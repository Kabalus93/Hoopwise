# Hoopwise Player Card — Design Brief

## TL;DR
Design a **print-ready, professional-looking basketball player card** for a youth coaching app. The card has two faces (front + back), is sized like an NBA collectible card (2.5″ × 3.5″ portrait), and gets handed to kids monthly + shared digitally with their parents. The current implementation works but reads as a generic vintage-baseball-card pastiche — we need a confident, modern look the coach is proud to print.

Deliverable: a Figma file with the front and back as separate frames at print resolution, plus a small token sheet (colors, fonts, spacing) so engineering can rebuild it 1:1 in SwiftUI.

---

## Product context

**Hoopwise** is an iOS app for basketball coaches running youth programs (mostly ages 8–14, mixed bilingual EN/中文 audience in Hong Kong). Coaches track attendance, run training sessions with in-session scrimmages, and rate player skills. The card is a **monthly artifact**:

- **Printed at A3** in 6×3 grids and handed out to kids as physical trading cards (huge pride moment for the kid, parents stick it on the fridge).
- **Shared as a 2-page PDF** with parents over WeChat / iMessage at the end of the month.

The card is the most visible artifact the coach hands to the family. It deserves to feel premium.

---

## Hard constraints (don't break these)

| Spec | Value |
|---|---|
| Aspect ratio | 5:7 portrait (NBA standard) |
| Print size | 2.5″ × 3.5″ (63.5 × 88.9 mm) |
| Pixel size at 300 dpi | 750 × 1050 px |
| Bleed | 0.125″ all sides — extend background art into bleed |
| Safe area | 0.125″ inset from trim — no critical text outside |
| Faces | Two: front (identity + stats) + back (radar + branding) |
| Type rendering | Native iOS system fonts only (SF Pro, SF Mono, no custom font files) — keeps build size sane and avoids licensing |
| Bilingual | Layout must accommodate both `Alan` (1 word, English) and `沈铎` (2 Chinese characters) as the primary name — same prominence either way |

---

## Required data fields

Every field below is real data the app already has — design must accommodate all of them, including their empty states.

