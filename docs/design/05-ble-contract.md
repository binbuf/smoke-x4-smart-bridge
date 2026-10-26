# 05 — BLE Contract

The bridge exposes one custom GATT service. There is no Wi-Fi provisioning
service, no HTTP, and no OTA characteristic.

This is a **new service**, not the legacy `7f9a…` contract. The UUID base is
bumped so a legacy app cannot accidentally connect and misread a payload. The
payload encoders may reuse code patterns, but the contract is defined here.

## 5.1 Service and characteristics

Base UUID:

```
7f9bXXXX-4c5b-4b0f-9a3d-1c2e3f405162
```

Service: `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162`

| Slot | Characteristic | Properties | Security | Payload |
|---|---|---|---|---|
| `0001` | `info` | Read | open | 32 B fixed |
| `0002` | `live` | Read, Notify | encrypted | 20 B fixed |
| `0003` | `control` | Write | **encrypted + authenticated** | variable ≤ 16 B |
| `0004` | `result` | Notify | encrypted | variable ≤ 64 B |
| `0005` | `sync_ctrl` | Write | encrypted | 10 B fixed |
| `0006` | `sync_data` | Notify | encrypted | framed, ≤ MTU−3 |
| `0007` | `config` | Read, Write | **encrypted + authenticated** | 80 B fixed |
| `0008` | `stats` | Read | encrypted | 60 B fixed |

Every characteristic with Notify has a standard CCCD (`0x2902`). Writing a CCCD
requires the same security level as the characteristic.

All multi-byte fields are **little-endian**. Every payload begins with
`ver = 1`. Readers ignore unknown trailing bytes; they never reject on `ver`
alone. An unknown **major** protocol version is a named refusal, not a parse
gamble.

## 5.2 Advertising

| | |
|---|---|
| Local name | `SmokeX4-XXXX`, where `XXXX` is the last two bytes of the BLE MAC in uppercase hex |
| Advertising PDU | Flags + 128-bit service UUID (21 of 31 bytes) |
| Scan response | Complete local name + manufacturer-specific status blob |
| Interval | 250 ms for 60 s after boot/button/disconnect, then 1,000 ms |
| Starts | At boot when not connected; on disconnect; after failed connect; on advertising timeout |
| Stops | On connection |

BLE is peripheral-only: the bridge advertises; the app initiates the connection.
"Automatic discovery" means the bridge is always findable when it is on and
idle, not that the bridge scans for phones.

### Scan-response status blob (9 B after the 2-byte company ID)

Company ID: `0xFFFF` (Bluetooth SIG reserved test ID) for the bench build. Do not
ship a production advertisement with a test company ID; assign one before a
public release. The app must not require manufacturer data.

| Offset | Size | Field | Meaning |
|---|---:|---|---|
| 0 | 1 | `ver` | 1 |
| 1 | 1 | `flags` | Same bits as `live.flags` |
| 2 | 2 | `pit_temp_f10` | P4 (the fixed pit/Billows channel), tenths °F; sentinels allowed |
| 4 | 1 | `battery_pct` | 0–100, or 255 unknown |
| 5 | 2 | `billows_target_f10` | Observed/controlled target; 0 unknown |
| 7 | 1 | `age_s` | Seconds since last valid Smoke X4 packet, clamped 0–255 |
| 8 | 1 | reserved | 0 |

The scan response is optional decoration. The app must work if it is absent or
malformed.

### 5.2.1 MTU and notification reassembly

The app requests ATT MTU **247**, but every fixed payload is designed to work at
the default MTU 23 (20-byte notification payload).

| Characteristic | Read/write | Notification |
|---|---|---|
| `info` (32 B) | Read Blob (`MTU−1` per response) | — |
| `live` (20 B) | single read or Blob | single notification, always fits |
| `config` (80 B) | Read Blob; write uses queued writes | — |
| `stats` (60 B) | Read Blob | — |
| `result` | — | split at `MTU−3`; first 5 bytes carry `len`, so the app knows the total |
| `sync_data` | — | framed stream; 4-byte frame header + payload, reassembled by flags |

A notification is never assumed to be one record. The app treats each
`sync_data` notification as bytes in a stream and each `result` notification as
a chunk until `5 + len` bytes have arrived.

If the negotiated MTU is below 64, sync still works but is slow: at the default
MTU 23 the 16-byte frame payload means roughly 50 s for 24 h and ~45–50 min for
the full ring, versus seconds/minutes at MTU 247. The app records the negotiated
value, shows a "slow Bluetooth link" note, and keeps full-ring backfill in the
background. It is not an error.

## 5.3 `0001 info` — Read, open

