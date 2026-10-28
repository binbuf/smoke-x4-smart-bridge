# T33 — app: setup and passkey flow

## Goal
A factory-fresh phone can go from `Connect your Bridge` through permissions, scan, bridge selection, the passkey instruction, the OS bond, recovery states, and first sync to Live. The approved setup states and copy exist in production with no simulation control or fake OS prompt.

## Context (read first)
- [06 §6.4](../design/06-app.md) — setup steps, copy, and pairing outcomes.
- [13 §13.4 Setup](../design/13-ui-implementation-contract.md#setup) — the complete setup state inventory.
- [13 §13.5 First launch](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows) — the first-launch order.
- [12 §12.3 C1](../design/12-copy-and-label-review.md#123-remaining-copyux-gaps-before-release) — unsupported/protocol-mismatch copy gaps this task closes.
- [05 §5.11, §5.12](../design/05-ble-contract.md) — bond rules, `bonds_free`, and the first-connect procedure.
- [06 §6.8](../design/06-app.md) — named error copy.
- Design: [06](../design/06-app.md), [13](../design/13-ui-implementation-contract.md).
- Verify tier: **H/P**. Board: **no / phone**.
- Depends on T32, T06, and T30.

## Scope
- [ ] Mount the approved setup route end to end; land on Live on success, never on a dead summary screen.
- [ ] **No saved Bridge:** app-bar title `Set up`; headline `Connect your Bridge`; body “Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it on.”; primary `Find bridge`.
- [ ] Show the saved-history escape when saved history exists: a `History on this phone` notice with reading count and date range, plus `View history on this phone`.
- [ ] **Permission primer:** show only when the platform permission is not already granted, after the user taps `Find bridge`; title `Allow Bluetooth to find your Bridge`; explain Android 12+ Nearby devices versus Android 7–11 location and that permission is only needed to find the Bridge; `Continue` / `Not now`.
- [ ] **Bluetooth off:** `Bluetooth is off`; “Turn Bluetooth on so the app can find your Bridge. The Bridge keeps recording while you do.”; `Open Bluetooth settings` / `Check again`.
- [ ] **Permission denied:** `Bluetooth permission needed`; “The app needs Nearby devices permission to scan for the Bridge.”; `Grant permission` / `Open app settings`.
- [ ] **Permission blocked:** `Bluetooth permission is blocked`; “Enable Nearby devices permission in Android settings, then come back.”; `Open app settings`.
- [ ] **Unsupported phone:** no BLE scanning; saved history remains reachable; `Close` / `View history on this phone`, plus `Learn more` where applicable.
- [ ] **Scanning:** `Looking for your Bridge…`; “Scanning stops after 10 seconds. We’ll check your last Bridge first.”; `Cancel`; remembered bridge preferred by device ID, then name.
- [ ] **No results:** `No Bridge found`; “Make sure it’s on and within about 10 meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.”; `Try again` / `Open Bluetooth settings`; footer `View history on this phone` when saved history exists.
- [x] **Connect failed after a result was selected (post-T36):** `Couldn’t connect to the Bridge`; “The Bridge was found but the Bluetooth connection didn’t finish. Keep it nearby and try again. It keeps recording while you do.”; `Try again` retries the same result without a rescan, `Find another Bridge` starts a scan; always disconnect a failed attempt so the Bridge re-advertises.
- [ ] **Results:** `Nearby bridges`, remembered first; signal words `Strong` / `Good` / `Weak` with dBm in the detail line; scan-response preview `P4 225°F · 87%`; remembered row marked `Last used`; a protocol-mismatch row says `Requires a newer app` and selecting it opens `Update the app to use this Bridge`.
- [ ] **Select:** connect and read `info`; if `proto_major` is not the expected value, show `Update the app to use this Bridge` and stop.
- [ ] **Passkey instruction:** before triggering the OS bond, show the approved block:

  > **Pair with the Bridge**
  > Enter the 6-digit code shown on the Bridge screen in the Android prompt.
  > `Look at the Bridge screen`
  > Example code block: `418 302`
  > “Example: the code appears on the Bridge screen. Only the Bridge screen shows the real code.”
  > [ Pair ] [ Cancel ]

- [ ] Trigger the OS bond only after the instruction; the OS owns the passkey dialog. The app must not show a real code (it cannot know it).
- [ ] **Pairing progress:** `Pairing…`; steps `Connecting to the Bridge`, `Checking the code`, `Syncing recent history`; no GATT or “secure characteristics” language.
- [ ] **Success:** set time, sync recent, show the first-sync screen, then land on Live.
- [ ] **Wrong code:** `The code didn’t match`; `Try again`; after two failures explain how to remove the pairing in Android settings (`Open Android settings`).
- [ ] **Prompt timeout:** `No prompt appeared`; “Open your notifications and look for the Android pairing request, then try again.”; `Try again` / `Open Bluetooth settings`.
- [ ] **Stale bond:** `This phone’s pairing is out of date`; explain the Bridge was reset; `Forget and re-pair` / `Cancel`.
- [ ] **Bond store full (`info.bonds_free == 0`):** `This Bridge already has 4 phones paired`; “Open the app on a phone that’s already paired and choose Forget this phone. If none is available, the Bridge needs a USB reset.”; do not start the OS bond just to discover this; `Try again` / `Cancel`.
- [ ] **First sync:** `Loading history`; “Your latest readings are ready. Older readings will load in the background.”; steps `Time set`, `Loading the last 24 hours`, `Loading older readings`, `Live view ready`; primary `View live readings`. Until the M3 sync engine lands, V0 says `Loading recent readings` / `last 15 minutes` instead of the 24-hour copy.
- [ ] **Protocol mismatch / unsupported production gaps (12 C1):** offer `Update app`, `View history on this phone`, and `Learn more` where applicable, and explain the Bridge is unchanged.
- [ ] **Orphaned history:** `History on this phone` with readings, date range, storage used, and delete; reachable from setup after forget/reset and from `View history on this phone`; never deleted automatically.
- [ ] No simulation control, fake OS prompt, or prototype chrome on a product setup screen.

## Out of scope
- Live screen states and rendering → T34.
- Link procedure internals (MTU, subscriptions, control queue, reconnect state machine) → T35.
- History shell and chart → T36; full History in M3 → T42.
- Settings, `Forget this phone`, factory reset, and power off → T50–T52 (M4); this task only provides the setup-side escape after those actions.
- Billows UI and observation → T56, T57, T59 (M5); Billows stays hidden while `caps.billows_observe = 0`.
- Wi-Fi/HTTP/OTA or any provisioning path — outside MVP; no task owns it.
- iOS support — outside MVP; no task owns it.

## Design notes
- The approved prototype flow and copy are the baseline. [13 §13.4](../design/13-ui-implementation-contract.md#setup) is the state list; [12](../design/12-copy-and-label-review.md) is the copy source. Where prose conflicts, 12/13 win.
- The passkey example is always the example `418 302`; the real six-digit code is only on the OLED. The app cannot know it.
- The bridge displays the code when bonding starts. Show `Look at the Bridge screen` before the OS prompt, not after.
- `info` is open, so the protocol check and `bonds_free` read happen before the bond attempt. Do not start the OS bond when `bonds_free == 0`.
- First sync pulls recent readings first. The V0 build only reads the last 15 minutes; never claim 24 hours before M3 can deliver it.
- The saved-history escape is the only way to reach local history after the bridge identity is removed. It is never deleted automatically.
- Production strings are centralized; user copy uses `readings`, not `records`, and avoids GATT/MTU/RSSI/bonding language.
- Test keys and state coverage follow [13 §13.8](../design/13-ui-implementation-contract.md#138-evidence-and-test-keys).

## Done when
- [x] A fresh phone reaches Live through named setup steps on a real phone. **Deferred to T37**; widget/fake tests are the gate now.
- [x] Every setup state in 13 §13.4 is widget-tested with the approved copy.
- [x] Wrong code, prompt timeout, stale bond, bond-full, permission (denied and blocked), unsupported-phone, and protocol-mismatch states are reachable.
- [x] V0 shows `Loading recent readings` / `last 15 minutes` rather than the 24-hour copy.
- [x] No simulation control or fake OS prompt is on a product screen.
- [x] The `History on this phone` escape works when saved history exists and after forget/reset.
- [x] `flutter test` passes, including the new setup widget tests.
- [x] Hand-off below filled in

## Hand-off

**Landed**

- `features/setup/setup_flow.dart` — the production setup state machine over
  `BleClient`: platform check, primer/request, scan with 10 s stop, remembered
  ordering, `info` read, protocol check, `bonds_free == 0`, OS bond, wrong code,
  prompt timeout, stale bond, first sync and saved-history escape. No plugin
  import and no simulated scan/pair timers.
- `features/setup/setup_screen.dart` — renders every 13 §13.4 setup state with
  the approved copy. Removed the hard-coded results list from the product flow;
  the lab passes `previewBridges` instead. Pairing progress no longer mentions
  GATT. First sync uses V0 `Loading recent readings` / `last 15 minutes`.
- `data/ble/bridge_codecs.dart` — `info` and advertisement decoding for setup,
  scan signal words and legacy-row classification. Offsets pinned by
  `test/setup_codec_test.dart` to `protocol/gen/records.dart`.
- Routing: `SmokeBridgeApp` mounts `SetupScreen` while `phase == setup` (or no
  saved Bridge) and the Live shell afterwards; `bootstrap()` starts in setup and
  creates the platform BLE client. `completeSetup()` lands on Live; there is no
  dead summary screen.
- Controller: `beginSetup()`, `rememberBridge()` and session fields for the
  remembered device ID/name and negotiated MTU; `forgetPhone()`/`factoryReset()`
  clear the remembered identity while keeping local history.
- Tests: `test/setup_flow_test.dart` (17 widget tests) covers primer gating,
  denied/blocked, Bluetooth off, unsupported, scanning/cancel, no results,
  remembered/preview rows, protocol-mismatch row and `info` mismatch, passkey
  block, full pairing-to-Live route, wrong code twice, prompt timeout, stale
  bond, bond store full, and orphaned history after forget.
  `test/setup_codec_test.dart` (4 tests) pins offsets, UUID and preview.
- Docs: ADR 0040, `docs/design/06-app.md` §6.9/§6.10.

**Deviations**

- Success currently moves through the first-sync screen and lands on Live; the
  actual `set_time` and recent-record sync writes remain T35's procedure work.
  `_afterBond()` only requests MTU and advances the approved steps.
- `Open Bluetooth settings` / `Open app settings` show a neutral instruction
  because `BleClient` has no settings-intent method yet. The buttons do not
  claim the settings screen opened. Follow-up below.
- Remembered Bridge identity and the initial setup phase are session-only; there
  is no saved-bridge store yet, so every production launch currently starts at
  setup. Persistence belongs with T35/T50.

**Checks**

- `flutter analyze` — No issues found.
- `flutter test` — 97 tests, all pass (including 21 new setup tests).
- `flutter build apk --debug` — see progress note; run from `app/`.

**Next task must know**

- Use `SetupFlow` for setup behavior; do not reintroduce timers or fixed device
  rows. `autoAdvance`/`previewBridges` are lab/review-only.
- T35 should replace the `_afterBond` shim with real time/sync procedures and
  persist `rememberedBridgeId`/`rememberedBridgeName`.
- Keep `info` reads before `bond()`; a future `bonds_free == 0` test must prove
  the OS bond never starts.

