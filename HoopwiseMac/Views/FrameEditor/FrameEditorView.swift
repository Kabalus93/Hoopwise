import SwiftUI

/// Play Editor v2 — the frame authoring surface.
///
/// Canvas on top, frame strip along the bottom. There is no inspector: every
/// action is authored by dragging on the court and every caption is typed in
/// the strip. That is the Phase B bar, and the layout is arranged so failing it
/// would be obvious — there is nowhere else to go.
///
/// The Apple coat (auto-collapse, HUD, materials) is Phase C; this is the
/// mechanics.
struct FrameEditorView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.undoManager) private var systemUndoManager
    @ObservedObject var model: FrameEditorModel

    @State private var keys = FrameEditorKeyDispatcher()
    @State private var placementKind: DiagramEntityKind?
    @State private var showingNewPlay = false
    @State private var newPlayName = ""
    @FocusState private var newPlayFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                toolStrip
                FrameCanvasView(model: model, placementKind: placementKind) {
                    // Sticky placement: a whole lineup goes down without
                    // re-picking the tool.
                }
                .frame(minWidth: 460, minHeight: 320)
            }
            Divider()
            FrameStripView(model: model)
                .frame(height: 176)
        }
        .toolbar { toolbar }
        .navigationTitle(model.diagramName)
        .navigationSubtitle(subtitle)
        .onAppear {
            model.dataManager = dataManager
            model.undoManager = systemUndoManager
            keys.install(model: model)
            guard !model.hasAttached else { return }
            model.hasAttached = true
            if let stored = dataManager.allPlayDiagrams()
                .first(where: { !($0.diagram.node($0.diagram.rootNodeId)?.frames.isEmpty ?? true) }) {
                model.load(stored.diagram, name: stored.name)
            }
            model.startAutosave()
            #if DEBUG
            FrameDemoScenario.applyIfRequested(to: model)
            #endif
        }
        .onChange(of: systemUndoManager) { _, manager in model.undoManager = manager }
        .onDisappear {
            keys.uninstall()
            model.save()
            model.purgeUndoActions()
        }
        .sheet(isPresented: $showingNewPlay) {
            newPlaySheet.dismissesOnPresentationEscape { showingNewPlay = false }
        }
    }

    private var subtitle: String {
        let frames = model.frameCount
        let duration = model.sequence.duration
        return String(format: "%d frame%@ · %.1fs", frames, frames == 1 ? "" : "s", duration)
    }

    // MARK: - Tools

    /// Four tools, and three of them only place things. Authoring is dragging.
    private var toolStrip: some View {
        VStack(spacing: 4) {
            toolButton("Select", "cursorarrow", isOn: placementKind == nil
                       && model.armedTool == .select) {
                placementKind = nil
                model.armedTool = .select
            }
            toolButton("Screen", "rectangle.compress.vertical",
                       isOn: model.armedTool == .screen) {
                placementKind = nil
                model.armedTool = model.armedTool == .screen ? .select : .screen
            }
            Divider().frame(width: 22)
            toolButton("Offense", "person.fill",
                       isOn: isPlacing(.offense)) {
                model.armedTool = .select
                placementKind = .player(team: .offense, number: nil, role: nil)
            }
            toolButton("Defense", "person.fill.badge.minus",
                       isOn: isPlacing(.defense)) {
                model.armedTool = .select
                placementKind = .player(team: .defense, number: nil, role: nil)
            }
            toolButton("Ball", "basketball.fill", isOn: isPlacingBall) {
                model.armedTool = .select
                placementKind = .ball
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 40)
        .background(.regularMaterial)
    }

    private func isPlacing(_ team: CourtTeam) -> Bool {
        if case .player(let t, _, _)? = placementKind { return t == team }
        return false
    }

    private var isPlacingBall: Bool {
        if case .ball? = placementKind { return true }
        return false
    }

    private func toolButton(_ title: String, _ icon: String, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 26)
                .foregroundStyle(isOn ? Color.white : .primary)
                .background(isOn ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("New Play…") {
                    newPlayName = "Play \(dataManager.allPlayDiagrams().count + 1)"
                    showingNewPlay = true
                }
                Divider()
                ForEach(dataManager.allPlayDiagrams(), id: \.id) { row in
                    Button(row.name) {
                        model.save()
                        model.load(row.diagram, name: row.name)
                    }
                }
            } label: {
                Label("Plays", systemImage: "square.stack")
            }
            .help("Switch play, or start a new one")

            Button { model.previousFrame() } label: {
                Label("Previous Frame", systemImage: "chevron.left")
            }
            .disabled(model.frameIndex == 0)
            .help("Previous frame (←)")

            Text("\(model.frameIndex + 1)/\(max(1, model.frameCount))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button { model.nextFrame() } label: {
                Label("Next Frame", systemImage: "chevron.right")
            }
            .disabled(model.frameIndex >= model.frameCount - 1)
            .help("Next frame (→)")
        }
    }

    private var newPlaySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Play").font(.headline)
            TextField("Play name", text: $newPlayName)
                .focused($newPlayFocused)
                .onSubmit(commitNewPlay)
            HStack {
                Button("Cancel") { showingNewPlay = false }
                Spacer()
                Button("Create", action: commitNewPlay)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPlayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { newPlayFocused = true }
    }

    private func commitNewPlay() {
        let name = newPlayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        showingNewPlay = false
        model.save()
        model.load(FrameEditorModel.newDiagram(), name: name)
        model.save()
    }
}
