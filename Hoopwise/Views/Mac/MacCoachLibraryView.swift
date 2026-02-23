import SwiftUI

#if os(macOS)
// MARK: - Main Coach Library View
struct MacCoachLibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: LibraryTab = .drills
    @State private var searchText = ""
    @State private var selectedDrillCategory: DrillCategory? = nil
    @State private var selectedPlayCategory: PlayCategory? = nil
    @State private var selectedDifficulty: DifficultyLevel? = nil
    @State private var showingAddDrill = false
    @State private var showingAddPlay = false
    @State private var selectedDrill: DrillItem? = nil
    @State private var selectedPlay: Play? = nil
    @State private var editingDrill: DrillItem? = nil
    @State private var editingPlay: Play? = nil
    
    // Multi-select state
    @State private var isMultiSelectMode = false
    @State private var selectedDrillIDs: Set<UUID> = []
    @State private var selectedPlayIDs: Set<UUID> = []
    @State private var showingBulkDeleteAlert = false
    
    enum LibraryTab: String, CaseIterable {
        case drills = "Drills"
        case plays = "Plays"
        
        var icon: String {
            switch self {
            case .drills: return "figure.basketball"
            case .plays: return "list.clipboard"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            libraryHeader
            
            Divider()
            
            // Content
            HStack(spacing: 0) {
                // Sidebar with filters
                filterSidebar
                    .frame(width: 220)
                
                Divider()
                
                // Main content
                if selectedTab == .drills {
                    drillsContent
                } else {
                    playsContent
                }
                
                // Detail panel
                if selectedDrill != nil || selectedPlay != nil {
                    Divider()
                    detailPanel
                        .frame(width: 350)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAddDrill) {
            AddEditDrillSheet(drill: nil)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddPlay) {
            AddEditPlaySheet(play: nil)
                .environmentObject(dataManager)
        }
        .sheet(item: $editingDrill) { drill in
            AddEditDrillSheet(drill: drill)
                .environmentObject(dataManager)
        }
        .sheet(item: $editingPlay) { play in
            AddEditPlaySheet(play: play)
                .environmentObject(dataManager)
        }
        .alert("Delete Selected Items?", isPresented: $showingBulkDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                bulkDeleteItems()
            }
        } message: {
            Text("This will permanently delete \(selectedTab == .drills ? selectedDrillIDs.count : selectedPlayIDs.count) items. This action cannot be undone.")
        }
        .onChange(of: selectedTab) { _ in
            selectedDrillIDs.removeAll()
            selectedPlayIDs.removeAll()
        }
    }
    
    private func bulkDeleteItems() {
        if selectedTab == .drills {
            for id in selectedDrillIDs {
                if let drill = dataManager.drills.first(where: { $0.id == id }) {
                    dataManager.deleteDrill(drill)
                }
            }
            selectedDrillIDs.removeAll()
        } else {
            for id in selectedPlayIDs {
                if let play = dataManager.plays.first(where: { $0.id == id }) {
                    dataManager.deletePlay(play)
                }
            }
            selectedPlayIDs.removeAll()
        }
        isMultiSelectMode = false
    }
    
    // MARK: - Header
    private var libraryHeader: some View {
        HStack(spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach Resources")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Text("Library")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textTertiary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .frame(width: 200)
            
            // Multi-select toggle
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isMultiSelectMode.toggle()
                    if !isMultiSelectMode {
                        selectedDrillIDs.removeAll()
                        selectedPlayIDs.removeAll()
                    }
                }
            }) {
                Label(isMultiSelectMode ? "Cancel" : "Select", systemImage: isMultiSelectMode ? "xmark" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(isMultiSelectMode ? .red : .secondary)
            
            // Bulk delete button (shown when items selected)
            if isMultiSelectMode && (selectedDrillIDs.count > 0 || selectedPlayIDs.count > 0) {
                Button(action: { showingBulkDeleteAlert = true }) {
                    Label("Delete (\(selectedTab == .drills ? selectedDrillIDs.count : selectedPlayIDs.count))", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            // Add Button
            Button(action: {
                if selectedTab == .drills {
                    showingAddDrill = true
                } else {
                    showingAddPlay = true
                }
            }) {
                Label(selectedTab == .drills ? "New Drill" : "New Play", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentColor)
            .disabled(isMultiSelectMode)
            
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Filter Sidebar
    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Stats
                VStack(spacing: 8) {
                    HStack {
                        Text("\(dataManager.drills.count)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Spacer()
                        Text("Drills")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    HStack {
                        Text("\(dataManager.plays.count)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                        Spacer()
                        Text("Plays")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                if selectedTab == .drills {
                    drillFilters
                } else {
                    playFilters
                }
                
                // Difficulty Filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("DIFFICULTY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .tracking(1)
                    
                    ForEach(DifficultyLevel.allCases, id: \.self) { level in
                        Button(action: {
                            selectedDifficulty = selectedDifficulty == level ? nil : level
                        }) {
                            HStack(spacing: 8) {
                                HStack(spacing: 2) {
                                    ForEach(1...3, id: \.self) { i in
                                        Image(systemName: i <= level.stars ? "star.fill" : "star")
                                            .font(.system(size: 8))
                                            .foregroundColor(i <= level.stars ? .orange : .gray.opacity(0.3))
                                    }
                                }
                                Text(level.displayName)
                                    .font(.system(size: 12))
                                Spacer()
                                if selectedDifficulty == level {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppTheme.accentColor)
                                }
                            }
                            .foregroundColor(selectedDifficulty == level ? AppTheme.accentColor : AppTheme.textPrimary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(selectedDifficulty == level ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Clear Filters
                if selectedDrillCategory != nil || selectedPlayCategory != nil || selectedDifficulty != nil {
                    Button(action: {
                        selectedDrillCategory = nil
                        selectedPlayCategory = nil
                        selectedDifficulty = nil
                    }) {
                        Label("Clear Filters", systemImage: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var drillFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(1)
            
            ForEach(DrillCategory.allCases, id: \.self) { category in
                Button(action: {
                    selectedDrillCategory = selectedDrillCategory == category ? nil : category
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(categoryColor(category.color))
                            .frame(width: 20)
                        Text(category.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(drillCount(for: category))")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .foregroundColor(selectedDrillCategory == category ? AppTheme.accentColor : AppTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(selectedDrillCategory == category ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var playFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(1)
            
            ForEach(PlayCategory.allCases, id: \.self) { category in
                Button(action: {
                    selectedPlayCategory = selectedPlayCategory == category ? nil : category
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text(category.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(playCount(for: category))")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .foregroundColor(selectedPlayCategory == category ? AppTheme.accentColor : AppTheme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(selectedPlayCategory == category ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Drills Content
    private var drillsContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Select All / Deselect All in multi-select mode
                if isMultiSelectMode && !filteredDrills.isEmpty {
                    HStack {
                        Button(action: {
                            if selectedDrillIDs.count == filteredDrills.count {
                                selectedDrillIDs.removeAll()
                            } else {
                                selectedDrillIDs = Set(filteredDrills.map { $0.id })
                            }
                        }) {
                            Label(
                                selectedDrillIDs.count == filteredDrills.count ? "Deselect All" : "Select All (\(filteredDrills.count))",
                                systemImage: selectedDrillIDs.count == filteredDrills.count ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text("\(selectedDrillIDs.count) selected")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
                
                if filteredDrills.isEmpty {
                    emptyState(
                        icon: "figure.basketball",
                        title: "No Drills Found",
                        subtitle: searchText.isEmpty ? "Add your first drill to get started" : "Try adjusting your filters"
                    )
                } else {
                    ForEach(filteredDrills) { drill in
                        DrillRowCard(
                            drill: drill,
                            isSelected: selectedDrill?.id == drill.id,
                            isMultiSelectMode: isMultiSelectMode,
                            isChecked: selectedDrillIDs.contains(drill.id),
                            onSelect: {
                                if isMultiSelectMode {
                                    if selectedDrillIDs.contains(drill.id) {
                                        selectedDrillIDs.remove(drill.id)
                                    } else {
                                        selectedDrillIDs.insert(drill.id)
                                    }
                                } else {
                                    selectedDrill = drill
                                    selectedPlay = nil
                                }
                            },
                            onEdit: { editingDrill = drill },
                            onFavorite: { dataManager.toggleDrillFavorite(drill) },
                            onDelete: { dataManager.deleteDrill(drill) }
                        )
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Plays Content
    private var playsContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Select All / Deselect All in multi-select mode
                if isMultiSelectMode && !filteredPlays.isEmpty {
                    HStack {
                        Button(action: {
                            if selectedPlayIDs.count == filteredPlays.count {
                                selectedPlayIDs.removeAll()
                            } else {
                                selectedPlayIDs = Set(filteredPlays.map { $0.id })
                            }
                        }) {
                            Label(
                                selectedPlayIDs.count == filteredPlays.count ? "Deselect All" : "Select All (\(filteredPlays.count))",
                                systemImage: selectedPlayIDs.count == filteredPlays.count ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text("\(selectedPlayIDs.count) selected")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
                
                if filteredPlays.isEmpty {
                    emptyState(
                        icon: "list.clipboard",
                        title: "No Plays Found",
                        subtitle: searchText.isEmpty ? "Add your first play to get started" : "Try adjusting your filters"
                    )
                } else {
                    ForEach(filteredPlays) { play in
                        PlayRowCard(
                            play: play,
                            isSelected: selectedPlay?.id == play.id,
                            isMultiSelectMode: isMultiSelectMode,
                            isChecked: selectedPlayIDs.contains(play.id),
                            onSelect: {
                                if isMultiSelectMode {
                                    if selectedPlayIDs.contains(play.id) {
                                        selectedPlayIDs.remove(play.id)
                                    } else {
                                        selectedPlayIDs.insert(play.id)
                                    }
                                } else {
                                    selectedPlay = play
                                    selectedDrill = nil
                                }
                            },
                            onEdit: { editingPlay = play },
                            onFavorite: { dataManager.togglePlayFavorite(play) },
                            onDelete: { dataManager.deletePlay(play) }
                        )
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Detail Panel
    @ViewBuilder
    private var detailPanel: some View {
        if let drill = selectedDrill {
            DrillDetailPanel(drill: drill, onEdit: { editingDrill = drill })
        } else if let play = selectedPlay {
            PlayDetailPanel(play: play, onEdit: { editingPlay = play })
        }
    }
    
    // MARK: - Helpers
    private var filteredDrills: [DrillItem] {
        var result = dataManager.drills
        if let category = selectedDrillCategory {
            result = result.filter { $0.category == category }
        }
        if let difficulty = selectedDifficulty {
            result = result.filter { $0.difficulty == difficulty }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result.sorted { $0.isFavorite && !$1.isFavorite }
    }
    
    private var filteredPlays: [Play] {
        var result = dataManager.plays
        if let category = selectedPlayCategory {
            result = result.filter { $0.category == category }
        }
        if let difficulty = selectedDifficulty {
            result = result.filter { $0.difficulty == difficulty }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result.sorted { $0.isFavorite && !$1.isFavorite }
    }
    
    private func drillCount(for category: DrillCategory) -> Int {
        dataManager.drills.filter { $0.category == category }.count
    }
    
    private func playCount(for category: PlayCategory) -> Int {
        dataManager.plays.filter { $0.category == category }.count
    }
    
    private func categoryColor(_ name: String) -> Color {
        switch name {
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
    
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Drill Row Card
struct DrillRowCard: View {
    let drill: DrillItem
    let isSelected: Bool
    var isMultiSelectMode: Bool = false
    var isChecked: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Checkbox for multi-select
                if isMultiSelectMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isChecked ? AppTheme.accentColor : AppTheme.textTertiary)
                        .animation(.spring(response: 0.2), value: isChecked)
                }
                
                // Category Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: drill.category.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(categoryColor)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drill.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                        if drill.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Label("\(drill.durationMinutes) min", systemImage: "clock")
                        Label(drill.playerRange, systemImage: "person.2")
                        difficultyBadge
                    }
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                }
                .frame(minWidth: 120, alignment: .leading)
                
                Spacer(minLength: 8)
                
                // Actions (show on hover)
                if isHovered || isSelected {
                    HStack(spacing: 8) {
                        Button(action: onFavorite) {
                            Image(systemName: drill.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundColor(drill.isFavorite ? .orange : AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { showingDeleteAlert = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 4)
                }
                
                // Category badge
                Text(drill.category.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.12) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.accentColor : (isHovered ? AppTheme.textTertiary.opacity(0.3) : Color.clear), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isHovered ? Color.black.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .alert("Delete Drill?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private var categoryColor: Color {
        switch drill.category.color {
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
    
    private var difficultyBadge: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= drill.difficulty.stars ? .orange : .gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Play Row Card
struct PlayRowCard: View {
    let play: Play
    let isSelected: Bool
    var isMultiSelectMode: Bool = false
    var isChecked: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Checkbox for multi-select
                if isMultiSelectMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isChecked ? AppTheme.accentColor : AppTheme.textTertiary)
                        .animation(.spring(response: 0.2), value: isChecked)
                }
                
                // Category Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: play.category.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(play.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                        if play.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if !play.formation.isEmpty {
                            Label(play.formation, systemImage: "square.grid.2x2")
                        }
                        Label("\(play.steps.count) steps", systemImage: "list.number")
                        difficultyBadge
                    }
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                }
                .frame(minWidth: 120, alignment: .leading)
                
                Spacer(minLength: 8)
                
                // Actions (show on hover)
                if isHovered || isSelected {
                    HStack(spacing: 8) {
                        Button(action: onFavorite) {
                            Image(systemName: play.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundColor(play.isFavorite ? .orange : AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { showingDeleteAlert = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 4)
                }
                
                // Category badge
                Text(play.category.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.12) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.accentColor : (isHovered ? AppTheme.textTertiary.opacity(0.3) : Color.clear), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isHovered ? Color.black.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .alert("Delete Play?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private var difficultyBadge: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= play.difficulty.stars ? .orange : .gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Drill Detail Panel
struct DrillDetailPanel: View {
    @EnvironmentObject var dataManager: DataManager
    let drill: DrillItem
    let onEdit: () -> Void
    
    @State private var currentSchemeIndex = 0
    
    private var linkedSchemes: [CourtScheme] {
        dataManager.courtSchemes.filter { $0.drillId == drill.id }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Scheme Carousel (if schemes exist)
                if !linkedSchemes.isEmpty {
                    schemeCarouselSection
                }
                
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(drill.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Label(drill.category.displayName, systemImage: drill.category.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(categoryColor)
                            .cornerRadius(8)
                        
                        Label("\(drill.durationMinutes) min", systemImage: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Label(drill.playerRange, systemImage: "person.2")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    // Difficulty
                    HStack(spacing: 4) {
                        Text("Difficulty:")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { i in
                                Image(systemName: i <= drill.difficulty.stars ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(i <= drill.difficulty.stars ? .orange : .gray.opacity(0.3))
                            }
                        }
                        Text(drill.difficulty.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Description
                if !drill.description.isEmpty {
                    detailSection(title: "Description", icon: "text.alignleft") {
                        Text(drill.description)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineSpacing(4)
                    }
                }
                
                // Instructions
                if !drill.instructions.isEmpty {
                    detailSection(title: "Instructions", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(drill.instructions.enumerated()), id: \.offset) { index, instruction in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        .background(AppTheme.accentColor)
                                        .cornerRadius(10)
                                    Text(instruction)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Key Points
                if !drill.keyPoints.isEmpty {
                    detailSection(title: "Key Points", icon: "lightbulb") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(drill.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                    Text(point)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Equipment
                if !drill.equipmentNeeded.isEmpty {
                    detailSection(title: "Equipment Needed", icon: "sportscourt") {
                        FlowLayout(spacing: 6) {
                            ForEach(drill.equipmentNeeded, id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Variations
                if !drill.variations.isEmpty {
                    detailSection(title: "Variations", icon: "arrow.triangle.branch") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(drill.variations, id: \.self) { variation in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                    Text(variation)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Tags
                if !drill.tags.isEmpty {
                    detailSection(title: "Tags", icon: "tag") {
                        FlowLayout(spacing: 6) {
                            ForEach(drill.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accentColor.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var categoryColor: Color {
        switch drill.category.color {
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
    
    private func detailSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Scheme Carousel
    private var schemeCarouselSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Court Diagrams", systemImage: "sportscourt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                Text("\(currentSchemeIndex + 1) of \(linkedSchemes.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            // Carousel
            ZStack {
                // Scheme preview placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.1))
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "sportscourt")
                                .font(.system(size: 40))
                                .foregroundColor(.green.opacity(0.5))
                            
                            Text(linkedSchemes[safe: currentSchemeIndex]?.name ?? "Scheme")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            if let desc = linkedSchemes[safe: currentSchemeIndex]?.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Text("\(linkedSchemes[safe: currentSchemeIndex]?.frameCount ?? 0) frames")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .padding()
                    )
                
                // Navigation arrows
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            currentSchemeIndex = max(0, currentSchemeIndex - 1)
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(currentSchemeIndex > 0 ? .white : .white.opacity(0.3))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentSchemeIndex == 0)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            currentSchemeIndex = min(linkedSchemes.count - 1, currentSchemeIndex + 1)
                        }
                    }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(currentSchemeIndex < linkedSchemes.count - 1 ? .white : .white.opacity(0.3))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentSchemeIndex >= linkedSchemes.count - 1)
                }
                .padding(.horizontal, 8)
            }
            
            // Dot indicators
            if linkedSchemes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<linkedSchemes.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentSchemeIndex ? AppTheme.accentColor : AppTheme.textTertiary.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    currentSchemeIndex = index
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// Safe array subscript extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Play Detail Panel
struct PlayDetailPanel: View {
    let play: Play
    let onEdit: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(play.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Label(play.category.displayName, systemImage: play.category.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(8)
                        
                        if !play.formation.isEmpty {
                            Label(play.formation, systemImage: "square.grid.2x2")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    
                    // Difficulty
                    HStack(spacing: 4) {
                        Text("Difficulty:")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { i in
                                Image(systemName: i <= play.difficulty.stars ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(i <= play.difficulty.stars ? .orange : .gray.opacity(0.3))
                            }
                        }
                        Text(play.difficulty.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Description
                if !play.description.isEmpty {
                    detailSection(title: "Description", icon: "text.alignleft") {
                        Text(play.description)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineSpacing(4)
                    }
                }
                
                // Best Used Against
                if let bestAgainst = play.bestUsedAgainst, !bestAgainst.isEmpty {
                    detailSection(title: "Best Used Against", icon: "shield") {
                        Text(bestAgainst)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                
                // Steps
                if !play.steps.isEmpty {
                    detailSection(title: "Steps", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(play.steps.sorted { $0.stepNumber < $1.stepNumber }) { step in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(step.stepNumber)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 22, height: 22)
                                            .background(Color.blue)
                                            .cornerRadius(11)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(step.description)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            if let keyPoint = step.keyPoint {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "lightbulb.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.orange)
                                                    Text(keyPoint)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(AppTheme.textSecondary)
                                                        .italic()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Key Teaching Points
                if !play.keyTeachingPoints.isEmpty {
                    detailSection(title: "Key Teaching Points", icon: "lightbulb") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(play.keyTeachingPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                    Text(point)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Variations
                if !play.variations.isEmpty {
                    detailSection(title: "Variations", icon: "arrow.triangle.branch") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(play.variations, id: \.self) { variation in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                    Text(variation)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Tags
                if !play.tags.isEmpty {
                    detailSection(title: "Tags", icon: "tag") {
                        FlowLayout(spacing: 6) {
                            ForEach(play.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accentColor.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func detailSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Add/Edit Drill Sheet (Improved with AI Assistant)
struct AddEditDrillSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    let drill: DrillItem?
    
    @State private var name: String
    @State private var category: DrillCategory
    @State private var difficulty: DifficultyLevel
    @State private var durationMinutes: Int
    @State private var drillDescription: String
    @State private var instructions: [String]
    @State private var keyPoints: [String]
    @State private var equipmentNeeded: [String]
    @State private var minPlayers: Int
    @State private var maxPlayers: Int?
    @State private var variations: [String]
    @State private var videoUrl: String
    @State private var tags: [String]
    @State private var newInstruction = ""
    @State private var newKeyPoint = ""
    @State private var newEquipment = ""
    @State private var newVariation = ""
    @State private var newTag = ""
    
    // AI Assistant state
    @State private var aiPrompt = ""
    @State private var isAIProcessing = false
    @State private var showingAIPanel = true
    @State private var aiSuggestion: AIDrillSuggestion? = nil
    @State private var aiErrorMessage: String? = nil
    
    // Tab selection
    @State private var selectedTab = 0
    
    init(drill: DrillItem?) {
        self.drill = drill
        _name = State(initialValue: drill?.name ?? "")
        _category = State(initialValue: drill?.category ?? .skills)
        _difficulty = State(initialValue: drill?.difficulty ?? .beginner)
        _durationMinutes = State(initialValue: drill?.durationMinutes ?? 10)
        _drillDescription = State(initialValue: drill?.description ?? "")
        _instructions = State(initialValue: drill?.instructions ?? [])
        _keyPoints = State(initialValue: drill?.keyPoints ?? [])
        _equipmentNeeded = State(initialValue: drill?.equipmentNeeded ?? [])
        _minPlayers = State(initialValue: drill?.minPlayers ?? 1)
        _maxPlayers = State(initialValue: drill?.maxPlayers)
        _variations = State(initialValue: drill?.variations ?? [])
        _videoUrl = State(initialValue: drill?.videoUrl ?? "")
        _tags = State(initialValue: drill?.tags ?? [])
        _showingAIPanel = State(initialValue: drill == nil)
    }
    
    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader
            
            Divider()
            
            HStack(spacing: 0) {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // AI Assistant Panel (collapsible)
                        if drill == nil {
                            aiAssistantPanel
                        }
                        
                        // Tab selector
                        tabSelector
                        
                        // Tab content
                        switch selectedTab {
                        case 0:
                            basicInfoTab
                        case 1:
                            instructionsTab
                        case 2:
                            detailsTab
                        default:
                            basicInfoTab
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
                
                // Preview panel
                if !name.isEmpty || !drillDescription.isEmpty {
                    Divider()
                    previewPanel
                        .frame(width: 280)
                }
            }
        }
        .frame(width: 850, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    private var sheetHeader: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(categoryColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(drill == nil ? "Create New Drill" : "Edit Drill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(drill == nil ? "Design a training drill with AI assistance" : "Modify drill details")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            
            Button(action: saveDrill) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Drill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(categoryColor)
            .disabled(!isValid)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - AI Assistant Panel
    private var aiAssistantPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Button(action: { withAnimation(.spring(response: 0.3)) { showingAIPanel.toggle() } }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Drill Assistant")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Describe your drill idea and get suggestions")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showingAIPanel ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            if showingAIPanel {
                VStack(alignment: .leading, spacing: 12) {
                    // AI Input
                    HStack(alignment: .top, spacing: 12) {
                        TextEditor(text: $aiPrompt)
                            .font(.system(size: 13))
                            .frame(height: 80)
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                Group {
                                    if aiPrompt.isEmpty {
                                        Text("Describe your drill idea...\n\nExample: \"A dribbling drill for beginners that focuses on ball control with both hands, using cones, for about 10 minutes\"")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                            .padding(14)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                        
                        VStack(spacing: 8) {
                            Button(action: generateAISuggestion) {
                                VStack(spacing: 4) {
                                    if isAIProcessing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 18))
                                    }
                                    Text("Generate")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .frame(width: 70, height: 60)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAIProcessing)
                            
                            if aiSuggestion != nil {
                                Button(action: applyAISuggestion) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Apply")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .frame(width: 70, height: 50)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                    }

                    if let aiErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(aiErrorMessage)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }
                    
                    // Quick prompts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            quickPromptButton("Dribbling drill for beginners")
                            quickPromptButton("Shooting form practice")
                            quickPromptButton("Team passing exercise")
                            quickPromptButton("Defensive footwork")
                            quickPromptButton("Conditioning with ball")
                        }
                    }
                    
                    // AI Suggestion Preview
                    if let suggestion = aiSuggestion {
                        aiSuggestionPreview(suggestion)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.purple.opacity(0.05), .blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        )
    }
    
    private func quickPromptButton(_ text: String) -> some View {
        Button(action: { aiPrompt = text }) {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func aiSuggestionPreview(_ suggestion: AIDrillSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("AI Suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button(action: { aiSuggestion = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(suggestion.description)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(3)
                
                HStack(spacing: 12) {
                    Label(suggestion.category.displayName, systemImage: suggestion.category.icon)
                    Label("\(suggestion.duration) min", systemImage: "clock")
                    Label(suggestion.difficulty.displayName, systemImage: "star.fill")
                }
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Basic Info", icon: "info.circle", index: 0)
            tabButton(title: "Instructions", icon: "list.number", index: 1)
            tabButton(title: "Details", icon: "doc.text", index: 2)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedTab == index ? categoryColor : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Basic Info Tab
    private var basicInfoTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            formSection(title: "Drill Name", icon: "textformat", required: true) {
                TextField("Enter drill name...", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(10)
            }
            
            // Category & Difficulty
            HStack(spacing: 16) {
                formSection(title: "Category", icon: "folder") {
                    Picker("", selection: $category) {
                        ForEach(DrillCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                
                formSection(title: "Difficulty", icon: "star") {
                    Picker("", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            HStack {
                                ForEach(1...level.stars, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                }
                                Text(level.displayName)
                            }.tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Duration & Players
            HStack(spacing: 16) {
                formSection(title: "Duration", icon: "clock") {
                    HStack {
                        Slider(value: Binding(get: { Double(durationMinutes) }, set: { durationMinutes = Int($0) }), in: 5...60, step: 5)
                        Text("\(durationMinutes) min")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(categoryColor)
                            .frame(width: 55)
                    }
                }
                
                formSection(title: "Players", icon: "person.2") {
                    HStack(spacing: 12) {
                        Stepper("Min: \(minPlayers)", value: $minPlayers, in: 1...30)
                            .font(.system(size: 12))
                        Stepper("Max: \(maxPlayers ?? minPlayers)", value: Binding(get: { maxPlayers ?? minPlayers }, set: { maxPlayers = $0 }), in: minPlayers...50)
                            .font(.system(size: 12))
                    }
                }
            }
            
            // Description
            formSection(title: "Description", icon: "text.alignleft") {
                TextEditor(text: $drillDescription)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        Group {
                            if drillDescription.isEmpty {
                                Text("Describe what this drill is about...")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            }
        }
    }
    
    // MARK: - Instructions Tab
    private var instructionsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instructions
            formSection(title: "Step-by-Step Instructions", icon: "list.number") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(categoryColor)
                                .cornerRadius(11)
                            
                            Text(instruction)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Spacer()
                            
                            Button(action: { instructions.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add instruction step...", text: $newInstruction)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newInstruction.isEmpty {
                                    instructions.append(newInstruction)
                                    newInstruction = ""
                                }
                            }
                        
                        Button(action: {
                            if !newInstruction.isEmpty {
                                instructions.append(newInstruction)
                                newInstruction = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(categoryColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newInstruction.isEmpty)
                    }
                }
            }
            
            // Key Points
            formSection(title: "Key Coaching Points", icon: "lightbulb") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Button(action: { keyPoints.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add key point...", text: $newKeyPoint)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newKeyPoint.isEmpty {
                                    keyPoints.append(newKeyPoint)
                                    newKeyPoint = ""
                                }
                            }
                        
                        Button(action: {
                            if !newKeyPoint.isEmpty {
                                keyPoints.append(newKeyPoint)
                                newKeyPoint = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newKeyPoint.isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Details Tab
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Equipment
            formSection(title: "Equipment Needed", icon: "sportscourt") {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(equipmentNeeded.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 4) {
                                Text(item)
                                    .font(.system(size: 12, weight: .medium))
                                Button(action: { equipmentNeeded.remove(at: index) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add equipment...", text: $newEquipment)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newEquipment.isEmpty {
                                    equipmentNeeded.append(newEquipment)
                                    newEquipment = ""
                                }
                            }
                        
                        Button(action: {
                            if !newEquipment.isEmpty {
                                equipmentNeeded.append(newEquipment)
                                newEquipment = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .disabled(newEquipment.isEmpty)
                    }
                    
                    // Quick add equipment
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["Basketballs", "Cones", "Chairs", "Resistance bands", "Ladder"], id: \.self) { item in
                                if !equipmentNeeded.contains(item) {
                                    Button(action: { equipmentNeeded.append(item) }) {
                                        Text("+ \(item)")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            
            // Variations
            formSection(title: "Variations", icon: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(variations.enumerated()), id: \.offset) { index, variation in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(variation)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Button(action: { variations.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add variation...", text: $newVariation)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newVariation.isEmpty {
                                    variations.append(newVariation)
                                    newVariation = ""
                                }
                            }
                        
                        Button(action: {
                            if !newVariation.isEmpty {
                                variations.append(newVariation)
                                newVariation = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(categoryColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newVariation.isEmpty)
                    }
                }
            }
            
            // Tags
            formSection(title: "Tags", icon: "tag") {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.system(size: 12, weight: .medium))
                                Button(action: { tags.remove(at: index) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundColor(AppTheme.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.accentColor.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add tag...", text: $newTag)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newTag.isEmpty {
                                    tags.append(newTag.lowercased().replacingOccurrences(of: " ", with: "-"))
                                    newTag = ""
                                }
                            }
                        
                        Button(action: {
                            if !newTag.isEmpty {
                                tags.append(newTag.lowercased().replacingOccurrences(of: " ", with: "-"))
                                newTag = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.isEmpty)
                    }
                }
            }
            
            // Video URL
            formSection(title: "Video Reference (Optional)", icon: "play.rectangle") {
                TextField("https://youtube.com/...", text: $videoUrl)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Preview Panel
    private var previewPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1)
                
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(categoryColor.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: category.icon)
                                .font(.system(size: 18))
                                .foregroundColor(categoryColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.isEmpty ? "Drill Name" : name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(name.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                            
                            HStack(spacing: 6) {
                                Text(category.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(categoryColor)
                                Text("•")
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("\(durationMinutes) min")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                    
                    // Difficulty
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { i in
                            Image(systemName: i <= difficulty.stars ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(i <= difficulty.stars ? .orange : .gray.opacity(0.3))
                        }
                        Text(difficulty.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Description
                if !drillDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(drillDescription)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(4)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Instructions count
                if !instructions.isEmpty {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundColor(categoryColor)
                        Text("\(instructions.count) instructions")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Key points count
                if !keyPoints.isEmpty {
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.green)
                        Text("\(keyPoints.count) key points")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Equipment
                if !equipmentNeeded.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Equipment")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textTertiary)
                        FlowLayout(spacing: 4) {
                            ForEach(equipmentNeeded, id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Tags
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.accentColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    // MARK: - Helpers
    private func formSection<Content: View>(title: String, icon: String, required: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            content()
        }
    }
    
    private var categoryColor: Color {
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
    
    // MARK: - AI Functions
    private func generateAISuggestion() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        aiErrorMessage = nil
        isAIProcessing = true

        Task {
            let functionName = "refine_drill"
            do {
                let suggestion: AIDrillSuggestion = try await SupabaseManager.shared.invokeFunction(
                    name: functionName,
                    body: DrillRefineRequest(prompt: prompt)
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiSuggestion = suggestion
                        isAIProcessing = false
                    }
                }
            } catch {
                let fallback = generateDrillFromPrompt(prompt)
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiSuggestion = fallback
                        aiErrorMessage = "AI service unavailable — showing a best-effort suggestion."
                        isAIProcessing = false
                    }
                }
            }
        }
    }
    
    private func generateDrillFromPrompt(_ prompt: String) -> AIDrillSuggestion {
        let lowercased = prompt.lowercased()
        
        // Determine category from prompt (using available categories: shooting, offense, defense, skills, conditioning, warmup, cooldown)
        var suggestedCategory: DrillCategory = .skills
        if lowercased.contains("dribbl") || lowercased.contains("ball handling") {
            suggestedCategory = .skills
        } else if lowercased.contains("shoot") || lowercased.contains("form") {
            suggestedCategory = .shooting
        } else if lowercased.contains("pass") || lowercased.contains("offense") || lowercased.contains("attack") {
            suggestedCategory = .offense
        } else if lowercased.contains("defense") || lowercased.contains("defensive") || lowercased.contains("footwork") {
            suggestedCategory = .defense
        } else if lowercased.contains("warm") {
            suggestedCategory = .warmup
        } else if lowercased.contains("cool") || lowercased.contains("stretch") {
            suggestedCategory = .cooldown
        } else if lowercased.contains("condition") || lowercased.contains("fitness") || lowercased.contains("cardio") {
            suggestedCategory = .conditioning
        }
        
        // Determine difficulty
        var suggestedDifficulty: DifficultyLevel = .intermediate
        if lowercased.contains("beginner") || lowercased.contains("basic") || lowercased.contains("simple") {
            suggestedDifficulty = .beginner
        } else if lowercased.contains("advanced") || lowercased.contains("complex") || lowercased.contains("difficult") {
            suggestedDifficulty = .advanced
        }
        
        // Determine duration
        var suggestedDuration = 10
        if let match = prompt.range(of: #"\d+\s*(min|minute)"#, options: .regularExpression) {
            let numStr = prompt[match].filter { $0.isNumber }
            suggestedDuration = Int(numStr) ?? 10
        }
        
        // Generate drill details based on category
        let drillTemplates: [DrillCategory: (name: String, desc: String, instructions: [String], keyPoints: [String], equipment: [String])] = [
            .skills: (
                name: "Cone Weave Dribbling",
                desc: "A fundamental ball handling drill that develops control and coordination while dribbling through obstacles.",
                instructions: [
                    "Set up 5-7 cones in a straight line, spaced 3 feet apart",
                    "Start at one end with the ball in your dominant hand",
                    "Dribble through the cones using crossovers at each cone",
                    "Keep your head up and eyes forward",
                    "Return using your non-dominant hand",
                    "Repeat for the specified duration"
                ],
                keyPoints: ["Keep the ball low", "Use fingertips, not palm", "Stay in athletic stance", "Protect the ball with off-hand"],
                equipment: ["Basketballs", "Cones"]
            ),
            .shooting: (
                name: "Form Shooting Progression",
                desc: "A shooting drill focused on developing proper form and muscle memory from close range.",
                instructions: [
                    "Start 3 feet from the basket",
                    "Focus on one-hand form shots (BEEF: Balance, Eyes, Elbow, Follow-through)",
                    "Make 5 shots before moving back",
                    "Progress to 5, 8, 10, and 15 feet",
                    "Add guide hand at mid-range distances"
                ],
                keyPoints: ["Elbow under the ball", "Follow through to the rim", "Hold finish until ball hits rim", "Consistent release point"],
                equipment: ["Basketballs"]
            ),
            .offense: (
                name: "Partner Passing Circuit",
                desc: "A dynamic passing drill that develops accuracy, timing, and various pass types with a partner.",
                instructions: [
                    "Partners face each other 10-15 feet apart",
                    "Start with chest passes - 20 reps",
                    "Progress to bounce passes - 20 reps",
                    "Add overhead passes - 15 reps",
                    "Finish with one-hand push passes - 10 each hand"
                ],
                keyPoints: ["Step into passes", "Snap wrists on release", "Target partner's chest", "Receive with soft hands"],
                equipment: ["Basketballs"]
            ),
            .defense: (
                name: "Defensive Slide Ladder",
                desc: "A footwork drill that builds defensive stance endurance and lateral quickness.",
                instructions: [
                    "Start in defensive stance at baseline",
                    "Slide to free throw line, touch floor",
                    "Slide back to baseline, touch floor",
                    "Slide to half court, touch floor",
                    "Slide back to baseline",
                    "Rest 30 seconds, repeat 3-5 times"
                ],
                keyPoints: ["Stay low throughout", "Don't cross feet", "Keep hands active", "Push off back foot"],
                equipment: ["Cones"]
            ),
            .warmup: (
                name: "Dynamic Warmup Series",
                desc: "A comprehensive warmup routine to prepare players physically and mentally for practice.",
                instructions: [
                    "Jog baseline to baseline x2",
                    "High knees to half court, backpedal return",
                    "Butt kicks to half court, shuffle return",
                    "Karaoke/Carioca both directions",
                    "Walking lunges with twist",
                    "Leg swings (front/back and side/side)"
                ],
                keyPoints: ["Gradually increase intensity", "Full range of motion", "Stay light on feet", "Focus on form"],
                equipment: []
            ),
            .cooldown: (
                name: "Static Stretching Routine",
                desc: "A comprehensive cooldown routine to help players recover and prevent injury.",
                instructions: [
                    "Seated hamstring stretch - 30 seconds each leg",
                    "Quad stretch standing - 30 seconds each leg",
                    "Hip flexor stretch - 30 seconds each side",
                    "Shoulder cross-body stretch - 20 seconds each arm",
                    "Tricep overhead stretch - 20 seconds each arm",
                    "Deep breathing exercises - 1 minute"
                ],
                keyPoints: ["Hold stretches, don't bounce", "Breathe deeply throughout", "Feel the stretch, not pain", "Relax muscles completely"],
                equipment: []
            ),
            .conditioning: (
                name: "Ball Handling Conditioning",
                desc: "A conditioning drill that combines fitness with ball handling skills.",
                instructions: [
                    "Dribble baseline to baseline at 75% speed",
                    "Perform 10 stationary crossovers",
                    "Dribble back at full speed",
                    "Perform 10 between-the-legs",
                    "Rest 20 seconds",
                    "Repeat 5 times"
                ],
                keyPoints: ["Maintain ball control when tired", "Push through fatigue", "Keep head up", "Control breathing"],
                equipment: ["Basketballs"]
            )
        ]
        
        let template = drillTemplates[suggestedCategory] ?? drillTemplates[.skills]!
        
        return AIDrillSuggestion(
            name: template.name,
            category: suggestedCategory,
            difficulty: suggestedDifficulty,
            duration: suggestedDuration,
            description: template.desc,
            instructions: template.instructions,
            keyPoints: template.keyPoints,
            equipment: template.equipment,
            tags: [suggestedCategory.displayName.lowercased(), suggestedDifficulty.displayName.lowercased()],
            minPlayers: 1,
            maxPlayers: nil,
            variations: [],
            videoUrl: nil
        )
    }
    
    private func applyAISuggestion() {
        guard let suggestion = aiSuggestion else { return }
        
        withAnimation(.spring(response: 0.3)) {
            name = suggestion.name
            category = suggestion.category
            difficulty = suggestion.difficulty
            durationMinutes = suggestion.duration
            drillDescription = suggestion.description
            instructions = suggestion.instructions
            keyPoints = suggestion.keyPoints
            equipmentNeeded = suggestion.equipment
            tags = suggestion.tags
            variations = suggestion.variations
            minPlayers = suggestion.minPlayers
            maxPlayers = suggestion.maxPlayers
            videoUrl = suggestion.videoUrl ?? ""
            
            aiSuggestion = nil
            showingAIPanel = false
        }
    }
    
    private func saveDrill() {
        let d = DrillItem(
            id: drill?.id ?? UUID(),
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: drillDescription,
            instructions: instructions,
            keyPoints: keyPoints,
            equipmentNeeded: equipmentNeeded,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            variations: variations,
            videoUrl: videoUrl.isEmpty ? nil : videoUrl,
            tags: tags,
            isFavorite: drill?.isFavorite ?? false,
            createdAt: drill?.createdAt ?? Date(),
            updatedAt: Date()
        )
        if drill != nil {
            dataManager.updateDrill(d)
        } else {
            dataManager.addDrill(d)
        }
        dismiss()
    }
}

// MARK: - AI Drill Suggestion Model
struct AIDrillSuggestion: Codable {
    let name: String
    let category: DrillCategory
    let difficulty: DifficultyLevel
    let duration: Int
    let description: String
    let instructions: [String]
    let keyPoints: [String]
    let equipment: [String]
    let tags: [String]
    let minPlayers: Int
    let maxPlayers: Int?
    let variations: [String]
    let videoUrl: String?
    
    // Custom decoding to handle API category strings that don't match our enum
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decode(Int.self, forKey: .duration)
        description = try container.decode(String.self, forKey: .description)
        instructions = try container.decode([String].self, forKey: .instructions)
        keyPoints = try container.decode([String].self, forKey: .keyPoints)
        equipment = try container.decode([String].self, forKey: .equipment)
        tags = try container.decode([String].self, forKey: .tags)
        minPlayers = try container.decode(Int.self, forKey: .minPlayers)
        maxPlayers = try container.decodeIfPresent(Int.self, forKey: .maxPlayers)
        variations = try container.decode([String].self, forKey: .variations)
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        
        // Map API category string to our DrillCategory enum
        let categoryString = try container.decode(String.self, forKey: .category).lowercased()
        switch categoryString {
        case "shooting": category = .shooting
        case "offense", "passing", "teamwork": category = .offense
        case "defense", "defensive", "footwork": category = .defense
        case "skills", "dribbling", "ball handling", "ballhandling": category = .skills
        case "conditioning", "fitness", "cardio": category = .conditioning
        case "warmup", "warm-up", "warm up": category = .warmup
        case "cooldown", "cool-down", "cool down": category = .cooldown
        default: category = .skills // Default fallback
        }
        
        // Map API difficulty string to our DifficultyLevel enum
        let difficultyString = try container.decode(String.self, forKey: .difficulty).lowercased()
        switch difficultyString {
        case "beginner", "easy", "basic": difficulty = .beginner
        case "intermediate", "medium", "moderate": difficulty = .intermediate
        case "advanced", "hard", "difficult", "expert": difficulty = .advanced
        default: difficulty = .intermediate // Default fallback
        }
    }
    
    // Standard initializer for local creation
    init(name: String, category: DrillCategory, difficulty: DifficultyLevel, duration: Int, description: String, instructions: [String], keyPoints: [String], equipment: [String], tags: [String], minPlayers: Int, maxPlayers: Int?, variations: [String], videoUrl: String?) {
        self.name = name
        self.category = category
        self.difficulty = difficulty
        self.duration = duration
        self.description = description
        self.instructions = instructions
        self.keyPoints = keyPoints
        self.equipment = equipment
        self.tags = tags
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.variations = variations
        self.videoUrl = videoUrl
    }
}

struct DrillRefineRequest: Codable {
    let prompt: String
}

// MARK: - Add/Edit Play Sheet (Redesigned with AI Assistant)
struct AddEditPlaySheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    let play: Play?
    
    @State private var name: String
    @State private var category: PlayCategory
    @State private var formation: String
    @State private var playDescription: String
    @State private var difficulty: DifficultyLevel
    @State private var keyTeachingPoints: [String]
    @State private var steps: [PlayStep]
    @State private var variations: [String]
    @State private var bestUsedAgainst: String
    @State private var tags: [String]
    @State private var newKP = ""
    @State private var newVar = ""
    @State private var newTag = ""
    @State private var newStepDesc = ""
    @State private var newStepKP = ""
    
    // AI Assistant state
    @State private var aiPrompt = ""
    @State private var isAIProcessing = false
    @State private var showingAIPanel = true
    @State private var aiSuggestion: AIPlaySuggestion? = nil
    @State private var aiErrorMessage: String? = nil
    
    // Tab selection
    @State private var selectedTab = 0
    
    init(play: Play?) {
        self.play = play
        _name = State(initialValue: play?.name ?? "")
        _category = State(initialValue: play?.category ?? .setPlays)
        _formation = State(initialValue: play?.formation ?? "")
        _playDescription = State(initialValue: play?.description ?? "")
        _difficulty = State(initialValue: play?.difficulty ?? .intermediate)
        _keyTeachingPoints = State(initialValue: play?.keyTeachingPoints ?? [])
        _steps = State(initialValue: play?.steps ?? [])
        _variations = State(initialValue: play?.variations ?? [])
        _bestUsedAgainst = State(initialValue: play?.bestUsedAgainst ?? "")
        _tags = State(initialValue: play?.tags ?? [])
        _showingAIPanel = State(initialValue: play == nil)
    }
    
    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            playSheetHeader
            
            Divider()
            
            HStack(spacing: 0) {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // AI Assistant Panel (collapsible)
                        if play == nil {
                            aiAssistantPanel
                        }
                        
                        // Tab selector
                        playTabSelector
                        
                        // Tab content
                        switch selectedTab {
                        case 0:
                            playBasicInfoTab
                        case 1:
                            playStepsTab
                        case 2:
                            playStrategyTab
                        default:
                            playBasicInfoTab
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
                
                // Preview panel
                if !name.isEmpty || !playDescription.isEmpty {
                    Divider()
                    playPreviewPanel
                        .frame(width: 280)
                }
            }
        }
        .frame(width: 900, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    private var playSheetHeader: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(play == nil ? "Create New Play" : "Edit Play")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(play == nil ? "Design a strategic play with AI assistance" : "Modify play details")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            
            Button(action: savePlay) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Play")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!isValid)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - AI Assistant Panel
    private var aiAssistantPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Button(action: { withAnimation(.spring(response: 0.3)) { showingAIPanel.toggle() } }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Play Designer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Describe your play concept and get a complete breakdown")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showingAIPanel ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            if showingAIPanel {
                VStack(alignment: .leading, spacing: 12) {
                    // AI Input
                    HStack(alignment: .top, spacing: 12) {
                        TextEditor(text: $aiPrompt)
                            .font(.system(size: 13))
                            .frame(height: 80)
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                Group {
                                    if aiPrompt.isEmpty {
                                        Text("Describe your play idea...\n\nExample: \"A pick and roll play against man-to-man defense, starting from a 1-4 high formation\"")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                            .padding(14)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                        
                        VStack(spacing: 8) {
                            Button(action: generateAIPlaySuggestion) {
                                VStack(spacing: 4) {
                                    if isAIProcessing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 18))
                                    }
                                    Text("Generate")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .frame(width: 70, height: 60)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isAIProcessing)
                            
                            if aiSuggestion != nil {
                                Button(action: applyAIPlaySuggestion) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Apply")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .frame(width: 70, height: 50)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                    }
                    
                    if let aiErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(aiErrorMessage)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }
                    
                    // Quick prompts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            playQuickPromptButton("Pick and roll vs man-to-man")
                            playQuickPromptButton("Motion offense entry")
                            playQuickPromptButton("Zone attack from 1-3-1")
                            playQuickPromptButton("Fast break transition")
                            playQuickPromptButton("Out of bounds sideline")
                        }
                    }
                    
                    // AI Suggestion Preview
                    if let suggestion = aiSuggestion {
                        aiPlaySuggestionPreview(suggestion)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.blue.opacity(0.05), .cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LinearGradient(colors: [.blue.opacity(0.2), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        )
    }
    
    private func playQuickPromptButton(_ text: String) -> some View {
        Button(action: { aiPrompt = text }) {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func aiPlaySuggestionPreview(_ suggestion: AIPlaySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("AI Suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button(action: { aiSuggestion = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(suggestion.description)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(3)
                
                HStack(spacing: 12) {
                    Label(suggestion.category.displayName, systemImage: suggestion.category.icon)
                    Label(suggestion.formation, systemImage: "square.grid.2x2")
                    Label("\(suggestion.steps.count) steps", systemImage: "list.number")
                }
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Tab Selector
    private var playTabSelector: some View {
        HStack(spacing: 0) {
            playTabButton(title: "Basic Info", icon: "info.circle", index: 0)
            playTabButton(title: "Steps", icon: "list.number", index: 1)
            playTabButton(title: "Strategy", icon: "target", index: 2)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func playTabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedTab == index ? Color.blue : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Basic Info Tab
    private var playBasicInfoTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            playFormSection(title: "Play Name", icon: "textformat", required: true) {
                TextField("Enter play name...", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(10)
            }
            
            // Category & Difficulty
            HStack(spacing: 16) {
                playFormSection(title: "Category", icon: "folder") {
                    Picker("", selection: $category) {
                        ForEach(PlayCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                
                playFormSection(title: "Difficulty", icon: "star") {
                    Picker("", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                
                playFormSection(title: "Formation", icon: "square.grid.2x2") {
                    TextField("e.g., 1-4 High", text: $formation)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
            }
            
            // Description
            playFormSection(title: "Description", icon: "text.alignleft") {
                TextEditor(text: $playDescription)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        Group {
                            if playDescription.isEmpty {
                                Text("Describe what this play accomplishes and when to use it...")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            }
            
            // Tags
            playFormSection(title: "Tags", icon: "tag") {
                VStack(alignment: .leading, spacing: 10) {
                    if !tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                                HStack(spacing: 4) {
                                    Text("#\(tag)")
                                        .font(.system(size: 12, weight: .medium))
                                    Button(action: { tags.remove(at: index) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add tag...", text: $newTag)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newTag.isEmpty {
                                    tags.append(newTag.lowercased().replacingOccurrences(of: " ", with: "-"))
                                    newTag = ""
                                }
                            }
                        
                        Button(action: {
                            if !newTag.isEmpty {
                                tags.append(newTag.lowercased().replacingOccurrences(of: " ", with: "-"))
                                newTag = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Steps Tab
    private var playStepsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            playFormSection(title: "Play Execution Steps", icon: "list.number") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(step.stepNumber)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.blue)
                                .cornerRadius(13)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.description)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                if let keyPoint = step.keyPoint {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                        Text(keyPoint)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .italic()
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: { steps.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                    
                    // Add new step
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Step description...", text: $newStepDesc)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                        
                        HStack(spacing: 10) {
                            TextField("Key point (optional)...", text: $newStepKP)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                            
                            Button(action: {
                                if !newStepDesc.isEmpty {
                                    steps.append(PlayStep(
                                        stepNumber: steps.count + 1,
                                        description: newStepDesc,
                                        keyPoint: newStepKP.isEmpty ? nil : newStepKP
                                    ))
                                    newStepDesc = ""
                                    newStepKP = ""
                                }
                            }) {
                                Label("Add Step", systemImage: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(newStepDesc.isEmpty)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
            }
            
            // Key Teaching Points
            playFormSection(title: "Key Teaching Points", icon: "lightbulb") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(keyTeachingPoints.enumerated()), id: \.offset) { index, point in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Button(action: { keyTeachingPoints.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add teaching point...", text: $newKP)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newKP.isEmpty {
                                    keyTeachingPoints.append(newKP)
                                    newKP = ""
                                }
                            }
                        
                        Button(action: {
                            if !newKP.isEmpty {
                                keyTeachingPoints.append(newKP)
                                newKP = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newKP.isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Strategy Tab
    private var playStrategyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Best Used Against
            playFormSection(title: "Best Used Against", icon: "shield") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("e.g., Man-to-man defense, 2-3 Zone...", text: $bestUsedAgainst)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(10)
                    
                    // Quick options
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["Man-to-man", "2-3 Zone", "3-2 Zone", "1-3-1 Zone", "Full court press", "Half court trap"], id: \.self) { defense in
                                Button(action: {
                                    if bestUsedAgainst.isEmpty {
                                        bestUsedAgainst = defense
                                    } else if !bestUsedAgainst.contains(defense) {
                                        bestUsedAgainst += ", \(defense)"
                                    }
                                }) {
                                    Text("+ \(defense)")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            
            // Variations
            playFormSection(title: "Play Variations", icon: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(variations.enumerated()), id: \.offset) { index, variation in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(variation)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Button(action: { variations.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Add variation...", text: $newVar)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .onSubmit {
                                if !newVar.isEmpty {
                                    variations.append(newVar)
                                    newVar = ""
                                }
                            }
                        
                        Button(action: {
                            if !newVar.isEmpty {
                                variations.append(newVar)
                                newVar = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newVar.isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Preview Panel
    private var playPreviewPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1)
                
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: category.icon)
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.isEmpty ? "Play Name" : name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(name.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                            
                            HStack(spacing: 6) {
                                Text(category.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                if !formation.isEmpty {
                                    Text("•")
                                        .foregroundColor(AppTheme.textTertiary)
                                    Text(formation)
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                    
                    // Difficulty
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { i in
                            Image(systemName: i <= difficulty.stars ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(i <= difficulty.stars ? .orange : .gray.opacity(0.3))
                        }
                        Text(difficulty.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Steps count
                if !steps.isEmpty {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundColor(.blue)
                        Text("\(steps.count) steps")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Key points count
                if !keyTeachingPoints.isEmpty {
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.green)
                        Text("\(keyTeachingPoints.count) teaching points")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Best against
                if !bestUsedAgainst.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best Against")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(bestUsedAgainst)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Tags
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
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
                
                Spacer()
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    // MARK: - Helpers
    private func playFormSection<Content: View>(title: String, icon: String, required: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            content()
        }
    }
    
    // MARK: - AI Functions
    private func generateAIPlaySuggestion() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        aiErrorMessage = nil
        isAIProcessing = true
        
        Task {
            do {
                let suggestion: AIPlaySuggestion = try await SupabaseManager.shared.invokeFunction(
                    name: "refine_play",
                    body: PlayRefineRequest(prompt: prompt)
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiSuggestion = suggestion
                        isAIProcessing = false
                    }
                }
            } catch {
                let fallback = generatePlayFromPrompt(prompt)
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        aiSuggestion = fallback
                        aiErrorMessage = "AI service unavailable — showing a best-effort suggestion."
                        isAIProcessing = false
                    }
                }
            }
        }
    }
    
    private func generatePlayFromPrompt(_ prompt: String) -> AIPlaySuggestion {
        let lowercased = prompt.lowercased()
        
        var suggestedCategory: PlayCategory = .setPlays
        if lowercased.contains("fast break") || lowercased.contains("transition") {
            suggestedCategory = .fastBreak
        } else if lowercased.contains("out of bounds") || lowercased.contains("inbound") {
            suggestedCategory = .outOfBounds
        } else if lowercased.contains("press break") {
            suggestedCategory = .pressBreak
        } else if lowercased.contains("motion") {
            suggestedCategory = .motionOffense
        }
        
        var suggestedFormation = "1-4 High"
        if lowercased.contains("1-3-1") { suggestedFormation = "1-3-1" }
        else if lowercased.contains("2-3") { suggestedFormation = "2-3" }
        else if lowercased.contains("horns") { suggestedFormation = "Horns" }
        else if lowercased.contains("box") { suggestedFormation = "Box" }
        
        var suggestedDifficulty: DifficultyLevel = .intermediate
        if lowercased.contains("simple") || lowercased.contains("basic") { suggestedDifficulty = .beginner }
        else if lowercased.contains("advanced") || lowercased.contains("complex") { suggestedDifficulty = .advanced }
        
        return AIPlaySuggestion(
            name: "Pick and Roll Action",
            category: suggestedCategory,
            formation: suggestedFormation,
            description: "A versatile pick and roll play that creates scoring opportunities through ball screen action.",
            difficulty: suggestedDifficulty,
            steps: [
                AIPlayStep(stepNumber: 1, description: "Point guard brings ball up and calls the play", keyPoint: "Read the defense early"),
                AIPlayStep(stepNumber: 2, description: "Big man sets screen on ball handler's defender", keyPoint: "Solid screen angle"),
                AIPlayStep(stepNumber: 3, description: "Ball handler attacks off screen toward basket", keyPoint: "Turn corner tight"),
                AIPlayStep(stepNumber: 4, description: "Screener rolls to basket or pops to elbow", keyPoint: "Read help defense"),
                AIPlayStep(stepNumber: 5, description: "Weak side players space to corners", keyPoint: "Be ready to shoot")
            ],
            keyTeachingPoints: ["Read the defense", "Tight turns off screens", "Spacing is critical", "Communication"],
            variations: ["Pop instead of roll", "Slip screen early", "Double drag screen"],
            bestUsedAgainst: "Man-to-man defense",
            tags: ["pick-and-roll", "half-court", suggestedCategory.displayName.lowercased()]
        )
    }
    
    private func applyAIPlaySuggestion() {
        guard let suggestion = aiSuggestion else { return }
        
        withAnimation(.spring(response: 0.3)) {
            name = suggestion.name
            category = suggestion.category
            formation = suggestion.formation
            playDescription = suggestion.description
            difficulty = suggestion.difficulty
            steps = suggestion.steps.map { PlayStep(stepNumber: $0.stepNumber, description: $0.description, keyPoint: $0.keyPoint) }
            keyTeachingPoints = suggestion.keyTeachingPoints
            variations = suggestion.variations
            bestUsedAgainst = suggestion.bestUsedAgainst ?? ""
            tags = suggestion.tags
            
            aiSuggestion = nil
            showingAIPanel = false
        }
    }
    
    private func savePlay() {
        let p = Play(
            id: play?.id ?? UUID(),
            name: name,
            category: category,
            formation: formation,
            description: playDescription,
            keyTeachingPoints: keyTeachingPoints,
            steps: steps,
            variations: variations,
            bestUsedAgainst: bestUsedAgainst.isEmpty ? nil : bestUsedAgainst,
            difficulty: difficulty,
            tags: tags,
            isFavorite: play?.isFavorite ?? false,
            createdAt: play?.createdAt ?? Date(),
            updatedAt: Date()
        )
        if play != nil {
            dataManager.updatePlay(p)
        } else {
            dataManager.addPlay(p)
        }
        dismiss()
    }
}

// MARK: - AI Play Suggestion Models
struct AIPlaySuggestion: Codable {
    let name: String
    let category: PlayCategory
    let formation: String
    let description: String
    let difficulty: DifficultyLevel
    let steps: [AIPlayStep]
    let keyTeachingPoints: [String]
    let variations: [String]
    let bestUsedAgainst: String?
    let tags: [String]
}

struct AIPlayStep: Codable {
    let stepNumber: Int
    let description: String
    let keyPoint: String?
}

struct PlayRefineRequest: Codable {
    let prompt: String
}
#endif
