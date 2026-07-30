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

## Sync observability (fixed July 2026)
- CloudSyncMonitor (Hoopwise/Services/, BOTH targets) observes
  NSPersistentCloudKitContainer.eventChangedNotification, which SwiftData's
  CloudKit integration posts for every setup/import/export including
  failures. It publishes account status, activity, last real sync, and a
  readable error, and writes the lastCloudKitSyncDate key. Use it rather
  than adding new ad-hoc status checks.
- Always use CKContainer(identifier: "iCloud.com.hoopwise.Hoopwise").
  CKContainer.default() resolves to iCloud.{bundleID}, which exists for
  neither target.
- The iOS placebo Sync Now / Auto Sync controls are gone. Sync Now became
  "Reload Data" (it only re-reads local caches, which is what it always
  did); the inert Auto Sync toggle was removed. SDCoach.autoSyncEnabled
  remains in the schema, unused, so the schema is unchanged.
- Mac Settings has a Sync tab with account status, activity, last sync,
  errors, and the CloudKit environment.

## Known broken things (do not mistake these for working)
- syncFromCloud() and syncToCloud() in SwiftDataManager are no-ops that
  only stamp lastSyncDate.
- getLocalStorageURL() returns a URL that is never passed to
  ModelConfiguration. It is dead code and its surrounding comments about
  platform-specific storage are stale.
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
7. ADDING A SWIFTDATA MODEL is a five-step operation, in this order.
   Skipping 3 or 4 makes Mac write record types Production does not know,
   which fails silently — the failure mode this project already suffers.
   a. New model in Hoopwise/Models/SwiftData/, BOTH target memberships.
      Every property needs a default or must be optional; no
      @Attribute(.unique); all relationships optional. CloudKit requires
      this and the existing models already follow it.
   b. Register it in the Schema([...]) array in SwiftDataManager.
   c. Run both targets once in Debug so SwiftData materializes the
      Development schema.
   d. Deploy Development to Production in CloudKit Console by hand.
      Nothing automates this.
   e. Ship an iOS build carrying the types — even with no UI — before Mac
      authoring writes any of them.
   Define new record types in ONE pass and deploy once. Each extra deploy
   costs another iOS release, and TestFlight review time gates it. Empty
   models cost nothing to carry.

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

## Product direction (decided July 2026)
- The iOS UI is FROZEN. The phone is an operations terminal. The only
  permitted iOS changes are contract work and outright bugs (data loss,
  crashes) — not interface work.
- iOS/Mac feature parity is CANCELLED as a goal. Do not pursue it.
- The Mac app becomes an authoring tool for basketball research and video
  production: court/play editor, PDF play sheets, animation export for
  DaVinci Resolve, and a linked knowledge base.

## Current state (July 2026)
- CloudKit sync works. Both apps see the same private-database data.
- HoopwiseMac builds and runs; Settings has General / Profile / Sync /
  Data.
- Roadmap: (1) contracts — payments ledger + travel fee, (2) persist
  Play/CourtScheme and define the four new record types, (3) deploy
  schema Dev→Production, (4) ship one iOS build carrying the new types,
  (5) Mac court editor UI, (6) PDF then PNG then ProRes export,
  (7) knowledge base, (8) bundle import/export via HoopwiseBundle.swift,
  (9) Mac-idiomatic UI polish, (10) delete dead Supabase code and SQL.

## Court / play authoring decisions (July 2026)
- Coordinate space is COURT-FEET, not normalized 0-1. The legacy
  CourtPlayer.position was 0-1; nothing was persisted, so it converted for
  free. Never reintroduce a normalized space.
- Full court 50x94 with courtMode (.half / .full). Half-court alone cannot
  express pressBreak or fastBreak, which are existing PlayCategory cases.
- courtStandard (.nba / .fiba) is part of the model, not the renderer.
  FIBA is 28m x 15m with a 6.75m arc and a rectangular key; NBA uses a
  23'9" arc. Coaching happens under FIBA rules, analysis content is NBA.
  Retrofitting this after diagrams exist is a coordinate-semantics
  migration, so it ships with the model.
- Time model is KEYFRAMED TRACKS, not frames. The legacy
  CourtFrame/order shape is a discrete slideshow. Tracks carry t, easing,
  and path type. The entity vocabulary (CourtPlayer, CourtMovement,
  MovementType, pathStyle, lineStyle) is kept and ported.
- A play is a TREE of read nodes, each branch a defensive read with its
  own tracks. This is the core structure, not a feature.
- NO SceneKit, NO RealityKit. Source of truth is 2D court-feet. The
  oblique look is a perspective projection (3x3 homography) of the court
  plane applied at render time, with an animatable camera-angle parameter.
  Reasons: PDF export requires vector output, one model must serve both
  PDF and video, and 3D scene graphs would shadow the read-tree state.
- Player pucks are BILLBOARDED, not projected. Project the puck's ground
  point through the homography, then draw the puck upright at that point
  scaled by depth. A circle pushed through the homography shears into a
  wrong-looking ellipse. The cast shadow IS the projected ellipse.
- Diagram geometry is stored as a Codable JSON blob in a Data column, not
  a normalized entity graph. A diagram is a document — always loaded and
  saved whole, never queried by keyframe. This also keeps the CloudKit
  record-type count low.
- External constraint driving all of the above: DaVinci Resolve Fusion
  chokes on ten player spheres in Merge3D groups at 16GB RAM (Resolve
  ~9GB, swap engaging), which forces baking comps to rendered video.
  Exports must be flat 2D media, not 3D scene data. This constraint lives
  in the editing suite, not in this repo — it is not greppable here.

## Export decisions
- PDF: draw with CoreGraphics into CGPDFContext. NOT ImageRenderer —
  it silently rasterizes any view containing materials, blurs, or images,
  producing a valid PDF that is secretly a bitmap. NSPrintOperation backs
  a Print menu item only, not the export path.
- Animation: PNG sequence with alpha first, then ProRes 4444 with alpha
  via AVAssetWriter (proRes4444 + 32ARGB buffers; alpha is silently
  dropped if output settings are wrong). Transparent background is
  non-negotiable.
- No Fusion JSON importer. Resolve imports PNG/ProRes natively; a real
  bridge means emitting .comp or Lua, which is a separate deliverable.
- Exported media NEVER goes in CloudKit — it counts against the personal
  iCloud quota. Sync vector model data only; write exports to disk. This
  follows the existing SDDrillMedia pattern (paths in the model, bytes on
  disk via DrillMediaStorage).

## Contract decisions
- Payments are a JSON ledger (paymentsData: Data? holding
  [ContractPayment]), not a separate record type — same idiom as
  bundleSessionIdsData. Supports partial and multiple payments with zero
  new CloudKit record types.
- Travel is travelFeeAmount + travelFeeBasis (.perContract / .perSession,
  default .perContract). Travel money stays OUT of amountPaid and OUT of
  session revenue — folding it in corrupts the paid-sessions arithmetic.
- expiryDate stays as a dead legacy column. Do not revive it (contract
  validity is derivable from bundle exhaustion + manualStatus, and a
  second source of truth will drift) and do not drop it (removing a column
  from a live CloudKit schema is a sync risk for no gain).

## Build commands
- iOS:  xcodebuild -project Hoopwise.xcodeproj -scheme Hoopwise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Mac:  xcodebuild -project Hoopwise.xcodeproj -scheme HoopwiseMac -destination 'platform=macOS' build
