import XCTest
@testable import Hoopwise

/// Organization coaches on a scrimmage / game prep: kept in the curriculum
/// JSON, and their game lines never reach athlete stats.
final class SessionCoachesTests: XCTestCase {

    func testCoachIdsRoundTripAndOldPlansDecodeWithNone() throws {
        let coach = UUID()
        let plan = SessionCurriculum(coachIds: [coach])
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(back.coachIds, [coach])

        let old = #"{"warmupDrillIds":[],"skillDrillIds":[],"gameDrillIds":[],"warmupMinutes":30,"skillsMinutes":30,"gameMinutes":30}"#
        XCTAssertEqual(try JSONDecoder().decode(SessionCurriculum.self, from: Data(old.utf8)).coachIds, [])
    }

    func testOnlyScrimmageGamePrepAndTeamPracticeTakeCoaches() {
        XCTAssertEqual(SessionType.allCases.filter(\.takesCoachesAsPlayers), [.scrimmage, .gamePrep, .teamPractice])
    }

    func testACoachsLinesStayOutOfTheReport() {
        let kid = UUID(), coach = UUID()
        let team = GameTeam(name: "Blue", colorHex: "#007AFF", playerIds: [kid, coach])
        var game = SessionGame(sessionId: UUID(), teams: [team], status: .inProgress, startedAt: Date())
        game.addStat(.points(2), for: kid, teamId: team.id)
        game.addStat(.points(3), for: coach, teamId: team.id)
        game.addStat(.assist, for: coach, teamId: team.id)
        var session = SessionEvent(sessionType: .scrimmage, title: "Scrimmage", date: Date(),
                                   startTime: Date(), endTime: Date().addingTimeInterval(3600))
        session.games = [game]

        let report = GameStatsReport.make(sessions: [session], roster: [kid], current: session, excluding: [coach])
        XCTAssertEqual(report.leaders[.points]?.map(\.playerId), [kid])
        XCTAssertTrue((report.leaders[.assists] ?? []).isEmpty, "the coach's assist is not counted")
        XCTAssertEqual(report.average[.points], 2)
        XCTAssertFalse(report.playing.contains { $0.playerId == coach })
    }
}
