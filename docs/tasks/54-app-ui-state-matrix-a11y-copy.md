# T54 — app: UI state matrix, accessibility and copy gate

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
- Depends on T42, T45, T52 and T53.

## Scope
- [ ] Add widget tests for every state in 13 §13.4 that is reachable without hardware: Setup, Live, History, Settings, Bridge details, confirmations, Cook view and the product error/empty states.
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
- Fixing product states that earlier tasks own (Settings root T50, Bridge details T51, destructive flows T52, units/time T53); this task adds the gate and reports failures back.
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
- Stable settings keys: `settings.bridge.status`, `settings.history.logs`, `settings.units`, `settings.appearance`. Bridge keys: `bridge.name`, `bridge.timeout`, `bridge.billows`, `bridge.repair`, `bridge.connectionLog`.
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
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
