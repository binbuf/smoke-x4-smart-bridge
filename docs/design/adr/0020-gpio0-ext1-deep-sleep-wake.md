# 0020 — GPIO0/PRG is the deep-sleep wake source

## Status

accepted (bench evidence 2026-10-26; USB-detached physical repeat still owed)

## Context

The product has no power switch. "Off" is deep sleep, and the only user control
is the PRG button on GPIO0 — which is also the ESP32-S3 ROM download strap. The
legacy build left this as an unproven risk: a wake press could sample the strap
and enter the ROM downloader instead of booting the application.

T09 flashed a disposable IDF probe (bare NimBLE advertising + 10 s awake +
deep sleep), then held the GPIO0 net low for 2 s, released it, and repeated 20
times. All 20 wakes were `rst:0x5 (DSLEEP)` / `boot:0x8
(SPI_FAST_FLASH_BOOT)`; each app logged `causes=0x8` (EXT1), `mask=0x1`, and
`gpio0=0` at `app_main`. No ROM-download banner appeared.

The press was driven by the CP2102 DTR transistor rather than a finger; DTR is
on the same GPIO0 net (the probe's 30 ms-debounced PRG check saw the exact pulse
and no bounce). A physical press with USB detached is still owed.

## Decision

Use GPIO0 (PRG) active-low as the deep-sleep wake source, configured as an
**EXT1** wake (`esp_sleep_enable_ext1_wakeup_io(BIT(0),
ESP_EXT1_WAKEUP_ANY_LOW)`), not the light-sleep-only GPIO wake API. Keep the
RST-button fallback and external latch rejected: the ROM download strap did not
fire on a DSLEEP wake, so there is no evidence for either.

## Consequences

- T23/T11 may implement hold-PRG wake without an additional latch or a
  "hold RST" user instruction.
- Firmware must use the EXT1 path and must still debounce GPIO0 for the
  post-boot hold/release semantics in 07 §7.7; the wake itself is a reset, so
  RTC-retained state is the way to distinguish a wake from a cold boot.
- Still required before release (not a blocker for T11's decision): repeat the
  20 cycles with the physical button on battery, and measure sleep current.
  Record those in `hardware-verified.md`; if they contradict this evidence,
  supersede this ADR rather than silently changing the mechanism.
- The probe is a throwaway under `firmware/bench/t09_probe/`; it is not product
  code and must not be linked into `firmware/`.
