import SwiftUI

struct StudentDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    @State private var showingEditSheet = false
    @State private var showingMeasurementSheet = false
    
    // Section expansion states
    @State private var showContract = true
    @State private var showParent = false
    @State private var showMeasurements = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var player: Player? {
        dataManager.player(for: student.id)
    }
    
    var contract: Contract? {
        dataManager.currentContract(for: student.id)
    }
    
    var measurementSummary: MeasurementSummary {
        dataManager.measurementSummary(for: student.id)
    }
    
    var enrolledPrograms: [Program] {
        dataManager.programs.filter { $0.enrolledStudentIds.contains(student.id) }
    }
    
    var hasLeagueData: Bool {
        dataManager.teams.contains { $0.playerIds.contains(student.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Clean header
                cleanHeader
                
                // Quick stats row
                quickStatsRow
                    .padding(.top, 16)
                
                // Main content sections
                VStack(spacing: 12) {
                    // Contract & Risk Analysis section (comprehensive)
                    contractAndRiskSection
                    
                    // Measurements
                    measurementsSection
                    
                    // League Stats
                    CollapsibleLeagueSection(studentId: student.id)
                    
                    // Training Stats
                    CollapsibleTrainingStatsSection(studentId: student.id)
                    
                    // Notes
                    if let player = player, let notes = player.coachNotes, !notes.isEmpty {
                        notesSection(notes)
                    }
                    
                    // Parent/Guardian (moved to bottom)
                    if let player = player, !player.parentInfo.name.isEmpty {
                        parentSection(player)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                Spacer(minLength: 100)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(student.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingEditSheet = true }) {
                    Text(isChinese ? "编辑" : "Edit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditStudentView(student: student, player: player)
        }
        .sheet(isPresented: $showingMeasurementSheet) {
            QuickMeasurementView(student: student, sessionId: nil)
        }
    }
    
    // MARK: - Clean Header
    private var cleanHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            StudentAvatarView(student: student, size: 80)
            
            // Name
            VStack(spacing: 4) {
                if isChinese, let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(student.name)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text(student.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            
            // Program badges
            if !enrolledPrograms.isEmpty {
                HStack(spacing: 8) {
                    ForEach(enrolledPrograms.prefix(3)) { program in
                        HStack(spacing: 4) {
                            Image(systemName: program.mascot.icon)
                                .font(.system(size: 10))
                            Text(program.name)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(program.mascotColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(program.mascotColor.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: 0) {
            // Age
            quickStatItem(
                value: student.age != nil ? "\(student.age!)" : "—",
                label: isChinese ? "年龄" : "Age"
            )
            
            Divider().frame(height: 32)
            
            // Sessions
            quickStatItem(
                value: contract?.isPayAsYouGo == true ? "∞" : "\(contract?.remainingSessions ?? 0)",
                label: isChinese ? "剩余" : "Left",
                valueColor: (contract?.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary
            )
            
            Divider().frame(height: 32)
            
            // Attended
            let attendedCount = contract?.attendedSessions ?? 0
            quickStatItem(
                value: "\(attendedCount)",
                label: isChinese ? "已上" : "Done"
            )
            
            Divider().frame(height: 32)
            
            // Height
            if let height = player?.heightCm {
                quickStatItem(
                    value: "\(Int(height))",
                    label: "cm"
                )
            } else {
                quickStatItem(
                    value: "—",
                    label: isChinese ? "身高" : "Height"
                )
            }
        }
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func quickStatItem(value: String, label: String, valueColor: Color = AppTheme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Contract & Risk Section (Comprehensive)
    private var contractAndRiskSection: some View {
        VStack(spacing: 12) {
            // Contract Card
            contractCard
            
            // Churn Risk Analysis Card
            churnRiskCard
        }
    }
    
    private var contractCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text(isChinese ? "合同状态" : "Contract Status")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
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
                    // Sessions Attended
                    VStack(spacing: 4) {
                        Text("\(contract.sessionCount)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text(isChinese ? "已参加" : "Attended")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 1, height: 50)
                    
                    // Remaining (for fixed) or Enrollment
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let remaining = contract.remainingSessions {
                            Text("\(remaining)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(remaining <= 3 ? .orange : .blue)
                            Text(isChinese ? "剩余" : "Remaining")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        } else {
                            Text(contract.enrollmentDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text(isChinese ? "入学日期" : "Enrolled")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(AppTheme.surfaceColor)
                        .frame(width: 1, height: 50)
                    
                    // Expiry or Duration
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let expiry = contract.expiryDate {
                            Text(expiry.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(contract.isExpired ? .red : AppTheme.textSecondary)
                            Text(contract.isExpired ? (isChinese ? "已过期" : "Expired") : (isChinese ? "到期日" : "Expires"))
                                .font(.system(size: 11))
                                .foregroundColor(contract.isExpired ? .red : AppTheme.textSecondary)
                        } else {
                            // Show enrollment duration for PAYG
                            let weeks = Calendar.current.dateComponents([.weekOfYear], from: contract.enrollmentDate, to: Date()).weekOfYear ?? 0
                            Text("\(weeks)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.purple)
                            Text(isChinese ? "周" : "Weeks")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(AppTheme.surfaceColor.opacity(0.5))
                .cornerRadius(12)
                
                // Progress bar for fixed contracts
                if !contract.isPayAsYouGo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(isChinese ? "进度" : "Progress")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                            Spacer()
                            Text("\(Int(contract.progressPercentage * 100))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.surfaceColor)
                                    .frame(height: 8)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * contract.progressPercentage, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
                
                // View attendance history link
                if contract.sessionCount > 0 {
                    NavigationLink(destination: AttendedSessionsListView(studentId: student.id)) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 12))
                            Text(isChinese ? "查看出勤记录" : "View attendance history")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.accentColor)
                        .padding(12)
                        .background(AppTheme.accentColor.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
            } else {
                // No contract
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.accentColor)
                    Text(isChinese ? "暂无合同，点击添加" : "No contract yet, tap to add")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.surfaceColor)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var churnRiskCard: some View {
        // Use static method with available data
        let risk = StudentIntelligence.analyzeChurnRisk(
            student: student,
            contract: contract,
            attendanceRecords: [],
            performanceStats: nil,
            allContracts: dataManager.contracts.filter { $0.studentId == student.id },
            player: player,
            enrolledProgram: enrolledPrograms.first,
            touchpoints: student.parentalTouchpoints
        )
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header with risk level badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(riskColor(risk.level))
                    Text(isChinese ? "留存分析" : "Retention Analysis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                // Risk level badge
                Text(riskLevelText(risk.level))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(riskColor(risk.level))
                    .cornerRadius(8)
            }
            
            // Risk score with gauge
            HStack(spacing: 16) {
                // Score
                VStack(spacing: 2) {
                    Text("\(Int(risk.score))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(riskColor(risk.level))
                    Text(isChinese ? "风险指数" : "Risk Score")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                // Gauge
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ).opacity(0.3)
                                )
                                .frame(height: 12)
                            
                            // Indicator
                            Circle()
                                .fill(riskColor(risk.level))
                                .frame(width: 16, height: 16)
                                .shadow(color: riskColor(risk.level).opacity(0.5), radius: 4)
                                .offset(x: geo.size.width * CGFloat(risk.score / 100) - 8)
                        }
                    }
                    .frame(height: 16)
                    
                    HStack {
                        Text(isChinese ? "低" : "Low")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Spacer()
                        Text(isChinese ? "高" : "High")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(AppTheme.surfaceColor.opacity(0.5))
            .cornerRadius(12)
            
            // Risk factors
            if !risk.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "影响因素" : "Key Factors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    ForEach(risk.factors.prefix(3), id: \.name) { factor in
                        HStack(spacing: 8) {
                            // Impact indicator
                            Circle()
                                .fill(factor.impact > 0 ? Color.green : (factor.impact < -10 ? Color.red : Color.orange))
                                .frame(width: 8, height: 8)
                            
                            Text(factor.localizedName)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Spacer()
                            
                            // Impact value
                            Text(factor.impact > 0 ? "+\(Int(factor.impact))" : "\(Int(factor.impact))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(factor.impact > 0 ? .green : (factor.impact < -10 ? .red : .orange))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Recommendation
            if let recommendation = risk.factors.first(where: { $0.impact < 0 }) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    Text(recommendationText(for: recommendation.name))
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
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
        case .moderate: return isChinese ? "中风险" : "Moderate"
        case .high: return isChinese ? "高风险" : "High Risk"
        case .critical: return isChinese ? "危险" : "Critical"
        }
    }
    
    private func recommendationText(for factorName: String) -> String {
        switch factorName {
        case "attendance": return isChinese ? "建议增加出勤率，可考虑调整课程时间" : "Consider adjusting class times to improve attendance"
        case "parentContact": return isChinese ? "建议联系家长，保持沟通" : "Reach out to parents to maintain engagement"
        case "contractProgress": return isChinese ? "合同即将到期，建议续约沟通" : "Contract expiring soon, discuss renewal"
        case "sessionGap": return isChinese ? "学生已有段时间未参加训练" : "Student hasn't attended recently"
        default: return isChinese ? "关注学生状态" : "Monitor student engagement"
        }
    }
    
    // MARK: - Contract Section (Simplified - Legacy)
    private var contractSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                Text(isChinese ? "合同" : "Contract")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if let contract = contract {
                    // Contract type badge
                    Text(isChinese ? contract.typeLabelChinese : contract.typeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12))
                        .cornerRadius(6)
                }
            }
            
            if let contract = contract {
                // Session count and progress
                HStack(spacing: 16) {
                    // Sessions Attended (main metric)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(contract.sessionCount)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                            Text(isChinese ? "已参加" : "attended")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        // For fixed contracts, show remaining
                        if !contract.isPayAsYouGo {
                            if let remaining = contract.remainingSessions {
                                Text("\(remaining) \(isChinese ? "剩余" : "remaining")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(remaining <= 3 ? .orange : AppTheme.textTertiary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Right side info
                    VStack(alignment: .trailing, spacing: 4) {
                        // Enrollment date
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 10))
                            Text(contract.enrollmentDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.textSecondary)
                        
                        // Expiry for fixed contracts
                        if !contract.isPayAsYouGo, let expiry = contract.expiryDate {
                            HStack(spacing: 4) {
                                Image(systemName: contract.isExpired ? "exclamationmark.triangle.fill" : "calendar")
                                    .font(.system(size: 10))
                                Text(expiry.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(contract.isExpired ? .red : AppTheme.textTertiary)
                        }
                    }
                }
                
                // Progress bar for fixed contracts
                if !contract.isPayAsYouGo {
                    GeometryReader { geo in
                        let progress = contract.progressPercentage
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.surfaceColor)
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                
                // View sessions link
                if contract.sessionCount > 0 {
                    NavigationLink(destination: AttendedSessionsListView(studentId: student.id)) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 11))
                            Text(isChinese ? "查看出勤记录" : "View attendance history")
                                .font(.system(size: 12))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.accentColor)
                        .padding(.top, 4)
                    }
                }
            } else {
                // No contract - show create option
                Text(isChinese ? "暂无合同记录" : "No contract yet")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Parent Section
    private func parentSection(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.teal)
                Text(isChinese ? "家长/监护人" : "Parent/Guardian")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Parent avatar
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(player.parentInfo.name.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.teal)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.parentInfo.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(player.parentInfo.relationship)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Spacer()
                
                // Quick contact buttons
                if !player.parentInfo.phone.isEmpty {
                    Link(destination: URL(string: "tel:\(player.parentInfo.phone)")!) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                            .padding(10)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                
                if let wechat = player.parentInfo.wechatId, !wechat.isEmpty {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .padding(10)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Circle())
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Measurements Section
    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text(isChinese ? "测量数据" : "Measurements")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: { showingMeasurementSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            
            if measurementSummary.measurements.isEmpty {
                Button(action: { showingMeasurementSheet = true }) {
                    HStack {
                        Text(isChinese ? "点击记录身高、体重等" : "Tap to record height, weight...")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(12)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                // Compact measurement grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(measurementSummary.measurements.prefix(6)) { measurement in
                        VStack(spacing: 2) {
                            Text(measurement.formattedValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(measurement.type.rawValue)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Notes Section
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text(isChinese ? "教练备注" : "Coach Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            Text(notes)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Helper Views
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        StudentDetailView(student: Student.samples[0])
            .environmentObject(DataManager.shared)
    }
}
