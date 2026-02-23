import SwiftUI

struct GameDetailView: View {
    @State var game: Game
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: GameTab = .boxScore
    @State private var isEditing = false
    @State private var homeScore: Int
    @State private var awayScore: Int
    @State private var currentQuarter: Int
    @State private var gameStatus: GameStatus
    @State private var showingLiveScoring = false
    
    enum GameTab: String, CaseIterable {
        case boxScore = "Box Score"
        case playByPlay = "Play-by-Play"
        case stats = "Stats"
    }
    
    init(game: Game) {
        _game = State(initialValue: game)
        _homeScore = State(initialValue: game.homeScore)
        _awayScore = State(initialValue: game.awayScore)
        _currentQuarter = State(initialValue: game.quarter ?? 1)
        _gameStatus = State(initialValue: game.status)
    }
    
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Score Header
                    scoreHeader
                    
                    // Quick Actions (for live/scheduled games)
                    if game.status != .finished {
                        quickActions
                    }
                    
                    // Tab Selector
                    tabSelector
                    
                    // Content
                    switch selectedTab {
                    case .boxScore:
                        boxScoreContent
                    case .playByPlay:
                        playByPlayContent
                    case .stats:
                        statsContent
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayModeCompat(.inline)
            .onAppear {
                // Sync with dataManager on appear to get latest data
                if let updatedGame = dataManager.games.first(where: { $0.id == game.id }) {
                    game = updatedGame
                    homeScore = updatedGame.homeScore
                    awayScore = updatedGame.awayScore
                    currentQuarter = updatedGame.quarter ?? 1
                    gameStatus = updatedGame.status
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                if game.status != .finished {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if game.status == .scheduled {
                                Button(action: startGame) {
                                    Label("Start Game", systemImage: "play.fill")
                                }
                            }
                            if game.status == .live {
                                Button(action: endGame) {
                                    Label("End Game", systemImage: "stop.fill")
                                }
                            }
                            Button(role: .destructive, action: cancelGame) {
                                Label("Cancel Game", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Score Header
    private var scoreHeader: some View {
        VStack(spacing: 20) {
            // Status Badge
            HStack(spacing: 6) {
                if game.status == .live {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                Text(game.status.rawValue.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(game.status.color)
                
                if let quarter = game.quarterDisplay {
                    Text("•")
                        .foregroundColor(AppTheme.textTertiary)
                    Text(quarter)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            
            // Teams and Score
            HStack(spacing: 0) {
                // Away Team
                VStack(spacing: 12) {
                    TeamLogo(team: awayTeam, size: 64)
                    Text(awayTeam?.name ?? "Away")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                
                // Score
                VStack(spacing: 8) {
                    if game.status == .scheduled {
                        Text(game.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    } else {
                        HStack(spacing: 12) {
                            Text("\(awayScore)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(awayScore > homeScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .frame(minWidth: 55, alignment: .trailing)
                            
                            Text("-")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            Text("\(homeScore)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(homeScore > awayScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .frame(minWidth: 55, alignment: .leading)
                        }
                    }
                }
                .frame(minWidth: 150)
                
                // Home Team
                VStack(spacing: 12) {
                    TeamLogo(team: homeTeam, size: 64)
                    Text(homeTeam?.name ?? "Home")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Venue
            if let venue = game.venue {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                    Text(venue)
                        .font(.system(size: 12))
                }
                .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Team colors gradient (side to side)
                LinearGradient(
                    colors: [
                        (awayTeam?.primaryColor ?? Color(hex: "#5B8DEF")).opacity(0.25),
                        (awayTeam?.primaryColor ?? Color(hex: "#5B8DEF")).opacity(0.08),
                        (homeTeam?.primaryColor ?? Color(hex: "#6BCB77")).opacity(0.08),
                        (homeTeam?.primaryColor ?? Color(hex: "#6BCB77")).opacity(0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                
                // Subtle overlay for readability
                LinearGradient(
                    colors: [
                        AppTheme.cardBackground.opacity(0.3),
                        AppTheme.cardBackground.opacity(0.5),
                        AppTheme.cardBackground.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }
    
    // MARK: - Quick Actions
    private var quickActions: some View {
        VStack(spacing: 12) {
            if game.status == .scheduled {
                // Start Game Button
                Button(action: startGame) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                        Text("Start Game")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.successColor, AppTheme.successColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                // Game info
                VStack(spacing: 4) {
                    Text("Game scheduled for")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(game.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    if let venue = game.venue {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11))
                            Text(venue)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.bottom, 8)
            } else if game.status == .live {
                // Open Live Scoring Button
                Button(action: { showingLiveScoring = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sportscourt.fill")
                            .font(.system(size: 16))
                        Text("Live Scoring")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accentColor, AppTheme.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                // Quick score buttons (simplified)
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(awayTeam?.shortName ?? "AWY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        HStack(spacing: 8) {
                            quickScoreButton("+1", team: .away)
                            quickScoreButton("+2", team: .away)
                            quickScoreButton("+3", team: .away)
                        }
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(spacing: 4) {
                        Text(homeTeam?.shortName ?? "HME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        HStack(spacing: 8) {
                            quickScoreButton("+1", team: .home)
                            quickScoreButton("+2", team: .home)
                            quickScoreButton("+3", team: .home)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Text("Tap 'Live Scoring' to track individual player scores")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                
                // End Game Button
                Button(action: endGame) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 12))
                        Text("End Game")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.warningColor)
                    .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 12)
        .fullScreenCoverCompat(isPresented: $showingLiveScoring) {
            LiveScoringView(game: $game)
                .onDisappear {
                    // Sync local state with game state from dataManager (source of truth)
                    if let updatedGame = dataManager.games.first(where: { $0.id == game.id }) {
                        game = updatedGame
                    }
                    homeScore = game.homeScore
                    awayScore = game.awayScore
                    currentQuarter = game.quarter ?? 1
                    gameStatus = game.status
                }
        }
    }
    
    private enum QuickScoreTeam {
        case home, away
    }
    
    private func quickScoreButton(_ label: String, team: QuickScoreTeam) -> some View {
        let points = Int(label.replacingOccurrences(of: "+", with: "")) ?? 0
        return Button(action: {
            if team == .home {
                homeScore += points
                game.homeScore = homeScore
            } else {
                awayScore += points
                game.awayScore = awayScore
            }
            updateGameScore()
        }) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 36)
                .background(team == .home ? (homeTeam?.primaryColor ?? AppTheme.accentColor) : (awayTeam?.primaryColor ?? AppTheme.accentColor))
                .cornerRadius(8)
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(GameTab.allCases, id: \.self) { tab in
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
    
    // MARK: - Box Score Content
    private var boxScoreContent: some View {
        VStack(spacing: 24) {
            // Away Team Box Score
            if let away = awayTeam {
                TeamBoxScore(team: away, stats: awayTeamStats)
            }
            
            // Home Team Box Score
            if let home = homeTeam {
                TeamBoxScore(team: home, stats: homeTeamStats)
            }
            
            if game.playerStats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No stats recorded yet")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.vertical, 40)
            }
        }
        .padding(20)
    }
    
    // MARK: - Play by Play Content
    private var playByPlayContent: some View {
        VStack(spacing: 16) {
            if game.scoringPlays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No plays recorded yet")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    if game.status == .live {
                        Text("Use Live Scoring to track plays")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.vertical, 40)
            } else {
                // Quarter selector
                if !game.quarterScores.isEmpty {
                    quarterScoreHeader
                }
                
                // Plays list grouped by quarter
                ForEach(Array(Set(game.scoringPlays.map { $0.quarter })).sorted().reversed(), id: \.self) { quarter in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quarter <= 4 ? "Quarter \(quarter)" : "Overtime \(quarter - 4)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.top, 8)
                        
                        ForEach(game.scoringPlays(forQuarter: quarter).reversed()) { play in
                            PlayByPlayRow(play: play, game: game)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
    
    private var quarterScoreHeader: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 60)
            
            ForEach(game.quarterScores.sorted(by: { $0.quarter < $1.quarter }), id: \.quarter) { qs in
                VStack(spacing: 2) {
                    Text(qs.quarter <= 4 ? "Q\(qs.quarter)" : "OT\(qs.quarter - 4)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(width: 40)
            }
            
            Text("Total")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 50)
        }
        .padding(.vertical, 8)
        .background(AppTheme.surfaceColor)
        .cornerRadius(8)
    }
    
    // MARK: - Stats Content
    private var statsContent: some View {
        VStack(spacing: 16) {
            // Team comparison stats
            if game.status != .scheduled {
                TeamComparisonStats(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeScore: homeScore,
                    awayScore: awayScore
                )
            } else {
                Text("Stats will be available after the game starts")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 40)
            }
        }
        .padding(20)
    }
    
    // MARK: - Computed Properties
    private var awayTeamStats: [PlayerGameStats] {
        game.playerStats.filter { $0.teamId == game.awayTeamId }
    }
    
    private var homeTeamStats: [PlayerGameStats] {
        game.playerStats.filter { $0.teamId == game.homeTeamId }
    }
    
    // MARK: - Actions
    private func startGame() {
        game.status = .live
        game.quarter = 1
        // Initialize first quarter score
        if game.quarterScores.isEmpty {
            game.quarterScores.append(QuarterScore(quarter: 1))
        }
        dataManager.updateGame(game)
        gameStatus = .live
        currentQuarter = 1
    }
    
    private func endGame() {
        game.status = .finished
        game.homeScore = homeScore
        game.awayScore = awayScore
        
        // Update game - DataManager will handle stats updates internally
        dataManager.updateGame(game)
        gameStatus = .finished
    }
    
    private func cancelGame() {
        game.status = .cancelled
        dataManager.updateGame(game)
        dismiss()
    }
    
    private func updateGameScore() {
        game.homeScore = homeScore
        game.awayScore = awayScore
        dataManager.updateGame(game)
    }
}

// MARK: - Team Box Score
struct TeamBoxScore: View {
    let team: Team
    let stats: [PlayerGameStats]
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TeamLogo(team: team, size: 28)
                Text(team.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            if stats.isEmpty {
                Text("No player stats")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                // Header
                HStack(spacing: 0) {
                    Text("Player")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PTS")
                        .frame(width: 35)
                    Text("REB")
                        .frame(width: 35)
                    Text("AST")
                        .frame(width: 35)
                    Text("MIN")
                        .frame(width: 35)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 12)
                
                // Player rows
                ForEach(stats) { stat in
                    // playerId is player.id, so find player first, then student
                    if let player = dataManager.players.first(where: { $0.id == stat.playerId }),
                       let student = dataManager.students.first(where: { $0.id == player.studentId }) {
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                StudentAvatarView(student: student, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(student.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    if let jersey = player.jerseyNumber {
                                        Text("#\(jersey)")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(stat.points)")
                                .frame(width: 35)
                                .fontWeight(stat.points >= 10 ? .bold : .regular)
                            Text("\(stat.rebounds)")
                                .frame(width: 35)
                            Text("\(stat.assists)")
                                .frame(width: 35)
                            Text("\(stat.minutesPlayed)")
                                .frame(width: 35)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Team Comparison Stats
struct TeamComparisonStats: View {
    let homeTeam: Team?
    let awayTeam: Team?
    let homeScore: Int
    let awayScore: Int
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Team Stats")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                StatComparisonRow(label: "Points", awayValue: awayScore, homeValue: homeScore)
                // Add more comparison stats as needed
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

struct StatComparisonRow: View {
    let label: String
    let awayValue: Int
    let homeValue: Int
    
    var total: Int { awayValue + homeValue }
    var awayPercent: CGFloat {
        guard total > 0 else { return 0.5 }
        return CGFloat(awayValue) / CGFloat(total)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(awayValue)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(awayValue > homeValue ? AppTheme.accentColor : AppTheme.textSecondary)
                
                Spacer()
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Text("\(homeValue)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(homeValue > awayValue ? AppTheme.accentColor : AppTheme.textSecondary)
            }
            
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(awayValue > homeValue ? AppTheme.accentColor : AppTheme.textTertiary.opacity(0.3))
                        .frame(width: geo.size.width * awayPercent)
                    
                    Rectangle()
                        .fill(homeValue > awayValue ? AppTheme.accentColor : AppTheme.textTertiary.opacity(0.3))
                        .frame(width: geo.size.width * (1 - awayPercent))
                }
                .cornerRadius(2)
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Play By Play Row
struct PlayByPlayRow: View {
    let play: ScoringPlay
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    
    var player: Player? {
        dataManager.players.first { $0.id == play.playerId }
    }
    
    var student: Student? {
        guard let player = player else { return nil }
        return dataManager.students.first { $0.id == player.studentId }
    }
    
    var team: Team? {
        dataManager.teams.first { $0.id == play.teamId }
    }
    
    var assister: Student? {
        guard let assisterId = play.assistedById,
              let player = dataManager.players.first(where: { $0.id == assisterId }) else { return nil }
        return dataManager.students.first { $0.id == player.studentId }
    }
    
    var isHomeTeam: Bool {
        play.teamId == game.homeTeamId
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Team indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(team?.primaryColor ?? AppTheme.accentColor)
                .frame(width: 4, height: 44)
            
            // Play details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Player name
                    Text(student?.name ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    // Points badge
                    Text("+\(play.points)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(team?.primaryColor ?? AppTheme.accentColor)
                        .cornerRadius(4)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: play.playType.icon)
                        .font(.system(size: 11))
                    Text(play.playType.rawValue)
                        .font(.system(size: 12))
                    
                    if let assister = assister {
                        Text("•")
                        Text("Ast: \(assister.name.components(separatedBy: " ").first ?? "")")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            // Running score at this point
            VStack(alignment: .trailing, spacing: 2) {
                Text(play.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                
                Text(team?.shortName ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(team?.primaryColor ?? AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
    }
}

#Preview {
    GameDetailView(game: Game(
        homeTeamId: UUID(),
        awayTeamId: UUID(),
        homeScore: 45,
        awayScore: 42,
        date: Date(),
        status: .live,
        quarter: 3
    ))
    .environmentObject(DataManager.shared)
}
