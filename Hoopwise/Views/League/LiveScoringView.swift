import SwiftUI

/// Live scoring interface for basketball games
/// Rebuilt with clean, consistent structure and reliable action handling
struct LiveScoringView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @Binding var game: Game
    
    // MARK: - State
    @State private var selectedTeamIsHome: Bool = true
    @State private var showingQuarterSheet = false
    @State private var selectedPlayerId: UUID? = nil
    @State private var showingEndGameConfirm = false
    
    // MARK: - Computed Properties
    var homeTeam: Team? {
        dataManager.teams.first { $0.id == game.homeTeamId }
    }
    
    var awayTeam: Team? {
        dataManager.teams.first { $0.id == game.awayTeamId }
    }
    
    var selectedTeam: Team? {
        selectedTeamIsHome ? homeTeam : awayTeam
    }
    
    var selectedTeamId: UUID {
        selectedTeamIsHome ? game.homeTeamId : game.awayTeamId
    }
    
    var selectedTeamColor: Color {
        selectedTeam?.primaryColor ?? AppTheme.accentColor
    }
    
    /// Get players for selected team (team.playerIds contains student IDs)
    var teamPlayers: [(player: Player, student: Student)] {
        guard let team = selectedTeam else { return [] }
        return dataManager.players.compactMap { player in
            guard team.playerIds.contains(player.studentId),
                  let student = dataManager.students.first(where: { $0.id == player.studentId }) else {
                return nil
            }
            return (player, student)
        }
    }
    
    var recentPlays: [ScoringPlay] {
        Array(game.scoringPlays.suffix(5).reversed())
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Score Display
                scoreHeader
                
                // 2. Quarter Control
                quarterControl
                
                // 3. Team Tabs
                teamTabs
                
                // 4. Scoring Buttons (main action area)
                scoringSection
                
                // 5. Recent Plays
                recentPlaysSection
            }
            .background(AppTheme.background)
            .navigationTitle("Live Scoring")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showingQuarterSheet = true }) {
                            Label("Change Quarter", systemImage: "clock.badge")
                        }
                        if !game.scoringPlays.isEmpty {
                            Button(role: .destructive, action: undoLastScore) {
                                Label("Undo Last Score", systemImage: "arrow.uturn.backward")
                            }
                        }
                        Divider()
                        Button(role: .destructive, action: { showingEndGameConfirm = true }) {
                            Label("End Game", systemImage: "flag.checkered")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingQuarterSheet) {
                QuarterSelectionSheet(currentQuarter: game.quarter ?? 1) { newQuarter in
                    setQuarter(newQuarter)
                }
                .presentationDetents([.medium])
            }
            .alert("End Game?", isPresented: $showingEndGameConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("End Game", role: .destructive) {
                    endGame()
                }
            } message: {
                Text("This will mark the game as finished. Final score: \(game.awayScore) - \(game.homeScore)")
            }
            .onAppear {
                initializeGame()
            }
            .onChange(of: selectedTeamIsHome) { _ in
                // Clear player selection when switching teams
                selectedPlayerId = nil
            }
        }
    }
    
    // MARK: - Score Header
    private var scoreHeader: some View {
        HStack(spacing: 0) {
            // Away Team (tappable)
            Button(action: { selectedTeamIsHome = false }) {
                VStack(spacing: 8) {
                    TeamLogo(team: awayTeam, size: 48)
                    Text(awayTeam?.shortName ?? "AWY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(!selectedTeamIsHome ? awayTeam?.primaryColor ?? AppTheme.accentColor : AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(!selectedTeamIsHome ? (awayTeam?.primaryColor ?? AppTheme.accentColor).opacity(0.15) : Color.clear)
            }
            .buttonStyle(.plain)
            
            // Score Display
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    Text("\(game.awayScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(game.awayScore > game.homeScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(minWidth: 50, alignment: .trailing)
                    
                    Text("-")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text("\(game.homeScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(game.homeScore > game.awayScore ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(minWidth: 50, alignment: .leading)
                }
                
                // Quarter indicator
                Text(game.quarterDisplay ?? "Q1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(minWidth: 140)
            
            // Home Team (tappable)
            Button(action: { selectedTeamIsHome = true }) {
                VStack(spacing: 8) {
                    TeamLogo(team: homeTeam, size: 48)
                    Text(homeTeam?.shortName ?? "HME")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selectedTeamIsHome ? homeTeam?.primaryColor ?? AppTheme.accentColor : AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedTeamIsHome ? (homeTeam?.primaryColor ?? AppTheme.accentColor).opacity(0.15) : Color.clear)
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Quarter Control
    private var quarterControl: some View {
        HStack {
            Button(action: { showingQuarterSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14))
                    Text(game.quarterDisplay ?? "Q1")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.accentColor)
                .cornerRadius(20)
            }
            
            Spacer()
            
            // Quick quarter advance
            if let q = game.quarter, q < 4 {
                Button(action: { setQuarter(q + 1) }) {
                    HStack(spacing: 4) {
                        Text("Next Quarter")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.accentColor)
                }
            } else if let q = game.quarter, q == 4 {
                Button(action: { setQuarter(5) }) {
                    Text("Overtime")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Team Tabs
    private var teamTabs: some View {
        HStack(spacing: 0) {
            // Away Team Tab
            Button(action: { selectedTeamIsHome = false }) {
                VStack(spacing: 4) {
                    Text(awayTeam?.name ?? "Away")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(!selectedTeamIsHome ? awayTeam?.primaryColor ?? AppTheme.accentColor : AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    Rectangle()
                        .fill(!selectedTeamIsHome ? awayTeam?.primaryColor ?? AppTheme.accentColor : Color.clear)
                        .frame(height: 3),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
            
            // Home Team Tab
            Button(action: { selectedTeamIsHome = true }) {
                VStack(spacing: 4) {
                    Text(homeTeam?.name ?? "Home")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedTeamIsHome ? homeTeam?.primaryColor ?? AppTheme.accentColor : AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    Rectangle()
                        .fill(selectedTeamIsHome ? homeTeam?.primaryColor ?? AppTheme.accentColor : Color.clear)
                        .frame(height: 3),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.surfaceColor)
    }
    
    // MARK: - Scoring Section (Main Action Area)
    private var scoringSection: some View {
        VStack(spacing: 16) {
            // Selected Player Indicator
            if let playerId = selectedPlayerId,
               let playerItem = teamPlayers.first(where: { $0.player.id == playerId }) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(selectedTeamColor)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(playerItem.student.initials)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerItem.student.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Selected - tap stat button to add")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { selectedPlayerId = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(selectedTeamColor.opacity(0.15))
            } else {
                Text("Select a player below, then tap a stat button")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            }
            
            // Point Type Buttons (require player selection)
            HStack(spacing: 12) {
                ScoreButton(label: "FT", subtitle: "Free Throw", points: 1, color: selectedPlayerId != nil ? .blue : .blue.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addScore(playerId: playerId, points: 1, playType: .freeThrow)
                    }
                }
                .disabled(selectedPlayerId == nil)
                
                ScoreButton(label: "+2", subtitle: "2-Pointer", points: 2, color: selectedPlayerId != nil ? .green : .green.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addScore(playerId: playerId, points: 2, playType: .layup)
                    }
                }
                .disabled(selectedPlayerId == nil)
                
                ScoreButton(label: "+3", subtitle: "3-Pointer", points: 3, color: selectedPlayerId != nil ? .orange : .orange.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addScore(playerId: playerId, points: 3, playType: .threePointer)
                    }
                }
                .disabled(selectedPlayerId == nil)
            }
            .padding(.horizontal, 20)
            
            // Stats Buttons (require player selection)
            HStack(spacing: 12) {
                StatButton(label: "REB", subtitle: "Rebound", icon: "arrow.up.arrow.down", color: selectedPlayerId != nil ? .purple : .purple.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addRebound(playerId: playerId)
                    }
                }
                .disabled(selectedPlayerId == nil)
                
                StatButton(label: "AST", subtitle: "Assist", icon: "arrow.triangle.branch", color: selectedPlayerId != nil ? .cyan : .cyan.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addStat(playerId: playerId, statType: .assist)
                    }
                }
                .disabled(selectedPlayerId == nil)
                
                StatButton(label: "STL", subtitle: "Steal", icon: "hand.raised.fill", color: selectedPlayerId != nil ? .red : .red.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addStat(playerId: playerId, statType: .steal)
                    }
                }
                .disabled(selectedPlayerId == nil)
                
                StatButton(label: "BLK", subtitle: "Block", icon: "shield.fill", color: selectedPlayerId != nil ? .indigo : .indigo.opacity(0.4)) {
                    if let playerId = selectedPlayerId {
                        addStat(playerId: playerId, statType: .block)
                    }
                }
                .disabled(selectedPlayerId == nil)
            }
            .padding(.horizontal, 20)
            
            // Player Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap to select player")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 20)
                
                if teamPlayers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.3")
                                .font(.system(size: 28))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("No players on roster")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(teamPlayers, id: \.player.id) { item in
                                let playerStats = game.playerStats.first { $0.playerId == item.player.id }
                                let isSelected = selectedPlayerId == item.player.id
                                PlayerScoreButton(
                                    player: item.player,
                                    student: item.student,
                                    teamColor: selectedTeamColor,
                                    points: playerStats?.points ?? 0,
                                    rebounds: playerStats?.rebounds ?? 0,
                                    isSelected: isSelected,
                                    action: {
                                        // Tap action - select/deselect this player
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if selectedPlayerId == item.player.id {
                                                selectedPlayerId = nil
                                            } else {
                                                selectedPlayerId = item.player.id
                                            }
                                        }
                                    },
                                    longPressAction: {
                                        // Long press - quick add 2 points
                                        addScore(playerId: item.player.id, points: 2, playType: .layup)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Recent Plays Section
    private var recentPlaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Plays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                if !recentPlays.isEmpty {
                    Button("Undo") {
                        undoLastScore()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 20)
            
            if recentPlays.isEmpty {
                Text("No plays recorded yet")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(recentPlays) { play in
                            PlayRow(play: play, dataManager: dataManager, game: game)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxHeight: 180)
        .padding(.vertical, 12)
        .background(AppTheme.surfaceColor)
    }
    
    // MARK: - Actions
    
    /// Initialize game state on appear
    private func initializeGame() {
        if game.quarter == nil {
            var updated = game
            updated.quarter = 1
            updated.status = .live
            game = updated
            dataManager.updateGame(game)
        }
    }
    
    /// Set the current quarter
    private func setQuarter(_ quarter: Int) {
        var updated = game
        updated.quarter = quarter
        if !updated.quarterScores.contains(where: { $0.quarter == quarter }) {
            updated.quarterScores.append(QuarterScore(quarter: quarter))
        }
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Haptic
        HapticFeedback.impact(.light)
    }
    
    /// End the game and finalize all stats
    private func endGame() {
        var updated = game
        updated.status = .finished
        updated.updatedAt = Date()
        game = updated
        
        // updateGame will automatically:
        // 1. Update standings (updateStandingsAfterGame)
        // 2. Update season stats (updateSeasonStatsAfterGame)
        // 3. Sync to student profiles
        // 4. Save league data
        dataManager.updateGame(game)
        
        // Haptic
        HapticFeedback.notification(.success)
        
        debugLog("🏁 Game ended. Final: \(game.awayScore) - \(game.homeScore)")
        
        // Dismiss the view
        dismiss()
    }
    
    /// Add points to the currently selected team (no specific player)
    private func addPointsToTeam(_ points: Int) {
        var updated = game
        let quarter = game.quarter ?? 1
        
        if selectedTeamIsHome {
            updated.homeScore += points
        } else {
            updated.awayScore += points
        }
        
        // Update quarter score
        if let idx = updated.quarterScores.firstIndex(where: { $0.quarter == quarter }) {
            if selectedTeamIsHome {
                updated.quarterScores[idx].homeScore += points
            } else {
                updated.quarterScores[idx].awayScore += points
            }
        } else {
            var qs = QuarterScore(quarter: quarter)
            if selectedTeamIsHome {
                qs.homeScore = points
            } else {
                qs.awayScore = points
            }
            updated.quarterScores.append(qs)
        }
        
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Haptic
        HapticFeedback.impact(.medium)
        
        debugLog("✅ Added \(points) pts to \(selectedTeamIsHome ? "Home" : "Away"). Score: \(game.awayScore)-\(game.homeScore)")
    }
    
    /// Add score for a specific player
    private func addScore(playerId: UUID, points: Int, playType: ScoringPlayType) {
        let quarter = game.quarter ?? 1
        var updated = game
        
        // Create scoring play
        let play = ScoringPlay(
            gameId: game.id,
            playerId: playerId,
            teamId: selectedTeamId,
            points: points,
            playType: playType,
            quarter: quarter,
            assistedById: nil
        )
        updated.scoringPlays.append(play)
        
        // Update team score
        if selectedTeamIsHome {
            updated.homeScore += points
        } else {
            updated.awayScore += points
        }
        
        // Update quarter score
        if let idx = updated.quarterScores.firstIndex(where: { $0.quarter == quarter }) {
            if selectedTeamIsHome {
                updated.quarterScores[idx].homeScore += points
            } else {
                updated.quarterScores[idx].awayScore += points
            }
        } else {
            var qs = QuarterScore(quarter: quarter)
            if selectedTeamIsHome {
                qs.homeScore = points
            } else {
                qs.awayScore = points
            }
            updated.quarterScores.append(qs)
        }
        
        // Update player stats
        if let idx = updated.playerStats.firstIndex(where: { $0.playerId == playerId }) {
            updated.playerStats[idx].points += points
            switch playType {
            case .freeThrow:
                updated.playerStats[idx].freeThrowsMade += 1
                updated.playerStats[idx].freeThrowsAttempted += 1
            case .threePointer:
                updated.playerStats[idx].threePointersMade += 1
                updated.playerStats[idx].threePointersAttempted += 1
                updated.playerStats[idx].fieldGoalsMade += 1
                updated.playerStats[idx].fieldGoalsAttempted += 1
            default:
                updated.playerStats[idx].fieldGoalsMade += 1
                updated.playerStats[idx].fieldGoalsAttempted += 1
            }
        } else {
            var stats = PlayerGameStats(gameId: game.id, playerId: playerId, teamId: selectedTeamId)
            stats.points = points
            switch playType {
            case .freeThrow:
                stats.freeThrowsMade = 1
                stats.freeThrowsAttempted = 1
            case .threePointer:
                stats.threePointersMade = 1
                stats.threePointersAttempted = 1
                stats.fieldGoalsMade = 1
                stats.fieldGoalsAttempted = 1
            default:
                stats.fieldGoalsMade = 1
                stats.fieldGoalsAttempted = 1
            }
            updated.playerStats.append(stats)
        }
        
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Haptic
        HapticFeedback.impact(.medium)
        
        debugLog("✅ \(points) pts for player \(playerId). Score: \(game.awayScore)-\(game.homeScore)")
    }
    
    /// Add a rebound for a specific player
    private func addRebound(playerId: UUID) {
        var updated = game
        
        // Update player stats
        if let idx = updated.playerStats.firstIndex(where: { $0.playerId == playerId }) {
            updated.playerStats[idx].rebounds += 1
        } else {
            var stats = PlayerGameStats(gameId: game.id, playerId: playerId, teamId: selectedTeamId)
            stats.rebounds = 1
            updated.playerStats.append(stats)
        }
        
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Update season stats with rebound
        dataManager.updatePlayerSeasonStats(playerId: playerId, points: 0, rebounds: 1)
        
        // Haptic
        HapticFeedback.impact(.light)
        
        debugLog("🏀 +1 rebound for player \(playerId)")
    }
    
    /// Add a stat (assist, steal, block) for a specific player
    private func addStat(playerId: UUID, statType: StatType) {
        var updated = game
        
        // Update player stats
        if let idx = updated.playerStats.firstIndex(where: { $0.playerId == playerId }) {
            switch statType {
            case .assist:
                updated.playerStats[idx].assists += 1
            case .steal:
                updated.playerStats[idx].steals += 1
            case .block:
                updated.playerStats[idx].blocks += 1
            case .turnover:
                updated.playerStats[idx].turnovers += 1
            case .rebound:
                updated.playerStats[idx].rebounds += 1
            }
        } else {
            var stats = PlayerGameStats(gameId: game.id, playerId: playerId, teamId: selectedTeamId)
            switch statType {
            case .assist:
                stats.assists = 1
            case .steal:
                stats.steals = 1
            case .block:
                stats.blocks = 1
            case .turnover:
                stats.turnovers = 1
            case .rebound:
                stats.rebounds = 1
            }
            updated.playerStats.append(stats)
        }
        
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Update season stats
        switch statType {
        case .assist:
            dataManager.updatePlayerSeasonStats(playerId: playerId, points: 0, rebounds: 0, assists: 1)
        case .steal:
            dataManager.updatePlayerSeasonStats(playerId: playerId, points: 0, rebounds: 0, assists: 0, steals: 1)
        case .block:
            dataManager.updatePlayerSeasonStats(playerId: playerId, points: 0, rebounds: 0, assists: 0, steals: 0, blocks: 1)
        case .rebound:
            dataManager.updatePlayerSeasonStats(playerId: playerId, points: 0, rebounds: 1)
        case .turnover:
            break // Turnovers don't need season stat update here
        }
        
        // Haptic
        HapticFeedback.impact(.light)
        
        debugLog("📊 +1 \(statType.rawValue) for player \(playerId)")
    }
    
    enum StatType: String {
        case rebound = "rebound"
        case assist = "assist"
        case steal = "steal"
        case block = "block"
        case turnover = "turnover"
    }
    
    /// Undo the last scoring play
    private func undoLastScore() {
        guard let lastPlay = game.scoringPlays.last else { return }
        
        var updated = game
        
        // Remove scoring play
        updated.scoringPlays.removeLast()
        
        // Reverse team score
        if lastPlay.teamId == game.homeTeamId {
            updated.homeScore = max(0, updated.homeScore - lastPlay.points)
        } else {
            updated.awayScore = max(0, updated.awayScore - lastPlay.points)
        }
        
        // Reverse quarter score
        if let idx = updated.quarterScores.firstIndex(where: { $0.quarter == lastPlay.quarter }) {
            if lastPlay.teamId == game.homeTeamId {
                updated.quarterScores[idx].homeScore = max(0, updated.quarterScores[idx].homeScore - lastPlay.points)
            } else {
                updated.quarterScores[idx].awayScore = max(0, updated.quarterScores[idx].awayScore - lastPlay.points)
            }
        }
        
        // Reverse player stats
        if let idx = updated.playerStats.firstIndex(where: { $0.playerId == lastPlay.playerId }) {
            updated.playerStats[idx].points = max(0, updated.playerStats[idx].points - lastPlay.points)
            switch lastPlay.playType {
            case .freeThrow:
                updated.playerStats[idx].freeThrowsMade = max(0, updated.playerStats[idx].freeThrowsMade - 1)
                updated.playerStats[idx].freeThrowsAttempted = max(0, updated.playerStats[idx].freeThrowsAttempted - 1)
            case .threePointer:
                updated.playerStats[idx].threePointersMade = max(0, updated.playerStats[idx].threePointersMade - 1)
                updated.playerStats[idx].threePointersAttempted = max(0, updated.playerStats[idx].threePointersAttempted - 1)
                updated.playerStats[idx].fieldGoalsMade = max(0, updated.playerStats[idx].fieldGoalsMade - 1)
                updated.playerStats[idx].fieldGoalsAttempted = max(0, updated.playerStats[idx].fieldGoalsAttempted - 1)
            default:
                updated.playerStats[idx].fieldGoalsMade = max(0, updated.playerStats[idx].fieldGoalsMade - 1)
                updated.playerStats[idx].fieldGoalsAttempted = max(0, updated.playerStats[idx].fieldGoalsAttempted - 1)
            }
        }
        
        updated.updatedAt = Date()
        game = updated
        dataManager.updateGame(game)
        
        // Haptic
        HapticFeedback.notification(.warning)
        
        debugLog("⏪ Undo: Removed \(lastPlay.points) pts. Score: \(game.awayScore)-\(game.homeScore)")
    }
}

// MARK: - Score Button Component
struct ScoreButton: View {
    let label: String
    let subtitle: String
    let points: Int
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 24, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(color.gradient)
            .cornerRadius(16)
        }
    }
}

// MARK: - Stat Button Component (for Rebounds, Assists, etc.)
struct StatButton: View {
    let label: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.8).gradient)
            .cornerRadius(10)
        }
    }
}

// MARK: - Player Score Button Component
struct PlayerScoreButton: View {
    let player: Player
    let student: Student
    let teamColor: Color
    let points: Int
    let rebounds: Int
    let isSelected: Bool
    let action: () -> Void
    let longPressAction: () -> Void
    
    init(player: Player, student: Student, teamColor: Color, points: Int, rebounds: Int = 0, isSelected: Bool = false, action: @escaping () -> Void, longPressAction: @escaping () -> Void = {}) {
        self.player = player
        self.student = student
        self.teamColor = teamColor
        self.points = points
        self.rebounds = rebounds
        self.isSelected = isSelected
        self.action = action
        self.longPressAction = longPressAction
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isSelected ? teamColor : teamColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? teamColor : Color.clear, lineWidth: 3)
                            .frame(width: 56, height: 56)
                    )
                
                Text(student.initials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : teamColor)
                
                // Jersey number badge
                if let jersey = player.jerseyNumber {
                    Text("#\(jersey)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(teamColor)
                        .cornerRadius(4)
                        .offset(x: 18, y: 18)
                }
                
                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Circle().fill(teamColor).frame(width: 18, height: 18))
                        .offset(x: -18, y: -18)
                }
            }
            
            // Name
            Text(student.name.components(separatedBy: " ").first ?? "Player")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                .lineLimit(1)
            
            // Stats in this game (points + rebounds)
            HStack(spacing: 4) {
                Text("\(points)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(teamColor)
                Text("pts")
                    .font(.system(size: 8))
                    .foregroundColor(AppTheme.textSecondary)
                if rebounds > 0 {
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("\(rebounds)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.purple)
                    Text("reb")
                        .font(.system(size: 8))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .frame(width: 80)
        .padding(.vertical, 8)
        .background(isSelected ? teamColor.opacity(0.1) : Color.clear)
        .cornerRadius(12)
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            longPressAction()
        }
    }
}

// MARK: - Play Row Component
struct PlayRow: View {
    let play: ScoringPlay
    let dataManager: DataManager
    let game: Game
    
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
    
    var body: some View {
        HStack(spacing: 10) {
            // Team color indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(team?.primaryColor ?? AppTheme.accentColor)
                .frame(width: 4, height: 36)
            
            // Quarter
            Text("Q\(play.quarter)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 22)
            
            // Player & Points
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(student?.name ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("+\(play.points)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(team?.primaryColor ?? AppTheme.accentColor)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: play.playType.icon)
                        .font(.system(size: 9))
                    Text(play.playType.rawValue)
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            // Time
            Text(play.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(AppTheme.cardBackground)
        .cornerRadius(8)
    }
}


// MARK: - Quarter Selection Sheet
struct QuarterSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentQuarter: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("Regulation") {
                    ForEach(1...4, id: \.self) { quarter in
                        Button(action: {
                            onSelect(quarter)
                            dismiss()
                        }) {
                            HStack {
                                Text("Quarter \(quarter)")
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if currentQuarter == quarter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.accentColor)
                                }
                            }
                        }
                    }
                }
                
                Section("Overtime") {
                    ForEach(1...3, id: \.self) { ot in
                        Button(action: {
                            onSelect(4 + ot)
                            dismiss()
                        }) {
                            HStack {
                                Text("Overtime \(ot)")
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if currentQuarter == 4 + ot {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Quarter")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LiveScoringView(game: .constant(Game(
        homeTeamId: UUID(),
        awayTeamId: UUID(),
        date: Date(),
        status: .live,
        quarter: 1
    )))
    .environmentObject(DataManager.shared)
}
