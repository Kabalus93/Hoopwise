import SwiftUI

/// The play editor's tool icons (18 Nov 2026, Luther: "revamp how the tools
/// look … the same quality as a modern design software … attention to
/// details … simple but precise"). Drawn, not symbols: ONE unit grid, ONE
/// stroke weight (1/12 of the side, never under 1.5 pt), round caps and
/// joins, ONE arrowhead shape for every line tool, every mark on the same
/// diagonal so the rail reads as a family. Monochrome — the tint is the
/// caller's (white on the selected tool's accent tile).
struct EditorToolGlyph: View {
    let tool: JournalPlayStepEditor.Tool
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let ink = GraphicsContext.Shading.foreground
            let weight = max(1.5, s / 12)
            let stroke = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            /// The house arrowhead: a filled, slightly concave dart at `tip`
            /// pointing along `from → tip`.
            func head(from: CGPoint, tip: CGPoint) {
                let a = atan2(tip.y - from.y, tip.x - from.x)
                let length = s * 0.30, half = s * 0.15
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
            /// Where a line stops so the dart covers its end cleanly.
            func shaft(_ from: CGPoint, _ tip: CGPoint) -> CGPoint {
                let a = atan2(tip.y - from.y, tip.x - from.x)
                return CGPoint(x: tip.x - cos(a) * s * 0.22, y: tip.y - sin(a) * s * 0.22)
            }

            // Every line tool runs on the same diagonal.
            let start = p(0.16, 0.84), tip = p(0.86, 0.14)

            switch tool {
            case .move:
                // A precise pointer: straight left edge, notched tail.
                var arrow = Path()
                arrow.move(to: p(0.28, 0.12))
                arrow.addLine(to: p(0.28, 0.80))
                arrow.addLine(to: p(0.45, 0.64))
                arrow.addLine(to: p(0.57, 0.90))
                arrow.addLine(to: p(0.68, 0.85))
                arrow.addLine(to: p(0.56, 0.60))
                arrow.addLine(to: p(0.78, 0.58))
                arrow.closeSubpath()
                context.fill(arrow, with: ink)
                context.stroke(arrow, with: ink, style: StrokeStyle(lineWidth: weight * 0.5, lineJoin: .round))

            case .cut:
                var line = Path()
                line.move(to: start)
                line.addLine(to: shaft(start, tip))
                context.stroke(line, with: ink, style: stroke)
                head(from: start, tip: tip)

            case .dribble:
                // An even zigzag along the diagonal, back on the line for
                // the last stretch into the dart.
                let end = shaft(start, tip)
                let dx = end.x - start.x, dy = end.y - start.y
                let length = hypot(dx, dy)
                let ux = dx / length, uy = dy / length
                let amp = s * 0.11, teeth = 4
                var zig = Path()
                zig.move(to: start)
                let run = length * 0.70
                for k in 1...teeth {
                    let t = run * CGFloat(k) / CGFloat(teeth)
                    let side: CGFloat = k == teeth ? 0 : (k.isMultiple(of: 2) ? -1 : 1)
                    zig.addLine(to: CGPoint(x: start.x + ux * t - uy * amp * side,
                                            y: start.y + uy * t + ux * amp * side))
                }
                zig.addLine(to: end)
                context.stroke(zig, with: ink, style: stroke)
                head(from: start, tip: tip)

            case .pass:
                var line = Path()
                line.move(to: start)
                line.addLine(to: shaft(start, tip))
                context.stroke(line, with: ink, style: StrokeStyle(lineWidth: weight, lineCap: .round,
                                                                   dash: [s * 0.10, s * 0.11]))
                head(from: start, tip: tip)

            case .handoff:
                // The diagram's mark: a line, and across it two parallel bars
                // struck through.
                var line = Path()
                line.move(to: start)
                line.addLine(to: tip)
                context.stroke(line, with: ink, style: stroke)
                let c = p(0.62, 0.38)
                let a = atan2(tip.y - start.y, tip.x - start.x)
                let ux = cos(a), uy = sin(a)
                var bars = Path()
                for offset in [-0.07, 0.07] as [CGFloat] {
                    let o = CGPoint(x: c.x + ux * offset * s, y: c.y + uy * offset * s)
                    bars.move(to: CGPoint(x: o.x - uy * s * 0.17, y: o.y + ux * s * 0.17))
                    bars.addLine(to: CGPoint(x: o.x + uy * s * 0.17, y: o.y - ux * s * 0.17))
                }
                context.stroke(bars, with: ink, style: stroke)

            case .shot:
                // Into the rim: the line ends in a ring, the backboard behind.
                let rim = p(0.70, 0.30)
                var line = Path()
                line.move(to: start)
                line.addLine(to: p(0.56, 0.44))
                context.stroke(line, with: ink, style: stroke)
                context.stroke(Path(ellipseIn: CGRect(x: rim.x - s * 0.13, y: rim.y - s * 0.13,
                                                      width: s * 0.26, height: s * 0.26)),
                               with: ink, style: stroke)
                var board = Path()
                board.move(to: p(0.78, 0.06))
                board.addLine(to: p(0.94, 0.22))
                context.stroke(board, with: ink, style: stroke)

            case .screen:
                // Upright, so it reads as a T: the run, then the bar.
                var t = Path()
                t.move(to: p(0.5, 0.88))
                t.addLine(to: p(0.5, 0.20))
                t.move(to: p(0.22, 0.20))
                t.addLine(to: p(0.78, 0.20))
                context.stroke(t, with: ink, style: stroke)

            case .player:
                context.stroke(Path(ellipseIn: CGRect(x: s * 0.12, y: s * 0.12, width: s * 0.76, height: s * 0.76)),
                               with: ink, style: stroke)
                context.draw(Text("1").font(.system(size: s * 0.50, weight: .semibold, design: .rounded))
                                .foregroundStyle(.foreground),
                             at: p(0.5, 0.52))

            case .defender:
                var x = Path()
                x.move(to: p(0.22, 0.22)); x.addLine(to: p(0.78, 0.78))
                x.move(to: p(0.78, 0.22)); x.addLine(to: p(0.22, 0.78))
                context.stroke(x, with: ink, style: stroke)

            case .ball:
                // A ball with its seams.
                let r = s * 0.38, c = p(0.5, 0.5)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: ink, style: stroke)
                var seams = Path()
                seams.move(to: CGPoint(x: c.x - r, y: c.y)); seams.addLine(to: CGPoint(x: c.x + r, y: c.y))
                seams.move(to: CGPoint(x: c.x, y: c.y - r)); seams.addLine(to: CGPoint(x: c.x, y: c.y + r))
                seams.move(to: CGPoint(x: c.x - r * 0.62, y: c.y - r * 0.78))
                seams.addQuadCurve(to: CGPoint(x: c.x - r * 0.62, y: c.y + r * 0.78), control: CGPoint(x: c.x - r * 0.12, y: c.y))
                seams.move(to: CGPoint(x: c.x + r * 0.62, y: c.y - r * 0.78))
                seams.addQuadCurve(to: CGPoint(x: c.x + r * 0.62, y: c.y + r * 0.78), control: CGPoint(x: c.x + r * 0.12, y: c.y))
                context.stroke(seams, with: ink, style: StrokeStyle(lineWidth: weight * 0.7, lineCap: .round))

            case .cone:
                // A training cone: body, one band, the base.
                var body = Path()
                body.move(to: p(0.5, 0.12))
                body.addLine(to: p(0.74, 0.78))
                body.addLine(to: p(0.26, 0.78))
                body.closeSubpath()
                context.stroke(body, with: ink, style: stroke)
                var band = Path()
                band.move(to: p(0.38, 0.46)); band.addLine(to: p(0.62, 0.46))
                band.move(to: p(0.14, 0.86)); band.addLine(to: p(0.86, 0.86))
                context.stroke(band, with: ink, style: stroke)

            case .erase:
                // An eraser on the bias: the working end filled.
                var block = Path(roundedRect: CGRect(x: -s * 0.36, y: -s * 0.16, width: s * 0.72, height: s * 0.32),
                                 cornerRadius: s * 0.07)
                let turn = CGAffineTransform(translationX: s * 0.52, y: s * 0.46).rotated(by: -.pi / 4)
                block = block.applying(turn)
                var tipPart = Path(roundedRect: CGRect(x: -s * 0.36, y: -s * 0.16, width: s * 0.30, height: s * 0.32),
                                   cornerRadius: s * 0.07)
                tipPart = tipPart.applying(turn)
                context.fill(tipPart, with: ink)
                context.stroke(block, with: ink, style: stroke)
                var floor = Path()
                floor.move(to: p(0.12, 0.90)); floor.addLine(to: p(0.50, 0.90))
                context.stroke(floor, with: ink, style: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
