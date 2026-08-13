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
    /// Live drag-to-bend target: which track, and the FIXED node-local time
    /// the grab point mapped to. Position changes during the drag; this never
    /// does.
    @State private var bendTarget: (entityId: UUID, time: Double)?

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

    /// The style the PATH LAYER draws with. Identical to the render style
    /// except that "Show all paths" lifts the edit window — the escape hatch
    /// for the rare moment you want the whole map at once.
    private var pathStyle: RenderStyle {
        var style = model.renderStyle
        if model.showAllPaths { style.editPathWindow = nil }
        return style
    }

    /// Tracks exempt from the edit window: the selected entity, the one being
    /// dragged, and the one being bent. What you are editing is on screen the
    /// whole time you are editing it, whatever the playhead says.
    private var pinnedTracks: Set<UUID> {
        var pinned: Set<UUID> = []
        if let id = model.selectedEntityId { pinned.insert(id) }
        if let id = dragEntityId { pinned.insert(id) }
        if let id = bendTarget?.entityId { pinned.insert(id) }
        return pinned
    }

    /// Movement lines with heads, built in COURT FEET then projected.
    ///
    /// Lines, arrowheads and screen bars lie on the floor plane, so they go
    /// through the homography exactly like court markings. Only pucks and
    /// labels are billboarded — build a head in view space and it floats above
    /// an oblique court.
    private func drawMotionPaths(_ projection: CourtProjection, into context: inout GraphicsContext) {
        guard model.showMovementPaths else { return }
        let style = pathStyle
        let steps = model.activeSteps
        // BOTH modes consume the shared path layer — the read-boundary gate
        // and the one-arrowhead rule are enforced inside visibleTrackPaths,
        // not here. Edit mode additionally restricts to the selected read
        // (clean swap on read switch); presentation renders the whole chain,
        // each read gated to its own window.
        let visible = PathConsumption.visibleTrackPaths(
            steps: steps,
            at: model.playhead,
            style: style,
            onlyNodeId: style.consumeBehindMotion ? nil : model.activeNodeId,
            includeTrack: { id in
                guard let entity = model.entity(id), !model.isHidden(id) else { return false }
                if case .ball = entity.kind, model.possessionEnabled { return false }
                return true
            },
            pinnedTracks: pinnedTracks)
        if style.consumeBehindMotion {
            drawPresentationPaths(visible, projection, into: &context)
        } else {
            drawEditPaths(visible, steps: steps, projection: projection, into: &context)
        }
    }

    /// The video brush: uniform soft terracotta strokes that live AHEAD of
    /// motion only. Everything paints into one blurred layer — blur applied
    /// AFTER trimming so the consumed edge stays soft — while players, ball
    /// and court lines stay sharp outside it.
    private func drawPresentationPaths(_ visible: (pieces: [PathConsumption.TrackPathPiece],
                                                   heads: [PathConsumption.TrackArrowhead]),
                                       _ projection: CourtProjection,
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

        for piece in visible.pieces {
            let line = MovementGeometry.line(points: piece.points, kind: .run)
            brush.stroke(Path(projection.project(path: line)),
                         with: .color(stroke), style: brushStyle)
            // Screens keep their T-bar at the screen point.
            if piece.kind == .screen {
                let bar = MovementGeometry.brushScreenBar(
                    at: piece.endPoint, angle: piece.endAngle,
                    halfWidthFeet: projection.transform.courtFeet(width))
                headBrush.stroke(Path(projection.project(path: bar)),
                                 with: .color(stroke), style: brushStyle)
            }
        }

        // THE arrowhead — one per track, placed by the shared layer at the
        // end of the final visible segment. A solid filled chevron survives
        // blur; fill + round-join stroke rounds the corners.
        for head in visible.heads {
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

        // Pass: the ball's REMAINING flight arc, consumed behind it. No
        // dashed line — the travelling ball is what reads as the pass. Drawn
        // ONCE, outside the step loop: ballState already resolves in the
        // segment under the playhead, so there is one flight, and stroking it
        // per step compounded through the blur into a darker line.
        if model.possessionEnabled {
            if case .inFlight(let flight, let progress) = model.ballState(at: model.playhead) {
                // Sampled from the SAME curve the ball is on — a straight line
                // to the endpoint used to cut the corner of every shot arc.
                let ahead = MovementGeometry.line(
                    points: flight.remainingPolyline(from: progress), kind: .run)
                brush.stroke(Path(projection.project(path: ahead)),
                             with: .color(stroke),
                             style: StrokeStyle(lineWidth: width * 0.7,
                                                lineCap: .round))
            }
        }
    }

    /// Edit overlay: semantic per-segment strokes from the shared path layer,
    /// plus the possession-derived pass/shot lines of the selected read.
    /// Heads are NOT drawn per segment — the one-arrowhead rule lives in the
    /// shared layer, so a direction change never sprouts a head here either.
    private func drawEditPaths(_ visible: (pieces: [PathConsumption.TrackPathPiece],
                                           heads: [PathConsumption.TrackArrowhead]),
                               steps: [PlayDiagram.BranchStep],
                               projection: CourtProjection,
                               into context: inout GraphicsContext) {
        for piece in visible.pieces {
            guard piece.stepIndex < steps.count,
                  let entity = model.entity(piece.entityId) else { continue }
            let node = steps[piece.stepIndex].node
            let tint = color(for: entity)
            // AUTO-DRIBBLE: line style is COMPUTED at render time from
            // (movement AND possession overlap), never stored. Evaluated at
            // the segment midpoint so a possession starting mid-segment still
            // reads correctly.
            let midpoint = (piece.fromT + piece.toT) / 2
            let kind: PathKind = (model.possessionEnabled
                                  && node.isDribbling(piece.entityId, at: midpoint))
                ? .dribble : piece.kind
            let line = MovementGeometry.line(points: piece.points, kind: kind)
            context.stroke(Path(projection.project(path: line)),
                           with: .color(tint.opacity(0.95)),
                           style: strokeStyle(for: kind))
            // Screens keep their T-bar at the segment end — an ornament of
            // the screen segment, distinct from the track's one arrowhead.
            if piece.kind == .screen {
                let bar = MovementGeometry.brushScreenBar(
                    at: piece.endPoint, angle: piece.endAngle,
                    halfWidthFeet: MovementGeometry.screenBarHalfWidthFeet)
                context.stroke(Path(projection.project(path: bar)),
                               with: .color(tint),
                               style: StrokeStyle(lineWidth: 3, lineCap: .butt))
            }
        }

        // THE arrowhead — one per track, at the end of the final visible
        // segment, placed by the shared layer.
        for head in visible.heads {
            guard let entity = model.entity(head.entityId) else { continue }
            let arrow = MovementGeometry.arrowHead(at: head.at, angle: head.angle)
            context.fill(Path(projection.project(path: arrow)),
                         with: .color(color(for: entity)))
        }

        // Pass and shot lines DERIVE from possession — one source of truth
        // for "the ball went from here to there". Selected read only, like
        // everything else in edit mode; node-local possession times resolve
        // through the branch-aware resolver via the step offset.
        guard model.possessionEnabled,
              let step = steps.first(where: { $0.node.id == model.activeNodeId })
        else { return }
        let releases = step.node.releases(passSpeed: model.look.passSpeedFeetPerSecond,
                                          shotSpeed: model.look.shotSpeedFeetPerSecond,
                                          heldOffsetFeet: model.look.ballHeldOffsetFeet) { id, t in
            model.resolvedPosition(of: id, at: step.startsAt + t)
        }
        // A flight is an action like any other: it appears with its release and
        // goes once the catch has settled. Selecting the ball pins them all.
        let ballPinned = model.diagram.ball.map { pinnedTracks.contains($0.id) } ?? false
        let local = model.playhead - step.startsAt
        for item in releases {
            guard ballPinned || PathConsumption.withinEditWindow(
                local, start: item.departure, end: item.arrival, style: pathStyle)
            else { continue }
            // The SAME curve the ball flies — sampled, not re-derived. The
            // shot's parabola used to be written out a second time here, and
            // the ball flew 1.9 ft off it.
            drawReleaseLine(item.flight.polyline(), tint: Color(hex: model.theme.ballHex),
                            projection: projection, into: &context)
        }
    }

    /// A possession-derived pass/shot line: dashed, with its own single head —
    /// "passes keep their own single head" is this, not the track rule.
    private func drawReleaseLine(_ courtPoints: [CGPoint],
                                 tint: Color,
                                 projection: CourtProjection,
                                 into context: inout GraphicsContext) {
        let line = MovementGeometry.line(points: courtPoints, kind: .pass)
        context.stroke(Path(projection.project(path: line)),
                       with: .color(tint.opacity(0.95)),
                       style: strokeStyle(for: .pass))
        guard let head = MovementGeometry.head(points: courtPoints, kind: .pass) else { return }
        context.fill(Path(projection.project(path: head)), with: .color(tint))
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
        let radius = projection.transform.length(puckRadiusFeet) * depth * entity.effectiveSize
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

        // The selection ring is editing chrome; presentation must show only
        // the play, so switching mid-play leaves no residue.
        if model.selectedEntityId == entity.id, !model.renderStyle.uniformBrush {
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
        case .inFlight(let flight, let progress):
            fromCourt = flight.position(atProgress: progress)
        }
        let fromView = projection.project(fromCourt)
        // Snapped: the line goes to the rim or the receiver, not the raw
        // cursor — the same ring affordance either way, so what highlights is
        // what the drop creates.
        let toView: CGPoint
        if model.ballDragOverRim {
            let rimCourt = model.rimPosition
            toView = projection.project(rimCourt)
            let depth = projection.depthScale(at: rimCourt)
            let radius = projection.transform.length(model.renderStyle.rimSnapFeet)
                * depth + 4
            let ring = CGRect(x: toView.x - radius, y: toView.y - radius,
                              width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: ring), with: .color(ballColor),
                           style: StrokeStyle(lineWidth: 2.5))
        } else if let target = model.ballDragSnapTarget {
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
            // Selecting on the court retargets the inspector: keyframe and
            // camera selections would otherwise shadow it. Empty court clears
            // everything, returning the inspector to Court/Camera.
            model.selectedCameraKeyframeId = nil
            model.selectedBallSpanId = nil
            if model.selectedEntityId == nil {
                model.selectedKeyframeIds.removeAll()
            }
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

    /// Where along a visible path a grab landed: the track's entity and the
    /// node-local time of the grab point. Time comes from the sampled
    /// polyline — samples are uniform in segment time, so the nearest point
    /// on the polyline maps straight back to t (the arc-length → t mapping).
    ///
    /// Runs in VIEW space with a ±7pt corridor (a ≥14pt widened stroke): the
    /// visible line is ~2pt, far too thin to hit directly, and a court-feet
    /// tolerance would change meaning with zoom and tilt — the opposite of
    /// entity hit-testing, where the puck has a real court size.
    private func pathGrab(at viewPoint: CGPoint,
                          projection: CourtProjection) -> (entityId: UUID, time: Double)? {
        let visible = PathConsumption.visibleTrackPaths(
            steps: model.activeSteps,
            at: model.playhead,
            style: model.renderStyle,
            onlyNodeId: model.activeNodeId,
            includeTrack: { id in
                guard let entity = model.entity(id),
                      !model.isHidden(id), !model.isLocked(id) else { return false }
                if case .ball = entity.kind, model.possessionEnabled { return false }
                return true
            })
        let tolerance: CGFloat = 7
        var best: (entityId: UUID, time: Double)?
        var bestDistance: CGFloat = tolerance
        for piece in visible.pieces {
            guard piece.points.count > 1 else { continue }
            var projected: [CGPoint] = []
            for point in piece.points { projected.append(projection.project(point)) }
            let lastIndex = projected.count - 1
            for index in 0..<lastIndex {
                let hit = distanceToSegment(viewPoint, projected[index], projected[index + 1])
                if hit.distance < bestDistance {
                    bestDistance = hit.distance
                    let f = (CGFloat(index) + hit.fraction) / CGFloat(lastIndex)
                    let time = piece.fromT + (piece.toT - piece.fromT) * Double(f)
                    best = (piece.entityId, time)
                }
            }
        }
        return best
    }

    /// Distance from a point to a segment, plus where along it the closest
    /// point sits. Written as explicit typed steps — the type-checker budget.
    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint,
                                   _ b: CGPoint) -> (distance: CGFloat, fraction: CGFloat) {
        let abx: CGFloat = b.x - a.x
        let aby: CGFloat = b.y - a.y
        let lengthSquared: CGFloat = abx * abx + aby * aby
        if lengthSquared < 0.0001 {
            let dx: CGFloat = p.x - a.x
            let dy: CGFloat = p.y - a.y
            return ((dx * dx + dy * dy).squareRoot(), 0)
        }
        var f: CGFloat = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared
        f = max(0, min(1, f))
        let cx: CGFloat = a.x + abx * f
        let cy: CGFloat = a.y + aby * f
        let dx: CGFloat = p.x - cx
        let dy: CGFloat = p.y - cy
        return ((dx * dx + dy * dy).squareRoot(), f)
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
                if dragEntityId == nil, bendTarget == nil {
                    let start = projection.unproject(value.startLocation)
                    dragEntityId = hitTest(start, projection: projection)
                    if let id = dragEntityId {
                        // THE editing-while-playing rule: direct-manipulation
                        // gestures pause playback. A drag during playback would
                        // write a keyframe at every mouse-move as the playhead
                        // advanced — a smear of keyframes across the timeline.
                        // Discrete edits (K, inspector, delete) land live.
                        model.stop()
                        model.selectedEntityId = id
                        // ONE undo entry per gesture. Registering per mouse-move
                        // is the usual mistake and makes undo useless.
                        model.registerUndo("Move Entity")
                    } else if placementKind == nil,
                              !model.renderStyle.consumeBehindMotion,
                              let grab = pathGrab(at: value.startLocation,
                                                  projection: projection) {
                        // Drag-to-bend, edit mode only: grabbing the middle of
                        // a path fixes a time (arc length → t); the drag moves
                        // the keyframe at that time — inserting it first if
                        // none is nearby. Same rules as entity drags: pause
                        // playback, one undo per gesture.
                        model.stop()
                        model.selectedEntityId = grab.entityId
                        model.registerUndo("Bend Path")
                        bendTarget = grab
                    }
                }
                if let grab = bendTarget {
                    let court = model.maybeSnap(projection.unproject(value.location))
                    model.bendTrack(entityId: grab.entityId, atLocal: grab.time, to: court)
                    return
                }
                guard let id = dragEntityId, let entity = model.entity(id) else { return }

                // THE BALL IS NOT DRAGGED INTO POSITION when possession is on.
                // The drag only previews; the drop authors.
                if case .ball = entity.kind, model.possessionEnabled {
                    guard !model.ballDragCancelled else { return }   // Esc: stop previewing
                    model.ballDragLocation = value.location
                    let court = projection.unproject(value.location)
                    // Rim wins over receiver snap: a player camped under the
                    // basket must not steal a shot drop.
                    model.ballDragOverRim = model.isRimTarget(court)
                    model.ballDragSnapTarget = model.ballDragOverRim
                        ? nil : hitTestPlayers(court)
                    return
                }

                let court = model.maybeSnap(projection.unproject(value.location))
                // Keyframes are node-local; the playhead is absolute.
                model.setKeyframe(for: id, at: model.currentLocalTime, position: court)
            }
            .onEnded { value in
                defer {
                    dragEntityId = nil
                    bendTarget = nil
                    model.ballDragLocation = nil
                    model.ballDragSnapTarget = nil
                    model.ballDragOverRim = false
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
                if model.ballDragOverRim || model.isRimTarget(drop) {
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
