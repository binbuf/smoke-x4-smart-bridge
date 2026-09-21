# ROADMAP — new Flutter app (from the `newui/` prototype)

Ordered work packages for rebuilding the app at `app/` from the static HTML
prototype in `newui/`. Each bullet is one epic task file under `newui/tasks/`;
the epic file enumerates its numbered sub-tasks (`N0.1 … N16.12`). One fresh
symphony session runs per bullet, in file order. Dependencies are honoured by
that order (N0/N1 → N2/N3 → N4 → features → N9/N14 → N15 → N16).

Source of truth: `newui/NOTES.md` (translation map), `newui/components_research_notes.md`
(invariants I1–I15), and `newui/index.html` + `app.js` + `mock-data.js` + `styles.css`.
`app.old/` is reference only — do not copy systems or files wholesale.

## Wave 1 — Foundations

- [x] T01 — N0 Foundations: Flutter app skeleton, package set, lint/CI and golden harness → [tasks/N0-foundations.md](tasks/N0-foundations.md)
- [x] T02 — N1 Domain: entities, units, freshness, food safety and analysis engines → [tasks/N1-domain.md](tasks/N1-domain.md)
- [ ] T03 — N2 Data and mocks: catalog/style/timeline tables, scenarios, mock repository → [tasks/N2-data-and-mocks.md](tasks/N2-data-and-mocks.md)
- [ ] T04 — N3 Design system: tokens, typography, icons and component primitives → [tasks/N3-design-system.md](tasks/N3-design-system.md)

## Wave 2 — Shell and feature destinations

- [ ] T05 — N4 Shell: phone chrome, bottom nav, overlay framework and fullscreen graph host → [tasks/N4-shell.md](tasks/N4-shell.md)
- [ ] T06 — N5 Live: alerts, cook header, stopwatch, instrument mode, adopt banner, probe rail → [tasks/N5-live.md](tasks/N5-live.md)
- [ ] T07 — N6 Temps: per-probe cards, probe sheet, roles/targets, detached handling → [tasks/N6-temps.md](tasks/N6-temps.md)
- [ ] T08 — N7 Graph: chart, ranges, zoom/pan, fullscreen, legend isolate, targets/bands, stats → [tasks/N7-graph.md](tasks/N7-graph.md)
- [ ] T09 — N8 Timeline: Gantt, upcoming interventions, event rail, timeline DB projection → [tasks/N8-timeline.md](tasks/N8-timeline.md)
- [ ] T10 — N9 Catalog and setup: new/existing/watch, search, styles, custom food, add-item guard → [tasks/N9-catalog-and-setup.md](tasks/N9-catalog-and-setup.md)
- [ ] T11 — N10 Connection and provisioning: transport chip, connect sheet, AP/STA flows, rollback UX → [tasks/N10-connection-and-provisioning.md](tasks/N10-connection-and-provisioning.md)
- [ ] T12 — N11 Alarms and monitoring: strip/sheet/detail, two tiers, rules, delivery, quiet hours → [tasks/N11-alarms-and-monitoring.md](tasks/N11-alarms-and-monitoring.md)
- [ ] T13 — N12 History: history groups, cook detail, favourite/repeat/export/delete → [tasks/N12-history.md](tasks/N12-history.md)
- [ ] T14 — N13 Settings and device: settings tree, firmware/OTA, diagnostics, restart/forget/factory → [tasks/N13-settings-and-device.md](tasks/N13-settings-and-device.md)

## Wave 3 — Guidance

- [ ] T15 — N14 Onboarding: 8-step wizard, preflight, passkey coaching, troubleshoot → [tasks/N14-onboarding.md](tasks/N14-onboarding.md)

## Wave 4 — Real bridge

- [ ] T16 — N15 Bridge integration: real HTTP + BLE transports, sync engine, drift cache, background service, OTA → [tasks/N15-bridge-integration.md](tasks/N15-bridge-integration.md)

## Wave 5 — Verification and release

- [ ] T17 — N16 Verification and release: accessibility, copy audit, goldens, perf, release checklist → [tasks/N16-verification-and-release.md](tasks/N16-verification-and-release.md)