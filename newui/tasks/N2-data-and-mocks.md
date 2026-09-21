# N2 — Data, content tables and mocks

**Goal:** port the prototype's `mock-data.js` into typed Dart content tables and a
`BridgeRepository` interface with a `MockBridgeRepository` implementation, so
every screen can be built and tested before any radio code exists. N15 swaps the
implementation; no screen may know which one is live.

**Design:** [`newui/mock-data.js`](../mock-data.js) (the whole file) ·
[`newui/app.js`](../app.js) §4, §8 · `newui/NOTES.md` §2.2, §4, §5.

---

## 2.1 Content tables (the reviewer-owned data)

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N2.1 | `Catalog` entry model: id, category, name, glyph, hazard, thickness, pitBand, blurb, doneness[], defaultDoneness, `tl` seed | N1.6 | H | `mock-data.js` CATALOG |
| N2.2 | Port **Beef** (19) | N2.1 | H | `mock-data.js` |
| N2.3 | Port **Pork** (14) | N2.1 | H | `mock-data.js` |
| N2.4 | Port **Poultry** (15) | N2.1 | H | `mock-data.js` |
| N2.5 | Port **Seafood** (22) | N2.1 | H | `mock-data.js` |
| N2.6 | Port **Lamb** (7) + **Game** (8) | N2.1 | H | `mock-data.js` |
| N2.7 | Port **Veggies** (23) + **Sides** (17) | N2.1 | H | `mock-data.js` |
| N2.8 | Port **Misc** (6) + **Desserts** (8) | N2.1 | H | `mock-data.js` |
| N2.9 | `CATEGORIES` (10) as data-driven, not hard-coded in the picker | N2.1 | H | `mock-data.js` |
| N2.10 | Port `STYLES`: ~318 named variants over 133 cuts; each sets pit band/wrap/spritz/target/rest/timeline + `region` | N1.8, N2.1 | H | `mock-data.js` STYLES |
| N2.11 | `normalizeTimeline()`: derive `TIMELINES` for **every** catalog entry; synthesize when `tl` is absent; `buildPhases` | N1.9, N2.1 | H | `mock-data.js` normalizeTimeline |
| N2.12 | Content validation test: every catalog id has a timeline; every style maps to a real preset; no target below its hazard floor | N1.5, N2.11 | H | research notes I12 |
| N2.13 | A **named reviewer** field on the catalog + timeline tables (same class of data as `presets.dart`) | N2.11 | H | NOTES §4 |

## 2.2 Mock situations

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N2.14 | `BridgeSnapshot` freezed: connection (dual-link), cook, probes[4], alarms, marks, pendingSession, notice | N1.4 | H | `mock-data.js` scenario shape |
| N2.15 | `ConnectionState` model: `phase` (connected/connecting/offline/provisioning/rollback/error), `primary`, independent `bt`/`wifi` links with health | N2.14 | H | `mock-data.js` connection helpers, NOTES §2.4 |
| N2.16 | Scenario `running` (Wi-Fi + BLE warm, brisket/ribs/sausage, pit-crash + eta alarms) | N2.14 | H | `mock-data.js` SCENARIOS |
| N2.17 | Scenario `idle` (instrument mode) | N2.14 | H | `mock-data.js` |
| N2.18 | Scenario `existing` (bridge session already recording, BLE) | N2.14 | H | `mock-data.js` |
| N2.19 | Scenario `offline` (frozen/stale, bridge-unreachable insight) | N2.14 | H | `mock-data.js` |
| N2.20 | Connection-matrix scenarios: `bt_only`, `sta_connecting`, `sta_wrong_password`, `sta_router_unreachable`, `ap_broadcasting`, `ap_joined`, `switch_rollback` | N2.15 | H | `mock-data.js` SCENARIOS |
| N2.21 | `History` fixtures (7 past cooks with planned-vs-actual, marks, ratings, favourites) | N2.14 | H | `mock-data.js` HISTORY |
| N2.22 | `MODES` (ble/ap/sta) with capability flags + plain-language good/limited copy | N2.15 | H | `mock-data.js` MODES |
| N2.23 | `ALARM_RULES`: 9 device + 3 app insights, tier/severity/scope/window | N1.4 | H | `mock-data.js` ALARM_RULES |
| N2.24 | `DEVICE` + `FIRMWARE` fixtures (identity, heap/storage/logs, release notes, rollback promise) | — | H | `mock-data.js` DEVICE/FIRMWARE |
| N2.25 | `AppSettings` freezed: units, themeMode, displayProfile, density, reducedMotion, preferManualAlarm, quietHours, monitoring, holdBle, autoWrapReminder, otaChannel, forceOta, customCatalog | N2.14 | H | `mock-data.js` settings |
| N2.26 | `MockEventBus`: fire `ble-connected`, `ble-dropped`, `wifi-*`, `ap-*`, `switch-rollback`, `resync-complete`, `alarm-*`; each mutates the active snapshot | N2.20 | H | `app.js` §8 fireEvent, EVENTS |

