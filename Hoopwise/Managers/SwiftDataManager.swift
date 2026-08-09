import Foundation
import SwiftData
import SwiftUI
import Combine

/// Type alias for backward compatibility - views using DataManager will now use SwiftDataManager
typealias DataManager = SwiftDataManager

/// SwiftData-based data manager that provides the same interface as the legacy DataManager
/// but uses SwiftData for persistence instead of UserDefaults
@MainActor
/// Three-way attendance state used by `SwiftDataManager.setStudentAttendanceState`.
/// Lives at file scope so it's accessible from views without leaking
/// view-private types into the manager API.
/// The four distinguishable attendance states.
///
/// `unmarked` is not the same as `absent`, and the difference is money: an
/// unexcused absence consumes a bundle session under agreement clause 4, while
/// a student whose attendance has not been taken yet must consume nothing.
/// Three stored arrays give four states — membership in one of them, or none.
enum AttendanceTriState {
    case unmarked, present, excused, absent
}

class SwiftDataManager: ObservableObject {
    static let shared = SwiftDataManager()

    /// Set when the container fell back at launch. Surfaced in the UI so a
    /// store failure is visible rather than silent — or, as it used to be,
    /// a crash.
    static private(set) var startupFailure: String?
    
    // MARK: - Model Container
    let modelContainer: ModelContainer
    var modelContext: ModelContext { modelContainer.mainContext }
    
    // MARK: - Published Properties (for compatibility with existing views)
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    
    // MARK: - Batch Operation Mode
    /// When true, saveAndRefresh won't trigger fullSync (for batch operations like AI generation)
    private var isBatchMode = false
    
    // MARK: - Batch Mode for AI Generation
    /// Begin batch mode to prevent fullSync on every save
    func beginBatchMode() {
        isBatchMode = true
        debugLog("📦 Batch mode started - fullSync disabled")
    }

    /// End batch mode (CloudKit handles sync automatically)
    func endBatchModeAndSync() {
        isBatchMode = false
        debugLog("📦 Batch mode ended")
    }
    
    // MARK: - Authentication State (single-coach mode — kept for source-compat)
    var isLoggedIn: Bool { true }
    var loggedInCoachId: UUID? { coach.id }
    var hasSkippedLogin: Bool { false }
    
    // MARK: - Cached Data (for computed properties and quick access)
    @Published private(set) var cachedStudents: [Student] = []
    @Published private(set) var cachedPlayers: [Player] = []
    @Published private(set) var cachedContracts: [Contract] = []
    @Published private(set) var cachedPrograms: [Program] = []
    @Published private(set) var cachedMicroCycles: [MicroCycle] = []
    @Published private(set) var cachedSessionEvents: [SessionEvent] = []
    @Published private(set) var cachedDrills: [DrillItem] = []
    @Published private(set) var cachedMeasurements: [PlayerMeasurement] = []
    @Published private(set) var cachedCoach: Coach = Coach.default
    @Published private(set) var cachedAppSettings: AppSettings = AppSettings.default
    
    // Legacy compatibility aliases
    var students: [Student] { cachedStudents }
    var players: [Player] { cachedPlayers }
    var contracts: [Contract] { cachedContracts }
    var programs: [Program] { cachedPrograms }
    var microCycles: [MicroCycle] { cachedMicroCycles }
    var sessionEvents: [SessionEvent] { cachedSessionEvents }
    var drills: [DrillItem] { cachedDrills }
    var measurements: [PlayerMeasurement] { cachedMeasurements }
    var coach: Coach { cachedCoach }
    var appSettings: AppSettings { cachedAppSettings }
    
    // MARK: - Performance: Cached Filtered Data
    // These reduce filter operations in views by pre-computing common queries
    
    /// Active programs only (cached for performance)
    var activePrograms: [Program] {
        cachedPrograms.filter { $0.status == .active }
    }
    
    /// All students (alias for consistency)
    var allStudents: [Student] {
        cachedStudents
    }
    
    /// Active staff coaches only
    var activeStaffCoaches: [StaffCoach] {
        staffCoaches.filter { $0.isActive }
    }
    
    /// Active locations only
    var activeLocations: [Location] {
        locations.filter { $0.isActive }
    }
    
    /// Today's sessions
    var todaySessions: [SessionEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return cachedSessionEvents.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }
    
    /// Upcoming games (next 7 days)
    var upcomingGames: [Game] {
        let now = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return games
            .filter { $0.date >= now && $0.date <= weekFromNow && $0.status == .scheduled }
            .sorted { $0.date < $1.date }
    }
    
    /// Low session contracts (3 or fewer remaining) - excludes pay-as-you-go contracts
    /// Uses event-based session consumption calculation
    var lowSessionContracts: [Contract] {
        cachedContracts.filter { contract in
            guard !contract.isPayAsYouGo else { return false }
            let remaining = sessionsRemaining(for: contract)
            return remaining <= 3 && remaining > 0
        }
    }
    
    // MARK: - Performance: Contract Lookup Cache
    /// Cached dictionary for O(1) contract lookups by student ID
    private var _contractsByStudentId: [UUID: Contract]?
    
    /// Get contracts indexed by student ID for fast lookups
    var contractsByStudentId: [UUID: Contract] {
        if let cached = _contractsByStudentId { return cached }
        let dict = Dictionary(cachedContracts.map { ($0.studentId, $0) }, uniquingKeysWith: { first, _ in first })
        _contractsByStudentId = dict
        return dict
    }
    
    /// Invalidate contract cache (call when contracts change)
    func invalidateContractCache() {
        _contractsByStudentId = nil
    }
    
    // MARK: - Performance: Active Contracts Count
    var activeContractsCount: Int {
        cachedContracts.filter { $0.status == .active }.count
    }
    
    // MARK: - Performance: Students Needing Attention
    var studentsNeedingAttentionCount: Int {
        cachedStudents.filter { student in
            let contract = contractsByStudentId[student.id]
            let remaining = contract.map { sessionsRemaining(for: $0) } ?? 0
            return remaining <= 3
        }.count
    }
    
    // MARK: - Performance: High Risk Students Count
    var highRiskStudentsCount: Int {
        // Simplified check - students with very low sessions or no recent contact
        cachedStudents.filter { student in
            let contract = contractsByStudentId[student.id]
            let remaining = contract.map { sessionsRemaining(for: $0) } ?? 0
            let noRecentContact = student.lastParentContact == nil ||
                Calendar.current.dateComponents([.day], from: student.lastParentContact!, to: Date()).day ?? 0 > 30
            return remaining <= 2 || (remaining <= 5 && noRecentContact)
        }.count
    }
    
    // Categories (static, not stored in SwiftData)
    var categories: [BasketballCategory] = BasketballCategory.samples
    /// Backed by SDPlay. Refreshed by `reloadPlays()`; published so the
    /// playbook views update when a play is saved.
    @Published var plays: [Play] = []
    var playbookCollections: [PlaybookCollection] = []
    var enrollments: [ProgramEnrollment] = []
    var phaseSessions: [PhaseSession] = []
    
    // League data (in-memory for now, can be migrated to SwiftData later)
    @Published var teams: [Team] = []
    @Published var games: [Game] = []
    @Published var teamStandings: [TeamStanding] = []
    @Published var seasonStats: [SeasonStats] = []
    
    // Organization data
    @Published var staffCoaches: [StaffCoach] = []
    @Published var locations: [Location] = []
    @Published var schools: [School] = []
    @Published var ageCategories: [CustomAgeCategory] = CustomAgeCategory.defaults
    
    // Court schemes for Basketball Lab
    @Published var courtSchemes: [CourtScheme] = []
    
    // Reminders (local storage with UserDefaults for now)
    @Published var reminders: [Reminder] = []


