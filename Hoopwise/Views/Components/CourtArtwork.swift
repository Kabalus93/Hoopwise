import SwiftUI

// Header court artwork (12 November 2026, Luther: the old header court was
// "inaccurate … the lines are messy" — its lane, circle and arc were each
// scaled to the card's width OR height, so every card stretched the court
// differently). Drawn in METRES on a FIBA court (28 × 15 m) and pushed
// through one projection, so the proportions are always true; each session
// type gets its own angle and design:
//
//   training      half court from above, the basket at the bottom
//   scrimmage     the full court from above
//   gamePrep      a tactics board — half court, basket at the top, a set
//                 drawn on it (O's, a pass, a cut, X's)
//   recovery      the centre circle up close, calm rings around it
//   assessment    half court with the shooting test spots and lane marks
//   teamPractice  half court in perspective, the broadcast angle from half
//                 court toward the basket
//
// Lines are hairlines that fade out toward the leading edge, where the
// header's text sits.

enum CourtArtStyle: String, CaseIterable {
    case halfCourt, fullCourt, tacticsBoard, centreCircle, testSpots, broadcast

    init(_ type: SessionType) {
        switch type {
        case .training: self = .halfCourt
        case .scrimmage: self = .fullCourt
        case .gamePrep: self = .tacticsBoard
        case .recovery: self = .centreCircle
        case .assessment: self = .testSpots
        case .teamPractice: self = .broadcast
        }
    }
}

/// FIBA court measurements, metres. x runs from a baseline along the court
/// (0…28), y across it from the centre line of the court's width (−7.5…7.5).
private enum FIBA {
    static let length = 28.0, width = 15.0, half = 14.0
    static let basket = 1.575          // basket centre from the baseline
    static let backboard = 1.2, backboardWidth = 1.8
    static let rimRadius = 0.225
    static let laneWidth = 4.9, laneLength = 5.8
    static let circleRadius = 1.8      // free-throw and centre circles
    static let threeRadius = 6.75, threeCorner = 6.6
    static let restricted = 1.25
    /// Where the corner three's straight line meets the arc.
    static var threeStraightEnd: Double { basket + (threeRadius * threeRadius - threeCorner * threeCorner).squareRoot() }
}

struct CourtArtwork: View {
    let style: CourtArtStyle
    var lineOpacity: Double = 0.2

