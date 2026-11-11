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
    }

    var pick: Pick? = nil

    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var showingAddDrill = false
    /// "U8" … or "mine". The picker remembers its own age apart from the page.
    @AppStorage private var ageChoice: String

    init(pick: Pick? = nil) {
        self.pick = pick
        _ageChoice = AppStorage(wrappedValue: ActivityAge.u8.rawValue, pick == nil ? "library.age" : "planPicker.age")
    }
    @AppStorage("library.includeEarlier") private var includeEarlier = false
    @State private var block: ActivityBlock = .routine
    @State private var type: ActivityType?
    @State private var showGuidance = false
    @State private var openRule: LibraryActivity?
    @State private var mineCategory: DrillCategory?
    /// Mac: Return in the search bar asks Claude for the closest drills in
    /// the whole library (DrillFinder); they show above the list.
    @State private var claudeQuery: String?
    @State private var claudeResult: DrillFinderResult?
    @State private var claudeAsking = false
    @State private var claudeProblem: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var currentCoachId: UUID { dataManager.loggedInCoachId ?? dataManager.coach.id }
    private var age: ActivityAge? { ActivityAge(rawValue: ageChoice) }
    private var ages: [ActivityAge] {
        guard let age else { return [] }
        return includeEarlier ? age.upToHere : [age]
    }

    private var visibleDrills: [DrillItem] {
        dataManager.drills.filter { drill in
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

    /// Library drills for the chosen ages and block (all types), library order.
    private var blockPairs: [(activity: LibraryActivity, drill: DrillItem)] {
        let byId = Dictionary(visibleDrills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ActivityLibrary.shared.plannable.compactMap { activity in
            guard ages.contains(activity.age), activity.block == block,
                  let drill = byId[activity.id] else { return nil }
            return (activity, drill)
        }
    }

    private var shownPairs: [(activity: LibraryActivity, drill: DrillItem)] {
        guard let type else { return blockPairs }
        return blockPairs.filter { $0.activity.type == type }
    }

    /// Rule options for the chosen ages (Game block only).
    private var rules: [LibraryActivity] {
        guard block == .game, type == nil || type == .rules else { return [] }
        return ActivityLibrary.shared.items.filter {
            $0.isRule && ages.contains($0.age)
        }
    }

    private var typeCounts: [(ActivityType, Int)] {
        var counts: [ActivityType: Int] = [:]
        for pair in blockPairs { counts[pair.activity.type, default: 0] += 1 }
        if block == .game {
            let ruleCount = ActivityLibrary.shared.items.filter { $0.isRule && ages.contains($0.age) }.count
            if ruleCount > 0 { counts[.rules] = ruleCount }
        }
        return ActivityType.allCases.compactMap { t in counts[t].map { (t, $0) } }
    }

    private func blockCount(_ b: ActivityBlock) -> Int {
        let ids = Set(visibleDrills.map(\.id))
        return ActivityLibrary.shared.plannable.filter {
            ages.contains($0.age) && $0.block == b && ids.contains($0.id)
        }.count
    }

    /// Drills a coach created (not from the library).
    private var mine: [DrillItem] {
        visibleDrills.filter { !$0.isLibraryDrill }
            .filter { mineCategory == nil || $0.category == mineCategory }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
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

    /// The picker opened for a neglected axis: drills of the chosen age(s),
    /// any block, scoring 2–3 on it, strongest first; personal ones too.
    @ViewBuilder
    private func strongOnSection(_ axis: DrillAttribute) -> some View {
        let byId = Dictionary(visibleDrills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let library: [(LibraryActivity, DrillItem)] = ActivityLibrary.shared.plannable.compactMap { activity in
            guard ages.isEmpty || ages.contains(activity.age), let drill = byId[activity.id] else { return nil }
            return drill.attributes[axis] >= 2 ? (activity, drill) : nil
        }
        let ranked = library.sorted { $0.1.attributes[axis] > $1.1.attributes[axis] }.prefix(30)
        let personal = visibleDrills.filter { !$0.isLibraryDrill && $0.attributes[axis] >= 2 }
        Section {
            ForEach(personal) { drill in drillLink(drill) { DrillRow(drill: drill) } }
            ForEach(Array(ranked), id: \.0.key) { pair in
                drillLink(pair.1) { LibraryRow(activity: pair.0, drill: pair.1, showAge: ages.count > 1, showBlock: true) }
            }
        } header: {
            Label(isChinese ? "擅长\(axis.title)的训练" : "Strong on \(axis.title.lowercased())", systemImage: axis.icon)
        } footer: {
            if personal.isEmpty && ranked.isEmpty {
                Text(isChinese ? "这个年龄段没有找到，可以换个年龄。" : "None at this age — try another age.")
            }
        }
    }

    /// A drill row: opens the drill; in the plan picker, an add button
    /// beside it (a check once it is in the section).
    @ViewBuilder
    private func drillLink<Label: View>(_ drill: DrillItem, @ViewBuilder label: () -> Label) -> some View {
        if let pick {
            let added = pick.isAdded(drill.id)
            HStack(spacing: 10) {
                NavigationLink(destination: DrillDetailView(drill: drill)) { label() }
                Button {
                    if !added { pick.add(drill) }
                } label: {
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(added ? Color.green : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(added)
                .accessibilityLabel(added ? (isChinese ? "已添加" : "Added") : (isChinese ? "添加" : "Add"))
                .accessibilityIdentifier("drillPicker.add")
            }
        } else {
            NavigationLink(destination: DrillDetailView(drill: drill)) { label() }
        }
    }

    // MARK: Filters — one compact block: age, then block, then type

    private var filterSection: some View {
        Section {
            VStack(spacing: 10) {
                ageChips
                // The switch lives in the ⓘ sheet; while it is on, say so here
                // so the list is never filtered by something out of sight.
                if includeEarlier, let age, age != .u6 {
                    earlierAgesNote(age).padding(.horizontal, 20)
                }
                if age != nil {
                    Picker(isChinese ? "环节" : "Block", selection: $block) {
                        ForEach(ActivityBlock.allCases) { b in
                            Text(b.title).tag(b)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    if typeCounts.count > 1 {
                        typeChips
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    var body: some View {
        List {
            #if targetEnvironment(macCatalyst)
            claudeSection
            #endif
            if isSearching {
                searchResults
            } else {
                if let axis = pick?.attribute { strongOnSection(axis) }
                filterSection
                if let age {
                    libraryContent(age)
                } else {
                    mineContent
                }
            }
        }
        .listStyle(.insetGrouped)
        // The filters sit right on top of the list (Luther, November 2026:
        // there was a section gap between ages, blocks and the list).
        .listSectionSpacing(.compact)
        .navigationTitle(pick?.title ?? (isChinese ? "训练库" : "Activity library"))
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
            block = pick.initialBlock
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

    // MARK: Age chips

    private var ageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActivityAge.allCases) { a in
                    chip(a.title, selected: ageChoice == a.rawValue) { ageChoice = a.rawValue }
                }
                chip(isChinese ? "个人" : "Personal", selected: age == nil, icon: "person.crop.circle") {
                    ageChoice = "mine"
                }
            }
            .padding(.horizontal, 20)
        }
        .sensoryFeedback(.selection, trigger: ageChoice)
    }

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
            .background(Capsule().fill(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Library

    @ViewBuilder
    private func libraryContent(_ age: ActivityAge) -> some View {
        if shownPairs.isEmpty && rules.isEmpty {
            Section {
                Text(isChinese ? "这个环节暂无内容" : "Nothing in this block for this age")
                    .foregroundStyle(.secondary)
            }
        }

        if !shownPairs.isEmpty && type != .rules {
            Section {
                ForEach(shownPairs, id: \.activity.key) { pair in
                    drillLink(pair.drill) {
                        LibraryRow(activity: pair.activity, drill: pair.drill,
                                   showAge: includeEarlier)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(pair.drill) }
                }
            } header: {
                Text("\(type?.title ?? block.title) · \(shownPairs.count)")
            }
        }

        if !rules.isEmpty {
            Section {
                ForEach(rules) { rule in
                    Button { openRule = rule } label: {
                        LibraryRuleRow(rule: rule, showAge: includeEarlier)
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

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CategoryChip(title: DrillLocalization.L("All"),
                             count: typeCounts.reduce(0) { $0 + $1.1 },
                             color: .accentColor, isSelected: type == nil) { type = nil }
                ForEach(typeCounts, id: \.0) { t, count in
                    CategoryChip(title: t.title, count: count, color: .accentColor,
                                 isSelected: type == t) { type = t }
                }
            }
            .padding(.horizontal, 20)
        }
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

    // MARK: Personal (the "mine" choice)

    @ViewBuilder
    private var mineContent: some View {
        if mine.isEmpty && mineCategory == nil {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "figure.basketball")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(isChinese ? "还没有个人训练" : "No personal drills yet")
                        .font(.headline)
                    Text(isChinese ? "你或 Claude 创建的训练会出现在这里。" : "Drills you or Claude create appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(DrillLocalization.L("Add Drill")) { showingAddDrill = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(mine) { drill in
                    drillLink(drill) { DrillRow(drill: drill) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(drill) }
                }
            } header: {
                Text(isChinese ? "个人训练" : "Personal drills")
            }
        }
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
                Text(drill.localizedName)
                    .font(.body)
                    .lineLimit(2)
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
                Text(drill.localizedName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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
struct DrillDetailView: View {
    @EnvironmentObject var dataManager: DataManager
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
                        // Inline info chips (replaces cards)
                        quickInfoChips

                        // Activity library: age · block · type, and the source.
                        if let activity = currentDrill.libraryActivity {
                            VStack(alignment: .leading, spacing: 12) {
                                LibraryBadges(activity: activity)
                                if let zh = activity.nameZh, zh != currentDrill.localizedName {
                                    Text(zh).font(.subheadline).foregroundStyle(.secondary)
                                }
                                LibrarySourceView(activity: activity)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Description (with placeholder for empty)
                        descriptionSection

                        // What it develops: the eight-axis octagon (November
                        // 2026); the coach's Adjust wins over Claude's rating.
                        DrillAttributesCard(drill: currentDrill, onSave: { profile in
                            var updated = currentDrill
                            updated.tags = profile.replacing(in: updated.tags, byCoach: true)
                            dataManager.updateDrill(updated)
                        }, onReset: {
                            var updated = currentDrill
                            updated.tags = updated.tags.filter { !$0.hasPrefix(AttributeProfile.tagPrefix) }
                            dataManager.updateDrill(updated)
                        })
                        
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
                }
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showEditSheet) {
            AddEditDrillSheet(drill: currentDrill)
                .environmentObject(dataManager)
        }
        .fullScreenCover(item: $drawingEditor) { edit in
            JournalPlayStepEditor(drawing: edit.drawing) { drawing in
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
                .background(Color(.secondarySystemGroupedBackground),
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
                                .font(.caption.weight(.semibold))
                        }
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
                                .font(.caption.weight(.semibold))
                        }
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
    
    // MARK: - Compact Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background - more compact
            LinearGradient(
                colors: [categoryColor, categoryColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)
            
            // Smaller watermark icon
            Image(systemName: drill.category.icon)
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(.white.opacity(0.1))
                .offset(x: 220, y: -10)
            
            // Content - tighter spacing
            VStack(alignment: .leading, spacing: 6) {
                // Category + visibility as inline pills
                HStack(spacing: 6) {
                    Text(currentDrill.localizedCategory.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2))
                        .cornerRadius(4)

                    if let visibilityLabel {
                        Text(visibilityLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.22))
                            .cornerRadius(4)
                    }
                }
                
                // Drill name - single line with truncation
                Text(currentDrill.localizedName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Difficulty dots closer to name
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i < currentDrill.difficulty.level ? .white : .white.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                    Text(currentDrill.localizedDifficulty)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
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

    init(editing: DrillItem? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _category = State(initialValue: editing?.category ?? .skills)
        _difficulty = State(initialValue: editing?.difficulty ?? .beginner)
        _durationMinutes = State(initialValue: editing?.durationMinutes ?? 10)
        _description = State(initialValue: editing?.description ?? "")
        _instructions = State(initialValue: (editing?.instructions).flatMap { $0.isEmpty ? nil : $0 } ?? [""])
        _keyPoints = State(initialValue: (editing?.keyPoints).flatMap { $0.isEmpty ? nil : $0 } ?? [""])
        _minPlayers = State(initialValue: editing?.minPlayers ?? 1)
    }
    /// A court drawing made while creating the drill (Luther, November
    /// 2026): saved as the drill's first visual on Create.
    @State private var drawing: DrillDrawing?
    @State private var drawingOpen = false
    /// Return in the description asks Claude for the steps and key points
    /// (DrillWriter); the spinner beside "Description" is the only sign.
    @State private var writing = false
    @State private var lastWritten: DrillWriterResult?
    /// Claude's attribute rating from the same answer — saved as the drill's
    /// attr: tags unless the coach rated it themselves.
    @State private var writtenAttributes: AttributeProfile?
    
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

                // A drill's visuals are managed on its page once it exists.
                if editing == nil {
                    visualSection(isChinese: isChinese)
                }
            }
            .fullScreenCover(isPresented: $drawingOpen) {
                JournalPlayStepEditor(drawing: drawing ?? DrillDrawing.new()) { drawing = $0 }
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
    
    @ViewBuilder
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
            if let scores = result.attributes { writtenAttributes = AttributeProfile(array: scores) }
        }
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
        if let writtenAttributes, !updated.tags.contains(AttributeProfile.coachTag) {
            updated.tags = writtenAttributes.replacing(in: updated.tags, byCoach: false)
        }
        updated.updatedAt = Date()
        dataManager.updateDrill(updated)
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
        if let writtenAttributes { drill.tags = writtenAttributes.replacing(in: drill.tags, byCoach: false) }
        dataManager.addDrill(drill)
        dismiss()
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
