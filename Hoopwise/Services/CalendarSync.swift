import Foundation
#if os(iOS)
import EventKit
import UIKit
#endif

// MARK: - Sessions in Apple Calendar (October 2026, Luther)
//
// One-way: Hoopwise writes its sessions into a calendar of its own, named
// "Hoopwise", on the phone. The coach switches it on in Profile →
// Notifications; nothing is written before that, and switching it off removes
// the calendar (it only ever holds Hoopwise's events).
//
// - WHICH sessions: from 7 days ago to 60 days ahead, every session that
//   happens (skipped and cancelled ones are taken OUT — the calendar shows
//   where the coach must be).
// - IDENTITY is the event's URL, hoopwise://session/<id> — the same link the
//   widgets open. No local id table: a phone reinstalled, or a second device
//   whose iCloud calendar already has the events, finds them by URL and
//   updates them instead of adding copies (and removes any copy it finds).
// - It runs after every cache refresh, debounced, like the widget snapshot,
//   so a moved, renamed or cancelled session follows within a second.
//
// `plan` is pure (tested); `apply` is the EventKit half and needs a device.
// Member of both targets (rule 1); only the iOS app calls it.

enum CalendarSync {

    static let enabledKey = "calendarSync.enabled"
    static let calendarIdKey = "calendarSync.calendarId"
    static var calendarTitle: String { isLocalTest ? "Hoopwise (test)" : "Hoopwise" }

