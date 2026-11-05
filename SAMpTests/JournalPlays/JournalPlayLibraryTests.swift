import Foundation
import SwiftData
import Testing
@testable import Hoopwise

@MainActor
@Suite("Starter plays")
struct StarterPlaysTests {
    private static let file = JournalPlayLibrary.load()

    @Test func theStarterFileDecodes() throws {
        let file = try #require(Self.file)
        #expect(file.version >= 1)
        #expect(Set(file.plays.map(\.key)).count == file.plays.count)
        #expect(file.plays.map(\.key).contains("horns"))
    }

    /// Every play reads in both languages, and has a concept with steps.
    @Test func everyPlayIsWrittenInBothLanguages() throws {
        let file = try #require(Self.file)
        for play in file.plays {
            let texts = [play.name, play.situation, play.concept] + play.parts.flatMap { part in
                [part.name] + part.steps.flatMap { [$0.caption, $0.text] }
            }
            for text in texts {
                #expect(!text.en.isEmpty && !text.zh.isEmpty, "\(play.key): \(text.en)")
            }
            #expect(play.parts.first?.kind == .concept, "\(play.key)")
            #expect(play.parts.allSatisfy { !$0.steps.isEmpty }, "\(play.key)")
            for part in play.parts where part.kind != .concept {
                #expect(!part.notes.en.isEmpty && !part.notes.zh.isEmpty, "\(play.key) \(part.name.en)")
            }
        }
    }

    /// The drawings make sense: five players, actions by players who are
    /// there, passes to a teammate, paths that start at the player and stay
    /// near the court.
    @Test func everyDiagramIsWellFormed() throws {
        let file = try #require(Self.file)
        for play in file.plays {
            let size = play.court.size
            for part in play.parts {
                for (i, step) in part.steps.enumerated() {
                    let diagram = step.diagram.diagram(.en)
                    let label = "\(play.key) \(part.name.en) step \(i + 1)"
                    #expect(diagram.offense.map(\.number).sorted() == [1, 2, 3, 4, 5], "\(label)")
                    if let ball = diagram.ball { #expect(diagram.player(ball) != nil, "\(label)") }
                    for action in diagram.actions {
                        #expect(action.path.count >= 2, "\(label)")
                        if action.kind == .pass {
                            #expect(action.receiver.flatMap(diagram.player) != nil, "\(label)")
                        }
                        for point in action.path {
                            #expect((-JournalPlayCourt.margin...size.width + JournalPlayCourt.margin).contains(point.x), "\(label)")
                            #expect((-JournalPlayCourt.margin...size.height + JournalPlayCourt.margin).contains(point.y), "\(label)")
                        }
                    }
                    // A player's first move starts where they stand.
                    for player in diagram.offense {
                        if let first = diagram.actions.first(where: { $0.player == player.number && $0.kind != .pass }) {
                            #expect(first.path[0].distance(to: player.at) < 0.05, "\(label) player \(player.number)")
                        }
                    }
                }
            }
        }
    }

    /// Within a part, each step starts where the one before ended, so the
    /// playback runs on without jumps.
    @Test func stepsFollowOnFromEachOther() throws {
        let file = try #require(Self.file)
        for play in file.plays {
            for part in play.parts {
                let diagrams = part.steps.map { $0.diagram.diagram(.en) }
                for (before, after) in zip(diagrams, diagrams.dropFirst()) {
                    for player in after.offense {
                        let end = try #require(JournalPlayMath.endPosition(of: player.number, in: before))
                        #expect(end.distance(to: player.at) < 0.05,
                                "\(play.key) \(part.name.en): \(player.number) starts away from where it ended")
                    }
                }
            }
        }
    }
}

// Part of the serialized Model suite: it shares the test store.
extension JournalPlayModelTests {
    private func freshDefaults() throws -> UserDefaults {
        let name = "JournalPlayLibraryTests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func starterPlaysAreAddedOnce() throws {
        let context = try JournalPlayTestStore.freshContext()
        let defaults = try freshDefaults()
        let count = try #require(JournalPlayLibrary.load()).plays.count
        #expect(JournalPlayLibrary.seedIfNeeded(context, defaults: defaults, language: .en) == count)
        #expect(JournalPlayLibrary.seedIfNeeded(context, defaults: defaults, language: .en) == 0)
        #expect(try context.fetchCount(FetchDescriptor<JournalPlay>()) == count)

        // A play the athlete deleted stays deleted.
        let horns = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "horns" })
        #expect(horns.parts(.wrinkle).count == 2)
        context.delete(horns)
        try context.save()
        #expect(JournalPlayLibrary.seedIfNeeded(context, defaults: defaults, language: .en) == 0)
        #expect(try context.fetchCount(FetchDescriptor<JournalPlay>()) == count - 1)
    }

    @Test func addingTheStartersAgainBringsBackOnlyWhatIsMissing() throws {
        let context = try JournalPlayTestStore.freshContext()
        let count = try #require(JournalPlayLibrary.load()).plays.count
        JournalPlayLibrary.restoreStarters(context, language: .en)
        let box = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "box-1" })
        context.delete(box)
        try context.save()
        #expect(JournalPlayLibrary.restoreStarters(context, language: .en) == 1)
        #expect(try context.fetchCount(FetchDescriptor<JournalPlay>()) == count)
        // The restored play goes to the end of the library.
        let restored = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "box-1" })
        let orders = try context.fetch(FetchDescriptor<JournalPlay>()).map(\.order)
        #expect(restored.order == orders.max())
    }

    @Test func startersAreAddedInTheAppLanguage() throws {
        let context = try JournalPlayTestStore.freshContext()
        JournalPlayLibrary.restoreStarters(context, language: .zh)
        let horns = try #require(try context.fetch(FetchDescriptor<JournalPlay>()).first { $0.starterKey == "horns" })
        #expect(horns.name == "牛角战术")
        #expect(horns.conceptPart?.sortedSteps.first?.caption == "站位")
        #expect(horns.conceptPart?.sortedSteps.first?.diagram.offense.count == 5)
    }
}
