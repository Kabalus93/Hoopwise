import Foundation
import CoreGraphics

// MARK: - Court Geometry
//
// THE court renderer. One source of truth for court markings, driven entirely
// by CourtMetrics, consumed by the editor, the PDF exporter, and the animation
// exporter.
//
// It replaced two divergent renderers:
//
//   CourtBackgroundView  half court, portrait, uniform scale, court-feet.
//                        Sound approach, but NBA constants hardcoded and the
//                        rim centre was 4.75ft from the baseline — the 6-inch
//                        gap between backboard face and rim near edge was
//                        missing. The correct NBA figure is 5.25ft.
//   CourtLinesView       full court, landscape (axes swapped), NBA constants,
//                        basket at 4.0ft, and NON-UNIFORM scaling: it derived
//                        scaleX from length and scaleY from width, then drew
//                        the three-point arc as a circle of radius
//                        23.75 * scaleX. Whenever the frame aspect did not
//                        exactly match 94:50 that arc was geometrically wrong.
//                        Not salvageable; deleted with its host file.
//
// Paths are produced in COURT FEET. Nothing here knows about view size, so the
// same CGPath serves a SwiftUI Canvas, a CGPDFContext, and a video frame — the
// requirement that made vector output non-negotiable in the first place.
//
// Coordinate space matches CourtSpace:
//   x = 0 left sideline, x = width right sideline
//   y = 0 near baseline, y increasing away from the near basket
//   y is UP here. CourtTransform applies the flip to view space.

/// Court markings, split by how they are drawn.
///
/// Fills are separate paths rather than styling hints because the video style
/// is white line work over a coloured floor: the renderer fills the regions
/// first, then strokes the lines on top. A stroke-only CourtPaths forced every
/// caller to reconstruct the painted areas itself.
struct CourtPaths {
    /// The whole playing surface.
    var floor: CGPath
    /// The painted lane(s). Both ends in full-court mode.
    var paint: CGPath
    /// Restricted-area semicircle(s) under the basket.
    var restrictedArea: CGPath
    /// Centre circle. Half of it in half-court mode.
    var centerCircle: CGPath
    /// Everything drawn as a solid line.
    var solid: CGPath
    /// Everything drawn dashed — free-throw circles.
    var dashed: CGPath

    /// Fill regions in back-to-front paint order.
    var fillRegions: [(path: CGPath, role: CourtFillRole)] {
        [(floor, .floor), (paint, .paint),
         (restrictedArea, .restrictedArea), (centerCircle, .centerCircle)]
    }
}

/// What a fill region represents, so callers can colour it without guessing.
enum CourtFillRole: String, CaseIterable, Hashable {
    case floor, paint, restrictedArea, centerCircle
}

/// Builds court markings in court feet from a `CourtSpace`.
struct CourtGeometry {
    let space: CourtSpace

    init(space: CourtSpace) {
        self.space = space
    }

    var metrics: CourtMetrics { space.metrics }

    /// Where the three-point arc meets the straight corner segment, measured
    /// from the near baseline.
    ///
    /// Derived, not hardcoded. Both previous renderers baked in a number — 14ft
    /// in one, a ±68° sweep in the other — which is only right for NBA
    /// dimensions and silently wrong for FIBA. Solving the intersection makes
    /// the arc meet the corner line exactly for any metrics.
    var cornerArcJunctionFromBaseline: CGFloat {
        let m = metrics
        let dx = m.cornerThreeInsetFromSideline - m.width / 2
        let radiusSquared = m.threePointRadius * m.threePointRadius
        let dySquared = radiusSquared - dx * dx
        // Degenerate metrics (arc narrower than the corner inset) would make
        // this imaginary; fall back to the baseline so the line just vanishes
        // rather than producing NaN geometry.
        guard dySquared > 0 else { return m.basketFromBaseline }
        return m.basketFromBaseline + sqrt(dySquared)
    }

