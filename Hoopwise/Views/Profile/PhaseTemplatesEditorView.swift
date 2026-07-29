import SwiftUI

// MARK: - Phase Templates Editor
/// Settings → Coaching → Phase Templates. Lets the coach author per-age
/// phase chains that override the FEB defaults inside `AddPhaseOnboardingView`
/// and the "Generate phases" affordance. Empty when the coach hasn't
/// authored anything; the FEB chain is then served straight from
/// `FEBPhasePresets`.
struct PhaseTemplatesEditorView: View {
    @StateObject private var store = PhaseTemplateStore.shared
    @State private var presentingNewFor: AgeGroup?
    @State private var editing: UserPhaseTemplate?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        List {
            ForEach(AgeGroup.allCases, id: \.self) { age in
                ageSection(for: age)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(isChinese ? "训练阶段模板" : "Phase Templates")
        .sheet(item: $editing) { template in
            PhaseTemplateDetailView(template: template) { updated in
                store.save(updated)
            }
        }
    }

    private func ageSection(for age: AgeGroup) -> some View {
        let userTemplates = store.userTemplates(for: age)
        return Section {
            ForEach(userTemplates) { template in
                Button { editing = template } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(localized(
                                en: "\(template.phases.count) phases · custom",
                                zh: "\(template.phases.count) 个阶段 · 自定义",
                                es: "\(template.phases.count) fases · personalizada"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        store.delete(template)
                    } label: {
                        Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                    }
                }
            }

            if userTemplates.isEmpty {
                Text(localized(
                    en: "Using FEB defaults (\(FEBPhasePresets.phases(for: age).count) phases)",
                    zh: "使用 FEB 默认配置（\(FEBPhasePresets.phases(for: age).count) 个阶段）",
                    es: "Usando los valores FEB (\(FEBPhasePresets.phases(for: age).count) fases)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                let template = store.seedFromFEB(
                    name: localized(
                        en: "My \(age.rawValue) plan",
                        zh: "\(age.rawValue) 我的方案",
                        es: "Mi plan \(age.rawValue)"),
                    age: age
                )
                editing = template
            } label: {
                Label(
                    localized(en: "New from FEB defaults",
                              zh: "基于 FEB 创建副本",
                              es: "Nuevo a partir de FEB"),
                    systemImage: "plus.circle"
                )
            }
        } header: {
            Text("\(age.rawValue) · \(age.displayName)")
        }
    }

    private func localized(en: String, zh: String, es: String) -> String {
        switch LocalizationManager.shared.currentLanguage {
        case .english: return en
        case .chinese: return zh
        case .spanish: return es
        }
    }
}

// MARK: - Detail editor
/// Edits the phases inside a `UserPhaseTemplate`. Add / remove / reorder
/// phases; tap a phase to edit its title (other fields stay editable in the
/// onboarding flow when the template is applied).
private struct PhaseTemplateDetailView: View {
    let template: UserPhaseTemplate
    let onSave: (UserPhaseTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phases: [PhaseTemplate]

    init(template: UserPhaseTemplate, onSave: @escaping (UserPhaseTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template.name)
        _phases = State(initialValue: template.phases)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isChinese ? "模板名称" : "Template name", text: $name)
                } header: {
                    Text(isChinese ? "名称" : "Name")
                }

                Section {
                    ForEach($phases) { $phase in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(isChinese ? "阶段名称" : "Phase name",
                                      text: Binding(
                                        get: { phase.title.en },
                                        set: { phase.title.en = $0 }
                                      ))
                                .font(.body.weight(.medium))
                            HStack {
                                Stepper("\(phase.weeks) wk", value: $phase.weeks, in: 1...12)
                                    .font(.caption)
                                Spacer()
                                Text(phase.focus.prefix(2).map { $0.displayName }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        phases.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        phases.remove(atOffsets: offsets)
                    }

                    Button {
                        phases.append(PhaseTemplate(
                            title: LocalizedTriple(en: "New Phase", zh: "新阶段", es: "Nueva fase"),
                            weeks: 2,
                            focus: [.shooting],
                            intensity: 5, volume: 5
                        ))
                    } label: {
                        Label(isChinese ? "添加阶段" : "Add phase", systemImage: "plus.circle")
                    }
                } header: {
                    Text(isChinese ? "阶段（共 \(phases.count) 个）" : "Phases (\(phases.count))")
                } footer: {
                    Text(isChinese
                         ? "拖动重排，左滑删除。在程序中应用模板时可微调每个字段。"
                         : "Drag to reorder, swipe to delete. Per-phase fields are editable when the template is applied to a program.")
                }
            }
            .navigationTitle(isChinese ? "编辑模板" : "Edit Template")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        var updated = template
                        updated.name = name
                        updated.phases = phases
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
    }
}
