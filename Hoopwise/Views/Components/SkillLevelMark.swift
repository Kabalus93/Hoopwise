import SwiftUI

/// THE LEVEL MARK (26 Nov 2026, Luther, pointing at the Mac's "● Below
/// average" pill: "also add this mark … to iPadOS and iOS"). The athlete's
/// level in their group as a small pill — the level's colour as a dot, its
/// name beside it — under the player card on the profile and in the Quick
/// Peep. For the coach only: it sits beside the card, never on it (the card
/// is what gets shared and printed). Nothing shows for an athlete without a
/// level (a private client, a group too small to rank).
struct SkillLevelMark: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.skillLevelProgram) private var program
    let studentId: UUID

    var body: some View {
        if let tier = dataManager.skillTier(for: studentId, program: program) {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            HStack(spacing: 7) {
                Circle().fill(Color(hex: tier.hex)).frame(width: 9, height: 9)
                Text(tier.title(chinese: zh)).lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .filmGlass(.regular, in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((zh ? "组内水平：" : "Level in the group: ") + tier.title(chinese: zh))
            .accessibilityIdentifier("athlete.levelMark")
        }
    }
}
