import SwiftUI

/// Flippable baseball card-style profile view with front (stats) and back (contract/risk info)
struct StudentProfileCardView: View {
    let student: Student
    let player: Player?
    let trainingStats: TrainingSessionStats?
    let contract: Contract?
    let churnRisk: StudentIntelligence.ChurnRiskAssessment?
    let attendanceRate: Double? // 0-1 attendance percentage
    let sessionCount: Int // Total sessions attended
    
    @EnvironmentObject var dataManager: DataManager
    @State private var isFlipped = false
    @State private var flipDegrees: Double = 0
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    // Card colors
    private let cardBackground = Color(hex: "#F5F0E6")
    private let cardBorder = Color(hex: "#8B7355")
    private let statLabelColor = Color(hex: "#666666")
    
    var body: some View {
        ZStack {
            // Front of card (Stats)
            StudentProfileHeaderView(
                student: student,
                player: player,
                trainingStats: trainingStats
            )
            .opacity(isFlipped ? 0 : 1)
            .rotation3DEffect(
                .degrees(flipDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            
            // Back of card (Contract & Risk)
            cardBackSide
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(flipDegrees + 180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isFlipped.toggle()
                flipDegrees += 180
            }
        }
    }
    
    // Fixed card height to match front side
    private let cardHeight: CGFloat = 440
    
    // Service metrics computed from student data
    private var serviceMetrics: ServiceMetrics {
        let touchpoints = student.parentalTouchpoints
        let recentTouchpoints = touchpoints.filter {
            let days = Calendar.current.dateComponents([.day], from: $0.date, to: Date()).day ?? 0
            return days <= 30
        }
        let reportsSent = touchpoints.filter { $0.type == .reportCard }.count
        let hasRecentContact = recentTouchpoints.count > 0
        let hasVideo = student.mediaAssets.lastVideoDate != nil
        let daysSinceContact = student.lastParentContact.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 999
        } ?? 999
        
        return ServiceMetrics(
            parentContacted: hasRecentContact,
            daysSinceContact: daysSinceContact,
            reportsSent: reportsSent,
            videoShared: hasVideo,
            totalTouchpoints: touchpoints.count
        )
    }
    
    struct ServiceMetrics {
        let parentContacted: Bool
        let daysSinceContact: Int
        let reportsSent: Int
        let videoShared: Bool
        let totalTouchpoints: Int
    }
    
    // MARK: - Card Back Side (Performance Focus)
    private var cardBackSide: some View {
        VStack(spacing: 0) {
            // Compact header with name
            backHeader
            
            // Performance content - constrained to fit
            VStack(spacing: 6) {
                // Performance Radar (unified 6-axis)
                performanceRadarSection
                
                // Multi-stat trends
                performanceTrendsDetailed
                
                // Quick Actions hint at bottom
                tapToFlipHint
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .frame(height: cardHeight)
        .clipped()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorder, lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Performance Radar Section (Program Relative Model)
    
    /// Student's enrolled program (for relative comparison)
    private var enrolledProgram: Program? {
        dataManager.programs.first { program in
            program.enrolledStudentIds.contains(student.id)
        }
    }
    
    /// All student IDs in the same program for comparison
    private var programPeerIds: [UUID] {
        if let program = enrolledProgram {
            return program.enrolledStudentIds
        }
        // Fallback: compare against all students with game data
        return dataManager.students.map { $0.id }
    }
    
    /// Performance metrics using program-relative model
    /// Standard: 8 points from program percentile + 2 from coach (Effort: 6 coach + 4 stats)
    private var performanceMetrics: ProgramRelativeRadarMetrics {
        let skills = player?.skills ?? SkillsEvaluation()
        return ProgramRelativeRadarMetrics.compute(
            for: student.id,
            programId: enrolledProgram?.id,
            sessions: dataManager.sessionEvents,
            allStudentIds: programPeerIds,
            skills: skills
        )
    }
    
    private var performanceRadarSection: some View {
        let metrics = performanceMetrics
        let axisCount = 6
        let values = metrics.normalizedValues
        let labels = [
            isChinese ? "得分" : "Scoring",
            isChinese ? "组织" : "Playmaking",
            isChinese ? "篮板" : "Rebounding",
            isChinese ? "防守" : "Defense",
            isChinese ? "运动" : "Athletic",
            isChinese ? "努力" : "Effort"
        ]
        
        return VStack(spacing: 2) {
            sectionHeader(icon: "chart.pie.fill", title: isChinese ? "综合能力" : "PERFORMANCE", color: .pink)
            
            // 6-axis radar chart with properly positioned labels
            ZStack {
                // Chart area
                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - 24
                    
                    ZStack {
                        // Grid rings
                        ForEach([0.33, 0.66, 1.0], id: \.self) { scale in
                            radarPath(values: Array(repeating: scale, count: axisCount), center: center, radius: radius)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        }
                        
                        // Axes
                        ForEach(0..<axisCount, id: \.self) { i in
                            Path { p in
                                p.move(to: center)
                                p.addLine(to: radarPoint(center: center, radius: radius, index: i, count: axisCount))
                            }
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        }
                        
                        // Data fill
                        radarPath(values: values, center: center, radius: radius)
                            .fill(Color.pink.opacity(0.25))
                        radarPath(values: values, center: center, radius: radius)
                            .stroke(Color.pink, lineWidth: 2)
                        
                        // Data points
                        ForEach(0..<axisCount, id: \.self) { i in
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 5, height: 5)
                                .position(radarPoint(center: center, radius: radius * CGFloat(values[i]), index: i, count: axisCount))
                        }
                        
                        // Labels positioned symmetrically outside the chart
                        ForEach(0..<axisCount, id: \.self) { i in
                            radarLabel(labels[i], index: i, count: axisCount, center: center, radius: radius + 16)
                        }
                    }
                }
            }
            .frame(height: 140)
            
            // Data source indicator
            if metrics.hasGameData {
                Text("\(metrics.gamesPlayed) games")
                    .font(.system(size: 8))
                    .foregroundColor(statLabelColor.opacity(0.7))
            }
        }
    }
    
    private func radarLabel(_ text: String, index: Int, count: Int, center: CGPoint, radius: CGFloat) -> some View {
        let angle = -(.pi / 2) + (2 * .pi * Double(index) / Double(count))
        let x = center.x + radius * CGFloat(cos(angle))
        let y = center.y + radius * CGFloat(sin(angle))
        
        // Determine alignment based on position
        let alignment: Alignment = {
            if index == 0 { return .bottom } // Top
            if index == 3 { return .top } // Bottom
            if index == 1 || index == 2 { return .leading } // Right side
            return .trailing // Left side
        }()
        
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(statLabelColor)
            .position(x: x, y: y)
    }
    
    private func radarPoint(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = -(.pi / 2) + (2 * .pi * Double(index) / Double(count))
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
    
    private func radarPath(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for (i, v) in values.enumerated() {
                let pt = radarPoint(center: center, radius: radius * CGFloat(v), index: i, count: values.count)
                if i == 0 { path.move(to: pt) }
                else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
    }
    
    // MARK: - Training Stats Compact
    private var trainingStatsCompact: some View {
        VStack(spacing: 6) {
            if let stats = trainingStats, stats.hasStats {
                HStack(spacing: 0) {
                    statColumn(value: String(format: "%.1f", stats.ppg), label: "PPG", color: .orange)
                    Divider().frame(height: 28)
                    statColumn(value: String(format: "%.1f", stats.rpg), label: "RPG", color: .blue)
                    Divider().frame(height: 28)
                    statColumn(value: String(format: "%.1f", stats.apg), label: "APG", color: .green)
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.6))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 12))
                        .foregroundColor(statLabelColor)
                    Text(isChinese ? "暂无训练数据" : "No training stats yet")
                        .font(.system(size: 10))
                        .foregroundColor(statLabelColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.6))
                .cornerRadius(8)
            }
        }
    }
    
