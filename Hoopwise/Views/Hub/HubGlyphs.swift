import SwiftUI

/// The Hub's own icons (15 November 2026, Luther: "a better set of icons,
/// preferably bespoke to the app" — Plays and Coach shared a court symbol and
/// Teams' symbol overflowed its bubble). Drawn in a unit square so each fits
/// its tile: a play diagram, a jersey, an open book, a cone, an org chart.
struct HubGlyph: View {
    enum Kind { case plays, teams, lexicon, drills, organization }

    let kind: Kind
    var tint: Color = .accentColor
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let line = StrokeStyle(lineWidth: max(1.6, s * 0.075), lineCap: .round, lineJoin: .round)
            let shade = GraphicsContext.Shading.color(tint)

            switch kind {
            case .plays:
                // O cuts past the X: a smooth curve with a head that points the
                // way the curve arrives.
                context.stroke(Path(ellipseIn: CGRect(origin: p(0.08, 0.60), size: CGSize(width: 0.28 * s, height: 0.28 * s))),
                               with: shade, style: line)
                let from = p(0.30, 0.58), to = p(0.88, 0.14), bend = p(0.36, 0.14)
                var cut = Path()
                cut.move(to: from)
                cut.addQuadCurve(to: to, control: bend)
                context.stroke(cut, with: shade, style: line)
                let angle = atan2(to.y - bend.y, to.x - bend.x)
                let headLength = 0.17 * s, spread = CGFloat.pi / 5.5
                var head = Path()
                head.move(to: CGPoint(x: to.x - headLength * cos(angle - spread), y: to.y - headLength * sin(angle - spread)))
                head.addLine(to: to)
                head.addLine(to: CGPoint(x: to.x - headLength * cos(angle + spread), y: to.y - headLength * sin(angle + spread)))
                context.stroke(head, with: shade, style: line)
                var x = Path()
                x.move(to: p(0.64, 0.62)); x.addLine(to: p(0.88, 0.86))
                x.move(to: p(0.88, 0.62)); x.addLine(to: p(0.64, 0.86))
                context.stroke(x, with: shade, style: line)

            case .teams:
                // A clean tank-top jersey: scoop neck, curved armholes, a
                // band at the hem.
                var j = Path()
                j.move(to: p(0.26, 0.08))
                j.addLine(to: p(0.35, 0.08))
                j.addCurve(to: p(0.65, 0.08), control1: p(0.37, 0.30), control2: p(0.63, 0.30))
                j.addLine(to: p(0.74, 0.08))
                j.addQuadCurve(to: p(0.86, 0.40), control: p(0.74, 0.36))
                j.addLine(to: p(0.84, 0.92))
                j.addLine(to: p(0.16, 0.92))
                j.addLine(to: p(0.14, 0.40))
                j.addQuadCurve(to: p(0.26, 0.08), control: p(0.26, 0.36))
                j.closeSubpath()
                context.fill(j, with: GraphicsContext.Shading.color(tint.opacity(0.16)))
                context.stroke(j, with: shade, style: line)
                var hem = Path()
                hem.move(to: p(0.16, 0.80)); hem.addLine(to: p(0.84, 0.80))
                context.stroke(hem, with: GraphicsContext.Shading.color(tint.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))

            case .lexicon:
                // The playbook dictionary: a closed book, its spine band on the
                // left, a basketball on the cover.
                let cover = Path(roundedRect: CGRect(origin: p(0.16, 0.06), size: CGSize(width: 0.68 * s, height: 0.88 * s)),
                                 cornerRadius: 0.08 * s)
                context.fill(cover, with: GraphicsContext.Shading.color(tint.opacity(0.16)))
                context.stroke(cover, with: shade, style: line)
                var spine = Path()
                spine.move(to: p(0.30, 0.06)); spine.addLine(to: p(0.30, 0.94))
                context.stroke(spine, with: shade, style: line)
                let c = p(0.57, 0.44), r = 0.21 * s
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: shade, style: StrokeStyle(lineWidth: max(1.3, s * 0.06)))
                // A basketball's seams: the vertical line and the two side
                // curves (a straight cross read as a crosshair).
                var seams = Path()
                seams.move(to: CGPoint(x: c.x, y: c.y - r)); seams.addLine(to: CGPoint(x: c.x, y: c.y + r))
                seams.move(to: CGPoint(x: c.x - r * 0.62, y: c.y - r * 0.78))
                seams.addQuadCurve(to: CGPoint(x: c.x - r * 0.62, y: c.y + r * 0.78), control: CGPoint(x: c.x - r * 0.05, y: c.y))
                seams.move(to: CGPoint(x: c.x + r * 0.62, y: c.y - r * 0.78))
                seams.addQuadCurve(to: CGPoint(x: c.x + r * 0.62, y: c.y + r * 0.78), control: CGPoint(x: c.x + r * 0.05, y: c.y))
                context.stroke(seams, with: shade, style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
                var title = Path()
                title.move(to: p(0.44, 0.82)); title.addLine(to: p(0.70, 0.82))
                context.stroke(title, with: GraphicsContext.Shading.color(tint.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))

            case .drills:
                // A training cone: flat top, gently curved sides, a band, on a
                // square base slab — not a letter A.
                func edge(_ y: CGFloat) -> (CGFloat, CGFloat) {
                    let t = (y - 0.14) / 0.60
                    let half = 0.07 + 0.21 * t
                    return (0.50 - half, 0.50 + half)
                }
                var body = Path()
                body.move(to: p(0.43, 0.14))
                body.addQuadCurve(to: p(0.57, 0.14), control: p(0.50, 0.08))
                body.addQuadCurve(to: p(0.78, 0.74), control: p(0.65, 0.46))
                body.addLine(to: p(0.22, 0.74))
                body.addQuadCurve(to: p(0.43, 0.14), control: p(0.35, 0.46))
                body.closeSubpath()
                context.fill(body, with: GraphicsContext.Shading.color(tint.opacity(0.16)))
                let (l1, r1) = edge(0.38), (l2, r2) = edge(0.54)
                var band = Path()
                band.move(to: p(l1 + 0.01, 0.38)); band.addLine(to: p(r1 - 0.01, 0.38))
                band.addLine(to: p(r2 - 0.01, 0.54)); band.addLine(to: p(l2 + 0.01, 0.54))
                band.closeSubpath()
                context.fill(band, with: GraphicsContext.Shading.color(tint.opacity(0.45)))
                context.stroke(body, with: shade, style: line)
                let slab = Path(roundedRect: CGRect(origin: p(0.10, 0.74), size: CGSize(width: 0.80 * s, height: 0.14 * s)),
                                cornerRadius: 0.04 * s)
                context.fill(slab, with: GraphicsContext.Shading.color(tint.opacity(0.25)))
                context.stroke(slab, with: shade, style: line)

            case .organization:
                // An org chart: one node over two.
                let nodeSize = CGSize(width: 0.30 * s, height: 0.22 * s)
                let top = Path(roundedRect: CGRect(origin: p(0.35, 0.08), size: nodeSize), cornerRadius: 0.06 * s)
                let left = Path(roundedRect: CGRect(origin: p(0.06, 0.68), size: nodeSize), cornerRadius: 0.06 * s)
                let right = Path(roundedRect: CGRect(origin: p(0.64, 0.68), size: nodeSize), cornerRadius: 0.06 * s)
                context.fill(top, with: GraphicsContext.Shading.color(tint.opacity(0.25)))
                for node in [top, left, right] { context.stroke(node, with: shade, style: line) }
                var links = Path()
                links.move(to: p(0.50, 0.30)); links.addLine(to: p(0.50, 0.49))
                links.move(to: p(0.21, 0.68)); links.addLine(to: p(0.21, 0.49))
                links.addLine(to: p(0.79, 0.49)); links.addLine(to: p(0.79, 0.68))
                context.stroke(links, with: shade, style: line)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
