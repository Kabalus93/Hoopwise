import Foundation
import Combine
import SwiftUI

// MARK: - Profile Audit Entry
struct ProfileAuditEntry: Identifiable, Codable {
    let id: UUID
    let studentId: UUID
    let coachId: UUID
    let coachName: String       // denormalized — no join needed on read
    let field: String           // e.g. "grade", "contract", "profile"
    let summary: String         // human-readable, e.g. "Updated grade to A"
    let changedAt: Date

    init(
        id: UUID = UUID(),
        studentId: UUID,
        coachId: UUID,
        coachName: String,
        field: String,
        summary: String,
        changedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.coachId = coachId
        self.coachName = coachName
        self.field = field
        self.summary = summary
        self.changedAt = changedAt
    }
}

// MARK: - Audit Logger
/// Lightweight local-only audit logger. Per-device; no cross-device sync.
/// Keeps entries <= 30 days in local cache.
final class AuditLogger: ObservableObject {
    static let shared = AuditLogger()

    // In-memory cache keyed by studentId: [entries], newest first
    @Published private var cache: [UUID: [ProfileAuditEntry]] = [:]

    private let storageKey = "profile_audit_cache_v1"

    private init() {
        loadFromDisk()
    }

    // MARK: - Write
    @MainActor
    func log(
        studentId: UUID,
        coachId: UUID,
        coachName: String,
        field: String,
        summary: String
    ) {
        let entry = ProfileAuditEntry(
            studentId: studentId,
            coachId: coachId,
            coachName: coachName,
            field: field,
            summary: summary
        )

        var entries = cache[studentId] ?? []
        entries.insert(entry, at: 0)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        entries = entries.filter { $0.changedAt >= cutoff }
        cache[studentId] = entries

        saveToDisk()
    }

    // MARK: - Read
    /// Returns cached entries for a student (already filtered to 30 days, newest first).
    func entries(for studentId: UUID) -> [ProfileAuditEntry] {
        cache[studentId] ?? []
    }

    // MARK: - Persistence
    @MainActor
    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    @MainActor
    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UUID: [ProfileAuditEntry]].self, from: data) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        cache = decoded.mapValues { $0.filter { $0.changedAt >= cutoff } }
    }
}
