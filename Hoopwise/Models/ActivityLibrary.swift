import Foundation
import CryptoKit

// MARK: - Activity library (October 2026, Luther)
//
// THE drill library. Every activity comes from Luther's sourced "Activity
// Library: U6 to U16" document (FIBA, Jr. NBA, USA Basketball, …), split by
// AGE and by the session BLOCK it belongs to, with an activity TYPE inside.
// It replaced the 121 bundled sample drills.
//
// Activities and games are seeded as ordinary SDDrill records (so plans,
// favourites and media keep working) with DETERMINISTIC ids derived from the
// item's key — every device seeds the same id, and a session plan written on
// the phone resolves on the Mac. Rule options are NOT drills: they are read
// from the library directly and never reach session planning.

enum ActivityAge: String, CaseIterable, Codable, Identifiable {
    case u6 = "U6", u7 = "U7", u8 = "U8", u10 = "U10", u12 = "U12", u14 = "U14", u16 = "U16"
    var id: String { rawValue }

    /// "U6 and under" is how the library names its first tab.
    var title: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        if self == .u6 { return zh ? "U6及以下" : "U6 & under" }
        return rawValue
    }

    /// The tag the session-plan generator reads (`DrillProfile`). It has no
    /// U7 group, so U7 activities plan as U8 (FIBA's 5–7 band overlaps both).
    var plannerTag: String {
        switch self {
        case .u6: return "u6"
        case .u7, .u8: return "u8"
        case .u10: return "u10"
        case .u12: return "u12"
        case .u14: return "u14"
        case .u16: return "u16"
        }
    }

    var difficulty: DifficultyLevel {
        switch self {
        case .u6, .u7, .u8: return .beginner
        case .u10, .u12: return .intermediate
        case .u14, .u16: return .advanced
        }
    }

    /// This age and every younger one — the library says each tab adds to
    /// the ones before it.
    var upToHere: [ActivityAge] {
        Array(Self.allCases.prefix(through: Self.allCases.firstIndex(of: self)!))
    }
}

/// The four blocks of a session, as the library is organised.
enum ActivityBlock: String, CaseIterable, Codable, Identifiable {
    case routine, smallGames, compete, game
    var id: String { rawValue }

    var title: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .routine: return zh ? "常规" : "Routine"
        case .smallGames: return zh ? "小游戏" : "Small games"
        case .compete: return zh ? "对抗" : "Compete"
        case .game: return zh ? "比赛" : "Game"
        }
    }
}

/// The library's 55 sub-headings, folded into 15 types (U6's untitled
/// movement-and-ball rows are "Ball & movement").
enum ActivityType: String, CaseIterable, Codable, Identifiable {
    case warmup, ballMovement, dribbling, passing, footwork, layups, shooting, rebounding
    case oneOnOne, defence, teamPlay, post, guards, games, rules
    var id: String { rawValue }

    var title: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .warmup: return zh ? "热身" : "Warm-up"
        case .ballMovement: return zh ? "球感与移动" : "Ball & movement"
        case .dribbling: return zh ? "运球" : "Dribbling"
        case .passing: return zh ? "传球" : "Passing"
        case .footwork: return zh ? "急停与转身" : "Stops & pivots"
        case .layups: return zh ? "上篮" : "Lay-ups"
        case .shooting: return zh ? "投篮" : "Shooting"
        case .rebounding: return zh ? "篮板" : "Rebounding"
        case .oneOnOne: return zh ? "一对一" : "1 on 1"
        case .defence: return zh ? "防守" : "Defence"
        case .teamPlay: return zh ? "团队配合" : "Team play"
        case .post: return zh ? "内线" : "Post / bigs"
        case .guards: return zh ? "后卫" : "Guards"
        case .games: return zh ? "游戏" : "Games"
        case .rules: return zh ? "规则选项" : "Rule options"
        }
    }

    var icon: String {
        switch self {
        case .warmup: return "flame"
        case .ballMovement: return "figure.run"
        case .dribbling: return "basketball"
        case .passing: return "arrow.left.arrow.right"
        case .footwork: return "figure.walk"
        case .layups: return "arrow.up.forward"
        case .shooting: return "target"
        case .rebounding: return "arrow.down.to.line"
        case .oneOnOne: return "person.2"
        case .defence: return "shield"
        case .teamPlay: return "person.3"
        case .post: return "square.dashed"
        case .guards: return "figure.basketball"
        case .games: return "flag.checkered"
        case .rules: return "list.bullet.rectangle"
        }
    }

    /// The legacy category every drill still carries (planner focus, Mac UI).
    var category: DrillCategory {
        switch self {
        case .warmup: return .warmup
        case .ballMovement, .dribbling, .passing, .footwork: return .skills
        case .layups, .shooting: return .shooting
        case .rebounding, .defence: return .defense
        case .oneOnOne, .teamPlay, .post, .guards, .games, .rules: return .offense
        }
    }
}

