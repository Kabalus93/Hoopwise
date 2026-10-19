import SwiftUI

/// Plans a training cycle for a program: dates, level and emphasis in, phases
/// with sessions and session plans out (CyclePlanner). The preview is live —
/// every change re-plans, so the coach sees the phases before anything is
/// written.
struct CyclePlannerSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let program: Program
    /// Where the cycle starts: the day after the last phase, or today.
    let defaultStart: Date
    var onDone: (CyclePlanner.Result) -> Void = { _ in }

    @State private var start = Date()
    @State private var target = Date()
    @State private var level: Double = 3
    @State private var emphasis: [ActivityType] = []
    @State private var loaded = false
    @State private var suggested: [ActivityType] = []

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var enrolled: [Student] { dataManager.students.filter { program.enrolledStudentIds.contains($0.id) } }
    private var players: [Player] { enrolled.compactMap { dataManager.player(for: $0.id) } }
    private var games: [SessionGame] { dataManager.sessionEvents.filter { $0.programId == program.id }.flatMap(\.games) }

    private var input: CyclePlanner.Input {
        .init(program: program, start: start, target: target, level: Int(level.rounded()), emphasis: emphasis)
    }
    private var planned: [CyclePlanner.PlannedPhase] { CyclePlanner.plan(input) }
    private var weeks: Int {
        max(0, (Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0) + 1) / 7
    }

    var body: some View {
        NavigationStack {
            Form {
                datesSection
                levelSection
                emphasisSection
                previewSection
            }
            .navigationTitle(isChinese ? "规划训练周期" : "Plan a cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create") { create() }
                        .fontWeight(.semibold)
                        .disabled(planned.isEmpty)
                        .accessibilityIdentifier("cycle.create")
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Sections

    private var datesSection: some View {
        Section {
            DatePicker(isChinese ? "开始" : "Starts", selection: $start, displayedComponents: .date)
            DatePicker(isChinese ? "目标日期" : "Deliver by", selection: $target,
                       in: start.addingTimeInterval(7 * 86_400)..., displayedComponents: .date)
                .accessibilityIdentifier("cycle.target")
            HStack(spacing: 8) {
                ForEach([8, 12, 16], id: \.self) { w in
                    quickChip(isChinese ? "\(w) 周" : "\(w) wks") {
                        target = Calendar.current.date(byAdding: .day, value: w * 7 - 1, to: start) ?? target
                    }
                }
                if let end = program.endDate, end > start {
                    quickChip(isChinese ? "到项目结束" : "Program end") { target = end }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } header: {
            Text(isChinese ? "日期" : "Dates")
        } footer: {
            Text(program.endDate == nil
                 ? (isChinese ? "项目没有结束日期，但每个周期都需要一个目标日期来衡量球员成长。结束前两周会提醒你规划下一周期。"
                              : "This program has no end date, but every cycle needs a date to deliver by. You'll be reminded to plan the next cycle two weeks before it.")
                 : (isChinese ? "结束前两周会提醒你规划下一周期。" : "You'll be reminded to plan the next cycle two weeks before the target."))
        }
    }

    private var levelSection: some View {
        let l = Int(level.rounded())
        return Section {
            HStack {
                Text(isChinese ? "训练水平" : "Training level")
                Spacer()
                Text("\(l) · \(ProgramLevelCard.name(l, chinese: isChinese))")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
            Slider(value: $level, in: 1...5, step: 1)
        } footer: {
            Text(levelFootnote(l))
        }
    }

    private func levelFootnote(_ l: Int) -> String {
        let age = program.ageGroup.rawValue
        switch l {
        case 4...5: return isChinese ? "高于 \(age) 的水平：采用更高年龄段的阶段安排和训练。" : "Above \(age): phases and activities from the next age group up."
        case ...1: return isChinese ? "打基础：采用更低年龄段的阶段安排。" : "Foundations: phases from the age group below."
        default: return isChinese ? "按 \(age) 年龄段安排。" : "Phases for \(age)."
        }
    }

    private var emphasisSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(CyclePlanner.emphasisChoices) { t in
                    let on = emphasis.contains(t)
                    Button {
                        if on { emphasis.removeAll { $0 == t } } else { emphasis.append(t) }
                    } label: {
                        Text(t.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(isChinese ? "重点" : "Emphasis")
        } footer: {
            Text(suggested.isEmpty
                 ? (isChinese ? "球员评估与比赛数据还不足以建议重点，可自行选择。加入每个阶段的重点。"
                              : "Not enough evaluations or game stats to suggest an emphasis yet — pick your own. Added to every phase's focus.")
                 : (isChinese ? "已按球员评估与比赛数据预选，可修改。加入每个阶段的重点。"
                              : "Preselected from player evaluations and game stats; change freely. Added to every phase's focus."))
        }
    }

    private var previewSection: some View {
        let phases = planned
        let total = phases.reduce(0) { $0 + $1.sessionCount }
        return Section {
            if phases.isEmpty {
                Text(isChinese ? "目标日期需晚于开始日期至少一周" : "The target must be at least a week after the start")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(phases.enumerated()), id: \.offset) { i, p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(i + 1). \(p.template.title.resolve())").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(isChinese ? "\(p.weeks) 周 · \(p.sessionCount) 节" : "\(p.weeks) wk · \(p.sessionCount) sessions")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(p.start.formatted(.dateTime.month().day())) – \(p.end.formatted(.dateTime.month().day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(p.focus.prefix(4).map(\.displayName).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityIdentifier("cycle.phase")
            }
        } header: {
            Text(isChinese ? "预览 · \(weeks) 周 · \(total) 节课" : "Preview · \(weeks) weeks · \(total) sessions")
        } footer: {
            Text(isChinese ? "将在项目上课日创建课程，并为每节课生成计划（按日期顺序，复习与新内容逐步推进）。已有的课程会归入对应阶段，你写好的计划不会改动。"
                           : "Sessions are created on the program's days and every session gets a plan, in date order so review and new material build up. Sessions already on those dates join their phase; plans you've written are left alone.")
        }
    }

    private func quickChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / create

    private func load() {
        guard !loaded else { return }
        loaded = true
        let cal = Calendar.current
        start = cal.startOfDay(for: defaultStart)
        if let end = program.endDate, end > start.addingTimeInterval(7 * 86_400) {
            target = end
        } else {
            target = cal.date(byAdding: .day, value: 12 * 7 - 1, to: start) ?? start
        }
        let (resolved, _) = DrillPlanGenerator.resolveLevel(program: program, students: enrolled, players: players)
        level = Double(resolved)
        suggested = CyclePlanner.suggestedEmphasis(students: enrolled, players: players, games: games)
        emphasis = suggested
    }

    private func create() {
        let result = CyclePlanner.apply(planned, input: input, dataManager: dataManager)
        HapticFeedback.notification(.success)
        onDone(result)
        dismiss()
    }
}
