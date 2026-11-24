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
    /// true = open on a NEW round (the last one is complete).
    let onOpen: (Bool) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        // With several rounds the line follows the LATEST one, against the
        // round before it; with one, the session against last time.
        let rounds = run.roundCount
        let current = run.round(rounds - 1)
        let before = rounds > 1 ? run.round(rounds - 2) : nil
        let logged = students.filter { current.result(for: $0.id) != nil }
        let values = logged.compactMap { current.result(for: $0.id)?.value }
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let thenValues = logged.compactMap { s in
            before != nil ? before?.result(for: s.id)?.value
                : ShootingHistory.previous(s.id, setup: run.setup, before: sessionDate, sessions: allSessions)?.value
        }
        let thenAvg = thenValues.count >= (before != nil ? 1 : 2) ? thenValues.reduce(0, +) / Double(thenValues.count) : nil
        let complete = !students.isEmpty && logged.count == students.count
        let next = canEdit && complete

        return Button(action: { onOpen(next) }) {
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
                            Text(TrackerRoundText.logged(logged.count, students.count, round: rounds, chinese: isChinese))
                                .monospacedDigit()
                        }
                        if let avg {
                            Text("·")
                            Text((isChinese ? "全组 " : "Group ")
                                 + (before != nil && thenAvg != nil ? ShootingResult.text(thenAvg!, mode: run.setup.mode, chinese: isChinese) + " → " : "")
                                 + ShootingResult.text(avg, mode: run.setup.mode, chinese: isChinese))
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
                Text(TrackerRoundText.button(canEdit: canEdit, nextRound: next ? rounds + 1 : nil, chinese: isChinese))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmRoom.isOn ? Color.orange : Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: FilmRoom.isOn ? 26 : 32)
                    .background(Capsule().fill(Color.orange.opacity(FilmRoom.isOn ? 0.16 : 1)))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FilmRoom.isOn ? Color.white.opacity(0.04) : Color.orange.opacity(0.07)))
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
    /// Open on a new round.
    var newRound = false

    /// The round on screen.
    @State private var round = 0
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// The round on screen as a run of its own (what the cards edit).
    private var roundRun: Binding<ShootingRun> {
        Binding(get: { run.round(min(round, run.roundCount - 1)) },
                set: { updated in
                    var all = run
                    all.setup = updated.setup
                    all.setRound(min(round, all.roundCount - 1), entries: updated.entries)
                    run = all
                })
    }

    var body: some View {
        let shown = min(round, run.roundCount - 1)
        let before = shown > 0 ? run.round(shown - 1) : nil
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    RoundBar(count: run.roundCount, selection: $round, canEdit: canEdit,
                             canAdd: !run.round(run.roundCount - 1).entries.isEmpty,
                             onAdd: { var all = run; round = all.addRound(); run = all },
                             onDelete: { var all = run; all.removeRound(shown); run = all; round = max(0, shown - 1) })
                    if drill == .shotChart {
                        ShotChartAddOnCard(run: roundRun, students: students, sessionDate: sessionDate,
                                           allSessions: allSessions, canEdit: canEdit, station: true,
                                           previousRound: before, previousRoundNumber: shown, lockSetup: run.hasResults)
                            .id(shown)
                    } else {
                        ShootingAddOnCard(drill: drill, run: roundRun, students: students, sessionDate: sessionDate,
                                          allSessions: allSessions, canEdit: canEdit, station: true,
                                          previousRound: before, previousRoundNumber: shown, lockSetup: run.hasResults)
                            .id(shown)
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .filmRoomPage()
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
        .onAppear {
            if newRound, canEdit, !run.round(run.roundCount - 1).entries.isEmpty {
                var all = run; round = all.addRound(); run = all
            } else {
                round = run.roundCount - 1
            }
        }
        .onDisappear {
            // A round nobody logged in is not kept.
            var all = run; all.dropEmptyRounds()
            if all != run { run = all }
        }
    }
}

/// The words a tracker line uses once a drill has rounds.
enum TrackerRoundText {
    static func logged(_ n: Int, _ of: Int, round: Int, chinese: Bool) -> String {
        let base = chinese ? "已记录 \(n)/\(of)" : "\(n)/\(of) logged"
        guard round > 1 else { return base }
        return (chinese ? "第 \(round) 轮 · " : "Round \(round) · ") + base
    }

    static func button(canEdit: Bool, nextRound: Int?, chinese: Bool) -> String {
        guard canEdit else { return chinese ? "结果" : "Results" }
        if let nextRound { return chinese ? "第 \(nextRound) 轮" : "Round \(nextRound)" }
        return chinese ? "记录" : "Log"
    }
}

/// ROUNDS (23 Nov 2026, Luther: "sometimes I would run the same drill more
/// than once … see how they improve within the session or after correcting
/// something"). Round 1 | Round 2 | + over a station's table; hidden until
/// there is something to run again. Every round keeps the same setup.
struct RoundBar: View {
    let count: Int
    @Binding var selection: Int
    let canEdit: Bool
    /// The last round has results (so another can start).
    let canAdd: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        if count > 1 || (canEdit && canAdd) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { i in
                            let on = i == min(selection, count - 1)
                            Button { selection = i } label: {
                                Text(isChinese ? "第 \(i + 1) 轮" : "Round \(i + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(Capsule().fill(on ? Color.orange : Color(.tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("round.\(i + 1)")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                        if canEdit && canAdd {
                            Button(action: onAdd) {
                                Label(isChinese ? "再来一轮" : "New round", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(Capsule().strokeBorder(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("round.add")
                        }
                    }
                }
                Spacer(minLength: 0)
                if canEdit && count > 1 {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label(isChinese ? "删除第 \(min(selection, count - 1) + 1) 轮" : "Delete round \(min(selection, count - 1) + 1)", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .accessibilityIdentifier("round.more")
                }
            }
        }
    }
}
