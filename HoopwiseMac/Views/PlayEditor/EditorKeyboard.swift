import AppKit
import Combine
import os

// MARK: - The keyboard dispatch layer
//
// ONE local NSEvent key-down monitor per visible page context — no
// `.focusable()` views, no per-subview `onKeyPress`, no `onDeleteCommand`.
// Those were the focus-fragility class: whether Delete or O fired depended on
// which pane last owned focus, and each dead key got its own patch.
//
// `KeyDispatchCore` owns the mechanics every context shares:
//   1. Only key-downs addressed to the app's MAIN window are considered —
//      sheets, Settings, and popovers are separate NSWindows and pass
//      through untouched.
//   2. Suppressed while an actual text field is first responder (the field
//      editor is an NSTextView — the responder chain is queried, never a
//      bound-nowhere @FocusState).
//   3. A handled key is CONSUMED (returned nil), so Space can never reach a
//      default button and menu key equivalents cannot double-fire.
//   4. DEBUG builds log every decision to subsystem "hoopwise.keys": a dead
//      keypress tells you who swallowed it.
//
// Page contexts (editor, directory) supply only their key map. Exactly one
// is installed at a time — pages install on appear, uninstall on disappear.
@MainActor
final class KeyDispatchCore {

    /// What a context's key map decided.
    enum Verdict {
        case consumed(String)   // action name, for the log
        case pass(String)       // reason, for the log
    }

    private var monitor: Any?
    private let contextName: String
    private let keyMap: (NSEvent) -> Verdict
    #if DEBUG
    private let log = Logger(subsystem: "hoopwise.keys", category: "dispatch")
    #endif

    init(contextName: String, keyMap: @escaping (NSEvent) -> Verdict) {
        self.contextName = contextName
        self.keyMap = keyMap
    }

    func install() {
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
        // Monitor removal must not outlive the core; NSEvent holds the
        // closure, not us, so a leaked monitor keeps firing forever.
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Which windows a context receives events for.
    enum WindowScope {
        /// The document window only — sheets/popovers/Settings pass through.
        case mainWindow
        /// Attached sheets only — the presentation-dismissal context.
        case sheets
    }
    var windowScope: WindowScope = .mainWindow

    private func dispatch(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window else { return pass(event, "no-window") }
        switch windowScope {
        case .mainWindow:
            guard window === NSApp.mainWindow else { return pass(event, "other-window") }
        case .sheets:
            guard window.isSheet else { return pass(event, "not-a-sheet") }
        }
        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return pass(event, "text-field")
        }
        switch keyMap(event) {
        case .consumed(let action):
            #if DEBUG
            log.debug("[\(self.contextName, privacy: .public)] handled key=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) action=\(action, privacy: .public)")
            #endif
            return nil
        case .pass(let reason):
            return pass(event, reason)
        }
    }

    private func pass(_ event: NSEvent, _ reason: String) -> NSEvent {
        #if DEBUG
        let responder = event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        log.debug("[\(self.contextName, privacy: .public)] passed key=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) reason=\(reason, privacy: .public) responder=\(responder, privacy: .public)")
        #endif
        return event
    }
}

// MARK: - Shortcut reference (Settings reads these)

/// One row of the read-only Shortcuts reference. Declared IN this file,
/// beside the key maps they describe, so an edit to either is a one-file
/// diff — the closest thing to generation without table-driven dispatch.
struct KeyShortcutDescriptor {
    let keys: String
    let action: String
}

// MARK: - Presentation context (Esc closes any sheet, app-wide)

/// The anti-trap rule, in ONE place: Esc dismisses whatever sheet is up,
/// through the dispatch layer rather than per-sheet handlers. Installed by
/// RootView for the window's whole lifetime. SwiftUI observes the window
/// closing and clears the presenting binding, so no per-sheet wiring exists
/// to forget. (Popovers already dismiss on Esc and click-out natively.)
@MainActor
final class PresentationKeyDispatcher {

    private var core: KeyDispatchCore?

    func install() {
        guard core == nil else { return }
        let core = KeyDispatchCore(contextName: "presentation") { event in
            guard event.keyCode == 53,
                  event.window?.isSheet == true else {
                return .pass("unmapped")
            }
            // AppKit's endSheet does not clear SwiftUI's presentation
            // binding — the dismissal must flow through SwiftUI state. One
            // notification; MacSheetChrome (and the opt-in modifier for
            // chrome-less form sheets) clears the presenting binding.
            NotificationCenter.default.post(name: .macDismissPresentedSurface,
                                            object: nil)
            return .consumed("dismiss-sheet")
        }
        core.windowScope = .sheets
        core.install()
        self.core = core
    }

