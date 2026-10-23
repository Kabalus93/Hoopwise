import Foundation

// MARK: - A program's sessions follow the program (October 2026, Luther)
//
// Editing a program used to change only the program: its time, length, venue
// and roster were copied onto each session when the session was created, and
// nothing ever copied them again — so a class moved from 18:00 to 18:30 kept
// every scheduled session at 18:00, and a student enrolled in October was not
// expected at November's classes.
//
// Now an edit TRICKLES DOWN to every UPCOMING SCHEDULED session that still
// FOLLOWS the program — whose value is the program's OLD value. A session the
// coach changed on its own (moved one class to 19:00, held one at another
// gym, invited a guest) keeps its own value. Past, live, completed, skipped
// and cancelled sessions are history and never change.
//
//   time     → same day, new time of day (the length is kept)
//   length   → new end time
//   venue    → new venue (an empty venue follows too)
//   roster   → new roster (empty rosters already read the program's)
//   weekdays → `move`: a swapped day moves each session to the new day of the
//              same week, plan and all; `reflowPlans` keeps the plans in order
//              when classes are removed.
//
// Pure: `SwiftDataManager.updateProgram` and the enrollment writers apply it.

enum ProgramSessionSync {

    /// Upcoming scheduled sessions of the program, in date order.
    static func upcoming(of programId: UUID, in sessions: [SessionEvent], now: Date) -> [SessionEvent] {
        sessions
            .filter { $0.programId == programId && $0.status == .scheduled && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
    }

    /// The sessions that change, with their new values. Empty when nothing
    /// that sessions carry was edited.
    static func follow(before: Program, after: Program, sessions: [SessionEvent],
                       now: Date = Date(), calendar cal: Calendar = .current) -> [SessionEvent] {
        let oldTime = before.defaultSessionTime.map { hm($0, cal) }
        let newTime = after.defaultSessionTime.map { hm($0, cal) }
        let timeChanged = newTime != nil && oldTime != newTime
        let oldLength = before.defaultSessionDurationMinutes
        let newLength = after.defaultSessionDurationMinutes
        let lengthChanged = newLength > 0 && oldLength != newLength
        let oldVenue = clean(before.locationName)
        let newVenue = clean(after.locationName)
        let venueChanged = oldVenue != newVenue
        let oldRoster = Set(before.enrolledStudentIds)
        let rosterChanged = oldRoster != Set(after.enrolledStudentIds)
        guard timeChanged || lengthChanged || venueChanged || rosterChanged else { return [] }

        var changed: [SessionEvent] = []
        for var s in upcoming(of: after.id, in: sessions, now: now) {
            var touched = false
            let length = s.endTime.timeIntervalSince(s.startTime)

            if timeChanged, let newTime, oldTime == nil || hm(s.startTime, cal) == oldTime!,
               let moved = cal.date(bySettingHour: newTime.hour, minute: newTime.minute, second: 0, of: s.startTime),
               moved > now {
                s.startTime = moved
                s.date = moved
                s.endTime = moved.addingTimeInterval(length)
                touched = true
            }
            if lengthChanged, Int((length / 60).rounded()) == oldLength {
                s.endTime = s.startTime.addingTimeInterval(TimeInterval(newLength * 60))
                touched = true
            }
            if venueChanged, clean(s.location) == oldVenue || clean(s.location) == nil {
                s.location = newVenue
                touched = true
            }
            if rosterChanged, !s.attendeeIds.isEmpty, Set(s.attendeeIds) == oldRoster {
                s.attendeeIds = after.enrolledStudentIds
                touched = true
            }
            if touched { changed.append(s) }
        }
        return changed
    }

    /// A weekday SWAP (Saturday → Sunday): each upcoming session on a removed
    /// day moves to the nearest paired added day, plan and all.
    /// Pairs in weekday order; nil when the counts differ (not a swap).
    static func move(programId: UUID, from removed: [Weekday], to added: [Weekday],
                     sessions: [SessionEvent], now: Date = Date(),
                     calendar cal: Calendar = .current) -> [SessionEvent]? {
        guard !removed.isEmpty, removed.count == added.count else { return nil }
        let from = removed.sorted { $0.rawValue < $1.rawValue }
        let to = added.sorted { $0.rawValue < $1.rawValue }
        var moved: [SessionEvent] = []
        for var s in upcoming(of: programId, in: sessions, now: now) {
            let weekday = cal.component(.weekday, from: s.startTime)
            guard let i = from.firstIndex(where: { $0.rawValue == weekday }) else { continue }
            // The NEAREST new day: Saturday → Sunday is the next day, not the
            // Sunday that opens the calendar week six days earlier.
            var shift = to[i].rawValue - weekday
            if shift > 3 { shift -= 7 } else if shift < -3 { shift += 7 }
            var start = cal.date(byAdding: .day, value: shift, to: s.startTime) ?? s.startTime
            if start <= now {
                shift += 7
                start = cal.date(byAdding: .day, value: shift, to: s.startTime) ?? s.startTime
            }
            let length = s.endTime.timeIntervalSince(s.startTime)
            s.startTime = start
            s.date = start
            s.endTime = start.addingTimeInterval(length)
            moved.append(s)
        }
        return moved
    }

    /// Classes about to be removed: the plans of ALL upcoming classes, in date
    /// order, go to the classes that remain, in date order — so the program
    /// still teaches its plan from where it is, and only the last plans (as
    /// many as classes removed) have no class. Returns the remaining classes
    /// whose plan changed, and how many plans were left over.
    static func reflowPlans(removing removedIds: Set<UUID>, programId: UUID,
                            sessions: [SessionEvent], now: Date = Date()) -> (updated: [SessionEvent], leftOver: Int) {
        let all = upcoming(of: programId, in: sessions, now: now)
        // Every class's plan in order, empty ones included, so a class the
        // coach left unplanned stays a gap instead of being filled.
        let plans = all.map(\.curriculum)
        var kept = all.filter { !removedIds.contains($0.id) }
        guard plans.contains(where: { $0.totalDrillCount > 0 }) else { return ([], 0) }
        var updated: [SessionEvent] = []
        for i in kept.indices where kept[i].curriculum != plans[i] {
            kept[i].curriculum = plans[i]
            updated.append(kept[i])
        }
        let leftOver = plans.dropFirst(kept.count).filter { $0.totalDrillCount > 0 }.count
        return (updated, leftOver)
    }

    // MARK: Helpers

    private static func hm(_ date: Date, _ cal: Calendar) -> HM {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return HM(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private struct HM: Equatable { let hour: Int; let minute: Int }

    private static func clean(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}
