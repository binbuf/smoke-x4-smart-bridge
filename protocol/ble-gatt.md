# BLE — Bridge Control Service (GATT contract)

Normative contract for the bridge's custom GATT service (design decision D1 — no
`wifi_provisioning`, no CBOR/protobuf). Stack: **NimBLE** (D6).

Sources, in order of authority:

1. [`protocol/records.yaml`](records.yaml) — **source of truth** for every payload byte layout
   (`ble_payloads` and `control_bodies` sections). This document restates those layouts as
   byte-offset tables; on any conflict, `records.yaml` and the generated codecs
   ([`gen/record_gen.h`](gen/record_gen.h), [`gen/records.g.dart`](gen/records.g.dart)) win.
2. [Design 05 §5.6](../docs/design/05-connectivity-and-provisioning.md) — service shape,
   security, advertising, MTU strategy, coexistence.

Two payloads appear **only** here, because `records.yaml` does not (yet) describe them:
`device_info` (`0x0001`) and `wifi_scan_ctrl` (`0x0003`). Their tables in §5 are normative and
are marked *(defined by this document)*; they must be folded into `records.yaml` before the
firmware BLE service (M3) implements them.

Conventions, everywhere, no exceptions:

- **Little-endian** for every multi-byte field.
- Every payload starts with a **`ver` byte, currently `1`**. Readers never reject on `ver`;
  unknown trailing bytes are ignored (additive growth).
- Temperatures are **`i16`, tenths of °F**, with the named sentinels
  `TEMP_DETACHED = -32768` (`INT16_MIN`, probe detached — must surface as *null*, never 0) and
  `TEMP_INVALID = -32767` (`INT16_MIN + 1`, probe present but reading invalid).

---

## 1. Service and characteristic UUIDs

Base UUID: `7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162`. The service is
`7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162`; each characteristic replaces `XXXX`:

| `XXXX`  | Characteristic     | Properties   | Security                    | Payload |
| ------- | ------------------ | ------------ | --------------------------- | ------- |
| `0000`  | **Bridge Control Service** | —    | —                           | — |
| `0001`  | `device_info`      | Read         | open (unencrypted)          | fixed 40 B (§5.1) |
| `0002`  | `net_status`       | Read, Notify | encrypted                   | variable ≤ 64 B (§5.2) |
| `0003`  | `wifi_scan_ctrl`   | Write        | encrypted                   | fixed 2 B (§5.3) |
| `0004`  | `wifi_scan_result` | Notify       | encrypted                   | variable ≤ 39 B (§5.4) |
| `0005`  | `wifi_config`      | Write        | **encrypted + authenticated** | variable ≤ 134 B (§5.5) |
| `0006`  | `device_control`   | Write        | **encrypted + authenticated** | variable ≤ 30 B (§5.6) |
| `0007`  | `live_state`       | Read, Notify | encrypted                   | fixed 16 B (§5.7) |
| `0008`  | `history_preview`  | Read         | encrypted                   | variable ≤ 244 B (§5.8) |
| `0009`  | `result`           | Notify       | encrypted                   | variable ≤ 68 B (§5.9) |

Every characteristic with Notify carries a standard CCCD (`0x2902`); writing it requires the
same security level as the characteristic value.

---

## 2. Advertising and scan response

| | |
| --- | --- |
| Local name | `SmokeBridge-XXXX` — `XXXX` = last two bytes of the Wi-Fi MAC in hex, same suffix as the AP SSID (§5.3 of design 05) and the mDNS TXT `id` |
| Adv payload | Flags + the 128-bit service UUID (the UUID alone is 16 of the 31 legacy bytes) |
| Scan response | Complete local name + manufacturer-specific status blob |
| Interval | **500 ms** idle; **250 ms for 60 s** after a button press or a fresh boot |

### 2.1 Advertising PDU (legacy, 31-byte budget)

| Offset | Size | AD type | Content |
| ------ | ---- | ------- | ------- |
| 0 | 3 | `0x01` Flags | `0x06` — LE General Discoverable, BR/EDR not supported |
| 3 | 18 | `0x07` Complete List of 128-bit Service UUIDs | `7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162` (16 B, little-endian on air) |

Total: **21 of 31 bytes**. The name does not fit next to a 128-bit UUID, so it lives in the
scan response.

### 2.2 Scan-response PDU

