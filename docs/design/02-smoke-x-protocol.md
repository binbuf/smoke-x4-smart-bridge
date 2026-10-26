# 02 — Smoke X LoRa Protocol

This is the air contract the bridge depends on. It is derived from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT © 2022
G-Two), the legacy captures in
[`legacy/protocol/fixtures/lora/`](../../legacy/protocol/fixtures/lora), and the
legacy parser work. Confidence is marked:

- **[K]** known from working code plus captured packets.
- **[I]** inferred, consistent with captures but not proven.
- **[?]** unknown; preserve, do not invent semantics.

The bridge **never transmits except for the pairing acknowledgement**. Billows
is receive-only in the MVP; post-MVP Billows RF work is also a passive survey and
is not part of this contract.

## 2.1 Physical layer

| Parameter | Value | Confidence |
|---|---|---|
| Modulation | LoRa, plain (not LoRaWAN) | [K] |
| Band | 902–928 MHz ISM (US/Canada) | [K] |
| Spreading factor | 9 | [K] |
| Bandwidth | 125 kHz (SX126x driver index 4) | [K] |
| Coding rate | 4/5 | [K] |
| Preamble | 10 symbols | [K] |
| Sync word | `0x12` | [K] |
| CRC | on | [K] |
| Payload | ASCII CSV, trailing comma, no terminator | [K] |
| Max observed length | ~120 bytes | [I] |

The payload is unencrypted and unauthenticated. Anyone within range with an
SX1262 can read probe temperatures and could forge packets. That is a property
of the Smoke X, not of the bridge. The app never forwards raw frames anywhere.

### Frequencies

| Purpose | Frequency | Confidence |
|---|---|---|
| Smoke X4 sync channel | 915.000 MHz | [K] |
| Smoke X2 sync channel | 920.000 MHz | [K] |
| Operating channel | assigned by the Smoke X4 during pairing; observed 910.5 MHz and 918.5 MHz | [K] |

The operating frequency is per unit. The bridge persists it after pairing. The
valid range is enforced as 902–928 MHz before any retune or transmit.

## 2.2 Message discrimination

Message type is determined by comma count. The classes are disjoint.

| Message | Commas | Direction | Fields |
|---|---|---|---|
| Sync beacon | 6 | Smoke X4 → all | 6 |
| Sync ACK | 2 | **bridge → Smoke X4** | 2 |
| State, X2 | 16 | Smoke X4 → all | 4 header + 2×5 probe + 2 trailing |
| State, X4 | 26 | Smoke X4 → all | 4 header + 4×5 probe + 2 trailing |

The MVP targets X4. The parser may accept the X2 shape defensively, but no X2
UI or acceptance work is in scope.

## 2.3 Sync beacon (6 commas)

Broadcast every ~3 s while the Smoke X4 is held in sync/pairing mode.

```
<field0>,<device_id>,<freq_b0>,<freq_b1>,<freq_b2>,<freq_b3>,
```

Captured X4 example:

```
000000,LMXC[,160,50,191,54,
```

| Field | Example | Meaning | Confidence |
|---|---|---|---|
| 0 | `000000` | Unknown model/protocol code; X4 sent `000000`, X2-era docs `020001` | [I] |
| 1 | `LMXC[` | Device ID, up to 7 chars | [K] |
| 2–5 | `160,50,191,54` | Operating frequency as decimal bytes of a little-endian `uint32` in Hz | [K] |

Frequency decode:

```
160 | (50 << 8) | (191 << 16) | (54 << 24) = 918,500,000 Hz
```

The example above is an **operating** channel learned from a sync beacon. The
X4's sync channel itself is 915.0 MHz; the operating channel is normally
different and is persisted after pairing.

## 2.4 Sync ACK (2 commas)

```
<device_id>,SUCCESS,
```

Sent once, on the **operating frequency**, after decoding and validating a sync
beacon. The Smoke X4 stops beaconing and returns to normal operation.

This is the only LoRa packet the bridge ever transmits. There is no Billows
target-set frame in the MVP; see [08](08-billows.md).

## 2.5 State message (26 commas, X4)

Broadcast every ~30 s on the operating frequency.

