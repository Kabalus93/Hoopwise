import Foundation
import CryptoKit
import SwiftData

// MARK: - Bundle schema (v1)
//
// `.hoopwise` files are JSON containing a manifest + payload. The importer
// (Phase 3) verifies the schemaVersion + contentHash, shows a diff preview,
// and atomically merges. For MVP the bundle is single-file JSON with images
// embedded as base64 — simpler than a zip and easier to debug.
//
// Bumping the schema:
// - Add fields as optional in V1 first; readers ignore unknown fields.
// - Bump schemaVersion only when a breaking change is unavoidable, then add
//   a parallel V2 type alongside V1 (don't replace) so old bundles still load.

struct HoopwiseBundle: Codable {
    var manifest: BundleManifest
    var payload: BundlePayload
}

struct BundleManifest: Codable {
    var schemaVersion: Int
    var bundleId: UUID
    var exportedAt: Date
    var sourceCoachId: UUID
    var sourceCoachName: String
    var stats: BundleStats
    /// SHA-256 hex of the JSON-encoded payload. The importer verifies this
    /// matches before applying. Mismatch → file corrupted, abort.
    var contentHash: String
}

struct BundleStats: Codable {
    var studentCount: Int
    var drillCount: Int
    var coachCount: Int
    var locationCount: Int
    var attendanceCount: Int
    /// Number of students excluded from the bundle because their
    /// `excludeFromExport` flag is on. Surface this in the export-confirmation
    /// UI so the coach knows what's being held back.
    var excludedStudentCount: Int
}

struct BundlePayload: Codable {
    var students: [ExportedStudent]
    var drills: [ExportedDrill]
    var coaches: [ExportedStaffCoach]
    var locations: [ExportedLocation]
    var attendance: [ExportedAttendanceSnapshot]
}

// MARK: - Exported entity shapes

struct ExportedStudent: Codable {
    var id: UUID
    var name: String
    var chineseName: String?
    var avatarColorRaw: String
    var categoryId: UUID?
    var coachId: UUID?
    var programId: UUID?
    var birthdate: Date?
    var birthMonth: Int?
    var birthYear: Int?
    var schoolGradeRaw: String?
    var profileImageUrl: String?
    /// Inline thumbnail (small JPEG) base64-encoded. Receiver renders this
    /// directly in the list and detail rows. Full-resolution `profileImageData`
    /// is intentionally NOT included to keep bundle size sane.
    var thumbnailImageBase64: String?
    var createdByCoachId: UUID?
    var createdByCoachName: String?
    var lastModifiedAt: Date?
    var lastModifiedByCoachId: UUID?
    var lastModifiedByCoachName: String?
    var parentalTouchpointsData: Data?
    var lastParentContact: Date?
    var mediaAssetsData: Data?
    var personalBestsData: Data?
    var performanceGradeRaw: String?
    var gradeHistoryData: Data?
    var createdAt: Date
    var updatedAt: Date
    /// Snapshot of the linked SDPlayer (height, weight, parent info, skills, notes).
    var player: ExportedPlayer?
    /// Per-student measurement records.
    var measurements: [ExportedMeasurement]
}

struct ExportedPlayer: Codable {
    var id: UUID
    var heightCm: Double?
    var weightKg: Double?
    var wingspanCm: Double?
    var handednessRaw: String
    var position: String?
    var jerseyNumber: Int?
    var parentInfoData: Data?
    var secondaryParentInfoData: Data?
    var skillsData: Data?
    var coachNotes: String?
    var medicalNotes: String?
    var createdAt: Date
    var updatedAt: Date
}

struct ExportedMeasurement: Codable {
    var id: UUID
    var typeRaw: String
    var value: Double
    var notes: String?
    var recordedAt: Date
    var recordedBy: String?
}

