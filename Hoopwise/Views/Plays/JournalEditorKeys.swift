import OSLog
import SwiftUI
import UIKit

/// The step editor workspace's special keys: ⌫, Esc and the arrows.
///
/// SwiftUI's `.keyboardShortcut` reaches plain letters (the tool keys) but
/// never these on iPadOS / Mac Catalyst: the system keeps them for its own
/// behaviours (focus movement, dismissal) unless a UIKeyCommand asks for
/// priority, which SwiftUI cannot. Found in November 2026 by
/// PlayEditorWorkspaceUITests: letters switched tools, ⌫ and Esc did nothing.
///
/// The catcher takes first responder while `active` (no text field being
/// edited) and reads raw presses (`pressesBegan`), with priority key
/// commands as a second route; it gives way to a text field the moment one
/// is tapped — typing is never intercepted. Logs to "hoopwise.keys".
///
/// TESTING LIMIT: XCUITest's `typeKey` on the iPad simulator delivers
/// letters, arrows, Tab and Space as presses, but NOT Esc, ⌫ or Return
/// (only their modifier keys arrive). The arrows prove this catcher's path
/// end to end; ⌫ and Esc ride the same path and need a real keyboard.
struct JournalEditorKeys: UIViewRepresentable {
    enum Key { case delete, escape, left, right, up, down }

    var active: Bool
    /// The key, and whether ⇧ was held.
    var onKey: (Key, Bool) -> Void

    func makeUIView(context: Context) -> KeyCatcher {
        let view = KeyCatcher()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: KeyCatcher, context: Context) {
        view.onKey = onKey
        view.active = active
        view.claimIfNeeded()
    }

    final class KeyCatcher: UIView {
        var onKey: ((Key, Bool) -> Void)?
        var active = false
        static let log = Logger(subsystem: "hoopwise.keys", category: "editor")

        override var canBecomeFirstResponder: Bool { active }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            claimIfNeeded()
        }

        func claimIfNeeded() {
            guard active, window != nil, !isFirstResponder else { return }
            DispatchQueue.main.async { [weak self] in
                // `active` is already off while a text field is being edited.
                guard let self, self.active, self.window != nil, !self.isFirstResponder else { return }
                let claimed = self.becomeFirstResponder()
                Self.log.debug("key catcher claimed first responder: \(claimed, privacy: .public)")
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            guard active else { return nil }
            let inputs: [(String, Key)] = [
                ("\u{8}", .delete), ("\u{7F}", .delete), (UIKeyCommand.inputDelete, .delete),
                (UIKeyCommand.inputEscape, .escape),
                (UIKeyCommand.inputLeftArrow, .left), (UIKeyCommand.inputRightArrow, .right),
                (UIKeyCommand.inputUpArrow, .up), (UIKeyCommand.inputDownArrow, .down),
            ]
            return inputs.flatMap { input, _ in
                [UIKeyModifierFlags(), .shift].map { flags in
                    let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(handle(_:)))
                    command.wantsPriorityOverSystemBehavior = true
                    return command
                }
            }
        }

        /// Raw presses reach the first responder whatever the system does
        /// with key commands; this is the path that works on iPadOS.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard active, let uiKey = press.key else { continue }
                let key: Key? = switch uiKey.keyCode {
                case .keyboardDeleteOrBackspace, .keyboardDeleteForward: .delete
                case .keyboardEscape: .escape
                case .keyboardLeftArrow: .left
                case .keyboardRightArrow: .right
                case .keyboardUpArrow: .up
                case .keyboardDownArrow: .down
                default: nil
                }
                if let key {
                    Self.log.debug("key catcher press \(String(describing: key), privacy: .public)")
                }
                if let key, uiKey.modifierFlags.subtracting(.shift).intersection([.command, .control, .alternate]).isEmpty {
                    onKey?(key, uiKey.modifierFlags.contains(.shift))
                    handled = true
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }

        @objc private func handle(_ command: UIKeyCommand) {
            let key: Key? = switch command.input {
            case "\u{8}", "\u{7F}", UIKeyCommand.inputDelete: .delete
            case UIKeyCommand.inputEscape: .escape
            case UIKeyCommand.inputLeftArrow: .left
            case UIKeyCommand.inputRightArrow: .right
            case UIKeyCommand.inputUpArrow: .up
            case UIKeyCommand.inputDownArrow: .down
            default: nil
            }
            Self.log.debug("key catcher command \(String(describing: key), privacy: .public)")
            if let key { onKey?(key, command.modifierFlags.contains(.shift)) }
        }
    }
}
