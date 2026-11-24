# HoopWise — Project Context

## Start here
- THE VISION IS ACHIEVED (17 November 2026, Luther: "I'm happy with the
  current state of the app, page design and functioning … consider this as
  having achieved my vision … edits will be building"). Git tag
  `vision-achieved` marks that state. It is the REFERENCE: page designs and
  behaviour as they are there are settled. New work BUILDS ON it — extend,
  refine, fix — and does not redesign a page or replace a working flow
  unless Luther asks for that page by name. When unsure whether a change
  alters a settled page, compare with the tag (`git diff vision-achieved`)
  and ask.
- `RESTRUCTURE.md` — the Phase 2 restructure's end-state and its OPEN LEDGER.
  Read the ledger before touching sessions, programs, phases or contracts.
- "THE SESSION LAYER — canonical" below is the rule for new code in that area.

## What this is
Basketball coaching management app. SwiftUI + SwiftData. iOS is the
primary, mature target. The macOS version was retired on 6 November 2026
(tag mac-app-final); the iPad is the next platform. VERSION 3.0 since 17
November 2026 (Luther: "change the app version to 3.0 everywhere" — the app,
the widget and notification extensions and the test targets all read
MARKETING_VERSION 3.0); build numbers come from the archive command line.

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
Contract carried legacy compile-time shims for fields the model no longer
had: constants the UI rendered as real data, and setters that silently
discarded writes. Most are now fixed — amountPaid/outstandingBalance/
isFullyPaid derive from the payment ledger (July 2026), and isSigned,
jerseyGiven, ballGiven and isExpired became real in Phase 2.9. What
survives is listed under "Known broken things" below.

When touching any accessor in the legacy-shim block of Contract, assume
it lies until proven otherwise, and check whether a view renders it.
`grep -n "get { \(true\|false\|nil\|0\|\[\]\) }"` finds the family.
Fabricating a value the UI presents as fact is worse than crashing —
it produces confident wrong numbers the coach reconciles books against.

SECOND HALF OF THE SAME LESSON (Phase 2.9): before concluding that a
predicate is why something never appears on screen, CHECK THAT ITS VIEW IS
REACHABLE. Four of `isExpired`'s nine call sites sat in view properties that
were defined and never referenced, so they could not have rendered whatever
the predicate returned. A lie and a dead view look identical from the outside.

## Known broken things (do not mistake these for working)
- Contract shims that still lie, both harmless-by-guard but not honest:
  `jerseyNumber` / `jerseySize` on Contract are always nil (nothing ever wrote
  a jersey number to a CONTRACT — Player.jerseyNumber IS real; the two read
  sites are guarded so nothing renders "Jersey #0"), and `weeklyAttendance` is
  always empty.
- The drill library is seeded locally every launch by syncActivityLibrary()
  from the bundled activity library. Its presence is NOT evidence that
  CloudKit sync works.

## THE SESSION LAYER — canonical, post-restructure (August 2026)
Phase 2 ended here. Every question about a session has exactly one answer,
and it lives in a service. New code CALLS these; it does not re-derive them.

| question | authority |
|---|---|
| how is a session created? | `SessionCreation` + `DataManager.createSession` |
| what is it called? | `SessionNaming` (stored title is a fallback) |
| is it private? | `SessionPrivacy` (the program's TYPE) |
| what state is it in? | `SessionLifecycle` (isAllowed + apply) |
| did it happen? | `SessionLifecycle.didNotHappen` |
| which phase? | `PhaseAssignment` (from the DATE) |
| what do its phase's words say? | `PhaseNaming` (current language) |
| who is expected? | `AttendanceMath.expectedIds` |
| what does it charge? | `redeemPrivateAttendance` — the ONE authority |
| are the pointers sane? | `SessionReconciler` (repairs), `SessionIntegrity` (counts) |

TWO RULES FOR NEW CODE, both greppable:
1. NEVER construct a `SessionEvent` outside `SessionCreation`. Creation
   derives phase, venue, roster, series and name together; a hand-built record
   gets none of it. The only legitimate direct constructions left are
   `SDSessionEvent` model mapping, `#Preview`/`samples` fixtures, and DEBUG
   scratch records that are deleted in the same function.
2. NEVER read `programId == nil` as a proxy for something else. It means ONE
   thing now — a deliberate one-off — and `SessionCreation.Group.unassigned`
   is how a caller says so. It does NOT mean private (ask `SessionPrivacy`),
   does NOT mean standalone-series (ask `SessionSeries`), and does NOT mean
   "no Live Activity" (ask `SessionSeries.allowsLiveActivity`). Reading it to
   ASK "is this a one-off?" is fine and is what the census, the adoption
   planner and `SessionSeries`' legacy fingerprint fallback do.

SKIP SEMANTICS: skipped and cancelled are the same fact — it did not happen
and will not. `SessionLifecycle.didNotHappen` is the only test. It refunds
what it consumed, it leaves every attendance statistic, and it never appears
as live or next-up. It is NOT a visibility rule: the record stays in the
calendar with its "Skipped: <reason>" note.

PLANS MOVE ON (October 2026, Luther): a class that stops happening (cancel or
skip, any caller — the hook is in `updateSessionEvent`) hands its PLAN to the
next scheduled class of its phase (else program); each later plan moves down
one; completed/live/skipped classes are never rewritten
(Services/SessionPlanShift.swift, both targets — pure; the manager writes in
`shiftPlansAfterStatusChange`). The cancelled class keeps its plan as the
record plus the note marker "Plan moved to the next class". The plan left
over is offered as a MAKE-UP class (`makeUpOffer`, alert via
`.makeUpOfferAlert()` on MainTabView, the session page, the attention sheet
and the Mac RootView — only the most recently appeared host presents) on the
program's next usual day after the phase, at the class's time; accepting
creates it through SessionCreation with "Make-up for <date time>" in its notes
and stretches the phase end to it. REOPENING (reset to scheduled) pulls every
plan back; an untouched make-up (scheduled, no marks) is deleted, otherwise
kept, and without one the last class gets a freshly generated plan. Phase
numbering ("Session N of M") skips classes that did not happen, and the
Profile "Session in N minutes" reminder is removed. HOOPWISE_SHOT=makeUpOffer
shows the question. Tests: SessionPlanShiftTests.

SESSIONS FOLLOW THEIR PROGRAM (October 2026, Luther): `updateProgram` and the
enrollment writers pass each edit on to the program's UPCOMING SCHEDULED
sessions that still follow it (Services/ProgramSessionSync.swift, both
targets, pure): time of day (same day, length kept), length, venue (an empty
venue follows), roster (a stored roster equal to the OLD enrollment; empty
rosters already read the program). A session the coach changed on its own
keeps its value; history never changes. Until then every one of these was
copied at creation and never again — a new student was not expected at
already-scheduled classes. Weekday edits (iOS editor dialog): a SWAP offers
"Move <day> sessions to <day>" (`moveSessions` — nearest new day, plan and
roster kept); removing days still deletes those future classes, but their
plans first REFLOW in date order onto the classes that remain
(`reflowPlans`, gaps kept). Notifications and Live Activities re-sync from
the moved times on the monitor's 30 s tick. Tests: ProgramSessionSyncTests.
ROSTERS TAKE THE CHANGE, NOT A MATCH (18 Nov 2026, Luther: athletes on the
program were missing from the session and not in Add Athlete). The roster
rule used to need the stored roster to EQUAL the old enrolment; one drifted
roster (a guest added, someone removed on that class) and no later enrolment
ever reached it. Now an enrolment edit passes its DIFF on: who joined is
appended, who left is removed, the session's own extras stay. Repair:
`ProgramSessionSync.joining` + `addToUpcomingRosters` — the group session
page's Add Athlete now offers every athlete not EXPECTED at this class
(it hid everyone enrolled in the program, so the missing ones could not be
picked); adding them enrols, puts them on this class and every upcoming
class of the program whose roster is stored.

EXPIRY SEMANTICS: `Contract.expiresOn` derives from `validityMonths` +
`effectiveBundlePurchaseDate`; zero months is a term nobody agreed and never
expires. `isExpired` is display only — an expired contract STAYS `.active`, so
redemption and the private-session rule are unchanged. Making expiry stop a
bundle consuming sessions is an open money decision (see RESTRUCTURE.md).

## History — read before touching git
- This repo was created fresh in July 2026 after migrating to a new
  macOS user account. Single-root history is intentional; all pre-v2.2
  history, branches, and worktrees were deliberately discarded.
- NEVER create git worktrees in this repo. Work on branches in this
  checkout only. The previous setup accumulated 12 orphaned worktrees
  from AI agent sessions and it poisoned the repo.

## Targets
- Hoopwise (iOS) — the app. iPhone today; the iPad version is the current
  direction (November 2026).
- HoopwiseTests, HoopwiseUITests, SAMWidgetsExtension, HoopwiseNotifications
- Bundle ID: OKTO.SAMp — legacy name, do not change; provisioning and the
  iCloud container depend on it.
- Signing: automatic, team Beidy Dubhe Franco Parra

## iPad (decided 6 November 2026, Luther)
- The app is UNIVERSAL (TARGETED_DEVICE_FAMILY "1,2" on the app and both
  extensions). Direction: "iPad-first workflows", shipped WITH 1.0 — the 1.0
  resubmission waits for it and needs iPad screenshots.
- The iPhone stays frozen: iPad work happens only in regular width
  (horizontalSizeClass == .regular), so Split View / Stage Manager narrow
  windows fall back to the iPhone layout.
- Plan: (1) shell — Sessions and Hub → Plays as list/detail split views like
  Athletes already is, Home as a card grid; (2) a courtside session page —
  plan, roster and games visible at once; (3) plays on a big canvas with
  Apple Pencil; (4) iPad App Store screenshots.
- State at the start: Athletes already had a NavigationSplitView on iPad
  (StudentIntelligenceListView.shouldUseSplitView) and works; Home and
  Sessions are the iPhone layout stretched; detail pages push full screen.
- TAB BAR AT THE BOTTOM on iPad too (Luther). iPadOS puts a regular-width
  TabView's bar at the top, so MainTabView forces the TabView compact and
  hands each tab's content the window's real size class back
  (`contentSizeClass`) — split views inside the tabs still see .regular.
  `.sidebarAdaptable` (the top bar + sidebar toggle) is gone.
- PHASE 1 DONE (6 November 2026): regular width only —
  the Hub (FlightyHubView) was a NavigationSplitView (since 15 Nov 2026 a
  full page — see HUB LANDING REDESIGNED): their list on the left, and the rows'
  `NavigationLink(destination:)` land in the detail column by themselves
  (the Hub's detail opens on Plays). Athletes already was one. SESSIONS AS A
  SPLIT VIEW WAS TRIED AND REVERTED (Luther: "not looking good") — the
  Sessions tab stays the full-width calendar/programs page that pushes. Home
  (FlightyActionableDashboard) is two columns: the day (live, briefing, live
  games) | what needs doing (attention, today's athletes). Compact width keeps
  each tab's original NavigationStack.
- ATHLETES LIST LIKE CONTACTS (November 2026, Luther: "size and panel
  arrangement, clarity and style … not a total makeover"), regular width only:
  the list column 340–560 pt (ideal 420), a PLAIN list (grade = small section
  header), `contactsRow` — 40 pt avatar, primaryDisplayName at body size,
  secondaryNameLine under it, the format dot — and the open athlete's row in a
  solid accent highlight with white text; title "Athletes"/学员 inline. The
  profile (StudentDetailView) already had Contacts' shape and is unchanged.
  UPRIGHT TOO (16 Nov 2026, Luther: in portrait the page opened on "Select a
  student" with the list hidden behind the sidebar button): the split view
  is `.balanced` with columnVisibility `.all`, so the list stays beside the
  profile in portrait; nothing open = "Choose an athlete · N athletes".
  THE iPAD MINI UPRIGHT (744 pt) still slid the list away — iPadOS overlays
  a split view's sidebar at that width whatever its visibility — so below
  900 pt the page lays the two panes out ITSELF (list ≤ 340 pt | profile,
  `tiledSplitMinWidth`). For that the Athletes tab no longer wraps the page
  in a NavigationStack (it merged both panes' bars into one); the page owns
  its stacks — the phone branch wraps `mainContent` in one. Rows are
  `athletes.row`. Pinned by AthletesPortraitUITests (iPad Air AND mini; on
  the mini the first launch sometimes comes up without the demo store —
  "0 athletes" — rerun).
  iPhone keeps the inset-grouped Student Intelligence list. On the Mac the
  list hides the iOS 26 scroll-edge effect (`scrollEdgeEffectHidden`): the
  soft edge blur got stuck over the rows after scrolling, sometimes resizing.
  In its place the navigation bar (title + search field) has a fixed `.bar`
  material (toolbarBackgroundVisibility .visible), so rows blur only under
  the header — without it rows ran visibly under the title and search.
- TEST iPAD WORK ON THE iPAD MINI SIMULATOR (Luther, 16 Nov 2026: "for
  testing on ipad use an ipad mini simulator") — iPad mini (A17 Pro),
  54392A20-DA69-46EB-901D-97CB56B19FFF, with HOOPWISE_SCREENSHOT_STORE=1 and
  `-hasOnboarded YES`; its screenshots.store holds the full demo data. The
  mini is the iPad he uses and the narrowest regular width. The iPad Air 13
  M4 sim's demo store is nearly empty — data-dependent tests fail there.

## The Mac app IS the iPad app — Mac Catalyst (6 November 2026, Luther)
"Make this a Mac app: everything as it is for the iPad — views, aesthetic,
functionality." The app target has SUPPORTS_MACCATALYST = YES (SUPPORTED_
PLATFORMS adds macosx); no separate Mac code, so it cannot fall behind
again. Kept at the iPad look (Catalyst's default "Scaled to match iPad"
idiom). What differs on the Mac:
- NO LIVE ACTIVITIES (macOS has none): SessionActivityAttributes and the
  real SessionLiveActivityManager compile only for
  `os(iOS) && !targetEnvironment(macCatalyst)`; Catalyst gets a no-op
  manager with the same calls. New ActivityKit code needs the same guard.
- The widget and notification-content extensions are iOS-only
  (platformFilter = ios on their embed + dependency).
- LSSupportsOpeningDocumentsInPlace is YES (Catalyst refuses NO with
  document types); the .hoopwise import already takes security-scoped
  access, so iPhone behaviour is unchanged.
- EVERY POPUP ON THE MAC opens without animation and window-sized (Luther):
  Utilities/MacPresentation.swift swizzles UIViewController.present (and the
  preferredContentSize setter, because SwiftUI resets a sheet to its ~620×680
  form size after presenting) — Catalyst only, installed in SAMApp.init.
  Alerts, menus, popovers, share sheets and full-screen covers are untouched.
  A CLICK OUTSIDE a popup closes it like an iPad swipe-down
  (OutsideClickDismiss): the presentation delegate is asked first, so
  interactiveDismissDisabled sheets stay open; SwiftUI is told via
  presentationControllerDidDismiss. ESC and ⌘W close the top popup through the
  same path (UIKeyCommand on each popup → hw_closePopup → OutsideClickDismiss.
  close) — added after Luther got STUCK: an athlete page opened from the
  revenue sheet covered the whole window (no outside left to click) and had
  no Done. DEBUG HOOPWISE_TEST_POPUP_CLOSE=1 runs that path 2 s after a popup
  opens (verified: "key: dismissed"). Clicks log their point and the popup's
  bounds.
  WHY THE OUTSIDE CLICK NEVER WORKED (found 9 Nov 2026): a Catalyst sheet is
  its OWN window (`_UIBridgedPresentationWindow`, popup-sized) and AppKit
  blocks the main window behind it — clicks on the dimmed area never reach
  the app (the log only ever shows "click inside"), and nothing placed
  outside a popup can be clicked. So PopupDoneButton puts a Done at the
  LEADING end of the popup's own navigation bar, ONLY when that bar has no
  leading item and no Done/Cancel/Close/Save/OK (完成/取消/关闭/保存) among
  its items, on the stack's root (a pushed page has Back). Luther: a second
  Done beside the popup's own is a blunder — a bottom Done bar on every
  popup was tried and removed for that. Re-checked every 0.4 s (SwiftUI
  rebuilds bar items). Popups with no navigation bar get nothing (Esc/⌘W).
  Verified 9 Nov over 12 gallery shots: added on drillDetail and
  studentProfile only. DEBUG HOOPWISE_POPUP_NAVDUMP=1 logs each popup's bar
  items (=exit: the demo copy quits itself after — use it, demo copies
  cannot be killed from here); HOOPWISE_TEST_POPUP_CLOSE=button reports
  whether a popup got a Done.
  Each sheet logs its final size: `/usr/bin/log show --predicate
  'subsystem == "hoopwise.mac"'` (zsh's own `log` shadows /usr/bin/log; and
  NSLog text is <private> on macOS — use Logger with privacy: .public).
  Verified with HOOPWISE_SHOT=quickPeep: 620×680 → 962×1410.
- MAC WINDOW (Luther: "more adapted to the Mac, without drifting too far"):
  only chrome — MacWindow.configure() (MainTabView.onAppear, Catalyst) hides
  the title text and toolbar strip and sets a 900×680 minimum; SAMApp adds a
  View menu with ⌘1–⌘4 for the four tabs (.hoopwiseSelectTab). The screens
  keep the iPad look; Catalyst's "Optimize for Mac" idiom (Mac-drawn controls)
  was deliberately NOT taken — that is the drift he did not want.
- DESCRIBE A DRILL (9 Nov 2026, Luther: drills could only be found by exact
  name inside the right age and type). Mac only, in the drills page's OWN
  search bar (Luther: no special button): typing filters as before; RETURN
  (`onSubmit(of: .search)`) asks Claude and shows "Claude suggests" above the
  list (rows: name, age · block · type or Personal, why; a newer search or a
  changed field drops a slow answer). Services/DrillFinder.swift. CLAUDE (claude-haiku-4-5, raw URLSession —
  Swift has no Anthropic SDK) reads the WHOLE catalog every search: every
  plannable library activity (one line: ref | age · block · type | name /
  中文 | how it runs ≤ 320 chars) — the library half CACHED (cache_control
  ephemeral; ~35k tokens, above Haiku 4.5's 4096 minimum) — plus personal
  drills after the breakpoint; strict JSON (output_config.format
  json_schema): up to 6 {id, why} + note. "why" says what matches and what
  differs ("counts to 20, not 10"). Only drill text is sent. WHY NOT
  ON-DEVICE ALONE: for his example ("pass 10 times to score while the other
  team defends" = "20 Passes, Keeping Off", U7 small games) NLEmbedding,
  NLContextualEmbedding, BM25 and their fusion ranked it 41st at best. The
  fused on-device ranking (lemmas + coaching synonyms + sentence embedding)
  is the FALLBACK with no key / no connection. The key lives in the Mac's
  Keychain (AnthropicKeyStore), set in Profile → "Claude in the app" (under
  Claude Desktop); Configuration.xcconfig's
  ANTHROPIC_API_KEY is empty and unused. The target gained
  ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES (the sandbox had incoming only).
  Tests: DrillFinderTests (catalog, request shape/caching, parsing,
  fallback, Keychain).
  SESSION PLAN PICKER TOO (9 Nov 2026, Luther: "search when adding drills to
  the plan"): SmartDrillPickerSheet (FlightySessionPageView). Typing now
  searches EVERY drill the coach can see (it searched only the suggestions
  while "Smart Suggestions" was on) and matches every typed word anywhere in
  name, Chinese name, description and instructions (`DrillFinder.typedMatch`)
  — all platforms. Mac only: Return asks Claude (same DrillFinder, catalog
  `DrillFinder.entries(for:)`); its picks sit above the typed matches as
  normal rows with the why, a tap adds the drill. HOOPWISE_SHOT=drillPicker
  + HOOPWISE_DRILLPICKER_SEARCH=<text> (+ _ASK=1 on the Mac) logs both to
  hoopwise.mac / drillPicker. Verified live on the demo copy with the
  coach's key: his description → 20 Passes, 20 Passes Keeping Off, ….
  Tests: DrillTypedSearchTests.
  THE PICKER IS THE LIBRARY (11 Nov 2026, Luther: "reflect the drills
  library properly with the same search bar"): SmartDrillPickerSheet is now
  `DrillsLibraryView(pick:)` — the same page (age chips, block segments, type
  chips, Personal, search across the whole library, Claude on Return on the
  Mac) with an add button beside each drill row (a green check once in the
  section; a tap adds and closes, as before); rows still open the drill.
  Title "Add to Warm-up / Skills"; the age starts at the program's library
  age, Warm-up opens on Routine and Skills on Compete; the picker remembers
  its own age (`planPicker.age`) apart from the page's (`library.age`); no +
  New Drill there. The old Smart Suggestions / category chips / level dots
  are deleted. HOOPWISE_SHOT=drillPicker (+ HOOPWISE_DRILLPICKER_SEARCH).
- NEW DRILL: RETURN WRITES THE STEPS (11 Nov 2026, Luther: "after writing
  the description and pressing enter, have Claude interpret it and fill in
  the steps and key points … no visual cues besides a spin wheel next to
  Description"). AddDrillView: Return in the description (the text grew by
  one trailing line break — `DrillWriter.pressedReturn`; the break is
  dropped) sends name + description + players + minutes to Claude
  (Services/DrillWriter.swift — same model, key and raw call as DrillFinder;
  strict JSON {instructions, keyPoints}); a mini ProgressView beside
  "Description" while it works. It fills a list only when blank or still
  exactly its last answer (`mayReplace`) — never over the coach's typing.
  No key / no network / error: nothing changes, quietly. The key exists only
  where Profile → "Claude in the app" can set it — the Mac today. DEBUG
  HOOPWISE_SHOT=newDrill + HOOPWISE_NEWDRILL_DESCRIPTION=<text> types it,
  presses Return and logs hoopwise.mac / drillWriter (verified live on the
  demo copy, ~6 s: five steps, three points). Tests: DrillWriterTests.
  EDIT DRILL IS THE SAME FORM (11 Nov 2026, Luther: "make it work when
  editing … and make the edit drill UI match the create drill one"):
  `AddDrillView(editing:)` — prefilled, title Edit Drill, Save writes onto a
  COPY of the stored drill (updateDrill; never a rebuilt record), the Visual
  section hidden (visuals live on the drill page); Return in the description
  works there too and fills only blank lists. The old card-style
  EditDrillView is deleted; AddEditDrillSheet → AddDrillView(editing:).
  HOOPWISE_SHOT=newDrill + HOOPWISE_EDIT_DRILL=<name> opens it.
- RIGHT-CLICK MENUS + COMMANDS (Luther, November 2026), Catalyst only —
  Views/Components/MacMenus.swift: `.sessionMacMenu(session)` on calendar rows
  (Open → .hoopwiseOpenSessionRequest; Mark Everyone Present, confirmed, via
  setStudentAttendanceStates; Copy Details) and `.athleteMacMenu(student)` on
  athlete rows (Open Profile, Edit → EditStudentView, Copy Name). On iPhone
  and iPad they add NOTHING (no long-press menus — the freeze). File: ⌘N New
  Session (Sessions → calendar → Add Session sheet), ⇧⌘N New Athlete
  (Athletes → Add); Edit: ⌘F Find Athlete (Athletes, search focused via
  .searchFocused). MainTabView.switchThenPost shows the tab, then signals it.
  DEBUG HOOPWISE_MAC_COMMAND=newSession|newAthlete|find fires one at launch
  (verified: both sheets open). ⌘F first did nothing: the system Find group
  owned ⌘F (now `CommandGroup(replacing: .textEditing)`), and `.searchFocused`
  is not enough on Catalyst — MacSearch.focusFirstSearchField makes the
  UISearchTextField first responder (verified via the hook: "search field
  focused true"). Menu commands log "command …" to hoopwise.mac.
- Run a Mac debug shot: `open -n --env HOOPWISE_SCREENSHOT_STORE=1 --env
  HOOPWISE_SHOT=<shot> <Debug-maccatalyst>/Hoopwise.app` (screencapture is not
  permitted here, so check results through that log).
- Build: `xcodebuild -scheme Hoopwise -destination 'platform=macOS,variant=Mac Catalyst'`.
  The Mac build uses the SAME bundle ID as iPhone/iPad, OKTO.SAMp
  (DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO — Luther, 6 November
  2026: one App Store listing, Universal Purchase, same iCloud). Signed with
  "Mac Catalyst Team Provisioning Profile: OKTO.SAMp" (created then, with his
  OK). A debug Mac build reads CloudKit DEVELOPMENT, like the phone's.

## Claude Desktop connector (Mac only, 6 November 2026, Luther)
"A connector for me to tell Claude Desktop to do stuff in the app instead of
clicking through." Services/ClaudeConnector/ (Catalyst only):
- ConnectorServer: an MCP server (JSON-RPC 2.0 over HTTP POST) on
  127.0.0.1:47720 ONLY, started in SAMApp.init. Every request needs the
  per-Mac access key (Bearer; UserDefaults `connector.token`; DEBUG env
  HOOPWISE_CONNECTOR_TOKEN forces one for tests). The app is SANDBOXED, so it
  may listen only through ENABLE_INCOMING_NETWORK_CONNECTIONS, and it cannot
  write where Claude Desktop reads.
- The bridge tools/claude-connector/hoopwise-connector.py (stdio ⇄ HTTP,
  stdlib Python) is installed OUTSIDE the app at ~/Library/Application
  Support/Hoopwise Connector/. Claude Desktop's config passes HOOPWISE_URL and
  HOOPWISE_TOKEN as env; Profile → Claude Desktop → "Copy setup" puts that
  config entry (key included) on the clipboard.
- ConnectorTools: the retired Mac Whistle's tool registry, ported (tag
  mac-app-final). THE RULE stands: tools call the shared business layer only
  (SessionCreation, SessionLifecycle, setStudentEnrollment,
  setStudentAttendanceStates → the one redemption authority,
  updateSessionEvent(keepLiveFields: true), updateContract). New:
  mark_attendance (present / excused / unmarked, or all_present — never
  absent, it is inferred). open_in_app posts the widget deep-link
  notifications. DELETE TOOLS SINCE 8 NOV 2026 (Luther reversed "no delete"
  after Claude Desktop recorded a shared private lesson as two sessions) —
  see "PUTTING THINGS RIGHT" below; athletes, contracts and payments are
  still never deleted from here. Data minimisation ON by default
  (`assistant.minimized`): guardian contacts and money stay in the app.
  Claude Desktop asks before each call; there is no in-app confirmation.
- SHORT REFS (6 Nov 2026, after Claude Desktop's get_session/update_session
  failed on ids list_sessions had just returned — a model mis-copies 36-char
  UUIDs): every id the tools RETURN is the first 8 hex chars; every id they
  TAKE may be a ref (unique prefix ≥ 6), a full id in any case, or for
  sessions `when` (ISO start) + `program`. Failed lookups name what was sent
  and list candidates. Roster tools: add_to_session / remove_from_session
  (ONE session; an empty roster is first filled from AttendanceMath.
  expectedIds so adding one child doesn't make them the only one expected),
  add_to_program (addStudentEnrollment — ADDS; set_enrollment MOVES and says
  so). school_grade on create/update_athlete via Student.setSchoolGrade
  (K1–K3, P1–P6, H1–H6; 初一…高三 accepted). create_athlete takes a Chinese
  name alone (pinyin name) and an optional session_id. 19 tools.
- Verified 6 Nov 2026 on the demo copy: initialize, tools/list (16 tools),
  search/get/list, a write (record_note), a refusal, and a wrong key (401 →
  "access key is wrong").
- PLAYS TOOLS (November 2026, Luther: Claude creates plays and saves them in
  the library, from conversations or concepts he feeds it — "accurate and
  fully use the capabilities"). Services/ClaudeConnector/ConnectorPlayTools.
  swift, thin over Models/JournalPlays/JournalPlayAuthoring.swift (shared,
  pure-ish, tested on the simulator — JournalPlayAuthoringTests):
  get_play_drawing_guide (READ FIRST: court metres + landmarks, the format,
  playback rules — `JournalPlayAuthoring.guide`), list_plays, get_play (the
  SAME format create_play takes, so a play round-trips), create_play (whole
  play: steps + wrinkles + variations), update_play (details; court change
  converts), add_play_part, add_play_step, update_play_step,
  add_play_to_session (curriculum.plays, keepLiveFields); get_session shows
  plan_plays. FORMAT = the drawing model in metres with three conveniences:
  a step CARRIES OVER from the previous step's end; a move's path may be just
  its destination (it starts at the player); a pass names its receiver
  ("to") and a shot nothing — drawn from where players are at that moment,
  as the editor snaps. Validate everything, then write (a bad field names
  itself — "steps[1].actions[0]: …" — and saves nothing); warnings (a pass
  without a ball, crowded players, long notes) save but come back. play_id =
  starter key, else "p" + creation ms in base 36; a name also resolves.
  (Play deletes came later — see PUTTING THINGS RIGHT.) Verified 8 Nov 2026 over HTTP on the Mac demo copy
  (HOOPWISE_SCREENSHOT_STORE=1 + HOOPWISE_CONNECTOR_TOKEN): initialize
  mentions plays, tools/list, guide, create_play, a refused bad pass,
  get_play, list_plays, add_play_to_session twice (second: already_in_plan),
  get_session plan_plays. Verify on a demo copy BESIDE the coach's app:
  `open -n --env HOOPWISE_SCREENSHOT_STORE=1 --env HOOPWISE_CONNECTOR_TOKEN=…
  --env HOOPWISE_CONNECTOR_PORT=47721 <app>` (DEBUG port override) — never
  quit his app for it (he may have an edit open; a quit was refused once).
- FIXES + PUTTING THINGS RIGHT (8 Nov 2026, after the two-sessions /
  notes-in-the-contact-log / inferred-absent mess). Fixes: create_session
  and update_session take `notes` (appended; replace_notes); create_session
  explains a SHARED PRIVATE LESSON = ONE session, every client on the roster
  (each charged from their own bundle — redeemPrivateAttendance is per
  athlete), returns the roster's names and says when it came from program
  enrolment; programs resolve exact-then-unique (findProgram), never "first
  containing"; update_session's move is `new_start` (it read `when` while the
  schema said `starts` — every move was silently ignored); record_note says
  it is the athlete's CONTACT LOG, not session content. New
  (ConnectorCareTools.swift, each through the one authority): list_charges
  (bundleSessionIds with marks; flags a session on two balances),
  list_athlete_notes, delete_session (deleteSessionEvent → refunds),
  skip_session, complete_session (start→complete for a never-run one),
  reopen_session, refund_session (refundSessionToBundle), remove_from_program
  (NEW writer `removeStudentEnrollment` — one roster, primary moves;
  RemoveEnrollmentTests), delete_athlete_note, remove_play_from_session,
  delete_play / delete_play_part (not the concept) / delete_play_step (not a
  part's last). `ConnectorTool.destructive` → MCP destructiveHint. 41 tools.
  All verified over HTTP on the demo copy, 8 Nov 2026.
- DRILLS + PERSONAL (8 Nov 2026, Luther: "a category called Personal …
  where Claude would drop new drills"). The library's "Mine" chip is now
  PERSONAL (个人) — still every non-library drill (`!isLibraryDrill`): the
  coach's own and Claude's (twenty-second sanctioned exception, wording only).
  ConnectorDrillTools.swift: list_drills (personal by default; scope all),
  get_drill, create_drill (owner = the coach, tags visibility:private +
  owner: + `by:claude`; refuses a duplicate personal name), update_drill /
  delete_drill (PERSONAL only — library activities are re-seeded every
  launch, so they are refused with that reason), add_drill_to_session /
  remove_drill_from_session (Warm-up or Skills — the plan tab shows no Game
  section; keepLiveFields). A series of progressions of one exercise is ONE
  drill, one instruction per progression. 48 tools. Verified over HTTP on the
  demo copy with "Game simulation action series: Drive and kick".

## THE MAC APP IS RETIRED (6 November 2026, Luther)
"The Mac version is behind in many aspects … we've failed to make something
remotely close to usable." The HoopwiseMac target, its folder and scheme are
DELETED; its last state is the git tag `mac-app-final` (court/play editor,
Whistle assistant, Mac directory pages, Mac Settings). Consequences:
- There is ONE app target. Shared code no longer needs a second membership,
  and the `membershipExceptions` opt-in list described below no longer
  exists for a Mac target.
- `#if os(macOS)` branches in shared files are now dead code. Remove them
  when touching a file; there is no rush.
- The SwiftData models only the Mac wrote (SDPlay, SDPlayDiagram,
  SDConceptNode, SDConceptLink, SDDirectoryGroup) STAY in the schema:
  CloudKit record types cannot be removed, and dropping a model from the
  schema is a schema change (rule 5).
- Sections below that describe Mac screens, the court editor, the Whistle or
  Mac attendance are HISTORY — they describe code that now lives only at
  `mac-app-final`. Do not build against them.

## Hard rules
1. (Retired with the Mac app.) It said every shared file needed BOTH
   target memberships. One app target now; new files in Hoopwise/ join it
   automatically (synchronized folder). Widget/notification-extension
   membership is still an explicit opt-in list in project.pbxproj.
2. NEVER commit Configuration.xcconfig. It is gitignored and holds AI
   API keys (Anthropic/Gemini/Groq) for the Assistant Coach feature,
   surfaced via INFOPLIST_KEY_* substitutions. If it is missing, the
   build fails with "Unable to open base configuration reference file."
3. iPhone/iPad differences go by size class (horizontalSizeClass), not by
   device checks, so Split View and Stage Manager work. Prefer
   platform-neutral types (Data over UIImage) in models.
4. Do not add .claude/, build/, or xcuserdata to git. Check .gitignore
   before staging.
5. Do not change SwiftData model schemas without explicit approval. The
   schema is already CloudKit-compatible and iOS depends on it.
6. Never replicate a non-functional control to a second layout. Fix it on
   iPhone and iPad or remove it.
7. ADDING A SWIFTDATA MODEL is a five-step operation, in this order.
   Skipping 3 or 4 makes a released build write record types Production
   does not know, which fails silently.
   a. New model in Hoopwise/Models/SwiftData/.
      Every property needs a default or must be optional; no
      @Attribute(.unique); all relationships optional. CloudKit requires
      this and the existing models already follow it.
   b. Register it in the Schema([...]) array in SwiftDataManager.
   c. Run the app once in Debug so SwiftData materializes the
      Development schema.
   d. Deploy Development to Production in CloudKit Console by hand.
      Nothing automates this.
   e. Ship a build carrying the types before relying on them in a release.
   Define new record types in ONE pass and deploy once. Each extra deploy
   costs another iOS release, and TestFlight review time gates it. Empty
   models cost nothing to carry.

## iCloud / CloudKit environment gotchas (written for the Mac; still true)
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
- THE MOVE TO PRODUCTION (built 15 November 2026, Luther: TestFlight on the
  iPad showed none of his data). Services/ProductionMove.swift. RELEASE
  BUILDS NOW KEEP THEIR STORE IN `production.store`; debug builds keep
  `default.store` (both in the App Group's Application Support, which debug
  and TestFlight builds share on a device — before this a TestFlight build
  installed over a debug build would have opened the Development copy with
  the Production database). Every debug build writes `default.store.
  development` beside its store. A release build that finds that marker
  offers Profile → Sync → "Bring over your data": it sets a flag and quits;
  at the next launch, BEFORE SwiftData opens, a Core Data copy brings every
  attribute and relationship of every entity (SwiftDataManager.modelTypes →
  NSManagedObjectModel.makeManagedObjectModel) from a temporary copy of
  default.store into production.store, with persistent history on so the
  mirroring uploads it to Production. Rows with the same `id` replace what
  the release build seeded first; SDCoach / SDAppSettings are replaced
  outright; then every row is compared attribute by attribute and the
  report shows in Profile (counts, "every field checked"). The source is
  never written. DEBUG rehearsal: HOOPWISE_MOVE_REHEARSAL=demo|real|paths
  (copies into a temp store, checks, opens it with SwiftData — plays' parts
  and steps attached, contracts' charges and payments — logs hoopwise.mac /
  move, quits before any store opens; on the Mac run it as a second
  instance with `open -n --env …`). Rehearsed 15 Nov 2026 on the REAL Mac
  Development copy: 22 entity types, 171 athletes, 406 sessions, 216
  contracts (191 charged sessions), 23 plays / 40 parts / 99 steps, 0
  mismatched rows. SCHEMA COMPLETENESS: CloudKit adds a field only when a
  record carrying it is uploaded, so DEBUG HOOPWISE_INIT_CLOUDKIT_SCHEMA=1
  runs Core Data's initializeCloudKitSchema over the full model (samples of
  every type and field to DEVELOPMENT, then deleted; quits after). Ran 15
  Nov 2026 on the Mac: "initialized in Development — 27 record types" (the
  first try timed out at 30 s; the second passed). Run it again before any
  future deploy that adds fields. CUT-OVER: (1) Luther deploys the schema Dev→Production in
  CloudKit Console; (2) archive + upload a TestFlight build; (3) on the Mac
  (most complete copy) install TestFlight, Profile → Bring over your data,
  reopen, check the report; (4) wait for the upload; (5) TestFlight on the
  iPhone and iPad. The store holds TWO SDCoach and TWO SDAppSettings rows
  (made on two devices) — carried over as they are; worth a clean-up.
  FIRST REAL ATTEMPT FAILED SILENTLY (build 30, 15 Nov 2026, iPhone): the
  request was a UserDefaults bool followed by exit(0); the write never
  reached disk (the app's prefs plist is 33 MB, almost all
  `session_notes_board_v1`), so the next launch did nothing — no report, no
  data. Pulled the phone's prefs with `devicectl device copy from
  --domain-type appDataContainer` to prove it. FIX (build 31): the request
  and the report are FILES beside the store (`production-move.pending`,
  `production-move.report.json`, atomic writes). SECOND BUG FOUND THE SAME
  TIME: external-storage values (athlete / coach / own photos, revision
  snapshots) live in `.default_SUPPORT/_EXTERNAL_DATA`, which the copy did
  not take — both sides read empty, so the check passed. The copy now takes
  the support folder and the report counts them: real Mac rehearsal 795
  files (23 MB), 0 mismatched rows, 0.4 s.
  DONE 16 November 2026: build 31's move ran on the iPhone and the data
  reached Production — Luther confirmed it on the iPhone and iPad. FROM NOW
  ON the TestFlight build is the REAL app on his devices. A debug install to
  his iPhone or iPad REPLACES it (same bundle id) and points that device back
  at the stale Development copy — never install a debug build on his devices
  unless he asks; ship changes as TestFlight builds. The Mac still runs a
  debug Catalyst build (Development): real edits made there no longer reach
  the phone until a Mac TestFlight build replaces it.
  FIRST MAC TESTFLIGHT BUILD: 2.1 (39), 17 Nov 2026 (archive with
  `-destination 'generic/platform=macOS,variant=Mac Catalyst'`, same
  export.plist upload; one build-number counter for both platforms). Once
  the coach runs it, the Mac reads Production like the phone.
  OFFER SWITCHED OFF (17 Nov 2026, before the first Mac TestFlight build):
  `ProductionMove.isOffered` is now always false — the Mac's debug builds left
  a Development copy and its marker, and "Bring over your data" there would
  have replaced rows edited on the phone since with stale ones. The copy code
  and the DEBUG rehearsal stay.
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
- SECOND sanctioned exception (October 2026, Luther's request): the
  attendance control became a native iOS switch (present / absent) in place
  of the four-button strip. Superseded the same month by the FIFTH exception
  (three-position switch, roster as a List) — see "Attendance UI".
- THIRD sanctioned exception (October 2026, Luther's request): the iOS
  "Parent Notice" screen (ParentProgramSummaryView) became the Parent Guide
  screen — PDF preview, wording editor, PDF and long-image share. Approval
  covers that diff only. See "Documents → ProgramGuideDocument".
- FOURTH sanctioned exception (October 2026, Luther's request): the program
  page's hero tile (FlightyProgramDetailView.mascotTile) shows the age
  category ("U8") instead of the mascot SF Symbol; a coach-uploaded category
  icon still wins. Approval covers that diff only.
- FIFTH sanctioned exception (October 2026, Luther's request): the
  three-position attendance switch, inferred absence, and the session
  roster as a List so swipes fire. See "Attendance UI".
- SIXTH sanctioned exception (October 2026, Luther's request): the coach's
  class-list spreadsheet (上课名单.xlsx) is importable AND exportable on
  iPhone as well as Mac.
- SEVENTH sanctioned exception (October 2026, Luther's request): the
  profile-photo camera (Views/Components/ProfilePhotoCamera.swift — back
  camera, full screen, the avatar circle as a mask, the photo cropped to that
  circle's square, no edit step; replaces UIImagePickerController on the
  add/edit-student paths) and the edit-student school grade as ONE menu row
  instead of three chip grids. ProfilePhotoCropTests pins the crop; the
  preview→sensor mapping needs a real device. SHARPNESS (October 2026):
  the camera opens the VIRTUAL multi-lens device (triple → dual-wide → dual
  → wide; `bestDevice`) framed at the wide lens's 1× (`wideZoomFactor` = the
  first switch-over factor when an ultra-wide is present), so iOS switches
  lenses itself — ultra-wide macro when the child is too close, which the
  plain wide camera it used could not focus. Continuous focus/exposure on
  the circle's centre, tap to refocus, the shutter waits ≤ 0.6 s for focus,
  capture at .balanced (was .speed — no multi-frame deblur indoors).
  ProfileCameraLensTests pins the lens order and framing; the actual
  sharpness needs a real iPhone (the simulator has no camera).
- EIGHTH sanctioned exception (October 2026, Luther's request): the student
  quick peep (Components/StudentQuickPeepView.swift) has an "Edit Student"
  toolbar button that opens the same EditStudentView as the profile, so a
  coach can fix a record mid-session. The peep re-reads the student from the
  store, so the edit shows at once. Pinned by
  AttendanceSwipeUITests.testQuickPeepFromSessionOffersEdit.
- NINTH sanctioned exception (October 2026, Luther's request): the live
  session screen (LiveSessionView — drill timeline, End Session) is DELETED,
  and there is no Start Session button. Sessions START BY THEMSELVES:
  SessionStatusMonitor (both platforms, 30s tick) applies
  SessionLifecycle .start to any session where
  `SessionLifecycle.shouldAutoStart` holds — scheduled, start reached, end
  not reached, not skipped/cancelled. Status only, never attendance, and
  NEVER auto-complete (completion stays Complete Session, or the marked
  auto-close at end + 12h). The in-app LiveSessionEngine survives as the
  clock for the Lock Screen Live Activity (now gated by
  SessionSeries.allowsLiveActivity), the tab-bar pill and the home card;
  their taps open the SESSION PAGE. Complete Session ends the engine and
  opens RollCallPhotoSheet (Views/Components, reason .completed) unless a
  roll-call photo already exists. A past session that never ran is started
  then completed by "Mark Completed" — `.complete` is only legal from
  in progress, and that button used to save without changing the status.
  Covered by AutoStartTests.
- TENTH sanctioned exception (October 2026, Luther's request): the session
  roster's LEADING swipe is "Photo" — the masked back camera
  (ProfilePhotoCamera) straight to the shutter, no library; the capture
  replaces the student's profileImageData + thumbnail via updateStudent.
  It replaced the Metrics swipe (Quick Measure). StudentAvatarView now
  reloads when thumbnailImageData changes — its cache is keyed by id alone,
  so a retaken photo (here or in Edit Student) used to stay stale until
  relaunch. Pinned by AttendanceSwipeUITests.testLeadingSwipeOpensProfileCamera.
- ELEVENTH sanctioned exception (October 2026, Luther's request): in
  Chinese, a student's CHINESE NAME is the big line and pinyin the small one,
  everywhere (iOS + Mac), as Student Intelligence already did. Views read
  `Student.primaryDisplayName` + `secondaryNameLine`; never hand-pick
  `name`/`chineseName` for a student label. An empty or identical Chinese
  name counts as absent (it used to render a blank name). NOT done: the
  home-screen widgets — the widget process cannot read the app language
  (standard UserDefaults "app_language", not the App Group); fixing it means
  an optional language field in the widget snapshot. Exports, search and
  NameIndex collation are unchanged. Pinned by StudentNameLinesTests.
- The session roster's right-to-left swipe (Clear, Refund) was removed the
  same month at Luther's request — see "Attendance UI".
- TWELFTH sanctioned exception (October 2026, Luther's request, field use
  during games): the iPhone live-game screen (LiveGameScoringView's iPhone
  branch → `liveScoreboard` + `liveEntry` + Views/Coaching/LiveTeamPanel.swift).
  ONE team at a time; the scores are the team switcher (rows slide). Every
  player on screen, no scrolling: photo, pinyin + Chinese name (Chinese first
  in Chinese), stats, points. The ROW is the points target — tap = basket at
  the strip's value (+1 / +2 / +3; the game's STANDARD value, chosen on the
  setup page and stored as `SessionGame.basketValue` inside the games JSON —
  not a schema column, old games read 2 — is preselected and marked, and the
  strip returns to it after each basket; the last choice is remembered in
  UserDefaults `game.standardBasketValue`);
  press and DRAG onto a teammate's row = basket + assist (`AssistDrop`), a
  line follows the finger, release elsewhere = basket only. REB / STL / BLK
  are fixed colour-coded StatPressButtons with icons (tap add, hold removes
  one); REB is the big one because it is the most frequent.
  Points are corrected with Undo (`GameStatAction` log, view-local) — a hold
  on the row would collide with starting a drag. Battle Royal is unchanged.
  REFINED + ON THE iPAD (10 November 2026, Luther: "don't let it look low
  quality … the assist line looks grotesque"): the iPad / Mac (regular
  width, two teams) now use THIS entry, both teams' LiveTeamPanels side by
  side under one value strip (`liveEntryWide`; scores not a switcher there)
  — the old two-column screen (per-player +1/+2/+3, near-invisible on a dark
  team) is no longer reached. The assist line is ONE RED LINE (3 pt) WITH AN
  ARROWHEAD from where the finger went down to where it is now — no snapping
  to photos (Luther: "start where I touch and end where I drag it to"; a
  curve + halo + dots + name pill was "over complicated"); the target row gets an accent ring and a slight lift, the
  source a tint (it was a 4 pt dashed line in the team colour — black for
  the black team — and a 3 pt border). StatPressButton sizes its symbol from
  its own height inside an inset: over the word when tall, BESIDE it when
  short (STL / BLK on the phone), the word alone when tiny. Rows cap at
  150 pt. TEAM COLOUR ON SCREEN is `GameTeam.displayColor(for:)`: a
  near-black team is light grey in dark mode, a near-white team mid-grey in
  light mode (the black team's rows, points and score vanished in dark
  mode). The stat line is ONE line when it fits, else TWO even lines
  (REB · AST / STL · BLK) — never truncated. HOOPWISE_LIVE_BLACK=1 makes the
  gallery's home team black. DEBUG HOOPWISE_LIVE_ASSIST_DEMO=1 freezes a pass for screenshots;
  HOOPWISE_SHOT=liveGame is now a full-screen cover, as in the app. Every stat button goes through
  `StatPressButton` + `StatPressGate`: the old Button + simultaneous long
  press removed on hold and RE-ADDED on release. Tests: StatPressGateTests,
  LiveGameEntryTests, LiveGameStatUITests, LiveGameAssistUITests
  (HOOPWISE_SHOT=liveGame).
  WHO IS UP (19 Nov 2026, Luther): with more than two teams, a team on the
  scoreboard is a MENU ("Who's up instead?" → each waiting team; on the
  phone also "Show <team>'s players") only while `lineupEditable` — clock
  never run (timerSeconds 0, not running), no stat, no basket, no score.
  The chosen team takes that slot in activeTeamIds and the replaced team
  takes its place in the queue (teams swapped). A chevron marks it.
  HOOPWISE_LIVE_TEAMS=3 (liveGame) adds a waiting Yellow. Test:
  LiveGameLineupUITests (iPad mini; the first launch of a run sometimes
  comes up without its environment — rerun).
  GAME SETUP AS SLOTS (20 Nov 2026, Luther, markup on Create Game): a FORMAT
  2v2 · 3v3 · 4v4 · 5v5 (`SessionGame.playersPerSide`, remembered in
  `game.playersPerSide`); each team is a row of photo slots with names —
  STARTER slots (the format's count, solid team ring) | BENCH slots (dashed;
  at least two, always one free); the roster ("Roster", was Unassigned) is a
  grid of photos with names. Drag and drop everywhere: onto a filled slot =
  SWAP (the other goes where the dragged one came from — slot, team or
  roster), onto an empty starter slot = joins the starters, onto a bench
  slot = end of the bench, onto the roster = off the team. A TAP opens a
  popover: Make a starter / Move to the bench, To <team>, Back to the roster.
  `GameTeam.starters` (optional, in the games JSON) = how many leading
  playerIds start, so the bench can hold players while a starter slot is
  open; quick assign fills starters first. The page is a ScrollView of cards
  (`SetupCard`), NOT a Form: inside a List, iOS drags the whole ROW, so a
  single player could not be dragged. A tap uses a popover, not a Menu (a
  Menu swallows the long press a drag needs). The live game still shows
  every player of a team; starters/bench are recorded, not yet used there.
  Test: CreateGameSlotsUITests (iPad mini; slow drag with a hold).
  IN-APP CARRY, NOT SYSTEM DRAG AND DROP (21 Nov 2026, Luther: the drag and
  drop crashed the app on the court; "clean like dragging apps on iOS … no
  hand holding"). `.draggable` / `.dropDestination` are gone (the system
  preview renders outside the page — StudentAvatarView's DataManager is not
  there — and the drop wrote the teams mid-redraw). Now `carryGesture`: a
  LongPress (0.3 s) sequenced before a Drag, as a SIMULTANEOUS gesture on the
  player's Button (tap still opens options; a tap within 0.4 s after a carry
  is ignored). The player lifts (bump), rides above the page (`carriedGhost`,
  ×1.2 with a shadow) — its own spot fades — the slot under it swells, a
  tick on each new target; letting go drops it (player = swap, empty slot or
  team row = join, roster = off; elsewhere = back). Drop targets register
  their frames ON SCREEN (`.dropTarget`, TargetFrameKey, frame(in: .global)
  — re-measured as the page scrolls); players register `p.<id>`. ONE
  page-level gesture (`pageCarryGesture`, simultaneous on the page content):
  a LongPress (0.3 s) sequenced before a Drag in GLOBAL space; at the start
  it finds whose `p.` frame holds the finger. WHAT BROKE ON THE WAY (found
  by driving the iPad mini simulator with real touch paths — the XCUITest
  drag passed throughout and proved nothing): (1) a gesture per player:
  after a swap, the slot's still-running gesture picked up the newcomer;
  (2) `.scrollDisabled(carrying != nil)` CANCELS the touch in progress the
  moment the player lifts — never toggle it during a gesture; (3) frames
  and locations in the page's NAMED space came back 70–1500 pt off (lazy
  grid, popover-wrapped buttons) — screen space is the one that matched;
  (4) the edge auto-scroll must not move the carried point itself (it ran
  away to y ≈ 4700) — targets are re-measured as the page moves. The ghost
  rides an overlay on the scroll view, placed at finger − overlay origin.
 No hint texts (the teams footer
  and the empty-roster sentence went; an empty roster is a dashed icon).
  SAME NIGHT, three follow-ups (Luther, markups):
  · SETTINGS IN ONE CARD ("take unreasonable space — make it smarter"): the
    game type, then four chips — FORMAT · TIME · BASKET · PLAYERS — each a
    tap-to-change menu showing its value (`settingChip`); the explanations
    are gone; "Last game's teams" is a small toggle in the Teams header.
  · THE LIVE SCREEN SHOWS THE FLOOR ONLY: LiveTeamPanel rows = the team's
    first `starters` players (older games without starters: everyone), then
    a dashed BENCH strip (`live.bench`). Sub: DRAG a bench player onto a
    floor player (anywhere across that row's height — `subTarget`), or TAP
    him → "<name> in for…" lists who is on the floor (`live.sub.out`). They
    swap places in playerIds; stats stay with each player.
  · NEXT GAME (the top button; was "Next Round", which reset the same game in
    place): finishes and saves this game (winner, W–L) and opens a NEW game —
    same teams and lineups, same minutes / value / format (`startNextGame`,
    `onNextGame` → the games tab appends it and presents it). Two teams: at
    once. More: a sheet "Who plays next?" (`NextTeamsChooser`) — winner and
    the next waiting team preselected — then Start Game N. The new game opens
    READY (the coach starts the clock).
  Tests: LiveGameBenchUITests (HOOPWISE_LIVE_BENCH=1 on liveGame = 3v3 with
  two on each bench). The gallery's live game keeps its roster in @State —
  its scratch players got new ids on every redraw and the White team vanished.
  LiveGameAssistUITests' "five on screen" / "switching team" expect the
  iPhone layout and fail on the iPad mini (both teams side by side).
  WHO PLAYED A GAME (20 Nov 2026, Luther: "when a player participates but
  does not score or attain any stat, the app doesn't count the game"). A game
  counted only for players with a STAT LINE, and a line exists only once a
  stat is recorded — a player who played without one had no game, and a game
  with no stats counted for nobody. Now `SessionGame.participants` (player →
  team) = everyone with a line + the FLOOR of the teams that played (each
  team's first `starters`; everyone on a team set up before starters) +
  `subbedIds` (both players of every substitution made after the start —
  LiveTeamPanel.substitute; before the start it is only a lineup change).
  A bench player who never came on is not a participant. `played(game)`: a
  stat, or the game ran (in progress / paused / completed) — set up and never
  started does not count. GameStatsReport (games per player, playing time,
  leaders' per-game), playerGames (profile, card, grade — an empty line for a
  game without a stat), the recap's box score and the Quick Peep's last games
  read participants (`participantLines`). `withoutPlayers` also strips staff
  coaches from teams and subs. Tests: GameStatsReportTests (who played).
- THIRTEENTH sanctioned exception (October 2026, Luther's request): the
  roll-call photo band (AttendanceWatermarkOverlay, exported to Photos for
  WeChat). Same fields, one left edge: the count leads as present/expected
  ("7/10 到场", expected = AttendanceMath.expectedIds — the session's own
  roster, else program enrollment), then WHEN (weekday · date · time), then
  WHO/WHERE ("<coach>教练 · venue"), then the present names under a hairline.
  Text stays Chinese whatever the app language. HOOPWISE_SHOT=rollCallOverlay
  renders it over a stand-in photo.
  REVISED 19 Nov 2026 (Luther): NO TOTAL — the count is who is present alone
  ("7 到场"); WHEN is the moment the PHOTO WAS TAKEN (the attendance photo
  file's date, `PhotoCaptureManager.attendancePhotoTakenDate`; now if it
  cannot be read), not the session's start; ALWAYS CHINESE — the roll-call
  photo left Languages by Area, the coach's name is their Chinese name
  (profile, else their organization row, else the plain name), students by
  `primaryName(chinese: true)`.
- FOURTEENTH sanctioned exception (October 2026, Luther's request): ADDING an
  athlete opens the SAME page as editing one — `EditStudentView()` (create
  mode, a fresh unsaved record; `isNew`) — photo, name, Chinese name, the one
  School Grade menu, Parent/Guardian, Sharing. The old AddStudentView (date of
  birth / grade toggle, category/coach/program, physical stats, contract
  setup) is DELETED; enrolment happens on the program, contracts on the
  profile. A Chinese name alone is enough — the name becomes its pinyin. The
  profile's pencil also opens EditStudentView now. HOOPWISE_SHOT=addStudent;
  pinned by AddStudentUITests (Athletes → + → Add Student → Save).
- FIFTEENTH sanctioned exception (October 2026, Luther's design): the
  NOTIFICATION LOOK. (a) The Live Activity lock-screen card
  (SAMWidgets/SessionLiveActivityWidget.swift) is a deep gradient per moment
  (`ActivityCardStyle`: starting soon navy → blue → cyan bloom; live court
  green → navy → blue), "HOOPWISE · STARTING SOON / SESSION LIVE" in tracked
  caps, ONE huge countdown, "until <program> starts" / "remaining in
  <program>" bold, the class times bottom-right. The Dynamic Island takes the
  moment's accent. (b) Every standard notification is stamped through
  `NotificationCard.stamp` (Models/NotificationCard.swift — iOS, Mac and the
  extension): a KIND (upcoming / started / completed / reminder / nextCycle →
  category `HW_CARD_<KIND>`), a headline (= banner title) and a detail
  (= body). The collapsed banner is iOS's own and cannot be styled; PRESSING it
  shows the HoopwiseNotifications content extension (new target, bundle
  OKTO.SAMp.HoopwiseNotifications, embedded in the app): the kind's gradient,
  HOOPWISE caps, headline big, detail under it. The extension reads ONLY the
  stamped userInfo (falls back to title/body for older requests). New kinds
  need a case in Kind AND the category in HoopwiseNotifications/Info.plist.
  The "Class in 10 minutes" alert is ActivityKit's AlertConfiguration, not a
  UNNotification — only its words changed ("<program> · HH:mm").
  Pending "Session started" requests from before the design are replaced on
  the next 30s sync (their category is stale). Fixed with it: switching
  Session Reminders OFF used to removeAllPendingNotificationRequests — every
  reminder and the next-cycle reminder went with it; it now removes only its
  own "session-<id>" requests. DEBUG HOOPWISE_NOTIFY_DEMO=<kind> fires one
  stamped notification in 5 s; NotificationCardUITests (env-gated, recipe in
  its header) long-presses the banner found by its headline and attaches the
  expanded card, or pulls down Notification Center for the Live Activity.
  Verified on the simulator: four kinds expanded (upcoming, completed,
  reminder, nextCycle) and the starting-soon card; the extension needed
  ENABLE_DEBUG_DYLIB = NO — with Xcode's debug dylib the stub executable
  does not link UserNotificationsUI and the extension dies at launch
  ("Unable to find NSExtensionContextClass").
- SIXTEENTH sanctioned exception (October 2026, Luther's request): the
  session Games tab ends with GAME INSIGHTS — AT MOST THREE worded insights
  from the program's games (GameInsightsView; rules in
  GameStatsReport.insights, pure, both targets). It went card → sheet →
  unfolded record → curated: Luther found the full record "too much
  information", so do not add numbers back. Rules, each with a threshold so
  noise stays silent and a quiet program shows nothing: rostered players who
  have not played (≥ 2 sessions with games; first), else playing time 3×
  uneven (≥ 6 games); under 0.2 assists per basket (the plan engine's
  passing signal — "upcoming plans add passing"); this session's points per
  game a best (≥ 3 sessions); one player's points per game up ≥ 2 and ≥ 50 %
  over the last 3 sessions; the biggest team stat move ≥ 20 % (last 3
  sessions vs before; never the assist rate twice). The Top scorer / Most
  assists / Closest game chips were removed. Counting rules: a game counts
  once past setup with a stat line; sessions that did not happen are left
  out; baskets = points ÷ that game's basket value. Scope is the session's
  PROGRAM. HOOPWISE_SHOT=gameStats. Tests: GameStatsReportTests,
  GameStatsUITests.
- SEVENTEENTH sanctioned exception (October 2026, Luther's request): the
  athlete profile (StudentDetailView — the screen the Athletes list, widgets,
  dashboard and program roster open; StudentIntelligenceProfileView was never
  constructed) has NO measurements and NO league stats; the quick-stats Height
  became Games. Training Stats (Components/StudentLeagueStatsView.swift —
  the league views in it were deleted) is the one stats section and reads
  `GameStatsReport.player` / `playerGames`: played games (not only ones
  someone ended — it used to count `.completed` only, so an unfinished game
  vanished) in sessions that happened (skipped ones used to count), all five
  stats per game with totals, direction by the last 3 SESSIONS vs before (was
  two single games' points), recent games newest first with game number and
  W/L, bilingual. TrainingSessionStats.calculate (grade, radar, monthly card)
  and the profile card's trends read the same list, so no two surfaces
  disagree. HOOPWISE_SHOT=studentProfile / trainingStats.
- EIGHTEENTH sanctioned exception (October 2026, Luther's request): Profile →
  Notifications → "Add Sessions to Calendar" writes sessions into a
  "Hoopwise" calendar in Apple Calendar (Services/CalendarSync.swift, both
  targets; iOS only calls it). One-way, device setting (UserDefaults
  `calendarSync.enabled`), FULL calendar access (write-only cannot find and
  update its own events; NSCalendarsFullAccessUsageDescription). Window 7 days
  back to 60 ahead; sessions that did not happen are removed. IDENTITY IS THE
  EVENT URL hoopwise://session/<id> — no id table, so a reinstall or a second
  device seeing the same iCloud calendar updates the events instead of
  copying them, and copies/foreign events in that calendar are deleted
  (`plan`, pure, CalendarSyncTests). Runs debounced after every cache refresh
  (both refresh paths). The calendar goes in iCloud when the phone has it,
  else on the phone; switching off REMOVES the calendar. DEBUG
  HOOPWISE_CALENDAR_LOCAL=1 syncs into a phone-only "Hoopwise (test)" calendar
  (the simulators are on Luther's iCloud — never test without it), =remove
  deletes it; verified on the simulator: 18 sessions written, visible in
  Calendar, then removed.
- NINETEENTH sanctioned exception (November 2026, Luther: "take it as is"):
  Hub → PLAYS replaced League (FlightyLeagueView is no longer linked from the
  Hub). It is HoopWise Journal's Plays tab ported whole: library by category
  with thumbnails and search, play page (concept hero, when/idea, wrinkles,
  variations, source), step-by-step study with ▶ playback and legend, the
  step editor (move/cut/dribble/pass/screen/defender/ball/erase, undo/redo),
  new play / details / part sheets, delete with an undo toast, and the
  seven starter plays (Resources/StarterPlays.json, seeded once per device in
  the app language, "Add the starter plays again" in the ⋯ menu).
  Shared (both targets): Models/JournalPlays/ — three NEW SwiftData models
  JournalPlay → JournalPlayPart → JournalPlayStep (registered in the schema;
  RULE 7c–e APPLY: not yet in CloudKit Development until a normal Debug run,
  and Production needs the deploy Luther does by hand). Plays SYNC, which the
  Journal did not, so `removeDuplicateStarters` keeps the oldest copy of each
  starterKey (a reinstall seeds before iCloud returns the library).
  iOS views: Views/Plays/ (J-prefixed copies of the Journal's tokens and
  components — JSpacing, JPalette, JCard… — values unchanged). Every Journal
  type that clashed got a Journal prefix (Play, PlayStep, PlayDiagram,
  PlayCategory already exist here for the Mac court editor).
  STRINGS: the Journal localises by String Catalog + system language;
  Hoopwise has an in-app language and NO catalog, and adding zh-Hans to the
  bundle would change Locale.current app-wide. So Plays text goes through
  `jp(_:)` / `JText(_:)` (Models/JournalPlays/JournalPlayLocalization.swift)
  over JournalPlayStrings (generated from the Journal's catalog — regenerate,
  don't hand-edit). Starter play TEXT is written in the language active when
  it was seeded, as in the Journal. DEBUG: HOOPWISE_SHOT=plays (or =hub),
  HOOPWISE_PLAYS_OPEN=play|study|playback|legend|editor|details|newpart|
  newplay, HOOPWISE_PLAYS_PLAY=<starter key>, _PART, _STEP. Tests:
  SAMpTests/JournalPlays (the Journal's play tests, Swift Testing) and
  SAMpUITests/PlaysUITests (real taps: Hub → Plays → play → steps → editor
  → wrinkle; Coach and Organization open).
  TWO TRAPS FOUND ON THE FIRST PORT (it shipped inert):
  · A `.glassEffect` INSIDE a NavigationLink's label swallows every tap on
    iOS 26. All three Hub cards had it — League, Coach and Organization had
    never opened. Put the glass on the link itself.
  · The Journal's value links (`NavigationLink(value:)` +
    `navigationDestination(for:)`) do not resolve on a screen pushed by the
    Hub's `NavigationLink(destination:)`; the Plays screens use destination
    links. Simulator taps from the agent tool are unreliable on these
    cards (a system gesture claims them) — verify with XCUITest.
- TWENTIETH sanctioned exception (November 2026, Luther's request: drills
  where more than one player has a ball, and plays in the training plan).
  (a) SEVERAL BALLS: `JournalPlayDiagram.balls: [Int]` (one entry per ball);
  `ball` is now the first holder, computed. The JSON keeps writing `ball`
  beside `balls`, so an older build reads the first ball and a drawing it
  saved reads back as that one ball. The editor's Ball tool gives or takes a
  ball per player. Playback (`JournalPlayMath.frame`) moves each pass's
  PASSER'S ball (`ballIndex`; with one ball on the floor any pass moves it, as
  before); passes still fly one at a time. A second ball on one player sits on
  the other shoulder. (b) PLAYS IN THE PLAN: the session Plan tab has a PLAYS
  card under Skills (Views/Plays/SessionPlanPlays.swift — picker by category
  with search, tap opens the play, ⋯ moves/removes). Stored in
  `SessionCurriculum.plays` inside the curriculum JSON (no schema change; old
  plans decode with none; Generate Plan keeps them). JournalPlay has NO stored
  id and adding one is a schema change, so `SessionPlayRef` names a play by
  `starter:<key>` else `created:<ms since 1970>` (matched ±1 ms — CloudKit
  keeps dates to the millisecond) and keeps the name for a play since
  deleted. New Plays strings go in JournalPlayStringsAdded (the generated
  table stays untouched). Tests: JournalPlayBallsTests.
  (c) ONE TAP TO PLAY (Luther: the hero's ▶ opened a second screen where ▶
  then played — "redundant"): the play page's hero IS the step player
  (Views/Plays/JournalPlayStepPlayer.swift, shared with the step screen) —
  caption, Step N of M, diagram, ‹ ▶ ›, the step's text; Legend and the
  pencil (draw this step) are in the play page toolbar, ⋯ → Edit steps pushes
  the step screen for add/move/delete. An undrawn play keeps its Draw hero.
  A wrinkle or variation opens already playing. PlaysUITests pins it.
  The player's court FITS THE WINDOW: the page passes its visible height
  (`viewportHeight`, onGeometryChange) and the court's width is capped so its
  height + caption row + ‹ ▶ › + the floating tab bar (250 pt) fit — a wide
  Mac window used to push the half court off the bottom. Pinned by
  PlayEditorWorkspaceUITests.testPlayPageFitsAWideWindow (iPad landscape).
  (d) STRAIGHT OR CURVED LINES (Luther: lines drawn with a mouse or on a
  small screen came out wobbly — every hand shake became a bend, drawn as a
  curve). `Action.shape` (.straight / .curved; nil = drawn before, still
  curved through its points). The editor's Straight | Curved switch (cut,
  dribble, screen; `plays.lineShape`, device-local) shapes the stroke LIVE
  via `JournalPlayMath.shaped`: straight = one segment, a corner only where
  the hand turned > 1 m (≤ 2); curved = ≤ 2 bends, Catmull-Rom. Move tool:
  tap a line to toggle (`toggledShape` — curved gains a mid bend), drag a
  bend dot (`moving(bend:)`, hit `.actionBend`). Playback and touches follow
  the DRAWN path (`drawnPath`). Tests: JournalPlayShapeTests.
  (e) THE EDITOR WORKSPACE (Luther: "like Pixelmator Pro … most plays will be
  edited from here" — the Mac). Regular width only; the iPhone keeps the
  Journal layout. JournalPlayStepEditor = vertical TOOL RAIL (select | cut
  dribble pass screen | defender ball | erase; pointer icon; tooltips with
  keys) · the court as large as the window · INSPECTOR (This step: caption +
  notes; the tool: hint + Straight|Curved; the SELECTION). No shortcut list
  (Luther removed it); hovering a rail tool shows its NAME beside the rail at
  once (onHover overlay — a system tooltip waits and sits under the pointer).
  Move SELECTS (player: has a ball, erase their lines; defender: the one to
  read, delete; line: kind, shape, delete) — on the phone a tap still
  toggles a line's shape. Keys: V C D P S X B E (SwiftUI shortcuts), ⌘Z ⇧⌘Z,
  ⌘↩ Done; ⌫ Esc and arrows (⇧ = 0.5 m) go through JournalEditorKeys, a
  UIKit first-responder catcher: SwiftUI shortcuts NEVER fire for those keys
  on iPadOS/Catalyst (the system keeps them). All keys stand down while a
  text field is focused. Pointer hit radius is the circle (≥ 12 pt), not a
  finger's 22 pt. XCUITest cannot send Esc/⌫/Return on the simulator (only
  their modifiers arrive) — PlayEditorWorkspaceUITests (iPad) covers letters,
  selection, inspector, arrows, ⌘Z; it skips on a phone.
  (f) SHOTS (November 2026): ActionKind `.shot` — a solid RED line
  (JPalette.shot) from the shooter into the NEAREST RIM
  (`JournalCourtKind.baskets`: half (7.5, 1.575); full (26.425, 7.5) then
  (1.575, 7.5)); tool H, between Pass and Screen (phone grid now 5 + 4). A
  DRIBBLE whose end is within `basketReach` (1.4 m) of a rim is drawn red (a
  drive) — computed at render, never stored. `kind.movesPlayer` (cut, dribble,
  screen) / `kind.throwsBall` (pass, shot) replace every old `!= .pass` test.
  Playback: a shot flies like a late pass and its ball RESTS AT THE RIM for
  the rest of the step; next step it is out of play (`transfer` removes it).
  OLDER BUILDS cannot decode "shot": a step containing one reads as an empty
  drawing there (until they update). Tests: JournalPlayShotTests.
  ARROWHEADS (9 Nov 2026, Luther: a dribble's last tooth ran into the
  triangle's corner, and the Dribble icon read as an oblique stroke):
  `JournalPlayDiagramView.arrowFit` — the line is TRIMMED to end at the
  head's base and the head points the way the drawn curve ARRIVES over its
  own length (it used the last two raw points, which a curve does not head
  straight from). The zigzag has at least ~6 teeth on a short line (step =
  min(0.5 m, length ÷ 7)) and returns to the path for one straight tooth into
  the base — so the tool icon is a zigzag too.
  (g) SEVERAL STEPS PER EDITOR (Luther: edit more than one step without
  Done): JournalPlayStepEditor(step:court:) edits the step's whole PART. The
  title is a menu "Step N of M ▾" (all steps + Add a step); the workspace
  inspector starts with a STEPS list (thumbnails of the drafts, ‹ › with
  ⌘[ ⌘], Add a step). Each step keeps a DRAFT (drawing, caption, text, its
  own undo/redo) while you move between them; Done writes every draft in one
  save; Cancel discards them all AND deletes steps added in the editor. An
  added step starts from the current step's DRAFT end. DELETE STEP (trash in
  the Steps row, and the title menu; asks first; never the last step): a step
  added in this editor goes at once, a saved one is hidden and only deleted
  on Done — Cancel brings it back. The Screen icon is
  upright — a T. PlayEditorWorkspaceUITests.testMovingBetweenSteps (iPad).
  (h) PLAYBACK FOLLOWS THE DRAWING + HAND-OFF (12 November 2026, Luther:
  "the logic behind what happens first is inconsistent … the ball travels
  first and reappears on the target before he got there" — Getafe Wave's
  outlet). Playback was phased (passes drawn before their passer's cut,
  then every move, then the other passes); a pass the editor drew to a
  cutter's END flew before the cutter moved and the ball jumped back to
  them. `JournalPlayMath.schedule` is now a TIMELINE in drawing order, each
  action as soon as it can: a move when its player is free (a dribble also
  needs the ball); a pass when the passer is free and holds the ball — to a
  teammate who moved EARLIER in the drawing it is a LEAD PASS landing as
  they arrive; the passer moves on 0.35 beat after letting go; a receiver
  waits for the catch before a move drawn after it. Independent balls fly
  at once. frame / playBeats / ballsAfter read it. ActionKind `.handoff`
  (tool F, after Pass), 0.6 beat, `hasReceiver` like a pass (snaps, follows
  moved players, removed with the receiver). DRIBBLE HAND-OFF (same day,
  Luther, reference image "#"): the one tool does both — drawn to a teammate
  from more than `handoffGap` (1.9 m) + 0.3 away it adds a DRIBBLE along the
  stroke (straight/curved switch applies) ending 1.9 m short of him, then
  the hand-off (`addingHandoff`); closer, a plain hand-off. Drawn as two
  bars struck through by one ("ǂ" turned along the line) next to the receiver (`handoffMark` 0.62 m), with a line from the giver
  when they stand apart. Connector "handoff" {"to"} adds the dribble the
  same way. Older builds cannot decode "handoff" (the step
  reads empty there, as with shots). Tests: JournalPlayMathTests (outlet,
  catch-and-go, hand-off), JournalPlayBallsTests.
  (i) AUTO DEFENSE (12 November 2026, Luther: "assign a defender to an
  offensive player … the defender follows him in a natural way … awareness
  of screens"; decided: calculated with nudging, matched by NEAREST player,
  SWITCH EVERYTHING, a choice of man / 2-3 / 3-2). Models/JournalPlays/
  JournalPlayDefense.swift. Per step, inside the diagram JSON (no schema
  change): `defenseMode` (.man / .zone23 / .zone32, written only when set)
  and per defender `guards` + `nudge` (optionals — older builds keep the
  defenders at `at`, which is always the calculated start spot). Spots are
  WORKED OUT: man = ball–you–man (1.5 m off the ball toward the rim; off
  the ball sagging toward rim and ball line with distance — continuous, so
  closeouts happen); nudge added on top. DEEPER (same day, Luther: "for
  zone the defense only reacts to the ball … make it really good"): ZONE =
  AREAS — five anchors shift with the ball; every attacker within 9.5 m of
  the rim belongs to the nearest anchor's area (cutters are handed on);
  ball in your area → guard it; one attacker → shade him 60 % (between him
  and the rim, leaning to the ball); two → the one nearer the rim, 45 %;
  none → sink toward ball and paint; the ball outside every area → the
  nearest shows (all the way inside the arc, 40 % beyond); someone always
  within 2.5 m of the front of the rim. MAN TEAM RULES (`manTeamSpots`):
  POST — a man within ~3.8 m of the rim is played three-quarters on the
  ball side; HELP — as the ball gets within 5.5 m of the rim the defender
  nearest the driving line whose man is ≥ 4 m away steps in 1.4 m in front
  of the ball. No defender stands within 1 m of an attacker (`clearOf`). SWITCH: a move
  drawn after a screen passing within `screenReach` (1.5 m) of its spot
  uses it — the two defenders swap men as he goes by, carried to later
  steps (`carriedDefense`, in startOfNextStep). Playback: PlayFrame.defense,
  each spot averaged over the last `reactionBeats` (0.35) so defenders
  follow, and a switch slides. THE TIMELINE also gained: a move using a
  teammate's screen (drawn after it, passing it) leaves 0.4 beat before
  the screen is set — before, the user and the screener moved together.
  Editor: "Defense: By hand · Man · 2-3 · 3-2" — ALWAYS in the workspace
  inspector (under This step, with a line saying what the mode does; it hid
  under the Defender tool and Luther took a By-hand play for a broken zone),
  under the Defender tool on the phone; applied to every step of the part from the first (re-matched);
  `.onChange(of: diagram)` re-places after every edit; dragging or arrow-
  nudging a defender sets his nudge. Defenders show the man's number small
  beside the X. Connector: step "defense_mode" (man | 2-3 | 3-2 | off);
  get_play returns it and "guards". DEBUG HOOPWISE_PLAYS_DEFENSE=man|zone23|
  zone32 (with HOOPWISE_PLAYS_OPEN=editor). Tests: JournalPlayDefenseTests.
  REBUILT (20 Nov 2026, Luther: "a thorough and accurate check … man to man,
  2-3, 3-2 … NBA level of understanding … its own expandable place … explore
  rotations, switches — only if reliable"). JournalPlayDefense.swift now:
  MAN = the shell drill — on the ball an arm's length (1.1 m, looser beyond
  8.5 m), "No middle" shading off the middle third; ONE PASS AWAY gap (a
  third to the ball + a step to the rim) or deny (in the lane); TWO PASSES
  AWAY on the SPLIT LINE between ball depth and his man's (low man in front
  of the rim) — blended by `helpSideness`, never a jump; the POST 3/4 high
  with the ball above the FT line extended, fronted below it (ball side
  only); HELP from penetration (inside the FT line, full at 2.8 m), never
  off the strong-side corner, with a ROTATION (the free defender nearest the
  helper's man splits the two). SCREENS (`DefenseScheme.screens`): switch /
  drop / hedge / trap / chase on BALL screens (user = the holder), off-ball
  screens switch only under Switch (else chased); hedge and trap make the
  low man TAG the roller and the next man split. `screenUses` +
  `activeScreens` time the coverage (builds as the screen is set, fades a
  beat after use); `switches` only under Switch. ZONES = SLIDE CHARTS (top,
  deep, high post, wing, corner, low post, mirrored; 2-3 GL GR FL FR C, 3-2
  P WL WR BL BR) blended by Gaussian weight of the ball's distance (σ 1.3,
  relative — never all zero), the on-ball duty shared the same way, off-ball
  shading of the attacker in the area (≤ 4 m, 40 %), the rim always covered.
  `DefenseScheme` (onBall, offBall, screens, helpRotate) rides in each
  step's JSON as `defenseScheme`, only when not standard; `applyingScheme`
  changes it on every step keeping guards and nudges. UI: the board (and
  drill drawings) have a DEFENSE DOCK between Step and the play bar
  (`plays.editor.defenseDock`, "Man · Drop" / "2-3"), opening upward into
  the controls (mode, then for man: On the ball, One pass away, Ball
  screens, Help and rotate, and a line saying what the coverage does); it
  left the steps popover. The play editor's inspector and the phone's
  Defender tool show the same controls. The connector still sets only
  defense_mode. Tests: JournalPlayDefensePrinciplesTests (each principle,
  coverages, slide charts, smooth swing), BoardDefenseUITests.
  INBOUNDS AND THE FORMAT (22 Nov 2026, Luther, markup on a 3v3 BLOB: "the
  defense engine must understand when defending 1v1 to 5v5, out of bound or
  live — maybe this can be selected"). The live rules assumed the ball in
  FRONT of the rim: with the inbounder behind the baseline the ball's depth
  went negative, the help-side spot collapsed onto the rim (X1 under the
  basket), the post rule fronted toward the baseline, and a ball 2 m from
  the rim read as PENETRATION, pulling a helper. Now `DefenseScheme`
  .situation Auto (inbound when the BALL is beyond a line by 0.15 m —
  `outOfBounds`; half: y < 0 baseline, x < 0 / > 15 side; full: x > 28 the
  attacked baseline, else side) · Live (never) · Inbound (always — the
  holder's `nearestLine`), and .inbounder Pressure the pass (0.8 m inside
  the line opposite the passer, shaded toward the rim) · Protect the rim
  (free safety in front of the rim; at the ball-side elbow on a sideline) —
  both in the step JSON, tolerant, default Auto / Pressure. BASELINE:
  `baselineInboundSpot` — basket-side and ball-side of his man (Deny: in
  the lane of the direct pass in), perimeter men (> 5.8 m from the rim)
  sag into the paint; SIDELINE: the live rules with the men within 7.6 m
  of the ball denied; NO DRIVE HELP while the ball is out (`manTeamSpots`
  inbound). Once the ball is in, the live rules take over by themselves
  (detection follows the ball, also mid-pass). FORMAT: `format` "3v3"
  (attackers v defenders); zones need five attackers (`zonesFit`) — with
  fewer the picker has no 2-3 / 3-2 and says "Zones need five attackers"
  (kept while a zone is on, to turn it off). Dock: "3v3 · Man · Switch",
  falling back to "Man · Switch" when the bar is narrow (ViewThatFits — the
  mini wrapped it on three lines), an inbound shows as the arrow-to-line
  icon (and "Inbound" in the accessibility label); Situation and
  Inbounder's defender rows + a line saying what the coverage does. DEBUG
  HOOPWISE_BOARD_DEMO=blob|blobRim|slob opens the board on a 3v3 inbound
  (with HOOPWISE_SHOT=coachBoard). Tests: JournalPlayInboundDefenseTests,
  BoardDefenseUITests.testAnInboundIsReadAndZonesNeedFive.
- TWENTY-FIRST sanctioned exception (8 November 2026, Luther's request):
  on a PRIVATE session (SessionPrivacy), the session page's Add Athlete adds
  to THAT SESSION ONLY — `addStudentsToSessionOnly` (roster = who was
  expected + them, then present through setStudentAttendanceStates, so each
  is charged from their OWN private bundle). It used to enrol them in the
  program (the group-class behaviour, unchanged for group sessions), which
  put 大波 on Starbucks dude's private program: expected, and inferred
  absent, at every later lesson there. Private wording: "Add someone to this
  session only" / banner "This Session Only"; the picker offers anyone not
  already expected. PrivateAddToSessionTests (charge, roster, program
  untouched, later lessons). HOOPWISE_SHOT=privateSession; its UI test skips
  when the demo store has no private program (the iPhone one has none).
  SAME DAY, the session page's ROSTER ROWS: `enrolledStudents` (rows, the
  Expected stat, games, plan, All Present) read the PROGRAM's enrolment, not
  `AttendanceMath.expectedIds` — after 大波 left Starbucks dude's program, that
  session (roster: both, both present) counted 2 and listed 1. It is now
  expectedIds ∪ everyone marked, so a marked athlete never vanishes.
  (AttendanceSwipeUITests.testQuickPeepFromSessionOffersEdit fails on the
  previous commit too — pre-existing, not from this; the iPhone 17 Pro sim's
  demo store has no program sessions, so run attendance UI tests on the
  Pro Max sim.)
- TWENTY-THIRD sanctioned exception (9 November 2026, Luther's request,
  iPhone + iPad + Mac): the drills page (DrillsLibraryView). (a) No gaps:
  age chips, the block segments and the type chips are ONE compact filter
  row block (`filterSection`) with `.listSectionSpacing(.compact)` — they
  were three List sections with a section gap between each. (b) SEARCH IS
  THE WHOLE LIBRARY ("Search all drills"): while text is typed the filters
  step aside and results come from every age and block, every typed word
  anywhere in name / Chinese name / how it runs / instructions
  (`DrillFinder.typedMatch`), grouped Personal, then by age (rows say block ·
  type), then rule options. Browsing lists no longer filter by the search.
  The Mac's Return → Claude section still sits above. DEBUG
  HOOPWISE_LIBRARY_SEARCH=<text> opens with a search typed. Pinned by
  ActivityLibraryUITests.testSearchCoversTheWholeLibrary.
- APPLE PENCIL IN THE PLAY EDITOR (15 November 2026, Luther: "add pencil
  support for iPad, focus here is how to take advantage of it in the play
  editor"). The court's input is no longer a SwiftUI DragGesture (it cannot
  tell a Pencil from a finger): Views/Plays/CourtInputLayer.swift, a UIKit
  view that tracks ONE touch and says whether it is the Pencil (precise
  location). The editor's begin/update/finish rules are unchanged
  (`handle(_:size:)`, `cancelDrag`). What the Pencil adds:
  · PENCIL DRAWS, FINGER MOVES: once a Pencil touches the court, the Pencil
    uses the tool and a finger is Move (pick up, drag, select) whatever the
    tool — no switching to Move between strokes (`gestureTool`; AppStorage
    `plays.pencilDraws`, on; an "Apple Pencil" inspector section appears
    once one is seen). A Pencil landing while a finger is down takes over;
    fingers while the Pencil draws are ignored (a resting hand).
  · HOVER (Pencil hover on supported iPads, and the Mac pointer): a ring on
    what the stroke would use — the player a line starts from (dashed), or
    what Move / Erase / Ball / Defender would hit.
  · DOUBLE-TAP / SQUEEZE (UIPencilInteraction, not on Catalyst) follow the
    system Pencil setting: switch to Erase and back, the previous tool, or a
    tool palette (glass capsule of the tools) at the tip.
  · Two-finger tap = undo, three-finger tap = redo (a second finger cancels
    the first finger's gesture first, so a tap tool adds nothing).
  Mouse / trackpad on the Mac arrive as ordinary touches — unchanged.
  MARK-UP ON THE PLAY PAGE (16 Nov 2026, Luther: "using the Apple Pencil
  here should annotate"): JournalPlayStepPlayer (play page, step screen,
  drill drawings) lays Views/Plays/PlayInkLayer.swift over each step — a
  PencilKit canvas, `.pencilOnly`, red pen, Pencil double-tap / squeeze =
  eraser. A telestrator: ink belongs to its step while the page is open,
  NEVER saved; "Clear ink" appears on the court once a step has ink. The
  scroll views around it pan with fingers only (`PlayInkCanvas`), so the
  Pencil draws instead of paging and a finger still swipes steps
  (PlaysUITests.testFingerSwipeStillPagesUnderTheInkLayer).
  SCRIBBLE (16 Nov 2026, Luther: "the iPad would interpret what has been
  drawn … and have the player involved move or pass"; decided: move after
  the Pencil rests 2 s, SWAP the ink for the clean line, dribbles too).
  iPad only (not the Mac): a "Scribble" switch at the court's top left. The
  court shows the step's formation (its own lines hidden); 2 s after the
  last stroke the new strokes go through Models/JournalPlays/
  JournalPlayScribble.swift (pure, court metres, drawing order): a line
  must START ON A PLAYER (`lineStart`, 1.4 m) or it stays red ink; ≥ 3
  short collinear strokes = dashes = PASS to the teammate nearest the end;
  a zigzag (≥ 4 swings over 0.12 m around its running average) = DRIBBLE
  along the middle; a short stroke ACROSS the end = SCREEN; a V (separate
  strokes, or the line doubling back at its tip — trimmed) or nothing =
  CUT. Actions are built with the editor's `adding` (curved), so they play
  exactly like drawn ones. Each reading is a BATCH starting where the last
  left everyone (`startOfNextStep`); the read strokes leave the ink, the
  clean lines show 0.6 s, then the players move. ▶ replays every batch;
  "Reset ink" clears ink and batches. Never saved. DEBUG
  HOOPWISE_PLAYS_SCRIBBLE=1 | ink | demo (draws a cut + a dashed pass as
  Pencil strokes; demo reads them) with HOOPWISE_SHOT=plays
  HOOPWISE_PLAYS_OPEN=play. Tests: JournalPlayScribbleTests. Real Pencil
  handwriting needs the iPad — thresholds may want tuning.
  Verified on the iPad Air 13 simulator: a finger-drawn cut, two-finger
  undo; PlayEditorWorkspaceUITests, PlaysUITests, PlayDefenseUITests pass.
  Pencil touches, hover, double-tap and squeeze cannot be simulated — they
  need a real iPad.
- DRILLS PAGE FILTERS REDONE (16 November 2026, Luther: "I still need to
  know which are ball handling, passing or shooting … then optionally if I
  need to go by age group"; age must be removable; "a way to order drills by
  different criteria"; all platforms). DrillsLibraryView: SKILL CHIPS first
  (All skills + the octagon's eight DrillAttributes; a skill keeps drills
  scoring ≥ 2 — worked/main — with ●●○ dots on each row); then a row of
  removable FILTER PILLS (menu + ✕): Age (`library.ageFilter`, "" = any —
  the old required `library.age` is no longer read), Block, Type (types left
  by the other filters, with counts; Rule options), Source (All / Library /
  Personal — "Personal" is no longer an age chip; personal drills have no age
  or block so those filters drop them), and SORT (`DrillSort`: Suggested =
  library order or, with a skill, strongest first · Name · Age (sections per
  age when no age is set) · Duration); "Clear all". The page opens on every
  drill. The plan picker keeps its own keys (`planPicker.age/.skill/.sort`),
  starts on the program's age and the section's block (both removable), and
  "Find drills" for a neglected axis now just selects that skill (any block)
  — strongOnSection is gone. TRAP for UI tests: a `-key value` launch
  argument PINS that default (the argument domain wins over the app's
  writes) — testSkillFilterWithOptionalAge relaunches without them. Tests:
  ActivityLibraryUITests.
- DRILL VISUALS ARE DRAWN IN THE PLAYS EDITOR (9 November 2026, Luther's
  request: "the same editor that's in plays … remove the popup"). The drill
  page's "Add a visual" (and the carousel's + tile) opens
  JournalPlayStepEditor(drawing:onSave:) directly; the Add Visual menu
  (photo / camera / video / YouTube / Instagram / PencilKit sketch —
  DrillMediaPicker.swift) is DELETED. Existing photos, videos and links still
  show and open in the viewer; a legacy PencilKit diagram still edits in
  CourtDiagramEditor. The editor now keeps its steps as VALUES (pages) and
  writes the store only on Done — for a play it inserts/deletes/reorders the
  part's JournalPlayStep records there (Cancel has nothing to undo). DRILL
  MODE adds a Player tool (key O; any number of players, numbered past the
  highest; Erase / ⌫ removes one with its lines, passes to them and ball —
  `JournalPlayMath.removing(player:)`) and a Cone tool (key K;
  `JournalPlayDiagram.cones`, written only when non-empty so plays' JSON is
  unchanged; hit/move/erase/nudge like a defender). Plays keep their five and
  get neither tool. Storage (no schema change): a `.courtDiagram` DrillMedia
  whose strokesPath holds `DrillDrawing` JSON (Models/DrillDrawing.swift;
  `<id>.drawing.json`) beside a JPEG of step 1 (DrillDrawingMedia) that the
  carousel, viewer and bundles show; told from a .pkdrawing by CONTENT, since
  a bundle import names every strokes file .pkdrawing. DRAWINGS SYNC (9 Nov
  2026, Luther: "visible on all devices"): drill media FILES never reach
  CloudKit, so the drawing also rides in its synced SDDrillMedia row —
  `DrillDrawing.syncPayload` ("hoopwise-drawing:" + base64 JSON, ≤ 400 KB) in
  the `remoteURL` column a court diagram never used (no schema change).
  `DrillDrawingMedia.drawing(for:)` reads the payload first;
  `syncDrillDrawings` (both refresh paths) stamps the payload on drawings
  made before (on the device holding the file) and, on a receiving device,
  writes the drawing + JPEG + thumbnail to the row's paths
  (`restoreFiles`, also when an edit elsewhere made the file stale).
  `deduplicateDrills` now MOVES the visuals of a deleted duplicate to the
  survivor — library drills are seeded on every device, and a drawing on the
  losing copy used to go with it. Photos and videos still do not sync.
  Tests: DrillDrawingSyncTests. DRAWINGS PLAY WHERE THEY ARE READ (Luther: a
  three-step drawing showed only step 1): JournalPlayStepPlayer takes value
  steps too (`init(drawing:)`), the drill page shows each drawing as that
  player (DrillDrawingCard: caption, Step N of M, ‹ ▶ ›, Edit, ⋯ Delete) with
  photos/videos left in the carousel, the full-screen viewer (session plan
  taps open it) plays a drawing instead of its JPEG, and a multi-step
  drawing's thumbnail says "3 steps". Refined the same day (Luther: two Edit
  buttons, and the viewer blacked out the window): the drill page header
  has "+ Add" and, with two or more visuals, "Reorder" — the drawing's own
  Edit is the only Edit; the session plan opens a drawing in a popup
  (DrillDrawingSheet: drill name, player, Done) and the full-screen viewer
  pages photos/videos only (`DrillDrawingMedia.viewerMedia`); drawing
  thumbnails are drawn LIVE from the drawing so they follow dark mode.
  BIGGER CONTROLS (16 Nov 2026, Luther: "these buttons are way too small and
  not easy to find"): + Add, Reorder and each drawing's Edit are glass
  capsules, body text, ≥ 44 pt (`visualControlLabel()`, DrillDrawingMedia.
  swift); the drawing's ⋯ is a 44 pt glass circle.
  HOOPWISE_SHOT=drillDrawing / drillDetail. Tests:
  DrillDrawingTests, DrillVisualUITests (demo store, cleans up after itself).
- DRAW WHILE CREATING + PHONE STEPS BAR (9 November 2026, Luther's
  request). (a) New Drill (AddDrillView) ends with a VISUAL section: "Draw
  on the court" opens the same editor (JournalPlayStepEditor(drawing:));
  the drawing plays in the form with Edit / Remove and is saved on Create as
  the drill's first visual (DrillDrawingMedia.save with the new drill's id).
  (b) The editor's title menu never showed on the iPhone (no room beside
  Cancel / undo / redo / Done), so steps could not be added, moved or
  deleted there. Compact width now has a STEPS BAR under the caption:
  ‹ "Step N of M ▾" › and "+ Add a step"; the menu lists every step, Add,
  MOVE EARLIER / LATER (new — `moveStep`, also in the workspace's Steps row)
  and Delete. The principal title menu is workspace-only, and the phone's
  title is empty (the bar says which step). On the iPhone a coach's own drill
  has no Delete (only quick-note drills do) — UI tests clean up through DEBUG
  HOOPWISE_DELETE_DRILLS_NAMED=<name> (demo store only). Pinned by
  DrillVisualUITests.testNewDrillCanBeDrawnWithStepsOrganisedOnThePhone.
- EDITOR INSPECTOR FOLLOWS THE WINDOW (9 November 2026, Luther: on the iPad
  mini and the Mac "Add a step" wrapped letter by letter, and the right
  column ate the court). The workspace measures itself: TALLER THAN WIDE
  (iPad mini upright, a narrow Mac window) puts the inspector UNDER the court
  (`bottomInspector`, ≤ 300 pt / 36 %): Steps as a row of small drawings with
  ‹ › ⇅ 🗑 + "Add a step" on one line, then This step | the tool and the
  selection side by side; wider keeps the 290 pt column. The layout does not
  switch while a text field is focused (`inspectorBelow`) — the on-screen
  keyboard makes an upright window wider than tall and the switch took the
  caption field and its focus away. Step controls are icon buttons, Add a
  step its own prominent button. Pinned by
  PlayEditorWorkspaceUITests.testInspectorFollowsTheWindowShape (iPad mini).
- DRILL PAGE HERO (14 November 2026, Luther: the header "is awkward … make
  the page more fitting to the app and designed with purpose"). The drill
  page's header is the session page's language: a rounded card in the
  drill's BLOCK colour (routine teal-blue, small games violet, compete
  orange-red, game green; a personal drill its category colour) over
  CardCourtBackground with the block's court (routine = test spots, small
  games = tactics board, compete = half court, game = full court), then
  "U10 · ROUTINE" (or "PERSONAL DRILL") caps, the name, the Chinese name,
  and glass pills: type, minutes, players (+ difficulty and visibility for
  a personal drill). A library drill's legacy category and difficulty are
  guesses and are NOT shown (the old banner said "Shooting · Intermediate"
  on a U10 lay-up routine). The rows under it that repeated age/block/
  type/minutes/players are gone; Source stays; a quick note keeps its
  completion count. NOTE: a gallery shot of the drill page in light
  appearance looks half dark — AppTheme follows the in-app theme, applied
  by MainTabView's preferredColorScheme, which a gallery shot bypasses.
- SEVERAL DRAWINGS ON ONE DRILL (9 November 2026, Luther: two drawings sat
  one under the other). DrillDrawingsView (DrillDrawingMedia.swift) lays a
  drill's drawings out SIDE BY SIDE (two columns) when the drawings area is
  ≥ 900 pt wide (a Mac window, iPad landscape), else ONE AT A TIME under a
  TOGGLE of their names (segmented ≤ 4, a menu beyond), the card's own title
  hidden there. A drawing's NAME is its media caption ("Corner shot",
  "Option: 1v2" — options/wrinkles of the drill), else "Drawing N"; ⋯ →
  Rename sets it (updateDrillMedia; captions sync). HOOPWISE_SHOT=
  drillDrawings (+ HOOPWISE_DRAWINGS_WIDE=1 lays it out 1000 pt wide).
- ORGANIZATION PAGE REDESIGNED (9 November 2026, Luther: "the weakest page
  of the app … it feels like it's not from the app", all platforms).
  OrganizationView was two cards of numbers, a segmented control (Coaches /
  Locations / Schools / Categories) and a card per row. Now: title
  "Organization" (it said "Coaching Staff"), a strip of four tiles (coaches,
  venues, schools, age categories — a tap scrolls to the section), then ONE
  inset-grouped List: Coaches (you first, head coaches next; avatar, Chinese
  name first in Chinese, role · programs), Venues, Schools, Age categories,
  each with its Add row, then Share & import (two rows; what leaves the
  device in the subtitle, private athletes in the footer). One `.searchable`
  filters every section. Wide windows read as a centred ≤ 860 pt column
  (contentMargins; ≥ 20 pt on the phone). Rows are Views/Hub/
  OrganizationRows.swift; the editors/profiles are unchanged. The old
  CoachesListSection / LocationsListSection / SchoolsListSection /
  CategoriesListSection and their row cards are deleted. HOOPWISE_SHOT=
  organization. Pinned by OrganizationUITests.
- TODAY'S ATHLETES AS THE WIDGET'S CLUSTER (10 November 2026, Luther's
  request, all platforms): the Home card's right side was the hero's photo
  alone; it is now `TodaysRosterCluster` (Views/Dashboard/) — the Next Up
  widget's RosterClusterView brought into the app: the same 8 slots, three
  sizes and id-seeded jitter (never reshuffles), scaled ×1.3 compact / ×1.6
  regular. Hero = the big accent-ringed bubble, steady attenders
  (AttentionRules.steadyPercent over ≥ attendanceMinSessions) the small
  ones, everyone else between; each bubble opens that athlete, "+N" the
  list. The left side (name — now shrinks before truncating — reason chip,
  grade, focus) still opens the hero. The "See all N players" bar lost its
  duplicate mini photos. Pinned by TodaysAthletesUITests.
- COACHES ON A SCRIMMAGE / GAME PREP (10 November 2026, Luther: "add
  coaches from organization to a scrimmage session or game prep … they'd
  appear as coaches alongside other students"). `SessionType.
  takesCoachesAsPlayers` (scrimmage, gamePrep). `SessionCurriculum.coachIds`
  (inside the curriculum JSON — no schema change; older plans decode with
  none). The session page's Add Athlete sheet lists active organization
  coaches FIRST under "Coaches" with a Coach tag (AthletePickerSheet
  `coaches:`) — only on those two types; a program-less scrimmage shows the
  button for coaches alone. Added coaches are rows under the athlete roster
  (photo, names, Coach tag, ⋯ Remove from session) with NO attendance mark:
  never charged, never expected, never inferred absent. Games: they join
  the team pool (`SessionGamesTabView.guestPlayers`, as display-only
  `StaffCoach.asGuestPlayer` Student values — never saved) and are scored
  like anyone, but every staff coach's lines are stripped from the Games
  tab's report and insights (`GameStatsReport.withoutPlayers` /
  `make(excluding:)`); athlete profiles read only their own lines anyway.
  HOOPWISE_SHOT=scrimmageSession (+ HOOPWISE_SCRIMMAGE_RESET=1 puts the
  demo session back). Tests: SessionCoachesTests, SessionCoachesUITests.
- COACH PROFILE + FORM REDESIGNED (10 November 2026, Luther: "very messy …
  make it look better and intentional … game stats, last attended practice,
  position when playing 5v5, tendencies"). Views/Hub/CoachProfileViews.swift
  replaces the old CoachProfileDetailView / AddEditCoachView (deleted from
  OrganizationView.swift; ReassignProgramSheet stays there). PROFILE: header
  (photo, names Chinese-first in Chinese, role / position / You / Inactive
  tags), four tiles when they have games (Games, PTS · REB · AST per game),
  On the floor (position, tendency chips, last played, W–L), Recent games
  (5), Coaching (programs, age groups, specialties), Contact (tap to call /
  mail), Notes. A coach's games = scrimmage / game prep sessions they played
  in (`DataManager.sessionsPlayed(byCoach:)` → GameStatsReport.player).
  FORM: a native Form editing a DRAFT of the stored coach (photo via
  PhotosPicker, names, contact, role / access / active with the access
  description as footer, On the floor: position segmented — PG SG SF PF C —
  and tendency chips, Coaching: age-group chips + specialties, programs with
  Reassign, notes, Delete). FIXED: the old form rebuilt the record and
  ERASED the coach's photo on every save, and `updateStaffCoach` never wrote
  accessLevel. PLAYER DATA (Models/CoachPlayerProfile.swift, no schema
  change): `playerPosition` / `playerTendencies` are tagged entries
  ("player.position:pg", "player.tendency:shooter") in the synced
  `specializations`; `coachingSpecializations` is the list without them —
  what every screen shows, and what the profile→staff sync writes (it used to
  overwrite the whole list). Tendencies: shooter, high IQ, rebounder,
  all-around, defender, playmaker, slasher. TRAP: a `Label` inside a Form row
  rendered icon-only as a tall pill in a FlowLayout — chips use an explicit
  HStack. HOOPWISE_SHOT=coachProfile / coachEdit. Tests:
  CoachPlayerProfileTests, CoachProfileUITests.
- HUB → TEAMS (10 November 2026, Luther: "teams I coach … the athletes in
  it and their profiles … the plays we practice and run — base offense,
  BLOB, SLOB, transition, against zone, defense philosophy and schemes").
  A team is the EXISTING SDTeam record (the retired League's: name, short
  name, colour, coach, home venue, `playerIds`) — the roster holds athlete
  AND organization-coach ids (TeamRoster resolves both). SCHEMA CHANGE,
  APPROVED by Luther the same day: SDTeam gained `playbookData: Data?`
  (optional, additive) — Team.playbook ⇄ TeamPlaybook JSON (Models/
  TeamPlaybook.swift): sections base offense, transition, against zone,
  BLOB, SLOB, press break, defense, other — each plays (SessionPlayRef, as
  session plans) + notes; an emptied section is not stored. It RIDES THE
  PENDING Dev→Production deploy (rule 7d/7e) — debug builds write it to
  Development today. Views/Hub/TeamsViews.swift: TeamsScreen (list, + New
  Team, empty state), TeamDetailView (badge header; Roster — tap an athlete
  → StudentDetailView, a coach → CoachProfileDetailView, swipe to remove,
  Add Players = AthletePickerSheet with coaches; one section per playbook
  kind — plays with thumbnails open JournalPlayScreen, swipe/move, Add plays
  = SessionPlayPicker, notes saved 0.7 s after typing and on leaving),
  TeamEditorSheet (name, short name, colour swatches, home venue, head
  coach). Delete Team goes through deleteTeam (also removes that team's old
  League games). Hub card "Teams" between Plays and Coach | Organization.
  HOOPWISE_SHOT=teams. Tests: TeamPlaybookTests, TeamsUITests.
  STANDARDS + TEAM PRACTICE (10 November 2026, Luther: "break down the
  standards … what skill each player needs per position or action … assign
  skill workouts … the Team view should be blocks, meant to be
  contemplated"; then: "never billed but a record of their attendance …
  numbered roles, show on profile, one team set"). The team page
  (Views/Hub/TeamScreens.swift; TeamsViews.swift keeps TeamBadge +
  TeamEditorSheet) is BLOCKS: a colour hero with the roster cluster, FOCUS NOW
  (see below), Playbook tiles (filled sections + "Add a section"),
  Standards, Roster, Practices; two columns in regular width. ROSTER IS ONE
  BLOCK (11 Nov 2026, Luther: Workouts and Roster were redundant): each row
  = photo, name, Coach tag, the roles they play, drill count; the row opens
  the player's workout, ⋯ = View profile / Remove from team. A
  section's play opens PlayBreakdownView: the play's step player, then
  NUMBERED ROLES ("Break it down" takes the numbers of the play's step-1
  offense, else 1–5). A role (RoleEditorSheet) = a standard line, skills
  (the library's ActivityTypes minus warm-up/games/rules), drills
  (SkillDrillPicker: library drills tagged `type:<skill>` + personal),
  and who plays it (team roster). All in TeamPlaybook.breakdowns (keyed by
  SessionPlayRef.key) inside playbookData — no further schema change.
  `workout(for:)` = a player's drills over every role they play (a drill
  shared by two roles once, with both sources); `skillDemands` = skills by
  how many roles need them. SessionType gained `.teamPractice` (enum case
  in the stored raw string, no schema change): Add Session → Team Practice
  → "Which team?" (replaces the program step) creates through
  SessionCreation with group .unassigned (no program, no auto program),
  roster = the team's athletes, curriculum.teamId + coachIds = the team's
  coaches, title "<team> Practice", one series when recurring. NEVER
  BILLED: redeemPrivateAttendance skips `.teamPractice` and SessionPrivacy
  says not private. The session page OPENS ON PLAN for a team practice, with
  SessionTeamFocusCard on top (identity, objectives, workout-drill count,
  "Team" opens the team). The attendance RECORD (`teamPractices(of:)`):
  athlete profile → TeamPracticeRecordRow inside the Contracts card +
  TeamWorkoutProfileSection under it; coach profile → a Teams section.
  FOCUS → PLAN (11 Nov 2026, Luther: the identity/objectives block was
  "useless"; "a relationship between the team's composition and settings in
  the hub and the plan appearing in session"). `TeamPlaybook.focus` = the
  play keys practice works on now (in playbookData; identity/objectives stay
  in the JSON, no longer shown). Team page FOCUS NOW block: the focus plays
  (roles · drills, or "Not broken down yet"; tap → breakdown) + the skills
  they need; TeamFocusSheet picks them from the playbook. A team practice's
  Plan top is SessionTeamPlanCard (replaces the age · level · phase Generate
  Plan there): WORKING ON (focus plays, skills), "Build the plan from the
  team" (`practicePlan`: Skills = the focus plays' role drills once each in
  play order; Warm-up = ≤ 2 routine library drills of the needed skills,
  oldest age first; the plays added, existing ones kept; minutes 15 + half
  the rest; Rebuild asks first) and WHO DOES WHAT (each expected person's
  roles in the focus plays with the standard; "No role in these plays").
  COMPACT (13 Nov 2026, Luther: "how can this be compressed?"): one header
  row — badge, team name, "Working on: <plays>" as its subtitle, a small
  Build plan / Rebuild button (the wand alone on a phone) and Team; skills
  on one line; each person ONE line (role number, 24 pt photo, name, the
  standard), two columns in regular width with more than two people.
  Tests: TeamPlaybookTests (workout, demands, round trip, never billed,
  focus → plan),
  TeamsUITests (section → breakdown → role → workout on the team page).
- HOME: TEAM + PLAY CARDS (11 November 2026, Luther: "a Teams card — the
  team pinned on the home screen, bubbles of players and a couple of useful
  team stats … a card for a play I am working on or just finished; each card
  its own design, same language"). Views/Dashboard/HomeTeamPlayCards.swift.
  TEAM (right column on iPad, after Today's athletes): one per PINNED team —
  team page ⋯ → Pin to Home / Unpin (`HomePins`, device-local UserDefaults
  `home.pinnedTeams`). Glass card with a team-colour wash: badge, name,
  players, the roster cluster (≤ 34 % of the card), next practice and focus
  laid out like Today's athletes' performance / focus area (value over
  caption, no boxes — Luther removed the tiles and attendance) — and one
  nudge line (no focus
  plays yet, or who has no role in them). Tap → the team. PLAY (left
  column, after the briefing): `PlayActivity` (Models/JournalPlays/
  PlayActivity.swift, device-local — JournalPlay has no edit date and adding
  one is a schema change) remembers the last play EDITED (step editor Done)
  and OPENED (play page); Home shows one edited in 7 days ("WORKING ON"),
  else opened in 3 ("LAST STUDIED"). The court across the top, then name,
  category, steps · wrinkles · variations, "In N upcoming plans · <team>
  runs it". Tap → the play. TRAP: an @AppStorage on Home redrew it FOREVER
  (Home writes UserDefaults while it draws — attention state) and so did a
  @Query (Home's work saves the store): both are notifications
  (.hoopwiseHomePins / .hoopwisePlayActivity) and an on-demand fetch.
  HOOPWISE_SHOT=homeCards (pins the demo team, marks its play edited).
  Tests: HomeTeamPlayUITests.
  A PINNED STEP (19 Nov 2026, Luther: step 1 "almost never says anything
  useful"): the play page's ⋯ → "Show this step on Home" pins the step on
  screen (`PlayActivity.pin`, device-local `home.play.pinned`, ONE pin); the
  pinned play wins over recent activity until "Remove from Home"; the card
  draws that step, captioned "PINNED · STEP N OF M"; the play page opens on
  it. HOOPWISE_HOME_PIN_STEP=<n> with homeCards. Tests: HomePinnedStepUITests.
  THE BRIEFING (same day, Luther): opens by default in regular width (iPad,
  Mac; a tap still folds it), shut on the iPhone; its "Handled
  automatically" list is GONE (auto-close still runs; reopen from the
  session's ⋯ → Mark Scheduled; `AttentionEngine.ledger` stays for the
  DEBUG report).
- SESSION HEADER CLEARS THE BACK BUTTON (12 November 2026, Luther: the
  Scheduled tag sat under Back on the iPhone and was tight on the Mac). The
  status is now the FIRST pill of the meta row (status · format · date ·
  time, a FlowLayout that wraps instead of running off a phone), and the
  hero's content starts below the floating Back / ⋯ (safe area + 82) with the
  card growing to fit (minHeight 200 + safe area) instead of a fixed height
  that pushed the content up under the buttons.
  PUSHED PAGE (same day, Luther: the blue was cut by a grey bar beside the
  Dynamic Island, Back / ⋯ in the status bar): the page's GeometryReader sits
  inside ignoresSafeArea and read a top inset of 0, and iOS 26's scroll-edge
  bar drew over the hero. The real inset is read outside (`windowSafeTop`;
  0 in a sheet), the buttons sit at inset + 4 (30 in a sheet) and
  `.scrollEdgeEffectHidden(true, for: .top)` lets the blue run to the top.
- HEADER COURTS PER SESSION TYPE (12 November 2026, Luther: the header court
  was "inaccurate … the lines are messy" — lane, circle and arc were each
  scaled to the card's width or height, so it stretched). Views/Components/
  CourtArtwork.swift draws a FIBA court in METRES (lane 4.9 × 5.8, arc 6.75
  with 0.9 m corners, no-charge 1.25, circles 1.8, rim 1.575 from the
  baseline) through one projection, hairlines fading toward the text side.
  `CourtArtStyle(sessionType)`: training = half court from above; scrimmage
  = full court; game prep = tactics board (basket at the top, a set drawn:
  O's, pass, cut, X's); recovery = centre circle with calm rings;
  assessment = half court with shooting-test spots and lane marks; team
  practice = a true pinhole camera over the top of the key (broadcast).
  CardCourtBackground(color:style:) — athlete headers keep .halfCourt.
  HOOPWISE_SHOT=courtArt shows all six.
- GAME CHEMISTRY + WIDE SESSION PAGE (14 November 2026, Luther: "when a
  player gets most of their shots from assists or generates their own …
  who one player assists the most or receives from the most … the game page
  beside the record of games should have a ready dashboard"; "on mac and ipad
  … a double row list with larger player name and pictures"; "increase the
  height of the navigation bar in sessions (mac only)").
  (a) BASKET LOG: `SessionGame.baskets: [GameBasket]` (scorer, assister?,
  points, team, time) inside the games JSON — no schema change, older games
  decode with none. The live entry (`GameStatAction.apply`) appends one per
  basket and Undo removes exactly it (`basketId`). Stat lines still hold
  only counts, so CHEMISTRY ONLY KNOWS GAMES SCORED SINCE THIS BUILD. The
  old per-player +1/+2/+3 screen in FlightySessionPageView writes no log
  (no longer reached on any layout).
  (b) Services/GameChemistry.swift (pure): `summary` (creation per player —
  off a pass vs self-created —, passer→scorer duos, playmakers with their
  favourite target), `player` + `readings` behind thresholds (≥ 5 baskets
  and ≥ 70 % for finisher / creates own shot; ≥ 3 links, ≥ 2 with one
  teammate and ≥ 50 % for "looks for" / "fed by"). Same scope rules as
  GameStatsReport: skipped sessions out, staff coaches stripped.
  (c) Quick peep Coach Insights add those readings (StudentQuickPeepView
  `chemistryInsights`, neutral wording, bilingual).
  (d) GameDashboardView (Views/Coaching/): the Games tab is two columns in
  regular width — games | dashboard + GAME INSIGHTS — and stacked on the
  phone. Tiles (games, points/game, boards/game, % off a pass), HOW THEY
  SCORE split bars, CHEMISTRY duos, PLAYMAKERS; This session | Program
  (starts on this session when it has games). Empty: how to drag an assist.
  GAME ROW (same day, Luther: "Game 1 and completed, a bit awkward" — in
  the narrower games column the old row broke its words letter by letter):
  regular width uses `wideGameRow` — "Game N" + FINAL (or the live status
  pill), "Regular · 3 min" on one line, the score with team dots and the
  winner bright, a ⋯ menu (Game Recap / Keep Scoring, Delete) in place of
  the two buttons; the row opens the game. The phone keeps its row, but its
  scores now use `GameTeam.displayColor` (the black team's score vanished
  in dark mode). Dashboard tile captions and chemistry lines wrap to two
  lines instead of truncating. HOOPWISE_SESSION_TODAY=1 (sessionPage) opens
  today's session that has games.
  (e) Attendance in regular width = two columns of cards (`attendanceGrid`:
  56 pt photo, name title3, second name, mark caption, the same segmented
  control, Photo in the card menu — no swipes there); compact keeps the List.
  (f) Mac only: the Plan / Attend / Games / Notes selector is a 44 pt capsule
  with a sliding pill (`macTabSelector`); iPhone/iPad keep the system picker.
  DEBUG: HOOPWISE_SHOT=gameDashboard; HOOPWISE_GALLERY_FULL=1 shows any shot
  full screen (an iPad page at regular width — a form sheet is compact);
  HOOPWISE_SESSION_TAB=<0–3> on sessionPage / pastSession. Tests:
  GameChemistryTests, SessionWideLayoutUITests (iPad mini — its demo store
  was re-seeded with sessions on 14 Nov 2026).
- GAME RECAP REDESIGNED (14 November 2026, Luther: "another page that's a
  weak point of our design. make it match the vision", all platforms — his
  request, so a sanctioned iPhone change). Views/Coaching/GameRecapView.swift
  (moved out of FlightySessionPageView): a HERO over CardCourtBackground
  (.fullCourt) — "GAME N · FINAL · M MIN", both teams' scores in big rounded
  type, a WIN pill, "Black won by 10" (a Battle Royal shows a podium); then
  glass cards under caps headers: PLAYER OF THE GAME (still picked by the
  contribution formula, which is no longer shown; five stats, zeros dimmed,
  ↑/↓ against their previous game today), HOW THEY SCORED (the basket log —
  % off a pass, split bar, the strongest passer → scorer; hidden without a
  log, `GameChemistry.summary(games:)`), AWARDS (award over player, value +
  unit; a tie is nobody's award; "Most Improved" never fired and is gone),
  BOX SCORE by team (team display colour + score, PTS REB AST STL BLK, the
  player of the game's row tinted with a crown on the photo). The random tip
  line and the CTR column are deleted. ≤ 720 pt wide. HOOPWISE_SHOT=gameRecap
  (a scratch Black v White game with a basket log).
- SESSION NOTES TAB REDONE (14 November 2026, Luther: "the weakest point of
  the session. have lines like a notebook. change the reflection tab for
  reminders. redo this notes section to be more aligned with the app", all
  platforms — his request). Reminders | Notes — Reminders first and the
  default (Luther, same day); the Reflection tab is gone. WIDE (15 Nov
  2026, Luther: the Mac "not taking advantage of the window size"): from
  1100 pt the switch goes and both show side by side — Reminders on the
  left (≤ 560 pt, 40 %), the notebook column on the right; narrower keeps
  the switch in an ≤ 860 pt column. DEBUG HOOPWISE_NOTES_WIDE_AT=<pt> moves
  the threshold (check on the iPad mini in landscape with 900).
  NOTES: the session's notes in a ruled card (Views/Components/
  RuledNotebookEditor.swift — rules at the body line height + 8 pt spacing
  from the text view's 8 pt inset, a programme-colour margin line; the
  editor GROWS with its text, scrollDisabled, so the rules never drift); an
  older coach reflection (coachNotes) keeps its own ruled card only while it
  has text — nothing new is written there; previous class's notes as a
  card; then HOW DID IT GO (stars, a word for the rating, tap the same star
  to clear) and PLAYER OF THE SESSION (was "Man of the Match" — same stored
  manOfTheMatchId) as cards, side by side in regular width. REMINDERS:
  `dataManager.reminders` with this sessionId — one-line quick add (Return
  saves; due "Before next class · <day>" = the program's next class after
  now − 1 h, else tomorrow 09:00; Tomorrow / In a week), the slider button
  opens the full AddReminderSheet, rows (circle toggles done, due in its
  status colour, tagged athletes), tap = edit, context menu Delete, a
  folded DONE list. Due reminders still surface in Home's attention
  (rule 5). The old SessionReminderSection component stays unused.
  SAME DAY, second pass (Luther: options next to the date, not a sheet; "@
  should tag the student and attach the reminder to their profile … no
  collab with other coaches, remove tagging coaches … make tagging work
  well throughout the app so reminders and alerts are smart and carry
  context"): the sliders button is gone — chips under the field: due
  (Before next class / Tomorrow / In a week / Choose a date… → compact
  DatePicker), Athlete (multi-select menu of the session's athletes),
  priority, Note (a field appears). "@" in the field suggests athletes (the
  session's first, then everyone, NameIndex matching — pinyin, initials,
  Chinese), a tap writes the name and tags them. Services/
  ReminderContext.swift: `ReminderMentions` (activeQuery — "@" at the start
  or after a space, so emails are not mentions —, inserting, matches) and
  DataManager `openReminders(taggedWith:)`, `reminderSource` ("from <program>
  · <day>"), `reminderAthleteNames`, `reminderContext`. Tagged reminders show
  on the athlete: StudentRemindersCard (Views/Components) on the profile
  (always, with a one-line add that tags them, due tomorrow 09:00) and the
  quick peep (only when there are some). Home's reminder alert subtitle is
  now "<athletes> · from <program> · <day> · Due …"; the briefing row adds
  the source. COACH TAGGING removed from the UI (quick add and
  AddReminderSheet); stored coach tags are untouched.
  CALMER (20 Nov 2026, Luther: the box was "kind of intimidating to interact
  with"): the quick add is ONE QUIET LINE — "+ Add a reminder", no box, no
  chips, no explanation line; the options appear only while writing
  (`reminderComposing`, on focus; folds 0.4 s after leaving an empty
  reminder so a chip's menu cannot close it) — due keeps its words, athlete
  / priority / note are icon-only until set; "Type @ to tag an athlete"
  shows until the coach has used @ or saved one (`reminders.mentionTipSeen`);
  Return saves and folds (keyboard down). Rows: the due date small and grey,
  red only when overdue. The pane is an accessibility CONTAINER — its
  identifier used to override the field's and rows'. Test:
  SessionRemindersUITests.
  FIXED: `refreshAllCaches` (the launch path) never called loadReminders —
  reminders appeared only after something ran the synchronous refresh (a
  write, an iCloud change), so on reopening a session its reminders looked
  gone. Tests: ReminderMentionsTests.
  CRASH FIXED (15 Nov 2026, Mac): tapping a reminder in the quick peep's
  Reminders card trapped in AddReminderSheet's @EnvironmentObject getter —
  the peep is itself a sheet and the store did not reach the nested sheet.
  Both AddReminderSheet presentations pass `.environmentObject(dataManager)`
  explicitly; do the same for any sheet opened from inside a sheet.
- HUB LANDING REDESIGNED (15 November 2026, Luther: "the command center
  bar should be more like a header that occupies the upper half … change
  Coach to Drills … a better set of icons, preferably bespoke … the private
  class tracker deserves to be better presented", all platforms — his
  request; refined the same day). FlightyHubView: a FULL PAGE on every
  platform (the iPad's sidebar split is gone — Luther: "the full page rather
  than a side bar"; tiles push their pages). A full-bleed court HERO (blue,
  CardCourtBackground .fullCourt, rounded bottom, under the status bar):
  phone — "COMMAND CENTER · Hub" with the theme switch on its line, the
  tracker under; wide — switch top right, title bottom left, tracker
  beside it (≤ 560 pt, hero ≥ 300 pt). PRIVATE LESSONS (second version —
  month total + six bars was rejected: bundle sales arrive in lumps): one
  line "November CN¥… · October CN¥…", then each private client with an
  active bundle as their photo in a RING of the bundle left (orange at
  ≤ 2, nearest renewal first, five + "+N"), "N bundles · N sessions left";
  the money line, "+N" and the footer open Revenue — PUSHED as a full page
  (`MonthlyRevenueHistoryView(pushed: true)`: no stack of its own, no Done;
  it was a popup) — and each client bubble opens their contract card
  (PrivateClientDetailSheet: history, sessions, Schedule) as a popup. On
  the Revenue page "Active bundles" and the empty-month "Active private
  contracts" (which listed every private contract, used-up ones too, and
  opened the profile) are ONE "Private clients" section: bundles with
  sessions left, active pay-per-session clients (rate, sessions this month),
  bundles used up in the last 30 days (dimmed, "Renew?"); every row opens
  the contract card; a past empty month says "No revenue". Tiles: LIBRARY — Plays, Drills (was
  "Coach"), Lexicon (three across when wide, Lexicon wide on a phone) —
  and PEOPLE — Teams, Organization. Icons are DRAWN (Views/Hub/
  HubGlyphs.swift: play diagram, cone, open book, jersey "23", org chart)
  in the ink colour on a neutral tile — the cone too (Luther).
  REDRAWN TO THE EDITOR TOOLS' STANDARD (18 Nov 2026, Luther: "give these
  icons the same treatment as the tools icon"): one stroke weight (1/12 of
  the side, ≥ 1.5 pt), round caps, no tinted fills, the tools' dart
  arrowhead, the offensive O's ring in blue (Plays, Coach board); Lexicon is
  an open book with text lines; the tile gained a 0.5 pt hairline edge.
  Identifiers hub.plays / hub.drills / hub.lexicon / hub.teams /
  hub.organization / hub.revenue. Tests: PlaysUITests (Drills,
  Organization open), TeamsUITests, LexiconUITests, OrganizationUITests.
- DELETE AN ATHLETE (15 November 2026, Luther: "I have no ability to
  delete students"). It existed only behind Athletes → + → Select Multiple.
  Edit Athlete (EditStudentView, existing athletes) ends with a red DELETE
  ATHLETE; the confirmation says what goes — profile, photo, guardian; N
  contracts AND THEIR PAYMENTS (so past revenue from them leaves the Revenue
  page); out of programs, teams, upcoming rosters and reminders; past
  classes keep their attendance. There is no archive (it would be a schema
  field). `deleteStudent` now also removes the id from program enrolment,
  team rosters, scheduled upcoming sessions' attendeeIds and reminder tags
  (they stayed behind and counted as expected players) before deleting
  contracts / player / student in one save. `.hoopwiseStudentDeleted`
  (object: id) closes the profile and clears the Athletes selection.
  Tests: DeleteStudentTests.
- THE PLAYER CARD (16 November 2026, Luther: the shareable student cards
  were "too much to take on so far … finish this once and for all"; decided:
  ONE collectible card for the child and parents, any time, labelled with the
  month; WeChat image AND A3 print sheets; the back shows what their classes
  trained; all platforms — his request, so a sanctioned iPhone change).
  BEFORE: four overlapping systems (~7,000 lines) — the Quick Peep flip card
  snapshotted into a 2-page PDF (imperial height, a default "HAND R", an
  empty grade, EFRT, a radar with +2.0 added to coach ratings, front and back
  of different heights), a Parent Preview that previewed one design and
  shared another (and said "Basketball Academy"), an unreachable monthly
  collectible system, UnifiedStudentCard and StudentIntelligenceProfileView
  (never constructed); the session's A3 export read `attendeeIds` (empty on
  real classes → "No players to export"). NOW:
  · Services/AthleteCardFacts.swift (pure, `AthleteCardFacts.make`): names
    (primaryDisplayName / secondaryNameLine), photo, program (+ age group
    only when the name lacks it), jersey ONLY when set, accent = program
    colour else age category; THIS MONTH: classes where attendance was TAKEN
    (present / excused / absent — unmarked is not absent) and present at,
    games this month; per game (PTS REB AST STL BLK) over every game
    (GameStatsReport); the OCTAGON = PlanCoverage of the plans of classes
    they ATTENDED this month, else every class attended, else none (never a
    guess); a coach's line typed when sharing (never stored); coach name and
    ProgramGuideStore.academyName.
  · Views/Components/AthleteCardViews.swift: AthleteCardFront / Back (360 ×
    504 pt, 5 : 7, always light), AthleteCardSpread (side by side = the
    WeChat image), AthleteCardRenderer (SwiftUI ImageRenderer — the old path
    hosted a view in an off-screen UIHostingController): `shareImage`, and
    `printSheet` = A3 landscape, 2.5 × 3.5 in cards, fronts page then backs
    page mirrored for long-edge duplex, crop marks.
  · AthleteCardShareSheet (Views/Components/): the spread as it will be
    sent, "A word from the coach", Share image (PNG) / A3 print sheet (PDF).
    Opened from the athlete profile's toolbar (`athlete.shareCard` — it had
    no share at all) and the Quick Peep (`peep.shareCard`, replacing "Share
    Card (PDF)" + "Parent Preview"). Session ⋯ and program ⋯ "Print Player
    Cards (A3)" use `athleteCards(forSession:)` (AttendanceMath.expectedIds +
    anyone marked) / `athleteCards(forProgram:)`.
  · DELETED: PlayerCardPDFExporter, MonthlyStudentCardExportService,
    MonthlyStudentCardPrintViews, UnifiedStudentCard, StudentParentReportView
    / ParentReportSheet / StudentReportImageGenerator / ReportLocalization /
    the old radar views, StudentIntelligenceProfileView and the sheets only it
    opened (≈ 5,500 lines). StudentParentReport.swift keeps
    ProgramStatsContext, PerformanceRadarMetrics (the in-app flip card) and
    ShareSheet. (The Quick Peep's old flip card went the next day — see
    below.)
  THE ORIGINAL LOOK, AND ONE CARD IN THE APP TOO (17 Nov 2026, Luther: "not
  entirely satisfied … make improvements based on the card I had originally
  … make the in app card match what is going to be exported"). The two
  sides are drawn in the ORIGINAL card's style (`AthleteCardStyle`): cream
  stock, saddle-brown frame, the name in CAPITALS over the court header,
  the photo overlapping the header's edge, a DIAMOND (now the program's age
  group — it was a coach-facing A/B/C grade), the school GRADE only (AGE,
  HT and HAND removed — Luther, same day; a Chinese card shows the grade
  as "二年级", no label — `SchoolGrade.shortName(chinese:)`, 19 Nov 2026), the MONTH pill (was "SINCE
  <year>"), the header a RADIAL gradient centred on the photo: clear at the
  photo → at the far corners the PHOTO'S OWN BACKGROUND colour
  (`AthleteCardFacts.backgroundHex(ofPhoto:)` — the average of the photo's
  four corners on a 32 px thumbnail, i.e. the background-removal swatch),
  else the program colour; court lines over it; a pale colour (luminance
  > 0.72) takes dark name type and no shade,
  and the six-cell grid PPG APG RPG / STL BLK GAMES (GAMES replaces EFRT).
  Back (Luther's markup, same day): "<MONTH>" over the name, centred
  "WHAT WE WORKED ON" (no icon, no scope suffix) over the octagon, centred
  "THIS MONTH" (classes taken, games), the coach's line, and the ACADEMY
  alone at the foot — no coach name, no HoopWise credit. The Quick Peep shows
  `AthleteCardFlip` — these same two sides, tap to flip, scaled to the
  column — so the in-app card IS the exported one. THE ATHLETE PROFILE too (same day, Luther:
  "change this to the player card"): StudentDetailView opens on
  AthleteCardFlip (≤ 420 pt) in place of its identity header (avatar, names,
  format tag, program schedule pills), and its Training Stats section is
  GONE ("already in the card") — CollapsibleTrainingStatsSection survives
  only in the gallery. StudentProfileCardView
  and StudentProfileHeaderView are DELETED; CardCourtBackground moved to
  Components/CardCourtBackground.swift.
  DEBUG HOOPWISE_SHOT=athleteCard (the sheet) / athleteCardExport (writes
  athlete-card.png + athlete-cards-a3.pdf to the App Group Library/Caches).
  Tests: AthleteCardFactsTests (incl. both sides the same size, 2-page A3),
  AthleteCardUITests (profile and peep).
- HOME SEARCH (16 November 2026, Luther: "a Spotlight-like search bar that
  only appears on the home screen upon dragging down the page … students,
  drills, plays, lexicon, private students, coaches, sessions, programs and
  teams", all platforms — his request, so a sanctioned iPhone change).
  Pulling Home down brings the search in WITH THE FINGER, as on the
  iPhone's home screen (Luther, same day: the first version — pull 80 pt,
  "Release to search", open after the bounce — was "awkwardly slow"): while
  the scroll phase is `.interacting` the overlay's field slides down and the
  blur fades in by `searchPull / revealDistance` (70 pt); letting go
  (`onScrollPhaseChange` leaving .interacting) past `commitDistance` (28 pt
  of overscroll) opens it — no hint capsule, no haptic.
  Views/Dashboard/HomeSearchView.swift opens OVER Home (material, field
  focused, Cancel / Esc). ⌘K toggles it (iPad keyboard, Mac). Groups in
  order Athletes (NameIndex), Private clients (active private contract of a
  matching athlete), Sessions (name, program, venue; upcoming soonest, then
  latest), Programs, Teams, Coaches (NameIndex), Plays (name, concept,
  situation — fetched once on open, NOT a @Query: see the Home redraw trap),
  Drills (name first), Lexicon (`Lexicon.search`); 5 each, "+N more"
  expands; Return opens the top hit. A tap closes the search and Home routes
  the target: athlete → profile sheet, private client → contract card,
  coach → profile, drill / lexicon / session / program / team / play →
  pushed. The pull is read with onScrollGeometryChange (offset + top inset).
  TRAP: an accessibilityIdentifier on the search's container overrode the
  field's own. Tests: HomeSearchUITests (iPhone and iPad).
  SMOOTHNESS (18 Nov 2026, Luther: "somewhat slow and stutters a bit
  compared to the one on Apple's home screen"): the pull lived in Home's own
  @State, so every frame of the drag redrew every Home card. It is now
  `HomePull` (@Observable: distance, dragging), written by the scroll
  callbacks and read ONLY by `HomeSearchOverlay` — Home's body never reads
  it. Searching no longer re-folds every session, drill and play per
  keystroke: `HomeSearchIndex` folds them once when the search is OPEN
  (after the field is in, `.task(id: live)` — the plays fetch used to run at
  the first pixel of the drag, a hitch), and a keystroke checks prepared
  text. Athletes/coaches still match through NameIndex (cached).
- HUB → LEXICON (11 November 2026, Luther: "a lexicon in the Hub for
  basketball terms — names of plays and their definitions, actions, rules,
  defenses", from his researched Claude Docs "Basketball Lexicon",
  claude.ai/artifact/6RDG4J5RsYhqReZzi6mVem). Resources/Lexicon.json is
  GENERATED from that doc's markdown export (16 sections → groups → 601
  entries: term, also called, definition, source numbers; group kinds terms /
  compare — FIBA·NBA·NCAA values per rule / history / disputed; 77 sources)
  — regenerate, don't hand-edit. Models/Lexicon.swift: load, `search` (every
  word in term / other names / definition; name matches first), `related`
  (terms a definition names, whole words, longest first), `dispute` (the
  disputed-terms entry for a term; "a / b", "a vs b", "… origin" split).
  Views/Hub/LexiconViews.swift: LexiconScreen (section tiles + search all),
  LexiconSectionView (grouped list, notes, search within), LexiconEntryView
  (definition, By rulebook values, "means more than one thing", Terms it
  mentions, Sources as links), LexiconCompareView (the rule grid),
  LexiconSourcesView. Read-only, not stored or synced. Content is ENGLISH as
  researched; chrome is bilingual. Hub card under Teams. HOOPWISE_SHOT=
  lexicon (+ HOOPWISE_LEXICON_TERM=<term> opens an entry). Tests:
  LexiconTests, LexiconUITests.
- TWENTY-FOURTH sanctioned exception (14 November 2026, Luther's request,
  iPhone + iPad + Mac): PROFILE PHOTO BACKGROUND REMOVAL. After the shutter
  in ProfilePhotoCamera (Add/Edit Student, the roster's Photo swipe) the shot
  goes to ProfileBackgroundPicker (Views/Components/): the subject is cut out
  ON THE DEVICE (Services/ProfileBackgroundRemoval.swift — Apple Vision's
  VNGenerateForegroundInstanceMaskRequest only; no network, no third-party
  model), swatches recolour at once (9 colours + "Original"; the last one is
  preselected, UserDefaults `profilePhoto.backgroundColor`), Retake / Use
  Photo; the result saves through the existing profileImageData + thumbnail
  path. Decided (Luther): NO original kept (no schema change), colour PICKED
  at capture, ON by default with Profile → Preferences → "Remove Photo
  Backgrounds" (device setting `profilePhoto.removeBackground`), and Edit
  Student has "Remove Background" for the photo already there (stored only on
  Save, like every edit on that page). Rules: the instance under the circle's
  centre wins, else the nearest; a touching instance under 40 % of its area
  joins (a ball Vision returned on its own), a second person beside stays out
  (`chooseInstances`, pure); the mask is feathered (Gaussian, 0.2 % of the
  side). From the camera, no subject / Vision error = the plain photo goes
  through unchanged — never blocks or loses a capture. VISION'S FOREGROUND
  MODEL DOES NOT RUN ON THE SIMULATOR (the cut-out returns nil there, so the
  simulator always takes the plain-photo path); it runs in the Mac Catalyst
  build (verified: ~0.7 s cold, ~0.2 s warm on the drawn stills). Test
  images are DRAWN (ProfileBackgroundDebug.swift, ProfileBackgroundTestScene)
  and exported to SAMpTests/Resources/BackgroundRemoval — no real photos.
  HOOPWISE_SHOT=backgroundRemoval (+ HOOPWISE_BG_SCENE=single|twoPeople|
  empty) shows the picker in Edit Student mode and logs "bg <scene> found|
  none <s>" to hoopwise.mac / background, writing results to the App Group
  Library/Caches/background-<scene>.png. Tests: ProfileBackgroundRemovalTests
  (the three Vision tests skip on the simulator; the Catalyst test runner does
  not launch — "Could not launch HoopwiseTests" — so check Vision with the
  Mac shot). Edge quality, gym light and A15 speed need a real device.
  THE COLOUR IS THE SKILL LEVEL (20 Nov 2026, Luther: "the background should
  represent their skill level compared to the group they are enrolled in";
  decided: five levels, in-app only, ask when sharing/printing, 65/35,
  colour drawn live). Models/SkillTier.swift: `SkillTier` Best (red, could
  move up) · Better (yellow) · Average (green) · Below average (blue) ·
  Bottom of the group (purple, candidate to move down) — words for the
  COACH only, never on anything a child or parent sees; colours =
  `PhotoPalette` (the Photos logo's petals, sampled; also the 8 swatches when
  a colour is picked by hand; `unranked` light grey). SCORE per GROUP
  program (`SkillLevel.tiers(in:)`, pure): evaluation = average of the rated
  octagon skills (≥ 4 of 8) as points from the group's average, 65 %; games
  = production per game (PTS + REB + 1.5 AST + 2 STL+BLK) in THAT program's
  games of the last 42 days (≥ 3 games) as a percentile mapped to −2…+2,
  35 %; one input alone decides alone; < 3 ranked members ranks nobody
  (private clients have no level). Bands from the group average,
  symmetric: ≥ +1.5 Best, ≥ +0.5 Better, > −0.5 Average, > −1.5 Below,
  else Bottom — a level group is all green. `SkillTierMap` (byProgram +
  primary = student.programId else the first group that ranks them) is
  rebuilt on the main thread 0.5 s after every cache refresh
  (`scheduleSkillTiers`, both refresh paths) and published ONLY when a
  level moves (`DataManager.skillTiers`, `skillTier(for:program:)`,
  `photoBackdropHex`). One pass over each program's games
  (`SkillLevel.gameScores`): 10 ms for 200 athletes / 600 sessions in a
  debug build (SkillLevelTests.testTheRebuildIsCheapAtFullSize; it was 36 ms
  calling playerGames per athlete). PHOTOS ARE STORED TRANSPARENT: the cut-out
  (`ProfileBackgroundRemoval.transparent`) saves as HEIC with alpha, its
  thumbnail too (`ProfilePhotoEncoding`, `UIImage.profilePhotoData`,
  `makeProfileThumbnailData`) — plain Data, no schema change; an opaque
  photo stays JPEG. Measured on the demo cut-outs: photo 23–31 KB (JPEG was
  33–44), thumbnail 18–24 KB (JPEG 25–32; a PNG thumbnail was 160–206 KB —
  never use PNG there). HEIC decodes in ~2 ms vs JPEG ~0.3, so the launch
  warm-up decodes ahead (`decodedProfileImage` → preparingForDisplay, off
  the main thread); `isTransparent(data:)` reads the file header only (a
  HEIC is written only for a cut-out). StudentAvatarView / StudentImageView paint the level
  colour behind (env `\.skillLevelProgram`: the session page = its program,
  the program page = it, else primary). The capture review shows the cut-out
  over the level colour with Cut out | Original (the swatches are gone).
  Cards: in the app the level colour; AthleteCardShareSheet has "Photo
  background" (Keep level colour · the 8 petals, `CardBackdropPicker`), and
  session / program "Print Player Cards (A3)" first opens CardBackdropSheet
  (`CardBackdrop` .level / .color; each card's level in THAT program).
  Widget photo files flatten a cut-out over its level colour (part of the
  re-encode hash). PHOTOS TAKEN BEFORE THIS have the old colour burned in
  and show no level until re-cut (Edit Student → Remove Background).
  DEBUG HOOPWISE_DEMO_CUTOUTS=<folder of <athlete id>.heic> (+
  HOOPWISE_DEMO_EVALUATIONS=1) loads Mac-made cut-outs (the simulator cannot
  run Vision) into the DEMO store and logs "bg level <name> <tier>". Tests:
  SkillLevelTests, ProfileBackgroundRemovalTests (transparent storage),
  AthleteCardUITests.testTheShareSheetAsksForThePhotoBackground.
- LIVE ACTIVITY — ONLY TWO MOMENTS (October 2026, Luther): an activity is
  on screen for a class that is LIVE (counts down the time left) or that
  starts within 10 minutes (counts down to the start). Nothing else.
  `SessionLiveActivityManager.reconcile(targets:)` is THE writer: the
  monitor's 30s tick passes `SessionStatusMonitor.liveActivityTargets`
  (scheduled/in-progress, not skipped, not over, allowed by
  SessionSeries.allowsLiveActivity, within 12h, max 4) and every other
  activity is ended with .immediate dismissal — including one an older
  build armed hours early (that was the frozen "1:30:00"). Later classes are
  SCHEDULED with iOS 26's `Activity.request(…, start:)` at T−10, so they
  appear with the app closed (verified in the simulator: active at exactly
  T−10). The upcoming → live flip is the stale-date redraw at the start
  (ActivityClock in the widget decides by render time; verified on time).
  iOS gives no way to END an activity at a set time without a push server:
  at the class end it holds 0:00 until a BGAppRefresh
  (`com.hoopwise.liveactivity.cleanup`, earliest = the class end, runs
  `endFinished`, which needs no data) or the next app run removes it. iOS
  decides when that refresh runs; it is usually minutes, not guaranteed.
  Simulated launch via lldb `_simulateLaunchForTaskWithIdentifier` removed
  it. Completing the class in the app removes it at once. Scheduled starts
  carry an alert ("Class in 10 minutes"). DEBUG
  HOOPWISE_LIVE_ACTIVITY_DEMO=<seconds> runs a scratch 5-min class through
  the same reconcile (1 = 60s; 660 shows the scheduled T−10 appearance).
  Covered by LiveActivityTargetsTests. The floating in-app pill is gone: iOS
  never shows an app's own activity while it is in front.
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
- iOS/Mac feature parity is CANCELLED as a goal. (Superseded 6 November
  2026: the Mac app is retired — see "THE MAC APP IS RETIRED".)
- (History) The Mac app was to become an authoring tool: court/play editor,
  PDF play sheets, animation export, knowledge base. Retired with it.

## Current state (August 2026, restructure complete)
- CloudKit sync works. Both apps see the same private-database data.
- HoopwiseMac builds and runs; Settings has General / Profile / Sync /
  Data.
- THE PHASE 2 RESTRUCTURE IS DONE — see RESTRUCTURE.md for the one-page
  summary: store end-state, per-phase commits, the invariants the reconciler
  enforces, and the OPEN LEDGER. Read the ledger before starting anything in
  the session/contract area; it is what is deliberately unfinished.
- Store, 2026-08-11: 201 sessions · 21 phases · 17 programs · 176 contracts ·
  134 athletes. BROKEN 0, duplicate groups 0, phase-window violations 0,
  5 standalone sessions (the triage list in RESTRUCTURE.md).
- A SCHEMA DEPLOY IS OWED before any released build: seriesId, signedDate,
  jerseyGivenDate, ballGivenDate, SDTeam.playbookData (rule 7d/7e). They are written and working in
  Development; Production does not know them yet.
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

## School grades promote themselves (October 2026)
- The stored `schoolGrade` is what the coach PICKED; `Student.currentSchoolGrade()`
  is what every reader shows — it advances one grade each 1 September. No
  schema change: picking a grade writes `birthdate` as 1 September of the
  matching birth year (`SchoolGrade.estimatedBirthdate(asOf:)`, counted from
  the running SCHOOL year — it used the calendar year, so a grade entered in
  spring was a year off), and that anchor is what promotion reads.
- `Student.setSchoolGrade` is THE writer (grade + anchor together): iOS add/
  edit, Mac add sheet and athlete card. A grade written without its anchor
  is read back as whatever the old birthdate says. Mac card re-anchors only
  when the picker actually changed. Past H6 → no grade.
- Student Intelligence peers (`effectiveGradeKey`) use the promoted grade, or
  the grade the AGE puts a child in, on ONE scale (it used to mix H1 and an
  invented "M1"). Its birthday milestone skips grade-anchored birthdates —
  1 September is an estimate, not a birthday. Covered by
  SchoolGradePromotionTests.

## Activity library — the drill library (October 2026)
- Luther's "Activity Library: U6 to U16" (Claude Docs, sourced FIBA / Jr. NBA /
  USA Basketball …) REPLACED the 121 bundled sample drills. It is embedded as
  JSON in Models/ActivityLibraryData.swift (generated — regenerate, don't
  hand-edit) and modelled in Models/ActivityLibrary.swift (both targets):
  476 items = 7 ages (U6, U7, U8, U10, U12, U14, U16) × 4 blocks (routine,
  small games, compete, game) × 15 types (the doc's 55 sub-headings folded).
- Activities and games (422) are seeded as SDDrill records with
  DETERMINISTIC ids (SHA-256 of "age|block|name") so every device seeds the
  same record and plans resolve everywhere. Tags carry `library`,
  `library:<key>`, the planner age tag (U7 → `u8`; DrillProfile has no U7),
  `block:`, `type:`, `kind:`. No schema change.
- RULE OPTIONS (54) are NOT drills: read from the library only, shown under
  the Game block, never in session planning.
- `syncActivityLibrary()` (every launch, idempotent): deletes the old samples
  — only records with no coach owner whose name is in
  `DrillItem.legacySampleNames` (an older build elsewhere can re-seed them);
  inserts missing library drills; refreshes a library drill's text unless a
  coach edited it (`lastModifiedAt`). `deduplicateDrills` keys library drills
  by ID — the same name at two ages is legitimate.
- iOS drills page (sanctioned, Luther): age chips + "Mine" (coach-created),
  block segments, type chips; guidance and "Include earlier ages" (default
  off; each age adds to the ones before) behind ⓘ. Detail shows age/block/
  type, the source (linked) and "How it runs". HOOPWISE_SHOT=drillsLibrary.
  Tests: ActivityLibraryTests, ActivityLibraryUITests.
- Mac gets the same drills through the shared seeding; its page is unchanged.
- CHINESE (October 2026, Luther: "useless to Chinese-only coaches if not
  localised"): every item carries `nameZh` + `howItRunsZh` and every age
  `titleZh` + `guidanceZh`, translated to natural coaching Chinese against a
  shared glossary (7 parallel translators + one consistency review across
  ages: terms, cross-references, block/tab labels, misleading titles).
  `fibaNameZh` keeps FIBA's Chinese-edition name where the new title replaced
  it (shown under the source as "FIBA 中文版：…"). Library drills read their
  name/description from the library (`localizedName`/`localizedDescription`)
  and NEVER from the legacy DrillContentLocalization name table; a coach's
  edit wins. Sources stay as cited. Regenerate data with the merge step, never
  hand-edit ActivityLibraryData.swift. Pinned by ActivityLibraryChineseTests.
- Guidance and "Include earlier ages" live behind the ⓘ toolbar button
  (read 2 in 10 visits — not worth the top of the list); while the switch
  is on, a one-line note under the age chips says so.
- THE PLAN ENGINE (Services/DrillPlanGenerator.swift, October 2026 rewrite)
  plans from the library: slots follow its blocks (warm-up ← routine + a
  closing small game, skills ← compete, game ← game), rule options never.
  It reads AGE (program age group → library age), LEVEL 1–5 (the program
  page's Training level slider, stored as `ProgramSkillTargets.level` in the
  existing skillTargets JSON — no schema change; unset → player evaluations
  suggest one only when ≥ half the roster is rated; else 3), which sets the
  AGE WINDOW (3 = this age + the one below; 4–5 borrow older; 1–2 younger),
  FOCUS (phase focus, weakest evaluated area, and with ≥ 3 games a low
  assists-per-basket signal → passing), and HISTORY (every earlier plan of
  the program: nothing from the last session repeats; review vs new is 30/70
  in a phase's first two sessions, 60/40 after). `PlanRationale.summary` is
  shown under the plan. GENERATE ASKS FIRST (19 Nov 2026, Luther: "make it a
  custom generate with coach input — different parameters that would make
  the plan perfect"): Generate Plan and Regenerate open PlanGenerateSheet
  (Views/Coaching/) — BUILD IT AROUND (the eight skills as chips; preselected
  = the phase's gaps ≥ 0.4, top two), TIME (warm-up / skills minutes), LEVEL
  1–5 (starts on the engine's pick, which the footer names), MIX (Auto / All
  new / Half / Mostly review), "Don't repeat last class", and on a planned
  session "Keep what's planned, fill the rest". `DrillPlanGenerator.Options`
  (all defaults = the engine as before): chosen skills weigh as a gap of 1.5
  and the rationale says "your focus: …"; `History.forgetLastSession`.
  Tests: PlanGeneratorTests.testCoachOptionsShapeThePlan, PlanGenerateUITests
  (also the iPad games list's status word — `statusBadge` is fixedSize, it
  read "Re…"; DEBUG HOOPWISE_DEMO_READY_GAMES=1|clear on sessionPage writes
  three unstarted games to the demo store, once per launch).
  THE COACH'S WAY (19 Nov 2026, Luther: "rate drills so the engine knows to
  use more often or never … too easy, boring, not challenging, no kids at
  that stage … the engine learns my way of coaching"): every drill has a
  PREFERENCE — Use more · Normal · Use less · Never — and for less / never a
  reason (Too easy · Too hard · Boring · No one at that stage yet).
  Models/DrillPreference.swift; stored in the drill's synced TAGS
  (`pref:use=…`, `pref:why=…`, normal writes nothing) — no schema change;
  `setDrillPreference` writes only the tags (no revision, no
  lastModifiedAt, so a library drill still refreshes its text) and
  syncActivityLibrary keeps `pref:` tags like `attr:`. ENGINE: never = not a
  candidate; more = score + 2.5; less = score × 0.25. Set on the drill page
  ("In my plans" card under What it develops) or from a plan row (open it →
  Rate: the four, or "Never use, and take it out"); rated drills carry a
  small mark in the plan and the library. Reasons are recorded for the
  coach; the engine does not read them yet. Tests: DrillPreferenceTests,
  DrillPreferenceUITests.
  `ProgramSkillTargets.hasTargets` (lastUpdatedDate
  set) gates skill-target comparisons, so a level-only blob never shows
  default 5s as targets. Tests: PlanGeneratorTests, PlanGeneratorUITests.

## Tracked shooting drills (20 Nov 2026, Luther)
"Drills that are part of Hoopwise — added to a session they appear as an
add-on in the plan with a functioning mechanism … made vs miss or made in a
set amount of time … add to athletes and make it part of the student eval."
Decided: five spots for 2PT and 3PT, free throws one number; one clock per
spot; twos at Short / Mid; numbers BESIDE the rating only; in groups the
athletes SELF-REPORT, so entering a number must be one tap.
- Models/ShootingTest.swift: `ShootingDrill` (twos, freeThrows, threes —
  fixed ids, tag `tracked:<raw>`, seeded by syncActivityLibrary with
  `attr:shooting=3`; names/descriptions bilingual via localizedName),
  `ShootingSetup` (mode attempts | timed, shots or seconds a spot, range for
  twos; `key` = the comparison key; the coach's last setup per drill is
  remembered in UserDefaults `shooting.setup.<drill>`), `ShootingRun` (one per
  tracked drill in a plan: entries = per athlete, makes per spot, nil = not
  reported), `ShootingResult` (attempts → share over the spots reported;
  timed → makes a minute). Stored in `SessionCurriculum.shooting` (curriculum
  JSON, no schema change).
- Library: a "Tracked shooting" section at the top of the drills page and
  the plan picker (`library.tracked`); not listed under Personal.
- Plan: tracked drills in Warm-up/Skills show ADD-ONS under Skills
  (Views/Coaching/ShootingAddOnCard.swift): setup menu (locked once a result
  exists), a per-spot clock for timed (buzzer; when it ends, the pencil opens
  the pad on that spot), one row per athlete (present ones once roll call
  started, else expected) with a cell per spot, result, "Last …" and ↑/↓ vs
  last time, a group line. THE PAD (`ShootingEntryPad`): number buttons
  0…shots (timed 0…20+); a tap writes and moves on — made-of-N walks athlete
  by athlete through the spots, timed walks the athletes at the clock's spot;
  closes after the last empty cell; ‹ › and Clear.
- Private sessions: the Plan tab has no Plan Balance and no Plays.
- Athlete: Services/ShootingHistory.swift (series per key oldest first,
  previous, evidence); profile → ShootingProfileSection (latest, best, last
  3, sessions, a trend chart, five spot dots hot/cold vs their own average);
  Quick Peep → under the SHOOTING rating, up to three lines "FT · 10 shots:
  64% (last 3) · up from 48% · 2nd of 9 same grade" (peers = same current
  school grade). Never sets the rating.
- Plan engine: `shootingSignal` — the roster's latest made-of-N results
  average < 35 % over ≥ 3 athletes → shooting focus, "low shooting-drill
  results" in the rationale.
DEBUG HOOPWISE_DEMO_SHOOTING=1|clear on sessionPage (HOOPWISE_SESSION_TAB=0).
Tests: ShootingTestTests, ShootingAddOnUITests (iPad mini).
SEVEN DRILLS + THE GROUP CARD (21 Nov 2026, Luther: "add other types … actual
real ones … midrange in general (one rebounds, the other shoots) … the UI
could use improvement — 12 athletes, data visibility, interactivity, ease of
use"; and the athlete's Shooting section in the Quick Peep too):
- Drills, close to far: Free Throws, Lay-Ups Both Hands (right / left hand),
  Mikan Drill (under the rim, default timed 1 min), 5-Spot Twos, Mid-Range
  Shooting (partner rebounds, any mid-range spot, one total, default 20
  shots), Pull-Up Jumpers (going right / going left), 5-Spot Threes. Spots
  are table-driven per drill (`spots`); ids 1–3 unchanged (results keep
  their drill), 4–7 new. Lay-ups and Mikan rate as FINISHING (3), pull-ups
  add ball handling. The library section filters by the chosen skill.
- The card: header (drill symbol, title, setup + Change before any result,
  LOG MAKES, fold); a SUMMARY readable folded (Logged n/N with a bar, Group
  vs the same athletes last time with ↑/↓, Best today); the per-spot clock
  (timed); a TABLE — spot column heads once, cells tinted by value (heat),
  result with ↑/↓ and "last …", sort menu (roster / best first / still to
  log first, `shooting.sort`), a SPOT AVERAGE footer.
- The pad (`ShootingEntryPad`, full sheet): spot chips, EVERY ATHLETE AS A
  PHOTO (green badge = their number at this spot, dimmed once in) — the
  athletes self-report in any order, so tap whoever walked up — then the
  numbers. Made of N: next empty spot of that athlete, then the next
  athlete; timed: the next athlete at the clock's spot; closes when nothing
  is left.
- Quick Peep: ShootingProfileSection under the skills (both layouts); its
  spot dots now carry the spot labels.
THE SHOT CHART (21 Nov 2026, Luther: "this type of map … tap on a zone,
enter numbers, the app calculates the percentage per student … useful to
show athletes"; decided: 10 zones, made + attempted per zone, other drills
fill the athlete's map, absolute bands by default with "own average"):
- The eighth tracked drill `.shotChart` (id 8): ten zones = its spots — at
  the rim (2.5 m from the rim centre), left baseline / left elbow / right
  elbow / right baseline mid-range (rays at 45° · 90° · 135° from the rim),
  left corner / left wing / top / right wing / right corner three (corners
  outside 6.6 m below where the arc meets them; rays at 60° · 120°). A new
  mode `.chart`: MADE AND ATTEMPTED per zone (`ShootingEntry.attempts`,
  optional — older entries decode without it; `setAttempts`;
  `ShootingResult.shots(at:)` is the one place a spot becomes made/attempted);
  or the drill's .attempts mode = the same shots in every zone.
  `ShootingMode.isShare` replaces "== .attempts" wherever a share is meant.
- Views/Components/ShotChartMap.swift: the zones are CGPath boolean ops in
  court METRES (FIBA: arc 6.75, corners 6.6, lane 4.9 × 5.8), basket at the
  BOTTOM like a broadcast chart (plays draw it at the top); each zone a
  tappable shape, % and made/att on it, ↑/↓ deltas, the court lines over
  it; colour `ShotChartColour` bands (<25 / 25 / 35 / 45 / 55+ %, legend) or
  ownAverage (±15 % hot/cold); `forImage` = light for sharing. A zone
  element's accessibility frame is its bounding box (L-shaped zones: the
  centre may lie in a neighbour — UI tests tap inside, after scrolling).
- In the plan: ShotChartAddOnCard — athletes as photos (+ Group pooled,
  each with today's % badge), the map, By % | Vs own average, Vs last time,
  a summary line. Tap a zone → ShotZonePad: athletes, a small map (tap
  another zone), made then attempted (made…made+20), then the athlete's
  next empty zone.
- The athlete's map (ShootingHistory.zoneMap / zones(of:student:)): the
  Shot Chart zone = zone; 5-Spot Threes → the five three-point zones;
  5-Spot Twos at MID (not short) → corners to baseline mid, wings to the
  elbows, the top split between the elbows; lay-ups and Mikan → at the rim;
  timed results never (no attempts); free throws BESIDE the map
  (`freeThrows`). Profile and Quick Peep: AthleteShotChartCard leads the
  Shooting section (All sessions | Last session; ↑/↓ = all vs before the
  latest session); tap → AthleteShotChartScreen (zone list, colour, SHARE —
  a light 600 pt card rendered at 3× via ImageRenderer: name, month, map,
  legend, free throws, academy).
THE WHEEL (21 Nov 2026, Luther: "a scrolling wheel would be elegant and
practical"): Views/Components/NumberWheel.swift — a horizontal ruler of
numbers snapping to the middle (scrollPosition + viewAligned), a haptic
tick per number, tap a number to jump, VoiceOver adjustable; numbers are
`<identifier>.<n>` (lazy — only those near the middle exist). The shooting
pad uses it when there are MORE THAN TEN numbers (≤ 10 shots keeps the
one-tap grid): it starts on what is in, else that athlete's number at this
spot LAST TIME, else half the shots (timed: the others' median here); quick
chips save at once (0 · half · all; timed: 0 · last time); LOG n saves and
moves on. The shot chart pad: MADE and ATTEMPTED wheels side by side (start:
what is in, else their last chart's zone, else 4/10), the live %, one LOG
(refused while made > attempted); fixed shots per zone keeps the grid.
DEBUG HOOPWISE_DEMO_SHOOTING=chart puts the Shot Chart in the demo plan.
THE LOG POPUP IS A NUMBER PAD, NOTHING ELSE (23 Nov 2026, Luther, two
markups: a phone-style keypad floating over a field — "I prefer this floating
number pad … especially the trackable drills" — then: "the log pad should be as
clean as in the screenshot, just a number pad. everything else is noise there.
the spots already appear on the drill screen, and the athletes too … other
drills still use different views and methods"). Views/Components/
FloatingNumberPad.swift: `FloatingNumberPad` (1–9, then [✓ / → / .] 0 ⌫; keys
"<id>.key.<digit>", ".key.confirm", ".key.next", ".key.dot", ".key.delete";
`chrome: false` inside a popover) and `NumberPadEntry` (pure typing rules: the
FIRST key replaces what is in the cell, later keys append, past the top starts
again from the key, no leading zeros, decimals only when asked —
NumberPadEntryTests). EVERY tracked drill logs the same way: tap a cell in the
station's table (or Log / Log makes = the next empty cell) → the keys pop out
of THAT cell (`.cellNumberPad`, `PadCell`); what is typed shows in the cell
(orange ring); ✓ logs and the next cell opens (made of N: the athlete's next
spot, then the next athlete; timed / one spot: the next athlete at that spot;
custom drills: next empty spot); ⌫ to empty + ✓ clears; a tap outside keeps
what was typed. The next popup opens only when the previous one has GONE
(`onClosed` = the content's onDisappear) — opening it while the last one is
still closing is refused by iOS and nothing appears. The SHOT CHART: the keys
pop out of the tapped ZONE (`ShotChartMap.pad`, anchored on the zone's bounding
box), with made / attempted as two small boxes (→ moves on; made > attempted
refuses ✓) and the athlete's next empty zone after ✓. The coach's own
TIME-TO-FINISH drills: seconds with tenths on the same pad, and a STOPWATCH on
the station page that drops each stopped time into the next athlete's cell
("Next: <name>"). Gone: the big pad sheets (ShootingEntryPad, ShotZonePad,
CustomTrackPad — athlete photos, spot chips, prompts, quick chips), the ≤ 10
one-tap grid, the wheel (NumberWheel) and the second paired pad. Number FORM
fields open the same pad as a popover (`NumberPadField` / `NumberPadTextField`):
the contract sheet's price per session, payment amount and travel fee, and
SalesView's price, amount paid and jersey number. Tests: ShootingAddOnUITests,
CustomTrackingUITests (keys by identifier; a tap near the bottom-left corner
closes the popup).
RESULTS ARE LIVE DATA (21 Nov 2026, Luther: add-ons with recorded results
vanished from a session hours later). Causes: (1) Regenerate rebuilt the
curriculum keeping only notes and plays — results and tracked drills went;
(2) every whole-session save (auto-close at end + 12 h, auto-start, Home /
attention actions, another device whose copy predated the results) wrote
its curriculum back, and SDSessionEvent.apply assigned EVERY column, so
the stale plan was changed and uploaded too. Fixes: `setSessionShooting`
is THE writer of `curriculum.shooting` (field-level, a revision first; the
add-on binding calls it, never saveSession); `updateSessionEvent(keepLive
Fields: true)` keeps the STORED shooting like games and marks; `apply`
assigns only fields that DIFFER (a status change no longer rewrites the
plan); the page refresh always takes the stored shooting; Regenerate keeps
tracked drills and results; an add-on with results shows even when its
drill left the plan. Restore Earlier Version lists shooting results per
version and offers "Bring back the shooting results only". Sync: results
live in `curriculumData` (an existing synced column) — no schema change.
Tests: ShootingPersistenceTests.
DRIBBLE OUT & SHOOT (21 Nov 2026, Luther): `.dribbleShoot` (id 9) —
dribble to half court or the far baseline and back, shoot, own rebound,
repeat; one total; default makes in 1 min at half court; `CourtLength`
(`ShootingSetup.court`, optional — in the key, so half and full compare
apart); rated shooting / ball handling / footwork 2; not on the map.
Tests: ShootingTestTests (chart maths, map feeding, deltas, zone geometry),
ShootingAddOnUITests.testShotChartLogsAZoneFromTheMap.
BIG NUMBERS ON THE SHOT CHART (23 Nov 2026, Luther: a client's target was 60
made a spot and the pad "wouldn't let me log such high numbers"). The zone
pad capped made at 40 and attempted at 50 — a value past the cap restarts
from the key pressed, so "60" became "0". Both now take up to
`ShotChartAddOnCard.mostShots` (999). The setup's shots a spot / zone and a
custom made-of drill's amount go to 500 (were 100). Test:
ShootingAddOnUITests.testShotChartLogsAZoneFromTheMap logs 60 of 100.
THE CHART'S NUMBERS, LARGE, AND SHARE (23 Nov 2026, Luther, markup on the
one footnote line under the session's shot chart: "make these bigger and
more detailed — I'd like to share this with my client").
Views/Components/ShotChartBreakdown.swift: `ShotChartTotals` (pure: total,
threes = zones 5–9, mid = 1–4, rim = 0, best / weakest zone when two differ)
and `ShotChartBreakdown` under the map — the total at 52 pt
(`shotchart.total`), "N made of M shots", ↑/↓ against last time or the round
before, tiles by range (only with two or more ranges), Best / To work on,
and every logged zone as name · band-colour bar · made/att · %. "Share this
chart" (`shotchart.share`) = `SessionShotChartShareCard` — light, 600 pt at
3×: name, date, map, legend, the same numbers, academy — through ShareSheet.
Group works the same (pooled). The share picture was not looked at on screen.
TRACKER ON THE ROW, STATION AS A PAGE (23 Nov 2026, Luther: "annoying to set
up … the time could only be set up to 3 minutes, they took too much space and
collapsing them … was popping back up"). The ADD-ONS section of big cards
under Skills is GONE (its fold was @State, reset on every redraw). A tracked
drill's own plan row (drillRow) carries ONE tracker line
(Views/Coaching/ShootingStation.swift `ShootingTrackerLine`,
`shooting.tracker.<drill>`): setup, n/N logged with a bar, the group result
with ↑/↓ against last time, and Log (Results when read-only). The line opens
the SHOOTING STATION (`ShootingStationSheet`, page-sized, Done): the same
cards with `station: true` — no fold, no card frame. SETUP IS A SHEET
(ShootingSetupSheet, from "Change" in the card header, `shooting.setup`;
locked once results exist, as before): the summary on top, scoring
segmented, shots 1–100 (stepper + chips), time on minute / second wheels
5 s…20 min (chips 30 s…10 min), range / dribble-to; remembered per drill.
`ShootingSetup.time` prints 1:30 (1分30秒) for odd minutes. Tracked drills
with results that LEFT the plan show under Skills as "Shooting results" rows
with the same tracker line. HOOPWISE_DEMO_SHOOTING now clears results through
setSessionShooting (whole-session saves keep them). Tests:
ShootingAddOnUITests (all four through the tracker → station, plus
testSetupSheetTakesLongTimes).
THE COACH'S OWN TRACKED DRILLS (23 Nov 2026, Luther: "be able to create my
own trackable drill … control the variables … what the result would mean on
the player's oct evaluation"; decided: all four measures, ONE number per
drill, compared with own history + same-grade peers, the octagon SUGGESTS a
rating taken with one tap). Models/CustomTracking.swift (pure):
`TrackMeasure` madeOf (makes of N → share) · inTime (how many in N s, unit
default "makes") · timeToFinish (stopwatch, lower better) · count (unit,
higher or lower better); `TrackDefinition` (amount, optional named spots,
unit, direction, linked octagon skills; `key` = measure|amount|spots —
results compare only under the same key). DEFINITION = ONE drill tag
`track:<base64 JSON>` (no schema change; syncs; kept by syncActivityLibrary;
hidden from the tag chips) — New / Edit Drill → "Tracking" (toggle, measure,
amount, unit / direction, "Log by spot or side", skill chips, footer saying
what happens); writer for tag-only changes `setDrillTracking`. RESULTS =
`SessionCurriculum.tracked: [TrackedRun]` (its own JSON key; a run keeps the
definition it was taken with; entries athlete → one value a spot), THE writer
`setSessionTracking`, kept by keepLiveFields saves, Regenerate keeps tracked
drills and results. SESSION: the drill's plan row carries `CustomTrackerLine`
(`track.line`) → `CustomTrackStationSheet` (summary, table, Log `track.log`)
→ `CustomTrackPad` (athlete photos, spot chips; grid ≤ 10 shots, else the
number control; a stopwatch Start/Stop + seconds.tenths wheels for a time;
starts on what is in, else last time, else the others' median today).
Results of a drill that left the plan show under "Shooting results".
ATHLETE: `CustomTrackHistory.standings` (last-3 average, sessions, trend,
rank and percentile among same-grade peers — ≥ 3 with results for a
percentile; skipped sessions out); profile + Quick Peep "Tracked drills"
(CustomTrackProfileSection: last 3, best, sessions, same-grade rank, chart —
reversed for lower-is-better, linked skills); Quick Peep evaluation: the
lines under each linked skill and "Results suggest N · Use"
(`suggestion` = linked percentiles averaged → 2…9; Use writes the rating at
once, or into the draft while editing) — never set automatically. Drill page:
DrillTrackingCard. PLAN ENGINE: `trackedSignals` — a made-of drill the roster
makes under 35 % (≥ 3 athletes, latest each) puts its linked skills in focus,
rationale "low tracked-drill results: <skill>". DEBUG HOOPWISE_DEMO_TRACKED=
1|clear on sessionPage (demo drill "Wall Passes", 30 s, passes, Passing).
HOOPWISE_DEMO_SHOOTING also resets remembered shooting setups. Tests:
CustomTrackingTests, CustomTrackingUITests (iPad mini).
THE TYPE DRIVES IT (24 Nov 2026, Luther: "the kind of tracking should
determine the setup … shooting: how it's measured, what it impacts in the
eval — how much of Shooting plus how much of athleticism — needs a shot map?
… conditioning: laps in how long, sprints on a distance … not an incomplete
pain point"). `TrackKind` (shooting · finishing · ballHandling · passing ·
conditioning · defense · other) is chosen FIRST in New / Edit Drill →
Tracking; `kind.preset(measure:)` fills the measure (each kind lists only its
own, in its words — "Time over a distance"), amount, unit, sides and the
skills; picking another kind re-applies its preset, changing the measure
keeps the coach's skills / zones / sides. Definitions from before kinds read
as `.other` and their JSON, tag and comparison key are unchanged (new fields
are written only when set).
· MAIN / SOME: `TrackDefinition.some` ⊂ `skills`; a skill chip cycles off →
  Main → Some → off; `weight(for:)` 1 / 0.5. `suggestion` = percentiles
  weighted, and NIL unless the links add up to ≥ 1 (a lone "some" link never
  moves a rating). The plan engine reads MAIN skills only.
· SHOT MAP (shooting): `zones` = the ten ShotChart zones the drill is shot
  from, picked on `ShotZonePicker` (ShotChartMap.swift; numbered in logging
  order); spots ARE the zones (`onShotMap`, names `zoneShort`). Made-of
  results join the athlete's shot chart — `ShootingHistory.zones(of:
  TrackedRun…)` in `zoneMap` / `latestMapSession`; a FINISHING made-of drill
  lands at the rim (zone 0, both hands pooled); timed results have no
  attempts and stay off. The station shows the court for such a drill
  (Group | each athlete; the drill's other zones dimmed — ShotChartMap
  `dimmed`); a zone opens that cell's pad. On a phone a table with > 3 spots
  scrolls sideways.
· COURSE (conditioning, ball handling; not for a plain count): `TrackCourse`
  halfCourt · fullCourt · downAndBack · lineDrill · seventeens · lap — in the
  comparison key, so a time compares only over the same distance. No court
  map for conditioning (decided: the place is not the data, the distance is).
· PLAN ENGINE: `trackedSignals(runs oldest first)` — the < 35 % made-of
  signal, plus "trackedDown:<skill>:<percent>" for ANY measure: ≥ 3 athletes
  with a latest and a previous result under the same key, the group ≥ 10 %
  worse (slower / fewer / lower).
· CLAUDE PRE-FILLS (Mac — the key lives there): DrillWriter's answer gained
  `tracking` {kind | none, measure, amount (PER ZONE when split), unit, main,
  some, zones, course | none}; the form shows "Claude suggests tracking:
  <kind> — Use" and switching Track results on starts from it; never applied
  by itself. VERIFIED LIVE 24 Nov 2026 on the Mac demo copy: corners threes →
  shooting, 10 a zone, zones [5, 9]; suicides → conditioning, timed, Line
  drill; 45 s weak-hand lengths → full court, ball handling main; Mikan 30 s
  → finishing, makes in a time; a walkthrough → none. (A wrong strict schema
  would break Return-writes-the-steps too — rerun HOOPWISE_SHOT=newDrill +
  HOOPWISE_NEWDRILL_DESCRIPTION after touching it; the log line is
  "drillWriter tracking:".)
· CONNECTOR: create_drill / update_drill take `tracking` (same shape, plus
  sides, higher_is_better, {"off": true}); `TrackDefinition.parsed` names a
  bad field; get_drill returns it, list_drills says "tracked". NOT verified
  over HTTP.
· LIBRARY: "My tracked drills" section under Tracked shooting; the drill
  page's Tracked card shows kind, zones, main / some.
DEBUG HOOPWISE_DEMO_TRACKED=zones (a shooting drill on corners + top);
clear now deletes the demo drills. Tests: CustomTrackingTests (14),
CustomTrackingUITests (form driven by the type; logging on the shot map).
ActivityLibraryUITests had been failing on the mini since the Tracked
shooting rows pushed the lazy library rows out of reach — they scroll now.
DrillPreferenceTests.testTheEngineFollowsTheCoach is order-dependent (picks
from an unordered set): fails now and then in a full run, passes alone.
ROUNDS (23 Nov 2026, Luther: "what happens if I want multiple 5-Spot Threes?
… sometimes I run the same drill more than once, to see how they improve
within the session or after correcting something"; decided: pool for
percentages, best for the rest). A tracked drill is run again as a ROUND, not
added twice. `ShootingRun.more` / `TrackedRun.more` = rounds 2…n (optional
JSON key inside the curriculum, written only when present — no schema
change; `entries` stays round 1). `round(i)` is one round as a run of its
own — what the station's cards EDIT (a binding per round; the cards are
unchanged apart from `previousRound`, `previousRoundNumber`, `lockSetup`).
EVERYTHING ELSE reads `result(for:)`, which is the SESSION's: made-of-shots
(and the shot chart) POOL every round spot by spot (the pooled entry carries
its own attempts — `ShootingResult.shots(at:)` honours them in .attempts
mode), so the profile, shot map, "vs last time", ranks and the plan engine
see every shot; timed / time-to-finish / count take the BEST round. Station:
`RoundBar` (ShootingStation.swift — Round 1 | Round 2 | + New round, shown
once a round has results; ⋯ deletes the round on screen; ids `round.<n>`,
`round.add`, `round.more`); in a later round every "last time" compares with
the round BEFORE ("round 1 40%"); the setup is locked once any round has a
result; a round nobody logged in is dropped when the station closes. Plan
line: "Round 2 · 1/2 logged · Group 40% → 80% ↑", and the button reads
"Round N" once everyone is logged in the latest round (opens a new round).
Tests: ShootingTestTests / CustomTrackingTests (rounds),
ShootingAddOnUITests.testASecondRoundComparesWithTheFirst.
THE PLAN'S + (23 Nov 2026, Luther: "let the app open the library straight
after tapping on the plus … select more than one drill at a time … within the
drill detail view, show next to edit and favorite the add to the session
button"). Warm-up / Skills + is a plain button that opens the library picker
(`plan.add.warmup` / `plan.add.skills`); the "From Library / Quick Text" menu
is gone — Quick Text is a LONG PRESS on the +. The picker
(SmartDrillPickerSheet) no longer closes on an add: each tap adds at once, the
button reads "Done · N added" (`drillPicker.done`), and a drill added in THIS
visit can be taken back with a second tap (`Pick.canRemove` / `remove`;
drills already in the plan stay a disabled check). A drill page opened from
the picker gets `drill.addToSession` beside Edit and Favourite (env
`drillSessionPick`). The series and phase pickers still close on one pick.
TRAP: the tracked rows' `library.tracked` identifier overrides the add
button's — find those by label. Test: PlanPickerMultiAddUITests.
ONE EDITOR EVERYWHERE (23 Nov 2026, Luther, markup on a play's step editor:
"use the editor everywhere, it's more complete"). `JournalPlayStepEditor(step:
court:)` — a PLAY's steps — now opens in the BOARD layout too (regular width):
tool rail with the steps tile at its foot (panel: filmstrip, this step's
words, the tool's options, the selection), Offense and Defense docks, ‹ ▶ › +,
Lanes and Annotate in the top bar; Cancel and Done as before; NO court switch
and no Save menu (`BoardActions.showsCourt = false` — the court is the
play's). The inspector layout (side column / under the court) is no longer
reached; its code stays. The phone keeps its layout. Team breakdown page:
"Open in Plays" became "Edit play" (`team.play.edit` — straight into the
editor on the step on screen) + a smaller "Play page" (`team.play.open`).
PLAY SHEET PHOTOS (same day, markup "with photos"): "Players" on the share
sheet shows PHOTOS for everyone who has one (Include photos, on by default);
media consent no longer gates it — the footer says how many have no consent
on record ("fine for the team itself, not for a public post"). REVERSES the
23 Nov "photos only with media consent" rule for play sheets, at his request.
Tests: PlayEditorWorkspaceUITests (rewritten for the board layout),
PlayDefenseUITests (defense dock).
GAME DAY (23 Nov 2026, Luther, markup on the team page: "add a game day card
where I can plan and schedule a game"; decided: the plan holds LINEUP, PLAYS
TO RUN, KEYS TO THE GAME and OPPONENT NOTES; a game is a SESSION — calendar
and Home, attendance never billed, scored live against the opponent).
Models/GamePlan.swift: `SessionType.game` (a new case in the stored raw
string — no schema change), `SessionCurriculum.gamePlan: GamePlan?`
(opponent, isHome, starters in order, keys, opponentNotes — curriculum JSON,
tolerant), the plays in `curriculum.plays`. Created through SessionCreation
like a team practice (group .unassigned, roster = the team's athletes,
curriculum.teamId, title "<team> vs|@ <opponent>"); NEVER BILLED
(redeemPrivateAttendance skips `.game`, SessionPrivacy says not private); not
offered in Add Session's type list (a game is scheduled from its team).
Views/Hub/TeamGameDay.swift: `GameDaySheet` (schedule AND edit: opponent,
home/away, tip-off, length, venue; lineup = tap a player to start, in tap
order; plays from the team's playbook; keys; opponent notes; Delete this
game) — an edit writes onto the STORED session through updateSessionEvent.
Team page GAME DAY block (TeamScreens.gameDayBlock, above Practices, which no
longer lists games): NEXT GAME (vs, when, where, starters' photos, counts,
Plan | Open), other upcoming and played games with their result, "Schedule a
game". Session page: opens on Plan with `SessionGamePlanCard` on top (score,
starters with names, bench count, keys, opponent, Edit); the Games tab's
button is "Start the game" / "Next period" and makes a two-team game —
OUR team (id = the Team's id; the plan's starters who are present first, then
the bench; `starters` set) against THE OPPONENT (`GamePlan.opponentTeamId`,
a fixed id, no players). LiveTeamPanel shows a team with no players as a
SCORE PAD (+1 +2 +3, Take 1 back — writes teamScores directly, not in the
Undo log). `GameDay.score(of:)` adds every period played (clock ran, or
anyone scored): "W 34–28" once every period is ended. Ours are scored as in
any game, so the athletes' game stats and chemistry include it.
ON THE CALENDAR (same day, Luther, markup: "game icon and color should be
different" — the row read Group, blue, two people): `SessionFormat.game`
(checkered flag, gold `AppTheme.amber`, "Game" / 比赛), answered first by
`SessionPrivacy.format` for a `.game` session, so the day row's icon, bar
and badge, the day dots and every FormatBadge follow; the Game Day block and
Home's type tint use the same gold (red is a cancelled class).
NOT YET: the live screen's own button still says "Next Game"; no
quarter/foul/time-out tracking; the plan is not on a printable sheet.
Tests: GameDayTests, GameDayUITests (iPad mini; creates and deletes its team).
THE GAME'S PLAN PAGE (24 Nov 2026, Luther, markup on a game's Plan tab: "how
can we make the plan page for games actually useful? Plan balance, warmup and
skills is actually useless here"; decided: lineup and rotation with PLANNED
SUBS, calls by situation, opponent and matchups, a short pre-game warm-up
routine, a printable game sheet now; form / after-the-game review not chosen).
On a `.game` session the Plan tab has NO Plan Balance and NO Skills block. In
order: the game card (opponent, score, Game sheet, Edit, KEYS large) →
LINEUP AND ROTATION (`game.lineup`: starters and bench with photos and names,
"Not here" once roll call started and they are not present, planned subs
`game.sub`) beside THE OPPONENT (`game.opponent`: notes, their players with
number, note and who guards them — `game.threat`; side by side from 700 pt)
→ CALLS (the plays card in `calls:` mode — SessionPlanPlaysSection.Calls:
the defense line `game.calls.defense`, plays grouped by the team playbook's
situations via `GameCalls.groups`, plays outside the playbook under "Other
plays"; no move up/down there) → PRE-GAME WARM-UP (curriculum.warmupDrillIds,
no minutes chip). GamePlan gained `subs: [PlannedSub]` (in, out or nil =
whoever needs a rest, when as the coach's words), `defense: GameDefense?`
(man, 2-3, 3-2, press, mixed) + `defenseNote`, `threats: [OpponentPlayer]`
(number, note, guardedBy) — curriculum JSON, written only when used, an
unknown defense reads as unset; `validSubs(roster:)` drops a sub whose player
now starts or left. All edited in GameDaySheet (Rotation, Our defense, Their
players and matchups). THE LIVE SCREEN PROMPTS THE PLANNED SUBS (same day,
Luther): LiveTeamPanel(plannedSubs:period:elapsedSeconds:) lists the open
ones above the bench (`live.planned`, chip `live.planned.sub`: tap makes the
sub — asks "in for…" when no one is named or that player is off the floor —
✕ `live.planned.skip` drops it). `PlannedSub.period` / `.minute` (optional,
set in the editor's "Prompt" pickers): with a minute the chip turns ORANGE
"NOW" and the panel buzzes when that period's clock (counting up) gets
there; a period alone is due from its start; an earlier period's unmade sub
is overdue; neither = listed, never "due". `PlannedSubPrompts.pending`
(pure): not done, this period's, the player still on the bench, due first.
Done / skipped ids ride in `SessionGame.plannedSubsDone` (games JSON,
optional) and carry to the next period (startTeamGamePeriod, Next Game); any
substitution that brings the player on answers their planned subs. Period =
the game's place in the session's games. On a PHONE the prompt is on our
team's panel only (one team on screen at a time). GAME SHEET (Views/Hub/GameSheetDocument.swift,
`gameDay.sheet` → GameSheetShareSheet: preview, PDF / Image / Print): one A4
page, names only, a SwiftUI page drawn by ImageRenderer into the PDF context
(text stays text) — starters, bench, planned subs, warm-up | keys, defense,
calls, opponent and matchups, then ruled NOTES; language = Exported PDFs.
Tests: GameDayTests, GameDayUITests (iPad mini).
A PLAYER ON A TEAM (23 Nov 2026, Luther, markup on the roster's player page:
"make this page better — useful, complete, expressive … add a scheduler, for
example a session to have the athlete work on the skills he'll need for his
position. Also a way to export plays focused on him"). `TeamWorkoutView`
moved to Views/Hub/TeamPlayerPage.swift and is rebuilt: a team-colour header
(photo, names, tiles Roles · Plays · Drills · Minutes), Schedule a workout |
Export plays, SKILLS NEEDED (chips, ×n when several roles ask), ROLES (the
play's thumbnail, role number, its standard, its skills → the breakdown),
WORKOUT (numbered drills with minutes and the roles they are for → the drill),
POSITION WORKOUTS already scheduled. `TeamPlaybook.playerRoles(of:)` /
`skills(of:)`. SCHEDULE (`PositionWorkoutSheet`): when, length, venue, which
of the drills, "Include the plays" → a TEAM session (type .teamPractice,
curriculum.teamId — NEVER BILLED) with ONLY that athlete on its roster, the
drills as Skills, the plays in the plan, titled "<name> · Position workout";
found again as teamId + attendeeIds == [player]. Athletes only (a coach on
the team gets no schedule button). EXPORT (`PlayerPlaysShareSheet`): every
play the player has a role in as a PLAYER SHEET followed from that role, in
ONE PDF / long image / print (PlaySheetDocument.pdf with one sheet a play;
the player is forced onto their role in the cast); Faces on the court;
Defenders asked each time. App wording there is NEUTRAL (no he / his — the
first draft said "his" on a girl's page). FIXED with it: a FULL-COURT play
sheet laid three 75 mm courts across A4 — wider than the page, the outer two
cut off; `PlaySheetDocument.columns` now takes as many as fit (two on A4).
Tests: TeamsUITests (the page, export preview, schedule and delete).
THE EVALUATION READS CALMLY (24 Nov 2026, Luther, markup on the Quick Peep:
the evidence lines between the bars "create chaos"). The eight ratings are an
even column with NOTHING between the rows; a suggested rating is a short
orange tick across its bar. Every game stat, tracked-shooting line,
custom-drill standing and "Results suggest N · Use" sits in ONE block under
the ratings, "FROM GAMES AND DRILLS": skill (short name, once) | icon | text,
aligned (`evidenceRows` / `evidenceBlock`). Also fixed: the Coach Insights
title was white on its yellow card in dark mode. DEBUG HOOPWISE_PEEP=games
(the athlete with the most games) and HOOPWISE_PEEP_SAMPLE_EVIDENCE=1 (sample
lines — the demo store has nobody with three games) on quickPeep.
THE PEEP GROWS (24 Nov 2026, Luther: "holding the handle and pulling upwards
extend the page into a full screen"; then "extend into full screen … the
empty side left and right could be used to show more … pulled down to a peep,
and pull down to disappear"). `.quickPeep(item:)` (StudentQuickPeepView.swift)
on both places that open it (session roster, Home). COMPACT (iPhone): the
system sheet, detents 62 % / large, handle visible, content scrolls without
resizing (`quickPeepPresentation`). REGULAR (iPad, Mac): a system sheet can
grow taller but never wider, so `QuickPeepStage` over a clear fullScreenCover
(presented without the cover's slide; the stage animates itself): a centred
peep ≤ 720 pt wide, 62 % high, with a handle (`peep.handle`); dragging it
interpolates width and height up to the WHOLE screen (`peep.stage.full`);
release above halfway = full, else peep, below 55 % of the peep = gone; a tap
on the handle toggles; tap outside, Done (env `peepClose`) or the drag down
closes it. The page's layout follows its OWN width (onGeometryChange): < 700
one column, ≥ 700 card | the rest, ≥ 1100 three columns (card | evaluation +
results | notes, insights, reminders, contract). TWO COLUMNS (same day,
Luther, markup "use this space too"): left = card, Skills Evaluation, coach
notes, About; right = shooting, tracked drills, insights, reminders, contract.
SMOOTH (23 Nov 2026, Luther on build 71: opening, growing and a slow drag
"lagging behind my finger"): the stage resized the page with the finger, so
the whole heavy page re-laid out (and its body re-ran — the width was @State)
every frame, crossed column layouts mid-drag, and on opening was built twice
(two columns, then one once measured). Now the page has TWO layouts only —
peep width or screen width (`pageFull`, handed down as env `peepLayoutWidth`,
so the first draw is the right one) — and a drag only moves, clips and SCALES
it (full layout shrinking: scaled; peep growing: margins); it reflows ONCE on
release, unanimated, and the panel glides from the next run-loop pass. The
page stores a column COUNT, not its width. Never size the peep's page from a
drag again. Tests: QuickPeepSheetUITests
(iPad mini, sessionPage Attend tab; skips on a phone). Not checked on the Mac.

## Drill attributes, the plan dashboard and phase balance (11 Nov 2026, Luther)
"Give drills an attribute … a hex graph in each drill … the session plan
becomes a dashboard … feeds back into the program." Decided: 8 axes, ship
Claude's ratings without review, target = BOTH phase focus and program goals.
- Models/DrillAttributes.swift: `DrillAttribute` (ballHandling, passing,
  shooting, finishing, playmaking, gameIQ — vision merged in —, defense,
  footwork & athleticism) and `AttributeProfile` (0–3 per axis: none ·
  touched · worked · main). `DrillItem.attributes` resolves: the drill's own
  `attr:<axis>=<n>` tags (coach override, marked `attr:by:coach`, or Claude's
  rating of a personal drill) → the library rating → a guess from type /
  category. No schema change (tags sync). syncActivityLibrary keeps attr:
  tags when it refreshes a library drill. Mappings put TrainingFocus,
  ActivityType skills and ProgramSkillTargets on the same axes.
- LIBRARY RATINGS: Models/ActivityLibraryAttributes.swift is GENERATED —
  all 422 plannable activities rated by claude-sonnet-5 (Services/
  DrillRater.swift, rubric `DrillAttribute.rubric`) through DEBUG
  HOOPWISE_SHOT=rateLibrary on the Mac demo copy (Keychain key; logs "rate
  <key>|<scores>" to hoopwise.mac / rater; HOOPWISE_RATE_MISSING=1,
  _BATCH=n, _ONLY=n) and tools/attributes/merge.py. Large batches sometimes
  come back unusable — re-run MISSING with small batches. Don't hand-edit.
- PERSONAL DRILLS: DrillWriter's Return answer now includes `attributes`;
  New/Edit Drill saves them as attr: tags unless the coach rated the drill.
- DRILL PAGE: DrillAttributesCard (Views/Components/AttributeOctagon.swift)
  after the description — octagon, main axes as ●●○, "Also:", source
  (Rated by Claude / Adjusted by you / Estimated); Adjust = 8 segmented
  rows (None · Touched · Worked · Main), Save writes coach tags, "Go back to
  Claude's rating" removes them.
- PLAN DASHBOARD: SessionPlanDashboard (Views/Coaching/) at the top of every
  session's Plan: `PlanCoverage.minutes` (Services/PlanCoverage.swift, pure)
  weighs each drill's scores by its share of its block's minutes (plays = a
  10-minute item shaped by their team breakdown skills, else IQ/create/pass);
  octagon = emphasis (scaled to the top axis) against a TARGET
  (`PlanCoverage.target`: phase focus + program skill targets when set; a
  team practice: its focus plays' skills); "Leans on" (≥ 0.6, with
  minutes); "Neglected" = target ≥ 0.6 and target − plan ≥ 0.4, each with
  Find drills → the library picker (`Pick.attribute`) opening on "Strong on
  <axis>" (score ≥ 2 at the chosen ages, any block, strongest first).
- PROGRAM: PhaseCoverageCard on the program page (under the phases) — one
  phase at a time (current first, menu to switch): all its sessions' plans
  vs the same target, "N of M sessions planned", neglected axes. Generate
  Plan reads the same gap: `DrillPlanGenerator.phaseGaps` (target − what the
  phase's other plans cover) adds 2 × gap × score/3 to each candidate; the
  rationale says "fills the phase's gaps: …".
- THE LOOK (12 Nov 2026, Luther: the first chart "looks more like a bug
  than a chart"): hairline grid (0.5 pt) on a faint base, the plan as ONE
  1.75 pt stroke with a soft gradient fill and 5 pt vertex dots, every shape
  floored at a 0.12 ring (a zero pulled the outline into the centre and
  drew spikes), the TARGET as a short rounded TICK across each spoke it
  asks for (≥ 0.45; orange when neglected) — a dashed outline of a sparse
  target drew a star — and corner labels anchored outward so the outline
  never runs into them.
- LAYOUT: every octagon card goes through `OctagonCardLayout` — words
  beside the chart from 520 pt wide, UNDER it when narrower (on a phone the
  side column broke words mid-word: "De-fense", Luther 12 Nov 2026).
  LABEL ROOM (14 Nov 2026, Luther: "Defend" clipped at the card edge): a
  labelled octagon leaves 48 pt each side and 22 pt top/bottom INSIDE its
  frame for the corner labels, and is no longer forced square — frames are
  wider than tall (plan 240×190, drill 250×190, phase 230×170). An EMPTY plan
  shows a small centred chart (240×150) with its line under it, not the
  side-by-side layout.
- DEBUG: HOOPWISE_SHOT=planDashboard (a generated plan in memory, Plan tab;
  + HOOPWISE_PLAN_TARGET=1 shows the dashboard alone against Defense +
  Passing). Tests: DrillAttributesTests (all 422 rated, tags, guesses,
  minutes, neglect, both targets), DrillAttributesUITests (drill page Adjust
  → back; program phase balance — it launches twice: the first launch of a
  UI test run has come up without its environment on the iPad mini sim).

## Evaluation · plan balance · games — one system (17 Nov 2026, Luther)
"Make sure the student oct evaluation, the session's oct planning balance,
and the game stats can work together." Decided: keep 1–10, START FRESH.
- THE EVALUATION IS THE EIGHT OCTAGON SKILLS: `SkillsEvaluation.axes`
  ([DrillAttribute.rawValue: 1–10] inside the existing skillsData JSON — no
  schema change); `rating` / `setRating` (clamped) / `isEvaluated` /
  `axisAverage` / `axisShares`. The old six fields (scoring…intangibles)
  still decode and round-trip but NOTHING reads them — an old evaluation
  reads as "not evaluated". Quick Peep's Skills Evaluation = 8 rows, "—"
  unrated, Evaluate / Edit (unrated start at 5) / Save (`peep.evaluate`).
- GAME EVIDENCE beside each skill (Services/SkillEvidence.swift, pure):
  games never SET a rating. ≥ 3 games; shooting = PTS/game, finishing =
  share of own baskets off a pass, playmaking = assists per own basket (both
  need ≥ 5 logged baskets), passing = AST/game, defense = STL+BLK/game,
  ranked among program-mates ("1.4 AST/game · 2nd of 12"). Ball handling,
  Game IQ and Footwork have no stat; rebounds claim no skill.
- PLAN BALANCE FIX: `PlanCoverage.minutes` no longer counts the Game block —
  the Plan tab shows no Game section, so the dashboard's minutes exceeded
  the visible plan. SECOND HALF (18 Nov 2026, Luther: "still got wrong
  numbers here" — "Ball handling ~50 min" on blocks reading 24 + 10 min):
  each drill now counts for ITS OWN durationMinutes, the very numbers each
  block's header adds up (`sectionDuration`); the stored warmupMinutes /
  skillsMinutes (set at generation, never shown) are no longer shared out.
  No axis can exceed the visible plan (+ 10 per play). Test:
  SkillIntegrationTests.testMinutesNeverExceedWhatThePlanShows. The TARGET now adds the GROUP'S WEAK SKILLS
  (`groupRatings` = per-skill average of the expected athletes who were
  rated; average ≤ 5 → target 0.6 + (5 − avg) × 0.08, `groupWeakness`); the
  dashboard says "Group's weakest: Shooting (avg 4.1)" (`plan.groupWeakest`).
- PLAN ENGINE: the level suggestion and the weakest-area focus read the
  eight skills (`groupRatings`, `activityTypes(for:)`); `phaseGaps` uses the
  same target; a DEFENSE signal joins passing — under one steal/block per
  three player-games over ≥ 3 games and ≥ 15 lines (`defenseSignal`). The
  rationale line now SHOWS its notes (`PlanRationale.readable` — before,
  notes, including "fills the phase's gaps", were computed and never shown).
- THE CARD'S SECOND LINE: the player card's back octagon draws the
  evaluation (`AthleteCardFacts.evaluation` = axisShares) as a dashed black
  line over "what we worked on", legend "Worked on / Where they stand"; only
  rated skills. In the app, the shared image and the A3 sheets alike.
  (Asked Luther whether parents should see it; shown until he says.)
Tests: SkillIntegrationTests, PlanGeneratorTests.

## After the audit (25 Nov 2026, Luther: "build all of them, in that order")
The audit of 24 Nov found: ratings without history, no per-athlete focus, no
progress report, nothing noticing an athlete outgrowing a program, fields
stored and never shown, two rating systems, ~7,500 lines never opened.
1. EVALUATION HISTORY. `SkillsEvaluation.history: [EvaluationSnapshot]`
   (date + the eight ratings; inside skillsData JSON, written only when it
   has entries — no schema change). THE writer is
   `recordEvaluation(replacing:at:)`, called by the Quick Peep's saveSkills:
   the evaluation being replaced becomes the first entry when there was no
   history; two evaluations on one day are one; an unchanged save adds
   nothing; 60 kept. `baseline` (first, once there are two), `change(axis)`,
   `series(axis)`, `rating(_:asOf:)`. Quick Peep: a grey mark on each bar
   where the first evaluation stood and "+2" / "−1" beside the rating; the
   footer says how many evaluations and since when. Profile: SkillGrowthCard
   (Views/Components — `athlete.skillGrowth`: per skill a sparkline, "4 → 6",
   the change; `SkillGrowthRow.rows`, pure). Tests: EvaluationHistoryTests.
   Not looked at on screen.

## Coach board (17 Nov 2026, Luther)
"Half or full court … the full play editor with every feature, including
Scribble. Not cleared when I leave … save as play or skill in the corner …
I hit Clear myself." Then, the same night: "land directly in the editor in
full screen with only the tool bar on the side and steps at the bottom left
tucked into a button." Hub → Coach board (the third PEOPLE tile on a wide
screen, a wide tile on the phone; glyph `.board`) opens a FULL-SCREEN COVER
that IS the step editor in BOARD MODE (`JournalPlayStepEditor(drawing:
onChange:board:onSave:)`, `BoardActions`): tool rail | court, no inspector;
a glass "Step N of M ⌃" button at the bottom left opens a popover with the
steps strip, this step's words, defense, the tool's options and the
selection. Top bar: Court (Half/Full — converts the steps and rebuilds the
editor), Clear (asks; `board.confirmClear`), Save ▾ — Save as Play
(JournalNewPlaySheet(drawing:) → the concept's steps, cones dropped —
`JournalPlay.fill`) / Save as Drill (AddDrillView(drawing:) — the drawing is
the new drill's first visual); Done closes. No Cancel: `onChange` reports
every change and Views/Hub/CoachBoardScreen.swift saves it at once to a
DEVICE-LOCAL file (Application Support/CoachBoard/board.json,
`CoachBoardStore`) — a scratchpad; syncing would need a schema field.
Saving leaves the board as it is. BOTTOM RIGHT (same night, Luther: "remove
the play button … a bar in the lower right corner with previous step, play
and next step … play right there", "add the scribble functionality too"):
a glass bar — Scribble (iPad only) · ‹ · ▶/❚❚ · › (`board.scribble`,
`board.previous`, `board.play`, `board.next`). ▶ swaps the editable court
for the step player IN PLACE (`boardStage` — JournalPlayStepPlayer `bare`:
court only, driven by `scribbling` / `playToken`, reporting
`onPlayingChange`), playing from this step on; when it ends the court is
editable again. Scribble keeps the player on with Scribble on (ink, reading,
Reset ink) until switched off or a tool is picked; never saved, as on the
play page. ‹ › move between steps. The Watch button and its popup are gone.
A + at the bar's end (18 Nov 2026, Luther: "a plus button besides the next
button to add a new step quick") adds a step after this one and shows it
(`board.addStep`); its words go in the bottom-left steps panel.
DRILL DRAWINGS USE THIS EDITOR (19 Nov 2026, Luther: "adding a drawing to a
drill should use the general play editor like the one accessed in the hub,
not the halfcourt set editor"): the drill page's Add / Edit and New Drill's
"Draw on the court" open `DrillDrawingEditor` (Views/Drills/) — the board
layout titled "Drill drawing", Court + Clear in the top bar (no Save menu;
`BoardActions` clear/save are optional), Cancel + Done kept (a court change
rebuilds the editor and `edited` keeps Cancel asking). HOOPWISE_SHOT=
drillDrawingEditor.
ADDED TO THE BOARD'S EDITOR (19 Nov 2026, Luther), board and drill drawings:
· LANES — the top bar's Lanes button draws four dashed lines splitting the
  floor's width into five lanes, on every step (`JournalPlayDiagram.lanes`,
  written only when on; shown wherever the step is drawn; next steps keep it).
· DEFENDERS CUT — the Cut tool starts from a hand-drawn defender too: the
  line's `player` is −(index + 1) (`defenderActor` / `defenderIndex`), so the
  format is unchanged and older builds leave it unplayed. Only cuts, only
  while the defense is By hand (auto defense drops those lines). Playback
  moves him (`PlayFrame.defense`), the next step starts him at the end,
  dragging him takes his line's start, deleting one renumbers the others'
  lines (`removing(defender:)`). The inspector calls it "A defender's cut".
· ANNOTATIONS — Annotate (top bar menu): free ink over the court (finger,
  Pencil, pointer; each stroke one undo step) with a floating palette — Pen
  (red, white, yellow, blue, green) or a thick translucent Highlighter
  (yellow, green, pink, blue, orange), remembered per device
  (`plays.annotate.*`). KEPT only when "Keep annotations" is on (device
  setting `plays.keepAnnotations`, off): `JournalPlayDiagram.ink` = the
  PencilKit drawing at `inkScale` (40) points a metre of the court drawing,
  so it lands on the same spot at any size (`PlayInkImages`); off, Done /
  the board's autosave drop it. A new step starts without ink. "Clear this
  step's annotations". DEBUG HOOPWISE_BOARD_ANNOTATE=1 opens annotating.
  The simulator's synthetic touches draw near-invisible pen strokes (no
  touch size); the highlighter shows — real fingers/Pencil need a device.
Tests: BoardDrawingExtrasTests, BoardExtrasUITests (iPad mini).
ON THE PHONE (23 Nov 2026, found fixing DrillVisualUITests): the board
layout's top-bar controls (Court, Lanes, Annotate, Clear, Save) as a row
pushed DONE into the iPhone's overflow "•••" — in the drill-drawing editor
and the Coach board alike. In compact width they are now ONE menu at the top
left (`board.more`, "More"), so Cancel, undo, redo and Done stay in sight;
the iPad / Mac keep the row. DrillVisualUITests run again: the first drill
row sits under the skill chips, filters and nine Tracked shooting rows, so
`firstLibraryRow()` scrolls to it; the test starts by deleting drawings an
earlier failed run left on that demo drill (on a phone the page shows ONE
drawing at a time); steps are added by the board's + (iPad) or the phone
bar's "+ Add a step" tapped directly; the phone test puts the keyboard away
(Return) before scrolling the New Drill form, and skips on an iPad (it draws
in the board editor there).
CLEAR WIPES IT, STEPS IN THE RAIL, OFFENSE PRESETS (22 Nov 2026, Luther,
markup: Clear "is not functioning as intended … it should wipe the board
clean"; "move [Step] in the side bar and replace it with offense option &
preset"). Clear put the default five back (`DrillDrawing.new`); it now
leaves `DrillDrawing.empty` — one step, nobody on it — on the board AND in
drill drawings, and a new board starts empty (a new drill drawing still
starts on the five). `CoachBoardStore.isBlank` = an untouched empty court
or the five. The Step button is a 40 pt tile at the FOOT of the tool rail
("2/3" under a stack; same id `plays.editor.steps`; the panel opens beside
it). Bottom left is the OFFENSE DOCK (`plays.editor.offenseDock`, saying
the set on screen — `OffensePresets.matching` — else "Offense"): a panel
upward of presets 5v5 → 1v1, each a small court (`plays.editor.preset.<id>`;
a plain Grid — a lazy one left the lower tiles unbuilt): 5-Out (= the
default alignment exactly), 4-Out 1-In, Horns, 1-4 High, 1-4 Low, Box,
1-3-1 · 4-Out, 3-Out 1-In · 3-Out, 2-Out 1-In · Top and wing, Wing and post
· 1v1 at the top. Models/JournalPlays/OffensePresets.swift (pure, half-court
metres, converted to the attacked end of a full court). A tap
(`JournalPlayMath.applying`, one undo step) puts the set on THIS step: 1 with
the ball, the step's lines gone (drawn from the old spots), cones / lanes /
notes / ink kept, an auto defense re-matched one per attacker (by hand:
kept). Opening one dock closes the other. Tests: OffensePresetsTests,
CoachBoardUITests.testClearWipesTheCourtAndPresetsSetItUp (the ball-rule and
dock tests put 5-Out on after their Clear).
HOOPWISE_SHOT=coachBoard. Tests: CoachBoardUITests (opens in the editor,
draw, steps button, relaunch → still there, Save → Play/Drill, Clear; full
court upright; ball rule + play in place), SkillIntegrationTests.

## Team plays: faces, follow a player, play sheets (23 Nov 2026, Luther)
"When I'm using a play in a team practice or team option in the hub, let me
have the choice of having either numbers or bubble pictures on the play … share
a play to the team … share a play to a player: this highlights what that player
does … as PDF or printed. The quality of the export matters." Decided: A4,
defenders asked EACH TIME, names on paper by default, photos only with media
consent.
- ON SCREEN (Views/Plays/TeamPlaySharing.swift): where a play is opened FROM A
  TEAM — the breakdown page (PlayBreakdownView), the play page opened from it,
  a team practice's plan plays (`JournalPlayScreen(teamId:)`,
  `SessionPlanPlaysSection(teamId:)` = curriculum.teamId) — `TeamPlayCastBar`
  sits over the court: Numbers | Players (device-local per team,
  `team.play.people.<team>`), Share, and a chip per role (photo, name, role
  badge) that FOLLOWS that player; a role with several players is a Menu
  (tap follows, the menu picks who is on — `team.play.lineup.<team>.<play>`).
- THE COURT (JournalPlayDiagramView) reads three environment values
  (Views/Plays/PlayBubbles.swift): `playBubbles` (number → photo or initials,
  role number as a badge; the skill-level backdrop behind a cut-out),
  `playFocus` (the followed player's lines bold ORANGE `PlayFocusStyle.color`,
  a pass to them orange, every other line, player and defender faint grey, only
  their end spot), `playHidesDefense`. One drawing for the page, playback and
  paper. Who plays a role = the team's PlayBreakdown (`DataManager.
  teamPlayCast`); a play not broken down shows numbers.
- PLAY SHEETS (Views/Plays/PlaySheetDocument.swift): A4 portrait, VECTOR —
  each court is JournalPlayDiagramView drawn by ImageRenderer straight into
  the UIGraphicsPDFRenderer context (y flipped; Canvas paths and text stay
  vector — the courts' letters are selectable text in the PDF; only a photo
  is a bitmap). Header: team-colour rule, eyebrow (TEAM PLAY SHEET / PLAYER
  SHEET · name · ROLE n), play name, category · court · steps · options,
  When, The idea; ROLES key (team) or "Your role" box with the role's standard
  and drills (player); a grid of steps — half court two across, full court
  (upright) three across, the court as wide as lets the part take the FEWEST
  pages and never under 75 mm; caption over each court, its words under it,
  and on a player sheet "Your job: …" worded from the drawing by
  Models/JournalPlays/PlayRoleJob.swift (cut / dribble / pass / hand-off /
  shot / screen for whom / catch from whom, spots named "the left wing", "the
  right elbow", "the top"…; nothing drawn = "Stay at …"; bilingual, pure);
  each wrinkle / variation from a new page; footer = the line legend (+ "Your
  moves" on a player sheet), academy, page n of m. Long image for WeChat =
  the pages stacked (1242 px JPEG). Language: Languages by Area → Exported
  PDFs.
- SHARE SHEET (`PlaySheetShareSheet`): the first page as a live preview on
  top; For: the team / one role's player / sheets for everyone (one PDF, a
  page set per player); On the court: Numbers | Players, "Include photos"
  only when someone has a photo AND recorded publication consent
  (`mayPublishMedia`; staff coaches count as consenting) — the others print
  as initials; Defenders Show | Hide with NO default (PDF / Print / Image stay
  disabled until answered). Actions in a fixed bottom bar. Print =
  UIPrintInteractionController.
- DEBUG: HOOPWISE_SHOT=teamPlay (+ HOOPWISE_TEAMPLAY_PEOPLE=1,
  HOOPWISE_TEAMPLAY_FOLLOW=<n>) and =playSheet (+ HOOPWISE_PLAYSHEET_EXPORT=
  team|player|everyone, HOOPWISE_PLAYSHEET_DEFENSE=0 → playsheet.pdf +
  playsheet.jpg in the App Group Library/Caches). Tests: PlaySheetTests
  (jobs, spots, consent, A4, pages, text is text), TeamPlaySharingUITests.
- NEXT (agreed, not built): a BOOKLET — every play of a playbook section or
  the focus plays in one PDF.

## The ball rule (17 Nov 2026, Luther)
"A pass can only be drawn from a player with a ball, otherwise nothing is
drawn; a dribble same." In the step editor (every play and drill, not only
the board) a PASS, DRIBBLE, SHOT or HAND-OFF starts only from a player who
holds a ball at that point of the step — at the start or after the passes
already drawn (`JournalPlayMath.ballsAfter`); `JournalPlayStepEditor.
mayStart` is the test, checked when the stroke begins (and for the hover
ring). Cuts and screens need none. Scribble applies it to passes and
dribbles (the strokes stay ink). The connector's authoring is unchanged (a
pass without a ball still saves with a warning there). Tests:
JournalPlayScribbleTests.onlyAPlayerWithTheBallPassesOrDribbles.
THE STEPS PANEL REDESIGNED (same night, Luther: "the steps bottom tab is not
so well designed"): one header line — "STEPS  2 of 3", then move (menu) and
delete as one small capsule (shown with two or more steps;
`plays.editor.deleteStep`) — over a FILMSTRIP: each step a 104 × 74 drawing
with its number on it and its caption under, the one on screen ringed in
the accent, "+ Add a step" as the strip's last, dashed frame
(`plays.editor.addStep`). The ‹ › buttons are gone (tap a frame); ⌘[ ⌘]
still step through (hidden buttons, `stepKeys`). Used under the court
(upright) and in the board's popover; the side column keeps rows with the
same header and a dashed "+ Add a step" row. The phone's steps bar is
unchanged.

## Editor tools redrawn (18 Nov 2026, Luther: "revamp how the tools look … the same quality as a modern design software … simple but precise")
Views/Plays/EditorToolGlyph.swift draws every tool icon — rail, phone grid
and Pencil palette (`icon(_:)` is the one entry): one unit grid, one stroke
(1/12 of the side, ≥ 1.5 pt), round caps, ONE filled dart arrowhead for
every line tool, every line on the same diagonal; monochrome (pointer,
cut, dribble zigzag, dashed pass, hand-off bars, shot into a rim, screen T,
player ring with 1, defender X, seamed ball, banded cone, eraser). The RAIL:
56 pt, 40 pt tiles corner 10 (continuous) on 4 pt spacing, the tool in use
an ACCENT tile with a white glyph and a soft accent shadow, hover a faint
fill, hairline group dividers and a hairline rail edge; the hover tooltip
shows the name AND its key (a small keycap). Identifiers unchanged
(`plays.editor.tool.<tool>`).
COLOUR (same night, Luther: "I love the new icon looks … color the shoot to
the basket red and the circle around the offensive player blue"): the shot's
line is JPalette.shot and the player ring JPalette.play (`colored`, off on
the selected accent tile, where the glyph is white).
DRAWING DETAILS (same night): (1) a ball IN FLIGHT (pass, shot) or resting
at the rim is drawn ON its line — only a held ball sits on its holder's
shoulder (it was offset by 0.78 r even mid-flight: "the ball travels too
far off the drawn line"); playback already moved it along the drawn path.
(2) A SCREEN's T stands just past the screener's circle where he ends (end
+ r + 2 widths along the run, a stem to it), and it is drawn AFTER the
players (`ScreenPart`: line under, mark over), so it reads even when set
against a teammate ("the screener is literally over the sign").

## The full court is drawn UPRIGHT (17 Nov 2026, Luther: "full court should be vertical")
Attacking UP, the attacked basket at the top like the half court's baseline,
everywhere a play is drawn (editor, board, play page, study, thumbnails,
drill drawings). ONLY THE DRAWING TURNS: stored metres keep x along the floor
(0…28, attacking +x) and y across (0…15), so saved plays, the connector's
format and guide, defense, playback and Scribble's reading are unchanged.
`JournalPlayCourt.isUpright` / `turn` (x' = y, y' = 28 − x) / `drawnSize`;
every court ↔ screen conversion is `JournalPlayCourt.point(_:scale:court:)`
and `courtPoint(_:scale:court:)` (the editor's `metres`/`viewPoint`, the ink
layer and Scribble all use them) — never add a raw `(p.x + margin) * s`.
Arrow keys move the selection the way they point on screen
(`nudgeOnScreen`). Pinned by CoachBoardUITests.testTheFullCourtStandsUpright.

## Languages by area (17 Nov 2026, Luther)
Profile → Preferences → Languages by Area (AreaLanguageSettingsView):
Exported PDFs (the Parent Guide PDF and long image), Player card (app,
image, A3 — names, words, octagon labels), Game recap —
each Same as app / English / 中文 (Models/AreaLanguage.swift, UserDefaults
`language.area.<area>`, nonisolated — it reads `app_language` directly).
The roll-call photo is ALWAYS Chinese (removed from this list 19 Nov 2026). Statement and
agreement PDFs are bilingual by design and unchanged.
`Student.primaryName(chinese:)` / `secondaryName(chinese:)`,
`DrillAttribute.title(chinese:)` / `short(chinese:)` serve a page with its
own language.

## Small moves (17 Nov 2026, Luther)
- "ALL PRESENT" left the roster: it is in the session page's ⋯ menu
  (`session.more` → `attendance.allPresent`), same confirmation, attached to
  the page so it opens from any tab.
- The Quick Peep always shows its REMINDERS card with the add line (it hid
  when empty), so a reminder can be added from the peep.
- (18 Nov 2026, Luther) The program page's PHASES header has MANAGE beside
  + Add (`program.managePhases` → PhasesListView: reorder, multi-delete; it
  was only in the ⋯ menu). Its ATHLETES card shows the WHOLE roster (it
  stopped at six behind "View all"). The drill page's Tags hide the skill
  ratings (`attr:…`, `attr:by:coach`) and `by:` — bookkeeping shown as
  "Attr:Passing=3" chips; the ratings live on the octagon card.
- EDIT PHASE (18 Nov 2026, Luther: tapping a phase in Manage Phases showed
  "nothing to be modified" — it opened a read-only stub, MicroCycleDetailView,
  now DELETED). Manage Phases' rows open the program page's own phase page
  (FlightyMicroCycleDetailView, which now reads the STORED phase so edits show
  at once) and its toolbar has Edit Phase (`phase.edit`) → EditPhaseSheet
  (Views/Coaching/): name, what it is about, focus areas (Generate Plan and
  the phase balance read them), objectives; saved on a COPY through
  updateMicroCycle (the 2.7 words guard). Dates stay with the chain — Manage
  Phases' drag re-anchors them and moves the sessions inside. Tests:
  EditPhaseUITests.
- DRILLS IN THIS PHASE (18 Nov 2026, Luther: "remove planned drills from all
  sessions or some within the phase, add a recurring exercise to all or a
  select number of sessions"). Edit Phase's second section lists every drill
  in the phase's UPCOMING sessions with "In N of M upcoming sessions"; a tap
  → PhaseDrillChooser (Remove: the sessions holding it, all preselected); "+
  Add a recurring drill" → the library picker → the chooser (Warm-up |
  Skills, the sessions without it, all preselected). Applies AT ONCE (the
  name/focus/objectives still wait for Save). Services/PhaseDrillEditing.
  swift (pure): `editableSessions` (this phase, .scheduled, not didNotHappen,
  start in the future — completed/live/skipped keep their plan as the
  record), `usage`, `removing` (both blocks), `adding` (end of the block;
  never doubled — a drill already in either block is left alone). Writes
  re-read the STORED session and go through updateSessionEvent
  (keepLiveFields). Tests: PhaseDrillEditingTests, EditPhaseUITests.
  testARecurringDrillGoesInAndComesOut.
  EDIT PHASE LAYOUT REVISITED (18 Nov 2026, Luther: "the UI for edit phase is
  worth revisiting"): a page-sized sheet (`presentationSizing(.page)`), in
  order: HEADER (PHASE N pill, "dates · N wks · N upcoming", the name as a
  large field, the summary under it, the dates note as footer) → DRILLS IN
  THIS PHASE (each row: name, a Warm-up/Skills tag, a DOT STRIP — one dot
  per upcoming session, filled where the drill is planned — and "4/6", the
  red minus; "+ Add a recurring drill" in bold) → FOCUS as toggle CHIPS in a
  FlowLayout (accent when on; `phase.focus.<raw>`) — eight full rows were
  most of the form → OBJECTIVES numbered in accent circles.
- DRILL SERIES (18 Nov 2026, Luther: "series or evolutions of drills …
  increasing level of difficulty … when planning a phase … spread the
  exercises per session with progression from easy to hard"). Models/
  DrillSeries.swift: a series = an ORDERED LIST OF DRILLS (each level a whole
  drill — drawing, minutes, ratings; library drills allowed), stored with NO
  SCHEMA CHANGE as one personal SDDrill tagged `kind:series`, levels in tags
  `series.level:<n>=<drill id>`, block `series.block:warmup|skills`. The
  levels' own records are never touched (library drills are re-seeded).
  `DrillItem.isSeries` keeps a series OUT of the drills list and pickers
  (visibleDrills), the plan generator's candidates, Home search and
  list_drills. SCREENS (Views/Drills/DrillSeriesViews.swift): drills page
  "Series · N" row (`library.series`, not in pick mode) → DrillSeriesListView
  (+ New Series) → DrillSeriesView (name, summary, Warm-up | Skills, numbered
  levels — Edit to drag, swipe to take out, + Add a level from the library
  picker, Delete Series keeps the drills; every change written at once);
  DrillSeriesCard on a drill's page ("Dribbling · Level 3 of 7", Previous /
  Next); New / Edit Drill's "Series" section joins one as its next level or
  starts "New series…". SPREADING: Edit Phase → "Add a series"
  (`phase.series.add` → a sheet of series) → SeriesSpreadSheet: block,
  overflow choice when levels > sessions (stop where the phase ends | two
  levels in some sessions), "N sessions, up to level K of M", and a
  session-by-session preview (review line + level badges); Apply writes each
  upcoming session. `SeriesSpread.plan` (pure): EVEN PACING, early levels
  take the extra sessions; never more than one new level a session (unless
  doubleUp, which pairs from the END so level 1 keeps its own); the first
  session of each level from the second on opens with the previous level as
  a REVIEW; `applying` removes every level of the series first, so a
  re-spread never doubles. A skipped class holds the level through the
  existing plan shift (SessionPlanShift). CONNECTOR: list_drill_series,
  create_drill_series (levels = existing drill refs, easiest first; `by:
  claude`); create_drill now says progressions are a SERIES of separate
  drills (it used to say one drill with one instruction per progression).
  Tests: DrillSeriesTests, DrillSeriesUITests (A create, B spread + clean
  up, C delete). LATER (agreed): moving up a level by MASTERY (the group's
  evaluation on that skill) instead of by calendar.

## Cycle planner (October 2026, Luther)
- "Generate N phases" is now PLAN A CYCLE (Views/Coaching/CyclePlannerSheet,
  Services/CyclePlanner, both targets): the coach gives START, DELIVER-BY
  date (required — open-ended programs plan cycle by cycle; defaults to the
  program end, else 12 weeks), LEVEL (the program's Training level) and
  EMPHASIS (preselected from evaluations + game stats via
  DrillPlanGenerator.dataFocus). `plan` is pure and previewed live; `apply`
  writes: phases from the coach's templates else FEB, the NEXT age group's
  chain at level 4–5 and the previous at 1, stretched to fit start…target
  exactly (weeks shared out, each ≥ 1); emphasis added to every phase's
  focus; up to 8 library activities suggested per phase; sessions via
  materializeSessions (existing ones adopted, never doubled); a plan for
  every planless session IN DATE ORDER so review/new builds up; the level
  saved to the program. Phase titles stay template strings so PhaseNaming
  still localises them.
- NEXT-CYCLE REMINDER: AttentionEngine rule 6 (`.nextCycle`, sanctioned by
  Luther as a sixth rule) — an active program whose LAST phase ends within
  14 days or ended < 7 days ago; one item per cycle; opens the program. Plus a
  local notification at 09:00 two weeks before the target
  (`next-cycle-<programId>`, replaced on every new plan). "Plan the next
  cycle" button under the phase list starts the day after the last phase.
- A planner-made session with no block minutes gets its length split evenly
  over warm-up/skills/game before planning. Tests: CyclePlannerTests.

## Mac directory pattern (August 2026) — HISTORY (Mac retired; code at tag mac-app-final)
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

## Court editor (step 5, in progress) — HISTORY (Mac retired; code at tag mac-app-final)
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

## Court editor phase (August 2026) — what landed and its rules — HISTORY (Mac retired; code at tag mac-app-final)
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

## Play Editor v2 Phase D (August 2026) — playback, print, playbook — HISTORY (Mac retired; code at tag mac-app-final)
- PLAYBACK CONSUMES FRAMES. `FramePlayback` (Models/, both targets) re-expresses
  the presentation consumption rules on ACTIONS: draw-on tip-first, consumed
  behind motion, tail tucked in FEET, hold guard, one head. The look is
  unchanged because every knob is still `RenderStyle.presentation`; only the
  geometry source moved. Two simplifications are structural, not shortcuts — an
  action is traversed by ARC LENGTH so the tuck is `feet / length` of progress
  rather than a backwards time-walk, and an action IS the whole movement so
  ONE ARROWHEAD needs no enforcing.
- `BallDerivation` (Models/) is ReadNode's ball code extracted verbatim: a pure
  function of `[Possession]` plus a position resolver, so frames and reads
  answer "where is the ball" with ONE implementation. ReadNode's methods are
  one-line forwards. v2 uses `HeldBallOffset.fixed` (1.9ft, matching what the
  editor draws) rather than v1's direction-of-travel offset — both ends of a
  pass shift by the same vector, so the flight length equals the
  centre-to-centre distance the frame model priced its duration from and the
  two cannot drift. A SHOT is priced hand-to-rim while its frame is priced
  centre-to-rim; the gap is bounded by offset ÷ shot pace (~0.07s), nothing
  follows a shot, and a test pins the bound.
- THE BASE PLAY IS A RUN. A read's branches are what happens INSTEAD, so a node
  played to its own end is itself a way the play unfolds — and it is emitted
  first. Before Phase D a single branch silently truncated the play at the
  branch point and its later frames were on no leaf at all, so they could not be
  played back or printed. Fixed in `frameRuns` AND `frameBranches`; they must
  agree about what a play's runs are.
- PLAYBACK IS A MODE, not a second editor: Space enters it anywhere (through the
  key dispatcher, so no default button can steal Space), the frame strip is
  replaced by a thin scrub bar whose ticks are FRAME BOUNDARIES — the only time
  ruler v2 has, because nothing here is authorable in time — ←/→ step
  boundaries, scrubbing pauses, Esc lands on the frame you were watching. The
  authoring frame stepper is HIDDEN during playback: it counts frames of the
  read being edited while the canvas shows a spliced RUN.
- PRINT IS THE EDITOR'S SHAREABLE ARTIFACT, replacing video export.
  `PlayCardDocument` (Services/, both targets) on `PDFDocumentRenderer`: A4,
  2x2 frames per page, captions under each, bilingual header, ink and hairlines
  with ONE accent on the ball. It draws the AUTHORING notation, not the
  presentation brush — a card is read, not watched, and the coach needs to see
  that this line is a screen and that one a dribble.
- A READ PRINTS AS ITS OWN SECTION, headed by its condition and carrying only
  its own frames. Printing whole runs reprints the shared entry once per read.
  Frame numbering continues across sections so "frame five" means one thing.
- `FrameCardRenderer` (Utilities/, both targets) draws ONE frame into a
  CGContext and is shared by the printed card and the playbook thumbnail — the
  same picture at two sizes. The canvas works y-DOWN and CoreGraphics documents
  are y-UP, so geometry is drawn inside one flipped state and TEXT outside it.
  `FrameNotation` moved to Utilities for the same reason: print and canvas must
  not disagree about what a dashed line means.
- THUMBNAIL IS FRAME 1, not the midpoint. A play is recognised by its SET-UP;
  the keyframe editor rendered the middle instant, which is the moment every
  play looks alike. `FrameThumbnailRenderer` is in Services, not beside the
  editor, because it draws a play rather than a view — and so it can be tested.
- Playbook cards read `frameCount` / `frameDuration` for a v2 play;
  `nodeCount` / `totalDuration` describe the keyframe model and read ZERO for a
  play authored in frames.
- DEBUG evidence hooks (Mac, env-gated, subsystem "hoopwise.demo"):
  `HOOPWISE_FRAME_DEMO_PLAY=<t>` parks playback at an instant and logs what the
  path layer produces there (visible feet per path, head count, ball state);
  `HOOPWISE_FRAME_DEMO_CARD=container` renders the card into the sandbox
  container. The Mac app is SANDBOXED with only user-selected file access, so a
  headless export cannot write anywhere an outside agent can read — the play
  card's real verification is `PlayCardDocumentTests`, which renders and
  inspects the PDF.

## PDF layer defects found in Phase D (both pre-existing, both shipped)
The document layer had NO tests until Phase D. The first one that touched it
found two bugs, and both were in code that renders documents sent to clients.
- USE AFTER SCOPE in `PDFTextStyle.attributes()`: `CTParagraphStyleSetting`
  stores a RAW POINTER, and the settings were built inside `withUnsafeBytes`
  closures and then handed to `CTParagraphStyleCreate` AFTER those closures
  returned. CoreText read stack memory that was out of scope. It "worked"
  because the bytes were usually still there. The create now happens INSIDE
  both scopes.
- `PDFDocumentRenderer` was implicitly `@MainActor` (the project sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), which made its DEINIT isolated;
  releasing one aborted in malloc via `swift_task_deinitOnExecutorImpl`.
  Constructing a renderer and dropping it was enough to kill a test process,
  which is why this layer had no tests. It is now `nonisolated` — rendering a
  document is not main-thread work and pinning it there was never intended.
  `PlayCardDocumentTests.testARendererCanBeCreatedAndReleased` pins it.

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
  Reopen = resetToScheduled (strips the marker). The ledger derives from
  the marker (no longer shown on Home since 19 Nov 2026 — Luther).
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
- The Home ATTENTION card has no category chips (11 Nov 2026, Luther:
  the "Close out" box repeated the line above): the urgent row opens its
  category, "See everything" covers several.
- RARE BY CONSTRUCTION (October 2026, Luther: "every single thing appears
  in it"). The list carries ONLY five rules; the red card appears only when
  one fires:
  1. Attendance not taken — any session that ENDED within
     recoveryWindowHours (48h) with zero marks, whatever its status (not
     only auto-closed), unless it did not happen. Partial roll calls are
     not flagged.
  2. Bundle running out — private bundle with ≤ renewalRemaining (1) left
     and a session inside 7 days; once per contract.
  3. Re-engage — RETIRED 9 November 2026 (Luther: "re-engage shouldn't be
     part of need your attention alerts" — it listed twenty names at once).
     The Kind case, AttentionRules constants and cooldown state stay so
     adapters and stored state decode; consecutiveMisses still exists.
  4. Note follow-up — only ON its due date (24h), never ahead.
  5. Reminders — only once due, shown 48h.
  6. Next cycle — added October 2026 at Luther's request (see "Cycle
     planner").
  RETIRED from attention: plan needed (visible on the session itself) and
  new student with no first session. Their Kind cases stay so adapters
  compile. Do not re-add a rule without asking: each one must cost
  something real if missed.
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
  An unexcused absence consumes a bundle session (agreement clause 4).
- INFERRED ABSENCE (October 2026, Luther's decision — REVERSES the earlier
  absolute "unmarked is NOT absent"). Services/AttendanceInference.swift is
  the ONLY place absence is inferred, inside four bounds that keep it from
  inventing charges: (1) only once ROLL CALL STARTED — at least one student
  on the session has an explicit mark; a class nobody marked stays unmarked
  and the "Attendance not taken" alert fires instead; (2) SHOWN at once,
  CHARGED one hour after class ends — `chargeInferredAbsences`, run first in
  AttentionEngine.runAutomation, writes them as explicit unexcused absences
  through the one redemption authority; (3) only sessions starting on/after
  `effectiveFrom` (2026-10-15) — never retroactive; (4) never for a session
  that did not happen. Covered by AttendanceInferenceTests. Do not infer
  absence anywhere else.
- ONE redemption authority: redeemPrivateAttendance. FIFO by
  effectiveBundlePurchaseDate. A client who buys a second bundle before
  exhausting the first expects sessions consumed in purchase order;
  charging the newest strands sessions already paid for. A second path in
  updateContractsForAttendance used to select by highest contract number
  and could charge a different bundle for the same session — it is gone.
  Do not add a second redemption call site.
  A THIRD writer survived until October 2026: syncAllContractAttendance ran
  on every loadAllData and overwrote the newest contract's bundleSessionIds
  with every present-marked session (any kind, skipped included). Each
  launch un-charged unexcused absences, re-charged skip refunds, charged
  group classes to private bundles and double-charged FIFO. Deleted; tests
  never caught it because they never call loadAllData.
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
- SINCE OCTOBER 2026 the control is a THREE-POSITION switch: left =
  excused, middle = not marked, right = present (Luther's design, the fifth
  sanctioned freeze exception). SINCE NOVEMBER 2026 (Luther: "they slow down the
  system … use the native iOS 3-position control") it is the SYSTEM SEGMENTED
  control (clock · — · check), same three positions. The hand-built switch's
  zero-distance drag fought the List's scroll/swipe recognisers and its knob
  waited for the store. The segmented control's selection is local (instant).
  WRITES ARE BATCHED: each mark used to be a full save + reload of every
  record on the main thread. The session page shows a tap at once, holds it in
  `pendingMarks`, and writes a run of taps in ONE
  `setStudentAttendanceStates` call (one revision, one save, then the one
  redemption authority) after 0.6 s idle, on leaving the page, or when the app
  leaves the foreground; `refreshSessionFromStore` re-applies pending marks so
  a refresh cannot undo them. "ALL PRESENT" (above the roster, confirmation
  states the money consequence) marks every expected student not present or
  excused — excused keep their excuse — in one write. Tests:
  AttendanceControlUITests (HOOPWISE_SHOT=pastSession), AttendanceSwipeUITests. There is NO absent position and no explicit
  Absent action anywhere (menu, swipe, Mac segment): absent is what the
  middle MEANS once roll call starts (AttendanceInference). Rows pass the
  EFFECTIVE mark (`SessionEvent.effectiveAttendanceMark`) so an inferred or
  recorded absence sits in the middle captioned "Absent". The control only
  writes present / excused / unmarked.
- The session tab's roster is a non-scrolling List sized to its rows,
  because `.swipeActions` only fire on List rows. Until October 2026 it was a
  LazyVStack and every documented swipe (Excuse, Clear, Refund) was INERT —
  the long-press menu was the only working path. Each row height is rounded
  UP to whole points when sizing the List, or the last divider clips and the
  first row jitters. SAMpUITests/AttendanceSwipeUITests swipes real rows, so
  a regression to a non-List container fails there. Remaining swipes:
  Photo (leading — opens ProfilePhotoCamera, replaces the profile picture;
  it was Metrics/Quick Measure until October 2026). NO trailing swipe since
  October 2026 (Luther: redundant) — Clear duplicated the switch's middle
  and the long-press menu; Refund lives on the contract sheet only.
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
- refundSessionToBundle has UI on the contract sheet's "Sessions deducted"
  section (both platforms). The session-row Refund swipe was removed in
  October 2026 at Luther's request.

## Mac attendance marking (decision REVERSED August 2026) — HISTORY (Mac retired; code at tag mac-app-final)
(October 2026: the Mac row follows the three-position model too — segments
Excused · — · Present, no Absent segment, inferred absence in the caption.)
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
- ProgramGuideDocument (Services/, BOTH targets, October 2026) is the
  parent-facing program guide, replacing a SwiftUI-card screenshot. ONE
  composition renders two outputs: A4 PDF (paginated, vector) and a long
  single-column JPEG for WeChat (same drawing code on one tall page, sized
  by a measuring pass via PDFDocumentRenderer.cursorPosition, then
  rasterized with ImageIO). Content comes from the program's own data:
  phases (title via PhaseNaming, dates, focus, description, objectives),
  example activities (phase.suggestedDrillIds, else the drills its
  sessions used), a typical session read from a REAL planned session's
  curriculum (with "from the plan for <date>"), and checkpoints = phase end
  dates. NOTHING INVENTED: missing data omits the section. It states that
  goals describe what the program teaches, not what a child achieved.
  Academy/coach is the identity; Hoopwise is a footer credit.
- DEBUG headless export: launch iOS with env HOOPWISE_EXPORT_GUIDE="<program
  name>" ("*" = first program; append ":stress" to fill every coach field
  with long text, unsaved) → guide-debug-{en,zh}.{pdf,jpg} in the App Group
  Library/Caches, through the same makeInput/render calls as the screen.
  Simulator: `SIMCTL_CHILD_HOOPWISE_EXPORT_GUIDE='*' xcrun simctl launch …`.
- Parent-facing wording (introduction override, phase title/summary
  overrides, session note, progress note, coach's note, home activity,
  academy name) is DEVICE-LOCAL in UserDefaults via ProgramGuideStore —
  deliberately not synced, because syncing needs schema fields (rule 5).
  An override equal to the program's own text is not stored, so later
  program edits still flow through. If it must sync, that is a schema
  decision for Luther, not a quiet addition.
- Filenames: `Attendance_<name>_Contract<N>_<yyyy-MM-dd>.pdf` and
  `Agreement_<name>_Contract<N>_<yyyy-MM-dd>.pdf`.
- Export UI: iOS contract sheet (system share sheet, for WeChat), Mac
  ContractCard menu (NSSavePanel).

## Group session balances and the class list (October 2026)
- GROUP CLASSES NOW CHARGE. A `.group` contract with `bundleSize > 0` is a
  prepaid SESSION BALANCE (`Contract.hasSessionBalance`); bundleSize 0 is an
  enrollment with no balance, exactly as before. redeemPrivateAttendance (the
  one authority, name kept) draws private sessions from private bundles and
  group-program sessions from group balances — never across the two pools.
  A balance with `programId == nil` is SHARED by every class the student
  attends ("课时与其他班共用"); one naming a program serves only that class.
  FIFO, present + unexcused absent, skip/delete refund — same rules.
  Renewal attention and the widget pick read `hasSessionBalance`.
  Covered by GroupBalanceTests.
- iOS AddEditContractSheet SAVES IN PLACE (October 2026). It used to build a
  fresh Contract from its fields, silently resetting what it does not show
  (signed/jersey/ball dates, the consent ledger, validityMonths,
  sessionMinutes) and zeroing a group contract's bundleSize. Never rebuild a
  record from a form — copy the existing one and set the fields it edits
  (the Mac editor already did). Its group section shows the student's
  classes (from rosters), sessions left, "counts for" (shared or one class)
  and the deducted sessions with Refund.
- MONTHS are entered as sessions at FOUR a month (one class a week) and count
  down by attendance; the contract notes carry `ClassList.monthsMarker` so the
  export prints them back in months. Luther's decision.
- A student can be on SEVERAL class rosters: `addStudentEnrollment` ADDS
  (student.programId = primary class, set only when nil);
  `setStudentEnrollment` still MOVES (clears every other roster).
- The coach's spreadsheet (上课名单.xlsx) imports and exports on BOTH
  platforms (sixth sanctioned freeze exception): Services/ClassListImport.swift
  — `ClassList.parse` (the sheet's own 人数/总人次 checks become issues),
  `ClassList.plan` (pure; matches students by name/Chinese name, programs by
  weekday + time + age; NEVER adds to an existing group balance, so a
  re-import cannot double one), `applyClassListImport` / `undoClassListImport`
  (all writes through the existing writers), `ClassList.export` — ONE tab
  上课名单 in the coach's own layout (October 2026, Luther): every class in
  week order as a light-blue band (人数 = COUNTA formula with a cached value),
  one row per student, low balances (≤ `ClassList.lowBalance` = 8) pink,
  then 长期不来 and one 总人次 row per coach. It is written with the coach's
  stylesheet copied VERBATIM (`ClassList.exportStylesheet`, cellXfs ids in
  `ClassList.Style`) via `XLSX.write(_:stylesheet:)`; XLSX now writes shared
  strings, formulas, per-cell styles, row heights and no-gridline views. iPhone: Athletes → + → Import/Export Class
  List (Excel). Mac: Settings → Data. Utilities/XLSX.swift is the
  dependency-free codec (zip + XML, CRC-32, deflate via Compression).
- NAMES: the sheet's hanzi becomes the CHINESE NAME and the name field is
  toned pinyin (the AddStudentView convention). `romanizeHanziNames` runs in
  loadAllData and repairs records the first import wrote with hanzi in both
  fields — only when the name is purely hanzi and the Chinese name is empty
  or identical. PinyinConverter reads polyphonic SURNAMES from a table on the
  first character (任 Rén, 曾 Zēng, 单 Shàn …); toPinyinPlain derives from it
  so NameIndex search/sort agree with the displayed name.
- DEBUG: HOOPWISE_CLASSLIST_PREVIEW=<path> writes a READ-ONLY plan to the App
  Group Library/Caches/classlist-preview.txt; HOOPWISE_SHOT=classListImport
  shows the preview screen over that file. Real class lists hold children's
  names — never commit one or use it as a fixture.

## App Store screenshots (October 2026)
- THE SIMULATORS ARE SIGNED INTO LUTHER'S iCLOUD: the iPhone Air sim's
  default.store holds the REAL roster (synced from CloudKit Development).
  Anything an agent does in a normally-launched simulator reaches the
  coach's phone. Never prune, seed or experiment in the synced store.
- HOOPWISE_SCREENSHOT_STORE=1 (DEBUG, Hoopwise/ScreenshotStore.swift) opens
  `screenshots.store` in the App Group with CloudKit OFF — a copy of the
  synced store, pruned to demo data (students WITHOUT a Chinese name, the
  programs they are on, their coaches), shifted so a demo class falls today,
  and enriched once (named phases, 24-session balances, history, today's roll
  call half-taken, two private bundles for Hub revenue). prune refuses to
  run unless this unmirrored store is the one open.
- SAMpUITests/AppStoreScreenshots captures the set; it is SKIPPED unless the
  runner gets HOOPWISE_SCREENSHOTS=1, so ⌘U never runs it:
  `TEST_RUNNER_HOOPWISE_SCREENSHOTS=1 TEST_RUNNER_HOOPWISE_LANG=en|zh
  xcodebuild test-without-building … -only-testing:HoopwiseUITests/AppStoreScreenshots
  -resultBundlePath r.xcresult` then `xcrun xcresulttool export attachments`.
  Use the iPhone 17 Pro Max sim (1320×2868, the 6.9" size), status bar via
  `simctl status_bar override --time 9:41 --batteryState discharging
  --batteryLevel 100`, light appearance. Seed it by copying the Air sim's
  App Group default.store* AS screenshots.store* (never as default.store).

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

## The Whistle — integrated LLM assistant (Mac only, August 2026) — HISTORY (Mac retired; code at tag mac-app-final)
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

## Restructure Phase 2.9 — the Contract shims stop lying (August 2026)
- The dangerous class was a CONTROL THAT CLAIMED TO SAVE: SalesView offered
  Contract Signed / Jersey Given / Ball Given, called save, and the setters
  discarded the write. `isSigned` also returned TRUE for every contract ever
  created, so the sheet showed "Signed on <enrollment date>" for agreements
  nobody had signed. `isExpired` returned FALSE always, behind a red warning
  in four screens that could never fire.
- SCHEMA CHANGE, PENDING DEPLOY: SDContract gained `signedDate`,
  `jerseyGivenDate`, `ballGivenDate` — three optional Dates, additive and
  CloudKit-safe (rule 7a). They ride the SAME pending Dev→Production deploy as
  seriesId and the play record types; adding them before that deploy is why
  they cost nothing extra. Rule 7d/7e still apply before any released build.
- THE DATE IS THE TRUTH, the Bool derives — same reasoning as the consent
  ledger: a Bool loses when it happened, and the rows already wanted to print
  "Given on <date>". Re-setting a true toggle does NOT restamp.
- Signing NEVER touches enrollmentDate. The old setter wrote it, and bundle
  revenue is attributed via effectiveBundlePurchaseDate (which falls back to
  enrollmentDate), so ticking "Contract Signed" moved revenue between months.
- `isExpired` DERIVES from validityMonths + effectiveBundlePurchaseDate. Zero
  months means no agreed term, which cannot expire. `expiryDate` returns that
  derivation so a contract cannot read "expired" with no expiry date — this is
  NOT a revival of the dead expiryDate COLUMN, which stays dead; there is
  still one source of truth.
- STATUS IS DELIBERATELY UNCHANGED. An expired contract stays `.active`, so
  redemption and the private-session rule behave exactly as before. Making
  expiry inactive is a MONEY decision, not a display one, and is not taken here.
- LIVE-STORE FLIP LIST (HOOPWISE_EXPIRY_FLIP, read-only, 2026-08-10): of 176
  contracts, **0 flip to expired** — every one has validityMonths == 0. The
  warning becomes capable of firing; nothing changes on screen today.
- Mac ContractCard gained the same three toggles (rule 6: fix on both or
  remove), each one contract write and one undo step.
- ROUND TRIP PROVEN for ALL THREE toggles on real data (2026-08-11), Mac →
  CloudKit → iPhone → back: Frank's contract #1 [F5269E85] signed+jersey+ball
  all false→true from the Mac at 14:16, read on the phone as three stamps at
  14:16, then all→false at 14:17 and read back as no facts recorded. The
  contract is exactly as it was; only `updatedAt` moved. Development
  environment, both debug builds.
- THE RED EXPIRY WARNING has exactly ONE live home:
  StudentQuickPeepView.contractInfoSection. StudentDetailView.contractSection,
  UnifiedStudentCard.contractSectionCard and .contractDetailSection all render
  the same warning and are NEVER REFERENCED — so four of the nine isExpired
  sites could not have fired whatever isExpired returned. Verified firing on a
  six-month term bought 2025-09-01: "49 Weeks" (tenure, purple) → "Mar 1 /
  Expired" (red).
- The Mac write went through HandoverWriteDebug (HOOPWISE_HANDOVER_WRITE=
  "<idPrefix>,jersey=on", Mac target, DEBUG) rather than synthetic clicks. The
  coach is often AT the machine — driving the UI with CGEvent clicks risks
  landing them in whatever window is frontmost, and a gated call through the
  same `updateContract` the toggle uses proves the same thing safely. Read side
  is HOOPWISE_HANDOVER on iOS.
- `applyContract` hand-lists its columns, which is how four session fields were
  silently dropped before SessionRoundTripTests existed. ContractHandoverTests
  now carries the same reflection guard for Contract.
- Still shims, and now honest about it: contract `jerseyNumber` / `jerseySize`
  return nil (nothing ever wrote a jersey number to a CONTRACT —
  Player.jerseyNumber is the real one) and the two read sites are guarded, so
  a ticked jersey no longer renders "Jersey #0". `weeklyAttendance` is still
  always empty.

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

DELETED (found during 2.9, added to this ledger afterwards):
- `StudentDetailView.contractSection`, `UnifiedStudentCard.contractSectionCard`
  and `UnifiedStudentCard.contractDetailSection` — 351 lines of view code
  DEFINED AND NEVER REFERENCED. This class is worse than ordinary deadwood: all
  three render the red expiry warning, so four of the nine `isExpired` sites
  could never have fired whatever `isExpired` returned. The dead views made a
  lying shim look like the whole explanation. When a warning "never appears",
  check that its view is reachable before concluding the predicate is wrong.
  `allContracts` and `showContract` were orphaned with them and went too.

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

## Stale session saves — games and attendance lost in class (25 October 2026)
- Luther lost a class's games and attendance mid-session (瓜沥 U10, 16:32,
  just after taking a photo). FlightySessionPageView keeps an `@State` copy and
  `saveSession()` wrote the WHOLE copy back on many actions (plan, notes,
  skip/cancel/complete…); a copy older than the store erased everything
  recorded since, and a whole-record write kept no revision. The exact trigger
  that day was not proven.
- FIX: `updateSessionEvent(_:keepLiveFields: true)` — the page's saves never
  write games, actualAttendeeIds, excusedAbsences, unexcusedAbsences or
  attendancePhotoPath; those keep the store's values (they are written field
  by field as they happen). `refreshSessionFromStore` copies those live fields
  ALWAYS (it gated them on updatedAt, so the page could keep showing an empty
  list), and now also copies unexcusedAbsences, which it never did.
- Any other whole-record write that would REMOVE games, stat lines or marks
  (`erasesLiveData`) records a revision first, actorLabel "Before overwrite".
- RECOVERY: session ⋯ → Restore Earlier Version (SessionVersionsSheet) lists
  the session's revisions (last 10, one before every field-level write) with
  games / stat lines / points / present / excused / absent / photo and
  restores one (`restoreSession`, which keeps the current version first).
  SessionSnapshotV1.apply did not restore unexcusedAbsences — fixed.
- Never add a whole-record session save from a view's copy without
  keepLiveFields. Tests: SessionStaleSaveTests.
- SECOND TIME (14 November 2026, Luther, U14 intermediate 10:00): three games
  vanished when the Home tab's "ending soon" roll-call photo was taken —
  MainTabView saved `liveEngine.session` (a copy from the START of class)
  whole, with the photo path set. FIX: that sheet writes the photo alone
  (`setSessionAttendancePhoto`), and `keepLiveFields` now DEFAULTS TO TRUE —
  a whole-record save keeps the stored games, marks and photo unless the
  caller passes `keepLiveFields: false` (only duplicate-session merges,
  whose survivor carries the merged games/marks, and DEBUG seeding). Live
  fields have field-level writers: appendSessionGame / deleteSessionGame /
  replaceSessionGames, setStudentAttendanceStates / setSessionAttendance,
  setSessionAttendancePhoto. The bad write was redeemed through
  updateContractsForAttendance, which never un-charges, so balances were
  untouched; the "Before overwrite" revision restores games and marks.

## Programs list: no weekday is not Saturday (23 November 2026, Luther: "why are my clients appearing on Saturday?")
The Sessions tab's programs list grouped by `recurringDays.first ?? .saturday`,
so every program WITHOUT a weekday — each private client's own program, a
camp — sat under Saturday. `ProgramListGroup` (FlightySessionRootView.swift,
file scope): `.day(first weekday)`, else `.privateLessons` ("Private lessons"
/ 私教课, via `SessionPrivacy.isPrivate(program)`), else `.noFixedDay` ("No
fixed day"); those two sections come after the weekdays. Nothing stored
changed. Test: ProgramListGroupTests. Not looked at on screen.

## Session notes save themselves (23 November 2026, Luther: "make sure notes are syncing to the cloud like everything else")
- AUDIT: every kind of note is in the synced store — session notes
  (`SDSessionEvent.notes` / `coachNotes`), reminders (SDReminder), athlete
  notes and the contact log (SDPlayer), team playbook notes (playbookData).
  Device-local on purpose: Parent Guide wording (ProgramGuideStore).
- THE GAP was WHEN session notes were written: only when the Notes tab was
  LEFT (`.onDisappear { saveSession() }`). Notes typed and left on screen — a
  Mac or iPad sitting on the tab, or the app put away and closed by iOS —
  never reached the store, so never iCloud.
- NOW: `setSessionNotes(sessionId:notes:coachNotes:)` is the field-level
  writer (no revision — it runs every few seconds of typing and the ten kept
  revisions are the restore points for games and attendance). The session
  page writes 2 s after the last keystroke, and at once when the editor loses
  focus, the tab or page closes, or the app leaves the front (`notesEdited`,
  `flushNotes`). `notesBaseline` = the notes as last taken from / written to
  the store; text that differs is unsaved (`notesDirty`).
- STALE COPIES: a whole-session save from a page that did NOT change the
  notes now takes the store's notes first (another device's newer notes used
  to be written back over by an older open copy), and a refresh never
  replaces notes typed here and not yet written.
- DEAD, NOT SYNCED: Components/SessionNotesBoard.swift (`BoardNotesStore`,
  UserDefaults `session_notes_board_v1` — the 33 MB blob in the phone's
  prefs) is referenced by nothing. Whatever old board notes it holds exist
  only on the device that wrote them and show nowhere. Bringing them into
  the session notes is a decision for Luther (asked 23 Nov 2026).
- DEBUG HOOPWISE_DEMO_NOTES=<text> (sessionPage, demo store) sets the demo
  session's notes. Tests: SessionNotesSaveTests, SessionNotesAutosaveUITests
  (types, kills the app on the Notes tab, relaunches: the text is there).
  SessionRemindersUITests failed the same evening at "the options appear
  while writing" — not shown to be related (it expects a "Before next class"
  option, which needs a later class that day); check it in the morning.

## No third-party imagery (App Review 4.1(a), 29 October 2026)
- Version 1.0 (5) was REJECTED under 4.1(a) Copycats: "the app's metadata
  contains third-party content … from a third-party platform". The listing
  text was clean; the screenshots showed Unsplash stock photos — every
  session header was a random Unsplash photo minted on first view, and
  athlete cards/parent reports/card PDFs used a second Unsplash set.
- REMOVED: SessionEvent.randomUnsplashURL, StudentProfileHeaderView's
  curatedImages/basketballURL/randomBasketballURL, the Edit Student
  "Regenerate Card Background" button, UnsplashImageService/UnsplashConfig
  (unused, and fatalError'd in Release without a key), and the card
  exporters' background fetches. Headers are now `CardCourtBackground`
  (StudentProfileHeaderView.swift): the program's or athlete's colour with a
  half court drawn in code. Stored headerImageURL values are ignored (legacy
  column, kept — removing it would be a schema change).
- RULE: no hot-linked or bundled third-party images, logos or brand names in
  the app or the listing. Student portraits in screenshots are AI-generated
  (Luther, 30 October 2026). Real business names from the coach's store
  (e.g. 酷迅) must not appear in App Store screenshots.

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
