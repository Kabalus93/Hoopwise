import Foundation
import Photos
import UIKit
import Vision

// THE FACE INDEX (28 Nov 2026, Luther: "store faces in the media so that
// wherever a face needs to be used in the poster the engine knows from which
// photos it should choose"). Every photo in an athlete's vault is looked at
// once on the device: Vision finds the faces (rectangles only — iOS gives apps
// no face recognition), the athlete's is taken to be the LARGEST, unless the
// coach taps another on the photo. It is stored on the vault entry
// (VaultPhoto.face, inside the synced vault JSON — no schema change), so a
// poster asks `bestFace` and gets the sharpest close-up in the vault.

nonisolated enum FaceIndex {
    /// Every face Vision finds, largest first (normalized, top-left origin).
    static func faces(in image: CGImage) -> [VaultFace] {
        let rects = VNDetectFaceRectanglesRequest()
        let quality = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([rects]) } catch { return [] }
        let found = rects.results ?? []
        guard !found.isEmpty else { return [] }
        // Quality runs on the faces found (it may fail where the model is missing).
        quality.inputFaceObservations = found
        try? handler.perform([quality])
        let scored = quality.results ?? []
        let h = Double(image.height)
        return found.enumerated().map { i, f in
            let b = f.boundingBox   // bottom-left origin
            let rect = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            let q = i < scored.count ? scored[i].faceCaptureQuality.map(Double.init) : nil
            return VaultFace(rect: rect, pixels: Double(b.height) * h, quality: q)
        }
        .sorted { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }
    }

    /// The athlete's face in a photo: the largest.
    static func athleteFace(in image: CGImage) -> VaultFace? { faces(in: image).first }

    /// The vault entry whose face makes the best close-up.
    static func bestFace(in vault: [VaultPhoto]) -> VaultPhoto? {
        vault.filter { ($0.face?.score ?? 0) > 0 }.max { $0.face!.score < $1.face!.score }
    }

    /// Looks at every vault photo not looked at yet and stores what it found —
    /// one write. Videos are skipped (marked looked at).
    @MainActor
    static func index(studentId: UUID, vault: [VaultPhoto], dataManager: DataManager) async {
        let pending = vault.filter { $0.facesChecked != true }
        guard !pending.isEmpty, PhotoVault.hasAccess else { return }
        var found: [UUID: VaultFace?] = [:]
        for (entry, asset) in PhotoVault.assets(for: pending) {
            guard asset.mediaType == .image else { found[entry.id] = .some(nil); continue }
            guard let image = await PhotoVault.fullImage(asset, side: 1600), let cg = image.uprightCGImage else { continue }
            let face = await Task.detached(priority: .utility) { athleteFace(in: cg) }.value
            // Pixels at the photo's own size, not the 1600 px copy.
            let scale = Double(max(asset.pixelWidth, asset.pixelHeight)) / Double(max(cg.width, cg.height))
            found[entry.id] = face.map { var f = $0; f.pixels *= max(1, scale); return f }
        }
        guard !found.isEmpty else { return }
        dataManager.setVault(studentId: studentId) { list in
            for i in list.indices {
                guard let face = found[list[i].id] else { continue }
                if list[i].face?.byCoach != true { list[i].face = face }
                list[i].facesChecked = true
            }
        }
    }
}

extension UIImage {
    /// The bitmap drawn upright (Photos hands images with an orientation).
    nonisolated var uprightCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }.cgImage
    }
}

/// The face for a poster: the photo (cut out when Vision could) and where the
/// face sits in it.
struct PostPortrait {
    let image: UIImage
    /// Normalized, top-left origin, in `image`.
    let face: CGRect
    /// The background was removed — the template paints its own behind.
    let lifted: Bool
}

nonisolated enum PostLift {
    /// The athlete lifted out of a photo: the person whose face is largest (or
    /// the middle when there is none), a teammate leaning in left out. Full
    /// size and transparent around them.
    static func lift(_ image: CGImage, face: VaultFace?) -> CGImage? {
        let focus: CGPoint
        if let r = face?.rect {
            // Just under the chin: the body, not a face beside it.
            focus = CGPoint(x: r.midX, y: min(0.97, r.maxY + r.height * 0.6))
        } else {
            focus = CGPoint(x: 0.5, y: 0.5)
        }
        guard let c = ProfileBackgroundRemoval.cutOut(image, focus: focus, companionShare: 0.12) else { return nil }
        return ProfileBackgroundRemoval.transparent(c)
    }

    /// A transparent image cropped to what is not see-through.
    static func trimmed(_ image: CGImage) -> CGImage? { trimmedFigure(image)?.image }

    /// …and whether the subject runs off the photo's bottom edge (a waist-up
    /// shot): such a figure is set on the page's bottom edge, not stood on a
    /// shadow.
    static func trimmedFigure(_ image: CGImage) -> (image: CGImage, cutAtBottom: Bool)? {
        let w = image.width, h = image.height
        // Read alpha on a small copy; the bounds are scaled back up.
        let side = 256
        let sw = max(1, w * side / max(w, h)), sh = max(1, h * side / max(w, h))
        var alpha = [UInt8](repeating: 0, count: sw * sh)
        guard let ctx = CGContext(data: &alpha, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        var minX = sw, minY = sh, maxX = -1, maxY = -1
        for y in 0..<sh { for x in 0..<sw where alpha[y * sw + x] > 40 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        let k = Double(w) / Double(sw)
        // Memory row 0 is the top of the drawn image, as cropping counts it.
        let rect = CGRect(x: Double(minX) * k, y: Double(minY) * k,
                          width: Double(maxX - minX + 1) * k, height: Double(maxY - minY + 1) * k)
            .insetBy(dx: -k, dy: -k)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cropped = image.cropping(to: rect.integral) else { return nil }
        return (cropped, maxY >= sh - 2)
    }
}
