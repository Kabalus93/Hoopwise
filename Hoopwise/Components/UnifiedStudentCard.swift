import SwiftUI

// MARK: - Unified Student Card
/// A comprehensive, reusable student card that displays all available student information
/// in a smart, non-overwhelming way using expandable sections.
/// Use this component anywhere a student is referenced in the app.

struct UnifiedStudentCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    
    // Display mode
    var mode: DisplayMode = .full
    var showQuickActions: Bool = true
    
    // State for score detail popup
    @State private var selectedScoreType: ScoreType? = nil
    
    enum DisplayMode {
        case compact      // For lists - shows avatar, name, key stats
        case summary      // For dashboards - shows avatar, name, risk, contract status
        case full         // For detail views - shows everything with expandable sections
    }
    
    enum ScoreType: String, Identifiable {
        case service = "Service Quality"
        case performance = "Performance"
        case financials = "Financials"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .service: return "heart.text.square.fill"
            case .performance: return "chart.line.uptrend.xyaxis"
            case .financials: return "dollarsign.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .service: return .purple
            case .performance: return .blue
            case .financials: return .green
            }
        }
        
        var shortLabel: String {
            switch self {
            case .service: return "Service"
            case .performance: return "Perform"
            case .financials: return "Financial"
            }
        }
        
        var chineseLabel: String {
            switch self {
            case .service: return "服务"
            case .performance: return "表现"
            case .financials: return "财务"
            }
        }
        
        var localizedName: String {
            return rawValue
        }
        
        var localizedNameChinese: String {
            switch self {
            case .service: return "服务质量"
            case .performance: return "表现"
            case .financials: return "财务"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var player: Player? {
        dataManager.player(for: student.id)
    }
    
    private var contract: Contract? {
        dataManager.currentContract(for: student.id)
    }
    
    private var allContracts: [Contract] {
        dataManager.allContracts(for: student.id)
    }
    
    private var measurementSummary: MeasurementSummary {
        dataManager.measurementSummary(for: student.id)
    }
    
    private var teams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(student.id) }
    }
    
    private var primaryTeam: Team? {
        teams.first
    }
    
    private var seasonStats: SeasonStats? {
        guard let player = player else { return nil }
        return dataManager.seasonStats.first { $0.playerId == player.id }
    }
    
    private var program: Program? {
        guard let programId = student.programId else { return nil }
        return dataManager.programs.first { $0.id == programId }
    }
    
    /// First program where this student is enrolled
    private var enrolledProgram: Program? {
        dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) }
    }
    
    /// All programs where this student is enrolled
    private var enrolledPrograms: [Program] {
        dataManager.programs.filter { $0.enrolledStudentIds.contains(student.id) }
    }
    
    /// Next upcoming session for this student (from any program they're enrolled in)
    private var nextProgramSession: SessionEvent? {
        let now = Date()
        
        // Find all programs where this student is enrolled
        let enrolledProgramIds = dataManager.programs
            .filter { $0.enrolledStudentIds.contains(student.id) }
            .map { $0.id }
        
        // Also check if student has a direct programId assignment
        var allProgramIds = Set(enrolledProgramIds)
        if let directProgramId = student.programId {
            allProgramIds.insert(directProgramId)
        }
        
        // Find next session from any of these programs, or where student is in attendeeIds
        // Check both program enrollment and direct attendee list
        return dataManager.sessionEvents
            .filter { session in
                let isInProgram = !allProgramIds.isEmpty && (session.programId.map { allProgramIds.contains($0) } ?? false)
                let isAttendee = session.attendeeIds.contains(student.id)
                let isUpcoming = session.date >= now && session.status != .completed && session.status != .cancelled
                return (isInProgram || isAttendee) && isUpcoming
            }
            .sorted { $0.date < $1.date }
            .first
    }
    
    private var assignedCoach: StaffCoach? {
        guard let coachId = student.coachId else { return nil }
        return dataManager.staffCoaches.first { $0.id == coachId }
    }
    
    private var ageCategory: CustomAgeCategory? {
        guard let categoryId = student.categoryId else { return nil }
        return dataManager.ageCategories.first { $0.id == categoryId }
    }
    
    // Intelligence data
    private var attendanceRecords: [AttendanceRecord] {
        // Build attendance records from session events
        dataManager.sessionEvents.compactMap { session -> AttendanceRecord? in
            guard session.attendeeIds.contains(student.id) else { return nil }
            let didAttend = session.actualAttendeeIds.contains(student.id)
            return AttendanceRecord(
                studentId: student.id,
                sessionId: session.id,
                status: didAttend ? .present : .absent,
                recordedAt: session.date
            )
        }
    }
    
    private var churnRiskAssessment: StudentIntelligence.ChurnRiskAssessment {
        StudentIntelligence.analyzeChurnRisk(
            student: student,
            contract: contract,
            attendanceRecords: attendanceRecords,
            performanceStats: seasonStats
        )
    }
    
    private var churnRiskScore: Double {
        churnRiskAssessment.score
    }
    
    private var churnRiskLevel: StudentIntelligence.ChurnRiskLevel {
        churnRiskAssessment.level
    }
    
    private var recentSessions: [SessionEvent] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return dataManager.sessionEvents.filter { session in
            session.attendeeIds.contains(student.id) && session.date >= thirtyDaysAgo
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        switch mode {
        case .compact:
            compactCard
        case .summary:
            summaryCard
        case .full:
            fullCard
        }
    }
    
    // MARK: - Compact Card (for lists)
    
    private var compactCard: some View {
        HStack(spacing: 12) {
            // Avatar with risk indicator
            ZStack(alignment: .bottomTrailing) {
                StudentAvatarView(student: student, size: 50)
                
                if churnRiskLevel == .high || churnRiskLevel == .critical {
                    Circle()
                        .fill(churnRiskLevel == .critical ? Color.red : Color.orange)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            
            // Main info
            VStack(alignment: .leading, spacing: 4) {
                // Language-aware name display
                if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(student.chineseName!)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(student.name)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(student.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                // Quick stats row
                HStack(spacing: 8) {
                    // Age
                    if let age = student.age {
                        quickStat(icon: "person.fill", value: "\(age)y")
                    }
                    
                    // Team badge
                    if let team = primaryTeam {
                        teamBadge(team)
                    }
                    
                    // Sessions left
                    if let contract = contract {
                        quickStat(
                            icon: "ticket.fill",
                            value: contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)",
                            color: (!contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 3) ? .orange : AppTheme.textTertiary
                        )
                    }
                    
                    // League stats
                    if let stats = seasonStats, stats.gamesPlayed > 0 {
                        Text("\(String(format: "%.1f", stats.ppg)) PPG")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Right side indicators
            VStack(alignment: .trailing, spacing: 4) {
                // Next session date/time for enrolled program
                if let session = nextProgramSession {
                    nextSessionBadge(session)
                } else if !enrolledPrograms.isEmpty {
                    // Show all enrolled programs if no upcoming sessions
                    ForEach(enrolledPrograms.prefix(2)) { program in
                        programBadge(program)
                    }
                    if enrolledPrograms.count > 2 {
                        Text("+\(enrolledPrograms.count - 2) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                if let contract = contract {
                    contractStatusBadge(contract)
                }
                
                if let lastContact = student.lastParentContact {
                    let daysSince = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
                    if daysSince > 14 {
                        HStack(spacing: 2) {
                            Image(systemName: "phone.badge.waveform")
                                .font(.system(size: 9))
                            Text("\(daysSince)d")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    /// Badge showing next session with program info (mascot, day, time, location)
    private func nextSessionBadge(_ session: SessionEvent) -> some View {
        let calendar = Calendar.current
        
        // Get the program for this session
        let sessionProgram: Program? = session.programId.flatMap { programId in
            dataManager.programs.first { $0.id == programId }
        }
        
        // Format time as "3pm" or "3:30AM"
        let timeFormatter = DateFormatter()
        let minute = calendar.component(.minute, from: session.startTime)
        timeFormatter.dateFormat = minute == 0 ? "ha" : "h:mma"
        let timeText = timeFormatter.string(from: session.startTime).uppercased()
        
        // Format day name
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let dayName = dayFormatter.string(from: session.date)
        
        // Get location name
        let locationName = session.location ?? sessionProgram?.locationName
        
        // Build display text
        var displayText = "\(dayName) \(timeText)"
        if let loc = locationName, !loc.isEmpty {
            displayText += " \(loc)"
        }
        
        // Use program color and mascot if available
        let programColor = sessionProgram?.mascotColor ?? AppTheme.textTertiary
        let mascotIcon = sessionProgram?.mascot.icon ?? "calendar.badge.clock"
        
        return HStack(spacing: 4) {
            Image(systemName: mascotIcon)
                .font(.system(size: 10))
            Text(displayText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(programColor.accessibleText)
    }
    
    /// Badge showing enrolled program info (mascot, recurring days, time, location)
    private func programBadge(_ program: Program) -> some View {
        // Build display text with recurring day, time, and location
        var displayParts: [String] = []
        
        // Add recurring day(s)
        if !program.recurringDays.isEmpty {
            let dayName = program.recurringDays.first?.displayName ?? ""
            displayParts.append(dayName)
        }
        
        // Add default session time
        if let time = program.defaultSessionTime {
            let timeFormatter = DateFormatter()
            let calendar = Calendar.current
            let minute = calendar.component(.minute, from: time)
            timeFormatter.dateFormat = minute == 0 ? "ha" : "h:mma"
            displayParts.append(timeFormatter.string(from: time).uppercased())
        }
        
        // Add location
        if let loc = program.locationName, !loc.isEmpty {
            displayParts.append(loc)
        }
        
        let displayText = displayParts.isEmpty ? program.name : displayParts.joined(separator: " ")
        
        return HStack(spacing: 4) {
            Image(systemName: program.mascot.icon)
                .font(.system(size: 10))
            Text(displayText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(program.mascotColor)
    }
    
    // MARK: - Summary Card (for dashboards)
    
    private var summaryCard: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 56)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Language-aware name display
                    if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.chineseName!)
                                .font(.system(size: 16, weight: .semibold))
                            Text(student.name)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Text(student.name)
                                .font(.system(size: 16, weight: .semibold))
                            
                            if let chinese = student.chineseName {
                                Text(chinese)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let age = student.age {
                            Text("\(age) years")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let team = primaryTeam {
                            teamBadge(team)
                        }
                        
                        if let program = program {
                            HStack(spacing: 3) {
                                Image(systemName: program.mascot.icon)
                                    .font(.system(size: 9))
                                Text(program.name)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(program.mascotColor)
                        }
                    }
                }
                
                Spacer()
                
                // Risk indicator
                riskIndicator
            }
            
            // Quick stats bar
            HStack(spacing: 0) {
                // Contract
                summaryStatCell(
                    icon: "ticket.fill",
                    value: contract != nil ? (contract!.isPayAsYouGo ? "∞" : "\(contract!.remainingSessions ?? 0)") : "—",
                    label: LocalizationManager.shared.currentLanguage == .chinese ? "课时" : "Sessions",
                    color: (contract?.remainingSessions ?? 0) <= 3 ? .orange : .blue
                )
                
                Divider().frame(height: 30)
                
                // League
                summaryStatCell(
                    icon: "basketball.fill",
                    value: seasonStats != nil ? String(format: "%.1f", seasonStats!.ppg) : "—",
                    label: "PPG",
                    color: .green
                )
                
                Divider().frame(height: 30)
                
                // Skills
                summaryStatCell(
                    icon: "star.fill",
                    value: player != nil ? String(format: "%.1f", player!.skills.overallRating) : "—",
                    label: LocalizationManager.shared.currentLanguage == .chinese ? "评分" : "Rating",
                    color: .purple
                )
                
                Divider().frame(height: 30)
                
                // Last contact
                summaryStatCell(
                    icon: "phone.fill",
                    value: lastContactLabel,
                    label: LocalizationManager.shared.currentLanguage == .chinese ? "联系" : "Contact",
                    color: lastContactColor
                )
            }
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground.opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private var lastContactLabel: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        guard let lastContact = student.lastParentContact else { return isChinese ? "从未" : "Never" }
        let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
        if days == 0 { return isChinese ? "今天" : "Today" }
        if days == 1 { return isChinese ? "1天" : "1d" }
        return isChinese ? "\(days)天" : "\(days)d"
    }
    
    private var lastContactColor: Color {
        guard let lastContact = student.lastParentContact else { return .red }
        let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
        if days <= 7 { return .green }
        if days <= 14 { return .orange }
        return .red
    }
    
    // MARK: - Full Card (for detail views)
    
    private var fullCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 16) {
            // Header with avatar and basic info (includes intelligence scores)
            fullCardHeader
            
            // League & Performance (expanded by default - shows radar and stats)
            ExpandableSection(title: isChinese ? "联赛与表现" : "League & Performance", icon: "basketball.fill", iconColor: .orange, defaultExpanded: true) {
                leaguePerformanceSection
            }
            
            // Skills Evaluation
            skillsSectionCard
            
            // Parent/Guardian & Touchpoints (moved to bottom)
            parentSectionCard
            
            // Program & Organization (moved to bottom)
            programSectionCard
        }
    }
    
    // MARK: - Contract Section Card (Always Visible)
    
    private var contractSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "合同与课程" : "Contract & Sessions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            if let contract = contract {
                // Contract status badge
                HStack {
                    Text(contract.status.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: contract.status.color))
                        .cornerRadius(12)
                    
                    Spacer()
                    
                    if let expiry = contract.expiryDate {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "到期 \(expiry.formatted(date: .abbreviated, time: .omitted))" : "Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(contract.isExpired ? .red : .secondary)
                    }
                }
                
                // Sessions progress
                VStack(spacing: 6) {
                    HStack {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "课时" : "Sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(contract.attendedSessions) / \(contract.totalSessions)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * CGFloat(contract.attendedSessions) / CGFloat(max(contract.totalSessions, 1)), height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? (contract.isPayAsYouGo ? "按次付费" : "\(contract.remainingSessions ?? 0) 剩余") : (contract.isPayAsYouGo ? "Pay As You Go" : "\(contract.remainingSessions ?? 0) remaining"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor((!contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 3) ? .orange : .secondary)
                        Spacer()
                    }
                }
                
                // Payment info
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "总额" : "Total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("¥\(Int(contract.totalAmount))")
                            .font(.system(size: 13, weight: .medium))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "已付" : "Paid")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("¥\(Int(contract.amountPaid))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(contract.isFullyPaid ? .green : .primary)
                    }
                    
                    if contract.outstandingBalance > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "待付" : "Due")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("¥\(Int(contract.outstandingBalance))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    // Perks
                    HStack(spacing: 8) {
                        if contract.jerseyGiven {
                            Image(systemName: "tshirt.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                        if contract.ballGiven {
                            Image(systemName: "basketball.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                        }
                    }
                }
            } else {
                // No contract
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "无有效合同" : "No active contract")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Skills Section Card (Always Visible)
    
    private var skillsSectionCard: some View {
        SkillsSectionCardView(student: student, player: player, program: enrolledProgram)
    }
    
    private func skillMiniBar(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value) / 10, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Parent Section Card (Merged with Touchpoints)
    
    private var parentSectionCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let touchpoints = student.parentalTouchpoints
        
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.teal)
                Text(isChinese ? "家长/监护人" : "Parent/Guardian")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            if let player = player, !player.parentInfo.name.isEmpty {
                HStack(spacing: 16) {
                    // Parent info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.parentInfo.name)
                            .font(.system(size: 14, weight: .medium))
                        Text(player.parentInfo.relationship)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Contact buttons
                    HStack(spacing: 12) {
                        if !player.parentInfo.phone.isEmpty {
                            Link(destination: URL(string: "tel:\(player.parentInfo.phone)")!) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                    .frame(width: 36, height: 36)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(10)
                            }
                        }
                        
                        if let email = player.parentInfo.email, !email.isEmpty {
                            Link(destination: URL(string: "mailto:\(email)")!) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(10)
                            }
                        }
                        
                        if let wechat = player.parentInfo.wechatId, !wechat.isEmpty {
                            Button(action: {}) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                    .frame(width: 36, height: 36)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundColor(.secondary)
                    Text(isChinese ? "未添加家长信息" : "No parent info added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Last contact / Touchpoints section
            Divider()
            
            // Last contact status
            if let lastContact = student.lastParentContact {
                let daysSince = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(daysSince > 14 ? .orange : .blue)
                    Text(isChinese ? "最近联系: \(daysSince == 0 ? "今天" : "\(daysSince) 天前")" : "Last contact: \(daysSince == 0 ? "Today" : "\(daysSince) days ago")")
                        .font(.system(size: 13))
                        .foregroundColor(daysSince > 14 ? .orange : AppTheme.textSecondary)
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(isChinese ? "无家长联系记录" : "No parent contact logged")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
            
            // Recent touchpoints (show up to 2)
            if !touchpoints.isEmpty {
                ForEach(touchpoints.prefix(2)) { touchpoint in
                    HStack(spacing: 10) {
                        Image(systemName: touchpoint.type.icon)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accentColor)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(touchpoint.type.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(touchpoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        if let notes = touchpoint.notes, !notes.isEmpty {
                            Text(String(notes.prefix(20)) + (notes.count > 20 ? "..." : ""))
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
                }
                
                if touchpoints.count > 2 {
                    Text(isChinese ? "+\(touchpoints.count - 2) 更多记录" : "+\(touchpoints.count - 2) more")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Enrolling Coach (who brought in the student)
    
    private var enrollingCoach: Coach? {
        guard let coachId = student.createdByCoachId else { return nil }
        // Check if it's the main logged-in coach
        if coachId == dataManager.coach.id {
            return dataManager.coach
        }
        return nil
    }
    
    private var enrollingStaffCoach: StaffCoach? {
        guard let coachId = student.createdByCoachId else { return nil }
        return dataManager.staffCoaches.first { $0.id == coachId }
    }
    
    // MARK: - Program Section Card (Always Visible)
    
    private var programSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.indigo)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "训练计划与教练" : "Program & Coach")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                // Programs - show all enrolled programs
                if !enrolledPrograms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "训练计划" : "Programs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        ForEach(enrolledPrograms) { prog in
                            HStack(spacing: 8) {
                                Image(systemName: prog.mascot.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(prog.mascotColor)
                                Text(prog.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                        }
                    }
                } else if let program = program {
                    HStack(spacing: 8) {
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 16))
                            .foregroundColor(program.mascotColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "训练计划" : "Program")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Coach and Category row
                HStack(spacing: 16) {
                    // Coach
                    if let coach = assignedCoach {
                        HStack(spacing: 8) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 16))
                                .foregroundColor(coach.role.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(coach.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "教练" : "Coach")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Age Category
                    if let category = ageCategory {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.shortName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "类别" : "Category")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
            
            if enrolledPrograms.isEmpty && program == nil && assignedCoach == nil && ageCategory == nil {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundColor(.secondary)
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "未分配训练计划" : "No program assigned")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            
            // Enrolled By section - shows who brought in this student
            if enrollingCoach != nil || enrollingStaffCoach != nil {
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "招生教练" : "Enrolled By")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let coach = enrollingCoach {
                            Text(coach.name.isEmpty ? "You" : coach.name)
                                .font(.system(size: 13, weight: .medium))
                        } else if let staffCoach = enrollingStaffCoach {
                            Text(staffCoach.name)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    
                    Spacer()
                    
                    // Show enrollment date if available
                    Text(student.createdAt.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Full Card Header
    
    private var fullCardHeader: some View {
        VStack(spacing: 16) {
            // Avatar with status ring
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [riskColor, riskColor.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 96, height: 96)
                
                StudentAvatarView(student: student, size: 88)
            }
            
            // Name and basic info
            VStack(spacing: 6) {
                // Language-aware name display
                if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                    VStack(spacing: 2) {
                        Text(student.chineseName!)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(student.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(student.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    if let age = student.age {
                        Label("\(age) years", systemImage: "birthday.cake")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let player = player, let position = player.position {
                        Text(position)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.primaryColor.opacity(0.1))
                            .foregroundColor(AppTheme.primaryColor)
                            .cornerRadius(10)
                    }
                    
                    if let team = primaryTeam {
                        teamBadge(team)
                    }
                }
            }
            
            // Physical Stats - Always Visible in Hero Card
            heroPhysicalStats
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Hero Physical Stats (Always Visible)
    
    private var heroPhysicalStats: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 12) {
            Divider()
            
            // Primary physical stats - use HStack for consistent alignment
            HStack(spacing: 8) {
                // Height
                if let player = player, let height = player.heightFormatted {
                    heroStatCell(icon: "ruler", value: height, label: isChinese ? "身高" : "Height", color: .blue)
                } else if let latestHeight = measurementSummary.latestHeight {
                    heroStatCell(icon: "ruler", value: latestHeight, label: isChinese ? "身高" : "Height", color: .blue)
                }
                
                // Weight
                if let player = player, let weight = player.weightFormatted {
                    heroStatCell(icon: "scalemass", value: weight, label: isChinese ? "体重" : "Weight", color: .green)
                } else if let latestWeight = measurementSummary.latestWeight {
                    heroStatCell(icon: "scalemass", value: latestWeight, label: isChinese ? "体重" : "Weight", color: .green)
                }
                
                // Handedness
                if let player = player {
                    heroStatCell(icon: "hand.raised", value: String(player.handedness.displayName.prefix(1)), label: isChinese ? "惯用手" : "Hand", color: .orange)
                }
            }
            
            // Performance measurements row (if available)
            let performanceMeasurements = getPerformanceMeasurements()
            if !performanceMeasurements.isEmpty {
                HStack(spacing: 8) {
                    ForEach(performanceMeasurements.prefix(3), id: \.type) { measurement in
                        heroStatCell(
                            icon: measurement.type.icon,
                            value: measurement.formattedValue,
                            label: isChinese ? measurement.type.shortLabelChinese : measurement.type.shortLabel,
                            color: Color(hex: measurement.type.category.color),
                            improvement: measurementSummary.improvementPercent(for: measurement.type)
                        )
                    }
                }
            }
            
            Divider()
            
            // Intelligence scores row - Service, Performance, Financials
            HStack(spacing: 8) {
                heroScoreCell(type: .service, value: serviceScore, needsAttention: serviceNeedsAttention)
                heroScoreCell(type: .performance, value: performanceScore, needsAttention: performanceNeedsAttention)
                heroScoreCell(type: .financials, value: financialsScore, needsAttention: financialsNeedsAttention)
            }
            
            // Inline detail panel (expands when a score is selected)
            if let selected = selectedScoreType {
                inlineScoreDetail(for: selected)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
            
            // Risk Alert (if needed)
            if churnRiskLevel == .high || churnRiskLevel == .critical {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(churnRiskLevel == .critical ? .red : .orange)
                    
                    Text(churnRiskLevel == .critical ? 
                         (LocalizationManager.shared.currentLanguage == .chinese ? "紧急流失风险" : "Critical churn risk") : 
                         (LocalizationManager.shared.currentLanguage == .chinese ? "高流失风险" : "High churn risk"))
                        .font(.system(size: 10, weight: .medium))
                    
                    Spacer()
                    
                    Text("\(Int(churnRiskScore))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(churnRiskLevel == .critical ? .red : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((churnRiskLevel == .critical ? Color.red : Color.orange).opacity(0.1))
                .cornerRadius(8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedScoreType)
    }
    
    private func heroScoreCell(type: ScoreType, value: Double, needsAttention: Bool) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let isSelected = selectedScoreType == type
        let displayColor = needsAttention ? Color.red : type.color
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedScoreType = selectedScoreType == type ? nil : type
            }
        }) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : type.icon)
                        .font(.system(size: 10))
                        .foregroundColor(displayColor)
                    Text("\(Int(value))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? displayColor : AppTheme.textPrimary)
                        .lineLimit(1)
                }
                .frame(height: 20)
                
                Text(isChinese ? type.chineseLabel : type.shortLabel)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? displayColor : AppTheme.textTertiary)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .padding(.horizontal, 4)
            .background(needsAttention ? Color.red.opacity(0.15) : (isSelected ? type.color.opacity(0.15) : type.color.opacity(0.1)))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(needsAttention ? Color.red.opacity(0.6) : (isSelected ? type.color.opacity(0.5) : Color.clear), lineWidth: needsAttention ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func heroStatCell(icon: String, value: String, label: String, color: Color, improvement: Double? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(height: 20)
            
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
                
                if let improvement = improvement {
                    Text(improvement >= 0 ? "+\(Int(improvement))%" : "\(Int(improvement))%")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(improvement >= 0 ? .green : .red)
                }
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .padding(.horizontal, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func getPerformanceMeasurements() -> [PlayerMeasurement] {
        // Get latest performance-related measurements (sprint, vertical, shooting)
        var measurements: [PlayerMeasurement] = []
        
        if let sprint = measurementSummary.latest(for: .sprintTime) {
            measurements.append(sprint)
        }
        if let vertical = measurementSummary.latest(for: .verticalJump) {
            measurements.append(vertical)
        }
        if let shooting = measurementSummary.latest(for: .shootingPercent) {
            measurements.append(shooting)
        }
        
        return measurements
    }
    
    private func inlineScoreDetail(for type: ScoreType) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let attention = needsAttention(for: type)
        let displayColor = attention ? Color.red : type.color
        
        return VStack(alignment: .leading, spacing: 10) {
            // Header with close button
            HStack {
                Image(systemName: attention ? "exclamationmark.triangle.fill" : type.icon)
                    .font(.system(size: 12))
                    .foregroundColor(displayColor)
                Text(isChinese ? type.localizedNameChinese : type.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                // Rating badge
                if attention {
                    Text(isChinese ? "需要关注" : "Needs Attention")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .cornerRadius(6)
                } else {
                    Text(scoreRating(for: scoreValue(for: type)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(scoreRatingColor(for: scoreValue(for: type)))
                        .cornerRadius(6)
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedScoreType = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            // Breakdown items in horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(breakdownItems(for: type), id: \.label) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(item.impactColor)
                                Text(item.label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            
                            Text(item.value)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Text(item.impact)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(item.impactColor)
                        }
                        .padding(10)
                        .frame(minWidth: 90)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Meaning text with action recommendation
            Text(meaningText(for: type))
                .font(.system(size: 11))
                .foregroundColor(attention ? .red : AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(attention ? 8 : 0)
                .background(attention ? Color.red.opacity(0.1) : Color.clear)
                .cornerRadius(8)
        }
        .padding(12)
        .background(attention ? Color.red.opacity(0.08) : type.color.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(attention ? Color.red.opacity(0.4) : type.color.opacity(0.2), lineWidth: attention ? 2 : 1)
        )
    }
    
    private func scoreValue(for type: ScoreType) -> Double {
        switch type {
        case .service: return serviceScore
        case .performance: return performanceScore
        case .financials: return financialsScore
        }
    }
    
    private func needsAttention(for type: ScoreType) -> Bool {
        switch type {
        case .service: return serviceNeedsAttention
        case .performance: return performanceNeedsAttention
        case .financials: return financialsNeedsAttention
        }
    }
    
    private func scoreRating(for value: Double) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        if value >= 85 { return isChinese ? "优秀" : "Excellent" }
        if value >= 70 { return isChinese ? "良好" : "Good" }
        if value >= 50 { return isChinese ? "需关注" : "Attention" }
        return isChinese ? "紧急" : "Critical"
    }
    
    private func scoreRatingColor(for value: Double) -> Color {
        if value >= 85 { return .green }
        if value >= 70 { return .blue }
        if value >= 50 { return .orange }
        return .red
    }
    
    private struct InlineBreakdownItem {
        let icon: String
        let label: String
        let value: String
        let impact: String
        let impactColor: Color
    }
    
    private func breakdownItems(for type: ScoreType) -> [InlineBreakdownItem] {
        switch type {
        case .service:
            return serviceBreakdownItems
        case .performance:
            return performanceBreakdownItems
        case .financials:
            return financialsBreakdownItems
        }
    }
    
    // MARK: - Service Breakdown (Parent Communication)
    private var serviceBreakdownItems: [InlineBreakdownItem] {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        var items: [InlineBreakdownItem] = []
        
        // Last parent contact
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            items.append(InlineBreakdownItem(
                icon: "phone.fill",
                label: isChinese ? "最近联系" : "Last Contact",
                value: days == 0 ? (isChinese ? "今天" : "Today") : (days == 1 ? (isChinese ? "昨天" : "Yesterday") : "\(days) \(isChinese ? "天前" : "days ago")"),
                impact: days <= 7 ? (isChinese ? "良好" : "Good") : (days <= 14 ? (isChinese ? "应联系" : "Due") : (isChinese ? "过期" : "Overdue")),
                impactColor: days <= 7 ? .green : (days <= 14 ? .orange : .red)
            ))
        } else {
            items.append(InlineBreakdownItem(
                icon: "phone.badge.waveform",
                label: isChinese ? "最近联系" : "Last Contact",
                value: isChinese ? "从未" : "Never",
                impact: isChinese ? "紧急" : "Critical",
                impactColor: .red
            ))
        }
        
        return items
    }
    
    // MARK: - Financials Breakdown (Contract/Attendance)
    private var financialsBreakdownItems: [InlineBreakdownItem] {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        var items: [InlineBreakdownItem] = []
        if let contract = contract {
            // Sessions remaining
            let remaining = contract.remainingSessions ?? 0
            let sessionRatio = contract.isPayAsYouGo ? 1.0 : Double(remaining) / Double(max(contract.totalSessions, 1))
            items.append(InlineBreakdownItem(
                icon: "ticket.fill",
                label: isChinese ? "剩余课时" : "Sessions Left",
                value: contract.isPayAsYouGo ? "∞" : "\(remaining)/\(contract.totalSessions)",
                impact: sessionRatio > 0.3 ? (isChinese ? "正常" : "OK") : (sessionRatio > 0.1 ? (isChinese ? "较少" : "Low") : (isChinese ? "紧急" : "Critical")),
                impactColor: sessionRatio > 0.3 ? .green : (sessionRatio > 0.1 ? .orange : .red)
            ))
            
            // Payment status
            items.append(InlineBreakdownItem(
                icon: "creditcard.fill",
                label: isChinese ? "付款状态" : "Payment",
                value: contract.isFullyPaid ? (isChinese ? "已付清" : "Paid") : "¥\(Int(contract.outstandingBalance)) \(isChinese ? "待付" : "due")",
                impact: contract.isFullyPaid ? (isChinese ? "良好" : "Good") : (isChinese ? "待处理" : "Pending"),
                impactColor: contract.isFullyPaid ? .green : .orange
            ))
            
            // Attendance rate
            let attendanceRate = contract.totalSessions > 0 ? Double(contract.attendedSessions) / Double(contract.totalSessions) * 100 : 0
            items.append(InlineBreakdownItem(
                icon: "calendar.badge.checkmark",
                label: isChinese ? "出勤率" : "Attendance",
                value: "\(Int(attendanceRate))%",
                impact: attendanceRate >= 80 ? (isChinese ? "良好" : "Good") : (attendanceRate >= 50 ? (isChinese ? "一般" : "Fair") : (isChinese ? "较低" : "Low")),
                impactColor: attendanceRate >= 80 ? .green : (attendanceRate >= 50 ? .orange : .red)
            ))
        } else {
            items.append(InlineBreakdownItem(
                icon: "xmark.circle.fill",
                label: isChinese ? "合同" : "Contract",
                value: isChinese ? "无活跃合同" : "No Active Contract",
                impact: isChinese ? "紧急" : "Critical",
                impactColor: .red
            ))
        }
        return items
    }
    
    // MARK: - Performance Breakdown (Skill Progression)
    private var performanceBreakdownItems: [InlineBreakdownItem] {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        var items: [InlineBreakdownItem] = []
        
        // Skill rating from player profile
        if let player = player {
            let rating = player.skills.overallRating
            items.append(InlineBreakdownItem(
                icon: "star.fill",
                label: isChinese ? "技能评级" : "Skill Rating",
                value: String(format: "%.1f/10", rating),
                impact: rating >= 7 ? (isChinese ? "优秀" : "Strong") : (rating >= 5 ? (isChinese ? "一般" : "Average") : (isChinese ? "发展中" : "Developing")),
                impactColor: rating >= 7 ? .green : (rating >= 5 ? .orange : .red)
            ))
        } else {
            items.append(InlineBreakdownItem(
                icon: "star.fill",
                label: isChinese ? "技能评级" : "Skill Rating",
                value: isChinese ? "未评级" : "Not rated",
                impact: isChinese ? "需要评估" : "Evaluate",
                impactColor: .orange
            ))
        }
        
        // Improvement trend
        if let stats = seasonStats, stats.gamesPlayed > 0 {
            items.append(InlineBreakdownItem(
                icon: "chart.line.uptrend.xyaxis",
                label: isChinese ? "比赛数据" : "Game Stats",
                value: String(format: "%.1f PPG", stats.ppg),
                impact: stats.ppg > 8 ? (isChinese ? "进步中" : "Improving") : (isChinese ? "稳定" : "Stable"),
                impactColor: stats.ppg > 8 ? .green : .orange
            ))
            items.append(InlineBreakdownItem(
                icon: "sportscourt.fill",
                label: isChinese ? "比赛场次" : "Games Played",
                value: "\(stats.gamesPlayed)",
                impact: stats.gamesPlayed >= 5 ? (isChinese ? "活跃" : "Active") : (isChinese ? "较少" : "Low"),
                impactColor: stats.gamesPlayed >= 5 ? .green : .orange
            ))
        } else {
            items.append(InlineBreakdownItem(
                icon: "chart.line.uptrend.xyaxis",
                label: isChinese ? "进度" : "Progress",
                value: isChinese ? "无比赛数据" : "No game data",
                impact: isChinese ? "需要评估" : "Evaluate",
                impactColor: .orange
            ))
        }
        
        return items
    }
    
    private func meaningText(for type: ScoreType) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let value = scoreValue(for: type)
        let attention = needsAttention(for: type)
        
        switch type {
        case .service:
            if attention {
                return isChinese ? "⚠️ 需要行动：家长沟通已过期。联系家长更新孩子的进展，分享最近的照片/视频，并收集反馈。这可以显著降低流失风险。" : "⚠️ ACTION NEEDED: Parent communication is overdue. Contact the parents to update them on their child's progress, share recent photos/videos, and gather feedback. This reduces churn risk significantly."
            }
            if value >= 70 { return isChinese ? "优秀的家长参与度。定期沟通和媒体分享建立信任和留存。" : "Excellent parent engagement. Regular communication and media sharing builds trust and retention." }
            if value >= 50 { return isChinese ? "考虑尽快联系家长。分享孩子的进展更新。" : "Consider reaching out to parents soon. Share updates about their child's progress." }
            return isChinese ? "家长沟通不足。立即安排电话或发送进展更新。" : "Parent communication is lacking. Schedule a call or send progress update immediately."
            
        case .performance:
            if attention {
                return isChinese ? "⚠️ 需要行动：学员表现出停滞迹象。安排技能评估，调整训练计划，设定新的可实现目标。考虑一对一辅导课程。" : "⚠️ ACTION NEEDED: Student shows signs of stagnation. Schedule a skill evaluation, adjust training plan, and set new achievable goals. Consider 1-on-1 coaching session."
            }
            if value >= 70 { return isChinese ? "强劲的技能发展。学员在训练中进步良好。" : "Strong skill development. Student is progressing well through training." }
            if value >= 50 { return isChinese ? "平均进度。考虑更频繁的评估以跟踪改进。" : "Average progress. Consider more frequent evaluations to track improvement." }
            return isChinese ? "学员需要重点关注。审查训练方法并考虑个性化训练。" : "Student needs focused attention. Review training approach and consider personalized drills."
            
        case .financials:
            if attention {
                return isChinese ? "⚠️ 需要行动：合同续约即将到期。课时不足或出勤率下降。启动续约对话并解决任何问题。" : "⚠️ ACTION NEEDED: Contract renewal needed soon. Sessions are running low or attendance is declining. Initiate renewal conversation and address any concerns."
            }
            if value >= 70 { return isChinese ? "健康的财务状况，课时余额和出勤率良好。" : "Healthy financial status with good session balance and attendance." }
            if value >= 50 { return isChinese ? "监控课时数量。在2周内开始续约讨论。" : "Monitor session count. Start renewal discussion within 2 weeks." }
            return isChinese ? "紧急：需要立即处理合同续约或出勤问题。" : "Critical: Immediate action needed on contract renewal or attendance issues."
        }
    }
    
    private func compactScoreCircle(value: Double, label: String, color: Color, isLarge: Bool = false) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: isLarge ? 3 : 2.5)
                
                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: isLarge ? 3 : 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(value))")
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            .frame(width: isLarge ? 38 : 32, height: isLarge ? 38 : 32)
            
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Service Score (Parent Communication Quality)
    // Tracks: contact frequency, session attendance, engagement
    private var serviceScore: Double {
        var score: Double = 50
        
        // Last parent contact (weight: 50%)
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days <= 7 { score += 50 }
            else if days <= 14 { score += 35 }
            else if days <= 21 { score += 15 }
            else { score -= 10 }
        } else {
            score -= 20 // Never contacted
        }
        
        // Recent session attendance as engagement proxy (weight: 30%)
        let sessionCount = recentSessions.count
        if sessionCount >= 8 { score += 30 }
        else if sessionCount >= 4 { score += 20 }
        else if sessionCount >= 1 { score += 10 }
        
        return min(100, max(0, score))
    }
    
    private var serviceNeedsAttention: Bool {
        // Needs attention if: no contact in 14+ days or score < 50
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days > 14 { return true }
        } else {
            return true // Never contacted
        }
        return serviceScore < 50
    }
    
    // MARK: - Performance Score (Skill Progression)
    // Tracks: skill ratings, game stats, improvement over time
    private var performanceScore: Double {
        var score: Double = 50
        
        // Player skill rating (weight: 50%)
        if let player = player {
            let rating = player.skills.overallRating
            score += rating * 5 // 0-10 rating -> 0-50 points
        }
        
        // Game performance (weight: 30%)
        if let stats = seasonStats, stats.gamesPlayed > 0 {
            if stats.ppg > 10 { score += 30 }
            else if stats.ppg > 5 { score += 20 }
            else { score += 10 }
        }
        
        return min(100, max(0, score))
    }
    
    private var performanceNeedsAttention: Bool {
        // Needs attention if: no player profile, low skill rating, or score < 50
        if player == nil { return true }
        if let player = player, player.skills.overallRating < 4 { return true }
        return performanceScore < 50
    }
    
    // MARK: - Financials Score (Contract & Attendance)
    // Tracks: sessions remaining, payment status, attendance rate
    private var financialsScore: Double {
        guard let contract = contract else { return 0 }
        var score: Double = 30
        
        // Sessions remaining (weight: 40%) - Pay-as-you-go always gets full score
        let remaining = contract.remainingSessions ?? 0
        let sessionRatio = contract.isPayAsYouGo ? 1.0 : Double(remaining) / Double(max(contract.totalSessions, 1))
        if sessionRatio > 0.5 { score += 40 }
        else if sessionRatio > 0.3 { score += 25 }
        else if sessionRatio > 0.1 { score += 10 }
        
        // Payment status (weight: 20%)
        if contract.isFullyPaid { score += 20 }
        else if contract.outstandingBalance < contract.totalAmount * 0.3 { score += 10 }
        
        // Attendance rate (weight: 20%)
        let attendanceRate = contract.totalSessions > 0 ? Double(contract.attendedSessions) / Double(contract.totalSessions) : 0
        if attendanceRate >= 0.8 { score += 20 }
        else if attendanceRate >= 0.5 { score += 10 }
        
        return min(100, max(0, score))
    }
    
    private var financialsNeedsAttention: Bool {
        // Needs attention if: no contract, <5 sessions left, or score < 50
        guard let contract = contract else { return true }
        if !contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 5 { return true }
        let attendanceRate = contract.totalSessions > 0 ? Double(contract.attendedSessions) / Double(contract.totalSessions) : 0
        if attendanceRate < 0.5 { return true }
        return financialsScore < 50
    }
    
    // Overall score for churn risk calculation
    private var overallScore: Double {
        (serviceScore + performanceScore + financialsScore) / 3.0
    }
    
    private var overallScoreColor: Color {
        if overallScore >= 75 { return .green }
        if overallScore >= 50 { return .orange }
        return .red
    }
    
    private func scoreCircle(value: Double, label: String, color: Color, isLarge: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: isLarge ? 4 : 3)
                
                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: isLarge ? 4 : 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(value))")
                    .font(.system(size: isLarge ? 14 : 11, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            .frame(width: isLarge ? 50 : 40, height: isLarge ? 50 : 40)
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Contract Detail Section
    
    private var contractDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let contract = contract {
                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(contract.contractLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        contractStatusBadge(contract)
                    }
                    
                    // Session progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill((!contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 3) ? Color.orange : Color.green)
                                .frame(width: geo.size.width * contract.progressPercentage)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(contract.attendedSessions) attended")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(contract.isPayAsYouGo ? "Pay As You Go" : "\(contract.remainingSessions ?? 0) remaining")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor((!contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 3) ? .orange : .primary)
                    }
                }
                
                Divider()
                
                // Contract details grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    contractInfoCell(label: "Total Sessions", value: "\(contract.totalSessions)")
                    contractInfoCell(label: "Price/Session", value: "¥\(Int(contract.pricePerSession))")
                    contractInfoCell(label: "Total Amount", value: "¥\(Int(contract.totalAmount))")
                    contractInfoCell(label: "Amount Paid", value: "¥\(Int(contract.amountPaid))", color: contract.isFullyPaid ? .green : .orange)
                    
                    if let startDate = contract.startDate {
                        contractInfoCell(label: "Start Date", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    
                    if let expiryDate = contract.expiryDate {
                        contractInfoCell(label: "Expiry Date", value: expiryDate.formatted(date: .abbreviated, time: .omitted), color: contract.isExpired ? .red : nil)
                    }
                }
                
                // Perks
                if contract.jerseyGiven || contract.ballGiven {
                    Divider()
                    
                    HStack(spacing: 16) {
                        if contract.jerseyGiven {
                            HStack(spacing: 4) {
                                Image(systemName: "tshirt.fill")
                                    .foregroundColor(.blue)
                                Text("Jersey #\(contract.jerseyNumber ?? 0)")
                                    .font(.caption)
                            }
                        }
                        
                        if contract.ballGiven {
                            HStack(spacing: 4) {
                                Image(systemName: "basketball.fill")
                                    .foregroundColor(.orange)
                                Text("Ball Given")
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                // Outstanding balance warning
                if contract.outstandingBalance > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("Outstanding balance: ¥\(Int(contract.outstandingBalance))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                // No active contract
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No active contract")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !allContracts.isEmpty {
                        Text("\(allContracts.count) previous contract(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    private func contractInfoCell(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color ?? .primary)
        }
    }
    
    // MARK: - League Performance Section
    
    private var trainingStats: TrainingSessionStats {
        TrainingSessionStats.calculate(for: student.id, from: dataManager.sessionEvents)
    }
    
    /// Get all students enrolled in the same program as this student
    private var programPeerStats: [TrainingSessionStats] {
        // Method 1: Use program's enrolledStudentIds (most reliable)
        if let program = enrolledProgram {
            let peerStudentIds = program.enrolledStudentIds
            return peerStudentIds.map { studentId in
                TrainingSessionStats.calculate(for: studentId, from: dataManager.sessionEvents)
            }
        }
        
        // Method 2: Fallback to contract.programAssignments
        if let contract = contract, !contract.programAssignments.isEmpty {
            let programId = contract.programAssignments[0]
            if let program = dataManager.programs.first(where: { $0.id == programId }) {
                let peerStudentIds = program.enrolledStudentIds
                return peerStudentIds.map { studentId in
                    TrainingSessionStats.calculate(for: studentId, from: dataManager.sessionEvents)
                }
            }
        }
        
        // Method 3: Fallback to student.programId
        if let programId = student.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            let peerStudentIds = program.enrolledStudentIds
            return peerStudentIds.map { studentId in
                TrainingSessionStats.calculate(for: studentId, from: dataManager.sessionEvents)
            }
        }
        
        return []
    }
    
    private var programContext: ProgramStatsContext {
        ProgramStatsContext.calculate(from: programPeerStats)
    }
    
    private var performanceMetrics: PerformanceRadarMetrics {
        let skills = player?.skills ?? SkillsEvaluation()
        return PerformanceRadarMetrics.compute(from: trainingStats, skills: skills, programContext: programContext)
    }
    
    private var leaguePerformanceSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let stats = trainingStats
        
        return VStack(alignment: .leading, spacing: 16) {
            // Performance Radar Chart
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "表现分析" : "Performance Analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PerformanceRadarChartView(
                    metrics: performanceMetrics,
                    accentColor: Color.avatarColor(student.avatarColor),
                    loc: ReportLocalization()
                )
                .frame(height: 200)
            }
            
            // Training Stats (from in-session games)
            if stats.hasStats {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isChinese ? "训练数据" : "Training Stats")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(isChinese ? "\(stats.gamesPlayed) 场" : "\(stats.gamesPlayed) games")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statCell(value: String(format: "%.1f", stats.ppg), label: "PPG", color: .orange)
                        statCell(value: String(format: "%.1f", stats.rpg), label: "RPG", color: .blue)
                        statCell(value: String(format: "%.1f", stats.apg), label: "APG", color: .green)
                        statCell(value: String(format: "%.1f", stats.spg), label: "SPG", color: .purple)
                        statCell(value: String(format: "%.1f", stats.bpg), label: "BPG", color: .red)
                        statCell(value: "\(stats.gamesPlayed)", label: "GP", color: .gray)
                    }
                }
            }
            
            // Team association
            if !teams.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "球队" : "Teams")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(teams) { team in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(team.primaryColor)
                                .frame(width: 12, height: 12)
                            
                            Text(team.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(team.shortName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // League Season stats (if available)
            if let leagueStats = seasonStats, leagueStats.gamesPlayed > 0 {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(isChinese ? "联赛数据" : "League Stats")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(isChinese ? "\(leagueStats.gamesPlayed) 场" : "\(leagueStats.gamesPlayed) games")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statCell(value: String(format: "%.1f", leagueStats.ppg), label: "PPG", color: .orange)
                        statCell(value: String(format: "%.1f", leagueStats.rpg), label: "RPG", color: .blue)
                        statCell(value: String(format: "%.1f", leagueStats.apg), label: "APG", color: .green)
                        statCell(value: String(format: "%.1f", leagueStats.spg), label: "SPG", color: .purple)
                        statCell(value: String(format: "%.1f", leagueStats.bpg), label: "BPG", color: .red)
                        statCell(value: String(format: "%.1f", leagueStats.mpg), label: "MPG", color: .gray)
                    }
                }
            }
        }
    }
    
    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Physical Measurements Section
    
    private var physicalMeasurementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Physical stats from Player
            if let player = player {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let height = player.heightFormatted {
                        measurementCell(icon: "ruler", label: "Height", value: height, color: .blue)
                    }
                    if let weight = player.weightFormatted {
                        measurementCell(icon: "scalemass", label: "Weight", value: weight, color: .green)
                    }
                    if let wingspan = player.wingspanCm {
                        measurementCell(icon: "arrow.left.and.right", label: "Wingspan", value: "\(Int(wingspan))cm", color: .purple)
                    }
                    measurementCell(icon: "hand.raised", label: "Handedness", value: player.handedness.displayName, color: .orange)
                }
                
                Divider()
            }
            
            // Detailed measurements
            if !measurementSummary.measurements.isEmpty {
                ForEach(MeasurementCategory.allCases, id: \.self) { category in
                    let categoryMeasurements = measurementSummary.latestByCategory(category)
                    if !categoryMeasurements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundColor(Color(hex: category.color))
                                Text(category.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            ForEach(categoryMeasurements) { measurement in
                                HStack {
                                    Text(measurement.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(measurement.formattedValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    // Show improvement if available
                                    if let improvement = measurementSummary.improvementPercent(for: measurement.type) {
                                        Text(improvement >= 0 ? "+\(Int(improvement))%" : "\(Int(improvement))%")
                                            .font(.caption2)
                                            .foregroundColor(improvement >= 0 ? .green : .red)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(hex: category.color).opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            } else if player == nil {
                VStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No measurements recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    private func measurementCell(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Skills Evaluation Section
    
    private var skillsEvaluationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player = player {
                let skills = player.skills
                
                // Overall rating
                HStack {
                    Text("Overall Rating")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f", skills.overallRating))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(skillRatingColor(skills.overallRating))
                    
                    Text("/ 10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Individual skills (6-skill model matching radar)
                let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    skillBar(label: isChinese ? "得分" : "Scoring", value: skills.scoring, icon: "scope")
                    skillBar(label: isChinese ? "组织" : "Playmaking", value: skills.playmaking, icon: "arrow.triangle.branch")
                    skillBar(label: isChinese ? "篮板" : "Rebounding", value: skills.rebounding, icon: "arrow.up.arrow.down")
                    skillBar(label: isChinese ? "防守" : "Defense", value: skills.defense, icon: "shield.fill")
                    skillBar(label: isChinese ? "运动能力" : "Athleticism", value: skills.athleticism, icon: "figure.run")
                    skillBar(label: isChinese ? "软实力" : "Intangibles", value: skills.intangibles, icon: "star.fill")
                }
                
                // Last evaluated
                if let lastEval = skills.lastEvaluatedDate {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Last evaluated: \(lastEval.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                
                // Notes
                if let notes = skills.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evaluation Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No skills evaluation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    private func skillBar(label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(skillRatingColor(Double(value)))
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(skillRatingColor(Double(value)))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(skillRatingColor(Double(value)))
                        .frame(width: geo.size.width * (Double(value) / 10.0))
                }
            }
            .frame(height: 4)
        }
        .padding(8)
        .background(AppTheme.cardBackground.opacity(0.5))
        .cornerRadius(6)
    }
    
    private func skillRatingColor(_ value: Double) -> Color {
        if value >= 8 { return .green }
        if value >= 6 { return .blue }
        if value >= 4 { return .orange }
        return .red
    }
    
    // MARK: - Parent Info Section
    
    private var parentInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player = player {
                // Primary parent
                parentCard(info: player.parentInfo, isPrimary: true)
                
                // Secondary parent
                if let secondary = player.secondaryParentInfo, !secondary.name.isEmpty {
                    parentCard(info: secondary, isPrimary: false)
                }
                
                // Last contact info
                if let lastContact = student.lastParentContact {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("Last contact: \(lastContact.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                // Recent touchpoints
                if !student.parentalTouchpoints.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Touchpoints")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(student.parentalTouchpoints.prefix(3)) { touchpoint in
                            HStack {
                                Image(systemName: touchpoint.type.icon)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(touchpoint.type.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if let notes = touchpoint.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Text(touchpoint.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No parent information")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    private func parentCard(info: ParentInfo, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isPrimary ? "Primary Contact" : "Secondary Contact")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(info.relationship)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
            
            if !info.name.isEmpty {
                Text(info.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 16) {
                if !info.phone.isEmpty {
                    Link(destination: URL(string: "tel:\(info.phone)")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.caption)
                            Text(info.phone)
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                if let email = info.email, !email.isEmpty {
                    Link(destination: URL(string: "mailto:\(email)")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                                .font(.caption)
                            Text("Email")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                if let wechat = info.wechatId, !wechat.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.caption)
                        Text(wechat)
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground.opacity(0.5))
        .cornerRadius(10)
    }
    
    // MARK: - Program Organization Section
    
    private var programOrganizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Program
            if let program = program {
                HStack(spacing: 12) {
                    Image(systemName: program.mascot.icon)
                        .font(.title2)
                        .foregroundColor(program.mascotColor)
                        .frame(width: 40, height: 40)
                        .background(program.mascotColor.opacity(0.1))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Program")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(program.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
            }
            
            // Age Category
            if let category = ageCategory {
                HStack(spacing: 12) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(category.shortName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age Category")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(category.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
            }
            
            // Assigned Coach
            if let coach = assignedCoach {
                HStack(spacing: 12) {
                    Image(systemName: coach.role.icon)
                        .font(.title3)
                        .foregroundColor(coach.role.color)
                        .frame(width: 40, height: 40)
                        .background(coach.role.color.opacity(0.1))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assigned Coach")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(coach.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    Text(coach.role.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if program == nil && ageCategory == nil && assignedCoach == nil {
                VStack(spacing: 8) {
                    Image(systemName: "building.2")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No organization info")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickActionButton(icon: "phone.fill", label: "Call", color: .green) {
                    if let phone = player?.parentInfo.phone, !phone.isEmpty,
                       let url = URL(string: "tel:\(phone)") {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                
                quickActionButton(icon: "message.fill", label: "Message", color: .blue) {
                    // Message action
                }
                
                quickActionButton(icon: "doc.text.fill", label: "Report", color: .purple) {
                    // Generate report action
                }
                
                quickActionButton(icon: "camera.fill", label: "Media", color: .orange) {
                    // Media vault action
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Views
    
    private func quickStat(icon: String, value: String, color: Color = AppTheme.textTertiary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(color)
    }
    
    private func teamBadge(_ team: Team) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(team.primaryColor)
                .frame(width: 6, height: 6)
            Text(team.shortName)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(team.primaryColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(team.primaryColor.opacity(0.12))
        .cornerRadius(4)
    }
    
    private func contractStatusBadge(_ contract: Contract) -> some View {
        Text(contract.status.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color(contract.status.color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(contract.status.color).opacity(0.15))
            .cornerRadius(4)
    }
    
    private var riskIndicator: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(riskColor)
                .frame(width: 12, height: 12)
            Text(churnRiskLevel.rawValue)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(riskColor)
        }
    }
    
    private var riskColor: Color {
        switch churnRiskLevel {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    private func summaryStatCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Score Detail Popup

struct ScoreDetailPopup: View {
    @Environment(\.dismiss) var dismiss
    let scoreType: UnifiedStudentCard.ScoreType
    let student: Student
    let contract: Contract?
    let player: Player?
    let seasonStats: SeasonStats?
    let recentSessions: [SessionEvent]
    let serviceScore: Double
    let performanceScore: Double
    let financialsScore: Double
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Score Header
                    scoreHeader
                    
                    // Breakdown Section
                    breakdownSection
                    
                    // What This Means
                    meaningSection
                    
                    // How to Improve (if score is low)
                    if currentScore < 70 {
                        improvementSection
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(scoreType.rawValue)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var currentScore: Double {
        switch scoreType {
        case .service: return serviceScore
        case .performance: return performanceScore
        case .financials: return financialsScore
        }
    }
    
    private var scoreHeader: some View {
        VStack(spacing: 16) {
            // Large score circle
            ZStack {
                Circle()
                    .stroke(scoreType.color.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: currentScore / 100)
                    .stroke(scoreType.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(currentScore))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(scoreType.color)
                    Text("/ 100")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            // Score label
            HStack(spacing: 6) {
                Image(systemName: scoreType.icon)
                    .font(.system(size: 14))
                Text(scoreType.rawValue)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(scoreType.color)
            
            // Rating badge
            Text(scoreRating)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(scoreRatingColor)
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var scoreRating: String {
        if currentScore >= 85 { return "Excellent" }
        if currentScore >= 70 { return "Good" }
        if currentScore >= 50 { return "Needs Attention" }
        return "Critical"
    }
    
    private var scoreRatingColor: Color {
        if currentScore >= 85 { return .green }
        if currentScore >= 70 { return .blue }
        if currentScore >= 50 { return .orange }
        return .red
    }
    
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCORE BREAKDOWN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(spacing: 10) {
                ForEach(breakdownItems, id: \.label) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundColor(item.color)
                            .frame(width: 24)
                        
                        Text(item.label)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Spacer()
                        
                        Text(item.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        // Impact indicator
                        Text(item.impact)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(item.impactColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.impactColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .padding(12)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private struct BreakdownItem {
        let icon: String
        let label: String
        let value: String
        let impact: String
        let impactColor: Color
        
        var color: Color {
            switch impactColor {
            case .green: return .green
            case .orange: return .orange
            case .red: return .red
            default: return .gray
            }
        }
    }
    
    private var breakdownItems: [BreakdownItem] {
        switch scoreType {
        case .service:
            return serviceBreakdown
        case .performance:
            return performanceBreakdown
        case .financials:
            return financialsBreakdown
        }
    }
    
    private var serviceBreakdown: [BreakdownItem] {
        var items: [BreakdownItem] = []
        
        // Parent contact
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            items.append(BreakdownItem(
                icon: "phone.fill",
                label: "Last Parent Contact",
                value: days == 0 ? "Today" : "\(days) days ago",
                impact: days <= 7 ? "Good" : (days <= 14 ? "Due" : "Overdue"),
                impactColor: days <= 7 ? .green : (days <= 14 ? .orange : .red)
            ))
        } else {
            items.append(BreakdownItem(
                icon: "phone.badge.waveform.fill",
                label: "Parent Contact",
                value: "Never contacted",
                impact: "Critical",
                impactColor: .red
            ))
        }
        
        // Recent sessions
        items.append(BreakdownItem(
            icon: "calendar.badge.checkmark",
            label: "Recent Sessions",
            value: "\(recentSessions.count) attended",
            impact: recentSessions.count >= 4 ? "Good" : "Low",
            impactColor: recentSessions.count >= 4 ? .green : .orange
        ))
        
        return items
    }
    
    private var performanceBreakdown: [BreakdownItem] {
        var items: [BreakdownItem] = []
        
        if let player = player {
            items.append(BreakdownItem(
                icon: "star.fill",
                label: "Skills Rating",
                value: String(format: "%.1f / 10", player.skills.overallRating),
                impact: player.skills.overallRating > 7 ? "Strong" : (player.skills.overallRating > 5 ? "Average" : "Developing"),
                impactColor: player.skills.overallRating > 7 ? .green : (player.skills.overallRating > 5 ? .orange : .red)
            ))
        } else {
            items.append(BreakdownItem(
                icon: "star.fill",
                label: "Skills Rating",
                value: "Not evaluated",
                impact: "Evaluate",
                impactColor: .orange
            ))
        }
        
        if let stats = seasonStats, stats.gamesPlayed > 0 {
            items.append(BreakdownItem(
                icon: "basketball.fill",
                label: "Points Per Game",
                value: String(format: "%.1f PPG", stats.ppg),
                impact: stats.ppg > 8 ? "Improving" : "Stable",
                impactColor: stats.ppg > 8 ? .green : .orange
            ))
        }
        
        return items
    }
    
    private var financialsBreakdown: [BreakdownItem] {
        var items: [BreakdownItem] = []
        
        if let contract = contract {
            let remaining = contract.remainingSessions ?? 0
            let sessionRatio = contract.isPayAsYouGo ? 1.0 : Double(remaining) / Double(max(contract.totalSessions, 1))
            items.append(BreakdownItem(
                icon: "ticket.fill",
                label: "Sessions Remaining",
                value: contract.isPayAsYouGo ? "Pay As You Go" : "\(remaining) of \(contract.totalSessions)",
                impact: sessionRatio > 0.3 ? "OK" : (sessionRatio > 0.1 ? "Low" : "Critical"),
                impactColor: sessionRatio > 0.3 ? .green : (sessionRatio > 0.1 ? .orange : .red)
            ))
            
            items.append(BreakdownItem(
                icon: "creditcard.fill",
                label: "Payment Status",
                value: contract.isFullyPaid ? "Fully Paid" : "¥\(Int(contract.outstandingBalance)) Due",
                impact: contract.isFullyPaid ? "Good" : "Pending",
                impactColor: contract.isFullyPaid ? .green : .orange
            ))
        } else {
            items.append(BreakdownItem(
                icon: "xmark.circle.fill",
                label: "Contract",
                value: "No Active Contract",
                impact: "Critical",
                impactColor: .red
            ))
        }
        
        return items
    }
    
    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT THIS MEANS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(meaningText)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var meaningText: String {
        switch scoreType {
        case .service:
            if serviceScore >= 70 {
                return "Excellent parent engagement. Regular communication builds trust and reduces churn risk."
            } else if serviceScore >= 50 {
                return "Consider reaching out to parents soon. Share updates about their child's progress and gather feedback."
            } else {
                return "⚠️ ACTION NEEDED: Parent communication is overdue. Contact parents to update them on their child's progress. This reduces churn risk significantly."
            }
            
        case .performance:
            if performanceScore >= 70 {
                return "Strong skill development. Student is progressing well through training."
            } else if performanceScore >= 50 {
                return "Average progress. Consider more frequent evaluations to track improvement."
            } else {
                return "⚠️ ACTION NEEDED: Student shows signs of stagnation. Schedule a skill evaluation, adjust training plan, and set new achievable goals."
            }
            
        case .financials:
            if financialsScore >= 70 {
                return "Healthy financial status with good session balance and attendance."
            } else if financialsScore >= 50 {
                return "Monitor session count. Start renewal discussion within 2 weeks."
            } else {
                return "⚠️ ACTION NEEDED: Contract renewal needed soon. Sessions are running low. Initiate renewal conversation and address any concerns."
            }
        }
    }
    
    private var improvementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("HOW TO IMPROVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(improvementTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text(tip)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
    
    private var improvementTips: [String] {
        switch scoreType {
        case .service:
            var tips: [String] = []
            if student.lastParentContact == nil || Calendar.current.dateComponents([.day], from: student.lastParentContact!, to: Date()).day ?? 0 > 14 {
                tips.append("Schedule a parent touchpoint this week")
            }
            tips.append("Share photos or videos of the child's progress")
            tips.append("Ask for feedback on the training experience")
            return tips
            
        case .performance:
            return [
                "Schedule a skill evaluation session",
                "Set specific, measurable improvement goals",
                "Consider 1-on-1 coaching for focused development"
            ]
            
        case .financials:
            var tips: [String] = []
            if contract == nil {
                tips.append("Create a new contract to enroll this student")
            } else if let c = contract {
                if !c.isPayAsYouGo && (c.remainingSessions ?? 0) <= 5 {
                    tips.append("Discuss contract renewal before sessions run out")
                }
                if !c.isFullyPaid {
                    tips.append("Follow up on outstanding payment balance")
                }
            }
            return tips.isEmpty ? ["Maintain regular contract check-ins"] : tips
        }
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    var defaultExpanded: Bool = false
    @ViewBuilder let content: () -> Content
    
    @State private var isExpanded: Bool? = nil
    
    private var expanded: Bool {
        isExpanded ?? defaultExpanded
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { 
                withAnimation(.spring(response: 0.3)) { 
                    isExpanded = !(isExpanded ?? defaultExpanded)
                } 
            }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.1))
                        .cornerRadius(6)
                    
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Content
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding()
                .background(AppTheme.cardBackground.opacity(0.7))
                .cornerRadius(12)
                .padding(.top, -8)
            }
        }
    }
}

// MARK: - Color Extension for Contract Status

extension Color {
    init(_ colorName: String) {
        switch colorName {
        case "orange": self = .orange
        case "green": self = .green
        case "blue": self = .blue
        case "red": self = .red
        case "gray": self = .gray
        default: self = .primary
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            UnifiedStudentCard(student: Student.samples[0], mode: .compact)
            
            UnifiedStudentCard(student: Student.samples[0], mode: .summary)
            
            UnifiedStudentCard(student: Student.samples[0], mode: .full)
        }
        .padding()
    }
    .background(AppTheme.background)
    .environmentObject(DataManager.shared)
}
