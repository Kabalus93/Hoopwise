import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Thumbnail Generation
/// Produce a small square JPEG (~`maxDimension`pt) suitable for inline storage on a record.
/// Used so list rows can render instantly without waiting on a CKAsset/file decode.
func makeProfileThumbnailData(from imageData: Data, maxDimension: CGFloat = 120) -> Data? {
    #if os(iOS)
    guard let img = UIImage(data: imageData) else { return nil }
    let ratio = max(img.size.width, img.size.height) / maxDimension
    let target = ratio > 1
        ? CGSize(width: img.size.width / ratio, height: img.size.height / ratio)
        : img.size
    let renderer = UIGraphicsImageRenderer(size: target)
    let resized = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
    return resized.jpegData(compressionQuality: 0.7)
    #elseif os(macOS)
    guard let img = NSImage(data: imageData) else { return nil }
    let ratio = max(img.size.width, img.size.height) / maxDimension
    let target = ratio > 1
        ? NSSize(width: img.size.width / ratio, height: img.size.height / ratio)
        : img.size
    let resized = NSImage(size: target)
    resized.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: target))
    resized.unlockFocus()
    guard let tiff = resized.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    #endif
}

// MARK: - Avatar View (Minimalist)
struct AvatarView: View {
    let initials: String
    let color: AvatarColor
    var size: CGFloat = 44
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.avatarColor(color), Color.avatarColor(color).opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Student Avatar View
struct StudentAvatarView: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    var size: CGFloat = 44
    var showBadge: Bool = false
    var badgeCount: Int = 0
    var showOnlineIndicator: Bool = false
    var showCategoryRing: Bool = false
    /// Pre-loaded image. When non-nil, the avatar renders this directly
    /// and skips the `.onAppear`-driven cache load. Used by the PDF
    /// snapshot pipeline, which doesn't get an `onAppear` callback before
    /// the renderer reads pixels.
    var imageOverride: CacheImage? = nil

    @State private var cachedImage: CacheImage?
    @State private var isLoading = false

    private var displayImage: CacheImage? {
        imageOverride ?? cachedImage
    }
    
    private var cacheId: String {
        ImageCacheManager.studentImageId(student.id)
    }
    
    /// Category color for the ring based on student's age group
    private var categoryColor: Color {
        dataManager.categoryColor(for: student)
    }
    
    /// Ring width based on avatar size
    private var ringWidth: CGFloat {
        max(2, size * 0.06)
    }
    
    /// Total size including ring
    private var totalSize: CGFloat {
        showCategoryRing ? size + ringWidth * 2 + 4 : size
    }
    
