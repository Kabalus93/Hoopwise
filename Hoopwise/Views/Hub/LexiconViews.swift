import SwiftUI

// Hub → LEXICON: the coach's researched basketball lexicon (Models/
// Lexicon.swift). The home is a grid of sections; typing searches every term,
// other name and definition. An entry shows its definition, its rulebook
// values, the disputed meanings when it has them, the terms it mentions and
// its sources. The words are English as researched; the chrome is bilingual.

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

extension Lexicon.Section {
    var icon: String {
        switch title {
        case let t where t.hasPrefix("Court"): return "square.split.bottomrightquarter"
        case let t where t.hasPrefix("Positions"): return "person.2.fill"
        case let t where t.hasPrefix("Individual"): return "figure.basketball"
        case let t where t.hasPrefix("Screens"): return "arrow.triangle.turn.up.right.diamond"
        case let t where t.hasPrefix("Named actions"): return "arrow.left.arrow.right"
        case let t where t.hasPrefix("Sets"): return "circle.grid.2x2"
        case let t where t.hasPrefix("Offensive systems"): return "point.3.connected.trianglepath.dotted"
        case let t where t.hasPrefix("Transition"): return "hare.fill"
        case let t where t.hasPrefix("Man-to-man"): return "shield.lefthalf.filled"
        case let t where t.hasPrefix("Screen coverages"): return "shield.checkered"
        case let t where t.hasPrefix("Zones"): return "square.grid.3x3.middle.filled"
        case let t where t.hasPrefix("Rebounding"): return "arrow.up.circle"
        case let t where t.hasPrefix("Rules"): return "book.closed.fill"
        case let t where t.hasPrefix("Stats"): return "chart.bar.fill"
        case let t where t.hasPrefix("Slang"): return "quote.bubble.fill"
        case let t where t.hasPrefix("Disputed"): return "exclamationmark.bubble.fill"
        default: return "text.book.closed"
        }
    }

    var tint: Color {
        switch title {
        case let t where t.hasPrefix("Court") || t.hasPrefix("Positions"): return .teal
        case let t where t.hasPrefix("Individual") || t.hasPrefix("Screens"): return .orange
        case let t where t.hasPrefix("Named") || t.hasPrefix("Sets") || t.hasPrefix("Offensive") || t.hasPrefix("Transition"): return .blue
        case let t where t.hasPrefix("Man-to-man") || t.hasPrefix("Screen coverages") || t.hasPrefix("Zones") || t.hasPrefix("Rebounding"): return .red
        case let t where t.hasPrefix("Rules"): return .indigo
        case let t where t.hasPrefix("Stats"): return .green
        case let t where t.hasPrefix("Disputed"): return .pink
        default: return .purple
        }
    }
}

// MARK: - Home

struct LexiconScreen: View {
    private let lexicon = Lexicon.shared
    @State private var search = ""

