import SwiftUI

struct PlaybookView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedCategory: PlayCategory?
    @State private var showFavoritesOnly = false
    @State private var showingAddPlay = false
    
    var filteredPlays: [Play] {
        var plays = dataManager.plays
        
        if !searchText.isEmpty {
            plays = plays.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            plays = plays.filter { $0.category == category }
        }
        
        if showFavoritesOnly {
            plays = plays.filter { $0.isFavorite }
        }
        
        return plays.sorted { $0.name < $1.name }
    }
    
    var groupedPlays: [PlayCategory: [Play]] {
        Dictionary(grouping: filteredPlays, by: { $0.category })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter
                categoryFilter
                
                // Plays List
                if filteredPlays.isEmpty {
                    emptyState
                } else {
                    playsList
                }
            }
            .navigationTitle("Playbook")
            .searchable(text: $searchText, prompt: "Search plays...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailingCompat) {
                    Button(action: { showingAddPlay = true }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeadingCompat) {
                    Button(action: { showFavoritesOnly.toggle() }) {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundColor(showFavoritesOnly ? .red : .primary)
                    }
                }
            }
            .sheet(isPresented: $showingAddPlay) {
                AddPlayView()
            }
        }
    }
    
    // MARK: - Category Filter
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                
                ForEach(PlayCategory.allCases, id: \.self) { category in
                    FilterChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category,
                        color: AppTheme.primaryColor
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.systemBackground)
    }
    
    // MARK: - Plays List
    private var playsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if selectedCategory == nil {
                    // Grouped by category
                    ForEach(PlayCategory.allCases, id: \.self) { category in
                        if let plays = groupedPlays[category], !plays.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color.playCategoryColor(category))
                                    Text(category.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.textTertiary)
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                    Spacer()
                                    Text("\(plays.count)")
                                        .font(AppTheme.captionFont)
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                .padding(.top, AppTheme.smallSpacing)
                                
                                ForEach(plays) { play in
                                    NavigationLink(destination: PlayDetailView(play: play)) {
                                        PlayCard(play: play) {
                                            dataManager.togglePlayFavorite(play)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    // Flat list
                    ForEach(filteredPlays) { play in
                        NavigationLink(destination: PlayDetailView(play: play)) {
                            PlayCard(play: play) {
                                dataManager.togglePlayFavorite(play)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.bottom, AppTheme.largeSpacing)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Plays Found")
                .font(.headline)
            
            if searchText.isEmpty && selectedCategory == nil {
                Text("Add your first play to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: { showingAddPlay = true }) {
                    Label("Add Play", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 50)
            } else {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Play Card (Minimalist)
struct PlayCard: View {
    let play: Play
    var onFavorite: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: play.category.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Color.playCategoryColor(play.category))
                .frame(width: 48, height: 48)
                .background(Color.playCategoryColor(play.category).opacity(0.12))
                .cornerRadius(AppTheme.smallCornerRadius)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(play.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                HStack(spacing: 12) {
                    if !play.formation.isEmpty {
                        Text(play.formation)
                            .font(AppTheme.captionFont)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    // Difficulty dots
                    DifficultyIndicator(difficulty: play.difficulty)
                }
            }
            
            Spacer()
            
            // Favorite button
            if let onFavorite = onFavorite {
                Button(action: onFavorite) {
                    Image(systemName: play.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundColor(play.isFavorite ? AppTheme.accentColor : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.spacing)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
    }
}

// MARK: - Play Detail View
struct PlayDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let play: Play
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Court Diagram Placeholder
                courtDiagramSection
                
                // Description
                if !play.description.isEmpty {
                    descriptionSection
                }
                
                // Key Teaching Points
                if !play.keyTeachingPoints.isEmpty {
                    teachingPointsSection
                }
                
                // Steps
                if !play.steps.isEmpty {
                    stepsSection
                }
                
                // Variations
                if !play.variations.isEmpty {
                    variationsSection
                }
                
                // Best Used Against
                if let bestAgainst = play.bestUsedAgainst {
                    bestAgainstSection(bestAgainst)
                }
            }
            .padding()
        }
        .navigationTitle(play.name)
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                Button(action: {
                    dataManager.togglePlayFavorite(play)
                }) {
                    Image(systemName: play.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(play.isFavorite ? .red : .primary)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: play.category.icon)
                    .font(.title2)
                    .foregroundColor(AppTheme.primaryColor)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.primaryColor.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(play.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(play.category.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if !play.formation.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(play.formation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            
            HStack {
                DifficultyIndicator(difficulty: play.difficulty)
                Text(play.difficulty.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !play.tags.isEmpty {
                    ForEach(play.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    // MARK: - Court Diagram Section
    private var courtDiagramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Court Diagram")
            
            ZStack {
                // Basketball court placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .frame(height: 200)
                
                VStack {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 50))
                        .foregroundColor(.orange.opacity(0.5))
                    
                    Text("Court diagram placeholder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .cardStyle()
        }
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Description")
            
            Text(play.description)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
    }
    
    // MARK: - Teaching Points Section
    private var teachingPointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Key Teaching Points")
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(play.keyTeachingPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text(point)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .cardStyle()
        }
    }
    
    // MARK: - Steps Section
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Steps")
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(play.steps) { step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Step \(step.stepNumber)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.primaryColor)
                                .cornerRadius(4)
                            
                            if let keyPoint = step.keyPoint {
                                Text(keyPoint)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.primaryColor)
                            }
                        }
                        
                        Text(step.description)
                            .font(.subheadline)
                    }
                    
                    if step.id != play.steps.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .cardStyle()
        }
    }
    
    // MARK: - Variations Section
    private var variationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Variations")
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(play.variations, id: \.self) { variation in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(AppTheme.primaryColor)
                            .font(.caption)
                        Text(variation)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .cardStyle()
        }
    }
    
    // MARK: - Best Against Section
    private func bestAgainstSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Best Used Against")
            
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.green)
                Text(text)
                    .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

// MARK: - Add Play View
struct AddPlayView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var category: PlayCategory = .setPlays
    @State private var formation = ""
    @State private var description = ""
    @State private var difficulty: DifficultyLevel = .intermediate
    @State private var keyPoints: [String] = [""]
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            Form {
                Section(isChinese ? "基本信息" : "Basic Info") {
                    TextField(isChinese ? "战术名称" : "Play Name", text: $name)
                    
                    Picker(isChinese ? "类别" : "Category", selection: $category) {
                        ForEach(PlayCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    
                    TextField(isChinese ? "阵型 (例如：1-4 High)" : "Formation (e.g., 1-4 High)", text: $formation)
                    
                    Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }
                
                Section(isChinese ? "描述" : "Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
                
                Section(isChinese ? "要点" : "Key Teaching Points") {
                    ForEach(keyPoints.indices, id: \.self) { index in
                        TextField(isChinese ? "要点 \(index + 1)" : "Point \(index + 1)", text: $keyPoints[index])
                    }
                    Button(isChinese ? "添加要点" : "Add Point") {
                        keyPoints.append("")
                    }
                }
            }
            .navigationTitle(isChinese ? "新战术" : "New Play")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create") {
                        createPlay()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createPlay() {
        let play = Play(
            name: name,
            category: category,
            formation: formation,
            description: description,
            keyTeachingPoints: keyPoints.filter { !$0.isEmpty },
            difficulty: difficulty
        )
        dataManager.addPlay(play)
        dismiss()
    }
}

#Preview {
    PlaybookView()
        .environmentObject(DataManager.shared)
}
