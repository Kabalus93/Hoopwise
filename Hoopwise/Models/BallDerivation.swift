import Foundation
import CoreGraphics

// MARK: - Ball derivation
//
// WHERE THE BALL IS, given who holds it and when. Extracted verbatim from
// `ReadNode` in Phase D so the FRAME model can answer the same question with
// the same code rather than a second implementation that agrees until it does
// not — the failure mode this file's own comments already record twice (the
// flight whose drawn arc and flown path disagreed, the arrival computed in two
// places).
//
// It is a pure function of `[Possession]` plus two closures: where an entity is
// at a time, and how far a held ball sits from its holder's centre. It knows
// nothing about tracks, frames, reads or storage, which is exactly why both
// callers can have it:
//
//   · v1  `ReadNode`'s stored possessions, positions resolved from tracks.
//   · v2  `FrameSequence.derivedPossessions`, positions resolved from actions.
//
// Every method here was a method on ReadNode; those remain as one-line
// forwards, so no existing call site changed and the tests that pin this
// behaviour still exercise it.
/// How a held ball sits relative to its holder's centre.
///
/// Two shapes, because the two authoring models place it differently and both
/// are right for what they are:
///
///   `.alongMotion`  v1. The ball rides on the side the holder is TRAVELLING,
///                   retaining the last real direction when he stops — snapping
///                   to a default swung it by twice the offset the instant he
///                   came to rest (measured at 3.3 ft).
///   `.fixed`        v2. A constant vector: the ball sits where the frame
///                   editor draws it and never swings, because a frame has no
///                   sub-frame direction to read. It also makes a pass's flight
///                   distance EXACTLY the centre-to-centre distance the frame
///                   model priced its duration from — both endpoints move by
///                   the same vector, so the difference cancels — which is why
///                   the derived timing and the drawn flight cannot disagree.
enum HeldBallOffset: Equatable {
    case alongMotion(feet: CGFloat)
    case fixed(CGVector)
    case none
}

enum BallDerivation {

    /// Ball state at `time`. Never returns nothing.
    ///
    /// The flight window runs from a release to the NEXT possession's start, so
    /// it fills the gap exactly by construction. Duration is still derived from
    /// distance / speed — that is what authoring writes into the receiver's
    /// start — but rendering trusts the recorded interval rather than
    /// recomputing it, so the two can never disagree.
    static func state(possessions sorted: [Possession],
                      at time: Double,
                      passSpeed: Double,
                      shotSpeed: Double,
                      ballHome: CGPoint,
                      offset: HeldBallOffset = .none,
                      positionOf: (UUID, Double) -> CGPoint) -> BallState {
        guard !sorted.isEmpty else { return .atRest(ballHome) }

        // Before anything is authored, the ball waits where it was placed.
        if let first = sorted.first, time < first.start {
            return .atRest(ballHome)
        }

        if let holding = sorted.last(where: { $0.contains(time) }) {
            return .held(holderId: holding.holderId)
        }

        // Walk releases in order, remembering where the ball last came to
        // rest. Returning on the FIRST release whose time has passed was wrong:
        // once a pass completed, a later shot was never evaluated and the ball
        // fell through to the receiver's position instead of flying to the rim.
        var lastResolved: CGPoint?
        for possession in sorted {
            guard let releaseTime = possession.end,
                  time > releaseTime,
                  let flight = flight(after: possession,
                                      among: sorted,
                                      passSpeed: passSpeed,
                                      shotSpeed: shotSpeed,
                                      offset: offset,
                                      positionOf: positionOf)
            else { continue }

            if time <= releaseTime + flight.duration {
                let progress = (time - releaseTime) / max(flight.duration, 0.0001)
                return .inFlight(flight, progress: progress)
            }
            // Where the flight actually ended — the receiver's tucked hand, or
            // the rim. Taken from the curve so rest and flight agree.
            lastResolved = flight.endPoint
        }

        if let lastResolved { return .atRest(lastResolved) }

        // Held to the end, or an unreleased possession: rest with the last
        // holder rather than falling through to nothing.
        if let last = sorted.last {
            return .atRest(heldPosition(last.holderId, at: time,
                                        offset: offset,
                                        positionOf: positionOf))
        }
        return .atRest(ballHome)
    }

    /// Resolved ball position. Total by construction — see `state`.
    static func position(possessions sorted: [Possession],
                         at time: Double,
                         passSpeed: Double,
                         shotSpeed: Double,
                         ballHome: CGPoint,
                         offset: HeldBallOffset,
                         positionOf: (UUID, Double) -> CGPoint) -> CGPoint {
        switch state(possessions: sorted, at: time, passSpeed: passSpeed,
                     shotSpeed: shotSpeed, ballHome: ballHome,
                     offset: offset, positionOf: positionOf) {
        case .held(let holderId):
            return heldPosition(holderId, at: time, offset: offset,
                                positionOf: positionOf)
        case .inFlight(let flight, let progress):
            // THE shared curve — the same call the drawn arc is sampled from.
            return flight.position(atProgress: progress)
        case .atRest(let point):
            return point
        }
    }

    /// Where a held ball sits: BESIDE the holder, not on top of him.
    static func heldPosition(_ holderId: UUID, at time: Double,
                             offset: HeldBallOffset,
                             positionOf: (UUID, Double) -> CGPoint) -> CGPoint {
        let centre = positionOf(holderId, time)
        let tuck = heldTuck(holderId, at: time, offset: offset,
                            positionOf: positionOf)
        return CGPoint(x: centre.x + tuck.dx, y: centre.y + tuck.dy)
    }

