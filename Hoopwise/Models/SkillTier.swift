import Foundation

// MARK: - Skill level colours (20 November 2026, Luther)
//
// "The background colour on students' profile pictures should represent their
// skill level compared to the group they train with." Five levels, coloured
// from the Photos app's petals. The words are for the COACH only — children
// and parents see a colour, never "bottom of the group". The colour is drawn
// LIVE behind a cut-out photo (transparent background), so it follows the
// child as evaluations and games come in, and follows whichever program is on
// screen. Shared cards and print sheets ask first (keep the level colour or
// pick one) — see AthleteCardShareSheet / CardBackdropChoice.
//
// THE SCORE, per program (the group the child trains with):
// · the coach's evaluation — the average of the rated octagon skills, at least
//   `minimumRatedSkills` of the eight — 65 %;
// · games — production per game in that program's games of the last
//   `gameWindowDays`, at least `minimumGames` — 35 %. Production is points +
//   rebounds + 1.5 × assists + 2 × (steals + blocks).
// Both are read RELATIVE to the group: the evaluation as points above or below
// the group's average rating; games as a percentile among program-mates with
// enough games, mapped to −2…+2 points. One input alone decides alone; none
// leaves the child unranked (a neutral grey). A group needs at least
// `minimumGroup` ranked children, or nobody is ranked in it — a private client
// (a group of one) has no level.
//
// Bands are distances from the group's average, NOT quartiles, so a level
// group can be all green and nobody is forced to the bottom.

enum SkillTier: Int, CaseIterable, Codable, Sendable {
    /// Clearly above the group — could move up.
    case best
    /// Better than the rest at this level.
    case better
    /// At the group's level.
    case average
    /// A little behind.
    case belowAverage
    /// Well behind — a candidate to move down.
    case bottom

    /// The petal it is coloured with (Photos logo).
    var hex: String {
        switch self {
        // Luther's own five (26 Nov 2026), in place of the Photos petals.
        case .best: "#E5484D"          // red
        case .better: "#F0B429"        // amber
        case .average: "#2FA58C"       // teal
        case .belowAverage: "#3D9BE9"  // blue
        case .bottom: "#8E7CE0"        // purple
        }
    }

    /// Coach-facing name. Never printed on anything a child or parent sees.
    func title(chinese: Bool) -> String {
        switch self {
        case .best: chinese ? "最佳" : "Best"
        case .better: chinese ? "较好" : "Better"
        case .average: chinese ? "平均" : "Average"
        case .belowAverage: chinese ? "低于平均" : "Below average"
        case .bottom: chinese ? "组内末位" : "Bottom of the group"
        }
    }

    /// Coach-facing meaning.
    func meaning(chinese: Bool) -> String {
        switch self {
        case .best: chinese ? "可以升到更高的组" : "Could move up"
        case .better: chinese ? "在同级别中领先" : "Better than the rest at this level"
        case .average: chinese ? "与本组水平相当" : "At the group's level"
        case .belowAverage: chinese ? "稍落后于本组" : "A little behind the group"
        case .bottom: chinese ? "可考虑降到较低的组" : "Candidate to move down"
        }
    }
}

/// The Photos app's petals, sampled from its logo — the app's photo palette:
/// the level colours, and the swatches when a colour is picked by hand.
enum PhotoPalette {
    static let red = "#FF4D5F"
    static let orange = "#FF7F00"
    static let yellow = "#FFC700"
    static let green = "#77D700"
    static let teal = "#00D97A"
    static let blue = "#00ACF9"
    static let purple = "#A28AE7"
    static let pink = "#FF5CAF"
    /// Around the flower, in the logo's order.
    static let all = [red, orange, yellow, green, teal, blue, purple, pink]
    /// Behind a cut-out photo with no level (not enough to compare yet).
    static let unranked = "#5B6577"   // slate (Luther, 26 Nov 2026; was a light grey)
}

enum SkillLevel {
    static let evaluationWeight = 0.65
    static let gameWeight = 0.35
    static let minimumRatedSkills = 4
    static let minimumGames = 3
    static let gameWindowDays = 42
    static let minimumGroup = 3

