import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - Sync Log Entry

enum SyncDirection: String, Codable {
    case upload   // Device → Cloud
    case download // Cloud → Device
}

struct SyncLogEntry: Identifiable, Codable {
    let id: UUID
    let direction: SyncDirection
    let table: String       // e.g. "students", "programs"
    let displayName: String // Human-readable, e.g. "Athletes"
    let count: Int          // Number of new records synced
    let timestamp: Date
    let deviceName: String

    init(
        id: UUID = UUID(),
        direction: SyncDirection,
        table: String,
        displayName: String,
        count: Int,
        timestamp: Date = Date(),
        deviceName: String = SyncLogStore.currentDeviceName
    ) {
        self.id = id
        self.direction = direction
        self.table = table
        self.displayName = displayName
        self.count = count
        self.timestamp = timestamp
        self.deviceName = deviceName
    }
}

// MARK: - Sync Session
/// Groups all entries from a single sync run
struct SyncSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var entries: [SyncLogEntry]
    var completedAt: Date?

    var uploadEntries: [SyncLogEntry] { entries.filter { $0.direction == .upload && $0.count > 0 } }
    var downloadEntries: [SyncLogEntry] { entries.filter { $0.direction == .download && $0.count > 0 } }
    var totalUploaded: Int { uploadEntries.reduce(0) { $0 + $1.count } }
    var totalDownloaded: Int { downloadEntries.reduce(0) { $0 + $1.count } }
    var hadActivity: Bool { totalUploaded > 0 || totalDownloaded > 0 }

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.entries = []
    }
}

// MARK: - Sync Log Store

@MainActor
class SyncLogStore: ObservableObject {
    static let shared = SyncLogStore()

    @Published private(set) var sessions: [SyncSession] = []

    private let storageKey = "hoopwise_sync_log_v1"
    private let maxSessions = 50
    private var currentSession: SyncSession?

    nonisolated static var currentDeviceName: String {
        ProcessInfo.processInfo.hostName
    }

    private init() { load() }

    // MARK: - Session Lifecycle

    func beginSession() {
        currentSession = SyncSession()
    }

    func endSession() {
        guard var session = currentSession else { return }
        session.completedAt = Date()
        if session.hadActivity {
            sessions.insert(session, at: 0)
            if sessions.count > maxSessions {
                sessions = Array(sessions.prefix(maxSessions))
            }
            save()
        }
        currentSession = nil
    }

    // MARK: - Logging

    func logUpload(table: String, displayName: String, count: Int) {
        guard count > 0 else { return }
        let entry = SyncLogEntry(direction: .upload, table: table, displayName: displayName, count: count)
        currentSession?.entries.append(entry)
    }

    func logDownload(table: String, displayName: String, count: Int) {
        guard count > 0 else { return }
        let entry = SyncLogEntry(direction: .download, table: table, displayName: displayName, count: count)
        currentSession?.entries.append(entry)
    }

    // MARK: - Accessors

    var uploadSessions: [SyncSession] { sessions.filter { $0.totalUploaded > 0 } }
    var downloadSessions: [SyncSession] { sessions.filter { $0.totalDownloaded > 0 } }

    var lastUploadDate: Date? {
        sessions.first { $0.totalUploaded > 0 }?.completedAt
    }

    var lastDownloadDate: Date? {
        sessions.first { $0.totalDownloaded > 0 }?.completedAt
    }

    func clearLog() {
        sessions = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SyncSession].self, from: data) else { return }
        sessions = decoded
    }
}
