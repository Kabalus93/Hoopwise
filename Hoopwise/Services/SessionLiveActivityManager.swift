import Foundation
import SwiftUI
import Combine

#if os(iOS)
import ActivityKit
import BackgroundTasks

// SessionActivityAttributes and SessionPhase are defined in Models/SessionActivityAttributes.swift
// That file must be added to BOTH the main app and widget extension targets

// MARK: - Live Activity Manager (iOS only)
@MainActor
class SessionLiveActivityManager: ObservableObject {
    static let shared = SessionLiveActivityManager()
    
    @Published private(set) var currentActivity: Activity<SessionActivityAttributes>?
    @Published private(set) var isActivityActive = false
    
    private var updateTimer: Timer?
    private var currentSession: SessionEvent?
    private var curriculum: SessionCurriculum?
    private var drillNames: [UUID: String] = [:]
    
    private init() {}
    
    // MARK: - When an activity is on screen (October 2026, Luther)
    //
    // An activity exists for exactly two kinds of class:
    //   1. a class that is LIVE — it counts down the time left;
    //   2. a class starting within `leadTime` (10 min) — it counts down to
    //      the start, then switches to (1) by itself.
    // Anything else must not be on screen. iOS 26 schedules the start
    // (`request(…, start:)`), so (2) appears with the app closed; the switch
    // to (1) is the stale-date redraw at the start time. iOS gives an app no
    // way to END an activity at a set time, so a class that ends while the
    // app is closed is cleared on the next app run or background refresh
    // (`endFinished`, scheduled for the end time).
    static let leadTime: TimeInterval = 10 * 60

    /// One class that should have an activity now or at its lead time.
    struct Target {
        let session: SessionEvent
        let programName: String
        let accentColorHex: String
    }

    /// Every activity this app has, including scheduled (pending) ones.
    private var allActivities: [Activity<SessionActivityAttributes>] {
        Activity<SessionActivityAttributes>.activities.filter {
            $0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// THE reconciliation. Makes the app's activities exactly `targets`:
    /// ends every other one at once, replaces one that went up too early
    /// (an older build armed classes hours ahead, frozen at full length), and
    /// requests or schedules the missing ones.
    func reconcile(targets: [Target], now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let wanted = Dictionary(targets.map { ($0.session.id, $0) }, uniquingKeysWith: { a, _ in a })

        for activity in allActivities {
            let id = activity.attributes.sessionId
            let tooEarly = activity.activityState != .pending
                && now < activity.attributes.startTime.addingTimeInterval(-Self.leadTime)
            if wanted[id] == nil || tooEarly || activity.attributes.endTime <= now {
                dismiss(activity)
            }
        }

        let kept = Set(allActivities.map(\.attributes.sessionId))
        for target in targets where !kept.contains(target.session.id) {
            request(target, now: now)
        }
        scheduleCleanup(at: targets.map(\.session.endTime).min())
    }

    /// Ends every activity whose class is over. Needs no data — the end
    /// time travels in the attributes — so it can run in a background
    /// refresh before anything is loaded.
    func endFinished(now: Date = Date()) {
        for activity in allActivities where activity.attributes.endTime <= now {
            dismiss(activity)
        }
    }

    private func dismiss(_ activity: Activity<SessionActivityAttributes>) {
        if currentActivity?.id == activity.id {
            stopUpdateTimer()
            currentActivity = nil
            isActivityActive = false
        }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func attributes(for target: Target) -> SessionActivityAttributes {
        SessionActivityAttributes(
            sessionId: target.session.id,
            sessionTitle: target.session.title,
            programName: target.programName,
            startTime: target.session.startTime,
            endTime: target.session.endTime,
            location: target.session.location,
            accentColorHex: target.accentColorHex
        )
    }

    /// Redraw at the start (upcoming → live), and once more at the end.
    private func content(for session: SessionEvent, now: Date) -> ActivityContent<SessionActivityAttributes.ContentState> {
        ActivityContent(state: calculateContentState(for: session),
                        staleDate: now < session.startTime ? session.startTime : session.endTime)
    }

    @discardableResult
    private func request(_ target: Target, now: Date) -> Activity<SessionActivityAttributes>? {
        let session = target.session
        let showFrom = session.startTime.addingTimeInterval(-Self.leadTime)
        do {
            let activity: Activity<SessionActivityAttributes>
            if now >= showFrom {
                activity = try Activity.request(attributes: attributes(for: target),
                                                content: content(for: session, now: now),
                                                pushType: nil)
            } else {
                let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                let alert = AlertConfiguration(
                    title: LocalizedStringResource(stringLiteral: isChinese ? "10 分钟后上课" : "Class in 10 minutes"),
                    body: LocalizedStringResource(stringLiteral: target.programName),
                    sound: .default)
                activity = try Activity.request(attributes: attributes(for: target),
                                                content: content(for: session, now: showFrom),
                                                pushType: nil,
                                                style: .standard,
                                                alertConfiguration: alert,
                                                start: showFrom)
            }
            debugLog("✅ Live Activity \(now >= showFrom ? "started" : "scheduled for \(showFrom)") — \(session.title)")
            return activity
        } catch {
            debugLog("❌ Live Activity request failed: \(error)")
            return nil
        }
    }

    // MARK: - Background cleanup at the class's end
    static let cleanupTaskId = "com.hoopwise.liveactivity.cleanup"

    /// Asks iOS for a background refresh at the earliest class end so a
    /// finished class's activity is removed without opening the app. iOS
    /// decides when it actually runs (usually within minutes, never early).
    private func scheduleCleanup(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.cleanupTaskId)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.cleanupTaskId)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - The live class (in-app engine)
    /// Called by the in-app engine for the class running now: makes sure its
    /// activity exists and keeps phase / drill / headcount current while the
    /// app runs.
    func startActivity(
        for session: SessionEvent,
        programName: String,
        accentColorHex: String = "#FF6B35",
        drillNames: [UUID: String] = [:]
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugLog("⚠️ Live Activities are not enabled")
            return
        }
        self.currentSession = session
        self.curriculum = session.curriculum
        self.drillNames = drillNames

        let existing = allActivities.first { $0.attributes.sessionId == session.id }
        let activity = existing ?? request(Target(session: session, programName: programName,
                                                   accentColorHex: accentColorHex), now: Date())
        guard let activity else { return }
        currentActivity = activity
        isActivityActive = true
        updateActivity()
        stopUpdateTimer()
        startUpdateTimer()
    }
    
    // MARK: - Update Live Activity
    func updateActivity() {
        guard let activity = currentActivity,
              let session = currentSession else { return }
        let newContent = content(for: session, now: Date())
        Task { await activity.update(newContent) }
    }

    /// The session the live activity shows, if any.
    var activeSessionId: UUID? {
        currentActivity?.attributes.sessionId
    }

    // MARK: - End Live Activity
    /// Ends the live class's activity — it leaves the screen at once.
    func endActivity(showAttendanceReminder: Bool = true) {
        guard let activity = currentActivity else { return }
        dismiss(activity)
        if showAttendanceReminder { scheduleAttendanceReminder() }
        debugLog("✅ Live Activity ended")
    }
    
    // MARK: - Calculate Content State
    private func calculateContentState(for session: SessionEvent) -> SessionActivityAttributes.ContentState {
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(session.startTime))
        let total = session.endTime.timeIntervalSince(session.startTime)
        let elapsedMinutes = Int(elapsed / 60)
        let totalMinutes = Int(total / 60)
        let progress = min(1.0, max(0.0, elapsed / total))
        
        // Determine current phase based on elapsed time
        let curriculum = session.curriculum
        let warmupEnd = curriculum.warmupMinutes
        let skillsEnd = warmupEnd + curriculum.skillsMinutes
        let gameEnd = skillsEnd + curriculum.gameMinutes
        
        let (phase, drillName) = determinePhaseAndDrill(
            elapsedMinutes: elapsedMinutes,
            warmupEnd: warmupEnd,
            skillsEnd: skillsEnd,
            gameEnd: gameEnd,
            curriculum: curriculum
        )
        
        return SessionActivityAttributes.ContentState(
            elapsedMinutes: elapsedMinutes,
            totalMinutes: totalMinutes,
            currentPhase: phase,
            currentDrillName: drillName,
            progress: progress,
            attendeeCount: session.actualAttendeeIds.count
        )
    }
    
