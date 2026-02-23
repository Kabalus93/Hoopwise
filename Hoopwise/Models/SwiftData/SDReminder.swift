import Foundation
import SwiftData

@Model
final class SDReminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String?
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var priorityRaw: String
    var sessionId: UUID?
    var programId: UUID?
    var coachId: UUID
    var creatorCoachId: UUID
    var taggedStudentIdsData: Data?  // Stored as JSON
    var taggedCoachIdsData: Data?    // Stored as JSON
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        dueDate: Date,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        priority: ReminderPriority = .medium,
        sessionId: UUID? = nil,
        programId: UUID? = nil,
        coachId: UUID,
        creatorCoachId: UUID,
        taggedStudentIds: [UUID] = [],
        taggedCoachIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priorityRaw = priority.rawValue
        self.sessionId = sessionId
        self.programId = programId
        self.coachId = coachId
        self.creatorCoachId = creatorCoachId
        self.taggedStudentIdsData = try? JSONEncoder().encode(taggedStudentIds)
        self.taggedCoachIdsData = try? JSONEncoder().encode(taggedCoachIds)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    var priority: ReminderPriority {
        get { ReminderPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    
    var taggedStudentIds: [UUID] {
        get {
            guard let data = taggedStudentIdsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            taggedStudentIdsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var taggedCoachIds: [UUID] {
        get {
            guard let data = taggedCoachIdsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            taggedCoachIdsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Convert to Reminder struct
    func toStruct() -> Reminder {
        Reminder(
            id: id,
            title: title,
            note: note,
            dueDate: dueDate,
            isCompleted: isCompleted,
            completedAt: completedAt,
            priority: priority,
            sessionId: sessionId,
            programId: programId,
            coachId: coachId,
            creatorCoachId: creatorCoachId,
            taggedStudentIds: taggedStudentIds,
            taggedCoachIds: taggedCoachIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Create from Reminder struct
    static func from(_ reminder: Reminder) -> SDReminder {
        SDReminder(
            id: reminder.id,
            title: reminder.title,
            note: reminder.note,
            dueDate: reminder.dueDate,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completedAt,
            priority: reminder.priority,
            sessionId: reminder.sessionId,
            programId: reminder.programId,
            coachId: reminder.coachId,
            creatorCoachId: reminder.creatorCoachId,
            taggedStudentIds: reminder.taggedStudentIds,
            taggedCoachIds: reminder.taggedCoachIds,
            createdAt: reminder.createdAt,
            updatedAt: reminder.updatedAt
        )
    }
    
    /// Update from Reminder struct
    func update(from reminder: Reminder) {
        title = reminder.title
        note = reminder.note
        dueDate = reminder.dueDate
        isCompleted = reminder.isCompleted
        completedAt = reminder.completedAt
        priority = reminder.priority
        sessionId = reminder.sessionId
        programId = reminder.programId
        taggedStudentIds = reminder.taggedStudentIds
        taggedCoachIds = reminder.taggedCoachIds
        updatedAt = reminder.updatedAt
    }
}
