import Foundation
import CloudKit
import CoreData
import Combine

/// Observes the CloudKit sync that SwiftData performs on our behalf and makes it
/// legible to the UI on both platforms.
///
/// SwiftData has no public sync-status API, but its CloudKit integration is backed by
/// `NSPersistentCloudKitContainer`, which posts `eventChangedNotification` for every
/// setup / import / export it runs — including the failures that are otherwise silent.
/// Listening to that notification is the only way to surface sync errors today, and
/// surfacing them is the point: CloudKit problems on this project have historically been
/// invisible rather than loud.
///
/// This type only observes. It never triggers sync — SwiftData owns that — so there is
/// deliberately no `sync()` method to call. See `refreshAccountStatus()` for the one
/// thing the UI can meaningfully ask for on demand.
@MainActor
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    /// The one and only container. Never use `CKContainer.default()`: it resolves to
    /// `iCloud.{bundleID}`, which exists for neither target.
    static let containerIdentifier = "iCloud.com.hoopwise.Hoopwise"

    private static let lastSyncDefaultsKey = "lastCloudKitSyncDate"

    /// What SwiftData's CloudKit mirror is doing right now.
    enum Activity: Equatable {
        case idle
        case settingUp
        case importing
        case exporting

        var label: String {
            switch self {
            case .idle:      return "Idle"
            case .settingUp: return "Setting up"
            case .importing: return "Downloading"
            case .exporting: return "Uploading"
            }
        }
    }

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isCheckingAccount = false

    var isSyncing: Bool { activity != .idle }

    /// Which CloudKit database this build talks to. Development and Production hold
    /// entirely separate data, so a debug build and a TestFlight build never see each
    /// other's records — the single most common false alarm on this project.
    var environmentLabel: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private let container = CKContainer(identifier: CloudSyncMonitor.containerIdentifier)
    private var observers: [NSObjectProtocol] = []

    private init() {
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDefaultsKey) as? Date
        startObserving()
    }

    deinit {
        // Captured locally so the cleanup doesn't hop back to the main actor from deinit.
        let tokens = observers
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Observation

    private func startObserving() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.handleCloudKitEvent(note)
                }
            }
        )

        // Fires when the user signs in or out of iCloud at the system level.
        observers.append(
            center.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refreshAccountStatus() }
                }
            }
        )
    }

    private func handleCloudKitEvent(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        // A nil endDate means the event is still running.
        guard event.endDate != nil else {
            activity = Self.activity(for: event.type)
            return
        }

        activity = .idle

        if let error = event.error {
            lastErrorMessage = Self.describe(error)
            debugLog("☁️❌ CloudKit \(Self.activity(for: event.type).label) failed: \(error)")
            return
        }

        guard event.succeeded else { return }

        lastErrorMessage = nil

        // Only a completed import or export means data actually moved. A successful
        // setup just means we connected, which is not a sync.
        if event.type == .import || event.type == .export {
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncDefaultsKey)
            debugLog("☁️✅ CloudKit \(Self.activity(for: event.type).label) finished")
        }
    }

    private static func activity(for type: NSPersistentCloudKitContainer.EventType) -> Activity {
        switch type {
        case .setup:  return .settingUp
        case .import: return .importing
        case .export: return .exporting
        @unknown default: return .idle
        }
    }

    // MARK: - Account Status

    /// Re-reads the iCloud account status. This is what a "Check iCloud" button should
    /// call — it verifies the account this build can actually reach, which is the useful
    /// question. It does not and cannot force a sync.
    func refreshAccountStatus() async {
        isCheckingAccount = true
        defer { isCheckingAccount = false }

        do {
            accountStatus = try await container.accountStatus()
            debugLog("☁️ iCloud account status: \(Self.describe(accountStatus))")
        } catch {
            accountStatus = .couldNotDetermine
            lastErrorMessage = Self.describe(error)
            debugLog("☁️❌ Failed to read iCloud account status: \(error)")
        }
    }

    // MARK: - Display Helpers

    var accountStatusLabel: String { Self.describe(accountStatus) }

    /// Nil when there is nothing the user needs to act on.
    var accountStatusAdvice: String? {
        switch accountStatus {
        case .available:
            return nil
        case .noAccount:
            return "Sign in to iCloud in System Settings. A developer Apple ID in Xcode is not a system iCloud account."
        case .restricted:
            return "iCloud is restricted on this device."
        case .couldNotDetermine:
            return "Could not reach iCloud."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Reconnecting…"
        @unknown default:
            return "Could not reach iCloud."
        }
    }

    var lastSyncLabel: String {
        guard let lastSyncDate else { return "Never" }
        return lastSyncDate.formatted(.relative(presentation: .numeric))
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:              return "Signed in"
        case .noAccount:              return "No iCloud account"
        case .restricted:             return "Restricted"
        case .couldNotDetermine:      return "Unavailable"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default:             return "Unavailable"
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }

        switch ckError.code {
        case .notAuthenticated:
            return "Not signed in to iCloud."
        case .networkUnavailable, .networkFailure:
            return "No network connection to iCloud."
        case .quotaExceeded:
            return "iCloud storage quota exceeded."
        case .managedAccountRestricted:
            return "This managed Apple ID restricts iCloud."
        case .permissionFailure:
            return "iCloud permission denied for this container."
        default:
            return ckError.localizedDescription
        }
    }
}
