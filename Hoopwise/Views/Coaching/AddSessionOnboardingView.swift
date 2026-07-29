import SwiftUI

// MARK: - Add Session Onboarding
/// Splash-screen step flow for creating a session, matching the
/// `AddProgramOnboardingView` aesthetic. One question per screen.
struct AddSessionOnboardingView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    /// Optional initial date (used when launched from a calendar day).
    let initialDate: Date

    @State private var step: Step = .type

    // Step 1
    @State private var sessionType: SessionType?
    // Step 2
    @State private var sessionDate: Date
    @State private var sessionStartTime: Date
    // Step 3
    @State private var sessionDurationMinutes: Int = 90
    // Step 4
    @State private var locationId: UUID?
    @State private var newLocationName: String = ""
    // Step 5
    @State private var isRecurring: Bool = false
    @State private var recurringDays: Set<Weekday> = []
    @State private var recurringWeeks: Int = 12
    // Step 6
    @State private var programId: UUID?

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    init(initialDate: Date = Date()) {
        self.initialDate = initialDate
        let cal = Calendar.current
        let day = cal.startOfDay(for: initialDate)
        let defaultStart = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        _sessionDate = State(initialValue: day)
        _sessionStartTime = State(initialValue: defaultStart)
        // Pre-select the start date's weekday in case the coach toggles
        // recurring — saves a tap and matches user expectation.
        if let wd = Weekday(rawValue: cal.component(.weekday, from: day)) {
            _recurringDays = State(initialValue: [wd])
        }
    }

    enum Step: Int, CaseIterable {
        case type, when, length, location, recurring, program, review

        var title: String {
            switch self {
            case .type:      return "What kind of session?"
            case .when:      return "When?"
            case .length:    return "How long?"
            case .location:  return "Where?"
            case .recurring: return "Repeat weekly?"
            case .program:   return "Part of a program?"
            case .review:    return "Ready to create"
            }
        }

        var subtitle: String {
            switch self {
            case .type:      return "Pick the format that best fits."
            case .when:      return "Date and start time."
            case .length:    return "Most coaches choose 60–90 minutes."
            case .location:  return "Choose where it'll be held."
            case .recurring: return "Generate the same session every week."
            case .program:   return "Optional — link to a program so attendance and revenue track correctly."
            case .review:    return "Quick check before creating."
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                Group {
                    switch step {
                    case .type:      typeStep
                    case .when:      whenStep
                    case .length:    lengthStep
                    case .location:  locationStep
                    case .recurring: recurringStep
                    case .program:   programStep
                    case .review:    reviewStep
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
        if step == .review {
            let n = plannedSessionCount
            if isRecurring && n > 1 {
                return isChinese ? "创建 \(n) 个课程" : "Create \(n) Sessions"
            }
            return isChinese ? "创建" : "Create"
        }
        return isChinese ? "继续" : "Continue"
    }

    private var canAdvance: Bool {
        switch step {
        case .type:      return sessionType != nil
        case .location:  return locationId != nil
        case .recurring: return !isRecurring || !recurringDays.isEmpty
        default:         return true
        }
    }

    private func advance() {
        if step == .review {
            createSessions()
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

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
                    ForEach(SessionType.allCases, id: \.self) { type in
                        typeCard(type)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func typeCard(_ type: SessionType) -> some View {
        let selected = sessionType == type
        let detail: String = {
            switch type {
            case .training:   return isChinese ? "常规技能训练" : "Regular skills training"
            case .scrimmage:  return isChinese ? "队内对抗赛" : "Internal team scrimmage"
            case .gamePrep:   return isChinese ? "比赛前准备课" : "Pre-game preparation"
            case .recovery:   return isChinese ? "放松恢复课" : "Recovery session"
            case .assessment: return isChinese ? "评估测试课" : "Skills assessment / testing"
            }
        }()
        return Button {
            sessionType = type
        } label: {
            HStack(spacing: 14) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
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

    // MARK: - Step 2: When

    private var whenStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.when)
                VStack(spacing: 16) {
                    DatePicker(isChinese ? "日期" : "Date",
                               selection: $sessionDate, displayedComponents: .date)
                    DatePicker(isChinese ? "时间" : "Time",
                               selection: $sessionStartTime, displayedComponents: .hourAndMinute)
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

    // MARK: - Step 3: Length

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

    // MARK: - Step 4: Location

    private var locationStep: some View {
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

    // MARK: - Step 5: Recurring

    private var recurringStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.recurring)
                VStack(spacing: 16) {
                    Toggle(isChinese ? "每周重复" : "Repeat every week", isOn: $isRecurring.animation())
                        .tint(.accentColor)

                    if isRecurring {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isChinese ? "重复的星期" : "Days of the week")
                                .font(.subheadline.weight(.medium))

                            FlowLayout(spacing: 8) {
                                ForEach(Weekday.allCases, id: \.self) { day in
                                    let on = recurringDays.contains(day)
                                    Button {
                                        if on { recurringDays.remove(day) }
                                        else  { recurringDays.insert(day) }
                                    } label: {
                                        Text(day.shortName)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule().fill(on ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                            )
                                            .overlay(
                                                Capsule().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1)
                                            )
                                            .foregroundStyle(on ? Color.accentColor : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Stepper(value: $recurringWeeks, in: 1...52) {
                                HStack {
                                    Text(isChinese ? "持续" : "For")
                                    Spacer()
                                    Text("^[\(recurringWeeks) week](inflect: true)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
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

    // MARK: - Step 6: Program

    private var programStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.program)
                VStack(spacing: 10) {
                    programOptionRow(programId: nil, title: isChinese ? "无（独立课程）" : "None (standalone)")
                    ForEach(activePrograms) { program in
                        programOptionRow(programId: program.id, title: program.displayName)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var activePrograms: [Program] {
        dataManager.programs.filter { $0.status != .archived }
            .sorted { $0.displayName < $1.displayName }
    }

    private func programOptionRow(programId: UUID?, title: String) -> some View {
        let on = self.programId == programId
        return Button {
            self.programId = programId
        } label: {
            HStack {
                if let programId,
                   let program = dataManager.programs.first(where: { $0.id == programId }) {
                    AgeBadge(shortName: program.ageGroup.rawValue, tint: .accentColor, size: .xsmall)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.tertiary)
                }
                Text(title).font(.body)
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

    // MARK: - Step 7: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepHeader(.review)
                VStack(spacing: 0) {
                    summaryRow(label: isChinese ? "类型" : "Type",
                               value: sessionType?.displayName ?? "—",
                               icon: sessionType?.icon ?? "questionmark") { step = .type }
                    summaryRow(label: isChinese ? "日期" : "Date",
                               value: dateFormatter.string(from: sessionDate),
                               icon: "calendar") { step = .when }
                    summaryRow(label: isChinese ? "时间" : "Time",
                               value: timeFormatter.string(from: sessionStartTime),
                               icon: "clock") { step = .when }
                    summaryRow(label: isChinese ? "时长" : "Length",
                               value: "\(sessionDurationMinutes) \(isChinese ? "分钟" : "min")",
                               icon: "timer") { step = .length }
                    summaryRow(label: isChinese ? "场地" : "Location",
                               value: locationName ?? "—",
                               icon: "mappin.and.ellipse") { step = .location }
                    summaryRow(label: isChinese ? "重复" : "Recurring",
                               value: recurringSummary,
                               icon: "arrow.triangle.2.circlepath") { step = .recurring }
                    summaryRow(label: isChinese ? "训练计划" : "Program",
                               value: programName ?? (isChinese ? "无" : "None"),
                               icon: "rectangle.stack",
                               isLast: true) { step = .program }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundStyle(.secondary)
                    Text(isChinese
                         ? "将创建 \(plannedSessionCount) 个课程"
                         : "^[\(plannedSessionCount) session](inflect: true) will be created")
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

    // MARK: - Derived

    private var locationName: String? {
        locationId.flatMap { id in dataManager.locations.first(where: { $0.id == id })?.name }
    }

    private var programName: String? {
        programId.flatMap { id in dataManager.programs.first(where: { $0.id == id })?.displayName }
    }

    private var recurringSummary: String {
        guard isRecurring else { return isChinese ? "否" : "Off" }
        let days = recurringDays.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.shortName }.joined(separator: ", ")
        return isChinese ? "\(days) · \(recurringWeeks) 周" : "\(days) · \(recurringWeeks) wks"
    }

    /// Number of session events that will be created.
    private var plannedSessionCount: Int {
        guard isRecurring, !recurringDays.isEmpty else { return 1 }
        return generatedDates().count
    }

    private func generatedDates() -> [Date] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: sessionDate)
        guard let endDay = cal.date(byAdding: .weekOfYear, value: recurringWeeks, to: startDay) else {
            return [startDay]
        }
        var result: [Date] = []
        var d = startDay
        while d < endDay {
            let weekday = cal.component(.weekday, from: d)
            if recurringDays.contains(where: { $0.rawValue == weekday }) {
                result.append(d)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
        // Always include the explicit start date even if it doesn't match a
        // selected weekday (the coach picked it).
        if !result.contains(where: { cal.isDate($0, inSameDayAs: startDay) }) {
            result.insert(startDay, at: 0)
        }
        return result
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }

    // MARK: - Create

    private func createSessions() {
        guard let type = sessionType else { return }
        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute], from: sessionStartTime)
        let dates = isRecurring ? generatedDates() : [cal.startOfDay(for: sessionDate)]
        let location = dataManager.locations.first(where: { $0.id == locationId })

        // Recurring sessions without a chosen program get an auto-generated
        // one so the whole series can be edited/deleted in bulk later.
        let effectiveProgramId: UUID? = {
            if let id = programId { return id }
            guard isRecurring, dates.count > 1 else { return nil }
            return autoCreateRecurringProgram(type: type, location: location, startDay: dates.first ?? sessionDate)
        }()

        // Title: prefer the linked program's display name, else the session type.
        let title = (effectiveProgramId.flatMap { id in dataManager.programs.first(where: { $0.id == id })?.displayName })
            ?? type.displayName

        // Pre-populate attendees from the linked program's roster, if any.
        let attendees: [UUID] = effectiveProgramId
            .flatMap { id in dataManager.programs.first(where: { $0.id == id })?.enrolledStudentIds }
            ?? []

        for day in dates {
            let start = cal.date(bySettingHour: timeComps.hour ?? 18,
                                 minute: timeComps.minute ?? 0,
                                 second: 0, of: day) ?? day
            let end = cal.date(byAdding: .minute, value: sessionDurationMinutes, to: start) ?? start
            let event = SessionEvent(
                programId: effectiveProgramId,
                sessionType: type,
                title: title,
                date: day,
                startTime: start,
                endTime: end,
                location: location?.name,
                attendeeIds: attendees,
                createdByCoachId: dataManager.loggedInCoachId
            )
            dataManager.addSessionEvent(event)
        }
        dismiss()
    }

    /// Build a lightweight, phase-less Program for a recurring batch when the
    /// coach didn't link one explicitly. Carries over the schedule details so
    /// the program detail view can edit / cancel the whole series.
    private func autoCreateRecurringProgram(type: SessionType, location: Location?, startDay: Date) -> UUID {
        let cal = Calendar.current
        let nameParts: [String] = [
            location?.name,
            type.displayName,
            isChinese ? "周训" : "Recurring"
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        let name = nameParts.isEmpty ? (isChinese ? "周训课程" : "Recurring Sessions") : nameParts.joined(separator: " · ")

        let endDate = cal.date(byAdding: .weekOfYear, value: recurringWeeks, to: startDay)

        let program = Program(
            name: name,
            programType: .group,
            ageGroup: .adult,
            durationWeeks: recurringWeeks,
            description: nil,
            objectives: [],
            enrolledStudentIds: [],
            coachId: dataManager.loggedInCoachId,
            createdByCoachId: dataManager.loggedInCoachId,
            status: .active,
            startDate: startDay,
            endDate: endDate,
            recurringDays: Array(recurringDays),
            defaultSessionTime: sessionStartTime,
            defaultSessionDurationMinutes: sessionDurationMinutes,
            locationId: locationId,
            locationName: location?.name,
            usesPhases: false
        )
        dataManager.addProgram(program)
        return program.id
    }
}
