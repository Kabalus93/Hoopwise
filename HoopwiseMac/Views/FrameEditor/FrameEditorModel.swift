import SwiftUI
import Combine

/// Authoring state for the FRAME editor (Play Editor v2, Phase B).
///
/// It owns a `PlayDiagram` whose reads carry `frames`, and every mutation goes
/// through here so the diagram is written in one place — the same rule the
/// keyframe editor had, kept because it was the thing that worked.
///
/// WHAT IS DELIBERATELY ABSENT, versus the model it replaces: no playhead, no
/// per-entity tracks, no camera, no easing, no work area. The unit of authoring
/// is a FRAME, and the only navigation is which frame you are looking at.
@MainActor
final class FrameEditorModel: ObservableObject {

    @Published var diagram: PlayDiagram
    @Published var diagramName: String = "Untitled Play"
    @Published var activeNodeId: UUID
    /// Which frame of the active read is being authored.
    @Published var frameIndex: Int = 0
    @Published var selectedEntityId: UUID?
    /// The action under edit, if one is selected — deleting or bending acts on
    /// this.
    @Published var selectedActionId: UUID?
    /// Previous frame's end formation, ghosted so continuity is visible.
    @Published var showOnionSkin = true
    /// Armed tool. Nil is select-and-drag, which is how nearly everything is
    /// authored; a screen needs saying because dragging a player already means
    /// "cut".
    @Published var armedTool: FrameTool = .select
    @Published var isDirty = false

    enum FrameTool: Equatable { case select, screen }

    /// Set by the view so edits reach SwiftData.
    weak var dataManager: SwiftDataManager?

    /// NSUndoManager holds targets unowned(unsafe) — the same trap the keyframe
    /// editor documented. Purge whenever the manager is swapped, the diagram is
    /// replaced, or the view goes away.
    weak var undoManager: UndoManager? {
        willSet {
            if newValue !== undoManager { undoManager?.removeAllActions(withTarget: self) }
        }
    }

    func purgeUndoActions() { undoManager?.removeAllActions(withTarget: self) }

    deinit {
        let manager = undoManager
        manager?.removeAllActions(withTarget: self)
    }

    var hasAttached = false
    var persistenceDisabled = false
    private var autosave: AnyCancellable?

    init(diagram: PlayDiagram) {
        self.diagram = diagram
        self.activeNodeId = diagram.rootNodeId
    }

    static func newDiagram() -> PlayDiagram {
        let defaults = UserDefaults.standard
        let standard = CourtStandard(rawValue: defaults.string(forKey: "settings.defaultCourtStandard") ?? "fiba") ?? .fiba
        let mode = CourtMode(rawValue: defaults.string(forKey: "settings.defaultCourtMode") ?? "half") ?? .half
        var fresh = PlayDiagram(playId: UUID(), space: CourtSpace(standard: standard, mode: mode))
        fresh.pace = .default
        // A play always has a first frame: there is nowhere to draw otherwise.
        if let index = fresh.nodes.firstIndex(where: { $0.id == fresh.rootNodeId }) {
            fresh.nodes[index].frames = [PlayFrame()]
        }
        return fresh
    }

    // MARK: - Undo / persistence

    func registerUndo(_ name: String) {
        isDirty = true
        guard let undoManager else { return }
        let snapshot = diagram
        undoManager.registerUndo(withTarget: self) { model in
            model.registerUndo(name)
            model.diagram = snapshot
            model.clampSelection()
        }
        undoManager.setActionName(name)
    }

