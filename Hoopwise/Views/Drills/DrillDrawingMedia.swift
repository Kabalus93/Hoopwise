import SwiftUI

/// A drill visual drawn in the Plays editor (see `DrillDrawing`): reading it
/// back from a DrillMedia, and writing the drawing plus the picture of its
/// first step that every other surface shows.
enum DrillDrawingMedia {
    /// The drawing behind `media`, or nil for a photo, a video, a link or a
    /// legacy PencilKit diagram.
    static func drawing(for media: DrillMedia) -> DrillDrawing? {
        guard media.kind == .courtDiagram else { return nil }
        // The synced copy first: on a device that did not draw it there is
        // no file.
        if let synced = DrillDrawing.decode(syncPayload: media.remoteURL) { return synced }
        guard let path = media.strokesPath else { return nil }
        return DrillDrawing.decode(DrillMediaStorage.shared.loadStrokes(at: path))
    }

    /// A drawing whose row came from another device has no files here (or old
    /// ones, after an edit there): write the drawing and its pictures
    /// (bundles and older builds read them) to the paths the row names. True
    /// when something was written.
    @MainActor
    @discardableResult
    static func restoreFiles(for media: DrillMedia) -> Bool {
        guard media.kind == .courtDiagram,
              let drawing = DrillDrawing.decode(syncPayload: media.remoteURL) else { return false }
        let storage = DrillMediaStorage.shared
        guard let data = drawing.encoded else { return false }
        let missing = [media.strokesPath, media.localPath, media.thumbnailPath].contains { path in
            guard let path else { return false }
            return storage.absolutePath(forRelative: path) == nil
        }
        // Edited on another device: the file here is the old drawing.
        let stale = media.strokesPath.flatMap { storage.loadStrokes(at: $0) }.map { $0 != data } ?? false
        guard missing || stale else { return false }
        storage.saveDrawing(data, drillId: media.drillId, mediaId: media.id)
        if let image = picture(of: drawing) {
            storage.saveImage(image, drillId: media.drillId, mediaId: media.id, targetKB: 500)
            storage.saveThumbnail(image, drillId: media.drillId, mediaId: media.id)
        }
        return true
    }

    /// What the full-screen viewer pages through: photos, videos and links,
    /// in order. Drawings play in their own player instead.
    static func viewerMedia(_ media: [DrillMedia]) -> [DrillMedia] {
        media.sorted { $0.sortOrder < $1.sortOrder }.filter { drawing(for: $0) == nil }
    }

