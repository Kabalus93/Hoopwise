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
}
