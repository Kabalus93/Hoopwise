import XCTest
@testable import Hoopwise

/// Group classes drawing on a prepaid SESSION BALANCE (October 2026).
///
/// Academies sell group classes as a count of sessions ("剩余课时"), and a
/// student can attend two classes on one shared balance. Before this, only
/// private sessions ever charged anything. These run against a real in-memory
/// store, so they exercise the one redemption authority.
@MainActor
final class GroupBalanceTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var kid: Student!
    private var monday: Program!
    private var wednesday: Program!

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
        kid = Student(name: "Shared Balance Kid")
        dm.addStudent(kid)
        monday = Program(name: "周一 18:30 U6", ageGroup: .u6)
        wednesday = Program(name: "周三 18:30 U6", ageGroup: .u6)
        dm.addProgram(monday)
        dm.addProgram(wednesday)
        dm.addStudentEnrollment(studentId: kid.id, programId: monday.id)
        dm.addStudentEnrollment(studentId: kid.id, programId: wednesday.id)
    }

    override func tearDown() async throws {
        dm = nil; kid = nil; monday = nil; wednesday = nil
        try await super.tearDown()
    }

    @discardableResult
    private func addBalance(_ sessions: Int, program: UUID? = nil,
                            bought: Date = Date(timeIntervalSince1970: 1_600_000_000)) -> Contract {
        let contract = Contract(studentId: kid.id,
                                contractNumber: (dm.allContracts(for: kid.id).map(\.contractNumber).max() ?? 0) + 1,
                                kind: .group, bundleSize: sessions,
                                bundlePurchaseDate: bought, programId: program)
        dm.addContract(contract)
        return contract
    }

    private func classSession(_ program: Program, offsetDays: Double = 0) -> SessionEvent {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offsetDays * 86_400)
        let event = SessionEvent(programId: program.id, title: program.name, date: start,
                                 startTime: start, endTime: start.addingTimeInterval(5400),
                                 status: .scheduled, attendeeIds: [])
        dm.addSessionEvent(event)
        return event
    }

    private func remaining(_ contract: Contract) -> Int {
        dm.contracts.first { $0.id == contract.id }?.bundleRedemptionsRemaining ?? -1
    }

    func testAGroupClassDeductsFromAGroupBalance() {
        let balance = addBalance(10)
        let event = classSession(monday)
        dm.setStudentAttendanceState(sessionId: event.id, studentId: kid.id, state: .present)
        XCTAssertEqual(remaining(balance), 9)
    }

    func testUnexcusedAbsenceDeductsExcusedDoesNot() {
        let balance = addBalance(10)
        let a = classSession(monday), b = classSession(monday, offsetDays: 7)
        dm.setStudentAttendanceState(sessionId: a.id, studentId: kid.id, state: .absent)
        dm.setStudentAttendanceState(sessionId: b.id, studentId: kid.id, state: .excused)
        XCTAssertEqual(remaining(balance), 9)
    }

    func testAnEnrollmentWithoutABalanceChargesNothing() {
        // The pre-existing group contract shape: bundleSize 0.
        let enrollment = Contract(studentId: kid.id, kind: .group, programId: monday.id)
        dm.addContract(enrollment)
        let event = classSession(monday)
        dm.setStudentAttendanceState(sessionId: event.id, studentId: kid.id, state: .present)
        XCTAssertNil(dm.contracts.first { $0.id == enrollment.id }?.bundleRedemptionsRemaining)
        XCTAssertTrue(dm.contracts.first { $0.id == enrollment.id }?.bundleSessionIds.isEmpty ?? false)
    }

    func testOneSharedBalanceServesBothClasses() {
        let shared = addBalance(10, program: nil)
        dm.setStudentAttendanceState(sessionId: classSession(monday).id, studentId: kid.id, state: .present)
        dm.setStudentAttendanceState(sessionId: classSession(wednesday, offsetDays: 2).id,
                                     studentId: kid.id, state: .present)
        XCTAssertEqual(remaining(shared), 8)
    }

    func testAClassScopedBalanceIgnoresOtherClasses() {
        let mondayOnly = addBalance(10, program: monday.id)
        dm.setStudentAttendanceState(sessionId: classSession(wednesday).id, studentId: kid.id, state: .present)
        XCTAssertEqual(remaining(mondayOnly), 10)
    }

    func testGroupClassNeverTouchesAPrivateBundle() {
        let bundle = Contract(studentId: kid.id, kind: .privateBundle, pricePerSession: 300, bundleSize: 10)
        dm.addContract(bundle)
        dm.setStudentAttendanceState(sessionId: classSession(monday).id, studentId: kid.id, state: .present)
        XCTAssertEqual(remaining(bundle), 10)
    }

    func testOldestBalanceIsUsedFirst() {
        let older = addBalance(1, bought: Date(timeIntervalSince1970: 1_500_000_000))
        let newer = addBalance(10, bought: Date(timeIntervalSince1970: 1_600_000_000))
        dm.setStudentAttendanceState(sessionId: classSession(monday).id, studentId: kid.id, state: .present)
        dm.setStudentAttendanceState(sessionId: classSession(monday, offsetDays: 7).id,
                                     studentId: kid.id, state: .present)
        XCTAssertEqual(remaining(older), 0)
        XCTAssertEqual(remaining(newer), 9)
    }

    func testSkipRefundsAGroupBalance() {
        let balance = addBalance(10)
        let event = classSession(monday)
        dm.setStudentAttendanceState(sessionId: event.id, studentId: kid.id, state: .present)
        var skipped = dm.sessionEvents.first { $0.id == event.id }!
        XCTAssertTrue(SessionLifecycle.apply(.skip(.weather), to: &skipped))
        dm.updateSessionEvent(skipped)
        XCTAssertEqual(remaining(balance), 10)
    }

    func testAddingASecondClassKeepsTheFirst() {
        let rosters = dm.programs.filter { $0.enrolledStudentIds.contains(kid.id) }.map(\.id)
        XCTAssertEqual(Set(rosters), [monday.id, wednesday.id])
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.programId, monday.id,
                       "The primary class is the first one; adding another does not re-home the student.")
    }
}
