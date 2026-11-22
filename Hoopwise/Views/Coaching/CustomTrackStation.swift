import SwiftUI
import AudioToolbox
import Combine

// THE COACH'S OWN TRACKED DRILLS IN A SESSION (23 Nov 2026 — definition and
// maths in Models/CustomTracking.swift). Same shape as the built-in shooting
// drills: one tracker line on the drill's plan row → a station page (summary,
// table, Log) → a pad that takes one athlete's number and moves on. The pad
// fits the measure: a grid or wheel for makes and counts, a stopwatch (and
// wheels to correct it) for a time.

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

    @State private var pad: PadStart?
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var def: TrackDefinition { run.definition }

    struct PadStart: Identifiable {
        let id = UUID()
        let student: UUID
        let spot: Int
    }

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
            .sheet(item: $pad) { start in
                CustomTrackPad(drillId: drillId, run: $run, students: students, last: last,
                               student: start.student, spot: start.spot)
                    .presentationDetents([.large])
                    .environmentObject(dataManager)
            }
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
        return Button {
            guard canEdit else { return }
            pad = PadStart(student: s.id, spot: spot)
        } label: {
            Text(v.map { def.entryText($0) } ?? "·")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(width: 64, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(v == nil ? Color(.tertiarySystemFill) : Color.orange.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("track.cell")
        .accessibilityLabel("\(s.primaryDisplayName) \(def.spotName(spot, chinese: isChinese)) \(v.map { def.entryText($0) } ?? "—")")
    }

    private func openAtNext() {
        for s in students {
            for i in 0..<def.spotCount where run.value(for: s.id, spot: i) == nil {
                pad = PadStart(student: s.id, spot: i); return
            }
        }
        if let first = students.first { pad = PadStart(student: first.id, spot: 0) }
    }
}

/// One athlete's number at one spot, then the next.
struct CustomTrackPad: View {
    @Environment(\.dismiss) private var dismiss
    let drillId: UUID
    @Binding var run: TrackedRun
    let students: [Student]
    let last: [UUID: Double]
    @State var student: UUID
    @State var spot: Int

    @State private var number = 0
    @State private var tenths = 0
    /// Stopwatch (time to finish).
    @State private var startedAt: Date?
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var def: TrackDefinition { run.definition }
    private var useGrid: Bool { def.measure == .madeOf && def.amount <= 10 }

    init(drillId: UUID, run: Binding<TrackedRun>, students: [Student], last: [UUID: Double], student: UUID, spot: Int) {
        self.drillId = drillId
        _run = run
        self.students = students
        self.last = last
        _student = State(initialValue: student)
        _spot = State(initialValue: spot)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    athletes
                    if def.spotCount > 1 { spotChips }
                    current
                    entry
                }
                .padding(16)
            }
            .navigationTitle(def.measure.title(chinese: isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .accessibilityIdentifier("track.pad.done")
                }
            }
            .onAppear(perform: prepare)
            .onReceive(tick) { if startedAt != nil { now = $0 } }
        }
    }

    // MARK: Who and where

    private var athletes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(students) { s in
                    let done = run.result(for: s.id) != nil
                    Button {
                        student = s.id
                        spot = run.values(for: s.id).firstIndex { $0 == nil } ?? 0
                        prepare()
                    } label: {
                        VStack(spacing: 4) {
                            StudentAvatarView(student: s, size: 48)
                                .overlay(Circle().strokeBorder(s.id == student ? Color.orange : .clear, lineWidth: 3).padding(-3))
                                .opacity(done && s.id != student ? 0.45 : 1)
                            Text(s.primaryDisplayName).font(.caption2).lineLimit(1).frame(width: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("track.pad.athlete")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var spotChips: some View {
        HStack(spacing: 8) {
            ForEach(0..<def.spotCount, id: \.self) { i in
                Button {
                    spot = i; prepare()
                } label: {
                    Text(def.spotName(i, chinese: isChinese))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(Capsule().fill(i == spot ? Color.orange : Color(.tertiarySystemFill)))
                        .foregroundStyle(i == spot ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var current: some View {
        let s = students.first { $0.id == student }
        return VStack(spacing: 4) {
            Text(s?.primaryDisplayName ?? "").font(.title2.weight(.bold))
            HStack(spacing: 6) {
                if def.spotCount > 1 { Text(def.spotName(spot, chinese: isChinese)) }
                if let l = last[student] {
                    Text((isChinese ? "上次 " : "Last time ") + def.text(l, chinese: isChinese))
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Entry

    @ViewBuilder
    private var entry: some View {
        switch def.measure {
        case .timeToFinish: stopwatch
        default:
            if useGrid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(0...def.amount, id: \.self) { n in
                        Button { save(Double(n)) } label: {
                            Text("\(n)").font(.title2.weight(.bold)).monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(run.value(for: student, spot: spot) == Double(n) ? Color.orange : Color(.secondarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("track.pad.\(n)")
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Text("\(number)" + (def.measure == .madeOf ? " / \(def.amount)" : ""))
                        .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                    NumberWheel(range: 0...def.maxEntry, value: $number, identifier: "track.wheel")
                        .frame(height: 64)
                    logButton { save(Double(number)) }
                }
            }
        }
    }

    private var elapsed: Double {
        guard let startedAt else { return Double(number) + Double(tenths) / 10 }
        return now.timeIntervalSince(startedAt)
    }

    private var stopwatch: some View {
        VStack(spacing: 16) {
            Text(TrackDefinition.seconds(elapsed))
                .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("track.stopwatch.time")
            Button {
                if let startedAt {
                    let t = Date().timeIntervalSince(startedAt)
                    self.startedAt = nil
                    number = Int(t); tenths = Int(((t - Double(Int(t))) * 10).rounded(.down))
                    AudioServicesPlaySystemSound(1104)
                } else {
                    startedAt = Date(); now = Date()
                }
            } label: {
                Text(startedAt == nil ? (isChinese ? "开始" : "Start") : (isChinese ? "停止" : "Stop"))
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(startedAt == nil ? Color.green : Color.red))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("track.stopwatch")
            if startedAt == nil {
                HStack(spacing: 0) {
                    Picker(isChinese ? "秒" : "Seconds", selection: $number) {
                        ForEach(0...def.maxEntry, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Text(".").font(.title.weight(.bold))
                    Picker(isChinese ? "十分之一秒" : "Tenths", selection: $tenths) {
                        ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    Text("s").font(.title3).foregroundStyle(.secondary)
                }
                .frame(height: 130)
                logButton { save(Double(number) + Double(tenths) / 10) }
            }
        }
    }

    private func logButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isChinese ? "记录" : "Log")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("track.pad.log")
    }

    /// Starts on what is in, else this athlete's last time, else the
    /// others' median here today, else half (made of) or 0.
    private func prepare() {
        startedAt = nil
        let others = students.compactMap { run.value(for: $0.id, spot: spot) }.sorted()
        let median = others.isEmpty ? nil : others[others.count / 2]
        let v = run.value(for: student, spot: spot)
            ?? last[student].map { def.measure == .madeOf ? ($0 * Double(def.amount)).rounded() : $0 }
            ?? median
            ?? (def.measure == .madeOf ? Double(def.amount / 2) : 0)
        number = min(def.maxEntry, max(0, Int(v)))
        tenths = Int(((v - Double(Int(v))) * 10).rounded())
        if tenths > 9 { tenths = 9 }
    }

    private func save(_ value: Double) {
        run.set(value, for: student, spot: spot)
        // Next: this athlete's next empty spot, then the next athlete's.
        if let i = run.values(for: student).firstIndex(where: { $0 == nil }) {
            spot = i; prepare(); return
        }
        let order = students.map(\.id)
        let start = (order.firstIndex(of: student) ?? 0) + 1
        for id in order[min(start, order.count)...] + order[..<min(start, order.count)] {
            if let i = run.values(for: id).firstIndex(where: { $0 == nil }) {
                student = id; spot = i; prepare(); return
            }
        }
        dismiss()
    }
}
