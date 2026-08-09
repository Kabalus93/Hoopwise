import XCTest
@testable import Hoopwise

/// Adoption decides where 41 program-less sessions land. A wrong confident
/// answer is worse than an Unassigned one: it files a client's private
/// session into a group program, or invents a membership the coach never
/// made. So "confident" has to mean exactly one candidate.
@MainActor
final class SessionAdoptionTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let otherProgramId = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
    private let clientId = UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
    private let friday = Date(timeIntervalSince1970: 1_778_000_000)   // fixed instant

    private func program(_ id: UUID, name: String) -> Program {
        Program(id: id, name: name, ageGroup: .u14)
    }
    private func student(_ id: UUID, _ name: String) -> Student {
        Student(id: id, name: name)
    }
    private func contract(_ studentId: UUID, kind: ContractKind = .privateBundle) -> Contract {
        Contract(studentId: studentId, kind: kind, pricePerSession: 300, bundleSize: 10)
    }
    private func session(_ title: String, program: UUID?, at date: Date,
                         location: String? = "Hezhuang court",
                         attendees: [UUID] = []) -> SessionEvent {
        SessionEvent(programId: program, title: title, date: date,
                     startTime: date, endTime: date.addingTimeInterval(5400),
                     location: location, attendeeIds: attendees)
    }

    private func plan(_ sessions: [SessionEvent],
                      programs: [Program] = [],
                      contracts: [Contract] = [],
                      students: [Student] = []) -> SessionAdoption.Plan {
        SessionAdoption.plan(sessions: sessions, programs: programs,
                             contracts: contracts, students: students)
    }

    // MARK: - Fingerprint

    func testExactShapeMatchAdoptsIntoTheOwningProgram() {
        let owned = session("Training", program: programId, at: friday)
        let orphan = session("Training", program: nil, at: friday.addingTimeInterval(7 * 86_400))

        let result = plan([owned, orphan], programs: [program(programId, name: "U14 Friday")])

        XCTAssertEqual(result.fingerprintCount, 1)
        XCTAssertEqual(result.programAbsorption["U14 Friday"], 1)
    }

    /// Two programs owning the same shape is not confidence.
    func testAmbiguousShapeGoesToUnassigned() {
        let a = session("Training", program: programId, at: friday)
        let b = session("Training", program: otherProgramId, at: friday)
        let orphan = session("Training", program: nil, at: friday.addingTimeInterval(7 * 86_400))

        let result = plan([a, b, orphan],
                          programs: [program(programId, name: "A"), program(otherProgramId, name: "B")])

        XCTAssertEqual(result.unassignedCount, 1)
        XCTAssertEqual(result.fingerprintCount, 0)
        XCTAssertTrue(result.unassignedReasons.keys.contains { $0.contains("ambiguous") })
    }

    func testDifferentTimeOfDayIsADifferentShape() {
        let morning = session("Training", program: programId, at: friday)
        let evening = session("Training", program: nil, at: friday.addingTimeInterval(6 * 3600))

        let result = plan([morning, evening], programs: [program(programId, name: "U14 Friday")])

        XCTAssertEqual(result.fingerprintCount, 0, "A different hour is a different session slot.")
        XCTAssertEqual(result.unassignedCount, 1)
    }

    func testTitleEqualToProgramNameIsATierTwoMatch() {
        let orphan = session("U14 Friday", program: nil, at: friday)

        let result = plan([orphan], programs: [program(programId, name: "U14 Friday")])

        XCTAssertEqual(result.fingerprintCount, 1)
        XCTAssertTrue(result.decisions[0].destination == .fingerprint(
            programId: programId, programName: "U14 Friday", tier: "title = program name"))
    }

    // MARK: - Private micro-groups

    func testPrivateSessionJoinsItsClientsOwnProgram() {
        let orphan = session("Private · Frank", program: nil, at: friday, attendees: [clientId])

        let result = plan([orphan],
                          contracts: [contract(clientId)],
                          students: [student(clientId, "Frank")])

        XCTAssertEqual(result.privateCount, 1)
        XCTAssertEqual(result.microGroupClients["Frank"], 1)
    }

    /// Privateness is checked BEFORE the title tier, so a 1:1 session can
    /// never be swept into a group program by a matching name.
    func testPrivateSessionIsNotAdoptedByATitleMatch() {
        let orphan = session("U14 Friday", program: nil, at: friday, attendees: [clientId])

        let result = plan([orphan],
                          programs: [program(programId, name: "U14 Friday")],
                          contracts: [contract(clientId)],
                          students: [student(clientId, "Frank")])

        XCTAssertEqual(result.privateCount, 1, "A private session must not land in a group program.")
        XCTAssertEqual(result.fingerprintCount, 0)
    }

    func testPrivateWithTwoContractHoldersNeedsAHuman() {
        let second = UUID()
        let orphan = session("Private", program: nil, at: friday, attendees: [clientId, second])

        let result = plan([orphan],
                          contracts: [contract(clientId), contract(second)],
                          students: [student(clientId, "Frank"), student(second, "Alen")])

        XCTAssertEqual(result.unassignedCount, 1)
        XCTAssertTrue(result.unassignedReasons.keys.contains { $0.contains("2 private-contract attendees") })
    }

    /// An expired contract is not an active client.
    func testInactiveContractIsNotPrivate() {
        var expired = contract(clientId)
        expired.manualStatus = .completed
        let orphan = session("Private", program: nil, at: friday, attendees: [clientId])

        let result = plan([orphan], contracts: [expired], students: [student(clientId, "Frank")])

        XCTAssertEqual(result.privateCount, 0)
        XCTAssertEqual(result.unassignedCount, 1)
    }

    // MARK: - Unassigned is the honest default

    func testNoMatchGoesToUnassignedNotAGuess() {
        let orphan = session("Road to Elite Fridays", program: nil, at: friday)

        let result = plan([orphan], programs: [program(programId, name: "U14 Friday")])

        XCTAssertEqual(result.unassignedCount, 1)
        XCTAssertEqual(result.unassignedReasons["no matching program"], 1)
    }

    func testProgramLinkedSessionsAreNotInThePlan() {
        let owned = session("Training", program: programId, at: friday)

        let result = plan([owned], programs: [program(programId, name: "U14 Friday")])

        XCTAssertTrue(result.decisions.isEmpty, "Adoption only considers standalone sessions.")
    }

    func testReportStatesTheThreeBucketsAndWritesNothing() {
        let text = SessionAdoption.report(plan([session("X", program: nil, at: friday)]))
        XCTAssertTrue(text.contains("nothing was written"))
        XCTAssertTrue(text.contains("fingerprint match"))
        XCTAssertTrue(text.contains("Unassigned"))
    }
}
