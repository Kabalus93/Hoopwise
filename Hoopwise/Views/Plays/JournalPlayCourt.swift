import SwiftUI

/// Court geometry for play diagrams, in metres (see `JournalCourtKind`), with room
/// around the lines for inbounders and labels.
enum JournalPlayCourt {
    static let margin = 1.3

    /// The drawing's size in metres, margins included.
    static func canvas(_ kind: JournalCourtKind) -> CGSize {
        let size = kind.size
        return CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
    }

    static func aspectRatio(_ kind: JournalCourtKind) -> CGFloat {
        let c = canvas(kind)
        return c.width / c.height
    }

    /// Metres to points for a drawing `width` points wide.
    static func scale(_ kind: JournalCourtKind, width: CGFloat) -> CGFloat { width / canvas(kind).width }

    static func point(_ p: JournalCourtPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (p.x + margin) * scale, y: (p.y + margin) * scale)
    }

    // Sizes in metres, from the game plan's diagrams (20 units a metre).
    static let playerRadius = 0.55
    static let numberSize = 0.62
    static let defenderSize = 0.72
    static let noteSize = 0.56
    static let lineWidth = 0.075
    static let courtLineWidth = 0.06
    static let arrowLength = 0.34
    static let screenBar = 0.9
    static let ballRadius = 0.2
}

