import XCTest
@testable import Hoopwise

/// Skill levels (Models/SkillTier.swift, 20 Nov 2026, Luther): the colour
/// behind a profile photo says where a child stands in the group they train
/// with — evaluation 65 %, games 35 %, measured from the group's average.
@MainActor
final class SkillLevelTests: XCTestCase {

    private func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    func testBandsAreDistancesFromTheGroupsAverage() {
        XCTAssertEqual(SkillLevel.tier(forDelta: 2), .best)
        XCTAssertEqual(SkillLevel.tier(forDelta: 1.5), .best)
        XCTAssertEqual(SkillLevel.tier(forDelta: 0.7), .better)
        XCTAssertEqual(SkillLevel.tier(forDelta: 0), .average)
        XCTAssertEqual(SkillLevel.tier(forDelta: -0.6), .belowAverage)
        XCTAssertEqual(SkillLevel.tier(forDelta: -1.5), .bottom)
    }

    func testTheFiveLevelColours() {
        XCTAssertEqual(SkillTier.best.hex, "#E5484D")
        XCTAssertEqual(SkillTier.better.hex, "#F0B429")
        XCTAssertEqual(SkillTier.average.hex, "#2FA58C")
        XCTAssertEqual(SkillTier.belowAverage.hex, "#3D9BE9")
        XCTAssertEqual(SkillTier.bottom.hex, "#8E7CE0")
        XCTAssertEqual(PhotoPalette.unranked, "#5B6577")
        XCTAssertEqual(Set(SkillTier.allCases.map(\.hex)).count, 5)
    }

    func testEvaluationsSpreadAcrossAllFive() {
        let k = ids(5)
        let tiers = SkillLevel.tiers(evaluation: [k[0]: 9, k[1]: 7, k[2]: 6, k[3]: 5, k[4]: 3], games: [:])
        XCTAssertEqual(tiers[k[0]], .best)          // +3 from the average of 6
        XCTAssertEqual(tiers[k[1]], .better)        // +1
        XCTAssertEqual(tiers[k[2]], .average)       // 0
        XCTAssertEqual(tiers[k[3]], .belowAverage)  // −1
        XCTAssertEqual(tiers[k[4]], .bottom)        // −3
    }

    func testALevelGroupIsAllAverageNobodyIsForcedToTheBottom() {
        let k = ids(6)
        let tiers = SkillLevel.tiers(evaluation: Dictionary(uniqueKeysWithValues: k.map { ($0, 6.0) }), games: [:])
        XCTAssertEqual(Set(tiers.values), [.average])
    }

    func testTooSmallAGroupRanksNobody() {
        let k = ids(2)
        XCTAssertTrue(SkillLevel.tiers(evaluation: [k[0]: 9, k[1]: 3], games: [:]).isEmpty)
    }

    func testGamesAloneGoByTheSizeOfTheGapNotTheRank() {
        // Three near-equal producers: nobody is the Best or the Bottom (a
        // rank used to hand out both, whatever the gap).
        let k = ids(3)
        let close = SkillLevel.tiers(evaluation: [:], games: [k[0]: 4.9, k[1]: 5.0, k[2]: 5.1])
        XCTAssertEqual(Set(close.values), [.average])
        // One far ahead of a level group is the Best; the group stays Average.
        let g = ids(8)
        var games = Dictionary(uniqueKeysWithValues: g.map { ($0, 8.0) })
        games[g[0]] = 30
        let tiers = SkillLevel.tiers(evaluation: [:], games: games)
        XCTAssertEqual(tiers[g[0]], .best)
        XCTAssertEqual(tiers[g[1]], .average)
    }

    func testAnUnratedProducerWeighsLikeARatedOne() {
        // Everyone is rated the same except u, who is not rated; u and r
        // produce the same, far above the rest. They get the same level.
        let k = ids(8)
        var evaluation = Dictionary(uniqueKeysWithValues: k.map { ($0, 6.0) })
        evaluation[k[0]] = nil
        var games = Dictionary(uniqueKeysWithValues: k.map { ($0, 8.0) })
        games[k[0]] = 30; games[k[1]] = 30
        let tiers = SkillLevel.tiers(evaluation: evaluation, games: games)
        XCTAssertEqual(tiers[k[0]], tiers[k[1]])
        XCTAssertEqual(tiers[k[1]], .better, "games are 35 % of the level")
    }

    func testBasketsCountNotPointsAndABreakKeepsTheLatestGames() {
        // The same five baskets in a 1-point and a 3-point game.
        let line = SessionPlayerStats(playerId: UUID(), gameId: UUID(), teamId: UUID(), points: 15)
        var one = line; one.points = 5
        XCTAssertEqual(SkillLevel.production(line, basketValue: 3), SkillLevel.production(one, basketValue: 1))
        // No game in the last six weeks: the latest games stand in.
        let k = ids(1)
        let program = UUID()
        let old = (1...4).map { session(program: program, daysAgo: 60 + $0, points: [k[0]: 10]) }
        let scores = SkillLevel.gameScores(members: Set(k), sessions: old, program: program, now: Date())
        XCTAssertEqual(scores[k[0]] ?? 0, 10, accuracy: 0.001)
        // Fewer than three games ever: still nothing.
        XCTAssertNil(SkillLevel.gameScores(members: Set(k), sessions: Array(old.prefix(2)), program: program, now: Date())[k[0]])
    }

