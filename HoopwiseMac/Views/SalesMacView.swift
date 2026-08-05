import SwiftUI
import Charts

// MARK: - Sales (private clients + revenue)
//
// The Mac counterpart of iOS's Hub → Sales page: monthly coach revenue with
// a trend, active bundle tracking, and per-contract client documents. Every
// number comes from the SAME shared accessors iOS reads
// (currentMonthCoachRevenue, coachRevenue(in:), coachRevenueHistory,
// bundleRedemptionsRemaining) — no re-derived figures, per the fabricated-
// accessor lesson: a revenue page that disagrees with iOS is worse than no
// page. Documents reuse the shared statement/agreement renderers via the
// contract card's export menu.
struct SalesMacView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var filter: ContractFilter = .all
    /// Kind filter — PRIVATE BUNDLE by default: this page exists to track
    /// private clients; group rosters live in Programs.
    @AppStorage("sales.kindFilter") private var kindFilterRaw = "privateBundle"
    @State private var search = ""
    @State private var selection: UUID?   // student id

    enum KindFilter: String, CaseIterable, Identifiable {
        case all, privateBundle, payPerSession, group
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All Types"
            case .privateBundle: return "Private Bundle"
            case .payPerSession: return "Pay-per-session"
            case .group: return "Group"
            }
        }
        func matches(_ kind: ContractKind) -> Bool {
            switch self {
            case .all: return true
            case .privateBundle: return kind == .privateBundle
            case .payPerSession: return kind == .privatePayPerSession
            case .group: return kind == .group
            }
        }
    }

    private var kindFilter: KindFilter {
        KindFilter(rawValue: kindFilterRaw) ?? .privateBundle
    }

    /// iOS SalesView's filter vocabulary, unchanged.
    enum ContractFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case pending = "Pending"
        case expiring = "Expiring"
        case completed = "Completed"
        var id: String { rawValue }
    }

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
                .frame(maxHeight: .infinity)
            Group {
                if let id = selection,
                   let student = dataManager.students.first(where: { $0.id == id }) {
                    SalesContractDetail(student: student)
                        .id(student.id)
                } else {
                    EmptyDetail(systemImage: "creditcard",
                                title: "Select a Client")
                }
            }
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Sales")
        .onAppear { autoSelect() }
        .onChange(of: filter) { _, _ in autoSelect() }
        .onChange(of: kindFilterRaw) { _, _ in autoSelect() }
        .onChange(of: search) { _, _ in autoSelect() }
    }

    // MARK: - Left column

    private var listColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    revenueCard
                    statRow
                }
                .padding(12)
            }
            .frame(maxHeight: 330)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clients", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Picker("Type", selection: $kindFilterRaw) {
                    ForEach(KindFilter.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Picker("Filter", selection: $filter) {
                    ForEach(ContractFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)

            Divider()

            List(selection: $selection) {
                ForEach(filteredContracts, id: \.0.id) { student, contract in
                    SalesContractRow(student: student, contract: contract,
                                     currencySymbol: dataManager.appSettings.currency.symbol)
                        .tag(student.id)
                }
                if filteredContracts.isEmpty {
                    Text("No contracts match.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    /// This month vs last, plus the 12-month trend — all from the shared
    /// revenue accessors.
    private var revenueCard: some View {
        let history = dataManager.coachRevenueHistory(months: 12)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This month").font(.caption).foregroundStyle(.secondary)
                    Text(currency(dataManager.currentMonthCoachRevenue))
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last month").font(.caption).foregroundStyle(.secondary)
                    Text(currency(lastMonthRevenue))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Chart(history, id: \.month) { entry in
                BarMark(
                    x: .value("Month", entry.month, unit: .month),
                    y: .value("Revenue", entry.amount)
                )
                .foregroundStyle(Calendar.current.isDate(entry.month, equalTo: Date(),
                                                         toGranularity: .month)
                                 ? Color.accentColor
                                 : Color.accentColor.opacity(0.35))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactCurrency(amount)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 110)
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // iOS's stat cards exactly: Active / Bundles / Group. (An "Expiring"
    // card was tried and read 129-of-133 — the shared expiring formula
    // counts group contracts, which never run down a bundle. The FILTER
    // keeps iOS's formula for parity; the headline stats match iOS.)
    private var statRow: some View {
        HStack(spacing: 8) {
            salesStat("\(activeCount)", "Active", .green)
            salesStat("\(bundleCount)", "Bundles", .accentColor)
            salesStat("\(groupCount)", "Group", .secondary)
        }
    }

    private func salesStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Data (iOS SalesView's definitions, same accessors)

    private var allContracts: [(Student, Contract)] {
        var results: [(Student, Contract)] = []
        for student in dataManager.students {
            if let contract = dataManager.currentContract(for: student.id) {
                results.append((student, contract))
            }
        }
        return results.sorted {
            let l = NameIndex.cached(name: $0.0.name, secondary: $0.0.chineseName)
            let r = NameIndex.cached(name: $1.0.name, secondary: $1.0.chineseName)
            return l.sortKey < r.sortKey
        }
    }

    private var filteredContracts: [(Student, Contract)] {
        allContracts.filter { student, contract in
            if !kindFilter.matches(contract.kind) { return false }
            if !search.isEmpty,
               !NameIndex.cached(name: student.name,
                                 secondary: student.chineseName).matches(search) {
                return false
            }
            switch filter {
            case .all: return true
            case .active: return contract.status == .active
            case .pending: return contract.status == .pending
            case .expiring:
                return (contract.remainingSessions ?? 0) <= 5 && contract.status == .active
            case .completed: return contract.status == .completed
            }
        }
    }

    private var activeCount: Int {
        allContracts.filter { $0.1.status == .active }.count
    }
    private var bundleCount: Int {
        allContracts.filter { $0.1.kind == .privateBundle }.count
    }
    private var groupCount: Int {
        allContracts.filter { $0.1.kind == .group }.count
    }

    private var lastMonthRevenue: Double {
        guard let last = Calendar.current.date(byAdding: .month, value: -1, to: Date())
        else { return 0 }
        return dataManager.coachRevenue(in: last)
    }

    private func currency(_ amount: Double) -> String {
        "\(dataManager.appSettings.currency.symbol)\(Int(amount))"
    }

    private func compactCurrency(_ amount: Double) -> String {
        let symbol = dataManager.appSettings.currency.symbol
        if amount >= 1000 { return "\(symbol)\(Int(amount / 1000))k" }
        return "\(symbol)\(Int(amount))"
    }

    private func autoSelect() {
        let items = filteredContracts
        if let current = selection, items.contains(where: { $0.0.id == current }) { return }
        selection = items.first?.0.id
    }
}

// MARK: - Row

private struct SalesContractRow: View {
    let student: Student
    let contract: Contract
    let currencySymbol: String

    var body: some View {
        HStack(spacing: 9) {
            AthletePhoto(imageData: student.thumbnailImageData ?? student.profileImageData,
                         initials: student.initials,
                         color: Color.avatarColor(student.avatarColor),
                         size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(student.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                    if let chinese = student.chineseName, chinese != student.displayName {
                        Text(chinese)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(contract.kind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if contract.kind == .privateBundle {
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(contract.bundleRedemptionsRemaining ?? 0) left")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle((contract.bundleRedemptionsRemaining ?? 0) <= 3
                                             ? .orange : .secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(contract.status.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(statusTint.opacity(0.16), in: .capsule)
                .foregroundStyle(statusTint)
        }
        .padding(.vertical, 1)
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
}

// MARK: - Detail

/// Right pane: the client's full contract history with the existing Mac
/// contract cards — statements and agreements export from each card's menu
/// (the client-facing documents), edit and renew included. Private bundles
/// additionally show their ATTENDANCE HISTORY (the redemption ledger, read
/// from contract.bundleSessionIds — never recomputed) plus upcoming private
/// sessions, and a scheduler that creates sessions the redemption authority
/// automatically counts against the bundle at roll call.
private struct SalesContractDetail: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager
    @State private var schedulingSession = false
    @State private var editingSession: SessionEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    AthletePhoto(imageData: student.profileImageData,
                                 initials: student.initials,
                                 color: Color.avatarColor(student.avatarColor),
                                 size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(student.displayName).font(.title2.weight(.bold))
                            if let chinese = student.chineseName,
                               chinese != student.displayName {
                                Text(chinese).font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        Text("Documents export from each contract's menu — attendance statement (the client-facing session summary) and training agreements.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: .macSidebarSelection,
                                                        object: SidebarSection.athletes.rawValue)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(name: .macOpenAthlete,
                                                            object: student.id)
                        }
                    } label: {
                        Label("Open in Athletes", systemImage: "person.crop.circle")
                    }
                    .fixedSize()
                }

                ForEach(bundleContracts) { contract in
                    bundleHistorySection(contract)
                }

                AthleteContractsTab(student: student)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $schedulingSession) {
            PrivateSessionSheet(student: student)
                .dismissesOnPresentationEscape { schedulingSession = false }
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session)
                .dismissesOnPresentationEscape { editingSession = nil }
        }
    }

    private var bundleContracts: [Contract] {
        dataManager.cachedContracts
            .filter { $0.studentId == student.id && $0.kind == .privateBundle }
            .sorted { $0.contractNumber > $1.contractNumber }
    }

    // MARK: - Bundle attendance history + scheduling

    @ViewBuilder
    private func bundleHistorySection(_ contract: Contract) -> some View {
        let redeemed = redeemedSessions(contract)
        let upcoming = upcomingPrivateSessions()
        let remaining = contract.bundleRedemptionsRemaining ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bundle #\(contract.contractNumber) — Attendance")
                        .font(.headline)
                    // Consumption bar: the ledger drawn as progress, same
                    // number the statement prints.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(remaining <= 3 ? Color.orange : Color.green)
                                .frame(width: geo.size.width
                                       * CGFloat(redeemed.count)
                                       / CGFloat(max(contract.bundleSize, 1)))
                        }
                    }
                    .frame(width: 180, height: 5)
                    Text("\(redeemed.count) of \(contract.bundleSize) used · \(remaining) left")
                        .font(.caption)
                        .foregroundStyle(remaining <= 3 ? .orange : .secondary)
                }
                Spacer()
                Button {
                    schedulingSession = true
                } label: {
                    Label("Schedule Session", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if redeemed.isEmpty && upcoming.isEmpty {
                EmptyPanel(systemImage: "calendar",
                           text: "No sessions redeemed against this bundle yet.")
            } else {
                VStack(spacing: 3) {
                    // The redemption ledger — the array the redemption
                    // authority writes, same source as the client statement.
                    ForEach(Array(redeemed.enumerated()), id: \.element.id) { index, session in
                        bundleSessionRow(session, contract: contract,
                                         number: redeemed.count - index, upcoming: false)
                    }
                    if !redeemed.isEmpty && !upcoming.isEmpty {
                        HStack {
                            Text("Scheduled")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            VStack { Divider() }
                        }
                        .padding(.top, 4)
                    }
                    ForEach(upcoming) { session in
                        bundleSessionRow(session, contract: contract,
                                         number: nil, upcoming: true)
                    }
                }
            }
            Text("Sessions count against the bundle when attendance is marked Present or unexcused Absent — scheduling alone deducts nothing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Ledger order: the sessions this bundle actually paid for.
    private func redeemedSessions(_ contract: Contract) -> [SessionEvent] {
        contract.bundleSessionIds.compactMap { id in
            dataManager.sessionEvents.first { $0.id == id }
        }
        .sorted { $0.date > $1.date }
    }

    /// Scheduled private sessions for this client not yet redeemed by any
    /// bundle — what is on the calendar against their contract.
    private func upcomingPrivateSessions() -> [SessionEvent] {
        let redeemedIds = Set(dataManager.cachedContracts
            .filter { $0.studentId == student.id }
            .flatMap(\.bundleSessionIds))
        return dataManager.sessionEvents.filter { session in
            session.date >= Date()
                && session.status == .scheduled
                && session.programId == nil
                && session.attendeeIds.contains(student.id)
                && !redeemedIds.contains(session.id)
        }
        .sorted { $0.date < $1.date }
    }

    private func bundleSessionRow(_ session: SessionEvent,
                                  contract: Contract,
                                  number: Int?,
                                  upcoming: Bool) -> some View {
        let attended = session.actualAttendeeIds.contains(student.id)
        let unexcused = session.unexcusedAbsences.contains(student.id)
        return BundleHistoryRow(
            title: session.title,
            date: session.date,
            number: number,
            icon: upcoming ? "calendar"
                : (attended ? "checkmark.circle.fill" : "xmark.circle.fill"),
            tint: upcoming ? Color.secondary : (attended ? Color.green : Color.orange),
            trailing: upcoming ? "Scheduled"
                : (attended ? "Attended" : (unexcused ? "Absent · charged" : "Charged")),
            action: { editingSession = session })
    }
}

/// One ledger row: number chip, status glyph, hover-revealed edit affordance,
/// whole row clickable — the directory row grammar at history density.
private struct BundleHistoryRow: View {
    let title: String
    let date: Date
    let number: Int?
    let icon: String
    let tint: Color
    let trailing: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let number {
                    Text("\(number)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .frame(width: 20, height: 20)
                        .background(tint.opacity(0.14), in: Circle())
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(date, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
                Text(trailing)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(tint)
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(hovering ? Color.accentColor : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering
                    ? AnyShapeStyle(Color.accentColor.opacity(0.07))
                    : AnyShapeStyle(Color(NSColor.windowBackgroundColor).opacity(0.55)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .help("Edit session")
    }
}

// MARK: - Private session scheduler

/// Creates a 1:1 session that the redemption authority automatically counts
/// against the client's contract: program-less with the client on the
/// roster, which is exactly the "program-less private path" rule
/// (eventIsPrivate) — bundle redemption and PAYG revenue attribute at roll
/// call, FIFO across their bundles. Deduction NEVER happens at scheduling.
private struct PrivateSessionSheet: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Self.defaultStart()
    @State private var durationMinutes = 60
    @State private var location = ""
    @State private var loaded = false

    private var isPast: Bool { date < Date() }

    var body: some View {
        MacSheetChrome(title: "Private Session — \(student.displayName)") { dismiss() } content: {
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $date)
                Stepper("Duration: \(durationMinutes) min",
                        value: $durationMinutes, in: 30...180, step: 15)
                TextField("Location", text: $location)
                Section {
                    LabeledContent("Roster", value: student.displayName)
                    if let contract = dataManager.currentContract(for: student.id) {
                        LabeledContent("Contract",
                                       value: contract.kind == .privateBundle
                                       ? "Bundle · \(contract.bundleRedemptionsRemaining ?? 0) left"
                                       : contract.kind.rawValue)
                    }
                } footer: {
                    if isPast {
                        Label("This date is in the past: the session is logged as completed with \(student.displayName) marked Present — it charges the contract immediately and appears in the attendance history.",
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Counts against the contract when attendance is marked — Present or unexcused Absent deducts, Excused does not.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button(isPast ? "Log as Attended" : "Schedule") { commit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 440, minHeight: 380)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = "Private · \(student.displayName)"
        }
    }

    private static func defaultStart() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func commit() {
        let now = Date()
        let backdated = isPast
        let session = SessionEvent(
            id: UUID(),
            programId: nil,     // program-less = the private path
            sessionType: .training,
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            startTime: date,
            endTime: Calendar.current.date(byAdding: .minute,
                                           value: durationMinutes, to: date) ?? date,
            location: location.isEmpty ? nil : location,
            status: backdated ? .completed : .scheduled,
            attendeeIds: [student.id],
            createdByCoachId: dataManager.loggedInCoachId,
            createdAt: now,
            updatedAt: now
        )
        dataManager.addSessionEvent(session)
        if backdated {
            // Through THE attendance authority, so the redemption lockstep
            // (FIFO bundle deduction) fires exactly as a live roll call would.
            dataManager.setStudentAttendanceState(sessionId: session.id,
                                                  studentId: student.id,
                                                  state: .present)
        }
        dismiss()
    }
}
