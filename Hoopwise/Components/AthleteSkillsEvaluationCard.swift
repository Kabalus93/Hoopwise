import SwiftUI

// THE SKILLS EVALUATION CARD — the eight octagon skills, 1–10, with game and
// drill evidence under them, the focus picker and the evaluation history.
// Was the Quick Peep's own section; the athlete profile shows it too since
// 27 Nov 2026 (Luther, markup on the iPad profile: "add here the evaluation
// sliders"). One card, one save path (recordEvaluation through updatePlayer).

struct AthleteSkillsEvaluationCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student

    @State private var isEditingSkills = false
    @State private var editedSkills = SkillsEvaluation()

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var player: Player? { dataManager.player(for: student.id) }
    private var skills: SkillsEvaluation { player?.skills ?? SkillsEvaluation() }
    private var enrolledProgram: Program? {
        dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) }
    }

    var body: some View { skillsSection }

    // MARK: - Skills Evaluation — the eight octagon skills, 1–10
    // (17 Nov 2026, Luther: "make sure it reflects what the engine uses …
    // keep 1–10 … start fresh"). Unrated skills say so; under each skill, the
    // game evidence that speaks for it (SkillEvidence) against program-mates.

    private var skillEvidence: [DrillAttribute: SkillEvidence.Line] {
        SkillEvidence.lines(for: student.id, peers: enrolledProgram?.enrolledStudentIds ?? [],
                            sessions: dataManager.sessionEvents)
    }

    /// Tracked shooting results beside the Shooting rating, ranked among
    /// athletes of the same grade (20 Nov 2026). Numbers only — they never
    /// set the rating.
    private var shootingEvidence: [String] {
        let grade = student.currentSchoolGrade()
        let peers = grade == nil ? [] : dataManager.students.filter { $0.currentSchoolGrade() == grade }.map(\.id)
        return ShootingHistory.evidence(for: student.id, peers: peers, sessions: dataManager.sessionEvents)
            .map { ShootingHistory.text($0, chinese: isChinese) }
    }

    /// The coach's own tracked drills (23 Nov 2026): the athlete's standing
    /// in each, ranked among the same grade. Shown under the skills each
    /// drill is linked to, with the rating they suggest.
    private var trackStandings: [CustomTrackHistory.Standing] {
        let grade = student.currentSchoolGrade()
        let peers = grade == nil ? [] : dataManager.students.filter { $0.currentSchoolGrade() == grade }.map(\.id)
        return CustomTrackHistory.standings(for: student.id, peers: peers, drills: dataManager.drills,
                                            sessions: dataManager.sessionEvents)
    }

    /// Takes the suggested rating: into the draft while editing, else
    /// saved at once (one tap).
    private func takeSuggestion(_ rating: Int, for axis: DrillAttribute) {
        if isEditingSkills {
            editedSkills.setRating(rating, for: axis)
        } else {
            editedSkills = skills
            editedSkills.setRating(rating, for: axis)
            saveSkills()
        }
        HapticFeedback.impact(.light)
    }

    private struct EvidenceRow: Identifiable {
        let id: String
        let axis: DrillAttribute
        let icon: String
        let text: String
        var suggestion: Int? = nil
    }

    private func evidenceRows(evidence: [DrillAttribute: SkillEvidence.Line], shooting: [String],
                              standings: [CustomTrackHistory.Standing]) -> [EvidenceRow] {
        var rows: [EvidenceRow] = []
        for axis in DrillAttribute.allCases {
            if let line = evidence[axis] {
                rows.append(.init(id: "game.\(axis.rawValue)", axis: axis, icon: "sportscourt",
                                  text: SkillEvidence.text(line, chinese: isChinese)))
            }
            if axis == .shooting {
                for (i, line) in shooting.enumerated() {
                    rows.append(.init(id: "shoot.\(i)", axis: axis, icon: "gauge.with.dots.needle.67percent", text: line))
                }
            }
            for st in standings where st.definition.attributes.contains(axis) {
                rows.append(.init(id: "track.\(axis.rawValue).\(st.drillId)", axis: axis, icon: st.definition.measure.symbol,
                                  text: CustomTrackHistory.text(st, chinese: isChinese)))
            }
            if let suggested = CustomTrackHistory.suggestion(for: axis, standings: standings),
               suggested != (isEditingSkills ? editedSkills.rating(axis) : skills.rating(axis)) {
                rows.append(.init(id: "suggest.\(axis.rawValue)", axis: axis, icon: "sparkles",
                                  text: isChinese ? "成绩建议 \(suggested) 分" : "Results suggest \(suggested)",
                                  suggestion: suggested))
            }
        }
        #if DEBUG
        // HOOPWISE_PEEP_SAMPLE_EVIDENCE=1: sample lines to check the layout
        // (the demo store has no athlete with three games).
        if rows.isEmpty, ProcessInfo.processInfo.environment["HOOPWISE_PEEP_SAMPLE_EVIDENCE"] == "1" {
            rows = [
                .init(id: "game.passing", axis: .passing, icon: "sportscourt", text: "0.0 AST/game · 3rd of 4"),
                .init(id: "game.shooting", axis: .shooting, icon: "sportscourt", text: "1.0 PTS/game · 2nd of 4"),
                .init(id: "shoot.0", axis: .shooting, icon: "gauge.with.dots.needle.67percent",
                      text: "FT · 10 shots: 64% (last 3) · up from 48% · 2nd of 9 same grade"),
                .init(id: "suggest.shooting", axis: .shooting, icon: "sparkles", text: "Results suggest 6", suggestion: 6),
                .init(id: "game.defense", axis: .defense, icon: "sportscourt", text: "1.0 STL+BLK/game · 3rd of 4"),
            ]
        }
        #endif
        return rows
    }

    @ViewBuilder
    private func evidenceBlock(evidence: [DrillAttribute: SkillEvidence.Line], shooting: [String],
                               standings: [CustomTrackHistory.Standing]) -> some View {
        let rows = evidenceRows(evidence: evidence, shooting: shooting, standings: standings)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(isChinese ? "比赛与训练数据" : "FROM GAMES AND DRILLS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(rows) { row in
                    let first = rows.first { $0.axis == row.axis }?.id == row.id
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The skill's name once, on its first line.
                        Text(first ? row.axis.short(chinese: isChinese) : "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 64, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: row.icon)
                            .font(.system(size: 9))
                            .foregroundColor(row.suggestion == nil ? .secondary : .orange)
                            .frame(width: 12)
                        Text(row.text)
                            .font(.system(size: 10, weight: row.suggestion == nil ? .regular : .semibold))
                            .foregroundColor(row.suggestion == nil ? .secondary : .orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let suggested = row.suggestion {
                            Button {
                                takeSuggestion(suggested, for: row.axis)
                            } label: {
                                Text(isChinese ? "采用" : "Use")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("peep.useSuggestion.\(row.axis.rawValue)")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(row.id.hasPrefix("shoot") ? "peep.shootingEvidence"
                                             : row.id.hasPrefix("track") ? "peep.trackEvidence" : "peep.evidence")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08)))
        }
    }

    private var skillsSection: some View {
        let evidence = skillEvidence
        let shooting = shootingEvidence
        let standings = trackStandings
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isChinese ? "技能评估" : "Skills Evaluation")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if let average = skills.axisAverage {
                    Text(String(format: "%.1f", average))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(skillRatingColor(average))
                    Text("/ 10")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Button(action: {
                    if isEditingSkills {
                        saveSkills()
                    } else {
                        // Unrated skills STAY unrated until their slider is
                        // moved (they used to be filled with 5 and saved).
                        editedSkills = skills
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { isEditingSkills.toggle() }
                }) {
                    Text(isEditingSkills ? (isChinese ? "保存" : "Save")
                         : (skills.isEvaluated ? (isChinese ? "编辑" : "Edit") : (isChinese ? "评估" : "Evaluate")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isEditingSkills ? .green : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isEditingSkills ? Color.green : Color.blue).opacity(0.12))
                        .cornerRadius(6)
                }
                .accessibilityIdentifier("peep.evaluate")
            }

            // The eight ratings as an even column — nothing between the
            // rows (24 Nov 2026, Luther: the evidence lines between them
            // "create chaos"). A suggested rating is an orange tick on its bar.
            VStack(spacing: 10) {
                ForEach(DrillAttribute.allCases, id: \.self) { axis in
                    if isEditingSkills {
                        editableSkillRow(axis: axis, suggested: CustomTrackHistory.suggestion(for: axis, standings: standings))
                    } else {
                        skillBar(axis: axis, suggested: CustomTrackHistory.suggestion(for: axis, standings: standings))
                    }
                }
            }

            // What games and tracked drills say, in one aligned block under
            // the ratings: skill | evidence, one line each.
            evidenceBlock(evidence: evidence, shooting: shooting, standings: standings)

            if isEditingSkills {
                Button(action: { withAnimation { isEditingSkills = false } }) {
                    Text(isChinese ? "取消" : "Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
            } else if !skills.isEvaluated {
                Text(isChinese ? "还没有评估。点击「评估」给八项技能打 1–10 分；比赛数据会显示在每项下面作参考。"
                               : "Not evaluated yet. Tap Evaluate to rate the eight skills 1–10; game stats show under each as a reference.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isEditingSkills {
                Divider()
                AthleteFocusPicker(studentId: student.id)
            }

            if skills.isEvaluated, let lastDate = skills.lastEvaluatedDate {
                HStack {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text((isChinese ? "最近评估: \(lastDate.formatted(date: .abbreviated, time: .omitted))"
                                    : "Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                         + (skills.baseline.map { base in
                             isChinese ? " · 共 \(skills.history.count) 次，变化自 \(base.date.formatted(date: .abbreviated, time: .omitted))"
                                       : " · \(skills.history.count) evaluations, change since \(base.date.formatted(date: .abbreviated, time: .omitted))"
                         } ?? ""))
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }

    private func skillBar(axis: DrillAttribute, suggested: Int? = nil) -> some View {
        let value = skills.rating(axis)
        return HStack(spacing: 8) {
            Image(systemName: axis.icon)
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(axis.title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 112, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    if let value {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(value) / 10.0)
                    }
                    // Where the first evaluation stood: a thin grey mark.
                    if let then = skills.baseline?.axes[axis.rawValue], then != value {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, geo.size.width * CGFloat(then) / 10.0 - 1))
                    }
                    if let suggested, suggested != value {
                        suggestionTick(width: geo.size.width, value: suggested)
                    }
                }
            }
            .frame(height: 6)
            Text(value.map { "\($0)" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(value == nil ? .secondary : .accentColor)
                .frame(width: 20, alignment: .trailing)
            if skills.baseline != nil {
                let change = skills.change(axis) ?? 0
                Text(change == 0 ? "" : (change > 0 ? "+\(change)" : "\(change)"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(change > 0 ? .green : .red)
                    .frame(width: 22, alignment: .trailing)
                    .accessibilityIdentifier("peep.skill.change")
            }
        }
    }

    /// Where the tracked-drill results put this skill: a short orange tick
    /// across the bar.
    private func suggestionTick(width: CGFloat, value: Int) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.orange)
            .frame(width: 3, height: 12)
            .offset(x: max(0, width * CGFloat(value) / 10.0 - 1.5))
    }

    private func editableSkillRow(axis: DrillAttribute, suggested: Int? = nil) -> some View {
        let binding = Binding<Double>(
            get: { Double(editedSkills.rating(axis) ?? 5) },
            set: { editedSkills.setRating(Int($0.rounded()), for: axis) })
        return HStack(spacing: 8) {
            Image(systemName: axis.icon)
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(axis.title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 112, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            // Touching the slider rates the skill where it stands, so a 5
            // can be given without moving it.
            Slider(value: binding, in: 1...10, step: 1) { editing in
                if editing, editedSkills.rating(axis) == nil { editedSkills.setRating(5, for: axis) }
            }
                .opacity(editedSkills.rating(axis) == nil ? 0.45 : 1)
                .accessibilityIdentifier("peep.skill.slider.\(axis.rawValue)")
            Text(editedSkills.rating(axis).map(String.init) ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(editedSkills.rating(axis) == nil ? .secondary : .accentColor)
                .frame(width: 20)
                .accessibilityIdentifier("peep.skill.value.\(axis.rawValue)")
        }
    }

    private func skillRatingColor(_ rating: Double) -> Color {
        if rating >= 8 { return .green }
        if rating >= 6 { return .orange }
        return .red
    }
    
    private func saveSkills() {
        guard var updatedPlayer = player else { return }
        editedSkills.swept = true   // every rating here was set skill by skill
        editedSkills.recordEvaluation(replacing: updatedPlayer.skills)
        updatedPlayer.skills = editedSkills
        updatedPlayer.updatedAt = Date()
        dataManager.updatePlayer(updatedPlayer)
    }

}
