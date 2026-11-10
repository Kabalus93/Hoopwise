import SwiftData
import SwiftUI

/// Where a part opens: its study pages, or straight into drawing its first
/// step (a new play or part).
struct JournalPlayStudyRoute: Hashable {
    let part: JournalPlayPart
    var editing = false
}

/// One play: its concept drawn large, when it's run and the idea, then its
/// wrinkles and variations, and where it comes from.
struct JournalPlayScreen: View {
    let play: JournalPlay

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private var undoCenter: JUndoCenter { .shared }
    @State private var editingDetails = false
    @State private var partSheet: PartSheet?
    @State private var deletingPart: JournalPlayPart?
    @State private var confirmingDelete = false
    @State private var openedPart: JournalPlayStudyRoute?
    /// The concept's step on show: the page plays it in place.
    @State private var conceptStep = 0
    @State private var editingStep: JournalPlayStep?
    @State private var showingLegend = false
    /// The concept's step screen, for adding, moving and deleting steps.
    @State private var editingSteps = false
    /// The visible height, so the court fits the window (`JournalPlayStepPlayer`).
    @State private var viewportHeight: CGFloat?

    /// Opens straight on a part (a new play: its first step, to draw).
    init(play: JournalPlay, opening: JournalPlayStudyRoute? = nil) {
        self.play = play
        _openedPart = State(initialValue: opening)
    }

    private enum PartSheet: Identifiable {
        case add(JournalPlayPartKind)
        case edit(JournalPlayPart)

        var id: String {
            switch self {
            case .add(let kind): "add-\(kind.rawValue)"
            case .edit(let part): "edit-\(part.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JSpacing.m) {
                if let concept = play.conceptPart {
                    hero(concept)
                }
                about
                parts(.wrinkle)
                parts(.variation)
                source
            }
            .padding(.horizontal, JSpacing.screen)
            .padding(.bottom, JSpacing.xxl)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .background(JPalette.background)
        .navigationTitle(Text(verbatim: play.name))
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !isUndrawn, let step = currentConceptStep {
                    Button { showingLegend = true } label: {
                        Label { JText("Legend") } icon: { Image(systemName: "info.circle") }
                    }
                    Button { editingStep = step } label: {
                        Label { JText("Draw this step") } icon: { Image(systemName: "pencil") }
                    }
                }
                menu
            }
        }
        .navigationDestination(item: $openedPart) { route in
            JournalPlayStudyScreen(part: route.part, editsFirstStep: route.editing)
        }
        .navigationDestination(isPresented: $editingSteps) {
            if let concept = play.conceptPart {
                JournalPlayStudyScreen(part: concept, startingAt: conceptStep)
            }
        }
        .sheet(isPresented: $showingLegend) {
            JournalPlayLegendSheet()
        }
        .fullScreenCover(item: $editingStep) { step in
            JournalPlayStepEditor(step: step, court: play.court)
        }
        .sheet(isPresented: $editingDetails) {
            JournalPlayDetailsSheet(play: play)
        }
        .sheet(item: $partSheet) { sheet in
            switch sheet {
            case .add(let kind):
                JournalPlayPartSheet(mode: .add(play, kind)) { part in
                    openedPart = JournalPlayStudyRoute(part: part, editing: true)
                }
            case .edit(let part):
                JournalPlayPartSheet(mode: .edit(part))
            }
        }
        .confirmationDialog(JText("Delete this play?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: deletePlay) { JText("Delete play") }
        } message: {
            JText("Its parts and steps go with it. You can undo for a few seconds.")
        }
        .confirmationDialog(JText("Delete this part?"), isPresented: Binding(get: { deletingPart != nil },
                                                                           set: { if !$0 { deletingPart = nil } }),
                            titleVisibility: .visible, presenting: deletingPart) { part in
            Button(role: .destructive) { delete(part) } label: { JText("Delete \(part.name)") }
        } message: { _ in
            JText("Its steps go with it. You can undo for a few seconds.")
        }
        .journalUndoToast()
        .onAppear { PlayActivity.opened(play) }
        #if DEBUG
        .onAppear {
            switch JournalPlaysLaunch.current.open {
            case "details": editingDetails = true
            case "newpart": partSheet = .add(.wrinkle)
            default: break
            }
        }
        #endif
    }