/// FIBA lines in the game plan's style: half court with the baseline at the
/// top, or the full floor attacking right.
struct JournalPlayCourtLines: Shape {
    let kind: JournalCourtKind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .half: half(&p)
        case .full: full(&p)
        }
        let s = rect.width / JournalPlayCourt.canvas(kind).width
        return p.applying(CGAffineTransform(translationX: JournalPlayCourt.margin, y: JournalPlayCourt.margin)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    /// One end: lines, paint, free-throw half circle, three-point line,
    /// backboard and rim. `y` grows away from the baseline.
    private func half(_ p: inout Path) {
        p.addRect(CGRect(x: 0, y: 0, width: 15, height: 14))
        p.addRect(CGRect(x: 5.05, y: 0, width: 4.9, height: 5.8))
        p.move(to: CGPoint(x: 9.3, y: 5.8))
        p.addArc(center: CGPoint(x: 7.5, y: 5.8), radius: 1.8, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        let basket = CGPoint(x: 7.5, y: 1.575)
        let corner = 2.99 - 1.575
        let start = atan2(corner, 6.6)
        p.move(to: CGPoint(x: 0.9, y: 0))
        p.addLine(to: CGPoint(x: 0.9, y: 2.99))
        p.addArc(center: basket, radius: 6.75, startAngle: .radians(.pi - start), endAngle: .radians(start), clockwise: true)
        p.addLine(to: CGPoint(x: 14.1, y: 0))
        p.move(to: CGPoint(x: 6.6, y: 1.2))
        p.addLine(to: CGPoint(x: 8.4, y: 1.2))
        p.addEllipse(in: CGRect(x: basket.x - 0.375, y: basket.y - 0.375, width: 0.75, height: 0.75))
    }

    /// The whole floor, attacking right: both ends mirrored about half court.
    private func full(_ p: inout Path) {
        p.addRect(CGRect(x: 0, y: 0, width: 28, height: 15))
        p.move(to: CGPoint(x: 14, y: 0))
        p.addLine(to: CGPoint(x: 14, y: 15))
        p.addEllipse(in: CGRect(x: 14 - 1.8, y: 7.5 - 1.8, width: 3.6, height: 3.6))
        for side in [false, true] {
            func x(_ v: Double) -> Double { side ? 28 - v : v }
            p.addRect(CGRect(x: min(x(0), x(5.8)), y: 5.05, width: 5.8, height: 4.9))
            // Free-throw half circle, towards half court.
            p.move(to: CGPoint(x: x(5.8), y: 5.7))
            p.addArc(center: CGPoint(x: x(5.8), y: 7.5), radius: 1.8, startAngle: .degrees(-90), endAngle: .degrees(90),
                     clockwise: side)
            let basket = CGPoint(x: x(1.575), y: 7.5)
            let corner = 2.99 - 1.575
            let a = atan2(6.6, corner)
            p.move(to: CGPoint(x: x(0), y: 0.9))
            p.addLine(to: CGPoint(x: x(2.99), y: 0.9))
            if side {
                p.addArc(center: basket, radius: 6.75, startAngle: .radians(-(.pi - a)), endAngle: .radians(.pi - a),
                         clockwise: true)
            } else {
                p.addArc(center: basket, radius: 6.75, startAngle: .radians(-a), endAngle: .radians(a), clockwise: false)
            }
            p.addLine(to: CGPoint(x: x(0), y: 14.1))
            p.move(to: CGPoint(x: x(1.2), y: 6.6))
            p.addLine(to: CGPoint(x: x(1.2), y: 8.4))
            p.addEllipse(in: CGRect(x: basket.x - 0.375, y: basket.y - 0.375, width: 0.75, height: 0.75))
        }
    }
}

/// One step of a play, drawn like the game plan: the court, the actions in
/// ink, defenders as X (the one to read in amber), players as blue circles
/// and dashed circles where they end up. Pass `frame` to draw a moment of
/// the playback instead: players where they are, actions faint.
/// `compact` is for thumbnails: bigger marks, solid players, no numbers.
struct JournalPlayDiagramView: View {
    let diagram: JournalPlayDiagram
    let court: JournalCourtKind
    var frame: JournalPlayMath.PlayFrame?
    var compact = false
    /// The editor's Move tool: a dot on each bend point, to drag.
    var showsBends = false
    /// The editor's selection, haloed in the offense blue.
    var highlight: JournalPlayMath.PlayHit?

    /// Marks grow in thumbnails and on a small court (the full court on a
    /// phone) so players and numbers stay readable.
    private func markScale(_ s: CGFloat) -> CGFloat { compact ? 1.8 : max(1, 17 / s) }

    var body: some View {
        Canvas { context, size in
            let s = JournalPlayCourt.scale(court, width: size.width)
            let lines = JournalPlayCourtLines(kind: court).path(in: CGRect(origin: .zero, size: size))
            context.stroke(lines, with: .color(JPalette.courtLine),
                           lineWidth: max(0.6, JournalPlayCourt.courtLineWidth * s))
            draw(in: &context, scale: s)
        }
        .aspectRatio(JournalPlayCourt.aspectRatio(court), contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The marks (no court lines), at `s` points a metre.
    func draw(in context: inout GraphicsContext, scale s: CGFloat) {
        let ink = GraphicsContext.Shading.color(JPalette.ink)
        let k = markScale(s)
        let width = compact ? max(0.8, JournalPlayCourt.lineWidth * s * k) : max(1.2, JournalPlayCourt.lineWidth * s * min(k, 1.3))
        let r = JournalPlayCourt.playerRadius * s * k

        // Actions under the players; faint while the play moves.
        var actionLayer = context
        if frame != nil { actionLayer.opacity = 0.22 }
        if case .action(let i)? = highlight, diagram.actions.indices.contains(i) {
            var halo = context
            halo.opacity = 0.35
            drawAction(diagram.actions[i], in: &halo, scale: s, k: k, shading: .color(JPalette.play),
                       width: width * 3.2, radius: r, keepsColor: true)
        }
        for action in diagram.actions {
            drawAction(action, in: &actionLayer, scale: s, k: k, shading: ink, width: width, radius: r)
        }
        if showsBends {
            let dot = max(4, r * 0.32)
            for action in diagram.actions {
                for bend in action.path.dropFirst().dropLast() {
                    let c = JournalPlayCourt.point(bend, scale: s)
                    let circle = Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot, width: 2 * dot, height: 2 * dot))
                    context.fill(circle, with: .color(JPalette.background))
                    context.stroke(circle, with: .color(JPalette.play), lineWidth: max(1, width))
                }
            }
        }

        // Where players end up.
        if frame == nil {
            for spot in JournalPlayMath.endSpots(diagram) {
                let c = JournalPlayCourt.point(spot.at, scale: s)
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                context.stroke(ring, with: .color(JPalette.play),
                               style: StrokeStyle(lineWidth: max(compact ? 0.7 : 1, width * 0.85),
                                                  dash: compact ? [1.5, 1.5] : [3, 3]))
                if !compact {
                    context.draw(label("\(spot.number)", size: JournalPlayCourt.numberSize * s * k, weight: .regular)
                        .foregroundStyle(.secondary), at: c)
                }
            }
        }

        // Defenders.
        for defender in diagram.defense {
            let c = JournalPlayCourt.point(defender.at, scale: s)
            context.draw(Text(verbatim: "X")
                .font(.system(size: JournalPlayCourt.defenderSize * s * (compact ? 1.4 : k), weight: .semibold))
                .foregroundStyle(defender.isRead ? JPalette.read : Color.secondary), at: c)
        }

        // Players and the ball.
        for player in diagram.offense {
            let at = frame?.players[player.number] ?? player.at
            let c = JournalPlayCourt.point(at, scale: s)
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            if compact {
                context.fill(circle, with: .color(JPalette.play))
                continue
            }
            context.fill(circle, with: .color(JPalette.background))
            context.fill(circle, with: .color(JPalette.play.opacity(0.14)))
            context.stroke(circle, with: .color(JPalette.play), lineWidth: max(1.2, width * 1.15))
            context.draw(label("\(player.number)", size: JournalPlayCourt.numberSize * s * k, weight: .semibold)
                .foregroundStyle(JPalette.ink), at: c)
        }
        // Every ball beside its holder (a second ball on the same player on
        // the other shoulder), or in flight.
        let ballsAt: [CGPoint] = {
            if let frame { return frame.balls.map { JournalPlayCourt.point($0.at, scale: s) } }
            return diagram.balls.compactMap { diagram.player($0) }.map { JournalPlayCourt.point($0.at, scale: s) }
        }()
        var drawnAt: [CGPoint] = []
        for ball in ballsAt {
            let br = JournalPlayCourt.ballRadius * s * k
            let shared = drawnAt.filter { hypot($0.x - ball.x, $0.y - ball.y) < 0.5 }.count
            drawnAt.append(ball)
            let side: CGFloat = shared % 2 == 0 ? 1 : -1
            let c = CGPoint(x: ball.x + side * r * 0.78, y: ball.y - r * (0.78 - 0.9 * CGFloat(shared / 2)))
            let dot = Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br))
            context.fill(dot, with: .color(JCategory.court.color))
            context.stroke(dot, with: .color(JPalette.background), lineWidth: max(1, width * 0.7))
        }

        // The selected player or defender: a ring around it.
        let ringAt: CGPoint? = {
            switch highlight {
            case .player(let n)?: return diagram.player(n).map { JournalPlayCourt.point($0.at, scale: s) }
            case .defender(let i)? where diagram.defense.indices.contains(i):
                return JournalPlayCourt.point(diagram.defense[i].at, scale: s)
            default: return nil
            }
        }()
        if let c = ringAt {
            let rr = r * 1.4
            let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
            context.stroke(ring, with: .color(JPalette.play), lineWidth: max(1.5, width * 1.3))
        }

        // Notes on the court; a lone mark (①) in ink, like the game plan.
        for note in diagram.notes where frame == nil && !compact {
            let mark = note.text.count == 1
            context.draw(Text(verbatim: note.text)
                .font(.system(size: (mark ? JournalPlayCourt.defenderSize : JournalPlayCourt.noteSize) * s * k,
                              weight: mark ? .semibold : .regular))
                .foregroundStyle(mark ? JPalette.ink : Color.secondary), at: JournalPlayCourt.point(note.at, scale: s))
        }
    }

    private func label(_ text: String, size: CGFloat, weight: Font.Weight) -> Text {
        Text(verbatim: text).font(.system(size: size, weight: weight)).monospacedDigit()
    }

    // MARK: - Actions

    private func drawAction(_ action: JournalPlayDiagram.Action, in context: inout GraphicsContext, scale s: CGFloat,
                            k: CGFloat, shading: GraphicsContext.Shading, width: CGFloat, radius r: CGFloat,
                            keepsColor: Bool = false) {
        var points = action.path.map { JournalPlayCourt.point($0, scale: s) }
        guard points.count >= 2 else { return }
        // Leave the player's circle, and stop short of where it lands.
        points[0] = Self.moved(points[0], toward: points[1], by: r)
        if action.kind != .screen {
            let n = points.count - 1
            points[n] = Self.moved(points[n], toward: points[n - 1], by: r + width)
        }
        let curve = action.isStraight ? Self.polyline(points) : Self.smooth(points)
        // A shot is red, and so is a dribble that finishes at the rim (a drive).
        let toRim = action.kind == .shot
            || (action.kind == .dribble && action.path.last.map(court.isAtBasket) == true)
        // (The selection halo keeps its blue.)
        let shading = toRim && !keepsColor ? GraphicsContext.Shading.color(JPalette.shot) : shading
        switch action.kind {
        case .cut, .shot:
            context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            arrow(at: points, in: &context, scale: s, k: k, shading: shading)
        case .pass:
            context.stroke(curve, with: shading,
                           style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [5 * width / 1.5, 4 * width / 1.5]))
            arrow(at: points, in: &context, scale: s, k: k, shading: shading)
        case .dribble:
            context.stroke(Self.zigzag(along: curve, scale: s * k), with: shading,
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            arrow(at: points, in: &context, scale: s, k: k, shading: shading)
        case .screen:
            context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: width * 1.15, lineCap: .round))
            let end = points[points.count - 1], before = points[points.count - 2]
            let dx = end.x - before.x, dy = end.y - before.y
            let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
            let half = JournalPlayCourt.screenBar * s * k / 2
            var bar = Path()
            bar.move(to: CGPoint(x: end.x - dy / len * half, y: end.y + dx / len * half))
            bar.addLine(to: CGPoint(x: end.x + dy / len * half, y: end.y - dx / len * half))
            context.stroke(bar, with: shading, style: StrokeStyle(lineWidth: width * 1.15, lineCap: .round))
        }
    }

    private func arrow(at points: [CGPoint], in context: inout GraphicsContext, scale s: CGFloat, k: CGFloat,
                       shading: GraphicsContext.Shading) {
        let end = points[points.count - 1], before = points[points.count - 2]
        let dx = end.x - before.x, dy = end.y - before.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let ux = dx / len, uy = dy / len
        let l = JournalPlayCourt.arrowLength * s * k, w = l * 0.55
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - ux * l - uy * w, y: end.y - uy * l + ux * w))
        head.addLine(to: CGPoint(x: end.x - ux * l + uy * w, y: end.y - uy * l - ux * w))
        head.closeSubpath()
        context.fill(head, with: shading)
    }

    static func moved(_ p: CGPoint, toward q: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = q.x - p.x, dy = q.y - p.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > distance * 1.5 else { return p }
        return CGPoint(x: p.x + dx / len * distance, y: p.y + dy / len * distance)
    }

    /// Straight segments through the points, corners kept.
    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// Straight for two points, a curve through the middle points otherwise
    /// (Catmull-Rom), like the game plan's drawn curves.
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    /// The dribble's zigzag: half-metre teeth either side of the path,
    /// straight for the last stretch before the arrow.
    static func zigzag(along curve: Path, scale s: CGFloat) -> Path {
        let samples = sample(curve, step: 0.5 * s)
        var zig = Path()
        guard let first = samples.first else { return curve }
        zig.move(to: first)
        let amplitude = 0.25 * s
        for i in 1..<max(samples.count - 1, 1) {
            let a = samples[i - 1], b = samples[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
            let o = (i % 2 == 0 ? 1 : -1) * amplitude
            zig.addLine(to: CGPoint(x: b.x - dy / len * o, y: b.y + dx / len * o))
        }
        if let last = samples.last { zig.addLine(to: last) }
        return zig
    }

    /// Points every `step` along a path.
    static func sample(_ path: Path, step: CGFloat) -> [CGPoint] {
        var dense: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let p): dense.append(p)
            case .line(let p):
                if let a = dense.last { for k in 1...8 { dense.append(lerp(a, p, CGFloat(k) / 8)) } }
            case .curve(let p, let c1, let c2):
                if let a = dense.last {
                    for k in 1...16 {
                        let t = CGFloat(k) / 16, u = 1 - t
                        dense.append(CGPoint(
                            x: u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x,
                            y: u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y))
                    }
                }
            case .quadCurve(let p, let c):
                if let a = dense.last {
                    for k in 1...12 {
                        let t = CGFloat(k) / 12, u = 1 - t
                        dense.append(CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * p.x,
                                             y: u * u * a.y + 2 * u * t * c.y + t * t * p.y))
                    }
                }
            case .closeSubpath: break
            }
        }
        guard var last = dense.first else { return [] }
        var out = [last]
        var carried: CGFloat = 0
        for p in dense.dropFirst() {
            let d = hypot(p.x - last.x, p.y - last.y)
            carried += d
            if carried >= step {
                out.append(p)
                carried = 0
            }
            last = p
        }
        if let end = dense.last, out.last != end { out.append(end) }
        return out
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

