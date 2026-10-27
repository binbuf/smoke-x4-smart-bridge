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
- [ ] Bring up Vext, I²C, and the SSD1306: Vext (GPIO36) LOW before the I²C bus is created; 128×64 at address `0x3C`, 400 kHz.
- [ ] Implement the 1 KB page-ordered framebuffer and dirty-driven flush.
- [ ] Implement the four pages:
  - `Probes` (default),
  - `Connection`,
  - `Billows`,
  - `Bridge`.
- [ ] Implement the overlays:
  - pairing code (passkey),
  - power-off countdown,
  - storage failure,
  - resetting,
  - clearing log,
  - off,
  - boot.
- [ ] Add display timeout (default 60 s; configurable 30/60/120/never from the app) with panel `0xAE` and the render task idle while asleep.
- [ ] Use the final labels exactly:
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
- [ ] Render detached as `---`, never `0.0`; invalid-but-present as `ERR`.
- [ ] Render unknown battery as `—`, never 0%.
- [ ] Add framebuffer goldens for every page and overlay, including four probes, detached probe, unpaired link, paired link, passkey, power-off countdown, storage failure, and Billows detected/not detected.
- [ ] Add a small host tool that converts a framebuffer to PNG for human review; the `.fb` bytes remain the gate.
- [ ] Confirm the app's Bridge screen preview and the firmware labels agree.

## Out of scope
- PRG tap/hold gestures, power-off commit, deep sleep, and boot hold confirmation → T23.
- Battery ADC sampling and the SoC curve → T24; this task renders the supplied mV/%/unknown.
- BLE passkey generation, bonding, and `Phones paired` counts → Phase 3 BLE tasks (T27–T38).
- Billows target validation → M5 Billows (T56–T60); the page shows `SET —` until validated.
- App screens, themes, and navigation → Phase 3 app tasks (T27–T38 and later milestones).
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
- [ ] Host goldens match every page and overlay.
- [ ] The visible pages are legible on the real OLED through the case window.
- [ ] The panel sleeps after the configured timeout and wakes without changing the page.
- [ ] The app's Bridge screen preview and the firmware labels agree.
- [ ] Detached renders as `---`, invalid as `ERR`, and unknown battery as `—`.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
