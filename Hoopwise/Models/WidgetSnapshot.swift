import Foundation

// MARK: - Widget snapshot (schema v2)
//
// The widgets never touch CloudKit/SwiftData — they render this compact JSON
// from the App Group container, written by the app whenever relevant data
// changes. Pure Foundation: member of the iOS app, the Mac app, and the
// widget extension.
//
// Versioning: v2 added today/tomorrow agendas, the attention list, the week
// map, and file-based photos. Every v2 field is optional so a v1 snapshot on
// disk still decodes — widgets degrade to v1 content, never crash or blank.

enum WidgetShared {
    static let appGroup = "group.OKTO.SAMp"
    static let snapshotFilename = "nextup-snapshot.json"
    static let photosDirectoryName = "WidgetPhotos"
    static let widgetKind = "NextUpWidget"            // legacy kind string
    static let todayKind = "TodayWidget"
    static let attentionKind = "AttentionWidget"
    static let cadenceKind = "CadenceWidget"
    static let allKinds = [widgetKind, todayKind, attentionKind, cadenceKind]
    /// Older than this and widgets show an "open app to refresh" footer.
    static let stalenessInterval: TimeInterval = 24 * 3600

    static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFilename)
    }

    static var photosDirectory: URL? {
        containerURL?.appendingPathComponent(photosDirectoryName, isDirectory: true)
    }

    static func photoURL(filename: String) -> URL? {
        photosDirectory?.appendingPathComponent(filename)
    }

    static func loadSnapshot() -> NextUpSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NextUpSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: NextUpSnapshot) {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// One source of truth for the "needs attention" thresholds — the widgets'
/// student selection, the Whistle's Today curation, and any future alert
/// surface must read these, never re-invent the numbers.
enum AttentionRules {
    /// A private bundle with this many redemptions left (or fewer) is "low".
    static let bundleLowRemaining = 3
    /// Attendance below this percent is a risk…
    static let attendanceRiskPercent = 50
    /// …but only once the student has this many relevant sessions.
    static let attendanceMinSessions = 4
    /// A coach note within this window makes the student "Noted".
    static let notedWindowDays = 14
    /// At or above this attendance (with the minimum sessions) a student
    /// counts as steady — the bubble cluster's small tier.
    static let steadyPercent = 80

    // MARK: v2 — attention is an action inside ~48h that changes an outcome.
    // Everything else is automated (Tier 1) or a report (Tier 3).

    /// Hours past a session's end before the system closes it unrecorded.
    static let autoCloseGraceHours = 12
    /// An auto-closed session younger than this surfaces ONE roll-call
    /// recovery item; older, it stops asking forever.
    static let recoveryWindowHours = 48
    /// RETIRED October 2026: "plan needed" no longer reaches attention.
    static let planWindowHours = 48
    /// Renewal window: bundle at or below this remaining (the last paid
    /// session, or none left)…
    static let renewalRemaining = 1
    /// …with a session scheduled within this many days (the conversation
    /// moment; that session is the deadline). Fires once per contract.
    static let renewalSessionWindowDays = 7
    /// RETIRED October 2026: "new student, no first session" no longer
    /// reaches attention.
    static let newStudentWindowDays = 14
    /// Re-engage fires on the EDGE of this many consecutive missed
    /// (marked absent or excused) sessions — "missed more than two"…
    static let reengageConsecutiveMisses = 3
    /// …at most once per athlete per cooldown.
    static let reengageCooldownDays = 14
    /// RETIRED October 2026: follow-ups surface on their due date, not ahead.
    static let followUpWindowHours = 48
    /// Display cap — a safety rail, not a target. If one rule alone
    /// regularly produces more than ~5 items, tune the rule, never the cap.
    static let displayCap = 9
}

struct NextUpSnapshot: Codable, Equatable {
    var generatedAt: Date
    /// v1: sessions inside the 48h horizon, ascending. Still written in v2
    /// (Next Up + degradation path read it).
    var sessions: [NextUpSession]
    var highlight: NextUpStudent?

    // MARK: v2 fields — all optional so v1 snapshots decode.
    var version: Int?
    /// ALL of today's non-cancelled sessions, including finished ones.
    var todaySessions: [NextUpSession]?
    var tomorrowSessions: [NextUpSession]?
    /// Top attention students, the shared-rules order, max 3.
    var attention: [NextUpStudent]?
    /// Current week, first-weekday-first: one cell per day.
    var weekMap: [WeekCell]?
    /// Roster-wide attendance over the trailing week — the quiet positive
    /// stat when nothing needs attention.
    var weeklyAttendancePercent: Int?
    /// Precomputed timeline windows: each carries its own featured session,
    /// highlight, and roster cluster, so rollover changes BOTH the session
    /// and the student at the boundary without the app waking.
    var windows: [NextUpWindow]?

    var schemaVersion: Int { version ?? 1 }

    var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > WidgetShared.stalenessInterval
    }

    /// The window covering an instant. Past the last window's end this is
    /// nil ON PURPOSE — the precomputed relevance has run out, and carrying
    /// the final window's student forward would present hours-stale data as
    /// current. Views render the rest/stale state instead (the snapshot is
    /// necessarily >24h old there, so the "open app to refresh" footer shows).
    func window(at date: Date) -> NextUpWindow? {
        guard let windows, !windows.isEmpty else { return nil }
        if let covering = windows.first(where: { $0.start <= date && date < $0.end }) {
            return covering
        }
        return date < windows.first!.start ? windows.first : nil
    }

    /// The session to feature at a given instant: an in-progress session
    /// wins; otherwise the next future start; nil = rest day.
    func featuredSession(at date: Date) -> NextUpSession? {
        if let current = sessions.first(where: { $0.start <= date && date < $0.end }) {
            return current
        }
        return sessions.first { $0.start > date }
    }

    /// Today's agenda with a v1 fallback (derive from the 48h horizon).
    func agendaToday(at date: Date, calendar: Calendar = .current) -> [NextUpSession] {
        if let today = todaySessions { return today }
        return sessions.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    func agendaTomorrow(at date: Date, calendar: Calendar = .current) -> [NextUpSession] {
        if let tomorrow = tomorrowSessions { return tomorrow }
        guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return [] }
        return sessions.filter { calendar.isDate($0.start, inSameDayAs: next) }
    }

    /// Attention list with a v1 fallback (the single highlight).
    var attentionList: [NextUpStudent] {
        if let attention { return attention }
        if let highlight, highlight.reason != .streak { return [highlight] }
        return []
    }

    /// Week map with a v1 fallback derived from the known horizon.
    func week(at date: Date, calendar: Calendar = .current) -> [WeekCell] {
        if let weekMap { return weekMap }
        let start = calendar.startOfDay(for: date)
        let weekdayOffset = (calendar.component(.weekday, from: start)
            - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: start)
        else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart)
            else { return nil }
            let count = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }.count
            return WeekCell(date: day, count: count)
        }
    }
}