    /// All markings for the configured space.
    func paths() -> CourtPaths {
        let solid = CGMutablePath()
        let dashed = CGMutablePath()
        let paint = CGMutablePath()
        let restricted = CGMutablePath()
        let centre = CGMutablePath()
        let m = metrics

        let floor = CGPath(rect: CGRect(x: 0, y: 0, width: space.width, height: space.length),
                           transform: nil)
        // Outer boundary.
        solid.addRect(CGRect(x: 0, y: 0, width: space.width, height: space.length))

        switch space.mode {
        case .half:
            addEnd(solid: solid, dashed: dashed, paint: paint, restricted: restricted,
                   mirrored: false)
            // The half-court line is the far edge of a half-court diagram, so
            // the boundary already drew it. Only the centre semicircle is left.
            addCentreCircle(into: solid, atY: space.length, halfOnly: true)
            addCentreCircle(into: centre, atY: space.length, halfOnly: true)

        case .full:
            addEnd(solid: solid, dashed: dashed, paint: paint, restricted: restricted,
                   mirrored: false)
            addEnd(solid: solid, dashed: dashed, paint: paint, restricted: restricted,
                   mirrored: true)

            let midY = m.fullLength / 2
            solid.move(to: CGPoint(x: 0, y: midY))
            solid.addLine(to: CGPoint(x: m.width, y: midY))
            addCentreCircle(into: solid, atY: midY, halfOnly: false)
            addCentreCircle(into: centre, atY: midY, halfOnly: false)
        }

        return CourtPaths(floor: floor, paint: paint, restrictedArea: restricted,
                          centerCircle: centre, solid: solid, dashed: dashed)
    }

    // MARK: - One End

    /// Draws one basket's markings. `mirrored` flips to the far end, which only
    /// happens in `.full` mode.
    private func addEnd(solid: CGMutablePath, dashed: CGMutablePath,
                        paint: CGMutablePath, restricted: CGMutablePath,
                        mirrored: Bool) {
        let m = metrics
        let centreX = m.width / 2

        // Maps a near-end y (measured from that end's baseline) into diagram y.
        func y(_ fromBaseline: CGFloat) -> CGFloat {
            mirrored ? m.fullLength - fromBaseline : fromBaseline
        }

        // Lane / key.
        let laneLeft = centreX - m.keyWidth / 2
        let laneNear = y(0)
        let laneFar = y(m.freeThrowLineFromBaseline)
        let laneRect = CGRect(x: laneLeft,
                              y: min(laneNear, laneFar),
                              width: m.keyWidth,
                              height: abs(laneFar - laneNear))
        solid.addRect(laneRect)
        paint.addRect(laneRect)

        // Free-throw circle, dashed. Drawn whole; the lane rect overlaps its
        // near half, which is how coaching diagrams conventionally read.
        let ftCentre = CGPoint(x: centreX, y: y(m.freeThrowLineFromBaseline))
        dashed.addEllipse(in: CGRect(x: ftCentre.x - m.freeThrowCircleRadius,
                                     y: ftCentre.y - m.freeThrowCircleRadius,
                                     width: m.freeThrowCircleRadius * 2,
                                     height: m.freeThrowCircleRadius * 2))

        // Backboard. Sits between the baseline and the rim centre.
        let backboardY = y(m.basketFromBaseline - m.rimRadius - 0.5)
        solid.move(to: CGPoint(x: centreX - m.backboardWidth / 2, y: backboardY))
        solid.addLine(to: CGPoint(x: centreX + m.backboardWidth / 2, y: backboardY))

        // Rim.
        let basket = CGPoint(x: centreX, y: y(m.basketFromBaseline))
        solid.addEllipse(in: CGRect(x: basket.x - m.rimRadius,
                                    y: basket.y - m.rimRadius,
                                    width: m.rimRadius * 2,
                                    height: m.rimRadius * 2))

        // Three-point line: two straight corner segments, then the arc.
        let junction = cornerArcJunctionFromBaseline
        let leftX = m.cornerThreeInsetFromSideline
        let rightX = m.width - m.cornerThreeInsetFromSideline

        solid.move(to: CGPoint(x: leftX, y: y(0)))
        solid.addLine(to: CGPoint(x: leftX, y: y(junction)))
        solid.move(to: CGPoint(x: rightX, y: y(0)))
        solid.addLine(to: CGPoint(x: rightX, y: y(junction)))

        // Sweep between the two junction points, passing through the point
        // furthest from the basket. Angles are computed from the junctions so
        // the arc lands exactly on the ends of the straight segments.
        let leftJunction = CGPoint(x: leftX, y: y(junction))
        let rightJunction = CGPoint(x: rightX, y: y(junction))
        let startAngle = atan2(leftJunction.y - basket.y, leftJunction.x - basket.x)
        let endAngle = atan2(rightJunction.y - basket.y, rightJunction.x - basket.x)

        solid.addArc(center: basket,
                     radius: m.threePointRadius,
                     startAngle: startAngle,
                     endAngle: endAngle,
                     clockwise: !mirrored)

        // Restricted area, dashed half-circle opening away from the baseline.
        let restrictedStart: CGFloat = mirrored ? .pi : 0
        let restrictedEnd: CGFloat = mirrored ? 0 : .pi
        dashed.addArc(center: basket,
                      radius: m.restrictedAreaRadius,
                      startAngle: restrictedStart,
                      endAngle: restrictedEnd,
                      clockwise: mirrored)
        // Closed version for filling.
        restricted.move(to: basket)
        restricted.addArc(center: basket,
                          radius: m.restrictedAreaRadius,
                          startAngle: restrictedStart,
                          endAngle: restrictedEnd,
                          clockwise: mirrored)
        restricted.closeSubpath()
    }

