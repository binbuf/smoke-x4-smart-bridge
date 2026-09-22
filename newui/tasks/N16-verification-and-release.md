# N16 — Verification & release

**Goal:** the gate before the new app ships. Accessibility, copy discipline,
goldens, performance, and a release checklist. No new features here.

**Design:** `components_research_notes.md` §1, §9.5, §11.6, §14.4 ·
`newui/NOTES.md` §9 · `newui/app.js` copy strings.

---

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N16.1 | Copy audit: every user-facing string goes through the copy discipline (honest, no raw errors, "expected" says expected, "absent" never "0") | all | H | research notes I15, §14.4 |
| N16.2 | Invariant test suite: one named test per I1–I15 relevant to the app (I2–I15 here; I1 is firmware) | N1, N15 | H | research notes §1 |
| N16.3 | Accessibility: semantic labels on temps/alarms/controls, ticker text, contrast in all 3 themes, 200% text scale without clipping a temperature | N3.10 | W | I14, §9.2 |
| N16.4 | Reduced-motion verification: all non-pulse motion off; the staleness pulse remains | N3.8 | W | §9.4 |
| N16.5 | Golden set: every destination × {dark, light, daylight} × {compact, comfortable}, plus key overlays | N5–N14 | W | `styles.css` |
| N16.6 | Performance: 15-hour chart scroll, LTTB active, frame budget held on a mid device | N7.2 | S | §6.2 |
| N16.7 | Empty/problem/capability states pass a walkthrough (I5, I6, I13) | N5–N13 | W | research notes §10 |
| N16.8 | Reconnect/failover soak against `tools/sim`: kill/restore Wi-Fi and BLE repeatedly; the UI tells the truth at each step | N15.6 | S | I4, I9 |
| N16.9 | Adaptive layout pass (optional for v1): width classes, bottom bar → rail; fold postures deferred unless scoped | N3.1 | W | §9.5 |
| N16.10 | Release checklist: version, changelog, signed APK, fonts bundled offline, no dev panel in release | all | B | `docs/tasks/README.md` |
| N16.11 | Field report + diagnostics copy dry-run (nothing sensitive leaves without review) | N13.17 | W | `docs/FIELD-REPORT.md` |
| N16.12 | Retire `app.old/` reference notes into `docs/`; update `README.md` to point at the new app | all | H | repo hygiene |

## Exit gate

All epics' exit gates met, invariant suite green, goldens approved, no dev-only
code in the release build, and the release checklist signed.

## Must-not-regress

Every invariant named across N1–N15, plus the copy discipline (the app's strongest
asset) and "a temperature is never scaled to fit".

---

## Hand-off

**Status: continue.** The host-testable verification slice of N16 landed and the
tree is green; the bench/board half of the epic is not runnable in a session.

### Landed

- **N16.2 invariant suite** — `app/test/verification/invariants_test.dart`: one
  named test per I2–I15 (16 tests; I1 is firmware). Anchored to the real seams
  (`planNotifications`, freshness, `SetupState`, `CostSheet`, `ConnectionSupervisor`,
  `InMemorySampleCache`, `CookPlan`, `CapabilityNotice`, `ProblemState`).
- **N16.1 copy audit** — `app/test/verification/copy_audit_test.dart`: source
  scans over `lib/features` + `lib/design` (no exception interpolation, no
  `Object error` parameter, no `print`/`debugPrint`) plus pure copy assertions
  (absent is `—`/`No reading`; a predicted rail node says `· expected`; a wire
  error maps to named copy).
- **N16.3 accessibility** — `app/test/verification/accessibility_test.dart`:
  spoken temperature labels, WCAG contrast in dark/light/daylight, 200 % text
  scale. Forced two real fixes:
  - `live_format.dart` `spokenTemp()`; `temp_card.dart` and `probe_sheet.dart`
    now carry `semanticsLabel` (absent reads "No reading").
- **N16.4 reduced motion** — `app/test/verification/reduced_motion_test.dart`:
  the token contract, a source guard against raw `const SmokeMotion().<token>`,
  and a widget test. Forced one real fix:
  - `verb_sheet.dart` paced its steps with `const SmokeMotion().value`, ignoring
    reduced motion; it now uses `SmokeMotion.of(context).valueEffective`.
- **N16.7 empty/problem/capability walkthrough** —
  `app/test/verification/empty_states_test.dart`: Timeline, History,
  Cook-detail (missing), Live (skipped onboarding), Temps and Graph each offer a
  wired way forward; a capability notice carries no control.
- **N16.11 field-report dry-run** — `app/test/verification/field_report_test.dart`:
  the diagnostics payload carries no secret; the field report asks for review and
  Cancel sends nothing.
- **N16.10 release-build checks** — `app/test/verification/release_build_test.dart`
  (`kReleaseMode` gates the dev panel; semver; changelog), plus `app/CHANGELOG.md`
  and `docs/RELEASE.md` (the checklist; the signed-APK and bench rows are for a
  human).
- **N16.12 repo hygiene** — `docs/new-app.md` (the rebuilt app's entry point),
  an "archived" banner on `docs/current-app.md`, and `README.md` + `app/README.md`
  updated to point at the new app, the verification suite and the release gate.

### Evidence

```
make app.test                                  # analyze + format + flutter test
  -> 774 tests pass (was 731; +43 verification)
cd app && dart test test/domain test/data      # -> 304 pass
cd app && flutter test test/verification       # -> 43 pass
```

One golden changed: `app/test/golden/goldens/temps.golden.txt`. The golden
harness serializes `Text.semanticsLabel`, so the new spoken labels appear in it.
Reviewed and regenerated with
`flutter test --update-goldens test/golden/temps_golden_test.dart`.

### Deviated / not done (next session)

- **N16.5 goldens** (the biggest remaining chunk): no destination ×
  {dark, light, daylight} × {compact, comfortable} matrix and no overlay
  goldens. The design gallery golden still pins the system across themes and
  densities. This is mechanical but large; generate with
  `make app.golden` and review the diff.
- **N16.6 performance** (15-hour chart scroll, LTTB, frame budget) needs a mid
  device.
- **N16.8 soak** (repeated Wi-Fi/BLE kill/restore against `tools/sim` or a board)
  needs the sim/board; `test/data/real_bridge_http_test.dart` covers a single
  host-side kill.
- **N16.9 adaptive layout** (width classes, bottom bar → rail) is optional for v1
  and was not attempted.
- **N16.10 bench rows** (signed APK, on-device install) and the human sign-off
  in `docs/RELEASE.md` §2–§3 remain.
- Goldens approved and the release checklist signed are human approvals.

### For the next session

Continue at N16.5: add a parameterized text-golden test for the destinations
using `pumpForGolden` + the `shellPulseEnabledProvider`/`shellClockProvider`
overrides the existing goldens use, then `make app.golden` and review. The
verification suite (`app/test/verification/`) is the regression net; keep it
green.