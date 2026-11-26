import Foundation

// Balanced teams from what the app knows (26 Nov 2026, Luther, markup on
// Create Game: "give each team an oct diagram to see the balance live" and
// "a button that balances the teams based on data: their levels, shooting
// power, defense, chemistry").
//
// Pure. A player's PROFILE is the eight octagon skills on 0…1:
//  · the coach's rating (÷ 10) where the skill is rated;
//  · EVIDENCE where the app has it, as a rank among the players in this
//    game mapped to 0.3…0.8 — shooting: points a game and the share made in
//    tracked shooting; passing: assists a game; defense: steals + blocks a
//    game (three games or more, as SkillEvidence);
//  · both: 70 % rating, 30 % evidence.
// A skill with neither is UNKNOWN — it is left out of a team's average and
// counts as the group's average when balancing, so a child nobody has
// rated neither helps nor hurts a team.
// STRENGTH is the average of the known skills, blended 70 / 30 with the
// skill level in the group when there is one; nothing known = the middle.
//
// BALANCING starts from a snake draft by strength and then swaps pairs
// between teams while a swap makes the teams more even on: strength,
// each skill (shooting and defense count double), and CHEMISTRY — the
// passer → scorer links between teammates, so one team does not get every
// pair that already finds each other.

enum TeamBalance {

    struct Profile: Equatable {
        let id: UUID
        /// Known skills only, 0…1.
        var axes: [DrillAttribute: Double] = [:]
        /// 0…1.
        var strength: Double = 0.5
        /// False when nothing at all is known about the player.
        var known = false
    }

    /// What the game numbers say about one player.
    struct GameNumbers: Equatable {
        var games = 0
        var points = 0
        var assists = 0
        var stocks = 0
    }

    static let minimumGames = 3
    static let minimumShots = 20.0
    static let ratingWeight = 0.7
    static let levelWeight = 0.3

    // MARK: Gathering

