# 0017 - Immutable view-state seam over the approved UI

## Status

Accepted

## Context

T05 moved the controller into the production tree but the approved screens still
read mutable prototype-shaped fields directly. Live sparklines and History chart
data also imported prototype fixture builders. That makes M2/M3 data wiring a
screen rewrite instead of a source swap, and it lets fixture values leak into the
release widget graph. The UI contract requires the approved visuals to stay
fixed while only the state source changes.

## Decision

Introduce immutable view state in `app/lib/app/view_state.dart`:
`LiveViewState`, `ProbeView`, `BillowsView`, `HistoryViewState`,
`SetupViewState`, `SettingsViewState` and `BridgeDetailsViewState`.
`BridgeController` builds them in `liveView`, `historyViewFor()`, `setupView`,
`settingsView` and `bridgeDetailsView`. Screens and shared widgets consume those
objects; they may call controller methods for actions but must not read mutable
fields for display. Formatting lives in `app/lib/app/formatters.dart`.

Move the data seam to `app/lib/domain/content.dart`. `BridgeContent` supplies
probe temperatures, sparklines, history, cooks and storage metadata. Production
uses `EmptyBridgeContent` until M2/M3 wire BLE and SQLite. Fixture generators and
the demo adapter live in `app/lib/debug/` and are consumed only by tests, the
screenshot tool and the Experimental lab. Production files must not import
`debug/fixtures.dart` or `debug/demo_content.dart`.

The lab entry is gated by `app/lib/app/lab_gate.dart`
(`kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`). `AppShell`/`SmokeBridgeApp` accept an
`enableExperimentalLab` override so a release-mode test can prove the entry point
is hidden.

## Consequences

- Screens render deterministic, pre-formatted state and are cheaper to test.
- M2/M3 replace `BridgeContent` without touching the approved widget tree.
- Tests and screenshots seed `demoBridgeController()`; the production controller
  below the UI has no fixture values.
- The lab source is still imported by the shell in debug builds; T64 owns the
  hard release import-graph gate and final parity walk.
- Full locale-aware date/time formatting remains T53; T06 only moves the
  formatter layer.
