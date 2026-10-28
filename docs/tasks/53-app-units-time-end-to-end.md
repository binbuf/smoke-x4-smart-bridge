# T53 — app: units and time end-to-end

## Goal
Make one conversion path and one formatting layer govern every screen: Live, sparklines, History, Cook view, Billows, confirmations, storage counts and the OLED. The clock is set from the phone once per connect, and units, theme and locale persist across relaunch.

## Context (read first)
- [04 §4.4](../design/04-data-and-storage.md) — time without an RTC, the 2 s clock rule and estimated times.
- [06 §6.7](../design/06-app.md) — units, Appearance and save model.
- [13 §13.5](../design/13-ui-implementation-contract.md#units-theme-and-locale) — units, theme and locale rules.
- [13 §13.6](../design/13-ui-implementation-contract.md#136-visual-interaction-and-accessibility-contract) — formatting and tabular figures.
- [05 §5.5](../design/05-ble-contract.md) — `set_time` body `unix_ms u64, tz_offset_min i16`.
- [05 §5.9](../design/05-ble-contract.md) — `config.units` affects the OLED; stored samples are always °F.
- `app/lib/features/live/` — Live tiles and sparklines.
- `app/lib/features/history/` — History axis, tooltip, Summary and Cook view.
- **Verify:** H/P · **Board:** no / phone
- Depends on T51, T35 and T29.
- **Post-T36 status:** units, Appearance and the new `Live change window` are
  already wired through `BridgeController` and repaint in the same frame. They
  are process-local only. T53 adds the persisted store, the launch restore and
  the remaining locale/formatting coverage; it does not add a second conversion
  path.

## Scope
- [ ] Wire `set_time` into the connect path exactly once per connect, sending `unix_ms` and `tz_offset_min` when the bridge clock differs by more than 2 s.
- [ ] Implement one conversion path used by every temperature surface: Live tiles, sparklines, History axis, tooltip and Summary, Cook view, Billows target readout, confirmations, storage counts and the OLED.
- [ ] Apply the theme and locale formatting at the same layer as conversion, not per-widget.
- [ ] Persist the unit choice, Appearance and `Live change window` across app relaunch; apply the saved theme and window on launch.
- [ ] Repaint every visible temperature and probe change value in the same frame when units or the change window changes; no screen keeps the old unit until it is reopened.
- [ ] Keep stored samples in °F. The unit only changes presentation and the OLED setting.
- [ ] Respect the device locale and 12/24-hour setting for dates and times; no hard-coded `AM`/`PM`.
- [ ] Use locale number formatting for counts and storage (`128,430`, not `128430`).
- [ ] Use `P1`–`P4` for probe identity. There are no probe labels to wire; probe identity is order and colour.
- [ ] Make Billows target display read-only and converted through the same unit path.
- [ ] Wire the OLED units and timeout config through the same setting state that the app uses.
- [ ] Add unit/domain tests for conversion and formatting, and widget tests that a live unit change updates Live, History, Cooks and Billows in the same frame.
- [ ] Bench-verify on a real phone that a unit change survives relaunch and that the clock is set correctly on connect.

## Out of scope
- `config` characteristic layout, persistence and firmware validation → T47.
- Firmware `set_time` / clock implementation → T29.
- BLE connect/secure/sync lifecycle and reconnect backoff → T35.
- Settings editors for name, timeout and Appearance → T51.
- Destructive flows and loss copy → T52.
- Full UI state matrix, accessibility, goldens and copy-lint gate → T54.
- Billows control or setpoint editing → M5 Billows (T56–T60); `caps.billows_control` is always 0.
- Probe names, roles or labels — removed from the MVP; outside MVP, no task owns it.
- Local web UI, Wi-Fi/HTTP/OTA — outside MVP; no task owns it.

## Design notes
- Canonical storage is always °F. Convert at the presentation layer; do not store converted values and do not convert twice.
- Time rule (04 §4.4): `unix_s` comes from `bridge_state` at sample time. If the clock is unknown, `unix_s = 0` and `flags.clock_valid = 0`. The app sets the clock on connect when it differs by more than 2 s. The firmware persists the last known UTC in NVS every 10 minutes and marks it estimated until the app sets it.
- No sample time is ever adjusted backwards. A clock correction changes future records only; `seq` keeps ordering unambiguous.
- Records written before the first phone connection may have no wall time. Place them relative to `seq` and the sync time, label the History axis `times estimated`, and never invent a precise date.
- Formatting (12 §12.5 / 13 §13.6): `165.2°F` with no space, `2h 14m`, `1 min`, `12s ago`, locale dates/times. Keep 0.1°F precision; do not round Live or OLED values for copy reasons.
- Tabular figures for every temperature and axis; Live value 40–46 px; chart labels ≥11 px; body 14–15; labels 11–12.
- Theme is `System / Light / Dark`, local only, applied immediately and on launch. No colour-only state.
- `config.units` selects the OLED display unit; `config.display_timeout_s` selects the OLED timeout. Sending config uses whole-struct read-modify-write.
- There are no probe labels: identity is `P1`–`P4` by order and colour. P4 is the fixed Billows/pit channel.
- The OLED and the phone must agree after a unit change; the config write is queued when offline and the UI says the screen updates on reconnect.
- Design: [04 §4.4](../design/04-data-and-storage.md), [06 §6.7](../design/06-app.md), [13 §13.5](../design/13-ui-implementation-contract.md#units-theme-and-locale).

## Done when
- [ ] A unit change persists across relaunch and updates Live, History, Cooks and Billows in the same frame.
- [ ] Theme and `Live change window` persist across relaunch and are applied on launch.
- [ ] The clock is set once per connect (when the difference exceeds 2 s), with the correct timezone offset.
- [ ] Locale date/time formatting and the 12/24-hour setting are respected; no hard-coded `AM`/`PM`.
- [ ] Conversion and formatting tests pass, and `flutter analyze` / `flutter test` are clean.
- [ ] The OLED reflects units and timeout after a change.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_

### What landed
- `app/lib/app/formatters.dart` is now the single temperature conversion and
  locale formatting layer (values, deltas, counts, storage, dates, times,
  month labels). It uses `intl` 0.20.2; `clockLabel` takes the 12/24-hour
  choice and localises the markers, so no production `AM`/`PM` literal remains.
- `HistoryViewState` and the controller now delegate conversion to that layer;
  sparklines, charts, Live tiles, History Summary/chart, Cook view, Billows
  target, confirmations, storage counts and the OLED preview all go through it.
  Samples remain canonical °F.
- `BridgeController` stores `localeName`/`use24Hour`, restores units + Appearance
  + `Live change window` from `AppPreferences` before the first frame, persists
  changes, and persists the unit adopted from the Bridge config. Keys:
  `appearance.theme_mode`, `preferences.temperature_units`,
  `preferences.live_change_window_minutes`.
- Same-frame repaint: `HistoryViewLoader` re-wraps the loaded view with
  `HistoryViewState.withUnits` (no archive reload); `PastCookScreen` mirrors
  the source controller's presentation state; `DevicePreviewScreen` listens to
  the controller. `SmokeBridgeApp` applies the platform locale/24-hour setting
  and repaints the controller after the delivery frame.
- OLED unit and timeout remain the whole-struct `config` write owned by
  `setUnits` / `setDisplayTimeout` (offline units are queued and flushed on the
  next healthy connect).
- `set_time` was already in the connect path from T35; T53 adds a sub-2 s
  tolerance regression test. The connect path sends exactly one
  `control(set_time)` with `unix_ms` + `tz_offset_min`, forcing it on first
  connect, `clock_valid = 0` or drift > 2 s.
- Tests: `app/test/units_time_test.dart` (8 new), one new case in
  `bridge_link_test.dart`. `flutter analyze` clean; `flutter test` 271 passing;
  root `tools/ci/verify_host.ps1` 25/25 CTest passing.

### Deviations / decisions
- Device locale and 24-hour setting come from `PlatformDispatcher` in the app
  layer and are pushed into one `Intl`-backed formatter layer, rather than each
  widget deciding formatting. Recorded in ADR 0057.
- The real-phone relaunch/OLED walk is not possible in this host session and is
  recorded as a T55/T46 follow-up, consistent with T47-T52.
- `PastCookScreen` keeps its copy controller (so History state is untouched) and
  now mirrors presentation fields via a listener instead of freezing them.

### Docs
- `docs/design/adr/0057-units-locale-and-persisted-preferences.md`
- `docs/design/13-ui-implementation-contract.md` §13.5 units/locale note
- `docs/design/06-app.md` save model persistence notes
- `docs/progress/T53.md`

### Remaining work / blockers
- Bench on a real phone: units/Appearance/change window survive force-stop and
  relaunch; the OLED shows the new unit and timeout; `set_time` lands once per
  connect with the correct timezone after a board power cycle.
- T54 owns the copy/accessibility/golden gate over the new locale strings.
