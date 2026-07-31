import Foundation
import CoreGraphics

// MARK: - Render Style
//
// One struct owns every visual decision, so a style is DATA — the published
// video look ships as a preset, export presets can carry their own styles
// later, and no style logic hides in entity code.
//
// Two presets:
//   .edit          authoring look — numbered pucks, full paths always visible,
//                  dashed/wavy semantic conventions. You need the whole play
//                  at once while building it.
//   .presentation  the published video look — soft terracotta brush, flat
//                  yellow discs, black court, and paths that live AHEAD of
//                  motion only.
struct RenderStyle: Equatable {
    var name: String

    // Paths ("the brush")
    /// Stroke colour. Terracotta clay in presentation, sampled from the
    /// published renders.
    var pathStrokeHex: String
    /// Stroke width as a fraction of the player puck DIAMETER. Uniform along
    /// the path.
    var pathWidthPuckFactor: CGFloat
    /// Gaussian blur radius as a fraction of stroke width — the
    /// painted-with-a-soft-brush edge. Blur applies to the PATH LAYER only,
    /// never players, ball, or court lines, and always AFTER trimming so the
    /// consumed edge stays soft.
    var pathBlurFactor: CGFloat
    /// One uniform brush for cut/dribble/screen. The semantic distinction
    /// stays in the data model; dashed/wavy conventions belong to the edit
    /// overlay only. The travelling ball is what reads as a pass.
    var uniformBrush: Bool
    /// Chunky hooked V drawn as two strokes in the same brush — not a filled
    /// geometric triangle.
    var hookedArrowhead: Bool

    // Path consumption
    /// Paths render only AHEAD of motion — an announcement of where the player
    /// is going. Never a trail.
    var consumeBehindMotion: Bool
    /// Draw-on begins this many seconds before the segment's motion starts…
    var drawOnLead: Double
    /// …and takes this long, tip-first.
    var drawOnDuration: Double
    /// The trailing edge tucks this many FEET behind the player — about half a
    /// puck radius — so the stroke appears to be consumed by the puck. Feet,
    /// not seconds: a time-based tuck stretches with velocity, and at an
    /// easeInOut peak the tail escaped the puck entirely.
    var trailingTuckFeet: CGFloat

    // Entities
    var playerFillHex: String
    var showPlayerNumbers: Bool
    var playerStroke: Bool
    var ballHex: String
    /// Ball diameter as a fraction of player diameter.
    var ballScaleFactor: CGFloat

    // Court
    /// Nil means "use the diagram's CourtTheme" (edit style); a value overrides
    /// (presentation forces black floor / white lines).
    var courtFloorHex: String?
    var courtLineHex: String?

    /// Ghost trails are an authoring aid; a trail contradicts the
    /// presentation rule that nothing renders behind motion.
    var allowsGhostTrails: Bool

    static let edit = RenderStyle(
        name: "Edit",
        pathStrokeHex: "",              // edit paths use entity colours
        pathWidthPuckFactor: 0,         // edit uses its own thin semantic strokes
        pathBlurFactor: 0,
        uniformBrush: false,
        hookedArrowhead: false,
        consumeBehindMotion: false,
        drawOnLead: 0, drawOnDuration: 0, trailingTuckFeet: 0,
        playerFillHex: "",              // team colours from the theme
        showPlayerNumbers: true,
        playerStroke: true,
        ballHex: "",
        ballScaleFactor: 0.68,
        courtFloorHex: nil,
        courtLineHex: nil,
        allowsGhostTrails: true)

    static let presentation = RenderStyle(
        name: "Presentation",
        pathStrokeHex: "#A76458",       // terracotta clay, sampled
        pathWidthPuckFactor: 0.6,
        pathBlurFactor: 0.35,
        uniformBrush: true,
        hookedArrowhead: true,
        consumeBehindMotion: true,
        drawOnLead: 0.3, drawOnDuration: 0.25, trailingTuckFeet: 0.8,
        playerFillHex: "#FFFF70",
        showPlayerNumbers: false,
        playerStroke: false,
        ballHex: "#FE1A2C",
        ballScaleFactor: 0.4,
        courtFloorHex: "#000000",
        courtLineHex: "#FFFFFF",
        allowsGhostTrails: false)
}

// MARK: - Path Consumption
//
// Pure functions of t: visibility is stateless, so scrubbing backward regrows
// a consumed path correctly by construction.
enum PathConsumption {

