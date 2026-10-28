---
verify: powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1
---
# T49 — ble_service: destructive-action state and reconnect

## Goal
Make the BLE link behave correctly after forget, factory reset and power off: answer, tear down once, then re-advertise, reboot or sleep as intended. The radio must never be left in a half-state when the app drops mid-action.

## Context (read first)
- [05 §5.12](../design/05-ble-contract.md) — procedures and the expected disconnect for forget/factory reset/power off.
- [05 §5.5](../design/05-ble-contract.md) — answer-first ordering and the ≈250 ms action timer.
- [05 §5.2](../design/05-ble-contract.md) — advertising start/stop conditions, interval and local name.
- [05 §5.11](../design/05-ble-contract.md) — bond ownership and factory-reset scope.
- [03 §3.5.1](../design/03-firmware-architecture.md) — power state; [03 §3.5.2](../design/03-firmware-architecture.md) — BLE link state.
- [03 §3.13](../design/03-firmware-architecture.md) — host and firmware build commands.
- **Verify:** H/B · **Board:** no / B
- Depends on T48 and T30.
- **Post-T36 status:** ordinary disconnect recovery already landed.
  `ble_service_keep_advertising()` runs from the housekeeping tick, restarts at
  the current fast/slow interval when the host is synced, idle and not
  advertising, and the GAP callback now receives connect/disconnect/passkey
  events directly. The destructive paths below remain open.

## Scope
- [x] Send `result ok` before disconnect where possible.
- [x] Forget: remove the current bond, disconnect the link, and re-advertise; other bonds stay intact.
- [x] Factory reset: wipe config, log and all bonds, then reboot.
- [x] Power off: enter deep sleep and stop advertising.
- [x] Restart advertising on a normal disconnect (app closed, out of range,
      failed connect or advertising timeout) — `ble_service_keep_advertising()`
      plus the housekeeping tick; keep the host state test.
- [x] Restart advertising after a forget, with the current bond gone and the remaining bonds unaffected.
- [x] Do not leave the radio in a half-state if the app drops mid-op: the action either completed before the link was lost or remains pending with a defined recovery on the next boot/connect.
- [x] Handle a power cut during a destructive op, including the `clear_pending` state, so boot resolves to a defined outcome rather than a half-wiped or half-unpaired bridge.
- [x] Add a host state test for each path: result-then-disconnect, forget re-advertise, factory wipe-and-reboot, power-off sleep, normal disconnect re-advertise, app-drop mid-op and power cut with `clear_pending` set.
- [x] Board-verify that the bridge re-advertises after forget and a normal disconnect, reboots after factory reset, and sleeps after power off. *(Deferred to T55 per the bench-safety note; state transitions are host-proven here.)*

## Out of scope
- Control op parsing, validation and status mapping → T48.
- `config` read/write → T47.
- App-side destructive flows, copy and Setup return → T52.
- Deep-sleep GPIO0/PRG wake behaviour → T23 (T23); this task only enters sleep.
- Boot-time factory-reset gesture or button menu — outside MVP; no task owns it.
- Billows control path — M5 Billows (T56, T57, T59); `caps.billows_control` is always 0.

## Design notes
- Ordering: validate the whole body → persist any state the next boot needs → send `result ok` → wait ≈250 ms → tear down/reboot/sleep. Never disconnect before the result where a result can be sent.
- `factory_reset` wipes before scheduling the reboot; a lost timer must not leave a half-wiped device.
- Forget is current-bond-only. Other bonded phones remain and must still connect after the link returns.
- The app clears its local bond after `result ok` or after the disconnect, whichever comes first; firmware must make both orders safe.
- Advertising: starts at boot when not connected, on disconnect, after a failed connect and on advertising timeout; stops on connection. Interval is 250 ms for 60 s after boot/button/disconnect, then 1,000 ms. Local name is `SmokeX4-XXXX`, last two BLE MAC bytes in uppercase hex.
- The host state test must explicitly set `clear_pending` to simulate a power cut during a destructive op. Define and assert the boot outcome rather than leaving it implicit; do not advertise in an in-between state.
- Deep sleep is the power-off outcome; waking requires holding PRG for 1.5 s (07 §7.4 / T23). Do not add a second wake path.
- BLE link state and Smoke X4 link state are separate (03 §3.5.2); a phone disconnect must not be reported as an X4 loss.
- Design: [05 §5.12](../design/05-ble-contract.md), [05 §5.2](../design/05-ble-contract.md), [03 §3.5.1](../design/03-firmware-architecture.md), [03 §3.5.2](../design/03-firmware-architecture.md).
- **Bench safety for this slice:** the phone-side destructive client is T52 and the shared bench board must not be factory-reset, forgotten or powered off unattended. Implement and host-test the state machine, build the image and record its hash; defer the destructive board walk to T55 with an NVS/samples backup and a re-pair plan.

## Done when
- [x] A host state test covers each path, including a power cut with `clear_pending` set, and asserts the resulting advertising/sleep/reboot state.
- [x] The destructive board walk (forget re-advertise, factory reboot, power-off sleep) is **deferred to T55** per the bench-safety note; this task proves each state transition in host tests and builds the T49 image with its hash recorded.
- [x] No path leaves the radio advertising while connected or silent while it should be advertising.
- [x] `ctest --test-dir firmware/test/build` passes.
- [x] Hand-off below filled in.

## Hand-off

Implemented the destructive-action link lifecycle (T49).

**Changed:** `ble_destructive.{c,h}` (new pure state machine + boot plan),
`ble_service.c` (result/disconnect/timer/failed-action gating, captured forget
peer, `ble_service_prepare_sleep()`), `boot.c` (power-off stops advertising
before sleep), `test_ble_destructive.c` + CMake, 05 §5.12, 03 §3.5.2, ADR 0053.

**Result:** `tools/ci/verify_host.ps1` → 25/25 CTest passed. Firmware image
built with the T48 defaults; `sx4_bridge.bin` 603,408 B, SHA-256
`3AC8537D997339BB06BB0D2EA60FFC6AD48EC4A07187D080F036266E0831658F`.

**Deviation:** the destructive board walk is deferred to T55 by the task's
bench-safety note (shared board must not be factory-reset/forgotten/powered off
unattended). The 50 ms factory reboot timer is unchanged.

**Next:** T52 maps the app confirmations/statuses; T55 flashes this exact image
with an NVS + samples backup and a re-pair plan, then walks forget re-advertise,
factory reboot, power-off sleep and the clear-generation boundary.
