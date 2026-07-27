# M8 — The UX re-architecture (v1.2)

**Exit gate:** a factory-reset bridge and a factory-reset phone reach a live, guided cook over three
named hops without the user ever reading a wire identifier, a stack trace, or a temperature that is
not true — and then, with the bridge's power pulled mid-cook, the phone tells the truth on the lock
screen within 90 seconds.

**Design:** [13 §13.1–§13.8](../design/13-ux-architecture.md) ·
[14 §14.1–§14.6](../design/14-design-system.md) ·
[05](../design/05-connectivity-and-provisioning.md) ·
[07](../design/07-display-and-controls.md) · [06 §6.2](../design/06-device-api.md) ·
[08](../design/08-flutter-app.md)

**Confidence markers**, as [02](../design/02-smoke-x-protocol.md) uses them: **[K]** measured or read
out of the source · **[I]** inferred from the source but not run · **[?]** unknown until a bench
sitting takes it. Every estimate below is an estimate; the marker says which kind.

## Why

M4 shipped the MVP and M7 moved every control to the phone. What neither did was make setup
*survive itself*. Four failures are catastrophic in the literal sense — the product does not work
and the user cannot tell why:

1. **Setup succeeds, then un-succeeds.** `OnboardingRoute._verifyOverHttp` builds its verifier with
   `writeCache: (_) async {}` (`onboarding_route.dart:86`), so `prefs.lastBaseUrl` is still null the
   instant the wizard says *"Reached it at http://192.168.1.57"* → `neverMetABridge`
   (`connection.dart:104`) → `LaunchNeedsOnboarding` → `dashboard_route.dart:60` drops the user back
   into step 1 of the wizard they just finished, with no message. **[K]**
2. **Hosted-AP mode cannot complete.** `AP_STARTING` is stranded — `set_mode_internal` sets it
   (`app_net_core.c:273-277`) and `app_net_core_tick` has no case for it. The Kotlin binder answers
   `result.success(null)` before `invokeMethod("onBound")` (`NetworkBinder.kt:77-83`), so a join that
   worked reads as `false`. The escape hatch throws `BinderStateError` and lands on the same screen,
   permanently. **[K]**
3. **The bridge is never introduced to the thermometer.** There is no base-pairing step in the
   wizard (`wizard.dart:50-144`), and `alarm_task` seeds `since_last_packet_s` from boot with no
   pairing gate (`app_alarm.c:195-198`, `rules.c:246-247`) — so a brand-new bridge posts *"Base
   station lost"* ten minutes after setup, about hardware the user has not connected. **[K]**
4. **The glass and the phone contradict each other, and both freeze.** `BridgeSession` swallows link
   death (`onError: (Object _) {}`, `bridge_session.dart:88-92`), `AppConnection.reconnect()` has
   zero production callers, and there is no *periodic* ticker anywhere in `app/lib/` (two one-shot
   `Timer`s exist at `ble_gatt_fbp.dart:71,113`). A four-hour-old pit temperature renders under a
   green Wi-Fi chip with a frozen cook clock. **[K]**

M8 is the milestone that closes all four and rebuilds the app around one truth model instead of four
independent sources. **88 tasks — 74 `board: no`, 14 `board: yes`.** The board rows batch into four
sittings ([§12.6 rule 7](../design/12-task-planning-notes.md)): W0's bench facts, W2's heap
measurement, the W6–W9 firmware sitting, and the exit gate.

---

## The packages, in order

`⚑` marks a package that is **independently shippable** — merge it, cut a release, and the product
is materially better than the one before it. A reader who stops after W3 has removed every
catastrophic failure except hop 2, which cannot be pulled forward because it needs W0's bench facts
and W8's protocol bump.

| W | Package | Epic | Side | Board | Days | Shippable |
| --- | --- | --- | --- | --- | --- | --- |
| **W0** | Bench facts | V6 | — | **yes** | 1 | — (blocks W6, W7, W9) |
| **W1** | Stop the bleeding | A17 | app | no | 4 | **⚑** |
| **W2** | The parser, the panic paths, the heap | F17 | firmware | **yes** | 4 | **⚑** |
| **W3** | Preflight and the platform seams | A18 | app + Kotlin | no | 7 | **⚑** |
| **W4** | Design system | A19 | app | no | 8 | — (with W5) |
| **W5** | Shell, truth model, link controller | A20 | app | no | 9 | **⚑** (with W4) |
| **W6** | Setup rewrite — hops 1 and 3 | A21 | app | **yes** | 10 | **⚑** |
| **W7** | Firmware: network, BLE, glass | F18 | firmware | **yes** | 10 | **⚑** |
| **W8** | The coordinated protocol bump | P4 · T6 | both | no | 8 | — (enables W9) |
| **W9** | Hop 2, end to end | F19 · A22 · T6 | both | **yes** | 9 | **⚑** |
| **W10** | The cook screen and the guided cook | A23 | app | no | 11 | **⚑** |
| **W11** | Alarms, History, Bridge | A24 | app | no | 7 | **⚑** |
| **W12** | Accessibility, copy, verification | A25 | app | no | 5 | — (gate) |
| **—** | Exit gate | V7 | — | **yes** | 2 | — |

**≈ 95 engineer-days.** These are estimates, not measurements: they assume the author of each
package has the design docs open and does not have to re-derive a decision, and they include tests
and goldens but not review latency. The three packages most likely to be wrong are W6 (a ~34-state
machine against two OEM-variable radios), W9 (gated on a bench measurement nobody has taken) and
W10 (the only package that invents a domain model rather than projecting one).

```
        Firmware lane                        App lane
        ─────────────────                    ──────────────────────────────
W0      V6 bench facts ⚠ ───────────────────────────┐
          │                                          │
W1        │                                    A17 stop the bleeding ⚑
W2      F17 parser + panic + heap ⚑                  │
W3        │                                    A18 preflight + seams ⚑
W4        │                                    A19 design system
W5        │                                    A20 shell + truth ⚑
W6        │                                    A21 setup hops 1+3 ⚑ ◄── needs V6.3
W7      F18 network + BLE + glass ⚑ ◄── needs V6.2  │
          └──────────────┬───────────────────────────┘
W8                    P4 · T6  protocol bump (both)
                            │
W9                 F19 · A22 · T6  hop 2 (both) ⚑ ◄── needs V6.1
                            │
W10                        A23 cook + guided ⚑
W11                        A24 alarms/history/bridge ⚑
W12                        A25 a11y + copy + verification
                            │
                       ◄── M8 EXIT GATE (V7)
```

**Critical path: W0 → W4 → W5 → W6 → W8 → W9 → W10 → W12 ≈ 61 days.** The firmware lane
(W0 → W2 → W7 → W8 → W9 ≈ 32 days) is not the constraint; it finishes early and its engineer is the
second pair of hands on W6 and W10. With two engineers the parallel calendar is **≈ 13 weeks**; with
one full-stack engineer working the waves serially it is the full 95 days, **≈ 19 weeks**.

### Ownership, assigned here because no other document is in a position to

| Concern | Owner |
| --- | --- |
| `protocol/records.yaml` + `openapi.yaml` + `ble-gatt.md` | **OWNER: TBD — assign before W8.** Four generated files and three hand-written specs have been edited independently by three proposals. Without one named owner the bump lands three times against three schemas. |
| Plain-language copy review (every string in W6, W9, W10, W11) | **COPY OWNER: TBD — assign before W6.** The reading-level gate ([13 §13.3.7](../design/13-ux-architecture.md)) is a merge gate, not a suggestion; a gate with no named reviewer is a comment. |
| The preset table as a food-safety artifact | **REVIEWER: TBD — assign before W10.** See A23.2. |

---

## Heap budget

**The floor is 80 KB, not 70.** [`hardware-verified.md:450`](../hardware-verified.md) sets
`min_free_heap ≥ 80 KB` for the whole 24 h soak and says, verbatim, *"if it does \[bite\], the answer
is not 'lower the bar'"*. V3a.1 measured **78.2 KB [K]** — already under. So the rule for this
milestone is not "spend carefully", it is:

> **Every firmware addition in M8 must be net-neutral against 78.2 KB, or F17.5 must buy the headroom
> back first.** No wave merges until `/api/v1/debug/tasks` and `min_free_heap` are recorded in
> `docs/hardware-verified.md` for that wave's build.

| Addition | Lands in | Est. | Conf. | Note |
| --- | --- | --- | --- | --- |
| `pair_status` characteristic | P4.2 | ~64 B | **[I]** | one static 20 B snapshot + a NimBLE attribute entry |
| `live_state` +1 B, `net_status` +1 B | P4.1 | 0 | **[K]** | existing static buffers, no reallocation |
| ops 14/15 + the stance struct | P4.1 | ~32 B | **[I]** | static |
| CCCD tracking bitmap | F18.5 | ~16 B | **[I]** | `CONFIG_BT_NIMBLE_MAX_CCCDS=8`, already configured and unused |
| Listen-window state in `smoke_x_ctrl` | F19.1 | ~64 B | **[I]** | static; deadline + saved binding |
| Multi-unit candidate table (3 × 16 B) | F19.6 | ~48 B | **[I]** | static, dwell-window only |
| OTA progress publisher | F18.8 | ~0 | **[I]** | one extra `bridge_event_post` from the existing OTA task; no new queue |
| `hello` state snapshot | P4.6 | ~1 KB | **[I]** | built on the httpd task stack, not the heap; costs stack margin, not `min_free_heap` |
| QR encoder | F18.4 | 0 heap · ~3 KB flash · ~400 B stack | **[I]** | fixed version-3, no allocator |
| Framebuffer dirty-check scratch | F17.2 | +1 KB `.bss` | **[K]** | trades heap for `.bss` and *removes* ~23 ms of I²C per tick |
| AP_STARTING case, reconciliation, watchdogs, `base_lost` gating | F18.1, F19.2 | 0 | **[K]** | control flow only |
| Marks read route | P4.8 | ~0 | **[I]** | reuses the session reader's buffer |
| **Second tracked BLE connection** | F18.5 | **~1.2 KB** | **[I]** | **CONDITIONAL.** NimBLE already allocates for `MAX_CONNECTIONS=2` (`sdkconfig.defaults:15`); the handle array and per-conn state are ours |
| **`APP_API_WS_MAX_CLIENTS` 2 → 4** | P4.6 | **~4–6 KB** | **[I]** | **CONDITIONAL, and the largest single item.** Two more httpd sockets plus our per-client struct |

**Unconditional total ≈ 1.3 KB heap + 1 KB `.bss`.** Survivable at 78.2 KB, but it does not restore
the floor. **Conditional total ≈ 5.2–7.2 KB**, which is not.

**The rule, stated plainly:** the two conditional items do not merge until **V6.4 re-measures free
heap** and **F17.5 has bought back at least 8 KB**. If F17.5 comes up short, v1.0 ships with
`APP_API_WS_MAX_CLIENTS = 2` and the *"another device is watching this cook — Take over"* flow
(A20.5), which is a better product than a bridge that runs out of memory 14 hours into a brisket.
The second BLE connection is the one to keep if only one can be afforded: without it, one connected
phone makes the bridge invisible to every other phone in the household, with no explanation.

---

## W0 — V6 · Bench facts

- **side:** — · **board:** **yes** · **days:** 1 · **blocks:** W6, W7, W9

Five numbers and two behaviours that no amount of reading closes. Everything downstream that rests
on one of them is flagged at its task. **This is one sitting.**

> **What the repo already knows, so the sitting does not re-take it.**
> [`docs/reference/smoke-x-receiver/README.md:147`](../reference/smoke-x-receiver/README.md) states
> that an unpaired receiver alternates the two sync channels (920 MHz X2 / 915 MHz X4), that placing
> the base in sync mode makes it **send sync bursts every three seconds**, and that once the ESP32
> transmits its sync response on the target frequency **the base returns to normal operation**. The
> beacon interval and the post-ACK behaviour are therefore **[K]**, not unknowns. Hop 2 has exactly
> **three** genuine unknowns, not five.

### V6.1 bench: the X4 sync gesture — the three genuine unknowns

- **blocked-by:** — · **verify:** B · **board:** yes · **design:** [13 §13.2.2](../design/13-ux-architecture.md)

Put a real Smoke X4 base into sync mode with a stopwatch and a camera. Record, into
`docs/hardware-verified.md` under a new *"Smoke X4 sync"* heading:

| Fact | Status | Sets |
| --- | --- | --- |
| The physical control and its hold duration | **[?]** | the illustrated instruction card in `base_sync_copy.dart` |
| The base's own tell that sync mode is active (LCD legend, LED, beep) | **[?]** | *"Its screen will show …"* — the sentence that tells the user their action registered |
| How long the sync window stays open before the base gives up | **[?]** | `kListenWindowS`, and through it `kListenBudgetS` |
| Beacon repeat interval while open | **[K]** 3 s | the *"we're hearing something"* threshold |
| Post-ACK behaviour | **[K]** returns to normal operation | the `SYNC_RECEIVED` watchdog's success edge |
| Interval from ACK to the first state message | **[?]** | the `SYNC_RECEIVED` watchdog's **timeout** (F19.2) |

**The budget constants are derived, not guessed, and they live in one file** —
`app/lib/features/setup/copy/base_sync_copy.dart`, beside the copy, each with a comment citing this
sitting:

```dart
const kListenWindowS = /* V6.1 measured */;          // the base's own window
const kListenFloorS  = 20;                           // 6 beacons at the [K] 3 s interval,
                                                     // enough that a single missed burst is not a failure
const kListenBudgetS = max(kListenFloorS, 2 * kListenWindowS);
```

`kListenFloorS = 20` is the only invented number and it has a derivation: at a **[K]** 3 s beacon
interval, 20 s is six chances to hear one burst, so a listen that fails has failed for a reason the
user can act on rather than for bad luck. **One budget, one derivation, one file** — no screen holds
a literal, and if the bench says the window is 15 s rather than 30, three constants change and no
screen is redesigned.

**Done when:** the three `[?]` rows are `[K]` with a photograph of the base in sync mode committed
beside them, `base_sync_copy.dart` cites this row by task id, and any fact the sitting could not take
is written down as an open row rather than left blank.

### V6.2 bench: does `esp_wifi_set_config(WIFI_IF_AP, …)` re-emit `WIFI_EVENT_AP_START`?

- **blocked-by:** — · **verify:** B · **board:** yes · **design:** [05 §5.8](../design/05-connectivity-and-provisioning.md)

The hosted-AP root-cause chain is verified end to end **except this one link**, and the whole of
F18.1 rests on it. `op_start_ap` (`app_net.c:53-93`) calls `esp_wifi_set_config` **then**
`esp_wifi_set_mode(WIFI_MODE_APSTA)` — and APSTA is already the mode on a factory-fresh bridge
(`app_net.c:543-548`) **[K]**. Whether the `set_config` on an already-running AP interface re-emits
`WIFI_EVENT_AP_START` is **[?]** — an IDF behaviour this repo has never measured.

Log every `WIFI_EVENT_*` with a timestamp, then call `op_start_ap` from three starting states: cold
(no AP), APSTA with the AP already up, and APSTA with the AP up under a different SSID.

**Done when:** the three event sequences are in `docs/hardware-verified.md`, and F18.1's design is
either confirmed (no re-emit → the `AP_STARTING` case with a deadline is required) or corrected (it
does re-emit → the fix collapses to the missing `tick` case alone). **If this row is skipped, F18.1
ships on an inference and must say so in its commit message.**

### V6.3 bench: BLE survival across `esp_wifi_set_mode`

- **blocked-by:** — · **verify:** B · **board:** yes · **design:** [13 §13.2.3](../design/13-ux-architecture.md)

Hop 3 hands the bridge a Wi-Fi configuration over BLE and then waits. `_watchLink` today emits
`WizardLinkLost` on **any** disconnect while the flow is live (`wizard.dart:226-232`) **[K]**, and a
brief BLE drop across an ESP32-S3 radio reconfigure is expected rather than exceptional. A21.4's
grace window needs a real number.

With a phone bonded and subscribed, drive `wifi_config` ten times and record: whether the BLE link
survives at all, and if it drops, the reconnect latency distribution.

**Done when:** `kApplyGraceMs` has a measured value (default 5000 until it does), the ten trials are
tabulated, and the *"does the link survive"* answer is `[K]` in `docs/hardware-verified.md`.

### V6.4 bench: re-measure `min_free_heap` against the 80 KB floor

- **blocked-by:** — · **verify:** B · **board:** yes · **design:** [standing-work](standing-work.md)

V3a.1's 78.2 KB **[K]** is from M3 and predates M5, M6 and M7. Flash the current `main` build, bring
up AP + NimBLE + httpd + both LittleFS mounts + a WebSocket client, and read
`/api/v1/debug/tasks` — the endpoint V3.1 built precisely so an unattended board can answer this
without a serial cable.

**Done when:** a current `min_free_heap`, largest-free-block and per-task stack watermark set is in
`docs/hardware-verified.md` with the build's git sha, and the heap-budget table above is annotated
with the real starting number rather than M3's.

---

## W1 — A17 · Stop the bleeding ⚑

- **side:** app · **board:** no · **days:** 4 · **blocked-by:** —

Five app-only changes that make the two worst loops unreachable. **Nothing here needs the design
system, the truth model, or a protocol bump** — that is the point. It ships on its own.

### A17.1 data/prefs: persist at every proof point, not at Done

- **blocked-by:** A7.5 · **verify:** H · **board:** no
- **design:** [13 §13.2.4](../design/13-ux-architecture.md), [08 §8.4](../design/08-flutter-app.md)

`BridgePrefs` gains `lastBridgeName`, `lastMode`, `lastApSsid`, `lastApPsk`, `lastBleDeviceId`,
`basePaired`, `setupResumeAt` and `poweredOffAt`, and every one is written **at the moment its fact
becomes true**, not at the end of a flow the user may never reach:

| Proof point | Write |
| --- | --- |
| bond succeeds | `lastBridgeId` (from `device_info.id`), `lastBleDeviceId` |
| pairing confirms | `basePaired = true` |
| `net_status.state == up` | `lastMode`, plus `lastApSsid`/`lastApPsk` when AP |
| HTTP 200 from `_verifyOverHttp` | `recordConnection(url, bridgeId:)` — the id is captured at `onboarding_route.dart:76` today **and discarded** **[K]** |
| name + units submitted | `lastBridgeName`, `displayUnits` |

**Done when:** each proof point is asserted to write exactly its own keys and nothing else, an
abandoned setup leaves a resumable stub rather than a half-state, a corrupt preference degrades to
absent rather than throwing, and `onboarding_route.dart`'s `writeCache: (_) async {}` is gone.

