import SwiftUI

// THE ATHLETE ON THE MAC (25 Nov 2026, Luther: "even the student card (since
// nothing is shared from the computer but from the iPad or iOS)"). The
// collectible card is made to be sent and printed, and that happens on the
// iPad and the phone. On the Mac the profile opens on a pane of glass
// instead: who they are on the left, their numbers in light type on the
// right, what they are working on underneath. Same facts as the card
// (AthleteCardFacts) — nothing is computed twice.

struct MacAthleteHeader: View {
    @EnvironmentObject private var dataManager: DataManager
    let student: Student

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let stored = dataManager.students.first { $0.id == student.id } ?? student
        let facts = dataManager.athleteCard(for: stored)
        let focus = dataManager.athleteFocus(stored.id)
        let tier = dataManager.skillTier(for: stored.id)
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 22) {
                StudentAvatarView(student: stored, size: 96)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(stored.primaryDisplayName)
                        .font(.system(size: 30, weight: .light))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let second = stored.secondaryNameLine {
                        Text(second).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text([facts.schoolGrade, facts.program, facts.ageGroup].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    FlowLayout(spacing: 8) {
                        if let tier {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: tier.hex)).frame(width: 8, height: 8)
                                Text(tier.title(chinese: zh)).lineLimit(1)
                            }
                            .macChip().fixedSize()
                        }
                        if !focus.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "scope").foregroundStyle(.orange)
                                Text(focus.map(\.short).joined(separator: " · ")).lineLimit(1)
                            }
                            .macChip().fixedSize()
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            // The numbers: light, large, their words small underneath. They
            // wrap as a row of their own, so a narrow pane never squeezes them.
            if facts.gamesPlayed > 0 || facts.classesExpected > 0 {
                FlowLayout(spacing: 30) {
                    if facts.gamesPlayed > 0 {
                        number(value(facts, .points), zh ? "得分" : "PPG")
                        number(value(facts, .rebounds), zh ? "篮板" : "RPG")
                        number(value(facts, .assists), zh ? "助攻" : "APG")
                        number("\(facts.gamesPlayed)", zh ? "比赛" : "GAMES")
                    }
                    if facts.classesExpected > 0 {
                        number("\(facts.classesAttended)/\(facts.classesExpected)", zh ? "本月到课" : "THIS MONTH")
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filmGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("athlete.macHeader")
    }

    private func value(_ facts: AthleteCardFacts, _ metric: GameStatsReport.Metric) -> String {
        String(format: "%.1f", facts.perGame[metric] ?? 0)
    }

    private func number(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .light)).monospacedDigit().lineLimit(1)
            Text(label).font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A small quiet label on the Mac's glass.
    func macChip() -> some View {
        font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
