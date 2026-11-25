import SwiftUI
import Combine
import os
import UIKit
import AudioToolbox

// The session page's GAMES tab. Moved out of FlightySessionPageView.swift
// (25 Nov 2026, clean-up: that file held the whole session page, 7,900 lines).
// Behaviour unchanged.

struct SessionGamesTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Binding var session: SessionEvent
    let enrolledStudents: [Student]
    let programColor: Color
    let onSave: () -> Void
    /// Organization coaches playing in this scrimmage / game prep: on game
    /// teams like anyone, left out of every stat and insight.
    var guestPlayers: [Student] = []

    /// Everyone who can be put on a team or scored.
    private var players: [Student] { enrolledStudents + guestPlayers }
    
    @State private var showingCreateGame = false
    @State private var selectedGame: SessionGame?
    @State private var selectedRecapGame: SessionGame?

    /// Every played game of this session's program so far (just this
    /// session's when it has no program) — GameStatsReport.
    private var statsSessions: [SessionEvent] {
        let all = session.programId.map { pid in
            dataManager.sessionEvents.filter { $0.programId == pid && $0.id != session.id } + [session]
        } ?? [session]
        // Coaches who played are not athletes: their lines leave the stats.
        let coachIds = Set(dataManager.staffCoaches.map(\.id))
        return all.map { GameStatsReport.withoutPlayers(coachIds, in: $0) }
    }

    private var gameStats: GameStatsReport.Report {
        GameStatsReport.make(sessions: statsSessions, roster: enrolledStudents.map(\.id), current: session,
                             excluding: Set(dataManager.staffCoaches.map(\.id)))
    }

    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    @State private var gameToDelete: SessionGame?
    /// The tab's own width; 1000 until measured so an iPad's first draw is the wide one.
    @State private var tabWidth: CGFloat = 1000
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            // The record of games and, beside it on iPad / Mac (under it on
            // the phone), the dashboard of how they were played (14 Nov 2026).
            // By the tab's OWN width: in the Mac's class workspace the tab
            // shares the window with the roster and the sidebar, and at
            // ~400 pt the dashboard's tiles broke their words letter by letter.
            if horizontalSizeClass == .regular && tabWidth >= 620 {
                HStack(alignment: .top, spacing: 20) {
                    gamesColumn
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 480)
                    analysisColumn
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            } else {
                VStack(spacing: 24) {
                    gamesColumn
                    analysisColumn
                        .padding(.horizontal, 16)
                    Spacer(minLength: 76)
                }
                .padding(.top, 8)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabWidth = $0 }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除比赛" : "Delete Game", isPresented: Binding(
            get: { gameToDelete != nil },
            set: { if !$0 { gameToDelete = nil } }
        )) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) {
                gameToDelete = nil
            }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) {
                if let game = gameToDelete {
                    deleteGame(game)
                }
            }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "确定要删除这场比赛吗？" : "Are you sure you want to delete this game?")
        }
        .fullScreenCover(isPresented: $showingCreateGame) {
            CreateGameSheet(session: $session, enrolledStudents: players, programColor: programColor, onSave: onSave)
        }
        .fullScreenCover(item: $selectedGame) { game in
            if let index = session.games.firstIndex(where: { $0.id == game.id }) {
                LiveGameScoringView(
                    // Custom binding: local mutation for UI, then a
                    // field-level write that updates ONLY this one game's
                    // entry — siblings (other games, photo, attendance)
                    // stay intact even if our local snapshot is stale.
                    game: Binding(
                        get: { session.games[index] },
                        set: { updated in
                            session.games[index] = updated
                            dataManager.updateSessionGame(inSessionId: session.id, game: updated)
                        }
                    ),
                    students: players,
                    allGamesInSession: session.games,
                    // The Save button on the scoring screen used to do a
                    // whole-session overwrite. The binding above already
                    // persists per change, so this is a no-op stub —
                    // safer than a stale full-session write.
                    onSave: {},
                    onSaveCompletedRound: { completedRound in
                        session.games.append(completedRound)
                        dataManager.appendSessionGame(toSessionId: session.id, game: completedRound)
                    },
                    onNextGame: { next in
                        session.games.append(next)
                        dataManager.appendSessionGame(toSessionId: session.id, game: next)
                        selectedGame = next
                    },
                    plannedSubs: isTeamGame ? (session.curriculum.gamePlan ?? GamePlan())
                        .validSubs(roster: AttendanceMath.expectedIds(of: session, programs: dataManager.programs)) : [],
                    period: index + 1
                )
            }
        }
        .fullScreenCover(item: $selectedRecapGame) { game in
            GameRecapView(game: game, students: players, allGamesInSession: session.games)
        }

    }
    
    private var gamesColumn: some View {
        VStack(spacing: 0) {
            gamesHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if session.games.isEmpty {
                emptyGamesState
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(session.games.enumerated()), id: \.element.id) { index, game in
                        if horizontalSizeClass == .regular { wideGameRow(game) } else { gameRow(game) }
                        if index < session.games.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .filmGlass(.regular, in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    /// The dashboard, then at most three things worth acting on from the
    /// program's games so far (October 2026, Luther: limited, smart).
    @ViewBuilder
    private var analysisColumn: some View {
        let report = gameStats
        let insights = GameStatsReport.insights(report: report, sessions: statsSessions,
                                                roster: enrolledStudents.map(\.id))
        let played = statsSessions.contains { $0.games.contains(where: GameStatsReport.played) }
        VStack(alignment: .leading, spacing: 24) {
            if played {
                GameDashboardView(programSessions: statsSessions, session: session,
                                  roster: enrolledStudents.map(\.id), students: dataManager.students,
                                  excluding: Set(dataManager.staffCoaches.map(\.id)))
            }
            if !insights.isEmpty {
                GameInsightsView(insights: insights, games: report.games, sessions: report.sessions,
                                 students: dataManager.students)
            }
        }
    }

    private var gamesHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isTeamGame ? (isChinese ? "比赛 · 各节" : "THE GAME · PERIODS") : (isChinese ? "比赛" : "SCRIMMAGE GAMES"))
                    .font(.caption.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
                Text("^[\(session.games.count) game](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText(value: Double(session.games.count)))
            }
            Spacer()
            Button {
                newGameTapped()
            } label: {
                Label(isTeamGame ? (session.games.isEmpty ? (isChinese ? "开始比赛" : "Start the game") : (isChinese ? "下一节" : "Next period"))
                                 : (isChinese ? "新比赛" : "New Game"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.accentColor)
            .sensoryFeedback(.selection, trigger: showingCreateGame)
        }
    }
    
    /// "Why play games?" — one coaching tip, unattributed (17 Nov 2026,
    /// before App Store submission: the card used to credit quotes to real
    /// players and coaches that could not be sourced).
    private var emptyGamesState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let tips: [String] = isChinese ? [
            "孩子们通过打比赛学得最快：竞争、应对压力、与队友沟通，这些是技术练习教不会的。",
            "多比赛、少说教。比赛本身就是最好的老师。",
            "让比赛成为老师。在有意义的比赛情境中，孩子们学得更快。",
            "训练中学到的东西，只有放进比赛里才真正有意义。",
            "允许孩子犯错。比赛中的错误是最好的学习机会。",
            "篮球智商是在比赛中打出来的，不是在训练中讲出来的。",
            "孩子们需要感受比赛的节奏，任何练习都无法完全模拟。",
            "让比赛保持有趣——孩子们在玩乐中学得最快。",
            "真正的判断力只能在真实的比赛压力下培养。",
            "让孩子在比赛中自己解决问题，而不是直接告诉他们答案。",
            "比赛给孩子最真实的反馈。",
            "3对3、4对4、5对5，让每个孩子都有更多触球和决策的机会。",
        ] : [
            "Kids learn fastest by playing games: competing, handling pressure and talking to teammates are things drills can't teach.",
            "Coach less, play more. The game itself is the best teacher.",
            "Let the game be the teacher. Kids learn faster in game situations that mean something.",
            "What kids learn in drills only makes sense once they use it in a game.",
            "Let kids make mistakes. Mistakes in games are the best learning moments.",
            "Basketball IQ is built by playing, not explained in practice.",
            "Kids need to feel the rhythm of a game. No drill quite recreates it.",
            "Keep games fun — kids learn fastest when they're enjoying it.",
            "Real decision-making only grows under real game pressure.",
            "Let kids solve problems in games instead of handing them the answers.",
            "Games give kids the most honest feedback there is.",
            "Small-sided games — 3v3, 4v4 — give every child more touches and more decisions.",
        ]
        let tip = tips[Int.random(in: 0..<tips.count)]

        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "为什么要打比赛？" : "Why Play Games?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            Text(tip)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filmGlass(.regular, in: .rect(cornerRadius: 16))
    }

    private func quickStartGameButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: A team's game against an opponent (23 Nov 2026 — GamePlan.swift)

    private var isTeamGame: Bool { session.sessionType == .game && session.curriculum.teamId != nil }

    /// New Game: a team's game starts its next PERIOD against the opponent;
    /// everything else opens the setup page.
    private func newGameTapped() {
        if isTeamGame { startTeamGamePeriod() } else { showingCreateGame = true }
    }

    /// Our team (the plan's starters first, then the bench) against the
    /// opponent, who has no players — its score is typed on the live screen.
    private func startTeamGamePeriod() {
        guard let team = session.curriculum.teamId.flatMap({ id in dataManager.teams.first { $0.id == id } }) else {
            showingCreateGame = true
            return
        }
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let present = enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }
        let pool = (present.isEmpty ? enrolledStudents : present).map(\.id)
        let teams = GameDay.teams(team: team, plan: session.curriculum.gamePlan ?? GamePlan(), pool: pool, chinese: isChinese)
        var newGame = SessionGame(
            sessionId: session.id,
            gameNumber: (session.games.map { $0.gameNumber }.max() ?? 0) + 1,
            gameType: .twoTeam,
            teams: teams,
            durationMinutes: 10,
            basketValue: 2,
            status: .ready)
        newGame.playersPerSide = teams.first?.starters
        // Planned subs made or skipped in earlier periods are not asked again.
        let done = session.games.flatMap { $0.plannedSubsDone ?? [] }
        if !done.isEmpty { newGame.plannedSubsDone = Array(Set(done)) }
        session.games.append(newGame)
        dataManager.appendSessionGame(toSessionId: session.id, game: newGame)
        selectedGame = newGame
    }

    private func createStarterGame(type: SessionGameType) {
        if isTeamGame { startTeamGamePeriod(); return }
        let availableStudents = enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }
        // Coaches on a scrimmage are always in the pool (they take no roll call).
        let playerPool = (availableStudents.isEmpty ? enrolledStudents : availableStudents) + guestPlayers

        guard playerPool.count >= 2 else {
            showingCreateGame = true
            return
        }

        let gameNumber = (session.games.map { $0.gameNumber }.max() ?? 0) + 1
        let teamCount = max(type.requiredTeams, 2)
        var teams: [GameTeam] = []

        if !type.isIndividual {
            for index in 0..<teamCount {
                let preset = GameTeam.presetColors[index]
                teams.append(GameTeam(name: preset.name, colorHex: preset.hex))
            }

            for (index, student) in playerPool.enumerated() {
                teams[index % teamCount].playerIds.append(student.id)
            }
        }

        var newGame = SessionGame(
            sessionId: session.id,
            gameNumber: gameNumber,
            gameType: type,
            teams: teams,
            durationMinutes: 10,
            basketValue: UserDefaults.standard.object(forKey: SessionGame.basketValueDefaultsKey) as? Int ?? 2,
            status: .ready
        )

        if type.isIndividual {
            newGame.playerStats = playerPool.map {
                SessionPlayerStats(playerId: $0.id, gameId: newGame.id, teamId: newGame.id)
            }
        }

        // Optimistic local update for snappy UI, then a field-level write
        // through SwiftDataManager. The field-level helper reads the current
        // SDSessionEvent from the model context and only mutates `games`, so
        // a stale `@State session` on this view (or any sibling view) can
        // no longer wipe sibling fields like `attendancePhotoPath`.
        session.games.append(newGame)
        dataManager.appendSessionGame(toSessionId: session.id, game: newGame)
        selectedGame = newGame
    }

    private func deleteGame(_ game: SessionGame) {
        session.games.removeAll { $0.id == game.id }
        dataManager.deleteSessionGame(inSessionId: session.id, gameId: game.id)
    }

    
    private func gameRow(_ game: SessionGame) -> some View {
        HStack(spacing: 12) {
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Game \(game.gameNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    statusBadge(game.status)
                }

                HStack(spacing: 6) {
                    Image(systemName: game.gameType.icon)
                        .font(.caption2)
                    Text(game.gameType.displayName)
                        .font(.caption.weight(.medium))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(game.durationMinutes) min")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Compact team scores
            if !game.teams.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(game.activeTeams.enumerated()), id: \.element.id) { index, team in
                        compactTeamScore(team: team, score: game.score(for: team.id))
                        if index < game.activeTeams.count - 1 {
                            Text("–")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Action button
            Button {
                if game.status == .completed {
                    selectedRecapGame = game
                } else {
                    selectedGame = game
                }
            } label: {
                Image(systemName: game.status == .completed ? "chart.bar.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .controlSize(.small)
            .tint(game.status == .completed ? .green : Color.accentColor)
            .sensoryFeedback(.selection, trigger: selectedGame?.id)

            // Delete button
            Button(role: .destructive) {
                gameToDelete = game
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if game.status == .completed {
                selectedRecapGame = game
            } else {
                selectedGame = game
            }
        }
    }

    private func openGame(_ game: SessionGame) {
        if game.status == .completed { selectedRecapGame = game } else { selectedGame = game }
    }

    /// iPad / Mac (14 Nov 2026, Luther: "Game 1 and completed, a bit
    /// awkward" — in the narrower games column the old row broke its words
    /// letter by letter). One line each side: the game and how it is played;
    /// the score with the winner bright; a ⋯ menu instead of two buttons.
    private func wideGameRow(_ game: SessionGame) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let teams = game.activeTeams.isEmpty ? game.teams : game.activeTeams
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(isChinese ? "第\(game.gameNumber)场" : "Game \(game.gameNumber)")
                        .font(.headline)
                    if game.status == .completed {
                        Text(isChinese ? "终场" : "FINAL")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    } else {
                        statusBadge(game.status)
                    }
                }
                .lineLimit(1)
                Label {
                    Text("\(game.gameType.displayName) · \(game.durationMinutes) min")
                } icon: {
                    Image(systemName: game.gameType.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 8)

            if teams.count == 2 {
                let a = game.score(for: teams[0].id), b = game.score(for: teams[1].id)
                HStack(spacing: 8) {
                    wideScore(teams[0], a, bright: a >= b || game.status != .completed, dotFirst: true)
                    Text("–").font(.subheadline).foregroundStyle(.tertiary)
                    wideScore(teams[1], b, bright: b >= a || game.status != .completed, dotFirst: false)
                }
                .fixedSize()
            } else if let leader = game.individualLeaderboard.first {
                Text("\(leader.points)")
                    .font(.title3.weight(.bold).monospacedDigit())
            }

            Menu {
                Button {
                    openGame(game)
                } label: {
                    Label(game.status == .completed ? (isChinese ? "比赛回顾" : "Game Recap") : (isChinese ? "继续记分" : "Keep Scoring"),
                          systemImage: game.status == .completed ? "chart.bar.fill" : "play.fill")
                }
                Button(role: .destructive) {
                    gameToDelete = game
                } label: {
                    Label(isChinese ? "删除比赛" : "Delete Game", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("games.row.menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { openGame(game) }
        .accessibilityIdentifier("games.row")
    }

    private func wideScore(_ team: GameTeam, _ score: Int, bright: Bool, dotFirst: Bool) -> some View {
        let dot = Circle()
            .fill(Color(hex: team.colorHex))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
            .frame(width: 12, height: 12)
        let number = Text("\(score)")
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(bright ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentTransition(.numericText(value: Double(score)))
        return HStack(spacing: 6) {
            if dotFirst { dot; number } else { number; dot }
        }
    }

    private func compactTeamScore(team: GameTeam, score: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: team.colorHex))
                .frame(width: 14, height: 14)
                .overlay(
                    Text(String(team.name.prefix(1)))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("\(score)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(team.displayColor(for: colorScheme))
                .contentTransition(.numericText(value: Double(score)))
        }
    }

    private func statusBadge(_ status: SessionGameStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .inProgress)
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
                // Never "Re…" (19 Nov 2026, Luther, iPad): the word keeps its width.
                .fixedSize()
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .fixedSize()
        .filmGlass(.regular, in: Capsule())
    }

    private func statusColor(_ status: SessionGameStatus) -> Color {
        switch status {
        case .setup: return .secondary
        case .ready: return Color.accentColor
        case .inProgress: return .red
        case .paused: return .secondary
        case .completed: return .green
        }
    }
}
