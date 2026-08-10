import XCTest
@testable import Hoopwise

/// A session's phase comes from its date. The rules that matter are the ones
/// about NOT acting: an uncovered date keeps its existing link, and
/// overlapping windows never guess.
@MainActor
final class PhaseAssignmentTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let otherProgramId = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
    private let phaseA = UUID(uuidString: "C1000000-0000-0000-0000-00000000000C")!
    private let phaseB = UUID(uuidString: "C2000000-0000-0000-0000-00000000000C")!

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return Calendar.current.date(from: components)!
    }

    private func phase(_ id: UUID, program: UUID = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!,
                       number: Int, title: String,
                       start: Date?, end: Date?, weeks: Int = 2) -> MicroCycle {
        var cycle = MicroCycle(id: id, programId: program, phaseNumber: number,
                               title: title, durationWeeks: weeks)
        cycle.startDate = start
        cycle.endDate = end
        return cycle
    }

    private func session(phase: UUID?, program: UUID?, on date: Date) -> SessionEvent {
        SessionEvent(microCycleId: phase, programId: program, title: "S",
                     date: date, startTime: date, endTime: date.addingTimeInterval(5400))
    }

    // MARK: - Derivation

    func testSessionTakesThePhaseWhoseWindowContainsItsDate() {
        let one = phase(phaseA, number: 1, title: "Pre-Season",
                        start: date(2026, 5, 3), end: date(2026, 5, 17))
        let two = phase(phaseB, number: 2, title: "Build",
                        start: date(2026, 5, 18), end: date(2026, 5, 31))

        let outcome = PhaseAssignment.derive(
            session: session(phase: nil, program: programId, on: date(2026, 5, 20)),
            phases: [one, two])

        XCTAssertEqual(outcome, .assign(phaseId: phaseB))
    }

    /// Edge days count — the phase-window rule is inclusive.
    func testEdgeDayBelongsToThePhase() {
        let one = phase(phaseA, number: 1, title: "Pre-Season",
                        start: date(2026, 5, 3, 13), end: date(2026, 5, 17, 13))

        let outcome = PhaseAssignment.derive(
            session: session(phase: nil, program: programId, on: date(2026, 5, 3, 0)),
            phases: [one])

        XCTAssertEqual(outcome, .assign(phaseId: phaseA))
    }

    /// A plan that doesn't cover a date is a gap in the plan. Clearing the
    /// link would throw away what the merge just carried over.
    func testUncoveredDateKeepsItsExistingLink() {
        let one = phase(phaseA, number: 1, title: "Pre-Season",
                        start: date(2026, 5, 3), end: date(2026, 5, 17))

        let outcome = PhaseAssignment.derive(
            session: session(phase: phaseA, program: programId, on: date(2026, 9, 11)),
            phases: [one])

        XCTAssertEqual(outcome, .noWindow)

        let plan = PhaseAssignment.plan(
            sessions: [session(phase: phaseA, program: programId, on: date(2026, 9, 11))],
            phases: [one])
        XCTAssertEqual(plan.uncovered, 1)
        XCTAssertEqual(plan.changes.first?.to, "kept — no phase window covers this date")
    }

    /// The live store has overlapping Movement & Coordination windows.
    func testOverlappingWindowsKeepAValidCurrentLink() {
        let one = phase(phaseA, number: 1, title: "MC-1",
                        start: date(2026, 4, 30), end: date(2026, 5, 21))
        let two = phase(phaseB, number: 2, title: "MC-2",
                        start: date(2026, 5, 7), end: date(2026, 5, 28))

        let outcome = PhaseAssignment.derive(
            session: session(phase: phaseB, program: programId, on: date(2026, 5, 14)),
            phases: [one, two])

        XCTAssertEqual(outcome, .assign(phaseId: phaseB), "An existing valid link wins over a guess.")
    }

    func testOverlappingWindowsWithNoCurrentLinkAreAmbiguous() {
        let one = phase(phaseA, number: 1, title: "MC-1",
                        start: date(2026, 4, 30), end: date(2026, 5, 21))
        let two = phase(phaseB, number: 2, title: "MC-2",
                        start: date(2026, 5, 7), end: date(2026, 5, 28))

        let outcome = PhaseAssignment.derive(
            session: session(phase: nil, program: programId, on: date(2026, 5, 14)),
            phases: [one, two])

        guard case .ambiguous(let candidates) = outcome else {
            return XCTFail("Overlapping windows must not be resolved by guessing")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    /// Cross-program pointers become impossible: only the session's own
    /// program's phases are candidates.
    func testOnlyTheSessionsOwnProgramsPhasesAreCandidates() {
        let foreign = phase(phaseA, program: otherProgramId, number: 1, title: "Other",
                            start: date(2026, 5, 3), end: date(2026, 5, 17))

        let outcome = PhaseAssignment.derive(
            session: session(phase: nil, program: programId, on: date(2026, 5, 10)),
            phases: [foreign])

        XCTAssertEqual(outcome, .noWindow)
    }

    // MARK: - Reorder = re-window

    func testReorderRenumbersAndRewindowsWithoutMovingSessions() {
        let start = date(2026, 5, 4, 0)
        let one = phase(phaseA, number: 1, title: "A", start: nil, end: nil, weeks: 2)
        let two = phase(phaseB, number: 2, title: "B", start: nil, end: nil, weeks: 3)

        let reordered = PhaseAssignment.reordered([one, two], moving: phaseB, to: 0,
                                                  programStart: start)

        XCTAssertEqual(reordered.map(\.title), ["B", "A"])
        XCTAssertEqual(reordered.map(\.phaseNumber), [1, 2])
        // B is 3 weeks from the program start; A follows the day after.
        XCTAssertEqual(reordered[0].startDate, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(Calendar.current.dateComponents([.day],
                                                       from: reordered[0].startDate!,
                                                       to: reordered[0].endDate!).day, 20)
        XCTAssertEqual(Calendar.current.dateComponents([.day],
                                                       from: reordered[0].endDate!,
                                                       to: reordered[1].startDate!).day, 1)
    }

    /// The exact arithmetic behind the Elite U10 extension: pulling the start
    /// back a week and stretching Phase 1 from 2 weeks to 3 must leave
    /// Phase 2 starting on the day it already started.
    func testStretchingTheFirstPhaseAbsorbsAnEarlierStart() {
        let original = PhaseAssignment.rewindowed(
            [phase(phaseA, number: 1, title: "P1", start: nil, end: nil, weeks: 2),
             phase(phaseB, number: 2, title: "P2", start: nil, end: nil, weeks: 2)],
            programStart: date(2026, 5, 8, 0))

        let stretched = PhaseAssignment.rewindowed(
            [phase(phaseA, number: 1, title: "P1", start: nil, end: nil, weeks: 3),
             phase(phaseB, number: 2, title: "P2", start: nil, end: nil, weeks: 2)],
            programStart: date(2026, 5, 1, 0))

        XCTAssertEqual(stretched[0].startDate, Calendar.current.startOfDay(for: date(2026, 5, 1)))
        XCTAssertEqual(stretched[0].endDate, Calendar.current.startOfDay(for: date(2026, 5, 21)))
        XCTAssertEqual(stretched[1].startDate, original[1].startDate,
                       "Phase 2 must not move when Phase 1 absorbs the earlier start.")
    }

    /// Whole weeks cannot end exactly on 2026-09-11: 8 weeks from 07-17 ends
    /// 09-10 and would strand the final session by a single day.
    func testNineWeekBlockCoversTheFinalSeptemberSession() {
        let eight = PhaseAssignment.rewindowed(
            [phase(phaseA, number: 1, title: "Summer", start: nil, end: nil, weeks: 8)],
            programStart: date(2026, 7, 17, 0))
        let nine = PhaseAssignment.rewindowed(
            [phase(phaseA, number: 1, title: "Summer", start: nil, end: nil, weeks: 9)],
            programStart: date(2026, 7, 17, 0))

        let finalSession = session(phase: nil, program: programId, on: date(2026, 9, 11))
        XCTAssertEqual(PhaseAssignment.derive(session: finalSession, phases: eight), .noWindow)
        XCTAssertEqual(PhaseAssignment.derive(session: finalSession, phases: nine),
                       .assign(phaseId: phaseA))
    }

    /// Windows are contiguous and never overlap after a re-window, which is
    /// what makes derivation unambiguous going forward.
    func testRewindowedPlanHasNoOverlaps() {
        let start = date(2026, 5, 4, 0)
        let phases = (1...4).map { number in
            phase(UUID(), number: number, title: "P\(number)", start: nil, end: nil, weeks: number)
        }

        let rewindowed = PhaseAssignment.rewindowed(phases, programStart: start)

        for (earlier, later) in zip(rewindowed, rewindowed.dropFirst()) {
            XCTAssertLessThan(earlier.endDate!, later.startDate!,
                              "Contiguous windows must not overlap.")
        }
    }
}
