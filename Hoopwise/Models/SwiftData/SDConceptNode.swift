import Foundation
import SwiftData

/// What kind of thing a knowledge-base node is.
enum ConceptNodeType: String, Codable, CaseIterable, Hashable {
    case read
    case principle
    case play
    case coach
    case lineage
    case drill

    var displayName: String {
        switch self {
        case .read:      return "Read"
        case .principle: return "Principle"
        case .play:      return "Play"
        case .coach:     return "Coach"
        case .lineage:   return "Lineage"
        case .drill:     return "Drill"
        }
    }

    var icon: String {
        switch self {
        case .read:      return "eye"
        case .principle: return "flag"
        case .play:      return "sportscourt"
        case .coach:     return "person.bust"
        case .lineage:   return "arrow.triangle.branch"
        case .drill:     return "figure.basketball"
        }
    }
}

/// How much epistemic weight a claim carries.
///
/// Required on every node. Basketball writing routinely blurs measured fact,
/// widely-held opinion, and one coach's model; tagging forces the distinction
/// at authoring time, when it is still cheap to make.
enum EpistemicTag: String, Codable, CaseIterable, Hashable {
    /// Measurable and checkable. "The FIBA arc is 6.75m."
    case fact
    /// Broadly agreed among practitioners, but not measured.
    case consensus
    /// One coherent way of modelling something, held by a person or school.
    case framework

    var displayName: String {
        switch self {
        case .fact:      return "Fact"
        case .consensus: return "Consensus"
        case .framework: return "Framework"
        }
    }

    var shortLabel: String {
        switch self {
        case .fact:      return "FACT"
        case .consensus: return "CONSENSUS"
        case .framework: return "FRAMEWORK"
        }
    }
}

/// A node in the linked-concept store.
///
/// Mac-authored. Defined now, with no UI, so the CloudKit schema deploys once
/// and one iOS build carries every new record type — see CLAUDE.md rule 7.
@Model
final class SDConceptNode {
    var id: UUID = UUID()
    var typeRaw: String = ConceptNodeType.principle.rawValue
    /// Required in practice; the initializer will not let it default away.
    var epistemicTagRaw: String = EpistemicTag.framework.rawValue
    var title: String = ""
    /// Markdown.
    var body: String = ""
    /// Points at the domain record this node wraps, when it wraps one — an
    /// `SDPlay` for `.play`, an `SDDrill` for `.drill`. A plain id rather than
    /// a relationship because the target type varies by `type`.
    var refId: UUID?
    /// Optional `SDPlayDiagram` id to render inline in the node body.
    var embeddedDiagramId: UUID?
    var sourcesData: Data?
    var tagsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Bridges
    var type: ConceptNodeType {
        get { ConceptNodeType(rawValue: typeRaw) ?? .principle }
        set { typeRaw = newValue.rawValue }
    }

    var epistemicTag: EpistemicTag {
        get { EpistemicTag(rawValue: epistemicTagRaw) ?? .framework }
        set { epistemicTagRaw = newValue.rawValue }
    }

    /// Citations, URLs, book references.
    var sources: [String] {
        get { Self.decode(sourcesData) }
        set { sourcesData = try? JSONEncoder().encode(newValue) }
    }

    var tags: [String] {
        get { Self.decode(tagsData) }
        set { tagsData = try? JSONEncoder().encode(newValue) }
    }

    private static func decode(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// `epistemicTag` and `type` are required arguments with no defaults, so a
    /// node cannot be created untagged even though the stored column needs a
    /// default value for CloudKit.
    init(
        id: UUID = UUID(),
        type: ConceptNodeType,
        epistemicTag: EpistemicTag,
        title: String,
        body: String = "",
        refId: UUID? = nil,
        embeddedDiagramId: UUID? = nil,
        sources: [String] = [],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.epistemicTagRaw = epistemicTag.rawValue
        self.title = title
        self.body = body
        self.refId = refId
        self.embeddedDiagramId = embeddedDiagramId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        defer {
            self.sources = sources
            self.tags = tags
        }
    }
}
