import Foundation
import SwiftData

@Model
final class SDMicroCycle {
    var id: UUID = UUID()
    var programId: UUID = UUID()
    var phaseNumber: Int = 0
    var title: String = ""
    var focusRaw: [String] = []
    var durationWeeks: Int = 2
    var cycleDescription: String?
    var objectives: [String] = []
    var suggestedDrillIds: [UUID] = []
    var startDate: Date?
    var endDate: Date?
    var intensity: Int = 5
    var volume: Int = 5
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Relationship
    var program: SDProgram?

    @Relationship(deleteRule: .cascade, inverse: \SDSessionEvent.microCycle)
    var sessions: [SDSessionEvent]?

    init(
        id: UUID = UUID(),
        programId: UUID,
        phaseNumber: Int,
        title: String,
        focus: [TrainingFocus] = [],
        durationWeeks: Int = 2,
        description: String? = nil,
        objectives: [String] = [],
        suggestedDrillIds: [UUID] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        intensity: Int = 5,
        volume: Int = 5,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.programId = programId
        self.phaseNumber = phaseNumber
        self.title = title
        self.focusRaw = focus.map { $0.rawValue }
        self.durationWeeks = durationWeeks
        self.cycleDescription = description
        self.objectives = objectives
        self.suggestedDrillIds = suggestedDrillIds
        self.startDate = startDate
        self.endDate = endDate
        self.intensity = intensity
        self.volume = volume
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var focus: [TrainingFocus] {
        get { focusRaw.compactMap { TrainingFocus(rawValue: $0) } }
        set { focusRaw = newValue.map { $0.rawValue } }
    }
    
    var durationDays: Int {
        get { durationWeeks * 7 }
        set { durationWeeks = max(1, newValue / 7) }
    }
    
    var focusDisplayText: String { focus.map { $0.displayName }.joined(separator: ", ") }
    
    /// Convert to legacy MicroCycle struct
    func toStruct() -> MicroCycle {
        MicroCycle(
            id: id,
            programId: programId,
            phaseNumber: phaseNumber,
            title: title,
            focus: focus,
            durationWeeks: durationWeeks,
            description: cycleDescription,
            objectives: objectives,
            suggestedDrillIds: suggestedDrillIds,
            startDate: startDate,
            endDate: endDate,
            intensity: intensity,
            volume: volume,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from legacy MicroCycle struct
    static func from(_ cycle: MicroCycle) -> SDMicroCycle {
        SDMicroCycle(
            id: cycle.id,
            programId: cycle.programId,
            phaseNumber: cycle.phaseNumber,
            title: cycle.title,
            focus: cycle.focus,
            durationWeeks: cycle.durationWeeks,
            description: cycle.description,
            objectives: cycle.objectives,
            suggestedDrillIds: cycle.suggestedDrillIds,
            startDate: cycle.startDate,
            endDate: cycle.endDate,
            intensity: cycle.intensity,
            volume: cycle.volume,
            createdAt: cycle.createdAt,
            updatedAt: cycle.updatedAt
        )
    }
}
