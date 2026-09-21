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

---

## Hand-off

**Status: done.** All three start modes run end to end against the mock; the exit
gate's checks are automated. `make app.test` green (**409** tests, N9 adds 39);
`dart test test/domain test/data` green (**139**); `flutter analyze` and the
format check are clean; no golden changed.

### What landed
- `app/lib/features/setup/` — `setup_format.dart` (pure projections),
  `setup_sheet.dart` (`SetupSheetBody`), `custom_food_sheet.dart`
  (`CustomFoodSheetBody`), barrel `setup.dart`.
- `features/shell/overlay.dart` resolves `DevOverlay.setup` and
  `DevOverlay.customFood` to the real bodies. Setup reads `context=edit` (label
  "Add to cook"), `jack` (initial jack) and `food` (preselect after custom save).
- `BridgeRepository.startCook`/`addItem` gained optional `pullF10`, `timeline`,
  `wrap`, `spritz`; `startCook` also `startedAtMs` and `adoptPendingSession`
  (N9.15). Mock implemented; old call sites unchanged.
- `CustomFood` gained `glyph`, `thickness`, `blurb` (additive defaults).
- Tests: `app/test/features/setup_format_test.dart` (20 pure),
  `app/test/features/setup_test.dart` (17 widget, incl. the overlay wiring), and
  2 new `app/test/data/mock_repository_test.dart` cases.

### Exit gate evidence
- `cd app && flutter test test/features/setup_test.dart test/features/setup_format_test.dart` → 37 pass.
- Search by name/category/blurb, category override, live count and clear: pure tests.
- `existing` mode pulls + displays the session sample count (253) and backdates
  the cook: widget test + repo test.
- Long-item warning for a deliberately long add, then "Add anyway": widget test.
- Red-meat medium-rare default (135 °F on ribeye): pure + widget tests.
- Custom food stored with its own timeline; below-floor target refused (I12).

### Deviations from the plan (and why)
1. **Mode-specific sub copy lives in the body** (`setup-mode-sub`), not the
   sheet header: `resolveOverlay` is mode-agnostic. The sheet title is `Cook setup`
   for every mode (the prototype's `setupScrim` picks `New cook` for new/existing).
2. **I12 runs on custom targets only.** The catalog's below-floor rungs are
   reviewer-pinned by `content_validation_test.dart`; re-gating them in setup
   would fight the content owner. `CookPlan`'s constructor is still the gate for
   a real plan.
3. **`adoptCook` is `startCook(adoptPendingSession: true)`** rather than a new
   repository method. The Live adopt banner/modal (N9.16) already exists from N5.
4. **Long-item confirm uses `showModalCard`** (imperative) rather than the
   `confirm` named overlay, which needs no props plumbing and returns a bool.

### What the next task must know
- Extended repo signatures: N15 must implement them on the real transport and
  serialise the new `CustomFood`/`CookItem` fields.
- Custom foods persist in `AppSettings.customCatalog` (prefs); the picker reads
  them via `settingsProvider`. No repository method was added for them.
- `confirm`, `alarms`, `firmware`, … overlays remain placeholders owned by later
  tasks.
