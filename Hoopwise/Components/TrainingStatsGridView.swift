import SwiftUI

struct TrainingStatsGridView: View {
    let student: Student
    let player: Player?
    let scorecard: StudentIntelligence.HolisticScorecard
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text(isChinese ? "训练数据" : "Training Stats")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statItem(
                    value: String(scorecard.technicalPerformance.score),
                    label: isChinese ? "技术" : "Technical",
                    color: .orange
                )
                
                statItem(
                    value: String(scorecard.behavioralPatterns.score),
                    label: isChinese ? "表现" : "Behavior",
                    color: .blue
                )
                
                statItem(
                    value: String(scorecard.financialHealth.score),
                    label: isChinese ? "续约" : "Financial",
                    color: .green
                )
                
                statItem(
                    value: String(format: "%.0f", scorecard.overallScore),
                    label: isChinese ? "总分" : "Overall",
                    color: .purple
                )
                
                statItem(
                    value: scorecard.trend.rawValue,
                    label: isChinese ? "趋势" : "Trend",
                    color: scorecard.trend == .improving ? .green : (scorecard.trend == .declining ? .red : .orange)
                )
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 64, height: 64)
                
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    TrainingStatsGridView(
        student: Student.samples.first!,
        player: nil,
        scorecard: StudentIntelligence.HolisticScorecard(
            financialHealth: .init(score: 90, label: "Financial", details: []),
            technicalPerformance: .init(score: 85, label: "Technical", details: []),
            behavioralPatterns: .init(score: 75, label: "Behavior", details: []),
            overallScore: 83,
            trend: .improving
        )
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}
