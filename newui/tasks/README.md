# Smoke X4 Smart Bridge — New Flutter App Task Backlog

Execution plan for rebuilding the Flutter app from the **new UI/UX prototype** in
[`newui/`](../). The old app is archived at [`app.old/`](../../app.old/) and is
**reference only** — do not copy systems or files from it wholesale.

> The prototype (`newui/index.html` + `app.js` + `mock-data.js` + `styles.css`) is the
> **visual and behavioural source of truth**. `newui/NOTES.md` is the translation
> map; `newui/components_research_notes.md` is the parts bin and invariant list.
> Where they disagree with `app.old/`, the prototype wins for UI, the research
> notes win for invariants.

---

## 1. Decisions already taken (do not relitigate)

| # | Decision | Value |
|---|---|---|
| D1 | New app directory | **`app/`** (legacy archived at `app.old/`) |
| D2 | State / architecture | **Riverpod + freezed** (the migration the legacy notes deferred) |
| D3 | Data strategy | **Mock-first**, then real HTTP/BLE transport ([N15](N15-bridge-integration.md)) |
| D4 | Domain logic | **Rebuilt fresh** in a new `domain/`, legacy as behavioural reference |
| D5 | Navigation | 5 bottom-nav destinations + overlay stack + fullscreen graph (no Cooks tab) |
| D6 | Charting | `fl_chart` (keep; decimation and area rules from NOTES §6) |
| D7 | Units | Storage is canonical tenths-°F; conversion **only at the display edge** |
| D8 | Theme | `ThemeMode` (system/light/dark) + a daylight **contrast profile** + density axis |

Any new decision that shapes more than one epic should be appended here with its
date and the session that took it.

---

## 2. Source-of-truth map

| What | Read | Why |
|---|---|---|
| Every screen, state and overlay | `newui/app.js` §6–§8 | The actual renderers and interactions |
| The data model and content tables | `newui/mock-data.js` | Catalog (139 foods), styles (133 cuts), timelines, scenarios, history, alarm rules, device/firmware |
| Translation guidance + `[BIZ]`/`[FLUTTER]` markers | `newui/NOTES.md`, `newui/app.js` | Which engine each surface maps to |
| Invariants I1–I15 | `newui/components_research_notes.md` §1 | Load-bearing rules a redesign may re-express but not violate |
| Transport / protocol / storage behaviour | `docs/design/03..09`, `protocol/` | The bridge contract the app consumes |
| Legacy engines for behavioural reference | `app.old/lib/domain`, `data`, `features` | Rate/ETA/stall math, safety floors, sync protocol — re-implement, don't vendor |

---

## 3. Prototype → app inventory (the build surface)

**Bottom-nav destinations** — `app.js` §6

`Live` · `Temps` · `Timeline` · `Graph` · `Settings` (owns `History` + `Cook detail`)

**Overlays** — `app.js` §7

`onboarding` · `setup` (3 start modes + catalog + styles + custom food) · `connect`
(dual-link) · `modes` · `modesRef` · `provisionSta` · `provisionAp` · `alarms` ·
`alarmDetail` · `mark` · `probe` · `adopt` · `editStart` · `confirm` · `customFood` ·
`firmware` · `firmwareUpdate` · `diagnostics` · `verb`

**Theme axes** — `styles.css`, `mock-data.js settings`

`themeMode` (system/light/dark) · `displayProfile` (standard/daylight) · `density`
(compact/comfortable) · `reducedMotion`

---

## 4. Task format

`<Epic>.<n> <component>: <imperative>` — every task carries four fields:

| Field | Values |
|---|---|
| `blocked-by` | task ids, or `—` |
| `verify` | **H** unit/host · **W** widget + golden · **S** integration vs mock/`tools/sim` · **B** real board · **C** real cook |
| `design` | the exact prototype/doc location so the implementer does not re-derive a decision |

Each epic file ends with an **Exit gate** and a **Must-not-regress** list naming the
invariants it touches.

---

## 5. The epics

