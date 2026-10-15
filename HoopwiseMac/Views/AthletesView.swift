import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Athletes
/// Mac-native roster screen. Sidebar = filter/sort/search + grouped athlete list.
/// Detail pane = profile hero + stats + tabbed content (Overview / Performance /
/// Contracts / Notes / History). All mutations route through
/// `dataManager.updateStudent` / `updateContract`.
struct AthletesView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var search: String = ""
    @State private var selected: Student.ID?
    @State private var filter: AthleteFilter = .all
    @State private var sort: AthleteSort = .name
    @State private var groupByGrade = false
    @State private var showingNew = false

    enum AthleteFilter: String, CaseIterable, Identifiable {
        case all, active, bundleLow, inactive
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .bundleLow: return "Bundle Low"
            case .inactive: return "Inactive"
            }
        }
        var systemImage: String {
            switch self {
            case .all: return "person.2"
            case .active: return "person.crop.circle.badge.checkmark"
            case .bundleLow: return "exclamationmark.triangle.fill"
            case .inactive: return "person.crop.circle.badge.minus"
            }
        }
    }

    enum AthleteSort: String, CaseIterable, Identifiable {
        case name, recent, schoolGrade, attendance
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .recent: return "Recent"
            case .schoolGrade: return "School Grade"
            case .attendance: return "Attendance"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 320, idealWidth: 360)
        } detail: {
            if let id = selected, let student = dataManager.students.first(where: { $0.id == id }) {
                AthleteDetailView(student: student).id(student.id)
            } else {
                EmptyDetail(systemImage: "person.2", title: "Select an Athlete")
            }
        }
        .onAppear { autoSelectIfNeeded() }
        .onChange(of: filter) { _, _ in autoSelectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .macNewAthlete)) { _ in
            showingNew = true
        }
        .sheet(isPresented: $showingNew) {
            NewAthleteSheet()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Picker("Filter", selection: $filter) {
                ForEach(AthleteFilter.allCases) { f in
                    Label(f.label, systemImage: f.systemImage).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Picker("Sort", selection: $sort) {
                    ForEach(AthleteSort.allCases) { s in Text(s.label).tag(s) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                Toggle(isOn: $groupByGrade) {
                    Label("Group", systemImage: "rectangle.3.group")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Group by performance grade")

                Spacer()
                Text("\(filtered.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            athletesList
        }
        .navigationTitle("Athletes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Add Athlete", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by name", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.quinary, in: .rect(cornerRadius: 6))
    }

    @ViewBuilder
    private var athletesList: some View {
        List(selection: $selected) {
            if filtered.isEmpty {
                Text("No athletes match.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if groupByGrade {
                ForEach(grouped, id: \.grade) { group in
                    Section {
                        ForEach(group.students) { student in
                            AthleteRow(student: student, contract: dataManager.currentContract(for: student.id))
                                .tag(student.id)
                                .contextMenu { rowContextMenu(student) }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text("Grade \(group.grade.rawValue)")
                                .font(.caption.weight(.semibold))
                            Text("\(group.students.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ForEach(filtered) { student in
                    AthleteRow(student: student, contract: dataManager.currentContract(for: student.id))
                        .tag(student.id)
                        .contextMenu { rowContextMenu(student) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowContextMenu(_ student: Student) -> some View {
        Button("Open", systemImage: "arrow.up.right.square") { selected = student.id }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            dataManager.deleteStudent(student)
            if selected == student.id { selected = nil }
        }
    }

    // MARK: - Computed

    private struct GradeGroup {
        let grade: PerformanceGrade
        let students: [Student]
    }

    private var filtered: [Student] {
        let base: [Student]
        switch filter {
        case .all:
            base = dataManager.students
        case .active:
            base = dataManager.students.filter { dataManager.currentContract(for: $0.id)?.status == .active }
        case .bundleLow:
            base = dataManager.students.filter { student in
                guard let c = dataManager.currentContract(for: student.id), c.kind == .privateBundle else { return false }
                return (c.bundleRedemptionsRemaining ?? .max) <= 3
            }
        case .inactive:
            base = dataManager.students.filter {
                let status = dataManager.currentContract(for: $0.id)?.status
                return status == nil || status == .expired || status == .cancelled || status == .completed
            }
        }
        let searched = search.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            ($0.chineseName ?? "").localizedCaseInsensitiveContains(search)
        }
        return searched.sorted { lhs, rhs in
            switch sort {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .recent:
                return lhs.createdAt > rhs.createdAt
            case .schoolGrade:
                let l = lhs.schoolGrade?.rawValue ?? ""
                let r = rhs.schoolGrade?.rawValue ?? ""
                return l < r
            case .attendance:
                let la = sessionsAttended(lhs.id)
                let ra = sessionsAttended(rhs.id)
                return la > ra
            }
        }
    }

    private var grouped: [GradeGroup] {
        let buckets = Dictionary(grouping: filtered) { effectiveGrade(for: $0) }
        return PerformanceGrade.allCases.compactMap { grade in
            guard let students = buckets[grade], !students.isEmpty else { return nil }
            return GradeGroup(grade: grade, students: students)
        }
    }

    private func sessionsAttended(_ id: UUID) -> Int {
        dataManager.sessionEvents.filter { $0.actualAttendeeIds.contains(id) }.count
    }

    private func effectiveGrade(for student: Student) -> PerformanceGrade {
        if let g = student.performanceGrade { return g }
        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: dataManager.students,
            sessions: dataManager.sessionEvents,
            skills: skills
        )
    }

    private func autoSelectIfNeeded() {
        if let current = selected, dataManager.students.contains(where: { $0.id == current }) { return }
        selected = filtered.first?.id
    }
}

// MARK: - Sidebar Row

private struct AthleteRow: View {
    let student: Student
    let contract: Contract?

    var body: some View {
        HStack(spacing: 10) {
            AthleteAvatar(student: student, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(student.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                    if let cn = student.chineseName, !cn.isEmpty, cn != student.displayName {
                        Text(cn).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    if let grade = student.schoolGrade {
                        Text(grade.shortName)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    if let contract {
                        bundleHint(contract)
                    }
                }
            }
            Spacer(minLength: 0)
            if let g = student.performanceGrade {
                gradePill(g)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func bundleHint(_ contract: Contract) -> some View {
        if contract.kind == .privateBundle, let remaining = contract.bundleRedemptionsRemaining {
            Text("\(remaining) left")
                .font(.caption2.weight(.medium))
                .foregroundStyle(remaining <= 3 ? .orange : .secondary)
        } else if contract.status != .active {
            Text(contract.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func gradePill(_ g: PerformanceGrade) -> some View {
        Text(g.rawValue)
            .font(.caption2.weight(.bold))
            .frame(width: 22, height: 22)
            .background(gradeTint(g).opacity(0.18), in: Circle())
            .foregroundStyle(gradeTint(g))
    }
}

// MARK: - Athlete Detail

struct AthleteDetailView: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager
    @State private var tab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview, performance, contracts, notes, history
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .performance: return "Performance"
            case .contracts: return "Contracts"
            case .notes: return "Notes"
            case .history: return "History"
            }
        }
        var systemImage: String {
            switch self {
            case .overview: return "person.crop.rectangle"
            case .performance: return "chart.bar.fill"
            case .contracts: return "doc.text.fill"
            case .notes: return "note.text"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                statRow

                Picker("Section", selection: $tab) {
                    ForEach(DetailTab.allCases) { t in
                        Label(t.label, systemImage: t.systemImage).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    switch tab {
                    case .overview:    OverviewTab(student: student)
                    case .performance: AthletePerformanceTab(student: student)
                    case .contracts:   AthleteContractsTab(student: student)
                    case .notes:       AthleteNotesTab(student: student)
                    case .history:     AthleteHistoryTab(student: student)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(student.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    dataManager.deleteStudent(student)
                } label: {
                    Label("Delete Athlete", systemImage: "trash")
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            EditAvatarButton(
                currentData: student.profileImageData,
                initials: student.initials,
                avatarColor: student.avatarColor,
                size: 88,
                onPicked: { data in
                    var copy = student
                    copy.profileImageData = data
                    copy.thumbnailImageData = data
                    copy.updatedAt = Date()
                    dataManager.updateStudent(copy)
                },
                onCleared: {
                    var copy = student
                    copy.profileImageData = nil
                    copy.thumbnailImageData = nil
                    copy.updatedAt = Date()
                    dataManager.updateStudent(copy)
                }
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(student.displayName).font(.system(size: 30, weight: .bold))
                    if let cn = student.chineseName, !cn.isEmpty, cn != student.displayName {
                        Text(cn).font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    gradeBadge
                }
                HStack(spacing: 12) {
                    if let grade = student.schoolGrade {
                        Label(grade.displayName, systemImage: "graduationcap").labelStyle(.titleAndIcon)
                    }
                    if let age = student.age {
                        Label("\(age) years", systemImage: "calendar").labelStyle(.titleAndIcon)
                    }
                    if let pid = student.programId,
                       let program = dataManager.programs.first(where: { $0.id == pid }) {
                        Label(program.name, systemImage: "list.clipboard").labelStyle(.titleAndIcon)
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var gradeBadge: some View {
        let grade = effectiveGrade
        return VStack(spacing: 0) {
            Text(grade.rawValue)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(gradeTint(grade))
            Text("Performance")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(gradeTint(grade).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(gradeTint(grade).opacity(0.3), lineWidth: 1))
    }

    private var statRow: some View {
        let attended = dataManager.sessionEvents.filter { $0.actualAttendeeIds.contains(student.id) }.count
        let expected = dataManager.sessionEvents.filter { $0.attendeeIds.contains(student.id) || ($0.programId == student.programId && student.programId != nil) }.count
        let pct = expected > 0 ? Int((Double(attended) / Double(expected)) * 100) : 0
        let contract = dataManager.currentContract(for: student.id)
        let bundle: String = {
            guard let c = contract else { return "—" }
            switch c.kind {
            case .privateBundle: return "\(c.bundleRedemptionsRemaining ?? 0) left"
            case .privatePayPerSession: return "PAYG"
            case .group: return "Group"
            }
        }()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatPill(title: "Attended", value: "\(attended)")
            StatPill(title: "Attendance", value: expected > 0 ? "\(pct)%" : "—")
            StatPill(title: "Bundle", value: bundle)
            StatPill(title: "Status", value: contract?.status.rawValue ?? "No Contract")
        }
    }

    private var effectiveGrade: PerformanceGrade {
        if let g = student.performanceGrade { return g }
        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: dataManager.students,
            sessions: dataManager.sessionEvents,
            skills: skills
        )
    }
}

// MARK: - Avatar

private struct AthleteAvatar: View {
    let student: Student
    let size: CGFloat

    var body: some View {
        AthletePhoto(imageData: student.profileImageData,
                     initials: student.initials,
                     color: Color.avatarColor(student.avatarColor),
                     size: size)
    }
}

// MARK: - Overview tab

private struct OverviewTab: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager

    private var program: Program? {
        guard let pid = student.programId else { return nil }
        return dataManager.programs.first(where: { $0.id == pid })
    }

    private var recentSessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { $0.attendeeIds.contains(student.id) || ($0.programId != nil && $0.programId == student.programId) }
            .sorted { $0.date > $1.date }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionBlock(title: "Program") {
                if let program {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "list.clipboard.fill").foregroundStyle(Color.accentColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name).font(.subheadline.weight(.semibold))
                            Text("\(program.enrolledStudentIds.count) athletes")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(program.status.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    EmptyPanel(systemImage: "list.clipboard", text: "Not enrolled in a program.")
                }
            }

            SectionBlock(title: "Personal Bests") {
                if student.personalBests.isEmpty {
                    EmptyPanel(systemImage: "trophy", text: "No personal bests recorded yet.")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(Array(student.personalBests.keys.sorted()), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatValue(student.personalBests[key] ?? 0))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                Text(key).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            SectionBlock(title: "Recent Sessions") {
                if recentSessions.isEmpty {
                    EmptyPanel(systemImage: "calendar", text: "No sessions yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(recentSessions) { session in
                            recentSessionRow(session)
                        }
                    }
                }
            }
        }
    }

    private func recentSessionRow(_ session: SessionEvent) -> some View {
        let attended = session.actualAttendeeIds.contains(student.id)
        return HStack(spacing: 10) {
            Image(systemName: attended ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(attended ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(session.date, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let loc = session.location, !loc.isEmpty {
                Text(loc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formatValue(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Performance tab

struct AthletePerformanceTab: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager
    @State private var override: PerformanceGrade?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionBlock(title: "Performance Grade") {
                HStack(spacing: 14) {
                    let computed = computedGrade
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-computed")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(computed.rawValue)
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(gradeTint(computed))
                            Text(computed.chineseName).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Override")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { student.performanceGrade },
                            set: { newValue in saveOverride(newValue) }
                        )) {
                            Text("Use computed").tag(PerformanceGrade?.none)
                            ForEach(PerformanceGrade.allCases, id: \.self) { g in
                                Text(g.rawValue).tag(Optional(g))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            SectionBlock(title: "Grade History") {
                if student.gradeHistory.isEmpty {
                    EmptyPanel(systemImage: "clock", text: "No grade changes recorded.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(student.gradeHistory.sorted(by: { $0.date > $1.date }), id: \.id) { entry in
                            HStack(spacing: 10) {
                                Text(entry.grade.rawValue)
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 30, height: 30)
                                    .background(gradeTint(entry.grade).opacity(0.18), in: Circle())
                                    .foregroundStyle(gradeTint(entry.grade))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.date, format: .dateTime.month().day().year())
                                        .font(.caption.weight(.semibold))
                                    Text(entry.wasManual ? "Coach override" : "Auto-computed")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var computedGrade: PerformanceGrade {
        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: dataManager.students,
            sessions: dataManager.sessionEvents,
            skills: skills
        )
    }

    private func saveOverride(_ grade: PerformanceGrade?) {
        var copy = student
        copy.performanceGrade = grade
        copy.updatedAt = Date()
        dataManager.updateStudent(copy)
    }
}

// MARK: - Contracts tab

struct AthleteContractsTab: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager

    private var contracts: [Contract] {
        dataManager.cachedContracts
            .filter { $0.studentId == student.id }
            .sorted { $0.enrollmentDate > $1.enrollmentDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if contracts.isEmpty {
                EmptyPanel(systemImage: "doc.text", text: "No contracts on file.")
            } else {
                ForEach(contracts) { contract in
                    ContractCard(contract: contract,
                                 currencyCode: dataManager.appSettings.currency.currencyCode,
                                 studentId: student.id)
                }
            }
        }
    }
}

struct ContractCard: View {
    let contract: Contract
    /// Passed in rather than read from the environment: this is a private
    /// leaf view with no dataManager, and the figures must match the coach's
    /// configured currency rather than a hardcoded USD.
    let currencyCode: String
    let studentId: UUID
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.undoManager) private var undoManager
    @State private var showingEdit = false
    @State private var confirmingRenew = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Contract #\(contract.contractNumber)").font(.subheadline.weight(.semibold))
                kindBadge
                Spacer()
                consentBadge
                statusBadge
                documentMenu
            }
            HStack(spacing: 18) {
                metric("Enrolled", contract.enrollmentDate.formatted(.dateTime.month().day().year()))
                metric("Per session", contract.pricePerSession.formatted(.currency(code: currencyCode)))
                if contract.kind == .privateBundle {
                    metric("Bundle", "\(contract.bundleSize) sessions")
                    metric("Remaining", "\(contract.bundleRedemptionsRemaining ?? 0)")
                }
            }
            .font(.caption)

            // Session money. Travel is shown on its own row below because it
            // is deliberately excluded from paid/owed.
            if contract.kind != .group {
                HStack(spacing: 18) {
                    metric("Paid", contract.amountPaid.formatted(.currency(code: currencyCode)))
                    metric("Owed", contract.sessionAmountOwed.formatted(.currency(code: currencyCode)))
                        .foregroundStyle(contract.sessionAmountOwed > 0 ? .orange : .green)
                    if contract.hasTravelFee {
                        metric("Travel", travelLabel)
                    }
                }
                .font(.caption)
            }

            handoverRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }

    /// Signed / jersey / ball. iOS has offered these three toggles all along
    /// while their setters discarded the write; now that they persist, the Mac
    /// gets them too — rule 6, fix it on both or remove it. Each writes one
    /// contract and registers one undo step.
    private var handoverRow: some View {
        HStack(spacing: 16) {
            handoverToggle("Signed", isOn: contract.isSigned, on: contract.signedDate) {
                var updated = contract
                updated.isSigned = $0
                return updated
            }
            handoverToggle("Jersey", isOn: contract.jerseyGiven, on: contract.jerseyGivenDate) {
                var updated = contract
                updated.jerseyGiven = $0
                return updated
            }
            handoverToggle("Ball", isOn: contract.ballGiven, on: contract.ballGivenDate) {
                var updated = contract
                updated.ballGiven = $0
                return updated
            }
            Spacer()
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private func handoverToggle(_ label: String,
                                isOn: Bool,
                                on date: Date?,
                                apply: @escaping (Bool) -> Contract) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                let old = contract
                dataManager.updateContract(apply(newValue))
                undoManager?.registerUndo(withTarget: dataManager) { manager in
                    manager.updateContract(old)
                }
                undoManager?.setActionName("\(label) — contract #\(contract.contractNumber)")
            })) {
                // The date is the record; the tick derives from it, so the
                // day it happened is visible rather than merely stored.
                Text(date.map { "\(label) · \($0.formatted(.dateTime.month().day()))" } ?? label)
            }
            .help(date.map { "Recorded \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Not recorded")
    }

    /// Per-contract fees show the flat figure; per-session fees show the rate
    /// and, for bundles, what it totals across the bundle.
    private var travelLabel: String {
        let amount = contract.travelFeeAmount.formatted(.currency(code: currencyCode))
        switch contract.travelFeeBasis {
        case .perContract:
            return amount
        case .perSession:
            guard contract.kind == .privateBundle, contract.bundleSize > 0 else {
                return "\(amount)/session"
            }
            let total = contract.travelFeeTotalForContract.formatted(.currency(code: currencyCode))
            return "\(amount)/session · \(total)"
        }
    }

    /// Statement and agreement export. Save writes a file the coach keeps;
    /// Share hands it to Mail/AirDrop/Messages.
    private var documentMenu: some View {
        Menu {
            Button("Edit Contract…") { showingEdit = true }
            Button("Renew — new contract…") { confirmingRenew = true }
            Divider()
            Button("Attendance Statement…") { save(.statement) }
            Divider()
            Button("Agreement — from contract…") { save(.agreementFromContract) }
            Button("Agreement — blank for signing…") { save(.agreementBlank) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Edit, renew, or export documents for this contract")
        .sheet(isPresented: $showingEdit) {
            ContractEditSheet(contract: contract)
                .dismissesOnPresentationEscape { showingEdit = false }
        }
        .confirmationDialog("Renew contract #\(contract.contractNumber)?",
                            isPresented: $confirmingRenew) {
            Button("Create Renewal") { renew() }
        } message: {
            Text("Creates a new active contract for this athlete with the same kind, price and bundle size — the structure iOS uses for renewals. The current contract is untouched.")
        }
    }

    /// Renewal = a NEW contract record linked to the athlete, next number in
    /// line, same commercial terms, starting now. The old record is left
    /// exactly as it stands — history is the ledger.
    private func renew() {
        let nextNumber = (dataManager.cachedContracts
            .filter { $0.studentId == studentId }
            .map(\.contractNumber).max() ?? 0) + 1
        var renewal = Contract(id: UUID(),
                               studentId: studentId,
                               contractNumber: nextNumber,
                               kind: contract.kind,
                               enrollmentDate: Date(),
                               pricePerSession: contract.pricePerSession,
                               bundleSize: contract.bundleSize)
        renewal.programId = contract.programId
        renewal.travelFeeAmount = contract.travelFeeAmount
        renewal.travelFeeBasis = contract.travelFeeBasis
        renewal.notes = "Renewal of contract #\(contract.contractNumber)"
        dataManager.addContract(renewal)
    }

    /// Guardian consent, surfaced where the contract is read so a declined
    /// publication consent is visible before any clip is used.
    @ViewBuilder
    private var consentBadge: some View {
        if contract.consentState(for: .publicPublication) == false {
            Label("No publish consent", systemImage: "eye.slash.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.15), in: .capsule)
                .foregroundStyle(.red)
                .help("The guardian declined consent for public publication.")
        }
    }

    private enum DocumentKind { case statement, agreementFromContract, agreementBlank }

    private func save(_ kind: DocumentKind) {
        do {
            let url: URL
            let suggested: String
            switch kind {
            case .statement:
                guard let input = AttendanceStatementDocument.makeInput(
                    studentId: studentId, contract: contract, dataManager: dataManager) else { return }
                suggested = AttendanceStatementDocument.filename(for: input) + ".pdf"
                url = try AttendanceStatementDocument.render(input)
            case .agreementFromContract, .agreementBlank:
                var fields = TrainingAgreementDocument.makeFields(
                    studentId: studentId, contract: contract, dataManager: dataManager)
                if kind == .agreementBlank {
                    // Never hand someone a pre-ticked consent form.
                    fields.consentCoachingAnalysis = nil
                    fields.consentPublicPublication = nil
                }
                suggested = TrainingAgreementDocument.filename(
                    for: fields, contractNumber: contract.contractNumber) + ".pdf"
                url = try TrainingAgreementDocument.render(
                    fields, contractNumber: contract.contractNumber)
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggested
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            debugLog("❌ Mac document export failed: \(error)")
        }
    }

    private var kindBadge: some View {
        Text(contract.kind.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
            .foregroundStyle(.secondary)
    }

    private var statusBadge: some View {
        Text(contract.status.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusTint.opacity(0.18), in: .capsule)
            .foregroundStyle(statusTint)
    }

    private var statusTint: Color {
        switch contract.status {
        case .active: return .green
        case .pending: return .orange
        case .completed: return .blue
        case .expired: return .red
        case .cancelled: return .gray
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
        }
    }
}

// MARK: - Notes tab

struct AthleteNotesTab: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager
    @State private var newNote: String = ""

    private var touchpoints: [ParentalTouchpoint] {
        student.parentalTouchpoints.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionBlock(title: "Add Touchpoint") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $newNote)
                        .font(.subheadline)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
                    HStack {
                        Spacer()
                        Button("Save Note") { saveNote() }
                            .buttonStyle(.borderedProminent)
                            .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            SectionBlock(title: "Parental Touchpoints") {
                if touchpoints.isEmpty {
                    EmptyPanel(systemImage: "note.text", text: "No notes yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(touchpoints) { tp in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: tp.type.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(tp.type.rawValue.capitalized).font(.caption.weight(.semibold))
                                        Text("·").foregroundStyle(.tertiary)
                                        Text(tp.date, format: .dateTime.month().day().year())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let notes = tp.notes, !notes.isEmpty {
                                        Text(notes).font(.subheadline)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func saveNote() {
        let trimmed = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = student
        let tp = ParentalTouchpoint(id: UUID(), date: Date(), type: .message, notes: trimmed, followUpNeeded: false, followUpDate: nil)
        copy.parentalTouchpoints.append(tp)
        copy.lastParentContact = Date()
        copy.updatedAt = Date()
        dataManager.updateStudent(copy)
        newNote = ""
    }
}

// MARK: - History tab

struct AthleteHistoryTab: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager

    private var allSessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter {
                $0.attendeeIds.contains(student.id) ||
                $0.actualAttendeeIds.contains(student.id) ||
                ($0.programId != nil && $0.programId == student.programId)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allSessions.isEmpty {
                EmptyPanel(systemImage: "clock", text: "No session history.")
            } else {
                ForEach(allSessions) { session in
                    let attended = session.actualAttendeeIds.contains(student.id)
                    let excused = session.excusedAbsences.contains(student.id)
                    HStack(spacing: 10) {
                        Image(systemName: attended ? "checkmark.circle.fill" : (excused ? "minus.circle.fill" : "xmark.circle"))
                            .foregroundStyle(attended ? .green : (excused ? .orange : .secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(session.date, format: .dateTime.weekday().month().day().year().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.status.rawValue.capitalized)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Shared atoms

struct StatPill: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

struct EmptyDetail: View {
    let systemImage: String
    let title: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 42, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// File-private grade tint helper used by both list rows and detail.
fileprivate func gradeTint(_ g: PerformanceGrade) -> Color {
    switch g {
    case .A: return .green
    case .B: return .blue
    case .C: return .orange
    case .ungraded: return .gray
    }
}


// MARK: - Contract editing (smallest surface, strictest validation)

/// The most sensitive record in the app. Small transaction per Done, one
/// undo step, and every mutation appends a minimal old→new line to the
/// contract's existing notes field — the history mechanism available
/// without inventing schema.
struct ContractEditSheet: View {
    let contract: Contract
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var manualStatus: ContractStatus?
    @State private var enrollmentDate = Date()
    @State private var bundleSize = 10
    @State private var pricePerSession = 0.0
    @State private var payments: [ContractPayment] = []
    @State private var newPaymentAmount = ""
    @State private var newPaymentDate = Date()
    @State private var loaded = false

    private var consumed: Int { contract.bundleSessionIds.count }
    private var draftPaid: Double { payments.reduce(0) { $0 + $1.amount } }
    /// Bundle owed derives: total (price × size) − paid. PAYG owed depends
    /// on attendance, so only Paid is shown there.
    private var draftOwed: Double {
        guard contract.kind == .privateBundle else { return 0 }
        return max(0, pricePerSession * Double(bundleSize) - draftPaid)
    }
    private var currencyCode: String { dataManager.appSettings.currency.currencyCode }

    var body: some View {
        MacSheetChrome(title: "Contract #\(contract.contractNumber)") { dismiss() } content: {
            Form {
                Section("Status") {
                    Picker("Status", selection: $manualStatus) {
                        Text("Automatic (derived)").tag(ContractStatus?.none)
                        ForEach(ContractStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(Optional(status))
                        }
                    }
                    Text("Automatic derives from bundle exhaustion; a manual status overrides it — the same rule iOS applies.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Dates") {
                    DatePicker("Enrolled", selection: $enrollmentDate,
                               displayedComponents: .date)
                }
                Section("Pricing") {
                    HStack {
                        Text("Per session")
                        Spacer()
                        TextField("", value: $pricePerSession,
                                  format: .currency(code: currencyCode))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 130)
                    }
                    if contract.kind == .privateBundle {
                        LabeledContent("Bundle total",
                                       value: (pricePerSession * Double(bundleSize))
                                        .formatted(.currency(code: currencyCode)))
                    }
                }
                Section {
                    if payments.isEmpty {
                        Text("No payments recorded.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(payments) { payment in
                        HStack {
                            Text(payment.date, format: .dateTime.year().month().day())
                            Spacer()
                            Text(payment.amount.formatted(.currency(code: currencyCode)))
                                .monospacedDigit()
                            Button {
                                payments.removeAll { $0.id == payment.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove payment (correction)")
                        }
                    }
                    HStack {
                        DatePicker("", selection: $newPaymentDate,
                                   displayedComponents: .date)
                            .labelsHidden()
                        TextField("Amount", text: $newPaymentAmount)
                            .frame(width: 90)
                        Button {
                            guard let amount = Double(newPaymentAmount), amount > 0
                            else { return }
                            payments.append(ContractPayment(date: newPaymentDate,
                                                            amount: amount))
                            payments.sort { $0.date < $1.date }
                            newPaymentAmount = ""
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .disabled(Double(newPaymentAmount) == nil
                                  || (Double(newPaymentAmount) ?? 0) <= 0)
                    }
                    HStack(spacing: 16) {
                        LabeledContent("Paid",
                                       value: draftPaid.formatted(.currency(code: currencyCode)))
                        if contract.kind == .privateBundle {
                            LabeledContent("Owed",
                                           value: draftOwed.formatted(.currency(code: currencyCode)))
                        }
                    }
                    .font(.callout.weight(.semibold))
                } header: {
                    Text("Payments")
                } footer: {
                    Text("Paid is the sum of the ledger; owed derives from bundle total minus paid. Travel fees stay separate by design.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if contract.hasSessionBalance {
                    Section(contract.kind == .group ? "Session balance" : "Bundle") {
                        Stepper("\(contract.kind == .group ? "Balance" : "Bundle") size: \(bundleSize) sessions",
                                value: $bundleSize,
                                in: max(1, consumed)...100)
                        LabeledContent("Consumed",
                                       value: "\(consumed) (owned by roll call)")
                        LabeledContent("Remaining",
                                       value: "\(max(0, bundleSize - consumed))")
                        if bundleSize != contract.bundleSize {
                            Label("Resizing the bundle changes sessions remaining. Roll call normally owns this number — only override to correct a booking error.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("Remaining can never go below zero: the floor of the size stepper is the sessions already consumed (\(consumed)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Done") { commit() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 420)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            manualStatus = contract.manualStatus
            enrollmentDate = contract.enrollmentDate
            bundleSize = max(contract.bundleSize, 1)
            pricePerSession = contract.pricePerSession
            payments = contract.payments
        }
    }

    private func commit() {
        let old = contract
        var copy = contract
        var changes: [String] = []
        if copy.manualStatus != manualStatus {
            changes.append("status \(copy.manualStatus?.rawValue ?? "auto")→\(manualStatus?.rawValue ?? "auto")")
            copy.manualStatus = manualStatus
        }
        if copy.enrollmentDate != enrollmentDate {
            changes.append("enrolled \(copy.enrollmentDate.formatted(date: .numeric, time: .omitted))→\(enrollmentDate.formatted(date: .numeric, time: .omitted))")
            copy.enrollmentDate = enrollmentDate
        }
        if contract.hasSessionBalance, copy.bundleSize != bundleSize {
            changes.append("bundle \(copy.bundleSize)→\(bundleSize)")
            copy.bundleSize = max(bundleSize, consumed)
        }
        if abs(copy.pricePerSession - pricePerSession) > 0.001 {
            changes.append("price \(Int(copy.pricePerSession))→\(Int(pricePerSession))")
            copy.pricePerSession = max(0, pricePerSession)
        }
        if copy.payments != payments {
            changes.append("paid \(Int(copy.amountPaid))→\(Int(draftPaid))")
            copy.payments = payments.sorted { $0.date < $1.date }
        }
        guard !changes.isEmpty else { dismiss(); return }
        // Minimal mutation log in the EXISTING notes field — no new schema.
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        let line = "[\(stamp)] Mac edit: \(changes.joined(separator: ", "))"
        copy.notes = ((copy.notes ?? "").isEmpty ? line : (copy.notes! + "\n" + line))
        dataManager.updateContract(copy)
        undoManager?.registerUndo(withTarget: dataManager) { manager in
            manager.updateContract(old)
        }
        undoManager?.setActionName("Edit Contract")
        dismiss()
    }
}
