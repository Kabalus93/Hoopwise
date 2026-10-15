import Foundation

enum Handedness: String, Codable, CaseIterable {
    case right, left, ambidextrous
    var displayName: String { rawValue.capitalized }
    var shortName: String {
        switch self {
        case .right: return "R"
        case .left: return "L"
        case .ambidextrous: return "Both"
        }
    }
}

struct ParentInfo: Codable, Hashable, Sendable {
    var name: String
    var relationship: String
    var phone: String
    var email: String?
    var wechatId: String?
    
    init(name: String = "", relationship: String = "Parent", phone: String = "",
         email: String? = nil, wechatId: String? = nil) {
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.email = email
        self.wechatId = wechatId
    }
    
    // Custom decoder to handle missing keys with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? "Parent"
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        wechatId = try container.decodeIfPresent(String.self, forKey: .wechatId)
    }
}

enum ContractStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case active = "Active"
    case completed = "Completed"
    case expired = "Expired"
    case cancelled = "Cancelled"
    
    var color: String {
        switch self {
        case .pending: return "orange"
        case .active: return "green"
        case .completed: return "blue"
        case .expired: return "red"
        case .cancelled: return "gray"
        }
    }
    
    var localizedName: String {
        return rawValue
    }
    
    var localizedNameChinese: String {
        switch self {
        case .pending: return "待定"
        case .active: return "活跃"
        case .completed: return "已完成"
        case .expired: return "已过期"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - Contract Kind (the only enum that matters now)
/// Three contract kinds, each with distinct billing semantics:
/// - `.privatePayPerSession`: revenue counted per attended private session.
/// - `.privateBundle`: prepaid bundle, revenue counted in the purchase month.
/// - `.group`: company-billed; the coach only counts attendance, no revenue.
///
/// Decoder accepts the legacy `ContractType` raw values (`"Pay As You Go"`,
/// `"1x/week - 6 months"`, etc.) and maps them — PAYG → privatePayPerSession,
/// recurring weekly → group.
enum ContractKind: String, Codable, CaseIterable {
    case privatePayPerSession = "privatePayPerSession"
    case privateBundle        = "privateBundle"
    case group                = "group"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "privatePayPerSession": self = .privatePayPerSession
        case "privateBundle":        self = .privateBundle
        case "group":                self = .group
        // Legacy migration:
        case "Pay As You Go":        self = .privatePayPerSession
        case "1x/week - 6 months",
             "1x/week - 12 months",
             "2x/week - 6 months",
             "2x/week - 12 months":  self = .group
        default:                     self = .privatePayPerSession
        }
    }

    var isPrivate: Bool { self != .group }
    var isBundle: Bool { self == .privateBundle }

    var displayName: String {
        switch self {
        case .privatePayPerSession: return "Private — pay per session"
        case .privateBundle:        return "Private — bundle"
        case .group:                return "Group enrollment"
        }
    }

    var displayNameChinese: String {
        switch self {
        case .privatePayPerSession: return "私教 · 按次付费"
        case .privateBundle:        return "私教 · 套餐"
        case .group:                return "团体注册"
        }
    }

    var shortName: String {
        switch self {
        case .privatePayPerSession: return "PAYG"
        case .privateBundle:        return "Bundle"
        case .group:                return "Group"
        }
    }

    var icon: String {
        switch self {
        case .privatePayPerSession: return "person.fill.questionmark"
        case .privateBundle:        return "shippingbox.fill"
        case .group:                return "person.3.fill"
        }
    }

    var description: String {
        switch self {
        case .privatePayPerSession: return "Charged each time the student attends a private session."
        case .privateBundle:        return "Prepaid pack. Revenue counted in the month of purchase."
        case .group:                return "Group sessions are billed by the company. Track attendance only."
        }
    }
}

// MARK: - Legacy type alias
/// Old code references `ContractType` everywhere. Keep the name as an alias so
/// the 16 UI files compile while the kind layer is new.
typealias ContractType = ContractKind

extension ContractKind {
    /// Legacy field. Pay-per-session is the closest analogue to PAYG.
    var isPayAsYouGo: Bool { self == .privatePayPerSession }
    /// Legacy. Group "contracts" are open-ended; private bundles get redeemed.
    var sessionsPerWeek: Int? { nil }
    var durationMonths: Int? { nil }
    var totalSessions: Int? { nil }
}

