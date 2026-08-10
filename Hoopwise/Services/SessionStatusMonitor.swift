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
    // Session status is owned by the coach. The monitor only:
    //   • reconciles scheduled local notifications for upcoming sessions, and
    //   • (iOS) keeps the in-app live engine in sync if a session is *already*
    //     marked .inProgress (e.g. coach tapped Start, then backgrounded).
    //
    // It deliberately does NOT auto-flip status on time. A session that the
    // coach never starts must remain .scheduled — silently completing it on
    // wall-clock time corrupts attendance history (see: a session shows up
    // as completed with phantom attendance even though the coach never ran
    // it). The only writers of `.inProgress` and `.completed` are the
    // explicit Start / Complete actions in `FlightySessionPageView`.
    private func checkAndUpdateSessionStatuses() {
        guard let dataManager = dataManager else { return }

        let sessions = dataManager.sessionEvents

        // Reconcile scheduled local notifications with the current set of
        // upcoming sessions. Cheap: this just diffs already-pending requests
        // against future starts.
        #if os(iOS)
        reconcileSessionStartNotifications(sessions: sessions)
        #endif
    }
    
    // MARK: - Live Activity Integration
    #if os(iOS)
    private func startLiveActivity(for session: SessionEvent, dataManager: DataManager) {
        guard let programId = session.programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
            return
        }
        // Phase 2.2: an explicit rule, not a side effect of privateness being
        // encoded as "no program". Group-shaped programs always raise one;
        // private sessions are a preference, defaulting off.
        guard SessionSeries.allowsLiveActivity(
            session,
            programs: dataManager.programs,
            contracts: dataManager.contracts,
            privateSessionsEnabled: SessionSeries.privateLiveActivityEnabled) else {
            return
        }
        
        // Build drill names dictionary
        var drillNames: [UUID: String] = [:]
        for drillId in session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds + session.curriculum.gameDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drillNames[drillId] = drill.name
            }
        }
        
        SessionLiveActivityManager.shared.startActivity(
            for: session,
            programName: program.name,
            accentColorHex: program.colorHex,
            drillNames: drillNames
        )
    }
    
    private func endLiveActivity() {
        SessionLiveActivityManager.shared.endActivity(showAttendanceReminder: true)
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
            drillNames: drillNames
        )
    }

    private func endInAppEngineIfMatches(session: SessionEvent) {
        if LiveSessionEngine.shared.session?.id == session.id {
            LiveSessionEngine.shared.end()
        }
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
                return drift > 5 ? id : nil
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
        content.title = isChinese ? "课程开始" : "Session started"
        content.body = isChinese
            ? "\(session.title) · \(timeOnlyString(session.startTime))"
            : "\(session.title) · \(timeOnlyString(session.startTime))"
        content.sound = .default
        content.categoryIdentifier = "SESSION_STARTED"
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "startEpoch": session.startTime.timeIntervalSince1970
        ]

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
    
    // MARK: - Manual Session Control
    func startSession(_ session: SessionEvent) {
        guard let dataManager = dataManager else { return }
        
        var updatedSession = session
        updatedSession.status = .inProgress
        dataManager.updateSessionEvent(updatedSession)
        
        #if os(iOS)
        startLiveActivity(for: updatedSession, dataManager: dataManager)
        #endif
        
        debugLog("▶️ Manually started session: \(session.title)")
    }
    
    func completeSession(_ session: SessionEvent) {
        guard let dataManager = dataManager else { return }
        
        var updatedSession = session
        updatedSession.status = .completed
        dataManager.updateSessionEvent(updatedSession)
        
        #if os(iOS)
        endLiveActivity()
        #endif

        debugLog("✅ Manually completed session: \(session.title)")
    }
}
