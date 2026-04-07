import SwiftUI
import MapKit
import Combine
#if os(iOS)
import UIKit
typealias OrgPlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias OrgPlatformImage = NSImage
#endif

// MARK: - Map Snapshot Cache
/// Caches map snapshots by location ID to avoid repeated geocoding and snapshot generation
class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    
    private var cache: [UUID: OrgPlatformImage] = [:]
    private let queue = DispatchQueue(label: "com.sam.mapsnapshotcache", attributes: .concurrent)
    
    private init() {}
    
    func getSnapshot(for locationId: UUID) -> OrgPlatformImage? {
        queue.sync { cache[locationId] }
    }
    
    func setSnapshot(_ image: OrgPlatformImage, for locationId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[locationId] = image
        }
    }
    
    func hasSnapshot(for locationId: UUID) -> Bool {
        queue.sync { cache[locationId] != nil }
    }
    
    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}

// MARK: - Organization View
struct OrganizationView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedTab: OrgTab = .coaches
    @State private var showingEditOrg = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    enum OrgTab: String, CaseIterable {
        case coaches = "Coaches"
        case locations = "Locations"
        case categories = "Categories"
        
        var icon: String {
            switch self {
            case .coaches: return "person.2.fill"
            case .locations: return "mappin.circle.fill"
            case .categories: return "rectangle.stack.fill"
            }
        }
        
        var localizedName: String {
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .coaches: return isChinese ? "教练" : "Coaches"
            case .locations: return isChinese ? "地点" : "Locations"
            case .categories: return isChinese ? "类别" : "Categories"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Organization Hero Card
                organizationHeroCard
                    .padding(.horizontal, 16)
                
                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(OrgTab.allCases, id: \.self) { tab in
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 16))
                                Text(tab.localizedName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(selectedTab == tab ? AppTheme.accentColor : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == tab ? AppTheme.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(orgCardBackground)
                .cornerRadius(10)
                .padding(.horizontal, 16)
                
                // Content based on selected tab
                switch selectedTab {
                case .coaches:
                    CoachesListSection()
                case .locations:
                    LocationsListSection()
                case .categories:
                    CategoriesListSection()
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top, 8)
        }
        .background(AppTheme.background)
        .navigationTitle(isChinese ? "组织" : "Organization")
        .navigationBarTitleDisplayModeCompat(.large)
        .sheet(isPresented: $showingEditOrg) {
            EditOrganizationSheet()
        }
    }
    
    // MARK: - Organization Hero Card (Compact)
    private var organizationHeroCard: some View {
        Group {
            if let org = authManager.currentOrganization {
                HStack(spacing: 12) {
                    // Organization icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.accentColor)
                    }
                    
                    // Name and code
                    VStack(alignment: .leading, spacing: 2) {
                        Text(org.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        HStack(spacing: 6) {
                            Text(org.secretCode)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.accentColor)
                            
                            Button(action: {
                                #if os(iOS)
                                UIPasteboard.general.string = org.secretCode
                                HapticFeedback.impact(.light)
                                #endif
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Compact stats
                    HStack(spacing: 12) {
                        compactStat(value: "\(dataManager.staffCoaches.count)", icon: "person.2.fill")
                        compactStat(value: "\(dataManager.locations.count)", icon: "mappin")
                        compactStat(value: "\(dataManager.programs.count)", icon: "folder.fill")
                    }
                    
                    // Settings button (admin only)
                    if authManager.currentUser?.role.canManageOrganization == true {
                        Button(action: { showingEditOrg = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
            } else {
                // No organization - compact join/create prompt
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "未加入组织" : "No Organization")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(isChinese ? "加入或创建一个组织" : "Join or create one")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Text(isChinese ? "加入" : "Join")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentColor)
                            .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
            }
        }
    }
    
    private func compactStat(value: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
    
    private var orgCardBackground: some View {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}

// MARK: - Edit Organization Sheet
struct EditOrganizationSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var displayName = ""
    @State private var showingRegenerateAlert = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            List {
                // Organization name
                Section(header: Text(isChinese ? "组织信息" : "Organization Info")) {
                    TextField(isChinese ? "显示名称" : "Display Name", text: $displayName)
                }
                
                // Secret code management
                Section(header: Text(isChinese ? "邀请码" : "Invite Code")) {
                    if let org = authManager.currentOrganization {
                        HStack {
                            Text(org.secretCode)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.accentColor)
                            
                            Spacer()
                            
                            Button(action: { showingRegenerateAlert = true }) {
                                Label(isChinese ? "重新生成" : "Regenerate", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13))
                            }
                        }
                        
                        Text(isChinese ? "重新生成代码会使旧代码失效" : "Regenerating will invalidate the old code")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isChinese ? "组织设置" : "Organization Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        // Save changes
                        dismiss()
                    }
                }
            }
            .alert(isChinese ? "重新生成代码?" : "Regenerate Code?", isPresented: $showingRegenerateAlert) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
                Button(isChinese ? "重新生成" : "Regenerate", role: .destructive) {
                    // Regenerate code
                }
            } message: {
                Text(isChinese ? "当前代码将失效，已使用旧代码的教练不受影响" : "Current code will be invalidated. Coaches who already joined won't be affected.")
            }
            .onAppear {
                displayName = authManager.currentOrganization?.displayName ?? ""
            }
        }
    }
}

// MARK: - Coaches List Section
struct CoachesListSection: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @State private var showingAddCoach = false
    @State private var selectedCoach: StaffCoach?
    @State private var searchText = ""
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var isAdmin: Bool {
        authManager.currentUser?.role.canManageOrganization == true
    }
    
    var filteredCoaches: [StaffCoach] {
        if searchText.isEmpty {
            return dataManager.staffCoaches
        }
        return dataManager.staffCoaches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Search Bar
            PanelSearchBar(text: $searchText, placeholder: isChinese ? "搜索教练..." : "Search coaches...")
                .padding(.horizontal, 16)
            
            // Add Button
            Button(action: { showingAddCoach = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text(isChinese ? "添加教练" : "Add Coach")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(AppTheme.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accentColor.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            
            if filteredCoaches.isEmpty {
                PanelEmptyState(
                    icon: "person.2",
                    title: searchText.isEmpty ? (isChinese ? "暂无教练" : "No Coaches Yet") : (isChinese ? "无结果" : "No Results"),
                    subtitle: searchText.isEmpty ? (isChinese ? "添加教练到您的组织" : "Add coaches to your organization") : (isChinese ? "试试其他搜索" : "Try a different search")
                )
            } else {
                // Coaches List
                VStack(spacing: 8) {
                    ForEach(filteredCoaches) { coach in
                        CoachCardRow(coach: coach, isAdmin: isAdmin)
                            .onTapGesture { selectedCoach = coach }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showingAddCoach) {
            AddEditCoachView(coach: nil)
        }
        .sheet(item: $selectedCoach) { coach in
            CoachProfileDetailView(coach: coach)
        }
    }
}

// MARK: - Coach Card Row (Enhanced)
struct CoachCardRow: View {
    let coach: StaffCoach
    let isAdmin: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var profileImage: Image?
    @State private var hasAccount = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var isProfileCoach: Bool {
        coach.id == dataManager.loggedInCoachId
    }
    
    private var coachPrograms: [Program] {
        dataManager.programs.filter { $0.coachId == coach.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let profileImage = profileImage {
                        profileImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        PanelAvatar(initials: coach.initials, color: Color.avatarColor(coach.avatarColor), size: 48)
                    }
                    
                    // Account status indicator
                    if hasAccount {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .background(Circle().fill(AppTheme.cardBackground).frame(width: 18, height: 18))
                    } else if isProfileCoach {
                        Circle()
                            .fill(AppTheme.accentColor)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .onAppear {
                    loadProfileImage()
                    checkAccountStatus()
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let chineseName = coach.chineseName, !chineseName.isEmpty {
                            Text(chineseName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("(\(coach.name))")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        } else {
                            Text(coach.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        if isProfileCoach {
                            Text(isChinese ? "您" : "You")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    
                    // Role and access level
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 10))
                            Text(coach.role.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(coach.role.color)
                        
                        Text("•")
                            .foregroundColor(AppTheme.textTertiary)
                        
                        HStack(spacing: 3) {
                            Image(systemName: coach.accessLevel.icon)
                                .font(.system(size: 9))
                            Text(coach.accessLevel.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(coach.accessLevel.color)
                    }
                }
                
                Spacer()
                
                // Right side - programs or account status
                VStack(alignment: .trailing, spacing: 4) {
                    if !coachPrograms.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(coachPrograms.prefix(2)) { program in
                                Circle()
                                    .fill(Color(hex: program.colorHex))
                                    .frame(width: 8, height: 8)
                            }
                            if coachPrograms.count > 2 {
                                Text("+\(coachPrograms.count - 2)")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    }
                    
                    // Account status badge for admin view
                    if isAdmin {
                        Text(hasAccount ? (isChinese ? "已激活" : "Active") : (isChinese ? "无账号" : "No Account"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(hasAccount ? .green : AppTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((hasAccount ? Color.green : AppTheme.textTertiary).opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(14)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isProfileCoach ? AppTheme.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private func loadProfileImage() {
        #if os(iOS)
        // First try to load from coach's profileImageData directly
        if let imageData = coach.profileImageData, let uiImage = UIImage(data: imageData) {
            profileImage = Image(uiImage: uiImage)
            return
        }
        
        // For logged-in coach, also check main coach profile
        if isProfileCoach {
            if let imageData = dataManager.coach.profileImageData, let uiImage = UIImage(data: imageData) {
                profileImage = Image(uiImage: uiImage)
                return
            }
            
            // Try file URL fallback
            if let imagePath = dataManager.coach.profileImageUrl, !imagePath.isEmpty {
                let fileURL: URL
                if imagePath.hasPrefix("file://") {
                    guard let url = URL(string: imagePath) else { return }
                    fileURL = url
                } else if imagePath.hasPrefix("http") {
                    return // Cloud URL handled separately
                } else {
                    fileURL = URL(fileURLWithPath: imagePath)
                }
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
                guard let data = try? Data(contentsOf: fileURL) else { return }
                if let uiImage = UIImage(data: data) {
                    profileImage = Image(uiImage: uiImage)
                }
            }
        }
        #endif
    }
    
    private func checkAccountStatus() {
        guard let orgId = AuthManager.shared.currentOrganization?.id else { return }
        Task {
            do {
                let accounts: [SupabaseOrganizationAccount] = try await SupabaseManager.shared.fetchWithFilter(
                    from: "organization_accounts",
                    column: "organization_id",
                    op: .eq,
                    value: orgId.uuidString
                )
                // Check if any account matches this coach's name or email
                await MainActor.run {
                    hasAccount = accounts.contains { account in
                        account.name.lowercased() == coach.name.lowercased() ||
                        (coach.email != nil && account.name.lowercased().contains(coach.email!.lowercased()))
                    }
                }
            } catch {
                debugLog("⚠️ Failed to check account status: \(error)")
            }
        }
    }
}

// MARK: - Coach Profile Detail View
struct CoachProfileDetailView: View {
    let coach: StaffCoach
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    
    @State private var showingEditCoach = false
    @State private var showingCreateAccount = false
    @State private var showingManageAccount = false
    @State private var coachAccount: OrganizationAccount?
    @State private var isLoadingAccount = true
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var isAdmin: Bool {
        authManager.currentUser?.role.canManageOrganization == true
    }
    
    private var coachPrograms: [Program] {
        dataManager.programs.filter { $0.coachId == coach.id }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header
                    profileHeader
                    
                    // Account Management Section (Admin Only)
                    if isAdmin {
                        accountManagementSection
                    }
                    
                    // Programs Section
                    if !coachPrograms.isEmpty {
                        programsSection
                    }
                    
                    // Contact Info
                    if coach.email != nil || coach.phone != nil {
                        contactSection
                    }
                    
                    // Quick Actions
                    actionButtons
                    
                    Spacer(minLength: 50)
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(isChinese ? "教练资料" : "Coach Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "关闭" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { showingEditCoach = true }) {
                        Text(isChinese ? "编辑" : "Edit")
                    }
                }
            }
            .sheet(isPresented: $showingEditCoach) {
                AddEditCoachView(coach: coach)
            }
            .sheet(isPresented: $showingCreateAccount) {
                CreateAccountForCoachSheet(coach: coach, onAccountCreated: { account in
                    coachAccount = account
                })
            }
            .sheet(isPresented: $showingManageAccount) {
                if let account = coachAccount {
                    ManageCoachAccountSheet(account: account)
                }
            }
            .onAppear {
                loadCoachAccount()
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.avatarColor(coach.avatarColor).opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Text(coach.initials)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color.avatarColor(coach.avatarColor))
            }
            
            // Name
            VStack(spacing: 4) {
                if let chineseName = coach.chineseName, !chineseName.isEmpty {
                    Text(chineseName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(coach.name)
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text(coach.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            
            // Role badges
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: coach.role.icon)
                        .font(.system(size: 12))
                    Text(coach.role.rawValue)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(coach.role.color)
                .cornerRadius(8)
                
                HStack(spacing: 4) {
                    Image(systemName: coach.accessLevel.icon)
                        .font(.system(size: 11))
                    Text(coach.accessLevel.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(coach.accessLevel.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(coach.accessLevel.color.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Account Management Section
    private var accountManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accentColor)
                Text(isChinese ? "账号管理" : "Account Management")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            if isLoadingAccount {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if let account = coachAccount {
                // Has account - show details and manage button
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "用户名" : "Username")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("@\(account.username)")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        
                        Spacer()
                        
                        // Status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(account.isActive ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(account.isActive ? (isChinese ? "已激活" : "Active") : (isChinese ? "已禁用" : "Disabled"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(account.isActive ? .green : .red)
                        }
                    }
                    
                    Button(action: { showingManageAccount = true }) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(isChinese ? "管理账号" : "Manage Account")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accentColor.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            } else {
                // No account - show create button
                VStack(spacing: 8) {
                    Text(isChinese ? "此教练还没有登录账号" : "This coach doesn't have a login account yet")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: { showingCreateAccount = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(isChinese ? "创建登录账号" : "Create Login Account")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accentColor)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Programs Section
    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(isChinese ? "负责项目" : "Assigned Programs")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Text("\(coachPrograms.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            ForEach(coachPrograms) { program in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: program.colorHex))
                        .frame(width: 10, height: 10)
                    
                    Text(program.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text("\(program.enrolledStudentIds.count) " + (isChinese ? "学员" : "students"))
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Contact Section
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text(isChinese ? "联系方式" : "Contact Info")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            if let email = coach.email, !email.isEmpty {
                HStack {
                    Text(isChinese ? "邮箱" : "Email")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            
            if let phone = coach.phone, !phone.isEmpty {
                HStack {
                    Text(isChinese ? "电话" : "Phone")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                    Text(phone)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let phone = coach.phone, !phone.isEmpty {
                Button(action: {
                    #if os(iOS)
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 20))
                        Text(isChinese ? "拨打" : "Call")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            
            if let email = coach.email, !email.isEmpty {
                Button(action: {
                    #if os(iOS)
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 20))
                        Text(isChinese ? "邮件" : "Email")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func loadCoachAccount() {
        guard let orgId = authManager.currentOrganization?.id else {
            isLoadingAccount = false
            return
        }
        
        Task {
            do {
                let accounts: [SupabaseOrganizationAccount] = try await SupabaseManager.shared.fetchWithFilter(
                    from: "organization_accounts",
                    column: "organization_id",
                    op: .eq,
                    value: orgId.uuidString
                )
                
                await MainActor.run {
                    // Find account matching this coach
                    coachAccount = accounts.first { account in
                        account.name.lowercased() == coach.name.lowercased()
                    }?.toOrganizationAccount()
                    isLoadingAccount = false
                }
            } catch {
                debugLog("⚠️ Failed to load coach account: \(error)")
                await MainActor.run {
                    isLoadingAccount = false
                }
            }
        }
    }
}

// MARK: - Create Account For Coach Sheet
struct CreateAccountForCoachSheet: View {
    let coach: StaffCoach
    let onAccountCreated: (OrganizationAccount) -> Void
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: OrganizationRole = .coach
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCredentials = false
    @State private var createdAccount: OrganizationAccount?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            if showingCredentials, let account = createdAccount {
                CredentialsShareView(
                    account: account,
                    password: password,
                    onDone: {
                        onAccountCreated(account)
                        dismiss()
                    }
                )
            } else {
                Form {
                    Section(header: Text(isChinese ? "教练信息" : "Coach Info")) {
                        HStack {
                            Text(isChinese ? "姓名" : "Name")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(coach.name)
                                .fontWeight(.medium)
                        }
                    }
                    
                    Section(header: Text(isChinese ? "登录凭证" : "Login Credentials")) {
                        TextField(isChinese ? "用户名" : "Username", text: $username)
                            .textContentType(.username)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .disableAutocorrection(true)
                            .onChange(of: username) { _, newValue in
                                username = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            }
                        
                        SecureField(isChinese ? "密码 (至少6位)" : "Password (min 6 chars)", text: $password)
                        SecureField(isChinese ? "确认密码" : "Confirm Password", text: $confirmPassword)
                        
                        if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                            Text(isChinese ? "密码不匹配" : "Passwords don't match")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section(header: Text(isChinese ? "权限" : "Permissions")) {
                        Picker(isChinese ? "角色" : "Role", selection: $selectedRole) {
                            ForEach([OrganizationRole.admin, .coach, .assistant, .viewer], id: \.self) { role in
                                HStack {
                                    Image(systemName: role.icon)
                                        .foregroundColor(Color(role.color))
                                    Text(role.localizedDisplayName)
                                }
                                .tag(role)
                            }
                        }
                        
                        // Role description
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "角色权限说明" : "Role Permissions")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text(roleDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle(isChinese ? "创建账号" : "Create Account")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isChinese ? "取消" : "Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: createAccount) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(isChinese ? "创建" : "Create")
                            }
                        }
                        .disabled(!canCreate || isLoading)
                    }
                }
                .onAppear {
                    // Pre-fill username from coach name
                    username = coach.name.lowercased().replacingOccurrences(of: " ", with: "_")
                }
            }
        }
    }
    
    private var canCreate: Bool {
        username.count >= 3 && password.count >= 6 && password == confirmPassword
    }
    
    private var roleDescription: String {
        switch selectedRole {
        case .owner:
            return isChinese ? "拥有所有权限，可以管理组织设置和所有账号" : "Full access to all features and organization management"
        case .admin:
            return isChinese ? "可以管理教练账号、创建和删除所有数据" : "Can manage accounts, create/edit/delete all data"
        case .coach:
            return isChinese ? "可以创建、编辑和删除学员、课程、训练阶段和课时" : "Can create/edit/delete students, programs, phases, and sessions"
        case .assistant:
            return isChinese ? "可以编辑学员、课程、训练阶段和课时，但不能创建或删除" : "Can edit students, programs, phases, and sessions (no create/delete)"
        case .viewer:
            return isChinese ? "只能查看数据，不能进行任何修改" : "View-only access, cannot make any changes"
        }
    }
    
    private func createAccount() {
        guard let orgId = authManager.currentOrganization?.id else {
            errorMessage = isChinese ? "请先加入组织" : "Please join an organization first"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Note: createdBy is nil because FK references user_accounts, not organization_accounts
        let newAccount = OrganizationAccount(
            id: UUID(),
            organizationId: orgId,
            username: username,
            email: nil,
            passwordHash: UserAccount.hashPassword(password),
            name: coach.name,
            role: selectedRole,
            isActive: true,
            createdAt: Date(),
            createdBy: nil
        )
        
        Task {
            do {
                try await SupabaseManager.shared.insert(into: "organization_accounts", data: SupabaseOrganizationAccount(from: newAccount))
                await MainActor.run {
                    createdAccount = newAccount
                    showingCredentials = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Manage Coach Account Sheet
struct ManageCoachAccountSheet: View {
    let account: OrganizationAccount
    @Environment(\.dismiss) var dismiss
    
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isActive: Bool
    @State private var isLoading = false
    @State private var showingResetConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var successMessage: String?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    init(account: OrganizationAccount) {
        self.account = account
        _isActive = State(initialValue: account.isActive)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Info
                Section(header: Text(isChinese ? "账号信息" : "Account Info")) {
                    HStack {
                        Text(isChinese ? "姓名" : "Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(account.name)
                    }
                    
                    HStack {
                        Text(isChinese ? "用户名" : "Username")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("@\(account.username)")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text(isChinese ? "角色" : "Role")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(account.role.displayName)
                    }
                }
                
                // Status
                Section(header: Text(isChinese ? "状态" : "Status")) {
                    Toggle(isChinese ? "账号激活" : "Account Active", isOn: $isActive)
                        .onChange(of: isActive) { _, newValue in
                            updateAccountStatus(newValue)
                        }
                }
                
                // Password Reset
                Section(header: Text(isChinese ? "重置密码" : "Reset Password")) {
                    SecureField(isChinese ? "新密码" : "New Password", text: $newPassword)
                    SecureField(isChinese ? "确认密码" : "Confirm Password", text: $confirmPassword)
                    
                    if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text(isChinese ? "密码不匹配" : "Passwords don't match")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { showingResetConfirm = true }) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(isChinese ? "重置密码" : "Reset Password")
                        }
                    }
                    .disabled(newPassword.count < 6 || newPassword != confirmPassword)
                }
                
                if let message = successMessage {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                // Danger Zone
                Section(header: Text(isChinese ? "危险操作" : "Danger Zone")) {
                    Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(isChinese ? "删除账号" : "Delete Account")
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "管理账号" : "Manage Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .alert(isChinese ? "重置密码?" : "Reset Password?", isPresented: $showingResetConfirm) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
                Button(isChinese ? "重置" : "Reset") { resetPassword() }
            } message: {
                Text(isChinese ? "这将立即更改此教练的登录密码" : "This will immediately change this coach's login password")
            }
            .alert(isChinese ? "删除账号?" : "Delete Account?", isPresented: $showingDeleteConfirm) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
                Button(isChinese ? "删除" : "Delete", role: .destructive) { deleteAccount() }
            } message: {
                Text(isChinese ? "此操作无法撤销。教练将无法登录。" : "This cannot be undone. The coach will no longer be able to sign in.")
            }
        }
    }
    
    private func updateAccountStatus(_ active: Bool) {
        Task {
            do {
                // Create updated account with new status
                let updatedAccount = OrganizationAccount(
                    id: account.id,
                    organizationId: account.organizationId,
                    username: account.username,
                    email: account.email,
                    passwordHash: account.passwordHash,
                    name: account.name,
                    role: account.role,
                    isActive: active,
                    createdAt: account.createdAt,
                    createdBy: account.createdBy
                )
                try await SupabaseManager.shared.upsert(into: "organization_accounts", data: SupabaseOrganizationAccount(from: updatedAccount))
            } catch {
                debugLog("⚠️ Failed to update account status: \(error)")
            }
        }
    }
    
    private func resetPassword() {
        isLoading = true
        Task {
            do {
                // Create updated account with new password
                let updatedAccount = OrganizationAccount(
                    id: account.id,
                    organizationId: account.organizationId,
                    username: account.username,
                    email: account.email,
                    passwordHash: UserAccount.hashPassword(newPassword),
                    name: account.name,
                    role: account.role,
                    isActive: account.isActive,
                    createdAt: account.createdAt,
                    createdBy: account.createdBy
                )
                try await SupabaseManager.shared.upsert(into: "organization_accounts", data: SupabaseOrganizationAccount(from: updatedAccount))
                await MainActor.run {
                    successMessage = isChinese ? "密码已重置" : "Password has been reset"
                    newPassword = ""
                    confirmPassword = ""
                    isLoading = false
                }
            } catch {
                debugLog("⚠️ Failed to reset password: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func deleteAccount() {
        Task {
            do {
                try await SupabaseManager.shared.delete(from: "organization_accounts", id: account.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                debugLog("⚠️ Failed to delete account: \(error)")
            }
        }
    }
}

// MARK: - Locations List Section
struct LocationsListSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddLocation = false
    @State private var selectedLocation: Location?
    @State private var searchText = ""
    
    var filteredLocations: [Location] {
        if searchText.isEmpty {
            return dataManager.locations
        }
        return dataManager.locations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Search Bar
                PanelSearchBar(text: $searchText, placeholder: LocalizationManager.shared.currentLanguage == .chinese ? "搜索地点..." : "Search locations...")
                    .padding(.horizontal, 16)
                
                // Add Button
                Button(action: { showingAddLocation = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加地点" : "Add Location")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                
                if filteredLocations.isEmpty {
                    PanelEmptyState(
                        icon: "mappin.circle",
                        title: searchText.isEmpty ? (LocalizationManager.shared.currentLanguage == .chinese ? "暂无地点" : "No Locations Yet") : (LocalizationManager.shared.currentLanguage == .chinese ? "无结果" : "No Results"),
                        subtitle: searchText.isEmpty ? (LocalizationManager.shared.currentLanguage == .chinese ? "添加训练场地和球场" : "Add training venues and courts") : (LocalizationManager.shared.currentLanguage == .chinese ? "试试其他搜索" : "Try a different search")
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredLocations) { location in
                            LocationRow(location: location)
                                .onTapGesture { selectedLocation = location }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showingAddLocation) {
            AddEditLocationView(location: nil)
        }
        .sheet(item: $selectedLocation) { location in
            LocationDetailView(location: location)
        }
    }
}

// MARK: - Location Row (Hero Card with Map Snapshot)
struct LocationRow: View {
    let location: Location
    @State private var mapSnapshot: OrgPlatformImage?
    @State private var isLoadingMap = true
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Map snapshot background
            mapBackground
            
            // Gradient overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content overlay
            HStack(alignment: .bottom, spacing: 12) {
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    // Status badges
                    HStack(spacing: 6) {
                        // Court type badge
                        HStack(spacing: 4) {
                            Image(systemName: location.courtType.icon)
                                .font(.system(size: 9))
                            Text(location.courtType.rawValue)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(location.courtType.color.opacity(0.9))
                        .cornerRadius(6)
                        
                        if !location.isActive {
                            Text(isChinese ? "未激活" : "Inactive")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                    
                    // Location name
                    Text(location.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Address
                    if let address = location.fullAddress {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                            Text(address)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Court count badge
                VStack(spacing: 2) {
                    Text("\(location.courtCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(isChinese ? "球场" : (location.courtCount == 1 ? "Court" : "Courts"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .background(.ultraThinMaterial.opacity(0.3))
                .cornerRadius(10)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(14)
        }
        .frame(height: 120)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .onAppear {
            loadMapSnapshot()
        }
    }
    
    @ViewBuilder
    private var mapBackground: some View {
        if let snapshot = mapSnapshot {
            #if os(iOS)
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(height: 120)
                .clipped()
            #endif
        } else {
            // Placeholder while loading
            ZStack {
                location.courtType.color.opacity(0.3)
                
                if isLoadingMap {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    // No map available - show icon
                    Image(systemName: "map")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
    
    private func loadMapSnapshot() {
        // Check cache first
        if let cachedSnapshot = MapSnapshotCache.shared.getSnapshot(for: location.id) {
            mapSnapshot = cachedSnapshot
            isLoadingMap = false
            return
        }
        
        guard let address = location.fullAddress, !address.isEmpty else {
            isLoadingMap = false
            return
        }
        
        // Geocode the address
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            guard let placemark = placemarks?.first,
                  let coordinate = placemark.location?.coordinate else {
                DispatchQueue.main.async {
                    isLoadingMap = false
                }
                return
            }
            
            // Generate map snapshot
            generateSnapshot(for: coordinate)
        }
    }
    
    private func generateSnapshot(for coordinate: CLLocationCoordinate2D) {
        #if os(iOS)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        options.size = CGSize(width: 400, height: 200)
        options.mapType = .standard
        options.showsBuildings = true
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [self] snapshot, error in
            DispatchQueue.main.async {
                isLoadingMap = false
                if let snapshot = snapshot {
                    // Draw a pin on the snapshot
                    let image = drawPinOnSnapshot(snapshot: snapshot, coordinate: coordinate)
                    self.mapSnapshot = image
                    // Cache the snapshot for future use
                    MapSnapshotCache.shared.setSnapshot(image, for: location.id)
                }
            }
        }
        #else
        isLoadingMap = false
        #endif
    }
    
    #if os(iOS)
    private func drawPinOnSnapshot(snapshot: MKMapSnapshotter.Snapshot, coordinate: CLLocationCoordinate2D) -> UIImage {
        let image = snapshot.image
        
        UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
        image.draw(at: .zero)
        
        // Draw pin at coordinate
        let point = snapshot.point(for: coordinate)
        let pinSize: CGFloat = 20
        let pinRect = CGRect(
            x: point.x - pinSize/2,
            y: point.y - pinSize,
            width: pinSize,
            height: pinSize
        )
        
        // Draw pin circle
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor(location.courtType.color).cgColor)
        context?.fillEllipse(in: pinRect)
        
        // Draw pin border
        context?.setStrokeColor(UIColor.white.cgColor)
        context?.setLineWidth(2)
        context?.strokeEllipse(in: pinRect)
        
        let finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return finalImage
    }
    #endif
}

// MARK: - Categories List Section
struct CategoriesListSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddCategory = false
    @State private var selectedCategory: CustomAgeCategory?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Add Button
                Button(action: { showingAddCategory = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加类别" : "Add Category")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                
                // Categories List
                VStack(spacing: 2) {
                    ForEach(dataManager.ageCategories.sorted { $0.minAge < $1.minAge }) { category in
                        CategoryRow(category: category)
                            .onTapGesture { selectedCategory = category }
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddEditCategoryView(category: nil)
        }
        .sheet(item: $selectedCategory) { category in
            AddEditCategoryView(category: category)
        }
    }
}

// MARK: - Category Row
struct CategoryRow: View {
    let category: CustomAgeCategory
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        HStack(spacing: 12) {
            // Color badge with mascot icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(category.color)
                    .frame(width: 44, height: 44)
                
                if let customImage = category.customIconImage {
                    #if canImport(UIKit)
                    Image(uiImage: customImage)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    #elseif canImport(AppKit)
                    Image(nsImage: customImage)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    #endif
                } else {
                    Image(systemName: category.mascotIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Mascot name + short name (e.g., "Cheetahs U12")
                    Text("\(isChinese ? category.mascotNameChinese : category.mascotName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text(category.shortName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(category.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(category.color.opacity(0.15))
                        .cornerRadius(4)
                    
                    if !category.isActive {
                        PanelBadge(text: isChinese ? "未激活" : "Inactive", color: AppTheme.textTertiary)
                    }
                }
                
                Text(category.ageRange)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            // Equipment info
            VStack(alignment: .trailing, spacing: 2) {
                Text(category.ballSize.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Text(category.rimHeight.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(categoryRowBackground)
        .cornerRadius(12)
    }
    
    private var categoryRowBackground: some View {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}

// MARK: - Add/Edit Coach View
struct AddEditCoachView: View {
    let coach: StaffCoach?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String
    @State private var chineseName: String
    @State private var email: String
    @State private var phone: String
    @State private var role: CoachRole
    @State private var accessLevel: AccessLevel
    @State private var selectedAgeGroups: Set<AgeGroup>
    @State private var specializations: [String]
    @State private var newSpecialization: String = ""
    @State private var avatarColor: AvatarColor
    @State private var isActive: Bool
    @State private var notes: String
    @State private var showingDeleteConfirmation: Bool = false
    @State private var showingReassignSheet: Bool = false
    @State private var selectedProgramForReassign: Program?
    
    var isEditing: Bool { coach != nil }
    let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    init(coach: StaffCoach?) {
        self.coach = coach
        _name = State(initialValue: coach?.name ?? "")
        _chineseName = State(initialValue: coach?.chineseName ?? "")
        _email = State(initialValue: coach?.email ?? "")
        _phone = State(initialValue: coach?.phone ?? "")
        _role = State(initialValue: coach?.role ?? .assistant)
        _accessLevel = State(initialValue: coach?.accessLevel ?? .coachingStaff)
        _selectedAgeGroups = State(initialValue: Set(coach?.ageGroups ?? []))
        _specializations = State(initialValue: coach?.specializations ?? [])
        _avatarColor = State(initialValue: coach?.avatarColor ?? .blue)
        _isActive = State(initialValue: coach?.isActive ?? true)
        _notes = State(initialValue: coach?.notes ?? "")
    }
    
    /// Programs assigned to this coach
    private func getCoachPrograms() -> [Program] {
        guard let coach = coach else { return [] }
        return dataManager.programs.filter { $0.coachId == coach.id }
    }
    
    /// Total students across all programs
    private func getTotalStudents(programs: [Program]) -> Int {
        let programIds = Set(programs.map { $0.id })
        return dataManager.students.filter { student in
            programIds.contains(student.programId ?? UUID())
        }.count
    }
    
    var body: some View {
        let coachPrograms = getCoachPrograms()
        let totalStudents = getTotalStudents(programs: coachPrograms)
        
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview Header
                    VStack(spacing: 8) {
                        PanelAvatar(initials: chineseName.isEmpty ? (name.isEmpty ? "?" : String(name.prefix(2)).uppercased()) : String(chineseName.prefix(1)), color: Color.avatarColor(avatarColor), size: 56)
                        
                        // Display name - favor Chinese
                        if !chineseName.isEmpty {
                            VStack(spacing: 2) {
                                Text(chineseName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                if !name.isEmpty {
                                    Text(name)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        } else {
                            Text(name.isEmpty ? (isChinese ? "教练姓名" : "Coach Name") : name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(name.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                        }
                        
                        PanelBadge(text: role.rawValue, color: role.color)
                        
                        // Quick stats for existing coaches
                        if isEditing {
                            HStack(spacing: 16) {
                                VStack(spacing: 2) {
                                    Text("\(coachPrograms.count)")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(AppTheme.accentColor)
                                    Text(isChinese ? "项目" : "Programs")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                VStack(spacing: 2) {
                                    Text("\(totalStudents)")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.green)
                                    Text(isChinese ? "学员" : "Students")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Basic Info - Names
                    PanelSectionCard(isChinese ? "基本信息" : "Basic Info", icon: "person.text.rectangle") {
                        VStack(spacing: 10) {
                            HStack {
                                Text(isChinese ? "英文名" : "English Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField(isChinese ? "必填" : "Required", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            Divider()
                            HStack {
                                Text(isChinese ? "中文名" : "Chinese Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField(isChinese ? "选填（优先显示）" : "Optional (preferred)", text: $chineseName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            Divider()
                            HStack {
                                Text(isChinese ? "邮箱" : "Email")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField(isChinese ? "选填" : "Optional", text: $email)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            Divider()
                            HStack {
                                Text(isChinese ? "电话" : "Phone")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField(isChinese ? "选填" : "Optional", text: $phone)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                        }
                    }
                    
                    // Programs Section (only for existing coaches)
                    if isEditing && !coachPrograms.isEmpty {
                        PanelSectionCard(isChinese ? "负责项目" : "Assigned Programs", icon: "sportscourt") {
                            VStack(spacing: 8) {
                                ForEach(coachPrograms) { program in
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: program.colorHex))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: program.mascot.icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(program.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            let studentCount = dataManager.students.filter { $0.programId == program.id }.count
                                            Text("\(studentCount) \(isChinese ? "学员" : "students")")
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        // Reassign button
                                        Button(action: {
                                            selectedProgramForReassign = program
                                            showingReassignSheet = true
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.left.arrow.right")
                                                    .font(.system(size: 10))
                                                Text(isChinese ? "转移" : "Reassign")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(AppTheme.surfaceColor)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    // Role & Access
                    PanelSectionCard("Role & Access", icon: "person.badge.shield.checkmark") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Role")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Picker("", selection: $role) {
                                    ForEach(CoachRole.allCases, id: \.self) { r in
                                        Label(r.rawValue, systemImage: r.icon).tag(r)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Access Level")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Picker("", selection: $accessLevel) {
                                    ForEach(AccessLevel.allCases, id: \.self) { level in
                                        Label(level.rawValue, systemImage: level.icon).tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            
                            // Access level description
                            HStack(spacing: 8) {
                                Image(systemName: accessLevel.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(accessLevel.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(accessLevel.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(accessLevel.color)
                                    Text(accessLevel.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(accessLevel.color.opacity(0.1))
                            .cornerRadius(8)
                            
                            Divider()
                            HStack {
                                Text("Active")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $isActive)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                    
                    // Age Groups
                    PanelSectionCard("Age Groups", icon: "person.3") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(AgeGroup.allCases, id: \.self) { age in
                                Button(action: {
                                    if selectedAgeGroups.contains(age) {
                                        selectedAgeGroups.remove(age)
                                    } else {
                                        selectedAgeGroups.insert(age)
                                    }
                                    HapticFeedback.impact(.light)
                                }) {
                                    Text(age.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(selectedAgeGroups.contains(age) ? .white : AppTheme.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity)
                                        .background(selectedAgeGroups.contains(age) ? Color(hex: age.colorHex) : AppTheme.surfaceColor)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Specializations
                    PanelSectionCard("Specializations", icon: "star") {
                        VStack(spacing: 8) {
                            if specializations.isEmpty {
                                Text("No specializations added")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(specializations, id: \.self) { spec in
                                        HStack(spacing: 4) {
                                            Text(spec)
                                                .font(.system(size: 10, weight: .medium))
                                            Button(action: {
                                                specializations.removeAll { $0 == spec }
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .foregroundColor(AppTheme.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            
                            HStack(spacing: 8) {
                                TextField("Add specialization", text: $newSpecialization)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                Button(action: {
                                    if !newSpecialization.isEmpty {
                                        specializations.append(newSpecialization)
                                        newSpecialization = ""
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(newSpecialization.isEmpty ? AppTheme.textTertiary : AppTheme.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(newSpecialization.isEmpty)
                            }
                            .padding(8)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Delete Button with confirmation
                    if isEditing {
                        Button(action: { showingDeleteConfirmation = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text(isChinese ? "删除教练" : "Delete Coach")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Warning about permanent deletion
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            Text(isChinese ? "删除操作不可撤销，将从云端永久删除" : "Deletion is permanent and syncs to cloud")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(isEditing ? (isChinese ? "编辑教练" : "Edit Coach") : (isChinese ? "添加教练" : "Add Coach"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { saveCoach() }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(name.isEmpty)
                }
            }
            .alert(isChinese ? "确认删除" : "Confirm Delete", isPresented: $showingDeleteConfirmation) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
                Button(isChinese ? "删除" : "Delete", role: .destructive) { deleteCoach() }
            } message: {
                Text(isChinese ? "确定要删除此教练吗？此操作将从云端永久删除，无法恢复。" : "Are you sure you want to delete this coach? This will permanently remove them from the cloud and cannot be undone.")
            }
            .sheet(isPresented: $showingReassignSheet) {
                if let program = selectedProgramForReassign {
                    ReassignProgramSheet(program: program, currentCoachId: coach?.id)
                }
            }
        }
    }
    
    private func saveCoach() {
        let updatedCoach = StaffCoach(
            id: coach?.id ?? UUID(),
            organizationId: coach?.organizationId ?? AuthManager.shared.currentOrganization?.id,
            name: name,
            chineseName: chineseName.isEmpty ? nil : chineseName,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            role: role,
            accessLevel: accessLevel,
            specializations: specializations,
            ageGroups: Array(selectedAgeGroups),
            avatarColor: avatarColor,
            isActive: isActive,
            hireDate: coach?.hireDate ?? Date(),
            notes: notes.isEmpty ? nil : notes,
            createdAt: coach?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        if isEditing {
            dataManager.updateStaffCoach(updatedCoach)
        } else {
            dataManager.addStaffCoach(updatedCoach)
        }
        HapticFeedback.notification(.success)
        dismiss()
    }
    
    private func deleteCoach() {
        if let coach = coach {
            dataManager.deleteStaffCoach(coach)
            HapticFeedback.notification(.warning)
            // Small delay to ensure deletion completes before dismissing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}

// MARK: - Reassign Program Sheet
struct ReassignProgramSheet: View {
    let program: Program
    let currentCoachId: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedCoachId: UUID?
    
    let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    /// Other coaches to reassign to (excluding current coach)
    var availableCoaches: [StaffCoach] {
        dataManager.staffCoaches.filter { $0.id != currentCoachId && $0.isActive }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Program info
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: program.colorHex))
                            .frame(width: 48, height: 48)
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        let studentCount = dataManager.students.filter { $0.programId == program.id }.count
                        Text("\(studentCount) \(isChinese ? "学员" : "students")")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(AppTheme.surfaceColor)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                
                // Select new coach
                Text(isChinese ? "选择新教练" : "Select New Coach")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                
                if availableCoaches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(isChinese ? "没有其他可用教练" : "No other coaches available")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(availableCoaches) { coach in
                                Button(action: { selectedCoachId = coach.id }) {
                                    HStack(spacing: 10) {
                                        PanelAvatar(initials: coach.initials, color: Color.avatarColor(coach.avatarColor), size: 40)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let chinese = coach.chineseName, !chinese.isEmpty {
                                                HStack(spacing: 4) {
                                                    Text(chinese)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(AppTheme.textPrimary)
                                                    Text("(\(coach.name))")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(AppTheme.textSecondary)
                                                }
                                            } else {
                                                Text(coach.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(AppTheme.textPrimary)
                                            }
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: coach.role.icon)
                                                    .font(.system(size: 9))
                                                Text(coach.role.rawValue)
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(coach.role.color)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedCoachId == coach.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(AppTheme.accentColor)
                                        } else {
                                            Circle()
                                                .strokeBorder(AppTheme.textTertiary, lineWidth: 1.5)
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .padding(12)
                                    .background(selectedCoachId == coach.id ? AppTheme.accentColor.opacity(0.1) : AppTheme.surfaceColor)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 16)
            .background(AppTheme.background)
            .navigationTitle(isChinese ? "转移项目" : "Reassign Program")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "确认转移" : "Reassign") { reassignProgram() }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(selectedCoachId == nil)
                }
            }
        }
    }
    
    private func reassignProgram() {
        guard let newCoachId = selectedCoachId else { return }
        
        var updatedProgram = program
        updatedProgram.coachId = newCoachId
        updatedProgram.updatedAt = Date()
        
        dataManager.updateProgram(updatedProgram)
        HapticFeedback.notification(.success)
        dismiss()
    }
}

// Note: FlowLayout is defined in ProgramDetailView.swift

// MARK: - Add/Edit Location View
struct AddEditLocationView: View {
    let location: Location?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String
    @State private var address: String
    @State private var city: String
    @State private var courtCount: Int
    @State private var courtType: CourtType
    @State private var maxCapacity: String
    @State private var contactPhone: String
    @State private var amenities: [String]
    @State private var newAmenity: String = ""
    @State private var isActive: Bool
    @State private var notes: String
    
    var isEditing: Bool { location != nil }
    
    init(location: Location?) {
        self.location = location
        _name = State(initialValue: location?.name ?? "")
        _address = State(initialValue: location?.address ?? "")
        _city = State(initialValue: location?.city ?? "")
        _courtCount = State(initialValue: location?.courtCount ?? 1)
        _courtType = State(initialValue: location?.courtType ?? .indoor)
        _maxCapacity = State(initialValue: location?.maxCapacity.map { String($0) } ?? "")
        _contactPhone = State(initialValue: location?.contactPhone ?? "")
        _amenities = State(initialValue: location?.amenities ?? [])
        _isActive = State(initialValue: location?.isActive ?? true)
        _notes = State(initialValue: location?.notes ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(courtType.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: courtType.icon)
                                .font(.system(size: 24))
                                .foregroundColor(courtType.color)
                        }
                        Text(name.isEmpty ? "Location Name" : name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(name.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                        HStack(spacing: 4) {
                            Text("\(courtCount)")
                                .font(.system(size: 12, weight: .bold))
                            Text(courtCount == 1 ? "Court" : "Courts")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Basic Info
                    PanelSectionCard("Basic Info", icon: "building.2") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("Required", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            Divider()
                            #if os(iOS)
                            AddressAutocompleteField(address: $address, city: $city)
                            #else
                            HStack {
                                Text("Address")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("Optional", text: $address)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            #endif
                            Divider()
                            HStack {
                                Text("City")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("Optional", text: $city)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                        }
                    }
                    
                    // Court Details
                    PanelSectionCard("Court Details", icon: "sportscourt") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Courts")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Stepper("\(courtCount)", value: $courtCount, in: 1...10)
                                    .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Type")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Picker("", selection: $courtType) {
                                    ForEach(CourtType.allCases, id: \.self) { type in
                                        Label(type.rawValue, systemImage: type.icon).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Max Capacity")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("Optional", text: $maxCapacity)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }
                            Divider()
                            HStack {
                                Text("Active")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $isActive)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                    
                    // Contact
                    PanelSectionCard("Contact", icon: "phone") {
                        HStack {
                            Text("Phone")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            TextField("Optional", text: $contactPhone)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                    }
                    
                    // Amenities
                    PanelSectionCard("Amenities", icon: "checkmark.seal") {
                        VStack(spacing: 8) {
                            if amenities.isEmpty {
                                Text("No amenities added")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(amenities, id: \.self) { amenity in
                                        HStack(spacing: 4) {
                                            Text(amenity)
                                                .font(.system(size: 10, weight: .medium))
                                            Button(action: {
                                                amenities.removeAll { $0 == amenity }
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .foregroundColor(courtType.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(courtType.color.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            
                            HStack(spacing: 8) {
                                TextField("Add amenity", text: $newAmenity)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                Button(action: {
                                    if !newAmenity.isEmpty {
                                        amenities.append(newAmenity)
                                        newAmenity = ""
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(newAmenity.isEmpty ? AppTheme.textTertiary : AppTheme.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(newAmenity.isEmpty)
                            }
                            .padding(8)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Delete Button
                    if isEditing {
                        Button(action: deleteLocation) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Location")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(isEditing ? "Edit Location" : "Add Location")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLocation() }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveLocation() {
        let updatedLocation = Location(
            id: location?.id ?? UUID(),
            name: name,
            address: address.isEmpty ? nil : address,
            city: city.isEmpty ? nil : city,
            courtCount: courtCount,
            courtType: courtType,
            hasIndoor: courtType != .outdoor,
            amenities: amenities,
            maxCapacity: Int(maxCapacity),
            contactPhone: contactPhone.isEmpty ? nil : contactPhone,
            notes: notes.isEmpty ? nil : notes,
            isActive: isActive,
            createdAt: location?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        if isEditing {
            dataManager.updateLocation(updatedLocation)
        } else {
            dataManager.addLocation(updatedLocation)
        }
        HapticFeedback.notification(.success)
        dismiss()
    }
    
    private func deleteLocation() {
        if let location = location {
            dataManager.deleteLocation(location)
        }
        HapticFeedback.notification(.warning)
        dismiss()
    }
}

// MARK: - Add/Edit Category View
struct AddEditCategoryView: View {
    let category: CustomAgeCategory?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String
    @State private var shortName: String
    @State private var minAge: Int
    @State private var maxAge: Int
    @State private var colorHex: String
    @State private var ballSize: BallSize
    @State private var rimHeight: RimHeight
    @State private var description: String
    @State private var isActive: Bool
    @State private var mascotNameOverride: String
    @State private var customIconData: Data?
    @State private var showingImagePicker = false
    @State private var selectedImage: OrgPlatformImage?
    
    let colorOptions: [String] = [
        "#F8A5C2", "#FFB347", "#FFE066", "#6BCB77", "#5B8DEF",
        "#9B7EDE", "#95A5A6", "#E94560", "#3B82F6", "#10B981"
    ]
    
    var isEditing: Bool { category != nil }
    
    init(category: CustomAgeCategory?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _shortName = State(initialValue: category?.shortName ?? "")
        _minAge = State(initialValue: category?.minAge ?? 5)
        _maxAge = State(initialValue: category?.maxAge ?? 7)
        _colorHex = State(initialValue: category?.colorHex ?? "#5B8DEF")
        _ballSize = State(initialValue: category?.ballSize ?? .size5)
        _rimHeight = State(initialValue: category?.rimHeight ?? .feet10)
        _description = State(initialValue: category?.description ?? "")
        _isActive = State(initialValue: category?.isActive ?? true)
        _mascotNameOverride = State(initialValue: category?.mascotNameOverride ?? "")
        _customIconData = State(initialValue: category?.customIconData)
        if let data = category?.customIconData {
            _selectedImage = State(initialValue: OrgPlatformImage(data: data))
        } else {
            _selectedImage = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: colorHex))
                                .frame(width: 56, height: 56)
                            
                            if let image = selectedImage {
                                #if canImport(UIKit)
                                Image(uiImage: image)
                                    .resizable()
                                    .renderingMode(.original)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                #elseif canImport(AppKit)
                                Image(nsImage: image)
                                    .resizable()
                                    .renderingMode(.original)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                #endif
                            } else {
                                Image(systemName: previewMascotIcon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        Text(previewMascotName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(shortName.isEmpty ? "U?" : shortName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: colorHex))
                        Text("Ages \(minAge)-\(maxAge)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Basic Info
                    PanelSectionCard("Basic Info", icon: "rectangle.stack") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("e.g., Under 8", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 180)
                            }
                            Divider()
                            HStack {
                                Text("Short Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("e.g., U8", text: $shortName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 60)
                                    .onChange(of: shortName) { _, newValue in
                                        shortName = String(newValue.uppercased().prefix(4))
                                    }
                            }
                        }
                    }
                    
                    // Age Range
                    PanelSectionCard("Age Range", icon: "calendar") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Min Age")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Stepper("\(minAge)", value: $minAge, in: 3...25)
                                    .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Max Age")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Stepper("\(maxAge)", value: $maxAge, in: minAge...30)
                                    .labelsHidden()
                            }
                        }
                    }
                    
                    // Equipment
                    PanelSectionCard("Equipment", icon: "basketball") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Ball Size")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Picker("", selection: $ballSize) {
                                    ForEach(BallSize.allCases, id: \.self) { size in
                                        Text(size.displayName).tag(size)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Rim Height")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Picker("", selection: $rimHeight) {
                                    ForEach(RimHeight.allCases, id: \.self) { height in
                                        Text(height.displayName).tag(height)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }
                    
                    // Mascot Identity
                    PanelSectionCard("Mascot", icon: "pawprint.fill") {
                        VStack(spacing: 12) {
                            // Mascot Name
                            HStack {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                TextField("e.g., Koalas", text: $mascotNameOverride)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 140)
                            }
                            
                            Divider()
                            
                            // Custom Icon
                            HStack {
                                Text("Icon")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                Spacer()
                                
                                if let image = selectedImage {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: colorHex).opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            #if canImport(UIKit)
                                            Image(uiImage: image)
                                                .resizable()
                                                .renderingMode(.original)
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                            #elseif canImport(AppKit)
                                            Image(nsImage: image)
                                                .resizable()
                                                .renderingMode(.original)
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                            #endif
                                        }
                                        
                                        Button(action: { 
                                            selectedImage = nil
                                            customIconData = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                    }
                                } else {
                                    Button(action: { showingImagePicker = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "photo.badge.plus")
                                            Text("Upload")
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            
                            Text("Upload a custom icon image for this category. Use a simple outline icon for best results.")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Color
                    PanelSectionCard("Color", icon: "paintpalette") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(colorOptions, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(.white, lineWidth: colorHex == color ? 3 : 0)
                                    )
                                    .shadow(color: colorHex == color ? Color(hex: color).opacity(0.5) : .clear, radius: 4)
                                    .onTapGesture {
                                        colorHex = color
                                        HapticFeedback.impact(.light)
                                    }
                            }
                        }
                    }
                    
                    // Status
                    PanelSectionCard("Status", icon: "checkmark.circle") {
                        HStack {
                            Text("Active")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Toggle("", isOn: $isActive)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    
                    // Delete Button
                    if isEditing {
                        Button(action: deleteCategory) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Category")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(isEditing ? "Edit Category" : "Add Category")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCategory() }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(name.isEmpty || shortName.isEmpty)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingImagePicker) {
                CategoryIconImagePicker(selectedImage: $selectedImage, customIconData: $customIconData)
            }
            #endif
        }
    }
    
    // MARK: - Computed Properties
    
    private var previewMascotName: String {
        if !mascotNameOverride.isEmpty {
            return mascotNameOverride
        }
        // Try to get from AgeGroup based on shortName
        let ageGroup: AgeGroup? = {
            switch shortName.uppercased() {
            case "U6": return .u6
            case "U8": return .u8
            case "U10": return .u10
            case "U12": return .u12
            case "U14": return .u14
            case "U16": return .u16
            case "U18": return .u18
            case "18+", "ADULT": return .adult
            default: return nil
            }
        }()
        return ageGroup?.mascotName ?? (name.isEmpty ? "Mascot Name" : name)
    }
    
    private var previewMascotIcon: String {
        let ageGroup: AgeGroup? = {
            switch shortName.uppercased() {
            case "U6": return .u6
            case "U8": return .u8
            case "U10": return .u10
            case "U12": return .u12
            case "U14": return .u14
            case "U16": return .u16
            case "U18": return .u18
            case "18+", "ADULT": return .adult
            default: return nil
            }
        }()
        return ageGroup?.mascotIcon ?? "rectangle.stack.fill"
    }
    
    private func saveCategory() {
        let updatedCategory = CustomAgeCategory(
            id: category?.id ?? UUID(),
            name: name,
            shortName: shortName,
            minAge: minAge,
            maxAge: maxAge,
            colorHex: colorHex,
            ballSize: ballSize,
            rimHeight: rimHeight,
            description: description.isEmpty ? nil : description,
            isActive: isActive,
            createdAt: category?.createdAt ?? Date(),
            updatedAt: Date(),
            customIconData: customIconData,
            mascotNameOverride: mascotNameOverride.isEmpty ? nil : mascotNameOverride
        )
        
        if isEditing {
            dataManager.updateAgeCategory(updatedCategory)
        } else {
            dataManager.addAgeCategory(updatedCategory)
        }
        HapticFeedback.notification(.success)
        dismiss()
    }
    
    private func deleteCategory() {
        if let category = category {
            dataManager.deleteAgeCategory(category)
        }
        HapticFeedback.notification(.warning)
        dismiss()
    }
}

// MARK: - Category Icon Image Picker
#if os(iOS)
struct CategoryIconImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var customIconData: Data?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CategoryIconImagePicker
        
        init(_ parent: CategoryIconImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                processImage(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                processImage(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
        
        private func processImage(_ image: UIImage) {
            // Resize to a reasonable size for icon use (max 200x200)
            let maxSize: CGFloat = 200
            let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let resized = resizedImage {
                parent.selectedImage = resized
                parent.customIconData = resized.pngData()
            }
        }
    }
}
#endif

// MARK: - Address Autocomplete Field
#if os(iOS)
class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }
    
    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        isSearching = false
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        searchResults = []
        isSearching = false
    }
}

struct AddressAutocompleteField: View {
    @Binding var address: String
    @Binding var city: String
    @StateObject private var completer = AddressSearchCompleter()
    @State private var showSuggestions = false
    @FocusState private var isAddressFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Address")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                TextField("Start typing...", text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 200)
                    .focused($isAddressFocused)
                    .onChange(of: address) { _, newValue in
                        completer.search(query: newValue)
                        showSuggestions = !newValue.isEmpty
                    }
            }
            
            // Suggestions dropdown
            if showSuggestions && !completer.searchResults.isEmpty && isAddressFocused {
                VStack(spacing: 0) {
                    ForEach(completer.searchResults.prefix(5), id: \.self) { result in
                        Button(action: {
                            selectAddress(result)
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Text(result.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        
                        if result != completer.searchResults.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .padding(.top, 4)
            }
        }
    }
    
    private func selectAddress(_ result: MKLocalSearchCompletion) {
        address = result.title
        // Extract city from subtitle if available
        let subtitleParts = result.subtitle.components(separatedBy: ", ")
        if let cityPart = subtitleParts.first, !cityPart.isEmpty {
            city = cityPart
        }
        showSuggestions = false
        isAddressFocused = false
        HapticFeedback.impact(.light)
    }
}
#endif

// MARK: - Location Detail View with Map Hero
struct LocationDetailView: View {
    let location: Location
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingEditSheet = false
    @State private var mapRegion: MKCoordinateRegion?
    @State private var coordinate: CLLocationCoordinate2D?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Map Section
                    heroMapSection
                    
                    // Location Info
                    VStack(spacing: 16) {
                        // Basic info card
                        infoCard
                        
                        // Amenities
                        if !location.amenities.isEmpty {
                            amenitiesCard
                        }
                        
                        // Contact
                        if location.contactPhone != nil {
                            contactCard
                        }
                    }
                    .padding(16)
                }
            }
            .background(AppTheme.background)
            .navigationTitle(location.name)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { showingEditSheet = true }) {
                        Text(isChinese ? "编辑" : "Edit")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                AddEditLocationView(location: location)
            }
            .onAppear {
                geocodeAddress()
            }
        }
    }
    
    private var heroMapSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Map or placeholder
            if let region = mapRegion, let coord = coordinate {
                Map(coordinateRegion: .constant(region), annotationItems: [MapPin(coordinate: coord)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: location.courtType.color)
                }
                .frame(height: 200)
                .allowsHitTesting(false)
            } else {
                ZStack {
                    location.courtType.color.opacity(0.2)
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.system(size: 40))
                            .foregroundColor(location.courtType.color.opacity(0.5))
                        if location.fullAddress == nil {
                            Text(isChinese ? "未添加地址" : "No address added")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                .frame(height: 200)
            }
            
            // Overlay with location info
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(alignment: .leading, spacing: 6) {
                // Court type badge
                HStack(spacing: 4) {
                    Image(systemName: location.courtType.icon)
                        .font(.system(size: 10))
                    Text(location.courtType.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(location.courtType.color)
                .cornerRadius(6)
                
                // Location name
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 16))
                    Text(location.name)
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundColor(.white)
                
                // Address
                if let address = location.fullAddress {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(address)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(16)
        }
    }
    
    private var infoCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label(isChinese ? "球场数量" : "Courts", systemImage: "sportscourt")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(location.courtCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Divider()
            
            HStack {
                Label(isChinese ? "类型" : "Type", systemImage: location.courtType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text(location.courtType.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(location.courtType.color)
            }
            
            if let capacity = location.maxCapacity {
                Divider()
                HStack {
                    Label(isChinese ? "最大容量" : "Max Capacity", systemImage: "person.3")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("\(capacity)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private var amenitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isChinese ? "设施" : "Amenities", systemImage: "checkmark.seal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            FlowLayout(spacing: 6) {
                ForEach(location.amenities, id: \.self) { amenity in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text(amenity)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(location.courtType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(location.courtType.color.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phone = location.contactPhone {
                HStack {
                    Label(isChinese ? "电话" : "Phone", systemImage: "phone")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(phone)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private func geocodeAddress() {
        guard let address = location.fullAddress, !address.isEmpty else { return }
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            guard let placemark = placemarks?.first,
                  let coord = placemark.location?.coordinate else { return }
            
            DispatchQueue.main.async {
                self.coordinate = coord
                self.mapRegion = MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            }
        }
    }
}

// Helper for map annotation
struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    NavigationStack {
        OrganizationView()
            .environmentObject(DataManager.shared)
    }
}
