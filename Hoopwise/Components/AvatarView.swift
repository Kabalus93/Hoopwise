import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    
    @State private var cachedImage: CacheImage?
    @State private var isLoading = false
    
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
            if let image = cachedImage {
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
        // Check cache synchronously first (fast path)
        if let cached = ImageCacheManager.shared.image(for: cacheId) {
            self.cachedImage = cached
            return
        }
        
        // No image URL - nothing to load
        guard let imageUrl = student.profileImageUrl, !imageUrl.isEmpty else {
            return
        }
        
        // Load asynchronously
        isLoading = true
        Task {
            let image = await ImageCacheManager.shared.loadImage(for: cacheId, from: imageUrl)
            await MainActor.run {
                self.cachedImage = image
                self.isLoading = false
            }
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
