import Foundation
import CoreGraphics

// MARK: - Play Diagram
//
// The spatial model for a play. All positions are in court feet (see
// CourtSpace). This is a pure value tree: it is always loaded and saved whole,
// stored as a Codable JSON blob on SDPlayDiagram rather than a normalized
// entity graph. A diagram is a document, not a queryable table — nothing ever
// asks "which keyframes fall at t=3.2s across all plays".
//
// Time is continuous. The legacy CourtFrame/order shape was a discrete
// slideshow; tracks carry `t` in seconds with easing between keyframes.
//
// Rendering is 2D. The oblique "3D" look is a perspective projection of the
// court plane applied at render time, driven by `cameraAngle`. There is no
// SceneKit here and there must not be: PDF export needs vector output, and the
// Resolve/Fusion pipeline these exports feed cannot take 3D scene data.

// MARK: - Entities

/// What a marker on the floor represents.
enum DiagramEntityKind: Codable, Hashable {
    /// A player. `team` reuses the existing CourtTeam vocabulary.
    case player(team: CourtTeam, number: Int?, role: String?)
    /// The ball. At most one per diagram in practice, though not enforced —
    /// shell drills sometimes want two.
    case ball
    /// A screen marker, drawn as a bar perpendicular to the screener's stance.
    case screen
    /// A cone or other equipment marker.
    case cone
    /// Free annotation: an arrow, region, or text label anchored to the floor.
    case annotation(AnnotationShape)
}

/// Non-player annotation geometry.
enum AnnotationShape: Codable, Hashable {
    case text(String)
    case arrow
    case rectangle
    case ellipse
    /// A closed region, e.g. shading a zone's responsibility area.
    case polygon([CGPoint])
}

/// Something that exists on the floor and can be animated.
///
/// An entity carries identity and appearance. Where it *is* over time lives in
/// a `Track`, keyed by this id, on whichever read node owns that slice of time.
struct DiagramEntity: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: DiagramEntityKind
    /// Shown on the puck. For players this is usually the number; for
    /// annotations it may be empty.
    var label: String?
    /// Optional override; nil uses the team default.
    var colorHex: String?
    /// Where the entity sits before its first keyframe, and after its last.
    var homePosition: CGPoint
    /// Puck size multiplier, 1.0 default. Optional so old blobs decode.
    var sizeScale: CGFloat?

    var effectiveSize: CGFloat { sizeScale ?? 1 }

    init(id: UUID = UUID(),
         kind: DiagramEntityKind,
         label: String? = nil,
         colorHex: String? = nil,
         homePosition: CGPoint,
         sizeScale: CGFloat? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.colorHex = colorHex
        self.homePosition = homePosition
        self.sizeScale = sizeScale
    }

    var isPlayer: Bool {
        if case .player = kind { return true }
        return false
    }
}

// MARK: - Motion

/// How a value approaches the next keyframe.
enum Easing: String, Codable, CaseIterable, Hashable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// No interpolation: the previous value holds for the whole segment, then
    /// jumps at this keyframe — how a player "stays put then cuts".
    case hold

    /// Maps normalized progress 0...1 through the curve.
    func apply(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear:    return x
        case .easeIn:    return x * x
        case .easeOut:   return 1 - (1 - x) * (1 - x)
        case .easeInOut: return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        case .hold:      return 0
        }
    }
}

/// What kind of movement the segment leading into a keyframe represents.
///
/// This carries the line semantics — a cut and a pass are drawn differently
/// and mean different things. Deliberately mirrors the existing `MovementType`
/// vocabulary so the legacy editor's tools port over unchanged.
enum PathKind: String, Codable, CaseIterable, Hashable {
    case run
    case cut
    case dribble
    case pass
    case screen

    /// Matches MovementType.lineStyle so both models render identically.
    var lineStyle: String {
        switch self {
        case .run:     return "solid"
        case .cut:     return "zigzag"
        case .dribble: return "wavy"
        case .pass:    return "dashed"
        case .screen:  return "thick"
        }
    }

    /// A pass moves the ball between players rather than moving a player.
    var carriesBall: Bool { self == .pass || self == .dribble }

    var displayName: String {
        switch self {
        case .run:     return "Run"
        case .cut:     return "Cut"
        case .dribble: return "Dribble"
        case .pass:    return "Pass"
        case .screen:  return "Screen"
        }
    }
}

/// One point in time for one entity.
///
/// SEGMENT CONVENTION — `pathKind` describes the segment *leaving* this
/// keyframe, not an instant:
///
///   keyframe[N].pathKind  governs the segment from keyframe[N] to keyframe[N+1]
///   keyframe[last].pathKind  is IGNORED — there is no segment after it
///
/// So a player who cuts and then receives a pass has `.cut` on the keyframe
/// where the cut begins, not the one where it ends. `easing` runs the other
/// way — it governs how motion *arrives* at this keyframe — because easing is a
/// property of the approach and path kind is a property of the departure.
/// Editors should render the final keyframe's path-kind control as disabled.
struct Keyframe: Identifiable, Codable, Hashable {
    enum CodingKeys: String, CodingKey {
        case id, t, position, easing, pathKind, pathStyle, controlPoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        t = try c.decode(Double.self, forKey: .t)
        position = try c.decode(CGPoint.self, forKey: .position)
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .easeInOut
        pathKind = try c.decodeIfPresent(PathKind.self, forKey: .pathKind) ?? .run
        pathStyle = try c.decodeIfPresent(PathStyle.self, forKey: .pathStyle) ?? .sharp
        controlPoints = try c.decodeIfPresent([CGPoint].self, forKey: .controlPoints) ?? []
    }

    let id: UUID
    /// Seconds from the start of the owning read node.
    var t: Double
    var position: CGPoint
    /// How motion arrives at this keyframe from the previous one.
    var easing: Easing
    /// What the segment LEAVING this keyframe represents. Ignored on the last
    /// keyframe of a track — see the segment convention above.
    var pathKind: PathKind
    /// Whether the segment LEAVING this keyframe runs straight or curves
    /// through its neighbours. Reuses the legacy CourtMovement vocabulary.
    var pathStyle: PathStyle
    /// Optional bezier control points, in court feet. Empty means the style
    /// decides: sharp is a straight segment, curved is a Catmull-Rom spline
    /// through the surrounding keyframes.
    var controlPoints: [CGPoint]

