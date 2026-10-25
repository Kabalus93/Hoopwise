import XCTest
@testable import Hoopwise

/// 25 October 2026: games and attendance taken during a class vanished. The
/// session page saves a whole `@State` copy, and a copy older than the store
/// erased what had been recorded since. These pin the guard and the way back.
@MainActor
final class SessionStaleSaveTests: XCTestCase {

    private func setUp(_ dm: SwiftDataManager) -> (session: SessionEvent, kid: UUID, other: UUID) {
        let program = Program(name: "Stale U10", ageGroup: .u10)
        dm.addProgram(program)
        let start = Date().addingTimeInterval(-1800)
        let s = dm.createSession(.init(group: .program(program.id), start: start, durationMinutes: 90)).session
        return (s, UUID(), UUID())
    }

    func testDetailsSaveFromAStaleCopyKeepsGamesAndMarks() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let (stale, kid, other) = setUp(dm)
        // Recorded during class, field by field, after the page took its copy.
        dm.setStudentAttendanceState(sessionId: stale.id, studentId: kid, state: .present)
        dm.setStudentAttendanceState(sessionId: stale.id, studentId: other, state: .excused)
        var game = SessionGame(sessionId: stale.id, gameNumber: 1, status: .inProgress)
        game.playerStats = [SessionPlayerStats(playerId: kid, gameId: game.id, teamId: game.id, points: 6)]
        dm.appendSessionGame(toSessionId: stale.id, game: game)

        // The page saves its old copy (a note edit) — as it does on many actions.
        var copy = stale
        copy.coachNotes = "Good defence today"
        dm.updateSessionEvent(copy, keepLiveFields: true)

        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == stale.id })
        XCTAssertEqual(stored.coachNotes, "Good defence today")
        XCTAssertEqual(stored.games.count, 1, "games erased by a stale save")
        XCTAssertEqual(stored.games.first?.playerStats.first?.points, 6)
        XCTAssertEqual(stored.actualAttendeeIds, [kid], "attendance erased by a stale save")
        XCTAssertEqual(stored.excusedAbsences, [other])
    }

    func testAnErasingOverwriteKeepsACopyThatRestores() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let (stale, kid, _) = setUp(dm)
        dm.setStudentAttendanceState(sessionId: stale.id, studentId: kid, state: .present)
        var game = SessionGame(sessionId: stale.id, gameNumber: 1, status: .inProgress)
        game.playerStats = [SessionPlayerStats(playerId: kid, gameId: game.id, teamId: game.id, points: 4)]
        dm.appendSessionGame(toSessionId: stale.id, game: game)

        // Any other whole-record writer with an old copy (no guard).
        dm.updateSessionEvent(stale)
        XCTAssertEqual(dm.sessionEvents.first { $0.id == stale.id }?.games.count, 0)

        let versions = dm.sessionRevisions(for: stale.id)
        let before = try XCTUnwrap(versions.first { $0.actor == "Before overwrite" })
        XCTAssertEqual(before.event.games.count, 1)
        XCTAssertEqual(before.event.actualAttendeeIds, [kid])

        XCTAssertTrue(dm.restoreSession(toRevisionId: before.id))
        let restored = try XCTUnwrap(dm.sessionEvents.first { $0.id == stale.id })
        XCTAssertEqual(restored.games.first?.playerStats.first?.points, 4)
        XCTAssertEqual(restored.actualAttendeeIds, [kid])
    }

    func testRestoreBringsBackUnexcusedAbsences() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let (s, kid, _) = setUp(dm)
        dm.setStudentAttendanceState(sessionId: s.id, studentId: kid, state: .absent)
        dm.setStudentAttendanceState(sessionId: s.id, studentId: kid, state: .unmarked)
        // The newest version is the one taken before "unmarked": kid absent.
        let v = try XCTUnwrap(dm.sessionRevisions(for: s.id).first)
        XCTAssertEqual(v.event.unexcusedAbsences, [kid])
        XCTAssertTrue(dm.restoreSession(toRevisionId: v.id))
        XCTAssertEqual(dm.sessionEvents.first { $0.id == s.id }?.unexcusedAbsences, [kid])
    }
}
