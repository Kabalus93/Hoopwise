import SwiftUI

/// Keyframe timeline: one lane per entity, plus a camera lane.
///
/// Scrub by dragging the ruler; drag a keyframe to retime it; click to select.
struct TimelineView: View {
    @ObservedObject var model: PlayEditorModel

    private let laneHeight: CGFloat = 26
    private let labelWidth: CGFloat = 120
    private let rulerHeight: CGFloat = 22

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
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    model.stop()
                    model.playhead = min(max(0, Double(value.location.x / width) * duration), duration)
                }
            )
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
                    marker(color: .purple, selected: false)
                        .position(x: CGFloat(frame.t / duration) * width, y: laneHeight / 2)
                        .help("\(Int(frame.value))° at \(String(format: "%.2f", frame.t))s")
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
            Circle()
                .fill(event.color)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                .frame(width: 9, height: 9)
                .position(x: CGFloat(min(event.time, duration) / duration) * width,
                          y: laneHeight / 2)
                .help(event.label)
        }
    }

    private func entityLane(_ entity: DiagramEntity, width: CGFloat, duration: Double) -> some View {
        let isSelected = model.selectedEntityId == entity.id

        return HStack(spacing: 0) {
            Button {
                model.selectedEntityId = entity.id
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(laneColor(entity)).frame(width: 8, height: 8)
                    Text(laneTitle(entity))
                        .font(.caption)
                        .lineLimit(1)
                }
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))

                if case .ball = entity.kind, model.possessionEnabled {
                    possessionMarkers(width: width, duration: duration)
                }

                ForEach(model.laneKeyframes(for: entity.id)) { lane in
                    marker(color: laneColor(entity).opacity(lane.inWindow ? 1 : 0.35),
                           selected: isSelected && abs(lane.absoluteTime - model.playhead) < 0.02)
                        .position(x: CGFloat(lane.absoluteTime / duration) * width, y: laneHeight / 2)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let absolute = Double(value.location.x / width) * duration
                                    let start = lane.absoluteTime - lane.keyframe.t
                                    model.moveKeyframe(nodeId: lane.nodeId,
                                                       entityId: entity.id,
                                                       keyframeId: lane.keyframe.id,
                                                       toLocal: max(0, absolute - start))
                                }
                        )
                        .onTapGesture {
                            model.selectedEntityId = entity.id
                            model.playhead = lane.absoluteTime
                        }
                        .contextMenu {
                            Button("Delete Keyframe", role: .destructive) {
                                model.deleteKeyframe(entityId: entity.id,
                                                     keyframeId: lane.keyframe.id)
                            }
                        }
                }
            }
            .frame(width: width, height: laneHeight)
        }
        .frame(height: laneHeight)
    }

    private func marker(color: Color, selected: Bool) -> some View {
        Diamond()
            .fill(color)
            .overlay(Diamond().stroke(selected ? Color.white : .clear, lineWidth: 1.5))
            .frame(width: 11, height: 11)
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
