import Foundation

// WHAT THE GAMES SAY (28 Nov 2026, Luther, on the games dashboard: "is this
// the best we can do in terms of insight? … a better use of collected in-game
// data, be it to understand the group or predict" → "build all 7"). Pure.
//
// The dashboard counted things (baskets, assists, one-off "chemistry"). This
// reads RESULTS: every game between two teams of known players is a small
// experiment — who was with whom, against whom, and by how much they won.
//
//  1. IMPACT — whose teams win. A player's teams' margin, and a RATING that
//     shares each game's margin among the players on both sides (ridge
//     regression: a few games move a rating little, many move it a lot).
//  2. PREDICTION — the ratings of two proposed teams give an expected margin.
//  3. TRANSFER — what the recent classes trained, and whether the matching
//     game number moved.
//  4. PAIRS — how two players' teams do when they play TOGETHER.
//  5. RATING V GAMES — where the coach's rating and the games disagree.
//  6. DEPENDENCE and QUIET players.
//  7. THRESHOLDS — every finding needs enough games to mean something, and
//     says how many it stands on.
//
// Margins are in BASKETS (points ÷ that game's basket value), so 1-, 2- and
// 3-point games compare.

enum GameImpact {

    // MARK: The games

    /// One game between two teams of known players.
    struct TeamGame: Equatable {
        let date: Date
        let sessionId: UUID
        let a: [UUID]
        let b: [UUID]
        /// a's score − b's, in baskets.
        let margin: Double
    }

    static let minimumGames = 6          // team games before impact is shown
    static let minimumPlayerGames = 3    // a player's games before they are named
    static let minimumPairGames = 4

    /// Every played game with exactly two teams that had players on the
    /// floor, oldest first. A game against an opponent without players (a
    /// team's Game Day), a Battle Royal and a game nobody scored in a tie of
    /// zero are left out.
    static func teamGames(in sessions: [SessionEvent], excluding: Set<UUID> = []) -> [TeamGame] {
        var out: [TeamGame] = []
        for session in sessions.sorted(by: { $0.startTime < $1.startTime }) where !SessionLifecycle.didNotHappen(session) {
            for game in session.games.sorted(by: { $0.gameNumber < $1.gameNumber })
            where GameStatsReport.played(game) && !game.gameType.isIndividual {
                var sides: [UUID: [UUID]] = [:]
                for (player, team) in game.participants where !excluding.contains(player) {
                    sides[team, default: []].append(player)
                }
                let teams = sides.keys.sorted { $0.uuidString < $1.uuidString }
                guard teams.count == 2 else { continue }
                let scoreA = game.teamScores[teams[0]] ?? 0, scoreB = game.teamScores[teams[1]] ?? 0
                guard scoreA + scoreB > 0 else { continue }
                out.append(TeamGame(date: session.startTime, sessionId: session.id,
                                    a: sides[teams[0]]!.sorted { $0.uuidString < $1.uuidString },
                                    b: sides[teams[1]]!.sorted { $0.uuidString < $1.uuidString },
                                    margin: Double(scoreA - scoreB) / Double(max(1, game.basketValue))))
            }
        }
        return out
    }

    // MARK: 1 · Impact and the rating

    struct PlayerImpact: Identifiable, Equatable {
        var id: UUID { playerId }
        let playerId: UUID
        let games: Int
        let wins: Int
        let losses: Int
        /// Their teams' average margin, in baskets a game.
        let margin: Double
        /// What the rating says they are worth to a team's margin, in baskets
        /// a game, with who they played with and against taken into account.
        let worth: Double
    }

    /// How strongly a rating is held back until games accumulate.
    static let ridge = 0.25

    /// A rating per player: the margin of each game explained as (the average
    /// rating of one side) − (the average rating of the other). Deterministic.
    static func ratings(_ games: [TeamGame]) -> [UUID: Double] {
        var beta: [UUID: Double] = [:]
        for game in games { for p in game.a + game.b { beta[p] = 0 } }
        guard !games.isEmpty else { return beta }
        let players = beta.keys.sorted { $0.uuidString < $1.uuidString }
        // Each player's weight in each game they played.
        var rows: [UUID: [(game: Int, x: Double)]] = [:]
        for (i, game) in games.enumerated() {
            for p in game.a { rows[p, default: []].append((i, 1 / Double(game.a.count))) }
            for p in game.b { rows[p, default: []].append((i, -1 / Double(game.b.count))) }
        }
        var predicted = [Double](repeating: 0, count: games.count)
        for _ in 0..<80 {
            for p in players {
                guard let mine = rows[p] else { continue }
                let old = beta[p] ?? 0
                var top = 0.0, bottom = ridge
                for (g, x) in mine {
                    top += x * (games[g].margin - predicted[g] + x * old)
                    bottom += x * x
                }
                let new = top / bottom
                for (g, x) in mine { predicted[g] += x * (new - old) }
                beta[p] = new
            }
        }
        return beta
    }

