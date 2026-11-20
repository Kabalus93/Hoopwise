import SwiftUI

// THE SHOT CHART ADD-ON (21 Nov 2026). In the plan: athletes as photos
// (and Group — everyone pooled), the map for the one chosen, tap a zone,
// type made then attempted. The pad stays open and moves to the athlete's
// next empty zone; athletes can be switched on the pad as they walk up.
// Colour by absolute bands or against the athlete's own average; ↑/↓ per
// zone against their last shot chart.

struct ShotChartAddOnCard: View {
    @Binding var run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool

    @State private var chosen: UUID?
    @State private var pad: PadStart?
    @State private var expanded = true
    @AppStorage("shotChart.colour") private var colourRaw = ShotChartColour.bands.rawValue
    @AppStorage("shotChart.vsLast") private var vsLast = true
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private let drill = ShootingDrill.shotChart

    struct PadStart: Identifiable { let id = UUID(); let student: UUID; let zone: Int }

    private var setup: ShootingSetup { run.setup }
    private var colour: ShotChartColour { ShotChartColour(rawValue: colourRaw) ?? .bands }

    private func zones(for student: UUID?) -> [ShotZoneValue?] {
        if let student { return run.result(for: student)?.zoneValues ?? Array(repeating: nil, count: 10) }
        var out = [ShotZoneValue?](repeating: nil, count: 10)
        for s in students {
            guard let z = run.result(for: s.id)?.zoneValues else { continue }
            for i in 0..<10 {
                guard let v = z[i] else { continue }
                var cur = out[i] ?? ShotZoneValue(made: 0, attempted: 0)
                cur.made += v.made; cur.attempted += v.attempted
                out[i] = cur
            }
        }
        return out
    }

