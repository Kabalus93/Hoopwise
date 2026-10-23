import SwiftUI

// MARK: - Edit Enrolled Students View
struct EditEnrolledStudentsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var program: Program
    @Binding var selectedIds: Set<UUID>
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(dataManager.students) { student in
                    HStack {
                        Text(student.primaryDisplayName)
                        Spacer()
                        if selectedIds.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIds.contains(student.id) {
                            selectedIds.remove(student.id)
                        } else {
                            selectedIds.insert(student.id)
                        }
                    }
                }
            }
            .navigationTitle("Edit Enrolled Students")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updatedProgram = program
                        updatedProgram.enrolledStudentIds = Array(selectedIds)
                        dataManager.updateProgram(updatedProgram)
                        dismiss()
                    }
                }
            }
        }
    }
}

// `AddPhaseView` was the legacy two-field form. Superseded by
// `AddPhaseOnboardingView`. Removed during the FEB-aligned phase redesign.

// MARK: - Edit Program View
/// Full-surface program editor. Mirrors what `AddProgramOnboardingView`
/// captures during creation but in a single `Form` for revision. Edits are
/// staged on a local `draft` and only committed via Save, so Cancel reverts.
struct EditProgramView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var program: Program

    /// Local working copy. Bound directly to the form fields so partial edits
    /// don't leak back through the @Binding until the coach confirms Save.
    @State private var draft: Program

    /// Optional override field. When blank, the saved name falls through to
    /// the synthesised `Location · Age` form (see `Program.resolvedDisplayName`).
    @State private var customName: String = ""

    /// Mirrors the `hasEndDate` toggle from creation flow — `Program.endDate`
    /// is optional and we want a clean two-state UI.
    @State private var hasEndDate: Bool

    /// Pending schedule-delta surfaced after Save when the coach changed the
    /// recurring days. Drives the confirmation dialog that offers to backfill
    /// missing sessions on added days and/or cancel future sessions on
    /// removed days.
    @State private var pendingScheduleDelta: ScheduleDelta?

    private struct ScheduleDelta: Identifiable {
        let id = UUID()
        let added: [Weekday]
        let removed: [Weekday]
    }

    init(program: Binding<Program>) {
        self._program = program
        let snapshot = program.wrappedValue
        self._draft = State(initialValue: snapshot)
        self._customName = State(initialValue: snapshot.hasCoachAuthoredName ? snapshot.name : "")
        self._hasEndDate = State(initialValue: snapshot.endDate != nil)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// Synthesised name preview shown when the coach leaves the Name field
    /// blank — must match what the model would derive at display time.
    private var autoNamePreview: String {
        let parts = [draft.locationName, draft.ageGroup.rawValue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? draft.ageGroup.rawValue : parts.joined(separator: " · ")
    }

    private var canSave: Bool {
        // Either valid name choice, plus end date sanity if active.
        if hasEndDate, let end = draft.endDate, let start = draft.startDate, end < start {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                scheduleSection
                setupSection
                statusSection
                skillTargetsSection
            }
            .navigationTitle(isChinese ? "编辑训练计划" : "Edit Program")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                scheduleDeltaTitle,
                isPresented: Binding(
                    get: { pendingScheduleDelta != nil },
                    set: { if !$0 { pendingScheduleDelta = nil; dismiss() } }
                ),
                titleVisibility: .visible,
                presenting: pendingScheduleDelta
            ) { delta in
                // A swap (Saturday → Sunday) moves the classes, plans and all.
                if !delta.added.isEmpty, delta.added.count == delta.removed.count {
                    Button(moveButtonLabel(for: delta)) {
                        dataManager.moveSessions(forProgramId: draft.id, from: delta.removed, to: delta.added)
                        pendingScheduleDelta = nil
                        dismiss()
                    }
                }
                if !delta.added.isEmpty {
                    Button(generateButtonLabel(for: delta.added)) {
                        applySchedule(addedDays: delta.added, removedDays: [])
                    }
                }
                if !delta.removed.isEmpty {
                    Button(cancelButtonLabel(for: delta.removed), role: .destructive) {
                        applySchedule(addedDays: [], removedDays: delta.removed)
                    }
                }
                if !delta.added.isEmpty && !delta.removed.isEmpty {
                    Button(isChinese ? "全部应用" : "Do both") {
                        applySchedule(addedDays: delta.added, removedDays: delta.removed)
                    }
                }
                Button(isChinese ? "暂不调整" : "Skip", role: .cancel) {
                    pendingScheduleDelta = nil
                    dismiss()
                }
            } message: { delta in
                Text(scheduleDeltaMessage(for: delta))
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            TextField(autoNamePreview, text: $customName)
                .textInputAutocapitalization(.words)
            TextField(
                isChinese ? "描述（可选）" : "Description (optional)",
                text: Binding(
                    get: { draft.description ?? "" },
                    set: { draft.description = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...6)
        } header: {
            Text(isChinese ? "名称" : "Name")
        } footer: {
            Text(isChinese
                 ? "留空则使用「\(autoNamePreview)」。"
                 : "Leave blank to use “\(autoNamePreview)”.")
        }
    }

    private var scheduleSection: some View {
        Section {
            // Day-of-week multi-select. Native checkmark-style toggles
            // inside the Form so it matches Reminders / Calendar idioms.
            ForEach(Weekday.allCases, id: \.self) { day in
                let isOn = draft.recurringDays.contains(day)
                Button {
                    toggle(day)
                } label: {
                    HStack {
                        Text(localizedDay(day))
                            .foregroundStyle(.primary)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            DatePicker(
                isChinese ? "默认时间" : "Default time",
                selection: Binding(
                    get: { draft.defaultSessionTime ?? Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date() },
                    set: { draft.defaultSessionTime = $0 }
                ),
                displayedComponents: .hourAndMinute
            )

            Stepper(
                value: $draft.defaultSessionDurationMinutes,
                in: 15...240,
                step: 15
            ) {
                HStack {
                    Text(isChinese ? "课时长度" : "Session length")
                    Spacer()
                    Text(isChinese
                         ? "\(draft.defaultSessionDurationMinutes) 分钟"
                         : "\(draft.defaultSessionDurationMinutes) min")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(isChinese ? "时间安排" : "Schedule")
        } footer: {
            Text(isChinese
                 ? "时间、时长和场地的改动会同步到所有即将进行的课程；单独改过的课程保持不变。"
                 : "Time, length and venue changes apply to every upcoming session, except ones you changed on their own.")
        }
    }

    private var setupSection: some View {
        Section {
            Picker(isChinese ? "类型" : "Type", selection: $draft.programType) {
                ForEach(ProgramType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            Picker(isChinese ? "年龄组" : "Age group", selection: $draft.ageGroup) {
                ForEach(AgeGroup.allCases, id: \.self) { age in
                    Text(age.displayName).tag(age)
                }
            }

            Picker(isChinese ? "场地" : "Location", selection: locationBinding) {
                Text(isChinese ? "无" : "None").tag(UUID?.none)
                ForEach(dataManager.locations) { location in
                    Text(location.name).tag(UUID?.some(location.id))
                }
            }

            if draft.programType == .school {
                let activeSchools = dataManager.schools.filter { $0.isActive }
                if activeSchools.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "building.columns")
                            .foregroundStyle(.tertiary)
                        Text(isChinese
                             ? "请先在「机构 → 学校」中添加学校"
                             : "Add a school under Org → Schools first")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker(isChinese ? "学校" : "School", selection: $draft.schoolId) {
                        Text(isChinese ? "未指定" : "Unassigned").tag(UUID?.none)
                        ForEach(activeSchools) { school in
                            Text(school.displayName).tag(UUID?.some(school.id))
                        }
                    }
                }
            }

            let coaches = dataManager.activeStaffCoaches
            if !coaches.isEmpty {
                Picker(isChinese ? "主教练" : "Lead coach", selection: $draft.coachId) {
                    Text(isChinese ? "未指定" : "Unassigned").tag(UUID?.none)
                    ForEach(coaches) { coach in
                        Text(coach.displayName).tag(UUID?.some(coach.id))
                    }
                }
            }

            DatePicker(
                isChinese ? "开始日期" : "Start date",
                selection: Binding(
                    get: { draft.startDate ?? Date() },
                    set: { draft.startDate = $0 }
                ),
                displayedComponents: .date
            )

            Toggle(isChinese ? "设置结束日期" : "Has end date", isOn: $hasEndDate.animation())
            if hasEndDate {
                DatePicker(
                    isChinese ? "结束日期" : "End date",
                    selection: Binding(
                        get: { draft.endDate ?? draft.startDate ?? Date() },
                        set: { draft.endDate = $0 }
                    ),
                    in: (draft.startDate ?? Date.distantPast)...,
                    displayedComponents: .date
                )
            }
        } header: {
            Text(isChinese ? "设置" : "Setup")
        }
    }

    private var statusSection: some View {
        Section {
            Picker(isChinese ? "状态" : "Status", selection: $draft.status) {
                ForEach(ProgramStatus.allCases, id: \.self) { status in
                    Text(localizedStatus(status)).tag(status)
                }
            }
        } header: {
            Text(isChinese ? "状态" : "Status")
        } footer: {
            Text(isChinese
                 ? "归档的训练计划仍可查看，但不会出现在主列表中。"
                 : "Archived programs remain viewable but won't appear in the main list.")
        }
    }

    private var skillTargetsSection: some View {
        Section {
            NavigationLink {
                ProgramSkillTargetsSheet(program: $draft)
            } label: {
                Label(isChinese ? "技能目标" : "Skill Targets",
                      systemImage: "chart.bar.doc.horizontal")
            }
        }
    }

    // MARK: - Helpers

    private var locationBinding: Binding<UUID?> {
        Binding(
            get: { draft.locationId },
            set: { newId in
                draft.locationId = newId
                draft.locationName = newId.flatMap { id in
                    dataManager.locations.first(where: { $0.id == id })?.name
                }
            }
        )
    }

    private func toggle(_ day: Weekday) {
        if let i = draft.recurringDays.firstIndex(of: day) {
            draft.recurringDays.remove(at: i)
        } else {
            draft.recurringDays.append(day)
            draft.recurringDays.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func localizedDay(_ day: Weekday) -> String {
        guard isChinese else { return day.displayName }
        switch day {
        case .sunday:    return "周日"
        case .monday:    return "周一"
        case .tuesday:   return "周二"
        case .wednesday: return "周三"
        case .thursday:  return "周四"
        case .friday:    return "周五"
        case .saturday:  return "周六"
        }
    }

    private func localizedStatus(_ status: ProgramStatus) -> String {
        guard isChinese else { return status.displayName }
        switch status {
        case .draft:     return "草稿"
        case .active:    return "进行中"
        case .completed: return "已完成"
        case .archived:  return "已归档"
        }
    }

    // MARK: - Save

    private func save() {
        // Resolve the name. Custom input wins; otherwise fall back to the
        // synthesised label so `hasCoachAuthoredName` correctly classifies it.
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        draft.name = trimmed.isEmpty ? autoNamePreview : trimmed

        // Honor the end-date toggle. Drop the date when toggled off so the
        // program reverts to open-ended.
        if !hasEndDate { draft.endDate = nil }

        // Compute the recurring-day delta before persisting so we can offer
        // to backfill new days / cancel removed-day futures.
        let originalDays = Set(program.recurringDays)
        let updatedDays = Set(draft.recurringDays)
        let added = Array(updatedDays.subtracting(originalDays)).sorted { $0.rawValue < $1.rawValue }
        let removed = Array(originalDays.subtracting(updatedDays)).sorted { $0.rawValue < $1.rawValue }

        draft.updatedAt = Date()
        dataManager.updateProgram(draft)
        program = draft

        if !added.isEmpty || !removed.isEmpty {
            pendingScheduleDelta = ScheduleDelta(added: added, removed: removed)
        } else {
            dismiss()
        }
    }

    // MARK: - Schedule-delta dialog

    private var scheduleDeltaTitle: String {
        isChinese ? "排期已变" : "Schedule changed"
    }

    private func scheduleDeltaMessage(for delta: ScheduleDelta) -> String {
        var parts: [String] = []
        if !delta.added.isEmpty {
            let names = delta.added.map { dayName($0) }.joined(separator: ", ")
            parts.append(isChinese
                         ? "新增了 \(names)。要为现有阶段生成对应的训练吗？"
                         : "Added \(names). Generate matching sessions across existing phases?")
        }
        if !delta.removed.isEmpty {
            let names = delta.removed.map { dayName($0) }.joined(separator: ", ")
            parts.append(isChinese
                         ? "移除了 \(names)。要取消未来该日的训练吗？训练计划会顺延到保留的课程，过往训练会保留。"
                         : "Removed \(names). Cancel future sessions on those days? Their plans move to the classes that remain; past sessions stay as history.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func moveButtonLabel(for delta: ScheduleDelta) -> String {
        let from = delta.removed.map { dayName($0) }.joined(separator: ", ")
        let to = delta.added.map { dayName($0) }.joined(separator: ", ")
        return isChinese ? "把 \(from) 的训练移到 \(to)" : "Move \(from) sessions to \(to)"
    }

    private func generateButtonLabel(for days: [Weekday]) -> String {
        let names = days.map { dayName($0) }.joined(separator: ", ")
        return isChinese ? "生成 \(names) 训练" : "Generate \(names) sessions"
    }

    private func cancelButtonLabel(for days: [Weekday]) -> String {
        let names = days.map { dayName($0) }.joined(separator: ", ")
        return isChinese ? "取消 \(names) 训练" : "Cancel \(names) sessions"
    }

    private func dayName(_ day: Weekday) -> String {
        guard isChinese else { return day.displayName }
        switch day {
        case .sunday:    return "周日"
        case .monday:    return "周一"
        case .tuesday:   return "周二"
        case .wednesday: return "周三"
        case .thursday:  return "周四"
        case .friday:    return "周五"
        case .saturday:  return "周六"
        }
    }

    private func applySchedule(addedDays: [Weekday], removedDays: [Weekday]) {
        if !addedDays.isEmpty {
            dataManager.backfillSessions(forProgramId: draft.id, addedDays: Set(addedDays))
        }
        if !removedDays.isEmpty {
            dataManager.cancelFutureSessions(forProgramId: draft.id, removedDays: Set(removedDays))
        }
        pendingScheduleDelta = nil
        dismiss()
    }
}

// MARK: - MicroCycle Detail View
struct MicroCycleDetailView: View {
    let microCycle: MicroCycle
    let program: Program
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(microCycle.title)
                    .font(.title)
                Text(microCycle.description ?? "")
                    .foregroundColor(.secondary)
                
                if let startDate = microCycle.startDate, let endDate = microCycle.endDate {
                    HStack {
                        Text("Duration:")
                            .foregroundColor(.secondary)
                        Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(microCycle.title)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}
