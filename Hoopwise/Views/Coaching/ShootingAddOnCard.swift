import SwiftUI
import AudioToolbox
import Combine

// THE SHOOTING ADD-ON (20 Nov 2026, Luther; reworked the next day for groups
// of a dozen: "data visibility, interactivity, ease of use"). A tracked
// shooting drill in the plan shows this card:
// · a SUMMARY that is readable folded — logged n/N, the group today against
//   the same athletes last time, today's best;
// · for timed drills, ONE CLOCK PER SPOT with a buzzer;
// · a TABLE — spot columns labelled once, each cell tinted by its value (a
//   heat map), the result and ↑/↓ against last time, a footer with the
//   group's average per spot; sort by roster, best first or still to log;
// · LOG MAKES opens the pad on the next empty cell. Athletes self-report in
//   any order, so the pad shows everyone as photos: tap whoever walked up,
//   tap their number — it moves on by itself (made of N: that athlete's next
//   spot; timed: the next athlete at the clock's spot).
// Results → SessionCurriculum.shooting (ShootingRun).

struct ShootingAddOnCard: View {
    let drill: ShootingDrill
    @Binding var run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool

    @State private var pad: PadStart?
    @State private var expanded = true
    @State private var clockSpot = 0
    @State private var remaining: Int?
    @State private var running = false
    @State private var buzz = 0
    @AppStorage("shooting.sort") private var sortRaw = Sort.roster.rawValue
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    enum Sort: String, CaseIterable { case roster, best, toLog }

    struct PadStart: Identifiable {
        let id = UUID()
        let student: UUID
        let spot: Int
    }

    private var setup: ShootingSetup { run.setup }
    private var locked: Bool { !run.entries.isEmpty }
    private var sort: Sort { Sort(rawValue: sortRaw) ?? .roster }

    /// Each athlete's result in this test last time (computed once a draw).
    private var lastTime: [UUID: ShootingResult] {
        var out: [UUID: ShootingResult] = [:]
        for s in students {
            if let r = ShootingHistory.previous(s.id, setup: setup, before: sessionDate, sessions: allSessions) { out[s.id] = r }
        }
        return out
    }

