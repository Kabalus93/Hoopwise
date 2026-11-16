import SwiftUI
import PencilKit

// MARKING UP A PLAY WITH THE PENCIL (16 November 2026, Luther, on the play
// page: "using the Apple Pencil here should annotate"). A telestrator over
// the step player's court: the Pencil inks in red, a finger still swipes
// between steps and scrolls the page. Ink belongs to the step it was drawn
// on while the page is open and is never saved — it is for explaining, not
// for changing the play (that is the editor's job).
//
// PencilKit's canvas draws with the Pencil only (`.pencilOnly`). The scroll
// views around it (the step pager, the page) are told to scroll with fingers
// only, otherwise a Pencil stroke across the court would page to the next
// step instead of drawing. Double-tap / squeeze on the Pencil switches
// between pen and eraser.

struct PlayInkLayer: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PlayInkCanvas {
        let canvas = PlayInkCanvas()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.tool = Coordinator.pen
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        #if !targetEnvironment(macCatalyst)
        canvas.addInteraction(UIPencilInteraction(delegate: context.coordinator))
        #endif
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PlayInkCanvas, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing {
            context.coordinator.applying = true
            canvas.drawing = drawing
            context.coordinator.applying = false
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        static let pen = PKInkingTool(.pen, color: .systemRed, width: 5)

        var parent: PlayInkLayer
        weak var canvas: PKCanvasView?
        var applying = false

        init(_ parent: PlayInkLayer) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying else { return }
            let drawing = canvasView.drawing
            DispatchQueue.main.async { self.parent.drawing = drawing }
        }

        func toggleEraser() {
            guard let canvas else { return }
            canvas.tool = canvas.tool is PKEraserTool ? Self.pen : PKEraserTool(.vector)
        }
    }
}

#if !targetEnvironment(macCatalyst)
extension PlayInkLayer.Coordinator: UIPencilInteractionDelegate {
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        toggleEraser()
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { toggleEraser() }
    }
}
#endif

/// The canvas, which tells every scroll view around it to scroll with
/// fingers only once it is on screen.
final class PlayInkCanvas: PKCanvasView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                       NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        var view = superview
        while let current = view {
            if let scroll = current as? UIScrollView {
                scroll.panGestureRecognizer.allowedTouchTypes = fingers
            }
            view = current.superview
        }
    }
}
