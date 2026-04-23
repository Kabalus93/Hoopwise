import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Async-safe Pending Uploads Tracker (Swift 6 compatible)
/// Actor to manage pending upload tracking without NSLock (deprecated in async contexts)
actor PendingUploadsTracker {
    private var pendingUploads = Set<UUID>()
    
    func insert(_ id: UUID) {
        pendingUploads.insert(id)
    }
    
    func remove(_ id: UUID) {
        pendingUploads.remove(id)
    }
    
    func contains(_ id: UUID) -> Bool {
        pendingUploads.contains(id)
    }
    
    func count() -> Int {
        pendingUploads.count
    }
    
    func getAll() -> Set<UUID> {
        pendingUploads
    }
}

/// Type alias for backward compatibility - views using DataManager will now use SwiftDataManager
typealias DataManager = SwiftDataManager

/// SwiftData-based data manager that provides the same interface as the legacy DataManager
/// but uses SwiftData for persistence instead of UserDefaults
@MainActor
class SwiftDataManager: ObservableObject {
    static let shared = SwiftDataManager()
    
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
    
    /// Track IDs of items currently being uploaded to prevent premature deletion
    /// Using actor for Swift 6 async-safe access (NSLock.lock/unlock deprecated in async contexts)
    private let pendingUploadsTracker = PendingUploadsTracker()
    
    // MARK: - Batch Mode for AI Generation
    /// Begin batch mode to prevent fullSync on every save
    func beginBatchMode() {
        isBatchMode = true
        debugLog("📦 Batch mode started - fullSync disabled")
    }
    
    /// End batch mode and trigger a single fullSync AFTER uploads complete
    func endBatchModeAndSync() {
        isBatchMode = false
        debugLog("📦 Batch mode ended - waiting for uploads to complete before sync")
        
        if SupabaseManager.shared.isConnected {
            Task {
                // Wait for all pending uploads to complete before syncing
                var waitCount = 0
                while waitCount < 600 { // Max 60 seconds wait
                    let pendingCount = await pendingUploadsTracker.count()

                    if pendingCount == 0 {
                        debugLog("  ✅ All uploads complete - now safe to sync")
                        break
                    }

                    if waitCount % 10 == 0 { // Log every second
                        debugLog("  ⏳ Waiting for \(pendingCount) uploads to complete...")
                    }

                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    waitCount += 1
                }

                // If we hit the timeout, uploads are still in-flight. Pulling from cloud
                // now could treat those un-confirmed records as deleted. Skip and let
                // the auto-sync loop handle it once uploads settle.
                let timedOut = waitCount >= 600
                if timedOut {
                    debugLog("  ⚠️ Batch-mode upload wait timed out — skipping syncFromCloud to avoid race with pending uploads")
                    return
                }

                // All uploads confirmed — safe to pull cloud changes
                await syncFromCloud()
            }
        }
    }
    
    // MARK: - Authentication State
    @Published var isLoggedIn = false
    @Published var loggedInCoachId: UUID?
    @Published var hasSkippedLogin = false
    
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
    
