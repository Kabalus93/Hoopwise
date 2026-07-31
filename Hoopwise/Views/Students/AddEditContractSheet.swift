import SwiftUI

// MARK: - Add / Edit Contract Sheet
/// Three-kind contract form. Each kind exposes only its relevant fields:
/// - `.privatePayPerSession`: price, enrollment date.
/// - `.privateBundle`: price + bundle size + purchase date.
/// - `.group`: program selection + enrollment date.
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
            return programId != nil
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
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                fieldsSection
                if kind != .group {
                    paymentsSection
                    travelSection
                    redeemedSection
                }
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
                if groupPrograms.isEmpty {
                    Text(isChinese ? "尚未创建团体训练计划。" : "No group programs available yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(isChinese ? "训练计划" : "Program", selection: $programId) {
                        Text(isChinese ? "选择…" : "Select…").tag(UUID?.none)
                        ForEach(groupPrograms) { program in
                            Text(program.resolvedDisplayName(in: dataManager.programs)).tag(Optional(program.id))
                        }
                    }
                }
                DatePicker(isChinese ? "加入日期" : "Joined date",
                           selection: $enrollmentDate,
                           displayedComponents: .date)
            } header: {
                Text(isChinese ? "团体注册" : "Group enrollment")
            } footer: {
                Text(isChinese
                     ? "团体训练由公司收费。这里只统计自加入日期起出席与应计课时的对照。"
                     : "Group sessions are billed by the company. We only count attendance from the joined date for cross-checking.")
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
        if let existing, existing.kind == .privateBundle, !existing.bundleSessionIds.isEmpty {
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

    private func save() {
        let nextNumber = (dataManager.contracts.filter { $0.studentId == studentId }
                            .map(\.contractNumber).max() ?? 0) + 1
        let contractNumber = existing?.contractNumber ?? nextNumber

        var purchase: Date? = nil
        var size = 0
        var price = pricePerSession
        var pid: UUID? = nil

        switch kind {
        case .privatePayPerSession:
            break
        case .privateBundle:
            purchase = bundlePurchaseDate
            size = bundleSize
        case .group:
            price = 0
            pid = programId
        }

        let contract = Contract(
            id: existing?.id ?? UUID(),
            studentId: studentId,
            contractNumber: contractNumber,
            kind: kind,
            enrollmentDate: enrollmentDate,
            pricePerSession: price,
            bundleSize: size,
            bundlePurchaseDate: purchase,
            bundleSessionIds: existing?.bundleSessionIds ?? [],
            payments: kind == .group ? [] : payments,
            travelFeeAmount: kind == .group ? 0 : travelFeeAmount,
            travelFeeBasis: travelFeeBasis,
            programId: pid,
            notes: notes.isEmpty ? nil : notes,
            createdByCoachId: existing?.createdByCoachId ?? dataManager.loggedInCoachId,
            manualStatus: existing?.manualStatus,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )

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
