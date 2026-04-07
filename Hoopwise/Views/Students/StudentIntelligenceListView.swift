import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
typealias IntelPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias IntelPlatformImage = NSImage
#endif

// MARK: - Grade Change Notification
extension Notification.Name {
    static let studentGradeChanged = Notification.Name("studentGradeChanged")
}

// MARK: - Student Intelligence List View
/// Unified student intelligence profile center with AI-powered insights
struct StudentIntelligenceListView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var debouncedSearchText = ""  // Performance: debounced for filtering
    @State private var selectedFilter: StudentFilter
    @State private var sortOption: SortOption = .riskScore
    @State private var groupOption: GroupOption = .none
    @State private var selectedStudent: Student?
    @State private var sheetStudent: Student?
    @State private var showingAddStudent = false
    @State private var expandedGroups: Set<String> = []
    @State private var currentVisibleGrade: String = ""
    @State private var userTappedGrade: String? = nil  // Track explicit user taps
    @Namespace private var gradeScrollNamespace
    
    
    init(initialFilter: StudentFilter = .all) {
        _selectedFilter = State(initialValue: initialFilter)
    }
    
    enum StudentFilter: String, CaseIterable {
        case all = "All"
        case needsAttention = "Needs Attention"
        case activeContract = "Active Contract"
        case noContract = "No Contract"
        case highRisk = "High Risk"
        
        var icon: String {
            switch self {
            case .all: return "person.2.fill"
            case .needsAttention: return "exclamationmark.circle.fill"
            case .activeContract: return "checkmark.circle.fill"
            case .noContract: return "xmark.circle.fill"
            case .highRisk: return "exclamationmark.triangle.fill"
            }
        }
        
        var localizedName: String {
            switch self {
            case .all: return rawValue
            case .needsAttention: return rawValue
            case .activeContract: return rawValue
            case .noContract: return rawValue
            case .highRisk: return rawValue
            }
        }
        var localizedNameChinese: String {
            switch self {
            case .all: return "全部"
            case .needsAttention: return "需要关注"
            case .activeContract: return "有效合同"
            case .noContract: return "无合同"
            case .highRisk: return "高风险"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case riskScore = "Risk Score"
        case name = "Name"
        case age = "Age"
        case sessionDay = "Session Day"
        case sessionsLeft = "Sessions Left"
        case lastContact = "Last Contact"
        
        var icon: String {
            switch self {
            case .riskScore: return "chart.bar.fill"
            case .name: return "textformat"
            case .age: return "birthday.cake"
            case .sessionDay: return "calendar"
            case .sessionsLeft: return "number"
            case .lastContact: return "clock.fill"
            }
        }
        
        var localizedName: String {
            switch self {
            case .riskScore: return rawValue
            case .name: return rawValue
            case .age: return rawValue
            case .sessionDay: return rawValue
            case .sessionsLeft: return rawValue
            case .lastContact: return rawValue
            }
        }
        var localizedNameChinese: String {
            switch self {
            case .riskScore: return "风险评分"
            case .name: return "姓名"
            case .age: return "年龄"
            case .sessionDay: return "课程日"
            case .sessionsLeft: return "剩余课时"
            case .lastContact: return "最近联系"
            }
        }
    }
    
    enum GroupOption: String, CaseIterable {
        case none = "None"
        case program = "Program"
        case age = "Age"
        case contract = "Contract Status"
        case risk = "Risk Level"
        
        var icon: String {
            switch self {
            case .none: return "list.bullet"
            case .program: return "rectangle.stack.fill"
            case .age: return "birthday.cake"
            case .contract: return "doc.text.fill"
            case .risk: return "exclamationmark.triangle.fill"
            }
        }
        
        var localizedName: String { rawValue }
        var localizedNameChinese: String {
            switch self {
            case .none: return "无分组"
            case .program: return "按项目"
            case .age: return "按年龄"
            case .contract: return "按合同"
            case .risk: return "按风险"
            }
        }
    }
    
    // MARK: - Performance: Cached contract lookup
    private var contractLookup: [UUID: Contract] {
        dataManager.contractsByStudentId
    }
    
    // MARK: - Performance: Cached churn risk scores (computed once per render cycle)
    private var churnRiskCache: [UUID: (level: StudentIntelligence.ChurnRiskLevel, score: Double)] {
        var cache: [UUID: (level: StudentIntelligence.ChurnRiskLevel, score: Double)] = [:]
        for student in dataManager.students {
            let contract = contractLookup[student.id]
            let assessment = StudentIntelligence.analyzeChurnRisk(
                student: student,
                contract: contract,
                attendanceRecords: [],
                performanceStats: nil
            )
            cache[student.id] = (assessment.level, assessment.score)
        }
        return cache
    }
    
    var filteredStudents: [Student] {
        var students = dataManager.students
        let contracts = contractLookup  // Single O(1) dictionary access
        let riskCache = churnRiskCache  // Pre-computed risk scores
        
        // Search filter - use debounced text for performance
        let searchQuery = debouncedSearchText
        if !searchQuery.isEmpty {
            students = students.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                ($0.chineseName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        
        // Category filter - use O(1) contract lookup
        switch selectedFilter {
        case .all:
            break
        case .needsAttention:
            students = students.filter { student in
                let contract = contracts[student.id]
                let remaining = contract.map { dataManager.sessionsRemaining(for: $0) } ?? 0
                let lowSessions = remaining <= 3
                let noRecentContact = student.lastParentContact == nil ||
                    Calendar.current.dateComponents([.day], from: student.lastParentContact!, to: Date()).day ?? 0 > 21
                return lowSessions || noRecentContact
            }
        case .activeContract:
            students = students.filter { student in
                contracts[student.id]?.status == .active
            }
        case .noContract:
            students = students.filter { student in
                contracts[student.id] == nil
            }
        case .highRisk:
            students = students.filter { student in
                let risk = riskCache[student.id]?.level ?? .low
                return risk == .high || risk == .critical
            }
        }
        
        // Sort - use cached values
        switch sortOption {
        case .riskScore:
            students.sort { (riskCache[$0.id]?.score ?? 0) < (riskCache[$1.id]?.score ?? 0) }
        case .name:
            students.sort { $0.name < $1.name }
        case .age:
            students.sort { (s1: Student, s2: Student) -> Bool in
                (s1.age ?? 0) < (s2.age ?? 0)
            }
        case .sessionDay:
            students.sort { (s1: Student, s2: Student) -> Bool in
                let day1 = getNextSessionWeekday(for: s1)
                let day2 = getNextSessionWeekday(for: s2)
                return day1 < day2
            }
        case .sessionsLeft:
            students.sort { (s1: Student, s2: Student) -> Bool in
                let c1 = contracts[s1.id]
                let c2 = contracts[s2.id]
                let r1 = c1.map { dataManager.sessionsRemaining(for: $0) } ?? 999
                let r2 = c2.map { dataManager.sessionsRemaining(for: $0) } ?? 999
                return r1 < r2
            }
        case .lastContact:
            students.sort { (s1: Student, s2: Student) -> Bool in
                (s1.lastParentContact ?? .distantPast) > (s2.lastParentContact ?? .distantPast)
            }
        }
        
        return students
    }
    
    var body: some View {
        Group {
            if shouldUseSplitView {
                NavigationSplitView {
                    NavigationStack {
                        mainContent
                    }
                } detail: {
                    if let student = selectedStudent {
                        StudentIntelligenceProfileView(studentId: student.id, embeddedInSplit: true)
                    } else {
                        ZStack {
                            AppTheme.background.ignoresSafeArea()
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "请选择学员" : "Select a student")
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            } else {
                mainContent
            }
        }
    }

    private var shouldUseSplitView: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    // MARK: - Recently Added Students
    private var recentlyAddedStudents: [Student] {
        dataManager.students
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }
    
    // MARK: - Main Content (split to help compiler)
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Fixed search bar at top
            searchBarSection
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // Two-column list fills remaining space
            studentListSection
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(LocalizationManager.shared.currentLanguage == .chinese ? "学员档案" : "Student Intelligence")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.large)
        #endif
        .toolbar { toolbarContent }
        .sheet(item: $sheetStudent) { student in
            StudentIntelligenceProfileView(studentId: student.id)
        }
        .sheet(isPresented: $showingAddStudent) {
            NavigationStack {
                AddStudentView()
            }
        }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Only show Add button if user has permission
        if authManager.canCreateStudents {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddStudent = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textTertiary)
            
            TextField(LocalizationManager.shared.currentLanguage == .chinese ? "搜索运动员..." : "Search athletes...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary)
                .onChange(of: searchText) { _, newValue in
                    // Performance: Debounce search to reduce filter operations
                    NSObject.cancelPreviousPerformRequests(withTarget: self)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        debouncedSearchText = newValue
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: { 
                    searchText = ""
                    debouncedSearchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Summary Stats (Compact inline)
    private var summaryCardsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        // Performance: Use pre-computed counts from DataManager
        let activeCount = dataManager.activeContractsCount
        let attentionCount = dataManager.studentsNeedingAttentionCount
        let highRiskCount = dataManager.highRiskStudentsCount
        
        return HStack(spacing: 0) {
            // Total
            statItem(
                value: "\(dataManager.students.count)",
                label: isChinese ? "学员" : "Athletes",
                color: .blue
            )
            
            Divider().frame(height: 28)
            
            // Active
            statItem(
                value: "\(activeCount)",
                label: isChinese ? "合同" : "Active",
                color: .green
            )
            
            Divider().frame(height: 28)
            
            // Attention
            statItem(
                value: "\(attentionCount)",
                label: isChinese ? "关注" : "Attention",
                color: attentionCount > 0 ? .orange : .gray
            )
            
            Divider().frame(height: 28)
            
            // Risk
            statItem(
                value: "\(highRiskCount)",
                label: isChinese ? "风险" : "Risk",
                color: highRiskCount > 0 ? .red : .gray
            )
        }
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Filter Section
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudentFilter.allCases, id: \.self) { filter in
                    filterPill(filter)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func filterPill(_ filter: StudentFilter) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Button(action: { selectedFilter = filter }) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12))
                Text(isChinese ? filter.localizedNameChinese : filter.localizedName)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(selectedFilter == filter ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selectedFilter == filter ? AppTheme.accentColor : AppTheme.cardBackground)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selectedFilter == filter ? Color.clear : AppTheme.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Recently Added Section
    private var recentlyAddedSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(isChinese ? "最近添加" : "Recently Added")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(recentlyAddedStudents.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Vertical list in card
            VStack(spacing: 0) {
                ForEach(recentlyAddedStudents) { student in
                    Button(action: { selectStudent(student) }) {
                        recentlyAddedRow(student)
                    }
                    .buttonStyle(.plain)
                    
                    if student.id != recentlyAddedStudents.last?.id {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 16)
                    }
                }
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 16)
        }
    }
    
    private func recentlyAddedRow(_ student: Student) -> some View {
        let daysSinceCreated = Calendar.current.dateComponents([.day], from: student.createdAt, to: Date()).day ?? 0
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return HStack(spacing: 12) {
            // Avatar
            StudentAvatarView(student: student, size: 40)
            
            // Name and date
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isChinese, let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(student.name)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    } else {
                        Text(student.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                Text(relativeTimeString(from: student.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            // New badge
            if daysSinceCreated <= 7 {
                Text(isChinese ? "新" : "New")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        
        if days == 0 {
            return isChinese ? "今天添加" : "Added today"
        } else if days == 1 {
            return isChinese ? "昨天添加" : "Added yesterday"
        } else if days < 7 {
            return isChinese ? "\(days)天前添加" : "Added \(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = isChinese ? "M月d日添加" : "MMM d"
            return isChinese ? formatter.string(from: date) : "Added \(formatter.string(from: date))"
        }
    }
    
    // MARK: - Student List (NBA-style with school grades - Two Column)
    private var studentListSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let grades = studentsByGrade
        
        // Two-column layout: Grade sidebar | Students list (fills remaining space)
        return HStack(alignment: .top, spacing: 0) {
                // Left: Grade sidebar (fixed)
                gradeSidebar(grades: grades, isChinese: isChinese)
                
                // Subtle vertical divider
                Rectangle()
                    .fill(AppTheme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .frame(width: 1)
                
                // Right: Students list (scrollable)
                studentsScrollList(grades: grades, isChinese: isChinese)
        }
        .onAppear {
            // Initialize with first grade
            if currentVisibleGrade.isEmpty, let first = grades.first {
                currentVisibleGrade = first.grade
            }
        }
    }
    
    // MARK: - Grade Sidebar (Left Column) - Liquid Glass Style
    private func gradeSidebar(grades: [(grade: String, gradeName: String, students: [Student])], isChinese: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(grades, id: \.grade) { gradeGroup in
                        let isActive = currentVisibleGrade == gradeGroup.grade
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                userTappedGrade = gradeGroup.grade
                                currentVisibleGrade = gradeGroup.grade
                            }
                        }) {
                            Text(gradeGroup.gradeName)
                                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? .primary : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background {
                                    if isActive {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .glassEffect()
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id("sidebar_\(gradeGroup.grade)")
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .frame(width: 72)
            .onChange(of: currentVisibleGrade) { _, newGrade in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    proxy.scrollTo("sidebar_\(newGrade)", anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Students Scroll List (Right Column)
    private func studentsScrollList(grades: [(grade: String, gradeName: String, students: [Student])], isChinese: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(grades, id: \.grade) { gradeGroup in
                        // Grade section header with scroll tracking
                        gradeSectionHeader(gradeName: gradeGroup.gradeName, count: gradeGroup.students.count, isChinese: isChinese)
                            .id("grade_\(gradeGroup.grade)")
                            .onAppear {
                                // Update visible grade when section appears (lightweight tracking)
                                if userTappedGrade == nil {
                                    currentVisibleGrade = gradeGroup.grade
                                }
                            }
                        
                        ForEach(gradeGroup.students) { student in
                            Button(action: { selectStudent(student) }) {
                                studentRowCompact(student: student, isChinese: isChinese)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .background(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        }
                    }
                }
            }
            .onChange(of: userTappedGrade) { _, newGrade in
                // Only scroll when user explicitly taps a grade
                if let grade = newGrade {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("grade_\(grade)", anchor: .top)
                    }
                    // Reset after scroll completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        userTappedGrade = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Grade Section Header (Right Side)
    private func gradeSectionHeader(gradeName: String, count: Int, isChinese: Bool) -> some View {
        HStack(spacing: 8) {
            Text(gradeName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.accentColor)
            
            Text("·")
                .foregroundColor(AppTheme.textTertiary)
            
            Text(isChinese ? "球员" : "Players")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }
    
    // MARK: - Compact Student Row (No Grade Column)
    private func studentRowCompact(student: Student, isChinese: Bool) -> some View {
        HStack(spacing: 10) {
            // Small avatar (no ring)
            smallAvatarView(student: student)
            
            // Name
            VStack(alignment: .leading, spacing: 1) {
                if isChinese, let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(student.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                
                // Secondary name
                if isChinese {
                    Text(student.name)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                } else if let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Performance grade badge (A/B/C)
            gradeBadge(for: student)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    // MARK: - Students Grouped by School Grade
    private var studentsByGrade: [(grade: String, gradeName: String, students: [Student])] {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let students = filteredStudents
        
        // Pre-compute all grades ONCE for sorting (avoid N^2 computation)
        let gradeCache = buildGradeCache(for: students)
        
        // Group by school grade using effective grade key
        let grouped = Dictionary(grouping: students) { student -> String in
            StudentPerformanceGrader.effectiveGradeKey(for: student) ?? "—"
        }
        
        // Sort by grade order and convert to display names
        let gradeOrder = ["K1", "K2", "K3", "P1", "P2", "P3", "P4", "P5", "P6", "M1", "M2", "M3", "H1", "H2", "H3", "H+", "—"]
        
        return grouped.map { (grade, studentsInGrade) -> (String, String, [Student]) in
            let displayName = isChinese ? gradeDisplayNameChinese(grade) : grade
            // Sort by performance grade (A first), then by name - use pre-computed cache
            let sortedStudents = studentsInGrade.sorted { s1, s2 in
                let g1 = gradeCache[s1.id] ?? .ungraded
                let g2 = gradeCache[s2.id] ?? .ungraded
                if g1 != g2 { return g1 < g2 }
                return s1.name < s2.name
            }
            return (grade, displayName, sortedStudents)
        }
        .sorted { gradeOrder.firstIndex(of: $0.0) ?? 99 < gradeOrder.firstIndex(of: $1.0) ?? 99 }
    }
    
    /// Build grade cache once for efficient lookups
    private func buildGradeCache(for students: [Student]) -> [UUID: PerformanceGrade] {
        var cache: [UUID: PerformanceGrade] = [:]
        // Just use manual overrides for now - skip expensive auto-computation during list render
        for student in students {
            cache[student.id] = student.performanceGrade ?? .ungraded
        }
        return cache
    }
    
    /// Get effective performance grade for a student (for badge display)
    private func getEffectiveGrade(for student: Student) -> PerformanceGrade {
        // For list display, just show manual override or ungraded
        // Auto-grading happens in profile view on-demand
        return student.performanceGrade ?? .ungraded
    }
    
    private func gradeDisplayNameChinese(_ grade: String) -> String {
        switch grade {
        case "K1": return "小班"
        case "K2": return "中班"
        case "K3": return "大班"
        case "P1": return "一年级"
        case "P2": return "二年级"
        case "P3": return "三年级"
        case "P4": return "四年级"
        case "P5": return "五年级"
        case "P6": return "六年级"
        case "M1": return "初一"
        case "M2": return "初二"
        case "M3": return "初三"
        case "H1": return "高一"
        case "H2": return "高二"
        case "H3": return "高三"
        case "H+": return "高中+"
        default: return "未知"
        }
    }
    
    // MARK: - NBA Style Row (Grade | Info | Photo | Name | Status)
    private func nbaStyleRow(student: Student, gradeName: String, showGrade: Bool) -> some View {
        // Performance: Use cached contract lookup instead of O(n) search
        let contract = contractLookup[student.id]
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return HStack(spacing: 0) {
            // Grade column (left side - only show for first student in grade)
            Text(showGrade ? gradeName : "")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 56, alignment: .leading)
                .padding(.leading, 12)
            
            // Subtle vertical divider
            Rectangle()
                .fill(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .frame(width: 1)
                .padding(.vertical, 8)
            
            // Student info (right side)
            HStack(spacing: 10) {
                // Small avatar (no ring)
                smallAvatarView(student: student)
                
                // Name
                VStack(alignment: .leading, spacing: 1) {
                    if isChinese, let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                    } else {
                        Text(student.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                    }
                    
                    // Secondary name
                    if isChinese {
                        Text(student.name)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    } else if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Status info (compact)
                statusBadge(contract: contract, isChinese: isChinese)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Small Avatar (No Ring)
    private func smallAvatarView(student: Student) -> some View {
        Group {
            if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                if imageUrl.hasPrefix("file://") || imageUrl.hasPrefix("/") {
                    let path = imageUrl.hasPrefix("file://") ? String(imageUrl.dropFirst(7)) : imageUrl
                    #if os(iOS)
                    if let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        smallInitialsAvatar(student: student)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        smallInitialsAvatar(student: student)
                    }
                    #endif
                } else {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            smallInitialsAvatar(student: student)
                        }
                    }
                }
            } else {
                smallInitialsAvatar(student: student)
            }
        }
    }
    
    private func smallInitialsAvatar(student: Student) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.isDark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                .frame(width: 32, height: 32)
            Text(student.initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
        }
    }
    
    private func statusBadge(contract: Contract?, isChinese: Bool) -> some View {
        Group {
            if let contract = contract {
                if contract.isPayAsYouGo {
                    Text(isChinese ? "按次" : "PAYG")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                } else {
                    let remaining = contract.remainingSessions ?? 0
                    Text(isChinese ? "\(remaining)节" : "\(remaining)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(remaining <= 3 ? .orange : AppTheme.textTertiary)
                }
            } else {
                Text(isChinese ? "无" : "—")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(width: 36, alignment: .trailing)
    }
    
    private func gradeBadge(for student: Student) -> some View {
        let grade = getEffectiveGrade(for: student)
        let color: Color = {
            switch grade {
            case .A: return Color(red: 1.0, green: 0.84, blue: 0.0)  // Gold
            case .B: return Color(red: 0.75, green: 0.75, blue: 0.75)  // Silver
            case .C: return Color(red: 0.8, green: 0.5, blue: 0.2)  // Bronze
            case .ungraded: return AppTheme.textTertiary
            }
        }()
        
        return Text(grade.displayName)
            .font(.system(size: 13, weight: grade == .ungraded ? .regular : .semibold))
            .foregroundColor(color)
            .frame(width: 24, alignment: .trailing)
    }
    
    // MARK: - Instagram Style Row
    private func instagramStyleRow(_ student: Student) -> some View {
        // Performance: Use cached lookups
        let contract = contractLookup[student.id]
        let riskLevel = churnRiskCache[student.id]?.level ?? .low
        let nextSession = getNextSession(for: student)
        
        return HStack(spacing: 14) {
            // Large circular avatar with risk ring
            ZStack {
                // Risk ring (only for high/critical)
                if riskLevel == .high || riskLevel == .critical {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [riskLevel.color, riskLevel.color.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 56, height: 56)
                }
                
                StudentAvatarView(student: student, size: 50)
            }
            
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Name row
                HStack(spacing: 6) {
                    if LocalizationManager.shared.currentLanguage == .chinese, let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(student.name)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    } else {
                        Text(student.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                
                // Subtitle - key info
                HStack(spacing: 8) {
                    // Age
                    if let age = student.age {
                        Text("\(age)y")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    // Sessions remaining
                    if let contract = contract {
                        if contract.isPayAsYouGo {
                            Text("∞")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                        } else {
                            let remaining = contract.remainingSessions ?? 0
                            Text("\(remaining) left")
                                .font(.system(size: 13))
                                .foregroundColor(remaining <= 3 ? .orange : AppTheme.textTertiary)
                        }
                    }
                    
                    // Next session day
                    if let session = nextSession {
                        Text("• \(sessionDayText(session))")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Right side - next session badge or status
            VStack(alignment: .trailing, spacing: 4) {
                if let session = nextSession {
                    nextSessionCompactBadge(session)
                } else if contract != nil {
                    Text(contract!.status.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: contract!.status.color))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func sessionDayText(_ session: SessionEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: session.date)
    }
    
    private func nextSessionCompactBadge(_ session: SessionEvent) -> some View {
        let program = session.programId.flatMap { pid in dataManager.programs.first { $0.id == pid } }
        let color = program?.mascotColor ?? AppTheme.accentColor
        
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: session.startTime)
        formatter.dateFormat = minute == 0 ? "EEE ha" : "EEE h:mma"
        let timeText = formatter.string(from: session.date)
        
        return HStack(spacing: 4) {
            if let program = program {
                Image(systemName: program.mascot.icon)
                    .font(.system(size: 10))
            }
            Text(timeText)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
    }
    
    /// Get next session for a student
    private func getNextSession(for student: Student) -> SessionEvent? {
        let now = Date()
        let enrolledProgramIds = dataManager.programs
            .filter { $0.enrolledStudentIds.contains(student.id) }
            .map { $0.id }
        
        var allProgramIds = Set(enrolledProgramIds)
        if let directProgramId = student.programId {
            allProgramIds.insert(directProgramId)
        }
        
        return dataManager.sessionEvents
            .filter { session in
                let isInProgram = !allProgramIds.isEmpty && (session.programId.map { allProgramIds.contains($0) } ?? false)
                let isAttendee = session.attendeeIds.contains(student.id)
                let isUpcoming = session.date >= now && session.status != .completed && session.status != .cancelled
                return (isInProgram || isAttendee) && isUpcoming
            }
            .sorted { $0.date < $1.date }
            .first
    }
    
    // MARK: - Grouped Students
    private var groupedStudents: [(groupName: String, students: [Student])] {
        switch groupOption {
        case .none:
            return []
        case .program:
            return groupByProgram()
        case .age:
            return groupByAge()
        case .contract:
            return groupByContract()
        case .risk:
            return groupByRisk()
        }
    }
    
    private func groupByProgram() -> [(groupName: String, students: [Student])] {
        let grouped = Dictionary(grouping: filteredStudents) { student -> String in
            let programs = dataManager.programs.filter { $0.enrolledStudentIds.contains(student.id) }
            if let program = programs.first {
                return program.name
            }
            return "No Program"
        }
        return grouped.map { (groupName: $0.key, students: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }
    
    private func groupByAge() -> [(groupName: String, students: [Student])] {
        let grouped = Dictionary(grouping: filteredStudents) { student -> String in
            guard let age = student.age else { return "Unknown Age" }
            if age < 8 { return "Under 8" }
            if age < 10 { return "8-9 years" }
            if age < 12 { return "10-11 years" }
            if age < 14 { return "12-13 years" }
            if age < 16 { return "14-15 years" }
            return "16+ years"
        }
        return grouped.map { (groupName: $0.key, students: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }
    
    private func groupByContract() -> [(groupName: String, students: [Student])] {
        let contracts = contractLookup  // Performance: Use cached lookup
        let grouped = Dictionary(grouping: filteredStudents) { student -> String in
            if let contract = contracts[student.id] {
                if contract.isPayAsYouGo {
                    return "Pay As You Go"
                }
                let remaining = dataManager.sessionsRemaining(for: contract)
                if remaining <= 3 {
                    return "Low Sessions (≤3)"
                } else if remaining <= 10 {
                    return "Medium Sessions (4-10)"
                } else {
                    return "High Sessions (>10)"
                }
            }
            return "No Active Contract"
        }
        return grouped.map { (groupName: $0.key, students: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }
    
    private func groupByRisk() -> [(groupName: String, students: [Student])] {
        let riskCache = churnRiskCache  // Performance: Use cached risk scores
        let grouped = Dictionary(grouping: filteredStudents) { student -> String in
            let risk = riskCache[student.id]?.level ?? .low
            return risk.rawValue
        }
        return grouped.map { (groupName: $0.key, students: $0.value) }
            .sorted { riskOrder($0.groupName) < riskOrder($1.groupName) }
    }
    
    private func riskOrder(_ riskName: String) -> Int {
        switch riskName {
        case "Critical": return 0
        case "High": return 1
        case "Medium": return 2
        case "Low": return 3
        default: return 4
        }
    }
    
    private func groupedSection(group: (groupName: String, students: [Student])) -> some View {
        let isExpanded = expandedGroups.contains(group.groupName)
        let maxPreviewCards = 3
        
        return VStack(alignment: .leading, spacing: 12) {
            groupHeader(groupName: group.groupName, count: group.students.count, isExpanded: isExpanded, maxPreviewCards: maxPreviewCards)
            
            if isExpanded {
                expandedStudentList(students: group.students)
            } else {
                collapsedStackPreview(students: group.students, maxPreviewCards: maxPreviewCards, groupName: group.groupName)
            }
        }
    }
    
    private func groupHeader(groupName: String, count: Int, isExpanded: Bool, maxPreviewCards: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if isExpanded {
                    expandedGroups.remove(groupName)
                } else {
                    expandedGroups.insert(groupName)
                }
            }
        }) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 20)
                
                Text(groupName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
                
                Spacer()
                
                if !isExpanded && count > maxPreviewCards {
                    Text("+\(count - maxPreviewCards) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func expandedStudentList(students: [Student]) -> some View {
        VStack(spacing: 8) {
            ForEach(students) { student in
                Button(action: { selectStudent(student) }) {
                    UnifiedStudentCard(student: student, mode: .compact, showQuickActions: false)
                        .padding(14)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func collapsedStackPreview(students: [Student], maxPreviewCards: Int, groupName: String) -> some View {
        let previewStudents = Array(students.prefix(maxPreviewCards))
        
        return ZStack {
            ForEach(Array(previewStudents.enumerated()), id: \.element.id) { index, student in
                stackedCard(student: student, index: index, totalCount: previewStudents.count)
            }
        }
        .frame(height: CGFloat(70 + (min(students.count, maxPreviewCards) - 1) * 6))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                _ = expandedGroups.insert(groupName)
            }
        }
    }
    
    private func stackedCard(student: Student, index: Int, totalCount: Int) -> some View {
        UnifiedStudentCard(student: student, mode: .compact, showQuickActions: false)
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
            .offset(y: CGFloat(index) * 6)
            .scaleEffect(1.0 - CGFloat(index) * 0.02, anchor: .top)
            .zIndex(Double(totalCount - index))
    }
    
    // MARK: - Helper Methods
    private func selectStudent(_ student: Student) {
        if shouldUseSplitView {
            selectedStudent = student
        } else {
            sheetStudent = student
        }
    }
    
    // Performance: These now use cached values from churnRiskCache
    private func getChurnRiskLevel(for student: Student) -> StudentIntelligence.ChurnRiskLevel {
        return churnRiskCache[student.id]?.level ?? .low
    }
    
    private func getChurnRiskScore(for student: Student) -> Double {
        return churnRiskCache[student.id]?.score ?? 0
    }
    
    /// Get the weekday number (1-7, Sunday=1) of the student's next session
    private func getNextSessionWeekday(for student: Student) -> Int {
        let now = Date()
        
        // Find programs where student is enrolled
        let enrolledProgramIds = dataManager.programs
            .filter { $0.enrolledStudentIds.contains(student.id) }
            .map { $0.id }
        
        var allProgramIds = Set(enrolledProgramIds)
        if let directProgramId = student.programId {
            allProgramIds.insert(directProgramId)
        }
        
        // Find next session
        let nextSession = dataManager.sessionEvents
            .filter { session in
                let isInProgram = !allProgramIds.isEmpty && (session.programId.map { allProgramIds.contains($0) } ?? false)
                let isAttendee = session.attendeeIds.contains(student.id)
                let isUpcoming = session.date >= now && session.status != .completed && session.status != .cancelled
                return (isInProgram || isAttendee) && isUpcoming
            }
            .sorted { $0.date < $1.date }
            .first
        
        guard let session = nextSession else { return 8 } // No session = sort to end
        return Calendar.current.component(.weekday, from: session.date)
    }
}

// MARK: - Student Intelligence Row
struct StudentIntelligenceRow: View {
    let student: Student
    let contract: Contract?
    let player: Player?
    let riskLevel: StudentIntelligence.ChurnRiskLevel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                studentAvatar
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(student.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        // Risk badge
                        if riskLevel == .high || riskLevel == .critical {
                            Image(systemName: riskLevel.icon)
                                .font(.system(size: 12))
                                .foregroundColor(riskLevel.color)
                        }
                    }
                    
                    // Quick stats
                    HStack(spacing: 12) {
                        if let contract = contract {
                            let remaining = contract.remainingSessions ?? 0
                            let isLow = !contract.isPayAsYouGo && remaining <= 5
                            HStack(spacing: 4) {
                                Image(systemName: contract.isPayAsYouGo ? "infinity.circle.fill" : (isLow ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                                    .font(.system(size: 10))
                                    .foregroundColor(contract.isPayAsYouGo ? .blue : (isLow ? .orange : .green))
                                Text(contract.isPayAsYouGo ? (LocalizationManager.shared.currentLanguage == .chinese ? "按次付费" : "PAYG") : (LocalizationManager.shared.currentLanguage == .chinese ? "\(remaining) 节课" : "\(remaining) sessions"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "无合同" : "No contract")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        
                        // Last contact
                        if let lastContact = student.lastParentContact {
                            let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
                            HStack(spacing: 4) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(days > 21 ? .orange : .blue)
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "\(days)天前" : "\(days)d ago")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Scorecard preview
                VStack(alignment: .trailing, spacing: 4) {
                    // Mini score indicator
                    HStack(spacing: 2) {
                        Circle()
                            .fill(riskLevel.color)
                            .frame(width: 8, height: 8)
                        Text(riskLevel.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(riskLevel.color)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(riskLevel == .critical ? riskLevel.color.opacity(0.3) : (AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var studentAvatar: some View {
        Group {
            if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                if imageUrl.hasPrefix("file://") || imageUrl.hasPrefix("/") {
                    let path = imageUrl.hasPrefix("file://") ? String(imageUrl.dropFirst(7)) : imageUrl
                    #if os(iOS)
                    if let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    } else {
                        initialsAvatar
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    } else {
                        initialsAvatar
                    }
                    #endif
                } else {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                        } else {
                            initialsAvatar
                        }
                    }
                }
            } else {
                initialsAvatar
            }
        }
    }
    
    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: student.avatarColor).opacity(0.2))
                .frame(width: 50, height: 50)
            Text(student.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(avatarColor(for: student.avatarColor))
        }
    }
    
    private func avatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .pink: return .pink
        case .indigo: return .indigo
        }
    }
}

// MARK: - Student Intelligence Profile View
struct StudentIntelligenceProfileView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    let studentId: UUID
    
    /// Always fetch current student from dataManager to reflect updates
    private var student: Student {
        dataManager.students.first { $0.id == studentId } ?? Student(id: studentId, name: "Unknown")
    }

    var embeddedInSplit: Bool = false
    
    @State private var showingAddTouchpoint = false
    @State private var showingEditStudent = false
    @State private var showingAddContract = false
    @State private var editingContract: Contract?
    @State private var showingDeleteContractConfirm = false
    @State private var contractToDelete: Contract?
    @State private var showingParentReport = false
    @State private var reportImage: IntelPlatformImage?
    @State private var showingImagePicker = false
    @State private var showingVideoPicker = false
    #if os(iOS)
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    #endif
    @State private var showingMediaGallery = false
    @State private var selectedMediaUrl: String?
    @State private var showingContactHistory = false
    @State private var showingGradeExplanation = false
    
    var contract: Contract? {
        dataManager.currentContract(for: student.id)
    }
    
    var allContracts: [Contract] {
        dataManager.allContracts(for: student.id).reversed()
    }
    
    var player: Player? {
        dataManager.players.first { $0.studentId == student.id }
    }
    
    var enrolledProgram: Program? {
        dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) }
    }
    
    var scorecard: StudentIntelligence.HolisticScorecard {
        StudentIntelligence.generateScorecard(
            student: student,
            contract: contract,
            player: player,
            attendanceRecords: [],
            seasonStats: nil
        )
    }
    
    var touchpoints: [ParentalTouchpoint] {
        student.parentalTouchpoints
    }
    
    var churnRisk: StudentIntelligence.ChurnRiskAssessment {
        StudentIntelligence.analyzeChurnRisk(
            student: student,
            contract: contract,
            attendanceRecords: [],
            performanceStats: nil,
            allContracts: allContracts,
            player: player,
            enrolledProgram: enrolledProgram,
            touchpoints: touchpoints
        )
    }
    
    var trainingStats: TrainingSessionStats {
        TrainingSessionStats.calculate(for: student.id, from: dataManager.sessionEvents)
    }
    
    var sessionCount: Int {
        trainingStats.gamesPlayed
    }
    
    var attendanceRate: Double? {
        guard let contract = contract, contract.totalSessions > 0 else { return nil }
        return Double(contract.attendedSessions) / Double(contract.totalSessions)
    }
    
    var milestones: [StudentIntelligence.Milestone] {
        StudentIntelligence.detectMilestones(
            student: student,
            contract: contract,
            attendanceRecords: []
        )
    }
    
    var body: some View {
        Group {
            if embeddedInSplit {
                profileContent
            } else {
                NavigationStack {
                    profileContent
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear {
            // Auto-compute and save grade when profile is viewed
            computeAndSaveGradeIfNeeded()
        }
    }
    
    /// Compute auto-grade and save it to student (for list view caching)
    private func computeAndSaveGradeIfNeeded() {
        // Compute the auto-grade (even if manual override exists, for history tracking)
        let allStudents = dataManager.students
        let sessions = dataManager.sessionEvents
        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        
        let computedGrade = StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: allStudents,
            sessions: sessions,
            skills: skills
        )
        
        // Only save if we got a real grade (not ungraded)
        guard computedGrade != .ungraded else { return }
        
        var updatedStudent = student
        
        // Check if grade changed from last history entry
        let lastGrade = student.gradeHistory.last?.grade
        if lastGrade != computedGrade {
            // Add to history
            let entry = GradeHistoryEntry(grade: computedGrade, date: Date(), wasManual: false)
            updatedStudent.gradeHistory.append(entry)
            
            // Post notification for grade change
            if let oldGrade = lastGrade {
                NotificationCenter.default.post(
                    name: .studentGradeChanged,
                    object: nil,
                    userInfo: [
                        "studentId": student.id,
                        "studentName": student.displayName,
                        "oldGrade": oldGrade,
                        "newGrade": computedGrade
                    ]
                )
            }
        }
        
        // Only update performanceGrade if no manual override
        if student.performanceGrade == nil {
            updatedStudent.performanceGrade = computedGrade
        }
        
        // Save if anything changed
        if updatedStudent.gradeHistory.count != student.gradeHistory.count || student.performanceGrade == nil {
            dataManager.updateStudent(updatedStudent)
        }
    }

    private func parentInfoSection(_ player: Player) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.teal)
                Text(isChinese ? "家长信息" : "Parent Info")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            if !player.parentInfo.name.isEmpty {
                HStack(spacing: 12) {
                    // Parent info - tappable to show contact history
                    Button {
                        showingContactHistory = true
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.teal.opacity(0.15))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(String(player.parentInfo.name.prefix(1)).uppercased())
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.teal)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(player.parentInfo.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(player.parentInfo.relationship)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Contact timer button - ring depletes over 7 days
                    contactTimerButton
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var contactTimerButton: some View {
        let days = daysSinceLastParentContact
        let remaining = max(0.0, 1.0 - Double(min(days, 7)) / 7.0)
        let color = contactTimerColor(days: days)
        
        return Button {
            showingAddTouchpoint = true
        } label: {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var daysSinceLastParentContact: Int {
        guard let lastContact = student.lastParentContact ?? student.parentalTouchpoints.first?.date else {
            return 999
        }
        return Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 999
    }
    
    private func contactTimerColor(days: Int) -> Color {
        if days <= 3 { return .green }
        if days <= 5 { return .yellow }
        if days <= 7 { return .orange }
        return .red
    }

    private var leaguePerformanceSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let title = isChinese ? "联赛表现" : "League Performance"
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            if let player = player {
                radarChartForPlayer(player)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func radarChartForPlayer(_ player: Player) -> some View {
        RadarChartView(
            skills: player.skills,
            accentColor: Color.avatarColor(student.avatarColor),
            loc: ReportLocalization()
        )
        .frame(height: 200)
    }

    @State private var showingGradePicker = false
    
    /// Explanation for why student is ungraded
    private var ungradedReason: String? {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        // Check if student has effective school grade
        guard let gradeKey = StudentPerformanceGrader.effectiveGradeKey(for: student) else {
            return isChinese ? "需要设置年级或出生日期" : "Set grade or birthdate to enable"
        }
        
        // Get student's games played
        let sessions = dataManager.sessionEvents
        let studentStats = TrainingSessionStats.calculate(for: student.id, from: sessions)
        let gamesNeeded = StudentPerformanceGrader.minimumGamesRequired - studentStats.gamesPlayed
        
        if gamesNeeded > 0 {
            return isChinese
                ? "还需参加 \(gamesNeeded) 场比赛"
                : "Play \(gamesNeeded) more game\(gamesNeeded > 1 ? "s" : "") to unlock"
        }
        
        // Check eligible peers
        let allStudents = dataManager.students
        let eligiblePeers = allStudents.filter { peer in
            StudentPerformanceGrader.effectiveGradeKey(for: peer) == gradeKey &&
            TrainingSessionStats.calculate(for: peer.id, from: sessions).gamesPlayed >= StudentPerformanceGrader.minimumGamesRequired
        }
        
        let peersNeeded = StudentPerformanceGrader.minimumPeersRequired - eligiblePeers.count
        if peersNeeded > 0 {
            return isChinese
                ? "同年级还需 \(peersNeeded) 名同学达到要求"
                : "\(peersNeeded) more peer\(peersNeeded > 1 ? "s" : "") needed in grade"
        }
        
        return nil
    }
    
    /// Computed effective grade (manual override or auto-computed)
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
    
    // MARK: - Performance Grade Section
    private var performanceGradeSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let currentGrade = effectiveGrade
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text(isChinese ? "能力评级" : "Performance Grade")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Current grade display - tappable for explanation
                Button {
                    if currentGrade != .ungraded {
                        showingGradeExplanation = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(currentGrade.displayName)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(gradeColor(for: currentGrade))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? currentGrade.chineseName : gradeLevelName(for: currentGrade))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            if currentGrade == .ungraded, let reason = ungradedReason {
                                Text(reason)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                            } else {
                                HStack(spacing: 4) {
                                    Text(isChinese ? "点击查看详情" : "Tap for details")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textTertiary)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Edit button
                Button {
                    showingGradePicker = true
                } label: {
                    Text(isChinese ? "修改" : "Edit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .confirmationDialog(
            isChinese ? "设置能力评级" : "Set Performance Grade",
            isPresented: $showingGradePicker,
            titleVisibility: .visible
        ) {
            Button("A - \(isChinese ? "优秀 (前25%)" : "Elite (Top 25%)")") {
                updateGrade(.A)
            }
            Button("B - \(isChinese ? "良好 (中间50%)" : "Good (Middle 50%)")") {
                updateGrade(.B)
            }
            Button("C - \(isChinese ? "一般 (后25%)" : "Developing (Bottom 25%)")") {
                updateGrade(.C)
            }
            Button(isChinese ? "自动 (清除手动设置)" : "Auto (Clear Override)") {
                updateGrade(nil)
            }
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
        }
    }
    
    private func gradeColor(for grade: PerformanceGrade) -> Color {
        switch grade {
        case .A: return Color(red: 0.85, green: 0.65, blue: 0.0)  // Gold
        case .B: return Color(red: 0.5, green: 0.5, blue: 0.5)  // Silver
        case .C: return Color(red: 0.6, green: 0.4, blue: 0.2)  // Bronze
        case .ungraded: return AppTheme.textTertiary
        }
    }
    
    private func gradeLevelName(for grade: PerformanceGrade) -> String {
        switch grade {
        case .A: return "Elite"
        case .B: return "Good"
        case .C: return "Developing"
        case .ungraded: return "Not Graded"
        }
    }
    
    private func updateGrade(_ grade: PerformanceGrade?) {
        var updatedStudent = student
        updatedStudent.performanceGrade = grade
        
        // Record in history if setting a manual grade
        if let grade = grade, grade != .ungraded {
            let lastGrade = student.gradeHistory.last?.grade
            if lastGrade != grade {
                let entry = GradeHistoryEntry(grade: grade, date: Date(), wasManual: true)
                updatedStudent.gradeHistory.append(entry)
            }
        }
        
        dataManager.updateStudent(updatedStudent)
    }
    
    // MARK: - Peer Comparison Widget
    private var peerComparisonWidget: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let gradeKey = StudentPerformanceGrader.effectiveGradeKey(for: student)
        let allStudents = dataManager.students
        let sessions = dataManager.sessionEvents
        let skillsMap = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        
        // Get peer data
        let peers = allStudents.filter { StudentPerformanceGrader.effectiveGradeKey(for: $0) == gradeKey }
        let peerMetrics: [(id: UUID, name: String, metrics: ProgramRelativeRadarMetrics)] = peers.compactMap { peer in
            let stats = TrainingSessionStats.calculate(for: peer.id, from: sessions)
            guard stats.gamesPlayed >= StudentPerformanceGrader.minimumGamesRequired else { return nil }
            let m = ProgramRelativeRadarMetrics.compute(
                for: peer.id, programId: nil, sessions: sessions,
                allStudentIds: peers.map { $0.id }, skills: skillsMap[peer.id] ?? SkillsEvaluation()
            )
            return (peer.id, peer.name, m)
        }
        
        let studentM = peerMetrics.first { $0.id == student.id }?.metrics ?? ProgramRelativeRadarMetrics(scoring: 5, playmaking: 5, rebounding: 5, defense: 5, athleticism: 5, effort: 5, hasGameData: false, gamesPlayed: 0)
        
        // Calculate averages for comparison
        let avgScoring = peerMetrics.isEmpty ? 5.0 : peerMetrics.map { $0.metrics.scoring }.reduce(0, +) / Double(peerMetrics.count)
        let avgPlaymaking = peerMetrics.isEmpty ? 5.0 : peerMetrics.map { $0.metrics.playmaking }.reduce(0, +) / Double(peerMetrics.count)
        let avgRebounding = peerMetrics.isEmpty ? 5.0 : peerMetrics.map { $0.metrics.rebounding }.reduce(0, +) / Double(peerMetrics.count)
        let avgDefense = peerMetrics.isEmpty ? 5.0 : peerMetrics.map { $0.metrics.defense }.reduce(0, +) / Double(peerMetrics.count)
        
        // Find strengths and weaknesses
        let diffs = [
            (isChinese ? "得分" : "Scoring", studentM.scoring - avgScoring),
            (isChinese ? "组织" : "Playmaking", studentM.playmaking - avgPlaymaking),
            (isChinese ? "篮板" : "Rebounding", studentM.rebounding - avgRebounding),
            (isChinese ? "防守" : "Defense", studentM.defense - avgDefense)
        ].sorted { $0.1 > $1.1 }
        
        let strengths = diffs.filter { $0.1 > 0.5 }.prefix(2)
        let weaknesses = diffs.filter { $0.1 < -0.5 }.suffix(2)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text(isChinese ? "同年级对比" : "Peer Comparison")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text(isChinese ? "\(peerMetrics.count) 人" : "\(peerMetrics.count) peers")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            // Comparison bars
            VStack(spacing: 8) {
                comparisonBar(label: isChinese ? "得分" : "Scoring", value: studentM.scoring, avg: avgScoring)
                comparisonBar(label: isChinese ? "组织" : "Playmaking", value: studentM.playmaking, avg: avgPlaymaking)
                comparisonBar(label: isChinese ? "篮板" : "Rebounding", value: studentM.rebounding, avg: avgRebounding)
                comparisonBar(label: isChinese ? "防守" : "Defense", value: studentM.defense, avg: avgDefense)
            }
            
            // Strengths & Weaknesses
            if !strengths.isEmpty || !weaknesses.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    if !strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "优势" : "Excels")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                            Text(strengths.map { $0.0 }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                    if !weaknesses.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "待提高" : "Focus Area")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                            Text(weaknesses.map { $0.0 }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Grade History Section
    private var gradeHistorySection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let history = student.gradeHistory.sorted { $0.date < $1.date }
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text(isChinese ? "评级历史" : "Grade History")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                
                // Trend indicator
                if history.count >= 2 {
                    let first = history.first!.grade
                    let last = history.last!.grade
                    if last < first {
                        Label(isChinese ? "提升" : "Improving", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    } else if last > first {
                        Label(isChinese ? "下降" : "Declining", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Label(isChinese ? "稳定" : "Stable", systemImage: "equal.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Timeline
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(history) { entry in
                        VStack(spacing: 6) {
                            // Grade circle
                            ZStack {
                                Circle()
                                    .fill(gradeColor(for: entry.grade).opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Text(entry.grade.displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(gradeColor(for: entry.grade))
                            }
                            
                            // Date
                            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            // Manual badge
                            if entry.wasManual {
                                Text(isChinese ? "手动" : "Manual")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Improvement Velocity Section
    private var improvementVelocitySection: some View {
        let velocityData = calculateVelocityData()
        return buildVelocityView(data: velocityData)
    }
    
    private func calculateVelocityData() -> (ppgFirst: Double, ppgSecond: Double, apgFirst: Double, apgSecond: Double, rpgFirst: Double, rpgSecond: Double, midpoint: Int, hasData: Bool) {
        let sessions = dataManager.sessionEvents
        
        // Get all games for this student with stats (from session.games)
        var gameStats: [(date: Date, points: Int, assists: Int, rebounds: Int)] = []
        for session in sessions {
            for game in session.games where game.status == .completed {
                if let stats = game.stats(for: student.id) {
                    gameStats.append((session.date, stats.points, stats.assists, stats.rebounds))
                }
            }
        }
        gameStats.sort { $0.date < $1.date }
        
        guard gameStats.count >= 4 else {
            return (0, 0, 0, 0, 0, 0, 0, false)
        }
        
        let midpoint = gameStats.count / 2
        let firstHalf = Array(gameStats.prefix(midpoint))
        let secondHalf = Array(gameStats.suffix(midpoint))
        
        let ppgFirst = firstHalf.isEmpty ? 0 : Double(firstHalf.map { $0.points }.reduce(0, +)) / Double(firstHalf.count)
        let ppgSecond = secondHalf.isEmpty ? 0 : Double(secondHalf.map { $0.points }.reduce(0, +)) / Double(secondHalf.count)
        let apgFirst = firstHalf.isEmpty ? 0 : Double(firstHalf.map { $0.assists }.reduce(0, +)) / Double(firstHalf.count)
        let apgSecond = secondHalf.isEmpty ? 0 : Double(secondHalf.map { $0.assists }.reduce(0, +)) / Double(secondHalf.count)
        let rpgFirst = firstHalf.isEmpty ? 0 : Double(firstHalf.map { $0.rebounds }.reduce(0, +)) / Double(firstHalf.count)
        let rpgSecond = secondHalf.isEmpty ? 0 : Double(secondHalf.map { $0.rebounds }.reduce(0, +)) / Double(secondHalf.count)
        
        return (ppgFirst, ppgSecond, apgFirst, apgSecond, rpgFirst, rpgSecond, midpoint, true)
    }
    
    @ViewBuilder
    private func buildVelocityView(data: (ppgFirst: Double, ppgSecond: Double, apgFirst: Double, apgSecond: Double, rpgFirst: Double, rpgSecond: Double, midpoint: Int, hasData: Bool)) -> some View {
        if data.hasData {
            velocityContentView(data: data)
        }
    }
    
    private func velocityContentView(data: (ppgFirst: Double, ppgSecond: Double, apgFirst: Double, apgSecond: Double, rpgFirst: Double, rpgSecond: Double, midpoint: Int, hasData: Bool)) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let ppgChange = data.ppgFirst > 0 ? (data.ppgSecond - data.ppgFirst) / data.ppgFirst : 0
        let apgChange = data.apgFirst > 0 ? (data.apgSecond - data.apgFirst) / data.apgFirst : 0
        let rpgChange = data.rpgFirst > 0 ? (data.rpgSecond - data.rpgFirst) / data.rpgFirst : 0
        let velocityScore = (ppgChange + apgChange + rpgChange) / 3.0
        
        let trendLabel: String
        let trendIcon: String
        let trendColor: Color
        
        if velocityScore > 0.15 {
            trendLabel = isChinese ? "快速进步" : "Rapid Growth"
            trendIcon = "arrow.up.right.circle.fill"
            trendColor = .green
        } else if velocityScore > 0.05 {
            trendLabel = isChinese ? "稳步提高" : "Improving"
            trendIcon = "arrow.up.right"
            trendColor = .blue
        } else if velocityScore > -0.05 {
            trendLabel = isChinese ? "稳定" : "Stable"
            trendIcon = "arrow.right"
            trendColor = .secondary
        } else {
            trendLabel = isChinese ? "需关注" : "Declining"
            trendIcon = "arrow.down.right"
            trendColor = .orange
        }
        
        return VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text(isChinese ? "进步趋势" : "Progress Trend")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: trendIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(trendLabel)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(trendColor)
            }
            
            // Stats comparison table
            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("")
                        .frame(width: 50, alignment: .leading)
                    Text(isChinese ? "前期" : "Early")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                    Text(isChinese ? "近期" : "Recent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                    Text(isChinese ? "变化" : "Change")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // PPG row
                velocityStatRow(label: "PPG", first: data.ppgFirst, second: data.ppgSecond)
                
                Divider()
                
                // APG row
                velocityStatRow(label: "APG", first: data.apgFirst, second: data.apgSecond)
                
                Divider()
                
                // RPG row
                velocityStatRow(label: "RPG", first: data.rpgFirst, second: data.rpgSecond)
            }
            .padding(12)
            .background(AppTheme.background.opacity(0.5))
            .cornerRadius(10)
            
            // Period note
            Text(isChinese ? "对比前\(data.midpoint)场与后\(data.midpoint)场表现" : "Comparing first \(data.midpoint) vs last \(data.midpoint) games")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func velocityStatRow(label: String, first: Double, second: Double) -> some View {
        let change = second - first
        let changeColor: Color = change > 0.1 ? .green : (change < -0.1 ? .orange : .secondary)
        
        return HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 50, alignment: .leading)
            
            Text(String(format: "%.1f", first))
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
            
            Text(String(format: "%.1f", second))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
            
            Text(String(format: "%+.1f", change))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(changeColor)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
    
    private func comparisonBar(label: String, value: Double, avg: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 60, alignment: .leading)
            
            GeometryReader { geo in
                let width = geo.size.width
                let valuePos = min(value / 10.0, 1.0) * width
                let avgPos = min(avg / 10.0, 1.0) * width
                
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Student value bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(value >= avg ? Color.green : Color.orange)
                        .frame(width: valuePos, height: 8)
                    
                    // Average marker
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: 12)
                        .offset(x: avgPos - 1)
                }
            }
            .frame(height: 12)
            
            Text(String(format: "%.1f", value))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(value >= avg ? .green : .orange)
                .frame(width: 30, alignment: .trailing)
        }
    }
    
    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Baseball card-style flippable profile card
                StudentProfileCardView(
                    student: student,
                    player: player,
                    trainingStats: trainingStats,
                    contract: contract,
                    churnRisk: churnRisk,
                    attendanceRate: attendanceRate,
                    sessionCount: sessionCount
                )
                
                // Performance grade editor
                performanceGradeSection
                
                // Peer comparison widget (only if graded)
                if effectiveGrade != .ungraded {
                    peerComparisonWidget
                }
                
                // Grade history timeline (if has history)
                if student.gradeHistory.count > 1 {
                    gradeHistorySection
                }
                
                // Improvement velocity (if has enough data)
                if trainingStats.gamesPlayed >= 4 {
                    improvementVelocitySection
                }
                
                // Contract info
                contractAttendanceSection
                
                // Parent info
                if let player = player {
                    parentInfoSection(player)
                }
                
                if !milestones.isEmpty {
                    milestonesSection
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Intelligence Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button(action: { showingParentReport = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(action: { showingEditStudent = true }) {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTouchpoint) {
            AddTouchpointSheet(student: student)
        }
        .sheet(isPresented: $showingEditStudent) {
            AddStudentView(student: student, player: player)
        }
        .sheet(isPresented: $showingAddContract) {
            ContractEditSheet(
                studentId: student.id,
                contract: nil,
                onSave: { newContract in
                    dataManager.addContract(newContract)
                }
            )
        }
        .sheet(item: $editingContract) { contract in
            ContractEditSheet(
                studentId: student.id,
                contract: contract,
                onSave: { updatedContract in
                    dataManager.updateContract(updatedContract)
                },
                onDelete: { contractToDelete in
                    dataManager.deleteContract(contractToDelete)
                }
            )
        }
        .sheet(isPresented: $showingParentReport) {
            ParentReportSheet(
                student: student,
                player: player,
                contract: contract,
                programName: enrolledProgram?.displayName,
                coachName: dataManager.coach.name
            )
        }
        #if os(iOS)
        .sheet(isPresented: $showingImagePicker) {
            MediaImagePicker(sourceType: imagePickerSourceType) { image in
                handleCapturedImage(image)
            }
        }
        .sheet(isPresented: $showingVideoPicker) {
            MediaVideoPicker { videoURL in
                handleCapturedVideo(videoURL)
            }
        }
        #endif
        .sheet(isPresented: $showingContactHistory) {
            ContactHistorySheet(student: student)
        }
        .sheet(isPresented: $showingGradeExplanation) {
            GradeExplanationSheet(
                student: student,
                grade: effectiveGrade,
                allStudents: dataManager.students,
                sessions: dataManager.sessionEvents,
                skills: Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
            )
        }
    }
    
    private func handleCapturedImage(_ image: IntelPlatformImage) {
        // Save image locally
        let filename = "\(student.id.uuidString)_\(Date().timeIntervalSince1970).jpg"
        if let savedPath = saveImageLocally(image, filename: filename) {
            var updatedStudent = student
            updatedStudent.mediaAssets.photoReady = true
            updatedStudent.mediaAssets.lastPhotoDate = Date()
            updatedStudent.mediaAssets.photoUrls.append(savedPath)
            updatedStudent.updatedAt = Date()
            dataManager.updateStudent(updatedStudent)
        }
    }
    
    private func handleCapturedVideo(_ videoURL: URL) {
        // Copy video to app documents
        let filename = "\(student.id.uuidString)_\(Date().timeIntervalSince1970).mov"
        if let savedPath = copyVideoLocally(from: videoURL, filename: filename) {
            var updatedStudent = student
            updatedStudent.mediaAssets.videoHighlightPending = false
            updatedStudent.mediaAssets.lastVideoDate = Date()
            updatedStudent.mediaAssets.videoUrls.append(savedPath)
            updatedStudent.updatedAt = Date()
            dataManager.updateStudent(updatedStudent)
        }
    }
    
    private func saveImageLocally(_ image: IntelPlatformImage, filename: String) -> String? {
        #if canImport(UIKit)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        #endif
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaFolder = documentsPath.appendingPathComponent("StudentMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        let filePath = mediaFolder.appendingPathComponent(filename)
        do {
            try data.write(to: filePath)
            return filePath.path
        } catch {
            return nil
        }
    }
    
    private func copyVideoLocally(from sourceURL: URL, filename: String) -> String? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaFolder = documentsPath.appendingPathComponent("StudentMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        let destinationPath = mediaFolder.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationPath)
            return destinationPath.path
        } catch {
            return nil
        }
    }

    // MARK: - Contract & Retention Section (New Design)
    private var contractAttendanceSection: some View {
        VStack(spacing: 12) {
            contractStatusCard
            retentionAnalysisCard
        }
    }
    
    private var contractStatusCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            // Header with type badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text(isChinese ? "合同状态" : "Contract Status")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                if let contract = contract {
                    Text(isChinese ? contract.typeLabelChinese : contract.typeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.indigo)
                        .cornerRadius(8)
                }
            }
            
            if let contract = contract {
                // Main stats row
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("\(contract.sessionCount)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text(isChinese ? "已参加" : "Attended")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle().fill(AppTheme.surfaceColor).frame(width: 1, height: 50)
                    
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let remaining = contract.remainingSessions {
                            Text("\(remaining)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(remaining <= 3 ? .orange : .blue)
                            Text(isChinese ? "剩余" : "Remaining")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        } else {
                            Text(contract.enrollmentDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text(isChinese ? "入学日期" : "Enrolled")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle().fill(AppTheme.surfaceColor).frame(width: 1, height: 50)
                    
                    VStack(spacing: 4) {
                        if !contract.isPayAsYouGo, let expiry = contract.expiryDate {
                            Text(expiry.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(contract.isExpired ? .red : AppTheme.textSecondary)
                            Text(contract.isExpired ? (isChinese ? "已过期" : "Expired") : (isChinese ? "到期日" : "Expires"))
                                .font(.system(size: 11))
                                .foregroundColor(contract.isExpired ? .red : AppTheme.textSecondary)
                        } else {
                            let weeks = Calendar.current.dateComponents([.weekOfYear], from: contract.enrollmentDate, to: Date()).weekOfYear ?? 0
                            Text("\(weeks)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.purple)
                            Text(isChinese ? "周" : "Weeks")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(AppTheme.surfaceColor.opacity(0.5))
                .cornerRadius(12)
                
                // View attendance history
                if contract.sessionCount > 0 {
                    NavigationLink(destination: AttendedSessionsListView(studentId: student.id)) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 12))
                            Text(isChinese ? "查看出勤记录" : "View attendance history")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.accentColor)
                        .padding(12)
                        .background(AppTheme.accentColor.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
            } else {
                Button(action: { showingAddContract = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.accentColor)
                        Text(isChinese ? "暂无合同，点击添加" : "No contract yet, tap to add")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var retentionAnalysisCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let risk = churnRisk
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header with risk level badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(riskColor(risk.level))
                    Text(isChinese ? "留存分析" : "Retention Analysis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                Text(riskLevelText(risk.level))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(riskColor(risk.level))
                    .cornerRadius(8)
            }
            
            // Retention score with gauge (higher = better retention)
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(Int(risk.score))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(riskColor(risk.level))
                    Text(isChinese ? "留存指数" : "Retention")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing).opacity(0.3))
                                .frame(height: 12)
                            
                            Circle()
                                .fill(riskColor(risk.level))
                                .frame(width: 16, height: 16)
                                .shadow(color: riskColor(risk.level).opacity(0.5), radius: 4)
                                .offset(x: geo.size.width * CGFloat(risk.score / 100) - 8)
                        }
                    }
                    .frame(height: 16)
                    
                    HStack {
                        Text(isChinese ? "低" : "Low").font(.system(size: 9)).foregroundColor(.red)
                        Spacer()
                        Text(isChinese ? "高" : "High").font(.system(size: 9)).foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(AppTheme.surfaceColor.opacity(0.5))
            .cornerRadius(12)
            
            // Key factors - tappable with actions
            if !risk.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "影响因素" : "Key Factors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    ForEach(risk.factors.filter { $0.impact != 0 }.prefix(3), id: \.name) { factor in
                        factorActionRow(factor)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func riskColor(_ level: StudentIntelligence.ChurnRiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
    
    private func riskLevelText(_ level: StudentIntelligence.ChurnRiskLevel) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch level {
        case .low: return isChinese ? "低风险" : "Low Risk"
        case .moderate: return isChinese ? "中风险" : "Moderate"
        case .high: return isChinese ? "高风险" : "High Risk"
        case .critical: return isChinese ? "危险" : "Critical"
        }
    }
    
    private func recommendationText(for factorName: String) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch factorName {
        case "Renewal Urgent", "Contract Expired":
            return isChinese ? "紧急：今天联系家长讨论续约" : "Urgent: Contact parent today about renewal"
        case "Expires This Week", "Renewal Soon", "Expires Soon":
            return isChinese ? "本周安排与家长的续约讨论" : "Schedule renewal discussion this week"
        case "Expiring Next Month":
            return isChinese ? "准备续约提案并安排家长会议" : "Prepare renewal proposal for parent meeting"
        case "Low Engagement":
            return isChinese ? "与学生沟通，了解参与度低的原因" : "Check in with student about low attendance"
        case "Poor Weekly Attendance", "Recent Decline":
            return isChinese ? "了解缺课原因，可能需要调整时间" : "Discuss schedule - may need time adjustment"
        case "Contact Overdue":
            return isChinese ? "联系家长 - 已超过60天" : "Contact parent - it's been over 60 days"
        case "Contact Due":
            return isChinese ? "安排与家长的沟通" : "Schedule a check-in with parent"
        case "Log Parent Contact":
            return isChinese ? "点击+记录家长互动" : "Tap + to log parent interaction"
        case "Follow-ups Needed":
            return isChinese ? "完成待处理的家长跟进" : "Complete pending follow-ups"
        case "New Student", "First Contract Critical Phase":
            return isChinese ? "关注新学生体验，确保满意度" : "Focus on new student experience"
        case "Struggling with Skills", "Skill Development Needed":
            return isChinese ? "提供额外支持和鼓励" : "Provide extra support and encouragement"
        case "No Active Contract":
            return isChinese ? "联系讨论注册选项" : "Reach out to discuss enrollment options"
        default:
            return isChinese ? "关注学生状态" : "Monitor student engagement"
        }
    }
    
    @ViewBuilder
    private func factorActionRow(_ factor: StudentIntelligence.ChurnRiskAssessment.RiskFactor) -> some View {
        let isPositive = factor.impact > 0
        let isNegative = factor.impact < 0
        let color: Color = isPositive ? .green : (factor.impact < -10 ? .red : .orange)
        let actionInfo = factorAction(for: factor.name)
        
        Button {
            handleFactorAction(factor.name)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(factor.localizedName)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                if isNegative, let icon = actionInfo.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accentColor)
                } else if isPositive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                
                if actionInfo.hasAction {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isNegative ? color.opacity(0.08) : AppTheme.surfaceColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!actionInfo.hasAction)
    }
    
    private func factorAction(for factorName: String) -> (icon: String?, hasAction: Bool) {
        switch factorName {
        case "Contact Overdue", "Contact Due", "Log Parent Contact":
            return ("message.fill", true)
        case "Renewal Urgent", "Contract Expired", "Expires This Week", "Renewal Soon", "Expires Soon", "Expiring Next Month", "No Active Contract":
            return ("doc.text.fill", true)
        case "Low Engagement", "Poor Weekly Attendance", "Recent Decline":
            return ("calendar", false)
        case "Follow-ups Needed":
            return ("checklist", true)
        default:
            return (nil, false)
        }
    }
    
    private func handleFactorAction(_ factorName: String) {
        switch factorName {
        case "Contact Overdue", "Contact Due", "Log Parent Contact":
            showingAddTouchpoint = true
        case "Renewal Urgent", "Contract Expired", "Expires This Week", "Renewal Soon", "Expires Soon", "Expiring Next Month", "No Active Contract":
            showingAddContract = true
        case "Follow-ups Needed":
            showingAddTouchpoint = true
        default:
            break
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Avatar
            studentAvatar(size: 80)
            
            VStack(spacing: 4) {
                Text(student.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let chineseName = student.chineseName {
                    Text(chineseName)
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                if let age = student.age {
                    Text("\(age) years old")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            // Overall score badge
            HStack(spacing: 8) {
                Image(systemName: scorecard.trend.icon)
                    .font(.system(size: 12))
                Text("\(Int(scorecard.overallScore))% Overall")
                    .font(.system(size: 14, weight: .semibold))
                Text("• \(scorecard.trend.rawValue)")
                    .font(.system(size: 12))
            }
            .foregroundColor(scorecard.trend.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(scorecard.trend.color.opacity(0.15))
            .cornerRadius(20)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.cardBackground)
        .cornerRadius(20)
    }
    
    // MARK: - Scorecard
    private var scorecardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOLISTIC SCORECARD")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            HStack(spacing: 12) {
                scorecardComponent(scorecard.financialHealth, color: .green)
                scorecardComponent(scorecard.technicalPerformance, color: .blue)
                scorecardComponent(scorecard.behavioralPatterns, color: .purple)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func scorecardComponent(_ component: StudentIntelligence.HolisticScorecard.ScoreComponent, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: component.score / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(component.score))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Text(component.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Churn Risk
    private var churnRiskSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isChinese ? "流失风险" : "CHURN RISK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: churnRisk.level.icon)
                        .font(.system(size: 12))
                    Text(isChinese ? churnRisk.level.localizedNameChinese : churnRisk.level.localizedName)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(churnRisk.level.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(churnRisk.level.color.opacity(0.15))
                .cornerRadius(8)
            }
            
            // Risk factors
            if !churnRisk.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(churnRisk.factors.prefix(3), id: \.name) { factor in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(factor.impact < 0 ? Color.red : Color.green)
                                .frame(width: 6, height: 6)
                            Text(factor.localizedDescription)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
            }
            
            // Recommendations
            if !churnRisk.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "建议" : "Recommendations")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    ForEach(churnRisk.localizedRecommendations, id: \.self) { rec in
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(rec)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(churnRisk.level.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Contract
    private func contractSection(_ contract: Contract) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CONTRACT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Text(contract.contractLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor((contract.remainingSessions ?? 0) <= 5 ? .orange : AppTheme.textPrimary)
                    Text("Sessions Left")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(contract.progressPercentage * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Complete")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                if !contract.isFullyPaid {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contract.outstandingBalance, format: .currency(code: "USD"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("Outstanding")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.surfaceColor)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.accentColor)
                        .frame(width: geo.size.width * contract.progressPercentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Milestones
    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("UPCOMING MILESTONES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            ForEach(milestones, id: \.title) { milestone in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(milestone.type.color.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: milestone.type.icon)
                            .font(.system(size: 16))
                            .foregroundColor(milestone.type.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(milestone.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(milestone.description)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(milestone.type.color.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Parent Touchpoints
    private var parentTouchpointsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isChinese ? "家长沟通" : "PARENT TOUCHPOINTS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Button(action: { showingAddTouchpoint = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            
            if let lastContact = student.lastParentContact {
                let days = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(days > 21 ? .orange : .blue)
                    Text(isChinese ? "最近联系：\(days) 天前" : "Last contact: \(days) days ago")
                        .font(.system(size: 13))
                        .foregroundColor(days > 21 ? .orange : AppTheme.textSecondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(isChinese ? "无家长联系记录" : "No parent contact logged")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
            }
            
            // Recent touchpoints
            if !student.parentalTouchpoints.isEmpty {
                ForEach(student.parentalTouchpoints.prefix(3)) { touchpoint in
                    HStack(spacing: 12) {
                        Image(systemName: touchpoint.type.icon)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(touchpoint.type.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(touchpoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        if touchpoint.followUpNeeded {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(10)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Media Assets
    private var mediaVaultSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let hasPhotos = !student.mediaAssets.photoUrls.isEmpty
        let hasVideos = !student.mediaAssets.videoUrls.isEmpty
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isChinese ? "媒体库" : "MEDIA VAULT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                if hasPhotos || hasVideos {
                    Button {
                        showingMediaGallery = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(isChinese ? "查看全部" : "View All")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.accentColor)
                    }
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                #if os(iOS)
                // Take Photo button
                Button {
                    showingImagePicker = true
                    imagePickerSourceType = .camera
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(hasPhotos ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                                .frame(width: 50, height: 50)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20))
                                .foregroundColor(hasPhotos ? .green : .blue)
                        }
                        Text(isChinese ? "拍照" : "Take Photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                // Upload Photo button
                Button {
                    showingImagePicker = true
                    imagePickerSourceType = .photoLibrary
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 50, height: 50)
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundColor(.purple)
                        }
                        Text(isChinese ? "上传照片" : "Upload")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                // Record Video button
                Button {
                    showingVideoPicker = true
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(hasVideos ? Color.green.opacity(0.15) : Color.red.opacity(0.1))
                                .frame(width: 50, height: 50)
                            Image(systemName: "video.fill")
                                .font(.system(size: 20))
                                .foregroundColor(hasVideos ? .green : .red)
                        }
                        Text(isChinese ? "视频" : "Video")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                #endif
                
                Spacer()
                
                // Count badges
                VStack(alignment: .trailing, spacing: 4) {
                    if hasPhotos {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 10))
                            Text("\(student.mediaAssets.photoUrls.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.green)
                    }
                    if hasVideos {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10))
                            Text("\(student.mediaAssets.videoUrls.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                    }
                    if !hasPhotos && !hasVideos {
                        Text(isChinese ? "无媒体" : "No media")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            // Photo thumbnails preview (show last 4)
            if hasPhotos {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(student.mediaAssets.photoUrls.suffix(4), id: \.self) { urlString in
                            mediaThumbnail(urlString: urlString, isVideo: false)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .sheet(isPresented: $showingMediaGallery) {
            MediaGallerySheet(student: student, dataManager: dataManager)
        }
    }
    
    private func mediaThumbnail(urlString: String, isVideo: Bool) -> some View {
        ZStack {
            if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
                let path = urlString.hasPrefix("file://") ? String(urlString.dropFirst(7)) : urlString
                #if canImport(UIKit)
                if let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderThumbnail(isVideo: isVideo)
                }
                #elseif canImport(AppKit)
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderThumbnail(isVideo: isVideo)
                }
                #endif
            } else {
                AsyncImage(url: URL(string: urlString)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        placeholderThumbnail(isVideo: isVideo)
                    }
                }
            }
            
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
        }
    }
    
    private func placeholderThumbnail(isVideo: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: isVideo ? "video.fill" : "photo.fill")
                    .foregroundColor(.gray)
            )
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("QUICK ACTIONS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            HStack(spacing: 12) {
                quickActionButton(icon: "message.fill", label: "Contact", color: .blue)
                quickActionButton(icon: "doc.text.fill", label: "Report", color: .green)
                quickActionButton(icon: "camera.fill", label: "Media", color: .purple)
                quickActionButton(icon: "calendar", label: "Schedule", color: .orange)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func quickActionButton(icon: String, label: String, color: Color) -> some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Avatar Helper
    private func studentAvatar(size: CGFloat) -> some View {
        Group {
            if let imageUrl = student.profileImageUrl, !imageUrl.isEmpty {
                if imageUrl.hasPrefix("file://") || imageUrl.hasPrefix("/") {
                    let path = imageUrl.hasPrefix("file://") ? String(imageUrl.dropFirst(7)) : imageUrl
                    #if os(iOS)
                    if let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        initialsAvatar(size: size)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        initialsAvatar(size: size)
                    }
                    #endif
                } else {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(Circle())
                        } else {
                            initialsAvatar(size: size)
                        }
                    }
                }
            } else {
                initialsAvatar(size: size)
            }
        }
    }
    
    private func initialsAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: student.avatarColor).opacity(0.2))
                .frame(width: size, height: size)
            Text(student.initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(avatarColor(for: student.avatarColor))
        }
    }
    
    private func avatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .pink: return .pink
        case .indigo: return .indigo
        }
    }

 }

// MARK: - Grade Explanation Sheet
struct GradeExplanationSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let student: Student
    let grade: PerformanceGrade
    let allStudents: [Student]
    let sessions: [SessionEvent]
    let skills: [UUID: SkillsEvaluation]
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    private var gradeKey: String? {
        StudentPerformanceGrader.effectiveGradeKey(for: student)
    }
    
    private var peerData: [(id: UUID, name: String, score: Double, gamesPlayed: Int)] {
        guard let key = gradeKey else { return [] }
        let peers = allStudents.filter { StudentPerformanceGrader.effectiveGradeKey(for: $0) == key }
        
        return peers.compactMap { peer in
            let stats = TrainingSessionStats.calculate(for: peer.id, from: sessions)
            guard stats.gamesPlayed >= StudentPerformanceGrader.minimumGamesRequired else { return nil }
            
            let peerSkills = skills[peer.id] ?? SkillsEvaluation()
            let metrics = ProgramRelativeRadarMetrics.compute(
                for: peer.id,
                programId: nil,
                sessions: sessions,
                allStudentIds: peers.map { $0.id },
                skills: peerSkills
            )
            let score = (metrics.scoring + metrics.playmaking + metrics.rebounding +
                        metrics.defense + metrics.athleticism + metrics.effort) / 6.0
            return (peer.id, peer.name, score, stats.gamesPlayed)
        }.sorted { $0.score > $1.score }
    }
    
    private var studentRank: Int? {
        peerData.firstIndex { $0.id == student.id }.map { $0 + 1 }
    }
    
    private var studentMetrics: ProgramRelativeRadarMetrics {
        let peers = allStudents.filter { StudentPerformanceGrader.effectiveGradeKey(for: $0) == gradeKey }
        return ProgramRelativeRadarMetrics.compute(
            for: student.id,
            programId: nil,
            sessions: sessions,
            allStudentIds: peers.map { $0.id },
            skills: skills[student.id] ?? SkillsEvaluation()
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        gradeHeader
                        rankingSection
                        breakdownSection
                        peerDistributionSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isChinese ? "评级详情" : "Grade Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }
    
    private var gradeHeader: some View {
        VStack(spacing: 8) {
            Text(grade.displayName)
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(gradeColor)
            Text(isChinese ? grade.chineseName : gradeLevelName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            if let rank = studentRank {
                Text(isChinese ? "第 \(rank) 名 / \(peerData.count) 人" : "Rank #\(rank) of \(peerData.count)")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "排名依据" : "Based On")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            let stats = TrainingSessionStats.calculate(for: student.id, from: sessions)
            HStack(spacing: 16) {
                statBadge(value: "\(stats.gamesPlayed)", label: isChinese ? "比赛" : "Games")
                statBadge(value: "\(peerData.count)", label: isChinese ? "同年级" : "Peers")
                statBadge(value: gradeKey ?? "—", label: isChinese ? "年级" : "Grade")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(AppTheme.background)
        .cornerRadius(10)
    }
    
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "能力分解" : "Score Breakdown")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            let m = studentMetrics
            VStack(spacing: 8) {
                scoreRow(label: isChinese ? "得分" : "Scoring", value: m.scoring)
                scoreRow(label: isChinese ? "组织" : "Playmaking", value: m.playmaking)
                scoreRow(label: isChinese ? "篮板" : "Rebounding", value: m.rebounding)
                scoreRow(label: isChinese ? "防守" : "Defense", value: m.defense)
                scoreRow(label: isChinese ? "运动能力" : "Athleticism", value: m.athleticism)
                scoreRow(label: isChinese ? "努力" : "Effort", value: m.effort)
                Divider()
                let avg = (m.scoring + m.playmaking + m.rebounding + m.defense + m.athleticism + m.effort) / 6.0
                scoreRow(label: isChinese ? "综合" : "Overall", value: avg, bold: true)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func scoreRow(label: String, value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: bold ? .semibold : .regular))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Text(String(format: "%.1f", value))
                .font(.system(size: 14, weight: bold ? .bold : .medium, design: .rounded))
                .foregroundColor(scoreColor(value))
        }
    }
    
    private func scoreColor(_ value: Double) -> Color {
        if value >= 7.5 { return .green }
        if value >= 5.0 { return .orange }
        return .red
    }
    
    private var peerDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "同年级分布" : "Peer Distribution")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            // Horizontal bar showing A/B/C zones
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Background zones
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(red: 0.6, green: 0.4, blue: 0.2).opacity(0.3))
                            .frame(width: width * 0.25)
                        Rectangle().fill(Color.gray.opacity(0.3))
                            .frame(width: width * 0.50)
                        Rectangle().fill(Color(red: 0.85, green: 0.65, blue: 0.0).opacity(0.3))
                            .frame(width: width * 0.25)
                    }
                    .cornerRadius(8)
                    
                    // Labels
                    HStack {
                        Text("C").font(.system(size: 10, weight: .bold)).foregroundColor(.brown)
                            .frame(width: width * 0.25)
                        Text("B").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                            .frame(width: width * 0.50)
                        Text("A").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                            .frame(width: width * 0.25)
                    }
                    
                    // Student position
                    if let rank = studentRank, peerData.count > 1 {
                        let percentile = 1.0 - (Double(rank - 1) / Double(peerData.count - 1))
                        Circle()
                            .fill(gradeColor)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: width * percentile - 8)
                    }
                }
            }
            .frame(height: 30)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var gradeColor: Color {
        switch grade {
        case .A: return Color(red: 0.85, green: 0.65, blue: 0.0)
        case .B: return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .C: return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .ungraded: return AppTheme.textTertiary
        }
    }
    
    private var gradeLevelName: String {
        switch grade {
        case .A: return "Elite (Top 25%)"
        case .B: return "Good (Middle 50%)"
        case .C: return "Developing (Bottom 25%)"
        case .ungraded: return "Not Graded"
        }
    }
}

// MARK: - Add Touchpoint Sheet
struct AddTouchpointSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    
    @State private var selectedType: ParentalTouchpoint.TouchpointType = .message
    @State private var notes = ""
    @State private var followUpNeeded = false
    @State private var followUpDate = Date().addingTimeInterval(7 * 24 * 3600)
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        contactTypeSection
                        notesSection
                        followUpSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Log Contact")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTouchpoint()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var contactTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTACT TYPE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ParentalTouchpoint.TouchpointType.allCases, id: \.self) { type in
                    typeButton(for: type)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func typeButton(for type: ParentalTouchpoint.TouchpointType) -> some View {
        Button {
            selectedType = type
            HapticFeedback.impact(.light)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                Text(type.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(selectedType == type ? .black : AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selectedType == type ? AppTheme.accentColor : AppTheme.surfaceColor)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            TextEditor(text: $notes)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 100)
                .background(AppTheme.surfaceColor)
                .cornerRadius(10)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FOLLOW UP")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            HStack {
                Image(systemName: "bell.badge")
                    .foregroundColor(AppTheme.accentColor)
                Text("Follow up needed")
                Spacer()
                Toggle("", isOn: $followUpNeeded).labelsHidden()
            }
            .padding(14)
            .background(AppTheme.surfaceColor)
            .cornerRadius(10)
            
            if followUpNeeded {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(AppTheme.warningColor)
                    Text("Follow up date")
                    Spacer()
                    DatePicker("", selection: $followUpDate, displayedComponents: .date).labelsHidden()
                }
                .padding(14)
                .background(AppTheme.surfaceColor)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .animation(.easeInOut(duration: 0.2), value: followUpNeeded)
    }
    
    private func saveTouchpoint() {
        HapticFeedback.notification(.success)
        let touchpoint = ParentalTouchpoint(
            date: Date(),
            type: selectedType,
            notes: notes.isEmpty ? nil : notes,
            followUpNeeded: followUpNeeded,
            followUpDate: followUpNeeded ? followUpDate : nil
        )
        var updatedStudent = student
        updatedStudent.parentalTouchpoints.insert(touchpoint, at: 0)
        updatedStudent.lastParentContact = Date()
        updatedStudent.updatedAt = Date()
        dataManager.updateStudent(updatedStudent)
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        StudentIntelligenceListView()
            .environmentObject(DataManager.shared)
    }
}

// MARK: - Student Import View
// Inline definition to ensure it's always in scope
struct StudentImportView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if os(macOS)
        StudentImportContent()
        #else
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Import is only available on macOS")
                .font(.headline)
        }
        .padding()
        #endif
    }
}

#if os(macOS)
import UniformTypeIdentifiers

// MARK: - Student Import Content (macOS only)
struct StudentImportContent: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isFilePickerPresented = false
    @State private var importedStudents: [SimpleImportRow] = []
    @State private var importError: String?
    @State private var showingError = false
    @State private var importComplete = false
    @State private var importedCount = 0
    
    struct SimpleImportRow: Identifiable {
        let id = UUID()
        var name: String
        var phone: String?
        var amount: String?
        var isSelected: Bool = true
    }
    
    var selectedCount: Int {
        importedStudents.filter { $0.isSelected }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("导入学生 Import Students")
                        .font(.system(size: 16, weight: .bold))
                    Text("从CSV文件导入 Import from CSV")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            if importedStudents.isEmpty {
                // File selection
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor.opacity(0.6))
                    Text("选择CSV文件")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Select a CSV file to import")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Button(action: { isFilePickerPresented = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("选择文件 Choose File")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Text("期望格式: 姓名, 联系方式, 金额")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(24)
            } else {
                // Preview list
                VStack(spacing: 0) {
                    HStack {
                        Text("预览 (\(selectedCount) of \(importedStudents.count) selected)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("全选") { for i in importedStudents.indices { importedStudents[i].isSelected = true } }
                            .font(.system(size: 10))
                        Button("取消") { for i in importedStudents.indices { importedStudents[i].isSelected = false } }
                            .font(.system(size: 10))
                    }
                    .padding(12)
                    
                    List {
                        ForEach($importedStudents) { $row in
                            HStack {
                                Toggle("", isOn: $row.isSelected)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                Text(row.name)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                if let phone = row.phone {
                                    Text(phone)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if let amount = row.amount {
                                    Text("¥\(amount)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                            }
                            .opacity(row.isSelected ? 1 : 0.5)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                if !importedStudents.isEmpty {
                    Button("选择其他文件") { 
                        importedStudents = []
                        isFilePickerPresented = true 
                    }
                    .font(.system(size: 12))
                }
                Spacer()
                Button("取消") { dismiss() }
                if !importedStudents.isEmpty {
                    Button(action: performImport) {
                        Text("导入 \(selectedCount) 名学生")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCount > 0 ? Color.accentColor : Color.gray)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 600, minHeight: 500)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("导入错误", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("导入完成", isPresented: $importComplete) {
            Button("完成") { dismiss() }
        } message: {
            Text("成功导入 \(importedCount) 名学生")
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "无法访问文件"
                showingError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                parseCSV(content)
            } catch {
                importError = error.localizedDescription
                showingError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showingError = true
        }
    }
    
    private func parseCSV(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        var rows: [SimpleImportRow] = []
        
        for (idx, line) in lines.enumerated() {
            if idx == 0 { continue } // Skip header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            let columns = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !columns.isEmpty, !columns[0].isEmpty else { continue }
            
            rows.append(SimpleImportRow(
                name: columns[0],
                phone: columns.count > 1 ? columns[1] : nil,
                amount: columns.count > 2 ? columns[2] : nil
            ))
        }
        
        importedStudents = rows
    }
    
    private func performImport() {
        let toImport = importedStudents.filter { $0.isSelected }
        var count = 0
        
        for row in toImport {
            let student = Student(
                name: row.name,
                avatarColor: AvatarColor.allCases.randomElement() ?? .blue
            )
            dataManager.addStudent(student)
            
            if let amountStr = row.amount, let amount = Double(amountStr.replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: ",", with: "")) {
                let contract = Contract(
                    studentId: student.id,
                    contractNumber: 1,
                    totalSessions: max(1, Int(amount / 200)),
                    attendedSessions: 0,
                    startDate: Date(),
                    expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()),
                    totalAmount: amount,
                    amountPaid: amount,
                    isSigned: true,
                    signedDate: Date(),
                    notes: row.phone.map { "电话: \($0)" }
                )
                dataManager.addContract(contract)
            }
            count += 1
        }
        
        importedCount = count
        importComplete = true
    }
}
#endif

// MARK: - Contract Attendance Sheet
struct ContractAttendanceSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let student: Student
    @State var contract: Contract
    
    @State private var isEditing = false
    @State private var editedAttendance: [WeeklyAttendanceRecord] = []
    
    private var sortedWeeks: [WeeklyAttendanceRecord] {
        (isEditing ? editedAttendance : contract.weeklyAttendance)
            .sorted { $0.weekStartDate > $1.weekStartDate }
    }
    
    private var attendanceStats: (attended: Int, expected: Int, rate: Double) {
        let records = contract.weeklyAttendance
        let attended = records.reduce(0) { $0 + $1.attendedSessions }
        let expected = records.reduce(0) { $0 + $1.expectedSessions }
        let rate = expected > 0 ? Double(attended) / Double(expected) * 100 : 0
        return (attended, expected, rate)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    contractSummaryCard
                    attendanceStatsCard
                    weeklyAttendanceSection
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Attendance Tracker")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing { saveAttendance() } else { startEditing() }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if contract.weeklyAttendance.isEmpty && contract.startDate != nil {
                var updatedContract = contract
                updatedContract.generateWeeklyRecords()
                contract = updatedContract
                dataManager.updateContract(contract)
            }
        }
    }
    
    private var contractSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.contractLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(contract.contractType.shortName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                }
                Spacer()
                Text(contract.status.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(contract.status == .active ? Color.green : Color.orange)
                    .cornerRadius(8)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("\(contract.attendedSessions)/\(contract.totalSessions)")
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor((contract.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary)
                }
                Spacer()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geometry.size.width * contract.progressPercentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var attendanceStatsCard: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: attendanceStats.rate / 100)
                        .stroke(attendanceStats.rate >= 80 ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(attendanceStats.rate))%")
                        .font(.system(size: 14, weight: .bold))
                }
                Text("Attendance")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            VStack(spacing: 6) {
                Text("\(attendanceStats.attended)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                Text("Attended")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            VStack(spacing: 6) {
                let missed = attendanceStats.expected - attendanceStats.attended
                Text("\(missed)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(missed > 0 ? .orange : .gray)
                Text("Missed")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private var weeklyAttendanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY ATTENDANCE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            if sortedWeeks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("No attendance records yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sortedWeeks) { week in
                        weekRow(week)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func weekRow(_ week: WeeklyAttendanceRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(week.weekLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(week.expectedSessions) expected")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            if isEditing {
                HStack(spacing: 8) {
                    ForEach(0..<week.expectedSessions, id: \.self) { index in
                        Button(action: { toggleAttendance(for: week, sessionIndex: index) }) {
                            Image(systemName: index < week.attendedSessions ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundColor(index < week.attendedSessions ? .green : .gray.opacity(0.4))
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<week.expectedSessions, id: \.self) { index in
                        Image(systemName: index < week.attendedSessions ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(index < week.attendedSessions ? .green : .gray.opacity(0.4))
                    }
                }
            }
        }
        .padding(12)
        .background(week.isComplete ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
    
    private func startEditing() {
        editedAttendance = contract.weeklyAttendance
        isEditing = true
    }
    
    private func toggleAttendance(for week: WeeklyAttendanceRecord, sessionIndex: Int) {
        guard let index = editedAttendance.firstIndex(where: { $0.id == week.id }) else { return }
        var updatedWeek = editedAttendance[index]
        if sessionIndex < updatedWeek.attendedSessions {
            updatedWeek.attendedSessions = sessionIndex
        } else {
            updatedWeek.attendedSessions = min(sessionIndex + 1, updatedWeek.expectedSessions)
        }
        editedAttendance[index] = updatedWeek
    }
    
    private func saveAttendance() {
        contract.weeklyAttendance = editedAttendance
        contract.attendedSessions = contract.calculatedAttendedSessions
        contract.updatedAt = Date()
        dataManager.updateContract(contract)
        isEditing = false
        HapticFeedback.notification(.success)
    }
}

// MARK: - Contract Attendance Card
struct ContractAttendanceCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let contract: Contract
    let onTap: () -> Void
    
    private var attendanceRate: Double {
        let records = contract.weeklyAttendance
        let attended = records.reduce(0) { $0 + $1.attendedSessions }
        let expected = records.reduce(0) { $0 + $1.expectedSessions }
        return expected > 0 ? Double(attended) / Double(expected) * 100 : 0
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(contract.status == .active ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(contract.status == .active ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(contract.localizedContractLabel(isChinese: isChinese))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(contract.contractType.shortName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                    HStack(spacing: 8) {
                        Text("\(contract.attendedSessions)/\(contract.totalSessions) \(isChinese ? "节课" : "sessions")")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        if !contract.weeklyAttendance.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text("\(Int(attendanceRate))% \(isChinese ? "出勤" : "attendance")")
                                .font(.system(size: 12))
                                .foregroundColor(attendanceRate >= 80 ? .green : .orange)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor((contract.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary)
                    Text(isChinese ? "剩余" : "left")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Skills Evaluation Card
/// Unified skills card that shows skills with program comparison when available, includes editing
struct EnhancedSkillsCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let player: Player?
    let program: Program?
    
    @State private var isEditing = false
    @State private var editedSkills: SkillsEvaluation = SkillsEvaluation()
    
    private var targets: ProgramSkillTargets? { program?.skillTargets }
    
    private var currentPlayer: Player? {
        player ?? dataManager.player(for: student.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with overall rating and edit button
            headerSection
            
            if let player = currentPlayer {
                if isEditing {
                    editingSection
                } else {
                    displaySection(player: player)
                }
            } else {
                noSkillsSection
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundColor(.yellow)
            Text("Skills Evaluation")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            // Program badge if enrolled
            if let program = program {
                Text("• \(program.shortName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(program.mascotColor)
            }
            
            Spacer()
            
            if let player = currentPlayer {
                if !isEditing {
                    // Overall rating
                    Text(String(format: "%.1f", player.skills.overallRating))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(skillRatingColor(player.skills.overallRating))
                    Text("/ 10")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                // Edit button
                Button(action: {
                    if isEditing {
                        saveSkills()
                    } else {
                        editedSkills = player.skills
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing.toggle()
                    }
                }) {
                    Text(isEditing ? "Save" : "Edit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isEditing ? .green : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isEditing ? Color.green : Color.blue).opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Display Section
    private func displaySection(player: Player) -> some View {
        VStack(spacing: 10) {
            // Program comparison status (if enrolled with targets)
            if let targets = targets {
                let belowCount = targets.skillsBelowTarget(player.skills)
                HStack(spacing: 6) {
                    if belowCount == 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("Meeting all \(program?.shortName ?? "program") targets")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(belowCount) skill\(belowCount > 1 ? "s" : "") below \(program?.shortName ?? "program") targets")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(8)
                .background(belowCount == 0 ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            
            // Skills grid with comparison
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                skillDisplayBar(label: "Shooting", value: player.skills.shooting, target: targets?.shooting, color: .orange)
                skillDisplayBar(label: "Defense", value: player.skills.defense, target: targets?.defense, color: .blue)
                skillDisplayBar(label: "Ball Handling", value: player.skills.ballHandling, target: targets?.ballHandling, color: .green)
                skillDisplayBar(label: "Basketball IQ", value: player.skills.basketballIQ, target: targets?.basketballIQ, color: .purple)
                skillDisplayBar(label: "Athleticism", value: player.skills.athleticism, target: targets?.athleticism, color: .red)
                skillDisplayBar(label: "Teamwork", value: player.skills.teamwork, target: targets?.teamwork, color: .teal)
            }
            
            // Focus areas (if program targets exist)
            if let targets = targets {
                let belowSkills = targets.getSkillsBelowTarget(player.skills)
                if !belowSkills.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 10))
                        Text("Focus areas: \(belowSkills.joined(separator: ", "))")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.orange)
                }
            }
            
            // Last evaluated date
            if let lastDate = player.skills.lastEvaluatedDate {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.textTertiary)
            }
        }
    }
    
    // MARK: - Editing Section (6 skills matching radar)
    private var editingSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 12) {
            skillSlider(label: isChinese ? "得分" : "Scoring", value: $editedSkills.scoring, color: .orange, icon: "scope")
            skillSlider(label: isChinese ? "组织" : "Playmaking", value: $editedSkills.playmaking, color: .blue, icon: "arrow.triangle.branch")
            skillSlider(label: isChinese ? "篮板" : "Rebounding", value: $editedSkills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
            skillSlider(label: isChinese ? "防守" : "Defense", value: $editedSkills.defense, color: .red, icon: "shield.fill")
            skillSlider(label: isChinese ? "运动能力" : "Athleticism", value: $editedSkills.athleticism, color: .green, icon: "figure.run")
            skillSlider(label: isChinese ? "软实力" : "Intangibles", value: $editedSkills.intangibles, color: .teal, icon: "star.fill")
            
            Button(action: { withAnimation { isEditing = false } }) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - No Skills Section
    private var noSkillsSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.textTertiary)
            Text("No skills evaluation yet")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Skill Display Bar (with optional target comparison)
    private func skillDisplayBar(label: String, value: Int, target: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(target != nil ? (value >= target! ? .green : .orange) : color)
                if let target = target {
                    Text("/\(target)")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(target != nil ? (value >= target! ? Color.green : color) : color)
                        .frame(width: geometry.size.width * CGFloat(value) / 10, height: 4)
                    // Target marker
                    if let target = target {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 8)
                            .offset(x: geometry.size.width * CGFloat(target) / 10 - 1, y: -2)
                    }
                }
            }
            .frame(height: 4)
        }
    }
    
    // MARK: - Skill Slider (for editing)
    private func skillSlider(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 24)
                if let target = getTarget(for: label) {
                    Text("/ \(target)")
                        .font(.system(size: 10))
                        .foregroundColor(value.wrappedValue >= target ? .green : .orange)
                }
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 1...10, step: 1)
            .tint(color)
        }
    }
    
    private func getTarget(for skill: String) -> Int? {
        guard let targets = targets else { return nil }
        switch skill {
        case "Shooting": return targets.shooting
        case "Defense": return targets.defense
        case "Ball Handling": return targets.ballHandling
        case "Basketball IQ": return targets.basketballIQ
        case "Athleticism": return targets.athleticism
        case "Teamwork": return targets.teamwork
        default: return nil
        }
    }
    
    private func skillRatingColor(_ rating: Double) -> Color {
        switch rating {
        case 8...10: return .green
        case 6..<8: return .blue
        case 4..<6: return .orange
        default: return .red
        }
    }
    
    private func saveSkills() {
        guard var updatedPlayer = currentPlayer else { return }
        updatedPlayer.skills = editedSkills
        updatedPlayer.skills.lastEvaluatedDate = Date()
        updatedPlayer.updatedAt = Date()
        dataManager.updatePlayer(updatedPlayer)
        HapticFeedback.notification(.success)
    }
}

// MARK: - Contract Attendance Card (Tap to Edit, Swipe to Delete via List onDelete)
struct ContractAttendanceCardWithActions: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let contract: Contract
    let onTap: () -> Void  // Tap to edit contract
    
    private var attendanceRate: Double {
        let records = contract.weeklyAttendance
        let attended = records.reduce(0) { $0 + $1.attendedSessions }
        let expected = records.reduce(0) { $0 + $1.expectedSessions }
        return expected > 0 ? Double(attended) / Double(expected) * 100 : 0
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(contract.status == .active ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                        .foregroundColor(contract.status == .active ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(contract.contractLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(contract.contractType.shortName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                        Text(contract.status.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(contract.status == .active ? Color.green : Color.orange)
                            .cornerRadius(4)
                    }
                    HStack(spacing: 6) {
                        Text("\(contract.attendedSessions)/\(contract.totalSessions)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        if !contract.weeklyAttendance.isEmpty {
                            Text("•")
                                .foregroundColor(AppTheme.textTertiary)
                            Text("\(Int(attendanceRate))%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(attendanceRate >= 80 ? .green : .orange)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(contract.isPayAsYouGo ? "∞" : "\(contract.remainingSessions ?? 0)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor((contract.remainingSessions ?? 0) <= 3 ? .orange : AppTheme.textPrimary)
                    Text(isChinese ? "剩余" : "left")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Media Gallery Sheet
struct MediaGallerySheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStudent: Student
    let dataManager: DataManager
    
    @State private var selectedTab = 0
    @State private var selectedMediaUrl: String?
    @State private var selectedIsVideo = false
    @State private var isEditMode = false
    @State private var urlToDelete: String?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    init(student: Student, dataManager: DataManager) {
        self._currentStudent = State(initialValue: student)
        self.dataManager = dataManager
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        Text("Photos (\(currentStudent.mediaAssets.photoUrls.count))").tag(0)
                        Text("Videos (\(currentStudent.mediaAssets.videoUrls.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if selectedTab == 0 {
                        photosGrid
                    } else {
                        videosGrid
                    }
                }
            }
            .navigationTitle(isChinese ? "媒体库" : "Media Gallery")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditMode ? (isChinese ? "完成" : "Done") : (isChinese ? "编辑" : "Edit")) {
                        isEditMode.toggle()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "关闭" : "Close") { dismiss() }
                }
            }
            #if os(iOS)
            .fullScreenCover(item: Binding(
                get: { selectedMediaUrl.map { MediaItem(url: $0, isVideo: selectedIsVideo) } },
                set: { selectedMediaUrl = $0?.url }
            )) { item in
                MediaFullScreenView(urlString: item.url, isVideo: item.isVideo)
            }
            #else
            .sheet(item: Binding(
                get: { selectedMediaUrl.map { MediaItem(url: $0, isVideo: selectedIsVideo) } },
                set: { selectedMediaUrl = $0?.url }
            )) { item in
                MediaFullScreenView(urlString: item.url, isVideo: item.isVideo)
            }
            #endif
            .alert(isChinese ? "删除媒体?" : "Delete Media?", isPresented: Binding(
                get: { urlToDelete != nil },
                set: { if !$0 { urlToDelete = nil } }
            )) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) { urlToDelete = nil }
                Button(isChinese ? "删除" : "Delete", role: .destructive) { deleteMedia() }
            } message: {
                Text(isChinese ? "此操作无法撤销" : "This action cannot be undone")
            }
        }
    }
    
    private func deleteMedia() {
        guard let url = urlToDelete else { return }
        var updatedStudent = currentStudent
        
        if selectedTab == 0 {
            updatedStudent.mediaAssets.photoUrls.removeAll { $0 == url }
            // Delete file
            let path = url.hasPrefix("file://") ? String(url.dropFirst(7)) : url
            try? FileManager.default.removeItem(atPath: path)
        } else {
            updatedStudent.mediaAssets.videoUrls.removeAll { $0 == url }
            let path = url.hasPrefix("file://") ? String(url.dropFirst(7)) : url
            try? FileManager.default.removeItem(atPath: path)
        }
        
        updatedStudent.updatedAt = Date()
        dataManager.updateStudent(updatedStudent)
        currentStudent = updatedStudent
        urlToDelete = nil
    }
    
    private var photosGrid: some View {
        Group {
            if currentStudent.mediaAssets.photoUrls.isEmpty {
                emptyState(icon: "photo.fill", message: isChinese ? "暂无照片" : "No photos yet")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(currentStudent.mediaAssets.photoUrls, id: \.self) { urlString in
                            mediaGridItemWithDelete(urlString: urlString, isVideo: false)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var videosGrid: some View {
        Group {
            if currentStudent.mediaAssets.videoUrls.isEmpty {
                emptyState(icon: "video.fill", message: isChinese ? "暂无视频" : "No videos yet")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(currentStudent.mediaAssets.videoUrls, id: \.self) { urlString in
                            mediaGridItemWithDelete(urlString: urlString, isVideo: true)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private func mediaGridItemWithDelete(urlString: String, isVideo: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if !isEditMode {
                    selectedIsVideo = isVideo
                    selectedMediaUrl = urlString
                }
            } label: {
                mediaGridItem(urlString: urlString, isVideo: isVideo)
            }
            .disabled(isEditMode)
            
            if isEditMode {
                Button {
                    urlToDelete = urlString
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                        .background(Circle().fill(.white).frame(width: 18, height: 18))
                }
                .offset(x: 4, y: -4)
            }
        }
    }
    
    private func mediaGridItem(urlString: String, isVideo: Bool) -> some View {
        ZStack {
            if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
                let path = urlString.hasPrefix("file://") ? String(urlString.dropFirst(7)) : urlString
                #if canImport(UIKit)
                if let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderItem(isVideo: isVideo)
                }
                #elseif canImport(AppKit)
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderItem(isVideo: isVideo)
                }
                #endif
            } else {
                AsyncImage(url: URL(string: urlString)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        placeholderItem(isVideo: isVideo)
                    }
                }
            }
            
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
        }
    }
    
    private func placeholderItem(isVideo: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 100, height: 100)
            .overlay(
                Image(systemName: isVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            )
    }
    
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Helper struct for fullScreenCover
private struct MediaItem: Identifiable {
    let url: String
    let isVideo: Bool
    var id: String { url }
}

// MARK: - Full Screen Media View
struct MediaFullScreenView: View {
    @Environment(\.dismiss) var dismiss
    let urlString: String
    let isVideo: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isVideo {
                videoContent
            } else {
                imageContent
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var imageContent: some View {
        if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
            let path = urlString.hasPrefix("file://") ? String(urlString.dropFirst(7)) : urlString
            #if canImport(UIKit)
            if let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderView
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderView
            }
            #endif
        } else {
            AsyncImage(url: URL(string: urlString)) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFit()
                } else if case .failure = phase {
                    placeholderView
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
    }
    
    @ViewBuilder
    private var videoContent: some View {
        let videoURL: URL? = {
            if urlString.hasPrefix("file://") {
                return URL(string: urlString)
            } else if urlString.hasPrefix("/") {
                return URL(fileURLWithPath: urlString)
            } else {
                return URL(string: urlString)
            }
        }()
        
        if let url = videoURL {
            #if os(iOS)
            VideoPlayerView(url: url)
            #else
            VideoPlayer(player: AVPlayer(url: url))
            #endif
        } else {
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: isVideo ? "video.slash" : "photo.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Unable to load media")
                .foregroundColor(.gray)
        }
    }
}

#if os(iOS)
// Simple video player wrapper
struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif

// MARK: - Contact History Sheet
struct ContactHistorySheet: View {
    @Environment(\.dismiss) var dismiss
    let student: Student
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var touchpoints: [ParentalTouchpoint] {
        student.parentalTouchpoints.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if touchpoints.isEmpty {
                    emptyState
                } else {
                    ForEach(touchpoints) { touchpoint in
                        touchpointRow(touchpoint)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "联系记录" : "Contact History")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }
    
    private func touchpointRow(_ touchpoint: ParentalTouchpoint) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(touchpointColor(touchpoint.type).opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: touchpoint.type.icon)
                        .font(.system(size: 16))
                        .foregroundColor(touchpointColor(touchpoint.type))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(touchpointLabel(touchpoint.type))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text(touchpoint.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                if let notes = touchpoint.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                
                if touchpoint.followUpNeeded {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                        Text(isChinese ? "需要跟进" : "Follow-up needed")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(isChinese ? "暂无联系记录" : "No contact history yet")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(isChinese ? "与家长的沟通记录将在这里显示" : "Communication with parents will appear here")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }
    
    private func touchpointColor(_ type: ParentalTouchpoint.TouchpointType) -> Color {
        switch type {
        case .inPerson: return .green
        case .call: return .blue
        case .message: return .green
        case .email: return .orange
        case .reportCard: return .purple
        case .meeting: return .teal
        }
    }
    
    private func touchpointLabel(_ type: ParentalTouchpoint.TouchpointType) -> String {
        switch type {
        case .inPerson: return isChinese ? "当面沟通" : "In Person"
        case .call: return isChinese ? "电话" : "Phone Call"
        case .message: return isChinese ? "微信/消息" : "Message/WeChat"
        case .email: return isChinese ? "邮件" : "Email"
        case .reportCard: return isChinese ? "发送报告" : "Report Card"
        case .meeting: return isChinese ? "家长会" : "Meeting"
        }
    }
}

// MARK: - Visible Grade Preference Key
struct VisibleGradePreferenceKey: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}
