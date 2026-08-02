import SwiftUI
import AppKit
import ImageIO

// MARK: - Athlete photo
//
// THE photo component: every place a person's photo appears renders through
// this. The FRAME owns the size — aspect-fill inside, clipped, so a 12MP
// portrait or an extreme panorama can never influence layout; rows and cards
// stay pixel-identical to photo-less entries outside the photo frame.
// Decode happens at display scale through CGImageSource thumbnailing, so a
// phone photo costs kilobytes of texture per row, not 50MB.
struct AthletePhoto: View {
    enum PhotoShape {
        case circle
        case rounded(CGFloat)
    }

    let imageData: Data?
    let initials: String
    let color: Color
    let width: CGFloat
    let height: CGFloat
    var shape: PhotoShape = .circle

    init(imageData: Data?, initials: String, color: Color,
         size: CGFloat, shape: PhotoShape = .circle) {
        self.imageData = imageData
        self.initials = initials
        self.color = color
        self.width = size
        self.height = size
        self.shape = shape
    }

    init(imageData: Data?, initials: String, color: Color,
         width: CGFloat, height: CGFloat, shape: PhotoShape) {
        self.imageData = imageData
        self.initials = initials
        self.color = color
        self.width = width
        self.height = height
        self.shape = shape
    }

    var body: some View {
        ZStack {
            if let image = PhotoThumbnailStore.shared.thumbnail(
                for: imageData, fitting: CGSize(width: width, height: height)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder monogram — the no-photo look, kept.
                clipShape.fill(color)
                Text(initials)
                    .font(.system(size: min(width, height) * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: width, height: height)
        .clipShape(clipShape)
        .overlay(clipShape.stroke(Color(nsColor: .separatorColor).opacity(0.5),
                                  lineWidth: 0.5))
    }

    private var clipShape: AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .rounded(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// Display-size decode cache. Keyed by content and target size, so the same
/// photo at row size and card size are two small textures — never the
/// original bitmap. NSCache evicts under pressure.
final class PhotoThumbnailStore: @unchecked Sendable {
    static let shared = PhotoThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 2000
    }

    func thumbnail(for data: Data?, fitting size: CGSize) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        // 2x for Retina; bucketed so minor size differences share entries.
        let maxPixel = (max(size.width, size.height) * 2).rounded(.up)
        let key = "\(data.count)-\(data.prefix(64).hashValue)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg,
                            size: NSSize(width: CGFloat(cg.width) / 2,
                                         height: CGFloat(cg.height) / 2))
        cache.setObject(image, forKey: key)
        return image
    }
}
