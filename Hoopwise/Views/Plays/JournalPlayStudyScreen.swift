import SwiftData
import SwiftUI

/// Study one part of a play step by step (`JournalPlayStepPlayer`: the
/// diagram large, swipe or the arrows between steps, ▶ to watch it run).
/// The pencil draws the step; the menu adds, moves and deletes steps.
struct JournalPlayStudyScreen: View {
    let part: JournalPlayPart

    @State private var index = 0
    @State private var showingLegend = false
    /// DEBUG: a frozen moment of the playback, for screenshots.
    @State private var frozenT: Double?
    @State private var editingStep: JournalPlayStep?
    /// Open the first step to draw once the screen is up (a new play or part).
    @State private var opensEditor: Bool
    @State private var renaming = false
    @State private var confirmingDelete = false
    private let autoplay: Bool
    @Environment(\.modelContext) private var context
    private var undoCenter: JUndoCenter { .shared }

    private var steps: [JournalPlayStep] { part.sortedSteps }
    private var court: JournalCourtKind { part.play?.court ?? .half }

    /// `startingAt` opens on a step; `autoplay` starts playing at once (a
    /// part opened from the play page, where opening it IS asking to watch).
    init(part: JournalPlayPart, editsFirstStep: Bool = false, startingAt step: Int = 0, autoplay: Bool = false) {
        self.part = part
        self.autoplay = autoplay && !editsFirstStep
        _opensEditor = State(initialValue: editsFirstStep)
        _index = State(initialValue: max(0, min(step, part.sortedSteps.count - 1)))
        #if DEBUG
        let options = JournalPlaysLaunch.current
        if let debugStep = options.step {
            _index = State(initialValue: max(0, min(debugStep, part.sortedSteps.count - 1)))
        }
        _frozenT = State(initialValue: options.opens("playback") ? 0.45 : nil)
        _showingLegend = State(initialValue: options.opens("legend"))
        if options.opens("editor") { _opensEditor = State(initialValue: true) }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JSpacing.m) {
                if steps.isEmpty {
                    ContentUnavailableView {
                        Label { JText("No steps yet") } icon: { Image(systemName: "sportscourt") }
                    } actions: {
                        Button(action: addStep) { JText("Add a step") }
                            .buttonStyle(.glassProminent)
                            .tint(JPalette.ink)
                            .foregroundStyle(JPalette.background)
                    }
                } else {
                    JournalPlayStepPlayer(part: part, index: $index,
                                          paused: editingStep != nil || renaming || confirmingDelete || showingLegend,
                                          autoplay: autoplay, frozenT: frozenT)
                }
            }
            .padding(.horizontal, JSpacing.screen)
            .padding(.bottom, JSpacing.xxl)
        }
        .background(JPalette.background)
        .navigationTitle(Text(verbatim: part.name))
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingLegend = true
                } label: {
                    Label { JText("Legend") } icon: { Image(systemName: "info.circle") }
                }
                if let current {
                    Button {
                        editingStep = current
                    } label: {
                        Label { JText("Draw this step") } icon: { Image(systemName: "pencil") }
                    }
                }
                menu
            }
        }
        .sheet(isPresented: $showingLegend) {
            JournalPlayLegendSheet()
        }
        .sheet(isPresented: $renaming) {
            JournalPlayPartSheet(mode: .edit(part))
        }
        .fullScreenCover(item: $editingStep) { step in
            JournalPlayStepEditor(step: step, court: court)
        }
        .confirmationDialog(JText("Delete this step?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: deleteStep) { JText("Delete step") }
        } message: {
            JText("Its drawing and notes go with it. You can undo for a few seconds.")
        }
        .journalUndoToast()
        .task {
            // After the push (and any closing sheet), or the cover won't show.
            guard opensEditor else { return }
            opensEditor = false
            try? await Task.sleep(for: .milliseconds(450))
            editingStep = current
        }
    }

    private var menu: some View {
        Menu {
            Button(action: addStep) {
                Label { JText("Add a step after this one") } icon: { Image(systemName: "plus") }
            }
            if steps.count > 1 {
                Button { move(by: -1) } label: {
                    Label { JText("Move step earlier") } icon: { Image(systemName: "arrow.left") }
                }
                .disabled(index == 0)
                Button { move(by: 1) } label: {
                    Label { JText("Move step later") } icon: { Image(systemName: "arrow.right") }
                }
                .disabled(index >= steps.count - 1)
            }
            Button { renaming = true } label: {
                Label { JText("Rename") } icon: { Image(systemName: "character.cursor.ibeam") }
            }
            if current != nil {
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label { JText("Delete step") } icon: { Image(systemName: "trash") }
                }
            }
        } label: {
            Label { JText("More") } icon: { Image(systemName: "ellipsis") }
        }
    }

    // MARK: - Editing

    /// A step after this one, starting where it ends, opened to draw.
    private func addStep() {
        let step = part.addStep(after: current, in: context)
        try? context.save()
        index = step.order
        editingStep = step
    }

    private func move(by offset: Int) {
        guard let current else { return }
        part.moveStep(current, by: offset)
        try? context.save()
        index = current.order
    }

    private func deleteStep() {
        guard let current else { return }
        let snapshot = JournalPlayStepSnapshot(current)
        let part = part
        context.delete(current)
        try? context.save()
        part.renumberSteps()
        try? context.save()
        index = max(0, min(index, steps.count - 1))
        let context = context
        undoCenter.show("Step deleted") {
            snapshot.restore(in: context, into: part)
            try? context.save()
        }
    }

    /// The play, and the kind of part; just "Concept" when the concept is
    /// named after the play.
    private var subtitle: Text {
        let name = part.play?.name ?? ""
        if part.kind == .concept, part.name == name { return JText(JournalPlayPartKind.concept.label) }
        let play = Text(verbatim: name)
        return part.kind == .concept ? play : play + Text(verbatim: " · ") + JText(part.kind.label)
    }

    private var current: JournalPlayStep? { steps.indices.contains(index) ? steps[index] : nil }
}

/// How to read the diagrams.
struct JournalPlayLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                JournalPlayLegend()
                    .padding(.horizontal, JSpacing.screen)
                    .padding(.vertical, JSpacing.m)
            }
            .navigationTitle(JText("Legend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { JText("Done") }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