    func uninstall() {
        core?.uninstall()
        core = nil
    }
}

// MARK: - Editor context

/// The court editor's key map, riding KeyDispatchCore. All editor shortcuts
/// live HERE — never add key handling to an editor subview.
@MainActor
final class EditorKeyDispatcher {

    private weak var model: PlayEditorModel?
    private var core: KeyDispatchCore?

    func install(model: PlayEditorModel) {
        self.model = model
        guard core == nil else { return }
        let core = KeyDispatchCore(contextName: "editor") { [weak self] event in
            self?.verdict(for: event) ?? .pass("no-dispatcher")
        }
        core.install()
        self.core = core
    }

    func uninstall() {
        core?.uninstall()
        core = nil
    }

    private func verdict(for event: NSEvent) -> KeyDispatchCore.Verdict {
        guard let model else { return .pass("no-model") }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // The menu bar owns ⌘, except ⌘A.
        if flags.contains(.command) {
            if characters == "a", flags.subtracting([.command]).isEmpty {
                model.selectAllKeyframes()
                return .consumed("select-all-keyframes")
            }
            return .pass("command-menu")
        }

        switch event.keyCode {
        case 49:    // Space — never a default-button press, never a scroll.
            model.togglePlayback()
            return .consumed("play-pause")
        case 51, 117:   // Delete / forward delete
            if !model.selectedKeyframeIds.isEmpty {
                model.deleteSelectedKeyframesEverywhere()
                return .consumed("delete-selection")
            }
            if model.selectedEntityId != nil {
                model.deleteSelectedEntity()
                return .consumed("delete-entity")
            }
            return .pass("delete-nothing-selected")
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
            return .consumed("escape")
        case 123:   // ←
            guard !model.selectedKeyframeIds.isEmpty else { return .pass("arrow-no-selection") }
            model.nudgeSelectedKeyframes(by: -(model.snapEnabled ? model.snapInterval : 0.05))
            return .consumed("nudge-left")
        case 124:   // →
            guard !model.selectedKeyframeIds.isEmpty else { return .pass("arrow-no-selection") }
            model.nudgeSelectedKeyframes(by: model.snapEnabled ? model.snapInterval : 0.05)
            return .consumed("nudge-right")
        default:
            break
        }

        // Single-letter tools and actions. Shift is meaningful only for K.
        switch characters {
        case "a":
            model.placementKind = nil
            model.activeToolName = "Select"
            return .consumed("tool-select")
        case "o":
            model.placementKind = .player(team: .offense, number: nil, role: nil)
            model.activeToolName = "Offense"
            return .consumed("tool-offense")
        case "d":
            model.placementKind = .player(team: .defense, number: nil, role: nil)
            model.activeToolName = "Defense"
            return .consumed("tool-defense")
        case "b":
            guard model.canPlace(.ball) else { return .pass("ball-already-placed") }
            model.placementKind = .ball
            model.activeToolName = "Ball"
            return .consumed("tool-ball")
        case "c":
            model.placementKind = .cone
            model.activeToolName = "Cone"
            return .consumed("tool-cone")
        case "s":
            model.possessionEnabled.toggle()
            return .consumed("toggle-sticky")
        case "p":
            model.showMovementPaths.toggle()
            return .consumed("toggle-paths")
        case "k":
            if flags.contains(.shift) {
                model.keyframeAllLayersInPlace()
                return .consumed("keyframe-all")
            }
            guard let id = model.selectedEntityId else { return .pass("k-no-entity") }
            model.toggleKeyframeInPlace(id)
            return .consumed("keyframe-toggle")
        case "j":
            guard let id = model.selectedEntityId else { return .pass("j-no-entity") }
            model.jumpToKeyframe(id, direction: -1)
            return .consumed("jump-previous")
        case "l":
            guard let id = model.selectedEntityId else { return .pass("l-no-entity") }
            model.jumpToKeyframe(id, direction: 1)
            return .consumed("jump-next")
        default:
            return .pass("unmapped")
        }
    }
}

// MARK: - Directory context