| Offset | Size | AD type | Content |
| ------ | ---- | ------- | ------- |
| 0 | 18 | `0x09` Complete Local Name | `SmokeBridge-XXXX` (16 ASCII chars) |
| 18 | 11 | `0xFF` Manufacturer Specific Data | 2-byte company ID + 7-byte status blob (below) |

Total: **29 of 31 bytes**. Company ID: `0xFFFF` (Bluetooth SIG reserved test ID) until a real
one is assigned *(defined by this document — design 05 is silent)*.

### 2.3 Manufacturer status blob (7 B, after the company ID)

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `flags` | u8 | same bit assignments as `live_state.flags` (§5.7) |
| 2 | 2 | `pit_temp` | i16 LE | pit probe, tenths °F; `TEMP_DETACHED` / `TEMP_INVALID` sentinels |
| 4 | 1 | `soc` | u8 | battery state of charge, 0–100 |
| 5 | 2 | `session_minutes` | u16 LE | minutes into the active session; 0 when none |

This is what lets the app's device list render *"Smoke Bridge · pit 243 °F · 4 h 12 m"*
without connecting.

---

## 3. Security profile

**LE Secure Connections with Passkey Entry.** The bridge generates a 6-digit passkey and
**displays it on the OLED** (IO capability: DisplayOnly); the user types it into the app.
This yields an authenticated (MITM-protected) LTK — the display is what lets us do better
than Just Works, and it costs nothing.

| Level | Applies to | Meaning |
| ----- | ---------- | ------- |
| open | `device_info` | readable with no pairing at all, so the app can identify a bridge before bonding |
| encrypted | `net_status`, `wifi_scan_ctrl`, `wifi_scan_result`, `live_state`, `history_preview`, `result` | link must be encrypted (any bond) |
| encrypted + **authenticated** | `wifi_config`, `device_control` | link key must be MITM-authenticated (passkey pairing) — these two can change network config or wipe the device |

Bonding:

- Bonds persist in **NVS**, up to **3 phones**. A fourth pairing attempt is rejected until a
  slot is freed.
- **Forget all phones**, three paths: the settings UI, the 10 s PRG-hold factory reset, and
  `device_control` op 8 `factory_reset` (the frozen v1 op table has no narrower
  forget-bonds op; a full factory reset is the BLE path).

---

## 4. MTU strategy

**Request ATT_MTU 247 on connect.** 247 is chosen so the largest payload,
`history_preview` at 244 B, fits a single ATT PDU (244 + 3 = 247).

**`live_state` must survive a failed negotiation** — the single most likely Android BLE
failure (risk R7). At the default ATT_MTU of 23 the usable notify payload is
`23 − 3 = 20 B`. Summing the `live_state` fields:

| Field | Type | Bytes |
| ----- | ---- | ----- |
| `ver` | u8 | 1 |
| `flags` | u8 | 1 |
| `temp[4]` | i16 × 4 | 8 |
| `soc_pct` | u8 | 1 |
| `rssi_lora` | i8 | 1 |
| `session_t` | u32 | 4 |

**1 + 1 + 8 + 1 + 1 + 4 = 16 B, and 16 ≤ 20** — live telemetry works even when MTU
negotiation fails and the connection sits at the 23-byte default.

Everything else degrades by **chunking, with the chunk boundary derived from the negotiated
MTU**:

- **Reads** (`device_info`, `net_status`, `live_state`, `history_preview`): standard ATT
  Read Blob — first Read Response carries `MTU − 1` bytes, the client issues offset reads
  for the rest. The stack does this; no custom framing.
- **Writes** (`wifi_scan_ctrl`, `wifi_config`, `device_control`): a value longer than
  `MTU − 3` uses queued writes (Prepare/Execute, `MTU − 5` per segment). Again stack-level.
- **Notifications** (`net_status`, `wifi_scan_result`, `result`): ATT cannot fragment a
  notification. A payload longer than `MTU − 3` is sent as consecutive notifications split
  at `MTU − 3`-byte boundaries; the client concatenates until the total length implied by
  the payload's fixed-prefix length fields is reached. Every variable payload's fixed prefix
  is ≤ 10 B, so the prefix — and therefore the total length — always arrives whole in the
  first chunk even at the 20-byte default.

---

## 5. Payload layouts

