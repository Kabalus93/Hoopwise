import SwiftUI

// MARK: - Training Stats (athlete profile, October 2026)
//
// What the athlete has done in the games played during training sessions —
// the scrimmages on each session's Games tab. League stats and measurements
// were removed from the profile at Luther's request; this is the one stats
// section left, so it must be exactly right:
//   · games come from `GameStatsReport.playerGames` — the same games the
//     Games tab counts (played, not only "ended"; sessions that happened);
//   · per-game averages for all five counting stats, not three;
//   · direction compares the last 3 SESSIONS with the ones before (the Games
//     tab's rule), not two single games' points;
//   · recent games are listed by game, newest first, with the result.

struct CollapsibleTrainingStatsSection: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    /// The store's sessions unless given (the DEBUG gallery passes a made-up season).
    var sessions: [SessionEvent]? = nil
    @State private var isExpanded: Bool = true

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var report: GameStatsReport.PlayerReport {
        GameStatsReport.player(studentId, sessions: sessions ?? dataManager.sessionEvents)
    }

    var body: some View {
        let report = report
        return VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack {
                    Label {
                        Text(zh ? "训练比赛数据" : "Training Stats").font(.headline)
                    } icon: {
                        Image(systemName: "figure.basketball").foregroundStyle(.orange)
                    }
                    .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if report.games > 0 {
                    summaryLine(report)
                    averages(report)
                    if !report.recent.isEmpty { recentGames(report) }
                } else {
                    empty
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(report.games > 0 ? Color.orange.opacity(0.2) : Color.clear, lineWidth: 1))
        .accessibilityIdentifier("profile.trainingStats")
    }

    private func summaryLine(_ r: GameStatsReport.PlayerReport) -> some View {
        let record = r.record.won + r.record.lost > 0
            ? (zh ? " · \(r.record.won) 胜 \(r.record.lost) 负" : " · \(r.record.won)–\(r.record.lost) W–L") : ""
        return Text(zh ? "\(r.sessions) 次课共 \(r.games) 场比赛\(record)"
                       : "\(r.games) games over \(r.sessions) sessions\(record)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func averages(_ r: GameStatsReport.PlayerReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(zh ? "场均" : "PER GAME")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !r.direction.isEmpty {
                    Text(zh ? "箭头：最近 3 次课对比之前" : "Arrows: last 3 sessions vs before")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(GameStatsReport.countingMetrics) { m in
                    VStack(spacing: 3) {
                        Text(String(format: "%.1f", r.average[m] ?? 0))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle((r.average[m] ?? 0) > 0 ? m.tint : Color.secondary)
                        Text(zh ? m.title(true) : m.short)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(r.totals[m] ?? 0)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        StatDirectionChip(change: r.direction[m])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
            Text(zh ? "下方小字为总数" : "Small number: total")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func recentGames(_ r: GameStatsReport.PlayerReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(zh ? "最近比赛" : "RECENT GAMES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                ForEach(r.recent) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.date.formatted(.dateTime.month(.abbreviated).day()
                                .locale(Locale(identifier: zh ? "zh_CN" : "en_GB"))))
                                .font(.system(size: 11, weight: .medium))
                            Text(zh ? "第 \(item.game.gameNumber) 场" : "Game \(item.game.gameNumber)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 64, alignment: .leading)
                        if let won = item.won {
                            Text(won ? (zh ? "胜" : "W") : (zh ? "负" : "L"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(won ? Color.green : Color.red)
                                .frame(width: 18)
                        } else {
                            Text("–").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 18)
                        }
                        Spacer(minLength: 4)
                        statText(item.line.points, "PTS", .orange)
                        statText(item.line.rebounds, "REB", .teal)
                        statText(item.line.assists, "AST", .blue)
                        statText(item.line.steals, "STL", .purple)
                        statText(item.line.blocks, "BLK", .pink)
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }

    private func statText(_ v: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(v)").font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(v > 0 ? color : Color.secondary)
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(width: 30)
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar").font(.system(size: 20)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "还没有训练比赛数据" : "No training stats yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(zh ? "在课程的比赛里记录数据后会显示在这里" : "Stats appear after games played in sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
        CollapsibleTrainingStatsSection(studentId: UUID())
            .padding()
    }
}
