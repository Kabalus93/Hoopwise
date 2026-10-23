import Foundation

// MARK: - Plans move on when a class does not happen (October 2026, Luther)
//
// A cancelled or skipped class used to keep its plan and teach nobody: every
// later plan had been written assuming it happened, and the phase simply
// delivered one class less. Now the plans SHIFT:
//
//   forward  — the cancelled class's plan goes to the next scheduled class in
//              its phase, each later plan moves down one class, and the plan
//              left over at the end is offered as a MAKE-UP class on the
//              program's next usual day after the phase (the coach decides).
//              The cancelled class keeps its plan as the record, plus the
//              `movedMarker` note.
//   backward — reopening that class (Reset to scheduled) moves every plan
//              back; a make-up class made for it gives its plan back too.
//
// Only SCHEDULED classes after the cancelled one move — completed, live,
// skipped and cancelled classes are history and are never rewritten. Pure:
// the manager writes (`SwiftDataManager.shiftPlansAfterStatusChange`).

enum SessionPlanShift {

    /// Appended to the cancelled class's notes when its plans moved on —
    /// the same stable-prefix mechanism as "Skipped:". Reopening reads it.
    static let movedMarker = "Plan moved to the next class"
    /// Notes prefix of a make-up class: "Make-up for 2026-10-24 18:30".
    static let makeUpPrefix = "Make-up for "

    struct Forward: Equatable {
        /// Followers with their new plans.
        var updated: [SessionEvent]
        /// The plan that no longer has a class.
        var overflow: SessionCurriculum
    }

    struct Backward: Equatable {
        var updated: [SessionEvent]
        /// The make-up class made for this one, if it is still there.
        var makeUp: SessionEvent?
        /// The last follower needs a fresh plan (the dropped one is gone).
        var needsPlan: UUID?
    }

    /// The classes whose plans move: same phase (else same program),
    /// scheduled, starting after `session`, in date order.
    static func followers(of session: SessionEvent, in sessions: [SessionEvent]) -> [SessionEvent] {
        let sameGroup: (SessionEvent) -> Bool
        if let phase = session.microCycleId {
            sameGroup = { $0.microCycleId == phase }
        } else if let program = session.programId {
            sameGroup = { $0.programId == program }
        } else {
            return []
        }
        return sessions
            .filter { $0.id != session.id && sameGroup($0)
                && $0.status == .scheduled && $0.startTime > session.startTime }
            .sorted { $0.startTime < $1.startTime }
    }

    /// nil when there is nothing to move (no plan, no group).
    static func forward(cancelling session: SessionEvent, in sessions: [SessionEvent]) -> Forward? {
        guard session.curriculum.totalDrillCount > 0,
              session.microCycleId != nil || session.programId != nil else { return nil }
        var follow = followers(of: session, in: sessions)
        let chain = [session.curriculum] + follow.map(\.curriculum)
        for i in follow.indices { follow[i].curriculum = chain[i] }
        return Forward(updated: follow, overflow: chain[chain.count - 1])
    }

    static func backward(reopening session: SessionEvent, in sessions: [SessionEvent]) -> Backward? {
        guard hasMovedMarker(session.notes) else { return nil }
        let all = followers(of: session, in: sessions)
        let tag = makeUpNote(for: session)
        let makeUp = all.last { $0.notes?.contains(tag) == true }
        var follow = all.filter { $0.id != makeUp?.id }
        var chain = follow.map(\.curriculum)
        if let makeUp { chain.append(makeUp.curriculum) }
        for i in follow.indices where i + 1 < chain.count { follow[i].curriculum = chain[i + 1] }
        var needsPlan: UUID?
        if makeUp == nil, let last = follow.indices.last {
            follow[last].curriculum = SessionCurriculum(
                warmupMinutes: follow[last].curriculum.warmupMinutes,
                skillsMinutes: follow[last].curriculum.skillsMinutes,
                gameMinutes: follow[last].curriculum.gameMinutes)
            needsPlan = follow[last].id
        }
        return Backward(updated: follow, makeUp: makeUp, needsPlan: needsPlan)
    }

    // MARK: Notes

    static func hasMovedMarker(_ notes: String?) -> Bool {
        notes?.split(separator: "\n").contains { $0.hasPrefix(movedMarker) } == true
    }

    static func addingMovedMarker(_ notes: String?) -> String {
        guard !hasMovedMarker(notes) else { return notes ?? movedMarker }
        let base = notes ?? ""
        return base + (base.isEmpty ? "" : "\n") + movedMarker
    }

    static func removingMovedMarker(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let kept = notes.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(movedMarker) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? nil : kept
    }

    static func makeUpNote(for session: SessionEvent) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return makeUpPrefix + f.string(from: session.startTime)
    }

    // MARK: Make-up slot

    /// The program's next usual day after `after` (its recurring weekdays,
    /// else the cancelled class's own weekday), at the cancelled class's time.
    static func makeUpStart(for session: SessionEvent, program: Program?, after: Date,
                            calendar cal: Calendar = .current) -> Date {
        let days = Set((program?.recurringDays ?? []).map(\.rawValue))
        let wanted = days.isEmpty ? [cal.component(.weekday, from: session.startTime)] : days
        let time = cal.dateComponents([.hour, .minute], from: session.startTime)
        var day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: after)) ?? after
        for _ in 0..<14 {
            if wanted.contains(cal.component(.weekday, from: day)) { break }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}
