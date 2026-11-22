import SwiftUI
import AudioToolbox
import Combine

// THE COACH'S OWN TRACKED DRILLS IN A SESSION (23 Nov 2026 — definition and
// maths in Models/CustomTracking.swift). Same shape as the built-in shooting
// drills: one tracker line on the drill's plan row → a station page (summary,
// table, Log). A tap on a cell (or Log, for the next empty one) pops the
// floating number pad out of that cell — the keys alone, as on the shooting
// drills (23 Nov 2026, Luther: "the popup should only be a number pad");
// ✓ logs and the next cell opens. A time is typed in seconds with tenths; a
// time-to-finish drill also has a STOPWATCH on the page that drops each time
// into the next athlete's cell.

/// The one line under a custom tracked drill's plan row.
struct CustomTrackerLine: View {
    let drillId: UUID
    let run: TrackedRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool
    let onOpen: () -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var def: TrackDefinition { run.definition }

    var body: some View {
        let logged = students.filter { run.result(for: $0.id) != nil }
        let values = logged.compactMap { run.result(for: $0.id) }
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let then = logged.compactMap {
            CustomTrackHistory.previous($0.id, drillId: drillId, key: def.key, before: sessionDate, sessions: allSessions)
        }
        let thenAvg = then.count >= 2 ? then.reduce(0, +) / Double(then.count) : nil

        return Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: def.measure.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.orange.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(def.summary(chinese: isChinese))
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
                            Text((isChinese ? "全组 " : "Group ") + def.text(avg, chinese: isChinese))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            if let thenAvg, abs(avg - thenAvg) > 0.0001 {
                                let better = def.better(avg, than: thenAvg)
                                Image(systemName: better ? "arrow.up" : "arrow.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(better ? .green : .red)
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
        .accessibilityIdentifier("track.line")
    }
}

/// The custom tracked drill's results as a page.
struct CustomTrackStationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager
    let drillId: UUID
    let drillName: String
    @Binding var run: TrackedRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool

    @State private var active: PadCell?
    @State private var draft = NumberPadEntry(text: "")
    /// The cell to open once the current popup has gone.
    @State private var pending: PadCell?
    /// Stopwatch (time to finish).
    @State private var startedAt: Date?
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var def: TrackDefinition { run.definition }

    private var lastTime: [UUID: Double] {
        var out: [UUID: Double] = [:]
        for s in students {
            if let v = CustomTrackHistory.previous(s.id, drillId: drillId, key: def.key, before: sessionDate, sessions: allSessions) {
                out[s.id] = v
            }
        }
        return out
    }

    var body: some View {
        let last = lastTime
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summary(last)
                    if def.measure == .timeToFinish && canEdit && !students.isEmpty { stopwatch }
                    if students.isEmpty {
                        Text(isChinese ? "这节课还没有学员。" : "No athletes on this session yet.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        table(last)
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(drillName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("track.station.done")
                }
            }
            .onReceive(tick) { if startedAt != nil { now = $0 } }
        }
        .environmentObject(dataManager)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: def.measure.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(def.measure.title(chinese: isChinese).uppercased())
                    .font(.subheadline.weight(.bold))
                Text(def.summary(chinese: isChinese))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if canEdit && !students.isEmpty {
                Button {
                    openAtNext()
                } label: {
                    Label(isChinese ? "记录" : "Log", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("track.log")
            }
        }
    }

    private func summary(_ last: [UUID: Double]) -> some View {
        let logged = students.filter { run.result(for: $0.id) != nil }
        let today = logged.compactMap { run.result(for: $0.id) }
        let avg = today.isEmpty ? nil : today.reduce(0, +) / Double(today.count)
        let then = logged.compactMap { last[$0.id] }
        let thenAvg = then.count >= 2 ? then.reduce(0, +) / Double(then.count) : nil
        let best = logged.max { a, b in
            guard let x = run.result(for: a.id), let y = run.result(for: b.id) else { return false }
            return def.better(y, than: x)
        }
        return HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                caption(isChinese ? "已记录" : "Logged")
                Text("\(logged.count)/\(students.count)").font(.title3.weight(.bold)).monospacedDigit()
                ProgressView(value: Double(logged.count), total: Double(max(1, students.count))).tint(.orange).frame(width: 80)
            }
            if let avg {
                VStack(alignment: .leading, spacing: 2) {
                    caption(isChinese ? "全组" : "Group")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(def.text(avg, chinese: isChinese)).font(.title3.weight(.bold)).monospacedDigit()
                        if let thenAvg { arrow(avg, thenAvg) }
                    }
                    if let thenAvg {
                        Text((isChinese ? "上次 " : "last time ") + def.text(thenAvg, chinese: isChinese))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let best, let v = run.result(for: best.id) {
                VStack(alignment: .leading, spacing: 4) {
                    caption(isChinese ? "今日最佳" : "Best today")
                    HStack(spacing: 6) {
                        StudentAvatarView(student: best, size: 22)
                        Text(best.primaryDisplayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(def.text(v, chinese: isChinese)).font(.subheadline.weight(.bold)).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func arrow(_ now: Double, _ then: Double) -> some View {
        if abs(now - then) > 0.0001 {
            let better = def.better(now, than: then)
            Image(systemName: better ? "arrow.up" : "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(better ? .green : .red)
        }
    }

    private func table(_ last: [UUID: Double]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                caption(isChinese ? "学员" : "Athlete")
                Spacer()
                if def.spots.count > 1 {
                    ForEach(0..<def.spotCount, id: \.self) { i in
                        caption(def.spotName(i, chinese: isChinese)).frame(width: 64)
                    }
                }
                caption(isChinese ? "结果" : "Result").frame(width: 90, alignment: .trailing)
            }
            .padding(.bottom, 8)
            ForEach(students) { s in
                HStack(spacing: 6) {
                    StudentAvatarView(student: s, size: 30)
                    Text(s.primaryDisplayName).font(.body).lineLimit(1)
                    Spacer(minLength: 4)
                    ForEach(0..<def.spotCount, id: \.self) { i in
                        cell(s, spot: i)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        if let v = run.result(for: s.id) {
                            HStack(spacing: 3) {
                                Text(def.text(v, chinese: isChinese)).font(.body.weight(.semibold)).monospacedDigit()
                                if let l = last[s.id] { arrow(v, l) }
                            }
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                        if let l = last[s.id] {
                            Text((isChinese ? "上次 " : "last ") + def.text(l, chinese: isChinese))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 6)
                Divider().padding(.leading, 36)
            }
        }
    }

    private func cell(_ s: Student, spot: Int) -> some View {
        let v = run.value(for: s.id, spot: spot)
        let here = PadCell(student: s.id, spot: spot)
        let editing = active == here
        return Button {
            guard canEdit else { return }
            open(here)
        } label: {
            Text(editing ? (draft.text.isEmpty ? "·" : draft.text) : (v.map { def.entryText($0) } ?? "·"))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(width: 64, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(v == nil ? Color(.tertiarySystemFill) : Color.orange.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(editing ? Color.orange : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .cellNumberPad(isPresented: presented(here), draft: $draft, identifier: "track.keys",
                       onConfirm: { confirm(here) }, onClosed: openPending)
        .accessibilityIdentifier("track.cell")
        .accessibilityLabel("\(s.primaryDisplayName) \(def.spotName(spot, chinese: isChinese)) \(v.map { def.entryText($0) } ?? "—")")
    }

    // MARK: The number pad on a cell

    private func open(_ cell: PadCell) {
        draft = .cell(run.value(for: cell.student, spot: cell.spot), maximum: Double(def.maxEntry),
                      decimals: def.measure == .timeToFinish ? 1 : 0)
        active = cell
    }

    private func presented(_ cell: PadCell) -> Binding<Bool> {
        Binding(get: { active == cell }, set: { on in
            guard !on, active == cell else { return }
            commit(cell)
            active = nil
        })
    }

    private func commit(_ cell: PadCell) {
        guard draft.typed else { return }
        run.set(draft.text.isEmpty ? nil : draft.value, for: cell.student, spot: cell.spot)
    }

    private func confirm(_ cell: PadCell) {
        commit(cell)
        let next = nextEmpty(after: cell)
        pending = next
        active = nil
    }

    private func openPending() {
        guard let next = pending else { return }
        pending = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { open(next) }
    }

    /// This athlete's next empty spot, then the next athlete's.
    private func nextEmpty(after cell: PadCell?) -> PadCell? {
        let order = students.map(\.id)
        if let cell, let i = run.values(for: cell.student).firstIndex(where: { $0 == nil }) {
            return PadCell(student: cell.student, spot: i)
        }
        let start = cell.flatMap { order.firstIndex(of: $0.student) }.map { $0 + 1 } ?? 0
        let from = min(start, order.count)
        for id in order[from...] + order[..<from] {
            if let i = run.values(for: id).firstIndex(where: { $0 == nil }) { return PadCell(student: id, spot: i) }
        }
        return nil
    }

    private func openAtNext() {
        if let next = nextEmpty(after: nil) { open(next) }
        else if let first = students.first { open(PadCell(student: first.id, spot: 0)) }
    }

    // MARK: Stopwatch (time to finish)

    private var elapsed: Double { startedAt.map { now.timeIntervalSince($0) } ?? 0 }

    /// Start, stop: the time goes into the next athlete's cell (named here).
    private var stopwatch: some View {
        let target = active ?? nextEmpty(after: nil)
        let who = target.flatMap { t in students.first { $0.id == t.student } }
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TrackDefinition.seconds(elapsed))
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("track.stopwatch.time")
                if let who {
                    Text((isChinese ? "下一位：" : "Next: ") + who.primaryDisplayName
                         + (def.spotCount > 1 ? " · \(def.spotName(target?.spot ?? 0, chinese: isChinese))" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if let startedAt {
                    let t = (Date().timeIntervalSince(startedAt) * 10).rounded() / 10
                    self.startedAt = nil
                    AudioServicesPlaySystemSound(1104)
                    if let target { run.set(t, for: target.student, spot: target.spot); active = nil }
                } else {
                    startedAt = Date(); now = Date()
                }
            } label: {
                Text(startedAt == nil ? (isChinese ? "开始" : "Start") : (isChinese ? "停止" : "Stop"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 110, minHeight: 50)
                    .background(Capsule().fill(startedAt == nil ? Color.green : Color.red))
            }
            .buttonStyle(.plain)
            .disabled(target == nil && startedAt == nil)
            .accessibilityIdentifier("track.stopwatch")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
