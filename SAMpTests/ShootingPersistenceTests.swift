import XCTest
@testable import Hoopwise

/// 21 November 2026: a session's shooting add-ons vanished after they had
/// been logged. Whole-session saves from a copy taken before the results —
/// Regenerate, auto-close, auto-start, a device that had not yet received
/// the results — wrote the plan back without them. Results now have their
/// own writer and whole-session saves keep them.
@MainActor
final class ShootingPersistenceTests: XCTestCase {

    private func session(_ dm: SwiftDataManager) -> SessionEvent {
        let program = Program(name: "Shooting U12", ageGroup: .u12)
        dm.addProgram(program)
        var s = dm.createSession(.init(group: .program(program.id), start: Date().addingTimeInterval(-3600),
                                       durationMinutes: 90)).session
        s.curriculum.skillDrillIds.append(ShootingDrill.freeThrows.drillId)
        dm.updateSessionEvent(s)
        return dm.sessionEvents.first { $0.id == s.id }!
    }

    private func results(_ kid: UUID, _ made: Int) -> [ShootingRun] {
        var run = ShootingRun(setup: ShootingDrill.freeThrows.defaultSetup)
        run.set(made, for: kid, spot: 0)
        return [run]
    }

    func testResultsAreStoredAndReadBack() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let s = session(dm), kid = UUID()
        dm.setSessionShooting(sessionId: s.id, runs: results(kid, 7))
        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == s.id })
        XCTAssertEqual(stored.curriculum.shooting.first?.result(for: kid)?.made, 7)
        XCTAssertTrue(stored.curriculum.skillDrillIds.contains(ShootingDrill.freeThrows.drillId), "the plan is untouched")
    }

    func testAStaleWholeSessionSaveKeepsTheResults() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let stale = session(dm), kid = UUID()
        dm.setSessionShooting(sessionId: stale.id, runs: results(kid, 7))

        // An automatic close from a copy taken before the results.
        var closed = stale
        XCTAssertTrue(SessionLifecycle.apply(.autoClose, to: &closed))
        dm.updateSessionEvent(closed)

        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == stale.id })
        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(stored.curriculum.shooting.first?.result(for: kid)?.made, 7, "results erased by a stale save")
    }

    func testAPlanEditFromTheSessionPageKeepsTheResults() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let s = session(dm), kid = UUID()
        dm.setSessionShooting(sessionId: s.id, runs: results(kid, 5))
        // The page's copy, without the results, saved with a plan change.
        var copy = s
        copy.curriculum.warmupDrillIds.append(UUID())
        dm.updateSessionEvent(copy, keepLiveFields: true)
        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == s.id })
        XCTAssertEqual(stored.curriculum.warmupDrillIds.count, copy.curriculum.warmupDrillIds.count, "the plan change is saved")
        XCTAssertEqual(stored.curriculum.shooting.first?.result(for: kid)?.made, 5)
    }

    func testClearingResultsGoesThroughTheirWriter() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let s = session(dm), kid = UUID()
        dm.setSessionShooting(sessionId: s.id, runs: results(kid, 5))
        dm.setSessionShooting(sessionId: s.id, runs: [])
        XCTAssertTrue(try XCTUnwrap(dm.sessionEvents.first { $0.id == s.id }).curriculum.shooting.isEmpty)
    }

    func testRestoringAnEarlierVersionBringsResultsBack() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let s = session(dm), kid = UUID()
        dm.setSessionShooting(sessionId: s.id, runs: results(kid, 6))
        dm.setSessionShooting(sessionId: s.id, runs: [])   // revision of the "6" taken first
        let revisions = dm.sessionRevisions(for: s.id)
        XCTAssertTrue(revisions.contains { $0.event.curriculum.shooting.first?.result(for: kid)?.made == 6 },
                      "every results write leaves a version to go back to")
    }
}
