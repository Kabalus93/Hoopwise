import Foundation
import SwiftData

/// Type of entity that a revision snapshot belongs to.
/// Stored as a raw string so the schema is forward-compatible if more entity
/// types become revisable later (organization, location, etc.).
enum RevisionEntityType: String, Codable, CaseIterable {
    case student
    case drill
    /// Snapshot of an entire `SDSessionEvent` before a mutation. Added after
    /// a data-loss incident where a stale `@State` snapshot in
    /// `FlightySessionPageView` overwrote concurrently-added games and an
    /// attendance photo — with revisions in place that situation is at
    /// least recoverable from the version history.
    case session
}

/// Reason a revision was created. Used to render the version-history list.
/// `manualEdit` is the default for in-app edits; `beforeImport` is set by
/// the importer (Phase 3) before applying a bundle.
enum RevisionReason: String, Codable {
    case manualEdit
    case beforeImport
    case beforeRestore  // Snapshot taken right before the user restores an older revision
}

/// Immutable point-in-time snapshot of an entity's serialized state.
///
/// One row per (entity, save). Pruning is enforced by `SwiftDataManager`
/// after every insert: keep the last 10 per entity, plus revisions tagged
/// with a `triggerBundleId` for at least 30 days so an import remains
/// undoable for that window.
@Model
final class SDEntityRevision {
    // CloudKit-compatible: every property is optional or has a default value, and
    // no `@Attribute(.unique)` constraints. Uniqueness for `id` is upheld in code
    // (always initialized to `UUID()` at insertion).
    var id: UUID = UUID()
    var entityId: UUID = UUID()
    var entityTypeRaw: String = ""
    var reasonRaw: String = ""
    var createdAt: Date = Date()
    var triggerBundleId: UUID?  // Set when the revision was created as part of an import; used by Undo Import (Phase 4)
    /// Snapshot of the prior state, encoded by an entity-specific Codable struct
    /// owned by the manager (see `SwiftDataManager.snapshotStudent` / `restoreStudent`).
    /// We don't decode this here; the manager owns the schema.
    @Attribute(.externalStorage) var snapshotData: Data = Data()
    /// Best-effort label for who/what triggered this snapshot (e.g. coach name,
    /// or "Import from Coach Lee · May 8, 2026"). Shown in the version-history list.
    var actorLabel: String?

    init(
        id: UUID = UUID(),
        entityId: UUID,
        entityType: RevisionEntityType,
        reason: RevisionReason,
        createdAt: Date = Date(),
        triggerBundleId: UUID? = nil,
        snapshotData: Data,
        actorLabel: String? = nil
    ) {
        self.id = id
        self.entityId = entityId
        self.entityTypeRaw = entityType.rawValue
        self.reasonRaw = reason.rawValue
        self.createdAt = createdAt
        self.triggerBundleId = triggerBundleId
        self.snapshotData = snapshotData
        self.actorLabel = actorLabel
    }

    var entityType: RevisionEntityType {
        RevisionEntityType(rawValue: entityTypeRaw) ?? .student
    }

    var reason: RevisionReason {
        RevisionReason(rawValue: reasonRaw) ?? .manualEdit
    }
}

// MARK: - Snapshot encodings
//
// `SDEntityRevision.snapshotData` is opaque to the model; the manager owns
// the schema. We version each schema with a `_v` suffix so a future field
// addition can introduce `StudentSnapshotV2` without breaking decoders for
// already-stored V1 rows.

