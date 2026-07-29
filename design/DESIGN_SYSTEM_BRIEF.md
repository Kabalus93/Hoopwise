# Hoopwise Design System — Brief

## What we're building
A native iOS design system for **Hoopwise**, a basketball coaching app for youth programs. The system needs to work across three surfaces:

1. **In-app screens** — coach's daily tool. Glanceable, dense, runs in a noisy gym.
2. **Printable artifacts** — player cards that get printed at NBA collectible size and handed to kids monthly. Need to feel premium.
3. **Shareable digital artifacts** — PDFs / images sent to parents over WeChat & iMessage.

One design language across all three. The print stuff is the same family as the app, not a separate brand.

---

## Audience

**Primary user — the coach** (us, currently)
- Runs 1–6 sessions a day, mostly youth (ages 8–14)
- Often pulling out the phone mid-session — needs glanceable, fat tap targets, can't fiddle
- Power-user; over time moves all admin into the app (scheduling, attendance, stats, contracts)
- Bilingual EN / 中文 — mixes both in a single phrase regularly
- Mostly Hong Kong + mainland China

**Visible to — kids 8–14**
- See the cards handed to them, the live game scoreboard during scrimmages, sometimes the radar
- Should feel proud of artifacts that have their name on them
- Not gamified — kids see real numbers, not coins or XP

**Visible to — parents**
- Receive monthly card / report via messaging apps
- Often only touchpoint they have with the program
- Need to immediately read "this is professional, my kid's coach is on top of it"

---

## Personality

### What we are
- **Confident** — a tool a real coach hands to a real kid
- **Athletic** — clean lines, decisive type, motion has weight
- **Native-feeling** — built on iOS conventions, not fighting them
- **Quietly premium** — restraint over flair; a single accent does the work
- **Bilingual-first** — Chinese characters and Latin letters look equally considered

### What we are not
- Not gamified (no XP bars, no glittery rewards, no mascots)
- Not cute or childish (kids see real data, not stickers)
- Not corporate (no SaaS-blue everything, no stock-photo placeholders)
- Not vintage (the current cream/brown was a placeholder — explicitly leaving Topps-baseball-card territory)
- Not flashy fitness-app (no neon gradients, no liquid blobs)

### References to pull from
- **Apple Fitness, Health, Calendar** — for layout density, glassiness, system-native feel
- **Linear** — for type rhythm, restrained color, information hierarchy
- **NBA app + NBA 2K rookie cards** — for the celebratory print artifacts only
- **Letterboxd diary cards** — for content-first cards

### References to avoid
- Anything looking like Topps / vintage trading cards
- Anything looking like a youth-camp brochure (yellow! orange! "fun fonts!")
- Anything looking like a SaaS dashboard (ChartJS pie charts, generic blue, wall-of-numbers)

---

## Color

### Anchor palette (pick or refine — these are intent, not commitments)

| Role | Direction |
|---|---|
| **Surface** | Off-white / very light warm gray for the canvas. iOS systemGroupedBackground feel. Dark mode: near-black, not pure |
| **Card** | Pure white in light mode, elevated near-black in dark mode |
| **Ink (primary text)** | Near-black warm — not pure `#000` |
| **Ink (secondary)** | Mid neutral, ~60% contrast |
| **Ink (tertiary)** | Faded neutral, ~40% contrast — for axis labels, captions |
| **Brand accent** | One confident hero color the system rallies around. Not blue (overdone for SaaS). Could be a deep court-orange, a saturated green-court, or a confident red. Pick one direction |
| **Stroke / border** | Hair-thin neutral, used sparingly |

### Semantic color (every app needs these — let the palette dictate exact hexes)
- **Success / completed** — green family
- **Warning / attention** — amber family
- **Danger / urgent** — red family
- **Info / neutral status** — blue family

### Categorical color (already in the codebase — keep as a per-entity tinting layer)

Each student / program gets one of these as their *personal* accent:
`blue · green · orange · purple · red · teal · pink · yellow · indigo · gray`

