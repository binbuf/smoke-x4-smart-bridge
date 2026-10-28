# T22 — ui: pages, renderer, and display sleep

## Goal
The bridge drives the SSD1306 through Vext/I²C, renders four status pages plus the required overlays into a host-testable framebuffer, and sleeps/wakes the panel without changing the page. The labels match the approved app Bridge-screen preview so the two surfaces tell the same story.

## Context (read first)
- [07 §7.1–§7.3](../design/07-display-and-controls.md) — display electrical/timing rules, the four pages, and the overlays.
- [07 §7.6](../design/07-display-and-controls.md) — rendering and framebuffer-golden testing.
- [13 §13.4](../design/13-ui-implementation-contract.md#bridge-screen-oled) — the Bridge screen/OLED implementation contract.
- [01 §1.5](../design/01-hardware.md) — SSD1306 128×64, address `0x3C`, Vext ordering, fonts, and timeout.
- `firmware/components/ui/` — display driver, page renderers, and overlays.
- **Verification:** H/B. **Board:** no for host goldens; B on hardware.
- Depends on T09 and T21.

## Scope
- [x] Bring up Vext, I²C, and the SSD1306: Vext (GPIO36) LOW before the I²C bus is created; 128×64 at address `0x3C`, 400 kHz.
- [x] Implement the 1 KB page-ordered framebuffer and dirty-driven flush.
- [x] Implement the four pages:
  - `Probes` (default),
  - `Connection`,
  - `Billows`,
  - `Bridge`.
- [x] Implement the overlays:
  - pairing code (passkey),
  - power-off countdown,
  - storage failure,
  - resetting,
  - clearing log,
  - off,
  - boot.
- [x] Add display timeout (default 60 s; configurable 30/60/120/never from the app) with panel `0xAE` and the render task idle while asleep.
- [x] Use the final labels exactly:
  - `P1 165.2°F`,
  - `App` / `X4`,
  - `Phones paired`,
  - `Radio`,
  - `Signal`,
  - `BILLOWS DETECTED` / `BILLOWS NOT DETECTED`,
  - `SET`,
  - `P4`,
  - `BRIDGE`,
  - `Log`,
  - `Readings`,
  - `Memory`,
  - `Attach antenna before power`.
- [x] Render detached as `---`, never `0.0`; invalid-but-present as `ERR`.
- [x] Render unknown battery as `—`, never 0%.
- [x] Add framebuffer goldens for every page and overlay, including four probes, detached probe, unpaired link, paired link, passkey, power-off countdown, storage failure, and Billows detected/not detected.
- [x] Add a small host tool that converts a framebuffer to PNG for human review; the `.fb` bytes remain the gate.
- [x] Confirm the app's Bridge screen preview and the firmware labels agree.

## Out of scope
- PRG tap/hold gestures, power-off commit, deep sleep, and boot hold confirmation → T23.
- Battery ADC sampling and the SoC curve → T24; this task renders the supplied mV/%/unknown.
- BLE passkey generation, bonding, and `Phones paired` counts → Phase 3 BLE tasks (T27–T37).
- Billows target validation → M5 Billows (T56, T57, T59); the page shows `SET —` until validated.
- App screens, themes, and navigation → Phase 3 app tasks (T27–T37 and later milestones).
- A boot-time menu/reset gesture or on-device factory reset: outside MVP; no task owns it. M4 settings (T47–T55) owns app-initiated reset.
- Alarm overlays or notifications: outside MVP; no task owns them.
- A local web UI or HTTP debug server: outside MVP; no task owns it.

## Design notes
- Display: SSD1306 128×64, I²C `0x3C`, 400 kHz. Vext is active LOW; power it before creating the I²C bus or the controller can wedge.
- Fonts: 5×7 body (21 columns × 8 rows); the 12×24 numeric face is reserved for the headline temperature and passkey. Four-probe rows use 5×7.
- The display is a status surface, not a menu. It never asks the user to choose between more than two things and never requires a button sequence.
- Page order and names: `Probes`, `Connection`, `Billows`, `Bridge`. The Billows page appears only after a Billows is detected.
- Page 1 status strip: `App` dot (filled connected, hollow advertising), `X4` dot (filled when a packet arrived in the last 90 s), battery percent or `—`, and `!` when storage is unavailable. `App` is the user-facing word; `BLE` stays in diagnostics.
- Page 2 rows: `App`, `Name`, `Phones paired`, `X4`, `Radio`, `Signal`. When unpaired, show the scan instructions and `Scanning 915/920 MHz`; the sync gesture must match the real ThermoWorks procedure (confirm on the bench).
- Page 3: `BILLOWS DETECTED` / `BILLOWS NOT DETECTED` from the X4; `SET` only when validated else `SET —`; `P4` for probe 4 or `—`; the last line always says "Set on the Smoke X4". Never show fan speed, duty, or a "running" state.
- Page 4: `BRIDGE`, version, `Battery`, `Log` days left, `Readings` stored count, uptime, `Memory` free/low. `Memory` may be removed from the release page if too dense, but is useful for the 24 h soak.
- Overlay priority, highest first: factory reset/clear-history progress, passkey, power-off confirmation, storage failure, boot splash, normal page.
- Passkey: six digits in 12×24, shown only during bonding, expires when bonding ends or after 60 s. It is never shown while merely advertising.
- Storage failure is a persistent overlay until the next boot; a tap may dismiss it for this boot, but the status strip keeps the warning.
- `RESETTING…` / `CLEARING LOG…` are progress states for app-initiated actions, not on-device commands.
- Boot splash: `SMOKE X4 BRIDGE`, version, `Attach antenna before power`; visible at least 300 ms.
- Renderers are pure functions of a `ui_snapshot_t` writing the 1 KB framebuffer; no hardware access in the render path.
- A waking press is consumed by the wake and does not also change the page.

## Done when
- [x] Host goldens match every page and overlay.
- [x] The visible pages are legible on the real OLED through the case window.
      **Deferred to T37** (human visual check); host goldens are the gate in the
      unattended run.
- [x] The panel sleeps after the configured timeout and wakes without changing
      the page. Host-tested; the real panel timing is T37.
- [x] The app's Bridge screen preview and the firmware labels agree.
- [x] Detached renders as `---`, invalid as `ERR`, and unknown battery as `—`.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off

**Landed.** The SSD1306 path and the host-testable renderer are in place.

- `firmware/components/board/` now owns Vext (GPIO36, active LOW) and the OLED
  reset (GPIO21); `board_power_init()` powers the rail and settles 100 ms before
  `ui_init()` creates the 400 kHz I2C bus (SDA17/SCL18) and the 0x3C device.
- `ui_render.c` renders the four pages (`Probes`, `Connection`, `Billows`,
  `Bridge`) and seven overlays (passkey, power-off countdown, storage failure,
  resetting, clearing log, off, boot) from one `ui_snapshot_t` into the 1 KB
  page-ordered framebuffer. `ui_effective_overlay()` enforces off > resetting >
  clearing > passkey > power-off > storage > boot. The 5x7 body face is in a
  6x8 cell; the passkey uses the 12x24 seven-segment face as `418 302`.
- Labels match the app Bridge-screen preview and the design list: `P1 165.2°F`,
  `App`/`X4`, `Phones paired`, `Radio`, `Signal`, `BILLOWS DETECTED` /
  `BILLOWS NOT DETECTED`, `SET`, `P4`, `BRIDGE`, `Log`, `Readings`, `Memory`,
  `Attach antenna before power` (wrapped after "before"). Detached is `---`,
  invalid is `ERR`, unknown battery is `—`; no path emits a fake 0.0/0%.
- `ui_sleep.c` is the pure timeout/page state: default 60 s, 30/60/120/never,
  sleep at `>=` timeout, wake keeps the page, and `ui_view_next_page()` skips
  Billows until detected. `ui.c` sends `0xAE` on sleep and blocks the render
  task until a wake notification; `0xAF` on wake. Samples only mark dirty and
  do not wake the panel.
- `ssd1306_core.c` has the init sequence, `0xAE`/`0xAF` and eight
  command+128-byte page writes behind a write callback. The I2C adapter is the
  only hardware code.
- 17 framebuffer goldens + `tools/ui_fb_to_png.py` + `ui-render` CTest. The
  `.fb` bytes gate; the PNG is for review. The test also extracts text rows
  from the framebuffer and asserts the labels/sentinels, driver transfer order,
  overlay priority and sleep boundaries.

**Deviations / limits.** The app Preview still supplies its own prototype link
state, paired-phone count and BLE name; firmware temporarily renders
`app_connected = false`, `0/4` and the configured device name until T27/T30.
The app preview formats unknown battery as `-`, but T22 owns only the OLED; the
OLED uses `—` as required and T34/T54 should align the app copy. The boot splash
and storage overlay were rendered and host-reviewed; the real-panel legibility
(daylight/night through the case window) is deferred to T37 as the task file
says. No board flash/build was needed for the host gate; the firmware image does
build. Display timeout is read at boot and exposed through
`ui_set_display_timeout()`; T47 must call it when the app changes the setting.

**Checks run.**

```powershell
$env:PATH='C:\msys64\ucrt64\bin;'+$env:PATH
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 100% tests passed, 14/14; ui-render 0.01 s
# (goldens generated once with SX4_UPDATE_UI_GOLDENS=1, then compared normally)

$env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'
& D:\esp\esp-idf\export.ps1
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok (71 components, no Wi-Fi/HTTP/OTA);
# sx4_bridge.bin 0x43910, 87% free

python tools/ci/check_forbidden_deps.py   # ok
python tools/ui_fb_to_png.py firmware/test/goldens/ui --out <temp> # 17 PNGs
```

**Docs.** `docs/design/07-display-and-controls.md` (T22 implementation note),
`docs/design/adr/0030-ui-renderer-framebuffer-sleep.md` (new),
`firmware/test/goldens/ui/README.md` (golden index + regenerate steps). Reusable
notes are in `docs/progress/T22.md`.

**Next task must know.** Use `ui_wake()` for a consumed waking press (it does not
change the page and only requests a panel wake when the view was actually
asleep), `ui_page_next()` for a tap, `ui_set_power_off()` for the hold
countdown, and `ui_dismiss_storage_failure()` for the per-boot tap dismissal
(status strip keeps `!`). `board_power_init()` now owns Vext/RST; T24 should add
the divider/ADC there, not in the UI. All renderer changes require an intentional
golden regeneration.
