import Foundation

// HOW BASKETS ARE MADE, AND WHO PLAYS WELL TOGETHER (14 November 2026,
// Luther: "when a player gets most of his shots from assists or generates
// his own shots … who one player assists the most or receives from the most
// … the type of interpretation I expect from the app"). Pure: reads the
// games' basket logs (SessionGame.baskets) — the stat lines hold only counts,
// so games scored before the log existed say nothing here.
//
// Same scope and counting rules as GameStatsReport: sessions that did not
// happen are left out; people in `excluding` (organization coaches who
// played) are dropped from every basket they scored or set up.

enum GameChemistry {

    /// How one player's baskets were made.
    struct Creation: Identifiable, Equatable {
        var id: UUID { playerId }
        let playerId: UUID
        let baskets: Int
        let assisted: Int
        var own: Int { baskets - assisted }
        var assistedShare: Double { baskets > 0 ? Double(assisted) / Double(baskets) : 0 }
    }

    /// A passer → scorer connection.
    struct Duo: Identifiable, Equatable {
        var id: String { "\(passer)>\(scorer)" }
        let passer: UUID
        let scorer: UUID
        let count: Int
    }

    /// A player who sets others up, and who they find most.
    struct Playmaker: Identifiable, Equatable {
        var id: UUID { playerId }
        let playerId: UUID
        let assists: Int
        let favourite: UUID?
        let favouriteCount: Int
    }

    struct Summary: Equatable {
        /// Games with a basket log.
        let games: Int
        let baskets: Int
        let assisted: Int
        let points: Int
        /// Most baskets first.
        let creation: [Creation]
        /// Strongest connections first (passer → scorer).
        let duos: [Duo]
        /// Most assists first.
        let playmakers: [Playmaker]
        var assistedShare: Double { baskets > 0 ? Double(assisted) / Double(baskets) : 0 }
        var isEmpty: Bool { baskets == 0 }
    }

    /// Every logged basket in these sessions, coaches left out.
    static func baskets(in sessions: [SessionEvent], excluding: Set<UUID> = []) -> (games: Int, baskets: [GameBasket]) {
        var games = 0
        var out: [GameBasket] = []
        for session in sessions where !SessionLifecycle.didNotHappen(session) {
            for game in session.games where !game.baskets.isEmpty {
                games += 1
                for b in game.baskets where !excluding.contains(b.scorerId) {
                    var basket = b
                    if let a = b.assisterId, excluding.contains(a) { basket.assisterId = nil }
                    out.append(basket)
                }
            }
        }
        return (games, out)
    }

    static func summary(sessions: [SessionEvent], excluding: Set<UUID> = []) -> Summary {
        let (games, log) = baskets(in: sessions, excluding: excluding)
        return summary(log: log, games: games)
    }

    /// One game (or a few) on their own — the game recap.
    static func summary(games: [SessionGame], excluding: Set<UUID> = []) -> Summary {
        let log = games.flatMap(\.baskets).filter { !excluding.contains($0.scorerId) }.map { b -> GameBasket in
            var basket = b
            if let a = b.assisterId, excluding.contains(a) { basket.assisterId = nil }
            return basket
        }
        return summary(log: log, games: games.filter { !$0.baskets.isEmpty }.count)
    }

    private static func summary(log: [GameBasket], games: Int) -> Summary {
        var made: [UUID: (Int, Int)] = [:]
        var pairs: [String: (UUID, UUID, Int)] = [:]
        var given: [UUID: [UUID: Int]] = [:]
        for b in log {
            var m = made[b.scorerId] ?? (0, 0)
            m.0 += 1
            if let a = b.assisterId {
                m.1 += 1
                let key = "\(a)>\(b.scorerId)"
                let p = pairs[key] ?? (a, b.scorerId, 0)
                pairs[key] = (p.0, p.1, p.2 + 1)
                given[a, default: [:]][b.scorerId, default: 0] += 1
            }
            made[b.scorerId] = m
        }
        let creation = made.map { Creation(playerId: $0.key, baskets: $0.value.0, assisted: $0.value.1) }
            .sorted { ($0.baskets, $0.assisted) > ($1.baskets, $1.assisted) }
        let duos = pairs.values.map { Duo(passer: $0.0, scorer: $0.1, count: $0.2) }
            .sorted { $0.count > $1.count }
        let playmakers = given.map { passer, targets -> Playmaker in
            let top = targets.max { $0.value < $1.value }
            return Playmaker(playerId: passer, assists: targets.values.reduce(0, +),
                             favourite: top?.key, favouriteCount: top?.value ?? 0)
        }
        .sorted { $0.assists > $1.assists }
        return Summary(games: games, baskets: log.count, assisted: log.filter { $0.assisterId != nil }.count,
                       points: log.reduce(0) { $0 + $1.points },
                       creation: creation, duos: duos, playmakers: playmakers)
    }

