import XCTest
@testable import Hoopwise

/// The write half of Phase 2.5, against a real in-memory manager — so the
/// undo path is exercised rather than described.
///
/// The rule these protect: booking a 1:1 for a brand-new client creates their
/// micro-group AND the session, and ⌘Z removes both. A half-undo that left an
/// empty "Private · <name>" program behind would be a record the coach finds
/// weeks later and cannot explain.
@MainActor
final class SessionCreationWriteTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var client: Student!

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
        client = Student(name: "Frank", chineseName: "弗兰克")
        dm.addStudent(client)
    }

    private func bookPrivate(at start: Date = Date(timeIntervalSince1970: 1_778_000_000),
                             title: String? = nil,
                             location: String? = nil) -> SwiftDataManager.SessionCreationResult {
        dm.createSession(SessionCreation.Intent(
            group: .privateClient(client.id),
            start: start,
            durationMinutes: 60,
            title: title,
            location: location))
    }

    func testBookingForANewClientCreatesTheMicroGroupAndTheSession() {
        let result = bookPrivate()

        let created = dm.programs.first { $0.id == result.createdProgramId }
        XCTAssertNotNil(created, "A brand-new client gets their private micro-group.")
        XCTAssertEqual(created?.programType, .privateSessions)
        XCTAssertEqual(created?.name, "Private · 弗兰克 / Frank")

        let session = dm.sessionEvents.first { $0.id == result.session.id }
        XCTAssertEqual(session?.programId, created?.id)
        XCTAssertEqual(session?.attendeeIds, [client.id])
        XCTAssertNotNil(session, "programId == nil is the state this phase retires.")
    }

    func testUndoRemovesBothTheSessionAndTheProgramItCreated() {
        let result = bookPrivate()
        XCTAssertEqual(dm.sessionEvents.count, 1)
        XCTAssertEqual(dm.programs.count, 1)

        dm.undoSessionCreation(result)

        XCTAssertTrue(dm.sessionEvents.isEmpty, "The session goes.")
        XCTAssertTrue(dm.programs.isEmpty,
                      "…and so does the program it brought into existence. One booking, one undo step.")
        XCTAssertNil(dm.students.first { $0.id == client.id }?.programId,
                     "The enrolment the booking made is released too.")
    }

    func testASecondBookingReusesTheSameMicroGroup() {
        let first = bookPrivate()
        let second = bookPrivate(at: Date(timeIntervalSince1970: 1_778_600_000))

        XCTAssertNil(second.createdProgramId, "The client already has a program.")
        XCTAssertEqual(dm.programs.count, 1)
        XCTAssertEqual(dm.sessionEvents.first { $0.id == second.session.id }?.programId,
                       first.createdProgramId)
    }

    func testUndoingTheFirstBookingKeepsAProgramThatStillOwnsSessions() {
        let first = bookPrivate()
        _ = bookPrivate(at: Date(timeIntervalSince1970: 1_778_600_000))

        dm.undoSessionCreation(first)

        XCTAssertEqual(dm.programs.count, 1,
                       "deleteProgram cascades to sessions — it may only run on a provably empty program.")
        XCTAssertEqual(dm.sessionEvents.count, 1)
    }

    func testAReturningClientReactivatesTheirArchivedProgram() {
        let first = bookPrivate()
        let programId = try! XCTUnwrap(first.createdProgramId)

        // The client leaves: their program is archived, session history stays.
        var archived = try! XCTUnwrap(dm.programs.first { $0.id == programId })
        archived.status = .archived
        dm.updateProgram(archived)

        let comeback = bookPrivate(at: Date(timeIntervalSince1970: 1_779_000_000))

        XCTAssertNil(comeback.createdProgramId,
                     "No “Private · Frank 2” — that would split the client's history across two containers.")
        XCTAssertEqual(comeback.reactivatedProgramId, programId)
        XCTAssertEqual(dm.programs.first { $0.id == programId }?.status, .active)
        XCTAssertEqual(dm.programs.filter { $0.programType == .privateSessions }.count, 1)
    }

    func testUndoingAComebackRestoresTheArchivedStatus() {
        let first = bookPrivate()
        let programId = try! XCTUnwrap(first.createdProgramId)
        var archived = try! XCTUnwrap(dm.programs.first { $0.id == programId })
        archived.status = .archived
        dm.updateProgram(archived)

        let comeback = bookPrivate(at: Date(timeIntervalSince1970: 1_779_000_000))
        dm.undoSessionCreation(comeback)

        XCTAssertEqual(dm.programs.first { $0.id == programId }?.status, .archived,
                       "Undo puts the program back the way it was found.")
        XCTAssertEqual(dm.sessionEvents.count, 1, "Only the comeback session goes.")
    }

    func testVenueIsInheritedFromTheProgramOnLaterBookings() {
        let first = bookPrivate(location: "酷迅")
        var program = try! XCTUnwrap(dm.programs.first { $0.id == first.createdProgramId })
        program.locationName = "酷迅"
        dm.updateProgram(program)

        let second = bookPrivate(at: Date(timeIntervalSince1970: 1_778_600_000))
        XCTAssertEqual(dm.sessionEvents.first { $0.id == second.session.id }?.location, "酷迅",
                       "The venue stops being retyped once the program carries it.")
    }
}
