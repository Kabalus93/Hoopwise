import SwiftUI

/// Editing a phase (18 Nov 2026, Luther: "when tapping on manage phases and
/// finally tapping a phase, nothing to be modified appears"): its name, what
/// it is about, its focus areas and its objectives. Dates stay with the chain
/// — Manage Phases' drag re-anchors them and moves the sessions inside, which
/// a single date field here could not do safely. Saves onto a COPY of the
/// stored phase (updateMicroCycle and its 2.7 words guard), never a rebuilt
/// record.
struct EditPhaseSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let phase: MicroCycle

    @State private var title: String
    @State private var summary: String
    @State private var focus: Set<TrainingFocus>
    @State private var objectives: [String]
    // Drills across the phase's upcoming sessions (PhaseDrillEditing).
    @State private var pickingDrill = false
    @State private var choosing: PhaseDrillChooser.Mode?
    @State private var drillsNote: String?
    /// Spreading a drill series over the phase (DrillSeries / SeriesSpread).
    @State private var spreading: DrillSeries?
    @State private var pickingSeries = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    init(phase: MicroCycle) {
        self.phase = phase
        _title = State(initialValue: phase.title)
        _summary = State(initialValue: phase.description ?? "")
        _focus = State(initialValue: Set(phase.focus))
        _objectives = State(initialValue: phase.objectives.isEmpty ? [""] : phase.objectives)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                drillsSection
                focusSection
                objectivesSection
            }
            .sheet(isPresented: $pickingDrill) { recurringPicker }
            .sheet(item: $choosing) { mode in
                PhaseDrillChooser(mode: mode, sessions: upcoming) { note in
                    drillsNote = note
                }
                .environmentObject(dataManager)
            }
            .sheet(isPresented: $pickingSeries) { seriesPicker }
            .sheet(item: $spreading) { series in
                SeriesSpreadSheet(series: series, sessions: upcoming) { note in drillsNote = note }
                    .environmentObject(dataManager)
            }
            .navigationTitle(isChinese ? "编辑阶段" : "Edit Phase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                        .accessibilityIdentifier("phase.edit.save")
                }
            }
        }
        .presentationSizing(.page)
    }

    // MARK: - Header

    /// The phase at a glance (18 Nov 2026, Luther: "the UI for edit phase is
    /// worth revisiting"): its number and when it runs, then its words.
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(isChinese ? "第\(phase.phaseNumber)阶段" : "PHASE \(phase.phaseNumber)")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                TextField(isChinese ? "阶段名称" : "Phase name", text: $title, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("phase.edit.title")
                TextField(isChinese ? "这一阶段练什么" : "What this phase is about", text: $summary, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2...6)
            }
            .padding(.vertical, 6)
        } footer: {
            Text(isChinese ? "日期跟随阶段顺序：在“管理阶段”中拖动可调整。" : "Dates follow the phase order — drag in Manage Phases to change them.")
        }
    }

    /// "Nov 4 – Dec 1 · 4 wks · 6 upcoming".
    private var metaLine: String {
        var parts: [String] = []
        if let start = phase.startDate, let end = phase.endDate {
            parts.append("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))")
        }
        parts.append(isChinese ? "\(phase.durationWeeks) 周" : "\(phase.durationWeeks) wk\(phase.durationWeeks == 1 ? "" : "s")")
        let count = upcoming.count
        parts.append(isChinese ? "\(count) 节待上" : "\(count) upcoming")
        return parts.joined(separator: " · ")
    }

    // MARK: - Focus

    /// Focus as toggle chips — eight full rows were most of the form.
    private var focusSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(TrainingFocus.allCases, id: \.self) { item in
                    let on = focus.contains(item)
                    Button {
                        if on { focus.remove(item) } else { focus.insert(item) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.caption.weight(.semibold))
                            Text(item.displayName).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.10), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("phase.focus.\(item.rawValue)")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(isChinese ? "重点" : "Focus")
        } footer: {
            Text(isChinese ? "生成课程计划和阶段平衡都会参考这些重点。" : "Generate Plan and the phase balance read these.")
        }
    }

    // MARK: - Objectives

    private var objectivesSection: some View {
        Section {
            ForEach(objectives.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor.opacity(0.14), in: Circle())
                    TextField(isChinese ? "目标" : "Objective", text: $objectives[i], axis: .vertical)
                }
            }
            .onDelete { objectives.remove(atOffsets: $0) }
            Button {
                objectives.append("")
            } label: {
                Label(isChinese ? "添加目标" : "Add objective", systemImage: "plus")
            }
        } header: {
            Text(isChinese ? "目标" : "Objectives")
        }
    }

    // MARK: - Drills in this phase

    /// The phase's sessions a bulk edit may change (upcoming, scheduled).
    private var upcoming: [SessionEvent] {
        PhaseDrillEditing.editableSessions(dataManager.sessionEvents, phaseId: phase.id)
    }

    private func drill(_ id: UUID) -> DrillItem? { dataManager.drills.first { $0.id == id } }

    /// Each drill: its name, its block, and a dot per upcoming session —
    /// filled where it is planned — so "which sessions" reads at a glance.
    private var drillsSection: some View {
        let sessions = upcoming
        let usage = PhaseDrillEditing.usage(in: sessions)
        return Section {
            if sessions.isEmpty {
                Text(isChinese ? "这个阶段没有待上的课程。" : "No upcoming sessions in this phase.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usage) { use in
                    Button {
                        if let d = drill(use.drillId) { choosing = .remove(d) }
                    } label: {
                        drillRow(use, sessions: sessions)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("phase.drill.remove")
                }
                Button {
                    pickingDrill = true
                } label: {
                    Label(isChinese ? "添加固定训练" : "Add a recurring drill", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("phase.drill.add")
                if DrillSeries.all(in: dataManager.drills).contains(where: { !$0.levels.isEmpty }) {
                    Button {
                        pickingSeries = true
                    } label: {
                        Label(isChinese ? "排入一个系列" : "Add a series", systemImage: "stairs")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier("phase.series.add")
                }
            }
        } header: {
            HStack {
                Text(isChinese ? "这个阶段的训练" : "Drills in this phase")
                Spacer()
                if !sessions.isEmpty {
                    Text(isChinese ? "\(sessions.count) 节待上" : "\(sessions.count) upcoming")
                        .font(.caption)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let drillsNote {
                    Label(drillsNote, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(isChinese ? "点一个训练可从全部或部分课程中移除。只改动待上的课程，改动立即生效。"
                               : "Tap a drill to take it out of all or some sessions. Only upcoming sessions change, at once.")
            }
        }
    }

    private func drillRow(_ use: PhaseDrillEditing.Usage, sessions: [SessionEvent]) -> some View {
        let warmup = sessions.contains { $0.curriculum.warmupDrillIds.contains(use.drillId) }
        let item = drill(use.drillId)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item?.localizedName ?? (isChinese ? "已删除的训练" : "Deleted drill"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(warmup ? (isChinese ? "热身" : "Warm-up") : (isChinese ? "技能" : "Skills"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                HStack(spacing: 4) {
                    ForEach(sessions) { session in
                        Circle()
                            .fill(use.sessionIds.contains(session.id) ? Color.accentColor : Color.primary.opacity(0.12))
                            .frame(width: 8, height: 8)
                    }
                    Text("\(use.sessionIds.count)/\(sessions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isChinese ? "在 \(use.sessionIds.count)/\(sessions.count) 节待上课程中"
                                              : "In \(use.sessionIds.count) of \(sessions.count) upcoming sessions")
            }
            Spacer(minLength: 8)
            Image(systemName: "minus.circle")
                .font(.title3)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    /// Which series to spread over the phase.
    private var seriesPicker: some View {
        NavigationStack {
            List(DrillSeries.all(in: dataManager.drills).filter { !$0.levels.isEmpty }) { series in
                Button {
                    pickingSeries = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { spreading = series }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "stairs")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(series.name).foregroundStyle(.primary)
                            Text(isChinese ? "\(series.levels.count) 级 · \(upcoming.count) 节待上"
                                           : "\(series.levels.count) levels · over \(upcoming.count) upcoming sessions")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("phase.series.choice")
            }
            .navigationTitle(isChinese ? "排入一个系列" : "Add a series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { pickingSeries = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var recurringPicker: some View {
        NavigationStack {
            DrillsLibraryView(pick: DrillsLibraryView.Pick(
                title: isChinese ? "添加固定训练" : "Add a recurring drill",
                initialAge: nil,
                initialBlock: .routine,
                isAdded: { _ in false },
                add: { drill in
                    pickingDrill = false
                    // The chooser opens once the picker is gone.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { choosing = .add(drill) }
                }))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isChinese ? "取消" : "Cancel") { pickingDrill = false }
                    }
                }
        }
        .environmentObject(dataManager)
    }

    private func save() {
        var updated = phase
        updated.title = trimmedTitle
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = text.isEmpty ? nil : text
        // Keep the focus in its canonical order.
        updated.focus = TrainingFocus.allCases.filter { focus.contains($0) }
        updated.objectives = objectives.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        dataManager.updateMicroCycle(updated)
        HapticFeedback.notification(.success)
        dismiss()
    }
}


/// Which of the phase's upcoming sessions a drill goes into (Add) or comes
/// out of (Remove): every one preselected, a tap to leave one out.
struct PhaseDrillChooser: View {
    enum Mode: Identifiable {
        case add(DrillItem)
        case remove(DrillItem)
        var id: String {
            switch self {
            case .add(let d): "add-\(d.id)"
            case .remove(let d): "remove-\(d.id)"
            }
        }
        var drill: DrillItem {
            switch self {
            case .add(let d), .remove(let d): d
            }
        }
        var isAdd: Bool { if case .add = self { true } else { false } }
    }

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let sessions: [SessionEvent]
    let done: (String) -> Void

    @State private var chosen: Set<UUID> = []
    @State private var block: PhaseDrillEditing.Block = .warmup

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private func holds(_ session: SessionEvent) -> Bool {
        let c = session.curriculum
        return c.warmupDrillIds.contains(mode.drill.id) || c.skillDrillIds.contains(mode.drill.id)
    }

    /// The sessions this edit can touch: Add — those without the drill;
    /// Remove — those with it.
    private var candidates: [SessionEvent] {
        sessions.filter { mode.isAdd ? !holds($0) : holds($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if mode.isAdd {
                    Section {
                        Picker(isChinese ? "放在" : "Put it in", selection: $block) {
                            Text(isChinese ? "热身" : "Warm-up").tag(PhaseDrillEditing.Block.warmup)
                            Text(isChinese ? "技能" : "Skills").tag(PhaseDrillEditing.Block.skills)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    if candidates.isEmpty {
                        Text(mode.isAdd
                             ? (isChinese ? "每节待上的课都已有这个训练。" : "Every upcoming session already has it.")
                             : (isChinese ? "没有待上的课程包含这个训练。" : "No upcoming session has it."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { session in
                        Button {
                            if chosen.contains(session.id) { chosen.remove(session.id) } else { chosen.insert(session.id) }
                        } label: {
                            HStack {
                                Image(systemName: chosen.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(session.id) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.startTime.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                        .foregroundStyle(.primary)
                                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("phase.chooser.session")
                    }
                } header: {
                    HStack {
                        Text(isChinese ? "课程" : "Sessions")
                        Spacer()
                        if !candidates.isEmpty {
                            Button(chosen.count == candidates.count ? (isChinese ? "全不选" : "None")
                                                                    : (isChinese ? "全选" : "All")) {
                                chosen = chosen.count == candidates.count ? [] : Set(candidates.map(\.id))
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle(mode.isAdd ? (isChinese ? "添加：" : "Add: ") + mode.drill.localizedName
                                        : (isChinese ? "移除：" : "Remove: ") + mode.drill.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isAdd ? (isChinese ? "添加" : "Add") : (isChinese ? "移除" : "Remove"), role: mode.isAdd ? nil : .destructive) {
                        apply()
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("phase.chooser.apply")
                }
            }
            .onAppear { chosen = Set(candidates.map(\.id)) }
        }
    }

    private func apply() {
        var changed = 0
        for id in chosen {
            // The STORED session, so nothing the page holds is written back.
            guard var session = dataManager.sessionEvents.first(where: { $0.id == id }) else { continue }
            let before = session.curriculum
            session.curriculum = mode.isAdd
                ? PhaseDrillEditing.adding(mode.drill.id, to: before, block: block)
                : PhaseDrillEditing.removing(mode.drill.id, from: before)
            guard session.curriculum != before else { continue }
            dataManager.updateSessionEvent(session, keepLiveFields: true)
            changed += 1
        }
        HapticFeedback.notification(.success)
        let name = mode.drill.localizedName
        done(mode.isAdd
             ? (isChinese ? "已把「\(name)」加入 \(changed) 节课" : "Added “\(name)” to \(changed) session\(changed == 1 ? "" : "s")")
             : (isChinese ? "已从 \(changed) 节课移除「\(name)」" : "Removed “\(name)” from \(changed) session\(changed == 1 ? "" : "s")"))
        dismiss()
    }
}


/// A series laid over the phase's upcoming sessions, easiest first: the
/// preview says which level each session teaches (and reviews), then Apply
/// writes every session (SeriesSpread.applying — re-spreading never doubles).
struct SeriesSpreadSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let series: DrillSeries
    let sessions: [SessionEvent]
    let done: (String) -> Void

    @State private var block: PhaseDrillEditing.Block
    @State private var overflow: SeriesSpread.Overflow = .stop

    init(series: DrillSeries, sessions: [SessionEvent], done: @escaping (String) -> Void) {
        self.series = series
        self.sessions = sessions
        self.done = done
        _block = State(initialValue: series.block)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var plan: [SeriesSpread.Slot] { SeriesSpread.plan(levels: series.levels, sessions: sessions.count, overflow: overflow) }
    private func name(_ id: UUID) -> String {
        dataManager.drills.first { $0.id == id }?.localizedName ?? (isChinese ? "已删除的训练" : "Deleted drill")
    }
    private func level(_ id: UUID) -> Int { series.level(of: id) ?? 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(isChinese ? "排进" : "Put it in", selection: $block) {
                        Text(isChinese ? "热身" : "Warm-up").tag(PhaseDrillEditing.Block.warmup)
                        Text(isChinese ? "技能" : "Skills").tag(PhaseDrillEditing.Block.skills)
                    }
                    .pickerStyle(.segmented)
                    if series.levels.count > sessions.count {
                        Picker(isChinese ? "级数多于课程" : "More levels than sessions", selection: $overflow) {
                            Text(isChinese ? "到能到的那一级为止" : "Stop where the phase ends").tag(SeriesSpread.Overflow.stop)
                            Text(isChinese ? "有的课教两级" : "Two levels in some sessions").tag(SeriesSpread.Overflow.doubleUp)
                        }
                        .accessibilityIdentifier("series.overflow")
                    }
                } footer: {
                    let reached = SeriesSpread.reached(plan, levels: series.levels)
                    Text(isChinese ? "\(sessions.count) 节课，到第 \(reached)/\(series.levels.count) 级。每级的第一节课先用上一级热身复习。"
                                   : "\(sessions.count) sessions, up to level \(reached) of \(series.levels.count). The first session of each level opens with the one before as a short review.")
                }

                Section {
                    ForEach(Array(zip(sessions, plan).enumerated()), id: \.offset) { _, pair in
                        let (session, slot) = pair
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.subheadline.weight(.medium))
                                Text(session.startTime.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 92, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                if let review = slot.review {
                                    Label(isChinese ? "复习 \(level(review)) · \(name(review))" : "Review \(level(review)) · \(name(review))",
                                          systemImage: "arrow.counterclockwise")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(slot.teach, id: \.self) { id in
                                    HStack(spacing: 8) {
                                        Text("\(level(id))")
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 22, height: 22)
                                            .background(Color.accentColor.opacity(0.14), in: Circle())
                                        Text(name(id)).font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(isChinese ? "每节课" : "Session by session")
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "排入" : "Apply", action: apply)
                        .disabled(sessions.isEmpty)
                        .accessibilityIdentifier("series.apply")
                }
            }
        }
    }

    private func apply() {
        var laid = series
        laid.block = block
        var changed = 0
        for (session, slot) in zip(sessions, plan) {
            guard var stored = dataManager.sessionEvents.first(where: { $0.id == session.id }) else { continue }
            let before = stored.curriculum
            stored.curriculum = SeriesSpread.applying(slot, series: laid, to: before)
            guard stored.curriculum != before else { continue }
            dataManager.updateSessionEvent(stored, keepLiveFields: true)
            changed += 1
        }
        HapticFeedback.notification(.success)
        done(isChinese ? "「\(series.name)」已排入 \(changed) 节课" : "Spread “\(series.name)” over \(changed) session\(changed == 1 ? "" : "s")")
        dismiss()
    }
}