    private func determinePhaseAndDrill(
        elapsedMinutes: Int,
        warmupEnd: Int,
        skillsEnd: Int,
        gameEnd: Int,
        curriculum: SessionCurriculum
    ) -> (SessionPhase, String?) {
        var phase: SessionPhase
        var drillIds: [UUID]
        var phaseStart: Int
        var phaseEnd: Int
        
        if elapsedMinutes < warmupEnd {
            phase = .warmup
            drillIds = curriculum.warmupDrillIds
            phaseStart = 0
            phaseEnd = warmupEnd
        } else if elapsedMinutes < skillsEnd {
            phase = .skills
            drillIds = curriculum.skillDrillIds
            phaseStart = warmupEnd
            phaseEnd = skillsEnd
        } else if elapsedMinutes < gameEnd {
            phase = .game
            drillIds = curriculum.gameDrillIds
            phaseStart = skillsEnd
            phaseEnd = gameEnd
        } else {
            phase = .cooldown
            return (phase, nil)
        }
        
        // Calculate which drill we're on within the phase
        guard !drillIds.isEmpty else { return (phase, nil) }
        
        let phaseElapsed = elapsedMinutes - phaseStart
        let phaseDuration = phaseEnd - phaseStart
        let drillDuration = phaseDuration / drillIds.count
        let drillIndex = min(drillIds.count - 1, phaseElapsed / max(1, drillDuration))
        
        let drillId = drillIds[drillIndex]
        let drillName = drillNames[drillId]
        
        return (phase, drillName)
    }
    
    // MARK: - Timer Management
    /// Fire once per minute. Time-based UI (countdown, progress bar) is
    /// driven by `Text(timerInterval:)` and `ProgressView(timerInterval:)`
    /// inside the widget, which auto-tick locally — these state pushes only
    /// carry phase/drill/attendee changes.
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateActivity()
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Attendance Reminder
    private func scheduleAttendanceReminder() {
        let content = UNMutableNotificationContent()
        content.title = LocalizationManager.shared.currentLanguage == .chinese ? "课程已结束" : "Session Completed"
        content.body = LocalizationManager.shared.currentLanguage == .chinese 
            ? "别忘了记录今天的出勤情况！" 
            : "Don't forget to take attendance for today's session!"
        content.sound = .default
        content.categoryIdentifier = "ATTENDANCE_REMINDER"
        
        // Show notification after 5 seconds
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "attendance-reminder-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                debugLog("❌ Failed to schedule attendance reminder: \(error)")
            } else {
                debugLog("✅ Attendance reminder scheduled")
            }
        }
    }
    
    // MARK: - Update Attendee Count
    func updateAttendeeCount(_ count: Int) {
        guard var state = currentActivity?.content.state else { return }
        state.attendeeCount = count
        
        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: currentActivity?.content.staleDate)
            )
        }
    }
}
#endif
