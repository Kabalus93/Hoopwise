import CoreData
import Foundation
import OSLog
import SwiftData

// MOVING THE DATA TO PRODUCTION (15 November 2026, Luther: TestFlight on the
// iPad showed none of his data — it reads CloudKit PRODUCTION, while every
// debug build has written to DEVELOPMENT for months. Apple copies only the
// schema between the two, never records.)
//
// Each device keeps its synced copy of the cloud in a local store file. Debug
// and release builds share the App Group folder, so:
//
// · RELEASE BUILDS NOW USE THEIR OWN FILE, `production.store`. A TestFlight
//   build installed over a debug build used to open the Development copy with
//   the Production database — iCloud's reaction to that is not defined.
// · A release build can BRING OVER the Development copy already on the device
//   (`default.store`, marked by any debug build that ran here). It is copied
//   at the Core Data level — every attribute and relationship of every entity,
//   so no hand-written field list can drop anything — into the production
//   store BEFORE SwiftData opens it, with persistent history on, so iCloud's
//   mirroring uploads it to Production as it does every local change.
//   Rows with the same `id` replace what the release build seeded first
//   (library drills, the default coach and settings); the singletons are
//   replaced outright. The source is read from a temporary COPY and never
//   changed. Afterwards every row is compared attribute by attribute.
// · DEBUG: HOOPWISE_MOVE_REHEARSAL=demo|real copies the demo store or the
//   real Development copy into a temporary store, checks it, logs the report
//   (hoopwise.mac / move) and writes it to the App Group Library/Caches/
//   move-report.txt, then QUITS before any store is opened.

enum ProductionMove {

    // MARK: Files

    /// SwiftData's default store location (the App Group's Application
    /// Support when the app has an App Group).
    static var developmentStoreURL: URL {
        ModelConfiguration(schema: SwiftDataManager.schema, cloudKitDatabase: .none).url
    }

    static var productionStoreURL: URL {
        developmentStoreURL.deletingLastPathComponent().appendingPathComponent("production.store")
    }

    /// The file this build keeps its live, mirrored store in.
    static var liveStoreURL: URL {
        #if DEBUG
        return developmentStoreURL
        #else
        return productionStoreURL
        #endif
    }

    /// Written next to the store by every debug build, so a release build
    /// knows the `default.store` here is a DEVELOPMENT copy (an older
    /// TestFlight build kept Production data in that same file).
    static var developmentMarkerURL: URL {
        developmentStoreURL.deletingLastPathComponent().appendingPathComponent("default.store.development")
    }

    static func markDevelopmentStore() {
        let url = developmentMarkerURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? Data("Development copy, written by a debug build.".utf8).write(to: url)
    }

    // MARK: State

    static let pendingKey = "productionMove.pending"
    static let reportKey = "productionMove.report"

    /// The request and the report are FILES beside the store (15 Nov 2026):
    /// the first version kept the request in UserDefaults and quit at once,
    /// and on the coach's iPhone the write never reached disk — the next
    /// launch found nothing to do. A file written atomically is on disk
    /// before the app closes.
    static var pendingFileURL: URL {
        developmentStoreURL.deletingLastPathComponent().appendingPathComponent("production-move.pending")
    }
    static var reportFileURL: URL {
        developmentStoreURL.deletingLastPathComponent().appendingPathComponent("production-move.report.json")
    }

