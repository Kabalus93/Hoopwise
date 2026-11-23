import SwiftUI

// THE SHOT CHART'S NUMBERS (23 Nov 2026, Luther, markup on the one small line
// under the map: "can you make these bigger and more detailed? I'd like to
// share this with my client"). The total large, the split by range (threes,
// mid-range, at the rim), the best zone and the one to work on, then every
// zone logged as a line with its bar. `forImage` = light, for the shared
// picture. Pure reading of the zones on the map — nothing here is stored.

nonisolated struct ShotChartTotals {
    struct Part: Identifiable {
        let id: String
        let made: Double, attempted: Double
        var share: Double { attempted > 0 ? made / attempted : 0 }
    }

    let zones: [ShotZoneValue?]

    private func part(_ id: String, _ range: [Int]) -> Part {
        let z = range.compactMap { zones.indices.contains($0) ? zones[$0] : nil }
        return Part(id: id, made: z.reduce(0) { $0 + $1.made }, attempted: z.reduce(0) { $0 + $1.attempted })
    }

    var total: Part { part("total", Array(0..<10)) }
    var threes: Part { part("threes", [5, 6, 7, 8, 9]) }
    var mid: Part { part("mid", [1, 2, 3, 4]) }
    var rim: Part { part("rim", [0]) }

    /// Zones with shots, in the map's order.
    var logged: [Int] { zones.indices.filter { (zones[$0]?.attempted ?? 0) > 0 } }

    /// The best and the weakest zone — only when at least two zones differ.
    var extremes: (best: Int, weakest: Int)? {
        let l = logged
        guard l.count >= 2,
              let best = l.max(by: { zones[$0]!.share < zones[$1]!.share }),
              let weakest = l.min(by: { zones[$0]!.share < zones[$1]!.share }),
              zones[best]!.share - zones[weakest]!.share >= 0.005 else { return nil }
        return (best, weakest)
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}

struct ShotChartBreakdown: View {
    let name: String
    let zones: [ShotZoneValue?]
    /// "last time 36%" / "round 1 36%" and whether today is up on it.
    var comparison: (text: String, up: Bool?)? = nil
    var forImage = false
    var chinese = false

    private var ink: Color { forImage ? .black : .primary }
    private var soft: Color { forImage ? Color.black.opacity(0.55) : .secondary }
    private var panel: Color { forImage ? Color(white: 0.955) : Color(.tertiarySystemFill) }
    private var totals: ShotChartTotals { ShotChartTotals(zones: zones) }

    var body: some View {
        let t = totals
        VStack(alignment: .leading, spacing: 14) {
            headline(t)
            parts(t)
            if let e = t.extremes { extremes(e) }
            zoneRows(t)
        }
        .foregroundStyle(ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shotchart.breakdown")
    }

    private func headline(_ t: ShotChartTotals) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(ShotChartTotals.percent(t.total.share))
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier("shotchart.total")
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(chinese ? "\(Int(t.total.attempted)) 投 \(Int(t.total.made)) 中"
                             : "\(Int(t.total.made)) made of \(Int(t.total.attempted)) shots")
                    .font(.headline).monospacedDigit().foregroundStyle(soft)
                if let comparison {
                    HStack(spacing: 4) {
                        if let up = comparison.up {
                            Image(systemName: up ? "arrow.up" : "arrow.down")
                                .font(.footnote.weight(.heavy))
                                .foregroundStyle(up ? Color.green : Color.red)
                        }
                        Text(comparison.text).font(.subheadline).foregroundStyle(soft)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func parts(_ t: ShotChartTotals) -> some View {
        let all: [(String, ShotChartTotals.Part)] = [
            (chinese ? "三分" : "Threes", t.threes),
            (chinese ? "中距离" : "Mid-range", t.mid),
            (chinese ? "篮下" : "At the rim", t.rim),
        ]
        // One range alone would only repeat the total above.
        let shown = all.filter { $0.1.attempted > 0 }
        return HStack(spacing: 10) {
            ForEach(shown.count > 1 ? shown : [], id: \.1.id) { title, p in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(soft)
                    Text(ShotChartTotals.percent(p.share))
                        .font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("\(Int(p.made))/\(Int(p.attempted))").font(.subheadline).monospacedDigit().foregroundStyle(soft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(panel))
            }
        }
    }

    private func extremes(_ e: (best: Int, weakest: Int)) -> some View {
        HStack(spacing: 18) {
            extreme(chinese ? "最好" : "Best", e.best, "flame.fill", Color(red: 0.92, green: 0.30, blue: 0.24))
            extreme(chinese ? "要加强" : "To work on", e.weakest, "target", Color(red: 0.36, green: 0.55, blue: 0.93))
            Spacer(minLength: 0)
        }
    }

    private func extreme(_ title: String, _ zone: Int, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).foregroundStyle(tint)
            Text(title + (chinese ? "：" : ": ")).font(.subheadline).foregroundStyle(soft)
            + Text(ShootingDrill.shotChart.spotName(zone, chinese: chinese) + " "
                   + ShotChartTotals.percent(zones[zone]?.share ?? 0)).font(.subheadline.weight(.semibold))
        }
    }

    private func zoneRows(_ t: ShotChartTotals) -> some View {
        VStack(spacing: 9) {
            ForEach(t.logged, id: \.self) { i in
                let z = zones[i]!
                HStack(spacing: 10) {
                    Text(ShootingDrill.shotChart.spotName(i, chinese: chinese))
                        .font(.body).lineLimit(1).minimumScaleFactor(0.75)
                        .frame(width: 132, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(panel)
                            Capsule().fill(ShotChartMap.bandColour(z.share))
                                .frame(width: max(6, geo.size.width * min(1, z.share)))
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int(z.made.rounded()))/\(Int(z.attempted.rounded()))")
                        .font(.body).monospacedDigit().foregroundStyle(soft)
                        .frame(width: 76, alignment: .trailing)
                    Text(ShotChartTotals.percent(z.share))
                        .font(.body.weight(.bold)).monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

/// The picture sent to a client: always light — name, the day, the map and
/// the numbers.
struct SessionShotChartShareCard: View {
    let student: Student?
    let groupName: String
    let date: Date
    let zones: [ShotZoneValue?]
    let colour: ShotChartColour
    var comparison: (text: String, up: Bool?)? = nil
    var chinese = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.primaryDisplayName ?? groupName).font(.system(size: 26, weight: .heavy))
                    if let second = student?.secondaryNameLine {
                        Text(second).font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(chinese ? "投篮热区图" : "SHOT CHART").font(.system(size: 13, weight: .heavy)).foregroundStyle(.orange)
                    Text(date.formatted(.dateTime.year().month(.abbreviated).day()))
                        .font(.system(size: 12)).foregroundStyle(.black.opacity(0.55))
                }
            }
            ShotChartMap(zones: zones, colour: colour, forImage: true)
            if colour == .bands { ShotChartLegend(forImage: true) }
            ShotChartBreakdown(name: chinese ? "本次训练" : "This session", zones: zones,
                               comparison: comparison, forImage: true, chinese: chinese)
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

    @MainActor
    func image() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}
