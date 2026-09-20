# Components Research Notes — Smoke X4 Smart Bridge

**Purpose.** A neutral, implementation-agnostic inventory of everything the product is made of,
disassembled into reusable "lego" pieces grouped by topic. This is *not* a spec and *not* a
redesign. It is the parts bin: each item states what it is, what it needs, what it produces, and
what constraints ride along with it, so a new UI/UX can be assembled top-down without rediscovering
the substrate.

**Method.** Compiled from the shipping source (`app/lib`, `firmware/`, `protocol/`, `tools/`) and the
design docs. Where the docs and the code disagree, the code wins. Each entry carries a **Status**:

| Status | Meaning |
|---|---|
| `shipped` | Built, reachable, exercised by tests |
| `partial` | Built but incomplete, or correct only on some transports |
| `unwired` | Code exists but no live call path reaches it |
| `dead` | Superseded or placeholder; no caller |
| `firmware` | Lives on the device; expected to stay stable |
| `contract` | Wire/data format both sides depend on |

**How to use it.** Treat each numbered item as a self-contained component. The dependency column is
the wiring diagram: if you move, merge, or delete a component, the "Depends on / Feeds" columns tell
you what else must move. Invariants (§1) are load-bearing; they are the things a redesign may
*re-express* but must not *violate*. Open questions (§14) are decision points for the redesign, not
bugs.

**Two tracks.** Firmware and protocol (§2–§4) are the stable substrate — the redesign assumes they
change little. The app layers (§5–§11) are the movable pieces. §12 (setup machine) and §13 (tools)
are supporting systems.

---

## 1. Non-negotiable invariants

These are enforced in code or by test and constrain any future UI. They are listed first because
every component below assumes them.

| # | Invariant | Enforced by / evidence |
|---|---|---|
| I1 | **The bridge is a listener, never a transmitter.** Exactly one LoRa packet in its lifetime: the pairing ack. | `app_lora` TX guard; `smoke_x` sync handler; host tests |
| I2 | **The device is authoritative.** It records and alarms with no phone. The app mirrors device alarms; it never re-decides them and never starts/stops recording. | `cook_lifecycle`, `app_alarm`; `BridgeSession`, `planNotifications` |
| I3 | **Absent ≠ zero.** A detached probe, unknown battery, or unmeasured signal is `null` and renders as absent with a reason — never `0`. | `tempDetached`/`socUnknown` sentinels; `format.noValue = '—'`; `buildDashboard` |
| I4 | **Never present stale data as current.** Freshness ladder ≤45 s live / ≤90 s aging / ≤600 s stale / >600 s frozen; derived values are *removed* when stale, not greyed. | `ProbeFreshness`, `StaleVeil` |
| I5 | **No dead controls.** A control that cannot work is either absent, or present-and-disabled with its reason on screen. | House rule; `SettingsRow` disabled-with-reason |
| I6 | **No state without a next step.** Every setup state and every empty screen has at least one way forward. | `SetupMachine`; `EmptyState`/`ProblemState` |
| I7 | **Verify by behaviour, not by return value.** Device answers that precede action (reboot, mode switch, config write) are confirmed by read-back or by watching the link drop. | `VerbProgressSheet`, `_writeAndVerify`, `markConfirmed` |
| I8 | **State the cost before a destructive action**, split into *keeps* / *loses*. | `CostSheet` |
| I9 | **One transport active at a time**, so capability flags stay honest. BLE leads, Wi-Fi upgrades, BLE held as warm standby. | `ConnectionSupervisor` |
| I10 | **Samples key on `(bridgeId, sessionId, t)`** and are idempotent; no sample row is ever rewritten. Cooks are time-window annotations over that stream. | drift key; `CookRepository` tests |
| I11 | **A bridge with no clock stores `NULL`**, never a fabricated timestamp. | `samples.unixMs` nullable; `app_time` |
| I12 | **Food safety is a hard gate.** Targets below a protein's floor throw; stored plans are re-validated on load and dropped if now unsafe. | `CookPlan` ctor, `SafetyFloor`, `CookDao` |
| I13 | **Copy over error** when a capability is genuinely missing (e.g. "Full history needs Wi-Fi"). | `CapabilityNotice`; transport degradation copy |
| I14 | **One ember primary action per screen**; status hue is chrome only, series hue is a mark only, green means transport health only. | `PrimaryAction`, `StatusPalette`, `ProbePalette` |
| I15 | **No raw exception reaches the user.** Failures become named states with specific copy. | `SetupFault`, `ErrorBoundary`, `BridgeRefusal` |

---

## 2. Hardware & device systems (firmware — stable substrate)

Board: Heltec WiFi LoRa 32 **V3** (ESP32-S3 + SX1262 + 128×64 SSD1306). Architecture pattern: each
component is a **pure C11 `_core`** (no ESP-IDF, host-tested, injected deps) plus a thin IDF glue
that owns hardware/tasks/event bus. All records go through generated codecs.

### 2.1 Component inventory

