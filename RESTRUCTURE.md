# The Phase 2 restructure — what changed, and what is still open

August 2026. One page. `CLAUDE.md` carries the rules; this carries the
end-state, the trail, and the ledger of what was deliberately left undone.

## Why it happened

`programId == nil` meant four different things at once — standalone, private,
legacy orphan series, and "no Live Activity" — and every consumer picked its
own reading. Around that grew the rest: session names frozen at generation
time, phase links written once and never re-derived, nine hand-rolled creation
sites that disagreed on every derived field, and a set of Contract accessors
that returned constants the UI rendered as fact.

The restructure gave each of those questions exactly one owner.

## Store end-state (2026-08-11, live device store)

| | |
|---|---|
| sessions | 201 |
| phases | 21 |
| programs | 17 |
| contracts | 176 |
| athletes | 134 |
| BROKEN total | **0** |
| duplicate groups | **0** |
| phase-window violations | **0** |
| standalone sessions | 5 (all in the triage list below) |
| contracts flipping to expired | **0** (every one has `validityMonths == 0`) |

Sessions went 217 → 201: 16 duplicate groups merged after derived names made
merging safe. Standalone went 41 → 5. Tests went 0 → 163.

## The trail

| phase | what it settled | commit |
|---|---|---|
| 0 | auto-close, skip/delete refunds, attention v2 | `e25403f` |
| 1 | reconciler, one privacy rule, one roster, manager-owned cascades | `2806d50` |
| 1.1 / 1.2 | duplicate merge rule; orphan census | `ff86a4c`, `448a551` |
| 2.1 | adoption — 41 standalone sessions re-homed; private micro-groups | `faa5a67` → `3623b40` |
| 2.2 | series identity (`seriesId`); Live Activity became a rule | `a45f0ba` |
| 2.3 | session names DERIVED; the 16 merges | `0237cc7` |
| 2.4 | phase links derived from the DATE | `55620c2`, `4ad5aa7` |
| — | Elite U10 plan reshape; folded the stray Frank session | `c5fed45`, `07eb4f9` |
| 2.5 | ONE creation service | `d6f3a36` |
| 2.6 | the skip rule | `9d0dde6` |
| 2.7 | phase words derived per language | `32e47d2` |
| 2.8 | deadwood verdicts (+ the armed day-only dedupe) | `6058a06` |
| 2.9 | Contract shims stop lying; round trip proven | `1b0f54f`, `deba4b8`, `38197b1` |

## Invariants the reconciler enforces

`SessionReconciler.run` is debounced into the same refresh paths as auto-close,
throttled 5 minutes, idempotent. It is a REPAIR pass, not a validator, because
CloudKit materialises records without running app code — `addSessionEvent`
validating at creation cannot be the guarantee on its own.

It repairs:
- a `programId` pointing at a program that no longer exists → cleared
- a `microCycleId` pointing at a phase that no longer exists → cleared
- a phase belonging to a DIFFERENT program than the session → the phase link is
  the invalid half, so it is cleared
- phase links re-derived from the session's DATE, through the one window rule
  (`SessionIntegrity.phaseWindow`, calendar days, both edges inclusive)

It COUNTS but never touches: duplicate groups (program + day + start time) and
orphan phases. Both need a human decision, and the merge proposes rather than
deletes.

Enforced elsewhere, and equally load-bearing:
- **one redemption authority** — `redeemPrivateAttendance`, FIFO by purchase
  date. Present and unexcused-absent consume; excused and unmarked do not.
- **unmarked is not absent**, in statistics exactly as in money.
- **cascade semantics live in the manager** — deleting a phase orphans its
  sessions; deleting a program cascades through `deleteSessionEvent` so slots
  refund.

## The open ledger

Verbatim. Nothing here is forgotten; all of it is deliberate.

1. **5-item Unassigned triage.** The standalone remainder: Scrimmage
   (2026-05-09), Scrimmage (2026-05-10), 义蓬U10周日上午9:30（活跃）
   (2026-05-17), Private Session - Mason (2026-08-06), Summer Camp
   (2026-08-07). The adoption planner returns "no matching program" for all
   five — they are genuine one-offs or need a program created. Not a defect;
   `programId == nil` now legitimately means exactly this.

2. **Mason's contract record.** `Private Session - Mason` reads as NOT private,
   because `SessionPrivacy`'s interim rule needs an ACTIVE private contract and
   Mason has none on file. A private client with no contract is a
   missing-paperwork problem, not a data-model problem. Closing it is a
   business act (write the contract), after which the session classifies itself.

3. **Three-way venue spelling.** One gym is spelled 酷迅 (112 sessions),
   义蓬酷迅体育中心 (27) and 酷迅体育中心 (2), while all three programs point at
   the single Location record `BFE80A50`. Needs a verdict: canonicalise to one
   label, or accept the variants as historical. `SessionCreation` already stops
   NEW divergence by defaulting a session's venue from its program.

4. **`weeklyAttendance` shim.** Still always empty. Its only readers were in
   view code that has since been deleted. Decide: derive it, or delete it.

5. **Expired bundles and money.** `isExpired` is display only — an expired
   contract stays `.active` and still redeems. Whether a lapsed term should
   stop a bundle consuming sessions is a MONEY decision and was not smuggled in
   behind a display fix. Note the flip list is currently empty, so this is
   theoretical until a term is set on a real contract.

6. **Dev→Production CloudKit deploy — REQUIRED before any released build.**
   Four fields are live in Development and unknown to Production:
   `SDSessionEvent.seriesId`, and `SDContract.signedDate`, `jerseyGivenDate`,
   `ballGivenDate`. Plus the record types registered earlier (the four play
   types, `SDDirectoryGroup`). Rule 7d/7e: deploy by hand in the CloudKit
   Console, then ship an iOS build carrying the types BEFORE Mac authoring
   writes any of them. Development DATA does not cross — only the schema.

## Two lessons worth keeping

**A default that renders is a lie that renders.** `isSigned` returning true,
`jerseyNumber ?? 0`, `weeklyAttendance` empty — the failure is always the
display layer coalescing a missing value to a plausible one. Sweep for `?? 0`
and `?? ""` on domain values.

**Check the view is reachable before blaming the predicate.** Four of
`isExpired`'s nine call sites sat in view properties that were defined and
never referenced. The dead views made a lying shim look like the whole
explanation, and 351 lines of them were deleted in the same pass.
