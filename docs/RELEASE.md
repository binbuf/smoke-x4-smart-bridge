# Release checklist — Smoke Bridge app

The gate before a release build ships. The automated half runs in CI; the bench
half needs a phone and, for OTA, a board. Do the automated half first — a red
gate means stop.

The rebuilt app lives at `app/` (the `newui/` design language). `app.old/` is
the archived legacy app and is git-ignored; see [`new-app.md`](new-app.md).

---

## 1 · Automated gate (host, no device)

| # | Check | Command | Evidence |
|---|---|---|---|
| A1 | Analyzer, format and the full Flutter suite | `make app.test` | green |
| A2 | Pure Dart data/domain suite (drift cache, transports, policy) | `cd app && dart test test/domain test/data` | green |
| A3 | The invariant suite (I2–I15) | `cd app && flutter test test/verification` | green |
| A4 | Copy audit, accessibility, reduced motion, empty states, release build | included in A3 | green |
| A5 | Goldens compared, never regenerated in CI | part of A1 | green |
| A6 | Firmware host tests (unchanged by the app) | `make test-host` | green |
| A7 | Generated code is fresh | `make app.gen` then `git diff --exit-code` | no diff |

The invariant suite is `app/test/verification/`: `invariants_test.dart` (one
named test per I2–I15), `copy_audit_test.dart`, `accessibility_test.dart`,
`reduced_motion_test.dart`, `empty_states_test.dart`, `field_report_test.dart`
and `release_build_test.dart`.

## 2 · Release build (desk)

| # | Check | How | Evidence |
|---|---|---|---|
| B1 | Version matches the changelog | `app/pubspec.yaml` `version:` vs `app/CHANGELOG.md` | same `x.y.z` |
| B2 | Changelog entry exists for the release | `app/CHANGELOG.md` | `## x.y.z` present |
| B3 | Fonts bundle offline | `flutter build apk --release`, then inspect the APK assets for the three `.ttf` files | present |
| B4 | No dev panel in release | `release_build_test.dart` proves `kReleaseMode` gates; spot-check the release build has no panel button | absent |
| B5 | Release APK is signed | `flutter build apk --release --split-per-abi` with the release keystore configured (`android/key.properties`, not committed) | `apksigner verify` passes |
| B6 | No secrets in the tree | `git status` clean of `*.jks`, `key.properties`, `*.keystore` | none |

> **B5 needs a human with the signing key.** The keystore and `key.properties`
> are intentionally untracked (`.gitignore`); a debug-signed APK is not a
> release.

## 3 · Bench (phone required)

| # | Check | How | Evidence |
|---|---|---|---|
| C1 | Install and first-run onboarding | factory-fresh install; pair a real bridge over BLE; skip Wi-Fi | wizard completes |
| C2 | A live cook with no phone | start a cook, kill the app; the bridge keeps recording and alarming | recording continues |
| C3 | Notifications wake the phone | run the test alarm with the screen locked and face down | sound + heads-up + screen lights (see [`FIELD-REPORT.md`](FIELD-REPORT.md)) |
| C4 | Reconnect/failover soak | kill and restore Wi-Fi and BLE repeatedly against `tools/sim` or the board; the UI tells the truth at each step | no stale-as-current, no dead control |
| C5 | 15-hour chart scroll | scroll the longest cached cook with LTTB active; frame budget held on a mid device | no dropped frames / jank |
| C6 | Field report dry-run | run Diagnostics → Field report; confirm nothing sensitive leaves without review | reviewed |
| C7 | OTA on hardware | install a release `.bin` over Wi-Fi behind the rollback gate, on a board that is **not** the only USB-flashable one | update + rollback gate verified |

## 4 · Sign-off

| Role | Name | Date | Notes |
|---|---|---|---|
| Automated gate (A1–A7) | | | |
| Release build (B1–B6) | | | |
| Bench (C1–C7) | | | |
| Final approval | | | |

## Deferred / not in v1

- Adaptive layout beyond width classes (N16.9) — bottom bar → rail; fold
  postures are deferred until scoped.
- The full destination × theme × density golden matrix (N16.5) — the design
  gallery is the golden that pins the system in all three themes × both
  densities; per-destination goldens remain a follow-up.
- Performance (N16.6) and the soak (N16.8) are bench checks, not host tests.
