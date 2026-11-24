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
    /// Substitutions planned ahead: who comes in, for whom, about when.
    var subs: [PlannedSub] = []
    /// The defense the team means to play, and a line on how.
    var defense: GameDefense?
    var defenseNote = ""
    /// Their players to watch, and who guards each.
    var threats: [OpponentPlayer] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case opponent, isHome, starters, keys, opponentNotes, subs, defense, defenseNote, threats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opponent = try c.decodeIfPresent(String.self, forKey: .opponent) ?? ""
        isHome = try c.decodeIfPresent(Bool.self, forKey: .isHome) ?? true
        starters = try c.decodeIfPresent([UUID].self, forKey: .starters) ?? []
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        opponentNotes = try c.decodeIfPresent(String.self, forKey: .opponentNotes) ?? ""
        // Added 24 Nov 2026 — older plans have none; a value this build does
        // not know reads as unset instead of failing the whole plan.
        subs = (try? c.decodeIfPresent([PlannedSub].self, forKey: .subs)) ?? []
        defense = (try? c.decodeIfPresent(String.self, forKey: .defense)).flatMap { $0 }.flatMap(GameDefense.init)
        defenseNote = (try? c.decodeIfPresent(String.self, forKey: .defenseNote)) ?? ""
        threats = (try? c.decodeIfPresent([OpponentPlayer].self, forKey: .threats)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(opponent, forKey: .opponent)
        try c.encode(isHome, forKey: .isHome)
        try c.encode(starters, forKey: .starters)
        try c.encode(keys, forKey: .keys)
        try c.encode(opponentNotes, forKey: .opponentNotes)
        // Written only when used, so a plan without them is unchanged.
        if !subs.isEmpty { try c.encode(subs, forKey: .subs) }
        if let defense { try c.encode(defense.rawValue, forKey: .defense) }
        if !defenseNote.isEmpty { try c.encode(defenseNote, forKey: .defenseNote) }
        if !threats.isEmpty { try c.encode(threats, forKey: .threats) }
    }

    /// The planned subs that still make sense: the player coming in is on the
    /// roster and not a starter; a starter named to come out still starts.
    func validSubs(roster: [UUID]) -> [PlannedSub] {
        subs.compactMap { sub in
            guard roster.contains(sub.playerIn), !starters.contains(sub.playerIn) else { return nil }
            var s = sub
            if let out = s.playerOut, !starters.contains(out) { s.playerOut = nil }
            return s
        }
    }

    /// Their players that say something: a number or a note.
    var cleanThreats: [OpponentPlayer] {
        threats.filter { !$0.number.trimmingCharacters(in: .whitespaces).isEmpty
            || !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

/// One substitution planned before the game.
nonisolated struct PlannedSub: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var playerIn: UUID
    /// nil = whoever needs a rest.
    var playerOut: UUID?
    /// "Mid first half", "After 5 minutes" — the coach's words.
    var when = ""
    /// PROMPT (24 Nov 2026, Luther: "make the live scoring screen prompt the
    /// planned subs"): the period it belongs to (nil = any) and the minute
    /// of that period's clock at which the live screen calls for it
    /// (nil = no moment: it is listed from the period's start).
    var period: Int?
    var minute: Int?

    /// Listed on the live screen in this period: no period named, or this
    /// one, or an earlier one it was not made in.
    func shows(inPeriod current: Int) -> Bool { period.map { $0 <= current } ?? true }

    /// The moment has come: an earlier period's sub is overdue; with a
    /// minute, once the clock reaches it; a period alone, from its start.
    /// A sub with neither is never "due" — it only waits in the list.
    func isDue(period current: Int, elapsedSeconds: Int) -> Bool {
        if let period, period < current { return true }
        if let period, period > current { return false }
        if let minute { return elapsedSeconds >= minute * 60 }
        return period != nil
    }

    /// The coach's words and the prompt together: "Mid first half · P1 · 4:00".
    var whenLine: String {
        [when.trimmingCharacters(in: .whitespacesAndNewlines), promptLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "P2 · 4:00", "P1", "4:00" — nil without a prompt.
    var promptLabel: String? {
        let parts = [period.map { "P\($0)" }, minute.map { "\($0):00" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Which planned subs the live screen shows for a team right now.
nonisolated enum PlannedSubPrompts {
    /// Not made yet, in this period's list, the player still on the bench —
    /// due ones first, then in the plan's order.
    static func pending(_ subs: [PlannedSub], done: [UUID], floor: [UUID], bench: [UUID],
                        period: Int, elapsedSeconds: Int) -> [PlannedSub] {
        let open = subs.filter { !done.contains($0.id) && $0.shows(inPeriod: period) && bench.contains($0.playerIn) }
        let due = open.filter { $0.isDue(period: period, elapsedSeconds: elapsedSeconds) }
        return due + open.filter { sub in !due.contains { $0.id == sub.id } }
    }
}

/// The defense the team means to play.
nonisolated enum GameDefense: String, Codable, CaseIterable, Sendable, Identifiable {
    case man, zone23, zone32, press, mixed
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .man: return chinese ? "人盯人" : "Man to man"
        case .zone23: return chinese ? "2-3 联防" : "2-3 zone"
        case .zone32: return chinese ? "3-2 联防" : "3-2 zone"
        case .press: return chinese ? "全场紧逼" : "Full-court press"
        case .mixed: return chinese ? "混合防守" : "Mixed"
        }
    }
}

/// One of their players to watch.
nonisolated struct OpponentPlayer: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    /// Jersey number, as written ("7", "#23").
    var number = ""
    /// What to know: "left hand, shoots from the corner".
    var note = ""
    /// Who of ours guards them.
    var guardedBy: UUID?

    var label: String {
        let n = number.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "" : (n.hasPrefix("#") ? n : "#" + n)
    }
}

/// The game's plays, sorted by the situation the team's playbook files them
/// under — what the coach calls from the bench.
enum GameCalls {
    struct Group: Identifiable {
        /// nil = plays the playbook does not hold.
        let kind: TeamPlaybook.Kind?
        let plays: [SessionPlayRef]
        var id: String { kind?.rawValue ?? "none" }
        func title(chinese: Bool) -> String { kind?.title ?? (chinese ? "其他战术" : "Other plays") }
    }

    static func groups(plays: [SessionPlayRef], playbook: TeamPlaybook?) -> [Group] {
        var left = plays
        var out: [Group] = []
        if let playbook {
            for kind in TeamPlaybook.Kind.allCases {
                let keys = Set(playbook[kind].plays.map(\.key))
                let here = left.filter { keys.contains($0.key) }
                guard !here.isEmpty else { continue }
                out.append(Group(kind: kind, plays: here))
                left.removeAll { keys.contains($0.key) }
            }
        }
        if !left.isEmpty { out.append(Group(kind: nil, plays: left)) }
        return out
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
