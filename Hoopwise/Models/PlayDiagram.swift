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

    init(id: UUID = UUID(),
         kind: DiagramEntityKind,
         label: String? = nil,
         colorHex: String? = nil,
         homePosition: CGPoint) {
        self.id = id
        self.kind = kind
        self.label = label
        self.colorHex = colorHex
        self.homePosition = homePosition
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

    /// Maps normalized progress 0...1 through the curve.
    func apply(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear:    return x
        case .easeIn:    return x * x
        case .easeOut:   return 1 - (1 - x) * (1 - x)
        case .easeInOut: return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
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
    let id: UUID
    /// Seconds from the start of the owning read node.
    var t: Double
    var position: CGPoint
    /// How motion arrives at this keyframe from the previous one.
    var easing: Easing
    /// What the segment LEAVING this keyframe represents. Ignored on the last
    /// keyframe of a track — see the segment convention above.
    var pathKind: PathKind
    /// Optional bezier control points, in court feet, for curved paths. Empty
    /// means a straight segment.
    var controlPoints: [CGPoint]

    init(id: UUID = UUID(),
         t: Double,
         position: CGPoint,
         easing: Easing = .linear,
         pathKind: PathKind = .run,
         controlPoints: [CGPoint] = []) {
        self.id = id
        self.t = t
        self.position = position
        self.easing = easing
        self.pathKind = pathKind
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
            return CGPoint(
                x: previous.position.x + (frame.position.x - previous.position.x) * progress,
                y: previous.position.y + (frame.position.y - previous.position.y) * progress
            )
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

    init(id: UUID = UUID(),
         targetId: UUID,
         kind: ReadEdgeKind = .branch,
         condition: String? = nil) {
        self.id = id
        self.targetId = targetId
        self.kind = kind
        self.condition = condition
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
    var teachingPoints: [String]
    /// Motion for this slice. Time is local to the node: each node starts at 0.
    var tracks: [Track]
    /// Ordered outgoing edges. Order is the order they appear in the UI.
    var edges: [ReadEdge]

    init(id: UUID = UUID(),
         title: String,
         teachingPoints: [String] = [],
         tracks: [Track] = [],
         edges: [ReadEdge] = []) {
        self.id = id
        self.title = title
        self.teachingPoints = teachingPoints
        self.tracks = tracks
        self.edges = edges
    }

    var duration: Double { tracks.map(\.duration).max() ?? 0 }

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

    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         playId: UUID,
         space: CourtSpace = CourtSpace(),
         entities: [DiagramEntity] = [],
         nodes: [ReadNode]? = nil,
         rootNodeId: UUID? = nil,
         camera: ScalarTrack = ScalarTrack(constant: 90),
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

    /// One complete way the play can unfold: the nodes walked, and the return
    /// edge that closed it if it looped.
    struct Branch {
        var nodes: [ReadNode]
        /// Set when the path ended on a `.returns` edge, for rendering
        /// "returns to <node>" and for looping animation export.
        var returnsTo: ReadNode?

        var duration: Double { nodes.reduce(0) { $0 + $1.duration } }
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

        func walk(_ node: ReadNode, _ prefix: [ReadNode], _ visited: Set<UUID>) {
            guard result.count < limit else { truncated = true; return }
            // Corruption backstop only: a branch edge that loops.
            guard !visited.contains(node.id) else { return }

            let path = prefix + [node]
            let kids = children(of: node.id)

            if kids.isEmpty {
                let target = node.returnEdges.first.flatMap { self.node($0.targetId) }
                result.append(Branch(nodes: path, returnsTo: target))
                return
            }

            let seen = visited.union([node.id])
            for kid in kids { walk(kid, path, seen) }
        }

        walk(root, [], [])
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
            let onward = node.branchEdges
                .map { longest($0.targetId, seen) }
                .max() ?? 0
            let total = node.duration + onward
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
