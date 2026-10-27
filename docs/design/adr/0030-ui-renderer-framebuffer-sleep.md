# ADR 0030 - Pure page renderer, page-ordered framebuffer and display sleep

**Status:** accepted

## Context

The OLED is a status surface with four pages and seven overlays, and it must be
testable without a panel. The firmware also has to prove detached/invalid/unknown
values never render as real zeros, sleep the panel without losing the page, and
keep the app's Bridge-screen preview and the OLED labels aligned. Hardware and
task wiring must stay out of the render path so host tests can gate every visual
state.

## Decision

- `ui_render.c` is a pure C11 function of `ui_snapshot_t` plus page number. It
  owns no hardware, clock, NVS or allocation. It writes a 1 KB page-ordered
  framebuffer (`ui_framebuffer_t.page[8][128]`), matching SSD1306 GDDRAM.
- Unknown values have explicit sentinels in the snapshot: detached probe
  (`SX4_TEMP_DETACHED`), invalid-but-present (`SX4_TEMP_INVALID`) and unknown
  battery (`UI_BATTERY_UNKNOWN`). They render `---`, `ERR` and `—`; the
  renderer never substitutes `0.0` or `0%`.
- Overlay precedence lives in the renderer: off > resetting > clearing log >
  passkey > power-off > storage failure > boot > page. Later tasks may set bits
  in any order; the renderer selects the highest active one.
- Display sleep is a separate pure state machine (`ui_sleep.c`). It takes an
  injected monotonic millisecond clock, owns the page and timeout, and
  `wake` changes only the sleep state. The firmware task calls `0xAE` on sleep
  and `0xAF` on wake; the page survives and the task blocks while asleep.
- `ssd1306_core.c` owns the init sequence, `0xAE`/`0xAF` and the eight
  command+128-byte page transfers behind a write callback. The ESP adapter is
  the only I2C code; Vext/reset pin ownership stays in `board`.
- The `.fb` bytes are the golden gate. `tools/ui_fb_to_png.py` converts them to
  PNG for human review only. Labels are asserted from the framebuffer by the
  host test's row extractor, not by a parallel string table.

## Consequences

- T23 can drive page changes, PWR gestures and wake without touching the
  renderer; a waking press calls `ui_wake()` and is consumed.
- T24 fills battery mV/% or the unknown sentinel; T27 fills link state and the
  paired-phone count; T30 calls `ui_set_passkey()`; T47 maps the app timeout to
  `ui_set_display_timeout()`.
- T37 remains the human legibility gate on the real panel through the case
  window. Host goldens cannot prove viewing angle or daylight contrast.
- Changing a label or layout requires an intentional `.fb` golden update and a
  matching app-preview review.
