import SwiftUI
import SwiftData

@main
struct SAMApp: App {
    // Use SwiftDataManager instead of legacy DataManager
    @StateObject private var dataManager = SwiftDataManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var isInitialized = false
    @State private var autoSyncTask: Task<Void, Never>? = nil
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    // Loading state - Hoopwise branded splash
                    ZStack {
                        Color(red: 30/255, green: 58/255, blue: 138/255)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image("HoopwiseLogoWhite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                } else {
                    // Route based on auth state
                    switch authManager.authState {
                    case .unknown:
                        // First launch - go directly to guest mode with sample data
                        mainAppContent
                            .onAppear {
                                // Enter guest mode and load sample data
                                if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                                    authManager.enterGuestMode()
                                    dataManager.loadSampleDataIfNeeded()
                                }
                            }
                        
                    case .onboarding, .needsOrganization:
                        // User explicitly started onboarding - show it
                        OnboardingView()
                            .environmentObject(dataManager)
                            .modelContainer(dataManager.modelContainer)
                        
                    case .unauthenticated:
                        // Guest mode - show main app with sample data
                        mainAppContent
                            .onAppear {
                                dataManager.loadSampleDataIfNeeded()
                            }
                        
                    case .authenticated:
                        // Fully authenticated - sync with auth user and show main app
                        mainAppContent
                            .onAppear {
                                // Sync coach profile with authenticated user
                                dataManager.loginFromAuthManager()
                                // Clear sample data when authenticated
                                dataManager.clearSampleDataIfNeeded()
                            }
                    }
                }
            }
            .task {
                await initializeApp()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
        .onChange(of: scenePhase) { oldPhase, newPhase in
            debugLog("📱 Scene phase changed: \(oldPhase) -> \(newPhase)")
            
            switch newPhase {
            case .background, .inactive:
                // SwiftData auto-saves, but sync to cloud
                debugLog("💾 App going to background...")
                stopAutoSyncLoop()
                Task {
                    if dataManager.appSettings.autoSyncEnabled {
                        await dataManager.syncToCloud()
                    }
                }
            case .active:
                // Refresh cache when app becomes active (but not on first launch)
                guard isInitialized else { return }
                debugLog("📱 App becoming active - refreshing cache...")
                Task {
                    // Always refresh local cache first
                    await dataManager.refreshAllCaches()
                    
                    // Then full sync if connected
                    if SupabaseManager.shared.isConnected {
                        await dataManager.fullSync()
                    }
                }

                startAutoSyncLoopIfNeeded()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Main App Content
    @ViewBuilder
    private var mainAppContent: some View {
        #if os(macOS)
        MacContentView()
            .environmentObject(dataManager)
            .modelContainer(dataManager.modelContainer)
            .frame(minWidth: 900, minHeight: 600)
        #else
        MainTabView()
            .environmentObject(dataManager)
            .modelContainer(dataManager.modelContainer)
        #endif
    }
    
    private func initializeApp() async {
        guard !isInitialized else { return }
        
        debugLog("🚀 App launched - initializing...")
        
        // Initialize Supabase connection FIRST
        await SupabaseManager.shared.initialize()
        
        // Initialize auth manager
        await authManager.initialize()
        
        // Then load data (will migrate from UserDefaults if needed)
        await dataManager.loadAllData()
        
        // Restore legacy login state after data is loaded
        dataManager.restoreLoginState()
        
        // Start session status monitoring
        await SessionStatusMonitor.shared.startMonitoring(dataManager: dataManager)
        
        // Mark initialized
        isInitialized = true
        
        debugLog("✅ App initialization complete")

        // Start auto sync loop if app launches directly into active state
        if scenePhase == .active {
            startAutoSyncLoopIfNeeded()
        }
    }

    // MARK: - Auto Sync Loop
    private func startAutoSyncLoopIfNeeded() {
        // Only run while active and when auto-sync is enabled
        guard scenePhase == .active else { return }
        guard dataManager.appSettings.autoSyncEnabled else { return }
        guard SupabaseManager.shared.isConnected else { return }

        // Avoid duplicate loops
        guard autoSyncTask == nil else { return }

        autoSyncTask = Task {
            // Small delay to avoid racing with initial refresh/fullSync
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            while !Task.isCancelled {
                guard dataManager.appSettings.autoSyncEnabled else { break }
                guard SupabaseManager.shared.isConnected else {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    continue
                }

                await dataManager.fullSync()

                // Sync interval (2 minutes)
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }

    private func stopAutoSyncLoop() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }
}
