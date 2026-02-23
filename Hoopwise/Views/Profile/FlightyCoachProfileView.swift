import SwiftUI
import UserNotifications
import PhotosUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Flighty Coach Profile View
/// A clean, light-themed profile and settings view matching the actionable dashboard style
struct FlightyCoachProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingEditProfile = false
    @State private var showingLogoutAlert = false
    @State private var localSettings: AppSettings = AppSettings.default
    @State private var isRefreshing = false
    @State private var showingRefreshSuccess = false
    @State private var notificationPermissionDenied = false
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Image?
    
    private var coach: Coach {
        dataManager.coach
    }

    private var effectiveCoachId: UUID {
        dataManager.loggedInCoachId ?? coach.id
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Profile Header Card
                    profileHeaderCard
                    
                    // Quick Stats
                    quickStatsRow
                    
                    // Settings Cards
                    notificationsCard
                    
                    preferencesCard
                    
                    // App Info & Actions
                    appInfoCard
                    
                    // Danger Zone
                    dangerZoneCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeadingCompat) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.cardBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.surfaceColor, lineWidth: 1)
                            )
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "设置" : "Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                FlightyEditCoachProfileView()
            }
            .alert(LocalizationManager.shared.currentLanguage == .chinese ? "退出登录" : "Log Out", isPresented: $showingLogoutAlert) {
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "退出" : "Log Out", role: .destructive) {
                    handleLogout()
                }
            } message: {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "确定要退出登录吗？您的本地数据将被保留。" : "Are you sure you want to log out? Your local data will be preserved.")
            }
            .alert(LocalizationManager.shared.currentLanguage == .chinese ? "通知已禁用" : "Notifications Disabled", isPresented: $notificationPermissionDenied) {
                #if os(iOS)
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "打开设置" : "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            } message: {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "请在设置中启用通知以接收提醒。" : "Please enable notifications in Settings to receive alerts.")
            }
            .onAppear {
                localSettings = dataManager.appSettings
                loadSavedProfileImage()
            }
        }
    }
    
    // MARK: - Profile Header Card
    private var profileHeaderCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Avatar - Tappable for photo picker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack {
                        if let profileImage = profileImage {
                            profileImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else if let imageUrl = coach.profileImageUrl, !imageUrl.isEmpty, imageUrl.hasPrefix("http"), let url = URL(string: imageUrl) {
                            // Cloud URL - use AsyncImage
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                case .failure, .empty:
                                    defaultAvatarView
                                @unknown default:
                                    defaultAvatarView
                                }
                            }
                        } else {
                            defaultAvatarView
                        }
                        
                        // Camera badge
                        Circle()
                            .fill(AppTheme.cardBackground)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.accentColor)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            .offset(x: 20, y: 20)
                    }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task { await loadSelectedPhoto(newItem) }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if coach.name.isEmpty {
                        Text("Set up your profile")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Tap photo or Edit to get started")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    } else {
                        Text(coach.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(coach.email.isEmpty ? "No email set" : coach.email)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: { showingEditProfile = true }) {
                    Text("Edit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(16)
            
            // Experience badge
            if coach.yearsOfExperience > 0 || !coach.certifications.isEmpty {
                Divider()
                
                HStack(spacing: 12) {
                    if coach.yearsOfExperience > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.accentColor)
                            Text("\(coach.yearsOfExperience) years experience")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    
                    if !coach.certifications.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("\(coach.certifications.count) certification\(coach.certifications.count == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            quickStatCard(
                value: "\(myStudentsCount)",
                label: "Athletes",
                icon: "person.fill",
                color: .blue
            )
            
            quickStatCard(
                value: "\(myProgramsCount)",
                label: "Programs",
                icon: "folder.fill",
                color: .purple
            )
            
            quickStatCard(
                value: "\(mySessionsCount)",
                label: "Sessions",
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
    }
    
    private func quickStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    private var myPrograms: [Program] {
        // Show all programs - this is a single-coach app
        // Filter by coachId if set, otherwise show all
        let coachPrograms = dataManager.programs.filter { $0.coachId == effectiveCoachId }
        return coachPrograms.isEmpty ? dataManager.programs : coachPrograms
    }
    
    private var myProgramsCount: Int {
        // Show active (non-archived) programs count
        dataManager.programs.filter { $0.status != .archived }.count
    }
    
    private var myStudentsCount: Int {
        // Show total students count
        dataManager.students.count
    }
    
    private var mySessionsCount: Int {
        // Show sessions count (excluding sessions from archived programs)
        let archivedProgramIds = Set(dataManager.programs.filter { $0.status == .archived }.map { $0.id })
        return dataManager.sessionEvents.filter { session in
            guard let programId = session.programId else { return true }
            return !archivedProgramIds.contains(programId)
        }.count
    }
    
    private var defaultAvatarView: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient)
                .frame(width: 60, height: 60)
            
            Text(coach.initials)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Compress image for upload
                let compressedData = compressImageData(data)
                
                // Try to upload to cloud first for cross-platform sync
                var cloudUrl: String? = nil
                if SupabaseManager.shared.isConnected {
                    do {
                        let path = "coaches/\(effectiveCoachId.uuidString).jpg"
                        cloudUrl = try await SupabaseManager.shared.uploadImage(imageData: compressedData, bucket: "profile-images", path: path)
                        debugLog("✅ Profile image uploaded to cloud: \(cloudUrl ?? "")")
                    } catch {
                        debugLog("⚠️ Cloud upload failed, saving locally: \(error)")
                    }
                }
                
                // Also save locally as fallback
                let localPath = saveProfileImageLocally(data: compressedData)
                
                // Use cloud URL if available, otherwise local path
                let finalUrl = cloudUrl ?? localPath
                
                await MainActor.run {
                    #if os(iOS)
                    if let uiImage = UIImage(data: compressedData) {
                        profileImage = Image(uiImage: uiImage)
                        HapticFeedback.notification(.success)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: compressedData) {
                        profileImage = Image(nsImage: nsImage)
                    }
                    #endif
                    
                    // Update coach with new profile image URL and data (data as backup)
                    var updatedCoach = dataManager.coach
                    updatedCoach.profileImageUrl = finalUrl
                    updatedCoach.profileImageData = compressedData  // Store data directly for persistence
                    updatedCoach.updatedAt = Date()
                    dataManager.updateCoach(updatedCoach)
                    debugLog("✅ Coach profile image saved - URL: \(finalUrl ?? "none"), Data size: \(compressedData.count) bytes")
                }
            }
        } catch {
            debugLog("Error loading photo: \(error)")
        }
    }
    
    private func compressImageData(_ data: Data) -> Data {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            // Resize to max 400x400 for profile images
            let maxSize: CGFloat = 400
            let scale = min(maxSize / uiImage.size.width, maxSize / uiImage.size.height, 1.0)
            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let compressed = resizedImage?.jpegData(compressionQuality: 0.7) {
                return compressed
            }
        }
        #endif
        return data
    }
    
    private func saveProfileImageLocally(data: Data) -> String {
        let fileManager = FileManager.default
        let fileName = "coach_profile_\(effectiveCoachId.uuidString).jpg"
        
        #if os(macOS)
        // On macOS, use Application Support directory
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let samFolder = appSupportURL.appendingPathComponent("SAM/ProfileImages", isDirectory: true)
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: samFolder.path) {
                try? fileManager.createDirectory(at: samFolder, withIntermediateDirectories: true)
            }
            
            let fileURL = samFolder.appendingPathComponent(fileName)
            do {
                try data.write(to: fileURL)
                return fileURL.path
            } catch {
                debugLog("Error saving profile image: \(error)")
                return ""
            }
        }
        #else
        // On iOS, use Documents directory
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let profileFolder = documentsURL.appendingPathComponent("ProfileImages", isDirectory: true)
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: profileFolder.path) {
                try? fileManager.createDirectory(at: profileFolder, withIntermediateDirectories: true)
            }
            
            let fileURL = profileFolder.appendingPathComponent(fileName)
            do {
                try data.write(to: fileURL)
                return fileURL.path
            } catch {
                debugLog("Error saving profile image: \(error)")
                return ""
            }
        }
        #endif
        
        return ""
    }
    
    private func loadSavedProfileImage() {
        // First try to load from stored image data (most reliable)
        if let imageData = coach.profileImageData, !imageData.isEmpty {
            #if os(iOS)
            if let uiImage = UIImage(data: imageData) {
                profileImage = Image(uiImage: uiImage)
                debugLog("✅ Loaded profile image from stored data (\(imageData.count) bytes)")
                return
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: imageData) {
                profileImage = Image(nsImage: nsImage)
                debugLog("✅ Loaded profile image from stored data (\(imageData.count) bytes)")
                return
            }
            #endif
        }
        
        // Fall back to URL if no stored data
        guard let imagePath = coach.profileImageUrl, !imagePath.isEmpty else { return }
        
        // Check if it's a cloud URL (starts with http)
        if imagePath.hasPrefix("http") {
            // Cloud URL - AsyncImage will handle it in the view
            return
        }
        
        // Handle local file paths
        let fileURL: URL
        if imagePath.hasPrefix("file://") {
            guard let url = URL(string: imagePath) else { return }
            fileURL = url
        } else {
            fileURL = URL(fileURLWithPath: imagePath)
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            debugLog("⚠️ Profile image file not found at: \(fileURL.path)")
            return
        }
        
        guard let data = try? Data(contentsOf: fileURL) else {
            debugLog("⚠️ Could not load profile image data")
            return
        }
        
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            profileImage = Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            profileImage = Image(nsImage: nsImage)
        }
        #endif
    }
    
    // MARK: - Notifications Card
    private var notificationsCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.warningColor)
                Text(isChinese ? "通知" : "Notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 16)
            
            // Push notifications
            settingsRow(
                icon: "app.badge",
                iconColor: .red,
                title: isChinese ? "推送通知" : "Push Notifications",
                toggle: Binding(
                    get: { localSettings.notificationsEnabled },
                    set: { newValue in
                        if newValue { requestNotificationPermission() }
                        else { localSettings.notificationsEnabled = false }
                    }
                )
            )
            
            Divider().padding(.leading, 52)
            
            // Session reminders
            settingsRow(
                icon: "clock.badge",
                iconColor: .blue,
                title: isChinese ? "课程提醒" : "Session Reminders",
                subtitle: isChinese ? "\(localSettings.reminderMinutesBefore) 分钟前" : "\(localSettings.reminderMinutesBefore) min before",
                toggle: Binding(
                    get: { localSettings.sessionReminders },
                    set: { newValue in
                        localSettings.sessionReminders = newValue
                        if newValue && localSettings.notificationsEnabled { scheduleSessionReminders() }
                        else { cancelSessionReminders() }
                    }
                )
            )
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
        .onChange(of: localSettings) { _, newSettings in
            dataManager.updateAppSettings(newSettings)
        }
    }
    
    // MARK: - Preferences Card
    private var preferencesCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accentColor)
                Text(isChinese ? "偏好设置" : "Preferences")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 16)
            
            // Language selector
            languageRow
            
            Divider().padding(.leading, 52)
            
            // Currency selector
            currencyRow
            
            Divider().padding(.leading, 52)
            
            // Auto sync
            settingsRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .green,
                title: isChinese ? "自动同步" : "Auto Sync",
                subtitle: isChinese ? "自动同步数据" : "Sync data automatically",
                toggle: Binding(
                    get: { localSettings.autoSyncEnabled },
                    set: { localSettings.autoSyncEnabled = $0 }
                )
            )
            
            Divider().padding(.leading, 52)
            
            // Haptic feedback
            settingsRow(
                icon: "hand.tap.fill",
                iconColor: .indigo,
                title: isChinese ? "触感反馈" : "Haptic Feedback",
                toggle: Binding(
                    get: { localSettings.hapticFeedbackEnabled },
                    set: { newValue in
                        localSettings.hapticFeedbackEnabled = newValue
                        if newValue { HapticFeedback.impact(.medium) }
                    }
                )
            )
            
            Divider().padding(.leading, 52)
            
            // Manual sync button
            Button(action: refreshCache) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else if showingRefreshSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.accentColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "立即同步" : "Sync Now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "从云端刷新所有数据" : "Refresh all data from cloud")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .disabled(isRefreshing)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    // MARK: - App Info Card
    private var appInfoCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                Text(isChinese ? "关于" : "About")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 16)
            
            // App version
            HStack(spacing: 12) {
                Image("HoopwiseAppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoopwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(isChinese ? "篮球训练管理系统" : "Basketball Training Manager")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Spacer()
                
                Text("v1.0.0")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider().padding(.leading, 52)
            
            // Links row
            HStack(spacing: 0) {
                linkButton(icon: "questionmark.circle", title: isChinese ? "帮助" : "Help")
                
                Rectangle()
                    .fill(AppTheme.textTertiary.opacity(0.3))
                    .frame(width: 1, height: 24)
                
                linkButton(icon: "lock.shield", title: isChinese ? "隐私" : "Privacy")
                
                Rectangle()
                    .fill(AppTheme.textTertiary.opacity(0.3))
                    .frame(width: 1, height: 24)
                
                linkButton(icon: "doc.text", title: isChinese ? "条款" : "Terms")
            }
            .padding(.vertical, 8)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    private func linkButton(icon: String, title: String) -> some View {
        Button(action: {
            // Open appropriate URL based on title
            #if os(iOS)
            var urlString: String?
            switch title {
            case "Help":
                urlString = "https://support.apple.com" // Placeholder - replace with actual help URL
            case "Privacy":
                urlString = "https://www.apple.com/legal/privacy" // Placeholder
            case "Terms":
                urlString = "https://www.apple.com/legal/internet-services/terms" // Placeholder
            default:
                break
            }
            if let urlString = urlString, let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            #endif
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Danger Zone Card
    private var dangerZoneCard: some View {
        Button(action: { showingLogoutAlert = true }) {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "退出登录" : "Log Out")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Language Row
    private var languageRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "语言" : "Language")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "切换应用语言" : "Switch app language")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Menu {
                Button(action: {
                    LocalizationManager.shared.setLanguage(.english)
                    localSettings.language = "en"
                    HapticFeedback.impact(.light)
                }) {
                    HStack {
                        Text("English")
                        if LocalizationManager.shared.currentLanguage == .english {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: {
                    LocalizationManager.shared.setLanguage(.chinese)
                    localSettings.language = "zh"
                    HapticFeedback.impact(.light)
                }) {
                    HStack {
                        Text("中文")
                        if LocalizationManager.shared.currentLanguage == .chinese {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(LocalizationManager.shared.currentLanguage.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.accentColor.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Currency Row
    private var currencyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "货币" : "Currency")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "显示收入货币" : "Display currency for revenue")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Menu {
                ForEach(CurrencyType.allCases, id: \.self) { currency in
                    Button(action: {
                        localSettings.currency = currency
                        HapticFeedback.impact(.light)
                    }) {
                        HStack {
                            Text(currency.displayName)
                            if localSettings.currency == currency {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(localSettings.currency.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.warningColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.warningColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.warningColor.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Settings Row Helper
    private func settingsRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        toggle: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: toggle)
                .tint(AppTheme.accentColor)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        
        if localSettings.hapticFeedbackEnabled {
            HapticFeedback.impact(.medium)
        }
        
        Task {
            await dataManager.refreshAllCaches()

            if SupabaseManager.shared.isConnected {
                await dataManager.fullSync()
            }
            
            await MainActor.run {
                isRefreshing = false
                showingRefreshSuccess = true
                
                if localSettings.hapticFeedbackEnabled {
                    HapticFeedback.notification(.success)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingRefreshSuccess = false
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    localSettings.notificationsEnabled = true
                    if localSettings.hapticFeedbackEnabled {
                        HapticFeedback.notification(.success)
                    }
                } else {
                    localSettings.notificationsEnabled = false
                    notificationPermissionDenied = true
                }
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
}

// MARK: - Flighty Edit Coach Profile View
struct FlightyEditCoachProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var introduction: String = ""
    @State private var yearsOfExperience: Int = 0
    @State private var certifications: [String] = []
    @State private var specializations: [String] = []
    @State private var achievements: [String] = []
    
    @State private var newCertification: String = ""
    @State private var newSpecialization: String = ""
    @State private var newAchievement: String = ""
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var profileImageData: Data?
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Avatar Section
                    avatarSection
                    
                    // Basic Info Card
                    basicInfoCard
                    
                    // About Card
                    aboutCard
                    
                    // Certifications Card
                    listCard(
                        title: "CERTIFICATIONS",
                        icon: "checkmark.seal.fill",
                        iconColor: .green,
                        items: $certifications,
                        newItem: $newCertification,
                        placeholder: "Add certification...",
                        hint: "e.g., FIBA Level 2, Youth Development Certified"
                    )
                    
                    // Specializations Card
                    listCard(
                        title: "SPECIALIZATIONS",
                        icon: "star.fill",
                        iconColor: .orange,
                        items: $specializations,
                        newItem: $newSpecialization,
                        placeholder: "Add specialization...",
                        hint: "e.g., Youth Development, Shooting Mechanics"
                    )
                    
                    // Achievements Card
                    listCard(
                        title: "ACHIEVEMENTS",
                        icon: "trophy.fill",
                        iconColor: Color(hex: "#FFD700"),
                        items: $achievements,
                        newItem: $newAchievement,
                        placeholder: "Add achievement...",
                        hint: "e.g., Regional U14 Champions 2023"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeadingCompat) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Edit Profile")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailingCompat) {
                    Button("Save") { saveProfile() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            .onAppear { loadCoachData() }
        }
    }
    
    // MARK: - Avatar Section
    private var avatarSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    if let profileImage = profileImage {
                        profileImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else if let imageUrl = dataManager.coach.profileImageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                defaultEditAvatarView
                            @unknown default:
                                defaultEditAvatarView
                            }
                        }
                    } else {
                        defaultEditAvatarView
                    }
                    
                    // Camera badge
                    Circle()
                        .fill(AppTheme.cardBackground)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accentColor)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .offset(x: 28, y: 28)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { await loadSelectedPhotoForEdit(newItem) }
            }
            
            Text("Tap to change photo")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    private var defaultEditAvatarView: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient)
                .frame(width: 80, height: 80)
            
            Text(initials)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func loadSelectedPhotoForEdit(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                #if os(iOS)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        profileImage = Image(uiImage: uiImage)
                        profileImageData = data
                        HapticFeedback.impact(.light)
                    }
                }
                #endif
            }
        } catch {
            debugLog("Error loading photo: \(error)")
        }
    }
    
    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    // MARK: - Basic Info Card
    private var basicInfoCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("CONTACT INFO")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().padding(.horizontal, 16)
            
            // Name field
            inputField(label: "Name", placeholder: "Your name", text: $name)
            
            Divider().padding(.leading, 16)
            
            // Email field
            inputField(label: "Email", placeholder: "email@example.com", text: $email)
            
            Divider().padding(.leading, 16)
            
            // Phone field
            inputField(label: "Phone", placeholder: "Phone number", text: $phone)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    private func inputField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 60, alignment: .leading)
            
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - About Card
    private var aboutCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text("ABOUT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().padding(.horizontal, 16)
            
            // Introduction
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $introduction)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                
                Text("A brief description about yourself and your coaching philosophy")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider().padding(.horizontal, 16)
            
            // Years of experience
            HStack {
                Text("Years of Experience")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: { if yearsOfExperience > 0 { yearsOfExperience -= 1 } }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(yearsOfExperience > 0 ? AppTheme.accentColor : AppTheme.textTertiary.opacity(0.3))
                    }
                    .disabled(yearsOfExperience == 0)
                    
                    Text("\(yearsOfExperience)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 40)
                    
                    Button(action: { if yearsOfExperience < 50 { yearsOfExperience += 1 } }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    // MARK: - List Card
    private func listCard(
        title: String,
        icon: String,
        iconColor: Color,
        items: Binding<[String]>,
        newItem: Binding<String>,
        placeholder: String,
        hint: String
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().padding(.horizontal, 16)
            
            // Existing items
            ForEach(items.wrappedValue, id: \.self) { item in
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(iconColor.opacity(0.6))
                    
                    Text(item)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: {
                        items.wrappedValue.removeAll { $0 == item }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                Divider().padding(.leading, 40)
            }
            
            // Add new item
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                
                TextField(placeholder, text: newItem)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
                    .onSubmit {
                        addItem(to: items, from: newItem)
                    }
                
                if !newItem.wrappedValue.isEmpty {
                    Button(action: { addItem(to: items, from: newItem) }) {
                        Text("Add")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Hint
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    private func addItem(to items: Binding<[String]>, from newItem: Binding<String>) {
        let trimmed = newItem.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !items.wrappedValue.contains(trimmed) else { return }
        items.wrappedValue.append(trimmed)
        newItem.wrappedValue = ""
    }
    
    // MARK: - Actions
    private func loadCoachData() {
        let coach = dataManager.coach
        name = coach.name
        email = coach.email
        phone = coach.phone ?? ""
        introduction = coach.introduction
        yearsOfExperience = coach.yearsOfExperience
        certifications = coach.certifications
        specializations = coach.specializations
        achievements = coach.achievements
    }
    
    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var updatedCoach = dataManager.coach
        updatedCoach.name = trimmedName
        updatedCoach.email = trimmedEmail
        updatedCoach.phone = trimmedPhone
        updatedCoach.introduction = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.yearsOfExperience = yearsOfExperience
        updatedCoach.certifications = certifications
        updatedCoach.specializations = specializations
        updatedCoach.achievements = achievements
        updatedCoach.updatedAt = Date()
        
        // Save profile image if changed
        if let imageData = profileImageData {
            // Always store image data directly for reliable persistence
            updatedCoach.profileImageData = imageData
            
            // Save locally as fallback
            let savedUrl = saveProfileImageFromEdit(data: imageData)
            if !savedUrl.isEmpty {
                updatedCoach.profileImageUrl = savedUrl
            }
            
            // Upload to Supabase storage for cross-device sync
            if SupabaseManager.shared.isConnected {
                let coachId = dataManager.loggedInCoachId ?? dataManager.coach.id
                Task {
                    do {
                        let path = "coaches/\(coachId.uuidString).jpg"
                        let cloudUrl = try await SupabaseManager.shared.uploadImage(imageData: imageData, bucket: "profile-images", path: path)
                        // Update with cloud URL on success
                        var cloudCoach = updatedCoach
                        cloudCoach.profileImageUrl = cloudUrl
                        await MainActor.run {
                            dataManager.updateCoach(cloudCoach)
                        }
                        debugLog("✅ Profile image uploaded to Supabase from edit view")
                    } catch {
                        debugLog("⚠️ Cloud upload from edit view failed: \(error)")
                    }
                }
            }
        }
        
        dataManager.updateCoach(updatedCoach)
        
        if !trimmedName.isEmpty {
            syncStaffCoachWithProfile(updatedCoach)
        }
        
        dismiss()
    }
    
    private func saveProfileImageFromEdit(data: Data) -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "coach_profile_\(dataManager.coach.id.uuidString).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL.absoluteString
        } catch {
            debugLog("Error saving profile image: \(error)")
            return ""
        }
    }
    
    private func syncStaffCoachWithProfile(_ coach: Coach) {
        // Try to find matching staff coach by coach.id OR loggedInCoachId
        let matchId = dataManager.loggedInCoachId ?? coach.id
        if let existingStaffCoach = dataManager.staffCoaches.first(where: { $0.id == matchId }) {
            var updatedStaffCoach = existingStaffCoach
            updatedStaffCoach.name = coach.name
            updatedStaffCoach.email = coach.email
            updatedStaffCoach.phone = coach.phone
            updatedStaffCoach.specializations = coach.specializations
            updatedStaffCoach.profileImageData = coach.profileImageData
            updatedStaffCoach.updatedAt = Date()
            dataManager.updateStaffCoach(updatedStaffCoach)
        } else if let existingStaffCoach = dataManager.staffCoaches.first(where: { $0.id == coach.id }) {
            // Fallback: match on coach.id directly
            var updatedStaffCoach = existingStaffCoach
            updatedStaffCoach.name = coach.name
            updatedStaffCoach.email = coach.email
            updatedStaffCoach.phone = coach.phone
            updatedStaffCoach.specializations = coach.specializations
            updatedStaffCoach.profileImageData = coach.profileImageData
            updatedStaffCoach.updatedAt = Date()
            dataManager.updateStaffCoach(updatedStaffCoach)
        } else {
            let staffCoach = StaffCoach(
                id: matchId,
                organizationId: AuthManager.shared.currentOrganization?.id,
                name: coach.name,
                email: coach.email,
                phone: coach.phone,
                role: .head,
                specializations: coach.specializations,
                ageGroups: AgeGroup.allCases,
                avatarColor: .purple,
                isActive: true,
                hireDate: coach.createdAt,
                notes: "Main app profile coach",
                profileImageData: coach.profileImageData
            )
            dataManager.addStaffCoach(staffCoach)
        }
    }
}

// MARK: - API Keys Settings View
struct APIKeysSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var groqApiKey: String = ""
    @State private var claudeApiKey: String = ""
    @State private var showingSaveSuccess = false
    @State private var isTestingGroq = false
    @State private var isTestingClaude = false
    @State private var groqTestResult: TestResult?
    @State private var claudeTestResult: TestResult?
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header Info
                infoCard
                
                // Groq API Key Card
                groqCard
                
                // Claude API Key Card
                claudeCard
                
                // Save Button
                saveButton
            }
            .padding(16)
        }
        .background(Color(hex: "#f5f5f7"))
        .navigationTitle(isChinese ? "AI API 密钥" : "AI API Keys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            groqApiKey = dataManager.appSettings.groqApiKey
            claudeApiKey = dataManager.appSettings.claudeApiKey
        }
    }
    
    // MARK: - Info Card
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                
                Text(isChinese ? "关于 API 密钥" : "About API Keys")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Text(isChinese ?
                "API 密钥用于连接 AI 服务。您的密钥安全地存储在设备上，不会发送到我们的服务器。" :
                "API keys are used to connect to AI services. Your keys are stored securely on your device and are never sent to our servers.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .lineSpacing(4)
            
            Divider()
            
            Text(isChinese ?
                "💡 建议：Groq 提供免费额度，速度更快，推荐优先使用。" :
                "💡 Tip: Groq offers free credits and faster responses. Recommended as primary option.")
                .font(.system(size: 13))
                .foregroundColor(.orange)
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    // MARK: - Groq Card
    private var groqCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Groq")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text(isChinese ? "推荐" : "Recommended")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .cornerRadius(6)
                    }
                    
                    Text(isChinese ? "超快速 AI • 免费额度" : "Ultra-fast AI • Free tier")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if !groqApiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }
            }
            
            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "API 密钥" : "API Key")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    SecureField(isChinese ? "gsk_..." : "gsk_...", text: $groqApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(14)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(12)
                    
                    // Test Button
                    Button(action: testGroqKey) {
                        if isTestingGroq {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 70, height: 44)
                        } else {
                            Text(isChinese ? "测试" : "Test")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 70, height: 44)
                                .background(groqApiKey.isEmpty ? Color.gray : Color.orange)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(groqApiKey.isEmpty || isTestingGroq)
                }
                
                // Test Result
                if let result = groqTestResult {
                    HStack(spacing: 6) {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(isChinese ? "连接成功!" : "Connection successful!")
                                .foregroundColor(.green)
                        case .failure(let message):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(message)
                                .foregroundColor(.red)
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            
            // Get Key Link
            Link(destination: URL(string: "https://console.groq.com/keys")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text(isChinese ? "从 console.groq.com 获取密钥" : "Get key from console.groq.com")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    // MARK: - Claude Card
    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Text(isChinese ? "高级 AI • 按使用付费" : "Advanced AI • Pay per use")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if !claudeApiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }
            }
            
            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "API 密钥" : "API Key")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    SecureField(isChinese ? "sk-ant-..." : "sk-ant-...", text: $claudeApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(14)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(12)
                    
                    // Test Button
                    Button(action: testClaudeKey) {
                        if isTestingClaude {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 70, height: 44)
                        } else {
                            Text(isChinese ? "测试" : "Test")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 70, height: 44)
                                .background(claudeApiKey.isEmpty ? Color.gray : Color.purple)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(claudeApiKey.isEmpty || isTestingClaude)
                }
                
                // Test Result
                if let result = claudeTestResult {
                    HStack(spacing: 6) {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(isChinese ? "连接成功!" : "Connection successful!")
                                .foregroundColor(.green)
                        case .failure(let message):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(message)
                                .foregroundColor(.red)
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            
            // Get Key Link
            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text(isChinese ? "从 console.anthropic.com 获取密钥" : "Get key from console.anthropic.com")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.purple)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: saveKeys) {
            HStack(spacing: 10) {
                if showingSaveSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text(isChinese ? "已保存!" : "Saved!")
                } else {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 18))
                    Text(isChinese ? "保存密钥" : "Save Keys")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: showingSaveSuccess ? [Color.green, Color.green.opacity(0.8)] : [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: showingSaveSuccess ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), radius: 12, y: 6)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    private func saveKeys() {
        var settings = dataManager.appSettings
        settings.groqApiKey = groqApiKey
        settings.claudeApiKey = claudeApiKey
        dataManager.updateAppSettings(settings)
        
        HapticFeedback.notification(.success)
        
        withAnimation(.spring(response: 0.3)) {
            showingSaveSuccess = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingSaveSuccess = false
            }
        }
    }
    
    private func testGroqKey() {
        isTestingGroq = true
        groqTestResult = nil
        
        Task {
            do {
                let _ = try await GroqManager.shared.sendMessage(
                    query: "Say 'Hello' in one word",
                    context: "",
                    language: "en",
                    apiKey: groqApiKey
                )
                await MainActor.run {
                    groqTestResult = .success
                    isTestingGroq = false
                    HapticFeedback.notification(.success)
                }
            } catch let error as GroqError {
                await MainActor.run {
                    switch error {
                    case .invalidApiKey:
                        groqTestResult = .failure(isChinese ? "密钥无效" : "Invalid key")
                    default:
                        groqTestResult = .failure(isChinese ? "连接失败" : "Connection failed")
                    }
                    isTestingGroq = false
                    HapticFeedback.notification(.error)
                }
            } catch {
                await MainActor.run {
                    groqTestResult = .failure(isChinese ? "连接失败" : "Connection failed")
                    isTestingGroq = false
                    HapticFeedback.notification(.error)
                }
            }
        }
    }
    
    private func testClaudeKey() {
        isTestingClaude = true
        claudeTestResult = nil
        
        Task {
            do {
                let _ = try await ClaudeManager.shared.sendMessage(
                    query: "Say 'Hello' in one word",
                    context: "",
                    language: "en",
                    apiKey: claudeApiKey
                )
                await MainActor.run {
                    claudeTestResult = .success
                    isTestingClaude = false
                    HapticFeedback.notification(.success)
                }
            } catch let error as ClaudeError {
                await MainActor.run {
                    switch error {
                    case .invalidApiKey:
                        claudeTestResult = .failure(isChinese ? "密钥无效" : "Invalid key")
                    default:
                        claudeTestResult = .failure(isChinese ? "连接失败" : "Connection failed")
                    }
                    isTestingClaude = false
                    HapticFeedback.notification(.error)
                }
            } catch {
                await MainActor.run {
                    claudeTestResult = .failure(isChinese ? "连接失败" : "Connection failed")
                    isTestingClaude = false
                    HapticFeedback.notification(.error)
                }
            }
        }
    }
}

#Preview {
    FlightyCoachProfileView()
        .environmentObject(DataManager.shared)
}
