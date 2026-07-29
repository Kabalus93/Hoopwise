import Foundation
import SwiftData

@Model
final class SDDrill {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = "skills"
    var difficultyRaw: String = "beginner"
    var durationMinutes: Int = 10
    var drillDescription: String = ""
    var instructions: [String] = []
    var keyPoints: [String] = []
    var equipmentNeeded: [String] = []
    var minPlayers: Int = 1
    var maxPlayers: Int?
    var variations: [String] = []
    var videoUrl: String?
    var tags: [String] = []
    var isFavorite: Bool = false
    var createdByCoachId: UUID?
    var createdByCoachName: String?
    var lastModifiedByCoachId: UUID?
    var lastModifiedByCoachName: String?
    var lastModifiedAt: Date?
    var originBundleId: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Visuals attached to this drill (photos, own videos, court diagrams,
    /// YouTube/Instagram links). Cascade-deleted with the drill. Optional + []
    /// default is required for CloudKit-backed SwiftData.
    @Relationship(deleteRule: .cascade, inverse: \SDDrillMedia.drill)
    var media: [SDDrillMedia]? = []

    init(
        id: UUID = UUID(),
        name: String,
        category: DrillCategory,
        difficulty: DifficultyLevel = .beginner,
        durationMinutes: Int = 10,
        description: String = "",
        instructions: [String] = [],
        keyPoints: [String] = [],
        equipmentNeeded: [String] = [],
        minPlayers: Int = 1,
        maxPlayers: Int? = nil,
        variations: [String] = [],
        videoUrl: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.difficultyRaw = difficulty.rawValue
        self.durationMinutes = durationMinutes
        self.drillDescription = description
        self.instructions = instructions
        self.keyPoints = keyPoints
        self.equipmentNeeded = equipmentNeeded
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.variations = variations
        self.videoUrl = videoUrl
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var category: DrillCategory {
        get { DrillCategory(rawValue: categoryRaw) ?? .skills }
        set { categoryRaw = newValue.rawValue }
    }
    
    var difficulty: DifficultyLevel {
        get { DifficultyLevel(rawValue: difficultyRaw) ?? .beginner }
        set { difficultyRaw = newValue.rawValue }
    }
    
    var playerRange: String {
        if let max = maxPlayers { return "\(minPlayers)-\(max) players" }
        return "\(minPlayers)+ players"
    }
    
    /// Convert to legacy DrillItem struct. Media is sorted by `sortOrder` so
    /// downstream views can render the carousel in stable order.
    func toStruct() -> DrillItem {
        let mediaStructs: [DrillMedia] = (media ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.toStruct() }
        return DrillItem(
            id: id,
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: drillDescription,
            instructions: instructions,
            keyPoints: keyPoints,
            equipmentNeeded: equipmentNeeded,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            variations: variations,
            videoUrl: videoUrl,
            tags: tags,
            isFavorite: isFavorite,
            media: mediaStructs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from legacy DrillItem struct. Note: this does NOT populate the
    /// media relationship — `SwiftDataManager.addDrill` attaches `SDDrillMedia`
    /// children after inserting the parent so SwiftData identity is correct.
    static func from(_ drill: DrillItem) -> SDDrill {
        SDDrill(
            id: drill.id,
            name: drill.name,
            category: drill.category,
            difficulty: drill.difficulty,
            durationMinutes: drill.durationMinutes,
            description: drill.description,
            instructions: drill.instructions,
            keyPoints: drill.keyPoints,
            equipmentNeeded: drill.equipmentNeeded,
            minPlayers: drill.minPlayers,
            maxPlayers: drill.maxPlayers,
            variations: drill.variations,
            videoUrl: drill.videoUrl,
            tags: drill.tags,
            isFavorite: drill.isFavorite,
            createdAt: drill.createdAt,
            updatedAt: drill.updatedAt
        )
    }
}
