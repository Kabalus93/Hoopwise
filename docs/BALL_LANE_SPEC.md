# Possession semantics — what the ball lane meant (A3)

**Status: IMPLEMENTATION CANCELLED (2026-08-14). Kept as the record of
possession semantics that Play Editor v2's frame model must preserve.**

This began as a build spec for the timeline's Ball row. The row does not survive
v2 — the frame model replaces the timeline entirely — so none of the interaction
design below will be built. What survives is everything it forced into words:
what the ball's states ARE, which of them are facts and which are consequences,
and what a coach must be able to say about a ball's movement. A frame model that
cannot express §1, §2 and §6 has lost something the timeline could do.

**Read §1, §2 and §6 as binding.** §3, §4 and §5 are interaction design for a
row that is going away; they are kept because they document *why* each element
existed, which is the same question v2 has to answer in its own vocabulary.

**§6's proposal is ACCEPTED as semantics** (2026-08-14): dragging a pass
**release SHIFTS** the flight, dragging the **attach STRETCHES** it. One end
moves the event, the other sets the arrival. That is the rule wherever
pass-dragging resurfaces in v2, under whatever the frame model calls those two
handles.

One sentence of scope, which was true of the row and stays true of whatever
replaces it: **it answers "where is the ball, and when does that change" —
nothing else.** Anything that cannot be justified by that sentence is listed
below under *Delete*.

---

## 1. The model it is a view of

Possession is authored as intervals on the read node:

```
Possession { holderId, start, end?, release? }      release = .pass(toId) | .shot(target)
```

Everything drawn on the lane is either **a possession event** (an editable fact
in that array) or **a derived span** (a consequence of the array + where the
players are). The rule this spec is built on:

> **Bar segments are DISPLAY. Glyphs are the HANDLES. Nothing may exist on the
> lane without a model meaning.**

A flight has no stored duration — it runs from the release to the receiver's
attach (A1 made that the single authority). So the *length* of a flight segment
is never draggable on its own; you move the release or you move the attach, and
the flight is what is left between them.

---

## 2. Every visual element, and what it means

Annotating the current row, left to right:

```
 Ball  👁 🔒 ◎  [◀ ◇ ▶]  │ ⊙━━━━━━━━━●━━━━━━━━━━⊙━━━━━━━━━━━━🏀━━━━━━━━━━━━━━━ │
                          ↑ ↑        ↑          ↑            ↑
                          │ │        │          │            └ shot release (red)
                          │ │        │          └ attach: O2 gains it (green)
                          │ │        └ pass release (orange)
                          │ └ bar segment: state over an interval
                          └ attach: O1 gains it (green)
```

### 2a. Bar segments — DERIVED, display only

| Fill | State | Means | Comes from |
|---|---|---|---|
| Neutral grey 22% | **Held, still** | A holder has it and is not moving | possession ∧ holder travels < 0.3 ft over the span |
| Holder's tint 55% | **Dribbling** | A holder has it and is covering ground | possession ∧ movement — the *same* rule that renders the dribble squiggle on court |
| Orange 85% | **Pass in flight** | Nobody holds it; it is between two players | release `.pass` → next attach |
| Red 80% | **Shot in flight** | Nobody holds it; it is on its way to the rim | release `.shot` → derived arrival |
| Grey 8% | **Loose** | Nobody holds it: before the first attach, or resting at the rim after a shot | everything else |

The bar is **total and gap-free by construction** — every interval is classified
by asking `ballState` itself, so the bar cannot contradict the court.

### 2b. Glyphs — the editable handles

| Glyph | Event | Model fact | Exists when |
|---|---|---|---|
| ⊙ green `smallcircle.filled.circle` | **Attach** | `possession.start` | always, one per possession |
| ✈︎ orange `paperplane.fill` | **Pass release** | `possession.end` + `.pass(toId)` | a possession that ends in a pass |
| 🏀 red `basketball.fill` | **Shot release** | `possession.end` + `.shot(target)` | a possession that ends in a shot |

**There is no arrival glyph, deliberately.** A pass's arrival IS the receiver's
attach — the next ⊙. Drawing a fourth glyph for it would put two handles on one
instant that cannot move independently.

---

## 3. Every interaction

### 3a. Glyphs

