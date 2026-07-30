# HoopWise — Project Context

## What this is
Basketball coaching management app. SwiftUI + SwiftData. iOS is the
primary, mature target; a macOS version (HoopwiseMac) is in active
development and currently raw. Version 2, Build 2.

## Sync architecture
- CloudKit, via SwiftData's built-in integration. ModelConfiguration in
  Hoopwise/Managers/SwiftDataManager.swift sets
  cloudKitDatabase: .private("iCloud.com.hoopwise.Hoopwise").
- There is NO custom sync engine: no CKSyncEngine, no CKRecord
  operations, no NSPersistentCloudKitContainer. Sync is automatic.
- Both targets already have the iCloud capability, CloudKit enabled, and
  the SAME container. Never create a second container.
- Supabase is DEAD. The ~30 supabase_*.sql files and any remaining
  Supabase code are legacy artifacts from a previous architecture.
  Do not build against them. They are pending deletion.

## Known broken things (do not mistake these for working)
- The iOS "Sync Now" button and "Auto Sync" toggle are placebos.
  Sync Now calls refreshAllCaches(), which only re-reads the local
  SwiftData store into memory. The toggle writes autoSyncEnabled to
  SDCoach and gates nothing. The footer copy claiming it syncs with
  iCloud is false.
- syncFromCloud() and syncToCloud() in SwiftDataManager are no-ops that
  only stamp lastSyncDate.
- SyncStatusView reads a UserDefaults key lastCloudKitSyncDate that
  nothing ever writes, so "Last synced" is permanently blank.
- CKContainer.default() is used where an explicit container is required.
  default() resolves to iCloud.{bundleID}, which does not exist for
  either target. Always use
  CKContainer(identifier: "iCloud.com.hoopwise.Hoopwise").
- getLocalStorageURL() returns a URL that is never passed to
  ModelConfiguration. It is dead code and its surrounding comments about
  platform-specific storage are stale.
- CloudKit failures after successful ModelContainer init are silent.
  Nothing surfaces them. This is the root cause of most debugging pain
  on this project — prefer fixing error surfacing over guessing.
- The 121 drills visible in both apps are seeded locally every launch by
  syncSampleDrills() from bundled DrillItem.samples. Their presence is
  NOT evidence that CloudKit sync works.

## History — read before touching git
- This repo was created fresh in July 2026 after migrating to a new
  macOS user account. Single-root history is intentional; all pre-v2.2
  history, branches, and worktrees were deliberately discarded.
- NEVER create git worktrees in this repo. Work on branches in this
  checkout only. The previous setup accumulated 12 orphaned worktrees
  from AI agent sessions and it poisoned the repo.

## Targets
- Hoopwise (iOS) — primary, builds and runs
- HoopwiseMac (macOS) — in progress; has its own HoopwiseMac/Views/ and
  HoopwiseMac/HoopwiseMac.entitlements
- HoopwiseTests, HoopwiseUITests, SAMWidgetsExtension
- Bundle IDs: OKTO.SAMp (iOS), OKTO.SAMp.HoopwiseMac (Mac). Legacy
  names — do not change either; provisioning and the iCloud container
  depend on current values.
- Signing: automatic, team Beidy Dubhe Franco Parra

## Hard rules
1. TARGET MEMBERSHIP: every new file in Hoopwise/Models, Managers,
   Services, or Utilities MUST be added to BOTH Hoopwise and
   HoopwiseMac. This is the #1 recurring bug from past agent sessions —
   files created iOS-only broke the Mac build with hundreds of cascade
   errors. Views are per-platform; shared layers are both-targets.
2. NEVER commit Configuration.xcconfig. It is gitignored and holds AI
   API keys (Anthropic/Gemini/Groq) for the Assistant Coach feature,
   surfaced via INFOPLIST_KEY_* substitutions. If it is missing, the
   build fails with "Unable to open base configuration reference file."
3. Platform-specific code in shared files gets #if os(iOS) /
   #if os(macOS) guards. Prefer platform-neutral types (Data over
   UIImage) in models. Once a view diverges more than trivially, split
   it into a separate Mac view rather than branching heavily.
4. Do not add .claude/, build/, or xcuserdata to git. Check .gitignore
   before staging.
5. Do not change SwiftData model schemas without explicit approval. The
   schema is already CloudKit-compatible and iOS depends on it.
6. Never replicate a non-functional control to a second platform. Fix
   it on both or remove it.

## macOS gotchas specific to this setup
- The macOS user account is new. A Mac with no system-level iCloud
  account, or one signed into a different Apple ID than the iPhone,
  gets an empty CloudKit private database with no error. Signing into
  an Apple ID in Xcode is a developer credential and does NOT provide
  a system iCloud account.
- CloudKit Development and Production are separate databases with
  separate data. Neither entitlements file sets
  com.apple.developer.icloud-container-environment, so Xcode picks by
  build type: debug to Development, archive/TestFlight/App Store to
  Production. A debug Mac build will never see data written by a
  TestFlight iOS build.
- Console noise about hapticpatternlibrary.plist and
  UIKBFeedbackGenerator is ignorable iOS haptics logging on macOS.

## Current state (July 2026)
- HoopwiseMac builds and runs. It shows the local drill seed; athletes,
  sessions, and programs are empty because CloudKit delivers nothing.
  This is total sync failure, not selective.
- Mac Settings (HoopwiseMac/Views/MacSettingsView.swift) has only
  General / Profile / Data, with a Refresh All Data button that only
  refreshes local caches. No sync state, no account status, no
  timestamp.
- Roadmap: (1) diagnose and fix CloudKit sync end to end with real
  status and error surfacing on both platforms, (2) bundle
  import/export via the existing HoopwiseBundle.swift and
  HoopwiseBundleImporter.swift, (3) written iOS-vs-Mac feature parity
  audit, (4) Mac-idiomatic UI: menu bar commands, per-view toolbars,
  Table views, designed empty states, window state restoration,
  (5) delete dead Supabase code and SQL files.

## Build commands
- iOS:  xcodebuild -project Hoopwise.xcodeproj -scheme Hoopwise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Mac:  xcodebuild -project Hoopwise.xcodeproj -scheme HoopwiseMac -destination 'platform=macOS' build
