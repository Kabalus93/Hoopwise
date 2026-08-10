import XCTest
@testable import Hoopwise

/// Nine call sites used to build a SessionEvent by hand and disagree about
/// every derived field. These pin the agreements — especially the two that
/// cost real data: a 1:1 landing with no program, and a venue retyped into a
/// spelling the store does not know.
@MainActor
final class SessionCreationTests: XCTestCase {

    private let programId = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let phaseId = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
    private let clientId = UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
    private let mateId = UUID(uuidString: "C1000000-0000-0000-0000-000000000002")!

    /// A Friday inside the phase window below.
    private let friday = Date(timeIntervalSince1970: 1_778_000_000)

    private func groupProgram(usesPhases: Bool = true,
                              venue: String? = "酷迅") -> Program {
        Program(id: programId, name: "Elite U10 Development",
                programType: .group, ageGroup: .u10,
                enrolledStudentIds: [clientId, mateId],
                status: .active,
                locationName: venue, usesPhases: usesPhases)
    }

    private func phase(covering date: Date) -> MicroCycle {
        MicroCycle(id: phaseId, programId: programId, phaseNumber: 1,
                   title: "Pre-Season",
                   startDate: date.addingTimeInterval(-86_400 * 3),
                   endDate: date.addingTimeInterval(86_400 * 3))
    }

