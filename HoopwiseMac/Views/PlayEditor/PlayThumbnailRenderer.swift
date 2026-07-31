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
        // Thumbnails use the PRESENTATION style — the playbook shows what the
        // exported video will look like, not the authoring overlay. Rendered at
        // the Base read's midpoint, top-down, on an opaque black card.
        guard let root = diagram.rootNode else { return nil }
        let steps = [PlayDiagram.BranchStep(node: root, startsAt: 0)]
        return PlayFrameExporter.renderFrame(diagram: diagram,
                                             steps: steps,
                                             at: root.duration / 2,
                                             elevationDegrees: 90,
                                             look: CourtLookParameters(theme: theme),
                                             style: .presentation,
                                             backgroundHex: "#000000",
                                             size: size)
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
