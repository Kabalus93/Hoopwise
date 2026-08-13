import Foundation
import CoreGraphics

// MARK: - Frame sequence
//
// An ordered run of frames plus the formation it starts from — everything
// needed to answer "where is everyone at t" and "who has the ball at t"
// without a single stored timestamp.
//
// This is where Phase A's four deliverables live: frame CRUD, action→timing
// derivation, possession derivation, and branch-at-frame. It is a pure value
// type: no store, no view model, no I/O, so all of it is testable directly.

struct FrameSequence: Codable, Hashable {

    /// Where the play begins — entity home positions, or the formation a
    /// parent read left behind at the branch point.
    var startFormation: Formation
    var frames: [PlayFrame]
    var pace: PlayPace
    /// The rim, in court feet: a shot's default target.
    var rim: CGPoint

    init(startFormation: Formation = Formation(),
         frames: [PlayFrame] = [],
         pace: PlayPace = .default,
         rim: CGPoint = .zero) {
        self.startFormation = startFormation
        self.frames = frames
        self.pace = pace
        self.rim = rim
    }

    // MARK: - Formations

    /// Formation entering frame `index`. Frame 0 opens on the start formation;
    /// every later frame opens where the previous one closed.
    ///
    /// Reads the STORED end formation, which is what makes this cheap — see
    /// `PlayFrame.endFormation` for why that copy is allowed to exist and
    /// `driftedFrames` for the guard that keeps it honest.
    func formation(enteringFrame index: Int) -> Formation {
        guard index > 0 else { return startFormation }
        guard index <= frames.count else { return endFormation }
        return frames[index - 1].endFormation
    }

    var endFormation: Formation {
        frames.last?.endFormation ?? startFormation
    }

    /// Frames whose stored end formation disagrees with what their actions
    /// actually produce. ALWAYS EMPTY in a well-formed sequence — every
    /// mutation re-resolves — and the tests assert exactly that. This is the
    /// price of storing a derived value, paid openly.
    ///
    /// Drift CASCADES, deliberately: a corrupt frame makes every frame after it
    /// wrong too, because each one's expectation is built on its predecessor's
    /// stored formation. The report says "from here on this play is lying",
    /// which is the truth; reporting only the first would understate it.
    func driftedFrames(tolerance: CGFloat = 0.001) -> [Int] {
        var drifted: [Int] = []
        var running = startFormation
        for (index, frame) in frames.enumerated() {
            let expected = frame.resolvedEndFormation(from: running)
            for placement in expected.placements {
                let stored = frame.endFormation[placement.entityId]
                if stored == nil ||
                    hypot(stored!.x - placement.position.x,
                          stored!.y - placement.position.y) > tolerance {
                    drifted.append(index)
                    break
                }
            }
            running = frame.endFormation
        }
        return drifted
    }

    /// Recomputes every stored end formation from the start. Called after any
    /// mutation; idempotent.
    mutating func reresolve() {
        var running = startFormation
        for index in frames.indices {
            frames[index].endFormation = frames[index].resolvedEndFormation(from: running)
            running = frames[index].endFormation
        }
    }

    // MARK: - Timing

    /// Each frame's duration, in order.
    var frameDurations: [Double] {
        var running = startFormation
        var result: [Double] = []
        for frame in frames {
            result.append(frame.duration(from: running, pace: pace, rim: rim))
            running = frame.endFormation
        }
        return result
    }

    /// Absolute start time of each frame — the running sum. Frames play
    /// SEQUENTIALLY, so this is the only place time exists at all, and it is
    /// computed, never stored.
    var frameStartTimes: [Double] {
        var running: Double = 0
        var result: [Double] = []
        for duration in frameDurations {
            result.append(running)
            running += duration
        }
        return result
    }

    var duration: Double { frameDurations.reduce(0, +) }

    /// Index of the frame containing `time`, clamped into range. Ties resolve
    /// FORWARD — at a boundary the arriving frame owns the instant, the same
    /// convention the read boundary uses.
    func frameIndex(at time: Double) -> Int {
        guard !frames.isEmpty else { return 0 }
        let starts = frameStartTimes
        let durations = frameDurations
        guard time >= 0 else { return 0 }
        for index in frames.indices.reversed() where time >= starts[index] {
            return index
        }
        _ = durations
        return 0
    }

