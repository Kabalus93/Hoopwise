import SwiftUI

// MARK: - Add / Edit Contract Sheet
/// Three-kind contract form. Each kind exposes only its relevant fields:
/// - `.privatePayPerSession`: price, enrollment date.
/// - `.privateBundle`: price + bundle size + purchase date.
/// - `.group`: the student's classes (from rosters) + an optional prepaid
///   session balance.
struct AddEditContractSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager

    let studentId: UUID
    let existing: Contract?

    @State private var kind: ContractKind
    @State private var enrollmentDate: Date
    @State private var pricePerSession: Double
    @State private var bundleSize: Int
    @State private var bundlePurchaseDate: Date
    @State private var programId: UUID?
    @State private var notes: String
    @State private var payments: [ContractPayment]
    @State private var travelFeeAmount: Double
    @State private var travelFeeBasis: TravelFeeBasis
    /// Group only: whether this contract carries a prepaid session balance,
    /// and how many sessions are left on it.
    @State private var groupHasBalance: Bool
    @State private var groupRemaining: Int
    @State private var newPaymentAmount: Double = 0
    @State private var newPaymentDate: Date = Date()
    @State private var shareURL: URL?

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    private var groupPrograms: [Program] {
        dataManager.programs
            .filter { $0.programType != .privateSessions && $0.status != .archived }
            .sorted { $0.displayName < $1.displayName }
    }

    private var canSave: Bool {
        switch kind {
        case .privatePayPerSession:
            return pricePerSession > 0
        case .privateBundle:
            return pricePerSession > 0 && bundleSize > 0
        case .group:
            return !groupHasBalance || groupRemaining >= 0
        }
    }

    init(studentId: UUID, existing: Contract? = nil) {
        self.studentId = studentId
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? .privatePayPerSession)
        _enrollmentDate = State(initialValue: existing?.enrollmentDate ?? Date())
        _pricePerSession = State(initialValue: existing?.pricePerSession ?? 0)
        _bundleSize = State(initialValue: max(existing?.bundleSize ?? 10, 1))
        _bundlePurchaseDate = State(initialValue: existing?.bundlePurchaseDate ?? existing?.enrollmentDate ?? Date())
        _programId = State(initialValue: existing?.programId)
        _notes = State(initialValue: existing?.notes ?? "")
        _payments = State(initialValue: existing?.payments ?? [])
        _travelFeeAmount = State(initialValue: existing?.travelFeeAmount ?? 0)
        _travelFeeBasis = State(initialValue: existing?.travelFeeBasis ?? .perContract)
        let groupBalance = existing.flatMap { $0.kind == .group ? $0.bundleRedemptionsRemaining : nil }
        _groupHasBalance = State(initialValue: groupBalance != nil)
        _groupRemaining = State(initialValue: groupBalance ?? 10)
    }

    /// Sessions this contract has already deducted — the floor for its size.
    /// A group contract that had no balance carries only legacy entries
    /// (from a removed launch-time rewrite), which do not count.
    private var usedSessions: Int {
        guard let existing, existing.hasSessionBalance else { return 0 }
        return existing.bundleSessionIds.count
    }

    /// The classes this student is on — derived from the rosters, the same
    /// relation attendance uses.
    private var studentClasses: [Program] {
        dataManager.programs
            .filter { $0.enrolledStudentIds.contains(studentId)
                && $0.programType != .privateSessions && $0.status != .archived }
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                fieldsSection
                if kind != .group {
                    paymentsSection
                    travelSection
                }
                redeemedSection
                documentsSection
                notesSection
                if existing != nil { dangerSection }
            }
            .sheet(item: $shareURL) { url in
                DocumentShareSheet(url: url)
            }
            .navigationTitle(existing == nil
                             ? (isChinese ? "新合同" : "New Contract")
                             : (isChinese ? "编辑合同" : "Edit Contract"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var kindSection: some View {
        Section {
            Picker(selection: $kind) {
                ForEach(ContractKind.allCases, id: \.self) { k in
                    Label(k.displayName, systemImage: k.icon).tag(k)
                }
            } label: {
                Text(isChinese ? "类型" : "Kind")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: kind.icon)
                    .foregroundStyle(.secondary)
                Text(kind.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        switch kind {
        case .privatePayPerSession:
            Section {
                priceRow
                DatePicker(isChinese ? "开始日期" : "Start date",
                           selection: $enrollmentDate,
                           displayedComponents: .date)
            } header: {
                Text(isChinese ? "私教 · 按次付费" : "Pay per session")
            } footer: {
                Text(isChinese
                     ? "每次出席私教课时，按上述价格计入当月收入。"
                     : "Revenue is added each time the student attends a private session.")
            }

        case .privateBundle:
            Section {
                priceRow
                Stepper(value: $bundleSize, in: 1...50) {
                    HStack {
                        Text(isChinese ? "课时数" : "Sessions in bundle")
                        Spacer()
                        Text("\(bundleSize)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                HStack {
                    Text(isChinese ? "套餐金额" : "Bundle total")
                    Spacer()
                    Text(currencyString(pricePerSession * Double(bundleSize)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                DatePicker(isChinese ? "购买日期" : "Purchase date",
                           selection: $bundlePurchaseDate,
                           displayedComponents: .date)
                    .onChange(of: bundlePurchaseDate) { _, newDate in
                        if existing == nil { enrollmentDate = newDate }
                    }
            } header: {
                Text(isChinese ? "私教 · 套餐" : "Bundle")
            } footer: {
                Text(isChinese
                     ? "套餐金额会在购买月计入收入，之后每次出席从套餐余额扣除。"
                     : "The full bundle amount is counted as revenue in the purchase month. Subsequent attendance redeems sessions without adding more revenue.")
            }

        case .group:
            Section {
                if studentClasses.isEmpty {
                    Text(isChinese ? "尚未加入任何班级。" : "Not on any class roster yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(studentClasses) { program in
                        LabeledContent {
                            Text(program.ageGroup.rawValue)
                        } label: {
                            Text(program.resolvedDisplayName(in: dataManager.programs))
                        }
                    }
                }
                DatePicker(isChinese ? "加入日期" : "Joined date",
                           selection: $enrollmentDate,
                           displayedComponents: .date)
            } header: {
                Text(isChinese ? "班级" : "Classes")
            } footer: {
                Text(isChinese
                     ? "来自班级名单。在班级页面中添加或移除学员。"
                     : "From the class rosters. Add or remove the student on the class's page.")
            }

            Section {
                Toggle(isChinese ? "预付课时" : "Prepaid sessions", isOn: $groupHasBalance)
                if groupHasBalance {
                    Stepper(value: $groupRemaining, in: 0...500) {
                        LabeledContent(isChinese ? "剩余课时" : "Sessions left") {
                            Text("\(groupRemaining)")
                                .monospacedDigit()
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(groupRemaining <= 1 ? .orange : .primary)
                        }
                    }
                    if usedSessions > 0 {
                        LabeledContent(isChinese ? "已用" : "Used") {
                            Text(isChinese
                                 ? "\(usedSessions) / \(usedSessions + groupRemaining)"
                                 : "\(usedSessions) of \(usedSessions + groupRemaining)")
                                .monospacedDigit()
                        }
                    }
                    Picker(isChinese ? "适用于" : "Counts for", selection: $programId) {
                        Text(isChinese ? "所有班级（共用）" : "All their classes (shared)").tag(UUID?.none)
                        ForEach(groupPrograms) { program in
                            Text(program.resolvedDisplayName(in: dataManager.programs)).tag(Optional(program.id))
                        }
                    }
                }
            } header: {
                Text(isChinese ? "课时余额" : "Session balance")
            } footer: {
                Text(groupHasBalance
                     ? (isChinese
                        ? "每次出席或无故缺席扣 1 课时；请假和未记录不扣。"
                        : "Each class attended, or missed without notice, deducts one session. Excused and unmarked deduct nothing.")
                     : (isChinese
                        ? "无预付课时：只记录出勤。"
                        : "No prepaid balance: attendance is recorded, nothing is deducted."))
            }
        }
    }

    private var priceRow: some View {
        HStack {
            Text(isChinese ? "单价" : "Price per session")
            Spacer()
            TextField("0", value: $pricePerSession, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            Text(dataManager.appSettings.currency.symbol)
                .foregroundStyle(.secondary)
        }
    }

    /// Session payments only. Travel is entered separately below and is
    /// deliberately not part of this ledger — see `Contract`'s money section.
    private var paymentsSection: some View {
        Section {
            ForEach(payments) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currencyString(payment.amount))
                            .monospacedDigit()
                        Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete { payments.remove(atOffsets: $0) }

            HStack {
                TextField(isChinese ? "金额" : "Amount",
                          value: $newPaymentAmount, format: .number)
                    .keyboardTypeCompat(.decimalPad)
                    .monospacedDigit()
                DatePicker("", selection: $newPaymentDate, displayedComponents: .date)
                    .labelsHidden()
                Button {
                    payments.append(ContractPayment(date: newPaymentDate, amount: newPaymentAmount))
                    payments.sort { $0.date < $1.date }
                    newPaymentAmount = 0
                    newPaymentDate = Date()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newPaymentAmount <= 0)
            }

            HStack {
                Text(isChinese ? "已付" : "Paid")
                Spacer()
                Text(currencyString(paidTotal))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(isChinese ? "应付" : "Owed")
                Spacer()
                Text(currencyString(owedTotal))
                    .monospacedDigit()
                    .foregroundStyle(owedTotal > 0 ? .orange : .green)
            }
        } header: {
            Text(isChinese ? "付款" : "Payments")
        } footer: {
            Text(isChinese
                 ? "可记录多笔部分付款。差旅费用不计入此处。"
                 : "Record partial or installment payments. Travel is tracked separately and is not counted here.")
        }
    }

    private var travelSection: some View {
        Section {
            HStack {
                Text(isChinese ? "差旅费" : "Travel fee")
                Spacer()
                TextField("0", value: $travelFeeAmount, format: .number)
                    .keyboardTypeCompat(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 120)
            }
            Picker(isChinese ? "计费方式" : "Basis", selection: $travelFeeBasis) {
                ForEach(TravelFeeBasis.allCases, id: \.self) { basis in
                    Text(basis.localizedDisplayName(isChinese: isChinese)).tag(basis)
                }
            }
            if travelFeeAmount != 0, travelFeeBasis == .perSession, kind == .privateBundle {
                HStack {
                    Text(isChinese ? "差旅合计" : "Travel total")
                    Spacer()
                    Text(currencyString(travelFeeAmount * Double(bundleSize)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(isChinese ? "差旅" : "Travel")
        } footer: {
            Text(isChinese
                 ? "差旅费独立于课时收入统计，不影响已付/应付课时金额。"
                 : "Travel is tracked apart from session revenue and does not affect paid or owed session amounts.")
        }
    }

    private var paidTotal: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    private var owedTotal: Double {
        let due = kind == .privateBundle ? pricePerSession * Double(bundleSize) : 0
        return max(0, due - paidTotal)
    }

    /// Sessions this bundle has consumed, each with an explicit refund.
    /// The other place a mis-tap gets noticed is here, when the remaining count
    /// looks wrong — so the correction lives here too, not only in the session.
    @ViewBuilder
    private var redeemedSection: some View {
        if let existing, existing.hasSessionBalance, !existing.bundleSessionIds.isEmpty {
            Section {
                ForEach(existing.bundleSessionIds, id: \.self) { sessionId in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sessionLabel(for: sessionId))
                                .font(.subheadline)
                            Text(isChinese ? "已扣除 1 课时" : "1 session deducted")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            dataManager.refundSessionToBundle(sessionId: sessionId,
                                                              studentId: studentId)
                        } label: {
                            Text(isChinese ? "退回" : "Refund")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text(isChinese ? "已消课时" : "Sessions deducted")
            } footer: {
                Text(isChinese
                     ? "如误扣课时，可在此退回。退回不会更改该节课的出席记录。"
                     : "Return a session charged by mistake. Refunding does not change the session's attendance record.")
            }
        }
    }

    private func sessionLabel(for sessionId: UUID) -> String {
        guard let event = dataManager.sessionEvents.first(where: { $0.id == sessionId }) else {
            return isChinese ? "课程" : "Session"
        }
        return "\(event.date.formatted(date: .abbreviated, time: .omitted)) · \(event.title)"
    }

    /// Statement and agreement export. Placed on the contract because both
    /// documents are per-contract.
    @ViewBuilder
    private var documentsSection: some View {
        if let existing {
            Section {
                Button {
                    exportStatement(existing)
                } label: {
                    Label(isChinese ? "出席与账户结算单" : "Attendance & Account Statement",
                          systemImage: "doc.text")
                }
                Button {
                    exportAgreement(existing, blank: false)
                } label: {
                    Label(isChinese ? "协议（含已存授权）" : "Agreement — from contract",
                          systemImage: "doc.badge.gearshape")
                }
                Button {
                    exportAgreement(existing, blank: true)
                } label: {
                    Label(isChinese ? "协议（空白待签）" : "Agreement — blank for signing",
                          systemImage: "signature")
                }
            } header: {
                Text(isChinese ? "文件" : "Documents")
            } footer: {
                Text(isChinese
                     ? "「空白待签」的授权栏为空，供客户当面勾选；「含已存授权」会显示已记录的授权状态。"
                     : "\"Blank for signing\" prints empty consent boxes for the client to tick. \"From contract\" renders the consent state already recorded.")
            }
        }
    }

    private func exportStatement(_ contract: Contract) {
        guard let input = AttendanceStatementDocument.makeInput(
            studentId: studentId, contract: contract, dataManager: dataManager) else { return }
        do { shareURL = try AttendanceStatementDocument.render(input) }
        catch { debugLog("❌ statement export failed: \(error)") }
    }

    private func exportAgreement(_ contract: Contract, blank: Bool) {
        var fields = TrainingAgreementDocument.makeFields(
            studentId: studentId, contract: contract, dataManager: dataManager)
        if blank {
            // Never hand someone a pre-ticked consent form.
            fields.consentCoachingAnalysis = nil
            fields.consentPublicPublication = nil
        }
        do {
            shareURL = try TrainingAgreementDocument.render(
                fields, contractNumber: contract.contractNumber)
        } catch { debugLog("❌ agreement export failed: \(error)") }
    }

    private var notesSection: some View {
        Section {
            TextField(isChinese ? "备注（可选）" : "Notes (optional)",
                      text: $notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                if let existing { dataManager.deleteContract(existing) }
                dismiss()
            } label: {
                Label(isChinese ? "删除合同" : "Delete Contract", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    /// Edits the EXISTING contract in place. It used to rebuild a fresh
    /// Contract from the form's fields, which silently reset everything the
    /// form does not show — the signed / jersey / ball dates, the consent
    /// ledger, validity months, session length — and set a group contract's
    /// session count to zero.
    private func save() {
        let nextNumber = (dataManager.contracts.filter { $0.studentId == studentId }
                            .map(\.contractNumber).max() ?? 0) + 1
        var contract = existing ?? Contract(
            studentId: studentId,
            contractNumber: nextNumber,
            createdByCoachId: dataManager.loggedInCoachId)

        contract.kind = kind
        contract.enrollmentDate = enrollmentDate
        contract.notes = notes.isEmpty ? nil : notes
        contract.travelFeeBasis = travelFeeBasis
        contract.updatedAt = Date()

        switch kind {
        case .privatePayPerSession:
            contract.pricePerSession = pricePerSession
            contract.bundleSize = 0
            contract.bundlePurchaseDate = nil
            contract.programId = nil
            contract.payments = payments
            contract.travelFeeAmount = travelFeeAmount
        case .privateBundle:
            contract.pricePerSession = pricePerSession
            contract.bundleSize = bundleSize
            contract.bundlePurchaseDate = bundlePurchaseDate
            contract.programId = nil
            contract.payments = payments
            contract.travelFeeAmount = travelFeeAmount
        case .group:
            contract.pricePerSession = 0
            contract.payments = []
            contract.travelFeeAmount = 0
            contract.programId = groupHasBalance ? programId : nil
            if groupHasBalance {
                if existing?.hasSessionBalance != true {
                    // Starting a balance: entries left over from before it
                    // existed are not deductions from it.
                    contract.bundleSessionIds = []
                }
                contract.bundleSize = contract.bundleSessionIds.count + groupRemaining
                contract.bundlePurchaseDate = contract.bundlePurchaseDate ?? enrollmentDate
            } else {
                contract.bundleSize = 0
                contract.bundlePurchaseDate = nil
            }
        }

        if existing == nil {
            dataManager.addContract(contract)
        } else {
            dataManager.updateContract(contract)
        }
        dismiss()
    }

    private func currencyString(_ amount: Double) -> String {
        let symbol = dataManager.appSettings.currency.symbol
        return "\(symbol)\(Int(amount))"
    }
}
