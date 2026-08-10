import Foundation

// MARK: - AttentionRules v2 — the shared attention layer
//
// One principle: attention = an action the coach can take in the next
// 24–48h that changes an outcome. Everything else is either automated
// (Tier 1, below), or a report (Tier 3 — the smart group and filters).
//
// This file is the ONE home for that logic — the iOS Attention card, Mac
// Today, Whistle curation, and the widget writer all consume it. Threshold
// constants live in AttentionRules (Models/WidgetSnapshot.swift) so the
// widget process shares them.
//
// Edge/snooze/dismiss state is DEVICE-LOCAL (UserDefaults JSON — the
// smart-group-threshold precedent). It gates which items show, never what
// is true in the record, so two devices disagreeing costs nothing.

// MARK: - Attendance math (marked-only denominators)

/// The one attendance-rate definition attention decisions may use.
///
/// The denominator counts ONLY sessions where the student carries an
/// explicit mark (present / excused / unexcused). Unrecorded sessions —
/// auto-closed backlog or simply never-taken roll call — are EXCLUDED, so
/// closing 136 dead sessions cannot move anyone's percentage. Unmarked is
/// NOT absent, in statistics exactly as in money.
enum AttendanceMath {

    /// Expected roster: explicit attendees when set, else program enrollment
    /// (real sessions are created with empty attendeeIds).
    static func expectedIds(of session: SessionEvent, programs: [Program]) -> [UUID] {
        if !session.attendeeIds.isEmpty { return session.attendeeIds }
        if let programId = session.programId,
           let program = programs.first(where: { $0.id == programId }) {
            return program.enrolledStudentIds
        }
        return []
    }

    static func rate(for studentId: UUID, in sessions: [SessionEvent],
                     asOf now: Date = Date()) -> (percent: Int, of: Int) {
        var marked = 0, present = 0
        for session in sessions where session.date <= now && !SessionLifecycle.didNotHappen(session) {
            if session.actualAttendeeIds.contains(studentId) {
                marked += 1; present += 1
            } else if session.excusedAbsences.contains(studentId)
                        || session.unexcusedAbsences.contains(studentId) {
                marked += 1
            }
        }
        guard marked > 0 else { return (100, 0) }
        return (Int(Double(present) / Double(marked) * 100), marked)
    }

    /// Length of the most-recent run of marked sessions the student missed
    /// (excused or unexcused — three notified absences in a row still mean
    /// the engagement conversation is due).
    static func consecutiveMisses(for studentId: UUID, in sessions: [SessionEvent],
                                  asOf now: Date = Date()) -> Int {
        let marked = sessions
            .filter { session in
                session.date <= now && !SessionLifecycle.didNotHappen(session)
                    && (session.actualAttendeeIds.contains(studentId)
                        || session.excusedAbsences.contains(studentId)
                        || session.unexcusedAbsences.contains(studentId))
            }
            .sorted { $0.startTime > $1.startTime }
        var run = 0
        for session in marked {
            if session.actualAttendeeIds.contains(studentId) { break }
            run += 1
        }
        return run
    }
}

// MARK: - The engine

@MainActor
enum AttentionEngine {

    // MARK: Item model

    enum Category: String { case closeOut, reEngage, plan }

    enum Kind: String {
        case planNeeded, rollCallRecovery, renewalWindow
        case newStudent, reengage, followUp, reminderDue
    }

    /// 0 = fyi, 1 = attention, 2 = urgent — the inbox's existing ladder.
    struct Item: Identifiable {
        let key: String
        let kind: Kind
        let category: Category
        let title: String
        let subtitle: String
        let urgency: Int
        let deadline: Date
        var studentId: UUID?
        var sessionId: UUID?
        var reminderId: UUID?
        var id: String { key }
    }

    // MARK: Edge / snooze / dismiss state (device-local)

    struct State: Codable {
        var snoozedUntil: [String: Date] = [:]
        var dismissed: Set<String> = []
        var reengageLastFired: [UUID: Date] = [:]
        /// contractId → the deadline captured when the renewal edge fired.
        var renewalFired: [UUID: Date] = [:]
        var amnestyDone = false
        var amnestyClosedCount = 0
        var lastAutomationRun: Date?
    }

    private static let stateKey = "attention.state.v2"

