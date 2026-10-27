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
- [ ] Record the power decision in one place so firmware can proceed.
- [ ] Note that measured deep-sleep current and pack runtime are not available
      yet and are owned by T62, not this task.

## Out of scope
- Re-running the bench wake trials — owned by T09.
- Measuring current or running the 24 h pack test — owned by T62. T11 records
  the decision; it does not claim a runtime number.
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
- The wake decision is already supported by T09 and ADR 0020. Do not repeat the
  trials or pick a different mechanism.
- Current and runtime are **not** part of the decision until T62 measures them.
  Do not publish an estimate as a measurement.
- Base the record on T09's recorded evidence; do not pick silently or from
  assumption.
- Once written, the firmware power tasks treat this as settled and must not
  re-open the wake mechanism.

## Done when
- [x] `docs/hardware-verified.md` states whether hold-PRG wake works reliably.
- [x] If it does not, the chosen fallback is recorded with rationale. **No
      fallback selected: EXT1 on GPIO0 works.**
- [x] `docs/hardware-verified.md` names T62 as the owner of current and runtime
      measurements and does not claim a measured value.
- [x] The firmware power tasks can proceed without re-litigating the wake
      mechanism.
- [x] Hand-off below filled in.

## Hand-off

**Landed.** The power decision is written into `docs/hardware-verified.md`
under "Power decision (T11)". Hold-PRG wake works: 20/20 DTR-driven EXT1 boots
plus owner-observed physical battery wakes. No fallback selected; RST wake,
external latch and drop-hold-to-on are all rejected. ADR 0020 remains the
implementation contract (`ESP_EXT1_WAKEUP_ANY_LOW` on GPIO0, RTC-retained state
to distinguish wake from cold boot).

**Deviation.** This task no longer claims a measured deep-sleep current or
runtime. The meter was not available, so those rows stay ⏳ and are explicitly
owned by T62. No estimate is published as a measurement.

**Next task.** T23 implements the EXT1 path and the 07 §7.7 debounce; T62
measures current and the 24 h pack run. If either contradicts the wake result,
supersede ADR 0020 rather than re-opening it ad hoc.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
