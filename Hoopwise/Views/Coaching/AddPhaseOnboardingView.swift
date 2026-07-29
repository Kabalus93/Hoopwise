import SwiftUI

// MARK: - Add Phase Onboarding View
/// One-question-per-screen flow for adding (or editing) a phase, mirroring
/// `AddProgramOnboardingView`. Replaces the legacy two-field `AddPhaseView`.
///
/// Three entry shapes:
/// 1. **New phase, blank** — coach taps "Add Phase" on a program. Steps run
///    template → basics → duration → focus → objectives → load → review.
/// 2. **New phase, prefilled from a template** — coach picked a template in
///    step 0; the rest of the flow is review-style with editable defaults.
/// 3. **Edit existing phase** — caller passes `editing:`. Step 0 is skipped.
struct AddPhaseOnboardingView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let nextPhaseNumber: Int
    /// When set, the flow edits this phase in place instead of creating a new one.
    let editing: MicroCycle?

    init(program: Program, nextPhaseNumber: Int, editing: MicroCycle? = nil) {
        self.program = program
        self.nextPhaseNumber = nextPhaseNumber
        self.editing = editing

        if let edit = editing {
            _title = State(initialValue: edit.title)
            _weeks = State(initialValue: edit.durationWeeks)
            _focus = State(initialValue: Set(edit.focus))
            _objectives = State(initialValue: edit.objectives.isEmpty ? [""] : edit.objectives)
            _intensity = State(initialValue: edit.intensity)
            _volume = State(initialValue: edit.volume)
            _coachingNote = State(initialValue: edit.description ?? "")
            _suggestedDrillIds = State(initialValue: edit.suggestedDrillIds)
        }
    }

    // MARK: - State

    @State private var step: Step = .template
    @State private var selectedTemplate: PhaseTemplate?

    @State private var title: String = ""
    @State private var weeks: Int = 3
    @State private var focus: Set<TrainingFocus> = []
    @State private var objectives: [String] = [""]
    @State private var intensity: Int = 5
    @State private var volume: Int = 5
    @State private var coachingNote: String = ""
    @State private var suggestedDrillIds: [UUID] = []

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var isSpanish: Bool { LocalizationManager.shared.currentLanguage == .spanish }
    private var isEditing: Bool { editing != nil }
    private var availableTemplates: [PhaseTemplate] {
        PhaseTemplateStore.shared.defaultPhases(for: program.ageGroup)
    }

    enum Step: Int, CaseIterable {
        case template, basics, duration, focus, objectives, load, review

        var title: LocalizedTriple {
            switch self {
            case .template:   return .init(en: "Start from a template?", zh: "从模板开始？", es: "¿Empezar desde una plantilla?")
            case .basics:     return .init(en: "Phase name", zh: "阶段名称", es: "Nombre de la fase")
            case .duration:   return .init(en: "How long?", zh: "持续多久？", es: "¿Cuánto dura?")
            case .focus:      return .init(en: "Focus areas", zh: "训练重点", es: "Áreas de enfoque")
            case .objectives: return .init(en: "Objectives", zh: "目标", es: "Objetivos")
            case .load:       return .init(en: "Intensity & volume", zh: "强度与训练量", es: "Intensidad y volumen")
            case .review:     return .init(en: "Ready to add", zh: "准备添加", es: "Listo para añadir")
            }
        }

        var subtitle: LocalizedTriple {
            switch self {
            case .template:   return .init(en: "FEB defaults are tailored by age. You can edit anything later.",
                                          zh: "FEB 默认会按年龄给出建议。所有内容稍后可改。",
                                          es: "Las plantillas FEB se adaptan a la edad. Puedes editar todo después.")
            case .basics:     return .init(en: "Give this phase a short, descriptive name.",
                                          zh: "给这个阶段起个简短描述。",
                                          es: "Pon un nombre corto y descriptivo.")
            case .duration:   return .init(en: "FEB phases typically run 2–4 weeks.",
                                          zh: "FEB 阶段通常持续 2–4 周。",
                                          es: "Las fases FEB suelen durar 2–4 semanas.")
            case .focus:      return .init(en: "Pick the technical and tactical themes for this block.",
                                          zh: "选择本阶段的技术与战术主题。",
                                          es: "Elige los temas técnicos y tácticos del bloque.")
            case .objectives: return .init(en: "What does success look like? Tap a suggestion or write your own.",
                                          zh: "成功是什么样子？点击建议或自己输入。",
                                          es: "¿Qué es éxito? Toca una sugerencia o escribe la tuya.")
            case .load:       return .init(en: "Calibrate effort level. FEB recommendations appear below the sliders.",
                                          zh: "校准训练强度。滑杆下方有 FEB 推荐值。",
                                          es: "Calibra la carga. Las recomendaciones FEB aparecen bajo los deslizadores.")
            case .review:     return .init(en: "Quick check before saving.",
                                          zh: "保存前快速确认。",
                                          es: "Revisión rápida antes de guardar.")
            }
        }
    }

    /// Steps actually shown in the flow (template skipped when editing or
    /// when no presets are available for this age group).
    private var activeSteps: [Step] {
        if isEditing { return Array(Step.allCases.dropFirst()) }
        if availableTemplates.isEmpty { return Array(Step.allCases.dropFirst()) }
        return Step.allCases
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                Group {
                    switch step {
                    case .template:   templateStep
                    case .basics:     basicsStep
                    case .duration:   durationStep
                    case .focus:      focusStep
                    case .objectives: objectivesStep
                    case .load:       loadStep
                    case .review:     reviewStep
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                bottomBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(en: "Cancel", zh: "取消", es: "Cancelar")) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if let i = activeSteps.firstIndex(of: step) {
                        Text("\(i + 1) / \(activeSteps.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                if let initial = activeSteps.first { step = initial }
            }
        }
    }

    // MARK: - Progress + Bottom bar

    private var progressBar: some View {
        let i = activeSteps.firstIndex(of: step) ?? 0
        let progress = CGFloat(i + 1) / CGFloat(max(activeSteps.count, 1))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let i = activeSteps.firstIndex(of: step), i > 0 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        step = activeSteps[i - 1]
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button(action: advance) {
                Text(continueLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(.bar)
    }

    private var continueLabel: String {
        if step == .review {
            return isEditing
                ? localized(en: "Save Changes", zh: "保存更改", es: "Guardar cambios")
                : localized(en: "Add Phase", zh: "添加阶段", es: "Añadir fase")
        }
        return localized(en: "Continue", zh: "继续", es: "Continuar")
    }

    private var canAdvance: Bool {
        switch step {
        case .basics:   return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .duration: return weeks > 0
        default:        return true
        }
    }

    private func advance() {
        if step == .review {
            commit()
            return
        }
        guard let i = activeSteps.firstIndex(of: step), i < activeSteps.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = activeSteps[i + 1]
        }
    }

    // MARK: - Steps

    private func stepHeader(_ s: Step) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.title.resolve())
                .font(.largeTitle.weight(.bold))
            Text(s.subtitle.resolve())
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var templateStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader(.template)

                VStack(spacing: 8) {
                    templateOption(
                        title: localized(en: "Build from scratch", zh: "从零开始", es: "Empezar desde cero"),
                        subtitle: localized(en: "Start with empty fields.",
                                            zh: "从空白字段开始。",
                                            es: "Comenzar con campos vacíos."),
                        icon: "square.dashed",
                        isSelected: selectedTemplate == nil
                    ) {
                        selectedTemplate = nil
                    }

                    if !availableTemplates.isEmpty {
                        Text(localized(
                            en: "FEB templates · \(program.ageGroup.rawValue)",
                            zh: "FEB 模板 · \(program.ageGroup.rawValue)",
                            es: "Plantillas FEB · \(program.ageGroup.rawValue)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)

                        ForEach(availableTemplates) { template in
                            templateOption(
                                title: template.title.resolve(),
                                subtitle: templateSummary(template),
                                icon: "rectangle.stack.fill",
                                isSelected: selectedTemplate?.id == template.id
                            ) {
                                applyTemplate(template)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 40)
            }
        }
    }

    private func templateOption(title: String, subtitle: String, icon: String,
                                isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func templateSummary(_ t: PhaseTemplate) -> String {
        let weeksLabel = localized(en: "\(t.weeks)w", zh: "\(t.weeks)周", es: "\(t.weeks)sem")
        let focusLabel = t.focus.prefix(2).map { $0.displayName }.joined(separator: ", ")
        return [weeksLabel, focusLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func applyTemplate(_ t: PhaseTemplate) {
        selectedTemplate = t
        title = t.title.resolve()
        weeks = t.weeks
        focus = Set(t.focus)
        objectives = t.objectives.map { $0.resolve() }
        if objectives.isEmpty { objectives = [""] }
        intensity = t.intensity
        volume = t.volume
        coachingNote = t.coachingNote.resolve()
    }

    private var basicsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader(.basics)

                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        localized(en: "e.g. Tactical Block", zh: "例：战术阶段", es: "p. ej. Bloque táctico"),
                        text: $title
                    )
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(14)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    Text(localized(
                        en: "Phase \(nextPhaseNumber) of this program",
                        zh: "本计划第 \(nextPhaseNumber) 个阶段",
                        es: "Fase \(nextPhaseNumber) de este programa"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private var durationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader(.duration)

                VStack(spacing: 12) {
                    Stepper(value: $weeks, in: 1...12) {
                        HStack {
                            Text(localized(en: "Duration", zh: "持续时间", es: "Duración"))
                                .font(.body)
                            Spacer()
                            Text("^[\(weeks) week](inflect: true)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 40)
            }
        }
    }

    private var focusStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader(.focus)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(TrainingFocus.allCases, id: \.self) { f in
                        focusChip(f)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 40)
            }
        }
    }

    private func focusChip(_ f: TrainingFocus) -> some View {
        let isSelected = focus.contains(f)
        return Button {
            if isSelected { focus.remove(f) } else { focus.insert(f) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: f.icon)
                    .font(.callout)
                Text(f.displayName)
                    .font(.body.weight(.medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private var objectivesStep: some View {
        let suggestions = FEBPhasePresets.objectiveSuggestions(
            for: program.ageGroup,
            focus: Array(focus)
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader(.objectives)

                VStack(spacing: 10) {
                    ForEach(objectives.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            TextField(
                                localized(en: "Objective \(i + 1)",
                                          zh: "目标 \(i + 1)",
                                          es: "Objetivo \(i + 1)"),
                                text: Binding(
                                    get: { objectives[i] },
                                    set: { objectives[i] = $0 }
                                )
                            )
                            .textFieldStyle(.plain)
                            if objectives.count > 1 {
                                Button {
                                    objectives.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                    }

                    if objectives.count < 5 {
                        Button {
                            objectives.append("")
                        } label: {
                            Label(
                                localized(en: "Add objective", zh: "添加目标", es: "Añadir objetivo"),
                                systemImage: "plus.circle.fill"
                            )
                            .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                if !suggestions.isEmpty {
                    Text(localized(
                        en: "Suggestions for \(program.ageGroup.rawValue)",
                        zh: "\(program.ageGroup.rawValue) 推荐",
                        es: "Sugerencias para \(program.ageGroup.rawValue)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                let value = s.resolve()
                                if let empty = objectives.firstIndex(where: { $0.isEmpty }) {
                                    objectives[empty] = value
                                } else if objectives.count < 5 {
                                    objectives.append(value)
                                }
                            } label: {
                                HStack {
                                    Text(s.resolve())
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "plus")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private var loadStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(.load)

                VStack(spacing: 12) {
                    sliderRow(
                        label: localized(en: "Intensity", zh: "强度", es: "Intensidad"),
                        value: $intensity
                    )
                    sliderRow(
                        label: localized(en: "Volume", zh: "训练量", es: "Volumen"),
                        value: $volume
                    )
                }
                .padding(.horizontal, 16)

                Text(loadHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                Spacer(minLength: 40)
            }
        }
    }

    private func sliderRow(label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(value.wrappedValue) / 10")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            )
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }

    private var loadHint: String {
        // Pull a hint from the picked template; otherwise stay generic.
        if let note = selectedTemplate?.coachingNote.resolve(), !note.isEmpty {
            return note
        }
        return localized(
            en: "FEB rule of thumb: technique blocks run 6/7, competition peaks at 8/9, recovery drops to 3/4.",
            zh: "FEB 经验：技术阶段 6/7，比赛阶段 8/9，恢复阶段 3/4。",
            es: "Regla FEB: técnica 6/7, competición 8/9, recuperación 3/4."
        )
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader(.review)

                VStack(spacing: 0) {
                    summaryRow(label: localized(en: "Name", zh: "名称", es: "Nombre"), value: title.isEmpty ? "—" : title)
                    Divider().padding(.leading, 16)
                    summaryRow(label: localized(en: "Duration", zh: "时长", es: "Duración"), value: localized(en: "\(weeks) weeks", zh: "\(weeks) 周", es: "\(weeks) semanas"))
                    Divider().padding(.leading, 16)
                    summaryRow(label: localized(en: "Focus", zh: "重点", es: "Enfoque"),
                               value: focus.isEmpty ? "—" : focus.map { $0.displayName }.joined(separator: ", "))
                    Divider().padding(.leading, 16)
                    summaryRow(label: localized(en: "Objectives", zh: "目标", es: "Objetivos"),
                               value: objectives.filter { !$0.isEmpty }.isEmpty ? "—" :
                                "\(objectives.filter { !$0.isEmpty }.count)")
                    Divider().padding(.leading, 16)
                    summaryRow(label: localized(en: "Intensity", zh: "强度", es: "Intensidad"), value: "\(intensity) / 10")
                    Divider().padding(.leading, 16)
                    summaryRow(label: localized(en: "Volume", zh: "训练量", es: "Volumen"), value: "\(volume) / 10")
                }
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)

                if !coachingNote.isEmpty {
                    Text(coachingNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(14)
    }

    // MARK: - Commit

    private func commit() {
        let cleanObjectives = objectives.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let edit = editing {
            var updated = edit
            updated.title = title
            updated.durationWeeks = weeks
            updated.focus = Array(focus)
            updated.objectives = cleanObjectives
            updated.intensity = intensity
            updated.volume = volume
            updated.description = coachingNote.isEmpty ? nil : coachingNote
            updated.suggestedDrillIds = matchSuggestedDrills(for: Array(focus))
            updated.updatedAt = Date()
            dataManager.updateMicroCycle(updated)
        } else {
            // Anchor the new phase at the end of the existing chain so calendar
            // order stays consistent with phaseNumber.
            let existing = dataManager.microCycles
                .filter { $0.programId == program.id }
                .sorted { $0.phaseNumber < $1.phaseNumber }
            let chainAnchor: Date = existing.last?.endDate
                ?? program.endDate
                ?? program.startDate
                ?? Calendar.current.startOfDay(for: Date())
            let startDate = Calendar.current.date(byAdding: .day, value: 1, to: chainAnchor) ?? chainAnchor
            let endDate = Calendar.current.date(byAdding: .day, value: weeks * 7, to: startDate) ?? startDate

            let phase = MicroCycle(
                programId: program.id,
                phaseNumber: nextPhaseNumber,
                title: title,
                focus: Array(focus),
                durationWeeks: weeks,
                description: coachingNote.isEmpty ? nil : coachingNote,
                objectives: cleanObjectives,
                suggestedDrillIds: matchSuggestedDrills(for: Array(focus)),
                startDate: startDate,
                endDate: endDate,
                intensity: intensity,
                volume: volume
            )
            dataManager.addMicroCycle(phase)
            // Materialize the phase's sessions on the program's recurring
            // weekday(s) so the new phase shows up in the calendar
            // immediately. No-op if the program has no recurring days.
            dataManager.materializeSessions(for: phase)
        }
        dismiss()
    }

    /// Best-effort match: pick drill IDs whose categories or tags overlap with
    /// the picked focus areas. Empty when the coach has no matching drills.
    private func matchSuggestedDrills(for focus: [TrainingFocus]) -> [UUID] {
        guard !focus.isEmpty else { return [] }
        let focusSet = Set(focus)
        return dataManager.drills.compactMap { drill -> UUID? in
            let categoryFocus = mapCategoryToFocus(drill.category)
            return focusSet.contains(categoryFocus) ? drill.id : nil
        }
    }

    private func mapCategoryToFocus(_ category: DrillCategory) -> TrainingFocus {
        switch category {
        case .shooting:     return .shooting
        case .offense:      return .teamPlay
        case .defense:      return .defense
        case .skills:       return .ballHandling
        case .conditioning: return .conditioning
        case .warmup:       return .conditioning
        case .cooldown:     return .recovery
        }
    }

    // MARK: - Localization helper

    private func localized(en: String, zh: String, es: String) -> String {
        switch LocalizationManager.shared.currentLanguage {
        case .english: return en
        case .chinese: return zh
        case .spanish: return es
        }
    }
}
