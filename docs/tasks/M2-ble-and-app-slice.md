# M2 — BLE + App Slice (V0)

**Exit gate (V0):** a factory-fresh phone scans the bridge, pairs with the code
on the OLED, sees four live temperatures, and shows the last 15 minutes in
History from the bridge's log. A disconnect/reconnect and a power cycle work.
This is the first deployable end-to-end build.

**Design:** [05](../design/05-ble-contract.md), [06](../design/06-app.md),
[04 §4.5](../design/04-data-and-storage.md)

---

### F2.1 ble_service: GATT server and `info`

- **blocked-by:** F1.5 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.1, §5.3](../design/05-ble-contract.md)

Register the new service UUID and all characteristic slots (even if some return
empty/busy), implement `info` (open), and the NimBLE init/disconnect callbacks.
Add a host encoder test. Do not register Wi-Fi/OTA characteristics.

**Done when.** A phone sees the service and reads a correct 32-byte `info`; a
host test matches the byte vector.

---

### F2.2 ble_service: live notify

- **blocked-by:** F2.1, F1.10 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.4](../design/05-ble-contract.md)

Implement the 20-byte `live` payload, the CCCD, notification on every sample and
flag change, and the read fallback. Keep it ≤20 B so MTU 23 works. Feed it from
a bounded queue, not the radio task.

**Done when.** A subscriber receives a notify per sample; the host vector in
05 §5.4 matches; a missed notify is recoverable by sync.

---

### F2.3 ble_service: control, result, and the clock

- **blocked-by:** F2.1, F1.9 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.5, §5.6](../design/05-ble-contract.md)

Implement the control write dispatcher, `result` notify, `op_id` echo, status
mapping, and `set_time`. Answer before acting for later destructive ops. Reject
unknown ops as `unsupported`, malformed bodies as `invalid`.

**Done when.** `set_time` round-trips; a wrong length changes nothing; a host
test covers every status.

---

### F2.4 ble_service: security, passkey, and advertising

- **blocked-by:** F2.1, F1.11 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.2, §5.11](../design/05-ble-contract.md),
  [07 §7.3](../design/07-display-and-controls.md)

Implement LE Secure Connections + passkey + bonding, characteristic security
levels, the scan-response status blob, 250 ms/1 s advertising, and restart after
disconnect. Display the six-digit passkey on the OLED. Cap at 4 bonds (one
active connection); no Just Works fallback.

**Done when.** A real phone bonds with the displayed code; a wrong code fails; a
bond survives reboot; `info` is readable without a bond; `live` is not.

---

### F2.5 ble_service: sync status and recent records

- **blocked-by:** F2.1, F1.7, F1.8 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.7, §5.8](../design/05-ble-contract.md),
  [04 §4.5](../design/04-data-and-storage.md)

Implement `sync_ctrl` command 0 (status) and a forward/backward read of up to 64
records, with the framed START/RECORDS/END stream. This is enough for V0's last
15 minutes; M3 adds the full cursor logic. Handle MTU 23 and 247.

**Done when.** A host test reassembles a split frame at MTU 23 and a multi-frame
batch at MTU 247; the app can read the last 15 minutes in one request.

---

### A2.1 app: BLE client and scan

- **blocked-by:** T0.6, F2.4 · **verify:** H · **board:** no
- **design:** [06 §6.3, §6.9](../design/06-app.md)

Implement the real `BleClient` on `flutter_blue_plus`: permission states, scan by
service UUID, connect/disconnect, bond/removeBond, MTU, read/write/subscribe,
and typed exceptions. Keep the fake implementing the same interface.

**Done when.** Unit tests cover every platform exception mapping; a manual scan
on a real phone sees the bridge; a denied permission produces the named state.

---

### A2.2 app: setup and passkey flow

- **blocked-by:** A2.1, F2.4 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.4](../design/06-app.md)

Implement the setup route: permission primer, Bluetooth-off state, scan list,
info read, passkey instruction, OS bond, stale-bond heal, wrong-code retry, and
success → Live. Do not show a code in the app.

**Done when.** A fresh phone reaches Live through named steps; wrong code,
timeout, stale bond, and bond-full states are widget-tested.

