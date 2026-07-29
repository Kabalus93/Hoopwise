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
        self.programId = programId
        self.notes = notes
        self.createdByCoachId = createdByCoachId
        self.manualStatusRaw = manualStatus?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        defer { self.bundleSessionIds = bundleSessionIds }
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
            programId: contract.programId,
            notes: contract.notes,
            createdByCoachId: contract.createdByCoachId,
            manualStatus: contract.manualStatus,
            createdAt: contract.createdAt,
            updatedAt: contract.updatedAt
        )
    }
}
