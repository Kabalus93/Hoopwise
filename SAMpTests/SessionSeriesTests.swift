import XCTest
@testable import Hoopwise

/// Phase 2.2 retires the last two jobs `programId == nil` was doing: series
/// identity and Live Activity gating.
@MainActor
final class SessionSeriesTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let clientId = UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
    private let friday = Date(timeIntervalSince1970: 1_778_000_000)

    private func session(_ title: String, program: UUID? = nil, series: UUID? = nil,
                         offsetWeeks: Int = 0, location: String? = "酷迅",
                         attendees: [UUID] = []) -> SessionEvent {
        let date = friday.addingTimeInterval(TimeInterval(offsetWeeks * 7 * 86_400))
        return SessionEvent(programId: program, seriesId: series, title: title,
                            date: date, startTime: date,
                            endTime: date.addingTimeInterval(5400),
                            location: location, attendeeIds: attendees)
    }

    // MARK: - Series identity

    func testStampedSeriesIsFoundByIdNotByShape() {
        let seriesId = UUID()
        let one = session("Training", program: programId, series: seriesId, offsetWeeks: 0)
        // Same series, but the coach renamed it and moved the venue — the
        // fingerprint would have lost it.
        let two = session("Friday night", program: programId, series: seriesId,
                          offsetWeeks: 1, location: "Hezhuang court")
        let unrelated = session("Training", program: programId, series: UUID(), offsetWeeks: 2)

        let siblings = SessionSeries.siblings(of: one, in: [one, two, unrelated])

        XCTAssertEqual(Set(siblings.map(\.id)), Set([one.id, two.id]))
    }

    /// A stamped session must never be pulled into a legacy fingerprint group.
    func testStampedSessionIgnoresLookalikes() {
        let stamped = session("Training", series: UUID())
        let lookalike = session("Training", offsetWeeks: 1)

        XCTAssertEqual(SessionSeries.siblings(of: stamped, in: [stamped, lookalike]).count, 1)
    }

    /// Records generated before the field existed still resolve.
    func testUnstampedRecordsFallBackToTheFingerprint() {
        let one = session("Training", offsetWeeks: 0)
        let two = session("Training", offsetWeeks: 1)
        let differentSlot = session("Training", offsetWeeks: 1, location: "Hezhuang court")

        let siblings = SessionSeries.siblings(of: one, in: [one, two, differentSlot])

        XCTAssertEqual(Set(siblings.map(\.id)), Set([one.id, two.id]))
    }

    /// The fallback stays program-less: widening it would let it claim
    /// sessions that now belong to a real program after 2.1's adoption.
    func testFingerprintNeverClaimsProgramLinkedSessions() {
        let orphan = session("Training", offsetWeeks: 0)
        let adopted = session("Training", program: programId, offsetWeeks: 1)

        XCTAssertEqual(SessionSeries.siblings(of: orphan, in: [orphan, adopted]).count, 1)
    }

    // MARK: - Live Activity gating

    private func group() -> Program { Program(id: programId, name: "U10", ageGroup: .u10) }
    private func privateProgram() -> Program {
        Program(id: programId, name: "Private · Frank", programType: .privateSessions, ageGroup: .adult)
    }

    func testGroupProgramAlwaysRaisesALiveActivity() {
        XCTAssertTrue(SessionSeries.allowsLiveActivity(
            session("S", program: programId), programs: [group()], contracts: [],
            privateSessionsEnabled: false))
    }

    /// The old behaviour was accidental — private got none because it had no
    /// program. Now it is a preference, and off is the default.
    func testPrivateSessionIsOffByDefaultAndOnWhenEnabled() {
        let s = session("S", program: programId)
        XCTAssertFalse(SessionSeries.allowsLiveActivity(
            s, programs: [privateProgram()], contracts: [], privateSessionsEnabled: false))
        XCTAssertTrue(SessionSeries.allowsLiveActivity(
            s, programs: [privateProgram()], contracts: [], privateSessionsEnabled: true))
    }

    func testSessionWithNoProgramGetsNoLiveActivity() {
        XCTAssertFalse(SessionSeries.allowsLiveActivity(
            session("S"), programs: [group()], contracts: [], privateSessionsEnabled: true))
    }

    func testDanglingProgramPointerGetsNoLiveActivity() {
        XCTAssertFalse(SessionSeries.allowsLiveActivity(
            session("S", program: UUID()), programs: [group()], contracts: [],
            privateSessionsEnabled: true))
    }
}
