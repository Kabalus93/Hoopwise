import XCTest
@testable import Hoopwise

/// The October 2026 plan engine: library-aware, level-aware, history-aware.
@MainActor
final class PlanGeneratorTests: XCTestCase {

    private let lib = ActivityLibrary.shared
    private lazy var drills = lib.plannable.map { ActivityLibrary.drill(for: $0) }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(daysAgo: Double = 0, phase: UUID? = nil, plan: SessionCurriculum? = nil,
                         program: UUID) -> SessionEvent {
        let start = t0.addingTimeInterval(-daysAgo * 86_400)
        var s = SessionEvent(programId: program, title: "Class", date: start, startTime: start,
                             endTime: start.addingTimeInterval(5400), status: .completed, attendeeIds: [])
        s.microCycleId = phase
        s.curriculum = plan ?? SessionCurriculum(warmupMinutes: 30, skillsMinutes: 30, gameMinutes: 30)
        return s
    }

    private func ctx(program: Program, history: [SessionEvent], session s: SessionEvent,
                     students: [Student] = [], players: [Player] = []) -> DrillPlanGenerator.Context {
        .init(session: s, program: program, phase: nil, enrolledStudents: students, players: players,
              allDrills: drills, programHistory: history)
    }

    /// Fixed "random" so runs are reproducible.
    private func seeded() -> () -> Double { var x = 0.137; return { x = (x * 9301 + 0.49297).truncatingRemainder(dividingBy: 1); return x } }

    func testLevelMovesTheAgeWindow() {
        XCTAssertEqual(Set(DrillPlanGenerator.ageWeights(age: .u8, level: 3).keys), [.u8, .u7])
        XCTAssertEqual(Set(DrillPlanGenerator.ageWeights(age: .u8, level: 5).keys), [.u10, .u8, .u12])
        XCTAssertEqual(Set(DrillPlanGenerator.ageWeights(age: .u8, level: 1).keys), [.u7, .u6, .u8])
        XCTAssertEqual(Set(DrillPlanGenerator.ageWeights(age: .u6, level: 1).keys), [.u6], "nothing below U6")
    }

    func testEvaluationsSuggestALevelOnlyWithHalfTheRosterRated() {
        let kids = (0..<4).map { _ in Student(name: "Kid") }
        var strong = Player(studentId: kids[0].id)
        strong.skills = SkillsEvaluation(scoring: 9, playmaking: 8, rebounding: 8, defense: 8, athleticism: 9, intangibles: 8)
        XCTAssertNil(DrillPlanGenerator.suggestedLevel(students: kids, players: [strong]), "1 of 4 rated is too few")
        var second = Player(studentId: kids[1].id)
        second.skills = strong.skills
        XCTAssertEqual(DrillPlanGenerator.suggestedLevel(students: kids, players: [strong, second])?.level, 5)
    }

    func testCoachLevelWinsOverEvaluations() {
        var program = Program(name: "U8", ageGroup: .u8)
        program.skillTargets = ProgramSkillTargets()
        program.skillTargets?.level = 4
        XCTAssertEqual(DrillPlanGenerator.resolveLevel(program: program, students: [], players: []).0, 4)
        XCTAssertFalse(program.skillTargets!.hasTargets, "a level alone is not a set of skill targets")
    }

    func testSlotsFollowTheLibraryBlocksAndNeverPlanRules() {
        let program = Program(name: "U8", ageGroup: .u8)
        let s = session(program: program.id)
        let result = DrillPlanGenerator.generatePlan(in: ctx(program: program, history: [], session: s), random: seeded())
        let c = result.curriculum
        XCTAssertFalse(c.skillDrillIds.isEmpty)
        func blocks(_ ids: [UUID]) -> Set<ActivityBlock> { Set(ids.compactMap { ActivityLibrary.activity(forDrillId: $0)?.block }) }
        XCTAssertTrue(blocks(c.warmupDrillIds).isSubset(of: [.routine, .smallGames]))
        XCTAssertEqual(blocks(c.skillDrillIds), [.compete])
        XCTAssertTrue(blocks(c.gameDrillIds).isSubset(of: [.game]))
        let all = c.warmupDrillIds + c.skillDrillIds + c.gameDrillIds
        XCTAssertFalse(all.contains { ActivityLibrary.activity(forDrillId: $0)?.isRule == true })
        XCTAssertTrue(all.allSatisfy { [.u8, .u7].contains(ActivityLibrary.activity(forDrillId: $0)!.age) })
        XCTAssertEqual(result.rationale.reviewCount, 0, "no history → everything is new")
    }

    func testHistoryDrivesReviewAndNeverRepeatsTheLastSession() {
        let program = Program(name: "U8", ageGroup: .u8)
        let phase = UUID()
        // Three earlier sessions in this phase, each with a generated plan.
        var history: [SessionEvent] = []
        for d in [21.0, 14.0, 7.0] {
            let earlier = session(daysAgo: d, phase: phase, program: program.id)
            let plan = DrillPlanGenerator.generatePlan(in: ctx(program: program, history: history, session: earlier),
                                                       random: seeded()).curriculum
            history.append(session(daysAgo: d, phase: phase, plan: plan, program: program.id))
        }
        let today = session(phase: phase, program: program.id)
        let result = DrillPlanGenerator.generatePlan(in: ctx(program: program, history: history, session: today),
                                                     random: seeded())
        let last = Set(history.last!.curriculum.skillDrillIds + history.last!.curriculum.warmupDrillIds
                       + history.last!.curriculum.gameDrillIds)
        let now = result.curriculum.warmupDrillIds + result.curriculum.skillDrillIds + result.curriculum.gameDrillIds
        XCTAssertTrue(Set(now).isDisjoint(with: last), "nothing from the last session repeats")
        XCTAssertGreaterThan(result.rationale.reviewCount, 0, "later in a phase, plans consolidate")
        XCTAssertGreaterThan(result.rationale.newCount, 0, "and still introduce something")
    }
}

/// Game stats feed the plan only with enough games to mean something.
final class PlanPerformanceSignalTests: XCTestCase {
    private func game(_ kid: UUID, points: Int, assists: Int) -> SessionGame {
        var g = SessionGame(sessionId: UUID())
        var s = SessionPlayerStats(playerId: kid, gameId: g.id, teamId: UUID())
        s.points = points; s.assists = assists
        g.playerStats = [s]
        return g
    }

    func testFewAssistsAcrossThreeGamesPushesPassing() {
        let kid = UUID()
        let games = (0..<3).map { _ in game(kid, points: 12, assists: 0) }
        XCTAssertNotNil(DrillPlanGenerator.passingSignal(games: games, roster: [kid]))
        XCTAssertNil(DrillPlanGenerator.passingSignal(games: Array(games.prefix(2)), roster: [kid]), "2 games is too few")
        let passers = (0..<3).map { _ in game(kid, points: 12, assists: 4) }
        XCTAssertNil(DrillPlanGenerator.passingSignal(games: passers, roster: [kid]))
    }
}
