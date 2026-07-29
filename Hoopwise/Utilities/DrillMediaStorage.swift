import Foundation
import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - DrillMediaStorage
/// Disk-side companion to `DrillMedia` / `SDDrillMedia`. Persists binary assets
/// (photos, thumbnails, and — in later phases — own videos and flattened court
/// diagrams) under `Documents/DrillMedia/<drillId>/`.
///
/// **Path storage policy:** the *relative* subpath
/// `DrillMedia/<drillId>/<mediaId>.jpg` is what we store on the model, not the
/// absolute path. Container UUIDs change across reinstalls/some updates, which
/// would silently invalidate every saved file otherwise — same lesson learned
/// in `PhotoCaptureManager`.
///
/// Phase 1 scope: still images + their thumbnails. Video and diagram helpers
/// will land in Phase 2/3 alongside the corresponding UI.
final class DrillMediaStorage {
    static let shared = DrillMediaStorage()
    private init() {}

    private static let rootFolder = "DrillMedia"

    /// Documents/DrillMedia, computed fresh each call so the container UUID is
    /// always current.
    private var rootDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent(Self.rootFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Documents/DrillMedia/<drillId>/. Created on demand.
    private func drillFolder(_ drillId: UUID) -> URL {
        let folder = rootDirectory.appendingPathComponent(drillId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func relativePath(drillId: UUID, mediaId: UUID, kind: AssetKind) -> String {
        let filename: String
        switch kind {
        case .primaryImage: filename = "\(mediaId.uuidString).jpg"
        case .video:        filename = "\(mediaId.uuidString).mp4"
        case .thumbnail:    filename = "\(mediaId.uuidString)_thumb.jpg"
        case .strokes:      filename = "\(mediaId.uuidString).pkdrawing"
        }
        return "\(Self.rootFolder)/\(drillId.uuidString)/\(filename)"
    }

    private enum AssetKind {
        case primaryImage, video, thumbnail, strokes
    }

    // MARK: - Save (images)

    #if os(iOS)
    /// Saves a full-resolution-ish image. Mirrors PhotoCaptureManager's policy
    /// (max 1600px on the long edge, JPEG quality stepped down to hit a target
    /// size). Returns the relative path on success.
    @discardableResult
    func saveImage(_ image: UIImage, drillId: UUID, mediaId: UUID, targetKB: Int = 400) -> String? {
        let resized = resize(image, maxDimension: 1600)
        guard let initial = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let data = compress(initial, image: resized, targetKB: targetKB)
        let relative = relativePath(drillId: drillId, mediaId: mediaId, kind: .primaryImage)
        let absolute = drillFolder(drillId).appendingPathComponent("\(mediaId.uuidString).jpg")
        do {
            try data.write(to: absolute)
            debugLog("✅ Drill media saved: \(relative) (\(data.count / 1024)KB)")
            return relative
        } catch {
            debugLog("❌ Failed to save drill media: \(error)")
            return nil
        }
    }

    /// Saves a square-ish thumbnail (~720px on the long edge) at low quality.
    @discardableResult
    func saveThumbnail(_ image: UIImage, drillId: UUID, mediaId: UUID) -> String? {
        let thumb = resize(image, maxDimension: 720)
        guard let data = thumb.jpegData(compressionQuality: 0.65) else { return nil }
        let relative = relativePath(drillId: drillId, mediaId: mediaId, kind: .thumbnail)
        let absolute = drillFolder(drillId).appendingPathComponent("\(mediaId.uuidString)_thumb.jpg")
        do {
            try data.write(to: absolute)
            return relative
        } catch {
            debugLog("❌ Failed to save drill thumbnail: \(error)")
            return nil
        }
    }

    // MARK: - Compression helpers (iOS)
    private func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension, longEdge > 0 else { return image }
        let scale = maxDimension / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }

    private func compress(_ data: Data, image: UIImage, targetKB: Int) -> Data {
        var current = data
        var quality: CGFloat = 0.8
        while current.count > targetKB * 1024, quality > 0.2 {
            quality -= 0.1
            if let stepped = image.jpegData(compressionQuality: quality) {
                current = stepped
            } else {
                break
            }
        }
        return current
    }
    #endif

    // MARK: - Load
    /// Resolves a stored relative path against the *current* container's
    /// Documents directory, with the same legacy tolerances as
    /// `PhotoCaptureManager`: absolute-fresh paths, stale absolute paths, and
    /// bare filenames all degrade gracefully.
    func absolutePath(forRelative path: String) -> String? {
        let fm = FileManager.default
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Relative form — resolve against current Documents.
        if !trimmed.hasPrefix("/") {
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let candidate = documents.appendingPathComponent(trimmed).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // Absolute, still valid.
        if fm.fileExists(atPath: trimmed) {
            return trimmed
        }

        // Absolute but stale — strip up to "DrillMedia/" and re-resolve.
        if let range = trimmed.range(of: "/\(Self.rootFolder)/") {
            let suffix = String(trimmed[range.upperBound...])
            let candidate = rootDirectory.appendingPathComponent(suffix).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    #if os(iOS)
    /// Loads a saved image (full asset or thumbnail) by its stored relative
    /// path. Returns nil if the file no longer exists.
    func loadImage(at relativePath: String) -> UIImage? {
        guard let absolute = absolutePath(forRelative: relativePath) else { return nil }
        return UIImage(contentsOfFile: absolute)
    }
    #endif

    // MARK: - Delete
    /// Deletes the primary asset (image or video), thumbnail, and any
    /// editable strokes for a single media item. Safe to call when files
    /// are already gone.
    func delete(media: DrillMedia) {
        let drillId = media.drillId
        let candidatePaths = [
            media.localPath,
            media.thumbnailPath,
            media.strokesPath,
            relativePath(drillId: drillId, mediaId: media.id, kind: .primaryImage),
            relativePath(drillId: drillId, mediaId: media.id, kind: .video),
            relativePath(drillId: drillId, mediaId: media.id, kind: .thumbnail),
            relativePath(drillId: drillId, mediaId: media.id, kind: .strokes)
        ].compactMap { $0 }

        for relative in candidatePaths {
            if let absolute = absolutePath(forRelative: relative) {
                try? FileManager.default.removeItem(atPath: absolute)
            }
        }
    }

    /// Tear down the whole drill folder (called when the parent drill is
    /// deleted — SwiftData's cascade handles the records, this handles the
    /// binaries).
    func deleteAllMedia(drillId: UUID) {
        let folder = rootDirectory.appendingPathComponent(drillId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Video (own clips)
    #if os(iOS)
    /// Result of importing a coach's own video — relative paths for the
    /// compressed MP4 and its poster thumbnail, plus the asset duration in
    /// seconds (so the carousel can show a `2:35` badge without re-reading
    /// the file).
    struct VideoImportResult {
        let videoRelativePath: String
        let thumbnailRelativePath: String?
        let durationSeconds: Double
    }

    /// Imports a video from a source URL (PhotosPicker temp file or the
    /// camera output). Re-encodes through `AVAssetExportSession` so we can:
    ///   1. Strip oversized HEVC/4K footage to 1080p H.264 MP4 (small,
    ///      universally playable).
    ///   2. Move the file into our Documents container so it survives
    ///      PhotosPicker cleanup.
    /// Returns nil if the export fails (corrupt source, no compatible preset,
    /// etc.) — callers should treat that as "couldn't import this video".
    func importVideo(from sourceURL: URL, drillId: UUID, mediaId: UUID) async -> VideoImportResult? {
        let asset = AVURLAsset(url: sourceURL)
        let duration: Double
        do {
            let cmTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmTime)
        } catch {
            debugLog("❌ Drill video: failed to read duration: \(error)")
            return nil
        }

        let videoFolder = drillFolder(drillId)
        let outputURL = videoFolder.appendingPathComponent("\(mediaId.uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        // `AVAssetExportPreset1920x1080` gives a sane size budget for
        // coaching clips (typically 30s–2min). If `AVAssetExportSession`
        // init rejects the preset for this asset, retry with the universally
        // compatible passthrough preset — that's a smaller file, but at
        // least we get the clip onto disk.
        let presetCandidates = [
            AVAssetExportPreset1920x1080,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetPassthrough
        ]
        var session: AVAssetExportSession?
        var usedPreset = ""
        for candidate in presetCandidates {
            if let attempt = AVAssetExportSession(asset: asset, presetName: candidate) {
                session = attempt
                usedPreset = candidate
                break
            }
        }
        guard let exportSession = session else {
            debugLog("❌ Drill video: no compatible export preset available")
            return nil
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Drive the export via the legacy callback API wrapped in
        // `withCheckedContinuation`. The newer `export(to:as:)` is iOS 18+,
        // while this app deploys further back.
        let success: Bool = await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status == AVAssetExportSession.Status.completed)
            }
        }
        if !success {
            debugLog("❌ Drill video export failed (preset \(usedPreset)) error=\(String(describing: exportSession.error))")
            return nil
        }

        let relative = relativePath(drillId: drillId, mediaId: mediaId, kind: .video)
        let thumbnailPath = generateVideoPoster(at: outputURL, drillId: drillId, mediaId: mediaId)
        let sizeKB = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int).map { $0 / 1024 } ?? 0
        debugLog("✅ Drill video imported: \(relative) (\(sizeKB)KB, \(Int(duration))s)")
        return VideoImportResult(
            videoRelativePath: relative,
            thumbnailRelativePath: thumbnailPath,
            durationSeconds: duration
        )
    }

    /// Resolves a stored video relative path to a `URL` that AVPlayer can play.
    func videoFileURL(at relativePath: String) -> URL? {
        guard let absolute = absolutePath(forRelative: relativePath) else { return nil }
        return URL(fileURLWithPath: absolute)
    }

    /// Extracts a frame ~1s into the video and writes it as the JPEG poster
    /// thumbnail. Returns the saved relative path or nil if extraction failed.
    private func generateVideoPoster(at fileURL: URL, drillId: UUID, mediaId: UUID) -> String? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let posterTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: posterTime, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return saveThumbnail(uiImage, drillId: drillId, mediaId: mediaId)
        } catch {
            debugLog("⚠️ Drill video: poster generation failed, trying t=0: \(error)")
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                return saveThumbnail(uiImage, drillId: drillId, mediaId: mediaId)
            } catch {
                debugLog("❌ Drill video: poster generation failed entirely: \(error)")
                return nil
            }
        }
    }
    #endif

    // MARK: - PencilKit strokes (for editable diagrams)
    /// Saves a `.pkdrawing` data blob alongside the flattened JPEG. Used by
    /// the court diagram editor so a saved diagram can be re-opened and
    /// edited later — without this, the JPEG would be the only artifact.
    @discardableResult
    func saveStrokes(_ data: Data, drillId: UUID, mediaId: UUID) -> String? {
        let relative = relativePath(drillId: drillId, mediaId: mediaId, kind: .strokes)
        let absolute = drillFolder(drillId).appendingPathComponent("\(mediaId.uuidString).pkdrawing")
        do {
            try data.write(to: absolute)
            return relative
        } catch {
            debugLog("❌ Failed to save drill strokes: \(error)")
            return nil
        }
    }

    /// Loads a `.pkdrawing` blob by relative path. Returns nil if the file
    /// is missing (in which case the editor opens with an empty canvas).
    func loadStrokes(at relativePath: String) -> Data? {
        guard let absolute = absolutePath(forRelative: relativePath) else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: absolute))
    }

    // MARK: - Remote thumbnails
    #if os(iOS)
    /// Downloads a remote poster (e.g. YouTube `hqdefault.jpg`) and saves it
    /// as the local thumbnail for a media item. Used at link-add time so the
    /// carousel can render the tile without hitting the network later.
    /// Returns nil on any network/decode failure — callers should fall back
    /// to a kind-tinted placeholder.
    func cacheRemoteThumbnail(from url: URL, drillId: UUID, mediaId: UUID) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                debugLog("⚠️ Remote thumbnail HTTP \(http.statusCode) for \(url.absoluteString)")
                return nil
            }
            guard let image = UIImage(data: data) else {
                debugLog("⚠️ Remote thumbnail: data not decodable as image")
                return nil
            }
            return saveThumbnail(image, drillId: drillId, mediaId: mediaId)
        } catch {
            debugLog("⚠️ Remote thumbnail download failed: \(error)")
            return nil
        }
    }
    #endif

    // MARK: - Bundle import
    /// Asset slot a caller is writing into when restoring a bundle. Keeps
    /// the on-disk extension correct so AVPlayer / UIImage can read the
    /// resulting file without guessing.
    enum ImportedAssetSlot {
        case primaryImage      // .jpg
        case primaryVideo      // .mp4
        case thumbnail         // .jpg
        case strokes           // .pkdrawing
    }

    /// Writes raw bytes from a `.hoopwise` bundle payload into the local
    /// DrillMedia folder and returns the relative path the model should
    /// store. Used by `HoopwiseBundleImporter` so each drill's photos,
    /// videos, thumbnails, and editable strokes survive the trip across
    /// devices.
    @discardableResult
    func writeImportedAsset(_ data: Data,
                            drillId: UUID,
                            mediaId: UUID,
                            slot: ImportedAssetSlot) -> String? {
        let kind: AssetKind
        switch slot {
        case .primaryImage: kind = .primaryImage
        case .primaryVideo: kind = .video
        case .thumbnail:    kind = .thumbnail
        case .strokes:      kind = .strokes
        }
        let relative = relativePath(drillId: drillId, mediaId: mediaId, kind: kind)
        let absolute = drillFolder(drillId).appendingPathComponent((relative as NSString).lastPathComponent)
        do {
            try data.write(to: absolute)
            return relative
        } catch {
            debugLog("❌ Failed to write imported drill asset (\(slot)): \(error)")
            return nil
        }
    }

    /// Reads the bytes at a stored relative path. Used by the bundle
    /// exporter when packing a drill's media into JSON. Returns nil if the
    /// file no longer exists on disk.
    func readData(at relativePath: String) -> Data? {
        guard let absolute = absolutePath(forRelative: relativePath) else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: absolute))
    }

    // MARK: - Maintenance
    /// Total size of `Documents/DrillMedia/` for the Settings storage screen.
    func totalSizeOnDiskBytes() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootDirectory,
                                             includingPropertiesForKeys: [.fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
