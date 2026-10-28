---
hitl: true
---
# T54 - app: UI state matrix, accessibility and copy gate

## Goal
Turn the prototype review into a production gate: every reachable UI state has a widget test, both themes are regenerated from production widgets, and accessibility plus banned-term copy checks run in CI. This is the evidence that Settings and the rest of M4 match the approved contract.

## Context (read first)
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — complete state inventory; the matrix this task must cover.
- [13 §13.6](../design/13-ui-implementation-contract.md#136-visual-interaction-and-accessibility-contract) — width, themes, type, touch, status, motion, charts, copy and formatting rules.
- [13 §13.8](../design/13-ui-implementation-contract.md#138-evidence-and-test-keys) — required evidence and stable test keys.
- [12 §12.3](../design/12-copy-and-label-review.md) — remaining copy/UX gaps before release.
- [12 §12.6](../design/12-copy-and-label-review.md) — banned terms and copy lint.
- `app/test/widget_test.dart` — existing widget suite.
- `app/tool/ui_screenshots_test.dart` — screenshot generator for the committed dark/light set.
- **Verify:** H · **Board:** no
- Depends on T42, T45, T46a, T52 and T53.
- **Post-T36 status:** `ui_state_matrix_test.dart` already renders seven states
  at 320/390 dp in both themes, and `tool/ui_screenshots_test.dart` is the
  golden generator. The post-T36 connection chain, X4 warning dialog, probe
  Min/Max line and `Live change window` are not yet in the contract tests; T54
  owns their state rows, copy and screenshots.

## Scope
- [ ] Add widget tests for every state in 13 §13.4 that is reachable without hardware: Setup, Live, History, Settings, Bridge details, confirmations, Cook view and the product error/empty states.
- [ ] Add the post-T36 Live states: separate BLE/LoRa signal meters and
      durations, the amber X4 warning dialog, probe Min/Max range line, and the
      signed change for each `Live change window` value.
- [ ] Add 320 dp and 390 dp layout tests for Live, History, Settings and the Cook view; assert no overflow.
- [ ] Regenerate the dark/light screenshot set from the production widgets, review it intentionally, and commit it.
- [ ] Add semantics for the connection card, probe tiles, chart summary, filter menus, Summary rows and destructive actions.
- [ ] Audit WCAG AA contrast and 48 dp targets for chart controls and destructive buttons; fix failures.
- [ ] Centralize product strings in one place; use locale date/time/number formatting.
- [ ] Add the banned-term copy test from 12 §12.6, case-insensitive, with allow-listed context for technical docs and the Experimental lab.
- [ ] Verify reduced-motion behaviour and that no state relies on colour alone (label and icon accompany colour).
- [ ] Preserve or deliberately rename the stable test keys from 13 §13.8, updating tests when a key changes.
- [ ] Prove the gate catches regressions: a deliberately injected banned term makes the copy test fail, and a deliberately bad state/screenshot change is not silently accepted.

## Out of scope
- Fixing product states that earlier tasks own (Settings root T50, Bridge details T51, destructive flows T52, units/time T53); T46a owns the T46 History/connection corrections. This task adds the gate and verifies them.
- Implementing new screens or new state that 13 §13.4 does not define — outside MVP; no task owns it.
- Release-build Experimental lab gating and the final parity walk → release hardening (T61–T68); this task keeps the shared debug/`ENABLE_EXPERIMENTAL_LAB` gate and checks for fixture strings.
- Billows bench/observation evidence → M5 Billows (T56–T60).
- Firmware host tests → T47–T49.

## Design notes
- Evidence required before this task is done (13 §13.8): `flutter analyze` and `flutter test` clean; widget tests for every state the task owns; dark and light screenshots at 390 × 844; a 320 dp layout test for Live, History and Settings; no overflow, raw exception or fixture text in the production tree; screen-reader semantics for the connection card, probe tiles, chart summary, filters, Summary rows and destructive actions; screenshot/golden changes reviewed intentionally.
- Widths: the UI must work at 320 dp and scale up. 390 dp is the reference screenshot width. Chart, Summary and Cooks are the stress points.
- Touch: every actionable target ≥48 dp, including chart controls, filter menus, rows and destructive actions.
- Themes: dark and light are both first-class. Status uses a label and an icon in addition to colour. No colour-only state.
- Motion: 150–220 ms ease-out; range changes crossfade; reduced-motion is respected; no bouncy or decorative animation.
- Type: tabular figures for every temperature/axis; Live value 40–46 px; chart labels ≥11 px; body 14–15; labels 11–12.
- Charts: never connect across a gap; no zero for missing data; Summary is the accessible table equivalent; the chart has a screen-reader summary.
- Copy: sentence case for buttons/labels; product names keep their casing; no raw exceptions or platform error strings; no “simulated” text on product screens.
- Banned terms (12 §12.6, case-insensitive, allow-listed for technical docs and the lab):

  ```
  Graph, Probe history, Dashboard, Monitor (as a tab), Now (as a tab)
  Saved data, Device log, Bridge log, Bridge storage (as a copy of history)
  Records, Plot points, Samples (user copy), Sessions
  Aging, Stale, Frozen (user-facing)
  Last contact, No new 4m, No new 12m
  Attached, Reporting, Fan running, Fan speed
  Read-only (for the whole app), Monitor only, Observe mode
  Bonding, Bonded (user copy), Connect to GATT, Secure characteristics
  Current cook, Cook started (as a user concept), Set target
  Simulated, Simulation, Prototype, in this build, there is no OTA path
  MTU, RSSI, GATT, characteristic, backfill, ring, sector, generation
  ```

  `Cooks` is allowed; `cook sessions` is not. `Technical details` may contain `MTU`/`RSSI`; the main status card may not.
- Stable settings keys: `settings.bridge.status`, `settings.history.logs`, `settings.units`, `settings.tempChangeWindow`, `settings.appearance`. Bridge keys: `bridge.name`, `bridge.timeout`, `bridge.billows`, `bridge.repair`, `bridge.connectionLog`. Live keys: `status.appBridgeLink`, `status.x4Link`, `live.smokeXWarning`.
- Screenshot command: `flutter test --update-goldens tool/ui_screenshots_test.dart`. Review the diff before committing; do not accept golden changes blindly.
- No fixture, simulation, lab-only control or fake success may be reachable in a release build.
- Design: [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory), [13 §13.6](../design/13-ui-implementation-contract.md#136-visual-interaction-and-accessibility-contract), [13 §13.8](../design/13-ui-implementation-contract.md#138-evidence-and-test-keys), [12 §12.6](../design/12-copy-and-label-review.md).

## Done when
- [ ] The 13 §13.4 state matrix is green for every state reachable without hardware.
- [ ] 320 dp and 390 dp layout tests pass for Live, History, Settings and the Cook view with no overflow.
- [ ] The dark/light screenshot set is regenerated from production widgets, reviewed and committed (390 × 844).
- [ ] The copy-lint test fails on a deliberately injected banned term and passes on the production strings.
- [ ] Accessibility checks pass on a 320 dp phone: WCAG AA contrast, 48 dp targets, semantics for connection/probes/chart/filters/Summary/destructive actions, reduced motion and no colour-only state.
- [ ] No fixture or simulation string reaches a product screen.
- [ ] `flutter analyze` is clean and `flutter test` passes.
- [ ] Hand-off below filled in.

## Hand-off

**Status:** done for the host/app evidence; physical-phone walk stays T55.

### What landed
- `app/test/ui_state_matrix_test.dart` now covers every 13 §13.4 state reachable
  without hardware (all 19 Setup steps; healthy/aging/stale/lost/syncing/
  backfill/sync-failed/reconnecting/failed/blocked/offline/no-probe/detached/
  no-sparkline/storage-failure/Billows/X4-warning Live states; History default,
  custom, filter, help, cooks, empty, all-saved and offline; Cook view;
  full-screen chart; Settings/Bridge details/history & storage/appearance/about/
  Billows/re-pair/saved history/bridge-off and all destructive confirmations).
  Every row renders at 320 dp and 390 dp in dark and light with no overflow.
  The 13 §13.8 stable keys are asserted.
- `app/test/live_post_t36_test.dart` covers the post-T36 Live chain: separate
  BLE/LoRa meters with semantics and durations, probe Min/Max, a signed change
  for 1/5/10/15/30/60 min, and the amber X4 warning dialog.
- `app/test/accessibility_test.dart` gates WCAG AA contrast, 48 dp targets,
  screen-reader semantics (connection card, radio links, probe tiles, chart
  summary, filters, Summary rows, destructive actions), reduced motion and
  label-plus-icon status.
- `app/test/copy_lint_test.dart` implements the 12 §12.6 banned-term scan over
  product string literals, case-insensitive, interpolation-aware, with only the
  Technical details `MTU`/`RSSI` labels and the approved “The Bridge records…”
  sentence allow-listed. It includes a deliberately injected banned-term case.
- Screenshots: all 38 goldens regenerated from production widgets at 390 × 844,
  nine new shots including the X4 warning dialog and light variants.
  `screenshots/manifest.json` + `screenshot_manifest_test.dart` make any changed
  or added PNG fail until reviewed and the manifest regenerated; a one-byte
  mutation test proves the hash catches a change.
- Product fixes made to pass the gates: shared `app/lib/app/strings.dart` copy
  catalogue used by Live/History/Settings; `AppMotion` reduced-motion policy
  used by Setup; darker light-theme primary/error/status/probe colours for
  4.5:1; 48 dp filter menus, chart help/full-screen, `Now` and range buttons;
  scrollable chart help and a 320 dp-safe custom-range row; banned copy fixed
  (Billows “attached”, “Cook started”, OLED “simulated”); sparkline spacing is
  now one minute so every change window has a signed delta.

### Commands / results
```powershell
cd app
flutter analyze                              # No issues found
flutter test --timeout 180s                  # 373 tests, all passed
flutter test tool/ui_screenshots_test.dart   # 38 shots matched
dart run tool/screenshot_manifest.dart       # 38 manifest entries
cd ..
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1
# 25/25 CTest passed, exit 0
```

### Deviations
- The screenshot diff is gated by a committed hash manifest in `flutter test`
  rather than by adding the golden generator to `app-test`; the reviewed update
  sequence is update-goldens → manifest → visual diff (ADR 0059). This keeps
  the normal suite fast and still refuses an unreviewed pixel change.
- `AppStrings` centralises the shared T54 surfaces; a few one-off screen strings
  remain inline and are listed as a T64 follow-up.
- Light theme tokens changed for WCAG AA, so the light goldens intentionally
  differ in hue/darkness.

### Changed docs
- `docs/design/13-ui-implementation-contract.md` §13.8 — concrete gate files.
- `docs/design/12-copy-and-label-review.md` §12.6 — gate location/allow-list.
- `docs/design/adr/0059-ui-evidence-gates.md` — new decision record.
- `docs/progress/T54.md` — reusable commands, gotchas and follow-ups.

### Remaining work / next
- **T55:** physical 320 dp phone walk and real-Bridge before/after screenshots;
  host tests cannot replace the device pass.
- **T64:** add the golden/manifest command to release CI and prove the lab gate
  in a release build; finish migrating one-off strings to `AppStrings`.
