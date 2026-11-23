import Foundation

// GAME DAY (23 Nov 2026, Luther, markup on the team page: "add a game day
// card where I can plan and schedule a game"; decided: the plan holds the
// lineup, the plays to run, keys to the game and opponent notes; a game is a
// SESSION — in the calendar and on Home, attendance never billed, scored
// live against the opponent's score).
//
// A game is a session of type `.game` that names its team
// (`curriculum.teamId`), created through SessionCreation with no program —
// like a team practice. Its plan rides in the curriculum JSON (`gamePlan`),
// its plays in `curriculum.plays`: no schema change.

/// What the coach plans for one game.
nonisolated struct GamePlan: Codable, Hashable, Sendable {
    var opponent = ""
    var isHome = true
    /// Who starts, in order. Everyone else on the roster is the bench.
    var starters: [UUID] = []
    /// Keys to the game — short points for the team.
    var keys: [String] = []
    /// Who they are and what to watch for.
    var opponentNotes = ""

    init() {}

    private enum CodingKeys: String, CodingKey { case opponent, isHome, starters, keys, opponentNotes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opponent = try c.decodeIfPresent(String.self, forKey: .opponent) ?? ""
        isHome = try c.decodeIfPresent(Bool.self, forKey: .isHome) ?? true
        starters = try c.decodeIfPresent([UUID].self, forKey: .starters) ?? []
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        opponentNotes = try c.decodeIfPresent(String.self, forKey: .opponentNotes) ?? ""
    }

    /// The opponent has no players in the app: one fixed id names "them" in
    /// every game's teams, so a game's score reads the same on any device.
    static let opponentTeamId = UUID(uuidString: "0B0B0B0B-0000-4000-8000-0000000000FF")!

    var cleanKeys: [String] { keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }

    func opponentName(chinese: Bool) -> String {
        let name = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (chinese ? "对手" : "Opponent") : name
    }

    /// "<team> vs <opponent>" / "<team> @ <opponent>".
    func title(team: String, chinese: Bool) -> String {
        "\(team) \(isHome ? "vs" : "@") \(opponentName(chinese: chinese))"
    }
}

/// A game's score so far: every played period added up.
nonisolated struct GameDayScore: Hashable, Sendable {
    var ours: Int
    var theirs: Int
    /// Every period has been ended.
    var isFinal: Bool

    var won: Bool { ours > theirs }
    var tied: Bool { ours == theirs }
    /// "W 34–28" / "L 20–31" / "T 18–18" / "34–28" while it runs.
    func text(chinese: Bool) -> String {
        let score = "\(ours)–\(theirs)"
        guard isFinal else { return score }
        if tied { return (chinese ? "平 " : "T ") + score }
        return (won ? (chinese ? "胜 " : "W ") : (chinese ? "负 " : "L ")) + score
    }
}

nonisolated enum GameDay {
    /// The game's team as it plays: starters first (those who are in the
    /// pool), then everyone else, and the opponent with nobody.
    static func teams(team: Team, plan: GamePlan, pool: [UUID], chinese: Bool) -> [GameTeam] {
        let starters = plan.starters.filter { pool.contains($0) }
        let bench = pool.filter { !starters.contains($0) }
        var ours = GameTeam(id: team.id, name: team.name, colorHex: team.colorHex, playerIds: starters + bench)
        ours.starters = starters.isEmpty ? min(5, pool.count) : starters.count
        let theirs = GameTeam(id: GamePlan.opponentTeamId, name: plan.opponentName(chinese: chinese), colorHex: "#8E8E93")
        return [ours, theirs]
    }

    /// The score over every period that was played (nil before the first).
    static func score(of session: SessionEvent) -> GameDayScore? {
        guard let teamId = session.curriculum.teamId else { return nil }
        let played = session.games.filter { game in
            // A period counts once its clock ran, or once anyone scored in it.
            guard game.teams.contains(where: { $0.id == GamePlan.opponentTeamId }) else { return false }
            let scored = game.score(for: teamId) + game.score(for: GamePlan.opponentTeamId) > 0
            return game.status == .inProgress || game.status == .paused || game.status == .completed || scored
        }
        guard !played.isEmpty else { return nil }
        return GameDayScore(ours: played.reduce(0) { $0 + $1.score(for: teamId) },
                            theirs: played.reduce(0) { $0 + $1.score(for: GamePlan.opponentTeamId) },
                            isFinal: played.allSatisfy { $0.status == .completed })
    }
}
