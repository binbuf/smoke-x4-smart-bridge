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