    /// `easing` defaults to easeInOut. Linear is the opt-in — real movement
    /// accelerates and decelerates, and a linear default made every play read
    /// mechanical.
    init(id: UUID = UUID(),
         t: Double,
         position: CGPoint,
         easing: Easing = .easeInOut,
         pathKind: PathKind = .run,
         pathStyle: PathStyle = .sharp,
         controlPoints: [CGPoint] = []) {
        self.id = id
        self.t = t
        self.position = position
        self.easing = easing
        self.pathKind = pathKind
        self.pathStyle = pathStyle
        self.controlPoints = controlPoints
    }
}

/// One entity's motion across the owning read node's time span.
struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    var entityId: UUID
    /// Sorted by `t`. Use `sortedKeyframes` rather than trusting order.
    var keyframes: [Keyframe]

    init(id: UUID = UUID(), entityId: UUID, keyframes: [Keyframe] = []) {
        self.id = id
        self.entityId = entityId
        self.keyframes = keyframes
    }

    var sortedKeyframes: [Keyframe] { keyframes.sorted { $0.t < $1.t } }

    var duration: Double { sortedKeyframes.last?.t ?? 0 }

    /// Standard Catmull-Rom, written as explicit typed steps because the
    /// single-expression form exceeds the type checker's budget.
    static func catmullRom(_ p0: CGPoint, _ p1: CGPoint,
                           _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2: CGFloat = t * t
        let t3: CGFloat = t2 * t
        let a: CGFloat = -0.5 * t3 + t2 - 0.5 * t
        let b: CGFloat = 1.5 * t3 - 2.5 * t2 + 1.0
        let c: CGFloat = -1.5 * t3 + 2.0 * t2 + 0.5 * t
        let d: CGFloat = 0.5 * t3 - 0.5 * t2
        let x: CGFloat = a * p0.x + b * p1.x + c * p2.x + d * p3.x
        let y: CGFloat = a * p0.y + b * p1.y + c * p2.y + d * p3.y
        return CGPoint(x: x, y: y)
    }

    /// Position at time `t`, interpolated with the incoming keyframe's easing.
    /// Before the first keyframe holds the first position; after the last holds
    /// the last. Returns nil only when the track has no keyframes at all.
    func position(at time: Double) -> CGPoint? {
        let frames = sortedKeyframes
        guard let first = frames.first else { return nil }
        if time <= first.t { return first.position }
        guard let last = frames.last else { return nil }
        if time >= last.t { return last.position }

        for (index, frame) in frames.enumerated() where frame.t > time {
            let previous = frames[index - 1]
            let span = frame.t - previous.t
            guard span > 0 else { return frame.position }
            let progress = frame.easing.apply((time - previous.t) / span)

            // pathStyle on the DEPARTING keyframe governs this segment.
            guard previous.pathStyle == .curved else {
                return CGPoint(
                    x: previous.position.x + (frame.position.x - previous.position.x) * progress,
                    y: previous.position.y + (frame.position.y - previous.position.y) * progress)
            }
            // Catmull-Rom through the surrounding keyframes, clamping at the
            // ends so a curve at the start or finish does not overshoot.
            let before = index >= 2 ? frames[index - 2].position : previous.position
            let after = index + 1 < frames.count ? frames[index + 1].position : frame.position
            return Self.catmullRom(before, previous.position, frame.position, after,
                                   CGFloat(progress))
        }
        return last.position
    }
}

// MARK: - Scalar Animation

/// A keyframe for a single animated number.
struct ScalarKeyframe: Identifiable, Codable, Hashable {
    let id: UUID
    /// Seconds from the start of the play.
    var t: Double
    var value: Double
    /// How the value arrives here from the previous keyframe.
    var easing: Easing

    init(id: UUID = UUID(), t: Double, value: Double, easing: Easing = .easeInOut) {
        self.id = id
        self.t = t
        self.value = value
        self.easing = easing
    }
}

/// An animated scalar, using the same easing machinery as entity motion.
struct ScalarTrack: Codable, Hashable {
    var keyframes: [ScalarKeyframe]

    init(keyframes: [ScalarKeyframe] = []) {
        self.keyframes = keyframes
    }

    /// A track that holds one value for the whole play.
    init(constant: Double) {
        self.keyframes = [ScalarKeyframe(t: 0, value: constant)]
    }

    var sortedKeyframes: [ScalarKeyframe] { keyframes.sorted { $0.t < $1.t } }

    var duration: Double { sortedKeyframes.last?.t ?? 0 }

    /// True when the value never changes — lets renderers skip per-frame work
    /// and lets the PDF exporter pick a single representative angle.
    var isStatic: Bool {
        let values = keyframes.map(\.value)
        guard let first = values.first else { return true }
        return values.allSatisfy { $0 == first }
    }

    /// Value at `time`, holding the endpoints outside the keyframed range.
    func value(at time: Double) -> Double? {
        let frames = sortedKeyframes
        guard let first = frames.first else { return nil }
        if time <= first.t { return first.value }
        guard let last = frames.last else { return nil }
        if time >= last.t { return last.value }

        for (index, frame) in frames.enumerated() where frame.t > time {
            let previous = frames[index - 1]
            let span = frame.t - previous.t
            guard span > 0 else { return frame.value }
            let progress = frame.easing.apply((time - previous.t) / span)
            return previous.value + (frame.value - previous.value) * progress
        }
        return last.value
    }
}

// MARK: - Ball Possession

/// Who holds the ball, over a time range.
///
/// This is the TIME-VARYING replacement for the static `hasBall` flag that was
/// correctly dropped. A boolean was a second source of truth; a possession
/// interval is not — the ball's position derives from it.
///
/// Deliberately NOT magnetic snapping to the nearest offensive player. Naive
/// proximity grabs whichever player happens to be closest mid-pass and fights
/// the author. Possession is explicit and authored.
struct Possession: Identifiable, Codable, Hashable {
    let id: UUID
    /// The entity holding the ball.
    var holderId: UUID
    /// When possession begins, in node-local seconds.
    var start: Double
    /// When possession ends — the release. Nil means "holds to the end".
    var end: Double?
    /// How possession ended. Nil while still held.
    var release: BallRelease?

    init(id: UUID = UUID(), holderId: UUID, start: Double,
         end: Double? = nil, release: BallRelease? = nil) {
        self.id = id
        self.holderId = holderId
        self.start = start
        self.end = end
        self.release = release
    }

    func contains(_ time: Double) -> Bool {
        guard time >= start else { return false }
        guard let end else { return true }
        return time <= end
    }
}

