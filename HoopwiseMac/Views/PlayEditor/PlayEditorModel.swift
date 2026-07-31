import SwiftUI
import Combine

/// Authoring state for the court editor.
///
/// Owns one `PlayDiagram` and the transient editor state around it — selection,
/// playhead, playback, and the tunable look parameters. All geometry edits go
/// through here so the diagram is mutated in exactly one place.
@MainActor
final class PlayEditorModel: ObservableObject {

    @Published var diagram: PlayDiagram
    /// The read node being authored. Branch navigation arrives with step (d);
    /// until then this is always the root.
    @Published var activeNodeId: UUID
    @Published var selectedEntityId: UUID?
    /// Seconds into the active node.
    @Published var playhead: Double = 0
    @Published var isPlaying = false
    @Published var look: CourtLookParameters = .default
    /// Camera elevation being authored at the playhead, in degrees.
    @Published var cameraElevation: Double = 90
    /// Easing applied to the next camera keyframe.
    @Published var cameraEasing: Easing = .easeInOut

    /// Minimum length of the scrubbable timeline, so an empty diagram still has
    /// somewhere to place the first keyframe.
    static let minimumTimelineDuration: Double = 6

    private var playbackTimer: AnyCancellable?
    private var lastTick: Date?
    private var autosave: AnyCancellable?

    /// Set by the view so edits reach SwiftData.
    weak var dataManager: SwiftDataManager?
    /// Undo target, set by the view.
    weak var undoManager: UndoManager?

    @Published var diagramName: String = "Untitled Play"
    @Published var showMovementPaths = true
    @Published var snapEnabled = true
    @Published var snapInterval: Double = 0.25
    /// Keyframes selected in the timeline, as (entityId, keyframeId).
    @Published var selectedKeyframeIds: Set<UUID> = []

    var theme: CourtTheme {
        CourtTheme.all.first { $0.name == diagram.themeName } ?? .video
    }

    func setTheme(_ theme: CourtTheme) {
        registerUndo("Change Theme")
        diagram.themeName = theme.name
        look.theme = theme
    }

    /// Rounds a time to the snap grid when snapping is on.
    func snapped(_ time: Double) -> Double {
        guard snapEnabled, snapInterval > 0 else { return max(0, time) }
        return max(0, (time / snapInterval).rounded() * snapInterval)
    }

    // MARK: - Undo

    /// Registers the CURRENT diagram so undo restores it wholesale.
    ///
    /// Snapshotting the value tree is the right granularity here: the diagram
    /// is a document, and a drag must produce ONE undo entry rather than one
    /// per mouse-move. Callers register before mutating, and drags register
    /// only on gesture start.
    func registerUndo(_ name: String) {
        guard let undoManager else { return }
        let snapshot = diagram
        undoManager.registerUndo(withTarget: self) { model in
            // Re-register so redo works, and so repeated undo walks back.
            model.registerUndo(name)
            model.diagram = snapshot
        }
        undoManager.setActionName(name)
    }

    // MARK: - Persistence

