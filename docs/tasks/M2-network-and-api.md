# M2 — Network and API

**The milestone where the two tracks meet.** Everything the bridge has recorded since M1 becomes
reachable, and the app talks to real firmware for the first time — until now the A track has only
ever spoken to `tools/sim`. The contract work of M0 is what makes this a rendezvous rather than a
collision: both sides already parse the same fixtures, so M2 is wiring, not negotiation.

**Exit gate** ([M2 outline](M2-M6-outline.md), [11 §11.1](../design/11-roadmap-and-risks.md)):

- `curl` retrieves a 24-hour cook as CSV **and** as raw records
- A WebSocket client receives live samples
- AP↔STA switching works from `curl`
- **Free heap ≥ 150 KB with everything running**

> **Gate caveat, stated now rather than discovered later:** "everything running" at M2 means
> everything M2 *has* — AP + httpd + WebSocket clients + LoRa RX + both LittleFS mounts. NimBLE does
> not exist until M3, so F9.13 closes V1.6's deferred heap box **provisionally**, with the
> [01 §1.4](../design/01-hardware.md) NimBLE allowance subtracted on paper. V3a re-measures with BLE
> real. If the paper margin is already gone at M2, that is a design conversation before M3 starts —
> not after.

35 tasks — **31 `board: no`, 4 `board: yes`**. The board tasks (F8.8, A14.4, F9.12, F9.13) form
**one bench sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)) at the end of the
milestone, after every host- and sim-verifiable box is closed. The F track (F8 → F9 → F4) and the
A track (A5 → A7 → A14's Dart half) run in parallel; the sitting is where they join.

---

## F8 — app_net

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** F8 + A14 is the classic
> "works on my phone" trap. The phone probes `connectivitycheck.gstatic.com`, our AP has no
> internet, Android keeps the default route on cellular, and requests to `192.168.4.1` vanish.
> **Both** mitigations — the device-side captive shim (F8.5, F8.7) *and* the app-side network
> binding (A14.2) — are required; neither alone is sufficient, and OEM variance means the bench
> proof (A14.4) is the only test that counts. Expect one rework pass after the sitting. A second,
> smaller flag: the mDNS component is a managed dependency in current IDF — pin a version that
> builds in both the `release-v5.4` CI container and the local v6.0.2 install.

Follow the established component shape: a pure `app_net_core` state machine over injected ops
(start/stop AP and STA, scan, timers, event publish), with the `esp_wifi`/`esp_netif` glue kept
thin — the same split `smoke_x_ctrl` and `app_lora_core` use, so the whole supervision logic runs
in the host suite.

### F8.1 app_net: implement the mode state machine as a pure core

- **blocked-by:** F7.2, F1.5 · **verify:** H · **board:** no
- **design:** [05 §5.1, §5.2](../design/05-connectivity-and-provisioning.md), [03 §3.1](../design/03-firmware-architecture.md)

The §5.2 precedence order: recovery window / double-reset forces `AP` for this boot only (stored
config untouched — the flag comes from F1.5's boot sequence), otherwise stored `net/mode` applies.
All configuration through `app_config_store` — never NVS directly — and mode changes arrive as
change notifications, not polling. Publishes `BRIDGE_EVT_NET` transitions on the event bus.

**Done when:** a table test drives every §5.2 selection path on the host, and a forced-AP boot
leaves `net/mode` unmodified.

### F8.2 app_net: implement STA supervision with backoff and the fallback guard

- **blocked-by:** F8.1 · **verify:** H · **board:** no
- **design:** [05 §5.4](../design/05-connectivity-and-provisioning.md)

The §5.4 tree: 30 s connect budget, then **start AP so the device is never unreachable**, then
background STA retry at 1, 2, 5, 10, 10, 10… min. Switch back to STA **only if** no station is
associated to the AP *and* no HTTP/WebSocket client has been active for 60 s — the guard needs an
activity signal, so the core takes a `last_client_activity` query op that F9's glue feeds. The
reference falls back to AP and gives up forever; the backoff self-heals a router reboot mid-cook.

**Done when:** a fake-clock host test walks timeout → AP → retry → guarded switchback, including
the guard holding while a client is active and releasing 60 s after it goes quiet.

### F8.3 app_net: implement the AP parameter set

- **blocked-by:** F8.1, F7.3 · **verify:** H · **board:** no
- **design:** [05 §5.3](../design/05-connectivity-and-provisioning.md)

SSID `SmokeBridge-XXXX` from the last two Wi-Fi MAC bytes; PSK read from `net/ap_psk` (generated at
F7.3 — **never regenerated here**, only on factory reset); `192.168.4.1/24`, DHCP pool `.2–.20`,
`max_connection = 4`; channel chosen as the least congested of 1/6/11 from a startup scan, with the
scan results injected so selection is host-testable.

**Done when:** the parameter block is asserted against the §5.3 table, channel selection is
table-tested over synthetic scan results, and the PSK survives an AP restart unchanged.

### F8.4 app_net: implement deferred reconfiguration

- **blocked-by:** F8.1 · **verify:** H · **board:** no
- **design:** [05 §5.4](../design/05-connectivity-and-provisioning.md), [06 §6.2](../design/06-device-api.md)

An `apply_later` primitive: accept a validated network config, arm a ~500 ms timer, then tear down
and re-init the interface — so the HTTP reply (F9.7) or the future BLE `result` (M3) flushes before
the network it rode dies with it. The reference discovered this the hard way; keep it. A second
config arriving inside the window supersedes the first.

**Done when:** a host test proves the apply fires after the delay, not before, and a superseding
config wins.

### F8.5 app_net: implement the DNS hijack responder

- **blocked-by:** F8.3 · **verify:** H · **board:** no
- **design:** [05 §5.8.1](../design/05-connectivity-and-provisioning.md)

The UDP/53 half of the captive shim: in AP mode, answer **every** A query with `192.168.4.1`.
Build it as a pure codec — `dns_shim_respond(query_bytes) → response_bytes` — with the socket task
as thin glue, so malformed queries, AAAA queries (empty `NOERROR`, not `NXDOMAIN` — an `NXDOMAIN`
makes some resolvers fail over to IPv6 and skip us), and odd classes are all host-testable from
byte fixtures. Runs only while AP mode is active.

**Done when:** fixture queries (A, AAAA, malformed, wrong class) produce byte-exact responses on
the host, and the responder is provably down in STA mode.

### F8.6 app_net: implement mDNS registration and live TXT records

- **blocked-by:** F8.1 · **verify:** H · **board:** no
- **design:** [05 §5.5](../design/05-connectivity-and-provisioning.md)

Hostname `smokebridge`; `_smokebridge._tcp` and `_http._tcp` on port 80, registered in both modes
as soon as an interface has an address. The §5.5 TXT set — `id model fw api probes paired session
mode` — is what lets the app's picker say *"Smoke Bridge · 4 probes · cooking"* before connecting,
so it must be **live**: rebuilt on pairing, session, and mode transitions via the event bus, not
composed once at boot. TXT assembly is a pure builder; the IDF mdns component is glue (see the epic
flag about pinning its version).

**Done when:** the TXT builder matches the §5.5 table byte-for-byte for a matrix of states, and
each transition regenerates it exactly once.

### F8.7 app_net: implement the captive-portal probe endpoints

- **blocked-by:** F9.1, F8.3 · **verify:** H · **board:** no
- **design:** [05 §5.8.1](../design/05-connectivity-and-provisioning.md), [06 §6.2](../design/06-device-api.md)

The HTTP half of the shim, registered on F9's server: `/generate_204`, `/gen_204` → `204`;
`/hotspot-detect.html`, `/library/test/success.html` → Apple's success page; `/ncsi.txt`,
`/connecttest.txt` → the Microsoft strings. Answering `204` is what makes Android mark the network
validated, route traffic to us, and drop the "sign in" nag. All bodies are string constants shared
with `tools/sim`'s implementations, so both serve identical bytes. The config-gated true-captive
variant (302 to a setup page) exists but defaults **off**.

**Done when:** every probe path returns the exact §5.8.1 status and body (byte-compared against the
sim's), and the 302 variant only engages via its config flag.

### F8.8 bench: bring the network up on the board

- **blocked-by:** F8.2, F8.3, F8.5, F8.6, F8.7 · **verify:** B · **board:** yes
- **design:** [05 §5.3–5.5](../design/05-connectivity-and-provisioning.md), [01 §1.8](../design/01-hardware.md)

Part of the single M2 sitting. AP up with the generated PSK readable and a laptop pulling
`/api/v1/status` at `192.168.4.1`; STA joined to the home network with `smokebridge.local`
resolving and `dns-sd -B _smokebridge._tcp` showing the live TXT records; then the supervision
proof — take the router down mid-connection and watch fallback-to-AP, background retry, and the
guarded switchback behave exactly as the F8.2 host test predicted.

**Done when:** all three are recorded in `docs/hardware-verified.md`, including which Wi-Fi channel
auto-select chose and why.

---

## A14 — platform/network_binder

**Planned with F8 as one unit of work** ([M2 outline](M2-M6-outline.md),
[§12.8](../design/12-task-planning-notes.md)) — the epic flag above applies here verbatim. F8
builds the device half of the Android AP-routing mitigation; A14 builds the phone half; A14.4
proves them together and proves each is doing its share. The manual-IP escape hatch that always
works ships alongside them (A7.1), because OEM behaviour varies and the design refuses to make
discovery or validation the only path.

### A14.1 platform/network_binder: define the Dart channel API and fake

- **blocked-by:** A1.3 · **verify:** H · **board:** no
- **design:** [05 §5.8.1, §5.8.2](../design/05-connectivity-and-provisioning.md), [08 §8.8](../design/08-flutter-app.md)

A narrow `MethodChannel` surface: `bindToBridgeNetwork()` / `unbind()`, `joinAp(ssid, psk)` (the
`WifiNetworkSpecifier` one-tap join, credentials already known from provisioning), and a bound/lost
state stream. Ship a fake platform implementation alongside, so A7 and future onboarding logic test
against the contract without a device. Misuse (double bind, unbind without bind) has defined,
tested behaviour rather than platform-dependent luck.

**Done when:** the Dart API is fully exercised against the fake in `flutter test`, including the
misuse cases and the lost-network path.

### A14.2 platform/network_binder: implement the Kotlin side

- **blocked-by:** A14.1 · **verify:** H · **board:** no
- **design:** [05 §5.8.1, §5.8.2](../design/05-connectivity-and-provisioning.md), [08 §8.8](../design/08-flutter-app.md)

The ~120 lines from §5.8.1/§8.8: `NetworkRequest` with `TRANSPORT_WIFI` and
`NET_CAPABILITY_INTERNET` **removed**, `bindProcessToNetwork` in `onAvailable`, and the
`WifiNetworkSpecifier` join flow. Ours, not a package — we need exact lifecycle control, because
the failure mode of forgetting to unbind is *"the app has no internet anywhere, forever"*, which is
a one-star review with no reproduction steps. Unbind on leaving AP mode, on dispose, and on
`onLost`.

**Done when:** the debug APK builds with the channel wired, the Kotlin side answers A14.1's
contract test harness (same call/response vectors as the fake), and every unbind path is exercised
from the Dart lifecycle tests. The on-phone routing proof is A14.4 — this task closes on contract
conformance, not on faith.

### A14.3 app/android: write the manifest, permissions, and cleartext config

- **blocked-by:** A1.1 · **verify:** H · **board:** no
- **design:** [05 §5.8.3, §5.8.4](../design/05-connectivity-and-provisioning.md)

The network rows of the §5.8.3 matrix: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
`CHANGE_WIFI_STATE`, **`CHANGE_WIFI_MULTICAST_STATE`** (without it mDNS silently finds nothing —
the worst kind of bug), `NEARBY_WIFI_DEVICES` with `neverForLocation`, `ACCESS_FINE_LOCATION`
gated to API ≤ 12. Plus the scoped `network_security_config.xml` from §5.8.4: cleartext for
`smokebridge.local`, `192.168.4.1`, and the private ranges via base config — never a global
cleartext flag. The BLE and foreground-service rows land with A6 (M3) and A13 (M5), not here.

**Done when:** the build succeeds and a manifest test asserts the exact permission set and the
`neverForLocation` attributes, so a future dependency can't quietly add a location prompt.

### A14.4 bench: prove the Android AP-routing mitigations, separately and together

- **blocked-by:** A14.2, A14.3, F8.8 · **verify:** B · **board:** yes
- **design:** [05 §5.8.1](../design/05-connectivity-and-provisioning.md)

Part of the single M2 sitting, on the real phone with **cellular data ON** — that is the whole
point. Four checks: (1) shim active, binding active: Android validates the network, no "sign in"
nag, requests reach `192.168.4.1`. (2) Shim deliberately disabled via its config flag: the binding
**alone** still routes — proving A14.2 carries its half. (3) Binding skipped (fake side loaded):
the shim **alone** still routes — proving F8.5/F8.7 carry theirs. (4) Manual-IP entry works
regardless, and leaving AP mode unbinds with phone-wide internet restored. Record OEM, Android
version, and any deviation — this is the evidence §12.8 says to expect needing.

**Done when:** all four are recorded in `docs/hardware-verified.md` with the phone's identity, and
any OEM quirk found is captured as a follow-up task rather than a shrug.

---

## F9 — app_api

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md), [§12.9](../design/12-task-planning-notes.md)):**
> the concurrency caps (`max_open_sockets = 7`, 2 WebSocket clients) fall out of a RAM budget that
> is still *estimates* — F9.13 is where they become measurements. And one API question is open:
> **[RESOLVED 2026-07-22 — it cannot.** `esp_http_server` completes the handshake before routing
> `.is_websocket` handlers, so the device accepts-then-closes with `1013 Try Again Later`; the sim
> keeps the pre-handshake `503`; `openapi.yaml` amended; both forms are `busy` to clients.]
> Original flag:
> whether `esp_http_server` can refuse a WebSocket upgrade with the contract's JSON `503 busy`
> **before** completing the handshake. If it cannot, the fallback is accept-then-close with a
> `1013 Try Again Later` close frame, and `openapi.yaml` gets amended to say so. Spike this early
> in F9.9, not at the end.

**F9 inherits a structural rule, not an optimisation** ([M2 outline](M2-M6-outline.md)): no handler
ever materialises a full response in RAM; history streams from flash in ≤ 2 KB chunks. This is the
direct lesson from the reference's 16 KB `json_str` ceiling — an X4 starts returning `500` at
roughly 600 records (~5 h). F5.10 built the streaming read path precisely so F9 has nothing to
invent; F9.2 builds the matching write half, and everything else is handlers.

Same component shape as F8: a pure `app_api_core` (routing, parameter parsing, body assembly over
injected state) with the `esp_http_server` glue thin, so the entire contract runs in the host
suite. `tools/sim` is the reference implementation for every response shape — where this file says
"matches the sim", it means byte-for-byte against `protocol/fixtures/http/` and the sim's output.

### F9.1 app_api: implement the httpd skeleton, router core, and error envelope

- **blocked-by:** P2.2, F8.1 · **verify:** H · **board:** no
- **design:** [06 §6.1](../design/06-device-api.md)

Server config from the contract: `max_open_sockets = 7`, request bodies capped at 8 KB → `413
body_too_large` (OTA exempt, moot until M6), CORS `*` on everything. The router core resolves
method + path → handler id + parsed path/query params, pure and host-testable. The
`{ "error": { code, message, detail } }` envelope builder, `404 not_found` for unknown API routes,
and the optional bearer gate: when `device/api_token` is set, every `/api/v1/*` request without the
token gets `401 unauthorized` — **JSON, like every other response, success or failure.**

**Done when:** the router resolves every path in the [06 §6.2](../design/06-device-api.md) table on
the host, unknown routes and bad methods produce the fixture envelopes, and the auth gate is
table-tested (unset → open; set → 401 without or with a wrong token).

### F9.2 app_api: implement the streaming emit layer

- **blocked-by:** F9.1 · **verify:** H · **board:** no
- **design:** [06 §6.1](../design/06-device-api.md), [04 §4.8](../design/04-storage-and-history.md)

The no-materialisation rule made structural: a chunked emitter over an injected sink
(`httpd_resp_send_chunk` on device, a byte buffer in tests) with a single ≤ 2 KB stack buffer —
JSON fragments, raw bytes, and CSV rows all flow through it, and **every** F9 handler uses it.
There is no other way to send a body; that is what makes the rule unbreakable rather than
remembered.

**Done when:** a synthetic 100 KB body streams through the 2 KB buffer with peak usage asserted,
and the emitter API makes "build the whole body first" impossible to express without going around
the component.

### F9.3 app_api: implement GET /status and GET /live

- **blocked-by:** F9.2, F5.6, F3.7, F6.1 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md)