/// How a possession ended.
///
/// The distinction is the TARGET: dropping the ball on a player is a pass,
/// on the rim it is a shot.
enum BallRelease: Codable, Hashable {
    case pass(toId: UUID)
    /// Target is the rim, in court feet, so the shot survives a court-standard
    /// change without re-deriving from metrics that may have moved.
    case shot(target: CGPoint)
}

/// THE flight curve. One value answers both questions — "where is the ball at
/// this instant" and "what arc do I draw" — because it answers them with the
/// same function.
///
/// It exists because they used to be answered separately: the resolver
/// interpolated between TUCK-ADJUSTED endpoints while the renderer drew
/// CENTRE-to-CENTRE, so the ball flew a constant `ballHeldOffsetFeet` (1.9 ft
/// by default) off its own drawn arc, and a third copy in the frame exporter
/// ignored the shot's parabola entirely. Anything that draws a flight or places
/// the ball in one now samples `position(atProgress:)`; the drawn path is that
/// same function sampled, so the two cannot drift apart by construction.
///
/// THE ENDPOINTS ARE HANDS, and the line between them is straight.
///
/// A held ball sits BESIDE its holder, so at the instant of release the ball is
/// off the centre line whether anyone likes it or not. Three things cannot all
/// be true at once:
///
///   1. the ball is continuous at the release and the catch (no sideways pop),
///   2. the ball sits exactly on the path that is drawn for it,
///   3. a pass is drawn as a straight line.
///
/// An earlier revision kept (1) and (2) by blending the held offset away over
/// 0.1s at each end — and lost (3): the drawn pass hooked out of the passer's
/// hand and back into the receiver's, measured at **32.8° of turn and 1.54 ft
/// of bow** on an ordinary pass between two players who had last moved in
/// unrelated directions. A crooked pass line is wrong however it is justified.
///
/// So the offset lives in the ENDPOINTS: the flight runs hand-to-hand. All
/// three hold — continuous, ball-on-path, and dead straight — because the
/// off-line points are the ends of the line rather than deviations from it.
struct BallFlight: Equatable {
    /// The holder's HAND at release — his centre plus the held offset.
    var from: CGPoint
    /// The receiver's hand at arrival, or the rim for a shot.
    var to: CGPoint
    var isShot: Bool
    /// Seconds.
    var duration: Double
    /// Parabola height at midpoint, in court feet. Zero for a pass — a pass is
    /// a straight line at constant velocity, and the only curvature a flight
    /// may carry is a shot's arc.
    var arcFeet: CGFloat

    /// Shot arc height. A shot rises; a pass does not.
    static let shotArcFeet: CGFloat = 1.6

    /// THE position function. Everything — the ball on the canvas, the drawn
    /// arc, presentation, export — comes through here.
    func position(atProgress progress: Double) -> CGPoint {
        let p = min(max(progress, 0), 1)
        // A PASS is linear: constant velocity is the whole point of deriving
        // duration from distance. A SHOT decelerates, because a shot does.
        let eased = isShot ? Easing.easeOut.apply(p) : p
        let x = from.x + (to.x - from.x) * CGFloat(eased)
        var y = from.y + (to.y - from.y) * CGFloat(eased)
        if arcFeet != 0 {
            y -= CGFloat(sin(eased * .pi)) * arcFeet
        }
        return CGPoint(x: x, y: y)
    }

    var startPoint: CGPoint { position(atProgress: 0) }
    var endPoint: CGPoint { position(atProgress: 1) }

    private func sampleProgress(from start: Double, samples: Int) -> [Double] {
        let lower = min(max(start, 0), 1)
        var values: [Double] = []
        let count = max(2, samples)
        for step in 0...count {
            values.append(lower + (1 - lower) * Double(step) / Double(count))
        }
        return values
    }

    /// The whole arc in court feet, for drawing.
    func polyline(samples: Int = 24) -> [CGPoint] {
        sampleProgress(from: 0, samples: samples).map { position(atProgress: $0) }
    }

    /// The part still AHEAD of the ball at `progress` — presentation draws only
    /// this, and the frame exporter must draw the same thing.
    func remainingPolyline(from progress: Double, samples: Int = 16) -> [CGPoint] {
        sampleProgress(from: progress, samples: samples).map { position(atProgress: $0) }
    }
}

/// The ball's state at a moment.
///
/// TOTAL: every time resolves to one of these. There is no gap and no nil.
/// The previous shape had a hole — flight duration was computed independently
/// at author time and at render time, so if the receiver moved, the derived
/// window and the stored arrival disagreed and the ball fell through to a
/// fallback that placed it back at its home position. That is what "disappears
/// and reappears instantly" was.
enum BallState: Equatable {
    /// Held by an entity; position derives from the holder.
    case held(holderId: UUID)
    /// Travelling. Carries the CURVE, not loose endpoints: a caller cannot get
    /// the flight's timing without also getting the geometry that draws it.
    case inFlight(BallFlight, progress: Double)
    /// Sitting still at a resolved point: before the first possession, after a
    /// shot completes, or anywhere else nothing else applies.
    case atRest(CGPoint)

    var flight: BallFlight? {
        if case .inFlight(let flight, _) = self { return flight }
        return nil
    }
}

// MARK: - Read Tree

/// What an outgoing edge means.
enum ReadEdgeKind: String, Codable, CaseIterable, Hashable {
    /// A new read — the play continues into fresh action.
    case branch
    /// The play loops back to an earlier node. Continuity offenses do this by
    /// design: Princeton's chin series returns to its starting alignment,
    /// motion offense repeats, and "the defender denies so we're back where we
    /// started" is a legitimate read outcome, not malformed data.
    ///
    /// A return edge TERMINATES the export path — the walk stops rather than
    /// re-entering the cycle. It renders as "returns to <node>" in the PDF and
    /// can drive a real loop in animation export.
    case returns
}

/// A directed edge out of a read node.
///
/// The edge carries the read, because the read is what selects it. `condition`
/// lives here rather than on the target node: with explicit edges, a node's
/// "how did we get here" is a property of the incoming edge, and duplicating it
/// on the node would be a second source of truth.
struct ReadEdge: Identifiable, Codable, Hashable {
    let id: UUID
    /// The node this edge leads to. For `.returns`, an ancestor.
    var targetId: UUID
    var kind: ReadEdgeKind
    /// The defensive read that selects this edge — "if they go under",
    /// "if the help digs".
    var condition: String?

