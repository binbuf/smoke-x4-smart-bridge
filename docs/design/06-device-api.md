# 06 — Device API (HTTP + WebSocket)

The bridge's network interface. Identical in AP and STA mode. The canonical machine-readable
definition lives at `protocol/openapi.yaml`; this document explains the shape and the reasoning.

## 6.1 Conventions

|                 |                                                                                                                                                         |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base path       | `/api/v1`                                                                                                                                               |
| Transport       | HTTP/1.1, cleartext, port 80                                                                                                                            |
| Request bodies  | `application/json`, ≤ 8 KB (OTA excepted)                                                                                                               |
| Response bodies | `application/json` unless a `format` parameter says otherwise                                                                                           |
| Auth            | none by default; optional `Authorization: Bearer <token>` ([05 §5.9](05-connectivity-and-provisioning.md))                                              |
| CORS            | `Access-Control-Allow-Origin: *` — the device holds no secrets an attacker on the LAN couldn't read anyway, and it makes browser-based tooling painless |
| Time fields     | Unix ms (`_ms` suffix) or seconds-into-session (`t`), never local time                                                                                  |
| Temperatures    | tenths of °F as integers on the wire (`_f10`), matching the storage format. Clients convert for display                                                 |
| Concurrency     | `max_open_sockets = 7`; at most **2** concurrent WebSocket upgrades                                                                                     |

Every response — success or failure — is JSON. The reference replies to `POST`s with plain-text
`"Post control value successfully"`, which forces clients to special-case content types; we don't.

### Errors

```json
{
  "error": {
    "code": "session_not_found",
    "message": "no session 42",
    "detail": { "id": 42 }
  }
}
```

| Status | `code` examples                                     |
| ------ | --------------------------------------------------- |
| 400    | `invalid_body`, `invalid_field`, `unsupported_mode` |
| 401    | `unauthorized`                                      |
| 404    | `session_not_found`, `not_found`                    |
| 409    | `session_active`, `not_paired`, `busy`              |
| 413    | `body_too_large`                                    |
| 500    | `storage_error`, `internal`                         |
| 503    | `radio_unavailable`, `ota_in_progress`              |

### Streaming discipline

**No handler ever materializes a full response in RAM.** History endpoints stream from flash with
`httpd_resp_send_chunk` using a ≤ 2 KB stack buffer. This is the direct lesson from the reference's
16 KB `json_str` ceiling ([00](00-overview.md)) — it is a structural rule, not an optimization.

## 6.2 Endpoints

| Method   | Path                            | Purpose                                                                           |
| -------- | ------------------------------- | --------------------------------------------------------------------------------- |
| GET      | `/api/v1/status`                | Everything a dashboard header needs, in one call                                  |
| GET      | `/api/v1/live`                  | Current probe state + the in-RAM recent window                                    |
| GET      | `/api/v1/stream`                | **WebSocket** upgrade — push                                                      |
| GET      | `/api/v1/sessions`              | List cook sessions                                                                |
| POST     | `/api/v1/sessions`              | Start a session                                                                   |
| GET      | `/api/v1/sessions/{id}`         | Session header + stats                                                            |
| PATCH    | `/api/v1/sessions/{id}`         | Rename, set probe names/roles/targets, pin                                        |
| DELETE   | `/api/v1/sessions/{id}`         | Delete (refuses if active)                                                        |
| POST     | `/api/v1/sessions/{id}/stop`    | End the active session                                                            |
| GET      | `/api/v1/sessions/{id}/samples` | **Streamed** history — the workhorse                                              |
| GET      | `/api/v1/sessions/{id}/marks`   | Marks                                                                             |
| POST     | `/api/v1/sessions/{id}/marks`   | Add a mark                                                                        |
| GET      | `/api/v1/pairing`               | Pairing state                                                                     |
| POST     | `/api/v1/pairing/sync`          | Enter pairing mode                                                                |
| POST     | `/api/v1/pairing/unpair`        | Unpair                                                                            |
| GET/POST | `/api/v1/config/wifi`           | Network mode + credentials                                                        |
| GET/POST | `/api/v1/config/device`         | Units, display, retention, probes, calibration                                    |
| GET/POST | `/api/v1/config/alarms`         | Alarm rules                                                                       |
| POST     | `/api/v1/time`                  | Set the clock                                                                     |
| GET      | `/api/v1/radio`                 | LoRa parameters + link stats                                                      |
| POST     | `/api/v1/radio`                 | Set LoRa parameters (advanced)                                                    |
| POST     | `/api/v1/ota`                   | Upload firmware                                                                   |
| GET      | `/api/v1/debug/packets`         | Last N raw LoRa payloads                                                          |
| GET      | `/api/v1/debug/novelty`         | The pinned novelty log, verbatim `text/plain` ([02 §2.7](02-smoke-x-protocol.md)) |
| GET      | `/api/v1/debug/coredump`        | Stored panic dump, if any                                                         |
| GET      | `/*`                            | Static fallback web UI — **post-MVP** (§6.4); serves a built-in stub until then   |
| GET      | `/generate_204` etc.            | Captive-portal shims (AP mode) — [05 §5.8.1](05-connectivity-and-provisioning.md) |

