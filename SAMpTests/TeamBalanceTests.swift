import XCTest
@testable import Hoopwise

/// Create Game's "Balance teams" and the team octagons (TeamBalance, pure).
final class TeamBalanceTests: XCTestCase {

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    private func evaluation(_ ratings: [DrillAttribute: Int]) -> SkillsEvaluation {
        var e = SkillsEvaluation()
        for (axis, r) in ratings { e.setRating(r, for: axis) }
        return e
    }

    private func flat(_ r: Int) -> SkillsEvaluation {
        evaluation(Dictionary(uniqueKeysWithValues: DrillAttribute.allCases.map { ($0, r) }))
    }

    private func profiles(_ evaluations: [UUID: SkillsEvaluation], tiers: [UUID: SkillTier] = [:],
                          games: [UUID: TeamBalance.GameNumbers] = [:], shooting: [UUID: Double] = [:],
                          players: [UUID]) -> [UUID: TeamBalance.Profile] {
        TeamBalance.profiles(players: players, evaluations: evaluations, tiers: tiers, games: games, shooting: shooting)
    }

    func testAProfileIsTheRatingsAndAnUnratedPlayerIsTheMiddle() {
        let a = id(1), b = id(2)
        let p = profiles([a: flat(8)], players: [a, b])
        XCTAssertEqual(p[a]?.axes[.shooting] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(p[a]?.strength ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(p[a]?.known, true)
        XCTAssertEqual(p[b]?.axes.isEmpty, true)
        XCTAssertEqual(p[b]?.strength ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(p[b]?.known, false)
    }

    func testGamesAndShootingGiveEvidenceWhereNothingIsRated() {
        let a = id(1), b = id(2), c = id(3)
        let games: [UUID: TeamBalance.GameNumbers] = [
            a: .init(games: 4, points: 40, assists: 0, stocks: 8),
            b: .init(games: 4, points: 8, assists: 12, stocks: 0),
            c: .init(games: 2, points: 90, assists: 90, stocks: 90),   // too few games
        ]
        let p = profiles([:], games: games, shooting: [a: 0, b: 1], players: [a, b, c])
        // a scores more, b stands higher in the shooting tests: the two meet in the middle.
        XCTAssertEqual(p[a]?.axes[.shooting] ?? 0, 0.55, accuracy: 0.001)
        XCTAssertEqual(p[b]?.axes[.shooting] ?? 0, 0.55, accuracy: 0.001)
        XCTAssertEqual(p[a]?.axes[.defense] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(p[b]?.axes[.passing] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertNil(p[a]?.axes[.footwork])
        XCTAssertEqual(p[c]?.known, false)
    }

    func testARatingOutweighsEvidenceAndTheLevelOnlyStandsInForNoSkills() {
        let a = id(1), b = id(2)
        let games: [UUID: TeamBalance.GameNumbers] = [a: .init(games: 3, points: 30), b: .init(games: 3, points: 3)]
        let p = profiles([a: evaluation([.shooting: 4])], tiers: [a: .best], games: games, players: [a, b])
        // 70 % of 0.4 + 30 % of 0.8.
        XCTAssertEqual(p[a]?.axes[.shooting] ?? 0, 0.52, accuracy: 0.001)
        // Strength is the known skills; the level is built from the same
        // data and is not added on top.
        let skills = (p[a]?.axes.values.reduce(0, +) ?? 0) / Double(p[a]?.axes.count ?? 1)
        XCTAssertEqual(p[a]?.strength ?? 0, skills, accuracy: 0.001)
        // Nothing known but a level: the level stands in.
        let c = id(3)
        let alone = profiles([:], tiers: [c: .best], players: [c])
        XCTAssertEqual(alone[c]?.strength ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(alone[c]?.known, true)
    }

    func testATeamShapeAveragesOnlyWhoIsKnown() {
        let a = id(1), b = id(2), c = id(3)
        let p = profiles([a: flat(8), b: flat(4)], players: [a, b, c])
        let shape = TeamBalance.shape(of: [a, b, c], profiles: p)
        XCTAssertEqual(shape.axes[.defense] ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(shape.known, 2)
        XCTAssertEqual(shape.players, 3)
        XCTAssertEqual(shape.strength, (0.8 + 0.4 + 0.5) / 3 * 10, accuracy: 0.001)
        XCTAssertEqual(TeamBalance.shape(of: [c], profiles: p).axes[.defense], 0)
    }

    func testBalancingEvensOutStrength() {
        let players = (1...10).map(id)
        var evaluations: [UUID: SkillsEvaluation] = [:]
        for (i, p) in players.enumerated() { evaluations[p] = flat(i + 1) }   // 1…10
        let p = profiles(evaluations, players: players)
        let teams = TeamBalance.balanced(players: players, teamCount: 2, profiles: p)
        XCTAssertEqual(teams.map(\.count), [5, 5])
        XCTAssertEqual(Set(teams.flatMap { $0 }), Set(players))
        let strengths = teams.map { TeamBalance.shape(of: $0, profiles: p).strength }
        XCTAssertEqual(strengths[0], strengths[1], accuracy: 0.21)
        // The strongest of each team comes first — the starter slots.
        for team in teams {
            let s = team.map { p[$0]?.strength ?? 0 }
            XCTAssertEqual(s, s.sorted(by: >))
        }
        // The same data gives the same teams.
        XCTAssertEqual(teams, TeamBalance.balanced(players: players.reversed(), teamCount: 2, profiles: p))
    }

    func testBalancingSplitsTheShootersAndTheDefenders() {
        // Four of equal strength: two shooters, two defenders. A draft by
        // strength alone could put both shooters together.
        let shooters = [id(1), id(2)], defenders = [id(3), id(4)]
        var evaluations: [UUID: SkillsEvaluation] = [:]
        for s in shooters { evaluations[s] = evaluation([.shooting: 9, .defense: 3]) }
        for d in defenders { evaluations[d] = evaluation([.shooting: 3, .defense: 9]) }
        let players = shooters + defenders
        let p = profiles(evaluations, players: players)
        let teams = TeamBalance.balanced(players: players, teamCount: 2, profiles: p)
        for team in teams {
            XCTAssertEqual(team.filter(shooters.contains).count, 1)
            XCTAssertEqual(team.filter(defenders.contains).count, 1)
        }
        XCTAssertTrue(TeamBalance.gaps(teams.map { TeamBalance.shape(of: $0, profiles: p) }).isEmpty)
    }

    func testChemistryIsSharedOutWhenTheRestIsEqual() {
        // Four equal players; two pairs who find each other. Each team should
        // keep ONE pair rather than one team holding all the chemistry — or
        // none: what matters is that the teams are even.
        let players = (1...4).map(id)
        let p = profiles(Dictionary(uniqueKeysWithValues: players.map { ($0, flat(5)) }), players: players)
        let links: [TeamBalance.Pair: Int] = [.init(players[0], players[1]): 6, .init(players[2], players[3]): 6]
        let teams = TeamBalance.balanced(players: players, teamCount: 2, profiles: p, links: links)
        func inside(_ team: [UUID]) -> Int {
            links.filter { team.contains($0.key.a) && team.contains($0.key.b) }.values.reduce(0, +)
        }
        XCTAssertEqual(inside(teams[0]), inside(teams[1]))
    }

    func testThreeTeamsAndUnevenNumbers() {
        let players = (1...8).map(id)
        let p = profiles([:], players: players)
        let teams = TeamBalance.balanced(players: players, teamCount: 3, profiles: p)
        XCTAssertEqual(teams.map(\.count).sorted(), [2, 3, 3])
        XCTAssertEqual(Set(teams.flatMap { $0 }).count, 8)
    }

    func testGapsNameTheLeaderAndIgnoreAnUnratedTeam() {
        let a = id(1), b = id(2), c = id(3)
        let p = profiles([a: evaluation([.shooting: 9, .defense: 5]), b: evaluation([.shooting: 4, .defense: 5])],
                         players: [a, b, c])
        let gaps = TeamBalance.gaps([TeamBalance.shape(of: [a], profiles: p), TeamBalance.shape(of: [b], profiles: p)])
        XCTAssertEqual(gaps.map(\.axis), [.shooting])
        XCTAssertEqual(gaps.first?.leader, 0)
        XCTAssertEqual(gaps.first?.by ?? 0, 0.5, accuracy: 0.001)
        XCTAssertTrue(TeamBalance.gaps([TeamBalance.shape(of: [a], profiles: p),
                                        TeamBalance.shape(of: [c], profiles: p)]).isEmpty)
    }
}