    func startAutosave() {
        autosave = $diagram
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    func disableAutosave() {
        autosave?.cancel()
        autosave = nil
    }

    func save() {
        guard !persistenceDisabled else { return }
        dataManager?.savePlayDiagram(diagram, name: diagramName)
    }

    func load(_ stored: PlayDiagram, name: String? = nil) {
        diagram = stored
        if let name { diagramName = name }
        activeNodeId = stored.rootNodeId
        frameIndex = 0
        selectedEntityId = nil
        selectedActionId = nil
        // Stale actions would restore the PREVIOUS play's snapshot into this
        // one on Cmd-Z — a correctness bug even when nothing dangles.
        purgeUndoActions()
        isDirty = false
    }

    // MARK: - The active read

    var node: ReadNode? { diagram.node(activeNodeId) }

    /// Formation this read opens on: home positions for the root, or whatever
    /// the parent's branch frame left behind.
    func formationEntering(_ nodeId: UUID, visited: Set<UUID> = []) -> Formation {
        guard nodeId != diagram.rootNodeId, !visited.contains(nodeId) else {
            return diagram.homeFormation
        }
        guard let parent = diagram.nodes.first(where: { node in
            node.edges.contains { $0.targetId == nodeId && $0.kind == .branch }
        }), let edge = parent.edges.first(where: { $0.targetId == nodeId }) else {
            return diagram.homeFormation
        }
        var parentSequence = FrameSequence(
            startFormation: formationEntering(parent.id, visited: visited.union([nodeId])),
            frames: parent.frames, pace: diagram.effectivePace, rim: diagram.rimPoint)
        parentSequence.reresolve()
        let through = edge.afterFrameIndex.map { $0 + 1 } ?? parent.frames.count
        return parentSequence.formation(enteringFrame: max(0, through))
    }

    /// THE sequence being authored.
    var sequence: FrameSequence {
        FrameSequence(startFormation: formationEntering(activeNodeId),
                      frames: node?.frames ?? [],
                      pace: diagram.effectivePace,
                      rim: diagram.rimPoint)
    }

    var frames: [PlayFrame] { node?.frames ?? [] }
    var frameCount: Int { frames.count }

    var currentFrame: PlayFrame? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : nil
    }

    /// Where everyone stands when the current frame OPENS — the pose the canvas
    /// draws and gestures start from.
    var startFormation: Formation {
        sequence.formation(enteringFrame: frameIndex)
    }

    /// The onion skin: where everyone stood when the PREVIOUS frame opened.
    ///
    /// Not the previous frame's END formation — that is identical to this
    /// frame's start, so it ghosted every player exactly underneath himself and
    /// showed nothing. What makes continuity visible is where they came FROM.
    var onionFormation: Formation? {
        guard showOnionSkin, frameIndex > 0 else { return nil }
        return sequence.formation(enteringFrame: frameIndex - 1)
    }

    /// Writes a mutated sequence back into the read. One undo per call.
    private func mutate(_ name: String, _ body: (inout FrameSequence) -> Void) {
        guard let index = diagram.nodes.firstIndex(where: { $0.id == activeNodeId }) else { return }
        registerUndo(name)
        var working = sequence
        body(&working)
        diagram.nodes[index].frames = working.frames
        diagram.updatedAt = Date()
        clampSelection()
    }

    private func clampSelection() {
        frameIndex = min(max(frameIndex, 0), max(0, frameCount - 1))
        if let id = selectedActionId,
           currentFrame?.actions.contains(where: { $0.id == id }) != true {
            selectedActionId = nil
        }
    }

    // MARK: - Frame navigation and CRUD

    func selectFrame(_ index: Int) {
        guard frames.indices.contains(index) else { return }
        frameIndex = index
        selectedActionId = nil
    }

    func nextFrame() { selectFrame(frameIndex + 1) }
    func previousFrame() { selectFrame(frameIndex - 1) }

    /// The strip's `+`. A new frame continues from the end formation and
    /// changes nothing until something is drawn in it.
    func addFrame() {
        mutate("Add Frame") { $0.appendFrame() }
        frameIndex = max(0, frameCount - 1)
        selectedActionId = nil
    }

    /// Inserts an empty frame after `index`, continuing from it.
    func addFrameAfter(_ index: Int) {
        mutate("Add Frame") { $0.insertFrame(at: index + 1) }
        frameIndex = min(index + 1, frameCount - 1)
        selectedActionId = nil
    }

