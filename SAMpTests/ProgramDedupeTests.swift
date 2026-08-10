import XCTest
@testable import Hoopwise

/// Phase 2.8. `dedupeProgramSessions` sits behind a coach-facing button
/// captioned "This can't be undone". It grouped by CALENDAR DAY ALONE and
/// deleted every session but the most populated one — while its own comment
/// claimed it spared "back-to-back morning/afternoon sessions on the same
/// day", which is exactly what grouping by day destroys.
///
/// Since Phase 0, deleting a session also refunds whatever it consumed, so one
/// press could remove a real session and silently move a client's balance.
@MainActor
final class ProgramDedupeTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var program: Program!

    /// 2026-05-08, a Friday.
    private let day = Date(timeIntervalSince1970: 1_778_198_400)

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
        program = Program(name: "Twice A Day", ageGroup: .u10)
        dm.addProgram(program)
    }

    private func addSession(hour: Int, title: String = "Training") {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        dm.createSession(SessionCreation.Intent(
            group: .program(program.id),
            start: start,
            durationMinutes: 90,
            title: title))
    }

    func testAMorningAndAnAfternoonSessionAreNotDuplicates() {
        addSession(hour: 9)
        addSession(hour: 18)

        XCTAssertEqual(dm.duplicateSessionGroups(forProgramId: program.id).count, 0,
                       "A program that trains twice on one day has two sessions.")

        let removed = dm.dedupeProgramSessions(forProgramId: program.id)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(dm.sessionEvents.count, 2,
                       "The old day-only rule deleted the afternoon session here.")
    }

    func testTwoSessionsAtTheSameTimeAreDuplicates() {
        addSession(hour: 18)
        addSession(hour: 18)

        XCTAssertEqual(dm.duplicateSessionGroups(forProgramId: program.id).count, 1)

        let removed = dm.dedupeProgramSessions(forProgramId: program.id)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(dm.sessionEvents.count, 1)
    }

    func testTheSurvivorAbsorbsWhatTheDeletedRecordHeld() {
        addSession(hour: 18)
        addSession(hour: 18)

        // Give one of them content worth keeping.
        var withNotes = dm.sessionEvents[0]
        withNotes.coachNotes = "Mason's left hand looked better"
        dm.updateSessionEvent(withNotes)

        dm.dedupeProgramSessions(forProgramId: program.id)

        XCTAssertEqual(dm.sessionEvents.count, 1)
        XCTAssertTrue(dm.sessionEvents.first?.coachNotes?.contains("left hand") ?? false,
                      "Merging, not blind deletion — the old version threw the loser away whole.")
    }

    func testSessionsOnDifferentDaysAreUntouched() {
        addSession(hour: 18)
        let nextWeek = day.addingTimeInterval(7 * 86_400)
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: nextWeek) ?? nextWeek
        dm.createSession(SessionCreation.Intent(group: .program(program.id),
                                                start: start, durationMinutes: 90))

        XCTAssertEqual(dm.dedupeProgramSessions(forProgramId: program.id), 0)
        XCTAssertEqual(dm.sessionEvents.count, 2)
    }
}
