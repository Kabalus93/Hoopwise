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
    /// A team practice's team: its plays open with the team's faces and sharing.
    var teamId: UUID? = nil
    /// A GAME's plays (24 Nov 2026): titled "Calls", sorted by the situation
    /// the team's playbook files each under, with the defense on top.
    var calls: Calls? = nil
    /// The class's game RULES (27 Nov 2026, Luther): when given, + offers
    /// "Add plays" or "Add a rule" and the rules list under the plays.
    var rules: Binding<[SessionRule]>? = nil
    /// The age whose library rule options are offered first.
    var ruleAge: ActivityAge? = nil

    struct Calls {
        var playbook: TeamPlaybook?
        /// "Man to man — switch every screen".
        var defense: String?
    }

    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]
    @State private var picking = false
    @State private var addingRule = false
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
            if let defense = calls?.defense, !defense.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled").font(.footnote).foregroundStyle(color)
                    Text(isChinese ? "防守" : "Defense").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(defense).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("game.calls.defense")
            }
            if plays.isEmpty && (rules?.wrappedValue.isEmpty ?? true) {
                HStack {
                    Text(rules != nil ? (isChinese ? "点击 + 添加战术或比赛规则" : "Tap + to add plays or game rules")
                                      : (isChinese ? "点击 + 从战术库添加" : "Tap + to add plays from your library"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                if let calls {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(GameCalls.groups(plays: plays, playbook: calls.playbook)) { group in
                            HStack(spacing: 6) {
                                if let kind = group.kind {
                                    Image(systemName: kind.icon).font(.caption2).foregroundStyle(kind.tint)
                                }
                                Text(group.title(chinese: isChinese).uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            ForEach(group.plays, id: \.self) { ref in
                                row(ref, index: plays.firstIndex(of: ref) ?? 0, reorders: false)
                            }
                        }
                    }
                    .padding(.bottom, 6)
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
            if let rules, !rules.wrappedValue.isEmpty {
                rulesList(rules)
            }
        }
        .filmGlass(.regular, in: .rect(cornerRadius: 16))
        .sheet(isPresented: $addingRule) {
            SessionRuleSheet(age: ruleAge, existing: rules?.wrappedValue ?? []) { rule in
                guard let rules else { return }
                withAnimation { rules.wrappedValue.append(rule) }
                onChange()
            }
        }
        .sheet(isPresented: $picking) {
            SessionPlayPicker(library: library, selected: plays) { chosen in
                guard chosen != plays else { return }
                withAnimation { plays = chosen }
                onChange()
            }
        }
        .sheet(item: $opened) { opened in
            NavigationStack {
                JournalPlayScreen(play: opened.play, teamId: teamId)
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
                Text(calls != nil ? (isChinese ? "战术口令" : "CALLS")
                     : rules != nil ? (isChinese ? "战术与规则" : "PLAYS & RULES")
                     : (isChinese ? "战术" : "PLAYS"))
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
                    .filmGlass(.regular, in: Capsule())
            }
            if canEdit, rules != nil {
                Menu {
                    Button { picking = true } label: {
                        Label(isChinese ? "添加战术" : "Add Plays", systemImage: "sportscourt")
                    }
                    .accessibilityIdentifier("plan.plays.add.play")
                    Button { addingRule = true } label: {
                        Label(isChinese ? "添加规则" : "Add a Rule", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("plan.plays.add.rule")
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .frame(width: 28, height: 28)
                        .filmGlass(.regular, in: Circle())
                        .foregroundStyle(color)
                }
                .accessibilityLabel(isChinese ? "添加战术或规则" : "Add plays or rules")
                .accessibilityIdentifier("plan.plays.add")
            } else if canEdit {
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
    private func rulesList(_ rules: Binding<[SessionRule]>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !plays.isEmpty { Divider().padding(.leading, 16) }
            Text(isChinese ? "规则" : "RULES")
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            ForEach(rules.wrappedValue) { rule in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.title).font(.body.weight(.medium))
                        if let detail = rule.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if canEdit {
                        Button(role: .destructive) {
                            withAnimation { rules.wrappedValue.removeAll { $0.id == rule.id } }
                            onChange()
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isChinese ? "移除规则" : "Remove rule")
                        .accessibilityIdentifier("plan.rule.remove")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.rule")
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func row(_ ref: SessionPlayRef, index: Int, reorders: Bool = true) -> some View {
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
                    if reorders, index > 0 {
                        Button { move(index, by: -1) } label: {
                            Label(isChinese ? "上移" : "Move Up", systemImage: "arrow.up")
                        }
                    }
                    if reorders, index < plays.count - 1 {
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


/// Adding a game rule to a class (27 Nov 2026): the coach's own words, a few
/// common constraints, or a rule option from the activity library — this
/// age's first.
struct SessionRuleSheet: View {
    let age: ActivityAge?
    let existing: [SessionRule]
    let onAdd: (SessionRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// Constraints a coach puts on a game, in the app's language.
    private var common: [String] {
        isChinese ? ["进攻3秒内出手", "不许运球", "不许抢断", "每人必须触球才能投篮", "只能用弱侧手运球", "投篮前至少传3次"]
                  : ["3-second offense", "No dribble", "No steals", "Everyone touches the ball before a shot",
                     "Weak hand only", "Three passes before a shot"]
    }

    private var libraryRules: [(ActivityAge, [LibraryActivity])] {
        let rules = ActivityLibrary.shared.items.filter(\.isRule)
        var ages = ActivityAge.allCases
        if let age, let i = ages.firstIndex(of: age) { ages.remove(at: i); ages.insert(age, at: 0) }
        return ages.compactMap { a in
            let list = rules.filter { $0.age == a }
            return list.isEmpty ? nil : (a, list)
        }
    }

    private func has(_ title: String) -> Bool { existing.contains { $0.title == title } }

    private func add(_ rule: SessionRule) {
        onAdd(rule)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(isChinese ? "写一条规则" : "Write a rule", text: $text)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(addTyped)
                            .accessibilityIdentifier("rule.field")
                        Button(isChinese ? "添加" : "Add", action: addTyped)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("rule.addTyped")
                    }
                }
                Section(isChinese ? "常用" : "Common") {
                    ForEach(common, id: \.self) { rule in
                        Button { add(SessionRule(text: rule)) } label: {
                            HStack {
                                Text(rule).foregroundStyle(.primary)
                                Spacer()
                                if has(rule) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(has(rule))
                        .accessibilityIdentifier("rule.common")
                    }
                }
                ForEach(libraryRules, id: \.0) { age, rules in
                    Section(isChinese ? "规则选项 · \(age.title)" : "Rule options · \(age.title)") {
                        ForEach(rules, id: \.key) { a in
                            Button { add(SessionRule(text: a.name, libraryKey: a.key)) } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.displayName).foregroundStyle(.primary)
                                        Text(a.localizedHowItRuns).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    if has(a.displayName) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                                }
                            }
                            .disabled(has(a.displayName))
                            .accessibilityIdentifier("rule.library")
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "添加规则" : "Add a Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func addTyped() {
        let rule = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return }
        add(SessionRule(text: rule))
    }
}
