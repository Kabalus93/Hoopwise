import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Renders a play's thumbnail: the Base read at its midpoint, top-down (90°),
/// court + entities + movement paths, no UI chrome.
///
/// Draws with CoreGraphics through the same CourtGeometry / CourtProjection /
/// MovementGeometry the editor uses, so the thumbnail cannot disagree with the
/// canvas about what the play looks like.
enum PlayThumbnailRenderer {

    static let size = CGSize(width: 480, height: 400)

    /// Renders and writes the PNG, returning its path. Thumbnails live on disk
    /// under Application Support — never in CloudKit, per the media rule.
    static func renderAndSave(diagram: PlayDiagram, theme: CourtTheme, playId: UUID) -> String? {
        guard let image = render(diagram: diagram, theme: theme) else { return nil }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
            .appendingPathComponent("Hoopwise/PlayThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(playId.uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url.path
    }

    static func render(diagram: PlayDiagram, theme: CourtTheme) -> CGImage? {
        guard let root = diagram.rootNode else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // CG bitmaps are y-up; the transform expects y-down view space.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let rect = CGRect(origin: .zero, size: size)
        let transform = CourtTransform(space: diagram.space, in: rect, padding: 10)
        let projection = CourtProjection(transform: transform, space: diagram.space,
                                         elevationDegrees: 90)

        // Court.
        let paths = CourtGeometry(space: diagram.space).paths()
        for region in paths.fillRegions {
            context.setFillColor(cgColor(region.role == .floor ? theme.floorHex
                                         : region.role == .paint ? theme.paintHex
                                         : theme.lineHex,
                                         alpha: region.role == .floor || region.role == .paint ? 1 : 0.06))
            context.addPath(projection.project(path: region.path))
            context.fillPath()
        }
        context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.9))
        context.setLineWidth(1.4)
        context.addPath(projection.project(path: paths.solid))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.55))
        context.addPath(projection.project(path: paths.dashed))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        // Movement paths of the Base read.
        for track in root.tracks {
            let frames = track.sortedKeyframes
            guard frames.count > 1,
                  let entity = diagram.entity(track.entityId) else { continue }
            var points: [CGPoint] = []
            let samples = 24
            for step in 0...samples {
                let t = frames.first!.t + (frames.last!.t - frames.first!.t)
                    * Double(step) / Double(samples)
                if let point = track.position(at: t) { points.append(point) }
            }
            guard points.count > 1 else { continue }
            let midpoint = root.duration / 2
            let kind: PathKind = root.isDribbling(track.entityId, at: midpoint)
                ? .dribble : frames[0].pathKind
            let tint = entityColor(entity, theme: theme)
            context.setStrokeColor(tint)
            context.setLineWidth(2)
            if kind == .pass { context.setLineDash(phase: 0, lengths: [6, 4]) }
            context.addPath(projection.project(path: MovementGeometry.line(points: points, kind: kind)))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            if let head = MovementGeometry.head(points: points, kind: kind) {
                context.addPath(projection.project(path: head))
                if MovementGeometry.headIsFilled(kind) {
                    context.setFillColor(tint); context.fillPath()
                } else {
                    context.setLineWidth(2.6); context.strokePath()
                }
            }
        }

        // Entities at the Base read's midpoint.
        let midpoint = root.duration / 2
        let steps = [PlayDiagram.BranchStep(node: root, startsAt: 0)]
        for entity in diagram.entities {
            let court: CGPoint
            if case .ball = entity.kind {
                court = root.ballPosition(at: midpoint, passSpeed: 34, shotSpeed: 26,
                                          ballHome: entity.homePosition,
                                          heldOffsetFeet: 1.9,
                                          entityExists: { id in diagram.entity(id) != nil }) { id, t in
                    PlayDiagram.segmentPosition(of: id, segment: 0, localTime: t,
                                                steps: steps, entities: diagram.entities)
                }
            } else {
                court = PlayDiagram.resolvedPosition(of: entity.id, at: midpoint,
                                                     steps: steps, entities: diagram.entities)
            }
            let centre = projection.project(court)
            let radius: CGFloat = { if case .ball = entity.kind { return 6 } else { return 11 } }()
            context.setFillColor(entityColor(entity, theme: theme))
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                           width: radius * 2, height: radius * 2))
            context.setStrokeColor(cgColor(theme.lineHex, alpha: 0.85))
            context.setLineWidth(1.2)
            context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                             width: radius * 2, height: radius * 2))
        }

        return context.makeImage()
    }

    private static func entityColor(_ entity: DiagramEntity, theme: CourtTheme) -> CGColor {
        switch entity.kind {
        case .player(let team, _, _):
            return cgColor(team == .offense ? theme.offenseHex : theme.defenseHex)
        case .ball:
            return cgColor(theme.ballHex)
        default:
            return cgColor(theme.lineHex)
        }
    }

    private static func cgColor(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return CGColor(gray: 0.5, alpha: alpha)
        }
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: alpha)
    }
}