/// One row of the library.
struct LibraryActivity: Codable, Identifiable, Hashable {
    /// "<age>|<block>|<name>" — unique and stable; the drill id derives from it.
    let key: String
    let age: ActivityAge
    let block: ActivityBlock
    let type: ActivityType
    /// The library's own sub-heading, kept for reference.
    let group: String?
    /// activity | game | rule
    let kind: String
    let name: String
    /// Chinese title (October 2026 translation, natural coaching Chinese).
    let nameZh: String?
    /// FIBA's own Chinese-edition name, kept when the translation improved
    /// on it, so a coach can still find the page in FIBA's Chinese manual.
    let fibaNameZh: String?
    let howItRuns: String
    let howItRunsZh: String?
    /// The source cell as written (markdown links kept).
    let source: String
    let sourceUrl: String?

    var id: UUID { ActivityLibrary.drillId(forKey: key) }
    var isRule: Bool { kind == "rule" }

    /// Chinese name in Chinese, when the library has one.
    var displayName: String {
        if LocalizationManager.shared.currentLanguage == .chinese, let nameZh, !nameZh.isEmpty { return nameZh }
        return name
    }

    /// "How it runs" in the app's language.
    var localizedHowItRuns: String {
        if LocalizationManager.shared.currentLanguage == .chinese, let howItRunsZh, !howItRunsZh.isEmpty { return howItRunsZh }
        return howItRuns
    }

    /// The source without markdown link syntax ("Jr. NBA Rookie Plan 5, 7").
    var sourceText: String {
        source.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
    }
}

/// One age tab: its guidance bullets.
struct LibraryTab: Codable, Hashable {
    let age: ActivityAge
    let title: String
    let guidance: [String]
    let titleZh: String?
    let guidanceZh: [String]?

    var localizedGuidance: [String] {
        if LocalizationManager.shared.currentLanguage == .chinese, let guidanceZh, guidanceZh.count == guidance.count {
            return guidanceZh
        }
        return guidance
    }
}

struct ActivityLibrary: Codable {
    let version: Int
    let tabs: [LibraryTab]
    let items: [LibraryActivity]

    static let shared: ActivityLibrary = {
        do {
            return try JSONDecoder().decode(ActivityLibrary.self, from: Data(embeddedJSON.utf8))
        } catch {
            assertionFailure("Activity library failed to decode: \(error)")
            return ActivityLibrary(version: 0, tabs: [], items: [])
        }
    }()

    /// Tag every library drill carries, plus its own `library:<key>` tag.
    static let tag = "library"

    private static let byId: [UUID: LibraryActivity] = Dictionary(
        shared.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// The library row a drill was seeded from, if any.
    static func activity(forDrillId id: UUID) -> LibraryActivity? { byId[id] }

    /// Name-based (SHA-256) UUID, version 5 layout: the same key gives the same
    /// id on every device, so concurrent first launches seed the same record.
    static func drillId(forKey key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("hoopwise.activity-library|" + key).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Everything except rule options — what is seeded as drills.
    var plannable: [LibraryActivity] { items.filter { !$0.isRule } }

    func tab(_ age: ActivityAge) -> LibraryTab? { tabs.first { $0.age == age } }

    /// The drill a library row becomes. Duration 8 min: FIBA puts each
    /// activity at 5–10 minutes (Start Coaching workbook p.26).
    static func drill(for activity: LibraryActivity, createdAt: Date = Date()) -> DrillItem {
        DrillItem(
            id: activity.id,
            name: activity.name,
            category: activity.type.category,
            difficulty: activity.age.difficulty,
            durationMinutes: 8,
            description: activity.howItRuns,
            minPlayers: 1,
            tags: [tag, "library:\(activity.key)", activity.age.plannerTag,
                   "block:\(activity.block.rawValue)", "type:\(activity.type.rawValue)",
                   "kind:\(activity.kind)"],
            createdAt: createdAt,
            updatedAt: createdAt)
    }
}

extension DrillItem {
    /// The library row this drill was seeded from, if it is a library drill.
    var libraryActivity: LibraryActivity? { ActivityLibrary.activity(forDrillId: id) }
    var isLibraryDrill: Bool { tags.contains(ActivityLibrary.tag) }
}
