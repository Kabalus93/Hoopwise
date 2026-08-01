import SwiftUI

/// Keyframe timeline: one lane per entity, plus a camera lane.
///
/// Scrub by dragging the ruler; drag a keyframe to retime it; click to select.
struct TimelineView: View {
    @ObservedObject var model: PlayEditorModel

    private let laneHeight: CGFloat = 30
    private let labelWidth: CGFloat = 214
    private let rulerHeight: CGFloat = 22

    // Multi-drag: initial local times captured on gesture start so relative
    // spacing is preserved (and option-scale has a fixed reference).
    @State private var dragInitial: [UUID: (nodeId: UUID, entityId: UUID, local: Double, absolute: Double)]?
    @State private var dragAnchorId: UUID?
    // Box selection rubber band, in lanes coordinate space.
    @State private var boxStart: CGPoint?
    @State private var boxCurrent: CGPoint?
    @State private var renamingEntity: DiagramEntity?
    @State private var renameDraft = ""
    /// Inline rename on double-click.
    @State private var inlineRenameId: UUID?
    @State private var inlineRenameDraft = ""

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(80, geo.size.width - labelWidth)
            let duration = model.timelineDuration

            VStack(alignment: .leading, spacing: 0) {
                ruler(width: trackWidth, duration: duration)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        cameraLane(width: trackWidth, duration: duration)
                        ForEach(model.diagram.entities) { entity in
                            entityLane(entity, width: trackWidth, duration: duration)
                        }
                    }
                    .coordinateSpace(name: "lanes")
                    // Box-select in empty timeline area. Keyframe markers carry
                    // their own drag gesture, which wins where they are; empty
                    // track falls through to this.
                    .gesture(boxSelectGesture(width: trackWidth, duration: duration))
                    .overlay {
                        if let start = boxStart, let current = boxCurrent {
                            let rect = CGRect(x: min(start.x, current.x),
                                              y: min(start.y, current.y),
                                              width: abs(current.x - start.x),
                                              height: abs(current.y - start.y))
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.12))
                                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.7), lineWidth: 1))
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .alert("Rename Layer", isPresented: Binding(
                    get: { renamingEntity != nil },
                    set: { if !$0 { renamingEntity = nil } })) {
                    TextField("Label", text: $renameDraft)
                    Button("Cancel", role: .cancel) { renamingEntity = nil }
                    Button("Rename") {
                        if let entity = renamingEntity {
                            model.renameEntity(entity.id, to: renameDraft)
                        }
                        renamingEntity = nil
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                playhead(width: trackWidth, duration: duration, height: geo.size.height)
            }
        }
    }

    // MARK: - Ruler

    private func ruler(width: CGFloat, duration: Double) -> some View {
        HStack(spacing: 0) {
            Text("Time")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)

            Canvas { context, size in
                for second in 0...Int(duration.rounded(.up)) {
                    let x = CGFloat(Double(second) / duration) * size.width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 7))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    context.draw(context.resolve(
                        Text("\(second)s").font(.system(size: 9)).foregroundStyle(.secondary)),
                        at: CGPoint(x: x + 11, y: size.height - 13))
                }
                // Segment boundaries: where each read begins on the
                // concatenated timeline.
                for boundary in model.segmentBoundaries {
                    let x = CGFloat(boundary.time / duration) * size.width
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.accentColor.opacity(0.7)), lineWidth: 1)
                    context.draw(context.resolve(
                        Text(boundary.title).font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.accentColor)),
                        at: CGPoint(x: x + 4, y: 6), anchor: .leading)
                }
            }
            .frame(width: width, height: rulerHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                // Work-area band.
                if let area = model.workArea {
                    let x0 = CGFloat(area.lowerBound / duration) * width
                    let x1 = CGFloat(area.upperBound / duration) * width
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                        .frame(width: max(1, x1 - x0), height: rulerHeight)
                        .offset(x: x0)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let t = min(max(0, Double(value.location.x / width) * duration), duration)
                    // Shift-drag sets the work area; a plain drag scrubs.
                    if NSEvent.modifierFlags.contains(.shift) {
                        let start = min(max(0, Double(value.startLocation.x / width) * duration), duration)
                        model.setWorkArea(from: start, to: t)
                    } else {
                        model.stop()
                        model.playhead = t
                    }
                }
            )
            .onTapGesture(count: 2) { model.workArea = nil }
        }
        .frame(height: rulerHeight)
    }

    // MARK: - Lanes

    private func cameraLane(width: CGFloat, duration: Double) -> some View {
        HStack(spacing: 0) {
            Label("Camera", systemImage: "video")
                .font(.caption.weight(.medium))
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)

            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.06))
                ForEach(model.diagram.camera.keyframes) { frame in
                    marker(color: .purple,
                           selected: model.selectedCameraKeyframeId == frame.id)
                        .position(x: CGFloat(frame.t / duration) * width, y: laneHeight / 2)
                        .help("\(Int(frame.value))° at \(String(format: "%.2f", frame.t))s")
                        .onTapGesture {
                            model.selectedCameraKeyframeId = frame.id
                            model.selectedKeyframeIds.removeAll()
                        }
                }
            }
            .frame(width: width, height: laneHeight)
        }
        .frame(height: laneHeight)
    }

    /// Possession events on the Ball row.
    ///
    /// Zero position keyframes there is CORRECT — the ball has no position
    /// track. These are EVENTS, drawn as circles rather than diamonds so an
    /// event is never mistaken for a keyframe. Read-only for now: retiming and
    /// deleting them is a larger job than it looks, because a pass's arrival is
    /// derived from distance and speed rather than stored independently.
    @ViewBuilder
    private func possessionMarkers(width: CGFloat, duration: Double) -> some View {
        let events = model.possessionEvents
        ForEach(events, id: \.id) { event in
            let selected = model.selectedKeyframeIds.contains(event.id)
            Image(systemName: event.glyph)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(selected ? Color.white : event.color)
                .padding(2)
                .background(selected ? event.color : Color.clear, in: Circle())
                .scaleEffect(selected ? 1.35 : 1)
                .shadow(color: selected ? event.color.opacity(0.6) : .clear, radius: selected ? 3 : 0)
                .position(x: CGFloat(min(event.time, duration) / duration) * width,
                          y: laneHeight / 2)
                .help(event.label)
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        if selected { model.selectedKeyframeIds.remove(event.id) }
                        else { model.selectedKeyframeIds.insert(event.id) }
                    } else {
                        model.selectedKeyframeIds = [event.id]
                    }
                }
                .gesture(possessionDrag(event: event, width: width, duration: duration))
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        model.selectedKeyframeIds = [event.id]
                        model.deleteSelectedKeyframesEverywhere()
                    }
                }
        }
    }

    /// Retimes possession events with the same gesture grammar as keyframes:
    /// one undo per drag, selection moves together preserving spacing.
    private func possessionDrag(event: PlayEditorModel.PossessionEvent,
                                width: CGFloat, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragInitial == nil {
                    model.registerUndo("Retime Possession")
                    if !model.selectedKeyframeIds.contains(event.id) {
                        model.selectedKeyframeIds = [event.id]
                    }
                    var initial: [UUID: (UUID, UUID, Double, Double)] = [:]
                    for member in model.possessionEvents
                    where model.selectedKeyframeIds.contains(member.id) {
                        let step = model.activeSteps.first { $0.node.id == member.nodeId }
                        let local = member.time - (step?.startsAt ?? 0)
                        initial[member.id] = (member.nodeId, member.possessionId, local, member.time)
                    }
                    dragInitial = initial
                }
                guard let initial = dragInitial, let dragged = initial[event.id] else { return }
                let absoluteNow = Double(value.location.x / width) * duration
                let delta = absoluteNow - dragged.3
                for member in model.possessionEvents
                where model.selectedKeyframeIds.contains(member.id) {
                    guard let info = initial[member.id] else { continue }
                    model.retimePossessionEvent(member,
                                                toLocal: model.snapped(info.2 + delta))
                }
            }
            .onEnded { _ in dragInitial = nil }
    }

    private func entityLane(_ entity: DiagramEntity, width: CGFloat, duration: Double) -> some View {
        let isSelected = model.selectedEntityId == entity.id

        return HStack(spacing: 0) {
            // ALL controls, always visible, laid out once. The hover reveal
            // did not work in practice — no half-dead states left behind.
            HStack(spacing: 2) {
                Button {
                    model.selectedEntityId = entity.id
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(laneColor(entity)).frame(width: 8, height: 8)
                        if inlineRenameId == entity.id {
                            TextField("", text: $inlineRenameDraft, onCommit: {
                                model.renameEntity(entity.id, to: inlineRenameDraft)
                                inlineRenameId = nil
                            })
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 46)
                        } else {
                            Text(laneTitle(entity))
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(width: 54, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    guard entity.isPlayer else { return }
                    inlineRenameDraft = entity.label ?? ""
                    inlineRenameId = entity.id
                })
                .contextMenu {
                    if entity.isPlayer {
                        Button("Rename…") {
                            renameDraft = entity.label ?? ""
                            renamingEntity = entity
                        }
                    }
                    Button("Clear All Keyframes", role: .destructive) {
                        model.clearTrack(entity.id)
                    }
                    Menu("Duplicate Track To") {
                        ForEach(model.diagram.nodes.filter { $0.id != model.activeNodeId },
                                id: \.id) { node in
                            Button(node.title) { model.duplicateTrack(entity.id, to: node.id) }
                        }
                    }
                }

                layerToggle(model.isHidden(entity.id) ? "eye.slash" : "eye",
                            active: model.isHidden(entity.id),
                            help: "Show / hide on the court") {
                    if model.isHidden(entity.id) { model.hiddenEntityIds.remove(entity.id) }
                    else { model.hiddenEntityIds.insert(entity.id) }
                }
                layerToggle(model.isLocked(entity.id) ? "lock.fill" : "lock.open",
                            active: model.isLocked(entity.id),
                            help: "Lock — canvas clicks pass through") {
                    if model.isLocked(entity.id) { model.lockedEntityIds.remove(entity.id) }
                    else { model.lockedEntityIds.insert(entity.id) }
                }
                layerToggle("scope", active: model.soloEntityId == entity.id,
                            help: "Solo — dim everything else to 25%") {
                    model.soloEntityId = model.soloEntityId == entity.id ? nil : entity.id
                }

                Spacer(minLength: 2)

                // Keyframe cluster: grouped tight at the trailing edge,
                // reading as one control.
                HStack(spacing: 0) {
                    clusterButton("arrowtriangle.left.fill", help: "Previous keyframe (J)") {
                        model.jumpToKeyframe(entity.id, direction: -1)
                    }
                    clusterButton(model.hasKeyframeAtPlayhead(entity.id)
                                  ? "diamond.fill" : "diamond",
                                  tint: model.hasKeyframeAtPlayhead(entity.id)
                                  ? laneColor(entity) : nil,
                                  help: "Keyframe in place (K)") {
                        model.toggleKeyframeInPlace(entity.id)
                    }
                    clusterButton("arrowtriangle.right.fill", help: "Next keyframe (L)") {
                        model.jumpToKeyframe(entity.id, direction: 1)
                    }
                }
                .padding(.horizontal, 2)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.leading, 8)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
                    // A plain click on empty track clears the selection; a
                    // 4pt-threshold drag starts the marquee instead.
                    .onTapGesture { model.selectedKeyframeIds.removeAll() }

                if case .ball = entity.kind, model.possessionEnabled {
                    possessionMarkers(width: width, duration: duration)
                }

                ForEach(model.laneKeyframes(for: entity.id)) { lane in
                    marker(color: laneColor(entity).opacity(lane.inWindow ? 1 : 0.35),
                           selected: model.selectedKeyframeIds.contains(lane.keyframe.id))
                        .position(x: CGFloat(lane.absoluteTime / duration) * width, y: laneHeight / 2)
                        .gesture(keyframeDrag(lane: lane, entity: entity,
                                              width: width, duration: duration))
                        .onTapGesture {
                            model.selectedEntityId = entity.id
                            // Click selects; shift-click adds. Playhead stays
                            // put — selection and scrubbing are separate acts.
                            if NSEvent.modifierFlags.contains(.shift) {
                                if model.selectedKeyframeIds.contains(lane.keyframe.id) {
                                    model.selectedKeyframeIds.remove(lane.keyframe.id)
                                } else {
                                    model.selectedKeyframeIds.insert(lane.keyframe.id)
                                }
                            } else {
                                model.selectedKeyframeIds = [lane.keyframe.id]
                            }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                model.deleteKeyframe(entityId: entity.id,
                                                     keyframeId: lane.keyframe.id)
                            }
                            Divider()
                            // Interpolation of the segment LEAVING this key —
                            // AE semantics; stored on the next keyframe.
                            Button("Hold") {
                                model.setOutgoingEasing(nodeId: lane.nodeId, entityId: entity.id,
                                                        keyframeId: lane.keyframe.id, easing: .hold)
                            }
                            Button("Linear") {
                                model.setOutgoingEasing(nodeId: lane.nodeId, entityId: entity.id,
                                                        keyframeId: lane.keyframe.id, easing: .linear)
                            }
                            Button("Ease In/Out") {
                                model.setOutgoingEasing(nodeId: lane.nodeId, entityId: entity.id,
                                                        keyframeId: lane.keyframe.id, easing: .easeInOut)
                            }
                            Divider()
                            Button("Copy") {
                                if !model.selectedKeyframeIds.contains(lane.keyframe.id) {
                                    model.selectedKeyframeIds = [lane.keyframe.id]
                                }
                                model.copySelectedKeyframes()
                            }
                            Button("Paste at Playhead") { model.pasteKeyframesAtPlayhead() }
                                .disabled(!model.clipboardHasKeyframes)
                        }
                }
            }
            .frame(width: width, height: laneHeight)
        }
        .frame(height: laneHeight)
    }

    /// Drag: single keyframe, or the whole selection preserving relative
    /// spacing; option-drag on the LAST selected keyframe scales the spacing
    /// (AE stretch). One undo entry per gesture, registered on the first tick.
    private func keyframeDrag(lane: PlayEditorModel.LaneKeyframe,
                              entity: DiagramEntity,
                              width: CGFloat,
                              duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragInitial == nil {
                    model.registerUndo("Retime Keyframes")
                    if !model.selectedKeyframeIds.contains(lane.keyframe.id) {
                        model.selectedKeyframeIds = [lane.keyframe.id]
                    }
                    var initial: [UUID: (UUID, UUID, Double, Double)] = [:]
                    for member in model.diagram.entities.flatMap({ model.laneKeyframes(for: $0.id) })
                    where model.selectedKeyframeIds.contains(member.keyframe.id) {
                        if let owner = model.diagram.entities.first(where: { e in
                            model.laneKeyframes(for: e.id).contains { $0.keyframe.id == member.keyframe.id }
                        }) {
                            initial[member.keyframe.id] = (member.nodeId, owner.id,
                                                           member.keyframe.t, member.absoluteTime)
                        }
                    }
                    dragInitial = initial
                    dragAnchorId = lane.keyframe.id
                }
                guard let initial = dragInitial,
                      let dragged = initial[lane.keyframe.id] else { return }
                let absoluteNow = Double(value.location.x / width) * duration
                let scaling = NSEvent.modifierFlags.contains(.option)
                    && lane.keyframe.id == initial.max { $0.value.3 < $1.value.3 }?.key

                if scaling, initial.count > 1 {
                    // Stretch: anchor at the earliest selected keyframe.
                    let anchor = initial.values.map(\.3).min() ?? 0
                    let oldSpan = dragged.3 - anchor
                    guard oldSpan > 0.01 else { return }
                    let factor = max(0.05, (absoluteNow - anchor) / oldSpan)
                    for (id, info) in initial {
                        let newAbsolute = anchor + (info.3 - anchor) * factor
                        let delta = newAbsolute - info.3
                        model.moveKeyframe(nodeId: info.0, entityId: info.1,
                                           keyframeId: id,
                                           toLocal: model.snapped(info.2 + delta))
                    }
                } else {
                    let delta = absoluteNow - dragged.3
                    for (id, info) in initial {
                        model.moveKeyframe(nodeId: info.0, entityId: info.1,
                                           keyframeId: id,
                                           toLocal: model.snapped(info.2 + delta))
                    }
                }
            }
            .onEnded { _ in
                dragInitial = nil
                dragAnchorId = nil
            }
    }

    private func boxSelectGesture(width: CGFloat, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("lanes"))
            .onChanged { value in
                if boxStart == nil { boxStart = value.startLocation }
                boxCurrent = value.location
            }
            .onEnded { value in
                defer { boxStart = nil; boxCurrent = nil }
                guard let start = boxStart else { return }
                let rect = CGRect(x: min(start.x, value.location.x),
                                  y: min(start.y, value.location.y),
                                  width: abs(value.location.x - start.x),
                                  height: abs(value.location.y - start.y))
                var hit: Set<UUID> = NSEvent.modifierFlags.contains(.shift)
                    ? model.selectedKeyframeIds : []
                // INTERSECTION, not containment: a marquee touching any part of
                // a marker or its lane row selects it.
                let markerHalf: CGFloat = 6
                for (row, entity) in model.diagram.entities.enumerated() {
                    // Lane 0 is the camera; entities start below it.
                    let rowRect = CGRect(x: rect.minX, y: CGFloat(row + 1) * laneHeight,
                                         width: rect.width, height: laneHeight)
                    guard rect.intersects(rowRect) else { continue }
                    for lane in model.laneKeyframes(for: entity.id) {
                        let x = labelWidth + 6 + CGFloat(lane.absoluteTime / duration) * width
                        let markerRect = CGRect(x: x - markerHalf,
                                                y: rowRect.minY,
                                                width: markerHalf * 2,
                                                height: laneHeight)
                        if rect.intersects(markerRect) { hit.insert(lane.keyframe.id) }
                    }
                    // Possession events live on the ball's lane and box-select
                    // exactly like keyframes.
                    if case .ball = entity.kind, model.possessionEnabled {
                        for event in model.possessionEvents {
                            let x = labelWidth + 6 + CGFloat(min(event.time, duration) / duration) * width
                            let markerRect = CGRect(x: x - markerHalf, y: rowRect.minY,
                                                    width: markerHalf * 2, height: laneHeight)
                            if rect.intersects(markerRect) { hit.insert(event.id) }
                        }
                    }
                }
                model.selectedKeyframeIds = hit
            }
    }

    private func layerToggle(_ icon: String, active: Bool, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 20, height: 20)      // real hit target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func clusterButton(_ icon: String, tint: Color? = nil, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Selected keyframes must be unmistakable: white fill, coloured stroke,
    /// scaled up — not a subtle tint.
    private func marker(color: Color, selected: Bool) -> some View {
        Diamond()
            .fill(selected ? Color.white : color)
            .overlay(Diamond().stroke(selected ? color : .clear, lineWidth: 2))
            .frame(width: 11, height: 11)
            .scaleEffect(selected ? 1.45 : 1)
            .shadow(color: selected ? color.opacity(0.6) : .clear, radius: selected ? 3 : 0)
    }

    private func playhead(width: CGFloat, duration: Double, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 1.5, height: height)
            .offset(x: labelWidth + CGFloat(model.playhead / duration) * width)
            .allowsHitTesting(false)
    }

    private func laneTitle(_ entity: DiagramEntity) -> String {
        switch entity.kind {
        case .player(let team, _, _):
            let side = team == .offense ? "O" : "D"
            return "\(side)\(entity.label ?? "")"
        case .ball:       return "Ball"
        case .screen:     return "Screen"
        case .cone:       return "Cone"
        case .annotation: return entity.label ?? "Note"
        }
    }

    private func laneColor(_ entity: DiagramEntity) -> Color {
        if case .player(let team, _, _) = entity.kind {
            return team == .offense ? .blue : .red
        }
        return .orange
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
