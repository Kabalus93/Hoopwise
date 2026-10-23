import XCTest
@testable import Hoopwise

/// A cancelled class's plan moves to the next class, later plans move down,
/// the leftover is offered as a make-up, and reopening moves them back.
@MainActor
final class SessionPlanShiftTests: XCTestCase {

    private let phase = UUID()
    private let program = UUID()

    private func plan(_ n: Int) -> SessionCurriculum {
        SessionCurriculum(skillDrillIds: [UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!])
    }

    private func session(day: Int, plan n: Int, status: SessionEventStatus = .scheduled) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 18, minute: 30))!
        var s = SessionEvent(programId: program, title: "U8", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        s.microCycleId = phase
        s.curriculum = plan(n)
        return s
    }

    func testForwardMovesEveryLaterPlanDownOne() throws {
        let done = session(day: 1, plan: 0, status: .completed)
        let a = session(day: 8, plan: 1), b = session(day: 15, plan: 2), c = session(day: 22, plan: 3)
        let shift = try XCTUnwrap(SessionPlanShift.forward(cancelling: a, in: [done, a, b, c]))
        XCTAssertEqual(shift.updated.map(\.id), [b.id, c.id])
        XCTAssertEqual(shift.updated.map(\.curriculum), [plan(1), plan(2)])
        XCTAssertEqual(shift.overflow, plan(3))
    }

    func testOnlyScheduledLaterClassesMove() throws {
        let a = session(day: 8, plan: 1)
        let skipped = session(day: 15, plan: 2, status: .skipped)
        let earlier = session(day: 1, plan: 9)
        let shift = try XCTUnwrap(SessionPlanShift.forward(cancelling: a, in: [earlier, a, skipped]))
        XCTAssertTrue(shift.updated.isEmpty)
        XCTAssertEqual(shift.overflow, plan(1))
    }

    func testNoPlanNothingMoves() {
        var a = session(day: 8, plan: 1)
        a.curriculum = SessionCurriculum()
        XCTAssertNil(SessionPlanShift.forward(cancelling: a, in: [a, session(day: 15, plan: 2)]))
    }

    func testBackwardWithMakeUpRestoresExactly() throws {
        var a = session(day: 8, plan: 1), b = session(day: 15, plan: 1), c = session(day: 22, plan: 2)
        var makeUp = session(day: 29, plan: 3)
        makeUp.notes = SessionPlanShift.makeUpNote(for: a)
        a.notes = SessionPlanShift.addingMovedMarker(nil)
        let back = try XCTUnwrap(SessionPlanShift.backward(reopening: a, in: [a, b, c, makeUp]))
        XCTAssertEqual(back.updated.map(\.curriculum), [plan(2), plan(3)])
        XCTAssertEqual(back.makeUp?.id, makeUp.id)
        XCTAssertNil(back.needsPlan)
        _ = (b, c)
    }

    func testBackwardWithoutMakeUpAsksForAFreshLastPlan() throws {
        var a = session(day: 8, plan: 1)
        let b = session(day: 15, plan: 1), c = session(day: 22, plan: 2)
        a.notes = SessionPlanShift.addingMovedMarker("Skipped: Holiday")
        let back = try XCTUnwrap(SessionPlanShift.backward(reopening: a, in: [a, b, c]))
        XCTAssertEqual(back.updated.first?.curriculum, plan(2))
        XCTAssertEqual(back.needsPlan, c.id)
        XCTAssertEqual(back.updated.last?.curriculum.totalDrillCount, 0)
    }

    func testReopeningWithoutMarkerChangesNothing() {
        let a = session(day: 8, plan: 1)
        XCTAssertNil(SessionPlanShift.backward(reopening: a, in: [a, session(day: 15, plan: 2)]))
    }

    func testMarkerRoundTrip() {
        let marked = SessionPlanShift.addingMovedMarker("Skipped: Holiday")
        XCTAssertTrue(SessionPlanShift.hasMovedMarker(marked))
        XCTAssertEqual(SessionPlanShift.removingMovedMarker(marked), "Skipped: Holiday")
    }

    func testMakeUpFallsOnTheProgramsNextUsualDay() {
        let a = session(day: 7, plan: 1)   // Saturday 7 Nov 2026
        var p = Program(name: "U8", ageGroup: .u8)
        p.recurringDays = [.saturday]
        let after = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 28))!
        let start = SessionPlanShift.makeUpStart(for: a, program: p, after: after)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [12, 5, 18, 30])
    }

    /// Through the manager: cancel shifts and offers, accept adds the class,
    /// reopen pulls everything back and removes the untouched make-up.
    func testManagerCancelOfferAcceptReopen() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        var p = Program(name: "Shift U8", ageGroup: .u8)
        p.recurringDays = [.sunday]
        dm.addProgram(p)
        var cycle = MicroCycle(programId: p.id, phaseNumber: 1, title: "Phase 1")
        cycle.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1))
        cycle.endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 22))
        dm.addMicroCycle(cycle)
        var made: [UUID] = []
        for (i, day) in [8, 15, 22].enumerated() {
            let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 9))!
            var intent = SessionCreation.Intent(group: .program(p.id), start: start, durationMinutes: 60)
            intent.phase = cycle.id
            intent.curriculum = plan(i + 1)
            made.append(dm.createSession(intent).session.id)
        }
        func s(_ id: UUID) -> SessionEvent { dm.sessionEvents.first { $0.id == id }! }

        var first = s(made[0])
        XCTAssertTrue(SessionLifecycle.apply(.cancel, to: &first))
        dm.updateSessionEvent(first)
        XCTAssertEqual(s(made[1]).curriculum, plan(1))
        XCTAssertEqual(s(made[2]).curriculum, plan(2))
        XCTAssertTrue(SessionPlanShift.hasMovedMarker(s(made[0]).notes))
        let offer = try XCTUnwrap(dm.makeUpOffer)
        XCTAssertEqual(offer.curriculum, plan(3))

        dm.acceptMakeUp(offer)
        XCTAssertNil(dm.makeUpOffer)
        let makeUp = try XCTUnwrap(dm.sessionEvents.first { $0.notes?.contains(offer.note) == true })
        XCTAssertEqual(makeUp.curriculum, plan(3))
        XCTAssertEqual(makeUp.microCycleId, cycle.id)

        var reopened = s(made[0])
        XCTAssertTrue(SessionLifecycle.apply(.resetToScheduled, to: &reopened))
        dm.updateSessionEvent(reopened)
        XCTAssertEqual(s(made[1]).curriculum, plan(2))
        XCTAssertEqual(s(made[2]).curriculum, plan(3))
        XCTAssertFalse(SessionPlanShift.hasMovedMarker(s(made[0]).notes))
        XCTAssertNil(dm.sessionEvents.first { $0.id == makeUp.id }, "untouched make-up removed")
    }

    func testNumberingSkipsClassesThatDidNotHappen() {
        let p = Program(id: program, name: "U8", ageGroup: .u8)
        let cycle = MicroCycle(id: phase, programId: program, phaseNumber: 1, title: "Phase 1")
        let a = session(day: 8, plan: 1, status: .cancelled)
        let b = session(day: 15, plan: 2), c = session(day: 22, plan: 3)
        let name = SessionNaming.name(for: b, programs: [p], phases: [cycle],
                                      allSessions: [a, b, c], style: .planFirst)
        XCTAssertTrue(name.hasSuffix("1 of 2") || name.hasSuffix("1/2 次"), name)
    }
}
