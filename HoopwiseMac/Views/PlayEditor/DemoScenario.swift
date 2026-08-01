#if DEBUG
import Foundation
import CoreGraphics
import os

/// Launch-time scenario driver for agent verification runs.
///
/// The Mac has no Accessibility grant for synthetic input, so an agent cannot
/// click. This drives the REAL editor — the same model calls the gestures
/// make, the same canvas, the same renderer — gated behind DEBUG and an env
/// var so it cannot ship or fire in normal use. Screenshots are taken from
/// outside with `screencapture`.
///
/// Environment:
///   HOOPWISE_DEMO_SCENARIO=branched   author a Base → "down screen" play
///   HOOPWISE_DEMO_PLAYHEAD=<seconds>  park the playhead (absolute time)
///   HOOPWISE_DEMO_PRESENTATION=1      switch to presentation style
///   HOOPWISE_DEMO_PLAY=1              start playback (auto-present applies)
///   HOOPWISE_DEMO_BEND=1              run the bend sequence: baseline → bend
///                                     at 4s → undo at 8s, printing keyframe
///                                     dumps at each phase
///   HOOPWISE_DEMO_EXPORT=<path.png>   write a renderFrame PNG at the playhead
@MainActor
enum DemoScenario {

    static func applyIfRequested(to model: PlayEditorModel) {
        let env = ProcessInfo.processInfo.environment
        guard env["HOOPWISE_DEMO_SCENARIO"] != nil else { return }
        // Scratch content only: never into the coach's library or CloudKit.
        model.persistenceDisabled = true
        model.disableAutosave()

        buildBranchedPlay(model)

        if let raw = env["HOOPWISE_DEMO_PLAYHEAD"], let t = Double(raw) {
            model.playhead = t
        }
        if env["HOOPWISE_DEMO_PRESENTATION"] == "1" {
            model.isPresentation = true
        }
        if env["HOOPWISE_DEMO_PLAY"] == "1" {
            model.playhead = 0
            model.play()
        }
        if env["HOOPWISE_DEMO_BEND"] == "1" {
            runBendSequence(model)
        }
        // Synchronous variants, immune to screenshot timing races.
        if env["HOOPWISE_DEMO_BEND_NOW"] == "1" {
            applyBend(model)
        }
        if env["HOOPWISE_DEMO_BEND_UNDO"] == "1" {
            applyBend(model)
            model.undoManager?.undo()
            if let p1 = model.diagram.entities.first(where: { $0.label == "1" })?.id {
                dumpTrack(model, p1, phase: "undone-sync")
            }
        }
        if let path = env["HOOPWISE_DEMO_EXPORT"] {
            exportFrame(model, to: path)
        }
    }

    /// Base with a three-direction-change cut and a second player, branching
    /// into a "down screen" child read at t=3 with its own movement.
    private static func buildBranchedPlay(_ model: PlayEditorModel) {
        model.load(PlayEditorModel.newDiagram(), name: "Agent Demo")
        model.persistenceDisabled = true

        // Two offense players; placement authors the t=0 keyframe exactly as
        // the canvas tap does.
        model.addEntity(kind: .player(team: .offense, number: nil, role: nil),
                        at: CGPoint(x: 10, y: 40), label: "1")
        guard let p1 = model.selectedEntityId else { return }
        model.addEntity(kind: .player(team: .offense, number: nil, role: nil),
                        at: CGPoint(x: 40, y: 40), label: "2")
        guard let p2 = model.selectedEntityId else { return }

        // P1: three direction changes in the base read.
        model.setKeyframe(for: p1, at: 1.0, position: CGPoint(x: 20, y: 33))
        model.setKeyframe(for: p1, at: 2.0, position: CGPoint(x: 14, y: 24))
        model.setKeyframe(for: p1, at: 3.0, position: CGPoint(x: 30, y: 18))
        // P2: one cut.
        model.setKeyframe(for: p2, at: 3.0, position: CGPoint(x: 34, y: 26))

        // Child read branching at t=3 — the boundary under test.
        guard let root = model.diagram.rootNode?.id,
              let child = model.addBranch(from: root, at: 3.0,
                                          condition: "down screen") else { return }
        model.selectNode(child)
        // Child movement so the child window has its own paths.
        model.setKeyframe(for: p1, at: 1.2, position: CGPoint(x: 12, y: 10))
        model.setKeyframe(for: p2, at: 1.5, position: CGPoint(x: 42, y: 16))
        // Back to the top for a deterministic starting state.
        model.selectNode(root)
        model.playhead = 0
        model.selectedEntityId = nil
        demoLog("DEMO: branched play ready — boundary at 3.0s, branch duration \(model.branchDuration)")
    }

