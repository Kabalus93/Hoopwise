import Foundation

// MARK: - Series identity and Live Activity gating (Phase 2.2)
//
// `programId == nil` was doing four jobs: standalone, private, "part of a
// legacy recurring series", and "gets no Live Activity". Phase 1 gave private
// its own answer (the program's type) and Phase 2.1 gave nearly every session
// a program. This file retires the last two meanings.
//
// SERIES IDENTITY. Recurring sessions were recognised by a structural
// fingerprint — same title, venue, weekday, time-of-day and duration, and no
// program. That test is both too broad (two unrelated one-offs that happen to
// share a slot look like a series) and too narrow (it refuses to see any
// program-linked series at all, and any edit to the title or venue silently
// removes a session from its own series). A generated series now carries a
// stamped `seriesId`, and the fingerprint survives only as a fallback for
// records generated before the field existed.
//
// LIVE ACTIVITY. The old rule was accidental: `startLiveActivity` returned
// early unless the session had a program, so private clients never got one —
// not by decision, but because privateness was encoded as the absence of a
// program. Now it is an explicit rule with a preference behind it.
enum SessionSeries {

    /// Sessions belonging to the same generated series as `event`.
    ///
    /// Prefers the stamped id. Falls back to the legacy fingerprint only for
    /// records with no `seriesId`, which is the pre-2.2 data; once those are
    /// stamped or aged out, the fallback can go.
    static func siblings(of event: SessionEvent,
                         in sessions: [SessionEvent],
                         calendar: Calendar = .current) -> [SessionEvent] {
        if let seriesId = event.seriesId {
            return sessions.filter { $0.seriesId == seriesId }
        }
        return legacyFingerprintSiblings(of: event, in: sessions, calendar: calendar)
    }

    /// The pre-2.2 test, kept only for unstamped records. Deliberately still
    /// restricted to program-less sessions: widening it now would let it
    /// claim sessions that belong to a real program.
    static func legacyFingerprintSiblings(of event: SessionEvent,
                                          in sessions: [SessionEvent],
                                          calendar: Calendar = .current) -> [SessionEvent] {
        guard event.programId == nil, event.seriesId == nil else { return [] }
        let weekday = calendar.component(.weekday, from: event.date)
        let clock = calendar.dateComponents([.hour, .minute], from: event.startTime)
        let duration = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        return sessions.filter { other in
            other.programId == nil
                && other.seriesId == nil
                && other.title == event.title
                && other.location == event.location
                && calendar.component(.weekday, from: other.date) == weekday
                && calendar.dateComponents([.hour, .minute], from: other.startTime) == clock
                && Int(other.endTime.timeIntervalSince(other.startTime) / 60) == duration
        }
    }

    // MARK: - Live Activity

    /// Whether a running session should raise a Live Activity.
    ///
    /// Group-shaped programs always do. Private sessions are a preference,
    /// defaulting OFF so behaviour is unchanged from before the rule existed
    /// — a coach in a 1:1 does not necessarily want it on their Lock Screen.
    /// A session with no program gets none: there is nothing to title it with.
    static func allowsLiveActivity(_ session: SessionEvent,
                                   programs: [Program],
                                   contracts: [Contract],
                                   privateSessionsEnabled: Bool) -> Bool {
        guard session.programId != nil,
              programs.contains(where: { $0.id == session.programId }) else { return false }
        let isPrivate = SessionPrivacy.isPrivate(session, programs: programs, contracts: contracts)
        return isPrivate ? privateSessionsEnabled : true
    }

    /// Preference key for the private-session case.
    static let privateLiveActivityDefaultsKey = "liveActivity.privateSessions"

    static var privateLiveActivityEnabled: Bool {
        UserDefaults.standard.bool(forKey: privateLiveActivityDefaultsKey)
    }
}
