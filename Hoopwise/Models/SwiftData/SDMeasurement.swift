import Foundation
import SwiftData

@Model
final class SDMeasurement {
    @Attribute(.unique) var id: UUID
    var studentId: UUID
    var typeRaw: String
    var value: Double
    var sessionId: UUID?
    var notes: String?
    var recordedAt: Date
    var recordedBy: String?
    
    // Relationship
    var student: SDStudent?
    
    init(
        id: UUID = UUID(),
        studentId: UUID,
        type: MeasurementType,
        value: Double,
        sessionId: UUID? = nil,
        notes: String? = nil,
        recordedAt: Date = Date(),
        recordedBy: String? = nil
    ) {
        self.id = id
        self.studentId = studentId
        self.typeRaw = type.rawValue
        self.value = value
        self.sessionId = sessionId
        self.notes = notes
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
    }
    
    // Computed properties
    var type: MeasurementType {
        get { MeasurementType(rawValue: typeRaw) ?? .height }
        set { typeRaw = newValue.rawValue }
    }
    
    var formattedValue: String {
        switch type {
        case .height, .wingspan, .standingReach, .verticalJump:
            return "\(Int(value)) \(type.unit)"
        case .weight:
            return String(format: "%.1f \(type.unit)", value)
        case .sprintTime, .shuttleRun, .laneAgility:
            return String(format: "%.2f \(type.unit)", value)
        case .shootingPercent, .freeThrowPercent, .threePointPercent:
            return "\(Int(value))\(type.unit)"
        }
    }
    
    /// Convert to legacy PlayerMeasurement struct
    func toStruct() -> PlayerMeasurement {
        PlayerMeasurement(
            id: id,
            studentId: studentId,
            type: type,
            value: value,
            sessionId: sessionId,
            notes: notes,
            recordedAt: recordedAt,
            recordedBy: recordedBy
        )
    }
    
    /// Create from legacy PlayerMeasurement struct
    static func from(_ measurement: PlayerMeasurement) -> SDMeasurement {
        SDMeasurement(
            id: measurement.id,
            studentId: measurement.studentId,
            type: measurement.type,
            value: measurement.value,
            sessionId: measurement.sessionId,
            notes: measurement.notes,
            recordedAt: measurement.recordedAt,
            recordedBy: measurement.recordedBy
        )
    }
}
