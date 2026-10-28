# T51 — app: bridge settings

## Goal
Implement the approved Settings editors and Bridge details against the real config contract: units, Appearance, screen timeout, Bridge name, Smoke X4 status and re-pair, status-only Billows, technical details, one connection log and the Bridge action rows. Each field saves immediately with honest per-field state, never a bottom Save bar.

## Context (read first)
- [06 §6.7](../design/06-app.md) — Settings root, save model, Bridge details, History & storage, About and the offline table.
- [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations) — required Bridge details states and copy.
- [13 §13.6](../design/13-ui-implementation-contract.md#136-visual-interaction-and-accessibility-contract) — formatting, touch targets and no colour-only state.
- [05 §5.9](../design/05-ble-contract.md) — 80-byte `config`, read-modify-write, name/timeout/units validation.
- [05 §5.5](../design/05-ble-contract.md) — `unpair_smoke_x` behaviour.
- [12 §12.2](../design/12-copy-and-label-review.md) — exact Settings/Bridge details labels and destructive row names.
- `app/lib/features/settings/bridge_details.dart` — current Bridge details UI to port.
- `app/lib/features/settings/settings_details.dart` — current editor widgets.
- **Verify:** H/P · **Board:** no / phone
- Depends on T50 and T47.
- **Post-T36 status:** the Bridge details layout, editors, technical details,
  connection log, Billows status-only screen and action rows already exist in
  `bridge_details.dart`/`settings_details.dart`. They read controller fields and
  simulate saves. T51 replaces the simulated paths with the real 80-byte config
  read-modify-write, per-field save states and named refusals.

## Scope
- [ ] Implement `Temperature units` as inline segmented `°F` / `°C` in Preferences, applied immediately.
- [ ] Implement `Appearance` as `System / Light / Dark`, persisted and applied on launch; subtitles `Match your phone`, `Always use light`, `Always use dark`.
- [ ] Implement `Bridge screen timeout` with exactly `30 sec`, `1 min`, `2 min`, `Never` and the approved subtitles such as `1 min · screen turns off` and `Screen stays on`; applied immediately and requiring a connection.
- [ ] Implement Bridge name editing (≤15 chars, app-facing label only) with an edit dialog, apply on Done, and inline `Saving…` / `Saved` / `Couldn’t save`.
- [ ] Implement Smoke X4 pairing status: `Receiving readings` only when a valid X4 packet is ≤90 s old; otherwise `No readings for 4 min`, `Signal lost` or `Not paired`. Keep `Updated 12s ago` as supporting text.
- [ ] Implement `Re-pair Smoke X4` as the only re-pair entry point in the app; it writes `unpair_smoke_x` and then shows the SYNC instructions.
- [ ] Show Billows detection and last-seen only. The Billows target is read-only and there is no mode or target editor.
- [ ] Implement collapsed `Technical details` with `Bridge ID`, `Firmware`, `Protocol`, `Signal` (dBm), `MTU`, `Connected for`, `Last synced`.
- [ ] Implement one `Connection log` covering Bridge, Smoke X4, Billows and sync events, newest first, with the subtitle “Bridge, Smoke X4, and Billows events”.
- [ ] Implement Bridge action rows: `Power off the Bridge`, `Factory reset Bridge`, `Forget this phone`. They are action rows, not navigation rows; no chevrons. Factory reset uses the error colour; forget is available offline.
- [ ] Do not add probe names or roles anywhere. Probe identity is order and colour, `P1`–`P4`.
- [ ] Use read-modify-write of the whole 80-byte config for every config field; never write a partial struct.
- [ ] Show per-field saving and error state; never optimistically claim success.
- [ ] Map bridge refusals to the UI: a bad value is refused by the bridge and the UI says why. Use the `result` status (`invalid`, `unsupported`, `busy`, `unauthorized`, `failed`, `not_found`, `storage`) as the branch.
- [ ] Remove the bottom Save bar.
- [ ] Implement the approved offline reasons: timeout disabled with `Connect to change this`; Bridge name disabled with a reason; `Clear history on the Bridge` disabled with `Connect to the Bridge to clear it.`; power off/factory reset disabled with `Connect to the Bridge first`; forget available; units apply locally with “The Bridge screen will update when you reconnect.”
- [ ] Bench on a real phone: change each field, force a bad value, and verify the OLED reflects units and timeout.

## Out of scope
- The Settings root, section order and one-Bridge-header rule → T50.
- Destructive confirmation sheets, `Bridge is off` screen and Setup return → T52.
- End-to-end units/time/theme/locale wiring across Live, History, Cook and Billows → T53.
- `Live change window` (a local Live display preference, not a Bridge config field) → T50/T53.
- UI state matrix, accessibility audit, screenshot suite and copy-lint gate → T54.
- `config` characteristic implementation and validation → T47.
- Control op implementation → T48.
- Billows control, mode or target editor → M5 Billows (T56–T60); `caps.billows_control` is always 0.
- Probe names and roles — removed from the MVP; outside MVP, no task owns it.
- A second Smoke X4 screen or a separate `Bridge details` button — explicitly not in the approved contract.

## Design notes
- Units copy: `Temperature units`; `°F` / `°C`; “All temperatures, including the Bridge screen.” Offline: “The Bridge screen will update when you reconnect.”
- Appearance copy: `System`, `Light`, `Dark`; “Match your phone”, “Always use light”, “Always use dark”.
- Timeout values map to `config.display_timeout_s`: 30, 60, 120, 0 (`Never`). Never invent another interval.
- Bridge name is at most 15 UTF-8 characters, NUL-terminated in the 16-byte field. The config write is whole-struct read-modify-write.
- Inline name states are exactly `Saving…` / `Saved` / `Couldn’t save` (curly apostrophe in `Couldn’t`).
- Smoke X4 freshness: a valid state packet within the last 90 s is `Receiving readings`; 90 s–10 min is stale (`No readings for 4 min` as the approved example); after 10 min the X4 link is lost. BLE link state and X4 telemetry are separate.
- `Re-pair Smoke X4` copy: “Put the Smoke X4 into SYNC mode.”; “Hold its button until it beeps.”; “The Bridge confirms the pairing.”; “This clears the old radio pairing only. History on the Bridge, phone pairings, and settings are kept.”
- `Technical details` is the only place `MTU`/`RSSI`/GATT language may appear; the main status card must not contain it.
- `Connection log` is one timeline, newest first. Do not split it into separate Bridge/X4/Billows logs.
- Bridge details status card: name, `Bridge A4F2`, `Connected`, `Battery 87%`, `Signal` + bars + `Fair`, `Updated 4s ago`, `Sync now`, `Disconnect`. Offline the buttons become `Reconnect` / `Connect`, and the card notes “Recording continues on the Bridge.”
- Formatting (13 §13.6 / 12 §12.5): `165.2°F` (no space), `2h 14m`, `1 min`, `12s ago`, locale dates/times, `readings` not `records`. Sentence case for buttons and labels; product names keep their casing.
- No global success banner and no bottom Save bar; a small inline state is enough (06 §6.7).
- Design: [06 §6.7](../design/06-app.md), [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations), [05 §5.9](../design/05-ble-contract.md).

## Done when
- [ ] A real phone changes each config field: units, Appearance, Bridge screen timeout and Bridge name.
- [ ] A bad value is refused by the bridge and the UI says why, with no optimistic success.
- [ ] The OLED reflects units and timeout.
- [ ] Offline controls are disabled with the approved reasons, and one global offline banner is used.
- [ ] The Smoke X4 state (`Receiving readings`, `No readings for 4 min`, `Signal lost`, `Not paired`) and the connection log match the contract.
- [ ] `flutter analyze` is clean and `flutter test` passes, including widget tests for the new states.
- [ ] Hand-off below filled in.

## Hand-off

**Landed.** Units, Appearance, Bridge screen timeout and Bridge name now use the
real 80-byte `config` as a whole-struct read-modify-write with a confirming
read-back (ADR 0055). Each editor owns its inline `saving / saved / named error`
state and never shows success from the GATT write alone. Units apply locally at
once and queue the Bridge write while offline. Appearance persists in the local
`preference` table (schema v3) and is restored before the first frame. Smoke X4
now reports `Receiving readings`, `No readings for N min`, `Signal lost` or
`Not paired` with `Updated 12s ago` as support; re-pair sends `unpair_smoke_x`
and shows the SYNC steps only after `ok`. Billows is status-only and the
Billows-filtered log was removed so there is one connection log. Technical
details stay collapsed; the three Bridge action rows have no chevrons; the
approved offline reasons are in place and no bottom save bar exists.

**Deviation / deferred.** No phone is attached in this session, so the bench
items (real phone changes each field, forced bad value, OLED units/timeout) are
deferred to T55, as T47/T49 did. The review/demo path with no BLE client applies
fields locally for widget review; production always has the BLE seam.

**Checks.** `cd app; flutter analyze` → No issues found. `flutter test
--reporter expanded` → +245 All tests passed. `powershell -NoProfile
-ExecutionPolicy Bypass -File tools/ci/verify_host.ps1` → 25/25 CTest, exit 0.
New tests: `test/settings_config_test.dart` (9), `test/settings_bridge_test.dart`
(5), plus config codec pinning in `test/link_codec_test.dart`.

**Next.** T52 owns destructive confirmations and `Bridge is off`; T53 should
persist units and `Live change window` through `AppPreferences` and apply units
and theme across Live/History/Cook/Billows; T55 runs the real-phone walk.
Changed docs: `docs/design/05-ble-contract.md`, `docs/design/06-app.md`,
`docs/design/13-ui-implementation-contract.md`,
`docs/design/adr/0055-settings-config-writes-read-back.md`,
`docs/progress/T51.md`.