    /// Autosaves after edits settle. The Basketball Lab lost work at quit; a
    /// diagram that only saves on an explicit command would do the same.
    func startAutosave() {
        autosave = $diagram
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    func save() {
        dataManager?.savePlayDiagram(diagram, name: diagramName)
    }

    init(diagram: PlayDiagram) {
        self.diagram = diagram
        self.activeNodeId = diagram.rootNodeId
        self.cameraElevation = diagram.cameraAngle(at: 0)
    }

    /// A new empty half-court FIBA diagram, so the editor always opens on
    /// something authorable.
    static func newDiagram() -> PlayDiagram {
        PlayDiagram(playId: UUID(), space: CourtSpace(standard: .fiba, mode: .half))
    }

    // MARK: - Active Node

    var activeNode: ReadNode? { diagram.node(activeNodeId) }

    var timelineDuration: Double {
        max(Self.minimumTimelineDuration, (activeNode?.duration ?? 0) + 2)
    }

    private func mutateActiveNode(_ body: (inout ReadNode) -> Void) {
        guard let index = diagram.nodes.firstIndex(where: { $0.id == activeNodeId }) else { return }
        body(&diagram.nodes[index])
        diagram.updatedAt = Date()
    }

    // MARK: - Entities

    /// Whether this kind can still be placed. Only the ball is limited.
    func canPlace(_ kind: DiagramEntityKind) -> Bool {
        if case .ball = kind { return diagram.canAddBall }
        return true
    }

    func addEntity(kind: DiagramEntityKind, at courtPoint: CGPoint, label: String?) {
        // Model-level guard, not just a disabled button: a second ball would
        // make possession ambiguous and there is no correct way to resolve it.
        guard canPlace(kind) else { return }
        registerUndo("Place Entity")
        let entity = DiagramEntity(kind: kind,
                                   label: label,
                                   homePosition: diagram.space.clamp(courtPoint))
        diagram.entities.append(entity)
        selectedEntityId = entity.id

        // The ball NEVER gets a position track while possession is on. Placing
        // it used to author a keyframe, leaving a leftover track alongside the
        // possession resolver — two answers to "where is the ball", which is
        // the second-source-of-truth problem the resolver exists to remove.
        // Placement on empty floor authors nothing; dropping on a player
        // authors possession.
        if case .ball = kind, possessionEnabled { return }

        // Everything else gets a keyframe at the playhead so it is immediately
        // part of the animation rather than a static prop.
        setKeyframe(for: entity.id, at: playhead, position: entity.homePosition)
    }

    func deleteSelectedEntity() {
        guard let id = selectedEntityId else { return }
        registerUndo("Delete Entity")
        diagram.entities.removeAll { $0.id == id }
        mutateActiveNode { node in
            node.tracks.removeAll { $0.entityId == id }
            // Deleting a holder must not leave a possession pointing at him.
            node.possessions.removeAll { $0.holderId == id }
            for index in node.possessions.indices {
                if case .pass(let toId) = node.possessions[index].release, toId == id {
                    node.possessions[index].release = nil
                    node.possessions[index].end = nil
                }
            }
        }
        selectedEntityId = nil
    }

    /// Drops possessions whose holder no longer resolves. Called on load so a
    /// diagram saved with a phantom holder repairs itself rather than
    /// teleporting the ball forever.
    func repairPossessions() {
        for index in diagram.nodes.indices {
            diagram.nodes[index].possessions.removeAll { diagram.entity($0.holderId) == nil }
        }
    }

    func entity(_ id: UUID) -> DiagramEntity? { diagram.entity(id) }

    /// THE position authority. Drawing, hit testing, the timeline and the
    /// inspector all go through this.
    ///
    /// The ball is resolved by possession; everything else by its track. Hit
    /// testing used to read `position(of:)` directly, which for a ball with no
    /// track returned its home position — so after the first pass the ball was
    /// drawn by the resolver but hit-tested somewhere else entirely, and became
    /// unselectable. If it is drawn at a point it must be selectable there.
    func resolvedPosition(of entityId: UUID, at time: Double) -> CGPoint {
        if let ball = diagram.ball, ball.id == entityId,
           possessionEnabled, let derived = ballPosition(at: time) {
            return derived
        }
        return position(of: entityId, at: time)
    }

    /// Raw track position. Prefer `resolvedPosition(of:at:)` unless you
    /// specifically need the underlying track.
    func position(of entityId: UUID, at time: Double) -> CGPoint {
        if let track = track(for: entityId), let point = track.position(at: time) {
            return point
        }
        return diagram.entity(entityId)?.homePosition ?? .zero
    }

    func track(for entityId: UUID) -> Track? {
        activeNode?.tracks.first { $0.entityId == entityId }
    }

    // MARK: - Keyframes

    /// Sets or moves this entity's keyframe at `time`.
    ///
    /// Dragging on the canvas calls this with the playhead, which is the whole
    /// authoring loop: scrub to a moment, move a player, a keyframe appears.
    /// Default line kind for an entity. A DEFAULT per kind, not something set
    /// per path: player movement is continuous, ball movement is dashed.
    func defaultPathKind(for entityId: UUID) -> PathKind {
        guard let entity = diagram.entity(entityId) else { return .run }
        if case .ball = entity.kind { return .pass }
        return .run
    }

    func setKeyframe(for entityId: UUID, at time: Double, position: CGPoint) {
        let clamped = diagram.space.clamp(position)
        let defaultKind = defaultPathKind(for: entityId)
        mutateActiveNode { node in
            if let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId }) {
                if let frameIndex = node.tracks[trackIndex].keyframes
                    .firstIndex(where: { abs($0.t - time) < 0.02 }) {
                    node.tracks[trackIndex].keyframes[frameIndex].position = clamped
                } else {
                    node.tracks[trackIndex].keyframes.append(
                        Keyframe(t: time, position: clamped,
                                 pathKind: defaultKind))
                    node.tracks[trackIndex].keyframes.sort { $0.t < $1.t }
                }
            } else {
                node.tracks.append(Track(entityId: entityId,
                                         keyframes: [Keyframe(t: time, position: clamped,
                                                              pathKind: defaultKind)]))
            }
        }
    }

    func deleteKeyframe(entityId: UUID, keyframeId: UUID) {
        registerUndo("Delete Keyframe")
        mutateActiveNode { node in
            guard let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId })
            else { return }
            node.tracks[trackIndex].keyframes.removeAll { $0.id == keyframeId }
            if node.tracks[trackIndex].keyframes.isEmpty {
                node.tracks.remove(at: trackIndex)
            }
        }
    }

    func moveKeyframe(entityId: UUID, keyframeId: UUID, to time: Double) {
        mutateActiveNode { node in
            guard let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId }),
                  let frameIndex = node.tracks[trackIndex].keyframes
                    .firstIndex(where: { $0.id == keyframeId }) else { return }
            node.tracks[trackIndex].keyframes[frameIndex].t = max(0, time)
            node.tracks[trackIndex].keyframes.sort { $0.t < $1.t }
        }
    }

    func updateKeyframe(entityId: UUID,
                        keyframeId: UUID,
                        easing: Easing? = nil,
                        pathKind: PathKind? = nil,
                        pathStyle: PathStyle? = nil) {
        registerUndo(easing != nil ? "Change Easing"
                     : (pathStyle != nil ? "Change Path Style" : "Change Path Kind"))
        mutateActiveNode { node in
            guard let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId }),
                  let frameIndex = node.tracks[trackIndex].keyframes
                    .firstIndex(where: { $0.id == keyframeId }) else { return }
            if let easing { node.tracks[trackIndex].keyframes[frameIndex].easing = easing }
            if let pathKind { node.tracks[trackIndex].keyframes[frameIndex].pathKind = pathKind }
            if let pathStyle { node.tracks[trackIndex].keyframes[frameIndex].pathStyle = pathStyle }
        }
    }

    /// The keyframe at the playhead for the selected entity, if there is one.
    var selectedKeyframe: Keyframe? {
        guard let id = selectedEntityId, let track = track(for: id) else { return nil }
        return track.keyframes.first { abs($0.t - playhead) < 0.02 }
    }

    /// Whether this is the last keyframe on its track — its pathKind governs no
    /// segment, per the model's segment convention.
    func isFinalKeyframe(_ keyframe: Keyframe, entityId: UUID) -> Bool {
        guard let track = track(for: entityId) else { return true }
        return track.sortedKeyframes.last?.id == keyframe.id
    }

    // MARK: - Possession

    /// Whether the ball follows possession or its own keyframes.
    @Published var possessionEnabled = true

    var possessions: [Possession] { activeNode?.sortedPossessions ?? [] }

    /// Rim position for the near basket, in court feet — the shot target.
    var rimPosition: CGPoint { diagram.space.metrics.nearBasket }

    /// Whether a court point is close enough to the rim to count as a shot.
    func isRimTarget(_ court: CGPoint) -> Bool {
        let rim = rimPosition
        return hypot(court.x - rim.x, court.y - rim.y) <= 3.5
    }

    /// Ball home, used before anything is authored.
    private var ballHome: CGPoint { diagram.ball?.homePosition ?? rimPosition }

    func ballState(at time: Double) -> BallState {
        guard let node = activeNode else { return .atRest(ballHome) }
        return node.ballState(at: time,
                              passSpeed: look.passSpeedFeetPerSecond,
                              shotSpeed: look.shotSpeedFeetPerSecond,
                              ballHome: ballHome,
                              heldOffsetFeet: look.ballHeldOffsetFeet,
                              entityExists: { [weak self] in self?.diagram.entity($0) != nil }) { [weak self] id, t in
            self?.position(of: id, at: t) ?? .zero
        }
    }

    /// Whether this entity is dribbling at the playhead — its own movement line
    /// then renders with the dribble convention and the ball draws none.
    func isDribbling(_ entityId: UUID, at time: Double) -> Bool {
        activeNode?.isDribbling(entityId, at: time) ?? false
    }

    /// A possession change worth showing on the timeline.
    struct PossessionEvent: Identifiable {
        let id: UUID
        let time: Double
        let label: String
        let color: Color
    }

    /// Possession start, pass departure, arrival, and shot release.
    var possessionEvents: [PossessionEvent] {
        guard let node = activeNode else { return [] }
        var events: [PossessionEvent] = []
        for possession in node.sortedPossessions {
            let who = entityLabel(possession.holderId)
            events.append(PossessionEvent(id: possession.id, time: possession.start,
                                          label: "\(who) gains possession", color: .green))
            guard let end = possession.end, let release = possession.release else { continue }
            switch release {
            case .pass(let toId):
                events.append(PossessionEvent(id: UUID(), time: end,
                                              label: "\(who) passes to \(entityLabel(toId))",
                                              color: .orange))
            case .shot:
                events.append(PossessionEvent(id: UUID(), time: end,
                                              label: "\(who) shoots", color: .red))
            }
        }
        return events
    }

    private func entityLabel(_ id: UUID) -> String {
        guard let entity = diagram.entity(id) else { return "?" }
        if case .player(let team, _, _) = entity.kind {
            return "\(team == .offense ? "O" : "D")\(entity.label ?? "")"
        }
        return entity.label ?? "Ball"
    }

    /// Gives the ball to `holderId` starting at `time`. Used for the first drop.
    func beginPossession(_ holderId: UUID, at time: Double) {
        // A possession must name a real entity. Creating one for a missing id
        // is what produced "held by ?" and a (0,0) resolution.
        guard diagram.entity(holderId) != nil else { return }
        registerUndo("Give Possession")
        mutateActiveNode { node in
            node.possessions.removeAll { $0.start >= time }
            for index in node.possessions.indices where node.possessions[index].end == nil {
                node.possessions[index].end = max(node.possessions[index].start, time)
                node.possessions[index].release = nil
            }
            node.possessions.append(Possession(holderId: holderId, start: time))
            node.possessions.sort { $0.start < $1.start }
        }
    }

    /// Authors a pass: the current holder releases at `time` and the receiver
    /// gains possession when the ball ARRIVES, derived from distance / speed.
    func authorPass(to receiverId: UUID, at time: Double) {
        guard diagram.entity(receiverId) != nil else { return }
        // The holder is whoever has it at `time`, or failing that the most
        // recent possession starting at or before it. Requiring an exact
        // .held match meant a drop just after a release silently became a new
        // possession instead of a pass, and no release was ever recorded — so
        // no derived line was drawn.
        let holder = activeNode?.sortedPossessions.last { $0.contains(time) }
            ?? activeNode?.sortedPossessions.last { $0.start <= time }
        guard let node = activeNode, let holding = holder,
              holding.holderId != receiverId else {
            beginPossession(receiverId, at: time)
            return
        }
        _ = node
        registerUndo("Author Pass")

        let from = position(of: holding.holderId, at: time)
        let to = position(of: receiverId, at: time)
        let distance = Double(hypot(to.x - from.x, to.y - from.y))
        let arrival = time + max(0.08, distance / max(look.passSpeedFeetPerSecond, 1))

        mutateActiveNode { node in
            guard let index = node.possessions.firstIndex(where: { $0.id == holding.id })
            else { return }
            node.possessions[index].end = time
            node.possessions[index].release = .pass(toId: receiverId)
            node.possessions.removeAll { $0.start > time && $0.id != holding.id }
            node.possessions.append(Possession(holderId: receiverId, start: arrival))
            node.possessions.sort { $0.start < $1.start }
        }
    }

    /// Authors a shot at the rim. Possession ends and nothing receives it.
    func authorShot(at time: Double) {
        let holder = activeNode?.sortedPossessions.last { $0.contains(time) }
            ?? activeNode?.sortedPossessions.last { $0.start <= time }
        guard let holding = holder else { return }
        registerUndo("Author Shot")
        let target = rimPosition
        mutateActiveNode { node in
            guard let index = node.possessions.firstIndex(where: { $0.id == holding.id })
            else { return }
            node.possessions[index].end = time
            node.possessions[index].release = .shot(target: target)
            node.possessions.removeAll { $0.start > time }
        }
    }

    func clearPossessions() {
        mutateActiveNode { $0.possessions.removeAll() }
    }

    /// Ball position honouring possession when enabled. NEVER nil.
    func ballPosition(at time: Double) -> CGPoint? {
        guard let ball = diagram.ball else { return nil }
        guard possessionEnabled, let node = activeNode else {
            return position(of: ball.id, at: time)
        }
        return node.ballPosition(at: time,
                                 passSpeed: look.passSpeedFeetPerSecond,
                                 shotSpeed: look.shotSpeedFeetPerSecond,
                                 ballHome: ballHome,
                                 heldOffsetFeet: look.ballHeldOffsetFeet,
                                 entityExists: { [weak self] in self?.diagram.entity($0) != nil }) { [weak self] id, t in
            self?.position(of: id, at: t) ?? .zero
        }
    }

    // MARK: - Camera

    /// Records the current elevation as a camera keyframe at the playhead.
    func setCameraKeyframe() {
        registerUndo("Set Camera Keyframe")
        var frames = diagram.camera.keyframes
        if let index = frames.firstIndex(where: { abs($0.t - playhead) < 0.02 }) {
            frames[index].value = cameraElevation
            frames[index].easing = cameraEasing
        } else {
            frames.append(ScalarKeyframe(t: playhead, value: cameraElevation, easing: cameraEasing))
            frames.sort { $0.t < $1.t }
        }
        diagram.camera.keyframes = frames
        diagram.updatedAt = Date()
    }

    func clearCameraTrack() {
        registerUndo("Clear Camera Track")
        diagram.camera.keyframes = []
    }

    /// Updates one camera keyframe's easing from the timeline.
    func updateCameraKeyframe(id: UUID, easing: Easing) {
        registerUndo("Change Camera Easing")
        guard let index = diagram.camera.keyframes.firstIndex(where: { $0.id == id }) else { return }
        diagram.camera.keyframes[index].easing = easing
    }

    /// Which stored diagram is open, for library selection.
    var currentDiagramId: UUID { diagram.id }

    /// Replaces the whole diagram, e.g. when opening a play from the library.
    func load(_ stored: PlayDiagram, name: String? = nil) {
        diagram = stored
        if let name { diagramName = name }
        activeNodeId = stored.rootNodeId
        selectedEntityId = nil
        selectedKeyframeIds = []
        cursorEntityId = nil
        playhead = 0
        // Stale from the previous play. The playback-path Picker bridges to
        // NSPopUpButton, and selecting an index beyond its item range raises
        // "Index out of range" — which is exactly what clicking a read did
        // after switching from a play with more paths to one with fewer.
        activeBranchIndex = 0
        stop()
        repairPossessions()
        look.theme = CourtTheme.all.first { $0.name == stored.themeName } ?? .video
    }

    /// Elevation to render at the playhead. While scrubbing, the authored track
    /// wins; the slider follows it.
    var renderElevation: Double {
        diagram.camera.isStatic ? cameraElevation : diagram.cameraAngle(at: playhead)
    }

    // MARK: - Read Tree

    /// Which root-to-leaf path is being previewed. nil means the first.
    @Published var activeBranchIndex: Int = 0

    var branches: [PlayDiagram.Branch] {
        diagram.branches(limit: 64).branches
    }

    var activeBranch: PlayDiagram.Branch? {
        let all = branches
        guard !all.isEmpty else { return nil }
        return all[max(0, min(activeBranchIndex, all.count - 1))]
    }

    /// Nodes on the active path, for highlighting the tree.
    var activePathNodeIds: Set<UUID> {
        Set(activeBranch?.nodes.map(\.id) ?? [])
    }

    func node(_ id: UUID) -> ReadNode? { diagram.node(id) }

    /// One rendered line of the tree.
    struct TreeRow: Identifiable {
        enum Kind { case node(ReadNode), returnEdge(from: ReadNode, edge: ReadEdge) }
        let id: UUID
        var kind: Kind
        var depth: Int
        var incoming: ReadEdge?
    }

    /// The tree flattened depth-first.
    ///
    /// Flat rather than recursive views: a recursive @ViewBuilder cannot infer
    /// its own opaque return type, and a flat list re-renders far more cheaply.
    var treeRows: [TreeRow] {
        var rows: [TreeRow] = []
        var visited: Set<UUID> = []

        func walk(_ nodeId: UUID, _ depth: Int, _ incoming: ReadEdge?) {
            guard !visited.contains(nodeId), let node = diagram.node(nodeId) else { return }
            visited.insert(nodeId)
            rows.append(TreeRow(id: node.id, kind: .node(node), depth: depth, incoming: incoming))
            for edge in node.branchEdges {
                walk(edge.targetId, depth + 1, edge)
            }
            for edge in node.returnEdges {
                rows.append(TreeRow(id: edge.id, kind: .returnEdge(from: node, edge: edge),
                                    depth: depth + 1, incoming: nil))
            }
        }

        walk(diagram.rootNodeId, 0, nil)
        return rows
    }

    func parentOf(_ nodeId: UUID) -> ReadNode? {
        diagram.nodes.first { $0.branchEdges.contains { $0.targetId == nodeId } }
    }

    func depth(of nodeId: UUID) -> Int {
        var depth = 0
        var current = nodeId
        var guardCount = 0
        while let parent = parentOf(current), guardCount < 64 {
            depth += 1
            current = parent.id
            guardCount += 1
        }
        return depth
    }

    /// Adds an alternative read branching off `nodeId` at `time`.
    ///
    /// The child's tracks INHERIT the parent's entity positions at the
    /// divergence as their first keyframe: a read diverges from a shared
    /// position, it does not teleport. The child stays node-local starting at
    /// 0; when the branch departed is recorded on the EDGE as branchTime.
    @discardableResult
    func addBranch(from nodeId: UUID, at time: Double, condition: String) -> UUID? {
        guard let parent = diagram.node(nodeId) else { return nil }
        registerUndo("Add Read")

        var child = ReadNode(title: condition.isEmpty ? "New Read" : condition)
        for track in parent.tracks {
            guard let position = track.position(at: time) else { continue }
            child.tracks.append(Track(entityId: track.entityId,
                                      keyframes: [Keyframe(t: 0, position: position)]))
        }
        // Possession carries across the divergence too, otherwise the ball
        // would drop the moment a read branches.
        if let holding = parent.sortedPossessions.last(where: { $0.contains(time) }) {
            child.possessions = [Possession(holderId: holding.holderId, start: 0)]
        }

        diagram.nodes.append(child)
        if let index = diagram.nodes.firstIndex(where: { $0.id == nodeId }) {
            diagram.nodes[index].edges.append(
                ReadEdge(targetId: child.id, kind: .branch,
                         condition: condition.isEmpty ? nil : condition,
                         branchTime: time))
        }
        diagram.updatedAt = Date()
        return child.id
    }

    /// Adds a return edge from `nodeId` back to `targetId`.
    ///
    /// No inheritance: a return does not create a node, it hands control back
    /// to one that already has its own tracks from its own t=0.
    func addReturn(from nodeId: UUID, to targetId: UUID,
                   departingAt: Double, resumingAt: Double, condition: String) {
        guard diagram.node(targetId) != nil,
              let index = diagram.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        registerUndo("Add Return")
        diagram.nodes[index].edges.removeAll { $0.kind == .returns }
        diagram.nodes[index].edges.append(
            ReadEdge(targetId: targetId, kind: .returns,
                     condition: condition.isEmpty ? nil : condition,
                     branchTime: departingAt, returnToTime: resumingAt))
        diagram.updatedAt = Date()
    }

    func removeEdge(from nodeId: UUID, edgeId: UUID) {
        guard let index = diagram.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        registerUndo("Remove Read")
        diagram.nodes[index].edges.removeAll { $0.id == edgeId }
        diagram.updatedAt = Date()
        clampBranchIndex()
    }

    /// Deletes a read node and everything below it.
    func deleteNode(_ nodeId: UUID) {
        guard nodeId != diagram.rootNodeId else { return }
        registerUndo("Delete Read")
        var doomed: Set<UUID> = [nodeId]
        var frontier = [nodeId]
        while let current = frontier.popLast() {
            for edge in diagram.node(current)?.branchEdges ?? [] where !doomed.contains(edge.targetId) {
                doomed.insert(edge.targetId)
                frontier.append(edge.targetId)
            }
        }
        diagram.nodes.removeAll { doomed.contains($0.id) }
        for index in diagram.nodes.indices {
            diagram.nodes[index].edges.removeAll { doomed.contains($0.targetId) }
        }
        if doomed.contains(activeNodeId) { activeNodeId = diagram.rootNodeId }
        diagram.updatedAt = Date()
        clampBranchIndex()
    }

    /// Keeps activeBranchIndex inside the current branch list. Every structural
    /// tree change must call this — the index outliving the list is the crash
    /// class, not a cosmetic issue.
    func clampBranchIndex() {
        let count = branches.count
        activeBranchIndex = max(0, min(activeBranchIndex, max(0, count - 1)))
    }

    func renameNode(_ nodeId: UUID, to title: String) {
        guard let index = diagram.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        registerUndo("Rename Read")
        diagram.nodes[index].title = title
    }

    func updateEdge(from nodeId: UUID, edgeId: UUID,
                    condition: String? = nil,
                    branchTime: Double? = nil,
                    returnToTime: Double? = nil) {
        guard let nodeIndex = diagram.nodes.firstIndex(where: { $0.id == nodeId }),
              let edgeIndex = diagram.nodes[nodeIndex].edges.firstIndex(where: { $0.id == edgeId })
        else { return }
        registerUndo("Edit Read")
        if let condition { diagram.nodes[nodeIndex].edges[edgeIndex].condition = condition }
        if let branchTime { diagram.nodes[nodeIndex].edges[edgeIndex].branchTime = max(0, branchTime) }
        if let returnToTime { diagram.nodes[nodeIndex].edges[edgeIndex].returnToTime = max(0, returnToTime) }
    }

    /// How far entity positions jump when a return edge closes the loop.
    ///
    /// A continuity offence returns to its starting alignment, so a large gap
    /// means the play was mis-authored. Surfaced rather than silently
    /// interpolated — smoothing it would hide the error.
    func returnContinuityGap(for nodeId: UUID) -> Double? {
        guard let node = diagram.node(nodeId),
              let edge = node.returnEdges.first,
              let target = diagram.node(edge.targetId) else { return nil }
        let departAt = edge.branchTime
        let resumeAt = edge.returnToTime ?? 0
        var worst: Double = 0
        for track in node.tracks {
            guard let here = track.position(at: departAt),
                  let there = target.tracks.first(where: { $0.entityId == track.entityId })?
                    .position(at: resumeAt) else { continue }
            worst = max(worst, Double(hypot(there.x - here.x, there.y - here.y)))
        }
        return worst
    }

    // MARK: - Debug Readout

    @Published var showDebugPanel = false
    /// Play list visibility, remembered across launches so the canvas width
    /// choice sticks.
    @Published var libraryVisible: Bool = UserDefaults.standard.object(forKey: "editorLibraryVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(libraryVisible, forKey: "editorLibraryVisible") }
    }
    /// Court point under the cursor, published by the canvas.
    @Published var cursorCourtPoint: CGPoint?
    /// Entity the hit test finds under the cursor.
    @Published var cursorEntityId: UUID?
    /// Active placement tool, published by the editor view.
    @Published var activeToolName: String = "Select"
    /// Last projection used to draw, so the readout can report screen points.
    var lastProjection: CourtProjection?

    /// Everything the editor resolves at the playhead, as text.
    ///
    /// This exists because three increments of ball bugs each passed a model
    /// test while the UI still misbehaved. The gap was that runtime resolution
    /// was invisible, so every cycle cost a full round trip. Paste this instead
    /// of describing symptoms.
    var debugReadout: String {
        var lines: [String] = []
        lines.append(String(format: "t = %.3f s   (duration %.2f)", playhead, timelineDuration))
        lines.append("tool: \(activeToolName)   possession: \(possessionEnabled ? "on" : "off")")
        lines.append("camera: \(Int(renderElevation))°  theme: \(theme.name)")

        if let ball = diagram.ball {
            let state = ballState(at: playhead)
            lines.append("— ball —")
            lines.append("state: \(describe(state))")
            let court = ballPosition(at: playhead) ?? .zero
            lines.append(String(format: "court:  (%.2f, %.2f) ft", court.x, court.y))
            if let projection = lastProjection {
                let screen = projection.project(court)
                lines.append(String(format: "screen: (%.1f, %.1f) pt   depthScale %.3f",
                                    screen.x, screen.y, projection.depthScale(at: court)))
            }
            let hasTrack = activeNode?.tracks.contains { $0.entityId == ball.id } ?? false
            lines.append("has position track: \(hasTrack)  \(hasTrack ? "<- SHOULD BE FALSE" : "")")
        } else {
            lines.append("— ball — none placed")
        }

        let possessions = activeNode?.sortedPossessions ?? []
        lines.append("— possessions (\(possessions.count)) —")
        for possession in possessions {
            let end = possession.end.map { String(format: "%.2f", $0) } ?? "open"
            let release: String
            switch possession.release {
            case .pass(let toId): release = "pass -> \(label(toId))"
            case .shot: release = "shot"
            case nil: release = "—"
            }
            let active = possession.contains(playhead) ? " *ACTIVE*" : ""
            lines.append(String(format: "  %@  %.2f..%@  %@%@",
                                label(possession.holderId), possession.start, end, release, active))
        }

        lines.append("— selection —")
        if let id = selectedEntityId {
            let point = resolvedPosition(of: id, at: playhead)
            lines.append(String(format: "  %@ %@  (%.2f, %.2f) ft",
                                label(id), id.uuidString.prefix(8).description, point.x, point.y))
            if let keyframe = selectedKeyframe {
                lines.append(String(format: "  keyframe t=%.2f  %@ / %@",
                                    keyframe.t, keyframe.easing.rawValue, keyframe.pathKind.displayName))
            } else {
                lines.append("  no keyframe at playhead")
            }
        } else {
            lines.append("  none")
        }

        lines.append("— cursor —")
        if let point = cursorCourtPoint {
            lines.append(String(format: "  court (%.2f, %.2f) ft", point.x, point.y))
        } else {
            lines.append("  outside canvas")
        }
        lines.append("  hit: \(cursorEntityId.map { label($0) } ?? "none")")

        return lines.joined(separator: "\n")
    }

    private func describe(_ state: BallState) -> String {
        switch state {
        case .held(let holderId):
            return "held by \(label(holderId))"
        case .inFlight(let from, let to, let progress, let isShot):
            return String(format: "%@ (%.1f,%.1f) -> (%.1f,%.1f) progress %.2f",
                          isShot ? "shot" : "inFlight", from.x, from.y, to.x, to.y, progress)
        case .atRest(let point):
            return String(format: "atRest (%.2f, %.2f)", point.x, point.y)
        }
    }

    private func label(_ id: UUID) -> String { entityLabel(id) }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        guard !isPlaying else { return }
        if playhead >= timelineDuration - 0.05 { playhead = 0 }
        isPlaying = true
        lastTick = Date()
        playbackTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        isPlaying = false
        playbackTimer?.cancel()
        playbackTimer = nil
        lastTick = nil
    }

    private func tick() {
        // Wall-clock delta rather than a fixed step, so playback runs at real
        // speed even if the timer coalesces under load.
        let now = Date()
        let delta = lastTick.map { now.timeIntervalSince($0) } ?? (1.0 / 60.0)
        lastTick = now
        playhead += delta
        if playhead >= timelineDuration {
            playhead = timelineDuration
            stop()
        }
        if !diagram.camera.isStatic {
            cameraElevation = diagram.cameraAngle(at: playhead)
        }
    }

    // MARK: - Whole-diagram operations

    func mirror() {
        registerUndo("Mirror Play")
        diagram = diagram.mirroredHorizontally()
    }

    /// Deletes every selected keyframe.
    func deleteSelectedKeyframes() {
        guard !selectedKeyframeIds.isEmpty else { return }
        registerUndo("Delete Keyframes")
        mutateActiveNode { node in
            for index in node.tracks.indices {
                node.tracks[index].keyframes.removeAll { selectedKeyframeIds.contains($0.id) }
            }
            node.tracks.removeAll { $0.keyframes.isEmpty }
        }
        selectedKeyframeIds.removeAll()
    }

    /// Nudges every selected keyframe in time — arrow keys.
    func nudgeSelectedKeyframes(by delta: Double) {
        guard !selectedKeyframeIds.isEmpty else { return }
        registerUndo("Nudge Keyframes")
        mutateActiveNode { node in
            for trackIndex in node.tracks.indices {
                for frameIndex in node.tracks[trackIndex].keyframes.indices
                where selectedKeyframeIds.contains(node.tracks[trackIndex].keyframes[frameIndex].id) {
                    let current = node.tracks[trackIndex].keyframes[frameIndex].t
                    node.tracks[trackIndex].keyframes[frameIndex].t = max(0, current + delta)
                }
                node.tracks[trackIndex].keyframes.sort { $0.t < $1.t }
            }
        }
    }

    func setCourt(standard: CourtStandard? = nil, mode: CourtMode? = nil) {
        if let standard { diagram.space.standard = standard }
        if let mode { diagram.space.mode = mode }
        diagram.updatedAt = Date()
    }
}