    private func privateProgram(status: ProgramStatus = .active,
                                created: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Program {
        Program(id: UUID(), name: "Private · Frank",
                programType: .privateSessions, ageGroup: .u12,
                enrolledStudentIds: [clientId],
                status: status, createdAt: created,
                recurringDays: [], defaultSessionTime: nil,
                usesPhases: false)
    }

    private func plan(_ intent: SessionCreation.Intent,
                      programs: [Program] = [],
                      phases: [MicroCycle] = [],
                      students: [Student] = [],
                      sessions: [SessionEvent] = []) -> SessionCreation.Plan {
        SessionCreation.plan(intent, programs: programs, phases: phases,
                             students: students, sessions: sessions)
    }

    private func intent(_ group: SessionCreation.Group,
                        title: String? = nil,
                        location: String? = nil,
                        roster: [UUID]? = nil,
                        phase: UUID? = nil) -> SessionCreation.Intent {
        SessionCreation.Intent(group: group, start: friday, durationMinutes: 90,
                               title: title, location: location, roster: roster,
                               phase: phase)
    }

    // MARK: - The defect that motivated the phase

    func testPrivateClientGetsTheirMicroGroupNotANilProgram() {
        let existing = privateProgram()
        let result = plan(intent(.privateClient(clientId)),
                          programs: [existing],
                          students: [Student(id: clientId, name: "Frank")])

        XCTAssertEqual(result.event.programId, existing.id,
                       "A 1:1 must land in the client's micro-group. programId == nil is the encoding Phase 1 retired.")
        XCTAssertNil(result.programToCreate, "The client already had a program.")
        XCTAssertEqual(result.event.attendeeIds, [clientId])
    }

    func testPrivateClientWithNoProgramGetsOneInTheMigrationShape() {
        let result = plan(intent(.privateClient(clientId)),
                          programs: [],
                          students: [Student(id: clientId, name: "Frank", chineseName: "弗兰克")])

        let created = try? XCTUnwrap(result.programToCreate)
        XCTAssertEqual(created?.programType, .privateSessions)
        XCTAssertEqual(created?.name, "Private · 弗兰克 / Frank")
        XCTAssertEqual(created?.enrolledStudentIds, [clientId])
        XCTAssertTrue(created?.recurringDays.isEmpty ?? false,
                      "No weekly slot — otherwise the adoption slot tier could match it against an unrelated class.")
        XCTAssertNil(created?.defaultSessionTime)
        XCTAssertEqual(created?.usesPhases, false)
        XCTAssertEqual(result.event.programId, created?.id)
    }

    func testDormantPrivateProgramIsReactivatedNotDuplicated() {
        let archived = privateProgram(status: .archived)
        let result = plan(intent(.privateClient(clientId)),
                          programs: [archived],
                          students: [Student(id: clientId, name: "Frank")])

        XCTAssertNil(result.programToCreate,
                     "A returning client must not spawn “Private · Frank 2” beside their archived program.")
        XCTAssertEqual(result.reactivate?.id, archived.id)
        XCTAssertEqual(result.reactivate?.status, .active)
        XCTAssertEqual(result.event.programId, archived.id)
    }

    func testActivePrivateProgramWinsOverADormantOne() {
        let archived = privateProgram(status: .archived,
                                      created: Date(timeIntervalSince1970: 1_600_000_000))
        let active = privateProgram(status: .active)
        let result = plan(intent(.privateClient(clientId)),
                          programs: [archived, active],
                          students: [Student(id: clientId, name: "Frank")])

        XCTAssertEqual(result.event.programId, active.id)
        XCTAssertNil(result.programToCreate)
        XCTAssertNil(result.reactivate)
    }

    // MARK: - Enrolment must not steal a student from their squad

    func testClientAlreadyInAGroupKeepsThatEnrolment() {
        var student = Student(id: clientId, name: "Frank")
        student.programId = programId    // trains with a group
        let result = plan(intent(.privateClient(clientId)),
                          programs: [groupProgram()],
                          students: [student])

        XCTAssertNotNil(result.programToCreate)
        XCTAssertNil(result.enroll,
                     "setStudentEnrollment clears every other program's roster — pointing the student at their private micro-group would silently remove them from the group they train with.")
    }

    func testClientWithNoProgramIsEnrolledInTheNewMicroGroup() {
        let result = plan(intent(.privateClient(clientId)),
                          programs: [],
                          students: [Student(id: clientId, name: "Frank")])

        XCTAssertEqual(result.enroll?.studentId, clientId)
        XCTAssertEqual(result.enroll?.programId, result.programToCreate?.id)
    }

    // MARK: - Derived fields

    func testVenueDefaultsToTheProgramsSoItIsNotRetyped() {
        let result = plan(intent(.program(programId)), programs: [groupProgram()])
        XCTAssertEqual(result.event.location, "酷迅",
                       "A hand-typed “Kuxun Main court” is how one gym ended up spelled four ways.")
    }

    func testAnExplicitVenueStillWins() {
        let result = plan(intent(.program(programId), location: "河庄"),
                          programs: [groupProgram()])
        XCTAssertEqual(result.event.location, "河庄")
    }

    func testRosterDefaultsToTheProgramsEnrolment() {
        let result = plan(intent(.program(programId)), programs: [groupProgram()])
        XCTAssertEqual(Set(result.event.attendeeIds), [clientId, mateId],
                       "The program wizard used to create sessions with no attendees at all.")
    }

    func testPhaseIsDerivedFromTheDate() {
        let result = plan(intent(.program(programId)),
                          programs: [groupProgram()],
                          phases: [phase(covering: friday)])
        XCTAssertEqual(result.event.microCycleId, phaseId)
    }

    func testAnExplicitPhaseSurvivesADatelessPlan() {
        // A phase with no window: derivation has nothing to work from, and 16
        // links in the live store are exactly this shape.
        let undated = MicroCycle(id: phaseId, programId: programId,
                                 phaseNumber: 1, title: "Phase 1")
        let result = plan(intent(.program(programId), phase: phaseId),
                          programs: [groupProgram()],
                          phases: [undated])
        XCTAssertEqual(result.event.microCycleId, phaseId,
                       "The generator generates FOR a phase; deriving would drop the link.")
    }

    func testNoPhaseWhenTheProgramIsPlanless() {
        let result = plan(intent(.program(programId)),
                          programs: [groupProgram(usesPhases: false)],
                          phases: [phase(covering: friday)])
        XCTAssertNil(result.event.microCycleId)
    }

    func testUnassignedStaysProgramLessAndDerivesNothing() {
        let result = plan(intent(.unassigned, title: "Scrimmage", location: "瓜沥"),
                          programs: [groupProgram()],
                          phases: [phase(covering: friday)])

        XCTAssertNil(result.event.programId, "A one-off genuinely belongs to no program.")
        XCTAssertNil(result.event.microCycleId)
        XCTAssertEqual(result.event.title, "Scrimmage")
        XCTAssertNil(result.programToCreate)
    }

    // MARK: - Title, times, series

    func testTypedTitleIsKeptAndDerivedNameFillsInOtherwise() {
        let typed = plan(intent(.program(programId), title: "Friday scrimmage"),
                         programs: [groupProgram()])
        XCTAssertEqual(typed.event.title, "Friday scrimmage")

        let derived = plan(intent(.program(programId)), programs: [groupProgram()])
        XCTAssertEqual(derived.event.title, "Elite U10 Development",
                       "With nothing typed the stored column holds the derived name, its Phase 2.3 fallback role.")
    }

    func testEndTimeComesFromTheDurationAndDateMatchesTheStart() {
        let result = plan(intent(.program(programId)), programs: [groupProgram()])
        XCTAssertEqual(result.event.endTime.timeIntervalSince(result.event.startTime), 90 * 60)
        XCTAssertEqual(result.event.date, result.event.startTime,
                       "One convention for `date`, so day-and-time duplicate detection sees what the generators write.")
    }

    func testSeriesIdIsCarriedSoSiblingsResolveByIdentity() {
        let series = UUID()
        var intent = self.intent(.program(programId))
        intent.seriesId = series
        let result = plan(intent, programs: [groupProgram()])
        XCTAssertEqual(result.event.seriesId, series)
    }

    func testCreationNeverPreMarksAttendanceByItself() {
        let result = plan(intent(.program(programId)), programs: [groupProgram()])
        XCTAssertTrue(result.event.actualAttendeeIds.isEmpty,
                      "Charging a bundle stays with the redemption authority; creation must never be a second way to spend a client's sessions.")
    }

    func testAMissingProgramDoesNotInventOne() {
        let result = plan(intent(.program(UUID()), title: "Orphan"), programs: [groupProgram()])
        XCTAssertNil(result.event.programId)
        XCTAssertNil(result.programToCreate)
    }
}