    func duplicateFrame(at index: Int) {
        mutate("Duplicate Frame") { $0.duplicateFrame(at: index) }
        frameIndex = min(index + 1, frameCount - 1)
    }

    func deleteFrame(at index: Int) {
        // A play with no frames has nowhere to draw; the last one empties
        // rather than vanishing.
        if frameCount <= 1 {
            mutate("Clear Frame") {
                $0.frames = [PlayFrame(caption: $0.frames.first?.caption ?? "")]
            }
            frameIndex = 0
            return
        }
        mutate("Delete Frame") { $0.removeFrame(at: index) }
        frameIndex = min(index, frameCount - 1)
    }

    func moveFrame(from source: Int, to destination: Int) {
        mutate("Reorder Frames") { $0.moveFrame(from: source, to: destination) }
        frameIndex = min(max(destination, 0), frameCount - 1)
    }

    func setCaption(_ caption: String, at index: Int) {
        guard frames.indices.contains(index), frames[index].caption != caption else { return }
        mutate("Edit Caption") { $0.setCaption(caption, forFrame: index) }
    }

    // MARK: - Reads (branch at a frame)

    var reads: [ReadNode] { diagram.nodes }

    func selectRead(_ nodeId: UUID) {
        guard diagram.node(nodeId) != nil else { return }
        activeNodeId = nodeId
        frameIndex = 0
        selectedActionId = nil
        selectedEntityId = nil
    }

    /// "After frame N, if X: …" — the v2 read. The child opens on the formation
    /// this frame leaves, so it continues rather than restarting.
    func addRead(after index: Int, condition: String) {
        guard let parentIndex = diagram.nodes.firstIndex(where: { $0.id == activeNodeId })
        else { return }
        registerUndo("Add Read")
        let child = ReadNode(title: condition.isEmpty ? "Read" : condition,
                             frames: [PlayFrame()])
        diagram.nodes.append(child)
        diagram.nodes[parentIndex].edges.append(
            ReadEdge(targetId: child.id, kind: .branch,
                     condition: condition, afterFrameIndex: index))
        diagram.updatedAt = Date()
        activeNodeId = child.id
        frameIndex = 0
    }

    /// The condition that reaches this read, for the strip's header.
    func condition(of nodeId: UUID) -> String? {
        for node in diagram.nodes {
            if let edge = node.edges.first(where: { $0.targetId == nodeId }) {
                return edge.condition
            }
        }
        return nil
    }

    // MARK: - Possession, derived

    /// WHO THE BALL WAS PLACED ON.
    ///
    /// Possession has to start somewhere, and the coach's gesture for saying so
    /// is dropping the ball next to a player. Without this the derivation had a
    /// chicken-and-egg: it infers the opening holder from the first action only
    /// a holder can perform, but the first such action cannot be authored until
    /// something knows who the holder is — so the opening dribble came out a
    /// cut, and the pass and shot silently refused to author at all.
    var openingHolder: UUID? { openingHolder(for: activeNodeId) }

    /// A READ INHERITS THE BALL the way it inherits the formation. The root
    /// takes it from where the ball was placed; a branch takes whoever was
    /// holding it when the parent's branch frame ended — otherwise the child
    /// read starts with nobody holding anything and its pass cannot be drawn,
    /// which is exactly what happened on the first acceptance run.
    func openingHolder(for nodeId: UUID, visited: Set<UUID> = []) -> UUID? {
        guard nodeId != diagram.rootNodeId, !visited.contains(nodeId) else {
            return ballPlacedWith()
        }
        guard let parent = diagram.nodes.first(where: { node in
            node.edges.contains { $0.targetId == nodeId && $0.kind == .branch }
        }), let edge = parent.edges.first(where: { $0.targetId == nodeId }) else {
            return ballPlacedWith()
        }
        var parentSequence = FrameSequence(
            startFormation: formationEntering(parent.id, visited: visited.union([nodeId])),
            frames: parent.frames, pace: diagram.effectivePace, rim: diagram.rimPoint)
        parentSequence.reresolve()
        let through = edge.afterFrameIndex.map { $0 + 1 } ?? parent.frames.count
        let starts = parentSequence.frameStartTimes
        let handover = starts.indices.contains(through)
            ? starts[through] : parentSequence.duration
        let parentOpening = openingHolder(for: parent.id, visited: visited.union([nodeId]))
        return parentSequence.holder(at: handover, startingWith: parentOpening)
    }

