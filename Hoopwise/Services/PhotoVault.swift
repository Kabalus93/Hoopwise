import Photos
import UIKit

/// The media vault's side of Photos (26 Nov 2026): permission, turning vault
/// entries into this device's photos, images, the photos shot during a class,
/// and the "Hoopwise" albums. Nothing here writes the store.
@MainActor
enum PhotoVault {
    // MARK: Permission

    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    static var hasAccess: Bool { status == .authorized || status == .limited }

    /// Asks once; true when photos can be read.
    static func requestAccess() async -> Bool {
        if hasAccess { return true }
        let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return result == .authorized || result == .limited
    }

    // MARK: Entries ⇄ photos

    /// Vault entries for photos picked on this device: their iCloud
    /// identifiers (so the other devices find them), the date shot.
    static func entries(localIds: [String], sessionId: UUID? = nil) -> [VaultPhoto] {
        guard !localIds.isEmpty else { return [] }
        let clouds = cloudIds(for: localIds)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIds, options: nil)
        var dates: [String: Date] = [:]
        assets.enumerateObjects { asset, _, _ in dates[asset.localIdentifier] = asset.creationDate }
        let now = Date()
        return localIds.map {
            VaultPhoto(localId: $0, cloudId: clouds[$0], addedAt: now, takenAt: dates[$0], sessionId: sessionId)
        }
    }

    private static func cloudIds(for localIds: [String]) -> [String: String] {
        var out: [String: String] = [:]
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: localIds)
        for (local, result) in mappings {
            if case .success(let cloud) = result { out[local] = cloud.stringValue }
        }
        return out
    }

    /// This device's identifier for each entry the cloud knows — memo per run.
    private static var resolved: [String: String] = [:]

    /// The photos of these entries on this device, in the entries' order;
    /// an entry whose photo is gone (deleted, not synced yet) is left out.
    static func assets(for entries: [VaultPhoto]) -> [(entry: VaultPhoto, asset: PHAsset)] {
        guard hasAccess, !entries.isEmpty else { return [] }
        // Cloud identifiers of entries filed on another device.
        let toMap = entries.compactMap { e -> String? in
            guard let c = e.cloudId, resolved[c] == nil else { return nil }
            return c
        }
        if !toMap.isEmpty {
            let mappings = PHPhotoLibrary.shared().localIdentifierMappings(for: toMap.map { PHCloudIdentifier(stringValue: $0) })
            for (cloud, result) in mappings {
                if case .success(let local) = result { resolved[cloud.stringValue] = local }
            }
        }
        var wanted: [String] = []
        for e in entries {
            wanted.append(e.localId)
            if let c = e.cloudId, let l = resolved[c] { wanted.append(l) }
        }
        var byId: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: Array(Set(wanted)), options: nil)
            .enumerateObjects { asset, _, _ in byId[asset.localIdentifier] = asset }
        return entries.compactMap { e in
            if let a = byId[e.localId] { return (e, a) }
            if let c = e.cloudId, let l = resolved[c], let a = byId[l] { return (e, a) }
            return nil
        }
    }

    // MARK: Images

    static func image(_ asset: PHAsset, side: CGFloat, quality: Bool = false) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = quality ? .highQualityFormat : .opportunistic
        options.resizeMode = quality ? .exact : .fast
        let size = CGSize(width: side, height: side)
        return await withCheckedContinuation { continuation in
            var done = false
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                                  options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !done, !degraded || image == nil else { return }
                done = true
                continuation.resume(returning: image)
            }
        }
    }

    /// The whole photo for a post, its long side about `side` pixels.
    static func fullImage(_ asset: PHAsset, side: CGFloat = 2400) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        let ratio = CGFloat(asset.pixelWidth) / CGFloat(max(1, asset.pixelHeight))
        let size = ratio >= 1 ? CGSize(width: side, height: side / ratio) : CGSize(width: side * ratio, height: side)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: A class's photos

    /// Photos shot from 30 minutes before a class to an hour after it.
    static func photos(during session: SessionEvent) -> [PHAsset] {
        guard hasAccess else { return [] }
        let from = session.startTime.addingTimeInterval(-30 * 60)
        let to = session.endTime.addingTimeInterval(60 * 60)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                                        PHAssetMediaType.image.rawValue, from as NSDate, to as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var out: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { a, _, _ in out.append(a) }
        return out
    }

    // MARK: Albums — Photos › Hoopwise › <athlete>

    /// Puts the photos in the athlete's album inside a "Hoopwise" folder, so
    /// they are found from Photos too. Best effort: a refusal leaves the vault
    /// as it is.
    static func file(localIds: [String], inAlbumFor athleteName: String) {
        guard status == .authorized, !localIds.isEmpty, !athleteName.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIds, options: nil)
        guard assets.count > 0 else { return }
        Task.detached {
            let library = PHPhotoLibrary.shared()
            func folder() -> PHCollectionList? {
                let lists = PHCollectionList.fetchCollectionLists(with: .folder, subtype: .any, options: nil)
                var found: PHCollectionList?
                lists.enumerateObjects { l, _, stop in if l.localizedTitle == "Hoopwise" { found = l; stop.pointee = true } }
                return found
            }
            do {
                if folder() == nil {
                    try await library.performChanges {
                        PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: "Hoopwise")
                    }
                }
                guard let parent = folder() else { return }
                var album: PHAssetCollection?
                PHAssetCollection.fetchCollections(in: parent, options: nil).enumerateObjects { c, _, stop in
                    if let c = c as? PHAssetCollection, c.localizedTitle == athleteName { album = c; stop.pointee = true }
                }
                try await library.performChanges {
                    if let album {
                        PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
                    } else {
                        let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: athleteName)
                        request.addAssets(assets)
                        if let placeholder = request.placeholderForCreatedAssetCollection {
                            PHCollectionListChangeRequest(for: parent)?.addChildCollections([placeholder] as NSArray)
                        }
                    }
                }
            } catch {
                debugLog("📷 vault album: \(error)")
            }
        }
    }
}
