import SwiftUI
import AudioToolbox
import Combine

// THE SHOOTING ADD-ON (20 Nov 2026, Luther). A tracked shooting drill in the
// plan shows this card: how it is scored (made out of N a spot, or makes in
// N seconds a spot — one clock per spot), every athlete with a cell per spot,
// and a number pad for the self-reported makes. In a group the athletes come
// and say a number; one tap on the pad writes it and moves on — to the next
// spot of the same athlete (made out of N: each shoots all five then
// reports) or to the next athlete at the same spot (timed: everyone reports
// after each clock). Results → SessionCurriculum.shooting (ShootingRun).

struct ShootingAddOnCard: View {
    let drill: ShootingDrill
    @Binding var run: ShootingRun
    let students: [Student]
    /// The session's start, for "last time".
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool

    @State private var entry: EntryTarget?
    @State private var clockSpot = 0
    @State private var remaining: Int?
    @State private var running = false
    @State private var buzz = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    struct EntryTarget: Identifiable, Equatable {
        let student: UUID
        let spot: Int
        var id: String { "\(student)-\(spot)" }
    }

    private var setup: ShootingSetup { run.setup }
    private var locked: Bool { !run.entries.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if setup.mode == .timed && canEdit { clock }
            if students.isEmpty {
                Text(isChinese ? "这节课还没有学员。" : "No athletes on this session yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(students) { athleteRow($0) }
                }
                groupLine
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
        .sheet(item: $entry) { target in
            ShootingEntryPad(drill: drill, setup: setup, run: $run, students: students,
                             start: target, order: setup.mode == .timed ? .spotFirst : .athleteFirst)
                .presentationDetents([.medium, .large])
        }
        .onReceive(tick) { _ in
            guard running, let r = remaining else { return }
            if r <= 1 {
                remaining = 0; running = false; buzz += 1
                AudioServicesPlayAlertSound(SystemSoundID(1005))
            } else {
                remaining = r - 1
            }
        }
        .sensoryFeedback(.warning, trigger: buzz)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shooting.addon.\(drill.rawValue)")
    }

    // MARK: Header — what it is and how it is scored

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title(chinese: isChinese).uppercased())
                    .font(.subheadline.weight(.bold))
                Text(locked ? setup.summary(chinese: isChinese)
                     : setup.summary(chinese: isChinese) + (isChinese ? " · 点此更改" : " · tap to change"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canEdit && !locked { setupMenu }
        }
    }

