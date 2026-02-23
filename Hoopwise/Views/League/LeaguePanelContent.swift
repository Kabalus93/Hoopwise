import SwiftUI

// MARK: - Create Team Panel Content
struct CreateTeamPanelContent: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName = ""
    @State private var shortName = ""
    @State private var selectedColor = "#E94560"
    @State private var selectedSecondaryColor = "#1A1A2E"
    @State private var selectedIcon = "basketball.fill"
    @State private var selectedPlayerIds: Set<UUID> = []
    @State private var selectedPreset: TeamPreset? = nil
    @State private var venue = ""
    @State private var coachName = ""
    @State private var selectedCoachId: UUID?
    @State private var showingPlayerSelector = false
    
    let teamColors: [String] = [
        "#E94560", "#7C3AED", "#3B82F6", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#06B6D4", "#84CC16",
        "#1F2937", "#78716C", "#B45309", "#CA8A04", "#DC2626"
    ]
    
    let teamIcons: [String] = [
        "basketball.fill", "flame.fill", "bird.fill", "cat.fill",
        "dog.fill", "bolt.fill", "star.fill", "crown.fill",
        "shield.fill", "trophy.fill", "pawprint.fill", "leaf.fill",
        "moon.fill", "snowflake", "wind", "mountain.2.fill"
    ]
    
    var canCreate: Bool {
        !teamName.isEmpty && shortName.count >= 2
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Team Preview Card
                PanelSectionCard("Preview", icon: "eye") {
                    VStack(spacing: 10) {
                        TeamMascotLogo(mascot: selectedPreset?.mascot ?? .tiger, size: 56, showGlow: selectedPreset != nil)
                        
                        VStack(spacing: 4) {
                            Text(teamName.isEmpty ? "Team Name" : teamName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(teamName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                            
                            PanelBadge(text: shortName.isEmpty ? "ABC" : shortName, color: Color(hex: selectedColor))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                // Quick Select Presets
                PanelSectionCard("Quick Select", icon: "sparkles") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TeamPreset.presets) { preset in
                                Button(action: { selectPreset(preset) }) {
                                    VStack(spacing: 4) {
                                        TeamMascotLogo(mascot: preset.mascot, size: 36, showGlow: false)
                                        Text(preset.shortName)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(selectedPreset?.name == preset.name ? AppTheme.textPrimary : AppTheme.textSecondary)
                                    }
                                    .padding(8)
                                    .background(selectedPreset?.name == preset.name ? AppTheme.accentColor.opacity(0.15) : Color.clear)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedPreset?.name == preset.name ? Color(hex: preset.colorHex) : .clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Team Info
                PanelSectionCard("Team Info", icon: "info.circle") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Name")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("Team Name", text: $teamName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Short Name")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("ABC", text: $shortName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 60)
                                .onChange(of: shortName) { _, newValue in
                                    shortName = String(newValue.uppercased().prefix(3))
                                }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Coach")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            if dataManager.staffCoaches.isEmpty {
                                TextField("Coach Name", text: $coachName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            } else {
                                Menu {
                                    Button("None") {
                                        selectedCoachId = nil
                                        coachName = ""
                                    }
                                    ForEach(dataManager.staffCoaches) { coach in
                                        Button(coach.name) {
                                            selectedCoachId = coach.id
                                            coachName = coach.name
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(coachName.isEmpty ? "Select Coach" : coachName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(coachName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Team Color
                PanelSectionCard("Team Color", icon: "paintpalette") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(teamColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .shadow(color: selectedColor == color ? Color(hex: color).opacity(0.5) : .clear, radius: 4)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedColor = color
                                    }
                                    HapticFeedback.impact(.light)
                                }
                        }
                    }
                }
                
                // Team Icon
                PanelSectionCard("Team Icon", icon: "star") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(teamIcons, id: \.self) { icon in
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ? Color(hex: selectedColor) : AppTheme.surfaceColor)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(selectedIcon == icon ? .white : AppTheme.textSecondary)
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedIcon = icon
                                }
                                HapticFeedback.impact(.light)
                            }
                        }
                    }
                }
                
                // Players - Inline Selection with Flashy UI
                PanelSectionCard("Roster", icon: "person.3") {
                    VStack(spacing: 12) {
                        // Selected players preview with animated badges
                        if !selectedPlayerIds.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: -8) {
                                    ForEach(Array(selectedPlayerIds.prefix(8)), id: \.self) { playerId in
                                        if let student = dataManager.students.first(where: { $0.id == playerId }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.avatarColor(student.avatarColor))
                                                    .frame(width: 32, height: 32)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color(hex: selectedColor), lineWidth: 2)
                                                    )
                                                    .shadow(color: Color(hex: selectedColor).opacity(0.3), radius: 4)
                                                Text(student.initials)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    
                                    if selectedPlayerIds.count > 8 {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: selectedColor).opacity(0.2))
                                                .frame(width: 32, height: 32)
                                            Text("+\(selectedPlayerIds.count - 8)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(Color(hex: selectedColor))
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                            
                            HStack {
                                Text("\(selectedPlayerIds.count) player\(selectedPlayerIds.count == 1 ? "" : "s") selected")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: selectedColor))
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedPlayerIds.removeAll()
                                    }
                                }) {
                                    Text("Clear")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Expandable player list
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingPlayerSelector.toggle()
                            }
                        }) {
                            HStack {
                                Image(systemName: showingPlayerSelector ? "chevron.up.circle.fill" : "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: selectedColor))
                                Text(showingPlayerSelector ? "Hide Players" : "Add Players")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if !showingPlayerSelector {
                                    Text("\(dataManager.students.count) available")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: selectedColor).opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Inline player grid (expandable)
                        if showingPlayerSelector {
                            VStack(spacing: 8) {
                                if dataManager.students.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.badge.plus")
                                            .font(.system(size: 24))
                                            .foregroundColor(AppTheme.textTertiary)
                                        Text("No students available")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textSecondary)
                                        Text("Add students in the Hub first")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                } else {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                        ForEach(dataManager.students) { student in
                                            FlashyPlayerSelectionCard(
                                                student: student,
                                                isSelected: selectedPlayerIds.contains(student.id),
                                                teamColor: Color(hex: selectedColor)
                                            ) {
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
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
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                        }
                    }
                }
                
                // Create Button
                PanelActionButton(title: "Create Team", icon: "plus.circle.fill", color: Color(hex: selectedColor)) {
                    createTeam()
                }
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.5)
            }
            .padding(16)
        }
        .overlay {
            if showingPlayerSelector {
                PlayerSelectorPanel(
                    selectedPlayerIds: $selectedPlayerIds,
                    isPresented: $showingPlayerSelector,
                    students: dataManager.students
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingPlayerSelector)
    }
    
    private func selectPreset(_ preset: TeamPreset) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedPreset = preset
            teamName = preset.name
            shortName = preset.shortName
            selectedColor = preset.colorHex
            selectedSecondaryColor = preset.secondaryColorHex
            selectedIcon = preset.icon
        }
        HapticFeedback.impact(.light)
    }
    
    private func createTeam() {
        var team = Team(
            name: teamName,
            shortName: shortName,
            colorHex: selectedColor,
            secondaryColorHex: selectedSecondaryColor,
            logoSystemImage: selectedIcon,
            playerIds: Array(selectedPlayerIds),
            coachId: selectedCoachId,
            coachName: coachName.isEmpty ? nil : coachName,
            homeVenue: venue.isEmpty ? nil : venue
        )
        
        // Save mascot type from preset if selected
        if let mascot = selectedPreset?.mascot {
            team.mascotTypeRaw = mascot.rawValue
        }
        
        dataManager.addTeam(team)
        HapticFeedback.notification(.success)
        
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Schedule Game Panel Content
struct ScheduleGamePanelContent: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    
    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var gameDate = Date()
    @State private var venue = ""
    @State private var notes = ""
    @State private var selectedLocationId: UUID?
    @State private var selectedRefereeId: UUID?
    
    var canSchedule: Bool {
        homeTeamId != nil && awayTeamId != nil && homeTeamId != awayTeamId
    }
    
    var selectedHomeTeam: Team? {
        guard let id = homeTeamId else { return nil }
        return dataManager.teams.first { $0.id == id }
    }
    
    var selectedAwayTeam: Team? {
        guard let id = awayTeamId else { return nil }
        return dataManager.teams.first { $0.id == id }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Game Preview
                PanelSectionCard("Matchup", icon: "sportscourt") {
                    if let home = selectedHomeTeam, let away = selectedAwayTeam {
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                TeamLogo(team: away, size: 44)
                                Text(away.shortName)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            
                            VStack(spacing: 2) {
                                Text("@")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text(gameDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            
                            VStack(spacing: 4) {
                                TeamLogo(team: home, size: 44)
                                Text(home.shortName)
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 16) {
                            Circle().fill(AppTheme.surfaceColor).frame(width: 44, height: 44)
                            Text("vs").font(.system(size: 16, weight: .bold)).foregroundColor(AppTheme.textTertiary)
                            Circle().fill(AppTheme.surfaceColor).frame(width: 44, height: 44)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                
                if dataManager.teams.count < 2 {
                    PanelEmptyState(
                        icon: "person.3",
                        title: "Need at least 2 teams",
                        subtitle: "Create more teams to schedule games"
                    )
                } else {
                    // Away Team
                    PanelSectionCard("Away Team", icon: "airplane.departure") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(dataManager.teams.filter { $0.id != homeTeamId }) { team in
                                    teamButton(team: team, isSelected: awayTeamId == team.id) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            awayTeamId = team.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Home Team
                    PanelSectionCard("Home Team", icon: "house") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(dataManager.teams.filter { $0.id != awayTeamId }) { team in
                                    teamButton(team: team, isSelected: homeTeamId == team.id) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            homeTeamId = team.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Date & Time
                PanelSectionCard("Date & Time", icon: "calendar") {
                    DatePicker(
                        "Game Date",
                        selection: $gameDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
                
                // Venue
                if !dataManager.locations.isEmpty {
                    PanelSectionCard("Venue", icon: "mappin.circle") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(dataManager.locations.filter { $0.isActive }) { location in
                                    Button(action: { 
                                        venue = location.name
                                        selectedLocationId = location.id
                                    }) {
                                        VStack(spacing: 4) {
                                            Image(systemName: location.courtType.icon)
                                                .font(.system(size: 14))
                                            Text(location.name)
                                                .font(.system(size: 10, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(selectedLocationId == location.id ? .white : AppTheme.textSecondary)
                                        .frame(width: 60)
                                        .padding(.vertical, 8)
                                        .background(selectedLocationId == location.id ? location.courtType.color : AppTheme.surfaceColor)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                // Referee
                if !dataManager.staffCoaches.isEmpty {
                    PanelSectionCard("Referee", icon: "person.badge.shield.checkmark") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // No referee option
                                Button(action: { selectedRefereeId = nil }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "person.slash")
                                            .font(.system(size: 14))
                                        Text("None")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(selectedRefereeId == nil ? .white : AppTheme.textSecondary)
                                    .frame(width: 60)
                                    .padding(.vertical, 8)
                                    .background(selectedRefereeId == nil ? Color.gray : AppTheme.surfaceColor)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(dataManager.staffCoaches) { coach in
                                    Button(action: { selectedRefereeId = coach.id }) {
                                        VStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.avatarColor(coach.avatarColor))
                                                .frame(width: 24, height: 24)
                                                .overlay(
                                                    Text(String(coach.name.prefix(1)))
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.white)
                                                )
                                            Text(coach.name.components(separatedBy: " ").first ?? coach.name)
                                                .font(.system(size: 10, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(selectedRefereeId == coach.id ? .white : AppTheme.textSecondary)
                                        .frame(width: 60)
                                        .padding(.vertical, 8)
                                        .background(selectedRefereeId == coach.id ? Color.purple : AppTheme.surfaceColor)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                // Schedule Button
                PanelActionButton(title: "Schedule Game", icon: "calendar.badge.plus") {
                    scheduleGame()
                }
                .disabled(!canSchedule)
                .opacity(canSchedule ? 1 : 0.5)
            }
            .padding(16)
        }
    }
    
    private func teamButton(team: Team, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                TeamLogo(team: team, size: 40)
                Text(team.shortName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
            .padding(8)
            .background(isSelected ? AppTheme.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? team.primaryColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func scheduleGame() {
        guard let homeId = homeTeamId, let awayId = awayTeamId else { return }
        
        let game = Game(
            homeTeamId: homeId,
            awayTeamId: awayId,
            date: gameDate,
            venue: venue.isEmpty ? nil : venue,
            locationId: selectedLocationId,
            refereeId: selectedRefereeId,
            notes: notes.isEmpty ? nil : notes
        )
        
        dataManager.addGame(game)
        HapticFeedback.notification(.success)
        
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Team Detail Panel Content
struct TeamDetailPanelContent: View {
    let team: Team
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: TeamTab = .roster
    @State private var showingAddPlayer = false
    @State private var showingEditTeam = false
    
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
        HStack(spacing: 0) {
            // Main Team Detail Column
            teamDetailColumn
                .frame(minWidth: 340, idealWidth: showingAddPlayer ? 380 : 420)
            
            // Divider when showing add player
            if showingAddPlayer {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
            }
            
            // Add Player Column (slides in from right)
            if showingAddPlayer {
                addPlayerColumn
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingAddPlayer)
    }
    
    private var teamDetailColumn: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Team Header - matches Student profile style
                VStack(spacing: 12) {
                    TeamLogo(team: team, size: 64)
                    
                    VStack(spacing: 4) {
                        Text(team.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        HStack(spacing: 8) {
                            PanelBadge(text: team.shortName, color: team.primaryColor)
                            
                            if let coachName = team.coachName, !coachName.isEmpty {
                                Text("Coach: \(coachName)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // Quick Stats - matches Student stat pills
                HStack(spacing: 8) {
                    PanelStatPill(
                        value: "\(teamPlayers.count)",
                        unit: "",
                        label: "Players",
                        color: team.primaryColor
                    )
                    
                    if let standing = standing {
                        PanelStatPill(
                            value: standing.record,
                            unit: "",
                            label: "Record",
                            color: standing.wins >= standing.losses ? .green : .red
                        )
                        
                        let ppg = Double(standing.pointsFor) / max(1, Double(standing.gamesPlayed))
                        PanelStatPill(
                            value: String(format: "%.1f", ppg),
                            unit: "",
                            label: "PPG",
                            color: .blue
                        )
                    } else {
                        PanelStatPill(value: "0-0", unit: "", label: "Record", color: .gray)
                        PanelStatPill(value: "--", unit: "", label: "PPG", color: .gray)
                    }
                }
                
                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(TeamTab.allCases, id: \.self) { tab in
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab 
                            }
                        }) {
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? team.primaryColor : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? team.primaryColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AppTheme.surfaceColor)
                .cornerRadius(8)
                
                // Content
                switch selectedTab {
                case .roster:
                    rosterContent
                case .schedule:
                    scheduleContent
                case .stats:
                    statsContent
                }
                
                // Actions
                HStack(spacing: 10) {
                    PanelActionButton(title: "Add Player", icon: "person.badge.plus", color: team.primaryColor) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingAddPlayer = true 
                        }
                    }
                    
                    Button(action: deleteTeam) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Add Player Column (Finder-style)
    private var addPlayerColumn: some View {
        AddPlayerColumnView(team: team, isPresented: $showingAddPlayer)
            .environmentObject(dataManager)
    }
    
    private var rosterContent: some View {
        PanelSectionCard("Roster", icon: "person.3") {
            if teamPlayers.isEmpty {
                PanelEmptyState(
                    icon: "person.3",
                    title: "No players on this team",
                    action: { showingAddPlayer = true },
                    actionLabel: "Add Players",
                    actionColor: team.primaryColor
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(teamPlayers.enumerated()), id: \.element.id) { index, student in
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                PanelAvatar(initials: student.initials, color: Color.avatarColor(student.avatarColor), size: 36)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(student.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    if let age = student.age {
                                        Text("\(age) yrs")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                }
                                
                                Spacer()
                                
                                if let stats = dataManager.seasonStats.first(where: { $0.playerId == student.id }) {
                                    HStack(spacing: 8) {
                                        VStack(spacing: 0) {
                                            Text(String(format: "%.0f", stats.ppg))
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                            Text("PTS")
                                                .font(.system(size: 7, weight: .medium))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        VStack(spacing: 0) {
                                            Text(String(format: "%.0f", stats.rpg))
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                            Text("REB")
                                                .font(.system(size: 7, weight: .medium))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            
                            if index < teamPlayers.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var scheduleContent: some View {
        PanelSectionCard("Schedule", icon: "calendar") {
            if teamGames.isEmpty {
                PanelEmptyState(
                    icon: "calendar",
                    title: "No games scheduled"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(teamGames.prefix(8).enumerated()), id: \.element.id) { index, game in
                        VStack(spacing: 0) {
                            gameRow(game)
                            
                            if index < min(teamGames.count, 8) - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func gameRow(_ game: Game) -> some View {
        let opponent = game.homeTeamId == team.id 
            ? dataManager.teams.first { $0.id == game.awayTeamId }
            : dataManager.teams.first { $0.id == game.homeTeamId }
        let isHome = game.homeTeamId == team.id
        let teamScore = isHome ? game.homeScore : game.awayScore
        let opponentScore = isHome ? game.awayScore : game.homeScore
        let won = teamScore > opponentScore
        
        return HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(game.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(game.date.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(width: 32)
            
            TeamLogo(team: opponent, size: 28)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(isHome ? "vs" : "@")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(opponent?.name ?? "Unknown")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text(game.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            if game.status == .finished {
                VStack(spacing: 0) {
                    Text(won ? "W" : "L")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(won ? .green : .red)
                    Text("\(teamScore)-\(opponentScore)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            } else if game.status == .live {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                }
            } else {
                Text("Scheduled")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statsContent: some View {
        VStack(spacing: 12) {
            if let standing = standing {
                PanelSectionCard("Season Record", icon: "chart.bar") {
                    VStack(spacing: 10) {
                        PanelInfoRow(label: "Wins", value: "\(standing.wins)", icon: "checkmark.circle", valueColor: .green)
                        Divider()
                        PanelInfoRow(label: "Losses", value: "\(standing.losses)", icon: "xmark.circle", valueColor: .red)
                        Divider()
                        PanelInfoRow(label: "Games Played", value: "\(standing.gamesPlayed)", icon: "sportscourt")
                    }
                }
                
                PanelSectionCard("Performance", icon: "flame") {
                    let ppg = Double(standing.pointsFor) / max(1, Double(standing.gamesPlayed))
                    let oppg = Double(standing.pointsAgainst) / max(1, Double(standing.gamesPlayed))
                    
                    VStack(spacing: 10) {
                        PanelInfoRow(label: "Points Per Game", value: String(format: "%.1f", ppg), icon: "basketball", valueColor: team.primaryColor)
                        Divider()
                        PanelInfoRow(label: "Opponent PPG", value: String(format: "%.1f", oppg), icon: "basketball")
                        Divider()
                        PanelInfoRow(
                            label: "Point Differential",
                            value: standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)",
                            icon: "plus.forwardslash.minus",
                            valueColor: standing.pointDifferential >= 0 ? .green : .red
                        )
                    }
                }
            } else {
                PanelEmptyState(
                    icon: "chart.bar",
                    title: "No stats available yet",
                    subtitle: "Play some games to see team stats"
                )
            }
        }
    }
    
    private func deleteTeam() {
        dataManager.deleteTeam(team)
        HapticFeedback.notification(.warning)
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Game Detail Panel Content
struct GameDetailPanelContent: View {
    let gameId: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: GameTab = .boxScore
    @State private var showingAddScore = false
    @State private var selectedTeamForScore: UUID?
    @State private var selectedPlayerForScore: UUID?
    @State private var selectedPoints: Int = 2
    @State private var selectedPlayType: ScoringPlayType = .jumpShot
    
    // Legacy initializer for backward compatibility
    init(game: Game, isPresented: Binding<Bool>) {
        self.gameId = game.id
        self._isPresented = isPresented
    }
    
    enum GameTab: String, CaseIterable {
        case boxScore = "Box Score"
        case playByPlay = "Play-by-Play"
    }
    
    // Get the current game from data manager (reactive to updates)
    var game: Game {
        dataManager.games.first { $0.id == gameId } ?? Game(
            homeTeamId: UUID(),
            awayTeamId: UUID(),
            date: Date(),
            venue: ""
        )
    }
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Score Header - matches Student profile header style
                VStack(spacing: 12) {
                    // Status
                    if game.status == .live {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text(game.quarterDisplay ?? "LIVE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Teams and Score
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            TeamLogo(team: awayTeam, size: 48)
                            Text(awayTeam?.shortName ?? "AWY")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        
                        HStack(spacing: 8) {
                            Text("\(game.awayScore)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(game.awayScore >= game.homeScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                            
                            Text("-")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            Text("\(game.homeScore)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(game.homeScore >= game.awayScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                        }
                        .frame(minWidth: 100)
                        
                        VStack(spacing: 4) {
                            TeamLogo(team: homeTeam, size: 48)
                            Text(homeTeam?.shortName ?? "HME")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Game Info
                    HStack(spacing: 6) {
                        Text(game.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        if let venue = game.venue, !venue.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(venue)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // Quick Actions
                if game.status != .finished {
                    HStack(spacing: 10) {
                        if game.status == .scheduled {
                            PanelActionButton(title: "Start Game", icon: "play.fill", color: .green) {
                                startGame()
                            }
                        }
                        
                        if game.status == .live {
                            PanelActionButton(title: "End Game", icon: "stop.fill", style: .destructive) {
                                endGame()
                            }
                        }
                    }
                }
                
                // Score Tracking (for live or finished games that need editing)
                if game.status == .live || game.status == .finished {
                    scoreTrackingSection
                }
                
                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(GameTab.allCases, id: \.self) { tab in
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab 
                            }
                        }) {
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? AppTheme.accentColor : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AppTheme.surfaceColor)
                .cornerRadius(8)
                
                // Content
                switch selectedTab {
                case .boxScore:
                    boxScoreContent
                case .playByPlay:
                    playByPlayContent
                }
            }
            .padding(16)
        }
    }
    
    private var boxScoreContent: some View {
        VStack(spacing: 12) {
            if let away = awayTeam {
                teamBoxScore(team: away, isHome: false)
            }
            if let home = homeTeam {
                teamBoxScore(team: home, isHome: true)
            }
        }
    }
    
    private func teamBoxScore(team: Team, isHome: Bool) -> some View {
        let score = isHome ? game.homeScore : game.awayScore
        let isWinning = isHome ? (game.homeScore > game.awayScore) : (game.awayScore > game.homeScore)
        let teamPlayers = dataManager.students.filter { team.playerIds.contains($0.id) }
        
        return PanelSectionCard(team.name, icon: "person.3", showDivider: true) {
            VStack(spacing: 0) {
                // Team score header
                HStack {
                    TeamLogo(team: team, size: 24)
                    Text(team.shortName)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(isWinning ? team.primaryColor : AppTheme.textSecondary)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Players
                if teamPlayers.isEmpty {
                    Text("No players on roster")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(teamPlayers.prefix(5).enumerated()), id: \.element.id) { index, student in
                        // Get the Player for this student to look up game stats
                        let playerForStudent = dataManager.players.first { $0.studentId == student.id }
                        let gameStats = playerForStudent.flatMap { p in game.playerStats.first { $0.playerId == p.id } }
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(student.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                // Show game stats from current game's playerStats
                                if let gameStats = gameStats {
                                    HStack(spacing: 10) {
                                        VStack(spacing: 0) {
                                            Text("\(gameStats.points)")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(gameStats.points > 0 ? team.primaryColor : AppTheme.textPrimary)
                                            Text("PTS").font(.system(size: 7)).foregroundColor(AppTheme.textTertiary)
                                        }
                                        VStack(spacing: 0) {
                                            Text("\(gameStats.rebounds)")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(gameStats.rebounds > 0 ? .purple : AppTheme.textPrimary)
                                            Text("REB").font(.system(size: 7)).foregroundColor(AppTheme.textTertiary)
                                        }
                                        VStack(spacing: 0) {
                                            Text("\(gameStats.assists)")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(gameStats.assists > 0 ? .cyan : AppTheme.textPrimary)
                                            Text("AST").font(.system(size: 7)).foregroundColor(AppTheme.textTertiary)
                                        }
                                    }
                                } else {
                                    // No stats yet for this player in this game
                                    Text("-")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                            .padding(.vertical, 6)
                            
                            if index < min(teamPlayers.count, 5) - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var playByPlayContent: some View {
        PanelSectionCard("Play-by-Play", icon: "list.bullet") {
            if game.scoringPlays.isEmpty {
                PanelEmptyState(
                    icon: "list.bullet.rectangle",
                    title: "No plays recorded"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(game.scoringPlays.reversed().enumerated()), id: \.element.id) { index, play in
                        let team = play.teamId == game.homeTeamId ? homeTeam : awayTeam
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                PanelBadge(text: "Q\(play.quarter)", color: team?.primaryColor ?? AppTheme.accentColor)
                                
                                if let player = dataManager.students.first(where: { $0.id == play.playerId }) {
                                    Text(player.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Text("+\(play.points)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(team?.primaryColor ?? AppTheme.accentColor)
                            }
                            .padding(.vertical, 6)
                            
                            if index < game.scoringPlays.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Score Tracking Section
    private var scoreTrackingSection: some View {
        PanelSectionCard("Add Score", icon: "plus.circle.fill") {
            VStack(spacing: 16) {
                // Team Selection
                HStack(spacing: 12) {
                    if let away = awayTeam {
                        teamScoreButton(team: away, isHome: false)
                    }
                    if let home = homeTeam {
                        teamScoreButton(team: home, isHome: true)
                    }
                }
                
                // Points Selection (when team is selected)
                if selectedTeamForScore != nil {
                    VStack(spacing: 12) {
                        // Points buttons
                        HStack(spacing: 8) {
                            ForEach([1, 2, 3], id: \.self) { points in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedPoints = points
                                        selectedPlayType = ScoringPlayType.typesFor(points: points).first ?? .jumpShot
                                    }
                                } label: {
                                    Text("+\(points)")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedPoints == points ? .white : AppTheme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedPoints == points ? pointsColor(points) : AppTheme.surfaceColor)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Player Selection
                        if let teamId = selectedTeamForScore,
                           let team = dataManager.teams.first(where: { $0.id == teamId }) {
                            let teamPlayers = dataManager.students.filter { team.playerIds.contains($0.id) }
                            
                            if !teamPlayers.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(teamPlayers) { player in
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    selectedPlayerForScore = player.id
                                                }
                                            } label: {
                                                VStack(spacing: 4) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(Color.avatarColor(player.avatarColor))
                                                            .frame(width: 36, height: 36)
                                                        Text(player.initials)
                                                            .font(.system(size: 11, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                    .overlay(
                                                        Circle()
                                                            .stroke(selectedPlayerForScore == player.id ? team.primaryColor : .clear, lineWidth: 2)
                                                    )
                                                    Text(player.name.components(separatedBy: " ").first ?? player.name)
                                                        .font(.system(size: 9))
                                                        .foregroundColor(selectedPlayerForScore == player.id ? AppTheme.textPrimary : AppTheme.textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Add Score Button
                        Button {
                            addScore()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add \(selectedPoints) Point\(selectedPoints == 1 ? "" : "s")")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(pointsColor(selectedPoints))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedPlayerForScore == nil)
                        .opacity(selectedPlayerForScore == nil ? 0.5 : 1)
                    }
                }
            }
        }
    }
    
    private func teamScoreButton(team: Team, isHome: Bool) -> some View {
        let isSelected = selectedTeamForScore == team.id
        let teamScore = isHome ? game.homeScore : game.awayScore
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedTeamForScore == team.id {
                    selectedTeamForScore = nil
                    selectedPlayerForScore = nil
                } else {
                    selectedTeamForScore = team.id
                    selectedPlayerForScore = nil
                }
            }
        } label: {
            VStack(spacing: 6) {
                TeamLogo(team: team, size: 36)
                Text(team.shortName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? team.primaryColor : AppTheme.textSecondary)
                Text("\(teamScore)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? team.primaryColor.opacity(0.15) : AppTheme.surfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? team.primaryColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func pointsColor(_ points: Int) -> Color {
        switch points {
        case 1: return .orange
        case 2: return AppTheme.accentColor
        case 3: return .green
        default: return AppTheme.accentColor
        }
    }
    
    private func addScore() {
        guard let teamId = selectedTeamForScore,
              let studentId = selectedPlayerForScore else { return }
        
        // Find the player ID for this student (or use student ID if no player record exists)
        // In the league context, we use student IDs directly since teams contain student IDs
        let playerId = studentId
        
        // Create scoring play
        let scoringPlay = ScoringPlay(
            gameId: game.id,
            playerId: playerId,
            teamId: teamId,
            points: selectedPoints,
            playType: selectedPlayType,
            quarter: game.quarter ?? 1
        )
        
        // Update game with new score
        var updatedGame = game
        updatedGame.scoringPlays.append(scoringPlay)
        
        // Update team score
        if teamId == game.homeTeamId {
            updatedGame.homeScore += selectedPoints
        } else {
            updatedGame.awayScore += selectedPoints
        }
        
        // Also update or create player stats for this game
        if let existingIndex = updatedGame.playerStats.firstIndex(where: { $0.playerId == playerId && $0.gameId == game.id }) {
            // Update existing stats
            updatedGame.playerStats[existingIndex].points += selectedPoints
            if selectedPoints == 3 {
                updatedGame.playerStats[existingIndex].threePointersMade += 1
                updatedGame.playerStats[existingIndex].threePointersAttempted += 1
            } else if selectedPoints == 2 {
                updatedGame.playerStats[existingIndex].fieldGoalsMade += 1
                updatedGame.playerStats[existingIndex].fieldGoalsAttempted += 1
            } else if selectedPoints == 1 {
                updatedGame.playerStats[existingIndex].freeThrowsMade += 1
                updatedGame.playerStats[existingIndex].freeThrowsAttempted += 1
            }
        } else {
            // Create new player stats for this game
            var newStats = PlayerGameStats(
                gameId: game.id,
                playerId: playerId,
                teamId: teamId,
                points: selectedPoints
            )
            if selectedPoints == 3 {
                newStats.threePointersMade = 1
                newStats.threePointersAttempted = 1
            } else if selectedPoints == 2 {
                newStats.fieldGoalsMade = 1
                newStats.fieldGoalsAttempted = 1
            } else if selectedPoints == 1 {
                newStats.freeThrowsMade = 1
                newStats.freeThrowsAttempted = 1
            }
            updatedGame.playerStats.append(newStats)
        }
        
        dataManager.updateGame(updatedGame)
        
        // Also update season stats immediately (not just when game ends)
        dataManager.updatePlayerSeasonStats(playerId: playerId, points: selectedPoints)
        
        HapticFeedback.impact(.medium)
        
        // Reset selection
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedPlayerForScore = nil
        }
    }
    
    private func startGame() {
        var updatedGame = game
        updatedGame.status = .live
        updatedGame.quarter = 1
        dataManager.updateGame(updatedGame)
        HapticFeedback.notification(.success)
    }
    
    private func endGame() {
        var updatedGame = game
        updatedGame.status = .finished
        dataManager.updateGame(updatedGame)
        HapticFeedback.notification(.success)
    }
}

// MARK: - Edit Team Panel Content
struct EditTeamPanelContent: View {
    let team: Team
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName: String
    @State private var shortName: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var coachName: String
    @State private var venue: String
    
    init(team: Team, isPresented: Binding<Bool>) {
        self.team = team
        self._isPresented = isPresented
        self._teamName = State(initialValue: team.name)
        self._shortName = State(initialValue: team.shortName)
        self._selectedColor = State(initialValue: team.colorHex)
        self._selectedIcon = State(initialValue: team.logoSystemImage)
        self._coachName = State(initialValue: team.coachName ?? "")
        self._venue = State(initialValue: team.homeVenue ?? "")
    }
    
    let teamColors: [String] = [
        "#E94560", "#7C3AED", "#3B82F6", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#06B6D4", "#84CC16"
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Preview
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: selectedColor))
                            .frame(width: 56, height: 56)
                        Image(systemName: selectedIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(teamName)
                        .font(.system(size: 16, weight: .bold))
                    PanelBadge(text: shortName, color: Color(hex: selectedColor))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
                // Team Info
                PanelSectionCard("Team Info", icon: "info.circle") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Name")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("Team Name", text: $teamName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                        Divider()
                        HStack {
                            Text("Short Name")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("ABC", text: $shortName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 60)
                                .onChange(of: shortName) { _, newValue in
                                    shortName = String(newValue.uppercased().prefix(3))
                                }
                        }
                        Divider()
                        HStack {
                            Text("Coach")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("Coach Name", text: $coachName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                    }
                }
                
                // Color
                PanelSectionCard("Team Color", icon: "paintpalette") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(teamColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                    HapticFeedback.impact(.light)
                                }
                        }
                    }
                }
                
                // Save Button
                PanelActionButton(title: "Save Changes", icon: "checkmark.circle.fill", color: Color(hex: selectedColor)) {
                    saveTeam()
                }
            }
            .padding(16)
        }
    }
    
    private func saveTeam() {
        var updatedTeam = team
        updatedTeam.name = teamName
        updatedTeam.shortName = shortName
        updatedTeam.colorHex = selectedColor
        updatedTeam.logoSystemImage = selectedIcon
        updatedTeam.coachName = coachName.isEmpty ? nil : coachName
        updatedTeam.homeVenue = venue.isEmpty ? nil : venue
        
        dataManager.updateTeam(updatedTeam)
        HapticFeedback.notification(.success)
        
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Player Selector Panel (Finder-like nested panel)
struct PlayerSelectorPanel: View {
    @Binding var selectedPlayerIds: Set<UUID>
    @Binding var isPresented: Bool
    let students: [Student]
    @State private var searchText = ""
    
    var filteredStudents: [Student] {
        if searchText.isEmpty {
            return students
        }
        return students.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed left side - tap to go back
            Color.black.opacity(0.2)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isPresented = false
                    }
                }
            
            // Panel content
            VStack(spacing: 0) {
                // Header
                PanelHeader(
                    title: "Select Players",
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                )
                
                Divider()
                
                // Search
                PanelSearchBar(text: $searchText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                
                // Player List
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredStudents) { student in
                            PanelListRow(
                                title: student.name,
                                subtitle: student.age.map { "\($0) yrs" },
                                isSelected: selectedPlayerIds.contains(student.id),
                                showChevron: false
                            ) {
                                PanelAvatar(initials: student.initials, color: Color.avatarColor(student.avatarColor), size: 36)
                            } action: {
                                togglePlayer(student.id)
                            }
                            .overlay(
                                Image(systemName: selectedPlayerIds.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(selectedPlayerIds.contains(student.id) ? AppTheme.accentColor : AppTheme.textTertiary)
                                    .padding(.trailing, 10),
                                alignment: .trailing
                            )
                        }
                    }
                    .padding(8)
                }
                
                // Footer with count
                HStack {
                    Text("\(selectedPlayerIds.count) selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accentColor)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(AppTheme.surfaceColor)
            }
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1),
                alignment: .leading
            )
        }
    }
    
    private func togglePlayer(_ id: UUID) {
        if selectedPlayerIds.contains(id) {
            selectedPlayerIds.remove(id)
        } else {
            selectedPlayerIds.insert(id)
        }
        HapticFeedback.impact(.light)
    }
}

// MARK: - Add Player Column View (Finder-style column)
struct AddPlayerColumnView: View {
    let team: Team
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedPlayerIds: Set<UUID> = []
    
    init(team: Team, isPresented: Binding<Bool>) {
        self.team = team
        self._isPresented = isPresented
        // Initialize with current team players
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
    
    var newlySelectedCount: Int {
        selectedPlayerIds.subtracting(Set(team.playerIds)).count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Add Players")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: saveAndDismiss) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(newlySelectedCount > 0 ? AppTheme.accentColor : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(newlySelectedCount == 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textTertiary)
                    .font(.system(size: 12))
                TextField("Search students...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(panelCardBackground)
            .cornerRadius(6)
            .padding(.horizontal, 14)
            
            // Selected count badge
            if newlySelectedCount > 0 {
                HStack {
                    Text("\(newlySelectedCount) new player\(newlySelectedCount == 1 ? "" : "s") selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(team.primaryColor)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            
            Divider()
                .padding(.top, 10)
            
            // Player List
            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredPlayers.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundColor(AppTheme.textTertiary)
                            Text(searchText.isEmpty ? "All students are on teams" : "No students found")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredPlayers) { student in
                            playerRow(student)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
    }
    
    private func playerRow(_ student: Student) -> some View {
        let isSelected = selectedPlayerIds.contains(student.id)
        return Button(action: { togglePlayer(student.id) }) {
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 36, height: 36)
                    Text(student.initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(student.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    if let age = student.age {
                        Text("\(age) yrs")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? team.primaryColor : AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AnyView(team.primaryColor.opacity(0.1)) : AnyView(panelCardBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var panelCardBackground: some View {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
    
    private func togglePlayer(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedPlayerIds.contains(id) {
                selectedPlayerIds.remove(id)
            } else {
                selectedPlayerIds.insert(id)
            }
        }
        HapticFeedback.impact(.light)
    }
    
    private func saveAndDismiss() {
        var updatedTeam = team
        updatedTeam.playerIds = Array(selectedPlayerIds)
        dataManager.updateTeam(updatedTeam)
        HapticFeedback.notification(.success)
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Flashy Player Selection Card
/// Animated player card with glow effects and spring animations
struct FlashyPlayerSelectionCard: View {
    let student: Student
    let isSelected: Bool
    let teamColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressing = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Avatar with glow effect when selected
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(teamColor.opacity(0.3))
                            .frame(width: 38, height: 38)
                            .blur(radius: 4)
                    }
                    
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? teamColor : Color.clear, lineWidth: 2)
                        )
                    
                    Text(student.initials)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Name and age
                VStack(alignment: .leading, spacing: 1) {
                    Text(student.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    if let age = student.age {
                        Text("\(age) yrs")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer(minLength: 4)
                
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(isSelected ? teamColor : Color.clear)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .stroke(isSelected ? teamColor : AppTheme.textTertiary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? teamColor.opacity(0.12) : cardBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? teamColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
            .shadow(color: isSelected ? teamColor.opacity(0.2) : Color.clear, radius: 6, x: 0, y: 2)
            .scaleEffect(isPressing ? 0.96 : (isHovered ? 1.02 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}
