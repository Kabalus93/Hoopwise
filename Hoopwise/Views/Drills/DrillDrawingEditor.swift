import SwiftUI

/// A drill's drawing in the Coach board's editor (19 Nov 2026, Luther:
/// "adding a drawing to a drill should use the general play editor like the
/// one accessed in the hub, not the halfcourt set editor that opens by
/// default in plays"): tool rail | the court as large as the window, steps
/// behind the button at the bottom left, ‹ ▶ › + at the bottom right, Half /
/// Full court and Clear in the top bar — with Cancel and Done, since a drill
/// drawing is kept only on Done. A court change rebuilds the editor on the
/// converted drawing (as the board does) without losing the right to Cancel.
struct DrillDrawingEditor: View {
    let onSave: (DrillDrawing) -> Void

    @State private var drawing: DrillDrawing
    @State private var generation = 0
    @State private var confirmingClear = false

    init(drawing: DrillDrawing, onSave: @escaping (DrillDrawing) -> Void) {
        self.onSave = onSave
        _drawing = State(initialValue: drawing)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        JournalPlayStepEditor(
            drawing: drawing,
            board: .init(title: "Drill drawing",
                         isBlank: CoachBoardStore.isBlank(drawing) && generation == 0,
                         setCourt: changeCourt,
                         clear: { confirmingClear = true },
                         edited: generation > 0),
            onSave: onSave)
        .id(generation)
        .confirmationDialog(isChinese ? "清空这张图？" : "Clear this drawing?", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(isChinese ? "清空" : "Clear", role: .destructive) {
                drawing = .empty(court: drawing.court)
                generation += 1
            }
            .accessibilityIdentifier("board.confirmClear")
        } message: {
            Text(isChinese ? "所有步骤都会删除；点“取消”可以放弃。" : "Every step goes. Cancel still brings the drawing back.")
        }
    }

    private func changeCourt(_ court: JournalCourtKind, _ now: DrillDrawing) {
        guard court != now.court else { return }
        var new = now
        new.steps = now.steps.map { step in
            var s = step
            s.diagram = JournalPlayMath.converted(step.diagram, from: now.court, to: court)
            return s
        }
        new.court = court
        drawing = new
        generation += 1
    }
}