    private func statColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(statLabelColor)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Multi-Stat Trends (PPG, RPG, APG)
    private var performanceTrendsDetailed: some View {
        let trends = computeMultiStatTrends()
        
        return VStack(spacing: 6) {
            sectionHeader(icon: "chart.line.uptrend.xyaxis", title: isChinese ? "表现趋势" : "TRENDS", color: .green)
            
            if trends.hasData {
                // Compact 3-stat trend grid
                HStack(spacing: 6) {
                    trendCell(label: isChinese ? "得分" : "PPG", earlier: trends.ppgEarlier, recent: trends.ppgRecent, color: .orange)
                    trendCell(label: isChinese ? "篮板" : "RPG", earlier: trends.rpgEarlier, recent: trends.rpgRecent, color: .blue)
                    trendCell(label: isChinese ? "助攻" : "APG", earlier: trends.apgEarlier, recent: trends.apgRecent, color: .green)
                }
                
                // Overall assessment
                HStack(spacing: 6) {
                    Image(systemName: trends.overallTrend.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trends.overallTrend.color)
                    Text(trends.summary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(trends.overallTrend.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(trends.overallTrend.color.opacity(0.1))
                .cornerRadius(6)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 11))
                        .foregroundColor(statLabelColor)
                    Text(isChinese ? "需要4+场比赛" : "Need 4+ games")
                        .font(.system(size: 10))
                        .foregroundColor(statLabelColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.5))
                .cornerRadius(8)
            }
        }
    }
    