struct StudentSnapshotV1: Codable {
    var version: Int  // == 1
    var name: String
    var chineseName: String?
    var avatarColorRaw: String
    var attendanceStatusRaw: String
    var categoryId: UUID?
    var coachId: UUID?
    var programId: UUID?
    var birthdate: Date?
    var birthMonth: Int?
    var birthYear: Int?
    var schoolGradeRaw: String?
    var profileImageUrl: String?
    var createdByCoachId: UUID?
    var createdByCoachName: String?
    var lastModifiedByCoachId: UUID?
    var lastModifiedByCoachName: String?
    var lastModifiedAt: Date?
    var originBundleId: UUID?
    var parentalTouchpointsData: Data?
    var lastParentContact: Date?
    var mediaAssetsData: Data?
    var personalBestsData: Data?
    var performanceGradeRaw: String?
    var gradeHistoryData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(_ s: SDStudent) {
        self.version = 1
        self.name = s.name
        self.chineseName = s.chineseName
        self.avatarColorRaw = s.avatarColorRaw
        self.attendanceStatusRaw = s.attendanceStatusRaw
        self.categoryId = s.categoryId
        self.coachId = s.coachId
        self.programId = s.programId
        self.birthdate = s.birthdate
        self.birthMonth = s.birthMonth
        self.birthYear = s.birthYear
        self.schoolGradeRaw = s.schoolGradeRaw
        self.profileImageUrl = s.profileImageUrl
        self.createdByCoachId = s.createdByCoachId
        self.createdByCoachName = s.createdByCoachName
        self.lastModifiedByCoachId = s.lastModifiedByCoachId
        self.lastModifiedByCoachName = s.lastModifiedByCoachName
        self.lastModifiedAt = s.lastModifiedAt
        self.originBundleId = s.originBundleId
        self.parentalTouchpointsData = s.parentalTouchpointsData
        self.lastParentContact = s.lastParentContact
        self.mediaAssetsData = s.mediaAssetsData
        self.personalBestsData = s.personalBestsData
        self.performanceGradeRaw = s.performanceGradeRaw
        self.gradeHistoryData = s.gradeHistoryData
        self.createdAt = s.createdAt
        self.updatedAt = s.updatedAt
    }

    /// Apply this snapshot back onto an SDStudent in place (restore).
    func apply(to s: SDStudent) {
        s.name = name
        s.chineseName = chineseName
        s.avatarColorRaw = avatarColorRaw
        s.attendanceStatusRaw = attendanceStatusRaw
        s.categoryId = categoryId
        s.coachId = coachId
        s.programId = programId
        s.birthdate = birthdate
        s.birthMonth = birthMonth
        s.birthYear = birthYear
        s.schoolGradeRaw = schoolGradeRaw
        s.profileImageUrl = profileImageUrl
        s.createdByCoachId = createdByCoachId
        s.createdByCoachName = createdByCoachName
        s.lastModifiedByCoachId = lastModifiedByCoachId
        s.lastModifiedByCoachName = lastModifiedByCoachName
        s.lastModifiedAt = lastModifiedAt
        s.originBundleId = originBundleId
        s.parentalTouchpointsData = parentalTouchpointsData
        s.lastParentContact = lastParentContact
        s.mediaAssetsData = mediaAssetsData
        s.personalBestsData = personalBestsData
        s.performanceGradeRaw = performanceGradeRaw
        s.gradeHistoryData = gradeHistoryData
        s.createdAt = createdAt
        s.updatedAt = updatedAt
    }
}