    var body: some View {
        let last = lastTime
        VStack(alignment: .leading, spacing: 14) {
            header
            summary(last)
            if expanded {
                if setup.mode == .timed && canEdit { clock }
                if students.isEmpty {
                    Text(isChinese ? "这节课还没有学员。" : "No athletes on this session yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    table(last)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.orange.opacity(0.22), lineWidth: 1))
        .sheet(item: $pad) { start in
            ShootingEntryPad(drill: drill, setup: setup, run: $run, students: students,
                             student: start.student, spot: start.spot,
                             timedSpot: setup.mode == .timed ? clockSpot : nil)
                .presentationDetents([.large])
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: drill.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title(chinese: isChinese).uppercased())
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(setup.summary(chinese: isChinese))
                    if canEdit && !locked { setupMenu }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if canEdit && !students.isEmpty {
                Button {
                    openPadAtNext()
                } label: {
                    Label(isChinese ? "记录" : "Log makes", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .accessibilityIdentifier("shooting.log")
            }
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? (isChinese ? "收起" : "Fold") : (isChinese ? "展开" : "Unfold"))
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
                    ForEach([5, 10, 15, 20, 25, 30, 50], id: \.self) { Text("\($0)").tag($0) }
                }
            } else {
                Picker(drill.spotCount > 1 ? (isChinese ? "每点时间" : "Time a spot") : (isChinese ? "时间" : "Time"),
                       selection: setupBinding(\.seconds)) {
                    ForEach([20, 30, 45, 60, 90, 120, 180], id: \.self) { Text(ShootingSetup.time($0, chinese: isChinese)).tag($0) }
                }
            }
            if drill == .twos {
                Picker(isChinese ? "距离" : "Range", selection: setupBinding(\.range)) {
                    ForEach(TwosRange.allCases, id: \.self) { Text($0.title(chinese: isChinese)).tag(Optional($0)) }
                }
            }
        } label: {
            Label(isChinese ? "更改" : "Change", systemImage: "slider.horizontal.3")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityIdentifier("shooting.setup")
    }

    private func setupBinding<T>(_ path: WritableKeyPath<ShootingSetup, T>) -> Binding<T> {
        Binding(get: { run.setup[keyPath: path] },
                set: { run.setup[keyPath: path] = $0; run.setup.remember(); remaining = nil })
    }

    // MARK: Summary — readable folded

    private func summary(_ last: [UUID: ShootingResult]) -> some View {
        let logged = students.filter { run.result(for: $0.id) != nil }
        let today = logged.compactMap { run.result(for: $0.id)?.value }
        let avg = today.isEmpty ? nil : today.reduce(0, +) / Double(today.count)
        let then = logged.compactMap { last[$0.id]?.value }
        let thenAvg = then.count >= 2 ? then.reduce(0, +) / Double(then.count) : nil
        let best = logged.max { (run.result(for: $0.id)?.value ?? 0) < (run.result(for: $1.id)?.value ?? 0) }
        return HStack(alignment: .top, spacing: 18) {
            figure(isChinese ? "已记录" : "Logged", "\(logged.count)/\(students.count)",
                   progress: students.isEmpty ? 0 : Double(logged.count) / Double(students.count))
            if let avg {
                VStack(alignment: .leading, spacing: 2) {
                    caption(isChinese ? "全组" : "Group")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ShootingResult.text(avg, mode: setup.mode, chinese: isChinese))
                            .font(.title3.weight(.bold)).monospacedDigit()
                        if let thenAvg { delta(avg, thenAvg) }
                    }
                    if let thenAvg {
                        Text((isChinese ? "上次 " : "last time ") + ShootingResult.text(thenAvg, mode: setup.mode, chinese: isChinese))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let best, logged.count >= 2, let r = run.result(for: best.id) {
                VStack(alignment: .leading, spacing: 2) {
                    caption(isChinese ? "今日最佳" : "Best today")
                    HStack(spacing: 6) {
                        StudentAvatarView(student: best, size: 22)
                        Text(firstName(best)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(r.text).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func figure(_ title: String, _ value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption(title)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            ProgressView(value: progress).tint(.orange).frame(width: 64)
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func delta(_ now: Double, _ then: Double) -> some View {
        let same = abs(now - then) < 0.0001
        let up = now > then
        return Image(systemName: same ? "equal" : (up ? "arrow.up" : "arrow.down"))
            .font(.caption.weight(.bold))
            .foregroundStyle(same ? Color.secondary : (up ? Color.green : Color.red))
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
                    Text(isChinese ? "第 \(clockSpot + 1)/\(drill.spotCount) 点" : "SPOT \(clockSpot + 1) OF \(drill.spotCount)")
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
                    // Time's up: log this spot.
                    let first = students.first { run.makes($0.id, spot: clockSpot) == nil } ?? students.first
                    if let first { pad = PadStart(student: first.id, spot: clockSpot) }
                } else {
                    if remaining == nil { remaining = total }
                    running.toggle()
                }
            } label: {
                Image(systemName: left == 0 ? "square.and.pencil" : (running ? "pause.fill" : "play.fill"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(left == 0 ? Color.orange : (running ? Color.orange : Color.green)))
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

    // MARK: Table

    private var cellWidth: CGFloat {
        switch drill.spotCount { case 5: 38; case 2: 52; default: 60 }
    }

    private func sorted(_ last: [UUID: ShootingResult]) -> [Student] {
        switch sort {
        case .roster: return students
        case .best:
            return students.sorted { (run.result(for: $0.id)?.value ?? -1) > (run.result(for: $1.id)?.value ?? -1) }
        case .toLog:
            return students.sorted { a, b in
                let fa = filled(a.id), fb = filled(b.id)
                return fa != fb ? fa < fb : false
            }
        }
    }

    private func filled(_ id: UUID) -> Int { (0..<drill.spotCount).filter { run.makes(id, spot: $0) != nil }.count }

    private func table(_ last: [UUID: ShootingResult]) -> some View {
        VStack(spacing: 0) {
            // Column heads, once.
            HStack(spacing: 4) {
                Menu {
                    Picker("", selection: $sortRaw) {
                        Text(isChinese ? "名单顺序" : "Roster order").tag(Sort.roster.rawValue)
                        Text(isChinese ? "成绩最好在前" : "Best first").tag(Sort.best.rawValue)
                        Text(isChinese ? "待记录在前" : "Still to log first").tag(Sort.toLog.rawValue)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(isChinese ? "学员" : "ATHLETE")
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("shooting.sort")
                Spacer(minLength: 4)
                ForEach(0..<drill.spotCount, id: \.self) { spot in
                    Text(drill.spotShort(spot, chinese: isChinese))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: cellWidth)
                }
                Text(isChinese ? "成绩" : "RESULT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.bottom, 6)

            ForEach(Array(sorted(last).enumerated()), id: \.element.id) { i, student in
                if i > 0 { Divider().padding(.leading, 36) }
                athleteRow(student, last: last[student.id])
            }

            if students.filter({ run.result(for: $0.id) != nil }).count >= 2 {
                Divider().padding(.top, 4)
                spotFooter
            }
        }
    }

    private func athleteRow(_ student: Student, last: ShootingResult?) -> some View {
        let result = run.result(for: student.id)
        return HStack(spacing: 4) {
            StudentAvatarView(student: student, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(student.primaryDisplayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let last {
                    Text((isChinese ? "上次 " : "last ") + last.text)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)
            Spacer(minLength: 4)
            ForEach(0..<drill.spotCount, id: \.self) { spot in
                cell(student: student.id, spot: spot)
            }
            HStack(spacing: 3) {
                if let result, let last { delta(result.value, last.value) }
                Text(result?.text ?? "—")
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(result == nil ? .tertiary : .primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shooting.athlete")
    }

    /// 0…1 strength of a cell, for the heat tint.
    private func strength(_ makes: Int) -> Double {
        switch setup.mode {
        case .attempts: return Double(makes) / Double(max(setup.shots, 1))
        case .timed:
            let top = run.entries.flatMap { $0.makes.compactMap { $0 } }.max() ?? 1
            return Double(makes) / Double(max(top, 1))
        }
    }

    private func cell(student: UUID, spot: Int) -> some View {
        let value = run.makes(student, spot: spot)
        return Button {
            guard canEdit else { return }
            pad = PadStart(student: student, spot: spot)
        } label: {
            Text(value.map(String.init) ?? "·")
                .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .frame(width: cellWidth, height: 32)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(value.map { Color.orange.opacity(0.12 + 0.55 * strength($0)) } ?? Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(drill.spotName(spot, chinese: isChinese)) \(value.map(String.init) ?? "")")
        .accessibilityIdentifier("shooting.cell")
    }

    /// The group's average per spot — where it shoots well and where not.
    private var spotFooter: some View {
        HStack(spacing: 4) {
            Text(isChinese ? "各点平均" : "SPOT AVERAGE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            ForEach(0..<drill.spotCount, id: \.self) { spot in
                let values = students.compactMap { run.result(for: $0.id)?.spotValue(spot) }
                let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                Text(avg.map { setup.mode == .attempts ? "\(Int(($0 * 100).rounded()))%" : String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .frame(width: cellWidth, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
            }
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.top, 8)
    }

    private func firstName(_ s: Student) -> String {
        let name = s.primaryDisplayName
        return isChinese ? name : (name.components(separatedBy: " ").first ?? name)
    }

    private func openPadAtNext() {
        if setup.mode == .timed {
            let first = students.first { run.makes($0.id, spot: clockSpot) == nil } ?? students.first
            if let first { pad = PadStart(student: first.id, spot: clockSpot) }
            return
        }
        for s in students {
            if let spot = (0..<drill.spotCount).first(where: { run.makes(s.id, spot: $0) == nil }) {
                pad = PadStart(student: s.id, spot: spot); return
            }
        }
        if let first = students.first { pad = PadStart(student: first.id, spot: 0) }
    }
}

// MARK: - The pad

/// Everyone as photos, the spot, and the numbers. Tap whoever is in front of
/// you, tap their makes — it moves on by itself.
struct ShootingEntryPad: View {
    let drill: ShootingDrill
    let setup: ShootingSetup
    @Binding var run: ShootingRun
    let students: [Student]
    /// Timed: the clock's spot — everyone reports that spot.
    let timedSpot: Int?
    @State private var student: UUID
    @State private var spot: Int
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    init(drill: ShootingDrill, setup: ShootingSetup, run: Binding<ShootingRun>, students: [Student],
         student: UUID, spot: Int, timedSpot: Int?) {
        self.drill = drill; self.setup = setup; _run = run; self.students = students; self.timedSpot = timedSpot
        _student = State(initialValue: student)
        _spot = State(initialValue: spot)
    }

    private var maximum: Int {
        setup.mode == .attempts ? setup.shots : max(20, (run.entries.flatMap { $0.makes.compactMap { $0 } }.max() ?? 0) + 5)
    }

    private var current: Student? { students.first { $0.id == student } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if drill.spotCount > 1 { spotPicker }
                    athletes
                    Text(progressText)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    prompt
                    keypad
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle(drill.title(chinese: isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("shooting.pad.done")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: student)
    }

    private var spotPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<drill.spotCount, id: \.self) { i in
                let on = spot == i
                Button { spot = i } label: {
                    Text(drill.spotName(i, chinese: isChinese))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? Color.orange : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shooting.pad.spot.\(i)")
            }
        }
    }

    /// Everyone, as they come: a number badge when this spot is in.
    private var athletes: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 12) {
            ForEach(students) { s in
                let value = run.makes(s.id, spot: spot)
                let on = s.id == student
                Button { student = s.id } label: {
                    VStack(spacing: 4) {
                        StudentAvatarView(student: s, size: 52)
                            .overlay(Circle().strokeBorder(on ? Color.orange : .clear, lineWidth: 3).padding(-4))
                            .overlay(alignment: .topTrailing) {
                                if let value {
                                    Text("\(value)")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 22, minHeight: 22)
                                        .background(Circle().fill(Color.green))
                                        .offset(x: 6, y: -6)
                                }
                            }
                            .opacity(value != nil && !on ? 0.55 : 1)
                        Text(firstName(s))
                            .font(.caption2.weight(on ? .bold : .medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shooting.pad.athlete")
            }
        }
    }

    private var prompt: some View {
        HStack(spacing: 8) {
            if let current {
                Text(current.primaryDisplayName).font(.headline).lineLimit(1)
            }
            Text("·").foregroundStyle(.secondary)
            Text(question).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                run.set(nil, for: student, spot: spot)
            } label: {
                Image(systemName: "delete.left")
            }
            .disabled(run.makes(student, spot: spot) == nil)
            .accessibilityLabel(isChinese ? "清除" : "Clear")
        }
    }

    private var question: String {
        let at = drill.spotCount > 1 ? drill.spotName(spot, chinese: isChinese) + " · " : ""
        switch setup.mode {
        case .attempts: return at + (isChinese ? "\(setup.shots) 投中几个？" : "made of \(setup.shots)?")
        case .timed: return at + (isChinese ? "\(ShootingSetup.time(setup.seconds, chinese: true)) 进了几个？"
                                            : "makes in \(ShootingSetup.time(setup.seconds, chinese: false))?")
        }
    }

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(0...maximum, id: \.self) { n in
                let chosen = run.makes(student, spot: spot) == n
                Button {
                    run.set(n, for: student, spot: spot)
                    advance()
                } label: {
                    Text("\(n)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(chosen ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(chosen ? Color.orange : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shooting.pad.\(n)")
            }
        }
    }

    private var progressText: String {
        let filled = students.reduce(0) { sum, s in
            sum + (0..<drill.spotCount).filter { run.makes(s.id, spot: $0) != nil }.count
        }
        return isChinese ? "已记 \(filled)/\(students.count * drill.spotCount)" : "\(filled) of \(students.count * drill.spotCount) logged"
    }

    /// Made of N: this athlete's next empty spot, then the next athlete with
    /// one. Timed: the next athlete without this spot. Nothing left: close.
    private func advance() {
        let ids = students.map(\.id)
        guard let i = ids.firstIndex(of: student) else { dismiss(); return }
        let after = Array(ids[(i + 1)...] + ids[..<i])
        if timedSpot == nil, setup.mode == .attempts,
           let next = (0..<drill.spotCount).first(where: { run.makes(student, spot: $0) == nil }) {
            spot = next
            return
        }
        if setup.mode == .timed || drill.spotCount == 1 {
            if let next = after.first(where: { run.makes($0, spot: spot) == nil }) { student = next } else { dismiss() }
            return
        }
        for id in after {
            if let s = (0..<drill.spotCount).first(where: { run.makes(id, spot: $0) == nil }) {
                student = id; spot = s; return
            }
        }
        dismiss()
    }

    private func firstName(_ s: Student) -> String {
        let name = s.primaryDisplayName
        return isChinese ? name : (name.components(separatedBy: " ").first ?? name)
    }
}
