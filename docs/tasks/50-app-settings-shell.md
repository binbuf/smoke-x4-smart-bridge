# T50 — app: Settings shell

## Goal
Ship the approved Settings root: one Bridge status header that opens Bridge details, one `History & storage` destination, Preferences with immediate units and Appearance, and About. The root stops duplicating Bridge actions and stops calling the local archive `Device log`.

## Context (read first)
- [06 §6.7](../design/06-app.md) — approved Settings root, save model and offline behaviour.
- [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations) — required Settings, Bridge details and confirmation states.
- [13 §13.8](../design/13-ui-implementation-contract.md#138-evidence-and-test-keys) — Settings test keys: `settings.bridge.status`, `settings.history.logs`, `settings.units`, `settings.tempChangeWindow`, `settings.appearance`.
- [12 §12.2](../design/12-copy-and-label-review.md) — root sections and `History on this phone` naming.
- `app/lib/features/settings/settings_screen.dart` — current Settings root to port, not redesign.
- `app/lib/features/settings/settings_views.dart` — current Settings sub-views.
- **Verify:** H · **Board:** no
- Depends on T33 and T40.
- **Post-T36 status:** the approved root order, single Bridge header, single
  `History & storage` row, Preferences and About already render in
  `settings_screen.dart`, and the stable keys exist. Remaining: the global
  offline banner, persistence behind T40/T53, and the connected/offline/read-only
  widget matrix. Do not rebuild the root.

## Scope
- [ ] Implement the approved Settings root in this order: `Bridge`, `History & storage`, `Preferences`, `About`.
- [ ] Keep exactly one `Bridge` section. Its status header is the entry point to Bridge details.
- [ ] Remove any separate `Bridge details` button, second Bridge group and duplicate navigation row.
- [ ] The Bridge status header is status only: LED and `Connected`, battery, signal meter with an `Excellent / Good / Fair / Weak` label, and `Updated`. Tapping it opens Bridge details.
- [ ] Make `History & storage` one destination row; do not duplicate the phone and Bridge storage rows on the root.
- [ ] `Preferences`: `Temperature units` with segmented `°F` / `°C`, applied immediately; `Live change window` with `1 / 5 / 10 / 15 / 30 / 60 min` (default 5), local only; `Appearance` with `System / Light / Dark`, local only.
- [ ] Add `About` / `About this app`.
- [ ] Disable offline-only controls with a short inline reason; keep local delete and forget available.
- [ ] Show one global offline banner, not a `Connect to edit` notice on every subscreen.
- [ ] Keep `Sync now` / `Reconnect` and `Disconnect` only inside Bridge details; no duplicate sync or repair actions on the root.
- [ ] Move Smoke X4 pairing, Billows, Bridge name and Bridge screen timeout into the Bridge details sub-view.
- [ ] Label the local archive `History on this phone`, never `Device log`, `Saved data`, `recorded data` or `local data`.
- [ ] Preserve the approved visual layer and theme; only the state source and navigation wiring change.
- [ ] Add widget tests for connected, offline and read-only states, units, appearance, and navigation into and out of Bridge details.

## Out of scope
- Bridge details editors (name, timeout, Smoke X4, Billows, technical details, log, action rows) → T51.
- Destructive flows, confirmations and the `Bridge is off` screen → T52.
- Units, time, theme and locale conversion across all screens → T53.
- Full UI state matrix, accessibility, goldens and copy-lint gate → T54.
- History & storage delete/clear implementation and counts → T44.
- A UI redesign, new destination, probe names/roles, or prototype chrome — outside MVP; no task owns it.
- Save-all bars — removed by design, no task re-adds them.

## Design notes
- Approved root shape (06 §6.7): a single `BRIDGE` card with `Backyard Bridge`, `Bridge A4F2`, `● Connected`, `Battery 87%`, `Signal ▂▄▆▁ Fair`, `Updated 4s ago`; then `HISTORY & STORAGE` with one `Storage 128,430 on this phone · 24,810 on the Bridge` row; then `PREFERENCES` with `Temperature units [°F][°C]`, `Live change window 5 min` and `Appearance System`; then `ABOUT` with `About this app App 0.1.0 · Firmware 0.1.0`.
- The Bridge status header must not repeat `Connected for 2h 14m`; the LED and label already carry that meaning. `Connected for` belongs in collapsed `Technical details`.
- Save model (06 §6.7): units immediate (local change plus queued bridge write if offline); `Live change window` immediate and local only; Appearance immediate and local only; timeout and Bridge name require a connection; destructive actions live in Bridge details.
- Remove bottom `Save changes` bars. A preference never needs a second tap, and there is no global success banner.
- Offline: timeout, Bridge name and Smoke X4 pairing are disabled with reasons; phone delete and forget remain available. The root still shows last-connected context and `Bridge disconnected`.
- Use `readings`, not `records`, in user copy. `History on this phone` stays when the Bridge is reset.
- `Live change window` is a local display preference, not a Bridge config field.
  It sets the signed change period on the Live probe tiles (default `5 min`) and
  has no effect on stored samples or the OLED. T53 persists it with units and
  theme; T54 covers its copy and key.
- Test keys must survive: `settings.bridge.status`, `settings.history.logs`, `settings.units`, `settings.tempChangeWindow`, `settings.appearance`.
- Keep `Settings` as the app-bar title; do not add a second `Settings` heading inside the page.
- Design: [06 §6.7](../design/06-app.md), [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations).

## Done when
- [ ] Widget tests cover connected, offline and read-only Settings, units, Appearance and navigation to/from Bridge details.
- [ ] `flutter analyze` is clean and `flutter test` passes.
- [ ] No duplicate rows, duplicate Bridge section, save-all bar or `Device log` copy remain.
- [ ] The root matches [06 §6.7](../design/06-app.md) and the Settings states in [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations).
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