    /// Seconds into the frame that contains `time`.
    func localTime(at time: Double) -> Double {
        let index = frameIndex(at: time)
        let starts = frameStartTimes
        guard index < starts.count else { return 0 }
        return max(0, time - starts[index])
    }

    // MARK: - Resolution

    /// Where an entity is at absolute `time`.
    ///
    /// Before the play it stands in the start formation; after it, where the
    /// last frame left it. In between it is either running one action or
    /// holding — CONTINUITY IS THE DEFAULT, which is the whole point of frames.
    func position(of entityId: UUID, at time: Double) -> CGPoint {
        guard !frames.isEmpty else { return startFormation[entityId] ?? .zero }
        if time <= 0 { return startFormation[entityId] ?? .zero }
        if time >= duration { return endFormation[entityId] ?? startFormation[entityId] ?? .zero }
        let index = frameIndex(at: time)
        let local = localTime(at: time)
        return frames[index].position(of: entityId,
                                      atProgressSeconds: local,
                                      from: formation(enteringFrame: index),
                                      pace: pace, rim: rim)
    }

    // MARK: - Possession
    //
    // Derived FROM ACTIONS into the EXISTING possession model. The model stays
    // the truth: `ballState`, `BallFlight`, the flight arc and everything else
    // downstream consume `[Possession]` exactly as they do today, so the
    // constraints in docs/BALL_LANE_SPEC.md §1/§2 hold by construction rather
    // than by a second implementation agreeing with the first.

    /// Who holds the ball when the play opens: stated, or inferred from the
    /// first action that can only be performed by a holder.
    func openingHolder(explicit: UUID? = nil) -> UUID? {
        if let explicit { return explicit }
        for frame in frames {
            for action in frame.validActions
            where action.kind == .pass || action.kind == .shot
                || action.kind == .dribble || action.kind == .handoff {
                return action.actorId
            }
        }
        return nil
    }

    /// The possession intervals this sequence's actions describe.
    ///
    /// Rules, and they are the whole derivation:
    ///   · a PASS releases at its frame's start and the receiver attaches when
    ///     the ball arrives — flight duration priced from distance ÷ pass pace,
    ///     the same arithmetic the renderer uses;
    ///   · a HANDOFF releases at its frame's start and lands at the end of the
    ///     action, because the ball is carried, not thrown;
    ///   · a SHOT releases and ENDS possession — nothing receives it;
    ///   · a DRIBBLE changes nothing: the holder keeps it and moves.
    func derivedPossessions(startingWith explicitHolder: UUID? = nil) -> [Possession] {
        guard let opening = openingHolder(explicit: explicitHolder) else { return [] }
        var result: [Possession] = [Possession(holderId: opening, start: 0)]
        let starts = frameStartTimes
        var running = startFormation

        for (index, frame) in frames.enumerated() {
            let frameStart = starts[index]
            defer { running = frame.endFormation }
            // At most one ball event per frame: the ball cannot be thrown twice
            // at once, and a frame is one moment.
            guard let event = frame.validActions.first(where: { $0.kind.releasesPossession })
            else { continue }
            // Only the current holder can give the ball away. An action that
            // says otherwise is authoring noise and is ignored rather than
            // silently teleporting possession.
            guard var last = result.last, last.holderId == event.actorId, last.end == nil
            else { continue }

            let flight = frame.duration(of: event, from: running, pace: pace, rim: rim)
            last.end = frameStart
            switch event.kind {
            case .pass:
                guard let receiver = event.target?.playerId else { continue }
                last.release = .pass(toId: receiver)
                result[result.count - 1] = last
                result.append(Possession(holderId: receiver, start: frameStart + flight))
            case .handoff:
                guard let receiver = event.target?.playerId else { continue }
                // A handoff is a pass the ball never leaves a hand during, so
                // it lands when the carrying action finishes.
                last.release = .pass(toId: receiver)
                result[result.count - 1] = last
                result.append(Possession(holderId: receiver, start: frameStart + flight))
            case .shot:
                let target: CGPoint
                if case .point(let point) = event.target { target = point } else { target = rim }
                last.release = .shot(target: target)
                result[result.count - 1] = last
            default:
                continue
            }
        }
        return result
    }

    /// Who holds the ball at `time`, or nil while it is in flight or dead.
    func holder(at time: Double, startingWith explicitHolder: UUID? = nil) -> UUID? {
        derivedPossessions(startingWith: explicitHolder)
            .last { $0.contains(time) }?.holderId
    }

