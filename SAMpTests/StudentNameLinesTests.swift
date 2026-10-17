import XCTest
@testable import Hoopwise

/// In Chinese the Chinese name is the big line and pinyin the small one;
/// otherwise the reverse. An empty or identical Chinese name adds nothing.
@MainActor
final class StudentNameLinesTests: XCTestCase {

    private var saved: AppLanguage!

    override func setUp() { saved = LocalizationManager.shared.currentLanguage }
    override func tearDown() { LocalizationManager.shared.currentLanguage = saved }

    private func kid(_ chinese: String?) -> Student {
        var s = Student(name: "Wáng Shī Líng")
        s.chineseName = chinese
        return s
    }

    func testChineseModePutsHanziFirst() {
        LocalizationManager.shared.currentLanguage = .chinese
        XCTAssertEqual(kid("王诗玲").primaryDisplayName, "王诗玲")
        XCTAssertEqual(kid("王诗玲").secondaryNameLine, "Wáng Shī Líng")
    }

    func testEnglishModeKeepsPinyinFirst() {
        LocalizationManager.shared.currentLanguage = .english
        XCTAssertEqual(kid("王诗玲").primaryDisplayName, "Wáng Shī Líng")
        XCTAssertEqual(kid("王诗玲").secondaryNameLine, "王诗玲")
    }

    func testEmptyOrSameChineseNameAddsNothing() {
        LocalizationManager.shared.currentLanguage = .chinese
        XCTAssertEqual(kid("").primaryDisplayName, "Wáng Shī Líng", "never a blank name")
        XCTAssertNil(kid("").secondaryNameLine)
        XCTAssertNil(kid("Wáng Shī Líng").secondaryNameLine)
        XCTAssertNil(kid(nil).secondaryNameLine)
    }
}
