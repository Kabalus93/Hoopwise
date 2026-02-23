import Foundation
import SwiftUI
#if os(iOS)
import UIKit
import Photos
#elseif os(macOS)
import AppKit
#endif

// MARK: - Photo Capture Manager
/// Handles photo capture and compression for attendance photos
/// Compresses images to minimize storage usage (max 200KB per photo)
class PhotoCaptureManager {
    static let shared = PhotoCaptureManager()
    
    private init() {}
    
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
        
        // Save to documents directory
        let filename = "attendance_\(sessionId.uuidString).jpg"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent("AttendancePhotos").appendingPathComponent(filename)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: documentsPath.appendingPathComponent("AttendancePhotos"), withIntermediateDirectories: true)
        
        do {
            try finalData.write(to: filePath)
            let sizeKB = Double(finalData.count) / 1024.0
            debugLog("✅ Saved attendance photo: \(filename) (\(String(format: "%.1f", sizeKB))KB)")
            return filePath.path
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
        
        // Save to documents directory
        let filename = "attendance_\(sessionId.uuidString).jpg"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent("AttendancePhotos").appendingPathComponent(filename)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: documentsPath.appendingPathComponent("AttendancePhotos"), withIntermediateDirectories: true)
        
        do {
            try imageData.write(to: filePath)
            let sizeKB = Double(imageData.count) / 1024.0
            debugLog("✅ Saved attendance photo: \(filename) (\(String(format: "%.1f", sizeKB))KB)")
            return filePath.path
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
    func loadAttendancePhoto(from path: String) -> PlatformImage? {
        #if os(iOS)
        return UIImage(contentsOfFile: path)
        #elseif os(macOS)
        return NSImage(contentsOfFile: path)
        #endif
    }
    
    // MARK: - Delete Photo
    func deleteAttendancePhoto(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        debugLog("🗑️ Deleted attendance photo")
    }
    
    // MARK: - Get Storage Info
    func getAttendancePhotosSize() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosPath = documentsPath.appendingPathComponent("AttendancePhotos")
        
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
