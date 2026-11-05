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
        let moves = diagram.actions.filter { $0.player == number && $0.kind != .pass }
        if let last = moves.last?.path.last { return last }
        return diagram.player(number)?.at
    }

    /// Who has the ball when the step's actions are done: the receiver of
    /// the last pass, else whoever had it.
    static func ballAfter(_ diagram: JournalPlayDiagram) -> Int? {
        diagram.actions.last { $0.kind == .pass && $0.receiver != nil }?.receiver ?? diagram.ball
    }

    /// The step's end: everyone where their actions took them, the ball
    /// passed on, no actions drawn. The next step starts here.
    static func startOfNextStep(after diagram: JournalPlayDiagram) -> JournalPlayDiagram {
        var next = diagram
        next.offense = diagram.offense.map { player in
            JournalPlayDiagram.Player(number: player.number, at: endPosition(of: player.number, in: diagram) ?? player.at)
        }
        next.ball = ballAfter(diagram)
        next.actions = []
        next.notes = []
        return next
    }

    /// The dashed rings of the diagrams: where each player who moves ends up.
    static func endSpots(_ diagram: JournalPlayDiagram) -> [JournalPlayDiagram.Player] {
        diagram.offense.compactMap { player in
            guard diagram.actions.contains(where: { $0.player == player.number && $0.kind != .pass }),
                  let end = endPosition(of: player.number, in: diagram) else { return nil }
            return JournalPlayDiagram.Player(number: player.number, at: end)
        }
    }

    struct PlayFrame: Equatable, Sendable {
        var players: [Int: JournalCourtPoint]
        /// Where the ball is drawn, beside its holder or in flight.
        var ball: JournalCourtPoint?
    }

    /// Playback time in beats: all the moving takes one and a half beats
    /// (everyone runs at once), each pass one beat.
    static let playMoveBeats = 1.5

    /// How long a step's playback is, in beats.
    static func playBeats(_ diagram: JournalPlayDiagram) -> Double {
        let passes = diagram.actions.filter { $0.kind == .pass }.count
        let moves = diagram.actions.contains { $0.kind != .pass }
        return Double(passes) + (moves ? playMoveBeats : 0)
    }

    /// Everyone at moment `t` (0…1) of a step, in the order the actions
    /// are drawn: a pass drawn before its passer's cut is thrown first
    /// (pass and cut); then everyone runs their paths, eased in and out;
    /// then the other passes fly, one by one (drive and kick).
    static func frame(_ diagram: JournalPlayDiagram, at t: Double) -> PlayFrame {
        let t = min(max(t, 0), 1)
        let movers = Set(diagram.actions.filter { $0.kind != .pass }.map(\.player))
        var early: [JournalPlayDiagram.Action] = [], late: [JournalPlayDiagram.Action] = []
        for (i, action) in diagram.actions.enumerated() where action.kind == .pass {
            let movesAfter = diagram.actions[(i + 1)...].contains { $0.player == action.player && $0.kind != .pass }
            if movesAfter { early.append(action) } else { late.append(action) }
        }
        let total = playBeats(diagram)
        let beat = total > 0 ? 1 / total : 0
        let moveStart = Double(early.count) * beat
        let moveEnd = moveStart + (movers.isEmpty ? 0 : playMoveBeats * beat)

        let move = t >= moveEnd ? 1 : t <= moveStart ? 0 : eased((t - moveStart) / (moveEnd - moveStart))
        var players: [Int: JournalCourtPoint] = [:]
        for player in diagram.offense {
            let path = diagram.actions.filter { $0.player == player.number && $0.kind != .pass }.flatMap(\.path)
            players[player.number] = path.isEmpty ? player.at : point(along: path, at: move)
        }

        // The ball: along the pass in the air, else with whoever has it.
        var holder = diagram.ball
        var inFlight: JournalCourtPoint?
        for (i, pass) in (early + late).enumerated() {
            let begin = i < early.count ? Double(i) * beat : moveEnd + Double(i - early.count) * beat
            if t >= begin + beat {
                holder = pass.receiver ?? holder
                continue
            }
            if t > begin { inFlight = point(along: pass.path, at: eased((t - begin) / beat)) }
            break
        }
        return PlayFrame(players: players, ball: inFlight ?? holder.flatMap { players[$0] })
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
