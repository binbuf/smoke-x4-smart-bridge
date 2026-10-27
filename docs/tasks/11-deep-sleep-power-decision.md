# T11 — Deep-sleep and power decision record

## Goal
Write the deep-sleep/power decision into `docs/hardware-verified.md` — whether
hold-PRG wake works, the fallback if it does not, and the measured current and
pack runtime. Firmware power tasks can then proceed without re-litigating the
wake mechanism.

## Context (read first)
- Design: [01 §1.4](../design/01-hardware.md)
- Verification: **B** (bench/board) · Board required: **yes**
- Depends on T09.
- Uses the measurements and wake trials from T09; it does not repeat them.
- Closes open decision Q3 (GPIO0 deep-sleep wake works) from
  [README](README.md#open-decisions-that-block-tasks).

## Scope
Write the decision in `docs/hardware-verified.md`:

- [ ] Answer: does hold-PRG wake work reliably?
- [ ] If not, name the fallback: RST wake, external latch, or drop
      hold-to-on.
- [ ] Record the measured deep-sleep current and expected pack runtime.

## Out of scope
- Re-running the bench trials or current measurements — owned by T09.
- Implementing deep sleep, wake handling, or power features — M1/M4.
- Changing hardware, adding an external latch, or reworking the board — not
  part of the MVP; a fallback choice here is a decision, not a build task.
- Power UI, battery display, or low-power thresholds — M4.
- Wi-Fi/HTTP/OTA power trade-offs — outside MVP; no task owns them.

## Design notes
- The decision record lives in `docs/hardware-verified.md`; do not create a
  parallel document.
- Three fallback options are on the table and must be named explicitly if
  needed: RST wake, external latch, or drop hold-to-on. Pick one and say why.
- Include the measured deep-sleep current and the expected pack runtime derived
  from it.
- Base the record on T09's recorded evidence; do not pick silently or from
  assumption.
- Once written, the firmware power tasks treat this as settled and must not
  re-open the wake mechanism.

## Done when
- [ ] `docs/hardware-verified.md` states whether hold-PRG wake works reliably.
- [ ] If it does not, the chosen fallback is recorded with rationale.
- [ ] The measured deep-sleep current and expected pack runtime are recorded.
- [ ] The firmware power tasks can proceed without re-litigating the wake
      mechanism.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