These tint avatars, the radar fill on cards, format chips, and per-program highlights. **They are decoration, not communication** — the system shouldn't lean on them for state. The semantic palette above does that.

### Format tints (already in use)
Three formats of session/student exist; each has a stable tint:
- **Private client** — purple-leaning
- **Group** — blue-leaning
- **School program** — teal-leaning

---

## Typography

**SF Pro (iOS system) only.** No custom font files. Designer must pick from:
- SF Pro Display (large titles, big numbers)
- SF Pro Text (body, labels)
- SF Pro Rounded (only for stats — gives the digit display some warmth without going gimmicky)
- SF Mono (timestamps, monospaced digits in calendars / live timer)

**Type scale to define:**
- Hero number (the big 56pt count on attention card, hero stat readouts)
- Display (28–34pt, screen titles)
- Title 1 / 2 / 3
- Body
- Footnote
- Caption / Caption2
- Eyebrow (uppercase, tracked, monospaced — used for section labels like "TODAY'S BRIEFING")

Bilingual rule: **Chinese and Latin should sit on the same baseline at the same visual weight.** When a name is shown in both languages, neither dominates by accident. This is something the designer should solve explicitly.

---

## Spacing

- **Base unit: 4pt.** All spacing is 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40.
- Cards have generous internal padding (16–20pt horizontal, 12–16pt vertical).
- Between-card spacing: 16pt.
- List rows: 10–14pt vertical padding.
- Section headers: 8pt above content, eyebrow text style.

---

## Surfaces & depth

iOS 26 native materials. Use them, don't fight them.

- **`.regularMaterial`** — sheet backgrounds, modals, prominent toolbars
- **`.glassEffect(.regular, in: .rect(cornerRadius: 20))`** — primary cards (Today's Briefing, Attention, Today's Athletes)
- **Solid white (light) / `#1A1A1A` (dark)** — secondary cards
- **Hairline borders only on grouped lists** — never on cards (let elevation do the work)

Corner radii:
- Hero cards: 20–24pt
- Standard cards: 14–16pt
- Pills / chips: capsule
- Buttons: capsule (small) / 12pt rect (large)
- Photos: circle for avatars; 12pt rect for header bleeds

Shadows:
- Almost never use them. iOS materials handle elevation.
- The one exception: the printable card uses a real drop shadow because it's faking the look of a physical card.

---

## Iconography

**SF Symbols only.** No custom icons. Use:
- `.regular` weight by default, `.semibold` for emphasis
- Hierarchical rendering (`.symbolRenderingMode(.hierarchical)`) on filled-circle icons so they tint correctly with the surrounding accent
- `.fill` variants when the icon is doing chip-duty (inside a pill); otherwise outline

The system needs a list of the **canonical icons per concept** so screens stay consistent — e.g. `building.columns.fill` is always "school," `calendar` is always "session." Designer should produce this mapping for the top ~30 concepts in the app.

---

## Component archetypes

The designer needs to design these as a small library — every screen rebuilds from these:

### Atoms
- **Pill / chip** — icon + label, capsule, semantic-tinted
- **Stat cell** — big number + small label, optional trend arrow
- **Avatar** — circle, photo or initials fallback, optional ring
- **Eyebrow label** — uppercase tracked monospaced caption
- **Diamond grade badge** — currently A/B/C/S/— in a tilted square; designer can re-imagine the shape

### Composites
- **Hero card** — full-width, accent-tinted, big number + 1–2 supporting lines + optional CTA chip-row at the bottom (like the redesigned Attention card with category chips)
- **List row** — leading icon, two-line label, trailing trend / chevron / status — used everywhere (athletes, sessions, attention items)
- **Stats grid** — 3-column or 2-row × 3-column, monospaced digits, optional trend dashes
- **Hex radar** — 6-axis polygon, supports two overlapping shapes (lifetime + month) with legend
- **Calendar week strip** — 7 columns, weekday letters + dates + activity dots
- **Calendar month grid** — 7 × 6 cells, current-month vs. out-of-month dimming, today highlight, activity dots
- **Live activity pill** — persistent top-of-tabs indicator while a session is running (already in code)
- **Empty state** — `ContentUnavailableView` style, hierarchical icon + 1-line title + description

