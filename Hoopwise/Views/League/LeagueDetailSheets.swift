import SwiftUI

// MARK: - Enhanced Game Detail Sheet
struct EnhancedGameDetailSheet: View {
    let game: Game
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingLiveScoring = false
    
    private var currentGame: Game { dataManager.games.first { $0.id == game.id } ?? game }
    private var homeTeam: Team? { dataManager.teams.first { $0.id == currentGame.homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == currentGame.awayTeamId } }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [(awayTeam?.primaryColor ?? .gray).opacity(0.4), (homeTeam?.primaryColor ?? .gray).opacity(0.4)],
                          startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    Spacer()
                    statusBadge
                    Spacer()
                    Color.clear.frame(width: 28, height: 28)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        scoreSection
                        gameInfoSection
                        actionButtons
                        if currentGame.status == .finished && !currentGame.playerStats.isEmpty { boxScoreSection }
                        if currentGame.status == .scheduled { rosterSection }
                    }.padding(16).padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showingLiveScoring) {
            LiveScoringView(game: Binding(get: { dataManager.games.first { $0.id == game.id } ?? game }, set: { dataManager.updateGame($0) }))
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if currentGame.status == .live {
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(currentGame.quarterDisplay ?? "LIVE").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }.padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.red.opacity(0.3)))
        } else {
            Text(currentGame.status == .finished ? "Final" : "Scheduled")
                .font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.6))
        }
    }
    
    private var scoreSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                TeamLogoView(team: awayTeam, size: 50)
                Text(awayTeam?.shortName ?? "AWY").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                Text("\(currentGame.awayScore)").font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(currentGame.status == .finished && currentGame.awayScore > currentGame.homeScore ? .white : .white.opacity(0.6))
            }.frame(maxWidth: .infinity)
            
            VStack(spacing: 4) {
                if currentGame.status == .live {
                    Text(currentGame.timeRemaining ?? "0:00").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                } else {
                    Text("VS").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.3))
                }
            }.frame(width: 60)
            
            VStack(spacing: 8) {
                TeamLogoView(team: homeTeam, size: 50)
                Text(homeTeam?.shortName ?? "HME").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                Text("\(currentGame.homeScore)").font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(currentGame.status == .finished && currentGame.homeScore > currentGame.awayScore ? .white : .white.opacity(0.6))
            }.frame(maxWidth: .infinity)
        }.padding(.vertical, 20)
    }
    
    private var gameInfoSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                Text(currentGame.date.formatted(date: .complete, time: .shortened)).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            if let venue = currentGame.venue, !venue.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    Text(venue).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
            if let refereeId = currentGame.refereeId, let referee = dataManager.staffCoaches.first(where: { $0.id == refereeId }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    Text("Referee: \(referee.name)").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
    
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if currentGame.status == .scheduled {
                Button(action: {
                    var g = currentGame; g.status = .live; g.quarter = 1; g.timeRemaining = "10:00"
                    dataManager.updateGame(g)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Start Game").font(.system(size: 14, weight: .semibold))
                    }.foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 12).background(Capsule().fill(Color.white))
                }
            }
            if currentGame.status == .live {
                Button(action: { showingLiveScoring = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Live Scoring").font(.system(size: 14, weight: .semibold))
                    }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Capsule().fill(Color.green))
                }
                Button(action: { var g = currentGame; g.status = .finished; dataManager.updateGame(g) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered").font(.system(size: 12))
                        Text("End Game").font(.system(size: 14, weight: .semibold))
                    }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Capsule().fill(Color.red.opacity(0.8)))
                }
            }
        }
    }
    
    private var boxScoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BOX SCORE").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 0) {
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                Text("PTS").frame(width: 36); Text("REB").frame(width: 36); Text("AST").frame(width: 36)
            }.font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.4))
            
            ForEach(currentGame.playerStats.sorted { $0.points > $1.points }, id: \.id) { stat in
                let player = dataManager.players.first { $0.id == stat.playerId }
                let student = player.flatMap { p in dataManager.students.first { $0.id == p.studentId } }
                let team = dataManager.teams.first { $0.id == stat.teamId }
                
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(team?.primaryColor ?? .gray).frame(width: 6, height: 6)
                        Text(student?.name ?? "Unknown").font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(stat.points)").font(.system(size: 12, weight: stat.points >= 10 ? .bold : .regular)).foregroundColor(stat.points >= 10 ? .orange : .white).frame(width: 36)
                    Text("\(stat.rebounds)").font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).frame(width: 36)
                    Text("\(stat.assists)").font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).frame(width: 36)
                }.padding(.vertical, 6)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ROSTERS").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            if let away = awayTeam { teamRosterView(team: away) }
            if let home = homeTeam { teamRosterView(team: home) }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private func teamRosterView(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: team, size: 24)
                Text(team.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("\(team.playerIds.count) players").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            let players = dataManager.students.filter { team.playerIds.contains($0.id) }
            if players.isEmpty {
                Text("No players assigned").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(players) { student in
                            VStack(spacing: 4) {
                                Circle().fill(Color.avatarColor(student.avatarColor)).frame(width: 32, height: 32)
                                    .overlay(Text(student.initials).font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                                Text(student.name.components(separatedBy: " ").first ?? student.name).font(.system(size: 9)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(team.primaryColor.opacity(0.15)))
    }
}

// MARK: - Enhanced Team Detail Sheet
struct EnhancedTeamDetailSheet: View {
    let team: Team
    var onEdit: () -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingDeleteConfirmation = false
    
    private var wins: Int {
        dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore)) }.count
    }
    private var losses: Int {
        dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore)) }.count
    }
    private var teamGames: [Game] { dataManager.games.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }.sorted { $0.date > $1.date } }
    private var teamPlayers: [Student] { dataManager.students.filter { team.playerIds.contains($0.id) } }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [team.primaryColor.opacity(0.5), Color(hex: "#16213e")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    Spacer()
                    Text(team.name).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Menu {
                        Button(action: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit() } }) { Label("Edit Team", systemImage: "pencil") }
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) { Label("Delete Team", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 10) {
                            TeamLogoView(team: team, size: 64)
                            Text(team.shortName).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            Text("\(wins)-\(losses)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Text("Record").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        }.padding(.vertical, 10)
                        teamInfoSection
                        rosterSection
                        recentGamesSection
                    }.padding(16).padding(.bottom, 40)
                }
            }
        }
        .alert("Delete Team?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { dataManager.deleteTeam(team); dismiss() }
        } message: { Text("This will also delete all games involving this team. This action cannot be undone.") }
    }
    
    private var teamInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEAM INFO").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            if let coachId = team.coachId, let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    Text("Coach: \(coach.name)").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
            if let venue = team.homeVenue, !venue.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    Text("Home: \(venue)").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
            if let mascot = team.mascotType {
                HStack(spacing: 8) {
                    Image(systemName: "pawprint.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    Text("Mascot: \(mascot.displayName)").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ROSTER").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(teamPlayers.count) players").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            if teamPlayers.isEmpty {
                Text("No players assigned").font(.system(size: 13)).foregroundColor(.white.opacity(0.4)).padding(.vertical, 10)
            } else {
                ForEach(teamPlayers) { student in
                    HStack(spacing: 10) {
                        Circle().fill(Color.avatarColor(student.avatarColor)).frame(width: 32, height: 32)
                            .overlay(Text(student.initials).font(.system(size: 11, weight: .bold)).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(student.name).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                            if let age = student.age { Text("\(age) years old").font(.system(size: 10)).foregroundColor(.white.opacity(0.5)) }
                        }
                        Spacer()
                    }.padding(.vertical, 4)
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT GAMES").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            if teamGames.isEmpty {
                Text("No games played").font(.system(size: 13)).foregroundColor(.white.opacity(0.4)).padding(.vertical, 10)
            } else {
                ForEach(teamGames.prefix(5)) { game in
                    let opponent = game.homeTeamId == team.id ? dataManager.teams.first { $0.id == game.awayTeamId } : dataManager.teams.first { $0.id == game.homeTeamId }
                    let isHome = game.homeTeamId == team.id
                    let teamScore = isHome ? game.homeScore : game.awayScore
                    let oppScore = isHome ? game.awayScore : game.homeScore
                    let won = teamScore > oppScore
                    
                    HStack(spacing: 8) {
                        Text(game.status == .finished ? (won ? "W" : "L") : "-").font(.system(size: 11, weight: .bold))
                            .foregroundColor(game.status == .finished ? (won ? .green : .red) : .white.opacity(0.4)).frame(width: 20)
                        Text("vs \(opponent?.shortName ?? "?")").font(.system(size: 12)).foregroundColor(.white)
                        Spacer()
                        if game.status == .finished {
                            Text("\(teamScore)-\(oppScore)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        } else {
                            Text(game.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Edit Team Sheet
struct EditTeamSheet: View {
    let team: Team
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName: String
    @State private var shortName: String
    @State private var selectedColorIndex: Int
    @State private var selectedMascot: TeamMascotType?
    @State private var selectedPlayers: Set<UUID>
    @State private var selectedCoachId: UUID?
    @State private var homeVenue: String
    @State private var searchText = ""
    @State private var selectedTab = 0
    
    let colorOptions: [(color: Color, hex: String)] = [
        (.blue, "#3B82F6"), (.red, "#EF4444"), (.green, "#22C55E"), (.orange, "#F97316"),
        (.purple, "#A855F7"), (.pink, "#EC4899"), (.yellow, "#EAB308"), (.cyan, "#06B6D4")
    ]
    
    init(team: Team, isPresented: Binding<Bool>) {
        self.team = team
        self._isPresented = isPresented
        self._teamName = State(initialValue: team.name)
        self._shortName = State(initialValue: team.shortName)
        self._selectedColorIndex = State(initialValue: 0)
        self._selectedMascot = State(initialValue: team.mascotType)
        self._selectedPlayers = State(initialValue: Set(team.playerIds))
        self._selectedCoachId = State(initialValue: team.coachId)
        self._homeVenue = State(initialValue: team.homeVenue ?? "")
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { isPresented = false }.font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("Edit Team").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Spacer()
                    Button("Save") { saveTeam() }.font(.system(size: 14, weight: .semibold)).foregroundColor(!teamName.isEmpty ? .green : .white.opacity(0.3)).disabled(teamName.isEmpty)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                
                HStack(spacing: 0) {
                    ForEach(["Info", "Players", "Coach"], id: \.self) { tab in
                        let index = ["Info", "Players", "Coach"].firstIndex(of: tab) ?? 0
                        Button(action: { withAnimation { selectedTab = index } }) {
                            Text(tab).font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundColor(selectedTab == index ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(selectedTab == index ? Color.white.opacity(0.1) : Color.clear)
                        }
                    }
                }.background(Color.white.opacity(0.05)).cornerRadius(8).padding(.horizontal, 16).padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case 0: teamInfoSection
                        case 1: playersSection
                        case 2: coachSection
                        default: EmptyView()
                        }
                    }.padding(16).padding(.bottom, 40)
                }
            }
        }
    }
    
    private var teamInfoSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Team Name").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField("Enter team name", text: $teamName).textFieldStyle(.plain).font(.system(size: 15)).foregroundColor(.white)
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Short Name").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField("e.g., LAK", text: $shortName).textFieldStyle(.plain).font(.system(size: 15)).foregroundColor(.white)
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    .onChange(of: shortName) { _, newValue in shortName = String(newValue.uppercased().prefix(3)) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Team Color").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(0..<colorOptions.count, id: \.self) { i in
                        Circle().fill(colorOptions[i].color).frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.white, lineWidth: selectedColorIndex == i ? 3 : 0))
                            .onTapGesture { selectedColorIndex = i }
                    }
                }
            }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Home Venue").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField("Enter venue", text: $homeVenue).textFieldStyle(.plain).font(.system(size: 14)).foregroundColor(.white)
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
        }
    }
    
    private var playersSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                TextField("Search players...", text: $searchText).textFieldStyle(.plain).font(.system(size: 14)).foregroundColor(.white)
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            
            HStack {
                Text("Selected Players").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(selectedPlayers.count)").font(.system(size: 12, weight: .bold)).foregroundColor(.cyan)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.cyan.opacity(0.2)))
            }
            
            let filtered = searchText.isEmpty ? dataManager.students : dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            ForEach(filtered) { student in
                PlayerSelectionRow(student: student, isSelected: selectedPlayers.contains(student.id)) {
                    if selectedPlayers.contains(student.id) { selectedPlayers.remove(student.id) } else { selectedPlayers.insert(student.id) }
                }
            }
        }
    }
    
    private var coachSection: some View {
        VStack(spacing: 12) {
            Text("Assign a Coach").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: { selectedCoachId = nil }) {
                HStack(spacing: 12) {
                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.slash").font(.system(size: 16)).foregroundColor(.white.opacity(0.5)))
                    Text("No Coach Assigned").font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                    if selectedCoachId == nil { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.green) }
                }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(selectedCoachId == nil ? Color.white.opacity(0.1) : Color.white.opacity(0.05)))
            }.buttonStyle(.plain)
            
            ForEach(dataManager.staffCoaches) { coach in
                Button(action: { selectedCoachId = coach.id }) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.avatarColor(coach.avatarColor)).frame(width: 40, height: 40)
                            .overlay(Text(coach.initials).font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coach.name).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                            Text(coach.role.rawValue).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        if selectedCoachId == coach.id { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.green) }
                    }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(selectedCoachId == coach.id ? Color.white.opacity(0.1) : Color.white.opacity(0.05)))
                }.buttonStyle(.plain)
            }
        }
    }
    
    private func saveTeam() {
        var updated = team
        updated.name = teamName
        updated.shortName = shortName.isEmpty ? String(teamName.prefix(3)).uppercased() : shortName
        updated.colorHex = colorOptions[selectedColorIndex].hex
        updated.mascotType = selectedMascot
        updated.playerIds = Array(selectedPlayers)
        updated.coachId = selectedCoachId
        updated.coachName = selectedCoachId.flatMap { id in dataManager.staffCoaches.first { $0.id == id }?.name }
        updated.homeVenue = homeVenue.isEmpty ? nil : homeVenue
        dataManager.updateTeam(updated)
        isPresented = false
    }
}