// MARK: - Weekly Attendance Record (Legacy - kept for backward compatibility)
struct WeeklyAttendanceRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var weekStartDate: Date
    var expectedSessions: Int
    var attendedSessions: Int
    var sessionDates: [Date]
    var notes: String?
    
    init(id: UUID = UUID(), weekStartDate: Date, expectedSessions: Int = 1, 
         attendedSessions: Int = 0, sessionDates: [Date] = [], notes: String? = nil) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.expectedSessions = expectedSessions
        self.attendedSessions = attendedSessions
        self.sessionDates = sessionDates
        self.notes = notes
    }
    
    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }
    
    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStartDate)) - \(formatter.string(from: weekEndDate))"
    }
    
    var isComplete: Bool { attendedSessions >= expectedSessions }
    var missedSessions: Int { max(0, expectedSessions - attendedSessions) }
}

// MARK: - Attended Session Record
/// Links a contract to a specific session that was attended
struct AttendedSessionRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var sessionEventId: UUID
    var sessionDate: Date
    var sessionTitle: String
    var programName: String?
    
    init(id: UUID = UUID(), sessionEventId: UUID, sessionDate: Date, 
         sessionTitle: String, programName: String? = nil) {
        self.id = id
        self.sessionEventId = sessionEventId
        self.sessionDate = sessionDate
        self.sessionTitle = sessionTitle
        self.programName = programName
    }
}

// MARK: - Contract
/// Three-kind contract model. See `ContractKind` for the rules.
/// Legacy fields exist only as Codable migration sinks and computed shims so
/// older UI keeps compiling while it's migrated kind by kind.
/// A single payment against a contract. Contracts hold a ledger of these
/// rather than one `amountPaid` figure so partial and installment payments
/// are representable.
///
/// Session money only. Travel money is tracked separately on the contract via
/// `travelFeeAmount` — mixing the two corrupts the paid-sessions arithmetic,
/// because a lump travel stipend paid alongside a bundle prepayment would
/// otherwise read as extra sessions purchased.
struct ContractPayment: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var amount: Double
    var method: String?
    var note: String?

    init(id: UUID = UUID(), date: Date = Date(), amount: Double,
         method: String? = nil, note: String? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.method = method
        self.note = note
    }
}

/// What a media consent covers. Clause 8 of the training agreement requires
/// the two purposes to be authorised separately.
enum MediaConsentPurpose: String, Codable, CaseIterable, Hashable {
    /// Coaching analysis, used only between coach and client.
    case coachingAnalysis
    /// Public publication — social media, instructional content.
    case publicPublication

    var displayName: String {
        switch self {
        case .coachingAnalysis:   return "Coaching analysis"
        case .publicPublication:  return "Public publication"
        }
    }

    var displayNameChinese: String {
        switch self {
        case .coachingAnalysis:   return "教学分析"
        case .publicPublication:  return "公开发布"
        }
    }
}

/// One consent decision, at a point in time.
///
/// A ledger rather than a pair of booleans. Clause 8 grants the client the
/// right to withdraw either consent in writing at any time, and a bare Bool
/// loses both the date and the fact that a withdrawal happened — which is
/// precisely the evidence that matters if a guardian later objects to a
/// published clip. Entries are append-only in practice; the current state is
/// the most recent entry per purpose.
struct MediaConsentEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var purpose: MediaConsentPurpose
    var granted: Bool
    var date: Date
    var note: String?

    init(id: UUID = UUID(),
         purpose: MediaConsentPurpose,
         granted: Bool,
         date: Date = Date(),
         note: String? = nil) {
        self.id = id
        self.purpose = purpose
        self.granted = granted
        self.date = date
        self.note = note
    }
}

/// How a contract's travel fee is charged.
enum TravelFeeBasis: String, Codable, CaseIterable {
    /// One lump sum for the whole contract — e.g. a travel stipend paid
    /// alongside a bundle prepayment.
    case perContract
    /// Charged again for each session, for venues with a real per-trip cost.
    case perSession

    var displayName: String {
        switch self {
        case .perContract: return "Per contract"
        case .perSession:  return "Per session"
        }
    }

    func localizedDisplayName(isChinese: Bool) -> String {
        switch self {
        case .perContract: return isChinese ? "每份合同" : "Per contract"
        case .perSession:  return isChinese ? "每节课"   : "Per session"
        }
    }
}

