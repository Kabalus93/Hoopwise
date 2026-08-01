import SwiftUI
import AppKit

/// Context-sensitive inspector: the panel is about whatever is selected —
/// the Resolve pattern in Apple dress. Collapsible titled sections, one
/// parameter per row, native controls throughout.
struct EditorInspector: View {
    @ObservedObject var model: PlayEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .padding(.vertical, 6)
        }
    }

    /// Selection priority: possession event, keyframes, camera keyframe,
    /// entity, then the court/camera defaults.
    @ViewBuilder
    private var content: some View {
        let events = model.selectedPossessionEvents
        let keyframes = model.selectedKeyframeInfos
        if events.count == 1, keyframes.isEmpty {
            possessionSection(events[0])
        } else if let span = model.selectedBallSpan, events.isEmpty, keyframes.isEmpty {
            ballSpanSection(span)
        } else if !keyframes.isEmpty {
            keyframeSection(keyframes)
        } else if let cameraId = model.selectedCameraKeyframeId,
                  let frame = model.diagram.camera.keyframes.first(where: { $0.id == cameraId }) {
            cameraKeyframeSection(frame)
        } else if let entityId = model.selectedEntityId,
                  let entity = model.entity(entityId) {
            entitySections(entity)
        } else {
            courtSection
            cameraSection
        }
    }

    // MARK: - Possession event

    private func possessionSection(_ event: PlayEditorModel.PossessionEvent) -> some View {
        InspectorSection("Possession Event", key: "possession") {
            row("Type") {
                Label(event.label, systemImage: event.glyph)
                    .font(.callout)
                    .foregroundStyle(event.color)
                    .lineLimit(2)
            }
            NumericRow(title: "Time", model: model,
                       value: event.time, step: 0.05, format: "%.2f s",
                       defaultValue: nil) { newValue in
                model.setPossessionEventTime(event, absolute: newValue)
            }
            row("Holder") { Text(model.holderLabel(of: event)).foregroundStyle(.secondary) }
            if let flight = model.flightDuration(of: event) {
                row("Flight") {
                    Text(String(format: "%.2f s (derived from distance ÷ speed)", flight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Misdrop escape hatch: a shot near a receiver, or a pass meant
            // for the rim, converts in place — no redoing the gesture.
            if event.kind == .releaseShot {
                row("Convert") {
                    Menu("To Pass…") {
                        ForEach(model.diagram.entities.filter(\.isPlayer)) { player in
                            Button(player.label ?? "Player") {
                                model.convertShotToPass(event: event, receiverId: player.id)
                            }
                        }
                    }
                    .fixedSize()
                }
            } else if event.kind == .releasePass {
                row("Convert") {
                    Button("To Shot") { model.convertPassToShot(event: event) }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Ball state span

    /// A bar-segment selection: display-only facts about the span. The
    /// editable handles remain the event glyphs.
    private func ballSpanSection(_ span: PlayEditorModel.BallBarSpan) -> some View {
        InspectorSection("Ball State", key: "ballspan") {
            row("State") {
                Text(spanName(span.kind))
                    .foregroundStyle(.secondary)
            }
            if let holderId = span.holderId, let holder = model.entity(holderId) {
                row(span.kind == .flightPass || span.kind == .flightShot
                    ? "Released by" : "Holder") {
                    Text(holder.label ?? "—").foregroundStyle(.secondary)
                }
            }
            row("From") { Text(String(format: "%.2f s", span.start)).foregroundStyle(.secondary) }
            row("To") { Text(String(format: "%.2f s", span.end)).foregroundStyle(.secondary) }
            row("Duration") {
                Text(String(format: "%.2f s", span.duration)).foregroundStyle(.secondary)
            }
        }
    }

    private func spanName(_ kind: ReadNode.BallSpan.Kind) -> String {
        switch kind {
        case .rest:       return "Held, stationary"
        case .dribble:    return "Moving with player"
        case .flightPass: return "Pass in flight"
        case .flightShot: return "Shot in flight"
        case .loose:      return "At rest"
        }
    }

    // MARK: - Keyframes

    private func keyframeSection(_ infos: [PlayEditorModel.KeyframeInfo]) -> some View {
        InspectorSection(infos.count == 1
                         ? "Keyframe at \(String(format: "%.2f", infos[0].absoluteTime))s"
                         : "Keyframes (\(infos.count))",
                         key: "keyframe") {
            if infos.count == 1 {
                let info = infos[0]
                NumericRow(title: "Time", model: model,
                           value: info.absoluteTime, step: 0.05, format: "%.2f s",
                           defaultValue: nil) { newValue in
                    model.setKeyframeAbsoluteTime(info.keyframe.id, to: newValue)
                }
                NumericRow(title: "X", model: model,
                           value: Double(info.keyframe.position.x), step: 0.25, format: "%.1f ft",
                           defaultValue: nil) { newValue in
                    model.setKeyframePosition(info.keyframe.id,
                                              to: CGPoint(x: newValue,
                                                          y: info.keyframe.position.y))
                }
                NumericRow(title: "Y", model: model,
                           value: Double(info.keyframe.position.y), step: 0.25, format: "%.1f ft",
                           defaultValue: nil) { newValue in
                    model.setKeyframePosition(info.keyframe.id,
                                              to: CGPoint(x: info.keyframe.position.x,
                                                          y: newValue))
                }
            }
            // Shared properties; mixed values show an em dash and editing
            // applies to the whole selection in one undoable action.
            mixedPicker("Easing", current: model.sharedEasing()?.rawValue,
                        options: Easing.allCases.map(\.rawValue)) { raw in
                if let easing = Easing(rawValue: raw) { model.applyEasingToSelection(easing) }
            }
            mixedPicker("Path", current: model.sharedPathKind()?.displayName,
                        options: PathKind.allCases.map(\.displayName)) { name in
                if let kind = PathKind.allCases.first(where: { $0.displayName == name }) {
                    model.applyPathKindToSelection(kind)
                }
            }
            mixedPicker("Shape", current: model.sharedPathStyle()?.displayName,
                        options: PathStyle.allCases.map(\.displayName)) { name in
                if let style = PathStyle.allCases.first(where: { $0.displayName == name }) {
                    model.applyPathStyleToSelection(style)
                }
            }
        }
    }

    // MARK: - Camera keyframe

    private func cameraKeyframeSection(_ frame: ScalarKeyframe) -> some View {
        InspectorSection("Camera Keyframe", key: "cameraKF") {
            NumericRow(title: "Time", model: model,
                       value: frame.t, step: 0.05, format: "%.2f s",
                       defaultValue: nil) { newValue in
                model.updateCameraKeyframe(id: frame.id, t: newValue)
            }
            NumericRow(title: "Elevation", model: model,
                       value: frame.value, step: 1, format: "%.0f°",
                       defaultValue: 90) { newValue in
                model.updateCameraKeyframe(id: frame.id, value: newValue)
            }
            mixedPicker("Ease", current: frame.easing.rawValue,
                        options: Easing.allCases.map(\.rawValue)) { raw in
                if let easing = Easing(rawValue: raw) {
                    model.updateCameraKeyframe(id: frame.id, easing: easing)
                }
            }
        }
    }

    // MARK: - Entity

    @ViewBuilder
    private func entitySections(_ entity: DiagramEntity) -> some View {
        InspectorSection("Identity", key: "identity") {
            row("Label") {
                TextField("Label", text: Binding(
                    get: { entity.label ?? "" },
                    set: { model.renameEntity(entity.id, to: $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
            }
            row("Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: entity.colorHex ?? "#34A0F7") },
                    set: { model.setEntityColor(entity.id, hex: $0.hexString) }))
                .labelsHidden()
            }
        }
        InspectorSection("Transform", key: "transform") {
            let position = model.resolvedPosition(of: entity.id, at: model.playhead)
            NumericRow(title: "X", model: model,
                       value: Double(position.x), step: 0.25, format: "%.1f ft",
                       defaultValue: nil) { newValue in
                movePlayhead(entity, to: CGPoint(x: newValue, y: position.y))
            }
            NumericRow(title: "Y", model: model,
                       value: Double(position.y), step: 0.25, format: "%.1f ft",
                       defaultValue: nil) { newValue in
                movePlayhead(entity, to: CGPoint(x: position.x, y: newValue))
            }
        }
        InspectorSection("Appearance", key: "appearance") {
            NumericRow(title: "Size", model: model,
                       value: Double(entity.effectiveSize), step: 0.05, format: "%.2f×",
                       defaultValue: 1.0) { newValue in
                model.setEntitySize(entity.id, scale: min(2, max(0.4, newValue)))
            }
        }
        // The former "Keyframe at X.XXs" block folds in here.
        if let keyframe = model.selectedKeyframe {
            keyframeSection([PlayEditorModel.KeyframeInfo(
                nodeId: model.activeNodeId, entityId: entity.id,
                keyframe: keyframe,
                absoluteTime: model.playhead)])
        } else {
            InspectorSection("Path", key: "path") {
                Text("No keyframe at the playhead. Drag on the court or press K to add one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func movePlayhead(_ entity: DiagramEntity, to point: CGPoint) {
        // Edits the keyframe at the playhead when there is one; otherwise the
        // home position — matching what the canvas drag would author.
        if let keyframe = model.selectedKeyframeAt(entityId: entity.id) {
            model.setKeyframePosition(keyframe.id, to: point)
        } else {
            model.setHomePosition(entity.id, to: point)
        }
    }

    // MARK: - Court + Camera (nothing selected)

    private var courtSection: some View {
        InspectorSection("Court", key: "court") {
            row("Standard") {
                Picker("", selection: Binding(
                    get: { model.diagram.space.standard },
                    set: { model.setCourt(standard: $0) })) {
                    ForEach(CourtStandard.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            row("Extent") {
                Picker("", selection: Binding(
                    get: { model.diagram.space.mode },
                    set: { model.setCourt(mode: $0) })) {
                    ForEach(CourtMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var cameraSection: some View {
        InspectorSection("Camera", key: "camera") {
            NumericRow(title: "Elevation", model: model,
                       value: model.cameraElevation, step: 1, format: "%.0f°",
                       defaultValue: 90) { model.cameraElevation = $0 }
            row("Ease") {
                Picker("", selection: $model.cameraEasing) {
                    ForEach(Easing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Button("Set Camera Keyframe") { model.setCameraKeyframe() }
                .controlSize(.small)
            if !model.diagram.camera.isStatic {
                Button("Clear Camera Track", role: .destructive) { model.clearCameraTrack() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Row helpers

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    /// Shared-or-mixed picker: mixed selections show an em dash; choosing a
    /// value applies to the whole selection.
    private func mixedPicker(_ title: String, current: String?,
                             options: [String],
                             apply: @escaping (String) -> Void) -> some View {
        row(title) {
            Menu(current ?? "—") {
                ForEach(options, id: \.self) { option in
                    Button(option) { apply(option) }
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - Section

/// Collapsible titled section; expansion is remembered per section key.
private struct InspectorSection<Content: View>: View {
    let title: String
    @AppStorage private var expanded: Bool
    private let content: Content

    init(_ title: String, key: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self._expanded = AppStorage(wrappedValue: true, "inspector.\(key).expanded")
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 2) { content }
                .padding(.top, 2)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

// MARK: - Numeric row with scrubbing

/// Label left, numeric field right. Click-drag the LABEL to scrub — the
/// Resolve/pro-app idiom — with one undo per scrub gesture; typing commits a
/// discrete undoable edit. A per-row reset appears on hover when the row has
/// a default.
private struct NumericRow: View {
    let title: String
    @ObservedObject var model: PlayEditorModel
    let value: Double
    let step: Double
    let format: String
    let defaultValue: Double?
    let apply: (Double) -> Void

    @State private var draft: String = ""
    @State private var editing = false
    @State private var hovering = false
    @State private var scrubBase: Double?

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
                .gesture(scrubGesture)
                .help("Drag to scrub")
            if hovering, let defaultValue, abs(value - defaultValue) > 0.001 {
                Button {
                    apply(defaultValue)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
            Spacer()
            TextField("", text: $draft, onEditingChanged: { began in
                editing = began
                if !began, let typed = Double(draft.filter { "0123456789.-".contains($0) }) {
                    apply(typed)
                }
            })
            .onSubmit {
                if let typed = Double(draft.filter { "0123456789.-".contains($0) }) { apply(typed) }
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 84)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
        .onAppear { draft = String(format: format, value) }
        .onChange(of: value) { _, newValue in
            if !editing { draft = String(format: format, newValue) }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                if scrubBase == nil {
                    model.registerUndo("Scrub \(title)")
                    scrubBase = value
                }
                guard let base = scrubBase else { return }
                apply(base + Double(drag.translation.width) * step)
            }
            .onEnded { _ in scrubBase = nil }
    }
}

// MARK: - Color helpers

extension Color {
    /// sRGB hex for storage; the inverse of `Color(hex:)`.
    var hexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#808080" }
        return String(format: "#%02X%02X%02X",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255))
    }
}