### A17.2 app: key the setup gate on identity, not on an address

- **blocked-by:** A17.1 · **verify:** H · **board:** no
- **design:** [13 §13.2.4](../design/13-ux-architecture.md), [08 §8.4](../design/08-flutter-app.md)

`LaunchNeedsOnboarding` stops deriving from `lastBaseUrl == null` and becomes
`prefs.lastBridgeId == null` — *"have we ever met a bridge"* is **identity**, not **address**. A
BLE-only session, a DHCP move or a failed race can then never re-trigger setup.

**This is a seam change, not a one-liner, and the plan should stop calling it one.**
`connection.dart:134` is `writeCache: (baseUrl) => prefs.recordConnection(baseUrl)` — one argument
**[K]**. Making `_defaultProbe` return the verified device id changes `ConnectionProbe`'s typedef
(`connection_manager.dart:56-57`), the lane plumbing that consumes it, and `writeCache`'s signature.
Do all four in this task or none. `_defaultProbe` also stops accepting any host that returns a
non-empty `deviceId` (`connection.dart:171-181`) and rejects a mismatch against `lastBridgeId`,
which is what its own contract already promises.

**Done when:** a launch → connect → relaunch sequence over the fake never re-enters setup; a probe
that answers with a *different* bridge id is rejected rather than cached; the four seam signatures
change together and the analyzer is clean; and a test asserts that a BLE-only win still leaves the
user out of the wizard.

### A17.3 features/settings: wire `forgetBridge()` and give the user a way back in

- **blocked-by:** A17.1 · **verify:** H · **board:** no
- **design:** [13 §13.5.6](../design/13-ux-architecture.md)

`forgetBridge()` (`bridge_prefs.dart:47`) has **zero production callers** and `/onboarding` is
reachable from exactly one place **[K]** — so after a factory reset, which the app's own dialog warns
forces re-pairing (`settings_screen.dart:456-459`), the user is permanently locked out of their own
hardware. Add `SettingsSection.bridge` first in the list, with **Set up a new bridge** and **Forget
this bridge**, and route factory-reset and power-off completion through the forget path. Power-off
additionally writes `poweredOffAt`, so the offline surface can say *"You switched this bridge off at
20:14"* instead of *"can't connect"*.

**Done when:** factory reset lands on setup rather than on a dead dashboard, forget clears exactly
the bridge-scoped keys and leaves cached cooks alone until the user says otherwise, power-off writes
its timestamp, and a widget test asserts a setup entry point exists from Settings on every transport.

### A17.4 features/dashboard: export through the share sheet, inside a try/catch

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [13 §13.5.2](../design/13-ux-architecture.md), [04 §4.2](../design/04-storage-and-history.md)

`_export`'s rejected future escapes to `runZonedGuarded` and replaces the app with a stack trace
**[K]**; on success the SnackBar reports `/data/user/0/…`, a path no non-technical Android 11+ user
can reach. Wrap it, and add a `ShareExportSink` behind the existing `ExportSink` seam so the file
lands in the Android share sheet.

**Done when:** a throwing sink renders a typed problem state rather than the error boundary, the
success path is asserted to hand the file to the share seam rather than printing a path, and the
CSV's byte-compatibility with the device's `format=csv` (A11.4) is unchanged.

### A17.5 app: `BootFailureRoute` — the black-screen path

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [13 §13.5.8](../design/13-ux-architecture.md)

`bootstrap()` awaits `openAppDatabase()`, `SharedPrefsBridgePrefs.load()` and
`getApplicationDocumentsDirectory()` **before** `runApp` (`bootstrap.dart:35-48`) **[K]**. A throw in
any of them means `runApp` is never reached and the zone handler sets a `ValueNotifier` no mounted
widget observes: white launch window, then a permanently black screen, no timeout, no retry. Wrap
environment construction; on failure `runApp` a minimal recovery app — *"Smoke Bridge could not
start"* → **Try again** · *Reset local data*.

**Done when:** each of the three constructors is fault-injected in a test and each renders the
recovery app with a working retry, *Reset local data* deletes the drift file and re-runs bootstrap,
and the recovery app depends on nothing that can itself fail to construct.

---

## W2 — F17 · The parser, the panic paths, and the heap ⚑

- **side:** firmware · **board:** **yes** (F17.5 only) · **days:** 4 · **blocked-by:** —

Four defects that can take the bridge down or make it unusable, plus the heap headroom every later
firmware wave spends. **F17.1 is a hard prerequisite for every settings write path in M8.**

### F17.1 app_api: fix the `probes[]` rescan loop, and two adjacent validation defects

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [06 §6.2](../design/06-device-api.md)

`app_api_core.c:841-842` **[K]**:

```c
while ((p = strstr(p, "{\"n\"")) != NULL ||
       (p = strstr(probes, "{ \"n\"")) != NULL) {
```

The second alternative restarts from `probes` on every iteration, so **any pretty-printed body** —
curl, Postman, a Home Assistant integration — re-finds the first object forever: the httpd task spins
and the same NVS keys are rewritten in a tight loop. The route is unauthenticated by default
(`auth_ok` returns `true` on an empty token, `:189-191`) with `Access-Control-Allow-Origin: *`. The
shipped Flutter app is safe only because `jsonEncode` emits compact JSON.

Replace it with one tolerant forward scan: advance `p` past each parsed object and search from `p`
for `{` followed by optional whitespace and `"n"`. Two adjacent fixes in the same function, both
required before any settings screen writes: return **400 `invalid_field`** with the limit when
`app_api_json_str` overruns (today a >16-char probe name is silently dropped under a
`200 {"ok":true}`), and clamp `display_timeout_s` to `{0} ∪ [15,600]` (today `handle_config_device_post`
validates nothing, `:790-792`, so a 1-second timeout is settable and kills the passkey screen).

**Done when:** a host test posts a pretty-printed `/config/device` body with two probes and asserts
it returns once, in bounded time, having written each key exactly once; an over-length name returns
400 with the limit named; `display_timeout_s = 1` is refused and `0` is accepted.

### F17.2 app_ui: take I²C off the event loop, and make the dirty check real

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [07 §7.1](../design/07-display-and-controls.md)

Two bugs, one commit, because the second is what makes the first affordable.

`on_ble_event` / `on_alarm_event` → `app_ui_model_wake` → `panel_power` → a blocking
`i2c_master_transmit(s_dev, buf, len, 100)` runs **on the event loop, inside `s_lock`, on the alarm
path** (`app_ui.c:373` → `app_ui_model.c:56` → `app_ui.c:135`) **[K]**. That trips `bridge_event`'s
5 ms budget — which **asserts only under `!NDEBUG`** (`bridge_event.c:26-29`) **[K]**: it panics debug
builds and, in release, logs `ESP_LOGE` and **stalls the event loop** for every other subscriber. Not
a panic loop in the field; a silent stall on the one path that must not stall. Handlers set a flag
and `xTaskNotifyGive`; all I²C moves to `ui_task`.

The dirty-render check never fires: `app_ui.c:351` copies the panel's own I²C counters into the
compared snapshot and `app_ui_panel.c:185` memcmps the whole state **[K]**, so 1029 B goes out every
20 ms tick — ~23 ms of bus time at 400 kHz, which voids the power argument and degrades button
sampling. **Memcmp the rendered framebuffer, not the state.**

**Done when:** a host test with a stubbed 100 ms I²C write asserts every `bridge_event` handler
returns in <5 ms; `app_ui_panel_render()` returns false for an unchanged framebuffer **while
`i2c_ok` is rising**; and the alarm path is asserted to reach the panel through the task notification
rather than through the handler.

### F17.3 app_ble: reset the control lock on disconnect

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [05](../design/05-connectivity-and-provisioning.md)

`s_scanning` is cleared in exactly three places, none of them a disconnect, and `ble_push_task` drops
`PUSH_SCAN_RESULTS` when the link is down (`app_ble.c:450-452`) **[K]**. Pocket the phone mid-Wi-Fi
scan and every subsequent scan answers `BUSY` **until reboot** — during setup, which is when it
happens. Call `app_ble_ctrl_reset()` from the DISCONNECT path.

**Done when:** a host test drives scan → disconnect → reconnect → scan and asserts the second scan
is accepted, and asserts that a delivery arriving after the disconnect is dropped without leaving the
lock held.

### F17.4 app_ui: a dead OLED must not make the board unprovisionable

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [07 §7.1](../design/07-display-and-controls.md), [05 §5.6](../design/05-connectivity-and-provisioning.md)

`app_ui_init` returns `-1` before registering handlers or starting `ui_task`, while BLE is
`BLE_HS_IO_DISPLAY_ONLY` with `sm_mitm = 1` **[K]**. No display → no passkey → **no bond → a board
nobody can provision**, from a failed I²C probe. Start `ui_task` regardless
(`app_ui_panel_render` already no-ops on `!s_up`), and fall back to `BLE_HS_IO_NO_INPUT_OUTPUT`
(Just Works) when the panel is known dead — with the app told, because a silent security downgrade is
worse than a stated one.

**Done when:** a host test with a failing panel probe asserts `app_ui_init` still returns 0, `ui_task`
runs, the IO capability is `NO_INPUT_OUTPUT`, and a capability bit says so on the wire; and a test
asserts the normal path is unchanged when the panel probes fine.

### F17.5 sdkconfig: buy back the heap before anything spends it

- **blocked-by:** V6.4 · **verify:** B · **board:** **yes** · **design:** [standing-work](standing-work.md), [01 §1.4](../design/01-hardware.md)

M3 diagnosed the shortfall as a **level** problem, not growth: NimBLE costs ~90–100 KB against
§1.4's estimated 35–45 KB **[K]**. Target **≥ 8 KB recovered**, from the candidates in descending
confidence: `CONFIG_BT_NIMBLE_MAX_BONDS` (3 is a product decision — hold it), msys buffer counts and
sizes, ACL buffer count, `CONFIG_BT_NIMBLE_HS_STACK_SIZE`, the httpd `max_open_sockets`/stack pair,
and LittleFS cache sizes. Each change is measured on the board individually, not as a batch, because
a batch that nets zero teaches nothing.

**Done when:** each candidate has a measured before/after `min_free_heap` in
`docs/hardware-verified.md`, the total recovered is stated, LoRa RX + BLE advertising + a WebSocket
client still run together (the V3a criterion), and the heap-budget table above is updated with the
real headroom — **which decides whether the two conditional items in W7/W8 merge at all**.

---

## W3 — A18 · Preflight and the platform seams ⚑

- **side:** app + Kotlin · **board:** no · **days:** 7 · **blocked-by:** —

`grep -rn "adapterState|isSupported|turnOn|BluetoothAdapterState" app/lib/` → **zero hits**, and
`permission_handler` is not in `pubspec.yaml` **[K]**. So *"No bridges found — check that it is
powered on"* is the app's answer to Bluetooth-off, permission-denied and adapter-unsupported alike
(`wizard.dart:262-265` catches everything with `on Object { }`).

> **Scoping note, stated once and referenced everywhere: iOS is out of scope for v1.0.** There is no
> `app/ios/` directory and `pubspec.yaml:1` says Android-only **[K]**. That is a defensible decision
> and this document adopts it — but the mechanisms below are Android-*shaped*, and a later iOS port
> is a **redesign, not a port**: `FlutterBluePlus.turnOn()` is Android-only; the `ACTION_*`
> system-settings intents have no iOS equivalent (iOS can open only the app's own pane); the
> app-initiated bond with an app-owned passkey countdown cannot exist on iOS at all (there is no
> `createBond`, the sheet is OS-driven off the first encrypted read, and it can be neither timed nor
> cancelled); the *"remove this bond in Bluetooth settings"* recovery is impossible; the hosted-AP
> join needs `NEHotspotConfiguration` plus a paid entitlement instead of
> `WifiNetworkSpecifier` + `bindProcessToNetwork`; and the foreground service has no counterpart.
> Six redesigns, listed here so nobody costs the port as a week.

### A18.1 data/transport: adapter state on `BleGattClient`

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.2.0](../design/13-ux-architecture.md)

Extend the existing seam rather than reaching for the plugin from a widget: `Stream<BleAdapterState>
get adapterStates`, `BleAdapterState get adapterStateNow`, `Future<void> requestEnable()`. The stream
is subscribed for the **whole** setup lifetime, not just preflight — Bluetooth switched off at hop 3
is the same screen with a `resumeAt`, and today that case is an unbreakable loop (`WizardLinkLost` →
Reconnect → `BleConnectionLostException` → `WizardLinkLost`, never once mentioning Bluetooth) **[K]**.

**Done when:** the fake client drives all five adapter states through the seam, the `flutter_blue_plus`
implementation is not referenced outside `ble_gatt_fbp.dart`, `requestEnable()` on an unsupported
adapter is a typed refusal rather than a throw, and no test touches a platform channel.

### A18.2 platform: the `SystemSettings` channel

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.2.0](../design/13-ux-architecture.md)

One MethodChannel with the same shape as the existing `platform/network_binder.dart` precedent:
`openBluetoothSettings`, `openAppSettings`, `openWifiSettings`, `openLocationSettings`,
`openNotificationSettings`. Add `permission_handler` and `connectivity_plus` to `pubspec.yaml` —
the plugin's implicit prompting is unusable on rails because it cannot distinguish first-denial from
permanent-denial, and Android stops showing the dialog after two refusals, forever.

**Done when:** each method is asserted against a fake channel, a missing-activity failure is typed
rather than thrown, and the Kotlin side is exercised by an instrumentation-free unit test of the
handler's dispatch table.

### A18.3 features/setup: the preflight gate, five states

- **blocked-by:** A18.1, A18.2 · **verify:** H · **board:** no · **design:** [13 §13.2.0](../design/13-ux-architecture.md)

`SetupPreflight.run()` evaluates in order and stops at the first failure: unsupported → location
services (SDK ≤ 32) → **primer** → scan/connect permission → adapter on. The primer is not optional
and is not a check — it is the screen that buys the OS prompt its one chance.

**`SetupBluetoothUnsupported` is a terminal state, not an action.** *"Use Wi-Fi instead"* is a dead
end and must not be offered as a primary: a factory-fresh bridge hosts `SmokeBridge-XXXX` with a
random 10-character PSK **readable only on the OLED** **[K]**, so a phone with no BLE cannot learn the
SSID, the PSK, or an address except by walking to the bridge and reading the glass. The honest
screen says exactly that — *"Read the network name and password from the bridge's screen, then join
that network and come back"* — and if the glass is also dead, the state is terminal and says so.

**Done when:** each of the five states renders a distinct screen with exactly one primary action
(R1) and a named secondary; *"No bridges found"* is unreachable unless a scan genuinely ran;
permanent-denial is distinguished from first-denial and routes to app settings; and the unsupported
state is asserted to carry either the read-the-glass instruction or a terminal explanation, never a
button that leads nowhere.

### A18.4 platform: acquire the multicast lock, or mDNS finds nothing forever

- **blocked-by:** A18.2 · **verify:** H · **board:** no · **design:** [05 §5.5](../design/05-connectivity-and-provisioning.md), [08 §8.4](../design/08-flutter-app.md)

`AndroidManifest.xml:10` declares `CHANGE_WIFI_MULTICAST_STATE` with a comment explaining exactly why
— *"Without this, mDNS silently finds nothing"* — and **nothing in `MainActivity.kt` or
`NetworkBinder.kt` calls `WifiManager.createMulticastLock`** **[K]**. The mDNS lane A7.4 built has
therefore never worked on the phones where multicast is filtered at the driver, and A20.5's lane
table would report *"mDNS — nothing found"* forever without ever being wrong on screen.

Acquire a reference-counted lock around discovery on the Kotlin side, release it when the last browse
stops, and set it non-reference-counted-safe against an activity death. **A held multicast lock is a
battery cost**, so it is scoped to the browse and asserted released.

**Done when:** a unit test of the Kotlin dispatch asserts acquire-on-first-browse and
release-on-last-stop with nesting, a leaked lock fails the test, and the Dart discovery adapter is
asserted to stop the browse on `dispose()` even when the resolve is in flight.

### A18.5 platform: give the network binding a lifetime that survives the activity

- **blocked-by:** A18.2 · **verify:** H · **board:** no · **design:** [05 §5.8.1](../design/05-connectivity-and-provisioning.md)

**Hoisting the Dart binder into `AppEnv` does not buy process lifetime and the plan must stop saying
it does.** `MainActivity.kt:16` constructs the Kotlin `NetworkBinder` per `configureFlutterEngine`,
and `:21-27` calls `binder?.unbind()` **unconditionally** in `onDestroy()` **[K]**. Any activity
destroy — process recreation, task restore from the launcher, a configuration change outside the
`configChanges` list at `AndroidManifest.xml:59` — unbinds the network regardless of where the Dart
object lives.

Two honest options; **this task takes (a)**:

| | Option | Cost |
| --- | --- | --- |
| **(a)** | Move the binding into a bound `Service` with its own lifetime, and make `onDestroy` release only when the service is also going away | ~2 days of Kotlin, and the AP lane keeps working across a task restore |
| (b) | Keep it in the activity, scope the goal down to **route-independence**, and state on screen that leaving the app drops the bridge's network | ~0.5 day, and hosted mode becomes a foreground-only feature |

Whichever ships, **`ChannelNetworkBinder`'s onboarding-owned instance is deleted, not supplemented**:
its constructor calls `setMethodCallHandler` on a `const MethodChannel`
(`network_binder.dart:63-64`) **[K]**, so two instances silently clobber each other's handler and the
second one wins at random.

**Done when:** exactly one `ChannelNetworkBinder` is constructed in the whole app and a test asserts
a second construction throws rather than clobbering; the service (or the stated scope-down) is
covered by a Kotlin dispatch test; `FakeNetworkBinder.joinAp` is **asynchronous** (it is synchronous
today, `network_binder.dart:191-198`, which is why the microtask-ordering defect was invisible to the
suite); and a regression test drives the real ordering — `success` before `onBound` — and fails
against today's code.

---

## W4 — A19 · Design system

- **side:** app · **board:** no · **days:** 8 · **blocked-by:** A1.2

The port of [14](../design/14-design-system.md) into `app/lib/design/` and `app/lib/ui/`. Nothing
here has behaviour; everything here is a `StatelessWidget` over values, so every task closes with a
standalone golden in dark at 1.0× and 1.3× text scale.

