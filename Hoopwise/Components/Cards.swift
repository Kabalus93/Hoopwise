import SwiftUI

// MARK: - Student Card (Minimalist with League Stats)
struct StudentCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    var player: Player?
    var contract: Contract?
    var measurementSummary: MeasurementSummary?
    var showDetails: Bool = true
    var showMeasurements: Bool = true
    var showLeagueStats: Bool = true
    
    /// Category color based on student's age group from organization settings
    private var categoryColor: Color {
        dataManager.categoryColor(for: student)
    }
    
    /// Age category for the student
    private var ageCategory: CustomAgeCategory? {
        dataManager.ageCategory(for: student)
    }
    
    /// Teams this student is on
    private var teams: [Team] {
        dataManager.teams.filter { $0.playerIds.contains(student.id) }
    }
    
    /// Primary team
    private var primaryTeam: Team? {
        teams.first
    }
    
    /// Season stats for this player
    private var seasonStats: SeasonStats? {
        guard let player = player else { return nil }
        return dataManager.seasonStats.first { $0.playerId == player.id }
    }
    
    /// Check if current language is Chinese
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                StudentAvatarView(student: student, size: 52)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Language-aware name display
                        if isChinese && student.chineseName != nil {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(student.chineseName!)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(student.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        } else {
                            Text(student.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        // Age category badge (from organization settings)
                        if let category = ageCategory {
                            Text(category.shortName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor)
                                .cornerRadius(4)
                        } else if let ageGroup = student.ageGroup {
                            // Fallback to computed age group
                            Text(ageGroup.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor)
                                .cornerRadius(4)
                        }
                        
                        // Team badge (compact)
                        if showLeagueStats, let team = primaryTeam {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(team.primaryColor)
                                    .frame(width: 6, height: 6)
                                Text(team.shortName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(team.primaryColor)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(team.primaryColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        
                        // Contract status indicator
                        if let contract = contract {
                            Circle()
                                .fill(Color.contractStatusColor(contract.status))
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        // Only show Chinese name in secondary row if in English mode
                        if !isChinese, let chineseName = student.chineseName {
                            Text(chineseName)
                                .font(AppTheme.captionFont)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        if showDetails, let age = student.age {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text("\(age) yrs")
                                .font(AppTheme.captionFont)
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        // Season stats (compact)
                        if showLeagueStats, let stats = seasonStats, stats.gamesPlayed > 0 {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(String(format: "%.1f PPG", stats.ppg))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        
                        // Contract label
                        if let contract = contract, contract.contractNumber > 1 {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(contract.contractLabel)
                                .font(AppTheme.captionFont)
                                .foregroundColor(AppTheme.accentColor)
                        }
                    }
                }
                
                Spacer()
                
                // Contract info display
                if let contract = contract, contract.totalSessions > 0 || contract.isPayAsYouGo {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor((!contract.isPayAsYouGo && (contract.remainingSessions ?? 0) < 5) ? AppTheme.warningColor : AppTheme.successColor)
                        Text(contract.isPayAsYouGo ? "PAYG" : "left")
                            .font(AppTheme.smallFont)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            // League stats row (if has stats and no measurements)
            if showLeagueStats, let stats = seasonStats, stats.gamesPlayed > 0, !showMeasurements {
                Divider()
                    .padding(.vertical, 8)
                
                HStack(spacing: 12) {
                    leagueStatBadge(value: String(format: "%.1f", stats.ppg), label: "PPG", color: .orange)
                    leagueStatBadge(value: String(format: "%.1f", stats.rpg), label: "RPG", color: .blue)
                    leagueStatBadge(value: String(format: "%.1f", stats.apg), label: "APG", color: .green)
                    leagueStatBadge(value: "\(stats.gamesPlayed)", label: "GP", color: .gray)
                    Spacer()
                }
            }
            
            // Measurement stats row
            if showMeasurements, let summary = measurementSummary, !summary.measurements.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                HStack(spacing: 16) {
                    if let height = summary.latestHeight {
                        MeasurementBadge(icon: "ruler", value: height, color: .blue)
                    }
                    if let weight = summary.latestWeight {
                        MeasurementBadge(icon: "scalemass", value: weight, color: .green)
                    }
                    if let wingspan = summary.latestWingspan {
                        MeasurementBadge(icon: "arrow.left.and.right", value: wingspan, color: .purple)
                    }
                    if let sprint = summary.latestSprintTime {
                        MeasurementBadge(icon: "stopwatch", value: sprint, color: .orange)
                    }
                    if let shooting = summary.latestShootingPercent {
                        MeasurementBadge(icon: "basketball", value: shooting, color: .red)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(AppTheme.spacing)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
    }
    
    private func leagueStatBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Measurement Badge
struct MeasurementBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Session Card (Minimalist)
struct SessionCard: View {
    @EnvironmentObject var dataManager: DataManager
    let session: SessionEvent
    var program: Program? = nil
    
    /// Category color from organization settings based on program's age group
    private var categoryColor: Color {
        if let ageGroup = program?.ageGroup {
            return dataManager.categoryColor(for: ageGroup)
        }
        return AppTheme.accentColor
    }
    
    private var isCancelled: Bool { session.status == .cancelled }
    
    var body: some View {
        HStack(spacing: 16) {
            // Date block
            VStack(spacing: 2) {
                Text(session.date.formatted(.dateTime.day()))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(categoryColor.accessibleText)
                Text(session.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(width: 50)
            
            // Divider line
            Rectangle()
                .fill(AppTheme.surfaceColor)
                .frame(width: 2)
                .cornerRadius(1)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(isCancelled ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .strikethrough(isCancelled, color: .red.opacity(0.7))
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(session.startTime.formatted(date: .omitted, time: .shortened))
                    }
                    
                    if let location = session.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                            Text(location)
                                .lineLimit(1)
                        }
                    }
                }
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            // Status indicator / Cancelled badge
            if isCancelled {
                Text("CANCELLED")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(4)
            } else {
                Circle()
                    .fill(Color.statusColor(session.status))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(AppTheme.spacing)
        .background(isCancelled ? Color.red.opacity(0.05) : AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(isCancelled ? Color.red.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Program Card (Minimalist)
struct ProgramCard: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    var enrolledCount: Int = 0
    var phaseCount: Int = 0
    var sessionCount: Int = 0
    
    /// Category color from organization settings
    private var categoryColor: Color {
        dataManager.categoryColor(for: program.ageGroup)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // Mascot Avatar
                ProgramAvatarView(program: program, size: 48)
                
                VStack(alignment: .leading, spacing: 3) {
                    // Mascot name as title
                    Text(program.mascot.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(categoryColor.accessibleText)
                    
                    // Program name as subtitle
                    Text(program.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(program.ageGroup.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text(program.ageGroup.categoryName)
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(categoryColor.accessibleText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(categoryColor.opacity(0.12))
                .cornerRadius(6)
            }
            
            // Stats row - compact
            HStack(spacing: 0) {
                // Weeks
                CompactStatItem(value: "\(program.durationWeeks)", label: "wks", icon: "calendar")
                
                Divider().frame(height: 16).padding(.horizontal, 8)
                
                // Phases
                CompactStatItem(value: "\(phaseCount)", label: "phases", icon: "square.stack.3d.up")
                
                Divider().frame(height: 16).padding(.horizontal, 8)
                
                // Sessions
                CompactStatItem(value: "\(sessionCount)", label: "sessions", icon: "clock")
                
                Divider().frame(height: 16).padding(.horizontal, 8)
                
                // Enrolled
                CompactStatItem(value: "\(enrolledCount)", label: "players", icon: "person.2")
                
                Spacer()
                
                if program.isActive {
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.successColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.successColor.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
    }
}

// MARK: - Compact Stat Item
struct CompactStatItem: View {
    let value: String
    let label: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(AppTheme.smallFont)
                .foregroundColor(AppTheme.textTertiary)
        }
    }
}

// MARK: - Drill Card (Enhanced Visual Design)
struct DrillCard: View {
    let drill: DrillItem
    var onFavorite: (() -> Void)?
    var style: DrillCardStyle = .standard
    
    enum DrillCardStyle {
        case standard
        case compact
        case featured
    }
    
    private var categoryColor: Color {
        Color.drillCategoryColor(drill.category)
    }
    
    var body: some View {
        switch style {
        case .standard:
            standardCard
        case .compact:
            compactCard
        case .featured:
            featuredCard
        }
    }
    
    // MARK: - Standard Card
    private var standardCard: some View {
        HStack(spacing: 14) {
            // Category Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: drill.category.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: categoryColor.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(drill.localizedName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Category pill
                    Text(drill.localizedCategory)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(categoryColor.accessibleText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.12))
                        .cornerRadius(6)
                    
                    // Duration
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                        Text(drill.localizedDuration)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    
                    // Players
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text(drill.localizedPlayerRange)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
                
                // Difficulty indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i < drill.difficulty.level ? Color.difficultyColor(drill.difficulty) : AppTheme.surfaceColor)
                            .frame(width: 16, height: 4)
                    }
                    Text(drill.localizedDifficulty)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.difficultyColor(drill.difficulty))
                        .padding(.leading, 4)
                }
            }
            
            Spacer()
            
            // Favorite button
            if let onFavorite = onFavorite {
                Button(action: {
                    HapticFeedback.impact(.light)
                    onFavorite()
                }) {
                    Image(systemName: drill.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundColor(drill.isFavorite ? .red : AppTheme.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(drill.isFavorite ? Color.red.opacity(0.1) : AppTheme.surfaceColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Compact Card
    private var compactCard: some View {
        HStack(spacing: 12) {
            // Small icon
            Image(systemName: drill.category.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(categoryColor)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.localizedName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(drill.localizedDuration)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            // Difficulty dots
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i < drill.difficulty.level ? Color.difficultyColor(drill.difficulty) : AppTheme.surfaceColor)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Featured Card (Large)
    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top gradient section
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [categoryColor, categoryColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 100)
                
                // Category icon watermark
                Image(systemName: drill.category.icon)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
                    .offset(x: 120, y: -10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(drill.localizedCategory.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(drill.localizedName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                .padding(16)
            }
            .cornerRadius(16, corners: [.topLeft, .topRight])
            
            // Bottom info section
            VStack(alignment: .leading, spacing: 10) {
                Text(drill.description)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
                
                HStack(spacing: 16) {
                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                        Text(drill.localizedDuration)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    
                    // Players
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                        Text(drill.localizedPlayerRange)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    
                    Spacer()
                    
                    // Difficulty
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(i < drill.difficulty.level ? Color.difficultyColor(drill.difficulty) : AppTheme.surfaceColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
        }
        .shadow(color: categoryColor.opacity(0.2), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Drill Category Card (For Browse Section)
struct DrillCategoryCard: View {
    let category: DrillCategory
    let drillCount: Int
    var isSelected: Bool = false
    
    private var categoryColor: Color {
        Color.drillCategoryColor(category)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: category.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: categoryColor.opacity(0.3), radius: 6, x: 0, y: 3)
            .overlay(
                Circle()
                    .stroke(isSelected ? categoryColor : Color.clear, lineWidth: 3)
                    .frame(width: 64, height: 64)
            )
            
            Text(DrillLocalization.localizedCategory(category))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? categoryColor : AppTheme.textPrimary)
            
            Text("\(drillCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(isSelected ? categoryColor.opacity(0.08) : Color.clear)
        .cornerRadius(16)
    }
}

// MARK: - Quick Stats Card
struct DrillStatsCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .cornerRadius(16)
    }
}

// MARK: - Status Badge (Minimalist)
struct StatusBadge: View {
    let status: SessionEventStatus
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceColor)
        .cornerRadius(20)
    }
}

// MARK: - Category Badge (Minimalist)
struct CategoryBadge: View {
    let ageGroup: AgeGroup
    
    var body: some View {
        Text(ageGroup.rawValue)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color.ageGroupColor(ageGroup))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.ageGroupColor(ageGroup).opacity(0.12))
            .cornerRadius(20)
    }
}

// MARK: - Minimal List Row
struct MinimalListRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = AppTheme.accentColor
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, AppTheme.spacing)
        .background(AppTheme.cardBackground)
    }
}

// MARK: - Program Avatar View
struct ProgramAvatarView: View {
    let program: Program
    var size: CGFloat = 56
    
    var body: some View {
        ZStack {
            // Background gradient
            Circle()
                .fill(program.mascot.gradient)
            
            // Mascot icon
            Image(systemName: program.mascotIcon)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: program.mascotColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Program Mascot Picker
struct ProgramMascotPicker: View {
    @Binding var selectedMascot: ProgramMascot
    
    private let columns = [
        GridItem(.adaptive(minimum: 70), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ProgramMascot.allCases, id: \.self) { mascot in
                Button {
                    selectedMascot = mascot
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(mascot.gradient)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: mascot.icon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .overlay(
                            Circle()
                                .stroke(selectedMascot == mascot ? Color.white : Color.clear, lineWidth: 3)
                        )
                        .shadow(color: mascot.color.opacity(0.3), radius: 3, x: 0, y: 2)
                        
                        Text(mascot.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selectedMascot == mascot ? AppTheme.textPrimary : AppTheme.textSecondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedMascot == mascot ? mascot.color.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Program Badge (Compact)
struct ProgramBadge: View {
    let program: Program
    var showName: Bool = true
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(program.mascot.gradient)
                    .frame(width: 28, height: 28)
                
                Image(systemName: program.mascotIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            if showName {
                Text(program.mascot.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(program.mascotColor)
            }
        }
        .padding(.horizontal, showName ? 10 : 0)
        .padding(.vertical, showName ? 6 : 0)
        .background(
            Capsule()
                .fill(program.mascotColor.opacity(0.12))
                .opacity(showName ? 1 : 0)
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            StudentCard(student: Student.samples[0], contract: Contract.sample)
            SessionCard(session: SessionEvent.samples[0])
            ProgramCard(program: Program.samples[0], enrolledCount: 8)
            DrillCard(drill: DrillItem.samples[0])
            MinimalListRow(icon: "person.fill", title: "Profile", subtitle: "Edit your information")
            
            // Program Avatar examples
            HStack(spacing: 16) {
                ForEach(Program.samples) { program in
                    ProgramAvatarView(program: program)
                }
            }
            
            // Program Badge examples
            HStack(spacing: 12) {
                ForEach(Program.samples) { program in
                    ProgramBadge(program: program)
                }
            }
        }
        .padding()
    }
    .background(AppTheme.background)
}
