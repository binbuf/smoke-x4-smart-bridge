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
- Depends on T46a, T49, T52, T53 and T54.

## Scope
- [x] Change every Bridge/Preferences setting; verify read-back, persistence and the OLED. Check units, Appearance, Bridge name and screen timeout copy. (Continuation 2: °C/°F and 30 s/1 min confirmed on the panel.)
- [x] Forget this phone; verify bond removal, re-pair, and the orphaned `History on this phone` entry.
- [x] Reject a wrong passkey once, confirm the named `The code didn’t match`
      state, then complete a correct re-pair. Confirm the bond survives a bridge
      reboot with no prompt. This absorbs the T37 wrong-code/bond residual.
- [x] Re-pair the Smoke X4 from Settings; verify the log is preserved and the new channel is heard after SYNC. (Continuation 2: SYNC beep → `pair ACK sent on 918500000 Hz`, seq continued 2710→2714.)
- [x] Factory reset; verify config/log/pairings wiped, the app returns to Setup, and phone history is kept.
- [x] Power off; verify the `Bridge is off` screen and hold-PRG wake.
- [x] Clear history on the Bridge; verify the generation change and that old app data is preserved.
- [x] Kill the app mid-action; verify no half-state on the bridge.
- [x] Fill all 4 pairing slots (or host-test the cap); confirm the 5th pairing is refused with the named state and a paired phone can still forget one.
- [x] Walk Settings/Bridge details in 13 §13.4 connected and offline; no duplicate rows, no save-all bar, no `Device log` copy, no lab entry in release.
- [x] Re-check the T46a History/connection fixes on the real phone: offline probe semantics, sparkline backfill, saved-ID header, blocked sync card, `Not synced` gap label, range-scoped Cooks/loss banner, and Bridge-reboot recovery.

## Out of scope
- 24 h soak, field cook and release hardening → M6 (T61–T68).
- Billows observation bench evidence and target validation → M5 Billows (T56, T57, T59).
- New features or UI changes discovered during the walk; file them against the owning task rather than fixing scope here.
- Firmware host suite → T47–T49; app unit/widget gate → T54.
- Wi-Fi/HTTP/OTA, local web UI, notifications, on-device factory-reset gesture — outside MVP; no task owns it.

## Design notes
- **Bench safety before the destructive walk.** Back up the `nvs` and `samples`
  partitions (flash-read, hash both, store under `artifacts/bench/T55/`) and
  record the running image hash before forget/factory-reset/power-off. The T49
  image hash and the T46/T52 destructive state notes are the reference. Write
  the re-pair plan for the Bridge and the Smoke X4 before starting; restore the
  backups rather than leaving the shared board half-wiped. Confirm the phone is
  unlocked before the phone walk — it was PIN-locked at T46a.
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
- [x] All nine checks pass on the real bridge and phone.
- [x] The destructive-action evidence is committed.
- [x] The Settings UI matches the approved contract in both themes at 320 dp.
- [x] Hand-off below filled in.

## Hand-off

**Result: partial pass (tree green).** The app-driven walk is complete on the
real Pixel 11 Pro Fold + Heltec V3, including every setting, forget/wrong-code/
re-pair, clear (normal and app-killed), power off/PRG wake, factory reset and the
T46a offline/reboot re-check. Continuation 1 closed the seeded History gap: on a
debug install over the real phone archive, the 24 h chart draws the dashed
`Not synced` band and its label (390 and 320 dp), the permanent-loss banner sits
below Summary/Cooks, and the 1 h range drops both the banner and the long cook
(range-scoped). The real archive, release APK and live X4 link were restored;
`seed-01`-`seed-05` are the evidence. Two release defects were found and fixed:

1. **Clear history crashed and boot-looped the bridge.** The clear sweep used a
   4 KB stack buffer on the 3.5 KB `esp_timer`/main tasks. Fixed with a 256 B
   chunked scan in `firmware/components/sample_log/log_flash_core.c` (ADR 0060).
   Retested clear, mid-action kill and reboot-after-clear on the board.
2. **Setup scan row printed sentinels** (`P4 -3277°F · 255%`) for a blank/reset
   Bridge. `BridgeAdvertisement.preview` is now nullable and omits invalid/
   detached temperatures and unknown battery; `setup_codec_test.dart` covers it.

**Evidence:** `artifacts/bench/T55/README.md` and
`docs/progress/T55.md`. Final release image SHA-256
`02E2E2B4DA3013E14E3AED57A2D5505417B5214C263F2C7F43009ED3340F61F6`;
release APK `2E095C5343D0D7350B574EE376A9E7D59963571745363296026ABD6B1505F28C`.

**Continuation 2 — manual checks completed (2026-10-28).** With the operator at
the bench:

- **OLED units:** °C and °F both confirmed on the panel by the operator while the
  app showed `Saved on the Bridge`; screenshots `t55-units-celsius-final.png` and
  `t55-units-fahrenheit-final.png` plus `t55-units-*-final.xml`.
- **OLED timeout:** 30 s confirmed to sleep the panel and wake on a PRG tap, then
  restored to 1 min; `t55-timeout-30sec-final.png` plus the operator confirmation.
- **Smoke X4 SYNC re-pair:** Settings → Re-pair cleared the old radio pairing
  (`unpair_smoke_x: pairing cleared, scanning 915/920`); the operator held the X4
  button until it beeped; the Bridge answered `pair ACK sent on 918500000 Hz` and
  frames resumed. The log was preserved (`gen 081936f6`, `stored seq 2710` →
  `2714`). Evidence: `x4-repair-serial.log`, `t55-x4-repair-sync-steps.png`,
  `t55-x4-repair-done.png`.
- **Power off / OFF overlay:** the operator confirmed the panel `OFF` overlay and
  then held PRG ~1.9 s; the boot log shows
  `deep-sleep wake: confirming PRG hold` → `hold-to-wake confirmed`, recovered
  `seq 0..2712`, re-advertised and resumed `stored seq=2713`. Evidence:
  `t55-poweroff-screen.png`, `x4-repair-serial.log`. The app itself stayed on
  `Bridge is off` until relaunch — the known T43/T46a follow-up, not a new
  failure.
- **Not captured:** a panel photo of the `RESETTING` overlay (the factory-reset
  copy, `result ok`, reboot, wipe and orphaned history are already evidenced);
  the panel photos were operator-confirmed in this hand-off rather than captured.
- **Five physical phones** for the 4-slot cap: the task allows the host test,
  which passes (`ble-adv` bond limit + setup full-store widget test).

**Checks:** `verify_host.ps1` → 25/25 CTest pass (re-run in continuation 1);
`flutter analyze` → clean; `flutter test --timeout 180s` → full suite pass;
`make bench-test` pass; firmware release build and flash verified on the board.
No product code changed in continuation 1.

**Bench state:** pre-run NVS/samples backups are under
`artifacts/bench/T55/backup/` (binaries local-only, hashes committed). The board
was restored to the pre-run log/generation and X4 pairing, phone re-paired on
the release image, 1 bond slot used, recording. The phone archive was backed up
before the seeded run (`backup/phone-archive-pre-seed.db`, SHA-256 in
`SHA256SUMS.txt`) and restored afterwards. Do not restore the NVS backup
again after pairing: it reintroduces a stale bond and the link loops on
`disconnected reason 0x23d`. To repeat the pairing steps, use the temporary
passkey log / one-time bond clear dance described in `docs/progress/T55.md`,
then reflash the release image.

