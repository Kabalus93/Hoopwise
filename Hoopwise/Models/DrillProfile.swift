import Foundation

// MARK: - Structured drill signals
//
// These types expose the metadata the plan generator cares about — age fit,
// focus areas, intensity, format, lineage. Rather than migrate SwiftData with
// five new fields we *derive* them from existing fields plus the free-form
// `tags` array. Coaches can author tags like `u12`, `intensity:high`,
// `source:feb` and the generator picks them up automatically.
//
// As the library grows, the seed file just needs to set the right tags. No
// schema changes; no migration.

enum DrillIntensity: String, Codable, CaseIterable {
    case low, medium, high

    var displayName: String { rawValue.capitalized }
}

enum DrillFormat: String, Codable, CaseIterable {
    case individual    // 1 player
    case smallGroup    // 2–4
    case team          // 5–10
    case fullCourt     // 10+ / scrimmage scale

    var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .smallGroup: return "Small Group"
        case .team:       return "Team"
        case .fullCourt:  return "Full Court"
        }
    }

    /// Headcount → preferred format. Used as the default when no format tag
    /// is present.
    static func inferred(min: Int, max: Int?) -> DrillFormat {
        let upper = max ?? min
        if upper <= 1 { return .individual }
        if upper <= 4 { return .smallGroup }
        if upper <= 10 { return .team }
        return .fullCourt
    }

    /// Whether this format can comfortably absorb a cohort of `count` players.
    /// Used to filter eligible drills before scoring.
    func fits(cohort count: Int) -> Bool {
        switch self {
        case .individual: return count >= 1
        case .smallGroup: return count >= 2 && count <= 8
        case .team:       return count >= 4
        case .fullCourt:  return count >= 6
        }
    }
}

enum DrillSource: String, Codable, CaseIterable {
    case febYouth         = "feb"
    case fibaDevelopment  = "fiba"
    case nbaPlayerDev     = "nba"
    case coachsClipboard  = "clipboard"
    case coachAuthored    = "coach"
    case unattributed     = "unattributed"

    var displayName: String {
        switch self {
        case .febYouth:        return "FEB Youth"
        case .fibaDevelopment: return "FIBA Development"
        case .nbaPlayerDev:    return "NBA Player Dev"
        case .coachsClipboard: return "Coach's Clipboard"
        case .coachAuthored:   return "Coach-authored"
        case .unattributed:    return "Library"
        }
    }
}

// MARK: - Profile

/// Structured view over a `DrillItem`'s metadata, used by the plan generator.
/// Built lazily; nothing is persisted on the drill itself.
struct DrillProfile {
    let drill: DrillItem
    let ageGroups: Set<AgeGroup>     // empty = applies to all ages
    let focus: Set<TrainingFocus>    // derived from category + tags
    let intensity: DrillIntensity
    let format: DrillFormat
    let source: DrillSource

    init(_ drill: DrillItem) {
        self.drill = drill
        self.ageGroups = Self.parseAgeGroups(from: drill.tags)
        self.focus = Self.parseFocus(category: drill.category, tags: drill.tags)
        self.intensity = Self.parseIntensity(category: drill.category,
                                             difficulty: drill.difficulty,
                                             tags: drill.tags)
        self.format = Self.parseFormat(min: drill.minPlayers,
                                       max: drill.maxPlayers,
                                       tags: drill.tags)
        self.source = Self.parseSource(from: drill.tags)
    }

    /// Convenience for collections.
    static func profiles(for drills: [DrillItem]) -> [DrillProfile] {
        drills.map(DrillProfile.init)
    }

    // MARK: Tag parsing

    /// Recognised tag keys. Coaches can author "u12" / "u-12" / "ages:u12".
    private static let agePattern = #"^(?:ages?:)?(u-?\d+|adult)$"#