---

### A2.3 app: Live screen

- **blocked-by:** T0.5, A2.1, F2.2 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.5](../design/06-app.md)

Implement the compact connection status, four probe tiles in jack order,
per-probe last-hour sparklines, detached and stale states, and the Billows
read-only card. The Billows card is hidden when `caps.billows_observe = 0`, so
V0 does not depend on M5. No zero for absent data. Add the freshness calculation
and widget tests. The aggregate preview graph is not part of Live.

**Done when.** Live renders four numbered probes, a sparkline where history
exists, and every freshness state from a fake; a real phone shows live values at
the sample cadence.

---

### A2.4 app: link procedures and time sync

- **blocked-by:** A2.1, F2.3, F2.4 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.3](../design/06-app.md), [05 §5.12](../design/05-ble-contract.md)

Implement connect → read info → MTU → pair → subscribe → read live → set_time
→ sync. `config`/`stats` reads are added with F4.1/M4; V0 needs only info/live/
sync. Add the control/result queue with `op_id` matching and a 3 s timeout. Add
the reconnect state machine.

**Done when.** The fake drives the whole sequence; a real phone sets time and
recovers from a dropped link.

---

### A2.5 app: recent History (V0)

- **blocked-by:** A2.4, F2.5 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.6](../design/06-app.md)

Implement the History tab with four series, a 15-minute recent query from the
in-memory/DB cache, gap splitting, and an empty state. Full range chips, probe
filters, crosshair, summary and decimation are M3; V0 may show only the last
15 minutes.

**Done when.** A fake sync of 30 records draws four series with a gap; a real
phone shows the last 15 minutes after pairing.

---

### V2.1 Bench: V0 end-to-end

- **blocked-by:** F2.4, F2.5, A2.4, A2.5 · **verify:** P · **board:** yes
- **design:** [10 §10.3 B2/B3](../design/10-test-and-release.md)

On a factory-fresh install and a real board:

1. Power on; confirm advertising and the OLED page.
2. Scan, pair with the OLED code, reach Live.
3. See four live temperatures update at ~30 s.
4. See the last 15 minutes in History.
5. Disconnect by walking away; confirm stale/reconnect.
6. Stop the Smoke X4 (or move it out of range); confirm the bridge stays
   connected and the app shows stale, not fake live data.
7. Power-cycle the bridge; confirm auto-reconnect and history.
8. Confirm the stock receiver still works.

Record phone model, Android version, MTU, timings, and any failure. Commit the
V0 evidence.

**Done when.** All eight pass or every failure has a named follow-up task.

---

### V2.2 Field observation: first normal cook on V0

- **blocked-by:** V2.1 · **verify:** C · **board:** yes
- **design:** [10 §10.3 B5, §10.6](../design/10-test-and-release.md), [02 §2.9](../design/02-smoke-x-protocol.md)

Use the V0 build for a normal cook. Do not stage setpoint changes, receiver
button presses, probe detaches, or a special capture sequence. Pair once, let
the bridge record, use the app as intended, and sync before and after. This is
early dogfooding, not the V6.3 release cook.

Billows is out of scope for V0; it lands in M5 and the app hides the card while
`caps.billows_observe = 0`. This and V6.3 are the only tasks that need an actual
cook; protocol and Billows captures are bench-capable.

Keep a firmware serial log if one is already running; it is optional. The point
is to observe the product in normal use, not to run a test script.

Record what the cook shows:

- sample cadence, gaps, RSSI/SNR, and reconnect behavior,
- firmware counters (valid/bad packets, queue drops, heap) if the build exposes
  them,
- ring-log continuity after the cook and after a power cycle,
- battery behavior and any UX friction,
- anything that changes a design assumption.

Commit a short field report plus screenshots (and the serial log if captured).
Update `docs/hardware-verified.md` and the open-decisions table with what the
data proves or changes. If a result retires or creates a risk, adjust the
roadmap in the same change.

**Done when.** The report is committed; each open unknown touched by the cook is
advanced or explicitly left open; the roadmap reflects the result. Billows is
not exercised here; M5 owns it.
