# 02 — Smoke X LoRa Protocol

Everything the bridge needs to know about the air interface. All of it is derived from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT) — chiefly
`main/smoke_x_parser.{c,h}`, `main/smoke_x.c`, `main/app_lora.{c,h}` — plus its captured-packet
test vectors in `test/test_smoke_x_parser.c`.

Confidence is marked throughout:
**[K]** known from working code + captured packets · **[I]** inferred, consistent with the code but
unproven · **[?]** unknown.

## 2.1 Physical layer

The Smoke X uses plain LoRa (not LoRaWAN) with an ASCII CSV payload — no binary framing, no
encryption, no authentication.

| Parameter | Value | Conf. |
| --- | --- | --- |
| Modulation | LoRa | [K] |
| Region | 902–928 MHz ISM (US/Canada only) | [K] |
| Spreading factor | 9 | [K] |
| Bandwidth | 125 kHz | [K] |
| Coding rate | 4/5 | [K] |
| Preamble | 10 symbols | [K] |
| Sync word | `0x12` | [K] |
| CRC | enabled | [K] |
| Payload | ASCII, comma-separated, trailing comma, **no** terminator | [K] |
| Max observed length | ~120 bytes (X4 state message) | [I] |
| Header | explicit | [K] |

Because the payload is ASCII CSV and unauthenticated, **anyone within ~1 mile with an SX1262 can
read your probe temperatures, and could in principle forge packets.** This is a property of the
product, not of our bridge. It is worth stating plainly in user-facing docs. Our bridge never
forwards raw LoRa frames onward and never transmits anything except the pairing ACK.

### Frequency plan

| Purpose | Frequency | Conf. |
| --- | --- | --- |
| **X4** pairing/sync channel | 915.000 MHz | [K] |
| **X2** pairing/sync channel | 920.000 MHz | [K] |
| Operating channel | assigned by the base station during pairing; observed 910.5 MHz | [K] |
| Valid operating range enforced by firmware | 902–928 MHz | [K] |

The operating frequency is **per base station** and is communicated in the sync message. It is not
predictable, so the bridge must persist it.

## 2.2 Message types

Discriminated purely by **comma count**. Crude, but the counts are disjoint and it costs one pass
over the buffer.

| Message | Commas | Direction | Fields |
| --- | --- | --- | --- |
| Sync (pairing beacon) | **6** | base → all | 6 |
| Sync ACK | **2** | **bridge → base** (only transmission we ever make) | 2 |
| State, X2 | **16** | base → all | 4 header + 2×5 probe + 2 trailing |
| State, X4 | **26** | base → all | 4 header + 4×5 probe + 2 trailing |

No ambiguity: the smallest state message has 16 commas, well clear of the 6-comma sync.

### 2.2.1 Sync message (base → all)

Broadcast every ~3 s on the model's sync channel while the base station is held in sync/pairing
mode.

```
<unknown>,<device_id>,<freq_b0>,<freq_b1>,<freq_b2>,<freq_b3>,
```

Captured example:

```
020001,|abCDe,160,32,69,54,
```

| Field | Example | Meaning | Conf. |
| --- | --- | --- | --- |
| 0 | `020001` | **Unknown.** Constant across the one captured sample. Plausibly a model/protocol/firmware code | [?] |
| 1 | `|abCDe` | **Device ID.** 6 chars including a leading `|`. Buffer is 8 bytes incl. NUL, so ≤ 7 chars | [K] |
| 2–5 | `160,32,69,54` | **Operating frequency**, decimal-encoded bytes of a **little-endian uint32**, in Hz | [K] |

Frequency decode: `160 | (32<<8) | (69<<16) | (54<<24)` = `910,500,000` Hz = 910.5 MHz.

### 2.2.2 Sync ACK (bridge → base)

```
<device_id>,SUCCESS,
```

Sent **once**, on the newly learned operating frequency, immediately after decoding a sync message.
The base station sees it, stops beaconing, and returns to normal operation.

```
|abCDe,SUCCESS,
```

**This is the only LoRa transmission the bridge ever makes.** The firmware enforces it (§2.5).

### 2.2.3 State message (base → all)

Broadcast every **30 s** on the operating frequency, unconditionally, to every paired receiver.

```
<device_id>,<unknown>,<units>,<new_alarm>,
  <p1_state>,<p1_temp_x10>,<p1_alarm>,<p1_max>,<p1_min>,
  <p2_state>,<p2_temp_x10>,<p2_alarm>,<p2_max>,<p2_min>,
  [<p3_...>,  <p4_...>,   for X4]
  <billows_attached>,<unknown>,
```

Captured X2 example:

```
|abCDe,30,1,1,0,848,1,125,32,0,849,0,260,195,0,0,
```