`/status` assembles the one-round-trip dashboard body from what M1 already built: `smoke_x_ctrl`
state and stats, the `cook_store` index and active session, `app_config`, `app_time`, `app_net`
status, and injected system info (heap, uptime, reset reason). The `ble` and `power` sections emit
honest degenerate values until M3/M5 (`advertising: false`, no fabricated SoC) — shape-complete,
never invented. `/live` serves probe state plus the `recent` window straight from `cook_ring` —
no flash read — with `window` capped at 7200 and `format=json|bin`. Detached probes are `null`,
whole-window-detached series are `null`. **Never `0`.**

**Done when:** the host harness renders `/status` shape-identical to `status.json` and `/live`
byte-identical to `live-two-detached.json` given the seeded state, and no code path can turn a
`BRIDGE_TEMP_DETACHED` into a number.

### F9.4 app_api: implement the sessions group

- **blocked-by:** F9.2, F5.5, F5.9 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [04 §4.6](../design/04-storage-and-history.md)

`GET /sessions` streamed from the in-RAM index (64 sessions must not need a 64-entry array of JSON
objects in RAM — the emitter earns its keep immediately); `POST /sessions` as the explicit-start
path into F5.4's lifecycle (`409 session_active` if one is open); `GET/PATCH/DELETE /sessions/{id}`
with PATCH covering rename, probe names/roles/targets, and pin, and DELETE refusing the active
session; `POST /{id}/stop`; marks `GET`/`POST` riding F5.9 (UTF-8 truncation already handled in the
store — the handler validates, it does not re-implement).

