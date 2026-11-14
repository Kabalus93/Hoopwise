import SwiftUI
import UIKit

// APPLE PENCIL IN THE PLAY EDITOR (15 November 2026, Luther: "add pencil
// support for iPad, focus here is how to take advantage of it in the play
// editor"). SwiftUI's DragGesture cannot tell a Pencil from a finger and has
// no hover, double-tap or squeeze, so the court's input is this UIKit layer:
//
// · ONE touch is tracked at a time and reported with whether it is the
//   Pencil (its precise location). A Pencil arriving while a finger is down
//   takes over (the finger's gesture is cancelled); fingers touching while
//   the Pencil draws are ignored (a resting hand). A second FINGER cancels a
//   finger gesture — the start of a two- or three-finger tap.
// · Two-finger tap = undo, three-finger tap = redo.
// · Hover (Pencil hover on supported iPads, the pointer on a Mac / trackpad)
//   reports where the tip is, so the editor can ring what a stroke would use.
// · UIPencilInteraction double-tap and squeeze, mapped through the coach's
//   system preference (switch to eraser, previous tool, show palette).
//
// Mouse and trackpad clicks on the Mac arrive as ordinary touches, so the
// editor behaves there exactly as before.

struct CourtInputEvent {
    enum Phase { case began, moved, ended, cancelled }
    let phase: Phase
    let location: CGPoint
    let isPencil: Bool
}

/// What the Pencil's double-tap or squeeze asks for, from the system setting.
enum PencilShortcut {
    case eraser, previousTool, palette
}

struct CourtInputLayer: UIViewRepresentable {
    var onTouch: (CourtInputEvent) -> Void
    var onHover: (CGPoint?) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    /// Double-tap or squeeze, as the system setting asks, with the tip's
    /// location when it hovers.
    var onPencil: (_ shortcut: PencilShortcut, _ at: CGPoint?) -> Void

    func makeUIView(context: Context) -> CourtInputView {
        let view = CourtInputView()
        view.handlers = self
        return view
    }

    func updateUIView(_ view: CourtInputView, context: Context) {
        view.handlers = self
    }
}

final class CourtInputView: UIView {
    var handlers: CourtInputLayer?

    private var tracked: UITouch?
    /// Fingers came down together: nothing is drawn until every finger lifts.
    private var multiFinger = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let undo = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap))
        undo.numberOfTouchesRequired = 2
        undo.cancelsTouchesInView = false
        undo.delaysTouchesEnded = false
        undo.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(undo)

        let redo = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        redo.numberOfTouchesRequired = 3
        redo.cancelsTouchesInView = false
        redo.delaysTouchesEnded = false
        redo.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(redo)
        undo.require(toFail: redo)

        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))

        #if !targetEnvironment(macCatalyst)
        let pencil = UIPencilInteraction(delegate: self)
        addInteraction(pencil)
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Touches

    private func location(of touch: UITouch) -> CGPoint {
        touch.type == .pencil ? touch.preciseLocation(in: self) : touch.location(in: self)
    }

    private func send(_ phase: CourtInputEvent.Phase, _ touch: UITouch) {
        handlers?.onTouch(CourtInputEvent(phase: phase, location: location(of: touch), isPencil: touch.type == .pencil))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let current = tracked {
                if touch.type == .pencil, current.type != .pencil {
                    // The Pencil wins over a finger already down.
                    send(.cancelled, current)
                    tracked = touch
                    send(.began, touch)
                } else if touch.type != .pencil, current.type != .pencil {
                    // A second finger: a multi-finger tap, not a drawing.
                    send(.cancelled, current)
                    tracked = nil
                    multiFinger = true
                }
                // A finger while the Pencil draws: a resting hand, ignored.
            } else if touch.type == .pencil || !multiFinger {
                tracked = touch
                send(.began, touch)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked, touches.contains(tracked) else { return }
        send(.moved, tracked)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tracked, touches.contains(tracked) {
            send(.ended, tracked)
            self.tracked = nil
        }
        resetIfAllLifted(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tracked, touches.contains(tracked) {
            send(.cancelled, tracked)
            self.tracked = nil
        }
        resetIfAllLifted(event)
    }

    private func resetIfAllLifted(_ event: UIEvent?) {
        let stillDown = event?.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        if !stillDown { multiFinger = false }
    }

    // MARK: Gestures

    @objc private func twoFingerTap() { handlers?.onUndo() }
    @objc private func threeFingerTap() { handlers?.onRedo() }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed: handlers?.onHover(recognizer.location(in: self))
        default: handlers?.onHover(nil)
        }
    }
}

#if !targetEnvironment(macCatalyst)
extension CourtInputView: UIPencilInteractionDelegate {
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard let shortcut = Self.shortcut(for: UIPencilInteraction.preferredTapAction) else { return }
        handlers?.onPencil(shortcut, tap.hoverPose?.location)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        guard let shortcut = Self.shortcut(for: UIPencilInteraction.preferredSqueezeAction) else { return }
        handlers?.onPencil(shortcut, squeeze.hoverPose?.location)
    }

    private static func shortcut(for action: UIPencilPreferredAction) -> PencilShortcut? {
        switch action {
        case .switchEraser: return .eraser
        case .switchPrevious: return .previousTool
        case .showColorPalette, .showInkAttributes, .showContextualPalette: return .palette
        default: return nil
        }
    }
}
#endif