    static func impact(_ games: [TeamGame], ratings: [UUID: Double]) -> [PlayerImpact] {
        struct Tally { var games = 0, wins = 0, losses = 0, margin = 0.0, mates = 0 }
        var tally: [UUID: Tally] = [:]
        for game in games {
            for (side, sign) in [(game.a, 1.0), (game.b, -1.0)] {
                let m = sign * game.margin
                for p in side {
                    var t = tally[p] ?? Tally()
                    t.games += 1; t.margin += m; t.mates += side.count
                    if m > 0 { t.wins += 1 } else if m < 0 { t.losses += 1 }
                    tally[p] = t
                }
            }
        }
        return tally.filter { $0.value.games >= minimumPlayerGames }.map { id, t in
            // The rating is per "one whole side"; a player is one of n.
            let size = Double(t.mates) / Double(t.games)
            return PlayerImpact(playerId: id, games: t.games, wins: t.wins, losses: t.losses,
                                margin: t.margin / Double(t.games), worth: (ratings[id] ?? 0) / max(1, size))
        }
        .sorted { $0.worth != $1.worth ? $0.worth > $1.worth : $0.playerId.uuidString < $1.playerId.uuidString }
    }

    // MARK: 2 · Prediction

    struct Prediction: Equatable {
        /// Team a's expected margin over team b, in baskets.
        let margin: Double
        /// Games the ratings stand on.
        let games: Int
    }

    /// What the results so far say about two proposed teams. Nil until there
    /// are enough games and most of the players have played in them.
    static func predict(a: [UUID], b: [UUID], games: [TeamGame], ratings: [UUID: Double]) -> Prediction? {
        guard games.count >= minimumGames, !a.isEmpty, !b.isEmpty else { return nil }
        var played: [UUID: Int] = [:]
        for game in games { for p in game.a + game.b { played[p, default: 0] += 1 } }
        let everyone = a + b
        let known = everyone.filter { (played[$0] ?? 0) >= minimumPlayerGames }.count
        guard Double(known) >= 0.6 * Double(everyone.count) else { return nil }
        func mean(_ ids: [UUID]) -> Double { ids.reduce(0) { $0 + (ratings[$1] ?? 0) } / Double(ids.count) }
        return Prediction(margin: mean(a) - mean(b), games: games.count)
    }

    // MARK: 4 · Pairs

    struct Pair: Identifiable, Equatable {
        var id: String { first.uuidString + second.uuidString }
        let first: UUID
        let second: UUID
        let games: Int
        let wins: Int
        /// Their team's average margin when they play together, in baskets.
        let margin: Double
    }

    /// Pairs with enough games on the same team, best margin first.
    static func pairs(_ games: [TeamGame]) -> [Pair] {
        struct Tally { var games = 0, wins = 0, margin = 0.0 }
        var tally: [String: (UUID, UUID, Tally)] = [:]
        for game in games {
            for (side, sign) in [(game.a, 1.0), (game.b, -1.0)] {
                let m = sign * game.margin
                for i in side.indices {
                    for j in side.indices where j > i {
                        let key = side[i].uuidString + side[j].uuidString
                        var entry = tally[key] ?? (side[i], side[j], Tally())
                        entry.2.games += 1; entry.2.margin += m
                        if m > 0 { entry.2.wins += 1 }
                        tally[key] = entry
                    }
                }
            }
        }
        return tally.values.filter { $0.2.games >= minimumPairGames }
            .map { Pair(first: $0.0, second: $0.1, games: $0.2.games, wins: $0.2.wins, margin: $0.2.margin / Double($0.2.games)) }
            .sorted { $0.margin != $1.margin ? $0.margin > $1.margin : $0.id < $1.id }
    }

    // MARK: 3 · Training → games

    enum TransferMetric: Equatable { case offAPass, stocks, baskets }

    struct Transfer: Identifiable, Equatable {
        var id: String { axis.rawValue }
        let axis: DrillAttribute
        let metric: TransferMetric
        /// The share of the recent classes' plan time spent on the skill.
        let share: Double
        let classes: Int
        let before: Double
        let now: Double
        /// +1 clearly up, −1 clearly down, 0 about the same.
        var direction: Int {
            guard before > 0 else { return now > 0 ? 1 : 0 }
            let change = (now - before) / before
            return change >= 0.10 ? 1 : (change <= -0.10 ? -1 : 0)
        }
    }