**Done when:** every verb is host-tested against a seeded store double, and each error path
(`session_not_found`, both `session_active` variants) returns its exact fixture envelope.

### F9.5 app_api: implement streamed GET /sessions/{id}/samples

- **blocked-by:** F9.2, F5.10 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [04 §4.8](../design/04-storage-and-history.md)

The workhorse. All of `from/to/stride/bucket/agg/format/probes`, implemented as thin sinks over
`cook_store_read` — the seek-not-scan range logic, bucketing, and minmax already exist and were
verified in M1; this task is *formatting*. `format=bin` streams raw 16-byte records;
`json` emits the bucketed series with the `gaps` array from `t` deltas > 45 s; `ndjson` one object
per record; `csv` with the `t_s,iso8601,p1_f…` header and **empty fields, not `0`,** for detached.
Invalid parameter combinations get `400 invalid_field`, unknown ids `404 session_not_found`.

**Done when:** the 24-hour fixture at `bucket=90&agg=minmax` returns 960 buckets matching
`samples-bucketed-gaps.json` in shape, `format=bin` is byte-identical to the stored records, a
parameter matrix matches `tools/sim` byte-for-byte (via F9.11's harness), and peak buffer use
during a full-session stream stays under the F9.2 bound.

### F9.6 app_api: implement the pairing group

- **blocked-by:** F9.1, F3.6 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [02 §2.4](../design/02-smoke-x-protocol.md)

`GET /pairing` reports the `smoke_x_ctrl` state machine faithfully — including `SYNC_RECEIVED` as a
distinct, visible state, because "pairing…" and "paired" are different answers to a user standing
at the smoker. `POST /pairing/sync` enters scan mode; `POST /pairing/unpair` calls
`smoke_x_ctrl_unpair` — which M1 already proved touches nothing outside this device. Error
semantics mirror the sim (`409` where state forbids the transition).

**Done when:** a host test drives payload fixtures through `smoke_x_ctrl` and watches the API
reflect each transition, and both error envelopes match their fixtures.

### F9.7 app_api: implement the config groups and POST /time

- **blocked-by:** F9.1, F8.4, F6.1 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [05 §5.4](../design/05-connectivity-and-provisioning.md)

`config/wifi`: POST validates, replies with `accepted / applying_in_ms / expect` (the AP shape
carrying the generated SSID/PSK/IP), **then** hands off to F8.4's deferred apply — reply first,
reconfigure after. GET returns current network config and the AP PSK, and **never a stored STA
password** — grep-proof this, don't intend it. `config/device`: units, display, LED, retention,
probe metadata; `vbat_actual_mv` is *persisted* (the cal keys exist in the schema) but the solve
against an ADC reading is F12's (M5) — accepting it now keeps the contract complete without
faking a calibration. `config/alarms`: persist and echo the rules blob; the engine that reads it
is M5's F13. `POST /time` feeds `app_time` as a `phone` source — which triggers F6.2's header
back-patch for a clock-invalid session, already built and tested; the API just delivers the news.

**Done when:** both wifi accept shapes match `config-wifi-accept-ap.json` /
`config-wifi-accept-sta.json` byte-for-byte, no GET in the group can emit `sta_psk`, and a
`POST /time` against a clock-invalid open session is observed back-patching via the host harness.

### F9.8 app_api: implement GET/POST /radio

- **blocked-by:** F9.1, F2.3 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [02 §2.5](../design/02-smoke-x-protocol.md)

GET reports the §1.5 parameter block plus link stats from `smoke_x_ctrl_stats` — RSSI/SNR, the
counters, the interval histogram that turns "it seems flaky" into a number. POST is the advanced
escape hatch: range-check any frequency against 902–928 MHz **through F2.3's existing guard**
(reject without retuning), and refuse changes that would silently break a live pairing.

> **Uncertainty flag:** exactly which parameters POST may legitimately mutate on a *paired* bridge
> is not pinned down — the protocol fixes SF/BW/CR, and frequency is pairing state. Implement the
> conservative reading (mirror `tools/sim`, reject the rest with `invalid_field`) and record the
> question in [06](../design/06-device-api.md) rather than inventing semantics here.

**Done when:** GET matches the sim's `RadioInfo` shape, and a host test proves an out-of-band
frequency is rejected without touching the radio seam.

### F9.9 app_api: implement the WebSocket fan-out

- **blocked-by:** F9.1, F1.3 · **verify:** H · **board:** no
- **design:** [06 §6.3](../design/06-device-api.md)

The push path: a client registry hard-capped at **2**, with the third upgrade refused `503 busy`
(spike the pre-handshake question from the epic flag **first**); `hello` then the current `sample`
immediately on connect so a client has state without a `GET`; the full §6.3 frame set fanned out
from the `bridge_event` bus; `subscribe` topic filtering; server ping every 30 s, drop after two
missed; client `ping` and `ack_alarm` handled. Wi-Fi power save drops to `WIFI_PS_NONE` while a
client is connected and returns to `MIN_MODEM` 60 s after the last leaves — via an `app_net` op,
not a direct `esp_wifi` call. Frame builders and the registry are pure and host-tested; the
`httpd_ws` glue is thin.

**Done when:** frame builders byte-match the sim's frames for identical seeded state, the cap and
two-missed-ping drop are host-tested on a fake clock, and the busy refusal (whichever mechanism the
spike settles on) is asserted with its documented body or close code.

### F9.10 app_api: implement the www mount rule and built-in fallback page

- **blocked-by:** F9.1, F1.2 · **verify:** H · **board:** no
- **design:** [06 §6.4](../design/06-device-api.md), [03 §3.5](../design/03-firmware-architecture.md)

The D13 rule, exactly: attempt to mount `www` with **format-on-fail disabled** — the partition has
been deliberately unformatted since F1.2 and *must stay that way*; an accidental auto-format here
would be a silent decision reversal. Serve static content only if the mount succeeds *and*
`index.html.gz` exists (gzip + cache headers per §6.4); otherwise every unmatched `GET` returns a
small built-in page pointing at the app, from a string constant. The captive probes (F8.7) answer
regardless.

**Done when:** the routing logic is table-tested (mounted-with-index → static; everything else →
built-in page), the built-in page references nothing external, and the mount call provably cannot
format.

### F9.11 app_api: run the contract conformance suite

- **blocked-by:** F9.3, F9.4, F9.5, F9.6, F9.7, F9.8, F9.9, F9.10, F4.5, F4.6 · **verify:** S · **board:** no
- **design:** [10 §10.2, §10.5](../design/10-repo-tooling-and-testing.md), [06](../design/06-device-api.md)

The drift guard for the whole epic: a harness that boots `app_api_core` with state doubles seeded
identically to `tools/sim`, replays every fixture in `protocol/fixtures/http/` plus a `/samples`
parameter matrix, and byte-compares against both the fixtures and live sim output — with volatile
fields (uptime, heap) masked by an explicit normalisation list, so nothing else can hide behind
"that field just varies". Firmware, sim, and app now break together on any contract change, which
is the entire point of P2.

**Done when:** the suite runs in CI against a spawned sim, every fixture passes, and a deliberate
one-field divergence in a handler turns it red.

### F9.12 bench: pass the exit-gate curl checks on the board

- **blocked-by:** F9.11, F8.8, T4.2 · **verify:** B · **board:** yes
- **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md), [M2 outline](M2-M6-outline.md)

