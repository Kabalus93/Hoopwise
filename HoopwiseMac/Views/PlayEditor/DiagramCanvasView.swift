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
                drawGhostTrails(projection, into: &context)
                drawEntities(projection, into: &context)
                drawBallDragPreview(projection, into: &context)
            }
            .contentShape(Rectangle())
            .onAppear { model.lastProjection = projection }
            .onChange(of: model.renderElevation) { _, _ in model.lastProjection = projection }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    model.lastProjection = projection
                    let court = projection.unproject(location)
                    model.cursorCourtPoint = court
                    model.cursorEntityId = hitTest(court, projection: projection)
                case .ended:
                    model.cursorCourtPoint = nil
                    model.cursorEntityId = nil
                }
            }
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
        let style = model.renderStyle
        // Presentation forces the video court: black floor, white lines.
        if let floorHex = style.courtFloorHex {
            switch role {
            case .floor, .paint: return Color(hex: floorHex)
            case .restrictedArea, .centerCircle:
                return Color(hex: style.courtLineHex ?? "#FFFFFF").opacity(0.04)
            }
        }
        let theme = model.theme
        switch role {
        case .floor:          return Color(hex: theme.floorHex)
        case .paint:          return Color(hex: theme.paintHex)
        case .restrictedArea: return Color(hex: theme.lineHex).opacity(0.06)
        case .centerCircle:   return Color(hex: theme.lineHex).opacity(0.05)
        }
    }

    private var lineColor: Color {
        Color(hex: model.renderStyle.courtLineHex ?? model.theme.lineHex)
    }

    // MARK: - Motion

    /// Movement lines with heads, built in COURT FEET then projected.
    ///
    /// Lines, arrowheads and screen bars lie on the floor plane, so they go
    /// through the homography exactly like court markings. Only pucks and
    /// labels are billboarded — build a head in view space and it floats above
    /// an oblique court.
    private func drawMotionPaths(_ projection: CourtProjection, into context: inout GraphicsContext) {
        guard model.showMovementPaths else { return }
        if model.renderStyle.consumeBehindMotion {
            drawPresentationPaths(projection, into: &context)
        } else {
            for step in model.activeSteps {
                drawNodePaths(step.node, projection: projection, into: &context)
            }
        }
    }

    /// The video brush: uniform soft terracotta strokes that live AHEAD of
    /// motion only. Everything paints into one blurred layer — blur applied
    /// AFTER trimming so the consumed edge stays soft — while players, ball
    /// and court lines stay sharp outside it.
    private func drawPresentationPaths(_ projection: CourtProjection,
                                       into context: inout GraphicsContext) {
        let style = model.renderStyle
        let stroke = Color(hex: style.pathStrokeHex)
        // Uniform width: fraction of puck diameter, at mid-court depth.
        let midDepth = projection.depthScale(at: CGPoint(x: model.diagram.space.width / 2,
                                                         y: model.diagram.space.length / 2))
        let width = projection.transform.length(puckRadiusFeet * 2) * midDepth
            * style.pathWidthPuckFactor
        let blurRadius = width * style.pathBlurFactor

        var brush = context
        brush.addFilter(.blur(radius: blurRadius))
        // Heads composite through a LIGHTER blur so they stay soft-edged but
        // structurally crisp — full path blur ate the direction entirely.
        var headBrush = context
        headBrush.addFilter(.blur(radius: blurRadius * 0.5))
        let brushStyle = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

        for step in model.activeSteps {
            let node = step.node
            let localT = model.playhead - step.startsAt
            for track in node.tracks {
                guard let entity = model.entity(track.entityId), !model.isHidden(entity.id)
                else { continue }
                if case .ball = entity.kind, model.possessionEnabled { continue }
                let frames = track.sortedKeyframes
                guard frames.count > 1 else { continue }
                for index in 0..<(frames.count - 1) {
                    guard let visible = PathConsumption.visibleSegment(
                        track: track, from: frames[index], to: frames[index + 1],
                        at: localT, style: style) else { continue }

                    let line = MovementGeometry.line(points: visible.points, kind: .run)
                    brush.stroke(Path(projection.project(path: line)),
                                 with: .color(stroke), style: brushStyle)

                    // Screens keep their T-bar at the screen point.
                    if frames[index].pathKind == .screen {
                        let bar = MovementGeometry.brushScreenBar(
                            at: visible.headAt, angle: visible.headAngle,
                            halfWidthFeet: projection.transform.courtFeet(width))
                        headBrush.stroke(Path(projection.project(path: bar)),
                                         with: .color(stroke), style: brushStyle)
                    }
                }

                // ONE chevron per track, at the destination, visible whenever
                // any part of the path is. A solid filled shape survives blur;
                // fill + round-join stroke rounds the corners.
                if track.sortedKeyframes.last?.pathKind != .screen,
                   let head = PathConsumption.trackHead(track: track, at: localT, style: style) {
                    let chevron = MovementGeometry.filledChevronHead(
                        at: head.at, angle: head.angle,
                        strokeWidthFeet: projection.transform.courtFeet(width))
                    let projected = Path(projection.project(path: chevron))
                    headBrush.fill(projected, with: .color(stroke))
                    headBrush.stroke(projected, with: .color(stroke),
                                     style: StrokeStyle(lineWidth: width * 0.4,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                }
            }

            // Pass: the ball's REMAINING flight arc, consumed behind it. No
            // dashed line — the travelling ball is what reads as the pass.
            if model.possessionEnabled {
                if case .inFlight(_, let to, _, _) = model.ballState(at: model.playhead),
                   let ballAt = model.ballPosition(at: model.playhead) {
                    var flight = Path()
                    flight.move(to: projection.project(ballAt))
                    flight.addLine(to: projection.project(to))
                    brush.stroke(flight, with: .color(stroke),
                                 style: StrokeStyle(lineWidth: width * 0.7,
                                                    lineCap: .round))
                }
            }
        }
    }

    private func drawNodePaths(_ node: ReadNode,
                               projection: CourtProjection,
                               into context: inout GraphicsContext) {
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
                // AUTO-DRIBBLE: line style is COMPUTED at render time from
                // (movement AND possession overlap), never stored. The same
                // path renders wavy while its player holds the ball and as a
                // plain cut once possession is removed — no user action between.
                // Evaluated at the segment midpoint so a possession starting
                // mid-segment still reads correctly.
                let midpoint = (from.t + to.t) / 2
                let kind: PathKind = (model.possessionEnabled
                                      && node.isDribbling(track.entityId, at: midpoint))
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
                model.resolvedPosition(of: id, at: t)
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
        let visible = model.diagram.entities.filter { !model.isHidden($0.id) }
        let props = visible.filter { entity in
            switch entity.kind {
            case .screen, .cone, .annotation: return true
            default: return false
            }
        }
        // Players still sort far-to-near among THEMSELVES so nearer players
        // overlap farther ones. That is depth, not array order.
        let players = visible
            .filter(\.isPlayer)
            .sorted { resolvedPosition($0).y > resolvedPosition($1).y }
        let ball = visible.first { if case .ball = $0.kind { return true } else { return false } }

        for entity in props { drawEntity(entity, projection, into: &context) }
        for entity in players { drawEntity(entity, projection, into: &context) }
        // Mid-drag the ball renders under the cursor in the preview layer, not
        // at its resolved position — "in hand", visible the whole drag.
        if let ball, !model.isBallDragging { drawEntity(ball, projection, into: &context) }

        // Labels last: always legible, never occluded by a puck drawn after.
        for entity in players + (ball.map { [$0] } ?? []) {
            drawLabel(entity, projection, into: &context)
        }
    }

    /// Where an entity actually is at the playhead. Delegates to the model's
    /// single position authority so drawing and hit testing cannot disagree.
    private func resolvedPosition(_ entity: DiagramEntity) -> CGPoint {
        model.resolvedPosition(of: entity.id, at: model.playhead)
    }

    private func drawEntity(_ entity: DiagramEntity,
                            _ projection: CourtProjection,
                            into context: inout GraphicsContext) {
        // Solo dims everything but the soloed layer to 25%.
        var context = context
        context.opacity = model.opacity(for: entity.id)
        let court = resolvedPosition(entity)
        let centre = projection.project(court)
        let depth = projection.depthScale(at: court)
        let radius = projection.transform.length(puckRadiusFeet) * depth
        let tint = color(for: entity)

        // Puck: BILLBOARDED — upright and depth-scaled, never pushed through
        // the homography, which would shear it into a wrong ellipse.
        let puck = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)

        // Shadow derives ENTIRELY from tilt and vanishes at plan view. It used
        // to be a fixed ellipse, which showed as an oval artifact at 90° where
        // the projection is exactly affine and a floor shadow must coincide
        // with what casts it. It is also sized to the mark actually drawn —
        // the ball is inset, so a puck-sized shadow peeked out around it.
        let tilt = projection.tilt
        if tilt > 0.001 {
            let drawnRadius = markRadius(for: entity, puckRadius: radius)
            let lift = drawnRadius * 0.9 * tilt
            let shadowRect = CGRect(x: centre.x - drawnRadius,
                                    y: centre.y + lift - drawnRadius * 0.3 * tilt,
                                    width: drawnRadius * 2,
                                    height: drawnRadius * 0.6 * tilt)
            context.fill(Path(ellipseIn: shadowRect),
                         with: .color(.black.opacity(0.30 * Double(tilt))))
        }

        let style = model.renderStyle
        switch entity.kind {
        case .ball:
            // Presentation: small red disc tucked adjacent to the holder.
            let inset = radius * (1 - style.ballScaleFactor)
            let ballRect = puck.insetBy(dx: inset, dy: inset)
            let hex = style.uniformBrush ? style.ballHex : model.theme.ballHex
            context.fill(Path(ellipseIn: ballRect), with: .color(Color(hex: hex)))
            if !style.uniformBrush {
                context.stroke(Path(ellipseIn: ballRect), with: .color(.black.opacity(0.35)),
                               lineWidth: 1)
            }
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
            // Presentation: flat filled discs, no strokes, no numbers.
            let fill = style.uniformBrush ? Color(hex: style.playerFillHex) : tint
            context.fill(Path(ellipseIn: puck), with: .color(fill))
            if style.playerStroke {
                context.stroke(Path(ellipseIn: puck),
                               with: .color(Color(hex: model.theme.lineHex).opacity(0.9)),
                               lineWidth: 1.4)
            }
        }

        if model.selectedEntityId == entity.id {
            let ring = puck.insetBy(dx: -4, dy: -4)
            context.stroke(Path(ellipseIn: ring), with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
    }

    /// Radius of the mark actually drawn, so the shadow matches it.
    private func markRadius(for entity: DiagramEntity, puckRadius: CGFloat) -> CGFloat {
        if case .ball = entity.kind { return puckRadius * 0.68 }
        return puckRadius
    }

    /// Trailing positions at decaying opacity. Drawn beneath the entities so
    /// the live puck always reads on top. Entities that have not moved leave
    /// no trail — the samples coincide and paint inside the puck.
    private func drawGhostTrails(_ projection: CourtProjection,
                                 into context: inout GraphicsContext) {
        guard model.showGhostTrails, model.renderStyle.allowsGhostTrails else { return }
        let sampleCount = 8
        let sampleInterval = 0.12
        for entity in model.diagram.entities where !model.isHidden(entity.id) {
            guard entity.isPlayer || { if case .ball = entity.kind { return true }; return false }() else { continue }
            let tint = color(for: entity)
            let baseOpacity = model.opacity(for: entity.id)
            for index in 1...sampleCount {
                let t = model.playhead - Double(index) * sampleInterval
                guard t >= 0 else { break }
                let court: CGPoint
                if case .ball = entity.kind, let derived = model.ballPosition(at: t) {
                    court = derived
                } else {
                    court = model.resolvedPosition(of: entity.id, at: t)
                }
                let centre = projection.project(court)
                let depth = projection.depthScale(at: court)
                let radius = projection.transform.length(puckRadiusFeet) * depth
                    * (0.85 - CGFloat(index) * 0.05)
                let fade = baseOpacity * 0.38 * (1 - Double(index) / Double(sampleCount + 1))
                context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(tint.opacity(fade)))
            }
        }
    }

    /// Live feedback while dragging the ball: enlarged glowing glyph under the
    /// cursor, a provisional dashed line from the current holder, and a ring on
    /// the receiver it would snap to.
    private func drawBallDragPreview(_ projection: CourtProjection,
                                     into context: inout GraphicsContext) {
        guard let cursor = model.ballDragLocation else { return }
        let ballColor = Color(hex: model.theme.ballHex)

        // Provisional dashed line from the holder (or the ball's rest point).
        let fromCourt: CGPoint
        switch model.ballState(at: model.playhead) {
        case .held(let holderId):
            fromCourt = model.resolvedPosition(of: holderId, at: model.playhead)
        case .atRest(let point):
            fromCourt = point
        case .inFlight(let from, _, _, _):
            fromCourt = from
        }
        let fromView = projection.project(fromCourt)
        // Snapped: the line goes to the receiver, not the raw cursor.
        let toView: CGPoint
        if let target = model.ballDragSnapTarget {
            let targetCourt = model.resolvedPosition(of: target, at: model.playhead)
            toView = projection.project(targetCourt)
            // Highlight ring on the receiver.
            let depth = projection.depthScale(at: targetCourt)
            let radius = projection.transform.length(puckRadiusFeet) * depth + 5
            let ring = CGRect(x: toView.x - radius, y: toView.y - radius,
                              width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: ring), with: .color(ballColor),
                           style: StrokeStyle(lineWidth: 2.5))
        } else {
            toView = cursor
        }
        var line = Path()
        line.move(to: fromView)
        line.addLine(to: toView)
        context.stroke(line, with: .color(ballColor.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [7, 5]))

        // The ball itself, slightly enlarged with a glow so it reads as in hand.
        let radius = projection.transform.length(puckRadiusFeet) * 0.85
        let glyph = CGRect(x: cursor.x - radius, y: cursor.y - radius,
                           width: radius * 2, height: radius * 2)
        var glow = context
        glow.addFilter(.shadow(color: ballColor.opacity(0.8), radius: 8))
        glow.fill(Path(ellipseIn: glyph), with: .color(ballColor))
        context.stroke(Path(ellipseIn: glyph), with: .color(.white.opacity(0.9)), lineWidth: 1.2)
    }

    private func drawLabel(_ entity: DiagramEntity,
                           _ projection: CourtProjection,
                           into context: inout GraphicsContext) {
        guard model.renderStyle.showPlayerNumbers,
              let label = entityLabel(entity), !label.isEmpty else { return }
        var context = context
        context.opacity = model.opacity(for: entity.id)
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
        let court = model.maybeSnap(projection.unproject(location))
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
            // Hidden layers are not on the court; locked layers ignore clicks —
            // both pass through to whatever is beneath.
            if model.isHidden(entity.id) || model.isLocked(entity.id) { continue }
            // Resolver, not raw track: a ball with no track was hit-tested at
            // its home position while being drawn by the possession resolver,
            // which made it unselectable after the first pass.
            let point = model.resolvedPosition(of: entity.id, at: model.playhead)
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
            let point = model.resolvedPosition(of: entity.id, at: model.playhead)
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
                // The drag only previews; the drop authors.
                if case .ball = entity.kind, model.possessionEnabled {
                    guard !model.ballDragCancelled else { return }   // Esc: stop previewing
                    model.ballDragLocation = value.location
                    let court = projection.unproject(value.location)
                    model.ballDragSnapTarget = hitTestPlayers(court)
                    return
                }

                let court = model.maybeSnap(projection.unproject(value.location))
                // Keyframes are node-local; the playhead is absolute.
                model.setKeyframe(for: id, at: model.currentLocalTime, position: court)
            }
            .onEnded { value in
                defer {
                    dragEntityId = nil
                    model.ballDragLocation = nil
                    model.ballDragSnapTarget = nil
                    model.ballDragCancelled = false
                }
                // Esc during the drag: revert with no state mutation.
                guard !model.ballDragCancelled else { return }
                guard let id = dragEntityId, let entity = model.entity(id) else { return }
                guard case .ball = entity.kind, model.possessionEnabled else { return }

                // Snap: commit to the highlighted receiver, not the raw drop
                // point, so what the preview showed is what happens.
                let drop = projection.unproject(value.location)
                // Target decides: the rim is a shot, a player is a pass.
                if model.isRimTarget(drop) {
                    model.authorShot(at: model.currentLocalTime)
                } else if let target = model.ballDragSnapTarget ?? hitTestPlayers(drop) {
                    // authorPass falls back to beginPossession itself when
                    // there is no prior holder, so the caller does not need to
                    // second-guess the state machine.
                    model.authorPass(to: target, at: model.currentLocalTime)
                }
                // Drop over empty court: revert. No loose-ball state exists and
                // this deliberately does not invent one.
            }
    }
}
