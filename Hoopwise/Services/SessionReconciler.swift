import Foundation

// MARK: - Reconciliation, not just validation
//
// `addSessionEvent` is the natural chokepoint for invariants and it is not
// enough: CloudKit materialises records on the other device without running a
// line of app code, and that is the highest-volume creation path there is. So
// enforcement has to be a REPAIR PASS that runs over records already in the
// store — idempotent, on foreground and after sync, the same rhythm as
// auto-close. Creation-time validation still happens (fast feedback, one
// place: `normalize`), but the reconciler is the guarantee.
//
// What it repairs, and what it deliberately does not:
//   · dangling programId   → nil   (the program is gone; Phase 2 re-adopts)
//   · dangling microCycleId → nil  (the phase is gone)
//   · cross-program phase   → clears the phase pointer, which is the invalid
//                             half: the session's own program is evidence,
//                             the foreign phase link is not
//   · duplicates            → COUNTED, never touched. The 11 approved merges
//                             are pending and wait for Phase 2's derived
//                             names, because applying them today renames
//                             sessions in the coach's calendar.
//   · orphan phases         → counted, never deleted. Deleting a coach's
//                             phase is not a repair.
@MainActor
enum SessionReconciler {

    struct Result: Equatable {
        var repairedDanglingProgram = 0
        var repairedDanglingPhase = 0
        var repairedCrossProgramPhase = 0
        /// Not repaired — held for Phase 2.
        var pendingDuplicateGroups = 0
        var pendingOrphanPhases = 0

        var repairCount: Int {
            repairedDanglingProgram + repairedDanglingPhase + repairedCrossProgramPhase
        }
        var didRepair: Bool { repairCount > 0 }

        var summary: String {
            "repaired \(repairCount) (program \(repairedDanglingProgram), phase \(repairedDanglingPhase), cross-program \(repairedCrossProgramPhase)) · pending \(pendingDuplicateGroups) duplicate groups, \(pendingOrphanPhases) orphan phases"
        }
    }

    /// The single normalisation rule, used by BOTH creation and repair so a
    /// record cannot be valid on one path and not the other. Pure.
    ///
    /// Returns the corrected event and the names of the fields it changed;
    /// an empty list means the record was already sound.
    static func normalize(_ event: SessionEvent,
                          programs: [Program],
                          phases: [MicroCycle]) -> (event: SessionEvent, changes: [String]) {
        var corrected = event
        var changes: [String] = []

        if let programId = corrected.programId,
           !programs.contains(where: { $0.id == programId }) {
            corrected.programId = nil
            changes.append("programId")
        }

        if let phaseId = corrected.microCycleId {
            if let phase = phases.first(where: { $0.id == phaseId }) {
                if let programId = corrected.programId, phase.programId != programId {
                    corrected.microCycleId = nil
                    changes.append("microCycleId (phase belongs to another program)")
                }
            } else {
                corrected.microCycleId = nil
                changes.append("microCycleId")
            }
        }

        return (corrected, changes)
    }

    // MARK: - The pass

    private static var inFlight = false
    private static var pending: Task<Void, Never>?
    private static var lastRun: Date?

    /// Debounced entry point, hooked into the data manager's refresh paths —
    /// app foreground and post-sync, both platforms.
    static func scheduleReconcile(dataManager: DataManager) {
        pending?.cancel()
        pending = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let dataManager else { return }
            run(dataManager: dataManager)
        }
    }

    @discardableResult
    static func run(dataManager: DataManager,
                    now: Date = Date(),
                    force: Bool = false) -> Result {
        var result = Result()
        guard !inFlight else { return result }
        if !force, let lastRun, now.timeIntervalSince(lastRun) < 5 * 60 { return result }
        inFlight = true
        defer { inFlight = false; lastRun = now }

        let programs = dataManager.programs
        let phases = dataManager.microCycles

        for session in dataManager.sessionEvents {
            let (corrected, changes) = normalize(session, programs: programs, phases: phases)
            guard !changes.isEmpty else { continue }
            for change in changes {
                if change.hasPrefix("programId") { result.repairedDanglingProgram += 1 }
                else if change.contains("another program") { result.repairedCrossProgramPhase += 1 }
                else { result.repairedDanglingPhase += 1 }
            }
            dataManager.updateSessionEvent(corrected)
            debugLog("🧹 reconciler repaired \(changes.joined(separator: ", ")) on “\(session.title)”")
        }

        // Counted, not touched.
        let programIds = Set(programs.map(\.id))
        result.pendingOrphanPhases = phases.filter { !programIds.contains($0.programId) }.count
        result.pendingDuplicateGroups = SessionIntegrity
            .duplicateSessionGroups(in: dataManager.sessionEvents).count

        if result.didRepair {
            debugLog("🧹 reconciler: \(result.summary)")
        }
        return result
    }
}
