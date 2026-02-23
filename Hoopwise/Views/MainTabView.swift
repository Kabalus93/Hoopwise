import SwiftUI
import Foundation

// MARK: - Navigation Notification Names
extension Notification.Name {
    static let navigateToTab = Notification.Name("navigateToTab")
    static let navigateToStudent = Notification.Name("navigateToStudent")
    static let navigateToContract = Notification.Name("navigateToContract")
    static let showAddSession = Notification.Name("showAddSession")
}

struct MainTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var sessionMonitor = SessionStatusMonitor.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = 0
    @State private var isTabBarVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    
    // Navigation state for deep links
    @State private var selectedStudentId: UUID?
    @State private var selectedContractId: UUID?
    @State private var showStudentDetail = false
    @State private var showContractDetail = false
    @State private var showAddSession = false
    
    var body: some View {
        Group {
            if shouldUseSplitView {
                ZStack(alignment: .bottom) {
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Floating pill navigation at bottom on iPad
                    FloatingPillTabs(selectedTab: $selectedTab)
                        .environmentObject(dataManager)
                        .padding(.bottom, 16)
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                ZStack {
                    ZStack(alignment: .bottom) {
                        tabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        ActionableTabBar(selectedTab: $selectedTab, isDarkMode: themeManager.isDarkMode)
                            .offset(y: isTabBarVisible ? 0 : 100)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTabBarVisible)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            handleScrollChange(offset)
        }
        // Navigation notification handlers
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tabIndex = notification.object as? Int {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = tabIndex
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToStudent)) { notification in
            if let studentId = notification.object as? UUID {
                selectedStudentId = studentId
                showStudentDetail = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToContract)) { notification in
            if let contractId = notification.object as? UUID {
                selectedContractId = contractId
                showContractDetail = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddSession)) { _ in
            selectedTab = 1
            showAddSession = true
        }
        .sheet(isPresented: $showStudentDetail) {
            if let studentId = selectedStudentId,
               let student = dataManager.students.first(where: { $0.id == studentId }) {
                NavigationStack {
                    StudentDetailView(student: student)
                        .environmentObject(dataManager)
                }
            }
        }
        .sheet(isPresented: $showContractDetail) {
            if let contractId = selectedContractId,
               let contract = dataManager.contracts.first(where: { $0.id == contractId }) {
                ContractDetailSheet(contract: contract, currency: dataManager.appSettings.currency)
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $sessionMonitor.showAttendanceReminder) {
            if let session = sessionMonitor.completedSession {
                AttendanceReminderSheet(session: session)
                    .environmentObject(dataManager)
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

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case 0:
                FlightyActionableDashboard()
            case 1:
                FlightySessionRootView()
            case 2:
                NavigationStack {
                    StudentIntelligenceListView()
                }
            case 3:
                FlightyHubView()
            default:
                FlightyActionableDashboard()
            }
        }
    }

    private func handleScrollChange(_ offset: CGFloat) {
        let threshold: CGFloat = 10
        let delta = offset - lastScrollOffset
        
        // Scrolling down (content moving up) - hide tab bar
        if delta > threshold && isTabBarVisible {
            isTabBarVisible = false
        }
        // Scrolling up (content moving down) or near top - show tab bar
        else if delta < -threshold || offset < 50 {
            isTabBarVisible = true
        }
        
        lastScrollOffset = offset
    }
}

// MARK: - Floating Pill Tabs (Compact, no bar)
struct FloatingPillTabs: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var dataManager: DataManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var showingSearch = false

    private var tabs: [String] {
        let lang = localizationManager.currentLanguage
        return [
            lang == .chinese ? "首页" : "Home",
            lang == .chinese ? "课程" : "Sessions",
            lang == .chinese ? "学员" : "Students",
            lang == .chinese ? "中心" : "Hub"
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .padding(4)
        .background {
            Color.clear.glassEffect(in: Capsule())
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchSheet()
                .environmentObject(dataManager)
        }
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = index
            }
            HapticFeedback.impact(.light)
        }) {
            Text(tabs[index])
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? (AppTheme.isDark ? .white : Color(hex: "#1A1A1A")) : AppTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(AppTheme.accentColor.opacity(0.25))
                            .background { Capsule().fill(.ultraThinMaterial) }
                            .glassEffect()
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Global Search Sheet (placeholder)
struct GlobalSearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textTertiary)
                    TextField(isChinese ? "搜索学员、课程、项目..." : "Search students, sessions, programs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(14)
                .background(AppTheme.surfaceColor)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                if searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(isChinese ? "输入关键词搜索" : "Enter keywords to search")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                } else {
                    // Simple search results
                    List {
                        let matchingStudents = dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.chineseName?.localizedCaseInsensitiveContains(searchText) ?? false) }
                        let matchingPrograms = dataManager.programs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                        
                        if !matchingStudents.isEmpty {
                            Section(isChinese ? "学员" : "Students") {
                                ForEach(matchingStudents.prefix(5)) { student in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.avatarColor(student.avatarColor).opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Text(student.initials)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(Color.avatarColor(student.avatarColor))
                                            )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(student.name)
                                                .font(.system(size: 15, weight: .medium))
                                            if let cn = student.chineseName {
                                                Text(cn)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AppTheme.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        if !matchingPrograms.isEmpty {
                            Section(isChinese ? "项目" : "Programs") {
                                ForEach(matchingPrograms.prefix(5)) { program in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color(hex: program.colorHex).opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Image(systemName: "folder.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(Color(hex: program.colorHex))
                                            )
                                        Text(program.name)
                                            .font(.system(size: 15, weight: .medium))
                                    }
                                }
                            }
                        }
                        
                        if matchingStudents.isEmpty && matchingPrograms.isEmpty {
                            Text(isChinese ? "无结果" : "No results")
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "搜索" : "Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Actionable Tab Bar (Apple Fitness+ Style)
struct ActionableTabBar: View {
    @Binding var selectedTab: Int
    var isDarkMode: Bool = true
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Namespace private var tabAnimation
    
    private var tabs: [(icon: String, selectedIcon: String, label: String)] {
        let lang = localizationManager.currentLanguage
        return [
            ("house", "house.fill", lang == .chinese ? "首页" : "Home"),
            ("calendar", "calendar.badge.clock", lang == .chinese ? "课程" : "Sessions"),
            ("brain.head.profile", "brain.head.profile.fill", lang == .chinese ? "学员" : "Students"),
            ("square.grid.2x2", "square.grid.2x2.fill", lang == .chinese ? "中心" : "Hub")
        ]
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Color.clear.glassEffect(in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
    
    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        let tab = tabs[index]
        
        return Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = index
            }
            HapticFeedback.impact(.light)
        }) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textSecondary)
                
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.accentColor.opacity(0.2))
                        .background { Capsule().fill(.ultraThinMaterial) }
                        .glassEffect()
                        .matchedGeometryEffect(id: "tabSelection", in: tabAnimation)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager.shared)
}
