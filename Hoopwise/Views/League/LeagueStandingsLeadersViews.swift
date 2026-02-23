import SwiftUI

// MARK: - Standings Section View
struct StandingsSectionView: View {
    @EnvironmentObject var dataManager: DataManager
    
    private var standings: [TeamStandingData] {
        dataManager.teams.map { team in
            let games = dataManager.games.filter { $0.status == .finished && ($0.homeTeamId == team.id || $0.awayTeamId == team.id) }
            var wins = 0, losses = 0, pointsFor = 0, pointsAgainst = 0
            
            for game in games {
                let isHome = game.homeTeamId == team.id
                let teamScore = isHome ? game.homeScore : game.awayScore
                let oppScore = isHome ? game.awayScore : game.homeScore
                pointsFor += teamScore
                pointsAgainst += oppScore
                if teamScore > oppScore { wins += 1 } else if teamScore < oppScore { losses += 1 }
            }
            
            return TeamStandingData(team: team, wins: wins, losses: losses, pointsFor: pointsFor, pointsAgainst: pointsAgainst)
        }.sorted { $0.winPercentage > $1.winPercentage || ($0.winPercentage == $1.winPercentage && $0.pointDifferential > $1.pointDifferential) }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .center)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 32)
                Text("L").frame(width: 32)
                Text("PCT").frame(width: 48)
                Text("+/-").frame(width: 40)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
            
            ForEach(Array(standings.enumerated()), id: \.element.team.id) { index, standing in
                StandingRowView(rank: index + 1, standing: standing)
            }
            
            if standings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 40)).foregroundColor(.white.opacity(0.2))
                    Text("No standings yet").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                    Text("Complete some games to see standings").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                }.padding(.vertical, 40)
            }
        }
    }
}

struct TeamStandingData {
    let team: Team
    let wins: Int
    let losses: Int
    let pointsFor: Int
    let pointsAgainst: Int
    
    var gamesPlayed: Int { wins + losses }
    var winPercentage: Double { gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) : 0 }
    var pointDifferential: Int { pointsFor - pointsAgainst }
}

