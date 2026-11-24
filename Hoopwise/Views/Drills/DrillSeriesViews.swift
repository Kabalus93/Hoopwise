import SwiftUI

// The series screens (18 Nov 2026, Luther: drill series — DrillSeries.swift):
// every series as a list, one series as an editable ladder of levels, and the
// "Part of a series" card on a drill's page. Every change is written at once
// through updateDrill on the series record.

/// Every series, with + New Series.
struct DrillSeriesListView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var creating = false
    @State private var newName = ""
    @State private var openId: UUID?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let all = DrillSeries.all(in: dataManager.drills)
        List {
            if all.isEmpty {
                ContentUnavailableView(isChinese ? "还没有系列" : "No series yet",
                                       systemImage: "stairs",
                                       description: Text(isChinese ? "系列是从易到难的一组训练，如原地运球 → 行进间运球 → 双球。"
                                                                   : "A ladder of drills, easiest first — stationary dribble → moving → two balls."))
            }
            ForEach(all) { series in
                NavigationLink(destination: DrillSeriesView(seriesId: series.id)) {
                    SeriesRow(series: series)
                }
                .accessibilityIdentifier("series.row")
            }
        }
        .navigationTitle(isChinese ? "训练系列" : "Series")
        .navigationDestination(item: $openId) { id in DrillSeriesView(seriesId: id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label(isChinese ? "新系列" : "New Series", systemImage: "plus") }
                    .accessibilityIdentifier("series.new")
            }
        }
        .alert(isChinese ? "新系列" : "New Series", isPresented: $creating) {
            TextField(isChinese ? "名称" : "Name", text: $newName)
            Button(isChinese ? "创建" : "Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let series = DrillSeries(name: name)
                dataManager.addDrill(series.applied(to: DrillItem(id: series.id, name: name, category: .skills)))
                newName = ""
                openId = series.id
            }
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { newName = "" }
        }
    }
}

