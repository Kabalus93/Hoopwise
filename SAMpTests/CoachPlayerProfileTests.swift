import XCTest
@testable import Hoopwise

/// A coach as a player: position and tendencies ride in `specializations`
/// as tags without disturbing the coaching specialties, and their games are
/// read from the sessions they played in.
final class CoachPlayerProfileTests: XCTestCase {

    func testPositionAndTendenciesAreTaggedBesideSpecialties() {
        var coach = StaffCoach(name: "Luther", specializations: ["Shooting"])
        coach.playerPosition = .pointGuard
        coach.playerTendencies = [.highIQ, .shooter]
        XCTAssertEqual(coach.playerPosition, .pointGuard)
        XCTAssertEqual(coach.playerTendencies, [.shooter, .highIQ], "in a stable order")
        XCTAssertEqual(coach.coachingSpecializations, ["Shooting"])

        // Saving a profile's specialties keeps the player tags.
        coach.coachingSpecializations = ["Defense", "Footwork"]
        XCTAssertEqual(coach.coachingSpecializations, ["Defense", "Footwork"])
        XCTAssertEqual(coach.playerPosition, .pointGuard)
        XCTAssertEqual(coach.playerTendencies.count, 2)

        coach.playerPosition = nil
        coach.playerTendencies = []
        XCTAssertEqual(coach.specializations, ["Defense", "Footwork"])
    }

    func testACoachsGamesComeFromTheSessionsTheyPlayedIn() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let coach = StaffCoach(name: "Luther")
        let kid = UUID()
        let team = GameTeam(name: "Blue", colorHex: "#007AFF", playerIds: [kid, coach.id])
        var game = SessionGame(sessionId: UUID(), teams: [team], status: .inProgress, startedAt: Date())
        game.addStat(.points(3), for: coach.id, teamId: team.id)
        var session = SessionEvent(sessionType: .scrimmage, title: "Scrimmage", date: Date(),
                                   startTime: Date().addingTimeInterval(-7200), endTime: Date().addingTimeInterval(-3600))
        session.curriculum.coachIds = [coach.id]
        session.games = [game]
        dm.addSessionEvent(session)

        let played = dm.sessionsPlayed(byCoach: coach.id)
        XCTAssertEqual(played.map(\.id), [session.id])
        let report = GameStatsReport.player(coach.id, sessions: played)
        XCTAssertEqual(report.games, 1)
        XCTAssertEqual(report.totals[.points], 3)
        XCTAssertTrue(dm.sessionsPlayed(byCoach: UUID()).isEmpty)
        dm.deleteSessionEvent(session)
    }
}
