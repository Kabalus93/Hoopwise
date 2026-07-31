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

## Fabricated accessors — the recurring failure mode here
Contract carries legacy compile-time shims for fields the model no longer
has. Several return constants that the UI renders as real data, and
several have setters that silently discard writes. Three were fixed in
July 2026 (amountPaid, outstandingBalance, isFullyPaid — they now derive
from the payment ledger); the rest are still live and are listed under
"Known broken things" below.

When touching any accessor in the legacy-shim block of Contract, assume
it lies until proven otherwise, and check whether a view renders it.
`grep -n "get { \(true\|false\|nil\|0\|\[\]\) }"` finds the family.
Fabricating a value the UI presents as fact is worse than crashing —
it produces confident wrong numbers the coach reconciles books against.

## Known broken things (do not mistake these for working)
- Contract legacy shims that lie. Read-path (always show the same value
  regardless of reality): isSigned (always true), isExpired (always
  false, 9 UI refs incl. a red warning that can never fire),
  jerseyGiven/ballGiven (always false), jerseyNumber/jerseySize on
  Contract (always nil — note Player.jerseyNumber IS real),
  weeklyAttendance (always empty, so those sections never render).
  Write-path (setter discards, but the UI offers a control and calls
  save): SalesView's Contract Signed, Jersey Given and Ball Given
  toggles all no-op while appearing to save.
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
- Setting com.apple.developer.icloud-container-environment to force debug
  builds onto Production is PERMANENTLY DECLINED. It would mix
  development experiments with real student data. Do not propose it
  again.
- KNOWN FUTURE TASK, with a data-migration problem inside it: shipping a
  TestFlight or App Store release requires deploying the CloudKit schema
  to Production first (CLAUDE.md rule 7d). Development DATA does not
  transfer — only the schema. All authoring done in debug builds lives in
  Development and will not appear in a released build. Whoever plans that
  release has to decide how real content crosses the boundary; there is
  no supported automatic path, and re-authoring or an export/import round
  trip through HoopwiseBundle are the realistic options.
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
- Roadmap: (0) DONE documents — PDF layer, attendance statement, training
  agreement, export on both platforms; (1) DONE contracts — payments ledger + travel fee, (2) DONE
  persist Play, four new record types defined and registered,
  (3) deploy schema Dev→Production — only needed ahead of a released
  build; debug-to-debug authoring runs entirely in Development,
  (4) ship one iOS build carrying the new types — a debug install to the
  device is sufficient while working in Development, (5) Mac court editor
  UI, (6) PDF then PNG then ProRes export, (7) knowledge base, (8) bundle
  import/export via HoopwiseBundle.swift, (9) Mac-idiomatic UI polish,
  (10) delete dead Supabase code and SQL.
- SDCourtScheme was considered and DECLINED. CloudKit Production schemas
  are additive only — a record type cannot be removed once deployed, so
  persisting the legacy frame-based CourtScheme would be permanent schema
  debt plus a migration, and what it preserves is in the wrong coordinate
  convention (0-1, not court-feet) and the wrong time model (frames, not
  tracks). Do not author in the Basketball Lab until the step 5 editor
  exists; that work is discarded at quit.
- MacCoachResourcesView.swift is iOS-membership-only and is NOT a simple
  membership flip: it pulls in BasketballCourtLabView, CourtLinesView,
  MiniCourtPreview, FlatEndMarker, ScreenEndMarker, AddEditDrillSheet,
  FlowLayout, ArrowHead, and an AddEditPlaySheet that does not exist
  under that name. Port it as part of the step 5 court editor. Its body
  also exceeds the type-checker's budget at line 560 ("unable to
  type-check this expression in reasonable time") — decompose it during
  the port rather than working around it.

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

## Court editor (step 5, in progress)
- HoopwiseMac/Views/PlayEditor/: PlayEditorModel (authoring state, the only
  place the diagram is mutated), DiagramCanvasView, TimelineView,
  PlayEditorView. Reachable from the sidebar under Library > Court Editor.
- Opens on an empty FIBA half-court diagram so there is always something
  authorable. Playbook wiring comes with the read-tree navigator.
- Authoring loop: scrub the timeline to a moment, drag an entity on the
  court, a keyframe appears at the playhead. Everything is court-feet;
  gestures convert via CourtProjection.unproject.
