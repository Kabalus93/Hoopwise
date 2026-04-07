import SwiftUI
import MapKit

// MARK: - Flighty-Styled Program Detail View
/// A redesigned program detail page with Flighty's dark, confident aesthetic
struct FlightyProgramDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var program: Program
    
    @State private var showingEditStudents = false
    @State private var showingAddPhase = false
    @State private var showingEditProgram = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSkillTargets = false
    @State private var showingParentSummary = false
    @State private var selectedStudentIds: Set<UUID> = []
    
    // Mass delete phases states
    @State private var isEditingPhases = false
    @State private var selectedPhaseIds: Set<UUID> = []
    @State private var showingMassDeleteConfirmation = false
    
    // AI Generation states
    @State private var showingAIGenerator = false
    @State private var isAIProcessing = false
    @State private var aiPrompt = ""
    @State private var aiErrorMessage: String?
    @State private var selectedSkillLevel: SkillLevel = .beginner
    
    // Collapsible sections
    @State private var isPhasesExpanded = true
    
    enum SkillLevel: String, CaseIterable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        
        var description: String {
            switch self {
            case .beginner: return "New to basketball, learning fundamentals"
            case .intermediate: return "Comfortable with basics, developing skills"
            case .advanced: return "Strong fundamentals, refining techniques"
            }
        }
    }
    
    var microCycles: [MicroCycle] {
        dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }
    
    var enrolledStudents: [Student] {
        dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    var sessionCount: Int {
        dataManager.sessionEvents.filter { $0.programId == program.id }.count
    }
    
    var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    // MARK: - Category Color (from Organization settings)
    /// The category color for this program based on its age group
    private var categoryColor: Color {
        dataManager.categoryColor(for: program.ageGroup)
    }
    
    /// Gradient colors for hero card based on category color
    private var categoryGradientColors: [Color] {
        [
            categoryColor,
            categoryColor.opacity(0.85),
            categoryColor.opacity(0.7)
        ]
    }
    
    /// Text color that contrasts with category color (white for dark colors, dark for light)
    private var categoryTextColor: Color {
        .white
    }
    
    /// Secondary text color for the category card
    private var categorySecondaryTextColor: Color {
        .white.opacity(0.7)
    }
    
    /// Accent color for highlights on the category card
    private var categoryAccentColor: Color {
        .white
    }
    
    private var starCount: Int {
        program.stars.rawValue
    }
    
    // MARK: - Location for Map
    /// Get the location for the map - either from organization location or use a default
    private var mapLocation: Location? {
        if let locationId = program.locationId {
            return dataManager.locations.first { $0.id == locationId }
        }
        return nil
    }
    
    /// Map center coordinate from organization settings
    private var mapCoordinate: CLLocationCoordinate2D {
        // Use location coordinates if available
        if let location = mapLocation,
           let lat = location.latitude,
           let lon = location.longitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Try to get coordinates from organization's first location with coordinates
        if let firstLocationWithCoords = dataManager.locations.first(where: { $0.hasCoordinates }),
           let lat = firstLocationWithCoords.latitude,
           let lon = firstLocationWithCoords.longitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Default fallback (Hong Kong) - a known valid coordinate
        return CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
    }
    
    // MARK: - Schedule Display
    /// Format the recurring days for display
    private var scheduleDisplay: String {
        let days = program.recurringDays
        if days.isEmpty {
            return "No schedule set"
        }
        let dayNames = days.map { $0.shortName }.joined(separator: ", ")
        if let time = program.defaultSessionTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "\(dayNames) • \(formatter.string(from: time))"
        }
        return dayNames
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero header with integrated stats
                heroHeader
                
                // Content sections
                VStack(spacing: 20) {
                    // Training phases - PRIMARY CONTENT
                    phasesSection
                    
                    // Enrolled athletes - elegant display
                    athletesSection
                    
                    // Objectives (moved to bottom)
                    if !program.objectives.isEmpty {
                        objectivesSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                Menu {
                    Button(action: { showingParentSummary = true }) {
                        Label(LocalizationManager.shared.currentLanguage == .chinese ? "分享给家长" : "Share with Parents", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { showingEditProgram = true }) {
                        Label(LocalizationManager.shared.currentLanguage == .chinese ? "编辑训练计划" : "Edit Program", systemImage: "pencil")
                    }
                    
                    Button(action: { showingSkillTargets = true }) {
                        Label(LocalizationManager.shared.currentLanguage == .chinese ? "技能目标" : "Skill Targets", systemImage: "chart.bar.doc.horizontal")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(LocalizationManager.shared.currentLanguage == .chinese ? "删除训练计划" : "Delete Program", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.orange)
                }
            }
        }
        .onAppear {
            selectedStudentIds = Set(program.enrolledStudentIds)
            refreshProgramFromDataManager()
        }
        .sheet(isPresented: $showingEditStudents) {
            EditEnrolledStudentsView(program: $program, selectedIds: $selectedStudentIds)
        }
        .sheet(isPresented: $showingAddPhase) {
            AddPhaseView(program: program, nextPhaseNumber: microCycles.count + 1)
        }
        .sheet(isPresented: $showingEditProgram) {
            EditProgramView(program: $program)
        }
        .onChange(of: showingEditProgram) { _, isShowing in
            if !isShowing {
                // Refresh program from dataManager after edit sheet closes
                refreshProgramFromDataManager()
            }
        }
        .onChange(of: showingEditStudents) { _, isShowing in
            if !isShowing {
                refreshProgramFromDataManager()
            }
        }
        .sheet(isPresented: $showingSkillTargets) {
            ProgramSkillTargetsSheet(program: $program)
        }
        .sheet(isPresented: $showingParentSummary) {
            ParentProgramSummaryView(program: program)
        }
        .sheet(isPresented: $showingAIGenerator) {
            AIPhaseGeneratorSheet(
                program: program,
                aiPrompt: $aiPrompt,
                selectedSkillLevel: $selectedSkillLevel,
                isProcessing: $isAIProcessing,
                errorMessage: $aiErrorMessage,
                onGenerate: { generateAIPhases() }
            )
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除训练计划？" : "Delete Program?", isPresented: $showingDeleteConfirmation) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) { deleteProgram() }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "这将永久删除\"\(program.name)\"及其所有阶段和课程。" : "This will permanently delete \"\(program.name)\" and all its phases and sessions.")
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除选中的阶段？" : "Delete Selected Phases?", isPresented: $showingMassDeleteConfirmation) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) { deleteSelectedPhases() }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "这将永久删除 \(selectedPhaseIds.count) 个阶段及其所有课程。" : "This will permanently delete \(selectedPhaseIds.count) phase\(selectedPhaseIds.count == 1 ? "" : "s") and all their sessions.")
        }
    }
    
    private func deleteProgram() {
        let programMicroCycles = dataManager.microCycles.filter { $0.programId == program.id }
        for cycle in programMicroCycles {
            dataManager.deleteMicroCycle(cycle)
        }
        
        let programSessions = dataManager.sessionEvents.filter { $0.programId == program.id }
        for session in programSessions {
            dataManager.deleteSessionEvent(session)
        }
        
        dataManager.deleteProgram(program)
        dismiss()
    }
    
    private func deletePhase(_ phase: MicroCycle) {
        // Delete all sessions associated with this phase
        let phaseSessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
        for session in phaseSessions {
            dataManager.deleteSessionEvent(session)
        }
        
        // Delete the phase itself
        dataManager.deleteMicroCycle(phase)
    }
    
    private func deleteSelectedPhases() {
        // Get all phases to delete
        let phasesToDelete = microCycles.filter { selectedPhaseIds.contains($0.id) }
        
        // Delete all sessions associated with selected phases
        for phase in phasesToDelete {
            let phaseSessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
            for session in phaseSessions {
                dataManager.deleteSessionEvent(session)
            }
            
            // Delete the phase itself
            dataManager.deleteMicroCycle(phase)
        }
        
        // Reset edit mode and selection
        isEditingPhases = false
        selectedPhaseIds.removeAll()
    }
    
    /// Refresh the program state from dataManager to ensure we have latest data
    private func refreshProgramFromDataManager() {
        if let updatedProgram = dataManager.programs.first(where: { $0.id == program.id }) {
            program = updatedProgram
            selectedStudentIds = Set(updatedProgram.enrolledStudentIds)
        }
    }
    
    // MARK: - AI Phase Generation
    private func generateAIPhases() {
        isAIProcessing = true
        aiErrorMessage = nil
        
        // Build comprehensive prompt using program context
        let ageGroup = program.ageGroup.displayName
        let category = program.ageGroup.rawValue
        let skillLevel = selectedSkillLevel.rawValue.lowercased()
        let duration = program.durationWeeks
        let recurringDays = program.recurringDays.map { $0.displayName }.joined(separator: ", ")
        let sessionDuration = program.defaultSessionDurationMinutes
        let sessionsPerWeek = program.recurringDays.count
        
        // Calculate difficulty level from enrolled students or use default
        var difficultyLevel = 5
        if let skillTargets = program.skillTargets {
            difficultyLevel = Int(skillTargets.overallTarget)
        }
        
        // Program type specific context
        let programTypeContext: String
        switch program.programType {
        case .privateSessions:
            programTypeContext = """
            PROGRAM TYPE: PRIVATE SESSIONS
            - One-on-one or small group (max 3 athletes) personalized training
            - Highly individualized skill development and attention
            - Focus on specific weaknesses and accelerated improvement
            - More repetitions and detailed technical corrections per athlete
            - Flexible pacing based on individual progress
            """
        case .group:
            programTypeContext = """
            PROGRAM TYPE: GROUP TRAINING
            - Regular group training with \(enrolledStudents.count) athletes
            - Balance individual skill development with team dynamics
            - Include partner drills and small group activities
            - Structured progressions for the entire group
            """
        case .team:
            programTypeContext = """
            PROGRAM TYPE: TEAM PROGRAM
            - Competitive team-focused training
            - Emphasis on team tactics, chemistry, and game situations
            - Include full-court scrimmages and team plays
            - Prepare for competitive games and tournaments
            """
        case .clinic:
            programTypeContext = """
            PROGRAM TYPE: CLINIC/CAMP
            - Short-term intensive training program
            - Focus on specific skills or concepts
            - High-energy sessions with variety
            - Showcase and assessment opportunities
            """
        }
        
        var promptContext = """
        Create a detailed basketball training program for European youth development using FIBA methodology.
        
        \(programTypeContext)
        
        PROGRAM CONTEXT:
        - Category: \(category) (\(ageGroup))
        - Difficulty Level: \(difficultyLevel)/10 (\(difficultyLevelDescription(for: difficultyLevel)))
        - Skill Level: \(skillLevel) (\(selectedSkillLevel.description))
        - Total Duration: \(duration) weeks
        - Training Schedule: \(recurringDays.isEmpty ? "Not specified" : recurringDays) (\(sessionsPerWeek) sessions per week)
        - Session Duration: \(sessionDuration) minutes per session
        - Number of enrolled athletes: \(enrolledStudents.count)
        """
        
        // Add program objectives if available
        if !program.objectives.isEmpty {
            promptContext += "\n\nPROGRAM OBJECTIVES:\n"
            for objective in program.objectives {
                promptContext += "- \(objective)\n"
            }
        }
        
        // Add program description if available
        if let description = program.description, !description.isEmpty {
            promptContext += "\nPROGRAM DESCRIPTION:\n\(description)\n"
        }
        
        // Add coach's optional focus
        if !aiPrompt.isEmpty {
            promptContext += "\n\nOPTIONAL TRAINING FOCUS:\n\(aiPrompt)"
        }
        
        promptContext += """
        
        
        REQUIREMENTS BASED ON DIFFICULTY LEVEL (\(difficultyLevel)/10):
        \(difficultyRequirements(for: difficultyLevel))
        
        EUROPEAN BASKETBALL DEVELOPMENT GUIDELINES:
        - Follow FIBA youth development framework for \(category)
        - Age-appropriate progressions and skill development
        - Include proper warm-up (10-15 min) and cool-down (5-10 min) in each session
        - Focus on fundamentals: ball handling, passing, shooting, footwork, defense
        - Include game-based learning and small-sided games (3v3, 4v4)
        - Balance technical skills with tactical understanding
        - Consider physical development stages for \(ageGroup)
        - Emphasize player development over winning at this age
        
        Generate 3-4 training phases with specific sessions for each phase.
        Each session should have clear objectives and drill progressions appropriate for the difficulty level.
        Total sessions should equal: \(duration) weeks × \(sessionsPerWeek) sessions/week = \(duration * sessionsPerWeek) sessions.
        """
        
        Task {
            do {
                let response: AIProgramPhasesResponse = try await SupabaseManager.shared.invokeFunction(
                    name: "generate_program_phases",
                    body: [
                        "prompt": promptContext,
                        "category": category,
                        "ageGroup": ageGroup,
                        "skillLevel": skillLevel,
                        "durationWeeks": String(duration),
                        "difficultyLevel": String(difficultyLevel),
                        "sessionsPerWeek": String(sessionsPerWeek)
                    ]
                )
                
                await MainActor.run {
                    // Create phases and sessions from AI response
                    createPhasesFromAIResponse(response)
                    isAIProcessing = false
                    showingAIGenerator = false
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = "Failed to generate: \(error.localizedDescription)"
                    isAIProcessing = false
                }
            }
        }
    }
    
    private func createPhasesFromAIResponse(_ response: AIProgramPhasesResponse) {
        var currentDate = program.startDate ?? Date()
        let calendar = Calendar.current
        
        // Calculate sessions per week based on recurring days
        let sessionsPerWeek = program.recurringDays.isEmpty ? 1 : program.recurringDays.count
        let totalWeeks = program.durationWeeks
        let totalSessions = totalWeeks * sessionsPerWeek
        
        // Distribute sessions across phases
        let phaseCount = response.phases.count
        let sessionsPerPhase = totalSessions / phaseCount
        let extraSessions = totalSessions % phaseCount
        
        debugLog("📊 Auto-populate: \(totalWeeks) weeks × \(sessionsPerWeek) sessions/week = \(totalSessions) total sessions across \(phaseCount) phases")
        
        // Use batch mode to prevent fullSync for each add - sync once at end
        dataManager.beginBatchMode()
        
        var sessionIndex = 0
        
        for (phaseIndex, phaseData) in response.phases.enumerated() {
            // Calculate sessions for this phase (distribute extras to early phases)
            let sessionsInThisPhase = sessionsPerPhase + (phaseIndex < extraSessions ? 1 : 0)
            let weeksInThisPhase = max(1, sessionsInThisPhase / sessionsPerWeek)
            
            // Convert focus strings to TrainingFocus enum
            let focusValues: [TrainingFocus] = phaseData.focus.compactMap { focusString in
                TrainingFocus(rawValue: focusString.lowercased().replacingOccurrences(of: " ", with: ""))
            }
            
            let phase = MicroCycle(
                programId: program.id,
                phaseNumber: phaseIndex + 1,
                title: phaseData.title,
                focus: focusValues.isEmpty ? [.shooting] : focusValues,
                durationWeeks: weeksInThisPhase,
                description: phaseData.description,
                objectives: phaseData.objectives
            )
            dataManager.addMicroCycle(phase)
            
            debugLog("  📌 Phase \(phaseIndex + 1): \(phase.title) - \(weeksInThisPhase) weeks, \(sessionsInThisPhase) sessions")
            
            // Create sessions for this phase based on program's recurring days
            for sessionNum in 0..<sessionsInThisPhase {
                guard sessionIndex < totalSessions else { break }
                
                // Use AI session data if available, otherwise create generic session
                let aiSession = sessionNum < phaseData.sessions.count ? phaseData.sessions[sessionNum] : nil
                
                // Calculate session date based on recurring days
                var sessionDate = currentDate
                if !program.recurringDays.isEmpty {
                    // Use program's recurring days in order
                    let dayIndex = sessionNum % program.recurringDays.count
                    let targetDay = program.recurringDays.sorted(by: { $0.rawValue < $1.rawValue })[dayIndex]
                    
                    // Find next occurrence of this day
                    let currentWeekday = calendar.component(.weekday, from: currentDate)
                    let targetWeekday = targetDay.rawValue
                    var daysToAdd = targetWeekday - currentWeekday
                    if daysToAdd < 0 { daysToAdd += 7 }
                    
                    // Add weeks for sessions beyond the first week
                    let weekOffset = sessionNum / program.recurringDays.count
                    daysToAdd += weekOffset * 7
                    
                    sessionDate = calendar.date(byAdding: .day, value: daysToAdd, to: currentDate) ?? currentDate
                }
                
                // Set session start time
                var startTime = sessionDate
                if let defaultTime = program.defaultSessionTime {
                    let timeComponents = calendar.dateComponents([.hour, .minute], from: defaultTime)
                    startTime = calendar.date(bySettingHour: timeComponents.hour ?? 18, minute: timeComponents.minute ?? 0, second: 0, of: sessionDate) ?? sessionDate
                } else {
                    startTime = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: sessionDate) ?? sessionDate
                }
                
                // Calculate end time
                let duration = aiSession?.durationMinutes ?? program.defaultSessionDurationMinutes ?? 60
                let endTime = calendar.date(byAdding: .minute, value: duration, to: startTime) ?? startTime
                
                // Get location name
                let locationName = program.locationName ?? (program.locationId != nil ? dataManager.locations.first(where: { $0.id == program.locationId })?.name : nil)
                
                // Use AI-generated title or create default
                let sessionTitle = aiSession?.title ?? "\(phase.title) - Session \(sessionNum + 1)"
                
                let session = SessionEvent(
                    microCycleId: phase.id,
                    programId: program.id,
                    sessionType: .training,
                    title: sessionTitle,
                    date: sessionDate,
                    startTime: startTime,
                    endTime: endTime,
                    location: locationName,
                    notes: aiSession?.description
                )
                dataManager.addSessionEvent(session)
                
                sessionIndex += 1
            }
            
            // Move current date forward for next phase (continuous, no gaps)
            currentDate = calendar.date(byAdding: .weekOfYear, value: weeksInThisPhase, to: currentDate) ?? currentDate
        }
        
        debugLog("✅ Auto-populate complete: Created \(sessionIndex) sessions across \(phaseCount) phases")
        
        // End batch mode and sync all created phases/sessions at once
        dataManager.endBatchModeAndSync()
    }
    
    // MARK: - Hero Header with Map Background
    // MARK: - Average Performance (based on existing student grades A/B/C)
    private var averagePerformance: Double {
        let gradedStudents = enrolledStudents.filter { $0.performanceGrade != nil && $0.performanceGrade != .ungraded }
        guard !gradedStudents.isEmpty else { return 0 }
        
        // Convert grades to numeric: A=10, B=6.5, C=3
        let total = gradedStudents.reduce(0.0) { sum, student in
            switch student.performanceGrade {
            case .A: return sum + 10.0
            case .B: return sum + 6.5
            case .C: return sum + 3.0
            default: return sum
            }
        }
        return total / Double(gradedStudents.count)
    }
    
    // Average grade letter based on enrolled students' existing grades
    private var averageGradeLetter: PerformanceGrade {
        let gradedStudents = enrolledStudents.filter { $0.performanceGrade != nil && $0.performanceGrade != .ungraded }
        guard !gradedStudents.isEmpty else { return .ungraded }
        
        // Count each grade
        let aCount = gradedStudents.filter { $0.performanceGrade == .A }.count
        let bCount = gradedStudents.filter { $0.performanceGrade == .B }.count
        let cCount = gradedStudents.filter { $0.performanceGrade == .C }.count
        
        // Find most common, or average if tied
        let total = aCount * 3 + bCount * 2 + cCount * 1
        let avg = Double(total) / Double(gradedStudents.count)
        
        if avg >= 2.5 { return .A }
        if avg >= 1.5 { return .B }
        return .C
    }
    
    // Look up custom mascot icon from category
    #if canImport(UIKit)
    private var customMascotIcon: UIImage? {
        let matchingCategory = dataManager.ageCategories.first {
            $0.shortName.uppercased() == program.ageGroup.rawValue.uppercased()
        }
        return matchingCategory?.customIconImage
    }
    #elseif canImport(AppKit)
    private var customMascotIcon: NSImage? {
        let matchingCategory = dataManager.ageCategories.first {
            $0.shortName.uppercased() == program.ageGroup.rawValue.uppercased()
        }
        guard let data = matchingCategory?.customIconData else { return nil }
        return NSImage(data: data)
    }
    #endif
    
    private var heroHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return VStack(spacing: 16) {
            // Centered Mascot Circle with Performance Ring
            VStack(spacing: 12) {
                ZStack {
                    // Performance ring background
                    Circle()
                        .stroke(categoryColor.opacity(0.15), lineWidth: 6)
                        .frame(width: 100, height: 100)
                    
                    // Performance ring progress
                    Circle()
                        .trim(from: 0, to: min(averagePerformance / 10.0, 1.0))
                        .stroke(categoryColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                    
                    // Mascot circle
                    Circle()
                        .fill(categoryColor.opacity(0.12))
                        .frame(width: 84, height: 84)
                    
                    // Mascot icon (custom or fallback)
                    if let customIcon = customMascotIcon {
                        #if canImport(UIKit)
                        Image(uiImage: customIcon)
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                        #elseif canImport(AppKit)
                        Image(nsImage: customIcon)
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                        #endif
                    } else {
                        Image(systemName: program.mascotIcon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(categoryColor)
                    }
                    
                    // Performance badge (using existing student grades A/B/C)
                    if !enrolledStudents.isEmpty && averageGradeLetter != .ungraded {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(averageGradeLetter.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(categoryColor)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppTheme.background, lineWidth: 2))
                            }
                        }
                        .frame(width: 100, height: 100)
                    }
                }
                
                // Program name + subtitle
                VStack(spacing: 4) {
                    Text(program.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 8) {
                        // Age group badge
                        Text(program.ageGroup.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor)
                            .cornerRadius(4)
                        
                        // Schedule
                        Text(scheduleDisplay)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        // Duration
                        Text("• \(program.durationWeeks)" + (isChinese ? "周" : "wks"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            .padding(.top, 8)
            
            // Compact Stats Row
            HStack(spacing: 0) {
                compactStat(value: "\(enrolledStudents.count)", label: isChinese ? "学员" : "Athletes", color: .green)
                compactStatDivider
                compactStat(value: "\(microCycles.count)", label: isChinese ? "阶段" : "Phases", color: .purple)
                compactStatDivider
                compactStat(value: "\(sessionCount)", label: isChinese ? "课程" : "Sessions", color: .orange)
                compactStatDivider
                compactStat(value: String(format: "%.1f", averagePerformance), label: isChinese ? "评分" : "Avg", color: categoryColor)
            }
            .padding(.vertical, 12)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            
            // Coach row (compact, inline)
            if let coachId = program.coachId,
               let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.avatarColor(coach.avatarColor))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(coach.initials)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    Text(coach.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text(coach.role.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Spacer()
                    
                    // Location if available
                    if let location = mapLocation {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                            Text(location.name)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func compactStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var compactStatDivider: some View {
        Rectangle()
            .fill(AppTheme.textTertiary.opacity(0.2))
            .frame(width: 1, height: 32)
    }
    
    // MARK: - Map Hero Stat Helper
    private func mapHeroStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private func heroStat(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Amex Hero Stat
    private func amexHeroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(categoryTextColor)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.5)
                .foregroundColor(categorySecondaryTextColor)
        }
    }
    
    // MARK: - Stats Board
    private var statsBoard: some View {
        HStack(spacing: 0) {
            statCell(value: "\(program.durationWeeks)", label: LocalizationManager.shared.currentLanguage == .chinese ? "周" : "Weeks", color: .blue)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            statCell(value: "\(microCycles.count)", label: LocalizationManager.shared.currentLanguage == .chinese ? "阶段" : "Phases", color: .purple)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            statCell(value: "\(sessionCount)", label: LocalizationManager.shared.currentLanguage == .chinese ? "课程" : "Sessions", color: .orange)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            statCell(value: "\(enrolledStudents.count)", label: LocalizationManager.shared.currentLanguage == .chinese ? "学员" : "Athletes", color: .green)
        }
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Objectives Section
    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "目标" : "OBJECTIVES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(program.objectives.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(program.objectives, id: \.self) { objective in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text(objective)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(20)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Athletes Section (Elegant Display)
    private var athletesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "已报名学员" : "ENROLLED ATHLETES")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "\(enrolledStudents.count) 名学员" : "\(enrolledStudents.count) athlete\(enrolledStudents.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                Button(action: { showingEditStudents = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: enrolledStudents.isEmpty ? "plus" : "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? (enrolledStudents.isEmpty ? "添加" : "管理") : (enrolledStudents.isEmpty ? "Add" : "Manage"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(programColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(programColor.opacity(0.12))
                    .cornerRadius(16)
                }
            }
            
            if enrolledStudents.isEmpty {
                // Empty state
                Button(action: { showingEditStudents = true }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(programColor.opacity(0.1))
                                .frame(width: 50, height: 50)
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20))
                                .foregroundColor(programColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "暂无报名学员" : "No athletes enrolled yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加学员以跟踪他们的进度" : "Add athletes to track their progress")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                    }
                    .padding(16)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                }
            } else if enrolledStudents.count <= 4 {
                // Grid layout for small number of athletes
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(enrolledStudents) { student in
                        NavigationLink(destination: StudentDetailView(student: student)) {
                            AthleteCard(student: student, accentColor: programColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Stacked avatars with list for larger groups
                VStack(spacing: 12) {
                    // Stacked avatar preview
                    HStack(spacing: -12) {
                        ForEach(Array(enrolledStudents.prefix(5).enumerated()), id: \.element.id) { index, student in
                            StudentAvatarView(student: student, size: 44)
                                .overlay(
                                    Circle()
                                        .stroke(AppTheme.cardBackground, lineWidth: 3)
                                )
                                .zIndex(Double(5 - index))
                        }
                        
                        if enrolledStudents.count > 5 {
                            ZStack {
                                Circle()
                                    .fill(programColor)
                                    .frame(width: 44, height: 44)
                                Text("+\(enrolledStudents.count - 5)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.cardBackground, lineWidth: 3)
                            )
                        }
                        
                        Spacer()
                    }
                    
                    // Compact list
                    VStack(spacing: 8) {
                        ForEach(enrolledStudents) { student in
                            NavigationLink(destination: StudentDetailView(student: student)) {
                                HStack(spacing: 12) {
                                    StudentAvatarView(student: student, size: 36)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(student.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                        if let age = student.age {
                                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "\(age) 岁" : "\(age) years old")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if enrolledStudents.count > 3 {
                            Button(action: { showingEditStudents = true }) {
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "查看全部 \(enrolledStudents.count) 名学员" : "View all \(enrolledStudents.count) athletes")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(programColor)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Athlete Card (Elegant Grid Item)
struct AthleteCard: View {
    let student: Student
    let accentColor: Color
    
    private var ageText: String {
        if let age = student.age {
            return LocalizationManager.shared.currentLanguage == .chinese ? "\(age) 岁" : "\(age) years old"
        }
        return LocalizationManager.shared.currentLanguage == .chinese ? "学员" : "Athlete"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 44)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(student.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(ageText)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Phases Section Extension
extension FlightyProgramDetailView {
    // MARK: - Phases Section (Collapsible)
    var phasesSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return VStack(alignment: .leading, spacing: 12) {
            // Collapsible Header Row
            HStack(spacing: 8) {
                // Collapse toggle button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPhasesExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isPhasesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textTertiary)
                            .frame(width: 14)
                        
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 13))
                            .foregroundColor(categoryColor.accessibleText)
                        
                        Text(isChinese ? "训练阶段" : "PHASES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("\(microCycles.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(categoryColor.accessibleText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Action buttons (only when expanded or editing)
                if isPhasesExpanded {
                    if isEditingPhases {
                        if !selectedPhaseIds.isEmpty {
                            Button(action: { showingMassDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                        }
                        Button(action: {
                            isEditingPhases = false
                            selectedPhaseIds.removeAll()
                        }) {
                            Text(isChinese ? "完成" : "Done")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(categoryColor.accessibleText)
                        }
                    } else {
                        if !microCycles.isEmpty && authManager.canEditPhases {
                            Button(action: { isEditingPhases = true }) {
                                Text(isChinese ? "编辑" : "Edit")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        if authManager.canCreatePhases {
                            Button(action: { showingAddPhase = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(categoryColor.accessibleText)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.cardBackground)
            .cornerRadius(10)
            
            // Expandable Content
            if isPhasesExpanded {
                if microCycles.isEmpty {
                    // Empty state - compact
                    VStack(spacing: 10) {
                        Button(action: { showingAIGenerator = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16))
                                    .foregroundColor(.purple)
                                Text(isChinese ? "AI 生成计划" : "Generate with AI")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .padding(12)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                        }
                        
                        Button(action: { showingAddPhase = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(categoryColor.accessibleText)
                                Text(isChinese ? "手动创建" : "Create Manually")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                            }
                            .padding(12)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                        }
                    }
                } else {
                    // Phase list - compact cards
                    VStack(spacing: 8) {
                        ForEach(microCycles) { cycle in
                            if isEditingPhases {
                                Button(action: {
                                    if selectedPhaseIds.contains(cycle.id) {
                                        selectedPhaseIds.remove(cycle.id)
                                    } else {
                                        selectedPhaseIds.insert(cycle.id)
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedPhaseIds.contains(cycle.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedPhaseIds.contains(cycle.id) ? categoryColor.accessibleText : AppTheme.textTertiary)
                                        
                                        compactPhaseRow(cycle)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: FlightyMicroCycleDetailView(microCycle: cycle, program: program)) {
                                    compactPhaseRow(cycle)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { deletePhase(cycle) } label: {
                                        Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Compact phase row for collapsed view
    private func compactPhaseRow(_ cycle: MicroCycle) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return HStack(spacing: 10) {
            // Phase number badge
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(cycle.phaseNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(categoryColor.accessibleText)
            }
            
            // Title and focus
            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                if !cycle.focus.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(cycle.focus.prefix(2), id: \.self) { focus in
                            Text(focus.displayName)
                                .font(.system(size: 10))
                                .foregroundColor(categoryColor.accessibleText)
                        }
                        if cycle.focus.count > 2 {
                            Text("+\(cycle.focus.count - 2)")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Duration
            Text("\(cycle.durationWeeks)" + (isChinese ? "周" : "w"))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
        }
        .padding(10)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
    }
}

// MARK: - Enhanced Phase Card (Stands Out)
struct EnhancedPhaseCard: View {
    let microCycle: MicroCycle
    var accentColor: Color = .blue
    let totalPhases: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Phase number indicator
            ZStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 36, height: 36)
                Text("\(microCycle.phaseNumber)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(microCycle.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let description = microCycle.description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                
                // Focus tags
                if !microCycle.focus.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(microCycle.focus.prefix(3), id: \.self) { focus in
                            Text(focus.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(accentColor.accessibleText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accentColor.opacity(0.12))
                                .cornerRadius(4)
                        }
                        if microCycle.focus.count > 3 {
                            Text("+\(microCycle.focus.count - 3)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Duration & chevron
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(microCycle.durationWeeks)w")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Flighty Phase Card (Dark Theme)
struct FlightyPhaseCard: View {
    let microCycle: MicroCycle
    var accentColor: Color = .blue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("PHASE \(microCycle.phaseNumber)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor.accessibleText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.15))
                    .cornerRadius(4)
                
                Text(microCycle.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.5))
            }
            
            // Description
            if let description = microCycle.description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(2)
            }
            
            // Focus tags
            if !microCycle.focus.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(microCycle.focus.prefix(4), id: \.self) { focus in
                            HStack(spacing: 4) {
                                Image(systemName: focus.icon)
                                    .font(.system(size: 9))
                                Text(focus.displayName)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            
            // Stats row
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("\(microCycle.durationWeeks) weeks")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                // Intensity dots
                HStack(spacing: 3) {
                    Text("Intensity")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    ForEach(1...5, id: \.self) { i in
                        Circle()
                            .fill(i <= microCycle.intensity / 2 ? Color.orange : Color.white.opacity(0.15))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
}

// MARK: - Flighty MicroCycle Detail View (Phase Detail)
struct FlightyMicroCycleDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let microCycle: MicroCycle
    let program: Program?
    
    @State private var showingAddSession = false
    
    var phaseSessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { $0.microCycleId == microCycle.id }
            .sorted { $0.date < $1.date }
    }
    
    var accentColor: Color {
        program.map { Color(hex: $0.colorHex) } ?? .blue
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero header
                phaseHeader
                
                // Stats
                phaseStats
                
                // Content
                VStack(spacing: 20) {
                    // Sessions
                    sessionsSection
                    
                    // Focus areas
                    if !microCycle.focus.isEmpty {
                        focusSection
                    }
                    
                    // Objectives
                    if !microCycle.objectives.isEmpty {
                        objectivesSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(20)
            }
        }
        .background(Color(hex: "#f5f5f7").ignoresSafeArea())
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                Button(action: { showingAddSession = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showingAddSession) {
            FlightyCreateSessionView(
                microCycle: microCycle,
                program: program,
                sessionNumber: phaseSessions.count + 1
            )
        }
    }
    
    // MARK: - Phase Header
    private var phaseHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase badge
            HStack(spacing: 8) {
                Text("PHASE \(microCycle.phaseNumber)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor.accessibleText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.12))
                    .cornerRadius(6)
                
                if let program = program {
                    HStack(spacing: 4) {
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 10))
                        Text(program.mascot.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(accentColor.accessibleText)
                }
            }
            
            // Title
            Text(microCycle.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
            
            // Description
            if let description = microCycle.description {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Phase Stats
    private var phaseStats: some View {
        HStack(spacing: 0) {
            phaseStat(value: "\(microCycle.durationWeeks)", label: "Weeks", color: .blue)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            phaseStat(value: "\(microCycle.intensity)/10", label: "Intensity", color: .orange)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            phaseStat(value: "\(microCycle.volume)/10", label: "Volume", color: .purple)
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            phaseStat(value: "\(phaseSessions.count)", label: "Sessions", color: .green)
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private func phaseStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Sessions Section
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button(action: { showingAddSession = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(accentColor.accessibleText)
                }
            }
            
            if phaseSessions.isEmpty {
                Button(action: { showingAddSession = true }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(accentColor.accessibleText)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No sessions scheduled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                            Text("Tap to create your first session")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(16)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(phaseSessions) { session in
                        NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .architect)) {
                            FlightyPhaseSessionRow(session: session, accentColor: accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Focus Section
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FOCUS AREAS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            FlowLayout(spacing: 8) {
                ForEach(microCycle.focus, id: \.self) { focus in
                    HStack(spacing: 6) {
                        Image(systemName: focus.icon)
                            .font(.system(size: 12))
                        Text(focus.displayName)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accentColor.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Objectives Section
    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OBJECTIVES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(microCycle.objectives, id: \.self) { objective in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "target")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                        Text(objective)
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Flighty Phase Session Row (Light Theme)
struct FlightyPhaseSessionRow: View {
    let session: SessionEvent
    var accentColor: Color = .blue
    
    private var isPast: Bool {
        session.endTime < Date()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Session type icon
            Image(systemName: session.sessionType.icon)
                .font(.system(size: 16))
                .foregroundColor(accentColor)
                .frame(width: 40, height: 40)
                .background(accentColor.opacity(0.12))
                .cornerRadius(10)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isPast ? .gray : .black)
                    .lineLimit(1)
                
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 11))
                    }
                    
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(session.startTime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                    }
                    
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(session.durationMinutes)m")
                            .font(.system(size: 11))
                    }
                }
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Status
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(12)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch session.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        case .skipped: return .gray
        }
    }
}

// MARK: - Program Skill Targets Sheet
struct ProgramSkillTargetsSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @Binding var program: Program
    
    @State private var targets: ProgramSkillTargets
    @State private var hasChanges = false
    
    init(program: Binding<Program>) {
        self._program = program
        self._targets = State(initialValue: program.wrappedValue.skillTargets ?? ProgramSkillTargets())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    overallTargetCard
                    skillSlidersSection
                    if !program.enrolledStudentIds.isEmpty {
                        athletesComparisonSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Skill Targets")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTargets() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                }
            }
        }
    }
    
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(program.mascotColor)
                    .frame(width: 50, height: 50)
                Image(systemName: program.mascotIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("SKILL EXPECTATIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(program.mascotColor)
                Text(program.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(program.ageGroup.displayName) • \(program.enrolledCount) athletes")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var overallTargetCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Overall Target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text(String(format: "%.1f", targets.overallTarget))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(targets.overallTarget >= 7 ? .green : .orange)
                Text("/ 10")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(targets.overallTarget >= 7 ? Color.green : Color.orange)
                        .frame(width: geometry.size.width * targets.overallTarget / 10, height: 12)
                }
            }
            .frame(height: 12)
            Text("Athletes should aim to meet or exceed these skill levels")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var skillSlidersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SKILL TARGETS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(spacing: 14) {
                skillSlider(label: "Scoring", value: $targets.scoring, color: .orange, icon: "scope")
                skillSlider(label: "Playmaking", value: $targets.playmaking, color: .blue, icon: "arrow.triangle.branch")
                skillSlider(label: "Rebounding", value: $targets.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                skillSlider(label: "Defense", value: $targets.defense, color: .red, icon: "shield.fill")
                skillSlider(label: "Athleticism", value: $targets.athleticism, color: .green, icon: "figure.run")
                skillSlider(label: "Intangibles", value: $targets.intangibles, color: .teal, icon: "star.fill")
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func skillSlider(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 28)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); hasChanges = true }
            ), in: 1...10, step: 1)
            .tint(color)
        }
    }
    
    private var athletesComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ENROLLED ATHLETES")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(program.enrolledStudentIds.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(program.mascotColor)
                    .cornerRadius(8)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(enrolledStudentsWithSkills, id: \.student.id) { item in
                    athleteRow(student: item.student, player: item.player)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var enrolledStudentsWithSkills: [(student: Student, player: Player?)] {
        program.enrolledStudentIds.compactMap { studentId in
            guard let student = dataManager.students.first(where: { $0.id == studentId }) else { return nil }
            let player = dataManager.players.first(where: { $0.studentId == studentId })
            return (student, player)
        }
    }
    
    private func athleteRow(student: Student, player: Player?) -> some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                if let player = player {
                    let belowCount = targets.skillsBelowTarget(player.skills)
                    if belowCount == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Meets all targets")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.green)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("\(belowCount) skill\(belowCount > 1 ? "s" : "") below target")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    }
                } else {
                    Text("No skills evaluated")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            Spacer()
            if let player = player {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", player.skills.overallRating))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(player.skills.overallRating >= targets.overallTarget ? .green : .orange)
                    let diff = player.skills.overallRating - targets.overallTarget
                    Text(diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(diff >= 0 ? .green : .orange)
                }
            }
        }
        .padding(10)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
    }
    
    private func saveTargets() {
        targets.lastUpdatedDate = Date()
        program.skillTargets = targets
        program.updatedAt = Date()
        dataManager.updateProgram(program)
        HapticFeedback.notification(.success)
        dismiss()
    }
}

// MARK: - AI Response Types
struct AIProgramPhasesResponse: Codable {
    let phases: [AIPhaseData]
}

struct AIPhaseData: Codable {
    let title: String
    let focus: [String]
    let durationWeeks: Int
    let description: String
    let objectives: [String]
    let sessions: [AISessionData]
}

struct AISessionData: Codable {
    let title: String
    let sessionType: String
    let durationMinutes: Int
    let description: String
    let dayOfWeek: String?
    let weekNumber: Int?
    let objectives: [String]?
    let warmupDrills: [String]?
    let mainDrills: [String]?
    let cooldownActivities: [String]?
}

// MARK: - AI Phase Generator Sheet
struct AIPhaseGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let program: Program
    @Binding var aiPrompt: String
    @Binding var selectedSkillLevel: FlightyProgramDetailView.SkillLevel
    @Binding var isProcessing: Bool
    @Binding var errorMessage: String?
    let onGenerate: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 70, height: 70)
                            Image(systemName: "sparkles")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                        
                        Text("AI Training Plan Generator")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Generate professional training phases and sessions based on European youth basketball development methodology")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    
                    // Program Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Program Details")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        HStack(spacing: 16) {
                            infoItem(icon: "person.3.fill", label: "Age Group", value: program.ageGroup.displayName)
                            infoItem(icon: "clock.fill", label: "Duration", value: "\(program.durationWeeks) weeks")
                        }
                        
                        HStack(spacing: 16) {
                            infoItem(icon: "calendar", label: "Days", value: program.recurringDays.isEmpty ? "Not set" : program.recurringDays.map { $0.shortName }.joined(separator: ", "))
                            infoItem(icon: "timer", label: "Session", value: "\(program.defaultSessionDurationMinutes ?? 60) min")
                        }
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    
                    // Skill Level Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Student Skill Level")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        ForEach(FlightyProgramDetailView.SkillLevel.allCases, id: \.self) { level in
                            Button(action: { selectedSkillLevel = level }) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedSkillLevel == level ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedSkillLevel == level ? .blue : AppTheme.textTertiary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.rawValue)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Text(level.description)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedSkillLevel == level ? Color.blue.opacity(0.1) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedSkillLevel == level ? Color.blue : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Custom Goals Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Training Goals (Optional)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        Text("Describe specific skills, objectives, or areas you want to focus on")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        TextEditor(text: $aiPrompt)
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.textTertiary.opacity(0.2), lineWidth: 1)
                            )
                        
                        // Example prompts
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Example prompts:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            ForEach([
                                "Focus on ball handling and court vision",
                                "Prepare team for upcoming tournament",
                                "Improve shooting technique and confidence"
                            ], id: \.self) { example in
                                Button(action: { aiPrompt = example }) {
                                    Text("• \(example)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Generate Training Plan")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onGenerate) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Generate")
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
    
    private func infoItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        FlightyProgramDetailView(
            program: Program(
                name: "Spring Training",
                ageGroup: .u12,
                colorHex: "#FF6B35",
                mascot: .lion,
                stars: .two
            )
        )
        .environmentObject(DataManager.shared)
    }
}
