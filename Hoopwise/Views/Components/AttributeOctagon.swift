import SwiftUI

// The eight-axis chart (November 2026): one drill's shape on its page, the
// whole plan's shape on the session's Plan, a phase's coverage on the
// program. Values are 0…1 per axis; an optional TARGET is drawn as a dashed
// outline so "what we train" sits over "what we wanted".

struct AttributeOctagon: View {
    let values: [DrillAttribute: Double]
    var target: [DrillAttribute: Double]? = nil
    var tint: Color = .accentColor
    var showLabels = true
    /// Axes flagged as neglected get an orange corner label.
    var flagged: Set<DrillAttribute> = []

    private let axes = DrillAttribute.allCases

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inset: CGFloat = showLabels ? max(34, size * 0.17) : 4
            let radius = size / 2 - inset
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // Grid: three rings (1, 2, 3 on a drill's scale) and spokes.
                ForEach(1...3, id: \.self) { ring in
                    polygon(centre: centre, radius: radius) { _ in Double(ring) / 3 }
                        .stroke(Color.secondary.opacity(ring == 3 ? 0.35 : 0.18), lineWidth: ring == 3 ? 1 : 0.6)
                }
                Path { path in
                    for i in axes.indices {
                        path.move(to: centre)
                        path.addLine(to: point(i, 1, centre: centre, radius: radius))
                    }
                }
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.6)

                let shape = polygon(centre: centre, radius: radius) { values[$0] ?? 0 }
                shape.fill(tint.opacity(0.28))
                shape.stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                if let target {
                    polygon(centre: centre, radius: radius) { target[$0] ?? 0 }
                        .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [4, 3]))
                }

                if showLabels {
                    ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                        let p = point(i, 1, centre: centre, radius: radius + inset * 0.55)
                        Text(axis.short)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(flagged.contains(axis) ? Color.orange : .secondary)
                            .fixedSize()
                            .position(p)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DrillAttribute.allCases
            .map { "\($0.title) \(Int(((values[$0] ?? 0) * 3).rounded()))" }.joined(separator: ", "))
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
            HStack(alignment: .center, spacing: 16) {
                AttributeOctagon(values: profile.normalized)
                    .frame(width: 190, height: 190)
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
                Spacer(minLength: 0)
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