    // MARK: - Frame CRUD
    //
    // Every mutation re-resolves the stored end formations, so no caller can
    // leave the sequence drifted.

    /// Appends a frame that CONTINUES FROM THE END FORMATION — the `+` in the
    /// frame strip. A new frame changes nothing until something is drawn in it.
    @discardableResult
    mutating func appendFrame(caption: String = "") -> PlayFrame {
        let frame = PlayFrame(endFormation: endFormation, caption: caption)
        frames.append(frame)
        reresolve()
        return frame
    }

    @discardableResult
    mutating func insertFrame(at index: Int, caption: String = "") -> PlayFrame {
        let clamped = min(max(index, 0), frames.count)
        let frame = PlayFrame(endFormation: formation(enteringFrame: clamped), caption: caption)
        frames.insert(frame, at: clamped)
        reresolve()
        return frame
    }

    /// Duplicates a frame in place, actions and caption included. The copy gets
    /// fresh ids so the two are independently editable.
    @discardableResult
    mutating func duplicateFrame(at index: Int) -> PlayFrame? {
        guard frames.indices.contains(index) else { return nil }
        let source = frames[index]
        let copy = PlayFrame(actions: source.actions.map {
            PlayAction(kind: $0.kind, actorId: $0.actorId, target: $0.target,
                       path: $0.path, pace: $0.pace, screenForId: $0.screenForId)
        }, caption: source.caption)
        frames.insert(copy, at: index + 1)
        reresolve()
        return frames[index + 1]
    }

    mutating func removeFrame(at index: Int) {
        guard frames.indices.contains(index) else { return }
        frames.remove(at: index)
        reresolve()
    }

    /// Reorders a frame. Positions after it change, because a frame's meaning
    /// is where it sits in the sequence — that is the model working, not a bug.
    mutating func moveFrame(from source: Int, to destination: Int) {
        guard frames.indices.contains(source) else { return }
        let clamped = min(max(destination, 0), frames.count - 1)
        guard clamped != source else { return }
        let frame = frames.remove(at: source)
        frames.insert(frame, at: clamped)
        reresolve()
    }

    mutating func addAction(_ action: PlayAction, toFrame index: Int) {
        guard frames.indices.contains(index) else { return }
        frames[index].actions.append(action)
        reresolve()
    }

    mutating func removeAction(id: UUID, fromFrame index: Int) {
        guard frames.indices.contains(index) else { return }
        frames[index].actions.removeAll { $0.id == id }
        reresolve()
    }

    mutating func setCaption(_ caption: String, forFrame index: Int) {
        guard frames.indices.contains(index) else { return }
        frames[index].caption = caption
    }
}

// MARK: - Branch at a frame

/// The v2 read tree: the SHAPE carries over, the time-offsets die.
///
/// A read used to depart at `branchTime` seconds into its parent. It now
/// departs AFTER FRAME N — "after frame 2, if the defender goes under…" — which
/// is the way a coach describes it, and which no longer needs the branch point
/// and the parent's timing to agree.
struct FrameBranchPoint: Codable, Hashable {
    /// Index of the LAST parent frame the branch plays before diverging.
    var afterFrameIndex: Int
    /// The defensive read that selects it.
    var condition: String?

    init(afterFrameIndex: Int, condition: String? = nil) {
        self.afterFrameIndex = afterFrameIndex
        self.condition = condition
    }
}

/// One frame in a resolved root-to-leaf run, with where it came from.
struct ResolvedFrame: Identifiable, Hashable {
    var id: UUID { frame.id }
    var frame: PlayFrame
    /// Which read it belongs to.
    var nodeId: UUID
    /// Its index within that read.
    var indexInNode: Int
    /// Absolute start time along the branch, derived from every duration
    /// before it.
    var startsAt: Double
    var duration: Double
}

/// One complete way the play unfolds, as a flat run of frames.
///
/// This is v2's `PlayDiagram.Branch`: same job, no time arithmetic to keep in
/// step. A branch is just the parent's frames up to the branch point followed
/// by the child's, and its timing is the sum of what it contains.
struct FrameBranch {
    var steps: [ResolvedFrame]
    var conditions: [String]

    var duration: Double {
        guard let last = steps.last else { return 0 }
        return last.startsAt + last.duration
    }

