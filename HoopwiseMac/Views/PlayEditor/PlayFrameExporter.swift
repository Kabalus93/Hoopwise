import Foundation
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Export stubs: the architecture for the Resolve pipeline, proven with a
/// single frame before any encoder work.
///
/// The full deliverables are a PNG SEQUENCE with alpha and ProRes 4444 with
/// alpha via AVAssetWriter. Both consume exactly this renderer — one frame at
/// an absolute branch time, alpha background, sized for the pipeline — so
/// proving it now means the encoder work later is plumbing, not rendering.
enum PlayFrameExporter {

    /// 1080p, the Resolve timeline size.
    static let exportSize = CGSize(width: 1920, height: 1080)

    /// Renders one frame with a TRANSPARENT background — non-negotiable for
    /// compositing. Everything on the court draws; everything outside it is
    /// alpha zero.
    static func renderFrame(diagram: PlayDiagram,
                            steps: [PlayDiagram.BranchStep],
                            at time: Double,
                            elevationDegrees: Double,
                            look: CourtLookParameters,
                            style: RenderStyle = .presentation,
                            backgroundHex: String? = nil,
                            size: CGSize = exportSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // No background fill by default: the bitmap starts fully transparent.
        // Thumbnails pass an opaque background.
        if let backgroundHex {
            context.setFillColor(cgColor(backgroundHex))
            context.fill(CGRect(origin: .zero, size: size))
        }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let theme = look.theme
        let rect = CGRect(origin: .zero, size: size)
        let transform = CourtTransform(space: diagram.space, in: rect, padding: 24)
        let projection = CourtProjection(transform: transform, space: diagram.space,
                                         elevationDegrees: elevationDegrees, look: look)

        // Court: fills then lines — the video style.
        let paths = CourtGeometry(space: diagram.space).paths()
        let floorHex = style.courtFloorHex ?? theme.floorHex
        let paintHex = style.courtFloorHex ?? theme.paintHex
        let courtLineHex = style.courtLineHex ?? theme.lineHex
        for region in paths.fillRegions {
            let alpha: CGFloat = (region.role == .floor || region.role == .paint) ? 1 : 0.05
            context.setFillColor(cgColor(region.role == .floor ? floorHex
                                         : region.role == .paint ? paintHex
                                         : courtLineHex, alpha: alpha))
            context.addPath(projection.project(path: region.path))
            context.fillPath()
        }
        context.setStrokeColor(cgColor(courtLineHex, alpha: 0.9))
        context.setLineWidth(2.4)
        context.addPath(projection.project(path: paths.solid))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [7, 5])
        context.setStrokeColor(cgColor(courtLineHex, alpha: 0.55))
        context.addPath(projection.project(path: paths.dashed))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        // Movement paths. Presentation renders the soft consumed brush into an
        // offscreen layer, blurs it with CoreImage AFTER trimming (so the
        // consumed edge stays soft), and composites — players, ball and court
        // lines are never blurred. Edit style keeps the semantic overlay.
        if style.consumeBehindMotion {
            drawBrushLayer(into: context, diagram: diagram, steps: steps,
                           at: time, style: style, projection: projection,
                           transform: transform, size: size, look: look)
        } else {
            for step in steps {
                for track in step.node.tracks {
                    let frames = track.sortedKeyframes
                    guard frames.count > 1, let entity = diagram.entity(track.entityId) else { continue }
                    var points: [CGPoint] = []
                    for sample in 0...32 {
                        let t = frames.first!.t + (frames.last!.t - frames.first!.t)
                            * Double(sample) / 32
                        if let point = track.position(at: t) { points.append(point) }
                    }
                    guard points.count > 1 else { continue }
                    let midpoint = (frames.first!.t + frames.last!.t) / 2
                    let kind: PathKind = step.node.isDribbling(track.entityId, at: midpoint)
                        ? .dribble : frames[0].pathKind
                    let tint = entityColor(entity, theme: theme, style: style)
                    context.setStrokeColor(tint)
                    context.setLineWidth(3)
                    if kind == .pass { context.setLineDash(phase: 0, lengths: [10, 7]) }
                    context.addPath(projection.project(path: MovementGeometry.line(points: points, kind: kind)))
                    context.strokePath()
                    context.setLineDash(phase: 0, lengths: [])
                    if let head = MovementGeometry.head(points: points, kind: kind) {
                        context.addPath(projection.project(path: head))
                        if MovementGeometry.headIsFilled(kind) {
                            context.setFillColor(tint); context.fillPath()
                        } else { context.setLineWidth(4); context.strokePath() }
                    }
                }
            }
        }