    private func lastZones(for student: UUID) -> [ShotZoneValue?]? {
        ShootingHistory.previous(student, setup: setup, before: sessionDate, sessions: allSessions)?.zoneValues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if expanded {
                if students.isEmpty {
                    Text(isChinese ? "这节课还没有学员。" : "No athletes on this session yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    athleteStrip
                    map
                    controls
                    summary
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.orange.opacity(0.22), lineWidth: 1))
        .sheet(item: $pad) { start in
            ShotZonePad(run: $run, students: students, student: start.student, zone: start.zone)
                .presentationDetents([.large])
        }
        .onAppear { if chosen == nil { chosen = students.first?.id } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shooting.addon.shotChart")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: drill.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title(chinese: isChinese).uppercased()).font(.subheadline.weight(.bold))
                HStack(spacing: 4) {
                    Text(setup.summary(chinese: isChinese))
                    if canEdit && run.entries.isEmpty { setupMenu }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
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
        }
    }

    private var setupMenu: some View {
        Menu {
            Picker(isChinese ? "计分方式" : "Scoring", selection: Binding(
                get: { run.setup.mode }, set: { run.setup.mode = $0; run.setup.remember() })) {
                Text(isChinese ? "每区命中 / 出手" : "Made / attempted per zone").tag(ShootingMode.chart)
                Text(isChinese ? "每区固定出手" : "Same shots in every zone").tag(ShootingMode.attempts)
            }
            if setup.mode == .attempts {
                Picker(isChinese ? "每区出手" : "Shots a zone", selection: Binding(
                    get: { run.setup.shots }, set: { run.setup.shots = $0; run.setup.remember() })) {
                    ForEach([5, 10, 15, 20], id: \.self) { Text("\($0)").tag($0) }
                }
            }
        } label: {
            Label(isChinese ? "更改" : "Change", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    /// Group first, then everyone — each with their percentage today.
    private var athleteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                chip(id: nil, label: isChinese ? "全组" : "Group") {
                    Image(systemName: "person.3.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                ForEach(students) { s in
                    chip(id: s.id, label: firstName(s)) { StudentAvatarView(student: s, size: 44) }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func chip<V: View>(id: UUID?, label: String, @ViewBuilder avatar: () -> V) -> some View {
        let on = chosen == id
        let r = id.flatMap { run.result(for: $0) }
        return Button { chosen = id } label: {
            VStack(spacing: 3) {
                avatar()
                    .overlay(Circle().strokeBorder(on ? Color.orange : .clear, lineWidth: 3).padding(-3))
                    .overlay(alignment: .bottomTrailing) {
                        if let r {
                            Text("\(Int((r.value * 100).rounded()))")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minHeight: 18)
                                .background(Capsule().fill(Color.green))
                                .offset(x: 6, y: 4)
                        }
                    }
                Text(label).font(.caption2.weight(on ? .bold : .medium)).lineLimit(1)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id == nil ? "shotchart.group" : "shotchart.athlete")
    }

    private var map: some View {
        let now = zones(for: chosen)
        let last = chosen.flatMap(lastZones)
        return ShotChartMap(zones: now,
                            deltas: vsLast ? last.map { ShootingHistory.deltas(now, $0) } : nil,
                            colour: colour,
                            onTap: canEdit ? { zone in
                                guard let who = chosen ?? students.first?.id else { return }
                                pad = PadStart(student: who, zone: zone)
                            } : nil)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $colourRaw) {
                ForEach(ShotChartColour.allCases, id: \.rawValue) { Text($0.title(chinese: isChinese)).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Toggle(isOn: $vsLast) { Text(isChinese ? "对比上次" : "Vs last time").font(.caption) }
                .toggleStyle(.button)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            Spacer()
            if colour == .bands { ShotChartLegend() }
        }
    }

    @ViewBuilder
    private var summary: some View {
        let z = zones(for: chosen).compactMap { $0 }
        let made = z.reduce(0) { $0 + $1.made }, att = z.reduce(0) { $0 + $1.attempted }
        HStack(spacing: 6) {
            if let who = chosen.flatMap({ id in students.first { $0.id == id } }) {
                Text(who.primaryDisplayName).font(.footnote.weight(.semibold))
            } else {
                Text(isChinese ? "全组" : "Group").font(.footnote.weight(.semibold))
            }
            if att > 0 {
                Text("· \(Int(made))/\(Int(att)) · \(Int((made / att * 100).rounded()))%")
                    .font(.footnote).monospacedDigit()
                if let id = chosen, let last = ShootingHistory.previous(id, setup: setup, before: sessionDate, sessions: allSessions) {
                    Text((isChinese ? "· 上次 " : "· last time ") + last.text).font(.footnote).foregroundStyle(.secondary)
                }
            } else if canEdit {
                Text(chosen == nil ? (isChinese ? "· 选一位学员，点区域记录" : "· choose an athlete, tap a zone to log")
                                   : (isChinese ? "· 点区域记录" : "· tap a zone to log"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func firstName(_ s: Student) -> String {
        let name = s.primaryDisplayName
        return isChinese ? name : (name.components(separatedBy: " ").first ?? name)
    }
}

// MARK: - The zone pad

/// Made, then attempted (or made alone with a fixed number of shots).
struct ShotZonePad: View {
    @Binding var run: ShootingRun
    let students: [Student]
    @State private var student: UUID
    @State private var zone: Int
    /// Chart mode: the made just typed, waiting for its attempts.
    @State private var pendingMade: Int?
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private let drill = ShootingDrill.shotChart

    init(run: Binding<ShootingRun>, students: [Student], student: UUID, zone: Int) {
        _run = run; self.students = students
        _student = State(initialValue: student)
        _zone = State(initialValue: zone)
    }

    private var chart: Bool { run.setup.mode == .chart }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    athletes
                    HStack(alignment: .top, spacing: 14) {
                        ShotChartMap(zones: run.result(for: student)?.zoneValues ?? Array(repeating: nil, count: 10),
                                     selected: zone, showCounts: false,
                                     onTap: { zone = $0; pendingMade = nil })
                            .frame(maxWidth: 260)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(drill.spotName(zone, chinese: isChinese)).font(.headline)
                            Text(prompt).font(.subheadline).foregroundStyle(.secondary)
                            if let m = run.makes(student, spot: zone) {
                                let a = chart ? run.attempts(student, spot: zone) : run.setup.shots
                                Text(isChinese ? "已记：\(m)/\(a.map(String.init) ?? "?")" : "In: \(m)/\(a.map(String.init) ?? "?")")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(.green)
                                Button(role: .destructive) {
                                    run.set(nil, for: student, spot: zone)
                                    if chart { run.setAttempts(nil, for: student, spot: zone) }
                                    pendingMade = nil
                                } label: { Label(isChinese ? "清除此区" : "Clear zone", systemImage: "delete.left") }
                                    .font(.footnote)
                            }
                        }
                    }
                    keypad
                }
                .padding(20)
            }
            .navigationTitle(drill.title(chinese: isChinese))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("shotchart.pad.done")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: zone)
    }

    private var prompt: String {
        if !chart { return isChinese ? "\(run.setup.shots) 投中几个？" : "Made of \(run.setup.shots)?" }
        if let m = pendingMade { return isChinese ? "命中 \(m) · 共出手几次？" : "\(m) made · out of how many?" }
        return isChinese ? "命中几个？" : "How many made?"
    }

    private var athletes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(students) { s in
                    let on = s.id == student
                    Button { student = s.id; pendingMade = nil } label: {
                        VStack(spacing: 3) {
                            StudentAvatarView(student: s, size: 44)
                                .overlay(Circle().strokeBorder(on ? Color.orange : .clear, lineWidth: 3).padding(-3))
                            Text(s.primaryDisplayName.components(separatedBy: " ").first ?? s.primaryDisplayName)
                                .font(.caption2.weight(on ? .bold : .medium)).lineLimit(1)
                        }
                        .frame(width: 58)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shotchart.pad.athlete")
                }
            }
        }
    }

    /// Made: 0…20 (fixed shots: 0…shots). Attempted: made…made+20.
    private var keypad: some View {
        let range: ClosedRange<Int> = {
            if !chart { return 0...run.setup.shots }
            if let m = pendingMade { return max(m, 1)...(m + 20) }
            return 0...20
        }()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(Array(range), id: \.self) { n in
                Button { typed(n) } label: {
                    Text("\(n)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(pendingMade != nil ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(pendingMade != nil ? Color.orange.opacity(0.85) : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shotchart.pad.\(n)")
            }
        }
    }

    private func typed(_ n: Int) {
        if chart && pendingMade == nil { pendingMade = n; return }
        if chart, let m = pendingMade {
            run.set(m, for: student, spot: zone)
            run.setAttempts(n, for: student, spot: zone)
            pendingMade = nil
        } else {
            run.set(n, for: student, spot: zone)
        }
        // The athlete's next empty zone; none left: stay, the coach moves on.
        if let next = ((zone + 1)..<10).first(where: { run.makes(student, spot: $0) == nil })
            ?? (0..<zone).first(where: { run.makes(student, spot: $0) == nil }) {
            zone = next
        }
    }
}
