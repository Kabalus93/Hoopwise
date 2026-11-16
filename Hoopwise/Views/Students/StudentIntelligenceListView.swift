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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var debouncedSearchText = ""  // Performance: debounced for filtering
    @State private var selectedFilter: StudentFilter
    @State private var sortOption: SortOption = .riskScore
    @State private var groupOption: GroupOption = .none
    @State private var selectedStudent: Student?
    /// The list stays beside the profile in portrait too (16 Nov 2026,
    /// Luther: upright, the page opened empty and the list hid behind the
    /// sidebar button).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The tab's width, to pick the hand-laid panes on a narrow iPad.
    @State private var splitWidth: CGFloat = 1200
    @State private var sheetStudent: Student?
    @State private var showingAddStudent = false
    @FocusState private var searchFocused: Bool
    @State private var transferMode: StudentTransferView.Mode? = nil
    @State private var showingClassListImport = false
    @State private var classListExportFile: ClassListExportFile?
    @State private var expandedGroups: Set<String> = []
    @State private var currentVisibleGrade: String = ""
    @State private var userTappedGrade: String? = nil  // Track explicit user taps
    // Multi-select / bulk delete
    @State private var isSelecting = false
    @State private var selectedStudentIds: Set<UUID> = []
    @State private var showingBulkDeleteConfirm = false
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
        case school = "School"

        var icon: String {
            switch self {
            case .none: return "list.bullet"
            case .program: return "rectangle.stack.fill"
            case .age: return "birthday.cake"
            case .contract: return "doc.text.fill"
            case .risk: return "exclamationmark.triangle.fill"
            case .school: return "building.columns.fill"
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
            case .school: return "按学校"
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
        
        // Search filter - use debounced text for performance.
        // `localizedStandardContains` is case- AND diacritic-insensitive, so
        // typing "li yuzhe" matches a stored pinyin like "Lǐ Yǔzhé".
        let searchQuery = debouncedSearchText
        if !searchQuery.isEmpty {
            students = students.filter {
                $0.name.localizedStandardContains(searchQuery) ||
                ($0.chineseName?.localizedStandardContains(searchQuery) ?? false)
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
            if shouldUseSplitView, splitWidth < Self.tiledSplitMinWidth {
                // Narrow iPads upright (the mini, 744 pt): iPadOS slides the
                // split view's list over the profile however its visibility
                // is set, so the two panes are laid out here (16 Nov 2026,
                // Luther: the mini still opened empty).
                HStack(spacing: 0) {
                    NavigationStack {
                        mainContent
                    }
                    .frame(width: min(340, splitWidth * 0.44))
                    Divider().ignoresSafeArea()
                    athleteDetail
                        .frame(maxWidth: .infinity)
                }
            } else if shouldUseSplitView {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    NavigationStack {
                        mainContent
                    }
                    // Contacts-like proportions (November 2026): a list wide
                    // enough to read, the profile beside it.
                    .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
                } detail: {
                    athleteDetail
                }
                .navigationSplitViewStyle(.balanced)
                .onChange(of: selectedStudent == nil) { _, isEmpty in
                    // Nothing open (an athlete was deleted): bring the list back.
                    if isEmpty { columnVisibility = .all }
                }
            } else {
                NavigationStack {
                    mainContent
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitWidth = $0 }
    }

    /// Below this width the system split view will not keep its list on
    /// screen (iPad mini upright), so the panes are laid out by hand.
    private static let tiledSplitMinWidth: CGFloat = 900

    /// The open athlete, or the empty state.
    @ViewBuilder
    private var athleteDetail: some View {
        if let student = selectedStudent {
            // Unified profile — same view used everywhere else
            // (program detail, dashboard, attendance lists).
            NavigationStack {
                StudentDetailView(student: student)
            }
            .id(student.id)
        } else {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "选择一名学员" : "Choose an athlete")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(LocalizationManager.shared.currentLanguage == .chinese
                         ? "共 \(dataManager.students.count) 名学员"
                         : dataManager.students.count == 1 ? "1 athlete in the list" : "\(dataManager.students.count) athletes in the list")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
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
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        studentListSection
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(shouldUseSplitView
                ? (LocalizationManager.shared.currentLanguage == .chinese ? "学员" : "Athletes")
                : (LocalizationManager.shared.currentLanguage == .chinese ? "学员档案" : "Student Intelligence"))
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(shouldUseSplitView ? .inline : .large)
            #endif
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: LocalizationManager.shared.currentLanguage == .chinese ? "搜索运动员" : "Search athletes"
            )
            .searchFocused($searchFocused)
            // ⌘F / ⇧⌘N on the Mac (MainTabView switches here first).
            .onReceive(NotificationCenter.default.publisher(for: .hoopwiseFocusAthleteSearch)) { _ in
                searchFocused = true
                #if targetEnvironment(macCatalyst)
                // The Mac's search field can ignore .searchFocused; make it
                // first responder directly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MacSearch.focusFirstSearchField() }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .hoopwiseOpenAddAthlete)) { _ in
                showingAddStudent = true
            }
            .onChange(of: searchText) { _, newValue in
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    debouncedSearchText = newValue
                }
            }
            .toolbar { toolbarContent }
            .sheet(item: $sheetStudent) { student in
                NavigationStack {
                    StudentDetailView(student: student)
                }
            }
            .sheet(isPresented: $showingAddStudent) {
                EditStudentView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .hoopwiseStudentDeleted)) { note in
                guard let id = note.object as? UUID else { return }
                if selectedStudent?.id == id { selectedStudent = nil }
                if sheetStudent?.id == id { sheetStudent = nil }
            }
            .sheet(item: $transferMode) { mode in
                StudentTransferView(initialMode: mode)
            }
            .sheet(isPresented: $showingClassListImport) {
                ClassListImportView()
            }
            .sheet(item: $classListExportFile) { file in
                ProgramShareSheet(items: [file.url])
            }
            .alert(
                LocalizationManager.shared.currentLanguage == .chinese
                    ? "删除所选 \(selectedStudentIds.count) 名球员？"
                    : "Delete \(selectedStudentIds.count) player\(selectedStudentIds.count == 1 ? "" : "s")?",
                isPresented: $showingBulkDeleteConfirm
            ) {
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel",
                       role: .cancel) { }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete",
                       role: .destructive) {
                    performBulkDelete()
                }
            } message: {
                Text(LocalizationManager.shared.currentLanguage == .chinese
                     ? "此操作不可撤销。所选球员的资料、合同和测量记录都会被删除。"
                     : "This cannot be undone. The selected players' profiles, contracts, and measurements will be removed.")
            }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        Group {
            // Leading: cancel selection mode.
            if isSelecting {
                ToolbarItem(placement: .navigationBarLeadingCompat) {
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "完成" : "Done") {
                        isSelecting = false
                        selectedStudentIds.removeAll()
                    }
                }
            }

            // Primary action — Add menu OR delete-N action while selecting.
            ToolbarItem(placement: .primaryAction) {
                if isSelecting {
                    Button(role: .destructive) {
                        showingBulkDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedStudentIds.isEmpty)
                } else {
                    Menu {
                        Button {
                            showingAddStudent = true
                        } label: {
                            Label("Add Student", systemImage: "person.crop.circle.badge.plus")
                        }
                        Divider()
                        Button {
                            isSelecting = true
                            selectedStudentIds.removeAll()
                        } label: {
                            Label("Select Multiple", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button {
                            transferMode = .export
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            transferMode = .importing
                        } label: {
                            Label("Import…", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Button {
                            showingClassListImport = true
                        } label: {
                            Label(LocalizationManager.shared.currentLanguage == .chinese
                                  ? "导入上课名单（Excel）…" : "Import Class List (Excel)…",
                                  systemImage: "tablecells.badge.ellipsis")
                        }
                        Button {
                            exportClassList()
                        } label: {
                            Label(LocalizationManager.shared.currentLanguage == .chinese
                                  ? "导出上课名单（Excel）…" : "Export Class List (Excel)…",
                                  systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("athletes.add")
                }
            }
        }
    }
    
    private func exportClassList() {
        if let url = try? ClassListExport.file(dataManager: dataManager) {
            classListExportFile = ClassListExportFile(url: url)
        }
    }

    // MARK: - Search Bar
    private var searchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            
            TextField(LocalizationManager.shared.currentLanguage == .chinese ? "搜索运动员..." : "Search athletes...", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
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
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
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
        .background(.regularMaterial)
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
                .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.primary)
                Text("\(recentlyAddedStudents.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
            .background(.regularMaterial)
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
                            .foregroundStyle(.primary)
                        Text(student.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(student.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Text(relativeTimeString(from: student.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
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
    
    // MARK: - Student List (native inset-grouped sections per grade)
    private var studentListSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let grades = studentsByGrade

        return List {
            ForEach(grades, id: \.grade) { gradeGroup in
                Section {
                    ForEach(gradeGroup.students) { student in
                        if shouldUseSplitView {
                            let selected = selectedStudent?.id == student.id && !isSelecting
                            Button(action: { selectStudent(student) }) {
                                contactsRow(student: student, selected: selected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("athletes.row")
                            .athleteMacMenu(student)
                            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.accentColor : Color.clear)
                                    .padding(.horizontal, 8))
                            .listRowSeparator(selected ? .hidden : .visible)
                        } else {
                            Button(action: { selectStudent(student) }) {
                                studentRowCompact(student: student, isChinese: isChinese)
                            }
                            .buttonStyle(.plain)
                            .athleteMacMenu(student)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(gradeGroup.gradeName)
                            .textCase(nil)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("^[\(gradeGroup.students.count) athlete](inflect: true)")
                            .textCase(nil)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .modifier(AthleteListStyle(contacts: shouldUseSplitView))
    }

    /// iPad / Mac list row in the Contacts manner (November 2026, Luther):
    /// a bigger avatar, the name at reading size with the second name under
    /// it, and a solid accent highlight on the athlete whose profile is open.
    private func contactsRow(student: Student, selected: Bool) -> some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(student.primaryDisplayName)
                    .font(.body)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)
                if let second = student.secondaryNameLine {
                    Text(second)
                        .font(.subheadline)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            FormatBadge(format: dataManager.studentFormat(student), size: .mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
                            .athleteMacMenu(student)
                            
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
                .foregroundStyle(.tertiary)
            
            Text(isChinese ? "学员" : "Athletes")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }
    
    // MARK: - Compact Student Row (No Grade Column)
    private func studentRowCompact(student: Student, isChinese: Bool) -> some View {
        HStack(spacing: 10) {
            if isSelecting {
                Image(systemName: selectedStudentIds.contains(student.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedStudentIds.contains(student.id) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .transition(.scale.combined(with: .opacity))
            }
            // Small avatar (no ring)
            smallAvatarView(student: student)
            
            // Name
            VStack(alignment: .leading, spacing: 1) {
                if isChinese, let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text(student.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                // Secondary name
                if isChinese {
                    Text(student.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if let chinese = student.chineseName {
                    Text(chinese)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()

            // Format dot (private / group / school) — school enrolment wins
            // even if there's no contract yet, so school kids stand out.
            FormatBadge(format: dataManager.studentFormat(student), size: .mini)

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
                .foregroundStyle(.secondary)
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
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text(student.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    
                    // Secondary name
                    if isChinese {
                        Text(student.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()

                // Format (private / group / school) — school enrolment wins over contract.
                FormatBadge(format: dataManager.studentFormat(student), size: .compact)

                // Status info (compact)
                statusBadge(contract: contract, isChinese: isChinese)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Small Avatar (No Ring)
    /// Goes through the cached avatar pipeline so list scrolling never hits
    /// the network and re-mounts are free.
    private func smallAvatarView(student: Student) -> some View {
        StudentAvatarView(student: student, size: 32)
    }
    
    private func smallInitialsAvatar(student: Student) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.isDark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                .frame(width: 32, height: 32)
            Text(student.initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.primary)
                        Text(student.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(student.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Subtitle - key info
                HStack(spacing: 8) {
                    // Age
                    if let age = student.age {
                        Text("\(age)y")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.tertiary)
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
                let isUpcoming = session.date >= now && session.status != .completed && !SessionLifecycle.didNotHappen(session)
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
        case .school:
            return groupBySchool()
        }
    }

    private func groupBySchool() -> [(groupName: String, students: [Student])] {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        // Resolve "what school is this kid in" — they may be in multiple
        // school programs; we list them under the first matching school for
        // grouping, with all non-school athletes pooled into one section.
        let schoolPrograms = dataManager.programs.filter { $0.programType == .school }
        let schoolByStudent: [UUID: String] = Dictionary(uniqueKeysWithValues:
            filteredStudents.compactMap { student -> (UUID, String)? in
                guard let prog = schoolPrograms.first(where: { $0.enrolledStudentIds.contains(student.id) }) else {
                    return nil
                }
                let name = dataManager.school(for: prog.schoolId)?.displayName
                    ?? prog.name
                return (student.id, name)
            }
        )
        let nonSchoolLabel = isCN ? "非学校" : "Non-School"
        let grouped = Dictionary(grouping: filteredStudents) { student in
            schoolByStudent[student.id] ?? nonSchoolLabel
        }
        return grouped.map { (groupName: $0.key, students: $0.value) }
            // School groups first (alphabetical), then "Non-School" last.
            .sorted { lhs, rhs in
                if lhs.groupName == nonSchoolLabel { return false }
                if rhs.groupName == nonSchoolLabel { return true }
                return lhs.groupName.localizedCaseInsensitiveCompare(rhs.groupName) == .orderedAscending
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
    
    // MARK: - Helper Methods
    private func selectStudent(_ student: Student) {
        // In selection mode, taps toggle membership instead of opening profile.
        if isSelecting {
            if selectedStudentIds.contains(student.id) {
                selectedStudentIds.remove(student.id)
            } else {
                selectedStudentIds.insert(student.id)
            }
            return
        }
        if shouldUseSplitView {
            selectedStudent = student
        } else {
            sheetStudent = student
        }
    }

    private func performBulkDelete() {
        let ids = selectedStudentIds
        for student in dataManager.students where ids.contains(student.id) {
            dataManager.deleteStudent(student)
        }
        selectedStudentIds.removeAll()
        isSelecting = false
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
                let isUpcoming = session.date >= now && session.status != .completed && !SessionLifecycle.didNotHappen(session)
                return (isInProgram || isAttendee) && isUpcoming
            }
            .sorted { $0.date < $1.date }
            .first
        
        guard let session = nextSession else { return 8 } // No session = sort to end
        return Calendar.current.component(.weekday, from: session.date)
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        StudentIntelligenceListView()
            .environmentObject(DataManager.shared)
    }
}

private struct ClassListExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The athlete list's style: inset groups on iPhone (unchanged), a plain
/// Contacts-like list beside the profile on iPad and Mac.
private struct AthleteListStyle: ViewModifier {
    let contacts: Bool
    func body(content: Content) -> some View {
        if contacts {
            content.listStyle(.plain).scrollContentBackground(.hidden)
                #if targetEnvironment(macCatalyst)
                // The soft scroll-edge blur stuck over the list on the Mac
                // (Luther, November 2026: it stayed, or changed size, after
                // scrolling). No edge effect there; instead the header — the
                // title row and the search field under it — gets a fixed
                // frosted bar, so rows blur only where they pass beneath it.
                .scrollEdgeEffectHidden(true, for: .all)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbarBackground(.bar, for: .navigationBar)
                #endif
        } else {
            content.listStyle(.insetGrouped).scrollContentBackground(.hidden)
        }
    }
}
