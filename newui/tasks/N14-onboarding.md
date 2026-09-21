# N14 — Onboarding

**Goal:** the guided first-run wizard: pair over BLE, coach the passkey, listen for
the base station, choose a network mode, name the bridge, done.

**Design:** [`newui/app.js`](../app.js) §7 `overlayOnboarding`, `permRow`,
`modeCardCompact` · `newui/NOTES.md` §6 · `components_research_notes.md` §11.5,
§12 · `docs/design/05`.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| — | The passkey is shown **only on the device OLED**; the app cannot render a real code and coaches the user before Android's own (wrong) dialog | passkey step |
| — | The bridge is a pure listener: pairing is non-destructive and the base-pair step teaches that | sync step |
| I6 | No state without a next step | every step |
| I15 | No raw exception escapes; failures become named states with copy | `SetupFault` |
| — | A superseded flow cannot drag the user backwards (monotonic generation counter) | wizard controller |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N14.1 | `SetupMachine`: 8 named steps (welcome, preflight, scan, passkey, sync, network, name, done) with a step rail; monotonic generation guard | N4.6 | H | research notes §12 |
| N14.2 | Step 1 welcome: device illustration + "records with or without your phone" | N14.1 | W | `app.js` overlayOnboarding |
| N14.3 | Step 2 preflight: Bluetooth / Notifications / Location (older Android) permission rows; denied states resumable | N14.1 | W | `app.js` permRow, research notes §12 |
| N14.4 | Step 3 scan: scan ring, found-bridge card, "Can't find it?" | N14.3 | W | `app.js` overlayOnboarding |
| N14.5 | Troubleshoot sub-flow: powered? Bluetooth on? restart the bridge; Back / Try again | N14.4 | W | `app.js` onboardTroubleshoot |
| N14.6 | Step 4 passkey: "type the six digits from the bridge's own screen, not the 0000 your phone suggests"; MonoWell placeholder; coaching copy | N14.4 | W | `app.js` overlayOnboarding |
| N14.7 | Step 5 sync: "Listening for your Smoke X4" + pure-listener notice | N14.6 | W | `app.js` overlayOnboarding |
| N14.8 | Step 6 network: the three mode cards (default BLE), changeable later | N14.7, N10.4 | W | `app.js` overlayOnboarding |
| N14.9 | Step 7 name + units | N14.8 | W | `app.js` overlayOnboarding |
| N14.10 | Step 8 done: "You're all set" → Go to Live | N14.9 | W | `app.js` overlayOnboarding |
| N14.11 | Recovery paths: link-lost, fault, resume; a skipped hop reads "— not set up" | N14.10 | W | research notes §11.5 |
| N14.12 | First-run gating: the wizard shows only when no bridge is known; later launches go straight to the shell | N14.1, N2.29 | S | `app.js` launch logic |
| N14.13 | Skip is allowed; the shell then shows the "connect a bridge" empty state, never a dead end | N14.12 | W | I6 |

## Exit gate

A factory-fresh state walks all 8 steps to a live shell; denying a permission
gives a resumable, named state; "Skip" lands on a shell that offers a way to
connect.

## Must-not-regress

The passkey is never rendered by the app; no state lacks a next step; a superseded
flow cannot drag the user backwards.