Part of the single M2 sitting. Load a 24-hour cook onto the board — T4.2's replay stub build at
100×, or the real captures; no smoker required — then, from a laptop: pull it as CSV and as raw
records and verify both against the fixture pipeline; hold a WebSocket open through several live
samples; switch AP↔STA and back with `POST /config/wifi` from `curl`, riding the deferred apply
both ways. **This is three of the four exit-gate lines.**

**Done when:** the transcript (commands and outputs) is committed to the PR and the retrieved CSV
parses identically to the on-device records.

### F9.13 bench: measure free heap and stack watermarks with everything running

- **blocked-by:** F9.12 · **verify:** B · **board:** yes
- **design:** [01 §1.4](../design/01-hardware.md), [M2 outline](M2-M6-outline.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

The last task of F9, by design ([§12.9](../design/12-task-planning-notes.md)): with AP up, two
WebSocket clients streaming, a `/samples` export in flight, LoRa RX live, and both LittleFS mounts
active — log `free_heap`, `min_free_heap`, and every task's stack watermark, and compare against
the §1.4 budget line by line. The gate is **≥ 150 KB free** with the NimBLE allowance still
subtracted on paper (see the milestone caveat). Update `docs/hardware-verified.md`, closing V1.6's
deferred heap box provisionally, with V3a (M3) named as the re-measure.

**Done when:** the measured table is in `docs/hardware-verified.md` next to the budget. If the
margin is thin, **stop and have the design conversation** — shrinking caps or buffers ad hoc here
is explicitly not this task.

---

## F4 — Debug capture read-out

The read half of M1's capture work. F4.1–F4.3 have been collecting evidence in RAM and flash since
M1 — the pktring, the seen-set, the pinned novelty log — and until now the only way to get it off
the board is the serial console. These endpoints are what make [standing-work](standing-work.md)'s
"pull the novelty log after every cook" a 10-second habit instead of a cable hunt.

### F4.4 protocol: add GET /api/v1/debug/novelty to the contract and tools/sim

- **blocked-by:** P2.2, T3.1 · **verify:** S · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md), [10 §10.2](../design/10-repo-tooling-and-testing.md)

