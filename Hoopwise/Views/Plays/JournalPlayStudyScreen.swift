import SwiftData
import SwiftUI

/// Study one part of a play step by step: the diagram large, swipe or the
/// arrows between steps, ▶ to watch it run (players along their paths,
/// then the ball along the passes), and the step's caption and points.
/// The pencil draws the step; the menu adds, moves and deletes steps.
struct JournalPlayStudyScreen: View {
    let part: JournalPlayPart

    @State private var index = 0
    @State private var playing = false
    @State private var stepStart = Date.now
    @State private var playback: Task<Void, Never>?
    @State private var showingLegend = false
    /// DEBUG: a frozen moment of the playback, for screenshots.
    @State private var frozenT: Double?
    @State private var editingStep: JournalPlayStep?
    /// Open the first step to draw once the screen is up (a new play or part).
    @State private var opensEditor: Bool
    @State private var renaming = false
    @State private var confirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    private var undoCenter: JUndoCenter { .shared }

    private var steps: [JournalPlayStep] { part.sortedSteps }
    private var court: JournalCourtKind { part.play?.court ?? .half }

    init(part: JournalPlayPart, editsFirstStep: Bool = false) {
        self.part = part
        _opensEditor = State(initialValue: editsFirstStep)
        #if DEBUG
        let options = JournalPlaysLaunch.current
        let index = max(0, min(options.step ?? 0, part.sortedSteps.count - 1))
        _index = State(initialValue: index)
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
                    JCard(verticalPadding: JSpacing.s) {
                        VStack(alignment: .leading, spacing: JSpacing.s) {
                            header
                            pager
                            controls
                        }
                    }
                    stepText
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
                        stop()
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
            JournalPlayStepEditor(step: step, court: court, number: step.order + 1)
        }
        .confirmationDialog(JText("Delete this step?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: deleteStep) { JText("Delete step") }
        } message: {
            JText("Its drawing and notes go with it. You can undo for a few seconds.")
        }
        .journalUndoToast()
        .onDisappear(perform: stop)
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
        stop()
        let step = part.addStep(after: current, in: context)
        try? context.save()
        index = step.order
        editingStep = step
    }

    private func move(by offset: Int) {
        guard let current else { return }
        stop()
        part.moveStep(current, by: offset)
        try? context.save()
        index = current.order
    }

    private func deleteStep() {
        guard let current else { return }
        stop()
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

    // MARK: - Diagram

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: JSpacing.xs) {
            Text(verbatim: current?.caption ?? "")
                .font(.headline)
            Spacer(minLength: JSpacing.xs)
            JText("Step \(index + 1) of \(steps.count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                diagram(step, isCurrent: i == index)
                    .padding(JSpacing.xs)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(JournalPlayCourt.aspectRatio(court), contentMode: .fit)
        .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: current?.caption ?? ""))
        .accessibilityValue(JText("Step \(index + 1) of \(steps.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: index + 1)
            case .decrement: go(to: index - 1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func diagram(_ step: JournalPlayStep, isCurrent: Bool) -> some View {
        if isCurrent, let frozenT {
            JournalPlayDiagramView(diagram: step.diagram, court: court, frame: JournalPlayMath.frame(step.diagram, at: frozenT))
        } else if isCurrent, playing, !reduceMotion {
            let diagram = step.diagram
            let duration = Self.duration(diagram)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(stepStart) / duration
                JournalPlayDiagramView(diagram: diagram, court: court, frame: JournalPlayMath.frame(diagram, at: t))
            }
        } else {
            JournalPlayDiagramView(diagram: step.diagram, court: court)
        }
    }

    private var controls: some View {
        HStack(spacing: JSpacing.s) {
            stepButton("chevron.left", label: "Previous step", enabled: index > 0) { go(to: index - 1) }
            Spacer(minLength: 0)
            Button {
                playing ? stop() : play()
            } label: {
                Label {
                    playing ? JText("Pause") : JText("Play")
                } icon: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(JPalette.background)
                .padding(.horizontal, JSpacing.l)
                .frame(minHeight: JTouchTarget.standard)
            }
            .buttonStyle(.glassProminent)
            .tint(JPalette.ink)
            Spacer(minLength: 0)
            stepButton("chevron.right", label: "Next step", enabled: index < steps.count - 1) { go(to: index + 1) }
        }
    }

    private func stepButton(_ symbol: String, label: JPString, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { JText(label) } icon: { Image(systemName: symbol) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: JTouchTarget.standard, height: JTouchTarget.standard)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var stepText: some View {
        if let text = current?.text, !text.isEmpty {
            JCard {
                Text(verbatim: text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index)
            }
        }
    }

    // MARK: - Playback

    /// Seconds a step plays: 1.2 s a beat (`JournalPlayMath.playBeats`).
    private static func duration(_ diagram: JournalPlayDiagram) -> Double {
        max(1.2, 1.2 * JournalPlayMath.playBeats(diagram))
    }

    private func go(to newIndex: Int) {
        stop()
        guard steps.indices.contains(newIndex) else { return }
        withAnimation(JMotion.expand) { index = newIndex }
    }

    /// From this step to the last; from the start when already on the last.
    private func play() {
        frozenT = nil
        if index >= steps.count - 1 { index = 0 }
        playing = true
        playback = Task { @MainActor in
            while !Task.isCancelled, steps.indices.contains(index) {
                stepStart = .now
                let hold = reduceMotion ? 2.4 : Self.duration(steps[index].diagram) + 0.8
                try? await Task.sleep(for: .seconds(hold))
                guard !Task.isCancelled else { return }
                guard index < steps.count - 1 else { break }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { index += 1 }
            }
            playing = false
        }
    }

    private func stop() {
        playback?.cancel()
        playback = nil
        playing = false
    }
}

/// How to read the diagrams.
private struct JournalPlayLegendSheet: View {
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