    func frameIndex(at time: Double) -> Int? {
        guard !steps.isEmpty else { return nil }
        if time <= 0 { return 0 }
        for index in steps.indices.reversed() where time >= steps[index].startsAt {
            return index
        }
        return 0
    }
}

// MARK: - Diagram integration

extension PlayDiagram {

    /// The pace to price this play's actions at.
    var effectivePace: PlayPace { pace ?? .default }

    /// The rim, in court feet — a shot's default target.
    var rimPoint: CGPoint { space.metrics.nearBasket }

    /// Where everyone stands before the first frame.
    var homeFormation: Formation {
        Formation(placements: entities.map {
            Formation.Placement(entityId: $0.id, position: $0.homePosition)
        })
    }

    /// One read's frames as a sequence, opening on `formation`.
    func frameSequence(for nodeId: UUID, startingFrom formation: Formation) -> FrameSequence {
        FrameSequence(startFormation: formation,
                      frames: node(nodeId)?.frames ?? [],
                      pace: effectivePace,
                      rim: rimPoint)
    }

    /// The root read as a sequence, opening on the entities' home positions.
    var rootFrameSequence: FrameSequence {
        frameSequence(for: rootNodeId, startingFrom: homeFormation)
    }

    /// Every root-to-leaf run, flattened into frames.
    ///
    /// This is v2's `branches()`, and it is markedly simpler: a run is the
    /// parent's frames up to its branch point followed by the child's, and the
    /// timing is the sum of what it contains. There is no `branchTime` to keep
    /// in step with anything, which is the whole reason the time-offsets die —
    /// the branch point is an INDEX, and an index cannot disagree with a
    /// duration it does not know about.
    func frameBranches(limit: Int = PlayDiagram.defaultBranchLimit) -> [FrameBranch] {
        guard let root = rootNode else { return [] }
        var result: [FrameBranch] = []

        func walk(_ node: ReadNode,
                  prefix: [ResolvedFrame],
                  conditions: [String],
                  startFormation: Formation,
                  clock: Double,
                  visited: Set<UUID>) {
            guard result.count < limit, !visited.contains(node.id) else { return }
            // RE-RESOLVED against the formation this branch actually arrives
            // with. A read's stored end formations are a cache valid inside its
            // OWN sequence only: the same child reached from two different
            // parents inherits two different formations, so a branch that
            // trusted the stored copy would place the second one's players
            // wherever the first one left them (or, for a hand-built read, at
            // the origin).
            var sequence = FrameSequence(startFormation: startFormation,
                                         frames: node.frames,
                                         pace: effectivePace,
                                         rim: rimPoint)
            sequence.reresolve()
            let durations = sequence.frameDurations

            /// The first `count` frames of this read, timed from `clock`.
            func take(_ count: Int) -> (steps: [ResolvedFrame], clock: Double, formation: Formation) {
                var steps: [ResolvedFrame] = []
                var running = clock
                for index in 0..<min(count, sequence.frames.count) {
                    steps.append(ResolvedFrame(frame: sequence.frames[index],
                                               nodeId: node.id,
                                               indexInNode: index,
                                               startsAt: running,
                                               duration: durations[index]))
                    running += durations[index]
                }
                return (steps, running, sequence.formation(enteringFrame: min(count, node.frames.count)))
            }

            let branchEdges = node.edges.filter { $0.kind == .branch }
            guard !branchEdges.isEmpty else {
                let taken = take(node.frames.count)
                result.append(FrameBranch(steps: prefix + taken.steps, conditions: conditions))
                return
            }

            let seen = visited.union([node.id])
            for edge in branchEdges {
                guard let child = self.node(edge.targetId) else { continue }
                // "After frame N" — so the parent plays 0...N inclusive. An
                // edge with no index yet plays the parent whole, which is what
                // a branch appended to the end of a read means.
                let through = edge.afterFrameIndex.map { $0 + 1 } ?? node.frames.count
                let taken = take(max(0, through))
                walk(child,
                     prefix: prefix + taken.steps,
                     conditions: conditions + [edge.condition ?? ""],
                     startFormation: taken.formation,
                     clock: taken.clock,
                     visited: seen)
            }
        }

        walk(root, prefix: [], conditions: [],
             startFormation: homeFormation, clock: 0, visited: [])
        return result
    }
}
