import SwiftUI
import Charts

// MARK: - Game stats so far (October 2026, Luther)
//
// The Games tab's stats, unfolded at the bottom of the tab: the program's
// whole record — collective averages with their direction, the trend per
// session, this session against the average, leaders, and who has been
// playing. Numbers come from GameStatsReport; this file only draws.

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

// MARK: - Inline stats (bottom of the Games tab)

struct GameStatsContent: View {
    let report: GameStatsReport.Report
    let students: [Student]
    @State private var metric: GameStatsReport.Metric = .points
    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var locale: Locale { Locale(identifier: zh ? "zh_CN" : "en_GB") }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            tiles
            if report.trend.count >= 2 { trendSection }
            if let today = report.thisSession { todaySection(today) }
            leadersSection
            playingSection
        }
        .accessibilityIdentifier("games.stats")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(zh ? "比赛数据" : "GAME STATS SO FAR")
                .font(.caption.weight(.bold))
                .monospaced()
                .foregroundStyle(.secondary)
            Text(subtitle).font(.footnote).foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String {
        let since = report.firstDate.map { $0.formatted(.dateTime.month(.abbreviated).day().locale(locale)) } ?? ""
        return zh ? "\(report.sessions) 次课共 \(report.games) 场比赛 · 自 \(since) 起"
                  : "\(report.games) games over \(report.sessions) sessions · since \(since)"
    }

    // Collective averages, with the direction of the last three sessions.
    private var tiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(zh ? "全队平均" : "Team averages",
                         note: report.direction.isEmpty ? nil
                         : (zh ? "箭头：最近 3 次课对比之前" : "Arrows: last 3 sessions vs before"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(GameStatsReport.Metric.allCases) { m in
                    Button { metric = m } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: m.icon).font(.caption.weight(.semibold)).foregroundStyle(m.tint)
                            Text(report.average[m].map(m.format) ?? "–")
                                .font(.title3.weight(.bold)).monospacedDigit()
                            Text(m.title(zh)).font(.caption2.weight(.semibold))
                            Text(m.unit(zh)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .minimumScaleFactor(0.8)
                            StatDirectionChip(change: report.direction[m])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(metric == m ? m.tint : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Per-session line for the chosen stat, with the average as a rule.
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(zh ? "趋势 · \(metric.title(true))" : "Trend · \(metric.title(false))",
                         note: metric.unit(zh))
            Chart {
                ForEach(report.trend) { point in
                    if let v = point.values[metric] {
                        LineMark(x: .value("Session", point.date), y: .value(metric.short, v))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(metric.tint)
                        PointMark(x: .value("Session", point.date), y: .value(metric.short, v))
                            .foregroundStyle(metric.tint)
                    }
                }
                if let avg = report.average[metric] {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text(zh ? "平均 \(metric.format(avg))" : "avg \(metric.format(avg))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(locale))
            } }
            .frame(height: 180)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

            Picker("", selection: $metric) {
                ForEach(GameStatsReport.Metric.allCases) { Text($0.short).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func todaySection(_ today: [GameStatsReport.Metric: Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(zh ? "本次课 vs 平均" : "This session vs average", note: nil)
            VStack(spacing: 0) {
                ForEach(GameStatsReport.Metric.allCases) { m in
                    if let t = today[m], let avg = report.average[m] {
                        HStack {
                            Label(m.title(zh), systemImage: m.icon).foregroundStyle(.primary)
                                .labelStyle(.titleAndIcon).font(.subheadline)
                            Spacer()
                            Text(m.format(t)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text(zh ? "平均 \(m.format(avg))" : "avg \(m.format(avg))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 74, alignment: .trailing)
                            StatDirectionChip(change: avg > 0 ? (t - avg) / avg : nil)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        if m != .assistRate { Divider().padding(.leading, 12) }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var leadersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(zh ? "领先球员" : "Leaders", note: zh ? "总数 · 场均" : "total · per game")
            VStack(spacing: 0) {
                let counting: [GameStatsReport.Metric] = [.points, .rebounds, .assists, .steals, .blocks]
                ForEach(counting) { m in
                    if let top = report.leaders[m], !top.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: m.icon).foregroundStyle(m.tint).frame(width: 20)
                                .padding(.top, 8)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.title(zh)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(top) { leader in leaderRow(leader) }
                            }
                        }
                        .padding(12)
                        if m != counting.last { Divider().padding(.leading, 42) }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func leaderRow(_ leader: GameStatsReport.Leader) -> some View {
        HStack(spacing: 8) {
            if let s = student(leader.playerId) {
                StudentAvatarView(student: s, size: 26)
                Text(s.primaryDisplayName).font(.subheadline).lineLimit(1)
            } else {
                Text(zh ? "已离队球员" : "Former player").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(leader.total)").font(.subheadline.weight(.bold)).monospacedDigit()
            Text(String(format: "%.1f", leader.perGame))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    // Who has played how many games — the zeros are the ones to bring in.
    private var playingSection: some View {
        let most = max(1, report.playing.first?.games ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(zh ? "上场次数" : "Games played",
                         note: zh ? "还没上场的排在最后" : "players yet to play are last")
            VStack(spacing: 8) {
                ForEach(report.playing, id: \.playerId) { row in
                    if let s = student(row.playerId) {
                        HStack(spacing: 8) {
                            StudentAvatarView(student: s, size: 22)
                            Text(s.primaryDisplayName).font(.subheadline).lineLimit(1)
                                .frame(width: 110, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(row.games == 0 ? Color.red.opacity(0.25) : Color.accentColor.opacity(0.7))
                                    .frame(width: max(6, geo.size.width * CGFloat(row.games) / CGFloat(most)))
                            }
                            .frame(height: 8)
                            Text(row.games == 0 ? (zh ? "未上场" : "none") : "\(row.games)")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(row.games == 0 ? Color.red : Color.primary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func sectionTitle(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func student(_ id: UUID) -> Student? { students.first { $0.id == id } }
}