        // Entities: far to near, billboarded, tilt-derived shadows, floored labels.
        let ordered = diagram.entities.sorted {
            resolved($0, diagram: diagram, steps: steps, time: time, look: look).y >
            resolved($1, diagram: diagram, steps: steps, time: time, look: look).y
        }
        for entity in ordered {
            let court = resolved(entity, diagram: diagram, steps: steps, time: time, look: look)
            let centre = projection.project(court)
            let depth = projection.depthScale(at: court)
            let isBall: Bool = { if case .ball = entity.kind { return true }; return false }()
            let radius = transform.length(isBall ? 1.6 * style.ballScaleFactor : 1.6) * depth

            let tilt = projection.tilt
            if tilt > 0.001 {
                let lift = radius * 0.9 * tilt
                context.setFillColor(CGColor(gray: 0, alpha: 0.30 * tilt))
                context.fillEllipse(in: CGRect(x: centre.x - radius,
                                               y: centre.y + lift - radius * 0.3 * tilt,
                                               width: radius * 2, height: radius * 0.6 * tilt))
            }
            context.setFillColor(entityColor(entity, theme: theme, style: style))
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                           width: radius * 2, height: radius * 2))
            if style.playerStroke {
                context.setStrokeColor(cgColor(courtLineHex, alpha: 0.9))
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                 width: radius * 2, height: radius * 2))
            }

            if style.showPlayerNumbers, let label = entity.label, !label.isEmpty, !isBall {
                let fontSize = projection.labelPointSize(base: 26, at: court)
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
                let attributed = NSAttributedString(string: label, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key:
                        cgColor(theme.labelHex)])
                let line = CTLineCreateWithAttributedString(attributed)
                let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
                context.saveGState()
                // Text draws y-up; flip locally around the label position.
                context.translateBy(x: centre.x - bounds.width / 2,
                                    y: centre.y + bounds.height / 2)
                context.scaleBy(x: 1, y: -1)
                context.textPosition = .zero
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }
        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func resolved(_ entity: DiagramEntity,
                                 diagram: PlayDiagram,
                                 steps: [PlayDiagram.BranchStep],
                                 time: Double,
                                 look: CourtLookParameters) -> CGPoint {
        if case .ball = entity.kind, !steps.isEmpty {
            let index = PlayDiagram.segmentIndex(at: time, steps: steps)
            let node = steps[index].node
            return node.ballPosition(at: time - steps[index].startsAt,
                                     passSpeed: look.passSpeedFeetPerSecond,
                                     shotSpeed: look.shotSpeedFeetPerSecond,
                                     ballHome: entity.homePosition,
                                     heldOffsetFeet: look.ballHeldOffsetFeet,
                                     entityExists: { diagram.entity($0) != nil }) { id, t in
                PlayDiagram.segmentPosition(of: id, segment: index, localTime: t,
                                            steps: steps, entities: diagram.entities)
            }
        }
        return PlayDiagram.resolvedPosition(of: entity.id, at: time,
                                            steps: steps, entities: diagram.entities)
    }

    private static func entityColor(_ entity: DiagramEntity, theme: CourtTheme,
                                    style: RenderStyle) -> CGColor {
        if style.uniformBrush {
            switch entity.kind {
            case .player: return cgColor(style.playerFillHex)   // flat, no teams
            case .ball:   return cgColor(style.ballHex)
            default:      return cgColor(style.courtLineHex ?? "#FFFFFF")
            }
        }
        switch entity.kind {
        case .player(let team, _, _):
            return cgColor(team == .offense ? theme.offenseHex : theme.defenseHex)
        case .ball: return cgColor(theme.ballHex)
        default:    return cgColor(theme.lineHex)
        }
    }

    /// The presentation brush layer: trimmed consumed paths and same-brush
    /// heads, blurred once with CIGaussianBlur, composited under the entities.
    private static func drawBrushLayer(into context: CGContext,
                                       diagram: PlayDiagram,
                                       steps: [PlayDiagram.BranchStep],
                                       at time: Double,
                                       style: RenderStyle,
                                       projection: CourtProjection,
                                       transform: CourtTransform,
                                       size: CGSize,
                                       look: CourtLookParameters) {
        guard let layer = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                    bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        layer.translateBy(x: 0, y: size.height)
        layer.scaleBy(x: 1, y: -1)

        let midDepth = projection.depthScale(at: CGPoint(x: diagram.space.width / 2,
                                                         y: diagram.space.length / 2))
        let width = transform.length(3.2) * midDepth * style.pathWidthPuckFactor
        layer.setStrokeColor(cgColor(style.pathStrokeHex))
        layer.setLineWidth(width)
        layer.setLineCap(.round)
        layer.setLineJoin(.round)

        for step in steps {
            let localT = time - step.startsAt
            for track in step.node.tracks {
                guard let entity = diagram.entity(track.entityId) else { continue }
                if case .ball = entity.kind { continue }
                let frames = track.sortedKeyframes
                guard frames.count > 1 else { continue }
                for index in 0..<(frames.count - 1) {
                    guard let visible = PathConsumption.visibleSegment(
                        track: track, from: frames[index], to: frames[index + 1],
                        at: localT, style: style) else { continue }
                    layer.addPath(projection.project(
                        path: MovementGeometry.line(points: visible.points, kind: .run)))
                    layer.strokePath()
                    // ONE head per path, at the destination; screens keep their
                    // T-bar. Direction changes must not sprout arrowheads.
                    let isScreen = frames[index].pathKind == .screen
                    guard isScreen || index == frames.count - 2 else { continue }
                    let head: CGPath = isScreen
                        ? MovementGeometry.brushScreenBar(at: visible.headAt,
                                                          angle: visible.headAngle,
                                                          halfWidthFeet: transform.courtFeet(width))
                        : MovementGeometry.hookedHead(at: visible.headAt,
                                                      angle: visible.headAngle)
                    layer.addPath(projection.project(path: head))
                    layer.strokePath()
                }
            }
            // Remaining pass flight ahead of the ball, same brush.
            let node = step.node
            let segmentSteps = steps
            let index = PlayDiagram.segmentIndex(at: time, steps: steps)
            if steps[index].node.id == node.id,
               let ball = diagram.ball {
                let state = node.ballState(at: localT,
                                           passSpeed: look.passSpeedFeetPerSecond,
                                           shotSpeed: look.shotSpeedFeetPerSecond,
                                           ballHome: ball.homePosition,
                                           heldOffsetFeet: look.ballHeldOffsetFeet,
                                           entityExists: { diagram.entity($0) != nil }) { id, t in
                    PlayDiagram.segmentPosition(of: id, segment: index, localTime: t,
                                                steps: segmentSteps, entities: diagram.entities)
                }
                if case .inFlight(let from, let to, let progress, _) = state {
                    let at = CGPoint(x: from.x + (to.x - from.x) * CGFloat(progress),
                                     y: from.y + (to.y - from.y) * CGFloat(progress))
                    layer.setLineWidth(width * 0.7)
                    layer.move(to: projection.project(at))
                    layer.addLine(to: projection.project(to))
                    layer.strokePath()
                    layer.setLineWidth(width)
                }
            }
        }

        guard let raw = layer.makeImage() else { return }
        // Blur AFTER trimming, path layer only.
        let ci = CIImage(cgImage: raw)
        let blurred = ci.applyingGaussianBlur(sigma: Double(width * style.pathBlurFactor))
            .cropped(to: ci.extent)
        let ciContext = CIContext()
        guard let composited = ciContext.createCGImage(blurred, from: ci.extent) else {
            context.draw(raw, in: CGRect(origin: .zero, size: size))
            return
        }
        context.saveGState()
        // The frame context is already y-flipped; draw the layer unflipped.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(composited, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    private static func cgColor(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return CGColor(gray: 0.5, alpha: alpha)
        }
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}

