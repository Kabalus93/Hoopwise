import SwiftUI

/// A frame at card size: court outline, the pose it opens on, and its action
/// lines in the same notation the canvas uses.
///
/// LIVE BY CONSTRUCTION rather than a debounced snapshot. It is the same
/// geometry drawn through the same `MovementGeometry`, so a thumbnail cannot
/// lag the frame it describes or disagree with it — and there is no image to
/// invalidate, cache, or re-render on a timer.
struct FrameThumbnail: View {
    @ObservedObject var model: FrameEditorModel
    let index: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let transform = CourtTransform(space: model.diagram.space, in: rect, padding: 2)
            let court = EditCourtPalette(colorScheme)
            let formation = model.sequence.formation(enteringFrame: index)
            let frame = model.frames.indices.contains(index) ? model.frames[index] : nil

            Canvas { context, _ in
                let paths = CourtGeometry(space: model.diagram.space).paths()
                context.fill(Path(transform.viewPath(paths.solid)),
                             with: .color(court.floor))
                context.stroke(Path(transform.viewPath(paths.solid)),
                               with: .color(court.line.opacity(0.35)), lineWidth: 0.6)

                if let frame {
                    for action in frame.validActions {
                        let points = drawnPoints(of: action, in: formation)
                        guard points.count > 1 else { continue }
                        let notation = FrameNotation.for(action.kind)
                        let colour = notation.usesBallColour
                            ? Color(hex: "#E8863C")
                            : tint(model.diagram.entity(action.actorId))
                        context.stroke(
                            Path(transform.viewPath(
                                MovementGeometry.line(points: points, kind: notation.geometry))),
                            with: .color(colour),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round,
                                               dash: notation.dash.map { $0 * 0.4 }))
                    }
                }

                for placement in formation.placements {
                    guard let entity = model.diagram.entity(placement.entityId),
                          entity.isPlayer else { continue }
                    let centre = transform.viewPoint(placement.position)
                    let radius = max(1.6, transform.length(1.6))
                    context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .color(tint(entity)))
                }
            }
        }
    }

    /// The same origin rule the canvas uses, against this frame's own opening
    /// formation rather than the selected frame's.
    private func drawnPoints(of action: PlayAction, in formation: Formation) -> [CGPoint] {
        let origin = formation[action.actorId] ?? .zero
        switch action.kind {
        case .pass, .handoff:
            guard let target = action.target?.playerId,
                  let point = formation[target] else { return [origin] }
            return [origin, point]
        case .shot:
            if case .point(let target)? = action.target { return [origin, target] }
            return [origin, model.diagram.rimPoint]
        default:
            return [origin] + action.path
        }
    }

    private func tint(_ entity: DiagramEntity?) -> Color {
        guard let entity else { return .gray }
        if let hex = entity.colorHex { return Color(hex: hex) }
        if case .player(let team, _, _) = entity.kind {
            return team == .offense ? Color(hex: "#2C6BD8") : Color(hex: "#C0392B")
        }
        return .gray
    }
}
