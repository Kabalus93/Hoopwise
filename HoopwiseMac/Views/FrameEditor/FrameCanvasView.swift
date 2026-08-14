import SwiftUI

/// The frame canvas: one frame's pose, one frame's actions, nothing else.
///
/// PER-FRAME DISPLAY REPLACES TIME-WINDOWING. The keyframe editor had to decide
/// which of a play's paths were "current" from a playhead, which is the problem
/// A2's window was solving. A frame answers it structurally: what you see is
/// what this frame does.
///
/// Plan view only — v2 has no camera, so there is no projection to invert and a
/// drag lands exactly where the pointer is.
struct FrameCanvasView: View {
    @ObservedObject var model: FrameEditorModel
    /// What the tool palette has armed for placement, if anything.
    var placementKind: DiagramEntityKind?
    var onPlaced: () -> Void

    @State private var drag: DragState?
    @State private var hoverCourt: CGPoint?
    /// The edit court is a LIGHT/DARK PAIR tuned for legibility, not the
    /// diagram's stored presentation theme — that one is the published video
    /// look and Phase D still renders it untouched.
    @Environment(\.colorScheme) private var colorScheme

    private struct DragState {
        var grab: FrameEditorModel.Grab
        var current: CGPoint
        var bendingActionId: UUID?
        var didInsertBend = false
    }

    private let puckRadiusFeet: CGFloat = 1.6
    private let ballRadiusFeet: CGFloat = 1.05

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let transform = CourtTransform(space: model.diagram.space, in: rect, padding: 18)

