import SwiftUI

// MARK: - League View (Apple Sports Inspired - Polished)
struct LeagueView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedDateFilter: DateFilter = .today
    @State private var selectedSection: LeagueSection = .games
    @State private var showingCreateTeam = false
    @State private var showingScheduleGame = false
    @State private var showingQuickRoster = false
    @State private var selectedGame: Game?
    @State private var selectedTeam: Team?
    @Namespace private var animation
    
    enum DateFilter: String, CaseIterable { case yesterday = "YTD", today = "Today", upcoming = "Next" 
        var localizedName: String {
            switch self {
            case .yesterday: return rawValue
            case .today: return rawValue
            case .upcoming: return rawValue
            }
        }
        var localizedNameChinese: String {
            switch self {
            case .yesterday: return "昨天"
            case .today: return "今天"
            case .upcoming: return "下一场"
            }
        }
    }
    enum LeagueSection: String, CaseIterable {
        case games = "Games", standings = "Standings", leaders = "Leaders", teams = "Teams"
        var icon: String {
            switch self {
            case .games: return "sportscourt.fill"
            case .standings: return "list.number"
            case .leaders: return "trophy.fill"
            case .teams: return "person.3.fill"
            }
        }
        var localizedName: String {
            switch self {
            case .games: return rawValue
            case .standings: return rawValue
            case .leaders: return rawValue
            case .teams: return rawValue
            }
        }
        var localizedNameChinese: String {
            switch self {
            case .games: return "比赛"
            case .standings: return "排名"
            case .leaders: return "数据榜"
            case .teams: return "球队"
            }
        }
    }
    
    private var filteredGames: [Game] {
        let cal = Calendar.current; let now = Date()
        switch selectedDateFilter {
        case .yesterday: return dataManager.games.filter { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: -1, to: now)!) }
        case .today: return dataManager.games.filter { cal.isDateInToday($0.date) }
        case .upcoming: return dataManager.games.filter { $0.date >= cal.date(byAdding: .day, value: 1, to: now)! }.sorted { $0.date < $1.date }
        }
    }
    private var liveGames: [Game] { dataManager.games.filter { $0.status == .live } }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#0F2027"), Color(hex: "#203A43"), Color(hex: "#2C5364").opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    headerSection
                    if !liveGames.isEmpty && selectedSection == .games && selectedDateFilter == .today { liveGamesBanner }
                    sectionPicker
                    // Date filter only shows for Games section
                    if selectedSection == .games { dateFilterPicker }
                    switch selectedSection {
                    case .games: gamesContent
                    case .standings: standingsContent
                    case .leaders: leadersContent
                    case .teams: teamsContent
                    }
                }
                .padding(.bottom, 100)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
        }
        .sheet(isPresented: $showingCreateTeam) { CreateTeamSheet(isPresented: $showingCreateTeam) }
        .sheet(isPresented: $showingScheduleGame) { ScheduleGameSheet(isPresented: $showingScheduleGame) }
        .sheet(isPresented: $showingQuickRoster) { GlassQuickRosterSheet(isPresented: $showingQuickRoster) }
        .sheet(item: $selectedGame) { game in GlassGameDetailSheet(game: game) }
        .sheet(item: $selectedTeam) { team in TeamProfileSheet(team: team) }
    }
    
    private var headerSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "联赛" : "League").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text(isChinese ? "\(dataManager.teams.count) 支球队 · \(dataManager.games.count) 场比赛" : "\(dataManager.teams.count) teams · \(dataManager.games.count) games").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            HStack(spacing: 10) {
                glassBtn(icon: "plus") { showingScheduleGame = true }
                glassBtn(icon: "person.3.fill") { showingCreateTeam = true }
                glassBtn(icon: "bolt.fill") { showingQuickRoster = true }
            }
        }
        .padding(.horizontal, 16).padding(.top, 50).padding(.bottom, 10)
    }
    
    private func glassBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                .frame(width: 36, height: 36).background(Circle().fill(.ultraThinMaterial.opacity(0.6)))
        }
    }
    
    private var dateFilterPicker: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 4) {
            ForEach(DateFilter.allCases, id: \.self) { f in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedDateFilter = f } }) {
                    Text(isChinese ? f.localizedNameChinese : f.localizedName).font(.system(size: 15, weight: selectedDateFilter == f ? .semibold : .regular, design: .rounded))
                        .foregroundColor(selectedDateFilter == f ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Group { if selectedDateFilter == f { Capsule().fill(.ultraThinMaterial).matchedGeometryEffect(id: "df", in: animation) } })
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Capsule().fill(Color.white.opacity(0.06))).padding(.horizontal, 16)
    }
    
    private var liveGamesBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) { Circle().fill(Color.red).frame(width: 5, height: 5); Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(.red) }.padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(liveGames) { g in CompactLiveCard(game: g).onTapGesture { selectedGame = g } } }.padding(.horizontal, 14)
            }
        }.padding(.vertical, 6)
    }
    
    private var sectionPicker: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(LeagueSection.allCases, id: \.self) { s in
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedSection = s } }) {
                        HStack(spacing: 5) {
                            Image(systemName: s.icon).font(.system(size: 12, weight: .semibold))
                            Text(isChinese ? s.localizedNameChinese : s.localizedName).font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(selectedSection == s ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedSection == s ? Capsule().fill(.ultraThinMaterial) : nil)
                    }
                    .buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }.padding(.vertical, 10)
    }
    
    private var gamesContent: some View {
        LazyVStack(spacing: 10) {
            if filteredGames.isEmpty { emptyState(icon: "sportscourt", title: "No Games", sub: "Tap + to schedule") }
            else { ForEach(filteredGames) { g in CompactGameCard(game: g).onTapGesture { selectedGame = g } } }
        }.padding(.horizontal, 16)
    }
    
    private var standingsContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("#").frame(width: 18, alignment: .leading); Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 26); Text("L").frame(width: 26); Text("PCT").frame(width: 40); Text("+/-").frame(width: 32)
            }.font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.4)).padding(.horizontal, 10).padding(.vertical, 4)
            let sorted = dataManager.teams.sorted { teamWins($0) > teamWins($1) }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, t in CompactStandingsRow(team: t, rank: i + 1, dataManager: dataManager) }
            if dataManager.teams.isEmpty { emptyState(icon: "list.number", title: "No Teams", sub: "Create a team") }
        }.padding(.horizontal, 14)
    }
    
    private var leadersContent: some View {
        VStack(spacing: 10) {
            CompactLeaderboard(title: "Points", icon: "flame.fill", color: .orange, leaders: topScorers)
            CompactLeaderboard(title: "Rebounds", icon: "arrow.up.arrow.down", color: .blue, leaders: topRebounders)
            CompactLeaderboard(title: "Assists", icon: "arrow.triangle.branch", color: .green, leaders: topAssisters)
        }.padding(.horizontal, 14)
    }
    
    private var teamsContent: some View {
        LazyVStack(spacing: 6) {
            if dataManager.teams.isEmpty { emptyState(icon: "person.3.fill", title: "No Teams", sub: "Create your first team") }
            else { ForEach(dataManager.teams) { t in CompactTeamCard(team: t, dataManager: dataManager).onTapGesture { selectedTeam = t } } }
        }.padding(.horizontal, 14)
    }
    
    private func emptyState(icon: String, title: String, sub: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.white.opacity(0.2))
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5))
            Text(sub).font(.system(size: 14, design: .rounded)).foregroundColor(.white.opacity(0.3))
        }.frame(maxWidth: .infinity).padding(.vertical, 50)
    }
    
    private func teamWins(_ t: Team) -> Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == t.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == t.id && $0.awayScore > $0.homeScore)) }.count }
    
    private var topScorers: [(String, String, Double)] { computeLeaders { $0.points } }
    private var topRebounders: [(String, String, Double)] { computeLeaders { $0.rebounds } }
    private var topAssisters: [(String, String, Double)] { computeLeaders { $0.assists } }
    
    private func computeLeaders(_ stat: (PlayerGameStats) -> Int) -> [(String, String, Double)] {
        var d: [UUID: (String, String, Int, Int)] = [:]
        for g in dataManager.games where g.status == .finished {
            for s in g.playerStats {
                // Fix: playerId -> Player -> studentId -> Student
                let player = dataManager.players.first { $0.id == s.playerId }
                let studentName = player.flatMap { p in dataManager.students.first { $0.id == p.studentId }?.name } ?? "?"
                let teamShortName = dataManager.teams.first { $0.id == s.teamId }?.shortName ?? ""
                if let e = d[s.playerId] { d[s.playerId] = (studentName, teamShortName, e.2 + stat(s), e.3 + 1) }
                else { d[s.playerId] = (studentName, teamShortName, stat(s), 1) }
            }
        }
        return d.values.filter { $0.3 > 0 }.map { ($0.0, $0.1, Double($0.2) / Double($0.3)) }.sorted { $0.2 > $1.2 }.prefix(5).map { $0 }
    }
}

