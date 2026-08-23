import Foundation
import CoreGraphics

// MARK: - Frame playback
//
// Play Editor v2, Phase D: PLAYBACK DRIVEN BY FRAMES.
//
// The look does not change. Every visual decision still comes out of
// `RenderStyle` — the terracotta brush, its width as a fraction of puck
// diameter, the draw-on lead and duration, the hold guard, the tail tucked a
// fixed number of FEET behind the player, one head per path. What changes is
// where the geometry is read from: an action's polyline and its DERIVED
// duration, instead of a track's keyframes and their authored times.
//
// THE RULES ARE THE SAME; THE ARITHMETIC IS SIMPLER, and the difference is
// worth stating because it looks like a shortcut and is not:
//
//   · The TUCK is a subtraction. v1 had to walk backwards along the trajectory
//     in 0.01s steps accumulating distance, because easing made time and
//     distance non-proportional — at an easeInOut peak a time-based tuck let
//     the tail escape the puck entirely. An action is traversed by ARC LENGTH
//     at constant speed, so "0.8 feet behind" is exactly `0.8 / length` of
//     progress. No walk, no guard counter, same rule.
//
//   · ONE ARROWHEAD IS STRUCTURAL. v1 enforced it: a track was a chain of
//     segments and any of them could have sprouted a head, so the shared layer
//     had to pick the final visible one. An action IS the whole movement, so
//     there is exactly one place a head can go and nothing to enforce.
//
// Pure functions of t, like the layer they replace: visibility is stateless, so
// scrubbing backward regrows a consumed path by construction rather than by
// remembering to reset something.
enum FramePlayback {

    /// One drawable piece of one action's path, in COURT FEET.
    struct PathPiece: Identifiable {
        var id: UUID { actionId }
        var actionId: UUID
        var actorId: UUID
        var kind: PlayActionKind
        var points: [CGPoint]
        /// Where the head sits, with its tangent. During draw-on that is the
        /// leading tip; during motion, the destination.
        var endPoint: CGPoint
        var endAngle: CGFloat
        /// Absolute seconds this action occupies, for callers that want to
        /// label or seek to it.
        var startsAt: Double
        var duration: Double
    }

    /// The head at a path's end: a chevron, or a screen's T-bar.
    struct Head: Identifiable {
        var id: UUID { actionId }
        var actionId: UUID
        var actorId: UUID
        var at: CGPoint
        var angle: CGFloat
        /// A screen ends in its bar and gets no arrow — the convention, and the
        /// same exception the track rule carried.
        var isScreen: Bool
    }

    /// Everything the path layer may draw at absolute `time`.
    ///
    /// `include` filters actors (a hidden layer, a ball that the possession
    /// model draws instead).
    static func visiblePaths(in sequence: FrameSequence,
                             at time: Double,
                             style: RenderStyle,
                             include: (UUID) -> Bool = { _ in true },
                             samples: Int = 26) -> (pieces: [PathPiece], heads: [Head]) {
        var pieces: [PathPiece] = []
        var heads: [Head] = []
        let starts = sequence.frameStartTimes
        var entering = sequence.startFormation

        for (index, frame) in sequence.frames.enumerated() {
            let frameStart = starts.indices.contains(index) ? starts[index] : 0
            let opensOn = entering
            entering = frame.endFormation

            for action in frame.validActions where action.movesActor {
                guard include(action.actorId) else { continue }
                let origin = opensOn[action.actorId] ?? .zero
                let span = frame.duration(of: action, from: opensOn,
                                          pace: sequence.pace, rim: sequence.rim)
                guard let visible = visibleAction(action,
                                                  from: origin,
                                                  startingAt: frameStart,
                                                  lasting: span,
                                                  at: time,
                                                  style: style,
                                                  samples: samples)
                else { continue }
                pieces.append(PathPiece(actionId: action.id,
                                        actorId: action.actorId,
                                        kind: action.kind,
                                        points: visible.points,
                                        endPoint: visible.headAt,
                                        endAngle: visible.headAngle,
                                        startsAt: frameStart,
                                        duration: span))
                heads.append(Head(actionId: action.id,
                                  actorId: action.actorId,
                                  at: visible.headAt,
                                  angle: visible.headAngle,
                                  isScreen: action.kind == .screen))
            }
        }
        return (pieces, heads)
    }

    /// What remains visible of one action at absolute `time`.
    struct Visible {
        var points: [CGPoint]
        var headAt: CGPoint
        var headAngle: CGFloat
    }

