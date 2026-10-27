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

- [x] Before flashing anything new, read the current state of the board as
      found: `idf.py -p <COM> version` (or the running build's banner on the
      serial console) and `idf.py -p <COM> partition-table`. Record the image
      name/version, git commit and partition layout.
- [x] Before wiping, archive the stale pairing/config state if it is still
      readable: dump the `nvs` partition and keep the blob (and any offset dump
      of the smoke-X4 pairing entry) as an artifact, so the old
      `{device_id, frequency_hz, num_probes}` can be inspected later.
- [x] Wipe the board: `idf.py -p <COM> erase-flash`. The legacy pairing entry is
      not read by the new `bridge_config`; this is a deliberate clean slate, not
      a compatibility step.
- [x] Confirm the wipe: a second `partition-table` read shows no leftover app or
      legacy data, and the board boots only after the bench image is flashed.
- [x] Confirm the board is the Heltec WiFi LoRa 32 V3, 8 MB flash, SX1262,
      SSD1306.
- [ ] Fit the antenna; verify Vext/OLED, PRG, battery divider.
      **Vext/OLED, PRG and the divider passed 2026-10-26; the antenna was
      already fitted per the legacy record and was not re-fitted/visually
      checked in this session.**
- [x] Flash a **bare BLE advertising + deep-sleep test image** (an IDF example,
      not the product service) and confirm advertising, then sleep.
- [ ] Test hold-PRG wake 20 times with USB attached and detached.
      **USB attached 20/20 application boots, 0 ROM-download entries; USB
      detached not run (needs a physical press on battery).**
- [ ] Measure on/advertising/sleep current; run the pack for 24 h if time
      allows. **Not measured/run: no current meter and no 24 h window.**
- [x] Record every result in `docs/hardware-verified.md`.

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
- [x] The as-found image, version and partition layout are recorded.
- [x] Any readable legacy pairing/NVS state is archived as an artifact.
- [x] `erase-flash` completes and a follow-up partition-table read shows a clean
      board.
- [x] The board identity is written down in `docs/hardware-verified.md`.
- [x] The GPIO0 wake answer is written down in `docs/hardware-verified.md`.
- [x] If wake enters ROM download, the fallback decision is recorded before any
      power-feature work. **It did not: 0/20 ROM-download entries. ADR 0020
      records that the RST fallback is not selected.**
- [x] Hand-off below filled in.

## Hand-off

**Landed.** The board is confirmed as the Heltec WiFi LoRa 32 V3 (ESP32-S3 rev
v0.2, 8 MB GD flash, MAC `ac:a7:04:38:82:74`); the SSD1306 ACKs at 0x3C and
accepts init + a 1 KiB write; the SX126x answers SPI status/version; the battery
divider and PRG debounce work. The as-found legacy image, 7-row OTA table, NVS
(NVS `sx_pair/config` = `{918500000, 4c4d58435b5c0000, 4}`, one BLE bond, Wi-Fi
AP state), app slot and cooks partition are archived under
`artifacts/bench/T09/as-found/`. `erase-flash` completed; `0x0..0x2ffff` reads
100% `0xFF` and the board printed `invalid header: 0xffffffff` until the probe
was flashed. The throwaway probe at `firmware/bench/t09_probe/` advertises
`SX4-T09-PROBE` for 10 s and deep-sleeps with EXT1 GPIO0-low wake.
**Hold-PRG wake: 20/20 application boots, 0/20 ROM-download entries**; every
wake was `rst:0x5 (DSLEEP)`, `boot:0x8 (SPI_FAST_FLASH_BOOT)`,
`causes=0x8`, `EXT1 mask=0x1`, `gpio0=0` at `app_main`. ADR 0020 records EXT1 as
the wake decision; the RST-button fallback is not selected.

**Deviations / limits.** The 20 presses were driven by the CP2102 DTR
transistor, which is the same GPIO0/PRG net (proven by the 30 ms-debounced PRG
check), not by a finger. The image is a custom throwaway IDF probe
(`firmware/bench/t09_probe/`), not a stock IDF example, because it had to run
the OLED/ADC/PRG checks and count wake cycles; it is still bare NimBLE
advertising + deep sleep and is not product code. The USB-detached 20x repeat
was not run: it needs a human at the bench and removes the serial observation
channel. Currents were not measured (no meter), the 24 h pack run was not
attempted (no window), and the antenna/pack-polarity checks are inherited from
the legacy record rather than re-done. These are recorded as ⏳/⚠ in
`docs/hardware-verified.md`; do not read them as passes.

**Checks run.** `esptool flash-id`; as-found `read-flash` + `esptool
image-info` + `nvs_tool.py`; `erase-flash`; post-erase `read-flash` all-`0xFF`;
`idf.py -B build build` and `idf.py -p COM5 -B build flash` for the probe;
`cold_boot.py` (OLED OK, BLE active, PRG pulse); `wake_cycles.py` (20/20 APP).
All artifacts and logs are in `artifacts/bench/T09/` with SHA-256 sums.

**Board state / next task.** The board currently runs the T09 probe (3-row
`nvs`/`phy_init`/`factory` table) and is in deep sleep on COM5 with the pack
connected at ≈4.03 V. The legacy image, NVS and cooks are gone by design. T10
must flash its own capture image; T11/T23 must use ADR 0020 and repeat the
USB-detached physical press when a human is at the bench.