    /// Exactly the calls the canvas drag gesture makes: stop, one undo
    /// registration, then bendTrack at a FIXED time.
    private static func applyBend(_ model: PlayEditorModel) {
        guard let p1 = model.diagram.entities.first(where: { $0.label == "1" })?.id
        else { return }
        model.stop()
        model.selectedEntityId = p1
        model.registerUndo("Bend Path")
        model.bendTrack(entityId: p1, atLocal: 1.5, to: CGPoint(x: 24, y: 30))
        dumpTrack(model, p1, phase: "bent-sync")
    }

    /// The bend sequence, using exactly the calls the canvas drag gesture
    /// makes: stop, one undo registration, then bendTrack at a FIXED time.
    /// Phases are spaced so an external screenshot can catch each one.
    private static func runBendSequence(_ model: PlayEditorModel) {
        guard let p1 = model.diagram.entities.first(where: { $0.label == "1" })?.id
        else { return }
        dumpTrack(model, p1, phase: "baseline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            model.stop()
            model.selectedEntityId = p1
            model.registerUndo("Bend Path")
            // Grab was at local t=1.5 (mid-segment between the 1.0s and 2.0s
            // keys); the drag moves position only.
            model.bendTrack(entityId: p1, atLocal: 1.5, to: CGPoint(x: 24, y: 30))
            dumpTrack(model, p1, phase: "bent")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            model.undoManager?.undo()
            dumpTrack(model, p1, phase: "undone")
        }
    }

    private static func dumpTrack(_ model: PlayEditorModel, _ entityId: UUID,
                                  phase: String) {
        let frames = model.track(for: entityId)?.sortedKeyframes ?? []
        let dump = frames.map { frame in
            String(format: "t=%.2f (%.1f,%.1f)", frame.t,
                   frame.position.x, frame.position.y)
        }.joined(separator: "  ")
        demoLog("DEMO[\(phase)]: \(dump)")
    }

    private static let logger = Logger(subsystem: "hoopwise.demo", category: "scenario")

    /// The sandbox blocks file drops outside the container and `open` swallows
    /// stdout, so the unified log is the channel an outside agent can read:
    /// `log show --predicate 'subsystem == "hoopwise.demo"'`.
    private static func demoLog(_ message: String) {
        print(message)
        logger.notice("\(message, privacy: .public)")
        if let path = ProcessInfo.processInfo.environment["HOOPWISE_DEMO_LOG"],
           let data = (message + "\n").data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    private static func exportFrame(_ model: PlayEditorModel, to path: String) {
        guard let image = PlayFrameExporter.renderFrame(
            diagram: model.diagram,
            steps: model.activeSteps,
            at: model.playhead,
            elevationDegrees: model.renderElevation,
            look: model.look,
            style: model.isPresentation ? .presentation : .edit,
            backgroundHex: "#1B1B1B") else {
            demoLog("DEMO: export renderFrame returned nil")
            return
        }
        let ok = PlayFrameExporter.writePNG(image, to: URL(fileURLWithPath: path))
        demoLog("DEMO: export \(ok ? "wrote" : "FAILED") \(path) at t=\(model.playhead) style=\(model.isPresentation ? "presentation" : "edit")")
    }
}
#endif
