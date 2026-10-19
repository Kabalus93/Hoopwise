import SwiftUI

/// The drills screen, built on the activity library (October 2026, Luther):
/// pick an AGE, a session BLOCK and an activity TYPE. "Mine" lists the
/// drills coaches create themselves. Rule options live under the Game block
/// and are read from the library directly — they are not drills and never
/// reach session planning.
struct DrillsLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var showingAddDrill = false
    /// "U8" … or "mine".
    @AppStorage("library.age") private var ageChoice = ActivityAge.u8.rawValue
    @AppStorage("library.includeEarlier") private var includeEarlier = false
    @State private var block: ActivityBlock = .routine
    @State private var type: ActivityType?
    @State private var showGuidance = false
    @State private var openRule: LibraryActivity?
    @State private var mineCategory: DrillCategory?

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

    private func matchesSearch(_ text: String...) -> Bool {
        searchText.isEmpty || text.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// Library drills for the chosen ages and block (all types), library order.
    private var blockPairs: [(activity: LibraryActivity, drill: DrillItem)] {
        let byId = Dictionary(visibleDrills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ActivityLibrary.shared.plannable.compactMap { activity in
            guard ages.contains(activity.age), activity.block == block,
                  let drill = byId[activity.id],
                  matchesSearch(drill.name, drill.localizedName, drill.description,
                                activity.nameZh ?? "", activity.howItRunsZh ?? "") else { return nil }
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
                && matchesSearch($0.name, $0.howItRuns, $0.nameZh ?? "", $0.howItRunsZh ?? "")
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
            .filter { matchesSearch($0.name, $0.localizedName, $0.description) }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ageChips
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // The switch lives in the ⓘ sheet; while it is on, say so here
                // so the list is never filtered by something out of sight.
                if includeEarlier, let age, age != .u6 {
                    earlierAgesNote(age)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            if let age {
                libraryContent(age)
            } else {
                mineContent
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isChinese ? "训练库" : "Activity library")
        .searchable(text: $searchText, prompt: isChinese ? "搜索训练" : "Search")
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddDrill = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(DrillLocalization.L("Add Drill"))
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

    // MARK: Age chips

    private var ageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActivityAge.allCases) { a in
                    chip(a.title, selected: ageChoice == a.rawValue) { ageChoice = a.rawValue }
                }
                chip(isChinese ? "我的" : "Mine", selected: age == nil, icon: "person.crop.circle") {
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
        Section {
            Picker(isChinese ? "环节" : "Block", selection: $block) {
                ForEach(ActivityBlock.allCases) { b in
                    Text(b.title).tag(b)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if typeCounts.count > 1 {
                typeChips
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        if shownPairs.isEmpty && rules.isEmpty {
            Section {
                Text(searchText.isEmpty
                     ? (isChinese ? "这个环节暂无内容" : "Nothing in this block for this age")
                     : (isChinese ? "没有匹配的结果" : "No matches"))
                    .foregroundStyle(.secondary)
            }
        }

        if !shownPairs.isEmpty && type != .rules {
            Section {
                ForEach(shownPairs, id: \.activity.key) { pair in
                    NavigationLink(destination: DrillDetailView(drill: pair.drill)) {
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

    // MARK: Mine

    @ViewBuilder
    private var mineContent: some View {
        if mine.isEmpty && mineCategory == nil {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "figure.basketball")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(isChinese ? "还没有自己的训练" : "No drills of your own yet")
                        .font(.headline)
                    Text(isChinese ? "你创建的训练会出现在这里。" : "Drills you create appear here.")
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
                    NavigationLink(destination: DrillDetailView(drill: drill)) { DrillRow(drill: drill) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteButton(drill) }
                }
            } header: {
                Text(isChinese ? "我的训练" : "My drills")
            }
        }
    }
}

// MARK: - Library rows

private struct LibraryRow: View {
    let activity: LibraryActivity
    let drill: DrillItem
    let showAge: Bool

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
                Text([showAge ? activity.age.rawValue : nil, activity.type.title, activity.sourceText]
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
    @State private var showingMediaPicker = false
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
        .sheet(isPresented: $showingMediaPicker) {
            DrillMediaPicker(
                drillId: currentDrill.id,
                existingMediaCount: currentDrill.media.count
            ) { newMedia in
                dataManager.addDrillMedia(newMedia, toDrillId: currentDrill.id)
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
            DrillMediaViewer(media: currentDrill.media, initialIndex: wrapper.value)
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
        let media = currentDrill.media
        if media.isEmpty {
            Button {
                HapticFeedback.impact(.light)
                showingMediaPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.accent)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "添加图片/视频" : "Add a visual")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(isChinese
                             ? "让训练更容易记住，球场也能离线看"
                             : "Photos & videos make this easier to recall — offline-ready")
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
            .padding(.horizontal, AppTheme.spacing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(isChinese ? "图片与视频" : "Visuals")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(media.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        showingMediaEditor = true
                    } label: {
                        Text(isChinese ? "编辑" : "Edit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.accent)
                    }
                }
                .padding(.horizontal, AppTheme.spacing)

                DrillMediaCarousel(
                    media: media,
                    tileSize: 132,
                    horizontalPadding: AppTheme.spacing,
                    onTap: { _, index in
                        HapticFeedback.impact(.light)
                        viewerInitialIndex = index
                    },
                    onAdd: {
                        HapticFeedback.impact(.light)
                        showingMediaPicker = true
                    },
                    onDelete: { item in
                        HapticFeedback.impact(.medium)
                        dataManager.deleteDrillMedia(item)
                    },
                    onEditDiagram: { item in
                        HapticFeedback.impact(.light)
                        editingDiagram = item
                    }
                )
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
    
    @State private var name = ""
    @State private var category: DrillCategory = .skills
    @State private var difficulty: DifficultyLevel = .beginner
    @State private var durationMinutes = 10
    @State private var description = ""
    @State private var instructions: [String] = [""]
    @State private var keyPoints: [String] = [""]
    @State private var minPlayers = 1
    
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
                
                Section(isChinese ? "描述" : "Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
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
            }
            .navigationTitle(isChinese ? "新训练" : "New Drill")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create") {
                        createDrill()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createDrill() {
        let drill = DrillItem(
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: description,
            instructions: instructions.filter { !$0.isEmpty },
            keyPoints: keyPoints.filter { !$0.isEmpty },
            minPlayers: minPlayers
        )
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
            if let drill {
                EditDrillView(drill: drill)
            } else {
                AddDrillView()
            }
        }
    }
}

// MARK: - iOS Edit Drill View
private struct EditDrillView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let drill: DrillItem
    
    @State private var name: String
    @State private var category: DrillCategory
    @State private var difficulty: DifficultyLevel
    @State private var durationMinutes: Int
    @State private var description: String
    @State private var instructions: [String]
    @State private var keyPoints: [String]
    @State private var minPlayers: Int
    @State private var newInstruction = ""
    @State private var newKeyPoint = ""
    
    init(drill: DrillItem) {
        self.drill = drill
        _name = State(initialValue: drill.name)
        _category = State(initialValue: drill.category)
        _difficulty = State(initialValue: drill.difficulty)
        _durationMinutes = State(initialValue: drill.durationMinutes)
        _description = State(initialValue: drill.description)
        _instructions = State(initialValue: drill.instructions.isEmpty ? [""] : drill.instructions)
        _keyPoints = State(initialValue: drill.keyPoints.isEmpty ? [""] : drill.keyPoints)
        _minPlayers = State(initialValue: drill.minPlayers)
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "基础信息" : "Basic Info")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        TextField(isChinese ? "训练名称" : "Drill Name", text: $name)
                            .padding(12)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)

                        HStack(spacing: 10) {
                            Picker(isChinese ? "类别" : "Category", selection: $category) {
                                ForEach(DrillCategory.allCases, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)

                            Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                                ForEach(DifficultyLevel.allCases, id: \.self) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                        }

                        valueAdjustRow(
                            title: isChinese ? "时长" : "Duration",
                            valueText: isChinese ? "\(durationMinutes) 分钟" : "\(durationMinutes) min",
                            canDecrement: durationMinutes > 1,
                            decrement: { durationMinutes -= 1 },
                            canIncrement: durationMinutes < 60,
                            increment: { durationMinutes += 1 }
                        )

                        valueAdjustRow(
                            title: isChinese ? "最少人数" : "Min Players",
                            valueText: "\(minPlayers)",
                            canDecrement: minPlayers > 1,
                            decrement: { minPlayers -= 1 },
                            canIncrement: minPlayers < 20,
                            increment: { minPlayers += 1 }
                        )
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "描述" : "Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        TextEditor(text: $description)
                            .font(.system(size: 14))
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "说明" : "Instructions")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 8) {
                                TextField(
                                    isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)",
                                    text: Binding(
                                        get: { instructions[index] },
                                        set: { instructions[index] = $0 }
                                    )
                                )
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                                Button {
                                    instructions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .frame(width: 30, height: 30)
                                        .background(AppTheme.surfaceColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(isChinese ? "添加步骤" : "Add step", text: $newInstruction)
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                            Button {
                                let clean = newInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                instructions.append(clean)
                                newInstruction = ""
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isChinese ? "添加" : "Add")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "要点" : "Key Points")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        ForEach(Array(keyPoints.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 8) {
                                TextField(
                                    isChinese ? "要点 \(index + 1)" : "Point \(index + 1)",
                                    text: Binding(
                                        get: { keyPoints[index] },
                                        set: { keyPoints[index] = $0 }
                                    )
                                )
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                                Button {
                                    keyPoints.remove(at: index)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .frame(width: 30, height: 30)
                                        .background(AppTheme.surfaceColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(isChinese ? "添加要点" : "Add key point", text: $newKeyPoint)
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                            Button {
                                let clean = newKeyPoint.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                keyPoints.append(clean)
                                newKeyPoint = ""
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isChinese ? "添加" : "Add")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "编辑训练" : "Edit Drill")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        saveDrill()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveDrill() {
        var updated = drill
        updated.name = name
        updated.category = category
        updated.difficulty = difficulty
        updated.durationMinutes = durationMinutes
        updated.description = description
        updated.instructions = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.keyPoints = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.minPlayers = minPlayers
        updated.updatedAt = Date()
        
        dataManager.updateDrill(updated)
        dismiss()
    }

    private func valueAdjustRow(
        title: String,
        valueText: String,
        canDecrement: Bool,
        decrement: @escaping () -> Void,
        canIncrement: Bool,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            Text("\(title): \(valueText)")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 0) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canDecrement ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 34, height: 30)
                }
                .disabled(!canDecrement)

                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 1, height: 18)

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canIncrement ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 34, height: 30)
                }
                .disabled(!canIncrement)
            }
            .background(AppTheme.surfaceColor)
            .clipShape(Capsule())
        }
    }
}
#endif

#Preview {
    DrillsLibraryView()
        .environmentObject(DataManager.shared)
}