All layouts restate `records.yaml` (`ble_payloads` / `control_bodies`); offsets and sizes
below were cross-checked against the generated `gen/records.g.dart` encoders.

### 5.1 `0001 device_info` — Read, open *(defined by this document)*

Fixed 40 B. The unencrypted identity card, mirroring the mDNS TXT records
(`id`, `model`, `fw`, `api`, `probes`).

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `api` | u8 | HTTP/BLE API major version, `1` |
| 2 | 1 | `probes` | u8 | 2 or 4 |
| 3 | 1 | `caps` | u8 | b0 `wifi_ap` · b1 `wifi_sta` · b2 `wifi_enterprise` · b3 `history_preview` · b4 `ota` · b5–b7 reserved |
| 4 | 4 | `id` | char[4] | device id, e.g. `A4F2` (ASCII hex, matches SSID/name suffix) |
| 8 | 16 | `model` | char[16] | UTF-8, NUL-padded, e.g. `heltec-v3` |
| 24 | 16 | `fw` | char[16] | UTF-8, NUL-padded, e.g. `1.0.0` |

Total: 1 + 1 + 1 + 1 + 4 + 16 + 16 = **40 B**.

### 5.2 `0002 net_status` — Read + Notify, encrypted

Variable, ≤ 64 B. Notified on every network state transition (the app watches this across
the §5.7 handoff).

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `mode` | u8 | `net_mode`: 0 off · 1 AP · 2 STA |
| 2 | 1 | `state` | u8 | `net_state`: 0 idle · 1 connecting · 2 up · 3 failed |
| 3 | 1 | `wifi_rssi` | i8 | dBm; meaningless unless `state = up` in STA |
| 4 | 4 | `ip` | u8[4] | IPv4, byte 4 = first octet |
| 8 | 1 | `ssid_len` | u8 | ≤ 32 |
| 9 | 1 | `host_len` | u8 | ≤ 22 |
| 10 | `ssid_len` | `ssid` | char[] | UTF-8, no NUL |
| 10 + `ssid_len` | `host_len` | `host` | char[] | UTF-8, no NUL, e.g. `smokebridge` |

Wire length: `10 + ssid_len + host_len`; maximum 10 + 32 + 22 = **64 B**.

### 5.3 `0003 wifi_scan_ctrl` — Write, encrypted *(defined by this document)*

Fixed 2 B. Starts (or cancels) an AP scan; results arrive on `0004`, completion is implicit
in the last result's `index == total − 1`.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `cmd` | u8 | 1 = start scan · 0 = cancel |

A scan already in progress answers `result{op_echo: 0, status: busy}`.

### 5.4 `0004 wifi_scan_result` — Notify, encrypted

Variable; one AP per notification. Declared budget 40 B in `records.yaml`; the maximum
reachable wire length is 7 + 32 = **39 B**.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `index` | u8 | 0-based position of this AP |
| 2 | 1 | `total` | u8 | number of notifications in this scan |
| 3 | 1 | `rssi` | i8 | dBm |
| 4 | 1 | `auth` | u8 | auth mode (§5.4.1) |
| 5 | 1 | `channel` | u8 | 1–14 |
| 6 | 1 | `ssid_len` | u8 | ≤ 32 |
| 7 | `ssid_len` | `ssid` | char[] | UTF-8, no NUL |

#### 5.4.1 `auth` values *(defined by this document — `records.yaml` declares a plain u8; values follow ESP-IDF `wifi_auth_mode_t`)*

| Value | Mode |
| ----- | ---- |
| 0 | open |
| 1 | WEP |
| 2 | WPA-PSK |
| 3 | WPA2-PSK |
| 4 | WPA/WPA2-PSK |
| 5 | WPA2-Enterprise (EAP-TTLS/MSCHAPv2) |
| 6 | WPA3-PSK |
| 7 | WPA2/WPA3-PSK |

### 5.5 `0005 wifi_config` — Write, encrypted + authenticated

