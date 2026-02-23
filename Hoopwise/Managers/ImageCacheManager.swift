import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
typealias CacheImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias CacheImage = NSImage
#endif

/// Manages local image caching and storage to reduce memory usage and improve performance
@MainActor
final class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    // MARK: - Properties
    
    /// In-memory cache with automatic eviction (limited size)
    private let memoryCache = NSCache<NSString, ImageWrapper>()
    
    /// Pending image loads to avoid duplicate requests
    private var pendingLoads: [String: Task<CacheImage?, Never>] = [:]
    
    /// Images that need to be synced to cloud
    @Published private(set) var pendingSyncIds: Set<String> = []
    
    /// Directory for storing cached images
    private let cacheDirectory: URL
    
    /// Maximum memory cache size (50 images)
    private let maxMemoryCacheCount = 50
    
    /// Maximum disk cache size (100 MB)
    private let maxDiskCacheSize: Int64 = 100 * 1024 * 1024
    
    // MARK: - Initialization
    
    private init() {
        // Setup cache directory
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = maxMemoryCacheCount
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        // Clean old cache on init
        Task {
            await cleanDiskCacheIfNeeded()
        }
    }
    
    // MARK: - Public API
    
    /// Get image for an entity (student, player, coach, etc.)
    /// Returns cached image or nil if not available
    func image(for id: String) -> CacheImage? {
        // Check memory cache first
        if let wrapper = memoryCache.object(forKey: id as NSString) {
            return wrapper.image
        }
        
        // Check disk cache
        if let image = loadFromDisk(id: id) {
            // Store in memory cache for faster access
            cacheInMemory(image, for: id)
            return image
        }
        
        return nil
    }
    
    /// Load image asynchronously with automatic caching
    func loadImage(for id: String, from urlString: String?) async -> CacheImage? {
        // Check memory cache
        if let wrapper = memoryCache.object(forKey: id as NSString) {
            return wrapper.image
        }
        
        // Check disk cache
        if let image = loadFromDisk(id: id) {
            cacheInMemory(image, for: id)
            return image
        }
        
        // Check if already loading
        if let existingTask = pendingLoads[id] {
            return await existingTask.value
        }
        
        // Load from URL if provided
        guard var urlString = urlString, !urlString.isEmpty else {
            return nil
        }
        
        // Handle local file paths that may not exist after app reinstall
        // Try to construct Supabase Storage URL as fallback
        if urlString.hasPrefix("file://") || urlString.hasPrefix("/var/") || urlString.hasPrefix("/Users/") {
            // Check if local file exists
            let localPath = urlString.replacingOccurrences(of: "file://", with: "")
            if !FileManager.default.fileExists(atPath: localPath) {
                // Local file missing - try Supabase Storage fallback
                // Extract student ID from the path (format: .../StudentImages/UUID.jpg)
                if let studentId = extractStudentId(from: urlString) {
                    urlString = constructSupabaseStorageUrl(for: studentId)
                    debugLog("🔄 Local image missing, trying Supabase Storage: \(urlString)")
                } else {
                    return nil
                }
            }
        }
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        let task = Task<CacheImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = CacheImage(data: data) {
                    // Save to disk and memory
                    await self.saveImage(image, for: id)
                    return image
                }
                return nil
            } catch {
                debugLog("⚠️ Failed to load image for \(id): \(error)")
                return nil
            }
        }
        
        pendingLoads[id] = task
        let result = await task.value
        pendingLoads.removeValue(forKey: id)
        
        return result
    }
    
    /// Save image locally (and mark for cloud sync if needed)
    func saveImage(_ image: CacheImage, for id: String, syncToCloud: Bool = false) async {
        // Resize if too large (max 512x512 for avatars)
        let resizedImage = resizeImageIfNeeded(image, maxSize: 512)
        
        // Save to memory cache
        cacheInMemory(resizedImage, for: id)
        
        // Save to disk
        saveToDisk(resizedImage, id: id)
        
        // Mark for cloud sync if needed
        if syncToCloud {
            pendingSyncIds.insert(id)
        }
    }
    
    /// Save image from Data
    func saveImageData(_ data: Data, for id: String, syncToCloud: Bool = false) async {
        guard let image = CacheImage(data: data) else { return }
        await saveImage(image, for: id, syncToCloud: syncToCloud)
    }
    
    /// Get image data for syncing to cloud
    func imageData(for id: String) -> Data? {
        guard let image = image(for: id) else { return nil }
        return imageToData(image)
    }
    
    /// Mark image as synced (remove from pending)
    func markAsSynced(id: String) {
        pendingSyncIds.remove(id)
    }
    
    /// Clear all pending syncs
    func clearPendingSyncs() {
        pendingSyncIds.removeAll()
    }
    
    /// Clear specific image from cache
    func clearImage(for id: String) {
        memoryCache.removeObject(forKey: id as NSString)
        let fileURL = cacheDirectory.appendingPathComponent("\(id).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Clear all cached images
    func clearAllCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Preload images for a list of IDs (background loading)
    func preloadImages(ids: [String], urlProvider: @escaping (String) -> String?) {
        Task.detached(priority: .background) { [weak self] in
            for id in ids {
                guard let self = self else { return }
                let url = urlProvider(id)
                _ = await self.loadImage(for: id, from: url)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Extract student ID from a local file path like .../StudentImages/UUID.jpg
    private func extractStudentId(from path: String) -> String? {
        // Try to extract UUID from path
        // Expected format: .../StudentImages/UUID.jpg or student_UUID
        let components = path.components(separatedBy: "/")
        if let filename = components.last {
            // Remove extension
            let name = filename.replacingOccurrences(of: ".jpg", with: "")
                               .replacingOccurrences(of: ".jpeg", with: "")
                               .replacingOccurrences(of: ".png", with: "")
            // Check if it's a valid UUID
            if UUID(uuidString: name) != nil {
                return name
            }
        }
        return nil
    }
    
    /// Construct Supabase Storage URL for a student image
    private func constructSupabaseStorageUrl(for studentId: String) -> String {
        // Supabase Storage public URL format
        return "\(SupabaseConfig.url)/storage/v1/object/public/profile-images/students/\(studentId).jpg"
    }
    
    private func cacheInMemory(_ image: CacheImage, for id: String) {
        let wrapper = ImageWrapper(image: image)
        let cost = imageCost(image)
        memoryCache.setObject(wrapper, forKey: id as NSString, cost: cost)
    }
    
    private func loadFromDisk(id: String) -> CacheImage? {
        let fileURL = cacheDirectory.appendingPathComponent("\(id).jpg")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return CacheImage(data: data)
        } catch {
            return nil
        }
    }
    
    private func saveToDisk(_ image: CacheImage, id: String) {
        guard let data = imageToData(image) else { return }
        let fileURL = cacheDirectory.appendingPathComponent("\(id).jpg")
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("⚠️ Failed to save image to disk: \(error)")
        }
    }
    
    private func resizeImageIfNeeded(_ image: CacheImage, maxSize: CGFloat) -> CacheImage {
        #if canImport(UIKit)
        let size = image.size
        guard size.width > maxSize || size.height > maxSize else { return image }
        
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resized ?? image
        #elseif canImport(AppKit)
        let size = image.size
        guard size.width > maxSize || size.height > maxSize else { return image }
        
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
        #endif
    }
    
    private func imageToData(_ image: CacheImage) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: 0.7)
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #endif
    }
    
    private func imageCost(_ image: CacheImage) -> Int {
        #if canImport(UIKit)
        return Int(image.size.width * image.size.height * 4)
        #elseif canImport(AppKit)
        return Int(image.size.width * image.size.height * 4)
        #endif
    }
    
    private func cleanDiskCacheIfNeeded() async {
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return
        }
        
        // Calculate total size
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, date: Date, size: Int64)] = []
        
        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = attrs.contentModificationDate,
                  let size = attrs.fileSize else { continue }
            
            totalSize += Int64(size)
            fileInfos.append((file, date, Int64(size)))
        }
        
        // If over limit, remove oldest files
        if totalSize > maxDiskCacheSize {
            let sorted = fileInfos.sorted { $0.date < $1.date }
            var removed: Int64 = 0
            let target = totalSize - maxDiskCacheSize / 2 // Remove to 50% capacity
            
            for file in sorted {
                guard removed < target else { break }
                try? fileManager.removeItem(at: file.url)
                removed += file.size
            }
        }
    }
}