| Component | Kind | Purpose | Emits / exposes | Notes |
|---|---|---|---|---|
| `smoke_x` | firmware | LoRa packet parse, pairing state machine, stale-pairing watchdog, novelty seen-set, raw packet ring | `SMOKE_X_EVT_SYNCED/PAIRED`; stats, last-valid, base-lost | Comma count → 6=sync, 16=X2, 26=X4; X4 `state==3` = detached (temp field frozen); canonical storage tenths-°F |
| `app_lora` | firmware | SX1262 init/retune, unpaired 915↔920 MHz scanner, TX guard | `app_lora_start_tx`, guard open/close | SF9/BW125/CR4-5/+22 dBm; band 902–928 MHz; TX only inside sync window |
| `app_alarm` | firmware | Device-tier alarm engine: 9 rules, hysteresis, lid detection, ack | `BRIDGE_EVT_ALARM`; `app_alarm_list/unacked/ack` | Runs with no phone; 10 s tick; ack silences, does not resolve |
| `cook_store` | firmware | LittleFS `cooks` partition, session files, recovery, retention, streaming reads, RAM ring, novelty/power logs | session open/append/close/mark; ring slope; retention | `.smk` (256 B header + 16 B samples), `.mrk` (32 B marks); ~54 days; 64 sessions; fsync every 4th append |
| `app_api` | firmware | HTTP + WebSocket contract; streamed handlers, JSON emission | `app_api_handle`; WS frame builders | Port 80, `/api/v1`, max 2 WS clients, 8 KB body cap (OTA exempt), optional Bearer |
| `app_ble` | firmware | BLE GATT Bridge Control Service (NimBLE), advertising, chunked notify, history stream | `BRIDGE_EVT_BLE`; 11 characteristics | LE Secure Connections Passkey Entry; 3 bonds; MTU 247; history streams session/sample/mark/end |
| `app_net` | firmware | Wi-Fi AP/STA state machine, fallback ladder, deferred reconfig + rollback, mDNS TXT | `app_net_request_config`, scan seam, TXT | **Device is never unreachable**: STA failure always leaves AP up; retry 1/2/5/10 min; revert window 10–600 s |
| `app_config` | firmware | Sole NVS opener; typed get/set, schema, migration, change notify, AP PSK generation | typed config store; pairing blob | Namespaces: net/device/probes/session/time/alarms/mqtt |
| `app_time` | firmware | Wall-clock arbitration (SNTP > phone > stale floor > none); never goes backwards | `app_time_now`, acquired callback | No battery RTC; samples are seconds-since-session-start; back-patches session header on clock acquire |
| `app_power` | firmware | Battery ADC sampling, SoC curve, charging inference, calibration, saver, deep sleep | `app_power_svc_*` | GPIO37 gate inverted on real HW; 30 s cadence; `SOC_UNKNOWN=255` |
| `app_ota` | firmware | Streamed upload to inactive slot, image inspection, health rollback gate | `app_ota_*`, gate verdicts | Inspects first 288 B before flash; 409 `session_active` unless `?force=1`; gate clauses storage/net/httpd/crash/120 s uptime |
| `app_ui` | firmware | 128×64 OLED: 5 pages + 5 overlays + status strip; gesture machine; LED/buzzer patterns | `app_ui_render`, input, LED | Pages: PROBES/TRENDS/NETWORK/RADIO/SYSTEM; TAP=next page, HOLD≥2 s=power off |
| `app_mqtt` | firmware | Opt-in Wi-Fi-only MQTT publisher with Home Assistant discovery | `app_mqtt_core_*` | Runs only when enabled AND STA up; retained state; plaintext `mqtt://` in v1 |
| `bridge_event` | firmware | Event bus + 5 ms handler-budget guard | `bridge_event_post/register` | `BRIDGE_EVENT` esp_event base; POD payloads |
| `main` / `boot_seq` | firmware | 17-step boot; double-reset recovery window; bench mode | `bridge_boot_run`, RTC token | LoRa before Wi-Fi/BLE; UI before BLE (passkey); 2 resets in 10 s forces AP |
| `tasks.h` | firmware | Single source of truth for task stacks/prio/core | — | 9 app tasks; 32 KB stack budget static-asserted |

### 2.2 Device-tier alarm rules (nine)

