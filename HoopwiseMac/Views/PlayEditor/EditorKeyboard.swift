import AppKit
import os

/// THE keyboard dispatch layer for the court editor window.
///
/// Every editor shortcut routes through one local NSEvent key-down monitor —
/// no `.focusable()` views, no per-subview `onKeyPress`, no `onDeleteCommand`.
/// Those were the focus-fragility class: whether Delete or O fired depended on
/// which pane last owned focus, and each dead key got its own patch.
///
/// Rules, in order:
///   1. Only key-downs addressed to the editor's own window are considered —
///      sheets, Settings, and popovers are separate NSWindows and pass
///      through untouched.
///   2. Suppressed while an actual text field is first responder (the field
///      editor is an NSTextView — the responder chain is queried, never a
///      bound-nowhere @FocusState).
///   3. ⌘-shortcuts pass through to the menu bar (⌘A excepted — select all
///      keyframes is an editor concern).
///   4. A handled key is CONSUMED (return nil), so Space can never reach a
///      default button and the Play menu's key equivalent cannot double-fire.
///
/// DEBUG builds log every decision to subsystem "hoopwise.keys": a dead
/// keypress tells you who swallowed it instead of demanding a reproduction.
@MainActor
final class EditorKeyDispatcher {

    private weak var model: PlayEditorModel?
    private var monitor: Any?
    #if DEBUG
    private let log = Logger(subsystem: "hoopwise.keys", category: "dispatch")
    #endif

    func install(model: PlayEditorModel) {
        self.model = model
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.dispatch(event)
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        // Monitor removal must not outlive the dispatcher; NSEvent holds the
        // closure, not us, so a leaked monitor keeps firing forever.
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Dispatch

    private func dispatch(_ event: NSEvent) -> NSEvent? {
        guard let model else { return event }

        // Rule 1: our window only. Sheets, Settings, popovers, panels are
        // their own windows and keep native behaviour.
        guard let window = event.window, window === NSApp.mainWindow else {
            return pass(event, "other-window")
        }

        // Rule 2: typing wins. The field editor for any focused text control
        // is an NSTextView; NSTextField covers direct cases.
        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return pass(event, "text-field")
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Rule 3: the menu bar owns ⌘, except ⌘A.
        if flags.contains(.command) {
            if characters == "a", flags.subtracting([.command]).isEmpty {
                model.selectAllKeyframes()
                return consume(event, "select-all-keyframes")
            }
            return pass(event, "command-menu")
        }

        switch event.keyCode {
        case 49:    // Space — never a default-button press, never a scroll.
            model.togglePlayback()
            return consume(event, "play-pause")
        case 51, 117:   // Delete / forward delete
            if !model.selectedKeyframeIds.isEmpty {
                model.deleteSelectedKeyframesEverywhere()
                return consume(event, "delete-selection")
            }
            if model.selectedEntityId != nil {
                model.deleteSelectedEntity()
                return consume(event, "delete-entity")
            }
            return pass(event, "delete-nothing-selected")
        case 53:    // Escape: ball drag, then selection, then tool.
            if model.isBallDragging {
                model.cancelBallDrag()
            } else if !model.selectedKeyframeIds.isEmpty || model.selectedBallSpanId != nil {
                model.selectedKeyframeIds.removeAll()
                model.selectedBallSpanId = nil
            } else {
                model.placementKind = nil
                model.activeToolName = "Select"
            }
            return consume(event, "escape")
        case 123:   // ←
            guard !model.selectedKeyframeIds.isEmpty else { return pass(event, "arrow-no-selection") }
            model.nudgeSelectedKeyframes(by: -(model.snapEnabled ? model.snapInterval : 0.05))
            return consume(event, "nudge-left")
        case 124:   // →
            guard !model.selectedKeyframeIds.isEmpty else { return pass(event, "arrow-no-selection") }
            model.nudgeSelectedKeyframes(by: model.snapEnabled ? model.snapInterval : 0.05)
            return consume(event, "nudge-right")
        default:
            break
        }

        // Single-letter tools and actions. Shift is meaningful only for K.
        switch characters {
        case "a":
            model.placementKind = nil
            model.activeToolName = "Select"
            return consume(event, "tool-select")
        case "o":
            model.placementKind = .player(team: .offense, number: nil, role: nil)
            model.activeToolName = "Offense"
            return consume(event, "tool-offense")
        case "d":
            model.placementKind = .player(team: .defense, number: nil, role: nil)
            model.activeToolName = "Defense"
            return consume(event, "tool-defense")
        case "b":
            guard model.canPlace(.ball) else { return pass(event, "ball-already-placed") }
            model.placementKind = .ball
            model.activeToolName = "Ball"
            return consume(event, "tool-ball")
        case "c":
            model.placementKind = .cone
            model.activeToolName = "Cone"
            return consume(event, "tool-cone")
        case "s":
            model.possessionEnabled.toggle()
            return consume(event, "toggle-sticky")
        case "p":
            model.showMovementPaths.toggle()
            return consume(event, "toggle-paths")
        case "k":
            if flags.contains(.shift) {
                model.keyframeAllLayersInPlace()
                return consume(event, "keyframe-all")
            }
            guard let id = model.selectedEntityId else { return pass(event, "k-no-entity") }
            model.toggleKeyframeInPlace(id)
            return consume(event, "keyframe-toggle")
        case "j":
            guard let id = model.selectedEntityId else { return pass(event, "j-no-entity") }
            model.jumpToKeyframe(id, direction: -1)
            return consume(event, "jump-previous")
        case "l":
            guard let id = model.selectedEntityId else { return pass(event, "l-no-entity") }
            model.jumpToKeyframe(id, direction: 1)
            return consume(event, "jump-next")
        default:
            return pass(event, "unmapped")
        }
    }

    // MARK: - Outcome plumbing

    private func consume(_ event: NSEvent, _ action: String) -> NSEvent? {
        #if DEBUG
        log.debug("handled key=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) action=\(action, privacy: .public)")
        #endif
        return nil
    }

    private func pass(_ event: NSEvent, _ reason: String) -> NSEvent {
        #if DEBUG
        let responder = event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        log.debug("passed key=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) reason=\(reason, privacy: .public) responder=\(responder, privacy: .public)")
        #endif
        return event
    }
}
