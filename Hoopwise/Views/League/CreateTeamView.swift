import SwiftUI

// MARK: - Team Preset
/// Predefined team templates inspired by Chinese wildlife and nature
struct TeamPreset: Identifiable {
    let id = UUID()
    let mascot: TeamMascotType
    
    var name: String { mascot.fullName }
    var shortName: String { mascot.shortName }
    var colorHex: String { mascot.primaryColorHex }
    var secondaryColorHex: String { mascot.secondaryColorHex }
    var accentColorHex: String { mascot.accentColorHex }
    
    // Fallback SF Symbol for when mascot logo isn't used
    var icon: String { mascot.fallbackIcon }
    
    static let presets: [TeamPreset] = TeamMascotType.allCases.map { TeamPreset(mascot: $0) }
}

struct CreateTeamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName = ""
    @State private var shortName = ""
    @State private var selectedColor = "#E94560"
    @State private var selectedSecondaryColor = "#1A1A2E"
    @State private var selectedIcon = "basketball.fill"
    @State private var selectedPlayerIds: Set<UUID> = []
    @State private var selectedPreset: TeamPreset? = nil
    @State private var venue = ""
    @State private var coachName = ""
    
    let teamColors: [String] = [
        "#E94560", "#7C3AED", "#3B82F6", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#06B6D4", "#84CC16",
        "#1F2937", "#78716C", "#B45309", "#CA8A04", "#DC2626"
    ]
    
    let teamIcons: [String] = [
        "basketball.fill", "flame.fill", "bird.fill", "cat.fill",
        "dog.fill", "bolt.fill", "star.fill", "crown.fill",
        "shield.fill", "trophy.fill", "pawprint.fill", "leaf.fill",
        "moon.fill", "snowflake", "wind", "mountain.2.fill",
        "water.waves", "sparkles", "cloud.fill", "drop.fill"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Team Preview
                    teamPreview
                    
                    // Team Presets
                    teamPresetsSection
                    
                    // Team Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Team Info")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        VStack(spacing: 12) {
                            TextField("Team Name", text: $teamName)
                                .textFieldStyle(.plain)
                                .padding(14)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            
                            TextField("Short Name (3 letters)", text: $shortName)
                                .textFieldStyle(.plain)
                                .textCase(.uppercase)
                                .onChange(of: shortName) { _, newValue in
                                    shortName = String(newValue.uppercased().prefix(3))
                                }
                                .padding(14)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            
                            // Venue Picker (from Organization locations)
                            if !dataManager.locations.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Home Venue")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(dataManager.locations.filter { $0.isActive }) { location in
                                                Button(action: { venue = location.name }) {
                                                    Text(location.name)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(venue == location.name ? .white : AppTheme.textSecondary)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 8)
                                                        .background(venue == location.name ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                        .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                TextField("Home Venue (optional)", text: $venue)
                                    .textFieldStyle(.plain)
                                    .padding(14)
                                    .background(AppTheme.surfaceColor)
                                    .cornerRadius(12)
                            }
                            
                            // Coach Picker (from Organization staff)
                            if !dataManager.staffCoaches.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Coach")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                                                Button(action: { coachName = coach.name }) {
                                                    HStack(spacing: 6) {
                                                        ZStack {
                                                            Circle()
                                                                .fill(Color.avatarColor(coach.avatarColor))
                                                                .frame(width: 24, height: 24)
                                                            Text(coach.initials)
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(.white)
                                                        }
                                                        Text(coach.name)
                                                            .font(.system(size: 13, weight: .medium))
                                                    }
                                                    .foregroundColor(coachName == coach.name ? .white : AppTheme.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(coachName == coach.name ? AppTheme.accentColor : AppTheme.surfaceColor)
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                TextField("Coach Name", text: $coachName)
                                    .textFieldStyle(.plain)
                                    .padding(14)
                                    .background(AppTheme.surfaceColor)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Team Color
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team Color")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(teamColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                                    .shadow(color: selectedColor == color ? Color(hex: color).opacity(0.5) : .clear, radius: 8)
                                    .onTapGesture { selectedColor = color }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Team Icon
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team Icon")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(teamIcons, id: \.self) { icon in
                                ZStack {
                                    Circle()
                                        .fill(selectedIcon == icon ? Color(hex: selectedColor) : AppTheme.surfaceColor)
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(selectedIcon == icon ? .white : AppTheme.textSecondary)
                                }
                                .onTapGesture { selectedIcon = icon }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Select Players - Flashy Inline Selection
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Roster")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            Spacer()
                            
                            if !selectedPlayerIds.isEmpty {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedPlayerIds.removeAll()
                                    }
                                    HapticFeedback.impact(.light)
                                }) {
                                    Text("Clear All")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                            }
                        }
                        
                        // Selected players preview with stacked avatars
                        if !selectedPlayerIds.isEmpty {
                            VStack(spacing: 10) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: -10) {
                                        ForEach(Array(selectedPlayerIds.prefix(10)), id: \.self) { playerId in
                                            if let student = dataManager.students.first(where: { $0.id == playerId }) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(hex: selectedColor).opacity(0.3))
                                                        .frame(width: 48, height: 48)
                                                        .blur(radius: 4)
                                                    
                                                    Circle()
                                                        .fill(Color.avatarColor(student.avatarColor))
                                                        .frame(width: 40, height: 40)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color(hex: selectedColor), lineWidth: 2)
                                                        )
                                                    
                                                    Text(student.initials)
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                                .transition(.scale.combined(with: .opacity))
                                            }
                                        }
                                        
                                        if selectedPlayerIds.count > 10 {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: selectedColor).opacity(0.2))
                                                    .frame(width: 40, height: 40)
                                                Text("+\(selectedPlayerIds.count - 10)")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(Color(hex: selectedColor))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                                
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: selectedColor))
                                    Text("\(selectedPlayerIds.count) player\(selectedPlayerIds.count == 1 ? "" : "s") on roster")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: selectedColor))
                                    Spacer()
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: selectedColor).opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color(hex: selectedColor).opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Player selection grid
                        if dataManager.accessibleStudents.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No students available")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text("Add students in the Hub first")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(dataManager.accessibleStudents) { student in
                                    FlashyiOSPlayerCard(
                                        student: student,
                                        isSelected: selectedPlayerIds.contains(student.id),
                                        teamColor: Color(hex: selectedColor)
                                    ) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            if selectedPlayerIds.contains(student.id) {
                                                selectedPlayerIds.remove(student.id)
                                            } else {
                                                selectedPlayerIds.insert(student.id)
                                            }
                                        }
                                        HapticFeedback.impact(.light)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(AppTheme.background)
            .navigationTitle("Create Team")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTeam()
                    }
                    .fontWeight(.semibold)
                    .disabled(teamName.isEmpty || shortName.count < 2)
                }
            }
        }
    }
    
    private var teamPreview: some View {
        VStack(spacing: 16) {
            // Show mascot logo if preset selected, otherwise show SF Symbol
            if let mascot = selectedPreset?.mascot {
                TeamMascotLogo(mascot: mascot, size: 80, showGlow: true)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: selectedColor), Color(hex: selectedColor).opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: selectedIcon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(spacing: 4) {
                Text(teamName.isEmpty ? "Team Name" : teamName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(teamName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                
                Text(shortName.isEmpty ? "ABC" : shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                if !coachName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(coachName)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(AppTheme.textTertiary)
                }
            }
        }
        .padding(.vertical, 24)
    }
    
    // MARK: - Team Presets Section
    private var teamPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Select")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                if selectedPreset != nil {
                    Button(action: clearPreset) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(TeamPreset.presets) { preset in
                        TeamPresetCard(
                            preset: preset,
                            isSelected: selectedPreset?.name == preset.name,
                            action: { selectPreset(preset) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func selectPreset(_ preset: TeamPreset) {
        withAnimation(.spring(response: 0.3)) {
            selectedPreset = preset
            teamName = preset.name
            shortName = preset.shortName
            selectedColor = preset.colorHex
            selectedSecondaryColor = preset.secondaryColorHex
            selectedIcon = preset.icon
        }
        
        // Haptic feedback
        HapticFeedback.impact(.light)
    }
    
    private func clearPreset() {
        withAnimation(.spring(response: 0.3)) {
            selectedPreset = nil
            teamName = ""
            shortName = ""
            selectedColor = "#E94560"
            selectedSecondaryColor = "#1A1A2E"
            selectedIcon = "basketball.fill"
        }
    }
    
    private func createTeam() {
        var team = Team(
            name: teamName,
            shortName: shortName,
            colorHex: selectedColor,
            secondaryColorHex: selectedSecondaryColor,
            logoSystemImage: selectedIcon,
            playerIds: Array(selectedPlayerIds),
            coachId: dataManager.loggedInCoachId,
            coachName: coachName.isEmpty ? nil : coachName,
            homeVenue: venue.isEmpty ? nil : venue,
            createdByCoachId: dataManager.loggedInCoachId
        )
        
        // Save mascot type from preset if selected
        if let mascot = selectedPreset?.mascot {
            team.mascotTypeRaw = mascot.rawValue
        }
        
        dataManager.addTeam(team)
        dismiss()
    }
}

// MARK: - Team Preset Card
struct TeamPresetCard: View {
    let preset: TeamPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Custom Mascot Logo
                TeamMascotLogo(
                    mascot: preset.mascot,
                    size: 58,
                    showGlow: isSelected
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.9), Color.white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 3 : 0
                        )
                        .frame(width: 60, height: 60)
                )
                
                // Name with accent
                VStack(spacing: 2) {
                    Text(preset.mascot.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? Color(hex: preset.colorHex) : AppTheme.textSecondary)
                        .lineLimit(1)
                    
                    Text(preset.shortName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(hex: preset.colorHex).opacity(isSelected ? 0.2 : 0.1))
                        )
                }
            }
            .frame(width: 82)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color(hex: preset.colorHex).opacity(0.08) : AppTheme.surfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color(hex: preset.colorHex).opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Player Selection Row (Legacy)
struct TeamPlayerSelectionRow: View {
    let student: Student
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Language-aware name display
                    if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.chineseName!)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(student.name)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    } else {
                        Text(student.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    
                    if let age = student.age {
                        Text("\(age) years old")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textTertiary)
            }
            .padding(12)
            .background(isSelected ? AppTheme.accentColor.opacity(0.1) : AppTheme.surfaceColor)
            .cornerRadius(12)
        }
    }
}

