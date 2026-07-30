import Foundation
import SwiftData

/// SwiftData mirror of `Play`.
///
/// Plays were previously held in a plain in-memory array on SwiftDataManager
/// and never written anywhere, so every play a coach authored was discarded at
/// quit. This is the persistence that was missing.
///
/// All properties have defaults and no relationship is required, as CloudKit
/// demands. Collections are stored as JSON `Data` — the same idiom as
/// `SDContract.bundleSessionIdsData`.
@Model
final class SDPlay {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = PlayCategory.setPlays.rawValue
    var formation: String = ""
    var playDescription: String = ""
    var keyTeachingPointsData: Data?
    var stepsData: Data?
    var variationsData: Data?
    var bestUsedAgainst: String?
    var difficultyRaw: String = DifficultyLevel.intermediate.rawValue
    /// Legacy raster diagram path. Superseded by `SDPlayDiagram` but kept so
    /// existing content stays viewable.
    var diagramUrl: String?
    var tagsData: Data?
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Bridges
    var category: PlayCategory {
        get { PlayCategory(rawValue: categoryRaw) ?? .setPlays }
        set { categoryRaw = newValue.rawValue }
    }

    var difficulty: DifficultyLevel {
        get { DifficultyLevel(rawValue: difficultyRaw) ?? .intermediate }
        set { difficultyRaw = newValue.rawValue }
    }

    var keyTeachingPoints: [String] {
        get { Self.decode(keyTeachingPointsData) }
        set { keyTeachingPointsData = try? JSONEncoder().encode(newValue) }
    }

    var steps: [PlayStep] {
        get {
            guard let stepsData else { return [] }
            return (try? JSONDecoder().decode([PlayStep].self, from: stepsData)) ?? []
        }
        set { stepsData = try? JSONEncoder().encode(newValue) }
    }

    var variations: [String] {
        get { Self.decode(variationsData) }
        set { variationsData = try? JSONEncoder().encode(newValue) }
    }

    var tags: [String] {
        get { Self.decode(tagsData) }
        set { tagsData = try? JSONEncoder().encode(newValue) }
    }

    private static func decode(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        category: PlayCategory = .setPlays,
        formation: String = "",
        playDescription: String = "",
        keyTeachingPoints: [String] = [],
        steps: [PlayStep] = [],
        variations: [String] = [],
        bestUsedAgainst: String? = nil,
        difficulty: DifficultyLevel = .intermediate,
        diagramUrl: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.formation = formation
        self.playDescription = playDescription
        self.bestUsedAgainst = bestUsedAgainst
        self.difficultyRaw = difficulty.rawValue
        self.diagramUrl = diagramUrl
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        defer {
            self.keyTeachingPoints = keyTeachingPoints
            self.steps = steps
            self.variations = variations
            self.tags = tags
        }
    }

    func toStruct() -> Play {
        Play(
            id: id,
            name: name,
            category: category,
            formation: formation,
            description: playDescription,
            keyTeachingPoints: keyTeachingPoints,
            steps: steps,
            variations: variations,
            bestUsedAgainst: bestUsedAgainst,
            difficulty: difficulty,
            diagramUrl: diagramUrl,
            tags: tags,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func from(_ play: Play) -> SDPlay {
        SDPlay(
            id: play.id,
            name: play.name,
            category: play.category,
            formation: play.formation,
            playDescription: play.description,
            keyTeachingPoints: play.keyTeachingPoints,
            steps: play.steps,
            variations: play.variations,
            bestUsedAgainst: play.bestUsedAgainst,
            difficulty: play.difficulty,
            diagramUrl: play.diagramUrl,
            tags: play.tags,
            isFavorite: play.isFavorite,
            createdAt: play.createdAt,
            updatedAt: play.updatedAt
        )
    }

    func apply(_ play: Play) {
        name = play.name
        category = play.category
        formation = play.formation
        playDescription = play.description
        keyTeachingPoints = play.keyTeachingPoints
        steps = play.steps
        variations = play.variations
        bestUsedAgainst = play.bestUsedAgainst
        difficulty = play.difficulty
        diagramUrl = play.diagramUrl
        tags = play.tags
        isFavorite = play.isFavorite
        updatedAt = Date()
    }
}