Fixed 32 B. Safe to read before bonding.

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `proto_major` |
| 2 | 1 | `proto_minor` |
| 3 | 1 | `caps` |
| 4 | 1 | `probes` (2 or 4) |
| 5 | 1 | reserved |
| 6 | 4 | `device_id` ASCII hex, e.g. `A4F2` |
| 10 | 12 | `fw` UTF-8, NUL-padded |
| 22 | 8 | `model` UTF-8, NUL-padded, e.g. `heltec3` |
| 30 | 1 | `bonds_free` (0–4) |
| 31 | 1 | reserved |

### `caps`

| Bit | Meaning |
|---|---|
| 0 | `billows_observe` — the bridge decodes attached/target fields |
| 1 | `billows_control` — the bridge can set a target and drive the fan |
| 2 | `history` — sync is supported |
| 3 | `battery` — a real battery reading exists |
| 4 | `display_config` — display timeout/units configurable |
| 5 | `power_off` — app can request deep sleep |
| 6 | `factory_reset` — app can request a full wipe |
| 7 | `config` — the config characteristic is writable |

A client must not invent a capability the bit does not set. In particular,
`billows_control = 0` means the target field is read-only.

## 5.4 `0002 live` — Read, Notify, encrypted

Fixed 20 B. This fits the default ATT MTU 23 notification payload (20 B), so
live telemetry still works if MTU negotiation fails.

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `flags` |
| 2 | 8 | `temp[4]` i16, tenths °F, sentinels |
| 10 | 4 | `seq` u32, last stored sample sequence; `0xFFFFFFFF` if none |
| 14 | 2 | `billows_target_f10` i16; 0 = unknown |
| 16 | 1 | `battery_pct`; 255 = unknown |
| 17 | 1 | `rssi_lora` i8 |
| 18 | 2 | `age_s` u16, seconds since last valid Smoke X4 state packet |

### `flags`

| Bit | Meaning |
|---|---|
| 0 | `smoke_paired` |
| 1 | `smoke_live` — a valid state packet within the last 90 s |
| 2 | `billows_attached` — observed from the Smoke X4 |
| 3 | `billows_output` — the bridge is currently driving a fan output |
| 4 | `clock_valid` |
| 5 | `storage_ok` — the sample log is writable |
| 6 | `display_on` |
| 7 | `sync_active` — a history transfer is in flight |

Notifications are sent on every stored sample and whenever a flag changes
(connection, pairing, Billows, clock, display, sync start/end). The app should
tolerate a missing notification and catch up by sync.

### Example vector

Probe 1 = 225.0 °F, probe 2 = 165.2 °F, probe 3 detached, probe 4 = 80.0 °F,
seq = 1234, Billows target 225.0 °F, battery 87%, RSSI −71, age 12 s, flags
`paired|live|billows|clock`:

```
01 17 CA 08 74 06 00 80 20 03 D2 04 00 00 CA 08 57 B9 0C 00
```

## 5.5 `0003 control` — Write, authenticated

```
ver u8, op u8, op_id u8, body…
```

`op_id` is chosen by the app (0–255, wrapping) and echoed in `result`. The app
must not reuse an outstanding `op_id`.

| `op` | Name | Body | Meaning |
|---:|---|---|---|
| 1 | `set_time` | `unix_ms u64, tz_offset_min i16` | Set the bridge clock |
| 2 | `forget_phone` | — | Remove the **current phone's** bond, disconnect, re-advertise; other bonds remain |
| 3 | `factory_reset` | — | Wipe config, bonds, history; reboot |
| 4 | `power_off` | — | Enter deep sleep |
| 5 | `clear_history` | — | Erase the sample ring; keep config/pairing; new generation |
| 6 | `set_billows_target` | `target_f10 i16` | Set fan target; only if `caps.billows_control` |
| 7 | `unpair_smoke_x` | — | Forget the Smoke X4 pairing, keep log/config/bonds, restart the 915/920 scan |

Rules:

- A write on an unencrypted link gets `ATT 0x0F Insufficient Encryption`; a
  write on an encrypted-but-not-authenticated link gets `ATT 0x05 Insufficient
  Authentication`. The app treats both as "bond/authenticate first", not "retry
  forever".
- The device validates the whole body before acting. A malformed body changes
  nothing.
- Destructive ops answer **first**, then act on a short timer (≈250 ms) so the
  result notification can leave before the link drops or the device reboots.
- `factory_reset` wipes before scheduling the reboot; a lost timer must not
  leave a half-wiped device.
- `set_billows_target` returns `unsupported` when `caps.billows_control = 0` or
  the chosen Billows mode is observe-only.
- `unpair_smoke_x` answers `ok`, clears the stored device ID/frequency, keeps the
  log and phone bonds, and starts the sync scan. The app then tells the user to
  put the Smoke X4 in SYNC.
- `forget_phone` removes only the current phone's bond; the app clears its local
  bond after receiving `ok` or after the disconnect, whichever comes first.
  Other bonded phones are unaffected.