    /// Who the ball was PLACED on — the root read's opening holder.
    ///
    /// Possession has to start somewhere, and the coach's gesture for saying so
    /// is dropping the ball next to a player. Without this the derivation had a
    /// chicken-and-egg: it infers the opening holder from the first action only
    /// a holder can perform, but that action cannot be authored until something
    /// knows who the holder is — so the opening dribble came out a cut, and the
    /// pass and shot silently refused to author at all.
    private func ballPlacedWith() -> UUID? {
        guard let ball = diagram.ball else { return nil }
        var best: (UUID, CGFloat)?
        for placement in diagram.homeFormation.placements {
            guard let entity = diagram.entity(placement.entityId), entity.isPlayer else { continue }
            let distance = hypot(ball.homePosition.x - placement.position.x,
                                 ball.homePosition.y - placement.position.y)
            guard distance <= 4 else { continue }
            if best == nil || distance < best!.1 { best = (placement.entityId, distance) }
        }
        return best?.0
    }

    var possessions: [Possession] { sequence.derivedPossessions(startingWith: openingHolder) }

    /// Who holds the ball as the current frame opens.
    var holderAtFrameStart: UUID? {
        let working = sequence
        let opening = openingHolder
        let start = working.frameStartTimes
        guard start.indices.contains(frameIndex) else {
            return working.holder(at: 0, startingWith: opening)
        }
        // A hair inside the frame: at the exact instant a pass leaves, the
        // interval that just ended still contains the boundary.
        return working.holder(at: start[frameIndex] + 0.0001, startingWith: opening)
            ?? working.holder(at: start[frameIndex], startingWith: opening)
    }

    /// Where the ball sits as the frame opens: beside its holder, or at the
    /// rim once a shot has gone up.
    var ballPointAtFrameStart: CGPoint? {
        guard diagram.ball != nil else { return nil }
        if let holder = holderAtFrameStart, let point = startFormation[holder] {
            return CGPoint(x: point.x + FrameEditorModel.ballOffsetFeet, y: point.y)
        }
        // Nobody holds it: after a shot it lives at the rim, before anything is
        // authored it sits where it was placed.
        if possessions.contains(where: { if case .shot? = $0.release { return true }; return false }) {
            return diagram.rimPoint
        }
        return diagram.ball?.homePosition
    }

    static let ballOffsetFeet: CGFloat = 1.9

    // MARK: - Authoring gestures
    //
    // Everything a coach draws lands here, and the KIND IS INFERRED from what
    // was dragged and what it was dropped on — never chosen from a menu. That
    // inference is the whole reason the inspector is not needed to author.

    /// What the gesture layer resolved under the pointer.
    enum Grab: Equatable {
        case entity(UUID)
        case ball
        case action(UUID)
        case none
    }

    func grab(at court: CGPoint) -> Grab {
        if let ball = ballPointAtFrameStart,
           hypot(court.x - ball.x, court.y - ball.y) <= 1.4 {
            return .ball
        }
        if let id = entity(at: court) { return .entity(id) }
        if let action = action(at: court) { return .action(action) }
        return .none
    }

    func entity(at court: CGPoint) -> UUID? {
        var best: (UUID, CGFloat)?
        for placement in startFormation.placements {
            guard let entity = diagram.entity(placement.entityId) else { continue }
            if case .ball = entity.kind { continue }
            let distance = hypot(court.x - placement.position.x,
                                 court.y - placement.position.y)
            guard distance <= 2.2 else { continue }
            if best == nil || distance < best!.1 { best = (placement.entityId, distance) }
        }
        return best?.0
    }

