import SwiftUI

// THE COACH BOARD (17 November 2026, Luther: "a coach board … half or full
// court … the full play editor with every feature, including Scribble. It
// should not clear when I leave; it should offer the option to save as play
// or skill in the corner. If I leave without hitting either, I'd like to find
// it as is when I come back and hit myself the clear button to clean").
//
// Built from what exists: the board is a DrillDrawing (steps of the plays
// drawing model, any number of players, cones); the page shows it in the
// step player (▶ playback, Pencil ink, Scribble on an iPad) and Draw opens the
// full step editor on it. Every change in the editor is kept as it happens
// (`onChange`), so Cancel or leaving the app loses nothing. Save as Play /
// Save as Drill copy it into the library and leave the board as it is; only
// Clear empties it.
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

struct CoachBoardScreen: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var drawing: DrillDrawing = CoachBoardStore.load() ?? .new(court: .half)
    @State private var index = 0
    @State private var editing = false
    @State private var savingPlay = false
    @State private var savingDrill = false
    @State private var confirmingClear = false
    @State private var savedNote: String?
    @State private var viewportHeight: CGFloat?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                courtPicker
                JournalPlayStepPlayer(steps: drawing.steps.map { .init(diagram: $0.diagram, caption: $0.caption, text: $0.text) },
                                      court: drawing.court, index: $index, paused: editing,
                                      viewportHeight: viewportHeight) { EmptyView() }
                    .id(drawing.court)
                drawButton
                if let savedNote {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .background(JPalette.background)
        .navigationTitle(isChinese ? "战术板" : "Coach board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onChange(of: drawing.steps.count) { _, count in index = min(index, max(count - 1, 0)) }
        .fullScreenCover(isPresented: $editing) {
            JournalPlayStepEditor(drawing: drawing, onChange: keep) { keep($0) }
        }
        .sheet(isPresented: $savingPlay) {
            JournalNewPlaySheet(drawing: drawing) { play in
                PlayActivity.edited(play)
                announce(isChinese ? "已存为战术「\(play.name)」，战术板保持不变。" : "Saved as the play “\(play.name)”. The board stays as it is.")
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

    private var courtPicker: some View {
        Picker(isChinese ? "球场" : "Court", selection: Binding(get: { drawing.court }, set: changeCourt)) {
            ForEach(JournalCourtKind.allCases) { court in
                JText(court.label).tag(court)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .accessibilityIdentifier("board.court")
    }

    private var drawButton: some View {
        Button { editing = true } label: {
            Label(isChinese ? "在战术板上画" : "Draw on the board", systemImage: "pencil.tip.crop.circle")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("board.draw")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(role: .destructive) { confirmingClear = true } label: {
                Label(isChinese ? "清空" : "Clear", systemImage: "eraser")
            }
            .disabled(CoachBoardStore.isBlank(drawing))
            .accessibilityIdentifier("board.clear")

            Menu {
                Button { savingPlay = true } label: {
                    Label(isChinese ? "存为战术" : "Save as Play", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .accessibilityIdentifier("board.saveAsPlay")
                Button { savingDrill = true } label: {
                    Label(isChinese ? "存为训练" : "Save as Drill", systemImage: "figure.basketball")
                }
                .accessibilityIdentifier("board.saveAsDrill")
            } label: {
                Label(isChinese ? "保存" : "Save", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("board.save")
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
    }

    private func clear() {
        CoachBoardStore.clear()
        drawing = .new(court: drawing.court)
        index = 0
    }

    private func announce(_ text: String) {
        withAnimation { savedNote = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if savedNote == text { savedNote = nil } }
        }
    }
}
