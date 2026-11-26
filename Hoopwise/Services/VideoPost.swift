import AVFoundation
import Photos
import QuartzCore
import UIKit

// VIDEO POSTS (26 Nov 2026, Luther: "now let's do overlay templates for
// videos"). A clip from the athlete's vault, trimmed to at most a minute, cut to
// a 9:16 / 4:5 / 1:1 frame, with an ANIMATED overlay of their stats on top
// (VideoOverlayTemplates.swift builds the overlay as a CALayer tree). The SAME
// layer tree plays over the preview (AVSynchronizedLayer) and is burnt into the
// export (AVVideoCompositionCoreAnimationTool), so what is seen is what is sent.
// The clip stays in Photos; the export is a temporary .mp4 for the share sheet.

enum VideoPostAspect: String, CaseIterable, Identifiable {
    case story, portrait, square
    var id: String { rawValue }
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 1080, height: 1920)
        case .portrait: CGSize(width: 1080, height: 1350)
        case .square: CGSize(width: 1080, height: 1080)
        }
    }
    var title: String {
        switch self {
        case .story: "9:16"
        case .portrait: "4:5"
        case .square: "1:1"
        }
    }
}

enum VideoPost {
    /// The longest piece a post takes.
    static let longest: Double = 60

    // MARK: The clip

    /// The video of a Photos asset (downloaded from iCloud when needed).
    static func asset(for asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { av, _, _ in
                continuation.resume(returning: av)
            }
        }
    }

    // MARK: The cut

    struct Cut {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let duration: Double
        let renderSize: CGSize
    }

    /// The clip from `start` for `length` seconds (at most a minute), filling
    /// the frame (centred crop), with its sound.
    static func cut(_ source: AVAsset, start: Double, length: Double, aspect: VideoPostAspect) async throws -> Cut {
        let render = aspect.size
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoPost", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video in this clip"])
        }
        let total = try await source.load(.duration).seconds
        let from = max(0, min(start, max(0, total - 0.5)))
        let span = max(0.5, min(length, longest, total - from))
        let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                duration: CMTime(seconds: span, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VideoPost", code: 2)
        }
        try track.insertTimeRange(range, of: video, at: .zero)
        if let audio = try await source.loadTracks(withMediaType: .audio).first,
           let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? a.insertTimeRange(range, of: audio, at: .zero)
        }

        let natural = try await video.load(.naturalSize)
        let preferred = try await video.load(.preferredTransform)
        let fps = try await video.load(.nominalFrameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(fill(natural: natural, preferred: preferred, into: render), at: .zero)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = render
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps > 0 && fps <= 60 ? fps.rounded() : 30))
        videoComposition.instructions = [instruction]
        return Cut(composition: composition, videoComposition: videoComposition, duration: span, renderSize: render)
    }

    /// The transform that turns the track upright and fills `render`, centred.
    static func fill(natural: CGSize, preferred: CGAffineTransform, into render: CGSize) -> CGAffineTransform {
        let oriented = CGRect(origin: .zero, size: natural).applying(preferred)
        let upright = preferred.concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
        let w = abs(oriented.width), h = abs(oriented.height)
        guard w > 0, h > 0 else { return preferred }
        let s = max(render.width / w, render.height / h)
        return upright
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: (render.width - w * s) / 2, y: (render.height - h * s) / 2))
    }

    // MARK: The export

    /// Writes the cut with its overlay burnt in to a temporary .mp4.
    static func export(_ cut: Cut, overlay: CALayer, name: String) async throws -> URL {
        let size = cut.renderSize
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        // The overlay is built top-left; the video compositor draws bottom-left.
        let holder = CALayer()
        holder.frame = parent.frame
        holder.isGeometryFlipped = true
        overlay.frame = parent.frame
        holder.addSublayer(overlay)
        parent.addSublayer(holder)

        let composition = cut.videoComposition.mutableCopy() as! AVMutableVideoComposition
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.replacingOccurrences(of: "/", with: "-")).mp4")
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: cut.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoPost", code: 3)
        }
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: url, as: .mp4)
        return url
    }
}

// MARK: - Animation helpers (shared by the overlay templates)

/// Keyframes on the clip's timeline, in seconds. Before the first key the
/// first value holds; after the last, the last.
struct VideoTrack {
    let duration: Double

    func animate(_ layer: CALayer, _ keyPath: String, _ keys: [(Double, Any)],
                 timing: CAMediaTimingFunctionName = .easeOut) {
        guard let first = keys.first else { return }
        let d = max(duration, 0.1)
        var times: [NSNumber] = []
        var values: [Any] = []
        // Hold the first value from zero.
        if first.0 > 0 { times.append(0); values.append(first.1) }
        for (t, v) in keys {
            times.append(NSNumber(value: min(max(t / d, 0), 1)))
            values.append(v)
        }
        if (keys.last?.0 ?? 0) < d { times.append(1); values.append(keys.last!.1) }
        // Times must not go backwards.
        for i in 1..<times.count where times[i].doubleValue < times[i - 1].doubleValue { times[i] = times[i - 1] }
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: timing), count: max(values.count - 1, 1))
        a.duration = d
        a.beginTime = AVCoreAnimationBeginTimeAtZero
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        a.calculationMode = .linear
        layer.add(a, forKey: keyPath + ".\(layer.animationKeys()?.count ?? 0)")
    }

    /// A run of images shown one after another from `start`, `step` seconds
    /// apart (a number counting up, words typing).
    func frames(_ layer: CALayer, _ images: [CGImage], start: Double, step: Double) {
        guard !images.isEmpty else { return }
        let d = max(duration, 0.1)
        var times: [NSNumber] = [0]
        var values: [Any] = [images[0]]
        for (i, img) in images.enumerated() {
            times.append(NSNumber(value: min((start + Double(i) * step) / d, 1)))
            values.append(img)
        }
        // Discrete keyframes take one more time than values.
        times.append(1)
        for i in 1..<times.count where times[i].doubleValue < times[i - 1].doubleValue { times[i] = times[i - 1] }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = values
        a.keyTimes = times
        a.calculationMode = .discrete
        a.duration = d
        a.beginTime = AVCoreAnimationBeginTimeAtZero
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: "contents")
        layer.contents = images.last
    }
}