    /// Asked for from Profile: written to disk now; the move runs at the next
    /// launch, before the store opens.
    static func requestMove() {
        try? Data("pending".utf8).write(to: pendingFileURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    /// A release build offers the move when a Development copy is here and
    /// it has not been brought over yet.
    static var isOffered: Bool {
        #if DEBUG
        return false
        #else
        return FileManager.default.fileExists(atPath: developmentMarkerURL.path)
            && FileManager.default.fileExists(atPath: developmentStoreURL.path)
            && lastReport == nil
        #endif
    }

    static var lastReport: Report? {
        let data = (try? Data(contentsOf: reportFileURL)) ?? UserDefaults.standard.data(forKey: reportKey)
        guard let data else { return nil }
        return try? JSONDecoder().decode(Report.self, from: data)
    }

    // MARK: Report

    struct Report: Codable, Equatable {
        struct Line: Codable, Equatable {
            var entity: String
            var source: Int
            var copied: Int
        }
        var lines: [Line]
        /// Rows whose attributes differ after the copy.
        var mismatches: Int
        var mismatchSamples: [String]
        var replacedSeeded: Int
        /// Photos and other large values kept beside the store (external
        /// storage): how many came across, and their size.
        var blobs: Int = 0
        var blobBytes: Int = 0
        var error: String?
        var date: Date

        /// The destination may hold more than the source (rows the release
        /// build seeded with no twin, like starter plays — deduplicated later),
        /// never fewer.
        var ok: Bool { error == nil && mismatches == 0 && lines.allSatisfy { $0.copied >= $0.source } }

        var text: String {
            var out = ["Move \(ok ? "OK" : "PROBLEM") · \(date.formatted())"]
            if let error { out.append("error: \(error)") }
            for line in lines where line.source > 0 || line.copied > 0 {
                out.append("\(line.entity): \(line.copied)/\(line.source)")
            }
            out.append("mismatched rows: \(mismatches)")
            out.append(contentsOf: mismatchSamples)
            out.append("seeded rows replaced: \(replacedSeeded)")
            out.append("photos and other stored files: \(blobs) (\(blobBytes / 1_000_000) MB)")
            return out.joined(separator: "\n")
        }
    }

    // MARK: Launch hooks (called by SwiftDataManager before the container opens)

    /// Release builds: run a move the coach asked for at the last launch.
    static func runPendingIfNeeded() {
        let fileAsked = FileManager.default.fileExists(atPath: pendingFileURL.path)
        guard fileAsked || UserDefaults.standard.bool(forKey: pendingKey) else { return }
        try? FileManager.default.removeItem(at: pendingFileURL)
        UserDefaults.standard.set(false, forKey: pendingKey)
        let report = move(from: developmentStoreURL, to: productionStoreURL)
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: reportFileURL, options: .atomic)
            UserDefaults.standard.set(data, forKey: reportKey)
        }
        Logger(subsystem: "hoopwise.mac", category: "move").log("\(report.text, privacy: .public)")
    }

    #if DEBUG
    /// HOOPWISE_INIT_CLOUDKIT_SCHEMA=1 (debug, so CloudKit DEVELOPMENT):
    /// Core Data's initializeCloudKitSchema over the full model — every record
    /// type with EVERY field, uploaded as samples and deleted again. CloudKit
    /// adds a field only when a record carrying it is uploaded, so a field
    /// that was always empty may be missing from Development and therefore
    /// from the Production deploy. Run once before deploying. Quits after.
    static func initializeCloudKitSchemaIfAsked() {
        guard ProcessInfo.processInfo.environment["HOOPWISE_INIT_CLOUDKIT_SCHEMA"] == "1" else { return }
        let log = Logger(subsystem: "hoopwise.mac", category: "move")
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SwiftDataManager.modelTypes) else {
            log.log("schema: no model"); exit(1)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-init-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.hoopwise.Hoopwise")
        let container = NSPersistentCloudKitContainer(name: "SchemaInit", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            log.log("schema: store failed \(String(describing: loadError), privacy: .public)"); exit(1)
        }
        do {
            try container.initializeCloudKitSchema(options: [])
            log.log("schema: initialized in Development — \(model.entities.count, privacy: .public) record types")
        } catch {
            log.log("schema: FAILED \(String(describing: error), privacy: .public)")
        }
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        exit(0)
    }

