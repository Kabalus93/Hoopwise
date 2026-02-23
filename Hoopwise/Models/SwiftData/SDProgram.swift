import Foundation
import SwiftData
import SwiftUI

@Model
final class SDProgram {
    @Attribute(.unique) var id: UUID
    var name: String
    var programTypeRaw: String = "Group Training"  // Default to group training
    var ageGroupRaw: String
    var durationWeeks: Int
    var programDescription: String?
    var objectives: [String]
    var enrolledStudentIds: [UUID]
    var coachId: UUID?  // Assigned coach from Organization
    var createdByCoachId: UUID?  // For access control
    var statusRaw: String
    var colorHex: String
    var mascotRaw: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var imageData: Data?  // Store program cover image
    var starsRaw: Int = 1  // Quality/tier rating (1-4 stars), default to 1 (Green)
    
    // Recurring session schedule
    var recurringDaysRaw: [Int] = [7]  // Days of the week (1=Sun, 7=Sat), default Saturday
    var defaultSessionTime: Date?  // Default start time for sessions
    var defaultSessionDurationMinutes: Int = 90  // Default duration in minutes
    
    // Skill targets for program athletes (stored as JSON)
    var skillTargetsData: Data?  // ProgramSkillTargets stored as JSON
    
    // Location
    var locationId: UUID?  // Reference to Location from Organization
    var locationName: String?  // Cached location name for display
    
