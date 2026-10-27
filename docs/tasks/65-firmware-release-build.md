# T65 — Firmware release build

## Goal
A versioned firmware image, merged binary, and documented USB flash command are committed. A clean board flashes them, reaches advertising, and passes factory reset, deep sleep, and the TX invariant on the release image.

## Context (read first)
- Design: [10 §10.5](../design/10-test-and-release.md); hardware/partition details in [01 §1.8](../design/01-hardware.md).
- Original verification: **H/B** (host/CI + bench) · **board:** yes.
- Depends on T61, T62.
- The 24 h soak report from T61 and the power/sleep evidence from T62 must already be committed before this build is called release.

## Scope
- [ ] Set the firmware version.
- [ ] Run the host suite.
- [ ] Run `idf.py build`.
- [ ] Produce a merged image.
- [ ] Document the USB flash command.
- [ ] Confirm factory reset on the release image.
- [ ] Confirm deep sleep on the release image.
- [ ] Confirm the TX invariant on the release image: sync ACK only; no Billows TX path, `caps.billows_control = 0`.
- [ ] Flash a clean board and confirm it reaches advertising.

## Out of scope
- The app release build (→ T64).
- Running the 24-hour soak (→ T61) or measuring power/runtime (→ T62).
- Documentation, README, and release notes (→ T66).
- The final acceptance audit (→ T67).
- OTA or a browser installer — outside MVP; no task owns it.
- Any Billows control path or LoRa TX other than the pairing ACK — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- Version string is set and shown in `info`/OLED.
- `idf.py build` must be clean and the host suite green before the image is called release.
- The partition table matches [01 §1.8](../design/01-hardware.md); there are no OTA slots.
- Factory reset clears config, log, and bonds.
- Only TX path is the sync ACK. `caps.billows_control = 0`, and the invariant test runs against the actual build, not only the host configuration.
- The merged image and the exact USB flash command are committed together; a clean board flash is the final check.

## Done when
- [ ] The image and flash instructions are committed.
- [ ] A clean board flashes and reaches advertising.
- [ ] Factory reset, deep sleep, and the TX invariant pass on the release image.
- [ ] Host suite and `idf.py build` are green.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