    var body: some View {
        Canvas { ctx, size in
            let project = projection(for: style, in: size)
            var lines = Path()
            var dashed = Path()
            var marks = Path()     // filled: spots, rim, players
            var text: [(String, CGPoint)] = []

            func line(_ a: (Double, Double), _ b: (Double, Double), into p: inout Path) {
                p.move(to: project(a.0, a.1)); p.addLine(to: project(b.0, b.1))
            }
            /// A polyline through the projection, so arcs bend correctly in
            /// perspective too.
            func arc(cx: Double, cy: Double, r: Double, from a0: Double, to a1: Double, into p: inout Path) {
                let steps = max(12, Int(abs(a1 - a0) / 4))
                for i in 0...steps {
                    let a = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
                    let pt = project(cx + r * cos(a), cy + r * sin(a))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            /// One end of the court; `end` 0 = baseline at x 0, 1 = at x 28.
            func halfCourt(end: Int, lanes: Bool = false) {
                let s: Double = end == 0 ? 1 : -1
                let b = end == 0 ? 0.0 : FIBA.length
                func X(_ d: Double) -> Double { b + s * d }
                let lw = FIBA.laneWidth / 2
                // Lane and free-throw line.
                line((X(0), -lw), (X(FIBA.laneLength), -lw), into: &lines)
                line((X(0), lw), (X(FIBA.laneLength), lw), into: &lines)
                line((X(FIBA.laneLength), -lw), (X(FIBA.laneLength), lw), into: &lines)
                // Free-throw circle: solid outside the lane, dashed inside.
                let ftAngle: Double = end == 0 ? 0 : 180
                arc(cx: X(FIBA.laneLength), cy: 0, r: FIBA.circleRadius, from: ftAngle - 90, to: ftAngle + 90, into: &lines)
                arc(cx: X(FIBA.laneLength), cy: 0, r: FIBA.circleRadius, from: ftAngle + 90, to: ftAngle + 270, into: &dashed)
                // Three-point line: corner straights, then the arc.
                let straight = FIBA.threeStraightEnd
                line((X(0), -FIBA.threeCorner), (X(straight), -FIBA.threeCorner), into: &lines)
                line((X(0), FIBA.threeCorner), (X(straight), FIBA.threeCorner), into: &lines)
                let cornerAngle = atan2(FIBA.threeCorner, straight - FIBA.basket) * 180 / .pi
                if end == 0 {
                    arc(cx: X(FIBA.basket), cy: 0, r: FIBA.threeRadius, from: -cornerAngle, to: cornerAngle, into: &lines)
                } else {
                    arc(cx: X(FIBA.basket), cy: 0, r: FIBA.threeRadius, from: 180 - cornerAngle, to: 180 + cornerAngle, into: &lines)
                }
                // No-charge semicircle, backboard, rim.
                arc(cx: X(FIBA.basket), cy: 0, r: FIBA.restricted, from: ftAngle - 90, to: ftAngle + 90, into: &lines)
                line((X(FIBA.backboard), -FIBA.backboardWidth / 2), (X(FIBA.backboard), FIBA.backboardWidth / 2), into: &lines)
                arc(cx: X(FIBA.basket), cy: 0, r: FIBA.rimRadius, from: 0, to: 360, into: &lines)
                if lanes {
                    // Lane positioning marks (FIBA: 1.75 m from the baseline,
                    // then 0.85, 0.40 neutral, 0.85, 0.85).
                    for d in [1.75, 2.6, 3.0, 3.85, 4.7] {
                        line((X(d), -lw), (X(d), -lw - 0.1), into: &lines)
                        line((X(d), lw), (X(d), lw + 0.1), into: &lines)
                    }
                }
            }
            func boundary(fromX x0: Double, toX x1: Double) {
                let w = FIBA.width / 2
                line((x0, -w), (x1, -w), into: &lines)
                line((x0, w), (x1, w), into: &lines)
                line((x0, -w), (x0, w), into: &lines)
                if x1 >= FIBA.length { line((x1, -w), (x1, w), into: &lines) }
            }
            func spot(_ x: Double, _ y: Double, r: CGFloat) {
                let c = project(x, y)
                marks.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }

            switch style {
            case .broadcast:
                // The camera stands over the top of the key, so only what
                // lies in front of it is drawn.
                boundary(fromX: 0, toX: 9.4)
                halfCourt(end: 0)
            case .halfCourt, .tacticsBoard, .testSpots:
                boundary(fromX: 0, toX: FIBA.half)
                line((FIBA.half, -FIBA.width / 2), (FIBA.half, FIBA.width / 2), into: &lines)
                arc(cx: FIBA.half, cy: 0, r: FIBA.circleRadius, from: 90, to: 270, into: &lines)
                halfCourt(end: 0, lanes: style == .testSpots)
            case .fullCourt:
                boundary(fromX: 0, toX: FIBA.length)
                line((FIBA.half, -FIBA.width / 2), (FIBA.half, FIBA.width / 2), into: &lines)
                arc(cx: FIBA.half, cy: 0, r: FIBA.circleRadius, from: 0, to: 360, into: &lines)
                halfCourt(end: 0)
                halfCourt(end: 1)
            case .centreCircle:
                line((FIBA.half, -FIBA.width / 2), (FIBA.half, FIBA.width / 2), into: &lines)
                arc(cx: FIBA.half, cy: 0, r: FIBA.circleRadius, from: 0, to: 360, into: &lines)
                for r in [3.2, 4.8, 6.6] {
                    arc(cx: FIBA.half, cy: 0, r: r, from: 0, to: 360, into: &dashed)
                }
            }

            if style == .testSpots {
                // Shooting test: five spots on the arc, five mid-range, the
                // free-throw spot.
                for a in [-90.0, -45, 0, 45, 90] {
                    let rad = a * .pi / 180
                    let r3 = a == -90 || a == 90 ? FIBA.threeCorner + 0.3 : FIBA.threeRadius + 0.3
                    let x3 = a == -90 || a == 90 ? 1.2 : FIBA.basket + r3 * cos(rad)
                    let y3 = a == -90 ? -r3 : a == 90 ? r3 : r3 * sin(rad)
                    spot(x3, y3, r: 3.5)
                    spot(FIBA.basket + 4.2 * cos(rad), 4.2 * sin(rad), r: 2.5)
                }
                spot(FIBA.laneLength, 0, r: 2.5)
            }

            if style == .tacticsBoard {
                // A set on the board: 1 at the top passes to 2 on the wing,
                // 5 screens, 3 cuts baseline; X's guard 1 and 2.
                let o: [(String, Double, Double)] = [("1", 8.4, 0.6), ("2", 6.2, -5.0), ("3", 1.2, -6.2), ("4", 6.4, 3.0), ("5", 2.6, -3.1)]
                for (n, x, y) in o { text.append((n, project(x, y))) }
                var pass = Path()
                line((8.0, 0.0), (6.6, -4.4), into: &pass)
                dashed.addPath(pass)
                var cut = Path()
                cut.move(to: project(1.5, -5.6))
                cut.addQuadCurve(to: project(2.0, 3.4), control: project(0.3, -1.0))
                lines.addPath(cut)
                // Arrowhead at the cut's end.
                let tip = project(2.0, 3.4), back = project(1.3, 2.4)
                let dx = tip.x - back.x, dy = tip.y - back.y
                let len = max(0.001, (dx * dx + dy * dy).squareRoot())
                let ux = dx / len, uy = dy / len, head: CGFloat = 7
                var arrow = Path()
                arrow.move(to: CGPoint(x: tip.x - ux * head - uy * head * 0.6, y: tip.y - uy * head + ux * head * 0.6))
                arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x - ux * head + uy * head * 0.6, y: tip.y - uy * head - ux * head * 0.6))
                lines.addPath(arrow)
                for (x, y) in [(7.4, 0.5), (5.3, -4.5)] {
                    let c = project(x, y), r: CGFloat = 5
                    lines.move(to: CGPoint(x: c.x - r, y: c.y - r)); lines.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
                    lines.move(to: CGPoint(x: c.x + r, y: c.y - r)); lines.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
                }
            }

            // Fade toward the leading edge, where the header's words are.
            ctx.drawLayer { layer in
                let ink = GraphicsContext.Shading.color(.white.opacity(lineOpacity))
                let stroke = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
                layer.stroke(lines, with: ink, style: stroke)
                layer.stroke(dashed, with: ink, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [4, 5]))
                layer.fill(marks, with: .color(.white.opacity(lineOpacity * 1.6)))
                for (n, p) in text {
                    let r: CGFloat = 11
                    layer.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: ink, lineWidth: 1.25)
                    layer.draw(Text(n).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(lineOpacity * 1.4)), at: p)
                }
                layer.blendMode = .destinationIn
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.25), location: 0),
                                     .init(color: .white.opacity(0.7), location: 0.4),
                                     .init(color: .white, location: 0.7)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Court metres → points for each angle. Top-down views keep one scale on
    /// both axes, so a circle stays a circle.
    private func projection(for style: CourtArtStyle, in size: CGSize) -> (Double, Double) -> CGPoint {
        let w = Double(size.width), h = Double(size.height)
        switch style {
        case .halfCourt, .testSpots:
            // Basket at the bottom, the key on the trailing side.
            let s = max(h / 9.2, w / 22)
            let cx = w * 0.7, base = h + 0.6 * s
            return { x, y in CGPoint(x: cx + y * s, y: base - x * s) }
        case .tacticsBoard:
            // Basket at the top, as on a coach's clipboard.
            let s = max(h / 10.5, w / 22)
            let cx = w * 0.64, base = -0.4 * s
            return { x, y in CGPoint(x: cx + y * s, y: base + x * s) }
        case .fullCourt:
            // The whole court, lengthwise across the card.
            let s = max(w / 29.5, h / 16.2)
            let ox = w / 2 - FIBA.half * s, cy = h * 0.52
            return { x, y in CGPoint(x: ox + x * s, y: cy + y * s) }
        case .centreCircle:
            let s = h / 7.5
            let cx = w * 0.72, cy = h * 0.55
            return { x, y in CGPoint(x: cx + (x - FIBA.half) * s, y: cy + y * s) }
        case .broadcast:
            // A true pinhole camera 4 m up, 1.9 m behind the top of the
            // three-point arc, looking at the basket: the baseline lands near
            // the top, the arc's top at the bottom, far lines shrink.
            let camX = FIBA.basket + FIBA.threeRadius + 1.9, camHeight = 4.0
            let horizon = h * 0.02
            let focal = (h * 0.98) * 1.9 / camHeight
            let cx = w * 0.64
            return { x, y in
                let depth = max(0.6, camX - x)
                return CGPoint(x: cx + focal * y / depth, y: horizon + focal * camHeight / depth)
            }
        }
    }
}