// MARK: - Image Wrapper for NSCache

private class ImageWrapper {
    let image: CacheImage
    
    init(image: CacheImage) {
        self.image = image
    }
}

// MARK: - SwiftUI View for Cached Images

struct CachedImageView: View {
    let id: String
    let urlString: String?
    let placeholder: AnyView
    let size: CGSize?
    
    @State private var image: CacheImage?
    @State private var isLoading = false
    
    init(id: String, urlString: String?, placeholder: some View, size: CGSize? = nil) {
        self.id = id
        self.urlString = urlString
        self.placeholder = AnyView(placeholder)
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = image {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else if isLoading {
                placeholder
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.7)
                    )
            } else {
                placeholder
            }
        }
        .frame(width: size?.width, height: size?.height)
        .clipped()
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // Check cache first (synchronous)
        if let cached = ImageCacheManager.shared.image(for: id) {
            self.image = cached
            return
        }
        
        // Load async
        guard !isLoading else { return }
        isLoading = true
        
        Task {
            let loaded = await ImageCacheManager.shared.loadImage(for: id, from: urlString)
            await MainActor.run {
                self.image = loaded
                self.isLoading = false
            }
        }
    }
}

// MARK: - Convenience Extensions

extension ImageCacheManager {
    /// Generate cache ID for a student
    static func studentImageId(_ studentId: UUID) -> String {
        "student_\(studentId.uuidString)"
    }
    
    /// Generate cache ID for a player
    static func playerImageId(_ playerId: UUID) -> String {
        "player_\(playerId.uuidString)"
    }
    
    /// Generate cache ID for a coach
    static func coachImageId(_ coachId: UUID) -> String {
        "coach_\(coachId.uuidString)"
    }
    
    /// Generate cache ID for a program
    static func programImageId(_ programId: UUID) -> String {
        "program_\(programId.uuidString)"
    }
    
    /// Generate cache ID for a session header image
    static func sessionImageId(_ sessionId: UUID) -> String {
        "session_\(sessionId.uuidString)"
    }
}
