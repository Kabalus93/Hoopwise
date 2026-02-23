import SwiftUI
import Combine

// MARK: - Flighty-Styled League View
/// A stunning league page with Flighty's wow-effect aesthetic
/// Features: Live game animations, scoreboard displays, stadium atmosphere
struct FlightyLeagueView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: LeagueTab = .games
    @State private var showingCreateTeam = false
    @State private var showingScheduleGame = false
    @State private var selectedGame: Game?
    @State private var selectedTeam: Team?
    @State private var currentTime = Date()
    @State private var pulseAnimation = false
    @State private var showingTeamsList = false
    @State private var showingGamesList = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    enum LeagueTab: String, CaseIterable {
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
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero header
                    heroHeader
                    
                    // Tab selector
                    flightyTabSelector
                    
                    // Content
                    switch selectedTab {
                    case .games:
                        gamesContent
                    case .teams:
                        teamsContent
                    case .standings:
                        standingsContent
                    case .stats:
                        statsContent
                    }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("League")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailingCompat) {
                    Menu {
                        Button(action: { showingCreateTeam = true }) {
                            Label("Create Team", systemImage: "plus.circle")
                        }
                        Button(action: { showingScheduleGame = true }) {
                            Label("Schedule Game", systemImage: "calendar.badge.plus")
                        }
                        Divider()
                        Button(action: { showingTeamsList = true }) {
                            Label("Manage Teams", systemImage: "person.3")
                        }
                        Button(action: { showingGamesList = true }) {
                            Label("Manage Games", systemImage: "sportscourt")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                    }
                }
            }
            .onReceive(timer) { _ in
                currentTime = Date()
                withAnimation(.easeInOut(duration: 0.5)) {
                    pulseAnimation.toggle()
                }
            }
            .sheet(isPresented: $showingCreateTeam) {
                CreateTeamView()
            }
            .sheet(isPresented: $showingScheduleGame) {
                ScheduleGameView()
            }
            .sheet(item: $selectedGame) { game in
                FlightyGameDetailView(game: game)
            }
            .sheet(item: $selectedTeam) { team in
                FlightyTeamDetailView(team: team)
            }
            .sheet(isPresented: $showingTeamsList) {
                NavigationStack {
                    TeamsManagementListView()
                }
            }
            .sheet(isPresented: $showingGamesList) {
                NavigationStack {
                    GamesManagementListView()
                }
            }
        }
    }
    
    // MARK: - Hero Header (Dark Theme - Compact)
    private var heroHeader: some View {
        VStack(spacing: 10) {
            // Live games banner (only if live)
            if !liveGames.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red.opacity(0.6), radius: pulseAnimation ? 4 : 2)
                    
                    Text("\(liveGames.count) LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.15))
                .cornerRadius(16)
            }
            
            // Quick stats row - more compact
            HStack(spacing: 0) {
                heroStat(value: "\(dataManager.teams.count)", label: "Teams", color: AppTheme.accentColor)
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 28)
                
                heroStat(value: "\(dataManager.games.count)", label: "Games", color: AppTheme.warningColor)
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 28)
                
                heroStat(value: "\(finishedGames.count)", label: "Played", color: AppTheme.successColor)
            }
            .padding(.vertical, 12)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func heroStat(value: String, label: String, color: Color) -> some View {
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
    
    private var finishedGames: [Game] {
        dataManager.games.filter { $0.status == .finished }
    }
    
    // MARK: - Tab Selector (Dark Theme - Compact)
    private var flightyTabSelector: some View {
        HStack(spacing: 6) {
            ForEach(LeagueTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                    HapticFeedback.impact(.light)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(selectedTab == tab ? Color(hex: "#0D0D0D") : AppTheme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? AppTheme.accentColor : AppTheme.surfaceColor)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Games Content
    private var gamesContent: some View {
        VStack(spacing: 16) {
            // Live Games - Featured
            if !liveGames.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: .red, radius: pulseAnimation ? 4 : 2)
                        Text("LIVE NOW")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(liveGames) { game in
                                FlightyLiveGameCard(game: game, pulseAnimation: pulseAnimation)
                                    .onTapGesture { selectedGame = game }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            
            // Today's Games
            if !todayGames.isEmpty {
                gameSection(title: "TODAY", games: todayGames, showTime: true)
            }
            
            // Upcoming
            if !upcomingGames.isEmpty {
                gameSection(title: "UPCOMING", games: Array(upcomingGames.prefix(5)), showTime: true)
            }
            
            // Recent Results
            if !recentGames.isEmpty {
                gameSection(title: "RECENT RESULTS", games: recentGames, showTime: false)
            }
            
            // Empty state
            if dataManager.games.isEmpty {
                emptyGamesState
            }
        }
        .padding(.vertical, 24)
    }
    
    private func gameSection(title: String, games: [Game], showTime: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 6) {
                ForEach(games) { game in
                    FlightyGameRow(game: game, showTime: showTime)
                        .onTapGesture { selectedGame = game }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Teams Content
    private var teamsContent: some View {
        VStack(spacing: 16) {
            if dataManager.teams.isEmpty {
                emptyTeamsState
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(dataManager.teams) { team in
                        FlightyTeamCard(team: team)
                            .onTapGesture { selectedTeam = team }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
    
    // MARK: - Standings Content
    private var standingsContent: some View {
        VStack(spacing: 20) {
            if dataManager.teams.isEmpty {
                emptyTeamsState
            } else {
                FlightyStandingsTable(teams: dataManager.teams, games: dataManager.games)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            }
        }
    }
    
    // MARK: - Stats Content
    private var statsContent: some View {
        VStack(spacing: 16) {
            // Season Records Section
            FlightySeasonRecords()
                .padding(.horizontal, 16)
            
            // Stats Leaders
            FlightyStatsLeaders()
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Empty States (Light Theme)
    private var emptyGamesState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "sportscourt")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 4) {
                Text("No Games Scheduled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("Schedule your first game to get started")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Button(action: { showingScheduleGame = true }) {
                Text("Schedule Game")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 20)
    }
    
    private var emptyTeamsState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.3")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 4) {
                Text("No Teams Yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("Create teams from your athletes")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Button(action: { showingCreateTeam = true }) {
                Text("Create Team")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Computed Properties
    private var liveGames: [Game] {
        dataManager.games.filter { $0.status == .live }
    }
    
    private var todayGames: [Game] {
        let calendar = Calendar.current
        return dataManager.games.filter {
            calendar.isDateInToday($0.date) && $0.status != .live
        }
    }
    
    private var upcomingGames: [Game] {
        dataManager.games.filter {
            $0.status == .scheduled && $0.date > Date() && !Calendar.current.isDateInToday($0.date)
        }.sorted { $0.date < $1.date }
    }
    
    private var recentGames: [Game] {
        dataManager.games.filter {
            $0.status == .finished
        }.sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }
}

// MARK: - Flighty Live Game Card (Dark Theme)
struct FlightyLiveGameCard: View {
    let game: Game
    let pulseAnimation: Bool
    @EnvironmentObject var dataManager: DataManager
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Live header
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .shadow(color: .red.opacity(0.5), radius: pulseAnimation ? 3 : 1)
                    Text(game.quarterDisplay ?? "LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                if let time = game.timeRemaining {
                    Text(time)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.15))
            
            // Scoreboard
            HStack(spacing: 0) {
                // Away team
                VStack(spacing: 4) {
                    FlightyTeamLogo(team: awayTeam, size: 28)
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                // Score
                HStack(spacing: 6) {
                    Text("\(game.awayScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(game.awayScore >= game.homeScore ? AppTheme.textPrimary : AppTheme.textTertiary)
                    
                    Text("-")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.4))
                    
                    Text("\(game.homeScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(game.homeScore >= game.awayScore ? AppTheme.textPrimary : AppTheme.textTertiary)
                }
                
                // Home team
                VStack(spacing: 4) {
                    FlightyTeamLogo(team: homeTeam, size: 28)
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .frame(width: 220)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Flighty Game Row (Dark Theme)
struct FlightyGameRow: View {
    let game: Game
    let showTime: Bool
    @EnvironmentObject var dataManager: DataManager
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Away team
            HStack(spacing: 6) {
                FlightyTeamLogo(team: awayTeam, size: 24)
                Text(awayTeam?.shortName ?? "AWY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Score or Time
            VStack(spacing: 1) {
                if game.status == .finished {
                    HStack(spacing: 3) {
                        Text("\(game.awayScore)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(game.awayScore > game.homeScore ? AppTheme.accentColor : AppTheme.textPrimary)
                        Text("-")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary.opacity(0.4))
                        Text("\(game.homeScore)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(game.homeScore > game.awayScore ? AppTheme.accentColor : AppTheme.textPrimary)
                    }
                    Text("Final")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                } else if showTime {
                    Text(game.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(game.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                } else {
                    Text("@")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.4))
                }
            }
            .frame(width: 60)
            
            // Home team
            HStack(spacing: 6) {
                Text(homeTeam?.shortName ?? "HME")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                FlightyTeamLogo(team: homeTeam, size: 24)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Flighty Team Logo (Compact)
struct FlightyTeamLogo: View {
    let team: Team?
    var size: CGFloat = 28
    
    var body: some View {
        ZStack {
            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            (team?.primaryColor ?? .orange),
                            (team?.primaryColor ?? .orange).opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            // Icon
            Image(systemName: team?.logoSystemImage ?? "basketball.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Flighty Team Card (Dark Theme)
struct FlightyTeamCard: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    
    var standing: TeamStanding? {
        dataManager.teamStandings.first { $0.teamId == team.id }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Logo
            FlightyTeamLogo(team: team, size: 36)
            
            VStack(spacing: 3) {
                Text(team.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(team.shortName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(team.primaryColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(team.primaryColor.opacity(0.15))
                    .cornerRadius(4)
                
                Text("\(team.playerCount) players")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            // Record
            if let standing = standing {
                HStack(spacing: 10) {
                    VStack(spacing: 1) {
                        Text(standing.record)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("W-L")
                            .font(.system(size: 8))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 16)
                    
                    VStack(spacing: 1) {
                        Text(standing.streakDisplay)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(standing.streak > 0 ? .green : (standing.streak < 0 ? .red : AppTheme.textTertiary))
                        Text("Streak")
                            .font(.system(size: 8))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Flighty Standings Table
struct FlightyStandingsTable: View {
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
        
        var pointDifferential: Int {
            pointsFor - pointsAgainst
        }
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
            if $0.winPercentage != $1.winPercentage {
                return $0.winPercentage > $1.winPercentage
            }
            return $0.pointDifferential > $1.pointDifferential
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 24, alignment: .center)
                Text("TEAM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                Text("W")
                    .frame(width: 28, alignment: .center)
                Text("L")
                    .frame(width: 28, alignment: .center)
                Text("PCT")
                    .frame(width: 42, alignment: .center)
                Text("+/-")
                    .frame(width: 36, alignment: .center)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.05))
            
            // Rows
            ForEach(Array(computedStandings.enumerated()), id: \.element.id) { index, standing in
                HStack(spacing: 0) {
                    // Rank
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(index == 0 ? .orange : (index == 1 ? .gray : (index == 2 ? .brown : .gray.opacity(0.5))))
                        .frame(width: 24)
                    
                    // Team
                    HStack(spacing: 8) {
                        FlightyTeamLogo(team: standing.team, size: 24)
                        Text(standing.team.shortName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(standing.wins)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .frame(width: 28, alignment: .center)
                    
                    Text("\(standing.losses)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                        .frame(width: 28, alignment: .center)
                    
                    Text(String(format: ".%03d", Int(standing.winPercentage * 1000)))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(width: 42, alignment: .center)
                    
                    Text(standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(standing.pointDifferential >= 0 ? .green : .red)
                        .frame(width: 36, alignment: .center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.03))
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Flighty Season Records (Dark Theme)
struct FlightySeasonRecords: View {
    @EnvironmentObject var dataManager: DataManager
    
    var highestScoringGame: Game? {
        dataManager.games.filter { $0.status == .finished }
            .max(by: { ($0.homeScore + $0.awayScore) < ($1.homeScore + $1.awayScore) })
    }
    
    var biggestBlowout: Game? {
        dataManager.games.filter { $0.status == .finished }
            .max(by: { abs($0.homeScore - $0.awayScore) < abs($1.homeScore - $1.awayScore) })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEASON RECORDS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            if dataManager.games.filter({ $0.status == .finished }).isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "trophy")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("No records yet")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    // Highest Scoring Game
                    if let game = highestScoringGame {
                        recordCard(
                            title: "High Score",
                            value: "\(game.homeScore + game.awayScore)",
                            subtitle: "Total Points",
                            icon: "flame.fill",
                            color: .orange
                        )
                    }
                    
                    // Biggest Blowout
                    if let game = biggestBlowout {
                        recordCard(
                            title: "Biggest Win",
                            value: "\(abs(game.homeScore - game.awayScore))",
                            subtitle: "Point Margin",
                            icon: "bolt.fill",
                            color: .purple
                        )
                    }
                    
                    // Games Played
                    recordCard(
                        title: "Games",
                        value: "\(dataManager.games.filter { $0.status == .finished }.count)",
                        subtitle: "Completed",
                        icon: "sportscourt.fill",
                        color: .green
                    )
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func recordCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Flighty Stats Leaders (Dark Theme)
struct FlightyStatsLeaders: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(spacing: 10) {
            if dataManager.seasonStats.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "chart.bar")
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                    }
                    
                    Text("No Stats Yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text("Play some games to see player stats")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
            } else {
                FlightyStatLeaderCard(title: "POINTS", stat: "PPG", leaders: pointsLeaders, color: .orange)
                FlightyStatLeaderCard(title: "REBOUNDS", stat: "RPG", leaders: reboundsLeaders, color: .blue)
                FlightyStatLeaderCard(title: "ASSISTS", stat: "APG", leaders: assistsLeaders, color: .green)
            }
        }
    }
    
    private func student(for playerId: UUID) -> Student? {
        guard let player = dataManager.players.first(where: { $0.id == playerId }) else { return nil }
        return dataManager.students.first(where: { $0.id == player.studentId })
    }
    
    var pointsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.ppg > 0 }
            .sorted { $0.ppg > $1.ppg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.ppg)
            }
    }
    
    var reboundsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.rpg > 0 }
            .sorted { $0.rpg > $1.rpg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.rpg)
            }
    }
    
    var assistsLeaders: [(Student, Double)] {
        dataManager.seasonStats
            .filter { $0.apg > 0 }
            .sorted { $0.apg > $1.apg }
            .prefix(5)
            .compactMap { stat in
                guard let student = student(for: stat.playerId) else { return nil }
                return (student, stat.apg)
            }
    }
}

// MARK: - Flighty Stat Leader Card (Light Theme)
struct FlightyStatLeaderCard: View {
    let title: String
    let stat: String
    let leaders: [(Student, Double)]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                Spacer()
                Text(stat)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            if leaders.isEmpty {
                Text("No data yet")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(leaders.enumerated()), id: \.element.0.id) { index, item in
                        HStack(spacing: 8) {
                            // Rank
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(index == 0 ? color : .gray)
                                .frame(width: 16)
                            
                            StudentAvatarView(student: item.0, size: 28)
                            
                            Text(item.0.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(String(format: "%.1f", item.1))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(index == 0 ? color : .black)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(index == 0 ? color.opacity(0.08) : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Animated Team Gradient Background
struct AnimatedTeamGradientBackground: View {
    let homeColor: Color
    let awayColor: Color
    
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = sin(time * 0.5) * 0.5 + 0.5 // Oscillates 0-1
                let reversePhase = 1 - phase
                
                // Create gradient that oscillates
                let gradient = Gradient(stops: [
                    .init(color: awayColor.opacity(0.7 + phase * 0.3), location: 0),
                    .init(color: awayColor.opacity(0.4 + reversePhase * 0.2), location: 0.3 + phase * 0.1),
                    .init(color: homeColor.opacity(0.4 + phase * 0.2), location: 0.7 - phase * 0.1),
                    .init(color: homeColor.opacity(0.7 + reversePhase * 0.3), location: 1)
                ])
                
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: size.height * (0.3 + phase * 0.2)),
                        endPoint: CGPoint(x: size.width, y: size.height * (0.7 - phase * 0.2))
                    )
                )
                
                // Add subtle radial glow for away team (left)
                let awayGlow = Gradient(colors: [
                    awayColor.opacity(0.4 * phase),
                    awayColor.opacity(0)
                ])
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: -size.width * 0.3,
                        y: size.height * 0.2,
                        width: size.width * 0.8,
                        height: size.height * 0.8
                    )),
                    with: .radialGradient(
                        awayGlow,
                        center: CGPoint(x: size.width * 0.1, y: size.height * 0.5),
                        startRadius: 0,
                        endRadius: size.width * 0.5
                    )
                )
                
                // Add subtle radial glow for home team (right)
                let homeGlow = Gradient(colors: [
                    homeColor.opacity(0.4 * reversePhase),
                    homeColor.opacity(0)
                ])
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: size.width * 0.5,
                        y: size.height * 0.2,
                        width: size.width * 0.8,
                        height: size.height * 0.8
                    )),
                    with: .radialGradient(
                        homeGlow,
                        center: CGPoint(x: size.width * 0.9, y: size.height * 0.5),
                        startRadius: 0,
                        endRadius: size.width * 0.5
                    )
                )
            }
        }
    }
}

// MARK: - Flighty Game Detail View (Enhanced)
struct FlightyGameDetailView: View {
    let gameId: UUID
    private let initialGame: Game
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedSection: GameDetailSection = .overview
    @State private var showingLiveScoring = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEndGameConfirmation = false
    
    init(game: Game) {
        self.gameId = game.id
        self.initialGame = game
    }
    
    /// Always get fresh game data from dataManager
    var game: Game {
        dataManager.games.first { $0.id == gameId } ?? initialGame
    }
    
    enum GameDetailSection: String, CaseIterable {
        case overview = "Overview"
        case boxScore = "Box Score"
        case timeline = "Timeline"
    }
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var homeColor: Color {
        homeTeam?.primaryColor ?? Color.green
    }
    
    var awayColor: Color {
        awayTeam?.primaryColor ?? Color.orange
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedTeamGradientBackground(homeColor: homeColor, awayColor: awayColor)
                .ignoresSafeArea()
            
            // Frosted glass overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                // Header with close and options
                HStack {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                    }
                    
                    Spacer()
                    
                    // Game Options Menu
                    Menu {
                        if game.status == .live || game.status == .scheduled {
                            Button(action: { showingLiveScoring = true }) {
                                Label("Live Scoring", systemImage: "plus.circle")
                            }
                        }
                        
                        if game.status == .live {
                            Button(action: { showingEndGameConfirmation = true }) {
                                Label("End Game", systemImage: "flag.checkered")
                            }
                        }
                        
                        if game.status == .scheduled {
                            Button(action: { startGame() }) {
                                Label("Start Game", systemImage: "play.fill")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Game", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Hero Score Card
                        heroScoreCard
                        
                        // Live Game Actions (if live)
                        if game.status == .live {
                            liveGameActionsCard
                        }
                        
                        // Section Picker
                        sectionPicker
                        
                        // Section Content
                        switch selectedSection {
                        case .overview:
                            overviewSection
                        case .boxScore:
                            boxScoreSection
                        case .timeline:
                            timelineSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showingLiveScoring) {
            LiveScoringView(game: Binding(
                get: { dataManager.games.first { $0.id == game.id } ?? game },
                set: { dataManager.updateGame($0) }
            ))
        }
        .alert("End Game?", isPresented: $showingEndGameConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Game") {
                endGame()
            }
        } message: {
            Text("This will mark the game as finished with the current score.")
        }
        .alert("Delete Game?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                dataManager.deleteGame(game)
                dismiss()
            }
        } message: {
            Text("This will permanently delete this game. This action cannot be undone.")
        }
    }
    
    // MARK: - Live Game Actions Card
    private var liveGameActionsCard: some View {
        HStack(spacing: 10) {
            // Live Scoring Button
            Button(action: { showingLiveScoring = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Score")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange)
                .cornerRadius(10)
            }
            
            // End Game Button
            Button(action: { showingEndGameConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14))
                    Text("End Game")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func startGame() {
        var updatedGame = game
        updatedGame.status = .live
        dataManager.updateGame(updatedGame)
        HapticFeedback.notification(.success)
    }
    
    private func endGame() {
        var updatedGame = game
        updatedGame.status = .finished
        dataManager.updateGame(updatedGame)
        HapticFeedback.notification(.success)
    }
    
    // MARK: - Hero Score Card
    private var heroScoreCard: some View {
        VStack(spacing: 0) {
            // Status pill
            statusPill
                .padding(.top, 20)
            
            // Teams and Score
            HStack(spacing: 0) {
                // Away Team
                VStack(spacing: 10) {
                    FlightyTeamLogo(team: awayTeam, size: 64)
                    Text(awayTeam?.name ?? "Away")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(awayColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(awayColor.opacity(0.15))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity)
                
                // Score
                VStack(spacing: 6) {
                    if game.status == .scheduled {
                        Text("VS")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.gray.opacity(0.4))
                    } else {
                        HStack(spacing: 8) {
                            Text("\(game.awayScore)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(game.awayScore > game.homeScore ? .black : .gray)
                            
                            Text("-")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.gray.opacity(0.3))
                            
                            Text("\(game.homeScore)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(game.homeScore > game.awayScore ? .black : .gray)
                        }
                    }
                    
                    // Quarter scores if available
                    if !game.quarterScores.isEmpty {
                        quarterScoresRow
                    }
                }
                .frame(minWidth: 140)
                
                // Home Team
                VStack(spacing: 10) {
                    FlightyTeamLogo(team: homeTeam, size: 64)
                    Text(homeTeam?.name ?? "Home")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(homeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(homeColor.opacity(0.15))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 24)
            
            // Game Info Footer
            gameInfoFooter
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
    
    private var statusPill: some View {
        Group {
            if game.status == .live {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                        )
                    Text(game.quarterDisplay ?? "LIVE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.12))
                .cornerRadius(20)
            } else if game.status == .finished {
                Text("Final")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
            } else {
                VStack(spacing: 2) {
                    Text(game.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Text(game.date.formatted(.dateTime.month().day().hour().minute()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var quarterScoresRow: some View {
        HStack(spacing: 4) {
            ForEach(game.quarterScores.sorted(by: { $0.quarter < $1.quarter }), id: \.quarter) { qs in
                VStack(spacing: 2) {
                    Text(qs.quarter <= 4 ? "Q\(qs.quarter)" : "OT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                    Text("\(qs.awayScore)-\(qs.homeScore)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.8))
                }
                .frame(width: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
    
    private var gameInfoFooter: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 20)
            
            HStack(spacing: 20) {
                if let venue = game.venue {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text(venue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text(game.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Section Picker
    private var sectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(GameDetailSection.allCases, id: \.self) { section in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                }) {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: selectedSection == section ? .semibold : .medium))
                        .foregroundColor(selectedSection == section ? .white : .gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedSection == section ? Color.orange : Color.white.opacity(0.8))
                        )
                }
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Overview Section
    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Team Comparison Card
            teamComparisonCard
            
            // Recent Form
            if game.status == .finished {
                resultHighlightsCard
            }
            
            // Top Performers
            if !game.playerStats.isEmpty {
                topPerformersCard
            }
        }
    }
    
    private var teamComparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TEAM COMPARISON")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                comparisonRow(label: "Record", awayValue: "0-0", homeValue: "0-0")
                comparisonRow(label: "PPG", awayValue: String(format: "%.1f", Double(game.awayScore)), homeValue: String(format: "%.1f", Double(game.homeScore)))
                comparisonRow(label: "Players", awayValue: "\(awayTeam?.playerCount ?? 0)", homeValue: "\(homeTeam?.playerCount ?? 0)")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    private func comparisonRow(label: String, awayValue: String, homeValue: String) -> some View {
        HStack {
            Text(awayValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(awayColor)
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(homeValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(homeColor)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    private var resultHighlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RESULT HIGHLIGHTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            HStack(spacing: 16) {
                // Winner badge
                VStack(spacing: 8) {
                    let winner = game.homeScore > game.awayScore ? homeTeam : awayTeam
                    let winnerColor = game.homeScore > game.awayScore ? homeColor : awayColor
                    
                    FlightyTeamLogo(team: winner, size: 48)
                    
                    Text("Winner")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text(winner?.shortName ?? "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(winnerColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.08))
                .cornerRadius(12)
                
                // Point Difference
                VStack(spacing: 8) {
                    Text("\(abs(game.homeScore - game.awayScore))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text("Point Diff")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(12)
                
                // Total Points
                VStack(spacing: 8) {
                    Text("\(game.homeScore + game.awayScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text("Total Pts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(12)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    private var topPerformersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TOP PERFORMERS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            let topScorer = game.playerStats.max(by: { $0.points < $1.points })
            
            if let scorer = topScorer,
               let student = dataManager.students.first(where: { $0.id == scorer.playerId }) {
                HStack(spacing: 14) {
                    StudentAvatarView(student: student, size: 44)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                        Text("Top Scorer")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(scorer.points)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("PTS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(12)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    // MARK: - Box Score Section
    private var boxScoreSection: some View {
        VStack(spacing: 16) {
            // Away Team
            teamBoxScoreCard(team: awayTeam, stats: game.playerStats.filter { $0.teamId == game.awayTeamId }, color: awayColor)
            
            // Home Team
            teamBoxScoreCard(team: homeTeam, stats: game.playerStats.filter { $0.teamId == game.homeTeamId }, color: homeColor)
            
            if game.playerStats.isEmpty {
                emptyStateCard(icon: "chart.bar.doc.horizontal", title: "No Stats Yet", subtitle: "Player statistics will appear here after the game")
            }
        }
    }
    
    private func teamBoxScoreCard(team: Team?, stats: [PlayerGameStats], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FlightyTeamLogo(team: team, size: 32)
                Text(team?.name ?? "Team")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                Text("\(stats.reduce(0) { $0 + $1.points }) PTS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }
            
            if stats.isEmpty {
                Text("No player stats recorded")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.vertical, 12)
            } else {
                // Header
                HStack(spacing: 0) {
                    Text("Player")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PTS").frame(width: 36)
                    Text("REB").frame(width: 36)
                    Text("AST").frame(width: 36)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 8)
                
                ForEach(stats.sorted(by: { $0.points > $1.points }), id: \.playerId) { stat in
                    if let student = dataManager.students.first(where: { $0.id == stat.playerId }) {
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                StudentAvatarView(student: student, size: 28)
                                Text(student.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.black)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(stat.points)").frame(width: 36)
                            Text("\(stat.rebounds)").frame(width: 36)
                            Text("\(stat.assists)").frame(width: 36)
                        }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    // MARK: - Timeline Section
    private var timelineSection: some View {
        VStack(spacing: 16) {
            if game.scoringPlays.isEmpty {
                emptyStateCard(icon: "list.bullet.clipboard", title: "No Plays Recorded", subtitle: "Scoring plays will appear here during the game")
            } else {
                ForEach(Array(Set(game.scoringPlays.map { $0.quarter })).sorted().reversed(), id: \.self) { quarter in
                    quarterTimelineCard(quarter: quarter)
                }
            }
        }
    }
    
    private func quarterTimelineCard(quarter: Int) -> some View {
        let plays = game.scoringPlays(forQuarter: quarter).reversed()
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(quarter <= 4 ? "QUARTER \(quarter)" : "OVERTIME \(quarter - 4)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            ForEach(Array(plays), id: \.id) { play in
                HStack(spacing: 12) {
                    // Team indicator
                    Circle()
                        .fill(play.teamId == game.homeTeamId ? homeColor : awayColor)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let student = dataManager.students.first(where: { $0.id == play.playerId }) {
                            Text(student.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black)
                        }
                        Text(play.playType.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Text("+\(play.points)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(play.teamId == game.homeTeamId ? homeColor : awayColor)
                }
                .padding(12)
                .background(Color.gray.opacity(0.04))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    private func emptyStateCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.4))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.gray)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - Flighty Team Detail View (Dark Theme)
struct FlightyTeamDetailView: View {
    let team: Team
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddPlayer = false
    @State private var selectedPlayerIds: Set<UUID>
    @State private var showingDeleteConfirmation = false
    
    init(team: Team) {
        self.team = team
        _selectedPlayerIds = State(initialValue: Set(team.playerIds))
    }
    
    var teamPlayers: [Student] {
        dataManager.students.filter { team.playerIds.contains($0.id) }
    }
    
    var availablePlayers: [Student] {
        dataManager.students.filter { !team.playerIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Team header
                    VStack(spacing: 12) {
                        FlightyTeamLogo(team: team, size: 64)
                        
                        Text(team.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                        
                        Text(team.shortName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(team.primaryColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(team.primaryColor.opacity(0.12))
                            .cornerRadius(8)
                        
                        Text("\(teamPlayers.count) players")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    
                    // Roster Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("ROSTER")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showingAddPlayer.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showingAddPlayer ? "chevron.up" : "person.badge.plus")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(showingAddPlayer ? "Done" : "Add")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(team.primaryColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(team.primaryColor.opacity(0.12))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Current roster
                        if teamPlayers.isEmpty && !showingAddPlayer {
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(team.primaryColor.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "person.3")
                                        .font(.system(size: 20))
                                        .foregroundColor(team.primaryColor)
                                }
                                
                                Text("No players on this team")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                Button(action: {
                                    withAnimation(.spring(response: 0.35)) {
                                        showingAddPlayer = true
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.badge.plus")
                                        Text("Add Players")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(team.primaryColor)
                                    .cornerRadius(12)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            ForEach(teamPlayers) { student in
                                FlightyPlayerRow(student: student, team: team, onRemove: {
                                    removePlayer(student.id)
                                })
                            }
                        }
                        
                        // Add players section (expandable)
                        if showingAddPlayer {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("ADD PLAYERS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(team.primaryColor)
                                
                                if availablePlayers.isEmpty {
                                    Text("All students are already on this team")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 12)
                                } else {
                                    // Player selection grid
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                                        ForEach(availablePlayers) { student in
                                            FlightyPlayerSelectCard(
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
                                    
                                    // Save button
                                    let newPlayers = selectedPlayerIds.subtracting(Set(team.playerIds))
                                    if !newPlayers.isEmpty {
                                        Button(action: saveChanges) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("Add \(newPlayers.count) Player\(newPlayers.count == 1 ? "" : "s")")
                                            }
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(team.primaryColor)
                                            .cornerRadius(12)
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                }
                .padding(16)
            }
            .background(Color(hex: "#f5f5f7").ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            withAnimation(.spring(response: 0.35)) {
                                showingAddPlayer = true
                            }
                        }) {
                            Label("Add Players", systemImage: "person.badge.plus")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete Team", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.gray)
                    }
                }
            }
            .alert("Delete Team?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    dataManager.deleteTeam(team)
                    dismiss()
                }
            } message: {
                Text("This will permanently delete \(team.name). This action cannot be undone.")
            }
        }
    }
    
    private func removePlayer(_ playerId: UUID) {
        var updatedTeam = team
        updatedTeam.playerIds.removeAll { $0 == playerId }
        dataManager.updateTeam(updatedTeam)
        selectedPlayerIds.remove(playerId)
        HapticFeedback.impact(.medium)
    }
    
    private func saveChanges() {
        var updatedTeam = team
        updatedTeam.playerIds = Array(selectedPlayerIds)
        dataManager.updateTeam(updatedTeam)
        HapticFeedback.notification(.success)
        withAnimation(.spring(response: 0.35)) {
            showingAddPlayer = false
        }
    }
}

// MARK: - Flighty Player Row
struct FlightyPlayerRow: View {
    let student: Student
    let team: Team
    let onRemove: () -> Void
    @State private var showingRemove = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar with team color glow
            ZStack {
                Circle()
                    .fill(team.primaryColor.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .blur(radius: 4)
                
                Circle()
                    .fill(Color.avatarColor(student.avatarColor))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(team.primaryColor.opacity(0.5), lineWidth: 2)
                    )
                
                Text(student.initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                
                if let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Button(action: { showingRemove.toggle() }) {
                Image(systemName: showingRemove ? "xmark.circle.fill" : "minus.circle")
                    .font(.system(size: 18))
                    .foregroundColor(showingRemove ? .red : .gray.opacity(0.4))
            }
            
            if showingRemove {
                Button(action: onRemove) {
                    Text("Remove")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(12)
        .animation(.spring(response: 0.3), value: showingRemove)
    }
}

// MARK: - Flighty Player Select Card
struct FlightyPlayerSelectCard: View {
    let student: Student
    let isSelected: Bool
    let teamColor: Color
    let action: () -> Void
    
    @State private var isPressing = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(teamColor.opacity(0.3))
                            .frame(width: 48, height: 48)
                            .blur(radius: 5)
                    }
                    
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? teamColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
                        )
                    
                    Text(student.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    if isSelected {
                        Circle()
                            .fill(teamColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 14, y: 14)
                            .transition(.scale)
                    }
                }
                
                Text(student.name.components(separatedBy: " ").first ?? student.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? teamColor : .black)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? teamColor.opacity(0.08) : Color.gray.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? teamColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
            .scaleEffect(isPressing ? 0.95 : 1.0)
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

// MARK: - Teams Management List View
struct TeamsManagementListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var body: some View {
        List {
            ForEach(dataManager.teams.sorted { $0.name < $1.name }) { team in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: team.colorHex))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text(team.name).font(.headline)
                        Text("\(team.playerIds.count) players").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete(perform: deleteTeams)
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Manage Teams")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
    }
    
    private func deleteTeams(at offsets: IndexSet) {
        let sorted = dataManager.teams.sorted { $0.name < $1.name }
        for index in offsets {
            dataManager.deleteTeam(sorted[index])
        }
    }
}

// MARK: - Games Management List View
struct GamesManagementListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var sortedGames: [Game] {
        dataManager.games.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        List {
            ForEach(sortedGames) { game in
                gameRow(game)
            }
            .onDelete(perform: deleteGames)
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Manage Games")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
    }
    
    private func gameRow(_ game: Game) -> some View {
        let homeTeam = dataManager.teams.first { $0.id == game.homeTeamId }
        let awayTeam = dataManager.teams.first { $0.id == game.awayTeamId }
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(homeTeam?.name ?? "TBD").font(.headline)
                Text("vs").font(.caption).foregroundColor(.secondary)
                Text(awayTeam?.name ?? "TBD").font(.headline)
            }
            HStack {
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                Text("•")
                Text(game.status.rawValue)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func deleteGames(at offsets: IndexSet) {
        for index in offsets {
            dataManager.deleteGame(sortedGames[index])
        }
    }
}

// MARK: - Preview
#Preview {
    FlightyLeagueView()
        .environmentObject(DataManager.shared)
}
