import SwiftUI

// MARK: - Unified League View (Works on iOS and macOS)
struct UnifiedLeagueView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedDateFilter: GameDateFilter = .today
    @State private var selectedSection: LeagueSectionType = .games
    @State private var selectedLeaderStat: LeaderStatType = .points
    @State private var showingCreateTeam = false
    @State private var showingEditTeam = false
    @State private var showingScheduleGame = false
    @State private var selectedGame: Game?
    @State private var selectedTeam: Team?
    @State private var teamToEdit: Team?
    @Namespace private var animation
    
    enum GameDateFilter: String, CaseIterable {
        case past = "Past"
        case today = "Today"
        case upcoming = "Upcoming"
        
        var icon: String {
            switch self {
            case .past: return "clock.arrow.circlepath"
            case .today: return "calendar"
            case .upcoming: return "calendar.badge.clock"
            }
        }
    }
    
    enum LeagueSectionType: String, CaseIterable {
        case games = "Games"
        case standings = "Standings"
        case leaders = "Leaders"
        case teams = "Teams"
        
        var icon: String {
            switch self {
            case .games: return "sportscourt.fill"
            case .standings: return "list.number"
            case .leaders: return "trophy.fill"
            case .teams: return "person.3.fill"
            }
        }
    }
    
    enum LeaderStatType: String, CaseIterable {
        case points = "Points"
        case rebounds = "Rebounds"
        case assists = "Assists"
        case steals = "Steals"
        case blocks = "Blocks"
        case efficiency = "Efficiency"
        
        var icon: String {
            switch self {
            case .points: return "flame.fill"
            case .rebounds: return "arrow.up.arrow.down"
            case .assists: return "arrow.triangle.branch"
            case .steals: return "hand.raised.fill"
            case .blocks: return "hand.raised.slash.fill"
            case .efficiency: return "chart.line.uptrend.xyaxis"
            }
        }
        
        var color: Color {
            switch self {
            case .points: return .orange
            case .rebounds: return .blue
            case .assists: return .green
            case .steals: return .purple
            case .blocks: return .red
            case .efficiency: return .cyan
            }
        }
    }
    
    private var filteredGames: [Game] {
        let cal = Calendar.current
        let now = Date()
        switch selectedDateFilter {
        case .past:
            return dataManager.games.filter { 
                $0.status == .finished || (cal.compare($0.date, to: now, toGranularity: .day) == .orderedAscending && $0.status != .live)
            }.sorted { $0.date > $1.date }
        case .today:
            return dataManager.games.filter { cal.isDateInToday($0.date) || $0.status == .live }
        case .upcoming:
            return dataManager.games.filter { 
                $0.status == .scheduled && cal.compare($0.date, to: now, toGranularity: .day) != .orderedAscending
            }.sorted { $0.date < $1.date }
        }
    }
    
    private var liveGames: [Game] { dataManager.games.filter { $0.status == .live } }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [Color(hex: "#0F2027"), Color(hex: "#203A43"), Color(hex: "#2C5364").opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    headerSection
                    dateFilterPicker
                    
                    if !liveGames.isEmpty && selectedDateFilter == .today {
                        liveGamesBanner
                    }
                    
                    sectionPicker
                    
                    switch selectedSection {
                    case .games: gamesContent
                    case .standings: standingsContent
                    case .leaders: leadersContent
                    case .teams: teamsContent
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingCreateTeam) {
            EnhancedCreateTeamSheet(isPresented: $showingCreateTeam)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingScheduleGame) {
            EnhancedScheduleGameSheet(isPresented: $showingScheduleGame)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedGame) { game in
            EnhancedGameDetailSheet(game: game)
                .environmentObject(dataManager)
        }
        .sheet(item: $selectedTeam) { team in
            EnhancedTeamDetailSheet(team: team, onEdit: { teamToEdit = team })
                .environmentObject(dataManager)
        }
        .sheet(item: $teamToEdit) { team in
            EditTeamSheet(team: team, isPresented: Binding(
                get: { teamToEdit != nil },
                set: { if !$0 { teamToEdit = nil } }
            ))
            .environmentObject(dataManager)
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("League")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(dataManager.teams.count) teams · \(dataManager.games.count) games")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            HStack(spacing: 10) {
                glassButton(icon: "plus") { showingScheduleGame = true }
                glassButton(icon: "person.3.fill") { showingCreateTeam = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }
    
    private func glassButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.6)))
        }
    }
    
    // MARK: - Date Filter
    private var dateFilterPicker: some View {
        HStack(spacing: 4) {
            ForEach(GameDateFilter.allCases, id: \.self) { filter in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDateFilter = filter
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 10))
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: selectedDateFilter == filter ? .semibold : .regular, design: .rounded))
                    }
                    .foregroundColor(selectedDateFilter == filter ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if selectedDateFilter == filter {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .matchedGeometryEffect(id: "dateFilter", in: animation)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Live Games Banner
    private var liveGamesBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 14)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(liveGames) { game in
                        LiveGameCard(game: game)
                            .onTapGesture { selectedGame = game }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Section Picker
    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(LeagueSectionType.allCases, id: \.self) { section in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: section.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(selectedSection == section ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == section ? Capsule().fill(.ultraThinMaterial) : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Games Content
    private var gamesContent: some View {
        LazyVStack(spacing: 10) {
            if filteredGames.isEmpty {
                emptyState(
                    icon: "sportscourt",
                    title: selectedDateFilter == .past ? "No Past Games" : selectedDateFilter == .today ? "No Games Today" : "No Upcoming Games",
                    subtitle: "Tap + to schedule a game"
                )
            } else {
                ForEach(filteredGames) { game in
                    GameCard(game: game, showStats: selectedDateFilter == .past)
                        .onTapGesture { selectedGame = game }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Standings Content
    private var standingsContent: some View {
        VStack(spacing: 4) {
            // Header row
            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 30)
                Text("L").frame(width: 30)
                Text("PCT").frame(width: 50)
                Text("+/-").frame(width: 40)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            let sortedTeams = dataManager.teams.sorted { teamWins($0) > teamWins($1) }
            
            if sortedTeams.isEmpty {
                emptyState(icon: "list.number", title: "No Teams", subtitle: "Create a team to see standings")
            } else {
                ForEach(Array(sortedTeams.enumerated()), id: \.element.id) { index, team in
                    StandingsRow(team: team, rank: index + 1)
                        .onTapGesture { selectedTeam = team }
                }
            }
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Leaders Content with Stat Tabs
    private var leadersContent: some View {
        VStack(spacing: 12) {
            // Stat type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LeaderStatType.allCases, id: \.self) { stat in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLeaderStat = stat
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: stat.icon)
                                    .font(.system(size: 10))
                                Text(stat.rawValue)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(selectedLeaderStat == stat ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedLeaderStat == stat ? stat.color.opacity(0.3) : Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            
            // Leaders list for selected stat
            LeaderboardView(
                title: selectedLeaderStat.rawValue,
                icon: selectedLeaderStat.icon,
                color: selectedLeaderStat.color,
                leaders: computeLeaders(for: selectedLeaderStat)
            )
            .padding(.horizontal, 14)
        }
    }
    
    // MARK: - Teams Content
    private var teamsContent: some View {
        LazyVStack(spacing: 8) {
            if dataManager.teams.isEmpty {
                emptyState(icon: "person.3.fill", title: "No Teams", subtitle: "Create your first team")
            } else {
                ForEach(dataManager.teams) { team in
                    TeamCard(team: team)
                        .onTapGesture { selectedTeam = team }
                }
            }
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Helper Views
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.2))
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            Text(subtitle)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Calculations
    private func teamWins(_ team: Team) -> Int {
        dataManager.games.filter {
            $0.status == .finished &&
            (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) ||
             ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore))
        }.count
    }
    
    private func computeLeaders(for stat: LeaderStatType) -> [(name: String, team: String, value: Double)] {
        var playerData: [UUID: (name: String, team: String, total: Int, games: Int)] = [:]
        
        for game in dataManager.games where game.status == .finished {
            for stats in game.playerStats {
                let player = dataManager.players.first { $0.id == stats.playerId }
                let studentName = player.flatMap { p in dataManager.students.first { $0.id == p.studentId }?.name } ?? "Unknown"
                let teamShortName = dataManager.teams.first { $0.id == stats.teamId }?.shortName ?? ""
                
                let statValue: Int
                switch stat {
                case .points: statValue = stats.points
                case .rebounds: statValue = stats.rebounds
                case .assists: statValue = stats.assists
                case .steals: statValue = stats.steals
                case .blocks: statValue = stats.blocks
                case .efficiency: statValue = Int(stats.efficiency)
                }
                
                if let existing = playerData[stats.playerId] {
                    playerData[stats.playerId] = (existing.name, existing.team, existing.total + statValue, existing.games + 1)
                } else {
                    playerData[stats.playerId] = (studentName, teamShortName, statValue, 1)
                }
            }
        }
        
        return playerData.values
            .filter { $0.games > 0 }
            .map { (name: $0.name, team: $0.team, value: Double($0.total) / Double($0.games)) }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0 }
    }
}

// MARK: - Game Card
struct GameCard: View {
    let game: Game
    var showStats: Bool = false
    @EnvironmentObject var dataManager: DataManager
    
    private var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                // Away Team
                HStack(spacing: 10) {
                    TeamLogoView(team: awayTeam, size: 40)
                    Text(awayTeam?.shortName ?? "TBD")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Score / Time
                VStack(spacing: 2) {
                    if game.status == .live {
                        HStack(spacing: 6) {
                            Text("\(game.awayScore)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("-")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                            Text("\(game.homeScore)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text(game.quarterDisplay ?? "LIVE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                        }
                    } else if game.status == .finished {
                        HStack(spacing: 6) {
                            Text("\(game.awayScore)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(game.awayScore > game.homeScore ? .white : .white.opacity(0.4))
                            Text("-")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.3))
                            Text("\(game.homeScore)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(game.homeScore > game.awayScore ? .white : .white.opacity(0.4))
                        }
                        Text("Final")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    } else {
                        Text(game.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 100)
                
                // Home Team
                HStack(spacing: 10) {
                    Text(homeTeam?.shortName ?? "TBD")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    TeamLogoView(team: homeTeam, size: 40)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            // Show venue/location info for upcoming games
            if game.status == .scheduled {
                if let venue = game.venue, !venue.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                        Text(venue)
                            .font(.system(size: 11, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }
                
                // Show referee if assigned
                if let refereeId = game.refereeId,
                   let referee = dataManager.staffCoaches.first(where: { $0.id == refereeId }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 10))
                        Text("Ref: \(referee.name)")
                            .font(.system(size: 11, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }
            }
            
            // Show top scorers for finished games
            if showStats && game.status == .finished && !game.playerStats.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                
                let topScorers = game.playerStats.sorted { $0.points > $1.points }.prefix(2)
                HStack {
                    ForEach(Array(topScorers), id: \.id) { stat in
                        let player = dataManager.players.first { $0.id == stat.playerId }
                        let studentName = player.flatMap { p in dataManager.students.first { $0.id == p.studentId }?.name } ?? "?"
                        
                        HStack(spacing: 4) {
                            Text(studentName.components(separatedBy: " ").first ?? studentName)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Text("\(stat.points) pts")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        
                        if stat.id != topScorers.last?.id {
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(game.status == .live ? Color.red.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Live Game Card
struct LiveGameCard: View {
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    
    private var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    TeamLogoView(team: awayTeam, size: 24)
                    Text("\(game.awayScore)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 2) {
                    Text(game.quarterDisplay ?? "Q1")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Text(game.timeRemaining ?? "0:00")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 3) {
                    TeamLogoView(team: homeTeam, size: 24)
                    Text("\(game.homeScore)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            (awayTeam?.primaryColor ?? .gray).opacity(0.3),
                            (homeTeam?.primaryColor ?? .gray).opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.4), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Team Logo View
struct TeamLogoView: View {
    let team: Team?
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .fill(team?.primaryColor ?? .gray)
            
            if let mascotType = team?.mascotType {
                TeamMascotLogo(mascot: mascotType, size: size * 0.8, showGlow: false)
            } else {
                Text(String((team?.shortName ?? "?").prefix(1)))
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Standings Row
struct StandingsRow: View {
    let team: Team
    let rank: Int
    @EnvironmentObject var dataManager: DataManager
    
    private var wins: Int {
        dataManager.games.filter {
            $0.status == .finished &&
            (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) ||
             ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore))
        }.count
    }
    
    private var losses: Int {
        dataManager.games.filter {
            $0.status == .finished &&
            (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) ||
             ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore))
        }.count
    }
    
    private var winPct: Double {
        let total = wins + losses
        return total > 0 ? Double(wins) / Double(total) : 0
    }
    
    private var pointDiff: Int {
        var diff = 0
        for game in dataManager.games where game.status == .finished {
            if game.homeTeamId == team.id {
                diff += game.homeScore - game.awayScore
            } else if game.awayTeamId == team.id {
                diff += game.awayScore - game.homeScore
            }
        }
        return diff
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(rank <= 3 ? .white : .white.opacity(0.4))
                .frame(width: 24, alignment: .leading)
            
            HStack(spacing: 8) {
                TeamLogoView(team: team, size: 28)
                Text(team.shortName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("\(wins)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 30)
            
            Text("\(losses)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 30)
            
            Text(String(format: "%.3f", winPct))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50)
            
            Text(pointDiff >= 0 ? "+\(pointDiff)" : "\(pointDiff)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(pointDiff >= 0 ? .green : .red)
                .frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(rank <= 3 ? 0.5 : 0.3))
        )
    }
}

// MARK: - Leaderboard View
struct LeaderboardView: View {
    let title: String
    let icon: String
    let color: Color
    let leaders: [(name: String, team: String, value: Double)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("PPG")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            if leaders.isEmpty {
                Text("No data available")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(leaders.enumerated()), id: \.offset) { index, leader in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(index == 0 ? color : .white.opacity(0.4))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leader.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(leader.team)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", leader.value))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(index == 0 ? color : .white)
                    }
                    .padding(.vertical, 6)
                    
                    if index < leaders.count - 1 {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}

// MARK: - Team Card
struct TeamCard: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    
    private var wins: Int {
        dataManager.games.filter {
            $0.status == .finished &&
            (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) ||
             ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore))
        }.count
    }
    
    private var losses: Int {
        dataManager.games.filter {
            $0.status == .finished &&
            (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) ||
             ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore))
        }.count
    }
    
    var body: some View {
        HStack(spacing: 12) {
            TeamLogoView(team: team, size: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(team.playerIds.count)", systemImage: "person.fill")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if let coachId = team.coachId,
                       let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                        Label(coach.name.components(separatedBy: " ").first ?? coach.name, systemImage: "person.badge.shield.checkmark")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(wins)-\(losses)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Record")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}

#Preview {
    UnifiedLeagueView()
        .environmentObject(DataManager.shared)
}