    private func addCentreCircle(into path: CGMutablePath, atY centreY: CGFloat, halfOnly: Bool) {
        let m = metrics
        let centre = CGPoint(x: m.width / 2, y: centreY)
        if halfOnly {
            // Half-court diagram: only the half of the circle inside the court
            // is visible, which is the half nearer the basket.
            path.addArc(center: centre,
                        radius: m.centerCircleRadius,
                        startAngle: .pi,
                        endAngle: 2 * .pi,
                        clockwise: false)
        } else {
            path.addEllipse(in: CGRect(x: centre.x - m.centerCircleRadius,
                                       y: centre.y - m.centerCircleRadius,
                                       width: m.centerCircleRadius * 2,
                                       height: m.centerCircleRadius * 2))
        }
    }
}

// MARK: - Transform

/// Court feet to view points.
///
/// Uniform scale, always. The previous full-court renderer scaled each axis
/// independently to fill its frame, which stretched the court and made every
/// circle an ellipse while still drawing arcs as circles. Letterboxing is the
/// only correct choice when the model is real-world geometry.
struct CourtTransform {
    /// Points per court foot.
    let scale: CGFloat
    /// View-space origin of court (0, 0).
    let origin: CGPoint
    /// The court's drawn size in points.
    let courtSize: CGSize

    init(space: CourtSpace, in rect: CGRect, padding: CGFloat = 0) {
        let available = CGSize(width: max(0, rect.width - padding * 2),
                               height: max(0, rect.height - padding * 2))
        let fitScale = min(available.width / max(space.width, 1),
                           available.height / max(space.length, 1))
        self.scale = fitScale
        self.courtSize = CGSize(width: space.width * fitScale,
                                height: space.length * fitScale)
        self.origin = CGPoint(x: rect.minX + (rect.width - courtSize.width) / 2,
                              y: rect.minY + (rect.height - courtSize.height) / 2)
    }

    /// Court feet to view points, flipping y so the near baseline sits at the
    /// top — the orientation coaches draw on a board ("we run this *toward*
    /// the basket").
    func point(_ courtPoint: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + courtPoint.x * scale,
                y: origin.y + courtSize.height - courtPoint.y * scale)
    }

    /// The same mapping as an affine transform, for stroking whole CGPaths
    /// without walking their elements.
    var affine: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y + courtSize.height)
            .scaledBy(x: scale, y: -scale)
    }

    /// Court feet to points, for line widths and marker radii.
    func length(_ courtFeet: CGFloat) -> CGFloat { courtFeet * scale }

    /// View points back to court feet — the exact inverse of `point`.
    ///
    /// Every drag, placement and hit test in the editor needs this. Note the
    /// y flip: view y grows downward, court y grows away from the near basket.
    func inverse(_ viewPoint: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - origin.x) / scale,
                       y: (origin.y + courtSize.height - viewPoint.y) / scale)
    }

    /// Points back to court feet, for distances.
    func courtFeet(_ points: CGFloat) -> CGFloat {
        scale > 0 ? points / scale : 0
    }
}
