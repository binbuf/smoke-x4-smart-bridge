# T10 — Baseline capture

## Goal
Capture real Smoke X4 traffic on the bench — state frames for all four probes,
a detach/reattach, a °F/°C flip, an alarm edge, and the sync beacon/ACK — and
commit it as fixtures so the new parser can be replayed against reality.

## Context (read first)
- Design: [02 §2.9](../design/02-smoke-x-protocol.md)
- Verification: **B** (bench/board) · Board required: **yes**
- Depends on T09.
- This is a bench sitting, not a staged cook. Room-temperature probes are
  valid; the X4 broadcasts the same state whether it is cooking or sitting on
  the bench. No cook is required.
- **What already exists.** `protocol/fixtures/lora/` already holds real X4
  captures copied from the legacy tree (`x4-events-10min.loralog` — one sync
  beacon, one ACK and 37 state frames over ~10 min; `x4-passive-session.loralog`;
  `first-x4-contact.loralog`). They are 2026-07-21 captures from the *previous*
  build's radio. This task exists to replace/augment them with captures from the
  current board and to settle what those files cannot: a full 30+ minute run,
  a detach/reattach, a °F/°C flip, and a confirmed sync gesture.
- The T09 probe is still flashed and the legacy NVS image is gone (T09 wiped
  it), so there is no legacy firmware on the board to capture with.

## Scope
With a real Smoke X4, on the bench (not during a live cook):

- [ ] Decide the capture path **before touching the radio** and write it in the
      Hand-off. The candidates, in order of preference for this task:
      1. a throwaway RX-only IDF probe under `firmware/bench/` (the T09 probe
         already proves the toolchain, SPI and pins), or
      2. an SDR/LoRa sniffer capture decoded offline, or
      3. the `x4-events-10min`-style post-processed log from the previous build,
         used **only** as a cross-check, never as the new baseline.
      Whatever is chosen must run on the current board: the legacy firmware is
      no longer on it. The capture build may transmit **only** the pairing ACK
      (`<device_id>,SUCCESS,`) so the X4 leaves SYNC and returns to normal state
      traffic; it has no other TX path.
- [ ] Establish the pairing prerequisite. The X4 has to be put into SYNC mode
      and its SYNC control held until it acknowledges, because the bridge needs
      the **operating channel** from the sync beacon before it can hear state
      traffic. Confirm and record the exact gesture and the beep/LED feedback
      actually observed on this unit, including whether the X4's own receiver
      drops or recovers afterwards.
- [ ] Record the operating frequency decoded from the sync beacon.
- [ ] Record 30+ minutes of state traffic with all four probes.
- [ ] Include a detach/reattach in the capture.
- [ ] Include a °F/°C flip.
- [ ] Include an alarm edge if practical.
- [ ] Capture the sync beacon and the ACK.
- [ ] Commit the logs and a short report under `protocol/fixtures/lora/`.
- [ ] If a Billows is attached during the sitting, capture the
      `billows_attached` flag turning on/off. Do **not** sweep the target:
      the 225/250/275 °F relation belongs to T56.

## Out of scope
- Replaying the captures in a host test — the parser/harness side lands in
  T03/M1; this task supplies the fixtures.
- A staged cook or field cook — M6 / T63 field evidence.
- Billows target-relation evidence (the 225/250/275 °F sweep) — T56. This task
  may capture only the attached/not-attached flag.
- Parser feature work beyond what the captures verify — M1.
- Changing the protocol contract — owned by T02.
- Any LoRa transmission from the capture build other than the single pairing
  ACK — no task; the bridge has no other TX path, and this task does not re-pair
  a product build.

## Design notes
- Bench-only: do not capture during a live cook.
- Room-temperature probes are acceptable; do not wait for a cook.
- The state packets only appear on the X4's **operating channel**, which is
  learned from the sync beacon (02 §2.3) and is normally not 915 MHz. A powered
  X4 alone is not enough: without the sync gesture the capture sees nothing.
- The existing legacy captures cover sync+ACK and a passive session but not a
  30-minute four-probe run with a detach and a unit flip. Say explicitly in the
  report which rows the new captures add and which the legacy files still cover.
- The capture must include all four probes, a detach/reattach, a °F/°C flip,
  and (if practical) an alarm edge.
- The sync beacon and the ACK are required separate captures.
- Logs and a short report are committed together under
  `protocol/fixtures/lora/`, with provenance and a row in that directory's
  `README.md` table.
- Fixtures from T03 are the starting set; this task adds real, longer captures.
- Ongoing field evidence is gathered by T63; Billows-specific evidence is
  gathered in M5. This task neither replaces nor duplicates those.

## Done when
- [x] The capture path is named and is reproducible from this repo.
- [x] The SYNC gesture is recorded with what the X4 actually did. **The stock
      receiver completed its normal sync; its ACK is in the capture. The exact
      button press was not separately logged.**
- [ ] 30+ minutes of four-probe state traffic is captured. **Deviation: 22.4
      minutes / 41 state frames, stopped by owner choice after every required
      event type was present.**
- [x] The detach/reattach and °F/°C flip are in the capture. The alarm edge was
      not practical and is explicitly optional.
- [x] The sync beacon and the ACKs are captured (our tx ACK and the stock
      receiver's rx ACK).
- [x] Billows was not attached, so no `billows_attached` transition applies;
      the target sweep remains T56.
- [x] The fixture matches the existing `loralog v1` corpus shape; replay itself
      is T14's job.
- [x] The logs and short report are committed under `protocol/fixtures/lora/`
      with a row in its `README.md` provenance table.
- [x] Hand-off below filled in.

## Hand-off

**Landed.** A throwaway RX capture probe at `firmware/bench/t10_probe/` (vendored
`ra01s`, no product build dependency) captured a real X4 session on the current
board. The fixture is `protocol/fixtures/lora/x4-t10-25min.loralog` with
`x4-t10-25min.report.md` and a provenance row in that directory's `README.md`.
It contains the 915 MHz sync beacon, our ACK and the stock receiver's ACK on
918.5 MHz, 41 four-probe state frames, probe-2 detach → reattach, and
°F → °C → °F.

**Deviation.** State traffic is 22.4 minutes, not 30+. The owner stopped after
every required event type was captured; the remaining time would only add
steady-state frames. No alarm edge was captured (optional). The exact sync
button gesture was not logged; the stock receiver's normal sync completed and
its ACK is in the fixture.

**Gotchas for later tasks.**
- Our first ACK went out on 915 MHz and did nothing. The ACK must be sent **after**
  retuning to the operating frequency; the firmware confirms this rule.
- The 915 MHz sync beacon uses device id `LMXC[\`; the trailing backslash is part
  of the id and must be preserved.
- State frames are ~77 bytes, arrive every ~30 s, and the stock receiver also
  emits its own ACK on the operating channel during sync.
- The probe now sits in the T10 image, not the T09 probe. The next flash can
  replace it.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
