import Foundation
import SwiftUI
#if os(iOS)
import UIKit
import Photos
#elseif os(macOS)
import AppKit
#endif

// MARK: - Photo Capture Manager
/// Handles photo capture and compression for attendance photos.
///
/// **Path storage policy:** photos are persisted at `Documents/AttendancePhotos/`
/// and the *relative subpath* (e.g. `"AttendancePhotos/attendance_<id>.jpg"`)
/// is stored on `SessionEvent.attendancePhotoPath`. Absolute paths are not
/// stored because the iOS app container UUID changes across reinstalls and
/// some updates, which would silently break every saved photo.
///
/// `loadAttendancePhoto(from:)` accepts either form for backward compatibility
/// with sessions saved before this change — it strips any container prefix
/// and resolves against the *current* Documents directory.
class PhotoCaptureManager {
    static let shared = PhotoCaptureManager()

    private init() {}

    private static let attendanceFolder = "AttendancePhotos"

    /// Current `Documents/AttendancePhotos` URL. Computed each call so the
    /// container UUID is always fresh.
    private var attendancePhotosDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent(Self.attendanceFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Canonical *relative* path stored on the model
    /// (`AttendancePhotos/attendance_<id>.jpg`).
    private func relativePath(forSession sessionId: UUID) -> String {
        "\(Self.attendanceFolder)/attendance_\(sessionId.uuidString).jpg"
    }

    // MARK: - Save Compressed Photo
    /// Saves a photo with aggressive compression to minimize storage
    /// Target: ~200KB per photo (vs typical 2-5MB)
    func saveAttendancePhoto(_ image: PlatformImage, for sessionId: UUID) -> String? {
        #if os(iOS)
        return saveAttendancePhotoiOS(image, for: sessionId)
        #elseif os(macOS)
        return saveAttendancePhotomacOS(image, for: sessionId)
        #endif
    }
    
    #if os(iOS)
    private func saveAttendancePhotoiOS(_ image: UIImage, for sessionId: UUID) -> String? {
        // Resize to reasonable dimensions (max 1024px width)
        let resizedImage = resizeImage(image, maxWidth: 1024)

        // Compress to JPEG with quality 0.5 (good balance of quality vs size)
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else {
            debugLog("❌ Failed to compress image")
            return nil
        }

        // Further compress if still too large (target: 200KB)
        let finalData = compressToTargetSize(imageData, targetSizeKB: 200, image: resizedImage)

        let relative = relativePath(forSession: sessionId)
        let filePath = attendancePhotosDirectory.appendingPathComponent("attendance_\(sessionId.uuidString).jpg")

        do {
            try finalData.write(to: filePath)
            let sizeKB = Double(finalData.count) / 1024.0
            debugLog("✅ Saved attendance photo: \(relative) (\(String(format: "%.1f", sizeKB))KB)")
            // Return the *relative* path so the stored value survives container
            // UUID changes across reinstalls.
            return relative
        } catch {
            debugLog("❌ Failed to save photo: \(error)")
            return nil
        }
    }
    
    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        
        if size.width <= maxWidth {
            return image
        }
        
        let ratio = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
    
    private func compressToTargetSize(_ data: Data, targetSizeKB: Int, image: UIImage) -> Data {
        var currentData = data
        var quality: CGFloat = 0.5
        
        // If already under target, return as-is
        if data.count <= targetSizeKB * 1024 {
            return data
        }
        
        // Progressively reduce quality until under target
        while currentData.count > targetSizeKB * 1024 && quality > 0.1 {
            quality -= 0.1
            if let compressed = image.jpegData(compressionQuality: quality) {
                currentData = compressed
            }
        }
        
        return currentData
    }
    #endif
    
    #if os(macOS)
    private func saveAttendancePhotomacOS(_ image: NSImage, for sessionId: UUID) -> String? {
        // Resize to reasonable dimensions
        let resizedImage = resizeImageMac(image, maxWidth: 1024)

        // Convert to JPEG data
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else {
            debugLog("❌ Failed to compress image")
            return nil
        }

        let relative = relativePath(forSession: sessionId)
        let filePath = attendancePhotosDirectory.appendingPathComponent("attendance_\(sessionId.uuidString).jpg")

        do {
            try imageData.write(to: filePath)
            let sizeKB = Double(imageData.count) / 1024.0
            debugLog("✅ Saved attendance photo: \(relative) (\(String(format: "%.1f", sizeKB))KB)")
            return relative
        } catch {
            debugLog("❌ Failed to save photo: \(error)")
            return nil
        }
    }
    
    private func resizeImageMac(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
        let size = image.size
        
        if size.width <= maxWidth {
            return image
        }
        
        let ratio = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * ratio)
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    #endif
    
    // MARK: - Load Photo
    /// Resolves `path` to an absolute file path under the *current* Documents
    /// directory and loads the image. Tolerates stored values from before the
    /// container-safe migration:
    ///   1. Relative form (`AttendancePhotos/attendance_<id>.jpg`) — preferred.
    ///   2. Absolute form pointing at a still-valid container path.
    ///   3. Stale absolute form from an old container — strips up to
    ///      `AttendancePhotos/` and re-resolves.
    ///   4. Bare filename — searches Documents/AttendancePhotos.
    /// Returns nil only when no candidate exists on disk.
    func loadAttendancePhoto(from path: String) -> PlatformImage? {
        guard let resolved = resolveAttendancePhotoPath(path) else {
            debugLog("⚠️ Attendance photo not found for stored path: \(path)")
            return nil
        }
        #if os(iOS)
        return UIImage(contentsOfFile: resolved)
        #elseif os(macOS)
        return NSImage(contentsOfFile: resolved)
        #endif
    }

    /// Returns the canonical relative path the model *should* store for this
    /// photo, given whatever historical value is currently on disk. Callers
    /// can use this to opportunistically rewrite legacy absolute paths to
    /// the migration-safe relative form. Returns nil when the photo can't
    /// be located on disk.
    func canonicalRelativePath(for storedPath: String) -> String? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let resolved = resolveAttendancePhotoPath(trimmed) else { return nil }
        // Already in the relative form we want? Hand it back unchanged.
        if !trimmed.hasPrefix("/") {
            return trimmed
        }
        // Convert the resolved absolute path back to "AttendancePhotos/<file>".
        let url = URL(fileURLWithPath: resolved)
        return "\(Self.attendanceFolder)/\(url.lastPathComponent)"
    }

