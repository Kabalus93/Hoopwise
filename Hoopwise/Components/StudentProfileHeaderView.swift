import SwiftUI

/// Baseball card-style profile view matching the Kershaw card design
struct StudentProfileHeaderView: View {
    let student: Student
    let player: Player?
    let trainingStats: TrainingSessionStats?
    @EnvironmentObject var dataManager: DataManager
    /// Pre-loaded background image. When non-nil, the header renders this
    /// directly instead of `AsyncImage`. Used by the PDF export pipeline,
    /// where the synchronous snapshot can't wait for a network round-trip.
#if os(iOS)
    var headerImageOverride: UIImage? = nil
    var profileImageOverride: UIImage? = nil
#else
    var headerImageOverride: NSImage? = nil
    var profileImageOverride: NSImage? = nil
#endif

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    // Card colors
    private let cardBackground = AppTheme.cream // Cream/tan color like the card
    private let cardBorder = AppTheme.saddleBrown // Brown border
    private let statLabelColor = AppTheme.neutral600
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Section (Blurred background with name)
            topSection
            
            // MARK: - Middle Section (Profile photo + basic info)
            middleSection
            
            // MARK: - Season Label
            seasonLabel
            
            // MARK: - Stats Grid (PPG, APG, RBG, STL, BLK, Effort)
            statsGrid
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorder, lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    
    // MARK: - Top Section
    private var topSection: some View {
        ZStack {
            // Background: the athlete's own colour with court lines drawn
            // here — no third-party stock photography (App Review 4.1(a),
            // October 2026). A pre-loaded override still wins.
            backgroundLayer
                .frame(height: 160)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.5), .black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Name and number overlay
            VStack(spacing: 4) {
                if student.secondaryDisplayName != nil {
                    let chinese = student.primaryDisplayName
                    // Chinese mode: PinYin small on top, Chinese name large below
                    Text(student.name.uppercased())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(1)
                    
                    Text(chinese)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    // English mode - show name, with Chinese name below if available
                    Text(student.name.uppercased())
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    // Show Chinese name in smaller text below
                    if let chinese = student.secondaryNameLine {
                        Text(chinese)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60) // Leave room for jersey number
            .padding(.top, 20)
            
            // Jersey number badge (top right)
            if let jerseyNumber = player?.jerseyNumber {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 2)
                                .frame(width: 44, height: 44)
                            Text("\(jerseyNumber)")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 160)
    }
    
    // MARK: - Middle Section
    /// Resolves the header background: a pre-loaded override, else
    /// `CardCourtBackground` in the athlete's colour.
    @ViewBuilder
    private var backgroundLayer: some View {
        if let pre = headerImageOverride {
            #if os(iOS)
            Image(uiImage: pre)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 4)
            #else
            Image(nsImage: pre)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 4)
            #endif
        } else {
            CardCourtBackground(color: Color.avatarColor(student.avatarColor))
        }
    }

    private var middleSection: some View {
        ZStack {
            // Profile photo (center, overlapping top section)
            profilePhoto
                .offset(y: -40)
            
            // Side elements with equal widths
            HStack(alignment: .bottom, spacing: 0) {
                // Position badge (left side) - fixed width
                positionBadge
                    .frame(width: 80, alignment: .leading)
                    .padding(.leading, 16)
                
                Spacer()
                
                // Basic stats (right side) - fixed width to match left
                basicStats
                    .frame(width: 80, alignment: .trailing)
                    .padding(.trailing, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    private var positionBadge: some View {
        VStack(spacing: 4) {
            // Performance grade diamond shape
            ZStack {
                Rectangle()
                    .fill(.white)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(45))
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .rotationEffect(.degrees(45))
                    )
                
                Text(effectiveGrade.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(gradeColor)
            }
            .frame(width: 60, height: 60)
        }
    }
    
    /// Get effective performance grade (manual override or auto-computed)
    private var effectiveGrade: PerformanceGrade {
        if let override = student.performanceGrade {
            return override
        }
        let allStudents = dataManager.students
        let sessions = dataManager.sessionEvents
        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: allStudents,
            sessions: sessions,
            skills: skills
        )
    }
    
    /// Color for the performance grade
    private var gradeColor: Color {
        switch effectiveGrade {
        case .A: return Color(red: 0.85, green: 0.65, blue: 0.0)  // Gold
        case .B: return Color(red: 0.5, green: 0.5, blue: 0.5)  // Silver
        case .C: return Color(red: 0.6, green: 0.4, blue: 0.2)  // Bronze
        case .ungraded: return .black
        }
    }
    
    private var profilePhoto: some View {
        StudentAvatarView(student: student, size: 100, imageOverride: profileImageOverride)
            .overlay(
                Circle()
                    .stroke(cardBorder, lineWidth: 3)
            )
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 106, height: 106)
            )
    }
    
    private var basicStats: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Age
            statRow(label: isChinese ? "年龄" : "AGE", value: student.age != nil ? "\(student.age!)" : "—")
            
            // Height
            statRow(label: isChinese ? "身高" : "HT", value: heightString)
            
            // Handedness
            statRow(label: isChinese ? "手" : "HAND", value: player?.handedness.shortName ?? "—")
        }
    }
    
    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statLabelColor)
                .frame(width: 38, alignment: .trailing)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 32, alignment: .leading)
                .lineLimit(1)
        }
    }
    
    private var heightString: String {
        guard let height = player?.heightCm else { return "—" }
        let feet = Int(height / 30.48)
        let inches = Int((height / 2.54).truncatingRemainder(dividingBy: 12))
        return "\(feet)'\(inches)\""
    }
    
    // MARK: - Member Since Label
    private var seasonLabel: some View {
        Text(memberSinceText)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
            .padding(.vertical, 8)
    }
    
    private var memberSinceText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: student.createdAt)
        return isChinese ? "自 \(year)" : "SINCE \(year)"
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        let stats = trainingStats
        
        return VStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            // Row 1: PPG, APG, RPG
            HStack(spacing: 0) {
                statCell(value: formatStat(stats?.ppg), label: isChinese ? "得分" : "PPG")
                verticalDivider
                statCell(value: formatStat(stats?.apg), label: isChinese ? "助攻" : "APG")
                verticalDivider
                statCell(value: formatStat(stats?.rpg), label: isChinese ? "篮板" : "RPG")
            }
            .frame(height: 70)
            
            // Divider line
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            // Row 2: STL, BLK, Effort
            HStack(spacing: 0) {
                statCell(value: formatStat(stats?.spg), label: isChinese ? "抢断" : "STL")
                verticalDivider
                statCell(value: formatStat(stats?.bpg), label: isChinese ? "盖帽" : "BLK")
                verticalDivider
                statCell(value: effortString(stats), label: isChinese ? "努力" : "EFRT")
            }
            .frame(height: 70)
        }
        .padding(.bottom, 8)
    }
    
    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1)
    }
    
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statLabelColor)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatStat(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        if value == 0 { return "0.0" }
        return String(format: "%.1f", value)
    }
    
    private func effortString(_ stats: TrainingSessionStats?) -> String {
        guard let stats = stats, stats.hasStats else { return "—" }
        return String(format: "%.1f", stats.efrt)
    }
    
}


#Preview {
    StudentProfileHeaderView(
        student: Student.samples.first!,
        player: nil,
        trainingStats: nil
    )
    .environmentObject(DataManager.shared)
    .padding()
    .background(Color.gray.opacity(0.2))
}

/// The card header's background: a deep gradient in `color` with a half
/// court drawn over it in thin white lines. Original artwork, drawn in code.
struct CardCourtBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [color, color.opacity(0.75), .black.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let w = size.width, h = size.height
                var court = Path()
                // Free-throw lane and circle, three-point arc, from the bottom edge.
                let laneW = w * 0.22, laneH = h * 0.62
                court.addRect(CGRect(x: w / 2 - laneW / 2, y: h - laneH, width: laneW, height: laneH))
                court.addEllipse(in: CGRect(x: w / 2 - laneW / 2, y: h - laneH - laneW / 2, width: laneW, height: laneW))
                court.addArc(center: CGPoint(x: w / 2, y: h), radius: w * 0.42,
                             startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                court.addArc(center: CGPoint(x: w / 2, y: h - h * 0.12), radius: w * 0.03,
                             startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                ctx.stroke(court, with: .color(.white.opacity(0.16)), lineWidth: 2)
            }
        }
    }
}