| Gesture | Result | Canvas response |
|---|---|---|
| **Click** | Selects that event. Inspector shows Possession Event. | The flight arc or holder it refers to highlights on court. |
| **⇧-click** | Adds to selection (multi-retime). | — |
| **Drag** | Retimes, snapped to the grid, one undo per gesture. Selection moves together, spacing preserved. | **Live**: the ball's position at the playhead updates as you drag, and the flight arc redraws to its new endpoints. |
| **Double-click** | *(NEW)* Moves the playhead to the event. | The court jumps to that instant. |
| **Delete / ⌫** | Deletes the event through `deleteAttach` / `deleteRelease` — the model's own repair primitives, which keep possessions ordered and non-overlapping. | The ball never orphans: the previous holder simply keeps it through. |
| **Right-click** | Menu: *Go to* · *Convert to Shot/Pass…* · *Delete*. | Convert previews as a redrawn arc. |

**Constraints on a drag** (clamped, not rejected — the glyph stops moving):
- An attach cannot cross the previous possession's release.
- A release cannot cross its own attach.
- Dragging a **pass release** carries its receiver's attach with it, because the
  flight between them is derived and would otherwise invert.

### 3b. Bar segments

| Gesture | Result |
|---|---|
| **Click** | Selects the span. Inspector shows state / holder / from / to / duration — all read-only. |
| **Double-click** | *(NEW)* Selects the two glyphs that bound the span, so the next drag moves the thing the span is made of. |
| **Drag** | **Nothing.** Deliberately: a span's edges are its neighbouring events, and dragging a derived thing would need to guess which end you meant. |
| **Delete** | **Nothing.** You cannot delete a consequence. |

### 3c. Not interactive, and why

- **The ⟨◀ ◇ ▶⟩ keyframe cluster on the Ball row** — the ball has no position
  track while Sticky Ball is on; there is nothing to keyframe. *See Delete.*
- **The solo / lock toggles on the Ball row** — see Delete.

---

## 4. Selection sync, both directions

| You click | Lane shows | Canvas shows |
|---|---|---|
| A flight glyph | Glyph enlarged + shadowed | **That flight's arc highlighted** (thicker, full opacity, drawn even if the playhead is outside its A2 window) |
| A flight arc on court | **Its release glyph selected** | Arc highlighted |
| An attach glyph | Glyph enlarged | The holder's puck ringed at that instant |
| A bar span | Span outlined | Nothing — a span is not a thing on the court |

Two of these four are new: canvas→lane (clicking an arc selects its glyph) and
the arc highlight. They are the substance of "the lane is a view of the model"
— without them the row is a second window onto the same data with no thread
between them.

---

## 5. Delete

| Element | Why it goes |
|---|---|
| **Keyframe cluster ⟨◀ ◇ ▶⟩ on the Ball row** | The ball has no position track under Sticky Ball. `toggleKeyframeInPlace` already refuses for the ball, so the ◇ is a button that does nothing, and ◀ ▶ jump between keyframes that cannot exist. Replace with ⟨◀ ▶⟩ that step between **possession events** — same shape, real meaning — or show nothing. |
| **Solo ◎ on the Ball row** | Soloing the ball dims every player to 25% and leaves an orange dot on an empty court. No coaching read; no way back to the play except un-soloing. |
| **Lock 🔒 on the Ball row** | "Canvas clicks pass through" — but a locked ball still accepts the drag that authors a pass, because that gesture is possession authoring, not entity movement. It is a toggle whose promise does not survive contact with the one gesture the ball has. Either it blocks ball-drag authoring or it goes; I propose it goes. |
| **Box-select of possession events** | It works, and I cannot construct the case for rubber-banding two events that are not adjacent. Retained only if you want multi-retime from the marquee; otherwise ⇧-click covers it. |

Keep 👁 (hide): hiding the ball to look at spacing alone is a real thing.

---

## 6. Open question for you

**Should dragging a pass release also be allowed to change the flight's
duration?** Today it cannot: the receiver's attach moves with it, so the flight
keeps its length and only shifts. The alternative is that dragging the release
*compresses* the flight against a fixed attach, which is how you would author a
"skip pass takes longer" beat.

I propose: **release drag shifts (current behaviour), attach drag stretches.**
One end moves the whole event, the other end sets the arrival. That gives both
behaviours without a modifier key, and it matches what each glyph *is*.

---

## 7. What this spec does NOT do

- No new stored fields. Everything above reads or writes the existing
  `possessions` array.
- No change to what the canvas draws (beyond the selection highlight).
- Nothing that steps-first authoring would throw away: the lane stays a view of
  possession, and a step-based editor still needs "when does the ball change
  hands" as a timeline. If the read gets reorganised into steps, this row is
  re-parented, not rewritten.