    // Phase-less programs
    var usesPhases: Bool = true  // If false, sessions are created directly without phases
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \SDMicroCycle.program)
    var microCycles: [SDMicroCycle]?
    
    @Relationship(deleteRule: .cascade, inverse: \SDSessionEvent.program)
    var sessions: [SDSessionEvent]?
    
    /// Get/set skillTargets as ProgramSkillTargets struct
    var skillTargets: ProgramSkillTargets? {
        get {
            guard let data = skillTargetsData else { return nil }
            return try? JSONDecoder().decode(ProgramSkillTargets.self, from: data)
        }
        set {
            skillTargetsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        programType: ProgramType = .group,
        ageGroup: AgeGroup,
        durationWeeks: Int = 12,
        description: String? = nil,
        objectives: [String] = [],
        enrolledStudentIds: [UUID] = [],
        coachId: UUID? = nil,
        createdByCoachId: UUID? = nil,
        status: ProgramStatus = .draft,
        colorHex: String? = nil,
        mascot: ProgramMascot = .eagle,
        startDate: Date? = nil,
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imageData: Data? = nil,
        stars: ProgramStars = .one,
        recurringDays: [Weekday] = [.saturday],
        defaultSessionTime: Date? = nil,
        defaultSessionDurationMinutes: Int = 90,
        skillTargets: ProgramSkillTargets? = nil,
        locationId: UUID? = nil,
        locationName: String? = nil,
        usesPhases: Bool = true
    ) {
        self.id = id
        self.name = name
        self.programTypeRaw = programType.rawValue
        self.ageGroupRaw = ageGroup.rawValue
        self.durationWeeks = durationWeeks
        self.programDescription = description
        self.objectives = objectives
        self.enrolledStudentIds = enrolledStudentIds
        self.coachId = coachId
        self.createdByCoachId = createdByCoachId
        self.statusRaw = status.rawValue
        self.colorHex = colorHex ?? mascot.colorHex
        self.mascotRaw = mascot.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageData = imageData
        self.starsRaw = stars.rawValue
        self.recurringDaysRaw = recurringDays.map { $0.rawValue }
        self.defaultSessionTime = defaultSessionTime
        self.defaultSessionDurationMinutes = defaultSessionDurationMinutes
        self.skillTargets = skillTargets
        self.locationId = locationId
        self.locationName = locationName
        self.usesPhases = usesPhases
    }
    
    // Computed properties
    var programType: ProgramType {
        get { ProgramType(rawValue: programTypeRaw) ?? .group }
        set { programTypeRaw = newValue.rawValue }
    }
    
    var ageGroup: AgeGroup {
        get { AgeGroup(rawValue: ageGroupRaw) ?? .u12 }
        set { ageGroupRaw = newValue.rawValue }
    }
    
    var status: ProgramStatus {
        get { ProgramStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    
    var mascot: ProgramMascot {
        get { ProgramMascot(rawValue: mascotRaw) ?? .eagle }
        set { mascotRaw = newValue.rawValue }
    }
    
    var stars: ProgramStars {
        get { 
            // Ensure starsRaw has a valid value (1-4), default to 1 if invalid
            let validValue = (1...4).contains(starsRaw) ? starsRaw : 1
            return ProgramStars(rawValue: validValue) ?? .one 
        }
        set { starsRaw = newValue.rawValue }
    }
    
    var recurringDays: [Weekday] {
        get { recurringDaysRaw.compactMap { Weekday(rawValue: $0) } }
        set { recurringDaysRaw = newValue.map { $0.rawValue } }
    }
    
    var enrolledCount: Int { enrolledStudentIds.count }
    var isActive: Bool { status == .active }
    
    /// Full display name: Day Time Location (e.g., "Monday 6:30PM Yipeng")
    var displayName: String {
        var parts: [String] = []
        
        // Day of the week (use first recurring day)
        if let firstDay = recurringDays.first {
            parts.append(firstDay.displayName)
        }
        
        // Time
        if let time = defaultSessionTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            parts.append(formatter.string(from: time))
        }
        
        // Location
        if let location = locationName, !location.isEmpty {
            parts.append(location)
        }
        
        // Fallback to mascot + name if no schedule info
        if parts.isEmpty {
            return "\(mascot.displayName) - \(name)"
        }
        
        return parts.joined(separator: " ")
    }
    
    var shortName: String {
        mascot.displayName
    }
    
    /// Legacy display name with mascot
    var mascotDisplayName: String {
        "\(mascot.displayName) - \(name)"
    }
    
    var mascotColor: Color {
        mascot.color
    }
    
    var mascotIcon: String {
        mascot.icon
    }
    
    /// Convert to legacy Program struct
    func toStruct() -> Program {
        Program(
            id: id,
            name: name,
            programType: programType,
            ageGroup: ageGroup,
            durationWeeks: durationWeeks,
            description: programDescription,
            objectives: objectives,
            enrolledStudentIds: enrolledStudentIds,
            coachId: coachId,
            createdByCoachId: createdByCoachId,
            status: status,
            colorHex: colorHex,
            mascot: mascot,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imageData: imageData,
            stars: stars,
            recurringDays: recurringDays,
            defaultSessionTime: defaultSessionTime,
            defaultSessionDurationMinutes: defaultSessionDurationMinutes,
            skillTargets: skillTargets,
            locationId: locationId,
            locationName: locationName,
            usesPhases: usesPhases
        )
    }
    
    /// Create from legacy Program struct
    static func from(_ program: Program) -> SDProgram {
        let sd = SDProgram(
            id: program.id,
            name: program.name,
            programType: program.programType,
            ageGroup: program.ageGroup,
            durationWeeks: program.durationWeeks,
            description: program.description,
            objectives: program.objectives,
            enrolledStudentIds: program.enrolledStudentIds,
            coachId: program.coachId,
            createdByCoachId: program.createdByCoachId,
            status: program.status,
            colorHex: program.colorHex,
            mascot: program.mascot,
            startDate: program.startDate,
            endDate: program.endDate,
            createdAt: program.createdAt,
            updatedAt: program.updatedAt,
            imageData: program.imageData,
            stars: program.stars,
            recurringDays: program.recurringDays,
            defaultSessionTime: program.defaultSessionTime,
            defaultSessionDurationMinutes: program.defaultSessionDurationMinutes,
            skillTargets: program.skillTargets,
            locationId: program.locationId,
            locationName: program.locationName,
            usesPhases: program.usesPhases
        )
        sd.locationId = program.locationId
        sd.locationName = program.locationName
        return sd
    }
}