### Front
- **Player photo** — circular crop, ~80px diameter equivalent. Falls back to colored initials when not set (most kids won't have one initially).
- **English name + Chinese name** — both shown together; primary one swaps based on app language. Must handle 12+ character names.
- **Jersey number** — optional, top-right corner. Most kids don't have one yet.
- **Performance grade letter** — A / B / C / S / "—" (when ungraded). Currently displayed in a diamond.
- **Age** — number + unit
- **Height** — formatted like `5'1"` or `—` when unknown
- **Handedness** — `R` / `L` / `A` (ambidextrous)
- **Membership year** — e.g. "SINCE 2026" badge
- **Stats grid (6 cells)** — `PPG · APG · RPG · STL · BLK · EFRT`. All show as `0.0` for kids who haven't played a game yet.
- **Tiny trend indicators** next to each stat (currently shown as little dashes — meant to be ↑ / → / ↓ delta vs previous month)

### Back
- **Player name** (single line, both languages)
- **Program / season label** — e.g. "WEDNESDAY U12 GROUP" or "SEASON 2026"
- **Hexagonal radar (6 axes)**: Scoring · Playmaking · Rebounding · Defense · Athletic · Effort
  - Each axis is 0–10
  - Two overlapping shapes when monthly data exists: lifetime (filled) + this month (dashed outline) with a small legend
  - For brand-new players the radar stays a flat "untrained" hexagon at default values — surface a small "Awaiting first evaluation" chip so it doesn't read as a render bug
- **Hoopwise wordmark + small logo** as the back-of-card mark

---

## Key use cases

### 1. Monthly print drop (the headline use case)
Coach exports an A3 sheet with all enrolled kids → prints duplex on cardstock → cuts → hands one to each kid at the next session. The card has to feel *valuable*. Crop marks already render between cards on the A3 sheet — design just needs to keep critical content inside the safe area.

### 2. Parent share (digital)
Coach taps a single player → exports a 2-page PDF (front, back) → shares via the iOS share sheet. Whoever opens it sees the card at native 2.5×3.5 — most likely viewed in iOS Quick Look or WeChat preview. **The page IS the card** — no surrounding margin or matte.

### 3. Empty-state day-1 player
Most cards will be printed **before** the kid has played a single tracked game. The card must look polished even when every stat is `0.0` and the radar is a flat hexagon. The current cream/brown design fails this test — it just looks empty.

---

## Brand context

Hoopwise is **not** a Topps reissue or a vintage throwback. The current cream + saddle-brown palette was a placeholder that drifted into "baseball card 1956." We can either lean into vintage hard, or pivot — your call, but pick a direction.

**App accent palette already in use:**
- Avatar tints: blue `#5B8DEF`, green `#6BCB77`, purple `#9B7EDE`, red `#EF6B6B`, teal `#4ECDC4`, orange `#FFB347`, pink `#F8A5C2`, yellow `#FFE066`, indigo `#7C83FD`
- Per-student accent (already passed in as `accent`) — drives the radar fill on the back
- Format colors: private `#9B7EDE`, group `#5B8DEF`, school `#4ECDC4` — could be a subtle stripe on the card
- Existing in-app cream `#F5F0E6` and saddle brown `#8B7355` — keep, change, or kill

The youth audience is 8–14. The card should feel **proud and a little bold**, not cute, not corporate. Think: NBA team-issued rookie card energy, not Pokemon.

---

## Reference inspirations (not copies)

- **Topps Chrome** — refractor finish, clean grid, sharp typography
- **Panini Prizm Optic** — bold colored backgrounds, big player photo
- **Apple Wallet pass** — minimal, premium, restrained type
- **NBA 2K Ultimate Team cards** — layered metallic, rarity tiers
- **Letterboxd diary cards** — modern, content-first, photographic

Avoid: literal Topps replicas, anything that looks like a screenshot of a stat dashboard, anything cluttered.

---

## What's there today (and what's wrong)

I'm attaching one rendered PDF. What's working / not:

**Front works:**
- Player photo circle (or initials fallback)
- Name + Chinese name + age/height/hand block
- Stats grid populates correctly

**Front doesn't work:**
- Cream + brown reads as bargain-bin nostalgia
- Performance grade diamond ("B" in a tilted square) is awkward
- Jersey number is too easy to lose against the basketball photo
- Trend dashes next to stats are invisible
- "SINCE 2026" pill is generic — could say something more meaningful

**Back works:**
- Radar geometry is correct, dual-overlay logic for monthly comparison is wired up
- Bilingual axis labels

**Back doesn't work:**
- Visually disconnected from the front — same cream + brown but no shared design language
- Lots of empty space around the radar
- "Awaiting first evaluation" chip gets buried
- Hoopwise mark is afterthought-sized

---

## Specific asks for the designer

1. **Two finished frames** in Figma at 750 × 1050 px (300 dpi · 2.5×3.5″) — front and back.
2. **A 4-up demo board** showing the same card with realistic data variation:
   - Brand-new kid, all zeros, no photo, default skills
   - Mid-season kid, decent stats, no photo, evaluated
   - Star kid with photo, jersey #, monthly delta arrows, full radar
   - 12-year-old in school program (different format-stripe color)
3. **Token sheet** as a single Figma frame:
   - Color tokens (with hex + when each is used)
   - Type scale (which SF style for which element)
   - Spacing scale (4 / 8 / 12 / 16 etc)
   - Border + shadow specs
4. **Editable Figma file** (not flattened) — engineering rebuilds in SwiftUI from this. No bitmap exports needed except for any decorative artwork (foil patterns, background art).
5. **Loose component library** for the small bits engineering will reuse:
   - Stat cell with trend arrow
   - Performance grade badge (A/B/C/S/—)
   - Format chip (private/group/school) — uses existing tint colors
   - Bilingual name lockup (handles long names + Chinese gracefully)

---

## Decisions you have permission to make

- Keep cream/brown, kill it, or pick something new entirely
- Replace the diamond grade badge with anything that reads better
- Add or remove the basketball-action background photo on the front
- Treat the back as visually mirrored to the front, or completely different
- Add a "rarity tier" visual hint based on the performance grade if it adds something (subtle — don't gamify)
- Use foil / refractor patterns as decorative bg art (we'll bake them as PNGs)
- Restructure the data hierarchy on the front — what gets emphasized is up to you, but every field listed must appear

---

## Decisions to bring back to me first

- Anything that requires a custom font file (licensing, build-size cost)
- Anything that requires a bitmap render bigger than ~200KB per card (storage cost on the device for each kid)
- Removing a data field or changing its meaning
- Anything that breaks bilingual parity

---

## Output checklist

- [ ] Front frame (750×1050, 300 dpi)
- [ ] Back frame (750×1050, 300 dpi)
- [ ] 4-up variation board
- [ ] Token sheet
- [ ] Component library
- [ ] One paragraph of design notes per face — what's intentional, what's flexible
- [ ] List of any source assets (photos, foil patterns, etc.) with licenses

---

## Brand assets you'll need

- App name: **Hoopwise**
- Logo asset: `Hoopwise/Assets.xcassets/HoopwiseLogo.imageset/` (in repo)
- App accent: derived per-student (don't pick a single one for the brand mark)
- Voice: confident, encouraging, kid-positive — never corporate
