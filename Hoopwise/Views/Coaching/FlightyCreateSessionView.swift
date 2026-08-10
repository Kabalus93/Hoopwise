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
    @State private var selectedCoachId: UUID? = nil
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
        // Default coach to the logged-in coach
        _selectedCoachId = State(initialValue: DataManager.shared.loggedInCoachId)
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
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var phaseLabel: String {
        let cycleTitle = microCycle.title.trimmingCharacters(in: .whitespaces)
        if !cycleTitle.isEmpty {
            return cycleTitle
        }
        return isChinese ? "阶段 \(microCycle.phaseNumber)" : "Phase \(microCycle.phaseNumber)"
    }

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                scheduleSection
                locationSection
                coachSection
                drillsSection
                notesSection
                linkedToSection
            }
            .navigationTitle(isChinese ? "新建课程" : "New Session")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create", action: createSession)
                        .fontWeight(.semibold)
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

    // MARK: - Sections

    private var infoSection: some View {
        Section {
            TextField(isChinese ? "课程标题" : "Title", text: $title)

            Picker(isChinese ? "类型" : "Type", selection: $sessionType) {
                ForEach(SessionType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
        } header: {
            Text(isChinese ? "课程信息" : "Session Info")
        }
    }

    private var scheduleSection: some View {
        Section {
            DatePicker(isChinese ? "日期" : "Date",
                       selection: $date,
                       displayedComponents: .date)
            DatePicker(isChinese ? "开始" : "Start",
                       selection: $startTime,
                       displayedComponents: .hourAndMinute)
            DatePicker(isChinese ? "结束" : "End",
                       selection: $endTime,
                       displayedComponents: .hourAndMinute)
        } header: {
            Text(isChinese ? "时间" : "Schedule")
        } footer: {
            let duration = Calendar.current.dateComponents([.minute], from: startTime, to: endTime).minute ?? 0
            Text(isChinese ? "时长 \(duration) 分钟" : "\(duration) minutes")
        }
    }

    private var locationSection: some View {
        Section {
            if dataManager.locations.isEmpty {
                Label(isChinese ? "尚未添加场地" : "No locations added yet",
                      systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            } else {
                Picker(isChinese ? "场地" : "Location", selection: $selectedLocationId) {
                    Text(isChinese ? "无" : "None").tag(UUID?.none)
                    ForEach(dataManager.locations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
                    }
                }
            }
        } header: {
            Text(isChinese ? "场地" : "Location")
        }
    }

    private var coachSection: some View {
        Section {
            let coaches = dataManager.activeStaffCoaches
            if coaches.isEmpty {
                Label(isChinese ? "尚未添加教练" : "No coaches added yet",
                      systemImage: "person.slash")
                    .foregroundStyle(.secondary)
            } else {
                Picker(isChinese ? "教练" : "Coach", selection: $selectedCoachId) {
                    Text(isChinese ? "未指定" : "Unassigned").tag(UUID?.none)
                    ForEach(coaches) { coach in
                        Text(coachMenuLabel(coach)).tag(UUID?.some(coach.id))
                    }
                }
            }
        } header: {
            Text(isChinese ? "教练" : "Coach")
        }
    }

    private func coachMenuLabel(_ coach: StaffCoach) -> String {
        if coach.id == dataManager.loggedInCoachId {
            return isChinese ? "\(coach.displayName)（你）" : "\(coach.displayName) (You)"
        }
        return coach.displayName
    }

    private var drillsSection: some View {
        Section {
            drillCategoryRow(.warmup, selectedCount: selectedWarmupDrillIds.count)
            drillCategoryRow(.skills, selectedCount: selectedSkillDrillIds.count)
            drillCategoryRow(.game, selectedCount: selectedGameDrillIds.count)
        } header: {
            HStack {
                Text(isChinese ? "训练内容" : "Drills")
                Spacer()
                if totalDrillCount > 0 {
                    Text(isChinese ? "已选 \(totalDrillCount) 项" : "\(totalDrillCount) selected")
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        } footer: {
            if dataManager.drills.isEmpty {
                Text(isChinese
                     ? "在「中心 → 教练」中添加训练后即可在此选择。"
                     : "Add drills in Hub → Coach to select them here.")
            }
        }
    }

    private func drillCategoryRow(_ category: DrillPickerCategory, selectedCount: Int) -> some View {
        Button {
            drillPickerCategory = category
            showingDrillPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.color.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: category.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(category.color)
                }

                Text(localizedDrillCategory(category))
                    .foregroundStyle(.primary)

                Spacer()

                if selectedCount > 0 {
                    Text("\(selectedCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(category.color, in: Capsule())
                } else {
                    Text(isChinese ? "未选" : "None")
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func localizedDrillCategory(_ category: DrillPickerCategory) -> String {
        guard isChinese else { return category.title }
        switch category {
        case .warmup: return "热身"
        case .skills: return "技术"
        case .game:   return "比赛"
        }
    }

    private var notesSection: some View {
        Section {
            TextField(isChinese ? "添加课程备注…" : "Add session notes…",
                      text: $notes,
                      axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text(isChinese ? "备注" : "Notes")
        }
    }

    private var linkedToSection: some View {
        Section {
            HStack {
                Label(isChinese ? "阶段" : "Phase", systemImage: "square.stack.3d.up.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(phaseLabel)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if let program {
                HStack {
                    Label(isChinese ? "训练计划" : "Program", systemImage: program.mascot.icon)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(program.displayName)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text(isChinese ? "归属" : "Linked To")
        } footer: {
            Text(isChinese
                 ? "课程会出现在日历与阶段时间轴中。"
                 : "This session will appear in the calendar and phase timeline.")
        }
    }

    // MARK: - Helpers

    private func bindingForCategory(_ category: DrillPickerCategory) -> Binding<Set<UUID>> {
        switch category {
        case .warmup: return $selectedWarmupDrillIds
        case .skills: return $selectedSkillDrillIds
        case .game: return $selectedGameDrillIds
        }
    }
    
    private func createSession() {
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
        
        // The phase is explicit: this sheet is opened from inside one, and a
        // plan is allowed to carry no dates for derivation to work from.
        dataManager.createSession(SessionCreation.Intent(
            group: .program(program?.id ?? microCycle.programId),
            sessionType: sessionType,
            start: combinedStartTime,
            durationMinutes: Int(combinedEndTime.timeIntervalSince(combinedStartTime) / 60),
            title: title.trimmingCharacters(in: .whitespaces),
            location: locationString,
            phase: microCycle.id,
            notes: notes.isEmpty ? nil : notes,
            curriculum: curriculum,
            createdByCoachId: selectedCoachId ?? dataManager.loggedInCoachId))
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
    
    private var localizedCategoryTitle: String {
        guard isChinese else { return category.title }
        switch category {
        case .warmup: return "热身训练"
        case .skills: return "技术训练"
        case .game:   return "比赛训练"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.top, 4)

                if filteredDrills.isEmpty {
                    ContentUnavailableView {
                        Label(
                            searchText.isEmpty
                                ? (isChinese ? "暂无训练" : "No Drills Available")
                                : (isChinese ? "未找到匹配" : "No Matching Drills"),
                            systemImage: searchText.isEmpty ? "figure.basketball" : "magnifyingglass"
                        )
                    } description: {
                        if searchText.isEmpty {
                            Text(isChinese ? "在「中心 → 教练」中添加训练。" : "Add drills in Hub → Coach.")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredDrills) { drill in
                            drillRow(drill)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(isChinese ? "搜索训练" : "Search drills"))
            .navigationTitle(localizedCategoryTitle)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFavoritesOnly.toggle()
                    }
                } label: {
                    Label(isChinese ? "收藏" : "Favorites", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(showFavoritesOnly ? .pink : .secondary)

                Divider().frame(height: 18)

                categoryFilterButton(nil, title: isChinese ? "全部" : "All")
                ForEach(DrillCategory.allCases, id: \.self) { cat in
                    categoryFilterButton(cat, title: cat.localizedName)
                }

                Divider().frame(height: 18)

                difficultyFilterButton(nil, title: isChinese ? "所有难度" : "Any Level")
                ForEach(DifficultyLevel.allCases, id: \.self) { diff in
                    difficultyFilterButton(diff, title: diff.localizedName)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func categoryFilterButton(_ cat: DrillCategory?, title: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = cat
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isSelected ? accentColor : .secondary)
    }

    private func difficultyFilterButton(_ diff: DifficultyLevel?, title: String) -> some View {
        let isSelected = selectedDifficulty == diff
        let color: Color = {
            guard let d = diff else { return .secondary }
            switch d {
            case .beginner: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDifficulty = diff
            }
        } label: {
            HStack(spacing: 4) {
                if let d = diff {
                    ForEach(0..<d.stars, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                    }
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isSelected ? color : .secondary)
    }

    private func drillRow(_ drill: DrillItem) -> some View {
        let isSelected = selectedIds.contains(drill.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedIds.remove(drill.id)
                } else {
                    selectedIds.insert(drill.id)
                }
            }
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor(drill.category).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: drill.category.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(categoryColor(drill.category))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(drill.localizedName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if drill.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.pink)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(drill.category.localizedName)
                        Text("·")
                        Text(isChinese ? "\(drill.durationMinutes) 分钟" : "\(drill.durationMinutes) min")
                        if drill.difficulty.stars > 0 {
                            Text("·")
                            HStack(spacing: 1) {
                                ForEach(0..<drill.difficulty.stars, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : Color(.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? accentColor.opacity(0.08) : nil)
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
