import Foundation

// MARK: - Session lifecycle
//
// THE session state machine, shared by both platforms. iOS's coaching flow
// defined these semantics; they were extracted verbatim from
// FlightySessionPageView so Mac editing enforces the identical rules — same
// inputs, same outputs, one implementation. Platform-only side effects
// (Live Activities, haptics, live-session engine) remain with each platform;
// everything that touches the RECORD lives here.
//
// Data semantics preserved exactly:
//   - skip appends "Skipped: <reason>" to notes
//   - resetToScheduled PRESERVES attendance — only the status flips
//   - complete/cancel change status only (consumption derives from records)
enum SessionLifecycle {

    enum Transition: Equatable {
        case start
        case complete
        case cancel
        case skip(SkipReason)
        case resetToScheduled
        /// System-closed after the 12h grace: the session ended and nobody
        /// completed it. Distinct from a coach's .complete via the notes
        /// marker, so it can be listed, recovered, and reopened. Attendance
        /// stays exactly as it was (usually unmarked — and unmarked is NOT
        /// absent, so auto-close never consumes anyone's bundle).
        case autoClose
    }

    /// Stable machine-readable marker `autoClose` appends to notes —
    /// the same mechanism as "Skipped: …". Never localized: detection
    /// depends on the prefix.
    static let autoCloseMarkerPrefix = "Auto-closed: "

    /// Whether this session was closed by the system rather than the coach.
    static func wasAutoClosed(_ session: SessionEvent) -> Bool {
        session.status == .completed
            && session.notes?.contains(autoCloseMarkerPrefix) == true
    }

    /// Strips the auto-close marker line — used by reopen, so a session the
    /// coach takes back does not keep claiming it was system-closed.
    static func strippingAutoCloseMarker(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let kept = notes.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(autoCloseMarkerPrefix) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? nil : kept
    }

    /// Allowed transitions per state — the union both UIs must obey.
    /// Mirrors the actions iOS actually offers: a scheduled session can
    /// start, cancel or skip; a running one can complete or cancel; any
    /// non-scheduled state can be reset back to scheduled (the undo path,
    /// attendance intact).
    static func isAllowed(_ transition: Transition,
                          from status: SessionEventStatus) -> Bool {
        switch transition {
        case .start:
            return status == .scheduled
        case .complete:
            return status == .inProgress
        case .cancel:
            return status == .scheduled || status == .inProgress
        case .skip:
            return status == .scheduled
        case .resetToScheduled:
            return status != .scheduled
        case .autoClose:
            // The states the close-out backlog accumulates in. The TIME gate
            // (end + grace) belongs to the caller — the machine gates state.
            return status == .scheduled || status == .inProgress
        }
    }

    /// Applies the transition's DATA effects. Returns false (unchanged) for
    /// a disallowed transition, so callers cannot skip the gate.
    @discardableResult
    static func apply(_ transition: Transition,
                      to session: inout SessionEvent) -> Bool {
        guard isAllowed(transition, from: session.status) else { return false }
        switch transition {
        case .start:
            session.status = .inProgress
        case .complete:
            session.status = .completed
        case .cancel:
            session.status = .cancelled
        case .skip(let reason):
            session.status = .skipped
            session.notes = (session.notes ?? "")
                + (session.notes?.isEmpty == false ? "\n" : "")
                + "Skipped: \(reason.displayName)"
        case .resetToScheduled:
            // Attendance is preserved deliberately — only the status flips.
            // If the session was auto-closed, reopening also withdraws the
            // marker — the coach has taken it back.
            session.status = .scheduled
            session.notes = strippingAutoCloseMarker(session.notes)
        case .autoClose:
            session.status = .completed
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            session.notes = (session.notes ?? "")
                + (session.notes?.isEmpty == false ? "\n" : "")
                + autoCloseMarkerPrefix + formatter.string(from: Date())
        }
        session.updatedAt = Date()
        return true
    }
}

// MARK: - Skip reasons
//
// Moved verbatim from FlightySessionPageView (iOS) — the reason vocabulary
// is part of the record's note text, so it is model vocabulary, not view
// decoration.
enum SkipReason: String, CaseIterable, Identifiable {
    case holiday = "holiday"
    case internalReason = "internal"
    case weather = "weather"
    case venueUnavailable = "venue"
    case coachUnavailable = "coach"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .holiday: return isChinese ? "假期" : "Holiday"
        case .internalReason: return isChinese ? "内部原因" : "Internal Reason"
        case .weather: return isChinese ? "天气原因" : "Weather"
        case .venueUnavailable: return isChinese ? "场地不可用" : "Venue Unavailable"
        case .coachUnavailable: return isChinese ? "教练不可用" : "Coach Unavailable"
        case .other: return isChinese ? "其他" : "Other"
        }
    }

    var icon: String {
        switch self {
        case .holiday: return "gift.fill"
        case .internalReason: return "building.2.fill"
        case .weather: return "cloud.rain.fill"
        case .venueUnavailable: return "mappin.slash"
        case .coachUnavailable: return "person.fill.xmark"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
