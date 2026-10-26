# M4 — Settings & Actions

**Exit gate:** every setting the device cannot expose with one button is
editable from the phone, and forget/factory-reset/power-off work on the real
bridge. Destructive actions explain their cost before sending and handle the
disconnect as the expected outcome.

**Design:** [05 §5.5, §5.9](../design/05-ble-contract.md),
[06 §6.7](../design/06-app.md), [07 §7.4](../design/07-display-and-controls.md)

---

### F4.1 ble_service: config read/write

- **blocked-by:** F2.1, F1.5 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.9](../design/05-ble-contract.md)

Implement the 80-byte `config` characteristic: read, full write, validation
(bridge name, timeout, units). Probe name/role bytes and the Billows
mode/target bytes are reserved and ignored in the MVP. Persist to NVS and apply
runtime changes (OLED units/timeout). Reject any nonzero `billows_mode` with
`unsupported`; `caps.billows_control` is always 0.

**Done when.** Round-trip and every invalid case are host-tested; a real phone
changes units and display timeout and sees them on the OLED.

---

### F4.2 ble_service: control actions

- **blocked-by:** F2.3, F2.4, F1.8 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.5](../design/05-ble-contract.md)

Implement `forget_phone`, `factory_reset`, `power_off`, `clear_history`, and
`unpair_smoke_x`. Answer first, then act. `forget_phone` removes only the
current peer's bond; factory reset wipes config, log, and all bonds before
rebooting. Clear history writes a new random generation and keeps
pairing/config. Power off enters deep sleep. `set_billows_target` is reserved and
always returns `unsupported`; there is no Billows control path in the MVP.

**Done when.** Each op is host-tested for ordering, idempotency, and failure;
the destructive paths run on the board.

---

### F4.3 ble_service: destructive-action state and reconnect

- **blocked-by:** F4.2, F2.4 · **verify:** H/B · **board:** no / B
- **design:** [05 §5.12](../design/05-ble-contract.md)

Handle the link teardown after forget/factory/power correctly:

- send `result ok` before disconnect where possible,
- remove the current bond and re-advertise for forget (other bonds stay),
- wipe and reboot for factory reset,
- sleep for power off,
- restart advertising on a normal disconnect,
- do not leave the radio in a half-state if the app drops mid-op.

**Done when.** A host state test covers each path, including a power cut with
`clear_pending` set; the board re-advertises or sleeps as intended.

---

### A4.1 app: Settings shell

- **blocked-by:** A2.2, A3.1 · **verify:** H · **board:** no
- **design:** [06 §6.7](../design/06-app.md)

Implement the Settings root with sections: one Bridge section (status header
only), History & storage, Preferences, and About. Show current values; disable
Bridge controls with a reason when offline. Units are inside Preferences and
apply immediately. `Sync now` is a button in the Bridge status header, not a row.
Tapping the header opens Bridge details; do not add a separate `Bridge details`
button. Do not create a second Bridge group or a duplicate Bridge settings view.
Move Smoke X4 pairing, Billows, Bridge name and screen timeout into the Bridge
details sub-view. Label the local copy `Device log`, not `Phone history`.

**Done when.** Widget tests cover connected/offline/read-only, units, and
navigation; no duplicate rows, duplicate Bridge section, or save-all bar remain.

---

### A4.2 app: bridge settings

- **blocked-by:** A4.1, F4.1 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.7](../design/06-app.md)

Implement the editors:

- temperature units °F/°C inline in Preferences, applied immediately;
- bridge screen timeout 30/60/120/never;
- bridge name (≤15 chars, app-facing label);
- Smoke X4 pairing status + **Re-pair** (`unpair_smoke_x`);
- Billows detection/last-seen only; target is read-only and there is no mode or
  target editor.

There are no probe names or roles in the MVP. Use read-modify-write of the
whole config, show per-field saving/error, and never optimistically claim
success. Remove the bottom Save bar.

**Done when.** A real phone changes each field; a bad value is refused by the
bridge and the UI says why; the OLED reflects units and timeout.

---

### A4.3 app: destructive actions

- **blocked-by:** A4.1, F4.3 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.7, §6.8](../design/06-app.md)

Implement:

- **Forget this phone** — clear the saved connection + best-effort
  `forget_phone`; keep local history; explain if the bridge may still hold the
  pairing.
- **Factory reset bridge** — cost sheet listing pairings, settings, bridge log,
  and all phones; send; treat disconnect as success; clear the saved connection
  and return to setup; keep local history.
- **Power off bridge** — confirm; send; explain the 1.5 s PRG wake.
- **Clear bridge log** — confirm; generation boundary; device log kept.

**Done when.** Each action works on the real bridge; the app never reports
success before the device's `result` or the expected disconnect.

---

### A4.4 app: units and time end-to-end

- **blocked-by:** A4.2, A2.4, F2.3 · **verify:** H/P · **board:** no / phone
- **design:** [04 §4.4](../design/04-data-and-storage.md),
  [06 §6.7](../design/06-app.md)

Wire set_time on connect and unit display on every screen: Live tiles,
sparklines, History axis/tooltip/summary, the Billows target readout and OLED. There are no
probe labels to wire; identity is `P1`–`P4`.

**Done when.** A unit change persists across relaunch and updates Live and
History in the same frame; the clock is set once per connect.

---

### V4.1 Bench: all settings and actions

- **blocked-by:** A4.3, A4.4, F4.3 · **verify:** P · **board:** yes
- **design:** [10 §10.3 B2/B3](../design/10-test-and-release.md)

On the real bridge and phone:

1. Change every Device setting; verify read-back and OLED.
2. Forget this phone; verify bond removal and re-pair.
3. Re-pair the Smoke X4 from Settings; verify the log is preserved and the new
   channel is heard after SYNC.
4. Factory reset; verify config/log/pairings wiped and the app returns to setup.
5. Power off; verify the phone shows the wake instruction and hold-PRG wakes.
6. Clear bridge log; verify generation change, old app data preserved.
7. Kill the app mid-action; verify no half-state on the bridge.
8. Fill all 4 pairing slots (or host-test the cap); confirm the 5th pairing is
   refused with the named state and a paired phone can still forget one.

**Done when.** All eight pass; the destructive-action evidence is committed.