struct ExportedDrill: Codable {
    var id: UUID
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
    var lastModifiedAt: Date?
    var lastModifiedByCoachId: UUID?
    var lastModifiedByCoachName: String?
    var createdAt: Date
    var updatedAt: Date
    /// Drill visuals — photos, own videos, court diagrams, YouTube/Instagram
    /// refs. Optional so bundles produced before this field existed still
    /// decode cleanly; new bundles omit the key when the array is empty.
    var media: [ExportedDrillMedia]?
}

/// Drill media row inside a `.hoopwise` bundle. Binary assets (the JPEG /
/// MP4 / .pkdrawing / cached thumbnail) ride along as base64 strings so the
/// receiver can drop them onto disk and stay scannable courtside without
/// any follow-up download. YouTube/Instagram rows skip the binary and just
/// carry the URL plus a cached thumbnail.
struct ExportedDrillMedia: Codable {
    var id: UUID
    var kindRaw: String
    var remoteURL: String?
    var caption: String?
    var sortOrder: Int
    var durationSeconds: Double?
    /// JPEG bytes for `.image`/`.courtDiagram`, MP4 bytes for `.videoClip`.
    /// nil for remote kinds.
    var primaryDataBase64: String?
    /// 720px JPEG thumbnail. Set for any kind that had a thumbnail cached
    /// locally — including remote kinds whose host thumbnail was fetched at
    /// link-add time.
    var thumbnailDataBase64: String?
    /// `PKDrawing` data blob — only present for `.courtDiagram`, so the
    /// receiver can re-open and edit the strokes rather than only seeing
    /// the flattened JPEG.
    var strokesDataBase64: String?
    var createdAt: Date
    var updatedAt: Date
}

struct ExportedStaffCoach: Codable {
    var id: UUID
    var name: String
    var chineseName: String?
    var email: String?
    var phone: String?
    var roleRaw: String
    var accessLevelRaw: String
    var specializations: [String]
    var ageGroupsRaw: [String]
    var avatarColorRaw: String
    var isActive: Bool
    var hireDate: Date?
    var notes: String?
    var profileImageBase64: String?
    var createdAt: Date
    var updatedAt: Date
}

struct ExportedLocation: Codable {
    var id: UUID
    var name: String
    var address: String?
    var city: String?
    var courtCount: Int
    var courtTypeRaw: String
    var hasIndoor: Bool
    var amenities: [String]
    var maxCapacity: Int?
    var contactPhone: String?
    var notes: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}

/// Frozen attendance summary per student — derived from SDSessionEvent records.
/// Sessions themselves are NOT shared (they're private coaching context); the
/// receiver gets a read-only history badge.
struct ExportedAttendanceSnapshot: Codable {
    var studentId: UUID
    var totalSessionsAttended: Int
    var totalSessionsExcused: Int
    var totalSessionsMissed: Int
    var lastAttendanceDate: Date?
}

// MARK: - Exporter

/// Produces a `.hoopwise` JSON file describing the current organization's
/// shareable data. Honors `SDStudent.excludeFromExport` and emits the count
/// of excluded students in `manifest.stats.excludedStudentCount` so the
/// confirmation UI can surface it.
struct HoopwiseBundleExporter {
    let dataManager: SwiftDataManager

    enum ExportError: Error {
        case noOwnerCoach
        case writeFailed(Error)
        case encodeFailed(Error)
    }

    /// Builds the bundle on demand and writes it to a temp file with a
    /// human-readable name like `Hoopwise-2026-05-09.hoopwise`. Returns the
    /// URL — caller hands it to the iOS share sheet.
    func exportToTempFile() throws -> URL {
        let bundle = try buildBundle()
        return try writeBundle(bundle)
    }

