import Foundation
import SwiftData
import Testing
@testable import Hoopwise

// Part of the serialized Model suite: it shares the test store.
extension JournalPlayModelTests {
    private func horns(in context: ModelContext) -> JournalPlay {
        let play = JournalPlay(name: "Horns", category: .halfCourt, court: .half)
        context.insert(play)
        let concept = JournalPlayPart(kind: .concept, name: "Horns", order: 0)
        context.insert(concept)
        play.parts?.append(concept)
        let step = JournalPlayStep(order: 0, caption: "Set", diagram: JournalPlayMathTests.entry)
        context.insert(step)
        concept.steps?.append(step)
        let flare = JournalPlayPart(kind: .wrinkle, name: "Flare", order: 1)
        context.insert(flare)
        play.parts?.append(flare)
        return play
    }

    @Test func aStepKeepsItsDiagram() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = horns(in: context)
        try context.save()
        let step = try #require(play.conceptPart?.sortedSteps.first)
        #expect(step.diagram == JournalPlayMathTests.entry)
        #expect(play.parts(.wrinkle).map(\.name) == ["Flare"])
        #expect(play.category == .halfCourt && play.court == .half)
    }

    @Test func deletingAPlayDeletesItsPartsAndSteps() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = horns(in: context)
        try context.save()
        context.delete(play)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<JournalPlayPart>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<JournalPlayStep>()) == 0)
    }

}
