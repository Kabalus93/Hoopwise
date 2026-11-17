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
                Section {
                    TextField(isChinese ? "阶段名称" : "Phase name", text: $title)
                        .font(.headline)
                        .accessibilityIdentifier("phase.edit.title")
                    TextField(isChinese ? "这一阶段练什么" : "What this phase is about", text: $summary, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text(isChinese ? "第\(phase.phaseNumber)阶段" : "Phase \(phase.phaseNumber)")
                } footer: {
                    if let start = phase.startDate, let end = phase.endDate {
                        Text((isChinese ? "日期：" : "Dates: ")
                             + "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted)) · "
                             + (isChinese ? "在“管理阶段”中拖动可调整顺序和日期。" : "Drag in Manage Phases to change the order and dates."))
                    }
                }

                drillsSection

                Section {
                    ForEach(TrainingFocus.allCases, id: \.self) { item in
                        Button {
                            if focus.contains(item) { focus.remove(item) } else { focus.insert(item) }
                        } label: {
                            HStack {
                                Label(item.displayName, systemImage: item.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if focus.contains(item) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text(isChinese ? "重点" : "Focus")
                } footer: {
                    Text(isChinese ? "生成课程计划和阶段平衡都会参考这些重点。" : "Generate Plan and the phase balance read these.")
                }

                Section {
                    ForEach(objectives.indices, id: \.self) { i in
                        TextField(isChinese ? "目标" : "Objective", text: $objectives[i], axis: .vertical)
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
            .sheet(isPresented: $pickingDrill) { recurringPicker }
            .sheet(item: $choosing) { mode in
                PhaseDrillChooser(mode: mode, sessions: upcoming) { note in
                    drillsNote = note
                }
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
    }

    // MARK: - Drills in this phase

    /// The phase's sessions a bulk edit may change (upcoming, scheduled).
    private var upcoming: [SessionEvent] {
        PhaseDrillEditing.editableSessions(dataManager.sessionEvents, phaseId: phase.id)
    }

    private func drill(_ id: UUID) -> DrillItem? { dataManager.drills.first { $0.id == id } }

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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drill(use.drillId)?.localizedName ?? (isChinese ? "已删除的训练" : "Deleted drill"))
                                    .foregroundStyle(.primary)
                                Text(isChinese ? "在 \(use.sessionIds.count)/\(sessions.count) 节待上课程中"
                                               : "In \(use.sessionIds.count) of \(sessions.count) upcoming sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("phase.drill.remove")
                }
                Button {
                    pickingDrill = true
                } label: {
                    Label(isChinese ? "添加固定训练" : "Add a recurring drill", systemImage: "plus")
                }
                .accessibilityIdentifier("phase.drill.add")
            }
        } header: {
            Text(isChinese ? "这个阶段的训练" : "Drills in this phase")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let drillsNote {
                    Label(drillsNote, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(isChinese ? "点一个训练可从全部或部分课程中移除。只改动待上的课程，已上的课保留原计划。改动立即生效。"
                               : "Tap a drill to remove it from all or some sessions. Only upcoming sessions change — past ones keep their plan. Changes apply at once.")
            }
        }
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