    /// Phases, in order, and they are the whole rule:
    ///
    ///   t < appear                   nothing — no path before its time
    ///   appear ≤ t < start           draw-on, tip-first from where he stands
    ///   start ≤ t < end              consumed: only [t − tuck, destination]
    ///   t ≥ end                      nothing — fully consumed
    static func visibleAction(_ action: PlayAction,
                              from origin: CGPoint,
                              startingAt start: Double,
                              lasting span: Double,
                              at time: Double,
                              style: RenderStyle,
                              samples: Int = 26) -> Visible? {
        let length = action.length(from: origin)
        guard length > 0 else { return nil }

        // EDIT: the whole path, always. A frame answers "is this action
        // current" structurally — you are looking at one frame — so there is no
        // time window left to apply, which is the point of the rebuild.
        guard style.consumeBehindMotion else {
            return sample(action, from: origin, between: 0, and: 1, samples: samples)
        }

        // HOLD guard: an action that barely moves is a pose, not a path.
        // Without it, keyframing a player in place grew phantom arrowheads at
        // stationary men — the same defect, and the same guard.
        if style.minMovementFeet > 0, length < style.minMovementFeet { return nil }

        let end = start + span
        let appear = max(0, start - style.drawOnLead)
        guard time >= appear, time < end else { return nil }

        let lower: Double
        let upper: Double
        if time < start {
            // Draw-on: reveal outward from where the actor stands, tip first.
            let fraction = min(1, max(0.02,
                                      (time - appear) / max(style.drawOnDuration, 0.01)))
            lower = 0
            upper = fraction
        } else {
            let progress = span > 0 ? (time - start) / span : 1
            // THE TUCK, IN FEET. Progress is arc length, so a distance behind
            // the player is a straight subtraction — see the file comment.
            let tuck = Double(style.trailingTuckFeet / length)
            lower = min(1, max(0, progress - tuck))
            upper = 1
        }
        guard upper > lower else { return nil }
        return sample(action, from: origin, between: lower, and: upper, samples: samples)
    }

    private static func sample(_ action: PlayAction,
                               from origin: CGPoint,
                               between lower: Double,
                               and upper: Double,
                               samples: Int) -> Visible? {
        var points: [CGPoint] = []
        let count = max(2, samples)
        for step in 0...count {
            let progress = lower + (upper - lower) * Double(step) / Double(count)
            points.append(action.position(atProgress: progress, from: origin))
        }
        guard let last = points.last else { return nil }
        // The tangent comes from the last DISTINCT point walking back. Taking
        // the previous sample blindly gives atan2(0, 0) — a head pointing due
        // east — whenever the visible window is short enough that consecutive
        // samples land on top of each other.
        var reference = points[0]
        for point in points.reversed() where hypot(point.x - last.x, point.y - last.y) > 0.0001 {
            reference = point
            break
        }
        let angle = atan2(last.y - reference.y, last.x - reference.x)
        return Visible(points: points, headAt: last, headAngle: angle)
    }
}

// MARK: - The ball, over frames

extension FrameSequence {

    /// Where the ball sits relative to its holder in v2.
    ///
    /// A CONSTANT vector, matching what the frame editor draws while authoring,
    /// rather than v1's direction-of-travel offset: a frame has no sub-frame
    /// direction to read, and a constant offset shifts both ends of a pass by
    /// the same amount — so the flight's length is exactly the centre-to-centre
    /// distance the possession derivation priced its duration from, and the two
    /// cannot disagree.
    static let heldBallOffset = HeldBallOffset.fixed(CGVector(dx: 1.9, dy: 0))

    /// Ball state at absolute `time`, through the SAME derivation the keyframe
    /// model uses — `BallDerivation` — fed this sequence's derived possessions
    /// and its own position resolver.
    func ballState(at time: Double,
                   ballHome: CGPoint,
                   openingHolder: UUID? = nil,
                   offset: HeldBallOffset = FrameSequence.heldBallOffset) -> BallState {
        BallDerivation.state(possessions: derivedPossessions(startingWith: openingHolder),
                             at: time,
                             passSpeed: pace.pass,
                             shotSpeed: pace.shot,
                             ballHome: ballHome,
                             offset: offset,
                             positionOf: { id, t in self.position(of: id, at: t) })
    }

    /// Resolved ball position at absolute `time`.
    func ballPosition(at time: Double,
                      ballHome: CGPoint,
                      openingHolder: UUID? = nil,
                      offset: HeldBallOffset = FrameSequence.heldBallOffset) -> CGPoint {
        BallDerivation.position(possessions: derivedPossessions(startingWith: openingHolder),
                                at: time,
                                passSpeed: pace.pass,
                                shotSpeed: pace.shot,
                                ballHome: ballHome,
                                offset: offset,
                                positionOf: { id, t in self.position(of: id, at: t) })
    }
}