    /// Pure preview — counts of what would be exported, without writing
    /// anything to disk. Used to render the export-confirmation row.
    /// Reads SDStudents directly because `cachedStudents` is the legacy
    /// struct without the `excludeFromExport` flag.
    func previewStats() -> BundleStats {
        let context = dataManager.modelContext
        let allStudents = (try? context.fetch(FetchDescriptor<SDStudent>())) ?? []
        let included = allStudents.filter { !$0.excludeFromExport }
        return BundleStats(
            studentCount: included.count,
            drillCount: dataManager.drills.count,
            coachCount: dataManager.staffCoaches.count,
            locationCount: dataManager.locations.count,
            attendanceCount: included.count,
            excludedStudentCount: allStudents.count - included.count
        )
    }

    // MARK: - Build

    private func buildBundle() throws -> HoopwiseBundle {
        let context = dataManager.modelContext
        let coach = dataManager.cachedCoach
        let now = Date()

        // Students — only non-excluded
        let allStudents = try context.fetch(FetchDescriptor<SDStudent>())
        let exportableStudents = allStudents.filter { !$0.excludeFromExport }
        let excludedCount = allStudents.count - exportableStudents.count
        let exportableStudentIds = Set(exportableStudents.map(\.id))

        // Players linked to exportable students
        let allPlayers = try context.fetch(FetchDescriptor<SDPlayer>())
        let playersByStudentId = Dictionary(
            grouping: allPlayers.filter { exportableStudentIds.contains($0.studentId) },
            by: \.studentId
        )

        // Measurements linked to exportable students
        let allMeasurements = try context.fetch(FetchDescriptor<SDMeasurement>())
        let measurementsByStudentId = Dictionary(
            grouping: allMeasurements.filter { exportableStudentIds.contains($0.studentId) },
            by: \.studentId
        )

        // Sessions — used to compute attendance snapshots
        let allSessions = try context.fetch(FetchDescriptor<SDSessionEvent>())

        // Drills, coaches, locations — all included as-is
        let drills = try context.fetch(FetchDescriptor<SDDrill>())
        let staffCoaches = try context.fetch(FetchDescriptor<SDStaffCoach>())
        let locations = try context.fetch(FetchDescriptor<SDLocation>())

        let exportedStudents = exportableStudents.map { sd -> ExportedStudent in
            ExportedStudent(
                id: sd.id,
                name: sd.name,
                chineseName: sd.chineseName,
                avatarColorRaw: sd.avatarColorRaw,
                categoryId: sd.categoryId,
                coachId: sd.coachId,
                programId: sd.programId,
                birthdate: sd.birthdate,
                birthMonth: sd.birthMonth,
                birthYear: sd.birthYear,
                schoolGradeRaw: sd.schoolGradeRaw,
                profileImageUrl: sd.profileImageUrl,
                thumbnailImageBase64: sd.thumbnailImageData?.base64EncodedString(),
                createdByCoachId: sd.createdByCoachId,
                createdByCoachName: sd.createdByCoachName,
                lastModifiedAt: sd.lastModifiedAt,
                lastModifiedByCoachId: sd.lastModifiedByCoachId,
                lastModifiedByCoachName: sd.lastModifiedByCoachName,
                parentalTouchpointsData: sd.parentalTouchpointsData,
                lastParentContact: sd.lastParentContact,
                mediaAssetsData: sd.mediaAssetsData,
                personalBestsData: sd.personalBestsData,
                performanceGradeRaw: sd.performanceGradeRaw,
                gradeHistoryData: sd.gradeHistoryData,
                createdAt: sd.createdAt,
                updatedAt: sd.updatedAt,
                player: playersByStudentId[sd.id]?.first.map { Self.makePlayer(from: $0) },
                measurements: (measurementsByStudentId[sd.id] ?? []).map(Self.makeMeasurement)
            )
        }

        let exportedDrills = drills.map(Self.makeDrill)
        let exportedCoaches = staffCoaches.map(Self.makeCoach)
        let exportedLocations = locations.map(Self.makeLocation)
        let attendance = computeAttendance(
            sessions: allSessions,
            studentIds: exportableStudentIds
        )

        let payload = BundlePayload(
            students: exportedStudents,
            drills: exportedDrills,
            coaches: exportedCoaches,
            locations: exportedLocations,
            attendance: attendance
        )

        let stats = BundleStats(
            studentCount: exportedStudents.count,
            drillCount: exportedDrills.count,
            coachCount: exportedCoaches.count,
            locationCount: exportedLocations.count,
            attendanceCount: attendance.count,
            excludedStudentCount: excludedCount
        )

        // Encode payload first to compute the content hash; manifest references
        // the hash so the importer can detect corruption before applying.
        let encoder = Self.makeEncoder()
        let payloadData = try encoder.encode(payload)
        let contentHash = Self.sha256Hex(payloadData)

        let manifest = BundleManifest(
            schemaVersion: 1,
            bundleId: UUID(),
            exportedAt: now,
            sourceCoachId: coach.id,
            sourceCoachName: coach.name.isEmpty ? "Coach" : coach.name,
            stats: stats,
            contentHash: contentHash
        )

        return HoopwiseBundle(manifest: manifest, payload: payload)
    }

