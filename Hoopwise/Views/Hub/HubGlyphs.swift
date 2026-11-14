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
            let soft = GraphicsContext.Shading.color(tint.opacity(0.28))

            switch kind {
            case .plays:
                // O — a curved cut with its arrowhead — X.
                context.stroke(Path(ellipseIn: CGRect(origin: p(0.10, 0.60), size: CGSize(width: 0.26 * s, height: 0.26 * s))),
                               with: shade, style: line)
                var cut = Path()
                cut.move(to: p(0.30, 0.56))
                cut.addQuadCurve(to: p(0.80, 0.22), control: p(0.36, 0.14))
                context.stroke(cut, with: shade, style: line)
                var head = Path()
                head.move(to: p(0.62, 0.14))
                head.addLine(to: p(0.82, 0.21))
                head.addLine(to: p(0.70, 0.38))
                context.stroke(head, with: shade, style: line)
                var x = Path()
                x.move(to: p(0.62, 0.62)); x.addLine(to: p(0.86, 0.86))
                x.move(to: p(0.86, 0.62)); x.addLine(to: p(0.62, 0.86))
                context.stroke(x, with: shade, style: line)

            case .teams:
                // A team jersey with a number.
                var j = Path()
                j.move(to: p(0.22, 0.10))
                j.addLine(to: p(0.38, 0.10))
                j.addQuadCurve(to: p(0.62, 0.10), control: p(0.50, 0.30))
                j.addLine(to: p(0.78, 0.10))
                j.addLine(to: p(0.80, 0.30))
                j.addQuadCurve(to: p(0.74, 0.46), control: p(0.72, 0.36))
                j.addLine(to: p(0.74, 0.92))
                j.addLine(to: p(0.26, 0.92))
                j.addLine(to: p(0.26, 0.46))
                j.addQuadCurve(to: p(0.20, 0.30), control: p(0.28, 0.36))
                j.closeSubpath()
                context.fill(j, with: GraphicsContext.Shading.color(tint.opacity(0.16)))
                context.stroke(j, with: shade, style: line)
                context.draw(Text("23").font(.system(size: s * 0.3, weight: .heavy, design: .rounded)).foregroundStyle(tint),
                             at: p(0.50, 0.64))

            case .lexicon:
                // An open book with lines on its pages.
                var pages = Path()
                pages.move(to: p(0.50, 0.24))
                pages.addQuadCurve(to: p(0.08, 0.20), control: p(0.30, 0.10))
                pages.addLine(to: p(0.08, 0.80))
                pages.addQuadCurve(to: p(0.50, 0.86), control: p(0.30, 0.72))
                pages.addQuadCurve(to: p(0.92, 0.80), control: p(0.70, 0.72))
                pages.addLine(to: p(0.92, 0.20))
                pages.addQuadCurve(to: p(0.50, 0.24), control: p(0.70, 0.10))
                pages.closeSubpath()
                context.fill(pages, with: GraphicsContext.Shading.color(tint.opacity(0.16)))
                context.stroke(pages, with: shade, style: line)
                var spine = Path()
                spine.move(to: p(0.50, 0.24)); spine.addLine(to: p(0.50, 0.86))
                context.stroke(spine, with: shade, style: line)
                var text = Path()
                for (y, w) in [(0.38, 0.24), (0.52, 0.20), (0.66, 0.16)] as [(CGFloat, CGFloat)] {
                    text.move(to: p(0.17, y)); text.addLine(to: p(0.17 + w, y))
                    text.move(to: p(0.59, y)); text.addLine(to: p(0.59 + w, y))
                }
                context.stroke(text, with: GraphicsContext.Shading.color(tint.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))

            case .drills:
                // A training cone with a stripe, on its base.
                var cone = Path()
                cone.move(to: p(0.50, 0.08))
                cone.addLine(to: p(0.74, 0.78))
                cone.addLine(to: p(0.26, 0.78))
                cone.closeSubpath()
                context.fill(cone, with: GraphicsContext.Shading.color(tint.opacity(0.2)))
                context.stroke(cone, with: shade, style: line)
                var stripe = Path()
                stripe.move(to: p(0.37, 0.46)); stripe.addLine(to: p(0.63, 0.46))
                context.stroke(stripe, with: shade, style: line)
                var base = Path()
                base.move(to: p(0.12, 0.86)); base.addLine(to: p(0.88, 0.86))
                context.stroke(base, with: shade, style: line)

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
