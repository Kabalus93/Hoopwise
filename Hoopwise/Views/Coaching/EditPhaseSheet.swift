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
