import Foundation
import CoreGraphics

// MARK: - Court Projection
//
// THE single composition point where the camera homography meets
// CourtTransform. Screen, PDF, and video renderers all go through this type —
// if each grew its own camera maths they would drift, and a play authored on
// screen would not match its own export.
//
// The camera is a perspective projection of the court PLANE, not a 3D scene.
// Source of truth stays 2D court-feet; tilt is one animatable parameter.
//
// Elevation is in DEGREES, matching PlayDiagram.camera:
//   90 = straight down (plan view). The projection degenerates to the plain
//        affine CourtTransform, exactly.
//    0 = at floor level (degenerate; clamped well before this).

/// A named colour scheme. Print and video want opposite palettes: a sheet
/// handed to a team on white paper wants a light floor with dark lines; video
/// wants white line work on a dark floor. Stored on the diagram and selectable
/// per export.
struct CourtTheme: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    /// Hex strings so the theme survives in the Codable JSON blob without
    /// dragging a UI colour type into the model layer.
    var floorHex: String
    var paintHex: String
    var lineHex: String
    var offenseHex: String
    var defenseHex: String
    var ballHex: String
    var labelHex: String

    /// White line work on a dark floor.
    static let video = CourtTheme(
        name: "Video",
        floorHex: "#232B3A", paintHex: "#33445F", lineHex: "#FFFFFF",
        offenseHex: "#34A0F7", defenseHex: "#F05C4F", ballHex: "#FF9F0A",
        labelHex: "#FFFFFF")

    /// Dark line work on a light floor, for paper.
    static let print = CourtTheme(
        name: "Print",
        floorHex: "#FFFFFF", paintHex: "#ECEFF4", lineHex: "#1C1C1E",
        offenseHex: "#1B4F9C", defenseHex: "#A32820", ballHex: "#C05600",
        labelHex: "#FFFFFF")

    static let all: [CourtTheme] = [.video, .print]
}

/// Tunable look parameters for the oblique camera.
///
/// Deliberately NOT baked into CourtProjection. These are look decisions the
/// coach iterates on while watching output, and each iteration should not be a
/// code edit and a rebuild. Defaults are the values the projection shipped
/// with; freeze them here once the numbers settle.
struct CourtLookParameters: Codable, Hashable {
    /// How much the far end converges at full tilt. Higher is more dramatic.
    var maxConvergence: CGFloat
    /// Depth compression at full tilt. Lower shrinks the far end more.
    var minDepthScale: CGFloat
    /// Lowest camera elevation allowed, in degrees. Below roughly 20 the
    /// inverse degrades near the horizon and the diagram stops being usable
    /// for placement.
    var minElevationDegrees: Double
    /// Pass speed in FEET PER SECOND. Ball flight duration is derived from
    /// distance / speed rather than keyframed, so this is the constant that
    /// sets how snappy passes feel. Tunable against real playback.
    var passSpeedFeetPerSecond: Double
    /// Shot speed in feet per second. Slower than a pass, and rendered as a
    /// shallow parabola toward the rim.
    var shotSpeedFeetPerSecond: Double
    /// How far BESIDE the holder the ball sits, in court feet. On his centre it
    /// hides him; roughly a puck radius out and both read clearly.
    var ballHeldOffsetFeet: CGFloat
    /// Colour scheme.
    var theme: CourtTheme
    /// Labels never render smaller than this, in POINTS.
    ///
    /// Billboarding fixes orientation, not size. At 35° a far-baseline player
    /// sits at 68% depth scale, so an unclamped 11pt number lands near 7pt and
    /// is unreadable in a 1080p export — which you would only discover after
    /// rendering a sequence.
    var minLabelPointSize: CGFloat

