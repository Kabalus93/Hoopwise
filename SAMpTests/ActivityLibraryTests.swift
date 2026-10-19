import XCTest
import SwiftData
@testable import Hoopwise

/// The activity library replaced the 121 bundled sample drills (October 2026).
@MainActor
final class ActivityLibraryTests: XCTestCase {

    private var dm: SwiftDataManager!

    override func setUp() async throws {
        dm = SwiftDataManager.inMemoryForTesting()
    }

    private func drills() throws -> [SDDrill] { try dm.modelContext.fetch(FetchDescriptor<SDDrill>()) }

    func testTheWholeLibraryDecodes() {
        let lib = ActivityLibrary.shared
        XCTAssertEqual(lib.items.count, 476)
        XCTAssertEqual(lib.tabs.map(\.age), ActivityAge.allCases)
        XCTAssertEqual(lib.items.filter(\.isRule).count, 54)
        XCTAssertEqual(lib.plannable.count, 422)
        XCTAssertEqual(Set(lib.items.map(\.key)).count, 476, "keys are unique")
    }

    func testIdsAreDeterministicAndUnique() {
        let lib = ActivityLibrary.shared
        XCTAssertEqual(Set(lib.items.map(\.id)).count, lib.items.count)
        XCTAssertEqual(ActivityLibrary.drillId(forKey: "U8|routine|Cone Dribbling"),
                       ActivityLibrary.drillId(forKey: "U8|routine|Cone Dribbling"),
                       "every device must seed the same id")
    }

    func testSyncReplacesTheOldSamplesAndKeepsCoachDrills() throws {
        let legacy = SDDrill.from(DrillItem(name: "Pick and Roll", category: .offense))
        let coachOwn = SDDrill.from(DrillItem(name: "Suicides", category: .conditioning))
        coachOwn.createdByCoachId = UUID()                 // a coach made this one
        dm.modelContext.insert(legacy)
        dm.modelContext.insert(coachOwn)
        try dm.modelContext.save()

        dm.syncActivityLibrary()
        let after = try drills()
        XCTAssertFalse(after.contains { $0.id == legacy.id }, "bundled sample removed")
        XCTAssertTrue(after.contains { $0.id == coachOwn.id }, "a coach's own drill is never removed")
        XCTAssertEqual(after.filter { ActivityLibrary.activity(forDrillId: $0.id) != nil }.count, 422)
        XCTAssertFalse(after.contains { ActivityLibrary.activity(forDrillId: $0.id)?.isRule == true },
                       "rule options never become drills")

        dm.syncActivityLibrary()
        XCTAssertEqual(try drills().count, after.count, "idempotent")
    }

    func testSameNameAtTwoAgesSurvivesDedupe() throws {
        dm.syncActivityLibrary()
        let before = try drills().count
        dm.deduplicateDrills()
        XCTAssertEqual(try drills().count, before, "library drills dedupe by id, not by name")
    }

    func testRulesAndPlannerTags() {
        let u7 = ActivityLibrary.shared.items.first { $0.age == .u7 && !$0.isRule }!
        let drill = ActivityLibrary.drill(for: u7)
        XCTAssertTrue(drill.tags.contains("u8"), "U7 plans as U8")
        XCTAssertTrue(drill.isLibraryDrill)
        XCTAssertEqual(drill.libraryActivity?.key, u7.key)
    }
}
