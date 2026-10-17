import SwiftUI

// MARK: - Add Program Onboarding View
/// Splash-screen step flow for creating a program. One question per screen,
/// styled like Apple Fitness/Health onboarding: large title, single accent
/// color, native button styles, generous spacing.
struct AddProgramOnboardingView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    /// Called after a program is successfully created. Use this to switch the
    /// parent UI to the Programs tab so the coach lands on what they just made.
    var onCreated: ((Program) -> Void)? = nil

    @State private var step: Step = .type

    // Step 1
    @State private var programType: ProgramType?
    // Step 2
    @State private var recurringDays: Set<Weekday> = []
    // Step 3
    @State private var sessionTime: Date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    // Step 4
    @State private var sessionDurationMinutes: Int = 90
    // Step 5
    @State private var ageGroup: AgeGroup = .u12
    // Step 6
    @State private var locationId: UUID?
    @State private var newLocationName: String = ""
    @State private var schoolId: UUID?
    // Step 7
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
    // Step 8
    @State private var usesPhases: Bool = false
    @State private var phaseCount: Int = 3
    // Step 9
    @State private var selectedStudentIds: Set<UUID> = []
    @State private var showingStudentPicker = false
    // Optional override for the program's display name. When left blank, the
    // program gets the synthesised `Location · Age` label and the list view
    // applies its own auto-disambiguation.
    @State private var customName: String = ""

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    enum Step: Int, CaseIterable {
        case type, dates, days, time, length, age, location, phases, athletes, review

        var title: String {
            switch self {
            case .type:      return "What kind of program?"
            case .dates:     return "When does it run?"
            case .days:      return "Which days of the week?"
            case .time:      return "What time?"
            case .length:    return "How long is each session?"
            case .age:       return "Age group?"
            case .location:  return "Where will it happen?"
            case .phases:    return "Use training phases?"
            case .athletes:  return "Add athletes"
            case .review:    return "Ready to create"
            }
        }

        var subtitle: String {
            switch self {
            case .type:      return "Pick the format that best fits."
            case .dates:     return "Set a start date. Add an end date if it's a fixed-length program."
            case .days:      return "Optional. Leave empty to schedule a session for every day in the date range."
            case .time:      return "Default start time for every session."
            case .length:    return "Most coaches choose 60–90 minutes."
            case .age:       return "Players will be grouped by this age."
            case .location:  return "Choose where sessions happen."
            case .phases:    return "Phases let you sequence focus areas. You can add them later."
            case .athletes:  return "You can also add athletes after creating."
            case .review:    return "Quick check before we create the program."
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                Group {
                    switch step {
                    case .type:     typeStep
                    case .days:     daysStep
                    case .time:     timeStep
                    case .length:   lengthStep
                    case .age:      ageStep
                    case .location: locationStep
                    case .dates:    datesStep
                    case .phases:   phasesStep
                    case .athletes: athletesStep
                    case .review:   reviewStep
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
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingStudentPicker) {
                // Unified picker shared with session attendance + program edit.
                AthletePickerSheet(
                    title: LocalizationManager.shared.currentLanguage == .chinese
                        ? "选择学员" : "Select Athletes",
                    students: dataManager.students,
                    initialSelection: selectedStudentIds,
                    accentColor: .accentColor
                ) { ids in
                    selectedStudentIds = Set(ids)
                }
            }
        }
    }

    // MARK: - Progress + Bottom Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: CGFloat {
        CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .type {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
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
        if step == .review { return isChinese ? "创建训练计划" : "Create Program" }
        if step == .athletes && selectedStudentIds.isEmpty { return isChinese ? "稍后再加" : "Skip for now" }
        return isChinese ? "继续" : "Continue"
    }

    private var canAdvance: Bool {
        switch step {
        case .type:     return programType != nil
        case .location:
            // School programs are pinned to a partner school instead of a
            // registered venue — the school IS the location for billing &
            // scheduling purposes, so the venue picker becomes optional.
            if programType == .school { return schoolId != nil }
            return locationId != nil
        case .dates:    return !hasEndDate || endDate >= startDate
        default:        return true
        }
    }

    private func advance() {
        if step == .review {
            createProgram()
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

    // MARK: - Step Header

    private func stepHeader(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Step 1: Type
    private var typeStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.type)
                VStack(spacing: 12) {
                    typeCard(.privateSessions, title: isChinese ? "私教课" : "Private Session",
                             detail: isChinese ? "1对1或最多3名球员" : "1-on-1 or up to 3 players")
                    typeCard(.group, title: isChinese ? "团体训练" : "Group Training",
                             detail: isChinese ? "常规团队训练" : "Regular group sessions")
                    typeCard(.school, title: isChinese ? "校园课程" : "School Program",
                             detail: isChinese ? "与合作学校的课程（公司↔学校结算）" : "Sessions run with a partner school (company↔school billing)")
                    typeCard(.coachWorkshop, title: isChinese ? "教练研讨班" : "Coach Workshop",
                             detail: isChinese ? "为其他教练举办的培训" : "A session led for fellow coaches")
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func typeCard(_ type: ProgramType, title: String, detail: String) -> some View {
        let selected = programType == type
        return Button {
            programType = type
        } label: {
            HStack(spacing: 14) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step: Days
    private var daysStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.days)
                VStack(spacing: 10) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        let on = recurringDays.contains(day)
                        Button {
                            if on { recurringDays.remove(day) } else { recurringDays.insert(day) }
                        } label: {
                            HStack {
                                Text(day.displayName)
                                    .font(.body)
                                Spacer()
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Live preview so the coach never accidentally creates 0 sessions
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.secondary)
                        Text(sessionCountPreview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 3: Time
    private var timeStep: some View {
        VStack(spacing: 0) {
            stepHeader(.time)
            DatePicker("", selection: $sessionTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: - Step 4: Length
    private var lengthStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.length)
                let options = [30, 45, 60, 75, 90, 105, 120]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(options, id: \.self) { mins in
                        let on = sessionDurationMinutes == mins
                        Button {
                            sessionDurationMinutes = mins
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(mins)")
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                                Text(isChinese ? "分钟" : "min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            .foregroundStyle(on ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 5: Age
    private var ageStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.age)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(AgeGroup.allCases, id: \.self) { group in
                        let on = ageGroup == group
                        Button {
                            ageGroup = group
                        } label: {
                            Text(group.rawValue)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)
                                )
                                .foregroundStyle(on ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 6: Location
    private var locationStep: some View {
        // School programs are tied to a partner school, not a registered
        // venue — show only the school picker so the coach isn't forced
        // to pick both. The venue picker is hidden entirely in this case.
        if programType == .school {
            return AnyView(
                ScrollView {
                    VStack(spacing: 0) {
                        stepHeader(.location)
                        schoolPickerSection
                            .padding(.top, 4)
                    }
                }
            )
        }
        return AnyView(_locationStepDefault)
    }

    private var _locationStepDefault: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.location)
                if dataManager.locations.isEmpty {
                    VStack(spacing: 12) {
                        Text(isChinese ? "还没有保存的场地。添加一个继续。" : "No saved locations yet. Add one to continue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        TextField(isChinese ? "场地名称" : "Location name", text: $newLocationName)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let trimmed = newLocationName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            let loc = Location(name: trimmed)
                            dataManager.addLocation(loc)
                            locationId = loc.id
                            newLocationName = ""
                        } label: {
                            Label(isChinese ? "添加场地" : "Add Location", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dataManager.locations) { loc in
                            let on = locationId == loc.id
                            Button {
                                locationId = loc.id
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.secondary)
                                    Text(loc.name)
                                        .font(.body)
                                    Spacer()
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var schoolPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(SessionFormat.school.tint)
                Text(isChinese ? "合作学校" : "Partner School")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 20)

            let activeSchools = dataManager.schools.filter { $0.isActive }
            if activeSchools.isEmpty {
                Text(isChinese
                     ? "请先在「机构 → 学校」中添加学校。"
                     : "Add a school under Org → Schools first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(activeSchools) { school in
                        let on = schoolId == school.id
                        Button {
                            schoolId = school.id
                        } label: {
                            HStack {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(SessionFormat.school.tint)
                                Text(school.displayName)
                                    .font(.body)
                                Spacer()
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(SessionFormat.school.tint)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(on ? SessionFormat.school.tint : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 7: Dates
    private var datesStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.dates)
                VStack(spacing: 16) {
                    DatePicker(isChinese ? "开始日期" : "Start date",
                               selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)

                    Toggle(isChinese ? "设置结束日期" : "Set end date", isOn: $hasEndDate.animation())
                        .tint(.accentColor)

                    if hasEndDate {
                        DatePicker(isChinese ? "结束日期" : "End date",
                                   selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                    } else {
                        Label(isChinese
                              ? "无结束日期 — 将自动生成接下来 \(Self.openEndedHorizonWeeks) 周的课程"
                              : "No end date — sessions will be generated for the next \(Self.openEndedHorizonWeeks) weeks",
                              systemImage: "infinity")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 8: Phases
    private var phasesStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.phases)
                VStack(spacing: 16) {
                    Toggle(isChinese ? "使用训练阶段" : "Use phases", isOn: $usesPhases.animation())
                        .tint(.accentColor)

                    if usesPhases {
                        Stepper(value: $phaseCount, in: 2...6) {
                            HStack {
                                Text(isChinese ? "阶段数量" : "Number of phases")
                                Spacer()
                                Text("\(phaseCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Text(isChinese
                             ? "我们会创建 \(phaseCount) 个空白阶段。你可以稍后定义焦点和课程。"
                             : "We'll create \(phaseCount) empty phases. You can fill in focus and sessions later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 9: Athletes
    private var athletesStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.athletes)
                VStack(spacing: 16) {
                    Button {
                        showingStudentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.2.badge.plus")
                            Text(selectedStudentIds.isEmpty
                                 ? (isChinese ? "选择球员" : "Choose athletes")
                                 : (isChinese ? "已选 \(selectedStudentIds.count) 名" : "\(selectedStudentIds.count) selected"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)

                    if !selectedStudentIds.isEmpty {
                        let students = dataManager.students.filter { selectedStudentIds.contains($0.id) }.sorted { $0.name < $1.name }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(students.prefix(8)) { s in
                                HStack(spacing: 8) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.tertiary)
                                    Text(s.primaryDisplayName).font(.subheadline)
                                    Spacer()
                                }
                            }
                            if students.count > 8 {
                                Text(isChinese ? "及其他 \(students.count - 8) 名" : "and \(students.count - 8) more")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Step 10: Review
    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                stepHeader(.review)

                // Optional name override. Placeholder previews the
                // auto-generated name so the coach sees what'll appear if they
                // skip it. Coach-typed names are treated as authored and shown
                // verbatim across the app; otherwise the list applies
                // auto-disambiguation when needed.
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "名称（可选）" : "Name (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    TextField(autoNamePreview, text: $customName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    Text(isChinese
                         ? "留空则使用「\(autoNamePreview)」。"
                         : "Leave blank to use “\(autoNamePreview)”.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    summaryRow(label: isChinese ? "类型" : "Type",
                               value: programType?.displayName ?? "—",
                               icon: programType?.icon ?? "questionmark") { step = .type }
                    summaryRow(label: isChinese ? "日程" : "Days",
                               value: recurringDaysSummary,
                               icon: "calendar") { step = .days }
                    summaryRow(label: isChinese ? "时间" : "Time",
                               value: timeFormatter.string(from: sessionTime),
                               icon: "clock") { step = .time }
                    summaryRow(label: isChinese ? "时长" : "Length",
                               value: "\(sessionDurationMinutes) \(isChinese ? "分钟" : "min")",
                               icon: "timer") { step = .length }
                    summaryRow(label: isChinese ? "年龄组" : "Age",
                               value: ageGroup.rawValue,
                               icon: "person.3") { step = .age }
                    summaryRow(label: isChinese ? "场地" : "Location",
                               value: locationName ?? "—",
                               icon: "mappin.and.ellipse") { step = .location }
                    summaryRow(label: isChinese ? "开始" : "Starts",
                               value: dateFormatter.string(from: startDate) + (hasEndDate ? " → \(dateFormatter.string(from: endDate))" : ""),
                               icon: "calendar.badge.clock") { step = .dates }
                    summaryRow(label: isChinese ? "阶段" : "Phases",
                               value: usesPhases ? "\(phaseCount)" : (isChinese ? "无" : "None"),
                               icon: "rectangle.stack",
                               isLast: !selectedStudentIds.isEmpty || true) { step = .phases }
                    summaryRow(label: isChinese ? "学员" : "Athletes",
                               value: selectedStudentIds.isEmpty ? (isChinese ? "稍后再加" : "Add later") : "\(selectedStudentIds.count)",
                               icon: "person.2",
                               isLast: true) { step = .athletes }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 20)

                // Total session preview, surfaces the same warning the days step shows.
                HStack(spacing: 8) {
                    Image(systemName: plannedSessionCount == 0 && !recurringDays.isEmpty
                          ? "exclamationmark.triangle.fill"
                          : "calendar.badge.checkmark")
                        .foregroundStyle(plannedSessionCount == 0 && !recurringDays.isEmpty
                                         ? Color.orange : .secondary)
                    Text(sessionCountPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
        }
    }

    private func summaryRow(label: String, value: String, icon: String, isLast: Bool = false, edit: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { edit() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isLast {
                Divider().padding(.leading, 52)
            }
        }
    }

    // MARK: - Derived display
    private var recurringDaysSummary: String {
        guard !recurringDays.isEmpty else { return isChinese ? "范围内每天" : "Every day in range" }
        return recurringDays.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.shortName }.joined(separator: ", ")
    }

    /// Default horizon when the coach didn't set an end date. Long enough that
    /// recurring weekly programs generate a meaningful run of upcoming
    /// sessions on the calendar without spamming the database.
    private static let openEndedHorizonWeeks = 12

    /// The end date used by both the count preview and the actual session
    /// generator. If `hasEndDate`, that's what the user picked; otherwise we
    /// project `openEndedHorizonWeeks` ahead so a "recurring Thursday"
    /// program produces N Thursdays and not just the next one.
    private var effectiveEndDate: Date {
        if hasEndDate { return endDate }
        return Calendar.current.date(byAdding: .weekOfYear,
                                     value: Self.openEndedHorizonWeeks,
                                     to: startDate) ?? startDate
    }

    /// Dates in the date range, inclusive of start and the effective end.
    private var datesInRange: [Date] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: startDate)
        let endDay = cal.startOfDay(for: effectiveEndDate)
        guard endDay >= startDay else { return [startDay] }
        var result: [Date] = []
        var d = startDay
        while d <= endDay {
            result.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
        return result
    }

    /// Number of session events that will be generated.
    /// If recurringDays is empty, every day in range counts; otherwise only matching weekdays.
    private var plannedSessionCount: Int {
        let cal = Calendar.current
        if recurringDays.isEmpty { return datesInRange.count }
        return datesInRange.filter { date in
            recurringDays.contains(where: { $0.rawValue == cal.component(.weekday, from: date) })
        }.count
    }

    private var sessionCountPreview: String {
        let n = plannedSessionCount
        if recurringDays.isEmpty {
            return isChinese
                ? "将创建 \(n) 个课程（范围内每天一次）"
                : "Will create \(n) session\(n == 1 ? "" : "s") — one for every day in range"
        }
        if n == 0 {
            return isChinese
                ? "⚠︎ 所选日期与日期范围不重叠 — 不会创建任何课程"
                : "⚠︎ Picked days don't fall inside the date range — no sessions will be created"
        }
        return isChinese
            ? "将创建 \(n) 个课程"
            : "Will create \(n) session\(n == 1 ? "" : "s")"
    }

    private var locationName: String? {
        guard let id = locationId else { return nil }
        return dataManager.locations.first(where: { $0.id == id })?.name
    }

    /// Preview of the auto-generated program name when the coach leaves the
    /// optional Name field blank. Mirrors the synthesis used in
    /// `createProgram()` so the preview matches the saved value.
    private var autoNamePreview: String {
        let parts = [locationName, ageGroup.rawValue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? ageGroup.rawValue : parts.joined(separator: " · ")
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }

    // MARK: - Create
    private func createProgram() {
        guard let type = programType else { return }
        // School programs don't need a registered venue — the school IS
        // the location. Other types still require one.
        if type != .school, locationId == nil { return }
        let location = locationId.flatMap { id in
            dataManager.locations.first(where: { $0.id == id })
        }
        let school = type == .school ? dataManager.school(for: schoolId) : nil

        // Persist the user's end date if they set one. Otherwise leave it nil
        // on the Program (it stays open-ended), and use `effectiveEndDate` for
        // the immediate session-generation horizon.
        let computedEnd: Date? = hasEndDate ? endDate : nil
        let weeks = max(1, weeksBetween(startDate, effectiveEndDate))

        // If the user skipped the weekday step, derive the recurring days from the
        // actual dates we'll be scheduling on. This keeps the Program list (which
        // groups by `recurringDays.first`) honest, and prevents the silent
        // "scheduled to Saturday by default" bug.
        let cal = Calendar.current
        let resolvedDays: [Weekday] = recurringDays.isEmpty
            ? Array(Set(datesInRange.compactMap { Weekday(rawValue: cal.component(.weekday, from: $0)) }))
                .sorted(by: { $0.rawValue < $1.rawValue })
            : recurringDays.sorted(by: { $0.rawValue < $1.rawValue })

        // Name resolution: coach-typed name wins. Otherwise use the synthesised
        // `Location · Age` form — `Program.resolvedDisplayName(in:)` will
        // auto-disambiguate at display time when two programs collide.
        // For school programs the school name is the natural anchor and
        // takes the place of the location.
        let derivedName: String = {
            let trimmed = customName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
            let primary = school?.displayName ?? location?.name
            return [primary, ageGroup.rawValue]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }()

        let program = Program(
            name: derivedName,
            programType: type,
            ageGroup: ageGroup,
            durationWeeks: weeks,
            enrolledStudentIds: Array(selectedStudentIds),
            coachId: dataManager.loggedInCoachId,
            createdByCoachId: dataManager.loggedInCoachId,
            status: .active,
            mascot: .eagle,
            startDate: startDate,
            endDate: computedEnd,
            recurringDays: resolvedDays,
            defaultSessionTime: sessionTime,
            defaultSessionDurationMinutes: sessionDurationMinutes,
            locationId: locationId,
            locationName: location?.name,
            schoolId: type == .school ? schoolId : nil,
            usesPhases: usesPhases
        )

        dataManager.addProgram(program)

        if usesPhases {
            createEmptyPhases(for: program)
        } else {
            createRecurringSessions(for: program, until: computedEnd ?? startDate)
        }

        onCreated?(program)
        dismiss()
    }

    private func weeksBetween(_ a: Date, _ b: Date) -> Int {
        let comps = Calendar.current.dateComponents([.weekOfYear], from: a, to: b)
        return max(1, comps.weekOfYear ?? 1)
    }

    private func createEmptyPhases(for program: Program) {
        let totalWeeks = program.durationWeeks
        let weeksPerPhase = max(1, totalWeeks / phaseCount)
        for i in 0..<phaseCount {
            let phase = MicroCycle(
                programId: program.id,
                phaseNumber: i + 1,
                title: "Phase \(i + 1)",
                durationWeeks: weeksPerPhase
            )
            dataManager.addMicroCycle(phase)
        }
    }

    private func createRecurringSessions(for program: Program, until end: Date) {
        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute], from: sessionTime)
        // If no weekdays were picked, schedule one session for every day in the range.
        // Otherwise only fire on matching weekdays. This prevents silent zero-session
        // creation when the picked days don't fall inside the date range.
        let runEveryDay = recurringDays.isEmpty
        // One generated run, one series id (Phase 2.2). The roster is left to
        // the service, which takes the program's enrolment — this generator
        // used to create every session with no attendees at all, which is why
        // the widget's window ladder had to fall back to enrolment to find one.
        let seriesId = UUID()
        for date in datesInRange {
            let weekday = cal.component(.weekday, from: date)
            guard runEveryDay || recurringDays.contains(where: { $0.rawValue == weekday }) else { continue }
            let start = cal.date(bySettingHour: timeComps.hour ?? 18,
                                 minute: timeComps.minute ?? 0,
                                 second: 0, of: date) ?? date
            dataManager.createSession(SessionCreation.Intent(
                group: .program(program.id),
                start: start,
                durationMinutes: sessionDurationMinutes,
                title: program.name,
                seriesId: seriesId,
                createdByCoachId: dataManager.loggedInCoachId))
        }
        _ = end // kept for signature compatibility
    }
}

#Preview {
    AddProgramOnboardingView()
        .environmentObject(DataManager.shared)
}