> **Precedence, recorded because it is currently written nowhere:** where `docs/ui/` and
> `docs/design/` conflict, **`docs/design/` wins**. `docs/ui/` is untracked, **three** of its screens
> are empty headings (history `index.html:696`, alarms `:704`, settings `:712`; presets `:679` has
> real content) **[K]**, and its wizard renders 2 of 5 steps. It is a mood board with real tokens in
> it. Write this line into `docs/ui/README.md` as part of A19.1.

### A19.1 design: tokens — surfaces, geometry, elevation, motion

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [14 §14.2, §14.3](../design/14-design-system.md)

`SmokeTokens` as a `ThemeExtension`: the twelve surface and ink values, four radii, the seven-step
spacing scale, `shadowCard`, `glow`/`glowTight`, and the five named durations. No widget reads a
`Duration` literal — everything goes through `SmokeMotion.of(context)`, which honours
`MediaQuery.disableAnimations`. `#1E2638` is **`bg-card-hover`** in
[14 §14.2](../design/14-design-system.md) and is named `cardRaised` here; the mapping is written in
the doc comment so the two documents can be diffed.

**Done when:** every token has a test asserting its value, `SmokeMotion` collapses `quick`/`standard`/
`value`/`gauge` to zero and degrades `pulse` to opacity-only under `disableAnimations`, and no file
outside `design/` contains a hex literal or a `Duration(milliseconds:)`.

### A19.2 design: typography and the three font assets

- **blocked-by:** A19.1 · **verify:** H · **board:** no · **design:** [14 §14.4](../design/14-design-system.md)

The fourteen named styles, bundled as **assets** — no `google_fonts`, no network — so the app renders
identically offline and in goldens. Archivo at `wdth 112` for hero numerals (the probe tile is
width-constrained, not height-constrained), Inter for prose, JetBrains Mono for keys and addresses.
`SmokeTheme` maps the Material roles onto them so unmigrated widgets inherit correctly during the
port. **Never `FittedBox(scaleDown)` a temperature** — today `probe_tile.dart:54,166` does **[K]**, so
a hero number changes size between frames when a probe reads four digits.

**Done when:** the three families load from `assets/` in a golden with no network, every style is
asserted by name, a four-digit temperature is asserted not to change the widget's height, and a test
fails if any widget outside `design/` names a font family.

### A19.3 design: retune the series palette and re-run the validator

- **blocked-by:** A19.1 · **verify:** H · **board:** no · **design:** [14 §14.5](../design/14-design-system.md), [08 §8.7](../design/08-flutter-app.md)

A10.2's palette was validated against `#0D0F12`; the new background is `#07090E`, and `#008300` on it
is unreadable as a 2 dp stroke at ten feet. Retune the four slots, **re-run
`app/test/app/palette_test.dart`'s existing CVD / adjacent-ΔE / contrast validator, and paste the new
measured table into the doc comment beside the values** — the discipline A10.2 established and the
reason that table is trustworthy. If any adjacent pair drops below the current 26.0 dark floor,
permute within the four families before changing a family.

**Hue follows the jack, not the role** — re-roling mid-cook must not repaint the history behind it,
and the OLED can only name a probe by number. This contradicts [14 §14.5](../design/14-design-system.md)'s
role-keyed table; **the jack wins**, and the reason is recorded in `series_palette.dart`.

**Done when:** the validator is green with the new hues, the measured numbers are in the source next
to the values, probe → colour and probe → stroke are asserted stable under re-roling and under a
probe detaching, and `app/lib/app/palette.dart` is a one-release re-export so `probe_tile.dart`,
`cook_chart.dart` and `palette_test.dart` keep compiling.

### A19.4 design: the status palette and the separation rule

- **blocked-by:** A19.3 · **verify:** H · **board:** no · **design:** [14 §14.5](../design/14-design-system.md)

`StatusPalette` replaces `AlarmPalette` (`palette.dart:162-178`), keeping `of(AlarmSeverity)` and
`iconOf(AlarmSeverity)` so call sites migrate by import change. The rule goes in the doc comment
because it is what keeps the two palettes from colliding: **a series hue may only be drawn as a
mark** (a stroke, an arc, a 10 dp dot, a card's left rule — never a fill larger than 12 dp, never
carrying a word); **a status hue may only be drawn as chrome** (a filled pill or banner at 12–16%
with a 30–35% border, always containing an icon **and** a word).

**Target reached is not a colour — it is a closed ring** (the gauge sweeps to 360°, thickens, goes
solid in the probe's own hue, and the centre glyph cross-fades to a check). That removes the
three-way collision between slot-3 green, transport-healthy emerald and "success", and buys the app
its one memorable moment in the same decision.

**Done when:** a test asserts no status role resolves to a series hue within 15° and no series hue is
used as a fill above 12 dp anywhere in `ui/`, the severity mapping round-trips, and the ring-closes
transition is golden-tested at 0%, 99% and reached.

### A19.5 ui: the surface and state components

- **blocked-by:** A19.1, A19.4 · **verify:** H · **board:** no · **design:** [14 §14.6](../design/14-design-system.md)

`SmokeCard`, `SmokeSheet` (`.action` / `.flow` / `.detail`), `EmptyState`, `ProblemState`,
`CapabilityNotice`, `StaleVeil`, `CostSheet`, `MonoWell`, `SegmentedChips<T>`, `PrimaryAction`,
`ActionRow`, `StatRow`. Two carry weight beyond layout: **every `flow` sheet takes `inFlight`,
disables its primary and swallows back while true** — the app-wide fix for the double-tap class
(`onboarding_screens.dart:149,270,469-479`) **[K]** — and **`StaleVeil`** desaturates its children,
drops opacity, and pins an advisory, which is the single most important safety component in the app
and does not exist in any form today.

**Done when:** every component has a standalone golden in dark at 1.0× and 1.3×, `EmptyState` and
`ProblemState` are asserted to be impossible to construct without an action, `SmokeSheet.flow`'s
`inFlight` is asserted to swallow a back gesture, and `PrimaryAction` is asserted to be the only
ember-filled button in the library.

### A19.6 ui: the probe and chrome components

- **blocked-by:** A19.5, A19.3 · **verify:** H · **board:** no · **design:** [14 §14.6](../design/14-design-system.md)

`ProbeHeroCard`, `ProbeCompactCard`, `ProbeStripRow`, `TargetGauge` (band mode and sweep mode),
`AnimatedTemp` (which **rounds during the tween** so digits never show intermediate garbage),
`TargetPill`, `TrendChip`, `InsightBanner`, `TransportChip` + `PulseDot`, `AlarmBar`. Two rules that
are content, not styling: **`view.alarm!.rule` must never reach a user** — `probe_tile.dart:113-115`
prints `pit_out_of_band` today **[K]**, and the fix is to move `alarmTitle()` out of
`domain/alarms/notification_policy.dart:136-147` into `core/format.dart` and call it from all three
sites — and **`AlarmBar` renders device-scope alarms** (`probe == 0`), which are filtered out at
`dashboard_snapshot.dart:244` and rendered nowhere today **[K]**.

**The pulse dot stopping is the staleness signal**: it animates only while live, and goes hollow with
the age appended to the label otherwise.

**Done when:** every component is golden-tested attached / detached / no-target / target-reached /
alarm-raised; the detached form contains no digit at all; `TargetGauge` renders nothing rather than
an empty ring when it has neither target nor band; and a test asserts no rendered subtree anywhere
contains an underscore-cased rule identifier.

### A19.7 android: launch identity

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [14 §14.2](../design/14-design-system.md)

`launch_background.xml` becomes ember-on-obsidian with a `values-night` twin,
`AndroidManifest.xml:49` gets `android:label="Smoke Bridge"`, and a real adaptive icon replaces the
1443-byte stock Flutter `ic_launcher.png` **[K]**. **Delete `SmokeTheme.light`** (`theme.dart:40-50`,
reachable only from tests) and its `*-light.golden.txt` files, and set `theme:` as well as
`darkTheme:` so OS-light system chrome cannot leak; the light `ProbePalette` values survive as the
**export/print** palette and the doc comment says so.

**Done when:** the launch window is asserted not to flash white in either OS theme, the icon exists
at every density, and the golden suite has no light-theme files left to skip.

---

## W5 — A20 · Shell, truth model, link controller ⚑

- **side:** app · **board:** no · **days:** 9 · **blocked-by:** A19.6, A17.2

The package that makes "the app freezes and lies" structurally impossible. Everything renders from
one immutable `AppTruth`, and the three clocks are never conflated again.

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the risk is the same one A9.1
> named and it is worse here, because there are now five sources rather than four — the drift cache,
> the live stream, `GET /status`, the app-tier analysis, and *the link's own state*. The obvious
> implementation subscribes to all five in a widget and reconciles in `build()`. So the reconciliation
> is a **pure function** into one snapshot, and `truths(AppTruth) → List<Truth>` is a pure function
> tested with no widget tree — the same discipline `buildDashboard` already has and the reason it has
> never produced a wrong number.

### A20.1 app/truth: the truth model, as pure Dart

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.6.1](../design/13-ux-architecture.md)

`app/lib/app/truth/` — no Flutter imports, the rule CI already greps for. `Transport`, `LinkPhase`,
`Freshness`, `PairState`, `CookPhase`, `RecordingClaim`, `BleAvailability`; `BridgeLink`; `AppTruth`.
**`RecordingClaim` exists so that copy about "the bridge is still recording" is generated from
evidence rather than typed into a widget**: `verified` means a `/status` read inside 2 minutes with
paired + session open + storage free; `presumed` means last contact under 30 minutes and all of that
held then. The two get different sentences.

**Done when:** the model is constructed from every combination the matrix in
[13 §13.6.3](../design/13-ux-architecture.md) names, `RecordingClaim` is asserted to degrade
`verified` → `presumed` → `unknown` on the clock rather than on a flag, and the CI Flutter-import
grep covers `app/truth/`.

### A20.2 app/truth: freshness, and the first periodic ticker

- **blocked-by:** A20.1 · **verify:** H · **board:** no · **design:** [13 §13.6.1](../design/13-ux-architecture.md), [09 §9.1](../design/09-alarms-and-insights.md)

```dart
Freshness freshnessOf(Duration? age, int periodS)   // live ≤1.5p · aging ≤3p · stale ≤20p · frozen
```

The `frozen` boundary is pinned to the firmware's `base_lost_s = 600` (`alarm_cfg.c:46`) **[K]** **so
the phone and the bridge cross the same line at the same second**. Correspondingly the 60 s OLED
`base_ok` threshold (`app_ui.c:265`) stops driving `s_led.base_lost` (`:488`) and becomes a pure
freshness pip on the status strip — one threshold, two screens.

A 1 s ticker in the shell recomputes freshness. **This is the first *periodic* ticker in
`app/lib/`** — two one-shot `Timer`s already exist at `ble_gatt_fbp.dart:71,113` **[K]** — and it is
why the elapsed clock can currently stop forever. R6's rendering ladder hangs off it: at `stale`,
trend, ETA, arc, stall and target-reached are **removed, not greyed**, because a derived value that
outlives its source is the failure mode this whole milestone exists to prevent.

**Done when:** `freshnessOf` is table-tested at the 45/90/600 s boundaries for `periodS ∈ {30,60}`
and at both sides of each; the ladder is asserted to remove every derived value at `stale`; the
ticker is asserted to be cancelled on dispose; and a test asserts the elapsed clock advances with no
inbound data and no rebuild.

### A20.3 app: the `LinkController` and the first Riverpod providers

- **blocked-by:** A20.2 · **verify:** H · **board:** no · **design:** [13 §13.6.5](../design/13-ux-architecture.md), [08 §8.4](../design/08-flutter-app.md)

One instance, held by `AppEnv`. Three riverpod packages are dependencies today, `ProviderScope` is
mounted at `bootstrap.dart:48`, and there are **zero providers** **[K]**; this is the first.

**Lost is freshness-driven, not socket-driven.** The firmware never pings
(`app_api_ws_pings_due` has zero production callers) and `BridgeSession` swallows `onDone` **[K]**, so
a half-open TCP connection looks healthy forever. `lastByteAt` older than `3 × samplePeriodS` →
`LinkPhase.lost`, regardless of what the socket claims; `onDone`/`onError` is a *fast path*, not the
mechanism. The ladder is `backoffDelay` (1/2/4/8/15/30) — already implemented, currently uncalled —
capped at the 8 s rung in the foreground and run in full in the background with a cook. Kicks that
short-circuit the wait: `connectivity_plus` (the `connectivityChanges` parameter exists at
`connection_manager.dart:91` and is supplied by nothing in production), `AppLifecycleState.resumed`
via a shell-scoped `WidgetsBindingObserver` (zero exist today), the BLE adapter returning, **Retry
now**, and a successful manual address.

**`controlsEnabled` has exactly one source** — `phase == connected || degraded` **and**
`freshness != frozen` — so the chip and the buttons can never disagree (today `dashboard_route.dart:137`
says `_session != null` while the chip says Wi-Fi) **[K]**.

**Done when:** the state machine is table-tested for every transition including `suspended` and
`blocked`; a half-open link is asserted to reach `lost` on the freshness rule with the socket still
open; each kick is asserted to short-circuit the ladder exactly once; a failed control write is
asserted to transition to `lost` and name itself; and `controlsEnabled` is asserted to agree with the
chip in all four hard cells.

### A20.4 app: rewrite the router

- **blocked-by:** A20.3 · **verify:** H · **board:** no · **design:** [13 §13.3.2, §13.3.4](../design/13-ux-architecture.md)

`StatefulShellRoute.indexedStack` with four branches — Cook, History, Alarms, Bridge — plus `/setup`
and `/recover` above the shell. `redirect:` owns the setup gate, fed by a `refreshListenable`, which
deletes the widget-level `context.go` at `dashboard_route.dart:59-61` **and** the `SizedBox.shrink()`
blank frame at `:119` **[K]**. `context.go` is banned outside `redirect` and the setup→shell
transition; every in-branch navigation is `context.push`. `/history/:id` validates `int.tryParse`
and routes to a branded `NotFoundScreen` instead of fabricating session 0 (`router.dart:55`) **[K]**.

**Two existing feature directories must be accounted for, not silently orphaned:**
`features/debug/debug.dart` folds into `/bridge/advanced` (A24.5) and `features/alarms/alarms.dart`
becomes the seed of `/alarms` (A24.1). Whichever a task does not adopt is **deleted in this task**,
with the deletion in the diff rather than left to rot.

**Back behaviour:** system back pops the branch stack; at a non-Cook branch root it goes to Cook
rather than exiting; at Cook root it confirms **only while a cook is running** (*"A cook is running.
The bridge keeps recording either way."*) and otherwise exits silently. Today `OnboardingScreen`'s
AppBar has no leading widget and the route was entered with `context.go`, so Android Back **exits the
app** mid-setup **[K]**.

**Done when:** back is asserted from every branch root and from two levels deep in each; the setup
gate is asserted to fire from `redirect` and never from a widget; a malformed `/history/:id` renders
`NotFoundScreen`; and `debug.dart` and `alarms.dart` are each either referenced by a route or absent
from the tree.

### A20.5 app/shell: the chrome — status bar, banner stack, connection sheet

- **blocked-by:** A20.4, A19.6 · **verify:** H · **board:** no · **design:** [13 §13.5.7](../design/13-ux-architecture.md)

`SystemStatusBar` (transport chip + pulse dot; RSSI, battery and LoRa dBm on the right, each
**absent** when unknown rather than `0%`), `TruthBannerStack` (max 2, priority ordered, overflow
collapses to `+N`), and `ConnectionSheet`.

**`truths(AppTruth) → List<Truth>` is a pure function in `app/truth/truths.dart`, unit-tested with no
widget tree.** Banner 11 — *"Alerts are off — you won't be woken"* — is load-bearing: a cook running
with notifications denied, battery optimisation on, or monitoring off is a 14-hour silent failure,
and the user must learn before the cook rather than after.

**The lane table is the highest support value per unit of work in this milestone** and costs one
field on `ConnectionOutcome`: *"Saved address 192.168.1.42 — no answer (2.1 s)"* · *"mDNS — nothing
found"* · *"smokebridge.local — could not resolve"* · *"192.168.4.1 — no answer"* · *"Bluetooth — not
in range"*. It is honest only because A18.4 made the mDNS row capable of a different answer.

**Done when:** `truths()` is table-tested for ordering and for the max-2 collapse with no widget
tree; the sheet renders the three clocks with three different words; the lane table renders every
`LaneOutcome` including a lane that was never attempted; **Enter address** is asserted to route
through the never-called `AppConnection.enterManual` and to pre-empt an in-flight race; and every
`link.*` banner is asserted to open the sheet.

### A20.6 app: connection-manager hygiene

- **blocked-by:** A20.3 · **verify:** H · **board:** no · **design:** [08 §8.4](../design/08-flutter-app.md), [13 §13.6.4](../design/13-ux-architecture.md)

Four defects that only appear once the app reconnects for real. The HTTP fan-out caps at **6 s** and
the BLE lane gets its own **12 s budget measured from BLE start** (today it inherits the tail of an
8 s race the 5 s dio `connectTimeout` has already eaten) **[K]**. A late BLE transport is **disposed
in `_tryBle`'s continuation** rather than orphaned. `ConnectionManager.cancel()` completes the winner
with `Offline()` and cancels the lane futures, called from `dispose()`. And the discovery owner
becomes shell-scoped: `AppEnv.newConnection()` mints one per route today, so overlapping browses
overwrite `_discovery`'s single field and navigating dashboard↔settings tears down the *new* race's
native discovery **[K]**.

If BLE wins and HTTP later becomes reachable, the app **upgrades silently** — the chip animates, one
toast says *"Back on Wi-Fi — catching up"*, sync runs, history back-fills, and **no screen reloads**.

**Done when:** each budget is asserted independently; a late BLE win after an HTTP win is asserted to
dispose its transport; `cancel()` is asserted to leave no pending lane; two overlapping races are
asserted not to tear down each other's discovery; and the silent upgrade is asserted to preserve
scroll position and viewport.

### A20.7 app: `CookMonitor`, the foreground service, and the Android 12+ start restriction

- **blocked-by:** A20.3 · **verify:** H · **board:** no · **design:** [13 §13.6.6](../design/13-ux-architecture.md), [09 §9.5](../design/09-alarms-and-insights.md)

`CookMonitor` is complete, host-tested, and has **zero construction sites in `lib/`** **[K]**. It is
constructed once, in `AppEnv`, beside the link controller — not in a route's `initState`, because
routes dispose.

**And then the case the plan missed.** Cooks start **on the device** at ≥ 90 °F
(`cook_lifecycle.h:18`) **[K]**, from the OLED, or from a second phone. If the app is backgrounded
when that `session{action:"started"}` frame arrives, `startForegroundService` throws
`ForegroundServiceStartNotAllowedException` on Android 12+, and
`FOREGROUND_SERVICE_CONNECTED_DEVICE` (`AndroidManifest.xml:38`) **is not an exemption** **[K]**.
The policy, specified rather than discovered:

| Situation | Behaviour |
| --- | --- |
| Session starts while the app is **foreground** | FGS starts normally; ongoing notification at 30 s |
| Session starts while **backgrounded** | **Do not call `startForegroundService`.** Post a normal high-priority notification — *"Backyard smoker started a cook — open to monitor"* — which a background app may do, and set `pendingFgsStart` |
| Next `AppLifecycleState.resumed` | Start the FGS, clear the flag, and back-fill the ongoing notification's elapsed time from the device's session start, not from the FGS start |
| `POST_NOTIFICATIONS` denied | Even the fallback is silent. This is the honest limit, and it is exactly what banner 11 says on the next foreground |
| The Kotlin start throws anyway | Caught on the Kotlin side and returned as a channel **result**, never as a crash; the app renders banner 11 |

The cook itself is unaffected — **the bridge is recording either way**, and every string in this path
says so.

**Done when:** the three lifecycle cases are table-tested against a fake platform; a thrown
`ForegroundServiceStartNotAllowedException` is asserted to surface as banner 11 rather than an error
boundary; the ongoing notification is asserted to drop the ETA at `stale` and to prefix `⚠️` at
`frozen` (R6, where a false ETA does the most damage); and the critical-alarm notification is
asserted to carry both **Silence** and **Open** actions, because the one interaction a person in bed
will attempt must not require unlocking the phone.

---

## W6 — A21 · Setup rewrite, hops 1 and 3 ⚑

- **side:** app · **board:** **yes** (A21.5) · **days:** 10 · **blocked-by:** A18.3, A20.4, V6.3

`features/setup/` replaces `features/onboarding/`. ~34 states, each with a `SetupScaffold`, exactly
one `PrimaryAction`, a named secondary, and an `onExit`.

```
  HOP 1                     HOP 2 (W9)                 HOP 3
  Phone ←BLE→ Bridge        Bridge ←LoRa→ Smoke X4     Bridge ←Wi-Fi→ House
  "Find your bridge"        "Find your thermometer"    "Put it on your Wi-Fi"
  budget ~12 s              budget kListenBudgetS      budget 25–45 s
```

**Hop 0 is preflight (A18.3) and it has no hop circle.** `SetupScaffold({required int hop, …})`
takes `hop: 0`, and at hop 0 the rail renders **three unfilled circles with the connector dimmed and
no active circle** — `errorTint` recolours the active circle, and at hop 0 there is none, so at
hop 0 `errorTint` tints the **title** instead. Specified here because "recolour the active circle"
is undefined for five of the states that use the scaffold.

### A21.1 features/setup: `SetupMachine`

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.2.1](../design/13-ux-architecture.md)