    /// When this edge DEPARTS, in the source node's local time.
    ///
    /// A branch diverges partway through its parent, so a clip runs from the
    /// play's start to the end of that read — not through the parent's unused
    /// tail. Branch duration is therefore the sum of branchTimes along the path
    /// plus the leaf's own duration.
    var branchTime: Double

    /// V2: the branch departs AFTER THIS FRAME of the source read — "after
    /// frame 2, if they go under…". Nil on every pre-rebuild edge, which is
    /// why `branchTime` is still here; Phase E deletes the time.
    var afterFrameIndex: Int?

    /// Where in the TARGET the play resumes, in the target's local time.
    /// Meaningful only for `.returns`.
    ///
    /// Departure and arrival are separate values. A Princeton chin returning to
    /// its starting alignment resumes at the ancestor's t=0, not at whatever
    /// point the branch originally split off — without this the loop cannot
    /// close.
    var returnToTime: Double?

    init(id: UUID = UUID(),
         targetId: UUID,
         kind: ReadEdgeKind = .branch,
         condition: String? = nil,
         branchTime: Double = 0,
         afterFrameIndex: Int? = nil,
         returnToTime: Double? = nil) {
        self.id = id
        self.targetId = targetId
        self.kind = kind
        self.condition = condition
        self.branchTime = branchTime
        self.afterFrameIndex = afterFrameIndex
        self.returnToTime = kind == .returns ? (returnToTime ?? 0) : returnToTime
    }

    enum CodingKeys: String, CodingKey {
        case id, targetId, kind, condition, branchTime, afterFrameIndex, returnToTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        targetId = try c.decode(UUID.self, forKey: .targetId)
        kind = try c.decodeIfPresent(ReadEdgeKind.self, forKey: .kind) ?? .branch
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        branchTime = try c.decodeIfPresent(Double.self, forKey: .branchTime) ?? 0
        afterFrameIndex = try c.decodeIfPresent(Int.self, forKey: .afterFrameIndex)
        returnToTime = try c.decodeIfPresent(Double.self, forKey: .returnToTime)
    }
}

/// A node in the play's read graph.
///
/// A play is not a linear sequence. Each node is a slice of action, and its
/// outgoing edges are the alternative continuations depending on what the
/// defense does.
///
/// Nodes are stored flat on the diagram and referenced by id rather than nested
/// inline. Nesting a recursive struct forces indirection and makes editing a
/// deep branch an O(depth) rewrite; a flat table keeps edits local and the
/// Codable output readable. It also lets a `.returns` edge point at an ancestor,
/// which a nested tree cannot express at all.
struct ReadNode: Identifiable, Codable, Hashable {
    let id: UUID
    /// Short name for the branch, e.g. "Base" or "Reject".
    var title: String
    /// Coaching notes for this branch specifically.
    var teachingPoints: [String] = []
    /// Motion for this slice. Time is local to the node: each node starts at 0.
    ///
    /// SUPERSEDED BY `frames` (Play Editor v2, Phase A) and deleted in Phase E.
    /// Both exist during the rebuild so the current editor keeps working; no
    /// code reads both.
    var tracks: [Track] = []
    /// Ordered outgoing edges. Order is the order they appear in the UI.
    var edges: [ReadEdge] = []
    /// Who holds the ball, and when. Sorted by start time.
    ///
    /// Under v2 this is DERIVED from the frames' actions rather than authored —
    /// see `FrameSequence.derivedPossessions`. The model is unchanged, which is
    /// the point: everything downstream of possession keeps working.
    var possessions: [Possession] = []
    /// V2: this read's frames, in order. Empty on every play authored before
    /// the rebuild.
    var frames: [PlayFrame] = []

    init(id: UUID = UUID(),
         title: String,
         teachingPoints: [String] = [],
         tracks: [Track] = [],
         edges: [ReadEdge] = [],
         possessions: [Possession] = [],
         frames: [PlayFrame] = []) {
        self.id = id
        self.title = title
        self.teachingPoints = teachingPoints
        self.tracks = tracks
        self.edges = edges
        self.possessions = possessions
        self.frames = frames
    }

    enum CodingKeys: String, CodingKey {
        case id, title, teachingPoints, tracks, edges, possessions, frames
    }

