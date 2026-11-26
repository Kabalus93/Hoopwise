import XCTest
import SwiftData
@testable import Hoopwise

/// The evaluation, the plan balance and game stats working together (17 Nov
/// 2026, Luther), plus the board, languages by area and the plan fix.
@MainActor
final class SkillIntegrationTests: XCTestCase {

    // MARK: - The eight-skill evaluation

    func testAxesRoundTripAndOldEvaluationsReadAsUnrated() throws {
        var skills = SkillsEvaluation()
        XCTAssertFalse(skills.isEvaluated, "a fresh start: the old six fields do not count")
        skills.setRating(12, for: .shooting)
        skills.setRating(0, for: .defense)
        XCTAssertEqual(skills.rating(.shooting), 10, "clamped to 1–10")
        XCTAssertEqual(skills.rating(.defense), 1)
        let back = try JSONDecoder().decode(SkillsEvaluation.self, from: JSONEncoder().encode(skills))
        XCTAssertEqual(back.rating(.shooting), 10)
        XCTAssertNil(back.rating(.passing))
        XCTAssertEqual(back.axisAverage ?? 0, 5.5, accuracy: 0.001)

        let legacy = #"{"scoring":7,"playmaking":6,"rebounding":5,"defense":4,"athleticism":3,"intangibles":8}"#
        let old = try JSONDecoder().decode(SkillsEvaluation.self, from: Data(legacy.utf8))
        XCTAssertFalse(old.isEvaluated)
    }

