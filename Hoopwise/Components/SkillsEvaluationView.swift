import SwiftUI

// MARK: - Editable Skills Evaluation Section
struct EditableSkillsSection: View {
    @EnvironmentObject var dataManager: DataManager
    let player: Player
    @State private var isExpanded: Bool = false
    @State private var isEditing: Bool = false
    @State private var editedSkills: SkillsEvaluation
    
    init(player: Player) {
        self.player = player
        self._editedSkills = State(initialValue: player.skills)
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            // Header with collapse toggle and edit button
            HStack {
                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                        Text(isChinese ? "技能评估" : "Skills Evaluation")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        
                        // Overall rating badge
                        Text(String(format: "%.1f", player.skills.overallRating))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ratingColor(player.skills.overallRating))
                            .cornerRadius(6)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if isExpanded {
                    Button(action: {
                        if isEditing {
                            saveSkills()
                        }
                        withAnimation { isEditing.toggle() }
                    }) {
                        Text(isChinese ? (isEditing ? "保存" : "编辑") : (isEditing ? "Save" : "Edit"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isEditing ? .green : AppTheme.accentColor)
                    }
                }
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if isExpanded {
                VStack(spacing: 16) {
                    if isEditing {
                        editableSkillsGrid
                    } else {
                        readOnlySkillsView
                    }
                    
                    // Last evaluated date
                    if let lastDate = player.skills.lastEvaluatedDate {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Read-Only Skills View (6 skills matching radar)
    private var readOnlySkillsView: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 10) {
            skillRow(label: isChinese ? "得分" : "Scoring", value: player.skills.scoring, color: .orange, icon: "scope")
            skillRow(label: isChinese ? "组织" : "Playmaking", value: player.skills.playmaking, color: .blue, icon: "arrow.triangle.branch")
            skillRow(label: isChinese ? "篮板" : "Rebounding", value: player.skills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
            skillRow(label: isChinese ? "防守" : "Defense", value: player.skills.defense, color: .red, icon: "shield.fill")
            skillRow(label: isChinese ? "运动能力" : "Athleticism", value: player.skills.athleticism, color: .green, icon: "figure.run")
            skillRow(label: isChinese ? "软实力" : "Intangibles", value: player.skills.intangibles, color: .teal, icon: "star.fill")
        }
    }
    
    private func skillRow(label: String, value: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 100, alignment: .leading)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value) / 10, height: 8)
                }
            }
            .frame(height: 8)
            
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 24)
        }
    }
    
    // MARK: - Editable Skills Grid (6 skills matching radar)
    private var editableSkillsGrid: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 14) {
            editableSkillRow(label: isChinese ? "得分" : "Scoring", value: $editedSkills.scoring, color: .orange, icon: "scope")
            editableSkillRow(label: isChinese ? "组织" : "Playmaking", value: $editedSkills.playmaking, color: .blue, icon: "arrow.triangle.branch")
            editableSkillRow(label: isChinese ? "篮板" : "Rebounding", value: $editedSkills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
            editableSkillRow(label: isChinese ? "防守" : "Defense", value: $editedSkills.defense, color: .red, icon: "shield.fill")
            editableSkillRow(label: isChinese ? "运动能力" : "Athleticism", value: $editedSkills.athleticism, color: .green, icon: "figure.run")
            editableSkillRow(label: isChinese ? "软实力" : "Intangibles", value: $editedSkills.intangibles, color: .teal, icon: "star.fill")
        }
    }
    
    private func editableSkillRow(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 80, alignment: .leading)
            
            // Slider
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 1...10, step: 1)
            .tint(color)
            
            Text("\(value.wrappedValue)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 24)
        }
    }
    
    // MARK: - Helpers
    
    private func ratingColor(_ rating: Double) -> Color {
        switch rating {
        case 8...10: return .green
        case 6..<8: return .blue
        case 4..<6: return .orange
        default: return .red
        }
    }
    
    private func saveSkills() {
        var updatedPlayer = player
        updatedPlayer.skills = editedSkills
        updatedPlayer.skills.lastEvaluatedDate = Date()
        updatedPlayer.updatedAt = Date()
        dataManager.updatePlayer(updatedPlayer)
        
        // Haptic feedback
        HapticFeedback.notification(.success)
    }
}

