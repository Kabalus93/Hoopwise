import XCTest
@testable import Hoopwise

/// The coach's class list (上课名单): parse → plan → write → undo → export.
///
/// The fixture reproduces the real sheet's SHAPE — header row, class blocks
/// with 人数, sessions-or-months balances, a student shared by two classes,
/// a 长期不来 block, a 总人次 row and a class by another coach — with invented
/// names. Real class lists hold children's names and never enter the repo.
@MainActor
final class ClassListImportTests: XCTestCase {

    private func t(_ s: String) -> XLSXCell { .text(s) }
    private func n(_ v: Double) -> XLSXCell { .number(v) }
    private let e = XLSXCell.empty

    private var rows: [[XLSXCell]] {
        [
            [t("课程"), t("教练"), t("学生"), t("剩余课时(节)"), t("剩余时长(月)"), t("备注")],
            [t("周一 18:30 U6"), t("甲教练"), t("人数:"), n(3), e, e],
            [e, e, t("小明"), n(36), e, e],
            [e, e, t("小红"), e, n(8), e],
            [e, e, t("共享"), n(20), e, e],
            [t("周三 18:30 U6"), t("甲教练"), t("人数:"), n(2), e, e],
            [e, e, t("共享"), n(20), e, t("课时与其他班共用")],
            [e, e, t("小刚"), n(5), e, e],
            [t("周六 10:00 U12"), t("乙教练"), t("人数:"), n(1), e, e],
            [e, e, t("小强"), n(12), e, e],
            [t("长期不来"), e, t("人数:"), n(2), e, t("不计入总数")],
            [e, e, t("小美"), e, n(2), e],
            [t("甲教练 总人次"), e, e, n(5), e, t("同一学生上两节课计两次")],
        ]
    }

    // MARK: Parse

    func testParsesBlocksBalancesAndTheSheetsOwnChecks() throws {
        let sheet = try XCTUnwrap(ClassList.parse(rows: rows))
        XCTAssertEqual(sheet.blocks.count, 4)
        let monday = sheet.blocks[0]
        XCTAssertEqual(monday.weekday, .monday)
        XCTAssertEqual(monday.hour, 18); XCTAssertEqual(monday.minute, 30)
        XCTAssertEqual(monday.ageGroup, .u6)
        XCTAssertEqual(monday.coach, "甲教练")
        XCTAssertEqual(monday.entries.map(\.name), ["小明", "小红", "共享"])
        XCTAssertEqual(monday.entries[1].sessions, 32, "8 months at one class a week = 32 sessions")
        XCTAssertTrue(monday.entries[1].isMonthsBased)
        XCTAssertTrue(sheet.blocks[3].isUnscheduled, "长期不来 has no schedule")
        XCTAssertEqual(sheet.declaredTotal, 5)
        XCTAssertEqual(sheet.totalCoach, "甲教练")
        // 长期不来 declares 2 and lists 1 — exactly the kind of typo the real
        // sheet carried. The coach's own total (5) matches their classes.
        XCTAssertEqual(sheet.issues.map(\.message).filter { $0.contains("人数") }.count, 1)
        XCTAssertFalse(sheet.issues.contains { $0.message.contains("总人次") })
    }

    func testParsesTitleVariants() {
        var block = ClassList.Block(title: "", entries: [], row: 1)
        ClassList.parseTitle("星期日15:00 U10", into: &block)
        XCTAssertEqual(block.weekday, .sunday); XCTAssertEqual(block.hour, 15); XCTAssertEqual(block.ageGroup, .u10)
        block = ClassList.Block(title: "", entries: [], row: 1)
        ClassList.parseTitle("周五 19：00 U7", into: &block)
        XCTAssertEqual(block.weekday, .friday); XCTAssertEqual(block.minute, 0)
        XCTAssertEqual(block.ageGroup, .u8, "odd bands round up to the app's categories")
    }

    // MARK: Plan + write

