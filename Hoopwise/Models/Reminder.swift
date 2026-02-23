import Foundation
import SwiftUI

// MARK: - Reminder Model
/// A thoughtful reminder system inspired by award-winning apps like Things 3, Reminders, and Todoist
/// Supports tagging students and coaches for collaborative coaching
struct Reminder: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var note: String?
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var priority: ReminderPriority
    var sessionId: UUID?  // Link to session for context
    var programId: UUID?  // Optional program context
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Tagging & Ownership
    var coachId: UUID              // Owner coach (for sync)
    var creatorCoachId: UUID       // Who originally created this
    var taggedStudentIds: [UUID]   // @mentioned students (for context)
    var taggedCoachIds: [UUID]     // @mentioned coaches (they'll see this reminder)
    
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
        coachId: UUID = UUID(),
        creatorCoachId: UUID = UUID(),
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
        self.priority = priority
        self.sessionId = sessionId
        self.programId = programId
        self.coachId = coachId
        self.creatorCoachId = creatorCoachId
        self.taggedStudentIds = taggedStudentIds
        self.taggedCoachIds = taggedCoachIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    var isDueToday: Bool {
        Calendar.current.isDateInToday(dueDate)
    }
    
    var isOverdue: Bool {
        !isCompleted && dueDate < Date() && !isDueToday
    }
    
    var isDueSoon: Bool {
        let fourteenDaysFromNow = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        return !isCompleted && dueDate <= fourteenDaysFromNow && dueDate >= Date()
    }
    
    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }
    
    var relativeTimeString: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        if isOverdue {
            let days = abs(daysUntilDue)
            return isChinese ? "\(days)天前到期" : "\(days)d overdue"
        } else if isDueToday {
            return isChinese ? "今天" : "Today"
        } else if daysUntilDue == 1 {
            return isChinese ? "明天" : "Tomorrow"
        } else if daysUntilDue <= 7 {
            return isChinese ? "\(daysUntilDue)天后" : "In \(daysUntilDue)d"
        } else {
            return dueDate.formatted(date: .abbreviated, time: .omitted)
        }
    }
    
    var statusColor: Color {
        if isCompleted { return .gray }
        if isOverdue { return .red }
        if isDueToday { return .orange }
        if daysUntilDue <= 3 { return .yellow }
        return .blue
    }
    
    /// Whether this reminder has tagged coaches (shared with others)
    var isShared: Bool {
        !taggedCoachIds.isEmpty
    }
    
    /// Whether this reminder has tagged students
    var hasTaggedStudents: Bool {
        !taggedStudentIds.isEmpty
    }
    
    /// Check if a specific coach should see this reminder
    func isVisibleTo(coachId: UUID) -> Bool {
        self.coachId == coachId || taggedCoachIds.contains(coachId)
    }
    
    /// Check if this reminder was shared with the given coach (not created by them)
    func isSharedWith(coachId: UUID) -> Bool {
        self.creatorCoachId != coachId && taggedCoachIds.contains(coachId)
    }
    
    // MARK: - Mutating Methods
    
    mutating func complete() {
        isCompleted = true
        completedAt = Date()
        updatedAt = Date()
    }
    
    mutating func uncomplete() {
        isCompleted = false
        completedAt = nil
        updatedAt = Date()
    }
}

// MARK: - Reminder Priority
enum ReminderPriority: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var icon: String {
        switch self {
        case .low: return "flag"
        case .medium: return "flag.fill"
        case .high: return "exclamationmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .red
        }
    }
    
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .low: return isChinese ? "低" : "Low"
        case .medium: return isChinese ? "中" : "Medium"
        case .high: return isChinese ? "高" : "High"
        }
    }
}

// MARK: - Quick Reminder Presets
enum QuickReminderPreset: CaseIterable {
    case beforeNextSession
    case tomorrow
    case nextWeek
    case custom
    
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .beforeNextSession: return isChinese ? "下次课前" : "Before next session"
        case .tomorrow: return isChinese ? "明天" : "Tomorrow"
        case .nextWeek: return isChinese ? "下周" : "Next week"
        case .custom: return isChinese ? "自定义" : "Custom"
        }
    }
    
    var icon: String {
        switch self {
        case .beforeNextSession: return "figure.basketball"
        case .tomorrow: return "sunrise"
        case .nextWeek: return "calendar"
        case .custom: return "calendar.badge.clock"
        }
    }
    
    func date(relativeTo referenceDate: Date = Date()) -> Date {
        switch self {
        case .beforeNextSession:
            return referenceDate  // Will be overridden by actual next session
        case .tomorrow:
            return Calendar.current.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        case .nextWeek:
            return Calendar.current.date(byAdding: .day, value: 7, to: referenceDate) ?? referenceDate
        case .custom:
            return referenceDate
        }
    }
}

// MARK: - Supabase Reminder (for sync)
/// Codable struct matching Supabase table schema
struct SupabaseReminder: Codable {
    let id: UUID
    var title: String
    var note: String?
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var priority: String
    var sessionId: UUID?
    var programId: UUID?
    var coachId: UUID
    var creatorCoachId: UUID
    var taggedStudentIds: [UUID]
    var taggedCoachIds: [UUID]
    var createdAt: Date
    var updatedAt: Date
    
    init(from reminder: Reminder) {
        self.id = reminder.id
        self.title = reminder.title
        self.note = reminder.note
        self.dueDate = reminder.dueDate
        self.isCompleted = reminder.isCompleted
        self.completedAt = reminder.completedAt
        self.priority = reminder.priority.rawValue
        self.sessionId = reminder.sessionId
        self.programId = reminder.programId
        self.coachId = reminder.coachId
        self.creatorCoachId = reminder.creatorCoachId
        self.taggedStudentIds = reminder.taggedStudentIds
        self.taggedCoachIds = reminder.taggedCoachIds
        self.createdAt = reminder.createdAt
        self.updatedAt = reminder.updatedAt
    }
    
    func toReminder() -> Reminder {
        Reminder(
            id: id,
            title: title,
            note: note,
            dueDate: dueDate,
            isCompleted: isCompleted,
            completedAt: completedAt,
            priority: ReminderPriority(rawValue: priority) ?? .medium,
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
}
