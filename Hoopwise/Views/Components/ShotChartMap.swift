import SwiftUI

// THE SHOT CHART (21 Nov 2026, Luther: "this type of map … tap on a zone,
// enter numbers, the app calculates the percentage per student … useful and
// practical to show athletes"). Ten zones on a FIBA half court drawn in
// METRES, basket at the bottom as in a broadcast chart: at the rim, four
// mid-range (left baseline, left elbow, right elbow, right baseline), five
// threes (left corner, left wing, top, right wing, right corner). Zone order
// = ShootingDrill.shotChart's spots. Each zone is shaded by its percentage —
// absolute bands, or hot / cold against the athlete's own average — with
// the number on it; a zone can be tapped.

enum ShotChartColour: String, CaseIterable {
    case bands, ownAverage
    func title(chinese: Bool) -> String {
        switch self {
        case .bands: chinese ? "命中率" : "By %"
        case .ownAverage: chinese ? "对比自身平均" : "Vs own average"
        }
    }
}

struct ShotZoneValue: Hashable {
    var made: Double
    var attempted: Double
    var share: Double { attempted > 0 ? made / attempted : 0 }
}

enum ShotChartGeometry {
    static let width = 15.0, depth = 10.0
    static let rim = CGPoint(x: 0, y: 1.575)
    static let arc = 6.75, cornerX = 6.6
    static var cornerTop: Double { rim.y + (arc * arc - cornerX * cornerX).squareRoot() }
    static let rimZoneRadius = 2.5
    static var aspect: CGFloat { width / depth }

    /// Court metres → view points (basket at the bottom).
    static func transform(in rect: CGRect) -> CGAffineTransform {
        let s = min(rect.width / width, rect.height / depth)
        let ox = rect.midX - width * s / 2, oy = rect.midY - depth * s / 2
        return CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: ox + 7.5 * s, ty: oy + depth * s)
    }

    private static func sector(_ a0: Double, _ a1: Double) -> CGPath {
        let p = CGMutablePath()
        p.move(to: rim)
        p.addLine(to: CGPoint(x: rim.x + 40 * cos(a0 * .pi / 180), y: rim.y + 40 * sin(a0 * .pi / 180)))
        p.addArc(center: rim, radius: 40, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: false)
        p.closeSubpath()
        return p
    }

    private static var court: CGPath { CGPath(rect: CGRect(x: -7.5, y: 0, width: width, height: depth), transform: nil) }

    private static var threeInside: CGPath {
        let p = CGMutablePath()
        let yc = cornerTop
        let start = atan2(yc - rim.y, -cornerX), end = atan2(yc - rim.y, cornerX)
        p.move(to: CGPoint(x: -cornerX, y: 0))
        p.addLine(to: CGPoint(x: -cornerX, y: yc))
        p.addArc(center: rim, radius: arc, startAngle: start, endAngle: end, clockwise: true)
        p.addLine(to: CGPoint(x: cornerX, y: 0))
        p.closeSubpath()
        return p
    }

    /// The ten zones in court metres.
    static let zones: [CGPath] = {
        let rimDisc = CGPath(ellipseIn: CGRect(x: rim.x - rimZoneRadius, y: rim.y - rimZoneRadius,
                                               width: rimZoneRadius * 2, height: rimZoneRadius * 2), transform: nil)
            .intersection(court)
        let mid = threeInside.subtracting(rimDisc)
        let outside = court.subtracting(threeInside)
        let leftCornerBox = CGPath(rect: CGRect(x: -7.5, y: 0, width: 7.5 - cornerX, height: cornerTop), transform: nil)
        let rightCornerBox = CGPath(rect: CGRect(x: cornerX, y: 0, width: 7.5 - cornerX, height: cornerTop), transform: nil)
        let above = outside.subtracting(leftCornerBox).subtracting(rightCornerBox)
        return [
            rimDisc,
            mid.intersection(sector(135, 270)),      // left baseline
            mid.intersection(sector(90, 135)),       // left elbow
            mid.intersection(sector(45, 90)),        // right elbow
            mid.intersection(sector(-90, 45)),       // right baseline
            outside.intersection(leftCornerBox),
            above.intersection(sector(120, 270)),    // left wing
            above.intersection(sector(60, 120)),     // top
            above.intersection(sector(-90, 60)),     // right wing
            outside.intersection(rightCornerBox),
        ]
    }()

    /// Where each zone's number sits (metres), and its rotation.
    static let labels: [(CGPoint, Double)] = [
        (CGPoint(x: 0, y: 1.0), 0),
        (CGPoint(x: -4.7, y: 1.6), 0), (CGPoint(x: -2.4, y: 4.9), 0),
        (CGPoint(x: 2.4, y: 4.9), 0), (CGPoint(x: 4.7, y: 1.6), 0),
        (CGPoint(x: -7.05, y: 1.45), -90), (CGPoint(x: -6.1, y: 6.9), 0),
        (CGPoint(x: 0, y: 9.15), 0), (CGPoint(x: 6.1, y: 6.9), 0),
        (CGPoint(x: 7.05, y: 1.45), 90),
    ]

    /// The court's own lines, drawn over the zones.
    static var lines: CGPath {
        let p = CGMutablePath()
        p.addRect(CGRect(x: -2.45, y: 0, width: 4.9, height: 5.8))                   // lane
        p.addEllipse(in: CGRect(x: -1.8, y: 5.8 - 1.8, width: 3.6, height: 3.6))     // FT circle
        p.move(to: CGPoint(x: -0.9, y: 1.2)); p.addLine(to: CGPoint(x: 0.9, y: 1.2)) // backboard
        p.addEllipse(in: CGRect(x: -0.225, y: rim.y - 0.225, width: 0.45, height: 0.45))
        return p
    }
}

