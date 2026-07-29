import SwiftUI

// MARK: - CourtBackgroundView
/// SwiftUI-rendered half-court used as the immutable underlay for the drill
/// diagram editor.
///
/// Orientation: **basket at the top**, half-court line at the bottom — the
/// convention coaches use on tactic boards ("we run this *toward* the
/// basket"). Geometry follows NBA half-court proportions, normalized to a
/// 50ft (width) × 47ft (length) grid so the layout reads as a real court
/// regardless of which way the SwiftUI frame stretches.
///
/// Drawing the court ourselves keeps the asset catalog small and means lines
/// scale crisply at any resolution (live preview + the flattened-to-JPEG
/// export).
struct CourtBackgroundView: View {
    /// Court line color. Defaults to a soft contrast that reads on both
    /// light and dark photo overlays.
    var lineColor: Color = Color(white: 0.18)
    var lineWidth: CGFloat = 2
    var floorColor: Color = Color(red: 0.96, green: 0.91, blue: 0.83) // hardwood-ish

    /// How much vertical padding to leave above the basket end and below the
    /// half-court line. Smaller values make the court fill more of the
    /// screen but leave less room for fingers near the screen edges.
    var verticalPadding: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack {
                floorColor
                Path { path in
                    layoutCourt(in: geo.size, into: &path)
                }
                .stroke(lineColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Lays the court out filling the given size while keeping 50:47
    /// width:length proportions. Anything left over is symmetrical padding.
    /// `y=0` is the **baseline** (basket end), `y=47` is the half-court line
    /// — i.e. y increases as you move away from the basket.
    private func layoutCourt(in size: CGSize, into path: inout Path) {
        // Reserve a bit of breathing room at top/bottom so the basket and
        // half-court line aren't kissing the screen edges.
        let availableHeight = max(0, size.height - verticalPadding * 2)
        let availableWidth = size.width

        let courtAspect: CGFloat = 50.0 / 47.0      // width / length
        let containerAspect = availableWidth / max(availableHeight, 1)

        let scale: CGFloat
        if containerAspect > courtAspect {
            // Container is "wider" than the court — height is the limit.
            scale = availableHeight / 47.0
        } else {
            // Container is "narrower" than the court — width is the limit.
            scale = availableWidth / 50.0
        }
        let courtW = 50 * scale
        let courtL = 47 * scale
        let originX = (size.width - courtW) / 2
        let originY = (size.height - courtL) / 2

        // Court-feet → view points. y=0 → top of the court (basket end);
        // y=47 → bottom of the court (half-court line).
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        // 1) Outer court rectangle.
        path.addRect(CGRect(x: originX, y: originY, width: courtW, height: courtL))

        // 2) Free throw lane ("key"). NBA: 16ft wide × 19ft long, anchored
        //    at the baseline.
        let laneWidth: CGFloat = 16
        let laneLength: CGFloat = 19
        let laneLeft = (50 - laneWidth) / 2
        path.addRect(CGRect(
            x: point(laneLeft, 0).x,
            y: point(laneLeft, 0).y,
            width: laneWidth * scale,
            height: laneLength * scale
        ))

        // 3) Free throw circle. 12ft diameter centered at top of the key
        //    (i.e. 19ft from the baseline).
        let ftCircleDiameter: CGFloat = 12
        let ftCenter = point(25, laneLength)
        path.addEllipse(in: CGRect(
            x: ftCenter.x - (ftCircleDiameter / 2) * scale,
            y: ftCenter.y - (ftCircleDiameter / 2) * scale,
            width: ftCircleDiameter * scale,
            height: ftCircleDiameter * scale
        ))

        // 4) Backboard — 4ft from the baseline, 6ft wide centered on the
        //    rim. y=4 in court-feet, which sits *below* the baseline in view
        //    space because y grows downward away from the basket.
        let backboardOffset: CGFloat = 4
        let backboardWidth: CGFloat = 6
        path.move(to: point(25 - backboardWidth / 2, backboardOffset))
        path.addLine(to: point(25 + backboardWidth / 2, backboardOffset))

        // 5) Rim — 9 inches in front of the backboard, ~18in diameter.
        let rimDiameter: CGFloat = 1.5
        let rimCenter = point(25, backboardOffset + 0.75)
        path.addEllipse(in: CGRect(
            x: rimCenter.x - (rimDiameter / 2) * scale,
            y: rimCenter.y - (rimDiameter / 2) * scale,
            width: rimDiameter * scale,
            height: rimDiameter * scale
        ))

        // 6) 3-point line — straight 22ft corner segments from the baseline
        //    up to where the arc begins (y=33 in baseline-anchored court
        //    coordinates, i.e. 14ft from the baseline), then a 23'9" arc
        //    around the rim center. With basket-at-top orientation we draw
        //    the arc *below* the rim in view space.
        let cornerDistance: CGFloat = 3        // distance in from each sideline
        let cornerLineEndY: CGFloat = 14       // where the arc begins (14ft up from baseline)

        path.move(to: point(cornerDistance, 0))
        path.addLine(to: point(cornerDistance, cornerLineEndY))

        path.move(to: point(50 - cornerDistance, 0))
        path.addLine(to: point(50 - cornerDistance, cornerLineEndY))

        let threePointRadius: CGFloat = 23.75
        // Arc opens downward (away from the basket, toward the half-court
        // line). Compute the start/end angles symmetrically so the arc
        // visually meets the ends of the corner segments.
        // 0° points right; 90° points down in iOS view coordinates.
        let cornerLineEndPointL = point(cornerDistance, cornerLineEndY)
        let dx = cornerLineEndPointL.x - rimCenter.x
        let dy = cornerLineEndPointL.y - rimCenter.y
        let startAngle = atan2(dy, dx)                          // points to left corner end
        let endAngle = .pi - startAngle                         // mirrored on the right
        path.addArc(
            center: rimCenter,
            radius: threePointRadius * scale,
            startAngle: .radians(Double(startAngle)),
            endAngle: .radians(Double(endAngle)),
            clockwise: false
        )

        // 7) Restricted area — small semicircle 4ft from the rim, drawn so
        //    coaches can call out illegal-defense areas.
        let restrictedRadius: CGFloat = 4
        path.addArc(
            center: rimCenter,
            radius: restrictedRadius * scale,
            startAngle: .radians(0),
            endAngle: .radians(.pi),
            clockwise: false
        )
    }
}
