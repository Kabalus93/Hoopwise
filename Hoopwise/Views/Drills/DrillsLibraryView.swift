import SwiftUI
import OSLog

/// The drills screen, built on the activity library (October 2026, Luther):
/// pick an AGE, a session BLOCK and an activity TYPE. "Personal" (was
/// "Mine", renamed November 2026 — Luther) lists every drill that is not from
/// the library: the coach's own and the ones Claude creates through the
/// connector (create_drill). Rule options live under the Game block
/// and are read from the library directly — they are not drills and never
/// reach session planning.
struct DrillsLibraryView: View {
    /// The SAME page as the session plan's Add Drill picker (Luther, November
    /// 2026: the picker had its own old categories and search). Each drill row
    /// gets an add button; the age starts at the session's.
    struct Pick {
        let title: String
        let initialAge: ActivityAge?
        let initialBlock: ActivityBlock
        /// "Find drills" for a neglected axis: drills strong on it, first.
        var attribute: DrillAttribute? = nil
        let isAdded: (UUID) -> Bool
        let add: (DrillItem) -> Void
        /// Added in this visit: a second tap takes it back.
        var canRemove: (UUID) -> Bool = { _ in false }
        var remove: (DrillItem) -> Void = { _ in }
    }

    var pick: Pick? = nil

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.macDrillSelect) private var macDrillSelect
    @Environment(\.macDrillSelectedId) private var macDrillSelectedId
    @State private var searchText = ""
    @State private var showingAddDrill = false
    // FILTERS (16 November 2026, Luther: "I still need to know which are ball
    // handling, passing or shooting … then optionally if I need to go by age
    // group then I can"; age "should be a filter that can be removed", and "a
    // way to order drills by different criteria"). SKILL first — the octagon's
    // eight axes; then Age, Block, Type and Source as removable filters; then
    // the order. Nothing is required: the page opens on every drill.

    /// "" = every age, else an ActivityAge raw value. The picker remembers its
    /// own apart from the page.
    @AppStorage private var ageChoice: String
    /// "" = every skill, else a DrillAttribute raw value.
    @AppStorage private var skillChoice: String
    @AppStorage private var sortChoice: String

    init(pick: Pick? = nil) {
        self.pick = pick
        let prefix = pick == nil ? "library" : "planPicker"
        _ageChoice = AppStorage(wrappedValue: "", pick == nil ? "library.ageFilter" : "planPicker.age")
        _skillChoice = AppStorage(wrappedValue: "", "\(prefix).skill")
        _sortChoice = AppStorage(wrappedValue: DrillSort.suggested.rawValue, "\(prefix).sort")
    }
    @AppStorage("library.includeEarlier") private var includeEarlier = false
    @State private var block: ActivityBlock?
    @State private var type: ActivityType?
    @State private var source: DrillOrigin = .all
    @State private var showGuidance = false
    @State private var openRule: LibraryActivity?
    /// Mac: Return in the search bar asks Claude for the closest drills in
    /// the whole library (DrillFinder); they show above the list.
    @State private var claudeQuery: String?
    @State private var claudeResult: DrillFinderResult?
    @State private var claudeAsking = false
    @State private var claudeProblem: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var currentCoachId: UUID { dataManager.loggedInCoachId ?? dataManager.coach.id }
    private var age: ActivityAge? { ActivityAge(rawValue: ageChoice) }
    private var skill: DrillAttribute? { DrillAttribute(rawValue: skillChoice) }
    private var sort: DrillSort { DrillSort(rawValue: sortChoice) ?? .suggested }
    /// The ages shown: the chosen one (with the earlier ones when that is
    /// switched on), else all.
    private var ages: [ActivityAge] {
        guard let age else { return ActivityAge.allCases }
        return includeEarlier ? age.upToHere : [age]
    }

    private var visibleDrills: [DrillItem] {
        dataManager.drills.filter { drill in
            // A series is a ladder of drills, not one to list or pick.
            guard !drill.isSeries else { return false }
            let visibilityTag = drill.tags.first(where: { $0.hasPrefix("visibility:") })
            let ownerTag = drill.tags.first(where: { $0.hasPrefix("owner:") })
            if visibilityTag == "visibility:private" {
                guard let ownerTag else { return false }
                return ownerTag == "owner:\(currentCoachId.uuidString)"
            }
            return true
        }
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }

    /// One drill in the list: a library activity, or a personal drill.
    private struct Entry: Identifiable {
        let drill: DrillItem
        let activity: LibraryActivity?
        /// Library order (age, block, then the library's own order).
        let order: Int
        var id: UUID { drill.id }
    }

    /// Library activities passing age, block and type — before skill.
    private var libraryPairs: [Entry] {
        guard source != .personal else { return [] }
        let byId = Dictionary(visibleDrills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ActivityLibrary.shared.plannable.enumerated().compactMap { index, activity in
            guard ages.contains(activity.age), block == nil || activity.block == block,
                  let drill = byId[activity.id] else { return nil }
            return Entry(drill: drill, activity: activity, order: index)
        }
    }

    /// Personal drills have no age or block, so those filters leave them out.
    private var personalEntries: [Entry] {
        guard source != .library, age == nil, block == nil, type == nil else { return [] }
        return visibleDrills.filter { !$0.isLibraryDrill && $0.trackedShooting == nil }.map { Entry(drill: $0, activity: nil, order: -1) }
    }

    /// The list: every filter, then the order.
    private var entries: [Entry] {
        var out = libraryPairs.filter { type == nil || $0.activity?.type == type } + personalEntries
        if let skill { out = out.filter { $0.drill.attributes[skill] >= 2 } }
        let name: (Entry) -> String = { $0.activity?.displayName ?? $0.drill.localizedName }
        switch sort {
        case .suggested:
            if let skill {
                out.sort { ($0.drill.attributes[skill], -$0.order) > ($1.drill.attributes[skill], -$1.order) }
            } else {
                out.sort { $0.order < $1.order }
            }
        case .name:
            out.sort { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        case .age:
            let rank: (Entry) -> Int = { e in e.activity.flatMap { ActivityAge.allCases.firstIndex(of: $0.age) } ?? 99 }
            out.sort { (rank($0), $0.order) < (rank($1), $1.order) }
        case .duration:
            out.sort { ($0.drill.durationMinutes, $0.order) < ($1.drill.durationMinutes, $1.order) }
        }
        return out
    }

    /// Rule options (not drills): under Game, or when chosen as the type.
    private var rules: [LibraryActivity] {
        guard skill == nil, source != .personal,
              type == .rules || (type == nil && block == .game) else { return [] }
        return ActivityLibrary.shared.items.filter { $0.isRule && ages.contains($0.age) }
    }

    /// The types among the drills the other filters leave, with counts.
    private var typeCounts: [(ActivityType, Int)] {
        var counts: [ActivityType: Int] = [:]
        for entry in libraryPairs {
            if let t = entry.activity?.type { counts[t, default: 0] += 1 }
        }
        if source != .personal, block == nil || block == .game {
            let ruleCount = ActivityLibrary.shared.items.filter { $0.isRule && ages.contains($0.age) }.count
            if ruleCount > 0 { counts[.rules] = ruleCount }
        }
        return ActivityType.allCases.compactMap { t in counts[t].map { (t, $0) } }
    }

    private var hasFilters: Bool { age != nil || block != nil || type != nil || source != .all || skill != nil }

    private func clearFilters() {
        ageChoice = ""
        skillChoice = ""
        block = nil
        type = nil
        source = .all
    }

    // MARK: Search — the WHOLE library, whatever age/block/type is chosen
    // (Luther, November 2026: searching only inside the selected category hid
    // drills he knew were there). Every typed word must appear somewhere in
    // the name, Chinese name, how it runs or instructions (DrillFinder.typedMatch).

    private var searchHits: [(activity: LibraryActivity, drill: DrillItem)] {
        let byId = Dictionary(visibleDrills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ActivityLibrary.shared.plannable.compactMap { activity in
            guard let drill = byId[activity.id],
                  DrillFinder.typedMatch(query, in: [drill.name, drill.localizedName, drill.description,
                                                     drill.localizedDescription, activity.nameZh ?? "",
                                                     activity.howItRunsZh ?? ""] + drill.instructions)
            else { return nil }
            return (activity, drill)
        }
    }

    private var personalHits: [DrillItem] {
        visibleDrills.filter { !$0.isLibraryDrill }
            .filter { DrillFinder.typedMatch(query, in: [$0.name, $0.localizedName, $0.description] + $0.instructions) }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    private var ruleHits: [LibraryActivity] {
        ActivityLibrary.shared.items.filter {
            $0.isRule && DrillFinder.typedMatch(query, in: [$0.name, $0.howItRuns, $0.nameZh ?? "", $0.howItRunsZh ?? ""])
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let hits = searchHits
        let personal = personalHits
        let ruleMatches = ruleHits
        if hits.isEmpty && personal.isEmpty && ruleMatches.isEmpty {
            #if targetEnvironment(macCatalyst)
            if !claudeAsking && claudeResult == nil {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
            #else
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
            #endif
        }
        if !personal.isEmpty {
            Section {
                ForEach(personal) { drill in
                    drillLink(drill) { DrillRow(drill: drill) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(drill) }
                }
            } header: {
                Text(isChinese ? "个人 · \(personal.count)" : "Personal · \(personal.count)")
            }
        }
        ForEach(ActivityAge.allCases) { a in
            let rows = hits.filter { $0.activity.age == a }
            if !rows.isEmpty {
                Section {
                    ForEach(rows, id: \.activity.key) { pair in
                        drillLink(pair.drill) {
                            LibraryRow(activity: pair.activity, drill: pair.drill, showAge: false, showBlock: true)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(pair.drill) }
                    }
                } header: {
                    Text("\(a.title) · \(rows.count)")
                }
            }
        }
        if !ruleMatches.isEmpty {
            Section {
                ForEach(ruleMatches) { rule in
                    Button { openRule = rule } label: { LibraryRuleRow(rule: rule, showAge: true) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("\(ActivityType.rules.title) · \(ruleMatches.count)")
            }
        }
    }

    /// A drill row: opens the drill; in the plan picker, an add button
    /// beside it (a check once it is in the section).
    @ViewBuilder
    private func drillLink<Label: View>(_ drill: DrillItem, @ViewBuilder label: () -> Label) -> some View {
        if let pick {
            let added = pick.isAdded(drill.id)
            let removable = added && pick.canRemove(drill.id)
            HStack(spacing: 10) {
                NavigationLink(destination: DrillDetailView(drill: drill).environment(\.drillSessionPick, pick)) { label() }
                Button {
                    if !added { pick.add(drill) } else if removable { pick.remove(drill) }
                } label: {
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(added ? Color.green : Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(added && !removable)
                .accessibilityLabel(added ? (isChinese ? "已添加" : "Added") : (isChinese ? "添加" : "Add"))
                .accessibilityIdentifier("drillPicker.add")
            }
        } else if let macDrillSelect {
            // The Mac: the drill opens beside the list.
            let on = macDrillSelectedId == drill.id
            Button { macDrillSelect(drill) } label: {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(on ? 0.12 : 0))
                        .padding(.horizontal, -10).padding(.vertical, -6))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            NavigationLink(destination: DrillDetailView(drill: drill)) { label() }
        }
    }

    // MARK: Filters — skill first, then removable filters and the order

    /// TRACKED SHOOTING (20 Nov 2026): the three built-in drills whose
    /// results are logged in the plan and kept on each athlete. Always at the
    /// top, in the plan picker too.
    @ViewBuilder
    private var trackedSection: some View {
        let tracked = ShootingDrill.allCases
            .compactMap { t in dataManager.drills.first { $0.id == t.drillId } }
            .filter { skill == nil || $0.attributes[skill!] >= 2 }
        if !tracked.isEmpty {
            Section {
                ForEach(tracked) { drill in
                    drillLink(drill) {
                        HStack(spacing: 12) {
                            Image(systemName: drill.trackedShooting?.symbol ?? "gauge.with.dots.needle.67percent")
                                .font(.title3)
                                .foregroundStyle(Color.orange)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drill.localizedName).font(.body.weight(.semibold))
                                Text(trackedSubtitle(drill))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("library.tracked")
                }
            } header: {
                Text(isChinese ? "投篮测试 · 自动记录" : "Tracked shooting")
            }
        }
        // The coach's own tracked drills (24 Nov 2026).
        let mine = visibleDrills
            .filter { $0.tracking != nil && $0.trackedShooting == nil }
            .filter { skill == nil || ($0.tracking?.weight(for: skill!) ?? 0) > 0 || $0.attributes[skill!] >= 2 }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
        if !mine.isEmpty {
            Section {
                ForEach(mine) { drill in
                    drillLink(drill) {
                        HStack(spacing: 12) {
                            Image(systemName: drill.tracking?.kind.symbol ?? "chart.bar.xaxis")
                                .font(.title3)
                                .foregroundStyle(Color.orange)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drill.localizedName).font(.body.weight(.semibold))
                                Text([drill.tracking?.kind == .other ? nil : drill.tracking?.kind.title(chinese: isChinese),
                                      drill.tracking?.summary(chinese: isChinese)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .accessibilityIdentifier("library.myTracked")
                }
            } header: {
                Text(isChinese ? "我的记录训练" : "My tracked drills")
            }
        }
    }

    private func trackedSubtitle(_ drill: DrillItem) -> String {
        guard let t = drill.trackedShooting else { return "" }
        let where_: String
        switch t.spotCount {
        case 5: where_ = isChinese ? "五个点" : "five spots"
        case 2: where_ = isChinese ? "\(t.spotName(0, chinese: true)) · \(t.spotName(1, chinese: true))"
                                   : "\(t.spotName(0, chinese: false).lowercased()) · \(t.spotName(1, chinese: false).lowercased())"
        default: where_ = isChinese ? "一个总数" : "one total"
        }
        return isChinese ? "记录命中 · \(where_)" : "Logs makes · \(where_)"
    }

    /// Series (18 Nov 2026): ladders of drills, easiest first — their own
    /// page; they are not listed as drills.
    private var seriesEntry: some View {
        let count = DrillSeries.all(in: dataManager.drills).count
        return Section {
            NavigationLink(destination: DrillSeriesListView()) {
                Label {
                    HStack {
                        Text(isChinese ? "训练系列" : "Series")
                        Spacer()
                        Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "stairs").foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityIdentifier("library.series")
        }
    }

    private var filterSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                skillChips
                filterPills
                // The switch lives in the ⓘ sheet; while it is on, say so here
                // so the list is never filtered by something out of sight.
                if includeEarlier, let age, age != .u6 {
                    earlierAgesNote(age).padding(.horizontal, 20)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// All skills, then the octagon's eight.
    private var skillChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(isChinese ? "全部技能" : "All skills", selected: skill == nil) { skillChoice = "" }
                    .accessibilityIdentifier("library.skill.all")
                ForEach(DrillAttribute.allCases) { axis in
                    chip(axis.title, selected: skill == axis, icon: axis.icon) {
                        skillChoice = skill == axis ? "" : axis.rawValue
                    }
                    .accessibilityIdentifier("library.skill.\(axis.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
        .sensoryFeedback(.selection, trigger: skillChoice)
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill(age?.title ?? (isChinese ? "年龄" : "Age"), active: age != nil,
                     clear: { ageChoice = "" }, id: "library.filter.age") {
                    Picker(isChinese ? "年龄" : "Age", selection: $ageChoice) {
                        Text(isChinese ? "所有年龄" : "Any age").tag("")
                        ForEach(ActivityAge.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                pill(block?.title ?? (isChinese ? "环节" : "Block"), active: block != nil,
                     clear: { block = nil }, id: "library.filter.block") {
                    Picker(isChinese ? "环节" : "Block", selection: $block) {
                        Text(isChinese ? "所有环节" : "Any block").tag(ActivityBlock?.none)
                        ForEach(ActivityBlock.allCases) { Text($0.title).tag(ActivityBlock?.some($0)) }
                    }
                }
                if typeCounts.count > 1 || type != nil {
                    pill(type?.title ?? (isChinese ? "类型" : "Type"), active: type != nil,
                         clear: { type = nil }, id: "library.filter.type") {
                        Picker(isChinese ? "类型" : "Type", selection: $type) {
                            Text(isChinese ? "所有类型" : "Any type").tag(ActivityType?.none)
                            ForEach(typeCounts, id: \.0) { t, count in
                                Text("\(t.title) · \(count)").tag(ActivityType?.some(t))
                            }
                        }
                    }
                }
                pill(source == .all ? (isChinese ? "来源" : "Source") : source.title(isChinese), active: source != .all,
                     clear: { source = .all }, id: "library.filter.source") {
                    Picker(isChinese ? "来源" : "Source", selection: $source) {
                        ForEach(DrillOrigin.allCases, id: \.self) { Text($0.title(isChinese)).tag($0) }
                    }
                }
                pill((isChinese ? "排序：" : "Sort: ") + sort.title(isChinese, skill: skill), active: false,
                     clear: nil, id: "library.sort") {
                    Picker(isChinese ? "排序" : "Sort", selection: $sortChoice) {
                        ForEach(DrillSort.allCases, id: \.self) { Text($0.title(isChinese, skill: skill)).tag($0.rawValue) }
                    }
                }
                if hasFilters {
                    Button(isChinese ? "全部清除" : "Clear all") { withAnimation(.snappy) { clearFilters() } }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                        .accessibilityIdentifier("library.filter.clear")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// A filter: its value in a capsule that opens its menu, filled when set,
    /// with an ✕ that removes it.
    private func pill<Choices: View>(_ title: String, active: Bool, clear: (() -> Void)?, id: String,
                                     @ViewBuilder choices: () -> Choices) -> some View {
        HStack(spacing: 6) {
            Menu {
                choices()
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier(id)
            if active, let clear {
                Button(action: { withAnimation(.snappy) { clear() } }) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isChinese ? "移除 \(title)" : "Remove \(title)")
                .accessibilityIdentifier("\(id).clear")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(active ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .background(Capsule().fill(active ? Color.accentColor : Color.filmCard))
    }

    // MARK: The list

    @ViewBuilder
    private var drillList: some View {
        let list = entries
        if list.isEmpty && rules.isEmpty {
            Section {
                VStack(spacing: 10) {
                    Text(isChinese ? "没有符合这些筛选条件的训练" : "No drills match these filters")
                        .foregroundStyle(.secondary)
                    if hasFilters {
                        Button(isChinese ? "清除筛选" : "Clear filters") { clearFilters() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        if sort == .age, age == nil, !list.isEmpty {
            ForEach(ActivityAge.allCases) { a in
                let rows = list.filter { $0.activity?.age == a }
                if !rows.isEmpty {
                    Section { ForEach(rows) { entryRow($0) } } header: { Text("\(a.title) · \(rows.count)") }
                }
            }
            let personal = list.filter { $0.activity == nil }
            if !personal.isEmpty {
                Section { ForEach(personal) { entryRow($0) } } header: {
                    Text(isChinese ? "个人 · \(personal.count)" : "Personal · \(personal.count)")
                }
            }
        } else if !list.isEmpty {
            Section {
                ForEach(list) { entryRow($0) }
            } header: {
                Text(listTitle(list.count))
            } footer: {
                if skill != nil {
                    Text(isChinese ? "●●● 主要练习 · ●●○ 有练到" : "●●● main focus · ●●○ worked")
                }
            }
        }
        if !rules.isEmpty {
            Section {
                ForEach(rules) { rule in
                    Button { openRule = rule } label: {
                        LibraryRuleRow(rule: rule, showAge: age == nil || includeEarlier)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(ActivityType.rules.title)
            } footer: {
                Text(isChinese ? "规则选项不是训练，不会出现在课程计划中。"
                               : "Rule options are not drills and don't appear in session planning.")
            }
        }
    }

    private func listTitle(_ count: Int) -> String {
        if let skill {
            return isChinese ? "擅长\(skill.title) · \(count)" : "Strong on \(skill.title.lowercased()) · \(count)"
        }
        if let type { return "\(type.title) · \(count)" }
        if let block { return "\(block.title) · \(count)" }
        return isChinese ? "训练 · \(count)" : "Drills · \(count)"
    }

    private func entryRow(_ entry: Entry) -> some View {
        drillLink(entry.drill) {
            HStack(spacing: 8) {
                if let activity = entry.activity {
                    LibraryRow(activity: activity, drill: entry.drill,
                               showAge: age == nil || includeEarlier, showBlock: block == nil)
                } else {
                    DrillRow(drill: entry.drill)
                }
                if let skill {
                    SkillDots(score: entry.drill.attributes[skill])
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(entry.drill) }
    }

    var body: some View {
        List {
            // One Group so every row takes the Mac's pane (nil = the
            // system's own row background everywhere else).
            Group {
            #if targetEnvironment(macCatalyst)
            claudeSection
            #endif
            if isSearching {
                searchResults
            } else {
                filterSection
                trackedSection
                if pick == nil { seriesEntry }
                drillList
            }
            }
            .filmRoomListRow()
        }
        .listStyle(.insetGrouped)
        .filmRoomList()
        // The filters sit right on top of the list (Luther, November 2026:
        // there was a section gap between ages, blocks and the list).
        .listSectionSpacing(.compact)
        .onMacMenu(.newDrill) { if pick == nil { showingAddDrill = true } }
        // On the Mac the sidebar calls this place Drills; the page says the same.
        .navigationTitle(pick?.title ?? (FilmRoom.isOn ? (isChinese ? "训练" : "Drills")
                                         : (isChinese ? "训练库" : "Activity library")))
        .searchable(text: $searchText, prompt: isChinese ? "搜索全部训练" : "Search all drills")
        #if targetEnvironment(macCatalyst)
        // Typing filters as before; Return asks Claude about the whole library.
        .onSubmit(of: .search) { askClaude() }
        .onChange(of: searchText) { _, text in
            if text.trimmingCharacters(in: .whitespacesAndNewlines) != claudeQuery { clearClaude() }
        }
        #endif
        .onAppear {
            guard let pick else { return }
            if let age = pick.initialAge { ageChoice = age.rawValue }
            if let axis = pick.attribute {
                // "Find drills" for a neglected axis: strong on it, any block.
                skillChoice = axis.rawValue
                block = nil
            } else {
                block = pick.initialBlock
            }
        }
        #if DEBUG
        // HOOPWISE_LIBRARY_SEARCH=<text>: open with that search typed.
        // HOOPWISE_DELETE_DRILLS_NAMED=<name>: UI tests clean up the drills
        // they created — demo store only.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let text = env["HOOPWISE_LIBRARY_SEARCH"] ?? (pick != nil ? env["HOOPWISE_DRILLPICKER_SEARCH"] : nil) { searchText = text }
            if let name = env["HOOPWISE_DELETE_DRILLS_NAMED"], ScreenshotStore.isActive {
                for drill in dataManager.drills where drill.name == name { dataManager.deleteDrill(drill) }
            }
        }
        #endif
        .onChange(of: block) { _, _ in type = nil }
        .onChange(of: ageChoice) { _, _ in type = nil }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Guidance is read now and then, not every visit: it lives
                // behind ⓘ rather than taking the top of the list.
                if age != nil {
                    Button { showGuidance = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(isChinese ? "年龄段指引" : "Age guidance")
                        .accessibilityIdentifier("library.info")
                }
            }
            if pick == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddDrill = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(DrillLocalization.L("Add Drill"))
                }
            }
        }
        .sheet(isPresented: $showingAddDrill) {
            AddEditDrillSheet(drill: nil).environmentObject(dataManager)
        }
        .sheet(isPresented: $showGuidance) {
            if let age {
                LibraryGuidanceSheet(age: age, includeEarlier: $includeEarlier)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $openRule) { rule in
            LibraryRuleSheet(rule: rule)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Claude suggestions (Mac)

    #if targetEnvironment(macCatalyst)
    /// Every drill the finder may return: library activities the store has and
    /// personal drills.
    private var finderEntries: [DrillFinderEntry] { DrillFinder.entries(for: visibleDrills) }

    private func clearClaude() {
        claudeQuery = nil
        claudeResult = nil
        claudeProblem = nil
    }

    private func askClaude() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, !claudeAsking else { return }
        let entries = finderEntries
        let chinese = isChinese
        claudeQuery = text
        claudeResult = nil
        claudeProblem = nil
        claudeAsking = true
        Task {
            defer { claudeAsking = false }
            var result: DrillFinderResult?
            if let key = AnthropicKeyStore.key {
                do {
                    result = try await DrillFinder.askClaude(description: text, entries: entries, chinese: chinese, key: key)
                } catch {
                    claudeProblem = (chinese ? "Claude 暂时无法回答，以下为本机查找结果。" : "Claude couldn't answer, so this Mac searched instead. ")
                        + error.localizedDescription
                }
            }
            // A newer search (or a cleared field) wins over a slow answer.
            guard claudeQuery == text else { return }
            claudeResult = result ?? DrillFinder.rankOnDevice(text, entries: entries)
        }
    }

    @ViewBuilder
    private var claudeSection: some View {
        if claudeAsking || claudeResult != nil {
            Section {
                if claudeAsking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(isChinese ? "Claude 正在查找整个训练库…" : "Claude is looking through the whole library…")
                            .foregroundStyle(.secondary)
                    }
                } else if let result = claudeResult {
                    if result.matches.isEmpty {
                        Text(isChinese ? "没有找到相近的训练。" : "No drill comes close.").foregroundStyle(.secondary)
                    }
                    ForEach(result.matches, id: \.drillId) { match in
                        if let drill = visibleDrills.first(where: { $0.id == match.drillId }) {
                            drillLink(drill) { suggestionRow(drill, why: match.why) }
                                .accessibilityIdentifier("library.suggestion")
                        }
                    }
                }
            } header: {
                Text(claudeResult?.source == .onDevice
                     ? (isChinese ? "最接近的训练 · 本机" : "Closest drills · on this Mac")
                     : (isChinese ? "Claude 推荐" : "Claude suggests"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let note = claudeResult?.note, !note.isEmpty { Text(note) }
                    if let claudeProblem { Text(claudeProblem).foregroundStyle(.orange) }
                    if claudeResult?.source == .onDevice && AnthropicKeyStore.key == nil {
                        Text(isChinese ? "在「个人资料 → App 中的 Claude」加入 API 密钥，按玩法描述也能找到训练。"
                                       : "Add an API key in Profile → Claude in the app to find drills by how they work.")
                    }
                }
            }
        }
    }

    private func suggestionRow(_ drill: DrillItem, why: String) -> some View {
        let activity = ActivityLibrary.shared.items.first { $0.id == drill.id }
        let place = activity.map { "\($0.age.title) · \($0.block.title) · \($0.type.title)" } ?? (isChinese ? "个人" : "Personal")
        return VStack(alignment: .leading, spacing: 3) {
            Text(activity?.displayName ?? drill.localizedName).font(.body.weight(.semibold))
            Text(place).font(.caption).foregroundStyle(.secondary)
            if !why.isEmpty { Text(why).font(.subheadline).foregroundStyle(.primary.opacity(0.85)) }
        }
        .padding(.vertical, 2)
    }
    #endif

    private func chip(_ title: String, selected: Bool, icon: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? Color.accentColor : Color.filmCard))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func earlierAgesNote(_ age: ActivityAge) -> some View {
        let earlier = age.upToHere.dropLast().map(\.rawValue)
        return HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up").font(.caption2)
            Text(isChinese ? "含 \(earlier.joined(separator: "、"))" : "Including \(earlier.joined(separator: ", "))")
                .font(.caption)
            Spacer()
            Button(isChinese ? "关闭" : "Turn off") { includeEarlier = false }
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("library.earlierNote")
    }

    private func favoriteButton(_ drill: DrillItem) -> some View {
        Button {
            dataManager.toggleDrillFavorite(drill)
        } label: {
            Label(drill.isFavorite ? DrillLocalization.L("Unfavorite") : DrillLocalization.L("Favorite"),
                  systemImage: drill.isFavorite ? "heart.slash" : "heart")
        }
        .tint(.pink)
    }
}

/// Where drills come from.
enum DrillOrigin: String, CaseIterable {
    case all, library, personal

    func title(_ zh: Bool) -> String {
        switch self {
        case .all: zh ? "全部" : "All drills"
        case .library: zh ? "训练库" : "Library"
        case .personal: zh ? "个人" : "Personal"
        }
    }
}

/// How the drills page orders its list.
enum DrillSort: String, CaseIterable {
    /// Library order; with a skill chosen, strongest on it first.
    case suggested, name, age, duration

    func title(_ zh: Bool, skill: DrillAttribute?) -> String {
        switch self {
        case .suggested: skill == nil ? (zh ? "推荐" : "Suggested") : (zh ? "最擅长" : "Strongest")
        case .name: zh ? "名称" : "Name"
        case .age: zh ? "年龄" : "Age"
        case .duration: zh ? "时长" : "Duration"
        }
    }
}

/// How much a drill works the chosen skill: ●●○ worked, ●●● main.
private struct SkillDots: View {
    let score: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < score ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(score) of 3")
    }
}

// MARK: - Library rows

private struct LibraryRow: View {
    let activity: LibraryActivity
    let drill: DrillItem
    let showAge: Bool
    /// Search results span every block, so they say which one.
    var showBlock = false

    private var leadingMedia: DrillMedia? { drill.media.min(by: { $0.sortOrder < $1.sortOrder }) }

    var body: some View {
        HStack(spacing: 12) {
            if let media = leadingMedia {
                DrillMediaThumb(media: media, size: 40, cornerRadius: 8)
            } else {
                Image(systemName: activity.type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(drill.localizedName)
                        .font(.body)
                        .lineLimit(2)
                    DrillPreferenceMark(preference: drill.preference)
                }
                Text([showAge ? activity.age.rawValue : nil, showBlock ? activity.block.title : nil,
                      activity.type.title, showBlock ? nil : activity.sourceText]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if drill.isFavorite {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("library.row")
        .filmRoomDraggable(.drill(drill.id), title: drill.localizedName, symbol: "cone")
    }
}

private struct LibraryRuleRow: View {
    let rule: LibraryActivity
    let showAge: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ActivityType.rules.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName).font(.body)
                Text(rule.localizedHowItRuns)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if showAge {
                    Text(rule.age.rawValue).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .accessibilityIdentifier("library.rule")
    }
}

/// A rule option: what it does and where it comes from. Read-only.
private struct LibraryRuleSheet: View {
    let rule: LibraryActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LibraryBadges(activity: rule)
                    Text(rule.localizedHowItRuns).font(.body)
                    LibrarySourceView(activity: rule)
                }
                .padding(20)
            }
            .navigationTitle(rule.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DrillLocalization.L("Done")) { dismiss() }
                }
            }
        }
    }
}

/// Age · block · type, as small chips.
struct LibraryBadges: View {
    let activity: LibraryActivity
    var body: some View {
        HStack(spacing: 6) {
            badge(activity.age.title, accent: true)
            badge(activity.block.title)
            badge(activity.type.title)
        }
    }
    private func badge(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
            .background(Capsule().fill(accent ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill)))
    }
}

/// "Source" with the citation and, when there is one, the link.
struct LibrarySourceView: View {
    let activity: LibraryActivity
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isChinese ? "来源" : "Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let urlString = activity.sourceUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(activity.sourceText).multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
            } else {
                Text(activity.sourceText).font(.subheadline)
            }
            // The FIBA Chinese edition's own name, when the title above
            // improves on it — so the page can still be found in that book.
            if isChinese, let fiba = activity.fibaNameZh, fiba != activity.nameZh {
                Text("FIBA 中文版：\(fiba)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The age's guidance, plus the switch that adds younger ages to the list.
private struct LibraryGuidanceSheet: View {
    let age: ActivityAge
    @Binding var includeEarlier: Bool
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            List {
                if age != .u6 {
                    Section {
                        Toggle(isOn: $includeEarlier) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isChinese ? "包含更低年龄段" : "Include earlier ages")
                                Text(isChinese ? "每个年龄段在前一个的基础上增加" : "Each age adds to the ones before it")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("library.includeEarlier")
                    }
                }
                if let tab = ActivityLibrary.shared.tab(age) {
                    Section {
                        ForEach(Array(tab.localizedGuidance.enumerated()), id: \.offset) { _, line in
                            Text(LocalizedStringKey(line))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text(isChinese ? "指引" : "Guidance")
                    }
                }
            }
            .navigationTitle(isChinese ? "\(age.title) 指引" : "\(age.title) guidance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DrillLocalization.L("Done")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Category Chip
private struct CategoryChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drill Row
private struct DrillRow: View {
    let drill: DrillItem

    /// Lead with the first media thumbnail when present; otherwise the
    /// category icon. Makes scanning the library massively faster — a
    /// photo or court diagram is recognized instantly.
    private var leadingMedia: DrillMedia? {
        drill.media.min(by: { $0.sortOrder < $1.sortOrder })
    }

    var body: some View {
        HStack(spacing: 12) {
            if let media = leadingMedia {
                DrillMediaThumb(media: media, size: 44, cornerRadius: 8)
            } else {
                Image(systemName: drill.category.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.drillCategoryColor(drill.category))
                    .frame(width: 44, height: 44)
                    .background(Color.drillCategoryColor(drill.category).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(drill.localizedName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    DrillPreferenceMark(preference: drill.preference)
                }
                HStack(spacing: 6) {
                    Text("\(drill.localizedCategory) · \(drill.durationMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if drill.media.count > 1 {
                        Label("\(drill.media.count)", systemImage: "photo.stack")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            if drill.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Drill Detail View (Enhanced)
/// The plan picker the drill page was opened from (nil elsewhere): the page
/// then has an add-to-session button beside Edit and Favourite (23 Nov 2026).
private struct DrillSessionPickKey: EnvironmentKey {
    static let defaultValue: DrillsLibraryView.Pick? = nil
}

extension EnvironmentValues {
    var drillSessionPick: DrillsLibraryView.Pick? {
        get { self[DrillSessionPickKey.self] }
        set { self[DrillSessionPickKey.self] = newValue }
    }
}

struct DrillDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.drillSessionPick) private var sessionPick
    /// Flips the add button at once (the picker's own state is behind this page).
    @State private var addedHere: Bool?
    let drill: DrillItem
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    /// The Plays editor on a drill drawing (new, or one being edited) —
    /// "Add a visual" opens it directly (Luther, November 2026: the photo /
    /// video / link menu is gone).
    @State private var drawingEditor: DrawingEdit?
    @State private var showingMediaEditor = false
    @State private var viewerInitialIndex: Int?
    @State private var editingDiagram: DrillMedia?
    @Environment(\.dismiss) private var dismiss
    
    // Inline editing state
    @State private var editingDescription = false
    @State private var editedDescription = ""
    @State private var editingInstructions = false
    @State private var editedInstructions: [String] = []
    @State private var newInstruction = ""
    @State private var editingKeyPoints = false
    @State private var editedKeyPoints: [String] = []
    @State private var newKeyPoint = ""
    @FocusState private var focusedField: InlineEditField?
    
    private struct DrawingEdit: Identifiable {
        let id = UUID()
        var existing: DrillMedia?
        var drawing: DrillDrawing
    }

    /// Opens the editor on a new drawing.
    private func drawNew() {
        drawingEditor = DrawingEdit(existing: nil, drawing: .new())
    }

    /// A drawn visual opens in the editor; a legacy PencilKit diagram in
    /// its old editor. Nil when `item` is not a diagram.
    private func edit(diagram item: DrillMedia) {
        if let drawing = DrillDrawingMedia.drawing(for: item) {
            drawingEditor = DrawingEdit(existing: item, drawing: drawing)
        } else if item.kind == .courtDiagram {
            editingDiagram = item
        }
    }

    private func saveDrawing(_ drawing: DrillDrawing, existing: DrillMedia?) {
        let drill = currentDrill
        guard let media = DrillDrawingMedia.save(drawing, drillId: drill.id, existing: existing,
                                                 sortOrder: (drill.media.map(\.sortOrder).max() ?? -1) + 1) else { return }
        if existing == nil {
            dataManager.addDrillMedia(media, toDrillId: drill.id)
        } else {
            dataManager.updateDrillMedia(media)
        }
        HapticFeedback.notification(.success)
    }

    /// Wrapper that lets us drive `fullScreenCover(item:)` from an `Int?`
    /// state — the cover needs an Identifiable, an Int alone won't do.
    private struct IdentifiedIndex: Identifiable, Hashable {
        let value: Int
        var id: Int { value }
    }

    private enum InlineEditField: Hashable {
        case description
        case instruction(Int)
        case newInstruction
        case keyPoint(Int)
        case newKeyPoint
    }
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var categoryColor: Color {
        Color.drillCategoryColor(drill.category)
    }
    
    private var currentDrill: DrillItem {
        dataManager.drills.first(where: { $0.id == drill.id }) ?? drill
    }

    private var userFacingTags: [String] {
        currentDrill.tags
            .filter { !$0.hasPrefix("visibility:") }
            .filter { !$0.hasPrefix("owner:") }
            .filter { $0 != "quick-note" } // Hide internal tag
            .filter { $0 != ActivityLibrary.tag && !$0.hasPrefix("library:") && !$0.hasPrefix("block:")
                && !$0.hasPrefix("type:") && !$0.hasPrefix("kind:") }  // library bookkeeping
            // The skill ratings (attr:<axis>=n, attr:by:coach — shown on the
            // octagon card) and who made it (by:claude) are bookkeeping too
            // (18 Nov 2026, Luther: "what are those tags???").
            .filter { !$0.hasPrefix(AttributeProfile.tagPrefix) && !$0.hasPrefix("by:") && !$0.hasPrefix(DrillItem.preferencePrefix)
                && !$0.hasPrefix(DrillItem.trackPrefix) }
            .map { raw in
                raw.replacingOccurrences(of: "-", with: " ")
                   .replacingOccurrences(of: "_", with: " ")
                   .capitalized
            }
    }
    
    private var suggestedTags: [String] {
        var tags: [String] = []
        // Suggest based on category
        switch currentDrill.category {
        case .warmup: tags.append(contentsOf: ["Warm-up", "Stretching", "Mobility"])
        case .shooting: tags.append(contentsOf: ["Shooting", "Form", "Accuracy"])
        case .skills: tags.append(contentsOf: ["Ball Handling", "Footwork", "Fundamentals"])
        case .offense: tags.append(contentsOf: ["Offense", "Plays", "Movement"])
        case .defense: tags.append(contentsOf: ["Defense", "Positioning", "Pressure"])
        case .conditioning: tags.append(contentsOf: ["Conditioning", "Cardio", "Agility"])
        case .cooldown: tags.append(contentsOf: ["Cool-down", "Recovery", "Stretching"])
        }
        return tags.filter { !userFacingTags.contains($0) }
    }

    private var visibilityLabel: String? {
        if currentDrill.tags.contains("visibility:private") {
            return isChinese ? "私有" : "Private"
        }
        if currentDrill.tags.contains("visibility:shared") {
            return isChinese ? "共享" : "Shared"
        }
        return nil
    }

    private var isQuickNoteDrill: Bool {
        currentDrill.tags.contains("quick-note")
    }
    
    private var completionProgress: (filled: Int, total: Int) {
        var filled = 1 // name always filled
        let total = 5 // name, description, instructions, keyPoints, tags
        if !currentDrill.description.isEmpty { filled += 1 }
        if !currentDrill.instructions.isEmpty { filled += 1 }
        if !currentDrill.keyPoints.isEmpty { filled += 1 }
        if !userFacingTags.isEmpty { filled += 1 }
        return (filled, total)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Compact Hero Header
                    heroHeader

                    // Media visuals — empty-state CTA when none, carousel when present.
                    mediaSection
                        .padding(.top, 14)

                    // Content
                    VStack(spacing: 16) {
                        // Age, block, type, minutes and players are in the
                        // hero; a quick note still shows how complete it is.
                        if isQuickNoteDrill { quickInfoChips }

                        // Activity library: the source.
                        if let activity = currentDrill.libraryActivity {
                            LibrarySourceView(activity: activity)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Description (with placeholder for empty)
                        descriptionSection

                        // What it develops: the eight-axis octagon (November
                        // 2026); the coach's Adjust wins over Claude's rating.
                        // The series this drill is a level of (18 Nov 2026).
                        DrillSeriesCard(drillId: currentDrill.id)

                        DrillAttributesCard(drill: currentDrill, onSave: { profile in
                            var updated = currentDrill
                            updated.tags = profile.replacing(in: updated.tags, byCoach: true)
                            dataManager.updateDrill(updated)
                        }, onReset: {
                            var updated = currentDrill
                            updated.tags = updated.tags.filter { !$0.hasPrefix(AttributeProfile.tagPrefix) }
                            dataManager.updateDrill(updated)
                        })

                        // How the plan engine should use it (19 Nov 2026).
                        DrillPreferenceCard(drill: currentDrill)

                        // The coach's tracking (23 Nov 2026).
                        if let tracking = currentDrill.tracking {
                            DrillTrackingCard(tracking: tracking)
                        }
                        
                        // Instructions (with placeholder for empty)
                        instructionsSection
                        
                        // Key Points (with placeholder for empty)
                        keyPointsSection
                        
                        // Tags (with suggestions for empty)
                        tagsSection
                        
                        // Equipment (only if has content)
                        if !currentDrill.equipmentNeeded.isEmpty {
                            equipmentSection
                        }
                        
                        // Variations (only if has content)
                        if !currentDrill.variations.isEmpty {
                            variationsSection
                        }
                        
                        Spacer(minLength: isQuickNoteDrill ? 100 : 40)
                    }
                    .padding(.horizontal, AppTheme.spacing)
                    .padding(.top, 16)
                }
            }
            
            // Quick actions footer for quick-note drills
            if isQuickNoteDrill {
                quickActionsFooter
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .modifier(FilmRoomDestination())
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                HStack(spacing: 12) {
                    Button(action: {
                        showEditSheet = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Button(action: {
                        HapticFeedback.impact(.light)
                        dataManager.toggleDrillFavorite(currentDrill)
                    }) {
                        Image(systemName: currentDrill.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(currentDrill.isFavorite ? .red : AppTheme.textSecondary)
                    }

                    if let sessionPick {
                        let added = addedHere ?? sessionPick.isAdded(currentDrill.id)
                        Button {
                            HapticFeedback.impact(.light)
                            if added {
                                if sessionPick.canRemove(currentDrill.id) || addedHere == true {
                                    sessionPick.remove(currentDrill); addedHere = false
                                }
                            } else {
                                sessionPick.add(currentDrill); addedHere = true
                            }
                        } label: {
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(added ? .green : .accentColor)
                        }
                        .accessibilityLabel(added ? (LocalizationManager.shared.currentLanguage == .chinese ? "已在本节课" : "In the session")
                                                  : (LocalizationManager.shared.currentLanguage == .chinese ? "加入本节课" : "Add to session"))
                        .accessibilityIdentifier("drill.addToSession")
                    }
                }
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showEditSheet) {
            AddEditDrillSheet(drill: currentDrill)
                .environmentObject(dataManager)
        }
        .fullScreenCover(item: $drawingEditor) { edit in
            // The Coach board's editor (19 Nov 2026, Luther).
            DrillDrawingEditor(drawing: edit.drawing) { drawing in
                saveDrawing(drawing, existing: edit.existing)
            }
        }
        .sheet(isPresented: $showingMediaEditor) {
            DrillMediaEditorSheet(
                drillId: currentDrill.id,
                media: currentDrill.media
            )
            .environmentObject(dataManager)
        }
        #if os(iOS)
        .fullScreenCover(item: $editingDiagram) { existing in
            CourtDiagramEditor(mode: .edit(existing: existing)) { updated in
                dataManager.updateDrillMedia(updated)
            }
        }
        #endif
        .fullScreenCover(item: Binding(
            get: { viewerInitialIndex.map(IdentifiedIndex.init) },
            set: { viewerInitialIndex = $0?.value }
        )) { wrapper in
            DrillMediaViewer(media: DrillDrawingMedia.viewerMedia(currentDrill.media), initialIndex: wrapper.value)
        }
        .alert(isChinese ? "删除训练" : "Delete Drill", isPresented: $showDeleteConfirm) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                dataManager.deleteDrill(currentDrill)
                dismiss()
            }
        } message: {
            Text(isChinese ? "确定要删除这个训练吗？" : "Are you sure you want to delete this drill?")
        }
        #endif
    }

    // MARK: - Media Section
    /// Empty drill → tappable CTA strip. Drill with media → titled carousel
    /// with a trailing "+ add" tile and tap-to-open full-screen viewer.
    @ViewBuilder
    private var mediaSection: some View {
        let media = currentDrill.media.sorted { $0.sortOrder < $1.sortOrder }
        // Drawings play in place (every step); photos, videos and links stay
        // in the carousel.
        let drawn = media.compactMap { item in DrillDrawingMedia.drawing(for: item).map { (item, $0) } }
        let others = media.filter { item in !drawn.contains { $0.0.id == item.id } }
        if media.isEmpty {
            Button {
                HapticFeedback.impact(.light)
                drawNew()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.accent)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "添加图示" : "Add a visual")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(isChinese
                             ? "在球场上画出球员、防守人、标志桶和路线"
                             : "Draw it on the court — players, defenders, cones and lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.filmCard,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drill.addVisual")
            .padding(.horizontal, AppTheme.spacing)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(isChinese ? "图示" : "Visuals")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(media.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if others.isEmpty {
                        Button {
                            HapticFeedback.impact(.light)
                            drawNew()
                        } label: {
                            Label(isChinese ? "添加" : "Add", systemImage: "plus")
                                .visualControlLabel()
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("drill.visual.add")
                    }
                    // Order, captions and deleting, for two or more visuals;
                    // a drawing's own Edit is on the drawing (one "Edit" only).
                    if media.count > 1 {
                        Button {
                            HapticFeedback.impact(.light)
                            showingMediaEditor = true
                        } label: {
                            Label(isChinese ? "排序" : "Reorder", systemImage: "arrow.up.arrow.down")
                                .visualControlLabel()
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("drill.visual.reorder")
                    }
                }
                .padding(.horizontal, AppTheme.spacing)

                DrillDrawingsView(
                    drawings: drawn.map { (media: $0.0, drawing: $0.1) },
                    onEdit: { item in
                        HapticFeedback.impact(.light)
                        edit(diagram: item)
                    },
                    onDelete: { item in
                        HapticFeedback.impact(.medium)
                        dataManager.deleteDrillMedia(item)
                    },
                    onRename: { item, name in
                        var renamed = item
                        renamed.caption = name.isEmpty ? nil : name
                        dataManager.updateDrillMedia(renamed)
                    }
                )
                .padding(.horizontal, AppTheme.spacing)

                if !others.isEmpty {
                    DrillMediaCarousel(
                        media: others,
                        tileSize: 132,
                        horizontalPadding: AppTheme.spacing,
                        onTap: { item, _ in
                            HapticFeedback.impact(.light)
                            viewerInitialIndex = DrillDrawingMedia.viewerMedia(media).firstIndex { $0.id == item.id }
                        },
                        onAdd: {
                            HapticFeedback.impact(.light)
                            drawNew()
                        },
                        onDelete: { item in
                            HapticFeedback.impact(.medium)
                            dataManager.deleteDrillMedia(item)
                        },
                        onEditDiagram: { item in
                            HapticFeedback.impact(.light)
                            edit(diagram: item)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Hero
    /// The drill's hero (14 Nov 2026, Luther: the header "is awkward … make
    /// the page more fitting to the app and designed with purpose"). The
    /// session page's language: a card in the drill's BLOCK colour with that
    /// block's court drawn in code, the facts as caps + title + glass pills.
    /// A library drill's legacy category and difficulty are guesses, so they
    /// are not shown; a personal drill keeps its category and difficulty.
    private var heroHeader: some View {
        let activity = currentDrill.libraryActivity
        let zhName = activity?.nameZh.flatMap { $0 != currentDrill.localizedName ? $0 : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(heroEyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            Text(currentDrill.localizedName)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let zhName {
                Text(zhName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            FlowLayout(spacing: 8) {
                if let activity {
                    heroPill(icon: activity.type.icon, activity.type.title)
                } else {
                    heroPill(icon: drill.category.icon, currentDrill.localizedCategory)
                }
                heroPill(icon: "clock", currentDrill.localizedDuration)
                heroPill(icon: "person.2", currentDrill.localizedPlayerRange)
                if activity == nil {
                    heroPill(icon: "chart.bar", currentDrill.localizedDifficulty)
                }
                if let visibilityLabel {
                    heroPill(icon: "eye", visibilityLabel)
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .bottomLeading)
        .background {
            ZStack {
                CardCourtBackground(color: heroColor, style: heroCourt)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, AppTheme.spacing)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drill.hero")
    }

    /// "U10 · ROUTINE", or "PERSONAL" for the coach's own drills.
    private var heroEyebrow: String {
        if let activity = currentDrill.libraryActivity {
            return "\(activity.age.title) · \(activity.block.title)".uppercased()
        }
        return (isChinese ? "个人训练" : "Personal drill").uppercased()
    }

    /// The block's colour, the same family as the session headers.
    private var heroColor: Color {
        switch currentDrill.libraryActivity?.block {
        case .routine: return Color(hex: "#1F6F8B")
        case .smallGames: return Color(hex: "#5B3FA8")
        case .compete: return Color(hex: "#B4461C")
        case .game: return Color(hex: "#1E7A45")
        case nil: return categoryColor
        }
    }

    /// Each block's court: stations for a routine, a board for small games,
    /// the half court to compete, the whole floor for a game.
    private var heroCourt: CourtArtStyle {
        switch currentDrill.libraryActivity?.block {
        case .routine: return .testSpots
        case .smallGames: return .tacticsBoard
        case .compete: return .halfCourt
        case .game: return .fullCourt
        case nil: return .halfCourt
        }
    }

    private func heroPill(icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.caption.weight(.semibold)).lineLimit(1)
        } icon: {
            Image(systemName: icon).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background { Capsule().fill(.black.opacity(0.3)) }
        .filmGlass(.regular, in: Capsule())
    }

    // MARK: - Inline Info Chips (replaces cards)
    private var quickInfoChips: some View {
        HStack(spacing: 16) {
            // Duration chip
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(currentDrill.localizedDuration)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Text("·")
                .foregroundColor(AppTheme.textTertiary)
            
            // Players chip
            HStack(spacing: 5) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(currentDrill.localizedPlayerRange)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            // Completion indicator for quick-note drills
            if isQuickNoteDrill {
                let progress = completionProgress
                Text("\(progress.filled)/\(progress.total)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Refinement CTA Card
    private var refinementCTACard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text(isChinese ? "完善此训练" : "Complete This Drill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            Text(isChinese ? "添加说明、要点和器材，使其可重复使用。" : "Add instructions, key points, and equipment to make it reusable.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
    
    // MARK: - Quick Actions Footer
    private var quickActionsFooter: some View {
        HStack {
            Spacer()
            
            // Delete button only - Edit is in toolbar
            Button(action: {
                showDeleteConfirm = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                    Text(isChinese ? "删除此训练" : "Delete Drill")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(AppTheme.cardBackground)
                .shadow(color: .black.opacity(0.03), radius: 2, y: -1)
        )
    }
    
    // MARK: - Quick Info Section
    private var quickInfoSection: some View {
        HStack(spacing: 12) {
            // Duration
            QuickInfoCard(
                icon: "clock.fill",
                value: currentDrill.localizedDuration,
                label: DrillLocalization.L("Duration"),
                color: .blue
            )
            
            // Players
            QuickInfoCard(
                icon: "person.2.fill",
                value: currentDrill.localizedPlayerRange,
                label: DrillLocalization.L("Players"),
                color: .green
            )
            
            // Favorite
            Button(action: {
                HapticFeedback.impact(.medium)
                dataManager.toggleDrillFavorite(currentDrill)
            }) {
                QuickInfoCard(
                    icon: currentDrill.isFavorite ? "heart.fill" : "heart",
                    value: currentDrill.isFavorite ? "★" : "☆",
                    label: DrillLocalization.L("Favorites"),
                    color: currentDrill.isFavorite ? .red : .gray
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var quickNoteContextSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text(LocalizationManager.shared.currentLanguage == .chinese ? "此训练来自课程中的快速文本记录，可在这里完善为正式训练模板。" : "This drill came from a quick session text note. You can refine it into a full drill template here.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
    }
    
    // MARK: - Description Section (inline editing)
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: currentDrill.isLibraryDrill
                                    ? (isChinese ? "具体做法" : "How it runs")
                                    : DrillLocalization.L("Description"), icon: "text.alignleft")
                Spacer()
                if editingDescription {
                    Button(action: saveDescription) {
                        Text(isChinese ? "保存" : "Save")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppTheme.accentColor)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if editingDescription {
                // Inline editor
                TextEditor(text: $editedDescription)
                    .font(.system(size: 14))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.accentColor, lineWidth: 1.5)
                    )
                    .focused($focusedField, equals: .description)
            } else if currentDrill.description.isEmpty {
                // Placeholder for empty - tap to edit
                Button(action: startEditingDescription) {
                    HStack {
                        Text(isChinese ? "点击添加描述..." : "Tap to add a description...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textTertiary)
                            .italic()
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            } else {
                // Display mode - tap to edit
                Button(action: startEditingDescription) {
                    HStack(alignment: .top) {
                        Text(currentDrill.localizedDescription)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Instructions Section (inline editing)
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: DrillLocalization.L("Instructions"), icon: "list.number")
                Spacer()
                if editingInstructions {
                    Button(action: saveInstructions) {
                        Text(isChinese ? "完成" : "Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                } else if !currentDrill.instructions.isEmpty {
                    Button(action: startEditingInstructions) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                if editingInstructions {
                    // Editable list
                    ForEach(editedInstructions.indices, id: \.self) { index in
                        HStack(alignment: .center, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 20)
                            
                            TextField(isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)", text: $editedInstructions[index])
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .instruction(index))
                            
                            Button(action: { removeInstruction(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        
                        if index < editedInstructions.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                    
                    Divider().padding(.vertical, 6)
                    
                    // Add new step
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .frame(width: 20)
                        
                        TextField(isChinese ? "添加步骤..." : "Add step...", text: $newInstruction)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .focused($focusedField, equals: .newInstruction)
                            .onSubmit { addNewInstruction() }
                    }
                    .padding(.vertical, 6)
                } else if currentDrill.instructions.isEmpty {
                    // Empty placeholder
                    Button(action: startEditingInstructions) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text(isChinese ? "添加步骤" : "Add step")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Display mode
                    ForEach(Array(currentDrill.localizedInstructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            
                            Text(instruction)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        
                        if index < currentDrill.localizedInstructions.count - 1 {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Key Points Section (inline editing)
    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: DrillLocalization.L("Key Points"), icon: "lightbulb.fill")
                Spacer()
                if editingKeyPoints {
                    Button(action: saveKeyPoints) {
                        Text(isChinese ? "完成" : "Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                } else if !currentDrill.keyPoints.isEmpty {
                    Button(action: startEditingKeyPoints) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                if editingKeyPoints {
                    // Editable list
                    ForEach(editedKeyPoints.indices, id: \.self) { index in
                        HStack(alignment: .center, spacing: 10) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 16)
                            
                            TextField(isChinese ? "要点 \(index + 1)" : "Point \(index + 1)", text: $editedKeyPoints[index])
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .keyPoint(index))
                            
                            Button(action: { removeKeyPoint(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        
                        if index < editedKeyPoints.count - 1 {
                            Divider().padding(.leading, 26)
                        }
                    }
                    
                    Divider().padding(.vertical, 6)
                    
                    // Add new key point
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .frame(width: 16)
                        
                        TextField(isChinese ? "添加要点..." : "Add point...", text: $newKeyPoint)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .focused($focusedField, equals: .newKeyPoint)
                            .onSubmit { addNewKeyPoint() }
                    }
                    .padding(.vertical, 6)
                } else if currentDrill.keyPoints.isEmpty {
                    // Empty placeholder
                    Button(action: startEditingKeyPoints) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text(isChinese ? "添加要点" : "Add key point")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Display mode
                    ForEach(currentDrill.localizedKeyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(point)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Inline Editing Helpers
    private func startEditingDescription() {
        editedDescription = currentDrill.localizedDescription
        editingDescription = true
        focusedField = .description
    }
    
    private func saveDescription() {
        var updated = currentDrill
        updated.description = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.updateDrill(updated)
        editingDescription = false
        focusedField = nil
    }
    
    private func startEditingInstructions() {
        editedInstructions = currentDrill.instructions.isEmpty ? [""] : currentDrill.instructions
        newInstruction = ""
        editingInstructions = true
    }
    
    private func addNewInstruction() {
        let trimmed = newInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedInstructions.append(trimmed)
        newInstruction = ""
    }
    
    private func removeInstruction(at index: Int) {
        guard editedInstructions.indices.contains(index) else { return }
        editedInstructions.remove(at: index)
    }
    
    private func saveInstructions() {
        var updated = currentDrill
        updated.instructions = editedInstructions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        dataManager.updateDrill(updated)
        editingInstructions = false
        focusedField = nil
    }
    
    private func startEditingKeyPoints() {
        editedKeyPoints = currentDrill.keyPoints.isEmpty ? [""] : currentDrill.keyPoints
        newKeyPoint = ""
        editingKeyPoints = true
    }
    
    private func addNewKeyPoint() {
        let trimmed = newKeyPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedKeyPoints.append(trimmed)
        newKeyPoint = ""
    }
    
    private func removeKeyPoint(at index: Int) {
        guard editedKeyPoints.indices.contains(index) else { return }
        editedKeyPoints.remove(at: index)
    }
    
    private func saveKeyPoints() {
        var updated = currentDrill
        updated.keyPoints = editedKeyPoints.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        dataManager.updateDrill(updated)
        editingKeyPoints = false
        focusedField = nil
    }
    
    private func addTagInline(_ tag: String) {
        var updated = currentDrill
        // Convert tag to lowercase with dashes for storage
        let normalizedTag = tag.lowercased().replacingOccurrences(of: " ", with: "-")
        if !updated.tags.contains(normalizedTag) {
            updated.tags.append(normalizedTag)
            dataManager.updateDrill(updated)
        }
    }
    
    // MARK: - Equipment Section
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: DrillLocalization.L("Equipment Needed"), icon: "basketball.fill")
            
            FlowLayout(spacing: 10) {
                ForEach(currentDrill.equipmentNeeded, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: equipmentIcon(for: item))
                            .font(.system(size: 12))
                            .foregroundColor(categoryColor.accessibleText)
                        Text(DrillLocalization.localizedEquipment(item))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(categoryColor.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Variations Section
    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: DrillLocalization.L("Variations"), icon: "arrow.triangle.branch")
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(currentDrill.localizedVariations, id: \.self) { variation in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor.accessibleText)
                        Text(variation)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Tags Section (with suggestions)
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: isChinese ? "标签" : "Tags", icon: "tag")
            
            VStack(alignment: .leading, spacing: 10) {
                // Existing tags
                if !userFacingTags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(userFacingTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                        }
                    }
                }
                
                // Suggested tags (show when tags are empty or always show suggestions)
                if !suggestedTags.isEmpty {
                    if !userFacingTags.isEmpty {
                        Divider().padding(.vertical, 4)
                    }
                    
                    Text(isChinese ? "建议添加" : "Suggested")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(suggestedTags.prefix(4), id: \.self) { tag in
                            Button(action: {
                                addTagInline(tag)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Show placeholder if no tags and no suggestions
                if userFacingTags.isEmpty && suggestedTags.isEmpty {
                    Text(isChinese ? "暂无标签" : "No tags")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Helper
    private func equipmentIcon(for item: String) -> String {
        let lowercased = item.lowercased()
        if lowercased.contains("basketball") || lowercased.contains("ball") {
            return "basketball.fill"
        } else if lowercased.contains("cone") {
            return "cone.fill"
        } else if lowercased.contains("chair") {
            return "chair.fill"
        } else if lowercased.contains("ladder") {
            return "ladder.fill"
        } else {
            return "circle.fill"
        }
    }
}

// MARK: - Quick Info Card
struct QuickInfoCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Detail Section Header
struct DetailSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Add Drill View
struct AddDrillView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    /// Editing an existing drill uses this SAME form (Luther, November 2026:
    /// "make the edit drill UI match the create drill one"), prefilled; Save
    /// writes onto a copy of the stored drill, never a rebuilt record.
    let editing: DrillItem?
    
    @State private var name: String
    @State private var category: DrillCategory
    @State private var difficulty: DifficultyLevel
    @State private var durationMinutes: Int
    @State private var description: String
    @State private var instructions: [String]
    @State private var keyPoints: [String]
    @State private var minPlayers: Int

    /// `drawing`: a new drill that starts from a drawing (the Coach board's
    /// Save as Drill) — it shows in the Visual section and is saved on Create.
    init(editing: DrillItem? = nil, drawing: DrillDrawing? = nil) {
        self.editing = editing
        _drawing = State(initialValue: drawing)
        _name = State(initialValue: editing?.name ?? "")
        _category = State(initialValue: editing?.category ?? .skills)
        _difficulty = State(initialValue: editing?.difficulty ?? .beginner)
        _durationMinutes = State(initialValue: editing?.durationMinutes ?? 10)
        _description = State(initialValue: editing?.description ?? "")
        _instructions = State(initialValue: (editing?.instructions).flatMap { $0.isEmpty ? nil : $0 } ?? [""])
        _keyPoints = State(initialValue: (editing?.keyPoints).flatMap { $0.isEmpty ? nil : $0 } ?? [""])
        _minPlayers = State(initialValue: editing?.minPlayers ?? 1)
        _tracking = State(initialValue: editing?.tracking)
        _skills = State(initialValue: editing?.attributes ?? AttributeProfile(scores: [:]))
        _skillsByCoach = State(initialValue: editing?.tags.contains(AttributeProfile.coachTag) ?? false)
    }
    /// "Track results" (23 Nov 2026, Luther): nil = not tracked.
    @State private var tracking: TrackDefinition?
    /// What Claude proposes to track, from the description (Return).
    @State private var suggestedTracking: TrackDefinition?
    /// A court drawing made while creating the drill (Luther, November
    /// 2026): saved as the drill's first visual on Create.
    @State private var drawing: DrillDrawing?
    @State private var drawingOpen = false
    /// "Part of a series" (18 Nov 2026, Luther): the series this drill joins
    /// as its next level — "" none, "new" a new series named `newSeriesName`.
    @State private var seriesChoice = ""
    @State private var newSeriesName = ""
    /// Return in the description asks Claude for the steps and key points
    /// (DrillWriter); the spinner beside "Description" is the only sign.
    @State private var writing = false
    @State private var lastWritten: DrillWriterResult?
    /// Claude's attribute rating from the same answer — saved as the drill's
    /// attr: tags unless the coach rated it themselves.
    @State private var writtenAttributes: AttributeProfile?
    /// What the drill develops, on the eight octagon skills — shown and
    /// editable in the form (25 Nov 2026, Luther: one Category cannot say a
    /// drill works offense AND defense). Claude's reading of the description
    /// fills it until the coach sets a row himself.
    @State private var skills: AttributeProfile
    @State private var skillsByCoach: Bool
    /// The rows changed in this visit (by the coach or by Claude), so an
    /// untouched edit never rewrites a drill's rating.
    @State private var skillsChanged = false
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            Form {
                Section(isChinese ? "基本信息" : "Basic Info") {
                    TextField(isChinese ? "训练名称" : "Drill Name", text: $name)
                    
                    Picker(isChinese ? "类别" : "Category", selection: $category) {
                        ForEach(DrillCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    
                    Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    
                    Stepper(isChinese ? "时长：\(durationMinutes) 分钟" : "Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...60)
                    Stepper(isChinese ? "最少人数：\(minPlayers)" : "Min Players: \(minPlayers)", value: $minPlayers, in: 1...20)
                }
                
                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                        .accessibilityIdentifier("newDrill.description")
                        .onChange(of: description) { old, new in
                            if let text = DrillWriter.pressedReturn(old: old, new: new) {
                                description = text
                                writeFromDescription()
                            }
                        }
                } header: {
                    HStack(spacing: 6) {
                        Text(isChinese ? "描述" : "Description")
                        if writing {
                            ProgressView().controlSize(.mini)
                                .accessibilityIdentifier("newDrill.writing")
                        }
                    }
                }
                
                skillsSection(isChinese: isChinese)

                Section(isChinese ? "说明" : "Instructions") {
                    ForEach(instructions.indices, id: \.self) { index in
                        TextField(isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)", text: $instructions[index])
                    }
                    Button(isChinese ? "添加步骤" : "Add Step") {
                        instructions.append("")
                    }
                }
                
                Section(isChinese ? "要点" : "Key Points") {
                    ForEach(keyPoints.indices, id: \.self) { index in
                        TextField(isChinese ? "要点 \(index + 1)" : "Point \(index + 1)", text: $keyPoints[index])
                    }
                    Button(isChinese ? "添加要点" : "Add Point") {
                        keyPoints.append("")
                    }
                }

                trackSection(isChinese: isChinese)

                seriesSection(isChinese: isChinese)

                // A drill's visuals are managed on its page once it exists.
                if editing == nil {
                    visualSection(isChinese: isChinese)
                }
            }
            .fullScreenCover(isPresented: $drawingOpen) {
                DrillDrawingEditor(drawing: drawing ?? DrillDrawing.new()) { drawing = $0 }
            }
            #if DEBUG
            // HOOPWISE_NEWDRILL_DESCRIPTION=<text> types it and presses Return;
            // the result is logged to hoopwise.mac / drillWriter.
            .onAppear {
                guard let text = ProcessInfo.processInfo.environment["HOOPWISE_NEWDRILL_DESCRIPTION"] else { return }
                description = text
                Logger(subsystem: "hoopwise.mac", category: "drillWriter")
                    .notice("drillWriter key \(AnthropicKeyStore.key == nil ? "missing" : "present", privacy: .public)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { description = text + "\n" }
            }
            .onChange(of: writing) { _, now in
                guard !now, ProcessInfo.processInfo.environment["HOOPWISE_NEWDRILL_DESCRIPTION"] != nil else { return }
                let log = Logger(subsystem: "hoopwise.mac", category: "drillWriter")
                log.notice("drillWriter steps: \(instructions.joined(separator: " | "), privacy: .public)")
                log.notice("drillWriter points: \(keyPoints.joined(separator: " | "), privacy: .public)")
                log.notice("drillWriter tracking: \(suggestedTracking.map { "\($0.kind.rawValue) · \($0.summary(chinese: false)) · main \($0.mainAttributes.map(\.rawValue)) · some \($0.some) · zones \($0.zones)" } ?? "none", privacy: .public)")
            }
            #endif
            .navigationTitle(editing == nil ? (isChinese ? "新训练" : "New Drill") : (isChinese ? "编辑训练" : "Edit Drill"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? (isChinese ? "创建" : "Create") : (isChinese ? "保存" : "Save")) {
                        if editing == nil { createDrill() } else { saveEdits() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    /// TRACK RESULTS (23 Nov 2026; the TYPE drives it since 24 Nov 2026):
    /// the kind of drill first — it fills in how it is measured, the amount,
    /// the sides and the skills (main / some) — then what the coach changes:
    /// the shot-map zones of a shooting drill, the course of a timed one.
    @ViewBuilder
    private func trackSection(isChinese: Bool) -> some View {
        Section {
            Toggle(isOn: Binding(get: { tracking != nil },
                                 set: { on in
                                     if on { tracking = tracking ?? suggestedTracking ?? guessedKind.preset(chinese: isChinese) }
                                     else { tracking = nil }
                                 })) {
                Label(isChinese ? "记录成绩" : "Track results", systemImage: "chart.bar.xaxis")
            }
            .accessibilityIdentifier("newDrill.track")
            if tracking == nil, let suggested = suggestedTracking {
                // Claude read the description (Return) and proposes a setup.
                Button {
                    tracking = suggested
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "Claude 建议记录：\(suggested.kind.title(chinese: true))"
                                           : "Claude suggests tracking: \(suggested.kind.title(chinese: false))")
                                .font(.subheadline.weight(.semibold))
                            Text(suggested.summary(chinese: isChinese)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isChinese ? "采用" : "Use").font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityIdentifier("newDrill.track.useSuggestion")
            }
            if let def = tracking {
                // 1. The kind.
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "训练类型" : "Type of drill").font(.subheadline)
                    FlowLayout(spacing: 8) {
                        ForEach(TrackKind.allCases) { kind in
                            let on = def.kind == kind
                            Button {
                                guard !on else { return }
                                tracking = kind.preset(chinese: isChinese)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: kind.symbol).font(.caption)
                                    Text(kind.title(chinese: isChinese)).font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 11).frame(minHeight: 34)
                                .background(Capsule().fill(on ? Color.orange : Color(.tertiarySystemFill)))
                                .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("newDrill.track.kind.\(kind.rawValue)")
                        }
                    }
                }
                .padding(.vertical, 4)

                // 2. How it is measured (this kind's measures, in its words).
                Picker(isChinese ? "怎么记录" : "How it's measured", selection: Binding(
                    get: { def.measure },
                    set: { m in
                        guard m != def.measure else { return }
                        // The kind's defaults for that measure; the skills,
                        // zones and sides the coach set stay.
                        var next = def.kind.preset(measure: m, chinese: isChinese)
                        next.skills = def.skills; next.some = def.some
                        next.zones = def.zones
                        if !def.spots.isEmpty { next.spots = def.spots }
                        tracking = next
                    })) {
                    ForEach(def.kind.measures) { m in
                        Label(def.kind.measureTitle(m, chinese: isChinese), systemImage: m.symbol).tag(m)
                    }
                }
                .accessibilityIdentifier("newDrill.track.measure")

                // 3. How much.
                switch def.measure {
                case .madeOf:
                    Stepper(value: trackBinding(\.amount), in: 1...500) {
                        Text((isChinese ? "次数" : "Attempts")
                             + (def.onShotMap ? (isChinese ? "（每区）" : " a zone") : (def.spotCount > 1 ? (isChinese ? "（每点）" : " a spot") : ""))
                             + ": \(def.amount)")
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("newDrill.track.amount")
                case .inTime:
                    Stepper(value: Binding(get: { def.amount },
                                           set: { tracking?.amount = ShootingSetupSheet.clamped($0) }),
                            in: 5...ShootingSetupSheet.maxSeconds, step: def.amount < 60 ? 5 : 15) {
                        Text((isChinese ? "时间：" : "Time: ") + ShootingSetup.time(def.amount, chinese: isChinese))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("newDrill.track.amount")
                    TextField(isChinese ? "计什么，如“传球”（默认：命中）" : "What is counted, like “passes” (default: makes)",
                              text: trackBinding(\.unit))
                case .timeToFinish:
                    Text(isChinese ? "在课上用秒表计时，越快越好。" : "Timed with a stopwatch in class; faster is better.")
                        .foregroundStyle(.secondary)
                case .count:
                    TextField(isChinese ? "单位，如“次触球”“分”" : "Unit, like “touches” or “points”", text: trackBinding(\.unit))
                        .accessibilityIdentifier("newDrill.track.unit")
                    Picker(isChinese ? "更好的是" : "Better is", selection: trackBinding(\.higherIsBetter)) {
                        Text(isChinese ? "越多越好" : "Higher").tag(true)
                        Text(isChinese ? "越少越好" : "Lower").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                // 4. The kind's own tool: the course, or the shot map.
                if def.kind.usesCourse, def.measure != .count {
                    Picker(isChinese ? "距离 / 路线" : "Course", selection: trackBinding(\.course)) {
                        Text(isChinese ? "未指定" : "Not set").tag(TrackCourse?.none)
                        ForEach(TrackCourse.allCases) { c in Text(c.title(chinese: isChinese)).tag(Optional(c)) }
                    }
                    .accessibilityIdentifier("newDrill.track.course")
                }
                if def.kind.usesShotMap {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isChinese ? "投篮位置" : "Where it's shot from").font(.subheadline)
                            Spacer()
                            if !def.zones.isEmpty {
                                Button(isChinese ? "清除" : "Clear") { tracking?.zones = [] }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        ShotZonePicker(zones: trackBinding(\.zones))
                            .frame(maxWidth: 420)
                            .frame(maxWidth: .infinity)
                        Text(def.zones.isEmpty
                             ? (isChinese ? "点选这个训练的投篮区域。成绩会进入学员的投篮热区图。" : "Tap the zones this drill is shot from. Results join the athlete's shot chart.")
                             : (def.measure == .madeOf
                                ? (isChinese ? "每个区域记录一次（\(def.zones.count) 个）；成绩进入学员的投篮热区图。" : "One number a zone (\(def.zones.count)); results join the athlete's shot chart.")
                                : (isChinese ? "每个区域记录一次。限时成绩没有出手数，不进入热区图。" : "One number a zone. Timed results have no attempts, so they stay off the shot chart.")))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("newDrill.track.zones")
                }
                if !def.onShotMap { spotRows(def, isChinese: isChinese) }

                // 5. What it says about the athlete: main or some.
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "对评估的影响" : "What it says in the evaluation")
                        .font(.subheadline)
                    FlowLayout(spacing: 8) {
                        ForEach(DrillAttribute.allCases, id: \.self) { axis in
                            let weight = def.weight(for: axis)
                            Button {
                                // off → main → some → off
                                if weight == 0 {
                                    tracking?.skills.append(axis.rawValue)
                                } else if weight == 1 {
                                    tracking?.some.append(axis.rawValue)
                                } else {
                                    tracking?.skills.removeAll { $0 == axis.rawValue }
                                    tracking?.some.removeAll { $0 == axis.rawValue }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: axis.icon).font(.caption)
                                    Text(axis.title(chinese: isChinese)).font(.subheadline.weight(.medium))
                                    if weight > 0 {
                                        Text(weight == 1 ? (isChinese ? "主要" : "MAIN") : (isChinese ? "次要" : "SOME"))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(weight == 1 ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.18)))
                                    }
                                }
                                .padding(.horizontal, 10).frame(minHeight: 32)
                                .background(Capsule().fill(weight == 1 ? Color.accentColor : Color(.tertiarySystemFill)))
                                .overlay(Capsule().strokeBorder(weight == 0.5 ? Color.accentColor : .clear, lineWidth: 1.5))
                                .foregroundStyle(weight == 1 ? Color.white : (weight == 0.5 ? Color.accentColor : Color.primary))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("newDrill.track.skill.\(axis.rawValue)")
                            .accessibilityValue(weight == 1 ? "main" : (weight == 0.5 ? "some" : "off"))
                        }
                    }
                    Text(isChinese ? "点一下：主要；再点：次要；再点：取消。主要的训练更能影响建议评分。"
                                   : "Tap once for Main, again for Some, again to remove. Main drills weigh more in the suggested rating.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(isChinese ? "成绩记录" : "Tracking")
        } footer: {
            if let def = tracking {
                Text(trackFooter(def, isChinese: isChinese))
            } else {
                Text(isChinese ? "可选。选一个类型，其余自动设置好：怎么记录、记多少、影响哪些技能。"
                               : "Optional. Pick the type of drill and the rest is set up for you: how it is measured, how much, and which skills it speaks for.")
            }
        }
    }

    /// What will happen with this drill's results, in one paragraph.
    private func trackFooter(_ def: TrackDefinition, isChinese: Bool) -> String {
        var lines: [String] = []
        lines.append(isChinese ? "加入课程计划后，在训练那一行记录每位学员（\(def.summary(chinese: true))）。"
                               : "In a plan, the drill's row logs each athlete (\(def.summary(chinese: false))).")
        if (0..<def.spotCount).contains(where: { def.zone(forSpot: $0) != nil }) {
            lines.append(isChinese ? "成绩进入学员的投篮热区图。" : "Results join the athlete's shot chart.")
        }
        let main = def.mainAttributes.map { $0.title(chinese: isChinese) }
        if main.isEmpty {
            lines.append(isChinese ? "还没有选择技能：成绩只显示在学员的训练成绩里。" : "No skill chosen yet: results show only under the athlete's tracked drills.")
        } else {
            lines.append(isChinese ? "和他以前的成绩、同年级学员比较，显示在\(main.joined(separator: "、"))下，并给出建议评分。"
                                   : "Compared with their own history and athletes in the same grade, shown under \(main.joined(separator: ", ")), with a suggested rating.")
        }
        return lines.joined(separator: isChinese ? "" : " ")
    }

    /// The kind the drill's category points to, for the first switch-on.
    private var guessedKind: TrackKind {
        switch category {
        case .shooting: .shooting
        case .defense: .defense
        case .conditioning: .conditioning
        default: .other
        }
    }

    private func trackBinding<T>(_ path: WritableKeyPath<TrackDefinition, T>) -> Binding<T> {
        Binding(get: { (tracking ?? TrackDefinition())[keyPath: path] },
                set: { tracking?[keyPath: path] = $0 })
    }

    /// Named spots or sides — none means one number for the drill.
    @ViewBuilder
    private func spotRows(_ def: TrackDefinition, isChinese: Bool) -> some View {
        ForEach(def.spots.indices, id: \.self) { i in
            HStack {
                TextField(isChinese ? "点位 \(i + 1)" : "Spot \(i + 1)", text: Binding(
                    get: { tracking?.spots.indices.contains(i) == true ? tracking!.spots[i] : "" },
                    set: { if tracking?.spots.indices.contains(i) == true { tracking?.spots[i] = $0 } }))
                    .accessibilityIdentifier("newDrill.track.spot.\(i)")
                Button(role: .destructive) {
                    tracking?.spots.remove(at: i)
                } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                .buttonStyle(.plain)
            }
        }
        Button {
            if tracking?.spots.isEmpty == true {
                tracking?.spots = def.kind == .finishing || def.kind == .ballHandling
                    ? (isChinese ? ["右手", "左手"] : ["Right hand", "Left hand"])
                    : (isChinese ? ["左", "右"] : ["Left", "Right"])
            } else {
                tracking?.spots.append("")
            }
        } label: {
            Label(def.spots.isEmpty ? (isChinese ? "分点位或左右记录" : "Log by spot or side")
                                    : (isChinese ? "添加点位" : "Add a spot"), systemImage: "plus.circle")
        }
        .accessibilityIdentifier("newDrill.track.addSpot")
    }

    @ViewBuilder
    /// Join a series as its next level, or start one with this drill as
    /// level 1. Leaving a series happens on the series page.
    private func seriesSection(isChinese: Bool) -> some View {
        let all = DrillSeries.all(in: dataManager.drills)
        let joined = editing.map { DrillSeries.containing($0.id, in: dataManager.drills) } ?? []
        return Section {
            ForEach(joined, id: \.series.id) { item in
                Label(isChinese ? "\(item.series.name) · 第 \(item.level)/\(item.series.levels.count) 级"
                                : "\(item.series.name) · Level \(item.level) of \(item.series.levels.count)",
                      systemImage: "stairs")
                    .foregroundStyle(.secondary)
            }
            Picker(isChinese ? "加入系列" : "Add to a series", selection: $seriesChoice) {
                Text(isChinese ? "不加入" : "None").tag("")
                ForEach(all.filter { s in !joined.contains { $0.series.id == s.id } }) { series in
                    Text(isChinese ? "\(series.name)（第 \(series.levels.count + 1) 级）"
                                   : "\(series.name) (as level \(series.levels.count + 1))").tag(series.id.uuidString)
                }
                Text(isChinese ? "新系列…" : "New series…").tag("new")
            }
            .accessibilityIdentifier("newDrill.series")
            if seriesChoice == "new" {
                TextField(isChinese ? "系列名称，如“运球进阶”" : "Series name, like “Dribbling ladder”", text: $newSeriesName)
                    .accessibilityIdentifier("newDrill.seriesName")
            }
        } header: {
            Text(isChinese ? "系列" : "Series")
        } footer: {
            Text(isChinese ? "系列是从易到难的一组训练。规划阶段时可以把整个系列按课程逐级排开。"
                           : "A series is a ladder of drills, easiest first. A phase can spread a whole series over its sessions, level by level.")
        }
    }

    /// Adds `drillId` as the next level of the chosen series (or a new one).
    private func joinSeries(_ drillId: UUID) {
        if seriesChoice == "new" {
            let name = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let series = DrillSeries(name: name, levels: [drillId])
            dataManager.addDrill(series.applied(to: DrillItem(id: series.id, name: name, category: .skills)))
        } else if let id = UUID(uuidString: seriesChoice),
                  let record = dataManager.drills.first(where: { $0.id == id }),
                  var series = DrillSeries(drill: record), !series.levels.contains(drillId) {
            series.levels.append(drillId)
            dataManager.updateDrill(series.applied(to: record))
        }
    }

    private func visualSection(isChinese: Bool) -> some View {
        Section {
            if let drawing {
                DrillDrawingPlayer(drawing: drawing)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                Button {
                    drawingOpen = true
                } label: {
                    Label(isChinese ? "编辑图示" : "Edit drawing", systemImage: "pencil.and.outline")
                }
                Button(role: .destructive) {
                    self.drawing = nil
                } label: {
                    Label(isChinese ? "移除图示" : "Remove drawing", systemImage: "trash")
                }
            } else {
                Button {
                    drawingOpen = true
                } label: {
                    Label(isChinese ? "在球场上绘制" : "Draw on the court", systemImage: "pencil.and.outline")
                }
                .accessibilityIdentifier("newDrill.draw")
            }
        } header: {
            Text(isChinese ? "图示" : "Visual")
        } footer: {
            if drawing == nil {
                Text(isChinese ? "可选。用战术板的工具画出球员、跑位、传球和标志桶，可分多步。"
                               : "Optional. Draw players, runs, passes and cones with the plays editor, in as many steps as you need.")
            }
        }
    }

    /// Claude reads the description and fills Instructions and Key Points —
    /// only lists that are blank or still exactly its last answer. No key,
    /// no connection or a refusal: nothing changes, quietly.
    private func writeFromDescription() {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8, !writing, let key = AnthropicKeyStore.key else { return }
        writing = true
        let name = name, players = minPlayers, minutes = durationMinutes
        Task {
            defer { writing = false }
            guard let result = try? await DrillWriter.write(name: name, description: text, minPlayers: players,
                                                            minutes: minutes, key: key) else { return }
            if !result.instructions.isEmpty, DrillWriter.mayReplace(instructions, lastWritten: lastWritten?.instructions) {
                instructions = result.instructions
            }
            if !result.keyPoints.isEmpty, DrillWriter.mayReplace(keyPoints, lastWritten: lastWritten?.keyPoints) {
                keyPoints = result.keyPoints
            }
            lastWritten = result
            if let scores = result.attributes {
                let read = AttributeProfile(array: scores)
                writtenAttributes = read
                // Claude's reading shows in the form, unless the coach rated it.
                if !skillsByCoach { skills = read; skillsChanged = true }
            }
            suggestedTracking = result.tracking?.definition(chinese: LocalizationManager.shared.currentLanguage == .chinese)
        }
    }

    /// The eight skills, each None · Touched · Worked · Main, with the octagon
    /// drawn from them as they change.
    private func skillsSection(isChinese: Bool) -> some View {
        Section {
            if !skills.isEmpty {
                AttributeOctagon(values: skills.normalized)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("newDrill.skills.octagon")
            }
            ForEach(DrillAttribute.allCases) { axis in
                VStack(alignment: .leading, spacing: 6) {
                    Label(axis.title(chinese: isChinese), systemImage: axis.icon).font(.subheadline.weight(.medium))
                    Picker(axis.title(chinese: isChinese), selection: Binding(get: { skills[axis] }, set: {
                        skills[axis] = $0
                        skillsByCoach = true
                        skillsChanged = true
                    })) {
                        Text(isChinese ? "无" : "None").tag(0)
                        Text(isChinese ? "涉及" : "Touched").tag(1)
                        Text(isChinese ? "练到" : "Worked").tag(2)
                        Text(isChinese ? "重点" : "Main").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("newDrill.skill.\(axis.rawValue)")
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack(spacing: 6) {
                Text(isChinese ? "训练能力" : "What it develops")
                if writing { ProgressView().controlSize(.mini) }
            }
        } footer: {
            Text(skillsFooter(isChinese: isChinese))
        }
    }

    private func skillsFooter(isChinese: Bool) -> String {
        if skillsByCoach {
            return isChinese ? "你的评分。课程计划的能力图和训练库的技能筛选都用它。"
                             : "Your rating. The plan's balance chart and the library's skill filter use it."
        }
        if writtenAttributes != nil {
            return isChinese ? "Claude 根据描述的评估。改任何一行就以你的为准。"
                             : "Claude's reading of the description. Change any row and yours is kept."
        }
        let canAsk = AnthropicKeyStore.key != nil
        return isChinese
            ? (canAsk ? "一个训练可以练到多项能力。在描述里按回车，Claude 会根据描述填写；也可以自己选。"
                      : "一个训练可以练到多项能力，逐项选择。")
            : (canAsk ? "A drill can work several skills. Press Return in the description and Claude fills these from it — or set them yourself."
                      : "A drill can work several skills — set each one.")
    }

    /// Tracking as saved: blank spot names dropped, one spot = none.
    private var cleanedTracking: TrackDefinition? {
        guard var t = tracking else { return nil }
        t.spots = t.spots.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if t.spots.count == 1 { t.spots = [] }
        if !t.kind.usesShotMap { t.zones = [] }
        if t.onShotMap { t.spots = [] }
        if !t.kind.usesCourse || t.measure == .count { t.course = nil }
        t.some = t.some.filter { t.skills.contains($0) }
        t.unit = t.unit.trimmingCharacters(in: .whitespaces)
        return t
    }

    private func saveEdits() {
        guard var updated = editing else { return }
        updated.name = name
        updated.category = category
        updated.difficulty = difficulty
        updated.durationMinutes = durationMinutes
        updated.description = description
        updated.instructions = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.keyPoints = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.minPlayers = minPlayers
        updated.tags = DrillItem.tags(updated.tags, tracking: cleanedTracking)
        if skillsChanged { updated.tags = skills.replacing(in: updated.tags, byCoach: skillsByCoach) }
        updated.updatedAt = Date()
        dataManager.updateDrill(updated)
        joinSeries(updated.id)
        dismiss()
    }

    private func createDrill() {
        let id = UUID()
        var media: [DrillMedia] = []
        if let drawing, let saved = DrillDrawingMedia.save(drawing, drillId: id, existing: nil, sortOrder: 0) {
            media.append(saved)
        }
        var drill = DrillItem(
            id: id,
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: description,
            instructions: instructions.filter { !$0.isEmpty },
            keyPoints: keyPoints.filter { !$0.isEmpty },
            minPlayers: minPlayers,
            media: media
        )
        if skillsChanged, !skills.isEmpty { drill.tags = skills.replacing(in: drill.tags, byCoach: skillsByCoach) }
        drill.tags = DrillItem.tags(drill.tags, tracking: cleanedTracking)
        dataManager.addDrill(drill)
        joinSeries(id)
        dismiss()
    }
}

/// What a tracked drill records and what it means (23 Nov 2026). Edited in
/// Edit Drill → Tracking.
struct DrillTrackingCard: View {
    let tracking: TrackDefinition
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isChinese ? "记录成绩" : "Tracked", systemImage: "chart.bar.xaxis")
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: tracking.measure.symbol)
                    .foregroundStyle(.orange)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.orange.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracking.kind == .other ? tracking.measure.title(chinese: isChinese)
                         : tracking.kind.title(chinese: isChinese) + " · " + tracking.kind.measureTitle(tracking.measure, chinese: isChinese))
                        .font(.subheadline.weight(.semibold))
                    Text(tracking.summary(chinese: isChinese)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if tracking.onShotMap {
                ShotZonePicker(zones: .constant(tracking.zones))
                    .allowsHitTesting(false)
                    .frame(maxWidth: 300)
            }
            if !tracking.attributes.isEmpty {
                let main = tracking.mainAttributes.map { $0.title(chinese: isChinese) }
                let some = tracking.attributes.filter { tracking.weight(for: $0) < 1 }.map { $0.title(chinese: isChinese) }
                let sep = isChinese ? "、" : ", "
                Text((isChinese ? "评估：主要 " : "In the evaluation: mainly ") + (main.isEmpty ? "—" : main.joined(separator: sep))
                     + (some.isEmpty ? "" : (isChinese ? "；次要 " : "; some ") + some.joined(separator: sep)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if (0..<tracking.spotCount).contains(where: { tracking.zone(forSpot: $0) != nil }) {
                Label(isChinese ? "成绩进入学员的投篮热区图" : "Results join the athlete's shot chart", systemImage: "circle.grid.cross")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.filmCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drill.tracking")
    }
}

#if !os(macOS)
// MARK: - iOS Add/Edit Drill Sheet
/// macOS has its own `AddEditDrillSheet` in the Mac coach library.
/// iOS targets need a local implementation to avoid build failures.
struct AddEditDrillSheet: View {
    let drill: DrillItem?
    
    var body: some View {
        Group {
            AddDrillView(editing: drill)
        }
    }
}

#endif

#Preview {
    DrillsLibraryView()
        .environmentObject(DataManager.shared)
}
