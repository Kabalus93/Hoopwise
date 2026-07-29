import Foundation
import Combine

// MARK: - Sync Status (per-record)
// Attached to every syncable SwiftData model so the UI can show sync state.
enum SyncStatus: String, Codable {
    case synced    // Matches server
    case pending   // Local change not yet flushed
    case conflict  // Server and local diverged; needs resolution
}

// MARK: - Sync Table Registry
// Maps logical table names to their metadata for the sync engine.
enum SyncTable: String, CaseIterable {
    case students       = "students"
    case sessionEvents  = "session_events"
    case contracts      = "contracts"
    case staffCoaches   = "staff_coaches"
    case programs       = "programs"
    case microCycles    = "micro_cycles"
    case players        = "players"
    case drills         = "drills"
    case measurements   = "measurements"
    case reminders      = "reminders"

    var timestampColumn: String {
        switch self {
        case .measurements: return "recorded_at"
        default:            return "updated_at"
        }
    }
}

// MARK: - Mutation Kind
enum MutationKind: String, Codable {
    case insert
    case update
    case delete
}

// MARK: - Realtime Namespace
// One WebSocket channel per namespace — not per table.
enum RealtimeNamespace {
    case academy(UUID)       // students, enrollments, staff_coaches, programs
    case coach(UUID)         // session_events, micro_cycles, drills, schedules
    case contracts(UUID)     // contracts for a student

    var channelName: String {
        switch self {
        case .academy(let id):   return "academy:\(id.uuidString)"
        case .coach(let id):     return "coach:\(id.uuidString)"
        case .contracts(let id): return "contracts:\(id.uuidString)"
        }
    }

    /// Tables that belong to this namespace.
    var tables: [SyncTable] {
        switch self {
        case .academy:   return [.students, .staffCoaches, .programs, .players, .measurements]
        case .coach:     return [.sessionEvents, .microCycles, .drills, .reminders]
        case .contracts: return [.contracts]
        }
    }
}

// MARK: - Sync Error
enum SyncError: Error, LocalizedError {
    case networkUnavailable
    case conflict(table: String, recordId: UUID)
    case unauthorized
    case serverError(Int, String)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case queueFull
    case fatalError(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network unavailable — changes queued for retry"
        case .conflict(let table, let id):
            return "Conflict on \(table) record \(id.uuidString.prefix(8))"
        case .unauthorized:
            return "Session expired — please sign in again"
        case .serverError(let code, let msg):
            return "Server error \(code): \(msg)"
        case .encodingFailed(let err):
            return "Failed to encode: \(err.localizedDescription)"
        case .decodingFailed(let err):
            return "Failed to decode: \(err.localizedDescription)"
        case .queueFull:
            return "Sync queue is full — please try again later"
        case .fatalError(let msg):
            return msg
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable:
            return true
        case .serverError(let code, _) where (500...599).contains(code):
            return true
        case .conflict:
            return true  // Re-enqueue after merge
        default:
            return false
        }
    }
}

// MARK: - Merge Strategy
enum MergeStrategy {
    case serverWinsOnConflict
    case clientWinsOnConflict
    case fieldLevel  // Future: per-field merge
}

// MARK: - Sync State (observable by UI)
@MainActor
final class SyncState: ObservableObject {
    @Published var pendingCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var lastError: SyncError?
    @Published var failedOperations: [FailedOperation] = []

    struct FailedOperation: Identifiable {
        let id: UUID
        let table: String
        let operation: MutationKind
        let errorMessage: String
        let timestamp: Date
    }

    func clearError() {
        lastError = nil
    }

    func removeFailedOperation(_ id: UUID) {
        failedOperations.removeAll { $0.id == id }
    }
}
