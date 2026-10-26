# M4 — Settings & Actions

**Exit gate:** every setting the device cannot expose with one button is
editable from the phone, and forget/factory-reset/power-off work on the real
bridge. Destructive actions explain their cost before sending and handle the
disconnect as the expected outcome. Settings, confirmations, 320 dp, dark/light,
accessibility and copy lint match the approved UI contract.

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
- **design:** [06 §6.7](../design/06-app.md),
  [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations)

Implement the approved Settings root:

- one `Bridge` section whose status header opens Bridge details; no separate
  `Bridge details` button or second Bridge group;
- `History & storage` as one destination row;
- `Preferences` with `Temperature units` (immediate) and `Appearance`
  (`System / Light / Dark`, local);
- `About` / `About this app`;
- offline controls disabled with a short inline reason; local delete/forget stay
  available;
- `Sync now`/`Reconnect` and `Disconnect` only inside Bridge details.

Move Smoke X4 pairing, Billows, Bridge name and Bridge screen timeout into the
Bridge details sub-view. Label the local archive `History on this phone`, not
`Device log`.

**Done when.** Widget tests cover connected/offline/read-only, units, appearance,
and navigation; no duplicate rows, duplicate Bridge section, save-all bar or
`Device log` copy remain.

---

### A4.2 app: bridge settings

- **blocked-by:** A4.1, F4.1 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.7](../design/06-app.md),
  [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations)

Implement the approved editors and Bridge details:

- temperature units `°F`/`°C` inline in Preferences, applied immediately;
- Appearance `System / Light / Dark`, persisted and applied on launch;
- Bridge screen timeout 30 sec / 1 min / 2 min / Never with the approved
  subtitles;
- Bridge name (≤15 chars, app-facing label) with `Saving…` / `Saved` /
  `Couldn’t save`;
- Smoke X4 pairing status (`Receiving readings` only when fresh, otherwise
  `No readings for 4 min`/`Signal lost`/`Not paired`) and `Re-pair Smoke X4`
  (`unpair_smoke_x`);
- Billows detection/last-seen only; target is read-only and there is no mode or
  target editor;
- `Technical details` collapsed (Bridge ID, firmware, protocol, signal, MTU,
  connected for, last synced) and one `Connection log` covering Bridge, X4,
  Billows and sync events;
- Bridge actions rows: `Power off the Bridge`, `Factory reset Bridge`,
  `Forget this phone`.

There are no probe names or roles in the MVP. Use read-modify-write of the whole
config, show per-field saving/error, and never optimistically claim success.
Remove the bottom Save bar.

**Done when.** A real phone changes each field; a bad value is refused by the
bridge and the UI says why; the OLED reflects units and timeout; offline
controls are disabled with the approved reasons; the Smoke X4 state and
connection log match the contract.

---

### A4.3 app: destructive actions

- **blocked-by:** A4.1, F4.3 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.7, §6.8](../design/06-app.md),
  [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations)

Implement the approved destructive flows:

- **Forget this phone** — clear the saved connection + best-effort
  `forget_phone`; keep local history; explain if the Bridge may still hold the
  pairing; return to Setup with the `History on this phone` escape.
- **Factory reset Bridge** — cost sheet naming all paired phones, settings,
  saved readings and clock; send; treat disconnect as success; clear the saved
  connection and return to Setup; keep local history and show the orphaned
  history entry.
- **Power off the Bridge** — confirm; send; show the `Bridge is off` screen and
  the 1.5 s PRG wake instruction.
- **Clear history on the Bridge** — confirm; generation boundary; phone history
  kept.

Use the exact loss copy in 12 §12.2. No action reports success before the
device’s `result` or the expected disconnect.

**Done when.** Each action works on the real bridge; the sheet names exact loss,
count and date range where applicable; Setup shows saved history after forget or
reset; no `current cook` copy remains.

---

### A4.4 app: units and time end-to-end

- **blocked-by:** A4.2, A2.4, F2.3 · **verify:** H/P · **board:** no / phone
- **design:** [04 §4.4](../design/04-data-and-storage.md),
  [06 §6.7](../design/06-app.md),
  [13 §13.5](../design/13-ui-implementation-contract.md#units-theme-and-locale)

Wire set_time on connect and one conversion path on every screen: Live tiles,
sparklines, History axis/tooltip/Summary, Cook view, Billows target readout,
confirmations, storage counts and OLED. Apply theme and locale formatting at the
same layer. There are no probe labels to wire; identity is `P1`–`P4`.

**Done when.** A unit change persists across relaunch and updates Live, History,
Cooks and Billows in the same frame; theme persists; the clock is set once per
connect; locales/12–24-hour time are respected.

---

### A4.5 app: UI state matrix, accessibility and copy gate

- **blocked-by:** A3.3, A3.6, A4.3, A4.4 · **verify:** H · **board:** no
- **design:** [13 §13.4, §13.6, §13.8](../design/13-ui-implementation-contract.md),
  [12 §12.3, §12.6](../design/12-copy-and-label-review.md)

Turn the prototype review into a production gate:

- widget tests for every state in 13 §13.4 that is reachable without hardware;
- 320 dp and 390 dp layout tests for Live, History, Settings and the Cook view;
- dark/light screenshot set regenerated from the production widgets;
- semantics for the connection card, probe tiles, chart summary, filter menus,
  Summary rows and destructive actions;
- WCAG AA contrast and 48 dp target audit for chart controls and destructive
  buttons;
- centralize product strings, use locale date/time/number formatting, and add a
  banned-term copy test from 12 §12.6;
- reduced-motion behavior and no colour-only state.

**Done when.** The matrix is green, the screenshot set is reviewed and committed,
the copy-lint test fails on a banned term, the accessibility checks pass on a
320 dp phone, and no fixture/simulation string reaches a product screen.

---

### V4.1 Bench: all settings and actions

- **blocked-by:** A4.3, A4.4, A4.5, F4.3 · **verify:** P · **board:** yes
- **design:** [10 §10.3 B2/B3](../design/10-test-and-release.md)

On the real bridge and phone:

1. Change every Bridge/Preferences setting; verify read-back, persistence and
   OLED. Check units, Appearance, Bridge name and screen timeout copy.
2. Forget this phone; verify bond removal, re-pair, and the orphaned `History on
   this phone` entry.
3. Re-pair the Smoke X4 from Settings; verify the log is preserved and the new
   channel is heard after SYNC.
4. Factory reset; verify config/log/pairings wiped, the app returns to Setup, and
   phone history is kept.
5. Power off; verify the `Bridge is off` screen and hold-PRG wake.
6. Clear history on the Bridge; verify generation change, old app data preserved.
7. Kill the app mid-action; verify no half-state on the bridge.
8. Fill all 4 pairing slots (or host-test the cap); confirm the 5th pairing is
   refused with the named state and a paired phone can still forget one.
9. Walk Settings/Bridge details in 13 §13.4 connected and offline; no duplicate
   rows, no save-all bar, no `Device log` copy, no lab entry in release.

**Done when.** All nine pass; the destructive-action evidence is committed; the
Settings UI matches the approved contract in both themes at 320 dp.