Variable, ≤ 134 B. The reply arrives on `result` (`0009`); reconfiguration is deferred
~500 ms so the BLE acknowledgement flushes before the radio reconfigures (design 05 §5.4).

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `mode` | u8 | `net_mode`: 0 off · 1 AP · 2 STA |
| 2 | 1 | `auth` | u8 | target auth mode (§5.4.1); ignored for AP |
| 3 | 1 | `ssid_len` | u8 | ≤ 32 |
| 4 | 1 | `psk_len` | u8 | ≤ 64 |
| 5 | 1 | `user_len` | u8 | ≤ 32; nonzero selects WPA2-Enterprise |
| 6 | `ssid_len` | `ssid` | char[] | UTF-8, no NUL |
| 6 + `ssid_len` | `psk_len` | `psk` | char[] | password / passphrase |
| 6 + `ssid_len` + `psk_len` | `user_len` | `user` | char[] | WPA2-Enterprise identity |

Wire length: `6 + ssid_len + psk_len + user_len`; maximum 6 + 32 + 64 + 32 = **134 B**.

### 5.6 `0006 device_control` — Write, encrypted + authenticated

Variable, ≤ 30 B: a 2-byte header plus an op-specific body (≤ 28 B). Every write is
answered on `result` (`0009`) with `op_echo` set to the op.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `op` | u8 | `control_op`, table below |
| 2 | 0–28 | `body` | u8[] | op-specific; length implicit from the ATT write length |

#### 5.6.1 Op table (`control_op`)

| Op | Name | Body | Total write | Action |
| -- | ---- | ---- | ----------- | ------ |
| 1 | `pair` | — | 2 B | enter sync/scan mode toward the base station |
| 2 | `unpair` | — | 2 B | forget the paired base |
| 3 | `set_time` | 10 B (§5.6.2) | 12 B | set wall clock + timezone |
| 4 | `session_start` | — | 2 B | start a cook session |
| 5 | `session_stop` | — | 2 B | stop the session |
| 6 | `mark` | 2–26 B (§5.6.3) | 4–28 B | drop a mark into the session |
| 7 | `reboot` | — | 2 B | reboot the bridge |
| 8 | `factory_reset` | — | 2 B | wipe NVS (incl. all bonds), sessions, config |
| 9 | `set_units` | 1 B (§5.6.4) | 3 B | display units preference |
| 10 | `identify` | — | 2 B | flash the LED and screen for 5 s |
| 11 | `ack_alarm` | 1 B (§5.6.5) | 3 B | acknowledge an active alarm |

Ops not listed with a body carry none. Offsets below are **within the body**, i.e. relative
to byte 2 of the write.

#### 5.6.2 `set_time` body (op 3, 10 B)

| Body offset | (abs) | Size | Field | Type | Meaning |
| ----------- | ----- | ---- | ----- | ---- | ------- |
| 0 | 2 | 8 | `unix_ms` | u64 LE | milliseconds since Unix epoch |
| 8 | 10 | 2 | `tz_offset_min` | i16 LE | minutes east of UTC |

#### 5.6.3 `mark` body (op 6, 2–26 B)

| Body offset | (abs) | Size | Field | Type | Meaning |
| ----------- | ----- | ---- | ----- | ---- | ------- |
| 0 | 2 | 1 | `kind` | u8 | `mark_kind`: 0 note · 1 wrapped · 2 lid_open · 3 fuel · 4 probe_moved · 5 alarm · 6 phase_change · 7 auto_detected |
| 1 | 3 | 1 | `len` | u8 | ≤ 24 |
| 2 | 4 | `len` | `text` | char[] | UTF-8, no NUL |

#### 5.6.4 `set_units` body (op 9, 1 B)

| Body offset | (abs) | Size | Field | Type | Meaning |
| ----------- | ----- | ---- | ----- | ---- | ------- |
| 0 | 2 | 1 | `units` | u8 | 0 = °C · 1 = °F (display preference only; storage stays tenths °F) |

#### 5.6.5 `ack_alarm` body (op 11, 1 B)

| Body offset | (abs) | Size | Field | Type | Meaning |
| ----------- | ----- | ---- | ----- | ---- | ------- |
| 0 | 2 | 1 | `alarm_id` | u8 | the alarm being acknowledged |

### 5.7 `0007 live_state` — Read + Notify, encrypted