    init(maxConvergence: CGFloat = 0.55,
         minDepthScale: CGFloat = 0.45,
         minElevationDegrees: Double = 25,
         minLabelPointSize: CGFloat = 9,
         passSpeedFeetPerSecond: Double = 34,
         shotSpeedFeetPerSecond: Double = 26,
         ballHeldOffsetFeet: CGFloat = 1.9,
         theme: CourtTheme = .video) {
        self.maxConvergence = maxConvergence
        self.minDepthScale = minDepthScale
        self.minElevationDegrees = minElevationDegrees
        self.minLabelPointSize = minLabelPointSize
        self.passSpeedFeetPerSecond = passSpeedFeetPerSecond
        self.shotSpeedFeetPerSecond = shotSpeedFeetPerSecond
        self.ballHeldOffsetFeet = ballHeldOffsetFeet
        self.theme = theme
    }

    static let `default` = CourtLookParameters()
}

/// Court feet ⇄ view points, with optional perspective tilt.
///
/// Exactly invertible. Every drag, placement, and hit test in the editor goes
/// through `unproject`, so an approximate inverse would show up immediately as
/// entities landing where the coach did not drop them.
struct CourtProjection {
    let transform: CourtTransform
    /// Camera elevation in degrees. 90 is plan view.
    let elevationDegrees: Double
    /// Court extent, needed to normalise before the homography.
    let space: CourtSpace
    /// Tunable look parameters.
    let look: CourtLookParameters

    /// How much the far end converges. 0 at plan view. Kept below 1 so the
    /// divisor `1 + k·v` never approaches zero and the inverse stays stable.
    private let k: CGFloat
    /// Depth compression along the court's length.
    private let s: CGFloat

    init(transform: CourtTransform,
         space: CourtSpace,
         elevationDegrees: Double,
         look: CourtLookParameters = .default) {
        self.transform = transform
        self.space = space
        self.look = look
        let floorAngle = min(max(look.minElevationDegrees, 5), 89)
        let clamped = min(max(elevationDegrees, floorAngle), 90)
        self.elevationDegrees = clamped
        // 0 at plan view, 1 at the configured minimum elevation.
        let span = max(90 - floorAngle, 1)
        let tilt = CGFloat((90 - clamped) / span)
        self.k = tilt * look.maxConvergence
        self.s = 1 - tilt * (1 - look.minDepthScale)
    }

    /// True when the camera is at plan view and the mapping is purely affine.
    var isPlanView: Bool { k == 0 && s == 1 }

    // MARK: - Forward

    /// Court feet → view points.
    func project(_ courtPoint: CGPoint) -> CGPoint {
        guard !isPlanView else { return transform.point(courtPoint) }

        let (u, v) = normalise(courtPoint)
        let w = 1 + k * v
        let projectedU = u / w
        let projectedV = (v * s) / w
        return denormalise(u: projectedU, v: projectedV)
    }

    /// View points → court feet. The exact inverse of `project`.
    ///
    /// Derivation: v' = v·s / (1 + k·v)  ⟹  v = v' / (s − k·v'), and
    /// u = u'·(1 + k·v). Closed form, no iteration.
    func unproject(_ viewPoint: CGPoint) -> CGPoint {
        guard !isPlanView else { return transform.inverse(viewPoint) }

        let (projectedU, projectedV) = normaliseView(viewPoint)
        let denominator = s - k * projectedV
        // Behind the horizon: nothing on the floor maps here.
        guard abs(denominator) > 1e-6 else {
            return CGPoint(x: space.width / 2, y: space.length)
        }
        let v = projectedV / denominator
        let u = projectedU * (1 + k * v)
        return denormaliseToCourt(u: u, v: v)
    }

    // MARK: - Depth

    /// Scale factor for a BILLBOARDED mark at this court point.
    ///
    /// Player pucks are drawn upright at their projected ground point and
    /// scaled by this, never pushed through the homography — a circle through a
    /// perspective transform shears into a wrong-looking ellipse. The cast
    /// shadow is the projected ellipse; the puck is not.
    func depthScale(at courtPoint: CGPoint) -> CGFloat {
        guard !isPlanView else { return 1 }
        let (_, v) = normalise(courtPoint)
        return 1 / (1 + k * v)
    }

