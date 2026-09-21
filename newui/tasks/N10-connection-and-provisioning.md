# N10 — Connection & provisioning

**Goal:** the dual-link connection model and the three transport modes, with
plain-language explainers and a safe switch path. Setup over BLE must always work;
Wi-Fi is an upgrade.

**Design:** [`newui/app.js`](../app.js) §5 `linkInfo`/`appbarHtml`, §7
`overlayConnect`, `overlayModes`, `overlayModesRef`, `overlayProvisionSta`,
`overlayProvisionAp`, `modeCardCompact` · `newui/NOTES.md` §2.4, §6 ·
`mock-data.js` MODES, connection scenarios · `docs/design/05`.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I9 | One transport carries data at a time (BLE leads, Wi-Fi upgrades, BLE held warm) | `primary` + radio dots |
| I13 | Copy over error when a capability is missing ("Full history needs Wi-Fi") | mode capability rows |
| — | **The device is never unreachable**: a failed STA join always leaves AP/ BLE as the escape hatch | rollback UX |
| — | Wi-Fi password is sent over BLE and never stored by the app | provisioning copy |

## 10.1 Connection surfaces

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N10.1 | Transport chip (app bar): pulse dot, label (Bluetooth/Bridge Wi-Fi/Home Wi-Fi/Connecting/Hotspot/Offline), two radio indicators (bt/wifi), which carries data | N4.4, N3.20 | W | `app.js` linkInfo |
| N10.2 | Connect sheet: dual independent link rows (health, signal, last sync), battery, recording line | N10.1 | W | `app.js` overlayConnect |
| N10.3 | Error/rollback notice with Try again + Use hotspot | N10.2 | W | `app.js` overlayConnect |
| N10.4 | Mode cards (BLE / Bridge hotspot / Your Wi-Fi) with one-word state + `?` info | N10.2 | W | `app.js` modeCardCompact |
| N10.5 | Technical reference sheet: summary, good/limited lists, capability matrix (live/preview/full history/rules/OTA) | N10.4 | W | `app.js` overlayModesRef, I13 |
| N10.6 | "Switch mode — always available over Bluetooth" explainer + Re-sync now + Disconnect | N10.4 | W | `app.js` overlayConnect |

## 10.2 Provisioning

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N10.7 | Join home Wi-Fi: network scan list, signal, password field, Connect bridge | N10.4 | W | `app.js` overlayProvisionSta |
| N10.8 | Use hotspot: SSID + passkey MonoWell, numbered join steps, Open Wi-Fi settings, "I have joined" | N10.4 | W | `app.js` overlayProvisionAp |
| N10.9 | Forget network row (only when STA connected) | N10.7 | W | `app.js` viewSettings |
| N10.10 | SWITCH flow over BLE with a **device-side rollback** promise: if the new mode fails, the old link is kept and BLE stays the escape hatch | N10.6 | W | NOTES §3.8, research notes §14.2 |
| N10.11 | Named error states: wrong password, router unreachable, switch rollback — each with its own copy + recovery buttons | N10.7 | W | `mock-data.js` scenarios, I15 |

## 10.3 Bridge / device identity (settings-side)

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N10.12 | Settings "Bridge" card: dual link rows + battery + recording + Re-sync + Change mode + Disconnect | N4.3 | W | `app.js` viewSettings |
| N10.13 | Two-hop signal discipline: phone→bridge (BLE) and bridge→router (from device) are never conflated | N10.12 | W | research notes §11.4 |
| N10.14 | Resync calls the repository and shows the resync-complete notice | N10.12, N2.28 | S | `app.js` resync |
| N10.15 | Capability-gated controls: a mode/feature that cannot work is absent or disabled with its reason (I5) | N10.5 | W | I5, I13 |

## Exit gate

Every connection-matrix scenario (`bt_only`, `sta_connecting`,
`sta_wrong_password`, `sta_router_unreachable`, `ap_broadcasting`, `ap_joined`,
`switch_rollback`) renders the right chip, sheet and recovery path. A failed join
never strands the user without a working link.

## Must-not-regress

I9, I13, I15 and "the device is never unreachable". No Wi-Fi secret is persisted
by the app.

## Hand-off

**Status: done.** `make app.test` green (**451** tests; was 409 — N10 adds 42);
`flutter analyze` and format check clean; `dart test test/domain test/data`
green (**143**; was 139 — 4 new repo tests). No golden changed (no golden renders
the connect/settings surfaces).

### What landed (all under `app/lib/features/connection/`; barrel `connection.dart`)

