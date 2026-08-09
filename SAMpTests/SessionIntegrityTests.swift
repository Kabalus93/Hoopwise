import XCTest
@testable import Hoopwise

/// The census must be exact before anyone repairs anything with it — a
/// miscount here becomes a migration that deletes or re-homes the wrong
/// records. Each category gets a fixture that contains exactly one instance
/// of the thing it detects and at least one near-miss it must ignore.
@MainActor
final class SessionIntegrityTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let otherProgramId = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
    private let phaseId = UUID(uuidString: "C0000000-0000-0000-0000-00000000000C")!

    private func program(_ id: UUID, name: String = "U8") -> Program {
        Program(id: id, name: name, ageGroup: .u8)
    }

    private func phase(_ id: UUID, program: UUID,
                       start: Date? = nil, end: Date? = nil) -> MicroCycle {
        var cycle = MicroCycle(id: id, programId: program, phaseNumber: 1, title: "Competition & Review")
        cycle.startDate = start
        cycle.endDate = end
        return cycle
    }

    private func session(program: UUID?, phase: UUID? = nil,
                         date: Date = Date(timeIntervalSince1970: 1_700_000_000),
                         title: String = "Session") -> SessionEvent {
        SessionEvent(microCycleId: phase,
                     programId: program,
                     title: title,
                     date: date,
                     startTime: date,
                     endTime: date.addingTimeInterval(5400))
    }

    // MARK: - A healthy store

    func testCleanStoreReportsNothingBroken() {
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId)],
            programs: [program(programId)],
            phases: [phase(phaseId, program: programId)])

        XCTAssertTrue(census.isClean)
        XCTAssertEqual(census.brokenCount, 0)
        XCTAssertEqual(census.totalSessions, 1)
    }

    // MARK: - Broken pointers

    func testDanglingProgramPointerIsCounted() {
        let census = SessionIntegrity.census(
            sessions: [session(program: programId),        // program deleted
                       session(program: otherProgramId)],  // program exists
            programs: [program(otherProgramId)],
            phases: [])

        XCTAssertEqual(census.sessionsWithDanglingProgram.count, 1)
        XCTAssertEqual(census.brokenCount, 1)
    }

    func testDanglingPhasePointerIsCounted() {
        // The exact result of iOS swipe-delete / the Mac context menu on a
        // phase: the sessions survive pointing at a row that is gone.
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId)],
            programs: [program(programId)],
            phases: [])

        XCTAssertEqual(census.sessionsWithDanglingPhase.count, 1)
        XCTAssertEqual(census.brokenCount, 1)
    }

    func testPhaseWithDeletedProgramIsCounted() {
        let census = SessionIntegrity.census(
            sessions: [],
            programs: [],
            phases: [phase(phaseId, program: programId)])

        XCTAssertEqual(census.phasesWithDanglingProgram.count, 1)
        XCTAssertEqual(census.brokenCount, 1)
    }

    /// The invariant nothing in the app validates.
    func testCrossProgramPhasePointerIsCounted() {
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId)],
            programs: [program(programId), program(otherProgramId, name: "U14")],
            phases: [phase(phaseId, program: otherProgramId)])

        XCTAssertEqual(census.sessionsWithCrossProgramPhase.count, 1)
        XCTAssertEqual(census.brokenCount, 1)
    }

    // MARK: - Inconsistent but not broken

    func testPhaseWithoutProgramIsInconsistentNotBroken() {
        let census = SessionIntegrity.census(
            sessions: [session(program: nil, phase: phaseId)],
            programs: [program(programId)],
            phases: [phase(phaseId, program: programId)])

        XCTAssertEqual(census.sessionsWithPhaseButNoProgram.count, 1)
        XCTAssertEqual(census.brokenCount, 0, "A phase-without-program session is inconsistent, not a dead pointer.")
    }

    func testSessionOutsideItsPhaseWindowIsAdvisory() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let insideWindow = phase(phaseId, program: programId,
                                 start: start, end: start.addingTimeInterval(86_400 * 14))

        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId,
                               date: start.addingTimeInterval(86_400 * 30)),   // outside
                       session(program: programId, phase: phaseId,
                               date: start.addingTimeInterval(86_400 * 3))],   // inside
            programs: [program(programId)],
            phases: [insideWindow])

        XCTAssertEqual(census.sessionsOutsideTheirPhaseWindow.count, 1)
        XCTAssertEqual(census.brokenCount, 0)
    }

    // MARK: - The phase-window rule (decided: calendar days, inclusive)

    /// Phase windows carry whatever clock time the phase was created at, so
    /// instant comparison flagged every edge-day session as misfiled. The
    /// rule is calendar days, inclusive of both edges.
    func testPhaseWindowIncludesBothEdgeDaysWhateverTheClock() {
        let start = date(2026, 5, 3, 13, 54)      // phase created at 13:54
        let end = date(2026, 5, 17, 13, 54)

        XCTAssertTrue(SessionIntegrity.phaseWindow(start: start, end: end,
                                                   contains: date(2026, 5, 3, 0, 0)),
                      "Midnight on the first day is inside the window.")
        XCTAssertTrue(SessionIntegrity.phaseWindow(start: start, end: end,
                                                   contains: date(2026, 5, 17, 18, 30)),
                      "The evening of the last day is inside the window.")
        XCTAssertFalse(SessionIntegrity.phaseWindow(start: start, end: end,
                                                    contains: date(2026, 5, 2, 23, 59)))
        XCTAssertFalse(SessionIntegrity.phaseWindow(start: start, end: end,
                                                    contains: date(2026, 5, 18, 0, 1)))
    }

    func testEdgeDaySessionsAreNoLongerReportedAsOutside() {
        let start = date(2026, 5, 3, 13, 54)
        let phaseWithWindow = phase(phaseId, program: programId,
                                    start: start, end: date(2026, 5, 17, 13, 54))
        let onFirstDay = session(program: programId, phase: phaseId, date: date(2026, 5, 3, 9, 0))

        let census = SessionIntegrity.census(sessions: [onFirstDay],
                                             programs: [program(programId)],
                                             phases: [phaseWithWindow])

        XCTAssertTrue(census.sessionsOutsideTheirPhaseWindow.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)!
    }

    /// A phase with no window cannot put anything outside it.
    func testPhaseWithoutDatesProducesNoWindowFindings() {
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId)],
            programs: [program(programId)],
            phases: [phase(phaseId, program: programId)])

        XCTAssertTrue(census.sessionsOutsideTheirPhaseWindow.isEmpty)
    }

    // MARK: - Legitimate today

    func testStandaloneSessionsAreCountedButNotBroken() {
        let census = SessionIntegrity.census(
            sessions: [session(program: nil), session(program: nil)],
            programs: [],
            phases: [])

        XCTAssertEqual(census.sessionsWithNoProgram.count, 2)
        XCTAssertEqual(census.brokenCount, 0,
                       "programId == nil is standalone today — the re-anchor decides its fate, the census does not.")
    }

    // MARK: - Advisory duplicates

    func testSameDayDuplicatesAreGroupedNotDoubleCounted() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, date: when),
                       session(program: programId, date: when),
                       session(program: programId, date: when),
                       session(program: programId, date: when.addingTimeInterval(86_400))],
            programs: [program(programId)],
            phases: [])

        XCTAssertEqual(census.sameDayDuplicateGroups.count, 1, "Three same-slot records are ONE group.")
        XCTAssertTrue(census.sameDayDuplicateGroups[0].detail.contains("3 records"))
        XCTAssertEqual(census.brokenCount, 0)
    }

    /// Two sessions on the same day at different times are a morning and an
    /// afternoon session, not duplicates — the existing dedupe helper gets
    /// this wrong by bucketing on start-of-day alone.
    func testSameDayDifferentTimesAreNotDuplicates() {
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, date: morning),
                       session(program: programId, date: morning.addingTimeInterval(6 * 3600))],
            programs: [program(programId)],
            phases: [])

        XCTAssertTrue(census.sameDayDuplicateGroups.isEmpty)
    }

    // MARK: - Report

    func testReportNamesEveryCategoryAndTheBrokenTotal() {
        let census = SessionIntegrity.census(
            sessions: [session(program: programId, phase: phaseId)],
            programs: [],
            phases: [])
        let text = SessionIntegrity.report(census)

        XCTAssertTrue(text.contains("BROKEN TOTAL: 2"), "One dead program pointer + one dead phase pointer.")
        XCTAssertTrue(text.contains("dangling programId"))
        XCTAssertTrue(text.contains("dangling microCycleId"))
    }
}
