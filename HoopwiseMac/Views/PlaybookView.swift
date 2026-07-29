import SwiftUI

// MARK: - Playbook
struct PlaybookMacView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var category: PlayCategory? = nil
    @State private var search = ""
    @State private var selected: Play.ID?

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 320, idealWidth: 360)
        } detail: {
            if let id = selected, let play = dataManager.plays.first(where: { $0.id == id }) {
                PlayDetailView(play: play).id(play.id)
            } else {
                EmptyDetail(systemImage: "book.pages.fill", title: "Select a Play")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search plays", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(12)

            Picker("Category", selection: $category) {
                Text("All Categories").tag(PlayCategory?.none)
                ForEach(PlayCategory.allCases, id: \.self) { c in
                    Label(c.displayName, systemImage: c.icon).tag(Optional(c))
                }
            }
            .pickerStyle(.menu).labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            List(selection: $selected) {
                if filtered.isEmpty {
                    Text("No plays yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(grouped, id: \.category) { group in
                        Section {
                            ForEach(group.plays) { play in
                                HStack(spacing: 10) {
                                    Image(systemName: play.category.icon)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(play.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Text("\(play.steps.count) steps").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .tag(play.id)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text(group.category.displayName).font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Playbook")
    }

    private struct CategoryGroup {
        let category: PlayCategory
        let plays: [Play]
    }

    private var filtered: [Play] {
        var result = dataManager.plays
        if let category { result = result.filter { $0.category == category } }
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return result.sorted { $0.name < $1.name }
    }

    private var grouped: [CategoryGroup] {
        let buckets = Dictionary(grouping: filtered) { $0.category }
        return PlayCategory.allCases.compactMap { c in
            guard let plays = buckets[c], !plays.isEmpty else { return nil }
            return CategoryGroup(category: c, plays: plays)
        }
    }
}

private struct PlayDetailView: View {
    let play: Play
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if !play.description.isEmpty {
                    SectionBlock(title: "Description") {
                        Text(play.description).font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                if !play.steps.isEmpty {
                    SectionBlock(title: "Steps") {
                        VStack(spacing: 8) {
                            ForEach(play.steps.sorted(by: { $0.stepNumber < $1.stepNumber })) { step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(step.stepNumber)")
                                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                                        .frame(width: 32, height: 32)
                                        .background(Color.accentColor.opacity(0.18), in: Circle())
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.description).font(.subheadline)
                                        if let key = step.keyPoint, !key.isEmpty {
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                                                Text(key).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(play.name)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: play.category.icon).font(.system(size: 32, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(play.name).font(.system(size: 28, weight: .bold))
                Label(play.category.displayName, systemImage: play.category.icon)
                    .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
            Spacer()
        }
    }
}