struct StandingRowView: View {
    let rank: Int
    let standing: TeamStandingData
    
    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.system(size: 12, weight: rank <= 3 ? .bold : .regular))
                .foregroundColor(rank == 1 ? .yellow : (rank <= 3 ? .white : .white.opacity(0.5)))
                .frame(width: 24, alignment: .center)
            
            HStack(spacing: 8) {
                TeamLogoView(team: standing.team, size: 28)
                Text(standing.team.shortName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("\(standing.wins)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 32)
            
            Text("\(standing.losses)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red)
                .frame(width: 32)
            
            Text(String(format: "%.3f", standing.winPercentage))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 48)
            
            Text(standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(standing.pointDifferential >= 0 ? .cyan : .orange)
                .frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rank == 1 ? standing.team.primaryColor.opacity(0.15) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - Leaders Section View
struct LeadersSectionView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedStat: LeaderStatType = .points
    
    enum LeaderStatType: String, CaseIterable {
        case points = "PTS"
        case rebounds = "REB"
        case assists = "AST"
        case steals = "STL"
        case blocks = "BLK"
        case efficiency = "EFF"
        
        var fullName: String {
            switch self {
            case .points: return "Points"
            case .rebounds: return "Rebounds"
            case .assists: return "Assists"
            case .steals: return "Steals"
            case .blocks: return "Blocks"
            case .efficiency: return "Efficiency"
            }
        }
        
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
            case .rebounds: return .purple
            case .assists: return .cyan
            case .steals: return .green
            case .blocks: return .red
            case .efficiency: return .yellow
            }
        }
    }
    
    private var leaderData: [PlayerLeaderData] {
        var playerTotals: [UUID: PlayerLeaderData] = [:]
        
        for game in dataManager.games where game.status == .finished {
            for stat in game.playerStats {
                if var existing = playerTotals[stat.playerId] {
                    existing.points += stat.points
                    existing.rebounds += stat.rebounds
                    existing.assists += stat.assists
                    existing.steals += stat.steals
                    existing.blocks += stat.blocks
                    existing.gamesPlayed += 1
                    playerTotals[stat.playerId] = existing
                } else {
                    let player = dataManager.players.first { $0.id == stat.playerId }
                    let student = player.flatMap { p in dataManager.students.first { $0.id == p.studentId } }
                    let team = dataManager.teams.first { $0.id == stat.teamId }
                    
                    playerTotals[stat.playerId] = PlayerLeaderData(
                        playerId: stat.playerId,
                        playerName: student?.name ?? "Unknown",
                        team: team,
                        points: stat.points,
                        rebounds: stat.rebounds,
                        assists: stat.assists,
                        steals: stat.steals,
                        blocks: stat.blocks,
                        gamesPlayed: 1
                    )
                }
            }
        }
        
        return Array(playerTotals.values).sorted { getValue(for: $0) > getValue(for: $1) }
    }
    
    private func getValue(for data: PlayerLeaderData) -> Double {
        switch selectedStat {
        case .points: return Double(data.points)
        case .rebounds: return Double(data.rebounds)
        case .assists: return Double(data.assists)
        case .steals: return Double(data.steals)
        case .blocks: return Double(data.blocks)
        case .efficiency: return data.efficiency
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Stat Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LeaderStatType.allCases, id: \.self) { stat in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedStat = stat } }) {
                            HStack(spacing: 6) {
                                Image(systemName: stat.icon).font(.system(size: 11))
                                Text(stat.rawValue).font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(selectedStat == stat ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selectedStat == stat ? stat.color.opacity(0.4) : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Leaders List
            if leaderData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trophy").font(.system(size: 40)).foregroundColor(.white.opacity(0.2))
                    Text("No leaders yet").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                    Text("Complete games with player stats to see leaders").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                }.padding(.vertical, 40)
            } else {
                // Top 3 Podium
                if leaderData.count >= 3 {
                    topThreePodium
                }
                
                // Full List
                VStack(spacing: 8) {
                    ForEach(Array(leaderData.prefix(10).enumerated()), id: \.element.playerId) { index, data in
                        LeaderRowView(rank: index + 1, data: data, statType: selectedStat, value: getValue(for: data))
                    }
                }
            }
        }
    }
    
    private var topThreePodium: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 2nd Place
            if leaderData.count > 1 {
                podiumItem(data: leaderData[1], rank: 2, height: 70)
            }
            
            // 1st Place
            if !leaderData.isEmpty {
                podiumItem(data: leaderData[0], rank: 1, height: 90)
            }
            
            // 3rd Place
            if leaderData.count > 2 {
                podiumItem(data: leaderData[2], rank: 3, height: 55)
            }
        }
        .padding(.vertical, 10)
    }
    
    private func podiumItem(data: PlayerLeaderData, rank: Int, height: CGFloat) -> some View {
        VStack(spacing: 6) {
            // Player Avatar
            Circle()
                .fill(data.team?.primaryColor ?? .gray)
                .frame(width: rank == 1 ? 48 : 40, height: rank == 1 ? 48 : 40)
                .overlay(
                    Text(String(data.playerName.prefix(2)).uppercased())
                        .font(.system(size: rank == 1 ? 14 : 12, weight: .bold))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(rank == 1 ? Color.yellow : (rank == 2 ? Color.gray : Color.orange), lineWidth: rank == 1 ? 3 : 2)
                )
            
            Text(data.playerName.components(separatedBy: " ").first ?? data.playerName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(String(format: selectedStat == .efficiency ? "%.1f" : "%.0f", getValue(for: data)))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(selectedStat.color)
            
            // Podium
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            rank == 1 ? Color.yellow.opacity(0.4) : (rank == 2 ? Color.gray.opacity(0.3) : Color.orange.opacity(0.3)),
                            rank == 1 ? Color.yellow.opacity(0.2) : (rank == 2 ? Color.gray.opacity(0.15) : Color.orange.opacity(0.15))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: height)
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlayerLeaderData {
    let playerId: UUID
    let playerName: String
    let team: Team?
    var points: Int
    var rebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var gamesPlayed: Int
    
    var efficiency: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(points + rebounds + assists + steals + blocks) / Double(gamesPlayed)
    }
    
    var ppg: Double { gamesPlayed > 0 ? Double(points) / Double(gamesPlayed) : 0 }
    var rpg: Double { gamesPlayed > 0 ? Double(rebounds) / Double(gamesPlayed) : 0 }
    var apg: Double { gamesPlayed > 0 ? Double(assists) / Double(gamesPlayed) : 0 }
}

struct LeaderRowView: View {
    let rank: Int
    let data: PlayerLeaderData
    let statType: LeadersSectionView.LeaderStatType
    let value: Double
    
    var body: some View {
        HStack(spacing: 10) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 12, weight: rank <= 3 ? .bold : .regular))
                .foregroundColor(rank == 1 ? .yellow : (rank == 2 ? .gray : (rank == 3 ? .orange : .white.opacity(0.5))))
                .frame(width: 20)
            
            // Team Logo
            TeamLogoView(team: data.team, size: 28)
            
            // Player Name
            VStack(alignment: .leading, spacing: 2) {
                Text(data.playerName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(data.team?.shortName ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Games Played
            Text("\(data.gamesPlayed) GP")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            
            // Stat Value
            Text(String(format: statType == .efficiency ? "%.1f" : "%.0f", value))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(statType.color)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rank <= 3 ? statType.color.opacity(0.08) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - Teams Section View
struct TeamsSectionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var showingCreateTeam: Bool
    @Binding var selectedTeam: Team?
    @Binding var showingTeamDetail: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Create Team Button
            Button(action: { showingCreateTeam = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16))
                    Text("Create New Team").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)
            
            if dataManager.teams.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3").font(.system(size: 40)).foregroundColor(.white.opacity(0.2))
                    Text("No teams yet").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                    Text("Create your first team to get started").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                }.padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(dataManager.teams) { team in
                        TeamCardView(team: team) {
                            selectedTeam = team
                            showingTeamDetail = true
                        }
                    }
                }
            }
        }
    }
}

struct TeamCardView: View {
    let team: Team
    let onTap: () -> Void
    @EnvironmentObject var dataManager: DataManager
    
    private var wins: Int {
        dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore)) }.count
    }
    private var losses: Int {
        dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore)) }.count
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                TeamLogoView(team: team, size: 44)
                
                Text(team.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(wins)-\(losses)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 10))
                    Text("\(team.playerIds.count)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.5))
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [team.primaryColor.opacity(0.3), team.primaryColor.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(team.primaryColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// TeamLogoView is defined in UnifiedLeagueView.swift