    static func loadState() -> State {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    static func saveState(_ state: State) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    static func snooze(_ key: String, until date: Date) {
        var state = loadState()
        state.snoozedUntil[key] = date
        saveState(state)
    }

    /// Dismissal is PER-EDGE: keys embed the edge (session instance, fire
    /// date), so the same item returns only on a new edge.
    static func dismiss(_ key: String) {
        var state = loadState()
        state.dismissed.insert(key)
        saveState(state)
    }

    // MARK: - Tier 1 — automation

    struct AutomationResult {
        var closedNow = 0
        var amnestyClosed = 0
    }

    private static var automationInFlight = false
    private static var pendingAutomation: Task<Void, Never>?

    /// Debounced entry point, hooked into the data manager's refresh paths
    /// (app foreground and post-sync, both platforms) — the same rhythm as
    /// the widget snapshot writer. Refresh storms collapse to one run and
    /// the 5-minute throttle inside runAutomation breaks mutation loops.
    static func scheduleAutomation(dataManager: DataManager) {
        pendingAutomation?.cancel()
        pendingAutomation = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let dataManager else { return }
            runAutomation(dataManager: dataManager)
        }
    }

    /// Auto-closes every session past end + grace that nobody completed.
    /// Idempotent (closed sessions leave the predicate) and reentrancy-safe
    /// (it mutates sessions, which triggers cache refreshes, which call it
    /// again — the throttle breaks the loop).
    @discardableResult
    static func runAutomation(dataManager: DataManager,
                              now: Date = Date(),
                              force: Bool = false) -> AutomationResult {
        var result = AutomationResult()
        guard !automationInFlight else { return result }
        var state = loadState()
        if !force, let last = state.lastAutomationRun,
           now.timeIntervalSince(last) < 5 * 60 { return result }
        automationInFlight = true
        defer { automationInFlight = false }

        let grace = TimeInterval(AttentionRules.autoCloseGraceHours * 3600)
        let amnestyCutoff = now.addingTimeInterval(
            -TimeInterval(AttentionRules.recoveryWindowHours * 3600))
        let firstRun = !state.amnestyDone

        for session in dataManager.sessionEvents
        where session.endTime.addingTimeInterval(grace) < now
            && (session.status == .scheduled || session.status == .inProgress) {
            var updated = session
            guard SessionLifecycle.apply(.autoClose, to: &updated) else { continue }
            dataManager.updateSessionEvent(updated)
            result.closedNow += 1
            if firstRun && session.endTime < amnestyCutoff {
                result.amnestyClosed += 1
            }
        }

        if firstRun {
            state.amnestyDone = true
            state.amnestyClosedCount = result.amnestyClosed
        }
        state.lastAutomationRun = now
        saveState(state)
        return result
    }

    // MARK: The automation ledger

    struct LedgerEntry: Identifiable {
        let sessionId: UUID
        let title: String
        let sessionEnd: Date
        let closedAt: Date
        var id: UUID { sessionId }
    }