    private var dm: SwiftDataManager!

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
    }

    override func tearDown() async throws {
        dm = nil
        try await super.tearDown()
    }

    /// Two weeks starting on a Monday.
    private var options: ClassList.Options {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 2
        let from = Calendar.current.date(from: c)!
        return ClassList.Options(from: from, through: from.addingTimeInterval(13 * 86_400))
    }

    private func makePlan() throws -> ClassList.Plan {
        let sheet = try XCTUnwrap(ClassList.parse(rows: rows))
        return ClassList.plan(sheet, students: dm.students, contracts: dm.contracts,
                              programs: dm.programs, sessions: dm.sessionEvents,
                              coaches: [], accountCoach: nil, options: options)
    }

    func testPlanOneStudentPerNameAndWeeklySessions() throws {
        let plan = try makePlan()
        XCTAssertEqual(plan.students.count, 6, "共享 appears twice but is one student")
        XCTAssertEqual(plan.classes.count, 3)
        XCTAssertEqual(plan.classes.map(\.sessionStarts.count), [2, 2, 2], "two weeks, one class a week")
        let shared = try XCTUnwrap(plan.students.first { $0.name == "共享" })
        XCTAssertEqual(plan.classes.filter { $0.studentIds.contains(shared.id) }.count, 2)
        XCTAssertEqual(plan.withoutClass.count, 1, "小美 (长期不来) gets a balance and no class")
    }

    func testApplyWritesBalancesRostersAndCalendarAndUndoRemovesThem() throws {
        let plan = try makePlan()
        let result = dm.applyClassListImport(plan)

        XCTAssertEqual(dm.students.count, 6)
        XCTAssertEqual(dm.programs.count, 3)
        XCTAssertEqual(dm.sessionEvents.count, 6)
        let shared = try XCTUnwrap(dm.students.first { $0.name == "共享" })
        let rosters = dm.programs.filter { $0.enrolledStudentIds.contains(shared.id) }
        XCTAssertEqual(rosters.count, 2, "a shared student is on both classes")
        let balance = try XCTUnwrap(dm.contracts.first { $0.studentId == shared.id })
        XCTAssertEqual(balance.kind, .group)
        XCTAssertEqual(balance.bundleRedemptionsRemaining, 20)
        XCTAssertNil(balance.programId, "one balance shared across classes")
        let monthly = try XCTUnwrap(dm.students.first { $0.name == "小红" })
        let monthlyBalance = try XCTUnwrap(dm.contracts.first { $0.studentId == monthly.id })
        XCTAssertEqual(monthlyBalance.bundleRedemptionsRemaining, 32)
        XCTAssertTrue(monthlyBalance.notes?.contains(ClassList.monthsMarker) ?? false)

        // Attending either class draws on the one shared balance.
        let mondayClass = try XCTUnwrap(dm.sessionEvents.first {
            rosters.map(\.id).contains($0.programId ?? UUID())
        })
        dm.setStudentAttendanceState(sessionId: mondayClass.id, studentId: shared.id, state: .present)
        XCTAssertEqual(dm.contracts.first { $0.id == balance.id }?.bundleRedemptionsRemaining, 19)

        dm.undoClassListImport(result)
        XCTAssertTrue(dm.students.isEmpty)
        XCTAssertTrue(dm.programs.isEmpty)
        XCTAssertTrue(dm.sessionEvents.isEmpty)
        XCTAssertTrue(dm.contracts.filter { $0.kind == .group && $0.hasSessionBalance }.isEmpty)
    }

    func testReimportNeverDoublesABalance() throws {
        dm.applyClassListImport(try makePlan())
        let second = try makePlan()
        XCTAssertEqual(second.newStudentCount, 0)
        XCTAssertEqual(second.balanceCount, 0, "existing balances are kept, not added to")
        XCTAssertEqual(second.newClassCount, 0, "classes match their programs by slot")
        XCTAssertEqual(second.sessionCount, 0, "days that already have a session are skipped")
    }

    // MARK: Export

    func testExportReadsBackAsTheSameSheet() throws {
        dm.applyClassListImport(try makePlan())
        let sheets = ClassList.export(programs: dm.programs, students: dm.students,
                                      contracts: dm.contracts, coaches: [], accountCoach: nil)
        let data = try XLSX.write(sheets)
        let reread = try XLSX.read(data)
        let main = try XCTUnwrap(ClassList.parse(reread))
        XCTAssertEqual(main.blocks.map(\.canonicalTitle), ["周一 18:30 U6", "周三 18:30 U6", "周六 10:00 U12"])
        let monday = main.blocks[0]
        XCTAssertEqual(monday.entries.first { $0.name == "小明" }?.sessionsLeft, 36)
        XCTAssertEqual(monday.entries.first { $0.name == "小红" }?.monthsLeft, 8,
                       "a months balance exports in months")
        let wednesday = main.blocks[1]
        XCTAssertEqual(wednesday.entries.first { $0.name == "共享" }?.note, "课时与其他班共用")
        XCTAssertTrue(reread.contains { $0.name == "长期不来" })
    }
}