    // MARK: - One player

    struct PlayerChemistry: Equatable {
        let baskets: Int
        let assisted: Int
        let assistsGiven: Int
        /// Who the player sets up most, and how often.
        let feeds: (player: UUID, count: Int)?
        /// Who sets the player up most, and how often.
        let fedBy: (player: UUID, count: Int)?

        static func == (a: Self, b: Self) -> Bool {
            a.baskets == b.baskets && a.assisted == b.assisted && a.assistsGiven == b.assistsGiven
                && a.feeds?.player == b.feeds?.player && a.feeds?.count == b.feeds?.count
                && a.fedBy?.player == b.fedBy?.player && a.fedBy?.count == b.fedBy?.count
        }
    }

    static func player(_ id: UUID, sessions: [SessionEvent], excluding: Set<UUID> = []) -> PlayerChemistry {
        let log = baskets(in: sessions, excluding: excluding).baskets
        let mine = log.filter { $0.scorerId == id }
        let assistedMine = mine.compactMap(\.assisterId)
        let set = log.filter { $0.assisterId == id }
        func top(_ ids: [UUID]) -> (UUID, Int)? {
            Dictionary(grouping: ids, by: { $0 }).map { ($0.key, $0.value.count) }.max { $0.1 < $1.1 }
        }
        return PlayerChemistry(baskets: mine.count, assisted: assistedMine.count, assistsGiven: set.count,
                               feeds: top(set.map(\.scorerId)).map { ($0.0, $0.1) },
                               fedBy: top(assistedMine).map { ($0.0, $0.1) })
    }

    // MARK: - Worded readings (each behind a threshold, so noise stays quiet)

    enum Reading: Equatable {
        /// Most of the player's baskets come off a teammate's pass.
        case finisher(assisted: Int, of: Int)
        /// The player makes most baskets on their own.
        case creator(own: Int, of: Int)
        /// The player looks for one teammate above all.
        case feeds(player: UUID, count: Int, of: Int)
        /// One teammate sets the player up above all.
        case fedBy(player: UUID, count: Int, of: Int)
    }

    /// Baskets before saying how a player scores.
    static let minBaskets = 5
    /// Share that counts as "most".
    static let mostShare = 0.7
    /// Assists (given or received) before naming a partner, and the share of
    /// them one teammate must hold.
    static let minLinks = 3
    static let partnerShare = 0.5

    static func readings(for p: PlayerChemistry) -> [Reading] {
        var out: [Reading] = []
        if p.baskets >= minBaskets {
            let share = Double(p.assisted) / Double(p.baskets)
            if share >= mostShare { out.append(.finisher(assisted: p.assisted, of: p.baskets)) }
            else if 1 - share >= mostShare { out.append(.creator(own: p.baskets - p.assisted, of: p.baskets)) }
        }
        if p.assistsGiven >= minLinks, let f = p.feeds, f.count >= 2,
           Double(f.count) / Double(p.assistsGiven) >= partnerShare {
            out.append(.feeds(player: f.player, count: f.count, of: p.assistsGiven))
        }
        if p.assisted >= minLinks, let f = p.fedBy, f.count >= 2,
           Double(f.count) / Double(p.assisted) >= partnerShare {
            out.append(.fedBy(player: f.player, count: f.count, of: p.assisted))
        }
        return out
    }
}
