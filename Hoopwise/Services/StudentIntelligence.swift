import Foundation
import SwiftUI

// MARK: - Student Intelligence Service
/// AI-powered analytics for student engagement, performance, and relationship management
class StudentIntelligence {
    
    // MARK: - Churn Risk Analysis
    
    enum ChurnRiskLevel: String, CaseIterable {
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .moderate: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .low: return "checkmark.shield.fill"
            case .moderate: return "exclamationmark.shield.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.shield.fill"
            }
        }
        
        var localizedName: String {
            switch self {
            case .low: return rawValue
            case .moderate: return rawValue
            case .high: return rawValue
            case .critical: return rawValue
            }
        }
        
        var localizedNameChinese: String {
            switch self {
            case .low: return "低风险"
            case .moderate: return "中等风险"
            case .high: return "高风险"
            case .critical: return "紧急风险"
            }
        }
    }
    
    struct ChurnRiskAssessment {
        let level: ChurnRiskLevel
        let score: Double // 0-100
        let factors: [RiskFactor]
        let recommendations: [String]
        let recommendationsChinese: [String]
        
        var localizedRecommendations: [String] {
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            return isChinese ? recommendationsChinese : recommendations
        }
        
        struct RiskFactor {
            let name: String
            let nameChinese: String
            let impact: Double // -1 to 1, negative is bad
            let description: String
            let descriptionChinese: String
            
            var localizedName: String {
                let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                return isChinese ? nameChinese : name
            }
            
            var localizedDescription: String {
                let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                return isChinese ? descriptionChinese : description
            }
        }
    }
    
    /// Comprehensive churn risk analysis using all available student data
    /// Enhanced version that considers: contracts, weekly attendance, payment status, parent engagement,
    /// skill progression, program enrollment, tenure, and behavioral patterns
    static func analyzeChurnRisk(
        student: Student,
        contract: Contract?,
        attendanceRecords: [AttendanceRecord],
        performanceStats: SeasonStats?,
        allContracts: [Contract] = [],
        player: Player? = nil,
        enrolledProgram: Program? = nil,
        touchpoints: [ParentalTouchpoint] = []
    ) -> ChurnRiskAssessment {
        var factors: [ChurnRiskAssessment.RiskFactor] = []
        var totalScore: Double = 50 // Start neutral
        
        // ========== FACTOR 1: Contract & Session Status (Weight: 30%) ==========
        if let contract = contract {
            // Session-based analysis (applies to all contract types)
            let sessionCount = contract.sessionCount
            
            if contract.isPayAsYouGo {
                // For PAYG: Check engagement based on session frequency
                let weeksSinceEnrollment = Calendar.current.dateComponents([.weekOfYear], from: contract.enrollmentDate, to: Date()).weekOfYear ?? 1
                let sessionsPerWeek = Double(sessionCount) / max(Double(weeksSinceEnrollment), 1)
                
                if sessionsPerWeek >= 1.0 {
                    factors.append(.init(name: "Regular Attendance", nameChinese: "定期出勤", impact: 0.25, description: "\(String(format: "%.1f", sessionsPerWeek)) sessions/week", descriptionChinese: "每周 \(String(format: "%.1f", sessionsPerWeek)) 节课"))
                    totalScore += 12
                } else if sessionsPerWeek < 0.5 && weeksSinceEnrollment >= 4 {
                    factors.append(.init(name: "Low Engagement", nameChinese: "参与度低", impact: -0.25, description: "Only \(String(format: "%.1f", sessionsPerWeek)) sessions/week", descriptionChinese: "每周仅 \(String(format: "%.1f", sessionsPerWeek)) 节课"))
                    totalScore -= 12
                }
            } else {
                // Fixed contract: Check remaining sessions
                let remaining = contract.remainingSessions ?? 0
                let sessionRatio = Double(remaining) / max(Double(contract.totalSessions), 1)
                
                if remaining <= 2 {
                    factors.append(.init(name: "Renewal Urgent", nameChinese: "紧急续约", impact: -0.4, description: "Only \(remaining) sessions left - discuss renewal now", descriptionChinese: "仅剩 \(remaining) 节课 - 立即讨论续约"))
                    totalScore -= 20
                } else if remaining <= 5 {
                    factors.append(.init(name: "Renewal Soon", nameChinese: "即将续约", impact: -0.25, description: "\(remaining) sessions remaining", descriptionChinese: "剩余 \(remaining) 节课"))
                    totalScore -= 12
                } else if sessionRatio > 0.6 {
                    factors.append(.init(name: "Sessions Healthy", nameChinese: "课时充足", impact: 0.2, description: "\(remaining) sessions remaining", descriptionChinese: "剩余 \(remaining) 节课"))
                    totalScore += 10
                }
            }
            
            // Contract expiry analysis (only for non-PAYG)
            if !contract.isPayAsYouGo, let expiry = contract.expiryDate {
                let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                if daysUntilExpiry < 0 {
                    factors.append(.init(name: "Contract Expired", nameChinese: "合同已过期", impact: -0.5, description: "Expired \(abs(daysUntilExpiry)) days ago - contact parent", descriptionChinese: "已过期 \(abs(daysUntilExpiry)) 天 - 联系家长"))
                    totalScore -= 25
                } else if daysUntilExpiry < 7 {
                    factors.append(.init(name: "Expires This Week", nameChinese: "本周到期", impact: -0.35, description: "Only \(daysUntilExpiry) days left", descriptionChinese: "仅剩 \(daysUntilExpiry) 天"))
                    totalScore -= 18
                } else if daysUntilExpiry < 14 {
                    factors.append(.init(name: "Expires Soon", nameChinese: "即将到期", impact: -0.25, description: "\(daysUntilExpiry) days until expiry", descriptionChinese: "\(daysUntilExpiry) 天后到期"))
                    totalScore -= 12
                } else if daysUntilExpiry < 30 {
                    factors.append(.init(name: "Expiring Next Month", nameChinese: "下月到期", impact: -0.15, description: "\(daysUntilExpiry) days until expiry", descriptionChinese: "\(daysUntilExpiry) 天后到期"))
                    totalScore -= 8
                }
            }
            
            // Weekly attendance from contract (if available)
            if !contract.weeklyAttendance.isEmpty {
                let totalExpected = contract.weeklyAttendance.reduce(0) { $0 + $1.expectedSessions }
                let totalAttended = contract.weeklyAttendance.reduce(0) { $0 + $1.attendedSessions }
                let weeklyRate = totalExpected > 0 ? Double(totalAttended) / Double(totalExpected) : 0
                
                if weeklyRate < 0.6 {
                    factors.append(.init(name: "Poor Weekly Attendance", nameChinese: "每周出勤差", impact: -0.35, description: "Only \(Int(weeklyRate * 100))% weekly attendance rate", descriptionChinese: "每周出勤率仅 \(Int(weeklyRate * 100))%"))
                    totalScore -= 18
                } else if weeklyRate < 0.75 {
                    factors.append(.init(name: "Below Average Attendance", nameChinese: "出勤低于平均", impact: -0.2, description: "\(Int(weeklyRate * 100))% weekly attendance", descriptionChinese: "每周出勤率 \(Int(weeklyRate * 100))%"))
                    totalScore -= 10
                } else if weeklyRate >= 0.9 {
                    factors.append(.init(name: "Excellent Attendance", nameChinese: "出勤优秀", impact: 0.3, description: "\(Int(weeklyRate * 100))% weekly attendance", descriptionChinese: "每周出勤率 \(Int(weeklyRate * 100))%"))
                    totalScore += 15
                }
                
                // Check recent weeks trend (last 4 weeks)
                let recentWeeks = contract.weeklyAttendance.sorted { $0.weekStartDate > $1.weekStartDate }.prefix(4)
                let recentMissed = recentWeeks.filter { $0.attendedSessions < $0.expectedSessions }.count
                if recentMissed >= 3 {
                    factors.append(.init(name: "Recent Decline", nameChinese: "最近下降", impact: -0.25, description: "Missed sessions in \(recentMissed) of last 4 weeks - disengagement signal", descriptionChinese: "最近4周中有 \(recentMissed) 周缺课 - 脱离信号"))
                    totalScore -= 12
                }
            }
        } else {
            factors.append(.init(name: "No Active Contract", nameChinese: "无有效合同", impact: -0.5, description: "Student has no active contract", descriptionChinese: "学生无有效合同"))
            totalScore -= 25
        }
        
        // ========== FACTOR 2: Student Tenure & History (Weight: 15%) ==========
        let contractCount = allContracts.isEmpty ? (contract != nil ? 1 : 0) : allContracts.count
        if contractCount >= 3 {
            factors.append(.init(name: "Loyal Student", nameChinese: "忠诚学生", impact: 0.3, description: "\(contractCount) contracts - long-term relationship", descriptionChinese: "\(contractCount) 份合同 - 长期关系"))
            totalScore += 15
        } else if contractCount == 2 {
            factors.append(.init(name: "Returning Student", nameChinese: "回归学生", impact: 0.15, description: "On 2nd contract - building loyalty", descriptionChinese: "第二份合同 - 建立忠诚度"))
            totalScore += 8
        } else if contractCount == 1 {
            // First contract students need extra attention
            if let contract = contract, !contract.isPayAsYouGo, (contract.remainingSessions ?? 0) < contract.totalSessions / 2 {
                factors.append(.init(name: "First Contract Critical Phase", nameChinese: "首份合同关键阶段", impact: -0.1, description: "First contract past halfway - key renewal decision point", descriptionChinese: "首份合同过半 - 关键续约决定点"))
                totalScore -= 5
            }
        }
        
        // Student tenure based on first contract start date
        if let firstContract = allContracts.min(by: { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }),
           let startDate = firstContract.startDate {
            let monthsEnrolled = Calendar.current.dateComponents([.month], from: startDate, to: Date()).month ?? 0
            if monthsEnrolled >= 12 {
                factors.append(.init(name: "Long-term Student", nameChinese: "长期学生", impact: 0.2, description: "Enrolled for \(monthsEnrolled) months", descriptionChinese: "已注册 \(monthsEnrolled) 个月"))
                totalScore += 10
            }
        }
        
        // ========== FACTOR 3: Parent Engagement (Weight: 20%) ==========
        let recentTouchpoints = touchpoints.filter {
            let daysSince = Calendar.current.dateComponents([.day], from: $0.date, to: Date()).day ?? 0
            return daysSince <= 60
        }
        
        // Check if parent info exists
        let hasParentInfo = player?.parentInfo.name.isEmpty == false
        
        if let lastContact = student.lastParentContact ?? touchpoints.first?.date {
            let daysSinceContact = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            
            if daysSinceContact > 60 {
                factors.append(.init(name: "Contact Overdue", nameChinese: "联系过期", impact: -0.3, description: "Last contact \(daysSinceContact) days ago", descriptionChinese: "上次联系在 \(daysSinceContact) 天前"))
                totalScore -= 15
            } else if daysSinceContact > 30 {
                factors.append(.init(name: "Contact Due", nameChinese: "需要联系", impact: -0.15, description: "Last contact \(daysSinceContact) days ago", descriptionChinese: "上次联系在 \(daysSinceContact) 天前"))
                totalScore -= 8
            } else if daysSinceContact < 14 {
                factors.append(.init(name: "Recently Contacted", nameChinese: "最近联系", impact: 0.2, description: "Last contact \(daysSinceContact) days ago", descriptionChinese: "上次联系在 \(daysSinceContact) 天前"))
                totalScore += 10
            }
            
            // Quality of touchpoints - check for follow-ups needed
            let followUpNeeded = recentTouchpoints.filter { $0.followUpNeeded }.count
            if followUpNeeded >= 2 {
                factors.append(.init(name: "Follow-ups Needed", nameChinese: "需要跟进", impact: -0.2, description: "\(followUpNeeded) items need follow-up", descriptionChinese: "\(followUpNeeded) 项需要跟进"))
                totalScore -= 10
            }
        } else if hasParentInfo {
            // Parent info exists but no contact logged yet - mild concern, actionable
            factors.append(.init(name: "Log Parent Contact", nameChinese: "记录家长联系", impact: -0.1, description: "Tap + to log your first contact", descriptionChinese: "点击+记录首次联系"))
            totalScore -= 5
        }
        // If no parent info at all, don't penalize - they may not have provided it yet
        
        // ========== FACTOR 4: Skill Progression (Weight: 15%) ==========
        // The eight-skill evaluation, once enough skills are rated (it read
        // the retired six skills: everyone was a flat 5, and any program with
        // a level set counted as "Meeting Program Goals").
        if let skills = player?.skills, let overallSkill = skills.ratedAverage {
            if let targets = enrolledProgram?.skillTargets, targets.hasTargets, targets.comparable(skills) > 0 {
                let belowTarget = targets.below(skills).count
                if belowTarget == 0 {
                    factors.append(.init(name: "Meeting Program Goals", nameChinese: "达到项目目标", impact: 0.2, description: "At or above every target they are rated on", descriptionChinese: "已评估的技能均达到或超过目标"))
                    totalScore += 10
                } else if belowTarget >= 4 {
                    factors.append(.init(name: "Struggling with Skills", nameChinese: "技能困难", impact: -0.15, description: "\(belowTarget) skills below program target", descriptionChinese: "\(belowTarget) 项技能低于项目目标"))
                    totalScore -= 8
                }
            }

            // General skill level
            if overallSkill >= 7 {
                factors.append(.init(name: "High Performer", nameChinese: "表现优秀", impact: 0.15, description: "Strong skill development", descriptionChinese: "技能发展强劲"))
                totalScore += 8
            } else if overallSkill < 4 {
                factors.append(.init(name: "Skill Development Needed", nameChinese: "需要技能发展", impact: -0.1, description: "May need extra support and encouragement", descriptionChinese: "可能需要额外的支持和鼓励"))
                totalScore -= 5
            }
        }
        
        // ========== FACTOR 5: Program Engagement (Weight: 10%) ==========
        if let program = enrolledProgram {
            factors.append(.init(name: "Program Enrolled", nameChinese: "已注册项目", impact: 0.1, description: "Enrolled in \(program.name)", descriptionChinese: "已注册 \(program.name)"))
            totalScore += 5
        } else {
            factors.append(.init(name: "No Program", nameChinese: "无项目", impact: -0.05, description: "Not enrolled in any program", descriptionChinese: "未注册任何项目"))
            totalScore -= 3
        }
        
        // ========== FACTOR 6: Session Attendance Records (Weight: 15%) ==========
        if attendanceRecords.count >= 5 {
            let presentCount = attendanceRecords.filter { $0.status == .present }.count
            let lateCount = attendanceRecords.filter { $0.status == .late }.count
            let absentCount = attendanceRecords.filter { $0.status == .absent }.count
            let total = attendanceRecords.count
            
            let attendanceRate = Double(presentCount + lateCount) / Double(total)
            let lateRate = Double(lateCount) / Double(total)
            let absentRate = Double(absentCount) / Double(total)
            
            if absentRate > 0.3 {
                factors.append(.init(name: "High Absence Rate", nameChinese: "高缺勤率", impact: -0.35, description: "Absent \(Int(absentRate * 100))% of sessions", descriptionChinese: "缺勤 \(Int(absentRate * 100))% 的课程"))
                totalScore -= 18
            } else if attendanceRate < 0.7 {
                factors.append(.init(name: "Poor Attendance", nameChinese: "出勤差", impact: -0.3, description: "Only \(Int(attendanceRate * 100))% attendance rate", descriptionChinese: "出勤率仅 \(Int(attendanceRate * 100))%"))
                totalScore -= 15
            }
            
            // Late trend detection (Silent Churn indicator)
            if lateRate > 0.25 {
                factors.append(.init(name: "Punctuality Issues", nameChinese: "守时问题", impact: -0.25, description: "Late \(Int(lateRate * 100))% of sessions - possible disengagement", descriptionChinese: "迟到 \(Int(lateRate * 100))% 的课程 - 可能存在脱离情况"))
                totalScore -= 12
            }
            
            // Check recent trend (last 5 sessions)
            let recentRecords = Array(attendanceRecords.suffix(5))
            let recentAbsent = recentRecords.filter { $0.status == .absent }.count
            let recentLate = recentRecords.filter { $0.status == .late }.count
            
            if recentAbsent >= 2 {
                factors.append(.init(name: "Recent Absences", nameChinese: "最近缺勤", impact: -0.3, description: "Absent \(recentAbsent) of last 5 sessions - urgent attention needed", descriptionChinese: "最近5次课程缺勤 \(recentAbsent) 次 - 需要紧急关注"))
                totalScore -= 15
            } else if recentLate >= 3 {
                factors.append(.init(name: "Recent Late Trend", nameChinese: "最近迟到趋势", impact: -0.2, description: "Late in \(recentLate) of last 5 sessions", descriptionChinese: "最近5次课程中迟到 \(recentLate) 次"))
                totalScore -= 10
            }
        }
        
        // ========== FACTOR 7: Performance Stats (if available) ==========
        if let stats = performanceStats {
            if stats.ppg < 3 && stats.gamesPlayed > 3 {
                factors.append(.init(name: "Low Game Performance", nameChinese: "比赛表现差", impact: -0.15, description: "Averaging only \(String(format: "%.1f", stats.ppg)) PPG - may affect confidence", descriptionChinese: "平均仅 \(String(format: "%.1f", stats.ppg)) PPG - 可能影响信心"))
                totalScore -= 8
            } else if stats.ppg > 10 {
                factors.append(.init(name: "Strong Performer", nameChinese: "表现优秀", impact: 0.1, description: "Averaging \(String(format: "%.1f", stats.ppg)) PPG", descriptionChinese: "平均 \(String(format: "%.1f", stats.ppg)) PPG"))
                totalScore += 5
            }
        }
        
        // Clamp score between 0-100
        totalScore = max(0, min(100, totalScore))
        
        // Determine risk level with refined thresholds
        let level: ChurnRiskLevel
        switch totalScore {
        case 0..<20: level = .critical
        case 20..<40: level = .high
        case 40..<60: level = .moderate
        default: level = .low
        }
        
        // Generate smart, actionable recommendations based on factors
        let (recommendations, recommendationsChinese) = generateSmartRecommendations(factors: factors, student: student, contract: contract, level: level)
        
        return ChurnRiskAssessment(
            level: level,
            score: totalScore,
            factors: factors,
            recommendations: recommendations,
            recommendationsChinese: recommendationsChinese
        )
    }
    
    /// Generate smart, prioritized recommendations based on risk factors
    private static func generateSmartRecommendations(
        factors: [ChurnRiskAssessment.RiskFactor],
        student: Student,
        contract: Contract?,
        level: ChurnRiskLevel
    ) -> (recommendations: [String], recommendationsChinese: [String]) {
        var recommendations: [String] = []
        var recommendationsChinese: [String] = []
        let negativeFactors = factors.filter { $0.impact < 0 }.sorted { $0.impact < $1.impact }
        
        // Priority 1: Contract-related (most urgent)
        for factor in negativeFactors {
            switch factor.name {
            case "Renewal Urgent", "Contract Expired":
                recommendations.append("🚨 URGENT: Call parent today to discuss renewal")
                recommendationsChinese.append("🚨 紧急：今天致电家长讨论续约")
            case "Expires This Week":
                recommendations.append("📞 Schedule renewal call with parent this week")
                recommendationsChinese.append("📞 本周安排与家长的续约通话")
            case "Renewal Soon", "Expires Soon", "Expiring Next Month":
                recommendations.append("📋 Prepare renewal proposal and schedule parent meeting")
                recommendationsChinese.append("📋 准备续约提案并安排家长会议")
            case "No Active Contract":
                recommendations.append("💼 Reach out to discuss enrollment - student may be waiting")
                recommendationsChinese.append("💼 主动联系讨论注册 - 学生可能在等待")
            case "Low Engagement":
                recommendations.append("� Check in with student - may need schedule adjustment or encouragement")
                recommendationsChinese.append("� 与学生沟通 - 可能需要调整时间或鼓励")
            default:
                break
            }
        }
        
        // Priority 2: Parent engagement
        for factor in negativeFactors {
            switch factor.name {
            case "Contact Overdue":
                recommendations.append("📞 Contact parent - it's been over 60 days")
                recommendationsChinese.append("📞 联系家长 - 已超过60天")
            case "Contact Due":
                recommendations.append("📱 Schedule a check-in with parent")
                recommendationsChinese.append("📱 安排与家长的沟通")
            case "Log Parent Contact":
                recommendations.append("📝 Log your parent interactions to track engagement")
                recommendationsChinese.append("📝 记录家长互动以跟踪参与度")
            case "Follow-ups Needed":
                recommendations.append("✅ Complete pending follow-ups with parent")
                recommendationsChinese.append("✅ 完成待处理的家长跟进")
            default:
                break
            }
        }
        
        // Priority 3: Attendance-related
        for factor in negativeFactors {
            switch factor.name {
            case "Poor Weekly Attendance", "High Absence Rate", "Recent Absences":
                recommendations.append("🗣️ Have 1-on-1 conversation with \(student.name) about what's making sessions difficult")
                recommendationsChinese.append("🗣️ 与 \(student.name) 进行一对一谈话，了解课程困难的原因")
            case "Recent Decline", "Below Average Attendance":
                recommendations.append("📱 Send encouraging message to student and check if schedule needs adjustment")
                recommendationsChinese.append("📱 向学生发送鼓励信息并检查是否需要调整时间表")
            case "Punctuality Issues", "Recent Late Trend":
                recommendations.append("⏰ Ask about transportation or schedule conflicts that may cause lateness")
                recommendationsChinese.append("⏰ 询问可能导致迟到的交通或时间冲突问题")
            default:
                break
            }
        }
        
        // Priority 3: Parent relationship
        for factor in negativeFactors {
            switch factor.name {
            case "Parent Disengaged":
                recommendations.append("📧 Send personalized progress update email to re-engage parent")
                recommendationsChinese.append("📧 发送个性化进度更新邮件以重新吸引家长")
            case "Parent Contact Overdue", "No Parent Contact":
                recommendations.append("📱 Schedule brief check-in call with parent")
                recommendationsChinese.append("📱 安排与家长的简短查看通话")
            case "Parent Concerns":
                recommendations.append("🤝 Address parent concerns directly - schedule face-to-face meeting if possible")
                recommendationsChinese.append("🤝 直接解决家长疑虑 - 如可能安排面对面会议")
            default:
                break
            }
        }
        
        // Priority 4: Development-related
        for factor in negativeFactors {
            switch factor.name {
            case "Struggling with Skills", "Skill Development Needed":
                recommendations.append("🎯 Create personalized skill development plan and share progress with parent")
                recommendationsChinese.append("🎯 制定个性化技能发展计划并与家长分享进度")
            case "Low Game Performance":
                recommendations.append("💪 Focus on confidence-building activities and celebrate small wins")
                recommendationsChinese.append("💪 专注于建立信心的活动并庆祝小成就")
            case "First Contract Critical Phase":
                recommendations.append("⭐ Highlight student's progress and value to encourage renewal")
                recommendationsChinese.append("⭐ 强调学生的进步和价值以鼓励续约")
            default:
                break
            }
        }
        
        // Add general recommendation based on risk level
        if level == .critical && recommendations.isEmpty {
            recommendations.append("🚨 High churn risk - immediate personal outreach recommended")
            recommendationsChinese.append("🚨 高流失风险 - 建议立即进行个人联系")
        } else if level == .high && recommendations.count < 2 {
            recommendations.append("⚠️ Schedule proactive check-in to address potential concerns")
            recommendationsChinese.append("⚠️ 安排主动查看以解决潜在问题")
        }
        
        // Remove duplicates and limit to top 4 most important
        let finalRecommendations = Array(Set(recommendations)).prefix(4).map { $0 }
        let finalRecommendationsChinese = Array(Set(recommendationsChinese)).prefix(4).map { $0 }
        
        return (finalRecommendations, finalRecommendationsChinese)
    }
    
}

