import SwiftUI
#if os(iOS)
import UIKit
import PencilKit
#endif

// MARK: - CourtDiagramEditor
/// Full-screen sheet that lets a coach sketch a play over a half-court
/// underlay using PencilKit.
///
/// Two modes via the `Mode` enum:
///   - `.create`   — new diagram; on save, inserts a fresh `.courtDiagram`
///     `DrillMedia` (with both the flattened JPEG and the editable strokes).
///   - `.edit`     — existing diagram; on save, replaces the JPEG + strokes
///     on disk and updates the same `DrillMedia` row (no new media inserted,
///     so the carousel order is preserved).
struct CourtDiagramEditor: View {
    enum Mode {
        case create(drillId: UUID, existingMediaCount: Int)
        case edit(existing: DrillMedia)
    }

    let mode: Mode
    let onCommit: (DrillMedia) -> Void

    @Environment(\.dismiss) private var dismiss

    #if os(iOS)
    @State private var canvasView = PKCanvasView()
    @State private var drawing = PKDrawing()
    @State private var showToolPicker = true
    #endif
    @State private var isSaving = false

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    private var drillId: UUID {
        switch mode {
        case .create(let drillId, _): return drillId
        case .edit(let existing): return existing.drillId
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Convenience for `create` callers — preserves the prior call site.
    init(drillId: UUID,
         existingMediaCount: Int,
         onSave: @escaping (DrillMedia) -> Void) {
        self.mode = .create(drillId: drillId, existingMediaCount: existingMediaCount)
        self.onCommit = onSave
    }

    /// Designated initializer — supports both modes.
    init(mode: Mode, onCommit: @escaping (DrillMedia) -> Void) {
        self.mode = mode
        self.onCommit = onCommit
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            ZStack {
                GeometryReader { geo in
                    ZStack {
                        CourtBackgroundView()
                            .frame(width: geo.size.width, height: geo.size.height)
                        PKCanvasViewRepresentable(
                            canvasView: $canvasView,
                            drawing: $drawing,
                            showToolPicker: $showToolPicker
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.clear)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                if isSaving {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView(isChinese ? "保存中…" : "Saving…")
                        .progressViewStyle(.circular)
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .navigationTitle(isEditing
                             ? (isChinese ? "编辑战术图" : "Edit Diagram")
                             : (isChinese ? "绘制战术图" : "Draw Diagram"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailingCompat) {
                    Button(isChinese ? "清除" : "Clear") {
                        canvasView.drawing = PKDrawing()
                        drawing = PKDrawing()
                    }
                    .disabled(isSaving || drawing.bounds.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        Task { await persist() }
                    }
                    .disabled(isSaving || drawing.bounds.isEmpty)
                }
            }
            .onAppear { loadExistingStrokesIfNeeded() }
        }
        #else
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 48))
            Text(isChinese ? "战术图编辑暂仅支持 iOS / iPad"
                           : "Diagram editor is iOS / iPad only for now")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        #endif
    }

    #if os(iOS)
    /// In edit mode, hydrate the canvas from the saved `.pkdrawing` blob so
    /// the user picks up where they left off. If the strokes file is missing
    /// (older diagrams from before this field was added), the canvas opens
    /// blank — the JPEG underlay is still visible but not editable as
    /// strokes.
    private func loadExistingStrokesIfNeeded() {
        guard case .edit(let existing) = mode else { return }
        guard let path = existing.strokesPath,
              let data = DrillMediaStorage.shared.loadStrokes(at: path),
              let restored = try? PKDrawing(data: data) else {
            return
        }
        canvasView.drawing = restored
        drawing = restored
    }

    /// Flattens court + strokes into a JPEG, writes both the JPEG and the
    /// raw `PKDrawing` to disk, then dispatches the result to the caller.
    @MainActor
    private func persist() async {
        isSaving = true
        defer { isSaving = false }

        let bounds = canvasView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // 1) Compose court underlay + strokes into a single JPEG.
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(UIScreen.main.scale, 2)
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let composed = renderer.image { _ in
            let courtView = CourtBackgroundView()
                .frame(width: bounds.width, height: bounds.height)
            let host = UIHostingController(rootView: courtView)
            host.view.backgroundColor = .clear
            host.view.bounds = bounds
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)

            let drawingImage = canvasView.drawing.image(from: bounds, scale: format.scale)
            drawingImage.draw(in: bounds)
        }

        // 2) Decide media identity: new vs existing.
        let mediaId: UUID
        let baseMedia: DrillMedia?
        switch mode {
        case .create:
            mediaId = UUID()
            baseMedia = nil
        case .edit(let existing):
            mediaId = existing.id
            baseMedia = existing
        }

        // 3) Persist JPEG + thumbnail + strokes. Strokes are stored as the
        //    raw PKDrawing data blob so re-editing reproduces the exact
        //    paths, pressures, and colors.
        let drillId = self.drillId
        guard let primaryPath = DrillMediaStorage.shared.saveImage(
            composed, drillId: drillId, mediaId: mediaId, targetKB: 500
        ) else {
            return
        }
        let thumbPath = DrillMediaStorage.shared.saveThumbnail(
            composed, drillId: drillId, mediaId: mediaId
        )
        let strokesData = canvasView.drawing.dataRepresentation()
        let strokesPath = DrillMediaStorage.shared.saveStrokes(
            strokesData, drillId: drillId, mediaId: mediaId
        )

        // 4) Build the resulting DrillMedia. In edit mode we preserve the
        //    original sortOrder/caption/createdAt so the carousel doesn't
        //    visually jump.
        let media = DrillMedia(
            id: mediaId,
            drillId: drillId,
            kind: .courtDiagram,
            localPath: primaryPath,
            remoteURL: baseMedia?.remoteURL,
            thumbnailPath: thumbPath,
            strokesPath: strokesPath,
            caption: baseMedia?.caption,
            sortOrder: baseMedia?.sortOrder ?? {
                if case .create(_, let count) = mode { return count }
                return 0
            }(),
            durationSeconds: baseMedia?.durationSeconds,
            createdAt: baseMedia?.createdAt ?? Date(),
            updatedAt: Date()
        )

        onCommit(media)
        HapticFeedback.notification(.success)
        dismiss()
    }
    #endif
}

#if os(iOS)
// MARK: - PKCanvasViewRepresentable
/// Lightweight wrapper around `PKCanvasView` so SwiftUI can host it. Pushes
/// the system tool picker (pencil, marker, eraser, color picker) up when the
/// canvas becomes first responder.
struct PKCanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var drawing: PKDrawing
    @Binding var showToolPicker: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput  // finger + Apple Pencil
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator

        if showToolPicker {
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvasView)
            picker.addObserver(canvasView)
            DispatchQueue.main.async {
                canvasView.becomeFirstResponder()
            }
            context.coordinator.toolPicker = picker
        }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No-op: state changes flow through the delegate so we don't loop
        // on `@Binding var drawing`.
    }

    func makeCoordinator() -> Coordinator { Coordinator($drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var toolPicker: PKToolPicker?

        init(_ drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
#endif
