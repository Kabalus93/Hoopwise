import SwiftUI

// MARK: - Attention Inbox
/// Aggregates everything that needs the coach's attention into a small set
/// of *do-something* categories — not by which database table the data
/// lives in. The dashboard surfaces this as a triaging chip-row instead of a
/// flat list, so a busy coach can pick which kind of work they want to clear.

enum AttentionCategory: String, CaseIterable, Identifiable {
    /// Past sessions still scheduled/in-progress, overdue reminders, etc.
    /// Resolution is usually one tap (mark complete / skip / delete).
    case closeOut
    /// Dormant private clients, bundles running low — re-engagement signals.
    /// Action is usually messaging or scheduling.
    case reEngage
    /// Forward-looking gaps: unplanned sessions, programs missing phases.
    /// Action is opening the planner.
    case plan

    var id: String { rawValue }

    var label: String {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .closeOut: return isCN ? "收尾" : "Close out"
        case .reEngage: return isCN ? "回访" : "Re-engage"
        case .plan:     return isCN ? "排课" : "Plan"
        }
    }

    var icon: String {
        switch self {
        case .closeOut: return "checkmark.circle.badge.questionmark"
        case .reEngage: return "person.crop.circle.badge.exclamationmark"
        case .plan:     return "calendar.badge.exclamationmark"
        }
    }

    /// Tint used for the dashboard chip background. Distinct from the red
    /// header so the chips don't compete with the urgency framing.
    var tint: Color {
        switch self {
        case .closeOut: return .red
        case .reEngage: return .orange
        case .plan:     return .blue
        }
    }
}

enum AttentionSeverity: Int, Comparable {
    case fyi = 0       // Forward-looking, not yet actionable today
    case attention = 1 // Actionable now or soon
    case urgent = 2    // Past due / blocking

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where to navigate when the coach taps an item.
enum AttentionPayload {
    case session(UUID)
    case student(UUID)
    case program(UUID)
    case reminder(UUID)
}

struct AttentionItem: Identifiable {
    let id: UUID
    let category: AttentionCategory
    let severity: AttentionSeverity
    let title: String
    let subtitle: String?
    let timeContext: String?  // e.g. "ended 2h ago"
    let icon: String
    let payload: AttentionPayload
    /// Used as a tiebreaker when severity ties — older problems sort first.
    let referenceDate: Date

    init(
        id: UUID = UUID(),
        category: AttentionCategory,
        severity: AttentionSeverity,
        title: String,
        subtitle: String? = nil,
        timeContext: String? = nil,
        icon: String,
        payload: AttentionPayload,
        referenceDate: Date
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.subtitle = subtitle
        self.timeContext = timeContext
        self.icon = icon
        self.payload = payload
        self.referenceDate = referenceDate
    }
}

struct AttentionInbox {
    let items: [AttentionItem]

    var totalCount: Int { items.count }

    func items(in category: AttentionCategory) -> [AttentionItem] {
        items
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.referenceDate < rhs.referenceDate
            }
    }

    func count(in category: AttentionCategory) -> Int {
        items.filter { $0.category == category }.count
    }

    /// The single most-pressing item to surface at the top of the card.
    /// Severity wins, then "older" wins (a reminder overdue 3 days beats one
    /// overdue 1 day at the same severity).
    var mostUrgent: AttentionItem? {
        items.max { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.referenceDate > rhs.referenceDate
        }
    }
}

// MARK: - Computation
//
// v2: this is an ADAPTER over AttentionEngine (Services/, the shared rules
// layer). The card renders exactly what Mac Today, Whistle curation, and
// the widget writer see — edge-triggered, deadlined, small. The old
// level-triggered predicates (every unclosed session ever, every dormant
// client, every unplanned session in 14 days) are gone: close-outs are
// automated away by SessionLifecycle.autoClose, chronic states live in the
// Tier-3 reports (smart group, filters).

extension AttentionInbox {
    /// Build the inbox from the shared engine. Pure aggregation, no UI.
    @MainActor
    static func compute(from dm: DataManager, now: Date = Date()) -> AttentionInbox {
        let items = AttentionEngine.items(dataManager: dm, now: now).map { item in
            AttentionItem(
                category: category(for: item.category),
                severity: AttentionSeverity(rawValue: item.urgency) ?? .attention,
                title: item.title,
                subtitle: nil,
                timeContext: item.subtitle,
                icon: icon(for: item.kind),
                payload: payload(for: item),
                referenceDate: item.deadline
            )
        }
        return AttentionInbox(items: items)
    }

    private static func category(for category: AttentionEngine.Category) -> AttentionCategory {
        switch category {
        case .closeOut: return .closeOut
        case .reEngage: return .reEngage
        case .plan:     return .plan
        }
    }

    private static func icon(for kind: AttentionEngine.Kind) -> String {
        switch kind {
        case .planNeeded:       return "clipboard"
        case .rollCallRecovery: return "clock.badge.checkmark"
        case .renewalWindow:    return "exclamationmark.triangle.fill"
        case .newStudent:       return "person.crop.circle.badge.plus"
        case .reengage:         return "person.crop.circle.badge.clock"
        case .followUp:         return "text.bubble"
        case .reminderDue:      return "bell.badge.fill"
        }
    }

    private static func payload(for item: AttentionEngine.Item) -> AttentionPayload {
        if let sessionId = item.sessionId { return .session(sessionId) }
        if let studentId = item.studentId { return .student(studentId) }
        if let reminderId = item.reminderId { return .reminder(reminderId) }
        return .reminder(UUID())   // unreachable: every kind carries a ref
    }
}