// MARK: - Skills Section Card View (for Intelligence Profile)
/// Displays skills with edit capability using sliders and optional program comparison
struct SkillsSectionCardView: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let player: Player?
    var program: Program? = nil  // Optional program for skill target comparison
    
    @State private var isEditing = false
    @State private var editedSkills: SkillsEvaluation = SkillsEvaluation()
    
    private var currentPlayer: Player? {
        player ?? dataManager.player(for: student.id)
    }
    
    private var enrolledProgram: Program? {
        if let p = program { return p }
        guard let programId = student.programId else { return nil }
        return dataManager.programs.first { $0.id == programId }
    }
    
    private var skillTargets: ProgramSkillTargets? {
        enrolledProgram?.skillTargets
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        VStack(alignment: .leading, spacing: 12) {
            // Section header with edit button
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text(isChinese ? "技能评估" : "Skills Evaluation")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                
                if let p = currentPlayer {
                    if !isEditing {
                        Text(String(format: "%.1f", p.skills.overallRating))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(skillRatingColor(p.skills.overallRating))
                        Text("/ 10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        if isEditing {
                            saveSkills()
                        } else {
                            editedSkills = p.skills
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing.toggle()
                        }
                    }) {
                        Text(isChinese ? (isEditing ? "保存" : "编辑") : (isEditing ? "Save" : "Edit"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isEditing ? .green : AppTheme.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((isEditing ? Color.green : AppTheme.accentColor).opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
            
            // Program comparison header (if enrolled in program with skill targets)
            if let program = enrolledProgram, skillTargets != nil {
                HStack(spacing: 6) {
                    Image(systemName: program.mascotIcon)
                        .font(.system(size: 10))
                        .foregroundColor(program.mascotColor)
                    Text(isChinese ? "对比 \(program.shortName) 目标" : "vs \(program.shortName) targets")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(program.mascotColor)
                    
                    Spacer()
                    
                    // Legend
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.primary.opacity(0.6)).frame(width: 6, height: 6)
                            Text(isChinese ? "当前" : "Current")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 6, height: 6)
                            Text(isChinese ? "目标" : "Target")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(program.mascotColor.opacity(0.08))
                .cornerRadius(8)
            }
            
            if let p = currentPlayer {
                if isEditing {
                    // Editing mode with sliders (6 skills matching radar)
                    VStack(spacing: 14) {
                        skillSliderRow(label: isChinese ? "得分" : "Scoring", value: $editedSkills.scoring, color: .orange, icon: "scope")
                        skillSliderRow(label: isChinese ? "组织" : "Playmaking", value: $editedSkills.playmaking, color: .blue, icon: "arrow.triangle.branch")
                        skillSliderRow(label: isChinese ? "篮板" : "Rebounding", value: $editedSkills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                        skillSliderRow(label: isChinese ? "防守" : "Defense", value: $editedSkills.defense, color: .red, icon: "shield.fill")
                        skillSliderRow(label: isChinese ? "运动能力" : "Athleticism", value: $editedSkills.athleticism, color: .green, icon: "figure.run")
                        skillSliderRow(label: isChinese ? "软实力" : "Intangibles", value: $editedSkills.intangibles, color: .teal, icon: "star.fill")
                    }
                    
                    // Cancel button
                    Button(action: {
                        withAnimation { isEditing = false }
                    }) {
                        Text(isChinese ? "取消" : "Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else {
                    // Display mode - grid of skill bars (6 skills matching radar)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        skillComparisonBar(label: isChinese ? "得分" : "Scoring", value: p.skills.scoring, target: skillTargets?.scoring, color: .orange)
                        skillComparisonBar(label: isChinese ? "组织" : "Playmaking", value: p.skills.playmaking, target: skillTargets?.playmaking, color: .blue)
                        skillComparisonBar(label: isChinese ? "篮板" : "Rebounding", value: p.skills.rebounding, target: skillTargets?.rebounding, color: .purple)
                        skillComparisonBar(label: isChinese ? "防守" : "Defense", value: p.skills.defense, target: skillTargets?.defense, color: .red)
                        skillComparisonBar(label: isChinese ? "运动能力" : "Athleticism", value: p.skills.athleticism, target: skillTargets?.athleticism, color: .green)
                        skillComparisonBar(label: isChinese ? "软实力" : "Intangibles", value: p.skills.intangibles, target: skillTargets?.intangibles, color: .teal)
                    }
                    
                    // Skills summary vs program targets
                    if let targets = skillTargets, let program = enrolledProgram {
                        let belowCount = targets.skillsBelowTarget(p.skills)
                        let meetsAll = targets.meetsAllTargets(p.skills)
                        
                        HStack(spacing: 8) {
                            if meetsAll {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text(isChinese ? "已达到 \(program.shortName) 所有目标！" : "Meets all \(program.shortName) targets!")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "arrow.up.circle")
                                    .foregroundColor(.orange)
                                Text(isChinese ? "\(belowCount) 项低于 \(program.shortName) 目标" : "\(belowCount) skill\(belowCount == 1 ? "" : "s") below \(program.shortName) target")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    
                    // Last evaluated date
                    if let lastDate = p.skills.lastEvaluatedDate {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(isChinese ? "最近评估: \(lastDate.formatted(date: .abbreviated, time: .omitted))" : "Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                }
            } else {
                // No player data
                HStack {
                    Image(systemName: "star")
                        .foregroundColor(.secondary)
                    Text(isChinese ? "暂无技能评估" : "No skills evaluation yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Skill Comparison Bar (shows current value vs target)
    private func skillComparisonBar(label: String, value: Int, target: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                
                // Show value and comparison to target
                if let target = target {
                    let diff = value - target
                    HStack(spacing: 2) {
                        Text("\(value)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                        
                        if diff != 0 {
                            Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(diff >= 0 ? .green : .orange)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    Text("\(value)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                        .frame(height: 4)
                    
                    // Target marker (if available)
                    if let target = target {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(color.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 3, height: 8)
                            .offset(x: geometry.size.width * CGFloat(target) / 10 - 1.5, y: -2)
                    }
                    
                    // Current value bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value) / 10, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Slider Row for Editing
    private func skillSliderRow(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 28)
            }
            
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 1...10, step: 1)
            .tint(color)
        }
    }
    
    // MARK: - Mini Bar for Display
    private func skillMiniBar(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value) / 10, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    private func skillRatingColor(_ rating: Double) -> Color {
        switch rating {
        case 8...10: return .green
        case 6..<8: return .blue
        case 4..<6: return .orange
        default: return .red
        }
    }
    
    private func saveSkills() {
        guard var updatedPlayer = currentPlayer else { return }
        updatedPlayer.skills = editedSkills
        updatedPlayer.skills.lastEvaluatedDate = Date()
        updatedPlayer.updatedAt = Date()
        dataManager.updatePlayer(updatedPlayer)
        HapticFeedback.notification(.success)
    }
}

// MARK: - Compact Skills Badge (for cards)
struct SkillsBadge: View {
    let skills: SkillsEvaluation
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9))
            Text(String(format: "%.1f", skills.overallRating))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(ratingColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ratingColor.opacity(0.12))
        .cornerRadius(6)
    }
    
    private var ratingColor: Color {
        switch skills.overallRating {
        case 8...10: return .green
        case 6..<8: return .blue
        case 4..<6: return .orange
        default: return .red
        }
    }
}


#Preview {
    ScrollView {
        VStack(spacing: 20) {
            EditableSkillsSection(player: Player(studentId: UUID()))
            SkillsBadge(skills: SkillsEvaluation())
        }
        .padding()
    }
    .environmentObject(DataManager.shared)
}