    /// The held-ball offset as a vector, so a flight carries it in its
    /// ENDPOINTS rather than as a deviation from the line it draws.
    private static func heldTuck(_ holderId: UUID, at time: Double,
                                 offset: HeldBallOffset,
                                 positionOf: (UUID, Double) -> CGPoint) -> CGVector {
        switch offset {
        case .none:
            return .zero
        case .fixed(let vector):
            return vector
        case .alongMotion(let feet):
            guard feet != 0 else { return .zero }
            let direction = holderDirection(holderId, at: time, positionOf: positionOf)
            return CGVector(dx: direction.dx * feet, dy: direction.dy * feet)
        }
    }

    /// THE flight builder. `state`, `arrivalTime` and `releases` all come
    /// through here, so the arc the coach sees, the position the ball takes and
    /// the arrival the timeline reports are one derivation.
    ///
    /// ARRIVAL IS AUTHORED, NOT RECOMPUTED: a pass lands when the receiver's
    /// possession begins, and distance ÷ speed is only the fallback for a pass
    /// nothing receives. The two used to disagree the moment an attach was
    /// retimed — the ball flew to one point and the line was drawn to another.
    static func flight(after possession: Possession,
                       among ordered: [Possession],
                       passSpeed: Double,
                       shotSpeed: Double,
                       offset: HeldBallOffset,
                       positionOf: (UUID, Double) -> CGPoint) -> BallFlight? {
        guard let releaseTime = possession.end, let release = possession.release
        else { return nil }
        // HAND, not centre: the flight starts exactly where the held ball is,
        // so release is continuous and the drawn line still runs straight.
        let from = heldPosition(possession.holderId, at: releaseTime,
                                offset: offset, positionOf: positionOf)

        switch release {
        case .pass(let toId):
            let receiverAt = positionOf(toId, releaseTime)
            let distance = Double(hypot(receiverAt.x - from.x, receiverAt.y - from.y))
            let derived = releaseTime + max(0.08, distance / max(passSpeed, 1))
            let arrival = ordered.first { $0.start > releaseTime }?.start ?? derived
            let duration = max(0.0001, arrival - releaseTime)
            return BallFlight(from: from,
                              to: heldPosition(toId, at: arrival,
                                               offset: offset,
                                               positionOf: positionOf),
                              isShot: false,
                              duration: duration,
                              arcFeet: 0)

        case .shot(let target):
            let distance = Double(hypot(target.x - from.x, target.y - from.y))
            // Nothing catches a shot: it comes to rest exactly at the rim it
            // was aimed at, so that end takes no hand offset.
            return BallFlight(from: from,
                              to: target,
                              isShot: true,
                              duration: max(0.12, distance / max(shotSpeed, 1)),
                              arcFeet: BallFlight.shotArcFeet)
        }
    }

    /// Releases with the CURVE each one draws.
    ///
    /// The line derives from possession rather than being drawn separately, so
    /// there is one source of truth for "the ball went from here to there" —
    /// and it hands back the same `BallFlight` the resolver samples, so a
    /// renderer cannot draw an arc the ball does not fly.
    static func releases(possessions sorted: [Possession],
                         passSpeed: Double,
                         shotSpeed: Double,
                         offset: HeldBallOffset = .none,
                         positionOf: (UUID, Double) -> CGPoint)
    -> [(flight: BallFlight, release: BallRelease, departure: Double, arrival: Double)] {
        var result: [(BallFlight, BallRelease, Double, Double)] = []
        for possession in sorted {
            guard let departure = possession.end, let release = possession.release,
                  let flight = flight(after: possession, among: sorted,
                                      passSpeed: passSpeed, shotSpeed: shotSpeed,
                                      offset: offset,
                                      positionOf: positionOf)
            else { continue }
            result.append((flight, release, departure, departure + flight.duration))
        }
        return result
    }

    /// Direction the holder is travelling, for the held-ball offset.
    ///
    /// When he is stationary this RETAINS the last direction he actually moved,
    /// searching backwards, rather than snapping to a fixed default. Snapping
    /// swings the ball by twice the offset the instant he stops — the sampling
    /// test measured a 3.3ft jump at exactly the moment a holder reached his
    /// last keyframe. Only a holder who has never moved gets the default.
    static func holderDirection(_ holderId: UUID,
                                at time: Double,
                                positionOf: (UUID, Double) -> CGPoint) -> (dx: CGFloat, dy: CGFloat) {
        let epsilon = 0.12
        let threshold: CGFloat = 0.02

        func sample(_ t: Double) -> (CGFloat, CGFloat, CGFloat) {
            let now = positionOf(holderId, t)
            let ahead = positionOf(holderId, t + epsilon)
            let dx = ahead.x - now.x
            let dy = ahead.y - now.y
            return (dx, dy, (dx * dx + dy * dy).squareRoot())
        }

        let (dx, dy, magnitude) = sample(time)
        if magnitude > threshold { return (dx / magnitude, dy / magnitude) }

        // Walk back to the last moment he was moving.
        var back = time - epsilon
        var guard_ = 0
        while back >= 0, guard_ < 200 {
            let (bdx, bdy, bmag) = sample(back)
            if bmag > threshold { return (bdx / bmag, bdy / bmag) }
            back -= epsilon
            guard_ += 1
        }
        return (1, 0)
    }
}