    /// Delete local database to force schema rebuild (use when schema changes)
    static func deleteLocalDatabase() {
        if let url = getLocalStorageURL() {
            let fileManager = FileManager.default
            // Delete main store file and related files
            let basePath = url.deletingPathExtension().path
            let extensions = ["", ".sqlite", ".sqlite-shm", ".sqlite-wal", "-shm", "-wal"]
            for ext in extensions {
                let path = basePath + ext
                if fileManager.fileExists(atPath: path) {
                    try? fileManager.removeItem(atPath: path)
                    debugLog("🗑️ Deleted: \(path)")
                }
            }
            // Also try the exact URL
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
                debugLog("🗑️ Deleted: \(url.path)")
            }
            debugLog("✅ Local database deleted - will rebuild on next launch")
        }
    }
    
    // Helper to get platform-specific local storage URL
    // Each platform (iOS/macOS) has its own local storage - CloudKit is the sync mechanism
    private static func getLocalStorageURL() -> URL? {
        let fileManager = FileManager.default
        
        #if os(macOS)
        // On macOS, use ~/Library/Application Support/SAM/
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let samFolder = appSupportURL.appendingPathComponent("SAM", isDirectory: true)
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: samFolder.path) {
                try? fileManager.createDirectory(at: samFolder, withIntermediateDirectories: true)
            }
            
            return samFolder.appendingPathComponent("SAMData.store")
        }
        #else
        // On iOS, use Documents directory
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let samFolder = documentsURL.appendingPathComponent("SAMData", isDirectory: true)
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: samFolder.path) {
                try? fileManager.createDirectory(at: samFolder, withIntermediateDirectories: true)
            }
            
            return samFolder.appendingPathComponent("SAMData.store")
        }
        #endif
        
        return nil
    }
    
    private init() {
        // Configure SwiftData schema
        let schema = Schema([
            SDStudent.self,
            SDPlayer.self,
            SDContract.self,
            SDProgram.self,
            SDMicroCycle.self,
            SDSessionEvent.self,
            SDDrill.self,
            SDDrillMedia.self,
            SDMeasurement.self,
            SDCoach.self,
            SDAppSettings.self,
            SDTeam.self,
            SDGame.self,
            SDStaffCoach.self,
            SDLocation.self,
            SDSchool.self,
            SDReminder.self,
            SDEntityRevision.self,
            SDImportLog.self,
            // Registered together so the CloudKit schema deploys once and a
            // single iOS build carries every new record type. SDConceptNode and
            // SDConceptLink have no UI yet — empty models cost nothing to
            // carry, and a second deploy would cost another iOS release.
            SDPlay.self,
            SDPlayDiagram.self,
            SDConceptNode.self,
            SDConceptLink.self,
            // Directory groups (Contacts-style custom groups on the Mac).
            // Same deploy-once rule as the play types above: registered now so
            // the next CloudKit schema deploy carries it.
            SDDirectoryGroup.self
        ])
        
        // Use platform-specific local storage
        // iOS and macOS each have their own local data store
        // CloudKit private DB syncs SwiftData across the user's devices automatically
        let modelConfiguration: ModelConfiguration
        
        // CloudKit-backed configuration. iCloud private database syncs across the
        // user's devices automatically. SwiftData manages the schema in CloudKit.
        let cloudKitContainerID = "iCloud.com.hoopwise.Hoopwise"
        debugLog("☁️ Using CloudKit private DB: \(cloudKitContainerID)")
        modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        
        // A store or CloudKit problem must not be a hard crash. fatalError here
        // turned every schema mismatch, migration failure or CloudKit
        // unavailability into a trap with no way to recover or even read the
        // error. Fall back to an in-memory store and surface the failure so the
        // app opens and can say what went wrong.
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            debugLog("✅ SwiftData ModelContainer initialized")
        } catch {
            debugLog("❌ CloudKit-backed ModelContainer failed: \(error)")
            let localOnly = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: false,
                                               allowsSave: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [localOnly]) {
                modelContainer = fallback
                Self.startupFailure = "iCloud sync is unavailable, so this session is local only. \(error.localizedDescription)"
                debugLog("⚠️ Fell back to a LOCAL-ONLY store; changes will not sync")
            } else if let memory = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]) {
                modelContainer = memory
                Self.startupFailure = "The local database could not be opened, so this session is in memory only and will not be saved. \(error.localizedDescription)"
                debugLog("⚠️ Fell back to an IN-MEMORY store; nothing will persist")
            } else {
                // Nothing left to try. Still no fatalError — an empty in-memory
                // container is better than a trap with no diagnostics.
                modelContainer = try! ModelContainer(
                    for: Schema([SDAppSettings.self]),
                    configurations: [ModelConfiguration(schema: Schema([SDAppSettings.self]),
                                                        isStoredInMemoryOnly: true)])
                Self.startupFailure = "The data store could not be opened at all. \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Load All Data
    private var hasInitialized = false
    private var backgroundSyncTask: Task<Void, Never>?
    
    func loadAllData() async {
        isLoading = true
        
        debugLog("🚀 Starting SwiftData loadAllData...")
        
        // Check if we need to migrate from UserDefaults (only once)
        if !hasInitialized {
            await migrateFromUserDefaultsIfNeeded()
            hasInitialized = true
        }
        
        // First load local data for immediate display (fast path)
        await refreshAllCaches()
        
        // Run one-time migrations
        migrateSessionDurationsTo30()
        migrateAttendancePhotoPaths()
        backfillStudentPhotosFromLocalCache()
        
        // Sync sample drills (adds any new drills from DrillItem.samples)
        syncSampleDrills()
        
        // Clean up any duplicate drills (one-time cleanup + prevention)
        deduplicateDrills()
        
        // Mark loading complete immediately after local data loads
        // This ensures UI is responsive right away
        isLoading = false

        debugLog("✅ Local data loaded: \(cachedStudents.count) students, \(cachedPrograms.count) programs")

        // Warm the avatar cache so rows render synchronously on first scroll.
        warmAvatarCache()

        // Migrate stale auto-PAYG contracts → group, then ensure every student
        // has at least one tracking contract (now defaulting to group).
        migrateLegacyAutoContractsToGroup()
        ensureDefaultContractsForAllStudents()
        
        // Sync all contracts with actual attendance records (one-time reconciliation)
        syncAllContractAttendance()
        
        // CloudKit handles sync automatically - no manual cloud pull needed
        lastSyncDate = Date()
        
        // Production mode: Don't load sample data - let user populate their own data
        if cachedStudents.isEmpty && cachedPrograms.isEmpty && cachedSessionEvents.isEmpty {
            debugLog("📦 No data found - ready for user to add their own data")
        }
        
        // PERFORMANCE: Preload visible student images in background (batched)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            await self.preloadStudentImages()
        }
    }
    
    /// Preload student images in batches to avoid memory spikes.
    ///
    /// Warms the cache from RECORD bytes only. The URL fetch path is gone:
    /// every stored profileImageUrl points at the dead Supabase host (or an
    /// iPhone-local file path), so it produced a wall of failed requests on
    /// every launch and could never load anything. The photo backfill moves
    /// cache-only images into the records; URLs are pure legacy pending
    /// roadmap step 10.
    private func preloadStudentImages() async {
        let students = await MainActor.run { self.cachedStudents }
        var warmed = 0
        for student in students {
            guard let data = student.thumbnailImageData ?? student.profileImageData,
                  !data.isEmpty else { continue }
            let cacheId = ImageCacheManager.studentImageId(student.id)
            if ImageCacheManager.shared.image(for: cacheId) == nil,
               let image = CacheImage(data: data) {
                ImageCacheManager.shared.cacheInMemory(image, for: cacheId)
                warmed += 1
            }
        }
        debugLog("🖼️ Warmed \(warmed) student images from record data")
    }
    
    /// Cancel any ongoing background sync
    func cancelBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        isSyncing = false
    }
    
    /// Force a manual refresh of caches (CloudKit handles cloud sync automatically)
    func forceCloudSync() async {
        await refreshAllCaches()
        lastSyncDate = Date()
    }
    
    // MARK: - Refresh Caches
    func refreshAllCaches() async {
        defer {
            WidgetSnapshotWriter.scheduleWrite(dataManager: self)
            AttentionEngine.scheduleAutomation(dataManager: self)
        }
        do {
            // Fetch all SwiftData models and convert to structs
            let sdStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            cachedStudents = sdStudents.map { $0.toStruct() }
            
            let sdPlayers = try modelContext.fetch(FetchDescriptor<SDPlayer>())
            cachedPlayers = sdPlayers.map { $0.toStruct() }
            
            let sdContracts = try modelContext.fetch(FetchDescriptor<SDContract>())
            cachedContracts = sdContracts.map { $0.toStruct() }

            let sdPlays = try modelContext.fetch(FetchDescriptor<SDPlay>())
            plays = sdPlays.map { $0.toStruct() }
            
            let sdPrograms = try modelContext.fetch(FetchDescriptor<SDProgram>())
            cachedPrograms = sdPrograms.map { $0.toStruct() }
            
            let sdMicroCycles = try modelContext.fetch(FetchDescriptor<SDMicroCycle>())
            cachedMicroCycles = sdMicroCycles.map { $0.toStruct() }
            
            let sdSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            cachedSessionEvents = sdSessions.map { $0.toStruct() }
            
            // Debug: Log sessions with games
            let sessionsWithGames = cachedSessionEvents.filter { !$0.games.isEmpty }
            if !sessionsWithGames.isEmpty {
                debugLog("🎮 [DEBUG] refreshAllCaches: Found \(sessionsWithGames.count) sessions with games")
                for session in sessionsWithGames {
                    debugLog("   - \(session.title): \(session.games.count) games")
                }
            }
            
            let sdDrills = try modelContext.fetch(FetchDescriptor<SDDrill>())
            // Promote any legacy single-URL `videoUrl` fields into proper
            // SDDrillMedia rows so they show up in the carousel. Idempotent:
            // migrated drills have their videoUrl cleared so the next pass
            // skips them. Thumbnail caching is fire-and-forget so refresh
            // isn't gated on network.
            migrateLegacyVideoUrls(in: sdDrills)
            cachedDrills = sdDrills.map { $0.toStruct() }

            let sdMeasurements = try modelContext.fetch(FetchDescriptor<SDMeasurement>())
            cachedMeasurements = sdMeasurements.map { $0.toStruct() }

            // Coach (singleton)
            let sdCoaches = try modelContext.fetch(FetchDescriptor<SDCoach>())
            if let sdCoach = sdCoaches.first {
                cachedCoach = sdCoach.toStruct()
            }
            
            // App Settings (singleton)
            let sdSettings = try modelContext.fetch(FetchDescriptor<SDAppSettings>())
            if let settings = sdSettings.first {
                cachedAppSettings = settings.toStruct()
            }
            
            // League data
            let sdTeams = try modelContext.fetch(FetchDescriptor<SDTeam>())
            teams = sdTeams.map { $0.toTeam() }
            
            let sdGames = try modelContext.fetch(FetchDescriptor<SDGame>())
            games = sdGames.map { $0.toGame() }
            
            // Organization data
            let sdStaffCoaches = try modelContext.fetch(FetchDescriptor<SDStaffCoach>())
            staffCoaches = sdStaffCoaches.map { $0.toStaffCoach() }
            
            let sdLocations = try modelContext.fetch(FetchDescriptor<SDLocation>())
            locations = sdLocations.map { $0.toLocation() }

            let sdSchools = try modelContext.fetch(FetchDescriptor<SDSchool>())
            schools = sdSchools.map { $0.toSchool() }

            // Load persisted season stats from UserDefaults
            loadLeagueData()

            debugLog("📊 Caches refreshed: \(cachedStudents.count) students, \(cachedPrograms.count) programs, \(teams.count) teams, \(staffCoaches.count) coaches, \(locations.count) locations, \(schools.count) schools")
        } catch {
            debugLog("❌ Failed to refresh caches: \(error)")
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
    
    // MARK: - League Data Persistence (UserDefaults for seasonStats, teamStandings)
    private let leagueDataKey = "league_season_stats_data"
    private let teamStandingsKey = "league_team_standings_data"
    private let ageCategoriesKey = "age_categories_data"
    
    /// Save league data that isn't in SwiftData (seasonStats, teamStandings)
    func saveLeagueData() {
        // Save seasonStats
        if let encoded = try? JSONEncoder().encode(seasonStats) {
            UserDefaults.standard.set(encoded, forKey: leagueDataKey)
        }
        
        // Save teamStandings
        if let encoded = try? JSONEncoder().encode(teamStandings) {
            UserDefaults.standard.set(encoded, forKey: teamStandingsKey)
        }
        
        debugLog("💾 League data saved: \(seasonStats.count) season stats, \(teamStandings.count) standings")
    }
    
    /// Load league data from UserDefaults
    private func loadLeagueData() {
        // Load seasonStats
        if let data = UserDefaults.standard.data(forKey: leagueDataKey),
           let decoded = try? JSONDecoder().decode([SeasonStats].self, from: data) {
            seasonStats = decoded
            debugLog("📊 Loaded \(seasonStats.count) season stats from persistence")
        }
        
        // Load teamStandings
        if let data = UserDefaults.standard.data(forKey: teamStandingsKey),
           let decoded = try? JSONDecoder().decode([TeamStanding].self, from: data) {
            teamStandings = decoded
            debugLog("📊 Loaded \(teamStandings.count) team standings from persistence")
        }
        
        // Load ageCategories
        if let data = UserDefaults.standard.data(forKey: ageCategoriesKey),
           let decoded = try? JSONDecoder().decode([CustomAgeCategory].self, from: data) {
            // Drop accumulated duplicates by shortName (case-insensitive). For each
            // shortName, keep the most recently updated row. Anything stored over
            // earlier app versions with repeated U6/U8 entries gets cleaned here.
            let deduped = Dictionary(grouping: decoded, by: { $0.shortName.uppercased() })
                .compactMap { _, group in group.max(by: { $0.updatedAt < $1.updatedAt }) }
                .sorted { $0.minAge < $1.minAge }
            ageCategories = deduped
            if deduped.count != decoded.count {
                debugLog("🧹 Deduplicated age categories: \(decoded.count) → \(deduped.count)")
                saveAgeCategories()
            }
            debugLog("📊 Loaded \(ageCategories.count) age categories from persistence")
        }
    }
    
    /// Save age categories to UserDefaults for local persistence
    func saveAgeCategories() {
        if let encoded = try? JSONEncoder().encode(ageCategories) {
            UserDefaults.standard.set(encoded, forKey: ageCategoriesKey)
            debugLog("💾 Age categories saved: \(ageCategories.count) categories")
        }
    }
    
    // MARK: - Migration from UserDefaults
    private func migrateFromUserDefaultsIfNeeded() async {
        let migrationKey = "swiftdata_migration_completed_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            debugLog("✅ Migration already completed")
            return
        }
        
        debugLog("🔄 Starting migration from UserDefaults to SwiftData...")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let defaults = UserDefaults.standard
        
        // Helper function to load from UserDefaults
        func load<T: Decodable>(key: String) -> T? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
        
        // Migrate Students
        if let oldStudents: [Student] = load(key: "sam_students") {
            for student in oldStudents {
                let sdStudent = SDStudent.from(student)
                modelContext.insert(sdStudent)
            }
            debugLog("  ✓ Migrated \(oldStudents.count) students")
        }
        
        // Migrate Players
        if let oldPlayers: [Player] = load(key: "sam_players") {
            for player in oldPlayers {
                let sdPlayer = SDPlayer.from(player)
                modelContext.insert(sdPlayer)
            }
            debugLog("  ✓ Migrated \(oldPlayers.count) players")
        }
        
        // Migrate Contracts
        if let oldContracts: [Contract] = load(key: "sam_contracts") {
            for contract in oldContracts {
                let sdContract = SDContract.from(contract)
                modelContext.insert(sdContract)
            }
            debugLog("  ✓ Migrated \(oldContracts.count) contracts")
        }
        
        // Migrate Programs
        if let oldPrograms: [Program] = load(key: "sam_programs") {
            for program in oldPrograms {
                let sdProgram = SDProgram.from(program)
                modelContext.insert(sdProgram)
            }
            debugLog("  ✓ Migrated \(oldPrograms.count) programs")
        }
        
        // Migrate MicroCycles
        if let oldCycles: [MicroCycle] = load(key: "sam_micro_cycles") {
            for cycle in oldCycles {
                let sdCycle = SDMicroCycle.from(cycle)
                modelContext.insert(sdCycle)
            }
            debugLog("  ✓ Migrated \(oldCycles.count) micro cycles")
        }
        
        // Migrate Session Events
        if let oldSessions: [SessionEvent] = load(key: "sam_session_events") {
            for session in oldSessions {
                let sdSession = SDSessionEvent.from(session)
                modelContext.insert(sdSession)
            }
            debugLog("  ✓ Migrated \(oldSessions.count) sessions")
        }
        
        // Migrate Drills
        if let oldDrills: [DrillItem] = load(key: "sam_drills") {
            for drill in oldDrills {
                let sdDrill = SDDrill.from(drill)
                modelContext.insert(sdDrill)
            }
            debugLog("  ✓ Migrated \(oldDrills.count) drills")
        }
        
        // Migrate Measurements
        if let oldMeasurements: [PlayerMeasurement] = load(key: "sam_measurements") {
            for measurement in oldMeasurements {
                let sdMeasurement = SDMeasurement.from(measurement)
                modelContext.insert(sdMeasurement)
            }
            debugLog("  ✓ Migrated \(oldMeasurements.count) measurements")
        }
        
        // Migrate Coach
        if let oldCoach: Coach = load(key: "sam_coach") {
            let sdCoach = SDCoach.from(oldCoach)
            modelContext.insert(sdCoach)
            debugLog("  ✓ Migrated coach profile")
        }
        
        // Migrate App Settings
        if let oldSettings: AppSettings = load(key: "sam_app_settings") {
            let sdSettings = SDAppSettings.from(oldSettings)
            modelContext.insert(sdSettings)
            debugLog("  ✓ Migrated app settings")
        }
        
        // Save all migrated data
        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            debugLog("✅ Migration completed successfully")
        } catch {
            debugLog("❌ Migration failed: \(error)")
        }
    }
    
    // MARK: - Pinyin Tone Migration
    /// Updates existing student names from plain pinyin to pinyin with tone marks.
    /// Only updates names where the current name matches the plain pinyin of the Chinese name.
    /// Manually-entered English names are NOT affected.
    /// - Returns: Number of students updated
    @discardableResult
    func migratePinyinToToneMarks() -> Int {
        var updatedCount = 0
        
        do {
            let descriptor = FetchDescriptor<SDStudent>()
            let allStudents = try modelContext.fetch(descriptor)
            
            for sdStudent in allStudents {
                if let tonedName = PinyinConverter.tonedPinyinIfNeeded(
                    name: sdStudent.name,
                    chineseName: sdStudent.chineseName
                ) {
                    debugLog("🔤 Updating pinyin: '\(sdStudent.name)' → '\(tonedName)' (Chinese: \(sdStudent.chineseName ?? "nil"))")
                    sdStudent.name = tonedName
                    sdStudent.updatedAt = Date()
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                try modelContext.save()
                Task { await refreshAllCaches() }
                debugLog("✅ Pinyin migration complete: \(updatedCount) students updated with tone marks")
            } else {
                debugLog("ℹ️ Pinyin migration: No students needed updating")
            }
        } catch {
            debugLog("❌ Pinyin migration failed: \(error)")
        }
        
        return updatedCount
    }
    
    // MARK: - Sample Data
    private func loadSampleData() async {
        // Students
        for student in Student.samples {
            let sdStudent = SDStudent.from(student)
            modelContext.insert(sdStudent)
        }
        
        // Programs
        for program in Program.samples {
            let sdProgram = SDProgram.from(program)
            modelContext.insert(sdProgram)
        }
        
        // Sessions
        for session in SessionEvent.samples {
            let sdSession = SDSessionEvent.from(session)
            modelContext.insert(sdSession)
        }
        
        // Drills
        for drill in DrillItem.samples {
            let sdDrill = SDDrill.from(drill)
            modelContext.insert(sdDrill)
        }
        
        // Default Coach
        let sdCoach = SDCoach.sample
        modelContext.insert(sdCoach)
        
        // Default Settings
        let sdSettings = SDAppSettings.defaultSettings
        modelContext.insert(sdSettings)
        
        // Create players and contracts for students
        for student in Student.samples {
            let player = Player(
                studentId: student.id,
                heightCm: Double.random(in: 140...180),
                weightKg: Double.random(in: 35...70),
                handedness: .right,
                contractInfo: ContractInfo(totalSessions: 24, completedSessions: Int.random(in: 0...12))
            )
            let sdPlayer = SDPlayer.from(player)
            modelContext.insert(sdPlayer)
            
            let contract = Contract(
                studentId: student.id,
                contractNumber: 1,
                kind: .privateBundle,
                enrollmentDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
                pricePerSession: 200,
                bundleSize: 10
            )
            let sdContract = SDContract.from(contract)
            modelContext.insert(sdContract)
        }
        
        // Create micro cycles for first program
        if let firstProgram = Program.samples.first {
            for cycle in MicroCycle.samples(for: firstProgram.id) {
                let sdCycle = SDMicroCycle.from(cycle)
                modelContext.insert(sdCycle)
            }
        }
        
        do {
            try modelContext.save()
            debugLog("✅ Sample data loaded")
        } catch {
            debugLog("❌ Failed to save sample data: \(error)")
        }
    }
    
    // MARK: - Cloud Sync (no-ops; CloudKit handles sync automatically)
    /// CloudKit syncs SwiftData automatically - this is a no-op for legacy callers.
    func syncFromCloud() async {
        lastSyncDate = Date()
    }

    /// CloudKit syncs SwiftData automatically - this is a no-op for legacy callers.
    func syncToCloud() async {
        lastSyncDate = Date()
    }

    /// CloudKit syncs SwiftData automatically - this is a no-op for legacy callers.
    func fullSync() async {
        await refreshAllCaches()
        lastSyncDate = Date()
    }

    // MARK: - Student CRUD
    func addStudent(_ student: Student, player: Player? = nil) {
        let sdStudent = SDStudent.from(student)
        modelContext.insert(sdStudent)
        stampProvenanceOnCreate(sdStudent)

        if let player = player {
            let sdPlayer = SDPlayer.from(player)
            modelContext.insert(sdPlayer)
        }

        saveAndRefresh()
    }
    
    func updateStudent(_ student: Student) {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == student.id })
            if let sdStudent = try modelContext.fetch(descriptor).first {
                // Snapshot prior state for the version history before applying any change.
                recordStudentRevision(sdStudent, reason: .manualEdit)
                sdStudent.name = student.name
                sdStudent.chineseName = student.chineseName
                sdStudent.avatarColor = student.avatarColor
                sdStudent.attendanceStatus = student.attendanceStatus
                sdStudent.categoryId = student.categoryId
                sdStudent.coachId = cachedCoach.id
                sdStudent.programId = student.programId
                sdStudent.birthdate = student.birthdate
                sdStudent.birthMonth = student.birthMonth
                sdStudent.birthYear = student.birthYear
                sdStudent.schoolGrade = student.schoolGrade
                sdStudent.profileImageUrl = student.profileImageUrl
                sdStudent.profileImageData = student.profileImageData
                sdStudent.thumbnailImageData = student.thumbnailImageData
                sdStudent.parentalTouchpoints = student.parentalTouchpoints
                sdStudent.lastParentContact = student.lastParentContact
                sdStudent.mediaAssets = student.mediaAssets
                sdStudent.personalBests = student.personalBests
                sdStudent.performanceGrade = student.performanceGrade
                sdStudent.gradeHistory = student.gradeHistory
                sdStudent.updatedAt = Date()
                stampProvenanceOnEdit(sdStudent)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update student: \(error)")
        }
    }
    
    func deleteStudent(_ student: Student) {
        do {
            // First, delete all contracts associated with this student (locally)
            let contractDescriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.studentId == student.id })
            let studentContracts = try modelContext.fetch(contractDescriptor)
            let studentContractIds = studentContracts.map(\.id)
            for contract in studentContracts {
                modelContext.delete(contract)
            }
            
            // Delete associated player locally
            let playerDescriptor = FetchDescriptor<SDPlayer>(predicate: #Predicate { $0.studentId == student.id })
            let studentPlayers = try modelContext.fetch(playerDescriptor)
            let studentPlayerIds = studentPlayers.map(\.id)
            for player in studentPlayers {
                modelContext.delete(player)
            }
            
            // Delete the student
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == student.id })
            if let sdStudent = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdStudent)
                _ = studentContractIds
                _ = studentPlayerIds
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete student: \(error)")
        }
    }
    
    func player(for studentId: UUID) -> Player? {
        cachedPlayers.first { $0.studentId == studentId }
    }
    
    func addPlayer(_ player: Player) {
        let sdPlayer = SDPlayer.from(player)
        modelContext.insert(sdPlayer)
        saveAndRefresh()
    }
    
    func updatePlayer(_ player: Player) {
        do {
            let descriptor = FetchDescriptor<SDPlayer>(predicate: #Predicate { $0.id == player.id })
            if let sdPlayer = try modelContext.fetch(descriptor).first {
                sdPlayer.heightCm = player.heightCm
                sdPlayer.weightKg = player.weightKg
                sdPlayer.wingspanCm = player.wingspanCm
                sdPlayer.handedness = player.handedness
                sdPlayer.position = player.position
                sdPlayer.jerseyNumber = player.jerseyNumber
                sdPlayer.setParentInfo(player.parentInfo)
                sdPlayer.setSecondaryParentInfo(player.secondaryParentInfo)
                sdPlayer.setContractInfo(player.contractInfo)
                sdPlayer.setSkills(player.skills)
                sdPlayer.coachNotes = player.coachNotes
                sdPlayer.medicalNotes = player.medicalNotes
                sdPlayer.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update player: \(error)")
        }
    }
    
    // MARK: - Program CRUD
    func addProgram(_ program: Program) {
        let sdProgram = SDProgram.from(program)
        modelContext.insert(sdProgram)
        
        // Save to local storage immediately
        do {
            try modelContext.save()
            debugLog("💾 [PROGRAM-CREATE] Program saved locally: \(program.name) (ID: \(program.id))")
            debugLog("   - Created at: \(program.createdAt)")
        } catch {
            debugLog("❌ [PROGRAM-CREATE] Failed to save program locally: \(error)")
            return
        }
        
        // Refresh caches for UI
        refreshCachesSync()
        debugLog("   - Cache refreshed, total programs: \(cachedPrograms.count)")
        
    }
    
    func updateProgram(_ program: Program) {
        do {
            let descriptor = FetchDescriptor<SDProgram>(predicate: #Predicate { $0.id == program.id })
            if let sdProgram = try modelContext.fetch(descriptor).first {
                sdProgram.name = program.name
                sdProgram.programType = program.programType
                sdProgram.ageGroup = program.ageGroup
                sdProgram.durationWeeks = program.durationWeeks
                sdProgram.usesPhases = program.usesPhases
                sdProgram.programDescription = program.description
                sdProgram.objectives = program.objectives
                sdProgram.enrolledStudentIds = program.enrolledStudentIds
                sdProgram.coachId = program.coachId
                sdProgram.status = program.status
                sdProgram.colorHex = program.colorHex
                sdProgram.mascot = program.mascot
                sdProgram.startDate = program.startDate
                sdProgram.endDate = program.endDate
                sdProgram.imageData = program.imageData
                sdProgram.stars = program.stars
                
                // Recurring schedule
                sdProgram.recurringDays = program.recurringDays
                sdProgram.defaultSessionTime = program.defaultSessionTime
                sdProgram.defaultSessionDurationMinutes = program.defaultSessionDurationMinutes
                
                // Skill targets
                sdProgram.skillTargets = program.skillTargets
                
                // Location
                sdProgram.locationId = program.locationId
                sdProgram.locationName = program.locationName

                // School (only meaningful when programType == .school)
                sdProgram.schoolId = program.schoolId

                sdProgram.updatedAt = Date()
                
                // Save to local storage immediately
                do {
                    try modelContext.save()
                    debugLog("💾 Program updated locally: \(program.name)")
                } catch {
                    debugLog("❌ Failed to save program update locally: \(error)")
                }
                
                // Refresh caches for UI
                refreshCachesSync()
                
            }
        } catch {
            debugLog("❌ Failed to update program: \(error)")
        }
    }
    
    func deleteProgram(_ program: Program) {
        do {
            let descriptor = FetchDescriptor<SDProgram>(predicate: #Predicate { $0.id == program.id })
            if let sdProgram = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdProgram)
                
                // Also delete associated micro cycles
                let cycleDescriptor = FetchDescriptor<SDMicroCycle>(predicate: #Predicate { $0.programId == program.id })
                let cycles = try modelContext.fetch(cycleDescriptor)
                for cycle in cycles {
                    modelContext.delete(cycle)
                }
                
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete program: \(error)")
        }
    }

    // MARK: - Session materialization (recurring schedule → calendar)

    /// Create one `SessionEvent` per occurrence of the program's recurring
    /// weekday(s) inside the phase's date range, at the program's default
    /// session time and duration. Title is "<phase title> · <n>" where `n`
    /// is the session's index within the phase.
    ///
    /// Skips creation entirely if the program has no recurring days, or if
    /// the phase has no resolvable date range. Returns the count of sessions
    /// actually persisted so callers can surface "Generated N sessions" UX.
    @discardableResult
    func materializeSessions(for phase: MicroCycle) -> Int {
        guard let program = cachedPrograms.first(where: { $0.id == phase.programId }) else { return 0 }
        guard !program.recurringDays.isEmpty else { return 0 }

        let cal = Calendar.current
        // Resolve the phase window. Prefer explicit dates; otherwise derive
        // from the program's startDate plus the cumulative weeks of all
        // earlier phases on the same program.
        let resolvedStart: Date = {
            if let s = phase.startDate { return s }
            let earlier = cachedMicroCycles
                .filter { $0.programId == program.id && $0.phaseNumber < phase.phaseNumber }
                .map(\.durationWeeks)
                .reduce(0, +)
            let base = program.startDate ?? cal.startOfDay(for: Date())
            return cal.date(byAdding: .day, value: earlier * 7, to: base) ?? base
        }()
        let resolvedEnd: Date = phase.endDate
            ?? cal.date(byAdding: .day, value: phase.durationWeeks * 7 - 1, to: resolvedStart)
            ?? resolvedStart

        // Default time of day. defaultSessionTime stores only the time part
        // semantically — extract hour/minute and apply them to each weekday.
        let timeOfDay: (hour: Int, minute: Int) = {
            if let t = program.defaultSessionTime {
                let comps = cal.dateComponents([.hour, .minute], from: t)
                return (comps.hour ?? 18, comps.minute ?? 30)
            }
            return (18, 30)
        }()
        let durationMinutes = max(15, program.defaultSessionDurationMinutes)
        let recurringWeekdayValues = Set(program.recurringDays.map { $0.rawValue })
        // Multi-weekday phases drop the "· N" ordinal — once sessions span
        // more than one weekday, the ordinal stops conveying useful order
        // (Wed/Thu/Wed/Thu/… reads as 1/2/3/4 which is misleading). The date
        // column on every list/calendar already disambiguates.
        let suffixOrdinals = program.recurringDays.count <= 1

        // Index existing sessions for this program by start-of-day so we
        // can dedupe / adopt instead of creating fresh ones. Orphan
        // sessions (microCycleId == nil) created when the program ran in
        // phase-less mode get re-tagged with the new phase id; sessions
        // that already belong to a phase are left alone (no duplicates).
        var sessionsForProgram: [Date: SessionEvent] = [:]
        for event in cachedSessionEvents where event.programId == program.id {
            let key = cal.startOfDay(for: event.date)
            // Prefer phase-tagged events when collisions happen — they're
            // the "primary" record we care about preserving.
            if let existing = sessionsForProgram[key] {
                if existing.microCycleId == nil && event.microCycleId != nil {
                    sessionsForProgram[key] = event
                }
            } else {
                sessionsForProgram[key] = event
            }
        }

        var sessionNumber = 0
        var created = 0
        var adopted = 0
        var cursor = cal.startOfDay(for: resolvedStart)
        let lastDay = cal.startOfDay(for: resolvedEnd)

        while cursor <= lastDay {
            let weekday = cal.component(.weekday, from: cursor)
            if recurringWeekdayValues.contains(weekday) {
                sessionNumber += 1
                let startTime = cal.date(bySettingHour: timeOfDay.hour,
                                         minute: timeOfDay.minute,
                                         second: 0,
                                         of: cursor) ?? cursor
                let endTime = cal.date(byAdding: .minute, value: durationMinutes, to: startTime) ?? startTime

                let title = suffixOrdinals
                    ? "\(phase.title) · \(sessionNumber)"
                    : phase.title

                if let existing = sessionsForProgram[cursor] {
                    if existing.microCycleId == nil {
                        // Orphan from the program's pre-phase era — adopt it
                        // into this phase so the coach's customisations (drills,
                        // notes) are preserved instead of duplicated.
                        var adoptedEvent = existing
                        adoptedEvent.microCycleId = phase.id
                        // Only retitle if the coach hasn't customised the title.
                        // A title that still equals the auto-generated "Program
                        // Name · N" form is safe to refresh; anything else stays.
                        if existing.title.isEmpty || existing.title.hasPrefix(program.name) {
                            adoptedEvent.title = title
                        }
                        adoptedEvent.updatedAt = Date()
                        updateSessionEvent(adoptedEvent)
                        adopted += 1
                    }
                    // else: already belongs to a phase (this one or another) —
                    // never create a duplicate.
                } else {
                    let event = SessionEvent(
                        microCycleId: phase.id,
                        programId: program.id,
                        sessionType: .training,
                        title: title,
                        date: startTime,
                        startTime: startTime,
                        endTime: endTime,
                        location: program.locationName,
                        attendeeIds: program.enrolledStudentIds,
                        createdByCoachId: program.coachId ?? loggedInCoachId
                    )
                    addSessionEvent(event)
                    created += 1
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if adopted > 0 {
            debugLog("📌 Adopted \(adopted) orphan session(s) into phase \(phase.title)")
        }
        return created
    }

    /// One-shot cleanup for programs that ended up with duplicate sessions
    /// (typically after adding phases to a program that already had
    /// program-level sessions on the same calendar dates). Groups sessions
    /// by start-of-day, picks the "best" one to keep, deletes the rest.
    ///
    /// Heuristic for which to keep, in order:
    /// 1. The session with the most curriculum drills (coach has invested time).
    /// 2. The one with `coachNotes`/`notes` set.
    /// 3. The one with `actualAttendeeIds` populated (real attendance recorded).
    /// 4. The phase-tagged one (microCycleId != nil) over the orphan.
    /// 5. The one with `status != .scheduled` over a default-state record.
    /// 6. The oldest `createdAt` (assume earliest is canonical).
    @discardableResult
    func dedupeProgramSessions(forProgramId programId: UUID) -> Int {
        let cal = Calendar.current
        let allForProgram = cachedSessionEvents.filter { $0.programId == programId }

        // Group by start-of-day. We deliberately don't include time-of-day
        // in the key — duplicates we care about are calendar-day collisions,
        // not back-to-back morning/afternoon sessions on the same day.
        var groups: [Date: [SessionEvent]] = [:]
        for event in allForProgram {
            let key = cal.startOfDay(for: event.date)
            groups[key, default: []].append(event)
        }

        var deleted = 0
        for (_, events) in groups where events.count > 1 {
            let keeper = events.max { lhs, rhs in
                let lhsScore = sessionContentScore(lhs)
                let rhsScore = sessionContentScore(rhs)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                // Tiebreak: phase-tagged > orphan, then earliest createdAt.
                let lhsHasPhase = lhs.microCycleId != nil ? 1 : 0
                let rhsHasPhase = rhs.microCycleId != nil ? 1 : 0
                if lhsHasPhase != rhsHasPhase { return lhsHasPhase < rhsHasPhase }
                return lhs.createdAt > rhs.createdAt   // older wins (returns false from `max` when older = lhs)
            }
            guard let keeper = keeper else { continue }
            for event in events where event.id != keeper.id {
                deleteSessionEvent(event)
                deleted += 1
            }
        }
        if deleted > 0 {
            debugLog("🧹 Removed \(deleted) duplicate session(s) for program \(programId)")
        }
        return deleted
    }

    /// Higher score = "more invested in" — used as the primary keep heuristic
    /// during dedupe. Pure function; side-effect free.
    private func sessionContentScore(_ event: SessionEvent) -> Int {
        var score = 0
        score += event.curriculum.totalDrillCount * 10
        if (event.notes?.isEmpty == false) { score += 5 }
        if (event.coachNotes?.isEmpty == false) { score += 5 }
        if !event.actualAttendeeIds.isEmpty { score += 3 }
        if !event.games.isEmpty { score += 3 }
        if event.status != .scheduled { score += 2 }
        return score
    }

    /// Backfill helper for the "Generate sessions" button: materializes every
    /// phase on the program that currently has zero `SessionEvent`s. Safe to
    /// call repeatedly — phases that already have sessions are left alone.
    @discardableResult
    func materializeMissingSessions(forProgramId programId: UUID) -> Int {
        let phases = cachedMicroCycles
            .filter { $0.programId == programId }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        var created = 0
        for phase in phases {
            let existing = cachedSessionEvents.contains { $0.microCycleId == phase.id }
            if !existing {
                created += materializeSessions(for: phase)
            }
        }
        return created
    }

    /// Generate sessions for newly-added recurring days only.
    /// Used after `updateProgram` adds e.g. Wednesday alongside an existing
    /// Thursday schedule — we walk every phase's date window and create
    /// sessions on the new weekdays. Existing Thursday sessions are not
    /// touched (de-duped by exact `(weekday, calendar-day)` since dates
    /// across weekdays don't collide). Returns the count actually created.
    @discardableResult
    func backfillSessions(forProgramId programId: UUID, addedDays: Set<Weekday>) -> Int {
        guard !addedDays.isEmpty else { return 0 }
        guard let program = cachedPrograms.first(where: { $0.id == programId }) else { return 0 }
        let phases = cachedMicroCycles
            .filter { $0.programId == programId }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        guard !phases.isEmpty else { return 0 }

        let cal = Calendar.current
        let timeOfDay: (hour: Int, minute: Int) = {
            if let t = program.defaultSessionTime {
                let comps = cal.dateComponents([.hour, .minute], from: t)
                return (comps.hour ?? 18, comps.minute ?? 30)
            }
            return (18, 30)
        }()
        let durationMinutes = max(15, program.defaultSessionDurationMinutes)
        let addedWeekdayValues = Set(addedDays.map { $0.rawValue })
        let suffixOrdinals = program.recurringDays.count <= 1

        var created = 0
        for phase in phases {
            let resolvedStart: Date = {
                if let s = phase.startDate { return s }
                let earlier = phases
                    .filter { $0.phaseNumber < phase.phaseNumber }
                    .map(\.durationWeeks)
                    .reduce(0, +)
                let base = program.startDate ?? cal.startOfDay(for: Date())
                return cal.date(byAdding: .day, value: earlier * 7, to: base) ?? base
            }()
            let resolvedEnd: Date = phase.endDate
                ?? cal.date(byAdding: .day, value: phase.durationWeeks * 7 - 1, to: resolvedStart)
                ?? resolvedStart

            // Index existing sessions for this phase by start-of-day, so we
            // skip any date that already has a session (paranoid de-dupe in
            // case the coach manually scheduled an extra Wednesday earlier).
            let existingDays: Set<Date> = Set(
                cachedSessionEvents
                    .filter { $0.microCycleId == phase.id }
                    .map { cal.startOfDay(for: $0.date) }
            )

            var cursor = cal.startOfDay(for: resolvedStart)
            let lastDay = cal.startOfDay(for: resolvedEnd)
            while cursor <= lastDay {
                let weekday = cal.component(.weekday, from: cursor)
                if addedWeekdayValues.contains(weekday), !existingDays.contains(cursor) {
                    let startTime = cal.date(bySettingHour: timeOfDay.hour,
                                             minute: timeOfDay.minute,
                                             second: 0,
                                             of: cursor) ?? cursor
                    let endTime = cal.date(byAdding: .minute, value: durationMinutes, to: startTime) ?? startTime

                    let event = SessionEvent(
                        microCycleId: phase.id,
                        programId: program.id,
                        sessionType: .training,
                        title: suffixOrdinals ? "\(phase.title) · 1" : phase.title,
                        date: startTime,
                        startTime: startTime,
                        endTime: endTime,
                        location: program.locationName,
                        attendeeIds: program.enrolledStudentIds,
                        createdByCoachId: program.coachId ?? loggedInCoachId
                    )
                    addSessionEvent(event)
                    created += 1
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return created
    }

    /// Cancel sessions on weekdays that the coach removed from the program's
    /// recurring schedule. Only future sessions are touched — past ones are
    /// historical record. Returns the count cancelled.
    /// "Cancel" here = delete the session events (not soft-cancel). Coaches
    /// who care about audit trail can re-add them manually; preserving them
    /// in `.cancelled` status would clutter every list view.
    @discardableResult
    func cancelFutureSessions(forProgramId programId: UUID, removedDays: Set<Weekday>) -> Int {
        guard !removedDays.isEmpty else { return 0 }
        let cal = Calendar.current
        let removedWeekdayValues = Set(removedDays.map { $0.rawValue })
        let now = Date()

        let toCancel = cachedSessionEvents.filter { event in
            guard event.programId == programId else { return false }
            guard event.startTime > now else { return false }
            // Don't touch sessions the coach has already started/completed.
            guard event.status == .scheduled else { return false }
            let weekday = cal.component(.weekday, from: event.date)
            return removedWeekdayValues.contains(weekday)
        }

        for event in toCancel {
            deleteSessionEvent(event)
        }
        return toCancel.count
    }

    // MARK: - MicroCycle CRUD
    func addMicroCycle(_ microCycle: MicroCycle) {
        let sdCycle = SDMicroCycle.from(microCycle)
        modelContext.insert(sdCycle)
        
        // Save to local storage immediately
        do {
            try modelContext.save()
            debugLog("💾 [PHASE-CREATE] Phase saved locally: \(microCycle.title) (ID: \(microCycle.id))")
            debugLog("   - Program ID: \(microCycle.programId)")
            debugLog("   - Created at: \(microCycle.createdAt)")
        } catch {
            debugLog("❌ [PHASE-CREATE] Failed to save phase locally: \(error)")
            return
        }
        
        // Refresh caches for UI
        refreshCachesSync()
        debugLog("   - Cache refreshed, total phases: \(cachedMicroCycles.count)")
        
    }

    func updateMicroCycle(_ microCycle: MicroCycle) {
        do {
            let descriptor = FetchDescriptor<SDMicroCycle>(predicate: #Predicate { $0.id == microCycle.id })
            if let sdCycle = try modelContext.fetch(descriptor).first {
                sdCycle.phaseNumber = microCycle.phaseNumber
                sdCycle.title = microCycle.title
                sdCycle.focus = microCycle.focus
                sdCycle.durationWeeks = microCycle.durationWeeks
                sdCycle.cycleDescription = microCycle.description
                sdCycle.objectives = microCycle.objectives
                sdCycle.suggestedDrillIds = microCycle.suggestedDrillIds
                sdCycle.startDate = microCycle.startDate
                sdCycle.endDate = microCycle.endDate
                sdCycle.intensity = microCycle.intensity
                sdCycle.volume = microCycle.volume
                sdCycle.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update micro cycle: \(error)")
        }
    }

    // MARK: - Phase reorder (calendar-safe)
    /// Reorder the phases of `program` to the new ordering produced by
    /// SwiftUI's `.onMove`. This is the *only* sanctioned way to change
    /// phase ordering — it preserves the invariant that phases always form a
    /// contiguous chain on the calendar with `phaseNumber` reflecting
    /// chronology.
    ///
    /// Algorithm:
    /// 1. Take phases in their current `phaseNumber` order.
    /// 2. Apply the move; this gives the new logical order.
    /// 3. Walk the new order from the program's `startDate` (or the earliest
    ///    existing phase startDate as fallback). For each phase, set
    ///    `startDate = anchor`, `endDate = anchor + weeks`, and shift every
    ///    SessionEvent inside the phase by `Δ = newStart - oldStart`.
    /// 4. Re-stamp `phaseNumber` by index.
    func reorderPhases(in programId: UUID, oldIndices: IndexSet, newOffset: Int) {
        var phases = cachedMicroCycles
            .filter { $0.programId == programId }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        guard !phases.isEmpty else { return }

        phases.move(fromOffsets: oldIndices, toOffset: newOffset)

        // Anchor: program's startDate, falling back to the earliest current
        // phase startDate, falling back to today.
        let program = cachedPrograms.first(where: { $0.id == programId })
        let anchor: Date = program?.startDate
            ?? phases.compactMap(\.startDate).min()
            ?? Calendar.current.startOfDay(for: Date())

        let cal = Calendar.current
        var cursor = cal.startOfDay(for: anchor)

        for (index, phase) in phases.enumerated() {
            let oldStart = phase.startDate.map { cal.startOfDay(for: $0) }
            let newStart = cursor
            let newEnd = cal.date(byAdding: .day, value: phase.durationWeeks * 7, to: newStart) ?? newStart

            // Shift every session inside the phase by Δ so they stay anchored
            // to their phase rather than to a calendar position the coach
            // didn't intend to keep.
            if let oldStart, oldStart != newStart {
                let deltaSeconds = newStart.timeIntervalSince(oldStart)
                let phaseSessions = cachedSessionEvents.filter { $0.microCycleId == phase.id }
                for session in phaseSessions {
                    var updated = session
                    updated.date = session.date.addingTimeInterval(deltaSeconds)
                    updated.startTime = session.startTime.addingTimeInterval(deltaSeconds)
                    updated.endTime = session.endTime.addingTimeInterval(deltaSeconds)
                    updateSessionEvent(updated)
                }
            }

            var updated = phase
            updated.phaseNumber = index + 1
            updated.startDate = newStart
            updated.endDate = newEnd
            updateMicroCycle(updated)

            cursor = cal.date(byAdding: .day, value: 1, to: newEnd) ?? newEnd
        }
    }

    func deleteMicroCycle(_ microCycle: MicroCycle) {
        do {
            let descriptor = FetchDescriptor<SDMicroCycle>(predicate: #Predicate { $0.id == microCycle.id })
            if let sdCycle = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdCycle)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete micro cycle: \(error)")
        }
    }

    // MARK: - Session CRUD
    func addSessionEvent(_ event: SessionEvent) {
        let sdSession = SDSessionEvent.from(event)
        modelContext.insert(sdSession)
        
        // Save to local storage immediately
        do {
            try modelContext.save()
            debugLog("💾 [SESSION-CREATE] Session saved locally: \(event.title) (ID: \(event.id))")
            debugLog("   - Phase ID: \(event.microCycleId?.uuidString ?? "none")")
            debugLog("   - Program ID: \(event.programId?.uuidString ?? "none")")
            debugLog("   - Date: \(event.date)")
        } catch {
            debugLog("❌ [SESSION-CREATE] Failed to save session locally: \(error)")
            return
        }
        
        // Refresh caches for UI
        refreshCachesSync()
        debugLog("   - Cache refreshed, total sessions: \(cachedSessionEvents.count)")
        
    }

    func updateSessionEvent(_ event: SessionEvent) {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == event.id })
            if let sdSession = try modelContext.fetch(descriptor).first {
                // Debug: Log games before save
                debugLog("🎮 [DEBUG] updateSessionEvent: \(event.title)")
                debugLog("   - Input games count: \(event.games.count)")
                if !event.games.isEmpty {
                    for game in event.games {
                        debugLog("   - Game \(game.gameNumber): status=\(game.status.rawValue), playerStats=\(game.playerStats.count)")
                    }
                }
                
                sdSession.microCycleId = event.microCycleId
                sdSession.programId = event.programId
                sdSession.sessionType = event.sessionType
                sdSession.title = event.title
                sdSession.date = event.date
                sdSession.startTime = event.startTime
                sdSession.endTime = event.endTime
                sdSession.location = event.location
                sdSession.status = event.status
                sdSession.curriculum = event.curriculum
                sdSession.attendeeIds = event.attendeeIds
                sdSession.actualAttendeeIds = event.actualAttendeeIds
                sdSession.excusedAbsences = event.excusedAbsences
                sdSession.attendancePhotoPath = event.attendancePhotoPath
                sdSession.notes = event.notes
                sdSession.coachNotes = event.coachNotes
                sdSession.manOfTheMatchId = event.manOfTheMatchId
                sdSession.drillsCompleted = event.drillsCompleted
                sdSession.rating = event.rating
                sdSession.games = event.games  // Persist in-session games
                sdSession.updatedAt = Date()
                
                // Debug: Verify games were set
                debugLog("   - Saved games count: \(sdSession.games.count)")
                
                saveAndRefresh()
                
                // Update contracts for all students who attended this session
                updateContractsForAttendance(sessionEvent: event)
            }
        } catch {
            debugLog("❌ Failed to update session: \(error)")
        }
    }
    
    // MARK: - Field-level session writes (stale-snapshot-safe)
    //
    // Three-way attendance state for `setStudentAttendanceState`. Lives in
    // the manager namespace so callers don't pull in a view-private type.
    //
    // The legacy `updateSessionEvent` does a whole-record overwrite. That's
    // fine when the caller has a fresh snapshot, but it's a foot-gun when
    // a `@State` copy in a long-lived view has gone stale relative to
    // sibling fields that another path updated in the meantime. Concrete
    // failure mode observed in the field: a stale `FlightySessionPageView`
    // re-saved itself after attendance changes and wiped the games array
    // plus the attendance photo that a sibling view had added.
    //
    // The helpers below all (a) fetch the canonical SDSessionEvent from the
    // context, (b) snapshot it into the revision history first, then
    // (c) mutate ONLY the named field. Stale fields in the caller's struct
    // can no longer overwrite live data.

    /// Appends a single game to a session, taking the current persisted
    /// games array as the base — so a stale local copy can't accidentally
    /// drop games that another path already added.
    func appendSessionGame(toSessionId sessionId: UUID, game: SessionGame) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            var games = sd.games
            games.append(game)
            sd.games = games
        }
    }

    /// Replaces a single game in-place (matched by `game.id`). No-op if the
    /// game is no longer on the session.
    func updateSessionGame(inSessionId sessionId: UUID, game: SessionGame) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            var games = sd.games
            guard let idx = games.firstIndex(where: { $0.id == game.id }) else { return }
            games[idx] = game
            sd.games = games
        }
    }

    /// Removes a single game from the session by id.
    func deleteSessionGame(inSessionId sessionId: UUID, gameId: UUID) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            sd.games = sd.games.filter { $0.id != gameId }
        }
    }

    /// Bulk replace of the games array — used by recap flows that have a
    /// genuinely up-to-date list. Prefer the granular helpers above when
    /// possible.
    func replaceSessionGames(inSessionId sessionId: UUID, games: [SessionGame]) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            sd.games = games
        }
    }

    /// Sets the header-image URL for a session.
    func setSessionHeaderImageURL(sessionId: UUID, url: String?) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            sd.headerImageURL = url
        }
    }

    /// Sets or clears the attendance-photo relative path.
    func setSessionAttendancePhoto(sessionId: UUID, path: String?) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            sd.attendancePhotoPath = path
        }
    }

    /// Replaces the attendance lists wholesale. The arrays themselves come
    /// from the caller (which has computed the new state from a tap), but
    /// every *other* session field stays untouched.
    func setSessionAttendance(sessionId: UUID,
                              actualAttendeeIds: [UUID],
                              excusedAbsences: [UUID]) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            sd.actualAttendeeIds = actualAttendeeIds
            sd.excusedAbsences = excusedAbsences
        }
        // Keep contracts in lockstep with attendance changes.
        if let fresh = sessionEvents.first(where: { $0.id == sessionId }) {
            updateContractsForAttendance(sessionEvent: fresh)
        }
    }

    /// Marks a single student as present / absent / excused. Reads the
    /// current arrays out of SwiftData, applies the diff, and writes back.
    /// Saves a round-trip vs. the caller computing arrays itself.
    func setStudentAttendanceState(sessionId: UUID,
                                   studentId: UUID,
                                   state: AttendanceTriState) {
        mutateSession(id: sessionId, reason: .manualEdit) { sd in
            var actual = Set(sd.actualAttendeeIds)
            var excused = Set(sd.excusedAbsences)
            var unexcused = Set(sd.unexcusedAbsences)
            actual.remove(studentId)
            excused.remove(studentId)
            unexcused.remove(studentId)
            switch state {
            case .present:  actual.insert(studentId)
            case .excused:  excused.insert(studentId)
            case .absent:   unexcused.insert(studentId)
            case .unmarked: break  // membership in none of the three
            }
            sd.actualAttendeeIds = Array(actual)
            sd.excusedAbsences = Array(excused)
            sd.unexcusedAbsences = Array(unexcused)
        }
        if let fresh = sessionEvents.first(where: { $0.id == sessionId }) {
            updateContractsForAttendance(sessionEvent: fresh)
        }
    }

    /// Shared plumbing for every field-level helper. Fetches the canonical
    /// row, records a revision snapshot for recoverability, runs the
    /// caller's mutation, stamps `updatedAt`, saves + refreshes caches.
    private func mutateSession(id sessionId: UUID,
                               reason: RevisionReason,
                               apply: (SDSessionEvent) -> Void) {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == sessionId })
            guard let sd = try modelContext.fetch(descriptor).first else {
                debugLog("⚠️ mutateSession: no SDSessionEvent for id \(sessionId)")
                return
            }
            recordSessionRevision(sd, reason: reason)
            apply(sd)
            sd.updatedAt = Date()
            saveAndRefresh()
        } catch {
            debugLog("❌ mutateSession failed: \(error)")
        }
    }

    /// Snapshots the current session into the revision history. Mirrors
    /// `recordDrillRevision` — same retention rules apply via
    /// `pruneRevisions`.
    func recordSessionRevision(
        _ sd: SDSessionEvent,
        reason: RevisionReason,
        triggerBundleId: UUID? = nil,
        actorLabel: String? = nil
    ) {
        do {
            let snapshot = SessionSnapshotV1(sd)
            let data = try JSONEncoder().encode(snapshot)
            let rev = SDEntityRevision(
                entityId: sd.id,
                entityType: .session,
                reason: reason,
                triggerBundleId: triggerBundleId,
                snapshotData: data,
                actorLabel: actorLabel ?? currentCoachLabel
            )
            modelContext.insert(rev)
            pruneRevisions(forEntityId: sd.id, entityType: .session)
        } catch {
            debugLog("❌ recordSessionRevision encode failed: \(error)")
        }
    }

    /// Restores a session to a prior revision. Returns true on success.
    @discardableResult
    func restoreSession(toRevisionId revisionId: UUID) -> Bool {
        do {
            let descriptor = FetchDescriptor<SDEntityRevision>(predicate: #Predicate { $0.id == revisionId })
            guard let rev = try modelContext.fetch(descriptor).first,
                  rev.entityType == .session else { return false }
            let snapshot = try JSONDecoder().decode(SessionSnapshotV1.self, from: rev.snapshotData)
            let sessionId = snapshot.event.id
            let sessionDescriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == sessionId })
            guard let sd = try modelContext.fetch(sessionDescriptor).first else { return false }
            recordSessionRevision(sd, reason: .beforeRestore)
            snapshot.apply(to: sd)
            saveAndRefresh()
            return true
        } catch {
            debugLog("❌ restoreSession failed: \(error)")
            return false
        }
    }

    /// Update contracts to reflect attendance changes for a session
    /// Applies bundle redemption for everyone whose state on this session
    /// consumes one.
    ///
    /// This used to contain a second, divergent redemption implementation that
    /// selected the contract by highest contract number, while
    /// `redeemPrivateAttendance` selected the oldest bundle with capacity. The
    /// same session could be charged to different bundles depending on which
    /// path ran. There is now one authority and it is FIFO.
    ///
    /// Deliberately NOT retroactive and deliberately never un-charges: a
    /// session already redeemed stays redeemed unless the coach explicitly
    /// calls `refundSessionToBundle`. Silently reclaiming past sessions would
    /// move a client's balance without her knowing why.
    private func updateContractsForAttendance(sessionEvent: SessionEvent) {
        let consuming = Set(sessionEvent.actualAttendeeIds)
            .union(sessionEvent.unexcusedAbsences)
        for studentId in consuming {
            redeemPrivateAttendance(sessionId: sessionEvent.id, studentId: studentId)
        }
    }

    private func deductSessionFromContract(studentId: UUID, programId: UUID?) {
        // No-op: Session consumption is now derived from SessionEvent.actualAttendeeIds
        debugLog("⚠️ deductSessionFromContract is deprecated - session consumption is now event-based")
    }
    
    func deleteSessionEvent(_ event: SessionEvent) {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == event.id })
            if let sdSession = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdSession)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete session: \(error)")
        }
    }

    /// Sessions that look like part of the same orphan recurring series as
    /// `event` — same title, weekday, time-of-day, duration, location, and no
    /// program link. Used to bulk-edit/delete legacy recurring sessions that
    /// pre-date the auto-program-on-recurring change.
    func recurringSiblings(of event: SessionEvent) -> [SessionEvent] {
        guard event.programId == nil else { return [] }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: event.date)
        let hourMin = cal.dateComponents([.hour, .minute], from: event.startTime)
        let duration = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        return cachedSessionEvents.filter { other in
            other.programId == nil
                && other.title == event.title
                && other.location == event.location
                && cal.component(.weekday, from: other.date) == weekday
                && cal.dateComponents([.hour, .minute], from: other.startTime) == hourMin
                && Int(other.endTime.timeIntervalSince(other.startTime) / 60) == duration
        }
    }

    /// Delete the entire orphan recurring series that `event` belongs to.
    /// Returns the number of sessions removed (≥1).
    @discardableResult
    func deleteRecurringSeries(of event: SessionEvent) -> Int {
        let series = recurringSiblings(of: event)
        guard !series.isEmpty else {
            deleteSessionEvent(event)
            return 1
        }
        for s in series { deleteSessionEvent(s) }
        return series.count
    }
    
    /// Rewrite legacy absolute attendance-photo paths to the migration-safe
    /// relative form (`AttendancePhotos/attendance_<id>.jpg`). Container UUIDs
    /// change across iOS app reinstalls, so any absolute path stored before
    /// this migration breaks at load time. `PhotoCaptureManager` can still
    /// resolve them via fallback, but rewriting up front keeps subsequent
    /// loads on the fast path. Idempotent.
    /// One-time photo rescue: moves student photos that exist ONLY in this
    /// device's local image cache into the synced record.
    ///
    /// The Supabase era stored photos remotely and wrote only the URL into
    /// the record; the host is dead, so ~110 photos survive solely in the
    /// iPhone's cache directory — one reinstall away from being lost, and
    /// invisible to the Mac. Running on the device that HOLDS the cache (the
    /// iPhone), this writes the bytes into profileImageData/thumbnailImageData
    /// so CloudKit syncs them everywhere and the photo becomes durable data.
    /// On devices with an empty cache (the Mac) it is a no-op. Self-limiting:
    /// once a record has bytes it is skipped, so subsequent launches cost a
    /// handful of existence checks. Deliberately no revision snapshots — a
    /// mechanical rescue of 100+ records would flood the history.
    func backfillStudentPhotosFromLocalCache() {
        do {
            let descriptor = FetchDescriptor<SDStudent>()
            let students = try modelContext.fetch(descriptor)
            var rescued = 0
            for sdStudent in students {
                let hasData = !(sdStudent.profileImageData ?? Data()).isEmpty
                guard !hasData else { continue }
                let cacheId = ImageCacheManager.studentImageId(sdStudent.id)
                guard let jpeg = ImageCacheManager.shared.cachedJPEGData(
                    for: cacheId, maxEdge: 512) else { continue }
                sdStudent.profileImageData = jpeg
                sdStudent.thumbnailImageData = makeProfileThumbnailData(from: jpeg)
                    ?? jpeg
                sdStudent.updatedAt = Date()
                rescued += 1
            }
            if rescued > 0 {
                try modelContext.save()
                refreshCachesSync()
                objectWillChange.send()
                debugLog("📸 Photo backfill: rescued \(rescued) cache-only student photos into synced records")
            }
        } catch {
            debugLog("❌ Photo backfill failed: \(error)")
        }
    }

    func migrateAttendancePhotoPaths() {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>()
            let allSessions = try modelContext.fetch(descriptor)

            var updatedCount = 0
            var unresolvedCount = 0
            for session in allSessions {
                guard let stored = session.attendancePhotoPath, !stored.isEmpty else { continue }
                // URL-form references (legacy Supabase / web) are left alone.
                if stored.hasPrefix("http://") || stored.hasPrefix("https://") { continue }
                if let canonical = PhotoCaptureManager.shared.canonicalRelativePath(for: stored) {
                    if canonical != stored {
                        session.attendancePhotoPath = canonical
                        session.updatedAt = Date()
                        updatedCount += 1
                    }
                } else {
                    // File missing on disk — leave the value alone so the UI
                    // can surface "Unable to load" rather than silently
                    // claiming there's no photo.
                    unresolvedCount += 1
                }
            }

            if updatedCount > 0 {
                try modelContext.save()
                refreshCachesSync()
                debugLog("✅ Migrated \(updatedCount) attendance photo paths to relative form")
            }
            if unresolvedCount > 0 {
                debugLog("⚠️ \(unresolvedCount) attendance photos referenced but not found on disk")
            }
        } catch {
            debugLog("❌ Failed to migrate attendance photo paths: \(error)")
        }
    }

    /// Migrate all existing sessions to use 30/30/30 minute durations (was 10/35/15)
    func migrateSessionDurationsTo30() {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>()
            let allSessions = try modelContext.fetch(descriptor)
            
            var updatedCount = 0
            for session in allSessions {
                var curriculum = session.curriculum
                // Only update if using old default values (10/35/15)
                if curriculum.warmupMinutes == 10 && curriculum.skillsMinutes == 35 && curriculum.gameMinutes == 15 {
                    curriculum.warmupMinutes = 30
                    curriculum.skillsMinutes = 30
                    curriculum.gameMinutes = 30
                    session.curriculum = curriculum
                    session.updatedAt = Date()
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                try modelContext.save()
                refreshCachesSync()
                debugLog("✅ Migrated \(updatedCount) sessions to 30/30/30 durations")
            } else {
                debugLog("ℹ️ No sessions needed duration migration")
            }
        } catch {
            debugLog("❌ Failed to migrate session durations: \(error)")
        }
    }
    
    // MARK: - Drill CRUD
    
    /// Syncs sample drills to the database, adding any that don't already exist by name
    func syncSampleDrills() {
        do {
            let descriptor = FetchDescriptor<SDDrill>()
            let existingDrills = try modelContext.fetch(descriptor)
            let existingNames = Set(existingDrills.map { $0.name.lowercased() })
            
            var addedCount = 0
            for sampleDrill in DrillItem.samples {
                if !existingNames.contains(sampleDrill.name.lowercased()) {
                    let sdDrill = SDDrill.from(sampleDrill)
                    modelContext.insert(sdDrill)
                    addedCount += 1
                }
            }
            
            if addedCount > 0 {
                try modelContext.save()
                debugLog("✅ Added \(addedCount) new sample drills to library")
                // Refresh drills cache
                let sdDrills = try modelContext.fetch(FetchDescriptor<SDDrill>())
                cachedDrills = sdDrills.map { $0.toStruct() }
            }
        } catch {
            debugLog("❌ Failed to sync sample drills: \(error)")
        }
    }
    
    /// Removes duplicate drills, keeping only the oldest one (or favorited one) for each unique name
    func deduplicateDrills() {
        do {
            let descriptor = FetchDescriptor<SDDrill>()
            let allDrills = try modelContext.fetch(descriptor)
            
            // Group drills by lowercase name
            var drillsByName: [String: [SDDrill]] = [:]
            for drill in allDrills {
                let key = drill.name.lowercased().trimmingCharacters(in: .whitespaces)
                drillsByName[key, default: []].append(drill)
            }
            
            var deletedCount = 0
            var deletedIds: [UUID] = []
            
            for (name, drills) in drillsByName {
                guard drills.count > 1 else { continue }
                
                // Sort: prefer favorited, then oldest createdAt
                let sorted = drills.sorted { drill1, drill2 in
                    if drill1.isFavorite != drill2.isFavorite {
                        return drill1.isFavorite  // Favorited first
                    }
                    return drill1.createdAt < drill2.createdAt  // Oldest first
                }
                
                // Keep the first one, delete the rest
                let toKeep = sorted[0]
                let toDelete = sorted.dropFirst()
                
                for drill in toDelete {
                    deletedIds.append(drill.id)
                    modelContext.delete(drill)
                    deletedCount += 1
                }
                
                debugLog("🧹 Deduplicated '\(name)': kept 1, removed \(toDelete.count)")
            }
            
            if deletedCount > 0 {
                try modelContext.save()
                refreshCachesSync()
                _ = deletedIds
                debugLog("✅ Removed \(deletedCount) duplicate drills")
            } else {
                debugLog("ℹ️ No duplicate drills found")
            }
        } catch {
            debugLog("❌ Failed to deduplicate drills: \(error)")
        }
    }
    
    func addDrill(_ drill: DrillItem) {
        let sdDrill = SDDrill.from(drill)
        modelContext.insert(sdDrill)
        // Attach any media items the caller pre-populated (e.g. a quick-add
        // drill that already has one photo). SDDrill.from() intentionally
        // skips media so we can insert children after the parent.
        for mediaStruct in drill.media {
            let sdMedia = SDDrillMedia.from(mediaStruct)
            sdMedia.drill = sdDrill
            modelContext.insert(sdMedia)
        }
        stampProvenanceOnCreate(sdDrill)
        saveAndRefresh()
    }

    func updateDrill(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
                recordDrillRevision(sdDrill, reason: .manualEdit)
                sdDrill.name = drill.name
                sdDrill.category = drill.category
                sdDrill.difficulty = drill.difficulty
                sdDrill.durationMinutes = drill.durationMinutes
                sdDrill.drillDescription = drill.description
                sdDrill.instructions = drill.instructions
                sdDrill.keyPoints = drill.keyPoints
                sdDrill.equipmentNeeded = drill.equipmentNeeded
                sdDrill.minPlayers = drill.minPlayers
                sdDrill.maxPlayers = drill.maxPlayers
                sdDrill.variations = drill.variations
                sdDrill.videoUrl = drill.videoUrl
                sdDrill.tags = drill.tags
                sdDrill.isFavorite = drill.isFavorite
                syncMedia(on: sdDrill, target: drill.media)
                sdDrill.updatedAt = Date()
                stampProvenanceOnEdit(sdDrill)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update drill: \(error)")
        }
    }

    /// Reconcile an SDDrill's `media` relationship with a struct-side target
    /// list. Updates rows in place where IDs match, inserts new rows, and
    /// deletes rows that disappeared. Binary files for deleted rows are also
    /// torn down so we don't leak photos in Documents/.
    private func syncMedia(on sdDrill: SDDrill, target: [DrillMedia]) {
        let existing = sdDrill.media ?? []
        let targetById = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })

        // Delete rows missing from the target.
        for sdMedia in existing where targetById[sdMedia.id] == nil {
            DrillMediaStorage.shared.delete(media: sdMedia.toStruct())
            modelContext.delete(sdMedia)
        }

        // Update existing rows in place.
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for mediaStruct in target {
            if let sdMedia = existingById[mediaStruct.id] {
                sdMedia.apply(mediaStruct)
            } else {
                let sdMedia = SDDrillMedia.from(mediaStruct)
                sdMedia.drill = sdDrill
                modelContext.insert(sdMedia)
            }
        }
    }
    
    func toggleDrillFavorite(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
                sdDrill.isFavorite.toggle()
                sdDrill.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to toggle drill favorite: \(error)")
        }
    }
    
    func deleteDrill(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
                // SwiftData cascades the SDDrillMedia rows; tear down the
                // binary files ourselves so we don't leak photos.
                DrillMediaStorage.shared.deleteAllMedia(drillId: drill.id)
                modelContext.delete(sdDrill)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete drill: \(error)")
        }
    }

    // MARK: - Drill Media CRUD
    /// Adds a single media item to a drill. The caller is responsible for
    /// having already persisted the binary asset via `DrillMediaStorage` and
    /// for setting `sortOrder` (typically to the count of existing media).
    func addDrillMedia(_ media: DrillMedia, toDrillId drillId: UUID) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drillId })
            guard let sdDrill = try modelContext.fetch(descriptor).first else { return }
            recordDrillRevision(sdDrill, reason: .manualEdit)
            let sdMedia = SDDrillMedia.from(media)
            sdMedia.drill = sdDrill
            modelContext.insert(sdMedia)
            sdDrill.updatedAt = Date()
            stampProvenanceOnEdit(sdDrill)
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to add drill media: \(error)")
        }
    }

    /// Updates a single media item in place (caption changes, reordering,
    /// etc.). Resolves by media ID.
    func updateDrillMedia(_ media: DrillMedia) {
        do {
            let descriptor = FetchDescriptor<SDDrillMedia>(predicate: #Predicate { $0.id == media.id })
            guard let sdMedia = try modelContext.fetch(descriptor).first else { return }
            if let sdDrill = sdMedia.drill {
                recordDrillRevision(sdDrill, reason: .manualEdit)
                sdDrill.updatedAt = Date()
                stampProvenanceOnEdit(sdDrill)
            }
            sdMedia.apply(media)
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to update drill media: \(error)")
        }
    }

    /// Deletes a single media item — removes both the SwiftData row and the
    /// binary files on disk.
    func deleteDrillMedia(_ media: DrillMedia) {
        do {
            let descriptor = FetchDescriptor<SDDrillMedia>(predicate: #Predicate { $0.id == media.id })
            guard let sdMedia = try modelContext.fetch(descriptor).first else { return }
            if let sdDrill = sdMedia.drill {
                recordDrillRevision(sdDrill, reason: .manualEdit)
                sdDrill.updatedAt = Date()
                stampProvenanceOnEdit(sdDrill)
            }
            DrillMediaStorage.shared.delete(media: media)
            modelContext.delete(sdMedia)
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to delete drill media: \(error)")
        }
    }

    /// One-shot migration: promotes legacy `DrillItem.videoUrl` strings into
    /// proper SDDrillMedia rows. Called from the cache refresh paths so it
    /// runs on first launch after the feature ships and then becomes a no-op
    /// (the migrated `videoUrl` is cleared).
    ///
    /// - Skips drills with empty `videoUrl`.
    /// - Skips drills whose `videoUrl` doesn't parse as YouTube (Instagram
    ///   videoUrls didn't exist; raw URLs would just be confusing).
    /// - Skips drills that already have a `.youtube` SDDrillMedia matching
    ///   the URL (avoids duplicates if the user already re-added it manually).
    /// - Kicks off thumbnail caching as a fire-and-forget Task so refresh
    ///   isn't blocked on network.
    private func migrateLegacyVideoUrls(in sdDrills: [SDDrill]) {
        var didMigrateAny = false
        var thumbnailJobs: [(URL, UUID, UUID)] = []  // (thumbURL, drillId, mediaId)

        for sdDrill in sdDrills {
            guard let raw = sdDrill.videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            guard case .youtube(_, let url) = DrillMediaURL.parse(raw) else {
                // Not a YouTube URL — just clear the legacy field; we don't
                // have an unstructured-link kind to store it under.
                sdDrill.videoUrl = nil
                didMigrateAny = true
                continue
            }
            let alreadyHasIt = (sdDrill.media ?? []).contains { existing in
                existing.kindRaw == DrillMediaKind.youtube.rawValue
                    && existing.remoteURL == url.absoluteString
            }
            if !alreadyHasIt {
                let mediaId = UUID()
                let sortOrder = (sdDrill.media ?? []).count
                let sdMedia = SDDrillMedia(
                    id: mediaId,
                    kind: .youtube,
                    localPath: nil,
                    remoteURL: url.absoluteString,
                    thumbnailPath: nil,
                    caption: nil,
                    sortOrder: sortOrder
                )
                sdMedia.drill = sdDrill
                modelContext.insert(sdMedia)

                if let parsed = DrillMediaURL.parse(url.absoluteString).thumbnailURL {
                    thumbnailJobs.append((parsed, sdDrill.id, mediaId))
                }
            }
            sdDrill.videoUrl = nil
            didMigrateAny = true
        }

        guard didMigrateAny else { return }
        do {
            try modelContext.save()
            debugLog("✅ Migrated \(thumbnailJobs.count) legacy videoUrl entries to DrillMedia")
        } catch {
            debugLog("❌ Legacy videoUrl migration save failed: \(error)")
        }

        // Backfill thumbnails in the background so the carousel tiles look
        // right without making refresh wait on network.
        #if os(iOS)
        guard !thumbnailJobs.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            for job in thumbnailJobs {
                guard let path = await DrillMediaStorage.shared.cacheRemoteThumbnail(
                    from: job.0, drillId: job.1, mediaId: job.2
                ) else { continue }
                await self?.attachBackfilledThumbnail(path: path, mediaId: job.2)
            }
        }
        #endif
    }

    #if os(iOS)
    /// Persists a thumbnail path onto an existing SDDrillMedia row, run from
    /// the migration's background backfill task. No-op if the row was deleted
    /// in the meantime.
    @MainActor
    private func attachBackfilledThumbnail(path: String, mediaId: UUID) {
        do {
            let descriptor = FetchDescriptor<SDDrillMedia>(predicate: #Predicate { $0.id == mediaId })
            guard let sdMedia = try modelContext.fetch(descriptor).first else { return }
            sdMedia.thumbnailPath = path
            sdMedia.updatedAt = Date()
            try modelContext.save()
            // Reflect into the cache so any open drill detail updates.
            refreshCachesSync()
        } catch {
            debugLog("⚠️ Backfill thumbnail attach failed: \(error)")
        }
    }
    #endif

    /// Rewrites `sortOrder` on every media row of a drill to match the order
    /// of the supplied ID list. IDs not in `orderedIds` are appended in their
    /// existing relative order.
    func reorderDrillMedia(forDrillId drillId: UUID, orderedIds: [UUID]) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drillId })
            guard let sdDrill = try modelContext.fetch(descriptor).first else { return }
            let all = sdDrill.media ?? []
            let indexById = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
            let tail = orderedIds.count
            var trailing = tail
            for sdMedia in all {
                if let idx = indexById[sdMedia.id] {
                    sdMedia.sortOrder = idx
                } else {
                    sdMedia.sortOrder = trailing
                    trailing += 1
                }
            }
            sdDrill.updatedAt = Date()
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to reorder drill media: \(error)")
        }
    }
    
    // MARK: - Court Scheme CRUD (in-memory for now)
    func addCourtScheme(_ scheme: CourtScheme) {
        courtSchemes.append(scheme)
        objectWillChange.send()
    }
    
    func updateCourtScheme(_ scheme: CourtScheme) {
        if let index = courtSchemes.firstIndex(where: { $0.id == scheme.id }) {
            courtSchemes[index] = scheme
            objectWillChange.send()
        }
    }
    
    func deleteCourtScheme(_ scheme: CourtScheme) {
        courtSchemes.removeAll { $0.id == scheme.id }
        objectWillChange.send()
    }
    
    func toggleCourtSchemeFavorite(_ scheme: CourtScheme) {
        if let index = courtSchemes.firstIndex(where: { $0.id == scheme.id }) {
            courtSchemes[index].isFavorite.toggle()
            objectWillChange.send()
        }
    }
    
    func schemesForDrill(_ drillId: UUID) -> [CourtScheme] {
        courtSchemes.filter { $0.drillId == drillId }
    }
    
    // MARK: - Play CRUD
    //
    // These used to mutate an in-memory array and nothing else, so every play a
    // coach authored was discarded at quit. They now write through to SDPlay.

    func addPlay(_ play: Play) {
        upsertPlay(play)
    }

    func updatePlay(_ play: Play) {
        upsertPlay(play)
    }

    private func upsertPlay(_ play: Play) {
        do {
            let pid = play.id
            let descriptor = FetchDescriptor<SDPlay>(predicate: #Predicate { $0.id == pid })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(play)
            } else {
                modelContext.insert(SDPlay.from(play))
            }
            try modelContext.save()
            reloadPlays()
        } catch {
            debugLog("❌ Failed to save play: \(error)")
        }
    }

    func deletePlay(_ play: Play) {
        do {
            let pid = play.id
            let descriptor = FetchDescriptor<SDPlay>(predicate: #Predicate { $0.id == pid })
            if let existing = try modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
                try modelContext.save()
            }
            reloadPlays()
        } catch {
            debugLog("❌ Failed to delete play: \(error)")
        }
    }

    func togglePlayFavorite(_ play: Play) {
        var updated = play
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        upsertPlay(updated)
    }

    // MARK: - Play Diagrams

    /// Saves a diagram, creating the owning SDPlay if it does not exist yet.
    ///
    /// The editor can open on a loose diagram, so the play row is created
    /// lazily on first save rather than requiring one up front.
    func savePlayDiagram(_ diagram: PlayDiagram, name: String) {
        do {
            let playId = diagram.playId
            let playDescriptor = FetchDescriptor<SDPlay>(predicate: #Predicate { $0.id == playId })
            if try modelContext.fetch(playDescriptor).first == nil {
                let play = SDPlay(id: playId, name: name, category: .setPlays)
                modelContext.insert(play)
            }

            let diagramId = diagram.id
            let descriptor = FetchDescriptor<SDPlayDiagram>(predicate: #Predicate { $0.id == diagramId })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = name
                existing.diagram = diagram
            } else {
                modelContext.insert(SDPlayDiagram(id: diagram.id, playId: playId,
                                                  name: name, diagram: diagram))
            }
            try modelContext.save()
            reloadPlays()
        } catch {
            debugLog("❌ Failed to save play diagram: \(error)")
        }
    }

    /// Writes playbook metadata onto the play that owns a diagram.
    ///
    /// Family lives in `formation` (the field the iOS UI already displays),
    /// the note in `playDescription`, and the thumbnail PATH in the legacy
    /// `diagramUrl` — bytes stay on disk, never in CloudKit.
    func updatePlayMetadata(playId: UUID,
                            name: String,
                            family: String,
                            tags: [String],
                            note: String,
                            thumbnailPath: String?) {
        do {
            let descriptor = FetchDescriptor<SDPlay>(predicate: #Predicate { $0.id == playId })
            guard let play = try modelContext.fetch(descriptor).first else { return }
            play.name = name
            play.formation = family
            play.tags = tags
            play.playDescription = note
            if let thumbnailPath { play.diagramUrl = thumbnailPath }
            // Family implies the closest category so iOS grouping stays sane.
            switch family {
            case "SLOB", "BLOB":   play.category = .outOfBounds
            case "Press Break":    play.category = .pressBreak
            default:               play.category = .setPlays
            }
            play.updatedAt = Date()
            try modelContext.save()
            reloadPlays()
        } catch {
            debugLog("❌ Failed to update play metadata: \(error)")
        }
    }

    /// Records a diagram as a variation of another.
    func setVariant(diagramId: UUID, variant: PlayVariant) {
        do {
            let descriptor = FetchDescriptor<SDPlayDiagram>(predicate: #Predicate { $0.id == diagramId })
            guard let row = try modelContext.fetch(descriptor).first else { return }
            row.variant = variant
            try modelContext.save()
        } catch {
            debugLog("❌ Failed to set variant: \(error)")
        }
    }

    /// All stored diagrams, most recently updated first.
    func allPlayDiagrams() -> [(id: UUID, name: String, updatedAt: Date, diagram: PlayDiagram)] {
        do {
            return try modelContext.fetch(FetchDescriptor<SDPlayDiagram>())
                .compactMap { row in
                    guard let diagram = row.diagram else { return nil }
                    return (row.id, row.name, row.updatedAt, diagram)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            debugLog("❌ Failed to load play diagrams: \(error)")
            return []
        }
    }

    func mostRecentPlayDiagram() -> PlayDiagram? {
        allPlayDiagrams().first?.diagram
    }

    func deletePlayDiagram(id: UUID) {
        do {
            let descriptor = FetchDescriptor<SDPlayDiagram>(predicate: #Predicate { $0.id == id })
            if let row = try modelContext.fetch(descriptor).first {
                modelContext.delete(row)
                try modelContext.save()
            }
        } catch {
            debugLog("❌ Failed to delete play diagram: \(error)")
        }
    }

    /// Refreshes the `plays` cache from the store.
    func reloadPlays() {
        do {
            plays = try modelContext.fetch(FetchDescriptor<SDPlay>()).map { $0.toStruct() }
            objectWillChange.send()
        } catch {
            debugLog("❌ Failed to load plays: \(error)")
        }
    }
    
    // MARK: - Contract CRUD

    /// No-op shim. The new model derives attended sessions from events on
    /// demand via `sessionsAttended(for:)`; nothing to enrich anymore.
    private func enriched(_ contract: Contract) -> Contract { contract }

    /// Legacy shim — old code calls this for non-bundle contracts to display
    /// "X sessions consumed". Maps to the new attendance counter.
    func sessionsConsumed(for contract: Contract) -> Int {
        sessionsAttended(for: contract)
    }

    /// Legacy shim. Bundles return remaining redemptions; everything else
    /// returns `Int.max` (used by sort-by-fewest-remaining).
    func sessionsRemaining(for contract: Contract) -> Int {
        contract.bundleRedemptionsRemaining ?? Int.max
    }

    /// Legacy alias for the new revenue accessor.
    var monthlyRevenue: Double { currentMonthCoachRevenue }

    // MARK: - Directory groups (Mac Contacts-style groups)

    /// Custom directory groups for one directory page, sorted for display.
    /// Fetched on demand rather than cached: the Mac directory is the only
    /// consumer and group counts are tiny.
    func directoryGroups(kind: String) -> [DirectoryGroupItem] {
        let descriptor = FetchDescriptor<SDDirectoryGroup>(
            predicate: #Predicate { $0.entityKind == kind },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map {
            DirectoryGroupItem(id: $0.id, name: $0.name, entityKind: $0.entityKind,
                               isSmart: $0.kindRaw == "smart",
                               memberIds: $0.memberIds, sortOrder: $0.sortOrder)
        }
    }

    @discardableResult
    func createDirectoryGroup(kind: String, name: String) -> UUID {
        let group = SDDirectoryGroup(name: name, entityKind: kind)
        modelContext.insert(group)
        try? modelContext.save()
        objectWillChange.send()
        return group.id
    }

    func renameDirectoryGroup(id: UUID, to name: String) {
        mutateDirectoryGroup(id: id) { $0.name = name }
    }

    func deleteDirectoryGroup(id: UUID) {
        let descriptor = FetchDescriptor<SDDirectoryGroup>(
            predicate: #Predicate { $0.id == id })
        if let group = try? modelContext.fetch(descriptor).first {
            modelContext.delete(group)
            try? modelContext.save()
            objectWillChange.send()
        }
    }

    /// Adds members (drag-in). Duplicates are ignored, order preserved.
    func addToDirectoryGroup(id: UUID, memberIds newMembers: [UUID]) {
        mutateDirectoryGroup(id: id) { group in
            var members = group.memberIds
            for member in newMembers where !members.contains(member) {
                members.append(member)
            }
            group.memberIds = members
        }
    }

    func removeFromDirectoryGroup(id: UUID, memberId: UUID) {
        mutateDirectoryGroup(id: id) { group in
            group.memberIds = group.memberIds.filter { $0 != memberId }
        }
    }

    // MARK: - Enrollment (ONE relation, both link fields in lockstep)

    /// Enrollment is stored twice — student.programId and
    /// program.enrolledStudentIds — and the two demonstrably drift in legacy
    /// data. This is THE enrollment writer: it sets the student's pointer,
    /// adds them to the target program's list, and removes them from every
    /// other program's list, so program→athletes and athlete→program can
    /// never disagree going forward. Pass nil to unenroll.
    func setStudentEnrollment(studentId: UUID, programId: UUID?) {
        do {
            let studentDescriptor = FetchDescriptor<SDStudent>(
                predicate: #Predicate { $0.id == studentId })
            guard let sdStudent = try modelContext.fetch(studentDescriptor).first else { return }
            recordStudentRevision(sdStudent, reason: .manualEdit)
            sdStudent.programId = programId
            sdStudent.updatedAt = Date()

            let programs = try modelContext.fetch(FetchDescriptor<SDProgram>())
            for sdProgram in programs {
                var enrolled = sdProgram.enrolledStudentIds
                let isTarget = sdProgram.id == programId
                let contains = enrolled.contains(studentId)
                if isTarget, !contains {
                    enrolled.append(studentId)
                } else if !isTarget, contains {
                    enrolled.removeAll { $0 == studentId }
                } else {
                    continue
                }
                sdProgram.enrolledStudentIds = enrolled
                sdProgram.updatedAt = Date()
            }
            saveAndRefresh()
        } catch {
            debugLog("❌ setStudentEnrollment failed: \(error)")
        }
    }

    private func mutateDirectoryGroup(id: UUID, _ body: (SDDirectoryGroup) -> Void) {
        let descriptor = FetchDescriptor<SDDirectoryGroup>(
            predicate: #Predicate { $0.id == id })
        guard let group = try? modelContext.fetch(descriptor).first else { return }
        body(group)
        group.updatedAt = Date()
        try? modelContext.save()
        objectWillChange.send()
    }

    func currentContract(for studentId: UUID) -> Contract? {
        cachedContracts
            .filter { $0.studentId == studentId }
            .sorted { $0.contractNumber > $1.contractNumber }
            .first
            .map { enriched($0) }
    }
    
    func allContracts(for studentId: UUID) -> [Contract] {
        cachedContracts
            .filter { $0.studentId == studentId }
            .sorted { $0.contractNumber < $1.contractNumber }
            .map { enriched($0) }
    }
    
    /// Get or create a default group contract for students without contracts.
    /// Group is the right default because it carries no money or expiry —
    /// the coach can promote it to a private kind explicitly when appropriate.
    func getOrCreateDefaultContract(for studentId: UUID) -> Contract {
        if let existing = currentContract(for: studentId) {
            return existing
        }
        let studentSessions = cachedSessionEvents.filter {
            $0.actualAttendeeIds.contains(studentId)
        }.sorted { $0.date < $1.date }
        let enrollmentDate = studentSessions.first?.date ?? Date()
        // Pick a program if the student is enrolled in any group program; nil otherwise.
        let firstGroupProgramId = cachedPrograms.first(where: {
            $0.programType != .privateSessions && $0.enrolledStudentIds.contains(studentId)
        })?.id
        let defaultContract = Contract(
            studentId: studentId,
            contractNumber: 1,
            kind: .group,
            enrollmentDate: enrollmentDate,
            pricePerSession: 0,
            programId: firstGroupProgramId,
            notes: "Auto-created tracking contract"
        )
        addContract(defaultContract)
        return defaultContract
    }

    /// One-time migration: promote any auto-created PAYG-with-zero-price
    /// contracts to `.group` so existing students stop showing PAYG / Weeks
    /// chrome. Safe to run on every launch — it's a no-op for non-default rows.
    func migrateLegacyAutoContractsToGroup() {
        var changed = 0
        for var contract in cachedContracts where contract.kind == .privatePayPerSession
                                                    && contract.pricePerSession == 0
                                                    && contract.bundleSessionIds.isEmpty {
            contract.kind = .group
            contract.programId = contract.programId ?? cachedPrograms.first(where: {
                $0.programType != .privateSessions && $0.enrolledStudentIds.contains(contract.studentId)
            })?.id
            updateContract(contract)
            changed += 1
        }
        if changed > 0 {
            debugLog("🔄 Migrated \(changed) legacy default contracts → group")
        }
    }
    
    /// Ensure all students have at least a default contract
    func ensureDefaultContractsForAllStudents() {
        var created = 0
        for student in cachedStudents {
            if currentContract(for: student.id) == nil {
                _ = getOrCreateDefaultContract(for: student.id)
                created += 1
            }
        }
        if created > 0 {
            debugLog("✅ Created \(created) default contracts for students without contracts")
        }
    }
    
    /// Sync contract's attendedSessionIds with actual session event attendance
    /// Call this to reconcile contracts with actual attendance records
    func syncContractAttendance(for studentId: UUID) {
        guard var contract = currentContract(for: studentId) else {
            debugLog("⚠️ syncContractAttendance: No contract found for student \(studentId)")
            return
        }
        
        // Get ALL sessions where this student is in actualAttendeeIds
        // If they're marked as attended, they attended - regardless of session status
        let attendedSessions = cachedSessionEvents.filter { event in
            event.actualAttendeeIds.contains(studentId)
        }
        
        debugLog("📊 syncContractAttendance for \(studentId): found \(attendedSessions.count) attended sessions")
        for session in attendedSessions {
            debugLog("   - Session: \(session.title), status: \(session.status.rawValue), date: \(session.date)")
        }
        
        // Update the contract's attended session IDs
        let newIds = attendedSessions.map { $0.id }
        if Set(newIds) != Set(contract.attendedSessionIds) {
            contract.attendedSessionIds = newIds
            updateContract(contract)
            debugLog("📊 Updated contract for student \(studentId): \(newIds.count) sessions")
        } else {
            debugLog("📊 Contract already up-to-date for student \(studentId): \(contract.attendedSessionIds.count) sessions")
        }
    }
    
    /// Sync all contracts with their actual attendance records
    func syncAllContractAttendance() {
        debugLog("📊 syncAllContractAttendance: Starting sync for \(cachedContracts.count) contracts")
        debugLog("📊 Total session events: \(cachedSessionEvents.count)")
        
        for contract in cachedContracts {
            syncContractAttendance(for: contract.studentId)
        }
        
        // Refresh caches after all updates
        refreshCachesSync()
        debugLog("📊 syncAllContractAttendance: Complete")
    }
    
    /// Get attended session details for a student's contract
    func attendedSessionDetails(for studentId: UUID) -> [SessionEvent] {
        guard let contract = currentContract(for: studentId) else { return [] }
        return cachedSessionEvents
            .filter { contract.attendedSessionIds.contains($0.id) }
            .sorted { $0.date > $1.date }
    }
    
    // MARK: - Contract CRUD (rebuilt for ContractKind model)

    func addContract(_ contract: Contract) {
        do {
            let cid = contract.id
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == cid })
            if let existing = try modelContext.fetch(descriptor).first {
                applyContract(contract, to: existing)
            } else {
                let sd = SDContract.from(contract)
                let sid = contract.studentId
                let studentDescriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == sid })
                sd.student = try modelContext.fetch(studentDescriptor).first
                modelContext.insert(sd)
            }
            try modelContext.save()
            autoEnrollGroupContract(contract)
            refreshCachesSync()
            invalidateContractCache()
            objectWillChange.send()
        } catch {
            debugLog("❌ Failed to add contract: \(error)")
        }
    }

    func updateContract(_ contract: Contract) {
        do {
            let cid = contract.id
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == cid })
            if let sd = try modelContext.fetch(descriptor).first {
                applyContract(contract, to: sd)
                try modelContext.save()
                autoEnrollGroupContract(contract)
                refreshCachesSync()
                invalidateContractCache()
                objectWillChange.send()
            } else {
                addContract(contract)
            }
        } catch {
            debugLog("❌ Failed to update contract: \(error)")
        }
    }

    private func applyContract(_ contract: Contract, to sd: SDContract) {
        sd.contractNumber = contract.contractNumber
        sd.kind = contract.kind
        sd.enrollmentDate = contract.enrollmentDate
        sd.pricePerSession = contract.pricePerSession
        sd.bundleSize = contract.bundleSize
        sd.bundlePurchaseDate = contract.bundlePurchaseDate
        sd.bundleSessionIds = contract.bundleSessionIds
        sd.payments = contract.payments
        sd.travelFeeAmount = contract.travelFeeAmount
        sd.travelFeeBasis = contract.travelFeeBasis
        sd.consents = contract.consents
        sd.sessionMinutes = contract.sessionMinutes
        sd.validityMonths = contract.validityMonths
        sd.programId = contract.programId
        sd.notes = contract.notes
        sd.manualStatus = contract.manualStatus
        sd.updatedAt = Date()
    }

    func deleteContract(_ contract: Contract) {
        do {
            let cid = contract.id
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == cid })
            if let sd = try modelContext.fetch(descriptor).first {
                modelContext.delete(sd)
                invalidateContractCache()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete contract: \(error)")
        }
    }

    /// For group contracts, ensure the student is also in the program's roster
    /// so that recurring sessions render the student.
    private func autoEnrollGroupContract(_ contract: Contract) {
        guard contract.kind == .group, let programId = contract.programId,
              var program = cachedPrograms.first(where: { $0.id == programId }) else { return }
        if !program.enrolledStudentIds.contains(contract.studentId) {
            program.enrolledStudentIds.append(contract.studentId)
            updateProgram(program)
        }
    }

    // MARK: - Contract creation helpers (factories)

    /// Build a new private pay-per-session contract.
    @discardableResult
    func createPrivatePAYG(for studentId: UUID, pricePerSession: Double) -> Contract {
        let next = (allContracts(for: studentId).map { $0.contractNumber }.max() ?? 0) + 1
        let contract = Contract(
            studentId: studentId,
            contractNumber: next,
            kind: .privatePayPerSession,
            enrollmentDate: Date(),
            pricePerSession: pricePerSession,
            createdByCoachId: loggedInCoachId
        )
        addContract(contract)
        return contract
    }

    /// Build a new private bundle contract. Defaults to 10 sessions.
    @discardableResult
    func createPrivateBundle(for studentId: UUID,
                             pricePerSession: Double,
                             bundleSize: Int = 10,
                             purchaseDate: Date = Date()) -> Contract {
        let next = (allContracts(for: studentId).map { $0.contractNumber }.max() ?? 0) + 1
        let contract = Contract(
            studentId: studentId,
            contractNumber: next,
            kind: .privateBundle,
            enrollmentDate: purchaseDate,
            pricePerSession: pricePerSession,
            bundleSize: bundleSize,
            bundlePurchaseDate: purchaseDate,
            createdByCoachId: loggedInCoachId
        )
        addContract(contract)
        return contract
    }

    /// Build a new group enrollment. No revenue tracked.
    @discardableResult
    func createGroupEnrollment(for studentId: UUID,
                               programId: UUID,
                               enrollmentDate: Date = Date()) -> Contract {
        let next = (allContracts(for: studentId).map { $0.contractNumber }.max() ?? 0) + 1
        let contract = Contract(
            studentId: studentId,
            contractNumber: next,
            kind: .group,
            enrollmentDate: enrollmentDate,
            programId: programId,
            createdByCoachId: loggedInCoachId
        )
        addContract(contract)
        return contract
    }

    // MARK: - Revenue (coach's pocket only)

    /// Coach revenue collected in the calendar month containing `monthStart`.
    /// Group contracts contribute zero (company billing).
    func coachRevenue(in monthStart: Date) -> Double {
        let cal = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: monthStart)
        guard let month = cal.date(from: comp),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: month) else { return 0 }

        var total: Double = 0
        for contract in cachedContracts {
            switch contract.kind {
            case .privatePayPerSession:
                let attendedThisMonth = cachedSessionEvents.filter { event in
                    event.date >= month && event.date < nextMonth
                        && event.actualAttendeeIds.contains(contract.studentId)
                        && eventIsPrivate(event)
                }.count
                total += Double(attendedThisMonth) * contract.pricePerSession
            case .privateBundle:
                let purchase = contract.effectiveBundlePurchaseDate
                if purchase >= month && purchase < nextMonth {
                    total += contract.bundleAmount
                }
            case .group:
                continue
            }
        }
        return total
    }

    /// Convenience: revenue for the current calendar month.
    var currentMonthCoachRevenue: Double {
        coachRevenue(in: Date())
    }

    // MARK: - Revenue events
    /// One discrete coach-revenue event: either a bundle purchase or a single
    /// pay-per-session attendance. Used to render the revenue history feed.
    struct RevenueEvent: Identifiable, Hashable {
        enum Kind: Hashable { case bundlePurchase, paygAttendance }
        let id: String
        let date: Date
        let amount: Double
        let kind: Kind
        let contractId: UUID
        let studentId: UUID
        let sessionEventId: UUID?
    }

    /// All revenue-producing events in a given calendar month.
    /// - PAYG: one event per attended private session (price = pricePerSession).
    /// - Bundle: one event per bundle whose purchase date falls in the month
    ///           (amount = pricePerSession × bundleSize).
    /// Group contracts contribute nothing.
    func revenueEvents(in monthStart: Date) -> [RevenueEvent] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        guard let month = cal.date(from: comps),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: month) else { return [] }

        var events: [RevenueEvent] = []

        for contract in cachedContracts {
            switch contract.kind {
            case .privatePayPerSession:
                let attended = cachedSessionEvents.filter { event in
                    event.date >= month && event.date < nextMonth
                        && event.actualAttendeeIds.contains(contract.studentId)
                        && eventIsPrivate(event)
                }
                for event in attended {
                    events.append(RevenueEvent(
                        id: "payg-\(contract.id)-\(event.id)",
                        date: event.date,
                        amount: contract.pricePerSession,
                        kind: .paygAttendance,
                        contractId: contract.id,
                        studentId: contract.studentId,
                        sessionEventId: event.id
                    ))
                }
            case .privateBundle:
                let purchase = contract.effectiveBundlePurchaseDate
                if purchase >= month && purchase < nextMonth {
                    events.append(RevenueEvent(
                        id: "bundle-\(contract.id)",
                        date: purchase,
                        amount: contract.bundleAmount,
                        kind: .bundlePurchase,
                        contractId: contract.id,
                        studentId: contract.studentId,
                        sessionEventId: nil
                    ))
                }
            case .group:
                continue
            }
        }
        return events.sorted { $0.date > $1.date }
    }

    /// Convenience: this calendar month's events.
    var currentMonthRevenueEvents: [RevenueEvent] {
        revenueEvents(in: Date())
    }

    /// Months (descending) for which we have any revenue activity, plus the
    /// current month even if empty.
    func revenueMonthsWithActivity(includeCurrentMonth: Bool = true,
                                   limit: Int = 24) -> [Date] {
        let cal = Calendar.current
        var months = Set<Date>()
        for contract in cachedContracts {
            switch contract.kind {
            case .privatePayPerSession:
                for event in cachedSessionEvents
                where event.actualAttendeeIds.contains(contract.studentId) && eventIsPrivate(event) {
                    if let m = cal.date(from: cal.dateComponents([.year, .month], from: event.date)) {
                        months.insert(m)
                    }
                }
            case .privateBundle:
                let purchase = contract.effectiveBundlePurchaseDate
                if let m = cal.date(from: cal.dateComponents([.year, .month], from: purchase)) {
                    months.insert(m)
                }
            case .group:
                continue
            }
        }
        if includeCurrentMonth,
           let now = cal.date(from: cal.dateComponents([.year, .month], from: Date())) {
            months.insert(now)
        }
        return months.sorted(by: >).prefix(limit).map { $0 }
    }

    /// Returns the last `count` calendar months descending, regardless of
    /// activity. Used by the revenue history scrubber so the coach can always
    /// peek at quiet months.
    func recentMonths(_ count: Int = 12) -> [Date] {
        let cal = Calendar.current
        guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        return (0..<count).compactMap { offset in
            cal.date(byAdding: .month, value: -offset, to: thisMonth)
        }
    }

    /// Revenue per month for the past `months` calendar months (newest first).
    func coachRevenueHistory(months: Int = 6) -> [(month: Date, amount: Double)] {
        let cal = Calendar.current
        let now = Date()
        return (0..<months).compactMap { offset -> (Date, Double)? in
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))
            else { return nil }
            return (monthStart, coachRevenue(in: monthStart))
        }
    }

    private func eventIsPrivate(_ event: SessionEvent) -> Bool {
        // Classic path: session is attached to a program of type .privateSessions.
        if let pid = event.programId,
           let program = cachedPrograms.first(where: { $0.id == pid }),
           program.programType == .privateSessions {
            return true
        }
        // Program-less private path: a 1:1 session created from the private
        // client / bundle scheduler. We treat it as private if any attendee has
        // an active private contract — bundle redemption and PAYG revenue then
        // attribute correctly without forcing the session into a group program.
        guard event.programId == nil else { return false }
        let attendees = Set(event.attendeeIds + event.actualAttendeeIds)
        guard !attendees.isEmpty else { return false }
        return cachedContracts.contains { contract in
            (contract.kind == .privateBundle || contract.kind == .privatePayPerSession)
                && contract.status == .active
                && attendees.contains(contract.studentId)
        }
    }

    // MARK: - Attendance counts

    /// Sessions the student actually attended on/after their enrollment date,
    /// optionally restricted to a single program.
    func sessionsAttended(for contract: Contract) -> Int {
        cachedSessionEvents.filter { event in
            guard event.date >= contract.enrollmentDate else { return false }
            if let pid = contract.programId, event.programId != pid { return false }
            return event.actualAttendeeIds.contains(contract.studentId)
        }.count
    }

    /// Group cross-check: sessions the company would charge the student for —
    /// completed, not cancelled, student didn't excuse themselves.
    func groupSessionsChargedByCompany(for contract: Contract) -> Int {
        guard contract.kind == .group, let programId = contract.programId else { return 0 }
        return cachedSessionEvents.filter { event in
            event.date >= contract.enrollmentDate
                && event.programId == programId
                && event.status == .completed
                && !event.excusedAbsences.contains(contract.studentId)
        }.count
    }

    // MARK: - Bundle redemption

    /// THE redemption authority. Every path that consumes a bundle session
    /// goes through here.
    ///
    /// FIFO by `effectiveBundlePurchaseDate`: a client who buys a second bundle
    /// before exhausting the first expects sessions consumed in purchase order.
    /// Charging the newest bundle would strand sessions she has already paid
    /// for. This replaces a second, divergent path in
    /// `updateContractsForAttendance` which selected by highest contract
    /// number and could charge a different bundle for the same session.
    ///
    /// A session is consumed when the student is PRESENT or recorded as an
    /// UNEXCUSED ABSENCE — agreement clause 4: cancellation inside 24 hours or
    /// non-attendance consumes the session. Excused and unmarked consume
    /// nothing.
    func redeemPrivateAttendance(sessionId: UUID, studentId: UUID) {
        guard let event = cachedSessionEvents.first(where: { $0.id == sessionId }),
              eventIsPrivate(event) else { return }

        let consumes = event.actualAttendeeIds.contains(studentId)
            || event.unexcusedAbsences.contains(studentId)
        guard consumes else { return }

        // Already charged somewhere? Don't double-charge.
        guard !cachedContracts.contains(where: {
            $0.studentId == studentId && $0.bundleSessionIds.contains(sessionId)
        }) else { return }

        let bundles = cachedContracts
            .filter { $0.studentId == studentId
                      && $0.kind == .privateBundle
                      && ($0.bundleRedemptionsRemaining ?? 0) > 0 }
            .sorted { $0.effectiveBundlePurchaseDate < $1.effectiveBundlePurchaseDate }

        guard var oldest = bundles.first else { return }
        oldest.bundleSessionIds.append(sessionId)
        updateContract(oldest)
    }

    // MARK: - Media Consent (student-level)

    /// Whether any of this student's contracts records an explicit grant for
    /// public publication.
    ///
    /// Consent lives on the contract because that is the document that captures
    /// it, but the question "may I publish this clip?" is asked about a
    /// STUDENT. Nil means never asked; false means declined. Only an explicit
    /// grant returns true, so unasked and declined both block publication.
    func publicationConsent(for studentId: UUID) -> Bool? {
        let states = cachedContracts
            .filter { $0.studentId == studentId }
            .sorted { $0.contractNumber > $1.contractNumber }
            .compactMap { $0.consentState(for: .publicPublication) }
        return states.first
    }

    /// Safe default: publication is allowed ONLY on an explicit grant.
    func mayPublishMedia(for studentId: UUID) -> Bool {
        publicationConsent(for: studentId) == true
    }

    /// Whether this session has already consumed one of the student's prepaid
    /// sessions. Drives whether a refund action is worth offering.
    func isSessionRedeemed(sessionId: UUID, studentId: UUID) -> Bool {
        cachedContracts.contains {
            $0.studentId == studentId && $0.bundleSessionIds.contains(sessionId)
        }
    }

    /// Explicitly return a consumed session to its bundle.
    ///
    /// This is a DELIBERATE undo, invoked by the coach when a session was
    /// charged in error — not a side effect of changing attendance state.
    /// It used to fire automatically from `markStudentAbsent`, which is how a
    /// no-show silently got its session refunded in contradiction of clause 4.
    /// Marking someone absent now consumes the session; only this action
    /// returns it.
    func refundSessionToBundle(sessionId: UUID, studentId: UUID) {
        for var contract in cachedContracts where contract.studentId == studentId
                                                && contract.kind == .privateBundle
                                                && contract.bundleSessionIds.contains(sessionId) {
            contract.bundleSessionIds.removeAll { $0 == sessionId }
            updateContract(contract)
        }
    }
    
    // MARK: - Measurement CRUD
    func addMeasurement(_ measurement: PlayerMeasurement) {
        let sdMeasurement = SDMeasurement.from(measurement)
        modelContext.insert(sdMeasurement)
        saveAndRefresh()
    }
    
    func addMeasurements(_ newMeasurements: [PlayerMeasurement]) {
        for measurement in newMeasurements {
            let sdMeasurement = SDMeasurement.from(measurement)
            modelContext.insert(sdMeasurement)
        }
        saveAndRefresh()
    }
    
    func measurements(for studentId: UUID) -> [PlayerMeasurement] {
        cachedMeasurements.filter { $0.studentId == studentId }
    }
    
    func measurementSummary(for studentId: UUID) -> MeasurementSummary {
        MeasurementSummary(studentId: studentId, measurements: cachedMeasurements)
    }
    
    // MARK: - Coach & Settings
    func updateCoach(_ updatedCoach: Coach) {
        do {
            let descriptor = FetchDescriptor<SDCoach>()
            if let sdCoach = try modelContext.fetch(descriptor).first {
                sdCoach.name = updatedCoach.name
                sdCoach.chineseName = updatedCoach.chineseName
                sdCoach.email = updatedCoach.email
                sdCoach.phone = updatedCoach.phone
                sdCoach.profileImageUrl = updatedCoach.profileImageUrl
                sdCoach.profileImageData = updatedCoach.profileImageData
                sdCoach.introduction = updatedCoach.introduction
                sdCoach.yearsOfExperience = updatedCoach.yearsOfExperience
                sdCoach.certifications = updatedCoach.certifications
                sdCoach.specializations = updatedCoach.specializations
                sdCoach.achievements = updatedCoach.achievements
                sdCoach.updatedAt = Date()
            } else {
                let sdCoach = SDCoach.from(updatedCoach)
                modelContext.insert(sdCoach)
            }
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to update coach: \(error)")
        }
    }
    
    func updateAppSettings(_ settings: AppSettings) {
        do {
            let descriptor = FetchDescriptor<SDAppSettings>()
            if let sdSettings = try modelContext.fetch(descriptor).first {
                sdSettings.notificationsEnabled = settings.notificationsEnabled
                sdSettings.sessionReminders = settings.sessionReminders
                sdSettings.reminderMinutesBefore = settings.reminderMinutesBefore
                sdSettings.darkModeEnabled = settings.darkModeEnabled
                sdSettings.hapticFeedbackEnabled = settings.hapticFeedbackEnabled
                sdSettings.autoSyncEnabled = settings.autoSyncEnabled
                sdSettings.language = settings.language
                sdSettings.currencyRawValue = settings.currency.rawValue
            } else {
                let sdSettings = SDAppSettings.from(settings)
                modelContext.insert(sdSettings)
            }
            saveAndRefresh()
        } catch {
            debugLog("❌ Failed to update settings: \(error)")
        }
    }
    
    var coachFirstName: String {
        let components = cachedCoach.name.split(separator: " ")
        if let firstName = components.first {
            return String(firstName)
        }
        return cachedCoach.name.isEmpty ? "Coach" : cachedCoach.name
    }
    
    // MARK: - Computed Properties
    func category(for id: UUID?) -> BasketballCategory? {
        guard let id = id else { return nil }
        return categories.first { $0.id == id }
    }
    
    func students(for categoryId: UUID) -> [Student] {
        cachedStudents.filter { $0.categoryId == categoryId }
    }
    
    func students(enrolledIn programId: UUID) -> [Student] {
        guard let program = cachedPrograms.first(where: { $0.id == programId }) else { return [] }
        return cachedStudents.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    var upcomingSessions: [SessionEvent] {
        cachedSessionEvents.filter { $0.isUpcoming }.sorted { $0.date < $1.date }
    }
    
    var recentSessions: [SessionEvent] {
        cachedSessionEvents.filter { $0.isPast }.sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }
    
    var activeStudentCount: Int { cachedStudents.count }

    // MARK: - Avatar warm-up
    /// Decode every student's profile photo into `ImageCacheManager` once on
    /// launch so rows render synchronously, with zero network access. Runs in
    /// the background; the UI is already up by the time we start.
    func warmAvatarCache() {
        let students = cachedStudents
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for student in students {
                let id = ImageCacheManager.studentImageId(student.id)
                // Already in memory? Skip.
                if await ImageCacheManager.shared.image(for: id) != nil { continue }
                // Inline thumbnail wins.
                if let data = student.thumbnailImageData,
                   let image = CacheImage(data: data) {
                    await MainActor.run {
                        ImageCacheManager.shared.cacheInMemory(image, for: id)
                    }
                    continue
                }
                // Full image on record — decode and also generate a thumbnail
                // so subsequent launches are instant from the inline field.
                if let data = student.profileImageData,
                   let image = CacheImage(data: data) {
                    await MainActor.run {
                        ImageCacheManager.shared.cacheInMemory(image, for: id)
                    }
                    if student.thumbnailImageData == nil,
                       let thumb = makeProfileThumbnailData(from: data) {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if var s = self.cachedStudents.first(where: { $0.id == student.id }),
                               s.thumbnailImageData == nil {
                                s.thumbnailImageData = thumb
                                self.updateStudent(s)
                            }
                        }
                    }
                    continue
                }
                // Legacy local file path — load via the cache so it lands on disk too.
                if let urlString = student.profileImageUrl, !urlString.isEmpty {
                    _ = await ImageCacheManager.shared.loadImage(for: id, from: urlString)
                }
            }
        }
    }

    var averageAttendanceRate: Double {
        let completedSessions = cachedSessionEvents.filter { $0.status == .completed }
        guard !completedSessions.isEmpty else { return 0 }
        return completedSessions.reduce(0) { $0 + $1.attendanceRate } / Double(completedSessions.count)
    }
    
    // MARK: - Sample Data for Guest Mode
    private let sampleDataLoadedKey = "sampleDataLoaded_v2"
    
    /// No-op: guest/demo mode is gone.
    func loadSampleDataIfNeeded() {}
    
    /// Clear sample data when user authenticates with an organization
    func clearSampleDataIfNeeded() {
        guard UserDefaults.standard.bool(forKey: sampleDataLoadedKey) else { return }
        
        debugLog("🧹 Clearing demo data after authentication...")
        
        // Remove sample data by checking for sample UUIDs (starting with 00000000-)
        let samplePrefix = "00000000-"
        
        // Clear sample sessions first (depend on phases/programs)
        for session in cachedSessionEvents where session.id.uuidString.hasPrefix(samplePrefix) {
            deleteSessionEvent(session)
        }
        
        // Clear sample phases
        for phase in cachedMicroCycles where phase.id.uuidString.hasPrefix(samplePrefix) {
            deleteMicroCycle(phase)
        }
        
        // Clear sample contracts
        for contract in cachedContracts where contract.id.uuidString.hasPrefix(samplePrefix) {
            deleteContract(contract)
        }
        
        // Clear sample programs
        for program in cachedPrograms where program.id.uuidString.hasPrefix(samplePrefix) {
            deleteProgram(program)
        }
        
        // Clear sample students
        for student in cachedStudents where student.id.uuidString.hasPrefix(samplePrefix) {
            deleteStudent(student)
        }
        
        // Clear sample staff coaches
        for staffCoach in staffCoaches where staffCoach.id.uuidString.hasPrefix(samplePrefix) {
            deleteStaffCoach(staffCoach)
        }
        
        // Clear sample teams
        for team in teams where team.id.uuidString.hasPrefix(samplePrefix) {
            deleteTeam(team)
        }
        
        // Clear sample games
        for game in games where game.id.uuidString.hasPrefix(samplePrefix) {
            deleteGame(game)
        }
        
        UserDefaults.standard.removeObject(forKey: sampleDataLoadedKey)
        debugLog("✅ Demo data cleared")
    }
    
    // MARK: - Single-Coach Access (no-op compatibility shims)
    var currentLoggedInCoach: StaffCoach? { nil }
    var isAdmin: Bool { true }
    var accessibleStudents: [Student] { cachedStudents }
    var accessiblePrograms: [Program] { cachedPrograms }
    var accessibleSessions: [SessionEvent] { cachedSessionEvents }
    var accessibleContracts: [Contract] { cachedContracts }
    var accessibleTeams: [Team] { teams }
    var accessibleGames: [Game] { games }
    
    // MARK: - Legacy Compatibility
    func saveAllToLocal() {
        // No-op for SwiftData - data is automatically persisted
        debugLog("💾 SwiftData auto-saves, no manual save needed")
    }
    
    func resetLoadState() {
        hasInitialized = false
    }
    
    /// DEPRECATED: Manual attendance tracking is no longer used
    /// Session consumption is now calculated from SessionEvent records via sessionsConsumed(for:)
    /// This function is kept for backward compatibility but does nothing
    @available(*, deprecated, message: "Session consumption is now event-based. Use sessionsConsumed(for:) instead.")
    func updateAttendedSessions(for studentId: UUID) {
        // No-op: Session consumption is now derived from SessionEvent records
        debugLog("⚠️ updateAttendedSessions is deprecated - session consumption is now event-based")
    }
    
    // MARK: - Team CRUD
    func addTeam(_ team: Team) {
        // Save to SwiftData
        let sdTeam = SDTeam.from(team)
        modelContext.insert(sdTeam)
        saveAndRefresh()
        
        // Initialize standing for new team
        let standing = TeamStanding(teamId: team.id)
        teamStandings.append(standing)
    }
    
    func updateTeam(_ team: Team) {
        do {
            let descriptor = FetchDescriptor<SDTeam>(predicate: #Predicate { $0.id == team.id })
            if let sdTeam = try modelContext.fetch(descriptor).first {
                sdTeam.name = team.name
                sdTeam.shortName = team.shortName
                sdTeam.colorHex = team.colorHex
                sdTeam.secondaryColorHex = team.secondaryColorHex
                sdTeam.logoSystemImage = team.logoSystemImage
                sdTeam.mascotTypeRaw = team.mascotTypeRaw
                sdTeam.playerIds = team.playerIds
                sdTeam.coachId = team.coachId
                sdTeam.coachName = team.coachName
                sdTeam.homeVenue = team.homeVenue
                sdTeam.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update team: \(error)")
        }
    }
    
    func deleteTeam(_ team: Team) {
        do {
            let descriptor = FetchDescriptor<SDTeam>(predicate: #Predicate { $0.id == team.id })
            if let sdTeam = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdTeam)
            }
            
            // Also delete games involving this team
            let gameDescriptor = FetchDescriptor<SDGame>(predicate: #Predicate { $0.homeTeamId == team.id || $0.awayTeamId == team.id })
            let sdGames = try modelContext.fetch(gameDescriptor)
            for sdGame in sdGames {
                modelContext.delete(sdGame)
            }
            
            saveAndRefresh()
            teamStandings.removeAll { $0.teamId == team.id }
        } catch {
            debugLog("❌ Failed to delete team: \(error)")
        }
    }
    
    // MARK: - Game CRUD
    func addGame(_ game: Game) {
        let sdGame = SDGame.from(game)
        modelContext.insert(sdGame)
        saveAndRefresh()
    }
    
    func updateGame(_ game: Game) {
        do {
            let descriptor = FetchDescriptor<SDGame>(predicate: #Predicate { $0.id == game.id })
            if let sdGame = try modelContext.fetch(descriptor).first {
                let oldStatus = sdGame.status
                
                sdGame.homeTeamId = game.homeTeamId
                sdGame.awayTeamId = game.awayTeamId
                sdGame.homeScore = game.homeScore
                sdGame.awayScore = game.awayScore
                sdGame.date = game.date
                sdGame.venue = game.venue
                sdGame.locationId = game.locationId
                sdGame.refereeId = game.refereeId
                sdGame.status = game.status
                sdGame.quarter = game.quarter
                sdGame.timeRemaining = game.timeRemaining
                sdGame.notes = game.notes
                sdGame.playerStats = game.playerStats
                sdGame.scoringPlays = game.scoringPlays
                sdGame.quarterScores = game.quarterScores
                sdGame.updatedAt = Date()
                
                // Also update in-memory games array immediately for UI responsiveness
                if let index = games.firstIndex(where: { $0.id == game.id }) {
                    games[index] = game
                }
                
                saveAndRefresh()
                
                // Update standings and season stats if game finished
                if oldStatus != .finished && game.status == .finished {
                    updateStandingsAfterGame(game)
                    updateSeasonStatsAfterGame(game)
                }
            }
        } catch {
            debugLog("❌ Failed to update game: \(error)")
        }
    }
    
    func deleteGame(_ game: Game) {
        do {
            let descriptor = FetchDescriptor<SDGame>(predicate: #Predicate { $0.id == game.id })
            if let sdGame = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdGame)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete game: \(error)")
        }
    }
    
    private func updateStandingsAfterGame(_ game: Game) {
        // Update home team standing
        if let homeIndex = teamStandings.firstIndex(where: { $0.teamId == game.homeTeamId }) {
            var standing = teamStandings[homeIndex]
            standing.pointsFor += game.homeScore
            standing.pointsAgainst += game.awayScore
            
            let homeWon = game.homeScore > game.awayScore
            if homeWon {
                standing.wins += 1
                standing.streak = standing.streak > 0 ? standing.streak + 1 : 1
            } else {
                standing.losses += 1
                standing.streak = standing.streak < 0 ? standing.streak - 1 : -1
            }
            
            // Update last 5 results
            standing.lastFiveResults.append(homeWon)
            if standing.lastFiveResults.count > 5 {
                standing.lastFiveResults.removeFirst()
            }
            
            teamStandings[homeIndex] = standing
        }
        
        // Update away team standing
        if let awayIndex = teamStandings.firstIndex(where: { $0.teamId == game.awayTeamId }) {
            var standing = teamStandings[awayIndex]
            standing.pointsFor += game.awayScore
            standing.pointsAgainst += game.homeScore
            
            let awayWon = game.awayScore > game.homeScore
            if awayWon {
                standing.wins += 1
                standing.streak = standing.streak > 0 ? standing.streak + 1 : 1
            } else {
                standing.losses += 1
                standing.streak = standing.streak < 0 ? standing.streak - 1 : -1
            }
            
            // Update last 5 results
            standing.lastFiveResults.append(awayWon)
            if standing.lastFiveResults.count > 5 {
                standing.lastFiveResults.removeFirst()
            }
            
            teamStandings[awayIndex] = standing
        }
    }
    
    // MARK: - Player Stats
    func addPlayerGameStats(_ stats: PlayerGameStats) {
        // Find the game and add stats
        if let gameIndex = games.firstIndex(where: { $0.id == stats.gameId }) {
            games[gameIndex].playerStats.append(stats)
        }
        
        // Update season stats
        updateSeasonStats(for: stats.playerId, with: stats)
    }
    
    private func updateSeasonStats(for playerId: UUID, with gameStats: PlayerGameStats) {
        if let index = seasonStats.firstIndex(where: { $0.playerId == playerId }) {
            var stats = seasonStats[index]
            stats.gamesPlayed += 1
            stats.totalPoints += gameStats.points
            stats.totalRebounds += gameStats.rebounds
            stats.totalAssists += gameStats.assists
            stats.totalSteals += gameStats.steals
            stats.totalBlocks += gameStats.blocks
            stats.totalTurnovers += gameStats.turnovers
            stats.totalMinutes += gameStats.minutesPlayed
            seasonStats[index] = stats
            
            // Sync to Student.personalBests for persistence
            syncSeasonStatsToStudent(playerId: playerId, stats: stats)
        } else {
            // Create new season stats
            let stats = SeasonStats(
                playerId: playerId,
                gamesPlayed: 1,
                totalPoints: gameStats.points,
                totalRebounds: gameStats.rebounds,
                totalAssists: gameStats.assists,
                totalSteals: gameStats.steals,
                totalBlocks: gameStats.blocks,
                totalTurnovers: gameStats.turnovers,
                totalMinutes: gameStats.minutesPlayed
            )
            seasonStats.append(stats)
            
            // Sync to Student.personalBests for persistence
            syncSeasonStatsToStudent(playerId: playerId, stats: stats)
        }
    }
    
    /// Update season stats for all players after a game finishes
    private func updateSeasonStatsAfterGame(_ game: Game) {
        for playerStat in game.playerStats {
            updateSeasonStats(for: playerStat.playerId, with: playerStat)
        }
        
        // Save league data to UserDefaults
        saveLeagueData()
        
        debugLog("📊 Updated season stats for \(game.playerStats.count) players and synced to student profiles")
    }
    
    /// Public method to update player season stats immediately when scoring (for live games)
    func updatePlayerSeasonStats(playerId: UUID, points: Int, rebounds: Int = 0, assists: Int = 0, steals: Int = 0, blocks: Int = 0) {
        if let index = seasonStats.firstIndex(where: { $0.playerId == playerId }) {
            // Update existing stats
            var stats = seasonStats[index]
            stats.totalPoints += points
            stats.totalRebounds += rebounds
            stats.totalAssists += assists
            stats.totalSteals += steals
            stats.totalBlocks += blocks
            seasonStats[index] = stats
            debugLog("📊 Updated season stats for player \(playerId): +\(points) pts (total: \(stats.totalPoints))")
            
            // Sync to Student.personalBests for persistence
            syncSeasonStatsToStudent(playerId: playerId, stats: stats)
        } else {
            // Create new season stats for this player
            let stats = SeasonStats(
                playerId: playerId,
                gamesPlayed: 1,
                totalPoints: points,
                totalRebounds: rebounds,
                totalAssists: assists,
                totalSteals: steals,
                totalBlocks: blocks,
                totalTurnovers: 0,
                totalMinutes: 0
            )
            seasonStats.append(stats)
            debugLog("📊 Created new season stats for player \(playerId): \(points) pts")
            
            // Sync to Student.personalBests for persistence
            syncSeasonStatsToStudent(playerId: playerId, stats: stats)
        }
        
        // Persist league data
        saveLeagueData()
        
        // Trigger UI update
        objectWillChange.send()
    }
    
    /// Sync SeasonStats to Student.personalBests for persistence
    /// playerId here is the Player.id, we need to find the studentId first
    private func syncSeasonStatsToStudent(playerId: UUID, stats: SeasonStats) {
        // Find the player to get studentId
        guard let player = players.first(where: { $0.id == playerId }) else {
            debugLog("⚠️ Could not find player with id \(playerId) for stats sync")
            return
        }
        
        // Find the student
        guard var student = students.first(where: { $0.id == player.studentId }) else {
            debugLog("⚠️ Could not find student for player \(playerId)")
            return
        }
        
        // Update personalBests on local copy
        student.personalBests["ppg"] = stats.ppg
        student.personalBests["rpg"] = stats.rpg
        student.personalBests["apg"] = stats.apg
        student.personalBests["spg"] = stats.spg
        student.personalBests["bpg"] = stats.bpg
        student.personalBests["totalPoints"] = Double(stats.totalPoints)
        student.personalBests["totalRebounds"] = Double(stats.totalRebounds)
        student.personalBests["totalAssists"] = Double(stats.totalAssists)
        student.personalBests["gamesPlayed"] = Double(stats.gamesPlayed)
        
        // Persist to SwiftData (this will also refresh the in-memory cache)
        updateStudent(student)
        
        debugLog("✅ Synced stats to student \(student.name): PPG=\(String(format: "%.1f", stats.ppg)), RPG=\(String(format: "%.1f", stats.rpg))")
    }
    
    /// Sync all season stats to their respective students (call on app launch or after bulk updates)
    func syncAllSeasonStatsToStudents() {
        for stats in seasonStats {
            syncSeasonStatsToStudent(playerId: stats.playerId, stats: stats)
        }
        debugLog("📊 Synced all \(seasonStats.count) player stats to student profiles")
    }
    
    // MARK: - Staff Coach CRUD
    func addStaffCoach(_ coach: StaffCoach) {
        let sdCoach = SDStaffCoach.from(coach)
        modelContext.insert(sdCoach)
        saveAndRefresh()
    }
    
    func updateStaffCoach(_ coach: StaffCoach) {
        do {
            let descriptor = FetchDescriptor<SDStaffCoach>(predicate: #Predicate { $0.id == coach.id })
            if let sdCoach = try modelContext.fetch(descriptor).first {
                sdCoach.name = coach.name
                sdCoach.chineseName = coach.chineseName
                sdCoach.email = coach.email
                sdCoach.phone = coach.phone
                sdCoach.role = coach.role
                sdCoach.specializations = coach.specializations
                sdCoach.ageGroups = coach.ageGroups
                sdCoach.avatarColor = coach.avatarColor
                sdCoach.isActive = coach.isActive
                sdCoach.hireDate = coach.hireDate
                sdCoach.notes = coach.notes
                sdCoach.profileImageData = coach.profileImageData
                sdCoach.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update staff coach: \(error)")
        }
    }
    
    func deleteStaffCoach(_ coach: StaffCoach) {
        do {
            let descriptor = FetchDescriptor<SDStaffCoach>(predicate: #Predicate { $0.id == coach.id })
            if let sdCoach = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdCoach)
                debugLog("🗑️ Deleting staff coach: \(coach.name)")
                saveAndRefresh()
                debugLog("✅ Staff coach deleted locally")
            } else {
                debugLog("⚠️ Staff coach not found in database: \(coach.name)")
                // Still refresh cache in case of sync issues
                refreshCachesSync()
            }
        } catch {
            debugLog("❌ Failed to delete staff coach: \(error)")
            // Still try to refresh cache
            refreshCachesSync()
        }
    }
    
    // MARK: - Location CRUD
    func addLocation(_ location: Location) {
        let sdLocation = SDLocation.from(location)
        modelContext.insert(sdLocation)
        saveAndRefresh()
    }
    
    func updateLocation(_ location: Location) {
        do {
            let descriptor = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == location.id })
            if let sdLocation = try modelContext.fetch(descriptor).first {
                sdLocation.name = location.name
                sdLocation.address = location.address
                sdLocation.city = location.city
                sdLocation.courtCount = location.courtCount
                sdLocation.courtType = location.courtType
                sdLocation.hasIndoor = location.hasIndoor
                sdLocation.amenities = location.amenities
                sdLocation.maxCapacity = location.maxCapacity
                sdLocation.contactPhone = location.contactPhone
                sdLocation.notes = location.notes
                sdLocation.isActive = location.isActive
                sdLocation.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update location: \(error)")
        }
    }
    
    func deleteLocation(_ location: Location) {
        do {
            let descriptor = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == location.id })
            if let sdLocation = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdLocation)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete location: \(error)")
        }
    }

    // MARK: - School CRUD
    func addSchool(_ school: School) {
        let sdSchool = SDSchool.from(school)
        modelContext.insert(sdSchool)
        saveAndRefresh()
    }

    func updateSchool(_ school: School) {
        do {
            let descriptor = FetchDescriptor<SDSchool>(predicate: #Predicate { $0.id == school.id })
            if let sdSchool = try modelContext.fetch(descriptor).first {
                sdSchool.name = school.name
                sdSchool.chineseName = school.chineseName
                sdSchool.contactName = school.contactName
                sdSchool.contactPhone = school.contactPhone
                sdSchool.contactEmail = school.contactEmail
                sdSchool.address = school.address
                sdSchool.notes = school.notes
                sdSchool.isActive = school.isActive
                sdSchool.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update school: \(error)")
        }
    }

    func deleteSchool(_ school: School) {
        do {
            // Detach the school from any programs that reference it so we
            // don't end up with dangling schoolIds. The programs themselves
            // remain (coach may want to keep history), they just lose the
            // school link and the .school programType.
            let affected = cachedPrograms.filter { $0.schoolId == school.id }
            for var program in affected {
                program.schoolId = nil
                if program.programType == .school {
                    program.programType = .group
                }
                program.updatedAt = Date()
                updateProgram(program)
            }

            let descriptor = FetchDescriptor<SDSchool>(predicate: #Predicate { $0.id == school.id })
            if let sdSchool = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdSchool)
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to delete school: \(error)")
        }
    }

    /// Look up a school by id (nil-tolerant for the optional `Program.schoolId`).
    func school(for id: UUID?) -> School? {
        guard let id = id else { return nil }
        return schools.first { $0.id == id }
    }

    // MARK: - Age Category CRUD
    func addAgeCategory(_ category: CustomAgeCategory) {
        // shortName (e.g. "U12") is the canonical identity for an age band.
        // Updating instead of appending prevents the duplicate-rows bug.
        if let index = ageCategories.firstIndex(where: { $0.shortName.uppercased() == category.shortName.uppercased() }) {
            ageCategories[index] = category
        } else {
            ageCategories.append(category)
        }
        saveAgeCategories()
    }

    func updateAgeCategory(_ category: CustomAgeCategory) {
        if let index = ageCategories.firstIndex(where: { $0.id == category.id }) {
            ageCategories[index] = category
        }
        saveAgeCategories()  // Persist locally
    }

    func deleteAgeCategory(_ category: CustomAgeCategory) {
        ageCategories.removeAll { $0.id == category.id }
        saveAgeCategories()  // Persist locally
    }

    /// No-op: age categories are stored locally; CloudKit handles sync automatically.
    func fetchAgeCategoriesFromCloud() async {
        // Intentionally no-op (kept for API compatibility).
    }
    
    /// Get the category color for a student based on their categoryId or age
    func categoryColor(for student: Student) -> Color {
        // First try to get color from assigned categoryId
        if let categoryId = student.categoryId,
           let category = ageCategories.first(where: { $0.id == categoryId }) {
            return category.color
        }
        
        // Otherwise, determine from student's age group
        if let ageGroup = student.ageGroup {
            return categoryColor(for: ageGroup)
        }
        
        // Default fallback
        return AppTheme.accentColor
    }
    
    /// Get the category color for an AgeGroup
    func categoryColor(for ageGroup: AgeGroup) -> Color {
        // Find matching category by shortName (U8, U10, etc.)
        let shortName = ageGroup.rawValue
        if let category = ageCategories.first(where: { $0.shortName.uppercased() == shortName.uppercased() }) {
            return category.color
        }
        
        // Fallback to default age group colors
        return Color.ageGroupColor(ageGroup)
    }
    
    /// Get the CustomAgeCategory for a student
    func ageCategory(for student: Student) -> CustomAgeCategory? {
        // First try categoryId
        if let categoryId = student.categoryId {
            return ageCategories.first { $0.id == categoryId }
        }
        
        // Otherwise match by age group
        if let ageGroup = student.ageGroup {
            let shortName = ageGroup.rawValue
            return ageCategories.first { $0.shortName.uppercased() == shortName.uppercased() }
        }
        
        return nil
    }
    
    // MARK: - Helper
    private func saveAndRefresh() {
        do {
            try modelContext.save()
            debugLog("✅ Data saved to SwiftData")
            
            // Synchronously refresh caches to ensure UI updates immediately
            refreshCachesSync()
            
            // CloudKit handles cross-device sync automatically; nothing else to do here.
            _ = isBatchMode
        } catch {
            debugLog("❌ Failed to save: \(error)")
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    /// Synchronous cache refresh for immediate UI updates after save
    private func refreshCachesSync() {
        defer {
            WidgetSnapshotWriter.scheduleWrite(dataManager: self)
            AttentionEngine.scheduleAutomation(dataManager: self)
        }
        do {
            let sdStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            cachedStudents = sdStudents.map { $0.toStruct() }
            
            let sdPlayers = try modelContext.fetch(FetchDescriptor<SDPlayer>())
            cachedPlayers = sdPlayers.map { $0.toStruct() }
            
            let sdContracts = try modelContext.fetch(FetchDescriptor<SDContract>())
            cachedContracts = sdContracts.map { $0.toStruct() }

            let sdPlays = try modelContext.fetch(FetchDescriptor<SDPlay>())
            plays = sdPlays.map { $0.toStruct() }
            
            let sdPrograms = try modelContext.fetch(FetchDescriptor<SDProgram>())
            cachedPrograms = sdPrograms.map { $0.toStruct() }
            
            let sdMicroCycles = try modelContext.fetch(FetchDescriptor<SDMicroCycle>())
            cachedMicroCycles = sdMicroCycles.map { $0.toStruct() }
            
            let sdSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            cachedSessionEvents = sdSessions.map { $0.toStruct() }

            let sdDrills = try modelContext.fetch(FetchDescriptor<SDDrill>())
            migrateLegacyVideoUrls(in: sdDrills)
            cachedDrills = sdDrills.map { $0.toStruct() }

            let sdMeasurements = try modelContext.fetch(FetchDescriptor<SDMeasurement>())
            cachedMeasurements = sdMeasurements.map { $0.toStruct() }
            
            let sdCoaches = try modelContext.fetch(FetchDescriptor<SDCoach>())
            if let sdCoach = sdCoaches.first {
                cachedCoach = sdCoach.toStruct()
            }
            
            let sdSettings = try modelContext.fetch(FetchDescriptor<SDAppSettings>())
            if let settings = sdSettings.first {
                cachedAppSettings = settings.toStruct()
            }
            
            // League data
            let sdTeams = try modelContext.fetch(FetchDescriptor<SDTeam>())
            teams = sdTeams.map { $0.toTeam() }
            
            let sdGames = try modelContext.fetch(FetchDescriptor<SDGame>())
            games = sdGames.map { $0.toGame() }
            
            // Organization data
            let sdStaffCoaches = try modelContext.fetch(FetchDescriptor<SDStaffCoach>())
            staffCoaches = sdStaffCoaches.map { $0.toStaffCoach() }
            
            let sdLocations = try modelContext.fetch(FetchDescriptor<SDLocation>())
            locations = sdLocations.map { $0.toLocation() }

            let sdSchools = try modelContext.fetch(FetchDescriptor<SDSchool>())
            schools = sdSchools.map { $0.toSchool() }

            debugLog("📊 Caches refreshed sync: \(cachedStudents.count) students, \(cachedPrograms.count) programs, \(teams.count) teams, \(staffCoaches.count) coaches, \(locations.count) locations, \(schools.count) schools")
            
            // Load reminders from UserDefaults
            loadReminders()
        } catch {
            debugLog("❌ Failed to refresh caches sync: \(error)")
        }
    }
    
    // MARK: - Reminders (SwiftData + CloudKit)
    
    /// Load reminders from SwiftData
    func loadReminders() {
        do {
            let sdReminders = try modelContext.fetch(FetchDescriptor<SDReminder>())
            let currentCoachId = loggedInCoachId ?? coach.id
            
            // Filter: own reminders OR reminders shared with me
            reminders = sdReminders
                .map { $0.toStruct() }
                .filter { $0.isVisibleTo(coachId: currentCoachId) }
                .sorted { $0.dueDate < $1.dueDate }
            
            debugLog("🔔 Loaded \(reminders.count) reminders from SwiftData")
        } catch {
            debugLog("❌ Failed to load reminders: \(error)")
        }
    }
    
    /// Add a new reminder (with sync)
    func addReminder(_ reminder: Reminder) {
        // Set coach IDs
        var newReminder = reminder
        let currentCoachId = loggedInCoachId ?? coach.id
        newReminder.coachId = currentCoachId
        newReminder.creatorCoachId = currentCoachId
        
        // Save to SwiftData
        let sdReminder = SDReminder.from(newReminder)
        modelContext.insert(sdReminder)
        
        do {
            try modelContext.save()
            reminders.append(newReminder)
            reminders.sort { $0.dueDate < $1.dueDate }
            debugLog("🔔 Reminder added: \(newReminder.title)")
        } catch {
            debugLog("❌ Failed to save reminder: \(error)")
        }
    }
    
    /// Update an existing reminder (with sync)
    func updateReminder(_ reminder: Reminder) {
        var updatedReminder = reminder
        updatedReminder.updatedAt = Date()
        
        // Update in SwiftData
        let descriptor = FetchDescriptor<SDReminder>(predicate: #Predicate { $0.id == reminder.id })
        if let sdReminder = try? modelContext.fetch(descriptor).first {
            sdReminder.update(from: updatedReminder)
            
            do {
                try modelContext.save()
                if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                    reminders[index] = updatedReminder
                    reminders.sort { $0.dueDate < $1.dueDate }
                }
                debugLog("🔔 Reminder updated: \(updatedReminder.title)")
            } catch {
                debugLog("❌ Failed to update reminder: \(error)")
            }
        }
    }
    
    /// Delete a reminder (with sync)
    func deleteReminder(_ reminder: Reminder) {
        let descriptor = FetchDescriptor<SDReminder>(predicate: #Predicate { $0.id == reminder.id })
        if let sdReminder = try? modelContext.fetch(descriptor).first {
            modelContext.delete(sdReminder)
            
            do {
                try modelContext.save()
                reminders.removeAll { $0.id == reminder.id }
                debugLog("🗑️ Reminder deleted: \(reminder.title)")
            } catch {
                debugLog("❌ Failed to delete reminder: \(error)")
            }
        }
    }
    
    /// Toggle reminder completion (with sync)
    func toggleReminderCompletion(_ reminder: Reminder) {
        var updated = reminder
        if updated.isCompleted {
            updated.uncomplete()
        } else {
            updated.complete()
        }
        updateReminder(updated)
    }
    
    /// CloudKit syncs reminders automatically; kept for API compatibility.
    func syncRemindersFromCloud() async {
        loadReminders()
    }

    /// CloudKit syncs reminders automatically; kept for API compatibility.
    func syncRemindersToCloud() async {
        // Intentionally no-op.
    }
    
    /// Get reminders for a specific session
    func reminders(for sessionId: UUID) -> [Reminder] {
        reminders.filter { $0.sessionId == sessionId && !$0.isCompleted }
    }
    
    /// Get today's reminders (for Today's Briefing) - includes shared
    var todayReminders: [Reminder] {
        let currentCoachId = loggedInCoachId ?? coach.id
        return reminders.filter { $0.isDueToday && !$0.isCompleted && $0.isVisibleTo(coachId: currentCoachId) }
    }
    
    /// Get upcoming reminders within 14 days (for Attention Required) - includes shared
    var upcomingReminders: [Reminder] {
        let currentCoachId = loggedInCoachId ?? coach.id
        return reminders.filter { $0.isDueSoon && !$0.isCompleted && !$0.isDueToday && $0.isVisibleTo(coachId: currentCoachId) }
    }
    
    /// Get overdue reminders - includes shared
    var overdueReminders: [Reminder] {
        let currentCoachId = loggedInCoachId ?? coach.id
        return reminders.filter { $0.isOverdue && $0.isVisibleTo(coachId: currentCoachId) }
    }
    
    /// Get all active (incomplete) reminders - includes shared
    var activeReminders: [Reminder] {
        let currentCoachId = loggedInCoachId ?? coach.id
        return reminders.filter { !$0.isCompleted && $0.isVisibleTo(coachId: currentCoachId) }
    }
    
    /// Get reminders shared with current coach by others
    var sharedWithMeReminders: [Reminder] {
        let currentCoachId = loggedInCoachId ?? coach.id
        return reminders.filter { $0.isSharedWith(coachId: currentCoachId) && !$0.isCompleted }
    }
}

// MARK: - Provenance & Revision History (Phase 1 of Export/Import)
//
// Foundation for the "About this athlete" footer and Version History sheet.
// Wires into the existing addStudent/updateStudent/addDrill/updateDrill paths
// to (a) stamp who-created/who-last-edited and (b) snapshot prior state into
// `SDEntityRevision` rows that the user can later restore from.

extension SwiftDataManager {

    // MARK: - Helpers

    /// Best-effort display name for the device-owner coach.
    /// Used as the actorLabel on revisions and the lastModifiedByCoachName stamp.
    var currentCoachLabel: String {
        let trimmed = cachedCoach.name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return isChinese ? "你" : "You"
    }

    /// Stamp create-time provenance on a freshly-inserted SDStudent.
    /// Safe to call multiple times — only fills nil fields.
    fileprivate func stampProvenanceOnCreate(_ s: SDStudent) {
        let now = Date()
        if s.createdByCoachId == nil { s.createdByCoachId = cachedCoach.id }
        if s.createdByCoachName == nil { s.createdByCoachName = currentCoachLabel }
        s.lastModifiedByCoachId = cachedCoach.id
        s.lastModifiedByCoachName = currentCoachLabel
        s.lastModifiedAt = now
    }

    fileprivate func stampProvenanceOnCreate(_ d: SDDrill) {
        let now = Date()
        if d.createdByCoachId == nil { d.createdByCoachId = cachedCoach.id }
        if d.createdByCoachName == nil { d.createdByCoachName = currentCoachLabel }
        d.lastModifiedByCoachId = cachedCoach.id
        d.lastModifiedByCoachName = currentCoachLabel
        d.lastModifiedAt = now
    }

    /// Stamp last-modified provenance on an in-place edit.
    fileprivate func stampProvenanceOnEdit(_ s: SDStudent) {
        s.lastModifiedByCoachId = cachedCoach.id
        s.lastModifiedByCoachName = currentCoachLabel
        s.lastModifiedAt = Date()
    }

    fileprivate func stampProvenanceOnEdit(_ d: SDDrill) {
        d.lastModifiedByCoachId = cachedCoach.id
        d.lastModifiedByCoachName = currentCoachLabel
        d.lastModifiedAt = Date()
    }

    // MARK: - Revision recording

    /// Snapshot the current state of a student into `SDEntityRevision`.
    /// Called from `updateStudent` BEFORE applying the new field values, and
    /// from the importer (Phase 3) before applying a bundle.
    /// The caller is responsible for the surrounding `saveAndRefresh()`.
    func recordStudentRevision(
        _ s: SDStudent,
        reason: RevisionReason,
        triggerBundleId: UUID? = nil,
        actorLabel: String? = nil
    ) {
        do {
            let snapshot = StudentSnapshotV1(s)
            let data = try JSONEncoder().encode(snapshot)
            let rev = SDEntityRevision(
                entityId: s.id,
                entityType: .student,
                reason: reason,
                triggerBundleId: triggerBundleId,
                snapshotData: data,
                actorLabel: actorLabel ?? currentCoachLabel
            )
            modelContext.insert(rev)
            pruneRevisions(forEntityId: s.id, entityType: .student)
        } catch {
            debugLog("❌ recordStudentRevision encode failed: \(error)")
        }
    }

    func recordDrillRevision(
        _ d: SDDrill,
        reason: RevisionReason,
        triggerBundleId: UUID? = nil,
        actorLabel: String? = nil
    ) {
        do {
            let snapshot = DrillSnapshotV1(d)
            let data = try JSONEncoder().encode(snapshot)
            let rev = SDEntityRevision(
                entityId: d.id,
                entityType: .drill,
                reason: reason,
                triggerBundleId: triggerBundleId,
                snapshotData: data,
                actorLabel: actorLabel ?? currentCoachLabel
            )
            modelContext.insert(rev)
            pruneRevisions(forEntityId: d.id, entityType: .drill)
        } catch {
            debugLog("❌ recordDrillRevision encode failed: \(error)")
        }
    }

    /// Bounded retention. Keep the last 10 revisions per entity, plus any
    /// import-tagged revision from the last 30 days so an import remains
    /// undoable for that window (Phase 4 wires Undo Import on top of this).
    private func pruneRevisions(forEntityId entityId: UUID, entityType: RevisionEntityType) {
        let keepCount = 10
        let bundleProtectedWindow: TimeInterval = 30 * 24 * 60 * 60
        let cutoff = Date().addingTimeInterval(-bundleProtectedWindow)
        let typeRaw = entityType.rawValue
        do {
            let descriptor = FetchDescriptor<SDEntityRevision>(
                predicate: #Predicate { $0.entityId == entityId && $0.entityTypeRaw == typeRaw },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let revisions = try modelContext.fetch(descriptor)
            for (index, rev) in revisions.enumerated() {
                if index < keepCount { continue }
                if rev.triggerBundleId != nil && rev.createdAt > cutoff { continue }
                modelContext.delete(rev)
            }
        } catch {
            debugLog("❌ pruneRevisions failed: \(error)")
        }
    }

    // MARK: - Read API (for views)

    /// Provenance for the student profile footer. Returns nil if no SDStudent
    /// exists for the given id (e.g. a legacy Student struct in cache only).
    func studentProvenance(for studentId: UUID) -> StudentProvenance? {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == studentId })
            guard let s = try modelContext.fetch(descriptor).first else { return nil }
            return StudentProvenance(
                createdByCoachId: s.createdByCoachId,
                createdByCoachName: s.createdByCoachName,
                createdAt: s.createdAt,
                lastModifiedByCoachId: s.lastModifiedByCoachId,
                lastModifiedByCoachName: s.lastModifiedByCoachName,
                lastModifiedAt: s.lastModifiedAt,
                originBundleId: s.originBundleId
            )
        } catch {
            return nil
        }
    }

    func drillProvenance(for drillId: UUID) -> DrillProvenance? {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drillId })
            guard let d = try modelContext.fetch(descriptor).first else { return nil }
            return DrillProvenance(
                createdByCoachId: d.createdByCoachId,
                createdByCoachName: d.createdByCoachName,
                createdAt: d.createdAt,
                lastModifiedByCoachId: d.lastModifiedByCoachId,
                lastModifiedByCoachName: d.lastModifiedByCoachName,
                lastModifiedAt: d.lastModifiedAt,
                originBundleId: d.originBundleId
            )
        } catch {
            return nil
        }
    }

    /// Revisions for the Version History sheet, newest first.
    func studentRevisionSummaries(for studentId: UUID) -> [EntityRevisionSummary] {
        revisionSummaries(forEntityId: studentId, entityType: .student)
    }

    func drillRevisionSummaries(for drillId: UUID) -> [EntityRevisionSummary] {
        revisionSummaries(forEntityId: drillId, entityType: .drill)
    }

    private func revisionSummaries(forEntityId entityId: UUID, entityType: RevisionEntityType) -> [EntityRevisionSummary] {
        let typeRaw = entityType.rawValue
        do {
            let descriptor = FetchDescriptor<SDEntityRevision>(
                predicate: #Predicate { $0.entityId == entityId && $0.entityTypeRaw == typeRaw },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map { rev in
                EntityRevisionSummary(
                    id: rev.id,
                    entityId: rev.entityId,
                    entityType: rev.entityType,
                    reason: rev.reason,
                    createdAt: rev.createdAt,
                    actorLabel: rev.actorLabel,
                    triggerBundleId: rev.triggerBundleId
                )
            }
        } catch {
            debugLog("❌ revisionSummaries fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Restore

    /// Restore a student to a prior revision. Snapshots the current state
    /// first (so the restore itself is undoable), applies the prior snapshot,
    /// stamps the lastModified provenance, and saves.
    /// Returns true if applied, false if the revision or student is missing.
    @discardableResult
    func restoreStudent(toRevisionId revisionId: UUID) -> Bool {
        do {
            let revDesc = FetchDescriptor<SDEntityRevision>(predicate: #Predicate { $0.id == revisionId })
            guard let rev = try modelContext.fetch(revDesc).first,
                  rev.entityType == .student else { return false }
            let snapshot = try JSONDecoder().decode(StudentSnapshotV1.self, from: rev.snapshotData)
            let entityId = rev.entityId
            let studentDesc = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == entityId })
            guard let sdStudent = try modelContext.fetch(studentDesc).first else { return false }
            recordStudentRevision(sdStudent, reason: .beforeRestore)
            snapshot.apply(to: sdStudent)
            stampProvenanceOnEdit(sdStudent)
            sdStudent.updatedAt = Date()
            saveAndRefresh()
            return true
        } catch {
            debugLog("❌ restoreStudent failed: \(error)")
            return false
        }
    }

    // MARK: - Sharing exclusion flag

    /// Read whether a student is currently flagged as excluded from export bundles.
    func isExcludedFromExport(studentId: UUID) -> Bool {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == studentId })
            return try modelContext.fetch(descriptor).first?.excludeFromExport ?? false
        } catch {
            return false
        }
    }

    /// Set whether a student is excluded from export bundles. Stamps the
    /// last-modified provenance fields too so the change is reflected in
    /// the "Last edited by" line on the profile.
    @discardableResult
    func setExcludedFromExport(studentId: UUID, _ value: Bool) -> Bool {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == studentId })
            guard let sd = try modelContext.fetch(descriptor).first else { return false }
            if sd.excludeFromExport != value {
                sd.excludeFromExport = value
                stampProvenanceOnEdit(sd)
                sd.updatedAt = Date()
                saveAndRefresh()
            }
            return true
        } catch {
            debugLog("❌ setExcludedFromExport failed: \(error)")
            return false
        }
    }

    @discardableResult
    func restoreDrill(toRevisionId revisionId: UUID) -> Bool {
        do {
            let revDesc = FetchDescriptor<SDEntityRevision>(predicate: #Predicate { $0.id == revisionId })
            guard let rev = try modelContext.fetch(revDesc).first,
                  rev.entityType == .drill else { return false }
            let snapshot = try JSONDecoder().decode(DrillSnapshotV1.self, from: rev.snapshotData)
            let entityId = rev.entityId
            let drillDesc = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == entityId })
            guard let sdDrill = try modelContext.fetch(drillDesc).first else { return false }
            recordDrillRevision(sdDrill, reason: .beforeRestore)
            snapshot.apply(to: sdDrill)
            stampProvenanceOnEdit(sdDrill)
            sdDrill.updatedAt = Date()
            saveAndRefresh()
            return true
        } catch {
            debugLog("❌ restoreDrill failed: \(error)")
            return false
        }
    }
}
