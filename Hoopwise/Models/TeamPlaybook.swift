import SwiftUI

// A team's playbook (Hub → Teams, November 2026, Luther: "the plays we
// practice and run — our base offense, BLOB, SLOB, transition, what we play
// against zone, defense philosophy and schemes"). Each section holds plays
// from the Plays library (found by `SessionPlayRef`, as session plans do) and
// the coach's own notes. Stored as JSON in `SDTeam.playbookData`.

struct TeamPlaybook: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case baseOffense, transition, vsZone, blob, slob, pressBreak, defense, other

        var id: String { rawValue }

        var title: String {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .baseOffense: return zh ? "基础进攻" : "Base offense"
            case .transition: return zh ? "攻防转换" : "Transition"
            case .vsZone: return zh ? "打联防" : "Against zone"
            case .blob: return zh ? "底线发球（BLOB）" : "BLOB"
            case .slob: return zh ? "边线发球（SLOB）" : "SLOB"
            case .pressBreak: return zh ? "破紧逼" : "Press break"
            case .defense: return zh ? "防守" : "Defense"
            case .other: return zh ? "其他" : "Other"
            }
        }

        /// What the section is for, under its title.
        var hint: String {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .baseOffense: return zh ? "半场的主要进攻体系" : "What we run in the half court"
            case .transition: return zh ? "快攻与早期进攻" : "Fast break and early offense"
            case .vsZone: return zh ? "对付区域联防的打法" : "What we run against a zone"
            case .blob: return zh ? "底线界外球战术" : "Baseline out of bounds"
            case .slob: return zh ? "边线界外球战术" : "Sideline out of bounds"
            case .pressBreak: return zh ? "对付全场紧逼" : "Against full-court pressure"
            case .defense: return zh ? "防守理念与体系" : "Philosophy and schemes"
            case .other: return zh ? "特殊战术、末节、其他记录" : "Specials, late game, anything else"
            }
        }

        var icon: String {
            switch self {
            case .baseOffense: return "sportscourt"
            case .transition: return "hare"
            case .vsZone: return "square.grid.3x3"
            case .blob: return "arrow.up.to.line"
            case .slob: return "arrow.right.to.line"
            case .pressBreak: return "arrow.up.forward"
            case .defense: return "shield.lefthalf.filled"
            case .other: return "ellipsis.circle"
            }
        }

        var tint: Color {
            switch self {
            case .baseOffense: return .orange
            case .transition: return .green
            case .vsZone: return .purple
            case .blob, .slob: return .blue
            case .pressBreak: return .pink
            case .defense: return .teal
            case .other: return .gray
            }
        }
    }

    struct Section: Codable, Equatable {
        var plays: [SessionPlayRef] = []
        var notes: String = ""
        var isEmpty: Bool { plays.isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Stored by kind's raw value so a kind added later decodes in old data.
    var sections: [String: Section] = [:]
    /// The team's identity in a line or two ("Pace and space, switch 1–4").
    var identity: String = ""
    /// What the team works on now — one set for the team, shown at the top
    /// of every team practice's Plan.
    var objectives: [String] = []
    /// Plays broken down into numbered roles, keyed by the play's
    /// `SessionPlayRef.key`.
    var breakdowns: [String: PlayBreakdown] = [:]
    /// The plays practice works on NOW (their `SessionPlayRef.key`s) — what a
    /// team practice's plan is built from (Luther, November 2026: "a
    /// relationship between the team's composition and settings in the hub
    /// and the plan appearing in session").
    var focus: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case sections, identity, objectives, breakdowns, focus }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = try c.decodeIfPresent([String: Section].self, forKey: .sections) ?? [:]
        identity = try c.decodeIfPresent(String.self, forKey: .identity) ?? ""
        objectives = try c.decodeIfPresent([String].self, forKey: .objectives) ?? []
        breakdowns = try c.decodeIfPresent([String: PlayBreakdown].self, forKey: .breakdowns) ?? [:]
        focus = try c.decodeIfPresent([String].self, forKey: .focus) ?? []
    }

    subscript(kind: Kind) -> Section {
        get { sections[kind.rawValue] ?? Section() }
        set { sections[kind.rawValue] = newValue.isEmpty ? nil : newValue }
    }

    var playCount: Int { Kind.allCases.reduce(0) { $0 + self[$1].plays.count } }
}

extension Team {
    var playbook: TeamPlaybook {
        get { playbookData.flatMap { try? JSONDecoder().decode(TeamPlaybook.self, from: $0) } ?? TeamPlaybook() }
        set { playbookData = try? JSONEncoder().encode(newValue) }
    }
}

// MARK: - Standards: a play broken down into numbered roles

/// What a play asks of each player (Luther, November 2026: "break down what
/// skill each player needs per position or action so that I can assign skill
/// workouts … based on what we run"). Roles are the play's NUMBERED players
/// (Luther: numbered roles). Each holds the skills it needs (the drill
/// library's activity types), the drills that build them, one line of
/// standard, and who on the team plays it.
struct PlayBreakdown: Codable, Equatable {
    struct Role: Codable, Equatable, Identifiable {
        var number: Int
        var standard: String = ""
        /// `ActivityType` raw values.
        var skills: [String] = []
        var drillIds: [UUID] = []
        var playerIds: [UUID] = []
        var id: Int { number }
    }

    /// The play's name when it was broken down, for a play since deleted.
    var playName: String
    var roles: [Role] = []
}

extension TeamPlaybook {
    /// A player's workout: every drill of every role they play, in playbook
    /// order, each with where it comes from ("Triangle · 4").
    struct WorkoutItem: Identifiable, Equatable {
        let drillId: UUID
        var sources: [String]
        var id: UUID { drillId }
    }