struct NextUpSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var location: String?
    // v2
    var rosterCount: Int?
    /// "U14 · Phase 5" — the program line for the large agenda.
    var programLine: String?
    // v2.1: structured fields so widgets never parse titles.
    var ageBand: String?        // "U8"
    var category: String?       // "竞赛班"

    /// "U8 · 竞赛班", or the title when no program backs the session.
    var structuredLine: String? {
        let parts = [ageBand, category].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One member of a window's roster cluster. Tier is from the SAME shared
/// scoring as everything else: 0 = AttentionRules fires, 2 = steady
/// (≥ steadyPercent), 1 = neutral.
struct NextUpRosterMember: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var initials: String
    var photoFilename: String?
    var tier: Int
    var reason: NextUpStudent.Reason?
}

struct NextUpWindow: Codable, Equatable {
    var start: Date
    var end: Date
    var session: NextUpSession?
    var highlight: NextUpStudent?
    /// The featured session's roster, tier-sorted, capped at 8.
    var roster: [NextUpRosterMember]?
    var rosterTotal: Int?
}

struct WeekCell: Codable, Equatable, Hashable {
    var date: Date
    var count: Int
}

struct NextUpStudent: Codable, Equatable, Identifiable {
    enum Reason: String, Codable {
        case noted, attention, streak
        case bundle     // v2: bundle-low gets its own chip

        var chipLabel: String {
            switch self {
            case .noted: return "Noted"
            case .attention: return "Attendance"
            case .streak: return "Streak"
            case .bundle: return "Bundle"
            }
        }
    }

    var id: UUID
    var name: String
    var chineseName: String?
    var initials: String
    var reason: Reason
    /// v1 legacy: inline JPEG. v2 writes photoFilename instead.
    var avatarJPEG: Data?
    /// v2: file in AppGroup/WidgetPhotos — the only photo path the widget
    /// process reads.
    var photoFilename: String?

    // Tolerate unknown future reason strings instead of failing the decode.
    init(id: UUID, name: String, chineseName: String?, initials: String,
         reason: Reason, avatarJPEG: Data? = nil, photoFilename: String? = nil) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.initials = initials
        self.reason = reason
        self.avatarJPEG = avatarJPEG
        self.photoFilename = photoFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        chineseName = try container.decodeIfPresent(String.self, forKey: .chineseName)
        initials = try container.decode(String.self, forKey: .initials)
        let rawReason = try container.decodeIfPresent(String.self, forKey: .reason)
        reason = rawReason.flatMap(Reason.init(rawValue:)) ?? .attention
        avatarJPEG = try container.decodeIfPresent(Data.self, forKey: .avatarJPEG)
        photoFilename = try container.decodeIfPresent(String.self, forKey: .photoFilename)
    }
}
