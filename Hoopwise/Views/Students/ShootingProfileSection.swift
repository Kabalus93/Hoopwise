import SwiftUI
import Charts

/// The athlete's tracked shooting (20 Nov 2026): one row per test — latest,
/// best, the trend over sessions, and (five-spot drills) the spots tinted by
/// the athlete's own hot and cold. Hidden until there is a result.
struct ShootingProfileSection: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let series = ShootingHistory.series(for: studentId, sessions: dataManager.sessionEvents)
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(isChinese ? "投篮记录" : "Shooting", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                // Every drill with a place on the floor, on one map.
                AthleteShotChartCard(studentId: studentId)
                ForEach(series) { s in
                    row(s)
                    if s.id != series.last?.id { Divider() }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("athlete.shooting")
        }
    }

    private func row(_ s: ShootingHistory.Series) -> some View {
        let mode = s.setup.mode
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.setup.drill.title(chinese: isChinese)).font(.subheadline.weight(.semibold))
                    Text(s.setup.summary(chinese: isChinese)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = s.latest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ShootingResult.text(latest.value, mode: mode, chinese: isChinese))
                            .font(.title3.weight(.bold)).monospacedDigit()
                        Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 14) {
                if let best = s.best {
                    stat(isChinese ? "最佳" : "Best", ShootingResult.text(best, mode: mode, chinese: isChinese))
                }
                if let recent = s.recent(), s.points.count > 1 {
                    stat(isChinese ? "近 3 次" : "Last 3", ShootingResult.text(recent, mode: mode, chinese: isChinese))
                }
                stat(isChinese ? "次数" : "Sessions", "\(s.points.count)")
                Spacer()
                if s.setup.drill.spotCount > 1 { spots(s) }
            }
            if s.points.count >= 2 {
                Chart(Array(s.points.enumerated()), id: \.offset) { i, p in
                    LineMark(x: .value("#", i), y: .value("v", p.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.orange)
                    PointMark(x: .value("#", i), y: .value("v", p.value))
                        .foregroundStyle(Color.orange)
                        .symbolSize(24)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(mode.isShare ? "\(Int((d * 100).rounded()))%" : String(format: "%.0f", d))
                            }
                        }
                    }
                }
                .chartYScale(domain: mode.isShare ? 0...1 : 0...max(1, (s.best ?? 1) * 1.2))
                .frame(height: 70)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }

    /// A dot per spot (left corner to right corner; right / left), tinted
    /// against the athlete's own average: red hot, blue cold.
    private func spots(_ s: ShootingHistory.Series) -> some View {
        let averages = s.spotAverages
        let known = averages.compactMap { $0 }
        let mean = known.isEmpty ? 0 : known.reduce(0, +) / Double(known.count)
        return HStack(spacing: 4) {
            ForEach(0..<averages.count, id: \.self) { i in
                let v = averages[i]
                let tint: Color = {
                    guard let v, mean > 0 else { return Color(.tertiarySystemFill) }
                    if v >= mean * 1.15 { return .red.opacity(0.85) }      // hot
                    if v <= mean * 0.85 { return .blue.opacity(0.7) }      // cold
                    return .orange.opacity(0.5)
                }()
                VStack(spacing: 2) {
                    Circle().fill(tint).frame(width: 14, height: 14)
                    Text(s.setup.drill.spotShort(i, chinese: isChinese))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 18)
                .accessibilityLabel(s.setup.drill.spotName(i, chinese: isChinese))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
