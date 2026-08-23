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
    @State private var replayHints = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // THE CANVAS IS THE DOCUMENT: the palette floats ON it rather than
            // taking a column, and nothing else competes for width.
            FrameCanvasView(model: model, placementKind: placementKind) {
                // Sticky placement: a whole lineup goes down without
                // re-picking the tool.
            }
            .frame(minWidth: 460, minHeight: 320)
            .overlay(alignment: .topLeading) {
                if !model.isPlayingBack { floatingPalette.padding(12) }
            }
            .overlay(alignment: .bottom) {
                if !model.isPlayingBack {
                    FrameCoachMarks(forceShow: replayHints) { replayHints = false }
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) { if !model.isPlayingBack { hud } }
            Divider()
            // PLAYBACK REPLACES THE STRIP, it does not sit beside it: the play
            // is the document while it runs, and two rows of chrome would take
            // the court back that Phase C spent its effort winning.
            if model.isPlayingBack {
                FrameScrubBar(model: model)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom))
            } else {
                // Sized to what the strip needs — every point it does not take
                // is court, and the canvas-share bar is measured against the
                // window.
                FrameStripView(model: model)
                    .frame(height: 130)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isPlayingBack)
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

    /// Floating palette, Apple-pro style: a compact material capsule ON the
    /// canvas. Every tooltip names the GESTURE, not just the tool — the hand
    /// test found the screen tool only by going looking, so each control now
    /// says what dragging it does.
    private var floatingPalette: some View {
        VStack(spacing: 3) {
            paletteButton("Select", "cursorarrow",
                          help: "Select · drag a player to draw a cut",
                          isOn: placementKind == nil && model.armedTool == .select) {
                placementKind = nil
                model.armedTool = .select
            }
            paletteButton("Screen", "rectangle.compress.vertical",
                          help: "Screen (S) · or hold ⌥ and drag a player",
                          isOn: model.armedTool == .screen) {
                placementKind = nil
                model.armedTool = model.armedTool == .screen ? .select : .screen
            }
            Divider().frame(width: 20)
            paletteButton("Offense", "person.fill",
                          help: "Place an offensive player · click the court",
                          isOn: isPlacing(.offense)) {
                model.armedTool = .select
                placementKind = .player(team: .offense, number: nil, role: nil)
            }
            paletteButton("Defense", "person.fill.badge.minus",
                          help: "Place a defender · click the court",
                          isOn: isPlacing(.defense)) {
                model.armedTool = .select
                placementKind = .player(team: .defense, number: nil, role: nil)
            }
            paletteButton("Ball", "basketball.fill",
                          help: "Place the ball · then drag it to a player to pass, or to the rim to shoot",
                          isOn: isPlacingBall) {
                model.armedTool = .select
                placementKind = .ball
            }
            Divider().frame(width: 20)
            paletteButton("Hints", "questionmark",
                          help: "Show the gesture hints again",
                          isOn: replayHints) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    replayHints.toggle()
                }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07))
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private func paletteButton(_ title: String, _ icon: String, help: String,
                               isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 24)
                .foregroundStyle(isOn ? Color.white : .primary)
                .background(isOn ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The HUD, positioned at whatever is selected. Springs in, and stands
    /// still under Reduce Motion.
    @ViewBuilder
    private var hud: some View {
        if let subject = model.hudSubject, let anchor = model.hudAnchor {
            FrameHUDView(model: model, subject: subject)
                .fixedSize()
                .offset(x: max(12, anchor.x + 18), y: max(12, anchor.y - 20))
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                           value: model.hudAnchor)
                .allowsHitTesting(true)
        }
    }

    private func isPlacing(_ team: CourtTeam) -> Bool {
        if case .player(let t, _, _)? = placementKind { return t == team }
        return false
    }

    private var isPlacingBall: Bool {
        if case .ball? = placementKind { return true }
        return false
    }

    // The column tool strip is gone: the palette floats on the canvas now.

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // BREADCRUMB: the editor takes the window, so the way back has to
            // be visible rather than a shortcut you remember.
            Button {
                NotificationCenter.default.post(name: .macExpandSidebar, object: nil)
            } label: {
                Label("Library", systemImage: "sidebar.leading")
            }
            .help("Show the app sidebar")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.togglePlayback() } label: {
                Label(model.isRunning ? "Pause" : "Play",
                      systemImage: model.isRunning ? "pause.fill" : "play.fill")
            }
            .disabled(model.playbackDuration <= 0)
            .help(model.isRunning ? "Pause (Space)" : "Play the whole read (Space)")

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

            // THE FRAME STEPPER IS AUTHORING CHROME. During playback it would
            // count frames of the read being edited while the canvas shows a
            // RUN — a different, spliced list — so it is not merely useless
            // there, it is wrong. The scrub bar owns navigation instead.
            if !model.isPlayingBack {
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