#### Header fields

| Idx | Name | Example | Meaning | Conf. |
| --- | --- | --- | --- | --- |
| 0 | `device_id` | `|abCDe` | Matches the sync message. **The reference ignores it** — see §2.6 | [K] |
| 1 | *unknown* | `30` | **Unknown.** Value `30` in every captured packet. Strong hypothesis: **the transmit interval in seconds**, which matches the observed 30 s cadence. Could also be a sequence/battery/protocol field. Worth capturing from a base station with a changed setting | [I] |
| 2 | `units` | `1` | `1` → °F, anything else → °C | [K] |
| 3 | `new_alarm` | `1` | Non-zero → an alarm has newly triggered. Distinct from the per-probe `alarm` (which means *alarm enabled*) | [I] |

#### Per-probe fields (5 each, repeated `num_probes` times)

| Offset | Name | Meaning | Conf. |
| --- | --- | --- | --- |
| +0 | `state` | `3` → **detached**. Any other value → attached. `0` is the normal attached value. Other values (open circuit? shorted? out of range?) are unmapped | [K] / [?] |
| +1 | `temp_x10` | Temperature × 10 in the message's units. `848` → 84.8 °F. Signed (probe range is −58…572 °F) | [K] |
| +2 | `alarm` | Non-zero → **alarm is enabled** for this probe | [I] |
| +3 | `max` | High alarm setpoint, whole degrees. **On the Billows channel this field is reinterpreted as the Billows target temperature** | [K] |
| +4 | `min` | Low alarm setpoint, whole degrees | [K] |

The Billows overloading is explicit in the reference's type — `max_temp` and `billows_target` are a
`union` in `smoke_x_types.h`, and the published MQTT payload emits `probe_1_max` alongside
`billows_target`. Probe 1 is the pit/Billows channel on Smoke X hardware. **[I]**

#### Trailing fields

| Idx | Name | Meaning | Conf. |
| --- | --- | --- | --- |
| −2 | `billows_attached` | Non-zero → a Billows fan controller is connected to the base | [K] |
| −1 | *unknown* | `0` in all captures | [?] |

#### Detached-probe values

When a probe reads detached (`state == 3`), the other four fields are zeros in the captured
sample (`3,0,0,0,0`). **Never plot `0.0 °F` for a detached probe** — the reference does exactly
this, and a detached probe draws a line straight to zero on the graph. Our sample encoding uses a
dedicated sentinel (see [04 §4.2](04-storage-and-history.md)).

## 2.3 Test vectors

Carried over from the reference's host test suite; these become the seed corpus for ours.

| Case | Payload |
| --- | --- |
| X2, real capture, °F, alarm active | `\|abCDe,30,1,1,0,848,1,125,32,0,849,0,260,195,0,0,` |
| Celsius | `\|abCDe,30,0,0,0,250,0,125,32,0,251,0,260,195,0,0,` |
| Probe 2 detached | `\|abCDe,30,1,0,0,848,0,125,32,3,0,0,0,0,0,0,` |
| Billows attached | `\|abCDe,30,1,0,0,848,0,125,32,0,849,0,260,195,1,0,` |
| X4 (synthetic) | `\|abcde,30,1,0,0,700,0,200,100,0,710,0,200,100,0,720,0,200,100,0,730,0,200,100,0,0,` |
| Sync | `020001,\|abCDe,160,32,69,54,` |
| Sync ACK | `\|abCDe,SUCCESS,` |

> **Gap: no real X4 capture exists yet.** Every X4 vector above is synthetic, extrapolated from the
> X2 format. **An X4 is in hand**, so closing this is a first-week task rather than a blocker:
> capture and commit real traffic covering four attached probes, probes unplugged mid-cook, an alarm
> firing, and a °C switch. That settles Q1, Q4, Q6, and Q8 below.
>
> **Billows-dependent captures stay open.** No Billows unit is available, so Q3 and Q5 — what the
> trailing field carries and whether `billows_target` really overloads probe 1's `max` — cannot be
> resolved. Per [D11](00-overview.md), the fields are decoded and stored regardless, so a future
> capture reinterprets existing data rather than requiring a re-cook. See
> [10 §10.4](10-repo-tooling-and-testing.md) for the capture tooling.

## 2.4 Pairing state machine

