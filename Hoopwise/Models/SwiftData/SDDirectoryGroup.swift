import Foundation
import SwiftData

/// A user-created directory group — the Contacts "group" concept applied to
/// Hoopwise entities. Generic across directory pages (`entityKind`) so ONE
/// CloudKit record type covers Athletes now and Sessions/Programs later —
/// each extra record type costs a Dev→Production deploy plus an iOS release
/// (CLAUDE.md rule 7), so the type is defined once, broadly.
///
/// CloudKit constraints honoured: every property defaulted or optional, no
/// unique attributes, no relationships. Membership is a JSON id list in the
/// bundleSessionIdsData idiom — a group is small, always loaded whole.
@Model
final class SDDirectoryGroup {
    var id: UUID = UUID()
    var name: String = ""
    /// Which directory this group belongs to: "athlete", later "session"…
    var entityKind: String = "athlete"
    /// "custom" (hand-curated members) or "smart" (rule-driven, members
    /// derived at read time from ruleData).
    var kindRaw: String = "custom"
    /// JSON [UUID] for custom groups. Ignored by smart groups.
    var memberIdsData: Data?
    /// JSON rule payload for smart groups (e.g. {"type":"attendanceBelow",
    /// "threshold":0.6}). Nil for custom groups.
    var ruleData: Data?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         name: String = "",
         entityKind: String = "athlete",
         kindRaw: String = "custom",
         memberIdsData: Data? = nil,
         ruleData: Data? = nil,
         sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.entityKind = entityKind
        self.kindRaw = kindRaw
        self.memberIdsData = memberIdsData
        self.ruleData = ruleData
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var memberIds: [UUID] {
        get {
            guard let data = memberIdsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set { memberIdsData = try? JSONEncoder().encode(newValue) }
    }
}

/// Value copy for view consumption, matching the Student/Contract idiom.
struct DirectoryGroupItem: Identifiable, Hashable {
    var id: UUID
    var name: String
    var entityKind: String
    var isSmart: Bool
    var memberIds: [UUID]
    var sortOrder: Int
}