- Hit testing is in COURT FEET with a feet tolerance, not a pixel radius —
  a pixel tolerance changes meaning with zoom and tilt.
- LOOK PARAMETERS ARE NOT BAKED. CourtLookParameters (maxConvergence,
  minDepthScale, minElevationDegrees, minLabelPointSize) is tunable from
  the editor's Look popover. These are look decisions to iterate against
  real output, not constants to rebuild for. Freeze them only once the
  coach has settled the numbers.
- LEGIBILITY FLOOR: pucks scale with depth, labels do not shrink past
  look.minLabelPointSize (default 9pt) via
  CourtProjection.labelPointSize(base:at:). Billboarding fixes orientation,
  not size — at 35 degrees the far baseline is 68% scale, so unclamped
  numbers become unreadable in a 1080p export and it is only discovered
  after rendering a sequence.
- SwiftUI type-checker budget bites in this area. Two bezier expressions in
  CourtProjection and a chained map/filter/min in DiagramCanvasView.hitTest
  both had to be split into explicit statements. Write geometry as explicit
  typed steps, not one expression.

## Court editor phase (August 2026) — what landed and its rules
- Playhead is ABSOLUTE branch time. Chained playback resolution lives in
  PlayDiagram (segmentIndex/resolvedPosition/segmentPosition over
  BranchSteps), NOT the view model — the frame exporter uses the same
  resolver so playback and export cannot disagree. Boundary continuity is
  by construction: a read without a track resolves to the branch-moment
  position recursively.
- The playback-path Picker bridges to NSPopUpButton, which TRAPS on an
  out-of-range selection index. activeBranchIndex must be reset on load
  and clamped after every structural tree change (clampBranchIndex), and
  the binding clamps both directions.
- Auto-dribble is COMPUTED at render from (movement AND possession
  overlap) at segment midpoints. Never store a dribble style.
- Easing gained .hold (apply() = 0): previous value holds, jumps at the
  keyframe. Context-menu interpolation actions set the segment LEAVING
  the clicked key, which this model stores on the ARRIVING keyframe —
  the off-by-one is deliberate; see setOutgoingEasing.
- Layer eye/lock/solo are transient editor state, deliberately outside
  undo. Locked and hidden layers pass canvas clicks through.
- Save to Playbook: family lives in SDPlay.formation, note in
  playDescription, thumbnail PATH in the legacy diagramUrl (bytes on disk
  under Application Support, never CloudKit). savedToPlaybook derives
  from formation being non-empty. No close prompt by design: the diagram
  autosaves continuously, so a data-loss prompt would lie; the edited dot
  signals unpublished metadata only.
- PlayFrameExporter.renderFrame is THE export renderer: absolute time,
  transparent background (verified: corner alpha 0, court alpha 255 at
  1080p), same geometry/projection/movement code as the canvas. The PNG
  sequence and ProRes 4444 encoders must consume it, not re-render.
- SwiftUI type-checker budget failures in this codebase so far: bezier
  flattening, hitTest chain, drillDetailColumn, and the editor's body
  modifier chain. Write geometry and long modifier chains as explicit
  statements / hoisted subviews.

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

## Attendance and bundle redemption — read before touching any of it
- FOUR states, THREE stored arrays on SDSessionEvent: actualAttendeeIds,
  excusedAbsences, unexcusedAbsences. Membership in none means UNMARKED.
  Unmarked is NOT absent. An unexcused absence consumes a bundle session
  (agreement clause 4); a student whose attendance has not been taken yet
  must consume nothing. Inferring absence from "not present" would invent
  revenue, which is worse than the bug it would fix.
- ONE redemption authority: redeemPrivateAttendance. FIFO by
  effectiveBundlePurchaseDate. A client who buys a second bundle before
  exhausting the first expects sessions consumed in purchase order;
  charging the newest strands sessions already paid for. A second path in
  updateContractsForAttendance used to select by highest contract number
  and could charge a different bundle for the same session — it is gone.
  Do not add a second redemption call site.
- Present and unexcused-absent consume. Excused and unmarked do not.
- NOT RETROACTIVE, deliberately. Absences recorded before this change stay
  un-deducted. Silently reclaiming past sessions would move a client's
  balance without her knowing why and would contradict figures already
  discussed with her. Do not "fix" this with a backfill migration.
