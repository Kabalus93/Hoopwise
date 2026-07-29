import Foundation
import SwiftData

/// One row per `.hoopwise` bundle imported. Two purposes:
/// 1. Double-import guard — if the user re-opens the same bundle file, we
///    detect by `bundleId` and warn before re-applying.
/// 2. Phase 4 "Undo Import" — every entity touched by this import has an
///    `SDEntityRevision` snapshot tagged with `triggerBundleId == bundleId`.
///    Undo restores all of them.
///
/// CloudKit-compatible: every property is optional or has a default value,
/// no `@Attribute(.unique)`. Uniqueness for `id` is enforced in code.
@Model
final class SDImportLog {
    var id: UUID = UUID()
    var bundleId: UUID = UUID()
    var sourceCoachId: UUID?
    var sourceCoachName: String = ""
    var importedAt: Date = Date()
    var bundleExportedAt: Date = Date()
    var schemaVersion: Int = 1
    /// Counts surfaced in the import history list (Phase 4 UI).
    var newStudents: Int = 0
    var updatedStudents: Int = 0
    var skippedStudents: Int = 0
    var newDrills: Int = 0
    var updatedDrills: Int = 0
    var skippedDrills: Int = 0
    var newCoaches: Int = 0
    var updatedCoaches: Int = 0
    var newLocations: Int = 0
    var updatedLocations: Int = 0
    var attendanceUpdates: Int = 0
    /// True if the user has invoked Undo Import on this row (Phase 4).
    /// Once true, the row stays for record but Undo Import is hidden.
    var undone: Bool = false

    init(
        id: UUID = UUID(),
        bundleId: UUID,
        sourceCoachId: UUID?,
        sourceCoachName: String,
        importedAt: Date = Date(),
        bundleExportedAt: Date,
        schemaVersion: Int = 1,
        newStudents: Int = 0,
        updatedStudents: Int = 0,
        skippedStudents: Int = 0,
        newDrills: Int = 0,
        updatedDrills: Int = 0,
        skippedDrills: Int = 0,
        newCoaches: Int = 0,
        updatedCoaches: Int = 0,
        newLocations: Int = 0,
        updatedLocations: Int = 0,
        attendanceUpdates: Int = 0,
        undone: Bool = false
    ) {
        self.id = id
        self.bundleId = bundleId
        self.sourceCoachId = sourceCoachId
        self.sourceCoachName = sourceCoachName
        self.importedAt = importedAt
        self.bundleExportedAt = bundleExportedAt
        self.schemaVersion = schemaVersion
        self.newStudents = newStudents
        self.updatedStudents = updatedStudents
        self.skippedStudents = skippedStudents
        self.newDrills = newDrills
        self.updatedDrills = updatedDrills
        self.skippedDrills = skippedDrills
        self.newCoaches = newCoaches
        self.updatedCoaches = updatedCoaches
        self.newLocations = newLocations
        self.updatedLocations = updatedLocations
        self.attendanceUpdates = attendanceUpdates
        self.undone = undone
    }
}
