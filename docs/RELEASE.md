# Release checklist — Smoke Bridge app

The gate before a release build ships. There is no automated CI gate for the
app yet; run the checks below by hand. The app is at [`app/`](../app/) — see
[`new-app.md`](new-app.md) for its layout and commands.

---

## 1 · Automated gate (host, no device)

| # | Check | Command | Evidence |
|---|---|---|---|
| A1 | Analyzer, format and the full Flutter suite | `make app.test` | green |
| A2 | Pure Dart domain/data suite (drift cache, transports, sync, policy) | `cd app && dart test test/domain test/data` | green |
| A3 | Generated code is fresh | `make app.gen` then `git diff --exit-code` | no diff |
| A4 | Firmware host tests (unchanged by the app) | `make test-host` | 21/21 pass |

## 2 · Release build (desk)

| # | Check | How | Evidence |
|---|---|---|---|
| B1 | Version is set | `app/pubspec.yaml` `version:` | a real `x.y.z+n` |
| B2 | Fonts bundle offline | `flutter build apk --release`, then inspect the APK assets for the two `.ttf` files | present |
| B3 | Release APK is signed | `flutter build apk --release --split-per-abi` with the release keystore configured (`android/key.properties`, not committed) | `apksigner verify` passes |
| B4 | No secrets in the tree | `git status` clean of `*.jks`, `key.properties`, `*.keystore` | none |

> **B3 needs a human with the signing key.** The keystore and `key.properties`
> are intentionally untracked (`.gitignore`); a debug-signed APK is not a
> release.

## 3 · Bench (phone + a bridge required)

| # | Check | How | Evidence |
|---|---|---|---|
| C1 | Factory-fresh install reaches a live reading | install, bond over BLE (read the passkey off the bridge OLED), land on Live with a live temperature | a reading, no external prose needed |
| C2 | Pair the Smoke X4 | hold **SYNC** on the Smoke X4 until the bridge's OLED confirms | stock receiver keeps working |
| C3 | Graph and History over BLE | select a session in History, open its detail, compare with Graph | samples match the bridge |
| C4 | Clock | set the bridge clock from Live, confirm later sessions carry a real date | a dated History row |
| C5 | Reconnect soak | drop and restore the link repeatedly; the chip tells the truth at each step | no stale-as-current, no dead control |

## 4 · Sign-off

| Role | Name | Date | Notes |
|---|---|---|---|
| Automated gate (A1–A4) | | | |
| Release build (B1–B4) | | | |
| Bench (C1–C5) | | | |
| Final approval | | | |

## Deferred / not in v1

- Guided first-run pairing, Smoke X4-pairing controls, and auto clock-setting on
  connect are roadmap items [S1.1–S1.3](../ROADMAP.md), not release blockers.
- There is no golden or invariant suite; the end-to-end BLE harness is
  [S3.5](../ROADMAP.md).
- The signed release APK (B3) and the bench sign-off (C1–C5) need a human with
  the signing key, a phone, and a bridge.