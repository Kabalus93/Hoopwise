import Foundation
import CoreGraphics
import CoreText

// MARK: - Frame card renderer
//
// ONE frame drawn into a CoreGraphics context, in the authoring notation.
//
// Shared (Phase D) by the printed play card and the playbook thumbnail, which
// are the same picture at two sizes — a coach who recognises a play by its
// thumbnail must find that same diagram when they print it. It is also why the
// thumbnail is no longer the presentation look: that look exists to be WATCHED,
// and it deliberately throws away the cut/dribble/screen distinction that a
// still frame has to carry on its own.
//
// Drawn through the SAME `CourtGeometry`, `CourtTransform`, `FrameNotation` and
// `MovementGeometry` the canvas uses. The only thing it adds is the FLIP: the
// canvas works in a y-down view space and CoreGraphics documents are y-up, so
// geometry is drawn inside one flipped state and TEXT outside it. Type mirrored
// by a scale is the classic way a vector document comes out wrong.
enum FrameCardRenderer {

    /// Ink and hairlines, with one accent on the BALL — the thing a reader
    /// hunts for on a play sheet. Every other distinction is SHAPE, not colour,
    /// so the card still reads out of a photocopier.
    struct Palette {
        var ink = CGColor(gray: 0.10, alpha: 1)
        var secondary = CGColor(gray: 0.45, alpha: 1)
        var hairline = CGColor(gray: 0.72, alpha: 1)
        var paint = CGColor(gray: 0.955, alpha: 1)
        var floor = CGColor(gray: 1, alpha: 1)
        var accent = CGColor(red: 0, green: 0.478, blue: 1.0, alpha: 1)
        var white = CGColor(gray: 1, alpha: 1)

        static let print = Palette()
    }

    static let puckRadiusFeet: CGFloat = 1.6

    /// Everything one frame needs, resolved before drawing, so the drawing code
    /// makes no decisions about the play.
    struct Cell {
        var space: CourtSpace
        var entities: [DiagramEntity]
        /// Where everyone stands as the frame OPENS.
        var formation: Formation
        var frame: PlayFrame
        /// Nil when the play has no ball.
        var ball: CGPoint?
    }

    /// Draws the cell filling `size`, with the context's origin already at the
    /// box's bottom-left in y-up coordinates.
    static func draw(_ cell: Cell, in size: CGSize, into context: CGContext,
                     palette: Palette = .print, lineScale: CGFloat = 1) {
        let rect = CGRect(origin: .zero, size: size)
        let transform = CourtTransform(space: cell.space, in: rect, padding: 4)

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        drawCourt(cell, transform, into: context, palette: palette, lineScale: lineScale)
        drawActions(cell, transform, into: context, palette: palette, lineScale: lineScale)
        drawPucks(cell, transform, into: context, palette: palette, lineScale: lineScale)

        context.restoreGState()

        // Numbers last and UNFLIPPED, so type reads the right way round.
        drawNumbers(cell, transform, in: size, into: context,
                    palette: palette, lineScale: lineScale)
    }

    // MARK: - Court

