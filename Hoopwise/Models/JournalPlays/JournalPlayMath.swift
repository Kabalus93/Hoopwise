import Foundation

/// The play rules from HoopWise Journal (its `JournalMath`, plays part).
/// Pure functions on `JournalPlayDiagram`, in metres.
nonisolated enum JournalPlayMath {}

// The rules of a drawn play: where each step leaves everyone, where the
// next step starts, and where everyone is at a moment of the playback.

nonisolated extension JournalPlayMath {
    /// Where `number` is when the step's actions are done: the end of their
    /// cut, dribble or screen, else where they started.
    static func endPosition(of number: Int, in diagram: JournalPlayDiagram) -> JournalCourtPoint? {
        let moves = diagram.actions.filter { $0.player == number && $0.kind.movesPlayer }
        if let last = moves.last?.path.last { return last }
        return diagram.player(number)?.at
    }

    /// Who has the ball when the step's actions are done: the receiver of
    /// the last pass, else whoever had it. With several balls, the first.
    static func ballAfter(_ diagram: JournalPlayDiagram) -> Int? {
        ballsAfter(diagram).first
    }

    /// Who holds each ball when the step's actions are done, the passes
    /// thrown in playback order.
    static func ballsAfter(_ diagram: JournalPlayDiagram) -> [Int] {
        var holders = diagram.balls
        for pass in schedule(diagram).throwsInOrder.map({ diagram.actions[$0.index] }) {
            transfer(pass, holders: &holders)
        }
        return holders
    }

    /// One action on the step's timeline, in beats.
    struct Timed: Equatable, Sendable {
        var index: Int
        var start: Double
        var end: Double
    }

    /// The step's timeline (Luther, November 2026: "the logic behind what
    /// happens first is inconsistent" — a pass drawn to a cutter flew before
    /// the cutter moved, then the ball jumped back to them). The actions run
    /// in the order they are DRAWN, each as soon as it can:
    /// · a move starts when its player is free (a dribble also needs the ball);
    /// · a pass, shot or hand-off leaves when the passer is free and has the
    ///   ball; to a teammate who moved earlier in the drawing it is a LEAD
    ///   pass, timed to land as they arrive — the editor drew it to where
    ///   they end up;
    /// · the passer can move on just after letting go (pass and cut); the
    ///   receiver waits for the catch before any move drawn after it.
    /// Everyone who is free moves at once, as before.
    struct Schedule: Equatable, Sendable {
        var items: [Timed]
        var total: Double
        var throwsInOrder: [Timed]
    }

    static func beats(_ kind: JournalPlayDiagram.ActionKind) -> Double {
        switch kind {
        case .cut, .dribble, .screen: return playMoveBeats
        case .pass, .shot: return 1
        case .handoff: return 0.6
        }
    }

    static func schedule(_ diagram: JournalPlayDiagram) -> Schedule {
        var ready: [Int: Double] = [:]
        var lastMoveEnd: [Int: Double] = [:]
        // When each ball is in hand: (holder, from).
        var balls: [(holder: Int, from: Double)] = diagram.balls.map { ($0, 0) }
        var items: [Timed] = []
        for (i, action) in diagram.actions.enumerated() {
            let p = action.player
            let duration = beats(action.kind)
            if action.kind.movesPlayer {
                var start = ready[p] ?? 0
                if action.kind == .dribble, let ball = balls.first(where: { $0.holder == p }) {
                    start = max(start, ball.from)
                }
                let end = start + duration
                ready[p] = end
                lastMoveEnd[p] = end
                items.append(Timed(index: i, start: start, end: end))
            } else if action.kind.throwsBall {
                let ballIndex = balls.firstIndex(where: { $0.holder == p }) ?? (balls.count == 1 ? 0 : nil)
                var start = max(ready[p] ?? 0, ballIndex.map { balls[$0].from } ?? 0)
                if let r = action.receiver, let arrives = lastMoveEnd[r], arrives - duration > start {
                    start = arrives - duration
                }
                let end = start + duration
                ready[p] = start + min(duration, 0.35)
                if action.kind == .shot {
                    if let b = ballIndex { balls.remove(at: b) }
                } else if let r = action.receiver {
                    if let b = ballIndex { balls[b] = (r, end) } else { balls.append((r, end)) }
                    ready[r] = max(ready[r] ?? 0, end)
                }
                items.append(Timed(index: i, start: start, end: end))
            }
        }
        let total = items.map(\.end).max() ?? 0
        let throwsInOrder = items.filter { diagram.actions[$0.index].kind.throwsBall }
            .enumerated().sorted { ($0.element.end, $0.offset) < ($1.element.end, $1.offset) }.map(\.element)
        return Schedule(items: items, total: total, throwsInOrder: throwsInOrder)
    }

    /// Which ball a pass throws: the passer's; with one ball on the floor,
    /// that ball whoever drew it (a play has one ball, and a pass always
    /// moved it). `nil` when the passer has none among several.
    static func ballIndex(thrownBy pass: JournalPlayDiagram.Action, holders: [Int]) -> Int? {
        holders.firstIndex(of: pass.player) ?? (holders.count == 1 ? 0 : nil)
    }

    /// The ball the pass throws goes to its receiver; a pass from a player
    /// with no ball among several brings a ball into play. A shot's ball
    /// leaves play (it is at the rim; the next step gives it out again).
    static func transfer(_ pass: JournalPlayDiagram.Action, holders: inout [Int]) {
        if pass.kind == .shot {
            if let i = ballIndex(thrownBy: pass, holders: holders) { holders.remove(at: i) }
            return
        }
        guard let receiver = pass.receiver else { return }
        if let i = ballIndex(thrownBy: pass, holders: holders) {
            holders[i] = receiver
        } else {
            holders.append(receiver)
        }
    }

    /// The step's end: everyone where their actions took them, the ball
    /// passed on, no actions drawn. The next step starts here.
    static func startOfNextStep(after diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        var next = diagram
        next.offense = diagram.offense.map { player in
            JournalPlayDiagram.Player(number: player.number, at: endPosition(of: player.number, in: diagram) ?? player.at)
        }
        next.balls = ballsAfter(diagram)
        next.actions = []
        next.notes = []
        return next
    }

    /// The dashed rings of the diagrams: where each player who moves ends up.
    static func endSpots(_ diagram: JournalPlayDiagram) -> [JournalPlayDiagram.Player] {
        diagram.offense.compactMap { player in
            guard diagram.actions.contains(where: { $0.player == player.number && $0.kind.movesPlayer }),
                  let end = endPosition(of: player.number, in: diagram) else { return nil }
            return JournalPlayDiagram.Player(number: player.number, at: end)
        }
    }

    struct PlayFrame: Equatable, Sendable {
        var players: [Int: JournalCourtPoint]
        /// Where each ball is drawn: in flight, or at its holder (drawn
        /// beside them), holders in the order of `diagram.balls`.
        var balls: [Ball] = []

        struct Ball: Equatable, Sendable {
            var at: JournalCourtPoint
            var inFlight: Bool
        }

        /// The first ball: the play's ball when there is only one.
        var ball: JournalCourtPoint? { balls.first?.at }
    }

    /// Playback time in beats: a move takes one and a half beats, a pass or
    /// shot one, a hand-off 0.6 — on the step's timeline (`schedule`).
    static let playMoveBeats = 1.5

    /// How long a step's playback is, in beats.
    static func playBeats(_ diagram: JournalPlayDiagram) -> Double {
        schedule(diagram).total
    }

    /// Everyone at moment `t` (0…1) of a step, on its timeline: each move
    /// eased in and out over its own span, each ball with its holder or in
    /// the air along its pass.
    static func frame(_ diagram: JournalPlayDiagram, at t: Double) -> PlayFrame {
        let t = min(max(t, 0), 1)
        let plan = schedule(diagram)
        let now = t * plan.total

        var players: [Int: JournalCourtPoint] = [:]
        for player in diagram.offense {
            var at = player.at
            for item in plan.items where diagram.actions[item.index].player == player.number
                && diagram.actions[item.index].kind.movesPlayer {
                let path = drawnPath(diagram.actions[item.index])
                if now >= item.end { at = path.last ?? at; continue }
                if now > item.start {
                    at = point(along: path, at: eased((now - item.start) / (item.end - item.start)))
                }
                break
            }
            players[player.number] = at
        }

        // The balls: in the air along their pass, else with whoever has them.
        var holders = diagram.balls
        var flights: [(ball: Int?, at: JournalCourtPoint)] = []
        var landed: [JournalCourtPoint] = []
        for item in plan.throwsInOrder {
            let pass = diagram.actions[item.index]
            if now >= item.end {
                if pass.kind == .shot, let rim = pass.path.last { landed.append(rim) }
                transfer(pass, holders: &holders)
            } else if now > item.start {
                let f = eased((now - item.start) / (item.end - item.start))
                flights.append((ballIndex(thrownBy: pass, holders: holders), point(along: pass.path, at: f)))
            }
        }
        var balls: [PlayFrame.Ball] = holders.enumerated().compactMap { i, holder in
            if let flight = flights.first(where: { $0.ball == i }) { return PlayFrame.Ball(at: flight.at, inFlight: true) }
            return players[holder].map { PlayFrame.Ball(at: $0, inFlight: false) }
        }
        balls += flights.filter { $0.ball == nil }.map { PlayFrame.Ball(at: $0.at, inFlight: true) }
        balls += landed.map { PlayFrame.Ball(at: $0, inFlight: false) }
        return PlayFrame(players: players, balls: balls)
    }

    /// The point a `fraction` of the way along a path, by distance.
    static func point(along path: [JournalCourtPoint], at fraction: Double) -> JournalCourtPoint {
        guard let first = path.first, let last = path.last else { return JournalCourtPoint(0, 0) }
        guard path.count > 1, fraction > 0 else { return first }
        guard fraction < 1 else { return last }
        let segments = zip(path, path.dropFirst()).map { $0.distance(to: $1) }
        let total = segments.reduce(0, +)
        guard total > 0 else { return first }
        var remaining = min(max(fraction, 0), 1) * total
        for (i, length) in segments.enumerated() {
            if remaining <= length || i == segments.count - 1 {
                let f = length > 0 ? min(remaining / length, 1) : 1
                let a = path[i], b = path[i + 1]
                return JournalCourtPoint(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
            }
            remaining -= length
        }
        return path[path.count - 1]
    }

    /// Slow out, fast through the middle, slow in.
    static func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}