    /// HOOPWISE_MOVE_REHEARSAL=demo|real: copy into a temporary store, check,
    /// report, quit.
    static func rehearseIfAsked() {
        guard let mode = ProcessInfo.processInfo.environment["HOOPWISE_MOVE_REHEARSAL"] else { return }
        if mode == "paths" {
            let text = "live \(liveStoreURL.path)\ndevelopment \(developmentStoreURL.path)\nproduction \(productionStoreURL.path)"
            Logger(subsystem: "hoopwise.mac", category: "move").log("\(text, privacy: .public)")
            if let caches = WidgetShared.containerURL?.appendingPathComponent("Library/Caches", isDirectory: true) {
                try? text.write(to: caches.appendingPathComponent("move-report.txt"), atomically: true, encoding: .utf8)
            }
            exit(0)
        }
        let source = mode == "real"
            ? developmentStoreURL
            : developmentStoreURL.deletingLastPathComponent().appendingPathComponent("screenshots.store")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("rehearsal-\(UUID().uuidString).store")
        let started = Date()
        let report = move(from: source, to: target)
        var text = "Rehearsal (\(mode)) from \(source.lastPathComponent) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n" + report.text
        // The copy must open as the app opens it, links intact.
        do {
            let container = try ModelContainer(for: SwiftDataManager.schema,
                                               configurations: [ModelConfiguration(schema: SwiftDataManager.schema, url: target,
                                                                                   allowsSave: false, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let plays = try context.fetch(FetchDescriptor<JournalPlay>())
            let parts = plays.reduce(0) { $0 + ($1.parts?.count ?? 0) }
            let steps = plays.reduce(0) { total, play in total + (play.parts ?? []).reduce(0) { $0 + ($1.steps?.count ?? 0) } }
            let students = try context.fetchCount(FetchDescriptor<SDStudent>())
            let contracts = try context.fetch(FetchDescriptor<SDContract>())
            let charges = contracts.reduce(0) { $0 + $1.toStruct().bundleSessionIds.count }
            let paid = contracts.reduce(0.0) { $0 + $1.toStruct().amountPaid }
            text += "\nSwiftData opens it: \(students) athletes · \(plays.count) plays with \(parts) parts and \(steps) steps attached · \(contracts.count) contracts, \(charges) sessions charged, \(Int(paid)) paid"
        } catch {
            text += "\nSwiftData could NOT open the copy: \(error)"
        }
        Logger(subsystem: "hoopwise.mac", category: "move").log("\(text, privacy: .public)")
        if let caches = WidgetShared.containerURL?.appendingPathComponent("Library/Caches", isDirectory: true) {
            try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            try? text.write(to: caches.appendingPathComponent("move-report.txt"), atomically: true, encoding: .utf8)
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: target.path + suffix)
        }
        exit(0)
    }
    #endif

    // MARK: The copy

    /// Entities that hold one record per coach: the destination's own (seeded
    /// at first launch) is replaced, not kept beside the source's.
    static let singletonEntities: Set<String> = ["SDCoach", "SDAppSettings"]

    static func move(from source: URL, to destination: URL) -> Report {
        do {
            return try copy(from: source, to: destination)
        } catch {
            return Report(lines: [], mismatches: 0, mismatchSamples: [], replacedSeeded: 0,
                          error: String(describing: error), date: Date())
        }
    }

    enum MoveError: Error, CustomStringConvertible {
        case noModel, noSource(String)
        var description: String {
            switch self {
            case .noModel: return "The data model could not be built."
            case .noSource(let path): return "No development copy at \(path)."
            }
        }
    }

    private static func loadStore(at url: URL, model: NSManagedObjectModel, name: String) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: name, managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        // Persistent history ON: the mirrored store expects it, and it is what
        // makes iCloud see the copied rows as changes to upload.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    static func copy(from source: URL, to destination: URL) throws -> Report {
        guard FileManager.default.fileExists(atPath: source.path) else { throw MoveError.noSource(source.path) }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SwiftDataManager.modelTypes) else {
            throw MoveError.noModel
        }

        // Read from a temporary copy: the original is never opened for writing.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sourceCopy = temp.appendingPathComponent("source.store")
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: source.path + suffix) {
            try FileManager.default.copyItem(atPath: source.path + suffix, toPath: sourceCopy.path + suffix)
        }
        // Photos (and every revision snapshot) are EXTERNAL storage: files in
        // the hidden ".<store>_SUPPORT" folder beside the store. Without them
        // the copy reads those values as empty — the first version did.
        let supportName = ".\(source.deletingPathExtension().lastPathComponent)_SUPPORT"
        let support = source.deletingLastPathComponent().appendingPathComponent(supportName, isDirectory: true)
        if FileManager.default.fileExists(atPath: support.path) {
            try FileManager.default.copyItem(at: support, to: temp.appendingPathComponent(".source_SUPPORT", isDirectory: true))
        }

