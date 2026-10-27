# T63 — Field cook

## Goal
One supervised cook and one overnight cook prove the bridge records continuously, the phone reconnects and syncs the whole period, and History reports the cook and its real gaps with the stock receiver unaffected.

## Context (read first)
- Design: [10 §10.3 B5](../design/10-test-and-release.md); acceptance context in [10 §10.6](../design/10-test-and-release.md).
- Original verification: **C** (real cook) · **board:** yes.
- Depends on T46, T55.
- This repeats the field-data loop T38 established: a field cook that changes an assumption changes a task. Update the open-decisions table and roadmap the same way T38 does.

## Scope
- [ ] Run one supervised cook with the phone present.
- [ ] Run one overnight cook with the phone away for ≥ 6 h.
- [ ] Confirm the stock receiver works throughout.
- [ ] Confirm the bridge records continuously.
- [ ] Confirm the phone reconnects and syncs the whole period.
- [ ] Confirm History shows the cook and any real gaps.
- [ ] Confirm no reboot or panic.
- [ ] Confirm delete/retention is not accidentally triggered.
- [ ] Commit a short field report and screenshots.
- [ ] Create a named follow-up for any defect.
- [ ] Update the open-decisions table and roadmap the same way T38 does.

## Out of scope
- The 24-hour soak and its memory criteria (→ T61).
- Power, deep sleep, and runtime measurements (→ T62).
- Re-testing Billows observation beyond normal use (→ T59).
- Billows setpoint control, mode changes, or any Billows TX path — outside MVP; no task owns it. T68 does not add a control path.
- User-created cook sessions, names, marks, phases, presets, cook clock, ETA, stall/lid — outside MVP; no task owns it. Detected Cooks remain read-only archive navigation.
- Alarms, buzzers, phone notifications, foreground service, and quiet hours — outside MVP; no task owns it.
- CSV/JSON export, share sheets, cloud sync, and accounts — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA, web UI, multi-bridge, iOS/web/desktop — outside MVP; no task owns them.

## Design notes
- The overnight cook is the long test: phone away for at least 6 h, then reconnect and sync the whole period.
- History must show the cook and any real gaps; do not paper over a gap that has a real cause.
- The stock receiver must keep updating throughout; a regression there fails the cook even if the bridge records correctly.
- Retention/delete must not fire on its own during either cook.
- A field cook that changes an assumption changes a task: update the decisions table and roadmap rather than leaving the plan stale.

## Done when
- [ ] A short field report and screenshots are committed.
- [ ] Any defect has a named follow-up.
- [ ] The open-decisions table and roadmap are updated the same way T38 does.
- [ ] The supervised and overnight cooks both meet the bullets above.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