private struct SeriesRow: View {
    let series: DrillSeries
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "stairs")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(series.name).font(.body.weight(.medium))
                Text(isChinese ? "\(series.levels.count) 级 · \(series.block == .warmup ? "热身" : "技能")"
                               : "\(series.levels.count) level\(series.levels.count == 1 ? "" : "s") · \(series.block == .warmup ? "Warm-up" : "Skills")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One series: its name and what it builds, the block it plans into, and the
/// ladder — numbered levels, drag to reorder, swipe to remove, + Add a level.
struct DrillSeriesView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let seriesId: UUID

    @State private var addingLevel = false
    @State private var confirmingDelete = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var record: DrillItem? { dataManager.drills.first { $0.id == seriesId } }
    private var series: DrillSeries? { record.flatMap(DrillSeries.init(drill:)) }
    private func drill(_ id: UUID) -> DrillItem? { dataManager.drills.first { $0.id == id } }

    private func write(_ change: (inout DrillSeries) -> Void) {
        guard let record, var s = DrillSeries(drill: record) else { return }
        change(&s)
        var updated = s.applied(to: record)
        updated.updatedAt = Date()
        dataManager.updateDrill(updated)
    }

    var body: some View {
        Group {
            if let series {
                List {
                    Section {
                        TextField(isChinese ? "名称" : "Name", text: Binding(get: { series.name },
                                                                             set: { v in write { $0.name = v } }))
                            .font(.title3.weight(.semibold))
                            .accessibilityIdentifier("series.name")
                        TextField(isChinese ? "它练什么、怎么递进" : "What it builds, and how it climbs",
                                  text: Binding(get: { series.summary }, set: { v in write { $0.summary = v } }),
                                  axis: .vertical)
                            .lineLimit(1...4)
                            .foregroundStyle(.secondary)
                        Picker(isChinese ? "排进" : "Plans into", selection: Binding(get: { series.block },
                                                                                     set: { v in write { $0.block = v } })) {
                            Text(isChinese ? "热身" : "Warm-up").tag(PhaseDrillEditing.Block.warmup)
                            Text(isChinese ? "技能" : "Skills").tag(PhaseDrillEditing.Block.skills)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        ForEach(Array(series.levels.enumerated()), id: \.element) { i, id in
                            NavigationLink(destination: drill(id).map { DrillDetailView(drill: $0) }) {
                                levelRow(i, id)
                            }
                            .accessibilityIdentifier("series.level")
                        }
                        .onMove { from, to in write { $0.levels.move(fromOffsets: from, toOffset: to) } }
                        .onDelete { offsets in write { $0.levels.remove(atOffsets: offsets) } }
                        Button { addingLevel = true } label: {
                            Label(isChinese ? "添加一级" : "Add a level", systemImage: "plus.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityIdentifier("series.addLevel")
                    } header: {
                        Text(isChinese ? "从易到难" : "Easiest first")
                    } footer: {
                        Text(isChinese ? "点“编辑”可拖动排序；左滑移出系列（训练本身保留）。"
                                       : "Edit to drag levels into order; swipe to take one out (the drill itself stays).")
                    }

                    Section {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(isChinese ? "删除系列" : "Delete Series", systemImage: "trash")
                        }
                    } footer: {
                        Text(isChinese ? "只删除系列，各级训练保留在训练库中。" : "Only the series goes — its drills stay in the library.")
                    }
                }
                .navigationTitle(series.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Edit shows the drag handles for reordering levels.
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            } else {
                ContentUnavailableView(isChinese ? "系列已删除" : "Series deleted", systemImage: "stairs")
            }
        }
        .sheet(isPresented: $addingLevel) {
            NavigationStack {
                DrillsLibraryView(pick: DrillsLibraryView.Pick(
                    title: isChinese ? "添加一级" : "Add a level",
                    initialAge: nil,
                    initialBlock: series?.block == .skills ? .compete : .routine,
                    isAdded: { id in series?.levels.contains(id) ?? false },
                    add: { picked in
                        write { if !$0.levels.contains(picked.id) { $0.levels.append(picked.id) } }
                        addingLevel = false
                    }))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(isChinese ? "取消" : "Cancel") { addingLevel = false }
                        }
                    }
            }
            .environmentObject(dataManager)
        }
        .confirmationDialog(isChinese ? "删除这个系列？" : "Delete this series?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button(isChinese ? "删除系列" : "Delete Series", role: .destructive) {
                if let record { dataManager.deleteDrill(record) }
                dismiss()
            }
        }
    }

    private func levelRow(_ i: Int, _ id: UUID) -> some View {
        let item = drill(id)
        return HStack(spacing: 12) {
            Text("\(i + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.localizedName ?? (isChinese ? "已删除的训练" : "Deleted drill"))
                    .font(.body.weight(.medium))
                if let item {
                    Text(isChinese ? "\(item.durationMinutes) 分钟" : "\(item.durationMinutes) min")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// On a drill's page: the series it is a level of, with the levels around it.
struct DrillSeriesCard: View {
    @EnvironmentObject var dataManager: DataManager
    let drillId: UUID

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private func drill(_ id: UUID) -> DrillItem? { dataManager.drills.first { $0.id == id } }

    var body: some View {
        let memberships = DrillSeries.containing(drillId, in: dataManager.drills)
        if !memberships.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(memberships, id: \.series.id) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(destination: DrillSeriesView(seriesId: item.series.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: "stairs").foregroundStyle(Color.accentColor)
                                Text(isChinese ? "\(item.series.name) · 第 \(item.level)/\(item.series.levels.count) 级"
                                               : "\(item.series.name) · Level \(item.level) of \(item.series.levels.count)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            neighbour(item.series, at: item.level - 2, label: isChinese ? "上一级" : "Previous")
                            neighbour(item.series, at: item.level, label: isChinese ? "下一级" : "Next")
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.filmCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("drill.seriesCard")
        }
    }

    @ViewBuilder
    private func neighbour(_ series: DrillSeries, at index: Int, label: String) -> some View {
        if series.levels.indices.contains(index), let d = drill(series.levels[index]) {
            NavigationLink(destination: DrillDetailView(drill: d)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(label) · \(index + 1)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(d.localizedName).font(.caption.weight(.medium)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
