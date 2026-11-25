import SwiftUI

// EACH ATHLETE'S FOCUS (25 Nov 2026, Luther, after the audit: plans read the
// group, but nothing said what each child is working on). One or two of the
// eight skills per athlete — the coach's pick, else the two lowest-rated —
// shown on the roster in class (so a correction can be about THEIR thing),
// picked in the Quick Peep, printed on the progress report.

/// The small line on a roster row: "◎ Pass · Defend".
struct AthleteFocusLine: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID
    var font: Font = .caption2

    var body: some View {
        let focus = dataManager.athleteFocus(studentId)
        if !focus.isEmpty {
            // One small chip a skill, each with the skill's own icon (the
            // crosshair before the words read as nothing, and the line was
            // cut to "Create · D…" — 25 Nov 2026, Luther).
            HStack(spacing: 4) {
                ForEach(focus) { axis in
                    HStack(spacing: 3) {
                        Image(systemName: axis.icon).imageScale(.small)
                        Text(axis.short)
                    }
                    .font(font.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .fixedSize()
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((LocalizationManager.shared.currentLanguage == .chinese ? "重点：" : "Working on: ")
                                + focus.map(\.title).joined(separator: ", "))
            .accessibilityIdentifier("athlete.focus")
        }
    }
}

/// The Quick Peep's row: what they are working on, and a menu to pick it.
struct AthleteFocusPicker: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var skills: SkillsEvaluation? { dataManager.players.first { $0.studentId == studentId }?.skills }

    var body: some View {
        let picked = skills?.focus.compactMap(DrillAttribute.init(rawValue:)) ?? []
        let current = dataManager.athleteFocus(studentId)
        HStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(isChinese ? "现在的重点" : "Working on")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(current.isEmpty ? (isChinese ? "还没有定" : "Not set")
                                     : current.map(\.title).joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if picked.isEmpty, !current.isEmpty {
                    Text(isChinese ? "按评分最低的两项建议" : "Suggested: the two lowest ratings")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            Menu {
                ForEach(DrillAttribute.allCases, id: \.self) { axis in
                    Button {
                        toggle(axis, picked: picked.isEmpty ? [] : picked)
                    } label: {
                        if picked.contains(axis) { Label(axis.title, systemImage: "checkmark") } else { Text(axis.title) }
                    }
                }
                if !picked.isEmpty {
                    Divider()
                    Button(isChinese ? "改回建议" : "Back to the suggestion") {
                        dataManager.setAthleteFocus([], for: studentId)
                    }
                }
            } label: {
                Text(isChinese ? "选择" : "Choose")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
            }
            .accessibilityIdentifier("peep.focus.choose")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peep.focus")
    }

    /// Up to two; a third replaces the oldest pick.
    private func toggle(_ axis: DrillAttribute, picked: [DrillAttribute]) {
        var list = picked
        if let i = list.firstIndex(of: axis) { list.remove(at: i) }
        else { list.append(axis); if list.count > AthleteFocus.most { list.removeFirst() } }
        dataManager.setAthleteFocus(list, for: studentId)
    }
}