    /// Active staff coaches only (filtered by current organization)
    var activeStaffCoaches: [StaffCoach] {
        staffCoaches.filter { coach in
            guard coach.isActive else { return false }
            // If we have an organization, only show coaches belonging to it
            if let orgId = currentOrganizationId {
                return coach.organizationId == orgId
            }
            // In guest mode, show all coaches (including sample data)
            return true
        }
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
    /// Cached sessions remaining per contract ID — avoids O(n) session filtering per call
    private var _sessionsRemainingCache: [UUID: Int]?
    
    /// Get contracts indexed by student ID for fast lookups
    var contractsByStudentId: [UUID: Contract] {
        if let cached = _contractsByStudentId { return cached }
        let dict = Dictionary(cachedContracts.map { ($0.studentId, $0) }, uniquingKeysWith: { first, _ in first })
        _contractsByStudentId = dict
        return dict
    }
    
    /// Get cached sessions remaining for a contract (O(1) after first build)
    func cachedSessionsRemaining(for contract: Contract) -> Int {
        if let cache = _sessionsRemainingCache, let val = cache[contract.id] {
            return val
        }
        // Build the entire cache once
        var cache: [UUID: Int] = [:]
        for c in cachedContracts {
            cache[c.id] = sessionsRemaining(for: c)
        }
        _sessionsRemainingCache = cache
        return cache[contract.id] ?? sessionsRemaining(for: contract)
    }
    
    /// Invalidate contract cache (call when contracts change)
    func invalidateContractCache() {
        _contractsByStudentId = nil
        _sessionsRemainingCache = nil
    }
    
    // MARK: - Performance: Active Contracts Count
    var activeContractsCount: Int {
        cachedContracts.filter { $0.status == .active }.count
    }
    
    // MARK: - Performance: Students Needing Attention
    var studentsNeedingAttentionCount: Int {
        cachedStudents.filter { student in
            let contract = contractsByStudentId[student.id]
            let remaining = contract.map { cachedSessionsRemaining(for: $0) } ?? 0
            return remaining <= 3
        }.count
    }
    
    // MARK: - Performance: High Risk Students Count
    var highRiskStudentsCount: Int {
        cachedStudents.filter { student in
            let contract = contractsByStudentId[student.id]
            let remaining = contract.map { cachedSessionsRemaining(for: $0) } ?? 0
            let noRecentContact = student.lastParentContact == nil ||
                Calendar.current.dateComponents([.day], from: student.lastParentContact!, to: Date()).day ?? 0 > 30
            return remaining <= 2 || (remaining <= 5 && noRecentContact)
        }.count
    }
    
    // MARK: - Event-Based Session Consumption
    
    /// Calculate sessions consumed from completed SessionEvent records
    /// A session is consumed if: student attended OR (was expected but absent and not excused)
    func sessionsConsumed(for contract: Contract) -> Int {
        // Pay-as-you-go contracts don't track session consumption
        guard !contract.isPayAsYouGo else { return 0 }
        
        let fromEvents = cachedSessionEvents.filter { event in
            // Count completed and in-progress sessions (attendance is recorded during in-progress)
            guard event.status == .completed || event.status == .inProgress else { return false }
            
            // Session must belong to a program in the contract's assignments
            guard let programId = event.programId else { return false }
            
            // If contract has no program assignments, use fallback (count all sessions for this student)
            let matchesProgram = contract.programAssignments.isEmpty || contract.programAssignments.contains(programId)
            guard matchesProgram else { return false }
            
            let wasExpected = event.attendeeIds.contains(contract.studentId)
            let attended = event.actualAttendeeIds.contains(contract.studentId)
            let wasExcused = event.excusedAbsences.contains(contract.studentId)
            
            // Consumed if: attended OR (expected but didn't attend and wasn't excused)
            return attended || (wasExpected && !attended && !wasExcused)
        }.count
        
        return contract.historicalSessionsConsumed + fromEvents
    }
    
    /// Calculate remaining sessions for a contract using event-based consumption
    func sessionsRemaining(for contract: Contract) -> Int {
        guard !contract.isPayAsYouGo else { return Int.max } // Unlimited for pay-as-you-go
        return max(0, contract.totalSessions - sessionsConsumed(for: contract))
    }
    
    // Categories (static, not stored in SwiftData)
    var categories: [BasketballCategory] = BasketballCategory.samples
    var plays: [Play] = []
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
    @Published var ageCategories: [CustomAgeCategory] = CustomAgeCategory.defaults
    
    // Court schemes for Basketball Lab
    @Published var courtSchemes: [CourtScheme] = []
    
    // Reminders (persisted in SwiftData)
    @Published var reminders: [Reminder] = []
    
    private var isFullSyncInProgress = false
    
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
    // Each platform (iOS/macOS) has its own local storage - Supabase is the sync mechanism
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
            SDMeasurement.self,
            SDCoach.self,
            SDAppSettings.self,
            SDTeam.self,
            SDGame.self,
            SDStaffCoach.self,
            SDLocation.self,
            SDReminder.self
        ])
        
        // Use platform-specific local storage
        // iOS and macOS each have their own local data store
        // Supabase cloud sync is the single source of truth for cross-platform data sharing
        let modelConfiguration: ModelConfiguration
        
        if let storeURL = Self.getLocalStorageURL() {
            #if os(macOS)
            debugLog("📁 [macOS] Using local storage at: \(storeURL.path)")
            #else
            debugLog("📁 [iOS] Using local storage at: \(storeURL.path)")
            #endif
            debugLog("   ℹ️ Supabase is the source of truth for cross-platform sync")
            
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true
            )
        } else {
            // Fallback: use default SwiftData storage
            debugLog("⚠️ Could not determine storage location, using SwiftData default")
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
        }
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            debugLog("✅ SwiftData ModelContainer initialized")
        } catch {
            fatalError("❌ Failed to create ModelContainer: \(error)")
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
        
        // Backfill organizationId on any SDStudent records saved before this field was stamped
        // This fixes students added while AuthManager hadn't yet loaded the org
        backfillStudentOrganizationIds()
        
        // Run one-time migrations
        migrateSessionDurationsTo30()
        
        // Sync sample drills (adds any new drills from DrillItem.samples)
        syncSampleDrills()
        
        // Clean up any duplicate drills (one-time cleanup + prevention)
        deduplicateDrills()
        
        // Mark loading complete immediately after local data loads
        // This ensures UI is responsive right away
        isLoading = false
        
        debugLog("✅ Local data loaded: \(cachedStudents.count) students, \(cachedPrograms.count) programs")
        
        // Ensure all students have at least a default tracking contract
        ensureDefaultContractsForAllStudents()
        
        // Sync all contracts with actual attendance records (one-time reconciliation)
        syncAllContractAttendance()
        
        // PERFORMANCE: Run cloud sync in background (non-blocking)
        // This prevents the app from feeling slow on startup
        if SupabaseManager.shared.isConnected {
            backgroundSyncTask?.cancel()
            backgroundSyncTask = Task { [weak self] in
                guard let self = self else { return }
                
                // Small delay to let UI settle first
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                guard !Task.isCancelled else { return }
                
                debugLog("☁️ Background sync from Supabase starting...")
                self.isSyncing = true
                
                await self.syncFromCloud()
                await self.refreshAllCaches()
                
                self.isSyncing = false
                self.lastSyncDate = Date()
                debugLog("✅ Background cloud sync completed")
            }
        } else {
            debugLog("⚠️ Supabase not connected - using local data only")
        }
        
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
    
    /// Preload student images in batches to avoid memory spikes
    private func preloadStudentImages() async {
        let students = await MainActor.run { self.cachedStudents }
        let batchSize = 10
        
        for batch in stride(from: 0, to: students.count, by: batchSize) {
            let end = min(batch + batchSize, students.count)
            let batchStudents = Array(students[batch..<end])
            
            for student in batchStudents {
                guard let url = student.profileImageUrl, !url.isEmpty else { continue }
                let cacheId = ImageCacheManager.studentImageId(student.id)
                _ = await ImageCacheManager.shared.loadImage(for: cacheId, from: url)
            }
            
            // Small delay between batches to avoid memory pressure
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        debugLog("🖼️ Preloaded \(students.filter { $0.profileImageUrl != nil }.count) student images")
    }
    
    /// Cancel any ongoing background sync
    func cancelBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        isSyncing = false
    }
    
    /// Force a manual sync from cloud
    func forceCloudSync() async {
        guard SupabaseManager.shared.isConnected else {
            debugLog("⚠️ Cannot sync - Supabase not connected")
            return
        }
        
        isSyncing = true
        debugLog("🔄 Force syncing from Supabase...")
        
        await syncFromCloud()
        await refreshAllCaches()
        
        isSyncing = false
        lastSyncDate = Date()
        debugLog("✅ Force sync completed")
    }
    
    // MARK: - Refresh Caches
    func refreshAllCaches() async {
        do {
            // Fetch all SwiftData models and convert to structs
            let sdStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            cachedStudents = sdStudents.map { $0.toStruct() }
            
            let sdPlayers = try modelContext.fetch(FetchDescriptor<SDPlayer>())
            cachedPlayers = sdPlayers.map { $0.toStruct() }
            
            let sdContracts = try modelContext.fetch(FetchDescriptor<SDContract>())
            cachedContracts = sdContracts.map { $0.toStruct() }
            
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

            // Load persisted season stats from UserDefaults
            loadLeagueData()
            
            debugLog("📊 Caches refreshed: \(cachedStudents.count) students, \(cachedPrograms.count) programs, \(teams.count) teams, \(staffCoaches.count) coaches, \(locations.count) locations")
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
            ageCategories = decoded
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
                
                // Sync to cloud if connected
                if SupabaseManager.shared.isConnected {
                    Task {
                        await syncToCloud()
                    }
                }
                
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
                totalSessions: 24,
                attendedSessions: Int.random(in: 0...18),
                startDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()),
                expiryDate: Calendar.current.date(byAdding: .month, value: 4, to: Date()),
                pricePerSession: 200,
                totalAmount: 4800,
                amountPaid: Bool.random() ? 4800 : 2400,
                isSigned: true
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
    
    // MARK: - Organization Filtering
    /// Get the current organization ID for filtering data.
    /// Primary: AuthManager. Fallback: derive from any local record that already has an orgId.
    /// This ensures sync works even if AuthManager session wasn't restored yet.
    private var currentOrganizationId: UUID? {
        if let authOrgId = AuthManager.shared.currentOrganization?.id {
            return authOrgId
        }
        // Fallback: derive from local data (students or sessions that were stamped before)
        if let orgId = _cachedFallbackOrgId {
            return orgId
        }
        // Try to find an orgId from any local record
        let derivedOrgId: UUID? = {
            if let sd = (try? modelContext.fetch(FetchDescriptor<SDStudent>()))?.first(where: { $0.organizationId != nil }) {
                return sd.organizationId
            }
            if let se = (try? modelContext.fetch(FetchDescriptor<SDSessionEvent>()))?.first(where: { $0.organizationId != nil }) {
                return se.organizationId
            }
            return nil
        }()
        if let derivedOrgId {
            _cachedFallbackOrgId = derivedOrgId
            debugLog("🔧 [ORG-FALLBACK] Derived organizationId from local data: \(derivedOrgId)")
        }
        return derivedOrgId
    }
    /// Cache the fallback org ID so we don't re-query every time
    private var _cachedFallbackOrgId: UUID?
    
    /// Fetch data from Supabase filtered by organization
    /// Also includes legacy data where organization_id is null
    private func fetchForOrganization<T: Decodable>(from table: String) async throws -> [T] {
        if let orgId = currentOrganizationId {
            // Fetch items matching organization only (strict org isolation)
            let url = "\(SupabaseConfig.url)/rest/v1/\(table)?organization_id=eq.\(orgId.uuidString)"
            
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "GET"
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let formatter1 = ISO8601DateFormatter()
                formatter1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let formatter2 = ISO8601DateFormatter()
                formatter2.formatOptions = [.withInternetDateTime]
                
                if let date = formatter1.date(from: dateString) ?? formatter2.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.serverError(httpResponse.statusCode, errorMessage)
            }
            
            return try decoder.decode([T].self, from: data)
        } else {
            // No organization - return empty (new users see no data)
            return []
        }
    }
    
    // Debug version to see raw response
    private func fetchForOrganizationWithDebug<T: Decodable>(from table: String) async throws -> [T] {
        if let orgId = currentOrganizationId {
            let url = "\(SupabaseConfig.url)/rest/v1/\(table)?organization_id=eq.\(orgId.uuidString)"
            debugLog("🔍 DEBUG: Fetching from URL: \(url)")
            
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "GET"
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log raw response
            if let rawString = String(data: data, encoding: .utf8) {
                debugLog("🔍 DEBUG: Raw response (first 500 chars): \(String(rawString.prefix(500)))")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            
            debugLog("🔍 DEBUG: HTTP Status: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.serverError(httpResponse.statusCode, errorMessage)
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let formatter1 = ISO8601DateFormatter()
                formatter1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let formatter2 = ISO8601DateFormatter()
                formatter2.formatOptions = [.withInternetDateTime]
                
                if let date = formatter1.date(from: dateString) ?? formatter2.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            do {
                let result = try decoder.decode([T].self, from: data)
                debugLog("🔍 DEBUG: Successfully decoded \(result.count) items")
                return result
            } catch {
                debugLog("🔍 DEBUG: Decoding error: \(error)")
                throw error
            }
        } else {
            debugLog("🔍 DEBUG: No organization ID set")
            return []
        }
    }
    
    // MARK: - Cloud Sync
    func syncFromCloud() async {
        guard SupabaseManager.shared.isConnected else {
            debugLog("⚠️ Not connected to Supabase - skipping cloud sync")
            return
        }
        
        // Skip sync if no organization is set
        guard currentOrganizationId != nil else {
            debugLog("⚠️ No organization set - skipping cloud sync")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        debugLog("☁️ Starting sync from cloud for organization: \(AuthManager.shared.currentOrganization?.displayName ?? "Unknown")...")
        var syncErrors: [String] = []
        let syncLog = SyncLogStore.shared
        var newStudents = 0, newPlayers = 0, newContracts = 0, newPrograms = 0
        var newCycles = 0, newSessions = 0, newCoaches = 0, newLocations = 0
        
        // One-time: purge sample data rows (00000000- prefix UUIDs) from all tables
        await purgeSampleDataFromCloud()
        
        // Sync Students
        do {
            let cloudStudents: [SupabaseStudent] = try await fetchForOrganization(from: "students")
            let existingStudentIds = Set((try? modelContext.fetch(FetchDescriptor<SDStudent>()))?.map { $0.id } ?? [])
            for cloudStudent in cloudStudents {
                let isNew = !existingStudentIds.contains(cloudStudent.id)
                await mergeStudent(cloudStudent.toStudent())
                if isNew { newStudents += 1 }
            }
            debugLog("  ✓ Synced \(cloudStudents.count) students from cloud (\(newStudents) new)")
        } catch {
            debugLog("  ✗ Failed to sync students: \(error)")
            syncErrors.append("students: \(error.localizedDescription)")
        }
        
        // Sync Players
        do {
            let cloudPlayers: [SupabasePlayer] = try await fetchForOrganization(from: "players")
            let existingPlayerIds = Set((try? modelContext.fetch(FetchDescriptor<SDPlayer>()))?.map { $0.id } ?? [])
            for cloudPlayer in cloudPlayers {
                let isNew = !existingPlayerIds.contains(cloudPlayer.id)
                await mergePlayer(cloudPlayer.toPlayer())
                if isNew { newPlayers += 1 }
            }
            debugLog("  ✓ Synced \(cloudPlayers.count) players from cloud (\(newPlayers) new)")
        } catch {
            debugLog("  ✗ Failed to sync players: \(error)")
            syncErrors.append("players: \(error.localizedDescription)")
        }
        
        // Sync Contracts (including deletions)
        do {
            let cloudContracts: [SupabaseContract] = try await fetchForOrganization(from: "contracts")
            let cloudContractIds = Set(cloudContracts.map { $0.id })
            
            // Merge cloud contracts
            let existingContractIds = Set((try? modelContext.fetch(FetchDescriptor<SDContract>()))?.map { $0.id } ?? [])
            for cloudContract in cloudContracts {
                let isNew = !existingContractIds.contains(cloudContract.id)
                await mergeContract(cloudContract.toContract())
                if isNew { newContracts += 1 }
            }
            
            // Delete local contracts that no longer exist in cloud
            let localContracts = try modelContext.fetch(FetchDescriptor<SDContract>())
            var deletedCount = 0
            for localContract in localContracts {
                if !cloudContractIds.contains(localContract.id) {
                    modelContext.delete(localContract)
                    deletedCount += 1
                }
            }
            
            debugLog("  ✓ Synced \(cloudContracts.count) contracts from cloud, deleted \(deletedCount) local orphans")
        } catch {
            debugLog("  ✗ Failed to sync contracts: \(error)")
            syncErrors.append("contracts: \(error.localizedDescription)")
        }
        
        // Sync Programs (including deletions, but protect recently created local programs)
        do {
            let cloudPrograms: [SupabaseProgram] = try await fetchForOrganizationWithDebug(from: "programs")
            let cloudProgramIds = Set(cloudPrograms.map { $0.id })
            
            // Merge cloud programs
            let existingProgramIds = Set((try? modelContext.fetch(FetchDescriptor<SDProgram>()))?.map { $0.id } ?? [])
            for cloudProgram in cloudPrograms {
                let isNew = !existingProgramIds.contains(cloudProgram.id)
                await mergeProgram(cloudProgram.toProgram())
                if isNew { newPrograms += 1 }
            }
            
            // Delete local programs that no longer exist in cloud (protect recent)
            let localPrograms = try modelContext.fetch(FetchDescriptor<SDProgram>())
            let oneMinuteAgo = Date().addingTimeInterval(-300) // 5 minute protection for cloud replication
            var deletedCount = 0
            var protectedCount = 0
            
            let currentPendingUploads = await pendingUploadsTracker.getAll()
            
            for localProgram in localPrograms {
                if !cloudProgramIds.contains(localProgram.id) {
                    // Never delete if currently uploading
                    if currentPendingUploads.contains(localProgram.id) {
                        protectedCount += 1
                        debugLog("  🔄 Protected uploading program: \(localProgram.name)")
                        continue
                    }
                    
                    // Only delete if older than 1 minute
                    if localProgram.createdAt < oneMinuteAgo {
                        debugLog("  🗑️ Deleting orphan program: \(localProgram.name) (created \(Int(Date().timeIntervalSince(localProgram.createdAt)))s ago)")
                        modelContext.delete(localProgram)
                        deletedCount += 1
                    } else {
                        protectedCount += 1
                        debugLog("  ⏳ Protected recent program: \(localProgram.name) (created \(Int(Date().timeIntervalSince(localProgram.createdAt)))s ago)")
                    }
                }
            }
            
            debugLog("  ✓ Synced \(cloudPrograms.count) programs from cloud, deleted \(deletedCount) orphans, protected \(protectedCount) recent")
        } catch {
            debugLog("  ✗ Failed to sync programs: \(error)")
            syncErrors.append("programs: \(error.localizedDescription)")
        }
        
        // Sync Micro Cycles (Phases) - including deletions, protect recent
        do {
            let cloudMicroCycles: [SupabaseMicroCycle] = try await fetchForOrganization(from: "micro_cycles")
            let cloudMicroCycleIds = Set(cloudMicroCycles.map { $0.id })
            
            let existingCycleIds = Set((try? modelContext.fetch(FetchDescriptor<SDMicroCycle>()))?.map { $0.id } ?? [])
            for cloudMicroCycle in cloudMicroCycles {
                let isNew = !existingCycleIds.contains(cloudMicroCycle.id)
                await mergeMicroCycle(cloudMicroCycle.toMicroCycle())
                if isNew { newCycles += 1 }
            }
            
            // Delete local micro cycles that no longer exist in cloud (protect recent)
            let localMicroCycles = try modelContext.fetch(FetchDescriptor<SDMicroCycle>())
            let oneMinuteAgo = Date().addingTimeInterval(-300) // 5 minute protection for cloud replication
            var deletedCount = 0
            var protectedCount = 0
            
            let currentPendingUploads = await pendingUploadsTracker.getAll()
            
            for localCycle in localMicroCycles {
                if !cloudMicroCycleIds.contains(localCycle.id) {
                    // Never delete if currently uploading
                    if currentPendingUploads.contains(localCycle.id) {
                        protectedCount += 1
                        debugLog("  🔄 [SYNC-PROTECT] Protected uploading phase: \(localCycle.title) (ID: \(localCycle.id))")
                        continue
                    }
                    
                    // Only delete if older than 1 minute
                    if localCycle.createdAt < oneMinuteAgo {
                        debugLog("  🗑️ [SYNC-DELETE] Deleting orphan phase: \(localCycle.title) (ID: \(localCycle.id))")
                        debugLog("     - Created \(Int(Date().timeIntervalSince(localCycle.createdAt)))s ago")
                        debugLog("     - Not in cloud, older than 1min protection")
                        modelContext.delete(localCycle)
                        deletedCount += 1
                    } else {
                        protectedCount += 1
                        debugLog("  ⏳ [SYNC-PROTECT] Protected recent phase: \(localCycle.title) (ID: \(localCycle.id))")
                        debugLog("     - Created \(Int(Date().timeIntervalSince(localCycle.createdAt)))s ago (within 1min window)")
                    }
                }
            }
            
            debugLog("  ✓ Synced \(cloudMicroCycles.count) phases from cloud, deleted \(deletedCount) orphans, protected \(protectedCount) recent")
        } catch {
            debugLog("  ✗ Failed to sync phases: \(error)")
            syncErrors.append("micro_cycles: \(error.localizedDescription)")
        }
        
        // Sync Session Events - including deletions, protect recent
        do {
            let cloudSessions: [SupabaseSessionEvent] = try await fetchForOrganization(from: "session_events")
            let cloudSessionIds = Set(cloudSessions.map { $0.id })
            let existingSessionIds = Set((try? modelContext.fetch(FetchDescriptor<SDSessionEvent>()))?.map { $0.id } ?? [])
            for cloudSession in cloudSessions {
                let isNew = !existingSessionIds.contains(cloudSession.id)
                await mergeSessionEvent(cloudSession.toSessionEvent())
                if isNew { newSessions += 1 }
            }
            
            // Delete local sessions that no longer exist in cloud (protect recent)
            let localSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            let oneMinuteAgo = Date().addingTimeInterval(-300) // 5 minute protection for cloud replication
            var deletedCount = 0
            var protectedCount = 0
            
            let currentPendingUploads = await pendingUploadsTracker.getAll()
            
            for localSession in localSessions {
                if !cloudSessionIds.contains(localSession.id) {
                    // Never delete if currently uploading
                    if currentPendingUploads.contains(localSession.id) {
                        protectedCount += 1
                        debugLog("  🔄 [SYNC-PROTECT] Protected uploading session: \(localSession.title) (ID: \(localSession.id))")
                        continue
                    }
                    
                    // Only delete if older than 1 minute
                    if localSession.createdAt < oneMinuteAgo {
                        debugLog("  🗑️ [SYNC-DELETE] Deleting orphan session: \(localSession.title) (ID: \(localSession.id))")
                        debugLog("     - Created \(Int(Date().timeIntervalSince(localSession.createdAt)))s ago")
                        debugLog("     - Not in cloud, older than 1min protection")
                        modelContext.delete(localSession)
                        deletedCount += 1
                    } else {
                        protectedCount += 1
                        debugLog("  ⏳ [SYNC-PROTECT] Protected recent session: \(localSession.title) (ID: \(localSession.id))")
                        debugLog("     - Created \(Int(Date().timeIntervalSince(localSession.createdAt)))s ago (within 1min window)")
                    }
                }
            }
            
            debugLog("  ✓ Synced \(cloudSessions.count) sessions from cloud, deleted \(deletedCount) orphans, protected \(protectedCount) recent")
            
            // Auto-pull board notes for today's sessions (multi-user: see notes from other coaches)
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
            let todaySessions = cloudSessions.filter { $0.date >= todayStart && $0.date < todayEnd }
            for session in todaySessions {
                if let jsonString = session.boardNotesJson,
                   let data = jsonString.data(using: .utf8),
                   let cloudNotes = try? JSONDecoder().decode([BoardNote].self, from: data) {
                    // Merge with local: cloud wins on conflict (by note ID)
                    var merged: [UUID: BoardNote] = [:]
                    for note in BoardNotesStore.shared.notes(for: session.id) { merged[note.id] = note }
                    for note in cloudNotes { merged[note.id] = note }
                    let mergedList = Array(merged.values).sorted { $0.timestamp < $1.timestamp }
                    let localList = BoardNotesStore.shared.notes(for: session.id)
                    if mergedList.count != localList.count || mergedList.map(\.id) != localList.map(\.id) {
                        BoardNotesStore.shared.replaceNotes(for: session.id, with: mergedList)
                    }
                }
            }
            if !todaySessions.isEmpty {
                debugLog("  ✓ Auto-pulled board notes for \(todaySessions.count) today's sessions")
            }
        } catch {
            debugLog("  ✗ Failed to sync sessions: \(error)")
            syncErrors.append("sessions: \(error.localizedDescription)")
        }
        
        // Sync Measurements
        do {
            let cloudMeasurements: [SupabaseMeasurement] = try await fetchForOrganization(from: "measurements")
            let existingMeasurementIds = Set((try? modelContext.fetch(FetchDescriptor<SDMeasurement>()))?.map { $0.id } ?? [])
            var newMeasurements = 0
            for cloudMeasurement in cloudMeasurements {
                let isNew = !existingMeasurementIds.contains(cloudMeasurement.id)
                await mergeMeasurement(cloudMeasurement.toMeasurement())
                if isNew { newMeasurements += 1 }
            }
            if newMeasurements > 0 { syncLog.logDownload(table: "measurements", displayName: "Measurements", count: newMeasurements) }
            debugLog("  ✓ Synced \(cloudMeasurements.count) measurements from cloud (\(newMeasurements) new)")
        } catch {
            debugLog("  ✗ Failed to sync measurements: \(error)")
            syncErrors.append("measurements: \(error.localizedDescription)")
        }
        
        // Sync Drills
        do {
            let cloudDrills: [SupabaseDrill] = try await fetchForOrganization(from: "drills")
            let existingDrillIds = Set((try? modelContext.fetch(FetchDescriptor<SDDrill>()))?.map { $0.id } ?? [])
            var newDrills = 0
            for cloudDrill in cloudDrills {
                let isNew = !existingDrillIds.contains(cloudDrill.id)
                await mergeDrill(cloudDrill.toDrill())
                if isNew { newDrills += 1 }
            }
            if newDrills > 0 { syncLog.logDownload(table: "drills", displayName: "Drills", count: newDrills) }
            debugLog("  ✓ Synced \(cloudDrills.count) drills from cloud (\(newDrills) new)")
        } catch {
            debugLog("  ✗ Failed to sync drills: \(error)")
            syncErrors.append("drills: \(error.localizedDescription)")
        }
        
        // Sync Staff Coaches
        do {
            let cloudCoaches: [SupabaseStaffCoach] = try await fetchForOrganization(from: "staff_coaches")
            let existingCoachIds = Set((try? modelContext.fetch(FetchDescriptor<SDStaffCoach>()))?.map { $0.id } ?? [])
            for cloudCoach in cloudCoaches {
                let isNew = !existingCoachIds.contains(cloudCoach.id)
                await mergeStaffCoach(cloudCoach.toStaffCoach())
                if isNew { newCoaches += 1 }
            }
            debugLog("  ✓ Synced \(cloudCoaches.count) staff coaches from cloud (\(newCoaches) new)")
        } catch {
            debugLog("  ✗ Failed to sync staff coaches: \(error)")
            syncErrors.append("staff_coaches: \(error.localizedDescription)")
        }
        
        // Sync Locations
        do {
            let cloudLocations: [SupabaseLocation] = try await fetchForOrganization(from: "locations")
            let existingLocationIds = Set((try? modelContext.fetch(FetchDescriptor<SDLocation>()))?.map { $0.id } ?? [])
            for cloudLocation in cloudLocations {
                let isNew = !existingLocationIds.contains(cloudLocation.id)
                await mergeLocation(cloudLocation.toLocation())
                if isNew { newLocations += 1 }
            }
            debugLog("  ✓ Synced \(cloudLocations.count) locations from cloud (\(newLocations) new)")
        } catch {
            debugLog("  ✗ Failed to sync locations: \(error)")
            syncErrors.append("locations: \(error.localizedDescription)")
        }
        
        // Sync Age Categories
        do {
            let cloudCategories: [SupabaseAgeCategory] = try await fetchForOrganization(from: "age_categories")
            await MainActor.run {
                for cloudCategory in cloudCategories {
                    let category = cloudCategory.toAgeCategory()
                    if let index = ageCategories.firstIndex(where: { $0.id == category.id }) {
                        // Only update if cloud is newer
                        if category.updatedAt > ageCategories[index].updatedAt {
                            ageCategories[index] = category
                        }
                    } else {
                        ageCategories.append(category)
                    }
                }
                saveAgeCategories()  // Persist locally after cloud sync
            }
            debugLog("  ✓ Synced \(cloudCategories.count) age categories from cloud")
        } catch {
            debugLog("  ✗ Failed to sync age categories: \(error)")
            syncErrors.append("age_categories: \(error.localizedDescription)")
        }
        
        // Sync Plays
        do {
            let cloudPlays: [SupabasePlay] = try await fetchForOrganization(from: "plays")
            for cloudPlay in cloudPlays {
                mergePlay(cloudPlay.toPlay())
            }
            debugLog("  ✓ Synced \(cloudPlays.count) plays from cloud")
        } catch {
            debugLog("  ✗ Failed to sync plays: \(error)")
            syncErrors.append("plays: \(error.localizedDescription)")
        }
        
        // Sync Teams
        do {
            let cloudTeams: [SupabaseTeam] = try await fetchForOrganization(from: "teams")
            for cloudTeam in cloudTeams {
                await mergeTeam(cloudTeam.toTeam())
            }
            debugLog("  ✓ Synced \(cloudTeams.count) teams from cloud")
        } catch {
            debugLog("  ✗ Failed to sync teams: \(error)")
            syncErrors.append("teams: \(error.localizedDescription)")
        }
        
        // Sync Games
        do {
            let cloudGames: [SupabaseGame] = try await fetchForOrganization(from: "games")
            for cloudGame in cloudGames {
                await mergeGame(cloudGame.toGame())
            }
            debugLog("  ✓ Synced \(cloudGames.count) games from cloud")
        } catch {
            debugLog("  ✗ Failed to sync games: \(error)")
            syncErrors.append("games: \(error.localizedDescription)")
        }
        
        // Sync Team Standings
        do {
            let cloudStandings: [SupabaseTeamStanding] = try await fetchForOrganization(from: "team_standings")
            for cloudStanding in cloudStandings {
                await mergeTeamStanding(cloudStanding.toTeamStanding())
            }
            debugLog("  ✓ Synced \(cloudStandings.count) team standings from cloud")
        } catch {
            debugLog("  ✗ Failed to sync team standings: \(error)")
            syncErrors.append("team_standings: \(error.localizedDescription)")
        }
        
        // Flush download counts to log
        syncLog.logDownload(table: "students", displayName: "Athletes", count: newStudents)
        syncLog.logDownload(table: "players", displayName: "Player Profiles", count: newPlayers)
        syncLog.logDownload(table: "contracts", displayName: "Contracts", count: newContracts)
        syncLog.logDownload(table: "programs", displayName: "Programs", count: newPrograms)
        syncLog.logDownload(table: "micro_cycles", displayName: "Training Phases", count: newCycles)
        syncLog.logDownload(table: "session_events", displayName: "Sessions", count: newSessions)
        syncLog.logDownload(table: "staff_coaches", displayName: "Coaches", count: newCoaches)
        syncLog.logDownload(table: "locations", displayName: "Locations", count: newLocations)
        
        // Save and refresh
        do {
            try modelContext.save()
            await refreshAllCaches()
        } catch {
            debugLog("  ✗ Failed to save context: \(error)")
            syncErrors.append("save: \(error.localizedDescription)")
        }

        if syncErrors.isEmpty {
            lastSyncDate = Date()
            debugLog("✅ Cloud sync completed successfully")
            errorMessage = nil
        } else {
            debugLog("⚠️ Cloud sync completed with \(syncErrors.count) errors — lastSyncDate not advanced")
            errorMessage = "Sync errors: \(syncErrors.joined(separator: "; "))"
        }
    }
    
    // MARK: - Purge Sample Data from Cloud
    /// Deletes rows with 00000000- prefixed UUIDs (sample/demo data) from all Supabase tables.
    /// Only runs once per installation to avoid repeated delete calls.
    private func purgeSampleDataFromCloud() async {
        let purgeKey = "sample_data_purged_from_cloud_v1"
        guard !UserDefaults.standard.bool(forKey: purgeKey) else { return }
        
        debugLog("🧹 Purging sample data rows from Supabase...")
        
        let samplePrefix = "00000000-"
        let tables = ["students", "players", "contracts", "programs", "micro_cycles",
                      "session_events", "drills", "measurements", "staff_coaches"]
        
        for table in tables {
            do {
                let url = "\(SupabaseConfig.url)/rest/v1/\(table)?id=like.\(samplePrefix)%"
                var request = URLRequest(url: URL(string: url)!)
                request.httpMethod = "DELETE"
                request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("*", forHTTPHeaderField: "Prefer")
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    debugLog("  🗑️ Purged sample rows from \(table)")
                }
            } catch {
                debugLog("  ⚠️ Could not purge sample rows from \(table): \(error.localizedDescription)")
            }
        }
        
        // Also purge from local SwiftData store
        do {
            let sampleUUIDPrefix = "00000000"
            let sdStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            sdStudents.filter { $0.id.uuidString.hasPrefix(sampleUUIDPrefix) }.forEach { modelContext.delete($0) }
            let sdPrograms = try modelContext.fetch(FetchDescriptor<SDProgram>())
            sdPrograms.filter { $0.id.uuidString.hasPrefix(sampleUUIDPrefix) }.forEach { modelContext.delete($0) }
            let sdSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            sdSessions.filter { $0.id.uuidString.hasPrefix(sampleUUIDPrefix) }.forEach { modelContext.delete($0) }
            let sdCoaches = try modelContext.fetch(FetchDescriptor<SDStaffCoach>())
            sdCoaches.filter { $0.id.uuidString.hasPrefix(sampleUUIDPrefix) }.forEach { modelContext.delete($0) }
            try modelContext.save()
            debugLog("  🗑️ Purged sample rows from local SwiftData store")
        } catch {
            debugLog("  ⚠️ Could not purge sample rows from local store: \(error)")
        }
        
        UserDefaults.standard.set(true, forKey: purgeKey)
        debugLog("✅ Sample data purge complete")
    }
    
    func syncToCloud() async {
        guard SupabaseManager.shared.isConnected else {
            debugLog("⚠️ Not connected to Supabase - skipping upload")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        debugLog("☁️ Starting smart sync to cloud (only uploading newer local records)...")
        var uploadErrors: [String] = []
        let syncLog = SyncLogStore.shared
        
        // Fetch cloud timestamps to compare
        let cloudStudentTimestamps = await fetchCloudTimestamps(table: "students")
        let cloudPlayerTimestamps = await fetchCloudTimestamps(table: "players")
        let cloudContractTimestamps = await fetchCloudTimestamps(table: "contracts")
        let cloudProgramTimestamps = await fetchCloudTimestamps(table: "programs")
        let cloudMicroCycleTimestamps = await fetchCloudTimestamps(table: "micro_cycles")
        let cloudSessionTimestamps = await fetchCloudTimestamps(table: "session_events")
        let cloudDrillTimestamps = await fetchCloudTimestamps(table: "drills")
        let cloudMeasurementTimestamps = await fetchCloudTimestamps(table: "measurements")
        
        // Upload Students (only if local is newer)
        // Self-healing: stamp any nil-org SDStudents before building DTOs
        do {
            let sdStudents = (try? modelContext.fetch(FetchDescriptor<SDStudent>())) ?? []
            
            // Self-heal: if org is now available, stamp any SDStudents that were saved without one
            if let currentOrgId = currentOrganizationId {
                let untagged = sdStudents.filter { $0.organizationId == nil }
                if !untagged.isEmpty {
                    for sd in untagged { sd.organizationId = currentOrgId }
                    try? modelContext.save()
                    debugLog("  🔧 [SELF-HEAL] Stamped organizationId on \(untagged.count) students at sync time")
                }
            } else {
                debugLog("  ⚠️ [SYNC-DIAG] currentOrganizationId is NIL at syncToCloud time — students/sessions will be skipped")
                debugLog("  ⚠️ [SYNC-DIAG] AuthManager.currentOrganization: \(String(describing: AuthManager.shared.currentOrganization))")
                debugLog("  ⚠️ [SYNC-DIAG] AuthManager.authState: \(String(describing: AuthManager.shared.authState))")
            }
            
            // Re-read org map after potential self-heal
            let refreshedSDStudents = (try? modelContext.fetch(FetchDescriptor<SDStudent>())) ?? []
            let sdOrgIdMap = Dictionary(uniqueKeysWithValues: refreshedSDStudents.map { ($0.id, $0.organizationId) })
            let newerStudents = cachedStudents.filter { local in
                guard let cloudDate = cloudStudentTimestamps[local.id] else { return true } // New record
                return local.updatedAt > cloudDate
            }
            debugLog("  📊 [SYNC-DIAG] Students: \(cachedStudents.count) total, \(newerStudents.count) newer than cloud")
            if !newerStudents.isEmpty {
                let dtos = newerStudents.map { student -> SupabaseStudent in
                    let persistedOrgId = sdOrgIdMap[student.id] ?? nil
                    return SupabaseStudent(from: student, organizationId: persistedOrgId)
                }
                let uploadable = dtos.filter { $0.organizationId != nil }
                let skippedNoOrg = dtos.count - uploadable.count
                if skippedNoOrg > 0 {
                    debugLog("  ⚠️ Skipped \(skippedNoOrg) students with nil organizationId — will retry after org loads")
                }
                if !uploadable.isEmpty {
                    try await SupabaseManager.shared.batchUpsert(into: "students", data: uploadable)
                    syncLog.logUpload(table: "students", displayName: "Athletes", count: uploadable.count)
                    debugLog("  ✓ Uploaded \(uploadable.count) students to cloud (skipped \(cachedStudents.count - newerStudents.count) older)")
                }
            }
        } catch {
            debugLog("  ✗ Failed to upload students: \(error)")
            if let supaErr = error as? SupabaseError, case .serverError(let code, let msg) = supaErr {
                debugLog("  ⚠️ Supabase \(code): \(msg)")
                debugLog("  💡 If 'column does not exist': run supabase_migration_DEFINITIVE.sql in Supabase SQL Editor")
            }
            uploadErrors.append("students: \(error.localizedDescription)")
        }
        
        // Upload Players (only if local is newer and has valid student)
        do {
            let studentIds = Set(cachedStudents.map { $0.id })
            let validPlayers = cachedPlayers.filter { studentIds.contains($0.studentId) }
            let newerPlayers = validPlayers.filter { local in
                guard let cloudDate = cloudPlayerTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerPlayers.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "players", data: newerPlayers.map { SupabasePlayer(from: $0) })
                syncLog.logUpload(table: "players", displayName: "Player Profiles", count: newerPlayers.count)
                debugLog("  ✓ Uploaded \(newerPlayers.count) players to cloud")
            }
            if validPlayers.count < cachedPlayers.count {
                debugLog("  ⚠️ Skipped \(cachedPlayers.count - validPlayers.count) orphaned players (missing student)")
            }
        } catch {
            debugLog("  ✗ Failed to upload players: \(error)")
            uploadErrors.append("players: \(error.localizedDescription)")
        }
        
        // Upload Contracts (only if local is newer AND student exists)
        do {
            let studentIds = Set(cachedStudents.map { $0.id })
            let validContracts = cachedContracts.filter { studentIds.contains($0.studentId) }
            let newerContracts = validContracts.filter { local in
                guard let cloudDate = cloudContractTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerContracts.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "contracts", data: newerContracts.map { SupabaseContract(from: $0) })
                syncLog.logUpload(table: "contracts", displayName: "Contracts", count: newerContracts.count)
                debugLog("  ✓ Uploaded \(newerContracts.count) contracts to cloud")
            }
            if validContracts.count < cachedContracts.count {
                debugLog("  ⚠️ Skipped \(cachedContracts.count - validContracts.count) orphaned contracts (missing student)")
            }
        } catch {
            debugLog("  ✗ Failed to upload contracts: \(error)")
            uploadErrors.append("contracts: \(error.localizedDescription)")
        }
        
        // Upload Programs (only if local is newer)
        do {
            let newerPrograms = cachedPrograms.filter { local in
                guard let cloudDate = cloudProgramTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerPrograms.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "programs", data: newerPrograms.map { SupabaseProgram(from: $0) })
                syncLog.logUpload(table: "programs", displayName: "Programs", count: newerPrograms.count)
                debugLog("  ✓ Uploaded \(newerPrograms.count) programs to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload programs: \(error)")
            uploadErrors.append("programs: \(error.localizedDescription)")
        }
        
        // Upload Micro Cycles (only if local is newer, must be before session_events due to FK)
        do {
            let newerMicroCycles = cachedMicroCycles.filter { local in
                guard let cloudDate = cloudMicroCycleTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerMicroCycles.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "micro_cycles", data: newerMicroCycles.map { SupabaseMicroCycle(from: $0) })
                syncLog.logUpload(table: "micro_cycles", displayName: "Training Phases", count: newerMicroCycles.count)
                debugLog("  ✓ Uploaded \(newerMicroCycles.count) micro cycles to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload micro cycles: \(error)")
            uploadErrors.append("micro_cycles: \(error.localizedDescription)")
        }
        
        // Upload Session Events (only if local is newer and has valid micro_cycle or nil)
        // Self-healing: stamp any nil-org SDSessionEvents before building DTOs
        do {
            // Self-heal sessions the same way we do students
            if let currentOrgId = currentOrganizationId {
                let sdSessions = (try? modelContext.fetch(FetchDescriptor<SDSessionEvent>())) ?? []
                let untaggedSessions = sdSessions.filter { $0.organizationId == nil }
                if !untaggedSessions.isEmpty {
                    for sd in untaggedSessions { sd.organizationId = currentOrgId }
                    try? modelContext.save()
                    debugLog("  🔧 [SELF-HEAL] Stamped organizationId on \(untaggedSessions.count) sessions at sync time")
                }
            }

            // Build org map from persisted SDSessionEvent records
            let sdSessionEvents = (try? modelContext.fetch(FetchDescriptor<SDSessionEvent>())) ?? []
            let sdSessionOrgMap = Dictionary(uniqueKeysWithValues: sdSessionEvents.map { ($0.id, $0.organizationId) })

            let microCycleIds = Set(cachedMicroCycles.map { $0.id })
            let validSessions = cachedSessionEvents.filter { session in
                guard let mcId = session.microCycleId else { return true }
                return microCycleIds.contains(mcId)
            }
            let newerSessions = validSessions.filter { local in
                guard let cloudDate = cloudSessionTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            debugLog("  📊 [SYNC-DIAG] Sessions: \(cachedSessionEvents.count) total, \(newerSessions.count) newer than cloud")
            if !newerSessions.isEmpty {
                let dtos = newerSessions.map { session -> SupabaseSessionEvent in
                    let persistedOrgId = sdSessionOrgMap[session.id] ?? nil
                    return SupabaseSessionEvent(from: session, organizationId: persistedOrgId)
                }
                let uploadable = dtos.filter { $0.organizationId != nil }
                let skippedNoOrg = dtos.count - uploadable.count
                if skippedNoOrg > 0 {
                    debugLog("  ⚠️ Skipped \(skippedNoOrg) sessions with nil organizationId — will retry after org loads")
                }
                if !uploadable.isEmpty {
                    try await SupabaseManager.shared.batchUpsert(into: "session_events", data: uploadable)
                    syncLog.logUpload(table: "session_events", displayName: "Sessions", count: uploadable.count)
                    debugLog("  ✓ Uploaded \(uploadable.count) sessions to cloud")
                }
            }
            if validSessions.count < cachedSessionEvents.count {
                debugLog("  ⚠️ Skipped \(cachedSessionEvents.count - validSessions.count) sessions (missing micro_cycle)")
            }
        } catch {
            debugLog("  ✗ Failed to upload sessions: \(error)")
            uploadErrors.append("sessions: \(error.localizedDescription)")
        }
        
        // Upload Measurements (only if local is newer)
        do {
            let newerMeasurements = cachedMeasurements.filter { local in
                guard let cloudDate = cloudMeasurementTimestamps[local.id] else { return true }
                return local.recordedAt > cloudDate  // Measurements use recordedAt
            }
            if !newerMeasurements.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "measurements", data: newerMeasurements.map { SupabaseMeasurement(from: $0) })
                syncLog.logUpload(table: "measurements", displayName: "Measurements", count: newerMeasurements.count)
                debugLog("  ✓ Uploaded \(newerMeasurements.count) measurements to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload measurements: \(error)")
            uploadErrors.append("measurements: \(error.localizedDescription)")
        }
        
        // Upload Drills (only if local is newer)
        do {
            let newerDrills = cachedDrills.filter { local in
                guard let cloudDate = cloudDrillTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerDrills.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "drills", data: newerDrills.map { SupabaseDrill(from: $0) })
                syncLog.logUpload(table: "drills", displayName: "Drills", count: newerDrills.count)
                debugLog("  ✓ Uploaded \(newerDrills.count) drills to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload drills: \(error)")
            uploadErrors.append("drills: \(error.localizedDescription)")
        }
        
        // Upload Staff Coaches (with timestamp comparison to avoid duplicate upserts)
        do {
            let cloudCoachTimestamps = await fetchCloudTimestamps(table: "staff_coaches")
            let newerCoaches = staffCoaches.filter { local in
                guard let cloudDate = cloudCoachTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerCoaches.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "staff_coaches", data: newerCoaches.map { SupabaseStaffCoach(from: $0) })
                syncLog.logUpload(table: "staff_coaches", displayName: "Coaches", count: newerCoaches.count)
                debugLog("  ✓ Uploaded \(newerCoaches.count) staff coaches to cloud (skipped \(staffCoaches.count - newerCoaches.count) unchanged)")
            }
        } catch {
            debugLog("  ✗ Failed to upload staff coaches: \(error)")
            uploadErrors.append("staff_coaches: \(error.localizedDescription)")
        }
        
        // Upload Locations (no timestamp comparison for now)
        do {
            if !locations.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "locations", data: locations.map { SupabaseLocation(from: $0) })
                debugLog("  ✓ Uploaded \(locations.count) locations to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload locations: \(error)")
            uploadErrors.append("locations: \(error.localizedDescription)")
        }
        
        // Upload Plays (no timestamp comparison for now)
        do {
            if !plays.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "plays", data: plays.map { SupabasePlay(from: $0) })
                debugLog("  ✓ Uploaded \(plays.count) plays to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload plays: \(error)")
            uploadErrors.append("plays: \(error.localizedDescription)")
        }
        
        // Upload Teams (no timestamp comparison for now)
        do {
            if !teams.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "teams", data: teams.map { SupabaseTeam(from: $0) })
                debugLog("  ✓ Uploaded \(teams.count) teams to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload teams: \(error)")
            uploadErrors.append("teams: \(error.localizedDescription)")
        }
        
        // Upload Games (no timestamp comparison for now)
        do {
            if !games.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "games", data: games.map { SupabaseGame(from: $0) })
                debugLog("  ✓ Uploaded \(games.count) games to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload games: \(error)")
            uploadErrors.append("games: \(error.localizedDescription)")
        }
        
        // Upload Reminders (batch sync for resilience — individual sync on CRUD may fail)
        do {
            let cloudReminderTimestamps = await fetchCloudTimestamps(table: "reminders")
            let newerReminders = reminders.filter { local in
                guard let cloudDate = cloudReminderTimestamps[local.id] else { return true }
                return local.updatedAt > cloudDate
            }
            if !newerReminders.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "reminders", data: newerReminders.map { SupabaseReminder(from: $0) })
                syncLog.logUpload(table: "reminders", displayName: "Reminders", count: newerReminders.count)
                debugLog("  ✓ Uploaded \(newerReminders.count) reminders to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload reminders: \(error)")
            uploadErrors.append("reminders: \(error.localizedDescription)")
        }
        
        // Upload Team Standings (no timestamp comparison for now)
        do {
            if !teamStandings.isEmpty {
                try await SupabaseManager.shared.batchUpsert(into: "team_standings", data: teamStandings.map { SupabaseTeamStanding(from: $0) })
                debugLog("  ✓ Uploaded \(teamStandings.count) team standings to cloud")
            }
        } catch {
            debugLog("  ✗ Failed to upload team standings: \(error)")
            uploadErrors.append("team_standings: \(error.localizedDescription)")
        }
        
        if uploadErrors.isEmpty {
            debugLog("✅ Cloud upload completed successfully")
            errorMessage = nil
        } else {
            debugLog("⚠️ Cloud upload completed with \(uploadErrors.count) errors")
            errorMessage = "Upload errors: \(uploadErrors.joined(separator: "; "))"
        }
    }

    /// Fetch updatedAt timestamps from cloud for comparison, scoped to current organization
    private func fetchCloudTimestamps(table: String) async -> [UUID: Date] {
        // Measurements table uses recorded_at instead of updated_at
        if table == "measurements" {
            return await fetchMeasurementTimestamps()
        }
        
        guard let orgId = currentOrganizationId else {
            debugLog("  ⚠️ No organization set - skipping timestamp fetch for \(table)")
            return [:]
        }
        
        do {
            struct TimestampRecord: Decodable {
                let id: UUID
                let updatedAt: Date
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case updatedAt
                }
            }
            
            // Scope to current org so we don't see other orgs' records
            let urlString = "\(SupabaseConfig.url)/rest/v1/\(table)?select=id,updated_at&organization_id=eq.\(orgId.uuidString)"
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let s = try container.decode(String.self)
                let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
                if let d = f1.date(from: s) ?? f2.date(from: s) { return d }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(s)")
            }
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let records = try decoder.decode([TimestampRecord].self, from: data)
            debugLog("  📊 Fetched \(records.count) org-scoped timestamps from \(table)")
            return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.updatedAt) })
        } catch {
            debugLog("  ⚠️ Could not fetch timestamps from \(table): \(error.localizedDescription)")
            return [:]
        }
    }
    
    private func fetchMeasurementTimestamps() async -> [UUID: Date] {
        guard let orgId = currentOrganizationId else { return [:] }
        
        do {
            struct MeasurementTimestampRecord: Decodable {
                let id: UUID
                let recordedAt: Date
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case recordedAt = "recorded_at"
                }
            }
            
            let urlString = "\(SupabaseConfig.url)/rest/v1/measurements?select=id,recorded_at&organization_id=eq.\(orgId.uuidString)"
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let s = try container.decode(String.self)
                let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
                if let d = f1.date(from: s) ?? f2.date(from: s) { return d }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(s)")
            }
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let records = try decoder.decode([MeasurementTimestampRecord].self, from: data)
            debugLog("  📊 Fetched \(records.count) org-scoped timestamps from measurements")
            return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.recordedAt) })
        } catch {
            debugLog("  ⚠️ Could not fetch timestamps from measurements: \(error.localizedDescription)")
            return [:]
        }
    }
    
    func fullSync() async {
        guard SupabaseManager.shared.isConnected else { return }
        guard !isFullSyncInProgress else {
            debugLog("⚠️ fullSync already in progress, skipping")
            return
        }

        isFullSyncInProgress = true
        defer { isFullSyncInProgress = false }

        // Diagnostic: log org state so we can see why uploads/downloads may skip
        debugLog("🔄 [FULL-SYNC] Starting — org: \(AuthManager.shared.currentOrganization?.displayName ?? "NIL"), orgId: \(currentOrganizationId?.uuidString ?? "NIL"), authState: \(String(describing: AuthManager.shared.authState))")
        debugLog("🔄 [FULL-SYNC] Local counts — students: \(cachedStudents.count), sessions: \(cachedSessionEvents.count), measurements: \(cachedMeasurements.count), drills: \(cachedDrills.count)")

        // Self-heal: stamp nil-org SDStudents before sync if org is now available
        backfillStudentOrganizationIds()

        await SyncLogStore.shared.beginSession()
        // Upload local changes first to preserve user edits
        await syncToCloud()
        // Force-upload any students that syncToCloud may have missed (stuck local-only records)
        await forceUploadAllStudents()
        try? await Task.sleep(nanoseconds: 250_000_000)
        // Then download cloud changes
        await syncFromCloud()
        // Sync reminders (separate pipeline — has its own merge logic)
        await syncRemindersFromCloud()
        await SyncLogStore.shared.endSession()
    }
    
    // MARK: - Force Upload (Rescue Stuck Students)
    
    /// Force-upload ALL local students to Supabase, bypassing the "newer than cloud" check.
    /// This rescues students that are stuck locally (e.g., created when orgId was nil).
    /// Safe to call multiple times — uses upsert so existing records just get updated.
    func forceUploadAllStudents() async {
        guard SupabaseManager.shared.isConnected else { return }
        guard let orgId = currentOrganizationId else {
            debugLog("❌ [FORCE-UPLOAD] Cannot upload students — no organizationId available (auth: \(String(describing: AuthManager.shared.authState)))")
            return
        }
        
        // First, stamp orgId on any students that are missing it
        let allSDStudents = (try? modelContext.fetch(FetchDescriptor<SDStudent>())) ?? []
        var stamped = 0
        for sd in allSDStudents where sd.organizationId == nil {
            sd.organizationId = orgId
            stamped += 1
        }
        if stamped > 0 {
            try? modelContext.save()
            refreshCachesSync()
            debugLog("🔧 [FORCE-UPLOAD] Stamped organizationId on \(stamped) students")
        }
        
        // Build DTOs for ALL students (not just "newer")
        let dtos = cachedStudents.map { SupabaseStudent(from: $0, organizationId: orgId) }
        let uploadable = dtos.filter { $0.organizationId != nil }
        
        guard !uploadable.isEmpty else {
            debugLog("ℹ️ [FORCE-UPLOAD] No students to upload")
            return
        }
        
        do {
            try await SupabaseManager.shared.batchUpsert(into: "students", data: uploadable)
            debugLog("✅ [FORCE-UPLOAD] Force-uploaded \(uploadable.count) students to cloud")
        } catch {
            debugLog("❌ [FORCE-UPLOAD] Failed to upload students: \(error)")
        }
    }
    
    // MARK: - Lightweight Polling
    
    /// Lightweight poll: checks if any cloud table has changes since last sync.
    /// If changes are detected, runs syncFromCloud() only (no upload — that happens on local saves).
    /// Much cheaper than fullSync() — sends ~8 tiny queries (select=id&limit=1) in parallel.
    func pollForChanges() async {
        guard SupabaseManager.shared.isConnected else { return }
        guard !isFullSyncInProgress else { return }
        guard let orgId = currentOrganizationId else { return }
        
        // Use lastSyncDate; if never synced, skip polling (fullSync will run first)
        guard let since = lastSyncDate else { return }
        
        if let changedTable = await SupabaseManager.shared.hasCloudChanges(since: since, organizationId: orgId) {
            debugLog("🔔 [POLL] Change detected in '\(changedTable)' — pulling from cloud")
            await syncFromCloud()
            // lastSyncDate is updated inside syncFromCloud() only on full success
        }
    }
    
    // MARK: - Merge Helpers (for cloud sync)
    // Use timestamp-based conflict resolution - only overwrite if cloud is newer
    private func mergeStudent(_ cloudStudent: Student) async {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == cloudStudent.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data
                guard cloudStudent.updatedAt > existing.updatedAt else {
                    return // Local is newer, skip
                }
                
                existing.name = cloudStudent.name
                existing.chineseName = cloudStudent.chineseName
                existing.avatarColor = cloudStudent.avatarColor
                existing.attendanceStatus = cloudStudent.attendanceStatus
                existing.categoryId = cloudStudent.categoryId
                existing.coachId = cloudStudent.coachId
                existing.programId = cloudStudent.programId
                existing.birthdate = cloudStudent.birthdate
                existing.birthMonth = cloudStudent.birthMonth
                existing.birthYear = cloudStudent.birthYear
                existing.schoolGrade = cloudStudent.schoolGrade
                existing.profileImageUrl = cloudStudent.profileImageUrl
                existing.createdByCoachId = cloudStudent.createdByCoachId
                existing.parentalTouchpoints = cloudStudent.parentalTouchpoints
                existing.lastParentContact = cloudStudent.lastParentContact
                existing.mediaAssets = cloudStudent.mediaAssets
                existing.personalBests = cloudStudent.personalBests
                existing.performanceGrade = cloudStudent.performanceGrade
                existing.gradeHistory = cloudStudent.gradeHistory
                existing.updatedAt = cloudStudent.updatedAt
            } else {
                // Insert new
                modelContext.insert(SDStudent.from(cloudStudent))
            }
        } catch {
            debugLog("❌ Failed to merge student: \(error)")
        }
    }
    
    private func mergePlayer(_ cloudPlayer: Player) async {
        do {
            let descriptor = FetchDescriptor<SDPlayer>(predicate: #Predicate { $0.id == cloudPlayer.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data
                guard cloudPlayer.updatedAt > existing.updatedAt else {
                    return // Local is newer, skip
                }
                
                existing.heightCm = cloudPlayer.heightCm
                existing.weightKg = cloudPlayer.weightKg
                existing.wingspanCm = cloudPlayer.wingspanCm
                existing.handedness = cloudPlayer.handedness
                existing.position = cloudPlayer.position
                existing.jerseyNumber = cloudPlayer.jerseyNumber
                existing.setParentInfo(cloudPlayer.parentInfo)
                existing.setSecondaryParentInfo(cloudPlayer.secondaryParentInfo)
                existing.setContractInfo(cloudPlayer.contractInfo)
                existing.setSkills(cloudPlayer.skills)
                existing.coachNotes = cloudPlayer.coachNotes
                existing.medicalNotes = cloudPlayer.medicalNotes
                existing.updatedAt = cloudPlayer.updatedAt
            } else {
                modelContext.insert(SDPlayer.from(cloudPlayer))
            }
        } catch {
            debugLog("❌ Failed to merge player: \(error)")
        }
    }
    
    private func mergeContract(_ cloudContract: Contract) async {
        do {
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == cloudContract.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data (timestamp-based conflict resolution)
                guard cloudContract.updatedAt > existing.updatedAt else {
                    debugLog("⏭️ Skipping contract merge - local is newer (\(existing.updatedAt) > \(cloudContract.updatedAt))")
                    return
                }
                
                existing.contractNumber = cloudContract.contractNumber
                existing.contractType = cloudContract.contractType
                existing.totalSessions = cloudContract.totalSessions
                existing.attendedSessions = cloudContract.attendedSessions
                existing.weeklyAttendance = cloudContract.weeklyAttendance
                existing.startDate = cloudContract.startDate
                existing.expiryDate = cloudContract.expiryDate
                existing.pricePerSession = cloudContract.pricePerSession
                existing.totalAmount = cloudContract.totalAmount
                existing.amountPaid = cloudContract.amountPaid
                existing.isSigned = cloudContract.isSigned
                existing.signedDate = cloudContract.signedDate
                existing.jerseyGiven = cloudContract.jerseyGiven
                existing.jerseyGivenDate = cloudContract.jerseyGivenDate
                existing.ballGiven = cloudContract.ballGiven
                existing.ballGivenDate = cloudContract.ballGivenDate
                existing.jerseyNumber = cloudContract.jerseyNumber
                existing.jerseySize = cloudContract.jerseySize
                existing.notes = cloudContract.notes
                existing.createdByCoachId = cloudContract.createdByCoachId
                existing.manualStatus = cloudContract.manualStatus
                existing.programAssignments = cloudContract.programAssignments
                existing.historicalSessionsConsumed = cloudContract.historicalSessionsConsumed
                existing.updatedAt = cloudContract.updatedAt
                debugLog("✅ Merged contract from cloud (cloud is newer)")
            } else {
                modelContext.insert(SDContract.from(cloudContract))
            }
        } catch {
            debugLog("❌ Failed to merge contract: \(error)")
        }
    }
    
    private func mergeProgram(_ cloudProgram: Program) async {
        do {
            let descriptor = FetchDescriptor<SDProgram>(predicate: #Predicate { $0.id == cloudProgram.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data
                guard cloudProgram.updatedAt > existing.updatedAt else {
                    return // Local is newer, skip
                }
                
                existing.name = cloudProgram.name
                existing.ageGroup = cloudProgram.ageGroup
                existing.durationWeeks = cloudProgram.durationWeeks
                existing.programDescription = cloudProgram.description
                existing.objectives = cloudProgram.objectives
                existing.enrolledStudentIds = cloudProgram.enrolledStudentIds
                existing.coachId = cloudProgram.coachId
                existing.status = cloudProgram.status
                existing.colorHex = cloudProgram.colorHex
                existing.mascot = cloudProgram.mascot
                existing.startDate = cloudProgram.startDate
                existing.endDate = cloudProgram.endDate
                existing.imageData = cloudProgram.imageData
                existing.stars = cloudProgram.stars
                
                // Schedule fields - critical for persistence
                existing.recurringDays = cloudProgram.recurringDays
                existing.defaultSessionTime = cloudProgram.defaultSessionTime
                existing.defaultSessionDurationMinutes = cloudProgram.defaultSessionDurationMinutes
                
                // Skill targets
                existing.skillTargets = cloudProgram.skillTargets
                
                // Location
                existing.locationId = cloudProgram.locationId
                existing.locationName = cloudProgram.locationName
                
                existing.updatedAt = cloudProgram.updatedAt
            } else {
                modelContext.insert(SDProgram.from(cloudProgram))
            }
        } catch {
            debugLog("❌ Failed to merge program: \(error)")
        }
    }
    
    private func mergeMicroCycle(_ cloudMicroCycle: MicroCycle) async {
        do {
            let descriptor = FetchDescriptor<SDMicroCycle>(predicate: #Predicate { $0.id == cloudMicroCycle.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data
                guard cloudMicroCycle.updatedAt > existing.updatedAt else {
                    debugLog("   - Skipping micro cycle merge (local is newer)")
                    return
                }
                existing.programId = cloudMicroCycle.programId
                existing.phaseNumber = cloudMicroCycle.phaseNumber
                existing.title = cloudMicroCycle.title
                existing.focusRaw = cloudMicroCycle.focus.map { $0.rawValue }
                existing.durationWeeks = cloudMicroCycle.durationWeeks
                existing.cycleDescription = cloudMicroCycle.description
                existing.objectives = cloudMicroCycle.objectives
                existing.startDate = cloudMicroCycle.startDate
                existing.endDate = cloudMicroCycle.endDate
                existing.intensity = cloudMicroCycle.intensity
                existing.volume = cloudMicroCycle.volume
                existing.updatedAt = cloudMicroCycle.updatedAt
            } else {
                modelContext.insert(SDMicroCycle.from(cloudMicroCycle))
            }
        } catch {
            debugLog("❌ Failed to merge micro cycle: \(error)")
        }
    }
    
    private func mergeSessionEvent(_ cloudSession: SessionEvent) async {
        do {
            // Debug: Log incoming cloud session games
            if !cloudSession.games.isEmpty {
                debugLog("🎮 [DEBUG] mergeSessionEvent from cloud: \(cloudSession.title)")
                debugLog("   - Cloud games count: \(cloudSession.games.count)")
            }
            
            let descriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == cloudSession.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if cloud data is newer than local data
                guard cloudSession.updatedAt > existing.updatedAt else {
                    debugLog("   - Skipping merge (local is newer)")
                    return // Local is newer, skip
                }
                
                existing.programId = cloudSession.programId
                existing.microCycleId = cloudSession.microCycleId
                existing.title = cloudSession.title
                existing.date = cloudSession.date
                existing.startTime = cloudSession.startTime
                existing.endTime = cloudSession.endTime
                existing.location = cloudSession.location
                existing.sessionType = cloudSession.sessionType
                existing.status = cloudSession.status
                existing.curriculum = cloudSession.curriculum
                existing.attendeeIds = cloudSession.attendeeIds
                existing.actualAttendeeIds = cloudSession.actualAttendeeIds
                existing.excusedAbsences = cloudSession.excusedAbsences
                existing.attendancePhotoPath = cloudSession.attendancePhotoPath
                existing.notes = cloudSession.notes
                existing.coachNotes = cloudSession.coachNotes
                existing.developmentFocus = cloudSession.developmentFocus
                existing.manOfTheMatchId = cloudSession.manOfTheMatchId
                existing.drillsCompleted = cloudSession.drillsCompleted
                existing.rating = cloudSession.rating
                existing.createdByCoachId = cloudSession.createdByCoachId
                existing.games = cloudSession.games
                existing.updatedAt = cloudSession.updatedAt
            } else {
                modelContext.insert(SDSessionEvent.from(cloudSession))
            }
        } catch {
            debugLog("❌ Failed to merge session: \(error)")
        }
    }
    
    private func mergeMeasurement(_ cloudMeasurement: PlayerMeasurement) async {
        do {
            let descriptor = FetchDescriptor<SDMeasurement>(predicate: #Predicate { $0.id == cloudMeasurement.id })
            if try modelContext.fetch(descriptor).first == nil {
                // Measurements are immutable, only insert if not exists
                modelContext.insert(SDMeasurement.from(cloudMeasurement))
            }
        } catch {
            debugLog("❌ Failed to merge measurement: \(error)")
        }
    }
    
    private func mergeDrill(_ cloudDrill: DrillItem) async {
        do {
            // First try to find by ID
            let idDescriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == cloudDrill.id })
            if let existing = try modelContext.fetch(idDescriptor).first {
                // Cloud is source of truth - always update local with cloud data
                existing.name = cloudDrill.name
                existing.drillDescription = cloudDrill.description
                existing.category = cloudDrill.category
                existing.difficulty = cloudDrill.difficulty
                existing.durationMinutes = cloudDrill.durationMinutes
                existing.equipmentNeeded = cloudDrill.equipmentNeeded
                existing.instructions = cloudDrill.instructions
                existing.keyPoints = cloudDrill.keyPoints
                existing.variations = cloudDrill.variations
                existing.minPlayers = cloudDrill.minPlayers
                existing.maxPlayers = cloudDrill.maxPlayers
                existing.videoUrl = cloudDrill.videoUrl
                existing.tags = cloudDrill.tags
                existing.isFavorite = cloudDrill.isFavorite
                existing.updatedAt = cloudDrill.updatedAt
            } else {
                // Check by name to avoid duplicates (case-insensitive)
                let allDrills = try modelContext.fetch(FetchDescriptor<SDDrill>())
                let nameMatch = allDrills.first { $0.name.lowercased() == cloudDrill.name.lowercased() }
                
                if let existing = nameMatch {
                    // Update existing drill with same name (use cloud ID going forward)
                    existing.id = cloudDrill.id
                    existing.drillDescription = cloudDrill.description
                    existing.category = cloudDrill.category
                    existing.difficulty = cloudDrill.difficulty
                    existing.durationMinutes = cloudDrill.durationMinutes
                    existing.equipmentNeeded = cloudDrill.equipmentNeeded
                    existing.instructions = cloudDrill.instructions
                    existing.keyPoints = cloudDrill.keyPoints
                    existing.variations = cloudDrill.variations
                    existing.minPlayers = cloudDrill.minPlayers
                    existing.maxPlayers = cloudDrill.maxPlayers
                    existing.videoUrl = cloudDrill.videoUrl
                    existing.tags = cloudDrill.tags
                    // Preserve local favorite status
                    existing.updatedAt = cloudDrill.updatedAt
                } else {
                    modelContext.insert(SDDrill.from(cloudDrill))
                }
            }
        } catch {
            debugLog("❌ Failed to merge drill: \(error)")
        }
    }
    
    private func mergeStaffCoach(_ cloudCoach: StaffCoach) async {
        do {
            // Primary dedup: match by UUID
            let descriptor = FetchDescriptor<SDStaffCoach>(predicate: #Predicate { $0.id == cloudCoach.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Cloud is source of truth - always update local with cloud data
                existing.organizationId = cloudCoach.organizationId
                existing.name = cloudCoach.name
                existing.chineseName = cloudCoach.chineseName
                existing.email = cloudCoach.email
                existing.phone = cloudCoach.phone
                existing.role = cloudCoach.role
                existing.accessLevel = cloudCoach.accessLevel
                existing.specializations = cloudCoach.specializations
                existing.ageGroups = cloudCoach.ageGroups
                existing.avatarColor = cloudCoach.avatarColor
                existing.isActive = cloudCoach.isActive
                existing.hireDate = cloudCoach.hireDate
                existing.notes = cloudCoach.notes
                existing.profileImageUrl = cloudCoach.profileImageUrl
                existing.updatedAt = cloudCoach.updatedAt
                
                // Download profile image from cloud URL for local display on this device
                if let imageUrl = cloudCoach.profileImageUrl, imageUrl.hasPrefix("http"),
                   existing.profileImageData == nil,
                   let url = URL(string: imageUrl) {
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            await MainActor.run {
                                existing.profileImageData = data
                                debugLog("✅ Downloaded profile image for \(cloudCoach.name)")
                            }
                        } catch {
                            debugLog("⚠️ Failed to download profile image for \(cloudCoach.name): \(error)")
                        }
                    }
                }
            } else {
                let newCoach = SDStaffCoach.from(cloudCoach)
                modelContext.insert(newCoach)
                
                // Download profile image for the newly inserted coach
                if let imageUrl = cloudCoach.profileImageUrl, imageUrl.hasPrefix("http"),
                   let url = URL(string: imageUrl) {
                    Task {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            await MainActor.run {
                                newCoach.profileImageData = data
                                debugLog("✅ Downloaded profile image for new coach \(cloudCoach.name)")
                            }
                        } catch {
                            debugLog("⚠️ Failed to download profile image for \(cloudCoach.name): \(error)")
                        }
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to merge staff coach: \(error)")
        }
    }
    
    private func mergeLocation(_ cloudLocation: Location) async {
        do {
            let descriptor = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == cloudLocation.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Cloud is source of truth - always update local with cloud data
                existing.name = cloudLocation.name
                existing.address = cloudLocation.address
                existing.city = cloudLocation.city
                existing.courtCount = cloudLocation.courtCount
                existing.courtType = cloudLocation.courtType
                existing.amenities = cloudLocation.amenities
                existing.maxCapacity = cloudLocation.maxCapacity
                existing.isActive = cloudLocation.isActive
                existing.updatedAt = cloudLocation.updatedAt
            } else {
                modelContext.insert(SDLocation.from(cloudLocation))
            }
        } catch {
            debugLog("❌ Failed to merge location: \(error)")
        }
    }
    
    private func mergePlay(_ cloudPlay: Play) {
        // Cloud is source of truth - always update local with cloud data
        if let index = plays.firstIndex(where: { $0.id == cloudPlay.id }) {
            plays[index] = cloudPlay
        } else {
            plays.append(cloudPlay)
        }
    }
    
    private func mergeTeam(_ cloudTeam: Team) async {
        do {
            let descriptor = FetchDescriptor<SDTeam>(predicate: #Predicate { $0.id == cloudTeam.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Cloud is source of truth - always update local with cloud data
                existing.name = cloudTeam.name
                existing.shortName = cloudTeam.shortName
                existing.colorHex = cloudTeam.colorHex
                existing.secondaryColorHex = cloudTeam.secondaryColorHex
                existing.logoSystemImage = cloudTeam.logoSystemImage
                existing.mascotTypeRaw = cloudTeam.mascotTypeRaw
                existing.playerIds = cloudTeam.playerIds
                existing.coachName = cloudTeam.coachName
                existing.homeVenue = cloudTeam.homeVenue
                existing.updatedAt = cloudTeam.updatedAt
            } else {
                modelContext.insert(SDTeam.from(cloudTeam))
            }
        } catch {
            debugLog("❌ Failed to merge team: \(error)")
        }
    }
    
    private func mergeGame(_ cloudGame: Game) async {
        do {
            let descriptor = FetchDescriptor<SDGame>(predicate: #Predicate { $0.id == cloudGame.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Cloud is source of truth - always update local with cloud data
                existing.homeTeamId = cloudGame.homeTeamId
                existing.awayTeamId = cloudGame.awayTeamId
                existing.homeScore = cloudGame.homeScore
                existing.awayScore = cloudGame.awayScore
                existing.date = cloudGame.date
                existing.venue = cloudGame.venue
                existing.status = cloudGame.status
                existing.quarter = cloudGame.quarter
                existing.timeRemaining = cloudGame.timeRemaining
                existing.notes = cloudGame.notes
                existing.playerStats = cloudGame.playerStats
                existing.scoringPlays = cloudGame.scoringPlays
                existing.quarterScores = cloudGame.quarterScores
                existing.updatedAt = cloudGame.updatedAt
            } else {
                modelContext.insert(SDGame.from(cloudGame))
            }
        } catch {
            debugLog("❌ Failed to merge game: \(error)")
        }
    }
    
    private func mergeTeamStanding(_ cloudStanding: TeamStanding) async {
        // TeamStandings are stored in memory, not SwiftData
        if let index = teamStandings.firstIndex(where: { $0.teamId == cloudStanding.teamId }) {
            teamStandings[index] = cloudStanding
        } else {
            teamStandings.append(cloudStanding)
        }
    }
    
    // MARK: - Student CRUD
    func addStudent(_ student: Student, player: Player? = nil) {
        let sdStudent = SDStudent.from(student)
        modelContext.insert(sdStudent)
        
        if let player = player {
            let sdPlayer = SDPlayer.from(player)
            modelContext.insert(sdPlayer)
        }
        
        // Stamp organizationId immediately — try AuthManager first, then fallback to local data
        if sdStudent.organizationId == nil {
            if let orgId = currentOrganizationId {
                sdStudent.organizationId = orgId
                debugLog("🔧 [STUDENT-CREATE] Stamped organizationId on new student at insert time")
            }
        }
        
        let authOrgStr = AuthManager.shared.currentOrganization.map { $0.id.uuidString } ?? "NIL"
        debugLog("💾 [STUDENT-CREATE] Saving student: \(student.name) (ID: \(student.id), orgId: \(sdStudent.organizationId?.uuidString ?? "NIL"), authOrg: \(authOrgStr))")
        
        // Use saveAndRefresh — same pattern as every other CRUD method
        // This triggers fullSync → backfill → syncToCloud
        saveAndRefresh()
        
        // Also attempt an immediate direct upload for speed (belt-and-suspenders)
        if SupabaseManager.shared.isConnected {
            let capturedOrgId = sdStudent.organizationId
            Task {
                do {
                    let dto = SupabaseStudent(from: student, organizationId: capturedOrgId)
                    guard dto.organizationId != nil else {
                        debugLog("⚠️ [STUDENT-CREATE] Immediate upload skipped (orgId nil) — fullSync will handle it")
                        return
                    }
                    try await SupabaseManager.shared.batchUpsert(into: "students", data: [dto])
                    debugLog("✅ [STUDENT-CREATE] Student uploaded to cloud: \(student.name)")
                    
                    if let player = player {
                        try await SupabaseManager.shared.batchUpsert(into: "players", data: [SupabasePlayer(from: player)])
                        debugLog("✅ [STUDENT-CREATE] Player uploaded to cloud for: \(student.name)")
                    }
                } catch {
                    debugLog("❌ [STUDENT-CREATE] Immediate upload FAILED — fullSync will retry")
                    debugLog("   Error: \(error)")
                    if let supaErr = error as? SupabaseError, case .serverError(let code, let msg) = supaErr {
                        debugLog("   ⚠️ Supabase \(code): \(msg)")
                        debugLog("   💡 If 'column does not exist': run supabase_migration_DEFINITIVE.sql in Supabase SQL Editor")
                    }
                }
            }
        }
    }
    
    func updateStudent(_ student: Student) {
        do {
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == student.id })
            if let sdStudent = try modelContext.fetch(descriptor).first {
                // Self-heal: stamp organizationId if it was nil (student created before org loaded)
                if sdStudent.organizationId == nil, let orgId = AuthManager.shared.currentOrganization?.id {
                    sdStudent.organizationId = orgId
                    debugLog("🔧 [STUDENT-UPDATE] Late-stamped organizationId on \(student.name)")
                }
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
                sdStudent.parentalTouchpoints = student.parentalTouchpoints
                sdStudent.lastParentContact = student.lastParentContact
                sdStudent.mediaAssets = student.mediaAssets
                sdStudent.personalBests = student.personalBests
                sdStudent.performanceGrade = student.performanceGrade
                sdStudent.gradeHistory = student.gradeHistory
                sdStudent.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update student: \(error)")
        }
    }
    
    func deleteStudent(_ student: Student) {
        debugLog("🗑️ [DELETE-STUDENT] Starting deletion of: \(student.name) (ID: \(student.id))")
        do {
            // First, delete all contracts associated with this student (locally)
            let contractDescriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.studentId == student.id })
            let studentContracts = try modelContext.fetch(contractDescriptor)
            let studentContractIds = studentContracts.map(\.id)
            debugLog("🗑️ [DELETE-STUDENT] Found \(studentContracts.count) contracts to delete")
            for contract in studentContracts {
                modelContext.delete(contract)
            }
            
            // Delete associated player locally
            let playerDescriptor = FetchDescriptor<SDPlayer>(predicate: #Predicate { $0.studentId == student.id })
            let studentPlayers = try modelContext.fetch(playerDescriptor)
            let studentPlayerIds = studentPlayers.map(\.id)
            debugLog("🗑️ [DELETE-STUDENT] Found \(studentPlayers.count) players to delete")
            for player in studentPlayers {
                modelContext.delete(player)
            }
            
            // Delete the student
            let descriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == student.id })
            if let sdStudent = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdStudent)
                debugLog("🗑️ [DELETE-STUDENT] Deleted from local SwiftData: \(student.name)")
                saveAndRefresh()
                debugLog("✅ [DELETE-STUDENT] Local deletion completed, cache refreshed")
                
                // Also delete from cloud - contracts first, then player, then student
                if SupabaseManager.shared.isConnected {
                    Task {
                        debugLog("🌐 [DELETE-STUDENT] Starting cloud deletion for: \(student.name)")
                        
                        // Delete contracts from cloud first (FK constraint)
                        for contractId in studentContractIds {
                            await deleteFromCloudWithRetry(table: "contracts", id: contractId, entityLabel: "contract")
                        }

                        // Delete player from cloud
                        for playerId in studentPlayerIds {
                            await deleteFromCloudWithRetry(table: "players", id: playerId, entityLabel: "player")
                        }

                        // Finally delete student from cloud
                        await deleteFromCloudWithRetry(table: "students", id: student.id, entityLabel: "student")
                        debugLog("✅ [DELETE-STUDENT] Cloud deletion completed for: \(student.name)")
                    }
                } else {
                    debugLog("⚠️ [DELETE-STUDENT] Not connected to Supabase - deletion only local")
                }
            } else {
                debugLog("⚠️ [DELETE-STUDENT] Student not found in local database: \(student.name)")
            }
        } catch {
            debugLog("❌ [DELETE-STUDENT] Failed to delete student: \(error)")
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

        // Post activity event so the board notes feed shows this creation
        let creatorId: UUID = program.createdByCoachId ?? program.coachId ?? cachedCoach.id
        let creatorName = staffCoaches.first { $0.id == creatorId }?.name ?? cachedCoach.name
        Task { @MainActor in
            CoachMentionStore.shared.addProgramAddedEvent(
                programId: program.id,
                programName: program.name,
                createdByCoachId: creatorId,
                createdByCoachName: creatorName
            )
        }

        // CRITICAL: Upload program to cloud with retry and tracking
        // Phases and sessions depend on this program existing in cloud first
        if SupabaseManager.shared.isConnected {
            Task {
                await pendingUploadsTracker.insert(program.id)
                
                var uploadSucceeded = false
                var retryCount = 0
                let maxRetries = 3
                
                while !uploadSucceeded && retryCount < maxRetries {
                    do {
                        debugLog("   - [PROGRAM-UPLOAD] Attempting upload (\(retryCount + 1)/\(maxRetries))...")
                        try await SupabaseManager.shared.upsert(into: "programs", data: SupabaseProgram(from: program))
                        debugLog("✅ [PROGRAM-UPLOAD] Program uploaded to cloud: \(program.name) (ID: \(program.id))")
                        uploadSucceeded = true
                    } catch {
                        retryCount += 1
                        if retryCount < maxRetries {
                            debugLog("⚠️ [PROGRAM-UPLOAD] Failed (attempt \(retryCount)/\(maxRetries)): \(error.localizedDescription)")
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds before retry
                        } else {
                            debugLog("❌ [PROGRAM-UPLOAD] Upload failed after \(maxRetries) attempts: \(program.name)")
                            debugLog("   - Error: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Only remove from pending uploads if successful
                if uploadSucceeded {
                    await pendingUploadsTracker.remove(program.id)
                    let remainingCount = await pendingUploadsTracker.count()
                    debugLog("   - [PROGRAM-UPLOAD] Removed from pendingUploads (\(remainingCount) remaining)")
                } else {
                    let pendingCount = await pendingUploadsTracker.count()
                    debugLog("🔒 [PROGRAM-UPLOAD] Program kept in pendingUploads for protection: \(program.name)")
                    debugLog("   - Total pending uploads: \(pendingCount)")
                }
            }
        }
    }
    
    func updateProgram(_ program: Program) {
        do {
            let descriptor = FetchDescriptor<SDProgram>(predicate: #Predicate { $0.id == program.id })
            if let sdProgram = try modelContext.fetch(descriptor).first {
                sdProgram.name = program.name
                sdProgram.ageGroup = program.ageGroup
                sdProgram.durationWeeks = program.durationWeeks
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
                
                // Immediately upload to Supabase (async, don't block)
                if SupabaseManager.shared.isConnected {
                    Task {
                        await pendingUploadsTracker.insert(program.id)
                        
                        var uploadSucceeded = false
                        var retryCount = 0
                        let maxRetries = 3
                        
                        while !uploadSucceeded && retryCount < maxRetries {
                            do {
                                try await SupabaseManager.shared.upsert(into: "programs", data: SupabaseProgram(from: program))
                                debugLog("✅ Program updated in cloud: \(program.name)")
                                uploadSucceeded = true
                            } catch {
                                retryCount += 1
                                if retryCount < maxRetries {
                                    debugLog("⚠️ Failed to update program (attempt \(retryCount)/\(maxRetries)): \(error.localizedDescription)")
                                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds before retry
                                } else {
                                    debugLog("❌ Program update failed after \(maxRetries) attempts: \(program.name) - \(error.localizedDescription)")
                                }
                            }
                        }
                        
                        // Only remove from pending uploads if successful
                        if uploadSucceeded {
                            await pendingUploadsTracker.remove(program.id)
                        } else {
                            debugLog("🔒 Program kept in pendingUploads for protection: \(program.name)")
                        }
                    }
                }
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
                
                // Delete from cloud (fire and forget, but log errors)
                if SupabaseManager.shared.isConnected {
                    Task {
                        // Delete micro cycles first (foreign key constraint)
                        for cycle in cycles {
                            await deleteFromCloudWithRetry(table: "micro_cycles", id: cycle.id, entityLabel: "phase")
                        }

                        // Then delete program
                        await deleteFromCloudWithRetry(table: "programs", id: program.id, entityLabel: "program")
                        debugLog("✅ Program and \(cycles.count) phases deleted from cloud")
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to delete program: \(error)")
        }
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
        
        // Immediately upload to Supabase (async, don't block)
        if SupabaseManager.shared.isConnected {
            Task {
                await pendingUploadsTracker.insert(microCycle.id)
                
                var uploadSucceeded = false
                var retryCount = 0
                let maxRetries = 3
                
                while !uploadSucceeded && retryCount < maxRetries {
                    do {
                        debugLog("   - [PHASE-UPLOAD] Attempting upload (\(retryCount + 1)/\(maxRetries))...")
                        try await SupabaseManager.shared.upsert(into: "micro_cycles", data: SupabaseMicroCycle(from: microCycle))
                        debugLog("✅ [PHASE-UPLOAD] Phase uploaded to cloud: \(microCycle.title) (ID: \(microCycle.id))")
                        uploadSucceeded = true
                    } catch {
                        retryCount += 1
                        if retryCount < maxRetries {
                            debugLog("⚠️ [PHASE-UPLOAD] Failed (attempt \(retryCount)/\(maxRetries)): \(error.localizedDescription)")
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds before retry
                        } else {
                            debugLog("❌ [PHASE-UPLOAD] Upload failed after \(maxRetries) attempts: \(microCycle.title)")
                            debugLog("   - Error: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Only remove from pending uploads if successful
                if uploadSucceeded {
                    await pendingUploadsTracker.remove(microCycle.id)
                    let remainingCount = await pendingUploadsTracker.count()
                    debugLog("   - [PHASE-UPLOAD] Removed from pendingUploads (\(remainingCount) remaining)")
                } else {
                    let pendingCount = await pendingUploadsTracker.count()
                    debugLog("🔒 [PHASE-UPLOAD] Phase kept in pendingUploads for protection: \(microCycle.title)")
                    debugLog("   - Total pending uploads: \(pendingCount)")
                }
            }
        }
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
                sdCycle.startDate = microCycle.startDate
                sdCycle.endDate = microCycle.endDate
                sdCycle.intensity = microCycle.intensity
                sdCycle.volume = microCycle.volume
                sdCycle.updatedAt = Date()
                saveAndRefresh()
                
                // Immediately upload to Supabase
                if SupabaseManager.shared.isConnected {
                    Task {
                        do {
                            try await SupabaseManager.shared.upsert(into: "micro_cycles", data: SupabaseMicroCycle(from: microCycle))
                            debugLog("✅ Phase updated in cloud: \(microCycle.title)")
                        } catch {
                            debugLog("⚠️ Failed to update phase in cloud: \(error)")
                        }
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to update micro cycle: \(error)")
        }
    }
    
    func deleteMicroCycle(_ microCycle: MicroCycle) {
        do {
            let descriptor = FetchDescriptor<SDMicroCycle>(predicate: #Predicate { $0.id == microCycle.id })
            if let sdCycle = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdCycle)
                saveAndRefresh()
                
                // Also delete from cloud
                if SupabaseManager.shared.isConnected {
                    Task {
                        await deleteFromCloudWithRetry(table: "micro_cycles", id: microCycle.id, entityLabel: "phase")
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to delete micro cycle: \(error)")
        }
    }

    private func deleteFromCloudWithRetry(table: String, id: UUID, entityLabel: String, maxRetries: Int = 3) async {
        var attempt = 1

        while attempt <= maxRetries {
            do {
                try await SupabaseManager.shared.delete(from: table, id: id)
                debugLog("✅ Deleted \(entityLabel) from Supabase (id: \(id))")
                return
            } catch {
                if attempt == maxRetries {
                    debugLog("❌ Failed to delete \(entityLabel) from Supabase after \(maxRetries) attempts (id: \(id)): \(error.localizedDescription)")
                    return
                }

                debugLog("⚠️ Failed to delete \(entityLabel) from Supabase (attempt \(attempt)/\(maxRetries), id: \(id)): \(error.localizedDescription)")
                attempt += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    // MARK: - Session CRUD
    func addSessionEvent(_ event: SessionEvent) {
        let sdSession = SDSessionEvent.from(event)
        // Tag with current org so lightweight sync can filter by organization_id.
        // Backfill logic exists elsewhere, but setting it at creation time avoids a
        // follow-up write and ensures the row is sync-ready from the first save.
        if sdSession.organizationId == nil {
            sdSession.organizationId = AuthManager.shared.currentOrganization?.id
        }
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

        // Post activity event so the board notes feed shows this creation
        let sessionCreatorId: UUID = event.createdByCoachId ?? cachedCoach.id
        let sessionCreatorName = staffCoaches.first { $0.id == sessionCreatorId }?.name ?? cachedCoach.name
        let sessionProgramName = event.programId.flatMap { pid in cachedPrograms.first { $0.id == pid }?.name }
        Task { @MainActor in
            CoachMentionStore.shared.addSessionCreatedEvent(
                sessionId: event.id,
                sessionName: event.title,
                programId: event.programId,
                programName: sessionProgramName,
                createdByCoachId: sessionCreatorId,
                createdByCoachName: sessionCreatorName
            )
        }

        // Immediately upload to Supabase (async, don't block)
        if SupabaseManager.shared.isConnected {
            let parentPhaseId = event.microCycleId
            
            Task {
                await pendingUploadsTracker.insert(event.id)
                
                // CRITICAL: Wait for parent program to upload first (foreign key dependency)
                if let programId = event.programId {
                    var waitCount = 0
                    var isProgramUploading = await pendingUploadsTracker.contains(programId)
                    
                    while isProgramUploading && waitCount < 300 { // Max 30 seconds wait
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        waitCount += 1
                        isProgramUploading = await pendingUploadsTracker.contains(programId)
                    }
                    
                    if waitCount > 0 {
                        debugLog("⏳ [SESSION-UPLOAD] Session waited \(waitCount * 100)ms for parent program to upload")
                    }
                }
                
                // CRITICAL: If session has a parent phase, wait for phase to upload first
                if let phaseId = parentPhaseId {
                    var waitCount = 0
                    var isPhaseUploading = await pendingUploadsTracker.contains(phaseId)
                    
                    while isPhaseUploading && waitCount < 300 { // Max 30 seconds wait
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        waitCount += 1
                        isPhaseUploading = await pendingUploadsTracker.contains(phaseId)
                    }
                    
                    if waitCount > 0 {
                        debugLog("⏳ [SESSION-UPLOAD] Session waited \(waitCount * 100)ms for parent phase to upload")
                    }
                }
                
                var uploadSucceeded = false
                var retryCount = 0
                let maxRetries = 3
                
                while !uploadSucceeded && retryCount < maxRetries {
                    do {
                        debugLog("   - [SESSION-UPLOAD] Attempting upload (\(retryCount + 1)/\(maxRetries))...")
                        try await SupabaseManager.shared.upsert(into: "session_events", data: SupabaseSessionEvent(from: event))
                        debugLog("✅ [SESSION-UPLOAD] Session uploaded to cloud: \(event.title) (ID: \(event.id))")
                        uploadSucceeded = true
                    } catch {
                        retryCount += 1
                        if retryCount < maxRetries {
                            debugLog("⚠️ [SESSION-UPLOAD] Failed (attempt \(retryCount)/\(maxRetries)): \(error.localizedDescription)")
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds before retry
                        } else {
                            debugLog("❌ [SESSION-UPLOAD] Upload failed after \(maxRetries) attempts: \(event.title)")
                            debugLog("   - Error: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Only remove from pending uploads if successful
                if uploadSucceeded {
                    await pendingUploadsTracker.remove(event.id)
                    let remainingCount = await pendingUploadsTracker.count()
                    debugLog("   - [SESSION-UPLOAD] Removed from pendingUploads (\(remainingCount) remaining)")
                } else {
                    let pendingCount = await pendingUploadsTracker.count()
                    debugLog("🔒 [SESSION-UPLOAD] Session kept in pendingUploads for protection: \(event.title)")
                    debugLog("   - Total pending uploads: \(pendingCount)")
                }
            }
        }
    }
    
    func updateSessionEvent(_ event: SessionEvent) {
        do {
            let descriptor = FetchDescriptor<SDSessionEvent>(predicate: #Predicate { $0.id == event.id })
            if let sdSession = try modelContext.fetch(descriptor).first {
                // Self-heal: stamp organizationId if it was nil (session created before org loaded)
                if sdSession.organizationId == nil, let orgId = AuthManager.shared.currentOrganization?.id {
                    sdSession.organizationId = orgId
                    debugLog("🔧 [SESSION-UPDATE] Late-stamped organizationId on \(event.title)")
                }
                
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
                sdSession.assignedCoachIds = event.assignedCoachIds
                sdSession.games = event.games  // Persist in-session games
                sdSession.updatedAt = Date()
                
                // Debug: Verify games were set
                debugLog("   - Saved games count: \(sdSession.games.count)")
                
                saveAndRefresh()
                
                // Update contracts for all students who attended this session
                updateContractsForAttendance(sessionEvent: event)
                
                // Immediately upload to Supabase (use persisted orgId for reliability)
                let persistedSessionOrgId = sdSession.organizationId
                if SupabaseManager.shared.isConnected {
                    Task {
                        do {
                            let dto = SupabaseSessionEvent(from: event, organizationId: persistedSessionOrgId)
                            debugLog("🎮 [DEBUG] Uploading session to Supabase: \(event.title)")
                            debugLog("   - Games in DTO: \(dto.games.count)")
                            try await SupabaseManager.shared.upsert(into: "session_events", data: dto)
                            debugLog("✅ Session updated in cloud: \(event.title)")
                        } catch {
                            debugLog("⚠️ Failed to update session in cloud: \(error)")
                        }
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to update session: \(error)")
        }
    }
    
    /// Update contracts to reflect attendance changes for a session
    private func updateContractsForAttendance(sessionEvent: SessionEvent) {
        // Count any session where attendance is marked (regardless of status)
        // If someone is marked as attended, they attended
        
        // For each student who attended, ensure their contract has this session
        for studentId in sessionEvent.actualAttendeeIds {
            guard var contract = currentContract(for: studentId) else {
                // Create default contract if none exists
                var newContract = Contract(
                    studentId: studentId,
                    contractType: .payAsYouGo,
                    enrollmentDate: sessionEvent.date
                )
                newContract.attendedSessionIds = [sessionEvent.id]
                addContract(newContract)
                debugLog("📝 Created contract for \(studentId) with session \(sessionEvent.id)")
                continue
            }
            
            // Add session to contract if not already there
            if !contract.attendedSessionIds.contains(sessionEvent.id) {
                contract.attendedSessionIds.append(sessionEvent.id)
                updateContract(contract)
                debugLog("📝 Added session \(sessionEvent.id) to contract for \(studentId)")
            }
        }
        
        // For students who were removed from attendance, remove session from their contract
        for contract in cachedContracts {
            if contract.attendedSessionIds.contains(sessionEvent.id) &&
               !sessionEvent.actualAttendeeIds.contains(contract.studentId) {
                var updatedContract = contract
                updatedContract.attendedSessionIds.removeAll { $0 == sessionEvent.id }
                updateContract(updatedContract)
                debugLog("📝 Removed session \(sessionEvent.id) from contract for \(contract.studentId)")
            }
        }
    }
    
    /// Mark a student as present in a session
    /// Note: Session consumption is now calculated from SessionEvent records - no manual contract deduction needed
    ///
    /// Re-reads the latest session from `cachedSessionEvents` before mutating so that
    /// rapid-fire attendance toggles (or concurrent coaches marking different students)
    /// don't clobber each other with a stale snapshot.
    func markStudentPresent(studentId: UUID, in sessionEvent: SessionEvent) {
        var updatedSession = cachedSessionEvents.first(where: { $0.id == sessionEvent.id }) ?? sessionEvent

        // Add to actualAttendeeIds if not already present
        if !updatedSession.actualAttendeeIds.contains(studentId) {
            updatedSession.actualAttendeeIds.append(studentId)
            updateSessionEvent(updatedSession)

            // Session consumption is now derived from SessionEvent.actualAttendeeIds
            // No need to manually deduct from contract - it's calculated automatically
            debugLog("✅ Marked student \(studentId) as present")
        }
    }

    /// Mark a student as absent in a session (remove from actualAttendeeIds, but do NOT restore contract session)
    ///
    /// Re-reads the latest session from `cachedSessionEvents` before mutating (see
    /// `markStudentPresent`) to avoid overwriting concurrent attendance edits.
    func markStudentAbsent(studentId: UUID, in sessionEvent: SessionEvent) {
        var updatedSession = cachedSessionEvents.first(where: { $0.id == sessionEvent.id }) ?? sessionEvent

        // Remove from actualAttendeeIds
        if let index = updatedSession.actualAttendeeIds.firstIndex(of: studentId) {
            updatedSession.actualAttendeeIds.remove(at: index)
            updateSessionEvent(updatedSession)
            debugLog("✅ Marked student \(studentId) as absent")
            // Note: We do NOT restore contract sessions - once deducted, they stay deducted
            // This prevents gaming the system by toggling attendance
        }
    }
    
    /// DEPRECATED: Manual contract deduction is no longer used
    /// Session consumption is now calculated from SessionEvent records via sessionsConsumed(for:)
    /// This function is kept for backward compatibility but does nothing
    @available(*, deprecated, message: "Session consumption is now event-based. Use sessionsConsumed(for:) instead.")
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
                
                // Also delete from cloud
                if SupabaseManager.shared.isConnected {
                    Task {
                        try? await SupabaseManager.shared.delete(from: "session_events", id: event.id)
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to delete session: \(error)")
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
                
                // Sync to cloud
                if SupabaseManager.shared.isConnected {
                    Task {
                        await syncToCloud()
                    }
                }
            } else {
                debugLog("ℹ️ No sessions needed duration migration")
            }
        } catch {
            debugLog("❌ Failed to migrate session durations: \(error)")
        }
    }
    
    /// Backfill organizationId on any SDStudent and SDSessionEvent records that were saved before the field was stamped.
    /// Runs at loadAllData and again at fullSync time; only updates records where organizationId is nil and org is known.
    func backfillStudentOrganizationIds() {
        guard let orgId = currentOrganizationId else {
            debugLog("ℹ️ [BACKFILL] No org available (auth: \(String(describing: AuthManager.shared.authState))) — skipping organizationId backfill")
            return
        }
        var totalStamped = 0
        do {
            let allSDStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            let untaggedStudents = allSDStudents.filter { $0.organizationId == nil }
            if !untaggedStudents.isEmpty {
                for sd in untaggedStudents { sd.organizationId = orgId }
                totalStamped += untaggedStudents.count
                debugLog("✅ [BACKFILL] Stamped organizationId on \(untaggedStudents.count) students")
            }
        } catch {
            debugLog("❌ [BACKFILL] Failed to backfill student organizationIds: \(error)")
        }
        do {
            let allSDSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            let untaggedSessions = allSDSessions.filter { $0.organizationId == nil }
            if !untaggedSessions.isEmpty {
                for sd in untaggedSessions { sd.organizationId = orgId }
                totalStamped += untaggedSessions.count
                debugLog("✅ [BACKFILL] Stamped organizationId on \(untaggedSessions.count) sessions")
            }
        } catch {
            debugLog("❌ [BACKFILL] Failed to backfill session organizationIds: \(error)")
        }
        if totalStamped > 0 {
            try? modelContext.save()
            debugLog("✅ [BACKFILL] Total stamped: \(totalStamped) records — they will upload on next sync")
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
                debugLog("✅ Removed \(deletedCount) duplicate drills")
                
                // Also delete from Supabase
                if SupabaseManager.shared.isConnected {
                    Task {
                        for id in deletedIds {
                            try? await SupabaseManager.shared.delete(from: "drills", id: id)
                        }
                        debugLog("✅ Synced drill deletions to cloud")
                    }
                }
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
        saveAndRefresh()
    }
    
    func updateDrill(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
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
                sdDrill.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update drill: \(error)")
        }
    }
    
    func toggleDrillFavorite(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
                sdDrill.isFavorite.toggle()
                sdDrill.updatedAt = Date()
                saveAndRefresh()
                
                // Sync to Supabase immediately
                if SupabaseManager.shared.isConnected {
                    Task {
                        do {
                            let updatedDrill = sdDrill.toStruct()
                            try await SupabaseManager.shared.upsert(into: "drills", data: SupabaseDrill(from: updatedDrill))
                            debugLog("✓ Synced drill favorite to cloud: \(updatedDrill.name)")
                        } catch {
                            debugLog("❌ Failed to sync drill favorite: \(error)")
                        }
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to toggle drill favorite: \(error)")
        }
    }
    
    func deleteDrill(_ drill: DrillItem) {
        do {
            let descriptor = FetchDescriptor<SDDrill>(predicate: #Predicate { $0.id == drill.id })
            if let sdDrill = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdDrill)
                saveAndRefresh()
                
                // Also delete from cloud
                if SupabaseManager.shared.isConnected {
                    Task {
                        try? await SupabaseManager.shared.delete(from: "drills", id: drill.id)
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to delete drill: \(error)")
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
    func addPlay(_ play: Play) {
        plays.append(play)
        objectWillChange.send()
    }
    
    func updatePlay(_ play: Play) {
        if let index = plays.firstIndex(where: { $0.id == play.id }) {
            plays[index] = play
            objectWillChange.send()
        }
    }
    
    func deletePlay(_ play: Play) {
        plays.removeAll { $0.id == play.id }
        objectWillChange.send()
    }
    
    func togglePlayFavorite(_ play: Play) {
        if let index = plays.firstIndex(where: { $0.id == play.id }) {
            plays[index].isFavorite.toggle()
            objectWillChange.send()
        }
    }
    
    // MARK: - Contract CRUD
    
    /// Enrich a contract with event-based session consumption so all UI consumers
    /// see the correct attendedSessions without calling sessionsConsumed(for:) directly.
    private func enriched(_ contract: Contract) -> Contract {
        guard !contract.isPayAsYouGo else { return contract }
        var enriched = contract
        enriched.attendedSessions = sessionsConsumed(for: contract)
        return enriched
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
    
    /// Get or create a default pay-as-you-go contract for students without contracts
    /// This ensures every student has at least a basic contract to track session attendance
    func getOrCreateDefaultContract(for studentId: UUID) -> Contract {
        // Check if student already has a contract
        if let existing = currentContract(for: studentId) {
            return existing
        }
        
        // Try to find the student's earliest session attendance to use as enrollment date
        let studentSessions = cachedSessionEvents.filter { 
            $0.actualAttendeeIds.contains(studentId) 
        }.sorted { $0.date < $1.date }
        
        let enrollmentDate = studentSessions.first?.date ?? Date()
        
        // Create a default pay-as-you-go contract
        var defaultContract = Contract(
            studentId: studentId,
            contractNumber: 1,
            contractType: .payAsYouGo,
            enrollmentDate: enrollmentDate,
            notes: "Auto-created tracking contract"
        )
        
        // Pre-populate attended session IDs from actual attendance records
        defaultContract.attendedSessionIds = studentSessions.map { $0.id }
        
        addContract(defaultContract)
        debugLog("✅ Created default contract for student \(studentId) with \(defaultContract.attendedSessionIds.count) sessions")
        return defaultContract
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
    
    func addContract(_ contract: Contract) {
        debugLog("📝 addContract called for contract ID: \(contract.id), studentId: \(contract.studentId)")
        
        do {
            // First check if contract with this ID already exists (upsert logic)
            let contractId = contract.id
            let existingDescriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == contractId })
            let existing = try modelContext.fetch(existingDescriptor)
            
            if let sdContract = existing.first {
                // Contract exists - update it instead of inserting
                debugLog("📝 Contract already exists, updating instead...")
                sdContract.contractNumber = contract.contractNumber
                sdContract.contractType = contract.contractType
                sdContract.enrollmentDate = contract.enrollmentDate
                sdContract.totalSessions = contract.totalSessions
                sdContract.attendedSessions = contract.attendedSessions
                sdContract.attendedSessionIds = contract.attendedSessionIds
                sdContract.weeklyAttendance = contract.weeklyAttendance
                sdContract.startDate = contract.startDate
                sdContract.expiryDate = contract.expiryDate
                sdContract.pricePerSession = contract.pricePerSession
                sdContract.totalAmount = contract.totalAmount
                sdContract.amountPaid = contract.amountPaid
                sdContract.isSigned = contract.isSigned
                sdContract.signedDate = contract.signedDate
                sdContract.jerseyGiven = contract.jerseyGiven
                sdContract.jerseyGivenDate = contract.jerseyGivenDate
                sdContract.ballGiven = contract.ballGiven
                sdContract.ballGivenDate = contract.ballGivenDate
                sdContract.jerseyNumber = contract.jerseyNumber
                sdContract.jerseySize = contract.jerseySize
                sdContract.notes = contract.notes
                sdContract.manualStatus = contract.manualStatus
                sdContract.programAssignments = contract.programAssignments
                sdContract.historicalSessionsConsumed = contract.historicalSessionsConsumed
                sdContract.updatedAt = Date()
            } else {
                // New contract - insert
                debugLog("📝 Creating new contract...")
                let sdContract = SDContract.from(contract)
                
                // Link contract to student
                let studentId = contract.studentId
                let studentDescriptor = FetchDescriptor<SDStudent>(predicate: #Predicate { $0.id == studentId })
                if let sdStudent = try modelContext.fetch(studentDescriptor).first {
                    sdContract.student = sdStudent
                    debugLog("✅ Linked contract to student: \(sdStudent.name)")
                }
                
                modelContext.insert(sdContract)
            }
            
            // Force save immediately
            try modelContext.save()
            debugLog("✅ Contract saved to SwiftData")
            
            // Auto-enroll student in assigned programs
            enrollStudentInAssignedPrograms(studentId: contract.studentId, programAssignments: contract.programAssignments)
            
            // Refresh caches synchronously
            refreshCachesSync()
            invalidateContractCache() // Performance: invalidate lookup cache
            debugLog("✅ Caches refreshed, cachedContracts count: \(cachedContracts.count)")
            
            // Notify observers
            objectWillChange.send()
        } catch {
            debugLog("❌ Failed to add/update contract: \(error)")
        }
        
        // Also sync to Supabase immediately
        if SupabaseManager.shared.isConnected {
            Task {
                do {
                    let dto = SupabaseContract(from: contract)
                    try await SupabaseManager.shared.upsert(into: "contracts", data: dto)
                    debugLog("✅ Contract synced to Supabase")
                } catch {
                    debugLog("⚠️ Failed to sync contract to Supabase: \(error)")
                }
            }
        }
    }
    
    func updateContract(_ contract: Contract) {
        debugLog("📝 updateContract called for contract ID: \(contract.id), studentId: \(contract.studentId)")
        
        // First try to find existing contract - fetch ALL contracts to debug
        do {
            let allDescriptor = FetchDescriptor<SDContract>()
            let allContracts = try modelContext.fetch(allDescriptor)
            debugLog("📝 Total contracts in SwiftData: \(allContracts.count)")
            for c in allContracts {
                debugLog("   - Contract ID: \(c.id), studentId: \(c.studentId), number: \(c.contractNumber)")
            }
            
            let contractId = contract.id
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == contractId })
            let existingContracts = try modelContext.fetch(descriptor)
            debugLog("📝 Found \(existingContracts.count) existing contracts with ID \(contractId)")
            
            if let sdContract = existingContracts.first {
                debugLog("📝 Updating existing contract...")
                sdContract.contractNumber = contract.contractNumber
                sdContract.contractType = contract.contractType
                sdContract.enrollmentDate = contract.enrollmentDate  // CRITICAL: was missing
                sdContract.attendedSessionIds = contract.attendedSessionIds  // CRITICAL: was missing
                sdContract.totalSessions = contract.totalSessions
                sdContract.attendedSessions = contract.attendedSessions
                sdContract.weeklyAttendance = contract.weeklyAttendance
                sdContract.startDate = contract.startDate
                sdContract.expiryDate = contract.expiryDate
                sdContract.pricePerSession = contract.pricePerSession
                sdContract.totalAmount = contract.totalAmount
                sdContract.amountPaid = contract.amountPaid
                sdContract.isSigned = contract.isSigned
                sdContract.signedDate = contract.signedDate
                sdContract.jerseyGiven = contract.jerseyGiven
                sdContract.jerseyGivenDate = contract.jerseyGivenDate
                sdContract.ballGiven = contract.ballGiven
                sdContract.ballGivenDate = contract.ballGivenDate
                sdContract.jerseyNumber = contract.jerseyNumber
                sdContract.jerseySize = contract.jerseySize
                sdContract.notes = contract.notes
                sdContract.manualStatus = contract.manualStatus
                sdContract.programAssignments = contract.programAssignments
                sdContract.historicalSessionsConsumed = contract.historicalSessionsConsumed
                sdContract.updatedAt = Date()
                debugLog("📝 attendedSessionIds count: \(contract.attendedSessionIds.count)")
                
                // Force save immediately
                try modelContext.save()
                debugLog("✅ Contract saved to SwiftData")
                
                // Auto-enroll student in assigned programs
                enrollStudentInAssignedPrograms(studentId: contract.studentId, programAssignments: contract.programAssignments)
                
                // Refresh caches synchronously
                refreshCachesSync()
                invalidateContractCache() // Performance: invalidate lookup cache
                debugLog("✅ Caches refreshed, cachedContracts count: \(cachedContracts.count)")
                
                // Notify observers
                objectWillChange.send()
                
                // Also sync to Supabase immediately
                if SupabaseManager.shared.isConnected {
                    var updatedContract = contract
                    updatedContract.updatedAt = Date()
                    Task {
                        do {
                            let dto = SupabaseContract(from: updatedContract)
                            try await SupabaseManager.shared.upsert(into: "contracts", data: dto)
                            debugLog("✅ Contract update synced to Supabase")
                        } catch {
                            debugLog("⚠️ Failed to sync contract update to Supabase: \(error)")
                        }
                    }
                }
            } else {
                // Contract not found locally - add as new
                debugLog("⚠️ Contract not found locally with ID \(contractId), adding as new")
                addContract(contract)
            }
        } catch {
            debugLog("❌ Failed to update contract: \(error)")
        }
    }
    
    func deleteContract(_ contract: Contract) {
        do {
            let descriptor = FetchDescriptor<SDContract>(predicate: #Predicate { $0.id == contract.id })
            if let sdContract = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdContract)
                invalidateContractCache() // Performance: invalidate lookup cache
                saveAndRefresh()
                
                // Also delete from Supabase
                if SupabaseManager.shared.isConnected {
                    Task {
                        do {
                            try await SupabaseManager.shared.delete(from: "contracts", id: contract.id)
                            debugLog("✅ Contract deleted from Supabase")
                        } catch {
                            debugLog("⚠️ Failed to delete contract from Supabase: \(error)")
                        }
                    }
                }
            }
        } catch {
            debugLog("❌ Failed to delete contract: \(error)")
        }
    }
    
    /// Auto-enroll student in programs assigned via contract
    private func enrollStudentInAssignedPrograms(studentId: UUID, programAssignments: [UUID]) {
        // Get unique program IDs from assignments
        let uniqueProgramIds = Set(programAssignments)
        guard !uniqueProgramIds.isEmpty else { return }
        
        debugLog("📝 Auto-enrolling student \(studentId) in \(uniqueProgramIds.count) program(s)")
        
        for programId in uniqueProgramIds {
            // Find the program and add student if not already enrolled
            if var program = cachedPrograms.first(where: { $0.id == programId }) {
                if !program.enrolledStudentIds.contains(studentId) {
                    program.enrolledStudentIds.append(studentId)
                    updateProgram(program)
                    debugLog("✅ Enrolled student in program: \(program.name)")
                } else {
                    debugLog("ℹ️ Student already enrolled in program: \(program.name)")
                }
            }
        }
    }
    
    @available(*, deprecated, message: "Use createContractWithType(for:contractType:pricePerSession:) instead. This helper hardcodes a 6-month expiry.")
    func createNewContract(for studentId: UUID, totalSessions: Int, pricePerSession: Double) -> Contract {
        let existingContracts = allContracts(for: studentId)
        let newContractNumber = (existingContracts.map { $0.contractNumber }.max() ?? 0) + 1
        let total = Double(totalSessions) * pricePerSession
        let expiry = Calendar.current.date(byAdding: .month, value: 6, to: Date())
        
        let contract = Contract(
            studentId: studentId,
            contractNumber: newContractNumber,
            totalSessions: totalSessions,
            startDate: Date(),
            expiryDate: expiry,
            pricePerSession: pricePerSession,
            totalAmount: total
        )
        
        addContract(contract)
        return contract
    }
    
    /// Create a new contract with a specific contract type (1x or 2x per week, 6 or 12 months)
    func createContractWithType(for studentId: UUID, contractType: ContractType, pricePerSession: Double) -> Contract {
        let existingContracts = allContracts(for: studentId)
        let newContractNumber = (existingContracts.map { $0.contractNumber }.max() ?? 0) + 1
        
        // Pay-as-you-go contracts have no fixed sessions or expiry
        let totalSessions = contractType.totalSessions ?? 0
        let total = contractType.isPayAsYouGo ? 0 : Double(totalSessions) * pricePerSession
        let expiry: Date? = contractType.durationMonths.flatMap { 
            Calendar.current.date(byAdding: .month, value: $0, to: Date()) 
        }
        
        var contract = Contract(
            studentId: studentId,
            contractNumber: newContractNumber,
            contractType: contractType,
            totalSessions: totalSessions,
            startDate: Date(),
            expiryDate: expiry,
            pricePerSession: pricePerSession,
            totalAmount: total
        )
        
        // Generate initial weekly attendance records (not for pay-as-you-go)
        contract.generateWeeklyRecords()
        
        addContract(contract)
        return contract
    }
    
    /// Update attendance for a specific week in a contract
    func updateWeeklyAttendance(contractId: UUID, weekRecord: WeeklyAttendanceRecord) {
        guard var contract = cachedContracts.first(where: { $0.id == contractId }) else { return }
        
        if let index = contract.weeklyAttendance.firstIndex(where: { $0.id == weekRecord.id }) {
            contract.weeklyAttendance[index] = weekRecord
        } else {
            contract.weeklyAttendance.append(weekRecord)
            contract.weeklyAttendance.sort { $0.weekStartDate < $1.weekStartDate }
        }
        
        // Recalculate attended sessions from weekly records
        contract.attendedSessions = contract.calculatedAttendedSessions
        contract.updatedAt = Date()
        
        updateContract(contract)
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
                sdSettings.coachAssistantEnabled = settings.coachAssistantEnabled
                sdSettings.claudeApiKey = settings.claudeApiKey
                sdSettings.groqApiKey = settings.groqApiKey
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
    
    var monthlyRevenue: Double {
        cachedPlayers.reduce(0) { $0 + $1.contractInfo.totalPaid }
    }
    
    var averageAttendanceRate: Double {
        let completedSessions = cachedSessionEvents.filter { $0.status == .completed }
        guard !completedSessions.isEmpty else { return 0 }
        return completedSessions.reduce(0) { $0 + $1.attendanceRate } / Double(completedSessions.count)
    }
    
    // MARK: - Authentication
    private static let loggedInCoachIdKey = "loggedInCoachId"
    
    func login(as staffCoach: StaffCoach) {
        // Update the main coach profile to match the staff coach
        // IMPORTANT: Preserve existing profileImageUrl and profileImageData to avoid losing profile picture
        let existingCoach = cachedCoach
        let updatedCoach = Coach(
            id: staffCoach.id,
            name: staffCoach.name,
            email: staffCoach.email ?? "",
            phone: staffCoach.phone,
            profileImageUrl: existingCoach.profileImageUrl,
            profileImageData: existingCoach.profileImageData,
            introduction: existingCoach.introduction.isEmpty ? "Staff coach at the organization" : existingCoach.introduction,
            yearsOfExperience: existingCoach.yearsOfExperience,
            certifications: existingCoach.certifications,
            specializations: staffCoach.specializations.isEmpty ? existingCoach.specializations : staffCoach.specializations,
            achievements: existingCoach.achievements,
            createdAt: staffCoach.createdAt,
            updatedAt: Date()
        )
        updateCoach(updatedCoach)
        
        // Save login state
        loggedInCoachId = staffCoach.id
        isLoggedIn = true
        UserDefaults.standard.set(staffCoach.id.uuidString, forKey: Self.loggedInCoachIdKey)
        
        debugLog("✅ Logged in as: \(staffCoach.name)")
    }
    
    /// Login using AuthManager's current user data
    func loginFromAuthManager() {
        guard let authUser = AuthManager.shared.currentUser else { return }

        // Reset fallback org cache so it re-derives from the authenticated org, not stale local data
        _cachedFallbackOrgId = nil

        // IMPORTANT: Preserve existing profile data (especially profileImageData) to avoid losing profile picture
        let existingCoach = cachedCoach
        
        // Use authUser's profileImageUrl only if we don't have local data
        // Local profileImageData takes precedence since cloud URL might be stale
        let finalImageUrl = existingCoach.profileImageData != nil ? existingCoach.profileImageUrl : (authUser.profileImageUrl ?? existingCoach.profileImageUrl)
        
        let updatedCoach = Coach(
            id: authUser.id,
            name: authUser.name,
            email: authUser.email,
            phone: existingCoach.phone,
            profileImageUrl: finalImageUrl,
            profileImageData: existingCoach.profileImageData,
            introduction: existingCoach.introduction,
            yearsOfExperience: existingCoach.yearsOfExperience,
            certifications: existingCoach.certifications,
            specializations: existingCoach.specializations,
            achievements: existingCoach.achievements,
            createdAt: authUser.createdAt,
            updatedAt: authUser.updatedAt
        )
        updateCoach(updatedCoach)
        
        // Check if there's a matching StaffCoach and sync
        // Try to match by email first, then by name (for organization accounts without email)
        var matchedStaffCoach: StaffCoach? = nil
        
        // Match by email if user has one
        if !authUser.email.isEmpty {
            matchedStaffCoach = staffCoaches.first(where: { $0.email?.lowercased() == authUser.email.lowercased() })
        }
        
        // If no email match, try matching by name (case-insensitive)
        if matchedStaffCoach == nil {
            matchedStaffCoach = staffCoaches.first(where: { 
                $0.name.lowercased() == authUser.name.lowercased() ||
                $0.chineseName?.lowercased() == authUser.name.lowercased()
            })
        }
        
        if let staffCoach = matchedStaffCoach {
            loggedInCoachId = staffCoach.id
            isLoggedIn = true
            UserDefaults.standard.set(staffCoach.id.uuidString, forKey: Self.loggedInCoachIdKey)
            debugLog("✅ Synced with StaffCoach: \(staffCoach.name)")
        } else {
            // No existing StaffCoach found - only create if this is NOT an organization account
            // Organization accounts should already have a corresponding StaffCoach created by admin
            if authUser.email.isEmpty {
                // This is an organization account - don't create duplicate, just log warning
                debugLog("⚠️ Organization account \(authUser.name) has no matching StaffCoach - admin should create one")
                loggedInCoachId = authUser.id
                isLoggedIn = true
                UserDefaults.standard.set(authUser.id.uuidString, forKey: Self.loggedInCoachIdKey)
            } else {
                // Regular user account - create a new StaffCoach
                let newStaffCoach = StaffCoach(
                    id: authUser.id,
                    name: authUser.name,
                    email: authUser.email,
                    phone: nil,
                    role: authUser.role == .admin ? .head : .assistant,
                    accessLevel: authUser.role == .admin ? .admin : .coachingStaff,
                    specializations: [],
                    ageGroups: AgeGroup.allCases,
                    avatarColor: .purple,
                    isActive: true,
                    hireDate: authUser.createdAt,
                    notes: "Created from authenticated account"
                )
                addStaffCoach(newStaffCoach)
                loggedInCoachId = newStaffCoach.id
                isLoggedIn = true
                UserDefaults.standard.set(newStaffCoach.id.uuidString, forKey: Self.loggedInCoachIdKey)
                debugLog("✅ Created new StaffCoach for: \(authUser.name)")
            }
        }
    }
    
    func logout() {
        // Clear login state
        loggedInCoachId = nil
        isLoggedIn = false
        _cachedFallbackOrgId = nil
        hasSkippedLogin = false
        UserDefaults.standard.removeObject(forKey: Self.loggedInCoachIdKey)
        UserDefaults.standard.removeObject(forKey: "hasSkippedLogin")
        // Also clear the sample data loaded flag so demo data reloads if user goes to guest mode
        UserDefaults.standard.removeObject(forKey: sampleDataLoadedKey)
        
        // Delete all SwiftData records so refreshAllCaches() cannot reload stale data
        deleteAllSwiftDataRecords()
        
        // Clear in-memory caches
        cachedStudents = []
        cachedPlayers = []
        cachedContracts = []
        cachedPrograms = []
        cachedMicroCycles = []
        cachedSessionEvents = []
        cachedDrills = []
        cachedMeasurements = []
        cachedCoach = Coach.default
        staffCoaches = []
        teams = []
        games = []
        locations = []
        reminders = []
        
        debugLog("👋 Logged out - all SwiftData records and caches cleared")
    }
    
    private func deleteAllSwiftDataRecords() {
        do {
            try modelContext.delete(model: SDStudent.self)
            try modelContext.delete(model: SDPlayer.self)
            try modelContext.delete(model: SDContract.self)
            try modelContext.delete(model: SDProgram.self)
            try modelContext.delete(model: SDMicroCycle.self)
            try modelContext.delete(model: SDSessionEvent.self)
            try modelContext.delete(model: SDDrill.self)
            try modelContext.delete(model: SDMeasurement.self)
            try modelContext.delete(model: SDStaffCoach.self)
            try modelContext.delete(model: SDTeam.self)
            try modelContext.delete(model: SDGame.self)
            try modelContext.delete(model: SDLocation.self)
            try modelContext.delete(model: SDCoach.self)
            debugLog("🗑️ All SwiftData records deleted on logout")
        } catch {
            debugLog("❌ Failed to delete SwiftData records on logout: \(error)")
        }
    }
    
    func skipLogin() {
        hasSkippedLogin = true
        UserDefaults.standard.set(true, forKey: "hasSkippedLogin")
        debugLog("⏭️ Skipped login - continuing as guest")
    }
    
    // MARK: - Sample Data for Guest Mode
    private let sampleDataLoadedKey = "sampleDataLoaded_v2"
    
    /// Load rich sample data for guest/demo mode (screenshot-ready)
    func loadSampleDataIfNeeded() {
        // Only load if in guest mode and sample data hasn't been loaded
        guard AuthManager.shared.isGuestMode else { return }
        guard !UserDefaults.standard.bool(forKey: sampleDataLoadedKey) else {
            debugLog("📦 Demo mode already set up")
            return
        }
        
        debugLog("📦 Setting up demo mode...")
        
        // Sample data generation removed
        
        UserDefaults.standard.set(true, forKey: sampleDataLoadedKey)
        debugLog("✅ Demo mode ready")
    }
    
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
    
    func restoreLoginState() {
        // Check if user previously skipped login
        if UserDefaults.standard.bool(forKey: "hasSkippedLogin") {
            hasSkippedLogin = true
            debugLog("🔄 Restored skipped login state")
            return
        }
        
        if let savedIdString = UserDefaults.standard.string(forKey: Self.loggedInCoachIdKey),
           let savedId = UUID(uuidString: savedIdString) {
            // Find the staff coach with this ID
            if let staffCoach = staffCoaches.first(where: { $0.id == savedId }) {
                loggedInCoachId = savedId
                isLoggedIn = true
                debugLog("🔄 Restored login state for: \(staffCoach.name)")
            } else {
                // Staff coach no longer exists, clear login state
                UserDefaults.standard.removeObject(forKey: Self.loggedInCoachIdKey)
            }
        }
    }
    
    var currentLoggedInCoach: StaffCoach? {
        guard let id = loggedInCoachId else { return nil }
        return staffCoaches.first { $0.id == id }
    }
    
    /// Current access level of the logged-in coach (defaults to admin if not logged in for backward compatibility)
    var currentAccessLevel: AccessLevel {
        currentLoggedInCoach?.accessLevel ?? .admin
    }
    
    /// Check if current user is admin
    var isAdmin: Bool {
        currentAccessLevel == .admin
    }
    
    // MARK: - Access-Controlled Data
    // These properties return filtered data based on the logged-in coach's access level
    
    /// Students visible to the current coach (all for admin, assigned/created for coaching staff)
    var accessibleStudents: [Student] {
        guard isLoggedIn, !isAdmin, let coachId = loggedInCoachId else {
            return cachedStudents
        }
        // Coaching staff can see students in their programs or that they created
        let myProgramIds = Set(cachedPrograms.filter { $0.coachId == coachId }.map { $0.id })
        let studentsInMyPrograms = Set(cachedPrograms.filter { myProgramIds.contains($0.id) }.flatMap { $0.enrolledStudentIds })
        return cachedStudents.filter { studentsInMyPrograms.contains($0.id) || $0.createdByCoachId == coachId }
    }
    
    // MARK: - Dashboard-scoped (always filtered to the logged-in coach, even for admins)

    /// Programs owned by / assigned to the currently logged-in coach — always scoped, used by the home screen
    var myPrograms: [Program] {
        guard isLoggedIn, let coachId = loggedInCoachId ?? Optional(coach.id) else {
            return cachedPrograms
        }
        return cachedPrograms.filter { $0.coachId == coachId || $0.createdByCoachId == coachId }
    }

    /// Sessions belonging to the logged-in coach's programs or created by them — always scoped, used by the home screen
    var mySessions: [SessionEvent] {
        guard isLoggedIn, let coachId = loggedInCoachId ?? Optional(coach.id) else {
            return cachedSessionEvents
        }
        let myProgramIds = Set(myPrograms.map { $0.id })
        return cachedSessionEvents.filter {
            ($0.programId != nil && myProgramIds.contains($0.programId!)) || $0.createdByCoachId == coachId || $0.assignedCoachIds.contains(coachId)
        }
    }

    /// Students in the logged-in coach's programs or created by them — always scoped, used by the home screen
    var myStudents: [Student] {
        guard isLoggedIn, let coachId = loggedInCoachId ?? Optional(coach.id) else {
            return cachedStudents
        }
        let myProgramIds = Set(myPrograms.map { $0.id })
        let studentsInMyPrograms = Set(cachedPrograms.filter { myProgramIds.contains($0.id) }.flatMap { $0.enrolledStudentIds })
        return cachedStudents.filter { studentsInMyPrograms.contains($0.id) || $0.createdByCoachId == coachId }
    }

    /// Programs visible to the current coach
    var accessiblePrograms: [Program] {
        guard isLoggedIn, !isAdmin, let coachId = loggedInCoachId else {
            return cachedPrograms
        }
        // Coaching staff can see programs assigned to them or created by them
        return cachedPrograms.filter { $0.coachId == coachId || $0.createdByCoachId == coachId }
    }
    
    /// Sessions visible to the current coach
    var accessibleSessions: [SessionEvent] {
        guard isLoggedIn, !isAdmin, let coachId = loggedInCoachId else {
            return cachedSessionEvents
        }
        // Coaching staff can see sessions for their programs, created by them, or assigned to them
        let myProgramIds = Set(accessiblePrograms.map { $0.id })
        return cachedSessionEvents.filter {
            ($0.programId != nil && myProgramIds.contains($0.programId!)) || $0.createdByCoachId == coachId || $0.assignedCoachIds.contains(coachId)
        }
    }
    
    /// Contracts visible to the current coach
    var accessibleContracts: [Contract] {
        guard isLoggedIn, !isAdmin, let coachId = loggedInCoachId else {
            return cachedContracts
        }
        // Coaching staff can see contracts for their students
        let myStudentIds = Set(accessibleStudents.map { $0.id })
        return cachedContracts.filter { myStudentIds.contains($0.studentId) || $0.createdByCoachId == coachId }
    }
    
    /// Teams visible to the current coach
    var accessibleTeams: [Team] {
        guard isLoggedIn, !isAdmin, let coachId = loggedInCoachId else {
            return teams
        }
        // Coaching staff can see teams they coach or created
        return teams.filter { $0.coachId == coachId || $0.createdByCoachId == coachId }
    }
    
    /// Games visible to the current coach
    var accessibleGames: [Game] {
        guard isLoggedIn, !isAdmin, let _ = loggedInCoachId else {
            return games
        }
        // Coaching staff can see games involving their teams
        let myTeamIds = Set(accessibleTeams.map { $0.id })
        return games.filter { myTeamIds.contains($0.homeTeamId) || myTeamIds.contains($0.awayTeamId) }
    }
    
    // MARK: - Permission Checks
    
    /// Check if current user can edit a specific item
    func canEdit(createdByCoachId: UUID?) -> Bool {
        guard let coach = currentLoggedInCoach else { return true } // Not logged in = full access (backward compat)
        return coach.canEdit(createdByCoachId: createdByCoachId)
    }
    
    /// Check if current user can delete a specific item
    func canDelete(createdByCoachId: UUID?) -> Bool {
        guard let coach = currentLoggedInCoach else { return true }
        return coach.canDelete(createdByCoachId: createdByCoachId)
    }
    
    /// Check if current user can view a specific item
    func canView(assignedCoachId: UUID?, createdByCoachId: UUID?) -> Bool {
        guard let coach = currentLoggedInCoach else { return true }
        return coach.canView(assignedCoachId: assignedCoachId, createdByCoachId: createdByCoachId)
    }
    
    /// Check if current user can manage organization settings
    var canManageOrganization: Bool {
        currentLoggedInCoach?.accessLevel.canManageOrganization ?? true
    }
    
    /// Check if current user can view financials
    var canViewFinancials: Bool {
        currentLoggedInCoach?.accessLevel.canViewFinancials ?? true
    }
    
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
                sdCoach.accessLevel = coach.accessLevel
                sdCoach.specializations = coach.specializations
                sdCoach.ageGroups = coach.ageGroups
                sdCoach.avatarColor = coach.avatarColor
                sdCoach.isActive = coach.isActive
                sdCoach.hireDate = coach.hireDate
                sdCoach.notes = coach.notes
                sdCoach.profileImageData = coach.profileImageData
                sdCoach.profileImageUrl = coach.profileImageUrl
                sdCoach.updatedAt = Date()
                saveAndRefresh()
            }
        } catch {
            debugLog("❌ Failed to update staff coach: \(error)")
        }
    }
    
    func deleteStaffCoach(_ coach: StaffCoach) {
        debugLog("🗑️ [DELETE-COACH] Starting deletion of: \(coach.name) (ID: \(coach.id))")
        do {
            let descriptor = FetchDescriptor<SDStaffCoach>(predicate: #Predicate { $0.id == coach.id })
            if let sdCoach = try modelContext.fetch(descriptor).first {
                modelContext.delete(sdCoach)
                debugLog("🗑️ [DELETE-COACH] Deleted from local SwiftData: \(coach.name)")
                saveAndRefresh()
                debugLog("✅ [DELETE-COACH] Local deletion completed, cache refreshed")
                
                // Also delete from Supabase for permanent deletion
                Task {
                    do {
                        try await SupabaseManager.shared.delete(from: "staff_coaches", id: coach.id)
                        debugLog("✅ [DELETE-COACH] Deleted from Supabase: \(coach.name)")
                    } catch {
                        debugLog("⚠️ [DELETE-COACH] Failed to delete from Supabase: \(error)")
                    }
                }
            } else {
                debugLog("⚠️ [DELETE-COACH] Staff coach not found in local database: \(coach.name)")
                // Still refresh cache in case of sync issues
                refreshCachesSync()
            }
        } catch {
            debugLog("❌ [DELETE-COACH] Failed to delete staff coach: \(error)")
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
    
    // MARK: - Age Category CRUD
    func addAgeCategory(_ category: CustomAgeCategory) {
        ageCategories.append(category)
        saveAgeCategories()  // Persist locally
        
        // Sync to Supabase
        Task {
            do {
                let dto = SupabaseAgeCategory(from: category)
                try await SupabaseManager.shared.upsert(into: "age_categories", data: dto)
                debugLog("✅ Age category synced to Supabase: \(category.name)")
            } catch {
                debugLog("❌ Failed to sync age category to Supabase: \(error)")
            }
        }
    }
    
    func updateAgeCategory(_ category: CustomAgeCategory) {
        if let index = ageCategories.firstIndex(where: { $0.id == category.id }) {
            ageCategories[index] = category
        }
        saveAgeCategories()  // Persist locally
        
        // Sync to Supabase
        Task {
            do {
                let dto = SupabaseAgeCategory(from: category)
                try await SupabaseManager.shared.upsert(into: "age_categories", data: dto)
                debugLog("✅ Age category updated in Supabase: \(category.name)")
            } catch {
                debugLog("❌ Failed to update age category in Supabase: \(error)")
            }
        }
    }
    
    func deleteAgeCategory(_ category: CustomAgeCategory) {
        ageCategories.removeAll { $0.id == category.id }
        saveAgeCategories()  // Persist locally
        
        // Delete from Supabase
        Task {
            do {
                try await SupabaseManager.shared.delete(from: "age_categories", id: category.id)
                debugLog("✅ Age category deleted from Supabase: \(category.name)")
            } catch {
                debugLog("❌ Failed to delete age category from Supabase: \(error)")
            }
        }
    }
    
    /// Fetch age categories from Supabase and merge with local
    func fetchAgeCategoriesFromSupabase() async {
        do {
            let dtos: [SupabaseAgeCategory] = try await SupabaseManager.shared.fetch(from: "age_categories")
            let fetchedCategories = dtos.map { $0.toAgeCategory() }
            
            await MainActor.run {
                // Merge: keep local defaults if not in remote, add remote ones
                for fetched in fetchedCategories {
                    if let index = ageCategories.firstIndex(where: { $0.id == fetched.id }) {
                        // Update existing
                        ageCategories[index] = fetched
                    } else {
                        // Add new
                        ageCategories.append(fetched)
                    }
                }
                saveAgeCategories()  // Persist locally after sync
                debugLog("✅ Fetched \(fetchedCategories.count) age categories from Supabase")
            }
        } catch {
            debugLog("❌ Failed to fetch age categories from Supabase: \(error)")
        }
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
            
            // Skip fullSync if in batch mode (will sync when batch ends)
            guard !isBatchMode else {
                debugLog("  ↳ Skipping fullSync (batch mode)")
                return
            }
            
            // Always do full sync when connected - download first to get latest, then upload
            if SupabaseManager.shared.isConnected {
                Task {
                    await fullSync()
                }
            }
        } catch {
            debugLog("❌ Failed to save: \(error)")
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    /// Synchronous cache refresh for immediate UI updates after save
    private func refreshCachesSync() {
        do {
            let sdStudents = try modelContext.fetch(FetchDescriptor<SDStudent>())
            cachedStudents = sdStudents.map { $0.toStruct() }
            
            let sdPlayers = try modelContext.fetch(FetchDescriptor<SDPlayer>())
            cachedPlayers = sdPlayers.map { $0.toStruct() }
            
            let sdContracts = try modelContext.fetch(FetchDescriptor<SDContract>())
            cachedContracts = sdContracts.map { $0.toStruct() }
            
            let sdPrograms = try modelContext.fetch(FetchDescriptor<SDProgram>())
            cachedPrograms = sdPrograms.map { $0.toStruct() }
            
            let sdMicroCycles = try modelContext.fetch(FetchDescriptor<SDMicroCycle>())
            cachedMicroCycles = sdMicroCycles.map { $0.toStruct() }
            
            let sdSessions = try modelContext.fetch(FetchDescriptor<SDSessionEvent>())
            cachedSessionEvents = sdSessions.map { $0.toStruct() }
            
            let sdDrills = try modelContext.fetch(FetchDescriptor<SDDrill>())
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
            
            debugLog("📊 Caches refreshed sync: \(cachedStudents.count) students, \(cachedPrograms.count) programs, \(teams.count) teams, \(staffCoaches.count) coaches, \(locations.count) locations")
            
            // Load reminders from UserDefaults
            loadReminders()
        } catch {
            debugLog("❌ Failed to refresh caches sync: \(error)")
        }
    }
    
    // MARK: - Reminders (SwiftData + Supabase Sync)
    
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
            
            // Sync to Supabase
            if SupabaseManager.shared.isConnected {
                Task {
                    await syncReminderToCloud(newReminder)
                }
            }
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
                
                // Sync to Supabase
                if SupabaseManager.shared.isConnected {
                    Task {
                        await syncReminderToCloud(updatedReminder)
                    }
                }
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
                
                // Delete from Supabase
                if SupabaseManager.shared.isConnected {
                    Task {
                        try? await SupabaseManager.shared.delete(from: "reminders", id: reminder.id)
                    }
                }
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
    
    /// Sync a single reminder to Supabase
    private func syncReminderToCloud(_ reminder: Reminder) async {
        do {
            let supabaseReminder = SupabaseReminder(from: reminder)
            try await SupabaseManager.shared.upsert(into: "reminders", data: supabaseReminder)
            debugLog("☁️ Reminder synced to cloud: \(reminder.title)")
        } catch {
            debugLog("❌ Failed to sync reminder to cloud: \(error)")
        }
    }
    
    /// Sync all reminders from Supabase (for login/refresh)
    func syncRemindersFromCloud() async {
        guard SupabaseManager.shared.isConnected else { return }
        guard let currentCoachId = loggedInCoachId ?? Optional(coach.id) else { return }
        
        do {
            // Fetch all reminders for this organization (scoped, not global)
            let orgReminders: [SupabaseReminder] = try await fetchForOrganization(from: "reminders")
            
            // Filter to: my own reminders OR reminders shared with me
            let allMyReminders = orgReminders
                .map { $0.toReminder() }
                .filter { $0.isVisibleTo(coachId: currentCoachId) }
            
            // Save to SwiftData
            for reminder in allMyReminders {
                let descriptor = FetchDescriptor<SDReminder>(predicate: #Predicate { $0.id == reminder.id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Update if cloud is newer
                    if reminder.updatedAt > existing.updatedAt {
                        existing.update(from: reminder)
                    }
                } else {
                    // Insert new
                    modelContext.insert(SDReminder.from(reminder))
                }
            }
            
            try modelContext.save()
            loadReminders()
            debugLog("☁️ Synced \(allMyReminders.count) reminders from cloud")
        } catch {
            debugLog("❌ Failed to sync reminders from cloud: \(error)")
        }
    }
    
    /// Upload all local reminders to cloud
    func syncRemindersToCloud() async {
        guard SupabaseManager.shared.isConnected else { return }
        
        do {
            let supabaseReminders = reminders.map { SupabaseReminder(from: $0) }
            try await SupabaseManager.shared.batchUpsert(into: "reminders", data: supabaseReminders)
            debugLog("☁️ Uploaded \(supabaseReminders.count) reminders to cloud")
        } catch {
            debugLog("❌ Failed to upload reminders to cloud: \(error)")
        }
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
