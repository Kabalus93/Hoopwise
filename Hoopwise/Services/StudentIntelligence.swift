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
        if let player = player {
            let overallSkill = player.skills.overallRating
            
            // Check if enrolled in program with targets
            if let program = enrolledProgram, let targets = program.skillTargets {
                let belowTarget = targets.skillsBelowTarget(player.skills)
                if belowTarget == 0 {
                    factors.append(.init(name: "Meeting Program Goals", nameChinese: "达到项目目标", impact: 0.2, description: "All skills at or above program targets", descriptionChinese: "所有技能都达到或超过项目目标"))
                    totalScore += 10
                } else if belowTarget >= 4 {
                    factors.append(.init(name: "Struggling with Skills", nameChinese: "技能困难", impact: -0.15, description: "\(belowTarget) skills below program targets - may feel discouraged", descriptionChinese: "\(belowTarget) 项技能低于项目目标 - 可能感到沮丧"))
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
    
    // MARK: - Holistic Scorecard
    
    struct HolisticScorecard {
        let financialHealth: ScoreComponent
        let technicalPerformance: ScoreComponent
        let behavioralPatterns: ScoreComponent
        let overallScore: Double
        let trend: Trend
        
        struct ScoreComponent {
            let score: Double // 0-100
            let label: String
            let details: [String]
        }
        
        enum Trend: String {
            case improving = "Improving"
            case stable = "Stable"
            case declining = "Declining"
            
            var icon: String {
                switch self {
                case .improving: return "arrow.up.right"
                case .stable: return "arrow.right"
                case .declining: return "arrow.down.right"
                }
            }
            
            var color: Color {
                switch self {
                case .improving: return .green
                case .stable: return .blue
                case .declining: return .orange
                }
            }
        }
    }
    
    /// Generate holistic scorecard combining financial, performance, and behavioral data
    static func generateScorecard(
        student: Student,
        contract: Contract?,
        player: Player?,
        attendanceRecords: [AttendanceRecord],
        seasonStats: SeasonStats?
    ) -> HolisticScorecard {
        // Financial Health
        var financialScore: Double = 50
        var financialDetails: [String] = []
        
        if let contract = contract {
            if contract.status == .active {
                financialScore += 20
                financialDetails.append("Active contract")
            }
            if contract.isFullyPaid {
                financialScore += 15
                financialDetails.append("Fully paid")
            } else {
                let paidPercent = (contract.amountPaid / max(contract.totalAmount, 1)) * 100
                financialDetails.append("\(Int(paidPercent))% paid")
            }
            if contract.isPayAsYouGo {
                financialScore += 10
                financialDetails.append("Pay As You Go")
            } else {
                let remaining = contract.remainingSessions ?? 0
                if remaining > 10 {
                    financialScore += 15
                    financialDetails.append("\(remaining) sessions remaining")
                } else if remaining <= 3 {
                    financialScore -= 10
                    financialDetails.append("Only \(remaining) sessions left")
                }
            }
        } else {
            financialScore = 20
            financialDetails.append("No active contract")
        }
        
        // Technical Performance
        var performanceScore: Double = 50
        var performanceDetails: [String] = []
        
        if let stats = seasonStats, stats.gamesPlayed > 0 {
            performanceScore = 40 + min(stats.ppg * 3, 30) // PPG contribution
            performanceDetails.append("\(String(format: "%.1f", stats.ppg)) PPG")
            performanceDetails.append("\(String(format: "%.1f", stats.rpg)) RPG")
            performanceDetails.append("\(String(format: "%.1f", stats.apg)) APG")
        } else if let player = player {
            performanceScore = player.skills.overallRating * 10
            performanceDetails.append("Skills rating: \(String(format: "%.1f", player.skills.overallRating))")
        } else {
            performanceDetails.append("No performance data")
        }
        
        // Behavioral Patterns
        var behavioralScore: Double = 50
        var behavioralDetails: [String] = []
        
        if attendanceRecords.count > 0 {
            let presentCount = attendanceRecords.filter { $0.status == .present }.count
            let total = attendanceRecords.count
            let rate = Double(presentCount) / Double(total)
            behavioralScore = rate * 100
            behavioralDetails.append("\(Int(rate * 100))% attendance")
            
            let lateCount = attendanceRecords.filter { $0.status == .late }.count
            if lateCount > 0 {
                behavioralDetails.append("\(lateCount) late arrivals")
            }
        } else {
            behavioralDetails.append("No attendance data")
        }
        
        // Calculate overall and trend
        let overall = (financialScore + performanceScore + behavioralScore) / 3
        
        // Simple trend based on recent attendance
        let trend: HolisticScorecard.Trend
        if attendanceRecords.count >= 6 {
            let recent = Array(attendanceRecords.suffix(3))
            let older = Array(attendanceRecords.dropLast(3).suffix(3))
            let recentRate = Double(recent.filter { $0.status == .present }.count) / 3
            let olderRate = Double(older.filter { $0.status == .present }.count) / 3
            if recentRate > olderRate + 0.1 {
                trend = .improving
            } else if recentRate < olderRate - 0.1 {
                trend = .declining
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }
        
        return HolisticScorecard(
            financialHealth: .init(score: min(100, financialScore), label: "Financial", details: financialDetails),
            technicalPerformance: .init(score: min(100, performanceScore), label: "Performance", details: performanceDetails),
            behavioralPatterns: .init(score: min(100, behavioralScore), label: "Engagement", details: behavioralDetails),
            overallScore: min(100, overall),
            trend: trend
        )
    }
    
    // MARK: - Milestone Detection
    
    enum MilestoneType: String, CaseIterable {
        case birthday = "Birthday"
        case contractAnniversary = "Contract Anniversary"
        case personalBest = "Personal Best"
        case attendanceMilestone = "Attendance Milestone"
        case skillImprovement = "Skill Improvement"
        
        var icon: String {
            switch self {
            case .birthday: return "gift.fill"
            case .contractAnniversary: return "calendar.badge.clock"
            case .personalBest: return "star.fill"
            case .attendanceMilestone: return "checkmark.seal.fill"
            case .skillImprovement: return "chart.line.uptrend.xyaxis"
            }
        }
        
        var color: Color {
            switch self {
            case .birthday: return .pink
            case .contractAnniversary: return .blue
            case .personalBest: return .yellow
            case .attendanceMilestone: return .green
            case .skillImprovement: return .purple
            }
        }
    }
    
    struct Milestone {
        let type: MilestoneType
        let title: String
        let description: String
        let date: Date
        let actionSuggestion: String?
    }
    
    /// Detect upcoming milestones for a student
    static func detectMilestones(
        student: Student,
        contract: Contract?,
        attendanceRecords: [AttendanceRecord]
    ) -> [Milestone] {
        var milestones: [Milestone] = []
        let calendar = Calendar.current
        let today = Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        
        // Birthday check
        if let birthdate = student.birthdate {
            let birthdayThisYear = calendar.date(bySetting: .year, value: calendar.component(.year, from: today), of: birthdate)!
            let daysUntilBirthday = calendar.dateComponents([.day], from: today, to: birthdayThisYear).day ?? 0
            
            if daysUntilBirthday >= 0 && daysUntilBirthday <= 14 {
                let age = (student.age ?? 0) + (daysUntilBirthday == 0 ? 0 : 1)
                milestones.append(Milestone(
                    type: .birthday,
                    title: daysUntilBirthday == 0 ? "Happy Birthday!" : "Birthday Coming Up",
                    description: daysUntilBirthday == 0 ? "\(student.name) turns \(age) today!" : "\(student.name) turns \(age) in \(daysUntilBirthday) days",
                    date: birthdayThisYear,
                    actionSuggestion: "Send birthday message to parent with recent highlights"
                ))
            }
        }
        
        // Contract anniversary
        if let contract = contract, let startDate = contract.startDate {
            let monthsSinceStart = calendar.dateComponents([.month], from: startDate, to: today).month ?? 0
            if monthsSinceStart > 0 && monthsSinceStart % 6 == 0 {
                milestones.append(Milestone(
                    type: .contractAnniversary,
                    title: "\(monthsSinceStart) Month Anniversary",
                    description: "\(student.name) has been training for \(monthsSinceStart) months",
                    date: today,
                    actionSuggestion: "Send progress report to parent"
                ))
            }
        }
        
        // Attendance milestone
        let totalPresent = attendanceRecords.filter { $0.status == .present || $0.status == .late }.count
        let milestoneNumbers = [10, 25, 50, 100, 150, 200]
        for milestone in milestoneNumbers {
            if totalPresent == milestone {
                milestones.append(Milestone(
                    type: .attendanceMilestone,
                    title: "\(milestone) Sessions Attended!",
                    description: "\(student.name) has completed \(milestone) training sessions",
                    date: today,
                    actionSuggestion: "Celebrate achievement and share with parent"
                ))
                break
            }
        }
        
        return milestones
    }
    
    // MARK: - Alert Generation
    
    enum AlertPriority: Int, Comparable {
        case low = 0
        case medium = 1
        case high = 2
        case urgent = 3
        
        static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .urgent: return .red
            }
        }
    }
    
    struct StudentAlert: Identifiable {
        let id = UUID()
        let studentId: UUID
        let priority: AlertPriority
        let title: String
        let message: String
        let actionType: AlertActionType
        let createdAt: Date
        
        enum AlertActionType: String {
            case contactParent = "Contact Parent"
            case renewContract = "Renew Contract"
            case wellnessCheck = "Wellness Check"
            case scheduleReview = "Schedule Review"
            case celebrate = "Celebrate"
        }
    }
    
    /// Generate alerts for a student based on various factors
    static func generateAlerts(
        student: Student,
        contract: Contract?,
        attendanceRecords: [AttendanceRecord],
        seasonStats: SeasonStats?,
        previousStats: SeasonStats?
    ) -> [StudentAlert] {
        var alerts: [StudentAlert] = []
        
        // Parent contact alert
        if let lastContact = student.lastParentContact {
            let daysSince = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
            
            // High-value check (has active contract with many sessions)
            let isHighValue = contract?.remainingSessions ?? 0 > 15
            let threshold = isHighValue ? 14 : 21
            
            if daysSince > threshold {
                alerts.append(StudentAlert(
                    studentId: student.id,
                    priority: isHighValue ? .high : .medium,
                    title: "Parent Update Needed",
                    message: "No contact with \(student.name)'s parent in \(daysSince) days",
                    actionType: .contactParent,
                    createdAt: Date()
                ))
            }
        } else if contract?.status == .active {
            alerts.append(StudentAlert(
                studentId: student.id,
                priority: .medium,
                title: "No Parent Contact Logged",
                message: "Start tracking parent communication for \(student.name)",
                actionType: .contactParent,
                createdAt: Date()
            ))
        }
        
        // Contract renewal alert (skip pay-as-you-go)
        if let contract = contract {
            if !contract.isPayAsYouGo && (contract.remainingSessions ?? 0) <= 3 && contract.status == .active {
                alerts.append(StudentAlert(
                    studentId: student.id,
                    priority: .urgent,
                    title: "Contract Almost Complete",
                    message: "\(student.name) has only \(contract.remainingSessions ?? 0) sessions left",
                    actionType: .renewContract,
                    createdAt: Date()
                ))
            }
            
            if let expiry = contract.expiryDate {
                let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                if daysUntil > 0 && daysUntil <= 7 {
                    alerts.append(StudentAlert(
                        studentId: student.id,
                        priority: .high,
                        title: "Contract Expiring",
                        message: "\(student.name)'s contract expires in \(daysUntil) days",
                        actionType: .renewContract,
                        createdAt: Date()
                    ))
                }
            }
        }
        
        // Performance drop - Wellness check
        if let current = seasonStats, let previous = previousStats {
            if current.gamesPlayed >= 3 && previous.gamesPlayed >= 3 {
                let ppgDrop = previous.ppg - current.ppg
                let dropPercent = ppgDrop / max(previous.ppg, 1)
                
                if dropPercent > 0.3 { // 30% drop
                    alerts.append(StudentAlert(
                        studentId: student.id,
                        priority: .high,
                        title: "Performance Drop Detected",
                        message: "\(student.name)'s scoring dropped \(Int(dropPercent * 100))% - consider wellness check",
                        actionType: .wellnessCheck,
                        createdAt: Date()
                    ))
                }
            }
        }
        
        // Punctuality trend alert
        if attendanceRecords.count >= 5 {
            let recent = Array(attendanceRecords.suffix(5))
            let lateCount = recent.filter { $0.status == .late }.count
            if lateCount >= 3 {
                alerts.append(StudentAlert(
                    studentId: student.id,
                    priority: .medium,
                    title: "Punctuality Concern",
                    message: "\(student.name) was late \(lateCount) of last 5 sessions",
                    actionType: .scheduleReview,
                    createdAt: Date()
                ))
            }
        }
        
        return alerts.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Attendance Record (if not already defined)
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