A sealed `SetupState` where every arm implements `SetupActions get actions` with a non-null primary —
R2 enforced at compile time — plus `_flowGen`, `_inFlight`, `_guard()` and resume.

`restart()` is **less broken than the draft claimed and still broken**: `wizard.dart:324-334` **does**
bump `_scanGen` and **does** cancel `_connSub` **[K]**. What it lacks is a generation guard inside
`connectAndBond` (so a late bond drags the user out of the find list) and a `client.disconnect()` (so
the old link survives the restart). It also emits `WizardFind(scanning: false)`, which renders *"No
bridges found"* before any search has run. Fix those three.

`_guard()` is R3's mechanism: **no raw error text reaches a pixel**. It must also catch
`TimeoutException` explicitly — `_applyConfig` catches only `BridgeControlException` and
`BleException` (`wizard.dart:427-433`) while `applyWifiConfig` awaits with `.timeout(10 s)`
(`ble_transport.dart:538,557`) **[K]**, so a bridge that ACKs the write and never answers throws past
the unawaited `onPressed` closure into `runZonedGuarded` and replaces the app with a crash page and
twelve stack frames.

**Done when:** cancel mid-scan, mid-bond and mid-apply are each asserted to make the late completion
write nothing; double-tapping every primary is asserted to produce exactly one transport call;
`TimeoutException` lands on *"The bridge didn't answer"* rather than the error boundary; resume from
each `SetupStage` is asserted; and a widget test asserts no rendered subtree in any state contains
`Exception`, `Error`, `#0 ` or `.dart:`.

### A21.2 features/setup: hop 1 — scanning, passkey, and the fork

- **blocked-by:** A21.1 · **verify:** H · **board:** no · **design:** [13 §13.2.1](../design/13-ux-architecture.md), [ble-gatt §2.3](../../protocol/ble-gatt.md)

Rows sort by RSSI descending (`BridgeDiscovery.rssi` is parsed at `ble_transport.dart:99,116` and
rendered nowhere **[K]**); one bridge found auto-advances after 800 ms; two or more get an *"Is this
it?"* action per row driving `device_control{identify}`. `select()` is guarded — today a double tap
overwrites `_device` while the first connect is outstanding and `_connSub`/`_bondSub` stay `??=`-bound
to the first device, reporting the wrong device's state forever **[K]**.

**`SetupPasskey` is the highest-value screen in the app** and its job is *not* to display a code the
app knows — it is to show the user what to look for: a live vector reproduction of the bridge's
overlay, a visible **30 s** countdown rather than the plugin's silent 90 s default
(`bluetooth_device.dart:538,571`), and an **I don't see a prompt** escape that names the notification
shade. Today the 90 s silence times out into *"Pairing was declined — the code on the bridge and the
code you entered did not match"* — the user is told they mistyped a code **they were never shown**
**[K]**.

**Done when:** the scan list is asserted sorted, deduped and single-tap-safe; auto-advance is
asserted to be cancellable; the countdown is asserted visible and to land on `SetupPasskeyNotSeen` at
30 s; and `SetupBondSlotsFull` is asserted to be reached **from the advertisement blob before
connecting**, so a user is never mid-bond when told there is no room.

### A21.3 features/setup: the four bond outcomes, and the re-bond choreography

- **blocked-by:** A21.2 · **verify:** H · **board:** no · **design:** [13 §13.2.1](../design/13-ux-architecture.md)

Today **every** BLE exception funnels to *"Pairing was declined"* (`wizard.dart:306-318`) **[K]**,
including three failures for which retrying can never work.

| Cause | State | Primary |
| --- | --- | --- |
| `status != 0` on ENC_CHANGE | `SetupPasskeyWrong` | Try again — **see below** |
| `BleRebondRequiredException` | `SetupRebondNeeded` | Open Bluetooth settings, then auto-detect the bond is gone and resume |
| Bond slots full | `SetupBondSlotsFull` | Remove a phone (needs `forget_bond`, P4.5) |
| `BleStateException('…does not expose the Bridge Control Service')` | `SetupNotABridge` | Choose a different device — **no retry button on an unretryable failure** |

**"The bridge is showing a new passkey" is a five-step choreography, not a retry**, and the table cell
must not pretend otherwise. NimBLE generates a passkey only inside `BLE_GAP_EVENT_PASSKEY_ACTION`
(`app_ble.c:377-384`); after a failed `ENC_CHANGE` (`:387-395`) the link is still up but the security
procedure is over **[K]**. A new passkey requires, sequenced from the app: **(1)** terminate the
connection, **(2)** wait for the device to re-advertise (fast interval, which F18.5 re-arms),
**(3)** re-scan or reconnect to the same address, **(4)** re-initiate bonding, **(5)** await the new
`PASSKEY_SHOW`. Each step has its own failure, and the screen narrates the sequence rather than
spinning through it.

**Done when:** each of the four causes maps to its own state from its own exception type (not from a
string match); the re-bond sequence is table-tested including a failure at each of the five steps;
`SetupNotABridge` is asserted to have no retry affordance; and the rebond-needed state is asserted to
detect the bond's removal without the user returning to the app manually.

### A21.4 features/setup: hop 3 — picker, password, applying

- **blocked-by:** A21.1, V6.3 · **verify:** H · **board:** no · **design:** [13 §13.2.3](../design/13-ux-architecture.md), [05 §5.4](../design/05-connectivity-and-provisioning.md)

**The mode choice is deleted** (R4): `ModeStep` asks a first-time user to evaluate *"uses more
battery, and your phone has to be within range"* **[K]**, which they cannot. Hosted-AP appears as a
quiet tertiary link, automatically when the bridge saw zero networks, and automatically after two
consecutive Wi-Fi failures — never as an unprompted question.

Three defects the picker fixes: **enterprise** networks are disabled with *"Work and campus Wi-Fi
isn't supported"* rather than accepted and failed (`applyWifiConfig` accepts a `user` parameter that
`_applyConfig` never passes, so `user_len = 0`, the bridge tries PSK, and the user is told their
correct password is wrong) **[K]**; **hidden networks** get their own screen with an auth dropdown
(today manual entry is hard-wired to auth 3 and typing one character silently downgrades a selected
WPA3 row, because `onChanged` calls `_choose(v, 3)` on every keystroke) **[K]**; and the **password
screen** gets a reveal toggle, live length validation before Connect enables, and a prefilled,
revealed field on retry — today `ssid`/`psk`/`auth` live in `_NetworkStepState` and are disposed by
the route change, so a single typo costs a fresh 12 s scan and a full retype **[K]**. **Hold them on
`SetupMachine`, not in widget state.**

`SetupApplying` narrates four phases with a **Cancel** (`HandoffStep` today is one line of text and
no actions at all **[K]**), and suppresses link-lost for **`kApplyGraceMs`** — V6.3's measurement,
defaulting to 5000 — because a brief BLE drop across a radio reconfigure is expected.

**Pre-warming the scan crosses a hop boundary and therefore needs a buffer.** Firing
`startWifiScan()` at hop 2's listen means `wifi_scan_result` notifications arrive while the machine
is in hop 2, and `app_ble_scan_deliver` pushes the whole list and clears `s_scanning` **immediately**
(`app_ble_ctrl.c:150-196`) **[K]**. So: the delivered list is buffered **on `SetupMachine`**, stamped
with its arrival time, **discarded and re-scanned if older than 60 s** when the picker renders, and
the `_ctrlLock` (A21.1) is **never held across the listen window** — the lock covers the request and
the delivery, not the wait.

**Done when:** every `net_fail_reason` renders its own headline, body and primary (five distinct
screens, not one); enterprise is refused in the picker; a hidden open network is joinable; the retry
field is asserted prefilled and revealed with no re-scan; the applying screen is cancellable at every
phase; the grace window is asserted to swallow a reconnect inside it and to surface one outside it;
and the pre-warmed list is asserted discarded at 61 s and reused at 59 s.

### A21.5 features/setup: hosted AP, end to end

- **blocked-by:** A21.4, A18.5, F18.1 · **verify:** B · **board:** **yes** · **design:** [05 §5.8](../design/05-connectivity-and-provisioning.md), [13 §13.2.3](../design/13-ux-architecture.md)

Four compounding blockers, all four fixed together or hosted mode stays impossible. The Kotlin side
is A18.5; the device side is F18.1. This task is the three app-side ones: **resolve `joinAp` on
`states.firstWhere((s) => s == bound)`** raced against a timeout and `onLost`/`onUnavailable`, so
"resolved means bound" — which is what the doc comment at `network_binder.dart:52-55` already claims;
make **`revertToHosting` idempotent** (already bound → skip the join, go straight to verification, so
the escape hatch stops throwing `BinderStateError` into a swallowed `false`); and **take the SSID
from `net_status.ssid`**, which the app already holds live at `wizard.dart:506`, instead of guessing
it from the device name (`wizard.dart:509` yields `SmokeBridge-AA:BB:CC:DD:EE:FF` whenever the scan
response carried no name) **[K]**.

**And the credentials go on screen.** `wizard.apPsk` is stored at `wizard.dart:425` and rendered by
**no** onboarding screen **[K]**, while [05 §5.8.2](../design/05-connectivity-and-provisioning.md)
says plainly to always keep the manual path because OEM behaviour varies. `SetupHostedJoinRefused` is
its own state showing the same credentials — **never** the STA recovery copy about guest networks.

**Done when:** the join is proven on the board from a factory-reset bridge, including the refusal
path and the manual path; the SSID is asserted to come from `net_status` with the device-name guess
as a last resort; `revertToHosting` is asserted idempotent; the PSK is on screen and copyable; and the
outcome is recorded in `docs/hardware-verified.md` with the phone's OEM and Android version.

### A21.6 features/setup: add this phone

- **blocked-by:** A21.2 · **verify:** H · **board:** no · **design:** [13 §13.2.1](../design/13-ux-architecture.md)

The household case: a bridge advertising `bonds > 0`, `bonds_full == 0`, paired, network up gets the
row **"Already set up — add this phone"** and runs hop 1 only. A second phone must never be walked
through Wi-Fi provisioning for a bridge that is already on the network.

**And it must not finish with a null address.** `lastBaseUrl` is written only on an HTTP 200 from
`_verifyOverHttp`, and this flow makes no HTTP request — so without a fix the second phone's very
next launch races with **no cached-IP lane**, which is the lane-starvation this whole milestone
opened with. **Decision: the flow reads `net_status` for the address and performs one HTTP verify
before `SetupDone`**, writing `recordConnection(url, bridgeId:)` on success. If the verify fails —
the phone is on cellular, or a guest network — the flow **still completes**, records `lastBridgeId`
and `lastBleDeviceId`, and says on screen that this phone will start on Bluetooth until it is on the
same Wi-Fi.

**Done when:** the fork is asserted from the advertisement blob alone; the happy path writes both the
id and the URL; the verify-failed path is asserted to complete with the BLE-lane explanation rather
than an error; and the whole flow is asserted under 20 s against the fake.

### A21.7 features/setup: landing, escape, resume, re-entry

- **blocked-by:** A21.3, A21.4, A17.3 · **verify:** H · **board:** no · **design:** [13 §13.2.4](../design/13-ux-architecture.md)

`SetupNameAndUnits` (naming converts *"a gadget I configured"* into *"my smoker"*, and **units are
asked once, here**), `SetupDone` with the three-row summary, and a skipped hop rendered as
*"— not set up · Set up now"* plus a dismissible card on the Cook tab. Every non-terminal state has a
close affordance and a `PopScope` mapping system-back to *"Leave setup?"*, confirmed only during
`SetupApplying`. Killing the app at hop 2 re-enters at hop 2.

**Done when:** each hop's skip is asserted to produce a resumable stub, a resume from each stage lands
on the right screen with the right prefilled state, back is asserted from all ~34 states, and
`SetupDone` is asserted to render an honest row for every skipped hop.

---

## W7 — F18 · Firmware: network, BLE, glass ⚑

- **side:** firmware · **board:** **yes** (F18.1, F18.5) · **days:** 10 · **blocked-by:** F17.2, V6.2

The device half of the same story. **These board rows batch with W9's into one sitting.**

### F18.1 app_net: finish the AP path, and reconcile the boot race

- **blocked-by:** V6.2 · **verify:** B · **board:** **yes** · **design:** [05 §5.8](../design/05-connectivity-and-provisioning.md)

`set_mode_internal(AP, force)` sets `s_state = AP_STARTING; start_ap()` (`app_net_core.c:273-277`)
and `app_net_core_tick` has cases for `STA_CONNECTING` and `FALLBACK_AP` and `default: break` — so
**`AP_STARTING` is stranded for the life of that boot** and `net_status` reads `idle` forever **[K]**.
`op_start_ap` (`app_net.c:53-93`) calls `esp_wifi_set_config` then `esp_wifi_set_mode(APSTA)`, and
APSTA is already the mode on a factory-fresh bridge **[K]**; whether the `set_config` re-emits
`WIFI_EVENT_AP_START` is **[?]** and is exactly what V6.2 measures. **This task's design rests on
that row** and says so in its commit message if the row was skipped.

Three fixes: an `AP_STARTING` case in `tick` with a ~5 s deadline that re-issues `start_ap` once and
then publishes `AP_UP` anyway; a tri-state `already-up` return from `op_start_ap` when
`esp_wifi_get_mode()` includes AP and the AP netif has an address, with `set_mode_internal` calling
`app_net_core_on_ap_started()` synchronously in that case; and a **one-shot reconciliation** after
`app_net_core_init` returns in `app_net_start` — the null-guards added after the boot-race panic
(`app_net_core.c:161-163` et al.) *discard* Wi-Fi events that arrive before init **[K]**, and `AP_UP`
is only ever reached from that one edge. **Keep the guards; pair every guard-dropped edge with a
reconciliation.**

**Done when:** hosted mode reaches `AP_UP` in under 2 s from a cold radio, from APSTA-with-AP-up, and
from APSTA-with-a-different-SSID; a suppressed `AP_START` recovers within 5 s; a host test drives
`set_mode_internal(AP, force)` on an already-APSTA radio and asserts `AP_UP` within one tick; and the
three timings are in `docs/hardware-verified.md`.

### F18.2 app_net: carry the disconnect reason, and stop the retry ladder

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.2.3](../design/13-ux-architecture.md), [05 §5.4](../design/05-connectivity-and-provisioning.md)

`wifi_event_handler` discards `wifi_event_sta_disconnected_t.reason` (`app_net.c:283-285`) **[K]**,
which is why six distinct failures — wrong password, SSID not found, 5 GHz-only, out of range, DHCP
timeout, MAC-filtered — all read as *"That password did not work"* on the phone. Map the ESP reason
codes onto a five-value `net_fail_reason` and carry it (P4.1 puts it on the wire). Also **stop the
retry ladder** after N consecutive `wrong_password` results (`app_net_core.c:93-102, 305-309`) and
say so on the glass: grinding 1/2/5/10-minute retries against known-bad credentials forever is not
resilience. Wire the real `retry_attempt`/`retry_in_s` — today the OLED renders them
(`app_ui_render.c:375-382`) from fields nothing ever writes (`app_ui.c:274-291`) **[K]**.

**Done when:** each ESP reason class is table-tested onto its `net_fail_reason`; the ladder is
asserted to stop after N wrong-password results and to resume on a credential change; and
`retry_attempt`/`retry_in_s` are asserted non-zero in a golden.

### F18.3 app_ui: the overlay priority stack

- **blocked-by:** F17.2 · **verify:** H · **board:** no · **design:** [07 §7.3](../design/07-display-and-controls.md), [13 §13.7.2](../design/13-ux-architecture.md)

Today any overlay clobbers any other and none is restored. Three defects make the passkey screen
unsafe and all three ship here:

1. **A >400 ms PRG hold destroys the passkey.** `app_ui_model_tick` guards the power-off confirm with
   only `if (held >= APP_UI_TAP_MAX_MS && !m->alarm_overlay)` and unconditionally writes
   `st->overlay = APP_UI_OVERLAY_CONFIRM` (`app_ui_model.c:128-140`) **[K]**. The digits are gone
   permanently, because NimBLE will not re-issue `PASSKEY_SHOW` for the same attempt. A user pressing
   PRG to see the screen better kills their own pairing.
2. **An alarm overwrites the passkey and never restores it** (`:76-83`); the 60 s expiry clears to
   `NONE`, never back **[K]**.
3. **The display sleeps out from under the code** — `app_ui_model_wake` fires once on `PASSKEY_SHOW`
   and `display_timeout_s` then applies **[K]**.

```
OTA  >  PASSKEY  >  ALARM  >  CONFIRM  >  SETUP  >  SPLASH  >  NONE
```

**Why PASSKEY outranks ALARM, stated so nobody reverts it:** the alarm does not stop being an alarm —
the `!` glyph in the status strip persists, the LED alarm pattern persists (it outranks setup in
`app_ui_led_pattern`), and the phone gets the notification. The passkey window is ≤ 60 s,
user-attended, and **unrecoverable if lost**. OTA outranks everything because its failure mode is a
brick. Add `st->overlay_prev`, restored on transient expiry, and suppress sleep while the overlay is
`PASSKEY | OTA | ALARM-unacked`.

**Done when:** ctest asserts an alarm during a passkey leaves the passkey on the glass and restores
the alarm on expiry; a PRG hold during `PASSKEY`, `OTA` or `SPLASH` arms no confirm; and the panel is
asserted not to sleep while any of the three is up, at any `display_timeout_s`.

### F18.4 app_ui: the font — descenders, the degree glyph, the PSK alphabet, the QR

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [07 §7.1](../design/07-display-and-controls.md), [05 §5.3](../design/05-connectivity-and-provisioning.md)

`app_ui_draw_char()` draws glyph rows 0..6 only (`app_ui_fb.c:97`) while the Adafruit 5×7 table
stores descenders with bit 7 set **[K]**. `k_psk_alphabet` (`app_config_store.c:332-334`)
deliberately excludes `0/O/1/l/I` but **includes `g`, `p`, `q`, `y`** — clipped, `g` and `q` differ
by **one pixel**, and clipped `y` reads as `u`, which is also in the alphabet. So the hosted-AP
password is not reliably transcribable. **Two fixes, both required:** draw 8 glyph rows into the 6×8
cell (row 7 is empty for 90 of 95 glyphs — zero cost), *and* drop the descenders from the alphabet.

Separately: the 5×7 font has **no degree glyph** and substitutes `?` (`app_ui_fb.c:88-91`) **[K]**, so
committed goldens read `163??F` and `203.1??F` — the two screens a user reads mid-cook. Add the
glyph and regenerate.

The **Wi-Fi join QR** (`WIFI:T:WPA;S:<ssid>;P:<psk>;;`, version 3, ECC L, 29×29 at 2 px = 58×58,
inside the 64 px height, already sized by [05 §5.3](../design/05-connectivity-and-provisioning.md))
alternates with the text every 4 s. **The QR is not polish while the text path is broken** — but if
the schedule compresses, the font fix ships and the QR does not.

**Done when:** a `font-descenders.fb` golden renders the full PSK alphabet legibly; no committed
golden contains `??`; the QR encodes and decodes round-trip in a host test against a reference
decoder; and the encoder is asserted to allocate nothing.

### F18.5 app_ble: two connections, advertising that comes back, CCCD, and a deadline

- **blocked-by:** F17.3 · **verify:** B · **board:** **yes** · **design:** [05](../design/05-connectivity-and-provisioning.md), [ble-gatt](../../protocol/ble-gatt.md)

Five defects that together make a two-phone household impossible:

- **Advertising does not restart after `BLE_GAP_EVENT_CONNECT`** (`app_ble.c:333-346`) **[K]** — one
  connected phone makes the bridge invisible to every other phone, with no explanation on either
  screen.
- **`s_conn_handle` is a single handle** (`app_ble.c:55`) **[K]** — replace with an array sized by
  `CONFIG_BT_NIMBLE_MAX_CONNECTIONS` (already 2, `sdkconfig.defaults:15`), fan `op_notify` across
  live handles, clear only the disconnecting one. **This is the ~1.2 KB conditional heap item; it is
  the one to keep if only one conditional survives F17.5.**
- **`BLE_GAP_EVENT_SUBSCRIBE` is unhandled** and `CONFIG_BT_NIMBLE_MAX_CCCDS=8` is configured and
  unused **[K]** — every connected central gets a `live_state` push every 30 s whether it asked or
  not, at a battery cost on both ends.
- **Nothing re-arms the fast advertising window.** `app_ble_note_activity()` (`app_ble.c:304-310`)
  **does** re-arm fast advertising and **does** restart advertising when disconnected **[K]** — the
  real defect is that its only caller is `op_identify` (`:137`), which requires a live connection,
  and that `app_ble_adv_note_fast()` sets a **one-shot** 60 s window that nothing renews while a
  setup stance is up. **`app_ble` has no timers at all**, so name the owner: **`app_ui`'s existing
  20 ms tick calls `app_ble_note_activity()` while a setup stance is active**, which costs no new
  timer and no new task.
- **No device-side pairing deadline** — a passkey can sit on the glass forever.

**Done when:** a host test asserts advertising resumes on connect and on disconnect; two simulated
connections each receive their own notifications and a disconnect clears only its own handle; a
central that never subscribes receives nothing; the fast window is asserted re-armed for as long as a
stance is up; the deadline clears the passkey and terminates; and **two real phones are connected
simultaneously on the board** with both receiving live state, recorded in
`docs/hardware-verified.md`.

### F18.6 app_ui: the LED language — three redefinitions and one collision

- **blocked-by:** F17.2 · **verify:** H · **board:** no · **design:** [07 §7.5](../design/07-display-and-controls.md)

**Most of this table already exists** at `app_ui_led.h:25-31` **[K]**: `OFF`, `ALARM`, `IDENTIFY`,
`OTA` (slow breathe), `PAIRING` (solid), `BASE_LOST` (double-blink every 2 s), `HEARTBEAT` (one 20 ms
flash per packet, off by default). So this task is mostly **redefinition**, and it must say so.

| Pattern | Status | Shape | Means |
| --- | --- | --- | --- |
| `ALARM` | unchanged | 2 Hz hard, 50% | something needs you now |
| `OTA` | unchanged | slow breathe | do not power off |
| `IDENTIFY` | unchanged | 10 Hz, 5 s | this is the one you tapped |
| `SETUP_WAIT` | **new** | solid | ready and waiting for you |
| `SETUP_LISTEN` | **new** | 2 Hz soft pulse | working on it |
| `SETUP_OK` | **new** | 3 fast blinks then off | that worked |
| `SETUP_FAIL` | **new** | 1 Hz off-heavy (10%) | that didn't work; look at the screen |
| `BASE_LOST` | **retimed** | double-blink | retimed from the 60 s freshness pip to the alarm engine's 600 s, so the LED and the app agree (A20.2) |
| `PAIRING` | **retired as an LED pattern** | — | see below |
| `HEARTBEAT` | **redefined** | ~2% breathe at 0.5 Hz | alive and healthy — so "dark" unambiguously means "off". **The existing per-packet 20 ms flash is deleted**: at a 30 s packet cadence it is indistinguishable from a fault blink at a glance |

**The collision, resolved explicitly.** `APP_UI_LED_PAIRING` is *solid* and is driven **every tick**
by `s_led.pairing = !snapshot.paired` (`app_ui.c:487`) **[K]** — it means *"not paired to the Smoke X
base"*, which is a **steady state**, not an event. A new solid `SETUP_WAIT` would be the same duty
cycle carrying a second meaning of the word "pairing". **Decision: `PAIRING` stops driving the LED
entirely and is renamed `BASE_UNPAIRED` in the enum, surviving only as a status-strip pip.** An
unpaired bridge is not an emergency and does not need a lamp; the glass says it, and W9's Cook-tab
card says it. `SETUP_WAIT` takes solid.

**Precedence** (extending `app_ui_led.c:19-21`, with OTA's position preserved):

```
ALARM > OTA > IDENTIFY > SETUP_FAIL > SETUP_OK > SETUP_LISTEN > SETUP_WAIT > HEARTBEAT > OFF
```

`led_enabled` defaults to `ALARMS_ONLY` and `app_ui_led_duty` returns 0 for every pattern except
`ALARM` and `IDENTIFY` **[K]** — so during setup, the moment a user most needs to know the bridge is
alive, the LED is dark. Add `bool setup;` to `app_ui_led_input_t`, ranked immediately below
`alarm_unacked`, and exempt it from the `ALARMS_ONLY` gate alongside `IDENTIFY`, on the same stated
grounds: **the user deliberately started this, seconds ago.**

> **D16 — `led_enabled = OFF` is refused while an alarm is unacked.** This **reverses a documented
> decision**. `app_ui_led.c:64-70` says, in a comment: *"OFF is zero in EVERY state, including alarm.
> The user asked for darkness; the API, the app and the buzzer are where an alarm still shouts."*
> That implements [07 §7.5](../design/07-display-and-controls.md) **[K]**. The reversal is justified
> **only** by the buzzer decision below, and it is recorded as a new decision in
> [00](../design/00-overview.md) rather than as a consequence — because if the piezo is ever fitted,
> D16 should be revisited, and a reader needs to find it.
>
> **The buzzer decision it rests on:** `app_ui_buzzer_on()` exists, is called from nowhere, there is
> no GPIO7 configuration, and the header concedes the piezo is unfitted on every board **[K]**.
> **v1.0 ships with no buzzer**, so the LED is the only device-side annunciator, so an unacked
> critical alarm additionally **holds the panel awake**, overriding `display_timeout_s`. Fitting the
> piezo is an open hardware question for the product owner.

**Done when:** ctest covers the precedence ladder including OTA-during-setup and alarm-during-setup;
`HEARTBEAT`'s redefinition is asserted (no per-packet flash remains); `BASE_UNPAIRED` is asserted to
drive no duty cycle; the `ALARMS_ONLY` exemption is asserted for setup and identify and for nothing
else; and D16's refusal is asserted with its stated reason returned to the caller.

### F18.7 app_ui: the WELCOME page, the state table, and four copy fixes

- **blocked-by:** F18.3 · **verify:** H · **board:** no · **design:** [07 §7.2](../design/07-display-and-controls.md), [13 §13.7.6](../design/13-ux-architecture.md)

Out of the box today the bridge shows `APP_UI_PAGE_PROBES` (`app_ui_model.c:31-32`) — four rows
reading `--`, with BLE mentioned nowhere except the STA-joined branch of the Network page, which a
factory-default AP-mode bridge never reaches **[K]**. Add `APP_UI_PAGE_WELCOME`, forced while
`ble_bonds == 0 && !paired`, auto-retiring on first bond.

**The glass must never print a wire identifier.** One table, `k_user_state[]`, mapping
`APP_NET_STATE_*`, `SMOKE_X_*` and every alarm rule onto a sentence — today the alarm overlay renders
`bridge_alarm_rule_str()` with underscores swapped for spaces, so the glass reads `pit out of band`
and `smoke x alarm`, and device-scope alarms skip the value rows entirely **[K]**. **OLED strings
move into one table** with a compile-time `_Static_assert` on the 21-column budget, not scattered
`snprintf` literals.

**Four copy fixes, because the copy currently instructs gestures the firmware does not implement**
(`app_ui_model` has exactly one action, `POWER_OFF`) **[K]**:

| Where | Current | New |
| --- | --- | --- |
| `app_ui_render.c:618-621` splash | `hold PRG for` / `AP mode  3` | `double-tap RESET` / `for setup mode` — the path that **is** implemented (`main.c:60-70`) |
| `:383-384` network | `Hold PRG to host` / `own network` | `Open the app to` / `fix Wi-Fi` |
| `:244` cook | `Hold PRG to start` | `Start a cook in` / `the app` |
| `:579` alarm | `tap PRG to silence` | `tap to dismiss` |

**The splash string is the worst copy defect in the firmware:** following its printed instruction for
3 s arms the power-off confirm at 400 ms and deep-sleeps the board on release, and
`step_recovery_window()` is still `ESP_LOGI(TAG, "PRG recovery window: stub until F11")`
(`main.c:149-153`) **[K]**. Also add the Network page's missing **fallback** branch (`app_net_get_status`
emits `"fallback"` and `fill_snapshot` only tests for `"failed"`, so a bridge that could not join
renders as a cheerful `NETWORK hosting`) **[K]**, the Radio page's `SYNC_RECEIVED` third state, and
`SmokeBridge-XXXX` on the System page — the device never displays its own identity today.

**Done when:** the `_Static_assert` fires on a 22-column string; every state in `k_user_state[]` has a
golden; no golden contains an underscore-cased identifier; the four copy strings are asserted changed;
and the fallback branch renders distinctly from hosting.

### F18.8 app_ota: publish OTA progress on the bus

- **blocked-by:** F18.3 · **verify:** H · **board:** no · **design:** [03 §3.7](../design/03-firmware-architecture.md), [07 §7.2](../design/07-display-and-controls.md)

**`BRIDGE_EVT_OTA` has no publisher.** It appears in exactly two places in the tree: the enum at
`bridge_event_types.h:30` and `test_bridge_event_guard.c:44` asserting its value is 11 **[K]**. OTA
progress reaches the WebSocket through a **direct callback** — `.progress = ota_push_progress`
(`app_api/app_api.c:341`, defined `:636`) **[K]**. So "register `app_ui` for `BRIDGE_EVT_OTA`"
subscribes to silence, and the already-written, already-golden-tested OTA overlay
(`app_ui_render.c:627-640`) can never appear. A firmware update mid-cook shows **nothing** on the
glass, and *do not power off* is the one warning that must reach the person standing next to it.

**The fix is a new publisher, not a new subscriber**, and it is cheap: `ota_push_progress` becomes a
**fan-out of two** — the existing WebSocket sink, plus `bridge_event_post(BRIDGE_EVT_OTA, …)` with
phase and percent. Rate-limit the bus post to one per 2% or one per second, whichever is coarser, so
a 5 ms budget cannot be threatened by a fast flash.

**Done when:** a host test asserts the WebSocket sink still receives every progress callback
unchanged; asserts the bus receives a rate-limited subset; asserts `app_ui` renders the overlay from
the bus event and that it outranks every other overlay; and asserts the whole path costs no heap.

### F18.9 app_ui/app_ble: make identify perceptible, and route the button back

- **blocked-by:** F18.6 · **verify:** H · **board:** no · **design:** [06 §6.2](../design/06-device-api.md)

`op_identify` is `app_ble_note_activity(); return 0;` (`app_ble.c:134-139`) and `identify_until_ms`
is read by `app_ui_led_pattern` and **written by nobody** **[K]** — so the *"Is this it?"* button
A21.2 renders would do nothing. Add `BRIDGE_BLE_IDENTIFY`; `app_ui` sets
`s_led.identify_until_ms = now + 5000`, calls `app_ui_model_wake`, and shows a 5 s overlay with the
device name in 12×24. Add `POST /api/v1/identify` (P4.6 documents it).

Also post `BRIDGE_EVT_BUTTON{tap}` from `app_ui` and have `app_ble` call `app_ble_note_activity()` on
it — walking up and pressing the button is the most discoverable recovery action on a one-button
device and is currently wired to nothing.

**Done when:** ctest asserts identify lights the LED at 10 Hz for 5 s, wakes the panel, and shows the
name; asserts a PRG tap re-arms fast advertising; and asserts identify's overlay yields to PASSKEY and
OTA.

---

## W8 — P4 · T6 · The coordinated protocol bump

- **side:** both · **board:** no · **days:** 8 · **blocked-by:** F18.5, A20.3 · **OWNER: TBD — assign before this wave**

**One coordinated bump, one regeneration, one owner.** Everything below lands in a single commit that
moves `device_info.api` from 1 to 2, regenerates all four codegen outputs (`protocol/gen/record_gen.h`,
`protocol/gen/records.g.dart`, `tools/bridge_protocol/lib/records.g.dart`,
`app/lib/data/dto/records.g.dart`), and updates `openapi.yaml` and `ble-gatt.md` in the same diff. CI
already fails on a codegen diff.

**Storage record layouts do not change.** `meta.version: 1` is mirrored in `session_header.version`
and governs on-flash files; nothing here touches a storage record, so stored cooks stay readable.

### P4.1 protocol: `records.yaml` v2, and one regeneration

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.8.1, §13.8.3](../design/13-ux-architecture.md), [ble-gatt](../../protocol/ble-gatt.md)

`device_info` 40 → 44 B with a `u32 feat` bitfield (**absent — a read shorter than 44 B — means all
zero**, the same rule that makes this additive); `live_state.flags` b5 `base_lost` and b6
`alarm_critical`; `live_state` trailing `u8 sample_age_s` (255 = ≥255 or never); `net_status`
trailing `u8 reason`; `control_op` **14 `set_setup_stance`** (`u8 hop`, `u8 substate`, 4 B inside the
frozen 30 B envelope, auto-expiring at 120 s) and **15 `forget_bond`**; the advertising status blob's
b5 `bonds_full` and b6 `fallback_ap`; and a leading `u8 probe` on the `mark` body (27 B of the 28 B
budget — today `op_mark` hardcodes `probe = 0` so BLE can never mark a specific probe) **[K]**.

**The stance's expiry needs a named owner and gets one:** `app_ble` receives the write but has no
timers, so **`app_ui`'s 20 ms tick owns the 120 s deadline** and clears the stance, the same owner
F18.5 gave the fast-advertising window.

Ops 14–15 follow the [ble-gatt §5.6.6](../../protocol/ble-gatt.md) additive rule: appended, never
renumbered; a v1.0 bridge answers `invalid`.

**Done when:** CI's codegen freshness check is clean across all four outputs; every new field
round-trips in both the C and the Dart harness; and the frozen envelope sizes are asserted unchanged.

### P4.2 protocol: the `pair_status` characteristic

- **blocked-by:** P4.1 · **verify:** H · **board:** no · **design:** [13 §13.8.2](../design/13-ux-architecture.md)

The blocker for hop 2. The app is **structurally blind** to RF pairing today: it never calls
`GET /api/v1/pairing`; `app_api_ws_pairing()` (`app_api_ws.c:194`) has **zero callers** and
`app_api.c:891-898` registers only SAMPLE/SESSION/ALARM/POWER; and **BLE has no pairing surface at
all** — which matters because hop 2 runs over BLE, before Wi-Fi exists **[K]**.

