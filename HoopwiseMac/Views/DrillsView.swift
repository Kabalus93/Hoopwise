import SwiftUI

// MARK: - Drills Library
struct DrillsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var search = ""
    @State private var category: DrillCategory? = nil
    @State private var difficulty: DifficultyLevel? = nil
    @State private var selected: DrillItem.ID?

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 320, idealWidth: 360)
        } detail: {
            if let id = selected, let drill = dataManager.cachedDrills.first(where: { $0.id == id }) {
                DrillDetailView(drill: drill).id(drill.id)
            } else {
                EmptyDetail(systemImage: "figure.basketball", title: "Select a Drill")
            }
        }
        .onAppear { autoSelect() }
        .onChange(of: category) { _, _ in autoSelect() }
        .onChange(of: difficulty) { _, _ in autoSelect() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search drills", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(DrillCategory?.none)
                    ForEach(DrillCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(Optional(c))
                    }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small)

                Picker("Difficulty", selection: $difficulty) {
                    Text("Any Level").tag(DifficultyLevel?.none)
                    ForEach(DifficultyLevel.allCases, id: \.self) { d in
                        Text(d.displayName).tag(Optional(d))
                    }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small)

                Spacer()
                Text("\(filtered.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            List(selection: $selected) {
                if filtered.isEmpty {
                    Text("No drills match.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(grouped, id: \.category) { group in
                        Section {
                            ForEach(group.drills) { drill in
                                DrillListRow(drill: drill).tag(drill.id)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: group.category.icon).foregroundStyle(Color(hex: group.category.color))
                                Text(group.category.displayName).font(.caption.weight(.semibold))
                                Text("\(group.drills.count)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Drill Library")
    }

    private struct CategoryGroup {
        let category: DrillCategory
        let drills: [DrillItem]
    }

    private var filtered: [DrillItem] {
        var result = dataManager.cachedDrills
        if let category { result = result.filter { $0.category == category } }
        if let difficulty { result = result.filter { $0.difficulty == difficulty } }
        if !search.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.description.localizedCaseInsensitiveContains(search)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private var grouped: [CategoryGroup] {
        let buckets = Dictionary(grouping: filtered) { $0.category }
        return DrillCategory.allCases.compactMap { c in
            guard let d = buckets[c], !d.isEmpty else { return nil }
            return CategoryGroup(category: c, drills: d)
        }
    }

    private func autoSelect() {
        if let s = selected, dataManager.cachedDrills.contains(where: { $0.id == s }) { return }
        selected = filtered.first?.id
    }
}

private struct DrillListRow: View {
    let drill: DrillItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: drill.category.icon)
                .foregroundStyle(Color(hex: drill.category.color))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(drill.name).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(drill.durationMinutes)m").font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(drill.difficulty.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 1) {
                ForEach(0..<drill.difficulty.stars, id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color(hex: drill.difficulty.color))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct DrillDetailView: View {
    let drill: DrillItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                statRow

                if !drill.description.isEmpty {
                    SectionBlock(title: "Description") {
                        Text(drill.description).font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                if !drill.instructions.isEmpty {
                    SectionBlock(title: "Instructions") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(drill.instructions.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .frame(width: 22, height: 22)
                                        .background(Color.accentColor.opacity(0.18), in: Circle())
                                        .foregroundStyle(Color.accentColor)
                                    Text(step).font(.subheadline)
                                    Spacer()
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                if !drill.keyPoints.isEmpty {
                    SectionBlock(title: "Key Points") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(drill.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                                    Text(point).font(.subheadline)
                                    Spacer()
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                if !drill.equipmentNeeded.isEmpty {
                    SectionBlock(title: "Equipment") {
                        HStack(spacing: 8) {
                            ForEach(drill.equipmentNeeded, id: \.self) { item in
                                Label(item, systemImage: "shippingbox.fill")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.regularMaterial, in: .capsule)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }

                if let url = drill.videoUrl, !url.isEmpty {
                    SectionBlock(title: "Video") {
                        Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                            Label(url, systemImage: "play.rectangle.fill")
                                .font(.subheadline)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(drill.name)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: drill.category.color).gradient)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: drill.category.icon).font(.system(size: 32, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(drill.name).font(.system(size: 28, weight: .bold))
                HStack(spacing: 12) {
                    Label(drill.category.displayName, systemImage: drill.category.icon)
                    Label(drill.difficulty.displayName, systemImage: "speedometer")
                    Label("\(drill.durationMinutes) min", systemImage: "timer")
                }
                .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
            Spacer()
        }
    }

    private var statRow: some View {
        let players: String = {
            if let max = drill.maxPlayers, max > 0 { return "\(drill.minPlayers)–\(max)" }
            return "\(drill.minPlayers)+"
        }()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatPill(title: "Duration", value: "\(drill.durationMinutes)m")
            StatPill(title: "Difficulty", value: drill.difficulty.displayName)
            StatPill(title: "Players", value: players)
            StatPill(title: "Steps", value: "\(drill.instructions.count)")
        }
    }
}
