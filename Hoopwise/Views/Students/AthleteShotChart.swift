import SwiftUI

// The athlete's shot chart (21 Nov 2026): every tracked drill with a place on
// the floor, on one map (ShootingHistory.zoneMap). On the profile and the
// Quick Peep at the top of Shooting; a tap opens it full screen, where it
// can be shared as an image (WeChat) — name, month, the map, free throws.

enum ShotChartScope: String, CaseIterable {
    case all, last
    func title(chinese: Bool) -> String {
        switch self {
        case .all: chinese ? "全部" : "All sessions"
        case .last: chinese ? "最近一次" : "Last session"
        }
    }
}

private struct AthleteShotChartData {
    let zones: [ShotZoneValue?]
    let deltas: [Double?]?
    let freeThrows: ShotZoneValue?
    let lastDate: Date?

    init(studentId: UUID, sessions: [SessionEvent], scope: ShotChartScope) {
        let latest = ShootingHistory.latestMapSession(for: studentId, sessions: sessions)
        lastDate = latest?.startTime
        switch scope {
        case .all:
            zones = ShootingHistory.zoneMap(for: studentId, sessions: sessions)
            if let latest {
                let before = ShootingHistory.zoneMap(for: studentId, sessions: sessions, before: latest.startTime)
                deltas = before.contains { $0 != nil } ? ShootingHistory.deltas(zones, before) : nil
            } else { deltas = nil }
            freeThrows = ShootingHistory.freeThrows(for: studentId, sessions: sessions)
        case .last:
            let one = latest.map { [$0] } ?? []
            zones = ShootingHistory.zoneMap(for: studentId, sessions: one)
            deltas = nil
            freeThrows = ShootingHistory.freeThrows(for: studentId, sessions: one)
        }
    }

    var isEmpty: Bool { !zones.contains { $0 != nil } }
    var total: ShotZoneValue? {
        let z = zones.compactMap { $0 }
        let att = z.reduce(0) { $0 + $1.attempted }
        return att > 0 ? ShotZoneValue(made: z.reduce(0) { $0 + $1.made }, attempted: att) : nil
    }
}

struct AthleteShotChartCard: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    @AppStorage("shotChart.scope") private var scopeRaw = ShotChartScope.all.rawValue
    @AppStorage("shotChart.colour") private var colourRaw = ShotChartColour.bands.rawValue
    @State private var fullScreen = false
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let scope = ShotChartScope(rawValue: scopeRaw) ?? .all
        let data = AthleteShotChartData(studentId: studentId, sessions: dataManager.sessionEvents, scope: scope)
        if !ShootingHistory.zoneMap(for: studentId, sessions: dataManager.sessionEvents).allSatisfy({ $0 == nil }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(isChinese ? "热区图" : "SHOT CHART")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $scopeRaw) {
                        ForEach(ShotChartScope.allCases, id: \.rawValue) { Text($0.title(chinese: isChinese)).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                Button { fullScreen = true } label: {
                    ShotChartMap(zones: data.zones, deltas: data.deltas,
                                 colour: ShotChartColour(rawValue: colourRaw) ?? .bands)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlete.shotChart")
                footer(data)
            }
            .sheet(isPresented: $fullScreen) {
                AthleteShotChartScreen(studentId: studentId)
                    .environmentObject(dataManager)
            }
        }
    }

    private func footer(_ data: AthleteShotChartData) -> some View {
        HStack(spacing: 10) {
            if let t = data.total {
                Text((isChinese ? "合计 " : "All zones ") + "\(Int(t.made))/\(Int(t.attempted)) · \(Int((t.share * 100).rounded()))%")
            }
            if let ft = data.freeThrows {
                Text((isChinese ? "罚球 " : "FT ") + "\(Int((ft.share * 100).rounded()))%")
            }
            Spacer()
            Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
    }
}

