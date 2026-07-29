import SwiftUI

// MARK: - League
struct LeagueMacView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var section: Section = .teams
    @State private var selectedTeamID: Team.ID?
    @State private var selectedGameID: Game.ID?
    @State private var showingNewTeam = false
    @State private var showingNewGame = false

    enum Section: String, CaseIterable, Identifiable {
        case teams, games, standings
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .teams: return "person.3.fill"
            case .games: return "trophy.fill"
            case .standings: return "list.number"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 320, idealWidth: 360)
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingNewTeam) { NewTeamSheet() }
        .sheet(isPresented: $showingNewGame) { NewGameSheet() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingNewTeam = true } label: {
                        Label("New Team", systemImage: "person.3.fill")
                    }
                    Button { showingNewGame = true } label: {
                        Label("New Game", systemImage: "trophy.fill")
                    }
                    .disabled(dataManager.teams.count < 2)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { s in
                    Label(s.label, systemImage: s.systemImage).tag(s)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            Divider()

            switch section {
            case .teams: teamsList
            case .games: gamesList
            case .standings: standingsList
            }
        }
        .navigationTitle("League")
    }

    private var teamsList: some View {
        List(selection: $selectedTeamID) {
            if dataManager.teams.isEmpty {
                Text("No teams yet.").foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(dataManager.teams) { team in
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 22, height: 22)
                        Text(team.name).font(.subheadline.weight(.medium))
                        Spacer()
                        if let standing = dataManager.teamStandings.first(where: { $0.teamId == team.id }) {
                            Text(standing.record).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .tag(team.id)
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var gamesList: some View {
        List(selection: $selectedGameID) {
            if dataManager.games.isEmpty {
                Text("No games scheduled.").foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(dataManager.games.sorted { $0.date > $1.date }) { game in
                    GameSidebarRow(game: game).tag(game.id)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var standingsList: some View {
        let standings = dataManager.teamStandings.sorted {
            ($0.winPercentage, $0.wins) > ($1.winPercentage, $1.wins)
        }
        return ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { idx, standing in
                    if let team = dataManager.teams.first(where: { $0.id == standing.teamId }) {
                        HStack(spacing: 10) {
                            Text("\(idx + 1)").font(.caption.weight(.bold).monospacedDigit()).frame(width: 24, alignment: .leading).foregroundStyle(.secondary)
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 18, height: 18)
                            Text(team.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(standing.record).font(.caption.weight(.semibold).monospacedDigit())
                            Text(standing.streakDisplay).font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch section {
        case .teams:
            if let id = selectedTeamID, let team = dataManager.teams.first(where: { $0.id == id }) {
                TeamDetailView(team: team).id(team.id)
            } else {
                EmptyDetail(systemImage: "person.3", title: "Select a Team")
            }
        case .games:
            if let id = selectedGameID, let game = dataManager.games.first(where: { $0.id == id }) {
                GameDetailView(game: game).id(game.id)
            } else {
                EmptyDetail(systemImage: "trophy", title: "Select a Game")
            }
        case .standings:
            EmptyDetail(systemImage: "list.number", title: "Standings")
        }
    }
}

private struct GameSidebarRow: View {
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    private func teamName(_ id: UUID) -> String {
        dataManager.teams.first(where: { $0.id == id })?.name ?? "Team"
    }
    private var statusTint: Color {
        switch game.status {
        case .live: return .red
        case .finished: return .green
        case .scheduled: return .blue
        case .cancelled, .postponed: return .gray
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.date, format: .dateTime.month().day())
                    .font(.caption.weight(.semibold))
                Text(game.date, format: .dateTime.hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(teamName(game.homeTeamId)).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(teamName(game.awayTeamId)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(game.homeScore)–\(game.awayScore)").font(.caption.weight(.bold).monospacedDigit())
                Text(game.status.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(statusTint.opacity(0.18), in: .capsule)
                    .foregroundStyle(statusTint)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Team detail

private struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager

    private var standing: TeamStanding? {
        dataManager.teamStandings.first(where: { $0.teamId == team.id })
    }
    private var roster: [Student] {
        dataManager.students.filter { team.playerIds.contains($0.id) }
    }
    private var games: [Game] {
        dataManager.games.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let standing { standingsRow(standing) }

                SectionBlock(title: "Roster") {
                    if roster.isEmpty {
                        EmptyPanel(systemImage: "person.2", text: "No athletes assigned.")
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(roster) { student in
                                HStack(spacing: 10) {
                                    Circle().fill(Color.avatarColor(student.avatarColor))
                                        .overlay(Text(student.initials).font(.caption.weight(.bold)).foregroundStyle(.white))
                                        .frame(width: 32, height: 32)
                                    Text(student.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer()
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }

                SectionBlock(title: "Games") {
                    if games.isEmpty {
                        EmptyPanel(systemImage: "trophy", text: "No games yet.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(games) { GameSidebarRow(game: $0) }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(team.name)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color(hex: team.colorHex).gradient)
                .frame(width: 84, height: 84)
                .overlay(Text(initials).font(.system(size: 30, weight: .black)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(team.name).font(.system(size: 28, weight: .bold))
                HStack(spacing: 12) {
                    Label("\(team.playerIds.count) athletes", systemImage: "person.2")
                    if let coachId = team.coachId,
                       let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                        Label(coach.name, systemImage: "person.crop.circle")
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
            Spacer()
        }
    }

    private var initials: String {
        team.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func standingsRow(_ s: TeamStanding) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            StatPill(title: "Record", value: s.record)
            StatPill(title: "Win %", value: String(format: "%.0f%%", s.winPercentage * 100))
            StatPill(title: "PF", value: "\(s.pointsFor)")
            StatPill(title: "PA", value: "\(s.pointsAgainst)")
            StatPill(title: "Streak", value: s.streakDisplay)
        }
    }
}

// MARK: - Game detail

private struct GameDetailView: View {
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    @State private var showingScoring = false

    private var home: Team? { dataManager.teams.first(where: { $0.id == game.homeTeamId }) }
    private var away: Team? { dataManager.teams.first(where: { $0.id == game.awayTeamId }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                actionBar
                scoreboard

                if !game.quarterScores.isEmpty {
                    SectionBlock(title: "Quarter Scores") {
                        VStack(spacing: 6) {
                            ForEach(game.quarterScores, id: \.self) { qs in
                                HStack {
                                    Text("Q\(qs.quarter)").font(.caption.weight(.bold)).frame(width: 40, alignment: .leading)
                                    Text("\(qs.homeScore) – \(qs.awayScore)").font(.subheadline.weight(.semibold).monospacedDigit())
                                    Spacer()
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                if !game.scoringPlays.isEmpty {
                    SectionBlock(title: "Scoring Plays") {
                        VStack(spacing: 6) {
                            ForEach(game.scoringPlays.prefix(20), id: \.id) { play in
                                HStack(spacing: 8) {
                                    Image(systemName: "basketball").foregroundStyle(.orange)
                                    Text("\(play.points) pts").font(.caption.weight(.semibold))
                                    if let stu = dataManager.students.first(where: { $0.id == play.playerId }) {
                                        Text(stu.displayName).font(.caption)
                                    }
                                    Spacer()
                                    Text(play.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                if let notes = game.notes, !notes.isEmpty {
                    SectionBlock(title: "Notes") {
                        Text(notes).font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(matchTitle)
        .sheet(isPresented: $showingScoring) { LiveScoringSheet(game: game) }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showingScoring = true
            } label: {
                Label(game.status == .live ? "Resume Live Scoring" : "Open Live Scoring", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(game.status == .live ? .red : .accentColor)
            .disabled(game.status == .cancelled || game.status == .postponed)

            if game.status == .scheduled {
                Button {
                    var copy = game
                    copy.status = .cancelled
                    copy.updatedAt = Date()
                    dataManager.updateGame(copy)
                } label: {
                    Label("Cancel Game", systemImage: "xmark.circle")
                }
            }

            Spacer()

            Button(role: .destructive) {
                dataManager.deleteGame(game)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .controlSize(.large)
    }

    private var matchTitle: String {
        "\(home?.name ?? "Home") vs \(away?.name ?? "Away")"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(game.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }
            Text(matchTitle).font(.system(size: 28, weight: .bold))
            HStack(spacing: 12) {
                if let venue = game.venue, !venue.isEmpty {
                    Label(venue, systemImage: "mappin.and.ellipse")
                }
                if let q = game.quarterDisplay {
                    Label(q, systemImage: "timer")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
    }

    private var statusBadge: some View {
        Text(game.status.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(statusTint.opacity(0.18), in: .capsule)
            .foregroundStyle(statusTint)
    }

    private var statusTint: Color {
        switch game.status {
        case .live: return .red
        case .finished: return .green
        case .scheduled: return .blue
        case .cancelled, .postponed: return .gray
        }
    }

    private var scoreboard: some View {
        HStack {
            teamColumn(team: home, score: game.homeScore, side: "Home")
            Text("vs").font(.caption.weight(.bold)).foregroundStyle(.tertiary).padding(.horizontal, 12)
            teamColumn(team: away, score: game.awayScore, side: "Away")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func teamColumn(team: Team?, score: Int, side: String) -> some View {
        VStack(spacing: 6) {
            Circle().fill(Color(hex: team?.colorHex ?? "#666")).frame(width: 40, height: 40)
            Text(team?.name ?? side).font(.subheadline.weight(.semibold))
            Text("\(score)").font(.system(size: 48, weight: .black, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}