    private var setupMenu: some View {
        Menu {
            Picker(isChinese ? "计分方式" : "Scoring", selection: setupBinding(\.mode)) {
                Text(isChinese ? "命中 / 出手" : "Made out of shots").tag(ShootingMode.attempts)
                Text(isChinese ? "限时命中" : "Makes in a set time").tag(ShootingMode.timed)
            }
            if setup.mode == .attempts {
                Picker(drill.spotCount > 1 ? (isChinese ? "每点出手" : "Shots a spot") : (isChinese ? "出手数" : "Shots"),
                       selection: setupBinding(\.shots)) {
                    ForEach([5, 10, 15, 20, 25], id: \.self) { Text("\($0)").tag($0) }
                }
            } else {
                Picker(drill.spotCount > 1 ? (isChinese ? "每点时间" : "Time a spot") : (isChinese ? "时间" : "Time"),
                       selection: setupBinding(\.seconds)) {
                    ForEach([20, 30, 45, 60, 90, 120], id: \.self) { Text(ShootingSetup.time($0, chinese: isChinese)).tag($0) }
                }
            }
            if drill == .twos {
                Picker(isChinese ? "距离" : "Range", selection: setupBinding(\.range)) {
                    ForEach(TwosRange.allCases, id: \.self) { Text($0.title(chinese: isChinese)).tag(Optional($0)) }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .accessibilityIdentifier("shooting.setup")
    }

    private func setupBinding<T>(_ path: WritableKeyPath<ShootingSetup, T>) -> Binding<T> {
        Binding(get: { run.setup[keyPath: path] },
                set: { run.setup[keyPath: path] = $0; run.setup.remember(); remaining = nil })
    }

    // MARK: Clock — one per spot

    private var clock: some View {
        let total = setup.seconds
        let left = remaining ?? total
        return HStack(spacing: 10) {
            if drill.spotCount > 1 {
                Button { moveClock(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(clockSpot == 0 || running)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isChinese ? "第 \(clockSpot + 1) 点" : "SPOT \(clockSpot + 1) OF \(drill.spotCount)")
                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(drill.spotName(clockSpot, chinese: isChinese)).font(.subheadline.weight(.semibold))
                }
                Button { moveClock(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(clockSpot >= drill.spotCount - 1 || running)
            }
            Spacer()
            Text(String(format: "%d:%02d", left / 60, left % 60))
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(left == 0 ? .red : (left <= 5 && running ? .orange : .primary))
                .contentTransition(.numericText())
            Button {
                if left == 0 {
                    // Time's up: write the makes for this spot.
                    if let first = students.first(where: { run.makes($0.id, spot: clockSpot) == nil }) ?? students.first {
                        entry = EntryTarget(student: first.id, spot: clockSpot)
                    }
                } else {
                    if remaining == nil { remaining = total }
                    running.toggle()
                }
            } label: {
                Image(systemName: left == 0 ? "square.and.pencil" : (running ? "pause.fill" : "play.fill"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(left == 0 ? Color.accentColor : (running ? Color.orange : Color.green)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shooting.clock")
            if remaining != nil && !running {
                Button { remaining = nil } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill).opacity(0.6)))
    }

    private func moveClock(_ d: Int) {
        clockSpot = min(max(0, clockSpot + d), drill.spotCount - 1)
        remaining = nil
        running = false
    }

    // MARK: Athletes

    private func athleteRow(_ student: Student) -> some View {
        let result = run.result(for: student.id)
        let last = ShootingHistory.previous(student.id, setup: setup, before: sessionDate, sessions: allSessions)
        return HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(student.primaryDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let last {
                    Text((isChinese ? "上次 " : "Last ") + last.text)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 90, alignment: .leading)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(0..<drill.spotCount, id: \.self) { spot in
                    cell(student: student.id, spot: spot)
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(result?.text ?? "—")
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(result == nil ? .tertiary : .primary)
                if let result, let last {
                    let up = result.value > last.value
                    let same = abs(result.value - last.value) < 0.0001
                    Image(systemName: same ? "equal" : (up ? "arrow.up" : "arrow.down"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(same ? Color.secondary : (up ? Color.green : Color.red))
                }
            }
            .frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shooting.athlete")
    }

    private func cell(student: UUID, spot: Int) -> some View {
        let value = run.makes(student, spot: spot)
        return Button {
            guard canEdit else { return }
            entry = EntryTarget(student: student, spot: spot)
        } label: {
            VStack(spacing: 0) {
                Text(value.map(String.init) ?? "–")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(value == nil ? .tertiary : .primary)
                if drill.spotCount > 1 {
                    Text(drill.spotShort(spot, chinese: isChinese))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: drill.spotCount > 1 ? 36 : 52, height: 38)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(value == nil ? Color(.tertiarySystemFill) : Color.orange.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(drill.spotName(spot, chinese: isChinese)) \(value.map(String.init) ?? "")")
        .accessibilityIdentifier("shooting.cell")
    }

    /// The group today vs the same athletes last time.
    @ViewBuilder
    private var groupLine: some View {
        let today = students.compactMap { run.result(for: $0.id)?.value }
        if today.count >= 2 {
            let avg = today.reduce(0, +) / Double(today.count)
            let lasts = students.filter { run.result(for: $0.id) != nil }
                .compactMap { ShootingHistory.previous($0.id, setup: setup, before: sessionDate, sessions: allSessions)?.value }
            HStack(spacing: 6) {
                Text(isChinese ? "全组 \(ShootingResult.text(avg, mode: setup.mode, chinese: true))"
                               : "Group \(ShootingResult.text(avg, mode: setup.mode, chinese: false))")
                    .font(.footnote.weight(.semibold))
                if lasts.count >= 2 {
                    let then = lasts.reduce(0, +) / Double(lasts.count)
                    Text(isChinese ? "· 上次 \(ShootingResult.text(then, mode: setup.mode, chinese: true))"
                                   : "· last time \(ShootingResult.text(then, mode: setup.mode, chinese: false))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - The number pad

/// One tap writes the athlete's makes and moves on.
struct ShootingEntryPad: View {
    enum Order { case athleteFirst, spotFirst }

    let drill: ShootingDrill
    let setup: ShootingSetup
    @Binding var run: ShootingRun
    let students: [Student]
    let order: Order
    @State private var target: ShootingAddOnCard.EntryTarget
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    init(drill: ShootingDrill, setup: ShootingSetup, run: Binding<ShootingRun>, students: [Student],
         start: ShootingAddOnCard.EntryTarget, order: Order) {
        self.drill = drill; self.setup = setup; _run = run; self.students = students; self.order = order
        _target = State(initialValue: start)
    }

    private var student: Student? { students.first { $0.id == target.student } }
    private var maximum: Int {
        setup.mode == .attempts ? setup.shots : max(20, (run.entries.flatMap { $0.makes.compactMap { $0 } }.max() ?? 0) + 5)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                    .accessibilityIdentifier("shooting.pad.back")
                Spacer()
                if let student {
                    StudentAvatarView(student: student, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student.primaryDisplayName).font(.headline).lineLimit(1)
                        Text(drill.spotCount > 1
                             ? "\(drill.spotName(target.spot, chinese: isChinese)) · " + (setup.mode == .attempts
                                 ? (isChinese ? "\(setup.shots) 投中几个？" : "made of \(setup.shots)?")
                                 : (isChinese ? "\(ShootingSetup.time(setup.seconds, chinese: true)) 进了几个？" : "makes in \(ShootingSetup.time(setup.seconds, chinese: false))?"))
                             : (setup.mode == .attempts
                                 ? (isChinese ? "\(setup.shots) 投中几个？" : "made of \(setup.shots)?")
                                 : (isChinese ? "进了几个？" : "how many made?")))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.title3.weight(.semibold)) }
                    .accessibilityIdentifier("shooting.pad.next")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(0...maximum, id: \.self) { n in
                        let current = run.makes(target.student, spot: target.spot) == n
                        Button {
                            run.set(n, for: target.student, spot: target.spot)
                            advance()
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(current ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(current ? Color.orange : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shooting.pad.\(n)")
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Button(role: .destructive) {
                    run.set(nil, for: target.student, spot: target.spot)
                } label: {
                    Label(isChinese ? "清除" : "Clear", systemImage: "delete.left")
                }
                .disabled(run.makes(target.student, spot: target.spot) == nil)
                Spacer()
                Text(progressText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(isChinese ? "完成" : "Done") { dismiss() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("shooting.pad.done")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .sensoryFeedback(.selection, trigger: target)
    }

    private var progressText: String {
        let filled = students.reduce(0) { sum, s in
            sum + (0..<drill.spotCount).filter { run.makes(s.id, spot: $0) != nil }.count
        }
        let total = students.count * drill.spotCount
        return isChinese ? "已记 \(filled)/\(total)" : "\(filled) of \(total) logged"
    }

    /// The order the coach walks: athlete by athlete (all their spots), or
    /// spot by spot (everyone at this spot).
    private var sequence: [ShootingAddOnCard.EntryTarget] {
        let ids = students.map(\.id)
        let spots = Array(0..<drill.spotCount)
        switch order {
        case .athleteFirst: return ids.flatMap { id in spots.map { .init(student: id, spot: $0) } }
        case .spotFirst: return spots.flatMap { spot in ids.map { .init(student: $0, spot: spot) } }
        }
    }

    private func step(_ d: Int) {
        let seq = sequence
        guard let i = seq.firstIndex(of: target) else { return }
        let j = i + d
        if seq.indices.contains(j) { target = seq[j] }
    }

    /// Next empty cell in the walking order (after this one); the end closes.
    private func advance() {
        let seq = sequence
        guard let i = seq.firstIndex(of: target) else { dismiss(); return }
        // Timed: the clock is per spot — stay on this spot's round.
        let rest = seq[(i + 1)...].filter { order == .athleteFirst || $0.spot == target.spot }
        if let next = rest.first(where: { run.makes($0.student, spot: $0.spot) == nil }) {
            target = next
        } else {
            dismiss()
        }
    }
}
