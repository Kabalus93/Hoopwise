import Foundation

/// A play in a session's plan (`SessionCurriculum.plays`).
///
/// JournalPlay has no stored id, and adding one is a schema change (rule 5),
/// so a play is found by what already syncs: its starter key, else the
/// moment it was created (to the millisecond — CloudKit keeps dates to the
/// millisecond, so the creating device and the others read the same key).
/// The name is kept for a play that is gone: the plan still says what was
/// run, and the row says the play is no longer in the library.
nonisolated struct SessionPlayRef: Codable, Hashable, Sendable {
    var key: String
    var name: String

    static func starterKey(_ key: String) -> String { "starter:\(key)" }

    static func createdKey(_ date: Date) -> String {
        "created:\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
    }

    /// Whether this names a play with that starter key or creation date.
    /// A creation date matches within a millisecond either way: one device
    /// rounds its full-precision date, another reads CloudKit's.
    func matches(starterKey: String?, createdAt: Date) -> Bool {
        if let starterKey, key == Self.starterKey(starterKey) { return true }
        guard key.hasPrefix("created:"), let ms = Int64(key.dropFirst("created:".count)) else { return false }
        let mine = Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        return abs(mine - ms) <= 1
    }
}

extension JournalPlay {
    /// How a session plan names this play.
    var planRef: SessionPlayRef {
        SessionPlayRef(key: starterKey.map(SessionPlayRef.starterKey) ?? SessionPlayRef.createdKey(createdAt), name: name)
    }

    func isNamed(by ref: SessionPlayRef) -> Bool {
        ref.matches(starterKey: starterKey, createdAt: createdAt)
    }
}
