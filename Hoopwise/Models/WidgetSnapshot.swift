import Foundation

// MARK: - "Next Up" widget snapshot
//
// The widget never touches CloudKit/SwiftData — it renders this compact JSON
// from the App Group container, written by the app whenever relevant data
// changes. Pure Foundation: this file is a member of the iOS app, the Mac
// app, and the widget extension.

enum WidgetShared {
    static let appGroup = "group.OKTO.SAMp"
    static let snapshotFilename = "nextup-snapshot.json"
    static let widgetKind = "NextUpWidget"
    /// Older than this and the widget shows an "open app to refresh" footer.
    static let stalenessInterval: TimeInterval = 24 * 3600

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(snapshotFilename)
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

/// One source of truth for the "needs attention" thresholds — the widget's
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
}

struct NextUpSnapshot: Codable, Equatable {
    var generatedAt: Date
    /// Sessions inside the 48h horizon, ascending by start.
    var sessions: [NextUpSession]
    var highlight: NextUpStudent?

    var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > WidgetShared.stalenessInterval
    }

    /// The session to feature at a given instant: an in-progress session
    /// wins; otherwise the next future start; nil = rest day.
    func featuredSession(at date: Date) -> NextUpSession? {
        if let current = sessions.first(where: { $0.start <= date && date < $0.end }) {
            return current
        }
        return sessions.first { $0.start > date }
    }
}

struct NextUpSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var location: String?
}

struct NextUpStudent: Codable, Equatable {
    enum Reason: String, Codable {
        case noted, attention, streak

        /// The one-word chip.
        var chipLabel: String {
            switch self {
            case .noted: return "Noted"
            case .attention: return "Attendance"
            case .streak: return "Streak"
            }
        }
    }

    var id: UUID
    var name: String
    var chineseName: String?
    var initials: String
    var reason: Reason
    /// Tiny JPEG (≤ ~120px) for the medium widget; nil renders the monogram.
    var avatarJPEG: Data?
}