The contract gap found in planning: [06 §6.2](../design/06-device-api.md) and `openapi.yaml` carry
`/debug/packets` and `/debug/coredump` but **not** `/debug/novelty` — yet F4.3 built the file and
[10 §10.4](../design/10-repo-tooling-and-testing.md) promises it over HTTP. Specify it as
`text/plain`, the novelty-log lines verbatim (it is deliberately a plain-text format — pullable
and readable with no tooling), add a fixture, teach the sim to serve it from scenario state, and
note it in [06](../design/06-device-api.md).

**Done when:** the spec validates, the sim serves the fixture, and `protocol.yml` stays green.

### F4.5 app_api: implement GET /debug/packets and GET /debug/novelty

- **blocked-by:** F4.4, F9.2, F4.1, F4.3 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md), [10 §10.4](../design/10-repo-tooling-and-testing.md)

`/debug/packets` renders the pktring as JSON per the `DebugPackets` schema — `n` capped at 64,
newest last, raw payload plus RSSI/SNR/uptime per entry. `/debug/novelty` streams the F4.3 file as
`text/plain` through the F9.2 emitter — at 64 KB it is the second-largest body the API can produce,
and it must obey the same 2 KB rule as everything else.

**Done when:** the packets body byte-matches the sim for a seeded ring, and a full 64 KB novelty
file streams within the buffer bound.

