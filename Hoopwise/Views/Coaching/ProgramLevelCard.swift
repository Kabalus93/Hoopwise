import SwiftUI

// MARK: - Program level (October 2026, Luther)
//
// "Not every U6 program is the same": some work on basics, others run drills
// from the age group above. The coach sets the level here; the plan
// generator reads it to choose which library ages a session draws from.
// Until it is set, the card shows what the players' evaluations suggest
// (only when at least half the roster is rated).

struct ProgramLevelCard: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var program: Program
    let enrolledStudents: [Student]

    @State private var draft: Double = 3

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var stored: Int? { program.skillTargets?.level }
    private var suggestion: (level: Int, rated: Int, average: Double)? {
        DrillPlanGenerator.suggestedLevel(
            students: enrolledStudents,
            players: enrolledStudents.compactMap { dataManager.player(for: $0.id) })
    }

    static func name(_ level: Int, chinese: Bool) -> String {
        switch level {
        case 1: return chinese ? "打基础" : "Foundations"
        case 2: return chinese ? "发展中" : "Developing"
        case 4: return chinese ? "进阶" : "Advanced"
        case 5: return chinese ? "精英" : "Elite"
        default: return chinese ? "符合年龄" : "On age"
        }
    }

    private func window(_ level: Int) -> String {
        let age = DrillPlanGenerator.libraryAge(for: program.ageGroup)
        let ages = DrillPlanGenerator.ageWeights(age: age, level: level)
            .sorted { $0.value > $1.value }.map(\.key.rawValue)
        return (isChinese ? "取材 " : "Draws on ") + ages.joined(separator: ", ")
    }

    var body: some View {
        let level = Int(draft.rounded())
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(isChinese ? "训练水平" : "Training level", systemImage: "dial.medium")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(level) · \(Self.name(level, chinese: isChinese))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText(value: draft))
            }
            Slider(value: $draft, in: 1...5, step: 1) {
                Text(isChinese ? "训练水平" : "Training level")
            } minimumValueLabel: {
                Text("1").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("5").font(.caption2).foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                if !editing { save(Int(draft.rounded())) }
            }
            .accessibilityIdentifier("program.level")
            Text(window(level))
                .font(.caption)
                .foregroundStyle(.secondary)
            footnote
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .onAppear { draft = Double(stored ?? suggestion?.level ?? 3) }
        .sensoryFeedback(.selection, trigger: level)
    }

    @ViewBuilder
    private var footnote: some View {
        if let s = suggestion {
            let line = isChinese
                ? "球员评估建议 \(s.level)（\(s.rated)/\(enrolledStudents.count) 人已评，均分 \(String(format: "%.1f", s.average))）"
                : "Evaluations suggest \(s.level) (\(s.rated)/\(enrolledStudents.count) rated, avg \(String(format: "%.1f", s.average)))"
            HStack(spacing: 8) {
                Text(line).font(.caption2).foregroundStyle(.tertiary)
                if stored != nil, stored != s.level {
                    Button(isChinese ? "采用" : "Use") { draft = Double(s.level); save(s.level) }
                        .font(.caption2.weight(.semibold))
                }
            }
        } else {
            Text(stored == nil
                 ? (isChinese ? "未设定：评估不足时按 3 生成计划" : "Not set: plans use 3 until enough players are evaluated")
                 : (isChinese ? "评估人数不足，无法给出建议" : "Too few players evaluated to suggest a level"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func save(_ level: Int) {
        guard program.skillTargets?.level != level else { return }
        var targets = program.skillTargets ?? ProgramSkillTargets()
        targets.level = level
        program.skillTargets = targets
        program.updatedAt = Date()
        dataManager.updateProgram(program)
    }
}