struct AthleteShotChartScreen: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let studentId: UUID
    @AppStorage("shotChart.scope") private var scopeRaw = ShotChartScope.all.rawValue
    @AppStorage("shotChart.colour") private var colourRaw = ShotChartColour.bands.rawValue
    @State private var sharing: UIImage?
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var student: Student? { dataManager.students.first { $0.id == studentId } }

    var body: some View {
        let scope = ShotChartScope(rawValue: scopeRaw) ?? .all
        let colour = ShotChartColour(rawValue: colourRaw) ?? .bands
        let data = AthleteShotChartData(studentId: studentId, sessions: dataManager.sessionEvents, scope: scope)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $scopeRaw) {
                        ForEach(ShotChartScope.allCases, id: \.rawValue) { Text($0.title(chinese: isChinese)).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    ShotChartMap(zones: data.zones, deltas: data.deltas, colour: colour)
                        .frame(maxWidth: 760)
                    HStack {
                        Picker("", selection: $colourRaw) {
                            ForEach(ShotChartColour.allCases, id: \.rawValue) { Text($0.title(chinese: isChinese)).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                        Spacer()
                        if colour == .bands { ShotChartLegend() }
                    }
                    zoneList(data)
                }
                .padding(20)
            }
            .navigationTitle(student?.primaryDisplayName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sharing = shareImage(data: data, colour: colour)
                    } label: {
                        Label(isChinese ? "分享" : "Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("shotChart.share")
                }
            }
            .sheet(item: Binding(get: { sharing.map(SharedImage.init) }, set: { if $0 == nil { sharing = nil } })) { item in
                ShareSheet(items: [item.image])
            }
        }
    }

    /// Every zone as a line: name, made/attempted, percentage.
    private func zoneList(_ data: AthleteShotChartData) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<10, id: \.self) { i in
                HStack {
                    Text(ShootingDrill.shotChart.spotName(i, chinese: isChinese)).font(.subheadline)
                    Spacer()
                    if let z = data.zones[i] {
                        Text("\(Int(z.made.rounded()))/\(Int(z.attempted.rounded()))").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        Text("\(Int((z.share * 100).rounded()))%").font(.subheadline.weight(.bold)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                if i < 9 { Divider() }
            }
            if let ft = data.freeThrows {
                Divider()
                HStack {
                    Text(ShootingDrill.freeThrows.title(chinese: isChinese)).font(.subheadline)
                    Spacer()
                    Text("\(Int(ft.made))/\(Int(ft.attempted))").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Text("\(Int((ft.share * 100).rounded()))%").font(.subheadline.weight(.bold)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    @MainActor
    private func shareImage(data: AthleteShotChartData, colour: ShotChartColour) -> UIImage? {
        guard let student else { return nil }
        let card = ShotChartShareCard(student: student, data: data, colour: colour)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct SharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The image sent to a parent: always light, always Chinese-first like the
/// player card when the app is in Chinese.
private struct ShotChartShareCard: View {
    let student: Student
    let data: AthleteShotChartData
    let colour: ShotChartColour
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.primaryDisplayName).font(.system(size: 26, weight: .heavy))
                    if let second = student.secondaryNameLine {
                        Text(second).font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isChinese ? "投篮热区图" : "SHOT CHART").font(.system(size: 13, weight: .heavy)).foregroundStyle(.orange)
                    if let d = data.lastDate {
                        Text(d.formatted(.dateTime.year().month(.abbreviated))).font(.system(size: 12)).foregroundStyle(.black.opacity(0.55))
                    }
                }
            }
            ShotChartMap(zones: data.zones, colour: colour, forImage: true)
            HStack {
                if colour == .bands { ShotChartLegend(forImage: true) }
                Spacer()
                if let ft = data.freeThrows {
                    Text((isChinese ? "罚球 " : "Free throws ") + "\(Int(ft.made))/\(Int(ft.attempted)) · \(Int((ft.share * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            Text(ProgramGuideStore.academyName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.45))
        }
        .foregroundStyle(.black)
        .padding(24)
        .frame(width: 600)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
