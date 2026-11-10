import XCTest
@testable import Hoopwise

/// Hub → Lexicon: the bundled lexicon loads whole and search finds by name,
/// other name and definition.
final class LexiconTests: XCTestCase {
    private let lexicon = Lexicon.shared

    func testTheWholeLexiconLoads() {
        XCTAssertEqual(lexicon.sections.count, 16)
        XCTAssertEqual(lexicon.entryCount, 601)
        XCTAssertEqual(lexicon.sources.count, 77)
        let compare = lexicon.all.filter { $0.group.kind == .compare }
        XCTAssertFalse(compare.isEmpty)
        for row in compare {
            XCTAssertEqual(row.entry.values?.count, row.group.columns?.count, row.entry.term)
        }
        for item in lexicon.all {
            XCTAssertFalse(item.entry.term.contains("*"), item.entry.term)
            for n in item.entry.sources { XCTAssertNotNil(lexicon.source(n), "\(item.entry.term) cites \(n)") }
        }
    }

    func testSearchPutsTheTermFirstThenOtherNamesThenDefinitions() {
        XCTAssertEqual(lexicon.search("pick-and-roll").first?.entry.term, "Pick-and-roll")
        XCTAssertTrue(lexicon.search("PnR").contains { $0.entry.term == "Pick-and-roll" }, "other names count")
        XCTAssertTrue(lexicon.search("shot clock").contains { $0.group.kind == .compare }, "rule rows are found")
        XCTAssertTrue(lexicon.search("zzzz qqqq").isEmpty)
    }

    func testAnEntryLinksTheTermsItMentionsAndItsDispute() throws {
        let pnr = try XCTUnwrap(lexicon.all.first { $0.entry.term == "Pick-and-roll" })
        XCTAssertFalse(lexicon.related(to: pnr).contains { $0.entry.term == pnr.entry.term }, "never itself")
        let restricted = try XCTUnwrap(lexicon.all.first { $0.group.kind == .terms && $0.entry.term == "Restricted area arc" })
        XCTAssertNotNil(lexicon.dispute(for: restricted), "a disputed term points at its meanings")
    }
}
