import Foundation
import SwiftData

@Model
final class SDContract {
    // MARK: - Canonical
    var id: UUID = UUID()
    var studentId: UUID = UUID()
    var contractNumber: Int = 1
    /// Stored as the new `ContractKind.rawValue`. Old values like
    /// "Pay As You Go" are accepted by `ContractKind`'s decoder when reading
    /// JSON exports, but the column itself moves to the new vocabulary the
    /// next time a record is updated.
    var kindRaw: String = ContractKind.privatePayPerSession.rawValue
    var enrollmentDate: Date = Date()
    var pricePerSession: Double = 0
    var bundleSize: Int = 0
    var bundlePurchaseDate: Date?
    var bundleSessionIdsData: Data?
    /// JSON `[ContractPayment]`. Same idiom as `bundleSessionIdsData` — a
    /// ledger rather than a single `amountPaid` column, so partial and
    /// installment payments are representable without a second record type.
    var paymentsData: Data?
    /// Travel fee / stipend. Interpreted per `travelFeeBasisRaw`. Kept out of
    /// the payment ledger on purpose; see `Contract`'s money section.
    var travelFeeAmount: Double = 0
    var travelFeeBasisRaw: String = TravelFeeBasis.perContract.rawValue
    var programId: UUID?
    var notes: String?
    var createdByCoachId: UUID?
    var manualStatusRaw: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Legacy fields (kept so older DBs can be opened without migration)
    /// Old data may have stored a contract type string here. We migrate via
    /// `ContractKind.init(from:)` which understands the legacy raws.
    var contractTypeRaw: String?
    var startDate: Date?
    var expiryDate: Date?

    // Relationship
    var student: SDStudent?

    // MARK: - Bridges
    var kind: ContractKind {
        get { ContractKind(rawValue: kindRaw) ?? .privatePayPerSession }
        set { kindRaw = newValue.rawValue }
    }

    var manualStatus: ContractStatus? {
        get { manualStatusRaw.flatMap { ContractStatus(rawValue: $0) } }
        set { manualStatusRaw = newValue?.rawValue }
    }

    var bundleSessionIds: [UUID] {
        get {
            guard let data = bundleSessionIdsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            bundleSessionIdsData = try? JSONEncoder().encode(newValue)
        }
    }

    var payments: [ContractPayment] {
        get {
            guard let data = paymentsData else { return [] }
            return (try? JSONDecoder().decode([ContractPayment].self, from: data)) ?? []
        }
        set {
            paymentsData = try? JSONEncoder().encode(newValue)
        }
    }

    var travelFeeBasis: TravelFeeBasis {
        get { TravelFeeBasis(rawValue: travelFeeBasisRaw) ?? .perContract }
        set { travelFeeBasisRaw = newValue.rawValue }
    }

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
        programId: UUID? = nil,
        notes: String? = nil,
        createdByCoachId: UUID? = nil,
        manualStatus: ContractStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.contractNumber = contractNumber
        self.kindRaw = kind.rawValue
        self.enrollmentDate = enrollmentDate
        self.pricePerSession = pricePerSession
        self.bundleSize = bundleSize
        self.bundlePurchaseDate = bundlePurchaseDate
        self.travelFeeAmount = travelFeeAmount
        self.travelFeeBasisRaw = travelFeeBasis.rawValue
        self.programId = programId
        self.notes = notes
        self.createdByCoachId = createdByCoachId
        self.manualStatusRaw = manualStatus?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        defer {
            self.bundleSessionIds = bundleSessionIds
            self.payments = payments
        }
    }

    func toStruct() -> Contract {
        Contract(
            id: id,
            studentId: studentId,
            contractNumber: contractNumber,
            kind: kind,
            enrollmentDate: enrollmentDate,
            pricePerSession: pricePerSession,
            bundleSize: bundleSize,
            bundlePurchaseDate: bundlePurchaseDate,
            bundleSessionIds: bundleSessionIds,
            payments: payments,
            travelFeeAmount: travelFeeAmount,
            travelFeeBasis: travelFeeBasis,
            programId: programId,
            notes: notes,
            createdByCoachId: createdByCoachId,
            manualStatus: manualStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func from(_ contract: Contract) -> SDContract {
        SDContract(
            id: contract.id,
            studentId: contract.studentId,
            contractNumber: contract.contractNumber,
            kind: contract.kind,
            enrollmentDate: contract.enrollmentDate,
            pricePerSession: contract.pricePerSession,
            bundleSize: contract.bundleSize,
            bundlePurchaseDate: contract.bundlePurchaseDate,
            bundleSessionIds: contract.bundleSessionIds,
            payments: contract.payments,
            travelFeeAmount: contract.travelFeeAmount,
            travelFeeBasis: contract.travelFeeBasis,
            programId: contract.programId,
            notes: contract.notes,
            createdByCoachId: contract.createdByCoachId,
            manualStatus: contract.manualStatus,
            createdAt: contract.createdAt,
            updatedAt: contract.updatedAt
        )
    }
}
