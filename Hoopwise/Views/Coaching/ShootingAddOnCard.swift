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
// · TAP A CELL (or LOG MAKES for the next empty one): the floating number
//   pad pops out of that cell — the keys alone (23 Nov 2026, Luther: "the
//   popup should only be a number pad"); the number shows in the cell; ✓ logs
//   it and the next cell opens (made of N: that athlete's next spot; timed:
//   the next athlete at the clock's spot).
// Results → SessionCurriculum.shooting (ShootingRun).

struct ShootingAddOnCard: View {
    let drill: ShootingDrill
    @Binding var run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool
    /// In the shooting station (23 Nov 2026): no fold, no card frame — the
    /// station is the page. The plan shows a one-line tracker instead.
    var station = false
    /// Rounds (23 Nov 2026): the round before this one — numbers compare
    /// with IT instead of the last session — and its number.
    var previousRound: ShootingRun? = nil
    var previousRoundNumber = 0
    var lockSetup = false
    private func lastWord(long: Bool) -> String {
        if previousRound != nil { return isChinese ? "第 \(previousRoundNumber) 轮 " : "round \(previousRoundNumber) " }
        return isChinese ? "上次 " : (long ? "last time " : "last ")
    }

    @EnvironmentObject private var dataManager: DataManager
    /// The cell the number pad is open on, and what has been typed there.
    @State private var active: PadCell?
    @State private var draft = NumberPadEntry(text: "")
    /// The cell to open once the current popup has gone.
    @State private var pending: PadCell?
    @State private var editingSetup = false
    @State private var expanded = true
    @State private var clockSpot = 0
    @State private var remaining: Int?
    @State private var running = false
    @State private var buzz = 0
    @AppStorage("shooting.sort") private var sortRaw = Sort.roster.rawValue
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    enum Sort: String, CaseIterable { case roster, best, toLog }

    private var setup: ShootingSetup { run.setup }
    private var locked: Bool { lockSetup || !run.entries.isEmpty }
    private var sort: Sort { Sort(rawValue: sortRaw) ?? .roster }

    /// Each athlete's result in this test last time (computed once a draw).
    private var lastTime: [UUID: ShootingResult] {
        var out: [UUID: ShootingResult] = [:]
        for s in students {
            if let previousRound {
                if let r = previousRound.result(for: s.id) { out[s.id] = r }
            } else if let r = ShootingHistory.previous(s.id, setup: setup, before: sessionDate, sessions: allSessions) { out[s.id] = r }
        }
        return out
    }

    var body: some View {
        let last = lastTime
        VStack(alignment: .leading, spacing: 14) {
            header
            summary(last)
            if expanded || station {
                if setup.mode == .timed && canEdit { clock }
                if students.isEmpty {
                    Text(isChinese ? "这节课还没有学员。" : "No athletes on this session yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    table(last)
                }
            }
        }
        .padding(station ? 0 : 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(station ? Color.clear : Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(station ? Color.clear : Color.orange.opacity(0.22), lineWidth: 1))
        .sheet(isPresented: $editingSetup) {
            ShootingSetupSheet(setup: run.setup) { new in
                run.setup = new
                remaining = nil
                running = false
            }
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
            if !station {
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
    }

    /// The setup opens a sheet (23 Nov 2026 — a menu of fixed values capped
    /// the time at 3 minutes).
    private var setupMenu: some View {
        Button { editingSetup = true } label: {
            Label(isChinese ? "更改" : "Change", systemImage: "slider.horizontal.3")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shooting.setup")
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
                        Text(lastWord(long: true) + ShootingResult.text(thenAvg, mode: setup.mode, chinese: isChinese))
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
                    if let first { open(PadCell(student: first.id, spot: clockSpot)) }
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
                    Text(lastWord(long: false) + last.text)
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
        case .attempts, .chart: return Double(makes) / Double(max(setup.shots, 1))
        case .timed:
            let top = run.entries.flatMap { $0.makes.compactMap { $0 } }.max() ?? 1
            return Double(makes) / Double(max(top, 1))
        }
    }

    private func cell(student: UUID, spot: Int) -> some View {
        let value = run.makes(student, spot: spot)
        let here = PadCell(student: student, spot: spot)
        let editing = active == here
        let shown = editing ? (draft.text.isEmpty ? "·" : draft.text) : (value.map(String.init) ?? "·")
        return Button {
            guard canEdit else { return }
            open(here)
        } label: {
            Text(shown)
                .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(value == nil && !editing ? Color.secondary : Color.primary)
                .frame(width: cellWidth, height: 32)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(value.map { Color.orange.opacity(0.12 + 0.55 * strength($0)) } ?? Color(.tertiarySystemFill)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(editing ? Color.orange : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .cellNumberPad(isPresented: presented(here), draft: $draft, identifier: "shooting.keys",
                       onConfirm: { confirm(here) }, onClosed: openPending)
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
                Text(avg.map { setup.mode.isShare ? "\(Int(($0 * 100).rounded()))%" : String(format: "%.1f", $0) } ?? "—")
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

    // MARK: The number pad on a cell

    /// The most a cell takes: the shots (made of N), else a generous count.
    private var maximum: Int {
        setup.mode == .timed ? 200 : max(1, setup.shots)
    }

    private func open(_ cell: PadCell) {
        draft = .cell(run.makes(cell.student, spot: cell.spot).map(Double.init), maximum: Double(maximum))
        active = cell
    }

    private func presented(_ cell: PadCell) -> Binding<Bool> {
        Binding(get: { active == cell }, set: { on in
            guard !on, active == cell else { return }
            commit(cell)          // a tap outside keeps what was typed
            active = nil
        })
    }

    private func commit(_ cell: PadCell) {
        guard draft.typed else { return }
        run.set(draft.text.isEmpty ? nil : Int(draft.value), for: cell.student, spot: cell.spot)
    }

    /// ✓: log, then the next empty cell opens.
    private func confirm(_ cell: PadCell) {
        commit(cell)
        let next = nextCell(after: cell)
        pending = next
        active = nil
    }

    private func openPending() {
        guard let next = pending else { return }
        pending = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { open(next) }
    }

    /// Made of N: this athlete's next empty spot, then the next athlete's.
    /// Timed (or one spot): the next athlete at the same spot.
    private func nextCell(after cell: PadCell) -> PadCell? {
        let ids = students.map(\.id)
        guard let i = ids.firstIndex(of: cell.student) else { return nil }
        let after = Array(ids[(i + 1)...] + ids[..<i])
        if setup.mode == .timed || drill.spotCount == 1 {
            return after.first { run.makes($0, spot: cell.spot) == nil }.map { PadCell(student: $0, spot: cell.spot) }
        }
        if let s = (0..<drill.spotCount).first(where: { run.makes(cell.student, spot: $0) == nil }) {
            return PadCell(student: cell.student, spot: s)
        }
        for id in after {
            if let s = (0..<drill.spotCount).first(where: { run.makes(id, spot: $0) == nil }) {
                return PadCell(student: id, spot: s)
            }
        }
        return nil
    }

    private func openPadAtNext() {
        if setup.mode == .timed {
            let first = students.first { run.makes($0.id, spot: clockSpot) == nil } ?? students.first
            if let first { open(PadCell(student: first.id, spot: clockSpot)) }
            return
        }
        for s in students {
            if let spot = (0..<drill.spotCount).first(where: { run.makes(s.id, spot: $0) == nil }) {
                open(PadCell(student: s.id, spot: spot)); return
            }
        }
        if let first = students.first { open(PadCell(student: first.id, spot: 0)) }
    }
}