    /// Per player: games played and their totals, one pass over the sessions.
    static func gameNumbers(players: Set<UUID>, sessions: [SessionEvent]) -> [UUID: GameNumbers] {
        var out: [UUID: GameNumbers] = [:]
        for session in sessions where !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                for (player, _) in game.participants where players.contains(player) {
                    var n = out[player] ?? GameNumbers()
                    n.games += 1
                    if let line = game.stats(for: player) {
                        n.points += line.points
                        n.assists += line.assists
                        n.stocks += line.steals + line.blocks
                    }
                    out[player] = n
                }
            }
        }
        return out
    }

    /// The share made in tracked shooting (shot map + free throws), for the
    /// players with enough shots.
    static func shootingShares(players: Set<UUID>, sessions: [SessionEvent]) -> [UUID: Double] {
        var out: [UUID: Double] = [:]
        for id in players {
            var made = 0.0, attempted = 0.0
            for zone in ShootingHistory.zoneMap(for: id, sessions: sessions) {
                if let zone { made += zone.made; attempted += zone.attempted }
            }
            if let ft = ShootingHistory.freeThrows(for: id, sessions: sessions) {
                made += ft.made; attempted += ft.attempted
            }
            if attempted >= minimumShots { out[id] = made / attempted }
        }
        return out
    }

    /// Passer → scorer links between two players, either way.
    static func links(players: Set<UUID>, sessions: [SessionEvent]) -> [Pair: Int] {
        var out: [Pair: Int] = [:]
        for basket in GameChemistry.baskets(in: sessions).baskets {
            guard let passer = basket.assisterId, passer != basket.scorerId,
                  players.contains(passer), players.contains(basket.scorerId) else { continue }
            out[Pair(passer, basket.scorerId), default: 0] += 1
        }
        return out
    }

    struct Pair: Hashable {
        let a: UUID, b: UUID
        init(_ x: UUID, _ y: UUID) {
            if x.uuidString < y.uuidString { a = x; b = y } else { a = y; b = x }
        }
    }

    // MARK: Profiles

    /// A rank among the players who have the number, as 0.3…0.8. One player
    /// alone has nobody to be ranked against.
    static func evidence(_ values: [UUID: Double]) -> [UUID: Double] {
        guard values.count >= 2 else { return [:] }
        return SkillLevel.percentiles(values).mapValues { 0.3 + 0.5 * $0 }
    }

    static func profiles(players: [UUID],
                         evaluations: [UUID: SkillsEvaluation],
                         tiers: [UUID: SkillTier],
                         games: [UUID: GameNumbers],
                         shooting: [UUID: Double]) -> [UUID: Profile] {
        let played = games.filter { $0.value.games >= minimumGames }
        func perGame(_ value: (GameNumbers) -> Int) -> [UUID: Double] {
            evidence(played.mapValues { Double(value($0)) / Double($0.games) })
        }
        let points = perGame(\.points), assists = perGame(\.assists), stocks = perGame(\.stocks)
        let shots = evidence(shooting)

        var out: [UUID: Profile] = [:]
        for id in players {
            var profile = Profile(id: id)
            for axis in DrillAttribute.allCases {
                let rating = evaluations[id]?.rating(axis).map { Double($0) / 10 }
                var seen: [Double] = []
                switch axis {
                case .shooting:
                    if let v = points[id] { seen.append(v) }
                    if let v = shots[id] { seen.append(v) }
                case .passing: if let v = assists[id] { seen.append(v) }
                case .defense: if let v = stocks[id] { seen.append(v) }
                default: break
                }
                let shown = seen.isEmpty ? nil : seen.reduce(0, +) / Double(seen.count)
                switch (rating, shown) {
                case let (r?, e?): profile.axes[axis] = ratingWeight * r + (1 - ratingWeight) * e
                case let (r?, nil): profile.axes[axis] = r
                case let (nil, e?): profile.axes[axis] = e
                default: break
                }
            }
            let skills = profile.axes.isEmpty ? nil
                : profile.axes.values.reduce(0, +) / Double(profile.axes.count)
            let level = tiers[id].map(levelValue)
            switch (skills, level) {
            case let (s?, l?): profile.strength = (1 - levelWeight) * s + levelWeight * l
            case let (s?, nil): profile.strength = s
            case let (nil, l?): profile.strength = l
            default: profile.strength = 0.5
            }
            profile.known = skills != nil || level != nil
            out[id] = profile
        }
        return out
    }

    static func levelValue(_ tier: SkillTier) -> Double {
        switch tier {
        case .best: 0.8
        case .better: 0.65
        case .average: 0.5
        case .belowAverage: 0.35
        case .bottom: 0.2
        }
    }

    // MARK: A team

    struct TeamShape: Equatable {
        /// Each skill's average over the players it is known for (0 when for
        /// none) — the octagon.
        var axes: [DrillAttribute: Double] = [:]
        /// 0…10, the team's average strength.
        var strength = 0.0
        /// Players with anything known / on the team.
        var known = 0
        var players = 0
    }

    static func shape(of ids: [UUID], profiles: [UUID: Profile]) -> TeamShape {
        var shape = TeamShape(players: ids.count)
        let members = ids.compactMap { profiles[$0] }
        shape.known = members.filter(\.known).count
        for axis in DrillAttribute.allCases {
            let values = members.compactMap { $0.axes[axis] }
            shape.axes[axis] = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        if !members.isEmpty {
            shape.strength = members.map(\.strength).reduce(0, +) / Double(members.count) * 10
        }
        return shape
    }

    /// Where two or more teams differ most: the skills whose team averages
    /// are at least `gap` apart, widest first, with the team that leads.
    static func gaps(_ shapes: [TeamShape], gap: Double = 0.1) -> [(axis: DrillAttribute, leader: Int, by: Double)] {
        guard shapes.count >= 2 else { return [] }
        var out: [(axis: DrillAttribute, leader: Int, by: Double)] = []
        for axis in DrillAttribute.allCases {
            let values = shapes.map { $0.axes[axis] ?? 0 }
            // A team where nobody is rated on the skill says nothing.
            guard !values.contains(0), let top = values.max(), let low = values.min(),
                  top - low >= gap, let leader = values.firstIndex(of: top) else { continue }
            out.append((axis, leader, top - low))
        }
        return out.sorted { $0.by > $1.by }
    }

    // MARK: Balancing

    static func axisWeight(_ axis: DrillAttribute) -> Double {
        axis == .shooting || axis == .defense ? 2 : 1
    }

    /// How uneven a split is — 0 is perfectly even.
    static func cost(_ teams: [[UUID]], profiles: [UUID: Profile], links: [Pair: Int],
                     groupAxes: [DrillAttribute: Double]) -> Double {
        guard teams.count >= 2 else { return 0 }
        func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

        let strength = spread(teams.map { team in mean(team.map { profiles[$0]?.strength ?? 0.5 }) })

        var skills = 0.0, weights = 0.0
        for axis in DrillAttribute.allCases {
            let middle = groupAxes[axis] ?? 0.5
            let w = axisWeight(axis)
            skills += w * spread(teams.map { team in mean(team.map { profiles[$0]?.axes[axis] ?? middle }) })
            weights += w
        }
        skills /= weights

        var chemistry = 0.0
        let total = links.values.reduce(0, +)
        if total > 0 {
            let inside = teams.map { team -> Double in
                let set = Set(team)
                return Double(links.filter { set.contains($0.key.a) && set.contains($0.key.b) }.values.reduce(0, +))
            }
            chemistry = spread(inside) / Double(total)
        }
        return 3 * strength + 2 * skills + 0.5 * chemistry
    }

    /// The players split into `teamCount` teams, sizes at most one apart,
    /// each team's strongest first (they take the starter slots).
    /// Deterministic: the same players and data give the same teams.
    static func balanced(players: [UUID], teamCount: Int, profiles: [UUID: Profile],
                         links: [Pair: Int] = [:]) -> [[UUID]] {
        guard teamCount >= 1 else { return [] }
        func strength(_ id: UUID) -> Double { profiles[id]?.strength ?? 0.5 }
        let order = players.sorted {
            strength($0) != strength($1) ? strength($0) > strength($1) : $0.uuidString < $1.uuidString
        }
        var teams = Array(repeating: [UUID](), count: teamCount)
        for (i, id) in order.enumerated() {
            let round = i / teamCount, seat = i % teamCount
            teams[round.isMultiple(of: 2) ? seat : teamCount - 1 - seat].append(id)
        }
        guard teamCount >= 2 else { return teams }

        var groupAxes: [DrillAttribute: Double] = [:]
        for axis in DrillAttribute.allCases {
            let values = players.compactMap { profiles[$0]?.axes[axis] }
            if !values.isEmpty { groupAxes[axis] = values.reduce(0, +) / Double(values.count) }
        }

        var best = cost(teams, profiles: profiles, links: links, groupAxes: groupAxes)
        var passes = 0
        while passes < 60 {
            passes += 1
            var improved: (cost: Double, teams: [[UUID]])?
            for i in 0..<teamCount {
                for j in (i + 1)..<teamCount {
                    for a in teams[i].indices {
                        for b in teams[j].indices {
                            var trial = teams
                            trial[i][a] = teams[j][b]
                            trial[j][b] = teams[i][a]
                            let c = cost(trial, profiles: profiles, links: links, groupAxes: groupAxes)
                            if c < (improved?.cost ?? best) - 1e-9 { improved = (c, trial) }
                        }
                    }
                }
            }
            guard let improved else { break }
            teams = improved.teams
            best = improved.cost
        }
        return teams.map { team in
            team.sorted {
                strength($0) != strength($1) ? strength($0) > strength($1) : $0.uuidString < $1.uuidString
            }
        }
    }
}
