import SwiftUI
import Charts

/// The athlete's results in the coach's own tracked drills (23 Nov 2026):
/// one row per drill — the last three, best, sessions, the trend, their rank
/// in the same grade and the skills it speaks for. Hidden until there is a
/// result.
struct CustomTrackProfileSection: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let grade = student.currentSchoolGrade()
        let peers = grade == nil ? [] : dataManager.students.filter { $0.currentSchoolGrade() == grade }.map(\.id)
        let standings = CustomTrackHistory.standings(for: student.id, peers: peers, drills: dataManager.drills,
                                                     sessions: dataManager.sessionEvents)
        if !standings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(isChinese ? "训练成绩" : "Tracked drills", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                ForEach(standings, id: \.self) { st in
                    row(st)
                    if st != standings.last { Divider() }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("athlete.tracked")
        }
    }

    private func row(_ st: CustomTrackHistory.Standing) -> some View {
        let def = st.definition
        let points = CustomTrackHistory.series(student.id, drillId: st.drillId, key: def.key, sessions: dataManager.sessionEvents)
        let best = points.map(\.value).max { def.better($1, than: $0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.drillName).font(.subheadline.weight(.semibold))
                    Text(def.summary(chinese: isChinese)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = points.last {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(def.text(latest.value, chinese: isChinese)).font(.title3.weight(.bold)).monospacedDigit()
                        Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 14) {
                if let best { stat(isChinese ? "最佳" : "Best", def.text(best, chinese: isChinese)) }
                if points.count > 1 { stat(isChinese ? "近 3 次" : "Last 3", def.text(st.recent, chinese: isChinese)) }
                stat(isChinese ? "次数" : "Sessions", "\(points.count)")
                if st.of >= 2 {
                    stat(isChinese ? "同年级" : "Same grade",
                         isChinese ? "第 \(st.rank)/\(st.of)" : "\(CustomTrackHistory.ordinal(st.rank)) of \(st.of)")
                }
                Spacer()
            }
            if points.count >= 2 {
                Chart(points, id: \.self) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Result", p.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.orange)
                    PointMark(x: .value("Date", p.date), y: .value("Result", p.value))
                        .foregroundStyle(.orange)
                        .symbolSize(24)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: def.lowerIsBetter))
                .chartXAxis(.hidden)
                .frame(height: 70)
            }
            if !def.attributes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(def.attributes, id: \.self) { a in
                        Label(a.title(chinese: isChinese), systemImage: a.icon)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}
