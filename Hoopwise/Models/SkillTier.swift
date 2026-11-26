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

    /// Production per game: points + rebounds + 1.5 × assists + 2 × stocks.
    static func production(_ line: SessionPlayerStats) -> Double {
        Double(line.points + line.rebounds) + 1.5 * Double(line.assists) + 2 * Double(line.steals + line.blocks)
    }

    /// The evaluation's score: the average of the rated skills, when enough
    /// are rated.
    static func evaluationScore(_ evaluation: SkillsEvaluation?) -> Double? {
        guard let evaluation else { return nil }
        let rated = DrillAttribute.allCases.compactMap { evaluation.rating($0) }
        guard rated.count >= minimumRatedSkills else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    /// Production per game for every member, in ONE pass over the program's
    /// games in the window (the same games GameStatsReport.playerGames counts:
    /// played, in sessions that happened, everyone who took part).
    static func gameScores(members: Set<UUID>, sessions: [SessionEvent], program: UUID, now: Date) -> [UUID: Double] {
        let start = Calendar.current.date(byAdding: .day, value: -gameWindowDays, to: now) ?? now
        var total: [UUID: Double] = [:]
        var count: [UUID: Int] = [:]
        for session in sessions where session.programId == program
            && session.startTime >= start && session.startTime <= now
            && !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                for (player, team) in game.participants where members.contains(player) {
                    let line = game.stats(for: player) ?? SessionPlayerStats(playerId: player, gameId: game.id, teamId: team)
                    total[player, default: 0] += production(line)
                    count[player, default: 0] += 1
                }
            }
        }
        var out: [UUID: Double] = [:]
        for (player, n) in count where n >= minimumGames { out[player] = (total[player] ?? 0) / Double(n) }
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

    /// The levels in one group, from each member's evaluation score and game
    /// score (either may be missing). Pure — tests drive it directly.
    static func tiers(evaluation: [UUID: Double], games: [UUID: Double]) -> [UUID: SkillTier] {
        let evalMean = evaluation.isEmpty ? 0 : evaluation.values.reduce(0, +) / Double(evaluation.count)
        let gamePct = percentiles(games)
        let ids = Set(evaluation.keys).union(games.keys)
        guard ids.count >= minimumGroup else { return [:] }
        var out: [UUID: SkillTier] = [:]
        for id in ids {
            // A single evaluated child has nobody to be measured against.
            let e = evaluation.count >= 2 ? evaluation[id].map { $0 - evalMean } : nil
            let g = games.count >= 2 ? gamePct[id].map { ($0 - 0.5) * 4 } : nil
            let delta: Double
            switch (e, g) {
            case let (e?, g?): delta = evaluationWeight * e + gameWeight * g
            case let (e?, nil): delta = e
            case let (nil, g?): delta = g
            default: continue
            }
            out[id] = tier(forDelta: delta)
        }
        return out
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