/// The legend from the game plan: how to read every diagram.
struct JournalPlayLegend: View {
    private struct Item: Identifiable {
        let id: Int
        let title: JPString
        let diagram: JournalPlayDiagram
    }

    private static func item(_ id: Int, _ title: JPString, _ diagram: JournalPlayDiagram) -> Item {
        Item(id: id, title: title, diagram: diagram)
    }

    /// The game plan's legend, in its order, plus the ball.
    private static let items: [Item] = {
        typealias P = JournalCourtPoint
        let line = [P(-0.6, 1), P(2.8, 1)]
        return [
            item(0, "Offense", JournalPlayDiagram(offense: [.init(number: 1, at: P(1, 1))])),
            item(1, "Defender", JournalPlayDiagram(defense: [.init(at: P(1, 1))])),
            item(2, "Cut or run", JournalPlayDiagram(actions: [.init(kind: .cut, player: 0, path: line)])),
            item(3, "Pass", JournalPlayDiagram(actions: [.init(kind: .pass, player: 0, path: line)])),
            item(9, "Shot (a drive to the basket is red too)",
                 JournalPlayDiagram(actions: [.init(kind: .shot, player: 0, path: line)])),
            item(4, "legend.dribble",
                 JournalPlayDiagram(actions: [.init(kind: .dribble, player: 0, path: line)])),
            item(5, "Screen", JournalPlayDiagram(actions: [.init(kind: .screen, player: 0, path: [P(-0.6, 1), P(2.2, 1)])])),
            item(6, "End spot", JournalPlayDiagram(offense: [.init(number: 1, at: P(-3, 1))],
                                            actions: [.init(kind: .cut, player: 1, path: [P(-3, 1), P(1, 1)])])),
            item(7, "Defender to read", JournalPlayDiagram(defense: [.init(at: P(1, 1), isRead: true)])),
            item(8, "Ball", JournalPlayDiagram(offense: [.init(number: 1, at: P(1, 1))], ball: 1)),
        ]
    }()

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: JSpacing.s) {
            ForEach(Self.items) { item in
                HStack(spacing: JSpacing.xs) {
                    JournalPlayMark(diagram: item.diagram)
                        .frame(width: 56, height: 28)
                    JText(item.title)
                        .font(.footnote)
                }
            }
        }
    }
}

/// A tiny drawing of a mark, no court: the legend and the editor's tools.
/// Draws a 4 × 2 m window around the point (1, 1).
struct JournalPlayMark: View {
    let diagram: JournalPlayDiagram

    var body: some View {
        Canvas { context, size in
            // A 4 × 2 m window around (1, 1).
            let s = size.height / 2
            context.translateBy(x: size.width / 2 - (1 + JournalPlayCourt.margin) * s, y: size.height / 2 - (1 + JournalPlayCourt.margin) * s)
            JournalPlayDiagramView(diagram: diagram, court: .half).draw(in: &context, scale: s)
        }
        .accessibilityHidden(true)
    }
}
