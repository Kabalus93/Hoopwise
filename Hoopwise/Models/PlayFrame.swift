import Foundation
import CoreGraphics

// MARK: - Play Editor v2: the Frame model
//
// A play is an ORDERED LIST OF FRAMES. Each frame holds typed actions, the
// formation those actions leave behind, and a coaching caption. This is
// FastDraw's mechanics: you author a moment, then the next moment.
//
// WHAT IS DIFFERENT FROM THE KEYFRAME MODEL IT REPLACES, and why:
//
//   TIME IS DERIVED, NEVER AUTHORED. There is no `t` on anything here. An
//   action's duration is its path length ÷ the pace for its kind; a frame lasts
//   as long as its longest action; a play is its frames end to end. A coach
//   says "he sprints to the corner", not "he arrives at 1.4 seconds" — and
//   every bug where two derivations of the same instant disagreed (the pass
//   whose drawn arrival was 1.451s and whose ball landed at 1.400s) came from
//   storing a time that something else also computed.
//
//   POSITION IS A CONSEQUENCE, NOT A TRACK. An entity with no action in a frame
//   holds where the previous frame left it. Continuity is the default rather
//   than something a boundary-pin keyframe has to reconstruct.
//
//   POSSESSION IS DERIVED FROM ACTIONS. A pass moves the ball, a handoff moves
//   it, a shot ends it. The output is the EXISTING `Possession` model — the
//   truth stays where it was, and frames become its authoring interface, so
//   `ballState`, `BallFlight` and everything downstream keep working unchanged.
//   The constraints in docs/BALL_LANE_SPEC.md §1/§2 are what this must satisfy.
//
// Phase A is model + tests only. Nothing here draws, and nothing in the editor
// reads it yet.

// MARK: - Actions

/// The action vocabulary. Typed, because typed actions are DATA — which is the
/// whole foundation the recognition and co-builder work later needs, and the
/// reason notation can be applied automatically rather than chosen from a menu.
enum PlayActionKind: String, Codable, CaseIterable, Hashable {
    case cut
    case dribble
    case pass
    case screen
    case handoff
    case shot

    /// Whether the ball travels with this action rather than a player.
    var isBallFlight: Bool { self == .pass || self == .shot }

    /// Whether performing this action gives the ball away.
    var releasesPossession: Bool { self == .pass || self == .shot || self == .handoff }

    var displayName: String {
        switch self {
        case .cut:     return "Cut"
        case .dribble: return "Dribble"
        case .pass:    return "Pass"
        case .screen:  return "Screen"
        case .handoff: return "Handoff"
        case .shot:    return "Shot"
        }
    }

    /// THE RULE FOR WHAT A DRAG ON A PLAYER MEANS. Pure, and shared, so the
    /// inference the whole authoring model rests on can be tested without a
    /// window — which is exactly what it was not, and why it shipped broken:
    /// ⌥-drag reached the editor as "screen", but the editor decided the kind
    /// from whether a TEAMMATE happened to be under the drop point, so setting
    /// a screen on open floor — the normal case — came out a cut.
    ///
    /// The modifier decides. Who the screen is FOR is metadata, and may be nil.
    static func inferred(asScreen: Bool, actorHoldsBall: Bool) -> PlayActionKind {
        if asScreen { return .screen }
        return actorHoldsBall ? .dribble : .cut
    }
}

/// What an action is aimed at. A pass and a handoff name a player; a shot names
/// the rim; a cut or a screen may name only the floor it ends on.
enum ActionTarget: Codable, Hashable {
    case player(UUID)
    /// Court feet.
    case point(CGPoint)

    var playerId: UUID? {
        if case .player(let id) = self { return id }
        return nil
    }
}

/// How fast a movement is meant to be run. The spec's three tiers; a kind
/// carries a default so nothing has to be chosen, and this is the only way
/// `sprint` is reachable.
enum PaceTier: String, Codable, CaseIterable, Hashable {
    case walk
    case cut
    case sprint
}