## 2.3 Repository seam

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N2.27 | `BridgeRepository` interface: `snapshot()` stream, `resync()`, `connect()/disconnect()`, `adoptSession()`, `startCook()/addItem()/markPulled()`, `mark()`, `ackAlarm()`, `probeRole()/setTarget()`, `applyMode()`, device verbs | N2.14 | H | NOTES §6 |
| N2.28 | `MockBridgeRepository implements BridgeRepository` over the scenario fixtures + event bus | N2.27 | H | `app.js` §8 |
| N2.29 | `PrefsRepository` (mock, in-memory) for `AppSettings`; real `shared_preferences` impl deferred to N15 | N2.25 | H | NOTES §2.1 |
| N2.30 | Riverpod providers: `bridgeRepositoryProvider`, `prefsProvider`, `settingsProvider`, `snapshotProvider` (stream) | N2.27, N2.29 | H | — |
| N2.31 | Dev-only scenario/screen/event switcher panel (the prototype's right-hand panel), compiled out of release | N2.28, N2.30 | W | `index.html` devpanel, `app.js` §5 |
| N2.32 | Deep links: `?screen=`, `?overlay=`, `?scenario=`, `?units=` for rapid iteration | N2.31 | W | `index.html` boot |

## Exit gate

Every scenario in the dev panel loads its screen with the prototype's values;
`dart test test/domain test/data` green; content validation passes. No widget
imports `mock-data` directly — everything reads `BridgeRepository`.

## Must-not-regress

The repository is the **only** source of truth for screens (D3). Scenarios must
reproduce the exact prototype numbers so UI comparisons are valid.

## Hand-off

**Status: continue.** N2.1–N2.30 landed and green; N2.31/N2.32 landed as a
tested pure-Dart control layer, but their **widget + boot wiring** remain and
need the N4 shell/screens (there are no destinations to route to yet).

### What landed
- `app/lib/data/content/` — `catalog_data.dart`, `styles_data.dart`,
  `fixtures_data.dart` (generated by `node app/tool/gen_mock_content.mjs` from
  `newui/mock-data.js`); `timelines.dart` (`normalizeTimeline`/`buildPhases`,
  reviewer field); `catalog.dart` (`CatalogTable`, `kCatalogTable`); and
  `scenarios.dart` (all 11 scenario fixtures + `freshProbes()`).
- `app/lib/data/model/` — `catalog_entry.dart`, `connection_state.dart`
  (dual-link `ConnectionState`/`LinkState`), `cook_state.dart` (`CookState`,
  `ProbeState`), `bridge_snapshot.dart` (`BridgeSnapshot` freezed + `Scenario`),
  `app_settings.dart` (freezed), `alarm.dart`, `alarm_rule.dart`,
  `connection_mode.dart`, `device_info.dart`, `history_entry.dart`,
  `mock_event.dart`.
- `app/lib/data/repository/` — `bridge_repository.dart` (interface, `DeviceVerb`),
  `mock_bridge_repository.dart`, `mock_event_bus.dart`, `prefs_repository.dart`
  (`MockPrefsRepository`).
- `app/lib/data/providers.dart` (Riverpod: bridgeRepository, prefs, settings,
  snapshot, history), `data.dart` (pure-Dart barrel), `dev_panel.dart`
  (`DevScreen`, `DevOverlay`, `DevDeepLink.parse`, `DevPanelController`).
- Tests `app/test/data/`: `content_validation_test.dart`, `timeline_test.dart`,
  `mock_repository_test.dart`, `settings_test.dart`, `dev_panel_test.dart`.

### Commands + real results
- `cd app && dart test test/domain test/data` → **129 passed** (87 domain + 42 data).
- `cd app && flutter test` → **142 passed** (includes the golden harness).
- `cd app && flutter analyze` → No issues found.
- `cd app && dart format --output=none --set-exit-if-changed lib test` → 0.
- Regenerate content: `node app/tool/gen_mock_content.mjs` (from `app/`).

### Deviations / decisions (later tasks must know)
- **Counts differ from the task text.** `mock-data.js` now holds **139 cuts**,
  **139 styled cuts** and **331 styles** (task said ~318 over 133). The test
  pins 139/331/139, not the stale numbers.
- **Two cuts have one style, not two:** `game_antelope`, `game_squirrel`. The
  validation requires ≥1 style per cut, not ≥2.
- **Below-floor targets are pinned, not removed.** The prototype deliberately
  carries raw/rosé/cold-serve rungs below the class floor (sashimi tuna, rosé
  duck/duck breast, warm ham, 140 °F lobster/crab, 160 °F rabbit, cold sides).
  Exact numbers are a must-not-regress, so `content_validation_test.dart` pins
  the exact exception sets and fails on any new unsafe rung. `unstated` catalog
  entries are non-meat content, so N1's unstated floor is **not** applied to
  them in validation. **N9 must not apply the 160 °F unstated floor to the
  vegetable/side/dessert entries** — see PROGRESS follow-up.
- `ProbeState` is the data-layer probe value (role/target/pull/`etaNote` added);
  `ProbeState.reading` maps to the N1 `ProbeReading` and applies the I4 gate
  (frozen/stale ⇒ trend and ETA are null). No domain files were changed.
- `AppSettings` uses data-layer enums (`AppThemeMode`, `DisplayProfile`,
  `Density`, `OtaChannel`), not Flutter's `ThemeMode`.
- Deep-link `units` maps to `TempUnit` (`C`/`F`); unknown values are dropped.
- Generated content files are committed. `make app.gen` (build_runner) only
  covers freezed; it does **not** regenerate the content tables.

### Remaining (for the next session / N4)
1. **N2.31 widget** — render the right-hand panel (scenarios / screens /
   overlays / events) from `DevPanelController`, gated by `kReleaseMode`.
2. **N2.32 boot wiring** — call `DevPanelController.applyLocation` from the
   router/boot and route `DevScreen`/`DevOverlay` to the N4 destinations.
   `DevDeepLink.parse` and `DevPanelController.apply` are already tested.
3. The exit-gate sentence "every scenario loads its screen" can only be met once
   N4's shell exists; the fixtures and the controller are ready for it.