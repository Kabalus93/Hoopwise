import XCTest
@testable import Hoopwise

/// The data-logic audit of 26 Nov 2026: one rule for "evaluated", unrated
/// skills stay unrated, program targets on the eight skills, and the plan
/// engine's signals counted like the stats pages.
final class DataLogicAuditTests: XCTestCase {

    // MARK: The evaluation

    func testAnEvaluationNeedsFourRatedSkillsToSpeakForTheAthlete() {
        var e = SkillsEvaluation()
        e.setRating(9, for: .shooting)
        XCTAssertNil(e.ratedAverage, "one rated skill is not an evaluation of the athlete")
        XCTAssertNil(SkillLevel.evaluationScore(e))
        XCTAssertTrue(AthleteFocus.suggested(e).isEmpty)
        for axis in [DrillAttribute.passing, .defense, .footwork] { e.setRating(5, for: axis) }
        XCTAssertEqual(e.ratedAverage ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(SkillLevel.evaluationScore(e), e.ratedAverage)
    }

    func testTheSweepClearsFivesThatWereNeverAnythingElse() {
        // Edit filled seven skills with 5; the coach rated shooting 9, then
        // moved passing to 6 in a later evaluation.
        var first = SkillsEvaluation()
        for axis in DrillAttribute.allCases { first.setRating(5, for: axis) }
        first.setRating(9, for: .shooting)
        first.recordEvaluation(replacing: SkillsEvaluation(), at: Date(timeIntervalSince1970: 1_000_000))
        var second = first
        second.setRating(6, for: .passing)
        second.recordEvaluation(replacing: first, at: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(second.history.count, 2)

        var swept = second
        XCTAssertTrue(swept.sweepUnsetRatings())
        XCTAssertEqual(swept.rating(.shooting), 9)
        XCTAssertEqual(swept.rating(.passing), 6, "it was a 5 once and then moved: the coach set it")
        XCTAssertNil(swept.rating(.defense), "a 5 in every evaluation was never set")
        XCTAssertEqual(Set(swept.axes.keys), ["shooting", "passing"])
        XCTAssertEqual(swept.history.first?.axes, ["shooting": 9, "passing": 5])
        XCTAssertEqual(swept.history.last?.axes, ["shooting": 9, "passing": 6])
        XCTAssertNil(swept.ratedAverage, "two skills are not enough")
        // Once only: a 5 the coach sets afterwards stays.
        swept.setRating(5, for: .defense)
        XCTAssertFalse(swept.sweepUnsetRatings())
        XCTAssertEqual(swept.rating(.defense), 5)
    }

    func testTheSweepSurvivesSavingAndAnAllFiveEvaluationIsEmptied() throws {
        var e = SkillsEvaluation()
        for axis in DrillAttribute.allCases { e.setRating(5, for: axis) }
        e.recordEvaluation(replacing: SkillsEvaluation())
        e.sweepUnsetRatings()
        XCTAssertFalse(e.isEvaluated)
        XCTAssertTrue(e.history.isEmpty)
        let back = try JSONDecoder().decode(SkillsEvaluation.self, from: JSONEncoder().encode(e))
        XCTAssertTrue(back.swept, "the mark is stored, so no device sweeps it again")
        // An evaluation from before the mark decodes as not swept.
        XCTAssertFalse(try JSONDecoder().decode(SkillsEvaluation.self, from: Data(#"{"scoring":5,"axes":{"shooting":5}}"#.utf8)).swept)
    }

    // MARK: Program targets on the eight skills

    func testTargetsCompareOnlyWhatIsRated() throws {
        var targets = ProgramSkillTargets(scoring: 9, playmaking: 9)   // the retired six say nothing
        XCTAssertFalse(targets.hasTargets)
        XCTAssertNil(targets.overallTarget)
        targets.setTarget(7, for: .shooting)
        targets.setTarget(6, for: .defense)
        XCTAssertTrue(targets.hasTargets)
        XCTAssertEqual(targets.overallTarget ?? 0, 6.5, accuracy: 0.001)

        var skills = SkillsEvaluation()
        XCTAssertEqual(targets.comparable(skills), 0, "nothing rated: unknown, not below")
        XCTAssertTrue(targets.below(skills).isEmpty)
        skills.setRating(5, for: .shooting)
        skills.setRating(2, for: .passing)   // no target on passing
        XCTAssertEqual(targets.below(skills), [.shooting])
        XCTAssertEqual(targets.comparable(skills), 1)

        // The plan's target reads them; a level-only blob still asks for nothing.
        XCTAssertEqual(PlanCoverage.target(phaseFocus: [], skillTargets: targets)?[.shooting], 1)
        XCTAssertNil(PlanCoverage.target(phaseFocus: [], skillTargets: ProgramSkillTargets()))
        // Round trip, and an old blob without the eight decodes with none.
        let back = try JSONDecoder().decode(ProgramSkillTargets.self, from: JSONEncoder().encode(targets))
        XCTAssertEqual(back.target(.shooting), 7)
        XCTAssertEqual(back.scoring, 9)
        XCTAssertFalse(try JSONDecoder().decode(ProgramSkillTargets.self,
                                                from: Data(#"{"scoring":8,"lastUpdatedDate":0}"#.utf8)).hasTargets)
    }

    // MARK: The engine's signals

    private func game(floor: [UUID], stocks: [UUID: Int]) -> SessionGame {
        var g = SessionGame(sessionId: UUID())
        var team = GameTeam(name: "Black", colorHex: "#000000", playerIds: floor)
        team.starters = floor.count
        g.teams = [team]
        g.activeTeamIds = [team.id]
        g.playerStats = stocks.map { SessionPlayerStats(playerId: $0.key, gameId: g.id, teamId: team.id, steals: $0.value) }
        g.status = .completed
        return g
    }

    func testTheDefenseSignalCountsEveryoneWhoPlayed() {
        // Ten on the floor, three games; only two of them ever get a steal.
        let roster = (0..<10).map { _ in UUID() }
        let games = (0..<3).map { _ in game(floor: roster, stocks: [roster[0]: 2, roster[1]: 1]) }
        // 9 steals over 30 player-games = 0.30: defence is asked for. Counting
        // stat lines alone it read 9 ÷ 6 = 1.5 and stayed silent.
        XCTAssertEqual(DrillPlanGenerator.defenseSignal(games: games, roster: Set(roster)), "stocks:0.30")
        // A game set up and never started is not a game.
        var unplayed = games; for i in unplayed.indices { unplayed[i].status = .setup }
        XCTAssertNil(DrillPlanGenerator.defenseSignal(games: unplayed, roster: Set(roster)))
    }

    func testTheShootingSignalJudgesEachTestAlone() {
        // Three athletes make 6 of 10 free throws; three others make 2 of 10
        // threes. Averaged together that is 40 % and nothing was said.
        let ft = (0..<3).map { _ in UUID() }, three = (0..<3).map { _ in UUID() }
        var freeThrows = ShootingRun(setup: ShootingSetup(drill: .freeThrows, mode: .attempts, shots: 10))
        for id in ft { freeThrows.set(6, for: id, spot: 0) }
        var threes = ShootingRun(setup: ShootingSetup(drill: .threes, mode: .attempts, shots: 10))
        for id in three { threes.set(2, for: id, spot: 0) }
        XCTAssertEqual(DrillPlanGenerator.shootingSignal(runs: [freeThrows, threes], roster: Set(ft + three)), "shooting:20%")
        XCTAssertNil(DrillPlanGenerator.shootingSignal(runs: [freeThrows], roster: Set(ft + three)))
    }

    // MARK: Stop collecting what nothing reads; the focus suggests

    func testOlderBuildsStillReadAGameWithoutFoulsOrBasketTimes() throws {
        var game = SessionGame(sessionId: UUID())
        game.playerStats = [SessionPlayerStats(playerId: UUID(), gameId: game.id, teamId: UUID(), points: 4)]
        game.baskets = [GameBasket(scorerId: UUID(), points: 2, teamId: UUID())]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        // A build from before required both keys: they are still written.
        let line = try XCTUnwrap((object["playerStats"] as? [[String: Any]])?.first)
        XCTAssertEqual(line["fouls"] as? Int, 0)
        let basket = try XCTUnwrap((object["baskets"] as? [[String: Any]])?.first)
        XCTAssertNotNil(basket["at"])
        // And a game an older build wrote (fouls, a real time) reads back.
        let back = try JSONDecoder().decode(SessionGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back.playerStats.first?.points, 4)
        XCTAssertEqual(back.baskets.count, 1)
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","playerId":"00000000-0000-0000-0000-000000000002","gameId":"00000000-0000-0000-0000-000000000003","teamId":"00000000-0000-0000-0000-000000000004","points":6,"rebounds":1,"assists":2,"steals":0,"blocks":0,"fouls":3}"#
        XCTAssertEqual(try JSONDecoder().decode(SessionPlayerStats.self, from: Data(old.utf8)).points, 6)
    }

    func testTheGroupsFocusIsWhatSeveralAthletesWorkOn() {
        func player(_ focus: [DrillAttribute]) -> Player {
            var p = Player(studentId: UUID())
            p.skills.focus = focus.map(\.rawValue)
            return p
        }
        let players = [player([.shooting, .defense]), player([.shooting]), player([.shooting, .passing]),
                       player([.defense]), player([]), player([.footwork])]
        let common = AthleteFocus.common(among: players.map(\.studentId), players: players)
        XCTAssertEqual(common.map(\.axis), [.shooting, .defense])
        XCTAssertEqual(common.map(\.athletes), [3, 2])
        // One athlete's focus is not the group's; nobody with a focus, nothing.
        XCTAssertTrue(AthleteFocus.common(among: [players[5].studentId, players[4].studentId], players: players).isEmpty)
    }

    // MARK: Shooting percentage and the common bench (28 Nov 2026)

    func testMissesMakeAShootingLineOnlyWhereTheyAreCounted() throws {
        let shooter = UUID(), team = UUID()
        var game = SessionGame(sessionId: UUID())
        game.basketValue = 2
        game.addStat(.points(2), for: shooter, teamId: team)
        game.addStat(.points(2), for: shooter, teamId: team)
        game.addStat(.miss, for: shooter, teamId: team)
        game.addStat(.miss, for: shooter, teamId: team)
        game.addStat(.miss, for: shooter, teamId: team)
        XCTAssertNil(game.shooting(for: shooter), "a game that only counts makes has no percentage")
        game.tracksShots = true
        let line = try XCTUnwrap(game.shooting(for: shooter))
        XCTAssertEqual(line.made, 2)
        XCTAssertEqual(line.attempts, 5)
        // A miss changes no other number.
        XCTAssertEqual(game.stats(for: shooter)?.points, 4)
        XCTAssertEqual(game.teamScores[team], 4)
        XCTAssertEqual(SkillLevel.production(try XCTUnwrap(game.stats(for: shooter))), 4, accuracy: 0.001)
        game.removeStat(.miss, for: shooter, teamId: team)
        XCTAssertEqual(game.shooting(for: shooter)?.attempts, 4)
        // Round trip; a game from before decodes without any of it.
        let back = try JSONDecoder().decode(SessionGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back.tracksShots, true)
        XCTAssertEqual(back.stats(for: shooter)?.misses, 2)
        var plain = SessionGame(sessionId: UUID())
        plain.addStat(.points(2), for: shooter, teamId: team)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        XCTAssertNil(object["tracksShots"])
        XCTAssertNil(object["commonBench"])
        XCTAssertNil(((object["playerStats"] as? [[String: Any]])?.first)?["misses"], "written only when there are misses")
    }

    func testAPlayerBackOnTheCommonBenchStillPlayedForTheirTeam() throws {
        let a = UUID(), b = UUID(), sub = UUID()
        var black = GameTeam(name: "Black", colorHex: "#000000", playerIds: [a])
        black.starters = 1
        var white = GameTeam(name: "White", colorHex: "#FFFFFF", playerIds: [b])
        white.starters = 1
        var game = SessionGame(sessionId: UUID(), gameType: .twoTeam, teams: [black, white], status: .inProgress)
        game.activeTeamIds = [black.id, white.id]
        game.commonBench = [sub]
        XCTAssertNil(game.participants[sub], "waiting on the bench is not playing")
        // sub comes on for a in Black; a goes to the common bench.
        game.teams[0].playerIds[0] = sub
        game.commonBench = [a]
        game.benchTeams = [a: black.id]
        game.subbedIds = [sub, a]
        XCTAssertEqual(game.participants[sub], black.id)
        XCTAssertEqual(game.participants[a], black.id, "he started for Black, though he is on no team's list now")
        let back = try JSONDecoder().decode(SessionGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back.commonBench, [a])
        XCTAssertEqual(back.participants[a], black.id)
    }

    func testShootingInGamesAddsUpOnlyGamesThatCountedMisses() {
        let shooter = UUID(), team = UUID()
        func session(_ day: Int, tracked: Bool, makes: Int, misses: Int) -> SessionEvent {
            let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400)
            var s = SessionEvent(programId: nil, title: "G", date: start, startTime: start,
                                 endTime: start.addingTimeInterval(3600), status: .completed, attendeeIds: [])
            var game = SessionGame(sessionId: s.id, status: .completed)
            if tracked { game.tracksShots = true }
            for _ in 0..<makes { game.addStat(.points(2), for: shooter, teamId: team) }
            for _ in 0..<misses { game.addStat(.miss, for: shooter, teamId: team) }
            s.games = [game]
            return s
        }
        let lines = GameStatsReport.shooting(sessions: [
            session(1, tracked: true, makes: 3, misses: 2),
            session(2, tracked: true, makes: 1, misses: 4),
            session(3, tracked: false, makes: 9, misses: 0),   // makes only: not a percentage
        ])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.made, 4)
        XCTAssertEqual(lines.first?.attempts, 10)
        XCTAssertEqual(lines.first?.games, 2)
        XCTAssertEqual(lines.first?.share ?? 0, 0.4, accuracy: 0.001)
        XCTAssertTrue(GameStatsReport.shooting(sessions: [session(3, tracked: false, makes: 9, misses: 0)]).isEmpty)
    }
}
