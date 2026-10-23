import Foundation

// MARK: - Game stats so far (October 2026, Luther)
//
// Everything the Games tab's stats sheet shows, computed once from the
// program's sessions: collective per-game averages, a per-session trend for
// each stat, the recent-vs-earlier direction, this session against the
// average, leaders and who has been playing. Pure — the view only draws it.
//
// A game COUNTS once it has been played: any status past setup with at least
// one stat line. Sessions that did not happen are left out (their games, if
// any, were never real). Baskets are points ÷ that game's basket value, so a
// 1-point drill and a 2-point scrimmage both read as baskets made.

enum GameStatsReport {

    enum Metric: String, CaseIterable, Identifiable {
        case points, rebounds, assists, steals, blocks, assistRate
        var id: String { rawValue }
    }

    struct SessionPoint: Identifiable, Equatable {
        var id: UUID { sessionId }
        let sessionId: UUID
        let date: Date
        let games: Int
        let values: [Metric: Double]
    }

    struct Leader: Identifiable, Equatable {
        var id: UUID { playerId }
        let playerId: UUID
        let total: Int
        let games: Int
        var perGame: Double { games > 0 ? Double(total) / Double(games) : 0 }
    }

    struct Report: Equatable {
        let games: Int
        let sessions: Int
        let firstDate: Date?
        /// Collective per-game averages (whole team on court, all players).
        let average: [Metric: Double]
        /// One point per session with games, oldest first.
        let trend: [SessionPoint]
        /// Recent sessions vs the ones before, as a fraction (+0.12 = 12 % up).
        /// nil when there are too few sessions to say.
        let direction: [Metric: Double]
        /// This session's per-game values, when it has played games.
        let thisSession: [Metric: Double]?
        /// Top players per counting stat, by total.
        let leaders: [Metric: [Leader]]
        /// Games played per rostered player (0 included), most first.
        let playing: [(playerId: UUID, games: Int)]

        static func == (a: Report, b: Report) -> Bool {
            a.games == b.games && a.sessions == b.sessions && a.average == b.average
                && a.trend == b.trend && a.direction == b.direction && a.thisSession == b.thisSession
                && a.leaders == b.leaders && a.playing.map(\.playerId) == b.playing.map(\.playerId)
                && a.playing.map(\.games) == b.playing.map(\.games)
        }
    }

    /// Sessions compared on each side of the trend direction.
    static let recentWindow = 3

    static func played(_ game: SessionGame) -> Bool {
        game.status != .setup && !game.playerStats.isEmpty
    }

    static func make(sessions: [SessionEvent], roster: [UUID], current: SessionEvent?) -> Report {
        let real = sessions
            .filter { !SessionLifecycle.didNotHappen($0) && $0.games.contains(where: played) }
            .sorted { $0.startTime < $1.startTime }
        let games = real.flatMap { $0.games.filter(played) }

        let trend = real.map { s in
            let g = s.games.filter(played)
            return SessionPoint(sessionId: s.id, date: s.startTime, games: g.count, values: perGame(g))
        }

        var direction: [Metric: Double] = [:]
        if trend.count >= recentWindow + 1 {
            let recent = trend.suffix(recentWindow)
            let earlier = trend.dropLast(recentWindow)
            for m in Metric.allCases {
                let r = weighted(recent, m), e = weighted(earlier, m)
                if e > 0 { direction[m] = (r - e) / e }
            }
        }

        let currentGames = current?.games.filter(played) ?? []
        let rosterSet = Set(roster)
        var gamesBy: [UUID: Int] = [:]
        var totals: [Metric: [UUID: Int]] = [:]
        for game in games {
            for p in Set(game.playerStats.map(\.playerId)) { gamesBy[p, default: 0] += 1 }
            for line in game.playerStats {
                totals[.points, default: [:]][line.playerId, default: 0] += line.points
                totals[.rebounds, default: [:]][line.playerId, default: 0] += line.rebounds
                totals[.assists, default: [:]][line.playerId, default: 0] += line.assists
                totals[.steals, default: [:]][line.playerId, default: 0] += line.steals
                totals[.blocks, default: [:]][line.playerId, default: 0] += line.blocks
            }
        }
        var leaders: [Metric: [Leader]] = [:]
        for (m, byPlayer) in totals {
            leaders[m] = byPlayer
                .filter { $0.value > 0 }
                .map { Leader(playerId: $0.key, total: $0.value, games: gamesBy[$0.key] ?? 0) }
                .sorted { $0.total != $1.total ? $0.total > $1.total : $0.perGame > $1.perGame }
                .prefix(3).map { $0 }
        }

        let everyone = rosterSet.union(gamesBy.keys)
        let playing = everyone.map { (playerId: $0, games: gamesBy[$0] ?? 0) }
            .sorted { $0.games != $1.games ? $0.games > $1.games : $0.playerId.uuidString < $1.playerId.uuidString }

        return Report(games: games.count, sessions: real.count, firstDate: real.first?.startTime,
                      average: perGame(games), trend: trend, direction: direction,
                      thisSession: currentGames.isEmpty ? nil : perGame(currentGames),
                      leaders: leaders, playing: playing)
    }