struct DrillSnapshotV1: Codable {
    var version: Int  // == 1
    var name: String
    var categoryRaw: String
    var difficultyRaw: String
    var durationMinutes: Int
    var drillDescription: String
    var instructions: [String]
    var keyPoints: [String]
    var equipmentNeeded: [String]
    var minPlayers: Int
    var maxPlayers: Int?
    var variations: [String]
    var videoUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdByCoachId: UUID?
    var createdByCoachName: String?
    var lastModifiedByCoachId: UUID?
    var lastModifiedByCoachName: String?
    var lastModifiedAt: Date?
    var originBundleId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ d: SDDrill) {
        self.version = 1
        self.name = d.name
        self.categoryRaw = d.categoryRaw
        self.difficultyRaw = d.difficultyRaw
        self.durationMinutes = d.durationMinutes
        self.drillDescription = d.drillDescription
        self.instructions = d.instructions
        self.keyPoints = d.keyPoints
        self.equipmentNeeded = d.equipmentNeeded
        self.minPlayers = d.minPlayers
        self.maxPlayers = d.maxPlayers
        self.variations = d.variations
        self.videoUrl = d.videoUrl
        self.tags = d.tags
        self.isFavorite = d.isFavorite
        self.createdByCoachId = d.createdByCoachId
        self.createdByCoachName = d.createdByCoachName
        self.lastModifiedByCoachId = d.lastModifiedByCoachId
        self.lastModifiedByCoachName = d.lastModifiedByCoachName
        self.lastModifiedAt = d.lastModifiedAt
        self.originBundleId = d.originBundleId
        self.createdAt = d.createdAt
        self.updatedAt = d.updatedAt
    }

    func apply(to d: SDDrill) {
        d.name = name
        d.categoryRaw = categoryRaw
        d.difficultyRaw = difficultyRaw
        d.durationMinutes = durationMinutes
        d.drillDescription = drillDescription
        d.instructions = instructions
        d.keyPoints = keyPoints
        d.equipmentNeeded = equipmentNeeded
        d.minPlayers = minPlayers
        d.maxPlayers = maxPlayers
        d.variations = variations
        d.videoUrl = videoUrl
        d.tags = tags
        d.isFavorite = isFavorite
        d.createdByCoachId = createdByCoachId
        d.createdByCoachName = createdByCoachName
        d.lastModifiedByCoachId = lastModifiedByCoachId
        d.lastModifiedByCoachName = lastModifiedByCoachName
        d.lastModifiedAt = lastModifiedAt
        d.originBundleId = originBundleId
        d.createdAt = createdAt
        d.updatedAt = updatedAt
    }
}

/// Snapshot of an `SDSessionEvent`'s full state. Easier than enumerating
/// every field — we just encode the value-type `SessionEvent` produced by
/// `toStruct()`. That struct is `Codable` already; if its schema changes in
/// a non-additive way, bump this to `SessionSnapshotV2`.
struct SessionSnapshotV1: Codable {
    var version: Int  // == 1
    var event: SessionEvent

    init(_ sd: SDSessionEvent) {
        self.version = 1
        self.event = sd.toStruct()
    }

    func apply(to sd: SDSessionEvent) {
        sd.microCycleId = event.microCycleId
        sd.programId = event.programId
        sd.sessionType = event.sessionType
        sd.title = event.title
        sd.date = event.date
        sd.startTime = event.startTime
        sd.endTime = event.endTime
        sd.location = event.location
        sd.status = event.status
        sd.curriculum = event.curriculum
        sd.attendeeIds = event.attendeeIds
        sd.actualAttendeeIds = event.actualAttendeeIds
        sd.excusedAbsences = event.excusedAbsences
        sd.attendancePhotoPath = event.attendancePhotoPath
        sd.notes = event.notes
        sd.coachNotes = event.coachNotes
        sd.manOfTheMatchId = event.manOfTheMatchId
        sd.drillsCompleted = event.drillsCompleted
        sd.rating = event.rating
        sd.games = event.games
        sd.updatedAt = event.updatedAt
    }
}

// MARK: - Provenance value types (read API for views)

struct StudentProvenance: Equatable {
    let createdByCoachId: UUID?
    let createdByCoachName: String?
    let createdAt: Date
    let lastModifiedByCoachId: UUID?
    let lastModifiedByCoachName: String?
    let lastModifiedAt: Date?
    let originBundleId: UUID?
}

struct DrillProvenance: Equatable {
    let createdByCoachId: UUID?
    let createdByCoachName: String?
    let createdAt: Date
    let lastModifiedByCoachId: UUID?
    let lastModifiedByCoachName: String?
    let lastModifiedAt: Date?
    let originBundleId: UUID?
}

/// View-friendly summary of a single revision row.
struct EntityRevisionSummary: Identifiable, Equatable {
    let id: UUID
    let entityId: UUID
    let entityType: RevisionEntityType
    let reason: RevisionReason
    let createdAt: Date
    let actorLabel: String?
    let triggerBundleId: UUID?
}
