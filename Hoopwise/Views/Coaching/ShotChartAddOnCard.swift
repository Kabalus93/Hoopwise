import SwiftUI

// THE SHOT CHART ADD-ON (21 Nov 2026). In the plan: athletes as photos
// (and Group — everyone pooled), the map for the one chosen, tap a zone:
// the floating number pad pops out of it (23 Nov 2026, Luther: "the popup
// should only be a number pad") — made, → attempted, ✓ logs and the pad
// moves to the athlete's next empty zone. Switch athletes on the strip.
// Colour by absolute bands or against the athlete's own average; ↑/↓ per
// zone against their last shot chart.

struct ShotChartAddOnCard: View {
    @Binding var run: ShootingRun
    let students: [Student]
    let sessionDate: Date
    let allSessions: [SessionEvent]
    let canEdit: Bool
    /// In the shooting station: no fold, no card frame.
    var station = false
    /// Rounds: the round before this one (compared with instead of the
    /// last session) and its number.
    var previousRound: ShootingRun? = nil
    var previousRoundNumber = 0
    var lockSetup = false
    private func previous(_ student: UUID) -> ShootingResult? {
        if let previousRound { return previousRound.result(for: student) }
        return ShootingHistory.previous(student, setup: setup, before: sessionDate, sessions: allSessions)
    }

    @EnvironmentObject private var dataManager: DataManager
    @State private var chosen: UUID?
    /// The zone the number pad is open on; made and attempted being typed.
    @State private var active: Int?
    @State private var madeEntry = NumberPadEntry(text: "")
    @State private var attEntry = NumberPadEntry(text: "")
    @State private var typingAttempts = false
    /// The zone to open once the current popup has gone.
    @State private var pendingZone: Int?
    @State private var editingSetup = false
    @State private var sharing: UIImage?
    @State private var expanded = true
    @AppStorage("shotChart.colour") private var colourRaw = ShotChartColour.bands.rawValue
    @AppStorage("shotChart.vsLast") private var vsLast = true
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private let drill = ShootingDrill.shotChart

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
        previous(student)?.zoneValues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if expanded || station {
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
        .padding(station ? 0 : 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(station ? Color.clear : Color.filmCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(station ? Color.clear : Color.orange.opacity(0.22), lineWidth: 1))
        .sheet(isPresented: $editingSetup) {
            ShootingSetupSheet(setup: run.setup) { run.setup = $0 }
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
                    if canEdit && run.entries.isEmpty && !lockSetup { setupMenu }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
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
            }
        }
    }

    private var setupMenu: some View {
        Button { editingSetup = true } label: {
            Label(isChinese ? "更改" : "Change", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shooting.setup")
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
                            selected: active,
                            onTap: canEdit ? { zone in open(zone) } : nil,
                            pad: canEdit ? .init(isPresented: presented, content: { AnyView(zonePad) }) : nil)
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
            Toggle(isOn: $vsLast) { Text(previousRound != nil ? (isChinese ? "对比第 \(previousRoundNumber) 轮" : "Vs round \(previousRoundNumber)") : (isChinese ? "对比上次" : "Vs last time")).font(.caption) }
                .toggleStyle(.button)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            Spacer()
            if colour == .bands { ShotChartLegend() }
        }
    }

    private var chosenStudent: Student? { chosen.flatMap { id in students.first { $0.id == id } } }

    /// Today against the last chart (or the round before).
    private var comparison: (text: String, up: Bool?)? {
        guard let id = chosen, let last = previous(id), let now = run.result(for: id) else { return nil }
        let lead = previousRound != nil ? (isChinese ? "第 \(previousRoundNumber) 轮 " : "Round \(previousRoundNumber): ")
                                        : (isChinese ? "上次 " : "Last time: ")
        let gap = now.value - last.value
        return (lead + last.text, abs(gap) < 0.005 ? nil : gap > 0)
    }

