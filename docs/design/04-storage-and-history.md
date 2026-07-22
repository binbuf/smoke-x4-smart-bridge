# 04 — Storage and Cook History

## 4.1 The short answer

> **Q: What storage does the board have, and can it hold a 24-hour cook?**
>
> **A: 8 MB of on-board flash and no SD card slot — and yes, comfortably. Roughly 54 days of
> continuous logging, or ~50 complete 24-hour cooks, at full 30-second resolution.**

The arithmetic, because it is the whole reason this is easy:

| | |
| --- | --- |
| Base station transmit interval | 30 s |
| Samples per hour | 120 |
| **Samples in 24 h** | **2,880** |
| Bytes per sample (fixed, all 4 probes + flags + link quality + CRC) | **16 B** |
| **Bytes for a 24 h cook** | **46,080 B ≈ 45 KB** |
| Bytes for a 15 h cook | ~28 KB |
| `cooks` partition | **2,432 KB** |
| Samples it holds | ~155,600 |
| **Continuous logging time** | **~1,297 h ≈ 54 days** |
| Realistic after ~10 % LittleFS overhead + 256 B/session headers | **~48 days, or ~48 full 24 h cooks** |

A 24-hour cook is 1.8 % of the partition. The constraint was never storage capacity — the
reference project's 10-hour ceiling came from holding history in **RAM** as a `cJSON` document
(`MAX_RECORDS 1200`) and serializing it through a 16 KB static buffer. Moving to fixed-width binary
records on flash removes the ceiling and makes the data survive power loss, which matters more.

There is also 16 KB of RTC SRAM and a 24 KB NVS partition; neither is used for bulk history (NVS is
for configuration, RTC SRAM for the double-reset token).

## 4.2 Record formats

All little-endian, packed, no padding. Defined once in `protocol/records.md` and generated into both
`components/cook_store/record.h` and the Flutter DTOs ([10](10-repo-tooling-and-testing.md)).

### Sample record — 16 bytes

```c
typedef struct __attribute__((packed)) {
    uint32_t t;          /* seconds since session start (monotonic, never wall-clock) */
    int16_t  temp[4];    /* tenths of °F, canonical. Sentinels below                  */
    uint8_t  flags;      /* see table                                                 */
    int8_t   rssi;       /* dBm of the packet that produced this sample               */
    uint16_t crc16;      /* CRC-16/CCITT-FALSE over bytes 0..13                       */
} bridge_sample_rec_t;   /* == 16 */
```

| `temp[i]` value | Meaning |
| --- | --- |
| `INT16_MIN` (−32768) | **Probe detached.** Never plot as a temperature |
| `INT16_MIN + 1` | Probe present but reading invalid / out of range (reserved, pending [02 Q4](02-smoke-x-protocol.md)) |
| otherwise | Temperature × 10, °F. Probe range −58…572 °F → −580…5720, well inside `int16` |