| File | Epic | Depends on |
|---|---|---|
| [N0-foundations.md](N0-foundations.md) | Project skeleton, packages, lint, CI, golden harness | — |
| [N1-domain.md](N1-domain.md) | Entities, units, freshness, safety, analysis engines | — |
| [N2-data-and-mocks.md](N2-data-and-mocks.md) | Content tables, repositories, `MockBridgeRepository`, event bus | N1 |
| [N3-design-system.md](N3-design-system.md) | Tokens, typography, icons, component primitives | N0 |
| [N4-shell.md](N4-shell.md) | Phone chrome, app bar, bottom nav, overlay/sheet framework, fullscreen graph host | N2, N3 |
| [N5-live.md](N5-live.md) | Live glance: alerts, cook header, stopwatch, instrument mode, adopt banner, probe rail, mini graph | N4 |
| [N6-temps.md](N6-temps.md) | Per-probe big cards, probe sheet, roles/targets, detached handling | N4 |
| [N7-graph.md](N7-graph.md) | Chart, ranges, zoom/pan, fullscreen, legend isolate, targets/bands, marks, stats | N4 |
| [N8-timeline.md](N8-timeline.md) | Gantt, upcoming interventions, event rail, timeline DB projection | N4 |
| [N9-catalog-and-setup.md](N9-catalog-and-setup.md) | Setup sheet (new/existing/watch), catalog search, styles, custom food, add-item guard | N4, N8 |
| [N10-connection-and-provisioning.md](N10-connection-and-provisioning.md) | Transport chip, connect sheet, modes + tech ref, AP/STA provisioning, rollback UX | N4 |
| [N11-alarms-and-monitoring.md](N11-alarms-and-monitoring.md) | Alarm strip/sheet/detail, two tiers, rules, delivery, quiet hours, background monitoring | N4 |
| [N12-history.md](N12-history.md) | History groups, cook detail, favourite/repeat/export/delete | N4 |
| [N13-settings-and-device.md](N13-settings-and-device.md) | Settings tree, firmware/OTA, diagnostics, restart/forget/factory verbs | N4 |
| [N14-onboarding.md](N14-onboarding.md) | 8-step wizard, preflight, passkey coaching, troubleshoot | N4, N10 |
| [N15-bridge-integration.md](N15-bridge-integration.md) | Real HTTP + BLE transports, sync engine, drift cache, background service, OTA | N2, N10, N11 |
| [N16-verification-and-release.md](N16-verification-and-release.md) | Accessibility, copy audit, goldens, perf, release checklist | all |

---

## 6. Execution order

```
Wave 1   N0 ─┬─ N1 ── N2
             └─ N3
Wave 2   N4 ─┬─ N5  N6  N7  N8  N10  N11  N12  N13
             │
Wave 3   N9 (needs N8)      N14 (needs N10)
Wave 4   N15 (swap the mock repo for real transports)
Wave 5   N16 (gate)
```

Waves are a scheduling aid; **each task's `blocked-by` is authoritative**.
N5–N13 are independent of one another once N4 lands and can be run in parallel
sessions.

---

## 7. Scope

**In:** the five destinations, every overlay above, the catalog + timeline + style
content tables, three start modes, dual-link connection UX, two-tier alarms,
history, settings/device management, onboarding, theming (light/dark/daylight/
density), units, reduced motion, then the real bridge transport.

**Out (do not build here):** iOS, MQTT/Home Assistant, a device-served web UI,
cloud sync/push, a multi-bridge picker, wearable/Glance targets, localisation
(English only for now), photo attach on a cook, any LoRa transmission beyond the
network layer.

---

## 8. Open questions

| # | Question | Blocks | Needed by |
|---|---|---|---|
| Q1 | Tailwind-style token names (`N0`) vs the legacy `SmokeTokens` names | N3 | Wave 1 |
| Q2 | Is the timeline DB user-tunable per cook, or shipped read-only? | N8, N9 | Wave 2 |
| Q3 | Auto-adopt the bridge session, or keep the explicit tap? | N5, N9 | Wave 3 |
| Q4 | Does stopwatch pause suppress alarms, or only the displayed clock? | N5, N11 | Wave 2 |
| Q5 | Food imagery: vector glyphs vs photography | N3, N9 | Wave 2 |

Answers get recorded in `docs/design/` or a short `newui/tasks/DECISIONS.md`, not
buried in a commit message.