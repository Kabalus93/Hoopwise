import SwiftUI

/// The court, drawn from `CourtGeometry`.
///
/// This is the only SwiftUI court renderer. It shares its path construction
/// with the PDF and animation exporters, so what a coach sees in the editor is
/// the same geometry that lands in an export — the three-point line cannot
/// disagree between them.
struct CourtView: View {
    var space: CourtSpace
    var lineColor: Color = Color(white: 0.18)
    var floorColor: Color = Color(red: 0.96, green: 0.91, blue: 0.83)
    /// Stroke width in POINTS, held constant regardless of zoom so lines stay
    /// legible on a small preview and don't turn into slabs on a large canvas.
    var lineWidth: CGFloat = 1.5
    var padding: CGFloat = 12

    init(space: CourtSpace = CourtSpace(),
         lineColor: Color = Color(white: 0.18),
         floorColor: Color = Color(red: 0.96, green: 0.91, blue: 0.83),
         lineWidth: CGFloat = 1.5,
         padding: CGFloat = 12) {
        self.space = space
        self.lineColor = lineColor
        self.floorColor = floorColor
        self.lineWidth = lineWidth
        self.padding = padding
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let transform = CourtTransform(space: space, in: rect, padding: padding)
            // CGPath.copy(using:) takes the transform inout, so it needs a var.
            var affine = transform.affine
            let paths = CourtGeometry(space: space).paths()

            let floorRect = CGRect(x: 0, y: 0, width: space.width, height: space.length)
            if let floor = CGPath(rect: floorRect, transform: nil).copy(using: &affine) {
                context.fill(Path(floor), with: .color(floorColor))
            }

            if let solid = paths.solid.copy(using: &affine) {
                context.stroke(Path(solid), with: .color(lineColor),
                               style: StrokeStyle(lineWidth: lineWidth,
                                                  lineCap: .round,
                                                  lineJoin: .round))
            }
            if let dashed = paths.dashed.copy(using: &affine) {
                context.stroke(Path(dashed), with: .color(lineColor),
                               style: StrokeStyle(lineWidth: lineWidth,
                                                  lineCap: .round,
                                                  dash: [lineWidth * 3, lineWidth * 3]))
            }
        }
    }
}

// MARK: - Legacy Wrapper

/// Back-compat shim for the iOS drill diagram editor, which drew an NBA
/// half court. Delegates to `CourtView` so there is genuinely one renderer.
///
/// Note the geometry moved slightly: the rim centre is now 5.25ft from the
/// baseline rather than 4.75ft. The old value omitted the 6-inch gap between
/// the backboard face and the near edge of the rim.
struct CourtBackgroundView: View {
    var lineColor: Color = Color(white: 0.18)
    var lineWidth: CGFloat = 2
    var floorColor: Color = Color(red: 0.96, green: 0.91, blue: 0.83)
    var verticalPadding: CGFloat = 12

    var body: some View {
        CourtView(space: CourtSpace(standard: .nba, mode: .half),
                  lineColor: lineColor,
                  floorColor: floorColor,
                  lineWidth: lineWidth,
                  padding: verticalPadding)
    }
}
