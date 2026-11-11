import XCTest
@testable import Hoopwise

/// New Drill: Return in the description asks Claude for the steps and key
/// points. The request, the parsing and the two rules around it.
final class DrillWriterTests: XCTestCase {

    func testReturnIsTheEndOfTheDescriptionNotEveryLineBreak() {
        XCTAssertEqual(DrillWriter.pressedReturn(old: "Two lines", new: "Two lines\n"), "Two lines")
        XCTAssertNil(DrillWriter.pressedReturn(old: "Two", new: "Two lines\n"), "a paste is not a Return")
        XCTAssertNil(DrillWriter.pressedReturn(old: "Two lines", new: "Two linesX"))
    }

    func testItNeverWritesOverTheCoachsOwnLines() {
        XCTAssertTrue(DrillWriter.mayReplace([""], lastWritten: nil), "blank")
        XCTAssertTrue(DrillWriter.mayReplace(["Start at the baseline"], lastWritten: ["Start at the baseline"]), "still Claude's")
        XCTAssertFalse(DrillWriter.mayReplace(["My own step"], lastWritten: nil))
        XCTAssertFalse(DrillWriter.mayReplace(["Start at the baseline, edited"], lastWritten: ["Start at the baseline"]))
    }

    func testTheRequestAndTheAnswer() throws {
        let body = DrillWriter.requestBody(name: "2 vs 1 cone drill", description: "2 players start at the baseline",
                                           minPlayers: 3, minutes: 10)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        let user = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(user.contains("2 vs 1 cone drill") && user.contains("At least 3 players"))
        XCTAssertNotNil((body["output_config"] as? [String: Any])?["format"])

        let answer = #"{"instructions":["Two players start on the baseline."," ","Sprint to the cone."],"keyPoints":["Eyes up"]}"#
        let response: [String: Any] = ["content": [["type": "text", "text": answer]]]
        let result = try DrillWriter.parse(JSONSerialization.data(withJSONObject: response))
        XCTAssertEqual(result.instructions, ["Two players start on the baseline.", "Sprint to the cone."], "blank lines dropped")
        XCTAssertEqual(result.keyPoints, ["Eyes up"])
    }
}