// MARK: - Flashy iOS Player Card
/// Premium player selection card with glow effects and spring animations for iOS
struct FlashyiOSPlayerCard: View {
    let student: Student
    let isSelected: Bool
    let teamColor: Color
    let action: () -> Void
    
    @State private var isPressing = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Avatar with glow effect when selected
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(teamColor.opacity(0.4))
                            .frame(width: 52, height: 52)
                            .blur(radius: 6)
                    }
                    
                    Circle()
                        .fill(Color.avatarColor(student.avatarColor))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? teamColor : Color.clear, lineWidth: 2.5)
                        )
                        .shadow(color: isSelected ? teamColor.opacity(0.3) : Color.clear, radius: 8)
                    
                    Text(student.initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Name and details - language-aware
                VStack(alignment: .leading, spacing: 3) {
                    if LocalizationManager.shared.currentLanguage == .chinese && student.chineseName != nil {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.chineseName!)
                                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                            Text(student.name)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    } else {
                        Text(student.name)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? teamColor : AppTheme.textPrimary)
                    }
                    
                    HStack(spacing: 8) {
                        if let age = student.age {
                            Text("\(age) years")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        // Only show Chinese name in English mode
                        if LocalizationManager.shared.currentLanguage != .chinese, let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                // Animated selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? teamColor : Color.clear)
                        .frame(width: 26, height: 26)
                    
                    Circle()
                        .stroke(isSelected ? teamColor : AppTheme.textTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? teamColor.opacity(0.1) : AppTheme.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? teamColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
            )
            .shadow(color: isSelected ? teamColor.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isPressing ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressing = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressing = false
                    }
                }
        )
    }
}

#Preview {
    CreateTeamView()
        .environmentObject(DataManager.shared)
}
