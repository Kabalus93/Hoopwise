import Foundation
import SwiftData

@Model
final class SDSessionEvent {
    var id: UUID = UUID()
    var microCycleId: UUID?
    var programId: UUID?
    /// Identity of the generated recurring series this session belongs to,
    /// stamped at generation (Phase 2.2). Optional and defaulted, so the
    /// CloudKit schema change is additive. Replaces the structural
    /// fingerprint that recognised a series by title + venue + weekday +
    /// time + duration.
    var seriesId: UUID?
    var sessionTypeRaw: String = "training"
    var title: String = ""
    var date: Date = Date()
    var startTime: Date = Date()
    var endTime: Date = Date()
    var location: String?
    var statusRaw: String = "scheduled"
    
    // Curriculum stored as JSON
    var curriculumData: Data?
    
    // In-session games stored as JSON
    var gamesData: Data?
    
    // Attendance
    var attendeeIds: [UUID] = []
    var actualAttendeeIds: [UUID] = []
    var excusedAbsences: [UUID] = []  // Students who notified absence in advance (session preserved)
    /// Students recorded as an unexcused absence — a no-show, or notice too
    /// late to excuse. Stored EXPLICITLY rather than inferred from "not in
    /// actualAttendeeIds", because that inference cannot tell a no-show from a
    /// student whose attendance simply has not been taken yet. Since an
    /// unexcused absence consumes a bundle session (agreement clause 4), that
    /// ambiguity would invent revenue.
    var unexcusedAbsences: [UUID] = []
    var attendancePhotoPath: String?
    
    // Notes
    var notes: String?
    var coachNotes: String?
    
    // Development focus (theme for phase-less programs)
    var developmentFocusRaw: [String] = []  // TrainingFocus raw values
    
    // Post-session data
    var manOfTheMatchId: UUID?
    var drillsCompleted: [UUID] = []
    var rating: Int?
    var createdByCoachId: UUID?  // For access control
    /// Header image for the session detail hero card. Persisted so the same
    /// session keeps the same image across loads — before this field
    /// existed, the round-trip through `toStruct()` regenerated a random
    /// URL every read.
    var headerImageURL: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
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
        unexcusedAbsences: [UUID] = [],
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
        self.unexcusedAbsences = unexcusedAbsences
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
        let event = SessionEvent(
            id: id,
            microCycleId: microCycleId,
            programId: programId,
            seriesId: seriesId,
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
            unexcusedAbsences: unexcusedAbsences,
            attendancePhotoPath: attendancePhotoPath,
            notes: notes,
            coachNotes: coachNotes,
            developmentFocus: developmentFocus,
            manOfTheMatchId: manOfTheMatchId,
            drillsCompleted: drillsCompleted,
            rating: rating,
            createdByCoachId: createdByCoachId,
            games: games,
            // Persist the header image so the hero card stays stable across
            // reloads. `SessionEvent.init` auto-generates a random URL when
            // we pass nil, so existing sessions without a stored URL still
            // get one — they just won't be sticky until the next save.
            headerImageURL: headerImageURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        // SessionEvent.init substitutes a random URL when the stored value
        // is nil; the view's `.onAppear` saves that URL back via
        // `setSessionHeaderImageURL` so the next load is sticky.
        return event
    }

    /// Create from legacy SessionEvent struct
    static func from(_ event: SessionEvent) -> SDSessionEvent {
        // The initializer's required arguments are re-set by apply(); it is
        // the single writer of content.
        let sdEvent = SDSessionEvent(id: event.id,
                                     title: event.title,
                                     date: event.date,
                                     startTime: event.startTime,
                                     endTime: event.endTime)
        sdEvent.apply(event)
        sdEvent.createdAt = event.createdAt
        return sdEvent
    }

    /// THE whole-record write. Every mutable column is copied here and
    /// NOWHERE else, so a field cannot be persisted on create but dropped on
    /// update — which is exactly what happened to unexcusedAbsences (the
    /// revenue-critical one), developmentFocus, headerImageURL and
    /// createdByCoachId: `updateSessionEvent` hand-listed 19 of the 23
    /// columns and silently lost the other four on every save.
    ///
    /// `id` and `createdAt` are identity, not content, so they are not
    /// touched. Adding a property to this @Model means adding it here;
    /// SessionRoundTripTests fails until you do.
    func apply(_ event: SessionEvent) {
        microCycleId = event.microCycleId
        programId = event.programId
        seriesId = event.seriesId
        sessionType = event.sessionType
        title = event.title
        date = event.date
        startTime = event.startTime
        endTime = event.endTime
        location = event.location
        status = event.status
        curriculum = event.curriculum
        games = event.games
        attendeeIds = event.attendeeIds
        actualAttendeeIds = event.actualAttendeeIds
        excusedAbsences = event.excusedAbsences
        unexcusedAbsences = event.unexcusedAbsences
        attendancePhotoPath = event.attendancePhotoPath
        notes = event.notes
        coachNotes = event.coachNotes
        developmentFocus = event.developmentFocus
        manOfTheMatchId = event.manOfTheMatchId
        drillsCompleted = event.drillsCompleted
        rating = event.rating
        createdByCoachId = event.createdByCoachId
        headerImageURL = event.headerImageURL
        updatedAt = event.updatedAt
    }
}