    static let transferShare = 0.18

    /// For the skills the recent classes spent real time on: the game number
    /// that goes with the skill, before those classes and since. `trained` =
    /// minutes per skill of each class's plan (PlanCoverage), by session id.
    /// Needs four sessions with games (the later half are "since").
    static func transfer(sessions: [SessionEvent], trained: [UUID: [DrillAttribute: Double]],
                         excluding: Set<UUID> = []) -> [Transfer] {
        let happened = sessions.filter { !SessionLifecycle.didNotHappen($0) }.sorted { $0.startTime < $1.startTime }
        let withGames = happened.filter { $0.games.contains(where: GameStatsReport.played) }
        guard withGames.count >= 4 else { return [] }
        let recentCount = min(3, withGames.count / 2)
        let recent = Array(withGames.suffix(recentCount))
        let before = Array(withGames.dropLast(recentCount))
        guard let lastBefore = before.last?.startTime else { return [] }

        // What the classes since then trained.
        let since = happened.filter { $0.startTime > lastBefore }
        var minutes: [DrillAttribute: Double] = [:]
        var classes: [DrillAttribute: Int] = [:]
        for session in since {
            for (axis, value) in trained[session.id] ?? [:] where value > 0 {
                minutes[axis, default: 0] += value
                classes[axis, default: 0] += 1
            }
        }
        let total = minutes.values.reduce(0, +)
        guard total > 0 else { return [] }

        func numbers(_ list: [SessionEvent]) -> (offAPass: Double?, stocks: Double?, baskets: Double?) {
            var logged = 0, assisted = 0, playerGames = 0, stocks = 0, baskets = 0.0
            for session in list {
                for game in session.games where GameStatsReport.played(game) {
                    for basket in game.baskets where !excluding.contains(basket.scorerId) {
                        logged += 1
                        if let passer = basket.assisterId, !excluding.contains(passer) { assisted += 1 }
                    }
                    for player in game.participants.keys where !excluding.contains(player) {
                        playerGames += 1
                        if let line = game.stats(for: player) {
                            stocks += line.steals + line.blocks
                            baskets += Double(line.points) / Double(max(1, game.basketValue))
                        }
                    }
                }
            }
            return (logged >= 8 ? Double(assisted) / Double(logged) : nil,
                    playerGames >= 10 ? Double(stocks) / Double(playerGames) : nil,
                    playerGames >= 10 ? baskets / Double(playerGames) : nil)
        }
        let then = numbers(before), now = numbers(recent)

        var out: [Transfer] = []
        func add(_ axis: DrillAttribute, _ metric: TransferMetric, _ b: Double?, _ n: Double?) {
            let share = (minutes[axis] ?? 0) / total
            guard share >= transferShare, let b, let n else { return }
            out.append(Transfer(axis: axis, metric: metric, share: share, classes: classes[axis] ?? 0, before: b, now: n))
        }
        add(.passing, .offAPass, then.offAPass, now.offAPass)
        add(.defense, .stocks, then.stocks, now.stocks)
        // Shooting and finishing share the one number games have for scoring.
        let scoring: DrillAttribute = (minutes[.shooting] ?? 0) >= (minutes[.finishing] ?? 0) ? .shooting : .finishing
        add(scoring, .baskets, then.baskets, now.baskets)
        return out.sorted { $0.share > $1.share }
    }

    // MARK: 5 · Rating v games

    struct Mismatch: Identifiable, Equatable {
        var id: String { playerId.uuidString + axis.rawValue }
        let playerId: UUID
        let axis: DrillAttribute
        let rating: Int
        /// 1 = most in the group; `of` = players compared.
        let rank: Int
        let of: Int
        /// True: the games show more than the rating says. False: less.
        let playsAbove: Bool
    }

