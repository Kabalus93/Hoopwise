import Foundation

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