    var body: some View {
        Group {
            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                home
            } else {
                results
            }
        }
        .navigationTitle(isChinese ? "术语词典" : "Lexicon")
        .searchable(text: $search, prompt: isChinese ? "搜索术语、别名、定义" : "Search terms, other names, definitions")
        .accessibilityIdentifier("lexicon.screen")
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isChinese
                     ? "\(lexicon.entryCount) 个术语：场地、位置、技术、掩护、战术、防守、规则、数据与俚语。术语与定义为英文，规则以 FIBA、NBA、NCAA 规则书为准。"
                     : "\(lexicon.entryCount) terms — court, positions, skills, screens, actions, sets, defenses, rules, stats and slang. Rules follow the FIBA, NBA and NCAA rulebooks; where they differ, each value is given.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(lexicon.sections) { section in
                        NavigationLink(destination: LexiconSectionView(section: section)) {
                            sectionTile(section)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lexicon.section")
                    }
                }
                NavigationLink(destination: LexiconSourcesView()) {
                    Label(isChinese ? "来源（\(lexicon.sources.count)）" : "Sources (\(lexicon.sources.count))", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionTile(_ section: Lexicon.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: section.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(section.tint)
                .frame(width: 40, height: 40)
                .background(section.tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 0)
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text(isChinese ? "\(section.entryCount) 条" : "\(section.entryCount) terms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
    }

    private var results: some View {
        let found = lexicon.search(search)
        return List {
            if found.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Section(isChinese ? "\(found.count) 个结果" : "\(found.count) results") {
                    ForEach(found) { item in
                        NavigationLink(destination: LexiconEntryView(item: item)) {
                            LexiconRow(entry: item.entry, kind: item.group.kind, place: item.section.title)
                        }
                        .accessibilityIdentifier("lexicon.result")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// A term in a list: name, other names, the definition's first lines.
struct LexiconRow: View {
    let entry: Lexicon.Entry
    let kind: Lexicon.Group.Kind
    var place: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.term).font(.body.weight(.semibold))
            if !entry.aka.isEmpty {
                Text(entry.aka).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let place {
                Text(place).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        if kind == .compare, let values = entry.values { return values.joined(separator: " · ") }
        return entry.definition
    }
}

// MARK: - A section

struct LexiconSectionView: View {
    let section: Lexicon.Section
    @State private var search = ""

    var body: some View {
        List {
            if !section.note.isEmpty && search.isEmpty {
                Section { Text(section.note).font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(section.groups) { group in
                let entries = filtered(group)
                if !entries.isEmpty {
                    Section {
                        if group.kind == .compare && search.isEmpty {
                            NavigationLink(destination: LexiconCompareView(section: section, group: group)) {
                                Label(isChinese ? "对照表" : "See the comparison table", systemImage: "tablecells")
                            }
                        }
                        ForEach(entries) { entry in
                            NavigationLink(destination: LexiconEntryView(item: Lexicon.Located(entry: entry, section: section, group: group))) {
                                LexiconRow(entry: entry, kind: group.kind)
                            }
                            .accessibilityIdentifier("lexicon.entry")
                        }
                    } header: {
                        if !group.title.isEmpty { Text(group.title) }
                    } footer: {
                        if !group.note.isEmpty && search.isEmpty { Text(group.note) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: isChinese ? "在本类中搜索" : "Search \(section.title.lowercased())")
    }

    private func filtered(_ group: Lexicon.Group) -> [Lexicon.Entry] {
        let words = Lexicon.fold(search).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return group.entries }
        return group.entries.filter { entry in
            let text = Lexicon.fold([entry.term, entry.aka, entry.definition] .joined(separator: " ") + (entry.values ?? []).joined(separator: " "))
            return words.allSatisfy(text.contains)
        }
    }
}

// MARK: - An entry

struct LexiconEntryView: View {
    let item: Lexicon.Located
    private let lexicon = Lexicon.shared

    var body: some View {
        let entry = item.entry
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(item.group.title.isEmpty ? item.section.title : "\(item.section.title) · \(item.group.title)",
                          systemImage: item.section.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.section.tint)
                    Text(entry.term)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.aka.isEmpty {
                        Text((isChinese ? "又称：" : "Also called: ") + entry.aka)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.definition.isEmpty {
                        Text(entry.definition)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityIdentifier("lexicon.definition")
            }

            if let values = entry.values, let columns = item.group.columns {
                Section(isChinese ? "各规则书" : "By rulebook") {
                    ForEach(Array(zip(columns, values)), id: \.0) { column, value in
                        LabeledContent(column) {
                            Text(value).multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            if let dispute = lexicon.dispute(for: item) {
                Section {
                    NavigationLink(destination: LexiconEntryView(item: dispute)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(isChinese ? "这个词有不止一种意思" : "This term means more than one thing", systemImage: "exclamationmark.bubble.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.pink)
                            Text(dispute.entry.definition).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }

            let related = lexicon.related(to: item)
            if !related.isEmpty {
                Section(isChinese ? "提到的术语" : "Terms it mentions") {
                    ForEach(related) { other in
                        NavigationLink(destination: LexiconEntryView(item: other)) {
                            LexiconRow(entry: other.entry, kind: other.group.kind, place: other.section.title)
                        }
                        .accessibilityIdentifier("lexicon.related")
                    }
                }
            }

            let sources = entry.sources.compactMap(lexicon.source)
            if !sources.isEmpty {
                Section(isChinese ? "来源" : "Sources") {
                    ForEach(sources) { LexiconSourceRow(source: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.term)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LexiconSourceRow: View {
    let source: Lexicon.Source

    var body: some View {
        if let url = URL(string: source.url) {
            Link(destination: url) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(source.n)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text(url.host() ?? source.url).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        } else {
            Text(source.title).font(.subheadline)
        }
    }
}

struct LexiconSourcesView: View {
    var body: some View {
        List {
            Section {
                ForEach(Lexicon.shared.sources) { LexiconSourceRow(source: $0) }
            } footer: {
                Text(isChinese ? "规则书是一手来源；教练网站和词汇表是二手来源。" : "Rulebooks are primary sources; coaching sites and glossaries are secondary.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isChinese ? "来源" : "Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - FIBA vs NBA vs NCAA

/// The rulebook comparison as a grid: one row per rule, one column per
/// rulebook. Scrolls sideways on a phone.
struct LexiconCompareView: View {
    let section: Lexicon.Section
    let group: Lexicon.Group

    var body: some View {
        let columns = group.columns ?? []
        ScrollView([.vertical, .horizontal]) {
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text(isChinese ? "规则" : "Rule").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(columns, id: \.self) { column in
                        Text(column).font(.caption.weight(.bold)).foregroundStyle(section.tint)
                    }
                }
                Divider()
                ForEach(group.entries) { entry in
                    GridRow {
                        Text(entry.term).font(.subheadline.weight(.semibold)).frame(width: 150, alignment: .leading)
                        ForEach(Array((entry.values ?? []).enumerated()), id: \.offset) { _, value in
                            Text(value).font(.subheadline).frame(width: 160, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