    private func trendCell(label: String, earlier: Double, recent: Double, color: Color) -> some View {
        let diff = recent - earlier
        let trend: TrendDirection = diff > 0.5 ? .up : (diff < -0.5 ? .down : .stable)
        
        return VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(statLabelColor)
            
            HStack(spacing: 2) {
                Text(String(format: "%.1f", recent))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Image(systemName: trend.icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(trend.color)
            }
            
            if diff != 0 {
                Text(diff > 0 ? String(format: "+%.1f", diff) : String(format: "%.1f", diff))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(trend.color)
            } else {
                Text("—")
                    .font(.system(size: 8))
                    .foregroundColor(statLabelColor.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
    }
    
    struct MultiStatTrends {
        var hasData: Bool
        var ppgEarlier: Double
        var ppgRecent: Double
        var rpgEarlier: Double
        var rpgRecent: Double
        var apgEarlier: Double
        var apgRecent: Double
        var overallTrend: TrendDirection
        var summary: String
    }
    
    private func computeMultiStatTrends() -> MultiStatTrends {
        var gameStats: [(pts: Int, reb: Int, ast: Int)] = []
        
        for session in dataManager.sessionEvents.sorted(by: { $0.date > $1.date }) {
            for game in session.games where game.status == .completed {
                if let stats = game.stats(for: student.id) {
                    gameStats.append((stats.points, stats.rebounds, stats.assists))
                }
            }
        }
        
        let games = Array(gameStats.prefix(8))
        guard games.count >= 4 else {
            return MultiStatTrends(hasData: false, ppgEarlier: 0, ppgRecent: 0, rpgEarlier: 0, rpgRecent: 0, apgEarlier: 0, apgRecent: 0, overallTrend: .stable, summary: "")
        }
        
        let half = games.count / 2
        let recent = Array(games.prefix(half))
        let earlier = Array(games.dropFirst(half))
        
        let ppgRecent = Double(recent.map { $0.pts }.reduce(0, +)) / Double(half)
        let ppgEarlier = Double(earlier.map { $0.pts }.reduce(0, +)) / Double(earlier.count)
        let rpgRecent = Double(recent.map { $0.reb }.reduce(0, +)) / Double(half)
        let rpgEarlier = Double(earlier.map { $0.reb }.reduce(0, +)) / Double(earlier.count)
        let apgRecent = Double(recent.map { $0.ast }.reduce(0, +)) / Double(half)
        let apgEarlier = Double(earlier.map { $0.ast }.reduce(0, +)) / Double(earlier.count)
        
        // Calculate overall trend
        var improvements = 0
        var declines = 0
        if ppgRecent - ppgEarlier > 0.5 { improvements += 1 } else if ppgEarlier - ppgRecent > 0.5 { declines += 1 }
        if rpgRecent - rpgEarlier > 0.3 { improvements += 1 } else if rpgEarlier - rpgRecent > 0.3 { declines += 1 }
        if apgRecent - apgEarlier > 0.3 { improvements += 1 } else if apgEarlier - apgRecent > 0.3 { declines += 1 }
        
        let overallTrend: TrendDirection
        let summary: String
        if improvements > declines && improvements >= 2 {
            overallTrend = .up
            summary = isChinese ? "整体进步" : "Improving"
        } else if declines > improvements && declines >= 2 {
            overallTrend = .down
            summary = isChinese ? "需要关注" : "Needs Focus"
        } else {
            overallTrend = .stable
            summary = isChinese ? "表现稳定" : "Steady"
        }
        
        return MultiStatTrends(
            hasData: true,
            ppgEarlier: ppgEarlier, ppgRecent: ppgRecent,
            rpgEarlier: rpgEarlier, rpgRecent: rpgRecent,
            apgEarlier: apgEarlier, apgRecent: apgRecent,
            overallTrend: overallTrend,
            summary: summary
        )
    }
    
    // MARK: - Back Header
    private var backHeader: some View {
        VStack(spacing: 2) {
            Text(isChinese ? "学员档案" : "PLAYER FILE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(statLabelColor)
            
            Text(student.displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
    
    // MARK: - Contract Section (Simplified)
    private func contractSectionCompact(_ contract: Contract) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                icon: "doc.text.fill",
                title: isChinese ? "合同" : "CONTRACT",
                color: .green
            )
            
            HStack(spacing: 12) {
                // Contract Type + Enrollment
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? contract.typeLabelChinese : contract.typeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.15))
                        .cornerRadius(4)
                    
                    Text((isChinese ? "入学: " : "Enrolled: ") + contract.enrollmentDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(statLabelColor)
                }
                
                Spacer()
                
                // Session Count
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("\(contract.sessionCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    Text(isChinese ? "已参加课时" : "sessions")
                        .font(.system(size: 10))
                        .foregroundColor(statLabelColor)
                    
                    // Show remaining for non-PAYG
                    if !contract.isPayAsYouGo, let remaining = contract.remainingSessions {
                        Text("\(remaining) \(isChinese ? "剩余" : "left")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(remaining <= 3 ? .orange : statLabelColor)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Risk & Metrics Section (Combined)
    private var riskAndMetricsSection: some View {
        VStack(spacing: 8) {
            // Risk header with score
            if let risk = churnRisk {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 12))
                            .foregroundColor(riskColor(risk.level))
                        Text(isChinese ? "健康状态" : "HEALTH")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(statLabelColor)
                    }
                    Spacer()
                    riskLevelBadge(risk.level)
                    Text("\(Int(risk.score))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(riskColor(risk.level))
                }
            }
            
            // 2x3 Metrics Grid
            HStack(spacing: 8) {
                // Left column
                VStack(spacing: 6) {
                    metricCell(
                        icon: "calendar.badge.checkmark",
                        label: isChinese ? "出勤" : "Attend",
                        value: attendanceRate.map { "\(Int($0 * 100))%" } ?? "—",
                        color: (attendanceRate ?? 0) >= 0.8 ? .green : (attendanceRate ?? 0) >= 0.6 ? .orange : .red
                    )
                    metricCell(
                        icon: "person.wave.2.fill",
                        label: isChinese ? "联系" : "Contact",
                        value: serviceMetrics.daysSinceContact < 999 ? "\(serviceMetrics.daysSinceContact)d" : "—",
                        color: serviceMetrics.daysSinceContact <= 14 ? .green : serviceMetrics.daysSinceContact <= 30 ? .orange : .red
                    )
                }
                
                // Middle column
                VStack(spacing: 6) {
                    metricCell(
                        icon: "figure.basketball",
                        label: isChinese ? "课时" : "Sessions",
                        value: "\(sessionCount)",
                        color: sessionCount >= 10 ? .green : sessionCount >= 5 ? .orange : .gray
                    )
                    metricCell(
                        icon: "doc.text.fill",
                        label: isChinese ? "报告" : "Reports",
                        value: "\(serviceMetrics.reportsSent)",
                        color: serviceMetrics.reportsSent > 0 ? .green : .gray
                    )
                }
                
                // Right column
                VStack(spacing: 6) {
                    metricCell(
                        icon: "message.fill",
                        label: isChinese ? "沟通" : "Touch",
                        value: "\(serviceMetrics.totalTouchpoints)",
                        color: serviceMetrics.totalTouchpoints >= 3 ? .green : serviceMetrics.totalTouchpoints >= 1 ? .orange : .gray
                    )
                    metricCell(
                        icon: "video.fill",
                        label: isChinese ? "视频" : "Video",
                        value: serviceMetrics.videoShared ? "✓" : "—",
                        color: serviceMetrics.videoShared ? .green : .gray
                    )
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.6))
            .cornerRadius(8)
            
            // Top risk factor if any
            if let risk = churnRisk, let topFactor = risk.factors.first(where: { $0.impact < 0 }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(riskColor(risk.level))
                    Text(topFactor.localizedName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(riskColor(risk.level))
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }
    
    private func metricCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(statLabelColor)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Parent Section (Compact)
    private func parentSectionCompact(_ parent: ParentInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                icon: "person.2.fill",
                title: isChinese ? "家长" : "PARENT",
                color: .teal
            )
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(parent.name) (\(parent.relationship))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    if !parent.phone.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                            Text(parent.phone)
                                .font(.system(size: 11))
                                .foregroundColor(statLabelColor)
                        }
                    }
                }
                Spacer()
                if let wechat = parent.wechatId, !wechat.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text(wechat)
                            .font(.system(size: 10))
                            .foregroundColor(statLabelColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Tap to Flip Hint
    private var tapToFlipHint: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12))
                Text(isChinese ? "点击翻转" : "Tap to flip")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(statLabelColor)
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(statLabelColor)
        }
    }
    
    private func statusBadge(_ status: ContractStatus) -> some View {
        Text(isChinese ? status.localizedNameChinese : status.localizedName)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(hex: status.color))
            .cornerRadius(8)
    }
    
    private func riskLevelBadge(_ level: StudentIntelligence.ChurnRiskLevel) -> some View {
        Text(riskLevelText(level))
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(riskColor(level))
            .cornerRadius(8)
    }
    
    private func riskColor(_ level: StudentIntelligence.ChurnRiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
    
    private func riskLevelText(_ level: StudentIntelligence.ChurnRiskLevel) -> String {
        switch level {
        case .low: return isChinese ? "低风险" : "Low Risk"
        case .moderate: return isChinese ? "中风险" : "Moderate Risk"
        case .high: return isChinese ? "高风险" : "High Risk"
        case .critical: return isChinese ? "危险" : "Critical"
        }
    }
}

#Preview {
    StudentProfileCardView(
        student: Student.samples.first!,
        player: nil,
        trainingStats: nil,
        contract: Contract.sample,
        churnRisk: nil,
        attendanceRate: 0.85,
        sessionCount: 12
    )
    .environmentObject(DataManager.shared)
    .padding()
    .background(Color.gray.opacity(0.2))
}