        let from = try loadStore(at: sourceCopy, model: model, name: "MoveSource")
        let to = try loadStore(at: destination, model: model, name: "MoveDestination")
        let src = from.newBackgroundContext()
        let dst = to.newBackgroundContext()
        dst.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let entities = model.entities.filter { !$0.isAbstract && $0.name != nil }
        var lines: [Report.Line] = []
        var mismatches = 0
        var samples: [String] = []
        var replaced = 0
        var blobs = 0
        var blobBytes = 0

        try dst.performAndWait {
            try src.performAndWait {
                var map: [NSManagedObjectID: NSManagedObject] = [:]
                var pairs: [(NSManagedObject, NSManagedObject)] = []

                // 1. Rows: replace seeded twins, then insert copies.
                for entity in entities {
                    let name = entity.name!
                    let request = NSFetchRequest<NSManagedObject>(entityName: name)
                    request.includesSubentities = false
                    let rows = try src.fetch(request)

                    let existingRequest = NSFetchRequest<NSManagedObject>(entityName: name)
                    existingRequest.includesSubentities = false
                    let existing = try dst.fetch(existingRequest)
                    if singletonEntities.contains(name), !rows.isEmpty {
                        existing.forEach { dst.delete($0) }
                        replaced += existing.count
                    } else if entity.attributesByName["id"] != nil {
                        let incoming = Set(rows.compactMap { $0.value(forKey: "id") as? NSObject })
                        for row in existing {
                            if let id = row.value(forKey: "id") as? NSObject, incoming.contains(id) {
                                dst.delete(row)
                                replaced += 1
                            }
                        }
                    }

                    for row in rows {
                        let copy = NSManagedObject(entity: entity, insertInto: dst)
                        for attribute in entity.attributesByName.keys {
                            copy.setValue(row.value(forKey: attribute), forKey: attribute)
                        }
                        map[row.objectID] = copy
                        pairs.append((row, copy))
                    }
                    lines.append(.init(entity: name, source: rows.count, copied: 0))
                }

                // 2. Relationships, through the map.
                for (row, copy) in pairs {
                    for (name, relationship) in row.entity.relationshipsByName {
                        guard let value = row.value(forKey: name) else { continue }
                        if relationship.isToMany {
                            let members: [NSManagedObject]
                            if let ordered = value as? NSOrderedSet {
                                members = ordered.array.compactMap { ($0 as? NSManagedObject).flatMap { map[$0.objectID] } }
                                copy.setValue(NSOrderedSet(array: members), forKey: name)
                            } else if let set = value as? Set<NSManagedObject> {
                                members = set.compactMap { map[$0.objectID] }
                                copy.setValue(Set(members), forKey: name)
                            }
                        } else if let target = value as? NSManagedObject, let mapped = map[target.objectID] {
                            copy.setValue(mapped, forKey: name)
                        }
                    }
                }

                // Save in one transaction.
                try dst.save()

                // 3. Check: counts, and every attribute of every row.
                for index in lines.indices {
                    let request = NSFetchRequest<NSManagedObject>(entityName: lines[index].entity)
                    request.includesSubentities = false
                    lines[index].copied = try dst.count(for: request)
                }
                for (row, copy) in pairs {
                    for (name, description) in row.entity.attributesByName where description.allowsExternalBinaryDataStorage {
                        if let data = copy.value(forKey: name) as? Data, !data.isEmpty {
                            blobs += 1
                            blobBytes += data.count
                        }
                    }
                    for attribute in row.entity.attributesByName.keys {
                        let a = row.value(forKey: attribute) as? NSObject
                        let b = copy.value(forKey: attribute) as? NSObject
                        if a != b {
                            mismatches += 1
                            if samples.count < 5 { samples.append("\(row.entity.name ?? "?").\(attribute)") }
                            break
                        }
                    }
                }
            }
        }

        // Counts compare the destination with the source; a destination that
        // kept rows of its own (seeded with no twin) shows more than the source.
        return Report(lines: lines, mismatches: mismatches, mismatchSamples: samples,
                      replacedSeeded: replaced, blobs: blobs, blobBytes: blobBytes, error: nil, date: Date())
    }
}