/// One typed thing that happens inside a frame.
///
/// PATH EXCLUDES THE START POINT, deliberately: where the actor stands when the
/// frame opens is already known from the previous frame's end formation, and
/// storing it again is a second source of truth that drifts the moment an
/// earlier frame is edited. `path` is where the actor goes — one point for a
/// straight move, more to bend it.
struct PlayAction: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: PlayActionKind
    /// The entity performing it. For a pass or shot this is the PASSER — the
    /// ball is not an actor, it is a consequence.
    var actorId: UUID
    var target: ActionTarget?
    /// Court feet, excluding the start. Empty means the action goes nowhere,
    /// which `isWellFormed` rejects for movement kinds.
    var path: [CGPoint]
    /// Overrides the kind's default tier. Nil is the normal case.
    var pace: PaceTier?
    /// For a screen: the teammate it is set for. Display and coaching only —
    /// it moves nobody.
    var screenForId: UUID?

    init(id: UUID = UUID(),
         kind: PlayActionKind,
         actorId: UUID,
         target: ActionTarget? = nil,
         path: [CGPoint] = [],
         pace: PaceTier? = nil,
         screenForId: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.actorId = actorId
        self.target = target
        self.path = path
        self.pace = pace
        self.screenForId = screenForId
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, actorId, target, path, pace, screenForId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(PlayActionKind.self, forKey: .kind)
        actorId = try c.decode(UUID.self, forKey: .actorId)
        target = try c.decodeIfPresent(ActionTarget.self, forKey: .target)
        path = try c.decodeIfPresent([CGPoint].self, forKey: .path) ?? []
        pace = try c.decodeIfPresent(PaceTier.self, forKey: .pace)
        screenForId = try c.decodeIfPresent(UUID.self, forKey: .screenForId)
    }

    /// Whether the ACTOR moves. A pass and a shot move the ball, not the man.
    var movesActor: Bool { !kind.isBallFlight }

    /// The tier this action runs at.
    var effectiveTier: PaceTier {
        if let pace { return pace }
        switch kind {
        case .screen, .handoff: return .walk
        case .cut, .dribble:    return .cut
        case .pass, .shot:      return .cut      // unused: flights price separately
        }
    }

    /// Where the action ends, given where it started.
    func endPoint(from start: CGPoint) -> CGPoint {
        path.last ?? start
    }

    /// Total path length in court feet, including the leg out of `start`.
    func length(from start: CGPoint) -> CGFloat {
        var total: CGFloat = 0
        var previous = start
        for point in path {
            total += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
        }
        return total
    }

    /// Position along the path at normalised progress, measured by ARC LENGTH
    /// so a bent path is traversed at constant speed rather than lurching
    /// between control points.
    func position(atProgress progress: Double, from start: CGPoint) -> CGPoint {
        guard !path.isEmpty else { return start }
        let clamped = CGFloat(min(max(progress, 0), 1))
        let total = length(from: start)
        guard total > 0 else { return path.last ?? start }
        var travelled: CGFloat = 0
        let wanted = total * clamped
        var previous = start
        for point in path {
            let leg = hypot(point.x - previous.x, point.y - previous.y)
            if travelled + leg >= wanted {
                guard leg > 0 else { return point }
                let f = (wanted - travelled) / leg
                return CGPoint(x: previous.x + (point.x - previous.x) * f,
                               y: previous.y + (point.y - previous.y) * f)
            }
            travelled += leg
            previous = point
        }
        return path.last ?? start
    }

    /// A movement action that goes nowhere is not an action; a pass with no
    /// receiver cannot move the ball. Malformed actions are DROPPED by the
    /// resolvers rather than half-applied.
    var isWellFormed: Bool {
        switch kind {
        case .cut, .dribble, .screen:
            return !path.isEmpty
        case .pass, .handoff:
            return target?.playerId != nil
        case .shot:
            return target != nil
        }
    }
}

// MARK: - Pace

/// Feet per second, one setting per play. The spec's "role speed".
///
/// Tunable data rather than constants, for the same reason CourtLookParameters
/// is: these are feel decisions the coach iterates against real playback, and
/// a rebuild per adjustment is how they never get adjusted.
struct PlayPace: Codable, Hashable {
    var walk: Double
    var cut: Double
    var sprint: Double
    var pass: Double
    var shot: Double

    static let `default` = PlayPace(walk: 7, cut: 13, sprint: 19, pass: 34, shot: 26)

    init(walk: Double = 7, cut: Double = 13, sprint: Double = 19,
         pass: Double = 34, shot: Double = 26) {
        self.walk = walk
        self.cut = cut
        self.sprint = sprint
        self.pass = pass
        self.shot = shot
    }

    func speed(for tier: PaceTier) -> Double {
        switch tier {
        case .walk:   return max(0.1, walk)
        case .cut:    return max(0.1, cut)
        case .sprint: return max(0.1, sprint)
        }
    }

    func speed(for action: PlayAction) -> Double {
        switch action.kind {
        case .pass: return max(0.1, pass)
        case .shot: return max(0.1, shot)
        default:    return speed(for: action.effectiveTier)
        }
    }
}

// MARK: - Formation

/// Every entity's position at one instant, in court feet.
///
/// An array of placements rather than a dictionary: `[UUID: CGPoint]` encodes
/// as a flat alternating array in JSON, which is unreadable in a stored blob
/// and a nuisance to diff.
struct Formation: Codable, Hashable {
    struct Placement: Codable, Hashable {
        var entityId: UUID
        var position: CGPoint
    }

    var placements: [Placement]

    init(placements: [Placement] = []) {
        self.placements = placements
    }

