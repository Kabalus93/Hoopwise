import XCTest
@testable import Hoopwise

/// Game day (23 Nov 2026): a team's game is a session of type `.game` with a
/// plan in its curriculum; never billed; scored against the opponent.
@MainActor
final class GameDayTests: XCTestCase {

    func testThePlanRidesInTheCurriculumAndOlderPlansHaveNone() throws {
        var plan = GamePlan()
        plan.opponent = "Tigers"; plan.isHome = false
        plan.starters = [UUID(), UUID()]
        plan.keys = ["Box out", "  ", "Run"]
        plan.opponentNotes = "#7 shoots"
        var c = SessionCurriculum()
        c.teamId = UUID(); c.gamePlan = plan
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.gamePlan, plan)
        XCTAssertEqual(plan.cleanKeys, ["Box out", "Run"])
        XCTAssertEqual(plan.title(team: "Ballers", chinese: false), "Ballers @ Tigers")
        let old = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(SessionCurriculum()))
        XCTAssertNil(old.gamePlan)
        // A plan written by a build with fewer fields still reads.
        let partial = try JSONDecoder().decode(GamePlan.self, from: Data(#"{"opponent":"Lions"}"#.utf8))
        XCTAssertEqual(partial.opponent, "Lions"); XCTAssertTrue(partial.isHome); XCTAssertTrue(partial.starters.isEmpty)
        XCTAssertEqual(GamePlan().opponentName(chinese: false), "Opponent")
    }

    func testStartersLeadTheTeamAndTheOpponentHasNobody() {
        let a = UUID(), b = UUID(), c = UUID(), away = UUID()
        let team = Team(name: "Ballers", shortName: "BAL")
        var plan = GamePlan(); plan.opponent = "Tigers"; plan.starters = [c, away, a]
        let teams = GameDay.teams(team: team, plan: plan, pool: [a, b, c], chinese: false)
        XCTAssertEqual(teams[0].id, team.id)
        XCTAssertEqual(teams[0].playerIds, [c, a, b], "starters in the plan's order, the absent one out, then the bench")
        XCTAssertEqual(teams[0].starters, 2)
        XCTAssertEqual(teams[1].id, GamePlan.opponentTeamId)
        XCTAssertEqual(teams[1].name, "Tigers"); XCTAssertTrue(teams[1].playerIds.isEmpty)
        // No starters picked: up to five start.
        XCTAssertEqual(GameDay.teams(team: team, plan: GamePlan(), pool: [a, b, c], chinese: false)[0].starters, 3)
    }

    func testTheScoreAddsEveryPeriodPlayed() {
        let team = Team(name: "Ballers", shortName: "BAL")
        let kid = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = SessionEvent(programId: nil, title: "Ballers vs Tigers", date: start, startTime: start,
                                   endTime: start.addingTimeInterval(3600), status: .scheduled, attendeeIds: [kid])
        session.sessionType = .game
        session.curriculum.teamId = team.id
        XCTAssertNil(GameDay.score(of: session), "nothing played yet")
        func period(_ ours: Int, _ theirs: Int, _ status: SessionGameStatus) -> SessionGame {
            var g = SessionGame(sessionId: session.id, teams: GameDay.teams(team: team, plan: GamePlan(), pool: [kid], chinese: false),
                                status: status)
            g.teamScores[team.id] = ours; g.teamScores[GamePlan.opponentTeamId] = theirs
            return g
        }
        session.games = [period(0, 0, .ready)]
        XCTAssertNil(GameDay.score(of: session), "a period nobody played does not count")
        session.games = [period(12, 8, .completed), period(6, 9, .inProgress)]
        let running = GameDay.score(of: session)
        XCTAssertEqual(running?.ours, 18); XCTAssertEqual(running?.theirs, 17)
        XCTAssertEqual(running?.isFinal, false)
        XCTAssertEqual(running?.text(chinese: false), "18–17")
        session.games = [period(12, 8, .completed), period(6, 12, .completed)]
        XCTAssertEqual(GameDay.score(of: session)?.text(chinese: false), "L 18–20")
        session.games = [period(0, 4, .ready)]
        XCTAssertEqual(GameDay.score(of: session)?.theirs, 4, "scored before the clock ran")
    }

    func testAGameIsNeverBilledAndIsNotPrivate() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Game Day Kid")
        dm.addStudent(kid)
        dm.addContract(Contract(studentId: kid.id, contractNumber: 1, kind: .group, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        dm.addContract(Contract(studentId: kid.id, contractNumber: 2, kind: .privateBundle, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        var curriculum = SessionCurriculum()
        curriculum.teamId = UUID()
        var plan = GamePlan(); plan.opponent = "Tigers"; plan.starters = [kid.id]
        curriculum.gamePlan = plan
        dm.createSession(SessionCreation.Intent(group: .unassigned, sessionType: .game,
                                                start: Date(timeIntervalSince1970: 1_700_000_000),
                                                durationMinutes: 60, title: "Ballers vs Tigers",
                                                roster: [kid.id], curriculum: curriculum))
        let session = try XCTUnwrap(dm.sessionEvents.first { $0.sessionType == .game })
        XCTAssertEqual(session.curriculum.gamePlan?.starters, [kid.id], "the plan is stored")
        XCTAssertFalse(SessionPrivacy.isPrivate(session, programs: dm.programs, contracts: dm.contracts))
        dm.setStudentAttendanceState(sessionId: session.id, studentId: kid.id, state: .present)
        for contract in dm.allContracts(for: kid.id) {
            XCTAssertEqual(contract.bundleRedemptionsRemaining, 10, "contract #\(contract.contractNumber) was charged")
        }
        // A whole-session save keeps the plan.
        var copy = session; copy.notes = "Bring water"
        dm.updateSessionEvent(copy)
        XCTAssertEqual(dm.sessionEvents.first { $0.id == session.id }?.curriculum.gamePlan?.opponent, "Tigers")
        dm.deleteSessionEvent(session)
    }
}
