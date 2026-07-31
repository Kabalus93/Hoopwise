import Foundation
import CoreGraphics

/// Movement-line geometry in COURT FEET.
///
/// Arrowheads and screen T-bars lie on the FLOOR PLANE, so they are built here
/// in court feet and projected through the homography exactly like court
/// markings. Only pucks, numbers and labels are billboarded. Building an
/// arrowhead in view space would leave arrows floating above an oblique court.
///
/// Coaching convention:
///   run / cut  solid line, arrowhead
///   dribble    wavy line, arrowhead
///   pass       dashed line, arrowhead
///   screen     solid line ending in a perpendicular T bar, NO arrowhead
enum MovementGeometry {

    // Head sizes in COURT FEET, so they scale with the court and shrink with
    // depth under projection rather than staying a fixed pixel size. Sized
    // relative to a ~2ft player puck: an arrowhead as long as a player is
    // wide reads as oversized, which is what it looked like at 2.0ft.
    static let arrowLengthFeet: CGFloat = 1.15
    static let arrowHalfWidthFeet: CGFloat = 0.5
    static let screenBarHalfWidthFeet: CGFloat = 1.5
    /// Wave amplitude and period for the dribble line, in feet.
    static let waveAmplitudeFeet: CGFloat = 0.6
    static let wavePeriodFeet: CGFloat = 2.4

    /// The line itself, with dribble rendered as an actual wave rather than a
    /// dash pattern — a wavy line is the convention, and a dash is a pass.
    static func line(points: [CGPoint], kind: PathKind) -> CGPath {
        guard points.count > 1 else { return CGMutablePath() }
        switch kind {
        case .dribble: return wavy(points)
        default:       return polyline(points)
        }
    }

    /// The head: arrow for movement kinds, T bar for a screen, nothing else.
    static func head(points: [CGPoint], kind: PathKind) -> CGPath? {
        guard points.count > 1 else { return nil }
        let end = points[points.count - 1]
        let previous = points[points.count - 2]
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        switch kind {
        case .screen: return screenBar(at: end, angle: angle)
        default:      return arrowHead(at: end, angle: angle)
        }
    }

    /// True when the head should be filled rather than stroked.
    static func headIsFilled(_ kind: PathKind) -> Bool { kind != .screen }

    // MARK: - Builders

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// Sine wave along the polyline, offset perpendicular to local direction.
    private static func wavy(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        var travelled: CGFloat = 0
        var output: [CGPoint] = []

        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let dx: CGFloat = b.x - a.x
            let dy: CGFloat = b.y - a.y
            let length: CGFloat = (dx * dx + dy * dy).squareRoot()
            guard length > 0.0001 else { continue }
            let nx: CGFloat = -dy / length
            let ny: CGFloat = dx / length
            let steps = max(2, Int(length / 0.3))
            for step in 0...steps {
                let f = CGFloat(step) / CGFloat(steps)
                let px: CGFloat = a.x + dx * f
                let py: CGFloat = a.y + dy * f
                let phase: CGFloat = (travelled + length * f) / wavePeriodFeet * .pi * 2
                let offset: CGFloat = sin(phase) * waveAmplitudeFeet
                output.append(CGPoint(x: px + nx * offset, y: py + ny * offset))
            }
            travelled += length
        }
        guard let first = output.first else { return path }
        path.move(to: first)
        for point in output.dropFirst() { path.addLine(to: point) }
        return path
    }

    private static func arrowHead(at tip: CGPoint, angle: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let backX: CGFloat = tip.x - cos(angle) * arrowLengthFeet
        let backY: CGFloat = tip.y - sin(angle) * arrowLengthFeet
        let px: CGFloat = -sin(angle) * arrowHalfWidthFeet
        let py: CGFloat = cos(angle) * arrowHalfWidthFeet
        path.move(to: tip)
        path.addLine(to: CGPoint(x: backX + px, y: backY + py))
        path.addLine(to: CGPoint(x: backX - px, y: backY - py))
        path.closeSubpath()
        return path
    }

    /// Filled chevron head for the presentation brush.
    ///
    /// A SOLID shape survives blur; the two-stroke hooked V smeared into a
    /// directionless blob under the gaussian pass. Closed wedge with a concave
    /// back (chevron, not plain triangle), sized from the stroke width so it
    /// scales with the brush: length ~2.35x stroke width, splay ~60 degrees.
    /// Corners are rounded by the caller filling AND stroking with round joins.
    static func filledChevronHead(at tip: CGPoint, angle: CGFloat,
                                  strokeWidthFeet: CGFloat) -> CGPath {
        let length = strokeWidthFeet * 2.35
        let splay: CGFloat = 30 * .pi / 180        // half of ~60 degrees
        let back = CGPoint(x: tip.x - cos(angle) * length,
                           y: tip.y - sin(angle) * length)
        let leftAngle = angle + .pi - splay
        let rightAngle = angle + .pi + splay
        let left = CGPoint(x: tip.x + cos(leftAngle) * length,
                           y: tip.y + sin(leftAngle) * length)
        let right = CGPoint(x: tip.x + cos(rightAngle) * length,
                            y: tip.y + sin(rightAngle) * length)
        // Concave back point sits partway toward the tip, making the chevron.
        let notch = CGPoint(x: tip.x - cos(angle) * length * 0.55,
                            y: tip.y - sin(angle) * length * 0.55)
        _ = back
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: notch)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    /// Hooked V arrowhead for the presentation brush: two strokes meeting at
    /// the tip, slightly asymmetric, STROKED in the same soft brush — not a
    /// filled geometric triangle. Sized in court feet like everything else.
    static func hookedHead(at tip: CGPoint, angle: CGFloat,
                           lengthFeet: CGFloat = 1.5) -> CGPath {
        let path = CGMutablePath()
        // Slight asymmetry keeps it hand-drawn rather than geometric.
        let left = angle + .pi - 0.52
        let right = angle + .pi + 0.60
        path.move(to: CGPoint(x: tip.x + cos(left) * lengthFeet,
                              y: tip.y + sin(left) * lengthFeet))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x + cos(right) * lengthFeet * 0.85,
                                 y: tip.y + sin(right) * lengthFeet * 0.85))
        return path
    }

    /// T-bar for the presentation brush; crossbar length passed in feet so the
    /// caller can size it at ~2x the stroke width.
    static func brushScreenBar(at point: CGPoint, angle: CGFloat,
                               halfWidthFeet: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let px = -sin(angle) * halfWidthFeet
        let py = cos(angle) * halfWidthFeet
        path.move(to: CGPoint(x: point.x + px, y: point.y + py))
        path.addLine(to: CGPoint(x: point.x - px, y: point.y - py))
        return path
    }

    /// Perpendicular bar at the screen point — the convention for "screen set
    /// here", deliberately without an arrowhead.
    private static func screenBar(at point: CGPoint, angle: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let px: CGFloat = -sin(angle) * screenBarHalfWidthFeet
        let py: CGFloat = cos(angle) * screenBarHalfWidthFeet
        path.move(to: CGPoint(x: point.x + px, y: point.y + py))
        path.addLine(to: CGPoint(x: point.x - px, y: point.y - py))
        return path
    }
}
