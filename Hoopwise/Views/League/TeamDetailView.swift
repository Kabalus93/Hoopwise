import SwiftUI

struct TeamDetailView: View {
    let team: Team
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: TeamTab = .roster
    @State private var showingEditTeam = false
    @State private var showingAddPlayer = false
    @State private var showingDeleteConfirmation = false
    
    enum TeamTab: String, CaseIterable {
        case roster = "Roster"
        case schedule = "Schedule"
        case stats = "Stats"
    }
    
    var standing: TeamStanding? {
        dataManager.teamStandings.first { $0.teamId == team.id }
    }
    
    var teamPlayers: [Student] {
        dataManager.students.filter { team.playerIds.contains($0.id) }
    }
    
    var teamGames: [Game] {
        dataManager.games.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Team Header
                    teamHeader
                    
                    // Stats Summary
                    if let standing = standing {
                        statsSummary(standing)
                    }
                    
                    // Tab Selector
                    tabSelector
                    
                    // Content
                    switch selectedTab {
                    case .roster:
                        rosterContent
                    case .schedule:
                        scheduleContent
                    case .stats:
                        teamStatsContent
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddPlayer = true
                            }
                        }) {
                            Label("Add Player", systemImage: "person.badge.plus")
                        }
                        Button(action: { showingEditTeam = true }) {
                            Label("Edit Team", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Team", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if showingAddPlayer {
                    AddPlayerToTeamPanel(
                        team: team,
                        isPresented: $showingAddPlayer
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .slideInPanel(
                isPresented: $showingEditTeam,
                title: "Edit Team",
                minWidth: 380,
                maxWidth: 480
            ) {
                EditTeamPanelContent(
                    team: team,
                    isPresented: $showingEditTeam
                )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingAddPlayer)
            .alert("Delete Team?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTeam()
                }
            } message: {
                Text("Are you sure you want to delete \(team.name)? This will also remove all associated games and stats. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Team Header
    private var teamHeader: some View {
        VStack(spacing: 16) {
            TeamLogo(team: team, size: 80)
            
            VStack(spacing: 4) {
                Text(team.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(team.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                if let coachName = team.coachName, !coachName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Text("Coach: \(coachName)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.top, 4)
                }
            }
            
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("\(teamPlayers.count)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Players")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                if let standing = standing {
                    VStack(spacing: 2) {
                        Text(standing.record)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Record")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    VStack(spacing: 2) {
                        Text(standing.streakDisplay)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(standing.streak > 0 ? AppTheme.successColor : (standing.streak < 0 ? AppTheme.errorColor : AppTheme.textSecondary))
                        Text("Streak")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [team.primaryColor.opacity(0.15), AppTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Stats Summary
    private func statsSummary(_ standing: TeamStanding) -> some View {
        HStack(spacing: 0) {
            statItem(value: String(format: "%.1f", Double(standing.pointsFor) / max(1, Double(standing.gamesPlayed))), label: "PPG")
            Divider().frame(height: 30)
            statItem(value: String(format: "%.1f", Double(standing.pointsAgainst) / max(1, Double(standing.gamesPlayed))), label: "OPP PPG")
            Divider().frame(height: 30)
            statItem(value: String(format: "%.1f%%", standing.winPercentage * 100), label: "WIN %")
            Divider().frame(height: 30)
            statItem(value: standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)", label: "+/-")
        }
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(TeamTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? AppTheme.accentColor : AppTheme.textSecondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .fill(selectedTab == tab ? AppTheme.accentColor : Color.clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                }
            }
        }
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Roster Content
    private var rosterContent: some View {
        VStack(spacing: 16) {
            if teamPlayers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No players on this team")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Button(action: { showingAddPlayer = true }) {
                        Label("Add Players", systemImage: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 160)
                }
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(teamPlayers) { student in
                        PlayerRosterRow(student: student, team: team)
                    }
                }
            }
        }
        .padding(20)
    }
    
    // MARK: - Schedule Content
    private var scheduleContent: some View {
        VStack(spacing: 16) {
            if teamGames.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No games scheduled")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(teamGames) { game in
                        TeamGameRow(game: game, team: team)
                    }
                }
            }
        }
        .padding(20)
    }
    
    // MARK: - Team Stats Content
    private var teamStatsContent: some View {
        VStack(spacing: 16) {
            // Player stats for this team
            Text("Player Statistics")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if teamPlayers.isEmpty {
                Text("Add players to see stats")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 20)
            } else {
                // Stats table
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Player")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("GP")
                            .frame(width: 30)
                        Text("PPG")
                            .frame(width: 40)
                        Text("RPG")
                            .frame(width: 40)
                        Text("APG")
                            .frame(width: 40)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceColor)
                    
                    ForEach(teamPlayers) { student in
                        if let stats = dataManager.seasonStats.first(where: { $0.playerId == student.id }) {
                            HStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    StudentAvatarView(student: student, size: 28)
                                    Text(student.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text("\(stats.gamesPlayed)")
                                    .frame(width: 30)
                                Text(String(format: "%.1f", stats.ppg))
                                    .frame(width: 40)
                                Text(String(format: "%.1f", stats.rpg))
                                    .frame(width: 40)
                                Text(String(format: "%.1f", stats.apg))
                                    .frame(width: 40)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
            }
        }
        .padding(20)
    }
    
    // MARK: - Actions
    private func deleteTeam() {
        dataManager.deleteTeam(team)
        dismiss()
    }
}

// MARK: - Player Roster Row
struct PlayerRosterRow: View {
    let student: Student
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    
    var player: Player? {
        dataManager.player(for: student.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                // Language-aware name display
                if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(student.chineseName!)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(student.name)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                } else {
                    Text(student.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                HStack(spacing: 8) {
                    if let position = player?.position {
                        Text(position)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    if let age = student.age {
                        Text("\(age) yrs")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            if let jersey = player?.jerseyNumber {
                Text("#\(jersey)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(team.primaryColor)
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Team Game Row
struct TeamGameRow: View {
    let game: Game
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    
    var isHome: Bool { game.homeTeamId == team.id }
    
    var opponent: Team? {
        let opponentId = isHome ? game.awayTeamId : game.homeTeamId
        return dataManager.teams.first { $0.id == opponentId }
    }
    
    var teamScore: Int { isHome ? game.homeScore : game.awayScore }
    var opponentScore: Int { isHome ? game.awayScore : game.homeScore }
    var didWin: Bool { teamScore > opponentScore }
    
    var body: some View {
        HStack(spacing: 12) {
            // Result indicator
            if game.status == .finished {
                Text(didWin ? "W" : "L")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(didWin ? AppTheme.successColor : AppTheme.errorColor)
                    .cornerRadius(6)
            } else {
                Text(game.status == .live ? "LIVE" : game.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(game.status == .live ? .red : AppTheme.textSecondary)
                    .frame(width: 44)
            }
            
            // Opponent
            HStack(spacing: 8) {
                TeamLogo(team: opponent, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isHome ? "vs" : "@")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(opponent?.name ?? "Opponent")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            
            Spacer()
            
            // Score
            if game.status == .finished || game.status == .live {
                Text("\(teamScore) - \(opponentScore)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
            } else {
                Text(game.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Add Player to Team Panel (Frosted Glass Slide-in)
struct AddPlayerToTeamPanel: View {
    let team: Team
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedPlayerIds: Set<UUID>
    @State private var searchText = ""
    
    init(team: Team, isPresented: Binding<Bool>) {
        self.team = team
        self._isPresented = isPresented
        _selectedPlayerIds = State(initialValue: Set(team.playerIds))
    }
    
    var availablePlayers: [Student] {
        dataManager.students.filter { !team.playerIds.contains($0.id) }
    }
    
    var filteredPlayers: [Student] {
        if searchText.isEmpty {
            return availablePlayers
        }
        return availablePlayers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Dimmed background tap to dismiss
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isPresented = false
                        }
                    }
                
                // Frosted glass panel
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        Text("Add Players")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Spacer()
                        
                        Button(action: saveAndDismiss) {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        TextField("Search students...", text: $searchText)
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textPrimary)
                            .autocorrectionDisabled()
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.surfaceColor.opacity(0.8))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    
                    // Selected players preview with stacked avatars
                    let newlySelected = selectedPlayerIds.subtracting(Set(team.playerIds))
                    if !newlySelected.isEmpty {
                        VStack(spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: -8) {
                                    ForEach(Array(newlySelected.prefix(8)), id: \.self) { playerId in
                                        if let student = dataManager.students.first(where: { $0.id == playerId }) {
                                            ZStack {
                                                Circle()
                                                    .fill(team.primaryColor.opacity(0.4))
                                                    .frame(width: 44, height: 44)
                                                    .blur(radius: 5)
                                                
                                                Circle()
                                                    .fill(Color.avatarColor(student.avatarColor))
                                                    .frame(width: 36, height: 36)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(team.primaryColor, lineWidth: 2)
                                                    )
                                                
                                                Text(student.initials)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    
                                    if newlySelected.count > 8 {
                                        ZStack {
                                            Circle()
                                                .fill(team.primaryColor.opacity(0.2))
                                                .frame(width: 36, height: 36)
                                            Text("+\(newlySelected.count - 8)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(team.primaryColor)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            
                            HStack {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(team.primaryColor)
                                Text("\(newlySelected.count) new player\(newlySelected.count == 1 ? "" : "s") to add")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(team.primaryColor)
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedPlayerIds = Set(team.playerIds)
                                    }
                                    HapticFeedback.impact(.light)
                                }) {
                                    Text("Clear")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(team.primaryColor.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(team.primaryColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    
                    // Player List
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if filteredPlayers.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                                        .font(.system(size: 40))
                                        .foregroundColor(AppTheme.textTertiary)
                                    Text(searchText.isEmpty ? "All students are already on this team" : "No students found")
                                        .font(.system(size: 15))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else {
                                ForEach(filteredPlayers) { student in
                                    PlayerSelectionPanelRow(
                                        student: student,
                                        isSelected: selectedPlayerIds.contains(student.id),
                                        teamColor: team.primaryColor
                                    ) {
                                        withAnimation(.spring(response: 0.25)) {
                                            if selectedPlayerIds.contains(student.id) {
                                                selectedPlayerIds.remove(student.id)
                                            } else {
                                                selectedPlayerIds.insert(student.id)
                                            }
                                        }
                                        HapticFeedback.impact(.light)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
                .frame(width: min(geometry.size.width * 0.85, 360))
                .background(
                    ZStack {
                        // Frosted glass effect
                        #if os(iOS)
                        VisualEffectBlur(blurStyle: .systemThinMaterial)
                        #else
                        VisualEffectBlur()
                        #endif
                        
                        // Subtle gradient overlay
                        LinearGradient(
                            colors: [
                                AppTheme.background.opacity(0.3),
                                AppTheme.background.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: -5, y: 0)
                .padding(.vertical, 8)
                .padding(.trailing, 8)
            }
        }
        .ignoresSafeArea()
    }
    
    private func saveAndDismiss() {
        var updatedTeam = team
        updatedTeam.playerIds = Array(selectedPlayerIds)
        dataManager.updateTeam(updatedTeam)
        HapticFeedback.notification(.success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

// MARK: - Player Selection Panel Row (Flashy Version)
struct PlayerSelectionPanelRow: View {
    let student: Student
    let isSelected: Bool
    let teamColor: Color
    let action: () -> Void
    
    @State private var isPressing = false
    
    init(student: Student, isSelected: Bool, teamColor: Color = AppTheme.accentColor, action: @escaping () -> Void) {
        self.student = student
        self.isSelected = isSelected
        self.teamColor = teamColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Avatar with glow effect when selected
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(teamColor.opacity(0.4))
                            .frame(width: 52, height: 52)
                            .blur(radius: 6)
                    }
                    
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? teamColor : Color.clear, lineWidth: 2.5)
                        )
                        .shadow(color: isSelected ? teamColor.opacity(0.3) : Color.clear, radius: 8)
                    
                    Text(student.initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Name and details - language-aware
                VStack(alignment: .leading, spacing: 3) {
                    if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.chineseName!)
                                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                            Text(student.name)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    } else {
                        Text(student.name)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                    }
                    
                    HStack(spacing: 8) {
                        if let age = student.age {
                            Text("\(age) years")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        // Only show Chinese name in English mode
                        if LocalizationManager.shared.currentLanguage != .chinese, let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                // Animated selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? teamColor : Color.clear)
                        .frame(width: 26, height: 26)
                    
                    Circle()
                        .stroke(isSelected ? teamColor : AppTheme.textTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? teamColor.opacity(0.1) : AppTheme.surfaceColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? teamColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
            .shadow(color: isSelected ? teamColor.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isPressing ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressing = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressing = false
                    }
                }
        )
    }
}

// MARK: - Visual Effect Blur (Cross-platform)
#if os(iOS)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
#else
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

// MARK: - Edit Team View
struct EditTeamView: View {
    let team: Team
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName: String
    @State private var shortName: String
    @State private var coachName: String
    @State private var venue: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var selectedPreset: TeamPreset? = nil
    
    let teamColors: [String] = [
        "#E94560", "#7C3AED", "#3B82F6", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#06B6D4", "#84CC16",
        "#1F2937", "#78716C", "#B45309", "#CA8A04", "#DC2626"
    ]
    
    let teamIcons: [String] = [
        "basketball.fill", "flame.fill", "bird.fill", "cat.fill",
        "dog.fill", "bolt.fill", "star.fill", "crown.fill",
        "shield.fill", "trophy.fill", "pawprint.fill", "leaf.fill",
        "moon.fill", "snowflake", "wind", "mountain.2.fill",
        "water.waves", "sparkles", "cloud.fill", "drop.fill"
    ]
    
    init(team: Team) {
        self.team = team
        _teamName = State(initialValue: team.name)
        _shortName = State(initialValue: team.shortName)
        _coachName = State(initialValue: team.coachName ?? "")
        _venue = State(initialValue: team.homeVenue ?? "")
        _selectedColor = State(initialValue: team.colorHex)
        _selectedIcon = State(initialValue: team.logoSystemImage)
        // Initialize preset if team has a mascot
        if let mascot = team.mascotType {
            _selectedPreset = State(initialValue: TeamPreset(mascot: mascot))
        }
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Team Preview
                    VStack(spacing: 16) {
                        // Show mascot logo if preset selected, otherwise show SF Symbol
                        if let mascot = selectedPreset?.mascot {
                            TeamMascotLogo(mascot: mascot, size: 80, showGlow: true)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: selectedColor), Color(hex: selectedColor).opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text(teamName.isEmpty ? "Team Name" : teamName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(teamName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                            
                            Text(shortName.isEmpty ? "ABC" : shortName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            if !coachName.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10))
                                    Text("Coach: \(coachName)")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                    
                    // Team Presets
                    editTeamPresetsSection
                    
                    // Team Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Team Info")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        VStack(spacing: 12) {
                            TextField("Team Name", text: $teamName)
                                .textFieldStyle(.plain)
                                .padding(14)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            
                            TextField("Short Name (3 letters)", text: $shortName)
                                .textFieldStyle(.plain)
                                .textCase(.uppercase)
                                .onChange(of: shortName) { _, newValue in
                                    shortName = String(newValue.uppercased().prefix(3))
                                }
                                .padding(14)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            
                            // Venue Picker (from Organization locations)
                            if !dataManager.locations.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Home Venue")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            // Option to clear venue
                                            Button(action: { venue = "" }) {
                                                Text(isChinese ? "无" : "None")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(venue.isEmpty ? .white : AppTheme.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(venue.isEmpty ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                    .cornerRadius(8)
                                            }
                                            
                                            ForEach(dataManager.locations.filter { $0.isActive }) { location in
                                                Button(action: { venue = location.name }) {
                                                    Text(location.name)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(venue == location.name ? .white : AppTheme.textSecondary)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 8)
                                                        .background(venue == location.name ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                        .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                TextField("Home Venue (optional)", text: $venue)
                                    .textFieldStyle(.plain)
                                    .padding(14)
                                    .background(AppTheme.surfaceColor)
                                    .cornerRadius(12)
                            }
                            
                            // Coach Picker (from Organization staff)
                            if !dataManager.staffCoaches.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Coach")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            // Option to clear coach
                                            Button(action: { coachName = "" }) {
                                                Text(isChinese ? "无" : "None")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(coachName.isEmpty ? .white : AppTheme.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(coachName.isEmpty ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                    .cornerRadius(8)
                                            }
                                            
                                            ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                                                Button(action: { coachName = coach.name }) {
                                                    HStack(spacing: 6) {
                                                        ZStack {
                                                            Circle()
                                                                .fill(Color.avatarColor(coach.avatarColor))
                                                                .frame(width: 24, height: 24)
                                                            Text(coach.initials)
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(.white)
                                                        }
                                                        Text(coach.name)
                                                            .font(.system(size: 13, weight: .medium))
                                                    }
                                                    .foregroundColor(coachName == coach.name ? .white : AppTheme.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(coachName == coach.name ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                TextField("Coach Name", text: $coachName)
                                    .textFieldStyle(.plain)
                                    .padding(14)
                                    .background(AppTheme.surfaceColor)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Team Color
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team Color")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(teamColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                                    .shadow(color: selectedColor == color ? Color(hex: color).opacity(0.5) : .clear, radius: 8)
                                    .onTapGesture { selectedColor = color }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Team Icon
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team Icon")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(teamIcons, id: \.self) { icon in
                                ZStack {
                                    Circle()
                                        .fill(selectedIcon == icon ? Color(hex: selectedColor) : AppTheme.surfaceColor)
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(selectedIcon == icon ? .white : AppTheme.textSecondary)
                                }
                                .onTapGesture { selectedIcon = icon }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(AppTheme.background)
            .navigationTitle("Edit Team")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTeam()
                    }
                    .fontWeight(.semibold)
                    .disabled(teamName.isEmpty || shortName.count < 2)
                }
            }
        }
    }
    
    // MARK: - Team Presets Section
    private var editTeamPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Select")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                if selectedPreset != nil {
                    Button(action: clearPreset) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(TeamPreset.presets) { preset in
                        TeamPresetCard(
                            preset: preset,
                            isSelected: selectedPreset?.name == preset.name,
                            action: { selectPreset(preset) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func selectPreset(_ preset: TeamPreset) {
        withAnimation(.spring(response: 0.3)) {
            selectedPreset = preset
            teamName = preset.name
            shortName = preset.shortName
            selectedColor = preset.colorHex
            selectedIcon = preset.icon
        }
        
        // Haptic feedback
        HapticFeedback.impact(.light)
    }
    
    private func clearPreset() {
        withAnimation(.spring(response: 0.3)) {
            selectedPreset = nil
        }
    }
    
    private func saveTeam() {
        var updatedTeam = team
        updatedTeam.name = teamName
        updatedTeam.shortName = String(shortName.prefix(3))
        updatedTeam.coachName = coachName.isEmpty ? nil : coachName
        updatedTeam.homeVenue = venue.isEmpty ? nil : venue
        updatedTeam.colorHex = selectedColor
        updatedTeam.logoSystemImage = selectedIcon
        updatedTeam.mascotTypeRaw = selectedPreset?.mascot.rawValue  // Save mascot type
        updatedTeam.updatedAt = Date()
        
        dataManager.updateTeam(updatedTeam)
        dismiss()
    }
}

#Preview {
    TeamDetailView(team: Team.samples[0])
        .environmentObject(DataManager.shared)
}