New characteristic `0x000A`, Read + Notify, encrypted, **fixed 20 B** so it fits the default ATT MTU
— the same constraint `live_state` was sized against: `ver`, `state` (`pair_state`: unpaired /
listening / heard / confirmed, 1:1 with `smoke_x_ctrl_state()`), `elapsed_s`, `remaining_s`,
`device_id[8]`, `num_probes`, `rssi`, `reason` (`pair_fail`), `garbled`, 2 B pad.

**The clock behind `elapsed_s`/`remaining_s` needs an owner, because there isn't one today:**
`smoke_x_ctrl_tick` returns immediately unless `CONFIRMED` (`smoke_x_ctrl.c:163-166`) **[K]**.
**Decision: `smoke_x_ctrl` owns a `s_listen_deadline_ms`, set at `listen()` entry and evaluated at the
top of `tick` *before* the CONFIRMED early return** — which is the same one-line reordering F19.2's
watchdog needs, so the two land together. The glass reads it from the existing snapshot.

**The phone counts from a local start timestamp**, captured when the listen call returns, and
**reconciles on each notify**. Notify cadence is **on state change, plus one per 5 s while
listening** — not 1 Hz. At a 75 s budget that is ~15 notifies instead of 75, the count on screen is
smooth because it is local, and the reconciliation keeps it honest. A 1 Hz notify would cost five
times the radio wake-ups for a number the phone can compute itself.

**Done when:** the layout round-trips in both harnesses at exactly 20 B; the notify cadence is
asserted (state change + 5 s, never 1 Hz); the deadline is asserted to expire from `tick` in the
`UNPAIRED` and `LISTENING` states; and a v1.0 app that does not know the characteristic is asserted
unaffected.

### P4.3 protocol: size tolerance for the fixed records, in both directions

- **blocked-by:** P4.1 · **verify:** H · **board:** no · **design:** [ble-gatt §5.1](../../protocol/ble-gatt.md)

**`live_state` is a FIXED-size record by contract.** `records.yaml:279-282` states that
`device_info`, `wifi_scan_ctrl` and `live_state` are fixed-size, with `live_state` at 16 B ≤ 20 B
**so it survives a failed MTU negotiation (R7)** **[K]**. Growing it to 17 B is **not** covered by the
trailing-bytes rule that covers the variable-length records, and the draft treated it as if it were.

Specify tolerance explicitly, both ways, the same way `device_info`'s short-read `feat = 0` rule
works:

| Reader | Sees | Rule |
| --- | --- | --- |
| v1.0 app | 17 B | accept any length ≥ 16; parse the first 16 B; ignore the tail |
| v2 app | 16 B | accept; default `sample_age_s = 255` (unknown) and treat flags b5/b6 as 0 |
| either | < 16 B | reject — a short fixed record is a corrupt one, not an old one |
| v1.0 app | `device_info` 44 B | accept ≥ 40; `feat` absent means all zero |

`bridge_live_state_unpack` and its Dart twin both gain the range check, and 17 B still fits the
20 B MTU floor.

**Done when:** four host tests — one per row — pass in both the C and the Dart harness; the 20 B MTU
constraint is asserted by a compile-time check; and `records.yaml`'s fixed-size note is amended to
state the tolerance rather than leaving it to the reader.

### P4.4 protocol: give `wifi_config` its own echo — including the rejection paths

- **blocked-by:** P4.1 · **verify:** H · **board:** no · **design:** [ble-gatt §5.9](../../protocol/ble-gatt.md)

`startWifiScan` and `applyWifiConfig` both correlate on `firstWhere((r) => r.opEcho == 0)`
(`ble_transport.dart:503,541`) because `op_echo` is 0 for **both** `wifi_scan_ctrl` and `wifi_config`
**[K]** — so one result frame satisfies both awaits and the wrong future completes.

**`result.op_echo = 0xF0` will not generate as specified.** `records.yaml:419` types `op_echo` as
`enum: control_op`, and `control_op` (`:96-110`) is `1..13` **[K]**; codegen emits a
`bridge_control_op_t`-typed field and the C side has no such constant. **Decision: change the field's
type to plain `u8`** and document a reserved pseudo-op range `0xF0..0xFF` in
[ble-gatt §5.9](../../protocol/ble-gatt.md), with `0xF0 = wifi_config`. Adding `0xF0` to `control_op`
would break the enum's contiguity and every generated switch over it; changing the field type costs
one doc line and no generated code.

**And the fix must cover the rejection paths, or it makes the crash worse.** Four sites answer
`op_echo = 0` on a rejected `wifi_config` today — `app_ble_ctrl.c:67` (*"malformed wifi_config"*),
`:71` (*"mode must be ap|sta"*), and the two generic ones in `app_ble_core_write` at `:384`
(*"insufficient link security"*) and `:389` (*"over-length write"*) **[K]**. An app awaiting `0xF0`
would receive **no result at all** for any of them and fall to the 10 s `TimeoutException` — the exact
crash path A21.1 is fixing. All four echo `0xF0`.

Belt and braces: `BleTransport` gains a `_ctrlLock` single-flight guard regardless, because
correlation-by-echo is only as good as the firmware answering.

**Done when:** a host test drives a scan and a config concurrently and asserts each future receives
its own frame; each of the four rejection paths is asserted to answer `0xF0` with its own detail
string; and a v1.0 bridge answering 0 is asserted to still resolve (the lock, not the echo, saves it).

### P4.5 protocol: `forget_bond` needs a stable identity, not an ordinal

- **blocked-by:** P4.1 · **verify:** H · **board:** no · **design:** [ble-gatt §5.6, §5.9](../../protocol/ble-gatt.md)

NimBLE exposes peers via `ble_store_util_bonded_peers`, whose **ordering is not stable across
reboots** and whose identity is a `ble_addr_t`, not a name — and **the bridge never learns a phone's
name** **[K]**. So `forget_bond{index}` as specified can delete the wrong phone.

The specification, concretely:

- **The read.** `result{op_echo:15}`'s 64-byte detail (`records.yaml:436`) carries a generation byte
  and up to three records: `g<gen> <idx>:<addr_type><addr_hex_tail6>:<days_since_seen>[:me]`. Three
  records fit in 64 B with room for the generation. `gen` increments on any bond-list change.
- **The label.** There is no name to show, so the app shows what is true: *"Phone ending C1D3 · last
  connected 2 days ago"*. The entry matching the **current connection's peer address** — which the
  bridge does know — is flagged `:me` and rendered *"This phone"*.
- **The delete.** The write body stays `u8 index` (the frozen envelope), but the firmware **snapshots
  the list at read time into a stable table keyed by address**, and the delete carries the generation
  it was read with. A mismatched generation answers `invalid` with *"the list changed — read it
  again"* rather than deleting an ordinal into a reshuffled array.

**Done when:** a host test asserts a delete against a stale generation is refused; asserts the
snapshot survives a reboot between read and delete only by refusing; asserts three bonds encode
inside 64 B; and asserts the `:me` flag matches the connected peer and no other.

### P4.6 protocol: the HTTP surface

- **blocked-by:** P4.1 · **verify:** H · **board:** no · **design:** [06 §6.2](../design/06-device-api.md), [13 §13.8.4](../design/13-ux-architecture.md)

| Change | Where |
| --- | --- |
| **`POST /api/v1/alarms/ack`** `{alarm_id}` → the resulting alarm state | new route → `app_alarm_ack`. Ack is WS-only today, and `HttpTransport.control` writes to `_ws?.sink` **un-awaited**, so a null socket silently discards a 3 a.m. silence **[K]** |
| `/live` emits `name`/`role`/`target_f10` for **all four** probes regardless of `attached`; adds top-level `sample_age_s`; renames the emitted `alarm_enabled` to `base_alarm_active` | `app_api_core.c:512-547`. Identity is configuration, not telemetry — and the app currently round-trips the base's *firing* flag back as config **[K]** |
| Bounded `pending_start`: a 60 s deadline, `session.pending_start` + `pending_expires_s` on `/status`, WS `session{action:"pending"\|"pending_failed"}`, and **409 `base_lost`** when unpaired or silent | `cook_store_task.c:224-238`, `app_api_sessions.c:86-98`. Today `POST /sessions` returns 200 and may open a cook hours later when someone switches the base on **[K]** |
| Split `POST /pairing/sync` from unpair; add `POST /pairing/listen?window_ms=`; `GET /pairing` returns the full state including `last_packet_s_ago` and `base_lost`; both POSTs return the pairing state **as the spec already declares and the firmware never does** | `app_api_core.c:600-626, 1268-1282` |
| `/status.net` gains `mode`, `state`, `ssid`, `reason` — closing M7's known gap 1 | `app_api_core.c` |
| WS `session` frame carries `reason` (`stopped`/`detached`/`unpaired`/`cap`), a real `renamed` action, and `continues_session_id` on the 36 h cap split | `app_api.c:557-563`. Today every non-start maps to the literal `"ended"` **[K]** |
| `PATCH /sessions/{id}` honours `probes[]` (the patch struct already supports it) plus `pull_target_f10[4]` and `plan_id`; `POST /sessions` accepts `{name, probes[]}` and returns 201 + detail | `app_api_sessions.c:86-98, 526-545` |
| `hello` carries a state snapshot (session, alarms, net, pairing, probes, last_t); `subscribe` accepts `since_t` and replays ring samples above it | `app_api_ws.c:83-103, 150-160` |
| **`POST /api/v1/identify`**; document `GET /api/v1/debug/power` (routed at `app_api_core.c:1369-1372`, absent from the spec **[K]**) | new / `openapi.yaml` |
| **`POST /ota` refuses during a setup stance or an open pairing listen** | `app_api_core.c:1435` refuses on `session_active` and on nothing else **[K]**. Add `409 setup_active`; the app, if it lands mid-setup anyway, finishes the current hop and offers the update on `SetupDone` rather than interrupting a passkey window |
| `APP_API_WS_MAX_CLIENTS` 2 → 4, and the 1013 close carries a JSON reason | **CONDITIONAL on F17.5.** If the heap does not allow it, ship at 2 with A20.5's *"another device is watching — Take over"* copy |

**Done when:** every route has a sim fixture and an `openapi.yaml` entry that matches the firmware's
actual response; the ack route is asserted to work with no WebSocket open at all; `pending_start` is
asserted bounded; and the OTA refusal is asserted for both a stance and a listen.

### P4.7 data/transport: `BridgeFeatures` gating

- **blocked-by:** P4.1, P4.3 · **verify:** H · **board:** no · **design:** [13 §13.8.1](../design/13-ux-architecture.md)

`AppEnv` reads `device_info` once per connection into a `BridgeFeatures` value; every new call site is
gated on its bit. A v1.0.0 bridge returns 40 B → `feat = 0` → the app falls back to its current
behaviour and, where a feature is load-bearing (`pair_status`), shows *"Your bridge needs a firmware
update to do this — \[Update\]"* rather than failing. Mirror `feat` as a hex string in the mDNS TXT
record and at `/status.device.feat`.

**Done when:** every gated call site is table-tested against `feat = 0` and against its own bit set;
a v1.0.0 bridge is asserted fully usable with the affordances hidden and exactly one update path
offered; and no gated feature fails with an exception when its bit is clear.

### P4.8 data: the marks read path

- **blocked-by:** P4.6 · **verify:** H · **board:** no · **design:** [04 §4.2](../design/04-storage-and-history.md), [06 §6.2](../design/06-device-api.md)

**Marks are write-only today and nothing has noticed** because nothing renders them.
`bridge_transport.dart` has `MarkCommand` (`:86-89`) and **no `marks()` method**;
`http_transport.dart:341` POSTs one; `MarkDao.replaceMarks` (`database.dart:348`) has **zero
production callers** **[K]**. A23.7 renders marks on the chart and in the timeline, so the read path
has to exist first: a `marks({int? sessionId})` method on the transport contract, a
`GET /api/v1/sessions/{id}/marks` route in `openapi.yaml` and the firmware, and `replaceMarks` wired
into the sync engine beside samples.

**BLE cannot read marks** and says so through the capability flag rather than by returning an empty
list — an empty list and "not supported" are different sentences.

**Done when:** the A6.2 transport contract harness covers `marks()` across all three implementations;
the sim serves marks for the fixture cook; a session with no marks is distinguished from a transport
that cannot fetch them; and `replaceMarks` is asserted called by the sync engine with an upsert-only
reconcile, like samples.

### T6.1 tools/sim: serve the v2 contract

- **blocked-by:** P4.6 · **verify:** S · **board:** no · **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md)

The sim is a first-class harness and the bump orphans it. `/live`'s always-present probe identity,
`sample_age_s`, `/status.net`, the session `reason`, `hello`'s snapshot, `since_t` replay, the marks
route, the REST ack, bounded `pending_start`, and `device_info.feat` — plus a **`--api=1` flag** that
serves the v1.0.0 shape, because P4.7's gating is otherwise untestable without a physical old bridge.

**Done when:** A15.4's integration run passes against both `--api=1` and `--api=2`; the feature-gated
affordances are asserted hidden under `--api=1`; and the sim's responses are diffed against
`openapi.yaml` by a test rather than by eye.

---

## W9 — F19 · A22 · T6 · Hop 2, end to end ⚑

- **side:** both · **board:** **yes** (F19.1, F19.2) · **days:** 9 · **blocked-by:** V6.1, P4.2, P4.6

**This hop does not exist in the product today.** It is the largest single gap and the most direct
cause of *"my bridge doesn't work"*. Its board rows batch with W7's.

### F19.1 smoke_x: a non-destructive bounded listen

- **blocked-by:** V6.1, P4.2 · **verify:** B · **board:** **yes** · **design:** [02 §2.5](../design/02-smoke-x-protocol.md), [13 §13.2.2](../design/13-ux-architecture.md)

`POST /pairing/sync` and BLE op 1 `pair` both call `smoke_x_ctrl_unpair()` — **byte-identical to
`unpair`** (`app_api_core.c:1269-1278`, `app_ble_ctrl.c:296-301`) — which clears NVS first thing
(`smoke_x_ctrl.c:195`) **[K]**. **A button labelled "Pair" must never be able to unpair.**
`smoke_x_ctrl_listen(uint32_t window_ms)` keeps the existing binding live until a new sync confirms
and restores it if the window expires.

**But "non-destructive" is a claim about NVS, not about the radio, and the difference is a telemetry
gap.** `app_lora_set_frequency()` sets `s_scanning = false` (`app_lora.c:46`) while
`app_lora_set_scanning(true)` starts the 915/920 alternation **[K]** — the two are mutually exclusive
with sitting on the paired base's operating frequency. **During any listen window the bridge receives
no samples from the currently-paired base.** So:

- The listen entry point **refuses with `409 session_active` while a cook is open** and, over BLE,
  answers `invalid` with the same reason.
- With no cook open it proceeds, and both surfaces say what it costs: *"The bridge stops reading your
  Smoke X while it listens — about 30 seconds."*
- A24.4's Bridge-settings row is labelled **"Re-listen for the base station — pauses readings for the
  listen window"**, not *"keeps: everything"*.
- The listen entry point must satisfy `app_lora_guard_tx_allowed(s_freq_hz)` (`app_lora.c:41-44`)
  **[K]** before the ACK, or the ACK silently fails — which is the very failure F19.2 exists to
  detect.

**Done when:** a host test asserts NVS is untouched by a listen that times out and by one that is
cancelled; asserts the previous binding is restored; asserts the TX guard is satisfied before the ACK
is attempted; asserts the session refusal on both surfaces; and the bench run pairs a real X4 without
disturbing an existing binding, recorded in `docs/hardware-verified.md`.

### F19.2 smoke_x: check the ACK, and time out `SYNC_RECEIVED`

- **blocked-by:** F19.1 · **verify:** B · **board:** **yes** · **design:** [02 §2.5](../design/02-smoke-x-protocol.md)

`SYNC_RECEIVED` is an **unbounded trap**: `(void)s_ops->transmit(s_ctx, ack);` (`smoke_x_ctrl.c:82`)
advances the state regardless of the result, `smoke_x_ctrl_tick` returns immediately unless
`CONFIRMED` (`:163-166`), the radio has been retuned off the sync channel with `s_scanning` cleared,
further beacons are counted and dropped (`:51-56`), and the OLED cheerfully says *"Scanning 915/920
MHz"* **[K]**. Permanent deadlock, broken only by "Re-scan" — which erases the pairing.

Two fixes in the same reordering P4.2 needs: **check the ACK transmit result** (a failure stays
`UNPAIRED` with the scan running and retries on the next beacon, which the **[K]** 3 s interval makes
cheap), and a **`SYNC_RECEIVED` watchdog** of one broadcast interval plus margin — V6.1's
*"interval to first state message after ACK"* — publishing `SMOKE_X_EVT_SYNC_TIMEOUT` and returning
to `UNPAIRED` with the scan restarted.

**Done when:** ctest asserts a failed ACK leaves the state `UNPAIRED` with scanning on; asserts
`SYNC_RECEIVED` times out to `UNPAIRED` and republishes; asserts the deadline is evaluated **before**
the CONFIRMED early return; and the bench run reproduces at least the timeout path against a real
base whose sync window was allowed to close.

### F19.3 smoke_x/app_alarm: gate `base_lost`, and derive `/status.pairing` from the controller

- **blocked-by:** F19.1 · **verify:** H · **board:** no · **design:** [09 §9.1](../design/09-alarms-and-insights.md)

`alarm_task` seeds `since_last_packet_s` from boot with no pairing gate (`app_alarm.c:195-198`,
`rules.c:246-247`) **[K]**, so a brand-new bridge posts *"Base station lost"* ten minutes after setup
about hardware the user has never connected. Gate the rule on
`smoke_x_ctrl_state() == SMOKE_X_CONFIRMED`. And derive `/status.pairing.paired` from the controller
rather than from NVS (`app_api_core.c:306-307`) **[K]**, so `/status` and `/pairing` cannot disagree
during a watchdog re-scan.

**Done when:** ctest asserts an unpaired bridge never raises `base_lost` at any elapsed time; asserts
the rule arms on the confirm edge; and asserts `/status` and `/pairing` agree in all four controller
states including mid-watchdog.

### F19.4 cook_store: push samples with no session open — and define the time origin

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [04 §4.1](../design/04-storage-and-history.md), [06 §6.2](../design/06-device-api.md)

