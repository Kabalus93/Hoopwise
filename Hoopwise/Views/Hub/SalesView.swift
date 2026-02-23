import SwiftUI
import Combine

struct SalesView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var selectedFilter: ContractFilter = .all
    @State private var showingAddContract = false
    
    enum ContractFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case pending = "Pending"
        case expiring = "Expiring"
        case completed = "Completed"
    }
    
    var filteredContracts: [(Student, Contract)] {
        var results: [(Student, Contract)] = []
        
        for student in dataManager.students {
            if let contract = dataManager.currentContract(for: student.id) {
                // Search filter
                if !searchText.isEmpty {
                    let matchesSearch = student.name.localizedCaseInsensitiveContains(searchText) ||
                        (student.chineseName?.localizedCaseInsensitiveContains(searchText) ?? false)
                    if !matchesSearch { continue }
                }
                
                // Status filter
                switch selectedFilter {
                case .all:
                    break
                case .active:
                    if contract.status != .active { continue }
                case .pending:
                    if contract.status != .pending { continue }
                case .expiring:
                    // Expiring within 2 weeks or less than 5 sessions remaining
                    let isExpiringSoon = (contract.remainingSessions ?? 0) <= 5 && contract.status == .active
                    if !isExpiringSoon { continue }
                case .completed:
                    if contract.status != .completed { continue }
                }
                
                results.append((student, contract))
            }
        }
        
        return results.sorted { $0.0.name < $1.0.name }
    }
    
    // Stats
    var activeContracts: Int {
        filteredContracts.filter { $0.1.status == .active }.count
    }
    
    var pendingContracts: Int {
        filteredContracts.filter { $0.1.status == .pending }.count
    }
    
    var expiringContracts: Int {
        filteredContracts.filter { !$0.1.isPayAsYouGo && ($0.1.remainingSessions ?? 0) <= 5 && $0.1.status == .active }.count
    }
    
    var totalRevenue: Double {
        filteredContracts.reduce(0) { $0 + $1.1.amountPaid }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search
            searchBar
            
            // Stats
            statsSection
            
            // Filters
            filterChips
            
            // Contracts List
            if filteredContracts.isEmpty {
                emptyState
            } else {
                contractsList
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
            
            TextField("Search students...", text: $searchText)
                .font(.system(size: 16))
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.smallCornerRadius)
        .padding(.horizontal, AppTheme.spacing)
        .padding(.bottom, AppTheme.smallSpacing)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 10) {
            SalesStatCard(value: "\(activeContracts)", label: "Active", color: AppTheme.successColor)
            SalesStatCard(value: "\(pendingContracts)", label: "Pending", color: AppTheme.warningColor)
            SalesStatCard(value: "\(expiringContracts)", label: "Expiring", color: AppTheme.errorColor)
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.bottom, AppTheme.smallSpacing)
    }
    
    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContractFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.bottom, AppTheme.smallSpacing)
        }
    }
    
    // MARK: - Contracts List
    private var contractsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(filteredContracts, id: \.0.id) { student, contract in
                    NavigationLink(destination: ContractDetailView(student: student, contract: contract)) {
                        ContractCard(student: student, contract: contract)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.bottom, AppTheme.largeSpacing)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(AppTheme.textTertiary)
            
            VStack(spacing: 6) {
                Text("No contracts found")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(searchText.isEmpty ? "Add students to create contracts" : "Try a different search")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Sales Stat Card
struct SalesStatCard: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
    }
}

// MARK: - Contract Card
struct ContractCard: View {
    let student: Student
    let contract: Contract
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            StudentAvatarView(student: student, size: 48)
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(student.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    // Status badge
                    ContractStatusBadge(status: contract.status)
                }
                
                HStack(spacing: 16) {
                    // Sessions
                    HStack(spacing: 4) {
                        Text("\(contract.attendedSessions)/\(contract.totalSessions)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor((contract.remainingSessions ?? 0) < 5 ? AppTheme.warningColor : AppTheme.textPrimary)
                        Text("sessions")
                            .font(AppTheme.captionFont)
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    // Contract number
                    Text(contract.contractLabel)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.surfaceColor)
                        
                        Capsule()
                            .fill((contract.remainingSessions ?? 0) < 5 ? AppTheme.warningColor : AppTheme.accentColor)
                            .frame(width: max(geometry.size.width * contract.progressPercentage, 4))
                    }
                }
                .frame(height: 4)
            }
            
            // Indicators
            VStack(spacing: 6) {
                // Signed
                Image(systemName: contract.isSigned ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 14))
                    .foregroundColor(contract.isSigned ? AppTheme.successColor : AppTheme.textTertiary)
                
                // Jersey
                Image(systemName: contract.jerseyGiven ? "tshirt.fill" : "tshirt")
                    .font(.system(size: 14))
                    .foregroundColor(contract.jerseyGiven ? AppTheme.accentColor : AppTheme.textTertiary)
            }
        }
        .padding(AppTheme.spacing)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
    }
}

