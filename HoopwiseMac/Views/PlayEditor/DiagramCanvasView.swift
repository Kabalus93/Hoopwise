import SwiftUI

/// The court canvas: fills, lines, motion paths, and entities.
///
/// Everything is drawn through `CourtProjection`, and every gesture converts
/// back with `unproject`, so placement is in court feet at any camera angle.
struct DiagramCanvasView: View {
    @ObservedObject var model: PlayEditorModel
    /// What a click on empty floor places, or nil to select instead.
    var placementKind: DiagramEntityKind?
    var onPlaced: () -> Void

    @State private var dragEntityId: UUID?
    /// Where the ball is being dragged, for the drop preview. The ball is never
    /// keyframed by dragging when possession is on.
    @State private var ballDragLocation: CGPoint?

    // Court-feet radii, so markers stay the right size relative to the floor.
    private let puckRadiusFeet: CGFloat = 1.6
    private let baseLabelSize: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let transform = CourtTransform(space: model.diagram.space, in: rect, padding: 16)
            let projection = CourtProjection(transform: transform,
                                             space: model.diagram.space,
                                             elevationDegrees: model.renderElevation,
                                             look: model.look)

            Canvas { context, _ in
                draw(court: projection, into: &context)
                drawMotionPaths(projection, into: &context)
                drawEntities(projection, into: &context)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(projection))
            .onTapGesture { location in
                handleTap(at: location, projection: projection)
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: - Court

    private func draw(court projection: CourtProjection, into context: inout GraphicsContext) {
        let paths = CourtGeometry(space: model.diagram.space).paths()

        // Fills first, lines on top — the white-line-over-coloured-floor style.
        for region in paths.fillRegions {
            let projected = projection.project(path: region.path)
            context.fill(Path(projected), with: .color(fillColor(for: region.role)))
        }

        let solid = projection.project(path: paths.solid)
        context.stroke(Path(solid), with: .color(lineColor.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

        let dashed = projection.project(path: paths.dashed)
        context.stroke(Path(dashed), with: .color(lineColor.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
    }

    private func fillColor(for role: CourtFillRole) -> Color {
        let theme = model.theme
        switch role {
        case .floor:          return Color(hex: theme.floorHex)
        case .paint:          return Color(hex: theme.paintHex)
        case .restrictedArea: return Color(hex: theme.lineHex).opacity(0.06)
        case .centerCircle:   return Color(hex: theme.lineHex).opacity(0.05)
        }
    }

    private var lineColor: Color { Color(hex: model.theme.lineHex) }

    // MARK: - Motion

    /// Movement lines with heads, built in COURT FEET then projected.
    ///
    /// Lines, arrowheads and screen bars lie on the floor plane, so they go
    /// through the homography exactly like court markings. Only pucks and
    /// labels are billboarded — build a head in view space and it floats above
    /// an oblique court.
    private func drawMotionPaths(_ projection: CourtProjection, into context: inout GraphicsContext) {
        guard model.showMovementPaths, let node = model.activeNode else { return }

        for track in node.tracks {
            let frames = track.sortedKeyframes
            guard frames.count > 1, let entity = model.entity(track.entityId) else { continue }
            // The ball's line comes from possession, not its track.
            if case .ball = entity.kind, model.possessionEnabled { continue }
            let tint = color(for: entity)

            for index in 0..<(frames.count - 1) {
                let from = frames[index]
                let to = frames[index + 1]
                var courtPoints: [CGPoint] = []
                let samples = 20
                for step in 0...samples {
                    let t = from.t + (to.t - from.t) * Double(step) / Double(samples)
                    if let point = track.position(at: t) { courtPoints.append(point) }
                }
                guard courtPoints.count > 1 else { continue }
                // While the entity holds the ball its line IS the dribble,
                // regardless of the authored path kind — and the ball draws
                // nothing of its own.
                let kind: PathKind = (model.possessionEnabled
                                      && model.isDribbling(track.entityId, at: from.t))
                    ? .dribble : from.pathKind
                drawSegment(courtPoints, kind: kind, tint: tint,
                            projection: projection, into: &context)
            }
        }

        // Pass and shot lines DERIVE from possession — one source of truth for
        // "the ball went from here to there".
        if model.possessionEnabled {
            let releases = node.releases(passSpeed: model.look.passSpeedFeetPerSecond,
                                         shotSpeed: model.look.shotSpeedFeetPerSecond) { id, t in
                model.position(of: id, at: t)
            }
            for item in releases {
                let tint = Color(hex: model.theme.ballHex)
                switch item.release {
                case .pass:
                    drawSegment([item.from, item.to], kind: .pass, tint: tint,
                                projection: projection, into: &context)
                case .shot:
                    // Shallow parabola toward the rim, sampled in court feet so
                    // it projects with the floor.
                    var points: [CGPoint] = []
                    for step in 0...20 {
                        let f = CGFloat(step) / 20
                        let x = item.from.x + (item.to.x - item.from.x) * f
                        let y = item.from.y + (item.to.y - item.from.y) * f
                        let arc = sin(Double(f) * .pi) * 1.6
                        points.append(CGPoint(x: x, y: y - CGFloat(arc)))
                    }
                    drawSegment(points, kind: .pass, tint: tint,
                                projection: projection, into: &context)
                }
            }
        }
    }

    private func drawSegment(_ courtPoints: [CGPoint],
                             kind: PathKind,
                             tint: Color,
                             projection: CourtProjection,
                             into context: inout GraphicsContext) {
        let line = MovementGeometry.line(points: courtPoints, kind: kind)
        context.stroke(Path(projection.project(path: line)),
                       with: .color(tint.opacity(0.95)),
                       style: strokeStyle(for: kind))

        guard let head = MovementGeometry.head(points: courtPoints, kind: kind) else { return }
        let projected = Path(projection.project(path: head))
        if MovementGeometry.headIsFilled(kind) {
            context.fill(projected, with: .color(tint))
        } else {
            context.stroke(projected, with: .color(tint),
                           style: StrokeStyle(lineWidth: 3, lineCap: .butt))
        }
    }

    /// Coaching convention. Dribble is a real WAVE built in MovementGeometry,
    /// so it strokes solid here — a dash pattern would read as a pass.
    private func strokeStyle(for kind: PathKind) -> StrokeStyle {
        switch kind {
        case .run, .cut: return StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        case .dribble:   return StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        case .pass:      return StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [7, 5])
        case .screen:    return StrokeStyle(lineWidth: 2.6, lineCap: .round)
        }
    }

    // MARK: - Entities

    /// Explicit layer stack. Draw order NEVER depends on the order entities
    /// happen to sit in the array — that is why the ball rendered sometimes
    /// above and sometimes below the receiving player.
    ///
    ///   screens/cones -> player pucks -> ball -> labels
    ///
    /// (floor fills, court lines and movement paths are drawn before this by
    /// the caller, in that order.)
    private func drawEntities(_ projection: CourtProjection, into context: inout GraphicsContext) {
        let props = model.diagram.entities.filter { entity in
            switch entity.kind {
            case .screen, .cone, .annotation: return true
            default: return false
            }
        }
        // Players still sort far-to-near among THEMSELVES so nearer players
        // overlap farther ones. That is depth, not array order.
        let players = model.diagram.entities
            .filter(\.isPlayer)
            .sorted { resolvedPosition($0).y > resolvedPosition($1).y }
        let ball = model.diagram.entities.first { if case .ball = $0.kind { return true } else { return false } }

        for entity in props { drawEntity(entity, projection, into: &context) }
        for entity in players { drawEntity(entity, projection, into: &context) }
        if let ball { drawEntity(ball, projection, into: &context) }

        // Labels last: always legible, never occluded by a puck drawn after.
        for entity in players + (ball.map { [$0] } ?? []) {
            drawLabel(entity, projection, into: &context)
        }
    }

    /// Where an entity actually is at the playhead, ball included.
    private func resolvedPosition(_ entity: DiagramEntity) -> CGPoint {
        if case .ball = entity.kind, let derived = model.ballPosition(at: model.playhead) {
            return derived
        }
        return model.position(of: entity.id, at: model.playhead)
    }

    private func drawEntity(_ entity: DiagramEntity,
                            _ projection: CourtProjection,
                            into context: inout GraphicsContext) {
        let court = resolvedPosition(entity)
        let centre = projection.project(court)
        let depth = projection.depthScale(at: court)
        let radius = projection.transform.length(puckRadiusFeet) * depth
        let tint = color(for: entity)

        // Shadow IS the projected ellipse; the puck is not.
        let shadowRect = CGRect(x: centre.x - radius, y: centre.y - radius * 0.35,
                                width: radius * 2, height: radius * 0.7)
        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.28)))

        // Puck: BILLBOARDED — upright and depth-scaled, never pushed through
        // the homography, which would shear it into a wrong ellipse.
        let puck = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)

        switch entity.kind {
        case .ball:
            let ballRect = puck.insetBy(dx: radius * 0.32, dy: radius * 0.32)
            context.fill(Path(ellipseIn: ballRect), with: .color(Color(hex: model.theme.ballHex)))
            context.stroke(Path(ellipseIn: ballRect), with: .color(.black.opacity(0.35)),
                           lineWidth: 1)
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
            context.fill(Path(bar), with: .color(Color(hex: model.theme.lineHex)))
        default:
            context.fill(Path(ellipseIn: puck), with: .color(tint))
            context.stroke(Path(ellipseIn: puck), with: .color(Color(hex: model.theme.lineHex).opacity(0.9)),
                           lineWidth: 1.4)
        }

        if model.selectedEntityId == entity.id {
            let ring = puck.insetBy(dx: -4, dy: -4)
            context.stroke(Path(ellipseIn: ring), with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
    }

    private func drawLabel(_ entity: DiagramEntity,
                           _ projection: CourtProjection,
                           into context: inout GraphicsContext) {
        guard let label = entityLabel(entity), !label.isEmpty else { return }
        let court = resolvedPosition(entity)
        let centre = projection.project(court)
        // Labels stop shrinking at the legibility floor.
        let size = projection.labelPointSize(base: baseLabelSize, at: court)
        let text = Text(label)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(hex: model.theme.labelHex))
        context.draw(context.resolve(text), at: centre, anchor: .center)
    }

    private func entityLabel(_ entity: DiagramEntity) -> String? {
        if let label = entity.label, !label.isEmpty { return label }
        if case .player(_, let number, _) = entity.kind, let number { return "\(number)" }
        return nil
    }

    private func color(for entity: DiagramEntity) -> Color {
        let theme = model.theme
        if case .player(let team, _, _) = entity.kind {
            return Color(hex: team == .offense ? theme.offenseHex : theme.defenseHex)
        }
        if case .ball = entity.kind { return Color(hex: theme.ballHex) }
        return Color(hex: theme.lineHex)
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, projection: CourtProjection) {
        let court = projection.unproject(location)
        if let kind = placementKind {
            model.addEntity(kind: kind, at: court, label: nextLabel(for: kind))
            onPlaced()
        } else {
            model.selectedEntityId = hitTest(court, projection: projection)
        }
    }

    /// Next shirt number for the team being placed, so pucks come out numbered
    /// without a dialog per player.
    private func nextLabel(for kind: DiagramEntityKind) -> String? {
        guard case .player(let team, _, _) = kind else { return nil }
        let used = model.diagram.entities.compactMap { entity -> Int? in
            guard case .player(let t, _, _) = entity.kind, t == team else { return nil }
            return Int(entity.label ?? "")
        }
        return "\((used.max() ?? 0) + 1)"
    }

    /// Hit test in COURT FEET, so the tolerance is a real distance rather than
    /// a pixel radius that changes meaning with zoom and tilt.
    private func hitTest(_ court: CGPoint, projection: CourtProjection) -> UUID? {
        // Written as an explicit loop: the chained map/filter/min form exceeded
        // the type checker's budget.
        let tolerance: CGFloat = puckRadiusFeet * 1.4
        var best: UUID?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for entity in model.diagram.entities {
            let point = model.position(of: entity.id, at: model.playhead)
            let dx: CGFloat = point.x - court.x
            let dy: CGFloat = point.y - court.y
            let distance: CGFloat = (dx * dx + dy * dy).squareRoot()
            if distance <= tolerance && distance < bestDistance {
                bestDistance = distance
                best = entity.id
            }
        }
        return best
    }

    /// Nearest player to a court point, for possession drops.
    private func hitTestPlayers(_ court: CGPoint) -> UUID? {
        let tolerance: CGFloat = puckRadiusFeet * 2.2
        var best: UUID?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for entity in model.diagram.entities where entity.isPlayer {
            let point = model.position(of: entity.id, at: model.playhead)
            let dx: CGFloat = point.x - court.x
            let dy: CGFloat = point.y - court.y
            let distance: CGFloat = (dx * dx + dy * dy).squareRoot()
            if distance <= tolerance && distance < bestDistance {
                bestDistance = distance
                best = entity.id
            }
        }
        return best
    }

    private func dragGesture(_ projection: CourtProjection) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragEntityId == nil {
                    let start = projection.unproject(value.startLocation)
                    dragEntityId = hitTest(start, projection: projection)
                    if let id = dragEntityId {
                        model.selectedEntityId = id
                        // ONE undo entry per gesture. Registering per mouse-move
                        // is the usual mistake and makes undo useless.
                        model.registerUndo("Move Entity")
                    }
                }
                guard let id = dragEntityId, let entity = model.entity(id) else { return }

                // THE BALL IS NOT DRAGGED INTO POSITION when possession is on.
                // Writing keyframes here is what made the drop author position
                // instead of possession — the ball had a track, possession was
                // never recorded, and the derived pass line had nothing to
                // derive from. The drag only previews; the drop authors.
                if case .ball = entity.kind, model.possessionEnabled {
                    ballDragLocation = value.location
                    return
                }

                let court = projection.unproject(value.location)
                model.setKeyframe(for: id, at: model.playhead, position: court)
            }
            .onEnded { value in
                defer {
                    dragEntityId = nil
                    ballDragLocation = nil
                }
                guard let id = dragEntityId, let entity = model.entity(id) else { return }
                guard case .ball = entity.kind, model.possessionEnabled else { return }

                let drop = projection.unproject(value.location)
                // Target decides: the rim is a shot, a player is a pass.
                if model.isRimTarget(drop) {
                    model.authorShot(at: model.playhead)
                } else if let target = hitTestPlayers(drop) {
                    // authorPass falls back to beginPossession itself when
                    // there is no prior holder, so the caller does not need to
                    // second-guess the state machine.
                    model.authorPass(to: target, at: model.playhead)
                }
            }
    }
}