struct Contract: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var contractNumber: Int

    // MARK: - Canonical fields
    /// The kind of contract. Persisted under `contractType` for back-compat
    /// with old payloads.
    var kind: ContractKind
    var enrollmentDate: Date

    /// Per-session price, in the coach's currency.
    /// - `.privatePayPerSession`: charged per attended session.
    /// - `.privateBundle`: bundle price = `pricePerSession × bundleSize`.
    /// - `.group`: ignored.
    var pricePerSession: Double

    /// `.privateBundle` only — defaults to 10. 0 for other kinds.
    var bundleSize: Int

    /// `.privateBundle` only — month containing this date counts the bundle
    /// purchase revenue. Defaults to enrollmentDate when nil.
    var bundlePurchaseDate: Date?

    /// `.privateBundle` only — sessions redeemed against this bundle, FIFO.
    var bundleSessionIds: [UUID]

    /// `.group` only — the program this enrollment is for. Required for
    /// attendance counting. Nil for private kinds (any private session counts).
    var programId: UUID?

    /// Session payments, oldest first. Sum is `amountPaid`. Excludes travel.
    var payments: [ContractPayment]

    /// Travel fee / stipend for this contract, in the coach's currency.
    /// Interpreted per `travelFeeBasis`. Deliberately excluded from
    /// `amountPaid` and from session revenue.
    var travelFeeAmount: Double

    var travelFeeBasis: TravelFeeBasis

    /// Media consent decisions, oldest first. Current state per purpose is the
    /// most recent entry — see `consentState(for:)`.
    var consents: [MediaConsentEntry]

    /// Length of one session in minutes, for the agreement's clause 2.
    var sessionMinutes: Int

    /// How long the agreement remains valid, for clause 3. Zero means unset and
    /// prints as a fill-in rule rather than a fabricated term.
    var validityMonths: Int

    // MARK: - Handover facts (Phase 2.9)
    //
    // These three were compile-time shims that returned a constant and threw
    // their setters away, while SalesView offered a toggle for each and called
    // save. The coach ticked "Jersey Given", the row said it saved, and the
    // next launch showed it untouched.
    //
    // The DATE is stored and the Bool derives, as with the consent ledger: a
    // Bool loses when it happened, and the row already wanted to print
    // "Given on <date>".
    var signedDate: Date?
    var jerseyGivenDate: Date?
    var ballGivenDate: Date?

    var notes: String?
    var createdByCoachId: UUID?
    var manualStatus: ContractStatus?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Init
    init(
        id: UUID = UUID(),
        studentId: UUID,
        contractNumber: Int = 1,
        kind: ContractKind = .privatePayPerSession,
        enrollmentDate: Date = Date(),
        pricePerSession: Double = 0,
        bundleSize: Int = 0,
        bundlePurchaseDate: Date? = nil,
        bundleSessionIds: [UUID] = [],
        payments: [ContractPayment] = [],
        travelFeeAmount: Double = 0,
        travelFeeBasis: TravelFeeBasis = .perContract,
        consents: [MediaConsentEntry] = [],
        sessionMinutes: Int = 90,
        validityMonths: Int = 0,
        programId: UUID? = nil,
        signedDate: Date? = nil,
        jerseyGivenDate: Date? = nil,
        ballGivenDate: Date? = nil,
        notes: String? = nil,
        createdByCoachId: UUID? = nil,
        manualStatus: ContractStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.contractNumber = contractNumber
        self.kind = kind
        self.enrollmentDate = enrollmentDate
        self.pricePerSession = pricePerSession
        self.bundleSize = bundleSize
        self.bundlePurchaseDate = bundlePurchaseDate
        self.bundleSessionIds = bundleSessionIds
        self.payments = payments
        self.travelFeeAmount = travelFeeAmount
        self.travelFeeBasis = travelFeeBasis
        self.consents = consents
        self.sessionMinutes = sessionMinutes
        self.validityMonths = validityMonths
        self.programId = programId
        self.signedDate = signedDate
        self.jerseyGivenDate = jerseyGivenDate
        self.ballGivenDate = ballGivenDate
        self.notes = notes
        self.createdByCoachId = createdByCoachId
        self.manualStatus = manualStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable migration
    /// Decodes both the new shape and the legacy shape (which had
    /// `contractType`, `pricePerSession`, `totalAmount`, etc.).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        studentId = try c.decode(UUID.self, forKey: .studentId)
        contractNumber = try c.decodeIfPresent(Int.self, forKey: .contractNumber) ?? 1
        kind = (try? c.decodeIfPresent(ContractKind.self, forKey: .kind))
            ?? (try? c.decodeIfPresent(ContractKind.self, forKey: .contractType))
            ?? .privatePayPerSession
        enrollmentDate = try c.decodeIfPresent(Date.self, forKey: .enrollmentDate)
            ?? c.decodeIfPresent(Date.self, forKey: .startDate)
            ?? Date()
        pricePerSession = try c.decodeIfPresent(Double.self, forKey: .pricePerSession) ?? 0
        bundleSize = try c.decodeIfPresent(Int.self, forKey: .bundleSize) ?? (kind == .privateBundle ? 10 : 0)
        bundlePurchaseDate = try c.decodeIfPresent(Date.self, forKey: .bundlePurchaseDate)
        bundleSessionIds = try c.decodeIfPresent([UUID].self, forKey: .bundleSessionIds)
            ?? c.decodeIfPresent([UUID].self, forKey: .attendedSessionIds)
            ?? []
        programId = try c.decodeIfPresent(UUID.self, forKey: .programId)
            ?? (try c.decodeIfPresent([UUID].self, forKey: .programAssignments))?.first
        payments = try c.decodeIfPresent([ContractPayment].self, forKey: .payments) ?? []
        travelFeeAmount = try c.decodeIfPresent(Double.self, forKey: .travelFeeAmount) ?? 0
        travelFeeBasis = try c.decodeIfPresent(TravelFeeBasis.self, forKey: .travelFeeBasis) ?? .perContract
        consents = try c.decodeIfPresent([MediaConsentEntry].self, forKey: .consents) ?? []
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? 90
        validityMonths = try c.decodeIfPresent(Int.self, forKey: .validityMonths) ?? 0
        signedDate = try c.decodeIfPresent(Date.self, forKey: .signedDate)
        jerseyGivenDate = try c.decodeIfPresent(Date.self, forKey: .jerseyGivenDate)
        ballGivenDate = try c.decodeIfPresent(Date.self, forKey: .ballGivenDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdByCoachId = try c.decodeIfPresent(UUID.self, forKey: .createdByCoachId)
        manualStatus = try c.decodeIfPresent(ContractStatus.self, forKey: .manualStatus)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, studentId, contractNumber, kind, enrollmentDate, pricePerSession
        case bundleSize, bundlePurchaseDate, bundleSessionIds
        case payments, travelFeeAmount, travelFeeBasis
        case consents, sessionMinutes, validityMonths
        case programId, notes, createdByCoachId, manualStatus, createdAt, updatedAt
        case signedDate, jerseyGivenDate, ballGivenDate
        // Legacy
        case contractType, startDate, attendedSessionIds, programAssignments
    }

    /// Encode only the canonical shape. Legacy keys are dropped on write —
    /// the next decode of any older payload still works because the decoder
    /// understands the legacy keys.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(studentId, forKey: .studentId)
        try c.encode(contractNumber, forKey: .contractNumber)
        try c.encode(kind, forKey: .kind)
        try c.encode(enrollmentDate, forKey: .enrollmentDate)
        try c.encode(pricePerSession, forKey: .pricePerSession)
        try c.encode(bundleSize, forKey: .bundleSize)
        try c.encodeIfPresent(bundlePurchaseDate, forKey: .bundlePurchaseDate)
        try c.encode(bundleSessionIds, forKey: .bundleSessionIds)
        try c.encode(payments, forKey: .payments)
        try c.encode(travelFeeAmount, forKey: .travelFeeAmount)
        try c.encode(travelFeeBasis, forKey: .travelFeeBasis)
        try c.encode(consents, forKey: .consents)
        try c.encode(sessionMinutes, forKey: .sessionMinutes)
        try c.encode(validityMonths, forKey: .validityMonths)
        try c.encodeIfPresent(programId, forKey: .programId)
        try c.encodeIfPresent(signedDate, forKey: .signedDate)
        try c.encodeIfPresent(jerseyGivenDate, forKey: .jerseyGivenDate)
        try c.encodeIfPresent(ballGivenDate, forKey: .ballGivenDate)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(createdByCoachId, forKey: .createdByCoachId)
        try c.encodeIfPresent(manualStatus, forKey: .manualStatus)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Derived

    /// Total bundle price for `.privateBundle`.
    var bundleAmount: Double {
        kind.isBundle ? pricePerSession * Double(bundleSize) : 0
    }

    /// A prepaid SESSION BALANCE that attendance deducts from: a private
    /// bundle, or (October 2026) a group contract carrying a prepaid count —
    /// how academies sell group classes ("剩余课时"). A group contract with
    /// `bundleSize == 0` is an enrollment with no balance, as before.
    /// Months-based balances are converted to sessions at 4 a month (one
    /// class a week) when they are entered.
    var hasSessionBalance: Bool {
        kind == .privateBundle || (kind == .group && bundleSize > 0)
    }

    /// Sessions left on a balance, or nil when the contract has none.
    var bundleRedemptionsRemaining: Int? {
        guard hasSessionBalance else { return nil }
        return max(0, bundleSize - bundleSessionIds.count)
    }

    /// The date used for revenue attribution of a bundle purchase.
    var effectiveBundlePurchaseDate: Date {
        bundlePurchaseDate ?? enrollmentDate
    }

    // MARK: - Money
    //
    // Session money and travel money are kept strictly apart. `amountPaid`,
    // `sessionAmountDue` and `sessionAmountOwed` are session-only; travel is
    // reported by `travelFeeTotal(sessionCount:)`. Folding travel into either
    // side would make a lump stipend read as extra sessions purchased.

    /// Sum of the payment ledger. Session money only.
    var amountPaid: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    /// What the sessions themselves cost.
    ///
    /// - `.privateBundle`: the whole bundle is owed on purchase.
    /// - `.privatePayPerSession`: depends on sessions attended, which lives
    ///   outside this struct — pass a count to `sessionAmountDue(sessionCount:)`.
    /// - `.group`: priced by the program, not per session.
    var sessionAmountDue: Double {
        kind.isBundle ? bundleAmount : 0
    }

    /// Session cost for a known number of attended sessions. Bundles ignore
    /// the count — the bundle is owed in full regardless of redemptions.
    func sessionAmountDue(sessionCount: Int) -> Double {
        switch kind {
        case .privateBundle:        return bundleAmount
        case .privatePayPerSession: return pricePerSession * Double(max(0, sessionCount))
        case .group:                return 0
        }
    }

    /// Outstanding session money. Negative means paid ahead / credit.
    var sessionAmountOwed: Double {
        sessionAmountDue - amountPaid
    }

    func sessionAmountOwed(sessionCount: Int) -> Double {
        sessionAmountDue(sessionCount: sessionCount) - amountPaid
    }

    /// Travel money for this contract. `.perContract` ignores the count;
    /// `.perSession` multiplies by it. For bundles, `bundleSize` is the
    /// natural count to pass.
    func travelFeeTotal(sessionCount: Int) -> Double {
        switch travelFeeBasis {
        case .perContract: return travelFeeAmount
        case .perSession:  return travelFeeAmount * Double(max(0, sessionCount))
        }
    }

    /// Travel total using the contract's own session basis where one exists.
    /// Bundles use `bundleSize`; other kinds have no intrinsic count, so a
    /// `.perSession` fee reports as the single-session rate.
    var travelFeeTotalForContract: Double {
        travelFeeTotal(sessionCount: kind.isBundle ? bundleSize : 1)
    }

    var hasTravelFee: Bool { travelFeeAmount != 0 }

    // MARK: - Media Consent

    /// Current consent for a purpose: the most recent entry, or nil when the
    /// client has never been asked.
    ///
    /// Nil is meaningfully different from false. Unasked prints empty boxes on
    /// a fresh agreement; declined must block publication.
    func consentState(for purpose: MediaConsentPurpose) -> Bool? {
        consents
            .filter { $0.purpose == purpose }
            .max(by: { $0.date < $1.date })?
            .granted
    }

    /// Full history for a purpose, oldest first — including withdrawals.
    func consentHistory(for purpose: MediaConsentPurpose) -> [MediaConsentEntry] {
        consents.filter { $0.purpose == purpose }.sorted { $0.date < $1.date }
    }

    /// True only when publication was explicitly granted. Unasked and declined
    /// both return false, so the safe answer is the default.
    var allowsPublicPublication: Bool {
        consentState(for: .publicPublication) == true
    }

    /// Records a decision. Append-only: withdrawing consent adds an entry
    /// rather than editing or removing the grant, so the history survives.
    mutating func recordConsent(_ purpose: MediaConsentPurpose,
                                granted: Bool,
                                date: Date = Date(),
                                note: String? = nil) {
        consents.append(MediaConsentEntry(purpose: purpose, granted: granted,
                                          date: date, note: note))
        updatedAt = Date()
    }

    var contractLabel: String {
        let suffix: String
        switch contractNumber {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(contractNumber)\(suffix) Contract"
    }

    func localizedContractLabel(isChinese: Bool) -> String {
        isChinese ? "第\(contractNumber)份合同" : contractLabel
    }

    var status: ContractStatus {
        if let manual = manualStatus { return manual }
        if kind == .privateBundle, bundleRedemptionsRemaining == 0 { return .completed }
        return .active
    }

    // MARK: - Legacy compile-time shims (read-only)
    /// These return derived/safe values so the existing UI keeps building
    /// without changes. They will be removed view by view as screens are
    /// migrated to read `kind` / `pricePerSession` / `bundleSize` directly.
    var contractType: ContractKind {
        get { kind }
        set { kind = newValue }
    }
    var startDate: Date? {
        get { enrollmentDate }
        set { if let v = newValue { enrollmentDate = v } }
    }
    /// The DERIVED expiry — see `expiresOn`. This is not a revival of the dead
    /// `expiryDate` column, which stays dead: the value comes from
    /// validityMonths, so there is still exactly one source of truth. Leaving
    /// it nil while `isExpired` says "expired" would have put a contract on
    /// screen that is expired with no expiry date.
    var expiryDate: Date? { expiresOn }
    var totalSessions: Int { bundleSize }
    var attendedSessions: Int { bundleSessionIds.count }
    var attendedSessionIds: [UUID] {
        get { bundleSessionIds }
        set { bundleSessionIds = newValue }
    }
    var weeklyAttendance: [WeeklyAttendanceRecord] {
        get { [] }
        set { _ = newValue }
    }
    var totalAmount: Double { sessionAmountDue }
    // `amountPaid` used to assume every bundle was paid in full up front, and
    // `outstandingBalance`/`isFullyPaid` were hardcoded to 0 and true. The UI
    // rendered those fabricated figures as though they were real. They now read
    // from the payment ledger. Travel is excluded — see the money section.
    var outstandingBalance: Double { max(0, sessionAmountOwed) }
    var isFullyPaid: Bool { sessionAmountOwed <= 0 }
    /// Derived from `signedDate`. Setting it stamps or clears that date —
    /// it never touches `enrollmentDate`, which an earlier setter did: it
    /// overwrote the enrollment date with today and persisted it, and because
    /// bundle revenue is attributed via `effectiveBundlePurchaseDate` (which
    /// falls back to `enrollmentDate`), ticking "Contract Signed" silently
    /// moved revenue between months.
    var isSigned: Bool {
        get { signedDate != nil }
        set { signedDate = newValue ? (signedDate ?? Date()) : nil }
    }
    var jerseyGiven: Bool {
        get { jerseyGivenDate != nil }
        set { jerseyGivenDate = newValue ? (jerseyGivenDate ?? Date()) : nil }
    }
    var ballGiven: Bool {
        get { ballGivenDate != nil }
        set { ballGivenDate = newValue ? (ballGivenDate ?? Date()) : nil }
    }
    /// Still not stored, and now honest about it: nothing ever wrote a jersey
    /// number or size to a CONTRACT (Player.jerseyNumber is the real one), so
    /// there is no value to recover. The two read sites are guarded on nil.
    var jerseyNumber: Int? { nil }
    var jerseySize: String? { nil }
    var programAssignments: [UUID] {
        get { programId.map { [$0] } ?? [] }
        set { programId = newValue.first }
    }
    var sessionCount: Int { bundleSessionIds.count }
    var calculatedAttendedSessions: Int { sessionCount }
    var isPayAsYouGo: Bool { kind == .privatePayPerSession }
    var sessionsPerWeek: Int? { nil }
    var remainingSessions: Int? { bundleRedemptionsRemaining }
    var remainingSessionsDisplay: Int { bundleRedemptionsRemaining ?? 0 }
    var progressPercentage: Double {
        guard kind.isBundle, bundleSize > 0 else { return 0 }
        return Double(bundleSessionIds.count) / Double(bundleSize)
    }
    /// A bundle's agreement runs for `validityMonths` from the day it was
    /// bought (clause 3). Zero means the coach never set a term, and a term
    /// nobody agreed cannot expire.
    ///
    /// Derived, not stored: the dead `expiryDate` column stays dead, because a
    /// second source of truth drifts from the first.
    ///
    /// This used to return `false` unconditionally, behind a red warning in
    /// four screens that could therefore never fire.
    var expiresOn: Date? {
        guard validityMonths > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: validityMonths,
                                     to: effectiveBundlePurchaseDate)
    }

    func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresOn else { return false }
        return expiresOn < now
    }

    var isExpired: Bool { isExpired() }
    var typeLabel: String { kind.shortName }
    var typeLabelChinese: String { kind.displayNameChinese }

    mutating func recordAttendance(sessionEventId: UUID) {
        guard kind.isBundle, !bundleSessionIds.contains(sessionEventId) else { return }
        bundleSessionIds.append(sessionEventId)
        updatedAt = Date()
    }

    mutating func removeAttendance(sessionEventId: UUID) {
        bundleSessionIds.removeAll { $0 == sessionEventId }
        updatedAt = Date()
    }

    mutating func generateWeeklyRecords() { /* no-op */ }

    static let sample = Contract(
        studentId: UUID(),
        kind: .privateBundle,
        pricePerSession: 100,
        bundleSize: 10
    )
}