    private static func drawCourt(_ cell: Cell, _ transform: CourtTransform,
                                  into context: CGContext, palette: Palette,
                                  lineScale: CGFloat) {
        var affine = transform.affine
        let paths = CourtGeometry(space: cell.space).paths()

        context.setFillColor(palette.floor)
        if let floor = paths.floor.copy(using: &affine) {
            context.addPath(floor)
            context.fillPath()
        }
        context.setFillColor(palette.paint)
        if let lane = paths.paint.copy(using: &affine) {
            context.addPath(lane)
            context.fillPath()
        }
        context.setStrokeColor(palette.hairline)
        context.setLineWidth(0.7 * lineScale)
        context.setLineJoin(.round)
        if let solid = paths.solid.copy(using: &affine) {
            context.addPath(solid)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [2.5 * lineScale, 2 * lineScale])
        if let dashed = paths.dashed.copy(using: &affine) {
            context.addPath(dashed)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - Notation

    private static func drawActions(_ cell: Cell, _ transform: CourtTransform,
                                    into context: CGContext, palette: Palette,
                                    lineScale: CGFloat) {
        var affine = transform.affine
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for action in cell.frame.validActions {
            let points = drawnPoints(of: action, cell: cell)
            guard points.count > 1 else { continue }
            let notation = FrameNotation.for(action.kind)

            context.setStrokeColor(palette.ink)
            context.setLineWidth((action.kind.isBallFlight ? 1.0 : 1.3) * lineScale)
            if !notation.dash.isEmpty {
                context.setLineDash(phase: 0,
                                    lengths: notation.dash.map { $0 * 0.45 * lineScale })
            }
            let line = MovementGeometry.line(points: points, kind: notation.geometry)
            if let stroked = line.copy(using: &affine) {
                context.addPath(stroked)
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])

            if let head = MovementGeometry.head(points: points, kind: notation.headKind),
               let mapped = head.copy(using: &affine) {
                context.addPath(mapped)
                if MovementGeometry.headIsFilled(notation.headKind) {
                    context.setFillColor(palette.ink)
                    context.fillPath()
                } else {
                    context.setLineWidth(1.6 * lineScale)
                    context.strokePath()
                }
            }

            // WHO A SCREEN IS FOR is the coaching content of the screen. A
            // T-bar with nobody attached says only that a man stopped there.
            if action.kind == .screen, let forId = action.screenForId,
               let target = cell.formation[forId], let end = points.last {
                context.setStrokeColor(palette.secondary)
                context.setLineWidth(0.6 * lineScale)
                context.setLineDash(phase: 0, lengths: [1.5 * lineScale, 2 * lineScale])
                let link = CGMutablePath()
                link.move(to: end)
                link.addLine(to: target)
                if let mapped = link.copy(using: &affine) {
                    context.addPath(mapped)
                    context.strokePath()
                }
                context.setLineDash(phase: 0, lengths: [])
            }
        }
    }

    /// The points an action is DRAWN through. Same rule as the canvas: a flight
    /// leaves the BALL, a movement leaves the actor.
    static func drawnPoints(of action: PlayAction, cell: Cell) -> [CGPoint] {
        let origin: CGPoint
        if action.kind.isBallFlight {
            origin = cell.ball ?? cell.formation[action.actorId] ?? .zero
        } else {
            origin = cell.formation[action.actorId] ?? .zero
        }
        switch action.kind {
        case .pass, .handoff:
            guard let target = action.target?.playerId, let point = cell.formation[target]
            else { return [origin] }
            return [origin, point]
        case .shot:
            if case .point(let target)? = action.target { return [origin, target] }
            return [origin, cell.space.metrics.nearBasket]
        default:
            return [origin] + action.path
        }
    }

    // MARK: - Entities

    private static func drawPucks(_ cell: Cell, _ transform: CourtTransform,
                                  into context: CGContext, palette: Palette,
                                  lineScale: CGFloat) {
        let radius = transform.length(puckRadiusFeet)
        for placement in cell.formation.placements {
            guard let entity = cell.entities.first(where: { $0.id == placement.entityId }),
                  entity.isPlayer else { continue }
            let centre = transform.point(placement.position)
            let box = CGRect(x: centre.x - radius, y: centre.y - radius,
                             width: radius * 2, height: radius * 2)
            // OFFENCE IS SOLID, DEFENCE IS HOLLOW. The distinction survives a
            // photocopier; a colour one does not.
            if isOffence(entity) {
                context.setFillColor(palette.ink)
                context.fillEllipse(in: box)
            } else {
                context.setFillColor(palette.white)
                context.fillEllipse(in: box)
                context.setStrokeColor(palette.ink)
                context.setLineWidth(1.1 * lineScale)
                context.strokeEllipse(in: box)
            }
        }

        guard let ball = cell.ball else { return }
        let centre = transform.point(ball)
        let ballRadius = radius * 0.52
        // A white ring first, so the ball reads on top of a solid puck.
        context.setFillColor(palette.white)
        context.fillEllipse(in: CGRect(x: centre.x - ballRadius - 1.1 * lineScale,
                                       y: centre.y - ballRadius - 1.1 * lineScale,
                                       width: (ballRadius + 1.1 * lineScale) * 2,
                                       height: (ballRadius + 1.1 * lineScale) * 2))
        context.setFillColor(palette.accent)
        context.fillEllipse(in: CGRect(x: centre.x - ballRadius, y: centre.y - ballRadius,
                                       width: ballRadius * 2, height: ballRadius * 2))
    }

    static func isOffence(_ entity: DiagramEntity) -> Bool {
        if case .player(let team, _, _) = entity.kind { return team == .offense }
        return false
    }

    private static func drawNumbers(_ cell: Cell, _ transform: CourtTransform,
                                    in size: CGSize, into context: CGContext,
                                    palette: Palette, lineScale: CGFloat) {
        for placement in cell.formation.placements {
            guard let entity = cell.entities.first(where: { $0.id == placement.entityId }),
                  entity.isPlayer,
                  let label = entity.label, !label.isEmpty else { continue }
            let centre = transform.point(placement.position)
            let font = PDFFont.bilingual(size: 8 * lineScale, bold: true)
            let colour = isOffence(entity) ? palette.white : palette.ink
            let attributed = NSAttributedString(string: label, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: colour
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            // The flip is undone here: the court was drawn y-down inside a
            // flipped state, so a court point's y-up position is the box height
            // minus its view y.
            context.textPosition = CGPoint(x: centre.x - bounds.width / 2,
                                           y: size.height - centre.y - bounds.height / 2)
            CTLineDraw(line, context)
        }
    }
}
