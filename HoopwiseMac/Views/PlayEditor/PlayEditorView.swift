import SwiftUI

/// The court editor: canvas above, timeline below, inspector to the side.
///
/// Opens on an empty diagram so there is always something authorable. Wiring to
/// the playbook arrives with the read-tree navigator.
struct PlayEditorView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.undoManager) private var systemUndoManager
    @StateObject private var model: PlayEditorModel
    /// Sticky: stays active until deselected or Escape.
    @State private var placementKind: DiagramEntityKind?
    @State private var showingLookPanel = false
    /// True while a text field owns focus, so single-letter shortcuts stand down.
    @FocusState private var isTextFieldFocused: Bool

    init(diagram: PlayDiagram? = nil) {
        _model = StateObject(wrappedValue:
            PlayEditorModel(diagram: diagram ?? PlayEditorModel.newDiagram()))
    }

    var body: some View {
        VSplitView {
            HStack(spacing: 0) {
                PlayLibraryView(model: model)
                    .frame(width: 210)
                Divider()
                // Sticky tool: placing does NOT clear the selection, so a
                // whole lineup goes down without re-picking each time.
                DiagramCanvasView(model: model, placementKind: placementKind) { }
                .frame(minWidth: 420, minHeight: 320)

                Divider()
                VStack(spacing: 0) {
                    inspector
                    if model.showDebugPanel {
                        Divider()
                        debugPanel
                    }
                }
                .frame(width: 260)
                // Constrain the panel to its frame. Long unbroken values —
                // a UUID prefix, a play name — were painting past the right
                // edge because nothing clipped the column.
                .clipped()
            }
            .frame(minHeight: 340)

            TimelineView(model: model)
                .frame(minHeight: 150, idealHeight: 190)
        }
        .toolbar { toolbarContent }
        .navigationTitle(model.diagramName)
        .onAppear {
            model.dataManager = dataManager
            model.undoManager = systemUndoManager
            // Reopen the most recent diagram so quitting does not lose work.
            if let stored = dataManager.allPlayDiagrams().first {
                model.load(stored.diagram, name: stored.name)
            }
            model.startAutosave()
        }
        .onChange(of: systemUndoManager) { _, manager in model.undoManager = manager }
        .onDisappear { model.save() }
        .onReceive(NotificationCenter.default.publisher(for: .macEditorTogglePlay)) { _ in
            model.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macEditorMirror)) { _ in
            model.mirror()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macEditorTogglePaths)) { _ in
            model.showMovementPaths.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macEditorToggleSticky)) { _ in
            model.possessionEnabled.toggle()
        }
        .focusable()
        .onKeyPress(.escape) {
            placementKind = nil
            model.activeToolName = "Select"
            return .handled
        }
        .onKeyPress(.delete) {
            model.deleteSelectedKeyframes()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            model.nudgeSelectedKeyframes(by: -(model.snapEnabled ? model.snapInterval : 0.05))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.nudgeSelectedKeyframes(by: model.snapEnabled ? model.snapInterval : 0.05)
            return .handled
        }
        // Single-letter tool keys, GATED on no text field having focus —
        // naming a play must not place players.
        .onKeyPress(phases: .down) { press in
            guard !isTextFieldFocused else { return .ignored }
            switch press.characters.lowercased() {
            case "a": placementKind = nil; model.activeToolName = "Select"
            case "o": placementKind = .player(team: .offense, number: nil, role: nil)
                      model.activeToolName = "Offense"
            case "d": placementKind = .player(team: .defense, number: nil, role: nil)
                      model.activeToolName = "Defense"
            case "b": guard model.canPlace(.ball) else { return .ignored }
                      placementKind = .ball; model.activeToolName = "Ball"
            case "c": placementKind = .cone; model.activeToolName = "Cone"
            case "s": model.possessionEnabled.toggle()
            case "p": model.showMovementPaths.toggle()
            default:  return .ignored
            }
            return .handled
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            groupLabel("Tools")
            toolButton("Select", "cursorarrow", "A", nil)
            toolButton("Offense", "person.fill", "O",
                       .player(team: .offense, number: nil, role: nil))
            toolButton("Defense", "person.fill.badge.minus", "D",
                       .player(team: .defense, number: nil, role: nil))
            toolButton("Ball", "basketball.fill", "B", .ball)
            toolButton("Screen", "rectangle.fill", "S", .screen)
            toolButton("Cone", "triangle.fill", "C", .cone)
        }

        ToolbarItemGroup(placement: .principal) {
            Divider()
            groupLabel("Playback")
            Button { model.togglePlayback() } label: {
                Label(model.isPlaying ? "Pause" : "Play",
                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

            Button { model.stop(); model.playhead = 0 } label: {
                Label("Rewind", systemImage: "backward.end.fill")
            }
            .help("Rewind to start")

            scrubber
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Divider()
            groupLabel("View")
            Picker("Theme", selection: Binding(
                get: { model.theme }, set: { model.setTheme($0) })) {
                ForEach(CourtTheme.all) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu).fixedSize()
            .help("Colour theme — Print for paper, Video for film")

            Toggle(isOn: $model.showMovementPaths) {
                Label("Paths", systemImage: "scribble")
            }
            .toggleStyle(.button)
            .help("Show movement paths (P)")

            Toggle(isOn: $model.possessionEnabled) {
                Label("Sticky Ball", systemImage: "hand.raised.fill")
            }
            .toggleStyle(.button)
            .help("Ball follows possession (S). Off lets you keyframe it freehand.")

            Button { model.mirror() } label: {
                Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .help("Mirror the play, swapping left/right in teaching points (⌘M)")

            Divider()

            Button { showingLookPanel.toggle() } label: {
                Label("Look", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showingLookPanel) { lookPanel }
            .help("Look parameters — tilt, ball speed, colours")

            Toggle(isOn: $model.showDebugPanel) {
                Label("Debug", systemImage: "ladybug")
            }
            .toggleStyle(.button)
            .help("Show what the editor resolves at the playhead")
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .fixedSize()
    }

    private var scrubber: some View {
        HStack(spacing: 5) {
            Slider(value: Binding(
                get: { model.playhead },
                set: { model.stop(); model.playhead = $0 }),
                   in: 0...model.timelineDuration)
            .frame(width: 130)
            Text(String(format: "%.2fs", model.playhead))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
        .help("Scrub the playhead")
    }

    /// Tool button with a visible armed state.
    ///
    /// `kind == nil` is Select — arming nothing. There was previously no Select
    /// tool at all and no way to tell which tool was live.
    private func toolButton(_ title: String, _ icon: String,
                            _ key: String, _ kind: DiagramEntityKind?) -> some View {
        let isActive = placementKind == kind
        let available = kind.map { model.canPlace($0) } ?? true
        return Button {
            placementKind = kind
            model.activeToolName = title
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 20)
                .foregroundStyle(isActive ? Color.white : (available ? .primary : Color.secondary))
                .background(isActive ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .disabled(!available)
        .help(available ? "\(title) (\(key))" : "Only one ball per diagram")
    }

    // MARK: - Inspector

    private var inspector: some View {
        Form {
            Section("Court") {
                Picker("Standard", selection: Binding(
                    get: { model.diagram.space.standard },
                    set: { model.setCourt(standard: $0) })) {
                    ForEach(CourtStandard.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Extent", selection: Binding(
                    get: { model.diagram.space.mode },
                    set: { model.setCourt(mode: $0) })) {
                    ForEach(CourtMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("Camera") {
                HStack {
                    Text("Elevation")
                    Spacer()
                    Text("\(Int(model.renderElevation))°").monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.cameraElevation,
                       in: model.look.minElevationDegrees...90)
                Picker("Ease", selection: $model.cameraEasing) {
                    ForEach(Easing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("Set Camera Keyframe") { model.setCameraKeyframe() }
                    .controlSize(.small)
                if !model.diagram.camera.isStatic {
                    Button("Clear Camera Track", role: .destructive) { model.clearCameraTrack() }
                        .controlSize(.small)
                }
                Text("90° is plan view. Keyframe two values to author the oblique-to-top-down move — the ease is what stops it reading as mechanical.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            keyframeSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var keyframeSection: some View {
        if let entityId = model.selectedEntityId, let keyframe = model.selectedKeyframe {
            Section("Keyframe at \(String(format: "%.2f", keyframe.t))s") {
                Picker("Easing", selection: Binding(
                    get: { keyframe.easing },
                    set: { model.updateKeyframe(entityId: entityId,
                                                keyframeId: keyframe.id, easing: $0) })) {
                    ForEach(Easing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }

                let isFinal = model.isFinalKeyframe(keyframe, entityId: entityId)
                Picker("Path", selection: Binding(
                    get: { keyframe.pathKind },
                    set: { model.updateKeyframe(entityId: entityId,
                                                keyframeId: keyframe.id, pathKind: $0) })) {
                    ForEach(PathKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(isFinal)

                Picker("Shape", selection: Binding(
                    get: { keyframe.pathStyle },
                    set: { model.updateKeyframe(entityId: entityId,
                                                keyframeId: keyframe.id, pathStyle: $0) })) {
                    ForEach(PathStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(isFinal)
                .help("Sharp runs straight to the next keyframe; curved arcs through its neighbours")

                if isFinal {
                    // Segment convention: pathKind governs the segment LEAVING a
                    // keyframe, so the last one governs nothing.
                    Text("Last keyframe — path kind governs the segment that follows, so it has no effect here.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Button("Delete Keyframe", role: .destructive) {
                    model.deleteKeyframe(entityId: entityId, keyframeId: keyframe.id)
                }
                .controlSize(.small)
            }
        } else if model.selectedEntityId != nil {
            Section("Keyframe") {
                Text("No keyframe at the playhead. Drag the entity on the court to create one.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete Entity", role: .destructive) { model.deleteSelectedEntity() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Debug Panel

    /// Runtime state readout. Exists so a misbehaving editor can be diagnosed
    /// from resolved state rather than from a description of the symptom.
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STATE").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.debugReadout, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy readout")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView {
                Text(model.debugReadout)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(height: 300)
        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
    }

    // MARK: - Look Panel

    /// Tunable look parameters, exposed rather than baked so the numbers can be
    /// iterated against real output instead of a rebuild each time.
    private var lookPanel: some View {
        Form {
            Section("Perspective") {
                labelled("Convergence", model.look.maxConvergence, "%.2f")
                Slider(value: $model.look.maxConvergence, in: 0...0.9)

                labelled("Far depth scale", model.look.minDepthScale, "%.2f")
                Slider(value: $model.look.minDepthScale, in: 0.2...1.0)

                labelled("Min elevation", CGFloat(model.look.minElevationDegrees), "%.0f°")
                Slider(value: $model.look.minElevationDegrees, in: 10...60, step: 1)
            }
            Section("Ball") {
                labelled("Pass speed", CGFloat(model.look.passSpeedFeetPerSecond), "%.0f ft/s")
                Slider(value: $model.look.passSpeedFeetPerSecond, in: 12...60, step: 1)
                labelled("Shot speed", CGFloat(model.look.shotSpeedFeetPerSecond), "%.0f ft/s")
                Slider(value: $model.look.shotSpeedFeetPerSecond, in: 10...50, step: 1)
                labelled("Held offset", model.look.ballHeldOffsetFeet, "%.1f ft")
                Slider(value: $model.look.ballHeldOffsetFeet, in: 0...4, step: 0.1)
                Text("Flight duration is derived from distance / speed, so these set how snappy passes and shots feel.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Legibility") {
                labelled("Min label size", model.look.minLabelPointSize, "%.0f pt")
                Slider(value: $model.look.minLabelPointSize, in: 5...16, step: 0.5)
                Text("Labels stop shrinking here. Billboarding fixes orientation, not size — far-side numbers go unreadable in a 1080p export without a floor.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Timeline") {
                Toggle("Snap to grid", isOn: $model.snapEnabled)
                Picker("Grid", selection: $model.snapInterval) {
                    Text("1/20s").tag(0.05)
                    Text("1/10s").tag(0.1)
                    Text("1/4s").tag(0.25)
                    Text("1/2s").tag(0.5)
                    Text("1s").tag(1.0)
                }
                .disabled(!model.snapEnabled)
            }
            Section {
                Button("Reset to Defaults") { model.look = .default }
                    .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 380)
    }

    private func labelled(_ title: String, _ value: CGFloat, _ format: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
