import Foundation
import SwiftData

/// SwiftData mirror of `DrillMedia`. All properties have defaults so CloudKit
/// can sync. The inverse relationship to `SDDrill` is declared on the parent.
@Model
final class SDDrillMedia {
    var id: UUID = UUID()
    var kindRaw: String = DrillMediaKind.image.rawValue
    var localPath: String?
    var remoteURL: String?
    var thumbnailPath: String?
    var strokesPath: String?
    var caption: String?
    var sortOrder: Int = 0
    var durationSeconds: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Parent drill. Populated via cascade delete on the SDDrill side.
    var drill: SDDrill?

    init(
        id: UUID = UUID(),
        kind: DrillMediaKind = .image,
        localPath: String? = nil,
        remoteURL: String? = nil,
        thumbnailPath: String? = nil,
        strokesPath: String? = nil,
        caption: String? = nil,
        sortOrder: Int = 0,
        durationSeconds: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.thumbnailPath = thumbnailPath
        self.strokesPath = strokesPath
        self.caption = caption
        self.sortOrder = sortOrder
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: DrillMediaKind {
        get { DrillMediaKind(rawValue: kindRaw) ?? .image }
        set { kindRaw = newValue.rawValue }
    }

    /// Convert this SwiftData record into the value-type struct. `drill?.id`
    /// fallback prevents NSManagedObject-deleted access from crashing during a
    /// cascade.
    func toStruct() -> DrillMedia {
        DrillMedia(
            id: id,
            drillId: drill?.id ?? UUID(),
            kind: kind,
            localPath: localPath,
            remoteURL: remoteURL,
            thumbnailPath: thumbnailPath,
            strokesPath: strokesPath,
            caption: caption,
            sortOrder: sortOrder,
            durationSeconds: durationSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Build a new SwiftData record from a struct. The caller is responsible
    /// for attaching it to a parent `SDDrill` (so the inverse relationship is
    /// populated).
    static func from(_ media: DrillMedia) -> SDDrillMedia {
        SDDrillMedia(
            id: media.id,
            kind: media.kind,
            localPath: media.localPath,
            remoteURL: media.remoteURL,
            thumbnailPath: media.thumbnailPath,
            strokesPath: media.strokesPath,
            caption: media.caption,
            sortOrder: media.sortOrder,
            durationSeconds: media.durationSeconds,
            createdAt: media.createdAt,
            updatedAt: media.updatedAt
        )
    }

    /// Copy struct fields onto this record in place — used by
    /// `updateDrill` so SwiftData's identity is preserved across edits.
    func apply(_ media: DrillMedia) {
        kind = media.kind
        localPath = media.localPath
        remoteURL = media.remoteURL
        thumbnailPath = media.thumbnailPath
        strokesPath = media.strokesPath
        caption = media.caption
        sortOrder = media.sortOrder
        durationSeconds = media.durationSeconds
        updatedAt = Date()
    }
}
