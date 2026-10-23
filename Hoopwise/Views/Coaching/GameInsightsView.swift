import SwiftUI
import Charts

// MARK: - Game insights (October 2026, Luther)
//
// The Games tab ends with at most three insights from the program's games —
// Luther found the unfolded record too much ("limited smart insight"). The
// rules live in GameStatsReport.insights; this file words and draws them.
// The Metric labels and StatDirectionChip are shared with the athlete
// profile's Training Stats.

extension GameStatsReport.Metric {
    func title(_ zh: Bool) -> String {
        switch self {
        case .points: return zh ? "得分" : "Points"
        case .rebounds: return zh ? "篮板" : "Rebounds"
        case .assists: return zh ? "助攻" : "Assists"
        case .steals: return zh ? "抢断" : "Steals"
        case .blocks: return zh ? "盖帽" : "Blocks"
        case .assistRate: return zh ? "助攻率" : "Assist rate"
        }
    }

    /// What the number is per.
    func unit(_ zh: Bool) -> String {
        self == .assistRate ? (zh ? "每次进球的助攻" : "assists per basket") : (zh ? "每场" : "per game")
    }

    var short: String {
        switch self {
        case .points: return "PTS"
        case .rebounds: return "REB"
        case .assists: return "AST"
        case .steals: return "STL"
        case .blocks: return "BLK"
        case .assistRate: return "AST%"
        }
    }

    var icon: String {
        switch self {
        case .points: return "scope"
        case .rebounds: return "arrow.down.to.line"
        case .assists: return "arrow.triangle.branch"
        case .steals: return "hand.raised.fill"
        case .blocks: return "hand.raised.slash.fill"
        case .assistRate: return "point.3.connected.trianglepath.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .points: return .orange
        case .rebounds: return .teal
        case .assists: return .blue
        case .steals: return .purple
        case .blocks: return .pink
        case .assistRate: return .indigo
        }
    }

    func format(_ v: Double) -> String {
        self == .assistRate ? String(format: "%.2f", v) : String(format: "%.1f", v)
    }
}

/// "▲ 12%" / "▼ 8%" / "—", up is better for every stat here.
struct StatDirectionChip: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.05 {
            let up = change > 0
            Label("\(Int((abs(change) * 100).rounded()))%", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(up ? Color.green : Color.red)
        } else if change != nil {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "持平" : "steady")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Insights (bottom of the Games tab)

/// At most three sentences about the program's games — the ones worth acting
/// on (GameStatsReport.insights). Nothing worth saying → nothing shown.
struct GameInsightsView: View {
    let insights: [GameStatsReport.Insight]
    let games: Int
    let sessions: Int
    let students: [Student]
    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "比赛洞察" : "GAME INSIGHTS")
                    .font(.caption.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
                Text(zh ? "基于 \(sessions) 次课的 \(games) 场比赛" : "From \(games) games over \(sessions) sessions")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.offset) { i, insight in
                    row(insight)
                    if i < insights.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .accessibilityIdentifier("games.insights")
    }

    private func row(_ insight: GameStatsReport.Insight) -> some View {
        let c = content(insight)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: c.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.tint)
                .frame(width: 28, height: 28)
                .background(c.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(c.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func name(_ id: UUID) -> String {
        students.first { $0.id == id }?.primaryDisplayName ?? (zh ? "已离队球员" : "a former player")
    }

    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    private func content(_ insight: GameStatsReport.Insight) -> (icon: String, tint: Color, title: String, detail: String) {
        switch insight {
        case .notPlaying(let players):
            let names = players.prefix(3).map(name).joined(separator: zh ? "、" : ", ")
            let more = players.count > 3 ? (zh ? " 等 \(players.count) 人" : " and \(players.count - 3) more") : ""
            return ("person.crop.circle.badge.exclamationmark", .red,
                    zh ? "\(names)\(more) 还没上过场" : "\(names)\(more) \(players.count == 1 ? "hasn't" : "haven't") played a game yet",
                    zh ? "下次分队时先安排上场。" : "Put them on court first when you pick teams next.")
        case .unevenGames(let most, let mostGames, let least, let leastGames):
            return ("scalemass", .orange,
                    zh ? "上场次数不均" : "Playing time is uneven",
                    zh ? "\(name(most)) 打了 \(mostGames) 场，\(name(least)) 只有 \(leastGames) 场。"
                       : "\(name(most)) has played \(mostGames) games, \(name(least)) only \(leastGames).")
        case .fewAssists(let rate):
            return ("arrow.triangle.branch", .blue,
                    zh ? "很少通过传球得分" : "Few baskets come from a pass",
                    zh ? "每次进球只有 \(String(format: "%.2f", rate)) 次助攻——之后的训练计划会加入传球练习。"
                       : "\(String(format: "%.2f", rate)) assists per basket — upcoming plans add passing work.")
        case .bestSession(let ppg, let best):
            return ("trophy.fill", .yellow,
                    zh ? "本次课得分最高" : "Best scoring session yet",
                    zh ? "场均 \(f1(ppg)) 分，之前最好 \(f1(best)) 分。" : "\(f1(ppg)) points per game, up from a best of \(f1(best)).")
        case .riser(let player, let from, let to):
            return ("flame.fill", .orange,
                    zh ? "\(name(player)) 进步明显" : "\(name(player)) is taking off",
                    zh ? "最近 3 次课场均 \(f1(to)) 分，之前 \(f1(from)) 分。"
                       : "\(f1(to)) points per game over the last 3 sessions, up from \(f1(from)).")
        case .teamTrend(let metric, let change, let from, let to):
            let up = change > 0
            let pct = Int((abs(change) * 100).rounded())
            let value: (Double) -> String = { metric == .assistRate ? String(format: "%.2f", $0) : self.f1($0) }
            return (up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis", up ? .green : .red,
                    zh ? "全队\(metric.title(true))\(up ? "上升" : "下降") \(pct)%"
                       : "Team \(metric.title(false).lowercased()) \(up ? "up" : "down") \(pct)%",
                    zh ? "最近 3 次课\(metric.unit(true)) \(value(to))，之前 \(value(from))。"
                       : "\(value(to)) \(metric.unit(false)) over the last 3 sessions, from \(value(from)).")
        }
    }
}
