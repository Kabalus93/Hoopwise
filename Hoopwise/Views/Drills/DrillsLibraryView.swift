import SwiftUI

struct DrillsLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory?
    @State private var selectedDifficulty: DifficultyLevel?
    @State private var showFavoritesOnly = false
    @State private var showingAddDrill = false
    @State private var viewMode: ViewMode = .browse
    
    enum ViewMode: String, CaseIterable {
        case browse = "browse"
        case list = "list"
        
        var icon: String {
            switch self {
            case .browse: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    private var currentCoachId: UUID {
        dataManager.loggedInCoachId ?? dataManager.coach.id
    }

    private var visibleDrills: [DrillItem] {
        dataManager.drills.filter { drill in
            let visibilityTag = drill.tags.first(where: { $0.hasPrefix("visibility:") })
            let ownerTag = drill.tags.first(where: { $0.hasPrefix("owner:") })

            if visibilityTag == "visibility:private" {
                guard let ownerTag else { return false }
                return ownerTag == "owner:\(currentCoachId.uuidString)"
            }
            return true
        }
    }
    
    var filteredDrills: [DrillItem] {
        var drills = visibleDrills
        
        if !searchText.isEmpty {
            drills = drills.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.localizedName.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            drills = drills.filter { $0.category == category }
        }
        
        if let difficulty = selectedDifficulty {
            drills = drills.filter { $0.difficulty == difficulty }
        }
        
        if showFavoritesOnly {
            drills = drills.filter { $0.isFavorite }
        }
        
        return drills.sorted { $0.name < $1.name }
    }
    
    // Featured drills (random selection that changes)
    var featuredDrills: [DrillItem] {
        let allDrills = visibleDrills
        guard allDrills.count >= 3 else { return Array(allDrills.prefix(3)) }
        
        // Get drills from different categories for variety
        var featured: [DrillItem] = []
        let categories = DrillCategory.allCases.shuffled()
        
        for category in categories {
            if let drill = allDrills.filter({ $0.category == category }).randomElement() {
                featured.append(drill)
                if featured.count >= 3 { break }
            }
        }
        
        return featured
    }
    
    // Quick drills (under 10 minutes)
    var quickDrills: [DrillItem] {
        visibleDrills.filter { $0.durationMinutes <= 10 }.prefix(5).map { $0 }
    }
    
    // Drill counts by category
    func drillCount(for category: DrillCategory) -> Int {
        visibleDrills.filter { $0.category == category }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header with search
                    headerSection
                    
                    if searchText.isEmpty && selectedCategory == nil && !showFavoritesOnly {
                        // Browse mode content
                        browseContent
                    } else {
                        // Filtered list
                        filteredContent
                    }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .sheet(isPresented: $showingAddDrill) {
                AddEditDrillSheet(drill: nil)
                    .environmentObject(dataManager)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DrillLocalization.L("Drills"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text(isChinese ? "\(dataManager.drills.count) 个训练可用" : "\(dataManager.drills.count) drills available")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Spacer()
                
                // Favorites toggle
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation(.spring(response: 0.3)) {
                        showFavoritesOnly.toggle()
                    }
                }) {
                    Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundColor(showFavoritesOnly ? .red : AppTheme.textTertiary)
                        .frame(width: 40, height: 40)
                        .background(showFavoritesOnly ? Color.red.opacity(0.1) : AppTheme.surfaceColor)
                        .clipShape(Circle())
                }
                
                // Add drill button
                Button(action: { showingAddDrill = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.accentColor, AppTheme.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: AppTheme.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                
                TextField(DrillLocalization.L("Search drills..."), text: $searchText)
                    .font(.system(size: 16))
                
                if !searchText.isEmpty {
                    Button(action: { 
                        searchText = ""
                        HapticFeedback.impact(.light)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.surfaceColor)
            .cornerRadius(14)
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.top, AppTheme.spacing)
        .padding(.bottom, 8)
    }
    
    // MARK: - Browse Content (Default View)
    private var browseContent: some View {
        VStack(spacing: 24) {
            // Quick Stats
            statsSection
            
            // Categories Grid
            categoriesSection
            
            // Featured Drills
            if !featuredDrills.isEmpty {
                featuredSection
            }
            
            // Quick Drills
            if !quickDrills.isEmpty {
                quickDrillsSection
            }
            
            // All Drills by Category
            allDrillsSection
            
            Spacer(minLength: 100)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 12) {
            DrillStatsCard(
                icon: "figure.basketball",
                value: "\(visibleDrills.count)",
                label: DrillLocalization.L("Total Drills"),
                color: .orange
            )
            
            DrillStatsCard(
                icon: "folder.fill",
                value: "\(DrillCategory.allCases.count)",
                label: DrillLocalization.L("Categories"),
                color: .blue
            )
            
            DrillStatsCard(
                icon: "heart.fill",
                value: "\(visibleDrills.filter { $0.isFavorite }.count)",
                label: DrillLocalization.L("Favorites"),
                color: .red
            )
        }
        .padding(.horizontal, AppTheme.spacing)
    }
    
    // MARK: - Categories Section
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DrillLocalization.L("Browse by Category"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.spacing)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DrillCategory.allCases, id: \.self) { category in
                        Button(action: {
                            HapticFeedback.impact(.light)
                            withAnimation(.spring(response: 0.3)) {
                                selectedCategory = category
                            }
                        }) {
                            DrillCategoryCard(
                                category: category,
                                drillCount: drillCount(for: category),
                                isSelected: selectedCategory == category
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.spacing)
            }
        }
    }
    
    // MARK: - Featured Section
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DrillLocalization.L("Featured Drills"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, AppTheme.spacing)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(featuredDrills) { drill in
                        NavigationLink(destination: DrillDetailView(drill: drill)) {
                            DrillCard(drill: drill, style: .featured)
                                .frame(width: 280)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.spacing)
            }
        }
    }
    
    // MARK: - Quick Drills Section
    private var quickDrillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DrillLocalization.L("Quick Drills"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(isChinese ? "10分钟以内" : "Under 10 min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
                
                Spacer()
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, AppTheme.spacing)
            
            VStack(spacing: 8) {
                ForEach(quickDrills) { drill in
                    NavigationLink(destination: DrillDetailView(drill: drill)) {
                        DrillCard(drill: drill, onFavorite: {
                            dataManager.toggleDrillFavorite(drill)
                        }, style: .compact)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacing)
        }
    }
    
    // MARK: - All Drills Section
    private var allDrillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isChinese ? "所有训练" : "All Drills")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: {
                    // Could add sort options here
                }) {
                    HStack(spacing: 4) {
                        Text(isChinese ? "名称排序" : "A-Z")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, AppTheme.spacing)
            
            LazyVStack(spacing: 10) {
                ForEach(visibleDrills.sorted { $0.name < $1.name }) { drill in
                    NavigationLink(destination: DrillDetailView(drill: drill)) {
                        DrillCard(drill: drill, onFavorite: {
                            dataManager.toggleDrillFavorite(drill)
                        })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacing)
        }
    }
    
    // MARK: - Filtered Content
    private var filteredContent: some View {
        VStack(spacing: 12) {
            // Active filters
            if selectedCategory != nil || showFavoritesOnly || !searchText.isEmpty {
                activeFiltersBar
            }
            
            // Results
            if filteredDrills.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredDrills) { drill in
                        NavigationLink(destination: DrillDetailView(drill: drill)) {
                            DrillCard(drill: drill, onFavorite: {
                                dataManager.toggleDrillFavorite(drill)
                            })
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, AppTheme.spacing)
            }
        }
    }
    
    // MARK: - Active Filters Bar
    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let category = selectedCategory {
                    FilterPill(
                        text: DrillLocalization.localizedCategory(category),
                        color: Color.drillCategoryColor(category),
                        onRemove: {
                            withAnimation { selectedCategory = nil }
                        }
                    )
                }
                
                if showFavoritesOnly {
                    FilterPill(
                        text: DrillLocalization.L("Favorites"),
                        color: .red,
                        onRemove: {
                            withAnimation { showFavoritesOnly = false }
                        }
                    )
                }
                
                if !searchText.isEmpty {
                    FilterPill(
                        text: "\"\(searchText)\"",
                        color: AppTheme.accentColor,
                        onRemove: {
                            withAnimation { searchText = "" }
                        }
                    )
                }
                
                // Clear all button
                Button(action: {
                    withAnimation {
                        selectedCategory = nil
                        showFavoritesOnly = false
                        searchText = ""
                    }
                }) {
                    Text(DrillLocalization.L("Clear Filters"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceColor)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "figure.basketball")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(spacing: 8) {
                Text(DrillLocalization.L("No drills yet"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(searchText.isEmpty && selectedCategory == nil ? 
                     DrillLocalization.L("Add your first drill to get started") : 
                     DrillLocalization.L("Try adjusting your filters"))
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if searchText.isEmpty && selectedCategory == nil && selectedDifficulty == nil && !showFavoritesOnly {
                Button(action: { showingAddDrill = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(DrillLocalization.L("Add Drill"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 60)
            } else {
                Button(action: {
                    withAnimation {
                        searchText = ""
                        selectedCategory = nil
                        selectedDifficulty = nil
                        showFavoritesOnly = false
                    }
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text(DrillLocalization.L("Clear Filters"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 60)
            }
            
            Spacer()
        }
        .padding()
        .frame(minHeight: 400)
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let text: String
    let color: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(20)
    }
}

// MARK: - Drill Detail View (Enhanced)
struct DrillDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let drill: DrillItem
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    
    // Inline editing state
    @State private var editingDescription = false
    @State private var editedDescription = ""
    @State private var editingInstructions = false
    @State private var editedInstructions: [String] = []
    @State private var newInstruction = ""
    @State private var editingKeyPoints = false
    @State private var editedKeyPoints: [String] = []
    @State private var newKeyPoint = ""
    @FocusState private var focusedField: InlineEditField?
    
    private enum InlineEditField: Hashable {
        case description
        case instruction(Int)
        case newInstruction
        case keyPoint(Int)
        case newKeyPoint
    }
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var categoryColor: Color {
        Color.drillCategoryColor(drill.category)
    }
    
    private var currentDrill: DrillItem {
        dataManager.drills.first(where: { $0.id == drill.id }) ?? drill
    }

    private var userFacingTags: [String] {
        currentDrill.tags
            .filter { !$0.hasPrefix("visibility:") }
            .filter { !$0.hasPrefix("owner:") }
            .filter { $0 != "quick-note" } // Hide internal tag
            .map { raw in
                raw.replacingOccurrences(of: "-", with: " ")
                   .replacingOccurrences(of: "_", with: " ")
                   .capitalized
            }
    }
    
    private var suggestedTags: [String] {
        var tags: [String] = []
        // Suggest based on category
        switch currentDrill.category {
        case .warmup: tags.append(contentsOf: ["Warm-up", "Stretching", "Mobility"])
        case .shooting: tags.append(contentsOf: ["Shooting", "Form", "Accuracy"])
        case .skills: tags.append(contentsOf: ["Ball Handling", "Footwork", "Fundamentals"])
        case .offense: tags.append(contentsOf: ["Offense", "Plays", "Movement"])
        case .defense: tags.append(contentsOf: ["Defense", "Positioning", "Pressure"])
        case .conditioning: tags.append(contentsOf: ["Conditioning", "Cardio", "Agility"])
        case .cooldown: tags.append(contentsOf: ["Cool-down", "Recovery", "Stretching"])
        }
        return tags.filter { !userFacingTags.contains($0) }
    }

    private var visibilityLabel: String? {
        if currentDrill.tags.contains("visibility:private") {
            return isChinese ? "私有" : "Private"
        }
        if currentDrill.tags.contains("visibility:shared") {
            return isChinese ? "共享" : "Shared"
        }
        return nil
    }

    private var isQuickNoteDrill: Bool {
        currentDrill.tags.contains("quick-note")
    }
    
    private var completionProgress: (filled: Int, total: Int) {
        var filled = 1 // name always filled
        let total = 5 // name, description, instructions, keyPoints, tags
        if !currentDrill.description.isEmpty { filled += 1 }
        if !currentDrill.instructions.isEmpty { filled += 1 }
        if !currentDrill.keyPoints.isEmpty { filled += 1 }
        if !userFacingTags.isEmpty { filled += 1 }
        return (filled, total)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Compact Hero Header
                    heroHeader
                    
                    // Content
                    VStack(spacing: 16) {
                        // Inline info chips (replaces cards)
                        quickInfoChips
                        
                        // Description (with placeholder for empty)
                        descriptionSection
                        
                        // Instructions (with placeholder for empty)
                        instructionsSection
                        
                        // Key Points (with placeholder for empty)
                        keyPointsSection
                        
                        // Tags (with suggestions for empty)
                        tagsSection
                        
                        // Equipment (only if has content)
                        if !currentDrill.equipmentNeeded.isEmpty {
                            equipmentSection
                        }
                        
                        // Variations (only if has content)
                        if !currentDrill.variations.isEmpty {
                            variationsSection
                        }
                        
                        Spacer(minLength: isQuickNoteDrill ? 100 : 40)
                    }
                    .padding(.horizontal, AppTheme.spacing)
                    .padding(.top, 16)
                }
            }
            
            // Quick actions footer for quick-note drills
            if isQuickNoteDrill {
                quickActionsFooter
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                HStack(spacing: 12) {
                    Button(action: {
                        showEditSheet = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Button(action: {
                        HapticFeedback.impact(.light)
                        dataManager.toggleDrillFavorite(currentDrill)
                    }) {
                        Image(systemName: currentDrill.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(currentDrill.isFavorite ? .red : AppTheme.textSecondary)
                    }
                }
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showEditSheet) {
            AddEditDrillSheet(drill: currentDrill)
                .environmentObject(dataManager)
        }
        .alert(isChinese ? "删除训练" : "Delete Drill", isPresented: $showDeleteConfirm) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                dataManager.deleteDrill(currentDrill)
                dismiss()
            }
        } message: {
            Text(isChinese ? "确定要删除这个训练吗？" : "Are you sure you want to delete this drill?")
        }
        #endif
    }
    
    // MARK: - Compact Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background - more compact
            LinearGradient(
                colors: [categoryColor, categoryColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)
            
            // Smaller watermark icon
            Image(systemName: drill.category.icon)
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(.white.opacity(0.1))
                .offset(x: 220, y: -10)
            
            // Content - tighter spacing
            VStack(alignment: .leading, spacing: 6) {
                // Category + visibility as inline pills
                HStack(spacing: 6) {
                    Text(currentDrill.localizedCategory.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2))
                        .cornerRadius(4)

                    if let visibilityLabel {
                        Text(visibilityLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.22))
                            .cornerRadius(4)
                    }
                }
                
                // Drill name - single line with truncation
                Text(currentDrill.localizedName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Difficulty dots closer to name
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i < currentDrill.difficulty.level ? .white : .white.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                    Text(currentDrill.localizedDifficulty)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
    
    // MARK: - Inline Info Chips (replaces cards)
    private var quickInfoChips: some View {
        HStack(spacing: 16) {
            // Duration chip
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(currentDrill.localizedDuration)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Text("·")
                .foregroundColor(AppTheme.textTertiary)
            
            // Players chip
            HStack(spacing: 5) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                Text(currentDrill.localizedPlayerRange)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            // Completion indicator for quick-note drills
            if isQuickNoteDrill {
                let progress = completionProgress
                Text("\(progress.filled)/\(progress.total)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Refinement CTA Card
    private var refinementCTACard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text(isChinese ? "完善此训练" : "Complete This Drill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            Text(isChinese ? "添加说明、要点和器材，使其可重复使用。" : "Add instructions, key points, and equipment to make it reusable.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
    
    // MARK: - Quick Actions Footer
    private var quickActionsFooter: some View {
        HStack {
            Spacer()
            
            // Delete button only - Edit is in toolbar
            Button(action: {
                showDeleteConfirm = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                    Text(isChinese ? "删除此训练" : "Delete Drill")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(AppTheme.cardBackground)
                .shadow(color: .black.opacity(0.03), radius: 2, y: -1)
        )
    }
    
    // MARK: - Quick Info Section
    private var quickInfoSection: some View {
        HStack(spacing: 12) {
            // Duration
            QuickInfoCard(
                icon: "clock.fill",
                value: currentDrill.localizedDuration,
                label: DrillLocalization.L("Duration"),
                color: .blue
            )
            
            // Players
            QuickInfoCard(
                icon: "person.2.fill",
                value: currentDrill.localizedPlayerRange,
                label: DrillLocalization.L("Players"),
                color: .green
            )
            
            // Favorite
            Button(action: {
                HapticFeedback.impact(.medium)
                dataManager.toggleDrillFavorite(currentDrill)
            }) {
                QuickInfoCard(
                    icon: currentDrill.isFavorite ? "heart.fill" : "heart",
                    value: currentDrill.isFavorite ? "★" : "☆",
                    label: DrillLocalization.L("Favorites"),
                    color: currentDrill.isFavorite ? .red : .gray
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var quickNoteContextSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text(LocalizationManager.shared.currentLanguage == .chinese ? "此训练来自课程中的快速文本记录，可在这里完善为正式训练模板。" : "This drill came from a quick session text note. You can refine it into a full drill template here.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
    }
    
    // MARK: - Description Section (inline editing)
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: DrillLocalization.L("Description"), icon: "text.alignleft")
                Spacer()
                if editingDescription {
                    Button(action: saveDescription) {
                        Text(isChinese ? "保存" : "Save")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppTheme.accentColor)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if editingDescription {
                // Inline editor
                TextEditor(text: $editedDescription)
                    .font(.system(size: 14))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.accentColor, lineWidth: 1.5)
                    )
                    .focused($focusedField, equals: .description)
            } else if currentDrill.description.isEmpty {
                // Placeholder for empty - tap to edit
                Button(action: startEditingDescription) {
                    HStack {
                        Text(isChinese ? "点击添加描述..." : "Tap to add a description...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textTertiary)
                            .italic()
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            } else {
                // Display mode - tap to edit
                Button(action: startEditingDescription) {
                    HStack(alignment: .top) {
                        Text(currentDrill.localizedDescription)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Instructions Section (inline editing)
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: DrillLocalization.L("Instructions"), icon: "list.number")
                Spacer()
                if editingInstructions {
                    Button(action: saveInstructions) {
                        Text(isChinese ? "完成" : "Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                } else if !currentDrill.instructions.isEmpty {
                    Button(action: startEditingInstructions) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                if editingInstructions {
                    // Editable list
                    ForEach(editedInstructions.indices, id: \.self) { index in
                        HStack(alignment: .center, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 20)
                            
                            TextField(isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)", text: $editedInstructions[index])
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .instruction(index))
                            
                            Button(action: { removeInstruction(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        
                        if index < editedInstructions.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                    
                    Divider().padding(.vertical, 6)
                    
                    // Add new step
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .frame(width: 20)
                        
                        TextField(isChinese ? "添加步骤..." : "Add step...", text: $newInstruction)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .focused($focusedField, equals: .newInstruction)
                            .onSubmit { addNewInstruction() }
                    }
                    .padding(.vertical, 6)
                } else if currentDrill.instructions.isEmpty {
                    // Empty placeholder
                    Button(action: startEditingInstructions) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text(isChinese ? "添加步骤" : "Add step")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Display mode
                    ForEach(Array(currentDrill.localizedInstructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            
                            Text(instruction)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        
                        if index < currentDrill.localizedInstructions.count - 1 {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Key Points Section (inline editing)
    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(title: DrillLocalization.L("Key Points"), icon: "lightbulb.fill")
                Spacer()
                if editingKeyPoints {
                    Button(action: saveKeyPoints) {
                        Text(isChinese ? "完成" : "Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                } else if !currentDrill.keyPoints.isEmpty {
                    Button(action: startEditingKeyPoints) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                if editingKeyPoints {
                    // Editable list
                    ForEach(editedKeyPoints.indices, id: \.self) { index in
                        HStack(alignment: .center, spacing: 10) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 16)
                            
                            TextField(isChinese ? "要点 \(index + 1)" : "Point \(index + 1)", text: $editedKeyPoints[index])
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .keyPoint(index))
                            
                            Button(action: { removeKeyPoint(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        
                        if index < editedKeyPoints.count - 1 {
                            Divider().padding(.leading, 26)
                        }
                    }
                    
                    Divider().padding(.vertical, 6)
                    
                    // Add new key point
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .frame(width: 16)
                        
                        TextField(isChinese ? "添加要点..." : "Add point...", text: $newKeyPoint)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .focused($focusedField, equals: .newKeyPoint)
                            .onSubmit { addNewKeyPoint() }
                    }
                    .padding(.vertical, 6)
                } else if currentDrill.keyPoints.isEmpty {
                    // Empty placeholder
                    Button(action: startEditingKeyPoints) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text(isChinese ? "添加要点" : "Add key point")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Display mode
                    ForEach(currentDrill.localizedKeyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(point)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Inline Editing Helpers
    private func startEditingDescription() {
        editedDescription = currentDrill.description
        editingDescription = true
        focusedField = .description
    }
    
    private func saveDescription() {
        var updated = currentDrill
        updated.description = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.updateDrill(updated)
        editingDescription = false
        focusedField = nil
    }
    
    private func startEditingInstructions() {
        editedInstructions = currentDrill.instructions.isEmpty ? [""] : currentDrill.instructions
        newInstruction = ""
        editingInstructions = true
    }
    
    private func addNewInstruction() {
        let trimmed = newInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedInstructions.append(trimmed)
        newInstruction = ""
    }
    
    private func removeInstruction(at index: Int) {
        guard editedInstructions.indices.contains(index) else { return }
        editedInstructions.remove(at: index)
    }
    
    private func saveInstructions() {
        var updated = currentDrill
        updated.instructions = editedInstructions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        dataManager.updateDrill(updated)
        editingInstructions = false
        focusedField = nil
    }
    
    private func startEditingKeyPoints() {
        editedKeyPoints = currentDrill.keyPoints.isEmpty ? [""] : currentDrill.keyPoints
        newKeyPoint = ""
        editingKeyPoints = true
    }
    
    private func addNewKeyPoint() {
        let trimmed = newKeyPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedKeyPoints.append(trimmed)
        newKeyPoint = ""
    }
    
    private func removeKeyPoint(at index: Int) {
        guard editedKeyPoints.indices.contains(index) else { return }
        editedKeyPoints.remove(at: index)
    }
    
    private func saveKeyPoints() {
        var updated = currentDrill
        updated.keyPoints = editedKeyPoints.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        dataManager.updateDrill(updated)
        editingKeyPoints = false
        focusedField = nil
    }
    
    private func addTagInline(_ tag: String) {
        var updated = currentDrill
        // Convert tag to lowercase with dashes for storage
        let normalizedTag = tag.lowercased().replacingOccurrences(of: " ", with: "-")
        if !updated.tags.contains(normalizedTag) {
            updated.tags.append(normalizedTag)
            dataManager.updateDrill(updated)
        }
    }
    
    // MARK: - Equipment Section
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: DrillLocalization.L("Equipment Needed"), icon: "basketball.fill")
            
            FlowLayout(spacing: 10) {
                ForEach(currentDrill.equipmentNeeded, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: equipmentIcon(for: item))
                            .font(.system(size: 12))
                            .foregroundColor(categoryColor.accessibleText)
                        Text(DrillLocalization.localizedEquipment(item))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(categoryColor.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Variations Section
    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: DrillLocalization.L("Variations"), icon: "arrow.triangle.branch")
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(currentDrill.localizedVariations, id: \.self) { variation in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 14))
                            .foregroundColor(categoryColor.accessibleText)
                        Text(variation)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Tags Section (with suggestions)
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: isChinese ? "标签" : "Tags", icon: "tag")
            
            VStack(alignment: .leading, spacing: 10) {
                // Existing tags
                if !userFacingTags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(userFacingTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                        }
                    }
                }
                
                // Suggested tags (show when tags are empty or always show suggestions)
                if !suggestedTags.isEmpty {
                    if !userFacingTags.isEmpty {
                        Divider().padding(.vertical, 4)
                    }
                    
                    Text(isChinese ? "建议添加" : "Suggested")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(suggestedTags.prefix(4), id: \.self) { tag in
                            Button(action: {
                                addTagInline(tag)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Show placeholder if no tags and no suggestions
                if userFacingTags.isEmpty && suggestedTags.isEmpty {
                    Text(isChinese ? "暂无标签" : "No tags")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Helper
    private func equipmentIcon(for item: String) -> String {
        let lowercased = item.lowercased()
        if lowercased.contains("basketball") || lowercased.contains("ball") {
            return "basketball.fill"
        } else if lowercased.contains("cone") {
            return "cone.fill"
        } else if lowercased.contains("chair") {
            return "chair.fill"
        } else if lowercased.contains("ladder") {
            return "ladder.fill"
        } else {
            return "circle.fill"
        }
    }
}

// MARK: - Quick Info Card
struct QuickInfoCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Detail Section Header
struct DetailSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Add Drill View
struct AddDrillView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var category: DrillCategory = .skills
    @State private var difficulty: DifficultyLevel = .beginner
    @State private var durationMinutes = 10
    @State private var description = ""
    @State private var instructions: [String] = [""]
    @State private var keyPoints: [String] = [""]
    @State private var minPlayers = 1
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            Form {
                Section(isChinese ? "基本信息" : "Basic Info") {
                    TextField(isChinese ? "训练名称" : "Drill Name", text: $name)
                    
                    Picker(isChinese ? "类别" : "Category", selection: $category) {
                        ForEach(DrillCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    
                    Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    
                    Stepper(isChinese ? "时长：\(durationMinutes) 分钟" : "Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...60)
                    Stepper(isChinese ? "最少人数：\(minPlayers)" : "Min Players: \(minPlayers)", value: $minPlayers, in: 1...20)
                }
                
                Section(isChinese ? "描述" : "Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
                
                Section(isChinese ? "说明" : "Instructions") {
                    ForEach(instructions.indices, id: \.self) { index in
                        TextField(isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)", text: $instructions[index])
                    }
                    Button(isChinese ? "添加步骤" : "Add Step") {
                        instructions.append("")
                    }
                }
                
                Section(isChinese ? "要点" : "Key Points") {
                    ForEach(keyPoints.indices, id: \.self) { index in
                        TextField(isChinese ? "要点 \(index + 1)" : "Point \(index + 1)", text: $keyPoints[index])
                    }
                    Button(isChinese ? "添加要点" : "Add Point") {
                        keyPoints.append("")
                    }
                }
            }
            .navigationTitle(isChinese ? "新训练" : "New Drill")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create") {
                        createDrill()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createDrill() {
        let drill = DrillItem(
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: description,
            instructions: instructions.filter { !$0.isEmpty },
            keyPoints: keyPoints.filter { !$0.isEmpty },
            minPlayers: minPlayers
        )
        dataManager.addDrill(drill)
        dismiss()
    }
}

#if !os(macOS)
// MARK: - iOS Add/Edit Drill Sheet
/// macOS has its own `AddEditDrillSheet` in the Mac coach library.
/// iOS targets need a local implementation to avoid build failures.
struct AddEditDrillSheet: View {
    let drill: DrillItem?
    
    var body: some View {
        Group {
            if let drill {
                EditDrillView(drill: drill)
            } else {
                AddDrillView()
            }
        }
    }
}

// MARK: - iOS Edit Drill View
private struct EditDrillView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let drill: DrillItem
    
    @State private var name: String
    @State private var category: DrillCategory
    @State private var difficulty: DifficultyLevel
    @State private var durationMinutes: Int
    @State private var description: String
    @State private var instructions: [String]
    @State private var keyPoints: [String]
    @State private var minPlayers: Int
    @State private var newInstruction = ""
    @State private var newKeyPoint = ""
    
    init(drill: DrillItem) {
        self.drill = drill
        _name = State(initialValue: drill.name)
        _category = State(initialValue: drill.category)
        _difficulty = State(initialValue: drill.difficulty)
        _durationMinutes = State(initialValue: drill.durationMinutes)
        _description = State(initialValue: drill.description)
        _instructions = State(initialValue: drill.instructions.isEmpty ? [""] : drill.instructions)
        _keyPoints = State(initialValue: drill.keyPoints.isEmpty ? [""] : drill.keyPoints)
        _minPlayers = State(initialValue: drill.minPlayers)
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "基础信息" : "Basic Info")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        TextField(isChinese ? "训练名称" : "Drill Name", text: $name)
                            .padding(12)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)

                        HStack(spacing: 10) {
                            Picker(isChinese ? "类别" : "Category", selection: $category) {
                                ForEach(DrillCategory.allCases, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)

                            Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                                ForEach(DifficultyLevel.allCases, id: \.self) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                        }

                        valueAdjustRow(
                            title: isChinese ? "时长" : "Duration",
                            valueText: isChinese ? "\(durationMinutes) 分钟" : "\(durationMinutes) min",
                            canDecrement: durationMinutes > 1,
                            decrement: { durationMinutes -= 1 },
                            canIncrement: durationMinutes < 60,
                            increment: { durationMinutes += 1 }
                        )

                        valueAdjustRow(
                            title: isChinese ? "最少人数" : "Min Players",
                            valueText: "\(minPlayers)",
                            canDecrement: minPlayers > 1,
                            decrement: { minPlayers -= 1 },
                            canIncrement: minPlayers < 20,
                            increment: { minPlayers += 1 }
                        )
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "描述" : "Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        TextEditor(text: $description)
                            .font(.system(size: 14))
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(10)
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "说明" : "Instructions")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 8) {
                                TextField(
                                    isChinese ? "步骤 \(index + 1)" : "Step \(index + 1)",
                                    text: Binding(
                                        get: { instructions[index] },
                                        set: { instructions[index] = $0 }
                                    )
                                )
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                                Button {
                                    instructions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .frame(width: 30, height: 30)
                                        .background(AppTheme.surfaceColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(isChinese ? "添加步骤" : "Add step", text: $newInstruction)
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                            Button {
                                let clean = newInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                instructions.append(clean)
                                newInstruction = ""
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isChinese ? "添加" : "Add")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "要点" : "Key Points")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)

                        ForEach(Array(keyPoints.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 8) {
                                TextField(
                                    isChinese ? "要点 \(index + 1)" : "Point \(index + 1)",
                                    text: Binding(
                                        get: { keyPoints[index] },
                                        set: { keyPoints[index] = $0 }
                                    )
                                )
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                                Button {
                                    keyPoints.remove(at: index)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .frame(width: 30, height: 30)
                                        .background(AppTheme.surfaceColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(isChinese ? "添加要点" : "Add key point", text: $newKeyPoint)
                                .padding(10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)

                            Button {
                                let clean = newKeyPoint.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                keyPoints.append(clean)
                                newKeyPoint = ""
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isChinese ? "添加" : "Add")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)

                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "编辑训练" : "Edit Drill")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        saveDrill()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveDrill() {
        var updated = drill
        updated.name = name
        updated.category = category
        updated.difficulty = difficulty
        updated.durationMinutes = durationMinutes
        updated.description = description
        updated.instructions = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.keyPoints = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        updated.minPlayers = minPlayers
        updated.updatedAt = Date()
        
        dataManager.updateDrill(updated)
        dismiss()
    }

    private func valueAdjustRow(
        title: String,
        valueText: String,
        canDecrement: Bool,
        decrement: @escaping () -> Void,
        canIncrement: Bool,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            Text("\(title): \(valueText)")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 0) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canDecrement ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 34, height: 30)
                }
                .disabled(!canDecrement)

                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 1, height: 18)

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canIncrement ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 34, height: 30)
                }
                .disabled(!canIncrement)
            }
            .background(AppTheme.surfaceColor)
            .clipShape(Capsule())
        }
    }
}
#endif

#Preview {
    DrillsLibraryView()
        .environmentObject(DataManager.shared)
}
