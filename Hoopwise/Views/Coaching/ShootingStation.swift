import SwiftUI

// TRACKED DRILLS LIVE IN THEIR PLAN ROW (23 Nov 2026, Luther: the add-on
// cards "took too much space", folding one "was popping back up", setting
// them up was annoying). The plan no longer carries an ADD-ONS section of
// big cards under Skills. A tracked drill's own row in Warm-up / Skills shows
// ONE tracker line — how it is scored, who has logged, the group's result
// against last time — and a Log button. Log (or a tap on the line) opens the
// SHOOTING STATION: the whole tracker as a page (setup, clock, table, the
// pad), closed with Done. Nothing on the plan to fold, so nothing pops open.

/// The one line under a tracked drill's plan row.
struct ShootingTrackerLine: View {
    let drill: ShootingDrill
    let run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool
    let onOpen: () -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let logged = students.filter { run.result(for: $0.id) != nil }
        let values = logged.compactMap { run.result(for: $0.id)?.value }
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let thenValues = logged.compactMap {
            ShootingHistory.previous($0.id, setup: run.setup, before: sessionDate, sessions: allSessions)?.value
        }
        let thenAvg = thenValues.count >= 2 ? thenValues.reduce(0, +) / Double(thenValues.count) : nil

        return Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.orange.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.setup.summary(chinese: isChinese))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if students.isEmpty {
                            Text(isChinese ? "还没有学员" : "No athletes yet")
                        } else {
                            ProgressView(value: Double(logged.count), total: Double(max(1, students.count)))
                                .tint(.orange)
                                .frame(width: 44)
                            Text(isChinese ? "已记录 \(logged.count)/\(students.count)" : "\(logged.count)/\(students.count) logged")
                                .monospacedDigit()
                        }
                        if let avg {
                            Text("·")
                            Text((isChinese ? "全组 " : "Group ") + ShootingResult.text(avg, mode: run.setup.mode, chinese: isChinese))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            if let thenAvg, abs(avg - thenAvg) > 0.0001 {
                                Image(systemName: avg > thenAvg ? "arrow.up" : "arrow.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(avg > thenAvg ? .green : .red)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(canEdit ? (isChinese ? "记录" : "Log") : (isChinese ? "结果" : "Results"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Color.orange))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shooting.tracker.\(drill.rawValue)")
    }
}

/// The whole tracker as a page.
struct ShootingStationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager
    let drill: ShootingDrill
    @Binding var run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if drill == .shotChart {
                        ShotChartAddOnCard(run: $run, students: students, sessionDate: sessionDate,
                                           allSessions: allSessions, canEdit: canEdit, station: true)
                    } else {
                        ShootingAddOnCard(drill: drill, run: $run, students: students, sessionDate: sessionDate,
                                          allSessions: allSessions, canEdit: canEdit, station: true)
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(drill.title(chinese: isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("shooting.station.done")
                }
            }
        }
        .environmentObject(dataManager)
    }
}