    /// The numbers under the map, large: total, by range, best and weakest
    /// zone, every zone logged — and Share, the same as a light picture.
    @ViewBuilder
    private var summary: some View {
        let z = zones(for: chosen)
        let name = chosenStudent?.primaryDisplayName ?? (isChinese ? "全组" : "Group")
        if z.contains(where: { ($0?.attempted ?? 0) > 0 }) {
            VStack(alignment: .leading, spacing: 14) {
                ShotChartBreakdown(name: name, zones: z, comparison: comparison, chinese: isChinese)
                Button {
                    sharing = SessionShotChartShareCard(student: chosenStudent, groupName: name, date: sessionDate,
                                                        zones: z, colour: colour, comparison: comparison,
                                                        chinese: isChinese).image()
                } label: {
                    Label(isChinese ? "分享这张图" : "Share this chart", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shotchart.share")
            }
            .padding(.top, 4)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: [sharing]) }
            }
        } else {
            HStack(spacing: 6) {
                Text(name).font(.footnote.weight(.semibold))
                if canEdit {
                    Text(chosen == nil ? (isChinese ? "· 选一位学员，点区域记录" : "· choose an athlete, tap a zone to log")
                                       : (isChinese ? "· 点区域记录" : "· tap a zone to log"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func firstName(_ s: Student) -> String {
        let name = s.primaryDisplayName
        return isChinese ? name : (name.components(separatedBy: " ").first ?? name)
    }
}

// MARK: - The number pad on a zone

extension ShotChartAddOnCard {
    private var chart: Bool { setup.mode == .chart }
    /// The most one zone takes, made or attempted. A long shooting workout
    /// (make 60 a spot) runs well past a hundred shots a zone.
    static let mostShots = 999
    private var who: UUID? { chosen ?? students.first?.id }

    func open(_ zone: Int) {
        if chosen == nil { chosen = students.first?.id }
        guard let who else { return }
        let made = run.makes(who, spot: zone)
        madeEntry = .cell(made.map(Double.init), maximum: Double(chart ? Self.mostShots : max(1, setup.shots)))
        attEntry = .cell((chart ? run.attempts(who, spot: zone) : nil).map(Double.init), maximum: Double(Self.mostShots))
        typingAttempts = false
        active = zone
    }

    func presented(_ zone: Int) -> Binding<Bool> {
        Binding(get: { active == zone }, set: { on in
            guard !on, active == zone else { return }
            _ = commit(zone)
            active = nil
        })
    }

    /// Made and (chart) attempted from what was typed, else what is in.
    private func values(_ zone: Int) -> (made: Int?, att: Int?) {
        guard let who else { return (nil, nil) }
        let made = madeEntry.typed ? (madeEntry.text.isEmpty ? nil : Int(madeEntry.value)) : run.makes(who, spot: zone)
        let att = chart ? (attEntry.typed ? (attEntry.text.isEmpty ? nil : Int(attEntry.value)) : run.attempts(who, spot: zone)) : nil
        return (made, att)
    }

    private var invalid: Bool {
        guard chart, let zone = active else { return false }
        let v = values(zone)
        guard let m = v.made, let a = v.att else { return false }
        return m > a || a == 0
    }

    /// Writes the zone; false when made > attempted (nothing written).
    private func commit(_ zone: Int) -> Bool {
        guard let who, madeEntry.typed || attEntry.typed else { return true }
        let v = values(zone)
        if chart {
            if let m = v.made, let a = v.att, m > a || a == 0 { return false }
            run.set(v.made, for: who, spot: zone)
            run.setAttempts(v.made == nil ? nil : v.att, for: who, spot: zone)
        } else {
            run.set(v.made, for: who, spot: zone)
        }
        return true
    }

    private func key(_ k: Character) {
        guard let zone = active else { return }
        switch k {
        case "→": typingAttempts = true; attEntry.fresh = true
        case "✓":
            guard commit(zone), let who else { return }
            let next = ((zone + 1)..<10).first(where: { run.makes(who, spot: $0) == nil })
                ?? (0..<zone).first(where: { run.makes(who, spot: $0) == nil })
            pendingZone = next
            active = nil
        case "⌫": if typingAttempts { attEntry.delete() } else { madeEntry.delete() }
        default: if typingAttempts { attEntry.press(k) } else { madeEntry.press(k) }
        }
    }

    /// The keys, and (chart) the two numbers being typed — nothing else.
    @ViewBuilder
    var zonePad: some View {
        VStack(spacing: 10) {
            if chart {
                HStack(spacing: 8) {
                    numberBox(madeEntry, on: !typingAttempts, id: "shotchart.made") { typingAttempts = false; madeEntry.fresh = true }
                    Text("/").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                    numberBox(attEntry, on: typingAttempts, id: "shotchart.att") { typingAttempts = true; attEntry.fresh = true }
                }
                .overlay(alignment: .bottom) {
                    if invalid {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).offset(y: 14)
                    }
                }
            }
            FloatingNumberPad(onKey: key, nextKey: chart && !typingAttempts, confirmKey: !chart || typingAttempts,
                              keyHeight: 56, identifier: "shotchart.keys", chrome: false)
        }
        .padding(12)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
        .onDisappear {
            // The next zone opens once this popup has gone.
            guard let next = pendingZone else { return }
            pendingZone = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { open(next) }
        }
    }

    private func numberBox(_ e: NumberPadEntry, on: Bool, id: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(e.text.isEmpty ? "–" : e.text)
                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(on ? Color.orange : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(id).value")
        .accessibilityValue(e.text)
    }
}