    /// Where the coach's rating and the games disagree most: the player's
    /// place in the group by rating against their place by the game number
    /// for that skill (shooting: baskets a game; passing: assists; defense:
    /// steals + blocks). Half the group apart or more; four players compared.
    static func mismatches(sessions: [SessionEvent], ratings: [UUID: SkillsEvaluation],
                           excluding: Set<UUID> = []) -> [Mismatch] {
        struct Raw { var games = 0, baskets = 0.0, assists = 0, stocks = 0 }
        var raw: [UUID: Raw] = [:]
        for session in sessions where !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                for player in game.participants.keys where !excluding.contains(player) {
                    var r = raw[player] ?? Raw()
                    r.games += 1
                    if let line = game.stats(for: player) {
                        r.baskets += Double(line.points) / Double(max(1, game.basketValue))
                        r.assists += line.assists
                        r.stocks += line.steals + line.blocks
                    }
                    raw[player] = r
                }
            }
        }
        let played = raw.filter { $0.value.games >= minimumPlayerGames }
        var found: [(Mismatch, Double)] = []
        let measures: [(DrillAttribute, (Raw) -> Double)] = [
            (.shooting, { $0.baskets / Double($0.games) }),
            (.passing, { Double($0.assists) / Double($0.games) }),
            (.defense, { Double($0.stocks) / Double($0.games) }),
        ]
        for (axis, measure) in measures {
            var shown: [UUID: Double] = [:], rated: [UUID: Double] = [:]
            for (id, r) in played {
                guard let rating = ratings[id]?.rating(axis) else { continue }
                shown[id] = measure(r)
                rated[id] = Double(rating)
            }
            guard shown.count >= 4 else { continue }
            let byGames = SkillLevel.percentiles(shown), byRating = SkillLevel.percentiles(rated)
            for (id, value) in shown {
                let gap = (byGames[id] ?? 0.5) - (byRating[id] ?? 0.5)
                guard abs(gap) >= 0.5 else { continue }
                let rank = shown.values.filter { $0 > value }.count + 1
                found.append((Mismatch(playerId: id, axis: axis, rating: Int(rated[id] ?? 0), rank: rank,
                                       of: shown.count, playsAbove: gap > 0), abs(gap)))
            }
        }
        return found.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.prefix(3).map(\.0)
    }

    // MARK: 6 · Dependence and quiet players

    struct Dependence: Equatable {
        let top: UUID
        /// The top scorer's share of every basket, and the top two's.
        let topShare: Double
        let topTwoShare: Double
        let games: Int
    }

    struct Watch: Equatable {
        /// Set when one player makes 40 % of the baskets or more (five
        /// players or more in the games).
        var dependence: Dependence?
        /// Played three games or more without a single point, rebound,
        /// assist, steal or block.
        var quiet: [UUID] = []
        var isEmpty: Bool { dependence == nil && quiet.isEmpty }
    }

    static func watch(sessions: [SessionEvent], excluding: Set<UUID> = []) -> Watch {
        var games = 0
        var baskets: [UUID: Double] = [:], played: [UUID: Int] = [:], touched: Set<UUID> = []
        for session in sessions where !SessionLifecycle.didNotHappen(session) {
            for game in session.games where GameStatsReport.played(game) {
                games += 1
                for player in game.participants.keys where !excluding.contains(player) {
                    played[player, default: 0] += 1
                    guard let line = game.stats(for: player) else { continue }
                    baskets[player, default: 0] += Double(line.points) / Double(max(1, game.basketValue))
                    if line.hasStats { touched.insert(player) }
                }
            }
        }
        var watch = Watch()
        let total = baskets.values.reduce(0, +)
        // In a group of two or three, one player making most of the baskets
        // is not news.
        if games >= 4, total >= 15, played.count >= 5 {
            let order = baskets.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.uuidString < $1.key.uuidString }
            if let first = order.first, first.value / total >= 0.4 {
                watch.dependence = Dependence(top: first.key, topShare: first.value / total,
                                              topTwoShare: (first.value + (order.dropFirst().first?.value ?? 0)) / total,
                                              games: games)
            }
        }
        watch.quiet = played.filter { $0.value >= minimumPlayerGames && !touched.contains($0.key) }
            .keys.sorted { $0.uuidString < $1.uuidString }
        return watch
    }

    // MARK: Everything, once

    struct Report: Equatable {
        var games: [TeamGame] = []
        var ratings: [UUID: Double] = [:]
        var impact: [PlayerImpact] = []
        var pairs: [Pair] = []
        var transfer: [Transfer] = []
        var mismatches: [Mismatch] = []
        var watch = Watch()
        /// Enough games between two teams to speak about results.
        var hasResults: Bool { games.count >= minimumGames }
    }

    static func report(sessions: [SessionEvent], trained: [UUID: [DrillAttribute: Double]],
                       evaluations: [UUID: SkillsEvaluation], excluding: Set<UUID> = []) -> Report {
        let games = teamGames(in: sessions, excluding: excluding)
        let ratings = ratings(games)
        return Report(games: games, ratings: ratings,
                      impact: games.count >= minimumGames ? impact(games, ratings: ratings) : [],
                      pairs: games.count >= minimumGames ? pairs(games) : [],
                      transfer: transfer(sessions: sessions, trained: trained, excluding: excluding),
                      mismatches: mismatches(sessions: sessions, ratings: evaluations, excluding: excluding),
                      watch: watch(sessions: sessions, excluding: excluding))
    }
}
