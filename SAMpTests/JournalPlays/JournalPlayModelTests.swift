import Foundation
import SwiftData
import Testing
@testable import Hoopwise

/// The Journal's Plays tests run on Hoopwise's one in-memory test store
/// (CLAUDE.md: one container per test process, no CloudKit), wiped of plays
/// before each test. Serialized because they share it.
@MainActor
enum JournalPlayTestStore {
    static func freshContext() throws -> ModelContext {
        let context = SwiftDataManager.inMemoryForTesting().modelContext
        try context.delete(model: JournalPlay.self)
        try context.delete(model: JournalPlayPart.self)
        try context.delete(model: JournalPlayStep.self)
        try context.save()
        return context
    }
}

@MainActor
@Suite("Journal plays", .serialized)
struct JournalPlayModelTests {
    /// Rule 7a: CloudKit-compatible like every other model.
    @Test func playModelsAreCloudKitCompatible() {
        let names: Set<String> = ["JournalPlay", "JournalPlayPart", "JournalPlayStep"]
        let entities = SwiftDataManager.schema.entities.filter { names.contains($0.name) }
        #expect(entities.count == 3)
        for entity in entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique)
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name)")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name)")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name)")
            }
        }
    }

    /// Synced plays: a starter seeded twice (reinstall before iCloud brought
    /// the library back) keeps its oldest copy only.
    @Test func duplicateStartersKeepTheOldest() throws {
        let context = try JournalPlayTestStore.freshContext()
        let file = try #require(JournalPlayLibrary.load())
        let horns = try #require(file.plays.first { $0.key == "horns" })
        let first = JournalPlayLibrary.insert(horns, order: 0, into: context, language: .en)
        first.createdAt = Date(timeIntervalSince1970: 1_000)
        let second = JournalPlayLibrary.insert(horns, order: 1, into: context, language: .en)
        second.createdAt = Date(timeIntervalSince1970: 2_000)
        try context.save()
        #expect(JournalPlayLibrary.removeDuplicateStarters(context) == 1)
        let left = try context.fetch(FetchDescriptor<JournalPlay>())
        #expect(left.count == 1)
        #expect(left.first?.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(try context.fetchCount(FetchDescriptor<JournalPlayStep>()) == horns.parts.map(\.steps.count).reduce(0, +))
    }
}

/// The Plays strings follow Hoopwise's in-app language, not the system's.
@MainActor
struct JournalPlayStringsTests {
    @Test func stringsFollowTheAppLanguage() {
        #expect(jp("Delete play", chinese: false) == "Delete play")
        #expect(jp("Delete play", chinese: true) == "删除战术")
        #expect(jp("\(1) steps", chinese: false) == "1 step")
        #expect(jp("\(3) steps", chinese: false) == "3 steps")
        #expect(jp("\(3) steps", chinese: true) == "3 步")
        #expect(jp("legend.dribble", chinese: false) == "Dribble")
        #expect(jp("Not a key \(2)", chinese: true) == "Not a key 2")
    }

    @Test func everyCategoryAndToolHasChinese() {
        for category in JournalPlayCategory.allCases {
            #expect(JournalPlayStrings.table[category.label.key]?.zh != nil, "\(category)")
        }
        for kind in JournalPlayPartKind.allCases {
            #expect(JournalPlayStrings.table[kind.label.key]?.zh != nil, "\(kind)")
        }
    }
}
