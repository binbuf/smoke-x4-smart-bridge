# M7 — The bridge becomes a passthrough (v1.1)

**Exit gate:** the PRG button does two things and nothing else, and the app can do everything it
used to. Proven on the board and on the phone.

**Design:** [00 D15](../design/00-overview.md) · [07 §7.4](../design/07-display-and-controls.md) ·
[06 §6.2](../design/06-device-api.md) · [05](../design/05-connectivity-and-provisioning.md)

## Why

The on-device action set kept growing — per-page context actions, then a 2 s/5 s/10 s hold ladder,
then a menu — and each version was worse than the last. One button cannot carry eight verbs, and
asking a user to release inside a time-window is not an interface. D15 moves every control to the
app and leaves the device as a display that can be switched off.

Status 2026-07-23 — **all `board: no` work is done and host-green.** Firmware host suite 26/26;
Flutter `analyze` clean and `test` 515/515. What remains is the verification that needs the real
board and a real phone (below), plus the two follow-ups in *Known gaps*.

---

## Done (`board: no`)

### F16.1 app_ui: reduce the button to tap-cycles-views and hold-powers-off
- **verify:** H · **board:** no · **design:** [07 §7.4](../design/07-display-and-controls.md)

Gesture machine drops to TAP + HOLD; double-tap, the hold ladder, the menu, and eight of the nine
actions are deleted. Tap now emits on release *immediately* — with nothing to disambiguate against
there is no 400 ms wait, so view-cycling has no lag. `op_perform` is one guard clause.

**Done when:** a release under 400 ms is a TAP and a release past 2 s is a HOLD, with the
400 ms–2 s window deliberately nothing; the power-off confirm counts down and then reads
`release to confirm`; an alarm is displayed and a tap dismisses it *without* performing any action.

### F16.2 app_api: the three destructive verbs over HTTP
- **verify:** H · **board:** no · **design:** [06 §6.2](../design/06-device-api.md)

`POST /api/v1/restart`, `/factory-reset`, `/power-off`, behind the existing bearer gate and through
the injected ops seam. All answer first and act on a ~500 ms timer; `factory-reset` wipes before
scheduling the reboot so a lost timer cannot half-wipe a bridge.

**Done when:** each route fires its op exactly once, returns the deferral text, 501s when unwired,
500s on a failed wipe, and refuses GET.

### F16.3 app_ble: ops 12 `set_battery_saver` and 13 `power_off`
- **verify:** H · **board:** no · **design:** [05](../design/05-connectivity-and-provisioning.md)

Additive growth on the frozen v1 op table. Saver is tri-state (off/on/auto) via a generated enum so
BLE and `POST /config/device` cannot disagree about `auto`. `power_off` joins reboot/factory_reset
in the answer-first-then-execute branch.

**Done when:** the saver round-trips all three states and rejects a bad value; `power_off` answers
before the link dies.

### A16.4 app: every departed control reachable from the phone
- **verify:** H · **board:** no · **design:** [08](../design/08-flutter-app.md)

New `ControlCommand.reboot/factoryReset/powerOff`, `BridgeConfig.batterySaver`, and an
`applyNetwork()` method (a method, not a config field — switching to AP returns a generated PSK the
user must read to rejoin, and a `void configure` would throw it away). New **Power** settings
section; battery-saver tri-state; **Re-scan / Unpair** buttons that had plumbing and no UI; and
AP↔STA finally wired — `onApply` was literally `async {}`.

**Done when:** each verb lands on the right route/op, the tri-state round-trips, destructive
controls confirm first and name the real consequence, and the power-off dialog says the bridge can
only be woken by physically holding PRG.

---

## Open — needs the board (`board: yes`) or the phone

### V5.1 bench: the button does two things and only two
- **verify:** B · **board:** yes

Tap cycles all five views with no perceptible lag. Hold shows the countdown, then
`release to confirm`; releasing before 2 s does nothing. Releasing after it sleeps the board.

### V5.2 bench: deep-sleep wake, and the GPIO0 strap question
- **verify:** B · **board:** yes

**Still the one unproven hardware risk.** GPIO0 is the ROM download-mode strap; a wake press held
through the strap sample may drop the S3 into USB download mode instead of our firmware. If it
does, the wake source moves to the RST button. Also measure real deep-sleep current on battery.

### V5.3 bench: the destructive HTTP verbs, for real
- **verify:** B · **board:** yes

`POST /api/v1/restart` end-to-end with the bridge on the network. The answer-before-act *ordering*
is host-tested through the ops seam, but the actual flush-before-`esp_restart()` timing has never
run on hardware — the board did not associate with Wi-Fi during M7. Then `/power-off`, and confirm
the only way back is holding PRG.

### V5.4 phone: every control, against a real bridge
- **verify:** B · **board:** yes

Units, start/stop, mark, re-scan/unpair, battery saver (all three), AP↔STA both directions
(including reading back the generated AP PSK and rejoining), restart, power off, factory reset.
Over **both** transports — HTTP on the LAN and BLE with Wi-Fi off — since several verbs take
different paths per transport.

### V5.5 bench: alarm is displayed, never silenced on the device
- **verify:** C · **board:** yes · real cook

Fire a real alarm. The glass shows it and forces view 1; a tap dismisses the overlay and moves on
while the alarm stays active in `/status` and on the strip. Silence it on the Smoke X receiver and
on the app, and confirm the device never claims to have.

---

## Known gaps (deliberate, not defects)

1. **The network page's *current* mode is optimistic.** It shows what was last applied from that
   screen, defaulting to STA. `/status` does not carry net mode; reading it truly needs either a
   `GET /config/wifi` on the interface or a WebSocket on screen entry. It was hardcoded before, so
   this is not a regression — but the display can be wrong until you touch it. **Follow-up: add net
   mode to `/status`.**
2. **Route wiring has no test.** Routes need `AppEnv` and are widget-tested nowhere in this
   codebase, so both *sides* of the seam are covered (views by key/callback, transports by
   contract) but `onApply → applyNetwork` is verified only by the analyzer. This is the same
   pre-existing gap that let `async {}` sit there undetected.
3. **Power-off is asymmetric by design.** It can be sent from the app; waking is physical. Every
   client that offers it must say so first.
