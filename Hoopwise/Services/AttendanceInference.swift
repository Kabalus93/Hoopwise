import Foundation

/// When a student nobody marked counts as ABSENT.
///
/// REVERSES an earlier rule, by the coach's decision (October 2026). Until
/// then "unmarked is NOT absent" was absolute: nothing was ever inferred,
/// because an unexcused absence deducts a session and inferring one invents a
/// charge. The coach now marks attendance with a three-position switch
/// (excused · not marked · present) and wants whoever is left in the middle
/// to count as absent. The rule is bounded so that it can only ever follow a
/// roll call that actually happened:
///
/// 1. ROLL CALL STARTED. A session infers nothing until at least one student
///    on it has an explicit mark (present, excused or absent). A class where
///    nobody was marked stays unmarked — the "Attendance not taken" alert
///    fires instead of the whole roster being charged.
/// 2. SHOWN AT ONCE, CHARGED LATER. Once roll call has started, every
///    still-unmarked roster student DISPLAYS as absent. The absence is only
///    WRITTEN (and so deducted, through the one redemption authority)
///    `chargeDelay` after the class ends, so late arrivals and excuses
///    recorded during or just after class never need a refund.
/// 3. FROM `effectiveFrom` ON. Sessions that started earlier keep exactly
///    what was recorded. Applying this backwards would charge every unmarked
///    student of every past class at once and move balances families have
///    already been told.
/// 4. ONLY SESSIONS THAT HAPPENED. Skipped and cancelled sessions
///    (`SessionLifecycle.didNotHappen`) infer nothing.
///
/// Pure functions; the write lives in `SwiftDataManager.chargeInferredAbsences`.
enum AttendanceInference {

    /// Start of 2026-10-15, local time — the day the rule was adopted.
    static let effectiveFrom: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 15
        return Calendar.current.date(from: components) ?? .distantFuture
    }()

    /// How long after a class ends its inferred absences are charged.
    static let chargeDelay: TimeInterval = 60 * 60

    /// True once any student on the session has an explicit mark.
    static func rollCallStarted(_ session: SessionEvent) -> Bool {
        !session.actualAttendeeIds.isEmpty
            || !session.excusedAbsences.isEmpty
            || !session.unexcusedAbsences.isEmpty
    }

    /// Whether the session is inside the rule at all.
    static func applies(to session: SessionEvent) -> Bool {
        session.startTime >= effectiveFrom && !SessionLifecycle.didNotHappen(session)
    }

    private static func isUnmarked(_ studentId: UUID, in session: SessionEvent) -> Bool {
        !session.actualAttendeeIds.contains(studentId)
            && !session.excusedAbsences.contains(studentId)
            && !session.unexcusedAbsences.contains(studentId)
    }

    /// The student is unmarked, but counts as absent. Display only — nothing
    /// is charged until `absencesToCharge` returns them.
    static func isInferredAbsent(_ studentId: UUID, in session: SessionEvent) -> Bool {
        applies(to: session) && rollCallStarted(session) && isUnmarked(studentId, in: session)
    }

    /// Roster students whose inferred absence is due to be written now.
    /// `expected` is the session's roster (`AttendanceMath.expectedIds`).
    static func absencesToCharge(in session: SessionEvent,
                                 expected: [UUID],
                                 now: Date) -> [UUID] {
        guard applies(to: session),
              rollCallStarted(session),
              now >= session.endTime.addingTimeInterval(chargeDelay)
        else { return [] }
        return expected.filter { isUnmarked($0, in: session) }
    }
}
