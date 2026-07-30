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
struct Keyframe: Identifiable, Codable, Hashable {
    let id: UUID
    /// Seconds from the start of the owning read node.
    var t: Double
    var position: CGPoint
    /// How motion arrives at this keyframe from the previous one.
    var easing: Easing
    /// What the segment into this keyframe represents.
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

// MARK: - Read Tree

/// A node in the play's decision tree.
///
/// A play is not a linear sequence. Each node is a slice of action, and its
/// children are the alternative continuations depending on what the defense
/// does. `condition` is the read that selects a branch — "if the help digs",
/// "if they go under the screen".
///
/// Children are referenced by id and stored flat on the diagram rather than
/// nested inline. Nesting a recursive struct forces indirection and makes
/// editing a deep branch an O(depth) rewrite; a flat table with id references
/// keeps edits local and Codable output readable.
struct ReadNode: Identifiable, Codable, Hashable {
    let id: UUID
    /// Short name for the branch, e.g. "Base" or "Reject".
    var title: String
    /// The defensive read that leads here. Nil on the root.
    var condition: String?
    /// Coaching notes for this branch specifically.
    var teachingPoints: [String]
    /// Motion for this slice. Time is local to the node: each node starts at 0.
    var tracks: [Track]
    /// Ordered alternatives. Order is the order they appear in the UI.
    var childIds: [UUID]

    init(id: UUID = UUID(),
         title: String,
         condition: String? = nil,
         teachingPoints: [String] = [],
         tracks: [Track] = [],
         childIds: [UUID] = []) {
        self.id = id
        self.title = title
        self.condition = condition
        self.teachingPoints = teachingPoints
        self.tracks = tracks
        self.childIds = childIds
    }

    var duration: Double { tracks.map(\.duration).max() ?? 0 }

    var isLeaf: Bool { childIds.isEmpty }
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
    /// Flat node table. Walk it from `rootNodeId` via `childIds`.
    var nodes: [ReadNode]
    var rootNodeId: UUID
    /// Oblique camera. 0 is straight-down; 1 is the maximum authored tilt.
    /// Applied as a perspective projection of the court plane at render time,
    /// and animatable — it is a parameter, not a scene.
    var cameraAngle: Double
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         playId: UUID,
         space: CourtSpace = CourtSpace(),
         entities: [DiagramEntity] = [],
         nodes: [ReadNode]? = nil,
         rootNodeId: UUID? = nil,
         cameraAngle: Double = 0,
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
        self.cameraAngle = cameraAngle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func node(_ id: UUID) -> ReadNode? {
        nodes.first { $0.id == id }
    }

    var rootNode: ReadNode? { node(rootNodeId) }

    func children(of nodeId: UUID) -> [ReadNode] {
        guard let node = node(nodeId) else { return [] }
        return node.childIds.compactMap { self.node($0) }
    }

    func entity(_ id: UUID) -> DiagramEntity? {
        entities.first { $0.id == id }
    }

    /// Every root-to-leaf path. Each is one complete way the play can unfold,
    /// and each is what a single animation export renders.
    var branches: [[ReadNode]] {
        guard let root = rootNode else { return [] }
        var result: [[ReadNode]] = []
        var walk: (ReadNode, [ReadNode]) -> Void = { _, _ in }
        walk = { node, prefix in
            let path = prefix + [node]
            let kids = children(of: node.id)
            if kids.isEmpty {
                result.append(path)
            } else {
                for kid in kids { walk(kid, path) }
            }
        }
        walk(root, [])
        return result
    }

    /// Longest branch duration — how long the play runs end to end.
    var totalDuration: Double {
        branches.map { $0.reduce(0) { $0 + $1.duration } }.max() ?? 0
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