    /// Hand-written so a blob stored before v2 decodes with no frames rather
    /// than failing outright — the same additive idiom `Keyframe` and
    /// `ReadEdge` already use.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        teachingPoints = try c.decodeIfPresent([String].self, forKey: .teachingPoints) ?? []
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        edges = try c.decodeIfPresent([ReadEdge].self, forKey: .edges) ?? []
        possessions = try c.decodeIfPresent([Possession].self, forKey: .possessions) ?? []
        frames = try c.decodeIfPresent([PlayFrame].self, forKey: .frames) ?? []
    }

    var sortedPossessions: [Possession] { possessions.sorted { $0.start < $1.start } }

    /// Possessions whose holder still resolves to a real entity.
    ///
    /// A possession referencing a deleted or never-existing entity produced
    /// "held by ?" and a position of (0,0) — the holder lookup fell back to
    /// .zero and the ball teleported to the origin. Filtering here means no
    /// downstream code can resolve against a phantom holder.
    func validPossessions(resolving entityExists: (UUID) -> Bool) -> [Possession] {
        sortedPossessions.filter { entityExists($0.holderId) }
    }

    /// Ball state at `time`. Never returns nothing.
    ///
    /// THE DERIVATION LIVES IN `BallDerivation` (extracted Phase D, verbatim),
    /// because the FRAME model needs exactly this answer from a different set
    /// of possessions and a different position resolver. All this wrapper adds
    /// is dropping phantom holders and handing over the stored array.
    func ballState(at time: Double,
                   passSpeed: Double,
                   shotSpeed: Double,
                   ballHome: CGPoint,
                   heldOffsetFeet: CGFloat = 0,
                   entityExists: ((UUID) -> Bool)? = nil,
                   positionOf: (UUID, Double) -> CGPoint) -> BallState {
        // Phantom holders are dropped rather than resolved against.
        let sorted = entityExists.map { validPossessions(resolving: $0) } ?? sortedPossessions
        return BallDerivation.state(possessions: sorted, at: time,
                                    passSpeed: passSpeed, shotSpeed: shotSpeed,
                                    ballHome: ballHome,
                                    offset: .alongMotion(feet: heldOffsetFeet),
                                    positionOf: positionOf)
    }

    /// Where a held ball sits: BESIDE the holder, not on top of him.
    func heldPosition(_ holderId: UUID, at time: Double,
                      heldOffsetFeet: CGFloat,
                      positionOf: (UUID, Double) -> CGPoint) -> CGPoint {
        BallDerivation.heldPosition(holderId, at: time,
                                    offset: .alongMotion(feet: heldOffsetFeet),
                                    positionOf: positionOf)
    }

    /// THE flight builder — see `BallDerivation.flight`.
    func ballFlight(after possession: Possession,
                    among possessions: [Possession]? = nil,
                    passSpeed: Double,
                    shotSpeed: Double,
                    heldOffsetFeet: CGFloat,
                    positionOf: (UUID, Double) -> CGPoint) -> BallFlight? {
        BallDerivation.flight(after: possession,
                              among: possessions ?? sortedPossessions,
                              passSpeed: passSpeed, shotSpeed: shotSpeed,
                              offset: .alongMotion(feet: heldOffsetFeet),
                              positionOf: positionOf)
    }

    /// Resolved ball position. Total by construction — see `ballState`.
    func ballPosition(at time: Double,
                      passSpeed: Double,
                      shotSpeed: Double,
                      ballHome: CGPoint,
                      heldOffsetFeet: CGFloat,
                      entityExists: ((UUID) -> Bool)? = nil,
                      positionOf: (UUID, Double) -> CGPoint) -> CGPoint {
        let sorted = entityExists.map { validPossessions(resolving: $0) } ?? sortedPossessions
        return BallDerivation.position(possessions: sorted, at: time,
                                       passSpeed: passSpeed, shotSpeed: shotSpeed,
                                       ballHome: ballHome,
                                       offset: .alongMotion(feet: heldOffsetFeet),
                                       positionOf: positionOf)
    }

    /// When a released ball arrives. Derived from the flight, so the timeline's
    /// breakpoint, the inspector's "Flight" figure and the ball on the canvas
    /// are the same number by construction.
    func arrivalTime(of possession: Possession,
                     passSpeed: Double,
                     shotSpeed: Double,
                     positionOf: (UUID, Double) -> CGPoint) -> Double? {
        guard let releaseTime = possession.end,
              let flight = ballFlight(after: possession, passSpeed: passSpeed,
                                      shotSpeed: shotSpeed, heldOffsetFeet: 0,
                                      positionOf: positionOf)
        else { return nil }
        return releaseTime + flight.duration
    }

    /// Whether this entity holds the ball at `time` — the holder's own movement
    /// line renders as a dribble.
    func isDribbling(_ entityId: UUID, at time: Double) -> Bool {
        sortedPossessions.contains { $0.holderId == entityId && $0.contains(time) }
    }

    // MARK: - Possession repair
    //
    // Deleting possession events must never orphan the ball. Two primitive
    // repairs cover every case; both keep the invariant "possessions are
    // non-overlapping, sorted, and every release names the next holder".

    /// Deletes the ATTACH boundary of a possession: the previous possession
    /// absorbs this one's span — the previous holder keeps the ball through —
    /// inheriting its end and release. Deleting the first possession's attach
    /// simply removes it; if nothing remains the ball rests at home, which is
    /// a defined state, not an error.
    mutating func deleteAttach(of possessionId: UUID) {
        let sorted = sortedPossessions
        guard let index = sorted.firstIndex(where: { $0.id == possessionId }) else { return }
        let doomed = sorted[index]
        if index > 0 {
            let previousId = sorted[index - 1].id
            if let previousIndex = possessions.firstIndex(where: { $0.id == previousId }) {
                possessions[previousIndex].end = doomed.end
                possessions[previousIndex].release = doomed.release
            }
        }
        possessions.removeAll { $0.id == possessionId }
    }

    /// Deletes the RELEASE of a possession — which is also how deleting a
    /// FLIGHT works, since a pass is one release plus the next attach as a
    /// unit. The holder keeps the ball through the following possession's
    /// span (absorbing its end and release); with no follower the holder
    /// simply keeps the ball to the end of the read.
    mutating func deleteRelease(of possessionId: UUID) {
        let sorted = sortedPossessions
        guard let index = sorted.firstIndex(where: { $0.id == possessionId }),
              let holderIndex = possessions.firstIndex(where: { $0.id == possessionId })
        else { return }
        if index + 1 < sorted.count {
            let next = sorted[index + 1]
            possessions[holderIndex].end = next.end
            possessions[holderIndex].release = next.release
            possessions.removeAll { $0.id == next.id }
        } else {
            possessions[holderIndex].end = nil
            possessions[holderIndex].release = nil
        }
    }

    /// Retimes a possession's attach, clamped so ranges stay ordered.
    mutating func retimeAttach(of possessionId: UUID, to time: Double) {
        guard let index = possessions.firstIndex(where: { $0.id == possessionId }) else { return }
        var lower = 0.0
        let sorted = sortedPossessions
        if let position = sorted.firstIndex(where: { $0.id == possessionId }), position > 0,
           let previousEnd = sorted[position - 1].end {
            lower = previousEnd
        }
        let upper = possessions[index].end ?? .greatestFiniteMagnitude
        possessions[index].start = min(max(time, lower), upper - 0.01)
    }

    /// Retimes a possession's release; the receiving possession's attach moves
    /// with it so the flight stays a coherent unit.
    mutating func retimeRelease(of possessionId: UUID, to time: Double,
                                passSpeed: Double,
                                positionOf: (UUID, Double) -> CGPoint) {
        guard let index = possessions.firstIndex(where: { $0.id == possessionId }),
              possessions[index].end != nil else { return }
        let newEnd = max(possessions[index].start + 0.01, time)
        possessions[index].end = newEnd
        if case .pass(let toId) = possessions[index].release {
            let from = positionOf(possessions[index].holderId, newEnd)
            let to = positionOf(toId, newEnd)
            let distance = Double(hypot(to.x - from.x, to.y - from.y))
            let arrival = newEnd + max(0.08, distance / max(passSpeed, 1))
            let sorted = sortedPossessions
            if let position = sorted.firstIndex(where: { $0.id == possessionId }),
               position + 1 < sorted.count,
               sorted[position + 1].holderId == toId,
               let nextIndex = possessions.firstIndex(where: { $0.id == sorted[position + 1].id }) {
                possessions[nextIndex].start = arrival
            }
        }
    }

    /// Releases with the CURVE each one draws.
    ///
    /// The line derives from possession rather than being drawn separately, so
    /// there is one source of truth for "the ball went from here to there" —
    /// and it hands back the same `BallFlight` the resolver samples, so a
    /// renderer cannot draw an arc the ball does not fly.
    func releases(passSpeed: Double,
                  shotSpeed: Double,
                  heldOffsetFeet: CGFloat = 0,
                  positionOf: (UUID, Double) -> CGPoint)
    -> [(flight: BallFlight, release: BallRelease, departure: Double, arrival: Double)] {
        BallDerivation.releases(possessions: sortedPossessions,
                                passSpeed: passSpeed, shotSpeed: shotSpeed,
                                offset: .alongMotion(feet: heldOffsetFeet),
                                positionOf: positionOf)
    }

    var duration: Double { tracks.map(\.duration).max() ?? 0 }

    /// One homogeneous span of ball behaviour, for the timeline's state bar.
    /// Times are NODE-LOCAL, like everything else on a read.
    struct BallSpan: Hashable {
        enum Kind: Hashable {
            /// Held, holder stationary.
            case rest
            /// Held, holder travelling — the movement ∧ possession overlap
            /// that also drives auto-dribble.
            case dribble
            case flightPass
            case flightShot
            /// Nobody holds it: before the first possession, or resting at
            /// the rim after a shot.
            case loose
        }
        var kind: Kind
        var start: Double
        var end: Double
        /// The holder (held spans) or the releasing player (flights).
        var holderId: UUID?
    }

    /// Partitions [0, windowEnd] into ball-state spans. TOTAL and gap-free by
    /// construction: breakpoints come from the possession events, derived
    /// arrivals, and the holder's keyframes; each interval is then CLASSIFIED
    /// THROUGH `ballState` itself, so the bar cannot disagree with what the
    /// canvas renders. Dribble-vs-rest applies the same movement ∧ possession
    /// rule as auto-dribble, at span granularity.
    func ballSpans(windowEnd: Double,
                   passSpeed: Double,
                   shotSpeed: Double,
                   moveThresholdFeet: CGFloat = 0.3,
                   entityExists: ((UUID) -> Bool)? = nil,
                   positionOf: (UUID, Double) -> CGPoint) -> [BallSpan] {
        guard windowEnd > 0.001 else { return [] }
        let sorted = entityExists.map { validPossessions(resolving: $0) } ?? sortedPossessions

        // Every moment the ball's state (or its holder's motion) can change.
        var cuts: Set<Double> = [0, windowEnd]
        for possession in sorted {
            cuts.insert(possession.start)
            if let end = possession.end { cuts.insert(end) }
            if let arrival = arrivalTime(of: possession, passSpeed: passSpeed,
                                         shotSpeed: shotSpeed, positionOf: positionOf) {
                cuts.insert(arrival)
            }
            if let track = tracks.first(where: { $0.entityId == possession.holderId }) {
                let upper = possession.end ?? windowEnd
                for frame in track.keyframes
                where frame.t > possession.start && frame.t < upper {
                    cuts.insert(frame.t)
                }
            }
        }
        let ordered = cuts.filter { $0 >= 0 && $0 <= windowEnd }.sorted()

        var spans: [BallSpan] = []
        for index in 0..<(ordered.count - 1) {
            let a = ordered[index], b = ordered[index + 1]
            guard b - a > 0.0001 else { continue }
            let mid = (a + b) / 2
            let state = ballState(at: mid, passSpeed: passSpeed, shotSpeed: shotSpeed,
                                  ballHome: .zero, entityExists: entityExists,
                                  positionOf: positionOf)
            let kind: BallSpan.Kind
            var holder: UUID?
            switch state {
            case .held(let holderId):
                holder = holderId
                kind = holderTravels(holderId, from: a, to: b, positionOf: positionOf,
                                     threshold: moveThresholdFeet) ? .dribble : .rest
            case .inFlight(let flight, _):
                kind = flight.isShot ? .flightShot : .flightPass
                holder = sorted.last { ($0.end ?? .infinity) <= mid }?.holderId
            case .atRest:
                kind = .loose
                holder = nil
            }
            if var last = spans.last, last.kind == kind, last.holderId == holder {
                last.end = b
                spans[spans.count - 1] = last
            } else {
                spans.append(BallSpan(kind: kind, start: a, end: b, holderId: holder))
            }
        }
        return spans
    }

    /// Whether the holder covers real ground in [a, b] — sampled arc length,
    /// so a curved path that wanders and returns still counts its travel.
    private func holderTravels(_ entityId: UUID, from a: Double, to b: Double,
                               positionOf: (UUID, Double) -> CGPoint,
                               threshold: CGFloat) -> Bool {
        var length: CGFloat = 0
        var previous = positionOf(entityId, a)
        for step in 1...6 {
            let t = a + (b - a) * Double(step) / 6
            let point = positionOf(entityId, t)
            length += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
            if length >= threshold { return true }
        }
        return false
    }

    /// Edges that continue into new action.
    var branchEdges: [ReadEdge] { edges.filter { $0.kind == .branch } }

    /// Edges that loop back. At most one is meaningful in practice.
    var returnEdges: [ReadEdge] { edges.filter { $0.kind == .returns } }

    /// No new action follows. A node whose only outgoing edge is a return is
    /// still terminal for export purposes.
    var isTerminal: Bool { branchEdges.isEmpty }
}

