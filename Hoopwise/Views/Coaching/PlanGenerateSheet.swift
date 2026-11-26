import SwiftUI

/// Generate / Regenerate with the coach's say (19 Nov 2026, Luther: "when
/// tapping on generate, let's make it a custom generate with coach input —
/// different parameters that would make the plan perfect"). Every choice
/// starts where the engine would put it, so Generate alone gives the plan it
/// always gave; the coach changes only what they want different.
struct PlanGenerateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: DrillPlanGenerator.Context
    /// Whether the plan already has drills (Regenerate) — offers Keep.
    let hasPlan: Bool
    let onGenerate: (DrillPlanGenerator.Options) -> Void

    @State private var skills: Set<DrillAttribute>
    @State private var warmup: Int
    @State private var skillsBlock: Int
    @State private var level: Int
    private let engineLevel: Int
    @State private var mix: Mix = .auto
    @State private var keepExisting = false
    @State private var avoidLast = true

    enum Mix: String, CaseIterable, Identifiable {
        case auto, allNew, balanced, review
        var id: String { rawValue }
        var share: Double? {
            switch self {
            case .auto: nil
            case .allNew: 0
            case .balanced: 0.5
            case .review: 0.8
            }
        }
    }

    init(context: DrillPlanGenerator.Context, hasPlan: Bool,
         onGenerate: @escaping (DrillPlanGenerator.Options) -> Void) {
        self.context = context
        self.hasPlan = hasPlan
        self.onGenerate = onGenerate
        let gaps = DrillPlanGenerator.phaseGaps(context)
        _skills = State(initialValue: Set(gaps.filter { $0.value >= 0.4 }.sorted { $0.value > $1.value }.prefix(2).map(\.key)))
        let cur = context.session.curriculum
        let length = max(30, Int(context.session.endTime.timeIntervalSince(context.session.startTime) / 60))
        _warmup = State(initialValue: cur.warmupMinutes > 0 ? cur.warmupMinutes : length / 3)
        _skillsBlock = State(initialValue: cur.skillsMinutes > 0 ? cur.skillsMinutes : length / 3)
        let resolved = DrillPlanGenerator.resolveLevel(program: context.program, students: context.enrolledStudents,
                                                       players: context.players).0
        engineLevel = resolved
        _level = State(initialValue: resolved)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// The skills most of this class's athletes have as their focus.
    private var athleteFocus: [(axis: DrillAttribute, athletes: Int)] {
        AthleteFocus.common(among: context.enrolledStudents.map(\.id), players: context.players)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(DrillAttribute.allCases, id: \.self) { axis in
                            let on = skills.contains(axis)
                            Button {
                                if on { skills.remove(axis) } else { skills.insert(axis) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: axis.icon).font(.caption)
                                    Text(axis.title).font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("generate.skill.\(axis.rawValue)")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    // What the athletes themselves are working on — offered,
                    // never preselected (Luther: "suggest rather than steer").
                    let offered = athleteFocus.filter { !skills.contains($0.axis) }
                    if !offered.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isChinese ? "学员正在练的重点" : "What the athletes are working on")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 8) {
                                ForEach(offered, id: \.axis) { item in
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) { _ = skills.insert(item.axis) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus").font(.caption2.weight(.bold))
                                            Text(isChinese
                                                 ? "\(item.axis.title) · \(item.athletes) 人"
                                                 : "\(item.axis.title) · \(item.athletes) athletes")
                                                .font(.subheadline)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .foregroundStyle(Color.orange)
                                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.6), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("generate.focus.\(item.axis.rawValue)")
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(isChinese ? "这节课练什么" : "Build it around")
                } footer: {
                    Text(isChinese ? "已选的是本阶段的短板；不选则按阶段重点和评估。"
                                   : "Preselected: what the phase has neglected so far. None = phase focus and evaluations decide.")
                }

                Section(isChinese ? "时间" : "Time") {
                    Stepper(value: $warmup, in: 5...60, step: 5) {
                        LabeledContent(isChinese ? "热身" : "Warm-up", value: isChinese ? "\(warmup) 分钟" : "\(warmup) min")
                    }
                    .accessibilityIdentifier("generate.warmup")
                    Stepper(value: $skillsBlock, in: 5...90, step: 5) {
                        LabeledContent(isChinese ? "技能" : "Skills", value: isChinese ? "\(skillsBlock) 分钟" : "\(skillsBlock) min")
                    }
                    .accessibilityIdentifier("generate.skills")
                }

                Section {
                    Picker(isChinese ? "水平" : "Level", selection: $level) {
                        ForEach(1...5, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("generate.level")
                } header: {
                    Text(isChinese ? "难度" : "Level")
                } footer: {
                    Text(isChinese ? "1 偏向更小年龄段的训练，5 借用更大年龄段的。引擎建议：\(engineLevel)。"
                                   : "1 leans on younger ages' drills, 5 borrows older ones. The engine's pick: \(engineLevel).")
                }

                Section {
                    Picker(isChinese ? "新旧搭配" : "New or review", selection: $mix) {
                        Text(isChinese ? "自动" : "Auto").tag(Mix.auto)
                        Text(isChinese ? "全新" : "All new").tag(Mix.allNew)
                        Text(isChinese ? "各半" : "Half").tag(Mix.balanced)
                        Text(isChinese ? "以复习为主" : "Mostly review").tag(Mix.review)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("generate.mix")
                    Toggle(isChinese ? "不重复上节课的训练" : "Don't repeat last class", isOn: $avoidLast)
                    if hasPlan {
                        Toggle(isChinese ? "保留已排的训练，只补剩余时间" : "Keep what's planned, fill the rest", isOn: $keepExisting)
                            .accessibilityIdentifier("generate.keep")
                    }
                } header: {
                    Text(isChinese ? "搭配" : "Mix")
                } footer: {
                    Text(isChinese ? "自动：阶段前两节以新内容为主，之后多复习。"
                                   : "Auto: a phase's first two classes mostly introduce, later ones mostly review.")
                }
            }
            .navigationTitle(hasPlan ? (isChinese ? "重新生成计划" : "Regenerate Plan") : (isChinese ? "生成计划" : "Generate Plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onGenerate(options)
                        dismiss()
                    } label: {
                        Label(isChinese ? "生成" : "Generate", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("generate.go")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var options: DrillPlanGenerator.Options {
        DrillPlanGenerator.Options(
            warmupMinutes: warmup,
            skillsMinutes: skillsBlock,
            level: level == engineLevel ? nil : level,
            skills: skills,
            reviewShare: mix.share,
            keepExisting: hasPlan && keepExisting,
            avoidLastSession: avoidLast)
    }
}
