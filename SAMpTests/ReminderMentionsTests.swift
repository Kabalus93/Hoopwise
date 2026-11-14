import XCTest
@testable import Hoopwise

/// "@" tagging in reminders and the context a reminder carries
/// (14 November 2026).
@MainActor
final class ReminderMentionsTests: XCTestCase {

    func testActiveQuery() {
        XCTAssertEqual(ReminderMentions.activeQuery(in: "buy a bracelet for @ma"), "ma")
        XCTAssertEqual(ReminderMentions.activeQuery(in: "@"), "")
        XCTAssertEqual(ReminderMentions.activeQuery(in: "call @Maya C"), "Maya C")
        XCTAssertNil(ReminderMentions.activeQuery(in: "no mention here"))
        XCTAssertNil(ReminderMentions.activeQuery(in: "mail luther@example.com"), "an email is not a mention")
        XCTAssertNil(ReminderMentions.activeQuery(in: "@maya is late again today"), "a sentence after the @ is text again")
    }

    func testInsertingReplacesTheQuery() {
        XCTAssertEqual(ReminderMentions.inserting("Maya Chen", into: "buy a bracelet for @ma"), "buy a bracelet for Maya Chen ")
    }

    func testMatchesPreferTheRosterAndFindPinyinAndChinese() {
        let maya = Student(name: "Maya Chen")
        let cai = Student(name: "Cài Yī Míng", chineseName: "蔡一铭")
        let mason = Student(name: "Mason Lee")
        let all = [maya, cai, mason]
        XCTAssertEqual(ReminderMentions.matches("ma", in: all, preferred: [mason.id]).map(\.id), [mason.id, maya.id])
        XCTAssertEqual(ReminderMentions.matches("cai", in: all).map(\.id), [cai.id])
        XCTAssertEqual(ReminderMentions.matches("蔡", in: all).map(\.id), [cai.id])
        XCTAssertEqual(ReminderMentions.matches("", in: all, preferred: [maya.id]).map(\.id), [maya.id],
                       "a bare @ lists the session's athletes")
    }

    func testTaggedRemindersAndContext() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let maya = Student(name: "Maya Chen")
        dm.addStudent(maya)
        let reminder = Reminder(title: "Bring her a bracelet", dueDate: Date(), taggedStudentIds: [maya.id])
        dm.addReminder(reminder)
        dm.addReminder(Reminder(title: "Untagged", dueDate: Date()))
        XCTAssertEqual(dm.openReminders(taggedWith: maya.id).map(\.title), ["Bring her a bracelet"])
        XCTAssertEqual(dm.reminderContext(reminder), "Maya Chen")
    }
}