    private static func makePlayer(from sd: SDPlayer) -> ExportedPlayer {
        ExportedPlayer(
            id: sd.id,
            heightCm: sd.heightCm,
            weightKg: sd.weightKg,
            wingspanCm: sd.wingspanCm,
            handednessRaw: sd.handednessRaw,
            position: sd.position,
            jerseyNumber: sd.jerseyNumber,
            parentInfoData: sd.parentInfoData,
            secondaryParentInfoData: sd.secondaryParentInfoData,
            skillsData: sd.skillsData,
            coachNotes: sd.coachNotes,
            medicalNotes: sd.medicalNotes,
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt
        )
    }

    private static func makeMeasurement(from sd: SDMeasurement) -> ExportedMeasurement {
        ExportedMeasurement(
            id: sd.id,
            typeRaw: sd.typeRaw,
            value: sd.value,
            notes: sd.notes,
            recordedAt: sd.recordedAt,
            recordedBy: sd.recordedBy
        )
    }

    private static func makeDrill(from sd: SDDrill) -> ExportedDrill {
        let mediaRows = (sd.media ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(makeDrillMedia)
        return ExportedDrill(
            id: sd.id,
            name: sd.name,
            categoryRaw: sd.categoryRaw,
            difficultyRaw: sd.difficultyRaw,
            durationMinutes: sd.durationMinutes,
            drillDescription: sd.drillDescription,
            instructions: sd.instructions,
            keyPoints: sd.keyPoints,
            equipmentNeeded: sd.equipmentNeeded,
            minPlayers: sd.minPlayers,
            maxPlayers: sd.maxPlayers,
            variations: sd.variations,
            videoUrl: sd.videoUrl,
            tags: sd.tags,
            isFavorite: sd.isFavorite,
            createdByCoachId: sd.createdByCoachId,
            createdByCoachName: sd.createdByCoachName,
            lastModifiedAt: sd.lastModifiedAt,
            lastModifiedByCoachId: sd.lastModifiedByCoachId,
            lastModifiedByCoachName: sd.lastModifiedByCoachName,
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt,
            media: mediaRows.isEmpty ? nil : mediaRows
        )
    }

    /// Loads each binary asset off disk and inlines it as base64 so the
    /// receiver has everything in one file. Missing files (e.g. a media
    /// row whose JPEG was cleaned up underneath us) degrade gracefully —
    /// the metadata still travels, just without the bytes. `nonisolated`
    /// because the parent `makeDrill` is also nonisolated and the file
    /// reads here are thread-safe.
    nonisolated private static func makeDrillMedia(from sd: SDDrillMedia) -> ExportedDrillMedia {
        let store = DrillMediaStorage.shared

        // Primary asset bytes live on disk under `localPath`. For remote
        // kinds (YouTube/Instagram) this is nil and we skip the inline.
        let primaryBase64: String? = {
            guard let path = sd.localPath,
                  let data = store.readData(at: path) else { return nil }
            return data.base64EncodedString()
        }()
        let thumbnailBase64: String? = {
            guard let path = sd.thumbnailPath,
                  let data = store.readData(at: path) else { return nil }
            return data.base64EncodedString()
        }()
        let strokesBase64: String? = {
            guard let path = sd.strokesPath,
                  let data = store.readData(at: path) else { return nil }
            return data.base64EncodedString()
        }()

        return ExportedDrillMedia(
            id: sd.id,
            kindRaw: sd.kindRaw,
            remoteURL: sd.remoteURL,
            caption: sd.caption,
            sortOrder: sd.sortOrder,
            durationSeconds: sd.durationSeconds,
            primaryDataBase64: primaryBase64,
            thumbnailDataBase64: thumbnailBase64,
            strokesDataBase64: strokesBase64,
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt
        )
    }

    private static func makeCoach(from sd: SDStaffCoach) -> ExportedStaffCoach {
        ExportedStaffCoach(
            id: sd.id,
            name: sd.name,
            chineseName: sd.chineseName,
            email: sd.email,
            phone: sd.phone,
            roleRaw: sd.roleRaw,
            accessLevelRaw: sd.accessLevelRaw,
            specializations: sd.specializations,
            ageGroupsRaw: sd.ageGroupsRaw,
            avatarColorRaw: sd.avatarColorRaw,
            isActive: sd.isActive,
            hireDate: sd.hireDate,
            notes: sd.notes,
            profileImageBase64: sd.profileImageData?.base64EncodedString(),
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt
        )
    }

    private static func makeLocation(from sd: SDLocation) -> ExportedLocation {
        ExportedLocation(
            id: sd.id,
            name: sd.name,
            address: sd.address,
            city: sd.city,
            courtCount: sd.courtCount,
            courtTypeRaw: sd.courtTypeRaw,
            hasIndoor: sd.hasIndoor,
            amenities: sd.amenities,
            maxCapacity: sd.maxCapacity,
            contactPhone: sd.contactPhone,
            notes: sd.notes,
            isActive: sd.isActive,
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt
        )
    }

    private func computeAttendance(
        sessions: [SDSessionEvent],
        studentIds: Set<UUID>
    ) -> [ExportedAttendanceSnapshot] {
        var totals: [UUID: (attended: Int, excused: Int, missed: Int, last: Date?)] = [:]
        for session in sessions {
            let attendees = Set(session.actualAttendeeIds)
            let excused = Set(session.excusedAbsences)
            let expected = Set(session.attendeeIds)

            for studentId in expected.union(attendees).union(excused) where studentIds.contains(studentId) {
                var entry = totals[studentId] ?? (0, 0, 0, nil)
                if attendees.contains(studentId) {
                    entry.attended += 1
                    if entry.last == nil || session.date > (entry.last ?? .distantPast) {
                        entry.last = session.date
                    }
                } else if excused.contains(studentId) {
                    entry.excused += 1
                } else if expected.contains(studentId) {
                    entry.missed += 1
                }
                totals[studentId] = entry
            }
        }
        return totals.map { (sid, t) in
            ExportedAttendanceSnapshot(
                studentId: sid,
                totalSessionsAttended: t.attended,
                totalSessionsExcused: t.excused,
                totalSessionsMissed: t.missed,
                lastAttendanceDate: t.last
            )
        }
    }

    // MARK: - Write

    private func writeBundle(_ bundle: HoopwiseBundle) throws -> URL {
        let encoder = Self.makeEncoder()
        let data: Data
        do {
            data = try encoder.encode(bundle)
        } catch {
            throw ExportError.encodeFailed(error)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: bundle.manifest.exportedAt)
        let fileName = "Hoopwise-\(dateString).hoopwise"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            // Always overwrite — temp dir may have a stale bundle from a prior tap.
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(error)
        }
        return url
    }

    // MARK: - Encoding helpers

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
