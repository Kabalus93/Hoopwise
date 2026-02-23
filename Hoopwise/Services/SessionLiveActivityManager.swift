import Foundation
import SwiftUI
import Combine

#if os(iOS)
import ActivityKit

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
    
    // MARK: - Start Live Activity
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
        
        // End any existing activity first
        if currentActivity != nil {
            endActivity()
        }
        
        self.currentSession = session
        self.curriculum = session.curriculum
        self.drillNames = drillNames
        
        let attributes = SessionActivityAttributes(
            sessionId: session.id,
            sessionTitle: session.title,
            programName: programName,
            startTime: session.startTime,
            endTime: session.endTime,
            location: session.location,
            accentColorHex: accentColorHex
        )
        
        let initialState = calculateContentState(for: session)
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            
            currentActivity = activity
            isActivityActive = true
            
            // Start timer to update activity every 30 seconds
            startUpdateTimer()
            
            debugLog("✅ Live Activity started for session: \(session.title)")
        } catch {
            debugLog("❌ Failed to start Live Activity: \(error)")
        }
    }
    
    // MARK: - Update Live Activity
    func updateActivity() {
        guard let activity = currentActivity,
              let session = currentSession else { return }
        
        let newState = calculateContentState(for: session)
        
        Task {
            await activity.update(
                ActivityContent(state: newState, staleDate: nil)
            )
        }
    }
    
    // MARK: - End Live Activity
    func endActivity(showAttendanceReminder: Bool = true) {
        guard let activity = currentActivity else { return }
        
        stopUpdateTimer()
        
        let finalState = SessionActivityAttributes.ContentState(
            elapsedMinutes: currentSession?.durationMinutes ?? 0,
            totalMinutes: currentSession?.durationMinutes ?? 0,
            currentPhase: .completed,
            currentDrillName: nil,
            progress: 1.0,
            attendeeCount: currentSession?.actualAttendeeIds.count ?? 0
        )
        
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
            
            await MainActor.run {
                currentActivity = nil
                isActivityActive = false
                
                // Schedule attendance reminder notification
                if showAttendanceReminder {
                    scheduleAttendanceReminder()
                }
            }
        }
        
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
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }
}
#endif
