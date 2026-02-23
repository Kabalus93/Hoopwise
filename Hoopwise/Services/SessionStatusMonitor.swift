import Foundation
import SwiftUI
import Combine

// MARK: - Session Status Monitor
/// Monitors sessions and automatically transitions their status based on time
/// - scheduled → inProgress when startTime is reached
/// - inProgress → completed when endTime is reached
@MainActor
class SessionStatusMonitor: ObservableObject {
    static let shared = SessionStatusMonitor()
    
    @Published var showAttendanceReminder = false
    @Published var completedSession: SessionEvent?
    
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
    private func checkAndUpdateSessionStatuses() {
        guard let dataManager = dataManager else { return }
        
        let now = Date()
        let sessions = dataManager.sessionEvents
        
        for session in sessions {
            var updatedSession = session
            var shouldUpdate = false
            
            // Scheduled → In Progress (when start time is reached)
            if session.status == .scheduled && now >= session.startTime && now < session.endTime {
                updatedSession.status = .inProgress
                shouldUpdate = true
                debugLog("🟠 Auto-transitioning session '\(session.title)' to IN PROGRESS")
                
                // Start Live Activity if on iOS
                #if os(iOS)
                startLiveActivity(for: updatedSession, dataManager: dataManager)
                #endif
            }
            
            // In Progress → Completed (when end time is reached)
            else if session.status == .inProgress && now >= session.endTime {
                updatedSession.status = .completed
                shouldUpdate = true
                debugLog("🟢 Auto-transitioning session '\(session.title)' to COMPLETED")
                
                // End Live Activity and show attendance reminder
                #if os(iOS)
                endLiveActivity()
                #endif
                
                // Show attendance reminder if no photo taken yet
                if session.attendancePhotoPath == nil {
                    showAttendanceReminderSheet(for: updatedSession)
                }
            }
            
            if shouldUpdate {
                dataManager.updateSessionEvent(updatedSession)
            }
        }
    }
    
    // MARK: - Live Activity Integration
    #if os(iOS)
    private func startLiveActivity(for session: SessionEvent, dataManager: DataManager) {
        guard let programId = session.programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
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
    #endif
    
    // MARK: - Attendance Reminder
    private func showAttendanceReminderSheet(for session: SessionEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.completedSession = session
            self.showAttendanceReminder = true
            HapticFeedback.notification(.success)
        }
    }
    
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
        
        // Show attendance reminder if no photo
        if session.attendancePhotoPath == nil {
            showAttendanceReminderSheet(for: updatedSession)
        }
        
        debugLog("✅ Manually completed session: \(session.title)")
    }
}