// MARK: - Diagram

/// The complete spatial model for one play.
struct PlayDiagram: Identifiable, Codable, Hashable {
    let id: UUID
    /// The `Play` this diagram illustrates. Parallel model: `Play` keeps its
    /// prose and step list untouched, so the frozen iOS UI keeps working.
    var playId: UUID
    var space: CourtSpace
    /// Everything that can appear on the floor.
    var entities: [DiagramEntity]
    /// Flat node table. Walk it from `rootNodeId` via each node's `edges`.
    var nodes: [ReadNode]
    var rootNodeId: UUID

    /// Camera elevation over time, in DEGREES:
    ///   90 = straight down (plan view, what a clipboard diagram looks like)
    ///    0 = at floor level
    /// Values between are the oblique look, applied as a perspective projection
    /// of the court plane at render time.
    ///
    /// This is a track, not a scalar, because the oblique-to-top-down move is
    /// the signature output of this tool — "start at 55 degrees, ease to 90
    /// over two seconds" is the shot, and a single angle cannot express it.
    /// It reuses the same easing machinery as entity motion.
    var camera: ScalarTrack
    /// Selected colour theme, by name. Stored on the diagram so a play keeps
    /// the look it was authored for; export can still override per output.
    var themeName: String
    /// V2: ONE pace setting per play — every action's duration comes from its
    /// path length ÷ the pace for its kind. Optional so pre-rebuild blobs
    /// decode; `effectivePace` is what code should read.
    var pace: PlayPace?

    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         playId: UUID,
         space: CourtSpace = CourtSpace(),
         entities: [DiagramEntity] = [],
         nodes: [ReadNode]? = nil,
         rootNodeId: UUID? = nil,
         camera: ScalarTrack = ScalarTrack(constant: 90),
         themeName: String = CourtTheme.video.name,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.playId = playId
        self.space = space
        self.entities = entities
        // A diagram always has a root, so an empty one is still walkable.
        let root = ReadNode(title: "Base")
        self.nodes = nodes ?? [root]
        self.rootNodeId = rootNodeId ?? nodes?.first?.id ?? root.id
        self.camera = camera
        self.themeName = themeName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Camera elevation at a point in time, defaulting to plan view.
    func cameraAngle(at time: Double) -> Double {
        camera.value(at: time) ?? 90
    }