// Legacy support - maps to current contract
struct ContractInfo: Codable, Hashable, Sendable {
    var totalSessions: Int
    var completedSessions: Int
    var startDate: Date?
    var expiryDate: Date?
    var pricePerSession: Double
    var totalPaid: Double
    var notes: String?
    
    init(totalSessions: Int = 0, completedSessions: Int = 0, startDate: Date? = nil,
         expiryDate: Date? = nil, pricePerSession: Double = 0, totalPaid: Double = 0, notes: String? = nil) {
        self.totalSessions = totalSessions
        self.completedSessions = completedSessions
        self.startDate = startDate
        self.expiryDate = expiryDate
        self.pricePerSession = pricePerSession
        self.totalPaid = totalPaid
        self.notes = notes
    }
    
    // Custom decoder to handle missing keys with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        pricePerSession = try container.decodeIfPresent(Double.self, forKey: .pricePerSession) ?? 0
        totalPaid = try container.decodeIfPresent(Double.self, forKey: .totalPaid) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    var remainingSessions: Int { max(0, totalSessions - completedSessions) }
    var progressPercentage: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }
    var isExpired: Bool {
        guard let expiryDate else { return false }
        return Date() > expiryDate
    }
}

/// 6-axis skills evaluation matching the performance radar diagram
/// Each skill is rated 1-10 by the coach. These blend with game stats for final radar values.
struct SkillsEvaluation: Codable, Hashable, Sendable {
    // 6 skills matching radar axes (1-10 scale)
    var scoring: Int        // Shooting ability, shot selection, finishing
    var playmaking: Int     // Passing, vision, basketball IQ
    var rebounding: Int     // Boxing out, positioning, effort on boards
    var defense: Int        // On-ball defense, help defense, communication
    var athleticism: Int    // Speed, agility, vertical, endurance
    var intangibles: Int    // Teamwork, coachability, attitude, hustle
    
