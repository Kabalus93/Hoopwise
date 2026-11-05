import SwiftData
import SwiftUI

/// The plays library: plays grouped by when they're run, each with a small
/// diagram, to open and study step by step.
///
/// HoopWise Journal's Plays tab, taken as is (Luther, November 2026); it
/// replaced League in the Hub. In the Journal it was a tab root with its own
/// NavigationStack; here it is pushed onto the Hub's stack, so it declares
/// destinations instead of owning a path, and a new play opens through
/// `created` (the play, then its first step to draw).
struct JournalPlaysScreen: View {
    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)]) private var plays: [JournalPlay]
    @Environment(\.modelContext) private var context
    @State private var created: Opened?

    /// A play pushed from here, and the part it opens on (a new play: its
    /// first step, to draw).
    private struct Opened: Hashable {
        let play: JournalPlay
        let route: JournalPlayStudyRoute?
    }
    @State private var search = ""
    @State private var creating = false
    @State private var deleting: JournalPlay?
    @State private var restored: Int?
    private var undoCenter: JUndoCenter { .shared }

    private struct Group: Identifiable {
        let category: JournalPlayCategory
        let plays: [JournalPlay]
        var id: JournalPlayCategory { category }
    }

    private var groups: [Group] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = query.isEmpty ? plays : plays.filter { play in
            [play.name, play.situation, play.concept].contains { $0.localizedStandardContains(query) }
        }
        return JournalPlayCategory.allCases.compactMap { category in
            let inCategory = shown.filter { $0.category == category }
            return inCategory.isEmpty ? nil : Group(category: category, plays: inCategory)
        }
    }

    var body: some View {
        SwiftUI.Group {
            ScrollView {
                VStack(alignment: .leading, spacing: JSpacing.m) {
                    if plays.isEmpty {
                        emptyLibrary
                    } else if groups.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                }
                .padding(.horizontal, JSpacing.screen)
                .padding(.bottom, JSpacing.xxl)
            }
            .background(JPalette.background)
            .navigationTitle(JText("Plays"))
            .navigationSubtitle(JText("\(plays.count) plays"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(text: $search, prompt: JText("Search plays"))
            .navigationDestination(item: $created) { opened in
                JournalPlayScreen(play: opened.play, opening: opened.route)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(action: restoreStarters) {
                            Label { JText("Add the starter plays again") } icon: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    } label: {
                        Label { JText("More") } icon: { Image(systemName: "ellipsis") }
                    }
                    Button { creating = true } label: {
                        Label { JText("New play") } icon: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $creating) {
                JournalNewPlaySheet { play in
                    created = Opened(play: play, route: play.conceptPart.map {
                        JournalPlayStudyRoute(part: $0, editing: true)
                    })
                }
            }
            .confirmationDialog(JText("Delete this play?"),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { play in
                Button(role: .destructive) { delete(play) } label: { JText("Delete play") }
            } message: { _ in
                JText("Its parts and steps go with it. You can undo for a few seconds.")
            }
            .alert(restoredTitle, isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })) {
                Button { restored = nil } label: { JText("OK") }
            }
        }
        .journalUndoToast()
        .task {
            JournalPlayLibrary.seedIfNeeded(context)
            JournalPlayLibrary.removeDuplicateStarters(context)
            #if DEBUG
            debugOpen()
            #endif
        }
    }

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: JSpacing.xs) {
            JEyebrowLabel(title: group.category.label)
            JCard(verticalPadding: JSpacing.xxs) {
                VStack(spacing: 0) {
                    ForEach(Array(group.plays.enumerated()), id: \.element.id) { i, play in
                        if i > 0 { Divider() }
                        // Destination links, not value links: this screen is pushed by
                        // the Hub's NavigationLink(destination:), and value routes
                        // declared here never resolved (rows did nothing).
                        NavigationLink {
                            JournalPlayScreen(play: play)
                        } label: {
                            JournalPlayRow(play: play)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plays.row.\(play.starterKey ?? play.name)")
                        .contextMenu {
                            Button(role: .destructive) { deleting = play } label: {
                                Label { JText("Delete play") } icon: { Image(systemName: "trash") }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label { JText("No plays yet") } icon: { Image(systemName: "sportscourt") }
        } description: {
            JText("The starter plays are the game plan's plays and the Horns family, drawn step by step.")
        } actions: {
            Button(action: restoreStarters) {
                JText("Add the starter plays")
            }
            .buttonStyle(.glassProminent)
            .tint(JPalette.ink)
            .foregroundStyle(JPalette.background)
        }
    }

    private var restoredTitle: Text {
        restored == 0 ? JText("The starter plays are all in your library") : JText("\(restored ?? 0) starter plays added")
    }

    private func restoreStarters() {
        restored = JournalPlayLibrary.restoreStarters(context)
    }

    private func delete(_ play: JournalPlay) {
        let snapshot = JournalPlaySnapshot(play)
        context.delete(play)
        try? context.save()
        let context = context
        undoCenter.show("Play deleted") {
            snapshot.restore(in: context)
            try? context.save()
        }
    }

    #if DEBUG
    /// HOOPWISE_PLAYS_OPEN (the Journal's `-open play|study|playback|legend|editor|details|newpart|newplay`,
    /// with `-play <starter key>`.
    private func debugOpen() {
        let options = JournalPlaysLaunch.current
        if options.opens("newplay") { creating = true }
        guard created == nil, let open = options.open,
              ["play", "study", "playback", "legend", "editor", "details", "newpart"].contains(open),
              let play = plays.first(where: { $0.starterKey == (options.play ?? "zone-23") }) ?? plays.first
        else { return }
        // The play, and for the study screens its part.
        let parts = play.sortedParts
        let part = parts.indices.contains(options.part ?? 0) ? parts[options.part ?? 0] : parts.first
        let studies = ["study", "playback", "legend", "editor"].contains(open)
        created = Opened(play: play, route: studies ? part.map { JournalPlayStudyRoute(part: $0) } : nil)
    }
    #endif
}

/// A play in the list: its first diagram, name, when it's run and what's in it.
struct JournalPlayRow: View {
    let play: JournalPlay

    var body: some View {
        HStack(spacing: JSpacing.s) {
            JournalPlayThumbnail(diagram: play.conceptPart?.sortedSteps.first?.diagram, court: play.court)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: play.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if !play.situation.isEmpty {
                    Text(verbatim: play.situation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                JournalPlayContents(play: play)
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
        .frame(minHeight: JTouchTarget.standard)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// "3 steps · 2 wrinkles · 2 variations".
struct JournalPlayContents: View {
    let play: JournalPlay

    var body: some View {
        let steps = play.conceptPart?.sortedSteps.count ?? 0
        let wrinkles = play.parts(.wrinkle).count
        let variations = play.parts(.variation).count
        let parts: [Text] = [
            JText("\(steps) steps"),
            wrinkles > 0 ? JText("\(wrinkles) wrinkles") : nil,
            variations > 0 ? JText("\(variations) variations") : nil,
        ].compactMap { $0 }
        return parts.dropFirst().reduce(parts[0]) { line, part in line + Text(verbatim: " · ") + part }
    }
}

/// A diagram on its own white panel, like a figure in the game plan.
struct JournalPlayThumbnail: View {
    let diagram: JournalPlayDiagram?
    let court: JournalCourtKind
    var width: CGFloat = 84
    var height: CGFloat = 72

    var body: some View {
        JournalPlayDiagramView(diagram: diagram ?? JournalPlayDiagram(), court: court, compact: true)
            .padding(2)
            .frame(width: width, height: height)
            .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile - 4))
    }
}