```
<device_id>,<field1>,<units>,<field3>,
  <p1_state>,<p1_temp_x10>,<p1_alarm>,<p1_max>,<p1_min>,
  <p2_state>,<p2_temp_x10>,<p2_alarm>,<p2_max>,<p2_min>,
  <p3_state>,<p3_temp_x10>,<p3_alarm>,<p3_max>,<p3_min>,
  <p4_state>,<p4_temp_x10>,<p4_alarm>,<p4_max>,<p4_min>,
  <billows_attached>,<new_alarm>,
```

Captured X4 baseline:

```
LMXC[,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,32,0,0,
```

### Header

| Index | Name | Example | Meaning | Confidence |
|---|---|---|---|---|
| 0 | `device_id` | `LMXC[` | Must match the paired ID; foreign IDs are dropped and counted | [K] |
| 1 | `field1` | `30` | Unknown; never left `30` in captures. Likely transmit interval seconds. | [I] |
| 2 | `units` | `1` | `1` = °F, anything else = °C | [K] |
| 3 | `field3` | `1` | Unknown; rests at `1`, moved to `2` around alarm/menu activity | [?] |

Field 1 and field 3 are preserved in diagnostics but are not used for behavior.
Do not reinterpret them without a capture.

### Per-probe group (5 fields × 4)

| Offset | Name | Meaning | Confidence |
|---|---|---|---|
| +0 | `state` | `3` = detached; any other value = attached. Other values are unmapped. | [K]/[?] |
| +1 | `temp_x10` | Temperature × 10 in the message's active unit; signed | [K] |
| +2 | `alarm` | Non-zero = alarm enabled on the Smoke X4; not "ringing" | [I] |
| +3 | `max` | High alarm setpoint, whole degrees; in fan mode it may carry the target **or** target+25 °F — unvalidated | [K]/[?] |
| +4 | `min` | Low alarm setpoint, whole degrees | [K] |

Detached behavior:

- X4 sets `state == 3` and **freezes** the last temperature; it does not zero it.
- X2-era captures zeroed the fields.
- The bridge maps `state == 3` to `TEMP_DETACHED = INT16_MIN`, never to a
  numeric temperature. This is a hard invariant.

### Trailing fields

| Index | Name | Meaning | Confidence |
|---|---|---|---|
| −2 | `billows_attached` | Non-zero = Billows fan controller connected to the Smoke X4 | [K] |
| −1 | `new_alarm` | Non-zero = an alarm newly triggered on this packet; edge-triggered | [K] |

The trailing `new_alarm` field is the real alarm edge. Header field 3 is not
`new_alarm` on a real X4; the upstream reference was wrong about that. The MVP
does not implement alarms, but the parser preserves the bit.

### Units and canonical storage

The Smoke X4 can be flipped between °F and °C. Storing "whatever the unit was"
would put a false 20-degree cliff in a single series. The bridge stores
**tenths of °F**:

```
F10 = (C10 × 9) / 5 + 320
```

`C10` is finer than `F10`, so the conversion does not lose resolution. The
record carries a `source_celsius` flag for provenance only.

## 2.6 Billows fields

The fan is attached to the Smoke X4's **channel 4** on an X4 (channel 2 on an
X2). What is known and what is not:

- `billows_attached` is the trailing `−2` field. **[K]**
- The fan's actual on/off duty is **not** in the state broadcast. There is no
  observed fan-speed field. **[K]**
- The setpoint representation is **unsettled**. The candidate is probe 4's
  `max` field, but the Smoke X4's fan mode also sets high/low alarms at ±25 °F
  around the target. If `max` is the high alarm, it is `target + 25`, not the
  target. If `max` is the target, the ±25 alarms are not represented in the
  packet. **[?]**

B5.0 must passively capture `max` and `min` at 225, 250, and 275 °F and derive
the relation before the app displays a target. A single known setpoint separates
`max = target` from `max = target + 25`; a second setpoint confirms the mapping.
Do not change a setpoint during a live cook just to capture — use the M5 bench
sitting. The air probe can be at room temperature; no cook is required.