    var lastEvaluatedDate: Date?
    var notes: String?
    
    // MARK: - Legacy properties (computed for backward compatibility)
    var shooting: Int { scoring }
    var ballHandling: Int { playmaking }
    var basketballIQ: Int { playmaking }
    var teamwork: Int { intangibles }
    var coachability: Int { intangibles }
    
    init(scoring: Int = 5, playmaking: Int = 5, rebounding: Int = 5, defense: Int = 5,
         athleticism: Int = 5, intangibles: Int = 5,
         lastEvaluatedDate: Date? = nil, notes: String? = nil) {
        self.scoring = scoring
        self.playmaking = playmaking
        self.rebounding = rebounding
        self.defense = defense
        self.athleticism = athleticism
        self.intangibles = intangibles
        self.lastEvaluatedDate = lastEvaluatedDate
        self.notes = notes
    }
    
    // Custom decoder to handle both old 7-skill and new 6-skill formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new 6-skill format first
        if let s = try container.decodeIfPresent(Int.self, forKey: .scoring) {
            scoring = s
            playmaking = try container.decodeIfPresent(Int.self, forKey: .playmaking) ?? 5
            rebounding = try container.decodeIfPresent(Int.self, forKey: .rebounding) ?? 5
            intangibles = try container.decodeIfPresent(Int.self, forKey: .intangibles) ?? 5
        } else {
            // Migrate from old 7-skill format
            let oldShooting = try container.decodeIfPresent(Int.self, forKey: .shooting) ?? 5
            let oldBallHandling = try container.decodeIfPresent(Int.self, forKey: .ballHandling) ?? 5
            let oldBasketballIQ = try container.decodeIfPresent(Int.self, forKey: .basketballIQ) ?? 5
            let oldTeamwork = try container.decodeIfPresent(Int.self, forKey: .teamwork) ?? 5
            let oldCoachability = try container.decodeIfPresent(Int.self, forKey: .coachability) ?? 5
            
            // Map old skills to new
            scoring = oldShooting
            playmaking = (oldBallHandling + oldBasketballIQ) / 2
            rebounding = 5  // No direct mapping, use default
            intangibles = (oldTeamwork + oldCoachability) / 2
        }
        
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 5
        athleticism = try container.decodeIfPresent(Int.self, forKey: .athleticism) ?? 5
        lastEvaluatedDate = try container.decodeIfPresent(Date.self, forKey: .lastEvaluatedDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    private enum CodingKeys: String, CodingKey {
        // New 6-skill keys only for encoding
        case scoring, playmaking, rebounding, defense, athleticism, intangibles
        // Legacy 7-skill keys for decoding migration
        case shooting, ballHandling, basketballIQ, teamwork, coachability
        // Common
        case lastEvaluatedDate, notes
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scoring, forKey: .scoring)
        try container.encode(playmaking, forKey: .playmaking)
        try container.encode(rebounding, forKey: .rebounding)
        try container.encode(defense, forKey: .defense)
        try container.encode(athleticism, forKey: .athleticism)
        try container.encode(intangibles, forKey: .intangibles)
        try container.encodeIfPresent(lastEvaluatedDate, forKey: .lastEvaluatedDate)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
    
    var overallRating: Double {
        Double(scoring + playmaking + rebounding + defense + athleticism + intangibles) / 6.0
    }
    
    /// Returns array of values in radar order (0-10 scale)
    var radarValues: [Double] {
        [Double(scoring), Double(playmaking), Double(rebounding), 
         Double(defense), Double(athleticism), Double(intangibles)]
    }
}

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var heightCm: Double?
    var weightKg: Double?
    var wingspanCm: Double?
    var handedness: Handedness
    var position: String?
    var jerseyNumber: Int?
    var parentInfo: ParentInfo
    var secondaryParentInfo: ParentInfo?
    var contractInfo: ContractInfo
    var skills: SkillsEvaluation
    var coachNotes: String?
    var medicalNotes: String?
    var profileImageData: Data?  // Profile picture stored as Data
    var headerImageURL: String?   // Background image URL for profile card
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), studentId: UUID, heightCm: Double? = nil, weightKg: Double? = nil,
         wingspanCm: Double? = nil, handedness: Handedness = .right, position: String? = nil,
         jerseyNumber: Int? = nil, parentInfo: ParentInfo = ParentInfo(),
         secondaryParentInfo: ParentInfo? = nil, contractInfo: ContractInfo = ContractInfo(),
         skills: SkillsEvaluation = SkillsEvaluation(), coachNotes: String? = nil,
         medicalNotes: String? = nil, profileImageData: Data? = nil,
         headerImageURL: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.studentId = studentId
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.wingspanCm = wingspanCm
        self.handedness = handedness
        self.position = position
        self.jerseyNumber = jerseyNumber
        self.parentInfo = parentInfo
        self.secondaryParentInfo = secondaryParentInfo
        self.contractInfo = contractInfo
        self.skills = skills
        self.coachNotes = coachNotes
        self.medicalNotes = medicalNotes
        self.profileImageData = profileImageData
        self.headerImageURL = headerImageURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var heightFormatted: String? {
        guard let h = heightCm else { return nil }
        return "\(Int(h / 30.48))'\(Int((h.truncatingRemainder(dividingBy: 30.48)) / 2.54))\" (\(Int(h))cm)"
    }
    
    var weightFormatted: String? {
        guard let w = weightKg else { return nil }
        return "\(Int(w * 2.205))lbs (\(Int(w))kg)"
    }
}
