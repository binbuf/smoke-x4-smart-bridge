# T55 — Bench: all settings and actions

## Goal
Prove on the real bridge and phone that every Setting, re-pair, destructive action and recovery path works as specified, with no half-states and no leftover prototype chrome. This is the M4 bench gate.

## Context (read first)
- [10 §10.3 B2/B3](../design/10-test-and-release.md) — BLE and app bench matrix.
- [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations) — Settings, Bridge details and confirmation states to walk connected and offline.
- [06 §6.7](../design/06-app.md) — approved Settings and Bridge details behaviour.
- [05 §5.12](../design/05-ble-contract.md) — forget/factory-reset/power-off consequences.
- [12 §12.2](../design/12-copy-and-label-review.md) — exact destructive copy and `History on this phone` naming.
- **Verify:** P (phone + board) · **Board:** yes
- Depends on T52, T53, T54 and T49.

## Scope
- [ ] Change every Bridge/Preferences setting; verify read-back, persistence and the OLED. Check units, Appearance, Bridge name and screen timeout copy.
- [ ] Forget this phone; verify bond removal, re-pair, and the orphaned `History on this phone` entry.
- [ ] Reject a wrong passkey once, confirm the named `The code didn’t match`
      state, then complete a correct re-pair. Confirm the bond survives a bridge
      reboot with no prompt. This absorbs the T37 wrong-code/bond residual.
- [ ] Re-pair the Smoke X4 from Settings; verify the log is preserved and the new channel is heard after SYNC.
- [ ] Factory reset; verify config/log/pairings wiped, the app returns to Setup, and phone history is kept.
- [ ] Power off; verify the `Bridge is off` screen and hold-PRG wake.
- [ ] Clear history on the Bridge; verify the generation change and that old app data is preserved.
- [ ] Kill the app mid-action; verify no half-state on the bridge.
- [ ] Fill all 4 pairing slots (or host-test the cap); confirm the 5th pairing is refused with the named state and a paired phone can still forget one.
- [ ] Walk Settings/Bridge details in 13 §13.4 connected and offline; no duplicate rows, no save-all bar, no `Device log` copy, no lab entry in release.

## Out of scope
- 24 h soak, field cook and release hardening → M6 (T61–T68).
- Billows observation bench evidence and target validation → M5 Billows (T56–T60).
- New features or UI changes discovered during the walk; file them against the owning task rather than fixing scope here.
- Firmware host suite → T47–T49; app unit/widget gate → T54.
- Wi-Fi/HTTP/OTA, local web UI, notifications, on-device factory-reset gesture — outside MVP; no task owns it.

## Design notes
- Run on the real bridge and a real phone, release build, both dark and light themes, 320 dp.
- This is the board-serialized M4 gate; record the board and phone model with the evidence.
- "Persistence" means across app relaunch and, where applicable, bridge reboot: units, Appearance, Bridge name and timeout must read back identically.
- OLED checks are part of the setting result, not a separate cosmetic check: units and screen timeout must be visibly applied.
- Destructive evidence must include the confirmation copy shown, the `result`/disconnect outcome, and the post-action app state (Setup or `Bridge is off`).
- `History on this phone` must survive forget, factory reset and clear-history. The orphaned entry is the visible proof after forget/reset.
- Re-pairing the Smoke X4 must preserve `History on the Bridge`, phone bonds and settings; only the old radio pairing is cleared.
- The pairing cap is 4 phones, no eviction. The 5th attempt gets the named `This Bridge already has 4 phones paired` state, and an existing paired phone can still forget its own bond.
- A mid-action app kill must leave the bridge either fully before or fully after the action, never half-wiped or half-unpaired. Check the `clear_pending` recovery if the kill lands during a destructive op.
- Settings walk uses 13 §13.4, not a memory of the prototype. Confirm one Bridge section, one `History & storage` row, `Sync now`/`Reconnect` and `Disconnect` only in Bridge details, and no `Device log`.
- Design: [10 §10.3 B2/B3](../design/10-test-and-release.md), [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations), [05 §5.12](../design/05-ble-contract.md).

## Done when
- [ ] All nine checks pass on the real bridge and phone.
- [ ] The destructive-action evidence is committed.
- [ ] The Settings UI matches the approved contract in both themes at 320 dp.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
