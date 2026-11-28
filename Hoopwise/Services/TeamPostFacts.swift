import Foundation

// TEAM POSTS (28 Nov 2026, Luther: "for teams, add a vault too … exporting
// would be for the final score, Game day … and other team related stats").
// What a team post says, worked out from the team's games (sessions of type
// .game with curriculum.teamId — GameDay.score is the one scoring rule). Pure.
// Nothing is invented: a kind without data says so and the composer offers
// another.

struct TeamPostFacts {
    enum Kind: String, CaseIterable, Identifiable {
        case final, gameDay, season
        var id: String { rawValue }
        func title(chinese: Bool) -> String {
            switch self {
            case .final: chinese ? "比分" : "Final score"
            case .gameDay: chinese ? "比赛日" : "Game day"
            case .season: chinese ? "赛季" : "Season"
            }
        }
    }

    var kind: Kind
    var teamName: String
    var shortName: String
    var colorHex: String
    var academy: String
    var chinese: Bool

    // A game (final score / game day).
    var opponent = ""
    var isHome = true
    var date: Date?
    var venue = ""
    var ours = 0
    var theirs = 0
    var isFinal = false

    // The season.
    var wins = 0
    var losses = 0
    var ties = 0
    var pointsFor = 0.0
    var pointsAgainst = 0.0
    var games = 0
    /// Newest first, "W" / "L" / "T".
    var recent: [String] = []
    var firstDate: Date?
    var lastDate: Date?

    var hasData: Bool {
        switch kind {
        case .final: return date != nil && (ours + theirs > 0 || isFinal)
        case .gameDay: return date != nil
        case .season: return games > 0
        }
    }

    var won: Bool { ours > theirs }
    var tied: Bool { ours == theirs }
    var record: String { ties > 0 ? "\(wins)–\(losses)–\(ties)" : "\(wins)–\(losses)" }
    /// "VS" at home, "AT" away.
    var versusWord: String { isHome ? (chinese ? "主场对阵" : "VS") : (chinese ? "客场挑战" : "AT") }

    /// A badge's letters: the short name, else initials.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        if name.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return String(name.prefix(2)) }
        if words.count > 1 { return words.prefix(3).compactMap { $0.first.map(String.init) }.joined().uppercased() }
        return String(name.prefix(3)).uppercased()
    }

    // MARK: Making it

    /// The team's games, oldest first.
    static func teamGames(of team: Team, in sessions: [SessionEvent]) -> [SessionEvent] {
        sessions.filter { $0.curriculum.teamId == team.id && $0.sessionType == .game && !SessionLifecycle.didNotHappen($0) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Games with a score, newest first (the final-score picker).
    static func scored(of team: Team, in sessions: [SessionEvent]) -> [SessionEvent] {
        teamGames(of: team, in: sessions).filter { GameDay.score(of: $0) != nil }.reversed()
    }

    /// Games still to come, soonest first (the game-day picker).
    static func upcoming(of team: Team, in sessions: [SessionEvent], now: Date = .now) -> [SessionEvent] {
        teamGames(of: team, in: sessions).filter { $0.endTime >= now && $0.status != .completed }
    }

    static func make(kind: Kind, team: Team, game: SessionEvent?, sessions: [SessionEvent],
                     academy: String, chinese: Bool) -> TeamPostFacts {
        var f = TeamPostFacts(kind: kind, teamName: team.name,
                              shortName: team.shortName.isEmpty ? initials(team.name) : team.shortName,
                              colorHex: team.colorHex, academy: academy, chinese: chinese)
        switch kind {
        case .final, .gameDay:
            guard let game else { return f }
            let plan = game.curriculum.gamePlan ?? GamePlan()
            f.opponent = plan.opponentName(chinese: chinese)
            f.isHome = plan.isHome
            f.date = game.startTime
            f.venue = game.location ?? ""
            if let score = GameDay.score(of: game) {
                f.ours = score.ours; f.theirs = score.theirs; f.isFinal = score.isFinal
            }
        case .season:
            let finals = teamGames(of: team, in: sessions).compactMap { g -> (SessionEvent, GameDayScore)? in
                guard let s = GameDay.score(of: g), s.isFinal else { return nil }
                return (g, s)
            }
            f.games = finals.count
            guard !finals.isEmpty else { return f }
            f.wins = finals.filter { $0.1.won }.count
            f.ties = finals.filter { $0.1.tied }.count
            f.losses = finals.count - f.wins - f.ties
            f.pointsFor = Double(finals.reduce(0) { $0 + $1.1.ours }) / Double(finals.count)
            f.pointsAgainst = Double(finals.reduce(0) { $0 + $1.1.theirs }) / Double(finals.count)
            f.recent = finals.reversed().prefix(5).map { $0.1.won ? "W" : ($0.1.tied ? "T" : "L") }
            f.firstDate = finals.first?.0.startTime
            f.lastDate = finals.last?.0.startTime
        }
        return f
    }
}