| # | Rule | Severity | Auto-clear | Session-scoped | Lid-suppressed |
|---|---|---|---|---|---|
| 0 | `smoke_x_alarm` (mirrors base station's own band) | critical | latched | yes | no |
| 1 | `target_reached` (food crosses target up) | critical | latched | yes | no |
| 2 | `pit_out_of_band` | warning | auto | yes | yes |
| 3 | `pit_crash` | critical | latched | yes | yes |
| 4 | `probe_detached` | warning | auto | yes | no |
| 5 | `base_lost` | warning | auto | no | no |
| 6 | `battery_low` (warn→crit) | warning→critical | auto | no | no |
| 7 | `storage_low` | warning | auto | no | no |
| 8 | `system_fault` (coredump / OTA gate failed) | warning | latched | no | no |

Defaults: all enabled; pit band ±25 °F sustained 600 s; pit crash −100 °F/hr below target; base lost
600 s; battery warn 15 % / crit 5 %; storage free 2 %; target rearm 3 °F; band rearm 300 s; lid grace
900 s. Twelve global tunables back these (see `app_alarm_cfg_t`).

### 2.3 Device session lifecycle

- Auto-starts at power-on + sync when paired, receiving, and a probe attached (no temperature gate).
- Ends on: all probes detached 10 min, explicit stop, 36 h hard cap (with continuation), or unpair.
- **Packet loss does not end a session** — the gap stays visible.
- Detached temperature is a sentinel, not a number.

### 2.4 OLED pages / overlays (device-side UX, separate from phone)

- **Pages (5):** PROBES (default), TRENDS (current + rate + 2 h pit sparkline), NETWORK, RADIO, SYSTEM.
- **Overlays (5):** SPLASH (boot + 3 s recovery + antenna warning), PASSKEY (6-digit, display-only),
  ALARM (inverted video, 60 s), CONFIRM (release-to-cancel), OTA.
- **Status strip** on every page: `●sta 04:12 71% ⚠`; cook clock blank (not `--:--`) when unset.
- One button: TAP cycles pages; HOLD ≥2 s powers off; 10 s factory-resets.

---

## 3. Wire contract (`protocol/` — generated from `records.yaml`)

`protocol/` is the single source of truth. Byte layouts generate into **both C and Dart**; CI fails on
drift. Endianness: little. Record version 1. CRC-16/CCITT-FALSE (records), CRC-32/ISO-HDLC (header).

### 3.1 Constants & sentinels

`TEMP_DETACHED=-32768`, `TEMP_INVALID=-32767`, `SOC_UNKNOWN=255`, `SESSION_MAGIC="SMKS"`.

### 3.2 Records

| Record | Size | Fields (abridged) |
|---|---|---|
| `sample_rec` | 16 | `t` u32 (s since session start), `temp[4]` i16 (tenths °F, sentinels), `flags` (p1–p4 alarm, billows, new_alarm, source_celsius), `rssi` i8, `crc16` |
| `session_header` | 256 | magic, version, hdr_len, rec_len, num_probes, flags (clock_valid/closed/pinned), session_id, started/ended unix_ms, uptime, sample_period_s, sample_count, device_id, name, per-probe name/role/target, mark_count, crc32 |
| `mark_rec` | 32 | `t` u32, `kind` u8, `probe` u8 (0=whole cook), crc16, `text` char[24] |
| `history_session` | 56 | session_id, started/ended unix_ms, sample_count, sample_period_s, num_probes, flags, name |
| `device_info` (BLE) | 40 | ver, api, probes, caps (wifi_ap, wifi_sta, wifi_enterprise, history_preview, ota, battery, history_full), id, model, fw |
| `live_state` (BLE) | 16 | ver, flags (paired/session_active/billows/alarm_active/clock_valid), temp[4], soc_pct, rssi_lora, session_t |
| `net_status` (BLE) | ≤64 | ver, mode, state, wifi_rssi, ip, ssid, host |
| `wifi_scan_ctrl` / `wifi_scan_result` | 2 / ≤40 | scan cmd / SSID list entries (rssi, auth, channel) |
| `wifi_config` | ≤134 | ver, mode, auth, ssid, psk, user |
| `device_control` | ≤30 | ver, op, body |
| `result` | ≤68 | ver, op_echo, status, detail |
| `history_preview` | ≤244 | probe_index, count, bucket_min, values i16[≤120] |
| `history_ctrl` / `history_data` | 16 / ≤244 | request / streamed chunks with seq + last flag |
| control bodies | — | set_time, mark, set_units, set_cook_clock, ack_alarm, set_battery_saver |

**Enums:** probe_role (unused/pit/food/ambient), mark_kind (note/wrapped/lid_open/fuel/probe_moved/
alarm/phase_change/auto_detected), alarm_rule (9), alarm_severity, net_mode, net_state, control_op
(1–15), result_status, units, battery_saver, scan_cmd, history_req, history_kind.

### 3.3 HTTP endpoints (base `/api/v1`, optional Bearer)

| Group | Endpoints |
|---|---|
| Read | `GET /status`, `GET /live` (`window`, `format`), `GET /sessions`, `GET /sessions/{id}`, `GET /sessions/{id}/samples` (`from/to/stride/bucket/agg/format/probes`), `GET /sessions/{id}/marks`, `GET /pairing` |
| Session verbs | `POST /sessions`, `PATCH /sessions/{id}`, `DELETE /sessions/{id}`, `POST /sessions/{id}/stop`, `POST /sessions/{id}/marks` |
| Pairing / power | `POST /pairing/sync`, `POST /pairing/unpair`, `POST /restart`, `POST /factory-reset`, `POST /power-off` |
| Config | `GET/POST /config/wifi`, `POST /config/wifi/commit`, `GET/POST /config/device`, `GET/POST /config/alarms`, `GET/POST /config/mqtt`, `GET/POST /config/radio` |
| Clock | `POST /time`, `GET/POST/DELETE /cook-clock` |
| OTA | `POST /ota` (`force`) |
| Debug | `GET /debug/packets`, `/debug/novelty`, `/debug/coredump`, `/debug/tasks` |
| Captive portal | `/`, `/generate_204`, `/gen_204`, `/hotspot-detect.html`, `/library/test/success.html`, `/ncsi.txt`, `/connecttest.txt` |

Error envelope `{error:{code,message,detail}}`; status→code table in `openapi.yaml`.

### 3.4 WebSocket (`/api/v1/stream`)

- Server→client frames: `hello`, `sample`, `alarm`, `session`, `net`, `pairing`, `power`, `ota`.
- Client→server frames: `subscribe`, `ping`, `ack_alarm`.
- Server pings every 30 s; drops after two misses; while a WS client is connected in STA, Wi-Fi power
  save drops to `WIFI_PS_NONE`.

### 3.5 BLE GATT (service `7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162`)

| Slot | Characteristic | Props | Security |
|---|---|---|---|
| 0001 | `device_info` | Read | open |
| 0002 | `net_status` | Read, Notify | encrypted |
| 0003 | `wifi_scan_ctrl` | Write | encrypted |
| 0004 | `wifi_scan_result` | Notify | encrypted |
| 0005 | `wifi_config` | Write | enc + auth |
| 0006 | `device_control` | Write | enc + auth |
| 0007 | `live_state` | Read, Notify | encrypted |
| 0008 | `history_preview` | Read | encrypted |
| 0009 | `result` | Notify | encrypted |
| 000A | `history_ctrl` | Write | encrypted |
| 000B | `history_data` | Notify | encrypted |

Advertising: local name `SmokeBridge-XXXX`, 128-bit service UUID, manufacturer status blob (7 B:
ver, flags, pit temp, SoC, session minutes), company id `0xFFFF`.

### 3.6 Pairing handshake (the one-transmit path)

1. Unpaired bridge alternates 915 MHz (X4) ↔ 920 MHz (X2) scanning.
2. Base station in sync mode broadcasts `<field0>,<deviceid>,<freq bytes>,` (6 commas).
3. Bridge accepts only when unpaired; range-checks 902–928 MHz **before** retuning; copies device id;
   retunes to operating frequency; transmits `<deviceid>,SUCCESS,`; state → SYNC_RECEIVED.
4. First valid state message (16 or 26 commas) → CONFIRMED, learns probe count, persists pairing.
5. The ack is the **only** TX ever. Enforced by the `app_lora` guard + sole caller in `smoke_x`.

---

## 4. Transport capability matrix

One interface (`BridgeTransport`), three implementations. Screens never know which is active;
capability flags drive the few visible differences. Degradation is always surfaced as copy.

| Capability | HTTP (Wi-Fi) | BLE | Mock |
|---|:--:|:--:|:--:|
| Live state | ✔ | ✔ | ✔ |
| History preview (2 h) | ✔ | ✔ | ✔ |
| Full history | ✔ | ✔ (if `caps` b6) | ✔ |
| Config (network) | ✔ | ✔ | ✔ |
| Probe names / roles / targets | ✔ | ✘ (throws) | ✔ |
| Device config read-back | ✔ | ✘ (`unknown`) | ✔ |
| Alarm rules | ✔ | ✘ | ✔ |
| MQTT / Home Assistant | ✔ | ✘ | ✔ |
| OTA | ✔ | ✘ | ✘ |

Known per-transport quirks (see §14): BLE `live()` ignores its `window` arg and leaves `probes`
empty; BLE `applyNetwork` drops `revertAfterS`; HTTP ack can be silently dropped if the WS is down;
HTTP `status()` omits `alarm.value_f10`.

---

## 5. App data & persistence

### 5.1 Local cache — drift/SQLite, schema v2

| Table | Key | Notable fields |
|---|---|---|
| `Bridges` | id | name, lastSeenUnixMs |
| `Sessions` | (bridgeId, sessionId) | name, started/ended, samplePeriodS, sampleCount, numProbes, closed, pinned |
| `Samples` | (bridgeId, sessionId, t) | p1..p4 nullable, flags, rssi, **unixMs nullable** (v2 projection) |
| `Marks` | autoinc | bridgeId, sessionId, t, kind, probe, text, `autoAnchor` (v2, unwired) |
| `Cooks` | autoinc | bridgeId, name, start/end/created, notes, presetId, doneness, hazard, safetyMode, pit band, favourite, anchorSessionId, pulledAt |
| `CookProbeRoles` | (cookId, jack) | role, label, targetF10, pullOffsetF10, doneness, hazard, isIntact |
| `AlarmRules` | autoinc | bridgeId, scope, jack, type, threshold, windowS, enabled, pushedToDevice, lastConfirmed |
| `Gaps` | (bridgeId, sessionId, fromT) | toT, reason, detectedUnixMs |
| `SyncStates` | (bridgeId, sessionId) | highWaterT, deviceMinT, deviceMaxT, lastSync |
| `AlarmLog` | autoinc | **declared but never written — dead** |

Migration v1→v2 backfills `unixMs` from `session.started + t*1000`, creates one Cook per session
(clockless → `anchorSessionId`), seeds high-water marks. Unknown hazard on read → `unstated` (floored).

### 5.2 Preferences (`shared_preferences`, loaded once at boot for synchronous reads)

`bridge.base_url`, `bridge.id`, `bridge.ble_device_id`, `bridge.last_seen_ms`, `display.units`,
`display.theme_profile`, `alarms.quiet_hours` (default true), `alarms.monitoring` (default true),
`transport.preferred` (auto), `transport.hold_ble` (true), `cook.plan` (JSON).

No Wi-Fi password is ever stored by the app. `forgetBridge` clears identity + cook plan, keeps
transport preference.

### 5.3 Sync engine — high-water-mark protocol

1. `status()` → upsert bridge. 2. `sessions()` → upsert (upsert-only; device-purged cooks stay).
3. Per session: derive device extent from header; record sync state; `detectRollover` → record
permanent gap **before** fetch. 4. Skip if closed and fully cached. 5. Choose `fromT` (rollover→toT,
partial cache→0, else cachedMax+1). 6. Stream batches, insert idempotently, advance high-water per
batch, clear filled connectivity gaps.

Rollover (device `minT` ahead of phone high-water) becomes a permanent `Gaps` row; connectivity gaps
are derived from cadence and cleared when filled.

### 5.4 Repositories

| Repository | Responsibility |
|---|---|
| `SessionRepository` | Cache-only reads: sessions/watch/samples/marks/summaries/sparkline/cacheStats/clear |
| `BridgeRepository` | `status()` passthrough + `refresh()` = SyncEngine |
| `CookRepository` | Cook annotation verbs: list/watch/startFromPlan/backdate/rename/setNotes/setFavourite/retarget/markPulled/end/reopen/split/merge/repeat/delete/anchorsFor/gapsFor — **never writes a sample row** |

### 5.5 CSV export

Byte-compatible with the device's own `format=csv` (same header, order, ISO-8601). Detached probe =
empty field. Streamed line-by-line; generated from the cache so it works offline.

---

## 6. Domain engines (pure Dart, zero Flutter imports)

### 6.1 The pure projection — `buildDashboard()`

Four sources (cache, live push, `/status`, app analysis) meet in one immutable `DashboardSnapshot`.
Every reader widget renders the snapshot and nothing else. Contains the absent≠zero invariants;
`headlinePit`/`headlineFood`/`secondary`, `anyAttached`, `disconnected()`.

### 6.2 Analysis

| Engine | Behaviour |
|---|---|
| Rate of change | OLS over 10 min; null on too few samples or a >2 min gap; display floors ±0.6 °F/hr → `~0` |
| ETA to target | Linear OLS early, Newton cooling within 60 °F of pit; returns a **15-min-rounded range** or a named refusal (insufficient history, slope too flat, stalled, target at/above pit, not approaching) |
| Stall detection | Food probe; enter \|slope\|<2 °F/hr sustained 30 min ∧ 140–180 °F; exit >4 °F/hr sustained 15 min |
| Lid open | Pit drops ≥25 °F in ≤3 min; confirm ≥50 % recovery within 20 min else escalate — **unwired in app; device does it** |
| LTTB | Largest-Triangle-Three-Buckets decimation |
| Chart series | Runs split at gaps **before** per-run LTTB; min/max envelope for wide ranges; crosshair returns nearest real sample |
| Cook stats | Duration, readings, gaps + total, pit mean/σ/min/max, time-in-band (gap time excluded), stall duration, lid events (from marks), per-probe start/end/peak |
| Gaps | `connectivity` (recoverable) vs `bufferRollover` (permanent) |
| Units | tenths-°F ↔ tenths-°C |

### 6.3 Cook model

- **`CookPlan`** — app-tier guided cook (never reaches the base). Constructor is a food-safety gate.
  Persisted as JSON in prefs so the first frame picks the right mode. `fromJson` re-runs the gate.
- **`CookAnnotation`** — a named, time-bounded, targeted **window** over the continuous recording.
  Edits are metadata only: `backdatedTo`, `splitAt`, `mergedWith`, `retargetedTo`, `repeatAt`.
  `candidateAnchors` suggests start anchors (probe inserted, crossed ambient, user mark, recording
  start).
- **`CookPhase`** — four-phase arc: approaching → pullNow → resting → ready. Never infers "pulled";
  rest is a mass-based estimate; sensor wins if probe stays in.
- **`Presets`** — 13 cuts across 4 categories with doneness ladders, carryover offsets, pit bands.
- **Food safety** — `HazardClass` (unstated/wholeMuscleRedMeat/poultry/ground/pork/fish/egg) and
  `SafetyFloor.forClass(hazard, isIntact, mode)`. Whole-muscle red meat has no floor only when intact;
  mechanically tenderized/injected behaves like ground (160 °F). Dual modes: USDA-compliant vs
  enthusiast (intact only).

### 6.4 Alarm & notification logic

- **`AlarmRuleType`** (17 values) with per-type group/label/blurb/threshold-unit/isPerProbe/tiers.
  `AlarmRuleSpec` carries tier, jack, threshold, window, enabled, `pushedToDevice` (only set by
  confirmed read-back), `matchesReadBack` (fails closed).
- **`notification_policy.planNotifications()`** — pure function over device alarms, on-screen keys,
  wall clock, app findings, quiet hours, monitoring flag → post/withdraw. Quiet hours 22–06 silence
  warning/info, **never critical**, evaluated in phone local time. Four channels: critical/warning/
  info/ongoing. Escalation ladder: repeat at 5 min, full-screen at 10 min (critical only).
- **Two tiers, visibly separate:** Device (nine rules on the ESP32, authoritative) vs App (advisory:
  ETA-soon, stall, lid, bridge unreachable, phone offline).

### 6.5 Situation reconciliation

`reconcile(SituationFacts) → one named Situation`, priority-ordered: radio/permission → identity
(`bridgeWasReset` never automatic) → reachability → usefulness (pairing, clock, history support) →
`staleCook` → healthy. `SituationFacts` fields are nullable (null = not known, distinct from false).

---

## 7. Connection & session orchestration

| Component | Purpose | Notes |
|---|---|---|
| `ConnectionManager` | Six-lane race: manual → cachedIp → mdns → mdnsName → apDefault → ble | A lane wins only on a real `GET /status` 200; backoff 1/2/4/8/15/30 s; BLE is fallback after all HTTP lanes fail |
| `ConnectionSupervisor` | BLE leads → Wi-Fi upgrades in background → BLE held warm → silent failover → climb back | `preferredTransport` auto/wifi/ble; `holdBle`; owns all transport lifecycle; exactly one active |
| `BridgeSession` | One object owning status/live/history/marks/session for a link | start order status→sync→live→cache→subscribe; 10 s backstop poll; link loss verified by a `status()` read |
| `ShellSession` | The app's live session; exposes snapshot, plan, freshness, situation, transport prefs | Boots one connection for the whole shell; published via `ShellScope` InheritedNotifier |
| `AppConnection` | Launch state machine (`LaunchNeedsOnboarding`/`Connecting`/`Connected`/`Offline`) | Production shell uses the supervisor; this is legacy/test path |

Reads: WS/BLE push; 10 s backstop poll; 20 s signal poll (visible tab only); 30 s ongoing
notification; pull-to-refresh reconnects both radios then reads live and **throws on failure by
design**.

---

## 8. Platform services (Android seams)

| Seam | Provides | Notes |
|---|---|---|
| `notifications.dart` / `_plugin.dart` | 4 channels created up front; permission; full-screen-intent capability; post/cancel; ongoing | Channel importance is immutable after creation |
| `ForegroundServiceHost` | `connectedDevice` foreground service; battery-exemption opt-in | Avoids the `dataSync` 6 h/24 h cap; service declared in manifest |
| `permissions.dart` | bluetoothScan/Connect, location (SDK≤30), notification | Worst-verdict reduction; backend seam for tests |
| `network_binder.dart` | `bindProcessToNetwork` for hosted-AP join; onBound/onLost | Essential or traffic escapes to cellular |
| `share.dart` / `_plugin.dart` | Share sheet (`share_plus`) | Currently used for CSV/field-report export |
| `firmware_picker.dart` | Local `.bin` file selection for OTA | `file_selector`; streams the file |
| `system_settings.dart` | Deep-links to Bluetooth/app/Wi-Fi/location/notification settings; SDK int | Best-effort, swallows misses |
| `device_facts.dart` | platform, OS version, locale, processors | For diagnostics/field report |
| `CookMonitor` | Background loop: persist samples, mirror alarms, notifications, ongoing readout | Lifecycle: start on cook, stop 10 min idle; warns once after 3 min no data |

---

## 9. Design system (tokens & primitives)

### 9.1 Tokens (`SmokeTokens` ThemeExtension)

- **Surfaces (6):** `bg`, `surface`, `card`, `cardSubtle`, `cardRaised`, `well` (mono readouts only).
- **Lines:** `hairline` (8 %), `hairlineStrong` (14 %), `scrim` (72 %).
- **Ink (4):** `textHi`, `textBody`, `textMuted`, `chromeDim` (non-text only).
- **Elevation:** one shadow; `glow`/`glowTight` (off in daylight).
- **Two profiles:** `dark` (default) and `daylight` (same surfaces, lifted ink, thicker hairlines,
  no shadow/glow). No white/light theme — daylight is a contrast profile.
- **Geometry:** radii card 20 / control 14 / chip 8 / pill 999; 4 dp spacing scale (`s1`=4 … `s7`=32;
  "a 6 or a 10 is a bug").

### 9.2 Typography

Three bundled variable fonts — `Archivo` (display/temps), `Inter` (text/labels), `JetBrainsMono`
(keys/ids). Fourteen named styles (`heroTemp` 96 … `labelSm` 11, `monoKey` 34). Tabular figures on
numeric styles. `SmokeTextScale` reflow ladder: hero 96 pt + 84 dp gauge at 1.0×; gauge shrinks
84→64 to 1.3×; above that hero demotes to 56 pt and the gauge drops. **A temperature is never scaled
to fit.**

### 9.3 Colour discipline

- **Series hue (per-probe, follows the jack, never the role):** P1 ember, P2 violet, P3 green,
  P4 blue. Three identity channels: hue + stroke pattern + glyph. May only be a *mark* (chart stroke,
  gauge arc, ≤12 dp dot, card left rule, ≤16 % tint). Never carries a word.
- **Status hue (critical/warning/positive/info/pit):** may only be *chrome* (12–16 % fill, 22–35 %
  border, always icon **and** word). Banner text is always `textHi`.
- **Positive green is transport health only.** Target reached is not a colour — the gauge ring closes.
- **Identity palette** (`food_glyph.dart`): 13 food glyphs, two registers (disciplined / vivid),
  never encodes state.

### 9.4 Motion & haptics

- Motion tokens: `quick` 120 / `standard` 220 / `value` 600 / `gauge` 800 / `pulse` 2 s. No
  `Duration` literal may appear in `ui/` (layering test). Reduced motion zeroes all but `pulse` (the
  pulse stopping *is* the staleness signal).
- Haptics: selection/advisory/confirm/warning/critical; critical is the only two-event pattern;
  positive/pit silent.

### 9.5 Adaptive rules

Width classes compact <600 / medium 600–839 / expanded ≥840. `readableMax` 480 (readout column cap),
`noticeMax` 720. Navigation: bottom bar → rail (≥600) → extended rail (≥1240). Fold postures from
`displayFeatures`: tabletop (horizontal hinge → chart upper / readouts lower), book (vertical hinge →
panes snap to hinge).

---

## 10. UI component inventory (`app/lib/ui` — stateless over plain values)

| Group | Components | Purpose |
|---|---|---|
| Surface | `SmokeCard` | The one container: accent, spine, raised, inset, onTap, footer |
| Surface | `CostSheet` / `showCostSheet` | Destructive confirm: keeps / loses, named buttons |
| State | `EmptyState`, `LoadingState`, `ProblemState`, `CapabilityNotice` | The four "nothing here" surfaces (each one action) |
| State | `StaleVeil` | Desaturate + dim + pin age label; prevents double-dimming |
| Insight | `InsightBanner` | Slim status strip: hue on icon+border, words in `textHi` |
| Chrome | `AlarmBar` | Highest-severity unacked alarm, inline Acknowledge, role haptic |
| Chrome | `ChromeSlot` | Always-mounted zero-height reveal for shell chrome |
| Chrome | `PulseDot` | 7 dp liveness dot; hollow when not live |
| Chrome | `SeriesLegend` | Chart key: glyph + stroke swatch + name + value; tap-to-isolate |
| Chrome | `SignalBars` | Four neutral bars (never a status hue) |
| Chrome | `TransportChip` | Link pill (none/ble/wifiAp/wifiSta) with pulse dot |
| Controls | `PrimaryAction` | The only ember-filled button; one per screen; busy spinner |
| Controls | `MonoWell` | Deepest surface, mono type, tap-to-copy (passkey/AP PSK) |
| Controls | `SegmentedChips` | Single-select chip row (windows, °F/°C, saver) |
| Controls | `ActionRow` / `StatRow` | **unwired** (reader uses its own action row / fact rows) |
| Probe | `AnimatedTemp`, `TempReadout` | Temperature tween + series underline; never scaled |
| Probe | `ProbeFreshness` | live/aging/stale/frozen/unknown; `showsDerived`, `isDim` |
| Probe | `ProbeHeroCard` | Guided headline: 96 pt readout + radial gauge + phase track |
| Probe | `ProbeStripRow` | Instrument dense row: badge, avatar, trend, sparkline, chevron |
| Probe | `ProbeCompactCard` | Secondary two-up card with progress rule |
| Probe | `TargetPill`, `TrendChip`, `JackBadge`, `FoodAvatar` | Identity/target/trend atoms |
| Probe | `PhaseTrack` | Four-segment progression; position by height, not hue |
| Probe | `TargetGauge` | 84 dp radial: sweep (target + pull tick) or band (pit) |
| Probe | `Sparkline` | Tiny straight-segment recent line |
| Setup | `SetupScaffold`, `SetupRail`, `SetupSteps` | Setup frame, hop rail, "what happens next" |
| Setup | `PasskeyDisplay` | OLED overlay with **no** code parameter (cannot render a real code) |
| Setup | `BridgeIllustration`, `BaseStationIllustration` | Vector device art with mood-driven OLED |

---

## 11. Capability clusters (neutral feature surfaces)

These are the user-facing capabilities, decoupled from the current tab IA. Each can be placed,
merged, or split in a new design.

### 11.1 Read live telemetry

- Four probes in jack order, detached rendered in place (`—`, "unplugged"), never 0.
- Instrument mode (no plan) vs guided mode (plan with targets) — one nullable switches them.
- Freshness ladder with derived values removed when stale.
- Per-probe detail: window chips (15 m/1 h/6 h/15 h/All), Now pill, crosshair, stats, role/target.
- Trend chips, sparklines, target gauges, phase track.
- Actions: mark, export, test alarm, probe drill-down, set up / end cook, pull.

### 11.2 Record history & cook annotations

- Continuous recording exists with or without the app; a "cook" is an annotation window.
- Cook list grouped SCHEDULED / RECORDING NOW / TODAY / THIS WEEK / EARLIER; sparkline + metadata.
- Cook detail: chart, statistics table, mark timeline, notes, gaps card.
- Cook editor: rename, backdate (anchor-assisted), retarget, split, merge, repeat, favourite,
  end/reopen, delete (cost sheet states recording does not stop).
- CSV export (byte-compatible, streamed, offline).

### 11.3 Alarms & notifications

- Two tiers: device (authoritative, nine rules) vs app (advisory).
- Rule editor (add/edit/toggle/delete) with MEATER-style taxonomy + pre-alarm; device rules pushed
  with write→read-back→compare.
- Delivery verdict ("will this phone wake you?") + test alarm.
- Quiet hours, monitoring toggle, battery exemption, escalation ladder.
- Global alarm bar with inline acknowledge.

### 11.4 Device management

- Connection mode (BLE / bridge hosts / your Wi-Fi) with plain-language explainers and switch wizard
  (rollback timer + BLE escape hatch).
- Signal: two hops never conflated (phone→bridge on BLE; bridge→router from device, even over BLE).
- Identity facts, five-tap diagnostics gate.
- Reset & power verbs behind cost sheets + verb-progress sheets: restart, forget, factory reset,
  power off.
- Settings tree (12 sections): identity, probes, alarms, display/units, LED, power/sleep, network,
  MQTT/HA, firmware/OTA, data/export, diagnostics, about.

### 11.5 Onboarding / provisioning

- Three-hop guided setup (BLE pair → base/LoRa pair → Wi-Fi) behind a preflight gate; ~40 states.
- Passkey shown only on the device OLED.
- Non-destructive pairing; skipped hops read "— not set up".
- Recovery paths: factory reset over BLE, resume plan, add-second-phone fast path.

### 11.6 Global chrome

- Transport chip with staleness pulse dot; battery only when knowable.
- Refresh banner (failed pull says so; auto-retires when a link returns).
- Alarm bar (device-scope alarms included, on every tab).
- Connection sheet (transport, fallback story, preferred transport, hold-BLE).
- Cost sheet and verb-progress sheet.

---

## 12. Setup state machine atoms

The setup machine is pure over injected seams (runs in tests and the UX Lab with no radio). ~40
named states. Neutralized into hop stages:

| Stage | States |
|---|---|
| Preflight (hop 0) | permission primer, permission denied (permanent), Bluetooth off (resumable), location off (SDK≤32), Bluetooth unsupported (terminal) |
| BLE (hop 1) | scanning, no bridges, add-this-phone, pairing, passkey-not-seen, bonded, passkey-wrong, rebond-needed, bond-slots-full, not-a-bridge |
| Base/LoRa (hop 2) | intro, listening, heard, confirmed, skipped, failed (named causes) |
| Network (hop 3) | pick, empty, manual (hidden SSID + auth), password, applying (4 narrated phases), wifi-failed (5 reasons), unreachable, hosted-join, hosted-refused |
| Finish | name+units, done, reset-done, link-lost, fault |

Machine invariants: no state without a next step; no raw exception escapes (→ `SetupFault`); a
superseded flow cannot drag the user backwards (monotonic generation counter).

---

## 13. Tools & test harnesses

| Tool | Purpose |
|---|---|
| `tools/sim` | Fake bridge: full HTTP + WebSocket API from recorded/synthesized cooks + adverse scenarios + mDNS |
| `tools/cookgen` | Synthesizes physically plausible `.smk`/`.mrk` fixtures from a deterministic thermal model |
| `tools/protogen` | Emits committed C/Dart record codecs from `records.yaml`; `--check` fails CI on drift |
| `tools/lora` | Captures/normalizes ESP-IDF logs into `.loralog` fixtures + protocol-question reports; pulls debug endpoints |
| `tools/flash` | Builds merged flash image, esp-web-tools manifest, esptool command (does not flash) |
| `tools/soak` | 24 h soak recorder + four-criteria verdict report |
| `tools/bridge_protocol` | Dart package re-exporting generated records + shared OTA image decoder |
| `tools/oled`, `tools/installer` | OLED golden/preview renderer; browser esp-web-tools installer page |
| `scripts/deploy.sh` | `doctor` / `bridge` (esptool) / `app` (adb) turnkey deploy |
| UX Lab (`app/lib/lab`) | Hardware-free Chrome harness: live Cook tab + the real setup machine over fakes |
| Test suites | app ~1,177 tests (unit/widget/golden/integration); firmware 27/27 host suites; layering tests (domain = zero Flutter imports; ui = stateless) |

---

## 14. Gaps, dead code, seams, and open decisions

### 14.1 Dead / unwired

| Item | Status | Note |
|---|---|---|
| `features/debug/debug.dart` | dead | Doc-comment only, no implementation |
| `features/sessions/sessions_route.dart`, `SessionsListView` | dead | No route; `/sessions` redirects to `/cooks`. `SessionDetailView` is live (used by `CookDetailView`) |
| `ui/controls/action_row.dart` (`ActionRow`) | unwired | Zero call sites; reader has its own |
| `ui/controls/mono_well.dart` (`StatRow`) | unwired | Zero call sites |
| `AlarmLog` drift table | dead | Created, cleared, never written/read |
| `Marks.autoAnchor` column | unwired | Added by v2 migration; never set or read |
| `LidOpenDetector` / `AppFinding.lidOpen` | unwired | Device does lid detection; app finding never emitted |
| `AppFinding.phoneOffline` | unwired | Declared, copy written, never produced |
| `ControlOp.identify/setCookClock/clearCookClock` | unwired | Generated; no app command variant |
| `canScheduleExactAlarms` / `requestExactAlarms` | unwired | Not on the interface, no call sites |
| `AppConnection.start/reconnect/_race` | legacy | Supervisor is the production path |
| Legacy redirects (`/cook`, `/alerts`, `/settings*`, `/bridge*`, `/history`, `/sessions`) | partial | Kept for compatibility |

### 14.2 Seams / likely bugs (worth deciding on during redesign)

- **HTTP alarm ack can be silently dropped** if the WebSocket is closed/reconnecting (no REST
  fallback).
- **HTTP `status()` omits `alarm.value_f10`**, so poll-built notifications lack a temperature while
  WS-built ones have it.
- **Food-safety fallback inconsistency:** `CookPlan.fromJson` defaults unknown hazard to
  `wholeMuscleRedMeat` (floor-free in enthusiast mode); `CookDao` defaults to `unstated` (floored).
- **BLE `applyNetwork` ignores `revertAfterS`** — no rollback safety net over Bluetooth.
- **BLE `live()` ignores its `window` argument** and returns the fixed 2 h preview, single probe.
- **HTTP streaming sample parser hardcodes 16-byte records** (ignores a future `rec_len`).
- **`SampleDao.insertSamples` assumes length-4 `tempsF10`.**
- **Open-session device extent is underestimated** (rollover can be missed).
- **`SampleDao.sparkline` averages the first attached probe only** — a semantic trap if reused
  per-probe.

### 14.3 Open decisions carried forward (from `docs/newapp.md` §J.9 / `15-newapp-decisions.md`)

Already decided: samples keep their session key + `unixMs` projection; no virtual-core model; keep
`fl_chart`; daylight theme shipped; health chip + diagnostics; Riverpod deferred; BLE full history
built; live/history charts converged.

Still open / not built:
1. **Android 16 Live Update** progress notification (needs platform channel + device).
2. **CompanionDeviceManager** association (native Kotlin; changes pairing flow).
3. **Glance widget / Wear tile** (separate build targets).
4. **SoftAP `WifiNetworkSpecifier`** network-request API + coach-mark copy (`bindProcessToNetwork` is
   wired; the request API is not).
5. **Timed escalation re-post** (repeat sound if unacknowledged) — channels/quiet-hours/ack exist.
6. **Photo attach on a cook.**
7. **Localisation** — English only.
8. Never run on hardware: the §E.3 network rollback and the alarm-rule push read-back (Mock only).

### 14.4 Product-level questions a redesign should answer

1. Is a primary "Alerts" destination warranted, or is delivery a banner + a settings page?
2. Should the app lead as a **reader** (live first) with cooks as annotations, or keep a cook-centric
   mental model?
3. How much transport detail should be user-visible (preferred transport, hold-BLE, two-hop signal)?
4. Should live and history charts fully converge into one widget?
5. Where should alarm rules live, and should the two tiers stay visibly separate?
6. Should the settings tree be brought fully into the design system (currently the largest visual
   inconsistency)?
7. Is the copy discipline preserved verbatim? (It is the app's strongest asset.)
