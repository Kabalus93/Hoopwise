import Foundation
import SwiftData

/// What one node asserts about another.
enum ConceptLinkType: String, Codable, CaseIterable, Hashable {
    /// Untyped association.
    case relates
    /// Source is a specific instance of the target.
    case exampleOf
    /// Source is built on top of the target.
    case derivesFrom
    /// Source argues against the target. Both survive; disagreement is data.
    case refutes
    /// Source is a prerequisite for understanding the target.
    case prerequisiteFor
    /// Source teaches or coaches the target.
    case teaches

    var displayName: String {
        switch self {
        case .relates:         return "Relates to"
        case .exampleOf:       return "Example of"
        case .derivesFrom:     return "Derives from"
        case .refutes:         return "Refutes"
        case .prerequisiteFor: return "Prerequisite for"
        case .teaches:         return "Teaches"
        }
    }

    /// Wording when the link is read from the far end.
    var inverseDisplayName: String {
        switch self {
        case .relates:         return "Relates to"
        case .exampleOf:       return "Has example"
        case .derivesFrom:     return "Basis for"
        case .refutes:         return "Refuted by"
        case .prerequisiteFor: return "Requires"
        case .teaches:         return "Taught by"
        }
    }
}

/// A directed edge between two `SDConceptNode`s.
///
/// Links are their own record type rather than SwiftData inverse
/// relationships. Bidirectional many-to-many is the single most sync-fragile
/// construct available under CloudKit — every relationship must be optional and
/// inverse maintenance across devices is where silent divergence starts. An
/// explicit edge also gives link semantics somewhere to live and makes
/// backlinks a plain query.
///
/// Bidirectionality is a read concern: query `fromId == x` for outbound and
/// `toId == x` for backlinks. Store each edge once.
@Model
final class SDConceptLink {
    var id: UUID = UUID()
    var fromId: UUID = UUID()
    var toId: UUID = UUID()
    var linkTypeRaw: String = ConceptLinkType.relates.rawValue
    /// Why the link exists — the interesting part, usually.
    var note: String?
    var createdAt: Date = Date()

    var linkType: ConceptLinkType {
        get { ConceptLinkType(rawValue: linkTypeRaw) ?? .relates }
        set { linkTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        fromId: UUID,
        toId: UUID,
        linkType: ConceptLinkType = .relates,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.linkTypeRaw = linkType.rawValue
        self.note = note
        self.createdAt = createdAt
    }

    /// The other end, given one end. Nil if `nodeId` isn't on this edge.
    func otherEnd(from nodeId: UUID) -> UUID? {
        if nodeId == fromId { return toId }
        if nodeId == toId { return fromId }
        return nil
    }
}