// MARK: - Compact Game Card
struct CompactGameCard: View {
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    private var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                MiniTeamLogo(team: awayTeam, size: 36)
                Text(awayTeam?.shortName ?? "TBD").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
            }.frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 2) {
                if game.status == .live {
                    HStack(spacing: 6) {
                        Text("\(game.awayScore)").font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("-").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                        Text("\(game.homeScore)").font(.system(size: 20, weight: .bold, design: .rounded))
                    }.foregroundColor(.white)
                    HStack(spacing: 4) { Circle().fill(Color.red).frame(width: 6, height: 6); Text(game.quarterDisplay ?? "LIVE").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.red) }
                } else if game.status == .finished {
                    HStack(spacing: 6) {
                        Text("\(game.awayScore)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(game.awayScore > game.homeScore ? .white : .white.opacity(0.4))
                        Text("-").font(.system(size: 14)).foregroundColor(.white.opacity(0.3))
                        Text("\(game.homeScore)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(game.homeScore > game.awayScore ? .white : .white.opacity(0.4))
                    }
                    Text("Final").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.4))
                } else {
                    Text(game.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                    Text(game.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.4))
                }
            }.frame(width: 90)
            
            HStack(spacing: 10) {
                Text(homeTeam?.shortName ?? "TBD").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                MiniTeamLogo(team: homeTeam, size: 36)
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.5)).overlay(RoundedRectangle(cornerRadius: 14).stroke(game.status == .live ? Color.red.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)))
    }
}