    func node(_ id: UUID) -> ReadNode? {
        nodes.first { $0.id == id }
    }

    var rootNode: ReadNode? { node(rootNodeId) }

    /// Nodes reachable by `.branch` edges. Return edges are deliberately
    /// excluded — they close a loop rather than continue the play.
    func children(of nodeId: UUID) -> [ReadNode] {
        guard let node = node(nodeId) else { return [] }
        return node.branchEdges.compactMap { self.node($0.targetId) }
    }

    func entity(_ id: UUID) -> DiagramEntity? {
        entities.first { $0.id == id }
    }

    /// The ball, if one exists. There is at most one — enforced in the model by
    /// `canAddBall`, not merely disabled in the UI, so no code path can create
    /// a second and leave possession ambiguous.
    var ball: DiagramEntity? {
        entities.first { if case .ball = $0.kind { return true } else { return false } }
    }

    var canAddBall: Bool { ball == nil }

    /// One node in a branch, with when the play entered it.
    struct BranchStep {
        var node: ReadNode
        /// Absolute play time at which this node's local t=0 begins.
        var startsAt: Double
    }

    /// One complete way the play can unfold.
    struct Branch {
        var steps: [BranchStep]
        /// Set when the path ended on a `.returns` edge.
        var returnsTo: ReadNode?
        /// Where in the target the loop resumes, in the target's local time.
        var returnToTime: Double?

        var nodes: [ReadNode] { steps.map(\.node) }

        /// Sum of branchTimes along the path plus the leaf's own duration —
        /// NOT the sum of full node durations. A clip runs to the end of this
        /// read, not through each parent's unused tail.
        var duration: Double {
            guard let last = steps.last else { return 0 }
            return last.startsAt + last.node.duration
        }

        /// Absolute time at which the loop departs, for looping export.
        var loopsAt: Double? {
            guard returnsTo != nil, let last = steps.last else { return nil }
            let departure = last.node.returnEdges.first?.branchTime ?? last.node.duration
            return last.startsAt + departure
        }
    }

    /// Default ceiling on path enumeration. Three reads per node at depth five
    /// is 243 paths; Triangle-family material goes deeper still.
    static let defaultBranchLimit = 256

    /// Every root-to-terminal path. DERIVED, NEVER PERSISTED — materialized
    /// paths duplicate node payloads and explode combinatorially, which would
    /// collide with the CKRecord size budget. `SDPlayDiagram` stores the flat
    /// node table only; this is computed on demand.
    ///
    /// A `.returns` edge terminates its path rather than re-entering the loop,
    /// so continuity offenses enumerate cleanly. The visited set remains as a
    /// backstop against genuine corruption — a `.branch` edge pointing at an
    /// ancestor — not as the cycle strategy.
    func branches(limit: Int = PlayDiagram.defaultBranchLimit) -> (branches: [Branch], truncated: Bool) {
        guard let root = rootNode else { return ([], false) }
        var result: [Branch] = []
        var truncated = false

        func walk(_ node: ReadNode, _ prefix: [BranchStep], _ offset: Double, _ visited: Set<UUID>) {
            guard result.count < limit else { truncated = true; return }
            // Corruption backstop only: a branch edge that loops.
            guard !visited.contains(node.id) else { return }

            let path = prefix + [BranchStep(node: node, startsAt: offset)]
            let branchEdges = node.branchEdges

            if branchEdges.isEmpty {
                let returnEdge = node.returnEdges.first
                let target = returnEdge.flatMap { self.node($0.targetId) }
                result.append(Branch(steps: path, returnsTo: target,
                                     returnToTime: returnEdge?.returnToTime))
                return
            }

            let seen = visited.union([node.id])
            for edge in branchEdges {
                guard let kid = self.node(edge.targetId) else { continue }
                // The child's local t=0 begins where the branch departed.
                walk(kid, path, offset + edge.branchTime, seen)
            }
        }

        walk(root, [], 0, [])
        return (result, truncated)
    }

    /// Longest path duration, computed by memoized DFS rather than by
    /// materializing every path — O(V+E) instead of exponential.
    var totalDuration: Double {
        var memo: [UUID: Double] = [:]

        func longest(_ nodeId: UUID, _ visited: Set<UUID>) -> Double {
            if let cached = memo[nodeId] { return cached }
            guard !visited.contains(nodeId), let node = node(nodeId) else { return 0 }
            let seen = visited.union([nodeId])
            // A branch departs partway through, so onward time is measured from
            // the departure rather than from the end of this node.
            let onward = node.branchEdges
                .map { $0.branchTime + longest($0.targetId, seen) }
                .max() ?? 0
            let total = max(node.duration, onward)
            // Only memoize when no cycle guard was in play on this path, so a
            // truncated result never poisons the cache.
            if node.branchEdges.allSatisfy({ !seen.contains($0.targetId) }) {
                memo[nodeId] = total
            }
            return total
        }

        return longest(rootNodeId, [])
    }

    /// Cheap structural size, for list display and size budgeting.
    var nodeCount: Int { nodes.count }

    // MARK: - Chained playback resolution

    /// Index of the segment containing `time` along a path.
    static func segmentIndex(at time: Double, steps: [BranchStep]) -> Int {
        var index = 0
        for (i, step) in steps.enumerated() where step.startsAt <= time { index = i }
        return index
    }

