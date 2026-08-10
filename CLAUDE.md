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
  crashes) — not interface work. ONE sanctioned exception (August 2026):
  widget deep-link routing in MainTabView/SAMApp (tap-through to
  session/athlete). It is an explicit approval for that diff only, not
  precedent for general iOS edits.
- WHAT THE FREEZE PROTECTS (clarified August 2026, not a new exception):
  the iOS UI SURFACE — what renders and reads on screen. Rewiring the
  plumbing BEHIND that interface to a shared service is permitted, because
  the coach's screen is unchanged by it. The bar is evidence, not
  assertion: a plumbing diff carries before/after screenshots of every
  touched sheet, pixel-identical. SheetGalleryDebug + HOOPWISE_SHOT is the
  harness that makes that cheap (it constructs the real sheet directly, so
  two runs cannot differ in how they navigated there); scratchpad
  `pixdiff` does the comparison. Phase 2.5 is the worked example: four
  createSession() bodies replaced, four sheets identical to the pixel.
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

## Mac directory pattern (August 2026)
- DirectoryView (HoopwiseMac/Views/Directory/) is the Contacts skeleton:
  groups column → indexed list → detail card, three columns inside the
  page. Instances: AthletesDirectoryView, SessionsDirectoryView. Pages own
  DATA logic (membership, collation, search, selection coherence); the
  skeleton owns layout, rail, drag-to-group. Generalize only what a second
  page exercises — the index rail became optional because Sessions
  sections by month, not letter.
- COLLATION is NameIndex (Utilities, both targets): one derivation feeds
  sort key, A–Z section, and search blob — pinyin for hanzi, diacritics
  stripped (roster latin names carry tone marks). 蔡一铭 sorts under C and
  is findable by "cai" or initials "cym". Verified against the real 133.
- Sessions has a CALENDAR mode (toggle in the list-accessory row, persisted):
  month grid with dot indicators per session day, day selection drives the
  same selection binding as the list. It uses DirectoryView's listOverride
  slot — the page swaps the List body while search/accessory/count stay
  skeleton-owned. That slot exists because a second page exercised it; keep
  it a full-body swap, don't grow per-page knobs inside the skeleton.
