import Foundation

// MARK: - DrillMediaKind
/// What flavor of visual is attached to a drill. `isLocal` distinguishes media
/// the coach can rely on courtside (no signal) from media that requires the
/// internet (reference videos pulled from YouTube/Instagram).
enum DrillMediaKind: String, Codable, CaseIterable, Hashable {
    /// PencilKit-drawn court diagram (Phase 3). Stored as a flattened JPEG plus
    /// an editable CourtScheme.
    case courtDiagram
    /// Still photo from the camera or library.
    case image
    /// Coach's own short video, compressed for offline playback.
    case videoClip
    /// External YouTube reference. Thumbnail cached locally; playback requires
    /// network.
    case youtube
    /// External Instagram reference. Thumbnail cached when possible; deep-links
    /// out to the Instagram app for playback (no embed).
    case instagram

    /// Whether the media's primary asset lives in the app's Documents directory
    /// (true → works courtside without signal) or on a third-party host.
    var isLocal: Bool {
        switch self {
        case .courtDiagram, .image, .videoClip: return true
        case .youtube, .instagram: return false
        }
    }

    /// Whether the asset is video (still needs a poster thumbnail for the
    /// carousel, but the viewer must play it rather than just zoom).
    var isVideo: Bool {
        switch self {
        case .videoClip, .youtube, .instagram: return true
        case .courtDiagram, .image: return false
        }
    }

    /// SF Symbol used in compact badges and pickers.
    var iconName: String {
        switch self {
        case .courtDiagram: return "scribble.variable"
        case .image:        return "photo.fill"
        case .videoClip:    return "video.fill"
        case .youtube:      return "play.rectangle.fill"
        case .instagram:    return "camera.aperture"
        }
    }

    func localizedLabel(isChinese: Bool) -> String {
        switch self {
        case .courtDiagram: return isChinese ? "战术图" : "Diagram"
        case .image:        return isChinese ? "图片"   : "Photo"
        case .videoClip:    return isChinese ? "视频"   : "Video"
        case .youtube:      return "YouTube"
        case .instagram:    return "Instagram"
        }
    }
}

// MARK: - DrillMedia
/// A single visual attached to a drill. Local kinds store a relative path
/// under `Documents/DrillMedia/<drillId>/<mediaId>.{ext}` (relative so the
/// stored value survives container-UUID changes — same lesson as
/// `PhotoCaptureManager`). Remote kinds store a `remoteURL` plus a cached
/// `thumbnailPath` so the carousel stays scannable offline.
struct DrillMedia: Identifiable, Codable, Hashable {
    let id: UUID
    /// Owning drill. Persisted on the SwiftData side via @Relationship, but
    /// surfaced here so the wire format is self-contained.
    var drillId: UUID
    var kind: DrillMediaKind
    /// Relative path to the primary asset for local kinds (e.g. the JPEG for
    /// `.image` or the MP4 for `.videoClip`). `nil` for remote kinds.
    var localPath: String?
    /// Original URL for remote kinds. `nil` for local kinds.
    var remoteURL: String?
    /// Relative path to a small JPEG thumbnail (~720px on the long edge).
    /// Available for every kind so the carousel never has to hit the network.
    var thumbnailPath: String?
    /// Relative path to a `.pkdrawing` file holding the editable strokes for
    /// a `.courtDiagram`. The `localPath` JPEG is the canonical display
    /// asset; `strokesPath` is what we re-open when the user edits the
    /// diagram. nil for non-diagram kinds.
    var strokesPath: String?
    /// Optional caption shown under the tile and in the full-screen viewer.
    var caption: String?
    /// Position in the carousel. Reorderable.
    var sortOrder: Int
    /// Duration in seconds for video kinds (used to show a `2:35` badge).
    var durationSeconds: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        drillId: UUID,
        kind: DrillMediaKind,
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
        self.drillId = drillId
        self.kind = kind
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

    // MARK: - Codable (backward-compatible)
    /// Custom decode so bundles created before this field existed still
    /// decode cleanly — older payloads decode `strokesPath` as nil.
    private enum CodingKeys: String, CodingKey {
        case id, drillId, kind
        case localPath, remoteURL, thumbnailPath, strokesPath
        case caption, sortOrder, durationSeconds
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        drillId = try c.decode(UUID.self, forKey: .drillId)
        kind = try c.decode(DrillMediaKind.self, forKey: .kind)
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath)
        remoteURL = try c.decodeIfPresent(String.self, forKey: .remoteURL)
        thumbnailPath = try c.decodeIfPresent(String.self, forKey: .thumbnailPath)
        strokesPath = try c.decodeIfPresent(String.self, forKey: .strokesPath)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// Convenience: best path to use when rendering a small tile. Prefers a
    /// dedicated thumbnail; falls back to the full asset for local images.
    var thumbnailOrPrimaryPath: String? {
        thumbnailPath ?? (kind == .image ? localPath : nil)
    }
}
