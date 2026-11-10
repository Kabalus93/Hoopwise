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
    
    // MARK: - The page
    //
    // Redesigned November 2026 (Luther: "the weakest page of the app … it
    // feels like it's not from the app"). It was two cards of numbers, a
    // segmented control and a card list per tab. Now it reads like the rest
    // of the app: a large title, a strip of what the organization holds (tap
    // to jump), then native grouped sections — Coaches, Venues, Schools, Age
    // categories, Share & import — on one page with one search. Each row
    // opens the same editor or profile as before.

    @State private var searchText = ""
    @State private var showingAddCoach = false
    @State private var selectedCoach: StaffCoach?
    @State private var showingAddLocation = false
    @State private var selectedLocation: Location?
    @State private var showingAddSchool = false
    @State private var editingSchool: School?
    @State private var showingAddCategory = false
    @State private var selectedCategory: CustomAgeCategory?
    @State private var pageWidth: CGFloat = 0

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ fields: String?...) -> Bool {
        query.isEmpty || fields.contains { ($0 ?? "").localizedCaseInsensitiveContains(query) }
    }

    private var coaches: [StaffCoach] {
        dataManager.staffCoaches
            .filter { matches($0.name, $0.chineseName, $0.role.rawValue) }
            .sorted { a, b in
                // You first, then head coaches, then by name.
                let me = dataManager.loggedInCoachId
                if (a.id == me) != (b.id == me) { return a.id == me }
                if (a.role == .head) != (b.role == .head) { return a.role == .head }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private var venues: [Location] {
        dataManager.locations
            .filter { matches($0.name, $0.address, $0.city) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var schools: [School] {
        dataManager.schools
            .filter { matches($0.name, $0.chineseName, $0.contactName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var categories: [CustomAgeCategory] {
        dataManager.ageCategories
            .filter { matches($0.name, $0.shortName) }
            .sorted { $0.minAge < $1.minAge }
    }

    private enum Anchor: Hashable { case coaches, venues, schools, categories }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if query.isEmpty {
                    Section {
                        summaryStrip(proxy)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                coachesSection.id(Anchor.coaches)
                venuesSection.id(Anchor.venues)
                schoolsSection.id(Anchor.schools)
                categoriesSection.id(Anchor.categories)
                if query.isEmpty { shareSection }
                if !query.isEmpty && coaches.isEmpty && venues.isEmpty && schools.isEmpty && categories.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            // A readable column on a wide window, like a settings page.
            .contentMargins(.horizontal, max(20, (pageWidth - 860) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
        .navigationTitle(isChinese ? "组织" : "Organization")
        .navigationBarTitleDisplayModeCompat(.large)
        .searchable(text: $searchText, prompt: isChinese ? "搜索教练、场地、学校" : "Search coaches, venues, schools")
        .sheet(isPresented: $showingAddCoach) { AddEditCoachView(coach: nil) }
        .sheet(item: $selectedCoach) { CoachProfileDetailView(coach: $0) }
        .sheet(isPresented: $showingAddLocation) { AddEditLocationView(location: nil) }
        .sheet(item: $selectedLocation) { LocationDetailView(location: $0) }
        .sheet(isPresented: $showingAddSchool) { AddEditSchoolView(school: nil) }
        .sheet(item: $editingSchool) { AddEditSchoolView(school: $0) }
        .sheet(isPresented: $showingAddCategory) { AddEditCategoryView(category: nil) }
        .sheet(item: $selectedCategory) { AddEditCategoryView(category: $0) }
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

    // MARK: Summary

    /// What the organization holds, four tiles; a tap scrolls to the section.
    private func summaryStrip(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            summaryTile(dataManager.staffCoaches.count, isChinese ? "教练" : "Coaches", "person.2.fill", .accentColor) {
                withAnimation { proxy.scrollTo(Anchor.coaches, anchor: .top) }
            }
            summaryTile(dataManager.locations.count, isChinese ? "场地" : "Venues", "mappin.and.ellipse", .orange) {
                withAnimation { proxy.scrollTo(Anchor.venues, anchor: .top) }
            }
            summaryTile(dataManager.schools.count, isChinese ? "学校" : "Schools", "building.columns.fill", SessionFormat.school.tint) {
                withAnimation { proxy.scrollTo(Anchor.schools, anchor: .top) }
            }
            summaryTile(dataManager.ageCategories.count, isChinese ? "年龄组" : "Ages", "person.3.sequence.fill", .green) {
                withAnimation { proxy.scrollTo(Anchor.categories, anchor: .top) }
            }
        }
    }

    private func summaryTile(_ value: Int, _ label: String, _ icon: String, _ tint: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private func header(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)").foregroundStyle(.tertiary)
        }
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
                .font(.body.weight(.medium))
        }
    }

    @ViewBuilder
    private var coachesSection: some View {
        if query.isEmpty || !coaches.isEmpty {
            Section {
                ForEach(coaches) { coach in
                    Button { selectedCoach = coach } label: { OrgCoachRow(coach: coach) }
                        .buttonStyle(.plain)
                }
                if query.isEmpty { addRow(isChinese ? "添加教练" : "Add Coach") { showingAddCoach = true } }
            } header: {
                header(isChinese ? "教练" : "Coaches", coaches.count)
            }
        }
    }

    @ViewBuilder
    private var venuesSection: some View {
        if query.isEmpty || !venues.isEmpty {
            Section {
                ForEach(venues) { venue in
                    Button { selectedLocation = venue } label: { OrgVenueRow(location: venue) }
                        .buttonStyle(.plain)
                }
                if query.isEmpty { addRow(isChinese ? "添加场地" : "Add Venue") { showingAddLocation = true } }
            } header: {
                header(isChinese ? "场地" : "Venues", venues.count)
            }
        }
    }

    @ViewBuilder
    private var schoolsSection: some View {
        if query.isEmpty || !schools.isEmpty {
            Section {
                ForEach(schools) { school in
                    Button { editingSchool = school } label: { OrgSchoolRow(school: school) }
                        .buttonStyle(.plain)
                }
                if query.isEmpty { addRow(isChinese ? "添加学校" : "Add School") { showingAddSchool = true } }
            } header: {
                header(isChinese ? "学校" : "Schools", schools.count)
            } footer: {
                if query.isEmpty && schools.isEmpty {
                    Text(isChinese ? "合作学校用于校园合作项目。" : "Partner schools, for school-collaboration programs.")
                }
            }
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        if query.isEmpty || !categories.isEmpty {
            Section {
                ForEach(categories) { category in
                    Button { selectedCategory = category } label: { OrgCategoryRow(category: category) }
                        .buttonStyle(.plain)
                }
                if query.isEmpty { addRow(isChinese ? "添加年龄组" : "Add Age Category") { showingAddCategory = true } }
            } header: {
                header(isChinese ? "年龄组" : "Age categories", categories.count)
            }
        }
    }

    /// Sharing the organization's data with another coach, and taking
    /// theirs in — what leaves the device is said in the row and footer.
    private var shareSection: some View {
        let stats = HoopwiseBundleExporter(dataManager: dataManager).previewStats()
        let canShare = !isExporting && stats.studentCount > 0
        return Section {
            Button(action: startExport) {
                HStack(spacing: 12) {
                    OrgIconTile(icon: "square.and.arrow.up", tint: .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "共享组织数据…" : "Share organization data…")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(isChinese
                             ? "\(stats.studentCount) 名学员 · \(stats.drillCount) 个训练 · \(stats.coachCount) 名教练 · \(stats.locationCount) 个场地"
                             : "\(stats.studentCount) athletes · \(stats.drillCount) drills · \(stats.coachCount) coaches · \(stats.locationCount) venues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isExporting { ProgressView() }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canShare)
            .opacity(canShare || isExporting ? 1 : 0.5)

            Button { showingImportPicker = true } label: {
                HStack(spacing: 12) {
                    OrgIconTile(icon: "square.and.arrow.down", tint: .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "从文件导入…" : "Import from a file…")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(isChinese ? "导入前会先显示将要合并的内容" : "Shows what would change before anything is merged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isAnalyzingImport { ProgressView() }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isAnalyzingImport)
        } header: {
            Text(isChinese ? "共享与导入" : "Share & import")
        } footer: {
            if stats.excludedStudentCount > 0 {
                Label(excludedSubtitle(stats.excludedStudentCount), systemImage: "lock.shield.fill")
            }
        }
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
