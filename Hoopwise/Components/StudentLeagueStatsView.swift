import SwiftUI

// MARK: - Student League Stats View
/// A reusable component that displays league-related stats for a student
/// Shows: Team association, season averages, last game stats
struct StudentLeagueStatsView: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    var isCompact: Bool = false
    var showTeamBadge: Bool = true
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // MARK: - Computed Properties
    
    /// The player associated with this student
    private var player: Player? {
        dataManager.players.first { $0.studentId == studentId }
    }
    
    /// Teams this student is on (via playerIds which stores studentIds)
    private var teams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(studentId) }
    }
    
    /// Primary team (first team found)
    private var primaryTeam: Team? {
        teams.first
    }
    
    /// Season stats for this player
    private var seasonStats: SeasonStats? {
        guard let player = player else { return nil }
        return dataManager.seasonStats.first { $0.playerId == player.id }
    }
    
    /// All game stats for this player
    private var allGameStats: [PlayerGameStats] {
        guard let player = player else { return [] }
        return dataManager.games
            .flatMap { $0.playerStats }
            .filter { $0.playerId == player.id }
    }
    
    /// Last game stats
    private var lastGameStats: (game: Game, stats: PlayerGameStats)? {
        guard let player = player else { return nil }
        
        // Find finished games where this player has stats
        let finishedGames = dataManager.games
            .filter { $0.status == .finished }
            .sorted { $0.date > $1.date }
        
        for game in finishedGames {
            if let stats = game.playerStats.first(where: { $0.playerId == player.id }) {
                return (game, stats)
            }
        }
        return nil
    }
    
    /// Games played count
    private var gamesPlayed: Int {
        seasonStats?.gamesPlayed ?? allGameStats.count
    }
    
    /// Check if player has any league data
    var hasLeagueData: Bool {
        !teams.isEmpty || gamesPlayed > 0
    }
    
    // MARK: - Body
    
    var body: some View {
        if isCompact {
            compactView
        } else {
            fullView
        }
    }
    
    // MARK: - Compact View (for cards/lists)
    private var compactView: some View {
        HStack(spacing: 8) {
            if let team = primaryTeam, showTeamBadge {
                teamBadge(team)
            }
            
            if gamesPlayed > 0 {
                Divider()
                    .frame(height: 16)
                
                compactStats
            }
        }
    }
    
    private func teamBadge(_ team: Team) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(team.primaryColor)
                .frame(width: 8, height: 8)
            Text(team.shortName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(team.primaryColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(team.primaryColor.opacity(0.12))
        .cornerRadius(6)
    }
    
    private var compactStats: some View {
        HStack(spacing: 12) {
            if let stats = seasonStats, stats.gamesPlayed > 0 {
                statPill(value: String(format: "%.1f", stats.ppg), label: "PPG")
                statPill(value: String(format: "%.1f", stats.rpg), label: "RPG")
                statPill(value: String(format: "%.1f", stats.apg), label: "APG")
            } else if let lastGame = lastGameStats {
                statPill(value: "\(lastGame.stats.points)", label: "PTS")
                statPill(value: "\(lastGame.stats.rebounds)", label: "REB")
                statPill(value: "\(lastGame.stats.assists)", label: "AST")
            }
        }
    }
    
    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
    
    // MARK: - Full View (for detail pages)
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Team Association
            if !teams.isEmpty {
                teamSection
            }
            
            // Season Averages
            if let stats = seasonStats, stats.gamesPlayed > 0 {
                seasonAveragesSection(stats)
            }
            
            // Last Game
            if let lastGame = lastGameStats {
                lastGameSection(lastGame.game, lastGame.stats)
            }
            
            // No data state
            if !hasLeagueData {
                noDataView
            }
        }
    }
    
    // MARK: - Team Section
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "球队" : "Team")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .textCase(.uppercase)
            
            ForEach(teams) { team in
                HStack(spacing: 12) {
                    // Team logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [team.primaryColor, team.secondaryColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: team.logoSystemImage)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text(isChinese ? "\(team.playerCount) 名球员" : "\(team.playerCount) players")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Team record if available
                    if let standing = dataManager.teamStandings.first(where: { $0.teamId == team.id }) {
                        Text("\(standing.wins)-\(standing.losses)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(12)
                .background(AppTheme.surfaceColor)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Season Averages Section
    private func seasonAveragesSection(_ stats: SeasonStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "赛季平均" : "Season Averages")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text(isChinese ? "\(stats.gamesPlayed) 场比赛" : "\(stats.gamesPlayed) games")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            HStack(spacing: 0) {
                seasonStatItem(value: String(format: "%.1f", stats.ppg), label: "PPG", color: .orange)
                
                Divider().frame(height: 36)
                
                seasonStatItem(value: String(format: "%.1f", stats.rpg), label: "RPG", color: .blue)
                
                Divider().frame(height: 36)
                
                seasonStatItem(value: String(format: "%.1f", stats.apg), label: "APG", color: .green)
                
                Divider().frame(height: 36)
                
                seasonStatItem(value: String(format: "%.1f", stats.spg), label: "SPG", color: .purple)
            }
            .padding(.vertical, 12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private func seasonStatItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Last Game Section
    private func lastGameSection(_ game: Game, _ stats: PlayerGameStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "上场比赛" : "Last Game")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(spacing: 12) {
                // Game result
                HStack {
                    if let homeTeam = dataManager.teams.first(where: { $0.id == game.homeTeamId }),
                       let awayTeam = dataManager.teams.first(where: { $0.id == game.awayTeamId }) {
                        HStack(spacing: 8) {
                            Text(homeTeam.shortName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(homeTeam.primaryColor)
                            
                            Text("\(game.homeScore) - \(game.awayScore)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Text(awayTeam.shortName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(awayTeam.primaryColor)
                        }
                    }
                    
                    Spacer()
                    
                    // Win/Loss indicator
                    if let team = teams.first {
                        let isHome = game.homeTeamId == team.id
                        let won = isHome ? game.homeScore > game.awayScore : game.awayScore > game.homeScore
                        Text(won ? "W" : "L")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(won ? .green : .red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((won ? Color.green : Color.red).opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                
                Divider()
                
                // Player stats
                HStack(spacing: 16) {
                    lastGameStatItem(value: "\(stats.points)", label: "PTS")
                    lastGameStatItem(value: "\(stats.rebounds)", label: "REB")
                    lastGameStatItem(value: "\(stats.assists)", label: "AST")
                    lastGameStatItem(value: "\(stats.steals)", label: "STL")
                    lastGameStatItem(value: "\(stats.blocks)", label: "BLK")
                }
                
                // Shooting splits
                if stats.fieldGoalsAttempted > 0 {
                    HStack(spacing: 16) {
                        shootingSplit(
                            made: stats.fieldGoalsMade,
                            attempted: stats.fieldGoalsAttempted,
                            label: "FG"
                        )
                        shootingSplit(
                            made: stats.threePointersMade,
                            attempted: stats.threePointersAttempted,
                            label: "3PT"
                        )
                        shootingSplit(
                            made: stats.freeThrowsMade,
                            attempted: stats.freeThrowsAttempted,
                            label: "FT"
                        )
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private func lastGameStatItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shootingSplit(made: Int, attempted: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(made)/\(attempted)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - No Data View
    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(isChinese ? "尚未加入球队" : "Not on a team yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(isChinese ? "在联赛标签页中将该球员添加到球队" : "Add this player to a team in the League tab")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
}

// MARK: - Collapsible League Section for Detail View
struct CollapsibleLeagueSection: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    @State private var isExpanded: Bool = true
    
    // MARK: - Computed Properties
    
    private var player: Player? {
        dataManager.players.first { $0.studentId == studentId }
    }
    
    private var teams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(studentId) }
    }
    
    private var primaryTeam: Team? {
        teams.first
    }
    
    private var hasLeagueData: Bool {
        !teams.isEmpty
    }
    
    /// Compute stats from all games this player participated in
    private var computedStats: (ppg: Double, rpg: Double, gamesPlayed: Int) {
        guard let player = player else { return (0, 0, 0) }
        
        // Get all game stats for this player from finished games
        let allStats = dataManager.games
            .filter { $0.status == .finished }
            .compactMap { game -> PlayerGameStats? in
                game.playerStats.first { $0.playerId == player.id }
            }
        
        guard !allStats.isEmpty else { return (0, 0, 0) }
        
        let totalPoints = allStats.reduce(0) { $0 + $1.points }
        let totalRebounds = allStats.reduce(0) { $0 + $1.rebounds }
        let gamesPlayed = allStats.count
        
        return (
            ppg: Double(totalPoints) / Double(gamesPlayed),
            rpg: Double(totalRebounds) / Double(gamesPlayed),
            gamesPlayed: gamesPlayed
        )
    }
    
    /// Last game stats
    private var lastGameStats: (game: Game, stats: PlayerGameStats)? {
        guard let player = player else { return nil }
        
        let finishedGames = dataManager.games
            .filter { $0.status == .finished }
            .sorted { $0.date > $1.date }
        
        for game in finishedGames {
            if let stats = game.playerStats.first(where: { $0.playerId == player.id }) {
                return (game, stats)
            }
        }
        return nil
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with collapse toggle
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sportscourt.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accentColor)
                        Text("League Stats")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 16) {
                    // Team Section
                    if let team = primaryTeam {
                        teamRow(team)
                    }
                    
                    // Season Averages (computed from games)
                    if computedStats.gamesPlayed > 0 {
                        seasonAveragesRow
                    }
                    
                    // Last Game Stats
                    if let lastGame = lastGameStats {
                        lastGameRow(lastGame.game, lastGame.stats)
                    }
                    
                    // No stats yet
                    if computedStats.gamesPlayed == 0 && lastGameStats == nil && primaryTeam != nil {
                        noStatsYetView
                    }
                    
                    // Not on team
                    if !hasLeagueData {
                        notOnTeamView
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(hasLeagueData ? AppTheme.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Team Row
    private func teamRow(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAM")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
            
            HStack(spacing: 12) {
                // Team logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [team.primaryColor, team.secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: team.logoSystemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text("\(team.playerCount) players")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Season Averages Row
    private var seasonAveragesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SEASON AVERAGES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Text("\(computedStats.gamesPlayed) games")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            HStack(spacing: 0) {
                // PPG
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", computedStats.ppg))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("PPG")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                // RPG
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", computedStats.rpg))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("RPG")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Last Game Row
    private func lastGameRow(_ game: Game, _ stats: PlayerGameStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST GAME")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(spacing: 10) {
                // Game result
                HStack {
                    if let homeTeam = dataManager.teams.first(where: { $0.id == game.homeTeamId }),
                       let awayTeam = dataManager.teams.first(where: { $0.id == game.awayTeamId }) {
                        HStack(spacing: 6) {
                            Text(homeTeam.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(homeTeam.primaryColor)
                            
                            Text("\(game.homeScore) - \(game.awayScore)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Text(awayTeam.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(awayTeam.primaryColor)
                        }
                    }
                    
                    Spacer()
                    
                    // Win/Loss indicator
                    if let team = primaryTeam {
                        let isHome = game.homeTeamId == team.id
                        let won = isHome ? game.homeScore > game.awayScore : game.awayScore > game.homeScore
                        Text(won ? "W" : "L")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(won ? .green : .red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((won ? Color.green : Color.red).opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                
                Divider()
                
                // Player stats for this game
                HStack(spacing: 0) {
                    lastGameStat(value: "\(stats.points)", label: "PTS", highlight: true)
                    lastGameStat(value: "\(stats.rebounds)", label: "REB", highlight: false)
                    lastGameStat(value: "\(stats.assists)", label: "AST", highlight: false)
                    lastGameStat(value: "\(stats.steals)", label: "STL", highlight: false)
                }
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private func lastGameStat(value: String, label: String, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(highlight ? .orange : AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - No Stats Yet View
    private var noStatsYetView: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No game stats yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text("Stats will appear after playing games")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
    
    // MARK: - Not On Team View
    private var notOnTeamView: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Not on a team yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text("Add this player to a team in League")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
}

// MARK: - Collapsible Training Stats Section (In-Session Games)
struct CollapsibleTrainingStatsSection: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    @State private var isExpanded: Bool = true
    
    /// Compute training session stats from all session games
    private var trainingStats: TrainingSessionStats {
        TrainingSessionStats.calculate(for: studentId, from: dataManager.sessionEvents)
    }
    
    /// Get recent session games for trend calculation
    private var recentSessionGames: [(date: Date, stats: SessionPlayerStats)] {
        var results: [(Date, SessionPlayerStats)] = []
        for session in dataManager.sessionEvents.sorted(by: { $0.date > $1.date }) {
            for game in session.games where game.status == .completed {
                if let stats = game.stats(for: studentId) {
                    results.append((session.date, stats))
                }
            }
        }
        return Array(results.prefix(10)) // Last 10 games
    }
    
    /// Calculate trend (comparing recent to older games)
    private var pointsTrend: TrendDirection {
        let games = recentSessionGames
        guard games.count >= 4 else { return .stable }
        let recentAvg = Double(games.prefix(2).map { $0.stats.points }.reduce(0, +)) / 2.0
        let olderAvg = Double(games.dropFirst(2).prefix(2).map { $0.stats.points }.reduce(0, +)) / 2.0
        if recentAvg > olderAvg + 1 { return .up }
        if recentAvg < olderAvg - 1 { return .down }
        return .stable
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.basketball")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Training Stats")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                if trainingStats.hasStats {
                    VStack(spacing: 16) {
                        // Averages
                        trainingAveragesRow
                        
                        // Trend indicator
                        if recentSessionGames.count >= 4 {
                            trendRow
                        }
                        
                        // Recent games
                        if !recentSessionGames.isEmpty {
                            recentGamesRow
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    noTrainingStatsView
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(trainingStats.hasStats ? Color.orange.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    
    private var trainingAveragesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSION AVERAGES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(trainingStats.gamesPlayed) scrimmages")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            HStack(spacing: 0) {
                trainingStatItem(value: String(format: "%.1f", trainingStats.ppg), label: "PPG", color: .orange)
                Divider().frame(height: 40)
                trainingStatItem(value: String(format: "%.1f", trainingStats.rpg), label: "RPG", color: .blue)
                Divider().frame(height: 40)
                trainingStatItem(value: String(format: "%.1f", trainingStats.apg), label: "APG", color: .green)
            }
            .padding(.vertical, 14)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private func trainingStatItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var trendRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESSION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
            
            HStack(spacing: 12) {
                trendIndicator(stat: "Points", trend: pointsTrend)
                Spacer()
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private func trendIndicator(stat: String, trend: TrendDirection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: trend.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(trend.color)
            Text(stat)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Text(trend.label)
                .font(.system(size: 11))
                .foregroundColor(trend.color)
        }
    }
    
    private var recentGamesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SCRIMMAGES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(spacing: 6) {
                ForEach(recentSessionGames.prefix(3), id: \.date) { item in
                    HStack {
                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        HStack(spacing: 12) {
                            Text("\(item.stats.points) PTS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("\(item.stats.rebounds) REB")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                            Text("\(item.stats.assists) AST")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
    
    private var noTrainingStatsView: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No training stats yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text("Stats appear after in-session scrimmages")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
}

// MARK: - Trend Direction
enum TrendDirection {
    case up, down, stable
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .up: return "Improving"
        case .down: return "Declining"
        case .stable: return "Stable"
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            StudentLeagueStatsView(studentId: UUID(), isCompact: true)
            StudentLeagueStatsView(studentId: UUID())
            CollapsibleLeagueSection(studentId: UUID())
            CollapsibleTrainingStatsSection(studentId: UUID())
        }
        .padding()
    }
    .environmentObject(DataManager.shared)
}
