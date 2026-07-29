import SwiftUI

// MARK: - Live Scoring
/// Tight, two-team scoring console. Each scoring tap creates a `ScoringPlay`,
/// updates per-quarter scores, and writes back via `dataManager.updateGame`.
/// All mutations go through a single `commit` helper that also recomputes
/// running scores from the play log — so the totals are always derived from
/// the source of truth and can't drift.
struct LiveScoringSheet: View {
    let initialGame: Game
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var game: Game

    init(game: Game) {
        self.initialGame = game
        _game = State(initialValue: game)
    }

    private var homeTeam: Team? { dataManager.teams.first(where: { $0.id == game.homeTeamId }) }
    private var awayTeam: Team? { dataManager.teams.first(where: { $0.id == game.awayTeamId }) }

    private var homeRoster: [Student] {
        guard let team = homeTeam else { return [] }
        return dataManager.students.filter { team.playerIds.contains($0.id) }.sorted { $0.name < $1.name }
    }
    private var awayRoster: [Student] {
        guard let team = awayTeam else { return [] }
        return dataManager.students.filter { team.playerIds.contains($0.id) }.sorted { $0.name < $1.name }
    }

    private var currentQuarter: Int {
        max(1, min(8, game.quarter ?? 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controlBar
            Divider()
            HStack(spacing: 0) {
                teamColumn(team: homeTeam, roster: homeRoster, isHome: true)
                Divider()
                teamColumn(team: awayTeam, roster: awayRoster, isHome: false)
            }
            Divider()
            footer
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    // MARK: - Header / scoreboard

    private var header: some View {
        HStack {
            scoreboardSide(team: homeTeam, score: game.homeScore, alignment: .leading)
            Spacer()
            VStack(spacing: 4) {
                Text(quarterLabel).font(.title3.weight(.semibold).monospacedDigit())
                Text(statusLabel).font(.caption).foregroundStyle(statusTint)
            }
            Spacer()
            scoreboardSide(team: awayTeam, score: game.awayScore, alignment: .trailing)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
    }

    private func scoreboardSide(team: Team?, score: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(team?.name ?? "—").font(.subheadline.weight(.semibold))
            Text("\(score)")
                .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(team.map { Color(hex: $0.colorHex) } ?? .primary)
        }
        .frame(maxWidth: 220, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var quarterLabel: String {
        if currentQuarter <= 4 { return "Q\(currentQuarter)" }
        return "OT\(currentQuarter - 4)"
    }

    private var statusLabel: String {
        switch game.status {
        case .live: return "LIVE"
        case .finished: return "FINAL"
        case .scheduled: return "SCHEDULED"
        case .cancelled: return "CANCELLED"
        case .postponed: return "POSTPONED"
        }
    }

    private var statusTint: Color {
        switch game.status {
        case .live: return .red
        case .finished: return .green
        case .scheduled: return .blue
        case .cancelled, .postponed: return .gray
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            if game.status != .live {
                Button {
                    commit { g in
                        g.status = .live
                        if g.quarter == nil { g.quarter = 1 }
                    }
                } label: {
                    Label("Start Game", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    commit { g in
                        g.status = .finished
                    }
                } label: {
                    Label("End Game", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Divider().frame(height: 24)

            Button {
                commit { g in
                    let next = (g.quarter ?? 1) - 1
                    g.quarter = max(1, next)
                }
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .disabled(currentQuarter <= 1)

            Text(quarterLabel)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44)

            Button {
                commit { g in
                    let next = (g.quarter ?? 1) + 1
                    g.quarter = min(8, next)
                    // Pre-create a quarter score if missing
                    if !g.quarterScores.contains(where: { $0.quarter == g.quarter }) {
                        g.quarterScores.append(QuarterScore(quarter: g.quarter ?? 1))
                    }
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(currentQuarter >= 8)

            Spacer()

            Button(role: .destructive) {
                undoLastPlay()
            } label: {
                Label("Undo Last Play", systemImage: "arrow.uturn.backward")
            }
            .disabled(game.scoringPlays.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Team column

    @ViewBuilder
    private func teamColumn(team: Team?, roster: [Student], isHome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(team.map { Color(hex: $0.colorHex) } ?? .gray).frame(width: 14, height: 14)
                Text(team?.name ?? "—").font(.subheadline.weight(.semibold))
                Spacer()
                Text(isHome ? "HOME" : "AWAY")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }

            if roster.isEmpty {
                Text("No roster assigned to \(team?.name ?? "this team"). Add players in the Athletes tab.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(roster) { student in
                            PlayerScoringRow(
                                student: student,
                                points: pointsFor(playerId: student.id),
                                disabled: game.status != .live,
                                onScore: { points, type in
                                    record(points: points, type: type, player: student, teamId: isHome ? game.homeTeamId : game.awayTeamId)
                                }
                            )
                        }
                    }
                }
            }

            if !playLogFor(teamId: isHome ? game.homeTeamId : game.awayTeamId).isEmpty {
                Divider()
                Text("Recent")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(playLogFor(teamId: isHome ? game.homeTeamId : game.awayTeamId).prefix(8), id: \.id) { play in
                            playRow(play)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playRow(_ play: ScoringPlay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: play.playType.icon).foregroundStyle(.orange).font(.caption)
            Text("+\(play.points)").font(.caption.weight(.bold).monospacedDigit())
            if let stu = dataManager.students.first(where: { $0.id == play.playerId }) {
                Text(stu.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(play.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Text("\(game.scoringPlays.count) plays · Q\(currentQuarter)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Logic

    private func record(points: Int, type: ScoringPlayType, player: Student, teamId: UUID) {
        guard game.status == .live else { return }
        commit { g in
            let play = ScoringPlay(
                gameId: g.id,
                playerId: player.id,
                teamId: teamId,
                points: points,
                playType: type,
                quarter: g.quarter ?? 1,
                timestamp: Date()
            )
            g.scoringPlays.append(play)
        }
    }

    private func undoLastPlay() {
        commit { g in
            guard !g.scoringPlays.isEmpty else { return }
            g.scoringPlays.removeLast()
        }
    }

    /// Single mutation point. Mutates a working copy, recomputes running
    /// scores from the play log, persists. This keeps `homeScore` /
    /// `awayScore` / quarter scores derived rather than independently mutated,
    /// so they can't drift out of sync with the play history.
    private func commit(_ block: (inout Game) -> Void) {
        var copy = game
        block(&copy)

        // Recompute running scores from plays
        copy.homeScore = copy.scoringPlays.filter { $0.teamId == copy.homeTeamId }.reduce(0) { $0 + $1.points }
        copy.awayScore = copy.scoringPlays.filter { $0.teamId == copy.awayTeamId }.reduce(0) { $0 + $1.points }

        // Recompute quarter scores
        let allQuarters = Set(copy.scoringPlays.map(\.quarter)).union(copy.quarterScores.map(\.quarter))
        var rebuilt: [QuarterScore] = []
        for q in allQuarters.sorted() {
            let h = copy.scoringPlays.filter { $0.quarter == q && $0.teamId == copy.homeTeamId }.reduce(0) { $0 + $1.points }
            let a = copy.scoringPlays.filter { $0.quarter == q && $0.teamId == copy.awayTeamId }.reduce(0) { $0 + $1.points }
            rebuilt.append(QuarterScore(quarter: q, homeScore: h, awayScore: a))
        }
        copy.quarterScores = rebuilt
        copy.updatedAt = Date()

        dataManager.updateGame(copy)
        game = copy
    }

    private func pointsFor(playerId: UUID) -> Int {
        game.scoringPlays.filter { $0.playerId == playerId }.reduce(0) { $0 + $1.points }
    }

    private func playLogFor(teamId: UUID) -> [ScoringPlay] {
        game.scoringPlays.filter { $0.teamId == teamId }.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Per-player row

private struct PlayerScoringRow: View {
    let student: Student
    let points: Int
    let disabled: Bool
    let onScore: (Int, ScoringPlayType) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.avatarColor(student.avatarColor))
                .overlay(Text(student.initials).font(.caption2.weight(.bold)).foregroundStyle(.white))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(student.displayName).font(.caption.weight(.medium)).lineLimit(1)
                Text("\(points) pts").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                scoreButton(points: 1, type: .freeThrow, label: "+1")
                scoreButton(points: 2, type: .jumpShot, label: "+2")
                scoreButton(points: 3, type: .threePointer, label: "+3")
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(disabled ? 0.5 : 1.0)
    }

    private func scoreButton(points: Int, type: ScoringPlayType, label: String) -> some View {
        Button {
            onScore(points, type)
        } label: {
            Text(label).font(.caption.weight(.bold).monospacedDigit())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
        .help("\(label) · \(type.rawValue)")
    }
}