The attached flag is sufficient to display "Billows detected". The target is
shown only after B5.0 validates it; otherwise the UI shows `—`. There is no
control path: ThermoWorks documents that a Smoke X4 receiver cannot change set
points or the Billows, so the listener cannot either. See [08 — Billows](08-billows.md)
and [`../billows-decision.md`](../billows-decision.md).

Do not display a "fan running" state from RF data. The Smoke X4's fan output is
not observable and the bridge has no fan output in the MVP.

## 2.7 Pairing state machine

```
                 power on
                    │
                    ▼
          ┌───────────────────┐
          │ read pairing from │
          │ NVS               │
          └─────┬─────────────┘
                │
       valid?   ├── yes ──► PAIRED: tune to stored frequency, RX
                │
                └── no ───► UNPAIRED: alternate 915 ↔ 920 MHz every 3.3 s
                                      │
                                      │ sync beacon (6 commas)
                                      ▼
                             SYNC_RECEIVED
                             • parse device_id + frequency
                             • validate 902–928 MHz
                             • retune to operating frequency
                             • TX "<id>,SUCCESS," once
                                      │
                                      │ first state message
                                      ▼
                             CONFIRMED
                             • learn probe count from comma count
                             • persist {device_id, frequency, probes}
                                      │
                                      ▼
                                   PAIRED
```

Rules:

1. Once a sync is accepted, ignore further sync beacons until an explicit
   unpair/re-pair.
2. Probe count is learned from the first state message, not the sync beacon.
3. The ACK goes out on the operating frequency, never the sync channel.
4. If the paired Smoke X4 is silent for 10 minutes, mark the link lost and show
   it; do **not** automatically scan for a different unit or clear pairing.
5. Unpairing clears the stored pairing and restarts the scan. It does not affect
   the stock receiver or any other paired device. The app exposes this as
   `unpair_smoke_x` (Settings → Connection → Re-pair); the log is preserved.
6. If the Smoke X4 is re-synced to a new channel, the bridge will not hear it
   until the user re-pairs. This is a deliberate choice: silently following a
   different unit is worse than a visible "Smoke X4 lost" state. The Re-pair
   action is the recovery path.

## 2.8 Timing, gaps, and packet accounting

- Nominal cadence: 30 s.
- Observed wobble: 29–76 s during menu use; occasional real dropouts.
- The bridge timestamps each sample with its own UTC seconds (or an estimated
  time if the clock is not set); gaps are visible as `t` deltas, not compressed
  time.
- The app treats a delta > 90 s as a History gap; the observed cadence can wobble
  to ~76 s during menu use, so 60 s would draw false gaps.
- Counters to keep: valid state packets, CRC/parse failures, foreign device IDs,
  sync beacons seen, ACK attempts, last packet age, RSSI/SNR. These are cheap and
  answer "is the radio healthy?" without a packet capture.

## 2.9 Validation corpus

The host test suite must include:

- X4 real baseline,
- X4 alarm edge (`new_alarm`),
- X4 detached probe (frozen temp),
- X4 Celsius,
- X4 real sync,
- X2-era vectors as defensive parser tests (not product acceptance),
- malformed comma counts, bad numeric fields, out-of-range frequency,
- a Billows-attached vector once a unit is available (captured during the M5
  work; the target relation needs a known setpoint and confirmation at a second
  target).

Store captures under `protocol/fixtures/lora/` in the new tree and commit the
raw log plus a short report (time, radio settings, what changed). Do not edit
the legacy fixtures.

## 2.10 Open protocol questions

| # | Question | How it closes | Impact |
|---|---|---|---|
| Q1 | What is state header field 1? | Capture across settings/menu changes | None for MVP; diagnostics only |
| Q2 | What is state header field 3? | Capture around alarm/menu activity | None for MVP; diagnostics only |
| Q3 | Do other probe `state` values exist (shorted/open)? | Bench fault injection | Display would need an "invalid" state |
| Q4 | Is Billows target probe 4 `max`, `max − 25`, or another relation? | Passive capture with a Billows attached while changing the base target | Billows target display |
| Q5 | Is there any receiver→base command traffic? | Public docs say the receiver has no setpoint controls; a passive capture is post-MVP confirmation only | None for MVP; no control path |
| Q6 | Does the X4 change operating frequency without re-sync? | Long soak | Pairing recovery behavior |