### F4.6 app_api: implement GET /debug/coredump

- **blocked-by:** F9.1 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [03 §3.5](../design/03-firmware-architecture.md)

The coredump partition has existed since F1.2 (the 56 KB the app-slot alignment would have wasted).
No dump → `404 not_found` JSON; dump present → raw `application/octet-stream`. The partition reader
is injected, so both paths are host tests; the `esp_core_dump` glue is a dozen lines. With one
board and no debugger attached in the yard, a panic that leaves a retrievable dump is the
difference between a bug report and a mystery.

**Done when:** the 404 path matches its fixture and a synthetic dump streams back byte-identical
through the injected reader.

---

## T4 — Capture tooling

### T4.1b tools/lora: implement pull — fetch the ring and novelty log over HTTP

- **blocked-by:** F4.4, T4.1 · **verify:** S · **board:** no
- **design:** [10 §10.4](../design/10-repo-tooling-and-testing.md)

`dart run lora:pull --host <addr>`: fetch `/debug/packets` and `/debug/novelty`, archive the raw
pulls date-stamped, and feed them through T4.1's normaliser into `.loralog` staging under
`protocol/fixtures/lora/`. No serial cable, no reflash, no interrupting a cook — the tool that
turns [standing-work](standing-work.md)'s after-every-cook obligation into one command.