private struct ZoneShape: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        var t = ShotChartGeometry.transform(in: rect)
        return Path(ShotChartGeometry.zones[index].copy(using: &t) ?? CGMutablePath())
    }
}

private struct CourtLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var t = ShotChartGeometry.transform(in: rect)
        return Path(ShotChartGeometry.lines.copy(using: &t) ?? CGMutablePath())
    }
}

struct ShotChartMap: View {
    /// Ten zones (nil = no shots there).
    let zones: [ShotZoneValue?]
    /// Change vs before, in share points (−1…1), per zone.
    var deltas: [Double?]? = nil
    var colour: ShotChartColour = .bands
    var selected: Int? = nil
    var showCounts = true
    /// Light, for the shared image.
    var forImage = false
    var onTap: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var average: Double? {
        let all = zones.compactMap { $0 }
        let att = all.reduce(0) { $0 + $1.attempted }
        return att > 0 ? all.reduce(0) { $0 + $1.made } / att : nil
    }

    static func bandColour(_ v: Double) -> Color {
        switch v {
        case ..<0.25: Color(red: 0.36, green: 0.55, blue: 0.93)
        case ..<0.35: Color(red: 0.36, green: 0.76, blue: 0.80)
        case ..<0.45: Color(red: 0.98, green: 0.80, blue: 0.30)
        case ..<0.55: Color(red: 0.98, green: 0.58, blue: 0.24)
        default: Color(red: 0.92, green: 0.30, blue: 0.24)
        }
    }

    private func fill(_ i: Int) -> Color {
        guard let z = zones[i], z.attempted > 0 else {
            return forImage ? Color(white: 0.93) : Color(.tertiarySystemFill)
        }
        switch colour {
        case .bands: return Self.bandColour(z.share).opacity(0.85)
        case .ownAverage:
            guard let avg = average, avg > 0 else { return Color.orange.opacity(0.5) }
            if z.share >= avg * 1.15 { return Color(red: 0.92, green: 0.30, blue: 0.24).opacity(0.85) }
            if z.share <= avg * 0.85 { return Color(red: 0.36, green: 0.55, blue: 0.93).opacity(0.85) }
            return Color.orange.opacity(0.55)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let t = ShotChartGeometry.transform(in: rect)
            let unit = min(geo.size.width / ShotChartGeometry.width, geo.size.height / ShotChartGeometry.depth)
            ZStack {
                ForEach(0..<10, id: \.self) { i in
                    ZoneShape(index: i)
                        .fill(fill(i))
                        .overlay(ZoneShape(index: i).stroke(forImage ? Color.white : Color(.systemBackground), lineWidth: 1.5))
                        .overlay(ZoneShape(index: i).stroke(selected == i ? Color.accentColor : .clear, lineWidth: 3))
                        .contentShape(ZoneShape(index: i))
                        .onTapGesture { onTap?(i) }
                        .accessibilityElement()
                        .accessibilityLabel(ShootingDrill.shotChart.spotName(i, chinese: LocalizationManager.shared.currentLanguage == .chinese)
                                            + (zones[i].map { " \(Int(($0.share * 100).rounded()))%" } ?? ""))
                        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                        .accessibilityIdentifier("shotchart.zone.\(i)")
                }
                CourtLinesShape()
                    .stroke((forImage ? Color.black : Color.primary).opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
                ForEach(0..<10, id: \.self) { i in
                    label(i, unit: unit)
                        .rotationEffect(.degrees(ShotChartGeometry.labels[i].1))
                        .position(ShotChartGeometry.labels[i].0.applying(t))
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(ShotChartGeometry.aspect, contentMode: .fit)
    }

    @ViewBuilder
    private func label(_ i: Int, unit: CGFloat) -> some View {
        let corner = i == 5 || i == 9
        let ink: Color = forImage ? .black : .primary
        if let z = zones[i], z.attempted > 0 {
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Text("\(Int((z.share * 100).rounded()))%")
                        .font(.system(size: max(10, unit * (corner ? 0.42 : 0.62)), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    if let d = deltas?[i], abs(d) >= 0.01 {
                        Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: max(8, unit * 0.32), weight: .heavy))
                            .foregroundStyle(d > 0 ? Color.green : Color.red)
                    }
                }
                if showCounts && !corner {
                    Text("\(Int(z.made.rounded()))/\(Int(z.attempted.rounded()))")
                        .font(.system(size: max(8, unit * 0.32), weight: .semibold))
                        .monospacedDigit()
                        .opacity(0.75)
                }
            }
            .foregroundStyle(ink)
            .fixedSize()
        } else {
            Text("—").font(.system(size: max(9, unit * 0.4), weight: .bold)).foregroundStyle(ink.opacity(0.35))
        }
    }
}

/// The ten zones' values from one result (per spot = per zone).
extension ShootingResult {
    var zoneValues: [ShotZoneValue?] {
        (0..<setup.drill.spotCount).map { i in shots(at: i).map { ShotZoneValue(made: Double($0.made), attempted: Double($0.attempted)) } }
    }
}

/// The legend for the absolute bands.
struct ShotChartLegend: View {
    var forImage = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach([(0.2, "<25"), (0.3, "25"), (0.4, "35"), (0.5, "45"), (0.6, "55+")], id: \.1) { v, t in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(ShotChartMap.bandColour(v).opacity(0.85)).frame(width: 12, height: 8)
                    Text(t).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(forImage ? Color.black.opacity(0.6) : Color.secondary)
                }
            }
            Text("%").font(.system(size: 9, weight: .medium)).foregroundStyle(forImage ? Color.black.opacity(0.6) : Color.secondary)
        }
    }
}