### `GET /api/v1/status`

One round trip to render the entire app chrome. Deliberately chunky — on a 30-second-cadence device,
chattiness costs more than payload.

```json
{
  "device": {
    "id": "A4F2",
    "model": "heltec-v3",
    "fw": "1.0.0",
    "uptime_s": 51230,
    "free_heap": 168432,
    "min_free_heap": 141008,
    "reset_reason": "poweron",
    "coredump_available": false
  },
  "time": {
    "unix_ms": 1774094400000,
    "source": "phone",
    "tz_offset_min": -300,
    "valid": true
  },
  "net": {
    "mode": "sta",
    "state": "up",
    "ssid": "Backyard",
    "rssi": -54,
    "ip": "192.168.1.42",
    "host": "smokebridge.local",
    "ap_clients": 0
  },
  "ble": { "advertising": true, "connections": 1, "bonded": 2 },
  "pairing": {
    "paired": true,
    "device_id": "|abCDe",
    "model": "X4",
    "num_probes": 4,
    "frequency_hz": 910500000,
    "last_packet_s_ago": 12,
    "base_lost": false
  },
  "radio": {
    "rssi": -71,
    "snr": 9,
    "packets_ok": 4102,
    "packets_bad": 3,
    "id_mismatch": 0
  },
  "storage": {
    "total_b": 2490368,
    "used_b": 214016,
    "free_pct": 91,
    "sessions": 12,
    "oldest_session_id": 16
  },
  "power": { "mv": 3894, "soc_pct": 71, "charging": true, "saver": false },
  "session": {
    "active": true,
    "id": 27,
    "name": "Brisket",
    "started_unix_ms": 1774051200000,
    "elapsed_s": 43200,
    "samples": 1440
  },
  "alarms": [
    {
      "id": 3,
      "rule": "target_reached",
      "probe": 1,
      "since_unix_ms": 1774094100000,
      "acked": false
    }
  ]
}
```

### `GET /api/v1/live`

```
?window=7200          seconds of recent history to include (default 3600, max 7200 — the RAM ring)
&format=json|bin      default json
```

```json
{
  "t": 43200,
  "unix_ms": 1774094400000,
  "units_source": "F",
  "billows": { "attached": true, "target_f10": 2250 },
  "probes": [
    {
      "n": 1,
      "name": "Pit",
      "role": "pit",
      "attached": true,
      "temp_f10": 2431,
      "alarm_enabled": true,
      "min_f10": 2000,
      "max_f10": 2500,
      "target_f10": 2250,
      "rate_f_per_hr": -2.4
    },
    {
      "n": 2,
      "name": "Brisket",
      "role": "food",
      "attached": true,
      "temp_f10": 1632,
      "alarm_enabled": true,
      "min_f10": 0,
      "max_f10": 2030,
      "target_f10": 2030,
      "rate_f_per_hr": 4.1,
      "eta_s": 22800,
      "state": "stall"
    },
    { "n": 3, "attached": false },
    { "n": 4, "attached": false }
  ],
  "recent": {
    "t0": 36000,
    "step_s": 30,
    "count": 240,
    "series": [[2431, 2428, "…"], [1632, 1631, "…"], null, null]
  }
}
```

`recent.series[i]` is `null` for a probe that was detached for the whole window; individual
detached samples are `null` within a series. **Never `0`.**