    func testGroupRatingsAverageEachSkillOverThoseWhoRatedIt() {
        let a = Student(name: "A"), b = Student(name: "B")
        var sa = SkillsEvaluation(), sb = SkillsEvaluation()
        sa.setRating(4, for: .shooting); sa.setRating(8, for: .passing)
        sb.setRating(6, for: .shooting)
        let players = [Player(studentId: a.id, skills: sa), Player(studentId: b.id, skills: sb)]
        let group = DrillPlanGenerator.groupRatings(students: [a, b], players: players)
        XCTAssertEqual(group[.shooting] ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(group[.passing] ?? 0, 8, accuracy: 0.001, "only B left passing blank")
        XCTAssertNil(group[.defense])
    }

    // MARK: - Plan balance

    private func drill(_ scores: [DrillAttribute: Int]) -> DrillItem {
        var d = DrillItem(name: "D", category: .skills, difficulty: .beginner, durationMinutes: 10,
                          description: "", instructions: [], keyPoints: [], minPlayers: 1)
        d.tags = AttributeProfile(scores: scores).tags(byCoach: true)
        return d
    }

    func testTheHiddenGameBlockIsNotCounted() {
        let skills = drill([.passing: 3]), game = drill([.defense: 3])
        var plan = SessionCurriculum()
        plan.skillDrillIds = [skills.id]
        plan.skillsMinutes = 20
        plan.gameDrillIds = [game.id]
        plan.gameMinutes = 30
        let minutes = PlanCoverage.minutes(of: plan, drills: [skills, game])
        XCTAssertEqual(minutes[.defense] ?? 0, 0, "the Plan tab shows no Game section, so its drills don't weigh")
        XCTAssertLessThanOrEqual(minutes.values.max() ?? 0, 10, "no axis can exceed the visible minutes (the drill's own 10)")
    }

    /// The screenshot's case: blocks stored at 40 + 30 minutes, drills of
    /// 8 + 8 + 8 and 10 — the balance may not say more than 34 minutes.
    func testMinutesNeverExceedWhatThePlanShows() {
        let warm = (0..<3).map { _ in drill([.ballHandling: 3, .gameIQ: 2]) }.map { var d = $0; d.durationMinutes = 8; return d }
        var skill = drill([.ballHandling: 3, .passing: 3]); skill.durationMinutes = 10
        var plan = SessionCurriculum()
        plan.warmupDrillIds = warm.map(\.id); plan.warmupMinutes = 40
        plan.skillDrillIds = [skill.id]; plan.skillsMinutes = 30
        let minutes = PlanCoverage.minutes(of: plan, drills: warm + [skill])
        // 24 + 10 minutes on screen. Each drill's minutes are shared among
        // its skills: 3 × 8 × 3/5 + 10 × 3/6 = 19.4 of ball handling, and all
        // the skills together are exactly the 34 minutes the headers show.
        XCTAssertEqual(minutes[.ballHandling] ?? 0, 19.4, accuracy: 0.01)
        XCTAssertEqual(minutes.values.reduce(0, +), 34, accuracy: 0.01, "the skills add up to the plan")
    }

    func testTheGroupsWeakSkillsJoinTheTarget() {
        XCTAssertEqual(PlanCoverage.groupWeakness([.shooting: 4, .passing: 7]).keys.sorted { $0.rawValue < $1.rawValue }, [.shooting])
        let target = PlanCoverage.target(phaseFocus: [], skillTargets: nil, groupRatings: [.shooting: 3])
        XCTAssertGreaterThanOrEqual(target?[.shooting] ?? 0, 0.6, "a group average of 3 asks for shooting")
        XCTAssertNil(PlanCoverage.target(phaseFocus: [], skillTargets: nil, groupRatings: [.shooting: 8]),
                     "a strong group adds nothing")
    }

    // MARK: - Game evidence

    private func game(_ lines: [(UUID, Int, Int, Int)]) -> SessionGame {
        let id = UUID(), team = UUID()
        return SessionGame(sessionId: UUID(), gameType: .twoTeam,
                           playerStats: lines.map { SessionPlayerStats(playerId: $0.0, gameId: id, teamId: team,
                                                                       points: $0.1, rebounds: 0, assists: $0.2, steals: $0.3) },
                           basketValue: 2, status: .completed)
    }

    private func session(_ games: [SessionGame]) -> SessionEvent {
        var s = SessionEvent(programId: UUID(), title: "U10", date: Date(), startTime: Date(),
                             endTime: Date().addingTimeInterval(3600), status: .completed, attendeeIds: [])
        s.games = games
        return s
    }

    func testEvidenceNeedsThreeGamesAndRanksAgainstProgramMates() {
        let me = UUID(), mate = UUID()
        let two = [session([game([(me, 6, 1, 0), (mate, 2, 3, 1)]), game([(me, 6, 1, 0), (mate, 2, 3, 1)])])]
        XCTAssertTrue(SkillEvidence.lines(for: me, peers: [mate], sessions: two).isEmpty, "two games say nothing")

        let three = [session((0..<3).map { _ in game([(me, 6, 1, 0), (mate, 2, 3, 1)]) })]
        let lines = SkillEvidence.lines(for: me, peers: [mate], sessions: three)
        XCTAssertEqual(lines[.shooting]?.value ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(lines[.shooting]?.rank, 1)
        XCTAssertEqual(lines[.passing]?.rank, 2)
        XCTAssertEqual(lines[.passing]?.of, 2)
        XCTAssertNil(lines[.ballHandling], "no stat speaks for ball handling")
        XCTAssertNil(lines[.finishing], "no basket log, no finishing")
        XCTAssertEqual(SkillEvidence.text(lines[.passing]!, chinese: false), "1.0 AST/game · 2nd of 2")
    }

    func testFewStealsAndBlocksAskForDefence() {
        let roster = (0..<5).map { _ in UUID() }
        let quiet = (0..<3).map { _ in game(roster.map { ($0, 4, 1, 0) }) }
        XCTAssertNotNil(DrillPlanGenerator.defenseSignal(games: quiet, roster: Set(roster)))
        let busy = (0..<3).map { _ in game(roster.map { ($0, 4, 1, 1) }) }
        XCTAssertNil(DrillPlanGenerator.defenseSignal(games: busy, roster: Set(roster)))
        XCTAssertNil(DrillPlanGenerator.defenseSignal(games: Array(quiet.prefix(2)), roster: Set(roster)),
                     "under three games, nothing")
        XCTAssertEqual(DrillPlanGenerator.PlanRationale.readable("stocks:0.20", zh: false),
                       "few steals and blocks in games (0.20 per player-game)")
    }

    // MARK: - The card's second line

    func testTheCardCarriesTheEvaluationAndStillRenders() throws {
        let student = Student(name: "Maya")
        var skills = SkillsEvaluation()
        skills.setRating(8, for: .passing)
        let card = AthleteCardFacts.make(student: student, players: [Player(studentId: student.id, skills: skills)],
                                         programs: [], sessions: [], drills: [], categoryHex: "#007AFF",
                                         coach: "", academy: "", chinese: false)
        XCTAssertEqual(card.evaluation[.passing] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertNotNil(AthleteCardRenderer.image(AthleteCardBack(card: card), scale: 1))
    }

    // MARK: - Languages by area

    func testAreasFollowTheAppUnlessChosen() {
        let defaults = UserDefaults(suiteName: "AreaLanguageTests")!
        defaults.removePersistentDomain(forName: "AreaLanguageTests")
        defaults.set("en", forKey: "app_language")
        XCTAssertFalse(AreaLanguage.isChinese(.gameRecap, defaults: defaults))
        AreaLanguage.set(.chinese, for: .playerCard, defaults: defaults)
        XCTAssertTrue(AreaLanguage.isChinese(.playerCard, defaults: defaults))
        AreaLanguage.set(.english, for: .gameRecap, defaults: defaults)
        XCTAssertFalse(AreaLanguage.isChinese(.gameRecap, defaults: defaults))
        defaults.set("zh", forKey: "app_language")
        XCTAssertTrue(AreaLanguage.isChinese(.exports, defaults: defaults))
    }

    // MARK: - The coach board

    func testTheBoardKeepsItsDrawingUntilCleared() {
        CoachBoardStore.clear()
        XCTAssertNil(CoachBoardStore.load())
        var board = DrillDrawing.new(court: .full)
        XCTAssertTrue(CoachBoardStore.isBlank(board))
        board.steps[0].caption = "Press break"
        board.steps.append(DrillDrawing.Step(diagram: JournalPlayMath.defaultAlignment(.full)))
        XCTAssertFalse(CoachBoardStore.isBlank(board))
        CoachBoardStore.save(board)
        XCTAssertEqual(CoachBoardStore.load(), board, "found as it was left")
        CoachBoardStore.clear()
        XCTAssertNil(CoachBoardStore.load())
    }

    func testSaveAsPlayCopiesEveryStepWithoutCones() throws {
        let context = try JournalPlayTestStore.freshContext()
        var board = DrillDrawing.new(court: .half)
        board.steps[0].diagram.cones = [JournalCourtPoint(3, 3)]
        board.steps[0].caption = "Entry"
        board.steps.append(DrillDrawing.Step(diagram: JournalPlayMath.defaultAlignment(.half), caption: "Swing"))
        let play = JournalPlay.create(name: "Board play", category: .halfCourt, court: board.court, in: context)
        let concept = try XCTUnwrap(play.conceptPart)
        play.fill(concept, with: board, in: context)
        XCTAssertEqual(concept.sortedSteps.map(\.caption), ["Entry", "Swing"])
        XCTAssertTrue(concept.sortedSteps.allSatisfy { $0.diagram.cones.isEmpty }, "cones are a drill's")
    }
}