    /// An action whose drawn path passes near a point — in COURT FEET, like
    /// every other hit test in this app.
    func action(at court: CGPoint, toleranceFeet: CGFloat = 1.2) -> UUID? {
        guard let frame = currentFrame else { return nil }
        var best: (UUID, CGFloat)?
        for action in frame.validActions {
            let points = drawnPoints(of: action)
            guard points.count > 1 else { continue }
            var nearest = CGFloat.greatestFiniteMagnitude
            for index in 0..<(points.count - 1) {
                nearest = min(nearest, Self.distance(court, points[index], points[index + 1]))
            }
            guard nearest <= toleranceFeet else { continue }
            if best == nil || nearest < best!.1 { best = (action.id, nearest) }
        }
        return best?.0
    }

    /// The points an action is DRAWN through: its origin plus its path. One
    /// function, so hit testing and rendering cannot disagree about where a
    /// line is.
    func drawnPoints(of action: PlayAction) -> [CGPoint] {
        let origin: CGPoint
        switch action.kind {
        case .pass, .shot:
            origin = ballPointAtFrameStart ?? startFormation[action.actorId] ?? .zero
        default:
            origin = startFormation[action.actorId] ?? .zero
        }
        switch action.kind {
        case .pass, .handoff:
            guard let target = action.target?.playerId,
                  let point = startFormation[target] else { return [origin] }
            return [origin, point]
        case .shot:
            if case .point(let target)? = action.target { return [origin, target] }
            return [origin, diagram.rimPoint]
        default:
            return [origin] + action.path
        }
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }

    /// Dragging a PLAYER. Holding the ball makes it a dribble, the screen tool
    /// makes it a screen, otherwise it is a cut — inferred, never picked.
    /// `asScreen` is the GESTURE's verdict — ⌥ held, or the screen tool armed.
    /// It decides the kind on its own.
    ///
    /// `screenFor` is metadata about a screen, NOT the trigger for one. It used
    /// to be both, and that was the bug: the canvas passed whatever entity was
    /// under the drop point, which is nil whenever the screener is dropped on
    /// open floor — the normal way to set a screen — so ⌥-drag produced a CUT
    /// unless you happened to land on top of a teammate.
    func authorMove(actor: UUID, to court: CGPoint,
                    asScreen: Bool = false, screenFor: UUID? = nil) {
        guard frames.indices.contains(frameIndex) else { return }
        let clamped = diagram.space.clamp(court)
        let kind = PlayActionKind.inferred(
            asScreen: asScreen || armedTool == .screen || screenFor != nil,
            actorHoldsBall: holderAtFrameStart == actor)
        let action = PlayAction(kind: kind, actorId: actor,
                                target: .point(clamped), path: [clamped],
                                screenForId: screenFor)
        mutate(kind.displayName) { sequence in
            // One movement per actor per frame: a second drag RETIMES the same
            // action rather than stacking two, which is what a coach means by
            // dragging him somewhere else.
            sequence.frames[frameIndex].actions.removeAll {
                $0.actorId == actor && $0.movesActor
            }
            sequence.frames[frameIndex].actions.append(action)
            sequence.reresolve()
        }
        selectedActionId = action.id
        selectedEntityId = actor
    }

    /// Who a screen is set FOR: the teammate the screener ended up next to.
    ///
    /// A coach drops the screener on the SPOT, not on the man, so this looks
    /// for the nearest teammate within a body's width or two rather than
    /// requiring a direct hit. Nil is fine — an unattributed screen still
    /// renders as a screen.
    func screenTarget(near court: CGPoint, excluding actor: UUID,
                      withinFeet: CGFloat = 7) -> UUID? {
        var best: (UUID, CGFloat)?
        for placement in startFormation.placements where placement.entityId != actor {
            guard let entity = diagram.entity(placement.entityId), entity.isPlayer else { continue }
            let distance = hypot(court.x - placement.position.x,
                                 court.y - placement.position.y)
            guard distance <= withinFeet else { continue }
            if best == nil || distance < best!.1 { best = (placement.entityId, distance) }
        }
        return best?.0
    }

