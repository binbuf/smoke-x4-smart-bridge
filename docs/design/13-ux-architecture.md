# 13 — UX Architecture

The user-facing contract for the whole system: how a person sets a bridge up, what the app and the
glass say to each other while they do it, what every screen shows in every state, and what the
firmware and the protocol must provide for any of it to be true.

**Normative.** Where this document and [`docs/ui/`](../ui/) conflict, this document wins.
[`docs/ui/design-system.md`](../ui/design-system.md) is a design reference with real tokens in it;
its §2 five-step tree and its `index.html` prototype are a mood board — three of the prototype's six
screens are empty headings (`index.html:696`, `:704`, `:712`) and its wizard renders two of five
steps. The visual system it feeds is specified in [14 — Design System](14-design-system.md); this
document specifies behaviour.

**Supersedes** the UX and choreography sections of [05](05-connectivity-and-provisioning.md),
[07](07-display-and-controls.md) and [08](08-flutter-app.md). Their protocol, mechanism and
platform-trap content stands and is referenced throughout.

Confidence markers follow [02](02-smoke-x-protocol.md): **[K]** verified in code or on the bench ·
**[I]** inferred and consistent with the code · **[?]** unknown.

---

## 13.1 The core problem

Five failures, each verified in the tree at `a336597`. They are not polish items; each one ends a
user's evening.

**1 — Setup succeeds, then un-succeeds.** `OnboardingRoute._verifyOverHttp` builds its verifier with
`writeCache: (_) async {}` (`app/lib/features/onboarding/onboarding_route.dart:86`). The only two
production `recordConnection` call sites are `app/lib/app/connection.dart:134` and
`app/lib/features/settings/settings_route.dart:279`; neither is onboarding. So the moment the wizard
renders *"Reached it at http://192.168.1.57"*, `prefs.lastBaseUrl` is still null →
`neverMetABridge` (`connection.dart:104`) → the launch race runs with no cached-IP lane →
`LaunchNeedsOnboarding` → `dashboard_route.dart:60` returns the user to step 1 of the wizard they
just completed, with no message. **[K]**

**2 — Hosted-AP mode cannot complete.** Three stacked defects. (a) `set_mode_internal` sets
`s_state = APP_NET_STATE_AP_STARTING; start_ap()` (`app_net_core.c:273-277`) and
`app_net_core_tick` has cases for `STA_CONNECTING` and `FALLBACK_AP` and `default: break` —
`AP_STARTING` is stranded, so `net_status` reads `idle` and the wizard times out. (b)
`NetworkBinder.kt:80` calls `result.success(null)` before `:82` `invokeMethod("onBound")` inside one
`mainHandler.post`; the Dart continuation is a microtask and `onBound` a later event-loop task, so
`_joinAp`'s `_binder.state == BinderState.bound` check (`onboarding_route.dart:97-104`) reads
`binding` and returns false on a join that worked. The test suite cannot see this because
`FakeNetworkBinder.joinAp` sets state synchronously (`network_binder.dart:191-198`). (c) The escape
hatch from that false failure re-enters `joinAp` while already bound, throws `BinderStateError`, is
swallowed as `false`, and lands on the same screen — permanently. **[K]**

**3 — The bridge is never introduced to the thermometer.** There is no base-pairing step in the
wizard (`wizard.dart:50-144`), and `alarm_task` seeds `since_last_packet_s` from boot with no
pairing gate (`app_alarm.c:195-198`, `rules.c:246-247`). A brand-new bridge therefore posts
**"Base station lost"** ten minutes after the user finishes setup, about hardware they have not yet
connected. **[K]**

**4 — The glass and the phone contradict each other, and both freeze.** The OLED says *"enter this
code / in the app"* (`app_ui_render.c:541-543`); the app says *"type the code from the screen, not
from here"* (`onboarding_screens.dart:190-194`). Mid-cook, `HttpTransport` reports link death
honestly (`http_transport.dart:485-494`) and `BridgeSession` swallows it — `onError: (Object _) {}`
with no `onDone` (`bridge_session.dart:88-92`). `AppConnection.reconnect()` has zero production
callers and there is no periodic ticker in `app/lib/`. The result is a four-hour-old pit temperature
under a green Wi-Fi chip with a frozen cook clock. **[K]**

**5 — Every failure collapses into one of two sentences.** `startScan` catches everything with
`on Object { }` (`wizard.dart:262-265`), so Bluetooth-off, permission-denied and
adapter-unsupported all render *"No bridges found — check that it is powered on"*. `NetState.failed`
maps unconditionally to `RecoveryReason.wifiFailed` (`wizard.dart:495-500`), so SSID-not-found,
5 GHz-only, out-of-range, DHCP-timeout and MAC-filtered all render *"That password did not work"*.
The wire has nowhere to say otherwise: `wifi_event_handler` discards
`wifi_event_sta_disconnected_t.reason` (`app_net.c:283-285`). **[K]**

### 13.1.1 What the user asked for that the product cannot currently do

> *"ensure we can see temps without having to start a cook within the app if the user doesn't
> want to."*

This is **instrument mode** (§13.3.1), and it is blocked in firmware, not in the app.
`cook_ring_push` runs only inside `if (cook_session_is_open())` (`cook_store_task.c:180-191`), and a
session opens only once a probe reads ≥ 90.0 °F (`cook_lifecycle.h:18`). Both `/live` and BLE
`live_state` read `cook_ring_get(0)`. So a bridge sitting next to a cold smoker reports four
detached probes while the base station is transmitting perfect 68 °F readings every 30 s.

Fixing it is **not one line** — see §13.7.6.

---

## 13.2 The three hops

The current wizard is five steps, two of which are not steps: clock sync is a silent 40 ms write
with a screen that exists only to flash, and the hosted-vs-joined mode choice asks a first-time user
to evaluate a battery/range trade-off they have no basis to judge. And it is missing the largest
step entirely.

**The rail is three hops, named for the three radios that can physically fail.**

```
  HOP 1                      HOP 2                       HOP 3
  Phone ←BLE→ Bridge         Bridge ←LoRa→ Smoke X       Bridge ←Wi-Fi→ House
  "Find your bridge"         "Find your thermometer"     "Put it on your Wi-Fi"
  budget ~12 s               budget 20–90 s              budget 25–45 s
```

**The ordering is load-bearing.** BLE first: it is the only hop with no preconditions, and it is the
transport every later hop recovers over. **RF second, before Wi-Fi**, for three reasons — it is the
only hop that needs the user at a *second device*, and that is best done while they still think of
themselves as being in setup; it ends with a real temperature on screen, and that payoff should land
before the password chore; and `wifi_config` reconfigures the ESP32-S3 radio, so a *persisted*
pairing (`smoke_x_ctrl.c:110-123` writes NVS at CONFIRMED) survives the reconfigure where a
half-finished one may not. Wi-Fi last because it is the only genuinely optional hop, and because
hosted mode moves the phone off the house network.

**Every hop is skippable with a stated consequence** and writes `prefs.setupResumeAt`. Nothing is
ever silently incomplete, and nothing is ever mandatory that the product can work without.

Rail rendering: three circles on the phone (`SetupRail`, [14 §14.7.4](14-design-system.md)), three
bracketed digits on OLED row 0 — `SETUP    1 2[3]`.

### 13.2.0 Hop 0 — preflight

`grep -rn "adapterState|isSupported|turnOn|BluetoothAdapterState" app/lib/` returns zero hits and
`permission_handler` is not in `app/pubspec.yaml`. There is no gate at all today, which is why
failure #5 exists.

Two new seams. On `BleGattClient` (`app/lib/data/transport/ble_gatt.dart`):

```dart
Stream<BleAdapterState> get adapterStates;  // off | on | unauthorized | unsupported | unknown
BleAdapterState get adapterStateNow;
Future<void> requestEnable();               // Android: FlutterBluePlus.turnOn()
```

And `app/lib/platform/system_settings.dart`, one MethodChannel on the same shape as the existing
`platform/network_binder.dart` precedent: `openBluetoothSettings`, `openAppSettings`,
`openWifiSettings`, `openLocationSettings`, `openNotificationSettings`.

`SetupPreflight.run()` evaluates in order and stops at the first failure:

| # | Check | State | Primary | Secondary |
|---|---|---|---|---|
| 0 | adapter is supported | `SetupBluetoothUnsupported` | *(terminal — see below)* | — |
| 1 | Android SDK ≤ 32: location services on | `SetupLocationServicesOff` | Open location settings | I turned it on |
| 2 | *(a screen, not a check)* | `SetupPermissionPrimer` | Continue → triggers the OS prompt | Not now |
| 3 | `bluetoothScan`/`bluetoothConnect` granted | `SetupPermissionDenied(permanent:)` | Allow / Open app settings | — |
| 4 | adapter is on | `SetupBluetoothOff` | Turn on Bluetooth → `requestEnable()` | Open Bluetooth settings |

**The primer is not optional.** `permission_handler`'s implicit prompting cannot distinguish
first-denial from permanent-denial, and Android stops showing the dialog after two refusals,
forever. Copy:

> **Smoke Bridge needs to find nearby devices**
> Your phone uses Bluetooth to find your bridge and set it up. We never use it for location, and we
> never scan in the background.

`adapterStates` is subscribed for the **whole** setup lifetime, not just preflight. Bluetooth
switched off at hop 3 is `SetupBluetoothOff(resumeAt: SetupStage.network)` — same screen, resumes at
the recorded stage when the adapter returns. Today, adapter-off mid-flow is an unbreakable loop:
`WizardLinkLost` → "Reconnect" → `connect()` fails → `BleConnectionLostException` → `WizardLinkLost`,
never once mentioning Bluetooth.

**`SetupBluetoothUnsupported` is terminal, and the copy must say so.** A factory-fresh bridge hosts
`SmokeBridge-XXXX` with a random PSK that is readable **only on the OLED**. A phone with no BLE
cannot learn the SSID, the PSK or an address except by reading the glass. The honest instruction is
therefore *"Read the network name and password from the bridge's screen, join that Wi-Fi network,
then come back"* — not a button that leads nowhere.

**Hop-0 rail rendering:** `SetupRail` takes `hop: 0`, which renders all three circles inactive on
the connector with no error tint. A preflight failure is a precondition, not a bad hop.

**Device during preflight:** the bridge sits on `STANCE_READY_TO_PAIR` saying *"Open the app on your
phone"* — the one moment where the absence of a phone-driven stance is correct.

### 13.2.1 Hop 1 — phone ↔ bridge (BLE)

#### The fork: new bridge vs. already-provisioned bridge

Before `SetupScanning` renders a row, `BridgeDiscovery.fromAdvertisement` parses the status blob
(`ble-gatt.md` §2.3). Two new flag bits (§13.8.3) split the list:

| Blob state | Row treatment | On tap |
|---|---|---|
| `bonds == 0` | "New — not set up yet" | full three-hop flow |
| `bonds > 0`, `bonds_full == 0`, `paired == 1`, net up | **"Already set up — add this phone"** | `SetupAddThisPhone` |
| `bonds_full == 1` | greyed, "3 phones already paired" | `SetupBondSlotsFull` — **before connecting** |

This is the household case, and it is the difference between a 15-second second-phone setup and
walking a spouse through Wi-Fi provisioning for a bridge that is already on the network.

**`SetupAddThisPhone` must still verify over HTTP.** It does hop 1 only, then reads `net_status` for
the SSID and `pair_status` for the base id — but if it stops there, `prefs.lastBaseUrl` is null and
that phone's *next* launch races with no cached-IP lane, which is failure #1 all over again. So the
flow ends with the same `_verifyOverHttp` → `recordConnection(url, bridgeId:)` the main flow uses.
When the bridge is BLE-only (hop 3 skipped), it records `lastBridgeId` + `lastBleDeviceId` and
states that this phone starts on the Bluetooth lane.

#### `SetupScanning`

Animated concentric-ring radar in `pit`, elapsed budget as a thinning arc. *"Looking for your
bridge…"* / *"Make sure it's plugged in. The screen should be lit."*

Rows sort by RSSI descending — `BridgeDiscovery.rssi` is parsed at `ble_transport.dart:99,116` and
rendered nowhere today — each carrying the existing blob line from `FindStep._blobLine`
(`onboarding_screens.dart:157-171`), *"pit 243 °F · 4 h 12 m"*, which is good and survives unchanged.

- **One bridge → auto-advance after 800 ms**, row highlighted, Cancel available. Do not make a user
  tap a list of one.
- **Two or more →** each row gets a trailing **"Is this it?"** firing `device_control{identify}`
  (op 10). See §13.7.4: `op_identify` is currently `app_ble_note_activity(); return 0;`
  (`app_ble.c:137`) and does nothing perceptible.
- **`select()` is guarded.** `SetupMachine._inFlight` gates every public async method. Today
  `select()` has no guard (`wizard.dart:273-286`) and `connect` only rejects when already connected,
  so a double-tap overwrites the device while the first connect is outstanding and the subscriptions
  stay `??=`-bound to the first device — reporting the wrong device's state forever.

**OLED — `STANCE_READY_TO_PAIR`**, forced while `ble_bonds == 0 && !ble_connected`:

```
┌─────────────────────┐
│SETUP       [1]2 3   │
│                     │
│  Open the app       │
│  on your phone      │
│                     │
│SmokeBridge-A4F2     │
│Bluetooth ready      │
│*ap    --:--     87% │
└─────────────────────┘
```

Out of the box today the bridge shows `APP_UI_PAGE_PROBES` (`app_ui_model.c:31-32`): four rows
reading `--`, with BLE mentioned nowhere except the STA-joined branch of the network page, which a
factory-default AP-mode bridge never reaches.

