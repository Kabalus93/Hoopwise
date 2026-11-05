import Foundation
import SwiftData

/// A play in the library: when it's run, its idea, and its parts (the
/// concept, wrinkles and variations), each drawn step by step. Plays belong
/// to the athlete's library, not to a season.
///
/// CloudKit-ready (hard rule 1): defaults or optionals everywhere,
/// relationships optional with inverses.
@Model
final class JournalPlay {
    var createdAt: Date = Date.now
    var name: String = ""
    var categoryRaw: String = JournalPlayCategory.halfCourt.rawValue
    var courtRaw: String = JournalCourtKind.half.rawValue
    /// When you run it ("After a defensive rebound or made basket").
    var situation: String = ""
    /// The idea and the roles.
    var concept: String = ""
    /// Where it comes from ("Coach's Clipboard – Zone-23").
    var source: String = ""
    var sourceURL: String?
    /// Set on plays from the starter library, so they are added only once.
    var starterKey: String?
    var order: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \JournalPlayPart.play)
    var parts: [JournalPlayPart]? = []

    init(name: String, category: JournalPlayCategory, court: JournalCourtKind) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.courtRaw = court.rawValue
    }

    var category: JournalPlayCategory {
        get { JournalPlayCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var court: JournalCourtKind {
        get { JournalCourtKind(rawValue: courtRaw) ?? .half }
        set { courtRaw = newValue.rawValue }
    }

    var sortedParts: [JournalPlayPart] { (parts ?? []).sorted { $0.order < $1.order } }

    func parts(_ kind: JournalPlayPartKind) -> [JournalPlayPart] { sortedParts.filter { $0.kind == kind } }

    /// The concept: the play's base action.
    var conceptPart: JournalPlayPart? { parts(.concept).first }
}

/// The concept, a wrinkle or a variation of a play.
@Model
final class JournalPlayPart {
    var play: JournalPlay?
    var kindRaw: String = JournalPlayPartKind.concept.rawValue
    var name: String = ""
    var notes: String = ""
    var order: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \JournalPlayStep.part)
    var steps: [JournalPlayStep]? = []

    init(kind: JournalPlayPartKind, name: String, order: Int) {
        self.kindRaw = kind.rawValue
        self.name = name
        self.order = order
    }

    var kind: JournalPlayPartKind {
        get { JournalPlayPartKind(rawValue: kindRaw) ?? .variation }
        set { kindRaw = newValue.rawValue }
    }

    var sortedSteps: [JournalPlayStep] { (steps ?? []).sorted { $0.order < $1.order } }
}

/// One step: its diagram, a caption ("Set", "The read") and what to do.
@Model
final class JournalPlayStep {
    var part: JournalPlayPart?
    var order: Int = 0
    var caption: String = ""
    var text: String = ""
    /// The `JournalPlayDiagram`, as JSON.
    var diagramData: Data?

    init(order: Int, caption: String = "", text: String = "", diagram: JournalPlayDiagram = JournalPlayDiagram()) {
        self.order = order
        self.caption = caption
        self.text = text
        self.diagram = diagram
    }

    var diagram: JournalPlayDiagram {
        get { diagramData.flatMap { try? JSONDecoder().decode(JournalPlayDiagram.self, from: $0) } ?? JournalPlayDiagram() }
        set { diagramData = try? JSONEncoder().encode(newValue) }
    }
}
