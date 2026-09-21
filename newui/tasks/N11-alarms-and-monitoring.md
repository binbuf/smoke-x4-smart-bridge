# N11 — Alarms & monitoring

**Goal:** the two-tier alarm system — device rules (authoritative) and app
insights (advisory), kept visibly separate — plus notification delivery, quiet
hours and background monitoring.

**Design:** [`newui/app.js`](../app.js) §6 `alarmStrips`, §7 `overlayAlarms`,
`overlayAlarmDetail` · `newui/NOTES.md` §3.1, §6 · `mock-data.js` ALARM_RULES,
alarm scenarios · `docs/design/09`.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I2 | The device is authoritative; the app mirrors device alarms and never re-decides them | tier tags, no merge without tag |
| — | App alarms are labelled **Insight**; device alarms **Device**; the two are never merged untagged | list rows |
| — | Quiet hours 22:00–06:00 silence warning/info, **never critical**, in phone local time | preferences |
| — | Critical escalation: repeat 5 min, full-screen 10 min (critical only) | delivery |
| I15 | No raw exception reaches the user; failures are named states with copy | `BridgeRefusal` |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N11.1 | Alarm strip on Live (already in N5.1) completed with tier tags + ack | N5.1 | W | `app.js` alarmStrips |
| N11.2 | Alerts sheet: "Active now" list (severity icon, rule, tier, detail, ack) or the all-clear notice | N5.1 | W | `app.js` overlayAlarms |
| N11.3 | Delivery card: "This phone will wake you" verdict + Send a test alarm | N11.2 | W | `app.js` overlayAlarms |
| N11.4 | "From the bridge — authoritative" group: the 9 device rules with enable toggles | N2.23 | W | `mock-data.js` ALARM_RULES |
| N11.5 | "Insights from the app — never overrides the bridge" group: the 3 app rules | N11.4 | W | `app.js` overlayAlarms |
| N11.6 | Preferences: prefer my own alarms, quiet hours, background monitoring | N2.25 | W | `app.js` overlayAlarms |
| N11.7 | Alarm detail: severity card, fired time/ago, tier tag, "why this fired" (rule, trigger, reading, suggestion) | N11.2 | W | `app.js` overlayAlarmDetail |
| N11.8 | Detail actions: Acknowledge, Snooze 10m, View on graph | N11.7 | W | `app.js` overlayAlarmDetail |
| N11.9 | Acknowledge silences, does not resolve (device semantics) | N11.8 | H | `components_research_notes.md` §2.2 |
| N11.10 | "Prefer my own alarms" changes which notification wins; device alarms remain authoritative in the list | N11.6 | H | Start.md, NOTES §3.1 |
| N11.11 | Pure `planNotifications()` over device alarms, on-screen keys, wall clock, app findings, quiet hours, monitoring flag → post/withdraw | N1.19 | H | research notes §6.4 |
| N11.12 | Four channels (critical/warning/info/ongoing); critical bypasses quiet hours | N11.11 | H | research notes §6.4 |
| N11.13 | Escalation ladder (repeat 5 min, full-screen 10 min, critical only) | N11.12 | H | research notes §6.4 |
| N11.14 | Background monitoring surface: service checks the bridge and bubbles alarms when the app is backgrounded | N11.11, N15 (real) | S | `Start.md`, research notes §8 |
| N11.15 | Bridge-unreachable insight when the link drops mid-cook | N11.11 | W | `mock-data.js` offline scenario |
| N11.16 | Alarm rule editor for **app** tier only (device rules are toggled, not invented) | N11.4 | W | `components_research_notes.md` §11.3, I5 |

## Exit gate

The `running` and `offline` scenarios raise and acknowledge alarms correctly; a
test alarm proves delivery; quiet hours silence a warning but not a critical; the
list never shows a device rule without its Device tag.

## Must-not-regress

I2, I15 and the two-tier separation. **Do not merge the tiers.**

## Open question

Q4 — does stopwatch pause suppress alarms/notifications, or only the displayed
clock? The prototype assumes the latter (device is authoritative). Resolve with
N5.5.