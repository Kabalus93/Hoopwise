#if DEBUG
import Foundation
import CoreGraphics
import os

/// Phase B acceptance driver: re-authors TRIANGLE OFFENSE in v2 through exactly
/// the model calls the gestures make.
///
/// Every line below is one interaction a coach performs — `authorMove` is what
/// a drag on a player calls, `authorBallDrop` is what dropping the ball calls,
/// `addFrame` is the strip's `+`, `setCaption` is typing in the caption field.
/// Nothing here reaches past the authoring surface: there is no inspector call,
/// and no action's kind is set by hand — every one is INFERRED from what was
/// dragged onto what, which is the property the acceptance is really about.
///
///   HOOPWISE_FRAME_DEMO=triangle    author the play
///   HOOPWISE_FRAME_DEMO_FRAME=<n>   park on a frame (1-based) for a screenshot
///   HOOPWISE_FRAME_DEMO_READ=1      switch to the branched read
@MainActor
enum FrameDemoScenario {

    private static let logger = Logger(subsystem: "hoopwise.demo", category: "frames")
    private static var interactions = 0

    static func applyIfRequested(to model: FrameEditorModel) {
        let env = ProcessInfo.processInfo.environment
        guard env["HOOPWISE_FRAME_DEMO"] == "triangle" else { return }
        model.persistenceDisabled = true
        model.disableAutosave()
        interactions = 0

        author(model)

        if env["HOOPWISE_FRAME_DEMO_READ"] == "1",
           let branch = model.reads.first(where: { $0.id != model.diagram.rootNodeId }) {
            model.selectRead(branch.id)
        }
        if let raw = env["HOOPWISE_FRAME_DEMO_FRAME"], let number = Int(raw) {
            model.selectFrame(number - 1)
        }
        report(model)
    }

    /// One interaction, named for the log.
    private static func act(_ what: String, _ body: () -> Void) {
        body()
        interactions += 1
        logger.notice("ACT \(interactions, privacy: .public): \(what, privacy: .public)")
    }

    private static func author(_ model: FrameEditorModel) {
        model.load(FrameEditorModel.newDiagram(), name: "Triangle Offense")
        model.persistenceDisabled = true

        // ---- Setup: place the lineup and the ball (5 taps + 1) ----
        let spots: [CGPoint] = [CGPoint(x: 25, y: 30),   // O1 top
                                CGPoint(x: 43, y: 24),   // O2 right wing
                                CGPoint(x: 6, y: 22),    // O3 left corner
                                CGPoint(x: 34, y: 12),   // O4 right block
                                CGPoint(x: 10, y: 11)]   // O5 left block
        for (index, spot) in spots.enumerated() {
            act("place O\(index + 1)") {
                model.addEntity(kind: .player(team: .offense, number: nil, role: nil),
                                at: spot, label: "\(index + 1)")
            }
        }
        act("place ball") {
            model.addEntity(kind: .ball, at: CGPoint(x: 27, y: 30), label: nil)
        }
        guard let o1 = id(model, "1"), let o2 = id(model, "2"),
              let o3 = id(model, "3"), let o5 = id(model, "5") else { return }

        // ---- Frame 1: O1 enters right ----
        act("caption frame 1") { model.setCaption("O1 enters right", at: 0) }
        act("drag O1 to the wing → dribble") {
            model.authorMove(actor: o1, to: CGPoint(x: 33, y: 27))
        }

        // ---- Frame 2: down screen ----
        act("add frame 2") { model.addFrame() }
        act("caption frame 2") { model.setCaption("O5 down screens for O2", at: 1) }
        act("⌥-drag O5 to the elbow → screen for O2") {
            model.authorMove(actor: o5, to: CGPoint(x: 19, y: 19), screenFor: o2)
        }
        act("drag O2 to the top → cut") {
            model.authorMove(actor: o2, to: CGPoint(x: 30, y: 17))
        }

        // ---- Frame 3: the pass ----
        act("add frame 3") { model.addFrame() }
        act("caption frame 3") { model.setCaption("Swing to the curl", at: 2) }
        act("drag the ball onto O2 → pass") {
            model.authorBallDrop(at: model.startFormation[o2] ?? .zero)
        }

        // ---- Frame 4: the shot ----
        act("add frame 4") { model.addFrame() }
        act("caption frame 4") { model.setCaption("Catch and shoot", at: 3) }
        act("drag the ball onto the rim → shot") {
            model.authorBallDrop(at: model.diagram.rimPoint)
        }

        // ---- The read: a real branch, which is why this play is the test ----
        act("branch after frame 2") {
            model.selectFrame(1)
            model.addRead(after: 1, condition: "they switch the screen")
        }
        act("caption the read's frame 1") { model.setCaption("O3 lifts, O1 skips it", at: 0) }
        act("drag O3 up → cut") {
            model.authorMove(actor: o3, to: CGPoint(x: 8, y: 27))
        }
        act("drag the ball onto O3 → pass") {
            model.authorBallDrop(at: model.startFormation[o3] ?? .zero)
        }

        // Back to the base read, frame 1, for a deterministic starting state.
        model.selectRead(model.diagram.rootNodeId)
        model.selectFrame(0)
    }

    private static func id(_ model: FrameEditorModel, _ label: String) -> UUID? {
        model.diagram.entities.first { $0.label == label && $0.isPlayer }?.id
    }

    /// What the run produced, as text an outside agent can read.
    private static func report(_ model: FrameEditorModel) {
        logger.notice("FRAMEDEMO interactions=\(interactions, privacy: .public)")
        for read in model.reads {
            let sequence = FrameSequence(startFormation: model.formationEntering(read.id),
                                         frames: read.frames,
                                         pace: model.diagram.effectivePace,
                                         rim: model.diagram.rimPoint)
            let opening = model.openingHolder(for: read.id)
            let title = read.id == model.diagram.rootNodeId
                ? read.title : (model.condition(of: read.id) ?? read.title)
            logger.notice("READ \(title, privacy: .public) frames=\(read.frames.count, privacy: .public) duration=\(String(format: "%.2f", sequence.duration), privacy: .public)")
            for (index, frame) in read.frames.enumerated() {
                let kinds = frame.validActions.map(\.kind.rawValue).joined(separator: "+")
                logger.notice("  F\(index + 1, privacy: .public) [\(kinds, privacy: .public)] \(frame.caption, privacy: .public) — \(model.summary(of: frame), privacy: .public)")
            }
            let possessions = sequence.derivedPossessions(startingWith: opening).map { possession -> String in
                let release: String
                switch possession.release {
                case .pass(let to): release = "→pass \(model.label(of: to))"
                case .shot:         release = "→shot"
                case nil:           release = ""
                }
                return String(format: "%@ %.2f-%@%@", model.label(of: possession.holderId),
                              possession.start,
                              possession.end.map { String(format: "%.2f", $0) } ?? "end",
                              release)
            }
            logger.notice("  BALL \(possessions.joined(separator: " | "), privacy: .public)")
        }
    }
}
#endif
