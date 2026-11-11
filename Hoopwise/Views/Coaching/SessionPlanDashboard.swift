import SwiftUI

// The top of a session's Plan as a DASHBOARD (November 2026, Luther: "the
// plan page becomes a dashboard for the session"): the plan's octagon — what
// its drills and plays train, weighted by minutes — over a dashed TARGET from
// the phase focus and the program's skill targets (a team practice: its
// focus plays' skills), what it leans on, and what it neglects with a way to
// fix it (the drill picker, filtered to drills strong on that axis).

struct SessionPlanDashboard: View {
    let curriculum: SessionCurriculum
    let drills: [DrillItem]
    let teams: [Team]
    let phaseFocus: [TrainingFocus]
    let skillTargets: ProgramSkillTargets?
    var teamSkills: [String] = []
    var canEdit = true
    var onFind: (DrillAttribute) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let minutes = PlanCoverage.minutes(of: curriculum, drills: drills,
                                           playProfile: { PlanCoverage.playProfile($0, teams: teams) })
        let plan = PlanCoverage.normalized(minutes)
        let target = PlanCoverage.target(phaseFocus: phaseFocus, skillTargets: skillTargets, teamSkills: teamSkills)
        let neglected = PlanCoverage.neglected(plan: minutes, target: target)
        let leans = PlanCoverage.emphasis(minutes).prefix(3)
        let empty = plan.isEmpty

        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "计划平衡" : "PLAN BALANCE").font(.caption2.weight(.bold)).monospaced()
            } icon: {
                Image(systemName: "octagon").font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("plan.dashboard")

            HStack(alignment: .center, spacing: 16) {
                AttributeOctagon(values: plan, target: target, flagged: Set(neglected))
                    .frame(width: 180, height: 180)
                VStack(alignment: .leading, spacing: 10) {
                    if empty {
                        Text(isChinese ? "添加训练后，这里会显示计划练了哪些能力。" : "Add drills and this shows what the plan trains.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "侧重" : "Leans on").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(leans), id: \.self) { axis in
                                HStack(spacing: 6) {
                                    Image(systemName: axis.icon).font(.caption).foregroundStyle(Color.accentColor).frame(width: 18)
                                    Text(axis.title).font(.subheadline.weight(.semibold))
                                    Text(isChinese ? "约 \(Int((minutes[axis] ?? 0).rounded())) 分钟" : "~\(Int((minutes[axis] ?? 0).rounded())) min")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !neglected.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isChinese ? "被忽略" : "Neglected").font(.caption).foregroundStyle(.orange)
                            ForEach(neglected, id: \.self) { axis in
                                HStack(spacing: 6) {
                                    Image(systemName: axis.icon).font(.caption).foregroundStyle(.orange).frame(width: 18)
                                    Text(axis.title).font(.subheadline.weight(.medium))
                                    Spacer(minLength: 4)
                                    if canEdit {
                                        Button(isChinese ? "找训练" : "Find drills") { onFind(axis) }
                                            .font(.caption.weight(.semibold))
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                            .accessibilityIdentifier("plan.find.\(axis.rawValue)")
                                    }
                                }
                            }
                        }
                    } else if target != nil && !empty {
                        Label(isChinese ? "覆盖了本阶段的重点" : "Covers what this stage asks for", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
            }

            if target != nil {
                HStack(spacing: 14) {
                    legend(dashed: false, text: isChinese ? "计划" : "Plan")
                    legend(dashed: true, text: teamSkills.isEmpty
                           ? (isChinese ? "目标：阶段重点 + 项目目标" : "Target: phase focus + program goals")
                           : (isChinese ? "目标：球队重点战术" : "Target: the team's focus plays"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private func legend(dashed: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)) }
                .stroke(dashed ? Color.primary.opacity(0.55) : Color.accentColor,
                        style: StrokeStyle(lineWidth: dashed ? 1.5 : 2, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 8)
            Text(text)
        }
    }
}

// MARK: - The program: what each phase's plans train

/// On the program page: one phase at a time (the current one first), the
/// octagon of everything its sessions' plans train against the same target
/// as a session — phase focus + program goals — and what it neglects. Generate
/// Plan reads the same gap (DrillPlanGenerator.phaseGaps).
struct PhaseCoverageCard: View {
    let program: Program
    @EnvironmentObject var dataManager: DataManager
    @State private var phaseId: UUID?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var phases: [MicroCycle] {
        dataManager.microCycles.filter { $0.programId == program.id }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private var defaultPhase: MicroCycle? {
        let now = Date()
        return phases.first { ($0.startDate ?? .distantFuture) <= now && ($0.endDate ?? .distantPast) >= now }
            ?? phases.first { ($0.startDate ?? .distantPast) > now } ?? phases.last
    }

    var body: some View {
        if let phase = phases.first(where: { $0.id == phaseId }) ?? defaultPhase {
            card(phase)
        }
    }

    private func card(_ phase: MicroCycle) -> some View {
        let sessions = dataManager.sessionEvents.filter {
            $0.microCycleId == phase.id && !SessionLifecycle.didNotHappen($0)
        }
        let planned = sessions.filter { $0.curriculum.totalDrillCount > 0 }
        var minutes: [DrillAttribute: Double] = [:]
        for session in planned {
            for (axis, v) in PlanCoverage.minutes(of: session.curriculum, drills: dataManager.drills,
                                                  playProfile: { PlanCoverage.playProfile($0, teams: dataManager.teams) }) {
                minutes[axis, default: 0] += v
            }
        }
        let target = PlanCoverage.target(phaseFocus: phase.focus, skillTargets: program.skillTargets)
        let neglected = PlanCoverage.neglected(plan: minutes, target: target)
        let leans = PlanCoverage.emphasis(minutes).prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(isChinese ? "阶段训练平衡" : "PHASE BALANCE").font(.caption2.weight(.bold)).monospaced()
                } icon: { Image(systemName: "octagon").font(.caption) }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("program.coverage")
                Spacer()
                if phases.count > 1 {
                    Menu {
                        ForEach(phases) { p in
                            Button(p.title) { phaseId = p.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(phase.title).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("program.coverage.phase")
                } else {
                    Text(phase.title).font(.subheadline.weight(.semibold))
                }
            }
            HStack(alignment: .center, spacing: 16) {
                AttributeOctagon(values: PlanCoverage.normalized(minutes), target: target, flagged: Set(neglected))
                    .frame(width: 170, height: 170)
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "\(planned.count) / \(sessions.count) 节课已有计划" : "\(planned.count) of \(sessions.count) sessions planned")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !leans.isEmpty {
                        Text((isChinese ? "侧重：" : "Leans on: ") + leans.map(\.title).joined(separator: ", "))
                            .font(.subheadline)
                    }
                    if !neglected.isEmpty {
                        Text((isChinese ? "被忽略：" : "Neglected: ") + neglected.map(\.title).joined(separator: ", "))
                            .font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                        Text(isChinese ? "生成计划时会补上这些。" : "Generate Plan leans toward these.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if target != nil && !planned.isEmpty {
                        Label(isChinese ? "覆盖了阶段重点" : "Covers the phase focus", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