    /// Rendered size for a label at this court point, floored for legibility.
    ///
    /// Pucks scale with depth; text stops shrinking at
    /// `look.minLabelPointSize`. A far-side number that follows depth all the
    /// way down is correct perspective and useless film.
    func labelPointSize(base: CGFloat, at courtPoint: CGPoint) -> CGFloat {
        max(look.minLabelPointSize, base * depthScale(at: courtPoint))
    }

    /// Painter's-algorithm ordering key: larger draws later (nearer the front).
    func depthOrder(of courtPoint: CGPoint) -> CGFloat {
        -courtPoint.y
    }

    // MARK: - Paths

    /// Projects a whole path, flattening curves so the perspective is applied
    /// per point.
    ///
    /// A homography maps straight lines to straight lines but circles to
    /// conics, so an arc cannot be transformed by matrix alone. Flattening to
    /// short segments keeps the output VECTOR — which is what PDF export
    /// requires — while being geometrically correct.
    func project(path: CGPath, flatness: CGFloat = 0.6) -> CGPath {
        guard !isPlanView else {
            var affine = transform.affine
            return path.copy(using: &affine) ?? path
        }

        let output = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero

        func lineTo(_ courtPoint: CGPoint) {
            output.addLine(to: project(courtPoint))
        }

        /// Subdivision count scaled to the on-screen length of the segment.
        func steps(_ a: CGPoint, _ b: CGPoint) -> Int {
            let approx = hypot(b.x - a.x, b.y - a.y) * transform.scale
            return max(2, min(48, Int(approx / max(flatness, 0.1))))
        }

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
                start = current
                output.move(to: project(current))

            case .addLineToPoint:
                let end = element.points[0]
                // Straight in court space stays straight under a homography,
                // so no subdivision is needed here.
                lineTo(end)
                current = end

            case .addQuadCurveToPoint:
                let control = element.points[0], end = element.points[1]
                let n = steps(current, end)
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n)
                    let mt = 1 - t
                    // Split out: the single-expression form exceeded the type
                    // checker's budget.
                    let a: CGFloat = mt * mt
                    let b: CGFloat = 2 * mt * t
                    let c: CGFloat = t * t
                    let px: CGFloat = a * current.x + b * control.x + c * end.x
                    let py: CGFloat = a * current.y + b * control.y + c * end.y
                    lineTo(CGPoint(x: px, y: py))
                }
                current = end

            case .addCurveToPoint:
                let c1 = element.points[0], c2 = element.points[1], end = element.points[2]
                let n = steps(current, end)
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n)
                    let mt = 1 - t
                    let a: CGFloat = mt * mt * mt
                    let b: CGFloat = 3 * mt * mt * t
                    let c: CGFloat = 3 * mt * t * t
                    let d: CGFloat = t * t * t
                    let px: CGFloat = a * current.x + b * c1.x + c * c2.x + d * end.x
                    let py: CGFloat = a * current.y + b * c1.y + c * c2.y + d * end.y
                    lineTo(CGPoint(x: px, y: py))
                }
                current = end

            case .closeSubpath:
                output.closeSubpath()
                current = start

            @unknown default:
                break
            }
        }
        return output
    }

    // MARK: - Normalisation

    /// Court feet → u ∈ [-0.5, 0.5] across width, v ∈ [0, 1] along length.
    private func normalise(_ point: CGPoint) -> (CGFloat, CGFloat) {
        (point.x / space.width - 0.5, point.y / max(space.length, 1))
    }

    private func denormalise(u: CGFloat, v: CGFloat) -> CGPoint {
        transform.point(CGPoint(x: (u + 0.5) * space.width,
                                y: v * space.length))
    }

    private func normaliseView(_ viewPoint: CGPoint) -> (CGFloat, CGFloat) {
        let court = transform.inverse(viewPoint)
        return (court.x / space.width - 0.5, court.y / max(space.length, 1))
    }

    private func denormaliseToCourt(u: CGFloat, v: CGFloat) -> CGPoint {
        CGPoint(x: (u + 0.5) * space.width, y: v * space.length)
    }
}
