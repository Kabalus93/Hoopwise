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
    /// The editor's annotations (19 Nov 2026): finger, Pencil and pointer all
    /// draw; the play page's telestrator stays Pencil only.
    var anyInput = false
    /// The ink to draw with (the editor's pen or highlighter); nil keeps the
    /// telestrator's red pen.
    var ink: PKInkingTool? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PlayInkCanvas {
        let canvas = PlayInkCanvas()
        canvas.drawingPolicy = anyInput ? .anyInput : .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.tool = ink ?? Coordinator.pen
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
        // A new pen or colour, unless the Pencil switched to the eraser.
        if let ink, !(canvas.tool is PKEraserTool),
           (canvas.tool as? PKInkingTool).map({ $0.inkType != ink.inkType || $0.color != ink.color || $0.width != ink.width }) ?? true {
            canvas.tool = ink
        }
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
            canvas.tool = canvas.tool is PKEraserTool ? (parent.ink ?? Self.pen) : PKEraserTool(.vector)
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


// KEPT ANNOTATIONS (19 Nov 2026, Luther: "annotations can stay saved if I so
// choose"). A step stores its ink at `JournalPlayDiagram.inkScale` points a
// metre of the court drawing; these move it to and from a court drawn at `s`
// points a metre, and keep the rendered image so playback does not decode
// the drawing every frame.
enum PlayInkImages {
    /// The stored ink as it sits on a court drawn at `s` points a metre.
    static func drawing(_ data: Data?, scale s: CGFloat) -> PKDrawing {
        guard let data, let stored = try? PKDrawing(data: data) else { return PKDrawing() }
        let k = s / JournalPlayDiagram.inkScale
        return stored.transformed(using: CGAffineTransform(scaleX: k, y: k))
    }

    /// Ink drawn on a court at `s` points a metre, as the step stores it
    /// (nil when there is none).
    static func data(_ drawing: PKDrawing, scale s: CGFloat) -> Data? {
        guard !drawing.strokes.isEmpty, s > 0 else { return nil }
        let k = JournalPlayDiagram.inkScale / s
        return drawing.transformed(using: CGAffineTransform(scaleX: k, y: k)).dataRepresentation()
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// The ink rendered over a court drawn at `s` points a metre in `size`.
    static func image(_ data: Data, scale s: CGFloat, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = "\(data.hashValue)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let drawn = drawing(data, scale: s)
        guard !drawn.strokes.isEmpty else { return nil }
        let image = drawn.image(from: CGRect(origin: .zero, size: size), scale: 2)
        cache.setObject(image, forKey: key)
        return image
    }
}


/// The editor's annotation pens (19 Nov 2026, Luther: "a thick highlighter
/// plus a few colours, a pen plus colours").
enum AnnotationPen: String, CaseIterable, Identifiable {
    case pen, highlighter
    var id: String { rawValue }

    var colors: [AnnotationColor] {
        switch self {
        case .pen: [.red, .white, .yellow, .blue, .green]
        case .highlighter: [.yellow, .green, .pink, .blue, .orange]
        }
    }

    var defaultColor: AnnotationColor { self == .pen ? .red : .yellow }

    func tool(_ color: AnnotationColor) -> PKInkingTool {
        switch self {
        case .pen: PKInkingTool(.pen, color: color.ui, width: 5)
        case .highlighter: PKInkingTool(.marker, color: color.ui.withAlphaComponent(0.55), width: 26)
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, white, yellow, blue, green, pink, orange
    var id: String { rawValue }

    var ui: UIColor {
        switch self {
        case .red: .systemRed
        case .white: .white
        case .yellow: .systemYellow
        case .blue: .systemBlue
        case .green: .systemGreen
        case .pink: .systemPink
        case .orange: .systemOrange
        }
    }

    var label: JPString {
        switch self {
        case .red: "Red"
        case .white: "White"
        case .yellow: "Yellow"
        case .blue: "Blue"
        case .green: "Green"
        case .pink: "Pink"
        case .orange: "Orange"
        }
    }
}
