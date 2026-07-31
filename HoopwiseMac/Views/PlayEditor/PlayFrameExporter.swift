import Foundation
import CoreGraphics
import CoreText
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
                            size: CGSize = exportSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // No background fill: the bitmap starts fully transparent.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let theme = look.theme
        let rect = CGRect(origin: .zero, size: size)
        let transform = CourtTransform(space: diagram.space, in: rect, padding: 24)
        let projection = CourtProjection(transform: transform, space: diagram.space,
                                         elevationDegrees: elevationDegrees, look: look)

        // Court: fills then lines — the video style.
        let paths = CourtGeometry(space: diagram.space).paths()
        for region in paths.fillRegions {
            let alpha: CGFloat = (region.role == .floor || region.role == .paint) ? 1 : 0.06
            context.setFillColor(cgColor(region.role == .floor ? theme.floorHex
                                         : region.role == .paint ? theme.paintHex
                                         : theme.lineHex, alpha: alpha))
            context.addPath(projection.project(path: region.path))
            context.fillPath()
        }
        context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.9))
        context.setLineWidth(2.4)
        context.addPath(projection.project(path: paths.solid))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [7, 5])
        context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.55))
        context.addPath(projection.project(path: paths.dashed))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        // Movement paths per segment, auto-dribble derived exactly as on screen.
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
                let tint = entityColor(entity, theme: theme)
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
            let radius = transform.length(isBall ? 1.1 : 1.6) * depth

            let tilt = projection.tilt
            if tilt > 0.001 {
                let lift = radius * 0.9 * tilt
                context.setFillColor(CGColor(gray: 0, alpha: 0.30 * tilt))
                context.fillEllipse(in: CGRect(x: centre.x - radius,
                                               y: centre.y + lift - radius * 0.3 * tilt,
                                               width: radius * 2, height: radius * 0.6 * tilt))
            }
            context.setFillColor(entityColor(entity, theme: theme))
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                           width: radius * 2, height: radius * 2))
            context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.9))
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                             width: radius * 2, height: radius * 2))

            if let label = entity.label, !label.isEmpty, !isBall {
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

    private static func entityColor(_ entity: DiagramEntity, theme: CourtTheme) -> CGColor {
        switch entity.kind {
        case .player(let team, _, _):
            return cgColor(team == .offense ? theme.offenseHex : theme.defenseHex)
        case .ball: return cgColor(theme.ballHex)
        default:    return cgColor(theme.lineHex)
        }
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
