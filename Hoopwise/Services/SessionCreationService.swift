import Foundation

enum SessionCreationService {
    struct Draft {
        var title: String
        var date: Date
        var startTime: Date
        var endTime: Date
        var sessionType: SessionType = .training
        var microCycleId: UUID? = nil
        var program: Program? = nil
        var location: String? = nil
        var curriculum: SessionCurriculum = SessionCurriculum()
        var attendeeIds: [UUID]? = nil
        var notes: String? = nil
        var coachId: UUID? = nil
        var status: SessionEventStatus = .scheduled
        var developmentFocus: [TrainingFocus] = []
    }

    static func resolveCoachId(explicit: UUID?, dataManager: DataManager) -> UUID? {
        explicit ?? dataManager.loggedInCoachId ?? AuthManager.shared.currentUser?.id
    }

    static func resolveAttendeeIds(explicit: [UUID]?, program: Program?) -> [UUID] {
        if let explicit = explicit { return explicit }
        return program?.enrolledStudentIds ?? []
    }

    /// Combines a calendar date with separate start/end time-of-day values.
    /// Returns nil if the resulting range is empty or inverted.
    static func combineDateAndTime(date: Date, startTime: Date, endTime: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        guard let combinedStart = calendar.date(bySettingHour: startComponents.hour ?? 0,
                                                minute: startComponents.minute ?? 0,
                                                second: 0, of: date),
              let combinedEnd = calendar.date(bySettingHour: endComponents.hour ?? 0,
                                              minute: endComponents.minute ?? 0,
                                              second: 0, of: date),
              combinedEnd > combinedStart else { return nil }
        return (combinedStart, combinedEnd)
    }

    /// Builds a SessionEvent from a Draft, applying shared validation and defaulting rules.
    /// Returns nil if title is empty after trim or the time range is invalid.
    static func makeSession(_ draft: Draft, dataManager: DataManager) -> SessionEvent? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return nil }
        guard let range = combineDateAndTime(date: draft.date, startTime: draft.startTime, endTime: draft.endTime) else { return nil }

        let attendeeIds = resolveAttendeeIds(explicit: draft.attendeeIds, program: draft.program)
        let coachId = resolveCoachId(explicit: draft.coachId, dataManager: dataManager)
        let notes: String? = {
            guard let notes = draft.notes else { return nil }
            return notes.isEmpty ? nil : notes
        }()

        return SessionEvent(
            microCycleId: draft.microCycleId,
            programId: draft.program?.id,
            sessionType: draft.sessionType,
            title: trimmedTitle,
            date: draft.date,
            startTime: range.start,
            endTime: range.end,
            location: draft.location,
            status: draft.status,
            curriculum: draft.curriculum,
            attendeeIds: attendeeIds,
            notes: notes,
            developmentFocus: draft.developmentFocus,
            createdByCoachId: coachId
        )
    }
}