    func testTheEvaluationWeighsSixtyFiveAndGamesThirtyFive() {
        // A: rated 1 point above the group's average (Better alone) but the
        // lowest producer in games (−2): 0.65 × 1 + 0.35 × −2 = −0.05 → Average.
        let a = UUID(), b = UUID(), c = UUID()
        let tiers = SkillLevel.tiers(evaluation: [a: 7, b: 6, c: 5], games: [a: 1, b: 5, c: 9])
        XCTAssertEqual(tiers[a], .average)
        // C: −1 rated, top in games: −0.65 + 0.7 = +0.05 → Average.
        XCTAssertEqual(tiers[c], .average)
    }

    func testOneEvaluatedChildHasNobodyToBeMeasuredAgainst() {
        // Only A is rated; games decide for everyone.
        let a = UUID(), b = UUID(), c = UUID()
        let tiers = SkillLevel.tiers(evaluation: [a: 10], games: [a: 5, b: 1, c: 9])
        XCTAssertEqual(tiers[a], .average, "middle in games; the lone 10 is not compared with anyone")
    }

    func testAnEvaluationNeedsFourRatedSkills() {
        var e = SkillsEvaluation()
        e.setRating(9, for: .shooting); e.setRating(9, for: .passing); e.setRating(9, for: .defense)
        XCTAssertNil(SkillLevel.evaluationScore(e))
        e.setRating(5, for: .gameIQ)
        XCTAssertEqual(SkillLevel.evaluationScore(e) ?? 0, 8, accuracy: 0.001)
    }

    // MARK: - Per program, from real records

    private func evaluation(_ value: Int) -> SkillsEvaluation {
        var e = SkillsEvaluation()
        for axis in DrillAttribute.allCases.prefix(4) { e.setRating(value, for: axis) }
        return e
    }

    private func session(program: UUID, daysAgo: Int, points: [UUID: Int]) -> SessionEvent {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        var s = SessionEvent(programId: program, title: "U10", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: .completed, attendeeIds: [])
        let team = UUID(), gameId = UUID()
        s.games = [SessionGame(sessionId: s.id, gameType: .twoTeam,
                               playerStats: points.map { SessionPlayerStats(playerId: $0.key, gameId: gameId, teamId: team,
                                                                            points: $0.value) },
                               status: .completed)]
        return s
    }

    func testAProgramRanksItsOwnAthletesFromItsOwnGames() {
        let k = ids(3)
        var program = Program(name: "U10", ageGroup: .u10)
        program.enrolledStudentIds = k
        // Three recent games: k0 scores most, k2 least. Games elsewhere don't count.
        let games = (1...3).map { session(program: program.id, daysAgo: $0, points: [k[0]: 12, k[1]: 6, k[2]: 0]) }
        let elsewhere = (1...3).map { session(program: UUID(), daysAgo: $0, points: [k[2]: 40]) }
        let old = (1...3).map { session(program: program.id, daysAgo: 90 + $0, points: [k[2]: 40]) }
        let tiers = SkillLevel.tiers(in: program, sessions: games + elsewhere + old, evaluations: [:])
        XCTAssertEqual(tiers[k[0]], .better)
        XCTAssertEqual(tiers[k[2]], .belowAverage, "games in another program, or older than six weeks, don't lift them")
    }

    func testTheMapUsesThePrimaryProgramAndSkipsPrivateClients() {
        let k = ids(3)
        var group = Program(name: "U10", ageGroup: .u10)
        group.enrolledStudentIds = k
        var other = Program(name: "U12", ageGroup: .u12)
        other.enrolledStudentIds = k
        var privately = Program(name: "Private", ageGroup: .u10)
        privately.programType = .privateSessions
        privately.enrolledStudentIds = k
        var students = k.map { Student(id: $0, name: "S") }
        students[0].programId = other.id
        // The evaluation belongs to the athlete, so k0 leads both groups.
        let evaluations = [k[0]: evaluation(9), k[1]: evaluation(6), k[2]: evaluation(3)]
        let map = SkillTierMap.build(students: students, programs: [group, other, privately],
                                     sessions: [], evaluations: evaluations)
        XCTAssertNil(map.byProgram[privately.id], "a private client has no group to stand in")
        XCTAssertEqual(map.tier(for: k[0], program: group.id), .best)
        XCTAssertEqual(map.tier(for: k[0], program: nil), map.tier(for: k[0], program: other.id),
                       "no program on screen: their primary program")
    }

    /// Bigger than the real store (20 Nov 2026: 17 programs, 171 athletes,
    /// 406 sessions): the rebuild runs on the main thread after data changes,
    /// so it must stay a few milliseconds.
    func testTheRebuildIsCheapAtFullSize() {
        var programs: [Program] = []
        var students: [Student] = []
        var sessions: [SessionEvent] = []
        var evaluations: [UUID: SkillsEvaluation] = [:]
        for p in 0..<20 {
            var program = Program(name: "P\(p)", ageGroup: .u10)
            let members = (0..<10).map { _ in Student(name: "S") }
            program.enrolledStudentIds = members.map(\.id)
            for m in members { evaluations[m.id] = evaluation(Int.random(in: 3...9)) }
            for day in 0..<30 {
                sessions.append(session(program: program.id, daysAgo: day * 2,
                                        points: Dictionary(uniqueKeysWithValues: members.map { ($0.id, Int.random(in: 0...12)) })))
            }
            programs.append(program); students += members
        }
        let start = Date()
        let map = SkillTierMap.build(students: students, programs: programs, sessions: sessions, evaluations: evaluations)
        let ms = Date().timeIntervalSince(start) * 1000
        print("skill level rebuild: \(Int(ms)) ms for 200 athletes, 600 sessions")
        XCTAssertEqual(map.primary.count, 200)
        XCTAssertLessThan(ms, 250, "keep the rebuild off the critical path")
    }
}