    /// DEBUG, env HOOPWISE_CALENDAR_LOCAL=1: the simulators are signed into the
    /// coach's iCloud, so agent runs write a phone-only "Hoopwise (test)"
    /// calendar in the LOCAL source and never touch iCloud; …=remove deletes
    /// it. The enabled flag is forced on for the run.
    static var isLocalTest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["HOOPWISE_CALENDAR_LOCAL"] != nil
        #else
        return false
        #endif
    }
    static let pastWindow: TimeInterval = 7 * 86_400
    static let futureWindow: TimeInterval = 60 * 86_400

    static var isEnabled: Bool {
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["HOOPWISE_CALENDAR_LOCAL"] { return mode != "remove" }
        #endif
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// What one session looks like in the calendar.
    struct Entry: Equatable {
        let sessionId: UUID
        var title: String
        var start: Date
        var end: Date
        var location: String?
        var notes: String?

        var url: URL { URL(string: "hoopwise://session/\(sessionId.uuidString)")! }
    }

    /// An event already in the Hoopwise calendar.
    struct Existing: Equatable {
        let eventId: String
        /// nil when the event is not one of ours (no hoopwise URL).
        let sessionId: UUID?
        var title: String
        var start: Date
        var end: Date
        var location: String?
        var notes: String?

        func matches(_ e: Entry) -> Bool {
            title == e.title && start == e.start && end == e.end
                && (location ?? "") == (e.location ?? "") && (notes ?? "") == (e.notes ?? "")
        }
    }

    struct Changes: Equatable {
        var create: [Entry] = []
        var update: [(eventId: String, entry: Entry)] = []
        var delete: [String] = []
        var isEmpty: Bool { create.isEmpty && update.isEmpty && delete.isEmpty }

        static func == (a: Changes, b: Changes) -> Bool {
            a.create == b.create && a.delete == b.delete
                && a.update.map(\.eventId) == b.update.map(\.eventId)
                && a.update.map(\.entry) == b.update.map(\.entry)
        }
    }

    static func sessionId(from url: URL?) -> UUID? {
        guard let url, url.scheme == "hoopwise", url.host == "session" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// The sessions that belong in the calendar, as entries.
    static func entries(sessions: [SessionEvent], programs: [Program], now: Date = Date()) -> [Entry] {
        let from = now.addingTimeInterval(-pastWindow), to = now.addingTimeInterval(futureWindow)
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return sessions
            .filter { !SessionLifecycle.didNotHappen($0) && $0.startTime >= from && $0.startTime <= to }
            .sorted { $0.startTime < $1.startTime }
            .map { s in
                let expected = AttendanceMath.expectedIds(of: s, programs: programs).count
                var lines: [String] = []
                if expected > 0 { lines.append(isChinese ? "\(expected) 名球员" : "\(expected) players") }
                let plan = s.curriculum.totalDrillCount
                if plan > 0 { lines.append(isChinese ? "训练计划：\(plan) 项活动" : "Plan: \(plan) activities") }
                lines.append(isChinese ? "在 Hoopwise 中打开" : "Open in Hoopwise")
                let location = s.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                return Entry(sessionId: s.id, title: s.title,
                             start: s.startTime, end: max(s.endTime, s.startTime.addingTimeInterval(60)),
                             location: (location?.isEmpty ?? true) ? nil : location,
                             notes: lines.joined(separator: "\n"))
            }
    }

    /// Create what is missing, update what changed, delete what no longer
    /// belongs (a session gone, cancelled, out of the window, a copy, or an
    /// event that is not ours).
    static func plan(desired: [Entry], existing: [Existing]) -> Changes {
        var changes = Changes()
        var byId: [UUID: Existing] = [:]
        for e in existing {
            guard let id = e.sessionId, byId[id] == nil else {
                changes.delete.append(e.eventId)        // not ours, or a duplicate
                continue
            }
            byId[id] = e
        }
        let wanted = Set(desired.map(\.sessionId))
        for (id, e) in byId where !wanted.contains(id) { changes.delete.append(e.eventId) }
        for entry in desired {
            if let e = byId[entry.sessionId] {
                if !e.matches(entry) { changes.update.append((e.eventId, entry)) }
            } else {
                changes.create.append(entry)
            }
        }
        changes.delete.sort()
        return changes
    }

    #if os(iOS)
    // MARK: - EventKit

    private static let store = EKEventStore()
    @MainActor private static var pending: Task<Void, Never>?

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks for calendar access (full access: the app must find and update
    /// its own events later, which write-only access cannot).
    static func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Debounced, like the widget snapshot.
    @MainActor
    static func scheduleSync(dataManager: DataManager) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let dataManager else { return }
            syncNow(dataManager: dataManager)
        }
    }

    @MainActor
    @discardableResult
    static func syncNow(dataManager: DataManager, now: Date = Date()) -> Changes? {
        guard isEnabled, hasAccess, let calendar = hoopwiseCalendar(create: true) else { return nil }
        let from = now.addingTimeInterval(-pastWindow), to = now.addingTimeInterval(futureWindow + 86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
        let existing = events.map {
            Existing(eventId: $0.eventIdentifier, sessionId: sessionId(from: $0.url), title: $0.title ?? "",
                     start: $0.startDate, end: $0.endDate, location: $0.location, notes: $0.notes)
        }
        let desired = entries(sessions: dataManager.sessionEvents, programs: dataManager.programs, now: now)
        let changes = plan(desired: desired, existing: existing)
        guard !changes.isEmpty else { return changes }
        let byId = Dictionary(events.map { ($0.eventIdentifier ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        for id in changes.delete { if let e = byId[id] { try? store.remove(e, span: .thisEvent, commit: false) } }
        for (id, entry) in changes.update {
            if let e = byId[id] { fill(e, entry); try? store.save(e, span: .thisEvent, commit: false) }
        }
        for entry in changes.create {
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            fill(e, entry)
            try? store.save(e, span: .thisEvent, commit: false)
        }
        try? store.commit()
        debugLog("📅 Calendar sync: +\(changes.create.count) ~\(changes.update.count) -\(changes.delete.count)")
        return changes
    }

    /// Switching off: the Hoopwise calendar goes, with only its own events.
    static func removeCalendar() {
        guard hasAccess, let calendar = hoopwiseCalendar(create: false) else { return }
        try? store.removeCalendar(calendar, commit: true)
        UserDefaults.standard.removeObject(forKey: isLocalTest ? calendarIdKey + ".test" : calendarIdKey)
    }

    /// DEBUG hook body: sync now, or remove the test calendar.
    @MainActor
    static func runLocalTestIfRequested(dataManager: DataManager) {
        #if DEBUG
        guard let mode = ProcessInfo.processInfo.environment["HOOPWISE_CALENDAR_LOCAL"] else { return }
        if mode == "remove" { removeCalendar(); debugLog("📅 test calendar removed"); return }
        let changes = syncNow(dataManager: dataManager)
        debugLog("📅 test sync: \(changes.map { "+\($0.create.count) ~\($0.update.count) -\($0.delete.count)" } ?? "nothing (no access or no local source)")")
        #endif
    }

    private static func fill(_ e: EKEvent, _ entry: Entry) {
        e.title = entry.title
        e.startDate = entry.start
        e.endDate = entry.end
        e.location = entry.location
        e.notes = entry.notes
        e.url = entry.url
    }

    /// Ours by stored id, else by title (a calendar another device created
    /// through iCloud), else a new one — in iCloud when the phone has it, so
    /// it appears on the coach's other devices, else on the phone.
    private static func hoopwiseCalendar(create: Bool) -> EKCalendar? {
        let idKey = isLocalTest ? calendarIdKey + ".test" : calendarIdKey
        if let id = UserDefaults.standard.string(forKey: idKey),
           let calendar = store.calendar(withIdentifier: id), calendar.title == calendarTitle { return calendar }
        if let found = store.calendars(for: .event)
            .first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(found.calendarIdentifier, forKey: idKey)
            return found
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = UIColor(red: 0.12, green: 0.23, blue: 0.55, alpha: 1).cgColor   // brand navy
        let sources = store.sources
        if isLocalTest {
            calendar.source = sources.first { $0.sourceType == .local }
        } else {
            calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
                ?? store.defaultCalendarForNewEvents?.source
                ?? sources.first { $0.sourceType == .local }
        }
        guard calendar.source != nil, (try? store.saveCalendar(calendar, commit: true)) != nil else {
            debugLog("📅 Calendar sync: no writable calendar source")
            return nil
        }
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: idKey)
        return calendar
    }
    #endif
}
