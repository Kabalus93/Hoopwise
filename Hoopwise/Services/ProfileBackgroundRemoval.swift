import Foundation
import CoreGraphics
import CoreImage
import Vision

// MARK: - Profile photo background removal
//
// November 2026 (Luther's request, a sanctioned exception to the iOS UI
// freeze). A profile photo taken with ProfilePhotoCamera has its subject cut
// out ON THE DEVICE and laid over a solid colour the coach picks. Apple Vision
// only — no network, no third-party model.
//
// Two steps, so the colour picker recolours instantly:
// 1. `cutOut` (slow: Vision) finds the subject and returns the photo with a
//    feathered mask. Foreground INSTANCES, not person segmentation, so what a
//    child holds can stay; with several people in frame it keeps the one at
//    the circle's centre (`chooseInstances`), plus small instances touching
//    them (a ball Vision returned separately).
// 2. `composite` (fast: Core Image) blends the photo over the colour.
// Anything that fails returns nil, and the caller keeps the plain photo —
// a capture is never blocked or lost.

enum ProfileBackgroundRemoval {

    /// Device setting (Profile → Preferences): on unless switched off.
    static let enabledKey = "profilePhoto.removeBackground"
    /// The colour picked last, as "#RRGGBB", preselected next time.
    static let lastColorKey = "profilePhoto.backgroundColor"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The colours on offer, first = default. Clean portrait backgrounds.
    static let palette: [String] = [
        "#2F6FDE", // Hoopwise blue
        "#1C2B4A", // navy
        "#E8742A", // court orange
        "#C8312F", // red
        "#2E8B57", // green
        "#6A4BC4", // purple
        "#D9DDE3", // light grey
        "#FFFFFF", // white
        "#1A1A1A", // black
    ]

    /// The subject and its mask, at the photo's size.
    struct Cutout: Sendable {
        let image: CGImage
        /// Grey mask (white = subject), feathered, same extent as `image`.
        let mask: CIImage
    }

    // MARK: Cut out

    /// Finds the subject nearest `focus` (normalized, top-left origin; the
    /// camera's circle is centred, so the default is the middle).
    nonisolated static func cutOut(_ image: CGImage,
                                   focus: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> Cutout? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        // Pick instances on the low-resolution label map.
        let labels = observation.instanceMask
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)
        guard let base = CVPixelBufferGetBaseAddress(labels) else {
            CVPixelBufferUnlockBaseAddress(labels, .readOnly)
            return nil
        }
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var map = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { map[y * width + x] = pointer[y * rowBytes + x] }
        }
        CVPixelBufferUnlockBaseAddress(labels, .readOnly)

        let chosen = chooseInstances(labels: map, width: width, height: height, focus: focus)
        guard !chosen.isEmpty,
              let scaled = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(chosen.map(Int.init)), from: handler) else { return nil }

        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let raw = CIImage(cvPixelBuffer: scaled)
        // Feather: a short blur softens the stair-stepped edge.
        let radius = max(1.0, Double(min(image.width, image.height)) * 0.002)
        let feathered = raw.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: extent)
        return Cutout(image: image, mask: feathered)
    }

    /// Which instance labels to keep, from Vision's label map (0 = background,
    /// row-major, top-left origin). The instance under `focus` wins, else the
    /// one with a pixel nearest it; then any instance touching the winner
    /// whose area is under 40 % of it joins (a held ball returned on its own).
    /// A second person beside the child is bigger than that and stays out.
    nonisolated static func chooseInstances(labels: [UInt8], width: Int, height: Int,
                                            focus: CGPoint) -> [UInt8] {
        guard width > 0, height > 0, labels.count == width * height else { return [] }
        let fx = min(width - 1, max(0, Int(focus.x * CGFloat(width))))
        let fy = min(height - 1, max(0, Int(focus.y * CGFloat(height))))

        var area: [UInt8: Int] = [:]
        var nearest: [UInt8: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                area[label, default: 0] += 1
                let d = (x - fx) * (x - fx) + (y - fy) * (y - fy)
                if d < nearest[label, default: .max] { nearest[label] = d }
            }
        }
        guard !area.isEmpty else { return [] }

        let underFocus = labels[fy * width + fx]
        let main = underFocus != 0
            ? underFocus
            : nearest.min { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }!.key
        let mainArea = area[main] ?? 0

        // Instances that share an edge (4-neighbour, 2 px reach) with main.
        var touching = Set<UInt8>()
        let reach = 2
        for y in 0..<height {
            for x in 0..<width where labels[y * width + x] == main {
                for dy in -reach...reach {
                    for dx in -reach...reach {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let other = labels[ny * width + nx]
                        if other != 0, other != main { touching.insert(other) }
                    }
                }
            }
        }
        let companions = touching
            .filter { Double(area[$0] ?? 0) < Double(mainArea) * 0.4 }
            .sorted()
        return [main] + companions
    }

    // MARK: Composite

    /// The subject over a solid colour ("#RRGGBB"), the photo's size.
    nonisolated static func composite(_ cutout: Cutout, hex: String) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: cutout.image.width, height: cutout.image.height)
        let (r, g, b) = rgb(hex)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let color = CIColor(red: r, green: g, blue: b, alpha: 1, colorSpace: space) else { return nil }
        let background = CIImage(color: color).cropped(to: extent)
        let photo = CIImage(cgImage: cutout.image)
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(photo, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(cutout.mask, forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output.cropped(to: extent), from: extent,
                                     format: .RGBA8, colorSpace: space)
    }

    /// Cut out and composite in one go; nil when no subject was found.
    nonisolated static func process(_ image: CGImage, hex: String,
                                    focus: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGImage? {
        guard let cutout = cutOut(image, focus: focus) else { return nil }
        return composite(cutout, hex: hex)
    }

    nonisolated static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return (0.18, 0.44, 0.87) }
        return (CGFloat((value >> 16) & 0xFF) / 255,
                CGFloat((value >> 8) & 0xFF) / 255,
                CGFloat(value & 0xFF) / 255)
    }

    nonisolated private static let context = CIContext(options: [.cacheIntermediates: false])
}