- Directory keyboard rides KeyDispatchCore (the editor's dispatch layer):
  DirectoryKeyDispatcher maps ↑↓, ⌘F, ⌘N, Esc, type-to-select. Never add
  onKeyPress handlers to directory subviews.
- Card editing is EXPLICIT: Edit → draft → Done commits student+guardian
  in ONE undo step, Esc cancels. Contact fields live on Player.parentInfo,
  not SDStudent. No always-live editing in read mode.
- SDDirectoryGroup is the ONE record type for custom groups across all
  directory pages (entityKind field) — registered in the schema now so the
  next Dev→Production deploy (roadmap step 3) carries it. Run the iOS app
  once in Debug before relying on group sync (rule 7c/7e). The smart
  group ("Attendance < X%") is VIRTUAL — only its threshold persists, in
  AppStorage — so no auto-created records can duplicate across devices.
- AthletesView.swift / SessionsView.swift keep the tab content the new
  cards embed (Athlete*Tab, SessionDetailView); their old page structs are
  unwired. Old Sessions had a graphical calendar the directory dropped —
  flagged for reassessment, restore point intact.
- NEVER nest a NavigationSplitView inside RootView's on a Mac page. A
  second split-view controller re-bridges its own toolbar during sidebar
  page switches, and with concurrent layout invalidation (avatar preloads
  finishing mid-transition) AppKit's update-constraints pass livelocks —
  NSGenericException "more Update Constraints in Window passes than there
  are views", SIGABRT. It is a RACE: it can pass ten times and kill the
  eleventh. Two-pane pages use HSplitView (Drills, Programs, League,
  Playbook were converted August 2026; the directory pattern was already
  HSplitView).

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
- NSUndoManager holds registered targets unowned(unsafe). Any model that
  registers undo actions against the WINDOW's undo manager must purge them
  (removeAllActions(withTarget:)) when the manager reference swaps, when
  its content is replaced, on view disappearance, and in deinit — a
  dangling target makes Cmd-Z dereference freed memory and crash with a
  nonsense cast. The editor model is owned by RootView so its lifetime
  matches the window; do not move it back to a per-visit @StateObject.
  Purge-on-load also matters for correctness: without it, Cmd-Z after a
  play switch restores the PREVIOUS play's snapshot into the current one.
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
- RENDER STYLES: RenderStyle (Utilities/, both targets) owns every visual
  decision as data — .edit is the authoring overlay (numbers, full paths,
  semantic dash/wavy), .presentation is the published video look
  (terracotta #A76458 soft brush at 0.6x puck diameter with 0.35x blur,
  flat #FFFF70 discs, #FE1A2C ball at 0.4x, black court, white lines).
  Semantic pass/cut/dribble distinctions stay in the DATA; presentation
  renders one uniform brush and the travelling ball reads as the pass.
- PATH CONSUMPTION (PathConsumption, pure functions of t): presentation
  paths live AHEAD of motion only — draw-on tip-first 0.25s starting 0.3s
  before the segment, consumed behind with the tail tucked 0.8 FEET
  (distance, not time — a time tuck stretches with velocity) under the
  puck, gone at completion. Stateless in t so scrubbing regrows. Blur is
  applied AFTER trimming, path layer only, never entities or court. ONE
  arrowhead per path at the destination — direction changes must not
  sprout heads. Canvas blurs via GraphicsContext.addFilter(.blur) (GPU);
  the exporter via CIGaussianBlur on the offscreen path layer.
- PlayFrameExporter.renderFrame is THE export renderer: absolute time,
  transparent background (verified: corner alpha 0, court alpha 255 at
  1080p), same geometry/projection/movement code as the canvas. The PNG
  sequence and ProRes 4444 encoders must consume it, not re-render.
- SwiftUI type-checker budget failures in this codebase so far: bezier
  flattening, hitTest chain, drillDetailColumn, and the editor's body
  modifier chain. Write geometry and long modifier chains as explicit
  statements / hoisted subviews.
- KEYBOARD: every editor shortcut routes through EditorKeyDispatcher (one
  local NSEvent key-down monitor). Never add onKeyPress/focusable/
  onDeleteCommand handlers to editor subviews — per-view handlers are the
  focus-fragility class that made Delete and the tool letters fire
  inconsistently. The dispatcher gates on the editor's own window, stands
  down while a text field is first responder (responder chain, not
  @FocusState), consumes handled keys so Space can never hit a default
  button, and DEBUG-logs every decision to subsystem "hoopwise.keys".
- BALL LANE is a continuous state bar (rest / dribble / pass flight / shot
  flight / loose) computed by ReadNode.ballSpans — breakpoints from
  possession events + derived arrivals + holder keyframes, each interval
  classified THROUGH ballState so the bar cannot contradict the canvas.
  The bar is display; the event glyphs on top remain the editable handles.
- SHOTS: dropping the ball within RenderStyle.rimSnapFeet (2.5 ft) of the
  hoop authors a shot; rim beats receiver snap so a player under the
  basket cannot steal the drop. Shot↔pass conversion lives in the
  inspector (convertShotToPass / convertPassToShot) — a misdrop never
  requires redoing the gesture. Post-shot the ball rests at the rim.
- DemoScenario (DEBUG, env-gated) drives the real editor for agent
  verification runs — no Accessibility on this Mac, so synthetic input is
  impossible; screenshots via screencapture, results via unified log
  subsystem "hoopwise.demo". It disables persistence so scratch plays
  never reach the library.

## Widget suite (iOS home screen, August 2026)
- FOUR widgets (NextUp, Today, Attention, Cadence in SAMWidgets/) + lock
  accessories, all reading ONE snapshot (schema v2, versioned) through one
  provider. v2 fields are optional so a v1 snapshot on disk renders old
  content instead of crashing — keep that invariant when extending.
- PHOTOS: the widget process cannot read the app container or SwiftData
  external storage. WidgetSnapshotWriter EXPORTS square 360px JPEGs into
  AppGroup/WidgetPhotos/<athleteID>.jpg via CGImageSource thumbnailing
  (full-res never decoded), gated by a SHA256 manifest (re-encode only on
  change), orphans pruned each write. Widgets load ONLY those files
  (WidgetAvatar), monogram fallback, photo redacts to monogram.
- SAMWidgets/NextUpWidget.swift renders a snapshot JSON from the App Group
  (group.OKTO.SAMp) — the widget NEVER touches CloudKit/SwiftData. The
  app writes the snapshot via WidgetSnapshotWriter (Services/, hooked into
  refreshAllCaches + refreshCachesSync, debounced; inert on Mac) and the
  model lives in Models/WidgetSnapshot.swift (member of iOS + Mac + widget
  targets — the widget's Hoopwise-folder membershipExceptions list).
- AttentionRules in WidgetSnapshot.swift is THE source of truth for alert
  thresholds (bundle low ≤3, attendance <50% over ≥4 sessions, noted
  ≤14 days). The widget's student pick and any curation surface must read
  these constants, never re-invent the numbers.
- Timeline entries sit at display-change moments (now, session starts and
  ends, midnight) — rollover is an entry, not luck. Snapshots older than
  24h render an "open app to refresh" footer.
- hoopwise://session/<id> and hoopwise://athlete/<id> are registered
  (Info.plist), routed in SAMApp.onOpenURL to
  .hoopwiseOpenSession/AthleteRequest notifications, and OBSERVED by
  MainTabView (the sanctioned freeze exception): one sheet(item:) presents
  the session page or student profile. Cold start is covered by
  PendingWidgetRoute in SAMApp.swift — the URL lands before MainTabView
  exists, so the route is queued and drained in MainTabView.onAppear
  (data is loaded by then; lookups by id, unknown ids dropped).
- Photos in the snapshot: thumbnail bytes ≤120px, monogram fallback;
  privacy redaction collapses photo+name to monogram + reason chip.
- WINDOW HIGHLIGHT LADDER v2 (August 2026, on-device evidence): expected
  roster = attendeeIds if non-empty, else PROGRAM ENROLLMENT — real device
  sessions are created with EMPTY attendeeIds, and reading the array alone
  froze one attention student into every window (the stuck-Mason bug; the
  simulator seed data had the arrays filled). Ladder per window:
  attention-in-roster → roster-top-attender (≥1 recorded session) →
  roster-any (deterministic, photo-having first) → attention-first →
  global top attender; the global rungs may fire ONLY when the roster is
  empty even after the enrollment fallback — a kid actually in the
  displayed session always beats an unrelated noted student. Noted expiry
  follows the NOTE'S SESSION (same-day session resolved against ALL
  events, horizon or not); a session-less note gets a 48h window, NOT the
  attention list's 14 days — 14d + a global rung let one stale note
  colonize every abstaining window. Past the last window, window(at:)
  returns nil and the widget renders rest/stale — never the final
  window's student.
- DEBUGGING without root/Accessibility: provider and writer log to unified
  log subsystem "hoopwise.widget" AND mirror to App Group
  Library/Caches/nextup-{provider,writer}-trace.log (256KB-capped), which
  `devicectl device copy from --domain-type appGroupDataContainer` can pull
  from a physical iPhone. `log collect --device` needs root; the group
  container ROOT is not transferable, only Library/Documents/tmp.
  Deep links are testable headless via `devicectl device process launch
  --payload-url "hoopwise://..." OKTO.SAMp` (add --terminate-existing for
  the cold-start path); routing writes "deeplink …" lines to the writer
  trace. Widget "screenshots": copy a `render-request` file into the group
  Library/Caches and the NEXT timeline build renders every window (medium)
  into Library/Caches/renders/. ANY reload consumes the flag — drop it
  only after the snapshot you want rendered is already on disk, or the
  renders come from the stale one.

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

## Attention system v2 (August 2026) — the engine is the record
- ONE principle: attention = an action inside ~48h that changes an outcome.
  Everything else is automated (Tier 1) or a report (Tier 3). The rules
  live in Hoopwise/Services/AttentionEngine.swift (BOTH app targets) with
  thresholds in AttentionRules (Models/WidgetSnapshot.swift). The iOS
  Attention card (AttentionInbox is now an adapter), Mac Today's rail,
  Whistle curation, and the widget writer ALL consume this layer — never
  re-implement a predicate in a view; that duplication is exactly what
  produced the 158-item card.
- TIER 1: SessionLifecycle gained .autoClose (legal from scheduled/
  inProgress; sets .completed and appends the stable "Auto-closed: <date>"
  notes marker — same mechanism as "Skipped:"). AttentionEngine.
  runAutomation closes sessions past end + 12h grace; hooked debounced
  into refreshAllCaches/refreshCachesSync (foreground + post-sync, both
  platforms), throttled 5 min, idempotent. The first run IS the amnesty.
  Reopen = resetToScheduled (strips the marker). The ledger ("Handled
  automatically", iOS briefing + Mac Today group) derives from the marker.
- ATTENDANCE MATH: AttendanceMath.rate is THE per-student attendance
  definition for attention decisions — denominator counts ONLY sessions
  with an explicit mark (present/excused/unexcused). Unrecorded sessions
  are excluded, so auto-closing backlog cannot move any percentage.
  Unmarked is NOT absent, in statistics exactly as in money.
- TIER 2 state (snooze/dismiss/edge fire dates) is DEVICE-LOCAL JSON in
  UserDefaults ("attention.state.v2") — deliberately unsynced, like the
  smart-group threshold. Dismissal is per-edge (keys embed the edge).
  Items age out at their deadline; display cap AttentionRules.displayCap
  is a safety rail — if a rule alone produces >5 items, tune the rule.
- iOS has NO snooze/dismiss controls (UI freeze) — the engine and Mac
  Today have them; the iOS card benefits from the filtering only. Adding
  iOS controls is an OPEN FREEZE QUESTION, not sanctioned.
- Debug evidence hooks (DEBUG, env-gated, iOS): HOOPWISE_ATTENTION_REPORT
  and HOOPWISE_ATTENTION_SELFTEST write attention-report.txt to the App
  Group Library/Caches.
- The Mac target's membership for Hoopwise/ files is an explicit
  membershipExceptions OPT-IN list in project.pbxproj — a new shared file
  compiles on iOS but NOT Mac until added there (this is rule 1's actual
  mechanism; AttentionEngine.swift is in the list).

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
- Nothing un-charges a session automatically, WITH TWO EXCEPTIONS added in
  the restructure's Phase 0 (August 2026), both because the alternative is
  a charge the coach cannot see or find:
  a. A session that becomes SKIPPED or CANCELLED refunds whatever it
     consumed, and can never be charged afterwards (redeemPrivateAttendance
     gates on status). SkipSessionSheet has always promised "Skipped
     sessions won't count toward contracts" and nothing enforced it —
     mark attendance, then skip, and the client stayed charged forever.
  b. DELETING a session refunds what it consumed. This is what makes the
     back-dated private-session flow undoable in one step; without it the
     charge outlived the record that explained it.
  Marking someone ABSENT still consumes, and still un-charges only via the
  coach's explicit refundSessionToBundle. Covered by
  SAMpTests/SkipDoesNotChargeTests.swift — change these rules and it fails.
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

## Mac attendance marking (decision REVERSED August 2026)
The earlier rule was "Mac does not mark attendance — phone for operations,
Mac for authorship." Luther reversed it in the full-editability phase: Mac
roll call now exists and MUST be exact parity — the four-state model
(unmarked is NOT absent), every write through setStudentAttendanceState
(which keeps contracts in lockstep via the one redemption authority),
money consequences stated in words on each row. The previous Mac
RollCallTab was a three-state cycle writing arrays wholesale and never
deducting — that class of divergence is what to grep for when touching
any attendance surface.

## Shared editing rules (August 2026, full-editability phase)
- SessionLifecycle (Models/, both targets) is THE session state machine:
  isAllowed + apply, extracted verbatim from the iOS coaching flow, which
  now calls it. Mac transition buttons gate on isAllowed. Skip appends
  "Skipped: reason" to notes; resetToScheduled preserves attendance.
  Platform effects (Live Activity, haptics) stay per-platform.
- setStudentEnrollment is THE enrollment writer: one relation stored in
  two fields (student.programId and program.enrolledStudentIds) that
  drift when written separately — always go through the writer.
- Edit sheets commit small transactions on Done (CloudKit is
  last-write-wins per record; no long-lived drafts), one undo step each.
- Contract edits append a minimal timestamped old→new line to the
  contract's existing notes field — the history mechanism available
  without inventing schema. Bundle-size floor = sessions consumed, so
  remaining can never go negative.

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
- The statement is a CLIENT-FACING ONE-PAGER (v2, August 2026): NO MONEY —
  zero currency symbols; it states attendance, the agreement states price.
  Its table rows ARE contract.bundleSessionIds (the redemption authority's
  array) resolved to events, and the Consumed stat DERIVES from those rows
  — rows shown = sessions consumed by construction, so the document can
  never contradict itself. Never recompute consumption from attendance
  arrays. Five columns (# 日期 时间 地点 备注), three-stat strip, accent
  (#007AFF) exactly twice (wordmark + remaining), hairlines only, must
  survive grayscale. DEBUG headless export: launch the iOS app with env
  HOOPWISE_EXPORT_STATEMENT="<name>:<contractNo>" → PDF lands in the App
  Group Library/Caches as statement-debug.pdf (pullable via devicectl).
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

## The Whistle — integrated LLM assistant (Mac only, August 2026)
- HoopwiseMac/Assistant/: AssistantTools (tool registry), AnthropicClient
  (raw URLSession Messages API — no Swift SDK exists), AssistantEngine
  (conversation store + agent loop + Today curation), WhistleBubble
  (floating NSPanel). AssistantView is the sidebar page.
- THE RULE: the assistant never touches the database directly. Every tool
  handler calls the shared business-rule layer (SessionLifecycle,
  setStudentEnrollment, updateContract…), so app rules gate it for free.
  Never add a tool that bypasses that layer.
- Writes are previewed as confirmation cards; contract changes can NEVER
  be always-allowed. Every mutation registers one undo step tagged
  "Assistant: …". Deletes have no tool at all — deliberately.
- API key lives in the macOS Keychain (Settings → Assistant), falling
  back to the xcconfig ANTHROPIC_API_KEY. Chat = claude-sonnet-5,
  curation = claude-haiku-4-5. Data minimization is ON by default:
  guardian contacts, money amounts, and photos never enter prompts.
- Curation is an enhancement, never a dependency: offline/keyless, Today
  renders its deterministic layout and chat degrades with a clear notice.
- DEBUG env HOOPWISE_DEMO_ASSISTANT=script swaps in a scripted transport
  that exercises streaming, a real read tool, and the confirmation card
  with no key or network — the E2E verification path.

## Referential integrity / orphan census (Phase 1, August 2026)
- Services/SessionIntegrity.swift (BOTH targets) is the detection that did
  not exist: a PURE census over sessions/programs/phases — dangling
  programId, dangling microCycleId, phases naming a deleted program,
  sessions whose phase belongs to another program (the invariant nothing
  validates), plus advisory counts for sessions outside their phase window
  and same-program/day/TIME duplicate groups. No repair, no I/O.
- Run it on real data: launch iOS with env HOOPWISE_ORPHAN_CENSUS=1 → the
  report lands in the App Group Library/Caches as orphan-census.txt.
- BASELINE, live store, 2026-08-09: 217 sessions / 20 phases / 12 programs,
  **BROKEN TOTAL 0**. The inconsistent delete paths documented in the
  survey have evidently never been exercised on this data. Advisory:
  41 standalone (programId nil) sessions — the Phase 2 adoption workload;
  12 duplicate groups; 3 sessions outside their phase's window.
- Note the duplicate test bucket is program + day + START TIME. The legacy
  dedupeProgramSessions buckets on start-of-day alone, so it treats a
  morning and an afternoon session as duplicates; SessionIntegrityTests
  pins the correct behaviour.

## Restructure Phase 2.2 — decomposing programId == nil (August 2026)
- SCHEMA CHANGE PENDING DEPLOY: SDSessionEvent gained `seriesId: UUID?`
  (optional + defaulted, so additive and CloudKit-safe). Rule 7 still
  applies — it must be deployed Development→Production by hand, and an iOS
  build carrying the field must ship, before any released build writes it.
  It rides along with the other registered-but-undeployed types.
- Services/SessionSeries.swift owns what `programId == nil` used to imply:
  · SERIES IDENTITY. A generated run stamps one `seriesId` on every session
    it creates (materializeSessions, backfillSessions).
    SessionSeries.siblings prefers the id; the old structural fingerprint
    (title + venue + weekday + time + duration + no program) survives ONLY
    for unstamped legacy records. The fingerprint was wrong in both
    directions: renaming a session or moving its venue ejected it from its
    own series, and two unrelated one-offs in the same slot looked like one.
  · LIVE ACTIVITY. allowsLiveActivity is an explicit rule: group-shaped
    programs yes, private behind the `liveActivity.privateSessions`
    preference (default OFF, preserving today's behaviour), no program → no.
    Private clients previously got none purely because privateness was
    encoded as the absence of a program — never a decision.

## Restructure Phase 2.1 — adoption (August 2026, executed)
- PHASE-WINDOW RULE (decided): CALENDAR DAYS, inclusive of both edge days —
  SessionIntegrity.phaseWindow(start:end:contains:) is its only home, and
  2.4's date-derived phase assignment must call it. Instant comparison
  flagged every edge-day session as misfiled, because a phase window carries
  whatever clock time the phase was created at (13:54, 15:25, 10:59 in the
  live store) — times the coach never chose.
- Services/SessionAdoption.swift plans where standalone sessions land, and
  writes nothing. Tiers, in order: PRIVATE FIRST (a 1:1 session must never be
  swept into a group program by shape, slot or title), then exact shape owned
  by exactly one program, then the program's declared SLOT (weekday + time +
  duration + venue — a newly created program owns no sessions, so the shape
  index can never match it), then title == program name. Two candidates at
  any tier means Unassigned, never a guess.
- Executed on the live store: the "Training" / "Road to Elite Fridays"
  Friday series (15 sessions) adopted into the EXISTING Elite U10 Development
  — profile the existing programs' slots BEFORE creating a new one; a
  duplicate 酷迅 · U10 was created and deleted when the slot tier flagged the
  clash. Five one-person `Private · <name>` programs created
  (.privateSessions, planless, no recurringDays and no defaultSessionTime so
  the slot tier can never match them; note Program.init defaults
  recurringDays to [.saturday]). Age bands derived from birthdates.
- Adoption sets programId ONLY. Phase links stay nil for 2.4.
- Store after 2.1: 216 sessions, BROKEN 0, window violations 0, standalone
  41 → 5 (Scrimmage x2, 义蓬U10周日上午9:30, Summer Camp, Private Session -
  Mason — awaiting triage). Duplicate groups 11 → 16: adoption created 5 new
  pairs where Elite's phase-generated sessions already sat on those Fridays.
  ALL 16 remain PENDING until derived names land (2.3).

## Restructure Phase 2.8 — deadwood verdicts (August 2026)
Every candidate the restructure surfaced, with its verdict. Recorded so none
of them gets re-investigated from scratch a third time.

DELETED:
- `SampleDataGenerator.swift` (488 lines, both targets) — zero references
  anywhere. Gone.
- `syncFromCloud()` / `syncToCloud()` — no callers, and they only stamped
  lastSyncDate, which made the stamp a lie: it read "synced just now" when
  nothing had been asked of CloudKit. CloudSyncMonitor reports real state.
- `deleteLocalDatabase()` + `getLocalStorageURL()` — no callers, and the URL
  was never passed to ModelConfiguration, so the "delete the local database"
  utility deleted a path the store does not live at. A break-glass reset that
  silently resets nothing is a trap, not a tool. The stale platform-storage
  comments went with them.

FIXED (it was not deadwood — it was armed):
- `dedupeProgramSessions` sits behind a coach-facing iOS button captioned
  "This can't be undone". It grouped by CALENDAR DAY ALONE and deleted every
  session but the most populated one, while its own comment claimed it spared
  "back-to-back morning/afternoon sessions" — which is exactly what grouping
  by day destroys. Since Phase 0 a delete also refunds, so one press could
  remove a real session and move a client's balance. It now runs the tested
  Phase 1 layer (SessionIntegrity.duplicateSessionGroups + SessionDedupe:
  program + day + START TIME, merge into the survivor, leave review cases
  alone), and the count on the button uses the same rule so the number is
  what would actually go. Live store 2026-08-10: 0 real duplicates and 0
  same-day-different-time pairs, so nothing was at risk that day — the defect
  was latent, not active. Covered by ProgramDedupeTests.

KEEP, with the reason:
- `SDCoach.autoSyncEnabled` — unused, deliberately. Removing a column from a
  live CloudKit schema is a sync risk for no gain (same verdict as
  Contract.expiryDate).
- The five Supabase mentions in Swift (ImageCacheManager, SwiftDataManager)
  are NOT deadwood: they detect dead-host and file:// profileImageUrls in real
  legacy data. The 23 `supabase_*.sql` / migration files are deadwood and are
  roadmap step 10's job — nothing blocks that step now.
- `CourtScheme` / `CourtFrame` — superseded by PlayDiagram but still wired to
  the Basketball Lab views. They die with the step 5 port, not before.

STILL OPEN, needs a decision rather than a verdict:
- The Contract legacy shims that LIE (isSigned always true, isExpired always
  false behind a red warning that can never fire, jerseyGiven/ballGiven,
  jerseyNumber/jerseySize, weeklyAttendance) and SalesView's three toggles
  whose setters discard the write while the UI says it saved. Fixing them
  removes or changes iOS controls, so it needs the same explicit call the 2.6
  iOS half got. Listed under "Known broken things" since July 2026.
- `AddProgramView.swift` contains no `AddProgramView`. It holds
  EditEnrolledStudentsView, EditProgramView, MicroCycleDetailView and
  FlowLayout — all live. The file name and its doc comment are the deadwood;
  a rename is cosmetic and was not taken during a data-correctness phase.

## Restructure Phase 2.7 — a phase's WORDS are derived (August 2026)
- Services/PhaseNaming.swift (BOTH targets) finishes what 2.3's header comment
  flagged: PhaseTemplate carries LocalizedTriple(en/zh/es), but `instantiate`
  calls resolve(currentLanguage) and STORES one string. A plan built in
  English is called "Pre-Season" forever, and after 2.3 that English leaks
  onward into every session name, the calendar, the widget and the PDFs on a
  phone running in Chinese.
- The stored column is the LEGACY FALLBACK, same as 2.3. No schema change and
  no migration: the link back to the template IS the stored string, matched
  against every locale of every template for that program's AGE BAND.
- Two rules keep it honest. PER FIELD — title, description and each objective
  match independently, so a coach who keeps the preset title and rewrites the
  objectives keeps their objectives. NEVER GUESS — no match or two different
  renderings returns the stored string verbatim. ("Pre-Season" really is two
  phases in Chinese: 季前适应 for mini12, 季前 for infantil/senior. That is why
  the lookup is scoped by band, not a global title index.)
- Coach-authored templates (PhaseTemplateStore) are searched BEFORE the FEB
  defaults — a coach's programs are built from their own templates.
- Wired at the MANAGER BOUNDARY (cachedMicroCycles), like 2.3, with the same
  kind of write-path guard: `phaseTextToPersist` keeps the stored words when
  the caller round-tripped a cached copy, so saving an unrelated edit while
  running in Chinese cannot burn the Chinese rendering into an English plan.
- Switching language POSTS .hoopwiseLanguageChanged and the manager rebuilds
  its caches. Without that the chrome changes language and the coach's plan
  does not.
- Live-store evidence (HOOPWISE_PHASE_LANG, read-only, 2026-08-10): of 21
  phases, 11 preset ones resolve per language and 10 stay verbatim — the
  generic "Phase 1…5" and "Summer Block", which are not preset text. No false
  positives.
- STILL ENGLISH-ONLY, not addressed here: TrainingFocus.displayName. It is a
  missing translation rather than a frozen one, so it belongs to a
  localization pass, not to this rule.

## Restructure Phase 2.6 — the skip rule (August 2026)
- `SessionLifecycle.didNotHappen` is THE predicate: skipped and cancelled are
  the same fact — it did not take place and it will not. Before this the app
  agreed with itself in exactly two places, both about money (the Phase 0
  refund and the redemption gate); ~20 other sites asked "did this happen?"
  by testing `.cancelled` ALONE.
- So a holiday-skipped session was still real everywhere else: it sat in
  today's list, it could be NEXT UP on the home screen, and marks recorded
  before the skip still weighed on a student's attendance rate — after the
  money had been refunded. MONEY AND STATISTICS NOW AGREE.
- Adopted in: AttendanceMath.rate and consecutiveMisses, the monthly card
  export, WidgetSnapshotWriter (all three: NextUp roster, noted-session
  resolution, weekly attendance), the iOS dashboard's Today list and its
  per-athlete row, both "isUpcoming" badges, and Mac Today/Sessions.
  The two money gates now call it too, so there is ONE definition.
- IT IS NOT A VISIBILITY RULE. A skipped session stays in the calendar and in
  history carrying its "Skipped: <reason>" note — that record is how the coach
  explains the gap later. Status STYLING (the cancelled strikethrough, the
  gray) is untouched.
- Mac's session context menu now routes through SessionLifecycle.apply and
  gates on isAllowed. It used to set status directly, which let it offer
  "Cancel Session" on an already-skipped session — a transition the state
  machine forbids, performed anyway because the menu never asked it.

## Restructure Phase 2.5 — ONE creation service (August 2026)
- Services/SessionCreation.swift (BOTH targets) is THE way a session is born.
  Nine sites built a SessionEvent by hand and disagreed on every derived
  field; the stray Frank session (no program, venue typed "Kuxun Main court"
  for a gym stored as 酷迅, no phase) is what that cost in practice.
- Two steps: pure `plan` decides (so it is testable without a store), then
  `SwiftDataManager.createSession` writes. Callers state an INTENT.
- `Group` is the whole point: `.program(id)`, `.privateClient(id)`,
  `.unassigned`. programId == nil still exists — a scrimmage or a camp really
  belongs to no program — but it now means ONLY that. Nothing infers
  privateness from it, and no site may hardcode it "because private".
- PRIVATE CLIENTS: find-or-create their micro-group, in the 2.1 shape (no
  recurringDays, no defaultSessionTime, planless). The search IGNORES status,
  so a returning client REACTIVATES their archived program instead of
  spawning "Private · Frank 2" beside it.
- ENROLMENT is only written when the student has no program pointer at all.
  setStudentEnrollment clears every other program's roster by design, so
  pointing a group athlete at their private micro-group would silently remove
  them from the squad they train with.
- UNDO IS ONE STEP: createSession returns a SessionCreationResult and
  `undoSessionCreation` reverses all of it — session, auto-created program,
  reactivation, enrolment. ⌘Z on a mistaken booking never leaves an empty
  "Private · <name>" program behind. Program deletion is guarded on the
  program being provably empty, because deleteProgram cascades to sessions.
- Derived at creation: phase FROM THE DATE (2.4's window rule), venue and
  roster from the program, `date` == `startTime` (one convention), and the
  stored title = what the coach typed, else the derived name. `Intent.phase`
  overrides derivation for the generators, which generate FOR a phase — 16
  links in the live store sit in dateless plans and would otherwise be lost.
- Every batch stamps ONE seriesId, including the two wizard generators that
  used to stamp none.
- Residue, deliberately not converted: SDSessionEvent.from (model mapping),
  #Preview and `samples` fixtures, AttentionDebugReport's scratch records
  (DEBUG, deleted immediately, and they test the attention engine), and
  SampleDataGenerator — which has NO call sites at all and is a 2.8 verdict.

## Restructure Phase 2.3 — names are DERIVED (August 2026, executed)
- Services/SessionNaming.swift (both targets) computes a session's name from
  the group and the plan. groupFirst = the program's resolved display name
  (calendar, widget); planFirst = "<phase> · Session N of M" (inside a
  program). The stored column is a LEGACY FALLBACK, used only when a session
  has no program; the "Private ·" prefix is stripped there because
  privateness is the program's TYPE now, not a string prefix.
- Wiring is at the MANAGER BOUNDARY, not in 45 views: cachedSessionEvents
  carry the derived title (SwiftDataManager.withDerivedNames), so renaming a
  phase or program renames every surface at once.
- THE WRITE-PATH GUARD: `titleToPersist` compares the incoming title to what
  was rendered for that id. Identical → the caller round-tripped a cached copy
  and never touched the name, so the STORED string is kept. Different → a
  deliberate rename, stored as an override. Without this, every save would
  burn the derived name into the column and derivation would become a
  one-time rename. Covered by SessionNamingTests — do not remove.
- The stored `title` column is UNCHANGED on disk. "Retiring title to
  legacyTitle" is semantic only: renaming the column would be a CloudKit
  schema removal, which is not allowed.
- With names derived, the 16 pending duplicate merges executed: 216 → 200
  sessions, 0 groups remaining, BROKEN 0, 0 bundle slots moved.

## Restructure Phase 1 — integrity foundations (August 2026)
- Services/SessionReconciler.swift (BOTH targets) is the enforcement point.
  `addSessionEvent` validates at creation, but CloudKit materialises records
  without running app code, so the GUARANTEE is a repair pass: one pure
  `normalize` rule shared by creation and repair, debounced into the same
  refresh paths as auto-close, 5-min throttle, idempotent. It clears dangling
  programId / microCycleId and a cross-program phase pointer (the phase link
  is the invalid half). It COUNTS duplicates and orphan phases and touches
  neither — the 11 approved merges wait for Phase 2's derived names, because
  applying them today renames sessions in the coach's calendar.
- Services/SessionPrivacy.swift is the ONE isPrivate. Program type when a
  program is named; for programId == nil the strictest interim rule (an
  attendee holds an ACTIVE private contract). A dangling programId is NOT
  private — inventing privateness invents a charge. eventIsPrivate, the Hub
  sheet, Mac Sales and sessionFormat all delegate; the attendee-majority
  badge vote is deleted. Grep proof: `programType == .privateSessions`
  appears exactly once in the app.
- AttendanceMath.expectedIds is the ONE roster definition; the five inline
  `attendeeIds.isEmpty → enrolledStudentIds` copies are gone. One of them
  (the calendar row) had been showing NO headcount for enrollment-backed
  sessions.
- CASCADE SEMANTICS LIVE IN THE MANAGER: deleteMicroCycle orphans its
  sessions by clearing the pointer (never deletes them); deleteProgram
  cascades to phases AND sessions via deleteSessionEvent so slots refund and
  contract references are released. All four former phase-delete call sites
  and all five program-delete sites call these; views no longer compensate.
- PhaseSession is DELETED (no persistence, no writers; its only reference was
  an unused `phaseSessions` array on the manager). Verdict recorded: gone.

## Tests: never let CloudKit into the test process
- ModelConfiguration's `cloudKitDatabase` defaults to **.automatic**, which
  attaches CloudKit mirroring whenever the target has the iCloud entitlement
  — EVEN FOR AN IN-MEMORY STORE. Both test configurations must pass
  `cloudKitDatabase: .none`. Symptom when they don't: NSCloudKitMirroringDelegate
  failing CKAccountStatus, then "No eligible connection available" landing on
  a random test's setUp, then a crash loop ("Restarting after unexpected exit").
- `SwiftDataManager.isRunningUnitTests` must check XCTestBundlePath /
  XCTestSessionIdentifier / NSClassFromString("XCTestCase") — the
  XCTestConfigurationFilePath variable is NOT set in the app-host process on
  this toolchain, and relying on it alone left the real CloudKit store open
  during tests.
- ONE ModelContainer per test process: `inMemoryForTesting()` reuses a single
  container and wipes it per caller. Building one per test method crashed the
  runner intermittently.
- Run tests SEQUENTIALLY against a pre-booted simulator
  (`xcrun simctl boot <id>` then `build-for-testing` once, then
  `test-without-building -destination 'id=<udid>'`). Two concurrent xcodebuilds
  deadlock on the build DB, and `test-without-building` with no booted sim
  hangs instead of failing. Note `timeout(1)` does not exist on macOS.

## Tests (added Phase 0, August 2026)
- The HoopwiseTests / HoopwiseUITests targets existed in project.pbxproj all
  along as EMPTY SHELLS: their synchronized folder (SAMpTests/) had never
  been created, TEST_HOST still pointed at the pre-rename SAMp.app, and the
  Hoopwise scheme had no <Testables>. All three are fixed; tests live in
  SAMpTests/ and ⌘U (or `xcodebuild test -scheme Hoopwise`) runs them.
- SwiftDataManager.inMemoryForTesting() (DEBUG) is the test seam: a second
  instance over the SAME Schema (now `SwiftDataManager.schema`), in memory,
  no CloudKit. The app still only ever touches `shared`.
- SDSessionEvent.apply(_:) is THE whole-record writer — both `from(_:)` and
  updateSessionEvent go through it. updateSessionEvent used to hand-list 19
  of 23 columns and silently dropped unexcusedAbsences (revenue-critical),
  developmentFocus, headerImageURL and createdByCoachId on every save.
  SessionRoundTripTests reflects over SessionEvent and FAILS when the model
  gains a property, so a new field cannot be silently un-persisted again.
- SessionEvent.init no longer invents a random Unsplash headerImageURL.

## Build commands
- iOS:  xcodebuild -project Hoopwise.xcodeproj -scheme Hoopwise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Mac:  xcodebuild -project Hoopwise.xcodeproj -scheme HoopwiseMac -destination 'platform=macOS' build