// MARK: - Attendance Record (if not already defined)
extension AttendanceRecord {
    /// A student's MARKED classes that already happened, OLDEST FIRST (the
    /// engines below read "recent" as `suffix`), each
    /// with its recorded mark — the population AttendanceMath.rate counts:
    /// past, not skipped/cancelled, and explicitly present / excused / absent.
    /// Unmarked is neither attended nor missed. The two views that fed the
    /// insight engines (quick peep, intelligence card) used to take every
    /// session whose stored attendeeIds held the student — future ones
    /// included, empty for enrollment-backed sessions — and call anything not
    /// present "absent".
    static func marked(for studentId: UUID, in sessions: [SessionEvent],
                       asOf now: Date = Date()) -> [AttendanceRecord] {
        sessions.compactMap { session -> AttendanceRecord? in
            guard session.date <= now, !SessionLifecycle.didNotHappen(session) else { return nil }
            let status: AttendanceStatus
            if session.actualAttendeeIds.contains(studentId) {
                status = .present
            } else if session.excusedAbsences.contains(studentId) {
                status = .excused
            } else if session.unexcusedAbsences.contains(studentId) {
                status = .absent
            } else {
                return nil
            }
            return AttendanceRecord(studentId: studentId, sessionId: session.id,
                                    status: status, recordedAt: session.startTime)
        }
        .sorted { $0.recordedAt < $1.recordedAt }
    }
}

struct AttendanceRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var sessionId: UUID
    var status: AttendanceStatus
    var arrivalTime: Date?
    var notes: String?
    var recordedAt: Date
    
    init(id: UUID = UUID(), studentId: UUID, sessionId: UUID, status: AttendanceStatus = .present,
         arrivalTime: Date? = nil, notes: String? = nil, recordedAt: Date = Date()) {
        self.id = id
        self.studentId = studentId
        self.sessionId = sessionId
        self.status = status
        self.arrivalTime = arrivalTime
        self.notes = notes
        self.recordedAt = recordedAt
    }
}