    /// Per-game collective values for a set of games.
    static func perGame(_ games: [SessionGame]) -> [Metric: Double] {
        guard !games.isEmpty else { return [:] }
        let n = Double(games.count)
        var pts = 0, reb = 0, ast = 0, stl = 0, blk = 0
        var baskets = 0.0
        for g in games {
            var gamePoints = 0
            for line in g.playerStats {
                gamePoints += line.points
                reb += line.rebounds; ast += line.assists; stl += line.steals; blk += line.blocks
            }
            pts += gamePoints
            baskets += Double(gamePoints) / Double(max(1, g.basketValue))
        }
        var out: [Metric: Double] = [
            .points: Double(pts) / n, .rebounds: Double(reb) / n, .assists: Double(ast) / n,
            .steals: Double(stl) / n, .blocks: Double(blk) / n,
        ]
        if baskets > 0 { out[.assistRate] = Double(ast) / baskets }
        return out
    }

    /// Average over sessions weighted by games played.
    private static func weighted<S: Sequence>(_ points: S, _ m: Metric) -> Double where S.Element == SessionPoint {
        var sum = 0.0, n = 0.0
        for p in points {
            guard let v = p.values[m] else { continue }
            sum += v * Double(p.games); n += Double(p.games)
        }
        return n > 0 ? sum / n : 0
    }

    // MARK: - One player (the athlete profile's Training Stats)

    /// A game the player has a stat line in.
    struct PlayerGame: Identifiable, Equatable {
        var id: UUID { game.id }
        let date: Date
        let sessionId: UUID
        let game: SessionGame
        let line: SessionPlayerStats
        /// true won, false lost, nil a draw or an every-player-for-themselves game.
        var won: Bool? {
            guard !game.gameType.isIndividual else { return nil }
            let mine = game.teamScores[line.teamId] ?? 0
            let best = game.teamScores.filter { $0.key != line.teamId }.values.max() ?? 0
            return mine == best ? nil : mine > best
        }

        static func == (a: PlayerGame, b: PlayerGame) -> Bool { a.game.id == b.game.id && a.line == b.line }
    }

    struct PlayerReport: Equatable {
        let games: Int
        let sessions: Int
        let totals: [Metric: Int]
        let average: [Metric: Double]
        /// Last 3 sessions vs the ones before, per game.
        let direction: [Metric: Double]
        /// Newest first.
        let recent: [PlayerGame]
        let record: (won: Int, lost: Int)

        static func == (a: PlayerReport, b: PlayerReport) -> Bool {
            a.games == b.games && a.totals == b.totals && a.direction == b.direction && a.recent == b.recent
        }
    }

    /// THE list of a player's games, oldest first: played games (same rule
    /// as the team report) in sessions that happened. Every per-player stat
    /// reads this, so the profile, the card and the grade cannot disagree.
    static func playerGames(_ playerId: UUID, in sessions: [SessionEvent],
                            in range: ClosedRange<Date>? = nil) -> [PlayerGame] {
        sessions
            .filter { !SessionLifecycle.didNotHappen($0) && (range?.contains($0.startTime) ?? true) }
            .sorted { $0.startTime < $1.startTime }
            .flatMap { s in
                s.games.filter(played).sorted { $0.gameNumber < $1.gameNumber }.compactMap { g in
                    g.stats(for: playerId).map { PlayerGame(date: s.startTime, sessionId: s.id, game: g, line: $0) }
                }
            }
    }

    static let countingMetrics: [Metric] = [.points, .rebounds, .assists, .steals, .blocks]

    static func player(_ playerId: UUID, sessions: [SessionEvent]) -> PlayerReport {
        let games = playerGames(playerId, in: sessions)
        func value(_ m: Metric, _ l: SessionPlayerStats) -> Int {
            switch m {
            case .points: return l.points
            case .rebounds: return l.rebounds
            case .assists: return l.assists
            case .steals: return l.steals
            case .blocks: return l.blocks
            case .assistRate: return 0
            }
        }
        var totals: [Metric: Int] = [:]
        for m in countingMetrics { totals[m] = games.reduce(0) { $0 + value(m, $1.line) } }
        let n = Double(max(1, games.count))
        var average: [Metric: Double] = [:]
        if !games.isEmpty { for m in countingMetrics { average[m] = Double(totals[m] ?? 0) / n } }

        // Direction by SESSION, like the team: a day of three games weighs as
        // three games, and the last three sessions face everything before.
        let bySession = Dictionary(grouping: games, by: \.sessionId)
        let order = games.map(\.sessionId).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
        var direction: [Metric: Double] = [:]
        if order.count >= recentWindow + 1 {
            let recentIds = Set(order.suffix(recentWindow))
            let recent = games.filter { recentIds.contains($0.sessionId) }
            let earlier = games.filter { !recentIds.contains($0.sessionId) }
            for m in countingMetrics {
                let r = Double(recent.reduce(0) { $0 + value(m, $1.line) }) / Double(max(1, recent.count))
                let e = Double(earlier.reduce(0) { $0 + value(m, $1.line) }) / Double(max(1, earlier.count))
                if e > 0 { direction[m] = (r - e) / e } else if r > 0 { direction[m] = 1 }
            }
        }
        let results = games.compactMap(\.won)
        return PlayerReport(games: games.count, sessions: bySession.count, totals: totals, average: average,
                            direction: direction, recent: Array(games.reversed().prefix(5)),
                            record: (results.filter { $0 }.count, results.filter { !$0 }.count))
    }
}