    /// Dragging the BALL onto a player is a pass; onto the rim, a shot.
    func authorBallDrop(at court: CGPoint) {
        guard let holder = holderAtFrameStart else { return }
        let rim = diagram.rimPoint
        if hypot(court.x - rim.x, court.y - rim.y) <= RenderStyle.edit.rimSnapFeet + 1.5 {
            authorBallAction(PlayAction(kind: .shot, actorId: holder, target: .point(rim)))
            return
        }
        guard let receiver = entity(at: court), receiver != holder,
              diagram.entity(receiver)?.isPlayer == true else { return }
        authorBallAction(PlayAction(kind: .pass, actorId: holder, target: .player(receiver)))
    }

    private func authorBallAction(_ action: PlayAction) {
        guard frames.indices.contains(frameIndex) else { return }
        mutate(action.kind.displayName) { sequence in
            // One ball event per frame: the ball cannot be thrown twice in one
            // moment, and the derivation only honours the first anyway.
            sequence.frames[frameIndex].actions.removeAll { $0.kind.releasesPossession }
            sequence.frames[frameIndex].actions.append(action)
            sequence.reresolve()
        }
        selectedActionId = action.id
    }

    /// Drag-to-bend, carried over from the keyframe editor: grabbing a drawn
    /// path and pulling it inserts or moves ONE control point, so a straight
    /// cut becomes a curl without re-drawing it.
    func bend(actionId: UUID, to court: CGPoint, insertIfNeeded: Bool) {
        guard frames.indices.contains(frameIndex) else { return }
        let clamped = diagram.space.clamp(court)
        mutate("Bend Path") { sequence in
            guard let index = sequence.frames[frameIndex].actions
                .firstIndex(where: { $0.id == actionId }) else { return }
            var action = sequence.frames[frameIndex].actions[index]
            guard action.movesActor else { return }
            if action.path.count >= 2 {
                action.path[action.path.count - 2] = clamped
            } else if insertIfNeeded {
                action.path.insert(clamped, at: max(0, action.path.count - 1))
            }
            sequence.frames[frameIndex].actions[index] = action
            sequence.reresolve()
        }
    }

    // MARK: - HUD
    //
    // The context panel appears AT the selection, so what you can do to a thing
    // is next to the thing. It is also how gestures announce themselves: an
    // entity's HUD names the drags available on it, which is what stopped the
    // screen tool from having to be found in a palette.

    /// View-space point the HUD hangs off, published by the canvas.
    @Published var hudAnchor: CGPoint?

    /// What the HUD is about.
    enum HUDSubject: Equatable {
        case action(UUID)
        case entity(UUID)
    }

    var hudSubject: HUDSubject? {
        if let id = selectedActionId { return .action(id) }
        if let id = selectedEntityId { return .entity(id) }
        return nil
    }

    var selectedAction: PlayAction? {
        guard let id = selectedActionId else { return nil }
        return currentFrame?.actions.first { $0.id == id }
    }

    /// How long the selected action takes — derived, and worth showing because
    /// nothing in this model lets you type it.
    func duration(of action: PlayAction) -> Double {
        currentFrame?.duration(of: action, from: startFormation,
                               pace: diagram.effectivePace, rim: diagram.rimPoint) ?? 0
    }

    /// Changes how fast a movement is run. The only timing control there is,
    /// and it belongs on the action rather than in a panel.
    func setPace(_ tier: PaceTier?, for actionId: UUID) {
        guard frames.indices.contains(frameIndex) else { return }
        mutate("Change Pace") { sequence in
            guard let index = sequence.frames[frameIndex].actions
                .firstIndex(where: { $0.id == actionId }) else { return }
            sequence.frames[frameIndex].actions[index].pace = tier
        }
    }

