import AppKit

/// v2's keyboard, on the SAME dispatch layer as everything else.
///
/// One local monitor, gated to the main window, suppressed while a text field
/// is first responder — which matters more here than it ever did in the
/// keyframe editor, because the caption field lives inside the primary chrome
/// and typing "n" in it must not add a frame.
@MainActor
final class FrameEditorKeyDispatcher {

    private weak var model: FrameEditorModel?
    private var core: KeyDispatchCore?

    func install(model: FrameEditorModel) {
        self.model = model
        guard core == nil else { return }
        let core = KeyDispatchCore(contextName: "frame-editor") { [weak self] event in
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
        // Command belongs to the menus, undo included.
        if flags.contains(.command) { return .pass("command-menu") }

        switch event.keyCode {
        case 123:   // ←
            model.previousFrame()
            return .consumed("previous-frame")
        case 124:   // →
            model.nextFrame()
            return .consumed("next-frame")
        case 51, 117:   // Delete
            guard model.selectedActionId != nil else { return .pass("delete-nothing") }
            model.deleteSelectedAction()
            return .consumed("delete-action")
        case 53:    // Esc: drop the selection, then the armed tool.
            if model.selectedActionId != nil || model.selectedEntityId != nil {
                model.selectedActionId = nil
                model.selectedEntityId = nil
            } else {
                model.armedTool = .select
            }
            return .consumed("escape")
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n":
            model.addFrame()
            return .consumed("add-frame")
        case "o":
            model.showOnionSkin.toggle()
            return .consumed("toggle-onion")
        case "s":
            model.armedTool = model.armedTool == .screen ? .select : .screen
            return .consumed("toggle-screen-tool")
        default:
            return .pass("unmapped")
        }
    }
}
