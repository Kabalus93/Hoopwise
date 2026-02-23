import SwiftUI

// MARK: - Student Quick Peep View
/// A quick glance view for coaches during sessions showing relevant student stats and AI-generated insights
struct StudentQuickPeepView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let student: Student
    let sessionId: UUID?
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    // State for editable skills
    @State private var isEditingSkills = false
    @State private var editedSkills = SkillsEvaluation()

    @State private var showingParentReport = false
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // MARK: - Computed Properties
    
    private var player: Player? {
        dataManager.player(for: student.id)
    }
    
    private var contract: Contract? {
        dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
    }

    private var enrolledProgram: Program? {
        dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) }
    }
    
    private var trainingStats: TrainingSessionStats {
        TrainingSessionStats.calculate(for: student.id, from: dataManager.sessionEvents)
    }
    
    private var skills: SkillsEvaluation {
        player?.skills ?? SkillsEvaluation()
    }
    
    private var programContext: ProgramStatsContext {
        // Get all peer stats from the same program for comparison
        guard let programId = student.programId else { return .empty }
        let peerStats = dataManager.sessionEvents
            .filter { $0.programId == programId }
            .flatMap { session in
                session.attendeeIds.compactMap { studentId -> TrainingSessionStats? in
                    let stats = TrainingSessionStats.calculate(for: studentId, from: dataManager.sessionEvents)
                    return stats.hasStats ? stats : nil
                }
            }
        return ProgramStatsContext.calculate(from: peerStats)
    }
    
    private var performanceMetrics: PerformanceRadarMetrics {
        PerformanceRadarMetrics.compute(from: trainingStats, skills: skills, programContext: programContext)
    }
    
    private var attendanceRecords: [AttendanceRecord] {
        dataManager.sessionEvents.compactMap { session -> AttendanceRecord? in
            guard session.attendeeIds.contains(student.id) else { return nil }
            let didAttend = session.actualAttendeeIds.contains(student.id)
            return AttendanceRecord(
                studentId: student.id,
                sessionId: session.id,
                status: didAttend ? .present : .absent,
                recordedAt: session.date
            )
        }
    }

    private var gameAwardsAndImprovementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(isChinese ? "最近比赛" : "Recent Game")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }

            if lastGameStats == nil {
                Text(isChinese ? "暂无比赛数据" : "No recent game stats")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                // Award chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPeepAwardChips) { chip in
                            HStack(spacing: 6) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(chip.title)
                                    .font(.system(size: 12, weight: .semibold))
                                if let value = chip.value {
                                    Text("\(value)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                            }
                            .foregroundColor(chip.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(chip.color.opacity(0.12))
                            .cornerRadius(12)
                        }
                    }
                }

                // Improvement / Focus note
                if let note = quickPeepImprovementNote {
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var attendanceRate: Double {
        let total = attendanceRecords.count
        guard total > 0 else { return 0 }
        let present = attendanceRecords.filter { $0.status == .present }.count
        return Double(present) / Double(total)
    }
    
    private var recentAttendance: [AttendanceRecord] {
        Array(attendanceRecords.sorted { $0.recordedAt > $1.recordedAt }.prefix(5))
    }
    
    private var insights: [StudentInsight] {
        StudentInsightEngine.generateInsights(
            student: student,
            trainingStats: trainingStats,
            skills: skills,
            attendanceRate: attendanceRate,
            recentAttendance: recentAttendance,
            contract: contract
        )
    }

    private struct GameStatSnapshot {
        let points: Int
        let rebounds: Int
        let assists: Int
        let steals: Int
        let blocks: Int
    }

    private struct AwardChipData: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let color: Color
        let value: Int?
    }

    private var lastCompletedGamesForStudent: [(game: SessionGame, stats: SessionPlayerStats)] {
        dataManager.sessionEvents
            .flatMap { $0.games }
            .filter { $0.status == .completed }
            .sorted { ($0.endedAt ?? $0.updatedAt) > ($1.endedAt ?? $1.updatedAt) }
            .compactMap { game in
                guard let stats = game.playerStats.first(where: { $0.playerId == student.id }) else { return nil }
                return (game, stats)
            }
    }

    private var lastGameStats: SessionPlayerStats? {
        lastCompletedGamesForStudent.first?.stats
    }

    private var previousGameStats: SessionPlayerStats? {
        guard lastCompletedGamesForStudent.count >= 2 else { return nil }
        return lastCompletedGamesForStudent[1].stats
    }

    private func contributionScore(stats: SessionPlayerStats) -> Double {
        Double(stats.points) * 1.0 +
        Double(stats.rebounds) * 1.2 +
        Double(stats.assists) * 1.5 +
        Double(stats.steals) * 1.5 +
        Double(stats.blocks) * 1.5
    }

    private func snapshot(from stats: SessionPlayerStats) -> GameStatSnapshot {
        GameStatSnapshot(points: stats.points, rebounds: stats.rebounds, assists: stats.assists, steals: stats.steals, blocks: stats.blocks)
    }

    private func diffLine(labelEN: String, labelZH: String, current: Int, previous: Int) -> String {
        let label = isChinese ? labelZH : labelEN
        let diff = current - previous
        if diff > 0 { return "\(label) +\(diff)" }
        if diff < 0 { return "\(label) \(diff)" }
        return "\(label) +0"
    }

    private var quickPeepAwardChips: [AwardChipData] {
        guard let last = lastGameStats else { return [] }

        // Determine MVP for that game using the same formula as recap
        let lastGame = lastCompletedGamesForStudent.first?.game
        let allStats = (lastGame?.playerStats ?? []).filter { $0.hasStats }
        let mvp = allStats.max(by: { contributionScore(stats: $0) < contributionScore(stats: $1) })

        var chips: [AwardChipData] = []

        if mvp?.playerId == student.id {
            chips.append(AwardChipData(title: isChinese ? "MVP" : "MVP", icon: "crown.fill", color: .yellow, value: Int(contributionScore(stats: last))))
        }

        if let topPts = allStats.max(by: { $0.points < $1.points }), topPts.playerId == student.id, topPts.points >= 2 {
            chips.append(AwardChipData(title: isChinese ? "神射手" : "Sharpshooter", icon: "scope", color: .orange, value: topPts.points))
        }

        if let topAst = allStats.max(by: { $0.assists < $1.assists }), topAst.playerId == student.id, topAst.assists >= 1 {
            chips.append(AwardChipData(title: isChinese ? "助攻王" : "Playmaker", icon: "arrow.triangle.branch", color: .green, value: topAst.assists))
        }

        if let topStl = allStats.max(by: { $0.steals < $1.steals }), topStl.playerId == student.id, topStl.steals >= 1 {
            chips.append(AwardChipData(title: isChinese ? "抢断王" : "Pickpocket", icon: "hand.point.up.left.fill", color: .red, value: topStl.steals))
        }

        if let topBlk = allStats.max(by: { $0.blocks < $1.blocks }), topBlk.playerId == student.id, topBlk.blocks >= 1 {
            chips.append(AwardChipData(title: isChinese ? "盖帽王" : "The Wall", icon: "shield.lefthalf.filled", color: .purple, value: topBlk.blocks))
        }

        if let topReb = allStats.max(by: { $0.rebounds < $1.rebounds }), topReb.playerId == student.id, topReb.rebounds >= 2 {
            chips.append(AwardChipData(title: isChinese ? "篮板王" : "Board Boss", icon: "arrow.up.arrow.down.circle.fill", color: .blue, value: topReb.rebounds))
        }

        // If no award earned, still show a positive chip so kids don't feel "left out"
        if chips.isEmpty {
            let title = isChinese ? "贡献值" : "Contribution"
            chips.append(AwardChipData(title: title, icon: "seal.fill", color: .pink, value: Int(contributionScore(stats: last))))
        }

        return chips
    }

    private var quickPeepImprovementNote: String? {
        guard let last = lastGameStats else { return nil }
        let lastSnap = snapshot(from: last)

        guard let prev = previousGameStats else {
            // First game: give a focus suggestion based on zeros
            if lastSnap.assists == 0 {
                return isChinese ? "试试多传球，助攻也很重要！" : "Try passing more — assists are huge!"
            }
            if lastSnap.rebounds == 0 {
                return isChinese ? "试试更积极抢篮板！" : "Try fighting for rebounds!"
            }
            if lastSnap.steals + lastSnap.blocks == 0 {
                return isChinese ? "防守也能改变比赛！" : "Defense can change the game!"
            }
            return isChinese ? "很棒的一场比赛，继续保持！" : "Great game — keep it up!"
        }

        let prevSnap = snapshot(from: prev)
        let ptsDiff = lastSnap.points - prevSnap.points
        let astDiff = lastSnap.assists - prevSnap.assists
        let rebDiff = lastSnap.rebounds - prevSnap.rebounds
        let defDiff = (lastSnap.steals + lastSnap.blocks) - (prevSnap.steals + prevSnap.blocks)

        // Pick the biggest positive delta to celebrate
        let deltas: [(key: String, value: Int, message: String)] = [
            ("PTS", ptsDiff, isChinese ? "得分提升 +\(max(0, ptsDiff))" : "Scoring up +\(max(0, ptsDiff))"),
            ("AST", astDiff, isChinese ? "助攻提升 +\(max(0, astDiff))" : "Assists up +\(max(0, astDiff))"),
            ("REB", rebDiff, isChinese ? "篮板提升 +\(max(0, rebDiff))" : "Rebounds up +\(max(0, rebDiff))"),
            ("DEF", defDiff, isChinese ? "防守贡献提升 +\(max(0, defDiff))" : "Defense impact up +\(max(0, defDiff))")
        ]
        if let best = deltas.max(by: { $0.value < $1.value }), best.value > 0 {
            return best.message
        }

        // Otherwise provide a single focus point (choose the "lowest" category this time)
        if lastSnap.assists == 0 {
            return isChinese ? "下场目标：争取 1 次助攻（找到空位队友）" : "Next goal: get 1 assist (find the open teammate)"
        }
        if lastSnap.rebounds == 0 {
            return isChinese ? "下场目标：抢 1 个篮板（卡位 + 冲抢）" : "Next goal: get 1 rebound (box out + hustle)"
        }
        if lastSnap.steals + lastSnap.blocks == 0 {
            return isChinese ? "下场目标：做出 1 次防守贡献（抢断/盖帽）" : "Next goal: make 1 defensive play (steal/block)"
        }

        // Gentle summary when no big changes
        return isChinese
            ? "稳定发挥！\n\(diffLine(labelEN: "PTS", labelZH: "得分", current: lastSnap.points, previous: prevSnap.points)) • \(diffLine(labelEN: "REB", labelZH: "篮板", current: lastSnap.rebounds, previous: prevSnap.rebounds)) • \(diffLine(labelEN: "AST", labelZH: "助攻", current: lastSnap.assists, previous: prevSnap.assists))"
            : "Consistent game!\n\(diffLine(labelEN: "PTS", labelZH: "得分", current: lastSnap.points, previous: prevSnap.points)) • \(diffLine(labelEN: "REB", labelZH: "篮板", current: lastSnap.rebounds, previous: prevSnap.rebounds)) • \(diffLine(labelEN: "AST", labelZH: "助攻", current: lastSnap.assists, previous: prevSnap.assists))"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if isIPad {
                    // iPad: Compact two-column layout
                    ipadContent
                } else {
                    // iPhone: Single column scrolling
                    iphoneContent
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "学员速览" : "Quick Peep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingParentReport = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingParentReport) {
                ParentReportSheet(
                    student: student,
                    player: player,
                    contract: contract,
                    programName: enrolledProgram?.displayName,
                    coachName: dataManager.coach.name
                )
            }
        }
    }
    
    // MARK: - iPad Content (Two-column - matches Intelligence Profile)
    private var ipadContent: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left column: Profile card
            StudentProfileCardView(
                student: student,
                player: player,
                trainingStats: trainingStats,
                contract: contract,
                churnRisk: churnRisk,
                attendanceRate: attendanceRate,
                sessionCount: trainingStats.gamesPlayed
            )
            .frame(maxWidth: .infinity)
            
            // Right column: Skills + Notes + Insights + Contract
            VStack(spacing: 16) {
                skillsSection
                
                if let notes = player?.coachNotes, !notes.isEmpty {
                    coachNotesSection(notes)
                }
                
                if !insights.isEmpty {
                    insightsSection
                }
                
                contractInfoSection
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
    
    // MARK: - iPhone Content (Single column - matches Intelligence Profile)
    private var iphoneContent: some View {
        VStack(spacing: 16) {
            // Flippable profile card (same as Intelligence Profile)
            StudentProfileCardView(
                student: student,
                player: player,
                trainingStats: trainingStats,
                contract: contract,
                churnRisk: churnRisk,
                attendanceRate: attendanceRate,
                sessionCount: trainingStats.gamesPlayed
            )
            
            // Skills evaluation with editable sliders
            skillsSection
            
            // Coach notes (only show if has custom notes)
            if let notes = player?.coachNotes, !notes.isEmpty {
                coachNotesSection(notes)
            }
            
            // Filtered insights (relevant to this player)
            if !insights.isEmpty {
                insightsSection
            }
            
            // Contract info section (same as Intelligence Profile)
            contractInfoSection
            
            Spacer(minLength: 40)
        }
        .padding(16)
    }
    
    // MARK: - Contract Info Section
    private var contractInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text(isChinese ? "合同状态" : "Contract Status")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if let contract = contract {
                    Text(isChinese ? contract.typeLabelChinese : contract.typeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.indigo)
                        .cornerRadius(8)
                }
            }
            
            if let contract = contract {
                // Main stats row
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("\(contract.sessionCount)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text(isChinese ? "已参加" : "Attended")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 50)
                    
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let remaining = contract.remainingSessions {
                            Text("\(remaining)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(remaining <= 3 ? .orange : .blue)
                            Text(isChinese ? "剩余" : "Remaining")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text(contract.enrollmentDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text(isChinese ? "入学日期" : "Enrolled")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 50)
                    
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let expiry = contract.expiryDate {
                            Text(expiry.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(contract.isExpired ? .red : .secondary)
                            Text(contract.isExpired ? (isChinese ? "已过期" : "Expired") : (isChinese ? "到期日" : "Expires"))
                                .font(.system(size: 11))
                                .foregroundColor(contract.isExpired ? .red : .secondary)
                        } else {
                            let weeks = Calendar.current.dateComponents([.weekOfYear], from: contract.enrollmentDate, to: Date()).weekOfYear ?? 0
                            Text("\(weeks)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.purple)
                            Text(isChinese ? "周" : "Weeks")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(isChinese ? "暂无合同" : "No contract")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Churn Risk (for profile card)
    private var churnRisk: StudentIntelligence.ChurnRiskAssessment {
        StudentIntelligence.analyzeChurnRisk(
            student: student,
            contract: contract,
            attendanceRecords: attendanceRecords,
            performanceStats: nil,
            allContracts: dataManager.allContracts(for: student.id),
            player: player,
            enrolledProgram: enrolledProgram,
            touchpoints: student.parentalTouchpoints
        )
    }
    
    // MARK: - Coach Notes Section
    private func coachNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text(isChinese ? "教练笔记" : "Coach Notes")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(notes)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            StudentAvatarView(student: student, size: 80)
            
            VStack(spacing: 4) {
                Text(student.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                if let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                if let age = student.age {
                    Text(isChinese ? "\(age) 岁" : "\(age) years old")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Insights Section
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text(isChinese ? "教练洞察" : "Coach Insights")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            if insights.isEmpty {
                Text(isChinese ? "暂无足够数据生成洞察" : "Not enough data to generate insights")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(insights) { insight in
                        insightRow(insight)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "#fef9c3"), Color(hex: "#fef3c7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    private func insightRow(_ insight: StudentInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.icon)
                .font(.system(size: 14))
                .foregroundColor(insight.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? insight.titleChinese : insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(isChinese ? insight.descriptionChinese : insight.description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#4A4A4A"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Stats Grid Section
    
    private var statsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "训练数据" : "Training Stats")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
            
            if trainingStats.hasStats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(value: String(format: "%.1f", trainingStats.ppg), label: "PPG", color: .orange)
                    statCard(value: String(format: "%.1f", trainingStats.rpg), label: "RPG", color: .blue)
                    statCard(value: String(format: "%.1f", trainingStats.apg), label: "APG", color: .green)
                    statCard(value: String(format: "%.1f", trainingStats.spg), label: "SPG", color: .purple)
                    statCard(value: String(format: "%.1f", trainingStats.bpg), label: "BPG", color: .red)
                    statCard(value: "\(trainingStats.gamesPlayed)", label: isChinese ? "场次" : "GP", color: .gray)
                }
            } else {
                Text(isChinese ? "暂无比赛数据" : "No game stats yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Skills Section with Radar Diagram
    
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with edit button
            HStack {
                Text(isChinese ? "技能评估" : "Skills Evaluation")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Overall rating
                Text(String(format: "%.1f", skills.overallRating))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(skillRatingColor(skills.overallRating))
                Text("/ 10")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if isEditingSkills {
                        saveSkills()
                    } else {
                        editedSkills = skills
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingSkills.toggle()
                    }
                }) {
                    Text(isChinese ? (isEditingSkills ? "保存" : "编辑") : (isEditingSkills ? "Save" : "Edit"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isEditingSkills ? .green : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isEditingSkills ? Color.green : Color.blue).opacity(0.12))
                        .cornerRadius(6)
                }
            }
            
            // Skills with sliders or bars (radar removed - available on card flip)
            if isEditingSkills {
                VStack(spacing: 10) {
                    editableSkillRow(label: isChinese ? "得分" : "Scoring", value: $editedSkills.scoring, color: .orange, icon: "scope")
                    editableSkillRow(label: isChinese ? "组织" : "Playmaking", value: $editedSkills.playmaking, color: .blue, icon: "arrow.triangle.branch")
                    editableSkillRow(label: isChinese ? "篮板" : "Rebounding", value: $editedSkills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                    editableSkillRow(label: isChinese ? "防守" : "Defense", value: $editedSkills.defense, color: .red, icon: "shield.fill")
                    editableSkillRow(label: isChinese ? "运动能力" : "Athleticism", value: $editedSkills.athleticism, color: .green, icon: "figure.run")
                    editableSkillRow(label: isChinese ? "投入" : "Effort", value: $editedSkills.intangibles, color: .teal, icon: "star.fill")
                }
                
                // Cancel button
                Button(action: { withAnimation { isEditingSkills = false } }) {
                    Text(isChinese ? "取消" : "Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
            } else {
                VStack(spacing: 8) {
                    skillBar(label: isChinese ? "得分" : "Scoring", value: skills.scoring, color: .orange, icon: "scope")
                    skillBar(label: isChinese ? "组织" : "Playmaking", value: skills.playmaking, color: .blue, icon: "arrow.triangle.branch")
                    skillBar(label: isChinese ? "篮板" : "Rebounding", value: skills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                    skillBar(label: isChinese ? "防守" : "Defense", value: skills.defense, color: .red, icon: "shield.fill")
                    skillBar(label: isChinese ? "运动能力" : "Athleticism", value: skills.athleticism, color: .green, icon: "figure.run")
                    skillBar(label: isChinese ? "投入" : "Effort", value: skills.intangibles, color: .teal, icon: "star.fill")
                }
            }
            
            // Last evaluated
            if let lastDate = skills.lastEvaluatedDate {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(isChinese ? "最近评估: \(lastDate.formatted(date: .abbreviated, time: .omitted))" : "Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func skillBar(label: String, value: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value) / 10.0)
                }
            }
            .frame(height: 6)
            
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 20, alignment: .trailing)
        }
    }
    
    private func editableSkillRow(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 1...10, step: 1)
            .tint(color)
            
            Text("\(value.wrappedValue)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 20)
        }
    }
    
    private func skillRatingColor(_ rating: Double) -> Color {
        if rating >= 8 { return .green }
        if rating >= 6 { return .orange }
        return .red
    }
    
    private func saveSkills() {
        guard var updatedPlayer = player else { return }
        editedSkills.lastEvaluatedDate = Date()
        updatedPlayer.skills = editedSkills
        updatedPlayer.updatedAt = Date()
        dataManager.updatePlayer(updatedPlayer)
    }
    
    // MARK: - Attendance Section
    
    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isChinese ? "出勤记录" : "Attendance")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(attendanceRate * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(attendanceRate >= 0.8 ? .green : (attendanceRate >= 0.6 ? .orange : .red))
            }
            
            if recentAttendance.isEmpty {
                Text(isChinese ? "暂无出勤记录" : "No attendance records")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                HStack(spacing: 8) {
                    ForEach(recentAttendance, id: \.sessionId) { record in
                        Circle()
                            .fill(record.status == .present ? Color.green : Color.red.opacity(0.6))
                            .frame(width: 12, height: 12)
                    }
                    
                    Spacer()
                    
                    Text(isChinese ? "最近 \(recentAttendance.count) 次" : "Last \(recentAttendance.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Student Insight Model

struct StudentInsight: Identifiable {
    let id = UUID()
    let title: String
    let titleChinese: String
    let description: String
    let descriptionChinese: String
    let icon: String
    let color: Color
    let priority: Int  // Higher = more important
}

// MARK: - Student Insight Engine

struct StudentInsightEngine {
    
    /// Generate insights about a student based on their stats, attendance, and other data
    static func generateInsights(
        student: Student,
        trainingStats: TrainingSessionStats,
        skills: SkillsEvaluation,
        attendanceRate: Double,
        recentAttendance: [AttendanceRecord],
        contract: Contract?
    ) -> [StudentInsight] {
        var insights: [StudentInsight] = []
        
        // MARK: - Scoring Insights
        if trainingStats.hasStats {
            if trainingStats.ppg >= 10 {
                insights.append(StudentInsight(
                    title: "Elite Scorer",
                    titleChinese: "精英得分手",
                    description: "Averaging \(String(format: "%.1f", trainingStats.ppg)) PPG - one of the top scorers. Consider giving them more ball-handling responsibilities.",
                    descriptionChinese: "场均 \(String(format: "%.1f", trainingStats.ppg)) 分 - 顶级得分手之一。可以考虑给予更多持球责任。",
                    icon: "flame.fill",
                    color: .orange,
                    priority: 10
                ))
            } else if trainingStats.ppg >= 6 {
                insights.append(StudentInsight(
                    title: "Solid Contributor",
                    titleChinese: "稳定贡献者",
                    description: "Consistent scorer with \(String(format: "%.1f", trainingStats.ppg)) PPG. Good offensive awareness.",
                    descriptionChinese: "稳定得分手，场均 \(String(format: "%.1f", trainingStats.ppg)) 分。进攻意识良好。",
                    icon: "star.fill",
                    color: .yellow,
                    priority: 7
                ))
            } else if trainingStats.ppg < 3 && trainingStats.gamesPlayed >= 3 {
                insights.append(StudentInsight(
                    title: "Needs Scoring Focus",
                    titleChinese: "需加强得分",
                    description: "Low scoring average (\(String(format: "%.1f", trainingStats.ppg)) PPG). Consider drills focusing on shooting confidence.",
                    descriptionChinese: "得分偏低 (场均 \(String(format: "%.1f", trainingStats.ppg)) 分)。建议增加投篮信心训练。",
                    icon: "target",
                    color: .blue,
                    priority: 6
                ))
            }
        }
        
        // MARK: - Playmaking Insights
        if trainingStats.hasStats && trainingStats.apg >= 3 {
            insights.append(StudentInsight(
                title: "Court Vision",
                titleChinese: "球场视野",
                description: "Strong playmaker with \(String(format: "%.1f", trainingStats.apg)) APG. Great at finding open teammates.",
                descriptionChinese: "出色的组织者，场均 \(String(format: "%.1f", trainingStats.apg)) 次助攻。善于发现空位队友。",
                icon: "eye.fill",
                color: .purple,
                priority: 8
            ))
        }
        
        // MARK: - Rebounding Insights
        if trainingStats.hasStats && trainingStats.rpg >= 5 {
            insights.append(StudentInsight(
                title: "Board Monster",
                titleChinese: "篮板怪兽",
                description: "Dominates the glass with \(String(format: "%.1f", trainingStats.rpg)) RPG. Great hustle and positioning.",
                descriptionChinese: "篮板统治者，场均 \(String(format: "%.1f", trainingStats.rpg)) 个篮板。拼抢积极，卡位出色。",
                icon: "arrow.up.arrow.down",
                color: .blue,
                priority: 8
            ))
        }
        
        // MARK: - Defense Insights
        if trainingStats.hasStats {
            let defensiveImpact = trainingStats.spg + trainingStats.bpg
            if defensiveImpact >= 3 {
                insights.append(StudentInsight(
                    title: "Defensive Anchor",
                    titleChinese: "防守核心",
                    description: "Elite defender with \(String(format: "%.1f", trainingStats.spg)) SPG and \(String(format: "%.1f", trainingStats.bpg)) BPG. Disrupts opponent's offense.",
                    descriptionChinese: "顶级防守者，场均 \(String(format: "%.1f", trainingStats.spg)) 抢断 + \(String(format: "%.1f", trainingStats.bpg)) 盖帽。干扰对手进攻。",
                    icon: "shield.fill",
                    color: .green,
                    priority: 9
                ))
            } else if trainingStats.spg >= 1.5 {
                insights.append(StudentInsight(
                    title: "Active Hands",
                    titleChinese: "积极拼抢",
                    description: "Quick hands with \(String(format: "%.1f", trainingStats.spg)) SPG. Good at reading passing lanes.",
                    descriptionChinese: "手快，场均 \(String(format: "%.1f", trainingStats.spg)) 抢断。善于判断传球路线。",
                    icon: "hand.raised.fill",
                    color: .teal,
                    priority: 6
                ))
            }
        }
        
        // MARK: - Attendance Insights
        if attendanceRate < 0.6 && recentAttendance.count >= 3 {
            insights.append(StudentInsight(
                title: "Attendance Concern",
                titleChinese: "出勤问题",
                description: "Only \(Int(attendanceRate * 100))% attendance rate. May be falling behind peers in skill development.",
                descriptionChinese: "出勤率仅 \(Int(attendanceRate * 100))%。可能在技能发展上落后于同龄人。",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                priority: 10
            ))
        } else if attendanceRate >= 0.95 && recentAttendance.count >= 5 {
            insights.append(StudentInsight(
                title: "Perfect Attendance",
                titleChinese: "全勤模范",
                description: "Excellent commitment with \(Int(attendanceRate * 100))% attendance. Dedicated and reliable.",
                descriptionChinese: "出勤率 \(Int(attendanceRate * 100))%，表现出色。态度认真，值得信赖。",
                icon: "checkmark.seal.fill",
                color: .green,
                priority: 5
            ))
        }
        
        // Check for recent absences
        let recentAbsences = recentAttendance.prefix(3).filter { $0.status != .present }.count
        if recentAbsences >= 2 {
            insights.append(StudentInsight(
                title: "Recent Absences",
                titleChinese: "近期缺勤",
                description: "Missed \(recentAbsences) of last 3 sessions. Check in about any issues.",
                descriptionChinese: "最近3次课缺席\(recentAbsences)次。建议了解是否有问题。",
                icon: "person.fill.questionmark",
                color: .orange,
                priority: 8
            ))
        }
        
        // MARK: - Skills Insights (updated for 6-skill model)
        let avgSkill = skills.overallRating
        
        if avgSkill >= 8 {
            let phrases = [
                ("All-Around Talent", "全能型选手", "Well-rounded player with high marks across all skills. Ready for advanced challenges.", "各项技能均衡出色。可以尝试更高难度的训练。"),
                ("Complete Player", "全面球员", "Exceptional skill set with no major weaknesses. Could mentor younger players.", "技术全面，没有明显短板。可以帮助指导年轻球员。"),
                ("Star Potential", "明星潜质", "Outstanding overall rating (\(String(format: "%.1f", avgSkill))). Consider competition-level challenges.", "综合评分出色 (\(String(format: "%.1f", avgSkill)))。可以考虑竞技级别的挑战。")
            ]
            let phrase = phrases.randomElement()!
            insights.append(StudentInsight(
                title: phrase.0, titleChinese: phrase.1,
                description: phrase.2, descriptionChinese: phrase.3,
                icon: "trophy.fill", color: .yellow, priority: 7
            ))
        } else if avgSkill >= 6 {
            insights.append(StudentInsight(
                title: "Solid Foundation", titleChinese: "基础扎实",
                description: "Good overall skills (\(String(format: "%.1f", avgSkill))/10). Focus on specific areas to level up.",
                descriptionChinese: "整体技术良好 (\(String(format: "%.1f", avgSkill))/10)。专注特定领域可以更上一层楼。",
                icon: "chart.line.uptrend.xyaxis", color: .blue, priority: 5
            ))
        }
        
        // Find weak areas (6-skill model)
        let skillData: [(String, String, Int)] = [
            ("Scoring", "得分", skills.scoring),
            ("Playmaking", "组织", skills.playmaking),
            ("Rebounding", "篮板", skills.rebounding),
            ("Defense", "防守", skills.defense),
            ("Athleticism", "运动能力", skills.athleticism),
            ("Intangibles", "软实力", skills.intangibles)
        ]
        
        let weakSkills = skillData.filter { $0.2 <= 4 }
        if let weakest = weakSkills.min(by: { $0.2 < $1.2 }), weakest.2 <= 4 {
            let focusPhrases = [
                ("Focus Area", "重点提升", "Current rating: \(weakest.2)/10. Include targeted drills for improvement.", "当前评分: \(weakest.2)/10。建议针对性训练。"),
                ("Development Priority", "发展优先级", "Needs work (\(weakest.2)/10). Dedicate extra reps this session.", "需要加强 (\(weakest.2)/10)。本次训练可以多练习。"),
                ("Growth Opportunity", "成长机会", "Room to improve (\(weakest.2)/10). Small gains here will boost overall game.", "有提升空间 (\(weakest.2)/10)。进步将显著提升整体实力。")
            ]
            let phrase = focusPhrases.randomElement()!
            insights.append(StudentInsight(
                title: "\(phrase.0): \(weakest.0)", titleChinese: "\(phrase.1): \(weakest.1)",
                description: phrase.2, descriptionChinese: phrase.3,
                icon: "arrow.up.circle.fill", color: .blue, priority: 6
            ))
        }
        
        // Find strong areas
        let strongSkills = skillData.filter { $0.2 >= 8 }
        if let strongest = strongSkills.max(by: { $0.2 < $1.2 }), strongest.2 >= 8 {
            let strengthPhrases = [
                ("Strength", "优势", "Rated \(strongest.2)/10. Can help teach teammates in this area.", "评分 \(strongest.2)/10。可以帮助队友提升这方面能力。"),
                ("Elite Skill", "精英技术", "Top-tier ability (\(strongest.2)/10). Leverage this in game situations.", "顶级能力 (\(strongest.2)/10)。在比赛中充分发挥。"),
                ("Key Asset", "核心优势", "Exceptional (\(strongest.2)/10). Build plays around this strength.", "出色 (\(strongest.2)/10)。可以围绕这一优势设计战术。")
            ]
            let phrase = strengthPhrases.randomElement()!
            insights.append(StudentInsight(
                title: "\(phrase.0): \(strongest.0)", titleChinese: "\(phrase.1): \(strongest.1)",
                description: phrase.2, descriptionChinese: phrase.3,
                icon: "star.circle.fill", color: .green, priority: 5
            ))
        }
        
        // MARK: - Contract Insights
        if let contract = contract {
            let remaining = contract.remainingSessions ?? 0
            if remaining <= 3 && remaining > 0 {
                insights.append(StudentInsight(
                    title: "Contract Ending Soon",
                    titleChinese: "合同即将到期",
                    description: "Only \(remaining) sessions remaining. Good time to discuss renewal.",
                    descriptionChinese: "仅剩 \(remaining) 节课。适合讨论续约。",
                    icon: "doc.text.fill",
                    color: .orange,
                    priority: 9
                ))
            }
        }
        
        // MARK: - Intangibles Insights (replaces coachability/teamwork)
        if skills.intangibles >= 9 {
            let phrases = [
                ("Leadership Material", "领袖气质", "Outstanding intangibles (\(skills.intangibles)/10). Natural leader who elevates the team.", "软实力出色 (\(skills.intangibles)/10)。天生的领袖，能带动团队。"),
                ("Culture Builder", "文化建设者", "Exceptional attitude and work ethic. Sets the tone for others.", "态度和职业精神出色。为他人树立榜样。"),
                ("Coachable Star", "易教之星", "Implements feedback instantly. A joy to work with.", "能立即营改建议。教起来很轻松。")
            ]
            let phrase = phrases.randomElement()!
            insights.append(StudentInsight(
                title: phrase.0, titleChinese: phrase.1,
                description: phrase.2, descriptionChinese: phrase.3,
                icon: "hand.thumbsup.fill", color: .green, priority: 4
            ))
        } else if skills.intangibles <= 4 {
            let phrases = [
                ("Patience Required", "需要耐心", "May need extra patience and creative approaches to instruction.", "可能需要更多耐心和创新的教学方式。"),
                ("Engagement Challenge", "参与度挑战", "Work on building trust and motivation. Find what drives them.", "需要建立信任和动力。找到他们的兴趣点。"),
                ("Growth Mindset Needed", "需培养成长心态", "Focus on building confidence and positive habits.", "专注于建立自信和积极习惯。")
            ]
            let phrase = phrases.randomElement()!
            insights.append(StudentInsight(
                title: phrase.0, titleChinese: phrase.1,
                description: phrase.2, descriptionChinese: phrase.3,
                icon: "clock.fill", color: .orange, priority: 6
            ))
        }
        
        // MARK: - Game Performance Insights
        if trainingStats.hasStats && trainingStats.gamesPlayed >= 5 {
            // Efficiency insight
            let totalStats = trainingStats.ppg + trainingStats.rpg + trainingStats.apg
            if totalStats >= 15 {
                insights.append(StudentInsight(
                    title: "High Impact Player", titleChinese: "高影响力球员",
                    description: "Contributing \(String(format: "%.1f", totalStats)) combined stats per game. Key player in any lineup.",
                    descriptionChinese: "场均贡献 \(String(format: "%.1f", totalStats)) 综合数据。任何阵容的核心球员。",
                    icon: "bolt.fill", color: .purple, priority: 7
                ))
            }
            
            // Double-double potential
            if (trainingStats.ppg >= 8 && trainingStats.rpg >= 8) || 
               (trainingStats.ppg >= 8 && trainingStats.apg >= 5) ||
               (trainingStats.rpg >= 8 && trainingStats.apg >= 5) {
                insights.append(StudentInsight(
                    title: "Double-Double Threat", titleChinese: "两双威胁",
                    description: "Consistently fills multiple stat categories. Versatile contributor.",
                    descriptionChinese: "稳定贡献多项数据。多面手球员。",
                    icon: "2.circle.fill", color: .indigo, priority: 6
                ))
            }
        }
        
        // MARK: - Improvement Trajectory
        if let lastEval = skills.lastEvaluatedDate {
            let daysSinceEval = Calendar.current.dateComponents([.day], from: lastEval, to: Date()).day ?? 0
            if daysSinceEval > 30 {
                insights.append(StudentInsight(
                    title: "Evaluation Due", titleChinese: "需要重新评估",
                    description: "Last evaluated \(daysSinceEval) days ago. Time for a skill reassessment.",
                    descriptionChinese: "\(daysSinceEval) 天前评估。是时候重新评估技能了。",
                    icon: "calendar.badge.exclamationmark", color: .orange, priority: 5
                ))
            }
        } else {
            insights.append(StudentInsight(
                title: "Initial Evaluation Needed", titleChinese: "需要初次评估",
                description: "No skill evaluation on record. Tap Edit to assess this player.",
                descriptionChinese: "暂无技能评估记录。点击编辑进行评估。",
                icon: "plus.circle.fill", color: .blue, priority: 8
            ))
        }
        
        // Sort by priority and limit to top 4
        return insights.sorted { $0.priority > $1.priority }.prefix(4).map { $0 }
    }
}

// MARK: - Quick Peep Radar View (Mini 6-axis radar)
/// Now uses PerformanceRadarMetrics for consistency with Intelligence Profile and Parent Report
struct QuickPeepRadarView: View {
    let metrics: PerformanceRadarMetrics
    
    private let axisCount = 6
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    private var labels: [String] {
        isChinese 
            ? ["得分", "组织", "篮板", "防守", "运动能力", "投入"]
            : ["Scoring", "Playmaking", "Rebounding", "Defense", "Athleticism", "Effort"]
    }
    
    private var values: [Double] {
        metrics.normalizedValues
    }
    
    private var displayValues: [Double] {
        // For label display, show the actual blended values (0-10 scale)
        [metrics.scoring, metrics.playmaking, metrics.rebounding, metrics.defense, metrics.athleticism, metrics.effort]
    }
    
    private var colors: [Color] {
        [.orange, .blue, .purple, .red, .green, .teal]
    }
    
    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 30
            
            ZStack {
                // Grid rings
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { scale in
                    radarPath(Array(repeating: scale, count: axisCount), center, radius)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                }
                
                // Axes
                ForEach(0..<axisCount, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: point(center, radius, angle(i)))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                }
                
                // Data fill with gradient
                radarPath(values, center, radius)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                radarPath(values, center, radius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                
                // Points with colors
                ForEach(0..<axisCount, id: \.self) { i in
                    Circle()
                        .fill(colors[i])
                        .frame(width: 6, height: 6)
                        .position(point(center, radius * values[i], angle(i)))
                }
                
                // Labels
                ForEach(0..<axisCount, id: \.self) { i in
                    VStack(spacing: 0) {
                        Text(labels[i])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.primary)
                        Text("\(Int(displayValues[i].rounded()))")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(colors[i])
                    }
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    .position(point(center, radius + 20, angle(i)))
                }
            }
        }
    }
    
    private func angle(_ i: Int) -> Double {
        -.pi/2 + (2 * .pi * Double(i) / Double(axisCount))
    }
    
    private func point(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint {
        CGPoint(x: c.x + r * Foundation.cos(a), y: c.y + r * Foundation.sin(a))
    }
    
    private func radarPath(_ vals: [Double], _ c: CGPoint, _ r: CGFloat) -> Path {
        Path { p in
            for (i, v) in vals.enumerated() {
                let pt = point(c, r * v, angle(i))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
    }
}

