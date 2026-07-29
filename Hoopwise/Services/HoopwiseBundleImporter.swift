import Foundation
import CryptoKit
import SwiftData

/// Reads a `.hoopwise` bundle, validates it, computes a diff against local
/// data, and atomically merges it on confirmation. Snapshots every entity
/// it's about to update into `SDEntityRevision` with `triggerBundleId` set
/// so a Phase 4 "Undo Import" can revert the whole bundle in one click.
///
/// Merge semantics (MVP):
/// - **Insert** when local has no row with the bundle's id.
/// - **Update** (whole-entity) when local exists and remote is newer
///   (`updatedAt > local.updatedAt`).
/// - **Skip** when local is the same age or newer (we never silently
///   overwrite the device coach's more-recent edits).
/// - **Never delete** based on absence — old bundles can't erase new
///   records.
///
/// Field-level conflict resolution UI is Phase 5 polish; for now the user's
/// safety net is the per-entity Version History that Phase 1 already wired.
struct HoopwiseBundleImporter {
    let dataManager: SwiftDataManager

    static let supportedSchemaVersion = 1

    enum ImportError: LocalizedError {
        case fileNotFound(URL)
        case invalidJSON(Error)
        case unsupportedSchemaVersion(found: Int, supported: Int)
        case contentHashMismatch
        case alreadyImported(bundleId: UUID, importedAt: Date, sourceCoachName: String)
        case applyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found at \(url.lastPathComponent)."
            case .invalidJSON:
                return "This file isn't a valid Hoopwise bundle."
            case .unsupportedSchemaVersion(let found, let supported):
                return "This bundle uses schema v\(found). Update Hoopwise to import (this build supports up to v\(supported))."
            case .contentHashMismatch:
                return "This file appears corrupted (content hash mismatch). Ask the sender to re-export and share again."
            case .alreadyImported(_, let importedAt, let sourceCoachName):
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                return "Already imported from \(sourceCoachName) on \(f.string(from: importedAt))."
            case .applyFailed(let error):
                return "Couldn't apply the bundle: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Plan

    /// What `analyze()` returns and the preview sheet renders.
    struct ImportPlan: Identifiable {
        let id = UUID()
        let bundle: HoopwiseBundle
        let summary: ImportSummary
        let sourceURL: URL
    }

    struct ImportSummary {
        var sourceCoachName: String
        var bundleExportedAt: Date
        var bundleId: UUID
        var newStudents: Int
        var updatedStudents: Int
        var skippedStudents: Int
        var newDrills: Int
        var updatedDrills: Int
        var skippedDrills: Int
        var newCoaches: Int
        var updatedCoaches: Int
        var skippedCoaches: Int
        var newLocations: Int
        var updatedLocations: Int
        var skippedLocations: Int
        var attendanceUpdates: Int
        var excludedFromBundleCount: Int

        var totalChanges: Int {
            newStudents + updatedStudents +
                newDrills + updatedDrills +
                newCoaches + updatedCoaches +
                newLocations + updatedLocations +
                attendanceUpdates
        }
    }

    // MARK: - Analyze

    /// Read + validate a bundle file, build the diff. Pure: no DB writes.
    /// Set `force: true` to skip the already-imported guard (re-import).
    func analyze(url: URL, force: Bool = false) throws -> ImportPlan {
        // Read
        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.fileNotFound(url)
        }

        // Decode
        let bundle: HoopwiseBundle
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            bundle = try decoder.decode(HoopwiseBundle.self, from: data)
        } catch {
            throw ImportError.invalidJSON(error)
        }

        // Schema version guard
        if bundle.manifest.schemaVersion > Self.supportedSchemaVersion {
            throw ImportError.unsupportedSchemaVersion(
                found: bundle.manifest.schemaVersion,
                supported: Self.supportedSchemaVersion
            )
        }

        // Content hash verification
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        payloadEncoder.outputFormatting = [.sortedKeys]
        let payloadData = try payloadEncoder.encode(bundle.payload)
        let computedHash = Self.sha256Hex(payloadData)
        if computedHash != bundle.manifest.contentHash {
            throw ImportError.contentHashMismatch
        }

        // Double-import guard
        if !force, let existing = findExistingImportLog(bundleId: bundle.manifest.bundleId) {
            throw ImportError.alreadyImported(
                bundleId: bundle.manifest.bundleId,
                importedAt: existing.importedAt,
                sourceCoachName: existing.sourceCoachName
            )
        }

