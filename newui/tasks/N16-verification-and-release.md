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