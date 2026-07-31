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

    /// How much the far end converges. 0 at plan view. Kept below 1 so the
    /// divisor `1 + k·v` never approaches zero and the inverse stays stable.
    private let k: CGFloat
    /// Depth compression along the court's length.
    private let s: CGFloat

    /// Maximum convergence at full tilt. Chosen for the oblique broadcast look
    /// rather than physical accuracy — this is a diagram, not a simulation.
    private static let maxConvergence: CGFloat = 0.55
    /// Depth compression at full tilt.
    private static let minDepthScale: CGFloat = 0.45

    init(transform: CourtTransform, space: CourtSpace, elevationDegrees: Double) {
        self.transform = transform
        self.space = space
        // Clamp: below ~25° the projection is unusable for diagramming and the
        // inverse gets numerically nasty near the horizon.
        let clamped = min(max(elevationDegrees, 25), 90)
        self.elevationDegrees = clamped
        let tilt = CGFloat((90 - clamped) / 65)   // 0 at plan view, 1 at 25°
        self.k = tilt * Self.maxConvergence
        self.s = 1 - tilt * (1 - Self.minDepthScale)
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
