import Foundation
import SwiftData

@Model
final class SDContract {
    @Attribute(.unique) var id: UUID
    var studentId: UUID
    var contractNumber: Int
    var contractTypeRaw: String?  // ContractType stored as string
    var enrollmentDate: Date?  // When student enrolled (simplified) - optional for migration
    var totalSessions: Int
    var attendedSessions: Int
    var attendedSessionIdsData: Data?  // [UUID] stored as JSON - session event IDs attended
    var weeklyAttendanceData: Data?  // WeeklyAttendanceRecord array stored as JSON (legacy)
    var startDate: Date?
    var expiryDate: Date?
    var pricePerSession: Double
    var totalAmount: Double
    var amountPaid: Double
    var isSigned: Bool
    var signedDate: Date?
    var jerseyGiven: Bool
    var jerseyGivenDate: Date?
    var ballGiven: Bool
    var ballGivenDate: Date?
    var jerseyNumber: Int?
    var jerseySize: String?
    var notes: String?
    var createdByCoachId: UUID?  // For access control
    var manualStatusRaw: String?  // Manual override for status (stored as string)
    var programAssignmentsData: Data?  // Program IDs for each session slot stored as JSON
    var historicalSessionsConsumed: Int = 0  // Sessions consumed before event-based tracking began
    var createdAt: Date
    var updatedAt: Date
    
    /// Get/set contractType as ContractType enum
    var contractType: ContractType? {
        get {
            guard let raw = contractTypeRaw else { return nil }
            return ContractType(rawValue: raw)
        }
        set {
            contractTypeRaw = newValue?.rawValue
        }
    }
    
