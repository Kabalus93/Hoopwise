import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - DrillMediaThumb
/// A single media tile. Falls back to a kind-tinted placeholder when the
/// thumbnail file is missing (which happens for remote kinds before their
/// thumbnail has finished caching, and for any local file that got cleaned
/// up underneath us). Kind badge is overlaid on the bottom-leading corner.
struct DrillMediaThumb: View {
    let media: DrillMedia
    var size: CGFloat = 120
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            kindBadge
                .padding(8)
            durationBadge
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var background: some View {
        #if os(iOS)
        if let path = media.thumbnailOrPrimaryPath,
           let image = DrillMediaStorage.shared.loadImage(at: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else {
            placeholderFill
        }
        #else
        placeholderFill
        #endif
    }

    private var placeholderFill: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: media.kind.iconName)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var kindBadge: some View {
        Image(systemName: media.kind.iconName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.55), in: Circle())
    }

    @ViewBuilder
    private var durationBadge: some View {
        if media.kind.isVideo, let seconds = media.durationSeconds, seconds > 0 {
            Text(formatDuration(seconds))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - DrillMediaCarousel
/// Horizontal scroll of media tiles, with an optional trailing "+ add" tile.
/// Used on the drill detail screen, the session planner's drill expansion,
/// the live session card, and as the leading thumbnail in compact rows.
///
/// When an `onDelete` handler is supplied each tile picks up a long-press
/// context menu (Open / Delete) — surfaces destructive actions without
/// pushing the user into the dedicated editor sheet.
struct DrillMediaCarousel: View {
    let media: [DrillMedia]
    var tileSize: CGFloat = 120
    var horizontalPadding: CGFloat = 16
    var onTap: ((DrillMedia, Int) -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    /// Optional. When supplied, tiles expose an Open / Delete context menu.
    var onDelete: ((DrillMedia) -> Void)? = nil
    /// Optional. When supplied, `.courtDiagram` tiles add an Edit entry to
    /// the context menu so coaches can reopen the strokes.
    var onEditDiagram: ((DrillMedia) -> Void)? = nil

    private var sortedMedia: [DrillMedia] {
        media.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(sortedMedia.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onTap?(item, index)
                    } label: {
                        DrillMediaThumb(media: item, size: tileSize)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onTap?(item, index)
                        } label: {
                            Label(isChinese ? "查看" : "Open", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        if item.kind == .courtDiagram, let onEditDiagram {
                            Button {
                                onEditDiagram(item)
                            } label: {
                                Label(isChinese ? "编辑战术图" : "Edit Diagram", systemImage: "scribble.variable")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete(item)
                            } label: {
                                Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                if let onAdd {
                    Button(action: onAdd) {
                        addTile
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var addTile: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加" : "Add")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: tileSize, height: tileSize)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
    }
}