**Fixed 16 B** — deliberately ≤ 20 B so it fits the default ATT MTU (§4). Notified on every
decoded LoRa packet (~30 s) plus immediately on any alarm transition.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `flags` | u8 | b0 `paired` · b1 `session_active` · b2 `billows` · b3 `alarm_active` · b4 `clock_valid` · b5–b7 reserved |
| 2 | 2 | `temp[0]` | i16 LE | tenths °F; `TEMP_DETACHED` = detached, `TEMP_INVALID` = invalid |
| 4 | 2 | `temp[1]` | i16 LE | ” |
| 6 | 2 | `temp[2]` | i16 LE | ” |
| 8 | 2 | `temp[3]` | i16 LE | ” |
| 10 | 1 | `soc_pct` | u8 | battery state of charge, 0–100 |
| 11 | 1 | `rssi_lora` | i8 | dBm of the last state message |
| 12 | 4 | `session_t` | u32 LE | seconds into the active session; 0 when none |

Sum: 1 + 1 + 8 + 1 + 1 + 4 = **16 B ≤ 20 B** (see §4).

### 5.8 `0008 history_preview` — Read, encrypted

Variable, ≤ 244 B: one probe's temperature at 1-minute buckets for the last 2 h — enough to
draw a real sparkline over BLE alone. Full history over BLE is deferred to v1.1.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `probe_index` | u8 | 0-based; the pit probe in v1.0 |
| 2 | 1 | `count` | u8 | ≤ 120 |
| 3 | 1 | `bucket_min` | u8 | bucket width in minutes, nominal 1 |
| 4 | `count` × 2 | `values` | i16[] LE | tenths °F, oldest first; `TEMP_DETACHED` / `TEMP_INVALID` sentinels |

Wire length: `4 + 2 × count`; maximum 4 + 240 = **244 B** (a single PDU at MTU 247;
Read Blob otherwise).

### 5.9 `0009 result` — Notify, encrypted

Variable, ≤ 68 B. Outcome of the last `wifi_scan_ctrl`, `wifi_config`, or `device_control`
write.

| Offset | Size | Field | Type | Meaning |
| ------ | ---- | ----- | ---- | ------- |
| 0 | 1 | `ver` | u8 | `1` |
| 1 | 1 | `op_echo` | u8 | the `control_op` being answered (0 for `wifi_scan_ctrl`/`wifi_config`) |
| 2 | 1 | `status` | u8 | 0 ok · 1 invalid · 2 busy · 3 failed · 4 unauthorized |
| 3 | 1 | `len` | u8 | ≤ 64 |
| 4 | `len` | `detail` | char[] | UTF-8: the **AP PSK** after a mode change to AP, or an error string |

Wire length: `4 + len`; maximum 4 + 64 = **68 B**.

---

## 6. Wi-Fi / BLE coexistence

Wi-Fi and BLE share the single 2.4 GHz radio; `CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y`
(design 05 §5.6). Expectations a client must tolerate:

- **BLE notification jitter under Wi-Fi load** — do not treat a late `live_state` as a lost
  bridge; the staleness threshold belongs above the transport.
- **~20–30 % lower AP throughput while advertising.** At one 16-byte notification per 30 s
  and a few KB of HTTP, neither side notices in practice.
- The SX1262 LoRa radio is sub-GHz and independent of this contention — but that is
  confirmed empirically on the bench ([01 §1.8](../docs/design/01-hardware.md)), not assumed.

---

## Appendix A — cross-check against the generated codecs

Offsets above were verified against the encoders in `gen/records.g.dart` (byte-identical
copies: `tools/bridge_protocol/lib/records.g.dart`, `app/lib/data/dto/records.g.dart`):

| Doc section | Generated symbol | Size / max |
| ----------- | ---------------- | ---------- |
| §5.2 | `NetStatus.pack/unpack` | max 64 |
| §5.4 | `WifiScanResult.pack/unpack` | max 40 declared, 39 reachable |
| §5.5 | `WifiConfig.pack/unpack` | max 134 |
| §5.6 | `DeviceControl.pack/unpack` | max 30 |
| §5.6.2 | `CtrlSetTime.encode/decode` | 10 |
| §5.6.3 | `CtrlMark.pack/unpack` | max 26 |
| §5.6.4 | `CtrlSetUnits.encode/decode` | 1 |
| §5.6.5 | `CtrlAckAlarm.encode/decode` | 1 |
| §5.7 | `LiveState.encode/decode` | 16 |
| §5.8 | `HistoryPreview.pack/unpack` | max 244 |
| §5.9 | `ResultFrame.pack/unpack` | max 68 |

`device_info` (§5.1) and `wifi_scan_ctrl` (§5.3) have no generated codec yet — see the note
at the top of this file.
