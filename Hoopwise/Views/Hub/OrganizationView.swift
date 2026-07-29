import SwiftUI
import MapKit
import Combine
import UniformTypeIdentifiers
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
    @State private var selectedTab: OrgTab = .coaches

    // Phase 2 — bundle export state
    @State private var pendingShare: ExportedBundleHandle?
    @State private var exportError: String?
    @State private var isExporting = false

    // Phase 3 — bundle import state
    @State private var showingImportPicker = false
    @State private var importPlan: HoopwiseBundleImporter.ImportPlan?
    @State private var importError: String?
    @State private var isAnalyzingImport = false
    @State private var importSuccessMessage: String?

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    /// Wrap the URL so .sheet(item:) can present it.
    struct ExportedBundleHandle: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    enum OrgTab: String, CaseIterable {
        case coaches = "Coaches"
        case locations = "Locations"
        case schools = "Schools"
        case categories = "Categories"

        var icon: String {
            switch self {
            case .coaches: return "person.2.fill"
            case .locations: return "mappin.circle.fill"
            case .schools: return "building.columns.fill"
            case .categories: return "rectangle.stack.fill"
            }
        }

        var localizedName: String {
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .coaches: return isChinese ? "教练" : "Coaches"
            case .locations: return isChinese ? "地点" : "Locations"
            case .schools: return isChinese ? "学校" : "Schools"
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

                // Share Organization Data — Phase 2 of export/import
                shareOrganizationCard
                    .padding(.horizontal, 16)

                Picker("Section", selection: $selectedTab) {
                    ForEach(OrgTab.allCases, id: \.self) { tab in
                        Label(tab.localizedName, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: selectedTab)
                
                // Content based on selected tab
                switch selectedTab {
                case .coaches:
                    CoachesListSection()
                case .locations:
                    LocationsListSection()
                case .schools:
                    SchoolsListSection()
                case .categories:
                    CategoriesListSection()
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isChinese ? "教练人员" : "Coaching Staff")
        .navigationBarTitleDisplayModeCompat(.large)
        .sheet(item: $pendingShare) { handle in
            #if os(iOS)
            ActivityShareSheet(activityItems: [handle.url]) {
                // Optional: clean up the temp file once dismissed.
                try? FileManager.default.removeItem(at: handle.url)
            }
            .ignoresSafeArea()
            #else
            EmptyView()
            #endif
        }
        .alert(
            isChinese ? "导出失败" : "Export Failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button(isChinese ? "好的" : "OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        // Phase 3 — Import flow
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { startImportAnalysis(url: url) }
            case .failure(let err):
                importError = err.localizedDescription
            }
        }
        .sheet(item: $importPlan) { plan in
            BundleImportPreviewSheet(
                plan: plan,
                onConfirm: { applyImport(plan: plan) },
                onCancel: { importPlan = nil }
            )
            .environmentObject(dataManager)
        }
        .alert(
            isChinese ? "导入失败" : "Import Failed",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button(isChinese ? "好的" : "OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(
            isChinese ? "导入成功" : "Import Complete",
            isPresented: Binding(get: { importSuccessMessage != nil }, set: { if !$0 { importSuccessMessage = nil } })
        ) {
            Button(isChinese ? "好的" : "OK", role: .cancel) { importSuccessMessage = nil }
        } message: {
            Text(importSuccessMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .hoopwiseBundleOpenRequest)) { note in
            // External file taps (AirDrop / Mail / Files / Messages) route here.
            if let url = note.userInfo?["url"] as? URL {
                startImportAnalysis(url: url)
            }
        }
    }

    // MARK: - Share Organization Data Card

    /// Modern Apple-style "share data" card. Shows what's about to leave the
    /// device (counts + excluded students), and a single big button that
    /// builds the bundle on demand and presents the iOS share sheet.
    private var shareOrganizationCard: some View {
        let stats = HoopwiseBundleExporter(dataManager: dataManager).previewStats()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.headline)
                        .foregroundStyle(Color.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "共享组织数据" : "Share Organization Data")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(isChinese
                         ? "导出学员、训练动作、地点、考勤记录"
                         : "Export students, drills, locations, attendance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Counts row
            HStack(spacing: 16) {
                shareStat(value: "\(stats.studentCount)", icon: "person.fill", label: isChinese ? "学员" : "students")
                shareStat(value: "\(stats.drillCount)", icon: "figure.basketball", label: isChinese ? "训练" : "drills")
                shareStat(value: "\(stats.coachCount)", icon: "person.2.fill", label: isChinese ? "教练" : "coaches")
                shareStat(value: "\(stats.locationCount)", icon: "mappin", label: isChinese ? "地点" : "locations")
                Spacer()
            }

            if stats.excludedStudentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text(excludedSubtitle(stats.excludedStudentCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: startExport) {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isChinese ? "共享…" : "Share…")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isExporting || stats.studentCount == 0)
                .opacity((isExporting || stats.studentCount == 0) ? 0.6 : 1.0)

                Button(action: { showingImportPicker = true }) {
                    HStack(spacing: 6) {
                        if isAnalyzingImport {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isChinese ? "导入…" : "Import…")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzingImport)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Import flow

    private func startImportAnalysis(url: URL) {
        isAnalyzingImport = true
        Task {
            // Some files arrive with security-scoped access; ensure we have it.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let importer = HoopwiseBundleImporter(dataManager: dataManager)
                let plan = try importer.analyze(url: url)
                await MainActor.run {
                    importPlan = plan
                    isAnalyzingImport = false
                }
            } catch {
                await MainActor.run {
                    importError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    isAnalyzingImport = false
                }
            }
        }
    }

    private func applyImport(plan: HoopwiseBundleImporter.ImportPlan) {
        importPlan = nil
        Task {
            do {
                let importer = HoopwiseBundleImporter(dataManager: dataManager)
                try importer.apply(plan)
                await MainActor.run {
                    importSuccessMessage = importSuccessText(plan: plan)
                }
            } catch {
                await MainActor.run {
                    importError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                }
            }
        }
    }

    private func importSuccessText(plan: HoopwiseBundleImporter.ImportPlan) -> String {
        let s = plan.summary
        if isChinese {
            return "已从 \(s.sourceCoachName) 导入：\(s.newStudents) 位新学员，更新 \(s.updatedStudents) 位；\(s.newDrills) 个新训练，更新 \(s.updatedDrills) 个。"
        }
        return "Imported from \(s.sourceCoachName): \(s.newStudents) new students, \(s.updatedStudents) updated; \(s.newDrills) new drills, \(s.updatedDrills) updated."
    }

    private func shareStat(value: String, icon: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func excludedSubtitle(_ count: Int) -> String {
        if isChinese {
            return "\(count) 位私密学员将不会被分享"
        }
        return count == 1
            ? "1 private athlete excluded"
            : "\(count) private athletes excluded"
    }

    private func startExport() {
        isExporting = true
        Task {
            do {
                let exporter = HoopwiseBundleExporter(dataManager: dataManager)
                let url = try exporter.exportToTempFile()
                await MainActor.run {
                    pendingShare = ExportedBundleHandle(url: url)
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = "\(error)"
                    isExporting = false
                }
            }
        }
    }

    // MARK: - Organization Hero Card (Compact)
    private var organizationHeroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? "教练人员" : "Coaching Staff")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(isChinese ? "本地名册" : "Local roster")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                compactStat(value: "\(dataManager.staffCoaches.count)", icon: "person.2.fill")
                compactStat(value: "\(dataManager.locations.count)", icon: "mappin")
                compactStat(value: "\(dataManager.programs.count)", icon: "folder.fill")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func compactStat(value: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

// MARK: - Bundle Import Preview Sheet
//
// Shown after the user picks a .hoopwise file (or taps one in Files /
// AirDrop / Mail). Renders the diff that the importer computed — what's
// new, what will be updated, what's unchanged — and lets the coach
// confirm or cancel. Confirm fires an atomic merge with snapshot-before-
// import so a future Undo Import (Phase 4) can revert the whole bundle.

struct BundleImportPreviewSheet: View {
    let plan: HoopwiseBundleImporter.ImportPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if plan.summary.totalChanges == 0 {
                    Section {
                        Text(isChinese
                             ? "此文件中的所有数据已是最新版本，没有需要更新的内容。"
                             : "Everything in this file is already up to date. Nothing to import.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(isChinese ? "学员" : "Students") {
                        diffRow(label: isChinese ? "新增" : "New", count: plan.summary.newStudents, color: .green)
                        diffRow(label: isChinese ? "更新" : "Updated", count: plan.summary.updatedStudents, color: .orange)
                        diffRow(label: isChinese ? "已是最新（跳过）" : "Already up to date (skipped)", count: plan.summary.skippedStudents, color: .secondary)
                    }
                    Section(isChinese ? "训练动作" : "Drills") {
                        diffRow(label: isChinese ? "新增" : "New", count: plan.summary.newDrills, color: .green)
                        diffRow(label: isChinese ? "更新" : "Updated", count: plan.summary.updatedDrills, color: .orange)
                        diffRow(label: isChinese ? "跳过" : "Skipped", count: plan.summary.skippedDrills, color: .secondary)
                    }
                    Section(isChinese ? "组织" : "Organization") {
                        diffRow(label: isChinese ? "新教练" : "New coaches", count: plan.summary.newCoaches, color: .green)
                        diffRow(label: isChinese ? "更新教练" : "Updated coaches", count: plan.summary.updatedCoaches, color: .orange)
                        diffRow(label: isChinese ? "新地点" : "New locations", count: plan.summary.newLocations, color: .green)
                        diffRow(label: isChinese ? "更新地点" : "Updated locations", count: plan.summary.updatedLocations, color: .orange)
                    }
                }

                Section {
                    safetyFooter
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle(isChinese ? "导入预览" : "Review Import")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(plan.summary.totalChanges == 0
                           ? (isChinese ? "完成" : "Done")
                           : (isChinese ? "导入" : "Import")) {
                        if plan.summary.totalChanges > 0 {
                            onConfirm()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title3)
                        .foregroundStyle(Color.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "来自 \(plan.summary.sourceCoachName)" : "From \(plan.summary.sourceCoachName)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(isChinese
                         ? "导出于 \(formattedDate(plan.summary.bundleExportedAt))"
                         : "Exported \(formattedDate(plan.summary.bundleExportedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if plan.summary.excludedFromBundleCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text(isChinese
                         ? "对方已从此文件中排除 \(plan.summary.excludedFromBundleCount) 位私密学员"
                         : "Sender excluded \(plan.summary.excludedFromBundleCount) private athletes from this file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func diffRow(label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(count > 0 ? .primary : .secondary)
        }
        .padding(.vertical, 2)
    }

    private var safetyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(isChinese
                     ? "导入永远不会删除任何内容。"
                     : "Importing never deletes anything.")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Label {
                Text(isChinese
                     ? "每位被更新的学员/训练都会保留一份可恢复的备份。"
                     : "Every updated athlete and drill keeps a restorable backup.")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = isChinese ? Locale(identifier: "zh_CN") : Locale.current
        return f.string(from: date)
    }
}

// MARK: - Share Sheet bridge
//
// Wraps UIActivityViewController so SwiftUI can present AirDrop / Mail / Files /
// Messages / iCloud Drive in one tap. iOS-only; macOS uses NSSharingServicePicker
// when we add Mac sharing later.

#if os(iOS)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Coaches List Section
struct CoachesListSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddCoach = false
    @State private var selectedCoach: StaffCoach?
    @State private var searchText = ""

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var filteredCoaches: [StaffCoach] {
        if searchText.isEmpty {
            return dataManager.staffCoaches
        }
        return dataManager.staffCoaches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            PanelSearchBar(text: $searchText, placeholder: isChinese ? "搜索教练..." : "Search coaches...")
                .padding(.horizontal, 16)

            Button {
                showingAddCoach = true
            } label: {
                Label(isChinese ? "添加教练" : "Add Coach", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.regular)
            .tint(Color.accentColor)
            .padding(.horizontal, 16)
            .sensoryFeedback(.selection, trigger: showingAddCoach)

            if filteredCoaches.isEmpty {
                PanelEmptyState(
                    icon: "person.2",
                    title: searchText.isEmpty ? (isChinese ? "暂无教练" : "No Coaches Yet") : (isChinese ? "无结果" : "No Results"),
                    subtitle: searchText.isEmpty ? (isChinese ? "添加教练到您的组织" : "Add coaches to your organization") : (isChinese ? "试试其他搜索" : "Try a different search")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredCoaches) { coach in
                        CoachCardRow(coach: coach)
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
    @EnvironmentObject var dataManager: DataManager
    @State private var profileImage: Image?

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
                    
                    if isProfileCoach {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .onAppear {
                    loadProfileImage()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let chineseName = coach.chineseName, !chineseName.isEmpty {
                            Text(chineseName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("(\(coach.name))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(coach.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        if isProfileCoach {
                            Text(isChinese ? "您" : "You")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: .rect(cornerRadius: 4))
                        }
                    }

                    HStack(spacing: 8) {
                        Label {
                            Text(coach.role.rawValue)
                                .font(.caption.weight(.medium))
                        } icon: {
                            Image(systemName: coach.role.icon).font(.caption2)
                        }
                        .foregroundStyle(.secondary)

                        Text("·").foregroundStyle(.tertiary)

                        Label {
                            Text(coach.accessLevel.rawValue)
                                .font(.caption2)
                        } icon: {
                            Image(systemName: coach.accessLevel.icon).font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if !coachPrograms.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(coachPrograms.prefix(2)) { program in
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                            if coachPrograms.count > 2 {
                                Text("+\(coachPrograms.count - 2)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .glassEffect(isProfileCoach ? .regular.tint(Color.accentColor.opacity(0.08)) : .regular, in: .rect(cornerRadius: 12))
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
    
}

// MARK: - Coach Profile Detail View
struct CoachProfileDetailView: View {
    let coach: StaffCoach
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager

    @State private var showingEditCoach = false

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var coachPrograms: [Program] {
        dataManager.programs.filter { $0.coachId == coach.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileHeader

                    Text(isChinese ? "本地名册" : "Local roster")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if !coachPrograms.isEmpty {
                        programsSection
                    }

                    if coach.email != nil || coach.phone != nil {
                        contactSection
                    }

                    actionButtons

                    Spacer(minLength: 50)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isChinese ? "教练资料" : "Coach Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "关闭" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "编辑" : "Edit") {
                        showingEditCoach = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingEditCoach) {
                AddEditCoachView(coach: coach)
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.avatarColor(coach.avatarColor).opacity(0.2))
                    .frame(width: 100, height: 100)

                Text(coach.initials)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.avatarColor(coach.avatarColor))
            }

            VStack(spacing: 4) {
                if let chineseName = coach.chineseName, !chineseName.isEmpty {
                    Text(chineseName)
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                    Text(coach.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(coach.name)
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 8) {
                Label {
                    Text(coach.role.rawValue)
                        .font(.footnote.weight(.medium))
                } icon: {
                    Image(systemName: coach.role.icon).font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor, in: .rect(cornerRadius: 8))

                Label {
                    Text(coach.accessLevel.rawValue)
                        .font(.caption.weight(.medium))
                } icon: {
                    Image(systemName: coach.accessLevel.icon).font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: .rect(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    
    // MARK: - Programs Section
    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(isChinese ? "负责项目" : "Assigned Programs")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "folder.fill").font(.subheadline)
                }
                .foregroundStyle(.primary)

                Spacer()

                Text("\(coachPrograms.count)")
                    .font(.footnote.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ForEach(coachPrograms) { program in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)

                    Text(program.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(program.enrolledStudentIds.count) " + (isChinese ? "学员" : "students"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Contact Section
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "联系方式" : "Contact Info")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "envelope.fill").font(.subheadline)
            }
            .foregroundStyle(.primary)

            if let email = coach.email, !email.isEmpty {
                HStack {
                    Text(isChinese ? "邮箱" : "Email")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }

            if let phone = coach.phone, !phone.isEmpty {
                HStack {
                    Text(isChinese ? "电话" : "Phone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(phone)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let phone = coach.phone, !phone.isEmpty {
                Button {
                    #if os(iOS)
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "phone.fill").font(.title3)
                        Text(isChinese ? "拨打" : "Call")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.regular)
                .tint(.green)
            }

            if let email = coach.email, !email.isEmpty {
                Button {
                    #if os(iOS)
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "envelope.fill").font(.title3)
                        Text(isChinese ? "邮件" : "Email")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.regular)
                .tint(Color.accentColor)
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
                
                Button {
                    showingAddLocation = true
                } label: {
                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "添加地点" : "Add Location", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.regular)
                .tint(Color.accentColor)
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: showingAddLocation)
                
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
            
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label {
                            Text(location.courtType.rawValue)
                                .font(.system(size: 9, weight: .semibold))
                        } icon: {
                            Image(systemName: location.courtType.icon)
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(location.courtType.color.opacity(0.9), in: .rect(cornerRadius: 6))

                        if !location.isActive {
                            Text(isChinese ? "未激活" : "Inactive")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .rect(cornerRadius: 6))
                        }
                    }

                    Text(location.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let address = location.fullAddress {
                        Label {
                            Text(address)
                                .font(.caption2)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "mappin").font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(location.courtCount)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(isChinese ? "球场" : (location.courtCount == 1 ? "Court" : "Courts"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 16))
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
                Button {
                    showingAddCategory = true
                } label: {
                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "添加类别" : "Add Category", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.regular)
                .tint(Color.accentColor)
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: showingAddCategory)
                
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
            AgeBadge(shortName: category.shortName, tint: category.color, size: .medium, filled: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !category.isActive {
                        PanelBadge(text: isChinese ? "未激活" : "Inactive", color: .secondary)
                    }
                }
                Text(category.ageRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(category.ballSize.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(category.rimHeight.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
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
                    VStack(spacing: 8) {
                        PanelAvatar(initials: chineseName.isEmpty ? (name.isEmpty ? "?" : String(name.prefix(2)).uppercased()) : String(chineseName.prefix(1)), color: Color.avatarColor(avatarColor), size: 56)

                        if !chineseName.isEmpty {
                            VStack(spacing: 2) {
                                Text(chineseName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !name.isEmpty {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(name.isEmpty ? (isChinese ? "教练姓名" : "Coach Name") : name)
                                .font(.headline)
                                .foregroundStyle(name.isEmpty ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                        }

                        PanelBadge(text: role.rawValue, color: .secondary)

                        if isEditing {
                            HStack(spacing: 16) {
                                VStack(spacing: 2) {
                                    Text("\(coachPrograms.count)")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(Color.accentColor)
                                        .contentTransition(.numericText())
                                    Text(isChinese ? "项目" : "Programs")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                VStack(spacing: 2) {
                                    Text("\(totalStudents)")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(.green)
                                        .contentTransition(.numericText())
                                    Text(isChinese ? "学员" : "Students")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                                .fill(Color.accentColor)
                                                .frame(width: 32, height: 32)
                                            Image(systemName: program.mascot.icon)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(program.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                            let studentCount = dataManager.students.filter { $0.programId == program.id }.count
                                            Text("\(studentCount) \(isChinese ? "学员" : "students")")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            selectedProgramForReassign = program
                                            showingReassignSheet = true
                                        } label: {
                                            Label(isChinese ? "转移" : "Reassign", systemImage: "arrow.left.arrow.right")
                                                .font(.caption2.weight(.medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .controlSize(.mini)
                                        .tint(Color.accentColor)
                                    }
                                    .padding(8)
                                    .background(.quaternary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.tertiary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.tertiary)
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
                                        .foregroundColor(Color.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
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
                                        .foregroundColor(newSpecialization.isEmpty ? AppTheme.textTertiary : Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(newSpecialization.isEmpty)
                            }
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(8)
                        }
                    }
                    
                    if isEditing {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(isChinese ? "删除教练" : "Delete Coach", systemImage: "trash")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .controlSize(.regular)

                        Label {
                            Text(isChinese ? "删除操作不可撤销，将从云端永久删除" : "Deletion is permanent and syncs to cloud")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEditing ? (isChinese ? "编辑教练" : "Edit Coach") : (isChinese ? "添加教练" : "Add Coach"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { saveCoach() }
                        .fontWeight(.semibold)
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
            organizationId: coach?.organizationId,
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
                            .foregroundStyle(.primary)
                        let studentCount = dataManager.students.filter { $0.programId == program.id }.count
                        Text("\(studentCount) \(isChinese ? "学员" : "students")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(.quaternary)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                
                // Select new coach
                Text(isChinese ? "选择新教练" : "Select New Coach")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                
                if availableCoaches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text(isChinese ? "没有其他可用教练" : "No other coaches available")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
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
                                                        .foregroundStyle(.primary)
                                                    Text("(\(coach.name))")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Text(coach.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(.primary)
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
                                                .foregroundColor(Color.accentColor)
                                        } else {
                                            Circle()
                                                .strokeBorder(AppTheme.textTertiary, lineWidth: 1.5)
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .padding(12)
                                    .background(selectedCoachId == coach.id ? Color.accentColor.opacity(0.1) : AppTheme.surfaceColor)
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isChinese ? "转移项目" : "Reassign Program")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "确认转移" : "Reassign") { reassignProgram() }
                        .fontWeight(.semibold)
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
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Basic Info
                    PanelSectionCard("Basic Info", icon: "building.2") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Stepper("\(courtCount)", value: $courtCount, in: 1...10)
                                    .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Type")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.tertiary)
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
                                        .foregroundColor(newAmenity.isEmpty ? AppTheme.textTertiary : Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(newAmenity.isEmpty)
                            }
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(8)
                        }
                    }
                    
                    if isEditing {
                        Button(role: .destructive, action: deleteLocation) {
                            Label("Delete Location", systemImage: "trash")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .controlSize(.regular)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEditing ? "Edit Location" : "Add Location")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLocation() }
                        .fontWeight(.semibold)
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
    @State private var selectedImage: UIImage?
    
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
            _selectedImage = State(initialValue: UIImage(data: data))
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
                                Image(uiImage: image)
                                    .resizable()
                                    .renderingMode(.original)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(systemName: previewMascotIcon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        Text(previewMascotName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(shortName.isEmpty ? "U?" : shortName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: colorHex))
                        Text("Ages \(minAge)-\(maxAge)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Basic Info
                    PanelSectionCard("Basic Info", icon: "rectangle.stack") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Stepper("\(minAge)", value: $minAge, in: 3...25)
                                    .labelsHidden()
                            }
                            Divider()
                            HStack {
                                Text("Max Age")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if let image = selectedImage {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: colorHex).opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(uiImage: image)
                                                .resizable()
                                                .renderingMode(.original)
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                        }
                                        
                                        Button(action: { 
                                            selectedImage = nil
                                            customIconData = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                } else {
                                    Button(action: { showingImagePicker = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "photo.badge.plus")
                                            Text("Upload")
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color.accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            
                            Text("Upload a custom icon image for this category. Use a simple outline icon for best results.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
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
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: $isActive)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    
                    // Delete Button
                    if isEditing {
                        Button(role: .destructive, action: deleteCategory) {
                            Label("Delete Category", systemImage: "trash")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .controlSize(.regular)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEditing ? "Edit Category" : "Add Category")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCategory() }
                        .fontWeight(.semibold)
                        .disabled(name.isEmpty || shortName.isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                CategoryIconImagePicker(selectedImage: $selectedImage, customIconData: $customIconData)
            }
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
                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(result.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
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
                .background(.regularMaterial)
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle(location.name)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "编辑" : "Edit") {
                        showingEditSheet = true
                    }
                    .fontWeight(.semibold)
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
                                .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(location.courtCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            Divider()
            
            HStack {
                Label(isChinese ? "类型" : "Type", systemImage: location.courtType.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(capacity)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var amenitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isChinese ? "设施" : "Amenities", systemImage: "checkmark.seal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            
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
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phone = location.contactPhone {
                HStack {
                    Label(isChinese ? "电话" : "Phone", systemImage: "phone")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(phone)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.accentColor)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
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