// MARK: - Contract Status Badge
struct ContractStatusBadge: View {
    let status: ContractStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.contractStatusColor(status))
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.contractStatusColor(status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.contractStatusColor(status).opacity(0.12))
        .cornerRadius(12)
    }
}

// MARK: - Contract Detail View
struct ContractDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let student: Student
    @State var contract: Contract
    @State private var showingEditContract = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.largeSpacing) {
                // Header
                headerSection
                
                // Progress Section
                progressSection
                
                // Contract Details
                contractDetailsSection
                
                // Status Toggles
                statusTogglesSection
                
                // Equipment Section
                equipmentSection
                
                // Contract History
                contractHistorySection
            }
            .padding(.horizontal, AppTheme.spacing)
            .padding(.bottom, AppTheme.largeSpacing)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Contract")
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                Button("Edit") {
                    showingEditContract = true
                }
                .foregroundColor(AppTheme.accentColor)
            }
        }
        .sheet(isPresented: $showingEditContract) {
            EditContractView(contract: $contract)
        }
        .onAppear {
            // Sync with dataManager on appear to get latest data
            if let updatedContract = dataManager.contracts.first(where: { $0.id == contract.id }) {
                contract = updatedContract
            }
        }
        .onReceive(dataManager.objectWillChange) { _ in
            // Refresh contract when dataManager changes
            if let updatedContract = dataManager.contracts.first(where: { $0.id == contract.id }) {
                contract = updatedContract
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            StudentAvatarView(student: student, size: 80)
            
            VStack(spacing: 4) {
                Text(student.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(contract.contractLabel)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            ContractStatusBadge(status: contract.status)
        }
        .padding(.top, AppTheme.spacing)
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceColor, lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: contract.progressPercentage)
                    .stroke(
                        (contract.remainingSessions ?? 0) < 5 ? AppTheme.warningColor : AppTheme.accentColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(contract.remainingSessions ?? 0)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("remaining")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            // Stats row
            HStack(spacing: 0) {
                statItem(value: "\(contract.attendedSessions)", label: "Attended")
                Divider().frame(height: 40)
                statItem(value: "\(contract.totalSessions)", label: "Total")
                Divider().frame(height: 40)
                statItem(value: "\(Int(contract.progressPercentage * 100))%", label: "Progress")
            }
            .padding(.vertical, AppTheme.spacing)
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Contract Details Section
    private var contractDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.smallSpacing) {
            sectionHeader("Contract Details")
            
            VStack(spacing: 0) {
                detailRow(icon: "calendar", label: "Start Date", value: formatDate(contract.startDate))
                Divider().padding(.horizontal, AppTheme.spacing)
                detailRow(icon: "calendar.badge.clock", label: "Expiry Date", value: formatDate(contract.expiryDate))
                Divider().padding(.horizontal, AppTheme.spacing)
                detailRow(icon: "yensign.circle", label: "Price/Session", value: "¥\(Int(contract.pricePerSession))")
                Divider().padding(.horizontal, AppTheme.spacing)
                detailRow(icon: "banknote", label: "Total Amount", value: "¥\(Int(contract.totalAmount))")
                Divider().padding(.horizontal, AppTheme.spacing)
                detailRow(
                    icon: "checkmark.circle",
                    label: "Amount Paid",
                    value: "¥\(Int(contract.amountPaid))",
                    valueColor: contract.isFullyPaid ? AppTheme.successColor : AppTheme.warningColor
                )
                
                if contract.outstandingBalance > 0 {
                    Divider().padding(.horizontal, AppTheme.spacing)
                    detailRow(
                        icon: "exclamationmark.circle",
                        label: "Outstanding",
                        value: "¥\(Int(contract.outstandingBalance))",
                        valueColor: AppTheme.errorColor
                    )
                }
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, valueColor: Color = AppTheme.textPrimary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.vertical, 14)
    }
    
    // MARK: - Status Toggles Section
    private var statusTogglesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.smallSpacing) {
            sectionHeader("Status")
            
            VStack(spacing: 0) {
                toggleRow(
                    icon: "signature",
                    title: "Contract Signed",
                    subtitle: contract.signedDate != nil ? "Signed on \(formatDate(contract.signedDate))" : nil,
                    isOn: Binding(
                        get: { contract.isSigned },
                        set: { newValue in
                            contract.isSigned = newValue
                            contract.signedDate = newValue ? Date() : nil
                            saveContract()
                        }
                    ),
                    color: AppTheme.successColor
                )
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    // MARK: - Equipment Section
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.smallSpacing) {
            sectionHeader("Equipment")
            
            VStack(spacing: 0) {
                toggleRow(
                    icon: "tshirt.fill",
                    title: "Jersey Given",
                    subtitle: contract.jerseyNumber != nil ? "Jersey #\(contract.jerseyNumber!) (\(contract.jerseySize ?? ""))" : nil,
                    isOn: Binding(
                        get: { contract.jerseyGiven },
                        set: { newValue in
                            contract.jerseyGiven = newValue
                            contract.jerseyGivenDate = newValue ? Date() : nil
                            saveContract()
                        }
                    ),
                    color: AppTheme.accentColor
                )
                
                Divider().padding(.horizontal, AppTheme.spacing)
                
                toggleRow(
                    icon: "basketball.fill",
                    title: "Ball Given",
                    subtitle: contract.ballGivenDate != nil ? "Given on \(formatDate(contract.ballGivenDate))" : nil,
                    isOn: Binding(
                        get: { contract.ballGiven },
                        set: { newValue in
                            contract.ballGiven = newValue
                            contract.ballGivenDate = newValue ? Date() : nil
                            saveContract()
                        }
                    ),
                    color: AppTheme.warningColor
                )
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    private func toggleRow(icon: String, title: String, subtitle: String?, isOn: Binding<Bool>, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .tint(color)
                .labelsHidden()
        }
        .padding(.horizontal, AppTheme.spacing)
        .padding(.vertical, 12)
    }
    
    // MARK: - Contract History Section
    private var contractHistorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.smallSpacing) {
            sectionHeader("Contract History")
            
            VStack(spacing: 10) {
                // Show all contracts for this student
                ForEach(1...contract.contractNumber, id: \.self) { num in
                    HStack {
                        Circle()
                            .fill(num == contract.contractNumber ? AppTheme.accentColor : AppTheme.surfaceColor)
                            .frame(width: 8, height: 8)
                        
                        Text(ordinalLabel(num))
                            .font(.system(size: 15, weight: num == contract.contractNumber ? .semibold : .regular))
                            .foregroundColor(num == contract.contractNumber ? AppTheme.textPrimary : AppTheme.textSecondary)
                        
                        Spacer()
                        
                        if num == contract.contractNumber {
                            Text("Current")
                                .font(AppTheme.captionFont)
                                .foregroundColor(AppTheme.accentColor)
                        } else {
                            Text("Completed")
                                .font(AppTheme.captionFont)
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacing)
                    .padding(.vertical, 12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(AppTheme.smallCornerRadius)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not set" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func ordinalLabel(_ num: Int) -> String {
        let suffix: String
        switch num {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(num)\(suffix) Contract"
    }
    
    private func saveContract() {
        // Save contract to data manager
        dataManager.updateContract(contract)
    }
}

// MARK: - Edit Contract View
struct EditContractView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Binding var contract: Contract
    
    @State private var totalSessions: Int = 0
    @State private var pricePerSession: Double = 0
    @State private var amountPaid: Double = 0
    @State private var startDate: Date = Date()
    @State private var expiryDate: Date = Date()
    @State private var jerseyNumber: String = ""
    @State private var jerseySize: String = ""
    @State private var notes: String = ""
    
    let jerseySizes = ["YS", "YM", "YL", "S", "M", "L", "XL"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sessions") {
                    Stepper("Total Sessions: \(totalSessions)", value: $totalSessions, in: 1...100)
                    
                    HStack {
                        Text("Attended")
                        Spacer()
                        Text("\(contract.attendedSessions)")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                Section("Pricing") {
                    HStack {
                        Text("Price per Session")
                        Spacer()
                        TextField("0", value: $pricePerSession, format: .number)
                            .keyboardTypeCompat(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("¥")
                    }
                    
                    HStack {
                        Text("Total Amount")
                        Spacer()
                        Text("¥\(Int(Double(totalSessions) * pricePerSession))")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    HStack {
                        Text("Amount Paid")
                        Spacer()
                        TextField("0", value: $amountPaid, format: .number)
                            .keyboardTypeCompat(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("¥")
                    }
                }
                
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                }
                
                Section("Equipment") {
                    HStack {
                        Text("Jersey Number")
                        Spacer()
                        TextField("#", text: $jerseyNumber)
                            .keyboardTypeCompat(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    
                    Picker("Jersey Size", selection: $jerseySize) {
                        Text("Select").tag("")
                        ForEach(jerseySizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Contract")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeadingCompat) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailingCompat) {
                    Button("Save") {
                        contract.totalSessions = totalSessions
                        contract.pricePerSession = pricePerSession
                        contract.totalAmount = Double(totalSessions) * pricePerSession
                        contract.amountPaid = amountPaid
                        contract.startDate = startDate
                        contract.expiryDate = expiryDate
                        contract.jerseyNumber = Int(jerseyNumber)
                        contract.jerseySize = jerseySize.isEmpty ? nil : jerseySize
                        contract.notes = notes.isEmpty ? nil : notes
                        contract.updatedAt = Date()
                        
                        // Persist to SwiftData
                        dataManager.updateContract(contract)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                totalSessions = contract.totalSessions
                pricePerSession = contract.pricePerSession
                amountPaid = contract.amountPaid
                startDate = contract.startDate ?? Date()
                expiryDate = contract.expiryDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())!
                jerseyNumber = contract.jerseyNumber != nil ? "\(contract.jerseyNumber!)" : ""
                jerseySize = contract.jerseySize ?? ""
                notes = contract.notes ?? ""
            }
        }
    }
}

#Preview {
    NavigationStack {
        SalesView()
            .environmentObject(DataManager.shared)
    }
}
