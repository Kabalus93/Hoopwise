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
    /// Seconds along the ACTIVE PLAYBACK PATH — absolute branch time, not
    /// node-local. Segment boundaries are derived; scrubbing across one is
    /// seamless because resolution is continuous by construction.
    @Published var playhead: Double = 0 {
        didSet { syncActiveNodeToPlayhead() }
    }
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
        isDirty = true
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

    /// The segments of the active playback path, in order. Never empty.
    var activeSteps: [PlayDiagram.BranchStep] {
        if let steps = activeBranch?.steps, !steps.isEmpty { return steps }
        if let root = diagram.rootNode {
            return [PlayDiagram.BranchStep(node: root, startsAt: 0)]
        }
        return []
    }

    /// Full concatenated duration of the active path.
    var branchDuration: Double {
        activeBranch?.duration ?? (activeNode?.duration ?? 0)
    }

    var timelineDuration: Double {
        max(Self.minimumTimelineDuration, branchDuration + 1)
    }

    /// Index of the segment the playhead is inside.
    func segmentIndex(at time: Double) -> Int {
        PlayDiagram.segmentIndex(at: time, steps: activeSteps)
    }

    var currentStep: PlayDiagram.BranchStep? {
        let steps = activeSteps
        guard !steps.isEmpty else { return nil }
        return steps[segmentIndex(at: playhead)]
    }

    /// Playhead expressed in the current segment's node-local time.
    var currentLocalTime: Double {
        guard let step = currentStep else { return playhead }
        return max(0, playhead - step.startsAt)
    }

    /// Keeps the authoring target on the segment under the playhead, so canvas
    /// edits always land in the read being watched.
    private func syncActiveNodeToPlayhead() {
        guard let step = currentStep, step.node.id != activeNodeId else { return }
        activeNodeId = step.node.id
    }

    /// Selects a read: switches the active path to one containing it if needed,
    /// then moves the playhead to where that read begins.
    func selectNode(_ nodeId: UUID) {
        let all = branches
        if !(activeBranch?.steps.contains { $0.node.id == nodeId } ?? false) {
            if let index = all.firstIndex(where: { $0.steps.contains { $0.node.id == nodeId } }) {
                activeBranchIndex = index
            }
        }
        activeNodeId = nodeId
        if let step = activeSteps.first(where: { $0.node.id == nodeId }) {
            playhead = step.startsAt
        } else {
            playhead = 0
        }
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

    /// THE position authority, in ABSOLUTE branch time. Drawing, hit testing,
    /// the timeline and the inspector all go through this.
    ///
    /// Segment boundaries are continuous by construction: a read without its
    /// own track for an entity resolves to where that entity stood at the
    /// moment of branching, recursively — so nothing snaps back to a start
    /// position when playback crosses into a child read.
    func resolvedPosition(of entityId: UUID, at time: Double) -> CGPoint {
        if let ball = diagram.ball, ball.id == entityId,
           possessionEnabled, let derived = ballPosition(at: time) {
            return derived
        }
        let steps = activeSteps
        guard !steps.isEmpty else { return position(of: entityId, at: time) }
        let index = segmentIndex(at: time)
        return segmentPosition(of: entityId, segment: index,
                               localTime: time - steps[index].startsAt, steps: steps)
    }

    private func segmentPosition(of entityId: UUID, segment: Int,
                                 localTime: Double,
                                 steps: [PlayDiagram.BranchStep]) -> CGPoint {
        // Delegates to the shared resolver so editor playback and the frame
        // exporter cannot disagree.
        PlayDiagram.segmentPosition(of: entityId, segment: segment,
                                    localTime: localTime,
                                    steps: steps, entities: diagram.entities)
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
        // Continuity pin: creating a fresh track mid-read in a non-first
        // segment also writes the inherited position at t=0, so the read still
        // starts where its parent left the entity rather than holding the new
        // keyframe backwards to the boundary.
        let steps = activeSteps
        let segment = segmentIndex(at: playhead)
        var boundaryPin: CGPoint?
        if segment > 0, time > 0.02,
           let node = activeNode,
           node.tracks.first(where: { $0.entityId == entityId }) == nil {
            let branchLocal = steps[segment].startsAt - steps[segment - 1].startsAt
            boundaryPin = segmentPosition(of: entityId, segment: segment - 1,
                                          localTime: branchLocal, steps: steps)
        }
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
                var keyframes = [Keyframe(t: time, position: clamped, pathKind: defaultKind)]
                if let boundaryPin {
                    keyframes.insert(Keyframe(t: 0, position: boundaryPin,
                                              pathKind: defaultKind), at: 0)
                }
                node.tracks.append(Track(entityId: entityId, keyframes: keyframes))
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
    /// Playhead is absolute; keyframes are node-local, so compare in local time.
    var selectedKeyframe: Keyframe? {
        guard let id = selectedEntityId, let track = track(for: id) else { return nil }
        let local = currentLocalTime
        return track.keyframes.first { abs($0.t - local) < 0.02 }
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

    /// Ball state at ABSOLUTE branch time, resolved in the segment under it.
    func ballState(at time: Double) -> BallState {
        let steps = activeSteps
        guard !steps.isEmpty else { return .atRest(ballHome) }
        let index = segmentIndex(at: time)
        let node = steps[index].node
        let local = time - steps[index].startsAt
        return node.ballState(at: local,
                              passSpeed: look.passSpeedFeetPerSecond,
                              shotSpeed: look.shotSpeedFeetPerSecond,
                              ballHome: ballHome,
                              heldOffsetFeet: look.ballHeldOffsetFeet,
                              entityExists: { [weak self] in self?.diagram.entity($0) != nil }) { [weak self] id, t in
            self?.segmentPosition(of: id, segment: index, localTime: t, steps: steps) ?? .zero
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

    /// Possession start, pass departure, arrival, and shot release — across
    /// every segment of the active path, in absolute time.
    var possessionEvents: [PossessionEvent] {
        var events: [PossessionEvent] = []
        for step in activeSteps {
            events.append(contentsOf: possessionEvents(in: step.node, offset: step.startsAt))
        }
        return events
    }

    private func possessionEvents(in node: ReadNode, offset: Double) -> [PossessionEvent] {
        var events: [PossessionEvent] = []
        for possession in node.sortedPossessions {
            let who = entityLabel(possession.holderId)
            events.append(PossessionEvent(id: possession.id, time: offset + possession.start,
                                          label: "\(who) gains possession", color: .green))
            guard let end = possession.end, let release = possession.release else { continue }
            switch release {
            case .pass(let toId):
                events.append(PossessionEvent(id: UUID(), time: offset + end,
                                              label: "\(who) passes to \(entityLabel(toId))",
                                              color: .orange))
            case .shot:
                events.append(PossessionEvent(id: UUID(), time: offset + end,
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
        guard possessionEnabled else { return position(of: ball.id, at: time) }
        let steps = activeSteps
        guard !steps.isEmpty else { return position(of: ball.id, at: time) }
        let index = segmentIndex(at: time)
        let node = steps[index].node
        let local = time - steps[index].startsAt
        // A segment with no possessions of its own inherits the ball from the
        // moment of branching, exactly like entity positions.
        if node.sortedPossessions.isEmpty, index > 0 {
            let branchLocal = steps[index].startsAt - steps[index - 1].startsAt
            let previousSteps = Array(steps.prefix(index))
            let previousNode = previousSteps[index - 1].node
            return previousNode.ballPosition(at: branchLocal,
                                             passSpeed: look.passSpeedFeetPerSecond,
                                             shotSpeed: look.shotSpeedFeetPerSecond,
                                             ballHome: ballHome,
                                             heldOffsetFeet: look.ballHeldOffsetFeet,
                                             entityExists: { [weak self] in self?.diagram.entity($0) != nil }) { [weak self] id, t in
                self?.segmentPosition(of: id, segment: index - 1, localTime: t, steps: steps) ?? .zero
            }
        }
        return node.ballPosition(at: local,
                                 passSpeed: look.passSpeedFeetPerSecond,
                                 shotSpeed: look.shotSpeedFeetPerSecond,
                                 ballHome: ballHome,
                                 heldOffsetFeet: look.ballHeldOffsetFeet,
                                 entityExists: { [weak self] in self?.diagram.entity($0) != nil }) { [weak self] id, t in
            self?.segmentPosition(of: id, segment: index, localTime: t, steps: steps) ?? .zero
        }
    }

    /// Whether `entityId` is dribbling at ABSOLUTE time — has possession and
    /// the segment under the playhead says so.
    func isDribblingAbsolute(_ entityId: UUID, at time: Double) -> Bool {
        let steps = activeSteps
        guard !steps.isEmpty else { return false }
        let index = segmentIndex(at: time)
        return steps[index].node.isDribbling(entityId, at: time - steps[index].startsAt)
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
        // Restore playbook metadata from the owning play.
        if let play = dataManager?.plays.first(where: { $0.id == stored.playId }) {
            savedToPlaybook = !play.formation.isEmpty
            playFamily = play.formation.isEmpty
                ? (UserDefaults.standard.string(forKey: "lastPlayFamily") ?? "Horns")
                : play.formation
            playTags = play.tags.joined(separator: ", ")
            playNote = play.description
        } else {
            savedToPlaybook = false
            playTags = ""
            playNote = ""
        }
        isDirty = false
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

    /// One keyframe as the timeline lane sees it: which node owns it, where it
    /// sits in absolute time, and whether it is inside this path's window
    /// (keyframes past a segment's branch point belong to other paths and
    /// render dimmed).
    struct LaneKeyframe: Identifiable {
        var id: UUID { keyframe.id }
        let nodeId: UUID
        let keyframe: Keyframe
        let absoluteTime: Double
        let inWindow: Bool
    }

    func laneKeyframes(for entityId: UUID) -> [LaneKeyframe] {
        let steps = activeSteps
        var result: [LaneKeyframe] = []
        for (index, step) in steps.enumerated() {
            guard let track = step.node.tracks.first(where: { $0.entityId == entityId }) else { continue }
            let window = index + 1 < steps.count
                ? steps[index + 1].startsAt - step.startsAt
                : Double.greatestFiniteMagnitude
            for keyframe in track.sortedKeyframes {
                result.append(LaneKeyframe(nodeId: step.node.id,
                                           keyframe: keyframe,
                                           absoluteTime: step.startsAt + keyframe.t,
                                           inWindow: keyframe.t <= window + 0.001))
            }
        }
        return result
    }

    /// Segment boundaries for the ruler: absolute time and read title.
    var segmentBoundaries: [(time: Double, title: String)] {
        activeSteps.dropFirst().map { ($0.startsAt, $0.node.title) }
    }

    /// Timeline variant of moveKeyframe that knows which node owns the frame.
    func moveKeyframe(nodeId: UUID, entityId: UUID, keyframeId: UUID, toLocal time: Double) {
        guard let nodeIndex = diagram.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        guard let trackIndex = diagram.nodes[nodeIndex].tracks.firstIndex(where: { $0.entityId == entityId }),
              let frameIndex = diagram.nodes[nodeIndex].tracks[trackIndex].keyframes
                .firstIndex(where: { $0.id == keyframeId }) else { return }
        diagram.nodes[nodeIndex].tracks[trackIndex].keyframes[frameIndex].t = max(0, time)
        diagram.nodes[nodeIndex].tracks[trackIndex].keyframes.sort { $0.t < $1.t }
        diagram.updatedAt = Date()
    }

    // MARK: - Save to Playbook

    static let setFamilies = ["Horns", "1-4 High", "SLOB", "BLOB", "Press Break", "Custom"]

    @Published var playFamily: String =
        UserDefaults.standard.string(forKey: "lastPlayFamily") ?? "Horns"
    @Published var playTags: String = ""
    @Published var playNote: String = ""
    /// Whether this play has been through the Save to Playbook sheet once.
    @Published var savedToPlaybook = false
    /// Changes since the last playbook save — drives the window's edited dot.
    /// The DIAGRAM itself is still autosaved continuously; this tracks the
    /// coach-facing "have I published my latest edits" state only.
    @Published var isDirty = false

    func saveToPlaybook() {
        save()
        let tags = playTags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let thumbnail = PlayThumbnailRenderer.renderAndSave(diagram: diagram,
                                                            theme: theme,
                                                            playId: diagram.playId)
        dataManager?.updatePlayMetadata(playId: diagram.playId,
                                        name: diagramName,
                                        family: playFamily,
                                        tags: tags,
                                        note: playNote,
                                        thumbnailPath: thumbnail)
        UserDefaults.standard.set(playFamily, forKey: "lastPlayFamily")
        savedToPlaybook = true
        isDirty = false
    }

    /// Creates a linked variation: a full copy whose PlayVariant records the
    /// parent, so play families stay connected in the Playbook.
    func saveAsVariation(named name: String) {
        save()
        let copy = PlayDiagram(playId: UUID(),
                               space: diagram.space,
                               entities: diagram.entities,
                               nodes: diagram.nodes,
                               rootNodeId: diagram.rootNodeId,
                               camera: diagram.camera,
                               themeName: diagram.themeName)
        dataManager?.savePlayDiagram(copy, name: name)
        if let row = dataManager?.allPlayDiagrams().first(where: { $0.id == copy.id }) {
            _ = row
        }
        dataManager?.setVariant(diagramId: copy.id,
                                variant: PlayVariant(name: name,
                                                     baseDiagramId: diagram.id,
                                                     diagramId: copy.id))
        let thumbnail = PlayThumbnailRenderer.renderAndSave(diagram: copy,
                                                            theme: theme,
                                                            playId: copy.playId)
        dataManager?.updatePlayMetadata(playId: copy.playId, name: name,
                                        family: playFamily,
                                        tags: [], note: "",
                                        thumbnailPath: thumbnail)
        load(copy, name: name)
        savedToPlaybook = true
        isDirty = false
    }

    // MARK: - AE-style keyframe interaction

    /// Adds a keyframe at the playhead HOLDING the entity's current resolved
    /// value — pinning it where it sits — or removes the keyframe already
    /// there. The AE diamond.
    func toggleKeyframeInPlace(_ entityId: UUID) {
        if let ball = diagram.ball, ball.id == entityId, possessionEnabled { return }
        let local = currentLocalTime
        if let track = track(for: entityId),
           let existing = track.keyframes.first(where: { abs($0.t - local) < 0.02 }) {
            deleteKeyframe(entityId: entityId, keyframeId: existing.id)
            return
        }
        registerUndo("Add Keyframe")
        let pinned = resolvedPosition(of: entityId, at: playhead)
        setKeyframe(for: entityId, at: local, position: pinned)
    }

    /// Whether a keyframe sits at the playhead on this layer — drives the
    /// diamond's filled state.
    func hasKeyframeAtPlayhead(_ entityId: UUID) -> Bool {
        let local = currentLocalTime
        return track(for: entityId)?.keyframes.contains { abs($0.t - local) < 0.02 } ?? false
    }

    /// Jumps the playhead to the previous or next keyframe on this layer.
    func jumpToKeyframe(_ entityId: UUID, direction: Int) {
        let times = laneKeyframes(for: entityId).map(\.absoluteTime).sorted()
        guard !times.isEmpty else { return }
        if direction < 0 {
            if let previous = times.last(where: { $0 < playhead - 0.02 }) { playhead = previous }
        } else {
            if let next = times.first(where: { $0 > playhead + 0.02 }) { playhead = next }
        }
    }

    /// Sets the interpolation of the segment LEAVING a keyframe.
    ///
    /// AE puts interpolation on the outgoing side of the key you clicked; this
    /// model stores easing on the ARRIVING keyframe. So the menu action on
    /// keyframe k writes to the keyframe after it. Same behaviour, different
    /// storage side — documented here because it will look off-by-one in code.
    func setOutgoingEasing(nodeId: UUID, entityId: UUID, keyframeId: UUID, easing: Easing) {
        guard let nodeIndex = diagram.nodes.firstIndex(where: { $0.id == nodeId }),
              let trackIndex = diagram.nodes[nodeIndex].tracks.firstIndex(where: { $0.entityId == entityId })
        else { return }
        let sorted = diagram.nodes[nodeIndex].tracks[trackIndex].sortedKeyframes
        guard let position = sorted.firstIndex(where: { $0.id == keyframeId }),
              position + 1 < sorted.count else { return }
        let nextId = sorted[position + 1].id
        guard let frameIndex = diagram.nodes[nodeIndex].tracks[trackIndex].keyframes
            .firstIndex(where: { $0.id == nextId }) else { return }
        registerUndo(easing == .hold ? "Hold" : "Change Interpolation")
        diagram.nodes[nodeIndex].tracks[trackIndex].keyframes[frameIndex].easing = easing
        diagram.updatedAt = Date()
    }

    // MARK: - Keyframe clipboard

    private struct CopiedKeyframe {
        let entityId: UUID
        let offset: Double        // from the earliest copied keyframe
        let keyframe: Keyframe
    }
    private var keyframeClipboard: [CopiedKeyframe] = []

    /// Copies the selected keyframes, preserving relative spacing.
    func copySelectedKeyframes() {
        var copied: [CopiedKeyframe] = []
        for lane in diagram.entities.flatMap({ laneKeyframes(for: $0.id) })
        where selectedKeyframeIds.contains(lane.keyframe.id) {
            guard let entity = entityForKeyframe(lane.keyframe.id) else { continue }
            copied.append(CopiedKeyframe(entityId: entity, offset: lane.absoluteTime,
                                         keyframe: lane.keyframe))
        }
        guard let earliest = copied.map(\.offset).min() else { return }
        keyframeClipboard = copied.map {
            CopiedKeyframe(entityId: $0.entityId, offset: $0.offset - earliest, keyframe: $0.keyframe)
        }
    }

    /// Pastes at the playhead into each keyframe's ORIGINAL entity, keeping
    /// relative offsets. Cross-entity paste was judged not cheap; same-entity is.
    func pasteKeyframesAtPlayhead() {
        guard !keyframeClipboard.isEmpty else { return }
        registerUndo("Paste Keyframes")
        let baseLocal = currentLocalTime
        for item in keyframeClipboard {
            var frame = Keyframe(t: baseLocal + item.offset,
                                 position: item.keyframe.position,
                                 easing: item.keyframe.easing,
                                 pathKind: item.keyframe.pathKind,
                                 pathStyle: item.keyframe.pathStyle,
                                 controlPoints: item.keyframe.controlPoints)
            frame.t = snapped(frame.t)
            mutateActiveNode { node in
                if let trackIndex = node.tracks.firstIndex(where: { $0.entityId == item.entityId }) {
                    node.tracks[trackIndex].keyframes.append(frame)
                    node.tracks[trackIndex].keyframes.sort { $0.t < $1.t }
                } else {
                    node.tracks.append(Track(entityId: item.entityId, keyframes: [frame]))
                }
            }
        }
    }

    var clipboardHasKeyframes: Bool { !keyframeClipboard.isEmpty }

    private func entityForKeyframe(_ keyframeId: UUID) -> UUID? {
        for step in activeSteps {
            for track in step.node.tracks where track.keyframes.contains(where: { $0.id == keyframeId }) {
                return track.entityId
            }
        }
        return nil
    }

    /// Deletes the selection wherever it lives along the path — not just the
    /// active node.
    func deleteSelectedKeyframesEverywhere() {
        guard !selectedKeyframeIds.isEmpty else { return }
        registerUndo("Delete Keyframes")
        for nodeIndex in diagram.nodes.indices {
            for trackIndex in diagram.nodes[nodeIndex].tracks.indices {
                diagram.nodes[nodeIndex].tracks[trackIndex].keyframes
                    .removeAll { selectedKeyframeIds.contains($0.id) }
            }
            diagram.nodes[nodeIndex].tracks.removeAll { $0.keyframes.isEmpty }
        }
        selectedKeyframeIds.removeAll()
        diagram.updatedAt = Date()
    }

    // MARK: - Layer states (transient; deliberately no undo)

    @Published var hiddenEntityIds: Set<UUID> = []
    @Published var lockedEntityIds: Set<UUID> = []
    /// Solo dims everything else to 25% — AE's focus mode, doubling as the
    /// video-production isolate.
    @Published var soloEntityId: UUID?

    func isHidden(_ id: UUID) -> Bool { hiddenEntityIds.contains(id) }
    func isLocked(_ id: UUID) -> Bool { lockedEntityIds.contains(id) }
    func opacity(for id: UUID) -> Double {
        guard let solo = soloEntityId, solo != id else { return 1 }
        return 0.25
    }

    func renameEntity(_ id: UUID, to label: String) {
        guard let index = diagram.entities.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Rename")
        diagram.entities[index].label = label
        diagram.updatedAt = Date()
    }

    /// Removes every keyframe this entity has in the current read.
    func clearTrack(_ entityId: UUID) {
        registerUndo("Clear Keyframes")
        mutateActiveNode { node in
            node.tracks.removeAll { $0.entityId == entityId }
        }
    }

    /// Copies this entity's current-read track into another read.
    func duplicateTrack(_ entityId: UUID, to nodeId: UUID) {
        guard let track = track(for: entityId),
              let index = diagram.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        registerUndo("Duplicate Track")
        var copy = Track(entityId: entityId,
                         keyframes: track.keyframes.map {
                             Keyframe(t: $0.t, position: $0.position, easing: $0.easing,
                                      pathKind: $0.pathKind, pathStyle: $0.pathStyle,
                                      controlPoints: $0.controlPoints)
                         })
        copy.keyframes.sort { $0.t < $1.t }
        diagram.nodes[index].tracks.removeAll { $0.entityId == entityId }
        diagram.nodes[index].tracks.append(copy)
        diagram.updatedAt = Date()
    }

    // MARK: - Live Ball Drag

    /// View-space cursor location while the ball is being dragged, or nil.
    /// On the model because Esc is handled by the parent view and must be able
    /// to cancel the canvas's gesture mid-flight.
    @Published var ballDragLocation: CGPoint?
    /// Receiver currently within snap radius, for the highlight ring.
    @Published var ballDragSnapTarget: UUID?
    /// Set by Esc. The gesture observes it, stops previewing, and its drop
    /// mutates nothing.
    @Published var ballDragCancelled = false

    var isBallDragging: Bool { ballDragLocation != nil }

    func cancelBallDrag() {
        ballDragCancelled = true
        ballDragLocation = nil
        ballDragSnapTarget = nil
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