    /// The band for a distance from the group's average (in rating points).
    static func tier(forDelta delta: Double) -> SkillTier {
        // Symmetric: 1.5 above is Best, 1.5 below is Bottom; Average is the
        // open band around the average.
        if delta >= 1.5 { return .best }
        if delta >= 0.5 { return .better }
        if delta > -0.5 { return .average }
        if delta > -1.5 { return .belowAverage }
        return .bottom
    }

    /// Production in a game: baskets (as two-pointers, whatever that game's
    /// baskets were worth) + rebounds + 1.5 × assists + 2 × stocks. Raw
    /// points made a 3-point game count three times a 1-point game.
    static func production(_ line: SessionPlayerStats, basketValue: Int = 2) -> Double {
        let baskets = Double(line.points) / Double(max(1, basketValue))
        return baskets * 2 + Double(line.rebounds) + 1.5 * Double(line.assists) + 2 * Double(line.steals + line.blocks)
    }

    /// The evaluation's score: the average of the rated skills, when enough
    /// are rated (`SkillsEvaluation.ratedAverage` — the one rule).
    static func evaluationScore(_ evaluation: SkillsEvaluation?) -> Double? {
        evaluation?.ratedAverage
    }

    /// When the window holds too few games (a holiday), the athlete's latest
    /// games stand in — at most this many.
    static let fallbackGames = 6

