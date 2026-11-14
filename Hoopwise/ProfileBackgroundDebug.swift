#if DEBUG
import Foundation
import CoreGraphics

// MARK: - Test scenes for background removal (DEBUG)
//
// Drawn, not photographed: no real child's photo may live in the repo. The
// same drawing feeds HOOPWISE_SHOT=backgroundRemoval (the picker over a
// scene, result logged and written to the App Group caches) and the stills
// bundled in SAMpTests/Resources (exported once from this code). A drawing
// exercises the logic — subject found, the centre one kept, no subject → nil
// — not edge quality on a real child in gym light.

enum ProfileBackgroundTestScene: String, CaseIterable {
    /// One player in the middle holding a ball, a gym behind.
    case single
    /// The player in the middle, another person at the left edge.
    case twoPeople
    /// A flat wall: nothing to cut out.
    case empty

    nonisolated func render(side: Int = 1024) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(side) / 1024
        ctx.scaleBy(x: s, y: s)
        // CoreGraphics is y-up: y = 0 is the bottom of the picture.
        if self == .empty {
            ctx.setFillColor(CGColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            return ctx.makeImage()
        }
        Self.gym(ctx)
        if self == .twoPeople {
            Self.player(ctx, cx: 130, baseY: 150, scale: 0.72,
                        jersey: CGColor(srgbRed: 0.18, green: 0.55, blue: 0.3, alpha: 1), ball: false)
        }
        Self.player(ctx, cx: 520, baseY: 0, scale: 1.2,
                    jersey: CGColor(srgbRed: 0.84, green: 0.12, blue: 0.16, alpha: 1), ball: true)
        return ctx.makeImage()
    }

    private nonisolated static func gym(_ ctx: CGContext) {
        // Wall, bleachers, then a wooden floor.
        ctx.setFillColor(CGColor(srgbRed: 0.56, green: 0.6, blue: 0.68, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        for i in 0..<8 {
            let shade = 0.38 + Double(i % 2) * 0.08
            ctx.setFillColor(CGColor(srgbRed: shade, green: 0.42, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 560 + i * 55, width: 1024, height: 30))
        }
        for i in 0..<14 {
            ctx.setFillColor(CGColor(srgbRed: 0.72 + Double(i % 3) * 0.04, green: 0.52, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: 0, y: i * 40, width: 1024, height: 40))
        }
    }

    private nonisolated static func player(_ ctx: CGContext, cx: CGFloat, baseY: CGFloat, scale s: CGFloat,
                                           jersey: CGColor, ball: Bool) {
        let skin = CGColor(srgbRed: 0.78, green: 0.58, blue: 0.44, alpha: 1)
        let dark = CGColor(srgbRed: 0.14, green: 0.14, blue: 0.17, alpha: 1)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: cx + x * s, y: baseY + y * s, width: w * s, height: h * s)
        }
        ctx.setFillColor(dark)                               // legs and shorts
        ctx.fill(rect(-62, 0, 48, 270))
        ctx.fill(rect(14, 0, 48, 270))
        ctx.addPath(CGPath(roundedRect: rect(-74, 180, 148, 110), cornerWidth: 20 * s, cornerHeight: 20 * s, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(jersey)                             // jersey
        ctx.addPath(CGPath(roundedRect: rect(-98, 250, 196, 270), cornerWidth: 46 * s, cornerHeight: 46 * s, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(skin)                               // arms, neck, head
        ctx.addPath(CGPath(roundedRect: rect(-140, 300, 44, 200), cornerWidth: 22 * s, cornerHeight: 22 * s, transform: nil))
        ctx.addPath(CGPath(roundedRect: rect(96, 300, 44, 200), cornerWidth: 22 * s, cornerHeight: 22 * s, transform: nil))
        ctx.fillPath()
        ctx.fill(rect(-24, 505, 48, 45))
        ctx.fillEllipse(in: rect(-78, 530, 156, 186))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.07, blue: 0.05, alpha: 1)) // hair
        ctx.fillEllipse(in: rect(-82, 640, 164, 88))
        if ball {
            // Held in front of the body, hands on either side.
            ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.45, blue: 0.12, alpha: 1))
            ctx.fillEllipse(in: rect(-75, 300, 150, 150))
            ctx.setStrokeColor(CGColor(srgbRed: 0.2, green: 0.1, blue: 0.05, alpha: 1))
            ctx.setLineWidth(4 * s)
            ctx.strokeEllipse(in: rect(-75, 300, 150, 150))
            ctx.move(to: CGPoint(x: cx, y: baseY + 300 * s)); ctx.addLine(to: CGPoint(x: cx, y: baseY + 450 * s))
            ctx.strokePath()
            ctx.setFillColor(skin)
            ctx.fillEllipse(in: rect(-110, 350, 44, 50))
            ctx.fillEllipse(in: rect(66, 350, 44, 50))
        }
    }
}
#endif

#if DEBUG && os(iOS)
import SwiftUI
import OSLog
import UniformTypeIdentifiers
import ImageIO

/// HOOPWISE_SHOT=backgroundRemoval (Edit Student mode, so a missing subject
/// shows its message — the simulator cannot run Vision) (+ HOOPWISE_BG_SCENE=single|twoPeople|
/// empty): the real picker over a drawn scene. Alongside it, every scene is
/// run through `process` and logged to hoopwise.mac / background ("bg
/// <scene> found|none <seconds>"), the results written to the App Group
/// Library/Caches/background-<scene>.png so they can be looked at.
struct ProfileBackgroundDebugShot: View {
    private let scene = ProfileBackgroundTestScene(
        rawValue: ProcessInfo.processInfo.environment["HOOPWISE_BG_SCENE"] ?? "") ?? .single

    var body: some View {
        if let image = scene.render() {
            ProfileBackgroundPicker(image: UIImage(cgImage: image), fromCamera: false) { result in
                Logger(subsystem: "hoopwise.mac", category: "background")
                    .notice("bg picker finished \(result == nil ? "retake" : "use", privacy: .public)")
            }
            .task { await Self.runAll() }
        } else {
            Text("Could not draw \(scene.rawValue)")
        }
    }

    private static func runAll() async {
        let log = Logger(subsystem: "hoopwise.mac", category: "background")
        let caches = WidgetShared.containerURL?.appendingPathComponent("Library/Caches", isDirectory: true)
        if let caches { try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true) }
        for scene in ProfileBackgroundTestScene.allCases {
            let line = await Task.detached(priority: .userInitiated) { () -> String in
                guard let image = scene.render() else { return "bg \(scene.rawValue) draw-failed" }
                let start = Date()
                let output = ProfileBackgroundRemoval.process(image, hex: ProfileBackgroundRemoval.palette[0])
                let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
                if let output, let url = caches?.appendingPathComponent("background-\(scene.rawValue).png"),
                   let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, output, nil)
                    CGImageDestinationFinalize(destination)
                }
                return "bg \(scene.rawValue) \(output == nil ? "none" : "found") \(seconds)s"
            }.value
            log.notice("\(line, privacy: .public)")
            print(line)
        }
        if let caches { log.notice("bg written to \(caches.path, privacy: .public)") }
    }
}
#endif
