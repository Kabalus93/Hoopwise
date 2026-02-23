import SwiftUI

// MARK: - Skill Bar (Minimalist)
struct SkillBar: View {
    let label: String
    let value: Int
    let maxValue: Int
    var color: Color = AppTheme.accentColor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surfaceColor)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: max(geometry.size.width * CGFloat(value) / CGFloat(maxValue), 4))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Session Progress Bar (Minimalist)
struct SessionProgressBar: View {
    let completed: Int
    let total: Int
    var showLabel: Bool = true
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    var color: Color {
        if progress >= 0.8 { return AppTheme.warningColor }
        if progress >= 0.5 { return Color(hex: "#FFE066") }
        return AppTheme.successColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLabel {
                HStack {
                    Text("\(completed) of \(total)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(total - completed) left")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surfaceColor)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: max(geometry.size.width * progress, 4))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Circular Progress (Minimalist)
struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 60
    var lineWidth: CGFloat = 5
    var color: Color = AppTheme.accentColor
    var showPercentage: Bool = true
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.surfaceColor, lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            
            if showPercentage {
                Text("\(Int(progress * 100))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Rating Stars (Minimalist)
struct RatingStarsView: View {
    let rating: Int
    let maxRating: Int
    var size: CGFloat = 14
    var color: Color = Color(hex: "#FFD700")
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundColor(index <= rating ? color : AppTheme.surfaceColor)
            }
        }
    }
}

// MARK: - Difficulty Indicator (Minimalist)
struct DifficultyIndicator: View {
    let difficulty: DifficultyLevel
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < difficulty.level ? Color.difficultyColor(difficulty) : AppTheme.surfaceColor)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Linear Progress
struct LinearProgress: View {
    let progress: Double
    var height: CGFloat = 4
    var color: Color = AppTheme.accentColor
    var backgroundColor: Color = AppTheme.surfaceColor
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(backgroundColor)
                
                Capsule()
                    .fill(color)
                    .frame(width: max(geometry.size.width * progress, height))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Step Indicator
struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    var activeColor: Color = AppTheme.accentColor
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                if step < totalSteps {
                    Circle()
                        .fill(step <= currentStep ? activeColor : AppTheme.surfaceColor)
                        .frame(width: 8, height: 8)
                    
                    Rectangle()
                        .fill(step < currentStep ? activeColor : AppTheme.surfaceColor)
                        .frame(height: 2)
                } else {
                    Circle()
                        .fill(step <= currentStep ? activeColor : AppTheme.surfaceColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        SkillBar(label: "Shooting", value: 7, maxValue: 10)
        SessionProgressBar(completed: 8, total: 24)
        CircularProgressView(progress: 0.75)
        RatingStarsView(rating: 4, maxRating: 5)
        DifficultyIndicator(difficulty: .intermediate)
        LinearProgress(progress: 0.6)
        StepIndicator(currentStep: 2, totalSteps: 4)
    }
    .padding(AppTheme.spacing)
    .background(AppTheme.background)
}
