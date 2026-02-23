import Foundation
import SwiftData

@Model
final class SDSessionEvent {
    @Attribute(.unique) var id: UUID
    var microCycleId: UUID?
    var programId: UUID?
    var sessionTypeRaw: String
    var title: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var location: String?
    var statusRaw: String
    
    // Curriculum stored as JSON
    var curriculumData: Data?
    
    // In-session games stored as JSON
    var gamesData: Data?
    
    // Attendance
    var attendeeIds: [UUID]
    var actualAttendeeIds: [UUID]
    var excusedAbsences: [UUID] = []  // Students who notified absence in advance (session preserved)
    var attendancePhotoPath: String?
    
    // Notes
    var notes: String?
    var coachNotes: String?
    
    // Development focus (theme for phase-less programs)
    var developmentFocusRaw: [String] = []  // TrainingFocus raw values
    
    // Post-session data
    var manOfTheMatchId: UUID?
    var drillsCompleted: [UUID]
    var rating: Int?
    var createdByCoachId: UUID?  // For access control
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    var program: SDProgram?
    var microCycle: SDMicroCycle?
    
    init(
        id: UUID = UUID(),
        microCycleId: UUID? = nil,
        programId: UUID? = nil,
        sessionType: SessionType = .training,
        title: String,
        date: Date,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        status: SessionEventStatus = .scheduled,
        curriculum: SessionCurriculum = SessionCurriculum(),
        attendeeIds: [UUID] = [],
        actualAttendeeIds: [UUID] = [],
        excusedAbsences: [UUID] = [],
        attendancePhotoPath: String? = nil,
        notes: String? = nil,
        coachNotes: String? = nil,
        developmentFocus: [TrainingFocus] = [],
        manOfTheMatchId: UUID? = nil,
        drillsCompleted: [UUID] = [],
        rating: Int? = nil,
        createdByCoachId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.microCycleId = microCycleId
        self.programId = programId
        self.sessionTypeRaw = sessionType.rawValue
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.statusRaw = status.rawValue
        self.curriculumData = try? JSONEncoder().encode(curriculum)
        self.gamesData = nil  // Set separately if needed
        self.attendeeIds = attendeeIds
        self.actualAttendeeIds = actualAttendeeIds
        self.excusedAbsences = excusedAbsences
        self.attendancePhotoPath = attendancePhotoPath
        self.notes = notes
        self.coachNotes = coachNotes
        self.developmentFocusRaw = developmentFocus.map { $0.rawValue }
        self.manOfTheMatchId = manOfTheMatchId
        self.drillsCompleted = drillsCompleted
        self.rating = rating
        self.createdByCoachId = createdByCoachId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .training }
        set { sessionTypeRaw = newValue.rawValue }
    }
    
    var status: SessionEventStatus {
        get { SessionEventStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }
    
    var curriculum: SessionCurriculum {
        get {
            guard let data = curriculumData else { return SessionCurriculum() }
            return (try? JSONDecoder().decode(SessionCurriculum.self, from: data)) ?? SessionCurriculum()
        }
        set { curriculumData = try? JSONEncoder().encode(newValue) }
    }
    
    var games: [SessionGame] {
        get {
            guard let data = gamesData else { 
                return [] 
            }
            do {
                let decoded = try JSONDecoder().decode([SessionGame].self, from: data)
                if !decoded.isEmpty {
                    debugLog("🎮 [DEBUG] SDSessionEvent.games GET: decoded \(decoded.count) games from \(data.count) bytes")
                }
                return decoded
            } catch {
                debugLog("❌ [DEBUG] SDSessionEvent.games GET decode error: \(error)")
                return []
            }
        }
        set { 
            do {
                let encoded = try JSONEncoder().encode(newValue)
                gamesData = encoded
                if !newValue.isEmpty {
                    debugLog("🎮 [DEBUG] SDSessionEvent.games SET: encoded \(newValue.count) games to \(encoded.count) bytes")
                }
            } catch {
                debugLog("❌ [DEBUG] SDSessionEvent.games SET encode error: \(error)")
                gamesData = nil
            }
        }
    }
    
    var developmentFocus: [TrainingFocus] {
        get { developmentFocusRaw.compactMap { TrainingFocus(rawValue: $0) } }
        set { developmentFocusRaw = newValue.map { $0.rawValue } }
    }
    
    var belongsToPhase: Bool { microCycleId != nil }
    
    var attendanceRate: Double {
        guard !attendeeIds.isEmpty else { return 0 }
        return Double(actualAttendeeIds.count) / Double(attendeeIds.count)
    }
    
    var durationMinutes: Int { Int(endTime.timeIntervalSince(startTime) / 60) }
    var isUpcoming: Bool { date > Date() && status == .scheduled }
    var isPast: Bool { date < Date() || status == .completed }
    
    /// Convert to legacy SessionEvent struct
    func toStruct() -> SessionEvent {
        SessionEvent(
            id: id,
            microCycleId: microCycleId,
            programId: programId,
            sessionType: sessionType,
            title: title,
            date: date,
            startTime: startTime,
            endTime: endTime,
            location: location,
            status: status,
            curriculum: curriculum,
            attendeeIds: attendeeIds,
            actualAttendeeIds: actualAttendeeIds,
            excusedAbsences: excusedAbsences,
            attendancePhotoPath: attendancePhotoPath,
            notes: notes,
            coachNotes: coachNotes,
            developmentFocus: developmentFocus,
            manOfTheMatchId: manOfTheMatchId,
            drillsCompleted: drillsCompleted,
            rating: rating,
            createdByCoachId: createdByCoachId,
            games: games,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Create from legacy SessionEvent struct
    static func from(_ event: SessionEvent) -> SDSessionEvent {
        let sdEvent = SDSessionEvent(
            id: event.id,
            microCycleId: event.microCycleId,
            programId: event.programId,
            sessionType: event.sessionType,
            title: event.title,
            date: event.date,
            startTime: event.startTime,
            endTime: event.endTime,
            location: event.location,
            status: event.status,
            curriculum: event.curriculum,
            attendeeIds: event.attendeeIds,
            actualAttendeeIds: event.actualAttendeeIds,
            excusedAbsences: event.excusedAbsences,
            attendancePhotoPath: event.attendancePhotoPath,
            notes: event.notes,
            coachNotes: event.coachNotes,
            developmentFocus: event.developmentFocus,
            manOfTheMatchId: event.manOfTheMatchId,
            drillsCompleted: event.drillsCompleted,
            rating: event.rating,
            createdByCoachId: event.createdByCoachId,
            createdAt: event.createdAt,
            updatedAt: event.updatedAt
        )
        sdEvent.games = event.games
        return sdEvent
    }
}
