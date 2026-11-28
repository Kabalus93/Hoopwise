import SwiftUI
import Combine
import os
import UIKit
import AudioToolbox

// The LIVE GAME screen (scoreboard, clock, entry, Next Game) and the
// "who plays next?" chooser. Moved out of FlightySessionPageView.swift
// (25 Nov 2026, clean-up). Behaviour unchanged.

struct LiveGameScoringView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var game: SessionGame
    let students: [Student]
    let allGamesInSession: [SessionGame]
    let onSave: () -> Void
    var onSaveCompletedRound: ((SessionGame) -> Void)? = nil  // Callback to save completed round as new game
    /// NEXT GAME (20 Nov 2026, Luther): the current game is finished and
    /// saved, this new one (same teams; the chosen ones on court) is added
    /// to the session and opened in its place.
    var onNextGame: ((SessionGame) -> Void)? = nil
    /// A team's game: its planned subs and which period this is — the
    /// panel of the team they belong to prompts them.
    var plannedSubs: [PlannedSub] = []
    var period: Int = 1
    /// The teams preselected when the "who plays next?" sheet opens (nil = closed).
    @AppStorage(GameTeamBackdrop.key) private var teamBackdrop = true
    @State private var nextPick: NextPick?
    struct NextPick: Identifiable { let id = UUID(); let teams: Set<UUID> }
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning = false
    @State private var selectedTeamIndex: Int = 0
    @State private var headerCollapsed = false
    @State private var showingRecap = false
    /// Value of the next basket scored by tapping a row; back to the game's
    /// standard value (setup page) after each basket.
    @State private var basketValue = 2
    /// Every stat logged on this screen, newest last — what Undo reverses.
    @State private var actionLog: [GameStatAction] = []
    @State private var undoTick = 0
    /// Set the moment the countdown reaches 0 so we don't fire the alarm
    /// every tick afterward. Reset by `resetTimer()` and on round transitions.
    @State private var hasFiredAlarm = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Countdown helpers

    /// Total seconds the game is configured to run.
    private var totalSeconds: Int { game.durationMinutes * 60 }

    /// Seconds left on the clock. Goes negative once we're in overtime;
    /// the game does not auto-end at zero — the coach decides.
    private var remainingSeconds: Int { totalSeconds - timerSeconds }

    /// Display string. Counts down to 00:00, then keeps going as "OT MM:SS"
    /// so coaches can see how much extra they're letting it run.
    private var formattedClock: String {
        if remainingSeconds >= 0 {
            return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
        }
        let over = -remainingSeconds
        return String(format: "OT %02d:%02d", over / 60, over % 60)
    }

    /// True once we've crossed zero — drives the red-flash colour and the
    /// reset of the alarm guard.
    private var isExpired: Bool { timerSeconds >= totalSeconds }

    /// Has the clock entered the warning window (last 30s)? Used for tint.
    private var isWarningWindow: Bool {
        remainingSeconds > 0 && remainingSeconds <= 30
    }

    private var clockTint: Color {
        if isExpired { return .red }
        if isWarningWindow { return .orange }
        return .primary
    }
    
    private var isBattleRoyal: Bool { game.gameType.isIndividual }
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isBattleRoyal {
                    battleRoyalCompactHeader
                    battleRoyalPlayersList
                } else if isIPad && activeTeamsForScoring.count == 2 {
                    // iPad / Mac: the same entry as the phone, both teams
                    // side by side (November 2026 — the old two-column
                    // screen with per-player +1/+2/+3 buttons is retired).
                    liveScoreboard
                    liveEntryWide
                } else {
                    // iPhone: one team at a time, all its players on screen
                    // (October 2026 field redesign — see LiveTeamPanel).
                    liveScoreboard
                    liveEntry
                }
            }
            .filmRoomPage()
            .navigationTitle(isBattleRoyal ? (isChinese ? "大乱斗 \(game.gameNumber)" : "Battle Royal \(game.gameNumber)") : "Game \(game.gameNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { onSave(); dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !isBattleRoyal && onNextGame != nil {
                        Button(action: nextGameTapped) {
                            Label(isChinese ? "下一场" : "Next Game", systemImage: "forward.end.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Color.accentColor)
                        .accessibilityIdentifier("live.nextGame")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if game.status != .completed {
                        Button(role: .destructive, action: endGame) {
                            Text(isChinese ? "结束" : "End Game")
                        }
                    }
                }
                if !isBattleRoyal {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Toggle(isOn: $teamBackdrop) {
                                Label(isChinese ? "照片背景用队伍颜色" : "Team colour behind photos",
                                      systemImage: "paintpalette")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("live.more")
                    }
                }
            }
            .onReceive(timer) { _ in
                guard isTimerRunning && game.status == .inProgress else { return }
                timerSeconds += 1
                // First tick that crosses the duration: ring + vibrate but
                // keep ticking. Coach manually ends the game from the toolbar.
                if !hasFiredAlarm && isExpired {
                    fireExpirationAlarm()
                    hasFiredAlarm = true
                }
            }
            .onAppear {
                if game.status == .inProgress, let startedAt = game.startedAt {
                    timerSeconds = Int(Date().timeIntervalSince(startedAt))
                    // If the app was backgrounded past expiration, don't
                    // ring the alarm now — only ring on a live transition.
                    if isExpired { hasFiredAlarm = true }
                }
            }
            .sheet(isPresented: $showingRecap) {
                GameRecapView(game: game, students: students, allGamesInSession: allGamesInSession)
            }
            // A sheet, not a popover on the toolbar button: a toolbar
            // popover kept a stale copy of the choice (nothing ticked).
            .sheet(item: $nextPick) { pick in
                NextTeamsChooser(game: game, required: teamsOnCourtCount, initial: pick.teams,
                                 gameNumber: allGamesInSession.count + 1) { chosen in
                    nextPick = nil
                    startNextGame(onCourt: game.teams.map(\.id).filter { chosen.contains($0) })
                }
                .presentationDetents([.height(CGFloat(200 + 50 * game.teams.count))])
            }
        }
    }
    
    // MARK: - Battle Royal Header
    private var battleRoyalHeader: some View {
        VStack(spacing: 16) {
            // Timer
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerSeconds >= game.durationMinutes * 60 ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .contentTransition(.numericText())
                Text("/ \(game.durationMinutes):00")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Timer controls
            if game.status != .completed {
                HStack(spacing: 12) {
                    Button(action: toggleTimer) {
                        Label(
                            isTimerRunning ? (isChinese ? "暂停" : "Pause")
                                            : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume")),
                            systemImage: isTimerRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .tint(isTimerRunning ? .red : .green)
                    .sensoryFeedback(.impact, trigger: isTimerRunning)

                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(.secondary)
                }
            }

            // Crown + title
            Label {
                Text(isChinese ? "个人排名" : "Leaderboard")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 8)
            
            // Top 3 preview
            let leaderboard = game.individualLeaderboard
            if !leaderboard.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(leaderboard.prefix(3).enumerated()), id: \.element.playerId) { index, entry in
                        if let student = students.first(where: { $0.id == entry.playerId }) {
                            VStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    StudentAvatarView(student: student, size: 50)
                                    if index == 0 {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.yellow)
                                            .offset(y: -10)
                                    }
                                }
                                Text("\(entry.points)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? .orange : (index == 1 ? .gray : .brown))
                                Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }.padding(24).background(Color.filmCard)
    }
    
    // MARK: - Battle Royal Compact Header
    private var battleRoyalCompactHeader: some View {
        VStack(spacing: 8) {
            // Timer and controls in one row
            HStack(spacing: 12) {
                // Countdown clock
                Text(formattedClock)
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                    .symbolEffect(.pulse, options: .repeating, isActive: isExpired && isTimerRunning)
                Text("/ \(game.durationMinutes):00")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                // Timer controls
                if game.status != .completed {
                    bigPlayPauseButton
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(Color.gray.opacity(0.12), in: Circle())
                    }
                }
            }
            
            // Top 3 leaderboard compact
            let leaderboard = game.individualLeaderboard
            if !leaderboard.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(leaderboard.prefix(3).enumerated()), id: \.element.playerId) { index, entry in
                        if let student = students.first(where: { $0.id == entry.playerId }) {
                            HStack(spacing: 6) {
                                if index == 0 {
                                    Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.orange)
                                }
                                Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text("\(entry.points)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? .orange : (index == 1 ? .gray : .brown))
                            }
                        }
                    }
                    Spacer()
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(Color.filmCard)
    }
    
    // MARK: - Compact Game Header (smaller to show more players)
    private var compactGameHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(formattedClock)
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                    .symbolEffect(.pulse, options: .repeating, isActive: isExpired && isTimerRunning)
                Text(String(format: "/ %d:00", game.durationMinutes))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                if game.status != .completed {
                    bigPlayPauseButton
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(.secondary)
                }
            }

            // Team scores
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 24, height: 24)
                            .overlay(
                                Text(String(team.name.prefix(1)))
                                    .font(.caption2.bold())
                                    .foregroundStyle(team.colorHex == "#F5F5F5" ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
                            )
                        Text("\(game.score(for: team.id))")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: team.colorHex))
                            .contentTransition(.numericText(value: Double(game.score(for: team.id))))
                    }
                    .frame(maxWidth: .infinity)
                    if index < teamsOnCourt.count - 1 {
                        Text("vs")
                            .font(.subheadline.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Waiting teams
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "候场" : "Next")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                            Text(GameTeam.localizedColorName(team.name))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .filmGlass(.regular, in: Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.filmMaterial)
    }
    
    private var gameHeader: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60)).font(.system(size: 48, weight: .bold, design: .monospaced)).foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if game.status != .completed {
                HStack(spacing: 16) {
                    Button(action: toggleTimer) {
                        HStack(spacing: 6) { Image(systemName: isTimerRunning ? "pause.fill" : "play.fill"); Text(isTimerRunning ? (isChinese ? "暂停" : "Pause") : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume"))) }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary).padding(10).background(Color.gray.opacity(0.1)).cornerRadius(20) }
                }
            }
            // Only show active teams on court
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    VStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 40, height: 40).overlay(Text(String(team.name.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                        Text("\(game.score(for: team.id))").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundColor(Color(hex: team.colorHex))
                        Text(GameTeam.localizedColorName(team.name)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        if game.teams.count > 2 {
                            Text("\(team.wins)W-\(team.losses)L").font(.system(size: 10, weight: .medium)).foregroundColor(.gray.opacity(0.7))
                        }
                    }.frame(maxWidth: .infinity)
                    if index < teamsOnCourt.count - 1 { Text("vs").font(.system(size: 20, weight: .bold)).foregroundColor(.gray.opacity(0.4)) }
                }
            }
            // Show waiting teams if more than 2 teams total
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 8) {
                    Text(isChinese ? "候场" : "NEXT UP").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.gray.opacity(0.6))
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 16, height: 16)
                            Text(team.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Text("\(team.wins)W").font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
                        }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.1)).cornerRadius(12)
                    }
                }.padding(.top, 8)
            }
        }.padding(24).background(Color.filmCard)
    }
    
    // MARK: - Live entry (iPhone)

    /// Clock + the two scores. The scores ARE the team switcher: tap the
    /// other team and its players slide in.
    private var liveScoreboard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(formattedClock)
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                Spacer()
                if game.status != .completed {
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).tint(.secondary)
                    Button(action: toggleTimer) {
                        Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(isTimerRunning ? Color.orange : Color.green))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isTimerRunning ? "Pause timer" : "Start timer")
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                    teamScoreSwitch(team: team, index: index)
                }
            }
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "候场" : "Next").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
                            Text(GameTeam.localizedColorName(team.name)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.filmMaterial)
        .sensoryFeedback(.selection, trigger: selectedTeamIndex)
    }

    /// WHO IS UP (19 Nov 2026, Luther: with more than two teams, tap a team on
    /// the scoreboard and pick which team plays instead). Only before the
    /// clock has run and before anyone has a stat — after that the round is
    /// under way and the rotation decides.
    private var lineupEditable: Bool {
        guard game.status != .completed, !game.waitingTeams.isEmpty,
              timerSeconds == 0, !isTimerRunning else { return false }
        let noStats = game.playerStats.allSatisfy {
            $0.points == 0 && $0.rebounds == 0 && $0.assists == 0 && $0.steals == 0 && $0.blocks == 0
        }
        return noStats && game.baskets.isEmpty && game.teamScores.values.allSatisfy { $0 == 0 }
    }

    /// `waiting` goes on court in `current`'s slot, and `current` takes
    /// `waiting`'s place in the queue.
    private func putOnCourt(_ waiting: GameTeam, replacing current: GameTeam) {
        guard let slot = game.activeTeamIds.firstIndex(of: current.id),
              let a = game.teams.firstIndex(where: { $0.id == current.id }),
              let b = game.teams.firstIndex(where: { $0.id == waiting.id }) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            game.activeTeamIds[slot] = waiting.id
            game.teams.swapAt(a, b)
        }
        HapticFeedback.impact(.light)
        onSave()
    }

    @ViewBuilder
    private func teamScoreSwitch(team: GameTeam, index: Int) -> some View {
        if lineupEditable {
            Menu {
                Section(isChinese ? "换上哪队？" : "Who's up instead?") {
                    ForEach(game.waitingTeams) { waiting in
                        Button {
                            putOnCourt(waiting, replacing: team)
                        } label: {
                            Label(GameTeam.localizedColorName(waiting.name), systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                if !(isIPad && activeTeamsForScoring.count == 2) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selectedTeamIndex = index }
                    } label: {
                        Label(isChinese ? "显示\(GameTeam.localizedColorName(team.name))的球员" : "Show \(GameTeam.localizedColorName(team.name))'s players",
                              systemImage: "person.3")
                    }
                }
            } label: {
                teamScoreLabel(team: team, index: index, choosable: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.team.\(index)")
        } else {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selectedTeamIndex = index }
            } label: {
                teamScoreLabel(team: team, index: index, choosable: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.team.\(index)")
        }
    }

    private func teamScoreLabel(team: GameTeam, index: Int, choosable: Bool) -> some View {
        // Side by side (iPad / Mac) both teams are on screen: no selection.
        let selected = (isIPad && activeTeamsForScoring.count == 2) || selectedTeamIndex == index
        let color = team.displayColor(for: colorScheme)
        return Group {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                Text(GameTeam.localizedColorName(team.name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                if choosable {
                    // Says the team can be swapped for a waiting one.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("\(game.score(for: team.id))")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(game.score(for: team.id))))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(selected ? 0.18 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? color : .clear, lineWidth: 2))
        }
    }

    /// Basket-value strip, the selected team's players, and the last action.
    @ViewBuilder
    private var liveEntry: some View {
        let teams = activeTeamsForScoring
        if selectedTeamIndex < teams.count {
            let team = teams[selectedTeamIndex]
            VStack(spacing: 10) {
                if game.status != .completed {
                    basketValueStrip
                }
                LiveTeamPanel(game: $game, team: team, students: students,
                              pointValue: basketValue, onAction: log,
                              plannedSubs: plannedSubs, period: period, elapsedSeconds: timerSeconds)
                    .id(team.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: selectedTeamIndex == 0 ? .leading : .trailing),
                        removal: .move(edge: selectedTeamIndex == 0 ? .trailing : .leading)))
                    .allowsHitTesting(game.status != .completed)
                lastActionBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .clipped()
        }
    }

    /// Wide windows: the value strip, both teams' panels side by side (no
    /// switching — the scores above only show the score), the last action.
    private var liveEntryWide: some View {
        VStack(spacing: 12) {
            if game.status != .completed {
                basketValueStrip
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(activeTeamsForScoring) { team in
                    LiveTeamPanel(game: $game, team: team, students: students,
                                  pointValue: basketValue, onAction: log,
                                  plannedSubs: plannedSubs, period: period, elapsedSeconds: timerSeconds)
                        .allowsHitTesting(game.status != .completed)
                }
            }
            lastActionBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// +1 / +2 / +3. The game's standard value (set on the setup page) is
    /// selected by default and marked; any other is for the next basket only.
    private var basketValueStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { value in
                let selected = basketValue == value
                let standard = game.basketValue == value
                Button {
                    basketValue = value
                } label: {
                    VStack(spacing: 0) {
                        Text("+\(value)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        if standard {
                            Text(isChinese ? "标准" : "standard")
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live.value.\(value)")
            }
        }
        .sensoryFeedback(.selection, trigger: basketValue)
        .onAppear { basketValue = game.basketValue }
    }

    private var lastActionBar: some View {
        HStack(spacing: 10) {
            Text(lastActionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("live.last")
            Button(action: undoLast) {
                Label(isChinese ? "撤销" : "Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(actionLog.isEmpty)
            .accessibilityIdentifier("live.undo")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.filmCard))
        .sensoryFeedback(.warning, trigger: undoTick)
    }

    private func name(_ id: UUID) -> String {
        students.first { $0.id == id }?.primaryDisplayName ?? "—"
    }

    private var lastActionText: String {
        guard let last = actionLog.last else {
            return isChinese ? "点击球员得分 · 按住拖到传球人记助攻" : "Tap a player to score · drag to the passer for an assist"
        }
        let who = name(last.playerId)
        switch last.kind {
        case .points(let n):
            let assist = last.assistId.map { isChinese ? " · 助攻 \(name($0))" : " · assist \(name($0))" } ?? ""
            return "+\(n) \(who)\(assist)"
        case .rebound: return (isChinese ? "篮板 " : "Rebound ") + who
        case .steal: return (isChinese ? "抢断 " : "Steal ") + who
        case .block: return (isChinese ? "盖帽 " : "Block ") + who
        case .miss: return (isChinese ? "不中 " : "Miss ") + who
        }
    }

    private func log(_ action: GameStatAction) {
        action.apply(to: &game)
        actionLog.append(action)
        if case .points = action.kind { basketValue = game.basketValue }
        onSave()
    }

    private func undoLast() {
        guard let last = actionLog.popLast() else { return }
        last.undo(on: &game)
        undoTick += 1
        onSave()
    }

    // Teams currently on court for scoring
    private var activeTeamsForScoring: [GameTeam] {
        game.activeTeams.isEmpty ? game.teams : game.activeTeams
    }
    
    private var teamTabs: some View {
        HStack(spacing: 8) {
            ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                teamTabButton(team: team, index: index)
            }
        }
        .padding(16)
        .sensoryFeedback(.selection, trigger: selectedTeamIndex)
    }

    @ViewBuilder
    private func teamTabButton(team: GameTeam, index: Int) -> some View {
        let isSelected = selectedTeamIndex == index
        let label = HStack(spacing: 6) {
            Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
            Text(GameTeam.localizedColorName(team.name))
                .font(.footnote.weight(.semibold))
        }
        let action: () -> Void = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTeamIndex = index
            }
        }

        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(hex: team.colorHex))
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(hex: team.colorHex))
        }
    }
    
    // MARK: - iPad Side-by-Side Teams View
    private var sideBySideTeamsView: some View {
        HStack(spacing: 12) {
            // Only show active teams for scoring
            ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                teamColumn(team: team, teamIndex: index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func teamColumn(team: GameTeam, teamIndex: Int) -> some View {
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let isYellowTeam = team.colorHex == "#FFD700"
        // Use darker color for light teams (yellow, white) for better readability
        let displayColor = (isWhiteTeam || isYellowTeam) ? Color.black : teamColor
        
        return VStack(spacing: 0) {
            // Team header with score
            HStack(spacing: 8) {
                Circle().fill(teamColor).frame(width: 20, height: 20)
                    .overlay(Text(String(team.name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundColor(isWhiteTeam || isYellowTeam ? .black : .white))
                Text(GameTeam.localizedColorName(team.name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(game.score(for: team.id))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(displayColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(teamColor.opacity(0.15))
            .cornerRadius(12, corners: [.topLeft, .topRight])
            
            // Players list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(team.playerIds, id: \.self) { playerId in
                        if let student = students.first(where: { $0.id == playerId }) {
                            compactPlayerRow(student: student, team: team)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color.filmCard)
            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
        }
        .background(Color.filmCard)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    private func compactPlayerRow(student: Student, team: GameTeam) -> some View {
        let stats = game.stats(for: student.id)
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let isYellowTeam = team.colorHex == "#FFD700"
        // Use darker color for light teams for better button/text readability
        let buttonColor = (isWhiteTeam || isYellowTeam) ? Color(hex: "#CC9900") : teamColor
        
        return VStack(spacing: 6) {
            // Player info row
            HStack(spacing: 8) {
                StudentAvatarView(student: student, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(stats?.points ?? 0)").font(.system(size: 11, weight: .bold)).foregroundColor(buttonColor)
                        Text("PTS").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            
            // Compact scoring buttons
            if game.status != .completed {
                let rebLabel = isChinese ? "篮板" : "REB"
                let astLabel = isChinese ? "助攻" : "AST"
                let stlLabel = isChinese ? "抢断" : "STL"
                let blkLabel = isChinese ? "盖帽" : "BLK"
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        compactStatButton("+1", color: buttonColor) { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+2", color: buttonColor) { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+3", color: buttonColor) { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }
                    }
                    HStack(spacing: 4) {
                        compactStatButton(rebLabel, color: .secondary) { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(astLabel, color: .secondary) { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(stlLabel, color: .secondary) { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(blkLabel, color: .secondary) { game.addStat(.block, for: student.id, teamId: team.id); onSave() }
                    }
                }
            }
        }
        .padding(8)
        .filmGlass(.regular, in: .rect(cornerRadius: 8))
    }

    private func compactStatButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .controlSize(.small)
        .tint(color)
    }
    
    // MARK: - Battle Royal Players List
    private var battleRoyalPlayersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Sort by points descending
                let sortedPlayers = game.playerStats.sorted { $0.points > $1.points }
                ForEach(Array(sortedPlayers.enumerated()), id: \.element.playerId) { index, stats in
                    if let student = students.first(where: { $0.id == stats.playerId }) {
                        battleRoyalPlayerRow(student: student, stats: stats, rank: index + 1)
                    }
                }
            }.padding(16)
        }
    }
    
    private func battleRoyalPlayerRow(student: Student, stats: SessionPlayerStats, rank: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Rank indicator
                ZStack {
                    Circle()
                        .fill(rank == 1 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                        .frame(width: 24, height: 24)
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(rank)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                
                StudentAvatarView(student: student, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Show both English and Chinese names
                    HStack(spacing: 6) {
                        Text(student.primaryDisplayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.secondaryNameLine {
                            Text(chineseName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Show all stats (no assists for Battle Royal)
                    HStack(spacing: 8) {
                        statLabel("PTS", value: stats.points)
                        statLabel("REB", value: stats.rebounds)
                        statLabel("STL", value: stats.steals)
                        statLabel("BLK", value: stats.blocks)
                    }
                }
                
                Spacer()
            }
            
            // Scoring buttons
            if game.status != .completed {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: Color.accentColor, add: { game.addStat(.points(1), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+2", color: Color.accentColor, add: { game.addStat(.points(2), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+3", color: Color.accentColor, add: { game.addStat(.points(3), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: student.id); onSave() })
                    }
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .secondary, add: { game.addStat(.rebound, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("STL", color: .secondary, add: { game.addStat(.steal, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("BLK", color: .secondary, add: { game.addStat(.block, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: student.id); onSave() })
                    }
                }
            }
        }
        .padding(12)
        .filmGlass(.regular, in: .rect(cornerRadius: 12))
    }
    
    private var playersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Use activeTeamsForScoring to match teamTabs indexing
                if selectedTeamIndex < activeTeamsForScoring.count {
                    let team = activeTeamsForScoring[selectedTeamIndex]
                    ForEach(team.playerIds, id: \.self) { playerId in
                        if let student = students.first(where: { $0.id == playerId }) { playerScoringRow(student: student, team: team) }
                    }
                }
            }.padding(16)
        }
    }
    
    private func playerScoringRow(student: Student, team: GameTeam) -> some View {
        let stats = game.stats(for: student.id)
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let buttonColor = isWhiteTeam ? Color.gray : teamColor
        
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                StudentAvatarView(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    // Show both English and Chinese names
                    HStack(spacing: 6) {
                        Text(student.primaryDisplayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.secondaryNameLine {
                            Text(chineseName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Show all stats in a compact row
                    HStack(spacing: 8) {
                        statLabel("PTS", value: stats?.points ?? 0)
                        statLabel("REB", value: stats?.rebounds ?? 0)
                        statLabel("AST", value: stats?.assists ?? 0)
                        statLabel("STL", value: stats?.steals ?? 0)
                        statLabel("BLK", value: stats?.blocks ?? 0)
                    }
                }
                Spacer()
            }
            
            if game.status != .completed {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: buttonColor, add: { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+2", color: buttonColor, add: { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+3", color: buttonColor, add: { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: team.id); onSave() })
                    }
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .secondary, add: { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("AST", color: .secondary, add: { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.assist, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("STL", color: .secondary, add: { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("BLK", color: .secondary, add: { game.addStat(.block, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: team.id); onSave() })
                    }
                }
            }
        }
        .padding(12)
        .filmGlass(.regular, in: .rect(cornerRadius: 12))
    }

    private func statLabel(_ label: String, value: Int) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let localizedLabel: String = {
            switch label {
            case "PTS": return isChinese ? "分" : "PTS"
            case "REB": return isChinese ? "板" : "REB"
            case "AST": return isChinese ? "助" : "AST"
            case "STL": return isChinese ? "断" : "STL"
            case "BLK": return isChinese ? "帽" : "BLK"
            default: return label
            }
        }()
        return HStack(spacing: 2) { Text("\(value)").font(.system(size: 13, weight: .bold)).foregroundStyle(.primary); Text(localizedLabel).font(.system(size: 10)).foregroundStyle(.secondary) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("stat.\(label)")
            .accessibilityValue("\(value)")
    }
    private func statButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.small)
        .tint(color)
    }

    /// Stat button with long-press to undo/remove
    private func undoableStatButton(_ label: String, color: Color, add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let localizedLabel: String = {
            switch label {
            case "REB": return isChinese ? "篮板" : "REB"
            case "AST": return isChinese ? "助攻" : "AST"
            case "STL": return isChinese ? "抢断" : "STL"
            case "BLK": return isChinese ? "盖帽" : "BLK"
            default: return label
            }
        }()
        // One touch, one action: StatPressButton (tap adds, hold removes).
        // The Button + simultaneous long press here re-added on release.
        return StatPressButton(label: localizedLabel, color: color, add: add, remove: remove)
    }
    private func toggleTimer() {
        isTimerRunning.toggle()
        if isTimerRunning {
            if game.status == .ready {
                game.status = .inProgress
                game.startedAt = Date()
                hasFiredAlarm = false
            } else {
                game.status = .inProgress
            }
        } else {
            game.status = .paused
        }
        onSave()
    }
    private func resetTimer() {
        timerSeconds = 0
        isTimerRunning = false
        game.status = .ready
        game.startedAt = nil
        hasFiredAlarm = false
        onSave()
    }

    /// Hero play/pause control — sized so it's tappable across the gym
    /// from a bench. 56pt circle, large SF symbol, prominent fill.
    @ViewBuilder
    private var bigPlayPauseButton: some View {
        Button(action: toggleTimer) {
            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(isTimerRunning ? Color.orange : Color.green)
                )
                .shadow(color: (isTimerRunning ? Color.orange : Color.green).opacity(0.35),
                        radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isTimerRunning)
        .accessibilityLabel(isTimerRunning ? "Pause timer" : "Start timer")
    }

    /// Time-up alarm. Three short haptics + system sound bursts so the
    /// coach hears it across the gym even with the phone in a bag.
    /// Doesn't end the game — that stays on the coach's End Game tap.
    private func fireExpirationAlarm() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        // Sound 1005 = "Tweet" / short notification chime, audible without
        // disturbing nearby gyms. AudioServicesPlayAlertSound also vibrates
        // by default on devices that support it, but the haptic generator
        // adds a sharper kick on newer iPhones.
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                generator.notificationOccurred(.warning)
            }
        }
        #endif
    }
    
    private func endRound() {
        isTimerRunning = false
        
        // Determine winner of this round (use score(for:) which returns 0 if not set)
        let activeScores = game.activeTeamIds.map { teamId -> (UUID, Int) in
            (teamId, game.score(for: teamId))
        }
        
        // Find winner (highest score, or first team if tied)
        if let winner = activeScores.max(by: { $0.1 < $1.1 }) {
            // Rotate teams for next round (winner stays on)
            if game.gameType == .twoTeam && game.teams.count > 2 {
                // Save completed round as a separate game before resetting
                let completedRound = SessionGame(
                    id: UUID(),
                    sessionId: game.sessionId,
                    gameNumber: allGamesInSession.count + 1,
                    gameType: game.gameType,
                    teams: game.teams,
                    activeTeamIds: game.activeTeamIds,
                    teamScores: game.teamScores,
                    playerStats: game.playerStats,
                    durationMinutes: game.durationMinutes,
                    basketValue: game.basketValue,
                    roundNumber: game.roundNumber,
                    status: .completed,
                    startedAt: game.startedAt,
                    endedAt: Date(),
                    winningTeamId: winner.0
                )
                onSaveCompletedRound?(completedRound)
                
                // Rotate teams
                game.rotateTeamsForWinner(winnerId: winner.0)
                
                // Reset scores and player stats for new round
                for teamId in game.activeTeamIds {
                    game.teamScores[teamId] = 0
                }
                game.playerStats.removeAll()  // Clear all player stats for fresh round
                
                timerSeconds = 0
                game.status = .ready
                game.startedAt = nil
                hasFiredAlarm = false
            } else if game.gameType == .continuousFullCourt {
                game.rotateTeamsForContinuous(scoringTeamId: winner.0)
            }
        }
        onSave()
    }
    
    // MARK: - Next game

    private var teamsOnCourtCount: Int { max(2, game.gameType.requiredTeams) }

    private func nextGameTapped() {
        if game.teams.count <= teamsOnCourtCount {
            startNextGame(onCourt: game.teams.map(\.id))
            return
        }
        // Winner stays on, the next waiting team comes in — preselected,
        // the coach changes it if he wants.
        let active = activeTeamsForScoring
        var pick: [UUID] = []
        if game.gameType == .twoTeam {
            if let winner = active.max(by: { game.score(for: $0.id) < game.score(for: $1.id) }),
               game.score(for: winner.id) > 0 { pick.append(winner.id) }
            pick += game.waitingTeams.map(\.id)
            pick += active.map(\.id)
        } else {
            pick = active.map(\.id)
        }
        var seen = Set<UUID>()
        nextPick = NextPick(teams: Set(pick.filter { seen.insert($0).inserted }.prefix(teamsOnCourtCount)))
    }

    /// Finish this game (winner, record) and open a fresh one with the same
    /// teams and lineups, `onCourt` playing.
    private func startNextGame(onCourt: [UUID]) {
        isTimerRunning = false
        if game.status != .completed {
            game.status = .completed
            game.endedAt = Date()
            let scores = game.activeTeamIds.map { ($0, game.score(for: $0)) }
            if let best = scores.max(by: { $0.1 < $1.1 }), best.1 > 0,
               scores.filter({ $0.1 == best.1 }).count == 1 {
                game.winningTeamId = best.0
                for (id, _) in scores {
                    guard let i = game.teams.firstIndex(where: { $0.id == id }) else { continue }
                    if id == best.0 { game.teams[i].wins += 1 } else { game.teams[i].losses += 1 }
                }
            }
            onSave()
        }
        var next = SessionGame(
            sessionId: game.sessionId,
            gameNumber: allGamesInSession.count + 1,
            gameType: game.gameType,
            teams: game.teams,
            activeTeamIds: onCourt,
            durationMinutes: game.durationMinutes,
            basketValue: game.basketValue,
            status: .ready)
        next.playersPerSide = game.playersPerSide
        next.plannedSubsDone = game.plannedSubsDone
        next.tracksShots = game.tracksShots
        next.commonBench = game.commonBench
        HapticFeedback.impact(.medium)
        onNextGame?(next)
    }

    private func endGame() {
        isTimerRunning = false; game.status = .completed; game.endedAt = Date()
        
        // Determine overall winner based on total scores
        if let maxScore = game.teamScores.values.max(), let winningTeamId = game.teamScores.first(where: { $0.value == maxScore })?.key { 
            game.winningTeamId = winningTeamId 
        }
        
        // Update win/loss for final round
        if let winnerId = game.winningTeamId {
            if let winnerIndex = game.teams.firstIndex(where: { $0.id == winnerId }) {
                game.teams[winnerIndex].wins += 1
            }
            for teamId in game.activeTeamIds where teamId != winnerId {
                if let loserIndex = game.teams.firstIndex(where: { $0.id == teamId }) {
                    game.teams[loserIndex].losses += 1
                }
            }
        }
        
        onSave()
        
        // Show recap if there are stats
        if !game.playerStats.isEmpty {
            showingRecap = true
        }
    }
}

/// "Who plays next?" — pick the teams for the next game (Next Game with
/// more teams than fit on the court).
struct NextTeamsChooser: View {
    let game: SessionGame
    let required: Int
    let gameNumber: Int
    let onStart: (Set<UUID>) -> Void
    @State private var picked: Set<UUID>
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    init(game: SessionGame, required: Int, initial: Set<UUID>, gameNumber: Int, onStart: @escaping (Set<UUID>) -> Void) {
        self.game = game; self.required = required; self.gameNumber = gameNumber; self.onStart = onStart
        _picked = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isChinese ? "下一场谁上？" : "Who plays next?")
                .font(.headline)
                .padding(.horizontal, 16).padding(.top, 20)
            Text(isChinese ? "选 \(required) 队 · 这一场会结束并保存" : "Pick \(required) · this game ends and is saved")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(game.teams) { team in
                let on = picked.contains(team.id)
                Button {
                    if on { picked.remove(team.id) }
                    else if picked.count < required { picked.insert(team.id) }
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                        Text(GameTeam.localizedColorName(team.name)).foregroundStyle(.primary)
                        if game.activeTeamIds.contains(team.id) {
                            Text("\(game.score(for: team.id))")
                                .font(.subheadline.weight(.bold)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(isChinese ? "候场" : "waiting").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live.next.team")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button {
                onStart(picked)
            } label: {
                Text(isChinese ? "开始第 \(gameNumber) 场" : "Start Game \(gameNumber)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(picked.count != required)
            .padding(16)
            .accessibilityIdentifier("live.next.start")
        }
        .frame(maxWidth: 520)
    }
}