// MARK: - Compact Live Card
struct CompactLiveCard: View {
    let game: Game
    @EnvironmentObject var dataManager: DataManager
    private var homeTeam: Team? { dataManager.teams.first { $0.id == game.homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == game.awayTeamId } }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(spacing: 3) { MiniTeamLogo(team: awayTeam, size: 20); Text("\(game.awayScore)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white) }
                VStack(spacing: 1) {
                    Text(game.quarterDisplay ?? "Q1").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    Text(game.timeRemaining ?? "0:00").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                }
                VStack(spacing: 3) { MiniTeamLogo(team: homeTeam, size: 20); Text("\(game.homeScore)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [(awayTeam?.primaryColor ?? .gray).opacity(0.3), (homeTeam?.primaryColor ?? .gray).opacity(0.3)], startPoint: .leading, endPoint: .trailing)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.4), lineWidth: 0.5)))
    }
}

// MARK: - Mini Team Logo
struct MiniTeamLogo: View {
    let team: Team?
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(team?.primaryColor ?? .gray)
            Text(String((team?.shortName ?? "?").prefix(1))).font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundColor(.white)
        }.frame(width: size, height: size)
    }
}

// MARK: - Compact Standings Row
struct CompactStandingsRow: View {
    let team: Team; let rank: Int; let dataManager: DataManager
    private var wins: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore)) }.count }
    private var losses: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore)) }.count }
    private var winPct: Double { let t = wins + losses; return t > 0 ? Double(wins) / Double(t) : 0 }
    private var pointDiff: Int { var d = 0; for g in dataManager.games where g.status == .finished { if g.homeTeamId == team.id { d += g.homeScore - g.awayScore } else if g.awayTeamId == team.id { d += g.awayScore - g.homeScore } }; return d }
    
    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(rank <= 3 ? .white : .white.opacity(0.4)).frame(width: 24, alignment: .leading)
            HStack(spacing: 8) { MiniTeamLogo(team: team, size: 28); Text(team.shortName).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(wins)").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white).frame(width: 32)
            Text("\(losses)").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5)).frame(width: 32)
            Text(String(format: "%.2f", winPct)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.7)).frame(width: 50)
            Text(pointDiff >= 0 ? "+\(pointDiff)" : "\(pointDiff)").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(pointDiff >= 0 ? .green : .red).frame(width: 40)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial.opacity(rank <= 3 ? 0.5 : 0.3)))
    }
}

// MARK: - Compact Leaderboard
struct CompactLeaderboard: View {
    let title: String; let icon: String; let color: Color; let leaders: [(String, String, Double)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(color); Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white); Spacer() }
            if leaders.isEmpty { Text("No data").font(.system(size: 14, design: .rounded)).foregroundColor(.white.opacity(0.3)).padding(.vertical, 10) }
            else {
                ForEach(Array(leaders.enumerated()), id: \.offset) { i, l in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(i == 0 ? color : .white.opacity(0.4)).frame(width: 20)
                        Text(l.0).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(.white).lineLimit(1)
                        Text(l.1).font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text(String(format: "%.1f", l.2)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(i == 0 ? color : .white)
                    }.padding(.vertical, 6)
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.4)))
    }
}

// MARK: - Compact Team Card
struct CompactTeamCard: View {
    let team: Team; let dataManager: DataManager
    private var wins: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore)) }.count }
    private var losses: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore)) }.count }
    
    var body: some View {
        HStack(spacing: 12) {
            MiniTeamLogo(team: team, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(team.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white).lineLimit(1)
                Text("\(team.playerIds.count) players").font(.system(size: 13, design: .rounded)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(wins)-\(losses)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text("Record").font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.4))
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.4)))
    }
}