    /// What remains visible of one movement segment at local time `t`.
    struct VisibleSegment {
        var points: [CGPoint]
        /// Where the head (arrow / T-bar) sits. During draw-on it rides the
        /// leading tip; during motion it waits at the destination; it vanishes
        /// with the final portion.
        var headAt: CGPoint
        var headAngle: CGFloat
    }

    /// Segment between keyframes `from`→`to` on `track`, at node-local `t`.
    ///
    /// Phases:
    ///   t < appearStart                       nothing (no path before its time)
    ///   appearStart ≤ t < segStart            draw-on, tip-first
    ///   segStart ≤ t < segEnd                 consumed: only [t-tuck, end] ahead
    ///   t ≥ segEnd                            nothing (fully consumed)
    static func visibleSegment(track: Track,
                               from: Keyframe,
                               to: Keyframe,
                               at t: Double,
                               style: RenderStyle,
                               readStart: Double = 0,
                               samples: Int = 26) -> VisibleSegment? {
        guard style.consumeBehindMotion else {
            return fullSegment(track: track, from: from, to: to, samples: samples)
        }
        let segStart = from.t
        let segEnd = to.t
        guard segEnd > segStart else { return nil }
        let appearStart = max(readStart, segStart - style.drawOnLead)
        guard t >= appearStart, t < segEnd else { return nil }

        let visibleRange: ClosedRange<Double>
        if t < segStart {
            // Draw-on: reveal from the player's start outward — the leading
            // tip paints the path.
            let fraction = min(1, max(0.02, (t - appearStart) / max(style.drawOnDuration, 0.01)))
            visibleRange = segStart...(segStart + fraction * (segEnd - segStart))
        } else {
            // Consumption: only what lies ahead. The tail tucks a fixed
            // DISTANCE behind the player, walked backwards along the actual
            // trajectory, so the tuck is constant regardless of speed.
            var tail = t
            if style.trailingTuckFeet > 0, var here = track.position(at: t) {
                var travelled: CGFloat = 0
                let step = 0.01
                var guardCount = 0
                while travelled < style.trailingTuckFeet, tail - step >= segStart,
                      guardCount < 60 {
                    tail -= step
                    guardCount += 1
                    if let back = track.position(at: tail) {
                        travelled += hypot(back.x - here.x, back.y - here.y)
                        here = back
                    }
                }
            }
            tail = max(segStart, tail)
            guard t < segEnd else { return nil }
            visibleRange = tail...segEnd
        }

        var points: [CGPoint] = []
        let count = max(2, samples)
        for step in 0...count {
            let time = visibleRange.lowerBound
                + (visibleRange.upperBound - visibleRange.lowerBound)
                * Double(step) / Double(count)
            if let point = track.position(at: time) { points.append(point) }
        }
        guard points.count > 1 else { return nil }
        let last = points[points.count - 1]
        let previous = points[points.count - 2]
        return VisibleSegment(points: points,
                              headAt: last,
                              headAngle: atan2(last.y - previous.y, last.x - previous.x))
    }

    /// The head belongs to the TRACK, not a segment: it sits at the
    /// destination, oriented to the final tangent, and is visible whenever any
    /// portion of the path is — disappearing with the last consumed piece.
    /// Gating it to the final segment's own window left mid-path frames with
    /// no direction cue at all.
    static func trackHead(track: Track, at t: Double,
                          style: RenderStyle) -> (at: CGPoint, angle: CGFloat)? {
        let frames = track.sortedKeyframes
        guard frames.count > 1, let last = frames.last else { return nil }
        // Any segment visible?
        var anyVisible = false
        for index in 0..<(frames.count - 1) {
            if visibleSegment(track: track, from: frames[index], to: frames[index + 1],
                              at: t, style: style, samples: 4) != nil {
                anyVisible = true
                break
            }
        }
        guard anyVisible else { return nil }
        let beforeEnd = track.position(at: last.t - 0.06) ?? last.position
        let angle = atan2(last.position.y - beforeEnd.y, last.position.x - beforeEnd.x)
        return (last.position, angle)
    }

    private static func fullSegment(track: Track, from: Keyframe, to: Keyframe,
                                    samples: Int) -> VisibleSegment? {
        var points: [CGPoint] = []
        for step in 0...samples {
            let time = from.t + (to.t - from.t) * Double(step) / Double(samples)
            if let point = track.position(at: time) { points.append(point) }
        }
        guard points.count > 1 else { return nil }
        let last = points[points.count - 1]
        let previous = points[points.count - 2]
        return VisibleSegment(points: points,
                              headAt: last,
                              headAngle: atan2(last.y - previous.y, last.x - previous.x))
    }
}