## 5.6 `0004 result` — Notify, encrypted

```
ver u8
op u8
op_id u8
status u8
len u8
detail[len] UTF-8, ≤ 59
```

Maximum 64 B.

| `status` | Name | App behaviour |
|---:|---|---|
| 0 | `ok` | Continue |
| 1 | `invalid` | Fix the input; do not blind-retry |
| 2 | `unsupported` | Hide/disable the feature and explain |
| 3 | `busy` | Retry once after the current transfer |
| 4 | `unauthorized` | Bond/authenticate first |
| 5 | `failed` | Named failure; offer retry |
| 6 | `not_found` | Resource/feature absent |
| 7 | `storage` | Storage unavailable; show it |

`detail` is for humans ("clock out of range", "bond store full"), not for
machine branching. The status code is the branch.

## 5.7 `0005 sync_ctrl` — Write, encrypted

10 B.

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `cmd`: 0 status, 1 read, 2 cancel |
| 2 | 1 | `direction`: 0 forward, 1 backward |
| 3 | 4 | `cursor_seq` u32 |
| 7 | 1 | reserved |
| 8 | 2 | `max_records` u16, 1–64; 0 reads as 32 |

`cmd = 0` returns a START/END pair with `count = 0`, giving the app the current
generation and extent (`status = empty` if there are no records). `cmd = 2`
cancels an in-flight transfer and is allowed while busy.

## 5.8 `0006 sync_data` — Notify, encrypted

A framed byte stream. The app concatenates payload bytes and parses the logical
stream in [04 §4.5](04-data-and-storage.md).

Frame header, 4 B:

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `frame_seq` u8, wraps |
| 2 | 1 | `flags`: b0 START, b1 END, b2 ERROR |
| 3 | 1 | `len` u8 |

`len` is at most **240** and at most `MTU − 3 − 4`. At the default MTU 23 that
is 16 B, so a 20 B START header spans two frames. The app must reassemble by
`len` and flags, and must verify `frame_seq` is contiguous within one response.
A missing frame discards the partial batch and re-requests it; the app never
stores a stream with a hole. It must not assume one notification per record.

No ACK is required: the next `sync_ctrl` is the acknowledgement.

## 5.9 `0007 config` — Read/Write, authenticated

Fixed 80 B.

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `units`: 0 °C, 1 °F (OLED display; stored samples are always °F) |
| 2 | 2 | `display_timeout_s` u16; 0 = never |
| 4 | 16 | `device_name` UTF-8, NUL-padded (≤15 chars) |
| 20 | 2 | `billows_target_f10` i16; 0 = none |
| 22 | 1 | `billows_mode`: 0 observe, 1 control, 2 disabled |
| 23 | 57 | reserved (probe names/roles were removed from the MVP) |

Read returns current values. Write replaces the whole struct and validates:

- `device_name` is valid UTF-8, NUL-terminated within its field;
- display timeout is one of 30/60/120/0;
- target is 32–572 °F when in control mode;
- `billows_mode = control` is refused if `caps.billows_control = 0`.

Probe identity is jack order and colour in the app (`P1`–`P4`); there are no
probe names or roles in the MVP. P4 is the fixed Billows/pit channel on the
Smoke X4. The 80-byte characteristic is kept for now with the former
name/role bytes reserved, so the packet size does not churn before M0.

A partial write is not supported; read-modify-write is the app's job.

## 5.10 `0008 stats` — Read, encrypted

Fixed 60 B.

| Offset | Size | Field |
|---|---:|---|
| 0 | 1 | `ver = 1` |
| 1 | 1 | `flags` |
| 2 | 4 | `uptime_s` |
| 6 | 4 | `records_stored` |
| 10 | 4 | `records_capacity` |
| 14 | 4 | `min_seq` (`0xFFFFFFFF` if empty) |
| 18 | 4 | `max_seq` (`0xFFFFFFFF` if empty) |
| 22 | 4 | `generation` |
| 26 | 4 | `packets_ok` |
| 30 | 4 | `packets_bad` |
| 34 | 2 | `battery_mv` |
| 36 | 1 | `battery_pct` (255 unknown) |
| 37 | 1 | `lora_rssi` i8 |
| 38 | 1 | `lora_snr` i8 |
| 39 | 1 | reserved |
| 40 | 4 | `heap_free` |
| 44 | 4 | `heap_min` |
| 48 | 2 | `dropped_samples` u16 (sample queue/log drops since boot) |
| 50 | 2 | reserved |
| 52 | 4 | `oldest_unix_s` (0 if unknown) |
| 56 | 4 | `newest_unix_s` (0 if unknown) |

### `stats.flags`