    /// Get/set weeklyAttendance as array of WeeklyAttendanceRecord
    var weeklyAttendance: [WeeklyAttendanceRecord] {
        get {
            guard let data = weeklyAttendanceData else { return [] }
            return (try? JSONDecoder().decode([WeeklyAttendanceRecord].self, from: data)) ?? []
        }
        set {
            weeklyAttendanceData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Get/set manualStatus as ContractStatus enum
    var manualStatus: ContractStatus? {
        get {
            guard let raw = manualStatusRaw else { return nil }
            return ContractStatus(rawValue: raw)
        }
        set {
            manualStatusRaw = newValue?.rawValue
        }
    }
    
    /// Get/set programAssignments as array of UUIDs
    var programAssignments: [UUID] {
        get {
            guard let data = programAssignmentsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            programAssignmentsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Get/set attendedSessionIds as array of UUIDs
    var attendedSessionIds: [UUID] {
        get {
            guard let data = attendedSessionIdsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            attendedSessionIdsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Relationship
    var student: SDStudent?
    
    init(
        id: UUID = UUID(),
        studentId: UUID,
        contractNumber: Int = 1,
        contractTypeRaw: String? = nil,
        enrollmentDate: Date = Date(),
        totalSessions: Int = 0,
        attendedSessions: Int = 0,
        attendedSessionIdsData: Data? = nil,
        weeklyAttendanceData: Data? = nil,
        startDate: Date? = nil,
        expiryDate: Date? = nil,
        pricePerSession: Double = 0,
        totalAmount: Double = 0,
        amountPaid: Double = 0,
        isSigned: Bool = false,
        signedDate: Date? = nil,
        jerseyGiven: Bool = false,
        jerseyGivenDate: Date? = nil,
        ballGiven: Bool = false,
        ballGivenDate: Date? = nil,
        jerseyNumber: Int? = nil,
        jerseySize: String? = nil,
        notes: String? = nil,
        createdByCoachId: UUID? = nil,
        manualStatusRaw: String? = nil,
        programAssignmentsData: Data? = nil,
        historicalSessionsConsumed: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.contractNumber = contractNumber
        self.contractTypeRaw = contractTypeRaw
        self.enrollmentDate = enrollmentDate
        self.totalSessions = totalSessions
        self.attendedSessions = attendedSessions
        self.attendedSessionIdsData = attendedSessionIdsData
        self.weeklyAttendanceData = weeklyAttendanceData
        self.startDate = startDate
        self.expiryDate = expiryDate
        self.pricePerSession = pricePerSession
        self.totalAmount = totalAmount
        self.amountPaid = amountPaid
        self.isSigned = isSigned
        self.signedDate = signedDate
        self.jerseyGiven = jerseyGiven
        self.jerseyGivenDate = jerseyGivenDate
        self.ballGiven = ballGiven
        self.ballGivenDate = ballGivenDate
        self.jerseyNumber = jerseyNumber
        self.jerseySize = jerseySize
        self.notes = notes
        self.createdByCoachId = createdByCoachId
        self.manualStatusRaw = manualStatusRaw
        self.programAssignmentsData = programAssignmentsData
        self.historicalSessionsConsumed = historicalSessionsConsumed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    
    /// Whether this is a pay-as-you-go contract
    var isPayAsYouGo: Bool {
        contractType?.isPayAsYouGo ?? false
    }
    
    /// Remaining sessions (0 for PAYG since they have no fixed total)
    var remainingSessions: Int {
        guard !isPayAsYouGo else { return 0 }
        return max(0, totalSessions - attendedSessions)
    }
    
    var progressPercentage: Double {
        guard !isPayAsYouGo, totalSessions > 0 else { return 0 }
        return Double(attendedSessions) / Double(totalSessions)
    }
    
    var isExpired: Bool {
        guard !isPayAsYouGo, let expiryDate else { return false }
        return Date() > expiryDate
    }
    
    var isFullyPaid: Bool {
        if isPayAsYouGo { return outstandingBalance <= 0 }
        return amountPaid >= totalAmount
    }
    
    var outstandingBalance: Double {
        max(0, totalAmount - amountPaid)
    }
    
    var status: ContractStatus {
        // Use manual status if set
        if let manual = manualStatus { return manual }
        // Otherwise compute based on contract state
        if !isSigned { return .pending }
        // Pay-as-you-go is always active once signed
        if isPayAsYouGo { return .active }
        if isExpired { return .expired }
        if remainingSessions == 0 { return .completed }
        return .active
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
    
    /// Convert to Contract struct
    func toStruct() -> Contract {
        // Use backward-compatible initializer which derives enrollmentDate from startDate/createdAt
        var contract = Contract(
            id: id,
            studentId: studentId,
            contractNumber: contractNumber,
            contractType: contractType,
            totalSessions: totalSessions,
            attendedSessions: attendedSessions,
            weeklyAttendance: weeklyAttendance,
            startDate: enrollmentDate ?? startDate,
            expiryDate: expiryDate,
            pricePerSession: pricePerSession,
            totalAmount: totalAmount,
            amountPaid: amountPaid,
            isSigned: isSigned,
            signedDate: signedDate,
            jerseyGiven: jerseyGiven,
            jerseyGivenDate: jerseyGivenDate,
            ballGiven: ballGiven,
            ballGivenDate: ballGivenDate,
            jerseyNumber: jerseyNumber,
            jerseySize: jerseySize,
            notes: notes,
            createdByCoachId: createdByCoachId,
            manualStatus: manualStatus,
            programAssignments: programAssignments,
            historicalSessionsConsumed: historicalSessionsConsumed,
            attendedSessionIds: attendedSessionIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        // Override enrollmentDate if we have it stored
        if let stored = enrollmentDate {
            contract.enrollmentDate = stored
        }
        return contract
    }
    
    /// Create from Contract struct
    static func from(_ contract: Contract) -> SDContract {
        let sd = SDContract(
            id: contract.id,
            studentId: contract.studentId,
            contractNumber: contract.contractNumber,
            contractTypeRaw: contract.contractType.rawValue,
            enrollmentDate: contract.enrollmentDate,
            totalSessions: contract.totalSessions,
            attendedSessions: contract.attendedSessions,
            startDate: contract.startDate,
            expiryDate: contract.expiryDate,
            pricePerSession: contract.pricePerSession,
            totalAmount: contract.totalAmount,
            amountPaid: contract.amountPaid,
            isSigned: contract.isSigned,
            signedDate: contract.signedDate,
            jerseyGiven: contract.jerseyGiven,
            jerseyGivenDate: contract.jerseyGivenDate,
            ballGiven: contract.ballGiven,
            ballGivenDate: contract.ballGivenDate,
            jerseyNumber: contract.jerseyNumber,
            jerseySize: contract.jerseySize,
            notes: contract.notes,
            createdByCoachId: contract.createdByCoachId,
            manualStatusRaw: contract.manualStatus?.rawValue,
            createdAt: contract.createdAt,
            updatedAt: contract.updatedAt
        )
        sd.weeklyAttendance = contract.weeklyAttendance
        sd.programAssignments = contract.programAssignments
        sd.attendedSessionIds = contract.attendedSessionIds
        sd.historicalSessionsConsumed = contract.historicalSessionsConsumed
        return sd
    }
}