    /// What the system handled, newest first. Trust in automation comes
    /// from visibility: every entry is reversible via `reopen`.
    static func ledger(dataManager: DataManager, days: Int = 7,
                       now: Date = Date()) -> [LedgerEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(days * 24 * 3600))
        return dataManager.sessionEvents
            .filter { SessionLifecycle.wasAutoClosed($0) }
            .compactMap { session -> LedgerEntry? in
                let closedAt = autoCloseDate(of: session) ?? session.updatedAt
                guard closedAt >= cutoff else { return nil }
                return LedgerEntry(sessionId: session.id, title: session.title,
                                   sessionEnd: session.endTime, closedAt: closedAt)
            }
            .sorted { $0.closedAt > $1.closedAt }
    }

    static func reopen(sessionId: UUID, dataManager: DataManager) {
        guard var session = dataManager.sessionEvents.first(where: { $0.id == sessionId })
        else { return }
        // resetToScheduled strips the auto-close marker and preserves
        // whatever attendance exists.
        guard SessionLifecycle.apply(.resetToScheduled, to: &session) else { return }
        dataManager.updateSessionEvent(session)
    }

    private static func autoCloseDate(of session: SessionEvent) -> Date? {
        guard let notes = session.notes,
              let line = notes.split(separator: "\n")
                .first(where: { $0.hasPrefix(SessionLifecycle.autoCloseMarkerPrefix) })
        else { return nil }
        let stamp = line.dropFirst(SessionLifecycle.autoCloseMarkerPrefix.count)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(stamp))
    }

    // MARK: - Tier 2 — the attention list

    /// Every item satisfies: concrete action, deadline inside ~48h, and an
    /// edge. Aged-out, snoozed, and dismissed items are already filtered.
    /// Consumers cap DISPLAY at AttentionRules.displayCap; the count itself
    /// should naturally sit at 0–6 — if one rule alone regularly produces
    /// more than ~5, the rule is miscalibrated: tune it, never the cap.
    static func items(dataManager: DataManager, now: Date = Date()) -> [Item] {
        var state = loadState()
        var items: [Item] = []
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let dayStamp: (Date) -> String = { date in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }

        // 1. Plan needed — imminent sessions with an empty plan.
        let planHorizon = now.addingTimeInterval(TimeInterval(AttentionRules.planWindowHours * 3600))
        for session in dataManager.sessionEvents
        where session.status == .scheduled
            && session.startTime > now && session.startTime <= planHorizon
            && session.curriculum.totalDrillCount == 0 {
            items.append(Item(
                key: "plan:\(session.id)@\(Int(session.startTime.timeIntervalSince1970))",
                kind: .planNeeded, category: .plan,
                title: isChinese ? "排课 · \(session.title)" : "Plan · \(session.title)",
                subtitle: isChinese ? "开课前完成计划" : "Session starts \(relative(session.startTime, from: now))",
                urgency: session.startTime.timeIntervalSince(now) < 24 * 3600 ? 2 : 1,
                deadline: session.startTime,
                sessionId: session.id))
        }

        // 2. Roll-call recovery — auto-closed within the window, unrecorded.
        let recoveryCutoff = now.addingTimeInterval(
            -TimeInterval(AttentionRules.recoveryWindowHours * 3600))
        for session in dataManager.sessionEvents
        where SessionLifecycle.wasAutoClosed(session)
            && session.endTime >= recoveryCutoff
            && session.actualAttendeeIds.isEmpty
            && session.excusedAbsences.isEmpty
            && session.unexcusedAbsences.isEmpty {
            items.append(Item(
                key: "recovery:\(session.id)",
                kind: .rollCallRecovery, category: .closeOut,
                title: isChinese ? "补记点名 · \(session.title)" : "Record roll call · \(session.title)",
                subtitle: dayStamp(session.date),
                urgency: 2,
                deadline: session.endTime.addingTimeInterval(
                    TimeInterval(AttentionRules.recoveryWindowHours * 3600)),
                sessionId: session.id))
        }

        // 3. Renewal window — bundle low AND a session inside 7 days (the
        // conversation moment). Fires once per contract, on the edge.
        let renewalHorizon = now.addingTimeInterval(
            TimeInterval(AttentionRules.renewalSessionWindowDays * 24 * 3600))
        for contract in dataManager.contracts
        where contract.kind == .privateBundle && contract.status == .active
            && (contract.bundleRedemptionsRemaining ?? .max) <= AttentionRules.renewalRemaining {
            let student = dataManager.students.first { $0.id == contract.studentId }
            guard let student else { continue }
            if let firedDeadline = state.renewalFired[contract.id] {
                guard firedDeadline > now else { continue }   // aged out, never again
                items.append(renewalItem(contract: contract, student: student,
                                         deadline: firedDeadline, isChinese: isChinese))
            } else {
                let nextSession = dataManager.sessionEvents
                    .filter { $0.status == .scheduled && $0.startTime > now
                        && $0.startTime <= renewalHorizon
                        && AttendanceMath.expectedIds(of: $0, programs: dataManager.programs)
                            .contains(student.id) }
                    .min { $0.startTime < $1.startTime }
                guard let nextSession else { continue }
                state.renewalFired[contract.id] = nextSession.startTime
                items.append(renewalItem(contract: contract, student: student,
                                         deadline: nextSession.startTime, isChinese: isChinese))
            }
        }

        // 4. New student, no first session — recent enrollees only; a
        // months-old never-scheduled student is a report row, not a nag.
        let newCutoff = now.addingTimeInterval(
            -TimeInterval(AttentionRules.newStudentWindowDays * 24 * 3600))
        for student in dataManager.students where student.createdAt >= newCutoff {
            let hasUpcoming = dataManager.sessionEvents.contains { session in
                session.status == .scheduled && session.startTime > now
                    && AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
                        .contains(student.id)
            }
            guard !hasUpcoming else { continue }
            items.append(Item(
                key: "newstudent:\(student.id)",
                kind: .newStudent, category: .reEngage,
                title: isChinese ? "安排首课 · \(student.name)" : "Schedule first session · \(student.name)",
                subtitle: isChinese ? "新学员，还没有课" : "Enrolled \(relative(student.createdAt, from: now)), nothing scheduled",
                urgency: 1,
                deadline: student.createdAt.addingTimeInterval(
                    TimeInterval(AttentionRules.newStudentWindowDays * 24 * 3600)),
                studentId: student.id))
        }

        // 5. Attendance drop THIS WEEK — edge-triggered with cooldown.
        for student in dataManager.students {
            let misses = AttendanceMath.consecutiveMisses(
                for: student.id, in: dataManager.sessionEvents, asOf: now)
            guard misses >= AttentionRules.reengageConsecutiveMisses else { continue }
            let cooldown = TimeInterval(AttentionRules.reengageCooldownDays * 24 * 3600)
            let lastFired = state.reengageLastFired[student.id]
            let firedAt: Date
            if let lastFired, now.timeIntervalSince(lastFired) < cooldown {
                firedAt = lastFired
            } else {
                firedAt = now
                state.reengageLastFired[student.id] = now
            }
            let deadline = firedAt.addingTimeInterval(48 * 3600)
            guard deadline > now else { continue }   // fired, shown, aged out
            items.append(Item(
                key: "reengage:\(student.id)@\(dayStamp(firedAt))",
                kind: .reengage, category: .reEngage,
                title: isChinese ? "回访 · \(student.name)" : "Re-engage · \(student.name)",
                subtitle: isChinese ? "连续缺席 \(misses) 次" : "Missed \(misses) in a row",
                urgency: 2,
                deadline: deadline,
                studentId: student.id))
        }

        // 6. Note follow-up due — only because the field exists on
        // ParentalTouchpoint; if it were absent this rule would not.
        let followHorizon = now.addingTimeInterval(
            TimeInterval(AttentionRules.followUpWindowHours * 3600))
        for student in dataManager.students {
            for touchpoint in student.parentalTouchpoints
            where touchpoint.followUpNeeded {
                guard let due = touchpoint.followUpDate,
                      due <= followHorizon,
                      due.addingTimeInterval(24 * 3600) > now else { continue }
                items.append(Item(
                    key: "followup:\(student.id):\(dayStamp(due))",
                    kind: .followUp, category: .reEngage,
                    title: isChinese ? "跟进 · \(student.name)" : "Follow up · \(student.name)",
                    subtitle: touchpoint.notes ?? (isChinese ? "备注跟进" : "Note follow-up"),
                    urgency: due <= now ? 2 : 1,
                    deadline: due.addingTimeInterval(24 * 3600),
                    studentId: student.id))
            }
        }

        // 7. Reminders — coach-created deadlines keep flowing through, but
        // only inside the window; they age out of ATTENTION a week after
        // due (they still live in the reminders list itself).
        for reminder in dataManager.reminders where !reminder.isCompleted {
            let overdue = reminder.dueDate <= now
            guard reminder.dueDate <= followHorizon,
                  reminder.dueDate.addingTimeInterval(7 * 24 * 3600) > now else { continue }
            items.append(Item(
                key: "reminder:\(reminder.id)",
                kind: .reminderDue, category: overdue ? .closeOut : .plan,
                title: reminder.title,
                subtitle: overdue
                    ? (isChinese ? "已逾期" : "Overdue")
                    : (isChinese ? "待办" : "Due \(relative(reminder.dueDate, from: now))"),
                urgency: overdue ? 2 : 1,
                deadline: reminder.dueDate.addingTimeInterval(7 * 24 * 3600),
                reminderId: reminder.id))
        }

        saveState(state)

        // Age-out, snooze, dismiss — then urgency first, nearest deadline.
        return items
            .filter { $0.deadline > now }
            .filter { state.dismissed.contains($0.key) == false }
            .filter { (state.snoozedUntil[$0.key] ?? .distantPast) <= now }
            .sorted { lhs, rhs in
                lhs.urgency != rhs.urgency ? lhs.urgency > rhs.urgency
                    : lhs.deadline < rhs.deadline
            }
    }

    private static func renewalItem(contract: Contract, student: Student,
                                    deadline: Date, isChinese: Bool) -> Item {
        let remaining = contract.bundleRedemptionsRemaining ?? 0
        return Item(
            key: "renewal:\(contract.id)",
            kind: .renewalWindow, category: .reEngage,
            title: isChinese ? "续课 · \(student.name)" : "Renewal · \(student.name)",
            subtitle: isChinese ? "剩余 \(remaining) 节，下次课前谈" : "\(remaining) left — talk at the next session",
            urgency: remaining <= 1 ? 2 : 1,
            deadline: deadline,
            studentId: student.id)
    }

    private static func relative(_ date: Date, from now: Date) -> String {
        let hours = Int(abs(date.timeIntervalSince(now)) / 3600)
        if hours < 1 { return "soon" }
        if hours < 48 { return date > now ? "in \(hours)h" : "\(hours)h ago" }
        let days = hours / 24
        return date > now ? "in \(days)d" : "\(days)d ago"
    }
}