            Canvas { context, _ in
                drawCourt(transform, into: &context)
                drawOnionSkin(transform, into: &context)
                drawActions(transform, into: &context)
                drawEntities(transform, into: &context)
                drawDragPreview(transform, into: &context)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    hoverCourt = transform.courtPoint(location)
                } else {
                    hoverCourt = nil
                }
            }
            .gesture(dragGesture(transform))
            .onTapGesture { location in
                handleTap(transform.courtPoint(location))
                model.hudAnchor = hudAnchor(transform)
            }
            .onChange(of: model.selectedActionId) { _, _ in
                model.hudAnchor = hudAnchor(transform)
            }
            .onChange(of: model.selectedEntityId) { _, _ in
                model.hudAnchor = hudAnchor(transform)
            }
            .onChange(of: model.frameIndex) { _, _ in
                model.hudAnchor = hudAnchor(transform)
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }

    /// Where the HUD hangs: the selected action's midpoint, or the selected
    /// entity's puck. In VIEW space, because that is where the panel lives.
    private func hudAnchor(_ transform: CourtTransform) -> CGPoint? {
        if let action = model.selectedAction {
            let points = model.drawnPoints(of: action)
            guard points.count > 1 else { return nil }
            let mid = points[points.count / 2]
            return transform.viewPoint(mid)
        }
        if let id = model.selectedEntityId, let point = model.startFormation[id] {
            return transform.viewPoint(point)
        }
        return nil
    }

    // MARK: - Court

    private func drawCourt(_ transform: CourtTransform, into context: inout GraphicsContext) {
        let paths = CourtGeometry(space: model.diagram.space).paths()
        let court = EditCourtPalette(colorScheme)
        for region in paths.fillRegions {
            let color: Color
            switch region.role {
            case .floor:  color = court.floor
            case .paint:  color = court.paint
            default:      color = court.line.opacity(0.05)
            }
            context.fill(Path(transform.viewPath(region.path)), with: .color(color))
        }
        context.stroke(Path(transform.viewPath(paths.solid)),
                       with: .color(court.line.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        context.stroke(Path(transform.viewPath(paths.dashed)),
                       with: .color(court.line.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
    }

    // MARK: - Onion skin

    /// The previous frame's end formation, ghosted. Continuity is the thing
    /// frames make easy to get wrong — a player is where you left him, and
    /// without seeing that you re-place him by eye.
    private func drawOnionSkin(_ transform: CourtTransform, into context: inout GraphicsContext) {
        guard let formation = model.onionFormation else { return }
        for placement in formation.placements {
            guard let entity = model.diagram.entity(placement.entityId), entity.isPlayer
            else { continue }
            let centre = transform.viewPoint(placement.position)
            let radius = transform.length(puckRadiusFeet)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(tint(entity).opacity(0.30)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
    }

    // MARK: - Actions (the notation)

    private func drawActions(_ transform: CourtTransform, into context: inout GraphicsContext) {
        guard let frame = model.currentFrame else { return }
        for action in frame.validActions {
            let points = model.drawnPoints(of: action)
            guard points.count > 1 else { continue }
            let selected = model.selectedActionId == action.id
            let notation = FrameNotation.for(action.kind)
            let colour = notation.usesBallColour
                ? Color(hex: "#E8863C")
                : tint(model.diagram.entity(action.actorId))

            let line = MovementGeometry.line(points: points, kind: notation.geometry)
            context.stroke(Path(transform.viewPath(line)),
                           with: .color(colour.opacity(selected ? 1 : 0.92)),
                           style: StrokeStyle(lineWidth: selected ? 3.4 : 2.4,
                                              lineCap: .round, lineJoin: .round,
                                              dash: notation.dash))

            // ONE head per action, at its end: an arrow, or a screen's T-bar.
            if let head = MovementGeometry.head(points: points, kind: notation.headKind) {
                let path = Path(transform.viewPath(head))
                if MovementGeometry.headIsFilled(notation.headKind) {
                    context.fill(path, with: .color(colour))
                } else {
                    context.stroke(path, with: .color(colour), lineWidth: 3)
                }
            }

            // A screen says who it is FOR — the link is the coaching content.
            if action.kind == .screen, let forId = action.screenForId,
               let target = model.startFormation[forId] {
                var link = Path()
                link.move(to: transform.viewPoint(points[points.count - 1]))
                link.addLine(to: transform.viewPoint(target))
                context.stroke(link, with: .color(colour.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
    }

    // MARK: - Entities

    private func drawEntities(_ transform: CourtTransform, into context: inout GraphicsContext) {
        let formation = model.startFormation
        for placement in formation.placements {
            guard let entity = model.diagram.entity(placement.entityId) else { continue }
            if case .ball = entity.kind { continue }
            let centre = transform.viewPoint(placement.position)
            let radius = transform.length(puckRadiusFeet)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            switch entity.kind {
            case .cone:
                var triangle = Path()
                triangle.move(to: CGPoint(x: centre.x, y: centre.y - radius))
                triangle.addLine(to: CGPoint(x: centre.x - radius, y: centre.y + radius * 0.8))
                triangle.addLine(to: CGPoint(x: centre.x + radius, y: centre.y + radius * 0.8))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(.yellow))
            case .screen:
                let bar = CGRect(x: centre.x - radius, y: centre.y - radius * 0.28,
                                 width: radius * 2, height: radius * 0.56)
                context.fill(Path(bar), with: .color(.gray))
            default:
                context.fill(Path(ellipseIn: rect), with: .color(tint(entity)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)),
                               lineWidth: 1.4)
            }
            if model.selectedEntityId == entity.id {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                               with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            if let label = entity.label, !label.isEmpty, entity.isPlayer {
                context.draw(context.resolve(Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)), at: centre, anchor: .center)
            }
        }

        // The ball last, so it reads on top of its holder.
        if let ball = model.ballPointAtFrameStart {
            let centre = transform.viewPoint(ball)
            let radius = transform.length(ballRadiusFeet)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color(hex: "#E8863C")))
            context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.35)),
                           lineWidth: 1)
        }
    }

    /// Live feedback: the line you are drawing, in the notation it will become.
    private func drawDragPreview(_ transform: CourtTransform, into context: inout GraphicsContext) {
        guard let drag, drag.bendingActionId == nil else { return }
        let from: CGPoint
        let kind: PlayActionKind
        switch drag.grab {
        case .entity(let id):
            from = model.startFormation[id] ?? .zero
            kind = model.armedTool == .screen ? .screen
                : (model.holderAtFrameStart == id ? .dribble : .cut)
        case .ball:
            guard let ball = model.ballPointAtFrameStart else { return }
            from = ball
            let rim = model.diagram.rimPoint
            kind = hypot(drag.current.x - rim.x, drag.current.y - rim.y) <= 4 ? .shot : .pass
        default:
            return
        }
        let notation = FrameNotation.for(kind)
        let points = [from, drag.current]
        let colour = notation.usesBallColour ? Color(hex: "#E8863C") : Color.accentColor
        context.stroke(Path(transform.viewPath(
            MovementGeometry.line(points: points, kind: notation.geometry))),
                       with: .color(colour.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                          dash: notation.dash))
        if let head = MovementGeometry.head(points: points, kind: notation.headKind) {
            context.fill(Path(transform.viewPath(head)), with: .color(colour.opacity(0.8)))
        }
        // What the drop would create, spelled out at the pointer.
        let caption = kind.displayName
        context.draw(context.resolve(Text(caption)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colour)),
                     at: transform.viewPoint(drag.current).applying(
                        CGAffineTransform(translationX: 0, y: -18)))
    }

    private func tint(_ entity: DiagramEntity?) -> Color {
        guard let entity else { return .gray }
        if let hex = entity.colorHex { return Color(hex: hex) }
        if case .player(let team, _, _) = entity.kind {
            return team == .offense ? Color(hex: "#2C6BD8") : Color(hex: "#C0392B")
        }
        return .gray
    }

    // MARK: - Gestures

    private func dragGesture(_ transform: CourtTransform) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let court = model.diagram.space.clamp(transform.courtPoint(value.location))
                if drag == nil {
                    let start = transform.courtPoint(value.startLocation)
                    let grab = model.grab(at: start)
                    // Grabbing a path BENDS it; grabbing a player or the ball
                    // authors a new action.
                    if case .action(let id) = grab {
                        model.selectedActionId = id
                        drag = DragState(grab: grab, current: court, bendingActionId: id)
                    } else {
                        drag = DragState(grab: grab, current: court)
                    }
                }
                drag?.current = court
                if let bending = drag?.bendingActionId {
                    model.bend(actionId: bending, to: court,
                               insertIfNeeded: !(drag?.didInsertBend ?? false))
                    drag?.didInsertBend = true
                }
            }
            .onEnded { value in
                defer { drag = nil }
                guard let state = drag else { return }
                let court = model.diagram.space.clamp(transform.courtPoint(value.location))
                guard state.bendingActionId == nil else { return }
                switch state.grab {
                case .entity(let id):
                    // ⌥-drag is the screen modifier, as specced.
                    let screening = NSEvent.modifierFlags.contains(.option)
                        || model.armedTool == .screen
                    model.authorMove(actor: id, to: court,
                                     screenFor: screening ? model.entity(at: court) : nil)
                case .ball:
                    model.authorBallDrop(at: court)
                default:
                    break
                }
            }
    }

    private func handleTap(_ court: CGPoint) {
        if let kind = placementKind {
            model.addEntity(kind: kind, at: court, label: nextLabel(for: kind))
            onPlaced()
            return
        }
        switch model.grab(at: court) {
        case .entity(let id):
            model.selectedEntityId = id
            model.selectedActionId = nil
        case .action(let id):
            model.selectedActionId = id
        default:
            model.selectedEntityId = nil
            model.selectedActionId = nil
        }
    }

    /// Offense numbers 1…5 in placement order, so a lineup goes down without
    /// naming each one.
    private func nextLabel(for kind: DiagramEntityKind) -> String? {
        guard case .player(let team, _, _) = kind else { return nil }
        let existing = model.diagram.entities.compactMap { entity -> Int? in
            guard case .player(let t, _, _) = entity.kind, t == team else { return nil }
            return entity.label.flatMap(Int.init)
        }
        var candidate = 1
        while existing.contains(candidate) { candidate += 1 }
        return "\(candidate)"
    }
}

