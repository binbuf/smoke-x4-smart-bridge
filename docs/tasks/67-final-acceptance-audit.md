# T67 — Final acceptance audit

## Goal
Every row of the acceptance matrix and the UI/UX definition of done is marked pass, fail, or explicitly descoped with linked evidence. The audit proves the release notes match the capability bits and the observation-only Billows decision is accepted, not merely worded differently.

## Context (read first)
- Design: [10 §10.6](../design/10-test-and-release.md), [13 §13.10](../design/13-ui-implementation-contract.md#1310-definition-of-done).
- Original verification: **H/B/P/C** · **board:** yes.
- Depends on T63, T64, T65, T66.
- This is the last gate before release; a missing `docs/billows-decision.md` acceptance blocks release rather than passing with different wording.

## Scope
- [ ] Walk the acceptance matrix row by row.
- [ ] Walk the UI/UX definition of done row by row.
- [ ] Walk every OLED page and overlay through the case window: Probes,
      Connection, Billows (when detected), Bridge, pairing code, power-off,
      clearing/resetting, sleep/wake, and the blinking `BT` discovery
      indicator. Record legibility and link photos. This absorbs the T37 OLED
      page-walk residual.
- [ ] Mark pass/fail by observation for each row.
- [ ] Link the evidence for each row.
- [ ] If a row fails, create a named follow-up or explicitly descope it with the owner.
- [ ] Confirm release notes match the capability bits (`billows_control`, `history`, `battery`, `power_off`, `factory_reset`).
- [ ] Confirm `billows_control` is 0 and the Billows copy says "Set the target on the Smoke X4."
- [ ] Confirm `docs/billows-decision.md` records the observation-only decision and owner acceptance.
- [ ] Confirm UI parity, copy lint, dark/light, 320 dp, and accessibility evidence is committed.
- [ ] Confirm no prototype-only surface is reachable.

## Out of scope
- Fixing failed rows — each becomes a named follow-up task; this audit does not silently repair evidence.
- New features or a UI redesign — outside MVP; no task owns it.
- Billows setpoint control or any control affordance — outside MVP; no task owns it. T68 does not add a control path.
- Rebuilding the release artifacts (→ T64, T65).
- Editing screenshots or test results to make a row pass — outside this task; a fail stays a fail.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- The acceptance matrix is [10 §10.6](../design/10-test-and-release.md); the UI/UX definition of done is [13 §13.10](../design/13-ui-implementation-contract.md#1310-definition-of-done).
- Every row is pass, fail, or explicitly descoped; nothing is blank and no row is skipped.
- Evidence is linked, not asserted: screenshots, test output, traces, and dated bench records.
- The release note must match `caps`: `billows_control`, `history`, `battery`, `power_off`, `factory_reset`.
- `billows_control` is 0; the Billows copy says "Set the target on the Smoke X4." Owner acceptance in `docs/billows-decision.md` is a release blocker.
- UI parity, copy lint, dark/light, 320 dp, and accessibility evidence must be committed, and no prototype-only surface may be reachable.
- A fail gets a named follow-up or an explicit descope with the owner; it never gets a lowered bar.

## Done when
- [ ] Every row is pass, fail, or explicitly descoped; nothing is blank.
- [ ] The UI/UX contract has evidence for every screen and lifecycle state.
- [ ] Release notes match the capability bits and the observation-only Billows copy.
- [ ] `docs/billows-decision.md` records observation-only with owner acceptance.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
