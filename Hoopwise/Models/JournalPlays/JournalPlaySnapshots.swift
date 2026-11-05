import Foundation
import SwiftData

struct JournalPlayStepSnapshot {
    private let part: JournalPlayPart?
    private let order: Int
    private let caption: String
    private let text: String
    private let diagramData: Data?

    init(_ step: JournalPlayStep) {
        part = step.part
        order = step.order
        caption = step.caption
        text = step.text
        diagramData = step.diagramData
    }

    /// Back in its place: the steps from its old place on move down one.
    @discardableResult
    func restore(in context: ModelContext, into part: JournalPlayPart? = nil) -> JournalPlayStep {
        let step = JournalPlayStep(order: order, caption: caption, text: text)
        step.diagramData = diagramData
        context.insert(step)
        if let owner = part ?? self.part {
            for later in owner.steps ?? [] where later.order >= order { later.order += 1 }
            owner.steps?.append(step)
        }
        return step
    }
}

struct JournalPlayPartSnapshot {
    private let play: JournalPlay?
    private let kindRaw: String
    private let name: String
    private let notes: String
    private let order: Int
    private let steps: [JournalPlayStepSnapshot]

    init(_ part: JournalPlayPart) {
        play = part.play
        kindRaw = part.kindRaw
        name = part.name
        notes = part.notes
        order = part.order
        steps = part.sortedSteps.map(JournalPlayStepSnapshot.init)
    }

    @discardableResult
    func restore(in context: ModelContext, into play: JournalPlay? = nil) -> JournalPlayPart {
        let part = JournalPlayPart(kind: JournalPlayPartKind(rawValue: kindRaw) ?? .variation, name: name, order: order)
        context.insert(part)
        part.notes = notes
        (play ?? self.play)?.parts?.append(part)
        for step in steps { step.restore(in: context, into: part) }
        return part
    }
}

struct JournalPlaySnapshot {
    private let createdAt: Date
    private let name: String
    private let categoryRaw: String
    private let courtRaw: String
    private let situation: String
    private let concept: String
    private let source: String
    private let sourceURL: String?
    private let starterKey: String?
    private let order: Int
    private let parts: [JournalPlayPartSnapshot]

    init(_ play: JournalPlay) {
        createdAt = play.createdAt
        name = play.name
        categoryRaw = play.categoryRaw
        courtRaw = play.courtRaw
        situation = play.situation
        concept = play.concept
        source = play.source
        sourceURL = play.sourceURL
        starterKey = play.starterKey
        order = play.order
        parts = play.sortedParts.map(JournalPlayPartSnapshot.init)
    }

    @discardableResult
    func restore(in context: ModelContext) -> JournalPlay {
        let play = JournalPlay(name: name, category: .other, court: .half)
        context.insert(play)
        play.createdAt = createdAt
        play.categoryRaw = categoryRaw
        play.courtRaw = courtRaw
        play.situation = situation
        play.concept = concept
        play.source = source
        play.sourceURL = sourceURL
        play.starterKey = starterKey
        play.order = order
        for part in parts { part.restore(in: context, into: play) }
        return play
    }
}
