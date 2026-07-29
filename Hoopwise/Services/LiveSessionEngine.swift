import Foundation
import Combine
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Live Drill Item
struct LiveDrillItem: Identifiable {
    let id = UUID()
    let drill: DrillItem
    let section: CurriculumSection
    let durationSeconds: Int

    var sectionColor: Color {
        switch section {
        case .warmup: return Color.accentColor
        case .main: return Color.accentColor
        case .cooldown: return .green
        }
    }
}

// MARK: - Live Session Engine
/// Singleton state for an in-progress live session. Owns the timer, drill
/// progression, and pause state — so the live screen can be dismissed and
/// re-entered without losing tick state, and so a persistent banner anywhere
/// in the app can reflect what's happening.
@MainActor
final class LiveSessionEngine: ObservableObject {
    static let shared = LiveSessionEngine()

    // MARK: Published state

    /// The session being run. Mutations during the live run (notes, drills
    /// completed) are written here and persisted on `end()`.
    @Published var session: SessionEvent?

    /// Cached drill ladder built from the session's curriculum + drill catalog.
    @Published var drills: [LiveDrillItem] = []

    @Published var currentDrillIndex: Int = 0
    @Published var sessionElapsedSeconds: Int = 0
    @Published var drillElapsedSeconds: Int = 0
    @Published var isPaused: Bool = false

    /// Set once when the 5-minute mark hits so the roll-call sheet doesn't
    /// re-open every tick. Cleared on `end()`.
    @Published var rollCallPromptPending: Bool = false
    private var rollCallTriggered: Bool = false

    /// Whether a session is currently active (banner visibility).
    var isActive: Bool { session != nil }

    /// Snapshot used to decorate the banner / Live Activity.
    @Published var programName: String = ""
    @Published var programColorHex: String = "#007AFF"

    private var timer: Timer?

    private init() {}

    // MARK: - Lifecycle

    func start(session: SessionEvent,
               drills: [LiveDrillItem],
               programName: String,
               programColorHex: String,
               drillNames: [UUID: String]) {
        // Already running for the same session? No-op.
        if self.session?.id == session.id { return }

        // Stop any prior session first.
        if self.session != nil { hardReset() }

        self.session = session
        self.drills = drills
        self.programName = programName
        self.programColorHex = programColorHex

        // Anchor elapsed time to wall clock so an auto-started or
        // mid-session-resumed engine shows the truth, not "0:00 in".
        // If the session is being started before its `startTime` (manual
        // early start), elapsed begins at 0.
        let secondsSinceStart = max(0, Int(Date().timeIntervalSince(session.startTime)))

        self.sessionElapsedSeconds = secondsSinceStart
        self.currentDrillIndex = drillIndex(forElapsedSeconds: secondsSinceStart, drills: drills)
        self.drillElapsedSeconds = drillOffset(forElapsedSeconds: secondsSinceStart, drills: drills)
        self.isPaused = false
        self.rollCallTriggered = false
        self.rollCallPromptPending = false

        startTimer()

        #if os(iOS)
        SessionLiveActivityManager.shared.startActivity(
            for: session,
            programName: programName,
            accentColorHex: programColorHex,
            drillNames: drillNames
        )
        #endif
    }

    /// Mid-flight resync if the underlying session record changed (e.g.,
    /// attendance taken, notes updated) without restarting.
    func updateSessionSnapshot(_ updated: SessionEvent) {
        guard session?.id == updated.id else { return }
        session = updated
    }

    func end() {
        defer { hardReset() }
        #if os(iOS)
        SessionLiveActivityManager.shared.endActivity(showAttendanceReminder: false)
        #endif
    }

    private func hardReset() {
        timer?.invalidate()
        timer = nil
        session = nil
        drills = []
        currentDrillIndex = 0
        sessionElapsedSeconds = 0
        drillElapsedSeconds = 0
        isPaused = false
        rollCallTriggered = false
        rollCallPromptPending = false
    }

    // MARK: - Controls

    func togglePause() { isPaused.toggle() }

    func nextDrill() {
        guard currentDrillIndex < drills.count - 1 else { return }
        if let id = drills[safe: currentDrillIndex]?.drill.id,
           var s = session,
           !s.drillsCompleted.contains(id) {
            s.drillsCompleted.append(id)
            session = s
        }
        currentDrillIndex += 1
        drillElapsedSeconds = 0
    }

    func previousDrill() {
        guard currentDrillIndex > 0 else { return }
        currentDrillIndex -= 1
        drillElapsedSeconds = 0
    }

    func jump(to index: Int) {
        guard drills.indices.contains(index) else { return }
        currentDrillIndex = index
        drillElapsedSeconds = 0
    }

    /// Mark roll-call as handled (acknowledged or completed) so the prompt
    /// won't fire again this session.
    func dismissRollCallPrompt() {
        rollCallPromptPending = false
        rollCallTriggered = true
    }

    // MARK: - Derived

    var totalSessionSeconds: Int {
        (session?.curriculum.totalMinutes ?? 0) * 60
    }

    var sessionRemainingSeconds: Int {
        max(0, totalSessionSeconds - sessionElapsedSeconds)
    }

    var sessionProgress: Double {
        guard totalSessionSeconds > 0 else { return 0 }
        return min(Double(sessionElapsedSeconds) / Double(totalSessionSeconds), 1.0)
    }

    var currentDrill: LiveDrillItem? {
        drills[safe: currentDrillIndex]
    }

    // MARK: - Wall-clock anchoring

    /// Walks the drill ladder to find which drill is active given the
    /// number of session seconds that have elapsed. Used when the engine
    /// is auto-started mid-session so the live screen lands on the right
    /// drill instead of always restarting at drill 0.
    private func drillIndex(forElapsedSeconds elapsed: Int, drills: [LiveDrillItem]) -> Int {
        guard !drills.isEmpty else { return 0 }
        var cursor = 0
        for (i, drill) in drills.enumerated() {
            cursor += drill.durationSeconds
            if elapsed < cursor { return i }
        }
        return drills.count - 1
    }

    /// Seconds into the *current* drill given a session-relative elapsed.
    private func drillOffset(forElapsedSeconds elapsed: Int, drills: [LiveDrillItem]) -> Int {
        guard !drills.isEmpty else { return 0 }
        var cursor = 0
        for drill in drills {
            let next = cursor + drill.durationSeconds
            if elapsed < next { return elapsed - cursor }
            cursor = next
        }
        return drills.last.map { $0.durationSeconds } ?? 0
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !isPaused, session != nil else { return }
        sessionElapsedSeconds += 1
        drillElapsedSeconds += 1
        if let drill = currentDrill, drillElapsedSeconds >= drill.durationSeconds,
           currentDrillIndex < drills.count - 1 {
            nextDrill()
        }

        // Roll-call reminder: fires when 5 min remain (and once only).
        if !rollCallTriggered, sessionRemainingSeconds <= 5 * 60, sessionRemainingSeconds > 0 {
            rollCallTriggered = true
            rollCallPromptPending = true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
