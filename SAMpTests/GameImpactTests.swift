import XCTest
@testable import Hoopwise

/// What the games' RESULTS say (GameImpact, 28 Nov 2026): impact ratings,
/// prediction, pairs, training transfer, rating v games, what to watch.
final class GameImpactTests: XCTestCase {

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    private let day0 = Date(timeIntervalSince1970: 1_780_000_000)

    /// A session with one two-team game: `a` beat `b` by the scores given.
    private func session(_ n: Int, a: [UUID], b: [UUID], score: (Int, Int), basketValue: Int = 2,
                         lines: [UUID: (points: Int, assists: Int, stocks: Int)] = [:],
                         baskets: [(scorer: UUID, passer: UUID?)] = [],
                         status: SessionEventStatus = .completed) -> SessionEvent {
        let start = day0.addingTimeInterval(Double(n) * 86_400)
        var s = SessionEvent(programId: id(900), title: "U10", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        var teamA = GameTeam(id: id(1000), name: "Black", colorHex: "#000000", playerIds: a)
        teamA.starters = a.count
        var teamB = GameTeam(id: id(1001), name: "White", colorHex: "#FFFFFF", playerIds: b)
        teamB.starters = b.count
        var game = SessionGame(sessionId: s.id, gameType: .twoTeam, teams: [teamA, teamB], status: .completed)
        game.activeTeamIds = [teamA.id, teamB.id]
        game.basketValue = basketValue
        game.teamScores = [teamA.id: score.0, teamB.id: score.1]
        for (player, line) in lines {
            let team = a.contains(player) ? teamA.id : teamB.id
            game.playerStats.append(SessionPlayerStats(playerId: player, gameId: game.id, teamId: team,
                                                       points: line.points, assists: line.assists, steals: line.stocks))
        }
        for basket in baskets {
            game.baskets.append(GameBasket(scorerId: basket.scorer, assisterId: basket.passer, points: basketValue,
                                           teamId: a.contains(basket.scorer) ? teamA.id : teamB.id))
        }
        s.games = [game]
        return s
    }

    func testMarginsAreInBasketsAndSkippedClassesAreLeftOut() {
        let a = [id(1), id(2)], b = [id(3), id(4)]
        let games = GameImpact.teamGames(in: [
            session(1, a: a, b: b, score: (12, 6), basketValue: 3),
            session(2, a: a, b: b, score: (10, 0), status: .skipped),
            session(3, a: a, b: b, score: (0, 0)),
        ])
        XCTAssertEqual(games.count, 1, "a skipped class and a 0–0 game say nothing")
        XCTAssertEqual(abs(games[0].margin), 2, accuracy: 0.001, "six points in a 3-point game = two baskets")
    }

    /// One player is on the winning side every game, with different mates.
    func testTheRatingFindsThePlayerWhoseTeamsWin() {
        let star = id(1)
        let others = (2...8).map(id)
        var sessions: [SessionEvent] = []
        for n in 0..<14 {
            // Rotate who plays with the star.
            let mates = [others[n % 7], others[(n + 2) % 7]]
            let rest = others.filter { !mates.contains($0) }.prefix(3)
            sessions.append(session(n, a: [star] + mates, b: Array(rest), score: (14, 8)))
        }
        let games = GameImpact.teamGames(in: sessions)
        XCTAssertEqual(games.count, 14)
        let ratings = GameImpact.ratings(games)
        let impact = GameImpact.impact(games, ratings: ratings)
        XCTAssertEqual(impact.first?.playerId, star, "the star is worth the most")
        XCTAssertEqual(impact.first?.wins, 14)
        XCTAssertEqual(impact.first?.margin ?? 0, 3, accuracy: 0.001)
        XCTAssertGreaterThan(ratings[star] ?? 0, others.compactMap { ratings[$0] }.max() ?? 0)
        // The same data gives the same ratings.
        XCTAssertEqual(ratings, GameImpact.ratings(games))

        // The star's side is favoured; without the star it is not.
        let favoured = GameImpact.predict(a: [star, others[0], others[1]], b: [others[2], others[3], others[4]],
                                          games: games, ratings: ratings)
        XCTAssertGreaterThan(favoured?.margin ?? 0, 0.5)
        XCTAssertEqual(favoured?.games, 14)
        // Too few games, or players the games do not know: no prediction.
        XCTAssertNil(GameImpact.predict(a: [star], b: [others[0]], games: Array(games.prefix(3)), ratings: ratings))
        XCTAssertNil(GameImpact.predict(a: [id(50), id(51)], b: [id(52), id(53)], games: games, ratings: ratings))
    }

    func testPairsNeedFourGamesTogether() {
        let p = (1...4).map(id)
        var sessions = (0..<4).map { session($0, a: [p[0], p[1]], b: [p[2], p[3]], score: (10, 4)) }
        var pairs = GameImpact.pairs(GameImpact.teamGames(in: sessions))
        XCTAssertEqual(pairs.count, 2)
        // Whichever side the ids sort onto, the winners are +3 and the others −3.
        let winners = try? XCTUnwrap(pairs.first { Set([$0.first, $0.second]) == Set([p[0], p[1]]) })
        XCTAssertEqual(winners?.margin ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(winners?.wins, 4)
        sessions.removeLast()
        pairs = GameImpact.pairs(GameImpact.teamGames(in: sessions))
        XCTAssertTrue(pairs.isEmpty, "three games together are not enough")
    }

    func testTransferComparesTheGameNumberBeforeAndSinceTheTraining() {
        let a = [id(1), id(2), id(3)], b = [id(4), id(5), id(6)]
        // Two early classes: no basket off a pass. Two recent: most are.
        func baskets(_ assisted: Int) -> [(scorer: UUID, passer: UUID?)] {
            (0..<10).map { i in (a[0], i < assisted ? a[1] : nil) }
        }
        let sessions = [
            session(1, a: a, b: b, score: (20, 10), baskets: baskets(1)),
            session(2, a: a, b: b, score: (20, 10), baskets: baskets(1)),
            session(3, a: a, b: b, score: (20, 10), baskets: baskets(6)),
            session(4, a: a, b: b, score: (20, 10), baskets: baskets(6)),
        ]
        // The two recent classes trained passing for most of their time.
        var trained: [UUID: [DrillAttribute: Double]] = [:]
        trained[sessions[2].id] = [.passing: 30, .ballHandling: 10]
        trained[sessions[3].id] = [.passing: 25, .ballHandling: 15]
        let transfer = GameImpact.transfer(sessions: sessions, trained: trained)
        let passing = transfer.first { $0.axis == .passing }
        XCTAssertEqual(passing?.metric, .offAPass)
        XCTAssertEqual(passing?.before ?? 0, 0.1, accuracy: 0.001)
        XCTAssertEqual(passing?.now ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(passing?.direction, 1)
        XCTAssertEqual(passing?.classes, 2)
        // Nothing trained, nothing claimed; three sessions with games are too few.
        XCTAssertTrue(GameImpact.transfer(sessions: sessions, trained: [:]).isEmpty)
        XCTAssertTrue(GameImpact.transfer(sessions: Array(sessions.prefix(3)), trained: trained).isEmpty)
    }

    func testRatingsAndGamesThatDisagreeAreNamed() {
        let p = (1...5).map(id)
        // p0 is rated the best shooter and scores the least; p4 the reverse.
        var ratings: [UUID: SkillsEvaluation] = [:]
        for (i, player) in p.enumerated() {
            var e = SkillsEvaluation()
            e.setRating(9 - i * 2, for: .shooting)
            ratings[player] = e
        }
        let sessions = (0..<3).map { n in
            session(n, a: [p[0], p[1], p[2]], b: [p[3], p[4]], score: (10, 10),
                    lines: Dictionary(uniqueKeysWithValues: p.enumerated().map { ($0.element, (points: $0.offset * 4, assists: 0, stocks: 0)) }))
        }
        let found = GameImpact.mismatches(sessions: sessions, ratings: ratings)
        let top = found.first { $0.playerId == p[0] }
        XCTAssertEqual(top?.axis, .shooting)
        XCTAssertEqual(top?.rank, 5)
        XCTAssertEqual(top?.of, 5)
        XCTAssertEqual(top?.playsAbove, false)
        XCTAssertEqual(found.first { $0.playerId == p[4] }?.playsAbove, true)
        XCTAssertLessThanOrEqual(found.count, 3)
        // Nobody rated: nothing to disagree with.
        XCTAssertTrue(GameImpact.mismatches(sessions: sessions, ratings: [:]).isEmpty)
    }

    func testDependenceAndQuietPlayers() {
        let p = (1...6).map(id)
        let sessions = (0..<4).map { n in
            session(n, a: [p[0], p[1], p[2]], b: [p[3], p[4], p[5]], score: (16, 6),
                    lines: [p[0]: (points: 14, assists: 0, stocks: 0), p[1]: (points: 2, assists: 1, stocks: 0),
                            p[3]: (points: 6, assists: 0, stocks: 1)])
        }
        let watch = GameImpact.watch(sessions: sessions)
        XCTAssertEqual(watch.dependence?.top, p[0])
        XCTAssertEqual(watch.dependence?.topShare ?? 0, 14.0 / 22.0, accuracy: 0.001)
        XCTAssertEqual(Set(watch.quiet), Set([p[2], p[4], p[5]]), "on the floor four games, never a stat")
        // Three games: too few to speak of dependence.
        XCTAssertNil(GameImpact.watch(sessions: Array(sessions.prefix(3))).dependence)
        // Two players: one of them making most of the baskets is not news.
        let duel = (0..<5).map { n in
            session(n, a: [p[0]], b: [p[1]], score: (16, 4),
                    lines: [p[0]: (points: 16, assists: 0, stocks: 0), p[1]: (points: 4, assists: 0, stocks: 0)])
        }
        XCTAssertNil(GameImpact.watch(sessions: duel).dependence)
    }

    func testResultsJoinTheTeamBalance() {
        // Eight players nobody has rated; the games say two of them carry
        // their teams. A balance on results splits them.
        let players = (1...8).map(id)
        let profiles = TeamBalance.profiles(players: players, evaluations: [:], tiers: [:], games: [:], shooting: [:])
        var results = Dictionary(uniqueKeysWithValues: players.map { ($0, 0.0) })
        results[players[0]] = 6; results[players[1]] = 6
        let teams = TeamBalance.balanced(players: players, teamCount: 2, profiles: profiles, results: results)
        XCTAssertNotEqual(teams[0].contains(players[0]), teams[0].contains(players[1]), "one carrier a team")
    }
}
