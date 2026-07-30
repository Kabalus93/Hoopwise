import Foundation
import SwiftData

/// SwiftData record for a play's spatial model.
///
/// The geometry itself lives in `diagramData` as Codable JSON rather than a
/// normalized entity graph. A diagram is a document: it is always loaded and
/// saved whole, and nothing queries across keyframes. Normalizing it would cost
/// six or more CloudKit record types, force every relationship optional, and
/// buy nothing — SwiftData + CloudKit many-to-many is exactly the construct
/// that syncs unreliably.
///
/// A few fields are promoted to real columns so lists and filters don't need to
/// decode every blob.
@Model
final class SDPlayDiagram {
    var id: UUID = UUID()
    /// The `SDPlay` this illustrates. A plain id, not a relationship: the
    /// parallel model keeps `Play` untouched so the frozen iOS UI keeps
    /// working, and an optional relationship would buy nothing here.
    var playId: UUID = UUID()

    // Promoted for listing without decoding.
    var name: String = ""
    var courtStandardRaw: String = CourtStandard.fiba.rawValue
    var courtModeRaw: String = CourtMode.half.rawValue
    var durationSeconds: Double = 0
    var branchCount: Int = 1

    /// JSON `PlayDiagram`. External storage keeps large diagrams out of the
    /// record body and under CloudKit's per-field limits.
    @Attribute(.externalStorage) var diagramData: Data?

    /// Set when this diagram is a variant in a play family. JSON `PlayVariant`.
    var variantData: Data?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Bridges
    var courtStandard: CourtStandard {
        get { CourtStandard(rawValue: courtStandardRaw) ?? .fiba }
        set { courtStandardRaw = newValue.rawValue }
    }

    var courtMode: CourtMode {
        get { CourtMode(rawValue: courtModeRaw) ?? .half }
        set { courtModeRaw = newValue.rawValue }
    }

    var diagram: PlayDiagram? {
        get {
            guard let diagramData else { return nil }
            return try? JSONDecoder().decode(PlayDiagram.self, from: diagramData)
        }
        set {
            diagramData = newValue.flatMap { try? JSONEncoder().encode($0) }
            if let newValue {
                playId = newValue.playId
                courtStandard = newValue.space.standard
                courtMode = newValue.space.mode
                durationSeconds = newValue.totalDuration
                branchCount = max(1, newValue.branches.count)
                updatedAt = Date()
            }
        }
    }

    var variant: PlayVariant? {
        get {
            guard let variantData else { return nil }
            return try? JSONDecoder().decode(PlayVariant.self, from: variantData)
        }
        set { variantData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isVariant: Bool { variantData != nil }

    init(
        id: UUID = UUID(),
        playId: UUID = UUID(),
        name: String = "",
        diagram: PlayDiagram? = nil,
        variant: PlayVariant? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.playId = playId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        defer {
            self.diagram = diagram
            self.variant = variant
        }
    }
}
