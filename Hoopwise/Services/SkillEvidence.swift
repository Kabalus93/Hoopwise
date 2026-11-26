import Foundation

// GAME EVIDENCE FOR THE EVALUATION (17 November 2026, Luther: "make sure the
// student oct evaluation, the session's oct planning balance, and the game
// stats can work together"). Games never SET a rating — they show beside the
// coach's slider, against the athlete's program-mates. Pure.
//
// Which stat speaks for which skill (only where one honestly does):
// · Shooting — points per game
// · Finishing — share of their baskets that came off a pass (basket log)
// · Passing — assists per game
// · Playmaking — assists per basket they score themselves
// · Defense — steals + blocks per game
// Ball handling, Game IQ and Footwork have no stat: they show nothing.
// Rebounds stay a stat; no octagon skill claims them.

enum SkillEvidence {
    /// Below this many games a player has no evidence.
    static let minimumGames = 3
    /// The basket log needs this many of their baskets to judge finishing.
    static let minimumLoggedBaskets = 5

    enum Measure: Equatable {
        case pointsPerGame, offPassShare, assistsPerGame, assistsPerOwnBasket, stocksPerGame
    }

    struct Line: Equatable {
        let axis: DrillAttribute
        let measure: Measure
        let value: Double
        /// 1 = best among program-mates with evidence; `of` = how many.
        let rank: Int
        let of: Int
    }

    private struct Numbers {
        var games = 0
        /// What is shown.
        var values: [DrillAttribute: Double] = [:]
        /// What is ranked, where it differs from what is shown: scoring is
        /// ranked on BASKETS a game (points ÷ that game's basket value), so a
        /// 3-point game does not out-rank a 1-point one, and shown in points.
        var ranked: [DrillAttribute: Double] = [:]
    }

    /// Everyone's numbers in ONE pass over the games and one over the basket
    /// log (it used to build a full report per peer, per peep).
    private static func numbers(for ids: Set<UUID>, sessions: [SessionEvent]) -> [UUID: Numbers] {
        struct Raw { var games = 0, points = 0, assists = 0, stocks = 0, baskets = 0.0 }
        var raw: [UUID: Raw] = [:]
        for session in sessions where !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                for (player, _) in game.participants where ids.contains(player) {
                    var r = raw[player] ?? Raw()
                    r.games += 1
                    if let line = game.stats(for: player) {
                        r.points += line.points
                        r.baskets += Double(line.points) / Double(max(1, game.basketValue))
                        r.assists += line.assists
                        r.stocks += line.steals + line.blocks
                    }
                    raw[player] = r
                }
            }
        }
        var logged: [UUID: (baskets: Int, assisted: Int, given: Int)] = [:]
        for basket in GameChemistry.baskets(in: sessions).baskets {
            if ids.contains(basket.scorerId) {
                logged[basket.scorerId, default: (0, 0, 0)].baskets += 1
                if basket.assisterId != nil { logged[basket.scorerId, default: (0, 0, 0)].assisted += 1 }
            }
            if let passer = basket.assisterId, ids.contains(passer) { logged[passer, default: (0, 0, 0)].given += 1 }
        }
        var out: [UUID: Numbers] = [:]
        for id in ids {
            let r = raw[id] ?? Raw()
            var n = Numbers(games: r.games)
            if r.games >= minimumGames {
                let games = Double(r.games)
                n.values[.shooting] = Double(r.points) / games
                n.ranked[.shooting] = r.baskets / games
                n.values[.passing] = Double(r.assists) / games
                n.values[.defense] = Double(r.stocks) / games
                if let log = logged[id], log.baskets >= minimumLoggedBaskets {
                    n.values[.finishing] = Double(log.assisted) / Double(log.baskets)
                    n.values[.playmaking] = Double(log.given) / Double(log.baskets)
                }
            }
            out[id] = n
        }
        return out
    }

    static func measure(for axis: DrillAttribute) -> Measure? {
        switch axis {
        case .shooting: .pointsPerGame
        case .finishing: .offPassShare
        case .passing: .assistsPerGame
        case .playmaking: .assistsPerOwnBasket
        case .defense: .stocksPerGame
        default: nil
        }
    }

    /// The athlete's evidence per skill, ranked against `peers` (their
    /// program-mates; the athlete is added if missing).
    static func lines(for id: UUID, peers: [UUID], sessions: [SessionEvent]) -> [DrillAttribute: Line] {
        var group = Set(peers)
        group.insert(id)
        let everyone = numbers(for: group, sessions: sessions)
        guard let mine = everyone[id], !mine.values.isEmpty else { return [:] }
        var out: [DrillAttribute: Line] = [:]
        for (axis, value) in mine.values {
            guard let measure = measure(for: axis) else { continue }
            let own = mine.ranked[axis] ?? value
            let others = everyone.values.compactMap { $0.values[axis] == nil ? nil : ($0.ranked[axis] ?? $0.values[axis]) }
            let rank = others.filter { $0 > own }.count + 1
            out[axis] = Line(axis: axis, measure: measure, value: value, rank: rank, of: others.count)
        }
        return out
    }

    /// "1.4 AST/game · 2nd of 12" (or Chinese).
    static func text(_ line: Line, chinese: Bool) -> String {
        let value: String
        switch line.measure {
        case .pointsPerGame: value = chinese ? "场均 \(fmt(line.value)) 分" : "\(fmt(line.value)) PTS/game"
        case .offPassShare: value = chinese ? "\(pct(line.value)) 进球来自传球" : "\(pct(line.value)) of baskets off a pass"
        case .assistsPerGame: value = chinese ? "场均 \(fmt(line.value)) 助攻" : "\(fmt(line.value)) AST/game"
        case .assistsPerOwnBasket: value = chinese ? "每进一球 \(fmt(line.value)) 次助攻" : "\(fmt(line.value)) assists per own basket"
        case .stocksPerGame: value = chinese ? "场均 \(fmt(line.value)) 抢断+盖帽" : "\(fmt(line.value)) STL+BLK/game"
        }
        guard line.of > 1 else { return value }
        let rank = chinese ? "组内第 \(line.rank)/\(line.of)" : "\(ordinal(line.rank)) of \(line.of)"
        return "\(value) · \(rank)"
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
