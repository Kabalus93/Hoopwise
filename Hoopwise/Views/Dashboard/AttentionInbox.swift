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

extension AttentionInbox {
    /// Threshold for flagging a private-bundle client as dormant. Set per
    /// design call: the coach typically sees a private-bundle student
    /// roughly once a fortnight, so 14 days without contact is the point
    /// where re-engagement is genuinely warranted.
    static let dormancyDays: Int = 14

    /// Build the inbox from the live data manager. Pure aggregation, no UI.
    @MainActor
    static func compute(from dm: DataManager, now: Date = Date()) -> AttentionInbox {
        var items: [AttentionItem] = []

        let cal = Calendar.current
        let isCN = LocalizationManager.shared.currentLanguage == .chinese

        // ---------- CLOSE OUT ----------

        // Past sessions still in .scheduled or .inProgress — coach forgot
        // to close them. Severity grows with how long ago they ended.
        for session in dm.sessionEvents
            where session.endTime < now &&
                  (session.status == .scheduled || session.status == .inProgress) {
            let hoursPast = Int(now.timeIntervalSince(session.endTime) / 3600)
            let severity: AttentionSeverity = hoursPast >= 24 ? .urgent : .attention
            let title = session.title
            let subtitle = dm.programs
                .first(where: { $0.id == session.programId })?
                .resolvedDisplayName(in: dm.programs)
            let timeContext: String = {
                let mins = Int(now.timeIntervalSince(session.endTime) / 60)
                if mins < 60 {
                    return isCN ? "\(mins) 分钟前结束" : "ended \(mins)m ago"
                }
                let hours = mins / 60
                if hours < 24 {
                    return isCN ? "\(hours) 小时前结束" : "ended \(hours)h ago"
                }
                let days = hours / 24
                return isCN ? "\(days) 天前结束" : "ended \(days)d ago"
            }()
            items.append(AttentionItem(
                category: .closeOut,
                severity: severity,
                title: title,
                subtitle: subtitle,
                timeContext: timeContext,
                icon: "clock.badge.checkmark",
                payload: .session(session.id),
                referenceDate: session.endTime
            ))
        }

        // Overdue reminders — coach intended to handle these by their due
        // date and didn't.
        for reminder in dm.overdueReminders {
            items.append(AttentionItem(
                category: .closeOut,
                severity: .urgent,
                title: reminder.title,
                subtitle: nil,
                timeContext: reminder.relativeTimeString,
                icon: "bell.badge.fill",
                payload: .reminder(reminder.id),
                referenceDate: reminder.dueDate
            ))
        }

        // ---------- RE-ENGAGE ----------

        // Private-bundle clients running low on sessions. Urgent at ≤1,
        // attention at 2-3. PAYG and group contracts are excluded —
        // there's no inherent quota to flag.
        for student in dm.students {
            guard let contract = dm.currentContract(for: student.id),
                  contract.kind == .privateBundle else { continue }
            let remaining = contract.bundleRedemptionsRemaining ?? .max
            guard remaining <= 3 else { continue }
            let severity: AttentionSeverity = remaining <= 1 ? .urgent : .attention
            items.append(AttentionItem(
                category: .reEngage,
                severity: severity,
                title: student.name,
                subtitle: isCN ? "私教剩余" : "private bundle",
                timeContext: isCN
                    ? "剩 \(remaining) 节课"
                    : "\(remaining) session\(remaining == 1 ? "" : "s") left",
                icon: "exclamationmark.triangle.fill",
                payload: .student(student.id),
                referenceDate: contract.expiryDate ?? now.addingTimeInterval(TimeInterval(remaining * 86400))
            ))
        }

        // Dormant private clients: active private contract (any kind), but
        // they haven't been an `actualAttendeeIds` member in the dormancy
        // window. Group / school students are excluded — group cadence is
        // managed at the program level.
        let cutoff = cal.date(byAdding: .day, value: -dormancyDays, to: now) ?? now
        // Index by student → most recent attended session date.
        var lastAttendance: [UUID: Date] = [:]
        for session in dm.sessionEvents where session.status == .completed || session.endTime < now {
            for studentId in session.actualAttendeeIds {
                let prior = lastAttendance[studentId]
                if prior == nil || session.endTime > prior! {
                    lastAttendance[studentId] = session.endTime
                }
            }
        }
        for student in dm.students {
            guard let contract = dm.currentContract(for: student.id) else { continue }
            // Only re-engage private clients — group billing is school/co.
            guard contract.format == .privateClient else { continue }
            // Skip if they've been seen recently.
            if let last = lastAttendance[student.id], last >= cutoff { continue }
            // Skip if they have no past sessions tracked at all AND were
            // just enrolled — they're new, not dormant.
            let hasAnyPast = lastAttendance[student.id] != nil
            let createdRecently = student.createdAt >= cutoff
            if !hasAnyPast && createdRecently { continue }

            let daysSince: Int = {
                if let last = lastAttendance[student.id] {
                    return Int(now.timeIntervalSince(last) / 86400)
                }
                // Never attended — measure from enrollment.
                return Int(now.timeIntervalSince(student.createdAt) / 86400)
            }()
            // Avoid double-flagging students already in the low-bundle list.
            let alreadyFlagged = items.contains { item in
                if case .student(let id) = item.payload, id == student.id { return true }
                return false
            }
            if alreadyFlagged { continue }

            items.append(AttentionItem(
                category: .reEngage,
                severity: daysSince >= 30 ? .urgent : .attention,
                title: student.name,
                subtitle: isCN ? "近期未到场" : "no recent attendance",
                timeContext: lastAttendance[student.id] == nil
                    ? (isCN ? "尚未参加过课程" : "no sessions yet")
                    : (isCN ? "\(daysSince) 天未到" : "\(daysSince) days dormant"),
                icon: "person.crop.circle.badge.clock",
                payload: .student(student.id),
                referenceDate: lastAttendance[student.id] ?? student.createdAt
            ))
        }

        // ---------- PLAN ----------

        // Sessions in next two weeks with no curriculum drills set.
        let twoWeeks = cal.date(byAdding: .day, value: 14, to: now) ?? now
        for session in dm.sessionEvents where session.date >= now &&
                                              session.date <= twoWeeks &&
                                              session.status == .scheduled &&
                                              session.curriculum.totalDrillCount == 0 {
            let title = session.title
            let when: String = {
                if cal.isDateInToday(session.date)    { return isCN ? "今天" : "Today" }
                if cal.isDateInTomorrow(session.date) { return isCN ? "明天" : "Tomorrow" }
                let days = cal.dateComponents([.day], from: now, to: session.date).day ?? 0
                return isCN ? "\(days) 天后" : "in \(days)d"
            }()
            items.append(AttentionItem(
                category: .plan,
                severity: cal.isDateInToday(session.date) ? .urgent : .attention,
                title: title,
                subtitle: isCN ? "尚未排课" : "no drills planned",
                timeContext: when,
                icon: "clipboard",
                payload: .session(session.id),
                referenceDate: session.date
            ))
        }

        // Active programs with no phases AND upcoming sessions.
        for program in dm.programs where program.status == .active || program.status == .draft {
            let phases = dm.microCycles.filter { $0.programId == program.id }
            guard phases.isEmpty else { continue }
            let upcoming = dm.sessionEvents.contains { s in
                s.programId == program.id && s.date >= now && s.date <= twoWeeks
            }
            guard upcoming || (program.startDate ?? .distantFuture) <= twoWeeks else { continue }
            items.append(AttentionItem(
                category: .plan,
                severity: .attention,
                title: program.resolvedDisplayName(in: dm.programs),
                subtitle: isCN ? "尚无阶段" : "no phases set",
                timeContext: nil,
                icon: "rectangle.stack.badge.plus",
                payload: .program(program.id),
                referenceDate: program.startDate ?? now
            ))
        }

        // Upcoming reminders — gentle FYI, lowest severity.
        for reminder in dm.upcomingReminders {
            items.append(AttentionItem(
                category: .plan,
                severity: .fyi,
                title: reminder.title,
                subtitle: nil,
                timeContext: reminder.relativeTimeString,
                icon: "bell",
                payload: .reminder(reminder.id),
                referenceDate: reminder.dueDate
            ))
        }

        return AttentionInbox(items: items)
    }
}