- Nothing un-charges a session automatically. refundSessionToBundle is an
  explicit correction the coach invokes when a session was charged in
  error. It used to fire as a side effect of marking someone absent, which
  is how a no-show silently got refunded.
- The 24-hour threshold in clause 4 is NOT representable in data. Nothing
  timestamps when notice was given, so excused-vs-absent rests on the
  coach's judgement at the moment of marking. This is acceptable and
  intentional. Do not add a notice-timestamp field.
- No 'late' state. A late arrival consumes the session exactly as present
  does, so it earns a schema change for nothing, and "late" printed on a
  payment statement to a parent is not wanted. Behavioural detail goes in
  the session note.

## Attendance UI — one control, deliberately
- ONE shared control: `AttendanceMarkControl` / `AttendanceStudentRow` in
  Hoopwise/Components/AttendanceMarkControl.swift, with the `AttendanceMark`
  enum. Every iOS attendance surface uses it.
- There used to be TWO surfaces with different capabilities: a binary
  present/absent toggle in the Take Attendance sheet and a three-way
  control in the session attendance tab. Which states could be recorded
  depended on which screen was open, and the binary toggle could not
  express "excused" at all — so a notified absence recorded there consumed
  a session. Do not add a second attendance control.
- Unmarked is visually distinct from absent: dashed border, muted fill.
  Each row states the money consequence in words ("Deducts 1 session" /
  "No session deducted") because two of the four states charge the client.
- "Clear" means UNMARKED. It previously mapped to absent, which now
  consumes a session — clearing must never charge.
- refundSessionToBundle has UI in two places, chosen because they are
  where a mistake is actually noticed: the session attendance row (swipe,
  shown only when that session was really redeemed) and the contract
  sheet's "Sessions deducted" section.

## MAC DOES NOT MARK ATTENDANCE — do not build it
The division is deliberate: phone for operations, Mac for authorship. The
coach marks attendance courtside on iOS and the data syncs; a Mac-generated
statement is verified against iOS-recorded data. Building Mac attendance
marking adds a surface that will not be used and cuts against the
architecture. Do not add it, and do not cite "you can't verify Mac
statements" as a reason — that reasoning was raised and rejected.

## Documents
- PDFDocumentRenderer (Services/) is the shared vector layer: CoreGraphics +
  CoreText only, A4, both targets. Everything else here builds on it,
  including the future Part 3a play sheet via `draw(path:in:)`.
- Checkboxes are DRAWN as stroked CGPaths via `inlineRow`, never glyphs.
  U+25A1 and U+2611 are absent from PingFang SC and fell through the
  cascade to Hiragino, whose availability differs between iOS and macOS —
  that would break identical output for a signed document. Target font list
  is Helvetica + PingFang SC only; re-audit if new characters are added.
- AttendanceStatementDocument: ONE student, ONE contract, one file. Never
  build a multi-student variant — it goes to a client's phone and would
  leak other families' rates and balances. No images, ever: it keeps a
  minor's photo out of a forwardable document and preserves the vector
  property.
- The statement's "deducted" column reads contract.bundleSessionIds, the
  array the redemption authority writes. Never recompute it — a document
  that contradicts the app's running total is worse than no document.
- TrainingAgreementDocument: the coach's clause text is VERBATIM and must
  not be edited, paraphrased, or "improved". Unknown fields print fill-in
  rules, never plausible defaults. Two modes: blank-for-signing (empty
  consent boxes) and from-contract (stored consent state). Never
  pre-tick a consent form handed to a client.
- Filenames: `Attendance_<name>_Contract<N>_<yyyy-MM-dd>.pdf` and
  `Agreement_<name>_Contract<N>_<yyyy-MM-dd>.pdf`.
- Export UI: iOS contract sheet (system share sheet, for WeChat), Mac
  ContractCard menu (NSSavePanel).

## Media consent
- Stored as a LEDGER on SDContract (`consentsData`, `[MediaConsentEntry]`
  of purpose/granted/date/note), not booleans — clause 8 allows withdrawal
  at any time and a Bool loses the date and the fact of a withdrawal.
  Append, never edit.
- `mayPublishMedia(for:)` and `publicationConsent(for:)` on SwiftDataManager
  answer the student-level question. Only an EXPLICIT grant permits
  publication; unasked and declined both block. Surfaced in the iOS Media
  Vault banner and as a badge on the Mac ContractCard.

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
