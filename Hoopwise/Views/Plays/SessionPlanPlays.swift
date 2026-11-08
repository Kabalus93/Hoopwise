import SwiftData
import SwiftUI

/// The session plan's PLAYS card (November 2026, Luther: "add these plays to
/// the training plan"): plays from the Hub's library this session runs, in
/// order. Tap one to open it; + picks from the library. The plays are kept
/// in `SessionCurriculum.plays` (see `SessionPlayRef` for how a play is
/// found again).
struct SessionPlanPlaysSection: View {
    @Binding var plays: [SessionPlayRef]
    let canEdit: Bool
    let color: Color
    /// Writes the session after a change.
    let onChange: () -> Void

    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]
    @State private var picking = false
    @State private var opened: OpenedPlay?

    private struct OpenedPlay: Identifiable {
        let play: JournalPlay
        var id: PersistentIdentifier { play.persistentModelID }
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private func play(for ref: SessionPlayRef) -> JournalPlay? {
        library.first { $0.isNamed(by: ref) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if plays.isEmpty {
                HStack {
                    Text(isChinese ? "点击 + 从战术库添加" : "Tap + to add plays from your library")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plays.enumerated()), id: \.element) { index, ref in
                        row(ref, index: index)
                        if index < plays.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .sheet(isPresented: $picking) {
            SessionPlayPicker(library: library, selected: plays) { chosen in
                guard chosen != plays else { return }
                withAnimation { plays = chosen }
                onChange()
            }
        }
        .sheet(item: $opened) { opened in
            NavigationStack {
                JournalPlayScreen(play: opened.play)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { self.opened = nil } label: { Text(isChinese ? "完成" : "Done") }
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label {
                Text(isChinese ? "战术" : "PLAYS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "sportscourt")
                    .font(.caption)
                    .foregroundStyle(color)
            }
            Spacer()
            if !plays.isEmpty {
                Text(isChinese ? "\(plays.count) 个" : "\(plays.count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
            }
            if canEdit {
                Button { picking = true } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(color)
                .accessibilityLabel(isChinese ? "添加战术" : "Add plays")
                .accessibilityIdentifier("plan.plays.add")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func row(_ ref: SessionPlayRef, index: Int) -> some View {
        let found = play(for: ref)
        HStack(spacing: 12) {
            if let found {
                JournalPlayThumbnail(diagram: found.conceptPart?.sortedSteps.first?.diagram, court: found.court,
                                     width: 48, height: 42)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: found?.name ?? ref.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(found == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let found {
                    JournalPlayContents(play: found)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(isChinese ? "已不在战术库中" : "No longer in your library")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canEdit {
                Menu {
                    if index > 0 {
                        Button { move(index, by: -1) } label: {
                            Label(isChinese ? "上移" : "Move Up", systemImage: "arrow.up")
                        }
                    }
                    if index < plays.count - 1 {
                        Button { move(index, by: 1) } label: {
                            Label(isChinese ? "下移" : "Move Down", systemImage: "arrow.down")
                        }
                    }
                    Button(role: .destructive) { remove(index) } label: {
                        Label(isChinese ? "从计划中移除" : "Remove from Plan", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel(isChinese ? "更多" : "More")
            } else if found != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onTapGesture {
            if let found { opened = OpenedPlay(play: found) }
        }
        .accessibilityIdentifier("plan.plays.row.\(index)")
    }

    private func move(_ index: Int, by offset: Int) {
        guard plays.indices.contains(index), plays.indices.contains(index + offset) else { return }
        withAnimation { plays.swapAt(index, index + offset) }
        onChange()
    }

    private func remove(_ index: Int) {
        guard plays.indices.contains(index) else { return }
        _ = withAnimation { plays.remove(at: index) }
        onChange()
    }
}

/// Pick plays for a session from the library, by category, with search.
/// Ticks keep the plan's order; a newly ticked play goes at the end.
struct SessionPlayPicker: View {
    let library: [JournalPlay]
    let onDone: ([SessionPlayRef]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [SessionPlayRef]
    @State private var search = ""

    init(library: [JournalPlay], selected: [SessionPlayRef], onDone: @escaping ([SessionPlayRef]) -> Void) {
        self.library = library
        self.onDone = onDone
        _chosen = State(initialValue: selected)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var shown: [JournalPlay] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library }
        return library.filter { play in
            [play.name, play.situation, play.concept].contains { $0.localizedStandardContains(query) }
        }
    }

    private func isChosen(_ play: JournalPlay) -> Bool { chosen.contains { play.isNamed(by: $0) } }

    private func toggle(_ play: JournalPlay) {
        if let i = chosen.firstIndex(where: { play.isNamed(by: $0) }) {
            chosen.remove(at: i)
        } else {
            chosen.append(play.planRef)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if library.isEmpty {
                    ContentUnavailableView {
                        Label(isChinese ? "还没有战术" : "No plays yet", systemImage: "sportscourt")
                    } description: {
                        Text(isChinese ? "在 Hub → 战术 中绘制战术，然后在这里加入计划。"
                                       : "Draw plays in Hub → Plays, then add them to a plan here.")
                    }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach(JournalPlayCategory.allCases) { category in
                        let plays = shown.filter { $0.category == category }
                        if !plays.isEmpty {
                            Section { ForEach(plays) { row($0) } } header: { JText(category.label) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: JText("Search plays"))
            .navigationTitle(isChinese ? "添加战术" : "Add Plays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(isChinese ? "取消" : "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onDone(chosen)
                        dismiss()
                    } label: { Text(isChinese ? "完成" : "Done") }
                    .accessibilityIdentifier("plan.plays.done")
                }
            }
        }
    }

    private func row(_ play: JournalPlay) -> some View {
        Button { toggle(play) } label: {
            HStack(spacing: 12) {
                JournalPlayThumbnail(diagram: play.conceptPart?.sortedSteps.first?.diagram, court: play.court,
                                     width: 56, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: play.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    JournalPlayContents(play: play)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isChosen(play) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen(play) ? Color.accentColor : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen(play) ? .isSelected : [])
        .accessibilityIdentifier("plan.plays.pick.\(play.starterKey ?? play.name)")
    }
}