    var body: some View {
        ZStack {
            // Use cached image or placeholder (centered)
            if let image = displayImage {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                #elseif os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                #endif
            } else {
                AvatarView(initials: student.initials, color: student.avatarColor, size: size)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                    )
            }
            
            // Category color ring (overlay on top, centered)
            if showCategoryRing {
                Circle()
                    .stroke(categoryColor, lineWidth: ringWidth)
                    .frame(width: size + ringWidth + 2, height: size + ringWidth + 2)
            }
            
            // Badge overlay
            if showBadge && badgeCount > 0 {
                Text("\(min(badgeCount, 99))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(AppTheme.accentColor)
                    .clipShape(Circle())
                    .offset(x: size * 0.35, y: size * 0.35)
            }
            
            // Online indicator overlay
            if showOnlineIndicator {
                Circle()
                    .fill(AppTheme.successColor)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .offset(x: size * 0.35, y: size * 0.35)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
        }
        .onAppear {
            loadCachedImage()
        }
    }
    
    private func loadCachedImage() {
        // 1) Warm L1 (in-memory) — re-mounts of the same row are O(1).
        if let cached = ImageCacheManager.shared.image(for: cacheId) {
            self.cachedImage = cached
            return
        }

        // 2) Inline thumbnail on the record itself.
        if let data = student.thumbnailImageData, let image = CacheImage(data: data) {
            self.cachedImage = image
            ImageCacheManager.shared.cacheInMemory(image, for: cacheId)
            return
        }

        // 3) Full image on record but no thumbnail — decode now, push to L1,
        //    backfill the thumbnail so the next session reads it inline.
        if let data = student.profileImageData, let image = CacheImage(data: data) {
            self.cachedImage = image
            ImageCacheManager.shared.cacheInMemory(image, for: cacheId)
            backfillThumbnail(from: data)
            return
        }

        // 4) Legacy file/url path. Goes through the cache, which writes to disk.
        guard let imageUrl = student.profileImageUrl, !imageUrl.isEmpty else { return }
        isLoading = true
        Task {
            let image = await ImageCacheManager.shared.loadImage(for: cacheId, from: imageUrl)
            await MainActor.run {
                self.cachedImage = image
                self.isLoading = false
            }
        }
    }

    private func backfillThumbnail(from imageData: Data) {
        let studentId = student.id
        Task.detached(priority: .utility) {
            guard let thumb = makeProfileThumbnailData(from: imageData) else { return }
            await MainActor.run {
                guard var s = dataManager.students.first(where: { $0.id == studentId }),
                      s.thumbnailImageData == nil else { return }
                s.thumbnailImageData = thumb
                dataManager.updateStudent(s)
            }
        }
    }
}

// MARK: - Student Image View (rectangular)
/// Drop-in replacement for `AsyncImage(url: URL(string: student.profileImageUrl))`
/// that resolves through the cache pipeline (inline thumbnail → inline data →
/// in-memory cache → on-disk cache → file URL). Never hits the network.
struct StudentImageView<Placeholder: View>: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var cachedImage: CacheImage?

    private var cacheId: String { ImageCacheManager.studentImageId(student.id) }

    var body: some View {
        Group {
            if let cachedImage {
                #if canImport(UIKit)
                Image(uiImage: cachedImage).resizable().aspectRatio(contentMode: contentMode)
                #elseif canImport(AppKit)
                Image(nsImage: cachedImage).resizable().aspectRatio(contentMode: contentMode)
                #endif
            } else {
                placeholder()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let cached = ImageCacheManager.shared.image(for: cacheId) {
            cachedImage = cached
            return
        }
        if let data = student.thumbnailImageData ?? student.profileImageData,
           let image = CacheImage(data: data) {
            cachedImage = image
            ImageCacheManager.shared.cacheInMemory(image, for: cacheId)
            return
        }
        guard let urlString = student.profileImageUrl, !urlString.isEmpty else { return }
        Task {
            let image = await ImageCacheManager.shared.loadImage(for: cacheId, from: urlString)
            await MainActor.run { cachedImage = image }
        }
    }
}

// MARK: - Avatar Group View
struct AvatarGroupView: View {
    let students: [Student]
    var maxDisplay: Int = 3
    var size: CGFloat = 32
    
    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(students.prefix(maxDisplay).enumerated()), id: \.element.id) { index, student in
                AvatarView(initials: student.initials, color: student.avatarColor, size: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .zIndex(Double(maxDisplay - index))
            }
            
            if students.count > maxDisplay {
                ZStack {
                    Circle()
                        .fill(AppTheme.surfaceColor)
                    
                    Text("+\(students.count - maxDisplay)")
                        .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
            }
        }
    }
}

// MARK: - Icon Avatar
struct IconAvatar: View {
    let icon: String
    var size: CGFloat = 44
    var color: Color = AppTheme.accentColor
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12))
            .clipShape(Circle())
    }
}

#Preview {
    VStack(spacing: 24) {
        AvatarView(initials: "MC", color: .blue, size: 60)
        StudentAvatarView(student: Student.samples[0], size: 50, showBadge: true, badgeCount: 3)
        StudentAvatarView(student: Student.samples[0], size: 50, showOnlineIndicator: true)
        AvatarGroupView(students: Student.samples, maxDisplay: 3)
        IconAvatar(icon: "basketball.fill", size: 48, color: AppTheme.accentColor)
    }
    .padding()
    .background(AppTheme.background)
}