The `billows` object is emitted because decoding it is free and the data should not be thrown away
— but per [D11](00-overview.md) the v1 app ignores it. Treat it as recorded, not surfaced.

### `GET /api/v1/sessions/{id}/samples` — the workhorse

```
?from=0&to=86400          seconds into the session (default whole)
&stride=1                 take every Nth record
&bucket=60&agg=minmax     bucket seconds + aggregation: none | mean | minmax
&format=bin|json|ndjson|csv       default bin
&probes=1,2               subset
```

**`format=bin`** — `application/octet-stream`, the raw 16-byte records
([04 §4.2](04-storage-and-history.md)), optionally strided. The app's sync path uses this: 24 hours
of full-fidelity data is 46 KB and parses in a few milliseconds in Dart.

**`format=json&bucket=90&agg=minmax`** — what the chart actually renders:

```json
{
  "session_id": 27,
  "from": 0,
  "to": 86400,
  "bucket_s": 90,
  "agg": "minmax",
  "count": 960,
  "probes": [1, 2],
  "series": [
    { "probe": 1, "min": [2400, "…"], "mean": [2431, "…"], "max": [2460, "…"] },
    { "probe": 2, "min": [1620, "…"], "mean": [1632, "…"], "max": [1640, "…"] }
  ],
  "gaps": [{ "from": 21600, "to": 23400 }]
}
```

`gaps` is computed from `t` deltas > 45 s and rendered as a break in the line. This is only possible
because samples carry time — the single most important schema decision in the project.

**`format=csv`** — `t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi`, detached probes as empty fields.

### `POST /api/v1/config/wifi`

```json
{
  "mode": "sta",
  "auth": "wpa2_psk",
  "ssid": "Backyard",
  "psk": "…",
  "username": null
}
```

`mode` ∈ `ap` | `sta`. Responds **before** reconfiguring, then defers ~500 ms so the reply flushes
before the interface is torn down:

```json
{
  "accepted": true,
  "applying_in_ms": 500,
  "expect": { "mode": "sta", "host": "smokebridge.local" }
}
```

For `mode: "ap"` the response carries the generated credentials so the client can display them:

```json
{
  "accepted": true,
  "applying_in_ms": 500,
  "expect": {
    "mode": "ap",
    "ssid": "SmokeBridge-A4F2",
    "psk": "Gk7mR2xQpT",
    "ip": "192.168.4.1"
  }
}
```

`GET` never returns a stored password (matching the reference — a good instinct worth keeping),
except the AP PSK, which is not a secret from anyone already on the AP and which the user needs to
read back.

### `POST /api/v1/config/device`

```json
{
  "display_units": "F",
  "display_timeout_s": 60,
  "led_enabled": true,
  "battery_saver": "auto",
  "retention": { "max_sessions": 64, "min_free_pct": 10 },
  "probes": [
    { "n": 1, "name": "Pit", "role": "pit", "target_f10": 2250 },
    { "n": 2, "name": "Brisket", "role": "food", "target_f10": 2030 }
  ],
  "vbat_actual_mv": 4020
}
```

`vbat_actual_mv` is the one-point battery calibration ([01 §1.3](01-hardware.md)): send a DMM
reading and the firmware solves for the divider ratio and persists it.

### `POST /api/v1/ota`

`Content-Type: application/octet-stream`, the raw `.bin`. Streams into the inactive OTA slot,
verifies the image header and SHA-256, sets the boot partition, replies, and reboots. Progress is
pushed on the WebSocket. The new image is _pending verify_ until the health gate in
[03 §3.7](03-firmware-architecture.md) passes; otherwise the next reset rolls back.

Refused with `409` while a cook session is active unless `?force=1` — nobody should discover a bad
flash 14 hours into a brisket.

### `POST /api/v1/restart` · `POST /api/v1/factory-reset` · `POST /api/v1/power-off`

The v1.1 destructive verbs (D15). With every control moved off the button, these are the app's only
way to reach them; BLE has carried `reboot`/`factory_reset` since M3 and gained `power_off` as op 13.

