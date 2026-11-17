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
        var values: [DrillAttribute: Double] = [:]
    }

    private static func numbers(for id: UUID, sessions: [SessionEvent]) -> Numbers {
        let report = GameStatsReport.player(id, sessions: sessions)
        var n = Numbers(games: report.games)
        guard report.games >= minimumGames else { return n }
        let games = Double(report.games)
        let points = Double(report.totals[.points] ?? 0)
        let assists = Double(report.totals[.assists] ?? 0)
        n.values[.shooting] = points / games
        n.values[.passing] = assists / games
        n.values[.defense] = Double((report.totals[.steals] ?? 0) + (report.totals[.blocks] ?? 0)) / games
        let chemistry = GameChemistry.player(id, sessions: sessions)
        if chemistry.baskets >= minimumLoggedBaskets {
            n.values[.finishing] = Double(chemistry.assisted) / Double(chemistry.baskets)
            n.values[.playmaking] = Double(chemistry.assistsGiven) / Double(chemistry.baskets)
        }
        return n
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
        let mine = numbers(for: id, sessions: sessions)
        guard !mine.values.isEmpty else { return [:] }
        var group = Set(peers)
        group.insert(id)
        let everyone = group.map { ($0, $0 == id ? mine : numbers(for: $0, sessions: sessions)) }
        var out: [DrillAttribute: Line] = [:]
        for (axis, value) in mine.values {
            guard let measure = measure(for: axis) else { continue }
            let others = everyone.compactMap { $0.1.values[axis] }
            let rank = others.filter { $0 > value }.count + 1
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
