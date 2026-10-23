import Foundation
import SwiftUI
import Combine
#if os(iOS)
import UserNotifications
#endif

// MARK: - Session Status Monitor
/// Monitors sessions and automatically transitions their status based on time
/// - scheduled → inProgress when startTime is reached
/// - inProgress → completed when endTime is reached
@MainActor
class SessionStatusMonitor: ObservableObject {
    static let shared = SessionStatusMonitor()

    private var timer: Timer?
    private var dataManager: DataManager?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Start Monitoring
    func startMonitoring(dataManager: DataManager) {
        self.dataManager = dataManager
        
        // Check immediately
        checkAndUpdateSessionStatuses()
        
        // Then check every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndUpdateSessionStatuses()
            }
        }
        
        debugLog("✅ SessionStatusMonitor started")
    }
    
    // MARK: - Stop Monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        debugLog("⏹️ SessionStatusMonitor stopped")
    }
    
    // MARK: - Check and Update Statuses
    //
    // AUTO-START (October 2026, Luther: "sessions start automatically when
    // the scheduled time arrives unless they are cancelled"). A scheduled
    // session whose start has arrived and whose end has not becomes
    // .inProgress through SessionLifecycle — a status change only; no
    // attendance is written. Skipped and cancelled sessions never start.
    //
    // It still NEVER auto-completes. The earlier wall-clock monitor completed
    // sessions on time and left "completed" classes nobody ran, with
    // phantom attendance; completion stays the coach's Complete Session
    // (which opens the roll-call photo) or the attention engine's marked
    // auto-close 12 hours after the end.
    //
    // On iOS the in-app engine follows the live session: it is brought up
    // for the session running now (Lock Screen activity per
    // SessionSeries.allowsLiveActivity, the pill and the home card), and
    // ended once that session is no longer in progress.
    private func checkAndUpdateSessionStatuses() {
        guard let dataManager = dataManager else { return }
        let now = Date()

        for session in dataManager.sessionEvents
        where SessionLifecycle.shouldAutoStart(session, at: now) {
            var started = session
            guard SessionLifecycle.apply(.start, to: &started) else { continue }
            dataManager.updateSessionEvent(started)
            debugLog("▶️ Auto-started session: \(session.title)")
        }

        let sessions = dataManager.sessionEvents

        #if os(iOS)
        if let running = LiveSessionEngine.shared.session,
           sessions.first(where: { $0.id == running.id })?.status != .inProgress {
            LiveSessionEngine.shared.end()
        }
        reconcileLiveActivities(sessions: sessions, dataManager: dataManager, now: now)
        if let live = sessions.first(where: {
            $0.status == .inProgress && $0.startTime <= now && now < $0.endTime
        }) {
            startInAppEngine(for: live, dataManager: dataManager)
        }

        // Reconcile scheduled local notifications with the current set of
        // upcoming sessions. Cheap: this just diffs already-pending requests
        // against future starts.
        reconcileSessionStartNotifications(sessions: sessions)
        #endif
    }

    // MARK: - Live Activity Integration
    #if os(iOS)
    /// Which classes get a Lock Screen / Dynamic Island activity (October
    /// 2026, Luther): one that is LIVE, or one starting within 10 minutes.
    /// Classes starting later today are scheduled — iOS puts them up at their
    /// T−10 even with the app closed. Everything else is taken down.
    #if DEBUG
    /// Set by the HOOPWISE_LIVE_ACTIVITY_DEMO hook: its scratch class is not
    /// in the store, so reconciliation would take it down.
    static var debugKeepDemoActivity = false
    #endif

    /// How far ahead classes are scheduled, and at most how many — iOS limits
    /// how many activities one app may hold.
    private static let scheduleHorizon: TimeInterval = 12 * 3600
    private static let maxScheduled = 4

    static func liveActivityTargets(sessions: [SessionEvent], now: Date,
                                    allows: (SessionEvent) -> Bool) -> [SessionEvent] {
        let horizon = now.addingTimeInterval(scheduleHorizon)
        return sessions
            .filter { ($0.status == .scheduled || $0.status == .inProgress)
                && !SessionLifecycle.didNotHappen($0)
                && $0.endTime > now
                && $0.startTime.addingTimeInterval(-SessionLiveActivityManager.leadTime) <= horizon
                && allows($0) }
            .sorted { $0.startTime < $1.startTime }
            .prefix(maxScheduled)
            .map { $0 }
    }

    private func reconcileLiveActivities(sessions: [SessionEvent], dataManager: DataManager, now: Date) {
        #if DEBUG
        if Self.debugKeepDemoActivity { return }
        #endif
        let targets = Self.liveActivityTargets(sessions: sessions, now: now) {
            SessionSeries.allowsLiveActivity($0,
                                             programs: dataManager.programs,
                                             contracts: dataManager.contracts,
                                             privateSessionsEnabled: SessionSeries.privateLiveActivityEnabled)
        }.map { session -> SessionLiveActivityManager.Target in
            let program = session.programId.flatMap { id in dataManager.programs.first { $0.id == id } }
            return .init(session: session,
                         programName: program?.resolvedDisplayName(in: dataManager.programs) ?? session.title,
                         accentColorHex: program?.colorHex ?? "#FF6B35")
        }
        SessionLiveActivityManager.shared.reconcile(targets: targets, now: now)
    }

    /// Bring up the in-app `LiveSessionEngine` so the persistent pill at
    /// the top of `MainTabView` and the live screen reflect a session that
    /// auto-started while the app was backgrounded. Engine ignores the call
    /// when it's already running for the same session, so this is safe to
    /// invoke every tick.
    private func startInAppEngine(for session: SessionEvent, dataManager: DataManager) {
        guard LiveSessionEngine.shared.session?.id != session.id else { return }

        let program = session.programId.flatMap { id in
            dataManager.programs.first(where: { $0.id == id })
        }

        // Build the drill ladder from the curriculum so the live screen
        // jumps to the right drill given how much wall-clock time has
        // already elapsed (handled inside the engine).
        let drills: [LiveDrillItem] = buildLiveDrillLadder(
            for: session,
            allDrills: dataManager.drills
        )

        let drillNames: [UUID: String] = Dictionary(
            uniqueKeysWithValues: dataManager.drills.map { ($0.id, $0.name) }
        )

        LiveSessionEngine.shared.start(
            session: session,
            drills: drills,
            programName: program?.resolvedDisplayName(in: dataManager.programs) ?? session.title,
            programColorHex: program?.colorHex ?? "#FF6B35",
            drillNames: drillNames,
            startsLiveActivity: SessionSeries.allowsLiveActivity(
                session,
                programs: dataManager.programs,
                contracts: dataManager.contracts,
                privateSessionsEnabled: SessionSeries.privateLiveActivityEnabled)
        )
    }

    /// Builds the drill ladder consumed by `LiveSessionEngine`. Mirrors what
    /// the live screen builds when manually started — keep these aligned.
    private func buildLiveDrillLadder(for session: SessionEvent, allDrills: [DrillItem]) -> [LiveDrillItem] {
        let curriculum = session.curriculum

        func phaseDrills(_ ids: [UUID], totalSeconds: Int, section: CurriculumSection) -> [LiveDrillItem] {
            guard !ids.isEmpty, totalSeconds > 0 else { return [] }
            let perDrill = max(60, totalSeconds / ids.count)
            return ids.compactMap { id -> LiveDrillItem? in
                guard let drill = allDrills.first(where: { $0.id == id }) else { return nil }
                return LiveDrillItem(drill: drill, section: section, durationSeconds: perDrill)
            }
        }

        return phaseDrills(curriculum.warmupDrillIds, totalSeconds: curriculum.warmupMinutes * 60, section: .warmup)
            + phaseDrills(curriculum.skillDrillIds,  totalSeconds: curriculum.skillsMinutes * 60, section: .main)
            + phaseDrills(curriculum.gameDrillIds,   totalSeconds: curriculum.gameMinutes * 60,   section: .cooldown)
    }

    // MARK: - Local notification scheduling

    /// Reconcile pending start-time local notifications with the current
    /// session list:
    /// - Adds a request for every future scheduled session that doesn't
    ///   already have one pending.
    /// - Cancels pending requests for sessions that no longer exist, were
    ///   cancelled, or whose `startTime` shifted (the new request goes in).
    /// Idempotent and cheap to call from the 30s tick.
    private func reconcileSessionStartNotifications(sessions: [SessionEvent]) {
        let center = UNUserNotificationCenter.current()
        let now = Date()

        // Targets: every session that's scheduled and starts in the future.
        let targets = sessions.filter { $0.status == .scheduled && $0.startTime > now }
        let targetIds = Set(targets.map { sessionStartIdentifier(for: $0.id) })

        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let pendingMap = Dictionary(uniqueKeysWithValues:
                pending
                    .filter { $0.identifier.hasPrefix(Self.startNotificationPrefix) }
                    .map { ($0.identifier, $0) }
            )
            let pendingIds = Set(pendingMap.keys)

            // Cancel orphans + start-time changes.
            let toCancel = pendingIds.subtracting(targetIds)
            // Also cancel any pending whose stored fireDate disagrees with
            // the live session's startTime — UNCalendarNotificationTrigger
            // doesn't expose `nextTriggerDate` ergonomically, so we match
            // by userInfo timestamp.
            let driftedIds: [String] = targets.compactMap { session in
                let id = self.sessionStartIdentifier(for: session.id)
                guard let req = pendingMap[id],
                      let stored = req.content.userInfo["startEpoch"] as? TimeInterval else { return nil }
                let drift = abs(session.startTime.timeIntervalSince1970 - stored)
                // A request from before the card design (no card category)
                // is replaced too, so pending starts pick up the new look.
                let stale = req.content.categoryIdentifier != NotificationCard.Kind.started.categoryIdentifier
                return drift > 5 || stale ? id : nil
            }
            let allCancellations = Array(toCancel) + driftedIds
            if !allCancellations.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: allCancellations)
            }

            // Add new + drifted requests.
            let needsScheduling = targets.filter { session in
                let id = self.sessionStartIdentifier(for: session.id)
                return !pendingIds.contains(id) || driftedIds.contains(id)
            }
            for session in needsScheduling {
                self.scheduleStartNotification(for: session)
            }
        }
    }

    private static let startNotificationPrefix = "session-start-"

    private func sessionStartIdentifier(for id: UUID) -> String {
        Self.startNotificationPrefix + id.uuidString
    }

    private func scheduleStartNotification(for session: SessionEvent) {
        let content = UNMutableNotificationContent()
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        content.sound = .default
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "startEpoch": session.startTime.timeIntervalSince1970
        ]
        NotificationCard.stamp(content, kind: .started,
                               headline: isChinese ? "该上课了" : "Time to coach",
                               detail: "\(session.title) · \(timeOnlyString(session.startTime))")

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: session.startTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: sessionStartIdentifier(for: session.id),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                debugLog("❌ Failed to schedule session-start notification: \(error)")
            }
        }
    }

    private func timeOnlyString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
    #endif
}