`/live` and BLE `live_state` both read `cook_ring_get(0)`, and the ring is written only inside
`if (cook_session_is_open())` (`cook_store_task.c:180-191`), which requires a probe ≥ 90.0 °F
(`cook_lifecycle.h:18`) **[K]**. A cold smoker therefore reports four detached probes against a base
transmitting perfect 68 °F readings — which makes A21's payoff screen and A23's instrument mode
both empty on real hardware.

**This is not one line, and the plan must stop saying it is.** The push uses
`t = session_rel_t(s->t_rel_s)`, and `session_rel_t` (`:54-61`) reads `s_anchor_set`/`s_t_base`/
`s_uptime_base`, set in `open_session` (`:114-115`), cleared in `close_session` (`:132`), with
`cook_ring_reset()` on open (`:117`) **[K]**. **With no session there is no defined `t` origin**, and
`t` is read by four wire surfaces: `/live.t` and `/live.recent.t0` (`app_api_core.c:559-564`),
`live_state.session_t` (`records.yaml:341-345`), and the advertising blob's `minutes`
(`app_ble_adv.c:85-88`).

**Decision: with no session open, `t` is seconds since boot, and the origin is declared on the
wire.** `/live` gains `t_origin: "session"|"boot"`; `live_state.flags` spends one of its remaining
bits on the same distinction; and the advertising blob renders `minutes` as **absent** rather than
zero when the origin is boot, because *"0 minutes into a cook"* is a lie and *"no cook"* is not.
`cook_ring_reset()` on open **stays** — the pre-session samples are discarded when a real session
starts, which costs one sample period of the recent window and keeps the session's ring
unambiguous.

**Done when:** ctest asserts a cold ring serves four real temperatures with `t_origin: boot`; asserts
the origin flips on session open and the ring resets; asserts `minutes` is absent rather than 0 in
the boot origin; and the Dart-side unpackers are asserted to render elapsed time only when the origin
is `session`.

### F19.5 app_api: publish `BRIDGE_EVT_PAIRING`, and guard the destructive routes

- **blocked-by:** F19.1, P4.6 · **verify:** H · **board:** no · **design:** [06 §6.2](../design/06-device-api.md)

`app_api_ws_pairing()` has zero callers and `BridgeEvent.pairing` (`bridge_transport.dart:56`) is
constructed at `http_transport.dart:566` and consumed by nothing **[K]** — the handler was written
and never wired. Publish `BRIDGE_EVT_PAIRING` from `smoke_x` on every controller state change and
register the existing handler in `app_api_init`. Add the `409 session_active` guard on
`POST /pairing/unpair` that `openapi.yaml:535-536,556-557` already declares and the firmware has
never returned.

**Done when:** a host test asserts every controller transition produces exactly one WebSocket frame;
asserts the 409 on an open session for both unpair and listen; and asserts the app-side
`BridgeEvent.pairing` is consumed by the truth model rather than dropped.

### F19.6 smoke_x: two Smoke X bases in the room

- **blocked-by:** F19.2 · **verify:** H · **board:** no · **design:** [02 §2.5](../design/02-smoke-x-protocol.md)

`smoke_x_ctrl.c:50-88` accepts the **first decodable beacon** — no RSSI ranking, no dwell-window
collection, no confirmation — and `handle_state` then counts foreign traffic into
`s_stats.id_mismatch` (`:104-108`), exposed at `/status.radio.id_mismatch` and **read by nothing**
**[K]**. In a duplex, at a competition, or next door to another enthusiast, the bridge silently pairs
with a stranger's smoker.

Two changes, the second cheap enough that it ships even if the first is cut:

1. **Dwell before committing.** Collect candidates for one beacon interval (**[K]** 3 s) plus margin
   into a 3-entry static table with RSSI, then: one candidate → proceed as today; two or more → do
   **not** ACK, publish `SMOKE_X_EVT_MULTIPLE_FOUND` with the candidate ids and RSSIs, and let the
   app ask *"We found two Smoke X bases — which is yours?"* with the nearer one preselected. The ACK
   goes only to the chosen id.
2. **Surface `id_mismatch`.** A non-zero counter becomes *"Another Smoke X nearby is being ignored"*
   on the Radio page and in the Bridge settings — the sentence that converts an unexplained silence
   into an understood one.

**Done when:** ctest injects two beacons inside the dwell window and asserts no ACK is sent and the
event carries both candidates; asserts one beacon still pairs within the old timing; asserts the
chosen id is the only one ACKed; and `id_mismatch` renders on both surfaces. **The two-real-bases
confirmation is opportunistic** and joins [standing-work](standing-work.md) beside "borrow an X2"
rather than blocking this row.

### A22.1 features/setup: hop 2 screens

- **blocked-by:** A21.1, P4.2, V6.1 · **verify:** H · **board:** no · **design:** [13 §13.2.2](../design/13-ux-architecture.md)

`SetupBaseIntro` (the illustrated gesture from V6.1, with a real, non-punitive skip),
`SetupBaseListening` with its three sub-states driven by `pair_status`, `SetupBaseHeard` (a real
~30 s wait that must be **narrated, not spun through**), `SetupBaseConfirmed` — the payoff screen,
which renders **four actual temperatures**, not a checkmark, because this is where the product
justifies itself — and four failure branches, each with its own copy and its own primary:
`timeout_no_beacon`, `timeout_no_state`, `garbled > 3`, `ack_failed`. A skipped hop drops a
persistent resumable card on the Cook tab: *"Pair your Smoke X4 — the bridge can't read temperatures
until you do."*

**Done when:** each `pair_state` and each `pair_fail` renders its own screen; the elapsed count is
asserted to run from the local timestamp and reconcile on notify (P4.2); the confirmed screen is
asserted to render real values from `/live` or `live_state` rather than a placeholder; and the skip
is asserted to write a resumable stub and surface the card.

### A22.2 features/bridge: `BasePairingSheet` and the re-listen cost

- **blocked-by:** A22.1, A24.4 · **verify:** H · **board:** no · **design:** [13 §13.5.6](../design/13-ux-architecture.md)

The same machine, reachable after setup from `/bridge/pair-base`, plus the **cost sheet that tells
the truth about what a re-listen costs** (F19.1): readings pause for the listen window, and it is
refused outright while a cook is open. **Unpair** is a separate, harder-confirmed row that loses the
RF link and ends the running cook.

**Done when:** the sheet is asserted to refuse during an open cook with the reason on screen; the cost
sheet lists the telemetry pause; unpair is hold-to-confirm and lists what it loses; and the sheet
reuses `SetupMachine`'s hop-2 states rather than reimplementing them.

### T6.2 tools/sim: model pairing honestly

- **blocked-by:** T6.1, F19.1 · **verify:** S · **board:** no · **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md)

`tools/sim/lib/src/server.dart:177-190` models `POST /pairing/sync` as: set `syncActive`, **keep
`paired` true**, unconditionally succeed after 2 s, and push a pairing frame. The firmware does none
of those three — `app_api_core.c:1268-1275` clears NVS first, success is not guaranteed, and
`app_api_ws_pairing` has zero callers — and `GET /pairing` in the sim omits the `state` field the
firmware emits **[K]**. **Every hop-2 screen would be developed against a simulator that makes
pairing look infallible.**

The sim gains: the three real pair states plus `confirmed`; a **configurable time-to-beacon including
`never`**; an **ACK-lost path**; a garbled-signal path; the non-destructive listen semantics
(existing binding preserved on timeout); and **no pairing frame until F19.5 makes the firmware send
one**.

**Done when:** a sim scenario exists for each of the four failure branches A22.1 renders; the
happy-path timing is configurable from the scenario file; a listen that times out is asserted to
leave the sim's `paired` state exactly as it was; and A15.4's integration run drives at least two of
the adverse pairing scenarios.

---

## W10 — A23 · The cook screen and the guided cook ⚑

- **side:** app · **board:** no · **days:** 11 · **blocked-by:** A20.5, A19.6, F19.4

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** this is the only package that
> **invents** a domain model rather than projecting one, and the temptation is to make guided mode a
> second screen. It is not: guided and instrument are the same scaffold with a different readout
> organ, switched by one nullable, because you use instrument mode *mid-cook* to check the fire. A
> route change is the wrong grain for a change of organ, and two routes means two truths.

### A23.1 features/cook: `CookSnapshot` — and what happens to `DashboardSnapshot`

- **blocked-by:** A20.1 · **verify:** H · **board:** no · **design:** [13 §13.3.1](../design/13-ux-architecture.md), [08 §8.6](../design/08-flutter-app.md)

**`CookSnapshot` does not exist.** The codebase has `DashboardSnapshot` (`dashboard_snapshot.dart:74`),
`ProbeView` (`:24`) and the pure `buildDashboard` function **[K]**, and the whole
instrument↔guided architecture is described as switching on `CookSnapshot.plan` — a field on a type
nobody has written.

**Decision, stated so it is not improvised: `CookSnapshot` *renames* `DashboardSnapshot` and gains one
field, `CookPlan? plan`.** It does not wrap it — a wrapper means two objects that can disagree about
the same probe. `buildDashboard` is renamed `buildCookSnapshot`, keeps its signature plus the plan
argument, **keeps every one of its existing tests**, and stays exactly what it is: a pure function of
its inputs with no code path that can produce a temperature of 0. `ProbeView` is unchanged.
`dashboard_snapshot.dart` moves to `features/cook/` with a deprecated re-export for one release, the
same courtesy A19.3 gives the palette.

**Done when:** every existing `buildDashboard` test passes against the renamed function unmodified;
`plan == null` is asserted to produce a snapshot byte-identical to today's; the all-detached
invariant is re-asserted; and no file imports both names.

### A23.2 domain/plan: cook plans, presets, and the food-safety floor

- **blocked-by:** A23.1 · **verify:** H · **board:** no · **design:** [13 §13.5.3](../design/13-ux-architecture.md), [09 §9.4](../design/09-alarms-and-insights.md)

`domain/plan/{cook_plan,presets}.dart` — pure Dart, zero Flutter imports. A `CookPlan` carries the
cut, the doneness, per-probe targets, a pull target and a rest delta.

**The preset table is a food-safety artifact, not a preferences list**, and this task takes the
stricter of the two options: **cite the USDA/FSIS minimum in the file beside each protein, enforce a
hard floor in `CookPlan`'s constructor that a custom target cannot go below, and show the citation in
the sheet.** A poultry target below 165 °F is **refused, not warned**. **REVIEWER: TBD — assign
before this task**; a food-safety table with no named reviewer is a liability, not a feature.

**Done when:** the floor is asserted per protein including at the exact boundary; a custom target
below it is refused by the constructor rather than by the form; every preset's citation is present;
and the table has a reviewer's name in its header comment.

### A23.3 ui/probe: the two readout organs

- **blocked-by:** A19.6, A23.1 · **verify:** H · **board:** no · **design:** [13 §13.3.1](../design/13-ux-architecture.md), [14 §14.6](../design/14-design-system.md)

Instrument wears a **sparkline** (the existing `SparklinePainter`); guided wears a **`TargetGauge`**
and no sparkline. Band mode for the pit (track + tinted band sector + a current dot, going
`warning` then `critical` as the band is left and the sustain elapses); sweep mode for food (a solid
arc tweened over 800 ms plus a radial pull tick inside the ring). Neither target nor band → **not
rendered**, never an empty ring.

**Done when:** both organs are golden-tested at 0%, mid, reached, over, and with no target at all;
the band mode is asserted to change severity on the sustain rather than on the crossing; and the
gauge is asserted absent rather than empty when it has nothing to show.

### A23.4 features/cook: the cook root, its thirteen states, and the animated switch

- **blocked-by:** A23.3, A20.5 · **verify:** H · **board:** no · **design:** [13 §13.5.2](../design/13-ux-architecture.md)

The thirteen states [13 §13.5.2](../design/13-ux-architecture.md) enumerates — `connecting`,
`offline-empty`, `offline-cached`, `powered-off`, `unpaired`, `no-probes`, `instrument`, `guided`,
`ble-degraded`, `stale`/`frozen`, `alarm`, `pending-start`, `ended-remotely` — each rendering from
`AppTruth` and none of them a bare spinner (`dashboard_route.dart:120-123` is one today **[K]**).
`unpaired` says *"This bridge hasn't met your Smoke X yet"* → **Pair the base station**, **not**
*"Plug a probe into the base station"* (`dashboard_screen.dart:163`), which is wrong advice in that
branch **[K]**.

**The mode switch is animated, not a rebuild**: `AnimatedSwitcher` on the header, `AnimatedSize` +
`AnimatedSwitcher` on the probe region, and the gauge arcs sweeping in from 0 over 800 ms so
confirming a cook **visibly installs targets**. That one second is the product promise delivered.
Instrument mode is **never called "raw" in the UI** — the header says *"Live readings · Nothing is
being cooked yet — the bridge is logging anyway"*.

Pull-to-refresh on the whole scroll view → `retryNow()` + a status refresh. There is no
`RefreshIndicator` anywhere in the app today **[K]**.

**Done when:** all thirteen states have a golden; the switch is asserted to animate rather than
remount (the probe widgets keep their keys); `disableAnimations` collapses it; and the `unpaired`
state is asserted to route to hop 2 rather than to the wizard.

### A23.5 features/cook: `CookSetupSheet` and the preset library

- **blocked-by:** A23.2, A23.4 · **verify:** H · **board:** no · **design:** [13 §13.5.3](../design/13-ux-architecture.md)

Three pages in a `SmokeSheet.flow` — cut, doneness, probes — with **Skip — just watch the probes** on
page 1, which is what keeps instrument mode a first-class choice rather than a fallback. The footer
commits: `configure(probes:)` → `sessionStart` → `PATCH /sessions/{id}` with the plan.

**Presets is not a tab.** A tab you visit once per cook is wrong 95% of the time; it is a passage at
`/cook/presets`, reachable from this sheet and from `/bridge/probes`.

**Done when:** the sheet is asserted double-tap safe at every page (`inFlight`); a failed commit
leaves the sheet open with its state intact rather than dismissing; the skip path is asserted to
produce `plan == null` and close; and the three writes are asserted to happen in order with the
session id from the second feeding the third.

### A23.6 core: units, end to end

- **blocked-by:** A23.4 · **verify:** H · **board:** no · **design:** [13 §13.3.5](../design/13-ux-architecture.md)

`prefs.displayUnits` is read in **exactly one place** (`settings_route.dart:61`) and passed only to
`ProbeSettingsView`; every other widget defaults `celsius = false` and `CookChart` has no such
parameter at all **[K]**. So a °C user changes the bridge's OLED and nothing else — and
`settings_probes.dart:133-141` then renders an °F value under a `Target (°C)` label with °F bounds.

Fix it as one owned concern: units move onto `AppTruth`, are threaded from the shell to Cook /
History / Detail / Chart / Crosshair, the target editor converts and validates against converted
bounds, the CSV header states the unit, and `NotificationPolicy` takes units so the ongoing body and
the alarm text both convert.

**Storage stays tenths °F, always** — conversion is presentation-only, so a cook recorded in °F
renders in °C with no migration. **And `source_celsius` must be reconciled rather than ignored:** it
is a real `sample_rec` flag (`records.yaml:161`) **[K]**, and it records **what the base was
displaying when the sample was taken** — provenance, not storage units. Both facts go in
`core/units.dart`'s doc comment so nobody "fixes" either one.

**Done when:** one screen in each family is golden-tested in both units; the target editor is
asserted to refuse an out-of-range value in the *displayed* unit; the CSV is asserted to state its
unit in the header; `source_celsius` round-trips without affecting stored values; and a test asserts
no widget outside `core/units.dart` performs a conversion.

### A23.7 features/cook: marks, on a read path that exists

- **blocked-by:** P4.8, A23.4 · **verify:** H · **board:** no · **design:** [04 §4.2](../design/04-storage-and-history.md)

`MarkSheet` at `/cook/mark` offering the mark kinds by name and, now that the BLE body carries a
leading `u8 probe` (P4.1), letting a mark name its probe. Marks render as vertical lines on the chart
and as a timeline in the session detail — **which is only possible because P4.8 built the read path
first.**

**Done when:** a mark posts exactly one command with the right kind and probe; the chart is asserted
to render marks from the cache with no transport; a transport that cannot read marks renders the
capability notice rather than an empty timeline; and tapping a mark moves the viewport (A11.3's
behaviour, preserved).

### A23.8 data/local: drift `schemaVersion: 2`

- **blocked-by:** A23.2 · **verify:** H · **board:** no · **design:** [08 §8.5](../design/08-flutter-app.md), [04 §4.2](../design/04-storage-and-history.md)

**A guided cook cannot be cached offline today.** `database.dart:98` is `schemaVersion => 1`, the
tables are Bridges/Sessions/Samples/Marks/AlarmLog, and **Sessions has no probe columns and no plan
columns** **[K]** — so guided mode is unrenderable offline, `/history` detail's stats stay blank, and
[13 §13.5.2](../design/13-ux-architecture.md)'s `offline-cached` requirement ("full layout +
`StaleVeil`") cannot be met.

`schemaVersion: 2` with a `MigrationStrategy`: Sessions gains `planId`, `planJson`, per-probe
`name`/`role`/`targetF10`/`pullTargetF10`. Existing rows migrate with nulls and render *"needs probe
roles — this cook was recorded before names were saved"*, **not `—`**, which is the difference
between an honest gap and a bug.

**Done when:** a committed v1 database fixture is opened, migrated, and asserted to preserve every
sample and mark; a v1 session renders the honest explanation rather than blanks; a fresh install is
asserted to create v2 directly; and the migration is asserted idempotent under an interrupted upgrade.

---

## W11 — A24 · Alarms, History, Bridge ⚑

- **side:** app · **board:** no · **days:** 7 · **blocked-by:** A23.4, A20.5

### A24.1 features/alarms: three tiers, delivery first

- **blocked-by:** A20.7 · **verify:** H · **board:** no · **design:** [09 §9.1–§9.6](../design/09-alarms-and-insights.md), [13 §13.5.5](../design/13-ux-architecture.md)

**Delivery goes first because it is the thing silently broken today**: notifications blocked, battery
optimisation, quiet hours, background monitoring off — each with a fix action — plus **Send a test
alarm**, which posts through the real sink on the real channel, because that is the only way a user
verifies delivery before committing 14 hours.

Then **On the bridge**: nine rules from `GET /config/alarms` with **real** switches and their
tunables. Today this is a hardcoded 6-entry literal with `onChanged: null`
(`settings_route.dart:219-226`) **[K]** — six switches that look interactive, are always on, and
cannot move. Over BLE the section is read-only with *"Needs Wi-Fi to change"*. Then **On this
phone**: the advisory tier, wired to the `CookMonitor` that now exists (A20.7).