| `flags` bit | Meaning |
| --- | --- |
| 0–3 | Alarm **enabled** on probe 1–4 (mirrors the packet's per-probe alarm field) |
| 4 | Billows attached |
| 5 | `new_alarm` was set in this packet |
| 6 | Source packet was in °C (provenance only — the stored value is already °F) |
| 7 | Reserved |

**Why canonical °F rather than "whatever the base sent":** the user can flip the base station
between °F and °C mid-cook, which would otherwise leave a single series with two unit regimes and a
20 °-looking cliff in the middle of the graph. Converting °C tenths on write
(`F10 = C10 × 9 / 5 + 320`) upsamples — 0.1 °C is a finer step than 0.1 °F — so no resolution is
lost. Display units are a presentation choice, stored per session and overridable per user.

**Why no sequence number:** gaps are detectable from `t` alone. A delta greater than ~45 s means
packets were missed; the chart draws a break rather than a straight line across the hole. This is
the specific failure the reference cannot represent, because its samples carry no time at all.

### Session header — 256 bytes, at offset 0 of every `.smk`

| Off | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 4 | `magic` | `"SMKS"` |
| 4 | 2 | `version` | 1 |
| 6 | 2 | `hdr_len` | 256 |
| 8 | 2 | `rec_len` | 16 |
| 10 | 1 | `num_probes` | 2 or 4 |
| 11 | 1 | `flags` | b0 `clock_valid`, b1 `closed`, b2 `pinned`, b3 `source_celsius` |
| 12 | 4 | `session_id` | monotonic, from NVS |
| 16 | 8 | `started_unix_ms` | 0 until the clock is known; back-patched (§4.4) |
| 24 | 8 | `ended_unix_ms` | 0 while open |
| 32 | 4 | `started_uptime_s` | for correlating with logs across a reboot |
| 36 | 4 | `sample_period_s` | nominal 30 |
| 40 | 4 | `sample_count` | authoritative on close; derived from file size while open |
| 44 | 4 | — | reserved |
| 48 | 8 | `device_id[8]` | the paired base station |
| 56 | 40 | `name[40]` | user label, UTF-8 |
| 96 | 48 | `probe_name[4][12]` | UTF-8 |
| 144 | 4 | `probe_role[4]` | 0 unused · 1 pit · 2 food · 3 ambient |
| 148 | 8 | `probe_target[4]` | int16 tenths °F, 0 = no target |
| 156 | 4 | `mark_count` | |
| 160 | 92 | — | reserved, zeroed |
| 252 | 4 | `crc32` | over bytes 0..251 |

The header makes each file **self-describing**: pull a `.smk` off the device and it is fully
interpretable with no index, no database, and no firmware.

### Mark record — 32 bytes, in a sibling `.mrk`

```c
typedef struct __attribute__((packed)) {
    uint32_t t;          /* seconds since session start */
    uint8_t  kind;       /* 0 note · 1 wrapped · 2 lid_open · 3 fuel · 4 probe_moved
                            5 alarm · 6 phase_change · 7 auto_detected              */
    uint8_t  probe;      /* 0 = whole cook, 1..4 = a specific probe */
    uint16_t crc16;
    char     text[24];   /* UTF-8, NUL-padded */
} bridge_mark_rec_t;     /* == 32 */
```

Marks come from a PRG double-tap (kind 0, auto-named `"Mark N"`, renameable later), from the app,
and from the alarm engine (kinds 2/5/7 written automatically when lid-open or an alarm is detected).

## 4.3 On-disk layout

```
/cooks/
├── 0000001A.smk      256 B header + N × 16 B samples
├── 0000001A.mrk      M × 32 B marks       (absent if none)
├── 0000001A.raw      raw LoRa payloads    (only when capture_raw was set)
├── 0000001B.smk
├── 0000001B.mrk
└── novelty.log       64 KB ring, text — see 02 §2.7
```

`novelty.log` is partition-wide, not per-session: it accumulates one line per *structurally new*
packet across the device's whole life, which is what makes protocol investigation free
([02 §2.7](02-smoke-x-protocol.md)). `.raw` files are opt-in per session (~345 KB per 24 h) and the
retention policy keeps only the two most recent.

**No index file.** The session index is rebuilt at boot by reading the 256-byte header of each
`.smk` — 64 sessions is 16 KB of reads, well under 100 ms on LittleFS. An index file is one more
thing to get out of sync with reality after an unclean shutdown, and it buys nothing at this scale.

The in-RAM index is one 40-byte entry per session (id, start, end, samples, probes, flags, name
pointer into a small pool) — ~2.5 KB for 64 sessions.

### Live ring buffer

Separately, `cook_store` keeps the most recent **240 samples (2 h)** in RAM — 3.84 KB. This serves:

- `GET /api/v1/live` instantly with no flash read, so the app's dashboard paints immediately
- the OLED sparkline ([07](07-display-and-controls.md))
- the alarm engine's rolling-window rules ([09](09-alarms-and-insights.md))
- the BLE `history_preview` characteristic

## 4.4 Time without a clock

The board has no battery-backed RTC. Three possible clock sources, in preference order:

1. **SNTP** — when in STA mode with internet reachability
2. **The phone** — over BLE `device_control: set_time` or `POST /api/v1/time`. This is the primary
   source in AP mode, and usually arrives within seconds of the app connecting
3. **Nothing** — the bridge has only `esp_timer` monotonic uptime

The design keeps these strictly separated:

- **Samples always store `t` = seconds since session start**, derived from `esp_timer`. This is
  monotonic, never adjusted, and never wrong. The graph's x-axis is always correct *relative* to
  the cook, which is the axis that actually matters for barbecue.
- **Wall-clock is a session-level property**: `started_unix_ms` + `clock_valid`.

**Back-patching.** If a session starts with no clock (`clock_valid = 0`) and a source arrives 40
minutes later, the firmware computes
`started_unix_ms = now_unix_ms − (uptime_now − started_uptime_s) × 1000`, seeks to offset 16 in the
header, rewrites 8 bytes plus the CRC, and sets `clock_valid`. One 256-byte block rewrite; LittleFS
handles it as a normal in-place update. Every previously written sample becomes correctly dated with
no rewrite of the sample data — the entire reason `t` is relative.

**Monotonic floor.** `time/last_epoch_ms` is persisted every ~10 min. After a reboot the clock
starts from that value marked `source = stale`, so timestamps never go backwards and the app can
show "clock approximate" until a real source lands.

**Time zone** is display-only, stored as `tz_offset_min`, set by the phone. Everything on disk is
UTC.

## 4.5 Crash safety

Power loss mid-cook is the expected case, not the exceptional one — smokers get bumped, extension
cords get tripped over, batteries run down.

**Write path.** Append 16 bytes per sample to the open file. `fsync()` every 4th sample (2 min),
and immediately on: session close, alarm raised, network mode change, OTA start, low-battery
warning, and any button press. Worst-case data loss is **two minutes**.

The trade-off is deliberate. `fsync()` on every sample would cut worst-case loss to 30 s but roughly
quadruples LittleFS metadata commits; at 2,880 samples/day the endurance headroom absorbs either
choice (§4.7), so the deciding factor is write latency inside the event path. Two minutes of a
24-hour cook is noise. The interval is configurable.

**Recovery on open.** When `cook_store` mounts and finds `session/active_id` set:

```
1. open /cooks/<id>.smk
2. validate header magic, version, crc32     → corrupt: rename to .bad, start a fresh session
3. body = size - 256
4. if body % 16 != 0:  truncate to 256 + (body/16)*16     ← torn append
5. read the last record; if crc16 fails:      truncate by 16 more
6. repeat step 5 up to 3 times, then give up and close the session as-is
7. resume appending; write an auto-mark {kind: 7, text: "power restored"}
```

Every layer is defensive: the filesystem is power-loss resilient, records are length-aligned so
truncation is unambiguous, and each record carries its own CRC so a half-programmed final write is
detected rather than plotted.

**The session survives the reboot.** This is the headline improvement over the reference, where any
reset silently discards the entire cook.

## 4.6 Session lifecycle

A session is created automatically — asking the user to remember to press start before an 18-hour
brisket is a design that loses data.

**Start** when *all* of:

- the bridge is paired and receiving state messages
- at least one probe is attached
- no session is currently open

plus **either** any attached probe reading above **90 °F** (i.e. something is actually cooking, not
a probe sitting on the counter) **or** an explicit start from the app or a PRG long-press.

**End** when any of:

- all probes have read detached for **10 continuous minutes**
- explicit stop from the app or a PRG long-press on the cook page
- **36 hours** elapsed (hard cap; auto-starts a continuation session so a genuinely longer cook is
  split rather than lost)
- the bridge is unpaired

**Not** an end condition: packet loss. Going out of range, or the base station being switched off
briefly, leaves the session open and produces a visible gap in `t`. A cook that resumes after a
30-minute dropout is one cook, and the graph should say so.

Auto-naming: `"Cook — Sat 14 Mar, 06:12"` when the clock is known, else `"Cook #27"`. The user
renames from the app; the header's `name` field is rewritten in place.

## 4.7 Retention

Configurable, with these defaults:

| Setting | Default | Behaviour |
| --- | --- | --- |
| `retention_max_sessions` | 64 | Beyond this, delete the oldest **closed, unpinned** session |
| `retention_min_free_pct` | 10 % | Below this, delete oldest closed unpinned sessions until satisfied |
| Pinned sessions | — | Never auto-deleted. Set from the app |
| The active session | — | Never deleted, ever |

If the active session alone would fill the partition — 54 days of continuous logging — appending
stops, `BRIDGE_EVT_STORAGE` fires with `full`, and the OLED and app both say so. Practically
unreachable, but silent data loss is not an acceptable failure mode, so it is explicit.

## 4.8 Read paths

Serving history is a **streaming transform, never a materialized document.** `cook_store` exposes:

```c
/* Streams records to `sink` in fixed-size chunks; never allocates more than `buf_len`. */
esp_err_t cook_store_read(uint32_t session_id,
                          uint32_t from_t, uint32_t to_t,   /* 0,UINT32_MAX = whole */
                          uint16_t stride,                  /* 1 = every record     */
                          uint32_t bucket_s,                /* 0 = no aggregation   */
                          cook_agg_t agg,                   /* NONE | MINMAX | MEAN */
                          cook_sink_fn sink, void *ctx);
```

Because records are fixed-width, a time range is a **seek**, not a scan:
`offset = 256 + index × 16`, and the index for a given `t` is found with a binary search over ≤ 18
reads for a 54-day file.

**Aggregation matters for display honesty.** A 24-hour cook is 2,880 points; a phone chart is
~400 logical pixels wide. Plain stride decimation (take every 6th sample) can step straight over a
lid-open spike. `agg=minmax` emits per bucket the min, mean, and max for each probe, so the
rendered band still contains the excursion. The Flutter chart draws mean as the line and min/max as
a faint envelope ([08](08-flutter-app.md)).

Typical requests:

| View | Query | Points | Bytes |
| --- | --- | --- | --- |
| Live dashboard (last 2 h) | `from=t-7200` | 240 | 3.8 KB |
| Full 15 h cook | `bucket=60&agg=minmax` | 900 | ~22 KB |
| Full 24 h cook | `bucket=90&agg=minmax` | 960 | ~23 KB |
| Full-fidelity export | `format=csv` | 2,880 | ~130 KB CSV |

Even the unaggregated raw form (46 KB for 24 h) is trivial over Wi-Fi; aggregation exists for the
chart's sake and for the constrained BLE path, not to save the network.

**Over BLE**, bandwidth is genuinely scarce (realistically single-digit KB/s). v1.0 therefore serves
over BLE: live state (14 B notify per sample) and a `history_preview` characteristic — the pit
probe at 1-minute buckets for the last 2 hours, 120 × `int16` = 240 B. Full history over BLE is a
chunked-transfer feature deferred to v1.1 and noted in [11](11-roadmap-and-risks.md). **Full history
requires Wi-Fi** in v1.0, and the app says so rather than silently showing a stub.

## 4.9 Flash endurance

| | |
| --- | --- |
| Sample data written per 24 h | 46 KB |
| Realistic programmed bytes/day incl. LittleFS metadata | < 100 KB |
| Five years of daily cooking | ~180 MB |
| Spread over a 2,432 KB wear-levelled partition | **~75 erase cycles per sector** |
| Typical SPI NOR endurance | 100,000 cycles |

Three orders of magnitude of margin. The `fsync` cadence, the retention churn, and the session
header rewrites are all irrelevant against this. Endurance is not a design constraint here and the
design should not contort for it.

## 4.10 Export and versioning

**Export formats**, all generated by streaming (`GET /api/v1/sessions/{id}/samples?format=`):

- `bin` — the raw records. Fastest, and what the Flutter app uses for sync
- `ndjson` — one JSON object per line. Good for `jq`, streaming parsers
- `csv` — `t_seconds,iso8601,probe1_f,probe2_f,probe3_f,probe4_f,billows,rssi`, detached probes
  emitted as empty fields (not `0`), with marks as a companion `?format=csv&marks=1`

The app additionally exports a self-contained JSON bundle (header + samples + marks + app-side
notes) for sharing a cook.

**Versioning.** `version` in both the session header and the record layout. Readers must accept
`hdr_len` and `rec_len` from the header rather than `sizeof()` — that alone makes additive field
growth backward-compatible. A future v2 record can be longer; a v1 reader skips the extra bytes
using `rec_len`. Firmware never rewrites old sessions on upgrade; it reads them at their own
version.
</content>
