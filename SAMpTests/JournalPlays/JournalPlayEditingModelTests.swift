import Foundation
import SwiftData
import Testing
@testable import Hoopwise

// Part of the serialized Model suite: it shares the test store.
extension JournalPlayModelTests {
    @Test func aNewPlayHasAConceptReadyToDraw() throws {
        let context = try JournalPlayTestStore.freshContext()
        let first = JournalPlay.create(name: "Spain", category: .halfCourt, court: .half, in: context)
        let second = JournalPlay.create(name: "Floppy", category: .halfCourt, court: .half, in: context)
        try context.save()
        #expect(second.order == first.order + 1)
        let concept = try #require(second.conceptPart)
        #expect(concept.name == "Floppy")
        #expect(concept.sortedSteps.map(\.diagram) == [JournalPlayMath.defaultAlignment(.half)])
    }

    @Test func aWrinkleStartsFromTheConceptsSet() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = JournalPlay.create(name: "Horns", category: .halfCourt, court: .half, in: context)
        play.conceptPart?.sortedSteps.first?.diagram = JournalPlayMathTests.entry
        let twist = play.addPart(.wrinkle, name: "Twist", in: context)
        try context.save()
        let start = try #require(twist.sortedSteps.first?.diagram)
        #expect(start.offense == JournalPlayMathTests.entry.offense)
        #expect(start.actions.isEmpty)
        #expect(play.parts(.wrinkle).map(\.name) == ["Twist"])
    }

    @Test func aStepAfterAnotherStartsWhereItEnds() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = JournalPlay.create(name: "Zone", category: .halfCourt, court: .half, in: context)
        let concept = try #require(play.conceptPart)
        let first = try #require(concept.sortedSteps.first)
        first.diagram = JournalPlayMathTests.entry
        let last = concept.addStep(after: first, in: context)
        // A step put between the two: the last moves down one.
        let middle = concept.addStep(after: first, in: context)
        try context.save()
        #expect(concept.sortedSteps.map(\.persistentModelID) == [first, middle, last].map(\.persistentModelID))
        #expect(middle.diagram == JournalPlayMath.startOfNextStep(after: JournalPlayMathTests.entry))
        concept.moveStep(middle, by: 1)
        #expect(concept.sortedSteps.map(\.persistentModelID) == [first, last, middle].map(\.persistentModelID))
    }

    @Test func partsMoveWithinTheirKind() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = JournalPlay.create(name: "Horns", category: .halfCourt, court: .half, in: context)
        let twist = play.addPart(.wrinkle, name: "Twist", in: context)
        let down = play.addPart(.variation, name: "Down", in: context)
        let flare = play.addPart(.wrinkle, name: "Flare", in: context)
        play.movePart(flare, by: -1)
        #expect(play.parts(.wrinkle).map(\.name) == ["Flare", "Twist"])
        #expect(play.parts(.variation).map(\.name) == ["Down"])
        play.movePart(down, by: 1)  // nothing below: no change
        #expect(play.parts(.variation).map(\.name) == ["Down"])
        _ = twist
    }

    @Test func changingTheCourtRedrawsEveryStep() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = JournalPlay.create(name: "Break", category: .transition, court: .half, in: context)
        play.changeCourt(to: .full)
        #expect(play.court == .full)
        let step = try #require(play.conceptPart?.sortedSteps.first)
        #expect(step.diagram == JournalPlayMath.converted(JournalPlayMath.defaultAlignment(.half), from: .half, to: .full))
    }

    @Test func aDeletedPlayComesBackWhole() throws {
        let context = try JournalPlayTestStore.freshContext()
        JournalPlayLibrary.restoreStarters(context, language: .en)
        let horns = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "horns" })
        let before = horns.sortedParts.map { ($0.name, $0.sortedSteps.map(\.diagram)) }
        let snapshot = JournalPlaySnapshot(horns)
        context.delete(horns)
        try context.save()
        let restored = snapshot.restore(in: context)
        try context.save()
        #expect(restored.starterKey == "horns")
        let after = restored.sortedParts.map { ($0.name, $0.sortedSteps.map(\.diagram)) }
        #expect(after.map(\.0) == before.map(\.0))
        #expect(after.map(\.1) == before.map(\.1))
        // Restoring the starters doesn't add Horns twice.
        #expect(JournalPlayLibrary.restoreStarters(context, language: .en) == 0)
    }

    @Test func aDeletedStepComesBackInItsPlace() throws {
        let context = try JournalPlayTestStore.freshContext()
        JournalPlayLibrary.restoreStarters(context, language: .en)
        let horns = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "horns" })
        let concept = try #require(horns.conceptPart)
        let captions = concept.sortedSteps.map(\.caption)
        let middle = concept.sortedSteps[1]
        let snapshot = JournalPlayStepSnapshot(middle)
        context.delete(middle)
        try context.save()
        concept.renumberSteps()
        #expect(concept.sortedSteps.map(\.caption) == [captions[0], captions[2]])
        snapshot.restore(in: context, into: concept)
        try context.save()
        #expect(concept.sortedSteps.map(\.caption) == captions)
    }

    @Test func aDeletedPartComesBackWithItsSteps() throws {
        let context = try JournalPlayTestStore.freshContext()
        JournalPlayLibrary.restoreStarters(context, language: .en)
        let horns = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "horns" })
        let flare = try #require(horns.parts(.wrinkle).last)
        let steps = flare.sortedSteps.map(\.diagram)
        let snapshot = JournalPlayPartSnapshot(flare)
        context.delete(flare)
        try context.save()
        #expect(horns.parts(.wrinkle).count == 1)
        snapshot.restore(in: context)
        try context.save()
        #expect(horns.parts(.wrinkle).map(\.name) == ["Twist", "Flare"])
        #expect(horns.parts(.wrinkle).last?.sortedSteps.map(\.diagram) == steps)
    }
}