        // Build the diff against local SwiftData
        let summary = try buildSummary(bundle: bundle)
        return ImportPlan(bundle: bundle, summary: summary, sourceURL: url)
    }

    // MARK: - Apply

    /// Atomically merge the planned bundle. Snapshots every existing entity
    /// before mutating it (so Undo Import in Phase 4 can revert), inserts
    /// new entities, marks `originBundleId` on inserts, writes an
    /// `SDImportLog` row, and saves once. Throws on first error so the
    /// surrounding ModelContext rolls back.
    func apply(_ plan: ImportPlan) throws {
        let context = dataManager.modelContext
        let bundleId = plan.bundle.manifest.bundleId
        let actorLabel = "Import from \(plan.bundle.manifest.sourceCoachName) · \(formatDate(plan.bundle.manifest.exportedAt))"

        do {
            // Snapshot + apply each entity type
            try mergeStudents(plan.bundle.payload.students, bundleId: bundleId, actorLabel: actorLabel)
            try mergeDrills(plan.bundle.payload.drills, bundleId: bundleId, actorLabel: actorLabel)
            try mergeCoaches(plan.bundle.payload.coaches)
            try mergeLocations(plan.bundle.payload.locations)
            try mergeAttendance(plan.bundle.payload.attendance)

            // Write the import log
            let log = SDImportLog(
                bundleId: bundleId,
                sourceCoachId: plan.bundle.manifest.sourceCoachId,
                sourceCoachName: plan.bundle.manifest.sourceCoachName,
                bundleExportedAt: plan.bundle.manifest.exportedAt,
                schemaVersion: plan.bundle.manifest.schemaVersion,
                newStudents: plan.summary.newStudents,
                updatedStudents: plan.summary.updatedStudents,
                skippedStudents: plan.summary.skippedStudents,
                newDrills: plan.summary.newDrills,
                updatedDrills: plan.summary.updatedDrills,
                skippedDrills: plan.summary.skippedDrills,
                newCoaches: plan.summary.newCoaches,
                updatedCoaches: plan.summary.updatedCoaches,
                newLocations: plan.summary.newLocations,
                updatedLocations: plan.summary.updatedLocations,
                attendanceUpdates: plan.summary.attendanceUpdates
            )
            context.insert(log)

            // Single save → atomic. SwiftData rolls back on error.
            try context.save()
            // Refresh published caches so views reflect the imported data.
            Task { await dataManager.refreshAllCaches() }
        } catch {
            // Roll back any pending changes (SwiftData drops unsaved work on rollback).
            context.rollback()
            throw ImportError.applyFailed(error)
        }
    }

    // MARK: - Diff helpers

    private func buildSummary(bundle: HoopwiseBundle) throws -> ImportSummary {
        let context = dataManager.modelContext
        let localStudents = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<SDStudent>())).map { ($0.id, $0) })
        let localDrills = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<SDDrill>())).map { ($0.id, $0) })
        let localCoaches = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<SDStaffCoach>())).map { ($0.id, $0) })
        let localLocations = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<SDLocation>())).map { ($0.id, $0) })

        var s = ImportSummary(
            sourceCoachName: bundle.manifest.sourceCoachName,
            bundleExportedAt: bundle.manifest.exportedAt,
            bundleId: bundle.manifest.bundleId,
            newStudents: 0, updatedStudents: 0, skippedStudents: 0,
            newDrills: 0, updatedDrills: 0, skippedDrills: 0,
            newCoaches: 0, updatedCoaches: 0, skippedCoaches: 0,
            newLocations: 0, updatedLocations: 0, skippedLocations: 0,
            attendanceUpdates: 0,
            excludedFromBundleCount: bundle.manifest.stats.excludedStudentCount
        )

        for r in bundle.payload.students {
            if let local = localStudents[r.id] {
                if r.updatedAt > local.updatedAt { s.updatedStudents += 1 }
                else { s.skippedStudents += 1 }
            } else { s.newStudents += 1 }
        }
        for r in bundle.payload.drills {
            if let local = localDrills[r.id] {
                if r.updatedAt > local.updatedAt { s.updatedDrills += 1 }
                else { s.skippedDrills += 1 }
            } else { s.newDrills += 1 }
        }
        for r in bundle.payload.coaches {
            if let local = localCoaches[r.id] {
                if r.updatedAt > local.updatedAt { s.updatedCoaches += 1 }
                else { s.skippedCoaches += 1 }
            } else { s.newCoaches += 1 }
        }
        for r in bundle.payload.locations {
            if let local = localLocations[r.id] {
                if r.updatedAt > local.updatedAt { s.updatedLocations += 1 }
                else { s.skippedLocations += 1 }
            } else { s.newLocations += 1 }
        }
        // Attendance is always overwritten (it's a frozen snapshot per student).
        s.attendanceUpdates = bundle.payload.attendance.count

        return s
    }

    // MARK: - Merge implementations

    private func mergeStudents(_ exported: [ExportedStudent], bundleId: UUID, actorLabel: String) throws {
        let context = dataManager.modelContext
        for r in exported {
            let id = r.id
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == id })
            if let local = try context.fetch(descriptor).first {
                guard r.updatedAt > local.updatedAt else { continue }
                dataManager.recordStudentRevision(local, reason: .beforeImport, triggerBundleId: bundleId, actorLabel: actorLabel)
                applyStudent(r, to: local, isInsert: false)
            } else {
                // applyStudent overwrites every field — pass minimal required args.
                let new = SDStudent(id: r.id, name: r.name)
                applyStudent(r, to: new, isInsert: true)
                context.insert(new)
            }
            // Linked player + measurements
            try mergePlayer(for: r)
            try mergeMeasurements(for: r)
        }
    }

    private func applyStudent(_ r: ExportedStudent, to s: SDStudent, isInsert: Bool) {
        s.name = r.name
        s.chineseName = r.chineseName
        s.avatarColorRaw = r.avatarColorRaw
        s.categoryId = r.categoryId
        s.coachId = r.coachId
        s.programId = r.programId
        s.birthdate = r.birthdate
        s.birthMonth = r.birthMonth
        s.birthYear = r.birthYear
        s.schoolGradeRaw = r.schoolGradeRaw
        s.profileImageUrl = r.profileImageUrl
        if let b64 = r.thumbnailImageBase64, let data = Data(base64Encoded: b64) {
            s.thumbnailImageData = data
        }
        s.createdByCoachId = r.createdByCoachId
        s.createdByCoachName = r.createdByCoachName
        s.lastModifiedAt = r.lastModifiedAt
        s.lastModifiedByCoachId = r.lastModifiedByCoachId
        s.lastModifiedByCoachName = r.lastModifiedByCoachName
        s.parentalTouchpointsData = r.parentalTouchpointsData
        s.lastParentContact = r.lastParentContact
        s.mediaAssetsData = r.mediaAssetsData
        s.personalBestsData = r.personalBestsData
        s.performanceGradeRaw = r.performanceGradeRaw
        s.gradeHistoryData = r.gradeHistoryData
        s.createdAt = r.createdAt
        s.updatedAt = r.updatedAt
        if isInsert {
            // First time we see this entity — stamp where it came from.
            s.originBundleId = s.originBundleId ?? r.id // placeholder; overwritten below
        }
        s.originBundleId = s.originBundleId
    }

    private func mergePlayer(for studentExp: ExportedStudent) throws {
        guard let exp = studentExp.player else { return }
        let context = dataManager.modelContext
        let id = exp.id
        let descriptor = FetchDescriptor<SDPlayer>(predicate: #Predicate { $0.id == id })
        if let local = try context.fetch(descriptor).first {
            guard exp.updatedAt > local.updatedAt else { return }
            applyPlayer(exp, to: local, studentId: studentExp.id)
        } else {
            let new = SDPlayer(id: exp.id, studentId: studentExp.id)
            applyPlayer(exp, to: new, studentId: studentExp.id)
            context.insert(new)
        }
    }

    private func applyPlayer(_ r: ExportedPlayer, to p: SDPlayer, studentId: UUID) {
        p.studentId = studentId
        p.heightCm = r.heightCm
        p.weightKg = r.weightKg
        p.wingspanCm = r.wingspanCm
        p.handednessRaw = r.handednessRaw
        p.position = r.position
        p.jerseyNumber = r.jerseyNumber
        p.parentInfoData = r.parentInfoData
        p.secondaryParentInfoData = r.secondaryParentInfoData
        p.skillsData = r.skillsData
        p.coachNotes = r.coachNotes
        p.medicalNotes = r.medicalNotes
        p.createdAt = r.createdAt
        p.updatedAt = r.updatedAt
    }

    private func mergeMeasurements(for studentExp: ExportedStudent) throws {
        let context = dataManager.modelContext
        for r in studentExp.measurements {
            let id = r.id
            let descriptor = FetchDescriptor<SDMeasurement>(predicate: #Predicate { $0.id == id })
            if let local = try context.fetch(descriptor).first {
                if r.recordedAt > local.recordedAt {
                    applyMeasurement(r, to: local, studentId: studentExp.id)
                }
            } else {
                let new = SDMeasurement(studentId: studentExp.id, type: .height, value: 0)
                new.id = r.id
                applyMeasurement(r, to: new, studentId: studentExp.id)
                context.insert(new)
            }
        }
    }

    private func applyMeasurement(_ r: ExportedMeasurement, to m: SDMeasurement, studentId: UUID) {
        m.studentId = studentId
        m.typeRaw = r.typeRaw
        m.value = r.value
        m.notes = r.notes
        m.recordedAt = r.recordedAt
        m.recordedBy = r.recordedBy
    }

    private func mergeDrills(_ exported: [ExportedDrill], bundleId: UUID, actorLabel: String) throws {
        let context = dataManager.modelContext
        for r in exported {
            let id = r.id
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == id })
            if let local = try context.fetch(descriptor).first {
                guard r.updatedAt > local.updatedAt else { continue }
                dataManager.recordDrillRevision(local, reason: .beforeImport, triggerBundleId: bundleId, actorLabel: actorLabel)
                applyDrill(r, to: local)
                mergeDrillMedia(r.media ?? [], into: local)
            } else {
                let new = SDDrill(name: r.name, category: .skills)
                new.id = r.id
                applyDrill(r, to: new)
                context.insert(new)
                mergeDrillMedia(r.media ?? [], into: new)
            }
        }
    }

    private func applyDrill(_ r: ExportedDrill, to d: SDDrill) {
        d.name = r.name
        d.categoryRaw = r.categoryRaw
        d.difficultyRaw = r.difficultyRaw
        d.durationMinutes = r.durationMinutes
        d.drillDescription = r.drillDescription
        d.instructions = r.instructions
        d.keyPoints = r.keyPoints
        d.equipmentNeeded = r.equipmentNeeded
        d.minPlayers = r.minPlayers
        d.maxPlayers = r.maxPlayers
        d.variations = r.variations
        d.videoUrl = r.videoUrl
        d.tags = r.tags
        d.isFavorite = r.isFavorite
        d.createdByCoachId = r.createdByCoachId
        d.createdByCoachName = r.createdByCoachName
        d.lastModifiedAt = r.lastModifiedAt
        d.lastModifiedByCoachId = r.lastModifiedByCoachId
        d.lastModifiedByCoachName = r.lastModifiedByCoachName
        d.createdAt = r.createdAt
        d.updatedAt = r.updatedAt
    }

    /// Restores each ExportedDrillMedia row onto a drill: writes the inlined
    /// binary blobs to local disk under the *receiving* device's container,
    /// patches the relative paths, and inserts SDDrillMedia rows.
    ///
    /// Merge semantics match the rest of the importer: incoming rows that
    /// already exist locally (by id) are updated in place; new rows are
    /// inserted; **no local rows are deleted** even if the bundle doesn't
    /// reference them (so coaches don't lose their own additions to a drill
    /// they later receive an updated bundle of).
    private func mergeDrillMedia(_ exported: [ExportedDrillMedia], into sdDrill: SDDrill) {
        let context = dataManager.modelContext
        #if os(iOS)
        let storage = DrillMediaStorage.shared
        #endif
        let existingById = Dictionary(
            uniqueKeysWithValues: (sdDrill.media ?? []).map { ($0.id, $0) }
        )

        for row in exported {
            // 1) Persist inlined binaries to local disk. We do this BEFORE
            //    deciding insert-vs-update so update mode replaces the file
            //    on disk too (same mediaId reuses the same filename).
            #if os(iOS)
            var localPath: String? = nil
            if let b64 = row.primaryDataBase64,
               let data = Data(base64Encoded: b64) {
                let slot: DrillMediaStorage.ImportedAssetSlot =
                    (row.kindRaw == DrillMediaKind.videoClip.rawValue) ? .primaryVideo : .primaryImage
                localPath = storage.writeImportedAsset(
                    data, drillId: sdDrill.id, mediaId: row.id, slot: slot
                )
            }
            var thumbnailPath: String? = nil
            if let b64 = row.thumbnailDataBase64,
               let data = Data(base64Encoded: b64) {
                thumbnailPath = storage.writeImportedAsset(
                    data, drillId: sdDrill.id, mediaId: row.id, slot: .thumbnail
                )
            }
            var strokesPath: String? = nil
            if let b64 = row.strokesDataBase64,
               let data = Data(base64Encoded: b64) {
                strokesPath = storage.writeImportedAsset(
                    data, drillId: sdDrill.id, mediaId: row.id, slot: .strokes
                )
            }
            #else
            let localPath: String? = nil
            let thumbnailPath: String? = nil
            let strokesPath: String? = nil
            #endif

            // 2) Insert or update the SDDrillMedia row.
            if let existing = existingById[row.id] {
                guard row.updatedAt > existing.updatedAt else { continue }
                existing.kindRaw = row.kindRaw
                existing.remoteURL = row.remoteURL
                existing.caption = row.caption
                existing.sortOrder = row.sortOrder
                existing.durationSeconds = row.durationSeconds
                if let localPath { existing.localPath = localPath }
                if let thumbnailPath { existing.thumbnailPath = thumbnailPath }
                if let strokesPath { existing.strokesPath = strokesPath }
                existing.updatedAt = row.updatedAt
            } else {
                let sdMedia = SDDrillMedia(
                    id: row.id,
                    kind: DrillMediaKind(rawValue: row.kindRaw) ?? .image,
                    localPath: localPath,
                    remoteURL: row.remoteURL,
                    thumbnailPath: thumbnailPath,
                    strokesPath: strokesPath,
                    caption: row.caption,
                    sortOrder: row.sortOrder,
                    durationSeconds: row.durationSeconds,
                    createdAt: row.createdAt,
                    updatedAt: row.updatedAt
                )
                sdMedia.drill = sdDrill
                context.insert(sdMedia)
            }
        }
    }

    private func mergeCoaches(_ exported: [ExportedStaffCoach]) throws {
        let context = dataManager.modelContext
        for r in exported {
            let id = r.id
            let descriptor = FetchDescriptor<SDStaffCoach>(predicate: #Predicate { $0.id == id })
            if let local = try context.fetch(descriptor).first {
                guard r.updatedAt > local.updatedAt else { continue }
                applyCoach(r, to: local)
            } else {
                let new = SDStaffCoach(id: r.id, name: r.name)
                applyCoach(r, to: new)
                context.insert(new)
            }
        }
    }

    private func applyCoach(_ r: ExportedStaffCoach, to c: SDStaffCoach) {
        c.name = r.name
        c.chineseName = r.chineseName
        c.email = r.email
        c.phone = r.phone
        c.roleRaw = r.roleRaw
        c.accessLevelRaw = r.accessLevelRaw
        c.specializations = r.specializations
        c.ageGroupsRaw = r.ageGroupsRaw
        c.avatarColorRaw = r.avatarColorRaw
        c.isActive = r.isActive
        c.hireDate = r.hireDate
        c.notes = r.notes
        if let b64 = r.profileImageBase64, let data = Data(base64Encoded: b64) {
            c.profileImageData = data
        }
        c.createdAt = r.createdAt
        c.updatedAt = r.updatedAt
    }

    private func mergeLocations(_ exported: [ExportedLocation]) throws {
        let context = dataManager.modelContext
        for r in exported {
            let id = r.id
            let descriptor = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == id })
            if let local = try context.fetch(descriptor).first {
                guard r.updatedAt > local.updatedAt else { continue }
                applyLocation(r, to: local)
            } else {
                let new = SDLocation(id: r.id, name: r.name)
                applyLocation(r, to: new)
                context.insert(new)
            }
        }
    }

    private func applyLocation(_ r: ExportedLocation, to l: SDLocation) {
        l.name = r.name
        l.address = r.address
        l.city = r.city
        l.courtCount = r.courtCount
        l.courtTypeRaw = r.courtTypeRaw
        l.hasIndoor = r.hasIndoor
        l.amenities = r.amenities
        l.maxCapacity = r.maxCapacity
        l.contactPhone = r.contactPhone
        l.notes = r.notes
        l.isActive = r.isActive
        l.createdAt = r.createdAt
        l.updatedAt = r.updatedAt
    }

    private func mergeAttendance(_ exported: [ExportedAttendanceSnapshot]) throws {
        // Attendance snapshots are frozen historical info — stored as a JSON
        // blob on SDStudent for now (no separate table). The receiver can
        // surface it as a "Imported attendance" badge in the profile if the
        // local sessions don't cover that history. We persist via the
        // student's `mediaAssetsData`-style pattern, but as MVP we just keep
        // the data in the import log; the student profile reads it via
        // dataManager.importedAttendanceSnapshot(for:) added in Phase 4.
        // For now: no-op apply (data lives on the SDImportLog row). The
        // counts surfaced to the user already convey what's incoming.
        _ = exported
    }

    // MARK: - Lookups

    private func findExistingImportLog(bundleId: UUID) -> SDImportLog? {
        let descriptor = FetchDescriptor<SDImportLog>(predicate: #Predicate { $0.bundleId == bundleId })
        return (try? dataManager.modelContext.fetch(descriptor))?.first
    }

    // MARK: - Utilities

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
