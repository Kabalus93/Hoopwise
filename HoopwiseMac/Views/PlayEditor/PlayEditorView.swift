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

    init(diagram: PlayDiagram? = nil) {
        _model = StateObject(wrappedValue:
            PlayEditorModel(diagram: diagram ?? PlayEditorModel.newDiagram()))
    }

    var body: some View {
        VSplitView {
            HStack(spacing: 0) {
                // Sticky tool: placing does NOT clear the selection, so a
                // whole lineup goes down without re-picking each time.
                DiagramCanvasView(model: model, placementKind: placementKind) { }
                .frame(minWidth: 420, minHeight: 320)

                Divider()
                inspector.frame(width: 240)
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
            if let stored = dataManager.mostRecentPlayDiagram() {
                model.load(stored)
            }
            model.startAutosave()
        }
        .onChange(of: systemUndoManager) { _, manager in model.undoManager = manager }
        .onDisappear { model.save() }
        .focusable()
        .onKeyPress(.escape) {
            placementKind = nil
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
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            palette
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.togglePlayback()
            } label: {
                Label(model.isPlaying ? "Pause" : "Play",
                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])

            Button {
                model.stop()
                model.playhead = 0
            } label: {
                Label("Rewind", systemImage: "backward.end.fill")
            }

            Divider()

            Button { model.mirror() } label: {
                Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .help("Flip the play across the court, swapping left/right in teaching points")

            Toggle(isOn: $model.showMovementPaths) {
                Label("Paths", systemImage: "scribble")
            }
            .toggleStyle(.button)
            .help("Show or hide movement paths — off gives a clean court for stills")

            Toggle(isOn: $model.possessionEnabled) {
                Label("Possession", systemImage: "hand.raised.fill")
            }
            .toggleStyle(.button)
            .help("Ball follows possession. Off lets you keyframe it freehand.")

            Picker("Theme", selection: Binding(
                get: { model.theme },
                set: { model.setTheme($0) })) {
                ForEach(CourtTheme.all) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button { showingLookPanel.toggle() } label: {
                Label("Look", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showingLookPanel) { lookPanel }
        }
    }

    private var palette: some View {
        HStack(spacing: 6) {
            paletteButton("Offense", "person.fill", .blue,
                          .player(team: .offense, number: nil, role: nil))
            paletteButton("Defense", "person.fill.badge.minus", .red,
                          .player(team: .defense, number: nil, role: nil))
            paletteButton("Ball", "basketball.fill", .orange, .ball)
            paletteButton("Screen", "rectangle.fill", .white, .screen)
            paletteButton("Cone", "triangle.fill", .yellow, .cone)
        }
    }

    private func paletteButton(_ title: String, _ icon: String,
                               _ tint: Color, _ kind: DiagramEntityKind) -> some View {
        let isActive = placementKind == kind
        let available = model.canPlace(kind)
        return Button {
            placementKind = isActive ? nil : kind
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .foregroundStyle(isActive ? Color.white : (available ? tint : Color.secondary))
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(isActive ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .disabled(!available)
        .help(available
              ? (isActive ? "\(title) tool active — keeps placing until Escape" : "Place \(title)")
              : "Only one ball per diagram")
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