**Acknowledgement is not on this tab.** It is one tap on the Cook tab's `AlarmBar` and one tap on the
notification — a 3 a.m. ack must never require a tab change.

**Done when:** the three tiers render as visibly distinct sections with distinct copy; a device rule
toggle is asserted to emit exactly one `POST /config/alarms` and to revert on failure; the test alarm
is asserted to traverse the real notification path; and no control claims a capability that is not
wired.

### A24.2 data/local: `AlarmLogDao`

- **blocked-by:** A23.8 · **verify:** H · **board:** no · **design:** [09 §9.6](../design/09-alarms-and-insights.md)

The `AlarmLog` table exists at `database.dart:79-88`, is registered, and has **no DAO, no writer and
no reader** **[K]**. Add all three, fed from the WebSocket alarm frames and from `/status.alarms[]`
on reconnect, so an alarm that fired at 03:40 while the phone was face-down is still visible at 07:00.

**Done when:** an alarm raised while disconnected is asserted to appear in the log on the next
connect; acknowledging is asserted to flip the row to acked-not-cleared rather than deleting it; the
log survives a restart; and a duplicate frame is asserted idempotent.

### A24.3 features/history: watch the cache, wire the rename

- **blocked-by:** A23.8 · **verify:** H · **board:** no · **design:** [13 §13.5.4](../design/13-ux-architecture.md)

Swap the one-shot `repo.sessions()` (`sessions_route.dart:37-64`) for `watchSessions()`, which exists
at `repositories.dart:21-22` with **zero production callers** **[K]**, and add pull-to-refresh. Wire
`onRename`, which exists on the widget and is never passed (`sessions_route.dart:154-160`) **[K]**.
Five states: cache populated, sync-in-flight-with-empty-cache (*"Catching up with your bridge —
12,400 readings"*, **never** *"No cooks yet"*), offline-populated, offline-empty, and BLE.

**Done when:** the list is asserted to update from a cache write with no transport event; the
in-flight state is asserted distinct from empty; rename dispatches exactly one `PATCH` and updates
the cache optimistically with a revert on failure; and a v1-migrated session renders A23.8's honest
explanation.

### A24.4 features/bridge: the device pages and the cost sheets

- **blocked-by:** A17.3, A20.5 · **verify:** H · **board:** no · **design:** [13 §13.5.6](../design/13-ux-architecture.md)

`/bridge` with its nine sub-pages, the identity header, and **every destructive row behind a
`CostSheet` that names what is lost in nouns the user owns** — cooks, pairing, this phone's bond —
with the last two hold-to-confirm. Re-listen's cost is F19.1's telemetry pause, stated.

**Settings must borrow the shell transport** rather than building its own from `prefs.lastBaseUrl`
(`settings_route.dart:67-74`), which is why `_transport is BleTransport` (`:192`) can never be true
today **[K]**. Every sub-page renders one of three connection states — live, needs-Wi-Fi, not
connected — and **no page may render inert controls silently**, which is `settings_screen.dart:5-11`'s
own stated rule, finally applied.

**Done when:** every sub-page is asserted in all three connection states; every destructive row is
asserted to open its cost sheet before acting; the paired-phones page renders P4.5's list with its
stale-generation refusal; and a test asserts no disabled control exists anywhere without a rendered
reason.

### A24.5 features/bridge: bind Advanced, or delete it

- **blocked-by:** A24.4 · **verify:** H · **board:** no · **design:** [02 §2.7](../design/02-smoke-x-protocol.md), [06 §6.2](../design/06-device-api.md)

Advanced either binds `/debug/packets`, `/debug/novelty`, `/debug/coredump` and the app's log ring
for real, **or its four empty sections and dead Export-logs button are deleted**. An always-empty
diagnostic reads as *"the radio heard nothing"*, which is a lie. The `packets_seen` row bound to
`_status!.numProbes` (`settings_route.dart:311`) **[K]** is deleted either way. This is also where
`features/debug/debug.dart` lands or dies (A20.4).

**Done when:** each view renders the sim's fixtures verbatim including an empty one, or the section
is absent from the tree; the log ring exports through the share seam; and no section renders a
placeholder.

---

## W12 — A25 · Accessibility, copy, verification

- **side:** app · **board:** no · **days:** 5 · **blocked-by:** A24.4, A23.7

### A25.1 ui: semantics on every number

- **blocked-by:** — · **verify:** H · **board:** no · **design:** [13 §13.3.6](../design/13-ux-architecture.md)

An app whose entire job is to wake someone up and tell them one number cannot ship colour-only
status. Every temperature is announced with its unit and probe name; `TargetGauge`/`TargetArc` are
`CustomPaint` and therefore invisible to a screen reader, so they are wrapped in `Semantics(value:
'80 percent of the way to 203 degrees')` with `excludeSemantics: true` on the painter; a newly-raised
unacked alarm announces **assertively**, once, keyed by its id; every status chip and banner carries
an icon **and** a word; `textScale ≥ 1.3` drops the gauge and demotes `heroTemp` → `bigTemp`; reduced
motion collapses the durations; and every action is ≥ 48 dp including the transport chip and the ack
button.

**Done when:** a semantics-tree test asserts every temperature slot reads correctly out loud; the
assertive announcement is asserted to fire once per alarm id and not on rebuild; the 1.3× layout is
golden-tested with no overflow; and a test asserts no status is conveyed by hue alone.

### A25.2 copy: extraction and the reading-level gate

- **blocked-by:** A25.1 · **verify:** H · **board:** no · **design:** [13 §13.3.7](../design/13-ux-architecture.md)

Every user-facing string moves into one file per feature (`features/setup/copy/setup_copy.dart`,
`features/cook/copy/cook_copy.dart`, …) as `static const`. This is not ARB yet — it is the refactor
that makes ARB mechanical later, and it is what makes the gate below possible.

**Reading-level gate, target US grade 6.** Banned without a plain-language gloss: *client isolation,
association, DHCP, PMF, MAC filtering, enterprise, provisioning, handoff, transport, lane, RSSI*.
**COPY OWNER: TBD** reviews every string in W6, W9, W10 and W11 and reads it aloud before the wave
ships. **This is a merge gate**, because in an app whose failure copy *is* the product, an unreviewed
sentence is an unreviewed feature.

**Done when:** a test fails if any widget file contains a user-facing string literal; a test fails on
any banned term outside a gloss; and the copy owner's sign-off is recorded per wave in the PR
description rather than assumed.

### A25.3 test/golden: the truth-shape matrix

- **blocked-by:** A25.2 · **verify:** H · **board:** no · **design:** [08 §8.9](../design/08-flutter-app.md)

`app/test/support/shapes.dart` names six shapes today and **structurally cannot express
"unpaired"** **[K]**. Extend it into the matrix below and golden every cell that renders
differently, in the A15.1 harness's **deterministic text** form (pixel goldens are not portable and
the fix everyone applies is `skip:`).

**Done when:** every cell in §"Verification" below is committed and green, the stale cell is asserted
to contain **no** ETA/trend/arc/stall, and the frozen cell is asserted to contain the `LAST` chip and
no animating dot.

### A25.4 test: the pure-function suites

- **blocked-by:** A25.3 · **verify:** H · **board:** no · **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md)

The suites listed under §"Verification". None of them mounts a widget.

**Done when:** all seven suites are green, each runs in under a second, and none imports Flutter
outside a `testWidgets` file.

---

## Verification

### The truth-shape golden matrix (A25.3)

| Cell | Asserts |
| --- | --- |
| `sta.paired.live.cook` | the baseline; every derived value present |
| `sta.paired.stale.cook` | **ETA, trend, arc, stall absent** — not greyed (R6) |
| `sta.paired.frozen.cook` | `LAST` chips, crimson rail, no animating pulse dot |
| `sta.paired.baselost.cook` | the base-lost banner distinct from the link-lost banner |
| `sta.unpaired.nocook` | *"hasn't met your Smoke X"* + a route into hop 2 |
| `ap.paired.live.nocook` | the persistent AP chip and the no-internet sentence |
| `ble.paired.live.cook` | live temps, `Probe 1..4` names, no ETA, the chart's 2 h footer |
| `ble.unpaired` | pairing offered over BLE (ops 1/2 exist) |
| `offline.cache.cook` | `StaleVeil`, `as of 14:02`, controls disabled with a reason |
| `offline.nocache` | **a setup entry point exists** |
| `blocked.bluetoothOff` / `.permission` / `.phoneOffline` | three distinct sentences, three distinct actions |
| `lost.retrying(3)` | **the chip and the buttons agree** (H7's single source) |
| `pendingStart` | the countdown and its Cancel |
| `alarm.critical.unacked` | the bar on **every** tab, including a `probe == 0` device alarm |
| `notify.blocked.cook` | banner 11 |
| `differentBridge` | a decision sheet, never a silent swap |
| `instrument` / `guided` | the two organs, from one scaffold |
| `textScale1.3` / `celsius` | no overflow; both units |

### Pure-function suites, no widget tree

1. `truths(AppTruth)` — ordering, the max-2 collapse, and every banner's trigger.
2. `freshnessOf` — boundaries at 45/90/600 s for `periodS ∈ {30,60}`, both sides of each.
3. `SetupMachine` generation guards — cancel mid-scan / mid-bond / mid-apply, late completion writes
   nothing.
4. Double-tap every primary in every state → exactly one transport call.
5. Every `net_fail_reason` → its own state; every `pair_fail` → its own state.
6. Resume from each `SetupStage`.
7. **The microtask-ordering binder regression** — asserted against an *asynchronous*
   `FakeNetworkBinder`, and asserted to **fail** against today's synchronous one.

Plus: the drift v1→v2 migration against a committed fixture (A23.8); the marks read path across all
three transports (P4.8); the Android 12+ FGS policy's three lifecycle cases (A20.7); and the
multicast lock's acquire/release nesting (A18.4).

### Firmware ctest additions

| Suite | Asserts |
| --- | --- |
| Overlay priority | alarm during passkey → passkey survives and the alarm is restored on expiry; OTA outranks both |
| PRG suppression | a hold during `PASSKEY`/`OTA`/`SPLASH` arms no confirm |
| Setup stance | each stance renders; expiry at 120 s from `app_ui`'s tick |
| `smoke_x_ctrl` | a failed ACK stays `UNPAIRED` with scanning on; `SYNC_RECEIVED` times out; `listen()` preserves NVS; the deadline is evaluated **before** the CONFIRMED early return; two beacons in the dwell window send no ACK |
| `app_net_core` | `set_mode_internal(AP, force)` on an already-APSTA radio reaches `AP_UP` within one tick; a guard-dropped edge is reconciled |
| `app_ui_panel` | `render()` returns false on an unchanged framebuffer **while `i2c_ok` rises** |
| `bridge_event` | every handler under 5 ms with a stubbed 100 ms I²C write |
| `app_api` | a pretty-printed `probes[]` body terminates; an over-length name returns 400; `display_timeout_s` clamps |
| `app_ble` | advertising resumes on connect and disconnect; two handles notify independently; an unsubscribed central receives nothing; `0xF0` on all four rejection paths |
| LED | the precedence ladder; `HEARTBEAT`'s redefinition; `BASE_UNPAIRED` drives no duty; the `ALARMS_ONLY` exemption; D16's refusal |
| `cook_ring` | a cold ring serves real temperatures with `t_origin: boot`; `minutes` absent rather than 0 |
| Records | `live_state` at 16 B and 17 B, both directions; `device_info` at 40 B and 44 B |

### OLED golden framebuffers

One `.fb` per stance: `setup-ready`, `setup-passkey`, `setup-paired`, `setup-pair-failed`,
`setup-bonds-full`, `setup-base-listen`, `setup-base-heard`, `setup-base-ok`, `setup-base-timeout`,
`setup-wifi-pick`, `setup-wifi-joining`, `setup-wifi-ok`, `setup-wifi-failed`, `setup-ap-hosting`,
`setup-ap-qr`, `setup-complete`, `welcome`, `network-fallback`, `radio-sync-received`,
`overlay-ota-progress`, plus **`font-descenders.fb`** rendering the full PSK alphabet, plus
**regenerated** `page-cook*.fb` and `overlay-alarm-*.fb` once the degree glyph lands (F18.4) — the
committed goldens read `163??F` today.

---

## Exit gate

Nine clauses. The first eight are the product; the ninth is the one that matters.

1. **From two factory resets** — the bridge and the app's data — the three hops complete in one
   sitting without a cable, and `SetupDone` shows three green rows.
2. **Hop 2 pairs a real Smoke X4** and the payoff screen shows four real temperatures **on a cold
   smoker** (F19.4).
3. **Hosted AP completes**, including reading the PSK off the glass and rejoining, and the AP survives
   leaving the app (A18.5).
4. **Every failure branch reaches a screen with a next action** — no state renders `Exception`,
   `Error`, `#0 `, or `.dart:`.
5. **Two phones** connect simultaneously; either can ack, either can stop, and neither is silently
   swapped.
6. **The glass never contradicts the phone** — every stance in the golden list matches the app's copy
   at the same beat.
7. **`min_free_heap ≥ 80 KB`** on the 24 h soak, with the conditional items either merged and paid
   for or absent and recorded as absent.
8. **A guided cook renders offline from the cache**, plan and probe roles intact (A23.8).
9. **The acceptance test**, below.

### V7.1 bench: setup from two factory resets, all three hops

- **blocked-by:** A25.4, F19.6, A22.2 · **verify:** B · **board:** yes

Record the phone's OEM and Android version, the wall-clock time for each hop, and every deviation. An
OEM quirk becomes a named follow-up row, not a shrug.

**Done when:** clauses 1, 2, 4 and 6 are recorded in `docs/hardware-verified.md` with timings, and
anything that did not work is a row rather than an omission.

### V7.2 bench: hosted AP and the two-phone household

- **blocked-by:** V7.1 · **verify:** B · **board:** yes

Hosted mode end to end including the refusal path, the manual path, the QR, and leaving the app
mid-session. Then two phones on one cook.

**Done when:** clauses 3 and 5 are recorded, including which of A18.5's two options shipped and what
it cost.

### V7.3 bench: the 24 h soak and the heap

- **blocked-by:** V7.2 · **verify:** B · **board:** yes

The V3.2 criteria unchanged: `min_free_heap ≥ 80 KB` for the whole run, a −256 B/h leak-slope floor,
a 32 KB largest-free-block floor, and a 512 B per-task stack margin, evaluated by `tools/soak` from
`/api/v1/debug/tasks`.

**Done when:** clause 7 is recorded with the four numbers, and any conditional item that did not
merge is written down as *not shipped* rather than left ambiguous.

### V7.4 bench: the acceptance test

- **blocked-by:** V7.3 · **verify:** C · **board:** yes · real cook

> **Pull the bridge's power mid-cook, and the app must — within 90 seconds, with the phone in a
> pocket — tell the truth on the lock screen, and never, at any point, display a temperature that
> looks live.**

**Done when:** the run is recorded with a photograph of the lock screen and the elapsed time to the
notification, clauses 8 and 9 are closed, and the exact wording that appeared is committed as
evidence.

---

## What is deliberately _not_ in M8

| | Why |
| --- | --- |
| **iOS** | No `app/ios/` exists and `pubspec.yaml:1` says Android-only. Six mechanisms need **redesign, not porting** — see the W3 note. Deferred, and now costed honestly ([11 §11.2](../design/11-roadmap-and-risks.md)) |
| A true light theme | `SmokeTheme.light` is deleted and a Daylight *contrast profile* of the dark set ships instead. A second `Brightness` is a v1.1 project with its own token pass and its own golden set (~5 days), and [14](../design/14-design-system.md) ships no light tokens to start from |
| The piezo buzzer | Unfitted on every board, no GPIO7 net. D16 exists precisely because it is absent. Fitting it is one BOM line, one net and ~0.5 day of firmware — a hardware decision with a UX consequence, owed before the next board spin |
| `APP_API_WS_MAX_CLIENTS` 4 | **Conditional on F17.5** (see the heap budget). v1.0 ships at 2 with the *"another device is watching — Take over"* copy unless the heap says otherwise |
| Localization | W12 extracts every string, which makes ARB mechanical later. The OLED's 21-column budget and 5×7 font make device-side localization genuinely hard — German will not fit the current strings — so English-only for v1.0 |
| Two-base disambiguation **proven on hardware** | F19.6 ships the logic and the host tests; a second real Smoke X does not exist here. Joins [standing-work](standing-work.md) beside "borrow an X2" |
| Comparing two sessions on one chart | Route reserved at `/history/compare`, not built. Needs a second viewport and a second palette assignment; v1.1 |
| Multi-bridge picker | D12. The cache and prefs stay multi-capable; onboarding a second bridge replaces the first |
| The device-served web UI | D13. Would also be the natural home for freeing a bond slot with no phone left (see the open question below) |
| Pixel/bitmap goldens | Not portable across platform or Flutter version, and the fix everyone applies is `skip:`. The truth-shape matrix catches what actually regresses |

## Open questions for the product owner

Decisions this document cannot make. Each blocks a named task.

| # | Question | Blocks |
| --- | --- | --- |
| **Q-G** | **Feature negotiation, or a hard minimum-firmware wall?** P4.7 lets a new app talk to a v1.0.0 bridge with affordances hidden. Gating is simpler to build and worse to own. **If any bridge has shipped to a customer, negotiation is not optional** | P4.7 |
| **Q-H** | **Fit the piezo, or ship LED-only?** One BOM line, one GPIO7 net, ~0.5 day. Not fitting it means a phone-dead, out-of-range user gets a blinking LED and nothing else at 3 a.m. — and D16 stands or falls with the answer | F18.6, next board spin |
| **Q-I** | **Three bond slots, and what happens at the wall?** With `forget_bond` a user can free one *from a phone that is still paired*. A household that loses all three has only double-tap-RESET → AP mode → the QR. Acceptable, or should bonds be freeable from an AP-mode web path (which does not exist and is its own project)? | P4.5, D13 |
| **Q-J** | **Are hops 2 and 3 both skippable ship states?** A bridge with no base is a logger with nothing to log; a bridge with no Wi-Fi is BLE-only. Both are skippable by design — confirm, or name which one blocks `SetupDone` | A21.7, A22.1 |
| **Q-K** | **Who owns `protocol/`?** Four generated files, three hand-written specs, three proposals that have all edited them independently. **OWNER: TBD — assign before W8**, or the bump lands three times against three schemas | P4.1 |

**Do not relitigate D1–D16** ([§12.3](../design/12-task-planning-notes.md)) — if a decision looks
wrong, raise it as a question, don't quietly plan around it.
