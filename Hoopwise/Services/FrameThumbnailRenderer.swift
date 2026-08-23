import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The playbook thumbnail: FRAME 1 of the base play, drawn through the same
/// `FrameCardRenderer` the printed card uses.
///
/// FRAME 1, not the midpoint. The keyframe editor rendered a play at its middle
/// instant, which is the moment every play looks alike — five men strung out
/// mid-cut. A play is recognised by its SET-UP: horns is two men at the elbows,
/// and that is frame 1.
///
/// Bytes live on disk under Application Support and never in CloudKit, per the
/// media rule; only the path is stored on the play.
///
/// It sits in Services rather than beside the editor because it draws a play,
/// not a view — which also means it can be tested, and it was.
enum FrameThumbnailRenderer {

    static let size = CGSize(width: 480, height: 440)

    /// Renders and writes the PNG, returning its path.
    static func renderAndSave(diagram: PlayDiagram, playId: UUID,
                              frameIndex: Int = 0) -> String? {
        guard let image = render(diagram: diagram, frameIndex: frameIndex) else { return nil }
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

    static func render(diagram: PlayDiagram, frameIndex: Int = 0) -> CGImage? {
        guard let root = diagram.rootNode else { return nil }
        var sequence = diagram.frameSequence(for: root.id, startingFrom: diagram.homeFormation)
        sequence.reresolve()
        guard sequence.frames.indices.contains(frameIndex) else { return nil }

        let starts = sequence.frameStartTimes
        let time = (starts.indices.contains(frameIndex) ? starts[frameIndex] : 0) + 0.0001
        let ball = diagram.ball != nil
            ? sequence.ballPosition(at: time,
                                    ballHome: diagram.ball?.homePosition ?? .zero,
                                    openingHolder: diagram.openingHolder(for: root.id))
            : nil

        let cell = FrameCardRenderer.Cell(
            space: diagram.space,
            entities: diagram.entities,
            formation: sequence.formation(enteringFrame: frameIndex),
            frame: sequence.frames[frameIndex],
            ball: ball)

        guard let context = CGContext(data: nil,
                                      width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        // Line weights are tuned for a ~230pt print cell; at 480px the same
        // hairlines vanish, so they scale with the drawing rather than staying
        // a fixed number of device pixels.
        FrameCardRenderer.draw(cell, in: size, into: context, lineScale: 2)
        return context.makeImage()
    }
}
