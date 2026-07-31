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
        // A new entity gets a keyframe at the playhead so it is immediately
        // part of the animation rather than a static prop.
        setKeyframe(for: entity.id, at: playhead, position: entity.homePosition)
    }

    func deleteSelectedEntity() {
        guard let id = selectedEntityId else { return }
        registerUndo("Delete Entity")
        diagram.entities.removeAll { $0.id == id }
        mutateActiveNode { node in
            node.tracks.removeAll { $0.entityId == id }
        }
        selectedEntityId = nil
    }

    func entity(_ id: UUID) -> DiagramEntity? { diagram.entity(id) }

    /// Where an entity sits at a given time: its track if it has one, otherwise
    /// its home position.
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
    func setKeyframe(for entityId: UUID, at time: Double, position: CGPoint) {
        let clamped = diagram.space.clamp(position)
        mutateActiveNode { node in
            if let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId }) {
                if let frameIndex = node.tracks[trackIndex].keyframes
                    .firstIndex(where: { abs($0.t - time) < 0.02 }) {
                    node.tracks[trackIndex].keyframes[frameIndex].position = clamped
                } else {
                    node.tracks[trackIndex].keyframes.append(
                        Keyframe(t: time, position: clamped))
                    node.tracks[trackIndex].keyframes.sort { $0.t < $1.t }
                }
            } else {
                node.tracks.append(Track(entityId: entityId,
                                         keyframes: [Keyframe(t: time, position: clamped)]))
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
                        pathKind: PathKind? = nil) {
        registerUndo(easing != nil ? "Change Easing" : "Change Path Kind")
        mutateActiveNode { node in
            guard let trackIndex = node.tracks.firstIndex(where: { $0.entityId == entityId }),
                  let frameIndex = node.tracks[trackIndex].keyframes
                    .firstIndex(where: { $0.id == keyframeId }) else { return }
            if let easing { node.tracks[trackIndex].keyframes[frameIndex].easing = easing }
            if let pathKind { node.tracks[trackIndex].keyframes[frameIndex].pathKind = pathKind }
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

    func ballState(at time: Double) -> BallState {
        guard let node = activeNode else { return .free }
        return node.ballState(at: time,
                              passSpeed: look.passSpeedFeetPerSecond,
                              shotSpeed: look.shotSpeedFeetPerSecond) { [weak self] id, t in
            self?.position(of: id, at: t) ?? .zero
        }
    }

    /// Whether this entity is dribbling at the playhead — its own movement line
    /// then renders with the dribble convention and the ball draws none.
    func isDribbling(_ entityId: UUID, at time: Double) -> Bool {
        activeNode?.isDribbling(entityId, at: time) ?? false
    }

    /// Gives the ball to `holderId` starting at `time`. Used for the first drop.
    func beginPossession(_ holderId: UUID, at time: Double) {
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
        guard let node = activeNode,
              let holding = node.sortedPossessions.last(where: { $0.contains(time) }),
              holding.holderId != receiverId else {
            beginPossession(receiverId, at: time)
            return
        }
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
        guard let node = activeNode,
              let holding = node.sortedPossessions.last(where: { $0.contains(time) }) else { return }
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

    /// Ball position honouring possession when enabled.
    ///
    /// While held it derives from the holder and the ball needs no keyframes of
    /// its own — which is the fix for the drag gesture writing position
    /// keyframes instead of possession.
    func ballPosition(at time: Double) -> CGPoint? {
        guard let ball = diagram.ball else { return nil }
        guard possessionEnabled else { return position(of: ball.id, at: time) }
        switch ballState(at: time) {
        case .held(let holderId):
            return position(of: holderId, at: time)
        case .inFlight(let fromId, let toId, let progress):
            let a = position(of: fromId, at: time)
            let b = position(of: toId, at: time)
            return CGPoint(x: a.x + (b.x - a.x) * progress,
                           y: a.y + (b.y - a.y) * progress)
        case .shot(let fromId, let target, let progress):
            let a = position(of: fromId, at: time)
            // Shallow parabola toward the rim: lateral interpolation plus a
            // perpendicular rise that peaks mid-flight.
            let x = a.x + (target.x - a.x) * progress
            let y = a.y + (target.y - a.y) * progress
            let arc = sin(progress * .pi) * 1.6
            return CGPoint(x: x, y: y - arc)
        case .free:
            return position(of: ball.id, at: time)
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

    /// Replaces the whole diagram, e.g. when reopening stored work.
    func load(_ stored: PlayDiagram) {
        diagram = stored
        activeNodeId = stored.rootNodeId
        selectedEntityId = nil
        selectedKeyframeIds = []
        playhead = 0
        look.theme = CourtTheme.all.first { $0.name == stored.themeName } ?? .video
    }

    /// Elevation to render at the playhead. While scrubbing, the authored track
    /// wins; the slider follows it.
    var renderElevation: Double {
        diagram.camera.isStatic ? cameraElevation : diagram.cameraAngle(at: playhead)
    }

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
