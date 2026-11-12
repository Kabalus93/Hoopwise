import Foundation

// The rules of drawing a play: where a new play starts, what a touch hits,
// how a finger's path becomes a cut or a pass, and what moves with a player.
// Pure functions on `JournalPlayDiagram`, in metres; the editor only converts
// points and calls these.

nonisolated extension JournalPlayMath {
    /// A new play's first step: five out on the half court (1 at the top,
    /// 2 and 3 on the wings, 4 and 5 in the corners), or the five spread
    /// in the back court, 1 with the ball, on the full court.
    static func defaultAlignment(_ court: JournalCourtKind) -> JournalPlayDiagram {
        switch court {
        case .half:
            JournalPlayDiagram(offense: [
                .init(number: 1, at: JournalCourtPoint(7.5, 9.6)), .init(number: 2, at: JournalCourtPoint(12.6, 6.6)),
                .init(number: 3, at: JournalCourtPoint(2.4, 6.6)), .init(number: 4, at: JournalCourtPoint(13.9, 1.2)),
                .init(number: 5, at: JournalCourtPoint(1.1, 1.2)),
            ], ball: 1)
        case .full:
            JournalPlayDiagram(offense: [
                .init(number: 1, at: JournalCourtPoint(5.5, 7.5)), .init(number: 2, at: JournalCourtPoint(9, 13)),
                .init(number: 3, at: JournalCourtPoint(9, 2)), .init(number: 4, at: JournalCourtPoint(3, 9.5)),
                .init(number: 5, at: JournalCourtPoint(3, 5.5)),
            ], ball: 1)
        }
    }

    /// The same drawing on the other court. Half court to full court: the
    /// baseline goes to the right (full x = 28 − half y, full y = half x),
    /// and back.
    static func converted(_ diagram: JournalPlayDiagram, from: JournalCourtKind, to: JournalCourtKind) -> JournalPlayDiagram {
        guard from != to else { return diagram }
        let map: (JournalCourtPoint) -> JournalCourtPoint = to == .full
            ? { JournalCourtPoint(28 - $0.y, $0.x) }
            : { JournalCourtPoint($0.y, 28 - $0.x) }
        var out = diagram
        out.offense = diagram.offense.map { .init(number: $0.number, at: map($0.at)) }
        out.defense = diagram.defense.map { .init(at: map($0.at), isRead: $0.isRead) }
        out.actions = diagram.actions.map { .init(kind: $0.kind, player: $0.player, path: $0.path.map(map),
                                                  receiver: $0.receiver, shape: $0.shape) }
        out.notes = diagram.notes.map { .init(text: $0.text, at: map($0.at)) }
        out.cones = diagram.cones.map(map)
        return out
    }

    // MARK: - Paths

    /// A finger's path as a few bend points (Ramer–Douglas–Peucker): keeps
    /// the ends and any point further than `tolerance` metres from the
    /// line, at most `maxPoints`.
    static func simplified(_ points: [JournalCourtPoint], tolerance: Double = 0.4, maxPoints: Int = 5) -> [JournalCourtPoint] {
        guard points.count > 2 else { return points }
        var tolerance = tolerance
        var result = douglasPeucker(points, tolerance)
        while result.count > maxPoints {
            tolerance *= 1.5
            result = douglasPeucker(points, tolerance)
        }
        return result
    }

    private static func douglasPeucker(_ points: [JournalCourtPoint], _ tolerance: Double) -> [JournalCourtPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0, distance = 0.0
        for i in 1..<(points.count - 1) {
            let d = distanceToSegment(points[i], first, last)
            if d > distance { (farthest, distance) = (i, d) }
        }
        guard distance > tolerance else { return [first, last] }
        let left = douglasPeucker(Array(points[...farthest]), tolerance)
        let right = douglasPeucker(Array(points[farthest...]), tolerance)
        return left.dropLast() + right
    }

    static func distanceToSegment(_ p: JournalCourtPoint, _ a: JournalCourtPoint, _ b: JournalCourtPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return p.distance(to: a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1)
        return p.distance(to: JournalCourtPoint(a.x + t * dx, a.y + t * dy))
    }

    /// A finger's path as the line it means. Straight: one segment, with a
    /// corner only where the hand clearly turned (over a metre off the
    /// line) — at most two. Curved: one or two bends, drawn as a smooth
    /// curve, so the hand's shake never reaches the drawing.
    static func shaped(_ points: [JournalCourtPoint], _ shape: JournalPlayDiagram.PathShape) -> [JournalCourtPoint] {
        switch shape {
        case .straight: simplified(points, tolerance: 1.0, maxPoints: 3)
        case .curved: simplified(points, tolerance: 0.7, maxPoints: 4)
        }
    }

    /// The line as it is drawn, in metres: the bend points for a straight
    /// line, else the smooth curve through them (Catmull-Rom, as the
    /// diagram draws it), sampled. Playback and touches follow this.
    static func drawnPath(_ action: JournalPlayDiagram.Action) -> [JournalCourtPoint] {
        let p = action.path
        guard !action.isStraight else { return p }
        var out = [p[0]]
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            let c1 = JournalCourtPoint(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6)
            let c2 = JournalCourtPoint(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6)
            for k in 1...12 {
                let t = Double(k) / 12, u = 1 - t
                out.append(JournalCourtPoint(
                    u * u * u * p1.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p2.x,
                    u * u * u * p1.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p2.y))
            }
        }
        return out
    }

    static func length(of path: [JournalCourtPoint]) -> Double {
        zip(path, path.dropFirst()).map { $0.distance(to: $1) }.reduce(0, +)
    }

    /// Shorter than this, a drag is a tap, not a line.
    static let shortestAction = 0.8

    // MARK: - Touches

    enum PlayHit: Equatable, Sendable {
        case player(Int)
        case defender(Int)
        /// A cone (drill drawings).
        case cone(Int)
        /// The end of an action's path (its dashed ring, for a move).
        case actionEnd(Int)
        /// A bend point inside a line: action, point.
        case actionBend(Int, Int)
        case action(Int)
        case note(Int)
    }

    /// What a touch at `point` lands on, nearest first within `radius`
    /// metres: players, defenders, cones, the ends of lines, lines, notes. Of two
    /// on the same spot, the one drawn on top (the later one).
    static func hit(_ point: JournalCourtPoint, in diagram: JournalPlayDiagram, radius: Double) -> PlayHit? {
        func nearest<T>(_ items: [T], _ distance: (T) -> Double) -> Int? {
            items.indices.reversed().map { ($0, distance(items[$0])) }.filter { $0.1 <= radius }
                .min { $0.1 < $1.1 }?.0
        }
        if let i = nearest(diagram.offense, { $0.at.distance(to: point) }) { return .player(diagram.offense[i].number) }
        if let i = nearest(diagram.defense, { $0.at.distance(to: point) }) { return .defender(i) }
        if let i = nearest(diagram.cones, { $0.distance(to: point) }) { return .cone(i) }
        let moves = diagram.actions.indices.filter { diagram.actions[$0].kind.movesPlayer }
        if let i = nearest(moves, { diagram.actions[$0].path.last?.distance(to: point) ?? .infinity }) {
            return .actionEnd(moves[i])
        }
        let bends = diagram.actions.indices.flatMap { a in
            diagram.actions[a].path.indices.dropFirst().dropLast().map { (a, $0) }
        }
        if let i = nearest(bends, { diagram.actions[$0.0].path[$0.1].distance(to: point) }) {
            return .actionBend(bends[i].0, bends[i].1)
        }
        if let i = nearest(diagram.actions, { action in
            let drawn = drawnPath(action)
            return zip(drawn, drawn.dropFirst()).map { distanceToSegment(point, $0, $1) }.min() ?? .infinity
        }) { return .action(i) }
        if let i = nearest(diagram.notes, { $0.at.distance(to: point) }) { return .note(i) }
        return nil
    }

    /// The player a line drawn from `point` belongs to: the one whose
    /// current end (after their earlier moves) or start is nearest, and
    /// where the new line starts (always their current end, so a screen
    /// can be followed by a roll).
    static func lineStart(at point: JournalCourtPoint, in diagram: JournalPlayDiagram, radius: Double) -> (player: Int, from: JournalCourtPoint)? {
        let candidates = diagram.offense.compactMap { player -> (Int, JournalCourtPoint, Double)? in
            guard let end = endPosition(of: player.number, in: diagram) else { return nil }
            let d = min(end.distance(to: point), player.at.distance(to: point))
            return d <= radius ? (player.number, end, d) : nil
        }
        return candidates.min { $0.2 < $1.2 }.map { ($0.0, $0.1) }
    }

    /// A drawn line added to the step: a cut, dribble or screen along the
    /// finger's path (simplified), or a pass from the passer to whoever is
    /// nearest the finger's end, snapped to them. `nil` when the line is a
    /// tap, or a pass ends on no teammate.
    static func adding(_ kind: JournalPlayDiagram.ActionKind, by player: Int, along points: [JournalCourtPoint],
                       to diagram: JournalPlayDiagram, radius: Double,
                       shape: JournalPlayDiagram.PathShape = .straight,
                       court: JournalCourtKind = .half) -> JournalPlayDiagram? {
        guard let start = points.first, let end = points.last else { return nil }
        var out = diagram
        if kind == .shot {
            // A shot always ends in the rim: the basket nearest the release.
            guard let rim = court.baskets.min(by: { $0.distance(to: end) < $1.distance(to: end) }),
                  start.distance(to: rim) >= shortestAction else { return nil }
            out.actions.append(.init(kind: .shot, player: player, path: [start, rim]))
            return out
        }
        if kind.hasReceiver {
            let receivers = diagram.offense.filter { $0.number != player }.compactMap { other -> (Int, JournalCourtPoint)? in
                endPosition(of: other.number, in: diagram).map { (other.number, $0) }
            }
            guard let (receiver, at) = receivers.min(by: { $0.1.distance(to: end) < $1.1.distance(to: end) }),
                  at.distance(to: end) <= radius * 2, start.distance(to: at) >= shortestAction else { return nil }
            out.actions.append(.init(kind: kind, player: player, path: [start, at], receiver: receiver))
            return out
        }
        let path = shaped(points, shape)
        guard length(of: path) >= shortestAction else { return nil }
        out.actions.append(.init(kind: kind, player: player, path: path, shape: shape))
        return out
    }

    /// A line turned straight or curved. Straight runs start to end; curved
    /// gets a gentle bend at its middle (a fifth of its length to the
    /// side) when it has none, to drag into the curve wanted.
    static func toggledShape(of index: Int, in diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        guard diagram.actions.indices.contains(index), diagram.actions[index].kind.movesPlayer,
              let first = diagram.actions[index].path.first, let last = diagram.actions[index].path.last else { return diagram }
        var out = diagram
        if diagram.actions[index].isStraight {
            if diagram.actions[index].path.count == 2 {
                let dx = last.x - first.x, dy = last.y - first.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 0 else { return diagram }
                let off = max(0.6, length * 0.2)
                out.actions[index].path.insert(JournalCourtPoint((first.x + last.x) / 2 - dy / length * off,
                                                                 (first.y + last.y) / 2 + dx / length * off), at: 1)
            }
            out.actions[index].shape = .curved
        } else {
            out.actions[index].path = [first, last]
            out.actions[index].shape = .straight
        }
        return out
    }

    /// A bend point inside a line dragged to `point`.
    static func moving(bend point: Int, of index: Int, to at: JournalCourtPoint, in diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        guard diagram.actions.indices.contains(index),
              diagram.actions[index].path.indices.dropFirst().dropLast().contains(point) else { return diagram }
        var out = diagram
        out.actions[index].path[point] = at
        return out
    }

    // MARK: - Changes

    /// A player dragged to `point`. Lines that start where they stood
    /// start from the new spot, and passes to them land there.
    static func moving(player number: Int, to point: JournalCourtPoint, in diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        guard let index = diagram.offense.firstIndex(where: { $0.number == number }) else { return diagram }
        let old = diagram.offense[index].at
        var out = diagram
        out.offense[index].at = point
        out.actions = diagram.actions.map { action in
            var action = action
            if action.player == number, action.path.first.map({ $0.distance(to: old) < 0.05 }) == true {
                action.path[0] = point
            }
            if action.kind.hasReceiver, action.receiver == number,
               let last = action.path.last, last.distance(to: old) < 0.05 {
                action.path[action.path.count - 1] = point
            }
            return action
        }
        return out
    }

    /// The end of a line dragged to `point`: the player's later lines
    /// start there, and passes to or from that spot follow.
    static func moving(endOf index: Int, to point: JournalCourtPoint, in diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        guard diagram.actions.indices.contains(index), let old = diagram.actions[index].path.last else { return diagram }
        let player = diagram.actions[index].player
        var out = diagram
        out.actions[index].path[out.actions[index].path.count - 1] = point
        for i in out.actions.indices where i != index {
            let action = out.actions[i]
            let fromHere = action.path.first.map { $0.distance(to: old) < 0.05 } == true
            let toHere = action.path.last.map { $0.distance(to: old) < 0.05 } == true
            if fromHere, action.player == player { out.actions[i].path[0] = point }
            if toHere, action.kind.hasReceiver, action.receiver == player {
                out.actions[i].path[action.path.count - 1] = point
            }
        }
        return out
    }

    /// Takes away what was hit: a line, a defender, a cone or a note.
    /// Players stay (a play always has five; a drill drawing removes one
    /// with `removing(player:)`); a player's own lines are erased one by one.
    static func erasing(_ hit: PlayHit, in diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        var out = diagram
        switch hit {
        case .player: break
        case .defender(let i): if out.defense.indices.contains(i) { out.defense.remove(at: i) }
        case .cone(let i): if out.cones.indices.contains(i) { out.cones.remove(at: i) }
        case .action(let i), .actionEnd(let i), .actionBend(let i, _):
            if out.actions.indices.contains(i) { out.actions.remove(at: i) }
        case .note(let i): if out.notes.indices.contains(i) { out.notes.remove(at: i) }
        }
        return out
    }

    /// A player taken off the court (drill drawings): their lines, the
    /// passes thrown to them and their ball go with them. The others keep
    /// their numbers.
    static func removing(player number: Int, from diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        var out = diagram
        out.offense.removeAll { $0.number == number }
        out.actions.removeAll { $0.player == number || ($0.kind.hasReceiver && $0.receiver == number) }
        out.balls.removeAll { $0 == number }
        return out
    }
}
