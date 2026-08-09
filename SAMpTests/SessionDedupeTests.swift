import XCTest
@testable import Hoopwise

/// Duplicate resolution must be provably lossless: a duplicate carrying a
/// roll call is somebody's attendance history, and attendance is money.
/// These tests pin the survivor priority, the carry-over, and — most
/// importantly — the cases the planner must REFUSE to resolve on its own.
@MainActor
final class SessionDedupeTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let studentA = UUID(uuidString: "5A000000-0000-0000-0000-0000000000AA")!
    private let studentB = UUID(uuidString: "5B000000-0000-0000-0000-0000000000BB")!
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(_ id: String,
                         created: TimeInterval = 0,
                         present: [UUID] = [],
                         excused: [UUID] = [],
                         absent: [UUID] = [],
                         notes: String? = nil,
                         photo: String? = nil,
                         rating: Int? = nil,
                         drills: [UUID] = []) -> SessionEvent {
        var event = SessionEvent(
            id: UUID(uuidString: id)!,
            programId: programId,
            title: "Advanced Technique · 1",
            date: when,
            startTime: when,
            endTime: when.addingTimeInterval(5400),
            actualAttendeeIds: present,
            excusedAbsences: excused,
            unexcusedAbsences: absent,
            attendancePhotoPath: photo,
            notes: notes,
            rating: rating,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000 + created))
        event.curriculum.warmupDrillIds = drills
        return event
    }

    private func plan(_ group: [SessionEvent], redeemed: Set<UUID> = []) -> DedupeDecision {
        let plan = SessionDedupe.plan(groups: [group], redeemedSessionIds: redeemed)
        return plan.decisions[0]
    }

    // MARK: - Survivor priority

    func testRedeemedSlotOutranksEverything() {
        // The record with the slot is thinner — it still wins, because
        // deleting it would refund the slot and move the client's balance.
        let thin = session("11111111-0000-0000-0000-000000000001", created: 100)
        let fat = session("22222222-0000-0000-0000-000000000002", created: 0,
                          present: [studentA, studentB], notes: "good session")

        let decision = plan([thin, fat], redeemed: [thin.id])

        XCTAssertEqual(decision.id, thin.id)
        XCTAssertTrue(decision.survivorReason.contains("redeemed bundle slot"))
        XCTAssertEqual(decision.deletedIds, [fat.id])
    }

    func testRollCallBeatsNotesAndAge() {
        let older = session("11111111-0000-0000-0000-000000000001", created: 0, notes: "just a note")
        let withRollCall = session("22222222-0000-0000-0000-000000000002", created: 500,
                                   present: [studentA])

        let decision = plan([older, withRollCall])

        XCTAssertEqual(decision.id, withRollCall.id)
        XCTAssertTrue(decision.survivorReason.contains("roll-call"))
    }

    func testNotesBeatAge() {
        let older = session("11111111-0000-0000-0000-000000000001", created: 0)
        let noted = session("22222222-0000-0000-0000-000000000002", created: 500, notes: "ran late")

        XCTAssertEqual(plan([older, noted]).id, noted.id)
    }

    func testTwoEmptyRecordsKeepTheElder() {
        let elder = session("22222222-0000-0000-0000-000000000002", created: 0)
        let younger = session("11111111-0000-0000-0000-000000000001", created: 900)

        let decision = plan([younger, elder])

        XCTAssertEqual(decision.id, elder.id)
        XCTAssertEqual(decision.outcome, .automatic, "Two empty records are safe to resolve automatically.")
        XCTAssertTrue(decision.survivorReason.contains("elder"))
    }

    // MARK: - Manual review

    func testTwoDataCarryingRecordsAreNeverAutoResolved() {
        let a = session("11111111-0000-0000-0000-000000000001", present: [studentA])
        let b = session("22222222-0000-0000-0000-000000000002", present: [studentB], notes: "second")

        let decision = plan([a, b])

        XCTAssertEqual(decision.outcome, .manualReview)
        XCTAssertTrue(decision.reviewReasons.contains { $0.contains("carry data") })
    }

    /// The merge cannot honestly decide who is right.
    func testContradictoryAttendanceIsFlagged() {
        let present = session("11111111-0000-0000-0000-000000000001", present: [studentA])
        let absent = session("22222222-0000-0000-0000-000000000002", absent: [studentA])

        let decision = plan([present, absent])

        XCTAssertEqual(decision.outcome, .manualReview)
        XCTAssertTrue(decision.reviewReasons.contains { $0.contains("present on one record and absent") })
    }

    /// Two redeemed slots for one real session means the client was charged
    /// twice — a human must decide, and neither record may be deleted blind.
    func testTwoRedeemedSlotsAreFlagged() {
        let a = session("11111111-0000-0000-0000-000000000001", present: [studentA])
        let b = session("22222222-0000-0000-0000-000000000002", present: [studentA])

        let decision = plan([a, b], redeemed: [a.id, b.id])

        XCTAssertEqual(decision.outcome, .manualReview)
        XCTAssertTrue(decision.reviewReasons.contains { $0.contains("also holds a redeemed bundle slot") })
    }

    // MARK: - Losslessness

    func testDeletionCarriesEverythingOntoTheSurvivor() {
        let survivorSide = session("11111111-0000-0000-0000-000000000001",
                                   present: [studentA], notes: "kept")
        let doomed = session("22222222-0000-0000-0000-000000000002",
                             excused: [studentB], notes: "carried",
                             photo: "photo.jpg", rating: 5,
                             drills: [UUID(uuidString: "D0000000-0000-0000-0000-00000000000D")!])

        let decision = plan([survivorSide, doomed])
        let survivor = decision.survivor

        XCTAssertTrue(survivor.actualAttendeeIds.contains(studentA))
        XCTAssertTrue(survivor.excusedAbsences.contains(studentB), "The deleted record's roll call must survive.")
        XCTAssertEqual(survivor.attendancePhotoPath, "photo.jpg")
        XCTAssertEqual(survivor.rating, 5)
        XCTAssertEqual(survivor.curriculum.totalDrillCount, 1)
        XCTAssertTrue(survivor.notes?.contains("kept") == true)
        XCTAssertTrue(survivor.notes?.contains("carried") == true, "Notes are joined, never replaced.")
        XCTAssertTrue(decision.carriedOver.joined().contains("attendance mark"))
    }

    func testSurvivorContentIsNeverOverwritten() {
        let survivorSide = session("11111111-0000-0000-0000-000000000001",
                                   present: [studentA], photo: "keep.jpg", rating: 3)
        let doomed = session("22222222-0000-0000-0000-000000000002",
                             present: [studentB], photo: "other.jpg", rating: 1)

        let survivor = plan([survivorSide, doomed]).survivor

        XCTAssertEqual(survivor.attendancePhotoPath, "keep.jpg")
        XCTAssertEqual(survivor.rating, 3)
    }

    func testAttendanceIsUnionedNotDuplicated() {
        let a = session("11111111-0000-0000-0000-000000000001", present: [studentA, studentB])
        let b = session("22222222-0000-0000-0000-000000000002", present: [studentA])

        let survivor = plan([a, b]).survivor

        XCTAssertEqual(survivor.actualAttendeeIds.count, 2, "A student marked on both records must appear once.")
    }

    // MARK: - The invariant

    /// Whatever the shape of the group, the planner must never propose
    /// deleting a record that holds a redeemed slot without flagging it.
    func testARedeemedRecordIsNeverSilentlyDeleted() {
        let combinations: [(Set<UUID>, [SessionEvent])] = {
            let a = session("11111111-0000-0000-0000-000000000001", present: [studentA])
            let b = session("22222222-0000-0000-0000-000000000002", notes: "x")
            let c = session("33333333-0000-0000-0000-000000000003")
            return [([a.id], [a, b, c]), ([b.id], [a, b, c]), ([c.id], [a, b, c])]
        }()

        for (redeemed, group) in combinations {
            let decision = plan(group, redeemed: redeemed)
            let deletedRedeemed = Set(decision.deletedIds).intersection(redeemed)
            XCTAssertTrue(deletedRedeemed.isEmpty || decision.outcome == .manualReview,
                          "A record holding a redeemed slot was proposed for deletion without review.")
        }
    }

    /// The Phase 0 amnesty stamped "Auto-closed: …" into 142 sessions' notes
    /// in one pass. That marker is machine bookkeeping — treating it as coach
    /// data made 11 of 12 real duplicate groups look like they held notes and
    /// forced them all to manual review.
    func testAutoCloseMarkerIsNotCoachData() {
        var stamped = session("11111111-0000-0000-0000-000000000001", created: 500)
        stamped.notes = SessionLifecycle.autoCloseMarkerPrefix + "2026-08-07 12:00"
        let elder = session("22222222-0000-0000-0000-000000000002", created: 0)

        let decision = plan([stamped, elder])

        XCTAssertEqual(decision.outcome, .automatic,
                       "Two auto-closed clones carry no coach data and are safe to resolve.")
        XCTAssertEqual(decision.id, elder.id, "With no real content, the elder survives.")
    }

    /// …but a real note alongside the marker still counts.
    func testRealNotesAlongsideTheMarkerStillCount() {
        var stamped = session("11111111-0000-0000-0000-000000000001", created: 500)
        stamped.notes = "ran late, short warm-up\n" + SessionLifecycle.autoCloseMarkerPrefix + "2026-08-07 12:00"
        let elder = session("22222222-0000-0000-0000-000000000002", created: 0)

        let decision = plan([stamped, elder])

        XCTAssertEqual(decision.id, stamped.id, "A record with a genuine note must win over the elder.")
        XCTAssertTrue(decision.survivorReason.contains("notes"))
    }

    /// On the live store every duplicate pair is a phase-titled record plus a
    /// program-titled one, so most merges rename what the coach sees. That is
    /// deterministic, not ambiguous — so it is reported, not escalated.
    func testDifferingTitlesAreReportedAsARename() {
        var phaseTitled = session("11111111-0000-0000-0000-000000000001", created: 500)
        phaseTitled.title = "Advanced Technique · 1"
        var programTitled = session("22222222-0000-0000-0000-000000000002", created: 0)
        programTitled.title = "Hezhuang court · U14"

        let decision = plan([phaseTitled, programTitled])

        XCTAssertEqual(decision.outcome, .automatic)
        XCTAssertTrue(decision.notices.contains { $0.contains("calendar rename") },
                      "A merge that changes the visible title must say so.")
        XCTAssertTrue(decision.notices.contains { $0.contains("Advanced Technique · 1") })
    }

    func testIdenticalTitlesProduceNoRenameNotice() {
        let a = session("11111111-0000-0000-0000-000000000001", created: 500)
        let b = session("22222222-0000-0000-0000-000000000002", created: 0)

        XCTAssertTrue(plan([a, b]).notices.isEmpty)
    }

    /// Only private bundles have prepaid slots. The live store has GROUP
    /// contracts (bundleSize 0, remaining n/a) carrying legacy entries in
    /// bundleSessionIds from the divergent redemption path that was removed;
    /// counting those made a duplicate pair look like a double charge when
    /// neither record holds a slot at all.
    func testOnlyPrivateBundlesCountAsRedeemed() {
        let sessionId = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
        let student = UUID()
        let groupContract = Contract(studentId: student, kind: .group,
                                     bundleSize: 0, bundleSessionIds: [sessionId])
        let bundle = Contract(studentId: student, kind: .privateBundle,
                              bundleSize: 10, bundleSessionIds: [sessionId])

        XCTAssertTrue(SessionDedupe.redeemedSessionIds(in: [groupContract]).isEmpty,
                      "A group contract has no prepaid slots to redeem.")
        XCTAssertEqual(SessionDedupe.redeemedSessionIds(in: [groupContract, bundle]), [sessionId])
    }

    /// …and the false positive must not reach the plan.
    func testGroupContractEntriesDoNotFabricateADoubleCharge() {
        let a = session("11111111-0000-0000-0000-000000000001", created: 500, present: [studentA])
        let b = session("22222222-0000-0000-0000-000000000002", created: 0, present: [studentA])
        let groupContract = Contract(studentId: studentA, kind: .group, bundleSize: 0,
                                     bundleSessionIds: [a.id, b.id])

        let decision = plan([a, b],
                            redeemed: SessionDedupe.redeemedSessionIds(in: [groupContract]))

        XCTAssertFalse(decision.reviewReasons.contains { $0.contains("redeemed bundle slot") },
                       "No slot exists on a group contract, so nothing may be reported as double-charged.")
        XCTAssertTrue(decision.survivorReason.contains("roll-call"),
                      "With no slots, the roll-call rung decides.")
    }

    func testEmptyAndSingletonGroupsProduceNoDecisions() {
        XCTAssertTrue(SessionDedupe.plan(groups: [], redeemedSessionIds: []).decisions.isEmpty)
        let single = [session("11111111-0000-0000-0000-000000000001")]
        XCTAssertTrue(SessionDedupe.plan(groups: [single], redeemedSessionIds: []).decisions.isEmpty)
    }

    // MARK: - Report

    func testReportNamesSurvivorDeletionAndCarryOver() {
        let a = session("11111111-0000-0000-0000-000000000001", present: [studentA])
        let b = session("22222222-0000-0000-0000-000000000002")
        let text = SessionDedupe.report(SessionDedupe.plan(groups: [[a, b]], redeemedSessionIds: []))

        XCTAssertTrue(text.contains("nothing was written"))
        XCTAssertTrue(text.contains("survivor"))
        XCTAssertTrue(text.contains("delete"))
    }
}