/// Directory pages' bridge to the dispatch layer. The page owns one router,
/// wires closures, and the dispatcher maps keys through it: ↑↓ selection,
/// ⌘F search focus, ⌘N new item, Esc, and Contacts-style type-to-select.
@MainActor
final class DirectoryKeyRouter: ObservableObject {
    /// Bumps to ask the view to focus the search field (⌘F).
    @Published var searchFocusToken = 0
    var moveSelection: ((Int) -> Void)?
    var typeToSelect: ((String) -> Void)?
    /// Return true when Esc did something (cleared search/selection).
    var escape: (() -> Bool)?
    var newItem: (() -> Void)?

    // Type-to-select buffer with the standard timeout.
    fileprivate var buffer = ""
    fileprivate var lastKeyAt = Date.distantPast
}

@MainActor
final class DirectoryKeyDispatcher {

    private weak var router: DirectoryKeyRouter?
    private var core: KeyDispatchCore?

    func install(router: DirectoryKeyRouter) {
        self.router = router
        guard core == nil else { return }
        let core = KeyDispatchCore(contextName: "directory") { [weak self] event in
            self?.verdict(for: event) ?? .pass("no-dispatcher")
        }
        core.install()
        self.core = core
    }

    func uninstall() {
        core?.uninstall()
        core = nil
    }

    private func verdict(for event: NSEvent) -> KeyDispatchCore.Verdict {
        guard let router else { return .pass("no-router") }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            if characters == "f", flags.subtracting([.command]).isEmpty {
                router.searchFocusToken += 1
                return .consumed("focus-search")
            }
            if characters == "n", flags.subtracting([.command]).isEmpty,
               let newItem = router.newItem {
                newItem()
                return .consumed("new-item")
            }
            return .pass("command-menu")
        }

        switch event.keyCode {
        case 126:   // ↑
            router.moveSelection?(-1)
            return .consumed("selection-up")
        case 125:   // ↓
            router.moveSelection?(1)
            return .consumed("selection-down")
        case 53:    // Esc
            if router.escape?() == true { return .consumed("escape") }
            return .pass("escape-nothing")
        default:
            break
        }

        // Type-to-select: printable characters accumulate in a short window
        // and jump the selection — the Contacts/Finder behaviour.
        if flags.subtracting([.shift]).isEmpty,
           characters.count == 1,
           let scalar = characters.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) {
            let now = Date()
            if now.timeIntervalSince(router.lastKeyAt) > 1.0 { router.buffer = "" }
            router.lastKeyAt = now
            router.buffer += characters
            router.typeToSelect?(router.buffer)
            return .consumed("type-to-select:\(router.buffer)")
        }

        return .pass("unmapped")
    }
}


// MARK: - Shortcut tables

extension PresentationKeyDispatcher {
    static let shortcuts: [KeyShortcutDescriptor] = [
        .init(keys: "esc", action: "Close the open sheet"),
    ]
}

extension DirectoryKeyDispatcher {
    static let shortcuts: [KeyShortcutDescriptor] = [
        .init(keys: "\u{2191} \u{2193}", action: "Move selection"),
        .init(keys: "a\u{2026}z", action: "Type-to-select"),
        .init(keys: "\u{2318}F", action: "Focus search"),
        .init(keys: "\u{2318}N", action: "New item / new athlete"),
        .init(keys: "esc", action: "Clear search / cancel edit"),
    ]
}

extension EditorKeyDispatcher {
    static let shortcuts: [KeyShortcutDescriptor] = [
        .init(keys: "space", action: "Play / pause"),
        .init(keys: "\u{232B}", action: "Delete selection / entity"),
        .init(keys: "esc", action: "Cancel drag / clear selection / select tool"),
        .init(keys: "\u{2190} \u{2192}", action: "Nudge selected keyframes"),
        .init(keys: "A", action: "Select tool"),
        .init(keys: "O / D", action: "Place offense / defense"),
        .init(keys: "B", action: "Place ball"),
        .init(keys: "C", action: "Place cone"),
        .init(keys: "S", action: "Toggle sticky ball"),
        .init(keys: "P", action: "Toggle movement paths"),
        .init(keys: "K", action: "Keyframe in place"),
        .init(keys: "\u{21E7}K", action: "Keyframe all layers"),
        .init(keys: "J / L", action: "Previous / next keyframe"),
        .init(keys: "\u{2318}A", action: "Select all keyframes"),
    ]
}