    /// Writes `drawing` and its picture, and returns the media to add (new)
    /// or update (`existing` — same id, order, caption and creation date).
    @MainActor
    static func save(_ drawing: DrillDrawing, drillId: UUID, existing: DrillMedia?, sortOrder: Int) -> DrillMedia? {
        let mediaId = existing?.id ?? UUID()
        guard let data = drawing.encoded,
              let drawingPath = DrillMediaStorage.shared.saveDrawing(data, drillId: drillId, mediaId: mediaId),
              let image = picture(of: drawing),
              let primaryPath = DrillMediaStorage.shared.saveImage(image, drillId: drillId, mediaId: mediaId, targetKB: 500)
        else { return nil }
        // A legacy strokes file under the same id would otherwise linger.
        if let old = existing?.strokesPath, old != drawingPath,
           let absolute = DrillMediaStorage.shared.absolutePath(forRelative: old) {
            try? FileManager.default.removeItem(atPath: absolute)
        }
        return DrillMedia(
            id: mediaId,
            drillId: drillId,
            kind: .courtDiagram,
            localPath: primaryPath,
            // The drawing itself, so it syncs (see DrillDrawing.syncPayload).
            remoteURL: drawing.syncPayload,
            thumbnailPath: DrillMediaStorage.shared.saveThumbnail(image, drillId: drillId, mediaId: mediaId),
            strokesPath: drawingPath,
            caption: existing?.caption,
            sortOrder: existing?.sortOrder ?? sortOrder,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    /// The first step on its court, light, about 1200 pt wide.
    @MainActor
    static func picture(of drawing: DrillDrawing) -> UIImage? {
        guard let first = drawing.steps.first else { return nil }
        let width: CGFloat = 1200
        let height = width / JournalPlayCourt.aspectRatio(drawing.court)
        let view = JournalPlayDiagramView(diagram: first.diagram, court: drawing.court)
            .frame(width: width, height: height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// A drill drawing shown where it is read — the drill page and the viewer —
/// as the Plays step player: caption, "Step 1 of 3", ‹ ▶ › and each step's
/// text (Luther, November 2026: a three-step drawing showed only its first
/// step, as a thumbnail, and the others were reachable only through Edit).
struct DrillDrawingPlayer: View {
    let drawing: DrillDrawing
    var viewportHeight: CGFloat?
    @State private var index = 0

    var body: some View {
        JournalPlayStepPlayer(drawing: drawing, index: $index, viewportHeight: viewportHeight)
            .onChange(of: drawing.steps.count) { _, count in index = min(index, max(count - 1, 0)) }
    }
}

/// On the drill page: the drawing, playable, with Edit and Delete above it.
struct DrillDrawingCard: View {
    let drawing: DrillDrawing
    var title: String
    var onEdit: () -> Void
    var onDelete: () -> Void
    /// Names the drawing (its caption) — "Corner shot", "Option: 1v2".
    var onRename: ((String) -> Void)?
    /// Off under the toggle, which already names the drawing.
    var showsTitle = true
    @State private var confirmingDelete = false
    @State private var renaming = false
    @State private var newName = ""

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if showsTitle {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if drawing.steps.count > 1 {
                    Text(isChinese ? "\(drawing.steps.count) 步" : "\(drawing.steps.count) steps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onEdit) {
                    Label(isChinese ? "编辑" : "Edit", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("drill.drawing.edit")
                Menu {
                    if onRename != nil {
                        Button {
                            newName = title
                            renaming = true
                        } label: {
                            Label(isChinese ? "重命名" : "Rename", systemImage: "character.cursor.ibeam")
                        }
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label(isChinese ? "删除图示" : "Delete Drawing", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .accessibilityIdentifier("drill.drawing.more")
            }
            DrillDrawingPlayer(drawing: drawing)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .confirmationDialog(isChinese ? "删除这个图示？" : "Delete this drawing?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(isChinese ? "删除" : "Delete", role: .destructive, action: onDelete)
        }
        .alert(isChinese ? "图示名称" : "Name this drawing", isPresented: $renaming) {
            TextField(isChinese ? "例如：底角投篮" : "e.g. Corner shot", text: $newName)
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "保存" : "Save") { onRename?(newName.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
}

/// A drill's drawings on its page (Luther, November 2026: two drawings were
/// stacked one under the other). Wide windows put them SIDE BY SIDE; narrower
/// ones show one at a time with a TOGGLE of their names on top — the way a
/// drill's options or wrinkles are read. A drawing's name is its caption,
/// else "Drawing 2".
struct DrillDrawingsView: View {
    let drawings: [(media: DrillMedia, drawing: DrillDrawing)]
    var onEdit: (DrillMedia) -> Void
    var onDelete: (DrillMedia) -> Void
    var onRename: (DrillMedia, String) -> Void

    @State private var selected: UUID?
    @State private var width: CGFloat = 0

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    /// Two courts fit beside each other from about this width.
    static let sideBySideWidth: CGFloat = 900

    static func name(_ media: DrillMedia, index: Int, of count: Int, chinese: Bool) -> String {
        if let caption = media.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty { return caption }
        if count == 1 { return chinese ? "图示" : "Drawing" }
        return chinese ? "图示 \(index + 1)" : "Drawing \(index + 1)"
    }

    private func name(_ i: Int) -> String {
        Self.name(drawings[i].media, index: i, of: drawings.count, chinese: isChinese)
    }

    private func card(_ i: Int, showsTitle: Bool = true) -> some View {
        let pair = drawings[i]
        return DrillDrawingCard(drawing: pair.drawing, title: name(i),
                                onEdit: { onEdit(pair.media) },
                                onDelete: { onDelete(pair.media) },
                                onRename: { onRename(pair.media, $0) },
                                showsTitle: showsTitle)
            .id(pair.media.id)
    }

    var body: some View {
        SwiftUI.Group {
            if drawings.count < 2 {
                ForEach(drawings.indices, id: \.self) { card($0) }
            } else if width >= Self.sideBySideWidth {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .top),
                                    GridItem(.flexible(), spacing: 20, alignment: .top)],
                          alignment: .leading, spacing: 20) {
                    ForEach(drawings.indices, id: \.self) { card($0) }
                }
                .accessibilityIdentifier("drill.drawings.sideBySide")
            } else {
                let current = drawings.firstIndex { $0.media.id == selected } ?? 0
                VStack(alignment: .leading, spacing: 12) {
                    switcher(current: current)
                    card(current, showsTitle: false)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private func switcher(current: Int) -> some View {
        let binding = Binding<UUID>(get: { drawings[current].media.id }, set: { selected = $0 })
        if drawings.count <= 4 {
            Picker(isChinese ? "图示" : "Drawing", selection: binding) {
                ForEach(drawings.indices, id: \.self) { i in
                    Text(name(i)).tag(drawings[i].media.id)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drill.drawings.switch")
        } else {
            Picker(isChinese ? "图示" : "Drawing", selection: binding) {
                ForEach(drawings.indices, id: \.self) { i in
                    Text(name(i)).tag(drawings[i].media.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("drill.drawings.switch")
        }
    }
}

/// A drawing opened from a session plan: a popup titled with the drill, the
/// step player, Done (Luther, November 2026: the full-screen viewer blacked
/// out the whole window around a small court).
struct DrillDrawingSheet: View {
    let title: String
    let drawing: DrillDrawing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    DrillDrawingPlayer(drawing: drawing, viewportHeight: proxy.size.height + 120)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
            }
            .background(JPalette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }
}
