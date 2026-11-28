import Foundation
import CoreGraphics

// THE MEDIA VAULT (26 Nov 2026, Luther: "a media vault per player … the photos
// I shot of the athlete … quickly find media from a player and post it or share
// it … Hoopwise can automatically overlay a cool stat on it"; decided: the
// coach's PHOTOS LIBRARY is the store, Hoopwise keeps the index; photos first).
//
// A vault entry names a photo in Photos — never a copy of it. `localId` is the
// identifier on the device that filed it; `cloudId` is iCloud Photos' identifier
// for the same photo, which every device of the coach can turn back into its own
// local one (PhotoVault.resolve). The list rides in the athlete's existing
// synced `mediaAssetsData` JSON (MediaAssetStatus.vault).

nonisolated struct VaultPhoto: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var localId: String
    var cloudId: String?
    var addedAt: Date
    /// When it was shot (the photo's own date).
    var takenAt: Date?
    /// The class it was filed from, when it was.
    var sessionId: UUID?
    /// THE ATHLETE'S FACE in this photo (28 Nov 2026, Luther: "store faces in
    /// the media so that wherever a face needs to be used in the poster the
    /// engine knows from which photos it should choose"). Found on the device
    /// (Vision face rectangles — no recognition: the largest face, or the one
    /// the coach tapped). nil with `facesChecked` = looked, none found.
    var face: VaultFace?
    /// The photo has been looked at for faces (images only).
    var facesChecked: Bool?

    /// The same photo in Photos (by either identifier).
    func sameAsset(as other: VaultPhoto) -> Bool {
        if localId == other.localId { return true }
        if let a = cloudId, let b = other.cloudId { return a == b }
        return false
    }

    /// Newest shot first; undated by when they were filed.
    static func ordered(_ photos: [VaultPhoto]) -> [VaultPhoto] {
        photos.sorted { ($0.takenAt ?? $0.addedAt) > ($1.takenAt ?? $1.addedAt) }
    }
}

/// A face in a vault photo. `rect` is normalized, top-left origin.
nonisolated struct VaultFace: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// The face's height in the photo's pixels — how sharp a close-up can be.
    var pixels: Double
    /// Vision's capture quality 0…1, when it could tell.
    var quality: Double?
    /// The coach said this is the athlete.
    var byCoach: Bool?

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(rect: CGRect, pixels: Double, quality: Double? = nil, byCoach: Bool? = nil) {
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        self.pixels = pixels; self.quality = quality; self.byCoach = byCoach
    }

    /// How good a face is for a close-up: the coach's pick first, then big and
    /// sharp. A face under 80 px is too small to blow up.
    var score: Double {
        guard pixels >= 80 || byCoach == true else { return 0 }
        return (byCoach == true ? 10_000 : 0) + min(pixels, 900) * (0.5 + (quality ?? 0.5))
    }
}
