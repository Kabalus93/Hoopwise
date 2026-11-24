import Foundation

// HOW THE COACH USES A DRILL (19 Nov 2026, Luther: "a way to rate drills so
// that the engine knows to use more often or never … some drills are way too
// easy and boring, not challenging enough, or no kids are at that stage of
// learning … the engine learns my way of coaching").
//
// Stored in the drill's synced tags — no schema change — as `pref:use=<…>`
// and `pref:why=<…>`. Library drills keep them through the launch refresh
// (syncActivityLibrary), and setting one is not an edit of the drill, so the
// library still refreshes its text.

enum DrillPreference: String, CaseIterable, Identifiable {
    /// Plan it whenever it fits.
    case more
    case normal
    /// Plan it only when little else fits.
    case less
    /// Never planned by the engine (still pickable by hand).
    case never

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .more: chinese ? "多用" : "Use more"
        case .normal: chinese ? "正常" : "Normal"
        case .less: chinese ? "少用" : "Use less"
        case .never: chinese ? "不用" : "Never"
        }
    }

    var icon: String {
        switch self {
        case .more: "hand.thumbsup.fill"
        case .normal: "circle"
        case .less: "arrow.down.circle"
        case .never: "nosign"
        }
    }
}

/// Why the coach turned a drill down.
enum DrillPreferenceReason: String, CaseIterable, Identifiable {
    case tooEasy, tooHard, boring, notNow

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .tooEasy: chinese ? "太简单" : "Too easy"
        case .tooHard: chinese ? "太难" : "Too hard"
        case .boring: chinese ? "无聊" : "Boring"
        case .notNow: chinese ? "暂时没有孩子到这个阶段" : "No one at that stage yet"
        }
    }
}

extension DrillItem {
    static let preferencePrefix = "pref:"
    private static let useKey = "pref:use="
    private static let whyKey = "pref:why="

    var preference: DrillPreference {
        tags.first { $0.hasPrefix(Self.useKey) }
            .flatMap { DrillPreference(rawValue: String($0.dropFirst(Self.useKey.count))) } ?? .normal
    }

    var preferenceReason: DrillPreferenceReason? {
        tags.first { $0.hasPrefix(Self.whyKey) }
            .flatMap { DrillPreferenceReason(rawValue: String($0.dropFirst(Self.whyKey.count))) }
    }

    /// `tags` with this preference (normal and no reason write nothing; a
    /// reason only goes with less / never).
    static func tags(_ tags: [String], preference: DrillPreference, reason: DrillPreferenceReason?) -> [String] {
        var out = tags.filter { !$0.hasPrefix(preferencePrefix) }
        if preference != .normal { out.append(useKey + preference.rawValue) }
        if let reason, preference == .less || preference == .never { out.append(whyKey + reason.rawValue) }
        return out
    }
}

extension DrillPreference {
    /// How the plan engine weighs a drill: never is left out entirely
    /// (nil); use more adds, use less takes most of its chance away.
    func adjusted(_ score: Double) -> Double? {
        switch self {
        case .more: score + 2.5
        case .normal: score
        case .less: score * 0.25
        case .never: nil
        }
    }
}

extension DrillItem {
    /// THE REASON STEERS THE ENGINE (25 Nov 2026, Luther, after the audit:
    /// reasons were recorded and never read). A "use less" rating is about
    /// LEVEL when its reason is: too easy does not hold for a weaker group
    /// (training level 1–2), too hard / no one at that stage yet does not
    /// hold for a stronger one (level 4–5) — there the drill is planned
    /// normally. Boring is boring at any level; never stays never.
    func preference(atLevel level: Int) -> DrillPreference {
        guard preference == .less else { return preference }
        switch preferenceReason {
        case .tooEasy: return level <= 2 ? .normal : .less
        case .tooHard, .notNow: return level >= 4 ? .normal : .less
        case .boring, nil: return .less
        }
    }
}

/// What the coach's reasons say about the training LEVEL at one age.
nonisolated enum DrillLevelHint: Equatable {
    case raise(Int), lower(Int)

    /// At least three drills turned down for one reason, and clearly more
    /// than for the opposite reason.
    static func make(tooEasy: Int, tooHard: Int) -> DrillLevelHint? {
        if tooEasy >= 3, tooEasy >= tooHard + 2 { return .raise(tooEasy) }
        if tooHard >= 3, tooHard >= tooEasy + 2 { return .lower(tooHard) }
        return nil
    }
}
