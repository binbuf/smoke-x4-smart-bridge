# N9 — Catalog & setup

**Goal:** the catalog-as-setup flow and the three ways to start a cook. This is
the flexibility requirement from `Start.md`: set up before, during, or after the
fire is lit, including hooking into data already collected.

**Design:** [`newui/app.js`](../app.js) §7 `overlaySetup`, `setupScrim`,
`modeCardCompact`, `overlayCustomFood`, `requestAdd`, `addItemToCook`,
`adoptCook`, `openConfirm` · `newui/NOTES.md` §2.2–§2.3, §5, §7.5–§7.7 ·
`mock-data.js` CATALOG/STYLES/TIMELINES.

---

## The three start modes (NOTES §5)

| Mode | Meaning | Code path |
|---|---|---|
| `new` | Set up before you light the fire; pick cut/doneness/probe/reminders | `CookRepository.startFromPlan` |
| `existing` | Hook into data already collected; backdate + pull samples | `CookRepository.backdate` + high-water-mark sync |
| `watch` | No targets, no timers, no alarms; instrument mode; a cook can be added later | no cook created |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N9.1 | Setup sheet with `new` / `existing` / `watch` segmented switch + mode-specific sub copy | N4.6 | W | `app.js` overlaySetup |
| N9.2 | `watch` mode: notice + "Watch live temperatures" primary | N9.1 | W | `app.js` overlaySetup |
| N9.3 | `existing` mode: session-found card (id, started, samples) + "when did it go on?" (bridge session start / set a time) | N9.1, N2.18 | W | `app.js` overlaySetup, NOTES §5.2 |
| N9.4 | Catalog search across **all 139 foods** (name/category/blurb), live count, clear button | N2.1 | W | `app.js` catalog-search |
| N9.5 | Category filter chips (10), search overrides the category | N9.4 | W | `app.js` filter-row |
| N9.6 | Catalog tiles: avatar, name, Custom badge, blurb, target+pit band, "N styles" | N9.5 | W | `app.js` catalog-item |
| N9.7 | Preparation-style picker ("N ways to cook <cut>") with `region` badge + tagline + note | N1.8, N9.6 | W | `app.js` style-grid, NOTES §2.2 |
| N9.8 | Doneness chips from the selected preset; **red meat defaults to medium rare** | N1.6, N9.6 | W | `Start.md`, `app.js` doneness |
| N9.9 | Summary card: target (after rest), pull-by-carryover, expected rest, expected cook range | N1.7, N1.9 | W | `app.js` overlaySetup |
| N9.10 | Probe assignment: jacks 1–4, busy jacks disabled with "(in use)", jack 4 tagged "grate" | N9.8 | W | `app.js` catalog-jack, NOTES §7.2 |
| N9.11 | Wrap/spritz reminder toggle from the expected timeline | N8.9 | W | `app.js` overlaySetup |
| N9.12 | Start buttons per mode: Start cook / Start & pull history / Watch live; disabled until a food is picked (reason on screen) | N9.9 | W | `app.js` overlaySetup, I5 |
| N9.13 | `startCook`: create cook, assign item, set probe role/target/pull, close + go Live + toast | N9.12 | S | `app.js` addItemToCook |
| N9.14 | `requestAdd` long-item guard: warn when a new item would finish >15 min after everything else; confirm sheet with computed delay | N9.13 | W | `app.js` requestAdd |
| N9.15 | `adoptCook`: create cook backdated to the bridge session, assign item, pull sample count, toast | N9.3, N2.14 | S | `app.js` adoptCook, NOTES §5.2 |
| N9.16 | Adopt banner + adopt modal (samples/kept/start time stated before the action) | N5.3, N9.15 | W | `app.js` overlayAdopt, I8 |
| N9.17 | Custom-food form: name, category, glyph, hazard class, thickness, pit band, target, rest, cook range, wrap temp, spritz | N2.1 | W | `app.js` overlayCustomFood |
| N9.18 | Custom food stored with its own `timeline`, bypassing `TIMELINES`; re-runs the safety gate | N9.17, N1.16 | H | NOTES §2.2, I12 |
| N9.19 | "Add food" while a cook runs appends to it (same flow, edit context) | N9.14 | W | `app.js` open-setup |

## Exit gate

All three modes complete end to end against the mock; the `existing` mode pulls
and displays the collected sample count; the long-item warning appears for a
deliberately long add; search finds a cut by name, category and blurb.

## Must-not-regress

I5, I8, I10 (adopt only annotates; it never rewrites samples), I12 (safety gate on
preset and custom targets), and red-meat medium-rare default.