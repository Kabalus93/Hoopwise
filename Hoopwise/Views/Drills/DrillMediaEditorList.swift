import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - DrillMediaEditorSheet
/// Self-contained "manage visuals" sheet — reorder via drag handles, swipe to
/// delete, and edit per-row captions. Reorder + delete need a `List`, so this
/// is its own screen rather than something embedded inline in the drill edit
/// form.
///
/// Presented from the carousel header on `DrillDetailView`.
struct DrillMediaEditorSheet: View {
    let drillId: UUID
    let media: [DrillMedia]

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    private var sorted: [DrillMedia] {
        media.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(sorted, id: \.id) { item in
                                DrillMediaEditorRow(
                                    media: item,
                                    isChinese: isChinese,
                                    onCaptionCommit: { newCaption in
                                        var updated = item
                                        updated.caption = newCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? nil
                                            : newCaption
                                        updated.updatedAt = Date()
                                        dataManager.updateDrillMedia(updated)
                                    }
                                )
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    let target = sorted[index]
                                    dataManager.deleteDrillMedia(target)
                                    HapticFeedback.impact(.medium)
                                }
                            }
                            .onMove { source, destination in
                                var working = sorted
                                working.move(fromOffsets: source, toOffset: destination)
                                dataManager.reorderDrillMedia(
                                    forDrillId: drillId,
                                    orderedIds: working.map(\.id)
                                )
                                HapticFeedback.impact(.light)
                            }
                        } footer: {
                            Text(isChinese
                                 ? "拖动 ≡ 调整顺序；左滑删除；点击说明可编辑。"
                                 : "Drag ≡ to reorder, swipe to delete, tap a caption to edit.")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle(isChinese ? "管理素材" : "Manage Visuals")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(isChinese ? "暂无素材" : "No visuals yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DrillMediaEditorRow
/// Single row inside the editor sheet. Caption is committed on submit /
/// loss-of-focus rather than per keystroke, so we don't spam SwiftData.
private struct DrillMediaEditorRow: View {
    let media: DrillMedia
    let isChinese: Bool
    let onCaptionCommit: (String) -> Void

    @State private var captionDraft: String
    @FocusState private var captionFocused: Bool

    init(media: DrillMedia,
         isChinese: Bool,
         onCaptionCommit: @escaping (String) -> Void) {
        self.media = media
        self.isChinese = isChinese
        self.onCaptionCommit = onCaptionCommit
        _captionDraft = State(initialValue: media.caption ?? "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DrillMediaThumb(media: media, size: 60, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: media.kind.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(media.kind.localizedLabel(isChinese: isChinese))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !media.kind.isLocal {
                        Text(isChinese ? "· 在线" : "· online")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                TextField(
                    isChinese ? "添加说明（可选）" : "Add caption (optional)",
                    text: $captionDraft,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(.subheadline)
                .focused($captionFocused)
                .submitLabel(.done)
                .onSubmit { onCaptionCommit(captionDraft) }
                .onChange(of: captionFocused) { _, focused in
                    if !focused, captionDraft != (media.caption ?? "") {
                        onCaptionCommit(captionDraft)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
