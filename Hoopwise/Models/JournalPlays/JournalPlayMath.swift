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
        for pass in passOrder(diagram).all { transfer(pass, holders: &holders) }
        return holders
    }

    /// The passes and shots in the order they fly: those drawn before their passer's
    /// move (pass and cut) first, then the rest (drive and kick).
    static func passOrder(_ diagram: JournalPlayDiagram) -> (early: [JournalPlayDiagram.Action], late: [JournalPlayDiagram.Action], all: [JournalPlayDiagram.Action]) {
        var early: [JournalPlayDiagram.Action] = [], late: [JournalPlayDiagram.Action] = []
        for (i, action) in diagram.actions.enumerated() where action.kind.throwsBall {
            let movesAfter = diagram.actions[(i + 1)...].contains { $0.player == action.player && $0.kind.movesPlayer }
            if movesAfter { early.append(action) } else { late.append(action) }
        }
        return (early, late, early + late)
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

    /// Playback time in beats: all the moving takes one and a half beats
    /// (everyone runs at once), each pass one beat.
    static let playMoveBeats = 1.5

    /// How long a step's playback is, in beats.
    static func playBeats(_ diagram: JournalPlayDiagram) -> Double {
        let passes = diagram.actions.filter { $0.kind.throwsBall }.count
        let moves = diagram.actions.contains { $0.kind.movesPlayer }
        return Double(passes) + (moves ? playMoveBeats : 0)
    }

    /// Everyone at moment `t` (0…1) of a step, in the order the actions
    /// are drawn: a pass drawn before its passer's cut is thrown first
    /// (pass and cut); then everyone runs their paths, eased in and out;
    /// then the other passes fly, one by one (drive and kick).
    static func frame(_ diagram: JournalPlayDiagram, at t: Double) -> PlayFrame {
        let t = min(max(t, 0), 1)
        let movers = Set(diagram.actions.filter { $0.kind.movesPlayer }.map(\.player))
        let (early, late, passes) = passOrder(diagram)
        let total = playBeats(diagram)
        let beat = total > 0 ? 1 / total : 0
        let moveStart = Double(early.count) * beat
        let moveEnd = moveStart + (movers.isEmpty ? 0 : playMoveBeats * beat)

        let move = t >= moveEnd ? 1 : t <= moveStart ? 0 : eased((t - moveStart) / (moveEnd - moveStart))
        var players: [Int: JournalCourtPoint] = [:]
        for player in diagram.offense {
            let path = diagram.actions.filter { $0.player == player.number && $0.kind.movesPlayer }.flatMap(drawnPath)
            players[player.number] = path.isEmpty ? player.at : point(along: path, at: move)
        }

        // The balls: one along the pass in the air, the others with whoever has them.
        var holders = diagram.balls
        var flight: (ball: Int?, at: JournalCourtPoint)?
        /// Balls shot this step, resting at the rim.
        var landed: [JournalCourtPoint] = []
        for (i, pass) in passes.enumerated() {
            let begin = i < early.count ? Double(i) * beat : moveEnd + Double(i - early.count) * beat
            if t >= begin + beat {
                if pass.kind == .shot, let rim = pass.path.last { landed.append(rim) }
                transfer(pass, holders: &holders)
                continue
            }
            if t > begin {
                flight = (ballIndex(thrownBy: pass, holders: holders), point(along: pass.path, at: eased((t - begin) / beat)))
            }
            break
        }
        var balls: [PlayFrame.Ball] = holders.enumerated().compactMap { i, holder in
            if let flight, flight.ball == i { return PlayFrame.Ball(at: flight.at, inFlight: true) }
            return players[holder].map { PlayFrame.Ball(at: $0, inFlight: false) }
        }
        if let flight, flight.ball == nil { balls.append(PlayFrame.Ball(at: flight.at, inFlight: true)) }
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