| Bit | Meaning |
|---|---|
| 0 | `smoke_paired` |
| 1 | `smoke_live` |
| 2 | `advertising` |
| 3 | `connected` |
| 4 | `clock_valid` |
| 5 | `storage_ok` |
| 6 | `billows_attached` |
| 7 | `billows_control` |

## 5.11 Security

- **Pairing:** LE Secure Connections with Passkey Entry. The bridge has
  `DisplayOnly` IO capability and generates a six-digit code when bonding
  starts. The app/user enters it in the OS dialog.
- **Bonding:** persisted in NimBLE's NVS store. Up to **4** phones, one active
  connection at a time. This is not multi-user support; extra bonds are for
  phone replacement/handoff. No eviction. `info.bonds_free` tells the app how
  many slots remain before it attempts a bond; if zero, the app explains that an
  existing phone must forget the bridge.
- **Characteristics:** `info` open; `live`, `stats`, `sync_ctrl`, `sync_data`
  encrypted; `control`, `config` encrypted + authenticated.
- **Factory reset** clears config, history, and bonds.
- **Forget this phone** removes only the current phone's bond and disconnects.
  Other bonded phones remain. Factory reset clears every bond.
- **No Just Works fallback.** If the phone cannot do passkey entry, the app
  says so; it does not silently downgrade.

### Lost-phone recovery

If every bonded phone is lost, the only recovery is a USB erase/reflash
(`idf.py erase-flash`) because the MVP deliberately has no on-device factory
reset. This is a bench-product limitation, documented in the app's About page.
A future hardware revision may add a hidden recovery gesture; it is not in this
MVP.

## 5.12 Procedures

### First connect

```
app: scan(filter service UUID)
app: connect(device)
app: read info (open)            -> id, fw, caps, proto
app: request MTU 247
app: read live                   -> ATT Insufficient Encryption (0x0F) or
                                    Insufficient Authentication (0x05)
app: bond()                      -> OS passkey dialog
bridge: show 6 digits on OLED
user: enter digits
app: link secured
app: read config, stats, live
app: subscribe live, result, sync_data
app: control(set_time)           -> result ok
app: sync (recent first)
```

The app must show the "read the code on the bridge" instruction **before**
triggering the OS bond prompt. The bridge displays the code when bonding starts,
not while merely advertising.

### Reconnect

```
app: scan/filter; prefer remembered device id
app: connect; link encrypts with stored bond
app: request MTU; subscribe; read live/stats
app: control(set_time) if clock differs > 2 s
app: sync forward from local max seq
```

No passkey prompt on a valid bond.

### Control op

The app writes `control`, waits for a `result` with the same `op_id` (3 s
timeout), and maps the status to UI. It does not assume `ok` because the write
returned.

### Sync

The app writes `sync_ctrl`, waits for START/END frames, stores the batch in one
transaction, then sends the next request. It stops on `count = 0`, `status =
gap` (record the gap and reset the cursor), `generation` change (new segment),
or an app-level cancel.

### Re-pair the Smoke X4

The Settings → Connection row shows the Smoke X4 as paired/unpaired and offers
**Re-pair**. It writes `unpair_smoke_x`, then shows the SYNC instructions. This
is the only way to follow a Smoke X4 that was re-synced to a new channel; a
factory reset is not required and the log is preserved.

### Forget / factory reset / power off

All three are authenticated. The app confirms with the exact consequence:

- Forget: "This removes the Bluetooth bond for this phone on the bridge and this
  phone. Other bonded phones are unaffected. The bridge keeps recording, and
  this phone keeps its saved history until you delete it."
- Factory reset: "This erases the bridge's pairing, settings, and recorded
  history, and removes every phone bond. This cannot be undone. This phone keeps
  its saved history until you delete it."
- Power off: "The bridge stops recording and advertising. Hold PRG for 1.5 s to
  turn it back on."

The app treats a disconnect after the request as the expected success signal for
factory reset and power off, but only after a `result ok` or a deliberate
timeout with the link gone.

## 5.13 Versioning and errors

- `info.proto_major` must be `1`; an app seeing another major shows "Update the
  app or firmware" and does not write.
- New characteristics are additive; unknown slots are ignored.
- New payload trailing bytes are ignored.
- A control op the firmware does not know returns `unsupported`.
- A write larger than the characteristic's maximum is `invalid`, not truncated.
- The app never writes `config` or `control` before `SECURED`.

## 5.14 Test vectors

Host tests must include at least:

- `info` with all caps and with `billows_control = 0`;
- `live` four attached, one detached, all detached, clock invalid, Billows
  attached;
- `config` min/max device name, timeout, units, control mode refusal;
- `stats` at empty log and full ring;
- `control` each op, malformed bodies, wrong length, unknown op;
- `result` status/detail truncation;
- sync START/RECORDS/END at MTU 23 and MTU 247, including a record split across
  frames;
- a backward sync batch and a forward sync batch;
- a generation change and a gap.