    private static func parseAgeGroups(from tags: [String]) -> Set<AgeGroup> {
        var found: Set<AgeGroup> = []
        for raw in tags {
            let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "")
            if let ag = AgeGroup.from(rawTag: normalized) {
                found.insert(ag)
            }
        }
        return found
    }

    private static func parseFocus(category: DrillCategory, tags: [String]) -> Set<TrainingFocus> {
        // Start with the focus implied by the category — most drills have one
        // dominant theme that matches the category.
        var focus: Set<TrainingFocus> = []
        switch category {
        case .shooting:     focus.insert(.shooting)
        case .offense:      focus.insert(.teamPlay); focus.insert(.passing)
        case .defense:      focus.insert(.defense)
        case .skills:       focus.insert(.ballHandling)
        case .conditioning: focus.insert(.conditioning)
        case .warmup:       focus.insert(.conditioning)
        case .cooldown:     focus.insert(.recovery)
        }
        // Tags can add further focus areas explicitly.
        for raw in tags {
            let t = raw.lowercased().replacingOccurrences(of: " ", with: "-")
            switch t {
            case "shooting", "shoot", "form-shooting": focus.insert(.shooting)
            case "ball-handling", "ballhandling", "handles", "dribbling": focus.insert(.ballHandling)
            case "passing", "pass": focus.insert(.passing)
            case "defense", "defensive", "defending": focus.insert(.defense)
            case "conditioning", "endurance", "fitness": focus.insert(.conditioning)
            case "team-play", "teamplay", "team", "5v5": focus.insert(.teamPlay)
            case "game-prep", "gameprep", "scrimmage": focus.insert(.gamePrep)
            case "recovery", "cooldown", "stretch", "mobility": focus.insert(.recovery)
            default: break
            }
        }
        return focus
    }

    private static func parseIntensity(category: DrillCategory,
                                       difficulty: DifficultyLevel,
                                       tags: [String]) -> DrillIntensity {
        // Explicit tag wins.
        for raw in tags {
            let t = raw.lowercased()
            if t.hasPrefix("intensity:") {
                let value = String(t.dropFirst("intensity:".count))
                if let i = DrillIntensity(rawValue: value) { return i }
            }
        }
        // Otherwise infer from category + difficulty.
        switch category {
        case .cooldown: return .low
        case .warmup:   return .low
        case .conditioning: return .high
        default: break
        }
        switch difficulty {
        case .beginner:     return .low
        case .intermediate: return .medium
        case .advanced:     return .high
        }
    }

    private static func parseFormat(min: Int, max: Int?, tags: [String]) -> DrillFormat {
        for raw in tags {
            let t = raw.lowercased()
            if t.hasPrefix("format:") {
                let value = String(t.dropFirst("format:".count))
                if let f = DrillFormat(rawValue: value) { return f }
                // Friendly aliases.
                switch value {
                case "1v1", "individual", "solo": return .individual
                case "small-group", "smallgroup", "2v2", "3v3": return .smallGroup
                case "5v5", "scrimmage", "team": return .team
                case "fullcourt", "full-court": return .fullCourt
                default: break
                }
            }
        }
        return DrillFormat.inferred(min: min, max: max)
    }

    private static func parseSource(from tags: [String]) -> DrillSource {
        for raw in tags {
            let t = raw.lowercased()
            if t.hasPrefix("source:") {
                let value = String(t.dropFirst("source:".count))
                if let s = DrillSource(rawValue: value) { return s }
            }
        }
        return .unattributed
    }
}

// MARK: - AgeGroup tag parsing
extension AgeGroup {
    /// Parse common tag forms — "u12", "u-12", "u8", "adult". Returns nil if
    /// the tag isn't an age tag.
    static func from(rawTag: String) -> AgeGroup? {
        let trimmed = rawTag
            .replacingOccurrences(of: "ages:", with: "")
            .replacingOccurrences(of: "age:", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch trimmed {
        case "u6":  return .u6
        case "u8":  return .u8
        case "u10": return .u10
        case "u12": return .u12
        case "u14": return .u14
        case "u16": return .u16
        case "u18": return .u18
        case "adult", "senior", "pro": return .adult
        default: return nil
        }
    }

    /// Numeric upper bound — used by the generator to score age proximity.
    var ceilingAge: Int {
        switch self {
        case .u6: return 6
        case .u8: return 8
        case .u10: return 10
        case .u12: return 12
        case .u14: return 14
        case .u16: return 16
        case .u18: return 18
        case .adult: return 25
        }
    }
}
