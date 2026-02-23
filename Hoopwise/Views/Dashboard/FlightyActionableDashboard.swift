import SwiftUI
import Combine

// MARK: - Flighty Actionable Dashboard
/// A clean, Flighty-inspired home screen with full-width horizontal cards
struct FlightyActionableDashboard: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var currentTime = Date()
    @State private var selectedStudent: Student?
    @State private var selectedSession: SessionEvent?
    @State private var selectedProgram: Program?
    @State private var selectedContract: Contract?
    @State private var showingProfile = false
    @State private var briefingExpanded = false
    @State private var showingAllAttentionItems = false
    @State private var showingAllPlayers = false
    @State private var selectedLiveGame: Game?
    @State private var showingLiveScoring = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed Properties
    
    private var todaySessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { Calendar.current.isDateInToday($0.date) && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }
    }

    private func effectivePerformanceGrade(for student: Student) -> PerformanceGrade {
        if let override = student.performanceGrade {
            return override
        }

        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: dataManager.students,
            sessions: dataManager.sessionEvents,
            skills: skills
        )
    }
    
    private var todaysPlayers: [Student] {
        // Get players from today's sessions - either from session attendeeIds or from program enrollment
        var playerIds = Set<UUID>()
        
        for session in todaySessions {
            // First try session attendeeIds
            if !session.attendeeIds.isEmpty {
                playerIds.formUnion(session.attendeeIds)
            }
            // Fall back to program enrolled students
            else if let programId = session.programId,
                    let program = dataManager.programs.first(where: { $0.id == programId }) {
                playerIds.formUnion(program.enrolledStudentIds)
            }
        }
        
        return dataManager.students.filter { playerIds.contains($0.id) }
    }
    
    private var expiringContracts: [(contract: Contract, student: Student)] {
        let twoWeeksFromNow = Date().addingTimeInterval(14 * 24 * 3600)
        return dataManager.students.compactMap { student -> (contract: Contract, student: Student)? in
            guard let contract = dataManager.currentContract(for: student.id) else { return nil }
            guard contract.status == .active else { return nil }
            // Skip pay-as-you-go contracts for expiry/low session warnings
            guard !contract.isPayAsYouGo else { return nil }
            let isExpiringSoon = contract.expiryDate != nil && contract.expiryDate! <= twoWeeksFromNow
            let isLowSessions = (contract.remainingSessions ?? 0) <= 3
            guard isExpiringSoon || isLowSessions else { return nil }
            return (contract, student)
        }.sorted { ($0.contract.remainingSessions ?? 0) < ($1.contract.remainingSessions ?? 0) }
    }
    
    private var unplannedSessions: [SessionEvent] {
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.sessionEvents.filter { session in
            session.date >= now &&
            session.date <= twoWeeksFromNow &&
            session.status == .scheduled &&
            session.curriculum.totalDrillCount == 0
        }.sorted { $0.date < $1.date }
    }
    
    private var programsNeedingPlanning: [Program] {
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.programs.filter { program in
            program.status == .active || program.status == .draft
        }.filter { program in
            let phases = dataManager.microCycles.filter { $0.programId == program.id }
            // Only show if program has no phases AND has sessions in the next 2 weeks
            guard phases.isEmpty else { return false }
            let hasSoonSessions = dataManager.sessionEvents.contains { session in
                session.programId == program.id && session.date >= now && session.date <= twoWeeksFromNow
            }
            return hasSoonSessions || (program.startDate ?? Date.distantFuture) <= twoWeeksFromNow
        }
    }
    
    private var liveGames: [Game] {
        dataManager.games.filter { $0.status == .live }
    }
    
    /// Current session that is in progress with drills assigned
    private var liveSession: SessionEvent? {
        dataManager.sessionEvents.first { session in
            session.status == .inProgress && session.curriculum.totalDrillCount > 0
        }
    }
    
    private var totalActionItems: Int {
        expiringContracts.count + unplannedSessions.count + programsNeedingPlanning.count + dataManager.upcomingReminders.count + dataManager.overdueReminders.count
    }
    
    /// Hero player - the one requiring most attention (lowest contract sessions or focus area)
    private var heroPlayer: Student? {
        todaysPlayers.first { student in
            let contract = dataManager.currentContract(for: student.id)
            // Skip pay-as-you-go contracts for this check
            guard let contract = contract, !contract.isPayAsYouGo else { return false }
            return (contract.remainingSessions ?? 100) <= 5
        } ?? todaysPlayers.first
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    headerSection
                    
                    // Live Session Activity Card (when session is in progress with drills)
                    if let session = liveSession {
                        LiveSessionActivityCard(session: session)
                            .padding(.horizontal, 16)
                    }
                    
                    // Today's Briefing - Expandable
                    todayBriefingCard
                        .padding(.horizontal, 16)
                    
                    // Live Game Alert
                    if !liveGames.isEmpty {
                        liveGameAlert
                            .padding(.horizontal, 16)
                    }
                    
                    // Attention Required Card (Blue - Flighty style)
                    if totalActionItems > 0 {
                        attentionRequiredCard
                            .padding(.horizontal, 16)
                    }
                    
                    // Today's Players Card (Red/Coral - Flighty style)
                    if !todaysPlayers.isEmpty {
                        todaysPlayersCard
                            .padding(.horizontal, 16)
                    }
                    
                    // Player Growth Card (White - shows MIP and needs focus)
                    if !dataManager.students.isEmpty {
                        playerGrowthCard
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 120)
                }
                .padding(.top, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .background(AppTheme.background.ignoresSafeArea())
            .onReceive(timer) { _ in
                currentTime = Date()
            }
            .fullScreenCoverCompat(isPresented: $showingProfile) {
                FlightyCoachProfileView()
            }
            .navigationDestination(item: $selectedSession) { session in
                FlightySessionPageView(session: session, accessMode: .architect)
            }
            .navigationDestination(item: $selectedProgram) { program in
                FlightyProgramDetailView(program: program)
            }
            .sheet(item: $selectedStudent) { student in
                StudentQuickPeepView(student: student, sessionId: nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAllAttentionItems) {
                AllAttentionItemsSheet(
                    expiringContracts: expiringContracts,
                    unplannedSessions: unplannedSessions,
                    programsNeedingPlanning: programsNeedingPlanning,
                    onSelectStudent: { selectedStudent = $0 },
                    onSelectSession: { selectedSession = $0 },
                    onSelectProgram: { selectedProgram = $0 }
                )
            }
            .sheet(isPresented: $showingAllPlayers) {
                AllPlayersSheet(
                    players: todaysPlayers,
                    dataManager: dataManager,
                    onSelectStudent: { selectedStudent = $0 }
                )
            }
            .sheet(isPresented: $showingLiveScoring) {
                if let game = selectedLiveGame {
                    LiveScoringView(game: Binding(
                        get: { dataManager.games.first { $0.id == game.id } ?? game },
                        set: { dataManager.updateGame($0) }
                    ))
                }
            }
        }
    }
    
    // MARK: - Header Section (Dark Theme)
    @State private var showingLoginSheet = false
    
    private var isGuestMode: Bool {
        AuthManager.shared.isGuestMode
    }
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            // Profile button + Greeting + Coach name - LEFT
            Button(action: { 
                if isGuestMode {
                    showingLoginSheet = true
                } else {
                    showingProfile = true
                }
            }) {
                HStack(spacing: 12) {
                    // Profile picture
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(isGuestMode ? 0.3 : 0))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isGuestMode ? AnyShapeStyle(Color.clear) : AnyShapeStyle(AppTheme.accentGradient))
                            )
                        
                        if isGuestMode {
                            // Guest mode - show person icon with badge
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                        } else if let imageData = dataManager.coach.profileImageData,
                           !imageData.isEmpty {
                            DataImageView(data: imageData, size: 40)
                        } else if let imageUrlString = dataManager.coach.profileImageUrl,
                           !imageUrlString.isEmpty {
                            if imageUrlString.hasPrefix("http") {
                                AsyncImage(url: URL(string: imageUrlString)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    case .failure, .empty:
                                        defaultCoachAvatarContent
                                    @unknown default:
                                        defaultCoachAvatarContent
                                    }
                                }
                            } else {
                                // Local file path
                                LocalImageView(path: imageUrlString, size: 40)
                            }
                        } else {
                            defaultCoachAvatarContent
                        }
                    }
                    
                    // Greeting + Name
                    VStack(alignment: .leading, spacing: 2) {
                        if isGuestMode {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "体验模式" : "Demo Mode")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "点击登录" : "Tap to Sign In")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                        } else {
                            Text(greeting)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                            Text(dataManager.coach.name.components(separatedBy: " ").first ?? "Coach")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingLoginSheet) {
            GuestLoginPromptSheet()
        }
    }
    
    /// Helper view to load images from Data
    private struct DataImageView: View {
        let data: Data
        let size: CGFloat
        
        var body: some View {
            if let image = loadImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                EmptyView()
            }
        }
        
        private func loadImage() -> Image? {
            #if os(iOS)
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
            #else
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
            #endif
        }
    }
    
    /// Helper view to load local images from file path
    private struct LocalImageView: View {
        let path: String
        let size: CGFloat
        
        var body: some View {
            if let image = loadLocalImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                EmptyView()
            }
        }
        
        private func loadLocalImage() -> Image? {
            #if os(iOS)
            let fileURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let fileURL = fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
            #else
            let fileURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let fileURL = fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
            #endif
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch hour {
        case 5..<12: return isChinese ? "早上好，" : "Good morning,"
        case 12..<17: return isChinese ? "下午好，" : "Good afternoon,"
        case 17..<21: return isChinese ? "晚上好，" : "Good evening,"
        default: return isChinese ? "晚安，" : "Good night,"
        }
    }
    
    private var defaultCoachAvatarContent: some View {
        ZStack {
            Circle()
                .fill(AppTheme.background)
                .frame(width: 42, height: 42)
            
            Text(dataManager.coach.initials.isEmpty ? "?" : dataManager.coach.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.accentGradient)
        }
    }
    
    // MARK: - Today's Briefing Card (Expandable)
    private var todayBriefingCard: some View {
        VStack(spacing: 0) {
            // Main briefing header - tappable to expand
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    briefingExpanded.toggle()
                }
                HapticFeedback.impact(.light)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(todaySessions.isEmpty ? AppTheme.textTertiary : AppTheme.accentColor)
                                .frame(width: 8, height: 8)
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "今日简报" : "TODAY'S BRIEFING")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(todaySessions.isEmpty ? AppTheme.textTertiary : AppTheme.accentColor)
                        }
                        
                        if todaySessions.isEmpty {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "今天没有课程" : "No sessions scheduled")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                        } else {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "今天有 \(todaySessions.count) 节课" : "\(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s") today")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: briefingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(8)
                }
                .padding(20)
            }
            .buttonStyle(.plain)
            
            // Expanded sessions list
            if briefingExpanded && !todaySessions.isEmpty {
                Rectangle()
                    .fill(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(height: 1)
                
                VStack(spacing: 0) {
                    ForEach(Array(todaySessions.enumerated()), id: \.element.id) { index, session in
                        briefingSessionRow(session, isLast: index == todaySessions.count - 1 && dataManager.todayReminders.isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Today's reminders
            if briefingExpanded && !dataManager.todayReminders.isEmpty {
                if !todaySessions.isEmpty {
                    Rectangle()
                        .fill(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                        .frame(height: 1)
                }
                
                VStack(spacing: 0) {
                    // Reminders header
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "今日提醒" : "TODAY'S REMINDERS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    ForEach(Array(dataManager.todayReminders.enumerated()), id: \.element.id) { index, reminder in
                        briefingReminderRow(reminder, isLast: index == dataManager.todayReminders.count - 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func briefingReminderRow(_ reminder: Reminder, isLast: Bool) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let currentCoachId = dataManager.loggedInCoachId ?? dataManager.coach.id
        let isSharedWithMe = reminder.isSharedWith(coachId: currentCoachId)
        let creatorName = isSharedWithMe ? dataManager.staffCoaches.first { $0.id == reminder.creatorCoachId }?.name : nil
        let taggedStudentNames = reminder.taggedStudentIds.compactMap { id in
            dataManager.students.first { $0.id == id }?.name
        }
        
        return HStack(spacing: 12) {
            // Completion circle
            Button(action: {
                HapticFeedback.impact(.light)
                dataManager.toggleReminderCompletion(reminder)
            }) {
                Circle()
                    .stroke(reminder.statusColor, lineWidth: 2)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Priority indicator
                    if reminder.priority == .high {
                        HStack(spacing: 2) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.red)
                    }
                    
                    // Tagged student
                    if !taggedStudentNames.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                            Text(taggedStudentNames.count == 1 ? taggedStudentNames[0] : "\(taggedStudentNames.count)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.blue)
                    }
                    
                    // Shared by indicator
                    if let creatorName = creatorName {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9))
                            Text(isChinese ? "来自\(creatorName)" : "From \(creatorName)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.purple)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(height: 1)
                    .padding(.leading, 46)
            }
        }
    }
    
    private func briefingSessionRow(_ session: SessionEvent, isLast: Bool) -> some View {
        let program = session.programId.flatMap { pid in dataManager.programs.first { $0.id == pid } }
        let isPast = session.endTime < currentTime
        let isNow = session.startTime <= currentTime && session.endTime >= currentTime
        
        return Button(action: { selectedSession = session }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    // Time
                    VStack(spacing: 2) {
                        Text(session.startTime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(isNow ? AppTheme.accentColor : (isPast ? AppTheme.textTertiary : AppTheme.textPrimary))
                    }
                    .frame(width: 55, alignment: .leading)
                    
                    // Status dot
                    Circle()
                        .fill(isNow ? AppTheme.accentColor : (isPast ? AppTheme.textTertiary.opacity(0.3) : AppTheme.successColor))
                        .frame(width: 8, height: 8)
                    
                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isPast ? AppTheme.textTertiary : AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            if let program = program {
                                HStack(spacing: 4) {
                                    Image(systemName: program.mascot.icon)
                                        .font(.system(size: 10))
                                    Text(program.mascot.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(program.mascotColor.opacity(isPast ? 0.5 : 1))
                            }
                            
                            Text("\(session.attendeeIds.count) players")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    
                    Spacer()
                    
                    // Status
                    if isNow {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.isDark ? Color(hex: "#0D0D0D") : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accentColor)
                            .cornerRadius(6)
                    } else if isPast {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.successColor.opacity(0.5))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                        .frame(height: 1)
                        .padding(.leading, 80)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Live Game Alert
    private var liveGameAlert: some View {
        let game = liveGames.first ?? Game(id: UUID(), homeTeamId: UUID(), awayTeamId: UUID(), homeScore: 0, awayScore: 0, date: Date(), status: .scheduled, createdAt: Date(), updatedAt: Date())
        let homeTeam = dataManager.teams.first { $0.id == game.homeTeamId }
        let awayTeam = dataManager.teams.first { $0.id == game.awayTeamId }
        
        return Button(action: {
            selectedLiveGame = game
            showingLiveScoring = true
        }) {
            HStack(spacing: 12) {
                // Live indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                // Score
                HStack(spacing: 8) {
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(game.awayScore) - \(game.homeScore)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(12)
            .background(Color.red.opacity(0.9))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Attention Required Card (Blue - Flighty Style)
    private var attentionRequiredCard: some View {
        let mostUrgent = getMostUrgentItem()
        
        return VStack(alignment: .leading, spacing: 0) {
            // Hero stat
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "需要关注" : "ATTENTION REQUIRED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.7))
                
                // Big number
                Text("\(totalActionItems)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "项需要您关注" : "items need your attention")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                // Most urgent item preview
                if let urgent = mostUrgent {
                    HStack(spacing: 8) {
                        Image(systemName: urgent.icon)
                            .font(.system(size: 12))
                        Text(urgent.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 4)
                }
            }
            .padding(20)
            
            // View all button
            if totalActionItems > 1 {
                Button(action: { showingAllAttentionItems = true }) {
                    HStack {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "查看全部" : "All Attention Items")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.15))
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#1e3a8a"), Color(hex: "#1e40af")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(AppTheme.cornerRadius)
    }
    
    private func getMostUrgentItem() -> (icon: String, title: String)? {
        // Overdue reminders are highest priority
        if let first = dataManager.overdueReminders.first {
            return ("bell.badge.fill", "\(first.title) - \(first.relativeTimeString)")
        } else if let first = expiringContracts.first {
            return ("exclamationmark.triangle.fill", "\(first.student.name) - \(first.contract.remainingSessions ?? 0) sessions left")
        } else if let first = unplannedSessions.first {
            return ("clipboard", "\(first.title) needs planning")
        } else if let first = dataManager.upcomingReminders.first {
            return ("bell", "\(first.title) - \(first.relativeTimeString)")
        } else if let first = programsNeedingPlanning.first {
            return ("calendar.badge.exclamationmark", "\(first.name) has no phases")
        }
        return nil
    }
    
    // MARK: - Today's Players Card (Red/Coral - Flighty Style)
    private var todaysPlayersCard: some View {
        let hero = heroPlayer
        let heroGrade = hero.map { effectivePerformanceGrade(for: $0) }
        let player = hero.flatMap { s in dataManager.players.first { $0.studentId == s.id } }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Hero player display - tappable to open student detail
            Button(action: {
                if let hero = hero {
                    selectedStudent = hero
                }
            }) {
                HStack(spacing: 16) {
                    // Left side - Player info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14))
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "今日学员" : "TODAY'S PLAYERS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        
                        if let hero = hero {
                            Text(hero.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            HStack(spacing: 16) {
                                if let heroGrade = heroGrade {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(heroGrade == .ungraded ? "-" : heroGrade.displayName)
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "能力评级" : "performance")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                
                                if let player = player, let focus = player.skills.lowestSkill {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(focus)
                                            .font(.system(size: 14, weight: .bold))
                                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "重点提升" : "focus area")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.top, 2)
                        } else {
                            Text("\(todaysPlayers.count)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "今日学员" : "players today")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                    
                    // Right side - Profile picture
                    if let hero = hero {
                        heroPlayerAvatar(hero)
                    }
                }
                .padding(20)
            }
            .buttonStyle(.plain)
            
            // View all players button
            Button(action: { showingAllPlayers = true }) {
                HStack {
                    // Stack of avatars preview
                    HStack(spacing: -8) {
                        ForEach(todaysPlayers.prefix(3)) { student in
                            miniAvatar(student)
                        }
                        if todaysPlayers.count > 3 {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 28, height: 28)
                                Text("+\(todaysPlayers.count - 3)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "查看全部 \(todaysPlayers.count) 名学员" : "See all \(todaysPlayers.count) players")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.15))
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#991b1b"), Color(hex: "#b91c1c")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(AppTheme.cornerRadius)
    }
    
    // MARK: - Coaching Wisdom Card (Inspirational quotes)
    private var playerGrowthCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let quotes: [(quote: String, author: String, role: String, initials: String)] = isChinese ? [
            ("努力会打败天赋，当天赋不够努力的时候。", "蒂姆·诺特克", "篮球教练", "TN"),
            ("我职业生涯投丢了9000多个球，输了近300场比赛。26次被托付绝杀却失手。我一生中一次又一次地失败，这就是我成功的原因。", "迈克尔·乔丹", "名人堂球员", "MJ"),
            ("伟大不是天生的，是磨练出来的。", "科比·布莱恩特", "名人堂球员", "KB"),
            ("我不是来这里平庸的，我是来这里成为最好的。", "勒布朗·詹姆斯", "NBA传奇", "LJ"),
            ("基本功就是你每天都做的小事，让大事发生。", "约翰·伍登", "UCLA传奇教练", "JW"),
            ("如果你不愿意付出别人在付出的代价，你就永远得不到别人正在得到的东西。", "帕特·莱利", "名人堂教练", "PR"),
            ("每一天你要么变得更好，要么变得更差——你永远不会保持原样。", "鲍勃·奈特", "大学篮球名帅", "BK"),
            ("成功不是偶然的，它是努力、坚持、学习、牺牲，最重要的是热爱你正在做的事。", "佩莱·席尔瓦", "足球传奇", "PS"),
            ("没有完美的球员，只有追求完美的球员。", "格雷格·波波维奇", "NBA主教练", "GP"),
            ("唯一能阻止你实现梦想的人是你自己。", "凯文·杜兰特", "NBA球星", "KD"),
            ("防守赢得总冠军。", "保罗·皮尔斯", "名人堂球员", "PP"),
            ("最好的球员是最努力工作的球员。天赋只能带你走到这里。", "蒂姆·邓肯", "名人堂球员", "TD"),
            ("你必须期待自己能成功，然后才能真正做到。", "迈克尔·乔丹", "名人堂球员", "MJ"),
            ("篮球不是你打得有多好，而是你让队友打得有多好。", "魔术师约翰逊", "名人堂球员", "MJ"),
            ("一切伟大的事情都需要时间。耐心点。", "卡梅罗·安东尼", "NBA名宿", "CA"),
            ("控制你能控制的，其他的就让它去吧。", "史蒂夫·科尔", "NBA主教练", "SK"),
            ("最难的技能不是投篮——是在压力下保持冷静。", "雷·阿伦", "名人堂射手", "RA"),
            ("每一次训练都是提升自己的机会。", "凯里·欧文", "NBA球星", "KI"),
            ("学会失败才能学会成功。", "勒布朗·詹姆斯", "NBA传奇", "LJ"),
            ("专注于过程，结果会自然而来。", "尼克·纳斯", "NBA主教练", "NN"),
            ("团队篮球永远打败个人篮球。", "菲尔·杰克逊", "传奇教练", "PJ"),
            ("你每天都在和昨天的自己比赛。", "德怀恩·韦德", "名人堂球员", "DW"),
            ("态度决定高度。", "查尔斯·巴克利", "名人堂球员", "CB"),
            ("伟大的球员让周围的人都变得更好。", "拉里·伯德", "名人堂球员", "LB"),
            ("你的习惯决定你的未来。", "斯蒂芬·库里", "NBA球星", "SC"),
            ("先学会跑步，再学会飞翔。", "姚明", "名人堂球员", "YM"),
            ("教练能教你技术，但心态要靠自己。", "托尼·帕克", "名人堂球员", "TP"),
            ("成功需要牺牲，但牺牲是值得的。", "德克·诺维茨基", "名人堂球员", "DN"),
            ("每一滴汗水都是进步的证明。", "吉安尼斯·安特托昆博", "NBA球星", "GA"),
            ("相信自己，即使没人相信你。", "凯文·加内特", "名人堂球员", "KG"),
            ("天赋可以让你起步，但努力让你到达终点。", "克里斯·保罗", "NBA名宿", "CP"),
            ("不要害怕失败，害怕的应该是不去尝试。", "卡尔·马龙", "名人堂球员", "KM")
        ] : [
            ("Hard work beats talent when talent doesn't work hard.", "Tim Notke", "Basketball Coach", "TN"),
            ("I've missed more than 9,000 shots. Lost almost 300 games. 26 times I've been trusted to take the game-winning shot and missed. I've failed over and over. That's why I succeed.", "Michael Jordan", "Hall of Fame Player", "MJ"),
            ("Greatness is not born, it's grown.", "Kobe Bryant", "Hall of Fame Player", "KB"),
            ("I'm not here to be average. I'm here to be the best.", "LeBron James", "NBA Legend", "LJ"),
            ("Fundamentals are the little things you do every day that make big things happen.", "John Wooden", "UCLA Legend", "JW"),
            ("If you're not willing to pay the price that others are paying, you will never get what they are getting.", "Pat Riley", "Hall of Fame Coach", "PR"),
            ("Every day you're either getting better or worse — you never stay the same.", "Bob Knight", "College Basketball Legend", "BK"),
            ("Success isn't accidental. It's hard work, perseverance, learning, sacrifice, and most of all, love for what you're doing.", "Pelé", "Football Legend", "P"),
            ("There are no perfect players. Only players who pursue perfection.", "Gregg Popovich", "NBA Head Coach", "GP"),
            ("The only person who can stop you from achieving your dreams is yourself.", "Kevin Durant", "NBA Star", "KD"),
            ("Defense wins championships.", "Paul Pierce", "Hall of Fame Player", "PP"),
            ("The best players are the hardest workers. Talent only gets you so far.", "Tim Duncan", "Hall of Fame Player", "TD"),
            ("You have to expect things of yourself before you can do them.", "Michael Jordan", "Hall of Fame Player", "MJ"),
            ("Basketball isn't about how well you play — it's about how well you make your teammates play.", "Magic Johnson", "Hall of Fame Player", "MJ"),
            ("All great things take time. Be patient.", "Carmelo Anthony", "NBA Veteran", "CA"),
            ("Control what you can control and let everything else go.", "Steve Kerr", "NBA Head Coach", "SK"),
            ("The hardest skill isn't shooting — it's staying calm under pressure.", "Ray Allen", "Hall of Fame Shooter", "RA"),
            ("Every practice is an opportunity to get better.", "Kyrie Irving", "NBA Star", "KI"),
            ("You have to learn how to fail before you learn how to succeed.", "LeBron James", "NBA Legend", "LJ"),
            ("Focus on the process and the results will come.", "Nick Nurse", "NBA Head Coach", "NN"),
            ("Team basketball always beats individual basketball.", "Phil Jackson", "Legendary Coach", "PJ"),
            ("Every day you're competing against the person you were yesterday.", "Dwyane Wade", "Hall of Fame Player", "DW"),
            ("Attitude determines altitude.", "Charles Barkley", "Hall of Fame Player", "CB"),
            ("Great players make everyone around them better.", "Larry Bird", "Hall of Fame Player", "LB"),
            ("Your habits determine your future.", "Stephen Curry", "NBA Star", "SC"),
            ("Learn to walk before you try to fly.", "Yao Ming", "Hall of Fame Player", "YM"),
            ("A coach can teach you technique, but mindset is on you.", "Tony Parker", "Hall of Fame Player", "TP"),
            ("Success requires sacrifice, but sacrifice is worth it.", "Dirk Nowitzki", "Hall of Fame Player", "DN"),
            ("Every drop of sweat is proof of progress.", "Giannis Antetokounmpo", "NBA Star", "GA"),
            ("Believe in yourself even when no one else does.", "Kevin Garnett", "Hall of Fame Player", "KG"),
            ("Talent gets you started, but hard work gets you to the finish line.", "Chris Paul", "NBA Veteran", "CP"),
            ("Don't fear failure. Fear not trying.", "Karl Malone", "Hall of Fame Player", "KM"),
            ("The separation is in the preparation.", "Russell Wilson", "NFL Star", "RW"),
            ("Excellence is not a singular act, but a habit.", "Shaquille O'Neal", "Hall of Fame Player", "SO"),
            ("Champions are built in the offseason.", "Brad Stevens", "NBA Executive", "BS"),
            ("Your work ethic is the only thing you can fully control.", "Jimmy Butler", "NBA Star", "JB")
        ]
        let randomQuote = quotes[Int.random(in: 0..<quotes.count)]
        
        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 12, weight: .medium))
                Text(isChinese ? "训练智慧" : "COACHING WISDOM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.7))
            
            // Quote Content
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\"\(randomQuote.quote)\"")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("— \(randomQuote.author)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text(randomQuote.role)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer(minLength: 0)
                
                // Speaker initials avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    Text(randomQuote.initials)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "#0D5C4D"), Color(hex: "#1A8C7A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(AppTheme.cornerRadius)
    }
    
    // Hero player avatar with profile picture
    private func heroPlayerAvatar(_ student: Student) -> some View {
        Group {
            if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                if imageUrl.hasPrefix("file://") || imageUrl.hasPrefix("/") {
                    // Local image
                    let path = imageUrl.hasPrefix("file://") ? String(imageUrl.dropFirst(7)) : imageUrl
                    #if os(iOS)
                    if let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
                    } else {
                        initialsAvatar(student, size: 72)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
                    } else {
                        initialsAvatar(student, size: 72)
                    }
                    #endif
                } else {
                    // Remote URL
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
                        default:
                            initialsAvatar(student, size: 72)
                        }
                    }
                }
            } else {
                initialsAvatar(student, size: 72)
            }
        }
    }
    
    // Initials avatar fallback
    private func initialsAvatar(_ student: Student, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: size, height: size)
            Text(student.initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
    }
    
    // Mini avatar for the preview stack
    private func miniAvatar(_ student: Student) -> some View {
        Group {
            if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                if imageUrl.hasPrefix("file://") || imageUrl.hasPrefix("/") {
                    let path = imageUrl.hasPrefix("file://") ? String(imageUrl.dropFirst(7)) : imageUrl
                    #if os(iOS)
                    if let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                    } else {
                        miniInitialsAvatar(student)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                    } else {
                        miniInitialsAvatar(student)
                    }
                    #endif
                } else {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                        } else {
                            miniInitialsAvatar(student)
                        }
                    }
                }
            } else {
                miniInitialsAvatar(student)
            }
        }
    }
    
    private func miniInitialsAvatar(_ student: Student) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: student.avatarColor))
                .frame(width: 28, height: 28)
            Text(student.initials)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
    }
    
    private func avatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .pink: return .pink
        case .indigo: return .indigo
        }
    }
}

// MARK: - Skills Evaluation Extension
extension SkillsEvaluation {
    var lowestSkill: String? {
        let skills: [(String, Int)] = [
            ("Shooting", shooting),
            ("Ball Handling", ballHandling),
            ("Defense", defense),
            ("Basketball IQ", basketballIQ),
            ("Athleticism", athleticism),
            ("Teamwork", teamwork)
        ]
        return skills.min(by: { $0.1 < $1.1 })?.0
    }
}

// MARK: - All Attention Items Sheet (Flighty Past Flights Style)
struct AllAttentionItemsSheet: View {
    @Environment(\.dismiss) var dismiss
    let expiringContracts: [(contract: Contract, student: Student)]
    let unplannedSessions: [SessionEvent]
    let programsNeedingPlanning: [Program]
    var onSelectStudent: (Student) -> Void
    var onSelectSession: (SessionEvent) -> Void
    var onSelectProgram: (Program) -> Void
    
    // Filter state
    @State private var activeFilter: TimeFilter = .thisWeek
    
    enum TimeFilter: String, CaseIterable {
        case today, tomorrow, thisWeek
        
        var label: String {
            switch self {
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            case .thisWeek: return "This Week"
            }
        }
        
        var labelChinese: String {
            switch self {
            case .today: return "今天"
            case .tomorrow: return "明天"
            case .thisWeek: return "本周"
            }
        }
    }
    
    // Colors
    private let grayText = Color(hex: "#8E8E93")
    private let lightGray = Color(hex: "#C7C7CC")
    private let iconTileBg = Color(hex: "#E8F0FA")
    private let iconGlyph = Color(hex: "#3478F6")
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let filtered = filteredSessions
        
        return NavigationStack {
            VStack(spacing: 0) {
                // Native segmented picker for filters
                Picker(isChinese ? "筛选" : "Filter", selection: $activeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(filterLabel(filter: filter, isChinese: isChinese))
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                
                // Session list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, session in
                            Button(action: {
                                dismiss()
                                onSelectSession(session)
                            }) {
                                sessionRow(session: session, isChinese: isChinese)
                            }
                            .buttonStyle(.plain)
                            
                            if index < filtered.count - 1 {
                                Divider()
                                    .padding(.leading, 62)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "未计划课程" : "Unplanned Sessions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Filter Label with Count
    private func filterLabel(filter: TimeFilter, isChinese: Bool) -> String {
        let count = countForFilter(filter)
        let label = isChinese ? filter.labelChinese : filter.label
        return "\(label) \(count)"
    }
    
    // MARK: - Compact Session Row (~56pt)
    private func sessionRow(session: SessionEvent, isChinese: Bool) -> some View {
        HStack(spacing: 10) {
            // Small icon tile 36x36
            RoundedRectangle(cornerRadius: 8)
                .fill(iconTileBg)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(iconGlyph)
                )
            
            // Center: two lines
            VStack(alignment: .leading, spacing: 2) {
                // Line 1: TRN + time (gray, regular)
                HStack(spacing: 4) {
                    Text(sessionTypeCode(session))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(grayText)
                    Text("·")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(grayText)
                    Text(formatTime(session.date))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(grayText)
                }
                
                // Line 2: title (medium weight, NOT bold)
                Text(session.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer(minLength: 4)
            
            // Right: date + chevron
            HStack(spacing: 6) {
                Text(formatDate(session.date, isChinese: isChinese))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(grayText)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(lightGray)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
    }
    
    // MARK: - Helpers
    private var filteredSessions: [SessionEvent] {
        let calendar = Calendar.current
        let now = Date()
        let sorted = unplannedSessions.sorted { $0.date < $1.date }
        
        switch activeFilter {
        case .today:
            return sorted.filter { calendar.isDateInToday($0.date) }
        case .tomorrow:
            return sorted.filter { calendar.isDateInTomorrow($0.date) }
        case .thisWeek:
            return sorted.filter {
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start)!
                return $0.date >= start && $0.date < end
            }
        }
    }
    
    private func countForFilter(_ filter: TimeFilter) -> Int {
        let calendar = Calendar.current
        let now = Date()
        
        switch filter {
        case .today:
            return unplannedSessions.filter { calendar.isDateInToday($0.date) }.count
        case .tomorrow:
            return unplannedSessions.filter { calendar.isDateInTomorrow($0.date) }.count
        case .thisWeek:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            return unplannedSessions.filter { $0.date >= start && $0.date < end }.count
        }
    }
    
    private func sessionTypeCode(_ session: SessionEvent) -> String {
        switch session.sessionType {
        case .training: return "TRN"
        case .scrimmage: return "SCR"
        case .gamePrep: return "GMP"
        case .recovery: return "RCV"
        case .assessment: return "AST"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date, isChinese: Bool) -> String {
        let formatter = DateFormatter()
        if isChinese {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}

// MARK: - All Players Sheet
struct AllPlayersSheet: View {
    @Environment(\.dismiss) var dismiss
    let players: [Student]
    let dataManager: DataManager
    var onSelectStudent: (Student) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(players) { student in
                        Button(action: {
                            dismiss()
                            onSelectStudent(student)
                        }) {
                            UnifiedStudentCard(student: student, mode: .compact, showQuickActions: false)
                                .padding(14)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Today's Players")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Live Session Activity Card
/// Shows turn-by-turn drill progress for an in-progress session
struct LiveSessionActivityCard: View {
    @EnvironmentObject var dataManager: DataManager
    let session: SessionEvent
    
    @State private var currentDrillIndex: Int = 0
    @State private var currentSection: CurriculumSection = .warmup
    @State private var elapsedSeconds: Int = 0
    @State private var isPaused: Bool = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    enum CurriculumSection: String, CaseIterable {
        case warmup = "WARMUP"
        case skills = "SKILLS"
        case game = "GAME"
        
        var icon: String {
            switch self {
            case .warmup: return "flame.fill"
            case .skills: return "figure.basketball"
            case .game: return "trophy.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .warmup: return .orange
            case .skills: return .blue
            case .game: return .green
            }
        }
    }
    
    private var allDrills: [(drill: DrillItem, section: CurriculumSection)] {
        var drills: [(DrillItem, CurriculumSection)] = []
        
        for drillId in session.curriculum.warmupDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drills.append((drill, .warmup))
            }
        }
        for drillId in session.curriculum.skillDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drills.append((drill, .skills))
            }
        }
        for drillId in session.curriculum.gameDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drills.append((drill, .game))
            }
        }
        
        return drills
    }
    
    private var currentDrill: DrillItem? {
        guard currentDrillIndex < allDrills.count else { return nil }
        return allDrills[currentDrillIndex].drill
    }
    
    private var nextDrill: DrillItem? {
        guard currentDrillIndex + 1 < allDrills.count else { return nil }
        return allDrills[currentDrillIndex + 1].drill
    }
    
    private var progress: Double {
        guard !allDrills.isEmpty else { return 0 }
        return Double(currentDrillIndex) / Double(allDrills.count)
    }
    
    private var program: Program? {
        session.programId.flatMap { programId in
            dataManager.programs.first { $0.id == programId }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with session info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(Color.green.opacity(0.3))
                                    .frame(width: 16, height: 16)
                            )
                        Text("LIVE SESSION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    
                    Text(session.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Program mascot
                if let program = program {
                    VStack(spacing: 2) {
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 24))
                            .foregroundColor(program.mascotColor)
                        Text(program.mascot.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(16)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(currentSection.color)
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            
            // Current drill - main focus
            if let drill = currentDrill {
                VStack(spacing: 12) {
                    // Section indicator
                    HStack {
                        Image(systemName: currentSection.icon)
                            .font(.system(size: 12))
                        Text(currentSection.rawValue)
                            .font(.system(size: 11, weight: .bold))
                        
                        Spacer()
                        
                        Text("\(currentDrillIndex + 1) of \(allDrills.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(currentSection.color)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Drill card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(drill.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        if !drill.description.isEmpty {
                            Text(drill.description)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                        
                        // Duration and equipment
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                Text("\(drill.durationMinutes) min")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            
                            if !drill.equipmentNeeded.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "sportscourt")
                                        .font(.system(size: 12))
                                    Text(drill.equipmentNeeded.joined(separator: ", "))
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    
                    // Navigation controls
                    HStack(spacing: 20) {
                        // Previous
                        Button(action: previousDrill) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(currentDrillIndex > 0 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentDrillIndex == 0)
                        
                        // Pause/Play (optional future feature)
                        Button(action: { isPaused.toggle() }) {
                            Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.white)
                        }
                        
                        // Next
                        Button(action: nextDrillAction) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(currentDrillIndex < allDrills.count - 1 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentDrillIndex >= allDrills.count - 1)
                    }
                    .padding(.vertical, 16)
                    
                    // Up next preview
                    if let next = nextDrill {
                        HStack(spacing: 8) {
                            Text("UP NEXT:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                            Text(next.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.bottom, 16)
                    }
                }
            } else {
                // No drills or completed
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Session Complete!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(32)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.9), currentSection.color.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .onAppear {
            updateCurrentSection()
        }
    }
    
    private func previousDrill() {
        guard currentDrillIndex > 0 else { return }
        withAnimation(.spring(response: 0.3)) {
            currentDrillIndex -= 1
            updateCurrentSection()
        }
        HapticFeedback.impact(.light)
    }
    
    private func nextDrillAction() {
        guard currentDrillIndex < allDrills.count - 1 else { return }
        withAnimation(.spring(response: 0.3)) {
            currentDrillIndex += 1
            updateCurrentSection()
        }
        HapticFeedback.impact(.light)
    }
    
    private func updateCurrentSection() {
        guard currentDrillIndex < allDrills.count else { return }
        currentSection = allDrills[currentDrillIndex].section
    }
}

// MARK: - Preview
#Preview {
    FlightyActionableDashboard()
        .environmentObject(DataManager.shared)
}
