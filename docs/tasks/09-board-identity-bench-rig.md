# T09 — Board identity, bench rig, and deep-sleep gate

## Goal
Confirm on the bench that the board is the expected Heltec V3 and answer the
GPIO0/hold-PRG deep-sleep wake question with recorded evidence. The sitting also
clears the board's existing flash — including a legacy NVS entry that pairs it to
a Smoke X4 — so the new build starts from a known clean state. The result
unblocks all firmware power work and the real-capture tasks.

## Context (read first)
- Design: [01 §1.4, §1.9](../design/01-hardware.md),
  [07 §7.7](../design/07-display-and-controls.md)
- Verification: **B** (bench/board) · Board required: **yes**
- Depends on T04.
- This answers open decision Q1 (exact board is Heltec V3) and Q3 (GPIO0
  deep-sleep wake works) from [README](README.md#open-decisions-that-block-tasks).
- The board is already on USB and may still hold a legacy image with an NVS
  pairing entry for a Smoke X4. That entry is not read by the new firmware; this
  task archives it and wipes the flash deliberately.
- Bench sitting, one session; board time is serialized, so batch with other
  board tasks where possible.

## Scope
One bench sitting:

- [ ] Before flashing anything new, read the current state of the board as
      found: `idf.py -p <COM> version` (or the running build's banner on the
      serial console) and `idf.py -p <COM> partition-table`. Record the image
      name/version, git commit and partition layout.
- [ ] Before wiping, archive the stale pairing/config state if it is still
      readable: dump the `nvs` partition and keep the blob (and any offset dump
      of the smoke-X4 pairing entry) as an artifact, so the old
      `{device_id, frequency_hz, num_probes}` can be inspected later.
- [ ] Wipe the board: `idf.py -p <COM> erase-flash`. The legacy pairing entry is
      not read by the new `bridge_config`; this is a deliberate clean slate, not
      a compatibility step.
- [ ] Confirm the wipe: a second `partition-table` read shows no leftover app or
      legacy data, and the board boots only after the bench image is flashed.
- [ ] Confirm the board is the Heltec WiFi LoRa 32 V3, 8 MB flash, SX1262,
      SSD1306.
- [ ] Fit the antenna; verify Vext/OLED, PRG, battery divider.
- [ ] Flash a **bare BLE advertising + deep-sleep test image** (an IDF example,
      not the product service) and confirm advertising, then sleep.
- [ ] Test hold-PRG wake 20 times with USB attached and detached.
- [ ] Measure on/advertising/sleep current; run the pack for 24 h if time
      allows.
- [ ] Record every result in `docs/hardware-verified.md`.

## Out of scope
- Building the product BLE service or firmware features — M1/M2.
- The power decision record and fallback selection — owned by T11.
- Real X4 traffic capture — owned by T10.
- Deep-sleep/power feature implementation — M1/M4, gated on T11.
- Wi-Fi/HTTP/OTA test images as product code — no task; outside MVP (the IDF
  example is a bench probe only).
- Migrating, preserving or re-importing the legacy NVS pairing — no task; the
  new firmware owns its own pairing record and never reads the old one.
- Unpairing the board from the Smoke X4 through the old firmware's UI — no
  task; the flash wipe supersedes it.

## Design notes
- **Flash ownership before this task:** the board is already on USB and may
  carry a legacy image with an NVS pairing entry for a Smoke X4. Read the
  running image and partition table first, archive what is readable, then erase
  the whole flash. Nothing on the board is a dependency of the new build.
- The legacy pairing entry is **not** a compatibility concern: the new
  `bridge_config` (T15) uses its own namespaces and `config_version`, and the
  radio only tunes from a pairing record written after `CONFIRMED` (T16). A
  stale entry is inert; the wipe exists to remove ambiguity, not to fix a read
  path.
- Archive before erasing; `erase-flash` is destructive and there is no undo.
  Keep the NVS blob with the bench evidence so a later confusion can be traced
  to a concrete old value.
- Do not attempt to unpair from the Smoke X4 before wiping. The X4 keeps
  broadcasting on its own channel regardless of what this board remembers, and
  the stock receiver is unaffected.
- After the wipe, the bench image is the only thing on the board. If the wipe
  fails or the board refuses to enumerate, record that and stop rather than
  flashing over a half-erased board.
- The test image is an **IDF example**: bare BLE advertising plus deep sleep,
  explicitly not the product service. Do not let it become product code.
- Test with the antenna fitted; verify Vext/OLED, PRG, and the battery divider
  as part of the same sitting.
- Hold-PRG wake is tested 20 times in each condition: USB attached and USB
  detached. Record successes/failures, not just a verdict.
- Measure current in three states: on, advertising, sleep. The 24 h pack run is
  time-permitting but should be attempted.
- Every result goes in `docs/hardware-verified.md` — no verbal-only findings.
- If wake enters ROM download, record the fallback decision **before** any
  power-feature work; T11 writes the formal decision.
- GPIO0 wake behaviour is Q3; board identity is Q1. Do not silently pick an
  alternative board or wake mechanism.

## Done when
- [ ] The as-found image, version and partition layout are recorded.
- [ ] Any readable legacy pairing/NVS state is archived as an artifact.
- [ ] `erase-flash` completes and a follow-up partition-table read shows a clean
      board.
- [ ] The board identity is written down in `docs/hardware-verified.md`.
- [ ] The GPIO0 wake answer is written down in `docs/hardware-verified.md`.
- [ ] If wake enters ROM download, the fallback decision is recorded before any
      power-feature work.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
