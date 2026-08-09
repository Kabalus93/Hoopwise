import XCTest
@testable import Hoopwise

/// Phase and program deletion behave identically no matter which screen
/// invoked them, because the semantics live in the manager now.
///
/// Before: `deleteMicroCycle` touched no sessions and four call sites
/// disagreed about compensating — only iOS's program-detail path deleted
/// them, so swipe-delete and the Mac context menu left every session in the
/// phase pointing at a row that no longer existed. `deleteProgram` deleted
/// phases but never sessions, and the Mac path did not compensate at all.
@MainActor
final class CascadeSemanticsTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var program: Program!
    private var phase: MicroCycle!

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
        program = Program(name: "U8 Saturday", ageGroup: .u8)
        dm.addProgram(program)
        phase = MicroCycle(programId: program.id, phaseNumber: 1, title: "Pre-Season")
        dm.addMicroCycle(phase)
    }

    override func tearDown() async throws {
        dm = nil; program = nil; phase = nil
        try await super.tearDown()
    }

    @discardableResult
    private func addSession(phase phaseId: UUID?, program programId: UUID?) -> SessionEvent {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let event = SessionEvent(microCycleId: phaseId, programId: programId,
                                 title: "Session", date: when, startTime: when,
                                 endTime: when.addingTimeInterval(5400))
        dm.addSessionEvent(event)
        return event
    }

    // MARK: - Phase delete: orphan, never destroy

    func testDeletingAPhaseKeepsItsSessionsAndClearsThePointer() {
        let session = addSession(phase: phase.id, program: program.id)

        dm.deleteMicroCycle(phase)

        let survivor = dm.sessionEvents.first { $0.id == session.id }
        XCTAssertNotNil(survivor, "A coach's session is not deleted because a phase was.")
        XCTAssertNil(survivor?.microCycleId, "The phase pointer must be cleared, not left dangling.")
        XCTAssertEqual(survivor?.programId, program.id, "The program link is untouched.")
        XCTAssertFalse(dm.microCycles.contains { $0.id == phase.id })
    }

    /// The acceptance point: identical outcome regardless of entry point,
    /// because every former call site now calls this one function.
    func testPhaseDeleteLeavesNoDanglingPointerForTheCensus() {
        addSession(phase: phase.id, program: program.id)
        addSession(phase: phase.id, program: program.id)

        dm.deleteMicroCycle(phase)

        let census = SessionIntegrity.census(sessions: dm.sessionEvents,
                                             programs: dm.programs,
                                             phases: dm.microCycles)
        XCTAssertEqual(census.sessionsWithDanglingPhase.count, 0)
        XCTAssertEqual(census.brokenCount, 0, "Deleting a phase must not create integrity damage.")
    }

    // MARK: - Program delete: cascade to descendants

    func testDeletingAProgramRemovesItsPhasesAndSessions() {
        let inProgram = addSession(phase: phase.id, program: program.id)
        let unrelated = addSession(phase: nil, program: nil)

        dm.deleteProgram(program)

        XCTAssertFalse(dm.sessionEvents.contains { $0.id == inProgram.id },
                       "A deleted program takes its sessions with it.")
        XCTAssertFalse(dm.microCycles.contains { $0.id == phase.id })
        XCTAssertTrue(dm.sessionEvents.contains { $0.id == unrelated.id },
                      "Unrelated sessions are untouched.")
    }

    func testProgramDeleteLeavesTheStoreClean() {
        addSession(phase: phase.id, program: program.id)

        dm.deleteProgram(program)

        let census = SessionIntegrity.census(sessions: dm.sessionEvents,
                                             programs: dm.programs,
                                             phases: dm.microCycles)
        XCTAssertEqual(census.brokenCount, 0)
        XCTAssertEqual(census.totalSessions, 0)
    }

    /// Cascade goes through deleteSessionEvent, so contract references still
    /// get cleaned up rather than outliving the records.
    func testProgramDeleteReleasesContractReferences() {
        let student = Student(name: "Cascade Kid")
        dm.addStudent(student)
        let session = addSession(phase: nil, program: program.id)
        var contract = Contract(studentId: student.id, kind: .privateBundle,
                                pricePerSession: 300, bundleSize: 10)
        contract.bundleSessionIds = [session.id]
        dm.addContract(contract)

        dm.deleteProgram(program)

        XCTAssertFalse(dm.contracts.contains { $0.bundleSessionIds.contains(session.id) },
                       "A cascaded delete must not leave a contract pointing at a gone session.")
        XCTAssertEqual(dm.contracts.first { $0.id == contract.id }?.bundleRedemptionsRemaining, 10,
                       "The slot comes back, as it does for any deletion.")
    }
}
