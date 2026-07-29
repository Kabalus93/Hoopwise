import SwiftUI

struct ScheduleGameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var gameDate = Date()
    @State private var venue = ""
    @State private var notes = ""
    
    var canSchedule: Bool {
        homeTeamId != nil && awayTeamId != nil && homeTeamId != awayTeamId
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Game Preview
                    if let home = selectedHomeTeam, let away = selectedAwayTeam {
                        gamePreview(home: home, away: away)
                    } else {
                        placeholderPreview
                    }
                    
                    // Team Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Teams")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        if dataManager.teams.count < 2 {
                            VStack(spacing: 12) {
                                Image(systemName: "person.3")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("You need at least 2 teams to schedule a game")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        } else {
                            // Away Team
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Away Team")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                TeamPicker(
                                    selectedTeamId: $awayTeamId,
                                    teams: dataManager.teams,
                                    excludeId: homeTeamId
                                )
                            }
                            
                            Text("vs")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                            
                            // Home Team
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Home Team")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                TeamPicker(
                                    selectedTeamId: $homeTeamId,
                                    teams: dataManager.teams,
                                    excludeId: awayTeamId
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Date & Time
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Date & Time")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        DatePicker(
                            "Game Date",
                            selection: $gameDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    
                    // Venue (from Organization locations)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Venue")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        if !dataManager.locations.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(dataManager.locations.filter { $0.isActive }) { location in
                                        Button(action: { venue = location.name }) {
                                            VStack(spacing: 6) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(venue == location.name ? location.courtType.color : AppTheme.surfaceColor)
                                                        .frame(width: 44, height: 44)
                                                    
                                                    Image(systemName: location.courtType.icon)
                                                        .font(.system(size: 18))
                                                        .foregroundColor(venue == location.name ? .white : location.courtType.color)
                                                }
                                                
                                                Text(location.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(venue == location.name ? AppTheme.accentColor : AppTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 80)
                                        }
                                    }
                                }
                            }
                        } else {
                            TextField("Enter venue (optional)", text: $venue)
                                .textFieldStyle(.plain)
                                .padding(14)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .padding(12)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(AppTheme.background)
            .navigationTitle("Schedule Game")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        scheduleGame()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSchedule)
                }
            }
        }
    }
    
    private var selectedHomeTeam: Team? {
        guard let id = homeTeamId else { return nil }
        return dataManager.teams.first { $0.id == id }
    }
    
    private var selectedAwayTeam: Team? {
        guard let id = awayTeamId else { return nil }
        return dataManager.teams.first { $0.id == id }
    }
    
    private func gamePreview(home: Team, away: Team) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                // Away
                VStack(spacing: 8) {
                    TeamLogo(team: away, size: 56)
                    Text(away.shortName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                VStack(spacing: 4) {
                    Text("@")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text(gameDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                // Home
                VStack(spacing: 8) {
                    TeamLogo(team: home, size: 56)
                    Text(home.shortName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
    
    private var placeholderPreview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 56, height: 56)
                    Text("AWY")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Text("vs")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textTertiary)
                
                VStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 56, height: 56)
                    Text("HME")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Text("Select teams to preview")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surfaceColor)
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
    
    private func scheduleGame() {
        guard let homeId = homeTeamId, let awayId = awayTeamId else { return }
        
        let game = Game(
            homeTeamId: homeId,
            awayTeamId: awayId,
            date: gameDate,
            venue: venue.isEmpty ? nil : venue,
            notes: notes.isEmpty ? nil : notes
        )
        
        dataManager.addGame(game)
        dismiss()
    }
}

// MARK: - Team Picker
struct TeamPicker: View {
    @Binding var selectedTeamId: UUID?
    let teams: [Team]
    var excludeId: UUID?
    
    var availableTeams: [Team] {
        teams.filter { $0.id != excludeId }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableTeams) { team in
                    Button(action: { selectedTeamId = team.id }) {
                        VStack(spacing: 8) {
                            TeamLogo(team: team, size: 48)
                            Text(team.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedTeamId == team.id ? AppTheme.accentColor : AppTheme.textSecondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedTeamId == team.id ? AppTheme.accentColor.opacity(0.1) : AppTheme.surfaceColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedTeamId == team.id ? AppTheme.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ScheduleGameView()
        .environmentObject(DataManager.shared)
}
