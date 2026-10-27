# T06 — UI baseline and view-model seam

## Goal
Promote the approved prototype UI into the production tree and put immutable
view-state objects between widgets and data, so real business logic can replace
in-memory prototype state without rebuilding the approved screens.

## Context (read first)
- Design: [13 §13.2–13.4, §13.7](../design/13-ui-implementation-contract.md),
  [06 §6.2](../design/06-app.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T05.
- Read [13 — UI/UX Implementation Contract](../design/13-ui-implementation-contract.md):
  the approved prototype is the visual contract, not a starting suggestion.

## Scope
- [x] Promote the prototype UI into the production tree.
- [x] Keep `features/`, `widgets/`, and `theme/` as the visual contract.
- [x] Introduce immutable `LiveViewState`, `HistoryViewState`, `SetupViewState`,
      `SettingsViewState`, and `BridgeDetailsViewState` objects.
- [x] Replace direct `PrototypeController` reads in widgets with view state.
- [x] Keep the scenario lab and fixture data behind a debug/test adapter,
      gated by `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`.
- [x] Move reusable formatters to the production formatter layer.
- [x] Make the screenshot generator run against the production screens.

## Out of scope
- BLE interface and fake — owned by T07.
- Real scan/live/sync data wiring — M2.
- History archive and chart data — M3.
- Settings actions and confirmations — M4.
- A UI redesign, new destination, second chart, probe names/roles, or new
  prototype chrome — outside MVP; the contract is
  [13](../design/13-ui-implementation-contract.md).
- Shipping the lab, fixture values, simulation buttons, or fake OS prompts in a
  release build — explicitly forbidden by the anti-tasks; T06 only gates them.

## Design notes
- The view states are **immutable**; widgets render from them and never read
  `PrototypeController` directly.
- `features/`, `widgets/`, and `theme/` define the approved visual contract and
  must not be redesigned while porting.
- The scenario lab is reachable only through a debug/test adapter, gated by
  `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`; it is not reachable from the
  release entrypoint.
- Reusable formatting logic moves to the production formatter layer rather than
  staying in prototype-only code.
- Screenshot generation targets the **production** screens so the approved
  baseline is validated against the real widget tree.
- Stable test keys and approved states come from
  [13](../design/13-ui-implementation-contract.md).

## Done when
- [x] Production screens render from view models.
- [x] The widget suite still covers the approved states.
- [x] The lab is not reachable from the release entrypoint.
- [x] `flutter analyze` passes.
- [x] `flutter test` passes.
- [x] Screenshot generation passes.
- [x] Hand-off below filled in.

## Hand-off

### Landed

- The approved prototype UI is the production tree. `features/`, `widgets/` and
  `theme/` keep their visuals; screens now render immutable view state.
- `app/lib/app/view_state.dart` defines `LiveViewState`, `ProbeView`,
  `BillowsView`, `HistoryViewState`, `SetupViewState`, `SettingsViewState` and
  `BridgeDetailsViewState`. `BridgeController` exposes `liveView`,
  `historyViewFor()`, `setupView`, `settingsView` and `bridgeDetailsView`.
- Live, History, the full-screen chart, Settings, Bridge details, Billows,
  About, History & storage, Appearance, Setup, Saved history and the OLED
  preview read view state. Controller access is limited to actions/navigation.
- `app/lib/domain/models.dart` holds the shared enums and chart/cook/stat types;
  `app/lib/domain/content.dart` is the `BridgeContent` data seam with
  `EmptyBridgeContent` as the production default.
- Fixture generators moved to `app/lib/debug/fixtures.dart`; the demo adapter
  (`DemoBridgeContent`, `demoBridgeController()`) moved to
  `app/lib/debug/demo_content.dart`. Production screens import neither.
- Production formatters moved to `app/lib/app/formatters.dart`; all prototype
  formatter/fixture imports are gone from the production tree.
- Scenario lab moved to `app/lib/debug/scenario_lab.dart`; the gate moved to
  `app/lib/app/lab_gate.dart` (`kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`).
  `SmokeBridgeApp`/`AppShell`/`SettingsScreen` accept an
  `enableExperimentalLab` override so release hiding is tested.
- Screenshot generator targets the production screens with a debug-seeded demo
  controller; existing approved PNGs are unchanged.
- Tests: new `app/test/view_state_test.dart` covers all five view states, the
  empty production content, controller-free `ProbeCard` rendering, release lab
  hiding and a production import guard. Existing widget tests now seed
  `demoBridgeController()`.
- Docs: ADR 0017, `docs/design/06-app.md`, `docs/design/13-ui-implementation-contract.md`,
  `docs/progress/T06.md`.

### Deviations and boundaries

- Real BLE/SQLite data is still out of scope (M2/M3). The production controller
  defaults to `EmptyBridgeContent`: four disconnected probes, no history, no
  cooks, `—` storage range. Tests, screenshots and the lab inject the demo
  adapter. This is intentional so no fixture value lives in the production path.
- The controller still contains prototype simulation timers/actions
  (`simulateSync`, `simulateSave`, `retryConnection`) and default bridge metadata
  (`deviceId`, `firmware`, battery, RSSI). Real wiring is M2/M4; T64 owns the
  release/no-simulation gate.
- The shell still imports the debug lab in debug builds; only the entry is gated.
  A hard release import-graph check remains T64.
- Full locale-aware date/time output remains T53; T06 moves the formatter layer
  and keeps the existing `use24Hour` plumbing.

### Checks run

```text
cd app && flutter analyze                    -> No issues found
cd app && flutter test                       -> 38 tests passed
cd app && flutter test tool/ui_screenshots_test.dart -> 29 tests passed
make app-check                               -> analyze clean, 38 tests passed
```

`flutter test --update-goldens tool/ui_screenshots_test.dart` regenerates the
same approved set from the production screens if a future intentional UI change
needs it.

### Next task must know

- Inject BLE/data through `BridgeContent` or a new provider behind
  `BridgeController`; do not re-add fixture reads to screens.
- Use `demoBridgeController()` in tests/screenshots; plain `BridgeController()`
  is the honest empty production state.
- Keep `features/`, `widgets/` and `theme/` unchanged while wiring data.
- `docs/progress/T06.md` records the reusable commands and gotchas.
