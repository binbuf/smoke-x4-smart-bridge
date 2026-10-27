# T66 — Documentation and handoff

## Goal
A newcomer can follow the README from a blank phone and board to live data without external prose, and the hardware, Billows, UI, and release records match what actually shipped.

## Context (read first)
- Design: [10 §10.5, §10.7](../design/10-test-and-release.md); UI/copy sources in [12](../design/12-copy-and-label-review.md) and [13](../design/13-ui-implementation-contract.md).
- Original verification: **H** (host/docs review) · **board:** no.
- Depends on T63, T64, T65.
- Use the release notes template in [10 §10.7](../design/10-test-and-release.md); the note must match the capability bits.

## Scope
- [ ] Write/refresh root `README.md`: what it is, hardware, build/flash, install, pair, first run, limitations, attribution.
- [ ] Refresh `docs/hardware-verified.md` with dated bench results.
- [ ] Refresh `docs/billows-decision.md` with the observation-only decision and evidence.
- [ ] Update `docs/design/12-copy-and-label-review.md` and `docs/design/13-ui-implementation-contract.md` to mark the remaining production copy/UI gaps closed or explicitly descoped.
- [ ] Write release notes per [10 §10.7](../design/10-test-and-release.md).
- [ ] Write a one-page "new user" path: power, attach antenna, pair, live, history, Cooks.

## Out of scope
- Code changes, new features, or UI redesign — outside this task; no task owns a new feature here.
- Building the release APK (→ T64) or firmware image (→ T65).
- The final acceptance audit (→ T67).
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.
- Billows setpoint control or any control affordance — outside MVP; no task owns it. T68 does not add a control path.
- iOS, web, desktop, cloud sync, and accounts — outside MVP; no task owns them.

## Design notes
- Release notes follow the [10 §10.7](../design/10-test-and-release.md) template and include firmware, app, verified board/phone/Android, 24 h soak result, overnight cook result, and known limitations.
- Known limitations to state: USB firmware update only; no alarms/notifications (use the Smoke X4's alarm); Billows observed only; BLE range and phone-background behavior; recovery if all bonded phones are lost.
- The Billows line is observation-only and says "Set the target on the Smoke X4."; the note must match `caps.billows_control = 0`.
- The README path must stand alone: power, attach antenna, pair, live, history, Cooks, with no external prose.
- Mark copy/UI gaps as closed or explicitly descoped; do not leave an ambiguous "later".
- Record dated bench results, not undated claims.

## Done when
- [ ] A person who has never seen the repo can follow the README from a blank phone/board to live data without external prose.
- [ ] `docs/hardware-verified.md` has dated bench results.
- [ ] `docs/billows-decision.md` records the observation-only decision and evidence.
- [ ] The copy/UI gaps in 12 and 13 are marked closed or explicitly descoped.
- [ ] Release notes and the one-page new-user path are committed.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
