import XCTest
@testable import Hoopwise

/// Names are derived from the group and the plan, so renaming a phase or a
/// program renames every session instantly — and so merging two duplicates
/// stops depending on which stored string happens to survive.
///
/// The dangerous half is the write path: if a save ever persists the derived
/// name into the stored column, derivation quietly becomes a one-time rename
/// and the coach's own titles are lost. The guard tests below are the point.
@MainActor
final class SessionNamingTests: XCTestCase {

    /// The expected strings are English; the app-host's saved language is
    /// whatever the simulator last ran in, so pin it for the test and restore.
    private var savedLanguage: AppLanguage?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            savedLanguage = LocalizationManager.shared.currentLanguage
            LocalizationManager.shared.currentLanguage = .english
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if let savedLanguage { LocalizationManager.shared.currentLanguage = savedLanguage }
        }
        super.tearDown()
    }

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let phaseId = UUID(uuidString: "C0000000-0000-0000-0000-00000000000C")!
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func program() -> Program {
        Program(id: programId, name: "酷迅 · U10", ageGroup: .u10)
    }
    private func phase() -> MicroCycle {
        MicroCycle(id: phaseId, programId: programId, phaseNumber: 1, title: "Pre-Season")
    }
    private func session(_ title: String, program: UUID?, phase: UUID?,
                         offsetDays: Int = 0) -> SessionEvent {
        let date = when.addingTimeInterval(TimeInterval(offsetDays * 86_400))
        return SessionEvent(microCycleId: phase, programId: program, title: title,
                            date: date, startTime: date, endTime: date.addingTimeInterval(5400))
    }

    // MARK: - Derivation

    func testGroupFirstUsesTheProgramName() {
        let stale = session("Competition & Review · 2", program: programId, phase: phaseId)

        let name = SessionNaming.name(for: stale, programs: [program()], phases: [phase()],
                                      allSessions: [stale], style: .groupFirst)

        XCTAssertEqual(name, "酷迅 · U10", "The frozen stored title must not surface.")
    }

    func testPlanFirstCountsPositionWithinThePhase() {
        let first = session("x", program: programId, phase: phaseId, offsetDays: 0)
        let second = session("y", program: programId, phase: phaseId, offsetDays: 7)
        let third = session("z", program: programId, phase: phaseId, offsetDays: 14)

        let name = SessionNaming.name(for: second, programs: [program()], phases: [phase()],
                                      allSessions: [first, second, third], style: .planFirst)

        XCTAssertEqual(name, "Pre-Season · Session 2 of 3")
    }

    /// Renaming the phase renames every session, which is the entire point.
    func testRenamingThePhasePropagatesImmediately() {
        let existing = session("Pre-Season · 1", program: programId, phase: phaseId)
        var renamed = phase()
        renamed.title = "Playoffs"

        let name = SessionNaming.name(for: existing, programs: [program()], phases: [renamed],
                                      allSessions: [existing], style: .planFirst)

        XCTAssertTrue(name.hasPrefix("Playoffs"))
    }

    func testSessionWithNoProgramFallsBackToTheStoredTitle() {
        let orphan = session("Scrimmage", program: nil, phase: nil)

        let name = SessionNaming.name(for: orphan, programs: [], phases: [],
                                      allSessions: [orphan], style: .groupFirst)

        XCTAssertEqual(name, "Scrimmage")
    }

    /// The "Private ·" convention dies with derived names: privateness is the
    /// program's type, not a prefix on a string.
    func testLegacyPrivatePrefixIsStripped() {
        let orphan = session("Private · Frank", program: nil, phase: nil)

        XCTAssertEqual(SessionNaming.legacyFallback(orphan), "Frank")
    }

    // MARK: - The write-path guard

    func testCachedSessionsCarryTheDerivedName() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addProgram(program())
        dm.addSessionEvent(session("Competition & Review · 2", program: programId, phase: nil))

        XCTAssertEqual(dm.sessionEvents.first?.title, "酷迅 · U10")
    }

    /// Round-tripping a cached session must NOT persist the derived name.
    func testRoundTripDoesNotBurnTheDerivedNameIntoTheStore() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addProgram(program())
        let stored = session("Competition & Review · 2", program: programId, phase: nil)
        dm.addSessionEvent(stored)

        // A view reads the cached (derived-titled) copy and saves it back
        // after changing something else entirely.
        var roundTripped = dm.sessionEvents.first { $0.id == stored.id }!
        XCTAssertEqual(roundTripped.title, "酷迅 · U10")
        roundTripped.location = "酷迅"
        dm.updateSessionEvent(roundTripped)

        XCTAssertEqual(dm.storedTitleForTesting(sessionId: stored.id),
                       "Competition & Review · 2",
                       "The stored title must survive a save that never touched the name.")
    }

    /// A deliberate rename still persists — the guard must not swallow edits.
    func testDeliberateRenameIsStored() {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.addProgram(program())
        let stored = session("Competition & Review · 2", program: programId, phase: nil)
        dm.addSessionEvent(stored)

        var edited = dm.sessionEvents.first { $0.id == stored.id }!
        edited.title = "Friday night session"
        dm.updateSessionEvent(edited)

        XCTAssertEqual(dm.storedTitleForTesting(sessionId: stored.id), "Friday night session")
    }
}
