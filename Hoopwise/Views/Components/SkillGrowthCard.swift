import SwiftUI

// SKILL GROWTH (25 Nov 2026, Luther, after the audit: "do every gathered data
// points on athletes serve … how are we optimizing for athlete growth"). The
// athlete's eight ratings over time, read from the evaluation history
// (SkillsEvaluation.history): where each skill started, where it stands, and
// the line between. On the athlete profile.

/// One skill's path, pure — also what the progress report prints.
nonisolated struct SkillGrowthRow: Identifiable, Hashable, Sendable {
    let axis: DrillAttribute
    let first: Int
    let now: Int
    let ratings: [Int]
    var id: String { axis.rawValue }
    var change: Int { now - first }

    /// Every skill rated at both ends, biggest gain first (ties in the
    /// octagon's order).
    static func rows(_ skills: SkillsEvaluation) -> [SkillGrowthRow] {
        guard skills.baseline != nil else { return [] }
        return DrillAttribute.allCases.compactMap { axis -> SkillGrowthRow? in
            let series = skills.series(axis).map(\.rating)
            guard let first = series.first, let now = skills.rating(axis), series.count >= 2 else { return nil }
            return SkillGrowthRow(axis: axis, first: first, now: now, ratings: series)
        }
    }
}

struct SkillGrowthCard: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var skills: SkillsEvaluation? { dataManager.players.first { $0.studentId == studentId }?.skills }

    var body: some View {
        if let skills, skills.isEvaluated {
            let rows = SkillGrowthRow.rows(skills)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(isChinese ? "技能成长" : "SKILL GROWTH").font(.caption.weight(.bold))
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    if let base = skills.baseline {
                        Text(isChinese ? "自 \(base.date.formatted(date: .abbreviated, time: .omitted)) · \(skills.history.count) 次评估"
                                       : "Since \(base.date.formatted(date: .abbreviated, time: .omitted)) · \(skills.history.count) evaluations")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if rows.isEmpty {
                    Text(isChinese ? "目前只有一次评估。下次评估后，这里会显示每项技能的变化。"
                                   : "One evaluation so far. After the next one, each skill's change shows here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in line(row) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("athlete.skillGrowth")
        }
    }

    private func line(_ row: SkillGrowthRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.axis.icon).font(.footnote).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(row.axis.title).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Sparkline(values: row.ratings)
                .stroke(row.change > 0 ? Color.green : (row.change < 0 ? Color.red : Color.secondary),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                .frame(width: 64, height: 22)
            Text("\(row.first) → \(row.now)")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(width: 58, alignment: .trailing)
            Text(row.change == 0 ? "–" : (row.change > 0 ? "+\(row.change)" : "\(row.change)"))
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(row.change > 0 ? Color.green : (row.change < 0 ? Color.red : Color.secondary))
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("athlete.skillGrowth.row")
    }
}

/// Ratings 1…10 as a line across the frame.
struct Sparkline: Shape {
    let values: [Int]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count >= 2 else { return p }
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat(min(10, max(1, v)) - 1) / 9
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
