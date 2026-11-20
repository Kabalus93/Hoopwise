import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import PhotosUI
import CloudKit
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
    @State private var localSettings: AppSettings = AppSettings.default
    @State private var calendarSyncOn = UserDefaults.standard.bool(forKey: CalendarSync.enabledKey)
    @AppStorage(ProfileBackgroundRemoval.enabledKey) private var removePhotoBackgrounds = true
    @State private var calendarSyncMessage: String?
    @StateObject private var syncMonitor = CloudSyncMonitor.shared
    @State private var iCloudAccountLabel: String?
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @State private var isRefreshing = false
    @State private var showingRefreshSuccess = false
    @State private var confirmingProductionMove = false
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
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// `vX.Y.Z (build)` pulled live from the app bundle's Info.plist so the
    /// Settings screen no longer has to be hand-edited each release. Falls
    /// back to a `v?` placeholder if either key is missing (shouldn't happen
    /// in a properly built target, but cheap insurance).
    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        return build.isEmpty ? "v\(short)" : "v\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                profileHeaderSection
                statsSection
                notificationsSection
                #if targetEnvironment(macCatalyst)
                claudeDesktopSection
                claudeKeySection
                #endif
                preferencesSection
                coachingSection
                syncSection
                aboutSection
                legalSection
            }
            .scrollContentBackground(.visible)
            .navigationTitle(isChinese ? "设置" : "Settings")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                FlightyEditCoachProfileView()
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
                fetchiCloudAccountLabel()
            }
        }
    }
    
    // MARK: - Profile Header Section (Form-styled, Apple Settings)
    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    avatarView
                        .frame(width: 64, height: 64)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Circle().fill(.background))
                                .offset(x: 4, y: 4)
                        }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task { await loadSelectedPhoto(newItem) }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.name.isEmpty ? (isChinese ? "设置你的资料" : "Set up your profile") : coach.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(coach.email.isEmpty
                         ? (isChinese ? "点按头像或编辑开始" : "Tap photo or Edit to get started")
                         : coach.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if coach.yearsOfExperience > 0 || !coach.certifications.isEmpty {
                        HStack(spacing: 10) {
                            if coach.yearsOfExperience > 0 {
                                Label("\(coach.yearsOfExperience) \(isChinese ? "年经验" : "yrs")",
                                      systemImage: "clock")
                            }
                            if !coach.certifications.isEmpty {
                                Label("\(coach.certifications.count) \(isChinese ? "证书" : "certs")",
                                      systemImage: "checkmark.seal")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)

            Button {
                showingEditProfile = true
            } label: {
                Label(isChinese ? "编辑资料" : "Edit Profile", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let profileImage {
            profileImage
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let imageUrl = coach.profileImageUrl,
                  !imageUrl.isEmpty,
                  imageUrl.hasPrefix("http"),
                  let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill().clipShape(Circle())
                case .failure, .empty:
                    defaultAvatarView
                @unknown default:
                    defaultAvatarView
                }
            }
        } else {
            defaultAvatarView
        }
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                statCell(value: "\(myStudentsCount)",
                         label: isChinese ? "学员" : "Athletes",
                         icon: "person.2")
                Divider().frame(height: 36)
                statCell(value: "\(myProgramsCount)",
                         label: isChinese ? "训练计划" : "Programs",
                         icon: "rectangle.stack")
                Divider().frame(height: 36)
                statCell(value: "\(mySessionsCount)",
                         label: isChinese ? "课程" : "Sessions",
                         icon: "calendar")
            }
            .padding(.vertical, 4)
        }
    }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Label(label, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                let compressedData = compressImageData(data)
                let localPath = saveProfileImageLocally(data: compressedData)

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

                    var updatedCoach = dataManager.coach
                    updatedCoach.profileImageUrl = localPath
                    updatedCoach.profileImageData = compressedData
                    updatedCoach.updatedAt = Date()
                    dataManager.updateCoach(updatedCoach)
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
    
    #if targetEnvironment(macCatalyst)
    // MARK: - Claude Desktop (Mac only, November 2026)
    @State private var claudeSetupCopied = false
    @State private var connectorOn = ConnectorSetup.isEnabled
    @State private var askingConnectorConsent = false
    @State private var savingBridge = false
    @State private var bridgeSaved = false

    /// Lets Claude Desktop work in the app (ClaudeConnector/). OFF until the
    /// coach turns it on and agrees to what it shares (17 Nov 2026); then the
    /// app serves on this Mac only, the coach saves the bridge and copies
    /// Claude Desktop's config entry here.
    private var claudeDesktopSection: some View {
        Section {
            Toggle(isOn: Binding(get: { connectorOn }, set: { on in
                if on { askingConnectorConsent = true } else { setConnector(false) }
            })) {
                Text(isChinese ? "允许 Claude Desktop 使用 Hoopwise" : "Let Claude Desktop use Hoopwise")
            }
            .accessibilityIdentifier("profile.connectorSwitch")
            if connectorOn {
                Button {
                    savingBridge = true
                } label: {
                    Label(bridgeSaved
                          ? (isChinese ? "已保存连接脚本" : "Bridge saved")
                          : (isChinese ? "保存连接脚本…" : "Save the bridge…"),
                          systemImage: bridgeSaved ? "checkmark" : "square.and.arrow.down")
                }
                Button {
                    UIPasteboard.general.string = ConnectorSetup.claudeDesktopConfig()
                    claudeSetupCopied = true
                } label: {
                    Label(claudeSetupCopied
                          ? (isChinese ? "已复制" : "Copied")
                          : (isChinese ? "复制 Claude Desktop 设置" : "Copy setup for Claude Desktop"),
                          systemImage: claudeSetupCopied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("profile.copyClaudeSetup")
            }
        } header: {
            Text(isChinese ? "Claude Desktop · 高级" : "Claude Desktop · Advanced")
        } footer: {
            Text(isChinese
                 ? "开启后，本机上的 Claude Desktop 可以查看学员姓名、课程、考勤和训练计划，并在你同意后进行修改，包括删除课程和战术；学员档案、合同和付款永远不会被删除。数据会按 Anthropic 的条款发送给 Claude。设置里含有访问密钥，请勿分享。"
                 : "When on, Claude Desktop on this Mac can read athletes' names, sessions, attendance and plans, and make changes you approve — including deleting sessions and plays. Athlete records, contracts and payments are never deleted. What Claude reads is sent to Anthropic under their terms. The setup contains this Mac's access key — don't share it.")
        }
        .alert(isChinese ? "允许 Claude Desktop 访问？" : "Let Claude Desktop in?", isPresented: $askingConnectorConsent) {
            Button(isChinese ? "允许" : "Allow") { setConnector(true) }
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
        } message: {
            Text(isChinese
                 ? "Claude Desktop 将能读取学员姓名、课程、考勤和训练计划，这些内容会发送给 Anthropic。每次修改前 Claude 都会征求你的同意。你可以随时关闭。"
                 : "Claude Desktop will be able to read athletes' names, sessions, attendance and plans, and what it reads is sent to Anthropic. Claude asks before every change. You can switch this off at any time.")
        }
        .fileExporter(isPresented: $savingBridge, document: ConnectorBridgeDocument(),
                      contentType: .pythonScript, defaultFilename: ConnectorBridgeScript.fileName) { result in
            if case .success(let url) = result {
                UserDefaults.standard.set(url.path, forKey: ConnectorSetup.savedBridgeKey)
                bridgeSaved = true
                claudeSetupCopied = false
            }
        }
    }

    private func setConnector(_ on: Bool) {
        ConnectorSetup.isEnabled = on
        connectorOn = on
        if on {
            ConnectorServer.shared.start(dataManager: dataManager)
        } else {
            ConnectorServer.shared.stop()
        }
    }

    // MARK: - Claude in the app (Mac only, November 2026)
    @State private var claudeKeySet = AnthropicKeyStore.key != nil
    @State private var claudeKeyDraft = ""
    @State private var claudeKeyEditing = false

    /// The Anthropic API key the app itself uses (the drills search asks
    /// Claude when Enter is pressed — DrillFinder). Kept in this Mac's
    /// Keychain only, never in the store or iCloud.
    private var claudeKeySection: some View {
        Section {
            if claudeKeySet && !claudeKeyEditing {
                HStack {
                    Label(isChinese ? "已设置 API 密钥" : "API key set", systemImage: "checkmark.seal")
                    Spacer()
                    Button(isChinese ? "更换" : "Change") { claudeKeyEditing = true }
                    Button(isChinese ? "移除" : "Remove", role: .destructive) {
                        AnthropicKeyStore.remove()
                        claudeKeySet = false
                    }
                }
            } else {
                SecureField(isChinese ? "粘贴 Anthropic API 密钥（sk-ant-…）" : "Paste an Anthropic API key (sk-ant-…)",
                            text: $claudeKeyDraft)
                    .accessibilityIdentifier("profile.anthropicKey")
                HStack {
                    Button(isChinese ? "保存到钥匙串" : "Save to Keychain") {
                        if AnthropicKeyStore.save(claudeKeyDraft) {
                            claudeKeySet = true
                            claudeKeyEditing = false
                            claudeKeyDraft = ""
                        }
                    }
                    .disabled(!claudeKeyDraft.trimmingCharacters(in: .whitespaces).hasPrefix("sk-ant-"))
                    if claudeKeyEditing {
                        Button(isChinese ? "取消" : "Cancel") { claudeKeyEditing = false; claudeKeyDraft = "" }
                    }
                }
            }
        } header: {
            Text(isChinese ? "App 中的 Claude" : "Claude in the app")
        } footer: {
            Text(isChinese
                 ? "在训练库的搜索栏输入描述并按回车，Claude 会从整个训练库中找出最接近的训练。只发送训练内容，不含学员信息。密钥只保存在这台 Mac 的钥匙串里，可在 console.anthropic.com 创建；每次查找花费不到一美分。"
                 : "In the drills library, type a description in the search bar and press Return: Claude finds the closest drills in the whole library. Only drill text is sent, never athletes. The key stays in this Mac's Keychain; create one at console.anthropic.com. A search costs under a cent.")
        }
    }
    #endif

    // MARK: - Notifications Section
    private var notificationsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { localSettings.notificationsEnabled },
                set: { newValue in
                    if newValue { requestNotificationPermission() }
                    else { localSettings.notificationsEnabled = false }
                })) {
                    Label(isChinese ? "推送通知" : "Push Notifications", systemImage: "bell")
                }

            Toggle(isOn: Binding(
                get: { localSettings.sessionReminders },
                set: { newValue in
                    localSettings.sessionReminders = newValue
                    if newValue && localSettings.notificationsEnabled { scheduleSessionReminders() }
                    else { cancelSessionReminders() }
                })) {
                    Label(isChinese ? "课程提醒" : "Session Reminders", systemImage: "alarm")
                }

            if localSettings.sessionReminders {
                Stepper(value: $localSettings.reminderMinutesBefore, in: 5...120, step: 5) {
                    HStack {
                        Text(isChinese ? "提前" : "Remind me")
                        Spacer()
                        Text("\(localSettings.reminderMinutesBefore) \(isChinese ? "分钟" : "min")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            // Sessions in Apple Calendar (CalendarSync): a "Hoopwise"
            // calendar of their own, kept in step after every change.
            Toggle(isOn: Binding(
                get: { calendarSyncOn },
                set: { newValue in setCalendarSync(newValue) })) {
                    Label(isChinese ? "同步到日历" : "Add Sessions to Calendar", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("profile.calendarSync")
        } header: {
            Text(isChinese ? "通知" : "Notifications")
        } footer: {
            Text(calendarSyncMessage ?? (isChinese
                 ? "在「日历」App 中新建 Hoopwise 日历，显示前 7 天到之后 60 天的课程；课程改动或取消时自动更新。"
                 : "Adds a Hoopwise calendar to the Calendar app with your sessions from the last 7 days to the next 60. It updates when a session moves or is cancelled."))
        }
        .onChange(of: localSettings) { _, newSettings in
            dataManager.updateAppSettings(newSettings)
        }
    }

    private func setCalendarSync(_ on: Bool) {
        calendarSyncMessage = nil
        if on {
            Task { @MainActor in
                if await CalendarSync.requestAccess() {
                    UserDefaults.standard.set(true, forKey: CalendarSync.enabledKey)
                    calendarSyncOn = true
                    CalendarSync.syncNow(dataManager: dataManager)
                } else {
                    calendarSyncOn = false
                    calendarSyncMessage = isChinese
                        ? "没有日历权限。请在「设置 › Hoopwise › 日历」中选择「完全访问」。"
                        : "Calendar access is off. Allow Full Access in Settings › Hoopwise › Calendars."
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: CalendarSync.enabledKey)
            calendarSyncOn = false
            CalendarSync.removeCalendar()
        }
    }

    // MARK: - Preferences Section
    private var preferencesSection: some View {
        Section {
            Picker(selection: Binding(
                    get: { LocalizationManager.shared.currentLanguage },
                    set: { newLang in
                        LocalizationManager.shared.setLanguage(newLang)
                        localSettings.language = newLang.rawValue
                    })) {
                Text("English").tag(AppLanguage.english)
                Text("中文").tag(AppLanguage.chinese)
                Text("Español").tag(AppLanguage.spanish)
            } label: {
                Label(isChinese ? "语言" : "Language", systemImage: "globe")
            }

            NavigationLink {
                AreaLanguageSettingsView()
            } label: {
                Label(isChinese ? "分区语言" : "Languages by Area", systemImage: "character.bubble")
            }
            .accessibilityIdentifier("profile.areaLanguages")

            Picker(selection: $localSettings.currency) {
                ForEach(CurrencyType.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            } label: {
                Label(isChinese ? "货币" : "Currency", systemImage: "dollarsign.circle")
            }

            Toggle(isOn: Binding(
                get: { localSettings.hapticFeedbackEnabled },
                set: { newValue in
                    localSettings.hapticFeedbackEnabled = newValue
                    if newValue { HapticFeedback.impact(.medium) }
                })) {
                    Label(isChinese ? "触感反馈" : "Haptic Feedback", systemImage: "hand.tap")
                }

            // ProfileBackgroundRemoval: after a profile photo, the subject is
            // cut out on this device and a background colour picked.
            Toggle(isOn: $removePhotoBackgrounds) {
                Label(isChinese ? "去除照片背景" : "Remove Photo Backgrounds", systemImage: "person.crop.circle.badge.minus")
            }
            .accessibilityIdentifier("profile.removePhotoBackgrounds")
        } header: {
            Text(isChinese ? "偏好设置" : "Preferences")
        } footer: {
            Text(isChinese
                 ? "拍学员头像后，在本机自动抠出人物。背景颜色显示该学员在组内的水平：红 最佳 · 黄 较好 · 绿 平均 · 蓝 低于平均 · 紫 组内末位。分享或打印卡片时可另选颜色。照片不会离开设备。"
                 : "After you take an athlete's photo, the person is cut out on this device. The colour behind them shows their level in their group: red best · yellow better · green average · blue below average · purple bottom of the group. When sharing or printing a card you can keep it or pick another. Photos never leave the device.")
        }
    }

    // MARK: - Coaching Section
    private var coachingSection: some View {
        Section {
            NavigationLink {
                PhaseTemplatesEditorView()
                    .environmentObject(dataManager)
            } label: {
                Label(isChinese ? "训练阶段模板" : "Phase Templates", systemImage: "rectangle.stack.fill")
            }
        } header: {
            Text(isChinese ? "教练" : "Coaching")
        } footer: {
            Text(isChinese
                 ? "编辑各年龄段使用的 FEB 训练阶段。空白时自动使用 FEB 默认配置。"
                 : "Edit the FEB phase chains used per age group. Falls back to FEB defaults when empty.")
        }
    }

    // MARK: - Sync Section
    private var syncSection: some View {
        Section {
            // No "Auto Sync" toggle: SwiftData drives CloudKit itself and the setting
            // gated nothing. The stored SDCoach.autoSyncEnabled field is left alone so
            // the schema is unchanged.
            if let label = iCloudAccountLabel {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isChinese ? "iCloud" : "iCloud")
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: iCloudStatus == .available ? "icloud.fill" : "icloud.slash")
                            .foregroundStyle(iCloudStatus == .available ? Color.accentColor : .orange)
                    }
                    Spacer()
                }
            }

            HStack {
                Text(isChinese ? "上次同步" : "Last synced")
                Spacer()
                Text(syncMonitor.lastSyncLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let error = syncMonitor.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Was labelled "Sync Now", which was false — it only re-reads the local
            // store into memory. Same action, honest name.
            Button {
                refreshCache()
            } label: {
                HStack {
                    Label(isChinese ? "重新载入数据" : "Reload Data",
                          systemImage: showingRefreshSuccess ? "checkmark" : "arrow.clockwise")
                    Spacer()
                    if isRefreshing { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isRefreshing)

            productionMoveRows
        } header: {
            Text(isChinese ? "同步" : "Sync")
        } footer: {
            Text(isChinese
                 ? "数据通过 iCloud 自动同步，无需手动触发。「重新载入数据」仅刷新本设备上已有的数据。"
                 : "Data syncs with iCloud automatically; there is nothing to trigger by hand. Reload Data only refreshes what is already on this device.")
        }
    }

    // MARK: - Bring the data over to Production (15 Nov 2026)

    /// Release builds only: the Development copy on this device can be
    /// brought into this build's iCloud (Production) once; afterwards the
    /// report says what came across. See ProductionMove.
    @ViewBuilder
    private var productionMoveRows: some View {
        if let report = ProductionMove.lastReport {
            VStack(alignment: .leading, spacing: 4) {
                Label(report.ok
                      ? (isChinese ? "数据已迁入" : "Your data was brought over")
                      : (isChinese ? "迁移有问题" : "The move reported a problem"),
                      systemImage: report.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.ok ? Color.green : Color.orange)
                Text(productionMoveSummary(report))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("profile.moveReport")
        } else if productionMoveOffered {
            Button {
                confirmingProductionMove = true
            } label: {
                Label(isChinese ? "迁入你的数据" : "Bring over your data", systemImage: "square.and.arrow.down.on.square")
            }
            .accessibilityIdentifier("profile.moveData")
            .confirmationDialog(isChinese ? "把开发版的数据迁入这个版本？" : "Bring over the data from the development version?",
                                isPresented: $confirmingProductionMove, titleVisibility: .visible) {
                Button(isChinese ? "迁入并关闭 Hoopwise" : "Bring It Over and Close Hoopwise") {
                    ProductionMove.requestMove()
                    exit(0)
                }
                Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(isChinese
                     ? "这台设备上开发版的全部数据（学员、课程、合同和付款、战术、训练……）会复制到这个版本的 iCloud，然后同步到你的其他设备。只做一次，并在数据最完整的设备上做。Hoopwise 会关闭——再次打开即开始。"
                     : "Everything the development version holds on this device — athletes, sessions, contracts and payments, plays, drills — is copied into this version's iCloud and then syncs to your other devices. Do it once, on the device whose copy is most complete. Hoopwise will close; open it again to start.")
            }
        }
    }

    private var productionMoveOffered: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOOPWISE_MOVE_OFFER"] == "1" { return true }
        #endif
        return ProductionMove.isOffered
    }

    private func productionMoveSummary(_ report: ProductionMove.Report) -> String {
        if let error = report.error { return error }
        func count(_ entity: String) -> Int { report.lines.first { $0.entity == entity }?.copied ?? 0 }
        let parts = isChinese
            ? ["\(count("SDStudent")) 名学员", "\(count("SDSessionEvent")) 节课", "\(count("SDContract")) 份合同", "\(count("JournalPlay")) 个战术"]
            : ["\(count("SDStudent")) athletes", "\(count("SDSessionEvent")) sessions", "\(count("SDContract")) contracts", "\(count("JournalPlay")) plays"]
        let tail = report.ok
            ? (isChinese ? "，每个字段都核对无误。正在上传到 iCloud。" : ", every field checked. Uploading to iCloud.")
            : (isChinese ? "。\(report.mismatches) 行不一致。" : ". \(report.mismatches) rows differ.")
        return parts.joined(separator: " · ") + tail
    }

    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                Image("HoopwiseAppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoopwise")
                        .font(.body)
                    Text(isChinese ? "篮球训练管理系统" : "Basketball Training Manager")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appVersionDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Legal Section
    private var legalSection: some View {
        Section {
            legalLink(title: isChinese ? "帮助" : "Help",
                      systemImage: "questionmark.circle",
                      urlString: "https://support.apple.com")
            legalLink(title: isChinese ? "隐私" : "Privacy",
                      systemImage: "lock.shield",
                      urlString: "https://www.apple.com/legal/privacy")
            legalLink(title: isChinese ? "条款" : "Terms",
                      systemImage: "doc.text",
                      urlString: "https://www.apple.com/legal/internet-services/terms")
        }
    }

    private func legalLink(title: String, systemImage: String, urlString: String) -> some View {
        Button {
            #if os(iOS)
            if let url = URL(string: urlString) { UIApplication.shared.open(url) }
            #elseif os(macOS)
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
            #endif
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private var iCloudIconName: String {
        iCloudStatus == .available ? "icloud.fill" : "icloud.slash"
    }

    private var iCloudIconColor: Color {
        iCloudStatus == .available ? AppTheme.accentColor : .orange
    }

    private func fetchiCloudAccountLabel() {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        Task {
            let status: CKAccountStatus
            do {
                // Not CKContainer.default(): that resolves to iCloud.{bundleID},
                // which exists for neither target, so it never reported real status.
                status = try await CKContainer(identifier: CloudSyncMonitor.containerIdentifier)
                    .accountStatus()
            } catch {
                await MainActor.run {
                    iCloudStatus = .couldNotDetermine
                    iCloudAccountLabel = nil
                }
                return
            }
            let label: String?
            switch status {
            case .available:
                label = isChinese ? "已同步至 iCloud" : "Synced to iCloud"
            case .noAccount:
                label = isChinese ? "在系统设置中登录 iCloud 以启用同步" : "Sign in to iCloud in Settings to enable sync"
            case .restricted:
                label = isChinese ? "iCloud 受限" : "iCloud access restricted"
            case .couldNotDetermine, .temporarilyUnavailable:
                label = nil
            @unknown default:
                label = nil
            }
            await MainActor.run {
                iCloudStatus = status
                iCloudAccountLabel = label
            }
        }
    }
    // MARK: - Actions
    private func refreshCache() {
        isRefreshing = true
        showingRefreshSuccess = false
        
        if localSettings.hapticFeedbackEnabled {
            HapticFeedback.impact(.medium)
        }
        
        Task {
            await dataManager.refreshAllCaches()

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
            let minutes = localSettings.reminderMinutesBefore
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            content.sound = .default
            NotificationCard.stamp(content, kind: .upcoming,
                                   headline: isChinese ? "\(minutes) 分钟后上课" : "Session in \(minutes) minutes",
                                   detail: "\(session.title) · \(NotificationCard.time(session.startTime))")
            
            let triggerDate = session.startTime.addingTimeInterval(-Double(localSettings.reminderMinutesBefore * 60))
            guard triggerDate > Date() else { continue }
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: "session-\(session.id)", content: content, trigger: trigger)
            center.add(request)
        }
    }
    
    /// Cancels only THESE reminders ("session-<id>"). It used to remove every
    /// pending request — the coach's own reminders and the next-cycle reminder
    /// with them — whenever Session Reminders was switched off.
    private func cancelSessionReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix("session-") && !$0.hasPrefix("session-start-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

// MARK: - Flighty Edit Coach Profile View
struct FlightyEditCoachProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name: String = ""
    @State private var chineseName: String = ""
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
                    
                    let isCN = LocalizationManager.shared.currentLanguage == .chinese

                    // Certifications Card
                    listCard(
                        title: isCN ? "证书" : "CERTIFICATIONS",
                        icon: "checkmark.seal.fill",
                        iconColor: .green,
                        items: $certifications,
                        newItem: $newCertification,
                        placeholder: isCN ? "添加证书…" : "Add certification...",
                        hint: isCN ? "例如：FIBA 二级, 青少年发展认证" : "e.g., FIBA Level 2, Youth Development Certified"
                    )

                    // Specializations Card
                    listCard(
                        title: isCN ? "专长" : "SPECIALIZATIONS",
                        icon: "star.fill",
                        iconColor: .orange,
                        items: $specializations,
                        newItem: $newSpecialization,
                        placeholder: isCN ? "添加专长…" : "Add specialization...",
                        hint: isCN ? "例如：青少年发展, 投篮技术" : "e.g., Youth Development, Shooting Mechanics"
                    )

                    // Achievements Card
                    listCard(
                        title: isCN ? "成就" : "ACHIEVEMENTS",
                        icon: "trophy.fill",
                        iconColor: AppTheme.gold,
                        items: $achievements,
                        newItem: $newAchievement,
                        placeholder: isCN ? "添加成就…" : "Add achievement...",
                        hint: isCN ? "例如：U14 区域冠军 2023" : "e.g., Regional U14 Champions 2023"
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

            // Chinese name field — surfaced as the watermark name on
            // attendance photos shared in WeChat, and elsewhere we want
            // a name that reads natively in CN.
            inputField(label: "中文名", placeholder: "可选 / Optional", text: $chineseName)

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
        chineseName = coach.chineseName ?? ""
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
        let trimmedChineseName = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)

        var updatedCoach = dataManager.coach
        updatedCoach.name = trimmedName
        updatedCoach.chineseName = trimmedChineseName.isEmpty ? nil : trimmedChineseName
        updatedCoach.email = trimmedEmail
        updatedCoach.phone = trimmedPhone
        updatedCoach.introduction = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedCoach.yearsOfExperience = yearsOfExperience
        updatedCoach.certifications = certifications
        updatedCoach.specializations = specializations
        updatedCoach.achievements = achievements
        updatedCoach.updatedAt = Date()
        
        if let imageData = profileImageData {
            updatedCoach.profileImageData = imageData

            let savedUrl = saveProfileImageFromEdit(data: imageData)
            if !savedUrl.isEmpty {
                updatedCoach.profileImageUrl = savedUrl
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
            updatedStaffCoach.coachingSpecializations = coach.specializations
            updatedStaffCoach.profileImageData = coach.profileImageData
            updatedStaffCoach.updatedAt = Date()
            dataManager.updateStaffCoach(updatedStaffCoach)
        } else if let existingStaffCoach = dataManager.staffCoaches.first(where: { $0.id == coach.id }) {
            // Fallback: match on coach.id directly
            var updatedStaffCoach = existingStaffCoach
            updatedStaffCoach.name = coach.name
            updatedStaffCoach.email = coach.email
            updatedStaffCoach.phone = coach.phone
            updatedStaffCoach.coachingSpecializations = coach.specializations
            updatedStaffCoach.profileImageData = coach.profileImageData
            updatedStaffCoach.updatedAt = Date()
            dataManager.updateStaffCoach(updatedStaffCoach)
        } else {
            let staffCoach = StaffCoach(
                id: matchId,
                organizationId: nil,
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

#Preview {
    FlightyCoachProfileView()
        .environmentObject(DataManager.shared)
}

#if targetEnvironment(macCatalyst)
/// The bridge script as a file the coach saves (Profile → Claude Desktop).
struct ConnectorBridgeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pythonScript] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(ConnectorBridgeScript.source.utf8))
    }
}
#endif
