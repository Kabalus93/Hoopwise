import Foundation
import SwiftData

// Writing plays: a new play, its parts and steps, their order. Models are
// linked from the parent's side (see the decisions log).

extension JournalPlay {
    /// A new play at the end of the library, with its concept and a first
    /// step in the default alignment.
    @discardableResult
    static func create(name: String, category: JournalPlayCategory, court: JournalCourtKind, in context: ModelContext) -> JournalPlay {
        let play = JournalPlay(name: name, category: category, court: court)
        context.insert(play)
        let last = ((try? context.fetch(FetchDescriptor<JournalPlay>())) ?? []).filter { $0 !== play }.map(\.order).max()
        play.order = (last ?? -1) + 1
        let concept = JournalPlayPart(kind: .concept, name: name, order: 0)
        context.insert(concept)
        play.parts?.append(concept)
        concept.addStep(after: nil, in: context)
        return play
    }

    /// A wrinkle or variation at the end of its kind. Its first step starts
    /// from the concept's set, without the concept's lines.
    @discardableResult
    func addPart(_ kind: JournalPlayPartKind, name: String, in context: ModelContext) -> JournalPlayPart {
        let part = JournalPlayPart(kind: kind, name: name, order: (sortedParts.map(\.order).max() ?? -1) + 1)
        context.insert(part)
        parts?.append(part)
        var start = conceptPart?.sortedSteps.first?.diagram ?? JournalPlayMath.defaultAlignment(court)
        start.actions = []
        start.notes = []
        let step = JournalPlayStep(order: 0, diagram: start)
        context.insert(step)
        part.steps?.append(step)
        return part
    }

    /// Moves a part up or down among the parts of its kind.
    func movePart(_ part: JournalPlayPart, by offset: Int) {
        var same = parts(part.kind)
        guard let i = same.firstIndex(where: { $0 === part }), same.indices.contains(i + offset) else { return }
        same.swapAt(i, i + offset)
        let orders = parts(part.kind).map(\.order)
        for (part, order) in zip(same, orders) { part.order = order }
    }

    /// The same plays drawn on the other court (see `JournalPlayMath.converted`).
    func changeCourt(to newCourt: JournalCourtKind) {
        guard newCourt != court else { return }
        for part in parts ?? [] {
            for step in part.steps ?? [] {
                step.diagram = JournalPlayMath.converted(step.diagram, from: court, to: newCourt)
            }
        }
        court = newCourt
    }
}

extension JournalPlayPart {
    /// A step after `step` (or at the end), starting where that one ends.
    /// The first step of an empty part starts from the default alignment.
    @discardableResult
    func addStep(after step: JournalPlayStep?, in context: ModelContext) -> JournalPlayStep {
        let steps = sortedSteps
        let previous = step ?? steps.last
        let diagram = previous.map { JournalPlayMath.startOfNextStep(after: $0.diagram) }
            ?? JournalPlayMath.defaultAlignment(play?.court ?? .half)
        let order = previous.map { $0.order + 1 } ?? 0
        for later in steps where later.order >= order { later.order += 1 }
        let new = JournalPlayStep(order: order, diagram: diagram)
        context.insert(new)
        self.steps?.append(new)
        return new
    }

    /// Moves a step one place earlier or later.
    func moveStep(_ step: JournalPlayStep, by offset: Int) {
        var steps = sortedSteps
        guard let i = steps.firstIndex(where: { $0 === step }), steps.indices.contains(i + offset) else { return }
        steps.swapAt(i, i + offset)
        for (order, step) in steps.enumerated() { step.order = order }
    }

    /// Closes the gap a deleted step leaves.
    func renumberSteps() {
        for (order, step) in sortedSteps.enumerated() { step.order = order }
    }
}
