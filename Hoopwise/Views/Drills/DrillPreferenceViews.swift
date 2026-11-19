import SwiftUI

/// On a drill's page: how the plan engine should use it (19 Nov 2026,
/// Luther: "rate drills so that the engine knows to use more often or
/// never"). Use more · Normal · Use less · Never, and for the last two why.
struct DrillPreferenceCard: View {
    @EnvironmentObject var dataManager: DataManager
    let drill: DrillItem

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let preference = drill.preference
        VStack(alignment: .leading, spacing: 12) {
            Label(isChinese ? "在我的计划里" : "IN MY PLANS", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Picker(isChinese ? "使用频率" : "How often", selection: Binding(
                get: { preference },
                set: { new in dataManager.setDrillPreference(drill.id, new, reason: drill.preferenceReason) })) {
                ForEach(DrillPreference.allCases) { p in
                    Text(p.title(chinese: isChinese)).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drill.preference")

            if preference == .less || preference == .never {
                FlowLayout(spacing: 8) {
                    ForEach(DrillPreferenceReason.allCases) { reason in
                        let on = drill.preferenceReason == reason
                        Button {
                            dataManager.setDrillPreference(drill.id, preference, reason: on ? nil : reason)
                        } label: {
                            Text(reason.title(chinese: isChinese))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("drill.preference.\(reason.rawValue)")
                    }
                }
            }

            Text(footnote(preference))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("drill.preferenceCard")
    }

    private func footnote(_ p: DrillPreference) -> String {
        switch p {
        case .more: isChinese ? "生成计划时优先选用。" : "Generated plans pick it whenever it fits."
        case .normal: isChinese ? "按年龄、水平和重点正常选择。" : "Picked on age, level and focus like any drill."
        case .less: isChinese ? "只有在没有更合适的训练时才会选。" : "Picked only when little else fits."
        case .never: isChinese ? "生成计划时不再选用；你仍可以手动加入。" : "Generated plans leave it out. You can still add it by hand."
        }
    }
}

/// A small mark on a drill row for a drill the coach rated.
struct DrillPreferenceMark: View {
    let preference: DrillPreference

    var body: some View {
        switch preference {
        case .normal:
            EmptyView()
        case .more:
            Image(systemName: preference.icon).font(.caption2).foregroundStyle(.green)
        case .less:
            Image(systemName: preference.icon).font(.caption2).foregroundStyle(.orange)
        case .never:
            Image(systemName: preference.icon).font(.caption2).foregroundStyle(.red)
        }
    }
}
