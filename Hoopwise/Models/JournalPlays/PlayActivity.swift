import Foundation

// The play the coach is working on (November 2026, Home's play card).
// JournalPlay has no edit date and adding one is a schema change, so this
// device remembers the last play EDITED (the step editor's Done) and the last
// one OPENED (its page). Device-local, like the attention state: a play edited
// on the Mac is not "being worked on" on the phone.
enum PlayActivity {
    struct Mark: Codable, Equatable {
        let key: String
        let date: Date
    }

    private static let editedKey = "home.play.edited"
    private static let openedKey = "home.play.opened"

    @MainActor static func edited(_ play: JournalPlay) { write(Mark(key: play.planRef.key, date: .now), to: editedKey) }
    @MainActor static func opened(_ play: JournalPlay) { write(Mark(key: play.planRef.key, date: .now), to: openedKey) }

    static var lastEdited: Mark? { read(editedKey) }
    static var lastOpened: Mark? { read(openedKey) }

    /// What Home shows: a play edited in the last 7 days, else one opened in
    /// the last 3; `edited` says which.
    static func current(now: Date = .now) -> (mark: Mark, edited: Bool)? {
        if let e = lastEdited, now.timeIntervalSince(e.date) < 7 * 86_400 {
            if let o = lastOpened, o.key != e.key, o.date > e.date, now.timeIntervalSince(o.date) < 3 * 86_400,
               o.date.timeIntervalSince(e.date) > 86_400 {
                return (o, false)
            }
            return (e, true)
        }
        if let o = lastOpened, now.timeIntervalSince(o.date) < 3 * 86_400 { return (o, false) }
        return nil
    }

    private static func write(_ mark: Mark, to key: String) {
        if let data = try? JSONEncoder().encode(mark) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: .hoopwisePlayActivity, object: nil)
    }

    private static func read(_ key: String) -> Mark? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Mark.self, from: $0) }
    }
}

extension Notification.Name {
    static let hoopwisePlayActivity = Notification.Name("hoopwisePlayActivity")
    /// Not @AppStorage: Home writes UserDefaults while it draws (attention
    /// state), and an @AppStorage there redrew it forever.
    static let hoopwiseHomePins = Notification.Name("hoopwiseHomePins")
}

/// Teams pinned to Home (device-local, like the play activity).
enum HomePins {
    static let key = "home.pinnedTeams"

    static var teamIds: [UUID] {
        (UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    static func isPinned(_ id: UUID) -> Bool { teamIds.contains(id) }

    static func toggle(_ id: UUID) {
        var ids = teamIds
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        UserDefaults.standard.set(ids.map(\.uuidString).joined(separator: ","), forKey: key)
        NotificationCenter.default.post(name: .hoopwiseHomePins, object: nil)
    }
}
