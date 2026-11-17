import SwiftUI

/// The Hub's own icons, drawn to the play editor's tool standard (18 Nov
/// 2026, Luther: "give these icons the same treatment as the tools icon" —
/// EditorToolGlyph): one unit grid, ONE stroke weight (1/12 of the side,
/// never under 1.5 pt), round caps and joins, no tinted fills, the same
/// filled dart arrowhead, and the diagram's one colour cue — the offensive
/// player's ring in blue. A play, a cone, a book, a jersey, an org chart, a
/// board.
struct HubGlyph: View {
    enum Kind { case plays, teams, lexicon, drills, organization, board }

    let kind: Kind
    var tint: Color = .primary
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let ink = GraphicsContext.Shading.color(tint)
            let blue = GraphicsContext.Shading.color(JPalette.play)
            let weight = max(1.5, s / 12)
            let stroke = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s))
            }
            /// The house dart (EditorToolGlyph's), tip at `tip`, arriving from `from`.
            func head(from: CGPoint, tip: CGPoint) {
                let a = atan2(tip.y - from.y, tip.x - from.x)
                let length = s * 0.26, half = s * 0.13
                let back = CGPoint(x: tip.x - cos(a) * length, y: tip.y - sin(a) * length)
                let notch = CGPoint(x: tip.x - cos(a) * length * 0.72, y: tip.y - sin(a) * length * 0.72)
                var dart = Path()
                dart.move(to: tip)
                dart.addLine(to: CGPoint(x: back.x + sin(a) * half, y: back.y - cos(a) * half))
                dart.addLine(to: notch)
                dart.addLine(to: CGPoint(x: back.x - sin(a) * half, y: back.y + cos(a) * half))
                dart.closeSubpath()
                context.fill(dart, with: ink)
                context.stroke(dart, with: ink, style: StrokeStyle(lineWidth: weight * 0.5, lineJoin: .round))
            }
            func x(at c: CGPoint, _ r: CGFloat) {
                var mark = Path()
                mark.move(to: CGPoint(x: c.x - r * s, y: c.y - r * s)); mark.addLine(to: CGPoint(x: c.x + r * s, y: c.y + r * s))
                mark.move(to: CGPoint(x: c.x + r * s, y: c.y - r * s)); mark.addLine(to: CGPoint(x: c.x - r * s, y: c.y + r * s))
                context.stroke(mark, with: ink, style: stroke)
            }

            switch kind {
            case .plays:
                // O cuts around the X: a smooth run ending in the dart.
                context.stroke(circle(p(0.22, 0.76), 0.15), with: blue, style: stroke)
                let from = p(0.30, 0.59), tip = p(0.90, 0.14), bend = p(0.34, 0.14)
                var run = Path()
                run.move(to: from)
                // Stop under the dart, along the way the curve arrives.
                let a = atan2(tip.y - bend.y, tip.x - bend.x)
                run.addQuadCurve(to: CGPoint(x: tip.x - cos(a) * s * 0.18, y: tip.y - sin(a) * s * 0.18), control: bend)
                context.stroke(run, with: ink, style: stroke)
                head(from: bend, tip: tip)
                x(at: p(0.74, 0.76), 0.12)

            case .drills:
                // A training cone: body, one band, the base (the Cone tool).
                var body = Path()
                body.move(to: p(0.5, 0.12))
                body.addLine(to: p(0.74, 0.78))
                body.addLine(to: p(0.26, 0.78))
                body.closeSubpath()
                context.stroke(body, with: ink, style: stroke)
                var lines = Path()
                lines.move(to: p(0.38, 0.46)); lines.addLine(to: p(0.62, 0.46))
                lines.move(to: p(0.12, 0.88)); lines.addLine(to: p(0.88, 0.88))
                context.stroke(lines, with: ink, style: stroke)

            case .lexicon:
                // An open book: two pages from one spine, a line of text each.
                var book = Path()
                book.move(to: p(0.5, 0.24))
                book.addQuadCurve(to: p(0.10, 0.20), control: p(0.30, 0.12))
                book.addLine(to: p(0.10, 0.78))
                book.addQuadCurve(to: p(0.5, 0.84), control: p(0.30, 0.70))
                book.addQuadCurve(to: p(0.90, 0.78), control: p(0.70, 0.70))
                book.addLine(to: p(0.90, 0.20))
                book.addQuadCurve(to: p(0.5, 0.24), control: p(0.70, 0.12))
                book.move(to: p(0.5, 0.24)); book.addLine(to: p(0.5, 0.84))
                context.stroke(book, with: ink, style: stroke)
                var text = Path()
                text.move(to: p(0.22, 0.40)); text.addLine(to: p(0.38, 0.42))
                text.move(to: p(0.22, 0.56)); text.addLine(to: p(0.38, 0.58))
                text.move(to: p(0.62, 0.42)); text.addLine(to: p(0.78, 0.40))
                text.move(to: p(0.62, 0.58)); text.addLine(to: p(0.78, 0.56))
                context.stroke(text, with: ink, style: StrokeStyle(lineWidth: weight * 0.8, lineCap: .round))

            case .teams:
                // A tank-top jersey: straps, scoop neck, armholes, hem.
                var jersey = Path()
                jersey.move(to: p(0.30, 0.10))
                jersey.addLine(to: p(0.38, 0.10))
                jersey.addQuadCurve(to: p(0.62, 0.10), control: p(0.50, 0.34))
                jersey.addLine(to: p(0.70, 0.10))
                jersey.addQuadCurve(to: p(0.84, 0.40), control: p(0.70, 0.36))
                jersey.addLine(to: p(0.84, 0.90))
                jersey.addLine(to: p(0.16, 0.90))
                jersey.addLine(to: p(0.16, 0.40))
                jersey.addQuadCurve(to: p(0.30, 0.10), control: p(0.30, 0.36))
                jersey.closeSubpath()
                context.stroke(jersey, with: ink, style: stroke)
                context.draw(Text("23").font(.system(size: s * 0.30, weight: .bold, design: .rounded))
                                .foregroundStyle(tint),
                             at: p(0.5, 0.62))

            case .organization:
                // An org chart: one node over two.
                let node = CGSize(width: 0.30 * s, height: 0.22 * s)
                let nodes = [p(0.35, 0.08), p(0.06, 0.70), p(0.64, 0.70)].map {
                    Path(roundedRect: CGRect(origin: $0, size: node), cornerRadius: 0.06 * s, style: .continuous)
                }
                for n in nodes { context.stroke(n, with: ink, style: stroke) }
                var links = Path()
                links.move(to: p(0.50, 0.30)); links.addLine(to: p(0.50, 0.50))
                links.move(to: p(0.21, 0.70)); links.addLine(to: p(0.21, 0.50))
                links.addLine(to: p(0.79, 0.50)); links.addLine(to: p(0.79, 0.70))
                context.stroke(links, with: ink, style: stroke)

            case .board:
                // A coach's board: the frame and its clip, an O, a dashed pass, an X.
                let frame = Path(roundedRect: CGRect(x: 0.12 * s, y: 0.16 * s, width: 0.76 * s, height: 0.76 * s),
                                 cornerRadius: 0.10 * s, style: .continuous)
                context.stroke(frame, with: ink, style: stroke)
                var clip = Path()
                clip.move(to: p(0.38, 0.16)); clip.addLine(to: p(0.38, 0.08))
                clip.addLine(to: p(0.62, 0.08)); clip.addLine(to: p(0.62, 0.16))
                context.stroke(clip, with: ink, style: stroke)
                context.stroke(circle(p(0.34, 0.68), 0.11), with: blue, style: stroke)
                x(at: p(0.67, 0.42), 0.09)
                var pass = Path()
                pass.move(to: p(0.44, 0.59))
                pass.addLine(to: p(0.58, 0.50))
                context.stroke(pass, with: ink, style: StrokeStyle(lineWidth: weight, lineCap: .round,
                                                                   dash: [s * 0.05, s * 0.06]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
