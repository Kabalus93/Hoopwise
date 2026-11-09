import Foundation
import Testing
@testable import Hoopwise

/// "Describe a drill" (Mac drills page): the catalog Claude reads, the request
/// it is sent, reading its answer, and the on-device fallback.
struct DrillFinderTests {
    static let library = ActivityLibrary.shared.items
    static let keepingOff = library.first { $0.name == "20 Passes, Keeping Off" }!

    static func entries(personal: [DrillItem] = []) -> [DrillFinderEntry] {
        DrillFinder.entries(library: library, personal: personal)
    }

    @Test func theCatalogHoldsEveryPlannableActivityAndNoRuleOptions() {
        let entries = Self.entries()
        #expect(entries.count == ActivityLibrary.shared.plannable.count)
        #expect(entries.contains { $0.drillId == Self.keepingOff.id })
        let line = DrillFinder.line(entries.first { $0.drillId == Self.keepingOff.id }!)
        #expect(line.hasPrefix(String(Self.keepingOff.id.uuidString.prefix(8)).lowercased() + " | U7"))
        #expect(line.contains("20 Passes, Keeping Off / 传球20次（有抢断）"))
        // Refs are unique, so an answer maps to exactly one drill.
        #expect(Set(entries.map(\.ref)).count == entries.count)
    }

    @Test func theRequestCachesTheLibraryAndAsksForStrictJSON() throws {
        let personal = [DrillItem(name: "Drive and kick", category: .offense, description: "45° drive, kick to the corner")]
        let body = DrillFinder.requestBody(description: "pass 10 times", entries: Self.entries(personal: personal), chinese: false)
        #expect(body["model"] as? String == "claude-haiku-4-5")
        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.count == 2)
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect(system[1]["cache_control"] == nil, "personal drills sit after the breakpoint")
        #expect((system[0]["text"] as? String)?.contains("20 Passes, Keeping Off") == true)
        #expect((system[1]["text"] as? String)?.contains("Drive and kick") == true)
        // The library half is far above Haiku 4.5's 4096-token cache minimum.
        #expect(((system[0]["text"] as? String)?.count ?? 0) > 4096 * 4)
        let format = try #require((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        // Same text whatever the description: only the user message varies.
        let other = DrillFinder.requestBody(description: "something else", entries: Self.entries(personal: personal), chinese: true)
        #expect((other["system"] as? [[String: Any]])?[0]["text"] as? String == system[0]["text"] as? String)
        #expect(JSONSerialization.isValidJSONObject(body))
    }

    @Test func claudesAnswerMapsToDrillsAndDropsWhatIsNotInTheCatalog() throws {
        let entries = Self.entries()
        let ref = String(Self.keepingOff.id.uuidString.prefix(8)).lowercased()
        let answer = #"{"matches":[{"id":"\#(ref)","why":"counts to 20, not 10; one team defends"},{"id":"deadbeef","why":"not real"},{"id":"\#(ref.uppercased())","why":"duplicate"}],"note":""}"#
        let response = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": answer]]])
        let result = try DrillFinder.parse(response, entries: entries)
        #expect(result.matches.map(\.drillId) == [Self.keepingOff.id])
        #expect(result.matches.first?.why == "counts to 20, not 10; one team defends")
        #expect(result.source == .claude)
        #expect(throws: DrillFinderError.self) { try DrillFinder.parse(Data("{}".utf8), entries: entries) }
    }

    @Test func onDeviceFindsDrillsDescribedByTheirWords() {
        let result = DrillFinder.rankOnDevice("dribble around cones and race back", entries: Self.entries())
        let names = result.matches.prefix(3).compactMap { m in Self.library.first { $0.id == m.drillId }?.name }
        #expect(names.contains("Dribble Slalom Relay Races"), "\(names)")
        #expect(result.source == .onDevice)
    }

    @Test func aKeyIsKeptInTheKeychain() {
        let before = AnthropicKeyStore.key
        defer { if let before { AnthropicKeyStore.save(before) } else { AnthropicKeyStore.remove() } }
        #expect(AnthropicKeyStore.save("sk-ant-test-123"))
        #expect(AnthropicKeyStore.key == "sk-ant-test-123")
        AnthropicKeyStore.remove()
        #expect(AnthropicKeyStore.key == nil)
    }
}

/// The session plan picker's as-you-type search.
struct DrillTypedSearchTests {
    @Test func everyWordAnywhereInAnyOrder() {
        let fields = ["20 Passes, Keeping Off", "Two teams; the side with the ball tries to make 20 passes while the others defend."]
        #expect(DrillFinder.typedMatch("defend pass", in: fields))
        #expect(DrillFinder.typedMatch("KEEPING", in: fields))
        #expect(!DrillFinder.typedMatch("pass shoot", in: fields))
        #expect(DrillFinder.typedMatch("   ", in: fields))
    }

    @Test func hanziAndAccents() {
        #expect(DrillFinder.typedMatch("传球", in: ["20次传球抢断"]))
        #expect(DrillFinder.typedMatch("cafe", in: ["Café drill"]))
    }
}