    /// Production per game for every member, in ONE pass over the program's
    /// games (the same games GameStatsReport.playerGames counts: played, in
    /// sessions that happened, everyone who took part). The games of the last
    /// `gameWindowDays`; after a break with fewer than `minimumGames` there,
    /// the latest `fallbackGames` instead, so a level does not lose its game
    /// half on the first day back.
    static func gameScores(members: Set<UUID>, sessions: [SessionEvent], program: UUID, now: Date) -> [UUID: Double] {
        let start = Calendar.current.date(byAdding: .day, value: -gameWindowDays, to: now) ?? now
        var games: [UUID: [(date: Date, value: Double)]] = [:]
        for session in sessions where session.programId == program
            && session.startTime <= now && !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                for (player, team) in game.participants where members.contains(player) {
                    let line = game.stats(for: player) ?? SessionPlayerStats(playerId: player, gameId: game.id, teamId: team)
                    games[player, default: []].append((session.startTime, production(line, basketValue: game.basketValue)))
                }
            }
        }
        var out: [UUID: Double] = [:]
        for (player, all) in games {
            let recent = all.filter { $0.date >= start }
            let used = recent.count >= minimumGames
                ? recent : Array(all.sorted { $0.date > $1.date }.prefix(fallbackGames))
            guard used.count >= minimumGames else { continue }
            out[player] = used.reduce(0) { $0 + $1.value } / Double(used.count)
        }
        return out
    }

    /// Percentile (0 lowest … 1 highest, ties shared) of each value.
    static func percentiles(_ values: [UUID: Double]) -> [UUID: Double] {
        guard values.count > 1 else { return values.mapValues { _ in 0.5 } }
        let n = Double(values.count - 1)
        var out: [UUID: Double] = [:]
        for (id, v) in values {
            let below = values.values.filter { $0 < v }.count
            let equal = values.values.filter { $0 == v }.count - 1
            out[id] = (Double(below) + Double(equal) / 2) / n
        }
        return out
    }

    /// How far each member's production is from the group's, in SPREADS
    /// (−2…+2): by the SIZE of the gap, not the rank. A rank made three
    /// players producing 5.1, 5.0 and 4.9 a game Best, Average and Bottom.
    /// The spread is the group's standard deviation, never under 15 % of the
    /// average or half a point, so near-equal players stay together.
    static func gameDeltas(_ values: [UUID: Double]) -> [UUID: Double] {
        guard values.count >= 2 else { return [:] }
        let mean = values.values.reduce(0, +) / Double(values.count)
        let variance = values.values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let spread = max(variance.squareRoot(), 0.15 * abs(mean), 0.5)
        return values.mapValues { min(2, max(-2, ($0 - mean) / spread)) }
    }

    /// WHERE AN ATHLETE STANDS, AND WHAT THE NEXT LEVEL TAKES (27 Nov 2026,
    /// Luther: a motivated kid asked how much he has to improve to go up, and
    /// the level sat "hidden perfectly behind the system"). Everything the
    /// level is made of, in numbers the coach can say out loud.
    struct Standing: Equatable, Sendable {
        let tier: SkillTier
        /// Distance from the group's average, in rating points (the bands:
        /// ≥ +1.5 Best, ≥ +0.5 Better, > −0.5 Average, > −1.5 Below).
        let delta: Double
        /// Athletes of the group who have a level.
        let ranked: Int

        /// Their average rating over the rated skills, and the group's.
        let rating: Double?
        let groupRating: Double?
        /// How much of the level the ratings are (0.65 with games, 1 alone).
        let ratingWeight: Double

        /// Their production a game, the group's, and the group's spread.
        let production: Double?
        let groupProduction: Double?
        let spread: Double
        /// How much of the level the games are (0.35 beside ratings, 1 alone).
        let gameWeight: Double

        /// The level above (nil at the top) and how far `delta` is from it.
        let next: SkillTier?
        let gap: Double
        /// To get there on RATINGS alone: this much more on the rating
        /// average (their own rise also lifts the group's average a little —
        /// counted). Nil when they are not rated, or it would pass 10.
        let ratingNeeded: Double?
        /// To get there on GAMES alone: this much more production a game.
        /// Nil without games, or when games cannot carry it that far (the
        /// game half stops at two spreads above the group).
        let productionNeeded: Double?
        /// How far above the line of the level below (nil at the bottom).
        let cushion: Double?
    }

    /// The delta a level starts at.
    static func floor(of tier: SkillTier) -> Double? {
        switch tier {
        case .best: 1.5
        case .better: 0.5
        case .average: -0.5
        case .belowAverage: -1.5
        case .bottom: nil
        }
    }

    static func tier(above tier: SkillTier) -> SkillTier? {
        SkillTier(rawValue: tier.rawValue - 1)
    }

    /// Every ranked member's standing. Pure — `tiers` reads it, so the level
    /// and its explanation cannot disagree.
    /// Games weigh `gameWeight` for everyone in a group that has
    /// evaluations — also for a member who is not rated (an unrated top
    /// producer used to count at full weight and out-rank a rated one);
    /// they decide alone only in a group nobody has rated.
    static func standings(evaluation: [UUID: Double], games: [UUID: Double]) -> [UUID: Standing] {
        let ids = Set(evaluation.keys).union(games.keys)
        guard ids.count >= minimumGroup else { return [:] }
        let evalMean = evaluation.isEmpty ? 0 : evaluation.values.reduce(0, +) / Double(evaluation.count)
        let gameDelta = gameDeltas(games)
        let gameMean = games.isEmpty ? 0 : games.values.reduce(0, +) / Double(games.count)
        let variance = games.isEmpty ? 0
            : games.values.reduce(0) { $0 + ($1 - gameMean) * ($1 - gameMean) } / Double(games.count)
        let spread = max(variance.squareRoot(), 0.15 * abs(gameMean), 0.5)
        // A single evaluated child has nobody to be measured against.
        let groupIsRated = evaluation.count >= 2

        var deltas: [UUID: (delta: Double, ratingWeight: Double, gameWeight: Double)] = [:]
        for id in ids {
            let e = groupIsRated ? evaluation[id].map { $0 - evalMean } : nil
            let g = gameDelta[id]
            switch (e, g) {
            case let (e?, g?): deltas[id] = (evaluationWeight * e + gameWeight * g, evaluationWeight, gameWeight)
            case let (e?, nil): deltas[id] = (e, 1, 0)
            case let (nil, g?): deltas[id] = groupIsRated ? (gameWeight * g, 0, gameWeight) : (g, 0, 1)
            default: continue
            }
        }
        var out: [UUID: Standing] = [:]
        for (id, d) in deltas {
            let level = tier(forDelta: d.delta)
            let next = tier(above: level)
            // Average and Below open just ABOVE their line; Better and Best on it.
            let gap = next.flatMap(floor(of:)).map { line in
                max(0, line - d.delta + (next == .average || next == .belowAverage ? 0.01 : 0))
            } ?? 0
            var ratingNeeded: Double?
            if next != nil, d.ratingWeight > 0, let own = evaluation[id] {
                // Their own rise moves the group's average by 1/n of it.
                let share = 1 - 1 / Double(max(2, evaluation.count))
                let need = gap / (d.ratingWeight * share)
                if own + need <= 10 { ratingNeeded = need }
            }
            var productionNeeded: Double?
            if next != nil, d.gameWeight > 0, let z = gameDelta[id] {
                let need = gap / d.gameWeight
                if z + need <= 2 { productionNeeded = need * spread }
            }
            out[id] = Standing(
                tier: level, delta: d.delta, ranked: deltas.count,
                rating: evaluation[id], groupRating: groupIsRated ? evalMean : nil, ratingWeight: d.ratingWeight,
                production: games[id], groupProduction: games.count >= 2 ? gameMean : nil, spread: spread,
                gameWeight: d.gameWeight, next: next, gap: gap,
                ratingNeeded: ratingNeeded, productionNeeded: productionNeeded,
                cushion: floor(of: level).map { d.delta - $0 })
        }
        return out
    }

    /// The levels in one group, from each member's evaluation score and game
    /// score (either may be missing).
    static func tiers(evaluation: [UUID: Double], games: [UUID: Double]) -> [UUID: SkillTier] {
        standings(evaluation: evaluation, games: games).mapValues(\.tier)
    }

    /// Every ranked athlete's standing in a program.
    static func standings(in program: Program, sessions: [SessionEvent],
                          evaluations: [UUID: SkillsEvaluation], now: Date = Date()) -> [UUID: Standing] {
        let members = program.enrolledStudentIds
        guard members.count >= minimumGroup else { return [:] }
        var evaluation: [UUID: Double] = [:]
        for id in members {
            if let e = evaluationScore(evaluations[id]) { evaluation[id] = e }
        }
        let games = gameScores(members: Set(members), sessions: sessions, program: program.id, now: now)
        return standings(evaluation: evaluation, games: games)
    }

    /// The levels in a program: its enrolled athletes, their evaluations and
    /// the games played in its sessions.
    static func tiers(in program: Program, sessions: [SessionEvent],
                      evaluations: [UUID: SkillsEvaluation], now: Date = Date()) -> [UUID: SkillTier] {
        let members = program.enrolledStudentIds
        guard members.count >= minimumGroup else { return [:] }
        var evaluation: [UUID: Double] = [:]
        for id in members {
            if let e = evaluationScore(evaluations[id]) { evaluation[id] = e }
        }
        let games = gameScores(members: Set(members), sessions: sessions, program: program.id, now: now)
        return tiers(evaluation: evaluation, games: games)
    }
}

/// Every athlete's level in every group program, plus the one shown where no
/// program is on screen (their primary program, else the first group program
/// that ranks them). Built off the main thread after data changes.
struct SkillTierMap: Equatable, Sendable {
    var byProgram: [UUID: [UUID: SkillTier]] = [:]
    var primary: [UUID: SkillTier] = [:]

    func tier(for studentId: UUID, program: UUID?) -> SkillTier? {
        if let program { return byProgram[program]?[studentId] }
        return primary[studentId]
    }

    static func build(students: [Student], programs: [Program], sessions: [SessionEvent],
                      evaluations: [UUID: SkillsEvaluation], now: Date = Date()) -> SkillTierMap {
        var map = SkillTierMap()
        for program in programs where program.programType != .privateSessions {
            let tiers = SkillLevel.tiers(in: program, sessions: sessions, evaluations: evaluations, now: now)
            if !tiers.isEmpty { map.byProgram[program.id] = tiers }
        }
        for student in students {
            if let primary = student.programId, let tier = map.byProgram[primary]?[student.id] {
                map.primary[student.id] = tier
            } else if let tier = programs.lazy.compactMap({ map.byProgram[$0.id]?[student.id] }).first {
                map.primary[student.id] = tier
            }
        }
        return map
    }
}
