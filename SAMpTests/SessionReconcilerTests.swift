import XCTest
@testable import Hoopwise

/// The reconciler is the guarantee that `addSessionEvent` cannot be: CloudKit
/// materialises records on the other device without running app code, so
/// invariants have to be repaired in place, not merely validated at creation.
@MainActor
final class SessionReconcilerTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let otherProgramId = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
    private let phaseId = UUID(uuidString: "C0000000-0000-0000-0000-00000000000C")!

    private func program(_ id: UUID) -> Program { Program(id: id, name: "U8", ageGroup: .u8) }
    private func phase(_ id: UUID, program: UUID) -> MicroCycle {
        MicroCycle(id: id, programId: program, phaseNumber: 1, title: "Pre-Season")
    }
    private func session(program: UUID?, phase: UUID?) -> SessionEvent {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionEvent(microCycleId: phase, programId: program,
                            title: "S", date: when, startTime: when,
                            endTime: when.addingTimeInterval(3600))
    }

    // MARK: - normalize: the one rule, used by creation and repair

    func testDanglingProgramIsCleared() {
        let (fixed, changes) = SessionReconciler.normalize(
            session(program: programId, phase: nil), programs: [], phases: [])

        XCTAssertNil(fixed.programId)
        XCTAssertEqual(changes, ["programId"])
    }

    func testDanglingPhaseIsCleared() {
        let (fixed, changes) = SessionReconciler.normalize(
            session(program: programId, phase: phaseId),
            programs: [program(programId)], phases: [])

        XCTAssertNil(fixed.microCycleId)
        XCTAssertEqual(fixed.programId, programId, "A sound program pointer must survive.")
        XCTAssertEqual(changes, ["microCycleId"])
    }

    /// The invariant nothing in the app validated: the phase pointer is the
    /// invalid half, because the session's own program is the evidence.
    func testCrossProgramPhasePointerIsCleared() {
        let (fixed, changes) = SessionReconciler.normalize(
            session(program: programId, phase: phaseId),
            programs: [program(programId), program(otherProgramId)],
            phases: [phase(phaseId, program: otherProgramId)])

        XCTAssertNil(fixed.microCycleId)
        XCTAssertEqual(fixed.programId, programId)
        XCTAssertTrue(changes.first?.contains("another program") == true)
    }

    func testSoundRecordIsUntouched() {
        let sound = session(program: programId, phase: phaseId)
        let (fixed, changes) = SessionReconciler.normalize(
            sound, programs: [program(programId)], phases: [phase(phaseId, program: programId)])

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(fixed.programId, sound.programId)
        XCTAssertEqual(fixed.microCycleId, sound.microCycleId)
    }

    func testStandaloneSessionIsNotARepairTarget() {
        let (_, changes) = SessionReconciler.normalize(
            session(program: nil, phase: nil), programs: [], phases: [])
        XCTAssertTrue(changes.isEmpty, "programId == nil is legitimate today, not damage.")
    }

    // MARK: - The pass, against a real store

    /// The acceptance case: a malformed record that arrived WITHOUT going
    /// through addSessionEvent — exactly what CloudKit does — is normalized
    /// by one reconcile pass.
    func testSyncedInMalformedRecordIsRepairedByOnePass() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addProgram(program(programId))

        // Simulate the sync path: insert straight into the context, bypassing
        // addSessionEvent and its validation entirely.
        let malformed = session(program: UUID(), phase: UUID())
        dm.insertSessionBypassingValidationForTesting(malformed)
        XCTAssertNotNil(dm.sessionEvents.first { $0.id == malformed.id }?.programId,
                        "Precondition: the bad pointers are in the store.")

        let result = SessionReconciler.run(dataManager: dm, force: true)

        let repaired = dm.sessionEvents.first { $0.id == malformed.id }
        XCTAssertNotNil(repaired)
        XCTAssertNil(repaired?.programId, "The dangling program pointer must be cleared.")
        XCTAssertNil(repaired?.microCycleId, "The dangling phase pointer must be cleared.")
        XCTAssertEqual(result.repairedDanglingProgram, 1)
        XCTAssertEqual(result.repairedDanglingPhase, 1)
    }

    func testSecondPassRepairsNothing() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.insertSessionBypassingValidationForTesting(session(program: UUID(), phase: nil))

        _ = SessionReconciler.run(dataManager: dm, force: true)
        let second = SessionReconciler.run(dataManager: dm, force: true)

        XCTAssertEqual(second.repairCount, 0, "The pass must be idempotent.")
    }

    /// The 11 approved merges are pending until Phase 2's derived names. The
    /// reconciler counts them and must not touch them.
    func testDuplicatesAreCountedNeverDeleted() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addProgram(program(programId))
        dm.addSessionEvent(session(program: programId, phase: nil))
        dm.addSessionEvent(session(program: programId, phase: nil))
        let countBefore = dm.sessionEvents.count

        let result = SessionReconciler.run(dataManager: dm, force: true)

        XCTAssertEqual(result.pendingDuplicateGroups, 1)
        XCTAssertEqual(dm.sessionEvents.count, countBefore, "The reconciler must never delete a duplicate.")
    }

    // MARK: - Creation-time validation

    func testAddSessionEventNormalizesOnTheWayIn() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addSessionEvent(session(program: UUID(), phase: UUID()))

        let stored = dm.sessionEvents.last
        XCTAssertNil(stored?.programId)
        XCTAssertNil(stored?.microCycleId)
    }
}