    func workout(for playerId: UUID) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        for key in orderedBreakdownKeys {
            guard let breakdown = breakdowns[key] else { continue }
            for role in breakdown.roles where role.playerIds.contains(playerId) {
                let source = "\(breakdown.playName) · \(role.number)"
                for drill in role.drillIds {
                    if let i = items.firstIndex(where: { $0.drillId == drill }) {
                        if !items[i].sources.contains(source) { items[i].sources.append(source) }
                    } else {
                        items.append(WorkoutItem(drillId: drill, sources: [source]))
                    }
                }
            }
        }
        return items
    }

    /// The roles a player is assigned to ("Triangle · 4").
    func roles(of playerId: UUID) -> [String] {
        orderedBreakdownKeys.flatMap { key -> [String] in
            guard let b = breakdowns[key] else { return [] }
            return b.roles.filter { $0.playerIds.contains(playerId) }.map { "\(b.playName) · \($0.number)" }
        }
    }

    /// The skills the playbook asks for, most demanded first, each with the
    /// roles that need it.
    struct SkillDemand: Identifiable, Equatable {
        let skill: String
        var roles: [String]
        var id: String { skill }
    }

    var skillDemands: [SkillDemand] {
        var bySkill: [String: [String]] = [:]
        for key in orderedBreakdownKeys {
            guard let b = breakdowns[key] else { continue }
            for role in b.roles {
                for skill in role.skills { bySkill[skill, default: []].append("\(b.playName) · \(role.number)") }
            }
        }
        return bySkill.map { SkillDemand(skill: $0.key, roles: $0.value) }
            .sorted { $0.roles.count != $1.roles.count ? $0.roles.count > $1.roles.count : $0.skill < $1.skill }
    }

    /// Breakdown keys in the order their plays sit in the playbook.
    private var orderedBreakdownKeys: [String] {
        var keys: [String] = []
        for kind in Kind.allCases {
            for ref in self[kind].plays where breakdowns[ref.key] != nil && !keys.contains(ref.key) { keys.append(ref.key) }
        }
        return keys + breakdowns.keys.filter { !keys.contains($0) }.sorted()
    }
}

// MARK: - Focus → the team practice plan

extension TeamPlaybook {
    /// Every play in the playbook, in section order, once.
    var allPlays: [(kind: Kind, ref: SessionPlayRef)] {
        var seen = Set<String>()
        var out: [(Kind, SessionPlayRef)] = []
        for kind in Kind.allCases {
            for ref in self[kind].plays where seen.insert(ref.key).inserted { out.append((kind, ref)) }
        }
        return out
    }

    /// The focus plays still in the playbook, in playbook order.
    var focusPlays: [SessionPlayRef] {
        let keys = Set(focus)
        return allPlays.map(\.ref).filter { keys.contains($0.key) }
    }

    /// One person's part in the given plays: each role they play, with the
    /// play's name.
    struct Part: Equatable {
        let playName: String
        let role: PlayBreakdown.Role
    }

    func parts(of playerId: UUID, in plays: [SessionPlayRef]) -> [Part] {
        plays.flatMap { ref -> [Part] in
            guard let breakdown = breakdowns[ref.key] else { return [] }
            return breakdown.roles.filter { $0.playerIds.contains(playerId) }
                .map { Part(playName: ref.name.isEmpty ? breakdown.playName : ref.name, role: $0) }
        }
    }

    /// Skills the plays' roles need, most needed first.
    func skills(in plays: [SessionPlayRef]) -> [String] {
        var count: [String: Int] = [:]
        var order: [String] = []
        for ref in plays {
            for role in breakdowns[ref.key]?.roles ?? [] {
                for skill in role.skills {
                    if count[skill] == nil { order.append(skill) }
                    count[skill, default: 0] += 1
                }
            }
        }
        return order.enumerated()
            .sorted { (count[$0.element]!, -$0.offset) > (count[$1.element]!, -$1.offset) }
            .map(\.element)
    }

    /// The practice built from the plays: their role drills as Skills (play
    /// order, each once), a warm-up of up to two routine library drills for
    /// the skills they need (oldest age first — a team is not a U8 class),
    /// the plays themselves, and minutes split over the session.
    func practicePlan(plays: [SessionPlayRef], drills: [DrillItem], durationMinutes: Int,
                      keeping current: SessionCurriculum) -> SessionCurriculum {
        var plan = current
        var skillIds: [UUID] = []
        for ref in plays {
            for role in breakdowns[ref.key]?.roles ?? [] {
                for id in role.drillIds where !skillIds.contains(id) { skillIds.append(id) }
            }
        }
        let wanted = skills(in: plays)
        let ages = ActivityAge.allCases
        let routine = drills.filter { $0.tags.contains("block:routine") }
            .sorted { a, b in
                let ra = a.libraryActivity.map { ages.firstIndex(of: $0.age) ?? 0 } ?? -1
                let rb = b.libraryActivity.map { ages.firstIndex(of: $0.age) ?? 0 } ?? -1
                return ra != rb ? ra > rb : a.name < b.name
            }
        var warmup: [UUID] = []
        for skill in wanted + ["warmup"] where warmup.count < 2 {
            if let drill = routine.first(where: { $0.tags.contains("type:\(skill)") && !warmup.contains($0.id) && !skillIds.contains($0.id) }) {
                warmup.append(drill.id)
            }
        }
        plan.warmupDrillIds = warmup
        plan.skillDrillIds = skillIds
        var refs = plan.plays
        for ref in plays where !refs.contains(where: { $0.key == ref.key }) { refs.append(ref) }
        plan.plays = refs
        let total = max(durationMinutes, 30)
        plan.warmupMinutes = min(15, total / 4)
        plan.skillsMinutes = (total - plan.warmupMinutes) / 2
        return plan
    }
}