Two scope notes, decided rather than drifted into: the design names this `pull.py`, but T4.1's
normaliser landed as Dart (`bin/normalize.dart`) and one language owns the fixture tooling — this
is `bin/pull.dart`, and [10 §10.4](../design/10-repo-tooling-and-testing.md) gets a one-line
correction. And the `.raw` fetch the design mentions is **omitted**: the opt-in raw writer was
never built in M1 (see the not-in-M2 table), so there is nothing to fetch.

**Done when:** against `tools/sim`, one invocation produces a `.loralog` the existing corpus tests
accept without hand-editing, and re-running is idempotent.

---

## A5 — HttpTransport

The A track's half of the rendezvous. `BridgeTransport` (A3.1) and the behavioral suite around
`MockTransport` (A3.3) already define what a transport must *do*; `wire_reader` already parses the
records; the sync engine (A4.3) already consumes the interface. A5 is the third implementation
sliding under all of it — which is exactly why the interface exists.

### A5.1 data/transport: implement HttpTransport over REST

- **blocked-by:** A3.3, T3.2, P2.3 · **verify:** S · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md)

`dio` with per-request timeouts and cancel tokens. `status()`, `live()`, `sessions()` map the JSON
bodies to the existing entities; `samples()` requests `format=bin` and parses the streamed 16-byte
records through the `wire_reader` path — `rec_len`-honouring, sentinels to `null`, batches emitted
as they arrive rather than buffered whole (24 h ≈ 46 KB, but the discipline matters at the `long`
scenario's 54 days). The error envelope maps to typed failures by `code`, so callers switch on
meaning, never on strings or status ints.

**Done when:** the MockTransport behavioural suite runs green against `HttpTransport` pointed at
`tools/sim` — same tests, both transports — and every `error-*.json` fixture maps to its typed
failure.

### A5.2 data/transport: implement the WebSocket event stream

- **blocked-by:** A5.1, T3.3 · **verify:** S · **board:** no
- **design:** [06 §6.3](../design/06-device-api.md), [08 §8.1](../design/08-flutter-app.md)

`web_socket_channel` on `/api/v1/stream`: consume `hello`, send `subscribe`, answer pings, and map
every §6.3 frame onto the `BridgeEvent` union — which grows `pairing` and `ota` variants here
(freezed's exhaustive `switch` then forces every consumer to decide, which is the feature). Unknown
frame types are dropped with a debug log, per the additive-contract rule. A refused upgrade
(`503 busy` — the sim enforces the 2-client cap precisely so this path is testable) surfaces as a
typed condition with REST still working, and disconnects surface on the stream; *retrying* is
A7's job, not the transport's.

**Done when:** every server frame type round-trips to the right `BridgeEvent` in tests against the
sim, a third client's refusal is surfaced without breaking REST, and `ack_alarm` goes out as the
contract writes it.

### A5.3 data/repos: prove transport parity through the sync engine

- **blocked-by:** A5.2, A4.3 · **verify:** S · **board:** no
- **design:** [08 §8.5](../design/08-flutter-app.md)

Run the A4 sync and repository suites over `HttpTransport` against the sim's adverse scenarios
(`flaky`, `base-lost`, `detached`), not just the happy path: the three-hour-disconnect reconnect
transfers **exactly 360 samples**, a restart mid-sync resumes without duplicate rows, and live
WebSocket samples append to the cache seamlessly across a sync boundary. This is the test that
says `MockTransport` and `HttpTransport` are behaviourally interchangeable — the claim the whole
architecture rests on.

**Done when:** the A4.3 acceptance reproduces over real HTTP, and the suite runs both transports
from one parameterised harness so they cannot drift apart unnoticed.

---

## A7 — ConnectionManager

### A7.1 data/transport: implement the candidate race

- **blocked-by:** A5.1, A4.1 · **verify:** H · **board:** no
- **design:** [08 §8.4](../design/08-flutter-app.md), [05 §5.8.5](../design/05-connectivity-and-provisioning.md)

The §8.4 fan-out: last-known IP (~50 ms), mDNS browse, `smokebridge.local`, `192.168.4.1`, raced
in parallel; first HTTP 200 on `/status` wins and becomes the `HttpTransport`. **Manual IP entry
jumps the queue and always works** — it is the escape hatch A14's epic note promises, and it must
not share a failure mode with anything it is an escape from. All HTTP lanes failing falls to the
BLE lane, which in M2 is an honest stub reporting unavailable (M3 fills it), which falls through to
offline-from-cache. Every success updates the `bridges` row (IP, last seen), so the common case —
same bridge, same network, second launch — is one 50 ms request. Candidate sources and the clock
are injected; the race logic is pure.

**Done when:** table tests cover each lane winning, manual entry pre-empting a race in flight,
all-fail → offline, and the cache row updating on every success.

### A7.2 data/transport: implement mDNS discovery over nsd

- **blocked-by:** A7.1 · **verify:** H · **board:** no
- **design:** [05 §5.5, §5.8.5](../design/05-connectivity-and-provisioning.md), [08 §8.2](../design/08-flutter-app.md)

Browse `_smokebridge._tcp` via `nsd` (the `multicast_dns` Android bug is why that package is
banned), resolve, and parse the §5.5 TXT records into a discovery model — id, fw, probes, paired,
session, mode — so M4's picker can say *"Smoke Bridge · 4 probes · cooking"* without connecting.
`nsd` is a platform plugin, so the discovery lane hides behind an interface with a fake for host
tests; the sim's `--advertise-mdns` (T3.6) and the real board (F8.8) are the live checks, exercised
at the bench sitting. Discovery is one lane of five, never a prerequisite — §5.8.5's rule.

**Done when:** TXT parsing is table-tested including missing and unknown keys, the fake-backed lane
integrates with A7.1's race, and a malformed advertisement degrades the lane silently instead of
failing the race.

### A7.3 data/transport: implement reconnect backoff and connectivity triggers

- **blocked-by:** A7.1, A5.2 · **verify:** S · **board:** no
- **design:** [08 §8.4](../design/08-flutter-app.md)

Exponential backoff at 1, 2, 4, 8, 15, 30 s capped, with `ConnectivityChanged` short-circuiting
the wait — walking back into Wi-Fi range reconnects without user action, which is the difference
between an app and an appliance. A dropped WebSocket re-races (the bridge may have changed mode or
address while away) rather than blindly redialling the old socket.

**Done when:** a fake clock asserts the exact backoff sequence, killing and restarting the sim
reconnects within one step, and a connectivity event mid-wait reconnects immediately.

---

## What is deliberately _not_ in M2

|                                                | Why                                                                                                                                                                          |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BLE / NimBLE, `BleTransport`, onboarding       | M3. A7.1's BLE lane is a stub that reports unavailable — the race is built so M3 fills a slot, not reworks a flow                                                             |
| `POST /api/v1/ota` implementation              | F14 (M6). The route stays unregistered → `404 not_found`; the sim keeps serving it so the app's OTA path stays testable. A dishonest `503` stub would lie about device state |
| Opt-in `.raw` full-session capture             | The writer was never built in M1 — the novelty log is what actually closes the protocol questions ([02 §2.7](../design/02-smoke-x-protocol.md)). Revisit via [standing-work](standing-work.md) only if a full-fidelity corpus is genuinely needed |
| Any Flutter screen                             | M4. A5/A7/A14 are transport, logic, and platform plumbing — the §12.6 rule 1 discipline holds until the transports are solid                                                  |
| The fallback web UI's content                  | D13, decided at M6. F9.10 implements only the mount-if-present rule; the `www` partition stays unformatted                                                                    |
| Bearer-token provisioning and settings UI      | The enforcement gate ships in F9.1; setting the token travels over BLE (M3) and its UI is M4                                                                                  |
| Battery calibration solve (`vbat_actual_mv`)   | F9.7 persists the value; solving for the divider ratio needs F12 and V1.3's measurements (M5, [§12.6 rule 6](../design/12-task-planning-notes.md))                            |
| Alarm engine reading `config/alarms`           | M5 (F13). F9.7 stores and echoes the rules blob so the contract is complete                                                                                                   |
| Wi-Fi join QR on the OLED                      | v1.1 stretch ([§12.7](../design/12-task-planning-notes.md))                                                                                                                    |
| Heap sign-off with NimBLE running              | Physically impossible before M3. F9.13 closes the V1.6 box provisionally; V3a re-measures with BLE live                                                                        |
