import Foundation
import CoreGraphics
import CoreImage
import Vision
import ImageIO
import UniformTypeIdentifiers

// MARK: - Profile photo background removal
//
// November 2026 (Luther's request, a sanctioned exception to the iOS UI
// freeze). A profile photo taken with ProfilePhotoCamera has its subject cut
// out ON THE DEVICE. Apple Vision only — no network, no third-party model.
//
// SINCE 20 NOVEMBER 2026 (Luther: the colour is the athlete's SKILL LEVEL in
// their group — Models/SkillTier.swift) the photo is SAVED TRANSPARENT
// (`transparent` + ProfilePhotoEncoding: HEIC with alpha, PNG thumbnail) and
// the colour is painted live behind it wherever it is drawn, so it can follow
// the child's level and the program on screen. Before that the colour the
// coach picked was burned into a JPEG; those photos still show as they are,
// and Edit Student → Remove Background cuts them out again.
//
// 1. `cutOut` (slow: Vision) finds the subject and returns the photo with a
//    feathered mask. Foreground INSTANCES, not person segmentation, so what a
//    child holds can stay; with several people in frame it keeps the one at
//    the circle's centre (`chooseInstances`), plus small instances touching
//    them (a ball Vision returned separately).
// 2. `transparent` keeps the subject and clears the rest; `composite` lays it
//    over a solid colour (exports: shared cards, widget photos).
// Anything that fails returns nil, and the caller keeps the plain photo —
// a capture is never blocked or lost.

enum ProfileBackgroundRemoval {

    /// Device setting (Profile → Preferences): on unless switched off.
    static let enabledKey = "profilePhoto.removeBackground"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

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
                                   focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                                   companionShare: Double = 0.4) -> Cutout? {
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

        let chosen = chooseInstances(labels: map, width: width, height: height, focus: focus,
                                     companionShare: companionShare)
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

    /// Every person (and thing) Vision lifts out — a team photo's whole group.
    nonisolated static func cutOutAll(_ image: CGImage) -> Cutout? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty,
              let scaled = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        else { return nil }
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let radius = max(1.0, Double(min(image.width, image.height)) * 0.002)
        let feathered = CIImage(cvPixelBuffer: scaled).clampedToExtent()
            .applyingGaussianBlur(sigma: radius).cropped(to: extent)
        return Cutout(image: image, mask: feathered)
    }

    /// Which instance labels to keep, from Vision's label map (0 = background,
    /// row-major, top-left origin). The instance under `focus` wins, else the
    /// one with a pixel nearest it; then any instance touching the winner
    /// whose area is under 40 % of it joins (a held ball returned on its own).
    /// A second person beside the child is bigger than that and stays out.
    /// `companionShare` = how big (of the winner) a touching instance may be and
    /// still join; posts pass 0.12 so a teammate leaning in stays out.
    nonisolated static func chooseInstances(labels: [UInt8], width: Int, height: Int,
                                            focus: CGPoint, companionShare: Double = 0.4) -> [UInt8] {
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
            .filter { Double(area[$0] ?? 0) < Double(mainArea) * companionShare }
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

    /// The subject alone, the rest transparent, the photo's size.
    nonisolated static func transparent(_ cutout: Cutout) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: cutout.image.width, height: cutout.image.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(CIImage(cgImage: cutout.image), forKey: kCIInputImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
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

// MARK: - Storing a photo that may be transparent

/// A cut-out photo keeps its transparency on disk and in iCloud: HEIC with
/// alpha for the full photo and its thumbnail (smaller than JPEG); an opaque
/// photo stays JPEG as before. The stored field is plain Data — no schema
/// change.
enum ProfilePhotoEncoding {
    /// Whether any pixel is see-through (not just whether the format allows it).
    nonisolated static func isTransparent(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        // Sample on a small copy: the corners of a cut-out are clear.
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    /// Cheap: the file's own header (no decode); a 24 px copy only when the
    /// header does not say.
    nonisolated static func isTransparent(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        // Only a cut-out is ever stored with alpha (ProfilePhotoEncoding.data
        // writes HEIC only after checking), so the header is the answer.
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool { return hasAlpha }
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 24,
        ] as CFDictionary) else { return false }
        return isTransparent(small)
    }

    /// The bytes to store for a photo: HEIC with alpha when transparent (PNG
    /// if HEIC cannot be written), else JPEG.
    nonisolated static func data(for image: CGImage, quality: Double = 0.7) -> Data? {
        if isTransparent(image) {
            return encode(image, type: .heic, quality: quality) ?? encode(image, type: .png, quality: 1)
        }
        return encode(image, type: .jpeg, quality: quality)
    }

    /// A small square-ish copy for list rows (≤ `maxDimension` px), keeping
    /// transparency when the photo has it — HEIC (a PNG was 6× a JPEG's size),
    /// PNG only if HEIC cannot be written.
    nonisolated static func thumbnail(from data: Data, maxDimension: Int = 120) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        guard isTransparent(thumb) else { return encode(thumb, type: .jpeg, quality: 0.7) }
        return encode(thumb, type: .heic, quality: 0.7) ?? encode(thumb, type: .png, quality: 1)
    }

    nonisolated private static func encode(_ image: CGImage, type: UTType, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        // HEIC must come back with its alpha, or it is no use here.
        if type == .heic, !isTransparent(data: out as Data) { return nil }
        return out as Data
    }
}
