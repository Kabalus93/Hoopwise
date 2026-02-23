import SwiftUI

// MARK: - Quick Session Creator View
/// A guided wizard for creating sessions - either one-off or as part of a recurring program
struct QuickSessionCreatorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    // Selected date passed from calendar
    let initialDate: Date
    
    // MARK: - Wizard State
    @State private var currentStep: CreatorStep = .selectType
    @State private var sessionType: SessionCreationType = .oneTime
    
    // MARK: - One-Time Session State
    @State private var sessionTitle: String = ""
    @State private var sessionDate: Date
    @State private var sessionStartTime: Date
    @State private var sessionDuration: Int = 90
    @State private var sessionLocation: String = ""
    @State private var linkedProgramId: UUID? = nil
    @State private var selectedStudentIds: Set<UUID> = []
    
    // MARK: - Recurring Program State
    @State private var programName: String = ""
    @State private var programAgeGroup: AgeGroup = .u12
    @State private var programMascot: ProgramMascot = .eagle
    @State private var recurringDay: Weekday = .saturday
    @State private var recurringTime: Date
    @State private var recurringDuration: Int = 90
    @State private var programStartDate: Date
    @State private var programWeeks: Int = 12
    @State private var programLocation: String = ""
    @State private var usesPhases: Bool = false
    @State private var enrolledStudentIds: Set<UUID> = []
    
    // MARK: - Phase Configuration (if usesPhases)
    @State private var phases: [PhaseConfig] = []
    
    // MARK: - UI State
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var studentSearchText = ""
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    init(initialDate: Date = Date()) {
        self.initialDate = initialDate
        _sessionDate = State(initialValue: initialDate)
        _sessionStartTime = State(initialValue: Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: initialDate) ?? initialDate)
        _recurringTime = State(initialValue: Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: initialDate) ?? initialDate)
        _programStartDate = State(initialValue: initialDate)
    }
    
    enum CreatorStep: Int, CaseIterable {
        case selectType = 0
        case configureSession = 1
        case selectStudents = 2
        case configurePhases = 3
        case review = 4
    }
    
    enum SessionCreationType {
        case oneTime
        case recurring
    }
    
    struct PhaseConfig: Identifiable {
        let id = UUID()
        var name: String
        var durationWeeks: Int
        var focus: [TrainingFocus]
        var focusDescription: String = ""
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Step content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        stepContent
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }
                
                // Navigation buttons
                navigationButtons
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "创建训练" : "Create Session")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
            }
            .alert(isChinese ? "错误" : "Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        let steps = stepsForCurrentType
        return HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { index in
                let step = steps[index]
                HStack(spacing: 4) {
                    Circle()
                        .fill(currentStep.rawValue >= step.rawValue ? AppTheme.accentColor : AppTheme.surfaceColor)
                        .frame(width: 8, height: 8)
                    
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(currentStep.rawValue > step.rawValue ? AppTheme.accentColor : AppTheme.surfaceColor)
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
    }
    
    private var stepsForCurrentType: [CreatorStep] {
        switch sessionType {
        case .oneTime:
            return [.selectType, .configureSession, .selectStudents, .review]
        case .recurring:
            if usesPhases {
                return [.selectType, .configureSession, .configurePhases, .selectStudents, .review]
            } else {
                return [.selectType, .configureSession, .selectStudents, .review]
            }
        }
    }
    
    // MARK: - Step Content
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .selectType:
            selectTypeStep
        case .configureSession:
            if sessionType == .oneTime {
                oneTimeSessionStep
            } else {
                recurringProgramStep
            }
        case .selectStudents:
            studentSelectionStep
        case .configurePhases:
            phaseConfigurationStep
        case .review:
            reviewStep
        }
    }
    
    // MARK: - Step 1: Select Type
    private var selectTypeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isChinese ? "您想创建什么？" : "What would you like to create?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            // One-Time Session Option
            Button(action: { sessionType = .oneTime }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(sessionType == .oneTime ? Color.blue : AppTheme.surfaceColor)
                            .frame(width: 50, height: 50)
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(sessionType == .oneTime ? .white : AppTheme.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "单次训练" : "One-Time Session")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(isChinese ? "为今天或选定日期创建单次训练" : "Create a single training for today or a selected date")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Image(systemName: sessionType == .oneTime ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(sessionType == .oneTime ? .blue : AppTheme.textTertiary)
                }
                .padding(16)
                .background(sessionType == .oneTime ? Color.blue.opacity(0.1) : AppTheme.cardBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(sessionType == .oneTime ? Color.blue : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            
            // Recurring Program Option
            Button(action: { sessionType = .recurring }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(sessionType == .recurring ? Color.green : AppTheme.surfaceColor)
                            .frame(width: 50, height: 50)
                        Image(systemName: "repeat.circle")
                            .font(.system(size: 22))
                            .foregroundColor(sessionType == .recurring ? .white : AppTheme.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "定期课程" : "Recurring Program")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(isChinese ? "创建每周定期训练计划，可选择添加训练阶段" : "Create weekly recurring sessions with optional training phases")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Image(systemName: sessionType == .recurring ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(sessionType == .recurring ? .green : AppTheme.textTertiary)
                }
                .padding(16)
                .background(sessionType == .recurring ? Color.green.opacity(0.1) : AppTheme.cardBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(sessionType == .recurring ? Color.green : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - One-Time Session Configuration
    private var oneTimeSessionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isChinese ? "训练详情" : "Session Details")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "标题（可选）" : "Title (optional)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                TextField(isChinese ? "例：技能训练" : "e.g., Skills Training", text: $sessionTitle)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
            }
            
            // Date & Time
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "日期" : "Date")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    DatePicker("", selection: $sessionDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "开始时间" : "Start Time")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    DatePicker("", selection: $sessionStartTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }
            
            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "时长" : "Duration")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                
                HStack(spacing: 10) {
                    ForEach([60, 90, 120], id: \.self) { minutes in
                        Button(action: { sessionDuration = minutes }) {
                            Text("\(minutes) \(isChinese ? "分钟" : "min")")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(sessionDuration == minutes ? .white : AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(sessionDuration == minutes ? AppTheme.accentColor : AppTheme.surfaceColor)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            
            // Location
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "地点（可选）" : "Location (optional)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                TextField(isChinese ? "例：主场馆" : "e.g., Main Gym", text: $sessionLocation)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
            }
            
            // Link to Program (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "关联项目（可选）" : "Link to Program (optional)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                
                Menu {
                    Button(action: { linkedProgramId = nil }) {
                        Label(isChinese ? "无关联" : "No Program", systemImage: "minus.circle")
                    }
                    
                    Divider()
                    
                    ForEach(dataManager.programs.filter { $0.status == .active }) { program in
                        Button(action: { linkedProgramId = program.id }) {
                            Label(program.displayName, systemImage: program.mascot.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let programId = linkedProgramId,
                           let program = dataManager.programs.first(where: { $0.id == programId }) {
                            Image(systemName: program.mascot.icon)
                                .foregroundColor(program.mascotColor)
                            Text(program.displayName)
                                .foregroundColor(AppTheme.textPrimary)
                        } else {
                            Image(systemName: "folder")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(isChinese ? "选择项目..." : "Select a program...")
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .font(.system(size: 15))
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                }
            }
        }
    }
    
    // MARK: - Recurring Program Configuration
    private var recurringProgramStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isChinese ? "课程详情" : "Program Details")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            // Program Name
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "课程名称" : "Program Name")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                TextField(isChinese ? "例：周六精英班" : "e.g., Saturday Elite", text: $programName)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
            }
            
            // Age Group & Mascot
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "年龄组" : "Age Group")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Picker("", selection: $programAgeGroup) {
                        ForEach(AgeGroup.allCases, id: \.self) { age in
                            Text(age.displayName).tag(age)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "吉祥物" : "Mascot")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Picker("", selection: $programMascot) {
                        ForEach(ProgramMascot.allCases, id: \.self) { mascot in
                            Label(mascot.displayName, systemImage: mascot.icon).tag(mascot)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                }
            }
            
            // Recurring Day & Time
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "每周" : "Day of Week")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Picker("", selection: $recurringDay) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.displayName).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "开始时间" : "Start Time")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    DatePicker("", selection: $recurringTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }
            
            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "每节时长" : "Session Duration")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                
                HStack(spacing: 10) {
                    ForEach([60, 90, 120], id: \.self) { minutes in
                        Button(action: { recurringDuration = minutes }) {
                            Text("\(minutes) \(isChinese ? "分钟" : "min")")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(recurringDuration == minutes ? .white : AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(recurringDuration == minutes ? AppTheme.accentColor : AppTheme.surfaceColor)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            
            // Start Date & Duration
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "开始日期" : "Start Date")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    DatePicker("", selection: $programStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "持续周数" : "Duration (weeks)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Stepper("\(programWeeks) \(isChinese ? "周" : "weeks")", value: $programWeeks, in: 4...52)
                        .padding(8)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(10)
                }
            }
            
            // Location
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "地点（可选）" : "Location (optional)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                TextField(isChinese ? "例：主场馆" : "e.g., Main Gym", text: $programLocation)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
            }
            
            // Use Phases Toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $usesPhases) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "使用训练阶段" : "Use Training Phases")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(isChinese ? "将课程分为多个阶段，每个阶段有不同的训练重点" : "Divide the program into phases with different training focuses")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .tint(AppTheme.accentColor)
                .padding(12)
                .background(AppTheme.cardBackground)
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Phase Configuration Step
    private var phaseConfigurationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(isChinese ? "训练阶段" : "Training Phases")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: { addPhase() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(isChinese ? "添加阶段" : "Add Phase")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accentColor)
                }
            }
            
            // Total program duration control
            HStack {
                Text(isChinese ? "总课程周数:" : "Total Program Weeks:")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(minWidth: 130, alignment: .leading)
                Spacer()
                Stepper("\(programWeeks)", value: $programWeeks, in: 4...52)
                    .fixedSize()
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .cornerRadius(10)
            
            if phases.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(isChinese ? "点击上方添加训练阶段" : "Tap above to add training phases")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(AppTheme.cardBackground)
                .cornerRadius(14)
            } else {
                ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                    phaseCard(phase: phase, index: index)
                }
            }
            
            // Total weeks indicator
            if !phases.isEmpty {
                let totalPhaseWeeks = phases.reduce(0) { $0 + $1.durationWeeks }
                HStack {
                    Text(isChinese ? "阶段总计" : "Total Phase Duration")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("\(totalPhaseWeeks) / \(programWeeks) \(isChinese ? "周" : "weeks")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(totalPhaseWeeks == programWeeks ? .green : (totalPhaseWeeks > programWeeks ? .red : .orange))
                }
                .padding(12)
                .background(AppTheme.cardBackground)
                .cornerRadius(10)
            }
        }
    }
    
    private func phaseCard(phase: PhaseConfig, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isChinese ? "阶段 \(index + 1)" : "Phase \(index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.accentColor)
                Spacer()
                Button(action: { phases.remove(at: index) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            TextField(isChinese ? "阶段名称" : "Phase Name", text: Binding(
                get: { phases[index].name },
                set: { phases[index].name = $0 }
            ))
            .font(.system(size: 15))
            .padding(10)
            .background(AppTheme.surfaceColor)
            .cornerRadius(8)
            
            HStack {
                Text(isChinese ? "周数:" : "Weeks:")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(minWidth: 88, alignment: .leading)
                Spacer()
                Stepper("\(phases[index].durationWeeks)", value: Binding(
                    get: { phases[index].durationWeeks },
                    set: { phases[index].durationWeeks = $0 }
                ), in: 1...20)
                    .fixedSize()
            }
            
            // Focus areas picker
            HStack {
                Text(isChinese ? "训练重点:" : "Focus Areas:")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(minWidth: 88, alignment: .leading)
                Spacer()
                Menu {
                    ForEach(TrainingFocus.allCases, id: \.self) { focus in
                        let isSelected = phases[index].focus.contains(focus)
                        Button(action: {
                            if isSelected {
                                phases[index].focus.removeAll { $0 == focus }
                            } else {
                                phases[index].focus.append(focus)
                            }
                        }) {
                            HStack {
                                Text(focus.displayName)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if phases[index].focus.isEmpty {
                            Text(isChinese ? "选择..." : "Select...")
                                .foregroundColor(AppTheme.textTertiary)
                        } else {
                            Text(phases[index].focus.map { $0.displayName }.joined(separator: ", "))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minWidth: 150, alignment: .trailing)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
                }
            }
            
            // Focus description text field
            TextField(isChinese ? "详细描述训练重点..." : "Describe focus area details...", text: Binding(
                get: { phases[index].focusDescription },
                set: { phases[index].focusDescription = $0 }
            ), axis: .vertical)
            .font(.system(size: 14))
            .foregroundColor(AppTheme.textPrimary)
            .padding(10)
            .background(AppTheme.surfaceColor)
            .cornerRadius(8)
            .lineLimit(2...4)
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    private func addPhase() {
        let phaseNumber = phases.count + 1
        let defaultNames = [
            isChinese ? "基础阶段" : "Foundation",
            isChinese ? "技能发展" : "Skill Development",
            isChinese ? "比赛准备" : "Game Prep",
            isChinese ? "高峰阶段" : "Peak Performance"
        ]
        let name = phaseNumber <= defaultNames.count ? defaultNames[phaseNumber - 1] : "\(isChinese ? "阶段" : "Phase") \(phaseNumber)"
        phases.append(PhaseConfig(name: name, durationWeeks: 3, focus: [], focusDescription: ""))
    }
    
    // MARK: - Student Selection Step
    private var filteredStudents: [Student] {
        // Sort by most recently added first
        let sorted = dataManager.students.sorted { $0.createdAt > $1.createdAt }
        
        // Filter by search text
        if studentSearchText.isEmpty {
            return sorted
        }
        
        let search = studentSearchText.lowercased()
        return sorted.filter { student in
            student.name.lowercased().contains(search) ||
            (student.chineseName?.lowercased().contains(search) ?? false)
        }
    }
    
    private var studentSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isChinese ? "选择学员" : "Select Students")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            Text(isChinese ? "选择参加此\(sessionType == .oneTime ? "训练" : "课程")的学员" : "Select students for this \(sessionType == .oneTime ? "session" : "program")")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textTertiary)
                
                TextField(isChinese ? "搜索学员..." : "Search students...", text: $studentSearchText)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
                
                if !studentSearchText.isEmpty {
                    Button(action: { studentSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .cornerRadius(10)
            
            // Quick actions
            HStack(spacing: 12) {
                Button(action: {
                    if sessionType == .oneTime {
                        selectedStudentIds = Set(dataManager.students.map { $0.id })
                    } else {
                        enrolledStudentIds = Set(dataManager.students.map { $0.id })
                    }
                }) {
                    Text(isChinese ? "全选" : "Select All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                
                Button(action: {
                    if sessionType == .oneTime {
                        selectedStudentIds = []
                    } else {
                        enrolledStudentIds = []
                    }
                }) {
                    Text(isChinese ? "清除" : "Clear")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(8)
                }
                
                Spacer()
                
                let count = sessionType == .oneTime ? selectedStudentIds.count : enrolledStudentIds.count
                Text("\(count) \(isChinese ? "已选" : "selected")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            // Student list
            VStack(spacing: 0) {
                ForEach(filteredStudents) { student in
                    let isSelected = sessionType == .oneTime ? selectedStudentIds.contains(student.id) : enrolledStudentIds.contains(student.id)
                    
                    Button(action: {
                        if sessionType == .oneTime {
                            if isSelected {
                                selectedStudentIds.remove(student.id)
                            } else {
                                selectedStudentIds.insert(student.id)
                            }
                        } else {
                            if isSelected {
                                enrolledStudentIds.remove(student.id)
                            } else {
                                enrolledStudentIds.insert(student.id)
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            StudentAvatarView(student: student, size: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(student.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                if let chinese = student.chineseName {
                                    Text(chinese)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    
                    if student.id != filteredStudents.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Review Step
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isChinese ? "确认创建" : "Review & Create")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            if sessionType == .oneTime {
                oneTimeReviewCard
            } else {
                recurringReviewCard
            }
        }
    }
    
    private var oneTimeReviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionTitle.isEmpty ? (isChinese ? "训练" : "Training") : sessionTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(isChinese ? "单次训练" : "One-Time Session")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
            
            reviewRow(icon: "calendar", label: isChinese ? "日期" : "Date", value: sessionDate.formatted(date: .abbreviated, time: .omitted))
            reviewRow(icon: "clock", label: isChinese ? "时间" : "Time", value: sessionStartTime.formatted(date: .omitted, time: .shortened))
            reviewRow(icon: "timer", label: isChinese ? "时长" : "Duration", value: "\(sessionDuration) \(isChinese ? "分钟" : "min")")
            
            if !sessionLocation.isEmpty {
                reviewRow(icon: "mappin", label: isChinese ? "地点" : "Location", value: sessionLocation)
            }
            
            if let programId = linkedProgramId,
               let program = dataManager.programs.first(where: { $0.id == programId }) {
                reviewRow(icon: program.mascot.icon, label: isChinese ? "关联项目" : "Program", value: program.displayName)
            }
            
            reviewRow(icon: "person.2", label: isChinese ? "学员" : "Students", value: "\(selectedStudentIds.count) \(isChinese ? "人" : "selected")")
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    private var recurringReviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(programMascot.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: programMascot.icon)
                        .font(.system(size: 20))
                        .foregroundColor(programMascot.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(programName.isEmpty ? programMascot.displayName : programName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(isChinese ? "定期课程" : "Recurring Program")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            reviewRow(icon: "person.3", label: isChinese ? "年龄组" : "Age Group", value: programAgeGroup.displayName)
            reviewRow(icon: "calendar", label: isChinese ? "每周" : "Day", value: recurringDay.displayName)
            reviewRow(icon: "clock", label: isChinese ? "时间" : "Time", value: recurringTime.formatted(date: .omitted, time: .shortened))
            reviewRow(icon: "timer", label: isChinese ? "时长" : "Duration", value: "\(recurringDuration) \(isChinese ? "分钟" : "min")")
            reviewRow(icon: "calendar.badge.clock", label: isChinese ? "开始" : "Starts", value: programStartDate.formatted(date: .abbreviated, time: .omitted))
            reviewRow(icon: "number", label: isChinese ? "周数" : "Weeks", value: "\(programWeeks) \(isChinese ? "周" : "weeks")")
            
            if !programLocation.isEmpty {
                reviewRow(icon: "mappin", label: isChinese ? "地点" : "Location", value: programLocation)
            }
            
            if usesPhases {
                reviewRow(icon: "square.stack.3d.up", label: isChinese ? "阶段" : "Phases", value: "\(phases.count) \(isChinese ? "个阶段" : "phases")")
            }
            
            reviewRow(icon: "person.2", label: isChinese ? "学员" : "Students", value: "\(enrolledStudentIds.count) \(isChinese ? "人" : "enrolled")")
            
            // Sessions to be created
            let sessionsCount = programWeeks
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accentColor)
                    .frame(width: 24)
                
                Text(isChinese ? "将创建 \(sessionsCount) 节课程" : "Will create \(sessionsCount) sessions")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    private func reviewRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
        }
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep != .selectType {
                Button(action: { goBack() }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text(isChinese ? "上一步" : "Back")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                }
            }
            
            Button(action: { goNext() }) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(currentStep == .review ? (isChinese ? "创建" : "Create") : (isChinese ? "下一步" : "Next"))
                        if currentStep != .review {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canProceed ? AppTheme.accentColor : AppTheme.textTertiary)
                .cornerRadius(12)
            }
            .disabled(!canProceed || isCreating)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.surfaceColor)
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .selectType:
            return true
        case .configureSession:
            if sessionType == .oneTime {
                return true // All fields optional or have defaults
            } else {
                return !programName.isEmpty
            }
        case .selectStudents:
            return true // Can skip student selection
        case .configurePhases:
            return !usesPhases || !phases.isEmpty
        case .review:
            return true
        }
    }
    
    private func goBack() {
        let steps = stepsForCurrentType
        if let currentIndex = steps.firstIndex(of: currentStep), currentIndex > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStep = steps[currentIndex - 1]
            }
        }
    }
    
    private func goNext() {
        if currentStep == .review {
            createSession()
            return
        }
        
        let steps = stepsForCurrentType
        if let currentIndex = steps.firstIndex(of: currentStep), currentIndex < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStep = steps[currentIndex + 1]
            }
        }
    }
    
    // MARK: - Create Session/Program
    private func createSession() {
        isCreating = true
        
        Task {
            do {
                if sessionType == .oneTime {
                    try await createOneTimeSession()
                } else {
                    try await createRecurringProgram()
                }
                
                await MainActor.run {
                    isCreating = false
                    HapticFeedback.notification(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func createOneTimeSession() async throws {
        let calendar = Calendar.current
        
        // Combine date and time
        let timeComponents = calendar.dateComponents([.hour, .minute], from: sessionStartTime)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        
        guard let startTime = calendar.date(from: dateComponents) else {
            throw NSError(domain: "QuickSessionCreator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid date/time"])
        }
        
        let endTime = calendar.date(byAdding: .minute, value: sessionDuration, to: startTime) ?? startTime
        
        let title = sessionTitle.isEmpty ? (isChinese ? "训练" : "Training") : sessionTitle
        
        let session = SessionEvent(
            programId: linkedProgramId,
            sessionType: .training,
            title: title,
            date: sessionDate,
            startTime: startTime,
            endTime: endTime,
            location: sessionLocation.isEmpty ? nil : sessionLocation,
            status: .scheduled,
            attendeeIds: Array(selectedStudentIds),
            createdByCoachId: AuthManager.shared.currentUser?.id
        )
        
        await MainActor.run {
            dataManager.addSessionEvent(session)
        }
    }
    
    private func createRecurringProgram() async throws {
        let calendar = Calendar.current
        
        // Create the program
        let program = Program(
            name: programName,
            programType: .group,
            ageGroup: programAgeGroup,
            durationWeeks: programWeeks,
            enrolledStudentIds: Array(enrolledStudentIds),
            createdByCoachId: AuthManager.shared.currentUser?.id,
            status: .active,
            mascot: programMascot,
            startDate: programStartDate,
            recurringDays: [recurringDay],
            defaultSessionTime: recurringTime,
            defaultSessionDurationMinutes: recurringDuration,
            locationName: programLocation.isEmpty ? nil : programLocation,
            usesPhases: usesPhases
        )
        
        await MainActor.run {
            dataManager.addProgram(program)
        }
        
        // Create phases if enabled
        var microCycles: [MicroCycle] = []
        if usesPhases {
            var phaseStartDate = programStartDate
            for (index, phase) in phases.enumerated() {
                let phaseEndDate = calendar.date(byAdding: .weekOfYear, value: phase.durationWeeks, to: phaseStartDate) ?? phaseStartDate
                
                let microCycle = MicroCycle(
                    programId: program.id,
                    phaseNumber: index + 1,
                    title: phase.name,
                    focus: phase.focus,
                    durationWeeks: phase.durationWeeks,
                    startDate: phaseStartDate,
                    endDate: phaseEndDate
                )
                
                await MainActor.run {
                    dataManager.addMicroCycle(microCycle)
                }
                
                microCycles.append(microCycle)
                phaseStartDate = phaseEndDate
            }
        }
        
        // Create sessions for each week
        let timeComponents = calendar.dateComponents([.hour, .minute], from: recurringTime)
        var currentDate = programStartDate
        
        // Find the first occurrence of the recurring day
        while calendar.component(.weekday, from: currentDate) != recurringDay.rawValue {
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        for weekIndex in 0..<programWeeks {
            let sessionDate = calendar.date(byAdding: .weekOfYear, value: weekIndex, to: currentDate) ?? currentDate
            
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            
            guard let startTime = calendar.date(from: dateComponents) else { continue }
            let endTime = calendar.date(byAdding: .minute, value: recurringDuration, to: startTime) ?? startTime
            
            // Find which phase this session belongs to
            var microCycleId: UUID? = nil
            var developmentFocus: [TrainingFocus] = []
            
            if usesPhases {
                var weekCounter = 0
                for microCycle in microCycles {
                    weekCounter += microCycle.durationWeeks
                    if weekIndex < weekCounter {
                        microCycleId = microCycle.id
                        developmentFocus = microCycle.focus
                        break
                    }
                }
            }
            
            let sessionTitle = "\(programMascot.displayName) - \(isChinese ? "第\(weekIndex + 1)周" : "Week \(weekIndex + 1)")"
            
            let session = SessionEvent(
                microCycleId: microCycleId,
                programId: program.id,
                sessionType: .training,
                title: sessionTitle,
                date: sessionDate,
                startTime: startTime,
                endTime: endTime,
                location: programLocation.isEmpty ? nil : programLocation,
                status: .scheduled,
                attendeeIds: Array(enrolledStudentIds),
                developmentFocus: developmentFocus,
                createdByCoachId: AuthManager.shared.currentUser?.id
            )
            
            await MainActor.run {
                dataManager.addSessionEvent(session)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    QuickSessionCreatorView()
        .environmentObject(DataManager.shared)
}