// MARK: - Create Team Sheet (Redesigned)
struct CreateTeamSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var currentStep = 0
    @State private var teamName = ""
    @State private var shortName = ""
    @State private var selectedColorIndex = 0
    @State private var selectedPlayers: Set<UUID> = []
    @State private var selectedCoachId: UUID?
    @State private var searchText = ""
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    let colorOptions: [(color: Color, hex: String, name: String)] = [
        (.blue, "#3B82F6", "Blue"), (.red, "#EF4444", "Red"), (.green, "#22C55E", "Green"), 
        (.orange, "#F97316", "Orange"), (.purple, "#A855F7", "Purple"), (.pink, "#EC4899", "Pink"), 
        (.yellow, "#EAB308", "Gold"), (.cyan, "#06B6D4", "Cyan")
    ]
    
    private var filteredStudents: [Student] { 
        searchText.isEmpty ? dataManager.students : dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) } 
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0: return !teamName.isEmpty
        case 1: return true
        case 2: return true
        default: return true
        }
    }
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { 
                        if currentStep > 0 { withAnimation { currentStep -= 1 } }
                        else { isPresented = false }
                    }) {
                        Image(systemName: currentStep > 0 ? "chevron.left" : "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.surfaceColor))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text(isChinese ? "创建球队" : "Create Team")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        // Progress dots
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i <= currentStep ? AppTheme.accentColor : AppTheme.textTertiary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if currentStep < 2 {
                            withAnimation(.spring(response: 0.3)) { currentStep += 1 }
                        } else {
                            createTeam()
                        }
                    }) {
                        Text(currentStep == 2 ? (isChinese ? "创建" : "Create") : (isChinese ? "下一步" : "Next"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(canProceed ? .white : AppTheme.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(canProceed ? AppTheme.accentColor : AppTheme.surfaceColor))
                    }
                    .disabled(!canProceed)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Content
                TabView(selection: $currentStep) {
                    step1TeamInfo.tag(0)
                    step2SelectPlayers.tag(1)
                    step3Review.tag(2)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut, value: currentStep)
            }
        }
    }
    
    private var step1TeamInfo: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Team logo preview
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [colorOptions[selectedColorIndex].color, colorOptions[selectedColorIndex].color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 100)
                            .shadow(color: colorOptions[selectedColorIndex].color.opacity(0.4), radius: 20, x: 0, y: 10)
                        
                        Text(shortName.isEmpty ? String(teamName.prefix(3)).uppercased() : shortName.uppercased())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Text(teamName.isEmpty ? (isChinese ? "球队名称" : "Team Name") : teamName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(teamName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                }
                .padding(.top, 20)
                
                // Form fields
                VStack(spacing: 16) {
                    // Team Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "球队名称" : "TEAM NAME")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        TextField(isChinese ? "输入球队名称" : "Enter team name", text: $teamName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(14)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                    }
                    
                    // Short Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "简称 (3字母)" : "SHORT NAME (3 letters)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        TextField(isChinese ? "例如: LAK" : "e.g. LAK", text: $shortName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .textCase(.uppercase)
                            .onChange(of: shortName) { _, new in shortName = String(new.prefix(3)).uppercased() }
                            .padding(14)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                    }
                    
                    // Color Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "球队颜色" : "TEAM COLOR")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                            ForEach(0..<colorOptions.count, id: \.self) { i in
                                Button(action: { withAnimation(.spring(response: 0.2)) { selectedColorIndex = i } }) {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(colorOptions[i].color)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle().stroke(Color.white, lineWidth: selectedColorIndex == i ? 3 : 0)
                                            )
                                            .shadow(color: selectedColorIndex == i ? colorOptions[i].color.opacity(0.5) : .clear, radius: 8)
                                        
                                        Text(colorOptions[i].name)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(selectedColorIndex == i ? AppTheme.textPrimary : AppTheme.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
    }
    
    private var step2SelectPlayers: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
                TextField(isChinese ? "搜索球员..." : "Search players...", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            
            // Selected count
            HStack {
                Text(isChinese ? "已选择 \(selectedPlayers.count) 名球员" : "\(selectedPlayers.count) players selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                if !selectedPlayers.isEmpty {
                    Button(isChinese ? "清除" : "Clear") {
                        withAnimation { selectedPlayers.removeAll() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
                }
            }
            .padding(.horizontal, 20)
            
            // Player list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredStudents) { student in
                        LeaguePlayerSelectionRow(
                            student: student,
                            isSelected: selectedPlayers.contains(student.id),
                            teamColor: colorOptions[selectedColorIndex].color
                        ) {
                            withAnimation(.spring(response: 0.2)) {
                                if selectedPlayers.contains(student.id) {
                                    selectedPlayers.remove(student.id)
                                } else {
                                    selectedPlayers.insert(student.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    private var step3Review: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Team preview card
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(colorOptions[selectedColorIndex].color)
                            .frame(width: 80, height: 80)
                        Text(shortName.isEmpty ? String(teamName.prefix(3)).uppercased() : shortName.uppercased())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Text(teamName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("\(selectedPlayers.count)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(isChinese ? "球员" : "Players")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        Rectangle().fill(AppTheme.textTertiary.opacity(0.3)).frame(width: 1, height: 30)
                        
                        VStack(spacing: 4) {
                            Text("0-0")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(isChinese ? "战绩" : "Record")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [colorOptions[selectedColorIndex].color.opacity(0.3), AppTheme.cardBackground], startPoint: .top, endPoint: .bottom))
                )
                .padding(.horizontal, 20)
                
                // Roster preview
                if !selectedPlayers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "阵容" : "ROSTER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        ForEach(dataManager.students.filter { selectedPlayers.contains($0.id) }) { student in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(student.avatarColor.color))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(student.displayName.prefix(1)))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                
                                Text(student.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(AppTheme.cardBackground)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    private func createTeam() {
        let sn = shortName.isEmpty ? String(teamName.prefix(3)).uppercased() : shortName.uppercased()
        let team = Team(
            name: teamName,
            shortName: sn,
            colorHex: colorOptions[selectedColorIndex].hex,
            playerIds: Array(selectedPlayers),
            coachId: selectedCoachId
        )
        dataManager.addTeam(team)
        isPresented = false
    }
}

// MARK: - Team Player Selection Row
struct LeaguePlayerSelectionRow: View {
    let student: Student
    let isSelected: Bool
    let teamColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(student.avatarColor.color))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    if let age = student.age {
                        Text("\(age) years old")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? teamColor : AppTheme.textTertiary.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(teamColor)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? teamColor.opacity(0.15) : AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? teamColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Game Sheet (Redesigned)
struct ScheduleGameSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var gameDate = Date()
    @State private var selectedLocationId: UUID?
    @State private var customVenue = ""
    @State private var showingHomeTeamPicker = false
    @State private var showingAwayTeamPicker = false
    @State private var showingLocationPicker = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var homeTeam: Team? { dataManager.teams.first { $0.id == homeTeamId } }
    private var awayTeam: Team? { dataManager.teams.first { $0.id == awayTeamId } }
    private var selectedLocation: Location? { dataManager.locations.first { $0.id == selectedLocationId } }
    private var canSchedule: Bool { homeTeamId != nil && awayTeamId != nil && homeTeamId != awayTeamId }
    private var venueName: String? { selectedLocation?.name ?? (customVenue.isEmpty ? nil : customVenue) }
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.surfaceColor))
                    }
                    
                    Spacer()
                    
                    Text(isChinese ? "安排比赛" : "Schedule Game")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: scheduleGame) {
                        Text(isChinese ? "确认" : "Schedule")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(canSchedule ? .white : AppTheme.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(canSchedule ? AppTheme.accentColor : AppTheme.surfaceColor))
                    }
                    .disabled(!canSchedule)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Matchup visualization
                        matchupSection
                        
                        // Team selection
                        VStack(spacing: 16) {
                            // Away Team
                            TeamSelectionButton(
                                label: isChinese ? "客队" : "AWAY TEAM",
                                team: awayTeam,
                                placeholder: isChinese ? "选择客队" : "Select away team",
                                action: { showingAwayTeamPicker = true }
                            )
                            
                            // VS divider
                            HStack {
                                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                                Text("VS")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.horizontal, 12)
                                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                            }
                            
                            // Home Team
                            TeamSelectionButton(
                                label: isChinese ? "主队" : "HOME TEAM",
                                team: homeTeam,
                                placeholder: isChinese ? "选择主队" : "Select home team",
                                action: { showingHomeTeamPicker = true }
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Date & Time
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isChinese ? "日期和时间" : "DATE & TIME")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            DatePicker("", selection: $gameDate)
                                .datePickerStyle(.graphical)
                                .tint(AppTheme.accentColor)
                                .padding(12)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                        
                        // Venue
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isChinese ? "场地" : "VENUE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            if dataManager.locations.isEmpty {
                                // Fallback to text field if no locations
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(AppTheme.accentColor)
                                    TextField(isChinese ? "输入场地 (可选)" : "Enter venue (optional)", text: $customVenue)
                                        .font(.system(size: 15))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                                .padding(14)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(12)
                            } else {
                                // Location picker button
                                Button(action: { showingLocationPicker = true }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(selectedLocation != nil ? Color.orange.opacity(0.2) : AppTheme.surfaceColor)
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(selectedLocation != nil ? .orange : AppTheme.textTertiary)
                                        }
                                        
                                        if let location = selectedLocation {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(location.name)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                if let address = location.address {
                                                    Text(address)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(AppTheme.textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        } else {
                                            Text(isChinese ? "选择场地 (可选)" : "Select venue (optional)")
                                                .font(.system(size: 15))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                    .padding(14)
                                    .background(AppTheme.cardBackground)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showingHomeTeamPicker) {
            TeamPickerSheet(selectedTeamId: $homeTeamId, excludeTeamId: awayTeamId, title: isChinese ? "选择主队" : "Select Home Team")
        }
        .sheet(isPresented: $showingAwayTeamPicker) {
            TeamPickerSheet(selectedTeamId: $awayTeamId, excludeTeamId: homeTeamId, title: isChinese ? "选择客队" : "Select Away Team")
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerSheet(selectedLocationId: $selectedLocationId, title: isChinese ? "选择场地" : "Select Venue")
        }
    }
    
    private var matchupSection: some View {
        HStack(spacing: 0) {
            // Away team
            VStack(spacing: 8) {
                if let away = awayTeam {
                    Circle()
                        .fill(away.primaryColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(away.shortName.prefix(1)))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text(away.shortName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                } else {
                    Circle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "questionmark")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.textTertiary)
                        )
                    Text("???")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            
            // VS
            VStack(spacing: 4) {
                Text("VS")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(AppTheme.textTertiary)
                Text(gameDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .frame(width: 80)
            
            // Home team
            VStack(spacing: 8) {
                if let home = homeTeam {
                    Circle()
                        .fill(home.primaryColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(home.shortName.prefix(1)))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text(home.shortName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                } else {
                    Circle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "questionmark")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.textTertiary)
                        )
                    Text("???")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 24)
        .background(
            LinearGradient(
                colors: [
                    (awayTeam?.primaryColor ?? Color.gray).opacity(0.2),
                    AppTheme.cardBackground,
                    (homeTeam?.primaryColor ?? Color.gray).opacity(0.2)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
    
    private func scheduleGame() {
        guard let h = homeTeamId, let a = awayTeamId else { return }
        dataManager.addGame(Game(homeTeamId: h, awayTeamId: a, date: gameDate, venue: venueName, status: .scheduled))
        isPresented = false
    }
}

// MARK: - Location Picker Sheet
struct LocationPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedLocationId: UUID?
    let title: String
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // Option to clear selection
                        Button(action: {
                            selectedLocationId = nil
                            dismiss()
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.surfaceColor)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 18))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                
                                Text(isChinese ? "不选择场地" : "No venue")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                Spacer()
                                
                                if selectedLocationId == nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(AppTheme.accentColor)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedLocationId == nil ? AppTheme.accentColor.opacity(0.1) : AppTheme.cardBackground)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Location options
                        ForEach(dataManager.locations) { location in
                            Button(action: {
                                selectedLocationId = location.id
                                dismiss()
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange.opacity(0.2))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "building.2.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                        
                                        HStack(spacing: 8) {
                                            if let address = location.address {
                                                Text(address)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(AppTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            if location.courtCount > 0 {
                                                Text("•")
                                                    .foregroundColor(AppTheme.textTertiary)
                                                Text("\(location.courtCount) \(isChinese ? "场地" : "courts")")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(AppTheme.textTertiary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedLocationId == location.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(AppTheme.accentColor)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedLocationId == location.id ? Color.orange.opacity(0.1) : AppTheme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if dataManager.locations.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                                Text(isChinese ? "暂无场地" : "No locations")
                                    .font(.system(size: 15))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text(isChinese ? "在组织设置中添加场地" : "Add locations in Organization settings")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .padding(.vertical, 60)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Team Selection Button
struct TeamSelectionButton: View {
    let label: String
    let team: Team?
    let placeholder: String
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
            
            Button(action: action) {
                HStack(spacing: 12) {
                    if let team = team {
                        Circle()
                            .fill(team.primaryColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(team.shortName.prefix(1)))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(team.shortName)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    } else {
                        Circle()
                            .fill(AppTheme.surfaceColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            )
                        
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(14)
                .background(AppTheme.cardBackground)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Team Picker Sheet
struct TeamPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedTeamId: UUID?
    let excludeTeamId: UUID?
    let title: String
    
    private var availableTeams: [Team] {
        dataManager.teams.filter { $0.id != excludeTeamId }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(availableTeams) { team in
                            Button(action: {
                                selectedTeamId = team.id
                                dismiss()
                            }) {
                                HStack(spacing: 14) {
                                    Circle()
                                        .fill(team.primaryColor)
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Text(String(team.shortName.prefix(1)))
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(team.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Text("\(team.playerIds.count) players")
                                            .font(.system(size: 13))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedTeamId == team.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(AppTheme.accentColor)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedTeamId == team.id ? team.primaryColor.opacity(0.2) : AppTheme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if availableTeams.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                                Text("No teams available")
                                    .font(.system(size: 15))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .padding(.vertical, 60)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Glass Quick Roster Sheet
struct GlassQuickRosterSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var team1Name = "Team A"
    @State private var team2Name = "Team B"
    @State private var team1Players: Set<UUID> = []
    @State private var team2Players: Set<UUID> = []
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { isPresented = false }.font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    VStack(spacing: 1) {
                        Text("Quick 3v3").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Text("3 players each").font(.system(size: 9, design: .rounded)).foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Start") { createGame(); isPresented = false }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(team1Players.count >= 3 && team2Players.count >= 3 ? .green : .white.opacity(0.3))
                        .disabled(team1Players.count < 3 || team2Players.count < 3)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                
                HStack(spacing: 8) {
                    rosterColumn(name: $team1Name, players: $team1Players, other: team2Players, color: .blue)
                    rosterColumn(name: $team2Name, players: $team2Players, other: team1Players, color: .red)
                }.padding(12)
            }
        }
    }
    
    private func rosterColumn(name: Binding<String>, players: Binding<Set<UUID>>, other: Set<UUID>, color: Color) -> some View {
        VStack(spacing: 8) {
            TextField("Team", text: name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white).multilineTextAlignment(.center)
                .padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.3)))
            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { i in Circle().fill(i < players.wrappedValue.count ? color : Color.white.opacity(0.2)).frame(width: 6, height: 6) } }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(dataManager.students.filter { !other.contains($0.id) }) { s in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if players.wrappedValue.contains(s.id) { players.wrappedValue.remove(s.id) }
                                else if players.wrappedValue.count < 3 { players.wrappedValue.insert(s.id) }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(s.avatarColor.color)).frame(width: 20, height: 20)
                                    .overlay(Text(String(s.name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                Text(s.name).font(.system(size: 11, design: .rounded)).foregroundColor(.white).lineLimit(1)
                                Spacer()
                                if players.wrappedValue.contains(s.id) { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(color) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(players.wrappedValue.contains(s.id) ? color.opacity(0.2) : Color.white.opacity(0.05)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial.opacity(0.3)))
    }
    
    private func createGame() {
        let t1 = Team(name: team1Name, shortName: String(team1Name.prefix(3)).uppercased(), colorHex: "#3B82F6", playerIds: Array(team1Players))
        let t2 = Team(name: team2Name, shortName: String(team2Name.prefix(3)).uppercased(), colorHex: "#EF4444", playerIds: Array(team2Players))
        dataManager.addTeam(t1); dataManager.addTeam(t2)
        dataManager.addGame(Game(homeTeamId: t1.id, awayTeamId: t2.id, date: Date(), status: .scheduled))
    }
}

// MARK: - Glass Game Detail Sheet
struct GlassGameDetailSheet: View {
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
            LinearGradient(colors: [(awayTeam?.primaryColor ?? .gray).opacity(0.4), (homeTeam?.primaryColor ?? .gray).opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    Spacer()
                    if currentGame.status == .live {
                        HStack(spacing: 3) { Circle().fill(Color.red).frame(width: 5, height: 5); Text(currentGame.quarterDisplay ?? "LIVE").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white) }
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.red.opacity(0.3)))
                    }
                    Spacer()
                    Color.clear.frame(width: 24, height: 24)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 0) {
                            VStack(spacing: 6) {
                                MiniTeamLogo(team: awayTeam, size: 36)
                                Text(awayTeam?.shortName ?? "AWY").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                                Text("\(currentGame.awayScore)").font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(currentGame.status == .finished && currentGame.awayScore > currentGame.homeScore ? .white : .white.opacity(0.7))
                            }.frame(maxWidth: .infinity)
                            VStack(spacing: 2) {
                                if currentGame.status == .finished { Text("Final").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.5)) }
                                else if currentGame.status == .scheduled { Text(currentGame.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center) }
                                else { Text(currentGame.timeRemaining ?? "0:00").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white) }
                            }.frame(width: 60)
                            VStack(spacing: 6) {
                                MiniTeamLogo(team: homeTeam, size: 36)
                                Text(homeTeam?.shortName ?? "HME").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                                Text("\(currentGame.homeScore)").font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(currentGame.status == .finished && currentGame.homeScore > currentGame.awayScore ? .white : .white.opacity(0.7))
                            }.frame(maxWidth: .infinity)
                        }.padding(.vertical, 12)
                        
                        if currentGame.status == .scheduled {
                            Button(action: { var g = currentGame; g.status = .live; g.quarter = 1; g.timeRemaining = "10:00"; dataManager.updateGame(g) }) {
                                HStack(spacing: 4) { Image(systemName: "play.fill").font(.system(size: 10)); Text("Start Game").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                                    .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Color.white))
                            }.padding(.horizontal, 20)
                        }
                        
                        if currentGame.status == .live {
                            Button(action: { showingLiveScoring = true }) {
                                HStack(spacing: 4) { Image(systemName: "plus.circle.fill").font(.system(size: 10)); Text("Live Scoring").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                                    .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Color.green))
                            }.padding(.horizontal, 20)
                            
                            Button(action: { var g = currentGame; g.status = .finished; dataManager.updateGame(g) }) {
                                HStack(spacing: 4) { Image(systemName: "flag.checkered").font(.system(size: 10)); Text("End Game").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                                    .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Color.red.opacity(0.8)))
                            }.padding(.horizontal, 20)
                        }
                        
                        if !currentGame.playerStats.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Box Score").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
                                HStack(spacing: 0) {
                                    Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("PTS").frame(width: 32); Text("REB").frame(width: 32); Text("AST").frame(width: 32)
                                }.font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.4))
                                ForEach(currentGame.playerStats, id: \.playerId) { s in
                                    // Get player name: playerId -> Player -> studentId -> Student
                                    let player = dataManager.players.first { $0.id == s.playerId }
                                    let student = player.flatMap { p in dataManager.students.first { $0.id == p.studentId } }
                                    HStack(spacing: 0) {
                                        Text(student?.name ?? "Unknown").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                                        Text("\(s.points)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(s.points >= 10 ? .orange : .white).frame(width: 32)
                                        Text("\(s.rebounds)").font(.system(size: 11, design: .rounded)).foregroundColor(s.rebounds >= 5 ? .purple : .white.opacity(0.6)).frame(width: 32)
                                        Text("\(s.assists)").font(.system(size: 11, design: .rounded)).foregroundColor(s.assists >= 5 ? .cyan : .white.opacity(0.6)).frame(width: 32)
                                    }.padding(.vertical, 4)
                                }
                            }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial.opacity(0.3))).padding(.horizontal, 12)
                        }
                    }.padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showingLiveScoring) {
            LiveScoringView(game: Binding(get: { dataManager.games.first { $0.id == game.id } ?? game }, set: { dataManager.updateGame($0) }))
        }
    }
}

// MARK: - Team Profile Sheet (Comprehensive)
struct TeamProfileSheet: View {
    let team: Team
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingDeleteConfirmation = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var wins: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore > $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore > $0.homeScore)) }.count }
    private var losses: Int { dataManager.games.filter { $0.status == .finished && (($0.homeTeamId == team.id && $0.homeScore < $0.awayScore) || ($0.awayTeamId == team.id && $0.awayScore < $0.homeScore)) }.count }
    private var winPct: Double { let t = wins + losses; return t > 0 ? Double(wins) / Double(t) : 0 }
    private var pointDiff: Int { var d = 0; for g in dataManager.games where g.status == .finished { if g.homeTeamId == team.id { d += g.homeScore - g.awayScore } else if g.awayTeamId == team.id { d += g.awayScore - g.homeScore } }; return d }
    
    private var teamGames: [Game] { dataManager.games.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }.sorted { $0.date > $1.date } }
    private var teamPlayers: [Student] { dataManager.students.filter { team.playerIds.contains($0.id) } }
    private var coach: StaffCoach? { team.coachId.flatMap { id in dataManager.staffCoaches.first { $0.id == id } } }
    private var homeVenue: String? { team.homeVenue }
    
    // Player stats
    private func playerStats(_ studentId: UUID) -> (ppg: Double, rpg: Double, apg: Double, gp: Int) {
        let player = dataManager.players.first { $0.studentId == studentId }
        guard let playerId = player?.id else { return (0, 0, 0, 0) }
        
        var pts = 0, reb = 0, ast = 0, gp = 0
        for game in teamGames where game.status == .finished {
            if let stat = game.playerStats.first(where: { $0.playerId == playerId }) {
                pts += stat.points
                reb += stat.rebounds
                ast += stat.assists
                gp += 1
            }
        }
        guard gp > 0 else { return (0, 0, 0, 0) }
        return (Double(pts)/Double(gp), Double(reb)/Double(gp), Double(ast)/Double(gp), gp)
    }
    
    var body: some View {
        ZStack {
            // Background gradient with team color
            LinearGradient(colors: [team.primaryColor.opacity(0.4), AppTheme.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            AppTheme.background.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.surfaceColor))
                    }
                    Spacer()
                    Text(isChinese ? "球队资料" : "Team Profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(isChinese ? "删除球队" : "Delete Team", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.surfaceColor))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Team header card
                        teamHeaderCard
                        
                        // Stats row
                        statsRow
                        
                        // Coach & Home Venue
                        if coach != nil || homeVenue != nil {
                            teamInfoSection
                        }
                        
                        // Roster with stats
                        rosterSection
                        
                        // Recent games
                        recentGamesSection
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(isChinese ? "删除球队？" : "Delete Team?", isPresented: $showingDeleteConfirmation) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                dataManager.deleteTeam(team)
                dismiss()
            }
        } message: {
            Text(isChinese ? "确定要删除 \(team.name) 吗？这将同时删除所有相关比赛和数据。此操作无法撤销。" : "Are you sure you want to delete \(team.name)? This will also remove all associated games and stats. This action cannot be undone.")
        }
    }
    
    private var teamHeaderCard: some View {
        VStack(spacing: 16) {
            // Team logo
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [team.primaryColor, team.primaryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .shadow(color: team.primaryColor.opacity(0.5), radius: 20, x: 0, y: 10)
                
                Text(team.shortName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Team name
            Text(team.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            
            // Record
            HStack(spacing: 8) {
                Text("\(wins)-\(losses)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(String(format: "%.1f%%", winPct * 100))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.surfaceColor))
            }
            
            Text(isChinese ? "赛季战绩" : "Season Record")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.vertical, 24)
    }
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            statBox(isChinese ? "胜" : "W", "\(wins)", .green)
            statBox(isChinese ? "负" : "L", "\(losses)", .red)
            statBox(isChinese ? "胜率" : "PCT", String(format: "%.2f", winPct), .blue)
            statBox("+/-", pointDiff >= 0 ? "+\(pointDiff)" : "\(pointDiff)", pointDiff >= 0 ? .green : .red)
        }
    }
    
    private func statBox(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private var teamInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "球队信息" : "TEAM INFO")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 10) {
                // Coach
                if let coach = coach {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.accentColor.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "主教练" : "Head Coach")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                            Text(coach.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
                
                // Home Venue
                if let venue = homeVenue, !venue.isEmpty {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "主场" : "Home Venue")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                            Text(venue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isChinese ? "阵容" : "ROSTER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(teamPlayers.count) \(isChinese ? "名球员" : "players")")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if teamPlayers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                    Text(isChinese ? "暂无球员" : "No players")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text(isChinese ? "球员" : "Player").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PPG").frame(width: 40)
                        Text("RPG").frame(width: 40)
                        Text("APG").frame(width: 40)
                        Text("GP").frame(width: 30)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    Divider().background(AppTheme.textTertiary.opacity(0.3))
                    
                    // Player rows
                    ForEach(teamPlayers) { player in
                        let stats = playerStats(player.id)
                        HStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(player.avatarColor.color))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(String(player.name.prefix(1)))
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(player.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    if let age = player.age {
                                        Text("\(age) \(isChinese ? "岁" : "yrs")")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(String(format: "%.1f", stats.ppg))
                                .font(.system(size: 12, weight: stats.ppg >= 10 ? .bold : .regular))
                                .foregroundColor(stats.ppg >= 10 ? .orange : AppTheme.textSecondary)
                                .frame(width: 40)
                            
                            Text(String(format: "%.1f", stats.rpg))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 40)
                            
                            Text(String(format: "%.1f", stats.apg))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 40)
                            
                            Text("\(stats.gp)")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 30)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        
                        if player.id != teamPlayers.last?.id {
                            Divider().background(AppTheme.textTertiary.opacity(0.2)).padding(.leading, 54)
                        }
                    }
                }
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
            }
        }
    }
    
    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "近期比赛" : "RECENT GAMES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
            
            if teamGames.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                    Text(isChinese ? "暂无比赛" : "No games")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
            } else {
                VStack(spacing: 8) {
                    ForEach(teamGames.prefix(5)) { game in
                        gameRow(game)
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
        let oppScore = isHome ? game.awayScore : game.homeScore
        let won = teamScore > oppScore
        
        return HStack(spacing: 12) {
            // Result indicator
            if game.status == .finished {
                Text(won ? "W" : "L")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(won ? .green : .red)
                    .frame(width: 24, height: 24)
                    .background((won ? Color.green : Color.red).opacity(0.2))
                    .cornerRadius(6)
            } else if game.status == .live {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(width: 24, height: 24)
            }
            
            // Opponent
            HStack(spacing: 8) {
                if let opp = opponent {
                    Circle()
                        .fill(opp.primaryColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(opp.shortName.prefix(1)))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(isHome ? "vs" : "@") \(opponent?.shortName ?? "TBD")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(game.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            // Score
            if game.status == .finished || game.status == .live {
                Text("\(teamScore) - \(oppScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            } else {
                Text(game.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Shared Helpers
private func sheetHeader(title: String, cancel: @escaping () -> Void, confirm: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    HStack {
        Button("Cancel", action: cancel).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7))
        Spacer()
        Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
        Spacer()
        Button(confirm, action: action).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(enabled ? .green : .white.opacity(0.3)).disabled(!enabled)
    }.padding(.horizontal, 12).padding(.vertical, 10)
}

private func glassSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6))
        content()
    }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial.opacity(0.4)))
}

private func glassTextField(placeholder: String, text: Binding<String>, icon: String? = nil) -> some View {
    HStack(spacing: 6) {
        if let icon = icon { Image(systemName: icon).font(.system(size: 10)).foregroundColor(.white.opacity(0.4)) }
        TextField(placeholder, text: text).font(.system(size: 12, design: .rounded)).foregroundColor(.white)
    }.padding(.horizontal, 10).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
}

private func playerRow(student: Student, selected: Bool, action: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Circle().fill(Color(student.avatarColor.color)).frame(width: 24, height: 24)
            .overlay(Text(String(student.name.prefix(1))).font(.system(size: 10, weight: .bold)).foregroundColor(.white))
        Text(student.name).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.white)
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).foregroundColor(selected ? .green : .white.opacity(0.3))
    }
    .padding(.vertical, 6).contentShape(Rectangle()).onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { action() } }
}

private func teamPicker(label: String, selection: Binding<UUID?>, excluding: UUID?, teams: [Team]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.5))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(teams.filter { $0.id != excluding }) { t in
                    Button(action: { selection.wrappedValue = t.id }) {
                        HStack(spacing: 4) { MiniTeamLogo(team: t, size: 18); Text(t.shortName).font(.system(size: 10, weight: .semibold, design: .rounded)) }
                            .foregroundColor(selection.wrappedValue == t.id ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(selection.wrappedValue == t.id ? t.primaryColor.opacity(0.6) : Color.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - TeamLogo Alias
typealias TeamLogo = MiniTeamLogo

#Preview {
    LeagueView().environmentObject(DataManager.shared)
}
