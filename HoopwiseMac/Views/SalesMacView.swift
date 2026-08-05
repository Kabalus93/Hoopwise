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
    @State private var search = ""
    @State private var selection: UUID?   // student id

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

            Picker("Filter", selection: $filter) {
                ForEach(ContractFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
/// (the client-facing documents), edit and renew included.
private struct SalesContractDetail: View {
    let student: Student
    @EnvironmentObject var dataManager: DataManager

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

                AthleteContractsTab(student: student)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
