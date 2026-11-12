import SwiftUI

// The eight-axis chart (November 2026): one drill's shape on its page, the
// whole plan's shape on the session's Plan, a phase's coverage on the
// program. Values are 0…1 per axis. An optional TARGET is a tick across each
// spoke it asks for, so "what we train" reads against "what we wanted".
//
// Drawn quietly (Luther: the first version "looks more like a bug than a
// chart"): hairline grid on a faint base, one 1.75 pt stroke with small
// vertex dots, target ticks instead of a dashed outline, and every shape
// floored at a small inner ring — a zero used to pull the outline into the
// centre and draw spikes.

struct AttributeOctagon: View {
    let values: [DrillAttribute: Double]
    var target: [DrillAttribute: Double]? = nil
    var tint: Color = .accentColor
    var showLabels = true
    /// Axes flagged as neglected get an orange corner label.
    var flagged: Set<DrillAttribute> = []

    private let axes = DrillAttribute.allCases
    /// A zero sits on this ring, not at the centre.
    private let floorRing = 0.12

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inset: CGFloat = showLabels ? max(28, size * 0.15) : 4
            let radius = size / 2 - inset
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                grid(centre: centre, radius: radius)


                if values.values.contains(where: { $0 > 0 }) {
                    let shape = polygon(centre: centre, radius: radius) { shown(values[$0] ?? 0) }
                    shape.fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.14)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.stroke(tint, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                    ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                        if (values[axis] ?? 0) > 0.02 {
                            Circle()
                                .fill(tint)
                                .frame(width: 5, height: 5)
                                .position(point(i, shown(values[axis] ?? 0), centre: centre, radius: radius))
                        }
                    }
                }

                // The target: a tick across each spoke it asks for, at the
                // level it asks for — a sparse target drawn as an area made
                // a star.
                if let target {
                    ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                        if let want = target[axis], want >= 0.45 {
                            targetTick(i, shown(want), centre: centre, radius: radius,
                                       colour: flagged.contains(axis) ? .orange : Color.primary.opacity(0.55))
                        }
                    }
                }

                if showLabels {
                    ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                        label(axis, at: i, centre: centre, radius: radius + 7)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DrillAttribute.allCases
            .map { "\($0.title) \(Int(((values[$0] ?? 0) * 3).rounded()))" }.joined(separator: ", "))
    }

    /// Hairline rings at 1, 2 and 3 of a drill's scale, faint spokes, and a
    /// barely-there fill so the chart reads as one object.
    private func grid(centre: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            polygon(centre: centre, radius: radius) { _ in 1 }
                .fill(Color.primary.opacity(0.035))
            ForEach(1...3, id: \.self) { ring in
                polygon(centre: centre, radius: radius) { _ in shown(Double(ring) / 3) }
                    .stroke(Color.primary.opacity(ring == 3 ? 0.16 : 0.08), lineWidth: 0.5)
            }
            Path { path in
                for i in axes.indices {
                    path.move(to: point(i, floorRing, centre: centre, radius: radius))
                    path.addLine(to: point(i, 1, centre: centre, radius: radius))
                }
            }
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    /// A short rounded bar across spoke `i` at `value`.
    private func targetTick(_ i: Int, _ value: Double, centre: CGPoint, radius: CGFloat, colour: Color) -> some View {
        let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(axes.count)
        let p = point(i, value, centre: centre, radius: radius)
        let half: CGFloat = 6
        let dx = CGFloat(-sin(angle)) * half, dy = CGFloat(cos(angle)) * half
        return Path { path in
            path.move(to: CGPoint(x: p.x - dx, y: p.y - dy))
            path.addLine(to: CGPoint(x: p.x + dx, y: p.y + dy))
        }
        .stroke(colour, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    /// A corner label sitting OUTSIDE its corner: right-side labels grow
    /// rightward, left-side leftward, top and bottom centred.
    private func label(_ axis: DrillAttribute, at i: Int, centre: CGPoint, radius: CGFloat) -> some View {
        let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(axes.count)
        let p = point(i, 1, centre: centre, radius: radius)
        let c = cos(angle), sn = sin(angle)
        let alignment: Alignment = abs(c) < 0.2 ? (sn < 0 ? .bottom : .top) : (c > 0 ? .leading : .trailing)
        let isFlagged = flagged.contains(axis)
        return Text(axis.short)
            .font(.caption2.weight(isFlagged ? .semibold : .medium))
            .foregroundStyle(isFlagged ? Color.orange : Color.secondary)
            .fixedSize()
            .frame(width: 120, height: 30, alignment: alignment)
            .position(x: p.x + (alignment == .leading ? 60 : alignment == .trailing ? -60 : 0),
                      y: p.y + (alignment == .bottom ? -15 : alignment == .top ? 15 : 0))
    }

    /// 0…1 drawn between the floor ring and the edge.
    private func shown(_ value: Double) -> Double {
        floorRing + (1 - floorRing) * max(0, min(1, value))
    }

    private func point(_ i: Int, _ value: Double, centre: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(axes.count)
        let r = radius * CGFloat(max(0, min(1, value)))
        return CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle)))
    }

    private func polygon(centre: CGPoint, radius: CGFloat, value: (DrillAttribute) -> Double) -> Path {
        Path { path in
            for (i, axis) in axes.enumerated() {
                let p = point(i, value(axis), centre: centre, radius: radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}

extension AttributeProfile {
    /// 0…1 per axis on a drill's 0–3 scale.
    var normalized: [DrillAttribute: Double] {
        Dictionary(uniqueKeysWithValues: DrillAttribute.allCases.map { ($0, Double(self[$0]) / 3) })
    }
}

// MARK: - On a drill's page

/// "What it develops": the drill's octagon, its main axes in words, where the
/// scores come from, and an Adjust sheet (the coach's rating wins).
struct DrillAttributesCard: View {
    let drill: DrillItem
    var onSave: (AttributeProfile) -> Void
    var onReset: (() -> Void)? = nil
    @State private var editing = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let profile = drill.attributes
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isChinese ? "训练能力" : "What it develops", systemImage: "hexagon")
                    .font(.headline)
                    .accessibilityIdentifier("drill.attributes")
                Spacer()
                Button(isChinese ? "调整" : "Adjust") { editing = true }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("drill.attributes.adjust")
            }
            OctagonCardLayout {
                AttributeOctagon(values: profile.normalized)
                    .frame(width: 190, height: 190)
            } details: {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(profile.main, id: \.self) { axis in
                        HStack(spacing: 6) {
                            Image(systemName: axis.icon).font(.caption).foregroundStyle(Color.accentColor).frame(width: 18)
                            Text(axis.title).font(.subheadline.weight(.medium))
                            Text(String(repeating: "●", count: profile[axis]) + String(repeating: "○", count: 3 - profile[axis]))
                                .font(.caption2).foregroundStyle(Color.accentColor)
                        }
                    }
                    let touched = DrillAttribute.allCases.filter { profile[$0] == 1 }
                    if !touched.isEmpty {
                        Text((isChinese ? "也涉及：" : "Also: ") + touched.map(\.title).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(sourceLine).font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .sheet(isPresented: $editing) {
            AttributeEditorSheet(profile: profile, onSave: onSave,
                                 onReset: drill.attributesSource == .coach ? onReset : nil)
        }
    }

    private var sourceLine: String {
        switch drill.attributesSource {
        case .coach: return isChinese ? "由你调整" : "Adjusted by you"
        case .claude: return isChinese ? "由 Claude 评估" : "Rated by Claude"
        case .guess: return isChinese ? "按训练类型估算" : "Estimated from the drill type"
        }
    }
}

/// The eight scores, 0–3 each, as segmented rows.
struct AttributeEditorSheet: View {
    @State var profile: AttributeProfile
    var onSave: (AttributeProfile) -> Void
    var onReset: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AttributeOctagon(values: profile.normalized)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(DrillAttribute.allCases) { axis in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(axis.title, systemImage: axis.icon).font(.subheadline.weight(.medium))
                            Picker(axis.title, selection: Binding(get: { profile[axis] }, set: { profile[axis] = $0 })) {
                                Text(isChinese ? "无" : "None").tag(0)
                                Text(isChinese ? "涉及" : "Touched").tag(1)
                                Text(isChinese ? "练到" : "Worked").tag(2)
                                Text(isChinese ? "重点" : "Main").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text(isChinese ? "你的评分会覆盖 Claude 的评估，并用于课程计划的能力图。"
                                   : "Your rating replaces Claude's and feeds the session plan's chart.")
                }
                if let onReset {
                    Section {
                        Button(isChinese ? "恢复 Claude 的评估" : "Go back to Claude's rating", role: .destructive) {
                            onReset()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "训练能力" : "What it develops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { onSave(profile); dismiss() }
                        .accessibilityIdentifier("drill.attributes.save")
                }
            }
        }
    }
}

/// An octagon with its words: side by side when the card is wide, the words
/// UNDER the chart when it is narrow — beside it on a phone they broke
/// mid-word ("De-fense", Luther, November 2026).
struct OctagonCardLayout<Chart: View, Details: View>: View {
    @ViewBuilder var chart: () -> Chart
    @ViewBuilder var details: () -> Details
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width >= 520 {
                HStack(alignment: .center, spacing: 16) {
                    chart()
                    details()
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    chart().frame(maxWidth: .infinity)
                    details()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
