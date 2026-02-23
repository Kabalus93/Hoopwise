import SwiftUI

// MARK: - Session Page View (Recreated - Legacy)
/// This is a legacy view - FlightySessionPageView is the primary implementation
struct SessionPageView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State var session: SessionEvent
    let accessMode: SessionAccessMode
    
    var body: some View {
        // Redirect to Flighty version
        FlightySessionPageView(session: session, accessMode: accessMode)
    }
}

// MARK: - Edit Session Details View
struct EditSessionDetailsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var session: SessionEvent
    var onSave: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session Details") {
                    TextField("Title", text: $session.title)
                    DatePicker("Date", selection: $session.date, displayedComponents: .date)
                    DatePicker("Start Time", selection: $session.startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $session.endTime, displayedComponents: .hourAndMinute)
                }
                
                Section("Location") {
                    TextField("Location", text: Binding(
                        get: { session.location ?? "" },
                        set: { session.location = $0.isEmpty ? nil : $0 }
                    ))
                }
                
                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { session.notes ?? "" },
                        set: { session.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dataManager.updateSessionEvent(session)
                        onSave?()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Drill Picker View
struct DrillPickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedDrillIds: [UUID]
    var onSave: (() -> Void)? = nil
    
    // Search and filter state
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory? = nil
    @State private var selectedDifficulty: DifficultyLevel? = nil
    @State private var showFavoritesOnly = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    init(selectedDrillIds: Binding<[UUID]>, onSave: (() -> Void)? = nil) {
        self._selectedDrillIds = selectedDrillIds
        self.onSave = onSave
    }
    
    var filteredDrills: [DrillItem] {
        var result = dataManager.drills
        
        // Search filter
        if !searchText.isEmpty {
            result = result.filter { drill in
                drill.name.localizedCaseInsensitiveContains(searchText) ||
                drill.localizedName.localizedCaseInsensitiveContains(searchText) ||
                drill.description.localizedCaseInsensitiveContains(searchText) ||
                drill.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Category filter
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        
        // Difficulty filter
        if let diff = selectedDifficulty {
            result = result.filter { $0.difficulty == diff }
        }
        
        // Favorites filter
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Filter chips
                filterChips
                
                // Drill list
                if filteredDrills.isEmpty {
                    emptyState
                } else {
                    drillList
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isChinese ? "选择训练" : "SELECT DRILLS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        onSave?()
                        dismiss()
                    }) {
                        Text(isChinese ? "完成" : "DONE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
            
            TextField("", text: $searchText, prompt: Text(isChinese ? "搜索训练..." : "Search drills...").foregroundColor(.white.opacity(0.3)))
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
    }
    
    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Favorites filter
                filterButton(
                    isSelected: showFavoritesOnly,
                    title: isChinese ? "收藏" : "Favorites",
                    icon: "heart.fill",
                    color: .pink
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFavoritesOnly.toggle()
                    }
                }
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.2))
                
                // Category: All
                categoryButton(nil, title: isChinese ? "全部" : "All")
                
                // Category options
                ForEach(DrillCategory.allCases, id: \.self) { cat in
                    categoryButton(cat, title: cat.localizedName)
                }
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.2))
                
                // Difficulty options
                difficultyButton(nil, title: isChinese ? "所有难度" : "Any Level")
                ForEach(DifficultyLevel.allCases, id: \.self) { diff in
                    difficultyButton(diff, title: diff.localizedName)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: showFavoritesOnly ? "heart.slash" : (searchText.isEmpty ? "figure.basketball" : "magnifyingglass"))
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            
            Text(emptyStateTitle)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            
            Text(emptyStateSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            
            if hasActiveFilters {
                Button(action: clearFilters) {
                    Text(isChinese ? "清除筛选" : "Clear Filters")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateTitle: String {
        if showFavoritesOnly {
            return isChinese ? "暂无收藏训练" : "NO FAVORITES"
        } else if !searchText.isEmpty {
            return isChinese ? "未找到训练" : "NO DRILLS FOUND"
        } else {
            return isChinese ? "暂无训练" : "NO DRILLS AVAILABLE"
        }
    }
    
    private var emptyStateSubtitle: String {
        if showFavoritesOnly {
            return isChinese ? "在训练详情中点击心形图标收藏" : "Tap the heart icon in drill details to add favorites"
        } else if !searchText.isEmpty {
            return isChinese ? "尝试其他搜索词或筛选条件" : "Try different search terms or filters"
        } else {
            return isChinese ? "在训练库中添加训练" : "Add drills in the Drill Library"
        }
    }
    
    private var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedCategory != nil || selectedDifficulty != nil || showFavoritesOnly
    }
    
    private func clearFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            searchText = ""
            selectedCategory = nil
            selectedDifficulty = nil
            showFavoritesOnly = false
        }
    }
    
    // MARK: - Drill List
    private var drillList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                // Selected count header
                if !selectedDrillIds.isEmpty {
                    HStack {
                        Text(isChinese ? "已选择 \(selectedDrillIds.count) 个训练" : "\(selectedDrillIds.count) drill(s) selected")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Button(action: { selectedDrillIds.removeAll() }) {
                            Text(isChinese ? "清除" : "Clear")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
                
                ForEach(filteredDrills) { drill in
                    drillRow(drill)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Helper Views
    private func filterButton(isSelected: Bool, title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color.white.opacity(0.08))
            .cornerRadius(16)
        }
    }
    
    private func categoryButton(_ cat: DrillCategory?, title: String) -> some View {
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
                .background(isSelected ? Color.blue : Color.white.opacity(0.08))
                .cornerRadius(16)
        }
    }
    
    private func difficultyButton(_ diff: DifficultyLevel?, title: String) -> some View {
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
        let isSelected = selectedDrillIds.contains(drill.id)
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedDrillIds.removeAll { $0 == drill.id }
                } else {
                    selectedDrillIds.append(drill.id)
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
                        
                        // Difficulty stars
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
                    .foregroundColor(isSelected ? .blue : .white.opacity(0.2))
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
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

// MARK: - Session Student Picker View
struct SessionStudentPickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    let students: [Student]
    @Binding var selectedStudentId: UUID?
    var onSave: (() -> Void)? = nil
    
    init(students: [Student], selectedStudentId: Binding<UUID?>, onSave: (() -> Void)? = nil) {
        self.students = students
        self._selectedStudentId = selectedStudentId
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(students) { student in
                    HStack {
                        Text(student.name)
                        Spacer()
                        if selectedStudentId == student.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedStudentId == student.id {
                            selectedStudentId = nil
                        } else {
                            selectedStudentId = student.id
                        }
                    }
                }
            }
            .navigationTitle("Select Player")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave?()
                        dismiss()
                    }
                }
            }
        }
    }
}