    /// The category, and the court when it's the whole floor.
    private var subtitle: Text {
        let category = JText(play.category.label)
        return play.court == .full ? category + Text(verbatim: " · ") + JText(play.court.label) : category
    }

    private var menu: some View {
        Menu {
            Button { editingDetails = true } label: {
                Label { JText("Edit details") } icon: { Image(systemName: "pencil") }
            }
            if !isUndrawn, play.conceptPart != nil {
                Button { editingSteps = true } label: {
                    Label { JText("Edit steps") } icon: { Image(systemName: "list.number") }
                }
            }
            Button { partSheet = .add(.wrinkle) } label: {
                Label { JText("Add a wrinkle") } icon: { Image(systemName: "plus") }
            }
            Button { partSheet = .add(.variation) } label: {
                Label { JText("Add a variation") } icon: { Image(systemName: "plus.square.on.square") }
            }
            Divider()
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label { JText("Delete play") } icon: { Image(systemName: "trash") }
            }
        } label: {
            Label { JText("More") } icon: { Image(systemName: "ellipsis") }
        }
    }

    /// Nothing drawn yet: the hero offers to draw instead of to play.
    private var isUndrawn: Bool {
        (play.parts ?? []).allSatisfy { part in (part.steps ?? []).allSatisfy { $0.diagram.actions.isEmpty } }
    }

    private var currentConceptStep: JournalPlayStep? {
        let steps = play.conceptPart?.sortedSteps ?? []
        return steps.indices.contains(conceptStep) ? steps[conceptStep] : nil
    }

    /// The concept, played in place: ‹ ▶ › under its diagram, its steps'
    /// text below. Undrawn, the hero offers to draw instead.
    @ViewBuilder
    private func hero(_ concept: JournalPlayPart) -> some View {
        if isUndrawn || concept.sortedSteps.isEmpty {
            drawHero(concept)
        } else {
            VStack(alignment: .leading, spacing: JSpacing.xs) {
                conceptLabel(concept)
                JournalPlayStepPlayer(part: concept, index: $conceptStep,
                                      paused: editingStep != nil || showingLegend || editingSteps,
                                      viewportHeight: viewportHeight)
            }
            // Steps deleted on the step screen: stay on one that exists.
            .onAppear { conceptStep = max(0, min(conceptStep, concept.sortedSteps.count - 1)) }
        }
    }

    /// "Concept", and its name when it isn't the play's.
    private func conceptLabel(_ concept: JournalPlayPart) -> some View {
        HStack(spacing: JSpacing.xxs) {
            JEyebrowLabel(title: JournalPlayPartKind.concept.label)
            if concept.name != play.name, !concept.name.isEmpty {
                Text(verbatim: "· \(concept.name)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button { partSheet = .edit(concept) } label: {
                Label { JText("Rename") } icon: { Image(systemName: "pencil") }
            }
        }
    }

    /// A play with nothing drawn yet: its first diagram; tap to draw it.
    private func drawHero(_ concept: JournalPlayPart) -> some View {
        NavigationLink {
            JournalPlayStudyScreen(part: concept, editsFirstStep: isUndrawn)
        } label: {
            JCard(verticalPadding: JSpacing.s) {
                VStack(alignment: .leading, spacing: JSpacing.s) {
                    JournalPlayDiagramView(diagram: concept.sortedSteps.first?.diagram ?? JournalPlayDiagram(), court: play.court)
                        .padding(JSpacing.xs)
                        .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
                    HStack(spacing: JSpacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            JEyebrowLabel(title: JournalPlayPartKind.concept.label)
                            Text(verbatim: concept.name)
                                .font(.headline)
                        }
                        Spacer(minLength: JSpacing.xs)
                        Label {
                            isUndrawn ? JText("Draw") : JText("\(concept.sortedSteps.count) steps")
                        } icon: {
                            Image(systemName: isUndrawn ? "pencil" : "play.fill")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JPalette.background)
                        .padding(.horizontal, JSpacing.m)
                        .frame(minHeight: JTouchTarget.standard)
                        .background(JPalette.ink, in: .capsule)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plays.hero")
        .contextMenu {
            Button { partSheet = .edit(concept) } label: {
                Label { JText("Rename") } icon: { Image(systemName: "pencil") }
            }
        }
    }

    @ViewBuilder
    private var about: some View {
        if !play.situation.isEmpty || !play.concept.isEmpty {
            JCard {
                VStack(alignment: .leading, spacing: JSpacing.s) {
                    if !play.situation.isEmpty {
                        paragraph("When", play.situation)
                    }
                    if !play.concept.isEmpty {
                        paragraph("The idea", play.concept)
                    }
                }
            }
        } else {
            Button { editingDetails = true } label: {
                JCard {
                    JSummaryRow(symbol: "text.alignleft", title: "When and the idea",
                               value: JText("Not filled in"))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func paragraph(_ title: JPString, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: JSpacing.xxs) {
            JEyebrowLabel(title: title)
            Text(verbatim: text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func parts(_ kind: JournalPlayPartKind) -> some View {
        let parts = play.parts(kind)
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: JSpacing.xs) {
                JEyebrowLabel(title: kind.label)
                JCard(verticalPadding: JSpacing.xxs) {
                    VStack(spacing: 0) {
                        ForEach(Array(parts.enumerated()), id: \.element.id) { i, part in
                            if i > 0 { Divider() }
                            // Opening a wrinkle or variation plays it at once.
                            NavigationLink {
                                JournalPlayStudyScreen(part: part, autoplay: true)
                            } label: {
                                JournalPlayPartRow(part: part, court: play.court)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("plays.part.\(kind.rawValue).\(i)")
                            .contextMenu { partMenu(part, index: i, count: parts.count) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func partMenu(_ part: JournalPlayPart, index: Int, count: Int) -> some View {
        Button { partSheet = .edit(part) } label: {
            Label { JText("Rename") } icon: { Image(systemName: "pencil") }
        }
        if index > 0 {
            Button { withAnimation { play.movePart(part, by: -1) } } label: {
                Label { JText("Move up") } icon: { Image(systemName: "arrow.up") }
            }
        }
        if index < count - 1 {
            Button { withAnimation { play.movePart(part, by: 1) } } label: {
                Label { JText("Move down") } icon: { Image(systemName: "arrow.down") }
            }
        }
        Button(role: .destructive) { deletingPart = part } label: {
            Label { JText("Delete") } icon: { Image(systemName: "trash") }
        }
    }

    @ViewBuilder
    private var source: some View {
        if !play.source.isEmpty {
            VStack(alignment: .leading, spacing: JSpacing.xxs) {
                JEyebrowLabel(title: "Source")
                if let link = play.sourceURL.flatMap(URL.init(string:)), link.scheme?.hasPrefix("http") == true {
                    Link(destination: link) {
                        Label { Text(verbatim: play.source) } icon: { Image(systemName: "arrow.up.right.square") }
                            .font(.subheadline)
                            .frame(minHeight: JTouchTarget.standard, alignment: .leading)
                    }
                } else {
                    Text(verbatim: play.source)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Delete

    private func deletePlay() {
        let snapshot = JournalPlaySnapshot(play)
        context.delete(play)
        try? context.save()
        let context = context
        undoCenter.show("Play deleted") {
            snapshot.restore(in: context)
            try? context.save()
        }
        dismiss()
    }

    private func delete(_ part: JournalPlayPart) {
        let snapshot = JournalPlayPartSnapshot(part)
        context.delete(part)
        try? context.save()
        let context = context
        undoCenter.show("Part deleted") {
            snapshot.restore(in: context)
            try? context.save()
        }
    }
}

/// A wrinkle or variation: its first diagram, name, what changes, steps.
private struct JournalPlayPartRow: View {
    let part: JournalPlayPart
    let court: JournalCourtKind

    var body: some View {
        HStack(spacing: JSpacing.s) {
            JournalPlayThumbnail(diagram: part.sortedSteps.first?.diagram, court: court)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: part.name)
                    .font(.body.weight(.semibold))
                if !part.notes.isEmpty {
                    Text(verbatim: part.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                JText("\(part.sortedSteps.count) steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, JSpacing.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