// MARK: - The edit court, light and dark

/// Both appearances are first-class, and the edit court is tuned for
/// LEGIBILITY rather than for looking like the published video: high contrast
/// between floor, paint and lines at small sizes, because the strip draws this
/// same court at thumbnail scale. The presentation palette is untouched.
struct EditCourtPalette {
    let floor: Color
    let paint: Color
    let line: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            floor = Color(hex: "#22262E")
            paint = Color(hex: "#2E3947")
            line = Color(hex: "#F2F4F8")
        } else {
            floor = Color(hex: "#FBFAF7")
            paint = Color(hex: "#E7EBF2")
            line = Color(hex: "#2B3038")
        }
    }
}

// MARK: - Notation

/// How each action kind is DRAWN. The coaching conventions, as data.
///
/// Dribble keeps the shared geometry's WAVE rather than a zigzag: the wave is
/// this codebase's documented dribble convention and is what presentation
/// already renders, and a second dribble look would be a divergence with
/// nothing behind it.
struct FrameNotation {
    var geometry: PathKind
    var headKind: PathKind
    var dash: [CGFloat]
    var usesBallColour: Bool

    static func `for`(_ kind: PlayActionKind) -> FrameNotation {
        switch kind {
        case .cut:
            return FrameNotation(geometry: .run, headKind: .run, dash: [], usesBallColour: false)
        case .dribble:
            return FrameNotation(geometry: .dribble, headKind: .run, dash: [], usesBallColour: false)
        case .screen:
            return FrameNotation(geometry: .run, headKind: .screen, dash: [], usesBallColour: false)
        case .pass:
            return FrameNotation(geometry: .run, headKind: .run, dash: [7, 5], usesBallColour: true)
        case .handoff:
            return FrameNotation(geometry: .run, headKind: .run, dash: [3, 3], usesBallColour: true)
        case .shot:
            return FrameNotation(geometry: .run, headKind: .run, dash: [10, 6], usesBallColour: true)
        }
    }
}

// MARK: - Court transform helpers
//
// `point`, `inverse`, `length` and `affine` already live on CourtTransform and
// already handle the y flip. Only the whole-path convenience is new, and it
// goes through `affine` so it cannot disagree with `point`.

extension CourtTransform {
    func viewPoint(_ court: CGPoint) -> CGPoint { point(court) }
    func courtPoint(_ view: CGPoint) -> CGPoint { inverse(view) }

    func viewPath(_ path: CGPath) -> CGPath {
        var transform = affine
        return path.copy(using: &transform) ?? path
    }
}