    /// Node-local time at which this segment's window ends — the read
    /// boundary. Unbounded for the last segment, which owns the tail.
    ///
    /// Lives beside `segmentIndex` so renderers and the resolver agree about
    /// who owns the boundary instant: `segmentIndex` resolves the tie forward,
    /// so at exactly `readEnd` the ARRIVING read is active and the ending
    /// read's paths must already be gone.
    static func localWindowEnd(segment: Int, steps: [BranchStep]) -> Double {
        guard segment + 1 < steps.count else { return .infinity }
        return steps[segment + 1].startsAt - steps[segment].startsAt
    }

    /// Entity position at ABSOLUTE path time.
    ///
    /// Continuous across segment boundaries by construction: a read without a
    /// track for the entity resolves to where the entity stood at the moment
    /// of branching, recursively. This is the single resolver behind editor
    /// playback and, later, the frame exporter — they must agree, so it lives
    /// here rather than in the view model.
    static func resolvedPosition(of entityId: UUID,
                                 at time: Double,
                                 steps: [BranchStep],
                                 entities: [DiagramEntity]) -> CGPoint {
        guard !steps.isEmpty else {
            return entities.first { $0.id == entityId }?.homePosition ?? .zero
        }
        let index = segmentIndex(at: time, steps: steps)
        return segmentPosition(of: entityId, segment: index,
                               localTime: time - steps[index].startsAt,
                               steps: steps, entities: entities)
    }

    static func segmentPosition(of entityId: UUID,
                                segment: Int,
                                localTime: Double,
                                steps: [BranchStep],
                                entities: [DiagramEntity]) -> CGPoint {
        let node = steps[segment].node
        if let track = node.tracks.first(where: { $0.entityId == entityId }),
           let point = track.position(at: localTime) {
            return point
        }
        if segment > 0 {
            let branchLocal = steps[segment].startsAt - steps[segment - 1].startsAt
            return segmentPosition(of: entityId, segment: segment - 1,
                                   localTime: branchLocal,
                                   steps: steps, entities: entities)
        }
        return entities.first { $0.id == entityId }?.homePosition ?? .zero
    }
}

// MARK: - Mirroring

extension PlayDiagram {
    /// Flips the play across the court's long axis: x → width − x.
    ///
    /// A MODEL operation, not a render flag. Mirroring at render time would
    /// leave the stored geometry and the teaching-point text disagreeing with
    /// what is on screen, and any export that skipped the flag would emit the
    /// unmirrored play.
    ///
    /// Left/right words in prose are swapped too. A mirrored play whose
    /// coaching note still says "cut off the left elbow" is worse than not
    /// mirroring at all, because the diagram now contradicts its own
    /// instructions.
    func mirroredHorizontally() -> PlayDiagram {
        var copy = self
        let width = space.width

        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: width - point.x, y: point.y)
        }

        copy.entities = entities.map { entity in
            var e = entity
            e.homePosition = flip(entity.homePosition)
            if case .annotation(.polygon(let points)) = entity.kind {
                e.kind = .annotation(.polygon(points.map(flip)))
            }
            return e
        }

        copy.nodes = nodes.map { node in
            var n = node
            n.teachingPoints = node.teachingPoints.map { Self.swapSides(in: $0) }
            n.tracks = node.tracks.map { track in
                var t = track
                t.keyframes = track.keyframes.map { frame in
                    var f = frame
                    f.position = flip(frame.position)
                    f.controlPoints = frame.controlPoints.map(flip)
                    return f
                }
                return t
            }
            n.edges = node.edges.map { edge in
                var e = edge
                e.condition = edge.condition.map { Self.swapSides(in: $0) }
                return e
            }
            return n
        }

        copy.updatedAt = Date()
        return copy
    }

    /// Swaps left/right words in English and Chinese.
    ///
    /// ONE pass over a single alternation, mapping each match to its
    /// counterpart. A two-pass approach cannot work: replacing "left"→"right"
    /// and then "right"→"left" immediately undoes the first pass, which is
    /// exactly the bug the round-trip test caught.
    ///
    /// Latin terms match on word boundaries so "strong-side" and names survive;
    /// CJK has no word boundaries so those match directly. Longer terms are
    /// listed first so "lefty" wins over "left".
    static func swapSides(in text: String) -> String {
        let mapping: [String: String] = [
            "lefty": "righty", "righty": "lefty",
            "Lefty": "Righty", "Righty": "Lefty",
            "left": "right",   "right": "left",
            "Left": "Right",   "Right": "Left",
            "LEFT": "RIGHT",   "RIGHT": "LEFT",
            "左": "右",        "右": "左"
        ]
        // Longest first so "lefty" is preferred over "left".
        let terms = mapping.keys.sorted { $0.count > $1.count }
        let alternation = terms.map { term -> String in
            let escaped = NSRegularExpression.escapedPattern(for: term)
            return term.allSatisfy(\.isASCII) ? "\\b\(escaped)\\b" : escaped
        }.joined(separator: "|")

        guard let regex = try? NSRegularExpression(pattern: alternation) else { return text }
        let full = NSRange(text.startIndex..., in: text)
        var result = ""
        var cursor = text.startIndex

        for match in regex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[cursor..<range.lowerBound]
            let matched = String(text[range])
            result += mapping[matched] ?? matched
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}

// MARK: - Play Families

/// A variation that stays linked to a base diagram.
///
/// Deliberately "fork with linkage" rather than live inheritance: the variant
/// owns replacement subtrees and can be told to pull changes from the base.
/// Live structural inheritance breaks down as soon as the base deletes a node a
/// variant overrode, and the resolution rules for that are worse than an
/// explicit re-sync.
struct PlayVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// The diagram this variant derives from.
    var baseDiagramId: UUID
    /// The variant's own diagram.
    var diagramId: UUID
    /// Node ids in the base that this variant replaces.
    var overriddenNodeIds: [UUID]
    /// When the variant last pulled from the base, for staleness display.
    var lastSyncedWithBase: Date?

    init(id: UUID = UUID(),
         name: String,
         baseDiagramId: UUID,
         diagramId: UUID,
         overriddenNodeIds: [UUID] = [],
         lastSyncedWithBase: Date? = nil) {
        self.id = id
        self.name = name
        self.baseDiagramId = baseDiagramId
        self.diagramId = diagramId
        self.overriddenNodeIds = overriddenNodeIds
        self.lastSyncedWithBase = lastSyncedWithBase
    }
}
