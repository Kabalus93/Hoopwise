import SwiftUI

#if os(macOS)
// MARK: - Mac Coach Resources View (Finder Column Style)
/// Redesigned coach resources with Finder-style column navigation and Lab integration
struct MacCoachResourcesView: View {
    @EnvironmentObject var dataManager: DataManager
    
    @State private var selectedTab: CoachResourceTab = .drills
    @State private var selectedDrill: DrillItem?
    @State private var selectedScheme: CourtScheme?
    @State private var showingAddDrill = false
    @State private var showingLab = false
    @State private var editingScheme: CourtScheme?
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory?
    @State private var enlargedFrame: CourtFrame?
    
    // Multi-select state
    @State private var isMultiSelectMode = false
    @State private var selectedDrillIDs: Set<UUID> = []
    @State private var showingBulkDeleteAlert = false
    
    enum CoachResourceTab: String, CaseIterable {
        case drills = "Drills"
        case schemes = "Schemes"
        case playbook = "Playbook"
        
        var icon: String {
            switch self {
            case .drills: return "figure.basketball"
            case .schemes: return "sportscourt"
            case .playbook: return "book.closed"
            }
        }
        
        var localizedName: String {
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .drills: return isChinese ? "训练" : "Drills"
            case .schemes: return isChinese ? "战术" : "Schemes"
            case .playbook: return isChinese ? "战术手册" : "Playbook"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            resourcesHeader
            
            Divider()
            
            // Main content - Finder column style
            HStack(spacing: 0) {
                switch selectedTab {
                case .drills:
                    drillsColumnView
                case .schemes:
                    schemesColumnView
                case .playbook:
                    playbookColumnView
                }
            }
        }
        .sheet(isPresented: $showingAddDrill) {
            AddEditDrillSheet(drill: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $editingScheme) { scheme in
            BasketballCourtLabView(
                scheme: Binding(
                    get: { scheme },
                    set: { editingScheme = $0 }
                ),
                onSave: { updatedScheme in
                    if dataManager.courtSchemes.contains(where: { $0.id == updatedScheme.id }) {
                        dataManager.updateCourtScheme(updatedScheme)
                    } else {
                        dataManager.addCourtScheme(updatedScheme)
                    }
                    editingScheme = nil
                }
            )
            .environmentObject(dataManager)
            .frame(minWidth: 1000, minHeight: 700)
        }
        .sheet(item: $enlargedFrame) { frame in
            EnlargedFrameView(frame: frame, onDismiss: { enlargedFrame = nil })
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除 \(selectedDrillIDs.count) 个训练？" : "Delete \(selectedDrillIDs.count) Drills?", isPresented: $showingBulkDeleteAlert) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) {
                bulkDeleteDrills()
            }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "此操作无法撤销。所有选中的训练将被永久删除。" : "This action cannot be undone. All selected drills will be permanently deleted.")
        }
    }
    
    // MARK: - Bulk Delete Function
    private func bulkDeleteDrills() {
        for drillID in selectedDrillIDs {
            if let drill = dataManager.drills.first(where: { $0.id == drillID }) {
                dataManager.deleteDrill(drill)
            }
        }
        selectedDrillIDs.removeAll()
        isMultiSelectMode = false
        selectedDrill = nil
    }
    
    // MARK: - Header (Flighty Style)
    private var resourcesHeader: some View {
        HStack {
            // Tab selector - pill style
            HStack(spacing: 4) {
                ForEach(CoachResourceTab.allCases, id: \.self) { tab in
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                            selectedDrill = nil
                            selectedScheme = nil
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.localizedName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedTab == tab ? Color.orange : Color.gray.opacity(0.08))
                        .foregroundColor(selectedTab == tab ? .white : .gray)
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Search - frosted glass style
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 10))
                TextField(LocalizationManager.shared.currentLanguage == .chinese ? "搜索..." : "Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            .frame(width: 160)
            
            // Actions
            if selectedTab == .drills {
                // Multi-select toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isMultiSelectMode.toggle()
                        if !isMultiSelectMode {
                            selectedDrillIDs.removeAll()
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isMultiSelectMode ? "xmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 9))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? (isMultiSelectMode ? "取消" : "选择") : (isMultiSelectMode ? "Cancel" : "Select"))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(isMultiSelectMode ? .red : .gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isMultiSelectMode ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // Bulk delete button (only in multi-select mode)
                if isMultiSelectMode && !selectedDrillIDs.isEmpty {
                    Button(action: { showingBulkDeleteAlert = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "删除 (\(selectedDrillIDs.count))" : "Delete (\(selectedDrillIDs.count))")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: { showingAddDrill = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加训练" : "Add Drill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isMultiSelectMode)
                .opacity(isMultiSelectMode ? 0.5 : 1)
            } else if selectedTab == .schemes {
                Button(action: { 
                    editingScheme = CourtScheme(name: "New Scheme")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "新建战术" : "New Scheme")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "#f5f5f7"))
    }
    
    // MARK: - Drills Column View
    private var drillsColumnView: some View {
        HStack(spacing: 0) {
            // Column 1: Categories
            drillCategoriesColumn
            
            Divider()
            
            // Column 2: Drills list
            drillsListColumn
            
            // Column 3: Drill detail (when selected)
            if let drill = selectedDrill {
                Divider()
                drillDetailColumn(drill)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedDrill?.id)
    }
    
    private var drillCategoriesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "分类" : "Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            Divider()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    // All drills
                    categoryRow(nil, title: LocalizationManager.shared.currentLanguage == .chinese ? "全部训练" : "All Drills", icon: "tray.full", count: filteredDrills.count)
                    
                    Divider()
                        .padding(.vertical, 6)
                    
                    ForEach(DrillCategory.allCases, id: \.self) { category in
                        let count = filteredDrills.filter { $0.category == category }.count
                        categoryRow(category, title: category.displayName, icon: category.icon, count: count)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 160)
        .background(Color(hex: "#f5f5f7").opacity(0.5))
    }
    
    private func categoryRow(_ category: DrillCategory?, title: String, icon: String, count: Int) -> some View {
        Button(action: { 
            withAnimation { selectedCategory = category }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(selectedCategory == category ? .white : categoryColor(category))
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selectedCategory == category ? .white : .black)
                
                Spacer()
                
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(selectedCategory == category ? .white.opacity(0.8) : .gray)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(selectedCategory == category ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedCategory == category ? Color.orange : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func categoryColor(_ category: DrillCategory?) -> Color {
        guard let category = category else { return .gray }
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
    
    private var filteredDrills: [DrillItem] {
        var drills = dataManager.drills
        
        if !searchText.isEmpty {
            drills = drills.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let category = selectedCategory {
            drills = drills.filter { $0.category == category }
        }
        
        return drills.sorted { $0.name < $1.name }
    }
    
    private var drillsListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(selectedCategory?.displayName ?? "All Drills")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                // Select All / Deselect All in multi-select mode
                if isMultiSelectMode && !filteredDrills.isEmpty {
                    Button(action: {
                        if selectedDrillIDs.count == filteredDrills.count {
                            selectedDrillIDs.removeAll()
                        } else {
                            selectedDrillIDs = Set(filteredDrills.map { $0.id })
                        }
                    }) {
                        Text(selectedDrillIDs.count == filteredDrills.count ? "Deselect All" : "Select All")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("\(filteredDrills.count) drills")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            // Selection count bar
            if isMultiSelectMode && !selectedDrillIDs.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text("\(selectedDrillIDs.count) selected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
            }
            
            Divider()
            
            if filteredDrills.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.basketball")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No Drills")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Button(action: { showingAddDrill = true }) {
                        Text("Add Drill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.orange)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredDrills) { drill in
                            drillRow(drill)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 240, maxWidth: selectedDrill != nil ? 240 : .infinity)
        .background(Color(hex: "#f5f5f7").opacity(0.3))
    }
    
    private func drillRow(_ drill: DrillItem) -> some View {
        let schemes = dataManager.schemesForDrill(drill.id)
        let isSelected = selectedDrill?.id == drill.id
        let isChecked = selectedDrillIDs.contains(drill.id)
        
        return Button(action: {
            if isMultiSelectMode {
                // Toggle selection in multi-select mode
                withAnimation(.spring(response: 0.2)) {
                    if isChecked {
                        selectedDrillIDs.remove(drill.id)
                    } else {
                        selectedDrillIDs.insert(drill.id)
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedDrill = drill
                }
            }
        }) {
            HStack(spacing: 8) {
                // Checkbox in multi-select mode
                if isMultiSelectMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(isChecked ? .orange : .gray.opacity(0.4))
                        .animation(.spring(response: 0.2), value: isChecked)
                }
                
                // Category icon
                Image(systemName: drill.category.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected && !isMultiSelectMode ? .white : categoryColor(drill.category))
                    .frame(width: 24, height: 24)
                    .background(isSelected && !isMultiSelectMode ? Color.white.opacity(0.2) : categoryColor(drill.category).opacity(0.1))
                    .cornerRadius(5)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(drill.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isSelected && !isMultiSelectMode ? .white : .black)
                            .lineLimit(1)
                        
                        if drill.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.yellow)
                        }
                        
                        if !schemes.isEmpty {
                            HStack(spacing: 1) {
                                Image(systemName: "sportscourt")
                                    .font(.system(size: 7))
                                Text("\(schemes.count)")
                                    .font(.system(size: 7, weight: .medium))
                            }
                            .foregroundColor(isSelected && !isMultiSelectMode ? .white.opacity(0.8) : .orange)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(isSelected && !isMultiSelectMode ? Color.white.opacity(0.2) : Color.orange.opacity(0.1))
                            .cornerRadius(3)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text("\(drill.durationMinutes) min")
                            .font(.system(size: 9))
                            .foregroundColor(isSelected && !isMultiSelectMode ? .white.opacity(0.7) : .gray)
                        
                        Text(drill.difficulty.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(isSelected && !isMultiSelectMode ? .white.opacity(0.7) : difficultyColor(drill.difficulty))
                    }
                }
                
                Spacer()
                
                if !isMultiSelectMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .gray.opacity(0.3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isMultiSelectMode 
                    ? (isChecked ? Color.orange.opacity(0.1) : Color.white)
                    : (isSelected ? Color.orange : Color.white)
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isChecked && isMultiSelectMode ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: (isSelected && !isMultiSelectMode) ? .clear : .black.opacity(0.02), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
    
    private func difficultyColor(_ difficulty: DifficultyLevel) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
    
    // MARK: - Drill Detail Column (Flighty Style)
    private func drillDetailColumn(_ drill: DrillItem) -> some View {
        let schemes = dataManager.schemesForDrill(drill.id)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedDrill = nil
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { dataManager.toggleDrillFavorite(drill) }) {
                    Image(systemName: drill.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(drill.isFavorite ? .yellow : .gray)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    var newScheme = CourtScheme(name: "\(drill.name) Diagram", schemeType: .drill)
                    newScheme.drillId = drill.id
                    editingScheme = newScheme
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 9))
                        Text("Add Diagram")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            Divider()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Drill header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: drill.category.icon)
                                .font(.system(size: 18))
                                .foregroundColor(categoryColor(drill.category))
                                .frame(width: 36, height: 36)
                                .background(categoryColor(drill.category).opacity(0.1))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(drill.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                                
                                Text(drill.category.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(categoryColor(drill.category))
                            }
                            
                            Spacer()
                        }
                        
                        // Stats row
                        HStack(spacing: 12) {
                            drillStatPill(icon: "clock", value: "\(drill.durationMinutes) min")
                            drillStatPill(icon: "person.2", value: drill.playerRange)
                            drillStatPill(icon: "star", value: drill.difficulty.displayName, color: difficultyColor(drill.difficulty))
                        }
                    }
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    
                    // Court Schemes section
                    if !schemes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("DIAGRAMS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(schemes.count)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                            
                            ForEach(schemes) { scheme in
                                schemePreviewRow(scheme)
                            }
                        }
                    }
                    
                    // Description
                    if !drill.description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESCRIPTION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            Text(drill.description)
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    }
                    
                    // Instructions
                    if !drill.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("INSTRUCTIONS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            ForEach(Array(drill.instructions.enumerated()), id: \.offset) { index, instruction in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                    
                                    Text(instruction)
                                        .font(.system(size: 10))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    }
                    
                    // Key Points
                    if !drill.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("KEY POINTS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            ForEach(drill.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    
                                    Text(point)
                                        .font(.system(size: 10))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    }
                    
                    // Equipment
                    if !drill.equipmentNeeded.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EQUIPMENT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            FlowLayout(spacing: 4) {
                                ForEach(drill.equipmentNeeded, id: \.self) { item in
                                    Text(item)
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.1))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    }
                }
                .padding(10)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func drillStatPill(icon: String, value: String, color: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func schemePreviewRow(_ scheme: CourtScheme) -> some View {
        Button(action: { editingScheme = scheme }) {
            HStack(spacing: 10) {
                // Mini preview
                MiniCourtPreview(frame: scheme.frames.first ?? CourtFrame(order: 0))
                    .frame(width: 50, height: 34)
                    .cornerRadius(4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(scheme.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    HStack(spacing: 6) {
                        Text("\(scheme.frameCount) frames")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(scheme.playerCount) players")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Schemes Column View
    private var schemesColumnView: some View {
        HStack(spacing: 0) {
            // Column 1: Schemes list
            schemesListColumn
            
            // Column 2: Scheme detail (when selected)
            if let scheme = selectedScheme {
                Divider()
                schemeDetailColumn(scheme)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedScheme?.id)
    }
    
    private var filteredSchemes: [CourtScheme] {
        var schemes = dataManager.courtSchemes
        
        if !searchText.isEmpty {
            schemes = schemes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        return schemes.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private var schemesListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("All Schemes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Text("\(filteredSchemes.count) schemes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            if filteredSchemes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Schemes")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Create your first play diagram")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Open Lab") { 
                        editingScheme = CourtScheme(name: "New Scheme")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSchemes) { scheme in
                            schemeListRow(scheme)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 320, maxWidth: selectedScheme != nil ? 320 : .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func schemeListRow(_ scheme: CourtScheme) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedScheme = scheme
            }
        }) {
            HStack(spacing: 12) {
                // Preview
                MiniCourtPreview(frame: scheme.frames.first ?? CourtFrame(order: 0))
                    .frame(width: 70, height: 48)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(scheme.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        if scheme.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Label(scheme.schemeType.displayName, systemImage: scheme.schemeType.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(scheme.frameCount) frames")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if selectedScheme?.id == scheme.id {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(selectedScheme?.id == scheme.id ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private func schemeDetailColumn(_ scheme: CourtScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedScheme = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { dataManager.toggleCourtSchemeFavorite(scheme) }) {
                    Image(systemName: scheme.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(scheme.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: { editingScheme = scheme }) {
                    Label("Edit in Lab", systemImage: "pencil")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Scheme header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scheme.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        HStack(spacing: 12) {
                            Label(scheme.schemeType.displayName, systemImage: scheme.schemeType.icon)
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            
                            Text("\(scheme.frameCount) frames")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text("\(scheme.playerCount) players")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Frame previews
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FRAMES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ForEach(Array(scheme.frames.enumerated()), id: \.element.id) { index, frame in
                            Button(action: { enlargedFrame = frame }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Frame \(index + 1)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppTheme.textSecondary)
                                        Spacer()
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Full fidelity court preview using Lab's CourtLinesView
                                    LabStyleFramePreview(frame: frame)
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    if let notes = frame.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 4)
                                    }
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Description
                    if let description = scheme.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DESCRIPTION")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                    
                    // Delete button
                    Button(action: {
                        dataManager.deleteCourtScheme(scheme)
                        selectedScheme = nil
                    }) {
                        Label("Delete Scheme", systemImage: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Playbook Column View
    @State private var selectedPlay: Play?
    @State private var selectedPlayCategory: PlayCategory?
    @State private var showingAddPlay = false
    @State private var editingPlay: Play?
    @State private var isPlayMultiSelectMode = false
    @State private var selectedPlayIDs: Set<UUID> = []
    @State private var showingPlayBulkDeleteAlert = false
    
    private var filteredPlays: [Play] {
        var plays = dataManager.plays
        
        if !searchText.isEmpty {
            plays = plays.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let category = selectedPlayCategory {
            plays = plays.filter { $0.category == category }
        }
        
        return plays.sorted { $0.name < $1.name }
    }
    
    private func bulkDeletePlays() {
        for playID in selectedPlayIDs {
            if let play = dataManager.plays.first(where: { $0.id == playID }) {
                dataManager.deletePlay(play)
            }
        }
        selectedPlayIDs.removeAll()
        isPlayMultiSelectMode = false
        selectedPlay = nil
    }
    
    private var playbookColumnView: some View {
        HStack(spacing: 0) {
            // Column 1: Play Categories
            playCategoriesColumn
            
            Divider()
            
            // Column 2: Plays list
            playsListColumn
            
            // Column 3: Play detail (when selected)
            if let play = selectedPlay {
                Divider()
                playDetailColumn(play)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedPlay?.id)
        .sheet(isPresented: $showingAddPlay) {
            AddEditPlaySheet(play: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $editingPlay) { play in
            AddEditPlaySheet(play: play)
                .environmentObject(dataManager)
        }
        .alert("Delete \(selectedPlayIDs.count) Plays?", isPresented: $showingPlayBulkDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                bulkDeletePlays()
            }
        } message: {
            Text("This action cannot be undone. All selected plays will be permanently deleted.")
        }
    }
    
    private var playCategoriesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            Divider()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    // All plays
                    playCategoryRow(nil, title: "All Plays", icon: "book.closed", count: filteredPlays.count)
                    
                    Divider()
                        .padding(.vertical, 6)
                    
                    ForEach(PlayCategory.allCases, id: \.self) { category in
                        let count = filteredPlays.filter { $0.category == category }.count
                        playCategoryRow(category, title: category.displayName, icon: category.icon, count: count)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 160)
        .background(Color(hex: "#f5f5f7").opacity(0.5))
    }
    
    private func playCategoryRow(_ category: PlayCategory?, title: String, icon: String, count: Int) -> some View {
        Button(action: { 
            withAnimation { selectedPlayCategory = category }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(selectedPlayCategory == category ? .white : .blue)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selectedPlayCategory == category ? .white : .black)
                
                Spacer()
                
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(selectedPlayCategory == category ? .white.opacity(0.8) : .gray)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(selectedPlayCategory == category ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedPlayCategory == category ? Color.blue : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private var playsListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with actions
            HStack {
                Text(selectedPlayCategory?.displayName ?? "All Plays")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                // Select All / Deselect All in multi-select mode
                if isPlayMultiSelectMode && !filteredPlays.isEmpty {
                    Button(action: {
                        if selectedPlayIDs.count == filteredPlays.count {
                            selectedPlayIDs.removeAll()
                        } else {
                            selectedPlayIDs = Set(filteredPlays.map { $0.id })
                        }
                    }) {
                        Text(selectedPlayIDs.count == filteredPlays.count ? "Deselect All" : "Select All")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("\(filteredPlays.count) plays")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                
                // Multi-select toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isPlayMultiSelectMode.toggle()
                        if !isPlayMultiSelectMode {
                            selectedPlayIDs.removeAll()
                        }
                    }
                }) {
                    Image(systemName: isPlayMultiSelectMode ? "xmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(isPlayMultiSelectMode ? .red : .gray)
                }
                .buttonStyle(.plain)
                
                // Bulk delete button
                if isPlayMultiSelectMode && !selectedPlayIDs.isEmpty {
                    Button(action: { showingPlayBulkDeleteAlert = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                // Add play button
                Button(action: { showingAddPlay = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isPlayMultiSelectMode)
                .opacity(isPlayMultiSelectMode ? 0.5 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            // Selection count bar
            if isPlayMultiSelectMode && !selectedPlayIDs.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                    Text("\(selectedPlayIDs.count) selected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
            }
            
            Divider()
            
            if filteredPlays.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No Plays")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Button(action: { showingAddPlay = true }) {
                        Text("Add Play")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredPlays) { play in
                            playRow(play)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 260, maxWidth: selectedPlay != nil ? 260 : .infinity)
        .background(Color(hex: "#f5f5f7").opacity(0.3))
    }
    
    private func playRow(_ play: Play) -> some View {
        let isSelected = selectedPlay?.id == play.id
        let isChecked = selectedPlayIDs.contains(play.id)
        
        return Button(action: {
            if isPlayMultiSelectMode {
                withAnimation(.spring(response: 0.2)) {
                    if isChecked {
                        selectedPlayIDs.remove(play.id)
                    } else {
                        selectedPlayIDs.insert(play.id)
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedPlay = play
                }
            }
        }) {
            HStack(spacing: 8) {
                // Checkbox in multi-select mode
                if isPlayMultiSelectMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(isChecked ? .blue : .gray.opacity(0.4))
                        .animation(.spring(response: 0.2), value: isChecked)
                }
                
                // Category icon
                Image(systemName: play.category.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected && !isPlayMultiSelectMode ? .white : .blue)
                    .frame(width: 24, height: 24)
                    .background(isSelected && !isPlayMultiSelectMode ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                    .cornerRadius(5)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(play.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isSelected && !isPlayMultiSelectMode ? .white : .black)
                            .lineLimit(1)
                        
                        if play.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        if !play.formation.isEmpty {
                            Text(play.formation)
                                .font(.system(size: 9))
                                .foregroundColor(isSelected && !isPlayMultiSelectMode ? .white.opacity(0.7) : .gray)
                        }
                        
                        Text("\(play.steps.count) steps")
                            .font(.system(size: 9))
                            .foregroundColor(isSelected && !isPlayMultiSelectMode ? .white.opacity(0.7) : .gray)
                        
                        Text(play.difficulty.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(isSelected && !isPlayMultiSelectMode ? .white.opacity(0.7) : difficultyColor(play.difficulty))
                    }
                }
                
                Spacer()
                
                if !isPlayMultiSelectMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .gray.opacity(0.3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isPlayMultiSelectMode 
                    ? (isChecked ? Color.blue.opacity(0.1) : Color.white)
                    : (isSelected ? Color.blue : Color.white)
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isChecked && isPlayMultiSelectMode ? Color.blue : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: (isSelected && !isPlayMultiSelectMode) ? .clear : .black.opacity(0.02), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Play Detail Column
    private func playDetailColumn(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedPlay = nil
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { dataManager.togglePlayFavorite(play) }) {
                    Image(systemName: play.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(play.isFavorite ? .yellow : .gray)
                }
                .buttonStyle(.plain)
                
                Button(action: { editingPlay = play }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                        Text("Edit")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            
            Divider()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Play header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: play.category.icon)
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 36, height: 36)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(play.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                                
                                Text(play.category.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                        }
                        
                        // Stats row
                        HStack(spacing: 12) {
                            if !play.formation.isEmpty {
                                playStatPill(icon: "square.grid.2x2", value: play.formation)
                            }
                            playStatPill(icon: "list.number", value: "\(play.steps.count) steps")
                            playStatPill(icon: "star", value: play.difficulty.displayName, color: difficultyColor(play.difficulty))
                        }
                    }
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
                    
                    // Description
                    if !play.description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESCRIPTION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            Text(play.description)
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    // Best Used Against
                    if let bestAgainst = play.bestUsedAgainst, !bestAgainst.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BEST USED AGAINST")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            Text(bestAgainst)
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    // Steps
                    if !play.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STEPS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            ForEach(play.steps) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(step.stepNumber)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.blue)
                                        .cornerRadius(9)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.description)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.black)
                                        
                                        if let keyPoint = step.keyPoint {
                                            HStack(spacing: 3) {
                                                Image(systemName: "lightbulb.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.orange)
                                                Text(keyPoint)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.gray)
                                                    .italic()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    // Key Teaching Points
                    if !play.keyTeachingPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("KEY TEACHING POINTS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            ForEach(play.keyTeachingPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text(point)
                                        .font(.system(size: 10))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    // Variations
                    if !play.variations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("VARIATIONS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            ForEach(play.variations, id: \.self) { variation in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.purple)
                                    Text(variation)
                                        .font(.system(size: 10))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    // Tags
                    if !play.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TAGS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            FlowLayout(spacing: 4) {
                                ForEach(play.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                }
                .padding(10)
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func playStatPill(icon: String, value: String, color: Color = .gray) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Lab Style Frame Preview (Uses exact same rendering as Lab)
struct LabStyleFramePreview: View {
    let frame: CourtFrame
    
    var body: some View {
        GeometryReader { geometry in
            let courtAspect: CGFloat = 94.0 / 50.0
            let containerAspect = geometry.size.width / geometry.size.height
            let courtSize = calculateCourtSize(containerSize: geometry.size, courtAspect: courtAspect, containerAspect: containerAspect)
            let courtOrigin = CGPoint(
                x: (geometry.size.width - courtSize.width) / 2,
                y: (geometry.size.height - courtSize.height) / 2
            )
            
            ZStack {
                // Background - same as Lab
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .frame(width: courtSize.width + 10, height: courtSize.height + 10)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Court lines - using Lab's CourtLinesView
                CourtLinesView()
                    .frame(width: courtSize.width, height: courtSize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Movements - using Lab's MovementLineView style
                ForEach(frame.movements) { movement in
                    LabStyleMovementLine(
                        movement: movement,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin
                    )
                }
                
                // Players - using Lab's PlayerMarkerView style
                ForEach(frame.players) { player in
                    LabStylePlayerMarker(
                        player: player,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin
                    )
                }
            }
        }
    }
    
    private func calculateCourtSize(containerSize: CGSize, courtAspect: CGFloat, containerAspect: CGFloat) -> CGSize {
        if containerAspect > courtAspect {
            let height = containerSize.height * 0.95
            return CGSize(width: height * courtAspect, height: height)
        } else {
            let width = containerSize.width * 0.95
            return CGSize(width: width, height: width / courtAspect)
        }
    }
}

// MARK: - Lab Style Movement Line
struct LabStyleMovementLine: View {
    let movement: CourtMovement
    let courtSize: CGSize
    let courtOrigin: CGPoint
    
    var body: some View {
        let startX = courtOrigin.x + movement.startPoint.x * courtSize.width
        let startY = courtOrigin.y + movement.startPoint.y * courtSize.height
        let endX = courtOrigin.x + movement.endPoint.x * courtSize.width
        let endY = courtOrigin.y + movement.endPoint.y * courtSize.height
        
        let allPoints = [movement.startPoint] + movement.waypoints + [movement.endPoint]
        
        ZStack {
            // Main line
            if movement.pathStyle == .curved && allPoints.count > 2 {
                buildCurvedPath(points: allPoints)
                    .stroke(movementColor, style: strokeStyle)
            } else {
                buildPath(points: allPoints)
                    .stroke(movementColor, style: strokeStyle)
            }
            
            // Arrow head (except for flat lines)
            if movement.movementType != .drawFlat {
                ArrowHead(
                    start: secondToLastPoint(allPoints),
                    end: CGPoint(x: endX, y: endY)
                )
                .fill(movementColor)
            }
            
            // Flat end marker
            if movement.movementType == .drawFlat {
                FlatEndMarker(
                    start: secondToLastPoint(allPoints),
                    end: CGPoint(x: endX, y: endY)
                )
                .stroke(movementColor, lineWidth: 2)
            }
            
            // Screen marker
            if movement.movementType == .screen {
                ScreenEndMarker(
                    start: secondToLastPoint(allPoints),
                    end: CGPoint(x: endX, y: endY)
                )
                .stroke(movementColor, lineWidth: 3)
            }
        }
    }
    
    private func secondToLastPoint(_ points: [CGPoint]) -> CGPoint {
        let screenPoints = points.map { CGPoint(
            x: courtOrigin.x + $0.x * courtSize.width,
            y: courtOrigin.y + $0.y * courtSize.height
        )}
        if screenPoints.count >= 2 {
            return screenPoints[screenPoints.count - 2]
        }
        return screenPoints.first ?? .zero
    }
    
    private func buildPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(
                x: courtOrigin.x + first.x * courtSize.width,
                y: courtOrigin.y + first.y * courtSize.height
            ))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: courtOrigin.x + point.x * courtSize.width,
                    y: courtOrigin.y + point.y * courtSize.height
                ))
            }
        }
    }
    
    private func buildCurvedPath(points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else { return }
            let screenPoints = points.map { CGPoint(
                x: courtOrigin.x + $0.x * courtSize.width,
                y: courtOrigin.y + $0.y * courtSize.height
            )}
            
            path.move(to: screenPoints[0])
            
            if screenPoints.count == 2 {
                path.addLine(to: screenPoints[1])
            } else {
                for i in 1..<screenPoints.count {
                    let current = screenPoints[i]
                    let previous = screenPoints[i - 1]
                    let control = CGPoint(
                        x: (previous.x + current.x) / 2,
                        y: (previous.y + current.y) / 2
                    )
                    if i == 1 {
                        path.addLine(to: control)
                    }
                    path.addQuadCurve(to: current, control: control)
                }
            }
        }
    }
    
    var movementColor: Color {
        switch movement.movementType {
        case .run: return .cyan
        case .dribble: return .orange
        case .pass: return .green
        case .screen: return .yellow
        case .cut: return .purple
        case .drawArrow, .drawFlat, .drawCurved: return .purple
        }
    }
    
    var strokeStyle: StrokeStyle {
        switch movement.movementType {
        case .run: return StrokeStyle(lineWidth: 2)
        case .dribble: return StrokeStyle(lineWidth: 2, dash: [6, 4])
        case .pass: return StrokeStyle(lineWidth: 2, dash: [3, 3])
        case .screen: return StrokeStyle(lineWidth: 3)
        case .cut: return StrokeStyle(lineWidth: 2, dash: [2, 2])
        case .drawArrow, .drawFlat, .drawCurved: return StrokeStyle(lineWidth: 2)
        }
    }
}

// MARK: - Lab Style Player Marker
struct LabStylePlayerMarker: View {
    let player: CourtPlayer
    let courtSize: CGSize
    let courtOrigin: CGPoint
    
    var playerColor: Color {
        player.team == .offense ? .white : .yellow
    }
    
    var body: some View {
        let x = courtOrigin.x + player.position.x * courtSize.width
        let y = courtOrigin.y + player.position.y * courtSize.height
        
        ZStack {
            // Player circle with border
            Circle()
                .fill(playerColor)
                .frame(width: 22, height: 22)
            
            Circle()
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
                .frame(width: 22, height: 22)
            
            // Number
            if let number = player.number {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
            }
            
            // Ball indicator
            if player.hasBall {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    )
                    .offset(x: 10, y: -10)
            }
        }
        .position(x: x, y: y)
    }
}

// MARK: - Enlarged Frame View (Full Screen Modal)
struct EnlargedFrameView: View {
    let frame: CourtFrame
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Frame Preview")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Full size court preview
            LabStyleFramePreview(frame: frame)
                .padding(20)
            
            // Frame info
            if !frame.players.isEmpty {
                HStack(spacing: 20) {
                    Label("\(frame.players.filter { $0.team == .offense }.count) Offense", systemImage: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    
                    Label("\(frame.players.filter { $0.team == .defense }.count) Defense", systemImage: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    
                    if !frame.movements.isEmpty {
                        Label("\(frame.movements.count) Movements", systemImage: "arrow.right")
                            .font(.system(size: 12))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.bottom, 16)
            }
            
            if let notes = frame.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview
#Preview {
    MacCoachResourcesView()
        .environmentObject(DataManager.shared)
        .frame(width: 1000, height: 700)
}
#endif