    init(_ positions: [UUID: CGPoint]) {
        placements = positions
            .map { Placement(entityId: $0.key, position: $0.value) }
            .sorted { $0.entityId.uuidString < $1.entityId.uuidString }
    }

    subscript(entityId: UUID) -> CGPoint? {
        get { placements.first { $0.entityId == entityId }?.position }
        set {
            guard let newValue else {
                placements.removeAll { $0.entityId == entityId }
                return
            }
            if let index = placements.firstIndex(where: { $0.entityId == entityId }) {
                placements[index].position = newValue
            } else {
                placements.append(Placement(entityId: entityId, position: newValue))
                placements.sort { $0.entityId.uuidString < $1.entityId.uuidString }
            }
        }
    }

    var entityIds: [UUID] { placements.map(\.entityId) }
    var isEmpty: Bool { placements.isEmpty }
}

// MARK: - Frame

/// One authored moment: what happens, where it leaves everyone, and what the
/// coach says about it.
struct PlayFrame: Identifiable, Codable, Hashable {
    let id: UUID
    var actions: [PlayAction]
    /// Where everyone stands when the frame ENDS.
    ///
    /// DERIVED, BUT STORED — the one place this model keeps a second copy of
    /// something it can compute, because the frame strip, the branch resolver
    /// and every thumbnail want it without replaying the play. The honesty
    /// mechanism is that ONE function computes it (`resolvedEndFormation`),
    /// every mutation re-runs it, and `FrameSequence.driftedFrames` reports any
    /// frame whose stored copy disagrees — which the tests assert is empty.
    var endFormation: Formation
    /// Per-frame coaching text, as the coach typed it.
    var caption: String

    init(id: UUID = UUID(),
         actions: [PlayAction] = [],
         endFormation: Formation = Formation(),
         caption: String = "") {
        self.id = id
        self.actions = actions
        self.endFormation = endFormation
        self.caption = caption
    }

    enum CodingKeys: String, CodingKey { case id, actions, endFormation, caption }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        actions = try c.decodeIfPresent([PlayAction].self, forKey: .actions) ?? []
        endFormation = try c.decodeIfPresent(Formation.self, forKey: .endFormation) ?? Formation()
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
    }

    var validActions: [PlayAction] { actions.filter(\.isWellFormed) }

    /// How long one action takes: path length ÷ pace. Flights price from the
    /// ball's journey, not the passer's feet.
    func duration(of action: PlayAction, from start: Formation, pace: PlayPace,
                  rim: CGPoint) -> Double {
        let speed = pace.speed(for: action)
        let origin = start[action.actorId] ?? .zero
        let distance: CGFloat
        switch action.kind {
        case .pass, .handoff:
            guard let receiver = action.target?.playerId,
                  let to = start[receiver] else { return 0 }
            distance = hypot(to.x - origin.x, to.y - origin.y)
        case .shot:
            let to: CGPoint
            if case .point(let target) = action.target { to = target } else { to = rim }
            distance = hypot(to.x - origin.x, to.y - origin.y)
        default:
            distance = action.length(from: origin)
        }
        // A floor, so a zero-length action still occupies a beat rather than
        // collapsing the frame to nothing.
        return max(0.12, Double(distance) / speed)
    }

    /// FRAME DURATION IS ITS LONGEST ACTION — actions inside a frame run
    /// concurrently, which is what makes a frame a MOMENT rather than a step in
    /// a queue. An empty frame still holds for a beat so it can be seen.
    func duration(from start: Formation, pace: PlayPace, rim: CGPoint) -> Double {
        let longest = validActions
            .map { duration(of: $0, from: start, pace: pace, rim: rim) }
            .max()
        return longest ?? PlayFrame.emptyFrameDuration
    }

    /// What an actionless frame is worth. A held pose is a legitimate frame —
    /// FastDraw's "set" — and zero would make it invisible in playback.
    static let emptyFrameDuration: Double = 0.6

    /// Where everyone stands at the end, given where they started. THE
    /// derivation: movers land at their path's end, everyone else carries over.
    func resolvedEndFormation(from start: Formation) -> Formation {
        var result = start
        for action in validActions where action.movesActor {
            let origin = start[action.actorId] ?? .zero
            result[action.actorId] = action.endPoint(from: origin)
        }
        return result
    }

    /// Position of one entity partway through this frame.
    func position(of entityId: UUID, atProgressSeconds seconds: Double,
                  from start: Formation, pace: PlayPace, rim: CGPoint) -> CGPoint {
        let origin = start[entityId] ?? .zero
        guard let action = validActions.first(where: {
            $0.actorId == entityId && $0.movesActor
        }) else { return origin }
        let span = duration(of: action, from: start, pace: pace, rim: rim)
        guard span > 0 else { return action.endPoint(from: origin) }
        return action.position(atProgress: seconds / span, from: origin)
    }
}