/// PDF play-sheet stub through the existing vector document layer.
enum PlaySheetExporter {

    /// Title + court diagram + read list. Single page — the pagination,
    /// per-read frames and teaching-point layout come with the full exporter;
    /// this proves the CGPath handoff into PDFDocumentRenderer.
    static func export(diagram: PlayDiagram, name: String, family: String,
                       to url: URL) throws {
        let renderer = PDFDocumentRenderer()
        renderer.onPageBegin = { doc, page in
            doc.footer("HoopWise · \(name) · Page \(page)")
        }
        try renderer.render(to: url) { doc in
            doc.text(name, style: .title(20))
            if !family.isEmpty { doc.text(family, style: .caption()) }
            doc.spacer(6)
            doc.rule()
            doc.spacer(10)

            // Court box: top-down, print-style dark-on-light strokes.
            let boxHeight: CGFloat = 320
            let box = doc.reserve(height: boxHeight)
            let localRect = CGRect(x: 0, y: 0, width: box.width, height: box.height)
            let transform = CourtTransform(space: diagram.space, in: localRect, padding: 6)
            let projection = CourtProjection(transform: transform, space: diagram.space,
                                             elevationDegrees: 90)
            let paths = CourtGeometry(space: diagram.space).paths()
            doc.draw(path: projection.project(path: paths.solid), in: box,
                     stroke: CGColor(gray: 0.15, alpha: 1), lineWidth: 1.2)
            doc.draw(path: projection.project(path: paths.dashed), in: box,
                     stroke: CGColor(gray: 0.45, alpha: 1), lineWidth: 0.9, dash: [4, 3])

            // Entities at the base read's midpoint.
            if let root = diagram.rootNode {
                let midpoint = root.duration / 2
                let steps = [PlayDiagram.BranchStep(node: root, startsAt: 0)]
                let dots = CGMutablePath()
                for entity in diagram.entities where entity.isPlayer {
                    let court = PlayDiagram.resolvedPosition(of: entity.id, at: midpoint,
                                                             steps: steps,
                                                             entities: diagram.entities)
                    let centre = projection.project(court)
                    dots.addEllipse(in: CGRect(x: centre.x - 6, y: centre.y - 6,
                                               width: 12, height: 12))
                }
                doc.draw(path: dots, in: box, stroke: CGColor(gray: 0.1, alpha: 1),
                         lineWidth: 1.4)
            }

            doc.spacer(12)
            doc.text("Reads", style: .heading(13))
            doc.spacer(4)
            for node in diagram.nodes {
                doc.text("• \(node.title)", style: .body())
                for point in node.teachingPoints {
                    doc.text(point, style: .caption(), indent: 14)
                }
            }
        }
    }
}
