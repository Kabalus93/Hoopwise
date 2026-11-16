import Foundation

// SCRIBBLE (16 November 2026, Luther: "the iPad would interpret what has been
// drawn — an arrow for a cut, a discontinued arrow for a pass, a flat-ended
// line for a screen — and have the player involved move or pass"; dribbles
// too). Pure: Pencil strokes, already in court metres and in the order they
// were drawn, become the editor's own actions through `lineStart` and
// `adding`, so a scribbled cut is exactly a drawn one.
//
// What is read:
// · a LINE starts on a player (their current spot) — anything else (writing,
//   a circle in the paint) is left as ink;
// · DASHES: three or more short strokes in a row, each starting near where
//   the last ended and heading the same way → a pass to the teammate nearest
//   its end;
// · a ZIGZAG (the line swings from side to side at least four times) → a
//   dribble along its middle;
// · the END decides the rest: a short bar across it → a screen; an
//   arrowhead (a V, one or two short strokes, or the line doubling back at
//   its tip) or nothing → a cut.

nonisolated enum JournalPlayScribble {
    typealias P = JournalCourtPoint

    struct Result: Equatable, Sendable {
        /// The diagram with the actions read added after its own.
        var diagram: JournalPlayDiagram
        /// The strokes that became actions (indices into the input); the rest
        /// stay on the court as ink.
        var used: Set<Int>
    }

    /// A line starts on a player within this many metres of them.
    static let startReach = 1.4
    /// Shorter strokes are dashes, arrowheads or screen bars, not lines.
    static let decorationMax = 1.1
    /// An arrowhead or bar this near a line's end belongs to it.
    static let endReach = 0.9
    /// An arrowhead or bar is at most this long (a bar drawn wide is still
    /// a bar).
    static let endMarkMax = 1.6
    /// A pass ends on the teammate nearest its end, within twice this.
    static let receiverReach = 1.2

    private enum Ending { case none, arrow, bar }

    private struct Line {
        var strokes: [Int]
        var points: [P]
        var dashed: Bool
    }

    static func read(_ strokes: [[P]], on base: JournalPlayDiagram, court: JournalCourtKind = .half) -> Result {
        let paths = strokes.map { resampled($0, step: 0.05) }
        let lengths = paths.map(JournalPlayMath.length(of:))

        // Lines: every long stroke, and every run of dashes.
        var lines: [Line] = []
        var chain: [Int] = []
        func closeChain() {
            if chain.count >= 3 {
                lines.append(Line(strokes: chain, points: chain.flatMap { paths[$0] }, dashed: true))
            }
            chain = []
        }
        for i in paths.indices where paths[i].count >= 2 {
            if lengths[i] >= decorationMax {
                closeChain()
                lines.append(Line(strokes: [i], points: paths[i], dashed: false))
                continue
            }
            let dash = paths[i]
            let straight = straightness(dash) > 0.8 && lengths[i] >= 0.12
            if let first = chain.first, let last = chain.last, straight {
                let chainEnd = paths[last][paths[last].count - 1]
                let chainDirection = unit(from: paths[first][0], to: chainEnd)
                let dashDirection = unit(from: dash[0], to: dash[dash.count - 1])
                if dash[0].distance(to: chainEnd) <= 1.3, dot(chainDirection, dashDirection) > cos(55 * .pi / 180) {
                    chain.append(i)
                    continue
                }
            }
            closeChain()
            if straight { chain = [i] }
        }
        closeChain()
        lines.sort { $0.strokes[0] < $1.strokes[0] }

        let dashes = Set(lines.filter(\.dashed).flatMap(\.strokes))
        var used = Set<Int>()
        var diagram = base

        for line in lines where !line.strokes.contains(where: used.contains) {
            guard let start = JournalPlayMath.lineStart(at: line.points[0], in: diagram, radius: startReach) else { continue }

            var points = line.points
            var ending = Ending.none
            if !line.dashed {
                let (trimmed, tail) = trimmingTail(points)
                points = trimmed
                ending = tail
            }
            guard points.count >= 2 else { continue }
            let end = points[points.count - 1]
            let arrival = unit(from: point(back: 0.6, in: points), to: end)

            // Arrowheads and bars drawn as their own strokes.
            var decorations: [Int] = []
            var arrows = 0, bars = 0
            for j in paths.indices where !dashes.contains(j) && !used.contains(j) && !line.strokes.contains(j)
                && lengths[j] < endMarkMax {
                guard paths[j].contains(where: { $0.distance(to: end) <= endReach }) else { continue }
                decorations.append(j)
                let d = paths[j]
                if straightness(d) >= 0.85 {
                    let across = acos(min(1, abs(dot(arrival, unit(from: d[0], to: d[d.count - 1]))))) * 180 / .pi
                    if across >= 60, JournalPlayMath.distanceToSegment(end, d[0], d[d.count - 1]) <= 0.45 {
                        bars += 1
                    } else {
                        arrows += 1
                    }
                } else {
                    arrows += 1
                }
            }
            if arrows > 0 { ending = .arrow } else if bars > 0, ending == .none { ending = .bar }

            let kind: JournalPlayDiagram.ActionKind
            var along = [start.from] + points.dropFirst()
            if line.dashed {
                kind = .pass
                along = [start.from, end]
            } else if let middle = zigzagMiddle(points) {
                kind = .dribble
                along = [start.from] + middle.dropFirst()
            } else {
                kind = ending == .bar ? .screen : .cut
            }
            let radius = kind == .pass ? receiverReach : startReach
            guard let added = JournalPlayMath.adding(kind, by: start.player, along: along, to: diagram,
                                                     radius: radius, shape: .curved, court: court) else { continue }
            diagram = added
            used.formUnion(line.strokes)
            used.formUnion(decorations)
        }
        return Result(diagram: diagram, used: used)
    }

    // MARK: - Shapes

    /// A line drawn in one stroke that ends in its own arrowhead (the pen
    /// runs to the tip, then back along a side of the V) or bar (the pen
    /// turns across): the line up to the turn, and what the turn was.
    private static func trimmingTail(_ points: [P]) -> ([P], Ending) {
        let total = JournalPlayMath.length(of: points)
        guard total >= 1.6, points.count > 8 else { return (points, .none) }
        let cumulative = cumulativeLengths(points)
        let reference = unit(from: point(at: total - 1.6, in: points, cumulative: cumulative),
                             to: point(at: total - 1.0, in: points, cumulative: cumulative))
        guard let windowStart = cumulative.firstIndex(where: { $0 >= total - 1.0 }) else { return (points, .none) }
        for i in windowStart..<(points.count - 1) {
            guard let j = cumulative[i...].firstIndex(where: { $0 >= cumulative[i] + 0.25 }) else { break }
            let ahead = unit(from: points[i], to: points[j])
            guard dot(ahead, reference) < cos(70 * .pi / 180) else { continue }
            let tail = JournalCourtPoint(points[points.count - 1].x - points[i].x, points[points.count - 1].y - points[i].y)
            let back = -(tail.x * reference.x + tail.y * reference.y)
            let side = abs(tail.x * reference.y - tail.y * reference.x)
            if back > 0.12 { return (Array(points[...i]), .arrow) }
            if side > 0.3 { return (Array(points[...i]), .bar) }
            return (Array(points[...i]), .none)
        }
        return (points, .none)
    }

    /// A zigzag's middle line: nil unless the stroke swings from side to side
    /// of its own running average at least four times, each swing over
    /// 0.12 m (a hand's wobble stays well under).
    static func zigzagMiddle(_ points: [P]) -> [P]? {
        let p = resampled(points, step: 0.08)
        let half = 6
        guard p.count > 2 * half + 4 else { return nil }
        let middle: [P] = p.indices.map { i in
            let lo = max(0, i - half), hi = min(p.count - 1, i + half)
            let slice = p[lo...hi]
            return JournalCourtPoint(slice.map(\.x).reduce(0, +) / Double(slice.count),
                                     slice.map(\.y).reduce(0, +) / Double(slice.count))
        }
        var swings = 0
        var side = 0
        for i in 1..<(p.count - 1) {
            let along = unit(from: middle[i - 1], to: middle[i + 1])
            let off = JournalCourtPoint(p[i].x - middle[i].x, p[i].y - middle[i].y)
            let deviation = along.x * off.y - along.y * off.x
            guard abs(deviation) > 0.12 else { continue }
            let now = deviation > 0 ? 1 : -1
            if now != side {
                if side != 0 { swings += 1 }
                side = now
            }
        }
        guard swings >= 4 else { return nil }
        // The ends of the running average fall short; keep the drawn ends.
        return [p[0]] + middle.dropFirst(half).dropLast(half) + [p[p.count - 1]]
    }

    // MARK: - Geometry

    /// The stroke as points about `step` metres apart.
    static func resampled(_ points: [P], step: Double) -> [P] {
        guard var last = points.first else { return [] }
        var out = [last]
        var carried = 0.0
        for next in points.dropFirst() {
            var from = last
            var gap = from.distance(to: next)
            while carried + gap >= step {
                let t = (step - carried) / gap
                let p = JournalCourtPoint(from.x + (next.x - from.x) * t, from.y + (next.y - from.y) * t)
                out.append(p)
                from = p
                gap = from.distance(to: next)
                carried = 0
            }
            carried += gap
            last = next
        }
        if let end = points.last, out.last.map({ $0.distance(to: end) > 0.01 }) ?? true { out.append(end) }
        return out
    }

    /// Chord over length: 1 for a straight stroke.
    private static func straightness(_ points: [P]) -> Double {
        let length = JournalPlayMath.length(of: points)
        guard length > 0, let a = points.first, let b = points.last else { return 0 }
        return a.distance(to: b) / length
    }

    private static func cumulativeLengths(_ points: [P]) -> [Double] {
        var out = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { out.append(out[out.count - 1] + a.distance(to: b)) }
        return out
    }

    private static func point(at distance: Double, in points: [P], cumulative: [Double]) -> P {
        let index = cumulative.firstIndex { $0 >= distance } ?? (points.count - 1)
        return points[max(0, index)]
    }

    /// The point `distance` metres back from the end of the line.
    private static func point(back distance: Double, in points: [P]) -> P {
        let cumulative = cumulativeLengths(points)
        return point(at: max(0, cumulative[cumulative.count - 1] - distance), in: points, cumulative: cumulative)
    }

    private static func unit(from a: P, to b: P) -> P {
        let length = a.distance(to: b)
        guard length > 0 else { return JournalCourtPoint(0, 0) }
        return JournalCourtPoint((b.x - a.x) / length, (b.y - a.y) / length)
    }

    private static func dot(_ a: P, _ b: P) -> Double { a.x * b.x + a.y * b.y }
}
