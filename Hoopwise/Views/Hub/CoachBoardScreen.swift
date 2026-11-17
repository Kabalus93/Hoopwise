import SwiftUI

// THE COACH BOARD (17 November 2026, Luther: "a coach board … half or full
// court … the full play editor with every feature, including Scribble. It
// should not clear when I leave; it should offer the option to save as play
// or skill in the corner. If I leave without hitting either, I'd like to find
// it as is when I come back and hit myself the clear button to clean").
//
// Built from what exists: the board is a DrillDrawing (steps of the plays
// drawing model, any number of players, cones) opened straight in the full
// step editor (board mode: tool rail | court, steps behind a button at the
// bottom left; Court, Watch — ▶ and Scribble —, Clear and Save in the top
// bar). Every change is kept as it happens (`onChange`), so leaving or
// quitting loses nothing. Save as Play / Save as Drill copy it into the
// library and leave the board as it is; only Clear empties it.
//
// Device-local (a file in Application Support): the board is a scratchpad,
// and syncing it would need a schema field.

enum CoachBoardStore {
    static var url: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("CoachBoard", isDirectory: true).appendingPathComponent("board.json")
    }

    /// The board as it was left; nil when it was cleared or never used.
    static func load() -> DrillDrawing? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DrillDrawing.self, from: data)
    }

    static func save(_ drawing: DrillDrawing) {
        guard let url, let data = drawing.encoded else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Whether `drawing` is still the untouched starting board (nothing to keep).
    static func isBlank(_ drawing: DrillDrawing) -> Bool {
        drawing == DrillDrawing(court: drawing.court, steps: [DrillDrawing.Step(id: drawing.steps.first?.id ?? UUID(),
                                                                                    diagram: JournalPlayMath.defaultAlignment(drawing.court))])
    }
}

/// The board IS the editor, full screen (17 Nov 2026, Luther: "land directly
/// in the editor in full screen with only the tool bar on the side and steps
/// at the bottom left tucked into a button"). Opened from the Hub as a
/// full-screen cover; Done closes it. A court change or Clear rebuilds the
/// editor on the new drawing (`generation`).
struct CoachBoardScreen: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var drawing: DrillDrawing = CoachBoardStore.load() ?? .new(court: .half)
    @State private var generation = 0
    @State private var savingPlay = false
    @State private var savingDrill = false
    @State private var confirmingClear = false
    @State private var savedNote: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        JournalPlayStepEditor(
            drawing: drawing, onChange: keep,
            board: .init(isBlank: CoachBoardStore.isBlank(drawing),
                         setCourt: changeCourt,
                         clear: { confirmingClear = true },
                         saveAsPlay: { savingPlay = true },
                         saveAsDrill: { savingDrill = true })
        ) { keep($0) }
        .id(generation)
        .overlay(alignment: .top) {
            if let savedNote {
                Label(savedNote, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $savingPlay) {
            JournalNewPlaySheet(drawing: drawing) { play in
                PlayActivity.edited(play)
                announce(isChinese ? "已存为战术「\(play.name)」" : "Saved as the play “\(play.name)”")
            }
        }
        .sheet(isPresented: $savingDrill) {
            AddDrillView(drawing: drawing)
                .environmentObject(dataManager)
        }
        .confirmationDialog(isChinese ? "清空战术板？" : "Clear the board?", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(isChinese ? "清空" : "Clear", role: .destructive, action: clear)
                .accessibilityIdentifier("board.confirmClear")
        } message: {
            Text(isChinese ? "所有步骤都会删除。已存为战术或训练的不受影响。"
                           : "Every step goes. Anything saved as a play or a drill stays in the library.")
        }
    }

    // MARK: - Writes

    /// Every change is the board's at once (the editor reports as it goes).
    private func keep(_ new: DrillDrawing) {
        drawing = new
        CoachBoardStore.save(new)
    }

    private func changeCourt(_ court: JournalCourtKind) {
        guard court != drawing.court else { return }
        var new = drawing
        new.steps = drawing.steps.map { step in
            var s = step
            s.diagram = JournalPlayMath.converted(step.diagram, from: drawing.court, to: court)
            return s
        }
        new.court = court
        keep(new)
        generation += 1
    }

    private func clear() {
        CoachBoardStore.clear()
        drawing = .new(court: drawing.court)
        generation += 1
    }

    private func announce(_ text: String) {
        withAnimation { savedNote = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { if savedNote == text { savedNote = nil } }
        }
    }
}