```
                    ┌──────────────────────────────────────────────────┐
                    │                                                  │
       power on     ▼                                                  │
   ┌───────────────────────────────┐                                   │
   │ read NVS: smoke_x/config      │                                   │
   │  {frequency, device_id, n}    │                                   │
   └──────────┬────────────────────┘                                   │
              │                                                        │
     valid?   ├── yes ──► ┌────────────────────────┐                   │
              │           │ PAIRED                 │                   │
              │           │ tune to config.freq    │◄──────────┐       │
              │           │ RX continuously        │           │       │
              │           └──────────┬─────────────┘           │       │
              │                      │ state msg (16 or 26 commas)     │
              │                      ▼                         │       │
              │           ┌────────────────────────┐           │       │
              │           │ decode → sample bus    │───────────┘       │
              │           └────────────────────────┘                   │
              │                                                        │
              └── no ───► ┌──────────────────────────────────────┐     │
                          │ UNPAIRED                             │     │
                          │ alternate 915 ↔ 920 MHz every 3.3 s  │     │
                          │ RX only, never TX                    │     │
                          └──────────┬───────────────────────────┘     │
                                     │ sync msg (6 commas)             │
                                     ▼                                 │
                          ┌──────────────────────────────────────┐     │
                          │ SYNC_RECEIVED                        │     │
                          │  • parse device_id + frequency       │     │
                          │  • validate 902–928 MHz              │     │
                          │  • retune to the operating freq      │     │
                          │  • TX "<id>,SUCCESS,"  ← only TX     │     │
                          └──────────┬───────────────────────────┘     │
                                     │ first state msg arrives         │
                                     ▼                                 │
                          ┌──────────────────────────────────────┐     │
                          │ CONFIRMED                            │     │
                          │  • num_probes = 2 (16) or 4 (26)     │     │
                          │  • persist config to NVS ────────────┼─────┘
                          └──────────────────────────────────────┘
```

Key points:

- **Probe count is learned from the first state message, not from the sync message.** The bridge
  does not know whether it paired with an X2 or an X4 until data arrives.
- The frequency scan alternates every **3.3 s** while the base beacons every **3 s** — deliberately
  offset so the two don't lock into a beat pattern that starves one channel.
- Once `sync_received` is set, further sync messages are ignored until an explicit unpair.
- Unpair clears `device_id` and `frequency` in NVS and restarts the scan. **It does not affect the
  pairing state of any other receiver**, including ThermoWorks' own.
- Recovery: if the bridge is paired but has heard nothing for a long time (base off, out of range,
  or the base was re-synced to a new channel), it stays on the stored frequency. Our firmware adds
  a **stale-pairing watchdog** the reference lacks — see §2.7.

## 2.5 Invariants

These are load-bearing. Violating any of them can disrupt a real cook.

1. **The bridge transmits exactly one packet per pairing: the sync ACK.** No polling, no keepalive,
   no beacon. Enforced by a `radio_tx_allowed` flag that is only true inside the sync handler, and
   by a unit test asserting no other call path reaches `app_lora_start_tx`.
2. **Pairing the bridge must not unpair anything else.** The base station supports multiple
   receivers; the ACK simply ends its sync broadcast. Verified by keeping the stock receiver paired
   and running through a full bridge pair/unpair cycle.
3. **Never transmit on the sync channel after pairing.** The ACK goes out on the *operating*
   frequency, after retuning.
4. **Reject out-of-band frequencies.** A corrupted sync message could decode to any uint32. Range
   check 902–928 MHz *before* retuning — transmitting outside the ISM band is illegal.
5. **The debug TX endpoint (`POST /api/v1/radio/tx`) is compile-time gated** behind
   `CONFIG_SMOKEBRIDGE_RADIO_DEBUG`, off in release builds. The reference exposes an unguarded
   arbitrary-transmit command over unauthenticated HTTP; we do not ship that.

## 2.6 Deviations from the reference

Deliberate changes, with reasons:

| Reference behaviour | Ours | Why |
| --- | --- | --- |
| `device_id` in state messages is parsed and discarded | **Compared against the paired ID; mismatches are counted and dropped** | With two Smoke X units in range on the same channel you would otherwise silently interleave two cooks into one graph |
| Detached probe stored as `temp = 0.0` | Stored as a dedicated `DETACHED` sentinel | A 0 °F sample is indistinguishable from a real reading and ruins the chart |
| No timestamps | Every sample carries seconds-since-session-start | A reception gap must show as a gap, not as compressed time |
| History in a RAM `cJSON` array, capped at 1200 | Append-only binary log on flash | Survives reboot; no practical cap |
| Unit change detected by `const char*` pointer equality | Explicit enum in the parsed struct | Pointer-identity comparison is a subtle trap for anyone refactoring the parser |
| `strtok` on a heap copy | `strtok_r` on a stack buffer | `strtok` is not reentrant; the parser is called from one task today but that is an accident, not a guarantee. Max payload is ~120 B, so no allocation is needed at all |
| RSSI/SNR only logged | Recorded per sample and exposed via the API | Link quality is genuinely useful — it tells the user when the bridge is about to lose the base station |

