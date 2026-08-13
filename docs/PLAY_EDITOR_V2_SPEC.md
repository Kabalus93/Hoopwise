# Play Editor v2 — FastDraw Mechanics, Apple Motion Coat

The decision: the editor's workflow and functioning follow FastDraw — frames, notation, per-frame coaching text, frame-strip navigation, print-quality play cards. The presentation follows Apple's pro apps — canvas-first, direct manipulation, context HUD, restraint. The existing presentation renderer survives as the playback look. The video workflow (camera authoring, easing, Resolve export) is removed inside this rebuild.

Phased with hard gates like the restructure: report each phase's acceptance before the next. Dry-run rule applies to anything touching stored plays.

**Migration stance, decided up front:** the store holds only test plays (3, all scratch). No converter. Old plays are deleted with one confirmation listing them by name; the keyframe timeline model they used goes with them. If that list surprises me with a play I care about, I'll say so — otherwise wipe.

---

## Phase A — The Frame model

A play becomes an ordered list of **Frames**. Each frame holds:
- A set of typed **Actions**: `cut`, `dribble`, `pass`, `screen`, `handoff`, `shot` — each with actor, optional target (player or court point), and a path (control points in court-feet).
- The **end formation** (every entity's position at frame end — derived from actions + carry-over, stored resolved for cheap reads).
- A **caption**: per-frame coaching text, bilingual-capable via the localization machinery (stored as the user typed; localizable presets later).
- Possession is *derived from actions* frame-by-frame (a pass moves it, a shot ends it) on top of the existing possession model — the model stays the truth; frames become its authoring interface.

Timing is **derived, never stored per keyframe**: each action gets duration from path length ÷ role speed (walk/cut/sprint per action type, one global pace setting per play). Frames play sequentially; simultaneous actions within a frame run concurrently. The old keyframe tracks, camera track, and easing data have no place in this model.

**Reads remap naturally:** a read is a branch *at a frame* — "after frame 2, if X: frames 3a…, else 3b…". The existing branch tree carries over; its time-offsets die.

Ship Phase A as model + tests only (frame CRUD, action→timing derivation, possession derivation, branch-at-frame), no UI yet. **Accept:** round-trip tests; a hand-built 4-frame play resolves to correct positions/possession at any t; suite green.

## Phase B — Authoring (the FastDraw core)

The editing surface rebuilt around frames:

- **Frame strip** along the bottom (replacing the timeline as the primary chrome): numbered thumbnails, current frame highlighted, `+` adds a frame continuing from the end formation, drag to reorder, context menu duplicate/delete. Click = jump. ←/→ arrows navigate (via KeyDispatchCore).
- **Drawing in a frame** — actions come from direct manipulation, notation auto-applied:
  - Drag a player → a cut path draws live (solid, arrowhead); path is bendable after (the existing drag-to-bend carries over).
  - Drag a player who holds the ball → dribble (the auto-dribble inference already exists; render zigzag notation in edit).
  - Drag the ball to a player → pass (dashed, existing snap/receiver highlight carries over); to the hoop → shot (existing).
  - **Screen tool** (or modifier-drag): drag a player to a spot, path ends in the T-bar; optional link to the teammate being screened for.
  - Standard notation is the edit-mode language: solid+arrow cut, zigzag dribble, dashed pass, T screen — clean vector, no blur in edit.
- **Onion skin:** previous frame's end formation ghosts at low opacity so continuity is visible; toggleable.
- **Caption field** attached to the frame strip (edit in place), rendered under the court in playback and on print.
- Per-frame path display replaces A2's time-windowing: **you see the current frame's actions, nothing else** — the messy-view problem dies structurally.
- Undo: every frame/action mutation one step, per convention. Selection sync canvas↔strip.

**Accept:** author a real play (your Horns entry) start to finish without touching an inspector: 4 frames, cuts/screen/pass/shot, captions — under 3 minutes of interactions, every action correctly typed and notated. Screenshots per frame.

## Phase C — The Apple coat

- **Canvas ≥75%** of the window: app sidebar and plays list auto-collapse entering the editor (breadcrumb back), reads panel becomes a popover from the frame strip, tool strip folds to a compact floating palette.
- **HUD, Motion-style:** selection summons a small translucent context panel *at the selection* — select a pass arc → flight time, convert-to-shot, delete, right there. The right inspector column survives only for multi-field precision (numeric positions), collapsed by default.
- Materials, type, motion: system materials/vibrancy for panels, SF Symbols only, one accent, spring-settle on drops, 150–250ms transitions, Reduce Motion honored. Light and dark both first-class; the court itself gets a light/dark pair tuned for edit legibility (presentation look unchanged).
- Frame strip thumbnails render live (small canvas snapshots, debounced).
- Every dismissal/Esc/undo convention from the app-wide rules audit applies; no editor-local deviations.

**Accept:** side-by-side before/after screenshots; a cold look reads as an Apple pro app; canvas share measured ≥75% at default window.

## Phase D — Playback, print, playbook

- **Playback** consumes frames: derived timing feeds the existing presentation renderer (brush, consume-behind, one arrowhead rule) — untouched visually, now driven by frames. Space plays; frame boundaries shown as subtle ticks on a thin scrub bar (the only time-ruler that survives).
- **Print becomes a first-class output:** play cards via CGPDFContext — 2×2 frames per page (or 2×3), notation vector-crisp, captions under each frame, bilingual header (play name, program, date), the same document quality bar as the attendance statement. This replaces video export as the editor's shareable artifact.
- **Playbook integration:** thumbnail = frame 1 (or chosen frame); the save-to-playbook flow, families, and variations from the earlier spec unchanged; playbook card shows frame count + duration.

**Accept:** print your Horns play → a card a parent or assistant coach could run the play from; playback of the same play looks exactly as good as the current presentation mode.

## Phase E — Removal

With frames live end-to-end: delete the keyframe timeline UI, per-entity tracks, camera track + Set Camera Keyframe, easing inspectors, elevation slider, the Resolve export pipeline and its offscreen render path (presentation canvas rendering stays), and every RenderStyle knob that existed only for export. Grep-provable: no references to the removed types; CLAUDE.md's editor section rewritten to the frame model; the removal is its own commit series so it's revertible in theory.

**Accept:** feature-by-feature deletion list in the report; both targets build; suite green; app size/complexity delta noted.

---

## Explicitly out of scope (next projects, but designed-for now)
- **Play recognition** and the **AI co-builder**: Phase A's typed-action grammar and court-landmark vocabulary are their foundation — actions are data, which is all recognition and generation need. Build nothing for them yet.
- Defense entities beyond the existing D1-style props, multi-team plays, video import.

## Ground rules
- Gates between phases; dry-run + named-list confirmation before the play wipe; committed tests per phase (frame model especially); evidence per the trimmed standard.
- iOS stays frozen except: the courtside play *viewer* (step-through) is a candidate future exception — flag, don't build.
- The three fixes and audit findings from the previous session that touch surviving surfaces carry over; anything that touched the old timeline dies with it unmourned.

---

# Amendments after approval

Not part of the spec text above; recorded here so they travel with it.

**2026-08-14 — the play list is 4, not 3, and one of them matters.**
The store holds FOUR plays, not three scratch ones: `test`, `Untitled Play`,
**`Triangle Offense`** (2 reads), `Untitled Play`. Triangle Offense is real
work — a branched play with an authored ball story whose pass lands at 3.46s.

Decided: the named list is still shown and confirmed as specced before any
wipe, and **Triangle Offense is kept** — re-authored in v2 rather than
converted, and it becomes the **Phase B acceptance play in place of the Horns
entry**, because it has real reads and is therefore the honest test of the
frame model's branching.

**2026-08-14 — possession semantics are pinned by `BALL_LANE_SPEC.md`.**
Its §1, §2 and §6 are binding on the frame model: what the ball's states are,
which are facts and which are consequences, and that a pass **release drag
SHIFTS** the flight while an **attach drag STRETCHES** it.
