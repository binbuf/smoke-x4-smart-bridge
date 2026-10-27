# T64 — App release build

## Goal
A release APK with the final version, signing, icon, and manifest installs fresh and upgrades an existing install, passes analyze/test/copy lint/screenshots, and exposes no lab, simulation, fixture, or prototype-only surface.

## Context (read first)
- Design: [10 §10.5](../design/10-test-and-release.md), [13 §13.7, §13.10](../design/13-ui-implementation-contract.md).
- Original verification: **H/P** (host/CI + phone) · **board:** no / phone.
- Depends on T53, T54, T61.
- The UI contract is [13](../design/13-ui-implementation-contract.md); the release checklist and acceptance rows are in [10 §10.5](../design/10-test-and-release.md).

## Scope
- [ ] Set the version, icon, package id, release signing (or a documented debug-only bench build), and Android manifest.
- [ ] Remove debug-only UI.
- [ ] Gate the Experimental lab on `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`.
- [ ] Verify the About long-press cannot open the lab in release.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`.
- [ ] Run the copy lint.
- [ ] Run the screenshot generator.
- [ ] Walk the UI parity/a11y checklist in 13 §13.10.
- [ ] Install a fresh APK.
- [ ] Upgrade an existing install.

## Out of scope
- The firmware release build and merged image (→ T65).
- Documentation, README, and release notes (→ T66).
- The final row-by-row acceptance audit (→ T67).
- A UI redesign or new destination — the contract is [13](../design/13-ui-implementation-contract.md).
- Shipping the Experimental lab, simulation controls, fixture values, or prototype-only copy — outside MVP; no task owns it.
- Billows setpoint control or any control affordance — outside MVP; no task owns it. T68 does not add a control path.
- Wi-Fi/HTTP/OTA, notifications, foreground service, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- Release signing is required, or the debug-only bench build is documented explicitly; do not leave an undocumented debug artifact.
- The lab gate is `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`; verify in the release build that the About long-press cannot open it.
- Manifest permissions must be minimal: no unused network, notification, or foreground-service permissions.
- Version and firmware version must be visible in About.
- Strings stay centralized; locale time/date/number formatting applies; banned copy terms stay out.
- The V0/V3 flows must still work on the release APK, including a fresh install and an upgrade over existing data.

## Done when
- [ ] A release APK installs and completes the V0/V3 flows.
- [ ] No lab, simulation control, fixture value, or prototype-only copy is reachable.
- [ ] The manifest contains no unused network/notification/foreground-service permissions.
- [ ] UI parity, 320 dp, dark/light, and accessibility checks pass.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