The parser's shape — pure C, no ESP-IDF headers, host-testable — is exactly right and we keep it.
`smoke_x_parser.c` ports over with its MIT notice intact.

## 2.7 Additions

**Stale-pairing watchdog.** If paired but no valid state message has been received for
`N × 30 s` (default N = 20, i.e. 10 min), raise a `BASE_LOST` event → OLED banner, LED pattern, and
a push to the app. After 60 min with no packets *and* no active cook, optionally drop to alternate
scanning again so a re-synced base can be re-acquired without a user visit. Config-gated, default
off (silently re-pairing to a different base would be worse than staying put).

**Link quality.** `GetPacketStatus()` already yields RSSI and SNR per packet in the SX1262 driver.
Record both with each sample (`int8` each). Expose a rolling average in the status API and on the
OLED radio page. Useful for antenna placement and for warning before the link drops.

**Packet accounting.** Counters for: valid state messages, CRC failures, unknown comma counts,
device-ID mismatches, and inter-packet interval histogram. Exposed at `/api/v1/status`. Cheap, and
turns "it seems flaky" into a number.

### The novelty log

With a single board there is no dedicated capture rig — the bridge under test *is* the bridge
collecting evidence, and re-flashing it into a capture build costs a cook. So capture has to be a
permanent, zero-effort background behaviour rather than a deliberate session.

Logging every raw packet would cost ~345 KB per 24 h (120 B × 2,880), 7.7× the sample data. Instead,
the firmware keeps a **seen-set of the values every normally-constant field has ever taken**, and
persists a packet only when something is new:

| Reason | Fires when |
| --- | --- |
| `first` | The first packet of each comma-count class |
| `field1` | State header field 1 takes an unseen value → **answers Q1** |
| `trailing` | The final field takes an unseen value → **answers Q3** |
| `probe_state` | A probe `state` field is neither `0` nor `3` → **answers Q4** |
| `alarm_edge` | `new_alarm` transitions, with the two packets either side → **answers Q8** |
| `billows` | `billows_attached` flips, or `billows_target` moves → **Q5, whenever a unit appears** |
| `units` | The units field changes |
| `sync` | Any sync message, always → **Q2, Q6** |
| `unparsed` | Unknown comma count or a parse failure |
| `id_mismatch` | A state message from a device ID we are not paired with |

Written as plain text so it can be pulled off and read directly:

```
uptime_s  rssi  snr  reason      payload
   43230   -71    9  field1      |abCDe,45,1,0,0,2431,1,2500,2000,…
   51002   -73    8  probe_state |abCDe,30,1,0,1,0,0,0,0,…
```

Capped at 64 KB / 512 entries as a ring — 2.6 % of the `cooks` partition — with the **first**
instance of each distinct `reason`+value pair pinned so it is never evicted by later churn. Served
at `GET /api/v1/debug/novelty` as `text/plain`.

The effect is that eight open questions get answered by cooking dinner. No capture session to
remember, no build to reflash, no cook spent on instrumentation instead of brisket. A per-session
`capture_raw` flag still exists for deliberate full-fidelity runs (retaining the last two), but the
novelty log is what actually closes the protocol gaps.

## 2.8 Open questions

| # | Question | How to resolve | Status |
| --- | --- | --- | --- |
| Q1 | What is state header field 1 (`30`)? Transmit interval? | Capture across base-station settings changes; check whether it ever differs from 30 | **actionable** — X4 in hand |
| Q2 | What is sync field 0 (`020001`)? | Capture sync from both an X2 and an X4; compare | partial — X4 only unless an X2 is borrowed |
| Q3 | What is the trailing state field? | Capture with Billows attached and running, alarms firing, low base battery | **blocked** — no Billows |
| Q4 | What probe `state` values exist besides `0` and `3`? | Short the probe jack, open it, exceed range, unplug mid-read | **actionable** |
| Q5 | Is `billows_target` really the Billows channel's `max` field? Which channel? | Attach a Billows, set a target, diff the packet | **blocked** — no Billows |
| Q6 | Does an X4 emit the same `30` and `020001` values? | First real X4 capture | **actionable** |
| Q7 | Does the base ever change operating frequency without a re-sync? | Long soak with the stale-pairing watchdog logging | actionable, slow |
| Q8 | Is `new_alarm` edge-triggered (one packet) or level? | Trigger an alarm and count how many packets carry it | **actionable** |

Each becomes a test vector once answered. Until then the parser treats unknown fields as opaque and
**preserves the raw payload** for the most recent N packets in a debug ring buffer, retrievable via
`GET /api/v1/debug/packets` — so field investigation does not require a second SDR.
</content>
