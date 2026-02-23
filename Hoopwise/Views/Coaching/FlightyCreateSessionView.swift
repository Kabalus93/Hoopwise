import SwiftUI

// MARK: - Flighty-Styled Create Session View
/// A redesigned session creation form with Flighty's dark, confident aesthetic
struct FlightyCreateSessionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let microCycle: MicroCycle
    let program: Program?
    let sessionNumber: Int
    
    @State private var title = ""
    @State private var sessionType: SessionType = .training
    @State private var date = Date()
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedLocationId: UUID? = nil
    @State private var customLocation = ""
    @State private var notes = ""
    
    // Drill selection
    @State private var selectedWarmupDrillIds: Set<UUID> = []
    @State private var selectedSkillDrillIds: Set<UUID> = []
    @State private var selectedGameDrillIds: Set<UUID> = []
    @State private var showingDrillPicker = false
    @State private var drillPickerCategory: DrillPickerCategory = .warmup
    
    enum DrillPickerCategory {
        case warmup, skills, game
        
        var title: String {
            switch self {
            case .warmup: return "Warm-up Drills"
            case .skills: return "Skill Drills"
            case .game: return "Game Drills"
            }
        }
        
        var icon: String {
            switch self {
            case .warmup: return "flame.fill"
            case .skills: return "star.fill"
            case .game: return "sportscourt.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .warmup: return .orange
            case .skills: return .purple
            case .game: return .green
            }
        }
    }
    
    init(microCycle: MicroCycle, program: Program?, sessionNumber: Int) {
        self.microCycle = microCycle
        self.program = program
        self.sessionNumber = sessionNumber
        let calendar = Calendar.current
        let startComponents = DateComponents(hour: 18, minute: 30)
        let endComponents = DateComponents(hour: 20, minute: 0)
        _startTime = State(initialValue: calendar.date(from: startComponents) ?? Date())
        _endTime = State(initialValue: calendar.date(from: endComponents) ?? Date())
    }
    
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var accentColor: Color {
        program.map { Color(hex: $0.colorHex) } ?? .blue
    }
    
    private var locationString: String? {
        if let id = selectedLocationId, let loc = dataManager.locations.first(where: { $0.id == id }) {
            return loc.name
        } else if !customLocation.isEmpty {
            return customLocation
        }
        return nil
    }
    
    private var totalDrillCount: Int {
        selectedWarmupDrillIds.count + selectedSkillDrillIds.count + selectedGameDrillIds.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    // Content
                    VStack(spacing: 20) {
                        // Session info
                        sessionInfoSection
                        
                        // Schedule
                        scheduleSection
                        
                        // Location
                        locationSection
                        
                        // Drills
                        drillsSection
                        
                        // Notes
                        notesSection
                        
                        // Hierarchy info
                        hierarchySection
                        
                        Spacer(minLength: 100)
                    }
                    .padding(20)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createSession) {
                        Text("CREATE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(isValid ? .black : .white.opacity(0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isValid ? accentColor : Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingDrillPicker) {
                FlightyDrillPickerSheet(
                    category: drillPickerCategory,
                    selectedIds: bindingForCategory(drillPickerCategory),
                    drills: dataManager.drills,
                    accentColor: accentColor
                )
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 28))
                    .foregroundColor(accentColor)
            }
            
            Text("NEW SESSION")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            if let program = program {
                HStack(spacing: 6) {
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 12))
                    Text(program.mascot.displayName)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Session Info Section
    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "SESSION INFO", icon: "info.circle")
            
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("TITLE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                
                TextField("", text: $title, prompt: Text("Enter session title...").foregroundColor(.white.opacity(0.3)))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(title.isEmpty ? Color.white.opacity(0.1) : accentColor.opacity(0.5), lineWidth: 1)
                    )
            }
            
            // Session Type - Use ScrollView for better fit
            VStack(alignment: .leading, spacing: 10) {
                Text("TYPE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                
                // Use LazyVGrid for consistent sizing
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        sessionTypeButton(type)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    private func sessionTypeButton(_ type: SessionType) -> some View {
        let isSelected = sessionType == type
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                sessionType = type
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                Text(type.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? accentColor : Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Schedule Section
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "SCHEDULE", icon: "clock")
            
            // Date row
            HStack {
                Text("DATE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .accentColor(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Time row - better aligned
            HStack(spacing: 16) {
                // Start time
                VStack(alignment: .leading, spacing: 8) {
                    Text("START")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .accentColor(accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)
                
                // Arrow
                VStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.bottom, 16)
                }
                
                // End time
                VStack(alignment: .leading, spacing: 8) {
                    Text("END")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .accentColor(accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Duration indicator
            let duration = Calendar.current.dateComponents([.minute], from: startTime, to: endTime).minute ?? 0
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                Text("DURATION: \(duration) MIN")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(16)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "LOCATION", icon: "mappin")
            
            if dataManager.locations.isEmpty {
                TextField("", text: $customLocation, prompt: Text("Enter location...").foregroundColor(.white.opacity(0.3)))
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        locationButton(id: nil, name: "None")
                        ForEach(dataManager.locations) { location in
                            locationButton(id: location.id, name: location.name)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    private func locationButton(id: UUID?, name: String) -> some View {
        let isSelected = selectedLocationId == id
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLocationId = id
            }
        }) {
            HStack(spacing: 6) {
                if id != nil {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                }
                Text(name)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? accentColor : Color.white.opacity(0.05))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Drills Section
    private var drillsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader(title: "DRILLS", icon: "figure.basketball")
                Spacer()
                if totalDrillCount > 0 {
                    Text("\(totalDrillCount) SELECTED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                }
            }
            
            VStack(spacing: 10) {
                drillCategoryRow(.warmup, selectedCount: selectedWarmupDrillIds.count)
                drillCategoryRow(.skills, selectedCount: selectedSkillDrillIds.count)
                drillCategoryRow(.game, selectedCount: selectedGameDrillIds.count)
            }
            
            if dataManager.drills.isEmpty {
                Text("Add drills in Hub → Coach to select them here")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    private func drillCategoryRow(_ category: DrillPickerCategory, selectedCount: Int) -> some View {
        Button(action: {
            drillPickerCategory = category
            showingDrillPicker = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.15))
                    .cornerRadius(10)
                
                Text(category.title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Spacer()
                
                if selectedCount > 0 {
                    Text("\(selectedCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(category.color)
                        .cornerRadius(10)
                } else {
                    Text("NONE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "NOTES", icon: "note.text")
            
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .overlay(
                    Group {
                        if notes.isEmpty {
                            Text("Add session notes...")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.3))
                                .padding(16)
                        }
                    },
                    alignment: .topLeading
                )
        }
        .padding(16)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    // MARK: - Hierarchy Section
    private var hierarchySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "LINKED TO", icon: "link")
            
            HStack(spacing: 16) {
                hierarchyItem(label: "PHASE", value: "Phase \(microCycle.phaseNumber)")
                
                if let program = program {
                    hierarchyItem(label: "PROGRAM", value: program.mascot.displayName)
                }
            }
            
            Text("This session will appear in the calendar and phase timeline")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(16)
        .background(Color(hex: "#1a1a2e"))
        .cornerRadius(16)
    }
    
    private func hierarchyItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
    
    // MARK: - Helpers
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func bindingForCategory(_ category: DrillPickerCategory) -> Binding<Set<UUID>> {
        switch category {
        case .warmup: return $selectedWarmupDrillIds
        case .skills: return $selectedSkillDrillIds
        case .game: return $selectedGameDrillIds
        }
    }
    
    private func createSession() {
        let attendeeIds = program?.enrolledStudentIds ?? []
        
        let curriculum = SessionCurriculum(
            warmupDrillIds: Array(selectedWarmupDrillIds),
            skillDrillIds: Array(selectedSkillDrillIds),
            gameDrillIds: Array(selectedGameDrillIds)
        )
        
        // Combine date with time components for correct startTime and endTime
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        let combinedStartTime = calendar.date(bySettingHour: startComponents.hour ?? 18,
                                               minute: startComponents.minute ?? 30,
                                               second: 0, of: date) ?? date
        let combinedEndTime = calendar.date(bySettingHour: endComponents.hour ?? 20,
                                             minute: endComponents.minute ?? 0,
                                             second: 0, of: date) ?? date
        
        let session = SessionEvent(
            microCycleId: microCycle.id,
            programId: program?.id,
            sessionType: sessionType,
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            startTime: combinedStartTime,
            endTime: combinedEndTime,
            location: locationString,
            curriculum: curriculum,
            attendeeIds: attendeeIds,
            notes: notes.isEmpty ? nil : notes,
            createdByCoachId: dataManager.loggedInCoachId
        )
        
        dataManager.addSessionEvent(session)
        dismiss()
    }
}

// MARK: - Flighty Drill Picker Sheet
struct FlightyDrillPickerSheet: View {
    let category: FlightyCreateSessionView.DrillPickerCategory
    @Binding var selectedIds: Set<UUID>
    let drills: [DrillItem]
    let accentColor: Color
    
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory? = nil
    @State private var selectedDifficulty: DifficultyLevel? = nil
    @State private var showFavoritesOnly = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var filteredDrills: [DrillItem] {
        var result = drills
        
        if !searchText.isEmpty {
            result = result.filter { drill in
                drill.name.localizedCaseInsensitiveContains(searchText) ||
                drill.localizedName.localizedCaseInsensitiveContains(searchText) ||
                drill.description.localizedCaseInsensitiveContains(searchText) ||
                drill.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        
        if let diff = selectedDifficulty {
            result = result.filter { $0.difficulty == diff }
        }
        
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                    
                    TextField("", text: $searchText, prompt: Text("Search drills...").foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Favorites filter
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFavoritesOnly.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                Text((isChinese ? "收藏" : "Favorites").uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(showFavoritesOnly ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(showFavoritesOnly ? Color.pink : Color.white.opacity(0.08))
                            .cornerRadius(16)
                        }
                        
                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.2))
                        
                        // Category filters
                        categoryFilterButton(nil, title: isChinese ? "全部" : "All")
                        ForEach(DrillCategory.allCases, id: \.self) { cat in
                            categoryFilterButton(cat, title: cat.localizedName)
                        }
                        
                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.2))
                        
                        // Difficulty filters
                        difficultyFilterButton(nil, title: isChinese ? "所有难度" : "Any Level")
                        ForEach(DifficultyLevel.allCases, id: \.self) { diff in
                            difficultyFilterButton(diff, title: diff.localizedName)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                // Drill list
                if filteredDrills.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty ? "figure.basketball" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.3))
                        Text(searchText.isEmpty ? "NO DRILLS AVAILABLE" : "NO DRILLS FOUND")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        if searchText.isEmpty {
                            Text("Add drills in Hub → Coach")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredDrills) { drill in
                                drillRow(drill)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .foregroundColor(category.color)
                        Text(category.title.uppercased())
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("DONE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(accentColor)
                            .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    private func categoryFilterButton(_ cat: DrillCategory?, title: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = cat
            }
        }) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? accentColor : Color.white.opacity(0.08))
                .cornerRadius(16)
        }
    }
    
    private func difficultyFilterButton(_ diff: DifficultyLevel?, title: String) -> some View {
        let isSelected = selectedDifficulty == diff
        let color: Color = {
            guard let d = diff else { return .gray }
            switch d {
            case .beginner: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }()
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDifficulty = diff
            }
        }) {
            HStack(spacing: 4) {
                if let d = diff {
                    ForEach(0..<d.stars, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                    }
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color.white.opacity(0.08))
            .cornerRadius(16)
        }
    }
    
    private func drillRow(_ drill: DrillItem) -> some View {
        let isSelected = selectedIds.contains(drill.id)
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedIds.remove(drill.id)
                } else {
                    selectedIds.insert(drill.id)
                }
            }
            HapticFeedback.impact(.light)
        }) {
            HStack(spacing: 12) {
                // Category icon
                Image(systemName: drill.category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor(drill.category))
                    .frame(width: 40, height: 40)
                    .background(categoryColor(drill.category).opacity(0.15))
                    .cornerRadius(10)
                
                // Drill info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drill.localizedName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if drill.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.pink)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(drill.category.localizedName)
                            .font(.system(size: 11, design: .monospaced))
                        
                        Text("•")
                        
                        Text("\(drill.durationMinutes) \(isChinese ? "分钟" : "min")")
                            .font(.system(size: 11, design: .monospaced))
                        
                        // Difficulty
                        HStack(spacing: 2) {
                            ForEach(0..<drill.difficulty.stars, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.2))
            }
            .padding(12)
            .background(isSelected ? accentColor.opacity(0.1) : Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    private func categoryColor(_ category: DrillCategory) -> Color {
        switch category.color {
        case "orange": return .orange
        case "blue": return .blue
        case "red": return .red
        case "purple": return .purple
        case "green": return .green
        case "yellow": return .yellow
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Preview
#Preview {
    FlightyCreateSessionView(
        microCycle: MicroCycle(
            programId: UUID(),
            phaseNumber: 1,
            title: "Foundation Phase"
        ),
        program: nil,
        sessionNumber: 1
    )
    .environmentObject(DataManager.shared)
}
