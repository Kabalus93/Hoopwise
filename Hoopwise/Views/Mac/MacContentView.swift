import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
/// Main content view for macOS with elegant sidebar navigation
struct MacContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: MacTab = .home
    @State private var selectedStudent: Student?
    @State private var selectedProgram: Program?
    @State private var selectedSession: SessionEvent?
    @State private var selectedTeam: Team?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var showingAddSheet = false
    
    // Dashboard state
    @State private var isNeedsAttentionExpanded = false
    @State private var showingSettings = false
    
    // Add/Edit sheet states
    @State private var showingAddProgram = false
    @State private var showingAddPhase = false
    @State private var showingAddSession = false
    @State private var editingProgram: Program? = nil
    @State private var editingPhase: MicroCycle? = nil
    @State private var editingSession: SessionEvent? = nil
    
    // Hierarchy selection for sheets
    @State private var selectedProgramForHierarchy: Program? = nil
    @State private var selectedPhaseForHierarchy: MicroCycle? = nil
    @State private var selectedSessionForHierarchy: SessionEvent? = nil
    
    // League state
    @State private var leagueTab: MacLeagueTab = .games
    @State private var showingCreateTeam = false
    @State private var showingScheduleGame = false
    @State private var selectedGame: Game? = nil
    
    // Hub state - now uses expandable cards instead of tabs
    @State private var expandedHubCard: MacHubCard? = nil
    @State private var showingAddStudent = false
    @State private var showingStudentDetail: Student? = nil
    @State private var showingStudentsOverlay = false
    @State private var showingStudentImport = false
    @State private var showingContractsOverlay = false
    @State private var showingContractDetail: Contract? = nil
    @State private var showingOrganization = false
    @State private var showingCoachLibrary = false
    @State private var athleteSearchText: String = ""
    @State private var drillSubSection: DrillSubSection = .drills
    
    enum MacHubCard: String, CaseIterable {
        case athletes = "Athletes"
        case drillsAndPlays = "Drills & Plays"
        case organization = "Organization"
        
        var icon: String {
            switch self {
            case .athletes: return "person.3.fill"
            case .drillsAndPlays: return "sportscourt.fill"
            case .organization: return "building.2.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .athletes: return GlassColors.accentCyan
            case .drillsAndPlays: return GlassColors.accentOrange
            case .organization: return Color.purple
            }
        }
    }
    
    enum DrillSubSection: String, CaseIterable {
        case drills = "Drills"
        case plays = "Plays"
        case studio = "Studio"
    }
    
    // Legacy - kept for compatibility
    @State private var hubSection: MacHubSection = .athletes
    enum MacHubSection: String, CaseIterable {
        case athletes = "Athletes"
        case drills = "Drills"
        case organization = "Organization"
    }
    
    enum MacLeagueTab: String, CaseIterable {
        case games = "Games"
        case teams = "Teams"
        case standings = "Standings"
        case stats = "Stats"
        
        var icon: String {
            switch self {
            case .games: return "sportscourt.fill"
            case .teams: return "person.3.fill"
            case .standings: return "list.number"
            case .stats: return "chart.bar.fill"
            }
        }
    }
    
    enum MacTab: String, CaseIterable, Identifiable {
        case home = "Dashboard"
        case sessions = "Sessions"
        case league = "League"
        case hub = "Hub"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .home: return "rectangle.3.group.fill"
            case .sessions: return "calendar.badge.clock"
            case .league: return "trophy.fill"
            case .hub: return "person.3.fill"
            }
        }
        
        var gradient: LinearGradient {
            switch self {
            case .home: return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .sessions: return LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .league: return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .hub: return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Ambient dark background
            AmbientBackground()
            
            // Main content with glass panels
            HStack(spacing: 0) {
                // Glass Sidebar
                glassSidebar
                    .frame(width: 260)
                
                // Main Content Area
                glassContentArea
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            MacSettingsView()
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingStudentImport) {
            MacStudentImportSheet()
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddProgram) {
            AddProgramSheet()
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddPhase) {
            if let program = selectedProgramForHierarchy {
                AddPhaseSheet(program: program)
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $showingAddSession) {
            if let phase = selectedPhaseForHierarchy, let program = selectedProgramForHierarchy {
                AddSessionSheet(phase: phase, program: program)
                    .environmentObject(dataManager)
            }
        }
        .sheet(item: $editingProgram) { program in
            EditProgramSheet(program: program)
                .environmentObject(dataManager)
        }
        .sheet(item: $editingPhase) { phase in
            if let program = selectedProgramForHierarchy {
                EditPhaseSheet(phase: phase, program: program)
                    .environmentObject(dataManager)
            }
        }
        .sheet(item: $editingSession) { session in
            EditSessionSheet(session: session)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedSession) { session in
            SessionPageView(session: session, accessMode: .execution)
                .environmentObject(dataManager)
                .frame(minWidth: 700, minHeight: 600)
        }
        .slideInPanel(
            isPresented: $showingCreateTeam,
            title: "Create Team",
            minWidth: 400,
            maxWidth: 520
        ) {
            CreateTeamPanelContent(isPresented: $showingCreateTeam)
        }
        .slideInPanel(
            isPresented: $showingScheduleGame,
            title: "Schedule Game",
            minWidth: 400,
            maxWidth: 520
        ) {
            ScheduleGamePanelContent(isPresented: $showingScheduleGame)
        }
        .slideInPanel(
            isPresented: Binding(
                get: { selectedGame != nil },
                set: { if !$0 { selectedGame = nil } }
            ),
            title: selectedGame.map { gameTitle(for: $0) } ?? "Game Details",
            minWidth: 420,
            maxWidth: 560
        ) {
            if let game = selectedGame {
                GameDetailPanelContent(
                    game: game,
                    isPresented: Binding(
                        get: { selectedGame != nil },
                        set: { if !$0 { selectedGame = nil } }
                    )
                )
            }
        }
        .slideInPanel(
            isPresented: Binding(
                get: { selectedTeam != nil },
                set: { if !$0 { selectedTeam = nil } }
            ),
            title: selectedTeam?.name ?? "Team Details",
            minWidth: 420,
            maxWidth: 800
        ) {
            if let team = selectedTeam {
                TeamDetailPanelContent(
                    team: team,
                    isPresented: Binding(
                        get: { selectedTeam != nil },
                        set: { if !$0 { selectedTeam = nil } }
                    )
                )
            }
        }
        .overlay {
            if showingAddStudent {
                MacAddStudentOverlay(
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingAddStudent = false
                        }
                    }
                )
                .environmentObject(dataManager)
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }
        }
        .overlay {
            if let student = showingStudentDetail {
                MacStudentDetailOverlay(student: student) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingStudentDetail = nil
                    }
                }
                .environmentObject(dataManager)
                .transition(.move(edge: .trailing))
                .zIndex(100)
            }
        }
        .overlay {
            if showingStudentsOverlay {
                MacStudentsListOverlay(
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingStudentsOverlay = false
                        }
                    },
                    onAddStudent: {
                        showingStudentsOverlay = false
                        showingAddStudent = true
                    },
                    onImport: {
                        showingStudentsOverlay = false
                        showingStudentImport = true
                    }
                )
                .environmentObject(dataManager)
                .transition(.move(edge: .trailing))
                .zIndex(99)
            }
        }
        .overlay {
            if showingContractsOverlay {
                MacContractsListOverlay(
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingContractsOverlay = false
                        }
                    }
                )
                .environmentObject(dataManager)
                .transition(.move(edge: .trailing))
                .zIndex(99)
            }
        }
        .overlay {
            if showingOrganization {
                MacOrganizationOverlay(
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingOrganization = false
                        }
                    }
                )
                .environmentObject(dataManager)
                .transition(.move(edge: .trailing))
                .zIndex(99)
            }
        }
        .sheet(isPresented: $showingCoachLibrary) {
            MacCoachResourcesView()
                .environmentObject(dataManager)
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
    
    // MARK: - Helpers
    private func gameTitle(for game: Game) -> String {
        let home = dataManager.teams.first { $0.id == game.homeTeamId }
        let away = dataManager.teams.first { $0.id == game.awayTeamId }
        return "\(away?.shortName ?? "AWY") @ \(home?.shortName ?? "HME")"
    }
    
    // MARK: - Glass Sidebar
    private var glassSidebar: some View {
        VStack(spacing: 0) {
            // App Header - Glass Style
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(GlassColors.accentCyan)
                        .frame(width: 40, height: 40)
                        .shadow(color: GlassColors.accentCyan.opacity(0.4), radius: 8, x: 0, y: 2)
                    
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoopwise")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Basketball Training Manager")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            
            // Navigation Items
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(MacTab.allCases) { tab in
                        GlassNavItem(
                            icon: tab.icon,
                            title: tab.rawValue,
                            isSelected: selectedTab == tab,
                            badge: badgeCount(for: tab),
                            action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            
            Spacer()
            
            // Bottom Profile Section
            VStack(spacing: 12) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                
                HStack(spacing: 12) {
                    // Profile avatar
                    Button(action: { showingSettings = true }) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(GlassColors.accentOrange)
                                    .frame(width: 36, height: 36)
                                
                                Text(dataManager.coach.initials.isEmpty ? "?" : dataManager.coach.initials)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dataManager.coach.name.isEmpty ? "Set up profile" : dataManager.coach.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(dataManager.coach.email.isEmpty ? "Configure" : "Coach")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Sync button
                    Button(action: {
                        Task { await dataManager.fullSync() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(SupabaseManager.shared.isConnected ? GlassColors.accentGreen : .white.opacity(0.4))
                            .rotationEffect(.degrees(dataManager.isSyncing ? 360 : 0))
                            .animation(dataManager.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataManager.isSyncing)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .glassCard(cornerRadius: GlassMetrics.radiusLarge, opacity: 0.06, borderOpacity: 0.15, padding: 0)
        .padding(.trailing, 16)
    }
    
    private func badgeCount(for tab: MacTab) -> Int? {
        switch tab {
        case .home:
            return actionItems.isEmpty ? nil : actionItems.count
        case .sessions:
            return dataManager.upcomingSessions.isEmpty ? nil : dataManager.upcomingSessions.count
        default:
            return nil
        }
    }
    
    // MARK: - Glass Content Area
    private var glassContentArea: some View {
        VStack(spacing: 0) {
            // Glass Header Bar
            glassHeaderBar
            
            // Main Content
            ScrollView(showsIndicators: false) {
                switch selectedTab {
                case .home:
                    glassDashboardContent
                case .sessions:
                    glassSessionsContent
                case .league:
                    glassLeagueContent
                case .hub:
                    glassHubContent
                }
            }
        }
        .glassCard(cornerRadius: GlassMetrics.radiusLarge, opacity: 0.06, borderOpacity: 0.15, padding: 0)
    }
    
    // MARK: - Glass Header Bar
    private var glassHeaderBar: some View {
        HStack(spacing: 16) {
            // Search field
            GlassTextField(placeholder: "Search \(selectedTab.rawValue.lowercased())...", text: $searchText, icon: "magnifyingglass")
                .frame(maxWidth: 300)
            
            Spacer()
            
            // Filter pills based on current tab
            glassFilterPills
            
            Spacer()
            
            // Date display
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundColor(GlassColors.accentCyan)
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Primary action button
            CircularActionButton(
                icon: primaryActionIcon,
                size: 44,
                accentColor: GlassColors.accentCyan
            ) {
                performPrimaryAction()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var primaryActionIcon: String {
        switch selectedTab {
        case .home: return "plus"
        case .sessions: return "plus"
        case .league: return "plus"
        case .hub: return "person.badge.plus"
        }
    }
    
    private func performPrimaryAction() {
        switch selectedTab {
        case .home:
            showingAddProgram = true
        case .sessions:
            if let program = dataManager.programs.first {
                selectedProgramForHierarchy = program
                if let phase = dataManager.microCycles.first(where: { $0.programId == program.id }) {
                    selectedPhaseForHierarchy = phase
                    showingAddSession = true
                } else {
                    showingAddPhase = true
                }
            } else {
                showingAddProgram = true
            }
        case .league:
            showingCreateTeam = true
        case .hub:
            showingAddStudent = true
        }
    }
    
    @ViewBuilder
    private var glassFilterPills: some View {
        switch selectedTab {
        case .home:
            HStack(spacing: 8) {
                GlassFilterPill(title: "All", isSelected: true)
                GlassFilterPill(title: "Programs", isSelected: false)
                GlassFilterPill(title: "Athletes", isSelected: false)
            }
        case .sessions:
            HStack(spacing: 8) {
                GlassFilterPill(title: "Upcoming", isSelected: true)
                GlassFilterPill(title: "Past", isSelected: false)
                GlassFilterPill(title: "All", isSelected: false)
            }
        case .league:
            HStack(spacing: 8) {
                GlassFilterPill(title: "Games", isSelected: leagueTab == .games) { leagueTab = .games }
                GlassFilterPill(title: "Teams", isSelected: leagueTab == .teams) { leagueTab = .teams }
                GlassFilterPill(title: "Standings", isSelected: leagueTab == .standings) { leagueTab = .standings }
            }
        case .hub:
            // Hub now uses card-based navigation, no filter pills needed
            EmptyView()
        }
    }
    
    // MARK: - Legacy Sidebar (kept for reference)
    private var sidebar: some View {
        glassSidebar
    }
    
    // MARK: - Glass Dashboard Content
    private var glassDashboardContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Key Metrics Row
            HStack(spacing: 16) {
                GlassStatCard(
                    title: "Active Athletes",
                    value: "\(dataManager.students.count)",
                    icon: "person.3.fill",
                    trend: "+3",
                    trendUp: true,
                    accentColor: GlassColors.accentCyan
                )
                
                GlassStatCard(
                    title: "Programs",
                    value: "\(dataManager.programs.filter { $0.status != .archived }.count)",
                    icon: "rectangle.stack.fill",
                    accentColor: GlassColors.accentOrange
                )
                
                GlassStatCard(
                    title: "This Week",
                    value: "\(dataManager.upcomingSessions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }.count)",
                    icon: "calendar.badge.clock",
                    accentColor: GlassColors.accentGreen
                )
                
                GlassStatCard(
                    title: "Revenue",
                    value: "¥\(Int(dataManager.monthlyRevenue / 1000))k",
                    icon: "yensign.circle.fill",
                    trend: "+12%",
                    trendUp: true,
                    accentColor: GlassColors.accentYellow
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Main content area - two columns
            HStack(alignment: .top, spacing: 20) {
                // Left column - Programs & Sessions
                VStack(alignment: .leading, spacing: 20) {
                    // Programs Section (excluding archived)
                    GlassSectionHeader(
                        title: "Programs",
                        subtitle: "\(dataManager.programs.filter { $0.status != .archived }.count) active",
                        actionLabel: "View All"
                    ) {
                        selectedTab = .sessions
                    }
                    
                    if dataManager.programs.filter({ $0.status != .archived }).isEmpty {
                        GlassEmptyState(
                            icon: "rectangle.stack.badge.plus",
                            title: "No Programs Yet",
                            message: "Create your first training program to get started",
                            actionLabel: "Create Program"
                        ) {
                            showingAddProgram = true
                        }
                        .frame(height: 200)
                    } else {
                        ForEach(dataManager.programs.filter { $0.status != .archived }.prefix(3)) { program in
                            GlassProgramCard(program: program) {
                                selectedProgramForHierarchy = program
                            } onEdit: {
                                editingProgram = program
                            }
                        }
                    }
                    
                    // Today's Sessions
                    GlassSectionHeader(
                        title: "Today's Schedule",
                        subtitle: todaySessionsSubtitle
                    )
                    
                    if todaySessions.isEmpty {
                        GlassDataCard {
                            HStack {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.4))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No sessions today")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("Enjoy your day off!")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                
                                Spacer()
                            }
                        }
                    } else {
                        ForEach(todaySessions) { session in
                            GlassSessionCard(session: session) {
                                selectedSession = session
                            } onEdit: {
                                editingSession = session
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right column - Quick Actions & Athletes
                VStack(alignment: .leading, spacing: 20) {
                    // Quick Actions
                    GlassSectionHeader(title: "Quick Actions")
                    
                    VStack(spacing: 8) {
                        GlassQuickActionButton(
                            icon: "plus.rectangle.fill",
                            title: "New Program",
                            subtitle: "Create training program",
                            accentColor: GlassColors.accentCyan
                        ) {
                            showingAddProgram = true
                        }
                        
                        GlassQuickActionButton(
                            icon: "person.badge.plus",
                            title: "Add Athlete",
                            subtitle: "Register new student",
                            accentColor: GlassColors.accentOrange
                        ) {
                            showingAddStudent = true
                        }
                        
                        GlassQuickActionButton(
                            icon: "calendar.badge.plus",
                            title: "Schedule Session",
                            subtitle: "Plan a training session",
                            accentColor: GlassColors.accentGreen
                        ) {
                            if let program = dataManager.programs.first,
                               let phase = dataManager.microCycles.first(where: { $0.programId == program.id }) {
                                selectedProgramForHierarchy = program
                                selectedPhaseForHierarchy = phase
                                showingAddSession = true
                            } else {
                                showingAddProgram = true
                            }
                        }
                    }
                    
                    // Recent Athletes
                    GlassSectionHeader(
                        title: "Athletes",
                        subtitle: "\(dataManager.students.count) total",
                        actionLabel: "View All"
                    ) {
                        hubSection = .athletes
                        selectedTab = .hub
                    }
                    
                    ForEach(dataManager.students.prefix(5)) { student in
                        GlassAthleteRow(student: student) {
                            showingStudentDetail = student
                        }
                    }
                    
                    Spacer()
                }
                .frame(width: 320)
            }
            .padding(.horizontal, 24)
            
            Spacer(minLength: 40)
        }
    }
    
    private var todaySessionsSubtitle: String {
        let count = todaySessions.count
        return count == 0 ? "No sessions" : "\(count) session\(count == 1 ? "" : "s")"
    }
    
    // MARK: - Glass Sessions Content
    private var glassSessionsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Programs hierarchy
            HStack(alignment: .top, spacing: 20) {
                // Programs list
                VStack(alignment: .leading, spacing: 16) {
                    GlassSectionHeader(
                        title: "Programs",
                        actionLabel: "New Program"
                    ) {
                        showingAddProgram = true
                    }
                    
                    if dataManager.programs.isEmpty {
                        GlassEmptyState(
                            icon: "rectangle.stack.badge.plus",
                            title: "No Programs",
                            message: "Create a program to organize your training sessions",
                            actionLabel: "Create Program"
                        ) {
                            showingAddProgram = true
                        }
                    } else {
                        ForEach(dataManager.programs) { program in
                            GlassProgramCard(
                                program: program,
                                isSelected: selectedProgramForHierarchy?.id == program.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedProgramForHierarchy = program
                                    selectedPhaseForHierarchy = nil
                                }
                            } onEdit: {
                                editingProgram = program
                            }
                        }
                    }
                }
                .frame(width: 280)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                        .fill(Color.white.opacity(0.04))
                )
                
                // Phases for selected program
                if let program = selectedProgramForHierarchy {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(
                            title: "Phases",
                            subtitle: program.name,
                            actionLabel: "Add Phase"
                        ) {
                            showingAddPhase = true
                        }
                        
                        let phases = dataManager.microCycles.filter { $0.programId == program.id }
                        
                        if phases.isEmpty {
                            GlassEmptyState(
                                icon: "square.stack.3d.up",
                                title: "No Phases",
                                message: "Add phases to structure your program",
                                actionLabel: "Add Phase"
                            ) {
                                showingAddPhase = true
                            }
                        } else {
                            ForEach(phases.sorted { $0.phaseNumber < $1.phaseNumber }) { phase in
                                GlassPhaseCard(
                                    phase: phase,
                                    isSelected: selectedPhaseForHierarchy?.id == phase.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPhaseForHierarchy = phase
                                    }
                                } onEdit: {
                                    editingPhase = phase
                                }
                            }
                        }
                    }
                    .frame(width: 260)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                
                // Sessions for selected phase
                if let phase = selectedPhaseForHierarchy {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(
                            title: "Sessions",
                            subtitle: phase.title,
                            actionLabel: "Add Session"
                        ) {
                            showingAddSession = true
                        }
                        
                        let sessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
                        
                        if sessions.isEmpty {
                            GlassEmptyState(
                                icon: "calendar.badge.plus",
                                title: "No Sessions",
                                message: "Schedule training sessions for this phase",
                                actionLabel: "Add Session"
                            ) {
                                showingAddSession = true
                            }
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(sessions.sorted { $0.date < $1.date }) { session in
                                        GlassSessionCard(session: session) {
                                            selectedSession = session
                                        } onEdit: {
                                            editingSession = session
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
    
    // MARK: - Glass League Content
    private var glassLeagueContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch leagueTab {
            case .games:
                glassGamesView
            case .teams:
                glassTeamsView
            case .standings:
                glassStandingsView
            case .stats:
                glassStatsView
            }
        }
        .padding(24)
    }
    
    private var glassGamesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(
                title: "Games",
                subtitle: "\(dataManager.games.count) scheduled",
                actionLabel: "Schedule Game"
            ) {
                showingScheduleGame = true
            }
            
            if dataManager.games.isEmpty {
                GlassEmptyState(
                    icon: "sportscourt",
                    title: "No Games Scheduled",
                    message: "Schedule your first game to track scores and stats",
                    actionLabel: "Schedule Game"
                ) {
                    showingScheduleGame = true
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(dataManager.games.sorted { $0.date > $1.date }) { game in
                        GlassGameCard(game: game) {
                            selectedGame = game
                        }
                    }
                }
            }
        }
    }
    
    private var glassTeamsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(
                title: "Teams",
                subtitle: "\(dataManager.teams.count) teams",
                actionLabel: "Create Team"
            ) {
                showingCreateTeam = true
            }
            
            if dataManager.teams.isEmpty {
                GlassEmptyState(
                    icon: "person.3.fill",
                    title: "No Teams Yet",
                    message: "Create teams to organize your league",
                    actionLabel: "Create Team"
                ) {
                    showingCreateTeam = true
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(dataManager.teams) { team in
                        GlassTeamCard(team: team) {
                            selectedTeam = team
                        }
                    }
                }
            }
        }
    }
    
    private var glassStandingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(title: "Standings")
            
            if dataManager.teamStandings.isEmpty {
                GlassEmptyState(
                    icon: "list.number",
                    title: "No Standings",
                    message: "Play some games to see team standings"
                )
            } else {
                GlassDataCard {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Team")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("W")
                                .frame(width: 40)
                            Text("L")
                                .frame(width: 40)
                            Text("PCT")
                                .frame(width: 60)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 12)
                        
                        ForEach(dataManager.teamStandings.sorted { $0.winPercentage > $1.winPercentage }) { standing in
                            if let team = dataManager.teams.first(where: { $0.id == standing.teamId }) {
                                HStack {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color(hex: team.colorHex))
                                            .frame(width: 24, height: 24)
                                        Text(team.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text("\(standing.wins)")
                                        .frame(width: 40)
                                    Text("\(standing.losses)")
                                        .frame(width: 40)
                                    Text(String(format: "%.3f", standing.winPercentage))
                                        .frame(width: 60)
                                }
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.vertical, 8)
                                
                                if standing.id != dataManager.teamStandings.last?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var glassStatsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(title: "Season Stats")
            
            GlassEmptyState(
                icon: "chart.bar.fill",
                title: "Stats Coming Soon",
                message: "Player and team statistics will appear here"
            )
        }
    }
    
    // MARK: - Glass Hub Content
    private var glassHubContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let expanded = expandedHubCard {
                // Expanded view with back button
                expandedHubCardView(expanded)
            } else {
                // Hub overview with clickable cards
                hubOverviewCards
            }
        }
    }
    
    // MARK: - Hub Overview Cards
    private var hubOverviewCards: some View {
        HubOverviewView(
            dataManager: dataManager,
            onCardTap: { card in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedHubCard = card
                }
            }
        )
    }
    
    @ViewBuilder
    private func expandedHubCardView(_ card: MacHubCard) -> some View {
        ExpandedHubCardContainer(
            card: card,
            dataManager: dataManager,
            athleteSearchText: $athleteSearchText,
            drillSubSection: $drillSubSection,
            showingAddDrill: $showingAddDrill,
            onBack: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedHubCard = nil
                }
            },
            onAddStudent: { showingAddStudent = true },
            onAddDrill: { showingAddDrill = true },
            onManageOrg: { showingOrganization = true },
            onSelectStudent: { student in showingStudentDetail = student },
            onImport: { showingStudentImport = true }
        )
    }
    
    // Legacy view - kept for compatibility
    private var glassAthletesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                GlassSectionHeader(
                    title: "Athletes",
                    subtitle: "\(dataManager.students.count) registered",
                    actionLabel: "Add Athlete"
                ) {
                    showingAddStudent = true
                }
                
                Spacer()
                
                // Import Button
                Button(action: { showingStudentImport = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.8))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            if dataManager.students.isEmpty {
                GlassEmptyState(
                    icon: "person.badge.plus",
                    title: "No Athletes",
                    message: "Add your first athlete to get started",
                    actionLabel: "Add Athlete"
                ) {
                    showingAddStudent = true
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(filteredStudents) { student in
                        GlassAthleteCard(student: student) {
                            showingStudentDetail = student
                        }
                    }
                }
            }
        }
    }
    
    private var glassContractsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(
                title: "Contracts",
                subtitle: "\(dataManager.contracts.count) active"
            )
            
            if dataManager.contracts.isEmpty {
                GlassEmptyState(
                    icon: "doc.text",
                    title: "No Contracts",
                    message: "Contracts will appear here when athletes are enrolled"
                )
            } else {
                ForEach(dataManager.contracts) { contract in
                    if let student = dataManager.students.first(where: { $0.id == contract.studentId }) {
                        GlassContractCard(contract: contract, student: student)
                    }
                }
            }
        }
    }
    
    // MARK: - Drill Library State
    @State private var showingAddDrill = false
    
    private var glassDrillsView: some View {
        GlassDrillLibraryView(
            dataManager: dataManager,
            showingAddDrill: $showingAddDrill
        )
    }
    
    private func drillCategoryColor(_ category: DrillCategory) -> Color {
        switch category {
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .warmup: return GlassColors.accentYellow
        case .cooldown: return Color.cyan
        }
    }
    
    private var glassOrganizationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionHeader(
                title: "Organization",
                actionLabel: "Manage"
            ) {
                showingOrganization = true
            }
            
            HStack(spacing: 16) {
                GlassStatCard(
                    title: "Staff Coaches",
                    value: "\(dataManager.staffCoaches.count)",
                    icon: "person.2.fill",
                    accentColor: GlassColors.accentCyan
                )
                
                GlassStatCard(
                    title: "Locations",
                    value: "\(dataManager.locations.count)",
                    icon: "mappin.circle.fill",
                    accentColor: GlassColors.accentOrange
                )
            }
        }
    }
    
    // MARK: - Content List (Full Width for all tabs)
    @ViewBuilder
    private var contentList: some View {
        switch selectedTab {
        case .home:
            homeContentList
        case .sessions:
            sessionsContentList
        case .league:
            leagueContentList
        case .hub:
            hubContentList
        }
    }
    
    // MARK: - Home Content (Dashboard) - Redesigned Clean Layout
    private var homeContentList: some View {
        ZStack {
            // Main scrollable content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with greeting and date
                    dashboardHeader
                    
                    // Live Session Banner (when a session is in progress)
                    if let session = activeSession {
                        macLiveSessionBanner(session: session)
                            .padding(.horizontal, 32)
                    }
                    
                    // Priority Alert Card (only if urgent items exist)
                    if !actionItems.isEmpty {
                        priorityAlertCard
                    }
                    
                    // Key Metrics Row - 3 essential stats
                    keyMetricsRow
                    
                    // Main Content - 2 column layout
                    HStack(alignment: .top, spacing: 20) {
                        // Left: Today's Timeline
                        todayTimelineCard
                            .frame(maxWidth: .infinity)
                        
                        // Right: Quick Actions & Insights
                        VStack(spacing: 16) {
                            quickActionsCard
                            if !upcomingGames.isEmpty {
                                upcomingGamesCard
                            }
                            recentAthletesCard
                        }
                        .frame(width: 320)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            // Slide-in panel for details
            if showingDashboardPanel {
                dashboardDetailPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingDashboardPanel)
    }
    
    // Dashboard panel state
    @State private var showingDashboardPanel = false
    @State private var dashboardPanelContent: DashboardPanelContent = .none
    
    enum DashboardPanelContent {
        case none
        case actionItems
        case athlete(Student)
        case game(Game)
        case session(SessionEvent)
    }
    
    // MARK: - Dashboard Header (Flighty Style)
    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Coach profile image
            coachAvatarView
            
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Text(dataManager.coach.name.isEmpty ? "Dashboard" : dataManager.coach.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            // Date pill - elegant frosted glass
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        }
        .padding(.horizontal, 24)
    }
    
    // Coach avatar view with profile image support
    private var coachAvatarView: some View {
        Group {
            if let imageUrlString = dataManager.coach.profileImageUrl,
               let imageUrl = URL(string: imageUrlString) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    case .failure, .empty:
                        defaultCoachAvatar
                    @unknown default:
                        defaultCoachAvatar
                    }
                }
            } else {
                defaultCoachAvatar
            }
        }
    }
    
    private var defaultCoachAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            
            Text(dataManager.coach.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    // MARK: - Priority Alert Card (Flighty Style)
    private var priorityAlertCard: some View {
        let urgentCount = actionItems.filter { $0.urgency != nil }.count
        
        return Button(action: {
            dashboardPanelContent = .actionItems
            showingDashboardPanel = true
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(urgentCount > 0 ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: urgentCount > 0 ? "exclamationmark.triangle.fill" : "bell.badge.fill")
                        .font(.system(size: 14))
                        .foregroundColor(urgentCount > 0 ? .red : .orange)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(urgentCount > 0 ? "\(urgentCount) Urgent Item\(urgentCount == 1 ? "" : "s")" : "Items Need Attention")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text("\(actionItems.count) total • Tap to review")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Preview badges
                HStack(spacing: 4) {
                    let contractIssues = actionItems.filter { if case .contract = $0.type { return true }; return false }.count
                    let sessionIssues = actionItems.filter { if case .session = $0.type { return true }; return false }.count
                    
                    if contractIssues > 0 {
                        Label("\(contractIssues)", systemImage: "doc.text")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    if sessionIssues > 0 {
                        Label("\(sessionIssues)", systemImage: "calendar")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Key Metrics Row (Flighty Style)
    private var keyMetricsRow: some View {
        HStack(spacing: 12) {
            // Today's Sessions
            GlassMetricCard(
                icon: "calendar.badge.clock",
                iconColor: .blue,
                value: "\(todaySessionsCount)",
                label: "Today",
                detail: nextSessionTime ?? "No sessions",
                progress: todaySessionsCount > 0 ? Double(completedTodaySessions) / Double(todaySessionsCount) : nil
            )
            
            // This Week
            GlassMetricCard(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .green,
                value: "\(sessionsThisWeek)",
                label: "This Week",
                detail: weeklySessionsTrend.map { "\($0) vs last week" } ?? "sessions",
                trend: weeklySessionsTrend
            )
            
            // Revenue
            GlassMetricCard(
                icon: "dollarsign.circle.fill",
                iconColor: .mint,
                value: monthlyEarningsShort,
                label: "This Month",
                detail: "\(newContractsThisMonth) new contracts",
                progress: monthlyEarningsProgress
            )
            
            // Athletes
            GlassMetricCard(
                icon: "person.2.fill",
                iconColor: .purple,
                value: "\(dataManager.students.count)",
                label: "Athletes",
                detail: "\(activeContractsCount) active",
                progress: dataManager.students.count > 0 ? Double(activeContractsCount) / Double(dataManager.students.count) : nil
            )
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Today Timeline Card (Flighty Style)
    private var todayTimelineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Today's Schedule")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                if !todaySessions.isEmpty || !todayGames.isEmpty {
                    Text("\(todaySessions.count + todayGames.count) events")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
            .padding(12)
            
            Divider().padding(.horizontal, 12)
            
            // Timeline content
            if todaySessions.isEmpty && todayGames.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    Text("All Clear Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    Text("No sessions or games scheduled")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let allEvents = buildTodayTimeline()
                        
                        ForEach(Array(allEvents.enumerated()), id: \.element.id) { index, event in
                            TimelineEventRow(
                                event: event,
                                isLast: index == allEvents.count - 1,
                                onTap: {
                                    switch event.type {
                                    case .session(let session):
                                        dashboardPanelContent = .session(session)
                                        showingDashboardPanel = true
                                    case .game(let game):
                                        dashboardPanelContent = .game(game)
                                        showingDashboardPanel = true
                                    }
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    private var todayGames: [Game] {
        dataManager.games.filter { Calendar.current.isDateInToday($0.date) }
    }
    
    struct TimelineEvent: Identifiable {
        let id = UUID()
        let time: Date
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let type: EventType
        
        enum EventType {
            case session(SessionEvent)
            case game(Game)
        }
    }
    
    private func buildTodayTimeline() -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        
        for session in todaySessions {
            events.append(TimelineEvent(
                time: session.startTime,
                title: session.title,
                subtitle: session.sessionType.displayName,
                icon: session.sessionType.icon,
                color: .blue,
                type: .session(session)
            ))
        }
        
        for game in todayGames {
            let homeTeam = dataManager.teams.first { $0.id == game.homeTeamId }
            let awayTeam = dataManager.teams.first { $0.id == game.awayTeamId }
            events.append(TimelineEvent(
                time: game.date,
                title: "\(homeTeam?.shortName ?? "Home") vs \(awayTeam?.shortName ?? "Away")",
                subtitle: game.status == .live ? "LIVE" : game.venue ?? "Game",
                icon: "sportscourt.fill",
                color: game.status == .live ? .red : .orange,
                type: .game(game)
            ))
        }
        
        return events.sorted { $0.time < $1.time }
    }
    
    // MARK: - Quick Actions Card (Flighty Style)
    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK ACTIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            
            VStack(spacing: 2) {
                QuickActionRow(icon: "plus.circle.fill", title: "New Session", color: .blue) {
                    selectedTab = .sessions
                }
                
                QuickActionRow(icon: "person.badge.plus", title: "Add Athlete", color: .purple) {
                    selectedTab = .hub
                    showingAddStudent = true
                }
                
                QuickActionRow(icon: "sportscourt", title: "Schedule Game", color: .orange) {
                    selectedTab = .league
                    showingScheduleGame = true
                }
                
                QuickActionRow(icon: "book.closed.fill", title: "Coach Library", color: .green) {
                    showingCoachLibrary = true
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Upcoming Games Card (Flighty Style)
    private var upcomingGamesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UPCOMING GAMES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button("View All") { selectedTab = .league }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            VStack(spacing: 6) {
                ForEach(upcomingGames.prefix(3)) { game in
                    CompactGameRow(game: game, dataManager: dataManager) {
                        dashboardPanelContent = .game(game)
                        showingDashboardPanel = true
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Recent Athletes Card (Flighty Style) - Enhanced with Focus Area
    private var recentAthletesCard: some View {
        let focusAthlete = athleteNeedingAttention ?? dataManager.students.first
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TODAY'S FOCUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button("All Athletes") { selectedTab = .hub }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            if let student = focusAthlete {
                // Featured athlete with score
                Button(action: {
                    dashboardPanelContent = .athlete(student)
                    showingDashboardPanel = true
                }) {
                    HStack(spacing: 12) {
                        // Avatar with score ring
                        ZStack {
                            // Score ring
                            Circle()
                                .stroke(focusScoreColor(for: student).opacity(0.2), lineWidth: 3)
                                .frame(width: 48, height: 48)
                            
                            Circle()
                                .trim(from: 0, to: focusScore(for: student) / 100)
                                .stroke(focusScoreColor(for: student), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 48, height: 48)
                                .rotationEffect(.degrees(-90))
                            
                            // Avatar
                            Circle()
                                .fill(Color.avatarColor(student.avatarColor))
                                .frame(width: 38, height: 38)
                            
                            Text(student.initials)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        // Info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(student.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                                .lineLimit(1)
                            
                            // Focus indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(focusScoreColor(for: student))
                                    .frame(width: 6, height: 6)
                                Text(focusReason(for: student))
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        // Score badge
                        VStack(spacing: 2) {
                            Text("\(Int(focusScore(for: student)))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(focusScoreColor(for: student))
                            Text(focusScoreLabel(for: student))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 44)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                // Divider
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                
                // Other athletes row
                let otherStudents = dataManager.students.filter { $0.id != student.id }.prefix(3)
                if !otherStudents.isEmpty {
                    HStack(spacing: 0) {
                        HStack(spacing: -6) {
                            ForEach(Array(otherStudents.enumerated()), id: \.element.id) { index, otherStudent in
                                Button(action: {
                                    dashboardPanelContent = .athlete(otherStudent)
                                    showingDashboardPanel = true
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.avatarColor(otherStudent.avatarColor))
                                            .frame(width: 26, height: 26)
                                        
                                        Text(otherStudent.initials)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .zIndex(Double(otherStudents.count - index))
                            }
                            
                            if dataManager.students.count > 4 {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 26, height: 26)
                                    
                                    Text("+\(dataManager.students.count - 4)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.gray)
                                }
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(dataManager.students.count) total")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 22))
                        .foregroundColor(.gray.opacity(0.3))
                    Text("No athletes yet")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Focus Athlete Helpers
    
    private var athleteNeedingAttention: Student? {
        // Find athlete with lowest overall score or needs attention
        dataManager.students.min { student1, student2 in
            focusScore(for: student1) < focusScore(for: student2)
        }
    }
    
    private func focusScore(for student: Student) -> Double {
        let contract = dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
        let player = dataManager.player(for: student.id)
        let seasonStats = player.flatMap { p in dataManager.seasonStats.first { $0.playerId == p.id } }
        
        // Calculate scores similar to UnifiedStudentCard
        let financialScore = calculateFinancialScore(contract: contract)
        let performanceScore = calculatePerformanceScore(player: player, stats: seasonStats)
        let behavioralScore = calculateBehavioralScore(student: student)
        
        return (financialScore + performanceScore + behavioralScore) / 3.0
    }
    
    private func calculateFinancialScore(contract: Contract?) -> Double {
        guard let contract = contract else { return 0 }
        var score: Double = 50
        let remaining = contract.remainingSessions ?? 0
        let sessionRatio = Double(remaining) / Double(max(contract.totalSessions, 1))
        score += sessionRatio * 30
        if contract.isFullyPaid { score += 20 }
        return min(100, score)
    }
    
    private func calculatePerformanceScore(player: Player?, stats: SeasonStats?) -> Double {
        if let stats = stats, stats.gamesPlayed > 0 {
            return min(100, 40 + stats.ppg * 3)
        }
        if let player = player {
            return player.skills.overallRating * 10
        }
        return 50
    }
    
    private func calculateBehavioralScore(student: Student) -> Double {
        var score: Double = 70
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days <= 7 { score += 15 }
            else if days <= 14 { score += 10 }
            else if days > 30 { score -= 20 }
        } else {
            score -= 10
        }
        return min(100, max(0, score))
    }
    
    private func focusScoreColor(for student: Student) -> Color {
        let score = focusScore(for: student)
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    private func focusScoreLabel(for student: Student) -> String {
        let contract = dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
        let financialScore = calculateFinancialScore(contract: contract)
        let player = dataManager.player(for: student.id)
        let seasonStats = player.flatMap { p in dataManager.seasonStats.first { $0.playerId == p.id } }
        let performanceScore = calculatePerformanceScore(player: player, stats: seasonStats)
        let behavioralScore = calculateBehavioralScore(student: student)
        
        // Return the lowest scoring category
        if financialScore <= performanceScore && financialScore <= behavioralScore {
            return "Financial"
        } else if performanceScore <= behavioralScore {
            return "Perform"
        } else {
            return "Behavior"
        }
    }
    
    private func focusReason(for student: Student) -> String {
        let contract = dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
        
        // Check for specific issues
        if contract == nil {
            return "No active contract"
        }
        if let c = contract, (c.remainingSessions ?? 0) <= 3 {
            return "\((c.remainingSessions ?? 0)) sessions left"
        }
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days > 21 {
                return "No contact in \(days)d"
            }
        } else {
            return "Never contacted"
        }
        
        let score = focusScore(for: student)
        if score >= 75 {
            return "Doing great"
        } else if score >= 50 {
            return "Needs attention"
        }
        return "Priority focus"
    }
    
    // MARK: - Dashboard Detail Panel (Slides from Right)
    private var dashboardDetailPanel: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showingDashboardPanel = false
                }
            
            // Panel content
            VStack(spacing: 0) {
                // Panel header
                HStack {
                    switch dashboardPanelContent {
                    case .actionItems:
                        Text("Action Items")
                    case .athlete(let student):
                        Text(student.name)
                    case .game:
                        Text("Game Details")
                    case .session(let session):
                        Text(session.title)
                    case .none:
                        Text("Details")
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Panel body
                ScrollView {
                    switch dashboardPanelContent {
                    case .actionItems:
                        actionItemsPanelContent
                    case .athlete(let student):
                        athletePanelContent(student)
                    case .game(let game):
                        gamePanelContent(game)
                    case .session(let session):
                        sessionPanelContent(session)
                    case .none:
                        EmptyView()
                    }
                }
                
                Spacer()
                
                // Close button
                Button(action: { showingDashboardPanel = false }) {
                    Text("Close")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .frame(width: 380)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var actionItemsPanelContent: some View {
        VStack(spacing: 2) {
            ForEach(actionItems) { item in
                MacActionItemRow(item: item, dataManager: dataManager) {
                    handleActionItem(item)
                    showingDashboardPanel = false
                }
            }
        }
        .padding()
    }
    
    private func athletePanelContent(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Avatar and name
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 60, height: 60)
                    
                    Text(student.initials)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if let age = student.age {
                        Text("\(age) years old")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            // Contract status
            if let contract = dataManager.contracts.first(where: { $0.studentId == student.id && $0.status == .active }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE CONTRACT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    HStack {
                        Text("\(contract.remainingSessions ?? 0)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor((contract.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary)
                        Text("sessions remaining")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    ProgressView(value: contract.progressPercentage)
                        .tint(AppTheme.accentColor)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No active contract")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            // View full profile button
            Button(action: {
                showingDashboardPanel = false
                selectedTab = .hub
                showingStudentDetail = student
            }) {
                Text("View Full Profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentColor.opacity(0.1))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private func gamePanelContent(_ game: Game) -> some View {
        let homeTeam = dataManager.teams.first { $0.id == game.homeTeamId }
        let awayTeam = dataManager.teams.first { $0.id == game.awayTeamId }
        
        return VStack(alignment: .leading, spacing: 16) {
            // Teams
            HStack {
                VStack {
                    Text(homeTeam?.shortName ?? "Home")
                        .font(.system(size: 16, weight: .bold))
                    if game.status != .scheduled {
                        Text("\(game.homeScore)")
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                
                Text("vs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                
                VStack {
                    Text(awayTeam?.shortName ?? "Away")
                        .font(.system(size: 16, weight: .bold))
                    if game.status != .scheduled {
                        Text("\(game.awayScore)")
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Game info
            VStack(alignment: .leading, spacing: 8) {
                Label(game.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                
                if let venue = game.venue {
                    Label(venue, systemImage: "mappin")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Label(game.status.rawValue, systemImage: "circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(game.status == .live ? .red : AppTheme.textSecondary)
            }
            
            // View game button
            Button(action: {
                showingDashboardPanel = false
                selectedTab = .league
                selectedGame = game
            }) {
                Text("View Game Details")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentColor.opacity(0.1))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private func sessionPanelContent(_ session: SessionEvent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Session type badge
            HStack {
                Label(session.sessionType.displayName, systemImage: session.sessionType.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
                
                Spacer()
                
                Text(session.status.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            // Time and location
            VStack(alignment: .leading, spacing: 8) {
                Label(session.startTime.formatted(date: .omitted, time: .shortened) + " - " + session.endTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                
                if let location = session.location {
                    Label(location, systemImage: "mappin")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Label("\(session.attendeeIds.count) athletes", systemImage: "person.2")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            // Curriculum status
            if session.curriculum.totalDrillCount == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No drills planned")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(session.curriculum.totalDrillCount) drills planned")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Start session button
            Button(action: {
                showingDashboardPanel = false
                selectedSession = session
            }) {
                Text("Open Session")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentColor)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Full Games Section (for wider layout)
    private var fullGamesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Upcoming Games", systemImage: "sportscourt.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button("View All") { selectedTab = .league }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
                    .buttonStyle(.plain)
            }
            
            VStack(spacing: 10) {
                ForEach(upcomingGames.prefix(4)) { game in
                    MacDashboardGameRow(game: game, dataManager: dataManager) {
                        selectedGame = game
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    private var emptyGamesPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
            Text("No Upcoming Games")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Text("Schedule a game in the League tab")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
            Button(action: { selectedTab = .league }) {
                Text("Go to League")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - This Week Section (for wider layout)
    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("This Week", systemImage: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(upcomingSessions.filter { !Calendar.current.isDateInToday($0.date) }.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
            }
            
            let weekSessions = upcomingSessions.filter { !Calendar.current.isDateInToday($0.date) }
            if weekSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    Text("All clear this week")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(weekSessions.prefix(5)) { session in
                        MacDashboardSessionRow(session: session) {
                            editingSession = session
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Dashboard Header (for full-width layout)
    private var dashboardDateHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text("Dashboard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            // Date pill
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accentColor)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.03)))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Smart Stats Grid (2x3 for full-width)
    private var smartStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
            // Today's Sessions - with progress ring
            MacDashboardStatCard(
                icon: "calendar.badge.clock",
                value: "\(todaySessionsCount)",
                label: "Today's Sessions",
                subtitle: nextSessionTime,
                color: .blue,
                progress: todaySessionsCount > 0 ? Double(completedTodaySessions) / Double(todaySessionsCount) : nil,
                trend: nil
            ) {
                if let session = todaySessions.first { editingSession = session }
            }
            
            // Weekly Sessions - with trend
            MacDashboardStatCard(
                icon: "chart.line.uptrend.xyaxis",
                value: "\(sessionsThisWeek)",
                label: "This Week",
                subtitle: "sessions scheduled",
                color: .green,
                progress: nil,
                trend: weeklySessionsTrend
            ) {
                selectedTab = .sessions
            }
            
            // Athletes - with active ratio bar
            MacDashboardStatCard(
                icon: "person.2.fill",
                value: "\(dataManager.students.count)",
                label: "Athletes",
                subtitle: "\(activeContractsCount) with contracts",
                color: .purple,
                progress: dataManager.students.count > 0 ? Double(activeContractsCount) / Double(dataManager.students.count) : nil,
                trend: nil
            ) {
                selectedTab = .hub
            }
            
            // Teams - with games indicator
            MacDashboardStatCard(
                icon: "trophy.fill",
                value: "\(dataManager.teams.count)",
                label: "Teams",
                subtitle: "\(upcomingGames.count) upcoming games",
                color: .orange,
                progress: nil,
                trend: nil,
                badge: upcomingGames.isEmpty ? nil : "\(upcomingGames.count)"
            ) {
                selectedTab = .league
            }
            
            // Monthly Earnings - with goal progress
            MacDashboardStatCard(
                icon: "dollarsign.circle.fill",
                value: monthlyEarningsShort,
                label: "This Month",
                subtitle: "\(newContractsThisMonth) new contracts",
                color: .mint,
                progress: monthlyEarningsProgress,
                trend: nil
            ) {
                selectedTab = .hub
            }
            
            // Action Items - with urgency indicator
            MacDashboardStatCard(
                icon: "bell.badge.fill",
                value: "\(actionItems.count)",
                label: "Actions Needed",
                subtitle: urgentActionsCount > 0 ? "\(urgentActionsCount) urgent" : "all routine",
                color: urgentActionsCount > 0 ? .red : .gray,
                progress: nil,
                trend: nil,
                badge: urgentActionsCount > 0 ? "!" : nil
            ) {
                withAnimation { isNeedsAttentionExpanded.toggle() }
            }
        }
        .padding(.horizontal, 32)
    }
    
    // Additional computed properties for stats
    private var completedTodaySessions: Int {
        todaySessions.filter { $0.status == .completed }.count
    }
    
    private var weeklySessionsTrend: String? {
        // Compare to last week (simplified)
        let lastWeekCount = sessionsLastWeek
        if lastWeekCount == 0 { return nil }
        let diff = sessionsThisWeek - lastWeekCount
        if diff > 0 { return "+\(diff)" }
        else if diff < 0 { return "\(diff)" }
        return nil
    }
    
    private var sessionsLastWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        guard let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: calendar.startOfDay(for: now)),
              let lastWeekEnd = calendar.date(byAdding: .day, value: 7, to: lastWeekStart) else { return 0 }
        return dataManager.sessionEvents.filter { $0.date >= lastWeekStart && $0.date < lastWeekEnd }.count
    }
    
    private var urgentActionsCount: Int {
        actionItems.filter { $0.urgency != nil }.count
    }
    
    private var monthlyEarningsProgress: Double? {
        // Assume a monthly goal of $5000 for progress visualization
        let goal = 5000.0
        return min(monthlyEarnings / goal, 1.0)
    }
    
    private var monthlyEarningsShort: String {
        let value = monthlyEarnings
        if value >= 1000 { return "$\(Int(value / 1000))k" }
        return "$\(Int(value))"
    }
    
    // MARK: - Compact Games Section (for right column)
    private var compactGamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Games", systemImage: "sportscourt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button("All") { selectedTab = .league }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .buttonStyle(.plain)
            }
            
            VStack(spacing: 8) {
                ForEach(upcomingGames.prefix(3)) { game in
                    MacCompactGameRow(game: game, dataManager: dataManager) {
                        selectedTab = .league
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(14)
    }
    
    // MARK: - Compact Upcoming Section (for right column)
    private var compactUpcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This Week", systemImage: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            VStack(spacing: 6) {
                ForEach(upcomingSessions.filter { !Calendar.current.isDateInToday($0.date) }.prefix(4)) { session in
                    MacCompactSessionRow(session: session) {
                        editingSession = session
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(14)
    }
    
    // MARK: - Today's Schedule Section (for full-width layout)
    private var todayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.accentColor)
                        .frame(width: 10, height: 10)
                    Text("Today's Schedule")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                Spacer()
                if !todaySessions.isEmpty {
                    Text("\(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.accentColor)
                        .cornerRadius(10)
                }
            }
            
            if todaySessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("All Clear Today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("No sessions scheduled")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 10) {
                    ForEach(todaySessions) { session in
                        MacTodaySessionCard(session: session) {
                            editingSession = session
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Expandable Needs Attention Section
    private var expandableNeedsAttentionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible, clickable to expand)
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isNeedsAttentionExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.orange.opacity(0.2), Color.red.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Needs Attention")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("\(actionItems.count) pending")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Urgent badge
                    let urgentCount = actionItems.filter({ $0.urgency != nil }).count
                    if urgentCount > 0 {
                        Text("\(urgentCount) urgent")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red))
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .rotationEffect(.degrees(isNeedsAttentionExpanded ? 90 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            
            // Expandable content
            if isNeedsAttentionExpanded {
                Divider().padding(.horizontal, 14)
                
                VStack(spacing: 2) {
                    ForEach(Array(actionItems.enumerated()), id: \.element.id) { index, item in
                        MacActionItemRow(item: item, dataManager: dataManager) {
                            handleActionItem(item)
                        }
                        .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: [Color.orange.opacity(0.2), Color.red.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
    
    private func handleActionItem(_ item: MacActionItem) {
        switch item.type {
        case .student(let student): selectedStudent = student
        case .program(let program): selectedProgram = program
        case .session(let session): selectedSession = session
        case .contract(let student, _): selectedStudent = student
        }
    }
    
    // MARK: - Live Session Banner (macOS)
    @ViewBuilder
    private func macLiveSessionBanner(session: SessionEvent) -> some View {
        let program = programFor(session)
        let programColor = program?.mascotColor ?? GlassColors.accentOrange
        let elapsed = max(0, Date().timeIntervalSince(session.startTime))
        let total = session.endTime.timeIntervalSince(session.startTime)
        let elapsedMinutes = Int(elapsed / 60)
        let totalMinutes = Int(total / 60)
        let remainingMinutes = max(0, totalMinutes - elapsedMinutes)
        let progress = min(1.0, max(0.0, elapsed / total))
        
        Button(action: { selectedSession = session }) {
            HStack(spacing: 16) {
                // Live indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .fill(Color.red.opacity(0.4))
                                .frame(width: 20, height: 20)
                        )
                    
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                
                // Session info
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(program?.name ?? "Training Session")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Progress bar
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(programColor)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(width: 120, height: 4)
                    
                    Text("\(elapsedMinutes)/\(totalMinutes) min")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Time remaining
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(remainingMinutes)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("min left")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Attendees
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    Text("\(session.actualAttendeeIds.count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [programColor.opacity(0.4), Color.black.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(programColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Computed Properties (Dashboard)
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }
    
    private var todaySessions: [SessionEvent] {
        dataManager.sessionEvents.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date }
    }
    
    private var todaySessionsCount: Int { todaySessions.count }
    
    /// Active session that's currently in progress
    private var activeSession: SessionEvent? {
        dataManager.sessionEvents.first { $0.status == .inProgress }
    }
    
    private func programFor(_ session: SessionEvent) -> Program? {
        guard let programId = session.programId else { return nil }
        return dataManager.programs.first { $0.id == programId }
    }
    
    private var nextSessionTime: String? {
        todaySessions.first { $0.date > Date() }.map { $0.date.formatted(date: .omitted, time: .shortened) }
    }
    
    private var upcomingSessions: [SessionEvent] {
        let now = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return dataManager.sessionEvents.filter { $0.date >= now && $0.date <= weekFromNow }.sorted { $0.date < $1.date }
    }
    
    private var sessionsThisWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? now
        return dataManager.sessionEvents.filter { $0.date >= startOfWeek && $0.date < endOfWeek }.count
    }
    
    private var activeContractsCount: Int {
        dataManager.contracts.filter { ($0.remainingSessions ?? 0) > 0 && !$0.isExpired }.count
    }
    
    private var upcomingGames: [Game] {
        let calendar = Calendar.current
        let now = Date()
        let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        let liveGames = dataManager.games.filter { $0.status == .live }
        let todayGames = dataManager.games.filter { calendar.isDateInToday($0.date) && $0.status == .scheduled }
        let soonGames = dataManager.games.filter { $0.date > now && $0.date <= threeDaysFromNow && !calendar.isDateInToday($0.date) && $0.status == .scheduled }.sorted { $0.date < $1.date }
        return liveGames + todayGames + soonGames
    }
    
    private var actionItems: [MacActionItem] {
        var items: [MacActionItem] = []
        let now = Date()
        let calendar = Calendar.current
        
        // Contract issues
        for contract in dataManager.contracts where contract.status == .active {
            guard let student = dataManager.students.first(where: { $0.id == contract.studentId }) else { continue }
            let remaining = contract.remainingSessions ?? 0
            if remaining <= 3 {
                items.append(MacActionItem(type: .contract(student, contract), icon: remaining == 0 ? "exclamationmark.circle.fill" : "doc.text.fill", iconColor: remaining == 0 ? .red : .orange, title: student.name, subtitle: remaining == 0 ? "No sessions remaining" : "\(remaining) session\(remaining == 1 ? "" : "s") left", urgency: remaining == 0 ? "Depleted" : nil, actionLabel: "Renew"))
            }
        }
        
        // Unprepared sessions
        let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        for session in dataManager.sessionEvents where session.date >= now && session.date <= threeDaysFromNow && session.status == .scheduled {
            if session.curriculum.totalDrillCount == 0 {
                let isToday = calendar.isDateInToday(session.date)
                items.append(MacActionItem(type: .session(session), icon: "clipboard", iconColor: .blue, title: session.title, subtitle: "\(isToday ? "Today" : "Soon") - No drills planned", urgency: isToday ? "Today" : nil, actionLabel: "Prepare"))
            }
        }
        
        // Students without contracts
        for student in dataManager.students {
            let hasActive = dataManager.contracts.contains { $0.studentId == student.id && $0.status == .active }
            if !hasActive {
                items.append(MacActionItem(type: .student(student), icon: "person.crop.circle.badge.questionmark", iconColor: .gray, title: student.name, subtitle: "No active contract", urgency: nil, actionLabel: "Add"))
            }
        }
        
        return items.sorted { ($0.urgency != nil ? 0 : 1) < ($1.urgency != nil ? 0 : 1) }
    }
    
    // MARK: - Sessions Content (Programs > Phases > Sessions hierarchy)
    @State private var selectedProgramId: UUID? = nil
    @State private var selectedPhaseId: UUID? = nil
    @State private var sessionsViewMode: SessionsViewMode = .programs
    
    enum SessionsViewMode: String, CaseIterable {
        case programs = "Programs"
        case calendar = "Calendar"
    }
    
    private var sessionsContentList: some View {
        VStack(spacing: 0) {
            // Header with view mode toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training & Programs")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Coaching")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                // View mode picker
                Picker("View", selection: $sessionsViewMode) {
                    ForEach(SessionsViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Button(action: { showingAddProgram = true }) {
                    Label("New Program", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentColor)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content based on view mode
            if sessionsViewMode == .programs {
                programsHierarchyView
            } else {
                sessionsCalendarView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Programs Hierarchy View (adaptive sliding panels)
    private var programsHierarchyView: some View {
        let _ = debugLog("🔍 programsHierarchyView - Program: \(selectedProgramForHierarchy?.name ?? "nil"), Phase: \(selectedPhaseForHierarchy?.title ?? "nil")")
        return HStack(spacing: 0) {
            // PHASE SELECTED: Phases | Phase Detail | Sessions
            if let phase = selectedPhaseForHierarchy, let program = selectedProgramForHierarchy {
                // DEBUG
                Text("BRANCH 1: PHASE SELECTED").foregroundColor(.red).padding()
                // Phases column (with back button to programs)
                phasesColumnWithBack(for: program)
                
                Divider()
                
                // Phase detail panel
                phaseDetailColumn(for: phase, program: program)
                
                Divider()
                
                // Sessions column
                sessionsColumn(for: phase, program: program)
                
                // Session detail (when selected)
                if let session = selectedSessionForHierarchy {
                    Divider()
                    sessionDetailColumn(for: session, program: program)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // PROGRAM SELECTED (no phase): Programs | Program Detail | Phases
            else if let program = selectedProgramForHierarchy {
                // DEBUG
                Text("BRANCH 2: PROGRAM ONLY").foregroundColor(.green).padding()
                programsColumn
                
                Divider()
                
                // Program detail panel
                programOverviewColumn(for: program)
                
                Divider()
                
                // Phases column
                phasesColumn(for: program)
            }
            // NO SELECTION: Programs | Empty state
            else {
                // DEBUG
                Text("BRANCH 3: NO SELECTION").foregroundColor(.blue).padding()
                programsColumn
                
                Divider()
                
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.left.circle")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                        Text("Select a Program")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Choose a program to view its details and phases")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedProgramForHierarchy?.id)
        .animation(.easeInOut(duration: 0.25), value: selectedPhaseForHierarchy?.id)
        .animation(.easeInOut(duration: 0.25), value: selectedSessionForHierarchy?.id)
    }
    
    // MARK: - Phases Column with Back Button (when phase is selected)
    private func phasesColumnWithBack(for program: Program) -> some View {
        let phases = dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedPhaseForHierarchy = nil
                        selectedSessionForHierarchy = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(program.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(hex: program.colorHex))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { showingAddPhase = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: program.colorHex).opacity(0.08))
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(phases) { phase in
                        MacPhaseListRow(
                            phase: phase,
                            sessionCount: dataManager.sessionEvents.filter { $0.microCycleId == phase.id }.count,
                            accentColor: Color(hex: program.colorHex),
                            isSelected: selectedPhaseForHierarchy?.id == phase.id,
                            onEdit: { editingPhase = phase },
                            onDelete: {
                                if selectedPhaseForHierarchy?.id == phase.id {
                                    selectedPhaseForHierarchy = nil
                                    selectedSessionForHierarchy = nil
                                }
                                let sessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
                                for session in sessions { dataManager.deleteSessionEvent(session) }
                                dataManager.deleteMicroCycle(phase)
                            }
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPhaseForHierarchy = phase
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Phase Detail Column
    private func phaseDetailColumn(for phase: MicroCycle, program: Program) -> some View {
        let programColor = Color(hex: program.colorHex)
        let sessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Phase header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(programColor.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text("\(phase.phaseNumber)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("\(phase.durationWeeks) weeks · \(sessions.count) sessions")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { editingPhase = phase }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Focus areas
                if !phase.focus.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Focus Areas")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(phase.focus, id: \.self) { focus in
                                HStack(spacing: 4) {
                                    Image(systemName: focus.icon)
                                        .font(.system(size: 10))
                                    Text(focus.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(programColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(programColor.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Intensity
                VStack(alignment: .leading, spacing: 10) {
                    Text("Intensity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    HStack(spacing: 3) {
                        ForEach(1...10, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i <= phase.intensity ? programColor : Color.gray.opacity(0.2))
                                .frame(width: 16, height: 20)
                        }
                        Spacer()
                        Text("\(phase.intensity)/10")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Description
                if let description = phase.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Programs Column
    private var programsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Text("Programs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(dataManager.programs.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if dataManager.programs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                            Text("No Programs")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            Button("Create Program") {
                                showingAddProgram = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(dataManager.programs) { program in
                            MacProgramListRow(
                                program: program,
                                phaseCount: dataManager.microCycles.filter { $0.programId == program.id }.count,
                                sessionCount: dataManager.sessionEvents.filter { $0.programId == program.id }.count,
                                isSelected: selectedProgramForHierarchy?.id == program.id,
                                onEdit: { editingProgram = program },
                                onDelete: {
                                    // Delete all phases and sessions first
                                    let phases = dataManager.microCycles.filter { $0.programId == program.id }
                                    for phase in phases {
                                        let sessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
                                        for session in sessions {
                                            dataManager.deleteSessionEvent(session)
                                        }
                                        dataManager.deleteMicroCycle(phase)
                                    }
                                    // Clear selection if this program was selected
                                    if selectedProgramForHierarchy?.id == program.id {
                                        selectedProgramForHierarchy = nil
                                        selectedPhaseForHierarchy = nil
                                        selectedSessionForHierarchy = nil
                                    }
                                    dataManager.deleteProgram(program)
                                }
                            ) {
                                debugLog("🔵 Program tapped: \(program.name)")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedProgramForHierarchy = program
                                    selectedPhaseForHierarchy = nil
                                    selectedSessionForHierarchy = nil
                                }
                                debugLog("🔵 After tap - Program: \(selectedProgramForHierarchy?.name ?? "nil"), Phase: \(selectedPhaseForHierarchy?.title ?? "nil")")
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Phases Column
    private func phasesColumn(for program: Program) -> some View {
        let phases = dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(Color(hex: program.colorHex))
                    .frame(width: 8, height: 8)
                Text("Phases")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(phases.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                
                Button(action: { showingAddPhase = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: program.colorHex).opacity(0.08))
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if phases.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 28))
                                .foregroundColor(Color(hex: program.colorHex).opacity(0.5))
                            Text("No Phases")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            Text("Add training phases to structure your program")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                                .multilineTextAlignment(.center)
                            Button("Add Phase") { showingAddPhase = true }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(phases) { phase in
                            MacPhaseListRow(
                                phase: phase,
                                sessionCount: dataManager.sessionEvents.filter { $0.microCycleId == phase.id }.count,
                                accentColor: Color(hex: program.colorHex),
                                isSelected: selectedPhaseForHierarchy?.id == phase.id,
                                onEdit: { editingPhase = phase },
                                onDelete: {
                                    // Delete all sessions in this phase first
                                    let sessions = dataManager.sessionEvents.filter { $0.microCycleId == phase.id }
                                    for session in sessions {
                                        dataManager.deleteSessionEvent(session)
                                    }
                                    // Clear selection if this phase was selected
                                    if selectedPhaseForHierarchy?.id == phase.id {
                                        selectedPhaseForHierarchy = nil
                                        selectedSessionForHierarchy = nil
                                    }
                                    dataManager.deleteMicroCycle(phase)
                                }
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedPhaseForHierarchy = phase
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Sessions Column (for a phase)
    private func sessionsColumn(for phase: MicroCycle, program: Program) -> some View {
        let sessions = dataManager.sessionEvents
            .filter { $0.microCycleId == phase.id }
            .sorted { $0.date < $1.date }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phase \(phase.phaseNumber): \(phase.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(sessions.count) sessions · \(phase.durationWeeks) weeks")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                Spacer()
                Button(action: { editingPhase = phase }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                Button(action: { showingAddSession = true }) {
                    Label("Add Session", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: program.colorHex))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: program.colorHex).opacity(0.05))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Phase info card
                    phaseInfoCard(phase: phase, program: program)
                    
                    // Sessions list
                    if sessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(Color(hex: program.colorHex).opacity(0.5))
                            Text("No Sessions")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            Text("Create sessions for this phase")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                            Button("Add Session") { showingAddSession = true }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sessions) { session in
                                MacPhaseSessionRow(
                                    session: session,
                                    accentColor: Color(hex: program.colorHex),
                                    isSelected: selectedSessionForHierarchy?.id == session.id,
                                    onEdit: { editingSession = session },
                                    onDelete: {
                                        // Clear selection if this session was selected
                                        if selectedSessionForHierarchy?.id == session.id {
                                            selectedSessionForHierarchy = nil
                                        }
                                        dataManager.deleteSessionEvent(session)
                                    }
                                ) {
                                    // Session tap action - Finder-style column selection
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedSessionForHierarchy = session
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Session Detail Column (Finder-style slide-in)
    private func sessionDetailColumn(for session: SessionEvent, program: Program) -> some View {
        let programColor = Color(hex: program.colorHex)
        let attendees = dataManager.students.filter { session.attendeeIds.contains($0.id) }
        
        return VStack(alignment: .leading, spacing: 0) {
            // Column header with back button
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedSessionForHierarchy = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(programColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { editingSession = session }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedSessionForHierarchy = nil
                    }
                    dataManager.deleteSessionEvent(session)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(programColor.opacity(0.05))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Session header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: session.sessionType.icon)
                                .font(.system(size: 24))
                                .foregroundColor(programColor)
                                .frame(width: 44, height: 44)
                                .background(programColor.opacity(0.1))
                                .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text(session.sessionType.displayName)
                                    .font(.system(size: 12))
                                    .foregroundColor(programColor)
                            }
                            
                            Spacer()
                            
                            // Status badge
                            Text(session.status.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(session.status == .completed ? .green : .blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((session.status == .completed ? Color.green : Color.blue).opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Schedule info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(session.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(.system(size: 12, weight: .medium))
                                Label("\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(session.durationMinutes)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(programColor)
                                Text("minutes")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        
                        if let location = session.location {
                            Label(location, systemImage: "mappin.circle")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Curriculum sections (Warmup, Skills, Game) - matching iOS
                    curriculumSectionCard(
                        title: "Warmup",
                        icon: "flame",
                        color: .orange,
                        minutes: session.curriculum.warmupMinutes,
                        drillIds: session.curriculum.warmupDrillIds,
                        allDrills: dataManager.drills
                    )
                    
                    curriculumSectionCard(
                        title: "Skills",
                        icon: "figure.basketball",
                        color: .blue,
                        minutes: session.curriculum.skillsMinutes,
                        drillIds: session.curriculum.skillDrillIds,
                        allDrills: dataManager.drills
                    )
                    
                    curriculumSectionCard(
                        title: "Game",
                        icon: "sportscourt",
                        color: .green,
                        minutes: session.curriculum.gameMinutes,
                        drillIds: session.curriculum.gameDrillIds,
                        allDrills: dataManager.drills
                    )
                    
                    // Attendees section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Attendees")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("\(attendees.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                        
                        if attendees.isEmpty {
                            HStack {
                                Image(systemName: "person.3")
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No attendees assigned")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                                ForEach(attendees) { student in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.avatarColor(student.avatarColor))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Text(student.initials)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.white)
                                            )
                                        Text(student.name.components(separatedBy: " ").first ?? student.name)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Notes section
                    if let notes = session.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Curriculum Section Card (for session detail)
    private func curriculumSectionCard(title: String, icon: String, color: Color, minutes: Int, drillIds: [UUID], allDrills: [DrillItem]) -> some View {
        let sectionDrills = allDrills.filter { drillIds.contains($0.id) }
        
        return VStack(alignment: .leading, spacing: 10) {
            // Header row with icon, title, and duration
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                Text("\(minutes) min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12))
                    .cornerRadius(6)
            }
            
            // Drills list or empty state
            if sectionDrills.isEmpty {
                HStack {
                    Text("No drills assigned")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(sectionDrills) { drill in
                        HStack(spacing: 10) {
                            Image(systemName: drill.category.icon)
                                .font(.system(size: 11))
                                .foregroundColor(color)
                                .frame(width: 24, height: 24)
                                .background(color.opacity(0.12))
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(drill.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("\(drill.durationMinutes) min")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Program Overview Column (when no phase selected)
    private func programOverviewColumn(for program: Program) -> some View {
        let phases = dataManager.microCycles.filter { $0.programId == program.id }.sorted { $0.phaseNumber < $1.phaseNumber }
        let sessions = dataManager.sessionEvents.filter { $0.programId == program.id }
        let enrolledStudents = dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
        let programColor = Color(hex: program.colorHex)
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // DEBUG: Visible indicator
                Text("PROGRAM DETAIL")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(8)
                
                // Program header
                programOverviewHeader(program: program, programColor: programColor)
                
                // Stats row
                programOverviewStats(program: program, phases: phases, sessions: sessions, enrolledStudents: enrolledStudents)
                
                // Schedule info (matching iOS)
                if !program.recurringDays.isEmpty || program.defaultSessionTime != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        HStack(spacing: 16) {
                            if !program.recurringDays.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 12))
                                        .foregroundColor(programColor)
                                    Text(program.recurringDays.map { $0.shortName }.joined(separator: ", "))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                            
                            if let time = program.defaultSessionTime {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 12))
                                        .foregroundColor(programColor)
                                    Text(time.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(.system(size: 12))
                                    .foregroundColor(programColor)
                                Text("\(program.defaultSessionDurationMinutes) min")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                        }
                        
                        if let locationName = program.locationName {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(programColor)
                                Text(locationName)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Description
                if let description = program.description, !description.isEmpty {
                    programDescriptionCard(description: description)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Objectives
                if !program.objectives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Objectives")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        FlowLayout(spacing: 8) {
                            ForEach(program.objectives, id: \.self) { objective in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text(objective)
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Enrolled athletes
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Enrolled Athletes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text("\(enrolledStudents.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    if enrolledStudents.isEmpty {
                        Text("No athletes enrolled")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(enrolledStudents) { student in
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.avatarColor(student.avatarColor))
                                                .frame(width: 44, height: 44)
                                            Text(student.initials)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text(student.name.split(separator: " ").first.map(String.init) ?? student.name)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Quick action: Select a phase
                if !phases.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select a Phase")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Choose a phase from the middle column to view its sessions")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: program.colorHex).opacity(0.08))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 320, idealWidth: 400, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func programOverviewHeader(program: Program, programColor: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(programColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: program.mascot.icon)
                    .font(.system(size: 28))
                    .foregroundColor(programColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(program.mascot.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(programColor)
                Text(program.name)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                HStack(spacing: 8) {
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(programColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(programColor.opacity(0.12))
                        .cornerRadius(6)
                    Text(program.status.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(program.isActive ? .green : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((program.isActive ? Color.green : Color.gray).opacity(0.12))
                        .cornerRadius(6)
                }
            }
            
            Spacer()
            
            Button(action: { editingProgram = program }) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(programColor.opacity(0.05)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(programColor.opacity(0.2), lineWidth: 1))
    }
    
    private func programOverviewStats(program: Program, phases: [MicroCycle], sessions: [SessionEvent], enrolledStudents: [Student]) -> some View {
        HStack(spacing: 16) {
            programStatCard(value: "\(program.durationWeeks)", label: "Weeks", icon: "calendar", color: .blue)
            programStatCard(value: "\(phases.count)", label: "Phases", icon: "square.stack.3d.up", color: .purple)
            programStatCard(value: "\(sessions.count)", label: "Sessions", icon: "clock", color: .orange)
            programStatCard(value: "\(enrolledStudents.count)", label: "Athletes", icon: "person.2", color: .green)
        }
    }
    
    private func programDescriptionCard(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func programStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func phaseInfoCard(phase: MicroCycle, program: Program) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Focus areas
            if !phase.focus.isEmpty {
                HStack(spacing: 6) {
                    ForEach(phase.focus.prefix(4), id: \.self) { focus in
                        HStack(spacing: 4) {
                            Image(systemName: focus.icon)
                                .font(.system(size: 10))
                            Text(focus.displayName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: program.colorHex))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: program.colorHex).opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            // Intensity
            HStack {
                Text("Intensity")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i <= phase.intensity ? Color.orange : Color.gray.opacity(0.2))
                            .frame(width: 8, height: 12)
                    }
                }
            }
            
            if let description = phase.description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Sessions Calendar View
    private var sessionsCalendarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Upcoming Sessions
                VStack(alignment: .leading, spacing: 16) {
                    Label("Upcoming Sessions", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    let upcoming = dataManager.sessionEvents
                        .filter { $0.date >= Date() }
                        .sorted { $0.date < $1.date }
                    
                    if upcoming.isEmpty {
                        MacEmptyStateCard(
                            icon: "calendar.badge.plus",
                            title: "No Upcoming Sessions",
                            subtitle: "Sessions are created within program phases",
                            color: .orange
                        )
                    } else {
                        ForEach(Array(upcoming.prefix(10).enumerated()), id: \.element.id) { _, session in
                            MacSessionCard(session: session, isSelected: selectedSession?.id == session.id) {
                                selectedSession = session
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Past Sessions
                VStack(alignment: .leading, spacing: 16) {
                    Label("Past Sessions", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    let past = dataManager.sessionEvents
                        .filter { $0.date < Date() }
                        .sorted { $0.date > $1.date }
                    
                    if past.isEmpty {
                        Text("No past sessions")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    } else {
                        ForEach(Array(past.prefix(5).enumerated()), id: \.element.id) { _, session in
                            MacSessionCard(session: session, isSelected: selectedSession?.id == session.id, isPast: true) {
                                selectedSession = session
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - League Content (Full-featured like iOS)
    private var leagueContentList: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Competition & Stats")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("League")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                // Action buttons
                Button(action: { showingScheduleGame = true }) {
                    Label("Schedule Game", systemImage: "calendar.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                Button(action: { showingCreateTeam = true }) {
                    Label("New Team", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentColor)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Tab selector
            leagueTabSelector
            
            Divider()
            
            // Tab content
            ScrollView {
                switch leagueTab {
                case .games:
                    leagueGamesContent
                case .teams:
                    leagueTeamsContent
                case .standings:
                    leagueStandingsContent
                case .stats:
                    leagueStatsContent
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - League Tab Selector
    private var leagueTabSelector: some View {
        HStack(spacing: 8) {
            ForEach(MacLeagueTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        leagueTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(leagueTab == tab ? AppTheme.accentColor : Color(NSColor.controlBackgroundColor))
                    )
                    .foregroundColor(leagueTab == tab ? .white : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
    
    // MARK: - League Games Content
    private var leagueGamesContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Live Games
            if !liveGames.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("LIVE").font(.system(size: 12, weight: .bold)).foregroundColor(.red)
                    }
                    
                    ForEach(liveGames) { game in
                        MacLiveGameCard(game: game, dataManager: dataManager) {
                            selectedGame = game
                        }
                    }
                }
            }
            
            // Today's Games
            if !todayGames.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    ForEach(todayGames) { game in
                        MacGameRow(game: game, dataManager: dataManager) {
                            selectedGame = game
                        }
                    }
                }
            }
            
            // Upcoming Games
            if !leagueUpcomingGames.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    ForEach(leagueUpcomingGames) { game in
                        MacGameRow(game: game, dataManager: dataManager) {
                            selectedGame = game
                        }
                    }
                }
            }
            
            // Recent Results
            if !recentFinishedGames.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Results")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    ForEach(recentFinishedGames) { game in
                        MacGameRow(game: game, dataManager: dataManager) {
                            selectedGame = game
                        }
                    }
                }
            }
            
            // Empty state
            if dataManager.games.isEmpty {
                leagueEmptyGamesState
            }
        }
        .padding(24)
    }
    
    // MARK: - League Teams Content
    private var leagueTeamsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dataManager.teams.isEmpty {
                leagueEmptyTeamsState
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(dataManager.teams) { team in
                        MacLeagueTeamCard(team: team, dataManager: dataManager) {
                            selectedTeam = team
                        }
                    }
                }
            }
        }
        .padding(24)
    }
    
    // MARK: - League Standings Content
    private var leagueStandingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dataManager.teams.isEmpty {
                leagueEmptyTeamsState
            } else {
                MacStandingsTable(teams: dataManager.teams, games: dataManager.games)
            }
        }
        .padding(24)
    }
    
    // MARK: - League Stats Content
    private var leagueStatsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if dataManager.seasonStats.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No Stats Yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Play some games to see player stats")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                // Stats in a grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    MacStatLeaderCard(title: "Points", stat: "PPG", leaders: pointsLeaders, dataManager: dataManager)
                    MacStatLeaderCard(title: "Rebounds", stat: "RPG", leaders: reboundsLeaders, dataManager: dataManager)
                    MacStatLeaderCard(title: "Assists", stat: "APG", leaders: assistsLeaders, dataManager: dataManager)
                    MacStatLeaderCard(title: "Steals", stat: "SPG", leaders: stealsLeaders, dataManager: dataManager)
                }
            }
        }
        .padding(24)
    }
    
    // MARK: - League Empty States
    private var leagueEmptyGamesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sportscourt")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            Text("No Games Scheduled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Text("Schedule your first game to get started")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            Button(action: { showingScheduleGame = true }) {
                Label("Schedule Game", systemImage: "calendar.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var leagueEmptyTeamsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            Text("No Teams Yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Text("Create teams from your students")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            Button(action: { showingCreateTeam = true }) {
                Label("Create Team", systemImage: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - League Computed Properties
    private var liveGames: [Game] {
        dataManager.games.filter { $0.status == .live }
    }
    
    private var leagueTodayGames: [Game] {
        let calendar = Calendar.current
        return dataManager.games.filter {
            calendar.isDateInToday($0.date) && $0.status != .live && $0.status != .finished
        }
    }
    
    private var leagueUpcomingGames: [Game] {
        dataManager.games.filter {
            $0.status == .scheduled && $0.date > Date() && !Calendar.current.isDateInToday($0.date)
        }.sorted { $0.date < $1.date }.prefix(10).map { $0 }
    }
    
    private var recentFinishedGames: [Game] {
        dataManager.games.filter { $0.status == .finished }
            .sorted { $0.date > $1.date }
            .prefix(5).map { $0 }
    }
    
    // Stats leaders helpers
    private func student(for playerId: UUID) -> Student? {
        guard let player = dataManager.players.first(where: { $0.id == playerId }) else { return nil }
        return dataManager.students.first(where: { $0.id == player.studentId })
    }
    
    private var pointsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.ppg > 0 }
            .sorted { $0.ppg > $1.ppg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.ppg)
            }
    }
    
    private var reboundsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.rpg > 0 }
            .sorted { $0.rpg > $1.rpg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.rpg)
            }
    }
    
    private var assistsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.apg > 0 }
            .sorted { $0.apg > $1.apg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.apg)
            }
    }
    
    private var stealsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.spg > 0 }
            .sorted { $0.spg > $1.spg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.spg)
            }
    }
    
    // MARK: - Hub Content (Flighty Style)
    private var hubContentList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with actions - Flighty style
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Athletes & Resources")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Hub")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    // Search Field - frosted glass
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        TextField("Search athletes...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                    .frame(width: 160)
                    
                    Button(action: { showingAddStudent = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("Add Athlete")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Monthly Earnings Card
                hubEarningsCard
                
                // Quick Stats Row
                hubQuickStats
                
                // Navigation Sections - Flighty cards
                VStack(spacing: 8) {
                    FlightyHubNavCard(icon: "person.2.fill", title: "Students", subtitle: "\(dataManager.students.count) athletes", color: .blue) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingStudentsOverlay = true
                        }
                    }
                    FlightyHubNavCard(icon: "doc.text.fill", title: "Contracts", subtitle: "\(dataManager.contracts.filter { $0.status == .active }.count) active", color: .green) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingContractsOverlay = true
                        }
                    }
                    FlightyHubNavCard(icon: "sportscourt.fill", title: "Coach", subtitle: "\(dataManager.drills.count) drills · \(dataManager.plays.count) plays", color: .orange) {
                        showingCoachLibrary = true
                    }
                    FlightyHubNavCard(icon: "building.2.fill", title: "Organization", subtitle: "\(dataManager.staffCoaches.count) coaches · \(dataManager.locations.count) venues", color: .teal) {
                        showingOrganization = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(hex: "#f5f5f7"))
    }
    
    // MARK: - Hub Earnings Card (Flighty Style)
    private var hubEarningsCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("\(currentMonthName) Earnings")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    Text(monthlyEarnings, format: .currency(code: "USD"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(newContractsThisMonth)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("new contracts")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Hub Quick Stats (Flighty Style)
    private var hubQuickStats: some View {
        HStack(spacing: 8) {
            FlightyMiniStatPill(value: "\(dataManager.students.count)", label: "Students", color: .blue)
            FlightyMiniStatPill(value: "\(dataManager.contracts.filter { $0.status == .active }.count)", label: "Active", color: .green)
            FlightyMiniStatPill(value: "\(dataManager.sessionEvents.filter { $0.isUpcoming }.count)", label: "Upcoming", color: .orange)
        }
        .padding(.horizontal, 20)
    }
    
    // Hub computed properties
    private var currentMonthName: String { Date().formatted(.dateTime.month(.wide)) }
    
    private var monthlyEarnings: Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return dataManager.contracts.filter { $0.createdAt >= startOfMonth }.reduce(0) { $0 + $1.amountPaid }
    }
    
    private var newContractsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return dataManager.contracts.filter { $0.createdAt >= startOfMonth }.count
    }
    
    private var filteredStudents: [Student] {
        if searchText.isEmpty { return dataManager.students }
        return dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        if let student = selectedStudent {
            StudentDetailView(student: student)
        } else if let program = selectedProgram {
            ProgramDetailView(program: program)
        } else if let session = selectedSession {
            SessionDetailView(session: session)
        } else {
            // Elegant Empty State
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentColor.opacity(0.1), AppTheme.accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accentColor, AppTheme.accentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 8) {
                    Text("Select an Item")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text("Choose an athlete, program, or session\nfrom the list to view details")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - Elegant Mac Components

/// Sidebar navigation item with hover effect
struct MacSidebarItem: View {
    let tab: MacContentView.MacTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AnyShapeStyle(tab.gradient) : AnyShapeStyle(Color.clear))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: tab.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                }
                
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(NSColor.controlBackgroundColor) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Compact stat card for sidebar
struct MacStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// Empty state card with icon
struct MacEmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

/// Student card with hover effect and league stats
struct MacStudentCard: View {
    let student: Student
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var dataManager: DataManager
    
    @State private var isHovered = false
    
    /// Teams this student is on
    private var teams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(student.id) }
    }
    
    /// Primary team
    private var primaryTeam: Team? {
        teams.first
    }
    
    /// Player record for this student
    private var player: Player? {
        dataManager.player(for: student.id)
    }
    
    /// Season stats for this player
    private var seasonStats: SeasonStats? {
        guard let player = player else { return nil }
        return dataManager.seasonStats.first { $0.playerId == player.id }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar with team color ring
                ZStack {
                    if let team = primaryTeam {
                        Circle()
                            .stroke(team.primaryColor, lineWidth: 2)
                            .frame(width: 48, height: 48)
                    }
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 44, height: 44)
                    Text(student.initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(student.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        // Team badge
                        if let team = primaryTeam {
                            HStack(spacing: 3) {
                                Circle().fill(team.primaryColor).frame(width: 5, height: 5)
                                Text(team.shortName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(team.primaryColor)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(team.primaryColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        
                        // PPG inline
                        if let stats = seasonStats, stats.gamesPlayed > 0 {
                            Text(String(format: "%.1f PPG", stats.ppg))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let age = student.age {
                            Text("\(age) yrs")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        // Full stats row if on a team
                        if let stats = seasonStats, stats.gamesPlayed > 0 {
                            Text("•").foregroundColor(AppTheme.textTertiary)
                            HStack(spacing: 6) {
                                Text(String(format: "%.1f RPG", stats.rpg))
                                Text(String(format: "%.1f APG", stats.apg))
                                Text("\(stats.gamesPlayed) GP")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppTheme.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
            .shadow(color: isHovered ? Color.black.opacity(0.05) : Color.clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Session card with time indicator
struct MacSessionCard: View {
    let session: SessionEvent
    let isSelected: Bool
    var isPast: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Time Block
                VStack(spacing: 2) {
                    Text(session.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(isPast ? AppTheme.textTertiary : AppTheme.accentColor)
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(width: 56)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPast ? Color(NSColor.controlBackgroundColor) : AppTheme.accentColor.opacity(0.1))
                )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isPast ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let location = session.location {
                            Label(location, systemImage: "mappin")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Status indicator
                if !isPast {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppTheme.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
            .opacity(isPast ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Program card with mascot
struct MacProgramCard: View {
    let program: Program
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Mascot Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [program.mascotColor, program.mascotColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(program.mascot.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        if program.isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Label("\(program.enrolledStudentIds.count)", systemImage: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        Label(program.ageGroup.displayName, systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? AppTheme.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Team card
struct MacTeamCard: View {
    let team: Team
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Team Logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [team.primaryColor, team.primaryColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: team.logoSystemImage)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text(team.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(team.playerCount) players")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? AppTheme.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Game card with score
struct MacGameCard: View {
    let game: Game
    let dataManager: DataManager
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Home Team
            HStack(spacing: 12) {
                if let home = homeTeam {
                    Circle()
                        .fill(home.primaryColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: home.logoSystemImage)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    Text(home.shortName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // Score
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(game.homeScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text("-")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text("\(game.awayScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Text(game.status == .live ? "LIVE" : game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(game.status == .live ? .green : AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(game.status == .live ? Color.green.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
            }
            .frame(width: 100)
            
            // Away Team
            HStack(spacing: 12) {
                Spacer()
                
                if let away = awayTeam {
                    Text(away.shortName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Circle()
                        .fill(away.primaryColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: away.logoSystemImage)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(14)
    }
}

// MARK: - Hub Navigation Card
struct MacHubNavCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(color.gradient)
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(AppTheme.textPrimary)
                    Text(subtitle).font(.system(size: 13)).foregroundColor(AppTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Mini Stat Pill
struct MacMiniStatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Flighty Hub Nav Card
struct FlightyHubNavCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray.opacity(isHovered ? 0.6 : 0.3))
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Flighty Mini Stat Pill
struct FlightyMiniStatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }
}

// MARK: - Action Item Model
struct MacActionItem: Identifiable {
    let id = UUID()
    let type: MacActionItemType
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let urgency: String?
    let actionLabel: String
}

enum MacActionItemType {
    case student(Student)
    case program(Program)
    case session(SessionEvent)
    case contract(Student, Contract)
}

// MARK: - Quick Stat Component
struct MacQuickStat: View {
    let icon: String
    let value: String
    let label: String
    var detail: String?
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    if let detail = detail {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Dashboard Game Card
struct MacDashboardGameCard: View {
    let game: Game
    let dataManager: DataManager
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        VStack(spacing: 12) {
            // Status header
            HStack {
                if game.status == .live {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                    }
                } else {
                    Text(gameTimeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            }
            
            // Teams and score
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    Circle()
                        .fill(awayTeam?.primaryColor ?? .gray)
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: awayTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                if game.status == .live || game.status == .finished {
                    HStack(spacing: 8) {
                        Text("\(game.awayScore)").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("-").font(.system(size: 16)).foregroundColor(AppTheme.textTertiary)
                        Text("\(game.homeScore)").font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(AppTheme.textPrimary)
                } else {
                    Text(game.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                VStack(spacing: 6) {
                    Circle()
                        .fill(homeTeam?.primaryColor ?? .gray)
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: homeTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    private var gameTimeLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(game.date) { return "Today • \(game.date.formatted(date: .omitted, time: .shortened))" }
        else if calendar.isDateInTomorrow(game.date) { return "Tomorrow • \(game.date.formatted(date: .omitted, time: .shortened))" }
        else { return game.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    }
}

// MARK: - Upcoming Session Card
struct MacUpcomingCard: View {
    let session: SessionEvent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    VStack(spacing: 0) {
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(session.date.formatted(.dateTime.day()))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Spacer()
                }
                
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                
                Text(session.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(width: 120)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Item Row
struct MacActionItemRow: View {
    let item: MacActionItem
    let dataManager: DataManager
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if item.urgency != nil {
                    RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 3, height: 36)
                }
                
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(item.iconColor)
                    .frame(width: 32, height: 32)
                    .background(item.iconColor.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        if let badge = item.urgency {
                            Text(badge.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(item.actionLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(item.iconColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(item.iconColor.opacity(0.08))
                    .cornerRadius(8)
            }
            .padding(.horizontal, item.urgency != nil ? 8 : 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Dashboard Stat Card
struct MacDashboardStatCard: View {
    let icon: String
    let value: String
    let label: String
    var subtitle: String?
    let color: Color
    var progress: Double?  // 0.0 to 1.0 for progress bar
    var trend: String?     // e.g., "+5" or "-2"
    var badge: String?     // Small badge indicator
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: Icon + Badge/Trend
                HStack(alignment: .top) {
                    // Icon with gradient background
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.2), color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Spacer()
                    
                    // Trend indicator or badge
                    if let trend = trend {
                        HStack(spacing: 2) {
                            Image(systemName: trend.hasPrefix("+") ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(trend)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(trend.hasPrefix("+") ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(trend.hasPrefix("+") ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        )
                    } else if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Circle().fill(color))
                    }
                }
                
                Spacer().frame(height: 12)
                
                // Value - large and prominent
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer().frame(height: 4)
                
                // Label
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                
                // Progress bar (if provided)
                if let progress = progress {
                    Spacer().frame(height: 10)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.15))
                                .frame(height: 6)
                            
                            // Progress fill with gradient
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [color, color.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                
                // Subtitle (below progress if exists)
                if let subtitle = subtitle {
                    Spacer().frame(height: progress != nil ? 6 : 2)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isHovered ? color.opacity(0.08) : Color.white.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovered ? color.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: isHovered ? color.opacity(0.15) : .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Compact Game Row
struct MacCompactGameRow: View {
    let game: Game
    let dataManager: DataManager
    let action: () -> Void
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Teams
                HStack(spacing: 6) {
                    Circle().fill(awayTeam?.primaryColor ?? .gray).frame(width: 20, height: 20)
                        .overlay(Image(systemName: awayTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                    Text(awayTeam?.shortName ?? "AWY").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textPrimary)
                    Text("@").font(.system(size: 10)).foregroundColor(AppTheme.textTertiary)
                    Text(homeTeam?.shortName ?? "HME").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textPrimary)
                    Circle().fill(homeTeam?.primaryColor ?? .gray).frame(width: 20, height: 20)
                        .overlay(Image(systemName: homeTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                }
                
                Spacer()
                
                // Time/Score
                if game.status == .live {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("\(game.awayScore)-\(game.homeScore)").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
                    }
                } else {
                    Text(game.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Session Row
struct MacCompactSessionRow: View {
    let session: SessionEvent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(session.date.formatted(.dateTime.day()))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(session.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today Session Card
struct MacTodaySessionCard: View {
    let session: SessionEvent
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Time block
                VStack(spacing: 2) {
                    Text(session.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.accentColor)
                    Text("\(session.durationMinutes)m")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(width: 50)
                
                Rectangle()
                    .fill(AppTheme.accentColor)
                    .frame(width: 3)
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if session.attendeeIds.count > 0 {
                            Label("\(session.attendeeIds.count)", systemImage: "person.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        if session.curriculum.totalDrillCount > 0 {
                            Label("\(session.curriculum.totalDrillCount) drills", systemImage: "list.bullet")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(12)
            .background(isHovered ? AppTheme.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Panel Content Views
struct MacStudentPanelContent: View {
    let student: Student
    let dataManager: DataManager
    
    var contract: Contract? { dataManager.contracts.first { $0.studentId == student.id && $0.status == .active } }
    var team: Team? { dataManager.teams.first { $0.playerIds.contains(student.id) } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Avatar and basic info
            HStack(spacing: 16) {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(Text(student.initials).font(.system(size: 22, weight: .bold)).foregroundColor(.white))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    if let team = team {
                        HStack(spacing: 4) {
                            Circle().fill(team.primaryColor).frame(width: 8, height: 8)
                            Text(team.name).font(.system(size: 12)).foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    Text("Age \(student.age)").font(.system(size: 12)).foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Divider()
            
            // Contract info
            VStack(alignment: .leading, spacing: 10) {
                Text("Contract").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textSecondary)
                if let contract = contract {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(contract.remainingSessions ?? 0)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor((contract.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary)
                            Text("sessions left").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(contract.expiryDate?.formatted(date: .abbreviated, time: .omitted) ?? "No end date")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.textSecondary)
                            Text("expires").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                } else {
                    Text("No active contract")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            
            // Quick actions
            HStack(spacing: 10) {
                Button(action: {}) {
                    Label("Message", systemImage: "message.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Label("Schedule", systemImage: "calendar.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MacSessionPanelContent: View {
    let session: SessionEvent
    let dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Session header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(session.status.rawValue.capitalized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(session.status == .scheduled ? .blue : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(session.status == .scheduled ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
                
                Text(session.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                HStack(spacing: 16) {
                    Label(session.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    Label("\(session.durationMinutes) min", systemImage: "timer")
                }
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
            }
            
            Divider()
            
            // Participants
            VStack(alignment: .leading, spacing: 10) {
                Text("Participants (\(session.attendeeIds.count))").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textSecondary)
                
                if session.attendeeIds.isEmpty {
                    Text("No participants assigned")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(session.attendeeIds.prefix(5), id: \.self) { studentId in
                            if let student = dataManager.students.first(where: { $0.id == studentId }) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 28, height: 28)
                                        .overlay(Text(student.initials).font(.system(size: 10, weight: .bold)).foregroundColor(.blue))
                                    Text(student.name).font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            
            // Curriculum
            VStack(alignment: .leading, spacing: 10) {
                Text("Curriculum").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textSecondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.curriculum.totalDrillCount)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(AppTheme.textPrimary)
                        Text("drills planned").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                    Button("Edit Plan") {}
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                        .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }
}

struct MacProgramPanelContent: View {
    let program: Program
    let dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Program header with mascot
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(program.mascotColor.gradient)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: program.mascot.icon).font(.system(size: 28, weight: .bold)).foregroundColor(.white))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.mascot.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    if program.isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            Divider()
            
            // Stats
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(program.enrolledStudentIds.count)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(AppTheme.textPrimary)
                    Text("Students").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("\(program.durationWeeks)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(AppTheme.textPrimary)
                    Text("Weeks").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
}

struct MacGamePanelContent: View {
    let game: Game
    let dataManager: DataManager
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Game header
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    // Away team
                    VStack(spacing: 8) {
                        Circle().fill(awayTeam?.primaryColor ?? .gray).frame(width: 56, height: 56)
                            .overlay(Image(systemName: awayTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 24, weight: .bold)).foregroundColor(.white))
                        Text(awayTeam?.name ?? "Away").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textPrimary)
                    }
                    
                    // Score
                    VStack(spacing: 4) {
                        if game.status == .live || game.status == .finished {
                            HStack(spacing: 12) {
                                Text("\(game.awayScore)").font(.system(size: 32, weight: .bold, design: .rounded))
                                Text("-").font(.system(size: 20)).foregroundColor(AppTheme.textTertiary)
                                Text("\(game.homeScore)").font(.system(size: 32, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        if game.status == .live {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
                            }
                        } else {
                            Text(game.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    
                    // Home team
                    VStack(spacing: 8) {
                        Circle().fill(homeTeam?.primaryColor ?? .gray).frame(width: 56, height: 56)
                            .overlay(Image(systemName: homeTeam?.logoSystemImage ?? "basketball.fill").font(.system(size: 24, weight: .bold)).foregroundColor(.white))
                        Text(homeTeam?.name ?? "Home").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(14)
            
            // Game info
            VStack(alignment: .leading, spacing: 10) {
                Text("Game Info").font(.system(size: 13, weight: .semibold)).foregroundColor(AppTheme.textSecondary)
                
                VStack(spacing: 8) {
                    HStack {
                        Label("Date", systemImage: "calendar").foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        Text(game.date.formatted(date: .abbreviated, time: .omitted)).foregroundColor(AppTheme.textPrimary)
                    }
                    HStack {
                        Label("Time", systemImage: "clock").foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        Text(game.date.formatted(date: .omitted, time: .shortened)).foregroundColor(AppTheme.textPrimary)
                    }
                    if let venue = game.venue {
                        HStack {
                            Label("Venue", systemImage: "mappin").foregroundColor(AppTheme.textTertiary)
                            Spacer()
                            Text(venue).foregroundColor(AppTheme.textPrimary)
                        }
                    }
                }
                .font(.system(size: 12))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - Dashboard Game Row (for full-width layout)
struct MacDashboardGameRow: View {
    let game: Game
    let dataManager: DataManager
    let action: () -> Void
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Away team
                HStack(spacing: 8) {
                    Circle()
                        .fill(awayTeam?.primaryColor ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: awayTeam?.logoSystemImage ?? "basketball.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                // VS or Score
                if game.status == .live {
                    HStack(spacing: 4) {
                        Text("\(game.awayScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("-")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(game.homeScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.red)
                } else if game.status == .finished {
                    HStack(spacing: 4) {
                        Text("\(game.awayScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("-")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(game.homeScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text("vs")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                // Home team
                HStack(spacing: 8) {
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Circle()
                        .fill(homeTeam?.primaryColor ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: homeTeam?.logoSystemImage ?? "basketball.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                Spacer()
                
                // Time/Status
                VStack(alignment: .trailing, spacing: 2) {
                    if game.status == .live {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }
                    } else {
                        Text(gameTimeLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    if let venue = game.venue {
                        Text(venue)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .background(isHovered ? AppTheme.accentColor.opacity(0.06) : Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var gameTimeLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(game.date) {
            return "Today \(game.date.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInTomorrow(game.date) {
            return "Tomorrow \(game.date.formatted(date: .omitted, time: .shortened))"
        } else {
            return game.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}

// MARK: - Dashboard Session Row (for full-width layout)
struct MacDashboardSessionRow: View {
    let session: SessionEvent
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Date block
                VStack(spacing: 2) {
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(session.date.formatted(.dateTime.day()))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                .frame(width: 40)
                
                // Accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accentColor)
                    .frame(width: 3, height: 36)
                
                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Label(session.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        Label("\(session.durationMinutes)m", systemImage: "timer")
                        if session.attendeeIds.count > 0 {
                            Label("\(session.attendeeIds.count)", systemImage: "person.fill")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(10)
            .background(isHovered ? AppTheme.accentColor.opacity(0.06) : Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Program List Row (for hierarchy view)
struct MacProgramListRow: View {
    let program: Program
    let phaseCount: Int
    let sessionCount: Int
    let isSelected: Bool
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Mascot icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: program.colorHex).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: program.colorHex))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.mascot.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: program.colorHex) : AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("\(phaseCount) phase\(phaseCount == 1 ? "" : "s")")
                        if sessionCount > 0 {
                            Text("·")
                            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                // Action buttons (show on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if onDelete != nil {
                            Button(action: { showingDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Status indicator
                Circle()
                    .fill(program.isActive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(hex: program.colorHex).opacity(0.12) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(hex: program.colorHex).opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .alert("Delete Program?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(program.mascot.displayName)\"? This will also delete all phases and sessions in this program.")
        }
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
    }
}

// MARK: - Phase List Row (for hierarchy view)
struct MacPhaseListRow: View {
    let phase: MicroCycle
    let sessionCount: Int
    let accentColor: Color
    let isSelected: Bool
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Phase number badge
                Text("\(phase.phaseNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? accentColor : accentColor.opacity(0.15))
                    )
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(phase.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? accentColor : AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text("\(phase.durationWeeks)w")
                        Text("·")
                        Text("\(sessionCount) sessions")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                // Action buttons (show on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if onDelete != nil {
                            Button(action: { showingDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Intensity dots
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Circle()
                            .fill(i <= phase.intensity / 2 ? Color.orange : Color.gray.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor.opacity(0.1) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
        .alert("Delete Phase?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(phase.title)\"? This will also delete all sessions in this phase.")
        }
    }
}

// MARK: - Phase Session Row (for sessions in a phase)
struct MacPhaseSessionRow: View {
    let session: SessionEvent
    let accentColor: Color
    var isSelected: Bool = false
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Date block
                VStack(spacing: 1) {
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(session.date.formatted(.dateTime.day()))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(session.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(width: 36)
                
                // Accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: 40)
                
                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 10) {
                        Label(session.startTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        Label("\(session.durationMinutes)m", systemImage: "timer")
                        if session.attendeeIds.count > 0 {
                            Label("\(session.attendeeIds.count)", systemImage: "person.fill")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                // Action buttons
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accentColor)
                } else if isHovered {
                    HStack(spacing: 4) {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if onDelete != nil {
                            Button(action: { showingDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Status badge
                Text(session.status.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(session.status == .completed ? .green : (session.status == .scheduled ? .blue : .gray))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((session.status == .completed ? Color.green : (session.status == .scheduled ? Color.blue : Color.gray)).opacity(0.12))
                    .cornerRadius(4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentColor.opacity(0.12) : (isHovered ? accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accentColor.opacity(0.3) : (isHovered ? accentColor.opacity(0.2) : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .alert("Delete Session?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(session.title)\"? This action cannot be undone.")
        }
    }
}

// MARK: - Glass Button Style
struct MacGlassButtonStyle: ButtonStyle {
    var color: Color = .blue
    var isDestructive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isDestructive ? .red : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((isDestructive ? Color.red : color).opacity(configuration.isPressed ? 0.2 : 0.1))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke((isDestructive ? Color.red : color).opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Glass Picker Style Component
struct MacGlassPicker<T: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selection: T
    let options: [T]
    let displayName: (T) -> String
    var color: Color = .blue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: { selection = option }) {
                        HStack {
                            Text(displayName(option))
                            if selection == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(displayName(selection))
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.05)))
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Glass Text Field
struct MacGlassTextField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var placeholder: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        }
    }
}

// MARK: - Add Program Sheet
struct AddProgramSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedMascot: ProgramMascot = .tiger
    @State private var selectedAgeGroup: AgeGroup = .u12
    @State private var durationWeeks = 8
    @State private var description = ""
    @State private var enrolledStudentIds: Set<UUID> = []
    @State private var selectedCoachId: UUID? = nil
    @State private var selectedTab = 0
    
    // Schedule state
    @State private var selectedRecurringDays: Set<Weekday> = []
    @State private var hasDefaultTime = false
    @State private var defaultSessionTime = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var sessionDurationMinutes = 90
    @State private var selectedLocationId: UUID? = nil
    
    // AI Assistant state
    @State private var aiPrompt = ""
    @State private var isAIProcessing = false
    @State private var aiSuggestion: AIProgramSuggestion? = nil
    @State private var aiErrorMessage: String? = nil
    @State private var suggestedPhases: [AIPhaseSuggestionFromProgram] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Glass Header
            sheetHeader
            
            // Tab Selector
            HStack(spacing: 0) {
                tabButton(title: "AI Assistant", icon: "sparkles", index: 0)
                tabButton(title: "Details", icon: "info.circle", index: 1)
                tabButton(title: "Students", icon: "person.3", index: 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == 0 {
                        aiAssistantTab
                    } else if selectedTab == 1 {
                        detailsTab
                    } else {
                        studentsTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - AI Assistant Tab
    private var aiAssistantTab: some View {
        VStack(spacing: 16) {
            // AI Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Program Assistant")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Describe your program idea and let AI help you create it")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            
            // Prompt Input
            VStack(alignment: .leading, spacing: 8) {
                Label("Describe your program", systemImage: "text.bubble")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $aiPrompt)
                    .font(.system(size: 14))
                    .frame(height: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.3), lineWidth: 1))
                
                Text("e.g., \"8-week youth basketball program for U12 focusing on fundamentals and teamwork\"")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Generate Button
            Button(action: generateAISuggestion) {
                HStack(spacing: 8) {
                    if isAIProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAIProcessing ? "Generating..." : "Generate Program")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)
            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIProcessing)
            .opacity(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            
            // Error Message
            if let error = aiErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
            
            // AI Suggestion Preview
            if let suggestion = aiSuggestion {
                aiSuggestionPreview(suggestion)
            }
        }
    }
    
    private func aiSuggestionPreview(_ suggestion: AIProgramSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Suggestion")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Apply") {
                    applyAISuggestion(suggestion)
                }
                .buttonStyle(MacGlassButtonStyle(color: .green))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(suggestion.name)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text("\(suggestion.durationWeeks) weeks")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                }
                
                Text(suggestion.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                // Objectives
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objectives:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    ForEach(suggestion.objectives.prefix(3), id: \.self) { obj in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(obj)
                                .font(.system(size: 11))
                        }
                    }
                }
                
                // Phases Preview
                if !suggestion.phases.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested Phases:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        ForEach(suggestion.phases, id: \.phaseNumber) { phase in
                            HStack(spacing: 6) {
                                Text("\(phase.phaseNumber)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.purple))
                                Text(phase.title)
                                    .font(.system(size: 11))
                                Text("(\(phase.durationWeeks)w)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2), lineWidth: 1))
        }
    }
    
    private func generateAISuggestion() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        aiErrorMessage = nil
        isAIProcessing = true
        
        Task {
            do {
                debugLog("🤖 [AI] Calling refine_program with prompt: \(prompt.prefix(50))...")
                let suggestion: AIProgramSuggestion = try await SupabaseManager.shared.invokeFunction(
                    name: "refine_program",
                    body: ["prompt": prompt]
                )
                debugLog("🤖 [AI] Success! Got suggestion: \(suggestion.name)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiSuggestion = suggestion
                        isAIProcessing = false
                    }
                }
            } catch {
                debugLog("🤖 [AI] Error: \(error)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiErrorMessage = "AI service unavailable. Please fill in details manually. (\(error.localizedDescription))"
                        isAIProcessing = false
                    }
                }
            }
        }
    }
    
    private func applyAISuggestion(_ suggestion: AIProgramSuggestion) {
        debugLog("🤖 [AI] Applying suggestion: \(suggestion.name)")
        debugLog("   - Phases count: \(suggestion.phases.count)")
        for phase in suggestion.phases {
            debugLog("   - Phase \(phase.phaseNumber): \(phase.title), sessions: \(phase.sessions?.count ?? 0)")
        }
        
        description = suggestion.description
        durationWeeks = suggestion.durationWeeks
        
        // Map age group
        if let ageGroup = AgeGroup(rawValue: suggestion.ageGroup) {
            selectedAgeGroup = ageGroup
        }
        
        // Map mascot
        if let mascot = ProgramMascot(rawValue: suggestion.mascot) {
            selectedMascot = mascot
        }
        
        // Map recurring days from AI suggestion OR extract from phase sessions
        if let days = suggestion.recurringDays, !days.isEmpty {
            selectedRecurringDays = Set(days.compactMap { dayString in
                Weekday.allCases.first { $0.displayName.lowercased() == dayString.lowercased() }
            })
        } else {
            // Extract recurring days from session day of week
            var daysFromSessions: Set<Weekday> = []
            for phase in suggestion.phases {
                for session in phase.sessions ?? [] {
                    if let dayString = session.dayOfWeek,
                       let weekday = Weekday.allCases.first(where: { $0.displayName.lowercased() == dayString.lowercased() }) {
                        daysFromSessions.insert(weekday)
                    }
                }
            }
            if !daysFromSessions.isEmpty {
                selectedRecurringDays = daysFromSessions
            }
        }
        
        // Map default session time from AI suggestion
        if let timeString = suggestion.defaultSessionTime {
            let components = timeString.split(separator: ":")
            if components.count >= 2,
               let hour = Int(components[0]),
               let minute = Int(components[1]) {
                if let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) {
                    defaultSessionTime = time
                    hasDefaultTime = true
                }
            }
        }
        
        // Auto-generate name using new format: Day + Time + Location + Coach
        var nameParts: [String] = []
        if let firstDay = Array(selectedRecurringDays).sorted(by: { $0.rawValue < $1.rawValue }).first {
            nameParts.append(firstDay.displayName)
        }
        if hasDefaultTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            nameParts.append(formatter.string(from: defaultSessionTime))
        }
        if let locationId = selectedLocationId,
           let location = dataManager.locations.first(where: { $0.id == locationId }) {
            nameParts.append(location.name)
        }
        if let coachId = selectedCoachId,
           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
            nameParts.append(coach.name)
        }
        name = nameParts.isEmpty ? suggestion.name : nameParts.joined(separator: " ")
        
        // Store suggested phases to create when program is created
        suggestedPhases = suggestion.phases.map { phase in
            AIPhaseSuggestionFromProgram(
                phaseNumber: phase.phaseNumber,
                title: phase.title,
                focus: phase.focus,
                durationWeeks: phase.durationWeeks,
                description: phase.description,
                objectives: phase.objectives,
                sessions: phase.sessions ?? []
            )
        }
        debugLog("🤖 [AI] Stored \(suggestedPhases.count) phases for creation")
        
        // Switch to details tab
        withAnimation { selectedTab = 1 }
    }
    
    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Program")
                    .font(.system(size: 20, weight: .bold))
                Text("Create a training program and enroll students")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(MacGlassButtonStyle(color: .secondary))
            Button("Create") { createProgram() }
                .buttonStyle(MacGlassButtonStyle(color: .green))
                .disabled(name.isEmpty && selectedRecurringDays.isEmpty)
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var detailsTab: some View {
        VStack(spacing: 16) {
            // Program Name (auto-generated from schedule)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Program Name", systemImage: "textformat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Auto-generated from schedule")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Text(name.isEmpty ? "Select schedule details below" : name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(name.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            
            // Mascot & Age Group Row
            HStack(spacing: 16) {
                MacGlassPicker(title: "Mascot", icon: "pawprint", selection: $selectedMascot, options: Array(ProgramMascot.allCases), displayName: { $0.displayName }, color: selectedMascot.color)
                MacGlassPicker(title: "Age Group", icon: "person.2", selection: $selectedAgeGroup, options: Array(AgeGroup.allCases), displayName: { $0.displayName })
            }
            
            // Schedule Section - Recurring Days
            VStack(alignment: .leading, spacing: 8) {
                Label("Training Days", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Button(action: {
                            if selectedRecurringDays.contains(day) {
                                selectedRecurringDays.remove(day)
                            } else {
                                selectedRecurringDays.insert(day)
                            }
                            regenerateProgramName()
                        }) {
                            Text(day.shortName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedRecurringDays.contains(day) ? .white : .secondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(selectedRecurringDays.contains(day) ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(selectedRecurringDays.contains(day) ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
            }
            
            // Time & Duration Row
            HStack(spacing: 16) {
                // Default Session Time
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Session Time", systemImage: "clock")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $hasDefaultTime)
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .onChange(of: hasDefaultTime) { _, _ in regenerateProgramName() }
                    }
                    
                    if hasDefaultTime {
                        DatePicker("", selection: $defaultSessionTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: defaultSessionTime) { _, _ in regenerateProgramName() }
                    } else {
                        Text("Not set")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                
                // Duration
                VStack(alignment: .leading, spacing: 6) {
                    Label("Duration", systemImage: "timer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(durationWeeks) weeks")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Stepper("", value: $durationWeeks, in: 1...52)
                            .labelsHidden()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            }
            
            // Location Selection
            VStack(alignment: .leading, spacing: 6) {
                Label("Location", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                if dataManager.locations.isEmpty {
                    HStack {
                        Image(systemName: "mappin.slash")
                            .foregroundColor(.secondary)
                        Text("Add locations in Hub → Organization")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            locationButton(id: nil, name: "None", icon: "minus.circle")
                            ForEach(dataManager.locations) { location in
                                locationButton(id: location.id, name: location.name, icon: "mappin.circle.fill")
                            }
                        }
                        .padding(8)
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                }
            }
            
            // Coach Assignment
            VStack(alignment: .leading, spacing: 6) {
                Label("Assigned Coach", systemImage: "person.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                if dataManager.staffCoaches.isEmpty {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.secondary)
                        Text("Add coaches in Hub → Organization")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            coachSelectionButton(id: nil, name: "None", initials: "—", color: .gray)
                            ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                                coachSelectionButton(id: coach.id, name: coach.name, initials: coach.initials, color: Color.avatarColor(coach.avatarColor), isYou: coach.id == dataManager.loggedInCoachId)
                            }
                        }
                        .padding(8)
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                }
            }
            
            // Description
            VStack(alignment: .leading, spacing: 6) {
                Label("Description", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $description)
                    .font(.system(size: 14))
                    .frame(height: 60)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private func locationButton(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = selectedLocationId == id
        return Button(action: {
            selectedLocationId = id
            regenerateProgramName()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func regenerateProgramName() {
        var nameParts: [String] = []
        if let firstDay = Array(selectedRecurringDays).sorted(by: { $0.rawValue < $1.rawValue }).first {
            nameParts.append(firstDay.displayName)
        }
        if hasDefaultTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            nameParts.append(formatter.string(from: defaultSessionTime))
        }
        if let locationId = selectedLocationId,
           let location = dataManager.locations.first(where: { $0.id == locationId }) {
            nameParts.append(location.name)
        }
        if let coachId = selectedCoachId,
           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
            nameParts.append(coach.name)
        }
        name = nameParts.isEmpty ? "" : nameParts.joined(separator: " ")
    }
    
    private func coachSelectionButton(id: UUID?, name: String, initials: String, color: Color, isYou: Bool = false) -> some View {
        let isSelected = selectedCoachId == id
        return Button(action: { 
            selectedCoachId = id
            regenerateProgramName()
        }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.3))
                        .frame(width: 36, height: 36)
                    Text(initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                
                Text(name.split(separator: " ").first.map(String.init) ?? name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                if isYou {
                    Text("You")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }
    
    private var studentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Enroll Students")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(enrolledStudentIds.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.1)))
            }
            
            // Student Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(dataManager.students) { student in
                    studentEnrollmentCard(student: student)
                }
            }
            
            if dataManager.students.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No students available")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
    
    @ViewBuilder
    private func studentAvatarView(student: Student, size: CGFloat = 36) -> some View {
        let avatarColor = Color(student.avatarColor.color)
        if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(avatarColor.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(avatarColor)
                    )
            }
        } else {
            Circle()
                .fill(avatarColor.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(student.name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(avatarColor)
                )
        }
    }
    
    private func studentEnrollmentCard(student: Student) -> some View {
        let isSelected = enrolledStudentIds.contains(student.id)
        let bgColor: Color = isSelected ? Color.green.opacity(0.1) : Color.clear
        let strokeColor: Color = isSelected ? Color.green.opacity(0.3) : Color.primary.opacity(0.1)
        
        return Button(action: {
            if isSelected {
                enrolledStudentIds.remove(student.id)
            } else {
                enrolledStudentIds.insert(student.id)
            }
        }) {
            HStack(spacing: 10) {
                studentAvatarView(student: student, size: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .green : .secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(bgColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(strokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func createProgram() {
        // Use generated name or fallback to mascot name
        var programName = name.trimmingCharacters(in: .whitespaces)
        if programName.isEmpty {
            programName = "\(selectedMascot.displayName) Program"
        }
        
        // Get location name
        var locationName: String? = nil
        if let locationId = selectedLocationId,
           let location = dataManager.locations.first(where: { $0.id == locationId }) {
            locationName = location.name
        }
        
        let program = Program(
            name: programName,
            ageGroup: selectedAgeGroup,
            durationWeeks: durationWeeks,
            description: description.isEmpty ? nil : description,
            enrolledStudentIds: Array(enrolledStudentIds),
            coachId: selectedCoachId,
            createdByCoachId: dataManager.loggedInCoachId,
            mascot: selectedMascot,
            stars: .one,
            recurringDays: Array(selectedRecurringDays).sorted { $0.rawValue < $1.rawValue },
            defaultSessionTime: hasDefaultTime ? defaultSessionTime : nil,
            defaultSessionDurationMinutes: sessionDurationMinutes,
            locationId: selectedLocationId,
            locationName: locationName
        )
        dataManager.addProgram(program)
        
        // Create AI-suggested phases and sessions if any
        debugLog("🤖 [AI] Creating program with \(suggestedPhases.count) suggested phases")
        if !suggestedPhases.isEmpty {
            // Use batch mode to prevent fullSync for each add - sync once at end
            dataManager.beginBatchMode()
            
            for phaseSuggestion in suggestedPhases {
                debugLog("🤖 [AI] Creating phase \(phaseSuggestion.phaseNumber): \(phaseSuggestion.title) with \(phaseSuggestion.sessions.count) sessions")
                // Convert string focus values to TrainingFocus enum
                let focusValues: [TrainingFocus] = phaseSuggestion.focus.compactMap { focusString in
                    TrainingFocus(rawValue: focusString.lowercased().replacingOccurrences(of: " ", with: ""))
                }
                
                let phase = MicroCycle(
                    programId: program.id,
                    phaseNumber: phaseSuggestion.phaseNumber,
                    title: phaseSuggestion.title,
                    focus: focusValues.isEmpty ? [.shooting] : focusValues,
                    durationWeeks: phaseSuggestion.durationWeeks,
                    description: phaseSuggestion.description,
                    objectives: phaseSuggestion.objectives,
                    intensity: 5,
                    volume: 5
                )
                dataManager.addMicroCycle(phase)
                
                // Create sessions for this phase with weekly recurrence
                for sessionSuggestion in phaseSuggestion.sessions {
                    let sessionType = SessionType(rawValue: sessionSuggestion.sessionType) ?? .training
                    
                    // Calculate session date based on week number and day of week
                    let weekNumber = sessionSuggestion.weekNumber ?? 1
                    let dayOfWeek = sessionSuggestion.dayOfWeek?.lowercased() ?? "saturday"
                    
                    // Map day of week string to weekday number (1 = Sunday, 7 = Saturday)
                    let weekdayMap: [String: Int] = [
                        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                        "thursday": 5, "friday": 6, "saturday": 7
                    ]
                    let targetWeekday = weekdayMap[dayOfWeek] ?? 7
                    
                    // Start from today and find the next occurrence of the target weekday
                    var sessionDate = Date()
                    let calendar = Calendar.current
                    let currentWeekday = calendar.component(.weekday, from: sessionDate)
                    var daysToAdd = targetWeekday - currentWeekday
                    if daysToAdd < 0 { daysToAdd += 7 }
                    
                    // Add weeks based on weekNumber (week 1 = this/next occurrence, week 2 = +7 days, etc.)
                    daysToAdd += (weekNumber - 1) * 7
                    
                    // Also offset by phase number (each phase starts after previous phase weeks)
                    let previousPhasesWeeks = suggestedPhases.prefix(phaseSuggestion.phaseNumber - 1).reduce(0) { $0 + $1.durationWeeks }
                    daysToAdd += previousPhasesWeeks * 7
                    
                    sessionDate = calendar.date(byAdding: .day, value: daysToAdd, to: sessionDate) ?? sessionDate
                    
                    // Default start time: 6:30 PM
                    let startTime = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: sessionDate) ?? sessionDate
                    let endTime = calendar.date(byAdding: .minute, value: sessionSuggestion.durationMinutes, to: startTime) ?? startTime
                    
                    let session = SessionEvent(
                        microCycleId: phase.id,
                        programId: program.id,
                        sessionType: sessionType,
                        title: sessionSuggestion.title,
                        date: sessionDate,
                        startTime: startTime,
                        endTime: endTime,
                        location: nil,
                        status: .scheduled,
                        curriculum: SessionCurriculum(),
                        attendeeIds: Array(enrolledStudentIds),
                        actualAttendeeIds: [],
                        notes: sessionSuggestion.description,
                        coachNotes: nil
                    )
                    dataManager.addSessionEvent(session)
                }
            }
            
            // End batch mode and sync all created phases/sessions at once
            dataManager.endBatchModeAndSync()
        }
        
        dismiss()
    }
}

// MARK: - Edit Program Sheet (Glassmorphic Dark Theme)
struct EditProgramSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let program: Program
    
    @State private var name: String
    @State private var selectedMascot: ProgramMascot
    @State private var selectedAgeGroup: AgeGroup
    @State private var durationWeeks: Int
    @State private var description: String
    @State private var colorHex: String
    @State private var isActive: Bool
    @State private var enrolledStudentIds: Set<UUID>
    @State private var selectedCoachId: UUID?
    @State private var selectedTab = 0
    @State private var selectedStars: ProgramStars
    
    // Recurring schedule state
    @State private var recurringDays: Set<Weekday>
    @State private var defaultSessionTime: Date
    @State private var sessionDurationMinutes: Int
    @State private var updateExistingSessions: Bool = false
    
    private let programColors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F"]
    
    init(program: Program) {
        self.program = program
        _name = State(initialValue: program.name)
        _selectedMascot = State(initialValue: program.mascot)
        _selectedAgeGroup = State(initialValue: program.ageGroup)
        _durationWeeks = State(initialValue: program.durationWeeks)
        _description = State(initialValue: program.description ?? "")
        _colorHex = State(initialValue: program.colorHex)
        _isActive = State(initialValue: program.isActive)
        _enrolledStudentIds = State(initialValue: Set(program.enrolledStudentIds))
        _selectedCoachId = State(initialValue: program.coachId)
        _selectedStars = State(initialValue: program.stars)
        
        // Initialize recurring schedule
        _recurringDays = State(initialValue: Set(program.recurringDays))
        _defaultSessionTime = State(initialValue: program.defaultSessionTime ?? Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date())
        _sessionDurationMinutes = State(initialValue: program.defaultSessionDurationMinutes)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            tabSelector
            
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == 0 {
                        detailsTab
                    } else if selectedTab == 1 {
                        scheduleTab
                    } else {
                        studentsTab
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 580, height: 680)
        .background(GlassColors.background)
    }
    
    // MARK: - Header
    private var sheetHeader: some View {
        HStack(spacing: 16) {
            // Program icon
            ZStack {
                Circle()
                    .fill(Color(hex: colorHex).opacity(0.2))
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 44, height: 44)
                Image(systemName: selectedMascot.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Program")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text(name.isEmpty ? "Untitled Program" : name)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Cancel button
            Button("Cancel") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .buttonStyle(.plain)
            
            // Save button
            Button("Save") { saveProgram() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GlassColors.accentGreen)
                )
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                .opacity(name.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(Color.white.opacity(0.03))
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 8) {
            editProgramTabButton(title: "Details", icon: "info.circle.fill", index: 0)
            editProgramTabButton(title: "Schedule", icon: "calendar.badge.clock", index: 1)
            editProgramTabButton(title: "Students", icon: "person.3.fill", index: 2)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
    
    private func editProgramTabButton(title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? GlassColors.accentCyan : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Details Tab
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Program Name
            glassTextField(title: "Program Name", icon: "textformat", text: $name, placeholder: "e.g., Summer Basketball Camp")
            
            // Mascot & Age Group Row
            HStack(alignment: .top, spacing: 16) {
                glassPicker(title: "Mascot", icon: "pawprint.fill", options: ProgramMascot.allCases, selection: $selectedMascot) { $0.displayName }
                glassPicker(title: "Age Group", icon: "person.2.fill", options: AgeGroup.allCases, selection: $selectedAgeGroup) { $0.displayName }
            }
            
            // Program Tier (Stars)
            VStack(alignment: .leading, spacing: 10) {
                Label("Program Tier", systemImage: "star.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 12) {
                    ForEach(ProgramStars.allCases, id: \.self) { tier in
                        Button(action: { selectedStars = tier }) {
                            VStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    ForEach(0..<tier.rawValue, id: \.self) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10))
                                    }
                                }
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                
                                Text(tier.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(selectedStars == tier ? .white : .white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedStars == tier ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedStars == tier ? Color(hex: "#FFD700").opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Label("Duration", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack {
                    Text("\(durationWeeks) weeks")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Stepper("", value: $durationWeeks, in: 1...52)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            // Status Toggle
            HStack {
                Label("Status", systemImage: "flag.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Text(isActive ? "Active" : "Draft")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? GlassColors.accentGreen : .white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Color Picker
            VStack(alignment: .leading, spacing: 10) {
                Label("Program Color", systemImage: "paintpalette.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 12) {
                    ForEach(programColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: colorHex == hex ? 3 : 0)
                            )
                            .shadow(color: colorHex == hex ? Color(hex: hex).opacity(0.6) : .clear, radius: 6)
                            .scaleEffect(colorHex == hex ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3), value: colorHex)
                            .onTapGesture { colorHex = hex }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                )
            }
            
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Label("Description", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                TextEditor(text: $description)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Schedule Tab
    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(GlassColors.accentCyan.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(GlassColors.accentCyan)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recurring Schedule")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Set the default days and time for sessions in this program")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            
            // Days of Week Selection
            VStack(alignment: .leading, spacing: 12) {
                Label("Session Days", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 8) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Button(action: {
                            if recurringDays.contains(day) {
                                recurringDays.remove(day)
                            } else {
                                recurringDays.insert(day)
                            }
                        }) {
                            Text(day.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(recurringDays.contains(day) ? .white : .white.opacity(0.5))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(recurringDays.contains(day) ? GlassColors.accentCyan : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(recurringDays.contains(day) ? GlassColors.accentCyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Selected days summary
                if !recurringDays.isEmpty {
                    let sortedDays = recurringDays.sorted { $0.rawValue < $1.rawValue }
                    Text("Sessions on: \(sortedDays.map { $0.displayName }.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(GlassColors.accentCyan)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            
            // Default Session Time
            VStack(alignment: .leading, spacing: 12) {
                Label("Default Start Time", systemImage: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack {
                    DatePicker("", selection: $defaultSessionTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                    
                    Spacer()
                    
                    // Quick time presets
                    HStack(spacing: 8) {
                        ForEach([(9, 0, "9 AM"), (14, 0, "2 PM"), (16, 30, "4:30 PM"), (18, 30, "6:30 PM")], id: \.2) { hour, minute, label in
                            Button(action: {
                                if let newTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) {
                                    defaultSessionTime = newTime
                                }
                            }) {
                                Text(label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            
            // Session Duration
            VStack(alignment: .leading, spacing: 12) {
                Label("Default Duration", systemImage: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack {
                    Text("\(sessionDurationMinutes) minutes")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Stepper("", value: $sessionDurationMinutes, in: 30...180, step: 15)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                
                // Duration presets
                HStack(spacing: 8) {
                    ForEach([60, 90, 120], id: \.self) { duration in
                        Button(action: { sessionDurationMinutes = duration }) {
                            Text("\(duration) min")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(sessionDurationMinutes == duration ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(sessionDurationMinutes == duration ? GlassColors.accentCyan.opacity(0.3) : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(sessionDurationMinutes == duration ? GlassColors.accentCyan.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            
            // Schedule Preview
            if !recurringDays.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Schedule Preview", systemImage: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    let timeFormatter = DateFormatter()
                    let _ = timeFormatter.dateFormat = "h:mm a"
                    let endTime = Calendar.current.date(byAdding: .minute, value: sessionDurationMinutes, to: defaultSessionTime) ?? defaultSessionTime
                    
                    HStack(spacing: 16) {
                        ForEach(recurringDays.sorted { $0.rawValue < $1.rawValue }, id: \.self) { day in
                            VStack(spacing: 6) {
                                Text(day.shortName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(GlassColors.accentCyan)
                                
                                Text(timeFormatter.string(from: defaultSessionTime))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("-")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Text(timeFormatter.string(from: endTime))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(GlassColors.accentCyan.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(GlassColors.accentCyan.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                )
            }
            
            // Update Existing Sessions Option
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Toggle("", isOn: $updateExistingSessions)
                        .labelsHidden()
                        .toggleStyle(.switch)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Existing Sessions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("Apply the new time to all scheduled sessions in this program")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                }
                
                if updateExistingSessions {
                    let sessionCount = dataManager.sessionEvents.filter { $0.programId == program.id && $0.status == .scheduled }.count
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(GlassColors.accentCyan)
                        Text("\(sessionCount) scheduled session\(sessionCount == 1 ? "" : "s") will be updated")
                            .font(.system(size: 11))
                            .foregroundColor(GlassColors.accentCyan)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GlassColors.accentCyan.opacity(0.1))
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }
    
    // MARK: - Glass Text Field
    private func glassTextField(title: String, icon: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Glass Picker
    private func glassPicker<T: Hashable>(title: String, icon: String, options: [T], selection: Binding<T>, displayName: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(displayName(option)) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack {
                    Text(displayName(selection.wrappedValue))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Students Tab
    private var studentsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enrolled Students")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(enrolledStudentIds.count) enrolled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GlassColors.accentCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(GlassColors.accentCyan.opacity(0.15))
                    )
            }
            
            if dataManager.students.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No Students Available")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Add students in Hub → Athletes")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(dataManager.students) { student in
                        glassStudentCard(student: student)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func editStudentAvatar(student: Student, size: CGFloat = 40) -> some View {
        let avatarColor = Color(student.avatarColor.color)
        if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(avatarColor.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: size * 0.35, weight: .bold))
                            .foregroundColor(avatarColor)
                    )
            }
        } else {
            Circle()
                .fill(avatarColor.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(student.name.prefix(1)))
                        .font(.system(size: size * 0.35, weight: .bold))
                        .foregroundColor(avatarColor)
                )
        }
    }
    
    private func glassStudentCard(student: Student) -> some View {
        let isEnrolled = enrolledStudentIds.contains(student.id)
        return Button {
            if isEnrolled {
                enrolledStudentIds.remove(student.id)
            } else {
                enrolledStudentIds.insert(student.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Avatar with profile picture support
                editStudentAvatar(student: student, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                Spacer()
                
                Image(systemName: isEnrolled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isEnrolled ? GlassColors.accentGreen : .white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnrolled ? GlassColors.accentGreen.opacity(0.1) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnrolled ? GlassColors.accentGreen.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Save
    private func saveProgram() {
        var updated = program
        updated.name = name
        updated.mascot = selectedMascot
        updated.ageGroup = selectedAgeGroup
        updated.durationWeeks = durationWeeks
        updated.description = description.isEmpty ? nil : description
        updated.colorHex = colorHex
        updated.status = isActive ? .active : .draft
        updated.enrolledStudentIds = Array(enrolledStudentIds)
        updated.coachId = selectedCoachId
        updated.stars = selectedStars
        
        // Save recurring schedule
        updated.recurringDays = Array(recurringDays).sorted { $0.rawValue < $1.rawValue }
        updated.defaultSessionTime = defaultSessionTime
        updated.defaultSessionDurationMinutes = sessionDurationMinutes
        updated.updatedAt = Date()
        
        dataManager.updateProgram(updated)
        
        // Update existing sessions if requested
        if updateExistingSessions {
            updateScheduledSessions()
        }
        
        dismiss()
    }
    
    private func updateScheduledSessions() {
        let calendar = Calendar.current
        let newHour = calendar.component(.hour, from: defaultSessionTime)
        let newMinute = calendar.component(.minute, from: defaultSessionTime)
        
        // Get all scheduled sessions for this program
        let scheduledSessions = dataManager.sessionEvents.filter { 
            $0.programId == program.id && $0.status == .scheduled 
        }
        
        for session in scheduledSessions {
            var updatedSession = session
            
            // Update start time - keep the same date but change the time
            if let newStartTime = calendar.date(bySettingHour: newHour, minute: newMinute, second: 0, of: session.date) {
                updatedSession.startTime = newStartTime
                updatedSession.date = newStartTime
                
                // Update end time based on new duration
                if let newEndTime = calendar.date(byAdding: .minute, value: sessionDurationMinutes, to: newStartTime) {
                    updatedSession.endTime = newEndTime
                }
                
                updatedSession.updatedAt = Date()
                dataManager.updateSessionEvent(updatedSession)
            }
        }
    }
}

// MARK: - Add Phase Sheet
struct AddPhaseSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let program: Program
    
    @State private var title = ""
    @State private var phaseNumber: Int
    @State private var durationWeeks = 2
    @State private var intensity = 5
    @State private var focus: [String] = []
    @State private var newFocus = ""
    @State private var description = ""
    @State private var selectedTab = 0
    
    // AI Assistant state
    @State private var aiPrompt = ""
    @State private var isAIProcessing = false
    @State private var aiSuggestion: AIPhaseSuggestion? = nil
    @State private var aiErrorMessage: String? = nil
    
    init(program: Program) {
        self.program = program
        let existingPhases = DataManager.shared.microCycles.filter { $0.programId == program.id }
        _phaseNumber = State(initialValue: existingPhases.count + 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Phase to \(program.mascot.displayName)")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Button("Create") { createPhase() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
            }
            .padding()
            .background(Color(hex: program.colorHex).opacity(0.1))
            
            // Tab Selector
            HStack(spacing: 0) {
                tabButton(title: "AI Assistant", icon: "sparkles", index: 0)
                tabButton(title: "Details", icon: "info.circle", index: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Divider()
            
            ScrollView {
                if selectedTab == 0 {
                    aiAssistantTab
                        .padding(16)
                } else {
                    detailsTab
                        .padding(16)
                }
            }
        }
        .frame(width: 500, height: 550)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? Color(hex: program.colorHex) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - AI Assistant Tab
    private var aiAssistantTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: program.colorHex), .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Phase Assistant")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Describe the training phase you want to create")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: program.colorHex).opacity(0.1)))
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Describe your phase", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $aiPrompt)
                    .font(.system(size: 13))
                    .frame(height: 70)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: program.colorHex).opacity(0.3), lineWidth: 1))
                
                Text("e.g., \"Foundation phase focusing on shooting fundamentals and footwork\"")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Button(action: generateAISuggestion) {
                HStack(spacing: 8) {
                    if isAIProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAIProcessing ? "Generating..." : "Generate Phase")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: program.colorHex)))
            }
            .buttonStyle(.plain)
            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIProcessing)
            .opacity(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            
            if let error = aiErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
            
            if let suggestion = aiSuggestion {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("AI Suggestion").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Apply") { applyAISuggestion(suggestion) }
                            .buttonStyle(MacGlassButtonStyle(color: .green))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.title).font(.system(size: 15, weight: .bold))
                        Text(suggestion.description).font(.system(size: 11)).foregroundColor(.secondary)
                        HStack {
                            Text("\(suggestion.durationWeeks) weeks").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.blue.opacity(0.1)))
                            ForEach(suggestion.focus.prefix(3), id: \.self) { f in
                                Text(f).font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color(hex: program.colorHex).opacity(0.1)))
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: program.colorHex).opacity(0.05)))
                }
            }
        }
    }
    
    private var detailsTab: some View {
        VStack(spacing: 16) {
            MacGlassTextField(title: "Phase Title", icon: "textformat", text: $title, placeholder: "e.g., Foundation Phase")
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Phase #", systemImage: "number")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Stepper("\(phaseNumber)", value: $phaseNumber, in: 1...20)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Duration", systemImage: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Stepper("\(durationWeeks) weeks", value: $durationWeeks, in: 1...12)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Intensity", systemImage: "flame")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Stepper("\(intensity)/10", value: $intensity, in: 1...10)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Focus Areas", systemImage: "target")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach(focus, id: \.self) { item in
                    HStack {
                        Text(item).font(.system(size: 12))
                        Spacer()
                        Button(action: { focus.removeAll { $0 == item } }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.7))
                        }.buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                }
                
                HStack {
                    TextField("Add focus area", text: $newFocus)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    Button("Add") {
                        if !newFocus.isEmpty {
                            focus.append(newFocus)
                            newFocus = ""
                        }
                    }
                    .disabled(newFocus.isEmpty)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
            }
        }
    }
    
    private func generateAISuggestion() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        aiErrorMessage = nil
        isAIProcessing = true
        
        Task {
            do {
                let suggestion: AIPhaseSuggestion = try await SupabaseManager.shared.invokeFunction(
                    name: "refine_phase",
                    body: ["prompt": prompt, "programContext": program.mascot.displayName]
                )
                await MainActor.run {
                    withAnimation { aiSuggestion = suggestion; isAIProcessing = false }
                }
            } catch {
                await MainActor.run {
                    withAnimation { aiErrorMessage = "AI service unavailable."; isAIProcessing = false }
                }
            }
        }
    }
    
    private func applyAISuggestion(_ suggestion: AIPhaseSuggestion) {
        title = suggestion.title
        durationWeeks = suggestion.durationWeeks
        focus = suggestion.focus
        description = suggestion.description
        withAnimation { selectedTab = 1 }
    }
    
    private func createPhase() {
        let phase = MicroCycle(
            programId: program.id,
            phaseNumber: phaseNumber,
            title: title,
            focus: [],
            durationWeeks: durationWeeks,
            description: description.isEmpty ? nil : description,
            intensity: intensity
        )
        dataManager.addMicroCycle(phase)
        dismiss()
    }
}

// MARK: - Edit Phase Sheet
struct EditPhaseSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let phase: MicroCycle
    let program: Program
    
    @State private var title: String
    @State private var phaseNumber: Int
    @State private var durationWeeks: Int
    @State private var intensity: Int
    @State private var focus: [TrainingFocus]
    @State private var newFocus = ""
    
    init(phase: MicroCycle, program: Program) {
        self.phase = phase
        self.program = program
        _title = State(initialValue: phase.title)
        _phaseNumber = State(initialValue: phase.phaseNumber)
        _durationWeeks = State(initialValue: phase.durationWeeks)
        _intensity = State(initialValue: phase.intensity)
        _focus = State(initialValue: phase.focus)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Phase")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Button("Save") { savePhase() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
            }
            .padding()
            .background(Color(hex: program.colorHex).opacity(0.1))
            
            Divider()
            
            Form {
                Section("Phase Info") {
                    TextField("Phase Title", text: $title)
                    Stepper("Phase #\(phaseNumber)", value: $phaseNumber, in: 1...20)
                    Stepper("Duration: \(durationWeeks) weeks", value: $durationWeeks, in: 1...12)
                    Stepper("Intensity: \(intensity)/10", value: $intensity, in: 1...10)
                }
                
                Section("Focus Areas") {
                    ForEach(focus, id: \.self) { item in
                        HStack {
                            Text(item.displayName)
                            Spacer()
                            Button(action: { focus.removeAll { $0 == item } }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 450)
    }
    
    private func savePhase() {
        var updated = phase
        updated.title = title
        updated.phaseNumber = phaseNumber
        updated.durationWeeks = durationWeeks
        updated.intensity = intensity
        updated.focus = focus
        dataManager.updateMicroCycle(updated)
        dismiss()
    }
}

// MARK: - Add Session Sheet
struct AddSessionSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let phase: MicroCycle
    let program: Program
    
    @State private var title = ""
    @State private var sessionType: SessionType = .training
    @State private var date = Date()
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedLocationId: UUID? = nil
    @State private var customLocation = ""
    @State private var notes = ""
    @State private var selectedTab = 0
    
    // AI Assistant state
    @State private var aiPrompt = ""
    @State private var isAIProcessing = false
    @State private var aiSuggestion: AISessionSuggestion? = nil
    @State private var aiErrorMessage: String? = nil
    
    init(phase: MicroCycle, program: Program) {
        self.phase = phase
        self.program = program
        // Default times: 6:30 PM to 8:00 PM
        let calendar = Calendar.current
        let startComponents = DateComponents(hour: 18, minute: 30)
        let endComponents = DateComponents(hour: 20, minute: 0)
        _startTime = State(initialValue: calendar.date(from: startComponents) ?? Date())
        _endTime = State(initialValue: calendar.date(from: endComponents) ?? Date())
    }
    
    private var locationString: String? {
        if let id = selectedLocationId, let loc = dataManager.locations.first(where: { $0.id == id }) {
            return loc.name
        } else if !customLocation.isEmpty {
            return customLocation
        }
        return nil
    }
    
    // Curriculum
    @State private var warmupMinutes = 30
    @State private var skillsMinutes = 30
    @State private var gameMinutes = 30
    @State private var warmupDrillIds: [UUID] = []
    @State private var skillDrillIds: [UUID] = []
    @State private var gameDrillIds: [UUID] = []
    @State private var curriculumNotes = ""
    
    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            
            // Tab Selector
            HStack(spacing: 0) {
                tabButton(title: "AI Assistant", icon: "sparkles", index: 0)
                tabButton(title: "Details", icon: "info.circle", index: 1)
                tabButton(title: "Plan", icon: "list.bullet.clipboard", index: 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == 0 {
                        aiAssistantTab
                    } else if selectedTab == 1 {
                        detailsTab
                    } else {
                        planTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 650, height: 750)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - AI Assistant Tab
    private var aiAssistantTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: program.colorHex), .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Session Assistant")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Describe the training session you want to create")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: program.colorHex).opacity(0.1)))
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Describe your session", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $aiPrompt)
                    .font(.system(size: 13))
                    .frame(height: 70)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: program.colorHex).opacity(0.3), lineWidth: 1))
                
                Text("e.g., \"Shooting fundamentals session with warmup drills and game simulation\"")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Button(action: generateAISuggestion) {
                HStack(spacing: 8) {
                    if isAIProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAIProcessing ? "Generating..." : "Generate Session")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: program.colorHex)))
            }
            .buttonStyle(.plain)
            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIProcessing)
            .opacity(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            
            if let error = aiErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
            
            if let suggestion = aiSuggestion {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("AI Suggestion").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Apply") { applyAISuggestion(suggestion) }
                            .buttonStyle(MacGlassButtonStyle(color: .green))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(suggestion.title).font(.system(size: 15, weight: .bold))
                            Spacer()
                            Text("\(suggestion.durationMinutes) min").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.blue.opacity(0.1)))
                        }
                        Text(suggestion.description).font(.system(size: 11)).foregroundColor(.secondary)
                        
                        // Drills preview
                        VStack(alignment: .leading, spacing: 4) {
                            if !suggestion.warmupDrills.isEmpty {
                                Text("Warmup: \(suggestion.warmupDrills.map { $0.name }.joined(separator: ", "))").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            if !suggestion.mainDrills.isEmpty {
                                Text("Main: \(suggestion.mainDrills.map { $0.name }.joined(separator: ", "))").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                        
                        if !suggestion.coachNotes.isEmpty {
                            Text("Notes: \(suggestion.coachNotes)").font(.system(size: 10)).foregroundColor(.secondary).italic()
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: program.colorHex).opacity(0.05)))
                }
            }
        }
    }
    
    private func generateAISuggestion() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        aiErrorMessage = nil
        isAIProcessing = true
        
        Task {
            do {
                let suggestion: AISessionSuggestion = try await SupabaseManager.shared.invokeFunction(
                    name: "refine_session",
                    body: ["prompt": prompt, "phaseContext": phase.title]
                )
                await MainActor.run {
                    withAnimation { aiSuggestion = suggestion; isAIProcessing = false }
                }
            } catch {
                await MainActor.run {
                    withAnimation { aiErrorMessage = "AI service unavailable."; isAIProcessing = false }
                }
            }
        }
    }
    
    private func applyAISuggestion(_ suggestion: AISessionSuggestion) {
        title = suggestion.title
        notes = suggestion.coachNotes
        
        // Map session type
        if let type = SessionType(rawValue: suggestion.sessionType) {
            sessionType = type
        }
        
        withAnimation { selectedTab = 1 }
    }
    
    private var sheetHeader: some View {
        HStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: program.colorHex))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "calendar.badge.plus").foregroundColor(.white))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Session")
                        .font(.system(size: 20, weight: .bold))
                    Text("Phase \(phase.phaseNumber): \(phase.title)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(MacGlassButtonStyle(color: .secondary))
            Button("Create") { createSession() }
                .buttonStyle(MacGlassButtonStyle(color: .green))
                .disabled(title.isEmpty)
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedTab == index ? Color(hex: program.colorHex) : Color.clear))
        }
        .buttonStyle(.plain)
    }
    
    private var detailsTab: some View {
        VStack(spacing: 16) {
            MacGlassTextField(title: "Session Title", icon: "textformat", text: $title, placeholder: "e.g., Ball Handling Fundamentals")
            
            MacGlassPicker(title: "Session Type", icon: "figure.basketball", selection: $sessionType, options: Array(SessionType.allCases), displayName: { $0.displayName }, color: Color(hex: program.colorHex))
            
            // Date & Time
            VStack(alignment: .leading, spacing: 6) {
                Label("Schedule", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            
            // Location picker or text field
            VStack(alignment: .leading, spacing: 6) {
                Label("Location", systemImage: "mappin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                if dataManager.locations.isEmpty {
                    TextField("e.g., Main Court", text: $customLocation)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $selectedLocationId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(dataManager.locations) { location in
                            Text(location.name).tag(location.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $notes)
                    .font(.system(size: 14))
                    .frame(height: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private var planTab: some View {
        VStack(spacing: 20) {
            // Time Allocation
            VStack(alignment: .leading, spacing: 12) {
                Label("Time Allocation", systemImage: "clock")
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 16) {
                    timeAllocationCard(title: "Warmup", minutes: $warmupMinutes, color: .orange, icon: "flame")
                    timeAllocationCard(title: "Skills", minutes: $skillsMinutes, color: .blue, icon: "figure.basketball")
                    timeAllocationCard(title: "Game", minutes: $gameMinutes, color: .green, icon: "sportscourt")
                }
            }
            
            // Curriculum Sections with Searchable Drill Picker
            MacCurriculumSectionView(
                title: "Warmup Drills",
                icon: "flame",
                color: .orange,
                drillIds: $warmupDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            MacCurriculumSectionView(
                title: "Skill Drills",
                icon: "figure.basketball",
                color: .blue,
                drillIds: $skillDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            MacCurriculumSectionView(
                title: "Game Drills",
                icon: "sportscourt",
                color: .green,
                drillIds: $gameDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            
            // Curriculum Notes
            VStack(alignment: .leading, spacing: 6) {
                Label("Plan Notes", systemImage: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $curriculumNotes)
                    .font(.system(size: 14))
                    .frame(height: 60)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private func timeAllocationCard(title: String, minutes: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            
            Text("\(minutes.wrappedValue) min")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Stepper("", value: minutes, in: 5...60, step: 5)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    private func curriculumSection(title: String, icon: String, color: Color, drillIds: Binding<[UUID]>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(drillIds.wrappedValue.count) drills")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            if drillIds.wrappedValue.isEmpty {
                HStack {
                    Text("No drills added")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            } else {
                ForEach(drillIds.wrappedValue, id: \.self) { drillId in
                    if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                        drillRow(drill: drill, color: color) {
                            drillIds.wrappedValue.removeAll { $0 == drillId }
                        }
                    }
                }
            }
            
            // Add Drill Button
            Menu {
                ForEach(dataManager.drills) { drill in
                    Button(action: {
                        if !drillIds.wrappedValue.contains(drill.id) {
                            drillIds.wrappedValue.append(drill.id)
                        }
                    }) {
                        Label(drill.name, systemImage: drill.category.icon)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Drill")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    private func drillRow(drill: DrillItem, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: drill.category.icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(drill.durationMinutes) min • \(drill.difficulty.displayName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    private func createSession() {
        let curriculum = SessionCurriculum(
            warmupDrillIds: warmupDrillIds,
            skillDrillIds: skillDrillIds,
            gameDrillIds: gameDrillIds,
            warmupMinutes: warmupMinutes,
            skillsMinutes: skillsMinutes,
            gameMinutes: gameMinutes,
            notes: curriculumNotes.isEmpty ? nil : curriculumNotes
        )
        
        // Combine date with time components for correct startTime and endTime
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        let combinedStartTime = calendar.date(bySettingHour: startComponents.hour ?? 18,
                                               minute: startComponents.minute ?? 30,
                                               second: 0, of: date) ?? date
        let combinedEndTime = calendar.date(bySettingHour: endComponents.hour ?? 20,
                                             minute: endComponents.minute ?? 0,
                                             second: 0, of: date) ?? date
        
        // Auto-populate attendees from program enrollment
        let attendeeIds = program.enrolledStudentIds
        
        let session = SessionEvent(
            microCycleId: phase.id,
            programId: program.id,
            sessionType: sessionType,
            title: title,
            date: date,
            startTime: combinedStartTime,
            endTime: combinedEndTime,
            location: locationString,
            curriculum: curriculum,
            attendeeIds: attendeeIds,
            notes: notes.isEmpty ? nil : notes,
            createdByCoachId: dataManager.loggedInCoachId
        )
        dataManager.addSessionEvent(session)
        dismiss()
    }
}

// MARK: - Edit Session Sheet
struct EditSessionSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let session: SessionEvent
    
    @State private var title: String
    @State private var sessionType: SessionType
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String
    @State private var status: SessionEventStatus
    @State private var selectedTab = 0
    
    // Curriculum
    @State private var warmupMinutes: Int
    @State private var skillsMinutes: Int
    @State private var gameMinutes: Int
    @State private var warmupDrillIds: [UUID]
    @State private var skillDrillIds: [UUID]
    @State private var gameDrillIds: [UUID]
    @State private var curriculumNotes: String
    
    private var programColor: Color {
        if let programId = session.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            return Color(hex: program.colorHex)
        }
        return .accentColor
    }
    
    init(session: SessionEvent) {
        self.session = session
        _title = State(initialValue: session.title)
        _sessionType = State(initialValue: session.sessionType)
        _date = State(initialValue: session.date)
        _startTime = State(initialValue: session.startTime)
        _endTime = State(initialValue: session.endTime)
        _location = State(initialValue: session.location ?? "")
        _notes = State(initialValue: session.notes ?? "")
        _status = State(initialValue: session.status)
        _warmupMinutes = State(initialValue: session.curriculum.warmupMinutes)
        _skillsMinutes = State(initialValue: session.curriculum.skillsMinutes)
        _gameMinutes = State(initialValue: session.curriculum.gameMinutes)
        _warmupDrillIds = State(initialValue: session.curriculum.warmupDrillIds)
        _skillDrillIds = State(initialValue: session.curriculum.skillDrillIds)
        _gameDrillIds = State(initialValue: session.curriculum.gameDrillIds)
        _curriculumNotes = State(initialValue: session.curriculum.notes ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            
            // Tab Selector
            HStack(spacing: 0) {
                tabButton(title: "Details", icon: "info.circle", index: 0)
                tabButton(title: "Plan", icon: "list.bullet.clipboard", index: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == 0 {
                        detailsTab
                    } else {
                        planTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 650, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var sheetHeader: some View {
        HStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(programColor)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: sessionType.icon).foregroundColor(.white))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Session")
                        .font(.system(size: 20, weight: .bold))
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(MacGlassButtonStyle(color: .secondary))
            Button("Save") { saveSession() }
                .buttonStyle(MacGlassButtonStyle(color: .green))
                .disabled(title.isEmpty)
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedTab == index ? programColor : Color.clear))
        }
        .buttonStyle(.plain)
    }
    
    private var detailsTab: some View {
        VStack(spacing: 16) {
            MacGlassTextField(title: "Session Title", icon: "textformat", text: $title, placeholder: "e.g., Ball Handling Fundamentals")
            
            HStack(spacing: 16) {
                MacGlassPicker(title: "Session Type", icon: "figure.basketball", selection: $sessionType, options: Array(SessionType.allCases), displayName: { $0.displayName }, color: programColor)
                MacGlassPicker(title: "Status", icon: "flag", selection: $status, options: Array(SessionEventStatus.allCases), displayName: { $0.displayName }, color: statusColor)
            }
            
            // Date & Time
            VStack(alignment: .leading, spacing: 6) {
                Label("Schedule", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            
            MacGlassTextField(title: "Location", icon: "mappin", text: $location, placeholder: "e.g., Main Court")
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $notes)
                    .font(.system(size: 14))
                    .frame(height: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
    
    private var planTab: some View {
        VStack(spacing: 20) {
            // Time Allocation
            VStack(alignment: .leading, spacing: 12) {
                Label("Time Allocation", systemImage: "clock")
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 16) {
                    timeAllocationCard(title: "Warmup", minutes: $warmupMinutes, color: .orange, icon: "flame")
                    timeAllocationCard(title: "Skills", minutes: $skillsMinutes, color: .blue, icon: "figure.basketball")
                    timeAllocationCard(title: "Game", minutes: $gameMinutes, color: .green, icon: "sportscourt")
                }
            }
            
            // Curriculum Sections with Searchable Drill Picker
            MacCurriculumSectionView(
                title: "Warmup Drills",
                icon: "flame",
                color: .orange,
                drillIds: $warmupDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            MacCurriculumSectionView(
                title: "Skill Drills",
                icon: "figure.basketball",
                color: .blue,
                drillIds: $skillDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            MacCurriculumSectionView(
                title: "Game Drills",
                icon: "sportscourt",
                color: .green,
                drillIds: $gameDrillIds,
                allDrills: dataManager.drills,
                programColor: .blue
            )
            
            // Curriculum Notes
            VStack(alignment: .leading, spacing: 6) {
                Label("Plan Notes", systemImage: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $curriculumNotes)
                    .font(.system(size: 14))
                    .frame(height: 60)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private func timeAllocationCard(title: String, minutes: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            
            Text("\(minutes.wrappedValue) min")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Stepper("", value: minutes, in: 5...60, step: 5)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    private func curriculumSection(title: String, icon: String, color: Color, drillIds: Binding<[UUID]>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(drillIds.wrappedValue.count) drills")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            if drillIds.wrappedValue.isEmpty {
                HStack {
                    Text("No drills added")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            } else {
                ForEach(drillIds.wrappedValue, id: \.self) { drillId in
                    if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                        drillRow(drill: drill, color: color) {
                            drillIds.wrappedValue.removeAll { $0 == drillId }
                        }
                    }
                }
            }
            
            // Add Drill Button
            Menu {
                ForEach(dataManager.drills) { drill in
                    Button(action: {
                        if !drillIds.wrappedValue.contains(drill.id) {
                            drillIds.wrappedValue.append(drill.id)
                        }
                    }) {
                        Label(drill.name, systemImage: drill.category.icon)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Drill")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    private func drillRow(drill: DrillItem, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: drill.category.icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(drill.durationMinutes) min • \(drill.difficulty.displayName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    private func saveSession() {
        var updated = session
        updated.title = title
        updated.sessionType = sessionType
        updated.date = date
        updated.startTime = startTime
        updated.endTime = endTime
        updated.location = location.isEmpty ? nil : location
        updated.notes = notes.isEmpty ? nil : notes
        updated.status = status
        updated.curriculum = SessionCurriculum(
            warmupDrillIds: warmupDrillIds,
            skillDrillIds: skillDrillIds,
            gameDrillIds: gameDrillIds,
            warmupMinutes: warmupMinutes,
            skillsMinutes: skillsMinutes,
            gameMinutes: gameMinutes,
            notes: curriculumNotes.isEmpty ? nil : curriculumNotes
        )
        dataManager.updateSessionEvent(updated)
        dismiss()
    }
}

// MARK: - Mac League Components

/// Live game card with prominent display
struct MacLiveGameCard: View {
    let game: Game
    let dataManager: DataManager
    let action: () -> Void
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // Live indicator
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text(game.quarterDisplay ?? "LIVE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                    Spacer()
                    if let time = game.timeRemaining {
                        Text(time)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                // Teams and Scores
                HStack(spacing: 24) {
                    // Home Team
                    VStack(spacing: 8) {
                        if let home = homeTeam {
                            Circle()
                                .fill(LinearGradient(colors: [home.primaryColor, home.primaryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: home.logoSystemImage).font(.system(size: 20, weight: .bold)).foregroundColor(.white))
                            Text(home.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    
                    // Score
                    HStack(spacing: 8) {
                        Text("\(game.homeScore)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(game.homeScore > game.awayScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                        Text("-")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(game.awayScore)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(game.awayScore > game.homeScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                    }
                    
                    // Away Team
                    VStack(spacing: 8) {
                        if let away = awayTeam {
                            Circle()
                                .fill(LinearGradient(colors: [away.primaryColor, away.primaryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: away.logoSystemImage).font(.system(size: 20, weight: .bold)).foregroundColor(.white))
                            Text(away.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.3), lineWidth: 2))
            )
            .shadow(color: Color.red.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { isHovered = $0 }
    }
}

/// Game row for lists
struct MacGameRow: View {
    let game: Game
    let dataManager: DataManager
    let action: () -> Void
    
    var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Home Team
                HStack(spacing: 10) {
                    if let home = homeTeam {
                        Circle()
                            .fill(home.primaryColor)
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: home.logoSystemImage).font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(home.shortName).font(.system(size: 13, weight: .bold)).foregroundColor(AppTheme.textPrimary)
                            Text(home.name.components(separatedBy: " ").last ?? "").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Score or Time
                VStack(spacing: 2) {
                    if game.status == .finished {
                        HStack(spacing: 4) {
                            Text("\(game.homeScore)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(game.homeScore > game.awayScore ? AppTheme.accentColor : AppTheme.textPrimary)
                            Text("-").font(.system(size: 12)).foregroundColor(AppTheme.textTertiary)
                            Text("\(game.awayScore)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(game.awayScore > game.homeScore ? AppTheme.accentColor : AppTheme.textPrimary)
                        }
                        Text("Final").font(.system(size: 9, weight: .medium)).foregroundColor(AppTheme.textTertiary)
                    } else {
                        Text(game.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .frame(width: 70)
                
                // Away Team
                HStack(spacing: 10) {
                    if let away = awayTeam {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(away.shortName).font(.system(size: 13, weight: .bold)).foregroundColor(AppTheme.textPrimary)
                            Text(away.name.components(separatedBy: " ").last ?? "").font(.system(size: 10)).foregroundColor(AppTheme.textSecondary).lineLimit(1)
                        }
                        Circle()
                            .fill(away.primaryColor)
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: away.logoSystemImage).font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Enhanced team card for League tab
struct MacLeagueTeamCard: View {
    let team: Team
    let dataManager: DataManager
    let action: () -> Void
    
    var standing: TeamStanding? {
        dataManager.teamStandings.first { $0.teamId == team.id }
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                // Logo with glow
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [team.primaryColor.opacity(0.3), Color.clear], center: .center, startRadius: 20, endRadius: 40))
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(LinearGradient(colors: [team.primaryColor, team.primaryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: team.logoSystemImage).font(.system(size: 24, weight: .bold)).foregroundColor(.white))
                }
                
                VStack(spacing: 6) {
                    Text(team.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text(team.shortName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(team.primaryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(team.primaryColor.opacity(0.15)))
                    
                    Text("\(team.playerCount) Players")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                if let standing = standing {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(standing.record)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Record").font(.system(size: 9)).foregroundColor(AppTheme.textTertiary)
                        }
                        Rectangle().fill(AppTheme.textTertiary.opacity(0.3)).frame(width: 1, height: 24)
                        VStack(spacing: 2) {
                            Text(standing.streakDisplay)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(standing.streak > 0 ? .green : (standing.streak < 0 ? .red : AppTheme.textSecondary))
                            Text("Streak").font(.system(size: 9)).foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(team.primaryColor.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1))
            )
            .shadow(color: team.primaryColor.opacity(isHovered ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// Standings table for macOS
struct MacStandingsTable: View {
    let teams: [Team]
    let games: [Game]
    
    struct ComputedStanding: Identifiable {
        let id: UUID
        let team: Team
        var wins: Int = 0
        var losses: Int = 0
        var pointsFor: Int = 0
        var pointsAgainst: Int = 0
        
        var winPercentage: Double {
            let total = wins + losses
            guard total > 0 else { return 0 }
            return Double(wins) / Double(total)
        }
        
        var pointDifferential: Int { pointsFor - pointsAgainst }
    }
    
    var computedStandings: [ComputedStanding] {
        var standingsDict: [UUID: ComputedStanding] = [:]
        for team in teams {
            standingsDict[team.id] = ComputedStanding(id: team.id, team: team)
        }
        for game in games where game.status == .finished {
            let homeWon = game.homeScore > game.awayScore
            if var homeSt = standingsDict[game.homeTeamId] {
                homeSt.pointsFor += game.homeScore
                homeSt.pointsAgainst += game.awayScore
                if homeWon { homeSt.wins += 1 } else { homeSt.losses += 1 }
                standingsDict[game.homeTeamId] = homeSt
            }
            if var awaySt = standingsDict[game.awayTeamId] {
                awaySt.pointsFor += game.awayScore
                awaySt.pointsAgainst += game.homeScore
                if homeWon { awaySt.losses += 1 } else { awaySt.wins += 1 }
                standingsDict[game.awayTeamId] = awaySt
            }
        }
        return standingsDict.values.sorted {
            if $0.winPercentage != $1.winPercentage { return $0.winPercentage > $1.winPercentage }
            return $0.pointDifferential > $1.pointDifferential
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("#").frame(width: 30, alignment: .center)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 40, alignment: .center)
                Text("L").frame(width: 40, alignment: .center)
                Text("PCT").frame(width: 60, alignment: .center)
                Text("+/-").frame(width: 50, alignment: .center)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Rows
            ForEach(Array(computedStandings.enumerated()), id: \.element.id) { index, standing in
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(index < 3 ? AppTheme.accentColor : AppTheme.textSecondary)
                        .frame(width: 30, alignment: .center)
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(standing.team.primaryColor)
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: standing.team.logoSystemImage).font(.system(size: 11, weight: .bold)).foregroundColor(.white))
                        Text(standing.team.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(standing.wins)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 40, alignment: .center)
                    
                    Text("\(standing.losses)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 40, alignment: .center)
                    
                    Text(String(format: "%.3f", standing.winPercentage))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 60, alignment: .center)
                    
                    Text(standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(standing.pointDifferential >= 0 ? .green : .red)
                        .frame(width: 50, alignment: .center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Mac Add Student Overlay
/// Frosted glass slide-in panel for adding a new student
struct MacAddStudentOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let onDismiss: () -> Void
    
    @State private var name = ""
    @State private var chineseName = ""
    @State private var birthdate = Date()
    @State private var avatarColor: AvatarColor = .blue
    @State private var selectedCategoryId: UUID?
    @State private var selectedCoachId: UUID?
    @State private var selectedProgramId: UUID?
    
    // Profile Image
    @State private var selectedImageData: Data?
    @State private var profileImageUrl: String?
    @State private var isUploadingImage = false
    
    // Physical Info
    @State private var heightCm = ""
    @State private var weightKg = ""
    @State private var handedness: Handedness = .right
    @State private var position = ""
    @State private var jerseyNumber = ""
    
    // Parent Info
    @State private var parentName = ""
    @State private var parentRelationship = "Parent"
    @State private var parentPhone = ""
    @State private var parentEmail = ""
    @State private var parentWechat = ""
    
    // Contract Info
    @State private var totalSessions = "24"
    @State private var pricePerSession = "200"
    @State private var contractSigned = false
    @State private var contractSignedDate = Date()
    @State private var jerseyGiven = false
    @State private var jerseySize = ""
    @State private var ballGiven = false
    
    private let jerseySizes = ["YS", "YM", "YL", "S", "M", "L", "XL"]
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Panel content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("Add Student")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: saveStudent) {
                        Text("Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isValid ? AppTheme.accentColor : AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // Form content
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile Photo Section
                        addStudentSection(title: "Profile Photo") {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    ZStack {
                                        if let imageData = selectedImageData, let nsImage = NSImage(data: imageData) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 80, height: 80)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.avatarColor(avatarColor))
                                                .frame(width: 80, height: 80)
                                                .overlay(
                                                    Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                                                        .font(.system(size: 28, weight: .bold))
                                                        .foregroundColor(.white)
                                                )
                                        }
                                        
                                        if isUploadingImage {
                                            Circle()
                                                .fill(Color.black.opacity(0.5))
                                                .frame(width: 80, height: 80)
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)
                                        }
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Button(action: selectPhoto) {
                                            Label(selectedImageData != nil ? "Change" : "Add Photo", systemImage: "photo")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isUploadingImage)
                                        
                                        if selectedImageData != nil {
                                            Button(action: removePhoto) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(isUploadingImage)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Basic Info Section
                        addStudentSection(title: "Basic Information") {
                            addStudentTextField(label: "Name *", text: $name)
                            addStudentTextField(label: "Chinese Name", text: $chineseName)
                            
                            HStack {
                                Text("Birthdate")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                DatePicker("", selection: $birthdate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 4)
                            
                            HStack {
                                Text("Avatar Color")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                HStack(spacing: 6) {
                                    ForEach(AvatarColor.allCases, id: \.self) { color in
                                        Circle()
                                            .fill(Color.avatarColor(color))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle()
                                                    .stroke(avatarColor == color ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                            .shadow(color: avatarColor == color ? Color.black.opacity(0.3) : .clear, radius: 2)
                                            .onTapGesture { avatarColor = color }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Assignment Section
                        addStudentSection(title: "Assignment") {
                            addStudentPicker(label: "Category", selection: $selectedCategoryId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(dataManager.ageCategories.filter { $0.isActive }) { category in
                                    HStack {
                                        Circle()
                                            .fill(category.color)
                                            .frame(width: 10, height: 10)
                                        Text("\(category.shortName) - \(category.name)")
                                    }
                                    .tag(category.id as UUID?)
                                }
                            }
                            
                            addStudentPicker(label: "Coach", selection: $selectedCoachId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                                    Text(coach.name).tag(coach.id as UUID?)
                                }
                            }
                            
                            addStudentPicker(label: "Program", selection: $selectedProgramId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(dataManager.programs.filter { $0.isActive }) { program in
                                    Text(program.name).tag(program.id as UUID?)
                                }
                            }
                        }
                        
                        // Physical Info Section
                        addStudentSection(title: "Physical Information") {
                            HStack(spacing: 12) {
                                addStudentTextField(label: "Height (cm)", text: $heightCm)
                                addStudentTextField(label: "Weight (kg)", text: $weightKg)
                            }
                            
                            addStudentPicker(label: "Handedness", selection: $handedness) {
                                ForEach(Handedness.allCases, id: \.self) { hand in
                                    Text(hand.displayName).tag(hand)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                addStudentTextField(label: "Position", text: $position)
                                addStudentTextField(label: "Jersey #", text: $jerseyNumber)
                            }
                        }
                        
                        // Parent Info Section
                        addStudentSection(title: "Parent/Guardian") {
                            addStudentTextField(label: "Parent Name", text: $parentName)
                            addStudentTextField(label: "Relationship", text: $parentRelationship)
                            addStudentTextField(label: "Phone", text: $parentPhone)
                            addStudentTextField(label: "Email", text: $parentEmail)
                            addStudentTextField(label: "WeChat ID", text: $parentWechat)
                        }
                        
                        // Contract Section
                        addStudentSection(title: "Contract") {
                            HStack(spacing: 12) {
                                addStudentTextField(label: "Sessions", text: $totalSessions)
                                addStudentTextField(label: "Price/Session (¥)", text: $pricePerSession)
                            }
                            
                            if let sessions = Int(totalSessions), let price = Double(pricePerSession) {
                                HStack {
                                    Text("Total Amount")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                    Text("¥\(Int(Double(sessions) * price))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.accentColor)
                                }
                                .padding(.vertical, 4)
                            }
                            
                            HStack {
                                Text("Contract Signed")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $contractSigned)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 2)
                            
                            if contractSigned {
                                HStack {
                                    Text("Signed Date")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                    DatePicker("", selection: $contractSignedDate, displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }
                        }
                        
                        // Equipment Section
                        addStudentSection(title: "Equipment") {
                            HStack {
                                Text("Jersey Given")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $jerseyGiven)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 2)
                            
                            if jerseyGiven {
                                addStudentPicker(label: "Jersey Size", selection: $jerseySize) {
                                    Text("Select Size").tag("")
                                    ForEach(jerseySizes, id: \.self) { size in
                                        Text(size).tag(size)
                                    }
                                }
                            }
                            
                            HStack {
                                Text("Ball Given")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $ballGiven)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(width: 420)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
        }
    }
    
    // MARK: - Helper Views
    private func addStudentSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .textCase(.uppercase)
            
            VStack(spacing: 8) {
                content()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    private func addStudentTextField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
        }
    }
    
    private func addStudentPicker<SelectionValue: Hashable, Content: View>(
        label: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Photo Actions
    private func selectPhoto() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Select a profile photo"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imageData = try Data(contentsOf: url)
                // Resize/compress image if needed
                if let nsImage = NSImage(data: imageData) {
                    if let resizedData = resizeImage(nsImage, maxSize: 400) {
                        selectedImageData = resizedData
                    } else {
                        selectedImageData = imageData
                    }
                }
            } catch {
                debugLog("❌ Failed to load image: \(error)")
            }
        }
    }
    
    private func removePhoto() {
        selectedImageData = nil
        profileImageUrl = nil
    }
    
    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData
    }
    
    // MARK: - Save Action
    private func saveStudent() {
        // Create student with a temporary ID so we can reference it for upload
        let studentId = UUID()
        
        var student = Student(
            id: studentId,
            name: name.trimmingCharacters(in: .whitespaces),
            chineseName: chineseName.isEmpty ? nil : chineseName,
            avatarColor: avatarColor,
            categoryId: selectedCategoryId,
            coachId: selectedCoachId,
            programId: selectedProgramId,
            birthdate: birthdate,
            profileImageUrl: profileImageUrl
        )
        
        let parentInfo = ParentInfo(
            name: parentName,
            relationship: parentRelationship,
            phone: parentPhone,
            email: parentEmail.isEmpty ? nil : parentEmail,
            wechatId: parentWechat.isEmpty ? nil : parentWechat
        )
        
        let sessions = Int(totalSessions) ?? 24
        let price = Double(pricePerSession) ?? 200
        let total = Double(sessions) * price
        
        let contractInfo = ContractInfo(
            totalSessions: sessions,
            pricePerSession: price,
            totalPaid: contractSigned ? total : 0
        )
        
        let player = Player(
            studentId: student.id,
            heightCm: Double(heightCm),
            weightKg: Double(weightKg),
            handedness: handedness,
            position: position.isEmpty ? nil : position,
            jerseyNumber: Int(jerseyNumber),
            parentInfo: parentInfo,
            contractInfo: contractInfo
        )
        
        let contract = Contract(
            studentId: student.id,
            contractNumber: 1,
            totalSessions: sessions,
            attendedSessions: 0,
            startDate: Date(),
            expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()),
            pricePerSession: price,
            totalAmount: total,
            amountPaid: contractSigned ? total : 0,
            isSigned: contractSigned,
            signedDate: contractSigned ? contractSignedDate : nil,
            jerseyGiven: jerseyGiven,
            jerseyGivenDate: jerseyGiven ? Date() : nil,
            ballGiven: ballGiven,
            ballGivenDate: ballGiven ? Date() : nil,
            jerseyNumber: Int(jerseyNumber),
            jerseySize: jerseySize.isEmpty ? nil : jerseySize
        )
        
        // If we have image data, upload it first
        if let imageData = selectedImageData {
            isUploadingImage = true
            Task {
                do {
                    let path = "students/\(studentId.uuidString).jpg"
                    let url = try await SupabaseManager.shared.uploadImage(imageData: imageData, path: path)
                    await MainActor.run {
                        student.profileImageUrl = url
                        dataManager.addStudent(student, player: player)
                        dataManager.addContract(contract)
                        isUploadingImage = false
                        HapticFeedback.notification(.success)
                        onDismiss()
                    }
                } catch {
                    debugLog("❌ Failed to upload image: \(error)")
                    await MainActor.run {
                        // Still save student without image
                        dataManager.addStudent(student, player: player)
                        dataManager.addContract(contract)
                        isUploadingImage = false
                        HapticFeedback.notification(.success)
                        onDismiss()
                    }
                }
            }
        } else {
            dataManager.addStudent(student, player: player)
            dataManager.addContract(contract)
            HapticFeedback.notification(.success)
            onDismiss()
        }
    }
}

// MARK: - Mac Student Detail Overlay
/// Frosted glass overlay that slides in from the right showing student details
struct MacStudentDetailOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let onDismiss: () -> Void
    
    @State private var showingEditSheet = false
    @State private var showingMeasurementSheet = false
    @State private var showingAddTouchpoint = false
    
    var player: Player? {
        dataManager.player(for: student.id)
    }
    
    var contract: Contract? {
        dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
    }
    
    var measurementSummary: MeasurementSummary {
        dataManager.measurementSummary(for: student.id)
    }
    
    var hasLeagueData: Bool {
        dataManager.teams.contains { $0.playerIds.contains(student.id) }
    }
    
    // Student Intelligence computed properties
    var scorecard: StudentIntelligence.HolisticScorecard {
        StudentIntelligence.generateScorecard(
            student: student,
            contract: contract,
            player: player,
            attendanceRecords: [],
            seasonStats: nil
        )
    }
    
    var churnRisk: StudentIntelligence.ChurnRiskAssessment {
        StudentIntelligence.analyzeChurnRisk(
            student: student,
            contract: contract,
            attendanceRecords: [],
            performanceStats: nil
        )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background - tap to dismiss
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Glassmorphic panel
            VStack(spacing: 0) {
                // Header with close button
                glassHeaderBar
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 20) {
                        // Profile header with overall score
                        glassProfileHeader
                        
                        // Holistic Scorecard
                        glassScorecardSection
                        
                        // Churn Risk Assessment
                        glassChurnRiskSection
                        
                        // Quick stats row
                        glassQuickStatsRow
                        
                        // Basic info card
                        glassBasicInfoCard
                        
                        // Physical stats
                        if let player = player {
                            glassPhysicalStatsCard(player)
                        }
                        
                        // Skills evaluation
                        if let player = player {
                            glassSkillsCard(player)
                        }
                        
                        // Parent/Guardian info
                        if let player = player {
                            glassParentInfoCard(player)
                        }
                        
                        // Coach notes
                        if let player = player, let notes = player.coachNotes, !notes.isEmpty {
                            glassNotesCard(notes)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(width: 480)
            .background(GlassColors.background)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditStudentView(student: student, player: player)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingMeasurementSheet) {
            QuickMeasurementView(student: student, sessionId: nil)
                .environmentObject(dataManager)
        }
    }
    
    // MARK: - Glass Header Bar
    private var glassHeaderBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Intelligence Profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            Menu {
                Button(action: { showingEditSheet = true }) {
                    Label("Edit Student", systemImage: "pencil")
                }
                Button(action: { showingMeasurementSheet = true }) {
                    Label("Record Measurements", systemImage: "ruler")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
    }
    
    // MARK: - Glass Profile Header
    private var glassProfileHeader: some View {
        VStack(spacing: 16) {
            // Avatar with glow
            ZStack {
                Circle()
                    .fill(Color.avatarColor(student.avatarColor).opacity(0.3))
                    .frame(width: 110, height: 110)
                    .blur(radius: 20)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.avatarColor(student.avatarColor), Color.avatarColor(student.avatarColor).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                
                Text(student.initials)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text(student.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                if let chineseName = student.chineseName {
                    Text(chineseName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack(spacing: 12) {
                    if let age = student.age {
                        Label("\(age) years", systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    if let player = player, let position = player.position {
                        Text(position)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(GlassColors.accentCyan)
                            .cornerRadius(12)
                    }
                    
                    if let player = player, let jersey = player.jerseyNumber {
                        Text("#\(jersey)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            
            // Overall score badge
            HStack(spacing: 8) {
                Image(systemName: scorecard.trend.icon)
                    .font(.system(size: 12))
                Text("\(Int(scorecard.overallScore))% Overall")
                    .font(.system(size: 14, weight: .semibold))
                Text("• \(scorecard.trend.rawValue)")
                    .font(.system(size: 12))
            }
            .foregroundColor(scorecard.trend.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(scorecard.trend.color.opacity(0.15))
            .cornerRadius(20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Glass Scorecard Section (Service, Performance, Financials)
    @State private var selectedMacScoreType: MacScoreType? = nil
    
    enum MacScoreType: String, CaseIterable {
        case service = "Service"
        case performance = "Performance"
        case financials = "Financials"
        
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
            case .performance: return .cyan
            case .financials: return .green
            }
        }
    }
    
    private var glassScorecardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STUDENT INTELLIGENCE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            
            HStack(spacing: 12) {
                glassScoreCell(type: .service, score: serviceScoreMac, needsAttention: serviceNeedsAttentionMac)
                glassScoreCell(type: .performance, score: performanceScoreMac, needsAttention: performanceNeedsAttentionMac)
                glassScoreCell(type: .financials, score: financialsScoreMac, needsAttention: financialsNeedsAttentionMac)
            }
            
            // Expanded detail when a score is selected
            if let selected = selectedMacScoreType {
                glassScoreDetailPanel(for: selected)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedMacScoreType)
    }
    
    private func glassScoreCell(type: MacScoreType, score: Double, needsAttention: Bool) -> some View {
        let isSelected = selectedMacScoreType == type
        let displayColor = needsAttention ? Color.red : type.color
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedMacScoreType = selectedMacScoreType == type ? nil : type
            }
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : type.icon)
                        .font(.system(size: 12))
                        .foregroundColor(displayColor)
                    Text("\(Int(score))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text(type.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(needsAttention ? Color.red.opacity(0.2) : (isSelected ? type.color.opacity(0.2) : Color.white.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(needsAttention ? Color.red.opacity(0.5) : (isSelected ? type.color.opacity(0.4) : Color.clear), lineWidth: needsAttention ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func glassScoreDetailPanel(for type: MacScoreType) -> some View {
        let needsAttention = macScoreNeedsAttention(for: type)
        let displayColor = needsAttention ? Color.red : type.color
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : type.icon)
                    .foregroundColor(displayColor)
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if needsAttention {
                    Text("Needs Attention")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .cornerRadius(6)
                }
                
                Button(action: { selectedMacScoreType = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            // Action recommendation text
            Text(macMeaningText(for: type))
                .font(.system(size: 11))
                .foregroundColor(needsAttention ? .red : .white.opacity(0.7))
                .lineSpacing(2)
                .padding(needsAttention ? 8 : 0)
                .background(needsAttention ? Color.red.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(needsAttention ? Color.red.opacity(0.1) : type.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(needsAttention ? Color.red.opacity(0.3) : type.color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Mac Score Calculations
    private var serviceScoreMac: Double {
        var score: Double = 50
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days <= 7 { score += 50 }
            else if days <= 14 { score += 35 }
            else if days <= 21 { score += 15 }
            else { score -= 10 }
        } else { score -= 20 }
        return min(100, max(0, score))
    }
    
    private var serviceNeedsAttentionMac: Bool {
        if let lastContact = student.lastParentContact {
            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            if days > 14 { return true }
        } else { return true }
        return serviceScoreMac < 50
    }
    
    private var performanceScoreMac: Double {
        var score: Double = 50
        if let player = player {
            score += player.skills.overallRating * 5
        }
        return min(100, max(0, score))
    }
    
    private var performanceNeedsAttentionMac: Bool {
        if player == nil { return true }
        if let player = player, player.skills.overallRating < 4 { return true }
        return performanceScoreMac < 50
    }
    
    private var financialsScoreMac: Double {
        guard let contract = contract else { return 0 }
        var score: Double = 30
        let remaining = contract.remainingSessions ?? 0
        let sessionRatio = Double(remaining) / Double(max(contract.totalSessions, 1))
        if sessionRatio > 0.5 { score += 40 }
        else if sessionRatio > 0.3 { score += 25 }
        else if sessionRatio > 0.1 { score += 10 }
        if contract.isFullyPaid { score += 20 }
        let attendanceRate = contract.totalSessions > 0 ? Double(contract.attendedSessions) / Double(contract.totalSessions) : 0
        if attendanceRate >= 0.8 { score += 20 }
        else if attendanceRate >= 0.5 { score += 10 }
        return min(100, max(0, score))
    }
    
    private var financialsNeedsAttentionMac: Bool {
        guard let contract = contract else { return true }
        if (contract.remainingSessions ?? 0) <= 5 { return true }
        return financialsScoreMac < 50
    }
    
    private func macScoreNeedsAttention(for type: MacScoreType) -> Bool {
        switch type {
        case .service: return serviceNeedsAttentionMac
        case .performance: return performanceNeedsAttentionMac
        case .financials: return financialsNeedsAttentionMac
        }
    }
    
    private func macMeaningText(for type: MacScoreType) -> String {
        switch type {
        case .service:
            if serviceNeedsAttentionMac {
                return "⚠️ ACTION: Contact parents to update them on their child's progress. Share photos/videos and gather feedback to reduce churn risk."
            }
            return "Good parent engagement. Regular communication builds trust and retention."
        case .performance:
            if performanceNeedsAttentionMac {
                return "⚠️ ACTION: Schedule skill evaluation, adjust training plan, and set achievable goals. Consider 1-on-1 coaching."
            }
            return "Strong skill development. Student is progressing well."
        case .financials:
            if financialsNeedsAttentionMac {
                return "⚠️ ACTION: Contract renewal needed. Sessions running low. Initiate renewal conversation."
            }
            return "Healthy financial status with good session balance."
        }
    }
    
    // MARK: - Glass Churn Risk Section
    private var glassChurnRiskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CHURN RISK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: churnRisk.level.icon)
                        .font(.system(size: 12))
                    Text(churnRisk.level.rawValue)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(churnRisk.level.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(churnRisk.level.color.opacity(0.15))
                .cornerRadius(8)
            }
            
            // Risk factors
            if !churnRisk.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(churnRisk.factors.prefix(3), id: \.name) { factor in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(factor.impact < 0 ? GlassColors.accentRed : GlassColors.accentGreen)
                                .frame(width: 6, height: 6)
                            Text(factor.description)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            
            // Recommendations
            if !churnRisk.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendations")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    ForEach(churnRisk.recommendations, id: \.self) { rec in
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(GlassColors.accentYellow)
                            Text(rec)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(churnRisk.level.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Glass Quick Stats Row
    private var glassQuickStatsRow: some View {
        HStack(spacing: 12) {
            if let player = player {
                glassQuickStatPill(value: player.heightCm.map { String(format: "%.0f", $0) } ?? "--", label: "Height", unit: "cm", color: GlassColors.accentCyan)
                glassQuickStatPill(value: player.weightKg.map { String(format: "%.1f", $0) } ?? "--", label: "Weight", unit: "kg", color: GlassColors.accentGreen)
                glassQuickStatPill(value: player.wingspanCm.map { String(format: "%.0f", $0) } ?? "--", label: "Wingspan", unit: "cm", color: GlassColors.accentOrange)
            } else {
                glassQuickStatPill(value: "--", label: "Height", unit: "cm", color: GlassColors.accentCyan)
                glassQuickStatPill(value: "--", label: "Weight", unit: "kg", color: GlassColors.accentGreen)
                glassQuickStatPill(value: "--", label: "Wingspan", unit: "cm", color: GlassColors.accentOrange)
            }
        }
    }
    
    private func glassQuickStatPill(value: String, label: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.15))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Glass Basic Info Card
    private var glassBasicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Basic Information", systemImage: "person.text.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 10) {
                if let birthdate = student.birthdate {
                    glassInfoRow(label: "Birthdate", value: birthdate.formatted(date: .long, time: .omitted), icon: "calendar")
                }
                
                if let categoryId = student.categoryId,
                   let category = dataManager.ageCategories.first(where: { $0.id == categoryId }) {
                    HStack {
                        Label("Category", systemImage: "tag")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(category.color).frame(width: 8, height: 8)
                            Text("\(category.shortName) - \(category.name)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                if let coachId = student.coachId,
                   let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                    HStack {
                        Label("Coach", systemImage: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 10))
                                .foregroundColor(coach.role.color)
                            Text(coach.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                if let programId = student.programId,
                   let program = dataManager.programs.first(where: { $0.id == programId }) {
                    HStack {
                        Label("Program", systemImage: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: program.mascot.icon)
                                .font(.system(size: 10))
                                .foregroundColor(program.mascotColor)
                            Text(program.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func glassInfoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Glass Physical Stats Card
    private func glassPhysicalStatsCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Physical Stats", systemImage: "figure.stand")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 10) {
                glassInfoRow(label: "Handedness", value: player.handedness.rawValue.capitalized, icon: "hand.raised")
                
                if let height = player.heightCm {
                    glassInfoRow(label: "Height", value: String(format: "%.1f cm", height), icon: "arrow.up.and.down")
                }
                
                if let weight = player.weightKg {
                    glassInfoRow(label: "Weight", value: String(format: "%.1f kg", weight), icon: "scalemass")
                }
                
                if let wingspan = player.wingspanCm {
                    glassInfoRow(label: "Wingspan", value: String(format: "%.1f cm", wingspan), icon: "arrow.left.and.right")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Glass Skills Card
    private func glassSkillsCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Skills Evaluation", systemImage: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                glassSkillRow(name: "Shooting", value: player.skills.shooting)
                glassSkillRow(name: "Ball Handling", value: player.skills.ballHandling)
                glassSkillRow(name: "Defense", value: player.skills.defense)
                glassSkillRow(name: "Basketball IQ", value: player.skills.basketballIQ)
                glassSkillRow(name: "Athleticism", value: player.skills.athleticism)
                glassSkillRow(name: "Teamwork", value: player.skills.teamwork)
                glassSkillRow(name: "Coachability", value: player.skills.coachability)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func glassSkillRow(name: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Circle()
                        .fill(i <= value ? GlassColors.accentCyan : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - Glass Parent Info Card
    private func glassParentInfoCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Parent/Guardian", systemImage: "person.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 10) {
                if !player.parentInfo.name.isEmpty {
                    glassInfoRow(label: "Name", value: player.parentInfo.name, icon: "person")
                }
                
                if !player.parentInfo.phone.isEmpty {
                    glassInfoRow(label: "Phone", value: player.parentInfo.phone, icon: "phone")
                }
                
                if let email = player.parentInfo.email, !email.isEmpty {
                    glassInfoRow(label: "Email", value: email, icon: "envelope")
                }
                
                if !player.parentInfo.relationship.isEmpty {
                    glassInfoRow(label: "Relationship", value: player.parentInfo.relationship, icon: "heart")
                }
            }
            
            // Secondary parent
            if let secondary = player.secondaryParentInfo, !secondary.name.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 4)
                
                Text("Secondary Contact")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                
                VStack(spacing: 10) {
                    glassInfoRow(label: "Name", value: secondary.name, icon: "person")
                    if !secondary.phone.isEmpty {
                        glassInfoRow(label: "Phone", value: secondary.phone, icon: "phone")
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Glass Notes Card
    private func glassNotesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coach Notes", systemImage: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            Text(notes)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Stat leader card for macOS
struct MacStatLeaderCard: View {
    let title: String
    let stat: String
    let leaders: [(Student, Double)]
    let dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            if leaders.isEmpty {
                Text("No data yet")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(leaders.enumerated()), id: \.element.0.id) { index, item in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(index == 0 ? AppTheme.accentColor : AppTheme.textSecondary)
                                .frame(width: 20)
                            
                            ZStack {
                                Circle()
                                    .fill(Color.avatarColor(item.0.avatarColor))
                                    .frame(width: 28, height: 28)
                                Text(item.0.initials)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Text(item.0.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(String(format: "%.1f", item.1))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Text(stat)
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(index == 0 ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Mac Students List Overlay (Finder Column View Style)
/// Frosted glass overlay with column view - list on left, detail on right
struct MacStudentsListOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let onDismiss: () -> Void
    let onAddStudent: () -> Void
    var onImport: (() -> Void)? = nil
    
    @State private var searchText = ""
    @State private var selectedStudent: Student? = nil
    
    var filteredStudents: [Student] {
        if searchText.isEmpty {
            return dataManager.students
        }
        return dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Column view container
            HStack(spacing: 0) {
                // Left column: Students list
                studentsListColumn
                
                // Divider between columns
                if selectedStudent != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                }
                
                // Right column: Student detail (appears when selected)
                if let student = selectedStudent {
                    studentDetailColumn(student)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: selectedStudent != nil ? 780 : 340)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
            .animation(.easeInOut(duration: 0.25), value: selectedStudent?.id)
        }
    }
    
    // MARK: - Students List Column
    private var studentsListColumn: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Students")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                // Import button
                if let onImport = onImport {
                    Button(action: onImport) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18))
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                    .help("Import from CSV")
                }
                
                Button(action: onAddStudent) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textTertiary)
                    .font(.system(size: 12))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 14)
            
            Divider()
                .padding(.top, 10)
            
            // Students list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredStudents.enumerated()), id: \.element.id) { _, student in
                        studentRow(student)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 340)
    }
    
    private func studentRow(_ student: Student) -> some View {
        MacStudentListRow(
            student: student,
            program: dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) },
            isSelected: selectedStudent?.id == student.id,
            onDelete: {
                // Clear selection if this student was selected
                if selectedStudent?.id == student.id {
                    selectedStudent = nil
                }
                // Delete associated player and contracts
                if let player = dataManager.player(for: student.id) {
                    // Remove from teams
                    for team in dataManager.teams where team.playerIds.contains(student.id) {
                        var updatedTeam = team
                        updatedTeam.playerIds.removeAll { $0 == student.id }
                        dataManager.updateTeam(updatedTeam)
                    }
                }
                // Delete contracts for this student
                let contracts = dataManager.contracts.filter { $0.studentId == student.id }
                for contract in contracts {
                    dataManager.deleteContract(contract)
                }
                // Delete the student
                dataManager.deleteStudent(student)
            }
        ) {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedStudent = student
            }
        }
    }
    
    // MARK: - Student Detail Column
    private func studentDetailColumn(_ student: Student) -> some View {
        MacStudentDetailColumnView(student: student)
            .environmentObject(dataManager)
            .frame(width: 440)
    }
}

// MARK: - Mac Student Detail Column View
/// Inline-editable student detail view for column layout with profile picture, league stats, teams/programs
struct MacStudentDetailColumnView: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    
    @State private var isEditing = false
    @State private var showingMeasurementSheet = false
    @State private var showingImagePicker = false
    
    // Editable fields
    @State private var editName: String = ""
    @State private var editChineseName: String = ""
    @State private var editBirthdate: Date = Date()
    @State private var editAvatarColor: AvatarColor = .blue
    @State private var editCategoryId: UUID? = nil
    @State private var editCoachId: UUID? = nil
    @State private var editPosition: String = ""
    @State private var editHandedness: Handedness = .right
    @State private var editHeightCm: String = ""
    @State private var editWeightKg: String = ""
    @State private var editWingspanCm: String = ""
    @State private var editParentName: String = ""
    @State private var editParentPhone: String = ""
    @State private var editParentEmail: String = ""
    
    var player: Player? {
        dataManager.player(for: student.id)
    }
    
    var seasonStats: SeasonStats? {
        dataManager.seasonStats.first { $0.playerId == student.id }
    }
    
    var studentTeams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(student.id) }
    }
    
    var studentPrograms: [Program] {
        dataManager.programs.filter { program in
            dataManager.enrollments.contains { $0.programId == program.id && $0.studentId == student.id }
        }
    }
    
    var enrollmentDate: Date? {
        student.createdAt
    }
    
    var tenureString: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: student.createdAt, to: Date())
        if let years = components.year, years > 0 {
            return years == 1 ? "1 year" : "\(years) years"
        } else if let months = components.month, months > 0 {
            return months == 1 ? "1 month" : "\(months) months"
        } else if let days = components.day {
            return days <= 1 ? "Just started" : "\(days) days"
        }
        return "Just started"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with edit toggle
            HStack {
                Text("Profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    
                    Button("Save") {
                        saveChanges()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.accentColor)
                } else {
                    Button(action: { showingMeasurementSheet = true }) {
                        Image(systemName: "ruler")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Record Measurements")
                    
                    Button(action: { startEditing() }) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Profile")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Profile header with photo
                    profileHeaderWithPhoto
                    
                    // Quick stats (physical measurements)
                    quickStatsRow
                    
                    // League stats (if any)
                    if seasonStats != nil {
                        leagueStatsCard
                    }
                    
                    // Teams & Programs
                    if !studentTeams.isEmpty || !studentPrograms.isEmpty {
                        teamsAndProgramsCard
                    }
                    
                    // Basic info
                    basicInfoCard
                    
                    // Physical stats
                    physicalStatsCard
                    
                    // Skills
                    if let player = player {
                        skillsCard(player)
                    }
                    
                    // Contract & Enrollment
                    contractAndEnrollmentCard
                    
                    // Parent info
                    parentInfoCard
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showingMeasurementSheet) {
            QuickMeasurementView(student: student, sessionId: nil)
                .environmentObject(dataManager)
        }
        .fileImporter(isPresented: $showingImagePicker, allowedContentTypes: [.image]) { result in
            handleImageSelection(result)
        }
    }
    
    // MARK: - Start/Save Editing
    private func startEditing() {
        editName = student.name
        editChineseName = student.chineseName ?? ""
        editBirthdate = student.birthdate ?? Date()
        editAvatarColor = student.avatarColor
        editCategoryId = student.categoryId
        editCoachId = student.coachId
        
        if let player = player {
            editPosition = player.position ?? ""
            editHandedness = player.handedness
            editHeightCm = player.heightCm.map { String(format: "%.1f", $0) } ?? ""
            editWeightKg = player.weightKg.map { String(format: "%.1f", $0) } ?? ""
            editWingspanCm = player.wingspanCm.map { String(format: "%.1f", $0) } ?? ""
            editParentName = player.parentInfo.name
            editParentPhone = player.parentInfo.phone
            editParentEmail = player.parentInfo.email ?? ""
        }
        
        isEditing = true
    }
    
    private func saveChanges() {
        var updatedStudent = student
        updatedStudent.name = editName
        updatedStudent.chineseName = editChineseName.isEmpty ? nil : editChineseName
        updatedStudent.birthdate = editBirthdate
        updatedStudent.avatarColor = editAvatarColor
        updatedStudent.categoryId = editCategoryId
        updatedStudent.coachId = editCoachId
        updatedStudent.updatedAt = Date()
        
        dataManager.updateStudent(updatedStudent)
        
        if var updatedPlayer = player {
            updatedPlayer.position = editPosition.isEmpty ? nil : editPosition
            updatedPlayer.handedness = editHandedness
            updatedPlayer.heightCm = Double(editHeightCm)
            updatedPlayer.weightKg = Double(editWeightKg)
            updatedPlayer.wingspanCm = Double(editWingspanCm)
            updatedPlayer.parentInfo.name = editParentName
            updatedPlayer.parentInfo.phone = editParentPhone
            updatedPlayer.parentInfo.email = editParentEmail
            updatedPlayer.updatedAt = Date()
            
            dataManager.updatePlayer(updatedPlayer)
        }
        
        isEditing = false
    }
    
    private func handleImageSelection(_ result: Result<URL, Error>) {
        // TODO: Implement image upload to Supabase Storage
        // For now, just log the selection
        switch result {
        case .success(let url):
            debugLog("Selected image: \(url)")
            // Upload to Supabase and update student.profileImageUrl
        case .failure(let error):
            debugLog("Image selection error: \(error)")
        }
    }
    
    // MARK: - Profile Header with Photo
    private var profileHeaderWithPhoto: some View {
        HStack(spacing: 14) {
            // Profile photo or avatar
            ZStack {
                if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                        case .failure, .empty:
                            avatarCircle
                        @unknown default:
                            avatarCircle
                        }
                    }
                } else {
                    avatarCircle
                }
                
                // Camera button overlay for editing
                if isEditing {
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 70, height: 70)
                    
                    Button(action: { showingImagePicker = true }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .shadow(color: Color.avatarColor(student.avatarColor).opacity(0.3), radius: 8, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Name", text: $editName)
                        .font(.system(size: 16, weight: .bold))
                        .textFieldStyle(.plain)
                    
                    TextField("Chinese Name", text: $editChineseName)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text(student.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if let chineseName = student.chineseName {
                        Text(chineseName)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                HStack(spacing: 8) {
                    if let age = student.age {
                        Text("\(age) years")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    if let player = player, let position = player.position, !isEditing {
                        Text(position)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.accentColor)
                            .cornerRadius(10)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.avatarColor(isEditing ? editAvatarColor : student.avatarColor), Color.avatarColor(isEditing ? editAvatarColor : student.avatarColor).opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 70, height: 70)
            
            Text(student.initials)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: 8) {
            if isEditing {
                editableStatPill(value: $editHeightCm, label: "Height", unit: "cm", color: .blue)
                editableStatPill(value: $editWeightKg, label: "Weight", unit: "kg", color: .green)
                editableStatPill(value: $editWingspanCm, label: "Wingspan", unit: "cm", color: .orange)
            } else if let player = player {
                quickStatPill(value: player.heightCm.map { String(format: "%.0f", $0) } ?? "--", label: "Height", unit: "cm", color: .blue)
                quickStatPill(value: player.weightKg.map { String(format: "%.1f", $0) } ?? "--", label: "Weight", unit: "kg", color: .green)
                quickStatPill(value: player.wingspanCm.map { String(format: "%.0f", $0) } ?? "--", label: "Wingspan", unit: "cm", color: .orange)
            } else {
                quickStatPill(value: "--", label: "Height", unit: "cm", color: .blue)
                quickStatPill(value: "--", label: "Weight", unit: "kg", color: .green)
                quickStatPill(value: "--", label: "Wingspan", unit: "cm", color: .orange)
            }
        }
    }
    
    private func quickStatPill(value: String, label: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func editableStatPill(value: Binding<String>, label: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                TextField("--", text: value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - League Stats Card
    private var leagueStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("League Stats", systemImage: "sportscourt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            if let stats = seasonStats {
                HStack(spacing: 6) {
                    leagueStatBox(value: String(format: "%.1f", stats.ppg), label: "PPG", color: .orange)
                    leagueStatBox(value: String(format: "%.1f", stats.rpg), label: "RPG", color: .blue)
                    leagueStatBox(value: String(format: "%.1f", stats.apg), label: "APG", color: .green)
                    leagueStatBox(value: "\(stats.gamesPlayed)", label: "GP", color: .purple)
                }
                
                HStack(spacing: 6) {
                    leagueStatBox(value: String(format: "%.1f", stats.spg), label: "SPG", color: .teal)
                    leagueStatBox(value: String(format: "%.1f", stats.bpg), label: "BPG", color: .red)
                    leagueStatBox(value: String(format: "%.1f", stats.mpg), label: "MPG", color: .gray)
                    leagueStatBox(value: "\(stats.totalPoints)", label: "PTS", color: .indigo)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func leagueStatBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Teams & Programs Card
    private var teamsAndProgramsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Teams & Programs", systemImage: "person.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 6) {
                ForEach(studentTeams) { team in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(team.primaryColor)
                            .frame(width: 8, height: 8)
                        Text(team.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("Team")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                ForEach(studentPrograms) { program in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(program.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("Program")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Basic Info Card
    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Basic Info", systemImage: "person.text.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                if isEditing {
                    HStack {
                        Text("Birthdate")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        DatePicker("", selection: $editBirthdate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    
                    HStack {
                        Text("Avatar Color")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $editAvatarColor) {
                            ForEach(AvatarColor.allCases, id: \.self) { color in
                                HStack {
                                    Circle().fill(Color.avatarColor(color)).frame(width: 10, height: 10)
                                    Text(color.displayName)
                                }
                                .tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Category")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $editCategoryId) {
                            Text("None").tag(nil as UUID?)
                            ForEach(dataManager.ageCategories) { category in
                                Text(category.shortName).tag(category.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Coach")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $editCoachId) {
                            Text("None").tag(nil as UUID?)
                            ForEach(dataManager.staffCoaches) { coach in
                                Text(coach.name).tag(coach.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                } else {
                    if let birthdate = student.birthdate {
                        infoRow(label: "Birthdate", value: birthdate.formatted(date: .abbreviated, time: .omitted))
                    }
                    
                    if let categoryId = student.categoryId,
                       let category = dataManager.ageCategories.first(where: { $0.id == categoryId }) {
                        HStack {
                            Text("Category")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(category.color).frame(width: 6, height: 6)
                                Text(category.shortName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                        }
                    }
                    
                    if let coachId = student.coachId,
                       let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                        infoRow(label: "Coach", value: coach.name)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
        }
    }
    
    // MARK: - Physical Stats Card
    private var physicalStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Physical", systemImage: "figure.stand")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                if isEditing {
                    HStack {
                        Text("Position")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        TextField("e.g. PG, SG", text: $editPosition)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Handedness")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $editHandedness) {
                            ForEach(Handedness.allCases, id: \.self) { hand in
                                Text(hand.rawValue.capitalized).tag(hand)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                } else if let player = player {
                    if let position = player.position {
                        infoRow(label: "Position", value: position)
                    }
                    infoRow(label: "Handedness", value: player.handedness.rawValue.capitalized)
                    if let height = player.heightCm {
                        infoRow(label: "Height", value: String(format: "%.1f cm", height))
                    }
                    if let weight = player.weightKg {
                        infoRow(label: "Weight", value: String(format: "%.1f kg", weight))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Skills Card
    private func skillsCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Skills", systemImage: "star.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                skillRow(name: "Shooting", value: player.skills.shooting)
                skillRow(name: "Defense", value: player.skills.defense)
                skillRow(name: "Ball Handling", value: player.skills.ballHandling)
                skillRow(name: "Basketball IQ", value: player.skills.basketballIQ)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func skillRow(name: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    Circle()
                        .fill(i <= value ? AppTheme.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(5)
    }
    
    // MARK: - Contract & Enrollment Card
    private var contractAndEnrollmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Contract & Enrollment", systemImage: "doc.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                // Enrollment info
                infoRow(label: "Enrolled", value: student.createdAt.formatted(date: .abbreviated, time: .omitted))
                infoRow(label: "Tenure", value: tenureString)
                
                Divider()
                
                // Contract info
                if let contract = dataManager.currentContract(for: student.id) {
                    infoRow(label: "Sessions", value: contract.isPayAsYouGo ? "PAYG" : "\(contract.attendedSessions)/\(contract.totalSessions)")
                    if contract.pricePerSession > 0 {
                        infoRow(label: "Per Session", value: String(format: "$%.0f", contract.pricePerSession))
                    }
                }
                
                // Active contracts count
                let activeContracts = dataManager.contracts.filter { $0.studentId == student.id && $0.status == .active }
                if !activeContracts.isEmpty {
                    infoRow(label: "Active Contracts", value: "\(activeContracts.count)")
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Parent Info Card
    private var parentInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Parent/Guardian", systemImage: "person.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                if isEditing {
                    HStack {
                        Text("Name")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        TextField("Parent Name", text: $editParentName)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                    }
                    
                    HStack {
                        Text("Phone")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        TextField("Phone", text: $editParentPhone)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                    }
                    
                    HStack {
                        Text("Email")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        TextField("Email", text: $editParentEmail)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                    }
                } else if let player = player {
                    if !player.parentInfo.name.isEmpty {
                        infoRow(label: "Name", value: player.parentInfo.name)
                    }
                    if !player.parentInfo.phone.isEmpty {
                        infoRow(label: "Phone", value: player.parentInfo.phone)
                    }
                    if let email = player.parentInfo.email, !email.isEmpty {
                        infoRow(label: "Email", value: email)
                    }
                    
                    if player.parentInfo.name.isEmpty && player.parentInfo.phone.isEmpty {
                        Text("No parent info")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .italic()
                    }
                } else {
                    Text("No parent info")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .italic()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Mac Contracts List Overlay (Finder Column View Style)
/// Frosted glass overlay with column view - list on left, detail on right
struct MacContractsListOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let onDismiss: () -> Void
    
    @State private var filterStatus: ContractStatus? = nil
    @State private var selectedContract: Contract? = nil
    
    var filteredContracts: [Contract] {
        if let status = filterStatus {
            return dataManager.contracts.filter { $0.status == status }
        }
        return dataManager.contracts
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Column view container
            HStack(spacing: 0) {
                // Left column: Contracts list
                contractsListColumn
                
                // Divider between columns
                if selectedContract != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                }
                
                // Right column: Contract detail (appears when selected)
                if let contract = selectedContract {
                    contractDetailColumn(contract)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: selectedContract != nil ? 780 : 380)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
            .animation(.easeInOut(duration: 0.25), value: selectedContract?.id)
        }
    }
    
    // MARK: - Contracts List Column
    private var contractsListColumn: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Contracts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Color.clear.frame(width: 20, height: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterPill(title: "All", status: nil)
                    ForEach(ContractStatus.allCases, id: \.self) { status in
                        filterPill(title: status.rawValue, status: status)
                    }
                }
                .padding(.horizontal, 14)
            }
            
            Divider()
                .padding(.top, 10)
            
            // Contracts list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredContracts.enumerated()), id: \.element.id) { _, contract in
                        contractRow(contract)
                    }
                    
                    if filteredContracts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 28))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("No contracts")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 380)
    }
    
    private func filterPill(title: String, status: ContractStatus?) -> some View {
        Button(action: { filterStatus = status }) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(filterStatus == status ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filterStatus == status ? AppTheme.accentColor : Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func contractRow(_ contract: Contract) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        let isSelected = selectedContract?.id == contract.id
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedContract = contract
            }
        }) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(Color(hex: contract.status.color))
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(student?.name ?? "Unknown")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(contract.attendedSessions)/\(contract.totalSessions) sessions")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                Text(contract.totalAmount, format: .currency(code: "USD"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Contract Detail Column
    private func contractDetailColumn(_ contract: Contract) -> some View {
        MacContractDetailColumnView(contract: contract)
            .environmentObject(dataManager)
            .frame(width: 400)
    }
}

// MARK: - Mac Contract Detail Column View
/// Compact contract detail view for column layout
struct MacContractDetailColumnView: View {
    @EnvironmentObject var dataManager: DataManager
    let contract: Contract
    
    var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Student header
                    if let student = student {
                        studentHeader(student)
                    }
                    
                    // Status card
                    statusCard
                    
                    // Sessions progress
                    sessionsCard
                    
                    // Financial info
                    financialCard
                    
                    // Dates
                    datesCard
                    
                    // Notes
                    if let notes = contract.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                }
                .padding(16)
            }
        }
    }
    
    private func studentHeader(_ student: Student) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.avatarColor(student.avatarColor), Color.avatarColor(student.avatarColor).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: Color.avatarColor(student.avatarColor).opacity(0.3), radius: 6, y: 3)
                
                Text(student.initials)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(contract.contractLabel)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var statusCard: some View {
        HStack {
            Label("Status", systemImage: "checkmark.seal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: contract.status.color))
                    .frame(width: 8, height: 8)
                
                Text(contract.status.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: contract.status.color))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sessions", systemImage: "calendar.badge.checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 10) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppTheme.accentColor)
                            .frame(width: geo.size.width * contract.progressPercentage, height: 6)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Attended")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.attendedSessions)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 1) {
                        Text("Remaining")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.remainingSessions)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Total")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.totalSessions)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var financialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Financial", systemImage: "dollarsign.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                infoRow(label: "Total Value", value: contract.totalAmount.formatted(.currency(code: "USD")))
                infoRow(label: "Amount Paid", value: contract.amountPaid.formatted(.currency(code: "USD")), valueColor: .green)
                infoRow(label: "Balance Due", value: contract.outstandingBalance.formatted(.currency(code: "USD")), valueColor: contract.outstandingBalance > 0 ? .orange : .green)
                
                Divider()
                
                infoRow(label: "Per Session", value: contract.pricePerSession.formatted(.currency(code: "USD")))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dates", systemImage: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 8) {
                if let startDate = contract.startDate {
                    infoRow(label: "Start Date", value: startDate.formatted(date: .abbreviated, time: .omitted))
                }
                
                if let expiryDate = contract.expiryDate {
                    infoRow(label: "Expiry Date", value: expiryDate.formatted(date: .abbreviated, time: .omitted))
                }
                
                infoRow(label: "Created", value: contract.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", systemImage: "note.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(notes)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func infoRow(label: String, value: String, valueColor: Color = AppTheme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Mac Contract Detail Overlay
/// Frosted glass overlay showing contract details
struct MacContractDetailOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let contract: Contract
    let onDismiss: () -> Void
    
    var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("Contract Details")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Spacer()
                    
                    Color.clear.frame(width: 20, height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Student header
                        if let student = student {
                            studentHeader(student)
                        }
                        
                        // Status card
                        statusCard
                        
                        // Sessions progress
                        sessionsCard
                        
                        // Financial info
                        financialCard
                        
                        // Dates
                        datesCard
                        
                        // Notes
                        if let notes = contract.notes, !notes.isEmpty {
                            notesCard(notes)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(width: 420)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
        }
    }
    
    private func studentHeader(_ student: Student) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.avatarColor(student.avatarColor), Color.avatarColor(student.avatarColor).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.avatarColor(student.avatarColor).opacity(0.3), radius: 8, y: 4)
                
                Text(student.initials)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let age = student.age {
                    Text("\(age) years old")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Status", systemImage: "checkmark.seal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            HStack {
                Circle()
                    .fill(Color(hex: contract.status.color))
                    .frame(width: 12, height: 12)
                
                Text(contract.status.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: contract.status.color))
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sessions", systemImage: "calendar.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("\(contract.attendedSessions) / \(contract.totalSessions)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.accentColor)
                            .frame(width: geo.size.width * contract.progressPercentage, height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completed")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.attendedSessions)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("Remaining")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.remainingSessions)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(contract.totalSessions)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var financialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Financial", systemImage: "dollarsign.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 10) {
                HStack {
                    Text("Total Value")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.totalAmount, format: .currency(code: "USD"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                HStack {
                    Text("Amount Paid")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.amountPaid, format: .currency(code: "USD"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Balance Due")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.outstandingBalance, format: .currency(code: "USD"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(contract.outstandingBalance > 0 ? .orange : .green)
                }
                
                Divider()
                
                HStack {
                    Text("Per Session")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.pricePerSession, format: .currency(code: "USD"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dates", systemImage: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 10) {
                if let startDate = contract.startDate {
                    HStack {
                        Text("Start Date")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text(startDate.formatted(date: .long, time: .omitted))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                
                if let endDate = contract.expiryDate {
                    HStack {
                        Text("End Date")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text(endDate.formatted(date: .long, time: .omitted))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                
                HStack {
                    Text("Created")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(notes)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Organization Overlay
struct MacOrganizationOverlay: View {
    @EnvironmentObject var dataManager: DataManager
    let onDismiss: () -> Void
    
    @State private var selectedTab: OrgTab = .coaches
    @State private var searchText = ""
    @State private var selectedCoach: StaffCoach? = nil
    @State private var selectedLocation: Location? = nil
    @State private var selectedCategory: CustomAgeCategory? = nil
    @State private var showingAddCoach = false
    @State private var showingAddLocation = false
    @State private var showingAddCategory = false
    
    enum OrgTab: String, CaseIterable {
        case coaches = "Coaches"
        case locations = "Locations"
        case categories = "Categories"
        
        var icon: String {
            switch self {
            case .coaches: return "person.2.fill"
            case .locations: return "mappin.circle.fill"
            case .categories: return "rectangle.stack.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Panel content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("Organization")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: addAction) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(OrgTab.allCases, id: \.self) { tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                                searchText = ""
                            }
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14))
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(selectedTab == tab ? AppTheme.accentColor : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 14)
                
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textTertiary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                
                Divider()
                    .padding(.top, 10)
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 2) {
                        switch selectedTab {
                        case .coaches:
                            ForEach(filteredCoaches) { coach in
                                orgCoachRow(coach)
                            }
                            if filteredCoaches.isEmpty {
                                emptyState(icon: "person.2", title: searchText.isEmpty ? "No Coaches" : "No Results")
                            }
                        case .locations:
                            ForEach(filteredLocations) { location in
                                orgLocationRow(location)
                            }
                            if filteredLocations.isEmpty {
                                emptyState(icon: "mappin.circle", title: searchText.isEmpty ? "No Locations" : "No Results")
                            }
                        case .categories:
                            ForEach(filteredCategories) { category in
                                orgCategoryRow(category)
                            }
                            if filteredCategories.isEmpty {
                                emptyState(icon: "rectangle.stack", title: searchText.isEmpty ? "No Categories" : "No Results")
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .frame(width: 380)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
        }
        .sheet(isPresented: $showingAddCoach) {
            AddEditCoachView(coach: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedCoach) { coach in
            AddEditCoachView(coach: coach)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddLocation) {
            AddEditLocationView(location: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedLocation) { location in
            AddEditLocationView(location: location)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddEditCategoryView(category: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedCategory) { category in
            AddEditCategoryView(category: category)
                .environmentObject(dataManager)
        }
    }
    
    // MARK: - Filtered Data
    var filteredCoaches: [StaffCoach] {
        if searchText.isEmpty { return dataManager.staffCoaches }
        return dataManager.staffCoaches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredLocations: [Location] {
        if searchText.isEmpty { return dataManager.locations }
        return dataManager.locations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredCategories: [CustomAgeCategory] {
        let sorted = dataManager.ageCategories.sorted { $0.minAge < $1.minAge }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Actions
    private func addAction() {
        switch selectedTab {
        case .coaches: showingAddCoach = true
        case .locations: showingAddLocation = true
        case .categories: showingAddCategory = true
        }
    }
    
    // MARK: - Row Views
    private func orgCoachRow(_ coach: StaffCoach) -> some View {
        let isProfileCoach = coach.id == dataManager.coach.id
        return Button(action: { selectedCoach = coach }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.avatarColor(coach.avatarColor))
                        .frame(width: 36, height: 36)
                    Text(coach.initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    if isProfileCoach {
                        Circle()
                            .fill(AppTheme.accentColor)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 12, y: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(coach.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        if isProfileCoach {
                            Text("You")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.accentColor)
                                .cornerRadius(3)
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: coach.role.icon)
                            .font(.system(size: 8))
                        Text(coach.role.rawValue)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(coach.role.color)
                }
                
                Spacer()
                
                if !coach.ageGroups.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(coach.ageGroups.prefix(2), id: \.self) { age in
                            Text(age.rawValue)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(hex: age.colorHex))
                                .cornerRadius(3)
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func orgLocationRow(_ location: Location) -> some View {
        Button(action: { selectedLocation = location }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(location.courtType.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: location.courtType.icon)
                        .font(.system(size: 14))
                        .foregroundColor(location.courtType.color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(location.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    if let address = location.fullAddress {
                        Text(address)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 0) {
                    Text("\(location.courtCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(location.courtCount == 1 ? "Court" : "Courts")
                        .font(.system(size: 8))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func orgCategoryRow(_ category: CustomAgeCategory) -> some View {
        Button(action: { selectedCategory = category }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.color)
                        .frame(width: 36, height: 36)
                    Text(category.shortName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(category.ageRange)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0) {
                    Text(category.ballSize.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(category.rimHeight.displayName)
                        .font(.system(size: 8))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Flighty Sidebar Nav Item
struct FlightySidebarNavItem: View {
    let tab: MacContentView.MacTab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : .gray)
                    .frame(width: 16)
                
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .black)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.orange : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flighty Metric Card (Dashboard)
struct GlassMetricCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let detail: String
    var progress: Double? = nil
    var trend: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(iconColor)
                }
                
                Spacer()
                
                // Trend badge
                if let trend = trend {
                    Text(trend)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(trend.hasPrefix("+") ? .green : (trend.hasPrefix("-") ? .red : .gray))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (trend.hasPrefix("+") ? Color.green : (trend.hasPrefix("-") ? Color.red : Color.gray))
                                .opacity(0.1)
                        )
                        .cornerRadius(4)
                }
            }
            
            // Value
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            // Label and detail
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.7))
                    .lineLimit(1)
            }
            
            // Progress bar
            if let progress = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 3)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(iconColor)
                            .frame(width: geo.size.width * min(progress, 1.0), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Timeline Event Row (Flighty Style)
struct TimelineEventRow: View {
    let event: MacContentView.TimelineEvent
    let isLast: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Time column
                VStack(spacing: 0) {
                    Text(event.time.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 44)
                    
                    if !isLast {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 44)
                
                // Event dot
                ZStack {
                    Circle()
                        .fill(event.color.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: event.icon)
                        .font(.system(size: 10))
                        .foregroundColor(event.color)
                }
                
                // Event details
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    Text(event.subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(event.subtitle == "LIVE" ? .red : .gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Action Row (Flighty Style)
struct QuickActionRow: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.04))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Game Row (Flighty Style)
struct CompactGameRow: View {
    let game: Game
    let dataManager: DataManager
    let onTap: () -> Void
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Teams
                HStack(spacing: 4) {
                    Text(homeTeam?.shortName ?? "TBD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black)
                    
                    if game.status == .live || game.status == .finished {
                        Text("\(game.homeScore)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(game.homeScore > game.awayScore ? .orange : .gray)
                        
                        Text("-")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.4))
                        
                        Text("\(game.awayScore)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(game.awayScore > game.homeScore ? .orange : .gray)
                    } else {
                        Text("vs")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    
                    Text(awayTeam?.shortName ?? "TBD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // Status/Time
                if game.status == .live {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(3)
                } else {
                    Text(game.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.04))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mac Student List Row (with delete support)
struct MacStudentListRow: View {
    let student: Student
    let program: Program?
    let isSelected: Bool
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    // Program color ring if enrolled
                    if let program = program {
                        Circle()
                            .stroke(Color(hex: program.colorHex), lineWidth: 2)
                            .frame(width: 40, height: 40)
                    }
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 36, height: 36)
                    Text(student.initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(student.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        // Program badge
                        if let program = program {
                            Text(program.name)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color(hex: program.colorHex))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(hex: program.colorHex).opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                    
                    if let age = student.age {
                        Text("\(age) yrs")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                // Action buttons (show on hover)
                if isHovered && onDelete != nil {
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accentColor.opacity(0.15) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .alert("Delete Student?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(student.name)\"? This will also delete their contracts and remove them from any teams. This action cannot be undone.")
        }
    }
}

// MARK: - Mac Searchable Drill Picker
struct MacSearchableDrillPicker: View {
    let title: String
    let color: Color
    let allDrills: [DrillItem]
    @Binding var selectedDrillIds: [UUID]
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory? = nil
    
    var filteredDrills: [DrillItem] {
        var result = allDrills
        
        // Filter out already selected drills
        result = result.filter { !selectedDrillIds.contains($0.id) }
        
        if !searchText.isEmpty {
            result = result.filter { drill in
                drill.name.localizedCaseInsensitiveContains(searchText) ||
                drill.description.localizedCaseInsensitiveContains(searchText) ||
                drill.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.basketball")
                        .foregroundColor(color)
                    Text("Add \(title)")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                TextField("Search drills by name, description, or tags...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(nil, title: "All")
                    ForEach(DrillCategory.allCases, id: \.self) { cat in
                        categoryButton(cat, title: cat.displayName)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            
            Divider()
            
            // Drill list
            if filteredDrills.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(searchText.isEmpty ? "No more drills available" : "No drills found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Text("Try a different search term")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredDrills) { drill in
                            drillSelectRow(drill)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 500, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func categoryButton(_ cat: DrillCategory?, title: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = cat
            }
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? color : Color(NSColor.controlBackgroundColor)))
        }
        .buttonStyle(.plain)
    }
    
    private func drillSelectRow(_ drill: DrillItem) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDrillIds.append(drill.id)
            }
        }) {
            HStack(spacing: 12) {
                // Category icon
                Image(systemName: drill.category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor(drill.category))
                    .frame(width: 36, height: 36)
                    .background(categoryColor(drill.category).opacity(0.15))
                    .cornerRadius(8)
                
                // Drill info
                VStack(alignment: .leading, spacing: 3) {
                    Text(drill.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(drill.category.displayName)
                            .font(.system(size: 11))
                        
                        Text("•")
                        
                        Text("\(drill.durationMinutes) min")
                            .font(.system(size: 11))
                        
                        // Difficulty stars
                        HStack(spacing: 2) {
                            ForEach(0..<drill.difficulty.stars, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Add button
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func categoryColor(_ category: DrillCategory) -> Color {
        switch category.color {
        case "orange": return .orange
        case "blue": return .blue
        case "red": return .red
        case "purple": return .purple
        case "green": return .green
        case "yellow": return .yellow
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Mac Curriculum Section with Searchable Picker
struct MacCurriculumSectionView: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var drillIds: [UUID]
    let allDrills: [DrillItem]
    let programColor: Color
    
    @State private var showingDrillPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(drillIds.count) drills")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            if drillIds.isEmpty {
                HStack {
                    Text("No drills added")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            } else {
                ForEach(drillIds, id: \.self) { drillId in
                    if let drill = allDrills.first(where: { $0.id == drillId }) {
                        curriculumDrillRow(drill: drill) {
                            drillIds.removeAll { $0 == drillId }
                        }
                    }
                }
            }
            
            // Add Drill Button - Opens searchable picker
            Button(action: { showingDrillPicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Drill")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDrillPicker) {
                MacSearchableDrillPicker(
                    title: title,
                    color: color,
                    allDrills: allDrills,
                    selectedDrillIds: $drillIds,
                    isPresented: $showingDrillPicker
                )
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    private func curriculumDrillRow(drill: DrillItem, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: drill.category.icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(drill.durationMinutes) min • \(drill.difficulty.displayName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
}

// MARK: - AI Suggestion Models
struct AIProgramSuggestion: Codable {
    let name: String
    let ageGroup: String
    let durationWeeks: Int
    let description: String
    let objectives: [String]
    let mascot: String
    let colorHex: String
    let phases: [AIPhaseSuggestion]
    let recurringDays: [String]?  // e.g., ["monday", "thursday"]
    let defaultSessionTime: String?  // e.g., "18:30"
}

struct AISessionBrief: Codable {
    let title: String
    let sessionType: String
    let durationMinutes: Int
    let description: String
    let dayOfWeek: String?
    let weekNumber: Int?
}

struct AIPhaseSuggestion: Codable {
    let phaseNumber: Int
    let title: String
    let focus: [String]
    let durationWeeks: Int
    let description: String
    let objectives: [String]
    let sessions: [AISessionBrief]?
}

struct AIPhaseSuggestionFromProgram {
    let phaseNumber: Int
    let title: String
    let focus: [String]
    let durationWeeks: Int
    let description: String
    let objectives: [String]
    let sessions: [AISessionBrief]
}

struct AISessionSuggestion: Codable {
    let title: String
    let sessionType: String
    let durationMinutes: Int
    let description: String
    let warmupDrills: [AIDrillBrief]
    let mainDrills: [AIDrillBrief]
    let cooldownDrills: [AIDrillBrief]
    let coachNotes: String
}

struct AIDrillBrief: Codable {
    let name: String
    let durationMinutes: Int
    let description: String
}

// MARK: - ==================== GLASSMORPHIC DESIGN SYSTEM ====================
// Note: GlassColors, GlassMetrics, GlassButtonStyle, etc. are defined in GlassDesignSystem.swift
// The following duplicate definitions have been removed to fix build errors.

// MARK: - Expanded Hub Card Container (Isolated to prevent type-checking freeze)
private struct _MacGlassPlaceholder {
    // Placeholder to maintain file structure
}

/* REMOVED DUPLICATE DEFINITIONS - See GlassDesignSystem.swift */

struct _GlassColors_REMOVED {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let backgroundGradientStart = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let backgroundGradientEnd = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let glassBackground = Color.white.opacity(0.08)
    static let glassBackgroundLight = Color.white.opacity(0.12)
    static let glassBackgroundDark = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.20)
    static let glassBorderSubtle = Color.white.opacity(0.10)
    static let accentCyan = Color(red: 0, green: 0.8, blue: 1.0)
    static let accentCyanGlow = Color(red: 0, green: 0.8, blue: 1.0).opacity(0.6)
    static let accentOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let accentGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let accentRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let accentYellow = Color(red: 1.0, green: 0.85, blue: 0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let textMuted = Color.white.opacity(0.35)
}

// MARK: - Design System Metrics
struct _MacGlassMetrics {
    static let radiusLarge: CGFloat = 28
    static let radiusMedium: CGFloat = 20
    static let radiusSmall: CGFloat = 12
    static let radiusXSmall: CGFloat = 8
    static let spacingXL: CGFloat = 32
    static let spacingLarge: CGFloat = 24
    static let spacingMedium: CGFloat = 16
    static let spacingSmall: CGFloat = 12
    static let spacingXS: CGFloat = 8
    static let spacingXXS: CGFloat = 4
    static let blurHeavy: CGFloat = 60
    static let blurMedium: CGFloat = 40
    static let blurLight: CGFloat = 20
    static let shadowRadius: CGFloat = 30
    static let shadowOpacity: Double = 0.3
}

// MARK: - Glass Card Modifier
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = GlassMetrics.radiusMedium
    var opacity: Double = 0.08
    var borderOpacity: Double = 0.20
    var padding: CGFloat = GlassMetrics.spacingMedium
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.5)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(GlassMetrics.shadowOpacity), radius: GlassMetrics.shadowRadius, x: 0, y: 10)
    }
}

// MARK: - Glass Container
struct GlassContainer: ViewModifier {
    var cornerRadius: CGFloat = GlassMetrics.radiusLarge
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.06))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 20)
    }
}

// MARK: - Glass Button Style
struct _MacGlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var accentColor: Color = GlassColors.accentCyan
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, GlassMetrics.spacingMedium)
            .padding(.vertical, GlassMetrics.spacingSmall)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(isActive ? accentColor : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(isActive ? accentColor.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundColor(isActive ? .black : .white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Primary Action Button Style
struct _MacPrimaryActionButtonStyle: ButtonStyle {
    var accentColor: Color = GlassColors.accentCyan
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, GlassMetrics.spacingLarge)
            .padding(.vertical, GlassMetrics.spacingSmall)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 12, x: 0, y: 4)
            )
            .foregroundColor(.black)
            .fontWeight(.semibold)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Circular Action Button
struct CircularActionButton: View {
    let icon: String
    var size: CGFloat = 48
    var accentColor: Color = GlassColors.accentCyan
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: size, height: size)
                    .shadow(color: accentColor.opacity(0.5), radius: 12, x: 0, y: 4)
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Text Field
struct _MacGlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: GlassMetrics.spacingSmall) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 14))
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 14))
        }
        .padding(.horizontal, GlassMetrics.spacingMedium)
        .padding(.vertical, GlassMetrics.spacingSmall)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Glass Progress Indicator
struct GlassProgressIndicator: View {
    var progress: Double
    var label: String? = nil
    var accentColor: Color = GlassColors.accentCyan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = label {
                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: geometry.size.width * CGFloat(progress))
                        .shadow(color: accentColor.opacity(0.5), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Glass Navigation Item
struct GlassNavItem: View {
    let icon: String
    let title: String
    var isSelected: Bool = false
    var badge: Int? = nil
    var accentColor: Color = GlassColors.accentCyan
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: GlassMetrics.spacingSmall) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.6))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                Spacer()
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accentColor))
                }
            }
            .padding(.horizontal, GlassMetrics.spacingMedium)
            .padding(.vertical, GlassMetrics.spacingSmall)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expanded Hub Card Container (Isolated to prevent type-checking freeze)
struct ExpandedHubCardContainer: View {
    let card: MacContentView.MacHubCard
    let dataManager: DataManager
    @Binding var athleteSearchText: String
    @Binding var drillSubSection: MacContentView.DrillSubSection
    @Binding var showingAddDrill: Bool
    let onBack: () -> Void
    let onAddStudent: () -> Void
    let onAddDrill: () -> Void
    let onManageOrg: () -> Void
    let onSelectStudent: (Student) -> Void
    var onImport: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            contentView
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Hub")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(card.rawValue)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            actionButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch card {
        case .athletes:
            Button(action: onAddStudent) {
                Label("Add Athlete", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GlassColors.accentCyan)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        case .drillsAndPlays:
            Button(action: onAddDrill) {
                Label("Add Drill", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GlassColors.accentOrange)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        case .organization:
            Button(action: onManageOrg) {
                Label("Manage", systemImage: "gear")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch card {
        case .athletes:
            ExpandedAthletesView(
                dataManager: dataManager,
                searchText: $athleteSearchText,
                onAddStudent: onAddStudent,
                onSelectStudent: onSelectStudent,
                onImport: onImport
            )
        case .drillsAndPlays:
            ExpandedDrillsPlaysView(
                dataManager: dataManager,
                drillSubSection: $drillSubSection,
                showingAddDrill: $showingAddDrill
            )
        case .organization:
            ExpandedOrganizationView(dataManager: dataManager)
        }
    }
}

// MARK: - Expanded Athletes View (Isolated)
struct ExpandedAthletesView: View {
    let dataManager: DataManager
    @Binding var searchText: String
    let onAddStudent: () -> Void
    let onSelectStudent: (Student) -> Void
    var onImport: (() -> Void)? = nil
    
    private var filteredStudents: [Student] {
        if searchText.isEmpty {
            return dataManager.students.sorted { $0.name < $1.name }
        }
        return dataManager.students.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.chineseName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            countLabel
            athletesList
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
            TextField("Search athletes...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var countLabel: some View {
        HStack {
            Text("\(filteredStudents.count) athletes")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            
            // Import button
            if let onImport = onImport {
                Button(action: onImport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                        Text("Import")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var athletesList: some View {
        if filteredStudents.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredStudents) { student in
                        AthleteListRow(student: student) {
                            onSelectStudent(student)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "person.badge.plus" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))
            Text(searchText.isEmpty ? "No Athletes" : "No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            if searchText.isEmpty {
                Button(action: onAddStudent) {
                    Text("Add Athlete")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(GlassColors.accentCyan)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Expanded Drills & Plays View (Isolated)
struct ExpandedDrillsPlaysView: View {
    let dataManager: DataManager
    @Binding var drillSubSection: MacContentView.DrillSubSection
    @Binding var showingAddDrill: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            tabsView
            contentView
        }
    }
    
    private var tabsView: some View {
        HStack(spacing: 8) {
            ForEach(MacContentView.DrillSubSection.allCases, id: \.self) { section in
                Button { drillSubSection = section } label: {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(drillSubSection == section ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(drillSubSection == section ? GlassColors.accentOrange : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch drillSubSection {
        case .drills:
            GlassDrillLibraryView(dataManager: dataManager, showingAddDrill: $showingAddDrill)
                .padding(.horizontal, 24)
        case .plays:
            PlaysLibraryView(dataManager: dataManager)
        case .studio:
            PlayStudioView()
        }
    }
}

// MARK: - Plays Library View (Isolated)
struct PlaysLibraryView: View {
    let dataManager: DataManager
    
    var body: some View {
        if dataManager.plays.isEmpty {
            emptyState
        } else {
            playsList
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))
            Text("No Plays Yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("Create plays to build your playbook")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
            Button { } label: {
                Text("Create Play")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(GlassColors.accentOrange)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var playsList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(dataManager.plays) { play in
                    GlassPlayCard(play: play)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Play Studio View (Comprehensive Basketball Play Creator)
struct PlayStudioView: View {
    // MARK: - State
    @State private var playName: String = "New Play"
    @State private var isHalfCourt: Bool = true
    @State private var selectedTool: StudioTool = .select
    @State private var selectedColor: Color = GlassColors.accentOrange
    @State private var selectedColorIndex: Int = 0
    
    // Available drawing colors
    private let drawingColors: [Color] = [
        GlassColors.accentOrange,
        GlassColors.accentCyan,
        .white,
        .yellow,
        .red,
        .green
    ]
    @State private var showingSidebar: Bool = true
    @State private var showingClearConfirm: Bool = false
    @State private var showingNewPlaySheet: Bool = false
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    
    // Drawing state
    @State private var drawings: [StudioDrawing] = []
    @State private var currentDrawing: [CGPoint] = []
    
    // Players state
    @State private var offensePlayers: [CourtPlayer] = []
    @State private var defensePlayers: [CourtPlayer] = []
    @State private var selectedPlayerId: UUID? = nil
    @State private var draggedPlayerId: UUID? = nil
    
    // Animation state
    @State private var frames: [PlayFrame] = []
    @State private var currentFrameIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0
    
    // Undo/Redo
    @State private var undoStack: [CanvasState] = []
    @State private var redoStack: [CanvasState] = []
    
    // Sample Plays Data
    @State private var samplePlays: [SamplePlay] = SamplePlay.samples
    @State private var selectedPlayId: UUID? = nil
    
    // Sample Play Structure
    struct SamplePlay: Identifiable {
        let id = UUID()
        let name: String
        let category: String
        let players: [CourtPlayer]
        let drawings: [StudioDrawing]
        
        // Pre-defined player positions for sample plays (relative to court center)
        // These will be positioned based on court size when loaded
        static let samples: [SamplePlay] = [
            SamplePlay(
                name: "Horns Entry",
                category: "Horns",
                players: [
                    CourtPlayer(position: CGPoint(x: 300, y: 280), number: 1, isOffense: true),  // Point guard at top
                    CourtPlayer(position: CGPoint(x: 220, y: 180), number: 2, isOffense: true),  // Left elbow
                    CourtPlayer(position: CGPoint(x: 380, y: 180), number: 3, isOffense: true),  // Right elbow
                    CourtPlayer(position: CGPoint(x: 180, y: 100), number: 4, isOffense: true),  // Left block
                    CourtPlayer(position: CGPoint(x: 420, y: 100), number: 5, isOffense: true)   // Right block
                ],
                drawings: []
            ),
            SamplePlay(
                name: "1-4 High Stack",
                category: "1-4 High",
                players: [
                    CourtPlayer(position: CGPoint(x: 300, y: 280), number: 1, isOffense: true),  // Point guard
                    CourtPlayer(position: CGPoint(x: 180, y: 200), number: 2, isOffense: true),  // Left wing
                    CourtPlayer(position: CGPoint(x: 420, y: 200), number: 3, isOffense: true),  // Right wing
                    CourtPlayer(position: CGPoint(x: 250, y: 200), number: 4, isOffense: true),  // Left high post
                    CourtPlayer(position: CGPoint(x: 350, y: 200), number: 5, isOffense: true)   // Right high post
                ],
                drawings: []
            ),
            SamplePlay(
                name: "Motion Weak",
                category: "Motion",
                players: [
                    CourtPlayer(position: CGPoint(x: 300, y: 260), number: 1, isOffense: true),  // Point
                    CourtPlayer(position: CGPoint(x: 160, y: 200), number: 2, isOffense: true),  // Left wing
                    CourtPlayer(position: CGPoint(x: 440, y: 200), number: 3, isOffense: true),  // Right wing
                    CourtPlayer(position: CGPoint(x: 200, y: 100), number: 4, isOffense: true),  // Left corner
                    CourtPlayer(position: CGPoint(x: 400, y: 100), number: 5, isOffense: true)   // Right corner
                ],
                drawings: []
            ),
            SamplePlay(
                name: "SLOB Box",
                category: "SLOB/BLOB",
                players: [
                    CourtPlayer(position: CGPoint(x: 140, y: 200), number: 1, isOffense: true),  // Inbounder
                    CourtPlayer(position: CGPoint(x: 260, y: 160), number: 2, isOffense: true),  // Box top left
                    CourtPlayer(position: CGPoint(x: 340, y: 160), number: 3, isOffense: true),  // Box top right
                    CourtPlayer(position: CGPoint(x: 260, y: 100), number: 4, isOffense: true),  // Box bottom left
                    CourtPlayer(position: CGPoint(x: 340, y: 100), number: 5, isOffense: true)   // Box bottom right
                ],
                drawings: []
            ),
            SamplePlay(
                name: "Press Break Diamond",
                category: "Press Break",
                players: [
                    CourtPlayer(position: CGPoint(x: 300, y: 60), number: 1, isOffense: true),   // Back
                    CourtPlayer(position: CGPoint(x: 200, y: 150), number: 2, isOffense: true),  // Left middle
                    CourtPlayer(position: CGPoint(x: 400, y: 150), number: 3, isOffense: true),  // Right middle
                    CourtPlayer(position: CGPoint(x: 300, y: 200), number: 4, isOffense: true),  // Center
                    CourtPlayer(position: CGPoint(x: 300, y: 280), number: 5, isOffense: true)   // Front
                ],
                drawings: []
            )
        ]
    }
    
    // MARK: - Types
    enum StudioTool: String, CaseIterable {
        case select = "arrow.up.left.and.arrow.down.right"
        case player = "person.fill"
        case defender = "xmark"
        case movement = "arrow.right"
        case pass = "basketball.fill"
        case screen = "rectangle.portrait.fill"
        case dribble = "scribble.variable"
        case cut = "line.diagonal"
        case text = "textformat"
        case eraser = "eraser.fill"
        
        var label: String {
            switch self {
            case .select: return "Select"
            case .player: return "Player"
            case .defender: return "Defender"
            case .movement: return "Move"
            case .pass: return "Pass"
            case .screen: return "Screen"
            case .dribble: return "Dribble"
            case .cut: return "Cut"
            case .text: return "Text"
            case .eraser: return "Erase"
            }
        }
        
        var color: Color {
            switch self {
            case .movement: return GlassColors.accentOrange
            case .pass: return .white
            case .cut: return GlassColors.accentCyan
            case .dribble: return .yellow
            default: return .white
            }
        }
    }
    
    struct CourtPlayer: Identifiable {
        let id = UUID()
        var position: CGPoint
        var number: Int
        var label: String
        var isOffense: Bool
        
        init(position: CGPoint, number: Int, isOffense: Bool) {
            self.position = position
            self.number = number
            self.label = isOffense ? "\(number)" : "X\(number)"
            self.isOffense = isOffense
        }
    }
    
    struct StudioDrawing: Identifiable {
        let id = UUID()
        var points: [CGPoint]
        var tool: StudioTool
        var color: Color
    }
    
    struct PlayFrame: Identifiable {
        let id = UUID()
        var offensePlayers: [CourtPlayer]
        var defensePlayers: [CourtPlayer]
        var drawings: [StudioDrawing]
        var duration: Double = 1.0
    }
    
    struct CanvasState {
        var offensePlayers: [CourtPlayer]
        var defensePlayers: [CourtPlayer]
        var drawings: [StudioDrawing]
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            if showingSidebar {
                playsLibrarySidebar
                    .frame(width: 240)
                    .transition(.move(edge: .leading))
            }
            
            // Main Content
            VStack(spacing: 0) {
                // Top Toolbar
                mainToolbar
                
                // Canvas Area with floating tools
                HStack(spacing: 0) {
                    // Main canvas area
                    GeometryReader { geometry in
                        ZStack {
                            // Center the court
                            courtCanvas(in: geometry.size)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Floating tools palette on right
                    floatingToolsPalette
                        .padding(.vertical, 16)
                        .padding(.trailing, 12)
                }
                
                // Bottom Timeline (for animation)
                animationTimeline
            }
        }
        .background(Color(hex: "#1a1a1e"))
        .alert("Clear Canvas?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) { clearCanvas() }
        } message: {
            Text("This will remove all players and drawings.")
        }
    }
    
    // MARK: - Plays Library Sidebar
    private var playsLibrarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("My Plays")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { showingNewPlaySheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(GlassColors.accentOrange)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white.opacity(0.03))
            
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                Text("Search plays...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Folders
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarFolder(name: "All Plays", icon: "folder.fill", count: samplePlays.count)
                    sidebarFolder(name: "Sets", icon: "rectangle.3.group.fill", count: 0)
                    sidebarFolder(name: "SLOB/BLOB", icon: "arrow.right.circle.fill", count: samplePlays.filter { $0.category == "SLOB/BLOB" }.count)
                    sidebarFolder(name: "Press Break", icon: "arrow.up.forward", count: samplePlays.filter { $0.category == "Press Break" }.count)
                    sidebarFolder(name: "Fast Break", icon: "hare.fill", count: 0)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 8)
                    
                    Text("TEMPLATES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    
                    // Show sample plays by category
                    ForEach(["Horns", "1-4 High", "Motion"], id: \.self) { category in
                        let playsInCategory = samplePlays.filter { $0.category == category }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            sidebarFolder(name: category, icon: categoryIcon(for: category), count: playsInCategory.count)
                            
                            // Show plays in this category
                            ForEach(playsInCategory) { play in
                                Button {
                                    loadSamplePlay(play)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.rectangle")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.4))
                                            .frame(width: 16)
                                        Text(play.name)
                                            .font(.system(size: 11))
                                            .foregroundColor(selectedPlayId == play.id ? GlassColors.accentOrange : .white.opacity(0.7))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPlayId == play.id ? GlassColors.accentOrange.opacity(0.15) : Color.clear)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .background(
            Color.white.opacity(0.02)
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private func sidebarFolder(name: String, icon: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(GlassColors.accentOrange.opacity(0.8))
                .frame(width: 20)
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category {
        case "Horns": return "square.grid.2x2"
        case "1-4 High": return "square.grid.3x2"
        case "Motion": return "arrow.triangle.swap"
        case "SLOB/BLOB": return "arrow.right.circle.fill"
        case "Press Break": return "arrow.up.forward"
        default: return "folder"
        }
    }
    
    private func loadSamplePlay(_ play: SamplePlay) {
        // Save current state before loading
        saveState()
        
        // Set selected play
        selectedPlayId = play.id
        playName = play.name
        
        // Load play data
        offensePlayers = play.players
        defensePlayers = []
        drawings = play.drawings
        
        // Reset frames
        frames.removeAll()
        currentFrameIndex = 0
    }
    
    // MARK: - Main Toolbar
    private var mainToolbar: some View {
        HStack(spacing: 16) {
            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSidebar.toggle()
                }
            } label: {
                Image(systemName: showingSidebar ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            // Play name
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(GlassColors.accentOrange)
                TextField("Play Name", text: $playName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 160)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.1))
            
            // Court toggle
            HStack(spacing: 0) {
                courtToggleButton(label: "Half", isSelected: isHalfCourt) {
                    isHalfCourt = true
                }
                courtToggleButton(label: "Full", isSelected: !isHalfCourt) {
                    isHalfCourt = false
                }
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            
            Spacer()
            
            // Undo/Redo
            HStack(spacing: 4) {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .foregroundColor(undoStack.isEmpty ? .white.opacity(0.2) : .white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(undoStack.isEmpty)
                
                Button { redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12))
                        .foregroundColor(redoStack.isEmpty ? .white.opacity(0.2) : .white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(redoStack.isEmpty)
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.1))
            
            // Actions
            Button { showingClearConfirm = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button { savePlay() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(GlassColors.accentOrange)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button { } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("Export")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func courtToggleButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .black : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? GlassColors.accentOrange : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Floating Tools Palette
    private var floatingToolsPalette: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Tools section
                VStack(spacing: 4) {
                    Text("TOOLS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 4) {
                        ForEach(StudioTool.allCases, id: \.self) { tool in
                            toolButton(tool)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.5))
                        .background(.ultraThinMaterial.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Colors section
                VStack(spacing: 4) {
                    Text("COLOR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    LazyVGrid(columns: [GridItem(.fixed(28)), GridItem(.fixed(28)), GridItem(.fixed(28))], spacing: 6) {
                        ForEach(Array(drawingColors.enumerated()), id: \.offset) { index, color in
                            Button {
                                selectedColorIndex = index
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorIndex == index ? Color.white : Color.clear, lineWidth: 3)
                                    )
                                    .shadow(color: selectedColorIndex == index ? color.opacity(0.6) : .clear, radius: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.5))
                        .background(.ultraThinMaterial.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .frame(width: 100)
    }
    
    private func toolButton(_ tool: StudioTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tool.rawValue)
                    .font(.system(size: 12))
                Text(tool.label)
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundColor(selectedTool == tool ? .black : .white.opacity(0.7))
            .frame(width: 40, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTool == tool ? GlassColors.accentOrange : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Court Canvas
    private func courtCanvas(in size: CGSize) -> some View {
        // FIBA Court Dimensions: 28m x 15m (full court)
        // Full court aspect ratio = 28/15 = 1.867
        // Half court = 14m x 15m, displayed landscape = 15/14 = 1.071 (or keep same width, half height)
        let availableWidth = size.width - 32
        let availableHeight = size.height - 32
        
        // FIBA aspect ratios
        let aspectRatio: CGFloat = isHalfCourt ? 1.071 : 1.867
        
        // Calculate dimensions to fit available space while maintaining aspect ratio
        var finalWidth: CGFloat
        var finalHeight: CGFloat
        
        if availableWidth / availableHeight > aspectRatio {
            // Height is limiting factor
            finalHeight = availableHeight
            finalWidth = finalHeight * aspectRatio
        } else {
            // Width is limiting factor
            finalWidth = availableWidth
            finalHeight = finalWidth / aspectRatio
        }
        
        // Ensure minimum size
        finalWidth = max(400, finalWidth)
        finalHeight = max(300, finalHeight)
        
        return ZStack {
            // Court background with wood texture effect
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#CD853F").opacity(0.5),
                            Color(hex: "#DEB887").opacity(0.45),
                            Color(hex: "#CD853F").opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Wood grain horizontal lines
                    VStack(spacing: 8) {
                        ForEach(0..<20, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.03))
                                .frame(height: 1)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                )
            
            // Court lines
            if isHalfCourt {
                halfCourtLinesHorizontal(width: finalWidth, height: finalHeight)
            } else {
                fullCourtLinesHorizontal(width: finalWidth, height: finalHeight)
            }
            
            // Drawings
            ForEach(drawings) { drawing in
                drawingPath(drawing)
            }
            
            // Current drawing
            if !currentDrawing.isEmpty {
                Path { path in
                    path.move(to: currentDrawing[0])
                    for point in currentDrawing.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(selectedColor, style: strokeStyle(for: selectedTool))
            }
            
            // Players
            ForEach(offensePlayers) { player in
                playerPiece(player, isSelected: selectedPlayerId == player.id)
                    .position(player.position)
                    .gesture(playerDragGesture(for: player))
            }
            
            ForEach(defensePlayers) { player in
                defenderPiece(player, isSelected: selectedPlayerId == player.id)
                    .position(player.position)
                    .gesture(playerDragGesture(for: player))
            }
        }
        .frame(width: finalWidth, height: finalHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .gesture(canvasGesture(courtSize: CGSize(width: finalWidth, height: finalHeight)))
        .scaleEffect(canvasScale)
        .offset(canvasOffset)
    }
    
    // MARK: - Half Court Lines (Horizontal/Landscape orientation - basket on RIGHT)
    // FIBA Dimensions: Half court 14m x 15m, 3pt line 6.75m, key 4.9m x 5.8m
    private func halfCourtLinesHorizontal(width: CGFloat, height: CGFloat) -> some View {
        let lineColor = Color.white.opacity(0.7)
        let lineWidth: CGFloat = 2
        
        // FIBA proportions (based on 14m x 15m half court)
        let basketOffset: CGFloat = width * 0.107  // 1.575m from baseline / 14m = 0.1125
        let threePointRadius: CGFloat = width * 0.482  // 6.75m / 14m = 0.482
        let cornerThreeY: CGFloat = height * 0.06  // Corner three distance from sideline
        let keyWidth: CGFloat = width * 0.414  // 5.8m / 14m = 0.414
        let keyHeight: CGFloat = height * 0.327  // 4.9m / 15m = 0.327
        let restrictedRadius: CGFloat = height * 0.083  // 1.25m / 15m = 0.083
        let centerCircleRadius: CGFloat = height * 0.12  // 1.8m / 15m = 0.12
        
        return ZStack {
            // Court boundary
            Rectangle()
                .stroke(lineColor, lineWidth: 3)
                .frame(width: width, height: height)
            
            // Half-court line (left side, vertical)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Center circle (half - on left edge)
            Path { path in
                path.addArc(
                    center: CGPoint(x: 0, y: height / 2),
                    radius: centerCircleRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Three-point line (on right side where basket is)
            Path { path in
                let basketX = width - basketOffset
                
                // Bottom corner three
                path.move(to: CGPoint(x: width, y: height - cornerThreeY))
                path.addLine(to: CGPoint(x: basketX + threePointRadius * cos(.pi * 0.85), y: height - cornerThreeY))
                
                // Arc
                path.addArc(
                    center: CGPoint(x: basketX, y: height / 2),
                    radius: threePointRadius,
                    startAngle: .degrees(72),
                    endAngle: .degrees(-72),
                    clockwise: true
                )
                
                // Top corner three
                path.addLine(to: CGPoint(x: width, y: cornerThreeY))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key/Paint area (rectangle on right)
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: width - keyWidth / 2, y: height / 2)
            
            // Free throw circle (solid half facing basket)
            Path { path in
                let ftRadius = keyHeight / 2
                let ftCenterX = width - keyWidth
                path.addArc(
                    center: CGPoint(x: ftCenterX, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Free throw circle dashed (left half)
            Path { path in
                let ftRadius = keyHeight / 2
                let ftCenterX = width - keyWidth
                path.addArc(
                    center: CGPoint(x: ftCenterX, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: true
                )
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
            
            // Restricted area arc
            Path { path in
                let basketX = width - basketOffset
                path.addArc(
                    center: CGPoint(x: basketX, y: height / 2),
                    radius: restrictedRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Basket/Rim
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: 18, height: 18)
                .position(x: width - basketOffset, y: height / 2)
            
            // Backboard
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 4, height: height * 0.12)
                .position(x: width - (width * 0.02), y: height / 2)
        }
        .frame(width: width, height: height)
    }
    
    // MARK: - Full Court Lines (Horizontal/Landscape orientation)
    // FIBA Dimensions: 28m x 15m, center circle 3.6m diameter
    private func fullCourtLinesHorizontal(width: CGFloat, height: CGFloat) -> some View {
        let lineColor = Color.white.opacity(0.7)
        let lineWidth: CGFloat = 2
        
        // FIBA center circle diameter = 3.6m, radius = 1.8m
        // 1.8m / 15m (height) = 0.12
        let centerCircleRadius: CGFloat = height * 0.24  // diameter proportion
        
        return ZStack {
            // Court boundary
            Rectangle()
                .stroke(lineColor, lineWidth: 3)
                .frame(width: width, height: height)
            
            // Center line (vertical, in middle)
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: 0))
                path.addLine(to: CGPoint(x: width / 2, y: height))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Center circle
            Circle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: centerCircleRadius, height: centerCircleRadius)
                .position(x: width / 2, y: height / 2)
            
            // LEFT SIDE (basket on left)
            leftSideCourtElements(width: width, height: height, lineColor: lineColor, lineWidth: lineWidth)
            
            // RIGHT SIDE (basket on right)
            rightSideCourtElements(width: width, height: height, lineColor: lineColor, lineWidth: lineWidth)
        }
        .frame(width: width, height: height)
    }
    
    private func leftSideCourtElements(width: CGFloat, height: CGFloat, lineColor: Color, lineWidth: CGFloat) -> some View {
        // FIBA proportions for full court (28m x 15m)
        let basketOffset: CGFloat = width * 0.056  // 1.575m / 28m
        let threePointRadius: CGFloat = width * 0.241  // 6.75m / 28m
        let cornerThreeY: CGFloat = height * 0.06
        let keyWidth: CGFloat = width * 0.207  // 5.8m / 28m
        let keyHeight: CGFloat = height * 0.327  // 4.9m / 15m
        let restrictedRadius: CGFloat = height * 0.083  // 1.25m / 15m
        
        return ZStack {
            // Three-point line (left side)
            Path { path in
                let basketX = basketOffset
                
                // Top corner
                path.move(to: CGPoint(x: 0, y: cornerThreeY))
                path.addLine(to: CGPoint(x: basketX + threePointRadius * 0.3, y: cornerThreeY))
                
                // Arc
                path.addArc(
                    center: CGPoint(x: basketX, y: height / 2),
                    radius: threePointRadius,
                    startAngle: .degrees(-72),
                    endAngle: .degrees(72),
                    clockwise: false
                )
                
                // Bottom corner
                path.addLine(to: CGPoint(x: 0, y: height - cornerThreeY))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key/Paint area (left)
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: keyWidth / 2, y: height / 2)
            
            // Free throw circle (left - solid half)
            Path { path in
                let ftRadius = keyHeight / 2
                path.addArc(
                    center: CGPoint(x: keyWidth, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Free throw circle dashed (left - dashed half)
            Path { path in
                let ftRadius = keyHeight / 2
                path.addArc(
                    center: CGPoint(x: keyWidth, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: false
                )
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
            
            // Restricted area arc (left)
            Path { path in
                path.addArc(
                    center: CGPoint(x: basketOffset, y: height / 2),
                    radius: restrictedRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Basket (left)
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: 14, height: 14)
                .position(x: basketOffset, y: height / 2)
            
            // Backboard (left)
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 4, height: height * 0.08)
                .position(x: width * 0.02, y: height / 2)
        }
    }
    
    private func rightSideCourtElements(width: CGFloat, height: CGFloat, lineColor: Color, lineWidth: CGFloat) -> some View {
        // FIBA proportions for full court (28m x 15m) - mirrored from left
        let basketOffset: CGFloat = width * 0.056  // 1.575m / 28m
        let threePointRadius: CGFloat = width * 0.241  // 6.75m / 28m
        let cornerThreeY: CGFloat = height * 0.06
        let keyWidth: CGFloat = width * 0.207  // 5.8m / 28m
        let keyHeight: CGFloat = height * 0.327  // 4.9m / 15m
        let restrictedRadius: CGFloat = height * 0.083  // 1.25m / 15m
        
        return ZStack {
            // Three-point line (right side)
            Path { path in
                let basketX = width - basketOffset
                
                // Top corner
                path.move(to: CGPoint(x: width, y: cornerThreeY))
                path.addLine(to: CGPoint(x: basketX - threePointRadius * 0.3, y: cornerThreeY))
                
                // Arc
                path.addArc(
                    center: CGPoint(x: basketX, y: height / 2),
                    radius: threePointRadius,
                    startAngle: .degrees(-108),
                    endAngle: .degrees(108),
                    clockwise: true
                )
                
                // Bottom corner
                path.addLine(to: CGPoint(x: width, y: height - cornerThreeY))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key/Paint area (right)
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: width - keyWidth / 2, y: height / 2)
            
            // Free throw circle (right - solid half)
            Path { path in
                let ftRadius = keyHeight / 2
                path.addArc(
                    center: CGPoint(x: width - keyWidth, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Free throw circle dashed (right - dashed half)
            Path { path in
                let ftRadius = keyHeight / 2
                path.addArc(
                    center: CGPoint(x: width - keyWidth, y: height / 2),
                    radius: ftRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: true
                )
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
            
            // Restricted area arc (right)
            Path { path in
                path.addArc(
                    center: CGPoint(x: width - basketOffset, y: height / 2),
                    radius: restrictedRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Basket (right)
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: 14, height: 14)
                .position(x: width - basketOffset, y: height / 2)
            
            // Backboard (right)
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 4, height: height * 0.08)
                .position(x: width - (width * 0.02), y: height / 2)
        }
    }
    
    // MARK: - Old Half Court Lines (kept for reference, not used)
    private func halfCourtLines(width: CGFloat, height: CGFloat) -> some View {
        let lineColor = Color.white.opacity(0.6)
        let lineWidth: CGFloat = 2
        let thickLine: CGFloat = 3
        
        return ZStack {
            // Baseline
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            .stroke(lineColor, lineWidth: thickLine)
            
            // Sidelines
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Half-court line
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Center circle (half)
            Path { path in
                let radius = width * 0.12
                path.addArc(
                    center: CGPoint(x: width / 2, y: 0),
                    radius: radius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Three-point line
            Path { path in
                let threePointRadius = width * 0.38
                let cornerY = height * 0.14
                let basketX = width / 2
                let basketY = height - (height * 0.06)
                
                // Left corner
                path.move(to: CGPoint(x: width * 0.06, y: height))
                path.addLine(to: CGPoint(x: width * 0.06, y: height - cornerY))
                
                // Arc
                path.addArc(
                    center: CGPoint(x: basketX, y: basketY),
                    radius: threePointRadius,
                    startAngle: .degrees(158),
                    endAngle: .degrees(22),
                    clockwise: true
                )
                
                // Right corner
                path.addLine(to: CGPoint(x: width * 0.94, y: height))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key/Paint area
            let keyWidth = width * 0.32
            let keyHeight = height * 0.35
            let keyX = (width - keyWidth) / 2
            let keyY = height - keyHeight
            
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: width / 2, y: height - keyHeight / 2)
            
            // Free throw circle
            Path { path in
                let ftRadius = keyWidth / 2
                path.addArc(
                    center: CGPoint(x: width / 2, y: keyY),
                    radius: ftRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Free throw circle (dashed bottom)
            Path { path in
                let ftRadius = keyWidth / 2
                path.addArc(
                    center: CGPoint(x: width / 2, y: keyY),
                    radius: ftRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false
                )
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, dash: [5, 5]))
            
            // Restricted area
            Path { path in
                let raRadius = width * 0.08
                let basketY = height - (height * 0.06)
                path.addArc(
                    center: CGPoint(x: width / 2, y: basketY),
                    radius: raRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: true
                )
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Basket/Rim
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: width * 0.035, height: width * 0.035)
                .position(x: width / 2, y: height - (height * 0.06))
            
            // Backboard
            Rectangle()
                .fill(GlassColors.accentOrange.opacity(0.8))
                .frame(width: width * 0.12, height: 4)
                .position(x: width / 2, y: height - (height * 0.02))
        }
    }
    
    // MARK: - Full Court Lines
    private func fullCourtLines(width: CGFloat, height: CGFloat) -> some View {
        let lineColor = Color.white.opacity(0.6)
        let lineWidth: CGFloat = 2
        
        return ZStack {
            // Outer boundary
            Rectangle()
                .stroke(lineColor, lineWidth: 3)
                .frame(width: width, height: height)
            
            // Center line
            Path { path in
                path.move(to: CGPoint(x: 0, y: height / 2))
                path.addLine(to: CGPoint(x: width, y: height / 2))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Center circle
            Circle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: width * 0.18, height: width * 0.18)
                .position(x: width / 2, y: height / 2)
            
            // Top half court elements
            topHalfCourtElements(width: width, height: height, lineColor: lineColor, lineWidth: lineWidth)
            
            // Bottom half court elements (mirrored)
            bottomHalfCourtElements(width: width, height: height, lineColor: lineColor, lineWidth: lineWidth)
        }
    }
    
    private func topHalfCourtElements(width: CGFloat, height: CGFloat, lineColor: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            // Three-point line
            Path { path in
                let threePointRadius = width * 0.38
                let cornerX = width * 0.06
                let basketY = height * 0.06
                
                path.move(to: CGPoint(x: cornerX, y: 0))
                path.addLine(to: CGPoint(x: cornerX, y: height * 0.1))
                path.addArc(
                    center: CGPoint(x: width / 2, y: basketY),
                    radius: threePointRadius,
                    startAngle: .degrees(158),
                    endAngle: .degrees(22),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: width - cornerX, y: 0))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key
            let keyWidth = width * 0.32
            let keyHeight = height * 0.18
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: width / 2, y: keyHeight / 2)
            
            // Basket
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: width * 0.03, height: width * 0.03)
                .position(x: width / 2, y: height * 0.06)
        }
    }
    
    private func bottomHalfCourtElements(width: CGFloat, height: CGFloat, lineColor: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            // Three-point line
            Path { path in
                let threePointRadius = width * 0.38
                let cornerX = width * 0.06
                let basketY = height - (height * 0.06)
                
                path.move(to: CGPoint(x: cornerX, y: height))
                path.addLine(to: CGPoint(x: cornerX, y: height - height * 0.1))
                path.addArc(
                    center: CGPoint(x: width / 2, y: basketY),
                    radius: threePointRadius,
                    startAngle: .degrees(-158),
                    endAngle: .degrees(-22),
                    clockwise: true
                )
                path.addLine(to: CGPoint(x: width - cornerX, y: height))
            }
            .stroke(lineColor, lineWidth: lineWidth)
            
            // Key
            let keyWidth = width * 0.32
            let keyHeight = height * 0.18
            Rectangle()
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: keyWidth, height: keyHeight)
                .position(x: width / 2, y: height - keyHeight / 2)
            
            // Basket
            Circle()
                .stroke(GlassColors.accentOrange, lineWidth: 3)
                .frame(width: width * 0.03, height: width * 0.03)
                .position(x: width / 2, y: height - height * 0.06)
        }
    }
    
    // MARK: - Player Pieces
    private func playerPiece(_ player: CourtPlayer, isSelected: Bool) -> some View {
        ZStack {
            // Glow effect when selected
            if isSelected {
                Circle()
                    .fill(GlassColors.accentOrange.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .blur(radius: 8)
            }
            
            Circle()
                .fill(GlassColors.accentOrange)
                .frame(width: 36, height: 36)
                .shadow(color: GlassColors.accentOrange.opacity(0.5), radius: 6, y: 2)
            
            Text(player.label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black)
        }
    }
    
    private func defenderPiece(_ player: CourtPlayer, isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(GlassColors.accentCyan.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .blur(radius: 8)
            }
            
            Circle()
                .stroke(GlassColors.accentCyan, lineWidth: 3)
                .frame(width: 34, height: 34)
            
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(GlassColors.accentCyan)
        }
    }
    
    // MARK: - Drawing Helpers
    private func drawingPath(_ drawing: StudioDrawing) -> some View {
        Path { path in
            guard drawing.points.count > 1 else { return }
            path.move(to: drawing.points[0])
            for point in drawing.points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(drawing.color, style: strokeStyle(for: drawing.tool))
    }
    
    private func strokeStyle(for tool: StudioTool) -> StrokeStyle {
        switch tool {
        case .pass:
            return StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6])
        case .dribble:
            return StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 4])
        case .movement:
            return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        case .cut:
            return StrokeStyle(lineWidth: 4, lineCap: .round)
        default:
            return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        }
    }
    
    // MARK: - Animation Timeline
    private var animationTimeline: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(spacing: 16) {
                // Frame thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Current frame (always shown)
                        frameThumb(index: 0, isCurrent: currentFrameIndex == 0)
                        
                        ForEach(frames.indices, id: \.self) { index in
                            frameThumb(index: index + 1, isCurrent: currentFrameIndex == index + 1)
                        }
                        
                        // Add frame button
                        Button { addKeyframe() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14))
                                Text("Add Frame")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 60, height: 45)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
                
                Spacer()
                
                // Playback controls
                HStack(spacing: 12) {
                    Button { previousFrame() } label: {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    
                    Button { togglePlayback() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black)
                            .frame(width: 36, height: 36)
                            .background(GlassColors.accentOrange)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button { nextFrame() } label: {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                
                // Speed picker
                Picker("", selection: $playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("1.5x").tag(1.5)
                    Text("2x").tag(2.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.02))
        }
    }
    
    private func frameThumb(index: Int, isCurrent: Bool) -> some View {
        Button {
            selectFrame(index)
        } label: {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#8B4513").opacity(0.3))
                    .frame(width: 60, height: 40)
                    .overlay(
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isCurrent ? GlassColors.accentOrange : Color.white.opacity(0.1), lineWidth: isCurrent ? 2 : 1)
                    )
                
                if isCurrent {
                    Circle()
                        .fill(GlassColors.accentOrange)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func selectFrame(_ index: Int) {
        // Save current frame state before switching
        if currentFrameIndex == 0 {
            // Frame 0 is the "live" canvas, save to a temporary frame if needed
        } else if currentFrameIndex - 1 < frames.count {
            // Update the current frame with current state
            frames[currentFrameIndex - 1] = PlayFrame(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                drawings: drawings
            )
        }
        
        // Switch to new frame
        currentFrameIndex = index
        
        // Load the new frame state
        if index == 0 {
            // Frame 0 is always the "live" working canvas - don't load anything
        } else if index - 1 < frames.count {
            let frame = frames[index - 1]
            offensePlayers = frame.offensePlayers
            defensePlayers = frame.defensePlayers
            drawings = frame.drawings
        }
    }
    
    // MARK: - Gestures
    private func canvasGesture(courtSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleCanvasDrag(value: value, courtSize: courtSize)
            }
            .onEnded { value in
                handleCanvasDragEnd(value: value, courtSize: courtSize)
            }
    }
    
    private func handleCanvasDrag(value: DragGesture.Value, courtSize: CGSize) {
        let point = value.location
        
        switch selectedTool {
        case .movement, .pass, .cut, .dribble:
            currentDrawing.append(point)
        case .eraser:
            eraseAt(point: point)
        default:
            break
        }
    }
    
    private func handleCanvasDragEnd(value: DragGesture.Value, courtSize: CGSize) {
        let point = value.location
        
        switch selectedTool {
        case .player:
            if offensePlayers.count < 5 {
                saveState()
                let newPlayer = CourtPlayer(
                    position: point,
                    number: offensePlayers.count + 1,
                    isOffense: true
                )
                offensePlayers.append(newPlayer)
            }
        case .defender:
            if defensePlayers.count < 5 {
                saveState()
                let newPlayer = CourtPlayer(
                    position: point,
                    number: defensePlayers.count + 1,
                    isOffense: false
                )
                defensePlayers.append(newPlayer)
            }
        case .movement, .pass, .cut, .dribble:
            if currentDrawing.count > 1 {
                saveState()
                let drawing = StudioDrawing(
                    points: currentDrawing,
                    tool: selectedTool,
                    color: selectedTool == .pass ? .white : selectedColor
                )
                drawings.append(drawing)
            }
            currentDrawing = []
        default:
            break
        }
    }
    
    private func playerDragGesture(for player: CourtPlayer) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if player.isOffense {
                    if let index = offensePlayers.firstIndex(where: { $0.id == player.id }) {
                        offensePlayers[index].position = value.location
                    }
                } else {
                    if let index = defensePlayers.firstIndex(where: { $0.id == player.id }) {
                        defensePlayers[index].position = value.location
                    }
                }
                selectedPlayerId = player.id
            }
            .onEnded { _ in
                saveState()
            }
    }
    
    // MARK: - Actions
    private func clearCanvas() {
        saveState()
        offensePlayers.removeAll()
        defensePlayers.removeAll()
        drawings.removeAll()
        currentDrawing.removeAll()
    }
    
    private func eraseAt(point: CGPoint) {
        drawings = drawings.filter { drawing in
            !drawing.points.contains { p in
                distance(from: p, to: point) < 20
            }
        }
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }
    
    private func saveState() {
        let state = CanvasState(
            offensePlayers: offensePlayers,
            defensePlayers: defensePlayers,
            drawings: drawings
        )
        undoStack.append(state)
        redoStack.removeAll()
    }
    
    private func undo() {
        guard let lastState = undoStack.popLast() else { return }
        let currentState = CanvasState(
            offensePlayers: offensePlayers,
            defensePlayers: defensePlayers,
            drawings: drawings
        )
        redoStack.append(currentState)
        offensePlayers = lastState.offensePlayers
        defensePlayers = lastState.defensePlayers
        drawings = lastState.drawings
    }
    
    private func redo() {
        guard let nextState = redoStack.popLast() else { return }
        let currentState = CanvasState(
            offensePlayers: offensePlayers,
            defensePlayers: defensePlayers,
            drawings: drawings
        )
        undoStack.append(currentState)
        offensePlayers = nextState.offensePlayers
        defensePlayers = nextState.defensePlayers
        drawings = nextState.drawings
    }
    
    private func savePlay() {
        // TODO: Save to Supabase
    }
    
    private func addKeyframe() {
        let frame = PlayFrame(
            offensePlayers: offensePlayers,
            defensePlayers: defensePlayers,
            drawings: drawings
        )
        frames.append(frame)
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
    }
    
    private func previousFrame() {
        if currentFrameIndex > 0 {
            currentFrameIndex -= 1
        }
    }
    
    private func nextFrame() {
        if currentFrameIndex < frames.count {
            currentFrameIndex += 1
        }
    }
}

// MARK: - Expanded Organization View (Isolated)
struct ExpandedOrganizationView: View {
    let dataManager: DataManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                staffSection
                locationsSection
                programsSection
            }
            .padding(24)
        }
    }
    
    private var staffSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "STAFF COACHES", count: dataManager.staffCoaches.count)
            
            if dataManager.staffCoaches.isEmpty {
                emptyRow(icon: "person.2", text: "No staff coaches added")
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(dataManager.staffCoaches) { coach in
                        GlassStaffCoachRow(coach: coach)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }
    
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "LOCATIONS", count: dataManager.locations.count)
            
            if dataManager.locations.isEmpty {
                emptyRow(icon: "mappin.circle", text: "No locations added")
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(dataManager.locations) { location in
                        GlassLocationRow(location: location)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }
    
    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "PROGRAMS", count: dataManager.programs.count)
            
            if dataManager.programs.isEmpty {
                emptyRow(icon: "folder", text: "No programs created")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(dataManager.programs) { program in
                        GlassProgramCard(program: program) { }
                    }
                }
            }
        }
    }
    
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private func emptyRow(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}

// MARK: - Hub Overview View (Isolated to prevent type-checking freeze)
struct HubOverviewView: View {
    let dataManager: DataManager
    let onCardTap: (MacContentView.MacHubCard) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hubHeader
                hubCardsGrid
            }
            .padding(.bottom, 24)
        }
    }
    
    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hub")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text("Manage your athletes, drills, plays, and organization")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
    
    private var hubCardsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(MacContentView.MacHubCard.allCases, id: \.self) { card in
                HubNavigationCard(
                    card: card,
                    count: hubCardCount(for: card),
                    subtitle: hubCardSubtitle(for: card)
                ) {
                    onCardTap(card)
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUICK STATS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 24)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                GlassStatCard(
                    title: "Total Athletes",
                    value: "\(dataManager.students.count)",
                    icon: "person.3.fill",
                    accentColor: GlassColors.accentCyan
                )
                GlassStatCard(
                    title: "Drills",
                    value: "\(dataManager.drills.count)",
                    icon: "sportscourt.fill",
                    accentColor: GlassColors.accentOrange
                )
                GlassStatCard(
                    title: "Staff",
                    value: "\(dataManager.staffCoaches.count)",
                    icon: "person.2.fill",
                    accentColor: Color.purple
                )
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }
    
    private func hubCardCount(for card: MacContentView.MacHubCard) -> Int {
        switch card {
        case .athletes: return dataManager.students.count
        case .drillsAndPlays: return dataManager.drills.count
        case .organization: return dataManager.staffCoaches.count + dataManager.locations.count
        }
    }
    
    private func hubCardSubtitle(for card: MacContentView.MacHubCard) -> String {
        switch card {
        case .athletes: return "Manage roster"
        case .drillsAndPlays: return "Library & playbook"
        case .organization: return "Staff & locations"
        }
    }
}

// MARK: - Hub Navigation Card
struct HubNavigationCard: View {
    let card: MacContentView.MacHubCard
    let count: Int
    let subtitle: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon container - properly aligned
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(card.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: card.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(card.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                HStack {
                    Text("\(count)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.3))
                }
            }
            .padding(20)
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(card.color.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Athlete List Row (Scalable)
struct AthleteListRow: View {
    let student: Student
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Avatar with profile picture support
                athleteAvatar
                
                // Name and details
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let chineseName = student.chineseName {
                        Text(chineseName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Age if available
                if let age = student.age {
                    Text("\(age) yrs")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 0.5 : 0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    @ViewBuilder
    private var athleteAvatar: some View {
        let avatarColor = Color(student.avatarColor.color)
        let size: CGFloat = 40
        
        if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(avatarColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(student.initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        } else {
            Circle()
                .fill(avatarColor)
                .frame(width: size, height: size)
                .overlay(
                    Text(student.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }
}

// MARK: - Glass Staff Coach Row
struct GlassStaffCoachRow: View {
    let coach: StaffCoach
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(coach.role.color.opacity(0.3))
                    .frame(width: 40, height: 40)
                Image(systemName: coach.role.icon)
                    .font(.system(size: 16))
                    .foregroundColor(coach.role.color)
            }
            
            // Name and role
            VStack(alignment: .leading, spacing: 2) {
                Text(coach.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(coach.role.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(coach.role.color)
            }
            
            Spacer()
            
            // Contact info
            if let phone = coach.phone, !phone.isEmpty {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            
            if let email = coach.email, !email.isEmpty {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Glass Location Row
struct GlassLocationRow: View {
    let location: Location
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(GlassColors.accentOrange.opacity(0.3))
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(GlassColors.accentOrange)
            }
            
            // Name and address
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let address = location.address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Glass Play Card
struct GlassPlayCard: View {
    let play: Play
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Play diagram placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(16/9, contentMode: .fit)
                
                Image(systemName: play.category.icon)
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.2))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(play.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(play.category.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Ambient Background View
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.12, blue: 0.10),
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(RadialGradient(colors: [Color.orange.opacity(0.15), Color.clear], center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 600, height: 600)
                .offset(x: -200, y: -100)
                .blur(radius: 60)
            Circle()
                .fill(RadialGradient(colors: [Color.blue.opacity(0.08), Color.clear], center: .center, startRadius: 0, endRadius: 250))
                .frame(width: 500, height: 500)
                .offset(x: 300, y: 200)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Filter Pill
struct GlassFilterPill: View {
    let title: String
    var isSelected: Bool
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { action?() }) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                        .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                        .stroke(Color.white.opacity(isSelected ? 0.2 : 0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Data Card
struct GlassDataCard<Content: View>: View {
    let content: Content
    var isHighlighted: Bool = false
    var accentColor: Color = GlassColors.accentCyan
    
    init(isHighlighted: Bool = false, accentColor: Color = GlassColors.accentCyan, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isHighlighted = isHighlighted
        self.accentColor = accentColor
    }
    
    var body: some View {
        content
            .padding(GlassMetrics.spacingMedium)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .fill(Color.white.opacity(isHighlighted ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .stroke(isHighlighted ? accentColor.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - Glass Stat Card
struct GlassStatCard: View {
    let title: String
    let value: String
    let icon: String
    var trend: String? = nil
    var trendUp: Bool = true
    var accentColor: Color = GlassColors.accentCyan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                Spacer()
                if let trend = trend {
                    HStack(spacing: 4) {
                        Image(systemName: trendUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(trend)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(trendUp ? GlassColors.accentGreen : GlassColors.accentRed)
                }
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(GlassMetrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Glass Section Header
struct _MacGlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GlassColors.accentCyan)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Glass Avatar
struct _MacGlassAvatar: View {
    let name: String
    var size: CGFloat = 40
    var color: Color = GlassColors.accentOrange
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Glass Quick Action Button
struct GlassQuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var accentColor: Color = GlassColors.accentCyan
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Athlete Card
struct GlassAthleteCard: View {
    let student: Student
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                GlassAvatar(initials: String(student.name.prefix(2)), color: Color(student.avatarColor.color), size: 56)
                VStack(spacing: 4) {
                    Text(student.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(student.attendanceStatus == .present ? GlassColors.accentGreen : GlassColors.accentOrange)
                        .frame(width: 6, height: 6)
                    Text(student.attendanceStatus.rawValue.capitalized)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Athlete Row (compact)
struct GlassAthleteRow: View {
    let student: Student
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlassAvatar(initials: String(student.name.prefix(2)), color: Color(student.avatarColor.color), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Program Card
struct GlassProgramCard: View {
    let program: Program
    var isSelected: Bool = false
    let action: () -> Void
    var onEdit: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: program.colorHex).opacity(0.3))
                        .frame(width: 48, height: 48)
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: program.colorHex))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Label("\(program.durationWeeks)w", systemImage: "calendar")
                        Label(program.ageGroup.rawValue.uppercased(), systemImage: "person.fill")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                
                // Edit button (visible on hover)
                if isHovered, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(GlassColors.accentCyan)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(program.enrolledStudentIds.count)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(GlassColors.accentCyan)
                    Text("athletes")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .fill(Color.white.opacity(isSelected ? 0.12 : (isHovered ? 0.10 : 0.08)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .stroke(isSelected ? GlassColors.accentCyan.opacity(0.5) : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Glass Phase Card
struct GlassPhaseCard: View {
    let phase: MicroCycle
    var isSelected: Bool = false
    let action: () -> Void
    var onEdit: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? GlassColors.accentCyan : Color.white.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text("\(phase.phaseNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isSelected ? .black : .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(phase.durationWeeks) weeks • \(phase.focus.first?.rawValue.capitalized ?? "Training")")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                
                // Edit button (visible on hover)
                if isHovered, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(GlassColors.accentOrange)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(Color.white.opacity(isSelected ? 0.12 : (isHovered ? 0.09 : 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(isSelected ? GlassColors.accentCyan.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Glass Drill Card
struct GlassDrillCard: View {
    let drill: DrillItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: categoryIcon)
                    .font(.system(size: 14))
                    .foregroundColor(categoryColor)
                Spacer()
                Text("\(drill.durationMinutes)m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(drill.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < difficultyLevel ? categoryColor : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Text(drill.category.rawValue.capitalized)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var categoryIcon: String {
        switch drill.category {
        case .warmup: return "flame.fill"
        case .shooting: return "scope"
        case .offense: return "arrow.right.circle.fill"
        case .defense: return "shield.fill"
        case .skills: return "star.fill"
        case .conditioning: return "figure.run"
        case .cooldown: return "wind"
        }
    }
    
    private var categoryColor: Color {
        switch drill.category {
        case .warmup: return GlassColors.accentYellow
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .cooldown: return GlassColors.accentCyan
        }
    }
    
    private var difficultyLevel: Int {
        switch drill.difficulty {
        case .beginner: return 1
        case .intermediate: return 3
        case .advanced: return 5
        }
    }
}

// MARK: - Simple Drill Row (non-interactive to avoid freeze)
struct SimpleDrillRow: View {
    let drill: DrillItem
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: categoryIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(categoryColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(drill.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if drill.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(drill.durationMinutes) min", systemImage: "clock")
                    Text(drill.difficulty.rawValue.capitalized)
                        .foregroundColor(difficultyColor)
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var categoryIcon: String {
        switch drill.category {
        case .warmup: return "flame.fill"
        case .shooting: return "scope"
        case .offense: return "arrow.right.circle.fill"
        case .defense: return "shield.fill"
        case .skills: return "star.fill"
        case .conditioning: return "figure.run"
        case .cooldown: return "wind"
        }
    }
    
    private var categoryColor: Color {
        switch drill.category {
        case .warmup: return GlassColors.accentYellow
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .cooldown: return Color.cyan
        }
    }
    
    private var difficultyColor: Color {
        switch drill.difficulty {
        case .beginner: return GlassColors.accentGreen
        case .intermediate: return GlassColors.accentOrange
        case .advanced: return GlassColors.accentRed
        }
    }
}

// MARK: - Glass Drill Row (for list view)
struct GlassDrillRow: View {
    let drill: DrillItem
    var isSelected: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: categoryIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(categoryColor)
                }
                
                // Drill info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drill.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if drill.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Label("\(drill.durationMinutes) min", systemImage: "clock")
                        Text(drill.difficulty.rawValue.capitalized)
                            .foregroundColor(difficultyColor)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
    
    private var categoryIcon: String {
        switch drill.category {
        case .warmup: return "flame.fill"
        case .shooting: return "scope"
        case .offense: return "arrow.right.circle.fill"
        case .defense: return "shield.fill"
        case .skills: return "star.fill"
        case .conditioning: return "figure.run"
        case .cooldown: return "wind"
        }
    }
    
    private var categoryColor: Color {
        switch drill.category {
        case .warmup: return GlassColors.accentYellow
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .cooldown: return Color.cyan
        }
    }
    
    private var difficultyColor: Color {
        switch drill.difficulty {
        case .beginner: return GlassColors.accentGreen
        case .intermediate: return GlassColors.accentOrange
        case .advanced: return GlassColors.accentRed
        }
    }
}

// MARK: - Glass Session Card
struct GlassSessionCard: View {
    let session: SessionEvent
    let action: () -> Void
    var onEdit: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(session.startTime.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: 50)
                Rectangle()
                    .fill(statusColor.opacity(0.5))
                    .frame(width: 3)
                    .cornerRadius(2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Label(session.sessionType.rawValue.capitalized, systemImage: "figure.run")
                        if let location = session.location {
                            Label(location, systemImage: "mappin")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                
                // Edit button (visible on hover)
                if isHovered, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(GlassColors.accentGreen)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                
                Text(session.status.rawValue.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(statusColor.opacity(0.2)))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(Color.white.opacity(isHovered ? 0.09 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case .scheduled: return GlassColors.accentCyan
        case .inProgress: return GlassColors.accentOrange
        case .completed: return GlassColors.accentGreen
        case .cancelled: return GlassColors.accentRed
        }
    }
}

// MARK: - Glass Game Card
struct GlassGameCard: View {
    let game: Game
    let action: () -> Void
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    Text(game.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(game.status.rawValue.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                HStack(spacing: 16) {
                    VStack(spacing: 6) {
                        teamAvatar(for: game.awayTeamId)
                        Text(teamName(for: game.awayTeamId))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 8) {
                        Text("\(game.awayScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("-")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.4))
                        Text("\(game.homeScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(spacing: 6) {
                        teamAvatar(for: game.homeTeamId)
                        Text(teamName(for: game.homeTeamId))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func teamAvatar(for teamId: UUID) -> some View {
        let team = dataManager.teams.first { $0.id == teamId }
        return Circle()
            .fill(Color(hex: team?.colorHex ?? "#666666"))
            .frame(width: 40, height: 40)
            .overlay(
                Text(team?.shortName.prefix(2).uppercased() ?? "??")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            )
    }
    
    private func teamName(for teamId: UUID) -> String {
        dataManager.teams.first { $0.id == teamId }?.shortName ?? "TBD"
    }
    
    private var statusColor: Color {
        switch game.status {
        case .scheduled: return GlassColors.accentCyan
        case .live: return GlassColors.accentOrange
        case .finished: return GlassColors.accentGreen
        case .cancelled, .postponed: return GlassColors.accentRed
        }
    }
}

// MARK: - Glass Team Card
struct GlassTeamCard: View {
    let team: Team
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: team.colorHex))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(team.shortName.prefix(2).uppercased())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color(hex: team.colorHex).opacity(0.4), radius: 8, x: 0, y: 4)
                VStack(spacing: 2) {
                    Text(team.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(team.playerIds.count) players")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Contract Card
struct GlassContractCard: View {
    let contract: Contract
    let student: Student
    
    var body: some View {
        HStack(spacing: 14) {
            GlassAvatar(initials: String(student.name.prefix(2)), color: Color(student.avatarColor.color), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                GlassProgressIndicator(
                    progress: Double(contract.attendedSessions) / Double(max(contract.totalSessions, 1)),
                    label: "\(contract.attendedSessions)/\(contract.totalSessions) sessions",
                    accentColor: GlassColors.accentCyan
                )
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(Int(contract.amountPaid))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(GlassColors.accentGreen)
                Text("of ¥\(Int(contract.totalAmount))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Glass Empty State
struct GlassEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - View Extensions for Glass
extension View {
    func _macGlassCard(
        cornerRadius: CGFloat = GlassMetrics.radiusMedium,
        opacity: Double = 0.08,
        borderOpacity: Double = 0.20,
        padding: CGFloat = GlassMetrics.spacingMedium
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, opacity: opacity, borderOpacity: borderOpacity, padding: padding))
    }
    
    func _macGlassContainer(cornerRadius: CGFloat = GlassMetrics.radiusLarge) -> some View {
        modifier(GlassContainer(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Drill Library View (Isolated to prevent infinite re-renders)
struct GlassDrillLibraryView: View {
    let dataManager: DataManager
    @Binding var showingAddDrill: Bool
    
    @State private var selectedCategory: DrillCategory? = nil
    @State private var searchText: String = ""
    @State private var selectedDrill: DrillItem? = nil
    @State private var showingEditDrill = false
    
    private var drills: [DrillItem] {
        var result = dataManager.drills
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            categorySidebar
            drillListView
        }
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showingAddDrill) {
            AddEditDrillSheet(drill: nil)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingEditDrill) {
            if let drill = selectedDrill {
                GlassEditDrillSheet(drill: drill, dataManager: dataManager)
            }
        }
    }
    
    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            // All Drills button
            Button {
                selectedCategory = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(selectedCategory == nil ? .white : GlassColors.accentCyan)
                    Text("All Drills")
                        .font(.system(size: 13, weight: selectedCategory == nil ? .semibold : .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(dataManager.drills.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selectedCategory == nil ? .black : .white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(selectedCategory == nil ? GlassColors.accentCyan : Color.white.opacity(0.15)))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedCategory == nil ? GlassColors.accentCyan : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            
            // Category buttons
            ForEach(DrillCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor(category))
                        Text(category.displayName)
                            .font(.system(size: 13, weight: selectedCategory == category ? .semibold : .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedCategory == category ? Color.white.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            
            Spacer()
        }
        .frame(width: 180)
        .background(Color.white.opacity(0.03))
    }
    
    private var drillListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(selectedCategory?.displayName ?? "All Drills")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                    TextField("Search drills...", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Add button
                Button {
                    showingAddDrill = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Drill")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GlassColors.accentCyan)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Text("\(drills.count) drills")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Drill list
            if drills.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "figure.basketball")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.2))
                    Text(searchText.isEmpty ? "No Drills in This Category" : "No Results Found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(searchText.isEmpty ? "Add drills to get started" : "Try a different search term")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(drills) { drill in
                            Button {
                                selectedDrill = drill
                                showingEditDrill = true
                            } label: {
                                ClickableDrillRow(drill: drill)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .background(Color.white.opacity(0.06))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private func categoryColor(_ category: DrillCategory) -> Color {
        switch category {
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .warmup: return GlassColors.accentYellow
        case .cooldown: return Color.cyan
        }
    }
}

// MARK: - Clickable Drill Row
struct ClickableDrillRow: View {
    let drill: DrillItem
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(categoryColor)
            }
            
            // Drill info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(drill.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if drill.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(GlassColors.accentRed)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(drill.durationMinutes) min", systemImage: "clock")
                    Text("•")
                    Text(drill.difficulty.displayName)
                        .foregroundColor(difficultyColor)
                    Text("•")
                    Text(drill.category.displayName)
                        .foregroundColor(categoryColor)
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var categoryIcon: String {
        switch drill.category {
        case .warmup: return "flame.fill"
        case .shooting: return "scope"
        case .offense: return "arrow.right.circle.fill"
        case .defense: return "shield.fill"
        case .skills: return "star.fill"
        case .conditioning: return "figure.run"
        case .cooldown: return "wind"
        }
    }
    
    private var categoryColor: Color {
        switch drill.category {
        case .warmup: return GlassColors.accentYellow
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .cooldown: return Color.cyan
        }
    }
    
    private var difficultyColor: Color {
        switch drill.difficulty {
        case .beginner: return GlassColors.accentGreen
        case .intermediate: return GlassColors.accentOrange
        case .advanced: return GlassColors.accentRed
        }
    }
    
    private var difficultyText: String {
        drill.difficulty.displayName
    }
}

// MARK: - Glass Edit Drill Sheet
struct GlassEditDrillSheet: View {
    let drill: DrillItem
    let dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var category: DrillCategory
    @State private var difficulty: DifficultyLevel
    @State private var durationMinutes: Int
    @State private var isFavorite: Bool
    @State private var instructions: String
    @State private var equipmentNeeded: String
    
    init(drill: DrillItem, dataManager: DataManager) {
        self.drill = drill
        self.dataManager = dataManager
        _name = State(initialValue: drill.name)
        _description = State(initialValue: drill.description)
        _category = State(initialValue: drill.category)
        _difficulty = State(initialValue: drill.difficulty)
        _durationMinutes = State(initialValue: drill.durationMinutes)
        _isFavorite = State(initialValue: drill.isFavorite)
        _instructions = State(initialValue: drill.instructions.joined(separator: "\n"))
        _equipmentNeeded = State(initialValue: drill.equipmentNeeded.joined(separator: ", "))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    glassTextField(title: "Drill Name", icon: "textformat", text: $name, placeholder: "e.g., Three-Point Shooting")
                    
                    // Category & Difficulty
                    HStack(alignment: .top, spacing: 16) {
                        glassPicker(title: "Category", icon: "folder.fill", options: DrillCategory.allCases, selection: $category) { $0.displayName }
                        glassPicker(title: "Difficulty", icon: "chart.bar.fill", options: DifficultyLevel.allCases, selection: $difficulty) { $0.displayName }
                    }
                    
                    // Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Duration", systemImage: "clock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        HStack {
                            Text("\(durationMinutes) minutes")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Stepper("", value: $durationMinutes, in: 1...120)
                                .labelsHidden()
                                .colorScheme(.dark)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    
                    // Favorite Toggle
                    HStack {
                        Label("Favorite", systemImage: "heart.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Toggle("", isOn: $isFavorite)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? GlassColors.accentRed : .white.opacity(0.3))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextEditor(text: $description)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(height: 80)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Instructions", systemImage: "list.number")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextEditor(text: $instructions)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    // Equipment
                    glassTextField(title: "Equipment (comma separated)", icon: "sportscourt.fill", text: $equipmentNeeded, placeholder: "e.g., Basketball, Cones, Whistle")
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 700)
        .background(GlassColors.background)
    }
    
    private var sheetHeader: some View {
        HStack(spacing: 16) {
            // Drill icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(categoryColor)
                    .frame(width: 44, height: 44)
                Image(systemName: categoryIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Drill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text(name.isEmpty ? "Untitled Drill" : name)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Delete button
            Button {
                deleteDrill()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(GlassColors.accentRed)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(GlassColors.accentRed.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            
            // Cancel button
            Button("Cancel") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .buttonStyle(.plain)
            
            // Save button
            Button("Save") { saveDrill() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GlassColors.accentGreen)
                )
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                .opacity(name.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(Color.white.opacity(0.03))
    }
    
    private func glassTextField(title: String, icon: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
    
    private func glassPicker<T: Hashable>(title: String, icon: String, options: [T], selection: Binding<T>, displayName: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(displayName(option)) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack {
                    Text(displayName(selection.wrappedValue))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var categoryIcon: String {
        switch category {
        case .warmup: return "flame.fill"
        case .shooting: return "scope"
        case .offense: return "arrow.right.circle.fill"
        case .defense: return "shield.fill"
        case .skills: return "star.fill"
        case .conditioning: return "figure.run"
        case .cooldown: return "wind"
        }
    }
    
    private var categoryColor: Color {
        switch category {
        case .warmup: return GlassColors.accentYellow
        case .shooting: return GlassColors.accentOrange
        case .offense: return GlassColors.accentCyan
        case .defense: return GlassColors.accentRed
        case .skills: return Color.purple
        case .conditioning: return GlassColors.accentGreen
        case .cooldown: return Color.cyan
        }
    }
    
    private func saveDrill() {
        var updated = drill
        updated.name = name
        updated.description = description
        updated.category = category
        updated.difficulty = difficulty
        updated.durationMinutes = durationMinutes
        updated.isFavorite = isFavorite
        updated.instructions = instructions.split(separator: "\n").map { String($0) }
        updated.equipmentNeeded = equipmentNeeded.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        dataManager.updateDrill(updated)
        dismiss()
    }
    
    private func deleteDrill() {
        dataManager.deleteDrill(drill)
        dismiss()
    }
}

// MARK: - Mac Student Import Sheet
struct MacStudentImportSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isFilePickerPresented = false
    @State private var importedStudents: [ImportRow] = []
    @State private var importError: String?
    @State private var showingError = false
    @State private var importComplete = false
    @State private var importedCount = 0
    
    struct ImportRow: Identifiable {
        let id = UUID()
        var name: String
        var phone: String?
        var amount: String?
        var program: String?
        var salesCoach: String?
        var isSelected: Bool = true
    }
    
    var selectedCount: Int {
        importedStudents.filter { $0.isSelected }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("导入学生")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Import Students from CSV or Excel")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(white: 0.15))
            
            if importedStudents.isEmpty {
                // File selection
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 56))
                        .foregroundColor(.purple.opacity(0.7))
                    
                    Text("选择文件")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Select a CSV or Excel file to import")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Button(action: { isFilePickerPresented = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("选择文件 Choose File")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.purple)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    VStack(spacing: 6) {
                        Text("支持格式 Supported Formats:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        HStack(spacing: 12) {
                            Label("CSV", systemImage: "doc.text")
                            Label("Excel (.xlsx)", systemImage: "tablecells")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                    
                    VStack(spacing: 4) {
                        Text("自动识别列 Auto-detect Columns:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        Text("姓名, 联系方式, 金额, 培训项目, 销售")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 12)
                    
                    Spacer()
                }
                .padding(24)
            } else {
                // Preview list
                VStack(spacing: 0) {
                    HStack {
                        Text("预览 Preview (\(selectedCount) of \(importedStudents.count) selected)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Button("全选 All") {
                            for i in importedStudents.indices { importedStudents[i].isSelected = true }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                        Button("取消 None") {
                            for i in importedStudents.indices { importedStudents[i].isSelected = false }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.2))
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach($importedStudents) { $row in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: $row.isSelected)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                    
                                    Text(row.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 60, alignment: .leading)
                                    
                                    if let program = row.program, !program.isEmpty {
                                        Text(program)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(program.contains("篮") ? Color.orange : program.contains("羽") ? Color.green : Color.blue))
                                    }
                                    
                                    Spacer()
                                    
                                    if let phone = row.phone, !phone.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "phone.fill")
                                                .font(.system(size: 10))
                                            Text(phone)
                                                .font(.system(size: 11))
                                        }
                                        .foregroundColor(.white.opacity(0.5))
                                    }
                                    
                                    if let amount = row.amount, !amount.isEmpty {
                                        Text("¥\(amount)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    if let coach = row.salesCoach, !coach.isEmpty {
                                        HStack(spacing: 3) {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 9))
                                            Text(coach)
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(.cyan.opacity(0.8))
                                    }
                                }
                                .padding(10)
                                .background(row.isSelected ? Color.purple.opacity(0.2) : Color.white.opacity(0.05))
                                .cornerRadius(8)
                                .opacity(row.isSelected ? 1 : 0.5)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            
            // Footer
            HStack {
                if !importedStudents.isEmpty {
                    Button("选择其他文件 Choose Different") {
                        importedStudents = []
                        isFilePickerPresented = true
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                }
                
                Spacer()
                
                Button("取消 Cancel") { dismiss() }
                    .foregroundColor(.white.opacity(0.6))
                
                if !importedStudents.isEmpty {
                    Button(action: performImport) {
                        Text("导入 Import \(selectedCount)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(selectedCount > 0 ? Color.purple : Color.gray)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0)
                }
            }
            .padding(20)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 600, height: 550)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
        )
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .spreadsheet, .init(filenameExtension: "xlsx")!, .init(filenameExtension: "xls")!],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("导入错误 Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("导入完成 Import Complete", isPresented: $importComplete) {
            Button("完成 Done") { dismiss() }
        } message: {
            Text("成功导入 \(importedCount) 名学生\nSuccessfully imported \(importedCount) student(s)")
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "无法访问文件 Unable to access file"
                showingError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let ext = url.pathExtension.lowercased()
            
            // Handle Excel files
            if ext == "xlsx" || ext == "xls" {
                parseExcel(url)
                return
            }
            
            do {
                // Try UTF-8 first, then other encodings
                var content: String?
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    content = utf8
                } else {
                    let cfEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    if let gbk = try? String(contentsOf: url, encoding: String.Encoding(rawValue: cfEnc)) {
                        content = gbk
                    }
                }
                
                guard let csvContent = content else {
                    importError = "无法读取文件 Unable to read file"
                    showingError = true
                    return
                }
                
                parseCSV(csvContent)
            } catch {
                importError = error.localizedDescription
                showingError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showingError = true
        }
    }
    
    private func parseCSV(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        var rows: [ImportRow] = []
        
        for (idx, line) in lines.enumerated() {
            if idx == 0 { continue } // Skip header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Handle quoted CSV
            var columns: [String] = []
            var current = ""
            var inQuotes = false
            for char in trimmed {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == "," && !inQuotes {
                    columns.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else {
                    current.append(char)
                }
            }
            columns.append(current.trimmingCharacters(in: .whitespaces))
            
            guard !columns.isEmpty, !columns[0].isEmpty else { continue }
            
            rows.append(ImportRow(
                name: columns[0],
                phone: columns.count > 1 ? columns[1] : nil,
                amount: columns.count > 2 ? columns[2] : nil
            ))
        }
        
        importedStudents = rows
    }
    
    private func parseExcel(_ url: URL) {
        // XLSX files are ZIP archives containing XML
        // Column mapping for your specific Excel format:
        // D (col 3) = 姓名 Name, G (col 6) = 联系方式 Phone, J (col 9) = 金额 Amount
        // K (col 10) = 培训项目 Program, N (col 13) = 销售 Sales Coach
        do {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }
            
            // Unzip the xlsx file
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", url.path, "-d", tempDir.path]
            process.standardOutput = nil
            process.standardError = nil
            try process.run()
            process.waitUntilExit()
            
            // Read shared strings (contains the actual text values)
            var sharedStrings: [String] = []
            let sharedStringsPath = tempDir.appendingPathComponent("xl/sharedStrings.xml")
            if let sharedData = try? Data(contentsOf: sharedStringsPath),
               let sharedContent = String(data: sharedData, encoding: .utf8) {
                let pattern = "<t[^>]*>([^<]*)</t>"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(sharedContent.startIndex..., in: sharedContent)
                    let matches = regex.matches(in: sharedContent, options: [], range: range)
                    for match in matches {
                        if let textRange = Range(match.range(at: 1), in: sharedContent) {
                            sharedStrings.append(String(sharedContent[textRange]))
                        }
                    }
                }
            }
            
            // Read sheet1.xml
            let sheetPath = tempDir.appendingPathComponent("xl/worksheets/sheet1.xml")
            guard let sheetData = try? Data(contentsOf: sheetPath),
                  let sheetContent = String(data: sheetData, encoding: .utf8) else {
                importError = "无法读取Excel工作表 Unable to read Excel sheet"
                showingError = true
                return
            }
            
            // Helper to convert column letter to index (A=0, B=1, etc)
            func columnIndex(_ col: String) -> Int {
                var result = 0
                for char in col.uppercased() {
                    result = result * 26 + Int(char.asciiValue! - Character("A").asciiValue!) + 1
                }
                return result - 1
            }
            
            // Parse rows - extract <row> elements
            var rows: [ImportRow] = []
            let rowPattern = "<row[^>]*r=\"(\\d+)\"[^>]*>(.*?)</row>"
            if let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(sheetContent.startIndex..., in: sheetContent)
                let rowMatches = rowRegex.matches(in: sheetContent, options: [], range: range)
                
                for rowMatch in rowMatches {
                    guard let rowNumRange = Range(rowMatch.range(at: 1), in: sheetContent),
                          let rowNum = Int(sheetContent[rowNumRange]),
                          rowNum >= 5 else { continue } // Data starts at row 5
                    
                    guard let rowRange = Range(rowMatch.range(at: 2), in: sheetContent) else { continue }
                    let rowContent = String(sheetContent[rowRange])
                    
                    // Extract cells with their column references
                    var cellMap: [Int: String] = [:]
                    let cellPattern = "<c r=\"([A-Z]+)\\d+\"[^>]*(t=\"s\")?[^>]*>(?:<[^v][^>]*>)*<v>([^<]*)</v>"
                    if let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: []) {
                        let cellRange = NSRange(rowContent.startIndex..., in: rowContent)
                        let cellMatches = cellRegex.matches(in: rowContent, options: [], range: cellRange)
                        
                        for cellMatch in cellMatches {
                            guard let colRange = Range(cellMatch.range(at: 1), in: rowContent),
                                  let valueRange = Range(cellMatch.range(at: 3), in: rowContent) else { continue }
                            
                            let colLetter = String(rowContent[colRange])
                            let colIdx = columnIndex(colLetter)
                            let isSharedString = cellMatch.range(at: 2).location != NSNotFound
                            let rawValue = String(rowContent[valueRange])
                            
                            if isSharedString, let idx = Int(rawValue), idx < sharedStrings.count {
                                cellMap[colIdx] = sharedStrings[idx]
                            } else {
                                cellMap[colIdx] = rawValue
                            }
                        }
                    }
                    
                    // Map columns: D=3, G=6, J=9, K=10, N=13
                    let name = cellMap[3] ?? ""
                    let phone = cellMap[6]
                    let amount = cellMap[9]
                    let program = cellMap[10]
                    let salesCoach = cellMap[13]
                    
                    if !name.isEmpty {
                        rows.append(ImportRow(
                            name: name,
                            phone: phone,
                            amount: amount,
                            program: program,
                            salesCoach: salesCoach
                        ))
                    }
                }
            }
            
            importedStudents = rows
            
            if rows.isEmpty {
                importError = "未找到数据行 No data rows found (data should start at row 5)"
                showingError = true
            }
        } catch {
            importError = "Excel解析错误: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func performImport() {
        let toImport = importedStudents.filter { $0.isSelected }
        var count = 0
        
        for row in toImport {
            let student = Student(
                name: row.name,
                avatarColor: AvatarColor.allCases.randomElement() ?? .blue
            )
            dataManager.addStudent(student)
            
            // Build notes from available info
            var notes: [String] = []
            if let phone = row.phone, !phone.isEmpty { notes.append("电话: \(phone)") }
            if let program = row.program, !program.isEmpty { notes.append("项目: \(program)") }
            if let coach = row.salesCoach, !coach.isEmpty { notes.append("销售: \(coach)") }
            
            // Create contract if amount provided
            if let amountStr = row.amount,
               let amount = Double(amountStr.replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "￥", with: "")) {
                let contract = Contract(
                    studentId: student.id,
                    contractNumber: 1,
                    totalSessions: max(1, Int(amount / 200)),
                    attendedSessions: 0,
                    startDate: Date(),
                    expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()),
                    totalAmount: amount,
                    amountPaid: amount,
                    isSigned: true,
                    signedDate: Date(),
                    notes: notes.isEmpty ? nil : notes.joined(separator: " | ")
                )
                dataManager.addContract(contract)
            }
            count += 1
        }
        
        importedCount = count
        importComplete = true
    }
}

#Preview {
    MacContentView()
        .environmentObject(DataManager.shared)
        .frame(width: 1200, height: 800)
}
#endif
