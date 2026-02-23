import SwiftUI
import Combine

// MARK: - Flighty-Inspired Hub View
/// A command center for managing all coaching resources with Flighty's calm, confident aesthetic
struct FlightyHubView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentTime = Date()
    @State private var showingRevenueHistory = false
    @State private var showingSampleDataAlert = false
    @State private var isLoadingSampleData = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed Properties
    
    /// Currency setting from app settings
    private var currency: CurrencyType {
        dataManager.appSettings.currency
    }
    
    /// Earnings from contracts created this month BY the logged-in coach
    private var monthlyEarnings: Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let coachId = dataManager.coach.id
        
        return dataManager.contracts
            .filter { contract in
                // Contracts created this month by this coach
                contract.createdAt >= startOfMonth &&
                contract.createdByCoachId == coachId
            }
            .reduce(0) { $0 + $1.amountPaid }
    }
    
    /// Number of new contracts this month by the logged-in coach
    private var newContractsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let coachId = dataManager.coach.id
        
        return dataManager.contracts.filter { 
            $0.createdAt >= startOfMonth && $0.createdByCoachId == coachId 
        }.count
    }
    
    private var activeContracts: Int {
        dataManager.contracts.filter { $0.status == .active }.count
    }
    
    
    private var upcomingSessions: Int {
        dataManager.sessionEvents.filter { $0.isUpcoming }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header with time
                    headerSection
                    
                    // Revenue Dashboard Card
                    revenueDashboard
                        .padding(.horizontal, 16)
                    
                    // Main Navigation Grid
                    navigationGrid
                        .padding(.horizontal, 16)
                    
                    // Settings Section
                    settingsSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .background(AppTheme.background.ignoresSafeArea())
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "控制中心" : "COMMAND CENTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accentColor)
                
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "中心" : "Hub")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            // Theme toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    themeManager.toggle()
                }
                HapticFeedback.impact(.light)
            }) {
                Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.isDarkMode ? .yellow : .orange)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
    }
    
    // MARK: - Revenue Dashboard (Dark Theme)
    private var revenueDashboard: some View {
        Button(action: { showingRevenueHistory = true }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.accentColor)
                            .frame(width: 8, height: 8)
                        Text(Date().formatted(.dateTime.month(.wide).year()).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    
                    Text(monthlyEarnings, format: .currency(code: currency.currencyCode))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                // New contracts indicator
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(newContractsThisMonth)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.accentColor)
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.accentColor.opacity(0.15))
                .cornerRadius(12)
            }
            .padding(18)
        }
        .buttonStyle(.plain)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .sheet(isPresented: $showingRevenueHistory) {
            MonthlyRevenueHistoryView()
        }
    }
    
    // MARK: - Navigation Grid
    private var navigationGrid: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 10) {
            // Row 1: League - Full width
            NavigationLink(destination: LeagueView()) {
                hubNavCardWide(
                    icon: "trophy.fill",
                    title: isChinese ? "联赛" : "League",
                    subtitle: isChinese ? "比赛与排名" : "Games & standings",
                    color: .yellow
                )
            }
            .buttonStyle(.plain)
            
            // Row 2: Coach & Organization
            HStack(spacing: 10) {
                NavigationLink(destination: DrillsLibraryView()) {
                    hubNavCard(
                        icon: "sportscourt.fill",
                        title: isChinese ? "训练" : "Coach",
                        subtitle: isChinese ? "\(dataManager.drills.count) 个训练" : "\(dataManager.drills.count) drills",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                
                NavigationLink(destination: OrganizationView()) {
                    hubNavCard(
                        icon: "building.2.fill",
                        title: isChinese ? "组织" : "Organization",
                        subtitle: organizationSubtitle(isChinese: isChinese),
                        color: .teal
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    /// Organization subtitle showing org name or staff count
    private func organizationSubtitle(isChinese: Bool) -> String {
        if let org = AuthManager.shared.currentOrganization {
            return org.displayName
        } else {
            return isChinese ? "\(dataManager.staffCoaches.count) 名员工" : "\(dataManager.staffCoaches.count) staff"
        }
    }
    
    /// Students needing attention (low sessions, no contact, etc.)
    private var studentsNeedingAttention: Int {
        dataManager.students.filter { student in
            let contract = dataManager.contracts.first { $0.studentId == student.id && $0.status == .active }
            // Low sessions or no recent parent contact
            let lowSessions = contract?.remainingSessions ?? 0 <= 3
            let noRecentContact: Bool
            if let lastContact = student.lastParentContact {
                noRecentContact = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0 > 21
            } else {
                noRecentContact = contract?.status == .active
            }
            return lowSessions || noRecentContact
        }.count
    }
    
    private func hubNavCardWide(icon: String, title: String, subtitle: String, color: Color, badge: String? = nil) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .cornerRadius(10)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func hubNavCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let hasSampleData = UserDefaults.standard.bool(forKey: "sampleDataLoaded_v2")
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "设置" : "SETTINGS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.leading, 4)
            
            VStack(spacing: 1) {
                // Sample Data Toggle - Only show in demo/guest mode
                if AuthManager.shared.isGuestMode {
                    Button(action: {
                        showingSampleDataAlert = true
                    }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: hasSampleData ? "tray.full.fill" : "tray.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.purple)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isChinese ? "示例数据" : "Sample Data")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(hasSampleData 
                                     ? (isChinese ? "示例数据已加载" : "Sample data loaded")
                                     : (isChinese ? "加载示例数据探索应用" : "Load sample data to explore"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            
                            Spacer()
                            
                            if isLoadingSampleData {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(hasSampleData ? (isChinese ? "清除" : "Clear") : (isChinese ? "加载" : "Load"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(hasSampleData ? .red : AppTheme.accentColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill((hasSampleData ? Color.red : AppTheme.accentColor).opacity(0.15))
                                    )
                            }
                        }
                        .padding(12)
                        .background(AppTheme.cardBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .alert(hasSampleData ? (isChinese ? "清除示例数据?" : "Clear Sample Data?") : (isChinese ? "加载示例数据?" : "Load Sample Data?"), isPresented: $showingSampleDataAlert) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
            Button(hasSampleData ? (isChinese ? "清除" : "Clear") : (isChinese ? "加载" : "Load"), role: hasSampleData ? .destructive : nil) {
                toggleSampleData()
            }
        } message: {
            Text(hasSampleData 
                 ? (isChinese ? "这将删除所有示例学员、课程和训练数据。" : "This will remove all sample students, sessions, and training data.")
                 : (isChinese ? "这将添加示例学员、课程和训练数据来帮助您探索应用功能。" : "This will add sample students, sessions, and training data to help you explore the app."))
        }
    }
    
    private func toggleSampleData() {
        isLoadingSampleData = true
        let hasSampleData = UserDefaults.standard.bool(forKey: "sampleDataLoaded_v2")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if hasSampleData {
                dataManager.clearSampleDataIfNeeded()
            } else {
                // Force load sample data
                UserDefaults.standard.set(false, forKey: "sampleDataLoaded_v2")
                dataManager.loadSampleDataIfNeeded()
            }
            isLoadingSampleData = false
            HapticFeedback.impact(.medium)
        }
    }
    
}

// MARK: - Monthly Revenue History View
/// Shows monthly revenue history with contracts signed by the logged-in coach
struct MonthlyRevenueHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContract: Contract?
    
    private var currency: CurrencyType {
        dataManager.appSettings.currency
    }
    
    /// Group contracts by month, filtered by logged-in coach
    private var monthlyData: [(month: Date, contracts: [Contract], total: Double)] {
        let coachId = dataManager.coach.id
        let coachContracts = dataManager.contracts.filter { $0.createdByCoachId == coachId }
        
        let calendar = Calendar.current
        var grouped: [Date: [Contract]] = [:]
        
        for contract in coachContracts {
            let components = calendar.dateComponents([.year, .month], from: contract.createdAt)
            if let monthStart = calendar.date(from: components) {
                grouped[monthStart, default: []].append(contract)
            }
        }
        
        return grouped.map { (month: $0.key, contracts: $0.value, total: $0.value.reduce(0) { $0 + $1.amountPaid }) }
            .sorted { $0.month > $1.month }
    }
    
    /// Current month's data
    private var currentMonthData: (contracts: [Contract], total: Double) {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let coachId = dataManager.coach.id
        
        let contracts = dataManager.contracts.filter {
            $0.createdAt >= startOfMonth && $0.createdByCoachId == coachId
        }
        let total = contracts.reduce(0) { $0 + $1.amountPaid }
        return (contracts, total)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Month Summary
                    currentMonthCard
                    
                    // Monthly History
                    if !monthlyData.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Monthly History")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                            
                            ForEach(monthlyData, id: \.month) { monthData in
                                MonthlyRevenueCard(
                                    month: monthData.month,
                                    contracts: monthData.contracts,
                                    total: monthData.total,
                                    currency: currency,
                                    onContractTap: { contract in
                                        selectedContract = contract
                                    }
                                )
                            }
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.vertical, 16)
            }
            .background(AppTheme.background)
            .navigationTitle("Revenue History")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            .sheet(item: $selectedContract) { contract in
                ContractDetailSheet(contract: contract, currency: currency)
            }
        }
    }
    
    // MARK: - Current Month Card
    private var currentMonthCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Month")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(Date().formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(currentMonthData.total, format: .currency(code: currency.currencyCode))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.accentColor)
                    Text("\(currentMonthData.contracts.count) contract\(currentMonthData.contracts.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            if !currentMonthData.contracts.isEmpty {
                Divider()
                
                VStack(spacing: 8) {
                    ForEach(currentMonthData.contracts) { contract in
                        Button(action: { selectedContract = contract }) {
                            ContractRowView(contract: contract, currency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.accentColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            
            Text("No Revenue History")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            Text("Contracts you sign will appear here.\nYour monthly earnings reset at the start of each month.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Monthly Revenue Card
struct MonthlyRevenueCard: View {
    let month: Date
    let contracts: [Contract]
    let total: Double
    let currency: CurrencyType
    let onContractTap: (Contract) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("\(contracts.count) contract\(contracts.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    Text(total, format: .currency(code: currency.currencyCode))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.successColor)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.leading, 8)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            // Expanded contracts list
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(spacing: 8) {
                    ForEach(contracts) { contract in
                        Button(action: { onContractTap(contract) }) {
                            ContractRowView(contract: contract, currency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Contract Row View
struct ContractRowView: View {
    let contract: Contract
    let currency: CurrencyType
    @EnvironmentObject var dataManager: DataManager
    
    private var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Student avatar
            Circle()
                .fill(Color(student?.avatarColor.color ?? .blue).opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(student?.initials ?? "?")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(student?.avatarColor.color ?? .blue))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(student?.name ?? "Unknown Student")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text(contract.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(contract.amountPaid, format: .currency(code: currency.currencyCode))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.successColor)
                Text("\(contract.totalSessions) sessions")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
    }
}

// MARK: - Contract Detail Sheet
struct ContractDetailSheet: View {
    let contract: Contract
    let currency: CurrencyType
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    private var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }
    
    private var enrollingCoach: Coach? {
        if contract.createdByCoachId == dataManager.coach.id {
            return dataManager.coach
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Student Info
                    studentInfoCard
                    
                    // Contract Details
                    contractDetailsCard
                    
                    // Enrolling Coach Info
                    enrollingCoachCard
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Contract Details")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accentColor)
                }
            }
        }
    }
    
    // MARK: - Student Info Card
    private var studentInfoCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(student?.avatarColor.color ?? .blue).opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(student?.initials ?? "?")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(student?.avatarColor.color ?? .blue))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(student?.name ?? "Unknown Student")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if let chineseName = student?.chineseName, !chineseName.isEmpty {
                        Text(chineseName)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Contract Details Card
    private var contractDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contract Information")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            VStack(spacing: 12) {
                detailRow(label: "Contract #", value: contract.contractLabel)
                detailRow(label: "Signed Date", value: contract.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                detailRow(label: "Total Sessions", value: "\(contract.totalSessions)")
                detailRow(label: "Price per Session", value: contract.pricePerSession.formatted(.currency(code: currency.currencyCode)))
                
                Divider()
                
                HStack {
                    Text("Amount Paid")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(contract.amountPaid, format: .currency(code: currency.currencyCode))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.successColor)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Enrolling Coach Card
    private var enrollingCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enrolled By")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(enrollingCoach?.initials ?? "?")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(enrollingCoach?.name ?? "Unknown Coach")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Coach")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

// MARK: - Preview
#Preview {
    FlightyHubView()
        .environmentObject(DataManager.shared)
}