| Route            | Effect                                                                         |
| ---------------- | ------------------------------------------------------------------------------ |
| `/restart`       | Reboot. Sessions resume from NVS on the way back up ([04](04-storage-and-history.md)) |
| `/factory-reset` | Wipes config, pairing, BLE bonds, **and all cook history**, then reboots        |
| `/power-off`     | Deep sleep. Replies `wake_requires_button: true` — see below                    |

All three **answer before they act**: the handler replies, then a ~500 ms timer fires the real
operation, so the HTTP response actually flushes before the device dies. This is the same idiom
`/ota` uses for its post-flash reboot. `factory-reset` wipes *before* scheduling the restart, so a
lost timer cannot leave a half-wiped bridge.

`power-off` is the one asymmetric verb in the API: it can be sent remotely, but **waking is
physical** — a sustained hold of PRG ([07 §7.4](07-display-and-controls.md)). Any client offering
it must say so first, because the user may be nowhere near the smoker.

## 6.3 WebSocket — `GET /api/v1/stream`

Push instead of polling. At a 30-second cadence, polling burns battery on both ends for nothing.

Server → client frames, JSON text:

```json
{ "type": "sample",  "t": 43230, "unix_ms": 1774094430000,
  "temps_f10": [2429, 1634, null, null], "flags": { "billows": true }, "rssi": -70 }

{ "type": "alarm",   "action": "raised", "id": 4, "rule": "target_reached",
  "probe": 2, "value_f10": 2031, "message": "Brisket reached 203.1°F" }

{ "type": "session", "action": "started", "id": 28, "name": "Cook #28" }
{ "type": "net",     "mode": "sta", "state": "up", "ip": "192.168.1.42" }
{ "type": "pairing", "paired": true, "device_id": "|abCDe", "num_probes": 4 }
{ "type": "power",   "soc_pct": 68, "charging": false, "saver": true }
{ "type": "ota",     "phase": "writing", "pct": 42 }
{ "type": "hello",   "fw": "1.0.0", "api": "v1", "server_time_ms": 1774094430000 }
```

Client → server:

```json
{ "type": "subscribe", "topics": ["sample", "alarm", "session", "net", "power"] }
{ "type": "ping" }
{ "type": "ack_alarm", "id": 4 }
```

- The server sends `hello` immediately on connect, then the current `sample`, so the client has
  state without a separate `GET`.
- Keepalive: server `ping` every 30 s; a client that misses two is dropped.
- **Max 2 concurrent WebSocket clients.** A third gets `503 { "code": "busy" }` — a hard limit that
  falls straight out of the RAM budget ([01 §1.4](01-hardware.md)), stated in the contract rather
  than discovered as flakiness.
- While a WebSocket client is connected in STA mode, Wi-Fi power save drops to `WIFI_PS_NONE` for
  responsiveness, and returns to `MIN_MODEM` 60 s after the last client leaves.

## 6.4 The fallback web UI — post-MVP (D13)

**Not in the MVP.** The `www` partition is reserved and left empty
([03 §3.5](03-firmware-architecture.md)); unmatched `GET`s return a small built-in page pointing at
the app, and the captive-portal probes answer from string constants. Nothing in the API depends on
it, and reclaiming the 512 KB for history is a one-line partition change if the answer turns out to
be no.

If it is built later, the case for it is: setup and recovery from a laptop when the app isn't
installed, a browser target for the captive portal, and debugging without a build toolchain. Scope
would be status, live temps, a simple chart, network config, pairing, and OTA — the reference's
Vue 3 + Chart.js UI already covers most of that and is MIT, so porting it to this API is the
obvious starting point.

Serving would follow the reference's approach, which is well judged: pre-gzipped assets with
`Content-Encoding: gzip`, `Cache-Control: max-age=604800` for hashed filenames and `no-cache` for
stable-named ones (`manifest`, `sw.js`, icons).

Deciding this early costs nothing; deciding it _late_ is why the partition exists now.

## 6.5 Versioning

- The path carries the major version. `/api/v2` would be served alongside `/api/v1` during any
  transition.
- Additive fields are not breaking; clients must ignore unknown keys.
- `GET /api/v1/status` reports `fw` and `api`, and the app enforces a minimum firmware version,
  prompting for OTA rather than failing in an obscure way.
- The binary sample format versions independently through the session header's `version` /
  `rec_len` ([04 §4.10](04-storage-and-history.md)).
  </content>