### Layouts
- **Tab bar** with sidebar-adaptable behavior (already in iOS 26 form)
- **NavigationStack** with large titles, no custom chrome
- **Sheet / fullScreenCover** with native drag indicator + standard detents

---

## Motion

Quiet. Use system defaults wherever possible.

- `.spring(response: 0.35, dampingFraction: 0.8)` for expand/collapse
- `.contentTransition(.numericText())` on stats and counters (already in heavy use — keep)
- `.symbolEffect(.pulse)` only on truly live indicators (live game pill, expiring timer)
- No bespoke transitions. No celebration animations. The numbers update, the user sees them update — that's enough.

---

## Print artifacts (player card specifically)

The print system inherits from the app system but has its own corner of the doc.

- 2.5″ × 3.5″ portrait, 300 dpi, 750 × 1050 px
- Uses the **same color tokens** as the app
- Type scale is its own (smaller — entire card needs to be readable at hand-held distance) but uses the same SF Pro family
- Photos / hero imagery can bleed full-width
- A separate token: `cardBleed` (0.125″) for print edge tolerance

Detailed brief in `PLAYER_CARD_BRIEF.md`.

---

## Accessibility (non-negotiable)

- Dynamic Type — all text must scale, no fixed-size body copy
- VoiceOver labels on every interactive element (most of these come for free with native components)
- Contrast ratios meet WCAG AA at minimum: 4.5:1 for body, 3:1 for large text
- Color is never the only carrier of meaning — pair with icon + label
- Light + dark mode are first-class (no light-only screens)

---

## Localization

Chinese (zh-Hans) is a first-class locale, not an afterthought.

- Design layouts to handle Chinese text being **shorter** in width (often 60–70% of the equivalent English) — don't have eyebrow labels that go from a clean line in EN to a tiny floating word in CN
- Numbers stay Western (Arabic numerals)
- Dates — never assume `MMM d` works in CN; defer to `Date.formatted()` with locale
- Bilingual name layouts get a dedicated component (handles `Alan` ↔ `沈铎` ↔ `Alan / 沈铎`)

---

## What I want back from the design tool

1. **Tokens.json** (or equivalent in the tool) — every color, type ramp, spacing step, radius, and elevation as a named token
2. **Component library** — a frame per atom + composite from the list above, in default + dark + key states (loading, empty, error)
3. **3 sample screens** showing the system in action:
   - Home dashboard (Briefing + Attention + Athletes cards)
   - Session detail with games tab + scrimmage timer + scoreboard
   - Player card (front + back) — link to the player-card brief
4. **Token mapping doc** — one page that says "this color = this Swift constant," "this type style = this `.font(...)`" so engineering can rebuild without ambiguity
5. **One paragraph of system rationale** — what choices were made and why, so we can defend them when the next request comes in

---

## Decisions you can make
- The hero brand accent (any single color, owned by Hoopwise — not a generic SaaS blue)
- Whether to use SF Pro Rounded for stat displays or stay with regular SF Pro
- Whether the system has a single `Card` archetype or two (`Card` + `HeroCard`)
- Specific corner radius values within reason
- Border treatment (where, when, how thin)

## Decisions to bring back to me
- Adding a custom font file
- Removing dark mode
- Removing bilingual support
- Switching the categorical avatar palette (10 colors are already used elsewhere — they're load-bearing)
- Adding a brand-new motion language (any non-spring transitions)

---

## How this evolves
The system is a living document. Versioned `v1.0`, `v1.1`, etc. When the next surface lands (we'll need a parent-app companion eventually, maybe a coach-staff multi-tenant version), the system grows — it doesn't fork.

Don't over-engineer for that yet. Build for what's in front of us.
