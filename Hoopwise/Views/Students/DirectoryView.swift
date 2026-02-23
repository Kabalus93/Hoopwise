import SwiftUI

struct DirectoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedCategory: AgeGroup?
    @State private var showingAddStudent = false
    
    var filteredStudents: [Student] {
        var students = dataManager.accessibleStudents
        
        if !searchText.isEmpty {
            students = students.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.chineseName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        if let category = selectedCategory {
            students = students.filter { student in
                if let categoryId = student.categoryId,
                   let cat = dataManager.category(for: categoryId) {
                    return cat.ageGroup == category
                }
                return false
            }
        }
        
        return students.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with search
                headerSection
                
                // Category Filter
                categoryFilter
                
                // Student List
                if filteredStudents.isEmpty {
                    emptyState
                } else {
                    studentList
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.smallSpacing) {
            HStack {
                Text("Students")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: { showingAddStudent = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.accentColor)
                        .clipShape(Circle())
                }
            }
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                
                TextField("Search students...", text: $searchText)
                    .font(.system(size: 16))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.smallCornerRadius)
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.top, AppTheme.spacing)
        .padding(.bottom, AppTheme.smallSpacing)
    }
    
    // MARK: - Category Filter
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCategory = nil
                    }
                }
                
                ForEach(AgeGroup.allCases, id: \.self) { group in
                    FilterChip(
                        title: group.rawValue,
                        isSelected: selectedCategory == group,
                        color: Color.ageGroupColor(group)
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = selectedCategory == group ? nil : group
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.vertical, AppTheme.smallSpacing)
        }
    }
    
    // MARK: - Student List
    private var studentList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(filteredStudents) { student in
                    NavigationLink(destination: StudentDetailView(student: student)) {
                        StudentCard(
                            student: student,
                            player: dataManager.player(for: student.id),
                            contract: dataManager.currentContract(for: student.id),
                            measurementSummary: dataManager.measurementSummary(for: student.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.bottom, AppTheme.largeSpacing)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(spacing: 6) {
                Text("No students yet")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(searchText.isEmpty ? "Add your first student to get started" : "Try a different search")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if searchText.isEmpty {
                Button(action: { showingAddStudent = true }) {
                    Text("Add Student")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 60)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Filter Chip (Minimalist)
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = AppTheme.accentColor
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color : AppTheme.surfaceColor)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DirectoryView()
        .environmentObject(DataManager.shared)
}
