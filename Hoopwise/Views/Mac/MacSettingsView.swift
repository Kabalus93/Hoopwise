import SwiftUI
import UserNotifications

#if os(macOS)
/// Native macOS Settings window with profile configuration
struct MacSettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSection: SettingsSection = .profile
    @State private var localSettings: AppSettings = AppSettings.default
    @State private var isRefreshing = false
    @State private var showingRefreshSuccess = false
    @State private var showingLogoutAlert = false
    @State private var isExportingIcons = false
    @State private var iconExportStatus = ""
    
    enum SettingsSection: String, CaseIterable, Identifiable {
        case profile = "Profile"
        case organization = "Organization"
        case notifications = "Notifications"
        case sync = "Sync & Data"
        case about = "About"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .profile: return "person.circle.fill"
            case .organization: return "building.2.fill"
            case .notifications: return "bell.badge.fill"
            case .sync: return "arrow.triangle.2.circlepath"
            case .about: return "info.circle.fill"
            }
        }
    }
    
    private var coach: Coach { dataManager.coach }
    private var effectiveCoachId: UUID { dataManager.loggedInCoachId ?? coach.id }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with settings sections
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Content based on selected section
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedSection {
                    case .profile:
                        profileSection
                    case .organization:
                        organizationSection
                    case .notifications:
                        notificationsSection
                    case .sync:
                        syncSection
                    case .about:
                        aboutSection
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            localSettings = dataManager.appSettings
        }
        .onChange(of: localSettings) { _, newSettings in
            dataManager.updateAppSettings(newSettings)
        }
        .alert("Log Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) { handleLogout() }
        } message: {
            Text("Are you sure you want to log out? Your local data will be preserved.")
        }
    }
    
    // MARK: - Profile Section
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Coach Profile")
            
            // Profile Card
            HStack(spacing: 20) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentColor, AppTheme.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Text(coach.initials)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(coach.name.isEmpty ? "Set up your profile" : coach.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if !coach.email.isEmpty {
                        Text(coach.email)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    if let phone = coach.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
            
            // Stats Row
            HStack(spacing: 24) {
                profileStat(value: "\(coach.yearsOfExperience)", label: "Years Experience")
                profileStat(value: "\(myStudentsCount)", label: "Athletes")
                profileStat(value: "\(myProgramsCount)", label: "Programs")
                profileStat(value: "\(coach.certifications.count)", label: "Certifications")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            
            Divider().padding(.vertical, 8)
            
            // Edit Profile Form
            sectionHeader("Edit Profile")
            
            MacProfileEditForm()
            
            // Certifications, Specializations, Achievements
            if !coach.certifications.isEmpty || !coach.specializations.isEmpty || !coach.achievements.isEmpty {
                Divider().padding(.vertical, 8)
                sectionHeader("Credentials & Achievements")
                
                VStack(alignment: .leading, spacing: 16) {
                    if !coach.certifications.isEmpty {
                        credentialRow(title: "Certifications", items: coach.certifications, color: .green, icon: "checkmark.seal.fill")
                    }
                    if !coach.specializations.isEmpty {
                        credentialRow(title: "Specializations", items: coach.specializations, color: .orange, icon: "star.fill")
                    }
                    if !coach.achievements.isEmpty {
                        credentialRow(title: "Achievements", items: coach.achievements, color: .yellow, icon: "trophy.fill")
                    }
                }
            }
        }
    }
    
    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func credentialRow(title: String, items: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }
    }
    
    private var myPrograms: [Program] { dataManager.programs.filter { $0.coachId == effectiveCoachId } }
    private var myProgramsCount: Int { myPrograms.count }
    private var myStudentsCount: Int { Set(myPrograms.flatMap { $0.enrolledStudentIds }).count }
    
    // MARK: - Organization Section
    @State private var showingSecretCode = false
    @State private var isGeneratingCode = false
    @State private var currentSecretCode: String = ""
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Organization")
            
            // Current Organization Card
            if let org = AuthManager.shared.currentOrganization {
                settingsCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "#B8860B"), Color(hex: "#FFD700")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 50, height: 50)
                                
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(org.displayName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text("ID: \(org.name)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            
                            Spacer()
                            
                            if let role = AuthManager.shared.currentUser?.role {
                                Text(role.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "#B8860B"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "#B8860B").opacity(0.15))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(16)
                    }
                }
                
                // Secret Code Section (for admins)
                if AuthManager.shared.currentUser?.role.canGenerateSecretCode == true {
                    sectionHeader("Invite Team Members")
                    
                    settingsCard {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#B8860B"))
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Organization Secret Code")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text("Share this code to invite coaches")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            
                            // Secret Code Display
                            HStack(spacing: 12) {
                                if showingSecretCode {
                                    Text(currentSecretCode.isEmpty ? org.secretCode : currentSecretCode)
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .tracking(4)
                                } else {
                                    Text("••••••••")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                
                                Spacer()
                                
                                Button(action: { showingSecretCode.toggle() }) {
                                    Image(systemName: showingSecretCode ? "eye.slash" : "eye")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: copySecretCode) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            
                            // Generate New Code Button
                            Button(action: generateNewCode) {
                                HStack(spacing: 8) {
                                    if isGeneratingCode {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Text("Generate New Code")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(hex: "#B8860B"))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isGeneratingCode)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            
                            // Warning
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                
                                Text("Generating a new code will invalidate the old one. Anyone trying to join with the old code won't be able to.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .lineSpacing(2)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                    }
                }
            } else {
                // No organization
                settingsCard {
                    VStack(spacing: 16) {
                        Image(systemName: "building.2")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.textTertiary)
                        
                        Text("No Organization")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Create or join an organization to collaborate with your team")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            currentSecretCode = AuthManager.shared.currentOrganization?.secretCode ?? ""
        }
    }
    
    private func copySecretCode() {
        let code = currentSecretCode.isEmpty ? (AuthManager.shared.currentOrganization?.secretCode ?? "") : currentSecretCode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        HapticFeedback.notification(.success)
    }
    
    private func generateNewCode() {
        isGeneratingCode = true
        Task {
            do {
                let newCode = try await AuthManager.shared.regenerateSecretCode()
                await MainActor.run {
                    currentSecretCode = newCode
                    showingSecretCode = true
                    isGeneratingCode = false
                    HapticFeedback.notification(.success)
                }
            } catch {
                await MainActor.run {
                    isGeneratingCode = false
                    HapticFeedback.notification(.error)
                }
            }
        }
    }
    
    // MARK: - Notifications Section
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Notifications")
            
            settingsCard {
                VStack(spacing: 0) {
                    settingsToggleRow(
                        icon: "bell.fill",
                        iconColor: .blue,
                        title: "Enable Notifications",
                        subtitle: "Receive alerts and reminders",
                        isOn: Binding(
                            get: { localSettings.notificationsEnabled },
                            set: { newValue in
                                if newValue { requestNotificationPermission() }
                                else { localSettings.notificationsEnabled = false }
                            }
                        )
                    )
                    
                    Divider().padding(.leading, 44)
                    
                    settingsToggleRow(
                        icon: "clock.fill",
                        iconColor: .orange,
                        title: "Session Reminders",
                        subtitle: "Get notified before sessions start",
                        isOn: Binding(
                            get: { localSettings.sessionReminders },
                            set: { newValue in
                                localSettings.sessionReminders = newValue
                                if newValue && localSettings.notificationsEnabled { scheduleSessionReminders() }
                                else { cancelSessionReminders() }
                            }
                        )
                    )
                    .disabled(!localSettings.notificationsEnabled)
                    .opacity(localSettings.notificationsEnabled ? 1 : 0.5)
                    
                    if localSettings.sessionReminders && localSettings.notificationsEnabled {
                        Divider().padding(.leading, 44)
                        
                        HStack {
                            Image(systemName: "timer")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            
                            Text("Remind me")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            
                            Spacer()
                            
                            Picker("", selection: Binding(
                                get: { localSettings.reminderMinutesBefore },
                                set: { localSettings.reminderMinutesBefore = $0 }
                            )) {
                                Text("15 min before").tag(15)
                                Text("30 min before").tag(30)
                                Text("1 hour before").tag(60)
                                Text("2 hours before").tag(120)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
    
    // MARK: - Sync Section
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Sync & Data")
            
            settingsCard {
                VStack(spacing: 0) {
                    settingsToggleRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .green,
                        title: "Auto Sync",
                        subtitle: "Automatically sync data with cloud",
                        isOn: Binding(
                            get: { localSettings.autoSyncEnabled },
                            set: { localSettings.autoSyncEnabled = $0 }
                        )
                    )
                    
                    Divider().padding(.leading, 44)
                    
                    // Manual sync button
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync Now")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Last synced: \(lastSyncLabel)")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        Button(action: refreshCache) {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else if showingRefreshSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Text("Sync")
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            
            sectionHeader("Data Management")
            
            settingsCard {
                VStack(spacing: 0) {
                    // Export data
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Data")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Export all your data as JSON")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        Spacer()
                        
                        Button("Export") {
                            // Export functionality
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("About Hoopwise")
            
            settingsCard {
                VStack(spacing: 0) {
                    HStack {
                        // Hoopwise Logo
                        HoopwiseLogoView(size: 56, showBackground: true)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hoopwise")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Basketball Training Manager")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Text("v1.0.0")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .padding(16)
                    
                    Divider()
                    
                    // Links
                    VStack(spacing: 0) {
                        aboutLink(icon: "questionmark.circle", title: "Help & Support")
                        Divider().padding(.leading, 44)
                        aboutLink(icon: "lock.shield", title: "Privacy Policy")
                        Divider().padding(.leading, 44)
                        aboutLink(icon: "doc.text", title: "Terms of Service")
                    }
                }
            }
            
            sectionHeader("Developer Tools")
            
            settingsCard {
                Button(action: { exportAppIcons() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                        Text("Export App Icons")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        if isExportingIcons {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .disabled(isExportingIcons)
                
                if !iconExportStatus.isEmpty {
                    Divider()
                    Text(iconExportStatus)
                        .font(.system(size: 12))
                        .foregroundColor(iconExportStatus.contains("✅") ? .green : (iconExportStatus.contains("❌") ? .red : AppTheme.textSecondary))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            
            sectionHeader("Account")
            
            settingsCard {
                Button(action: { showingLogoutAlert = true }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                        Text("Log Out")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func aboutLink(icon: String, title: String) -> some View {
        Button(action: {}) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accentColor)
                    .frame(width: 28)
                
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Views
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func settingsToggleRow(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Actions
    private func handleLogout() {
        // Sign out from AuthManager
        AuthManager.shared.signOut()
        
        // Also clear legacy data manager state
        dataManager.logout()
        
        dismiss()
    }
    
    private func refreshCache() {
        isRefreshing = true
        showingRefreshSuccess = false
        
        Task {
            await dataManager.refreshAllCaches()
            if SupabaseManager.shared.isConnected {
                await dataManager.fullSync()
            }
            
            await MainActor.run {
                isRefreshing = false
                showingRefreshSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingRefreshSuccess = false
                }
            }
        }
    }

    private var lastSyncLabel: String {
        guard SupabaseManager.shared.isConnected else { return "Offline" }
        guard let date = dataManager.lastSyncDate else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                localSettings.notificationsEnabled = granted
            }
        }
    }
    
    private func scheduleSessionReminders() {
        let center = UNUserNotificationCenter.current()
        let upcomingSessions = dataManager.sessionEvents.filter { $0.date > Date() && $0.status == .scheduled }
        
        for session in upcomingSessions.prefix(10) {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming Session"
            content.body = "\(session.title) starts in \(localSettings.reminderMinutesBefore) minutes"
            content.sound = .default
            
            let triggerDate = session.startTime.addingTimeInterval(-Double(localSettings.reminderMinutesBefore * 60))
            guard triggerDate > Date() else { continue }
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "session-\(session.id)", content: content, trigger: trigger)
            center.add(request)
        }
    }
    
    private func cancelSessionReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // MARK: - Export App Icons
    private func exportAppIcons() {
        isExportingIcons = true
        iconExportStatus = "Exporting..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let sizes: [(name: String, size: Int)] = [
                // iOS
                ("AppIcon-iOS-1024", 1024),
                ("AppIcon-iOS-180", 180),
                ("AppIcon-iOS-167", 167),
                ("AppIcon-iOS-152", 152),
                ("AppIcon-iOS-120", 120),
                ("AppIcon-iOS-87", 87),
                ("AppIcon-iOS-80", 80),
                ("AppIcon-iOS-76", 76),
                ("AppIcon-iOS-60", 60),
                ("AppIcon-iOS-58", 58),
                ("AppIcon-iOS-40", 40),
                // macOS
                ("AppIcon-Mac-1024", 1024),
                ("AppIcon-Mac-512@2x", 1024),
                ("AppIcon-Mac-512", 512),
                ("AppIcon-Mac-256@2x", 512),
                ("AppIcon-Mac-256", 256),
                ("AppIcon-Mac-128@2x", 256),
                ("AppIcon-Mac-128", 128),
                ("AppIcon-Mac-64@2x", 128),
                ("AppIcon-Mac-64", 64),
                ("AppIcon-Mac-32@2x", 64),
                ("AppIcon-Mac-32", 32),
                ("AppIcon-Mac-16@2x", 32),
                ("AppIcon-Mac-16", 16)
            ]
            
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let outputDir = desktopURL.appendingPathComponent("HoopwiseAppIcons")
            
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                
                var exportedCount = 0
                for (name, size) in sizes {
                    DispatchQueue.main.async {
                        iconExportStatus = "Exporting \(name)..."
                    }
                    
                    // Render on main thread
                    DispatchQueue.main.sync {
                        if let image = renderAppIcon(size: CGFloat(size)) {
                            let url = outputDir.appendingPathComponent("\(name).png")
                            if let tiffData = image.tiffRepresentation,
                               let bitmap = NSBitmapImageRep(data: tiffData),
                               let pngData = bitmap.representation(using: .png, properties: [:]) {
                                try? pngData.write(to: url)
                                exportedCount += 1
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    iconExportStatus = "✅ Exported \(exportedCount) icons to Desktop/HoopwiseAppIcons/"
                    isExportingIcons = false
                    
                    // Open folder in Finder
                    NSWorkspace.shared.open(outputDir)
                }
            } catch {
                DispatchQueue.main.async {
                    iconExportStatus = "❌ Error: \(error.localizedDescription)"
                    isExportingIcons = false
                }
            }
        }
    }
    
    @MainActor
    private func renderAppIcon(size: CGFloat) -> NSImage? {
        let view = Image("HoopwiseLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        return renderer.nsImage
    }
}

// MARK: - Profile Edit Form (inline for macOS)
struct MacProfileEditForm: View {
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var introduction: String = ""
    @State private var yearsOfExperience: Int = 0
    @State private var hasChanges = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name & Email row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    TextField("Your Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, _ in hasChanges = true }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    TextField("Email Address", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: email) { _, _ in hasChanges = true }
                }
            }
            
            // Phone & Experience row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    TextField("Phone Number", text: $phone)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: phone) { _, _ in hasChanges = true }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Years of Experience")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Stepper(value: $yearsOfExperience, in: 0...50) {
                        Text("\(yearsOfExperience) years")
                            .font(.system(size: 14))
                    }
                    .onChange(of: yearsOfExperience) { _, _ in hasChanges = true }
                }
            }
            
            // Introduction
            VStack(alignment: .leading, spacing: 6) {
                Text("Introduction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                TextEditor(text: $introduction)
                    .font(.system(size: 13))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    .onChange(of: introduction) { _, _ in hasChanges = true }
            }
            
            // Save button
            if hasChanges {
                HStack {
                    Spacer()
                    Button("Save Changes") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .onAppear {
            loadCoachData()
        }
    }
    
    private func loadCoachData() {
        let coach = dataManager.coach
        name = coach.name
        email = coach.email
        phone = coach.phone ?? ""
        introduction = coach.introduction
        yearsOfExperience = coach.yearsOfExperience
        hasChanges = false
    }
    
    private func saveProfile() {
        var updatedCoach = dataManager.coach
        updatedCoach.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.phone = phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.introduction = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.yearsOfExperience = yearsOfExperience
        updatedCoach.updatedAt = Date()
        dataManager.updateCoach(updatedCoach)
        hasChanges = false
    }
}

#Preview {
    MacSettingsView()
        .environmentObject(DataManager.shared)
        .frame(width: 800, height: 600)
}
#endif