**Advertising must be held at the 250 ms fast interval for as long as this stance is active.**
`app_ble_adv_note_fast()` sets a one-shot 60 s window and the interval decays afterwards
(`app_ble_adv.c:136-138`). `app_ble_note_activity()` (`app_ble.c:304-310`) *does* re-arm it — but its
only caller is `op_identify` (`:137`), which requires a live connection. **`app_ble` contains no
timers**, so the re-arm needs a named owner: `app_ui`'s existing 20 ms tick calls
`app_ble_note_activity()` while a setup stance is up. Same owner runs the 120 s stance expiry
(§13.8.3) and the ~60 s device-side pairing deadline.

#### `SetupNoBridges` (10 s, nothing found)

Not "check that it is powered on". A checklist of the bridge's own tells, ordered by likelihood:

> **We can't see your bridge yet**
> · Is its screen lit? If not, hold the **PRG** button for 5 seconds.
> · Are you within about 10 metres, in the same room?
> · Did it just start up? Give it 10 more seconds.
>
> **[ Look again ]**
> *My bridge is already set up — enter its address*

The second link exists because a returning user who lands here is not onboarding at all. Today
manual address entry lives three taps deep in Settings → Network (`settings_network.dart:153-176`)
and is unreachable from the wizard.

#### `SetupPasskey` — the highest-value screen in the app

A live vector reproduction of the bridge's OLED overlay — not a photograph — digits grouped
`418 302` in `monoKey` on `well` with a `glow(pit)` ring. This is the prototype's `.pin-display`
(`index.html:238-242`) used correctly: **not to display a code we know, but to show the user what to
look for.**