    /// Locate a photo on disk regardless of whether its stored value is
    /// relative, absolute-fresh, or absolute-stale.
    private func resolveAttendancePhotoPath(_ stored: String) -> String? {
        let fm = FileManager.default

        // (1) Stored as a relative path → resolve against current Documents.
        if !stored.hasPrefix("/") {
            let absolute = attendancePhotosDirectory
                .deletingLastPathComponent() // back to Documents
                .appendingPathComponent(stored)
                .path
            if fm.fileExists(atPath: absolute) {
                return absolute
            }
            // Maybe the relative form is just `attendance_<id>.jpg` without
            // the folder prefix — try inside the folder directly.
            let inFolder = attendancePhotosDirectory
                .appendingPathComponent(stored)
                .path
            if fm.fileExists(atPath: inFolder) {
                return inFolder
            }
        }

        // (2) Absolute path that's still valid (same container).
        if fm.fileExists(atPath: stored) {
            return stored
        }

        // (3) Absolute but stale — strip up to "AttendancePhotos/" and
        // re-resolve against the current container.
        if let range = stored.range(of: "/\(Self.attendanceFolder)/") {
            let suffix = stored[range.upperBound...]
            let candidate = attendancePhotosDirectory.appendingPathComponent(String(suffix)).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // (4) Last-ditch: just the filename component, look in current folder.
        let filename = (stored as NSString).lastPathComponent
        if !filename.isEmpty {
            let candidate = attendancePhotosDirectory.appendingPathComponent(filename).path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Save to Photo Library
    #if os(iOS)
    /// Saves an image to the user's Photos library after requesting add-only
    /// authorization. Completion is called on the main queue. Used by the
    /// session attendance "Export" flow that watermarks the roll-call photo
    /// before sharing in WeChat.
    func saveImageToPhotoLibrary(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "PhotoCaptureManager",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Photo library permission denied"]
                    )))
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? NSError(
                            domain: "PhotoCaptureManager",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Save failed"]
                        )))
                    }
                }
            }
        }
    }
    #endif

    // MARK: - Delete Photo
    func deleteAttendancePhoto(at path: String) {
        if let resolved = resolveAttendancePhotoPath(path) {
            try? FileManager.default.removeItem(atPath: resolved)
            debugLog("🗑️ Deleted attendance photo at \(resolved)")
        } else {
            debugLog("⚠️ deleteAttendancePhoto: nothing on disk for \(path)")
        }
    }
    
    // MARK: - Get Storage Info
    func getAttendancePhotosSize() -> String {
        let photosPath = attendancePhotosDirectory

        guard let files = try? FileManager.default.contentsOfDirectory(at: photosPath, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }

        var totalSize: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        let sizeKB = Double(totalSize) / 1024.0
        let sizeMB = sizeKB / 1024.0

        if sizeMB > 1 {
            return String(format: "%.1f MB", sizeMB)
        } else {
            return String(format: "%.0f KB", sizeKB)
        }
    }
}

// Note: PlatformImage typealias is defined in FlightySessionRootView.swift