    /// A misdrop must not require redoing the gesture — the same rule the
    /// keyframe editor's convert had, now on the HUD at the arc itself.
    func convertSelectedFlight() {
        guard let action = selectedAction, frames.indices.contains(frameIndex) else { return }
        switch action.kind {
        case .shot:
            // To a pass: the nearest other player to where the ball ended up.
            guard let holder = holderAtFrameStart else { return }
            let others = diagram.entities.filter { $0.isPlayer && $0.id != holder }
            guard let receiver = others.min(by: { a, b in
                let pa = startFormation[a.id] ?? .zero, pb = startFormation[b.id] ?? .zero
                let rim = diagram.rimPoint
                return hypot(pa.x - rim.x, pa.y - rim.y) < hypot(pb.x - rim.x, pb.y - rim.y)
            }) else { return }
            replaceSelectedFlight(with: PlayAction(kind: .pass, actorId: action.actorId,
                                                   target: .player(receiver.id)))
        case .pass:
            replaceSelectedFlight(with: PlayAction(kind: .shot, actorId: action.actorId,
                                                   target: .point(diagram.rimPoint)))
        default:
            break
        }
    }

    private func replaceSelectedFlight(with action: PlayAction) {
        mutate(action.kind.displayName) { sequence in
            sequence.frames[frameIndex].actions.removeAll { $0.kind.releasesPossession }
            sequence.frames[frameIndex].actions.append(action)
            sequence.reresolve()
        }
        selectedActionId = action.id
    }

    /// The gestures available on a thing, in words. THIS IS THE DISCOVERABILITY
    /// FIX: ⌥-drag and the screen tool used to exist only in a palette you had
    /// to go looking in.
    func gestureHints(for subject: HUDSubject) -> [String] {
        switch subject {
        case .entity(let id):
            guard let entity = diagram.entity(id) else { return [] }
            guard entity.isPlayer else { return ["Drag to move"] }
            var hints = [holderAtFrameStart == id ? "Drag to dribble" : "Drag to cut",
                         "⌥-drag to screen"]
            if holderAtFrameStart == id { hints.append("Drag the ball to pass or shoot") }
            return hints
        case .action:
            return ["Drag the line to bend it", "⌫ to delete"]
        }
    }

    func deleteSelectedAction() {
        guard let id = selectedActionId, frames.indices.contains(frameIndex) else { return }
        mutate("Delete Action") { sequence in
            sequence.frames[frameIndex].actions.removeAll { $0.id == id }
            sequence.reresolve()
        }
        selectedActionId = nil
    }

    /// Places an entity. Only needed to set a play up; v2 authoring is
    /// otherwise about actions.
    func addEntity(kind: DiagramEntityKind, at court: CGPoint, label: String?) {
        if case .ball = kind, !diagram.canAddBall { return }
        registerUndo("Place Player")
        let entity = DiagramEntity(kind: kind, label: label,
                                   homePosition: diagram.space.clamp(court))
        diagram.entities.append(entity)
        diagram.updatedAt = Date()
        selectedEntityId = entity.id
    }

    func label(of entityId: UUID) -> String {
        guard let entity = diagram.entity(entityId) else { return "?" }
        if case .player(let team, _, _) = entity.kind {
            return "\(team == .offense ? "O" : "D")\(entity.label ?? "")"
        }
        if case .ball = entity.kind { return "Ball" }
        return entity.label ?? "—"
    }

    /// One line of what this frame does, for the strip and for evidence.
    func summary(of frame: PlayFrame) -> String {
        let parts = frame.validActions.map { action -> String in
            switch action.kind {
            case .pass:
                return "\(label(of: action.actorId)) passes to \(action.target?.playerId.map(label) ?? "?")"
            case .shot:    return "\(label(of: action.actorId)) shoots"
            case .screen:  return "\(label(of: action.actorId)) screens"
            case .dribble: return "\(label(of: action.actorId)) dribbles"
            case .handoff: return "\(label(of: action.actorId)) hands off"
            case .cut:     return "\(label(of: action.actorId)) cuts"
            }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }
}