> **Look at your bridge**
> Your phone is about to ask for a 6-digit code. It's on the bridge's screen — type it from there.
>
> *Waiting for your phone's pairing prompt…* `0:12`
> **[ I don't see a prompt ]** · *Cancel*

A visible **30 s** countdown, not the plugin's silent 90 s default. At 30 s → `SetupPasskeyNotSeen`:
*"Some phones put it in the notification shade instead of on screen."* → **[ Check my
notifications ]** · *Try pairing again*.

Today the 90 s silence times out into a `FlutterBluePlusException` mapped to
`BleBondRejectedException` (`ble_gatt_fbp.dart:259-262`) → *"Pairing was declined — the code on the
bridge and the code you entered did not match."* The user is told they mistyped a code they were
never shown.

**OLED — `STANCE_PAIRING`**, hint rows corrected so the two surfaces agree:

```
│PAIR WITH PHONE      │
│                     │
│    418 302          │   12×24 at y=12
│                     │
│  your phone will    │
│  ask for this code  │
│*ap    --:--     87% │
```

**Three firmware defects make this screen unsafe today.** All three ship together (§13.7):

1. **A >400 ms PRG hold destroys the passkey.** `app_ui_model_tick` guards the power-off confirm with
   only `if (held >= APP_UI_TAP_MAX_MS && !m->alarm_overlay)` and unconditionally writes
   `st->overlay = APP_UI_OVERLAY_CONFIRM` (`app_ui_model.c:128-140`). The digits are gone
   permanently — NimBLE will not re-issue `PASSKEY_SHOW` for the same attempt. A user pressing PRG
   to see the screen better kills their own pairing.
2. **An alarm overwrites the passkey and never restores it.** `app_ui_model_on_alarm` sets
   `overlay = ALARM` unconditionally (`:76-83`); the 60 s expiry clears to `NONE`, never back.
3. **The display sleeps out from under the code.** `app_ui_model_wake` fires once on `PASSKEY_SHOW`
   (`app_ui.c:373`) and `display_timeout_s` then applies — default 60 s, clamped to 30 s under
   battery saver, and settable to **1** because `handle_config_device_post` validates nothing
   (`app_api_core.c:790-792`).

#### Bond outcomes — four states, not one

Today every BLE exception funnels to `WizardBondRejected` → *"Pairing was declined"*
(`wizard.dart:306-318`), including three failures for which retrying can never work.

| Cause | State | Copy | Primary |
|---|---|---|---|
| `status != 0` on ENC_CHANGE | `SetupPasskeyWrong` | "That code didn't match." | Try again — see the choreography below |
| `BleRebondRequiredException` | `SetupRebondNeeded` | "This bridge was reset and no longer recognises this phone." | Open Bluetooth settings, then auto-detect the bond is gone and resume |
| bond slots full (3) | `SetupBondSlotsFull` | "This bridge is already paired with 3 phones." | Remove a phone → needs op 15 (§13.8.3) |
| `BleStateException('…does not expose the Bridge Control Service')` | `SetupNotABridge` | "That device isn't a Smoke Bridge, or its firmware is too old." | Choose a different device — **no retry button on an unretryable failure** |

**"Try again" after a wrong passkey is a five-step choreography, not a retry.** NimBLE generates a
passkey only inside `BLE_GAP_EVENT_PASSKEY_ACTION` (`app_ble.c:377-384`); after a failed
`ENC_CHANGE` (`:387-395`) the link is still up but the security-manager procedure is over. A new
passkey requires: app terminates the connection → bridge re-advertises (the stance holds the fast
interval) → app re-connects → app initiates bond → device issues a fresh `PASSKEY_SHOW`. The
`SetupMachine` sequences all five and shows one uninterrupted *"Getting a new code…"* state; the
user sees one button.

**Bond success is today identical to failure on the glass:** `BRIDGE_BLE_BONDED` and
`BRIDGE_BLE_PASSKEY_CLEAR` fall through the same case in `on_ble_event` (`app_ui.c:375-382`) and the
digits simply vanish either way. It gets its own 3 s stance:

```
│   PAIRED  ✓         │
│                     │
│  Phone connected    │
│                     │
│  Next: your         │
│  Smoke X base       │
```

#### Also required at hop 1

- **Restart advertising after `BLE_GAP_EVENT_CONNECT`** — `app_ble.c:333-346` doesn't. One connected
  phone makes the bridge invisible to every other phone, with no explanation on either screen.
- **`app_ble_ctrl_reset()` on DISCONNECT.** `s_scanning` is cleared in three places, none of them a
  disconnect, and `ble_push_task` drops `PUSH_SCAN_RESULTS` when the link is down
  (`app_ble.c:450-452`). Pocket the phone mid-Wi-Fi-scan and every subsequent scan answers `BUSY`
  **until reboot**.
- **`_flowGen`** — a monotonic counter on `SetupMachine`, checked before every state transition in
  `connectAndBond`/`_applyConfig`/`_awaitHandoff`, bumped by restart/cancel, plus an explicit
  `client.disconnect()`. `wizard.restart()` (`wizard.dart:324-334`) *does* bump `_scanGen` and cancel
  `_connSub`; what it lacks is a guard inside `connectAndBond`, so a late bond still drags the user
  out of the find list. It also emits `WizardFind(scanning: false)`, so "Start over" instantly
  renders *"No bridges found"* before any search runs.
- **Fix the timezone write.** `ble_transport.dart:378` hardcodes `tzOffsetMin: 0` although `set_time`
  carries the field. The clock-sync *screen* is deleted; the *write* moves into the bond-success
  path and starts sending the real offset.

**Deferred, on the heap budget (§13.8.6):** tracking a second simultaneous BLE connection (~1.2 KB)
and CCCD-gated notifications. Until then the bridge serves one central at a time and
`SetupBondSlotsFull` plus the "another device is watching" path (§13.6.4 H9) carry the household case.

### 13.2.2 Hop 2 — bridge ↔ Smoke X (LoRa)

**This hop does not exist in the product today.** It is the largest single gap and the most direct
cause of "my bridge doesn't work".

#### What is known, and what still is not

Contrary to earlier drafts, the repo is **not** silent on this handshake.
`docs/reference/smoke-x-receiver/README.md:147` documents that an unpaired receiver alternates the
two sync channels (920 MHz for X2, 915 MHz for X4); that placing the base in sync mode makes it send
**sync bursts every three seconds**; and that once the receiver transmits its sync response on the
target frequency, **the base returns to normal operation**. [02 §2.4](02-smoke-x-protocol.md) carries
the state machine and [02 §2.5](02-smoke-x-protocol.md) the invariant that this ACK is the only LoRa
transmission we ever make.

The gesture itself is confirmed by the product owner: **hold the SYNC button for a few seconds**, on
the base and on a ThermoWorks receiver alike. Our bridge performs the receiver half in software, so
the user only ever touches the base. **[K, owner-reported]**

Three facts remain genuinely unmeasured, and all three are timing:

| Fact | Sets | Conf. |
|---|---|---|
| Exact hold duration and the base's own confirmation (LCD text? tone?) | the instruction card and the "did it register?" fallback | **[?]** |
| How long the sync window stays open before the base gives up | `kSyncWindowS` | **[?]** |
| Interval to the first state message after the ACK | the SYNC_RECEIVED watchdog | **[I]** one broadcast period, 30 s |

**These do not block the hop.** All three live as named constants in one file,
`app/lib/features/setup/copy/base_sync_copy.dart`, with the confidence marker in the comment. The
listen budget is **derived, not fixed**: `max(kListenFloorS, 2 × kSyncWindowS)` with
`kListenFloorS = 45` — long enough to cover fifteen 3 s beacons, short enough that a failed attempt
does not feel abandoned. If the bench says the window is 15 s rather than 60, three constants change
and no screen is redesigned.

#### `SetupBaseIntro`

Full-bleed illustration of the X4 base with the SYNC control highlighted in `pit`, gesture as the
headline:

> **Now let's find your thermometer**
> Press and hold **SYNC** on your Smoke X base for a few seconds, until its screen shows that it's
> syncing.
>
> **[ I've done it — start listening ]**
> *My base isn't here right now*

The secondary is a real, non-punitive skip → `SetupBaseSkipped`, which finishes setup and drops a
persistent resumable card on the Cook tab: *"Pair your Smoke X — the bridge can't read temperatures
until you do."* → **[ Set it up ]**.

**OLED — `STANCE_BASE_LISTEN`**, driven by `set_setup_stance` so both surfaces say the same sentence
at the same instant:

```
│SETUP       1[2]3    │
│                     │
│ Hold SYNC on your   │
│ Smoke X base        │
│                     │
│ Listening...   14s  │
│*ap    --:--     87% │
```

#### The protocol hole under this hop

The app is **structurally blind** to RF pairing. Three independent breaks:

- The app never calls `GET /api/v1/pairing` — only the two POSTs at `http_transport.dart:348,350`.
- `app_api_ws_pairing()` (`app_api_ws.c:194`) has **zero callers**; `app_api.c:891-898` registers
  SAMPLE/SESSION/ALARM/POWER only. `BridgeEvent.pairing` (`bridge_transport.dart:56`) is constructed
  at `http_transport.dart:566` and consumed by nothing.
- **BLE has no pairing surface at all** — and hop 2 runs over BLE, before Wi-Fi exists.

The fix is one new characteristic, `pair_status` (§13.8.2). It is the single most important protocol
addition in this document, and at ~64 B it fits the heap budget with room to spare.

#### `SetupBaseListening`

> **Listening for your Smoke X…** `0:14`
> Keep the base within about 30 metres of the bridge.
> *Cancel*

Three sub-states, driven by `pair_status`, that the user can act on differently:

| `pair_status` | Phone | OLED |
|---|---|---|
| `listening`, `garbled > 0` | "We're hearing something, but it's too faint to read. Move the base closer." | `Signal too faint / move closer` |
| `heard` | "Found it — Smoke X 3F91. Waiting for its first reading…" | `SMOKE X FOUND / waiting for a reading` |
| `confirmed` | the payoff → | |

The `heard` wait is real and ~30 s long — the base's broadcast interval. It must be narrated, not
spun through. Today `parse_fail` is folded into `/status.radio.packets_bad`, which the app never
reads, so "check your base" and "move it closer" look identical.

**Who counts the seconds.** `smoke_x_ctrl_tick` returns immediately unless CONFIRMED
(`smoke_x_ctrl.c:163-166`), so nothing drives `elapsed_s`/`remaining_s` today. The listen window
deadline is owned by `smoke_x_ctrl` and evaluated on the existing sample-task tick; `pair_status` is
**notified on state change only**, and the phone counts locally from the state-change timestamp. A
1 Hz notify for a progress ring is not worth the radio.

#### `SetupBaseConfirmed` — the payoff

The product justifies itself here. Do not render it as a checkmark.

> `SMOKE X4 · 3F91 · 4 probes`
> **Your bridge is reading temperatures**
>
> ```
>  Pit       243°F   ●
>  Probe 1    68°F   ●
>  Probe 2     —     ○
>  Probe 3     —     ○
> ```
> **[ Continue ]**

`HapticFeedback.mediumImpact()`, `AnimatedTemp` count-up, one-shot `glow(pit)` bloom on the pit row.
`grep -rn "HapticFeedback|AnimatedSwitcher|TweenAnimationBuilder" app/lib/features/onboarding/`
currently returns nothing.

**This screen cannot render today** — it is the same blocker as §13.1.1. See §13.7.6.

#### Failure branches

Today `SYNC_RECEIVED` is an unbounded trap: `smoke_x_ctrl_tick` returns early unless CONFIRMED, the
radio has been retuned off the sync channel with `s_scanning` cleared (`app_lora.c:46`), further
beacons are counted and dropped (`:51-56`), and the OLED cheerfully says *"Scanning 915/920 MHz"*.
Permanent deadlock, broken only by "Re-scan" — which **erases the pairing**.

| `reason` | Phone copy | Primary | OLED |
|---|---|---|---|
| `timeout_no_beacon` | "We didn't hear your Smoke X. Its sync window may have closed." | Try again (re-arms the instruction **and** the listen) | `NO SMOKE X / hold SYNC and / try again` |
| `timeout_no_state` | "We heard your Smoke X but it never sent a reading. Move it closer and try again." | Try again | `HEARD IT, NO DATA / move closer` |
| `garbled > 3` | "There's a lot of radio noise here. Try moving the bridge away from the smoker's metal body, or closer to the base." | Try again | `TOO NOISY / move the bridge` |
| `ack_failed` | "We couldn't answer your Smoke X. Trying again…" | *(auto-retry)* | `retrying...` |

#### Two hard truths this hop must tell

**1 — Re-listening costs a telemetry gap.** To hear a beacon the radio must alternate 915/920;
`app_lora_set_frequency()` sets `s_scanning = false` (`app_lora.c:46`) and
`app_lora_set_scanning(true)` starts the alternation — mutually exclusive with sitting on the paired
base's operating frequency. So during any listen window the bridge receives **nothing** from the base
it is already paired to. Consequences, all normative:

- `POST /pairing/listen` returns **409 `session_active`** while a cook is open, matching the OTA
  refusal at `app_api_core.c:1435` and the 409 `openapi.yaml:535-536,556-557` already declares and
  the firmware never returns.
- The Bridge settings row is *"Re-listen for the base station — pauses readings for up to 90 s"*,
  **not** "keeps: everything".
- The new listen entry point must satisfy `app_lora_guard_tx_allowed(s_freq_hz)`
  (`app_lora.c:41-44`) or the ACK silently fails — which is exactly the failure `ack_failed` exists
  to detect.

**2 — A button labelled "Pair" must never unpair.** Today `POST /pairing/sync` and BLE op 1 both call
`smoke_x_ctrl_unpair()` — byte-identical to `unpair` (`app_api_core.c:1268-1275`,
`app_ble_ctrl.c:296-301`) — which clears NVS first thing (`smoke_x_ctrl.c:195`). The new
`smoke_x_ctrl_listen(window_ms)` is **non-destructive**: the existing binding stays in NVS and is
restored if the window expires without a confirm.

#### Multi-unit: two Smoke X bases in range

`smoke_x_ctrl.c:50-88` accepts the **first decodable beacon** — no RSSI ranking, no dwell-window
collection, no confirmation. `handle_state` then counts foreign traffic into `s_stats.id_mismatch`
(`:104-108`), surfaced at `/status.radio.id_mismatch` and read by nothing.

v1.0 keeps first-beacon-wins — a second base *in sync mode* at the same moment is rare, and ranking
requires a dwell-and-collect rewrite of the pairing path. What v1.0 adds is **legibility**:

- `SetupBaseConfirmed` states the id it locked onto (`Smoke X 3F91`), so a wrong lock is visible
  immediately, and its secondary is *"That's not my thermometer — listen again"*.
- `id_mismatch > 0` sustained renders an advisory on the Cook tab: *"Another Smoke X nearby is being
  ignored."* This converts an unexplained silence into an understood one.

### 13.2.3 Hop 3 — bridge ↔ network (Wi-Fi)

#### The mode choice is deleted

`ModeStep` (`onboarding_screens.dart:219-250`) asks a first-time user to evaluate "uses more battery,
and your phone has to be within range". They cannot. **Go straight to the network list.** Hosted-AP
appears in exactly three places, never as an unprompted question: a quiet tertiary link at the bottom
of the picker (*"No Wi-Fi where you cook?"*), automatically as the primary on `SetupNetworkEmpty`,
and automatically as the primary after **two** consecutive Wi-Fi failures.

#### Pre-warm the scan, carefully

Fire `transport.startWifiScan()` when hop 2 enters `BASE_LISTEN`. The device-side scan takes ~3–4 s
and streams `wifi_scan_result` notifications, so the list is built by the time the user taps Continue
— turning a 12 s budget (`wizard.dart:398`) into an instant screen.

Two constraints make this non-trivial and both are normative. `app_ble_scan_deliver` pushes the whole
list and clears `s_scanning` immediately (`app_ble_ctrl.c:150-196`), so **the results must be
buffered on `SetupMachine`**, not in the picker's widget state, with a 90 s freshness cap after which
the picker re-scans on entry. And the control lock must **not** be held across the listen window:
`_ctrlLock` serialises individual control round-trips only.

**`_ctrlLock` is required regardless.** `startWifiScan` and `applyWifiConfig` both correlate on
`firstWhere((r) => r.opEcho == 0)` (`ble_transport.dart:503,541`) because `op_echo` is
`OP_ECHO_NONE = 0` (`app_ble_ctrl.c:20`) for both — one result frame satisfies both awaits. See
§13.8.3 for the protocol half of this fix and why the echo value alone does not close it.

#### `SetupNetworkPick`

> **Put your bridge on Wi-Fi**
> The bridge uses 2.4 GHz Wi-Fi. If your network is 5 GHz only, it won't appear here.

Rows sorted by RSSI and deduped by SSID (`wizard.dart:381-391` already does both — keep it). Per
`auth`:

| `auth` | Treatment |
|---|---|
| 0 (open) | tap goes **straight to applying** — no password screen at all |
| 2/3/4/6/7 | normal → password screen |
| 5 (enterprise) | **disabled**, *"Work and campus Wi-Fi isn't supported"*, expands to "Use the bridge's own network instead" |

Enterprise is the sharpest instance of asking an unanswerable question: `applyWifiConfig` accepts a
`user` parameter (`ble_transport.dart:536`), `_applyConfig` never passes one
(`wizard.dart:418-423`), so `user_len = 0`, the bridge tries PSK, and the user is told *"That password
did not work"* about a correct password. And the firmware never implements enterprise at all —
`op_sta_connect` populates only `cfg.sta.ssid`/`password` (`app_net.c:102-129`). **Firmware must
reject `auth == enterprise`** with `result{invalid, "enterprise Wi-Fi not supported"}` rather than
storing credentials it will never use.

Bottom of the list: **Join a hidden network** → `SetupNetworkManual`, a separate screen with an SSID
field *and an auth dropdown*. Today manual entry is hard-wired to auth 3
(`onboarding_screens.dart:382`), so a hidden open network is unjoinable, and typing one character
into the SSID field silently downgrades a selected WPA3 row to WPA2-PSK because `onChanged` calls
`_choose(v, 3)` on every keystroke.

#### `SetupNetworkPassword` — its own screen, one job

Reveal toggle (`obscureText: true` with no reveal today, `onboarding_screens.dart:388`). Live length
validation before Connect enables: 8–63 for WPA2/3, 5 or 13 for WEP, empty for open — today a
3-character PSK is written to the bridge and the user waits out **two** 20 s budgets to be told the
password is wrong. On retry the field is **prefilled and revealed**: `ssid`/`psk`/`auth` live on
`SetupMachine`, not in widget state, because today the tree passes through `HandoffStep` and
`_NetworkStepState` is disposed with all three (`onboarding_screens.dart:311-321`), so a single typo
costs a fresh 12 s scan and a full retype.

#### `SetupApplying` — four narrated phases with a cancel

`HandoffStep` today is one line of text and **no actions at all**
(`onboarding_screens.dart:406-421, 534-547`).

```
✓ Sent your network to the bridge          0:01
◐ The bridge is joining MyHouse            0:09
○ Getting an address
○ Checking this phone can reach it
                                    Cancel
```

**`_applyConfig` must catch `TimeoutException`.** It catches only `BridgeControlException` and
`BleException` (`wizard.dart:427-433`), but `applyWifiConfig` awaits with `.timeout(10 s)`
(`ble_transport.dart:538,557`). A bridge that ACKs the write but never emits a result frame throws
`TimeoutException` → escapes the unawaited `onPressed` closure → `runZonedGuarded` → **the
full-screen crash page with a raw Dart exception** (`error_boundary.dart:128-149`). Dismissing
returns to a cancel-less spinner that will never resolve.

**Grace window across the radio reconfigure.** `_watchLink` emits `WizardLinkLost` on any disconnect
while not done (`wizard.dart:226-232`), but a brief BLE drop across an ESP32-S3 Wi-Fi reconfigure is
expected. Suppress link-lost while applying, for `kApplyGraceMs`. **That constant is unmeasured
[?]** — it defaults to 5 s and is one of the bench items (M8 W0/V6.3).

#### Wi-Fi failure — the reason byte

`net_status` has no reason field, so six distinct failures read as "wrong password". Append
`reason: u8` (§13.8.3).

| `reason` | Headline | Body |
|---|---|---|
| `wrong_password` (ESP 15/202/204) | "That password didn't work" | "Check it and try again — you don't need to touch the bridge." |
| `not_found` (ESP 201) | "The bridge couldn't find MyHouse_5G" | "It may be a 5 GHz network — the bridge only sees 2.4 GHz. Or it's out of range of where the bridge is sitting." |
| `assoc_refused` (ESP 2/8/39/200) | "Your router turned the bridge away" | "Some routers block new devices, or filter by MAC address." |
| `no_ip` | "The bridge joined but never got an address" | "Your router didn't hand it one. Restarting the router usually fixes this." |
| `weak_signal` | "The signal is too weak where the bridge is" | "It connected, then dropped. Move the bridge closer to your router." |

Also: **stop the retry ladder** after N consecutive `wrong_password` results
(`app_net_core.c:93-102, 305-309`) and say so on the glass. Grinding 1/2/5/10-minute retries against
known-bad credentials forever is not resilience.

#### `SetupUnreachable` — joined, but this phone can't see it

`net_status: up` means the radio associated, not that this phone can reach the bridge. The app
already holds the IP (`_ipOf(settledStatus)`, `wizard.dart:536-542`) and never shows it.

> **The bridge is on your Wi-Fi, but this phone can't see it**
> The bridge is at **192.168.1.57**. Your phone might be on mobile data, on a guest network, or on a
> different Wi-Fi.
>
> **[ My phone is on MyHouse — try again ]** · *Let the bridge host its own network*

With `connectivity_plus` the app can name the actual mismatch instead of guessing.

#### Hosted mode — currently a guaranteed dead end

Four compounding blockers; all four fixed together or hosted mode stays impossible.

1. **The join reports failure on success** — the microtask-ordering bug in §13.1. Make Dart's
   `joinAp` resolve on `states.firstWhere((s) => s == bound)` raced against a timeout and
   `onLost`/`onUnavailable`, so "resolved means bound" — which is what the doc comment at
   `network_binder.dart:52-55` already claims. **`FakeNetworkBinder` must be made asynchronous** and
   a regression test added, or the suite cannot see the bug.
2. **The escape hatch loops** — `revertToHosting` re-enters `joinAp` while already bound. Make it
   idempotent: already bound to the bridge's AP → skip the join, go straight to verification.
3. **The SSID is guessed** — `'SmokeBridge-${_bridge?.name.split('-').last ?? ''}'`
   (`wizard.dart:509`). `BridgeDiscovery.fromAdvertisement` falls back to the raw device id when the
   scan response carried no name (`ble_transport.dart:93`), yielding
   `SmokeBridge-AA:BB:CC:DD:EE:FF` — an SSID that does not exist. The authoritative value is in hand:
   `net_status.ssid`, live at `wizard.dart:506`. Use it; fall back to `deviceInfo()`; guess never.
4. **The AP dies the moment the user taps Done** — `OnboardingRoute.dispose` calls
   `_binder.dispose()` (`:110`) → `bindProcessToNetwork(null)`.

**Blocker 4 is a Kotlin-side redesign, not a Dart hoist.** `MainActivity.kt:16` constructs the Kotlin
`NetworkBinder` per `configureFlutterEngine` and `:21-27` calls `binder?.unbind()` unconditionally in
`onDestroy()`. Hoisting the Dart object into `AppEnv` buys *route* independence — which is worth
having and is the v1.0 scope — but any activity destroy still unbinds. True process lifetime requires
a bound Service or a cached FlutterEngine plus a deliberate `onDestroy` policy. **v1.0 ships route
independence and re-binds on resume**; the Service is a recorded follow-up. Additionally,
`ChannelNetworkBinder`'s constructor calls `setMethodCallHandler` on a `const MethodChannel`
(`network_binder.dart:63-64`), so two instances silently clobber each other's handler — **the
onboarding-owned instance is deleted, not supplemented.**

**And the credentials must be on screen.** `wizard.apPsk` is stored (`wizard.dart:425`) and rendered
by no onboarding screen. [05 §5.8.2](05-connectivity-and-provisioning.md) says plainly: *always keep
the manual path, because OEM behaviour varies.*

> **Join the bridge's own network**
> ```
>  NETWORK   SmokeBridge-A4F2      [copy]
>  PASSWORD  k7Ru4mXwTz            [copy]
> ```
> **[ Join it for me ]** → the Android suggestion dialog
> *I'll join it myself in Wi-Fi settings*

**OLED — `STANCE_AP_HOSTING`:** SSID + PSK, alternating every 4 s with a Wi-Fi join QR
(`WIFI:T:WPA;S:<ssid>;P:<psk>;;`, version 3, ECC L, 29×29 at 2 px, inside the 64 px height —
[05 §5.3](05-connectivity-and-provisioning.md) already sizes it).

**The QR is not polish; the text path is broken.** `app_ui_draw_char()` draws glyph rows 0..6 only
(`app_ui_fb.c:97`) while the Adafruit 5×7 table stores descenders with bit 7 set. `k_psk_alphabet`
(`app_config_store.c:332-334`) excludes `0/O/1/l/I` but **includes `g`, `p`, `q`, `y`**. Clipped,
`g` and `q` differ by one pixel and `y` reads as `u`, which is also in the alphabet. **Two fixes,
both required:** draw 8 glyph rows into the 6×8 cell (row 7 is empty for 90 of 95 glyphs — zero
cost), *and* drop descenders from the alphabet.

#### The blocker under all of the above

`set_mode_internal(AP, force=true)` bypasses the same-mode early return and unconditionally does
`s_state = AP_STARTING; start_ap()`. `op_start_ap` (`app_net.c:53-93`) does `esp_wifi_set_config`
then `esp_wifi_set_mode(WIFI_MODE_APSTA)` — already the mode on a factory-fresh bridge
(`app_net.c:543-548`). The chain then requires that **no `WIFI_EVENT_AP_START` fires**, so
`app_net_core_on_ap_started` never runs and `app_net_core_tick` has no `AP_STARTING` case, leaving
`net_status` at `idle` forever.

**That last link is an unmeasured IDF behaviour [?]** — this repo has never measured whether
`esp_wifi_set_config(WIFI_IF_AP, …)` on an already-`APSTA` radio re-emits `AP_START`. It is bench
item M8 W0/V6.2, and the fix is written to be correct either way:

1. Add an `APP_NET_STATE_AP_STARTING` case to `app_net_core_tick` with a ~5 s deadline that re-issues
   `start_ap` once and then publishes `AP_UP` anyway.
2. Make `op_start_ap` return tri-state `already-up` when `esp_wifi_get_mode()` includes AP and the ap
   netif has an address; `set_mode_internal` then calls `app_net_core_on_ap_started()` synchronously.

**Same class:** the null-guards added after the boot-race panic (`app_net_core.c:161-163`) *discard*
Wi-Fi events arriving before init, and `AP_UP` is only ever reached from that one edge — so a boot
that loses the race is stranded for the life of that boot. Add a one-shot reconciliation after
`app_net_core_init` returns: read `esp_wifi_get_mode()` and the netif addresses and feed the
corresponding callback. **Keep the guards; pair every guard-dropped edge with a reconciliation.**

### 13.2.4 Landing, persistence and re-entry

#### `SetupNameAndUnits`

> **What should we call it?**  `[ Backyard smoker ]`
> **Show temperatures in**  `[ °F | °C ]`

Naming turns "a gadget I configured" into "my smoker" and makes notifications, the app bar and
session records legible in a two-bridge household. **Units are asked once, here** — not buried in
Settings where today they reach only the bridge's OLED (§13.3.5).

#### `SetupDone`

> ✓ **Backyard smoker is ready**
> ```
>  Bluetooth      paired
>  Smoke X        3F91 · 4 probes
>  Wi-Fi          MyHouse · 192.168.1.57
> ```
> **[ See my probes ]**

A skipped hop renders `— not set up · Set up now` in `warning`, and the same row appears as a
dismissible card on the Cook tab.

#### Persist at every proof point, not at Done

`BridgePrefs` gains `lastBridgeName`, `lastMode`, `lastApSsid`, `lastApPsk`, `lastBleDeviceId`,
`basePaired`, `setupResumeAt`, `poweredOffAt`, and starts writing the existing `displayUnits`.

| Proof point | Write |
|---|---|
| bond succeeds | `lastBridgeId` (from `device_info.id`), `lastBleDeviceId` |
| `pair_status.state == confirmed` | `basePaired` |
| `net_status.state == up` | `lastMode`, plus `lastApSsid`/`lastApPsk` when AP |
| HTTP 200 from `_verifyOverHttp` | `recordConnection(url, bridgeId:)` — the id is captured at `onboarding_route.dart:76` today and discarded |
| `SetupNameAndUnits` submit | `lastBridgeName`, `displayUnits` |

**And redefine the gate.** `LaunchNeedsOnboarding` stops deriving from `lastBaseUrl == null` and
becomes **`prefs.lastBridgeId == null`** — "have we ever met a bridge" is *identity*, not *address*.
A BLE-only session, a DHCP move, or a lost race can then never re-trigger setup.

`bridgeId` matters independently: `_defaultProbe` (`connection.dart:171-181`) accepts any host
returning a non-empty `deviceId`, despite `ConnectionProbe`'s own contract promising an id match
(`connection_manager.dart:56-57`). It changes to return `Future<String?>` and reject a mismatch
(§13.6.4 H4). **This is a seam change**, not a one-liner: `connection.dart:134` is
`writeCache: (baseUrl) => prefs.recordConnection(baseUrl)`, so `ConnectionProbe`'s typedef,
`ConnectionManager`'s lane plumbing and `writeCache`'s signature all move together.

#### Escape, resume, re-entry

- **Escape:** every non-terminal setup screen has a close affordance and a `PopScope` mapping system
  back to "Leave setup?" (confirmed only while applying). Today `OnboardingScreen`'s AppBar has no
  leading widget (`onboarding_screens.dart:42-43`), the route was entered with `context.go`, and
  Android Back **exits the app**.
- **Resume:** killing the app at hop 2 re-enters at hop 2, from `prefs.setupResumeAt`.
- **Re-entry:** the Bridge tab (§13.5.6) carries **Set up a new bridge** and **Forget this bridge**.
  `forgetBridge()` (`bridge_prefs.dart:47`) has **zero production callers** today and `/setup` is
  reachable from one place, so after a factory reset — which the app's own dialog warns forces
  re-pairing (`settings_screen.dart:456-459`) — the user is permanently locked out of their own
  hardware.
- **Factory reset and power-off route through the forget path** on success.
- **Lost phone, bridge in the rain:** op 15 lets a *remaining* paired phone free a slot. With no
  phone remaining the recovery is double-tap RESET → AP mode → the QR on the glass, which is why the
  descender fix is scheduled and not deferred.

### 13.2.5 The golden path, beat by beat

| t | Phone | OLED | LED |
|---|---|---|---|
| 0:00 | launch → preflight passes | `Open the app on your phone` | solid |
| 0:01 | radar, "Looking for your bridge…" | — | solid |
| 0:04 | one found → auto-advance | — | solid |
| 0:06 | passkey illustration, countdown | `PAIR WITH PHONE` + `418 302` | solid |
| 0:09 | OS dialog; user types from the glass | — | solid |
| 0:12 | ✓ haptic | `PAIRED ✓ / Next: your Smoke X base` (3 s) | 3 fast blinks |
| 0:13 | `SetupBaseIntro` — illustrated SYNC hold | `Hold SYNC on your Smoke X base` | 2 Hz pulse |
| 0:16 | user holds SYNC · **Wi-Fi scan pre-warms** | — | 2 Hz pulse |
| 0:19 | "Found it — Smoke X 3F91. Waiting for a reading…" | `SMOKE X FOUND / waiting for a reading` | 2 Hz pulse |
| 0:45 | **`SetupBaseConfirmed` — Pit 243 °F**, haptic | `Pit 243°F / Probe 1 68°F` | 3 fast blinks |
| 0:48 | network picker, already populated | `Choose a network in the app` | solid |
| 0:52 | password, revealed, validated | — | solid |
| 0:54 | `SetupApplying`, four rows ticking | `Joining MyHouse` | slow pulse |
| 1:03 | all four ✓ | `NETWORK joined / 192.168.1.57` | 3 fast blinks |
| 1:05 | name + units | — | off |
| 1:08 | `SetupDone`, three-row summary | `SETUP COMPLETE` (5 s) | 3 fast blinks |
| 1:10 | Cook tab, live, cached URL persisted | `Pit 243°F` | off |

**Seventy seconds. Three hops. Zero questions the user couldn't answer. Zero raw errors. The two
screens never disagreed.** The dominant cost is the ~30 s wait at hop 2 for the base's next
broadcast — real, unavoidable, and narrated rather than spun through.

---

## 13.3 App information architecture

### 13.3.1 Instrument mode and guided mode

`docs/ui/index.html` has "Raw Probes" and the guided cook as two screens (`:534`, `:722`). That is
wrong twice: guided mode is not a superset of instrument mode — you use instrument mode to *check the
fire*, mid-cook — and a route change is the wrong grain for what is really a change of readout organ.

**One Cook scaffold, two modes, switched by a single nullable plan.** Instrument mode is not
degraded; it is the **pre-commit state**, and per the product owner it is a first-class way to use
the product: *you must be able to see temperatures without starting a cook.*

```
INSTRUMENT (plan == null)                GUIDED (plan != null)
┌───────────────────────────────┐        ┌───────────────────────────────┐
│ BridgeHeaderCard              │        │ CookHeaderCard (ember grad.)  │
│  Backyard smoker · 4 probes   │        │  Texas brisket · Cook #42     │
│  [ ⚡ Set up a cook ]          │        │  ⏱ 06:12:44        [ Stop ]   │
└───────────────────────────────┘        └───────────────────────────────┘
│ ProbeStripRow P1 ▁▃▅ 243° +2.1│        │ ProbeHeroCard PIT   ◔band ring│
│ ProbeStripRow P2 ▁▂▃ 163° +4.4│        │ ProbeHeroCard FLAT  ◔sweep    │
│ ProbeStripRow P3      — unplug│        │ Compact P3    │ Compact P4     │
│ ProbeStripRow P4      — unplug│        └───────────────────────────────┘
│ CookChart (15m 1h 6h 15h All) │        │ CookChart + targets + pit band│
```

| | Instrument | Guided |
|---|---|---|
| header | device identity, probe count, "everything is being logged to the bridge" | ember gradient, cook name, mono elapsed badge, Stop |
| probe layout | four equal rows in jack order; detached rows present and dimmed | 1–2 hero + N compact |
| readout organ | **sparkline** (existing `SparklinePainter`) | **`TargetGauge`** — no sparkline |
| targets | only where set manually | plan-driven, with a pull tick |
| ETA / stall | suppressed | `InsightBanner` |
| primary CTA | **[ Set up a cook ]** | **[ Stop ]** |

**The switch is animated, not a rebuild.** `AnimatedSwitcher` on the header, `AnimatedSize` on the
probe region, and the gauge arcs sweep in from zero over 800 ms so confirming a cook *visibly
installs targets*. That one second is the product promise delivered.

**Instrument mode is never called "raw" in the UI.** Header copy: *Live readings* / *Nothing is being
cooked yet — the bridge is logging anyway*.

**Hard dependency:** instrument mode is empty on real hardware until §13.7.6 ships.

### 13.3.2 Route tree

```
rootNavigatorKey
├─ /setup                  full-screen, above the shell   SetupRoute
├─ /recover                full-screen                    BootFailureRoute
└─ StatefulShellRoute.indexedStack → AppShell
   ├─ 0  /cook                      ← initialLocation
   │     ├─ /cook/setup      sheet (flow)     CookSetupSheet
   │     ├─ /cook/presets    sheet (flow)     PresetLibrarySheet
   │     ├─ /cook/mark       sheet (action)   MarkSheet
   │     ├─ /cook/probe/:n   sheet (detail)   ProbeDetailSheet
   │     └─ /cook/connection sheet (detail)   ConnectionSheet
   ├─ 1  /history
   │     └─ /history/:id     push             SessionDetailRoute
   ├─ 2  /alarms
   │     └─ /alarms/quiet-hours   sheet (flow)
   └─ 3  /bridge
         ├─ /bridge/probes · /alarms-device · /network · /device
         ├─ /bridge/advanced · /firmware · /power · /about
         ├─ /bridge/phones        push   PairedPhonesView (needs op 15)
         └─ /bridge/pair-base     sheet (flow)  BasePairingSheet
```

- `errorBuilder` → a branded `NotFoundScreen` with one action.
- `redirect` owns the setup gate, fed by `refreshListenable`. The widget-level `context.go` at
  `dashboard_route.dart:59-61` is deleted, which also deletes the `SizedBox.shrink()` blank frame at
  `:119`.
- `/history/:id` validates `int.tryParse` instead of fabricating session 0 (`router.dart:55`).
- `features/debug/debug.dart` folds into `/bridge/advanced`; `features/alarms/alarms.dart` becomes
  the `/alarms` branch. Neither is orphaned.

### 13.3.3 Four tabs, and why

| Tab | Job |
|---|---|
| **Cook** | the live instrument; the only screen with a connection requirement |
| **History** | cache-served; works with the bridge unplugged, by design |
| **Alarms** | two tiers, quiet hours, **delivery status**, alarm log — configuration and history, not acknowledgement |
| **Bridge** | the device: probes, network, power, firmware, pairing, paired phones, forget/replace |

**Presets is not a tab.** A tab you visit once per cook is wrong 95% of the time; it is a passage at
`/cook/presets`. **Welcome is not a tab** — it is a gate above the shell, so the transport chip and
nav bar cannot render behind an unprovisioned device. **Acknowledgement is not on the Alarms tab** —
it is one tap on the Cook tab's `AlarmBar` and one tap on the notification. A 3 a.m. ack must never
require a tab change.

### 13.3.4 Back behaviour

`context.go` is banned outside `redirect` and the setup→shell transition; every in-branch navigation
is `context.push`.

1. System back pops the branch's stack.
2. At a branch root that is not Cook → `goBranch(0)`, do not exit.
3. At Cook root → `PopScope(canPop: false)` + confirm **only while a cook is running**: *"A cook is
   running. The bridge keeps recording either way."* No cook → back exits silently.
4. Sheets pop themselves; a `flow` sheet with work in flight intercepts back and shows its own cancel.

### 13.3.5 Units, end to end

`prefs.displayUnits` is read in exactly one place today (`settings_route.dart:61`) and passed only to
`ProbeSettingsView`. Every other widget defaults to Fahrenheit; `CookChart` has no such parameter at
all. A °C user changes the bridge's OLED and nothing else — and `settings_probes.dart:133-141` then
renders an °F value under a `Target (°C)` label with °F bounds.

| Surface | Change |
|---|---|
| source | `displayUnits` moves onto `AppTruth`, exposed by the shell provider |
| Cook / History / Detail / Chart / Crosshair | threaded from the shell; `CookChart` gains the parameter and an axis label |
| probe target editor | converts and validates against converted bounds |
| CSV export | header states the unit; values converted |
| notifications | ongoing body and alarm text both convert |
| OLED | already correct via `set_units` |

**Historical sessions.** Storage stays tenths of °F; conversion is presentation-only, so a cook
recorded in °F renders in °C with no migration. Note the nuance: `sample_rec` carries a
`source_celsius` flag (`records.yaml:161`) recording what the *base station* was displaying when the
sample was taken. It is provenance, not storage format, and it is what lets a session detail say
*"recorded while the base was set to °C"*. State both facts in `core/units.dart`'s doc comment so
nobody "fixes" either.

### 13.3.6 Accessibility

Specified in [14 §14.10](14-design-system.md). It is not a v1.1 item: an app whose entire job is to
wake someone up and tell them one number cannot ship colour-only status.

### 13.3.7 Copy, and the reading-level gate

- Every user-facing string lives in one place per feature (`features/setup/copy/setup_copy.dart`,
  `features/cook/copy/cook_copy.dart`, …) as `static const`. No string literals in widgets. This is
  not ARB yet; it is the refactor that makes ARB mechanical later, and it is what makes the gate
  below possible.
- **OLED strings live in one table** in `app_ui_render.c` with a compile-time `_Static_assert` on the
  21-column budget, not scattered `snprintf` literals.
- **Reading-level gate: US grade 6.** Banned without a plain-language gloss: *client isolation,
  association, DHCP, PMF, MAC filtering, enterprise, provisioning, handoff, transport, lane, RSSI*.
  One named reviewer reads every string in §13.2 and §13.5 aloud before the wave ships. This is a
  merge gate; the failure copy *is* the product in this app.
  **OWNER: TBD — assign before W6.**

### 13.3.8 Form factors

This document specified one form factor. The app shipped with none: five `LayoutBuilder`s existed
and all five sized a widget against its own parent, so on a 7.6" unfolded Fold the shell rendered a
stretched phone — a 240 px chart marooned in the middle of a tablet.

**The strategic premise, because it decides everything below: this app is a monitor, not a task
app.** It is watched from across a room, propped on a counter, for fourteen hours. Extra width must
therefore buy *one screen that answers everything without navigating*, not density. Two rules fall
out and are enforced in `design/breakpoints.dart`:

- the **chart** is what grows — it is the artifact people read and share;
- the **probe readouts do not**. A 90 dp temperature stretched across 900 dp reads as a broken
  layout, not a big number, so content columns cap at `SmokeWindow.readableMax` (480 dp) and the
  remainder goes to the chart.

| | Compact (< 600) | Medium (600–839) | Expanded (≥ 840) |
|---|---|---|---|
| navigation | bottom `NavigationBar` | `NavigationRail` | rail, `extended` past 1240 |
| status bar | full-width strip | rail footer | rail footer |
| **Cook** | readouts scroll, chart pinned under at `clamp(200, 32vh, 320)` | supporting pane: readouts left (capped), chart right | same, heroes side-by-side |
| **History** | list; detail is a **branch push** | list-detail; opening a cook is a **selection** | same, stats table two-column |
| **Alerts / Bridge** | list; sections push | list-detail | list-detail |

The destinations and their indices never change with the chrome — that is what keeps the rail swap
a layout change and not an IA change.

**Posture.** Read from `MediaQuery.displayFeatures`, which is real on a Fold and empty everywhere
else, so every non-foldable path takes the `flat` branch with no cost.

- **Tabletop** (half-open, horizontal hinge) is this product's best physical posture and gets its
  own Cook layout: chart above the fold, readouts below. A half-folded phone on a counter becomes a
  purpose-built pit monitor with no stand.
- **Book** (half-open, vertical hinge) snaps the list-detail split to the hinge rather than to a
  percentage. A brisket chart bisected by a crease is the most obvious "never opened on the device"
  tell a foldable app can ship, and it costs one branch to avoid.
- **Continuity** is free from the branch stacks, *provided selection state is hoisted*: History
  holds `selectedSessionId` on the list, not inside the detail, so unfolding while reading cook #27
  lands in the split view with #27 already open.

**Input.** The chart is gesture-only today. Keyboard crosshair stepping, `+`/`-` zoom, `Home`/`End`,
stylus hover-follow, and focus rings on probe rows are **not built** — the one adaptive obligation
this wave leaves open. Destructive confirms already autofocus *cancel*, so a trackpad user is never
one Enter away from an erase they were only reading about.

---

## 13.4 Design system

Specified in [14 — Design System](14-design-system.md): tokens, typography, colour, the component
library, chart rules, accessibility and golden obligations. This section is a pointer so the
numbering in §13.5 onward matches the work packages in
[M8](../tasks/M8-ux-rearchitecture.md).

---

## 13.5 Screen-by-screen specs

### 13.5.1 `/setup`

Replaces `features/onboarding/`. ~34 states across
`preflight.dart`, `screens/hop1_screens.dart`, `hop2_screens.dart`, `hop3_screens.dart`,
`finish_screens.dart`, driven by `setup_machine.dart` (a sealed `SetupState` plus `SetupMachine` with
`_flowGen`, `_inFlight`, `_guard`, resume). Every state: a `SetupScaffold`, one primary action, a
named secondary, an exit.

### 13.5.2 `/cook`

| State | Trigger | Render |
|---|---|---|
| `connecting` | searching | `EmptyState` with narration, lane line, attempt count, **[ Enter the address ]**, Cancel. **Never a bare spinner** (`dashboard_route.dart:120-123`). |
| `offline-empty` | offline, no cache | `EmptyState` + Try again + Enter the address + Set up a bridge + a "what was tried" disclosure |
| `offline-cached` | offline, cache non-empty | full layout + `StaleVeil` + reconnect countdown |
| `powered-off` | `prefs.poweredOffAt` recent | *"You switched this bridge off at 20:14. Hold PRG for 5 seconds to wake it."* |
| `unpaired` | `!truth.paired` | *"This bridge hasn't met your Smoke X yet."* → **[ Pair the base station ]**. **Not** *"Plug a probe into the base station"* (`dashboard_screen.dart:163`), which is wrong advice here. |
| `no-probes` | paired, none attached | today's copy — correct in this branch only |
| `instrument` / `guided` | connected | §13.3.1 |
| `ble-degraded` | BLE transport | full layout + `CapabilityNotice` |
| `stale` / `frozen` | data age | `StaleVeil`; derived values **removed**, not greyed |
| `alarm` | any unacked | any of the above + `AlarmBar` |
| `pending-start` | pending | header is a countdown + Cancel |
| `ended-remotely` | ended with a reason | dismissible info banner naming the reason |

Pull-to-refresh on the whole scroll view. There is no `RefreshIndicator` anywhere in the app today.

`_export` is wrapped in `try/catch` and routed to the Android share sheet. Today the rejected future
escapes to `runZonedGuarded` and replaces the app with a stack trace; on success the SnackBar reports
a `/data/user/0/…` path no non-technical Android 11+ user can reach.

### 13.5.3 `/cook/setup` — three pages

| Page | Content |
|---|---|
| 1 Cut | four category chips → cut cards from `domain/plan/presets.dart`. *Browse the full library* → `/cook/presets`. **[ Skip — just watch the probes ]** closes without a plan. |
| 2 Doneness | doneness cards showing `Target 203° · Pull 198° (+5° rest)`; custom target via a validated field |
| 3 Probes | which jack is the pit, which is the primary food; auto-named from the cut; preview of the hero cards |

**Food safety is enforced, not advised** (owner decision). `SafetyFloor.forProtein()` returns a hard
minimum that `CookPlan`'s constructor refuses to go below, with the citation shown in the sheet.
Floors apply where the hazard is real — poultry, ground meats, pork, fish — and the table cites
USDA/FSIS. **Whole-muscle red meat has no such floor**: a 125 °F rare ribeye is a doneness preference
on a surface-pasteurised cut, not an unsafe cook, and the UI must not lecture about it. Structure the
table so that distinction is data, not a special case:

```dart
enum HazardClass { wholeMuscleRedMeat, poultry, ground, pork, fish }
// wholeMuscleRedMeat -> floor == null; doneness runs 120..160 °F as preference
// poultry -> 165 °F (FSIS)   ground -> 160 °F   pork -> 145 °F + 3 min rest
```

A named reviewer signs off the preset table before it ships. **OWNER: TBD — assign before W10.**

### 13.5.4 `/history`

Swap the one-shot `repo.sessions()` (`sessions_route.dart:37-64`) for `watchSessions()` — it exists
at `repositories.dart:21-22` with zero production callers.

| State | Render |
|---|---|
| cache populated | a card per cook: name or `Cook #27`, date, duration, probe swatches, peak pit |
| sync in flight, cache empty | *"Catching up with your bridge — 12,400 readings"*. **Never** "No cooks yet." |
| offline, cache populated | list + offline badge; everything opens |
| BLE | cache only + *"Bluetooth can't fetch new cooks. Connect over Wi-Fi to catch up."* |
| detail | rename wired (`onRename` exists on the widget and is never passed at `sessions_route.dart:154-160`) |

**Two schema dependencies.** `database.dart:98` declares `schemaVersion => 1` and `Sessions` has no
probe or plan columns, so a guided cook cannot be cached offline and history stats stay blank. This
needs `schemaVersion: 2` plus a `MigrationStrategy`. Separately, **marks have no read path at all**:
`bridge_transport.dart` has `MarkCommand` (`:86-89`) and no `marks()` method,
`http_transport.dart:341` only POSTs, and `MarkDao.replaceMarks` (`database.dart:348`) has zero
production callers. Any screen that renders marks depends on adding the transport method, the HTTP
route and the DAO wiring together.

### 13.5.5 `/alarms`

Three tiers, in this order.

1. **Delivery** — first, because it is the thing silently broken today. Notification permission,
   battery-optimisation status, quiet hours, background monitoring, plus **[ Send a test alarm ]**
   which posts through the real sink on the real channel. It is the only way a user verifies delivery
   before committing fourteen hours.
2. **On the bridge** — the nine rules from `GET /config/alarms` with real switches and their
   tunables. Today this is a hardcoded six-entry literal with `onChanged: null`
   (`settings_route.dart:219-226`): six switches that look interactive, are always on, and cannot
   move. Over BLE: read-only with *"Needs Wi-Fi to change."*
3. **On this phone** — stall, ETA, lid, phone-offline, quiet hours, monitoring toggle.

Then the **alarm log**, from a new `AlarmLogDao` — the `AlarmLog` drift table exists
(`database.dart:79-88`), is registered, and has no DAO, no writer and no reader.

### 13.5.6 `/bridge`

```
Your bridge
  Backyard smoker · SmokeBridge-A4F2 · 192.168.1.42 · fw 1.0.2 · last seen 2s ago
  Rename…
  Identify (flash the screen)
  Paired phones (2 of 3)                 →
  Re-run Wi-Fi setup            keeps: pairing, cooks, this phone's bond
  Re-listen for the base station   pauses readings for up to 90 s
  ─────────────────────────────────────
  Restart the bridge            keeps: everything
  Forget this bridge on this phone   loses: cooks cached here   [Export first]
  Unpair the base station       loses: the RF link; ends the running cook
  Factory reset the bridge      loses: pairing, Wi-Fi, all cooks on the bridge,
                                       this phone's Bluetooth bond
  Power off                     nothing on your phone can turn it back on
```

Every destructive row opens a `CostSheet`; the last two are hold-to-confirm. `forgetBridge()` is
wired here and from factory-reset completion.

Every sub-page renders one of three connection states: **live**, **needs Wi-Fi**
(`CapabilityNotice`), **not connected** (`ProblemState` with the reason). No page may render inert
controls silently — `settings_screen.dart:5-11`'s own stated rule, finally applied. This requires
Settings to **borrow the shell transport** rather than building its own from `prefs.lastBaseUrl`
(`settings_route.dart:67-74`), which is why `_transport is BleTransport` (`:192`) can never be true
today.

**Advanced** either binds `/debug/packets`, `/debug/novelty`, `/debug/coredump` and the app's log
ring for real, or its four empty sections and dead Export-logs button are **deleted**. An
always-empty diagnostic reads as "the radio heard nothing", which is a lie. The `packets_seen` row
bound to `_status!.numProbes` (`settings_route.dart:311`) is deleted either way.

### 13.5.7 Chrome, on every tab

**`SystemStatusBar`** — transport chip with a pulse dot on the left; Wi-Fi RSSI, bridge battery and
LoRa dBm on the right, each **absent** when unknown, never `0%`.

**`TruthBannerStack`** — max two, priority order:

| # | Key | Copy | Action |
|---|---|---|---|
| 1 | `alarm.critical` | rule title + probe + value | Silence |
| 2 | `data.frozen` | "No readings for 14 minutes." | What to check |
| 3 | `link.lost` | "Not connected · retrying in 8s" | Retry now |
| 4 | `base.lost` | "Base station silent for 14m." | What to check |
| 5 | `alarm.warning` | title + value | Silence |
| 6 | `link.blocked` | "Bluetooth is off" / "Nearby devices permission needed" / "This phone is offline" | Turn on / Allow / Open settings |
| 7 | `pair.unpaired` | "Not linked to your Smoke X." | Set it up |
| 8 | `link.degraded` | "On Bluetooth — live readings only." | Why? |
| 9 | `data.stale` | "Readings are 4 minutes old." | — |
| 10 | `cook.pending` | "Waiting for the smoker — 43s" | Cancel |
| 11 | **`notify.blocked`** | **"Alerts are off — you won't be woken."** | Fix |
| 12 | `ota.running` | "Updating — 62% · don't power off" | — |
| 13 | `cook.ended` | "This cook ended: probes detached." | Open |

**Banner 11 is load-bearing.** A cook running with notifications denied, battery optimisation on, or
monitoring off is a fourteen-hour silent failure, and the user must learn before the cook.

**`ConnectionSheet`** — opened from the chip and from every link banner:

1. Bridge name, id, firmware.
2. **The three clocks, spelled out:** `Bridge: last heard 2s ago` / `Smoke X: last packet 31s ago` /
   `Showing data from 14:02`.
3. **Lane table** — every outcome from the last race: `Saved address 192.168.1.42 — no answer
   (2.1s)` · `mDNS — nothing found` · `smokebridge.local — could not resolve` · `192.168.4.1 — no
   answer` · `Bluetooth — not in range`. Highest support value per unit of work in this document;
   costs one field on the connection outcome.
4. Retry now · Enter address (probed inline, confirms the name before committing, through the
   never-called `AppConnection.enterManual`) · Switch to Bluetooth · Bridge settings.

**mDNS must actually work first.** `AndroidManifest.xml:10` declares `CHANGE_WIFI_MULTICAST_STATE`
with a comment explaining that without it mDNS silently finds nothing — and nothing in
`MainActivity.kt` or `NetworkBinder.kt` calls `WifiManager.createMulticastLock`. The lane table would
otherwise report *"mDNS — nothing found"* forever on exactly the phones where mDNS is the only
working lane.

### 13.5.8 `/recover`

`bootstrap()` awaits `openAppDatabase()`, `SharedPrefsBridgePrefs.load()` and
`getApplicationDocumentsDirectory()` before `runApp` (`bootstrap.dart:35-48`). A throw in any of them
means `runApp` is never reached and the zone handler sets a `ValueNotifier` no mounted widget
observes: **white launch window, then a permanently black screen, no timeout, no retry.**

Wrap environment construction; on failure `runApp` a minimal recovery app: *"Smoke Bridge could not
start"* → **[ Try again ]** · *Reset local data*.

---

## 13.6 State machine and failure matrix

### 13.6.1 The truth model

Pure Dart in `app/lib/app/truth/`, no Flutter, the same discipline `domain/` already has.

```dart
enum Transport { none, ble, wifiAp, wifiSta }
enum LinkPhase { searching, connected, degraded, lost, retrying, suspended, blocked }
enum Freshness { live, aging, stale, frozen, unknown }
enum PairState { unknown, unpaired, listening, syncHeard, paired }
enum CookPhase { none, pendingStart, running, endedRemotely }
enum RecordingClaim { verified, presumed, unknown, notRecording }
enum BleAvailability { unknown, ready, off, unauthorized, unsupported }
```

**`RecordingClaim` exists so that copy about "the bridge is still recording" is generated from
evidence rather than typed into a widget.** `verified` = saw `/status` within 2 min with paired +
session open + storage free. `presumed` = last contact < 30 min and all of that held then. The two
get different sentences, and `presumed` never uses the word "is".

**Three clocks, never conflated:** *link age* (bytes from the bridge), *data age* (LoRa packets from
the base), *cache age* (how old the thing on screen is). Each has its own field, its own surface and
its own word.

**Freshness is a function, not a field:**

```dart
Freshness freshnessOf(Duration? age, int periodS) {
  if (age == null) return Freshness.unknown;
  final p = Duration(seconds: periodS);
  if (age <= p * 1.5) return Freshness.live;   // ≤ 45 s
  if (age <= p * 3)   return Freshness.aging;  // ≤ 90 s
  if (age <= p * 20)  return Freshness.stale;  // ≤ 10 min
  return Freshness.frozen;                     // > 10 min == firmware base_lost_s
}
```

The `frozen` boundary is pinned to the firmware's `base_lost_s = 600` (`alarm_cfg.c:46`) **so the
phone and the bridge cross the same line at the same second**. Correspondingly the 60 s OLED
`base_ok` threshold (`app_ui.c:265`) stops driving `s_led.base_lost` (`:488`) and becomes a pure
freshness pip. One threshold, two screens.

A 1 s ticker in the shell recomputes freshness. Two `Timer`s already exist in `app/lib/`
(`ble_gatt_fbp.dart:71,113`), but this is the first **periodic** one, and its absence is why the
elapsed clock can currently stop forever.

**Rendering ladder — no derived value outlives its source:**

| Freshness | Temp | Trend / ETA / arc / stall | Elapsed | Pulse dot |
|---|---|---|---|---|
| `live` | 100 %, probe hue rail | shown | counting | animating |
| `aging` | 100 % | shown | counting | **static**, + `updated 1m ago` |
| `stale` | 55 % | **removed** | frozen, `paused 04:12` | static grey |
| `frozen` | 40 % + `LAST` chip | removed | frozen | absent |
| `unknown` | `—` | absent | `—` | absent |

### 13.6.2 Capability matrix

Every degradation in this document traces to a row here. The right-hand column names the §13.8 item
that closes it; every identifier used is defined there.

| Fact | Wi-Fi | BLE | Offline cache |
|---|---|---|---|
| Bridge identity | `/status.device.id` | `device_info.id` | `prefs.lastBridgeId` |
| Bridge net mode | §13.8.4 | `net_status.mode` ✓ | last known |
| Paired to Smoke X | `/status.pairing.paired` | `live_state.PAIRED` ✓ | last known |
| Base lost | `/status.pairing.base_lost` | §13.8.3 flags b5 | derived from cache age |
| Data age | `/status.pairing.last_packet_s_ago` | §13.8.3 `sample_age_s` | derived |
| Four probe temps | `/live` — §13.7.6 | `live_state.temp[4]` ✓ | last cached sample |
| Probe names / roles / targets | `/live` — §13.8.4 | ✗ — assume jack 1 = pit | needs schema v2 |
| Session active + elapsed | `/status.session` | `SESSION_ACTIVE` + `session_t` ✓ | drift |
| Alarm list | `/status.alarms[]` ✓ | ✗ — only `ALARM_ACTIVE` | needs schema v2 |
| Alarm severity | ✓ | §13.8.3 flags b6 | drift |
| Acknowledge | §13.8.4 REST ack | `ControlOp.ackAlarm` ✓ | queued |
| Pairing progress | §13.8.4 | §13.8.2 `pair_status` | — |
| Full history | ✓ | ✗ (2 h × 1 min, probe 1 only) | ✓ |
| Marks | §13.5.4 | ✗ | always empty today |
| Probe config write | ✓ | ✗ (`ble_transport.dart:427`) | queued |
| Wi-Fi reconfigure | ✓ | ✓ | ✗ |
| Power / restart / factory reset | ✓ | ✓ | ✗ |
| OTA | ✓ | ✗ | ✗ |

**BLE is not a lesser dashboard, it is a *different* dashboard.** Full live temperatures, live
session state, live battery, working controls, working provisioning, working alarm-silence — and no
history, no names, no alarm identity. The UI states that in exactly two places (the transport chip
and the chart footer) and nowhere else pretends.

### 13.6.3 Primary matrix — transport × pairing, at the Cook root

Each cell: **hero / banner / primary action**.

| | Unpaired | Listening / heard | Paired, live | Paired, base lost |
|---|---|---|---|---|
| **Wi-Fi STA** | four `—`, dashed · *"This bridge hasn't met your Smoke X yet."* · **Set up the base station** | `PairingProgress` card with elapsed and base-side instructions · **Cancel** | full dashboard, no banner · **Set up a cook** | values per the freshness ladder · *"Base station silent for 14m."* · **What to check** |
| **Wi-Fi AP** | as STA, plus a persistent `AP` chip and *"Your phone is on the bridge's network — no internet."* | as STA | full dashboard; chart, history, settings all work | as STA |
| **BLE** | four `—` · *"Not paired. Pair the base from here."* · **Set up the base station** | `PairingProgress` from `pair_status` | live temps ✓, names are `Probe 1..4`, no ETA · chart footer *"Bluetooth: 2 hours of the pit probe."* | needs flags b5; same banner as STA |
| **None (cache)** | `—` + "as of" · *"Can't reach your bridge."* · **Retry now** | *"Pairing was interrupted."* | last readings frozen + `LAST` chips + `as of 14:02` · **Retry now** | *"Base was silent when we last heard from the bridge."* |

### 13.6.4 The hard cells

**H1 — link dies silently (half-open TCP).** The firmware never pings
(`app_api_ws_pings_due` has zero production callers) and `BridgeSession` swallows `onDone`.
**Detection is freshness-driven:** `lastByteAt` older than `3 × samplePeriodS` → `lost`, regardless of
what the socket claims. The socket's `onDone`/`onError` is a fast path, not the mechanism.

**H2 — AP mode, phone drops the bridge's SSID.** Re-bind before racing. If the phone is not on the
SSID: `blocked`, with SSID and PSK in a `MonoWell`, Copy, Open Wi-Fi settings, "I've joined — try
again".

**H3 — BLE wins the race but Wi-Fi exists.** HTTP fan-out capped at 6 s; the BLE lane gets its own
12 s budget measured from BLE start (today it inherits the tail of an 8 s race the 5 s dio
`connectTimeout` has already eaten). A late BLE transport is disposed in its own continuation; today
it is orphaned. If BLE wins and HTTP later becomes reachable the app **upgrades silently**: chip
animates, one toast, sync runs, history back-fills. No screen reload.

**H4 — two bridges / DHCP reassignment.** `_defaultProbe` returns the device id and rejects a
mismatch against `prefs.lastBridgeId`. A mismatch is a **decision**, never a swap: *"This is
SmokeBridge-9C21, not your Backyard smoker"* → **Use this one instead** / **Keep looking**.

**H5 — onboarding persistence.** §13.2.4.

**H6 — alarm fires while unacked and the link is down.** The device latches. The app never enters
`connected` without an explicit `GET /status` read, so the banner and the notification appear within
one round trip.

**H7 — control tapped after a silent link death.** `controlsEnabled` is driven by phase **and**
freshness from **one source**, so the chip and the buttons can never disagree — today
`dashboard_route.dart:137` says `_session != null` while the chip says Wi-Fi. A failed control write
immediately transitions to `lost` and the toast names it.

**H8 — factory reset / power off.** Both currently strand the app forever. Factory reset →
`forgetBridge()` + clear the local cache (after offering export) + `/setup`. Power off → write
`prefs.poweredOffAt`, which the offline surface then reads back as a sentence.

**H9 — two phones, one cook.** With the WebSocket client cap held at 2 on the heap budget
(§13.8.6), the second phone is told the truth rather than failing generically: the 1013 close carries
a JSON reason and the chip reads *"Another device is watching this cook"* with **Take over**. Either
phone's ack is device state and clears on both. Either phone stopping the cook renders
`ended-remotely` on the other, not a silent control swap. Conflicting config writes are **last write
wins, and announced** — the loser refreshes and shows *"Someone else changed these settings."* Each
phone posts its own ongoing notification; there is no cloud and no fan-out, and that is stated rather
than hidden.

### 13.6.5 Reconnection

One `LinkController`, held by `AppEnv`, exposed as the **first real Riverpod provider** — three
riverpod packages are dependencies today and there are zero providers; `ProviderScope` is mounted at
`bootstrap.dart:48` and never consumed.

```
searching ──win──► connected ──degrade──► degraded
    ▲                  │                     │
    │            lost trigger ◄───────────────┘
    │                  ▼
    └──── retrying(n) ◄─┘ ──idle 10m, bg, no cook──► suspended
                        └──BT off / denied / no net──► blocked
```

**Lost triggers:** `onDone`/`onError`; `lastByteAt` older than `3 × samplePeriodS`; any control or
config write throwing; `BridgeStreamBusy` (special-cased per H9).

**Ladder:** `backoffDelay` (1/2/4/8/15/30) — already implemented, currently uncalled. Foreground caps
at the 8 s rung; background-with-cook runs the full ladder indefinitely.

**Kicks:** the `connectivity_plus` stream (the `connectivityChanges` parameter exists at
`connection_manager.dart:91` and is supplied by nothing in production); `AppLifecycleState.resumed`
via a `WidgetsBindingObserver` at shell scope (zero exist today); BLE adapter → on; Retry now; a
successful manual address.

**Race hygiene:** `ConnectionManager.cancel()` completing the winner and cancelling lane futures,
called from dispose. Today `AppEnv.newConnection()` mints one per route and overlapping browses
overwrite the discovery field, so navigating dashboard↔settings tears down the new race's native
discovery. A single shell-scoped owner is the real fix.

**On reconnect, in order:** `GET /status` → identity check (H4) → delta sync with progress →
re-subscribe → re-hydrate alarms → back-fill the chart gap. **The gap is drawn, not interpolated** —
it is the visible proof that the bridge kept recording.

### 13.6.6 Background and notifications

`CookMonitor` is complete, host-tested, and has **zero construction sites in `lib/`**. It is
instantiated once in `AppEnv`, not in a route's `initState`, because routes dispose.

| Trigger | Behaviour |
|---|---|
| First session start | Request notification permission **here**, not at launch; then offer the battery-optimisation exemption once |
| Cook running + monitoring on | Foreground service; ongoing notification at 30 s with pit, food, and ETA |
| Ongoing, `stale` | Body swaps to *"Last reading 6 minutes ago"* and **drops the ETA** — this is where a false ETA does the most damage |
| Ongoing, `frozen` | Title prefix ⚠️, body *"No readings for 14 min — check the base station"* |
| Critical alarm | HIGH channel, full-screen intent, DND bypass, survives quiet hours. **Two actions: Silence and Open** — the one interaction a person in bed will attempt must not require unlocking, finding the app and tapping a banner |
| Warning alarm | DEFAULT channel, silenced (not suppressed) during quiet hours |
| Bridge unreachable 3 min with a cook | Warning, once |
| Phone offline | *"Your phone lost its connection — the bridge is still recording."* A `presumed` claim, worded as one |
| No cook, 10 min idle | Service stops; link → `suspended` |

**Android 12+ blocks background foreground-service starts.** Cooks auto-start on the device at
≥ 90 °F (`cook_lifecycle.h:18`), from the OLED, or from another phone. If the app is backgrounded
when that `session{action:"started"}` frame arrives, `startForegroundService` throws
`ForegroundServiceStartNotAllowedException`; `FOREGROUND_SERVICE_CONNECTED_DEVICE`
(`AndroidManifest.xml:38`) is not an exemption. **Policy:** catch it, record
`monitoringDeferred = true`, post a normal (non-service) high-priority notification saying *"A cook
started on your bridge — open the app to keep watching it"*, and start the service on the next
resume. Banner 11 renders while deferred. The app never silently believes it is monitoring.

---

## 13.7 The on-device experience

### 13.7.1 OLED page set

Keep the five pages (`app_ui_core.h:130-135`), add one page and one overlay.

| Page | Changes |
|---|---|
| `WELCOME` **(new)** | forced default while `ble_bonds == 0 && !paired`: `SMOKE BRIDGE / Open the app / Bluetooth: SmokeBridge-A4F2 / or join Wi-Fi <ssid>`. Auto-retires on first bond. |
| `PROBES` | fix the sticky alarm band (`p->has_band` is set inside a conditional with no `else` and the state is memset once at init, so a disarmed band stays on the glass forever); fix the 12×24 headline colliding with row 4; `BASE LOST  Nm ago` replaces the numbers when the base is silent |
| `COOK` | copy fix `Hold PRG to start` → `No session running / Start one in the app`; real ETA and stall from `cook_ring_slope_f_per_hr` — today `eta_valid`/`eta_s`/`stalled` are never assigned outside tests, so it reads `ETA --` forever |
| `NETWORK` | add a **fallback branch** — `app_net_get_status` emits `"fallback"` and `fill_snapshot` only tests for `"failed"`, so a bridge that could not join renders as a cheerful `NETWORK hosting`; wire real `retry_attempt`/`retry_in_s` (today both render from fields nothing writes, `app_ui_render.c:375-382` vs `app_ui.c:274-291`); add the QR frame |
| `RADIO` | add the `SMOKE_X_SYNC_RECEIVED` third state — today it renders as fully unpaired, telling the user to do the thing they just did; replace the hardcoded `Interval 30.0s avg` with a real mean or delete the row |
| `SYSTEM` | add `SmokeBridge-XXXX` unconditionally — the device never displays its own identity today |
| `OVERLAY_SETUP` **(new)** | the stances in §13.2, expiring at 120 s |

**The OTA overlay needs a publisher, not a subscriber.** `app_ui_render.c:627-640` already draws it
and it is already golden-tested, but `BRIDGE_EVT_OTA` has **no publisher anywhere**: it appears only
at `bridge_event_types.h:30` and `firmware/test/test_bridge_event_guard.c:44`. OTA progress reaches
the WebSocket through a direct callback — `.progress = ota_push_progress` (`app_api/app_api.c:341`,
defined `:636`). Registering an `app_ui` handler subscribes to silence. **The work is a second
progress sink or a new publisher in `app_ota`**, and it must be scoped as such. It matters because
*don't power off* is the one warning that must reach the person standing next to the board.

### 13.7.2 Overlay priority

Today any overlay clobbers any other and none is restored. Introduce `st->overlay_prev` and:

```
OTA  >  PASSKEY  >  ALARM  >  CONFIRM  >  SETUP  >  SPLASH  >  NONE
```

**Why PASSKEY outranks ALARM, stated so nobody reverts it:** the alarm does not stop being an
alarm — the `!` glyph in the status strip persists, the LED alarm pattern persists (it outranks setup
in the LED order), and the phone gets the notification. The passkey window is ≤ 60 s, user-attended,
and unrecoverable if lost. OTA outranks everything because the failure mode is a brick.

### 13.7.3 Button model

M7 made the PRG button carry two meanings. Keep exactly that.

| Gesture | Effect |
|---|---|
| **Tap** | wake if asleep (press consumed whole); otherwise advance a page and dismiss a showing alarm overlay (**dismiss is not silence**) |
| **Hold 2 s, commit on release** | power off, behind a countdown confirm |

New suppression in `app_ui_model_tick`: the confirm does not arm while the overlay is `PASSKEY`,
`OTA` or `SPLASH`.

**And the copy must stop lying.** Four on-glass strings instruct gestures the firmware does not
implement — `app_ui_model` has exactly one action, `POWER_OFF`. Fix the copy, not the gestures:

| Where | Current | New |
|---|---|---|
| `app_ui_render.c:618-621` splash | `hold PRG for` / `AP mode  3` | `double-tap RESET` / `for setup mode` |
| `:383-384` network | `Hold PRG to host` / `own network` | `Open the app to` / `fix Wi-Fi` |
| `:244` cook | `Hold PRG to start` | `Start a cook in` / `the app` |
| `:579` alarm | `tap PRG to silence` | `tap to dismiss` |

**The splash string is the worst defect in the firmware:** following its printed instruction for 3 s
arms the power-off confirm at 400 ms and deep-sleeps the board on release. `step_recovery_window()`
is still a stub (`main.c:149-153`).

### 13.7.4 LED language

Four of these patterns already exist (`app_ui_led.h:25-31`). This table **redefines two of them** and
adds three; both redefinitions are called out so nobody reads this as new work only.

| Pattern | Shape | Means | Status |
|---|---|---|---|
| `ALARM` | 2 Hz hard, 50 % | something needs you now | exists |
| `IDENTIFY` | 10 Hz, 5 s | this is the one you tapped | exists, **but does nothing** — see below |
| `OTA` | slow breathe | updating; do not power off | exists, unchanged, highest precedence after ALARM |
| `BASE_LOST` | double-blink | **retimed to the alarm engine's 600 s**, not the 60 s freshness pip | **redefined** |
| `HEARTBEAT` | ~2 % breathe at 0.5 Hz | alive and healthy — so "dark" unambiguously means "off" | **redefined** from "one 20 ms flash per packet" |
| `SETUP_LISTEN` | 2 Hz soft pulse | working on it | new |
| `SETUP_OK` | 3 fast blinks then off | that worked | new |
| `SETUP_FAIL` | 1 Hz off-heavy (10 % duty) | that didn't work; look at the screen | new |

**The existing `PAIRING` (solid) is the "setup waiting" pattern — renamed, not duplicated.** It is
driven every tick by `s_led.pairing = !snapshot.paired` (`app_ui.c:487`), i.e. "not paired to the
**Smoke X base**". Adding a second solid pattern meaning "waiting for a phone" would give one duty
cycle two meanings. Resolution: rename it `APP_UI_LED_ATTENTION` (solid = *the bridge wants you*),
driven by `!paired || setup_stance_active`, and let the glass disambiguate — it is already saying
which.

**`led_enabled` defaults to `ALARMS_ONLY` and `app_ui_led_duty` returns 0 for every pattern except
ALARM and IDENTIFY** — so during setup, the moment a user most needs to know the bridge is alive, the
LED is dark. Add `bool setup;` to the input struct, ranked immediately below `alarm_unacked`, and
exempt it from the `ALARMS_ONLY` gate alongside IDENTIFY, on the same stated grounds: *the user
deliberately started this, seconds ago.*

**`identify` must become perceptible.** `op_identify` is `app_ble_note_activity(); return 0;`
(`app_ble.c:137`) and `identify_until_ms` is read by the LED code and **written by nobody**. Add a
`BRIDGE_BLE_IDENTIFY` event; `app_ui` sets the deadline, wakes the panel, and shows a 5 s overlay
with the device name in 12×24. Add `POST /api/v1/identify` for the Wi-Fi path.

Also post `BRIDGE_EVT_BUTTON{tap}` from `app_ui` and have `app_ble` call `app_ble_note_activity()` on
it — walking up and pressing the button is the most discoverable recovery action on a one-button
device, and it is currently wired to nothing.

**Buzzer.** `app_ui_buzzer_on()` exists, is called from nowhere, there is no GPIO7 configuration, and
the header concedes the piezo is unfitted on every board. **v1.0 ships with no buzzer** (§13.9.3), so
an **unacked critical alarm holds the panel awake**, overriding `display_timeout_s`.

**One thing this document does *not* change:** `app_ui_led.c:64-70` returns zero duty for
`APP_UI_LED_MODE_OFF` *in every state, including alarm*, with the comment *"The user asked for
darkness; the API, the app and the buzzer are where an alarm still shouts."* That implements
[07 §7.5](07-display-and-controls.md). With no buzzer fitted, the argument for overriding it is
stronger than it was — but overriding it is a **deliberate reversal of a recorded decision** and it
is listed as an open question (§13.9.3), not smuggled in as a consequence.

### 13.7.5 Rendering correctness

| Defect | Location | Consequence |
|---|---|---|
| Descenders clipped | `app_ui_fb.c:97` draws 7 of 8 glyph rows | `g`/`q` differ by 1 px in the AP password; `y` reads as `u` |
| No degree glyph in the 5×7 font | `app_ui_fb.c:88-91` substitutes `?` | committed goldens read `163??F` — the two screens a user reads mid-cook |
| Dirty-render never fires | `app_ui.c:351` copies the panel's own I²C counters into the compared snapshot; `app_ui_panel.c:185` memcmps the whole state | 1029 B pushed every 20 ms tick (~23 ms of bus at 400 kHz), voiding the power argument and degrading button sampling. **Fix: memcmp the rendered framebuffer, not the state.** |
| I²C on the event loop, inside the lock | `on_ble_event`/`on_alarm_event` → `app_ui_model_wake` → `panel_power` → blocking `i2c_master_transmit(…, 100)` | Over `bridge_event`'s 5 ms budget — the class that took the board down on 2026-07-23 (`19c88ec`, `a336597`), **on the alarm path**. Note the budget asserts only under `!NDEBUG` (`bridge_event.c:26-29`): it panics debug builds and stalls the event loop in release ones. Handlers set flags and notify; all I²C on `ui_task`. |
| Dead OLED bricks provisioning | `app_ui_init` returns -1 before registering handlers or starting `ui_task`, while BLE is `BLE_HS_IO_DISPLAY_ONLY` + `sm_mitm = 1` | No display → no passkey → **unprovisionable board**. Start `ui_task` regardless (`app_ui_panel_render` already no-ops when the panel is down) and fall back to Just Works when the display is known dead, saying so in the app. |
| Base indicator flaps | 60 s threshold against a 30 s nominal interval | two dropped packets start an alarming blink. Hysteresis: stale at 90 s, clear on the next valid packet. |

### 13.7.6 Live temperatures without a cook

This is the firmware half of §13.1.1 and §13.3.1, and it is a **wire-semantics change, not a
one-liner.**

`cook_store_task.c:180-191` pushes to the ring with `t = session_rel_t(s->t_rel_s)`, and
`session_rel_t` (`:54-61`) reads `s_anchor_set`/`s_t_base`/`s_uptime_base`, which are set in
`open_session` (`:114-115`) and cleared in `close_session` (`:132`), with `cook_ring_reset()` on open
(`:117`). With no session there is **no defined `t` origin** — and `t` is read by `/live.t` and
`/live.recent.t0` (`app_api_core.c:559-564`), by `live_state.session_t`
(`records.yaml:341-345`) and by the advertising blob's `minutes` (`app_ble_adv.c:85-88`).

**Specification:**

1. The ring is pushed on every valid state message, session or not.
2. With no session open, `t` is **seconds since boot**, and a new `live.t_origin` field
   (`session` | `boot`) says which. `session_t` in `live_state` reuses spare flag bit b7 as
   `t_is_boot`; the advertising blob's `minutes` reads 0 when the origin is boot, which is what it
   already means to a reader expecting a cook.
3. `cook_ring_reset()` still runs on session open, so a cook's chart never begins with pre-cook
   samples at negative or unrelated times.
4. The app treats a boot-origin `t` as unplottable against cook time and renders instrument mode's
   sparkline from the `recent` window only.

Four wire surfaces, one host test each. Without it, the product cannot do the thing the owner asked
for.

### 13.7.7 State names an average user can understand

The glass must never print a wire identifier. One table, `k_user_state[]` in `app_ui_render.c`:

| Internal | On the glass |
|---|---|
| `APP_NET_STATE_AP_STARTING` | `starting its own network` |
| `APP_NET_STATE_STA_CONNECTING` | `joining <ssid>` |
| `APP_NET_STATE_FALLBACK_AP` | `couldn't join <ssid> — hosting instead` |
| `SMOKE_X_UNPAIRED` | `no thermometer yet` |
| `SMOKE_X_SYNC_RECEIVED` | `found it — waiting for a reading` |
| `SMOKE_X_CONFIRMED` | `reading Smoke X 3F91` |
| `pit_out_of_band` | `PIT OFF TARGET` / `243°F, band 225–275` |
| `target_reached` | `BRISKET IS READY` / `203°F` |
| `pit_crash` | `PIT CRASHED` / `178°F and falling` |
| `probe_detached` | `PROBE 2 UNPLUGGED` |
| `base_lost` | `LOST THE SMOKE X` / `silent 14 min` |
| `battery_low` | `BATTERY LOW` / `11%` |
| `storage_low` | `STORAGE NEARLY FULL` / `97%` |
| `system_fault` | `SOMETHING'S WRONG` / `restart the bridge` |

Today the alarm overlay renders `bridge_alarm_rule_str()` with underscores swapped for spaces, so the
glass reads `pit out of band` and `smoke x alarm`, and device-scope alarms skip the value rows
entirely — an inverted `A L A R M` band, two words, and two blank rows. `alarm_severity` is carried
in the snapshot and never written or drawn.

---

## 13.8 Protocol and API changes

**One coordinated bump, one regeneration, one owner.** Every change lands in a single commit that
bumps `device_info.api` from 1 to 2, regenerates all four codegen outputs
(`protocol/gen/record_gen.h`, `protocol/gen/records.g.dart`,
`tools/bridge_protocol/lib/records.g.dart`, `app/lib/data/dto/records.g.dart`), and updates
`openapi.yaml` and `ble-gatt.md` in the same diff. CI already fails on a codegen diff.

**OWNER of `records.yaml` + `openapi.yaml` + `ble-gatt.md`: TBD — assign before W8.** Four generated
files and three hand-written specs have been edited independently by three separate efforts; without
a named owner the bump lands three times against three schemas.

**Storage record layouts do not change.** `meta.version: 1` governs on-flash files; nothing here
touches a storage record, so stored cooks remain readable.

### 13.8.1 Version negotiation

`device_info` grows 40 B → 44 B, additive under the file's own "unknown trailing bytes are ignored"
rule, gaining a `feat: u32` bitfield. **App contract:** `AppEnv` reads `device_info` once per
connection into `BridgeFeatures`; every new call site is gated on its bit. A v1.0.0 bridge returns
40 B → `feat = 0` → the app falls back to current behaviour and, where a feature is load-bearing
(`pair_status`), shows *"Your bridge needs a firmware update to do this — [Update]"* rather than
failing. Mirror `feat` in the mDNS TXT record and in `/status.device.feat`.

### 13.8.2 New BLE characteristic `pair_status` — read + notify, encrypted

The blocker for hop 2, and at ~64 B of heap the cheapest high-value item in this document.

```yaml
# protocol/records.yaml — enums
  pair_state:            # 1:1 with smoke_x_ctrl_state()
    unpaired: 0
    listening: 1         # bounded listen window open
    heard: 2             # SYNC_RECEIVED — beacon decoded, ACK sent
    confirmed: 3
  pair_fail:
    none: 0
    timeout_no_beacon: 1
    timeout_no_state: 2
    ack_failed: 3
    garbled: 4

# protocol/records.yaml — ble_payloads
  pair_status:           # char 0x000A, read + notify, fixed 20 B
    size: 20
    fields:
      - { name: ver,         type: u8, const: 1 }
      - { name: state,       type: u8, enum: pair_state }
      - { name: elapsed_s,   type: u16 }
      - { name: remaining_s, type: u16 }
      - { name: device_id,   type: char, count: 8 }
      - { name: num_probes,  type: u8 }
      - { name: rssi,        type: i8 }
      - { name: reason,      type: u8, enum: pair_fail }
      - { name: garbled,     type: u8 }
      - { name: _pad,        type: u8, count: 2 }
```

20 B fits the default ATT MTU — the same constraint `live_state` was sized against. Notified on
**state change only**; the phone counts seconds locally (§13.2.2).

### 13.8.3 BLE additions and corrections

| Change | Note |
|---|---|
| `live_state.flags` **b5 `base_lost`**, **b6 `alarm_critical`**, **b7 `t_is_boot`** | spare bits exist; without b5, BLE is structurally blind to base loss. b7 is §13.7.6's origin marker. |
| `live_state` trailing **`u8 sample_age_s`** (255 = ≥255/never), 16 B → 17 B | the data-age clock on the BLE lane |
| `net_status` trailing **`u8 reason`** | §13.2.3; `app_net.c:283-285` starts carrying `wifi_event_sta_disconnected_t.reason` through |
| `control_op` **14 `set_setup_stance`** — `u8 hop (0=exit,1..3)`, `u8 substate` | 4 B, inside the frozen 30 B envelope; expires at 120 s, owned by `app_ui`'s tick |
| `control_op` **15 `forget_bond`** | today the only way to free a slot is `factory_reset`, which also wipes every setting and cook |
| Advertising blob **b5 `bonds_full`**, **b6 `fallback_ap`** | lets the app grey a row and explain *before* connecting |
| `mark` body gains a leading **`u8 probe`** (0 = whole cook) | 27 B of the 28 B budget; today `op_mark` hardcodes probe 0 |

Ops 14–15 follow the additive rule: appended, never renumbered; a v1.0 bridge answers `invalid`.

**`live_state` is a *fixed-size* record.** `records.yaml:279-282` states that `device_info`,
`wifi_scan_ctrl` and `live_state` are fixed, with `live_state` at 16 B ≤ 20 B so it survives a failed
MTU negotiation. Growing it to 17 B is **not** covered by the trailing-bytes convention. Both
directions need an explicit rule, mirroring `device_info`'s short-read behaviour: *a reader accepts
16 B or 17 B; a 16 B read implies `sample_age_s = 255` (unknown); a reader must not reject a longer
record.* Write it into `ble-gatt.md` next to the fixed-size list.

**The `op_echo` collision needs two fixes, not one.** `op_echo` is typed `enum: control_op`
(`records.yaml:419`) and `control_op` is 1..13 (`:96-110`), so a sentinel like `0xF0` **will not
generate** — either add a reserved pseudo-op member to the enum or retype the field, and state which.
And even then, the three `wifi_config` rejection paths still answer `OP_ECHO_NONE = 0`
(`app_ble_ctrl.c:20`, rejections at `:67`, `:71`, plus the generic ones in `app_ble_core_write` at
`:384`, `:389`), so an app awaiting a new echo value receives **no result at all** for a rejected
config and falls to the 10 s timeout — the exact crash path §13.2.3 is fixing. **Therefore the
app-side `_ctrlLock` is the primary fix and the echo value is the secondary**, and the rejection
paths must be updated to echo the op they are rejecting.

### 13.8.4 HTTP additions

| Change | Path |
|---|---|
| **`POST /api/v1/alarms/ack`** `{alarm_id}` → the resulting alarm state | Ack is WebSocket-only today, and `HttpTransport.control` writes to `_ws?.sink` un-awaited, so a null socket silently discards a 3 a.m. silence |
| `/live` emits `name`/`role`/`target_f10` for **all four** probes regardless of attachment; adds `sample_age_s` and `t_origin`; renames the emitted `alarm_enabled` to `base_alarm_active` | `app_api_core.c:512-547`. Identity is configuration, not telemetry — and the app currently round-trips the base's *armed* flag back as config |
| Bounded `pending_start`: 60 s deadline, `pending_expires_s` on `/status`, WS `pending`/`pending_failed`, **409 `base_lost`** when unpaired or silent | Today `POST /sessions` returns 200 and may open a cook hours later when someone switches the base on |
| Split `POST /pairing/sync` from unpair: **`POST /pairing/listen?window_ms=`** non-destructive, **409 `session_active`** while a cook is open; `GET /pairing` returns the full state including `last_packet_s_ago` and `base_lost`; both POSTs return the pairing state as the spec already declares | `app_api_core.c:600-626, 1268-1282` |
| `/status.net` gains `mode`, `state`, `ssid`, `reason`; `/status.pairing.paired` derives from `smoke_x_ctrl_state()` rather than NVS (`app_api_core.c:306-307`) | so `/status` and `/pairing` cannot disagree during a watchdog re-scan |
| WS `session` frame carries `reason` (`stopped`/`detached`/`unpaired`/`cap`), a real `renamed` action, and `continues_session_id` on the 36 h split | `app_api.c:557-563`; today every non-start maps to the literal `"ended"` |
| `PATCH /sessions/{id}` honours `probes[]`, `pull_target_f10[4]` and `plan_id`; `POST /sessions` accepts `{name, probes[]}` and returns 201 | `app_api_sessions.c:86-98, 526-545` |
| `hello` carries a state snapshot; `subscribe` accepts `since_t` and replays ring samples above it | `app_api_ws.c:83-103, 150-160` |
| **`GET /api/v1/sessions/{id}/marks`** | closes the write-only mark path (§13.5.4) |
| **`POST /api/v1/identify`** | §13.7.4 |
| Document `GET /api/v1/debug/power` (routed at `app_api_core.c:1369-1372`, absent from the spec) | |

**Deferred on the heap budget:** the WebSocket client cap stays at **2** (§13.6.4 H9).

### 13.8.5 The parser fix that gates every write path

`app_api_core.c:841-842`, verified:

```c
while ((p = strstr(p, "{\"n\"")) != NULL ||
       (p = strstr(probes, "{ \"n\"")) != NULL) {
```

The second alternative restarts from `probes` on every iteration. Any pretty-printed body — curl,
Postman, a Home Assistant integration — re-finds the first object forever: the httpd task spins and
the same NVS keys are rewritten in a tight loop. The route is **unauthenticated by default**
(`auth_ok` returns true on an empty token, `:189-191`) with `Access-Control-Allow-Origin: *`. The
shipped Flutter app is safe only because `jsonEncode` emits compact JSON.

**Fix:** one tolerant scan — advance past each parsed object and search from there for `{` followed
by optional whitespace and `"n"`. Host test with a pretty-printed body. **Hard prerequisite for every
settings write path in this document.** Two adjacent fixes in the same function: return
400 `invalid_field` when a string overruns (today a >16-char probe name is silently dropped with a
`200 {"ok":true}`), and clamp `display_timeout_s` to `{0} ∪ [15,600]`.

### 13.8.6 Heap budget

**The floor is ≥ 80 KB** (`docs/hardware-verified.md:450`), which also records: *"if it does [bite],
the answer is not 'lower the bar'."* V3a.1 measured `min_free_heap` at **78.2 KB** — already under,
as a *level* problem rather than a leak, driven by NimBLE costing ~90–100 KB against
[01 §1.4](01-hardware.md)'s 35–45 KB allowance.

Owner decision: **additions stay net-neutral; the costly items wait for headroom.**

| Addition | Est. heap | Status |
|---|---|---|
| `pair_status` characteristic | ~64 B | **lands** |
| `live_state` +1 B, `net_status` +1 B, flag bits | 0 | **lands** (existing static buffers) |
| ops 14/15 + stance struct | ~32 B | **lands** |
| QR encoder | ~0 heap, ~3 KB flash, ~400 B stack | **lands** (fixed version-3, no allocator) |
| Framebuffer dirty-check scratch | +1 KB `.bss`, −heap pressure | **lands**; it *removes* bus load |
| AP_STARTING / reconciliation / watchdogs | 0 | **lands** (control flow only) |
| Second tracked BLE connection | ~1.2 KB | **deferred** |
| CCCD tracking bitmap | ~16 B | **deferred** with the above |
| WebSocket clients 2 → 4 | ~4–6 KB | **deferred** — H9 ships "Take over" instead |

**Gate:** every firmware wave ends with `/api/v1/debug/tasks` and `min_free_heap` recorded in
`docs/hardware-verified.md`. A wave that lowers `min_free_heap` does not merge until the regression is
found. A separate heap-reduction package (NimBLE bond count, buffer pools) is the prerequisite for
the deferred rows and is scheduled in [M8](../tasks/M8-ux-rearchitecture.md).

---

## 13.9 Decisions taken, and questions still open

### 13.9.1 Decided

| # | Decision | Rationale |
|---|---|---|
| U1 | **Instrument mode is first-class.** Temperatures are visible with no cook started. | Owner requirement; drives §13.7.6, which is otherwise easy to defer forever |
| U2 | **Heap additions stay net-neutral**; multi-client WebSocket and the second BLE connection wait for a heap-reduction package | The 80 KB floor is already failing and the repo explicitly refused to lower it |
| U3 | **Food-safety floors are enforced in `CookPlan`'s constructor**, cited to USDA/FSIS, and **hazard-classed** so whole-muscle red meat has no floor | Owner decision; a 125 °F ribeye is a preference, a 150 °F chicken breast is not |
| U4 | **Dark-only ships.** `SmokeTheme.light` is deleted; a daylight *contrast profile* of the dark set replaces it | A white screen outdoors is worse than a high-contrast dark one; see [14 §14.3.3](14-design-system.md) |
| U5 | **Both hop 2 and hop 3 are skippable** and resumable, with a persistent card until done | A bridge with no base is a logger with nothing to log; a bridge with no Wi-Fi is BLE-only. Neither is a reason to trap the user in setup |
| U6 | **iOS is out of scope for v1.0** | There is no `app/ios/` and `pubspec.yaml:1` says so. See below for what this costs |
| U7 | **English-only for v1.0**, with every string extracted to `copy/` files | ARB becomes mechanical later; the OLED's 21-column budget makes device-side localisation a real project |

**U6 in detail — what an iOS port would have to redesign, not port:** `FlutterBluePlus.turnOn()` is
Android-only; the `ACTION_*` settings intents have no iOS equivalent (iOS can only open the app's own
pane); the entire `SetupPasskey` screen assumes an app-initiated bond with an app-owned countdown,
and iOS has no `createBond` — the pairing sheet is OS-driven off the first encrypted read and cannot
be timed, cancelled, or detected as absent; the "remove this bond in Bluetooth settings" recovery is
impossible; `WifiNetworkSpecifier` + `bindProcessToNetwork` become `NEHotspotConfiguration` plus a
paid entitlement; and the foreground service has no counterpart. This is a project, not a build flag.

### 13.9.2 The three bench facts

Hop 2's copy is written and its constants are isolated (§13.2.2), but the sync window duration, the
exact hold duration, and the base's own confirmation remain **[?]**. They are M8 W0 and they change
three constants, not any screen.

### 13.9.3 Still open

**Q1 — Fit the piezo, or ship LED-only?** `app_ui_buzzer_on()` exists, is called from nowhere, and
the part is unfitted on every board. Every competitor in this category has an audible alarm on the
receiving hardware. Cost: one BOM line, one GPIO7 net, ~0.5 day of firmware. Consequence of not
fitting: a phone-dead, out-of-range user gets a blinking LED and nothing else at 3 a.m. **This is a
hardware decision with a UX consequence and it needs an answer before the next board spin.**

**Q2 — Does an unacked critical alarm override `led_enabled = OFF`?** Today it does not, deliberately
([07 §7.5](07-display-and-controls.md), `app_ui_led.c:64-70`). With no buzzer fitted, "the buzzer is
where an alarm still shouts" is no longer true. Reversing it is defensible; doing so silently is not.
Tied to Q1.

**Q3 — Two or three BLE bond slots, and what happens at the wall?** With op 15 a user can free a slot
from a phone that is still paired. A household that loses all three phones has only double-tap
RESET → AP mode → the QR. Acceptable, or should bonds be freeable from an AP-mode web path that does
not exist and would be its own project?

**Q4 — Named owners.** `protocol/` (§13.8) and the plain-language copy review (§13.3.7) are both
recorded as **TBD**. Both are merge gates. A gate with no named reviewer is a comment.
