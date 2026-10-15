import SwiftUI

struct StudentDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    @State private var showingEditSheet = false
    @State private var showingMeasurementSheet = false
    @State private var contractEdit: ContractEdit?

    // Section expansion states
    @State private var showParent = false
    @State private var showMeasurements = false

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    /// Wraps either an existing contract to edit, or `nil` for "create new".
    /// `Identifiable` so it drives a sheet(item:).
    struct ContractEdit: Identifiable {
        let id: UUID
        let contract: Contract?
    }

    var player: Player? {
        dataManager.player(for: student.id)
    }

    var contract: Contract? {
        dataManager.currentContract(for: student.id)
    }

    var allContracts: [Contract] {
        dataManager.contracts
            .filter { $0.studentId == student.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    var measurementSummary: MeasurementSummary {
        dataManager.measurementSummary(for: student.id)
    }
    
    var enrolledPrograms: [Program] {
        dataManager.programs.filter { $0.enrolledStudentIds.contains(student.id) }
    }
    
    var hasLeagueData: Bool {
        dataManager.teams.contains { $0.playerIds.contains(student.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Clean header
                cleanHeader
                
                // Quick stats row
                quickStatsRow
                    .padding(.top, 16)
                
                // Main content sections
                VStack(spacing: 12) {
                    // Contract & Risk Analysis section (comprehensive)
                    contractAndRiskSection
                    
                    // Measurements
                    measurementsSection
                    
                    // League Stats
                    CollapsibleLeagueSection(studentId: student.id)
                    
                    // Training Stats
                    CollapsibleTrainingStatsSection(studentId: student.id)
                    
                    // Notes
                    if let player = player, let notes = player.coachNotes, !notes.isEmpty {
                        notesSection(notes)
                    }
                    
                    // Parent/Guardian (moved to bottom)
                    if let player = player, !player.parentInfo.name.isEmpty {
                        parentSection(player)
                    }

                    // About this athlete — provenance footer (Phase 1 of export/import)
                    AboutAthleteCard(studentId: student.id)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                Spacer(minLength: 100)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(student.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isChinese ? "编辑" : "Edit") {
                    showingEditSheet = true
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditStudentView(student: student, player: player)
        }
        .sheet(isPresented: $showingMeasurementSheet) {
            QuickMeasurementView(student: student, sessionId: nil)
        }
        .sheet(item: $contractEdit) { edit in
            AddEditContractSheet(studentId: student.id, existing: edit.contract)
        }
    }
    
    // MARK: - Identity Card (the "collectible card")
    /// Rounded card pinned to the top: avatar, names, program schedule pills.
    /// Same shape regardless of how the profile was reached.
    private var cleanHeader: some View {
        VStack(spacing: 14) {
            StudentAvatarView(student: student, size: 96)
                .overlay(
                    Circle().strokeBorder(Color(.systemBackground), lineWidth: 4)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

            VStack(spacing: 2) {
                if isChinese, let chinese = student.chineseName {
                    Text(chinese)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text(student.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(student.name)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            FormatBadge(format: dataManager.studentFormat(student), size: .full)

            if !enrolledPrograms.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(enrolledPrograms.prefix(3)) { program in
                        programPill(program)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .padding(.horizontal, 16)
        .background(
            // Soft card-like backdrop with a subtle gradient — keeps the card
            // feel but stays inside the iOS 26 / Apple aesthetic.
            ZStack {
                Color(.secondarySystemGroupedBackground)
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Compact pill that summarises the student's spot in a program. Uses the
    /// AgeBadge instead of mascot icons (mascots were retired earlier).
    private func programPill(_ program: Program) -> some View {
        let scheduleText: String? = programScheduleText(for: program)
        return HStack(spacing: 6) {
            AgeBadge(shortName: program.ageGroup.rawValue, tint: .accentColor, size: .xsmall)
            if let scheduleText {
                Text(scheduleText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            if let location = program.locationName, !location.isEmpty {
                Text(location)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    /// "Sunday 9:30 AM" formatted from the program's recurring days + time.
    private func programScheduleText(for program: Program) -> String? {
        guard let firstDay = program.recurringDays.first else { return nil }
        let dayName = firstDay.displayName
        guard let time = program.defaultSessionTime else { return dayName }
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        return "\(dayName) \(f.string(from: time))"
    }

    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: 0) {
            quickStatItem(
                value: student.age != nil ? "\(student.age!)" : "—",
                label: isChinese ? "年龄" : "Age"
            )

            Divider().frame(height: 32)

            // Bundles get a real "Left" count; PAYG and group are open-ended.
            if let c = contract, c.kind == .privateBundle,
               let remaining = c.bundleRedemptionsRemaining {
                quickStatItem(
                    value: "\(remaining)",
                    label: isChinese ? "剩余" : "Left",
                    valueColor: remaining <= 3 ? .red : .primary
                )
            } else {
                quickStatItem(value: "∞", label: isChinese ? "剩余" : "Left")
            }

            Divider().frame(height: 32)

            let attendedCount = contract.map { dataManager.sessionsAttended(for: $0) } ?? 0
            quickStatItem(
                value: "\(attendedCount)",
                label: isChinese ? "已上" : "Done"
            )

            Divider().frame(height: 32)

            if let height = player?.heightCm {
                quickStatItem(value: "\(Int(height))", label: "cm")
            } else {
                quickStatItem(value: "—", label: isChinese ? "身高" : "Height")
            }
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func quickStatItem(value: String, label: String, valueColor: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Contracts Section
    private var contractAndRiskSection: some View {
        contractsCard
    }

    /// Lists all contracts for this student. Tap any row to edit; the
    /// "Add Contract" row at the bottom opens a fresh sheet.
    private var contractsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.green)
                    Text(isChinese ? "合同" : "Contracts")
                        .font(.headline)
                }
                Spacer()
                Button {
                    contractEdit = ContractEdit(id: UUID(), contract: nil)
                } label: {
                    Label(isChinese ? "添加" : "Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if allContracts.isEmpty {
                Button {
                    contractEdit = ContractEdit(id: UUID(), contract: nil)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(isChinese ? "添加第一份合同" : "Add the first contract")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(allContracts) { c in
                        Button {
                            contractEdit = ContractEdit(id: c.id, contract: c)
                        } label: {
                            contractRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !allContracts.isEmpty {
                NavigationLink(destination: AttendedSessionsListView(studentId: student.id)) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle").font(.caption)
                        Text(isChinese ? "查看出勤记录" : "View attendance history")
                            .font(.footnote.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func contractRow(_ c: Contract) -> some View {
        HStack(spacing: 12) {
            Image(systemName: c.kind.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? c.kind.displayNameChinese : c.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(contractMetric(c))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    /// One-line headline for a contract row, varying by kind.
    private func contractMetric(_ c: Contract) -> String {
        let symbol = dataManager.appSettings.currency.symbol
        switch c.kind {
        case .privatePayPerSession:
            let attended = dataManager.sessionsAttended(for: c)
            return isChinese
                ? "\(symbol)\(Int(c.pricePerSession))/课 · 已出席 \(attended)"
                : "\(symbol)\(Int(c.pricePerSession))/session · \(attended) attended"
        case .privateBundle:
            let used = c.bundleSessionIds.count
            let total = c.bundleSize
            return isChinese
                ? "\(used)/\(total) 已用 · \(symbol)\(Int(c.bundleAmount)) 套餐"
                : "\(used)/\(total) used · \(symbol)\(Int(c.bundleAmount)) bundle"
        case .group:
            let classes = dataManager.programs
                .filter { $0.enrolledStudentIds.contains(c.studentId)
                    && $0.programType != .privateSessions && $0.status != .archived }
                .map { $0.resolvedDisplayName(in: dataManager.programs) }
                .sorted()
                .joined(separator: isChinese ? "、" : ", ")
            let where_ = classes.isEmpty ? (isChinese ? "未加入班级" : "No class") : classes
            if let left = c.bundleRedemptionsRemaining {
                return isChinese ? "剩余 \(left) 课时 · \(where_)" : "\(left) sessions left · \(where_)"
            }
            return where_
        }
    }
    
    // MARK: - Contract Section (Simplified - Legacy)

    // MARK: - Parent Section
    private func parentSection(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(isChinese ? "家长/监护人" : "Parent/Guardian")
                    .font(.footnote.weight(.semibold))
            } icon: {
                Image(systemName: "person.2.fill").font(.caption)
            }
            .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(player.parentInfo.name.prefix(1)).uppercased())
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.parentInfo.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(player.parentInfo.relationship)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !player.parentInfo.phone.isEmpty {
                    Link(destination: URL(string: "tel:\(player.parentInfo.phone)")!) {
                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding(10)
                            .background(Color.green.opacity(0.12), in: Circle())
                    }
                }

                if let wechat = player.parentInfo.wechatId, !wechat.isEmpty {
                    Image(systemName: "message.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .padding(10)
                        .background(Color.green.opacity(0.12), in: Circle())
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Measurements Section
    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(isChinese ? "测量数据" : "Measurements")
                        .font(.footnote.weight(.semibold))
                } icon: {
                    Image(systemName: "ruler.fill").font(.caption)
                }
                .foregroundStyle(.primary)
                Spacer()
                Button {
                    showingMeasurementSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(Color.accentColor)
            }

            if measurementSummary.measurements.isEmpty {
                Button(action: { showingMeasurementSheet = true }) {
                    HStack {
                        Text(isChinese ? "点击记录身高、体重等" : "Tap to record height, weight...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                // Compact measurement grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(measurementSummary.measurements.prefix(6)) { measurement in
                        VStack(spacing: 2) {
                            Text(measurement.formattedValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(measurement.type.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .cornerRadius(14)
    }
    
    // MARK: - Notes Section
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(isChinese ? "教练备注" : "Coach Notes")
                    .font(.footnote.weight(.semibold))
            } icon: {
                Image(systemName: "note.text").font(.caption)
            }
            .foregroundStyle(.primary)

            Text(notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

}

// MARK: - About this athlete (reusable provenance footer)
//
// Drop into any student profile view that wants the "Created by / Last edited by /
// Imported from / Version History" footer. Self-contained: owns its own state,
// reads provenance straight from DataManager on every render so it stays in
// sync after edits in any sheet without callbacks.

struct AboutAthleteCard: View {
    let studentId: UUID
    @EnvironmentObject var dataManager: DataManager
    @State private var showingVersionHistory = false

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var provenance: StudentProvenance? {
        dataManager.studentProvenance(for: studentId)
    }

    private var revisionCount: Int {
        dataManager.studentRevisionSummaries(for: studentId).count
    }

    private var isExcludedFromExport: Bool {
        dataManager.isExcludedFromExport(studentId: studentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(isChinese ? "关于此学员" : "About this athlete")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if isExcludedFromExport {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isChinese ? "私密 · 不共享" : "Private · won't share")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12), in: .capsule)
                }
            }
            .padding(.bottom, 10)

            // Created
            provenanceRow(
                iconName: "person.crop.circle.badge.plus",
                iconColor: .blue,
                label: isChinese ? "创建者" : "Created by",
                primary: provenance?.createdByCoachName ?? (isChinese ? "未知" : "Unknown"),
                secondary: provenanceRelativeAndAbsolute(provenance?.createdAt)
            )

            cardDivider

            // Last edited
            provenanceRow(
                iconName: "pencil.circle.fill",
                iconColor: .orange,
                label: isChinese ? "最后修改" : "Last edited by",
                primary: provenance?.lastModifiedByCoachName
                    ?? provenance?.createdByCoachName
                    ?? (isChinese ? "—" : "—"),
                secondary: provenanceRelativeAndAbsolute(provenance?.lastModifiedAt ?? provenance?.createdAt)
            )

            // Imported (only if originBundleId non-nil)
            if provenance?.originBundleId != nil {
                cardDivider
                provenanceRow(
                    iconName: "square.and.arrow.down.fill",
                    iconColor: .purple,
                    label: isChinese ? "导入自" : "Imported from",
                    primary: provenance?.createdByCoachName ?? (isChinese ? "未知" : "Unknown"),
                    secondary: provenanceRelativeAndAbsolute(provenance?.createdAt)
                )
            }

            cardDivider

            // Version History disclosure
            Button(action: { showingVersionHistory = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.accentColor)
                        .frame(width: 22)
                    Text(isChinese ? "版本历史" : "Version History")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    if revisionCount > 0 {
                        Text("\(revisionCount)")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary.opacity(0.6))
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(revisionCount == 0)
            .opacity(revisionCount == 0 ? 0.5 : 1.0)
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .sheet(isPresented: $showingVersionHistory) {
            StudentVersionHistorySheet(studentId: studentId)
                .environmentObject(dataManager)
        }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(AppTheme.textSecondary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private func provenanceRow(
        iconName: String,
        iconColor: Color,
        label: String,
        primary: String,
        secondary: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(primary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    if let secondary = secondary, !secondary.isEmpty {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        Text(secondary)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    /// Relative for under a week, absolute for older. Returns nil for nil dates.
    private func provenanceRelativeAndAbsolute(_ date: Date?) -> String? {
        guard let date else { return nil }
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 7 * 24 * 60 * 60 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = isChinese ? Locale(identifier: "zh_CN") : Locale.current
        return formatter.string(from: date)
    }
}

// MARK: - Helper Views
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        StudentDetailView(student: Student.samples[0])
            .environmentObject(DataManager.shared)
    }
}

// MARK: - Version History sheet

struct StudentVersionHistorySheet: View {
    let studentId: UUID
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var revisions: [EntityRevisionSummary] = []
    @State private var pendingRestore: EntityRevisionSummary?

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    var body: some View {
        NavigationStack {
            Group {
                if revisions.isEmpty {
                    ContentUnavailableViewCompat(
                        title: isChinese ? "暂无历史" : "No history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: isChinese
                            ? "每次编辑此学员后，将在此处保留可恢复的备份。"
                            : "Each edit to this athlete keeps a restorable backup here."
                    )
                } else {
                    List {
                        Section {
                            ForEach(revisions) { rev in
                                revisionRow(rev)
                            }
                        } footer: {
                            Text(isChinese
                                 ? "保留最近 10 个版本。导入产生的版本将额外保留 30 天。"
                                 : "The last 10 versions are kept. Versions from imports are kept for an extra 30 days.")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle(isChinese ? "版本历史" : "Version History")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: refresh)
        .alert(
            isChinese ? "恢复此版本？" : "Restore this version?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )
        ) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {
                pendingRestore = nil
            }
            Button(isChinese ? "恢复" : "Restore", role: .destructive) {
                if let rev = pendingRestore {
                    _ = dataManager.restoreStudent(toRevisionId: rev.id)
                    pendingRestore = nil
                    refresh()
                }
            }
        } message: {
            if let rev = pendingRestore {
                Text(restoreMessage(for: rev))
            }
        }
    }

    private func refresh() {
        revisions = dataManager.studentRevisionSummaries(for: studentId)
    }

    @ViewBuilder
    private func revisionRow(_ rev: EntityRevisionSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reasonTitle(rev))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                if let actor = rev.actorLabel, !actor.isEmpty {
                    Text(isChinese ? "由 \(actor)" : "by \(actor)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Text(absoluteDateString(rev.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
            Button(isChinese ? "恢复" : "Restore") {
                pendingRestore = rev
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppTheme.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func reasonTitle(_ rev: EntityRevisionSummary) -> String {
        switch rev.reason {
        case .manualEdit: return isChinese ? "手动编辑前" : "Before manual edit"
        case .beforeImport: return isChinese ? "导入前" : "Before import"
        case .beforeRestore: return isChinese ? "恢复前" : "Before restore"
        }
    }

    private func absoluteDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = isChinese ? Locale(identifier: "zh_CN") : Locale.current
        return formatter.string(from: date)
    }

    private func restoreMessage(for rev: EntityRevisionSummary) -> String {
        let when = absoluteDateString(rev.createdAt)
        if isChinese {
            return "学员的当前数据将被替换为 \(when) 的版本。当前状态将保存为新的可恢复版本，所以这次恢复也是可撤销的。"
        }
        return "The athlete's current data will be replaced with the version from \(when). The current state will be saved as a new restorable version, so this restore is also undoable."
    }
}

/// Tiny shim so we don't depend on iOS 17 ContentUnavailableView from older deploy targets.
private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(AppTheme.textSecondary.opacity(0.6))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