- `connection_format.dart` — pure: `signalWord`, `agoLabel`, `activeModeId`,
  `activeMode`, `modeStateWord`, `wifiModeLabel`, `bluetoothSubtitle`,
  `bridgeBluetoothSubtitle`, `wifiSubtitle`, `bridgeWifiSubtitle`,
  `ConnectionError` + `connectionErrorOf`/`connectionErrorCopy`,
  `connectionHasProblem`/`connectionProblemIsWarning`, `ModeFeature` +
  `featureLabel`/`featureReason`/`featureAvailable`/`capabilityRows`,
  `fullHistoryRefusal`, `kScannedNetworks`, `kHotspotSsid`/`kHotspotPasskey`.
- `connect_sheet.dart` — `ConnectSheetBody` (N10.2/N10.3/N10.4/N10.6): device head
  + pulse, dual `LinkRow`s with a `Data` badge, battery + recording, the
  error/rollback `InsightBanner` with Try again + Use hotspot, the three mode
  cards, the Bluetooth rollback explainer, `PrimaryAction` Re-sync now and
  Disconnect.
- `mode_cards.dart` — `ConnectionModeCard` (one-word state + `?`),
  `ConnectionModesBody` (the `modes` sheet), `ModesReferenceBody` (N10.5: summary,
  good/limited lists, capability matrix with the I13 reason under each missing
  row).
- `provision_sheets.dart` — `ProvisionStaBody` (scan list, password field,
  Connect bridge, named-error banner + hotspot escape hatch) and
  `ProvisionApBody` (SSID, `MonoWell` passkey, numbered steps, Open Wi-Fi
  settings, I have joined).
- `bridge_card.dart` — `BridgeCard` (N10.12–N10.15) with the two-hop subtitles,
  the capability notice, Re-sync/Change mode/Disconnect and the conditional
  Forget-network row.
- Wired: `shell/overlay.dart` resolves `connect`, `modes`, `modesRef`,
  `provisionSta`, `provisionAp` to the real bodies; `shell/destinations.dart`
  mounts `BridgeCard` in the Settings placeholder (N13 replaces the rest).

### Repository seam (N15 must implement)

`BridgeRepository` gained four methods, implemented on `MockBridgeRepository`:
`joinWifi({ssid, password})` (password is an argument only — never stored),
`useHotspot()`, `confirmHotspotJoined()`, `forgetNetwork()`. `resync()` already
existed and is unchanged.

### Tests

- `app/test/features/connection_format_test.dart` (17 pure).
- `app/test/features/connection_test.dart` (21 widget) — includes the exit-gate
  matrix: all seven scenarios render the right chip projection and a connect
  sheet with both links; the three problem scenarios show the notice and both
  recovery buttons.
- `app/test/data/mock_repository_test.dart` — 4 new tests (joinWifi/useHotspot/
  forgetNetwork/resync rollback).
- `app/test/features/shell_router_test.dart` — the per-overlay scroll test now
  opens the `modesRef` sheet via the connect sheet's `?` button (the connect body
  is no longer a placeholder with `shell-overlay-copy`).

Commands: `make app.test`; `cd app && flutter test
test/features/connection_test.dart test/features/connection_format_test.dart`;
`cd app && dart test test/domain test/data`.

### Deviations / decisions

- **Active mode is derived, not read.** The prototype reads `connection.mode`,
  which `mock-data.js` never sets, so its mode card never highlights. N10 derives
  it from `primary` + `wifi.mode` (`activeModeId`); document that as an
  intentional fix.
- **Sheet sub-titles are static.** `resolveOverlay` has no snapshot, so the
  connect sub is `Bluetooth and Wi-Fi` (not the device name) and the modes sub is
  the prototype's explainer line. The device name is the first card in the body.
- **Wi-Fi `last sync` is now shown.** `wifiSubtitle`/`bridgeWifiSubtitle` append
  `agoLabel(lastSyncS)` so the task's "health, signal, last sync" holds for both
  rows (the prototype only put it on the Bluetooth row).
- **Named errors are rendered from the connection state.** `connectionErrorCopy`
  is the single source for the connect sheet and the STA sheet; the mock
  transitions through `joinWifi`/events, so the error copy is tested by scenario.
- **No Wi-Fi secret is persisted.** `joinWifi` takes the password as an argument
  and the mock writes nothing; a repo test asserts the snapshot's `toString()`
  never contains it.
- The `modesRef` body keeps its `onDone` for the host contract but does not use
  it (the `?` opens a new overlay rather than dismissing).
- The STA "Try again" primary re-submits; the hotspot escape hatch is a ghost
  button in the error block (I14 keeps one ember primary).

### Follow-ups

- N13: replace the Settings placeholder (the `BridgeCard` is the N10.12 seam);
  the firmware/OTA rows stay N13's.
- N14: onboarding step 5 reuses `ConnectionModeCard`; the wizard's mode step is
  not wired here.
- N15: implement the four new repository methods on the real transport and keep
  the password out of storage; `resync` notice copy is UI-side.
- N16: consider connect-sheet / reference goldens per scenario (none exist).
