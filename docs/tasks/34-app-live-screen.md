# T34 — app: Live screen

## Goal
Live is the single status surface: the App → Bridge → Smoke X4 chain, four numbered probe tiles with last-hour sparklines, inline notices, and a Billows card only when observed. It shows the approved healthy, delayed, stale, lost, syncing, offline, and no-cache states without ever presenting cached values as current.

> **Post-T36 supersession:** the fixed `1h · +3.8°F` footer, the single signal
> meter and the inline lost-X4 notice were replaced by the configurable Live
> change window, per-link signal meters and the X4-node warning dialog. The
> current contract is [06 §6.5](../design/06-app.md) and
> [13 §13.4](../design/13-ui-implementation-contract.md#live); follow those, not
> the historical checkboxes below.

## Context (read first)
- [06 §6.5](../design/06-app.md) — Live layout, chain rules, tiles, notices, Billows card, and refresh behaviour.
- [13 §13.4 Live](../design/13-ui-implementation-contract.md#live) — the complete Live state inventory.
- [13 §13.5 Connection health](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows) — 90 s fresh / 90 s–10 min delayed / >10 min lost, and the 110 s read fallback.
- [12 §12.3 C4](../design/12-copy-and-label-review.md#123-remaining-copyux-gaps-before-release) — no fixture values in the offline/no-cache state.
- [05 §5.4](../design/05-ble-contract.md) — `live.flags`, sentinels, and freshness fields.
- Design: [06](../design/06-app.md), [13](../design/13-ui-implementation-contract.md).
- Verify tier: **H/P**. Board: **no / phone**.
- Depends on T06, T32, and T28.

## Scope
- [ ] Mount the approved Live screen from the prototype as one status surface; keep the existing widgets/theme rather than rebuilding.
- [ ] Render the connection chain `App → Bridge → Smoke X4` with icons and labels.
- [ ] Render the two-row status block: `Bridge connected · 2h 14m` + cell-style signal meter, then `Receiving readings · updated 12s ago` only inside the 90 s window.
- [ ] For 90 s–10 min show `No readings for 4 min`; after 10 min show `Smoke X4 signal lost · 10 min ago`.
- [ ] Offline: `Bridge disconnected · last connected 2h ago` with the signal meter hidden; when cache is shown add `Showing saved readings · last reading 20 min ago`.
- [ ] Render four probe tiles in order with `P1`–`P4`, large values, last-hour sparklines, and the signed footer (`1h · +3.8°F`).
- [ ] Detached probe shows `—` and `Not connected`, never `0 °F` and never omitted; a tile with no sparkline history says `No history yet` with unchanged tile height.
- [ ] Render inline notices for: `No data from Smoke X4` + `Troubleshoot`, sync progress/failure, `Not recording`, `No probes connected`, and `Billows not detected` + `View connection log`.
- [ ] Show sync as its own card: `Syncing saved readings` with “Newest readings load first.”, or `Loading saved readings` with “Your latest readings are ready. Older readings continue in the background.”; add `Slow connection` when the negotiated MTU is low; a failure says `History sync failed` with `Retry sync` while live keeps updating.
- [ ] Show the Billows card only when detected, with `Billows`, `Set temp`, `Last detected`, and the caption `Set on the Smoke X4.` — no Connected/read-only pill and no `Detected` without an age. When offline use `Set temp (last known)`.
- [ ] Hide the Billows card when `caps.billows_observe = 0` or Billows has never been detected; show no notice when it has never been detected.
- [ ] Pull-to-refresh reads `live` and runs a forward sync; report a failure with a named error; there is no `Sync now` on Live.
- [ ] Offline without cache: `Bridge disconnected · nothing saved yet`, no fixture or last-session values presented as current, and one next action (`Retry`).
- [ ] Tapping the connection card opens Bridge details; tapping a probe tile opens History with that probe and the 1 h range.
- [ ] Keep all four tiles when all probes are absent and show the one `No probes connected` notice.
- [ ] No aggregate preview graph, no footer instruction text, and no small connection chip in the app bar.
- [ ] Map view state so the widget test can drive healthy/delayed/stale/lost/detached/no-probes/offline-cache/no-cache/sync-failure/Billows states from the fake.

## Out of scope
- History chart, Summary, and Cooks → T36; full History → T42; History empty states → T45.
- Setup and passkey states → T33.
- The reconnect state machine, control queue, and time sync → T35.
- Settings, units, and Bridge details → T50–T53 (M4); the `Troubleshoot` action opens the SYNC-mode help, not a new settings surface.
- Billows observation, target relation, and the Billows details screen → T56–T60 (M5). No Billows control, setpoint editor, or fan-running claim; control is outside MVP and no task owns it.
- Wi-Fi/HTTP/OTA — outside MVP; no task owns it.
- A second dashboard, aggregate graph, or redesigned Live — not in the MVP; no task owns it.
- Fixture values, simulated live readings, or prototype chrome presented as current — outside MVP; no task owns it.

## Design notes
- Freshness rules: a live notification is fresh for **90 s**; **90 s–10 min** is delayed/stale; after **10 min** the X4 link is lost. No notification for **110 s** triggers a `live` read. BLE link state and X4 telemetry are separate: a bridge that answers with a quiet X4 stays stale, not offline.
- Use the app's own receipt time as well as `live.age_s` so a bad bridge clock cannot fake freshness. Never display cached data as live.
- One status surface: do not repeat a no-reading line on every tile or add a second text line under each chain node.
- Probe identity is `P1`–`P4` plus colour; no names, roles, or tags. The whole tile is the tap target and carries a chevron.
- Sparklines are relative to each probe's own last hour and min/max; they communicate shape, not cross-probe comparison. The footer is one string `1h · +3.8°F` with a signed delta; do not split the `1h` and delta to opposite edges.
- Detached is `—` + `Not connected`; stale/frozen use time language (`Updated 62s ago`, `No readings for 4 min`), not internal health taxonomy. `Aging`, `Stale`, and `Frozen` stay internal.
- Billows `Detected` comes only from `billows_attached` in a recent valid X4 packet; never claim the fan is running. The target is the Smoke X4 channel 4 set temp, shown as `—` until validated. When `caps.billows_observe = 0`, the card is hidden entirely.
- The `Not recording` notice is: “Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.”
- The no-X4 notice is: “The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.”
- `Sync now` lives only in Bridge details; Live's recovery gesture is pull-to-refresh.
- Keep `fixtures.dart`, `scenario_lab.dart`, and simulation timers debug/test-only and unreachable from a release build.

## Done when
- [ ] Live renders the full chain, four numbered probes, and a sparkline where history exists from the fake.
- [ ] Every Live state in 13 §13.4 is reachable and widget-tested with the approved copy.
- [x] A real phone shows live values at the sample cadence. **Deferred to T37**; fake/widget tests are the gate now.
- [ ] The detached, no-cache, and Billows-loss states pass widget tests; offline without cache does not render fixture values as current.
- [ ] The Billows card is absent when `caps.billows_observe = 0` and when Billows has never been detected.
- [ ] `flutter test` passes, including the new Live widget tests.
- [ ] Hand-off below filled in

## Hand-off

**Status:** done. Live is mounted as the single status surface and every
§13.4 Live state is driven through the scripted fake and widget-tested.

**Changes**
- `app/lib/features/live/live_screen.dart` — approved chain, two-row status
  block, four numbered tiles, inline notices, sync card, Billows card; added
  the offline-no-cache `Nothing saved yet` notice with one `Retry`, hid the
  telemetry row when there is no cache, and made the Billows card conditional
  on the nullable view state. Test keys `live.probe.1..4`, `live.sync`,
  `live.noCache`.
- `app/lib/app/view_state.dart` — `LiveViewState.showSavedReadings`;
  `billows` documented and used as nullable.
- `app/lib/app/bridge_controller.dart` — `billowsObserveCap`
  (`caps.billows_observe`), `smokeXAgeOverride` receipt-age seam, no-cache
  probe/sparkline clearing, exact `Bridge disconnected · nothing saved yet`
  copy.
- `app/test/support/fake_bridge_session.dart` — `driveLiveState(...)` fake
  driver for all Live states, `flags` on `publishLiveSample`, deterministic
  sparkline content.
- `app/test/live_screen_test.dart` — 13 widget tests covering healthy, aging,
  stale, lost, detached, no-probes, offline cache, offline no-cache, sync
  progress/backfill/slow link, sync failure, Billows detected/lost/never/cap,
  connection-card and probe-tile navigation, and pull-to-refresh without
  `Sync now`.
- ADR `0041-live-state-gating-and-no-cache.md`; `06-app.md` §6.5 notes;
  `docs/progress/T34.md`.

**Deviations**
- The prototype-derived packet ages remain the default; T35 replaces them with
  the phone's monotonic receipt time via `smokeXAgeOverride`.
- Pull-to-refresh still uses the controller's existing retry/sync simulation;
  the real forward sync and named pull error belong to T35.
- Billows set temp in the offline test is shown as `Set temp (last known)`,
  which is labelled last-known rather than current; probe tiles never render
  cached values as current.

**Checks**
```
cd app
flutter analyze
# No issues found! (ran in 0.9s)

flutter test
# 00:06 +110: All tests passed!
```

**Remaining work / next task**
- T35: populate `smokeXAgeOverride` from receipt time, wire real pull-to-refresh
  forward sync and its named error, and set `billowsObserveCap` from `info`.
- T37: real-phone sample cadence and screenshot parity.
- T54: fold these Live cases into the full copy/golden matrix.

