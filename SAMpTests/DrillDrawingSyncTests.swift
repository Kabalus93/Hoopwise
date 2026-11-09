import XCTest
import SwiftData
@testable import Hoopwise

/// Drill drawings sync through their SDDrillMedia row, and a library drill's
/// duplicate copies (one seeded per device) keep every visual.
final class DrillDrawingSyncTests: XCTestCase {

    func testTheDrawingRidesInTheRowAndReadsBackWithoutAFile() throws {
        var drawing = DrillDrawing.new()
        drawing.steps[0].caption = "Set"
        let payload = try XCTUnwrap(drawing.syncPayload)
        XCTAssertTrue(payload.hasPrefix(DrillDrawing.syncPrefix))
        XCTAssertEqual(DrillDrawing.decode(syncPayload: payload), drawing)
        XCTAssertNil(DrillDrawing.decode(syncPayload: "https://youtu.be/abc"), "a link is not a drawing")

        // Another device: the row arrived, its files did not.
        let media = DrillMedia(drillId: UUID(), kind: .courtDiagram, localPath: "DrillMedia/x/missing.jpg",
                               remoteURL: payload, strokesPath: "DrillMedia/x/missing.drawing.json")
        XCTAssertEqual(DrillDrawingMedia.drawing(for: media), drawing)
    }

    func testDuplicateLibraryDrillsKeepEveryVisual() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let activity = try XCTUnwrap(ActivityLibrary.shared.plannable.first)
        let here = SDDrill.from(ActivityLibrary.drill(for: activity))
        let there = SDDrill.from(ActivityLibrary.drill(for: activity))
        dm.modelContext.insert(here)
        dm.modelContext.insert(there)
        let drawn = SDDrillMedia(kind: .courtDiagram, remoteURL: DrillDrawing.new().syncPayload)
        drawn.drill = here
        dm.modelContext.insert(drawn)
        for _ in 0..<2 {
            let photo = SDDrillMedia(kind: .image)
            photo.drill = there
            dm.modelContext.insert(photo)
        }
        try dm.modelContext.save()

        dm.deduplicateDrills()

        let id = activity.id
        let left = try dm.modelContext.fetch(FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == id }))
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.media?.count, 3, "the drawing moved to the copy that stayed")
        XCTAssertEqual(try dm.modelContext.fetch(FetchDescriptor<SDDrillMedia>()).count, 3)
    }
}
