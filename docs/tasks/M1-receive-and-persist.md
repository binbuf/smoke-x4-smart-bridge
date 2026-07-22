# M1 — Receive and Persist

**The load-bearing milestone.** A bridge that reliably records cooks to flash is already better than
the reference, and everything downstream assumes the parser is right.

**Exit gate** ([11 §11.1](../design/11-roadmap-and-risks.md)):

- A real Smoke X4 pairs with the bridge **and the stock ThermoWorks receiver keeps working**
- A cook is logged to flash and survives a mid-cook power cut, resuming into the same session
- Real X4 packets are committed to `protocol/fixtures/`, closing as many
  [02 §2.8](../design/02-smoke-x-protocol.md) questions as the hardware can answer
- Host tests pass against **real captures**, not just the synthetic X4 vectors

> **Gate applies to the F track only.** Do not start M2 firmware work until real X4 traffic decodes
> correctly. The A track keeps moving against `tools/sim` regardless — it has no dependency on the
> board until M2.

41 tasks — **39 `board: no`, 2 `board: yes`**.

---

## F7 — app_config

First, because F3 persists pairing state and [03 §3.6](../design/03-firmware-architecture.md) is
explicit that no other component opens NVS directly. The reference scatters `nvs_open` across four
files; that is the thing being fixed.

### F7.1 app_config: implement the typed NVS store and namespace schema

- **blocked-by:** F1.5 · **verify:** H · **board:** no
- **design:** [03 §3.6](../design/03-firmware-architecture.md)

The seven namespaces from §3.6: `sx_pair`, `net`, `device`, `probes`, `session`, `time`, `alarms`.
Keep `sx_pair` **blob-compatible with the reference** so a board upgraded from it keeps its pairing.

**Done when:** every key round-trips through a host-testable typed layer, and the `sx_pair` blob
matches the reference's byte layout.

### F7.2 app_config: implement change notifications and config_version migrations

- **blocked-by:** F7.1 · **verify:** H · **board:** no
- **design:** [03 §3.6](../design/03-firmware-architecture.md)

A single `config_version` key drives forward migrations. Consumers subscribe to changes rather than
re-reading NVS.

**Done when:** a host test migrates a v1 blob forward and a subscriber sees exactly one notification
per write.

### F7.3 app_config: generate the AP PSK on first boot

- **blocked-by:** F7.1 · **verify:** H · **board:** no
- **design:** [05 §5.3](../design/05-connectivity-and-provisioning.md)

Ten characters from the hardware RNG over an unambiguous alphabet — no `0/O`, no `1/l/I`, because
this gets read off a 128×64 OLED in a dark yard. Stored in NVS, regenerated **only** on factory reset.

This replaces the reference's hard-coded `Smoke X Receiver` / `The extra B is for BYOBB`. A fixed,
publicly documented password on a device broadcasting an open API is not a good default, however
charming the passphrase.

**Done when:** the PSK is stable across reboots, changes on factory reset, and contains no ambiguous
glyph.

---

## F2 — app_lora

### F2.1 app_lora: vendor esp-idf-sx126x as a pinned submodule

- **blocked-by:** F1.2 · **verify:** H · **board:** no
- **design:** [01 §1.5](../design/01-hardware.md), [10 §10.1](../design/10-repo-tooling-and-testing.md)

`vendor/esp-idf-sx126x` at a pinned commit, wired as an IDF component. The `ra01s` driver is a
known-good pairing with this board — that is why D5 fixes us to ESP-IDF v5.4 and C.

**Done when:** `make setup && make build` pulls and compiles the submodule from a clean checkout.

### F2.2 app_lora: implement the RX loop with the §1.5 radio parameters

- **blocked-by:** F2.1, F1.4 · **verify:** H · **board:** no
- **design:** [01 §1.5](../design/01-hardware.md), [02 §2.1](../design/02-smoke-x-protocol.md)

SF9, bandwidth **index 4** (= 125 kHz; the SX126x driver takes an index, not Hz, unlike the SX1276
path — an easy and silent mistake), CR 4/5, preamble 10, sync word `0x12`, CRC on, TCXO 3.3 V LDO,
`LoRaBegin(freq, 22, 3.3, 1)`. Task pinned to core 1.

The driver polls with `vTaskDelay(1)` while holding a radio semaphore. That is fine — packets arrive
at most every 30 s and there is no throughput pressure whatsoever. **Do not migrate to DIO1
interrupts**; that is a v1.1 item ([§12.7](../design/12-task-planning-notes.md)).

**Done when:** a host-testable seam lets a payload be injected without a radio, and the parameter
block is asserted against the §1.5 table.

### F2.3 app_lora: implement the TX guard

- **blocked-by:** F2.2 · **verify:** H · **board:** no
- **design:** [02 §2.5](../design/02-smoke-x-protocol.md), [01 §1.5](../design/01-hardware.md)

**The bridge transmits exactly one packet per pairing: the sync ACK.** No polling, no keepalive, no
beacon. A `radio_tx_allowed` flag is true only inside the sync handler. Frequency is range-checked
against 902–928 MHz **before** retuning — a corrupted sync message could decode to any `uint32`, and
transmitting outside the ISM band is illegal.

Also gate `POST /api/v1/radio/tx` behind `CONFIG_SMOKEBRIDGE_RADIO_DEBUG`, off in release builds. The
reference ships an unauthenticated arbitrary-transmit command over HTTP; we do not.

**Done when:** a **host test asserts that no call path other than the sync handler reaches
`app_lora_start_tx`**, and an out-of-band frequency is rejected without retuning. This invariant is
load-bearing — it is what keeps us a listener rather than a device that can disrupt a real cook.

### F2.4 app_lora: record RSSI and SNR per packet

- **blocked-by:** F2.2 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md)

`GetPacketStatus()` already yields both. Record them per sample as `int8`. Link quality is genuinely
useful — it tells the user when the bridge is about to lose the base station, and it makes antenna
placement a measurement rather than a guess.

**Done when:** both values reach `bridge_sample_t` and survive the record encode.

### F2.5 app_lora: implement the unpaired frequency scanner

- **blocked-by:** F2.2 · **verify:** H · **board:** no
- **design:** [02 §2.4](../design/02-smoke-x-protocol.md)

Alternate 915 ↔ 920 MHz every **3.3 s** while the base beacons every 3 s — deliberately offset so the
two never lock into a beat pattern that starves one channel.

**Done when:** a host test confirms the dwell is 3.3 s and both channels are visited.

---

## F3 — smoke_x

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** four header fields and one
> trailing field are unidentified. Write the parser against the reference vectors, timebox
> X4-specific assertions until V2.1's captures land, and **expect one rework pass.** This is the
> epic most likely to blow its budget.

### F3.1 smoke_x: port smoke_x_parser.c with the MIT notice intact

- **blocked-by:** F1.6 · **verify:** H · **board:** no
- **design:** [02 §2.6](../design/02-smoke-x-protocol.md), [00 D9](../design/00-overview.md)

Copy `smoke_x_parser.{c,h}` and `smoke_x_types.h` into `components/smoke_x/`, retaining the MIT
© 2022 G-Two notice. Port `test/test_smoke_x_parser.c` as the seed corpus. The parser's shape — pure
C, no ESP-IDF headers, host-testable — is exactly right; extend it, don't rewrite it.

**Done when:** the reference's own test suite passes unmodified against the ported parser.

### F3.2 smoke_x: replace strtok with strtok_r on a stack buffer

- **blocked-by:** F3.1 · **verify:** H · **board:** no
- **design:** [02 §2.6](../design/02-smoke-x-protocol.md)

`strtok` is not reentrant. The parser is called from one task today, but that is an accident, not a
guarantee. Max payload is ~120 B, so a stack buffer removes the heap copy entirely.

**Done when:** no allocation occurs on the parse path and the suite still passes.

### F3.3 smoke_x: replace the units pointer-identity check with an enum

- **blocked-by:** F3.1 · **verify:** H · **board:** no
- **design:** [02 §2.6](../design/02-smoke-x-protocol.md)

The reference detects a unit change by comparing `const char*` pointers for equality — it works, and
it is a trap for anyone who later refactors the parser. Make it an explicit enum in the parsed struct.

**Done when:** a unit change is detected by value, and a test that copies the string still detects it.

### F3.4 smoke_x: compare device_id and count mismatches

- **blocked-by:** F3.1 · **verify:** H · **board:** no
- **design:** [02 §2.6](../design/02-smoke-x-protocol.md)

The reference parses the state message's `device_id` and discards it. With two Smoke X units in range
on the same channel, that silently interleaves two cooks into one graph. Compare against the paired
ID; drop and count mismatches.

**Done when:** a fixture carrying a foreign device ID is dropped and the counter increments.

### F3.5 smoke_x: map detached probes to the sentinel and decode Billows fields

- **blocked-by:** F3.1 · **verify:** H · **board:** no
- **design:** [02 §2.2.3](../design/02-smoke-x-protocol.md), [04 §4.2](../design/04-storage-and-history.md), [00 D11](../design/00-overview.md)

`state == 3` → `INT16_MIN`, **never `0.0`**. In the captured detached sample the other four fields are
all zeros, and the reference stores that as a real temperature — which draws a line straight to zero
on the graph.

Decode `billows_attached` into `flags` bit 4 and the overloaded `billows_target` field, and **store
them**. Per D11 there is no tile, no alarm rule, and no API concept in v1 — but the fields cost
nothing to decode, so a future build with a Billows in hand reinterprets existing cooks instead of
needing new ones.

**Done when:** the detached fixture yields the sentinel, and the Billows fixture round-trips both
fields through a stored record.

### F3.6 smoke_x: implement the pairing state machine

- **blocked-by:** F3.1, F2.3, F2.5, F7.1 · **verify:** H · **board:** no
- **design:** [02 §2.4](../design/02-smoke-x-protocol.md)

`UNPAIRED → SYNC_RECEIVED → CONFIRMED`, persisted through `app_config`. Three details that are easy
to get wrong:

- **Probe count is learned from the first state message, not the sync message.** The bridge does not
  know whether it paired with an X2 or an X4 until data arrives.
- The ACK goes out on the **operating** frequency after retuning, never on the sync channel.
- Once `sync_received` is set, further sync messages are ignored until an explicit unpair.

Unpair clears `device_id` and `frequency` and restarts the scan. **It must not affect the pairing
state of any other receiver**, including ThermoWorks' own.

**Done when:** the full transition sequence passes on host fixtures, including an X2 (16-comma) and
an X4 (26-comma) confirming different probe counts from the same sync.

### F3.7 smoke_x: implement the stale-pairing watchdog and packet accounting

- **blocked-by:** F3.6 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md)

`BASE_LOST` after N × 30 s with no valid state message (default N = 20, i.e. 10 min), `BASE_FOUND` on
recovery. Counters for valid messages, CRC failures, unknown comma counts, and device-ID mismatches,
plus an inter-packet interval histogram — cheap, and it turns *"it seems flaky"* into a number.

The optional re-scan after 60 min with no packets **and** no active cook stays config-gated and
**default off**: silently re-pairing to a different base station would be worse than staying put.

**Done when:** the watchdog fires and clears on a synthetic packet gap, and the re-scan does not
engage by default.

### F3.8 smoke_x: validate the parser against the real X4 captures

- **blocked-by:** F3.6, V2.1, V2.2, T4.3 · **verify:** H · **board:** no
- **design:** [02 §2.3, §2.8](../design/02-smoke-x-protocol.md)

Run the whole corpus from `protocol/fixtures/lora/` — including malformed and truncated payloads —
against the parser. Update the confidence markers in [02](../design/02-smoke-x-protocol.md) from
**[I]** to **[K]** where the captures settle a field, and update the §2.8 status column.

**Done when:** every real capture parses to the values observed on the reference's serial log, and Q1
and Q6 are marked resolved (or explicitly still open with what was learned).

### F3.9 smoke_x: verify pairing against a real X4 without disturbing the stock receiver

- **blocked-by:** F3.8 · **verify:** C · **board:** yes
- **design:** [02 §2.5](../design/02-smoke-x-protocol.md), [11 §11.1](../design/11-roadmap-and-risks.md)

Pair the bridge with a real Smoke X4 while the stock ThermoWorks receiver stays paired and running.
Then unpair and re-pair. **The stock receiver must keep working throughout** — invariant 2, and the
whole basis of R9's "we coexist, we don't replace".

**Done when:** a full pair → unpair → re-pair cycle leaves the stock receiver unaffected, recorded in
the PR. **This is half of M1's exit gate.**

---

## F4 — Novelty log and packet capture

**Land this early in M1, not late** ([§12.6 rule 2](../design/12-task-planning-notes.md)). Every cook
before it exists is evidence thrown away, and six of the eight open protocol questions close by
themselves once it is running. With one board there is no dedicated capture rig — the bridge under
test *is* the bridge collecting evidence, so capture has to be permanent background behaviour rather
than a deliberate session.

### F4.1 smoke_x: implement the RAM packet ring

- **blocked-by:** F3.1 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md), [10 §10.4](../design/10-repo-tooling-and-testing.md)

Last 64 raw payloads with RSSI, SNR, and uptime. Free, and it answers *"what did it just receive?"*
without a second SDR.

**Done when:** the ring wraps correctly and survives 1,000 synthetic packets without leaking.

### F4.2 smoke_x: implement the novelty seen-set and reason classes

- **blocked-by:** F4.1 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md)

Logging every raw packet costs ~345 KB per 24 h — 7.7× the sample data. Instead keep a seen-set of
the values every normally-constant field has ever taken, and persist a packet only when something is
new. All ten reasons: `first`, `field1`, `trailing`, `probe_state`, `alarm_edge`, `billows`, `units`,
`sync`, `unparsed`, `id_mismatch`.

`alarm_edge` must capture **the two packets either side** of the transition — that is what answers Q8.

**Done when:** a synthetic stream containing one instance of each reason produces exactly ten entries,
and a repeat of the same value produces none.

### F4.3 cook_store: persist novelty.log as a pinned ring

- **blocked-by:** F4.2, F5.5 · **verify:** H · **board:** no
- **design:** [02 §2.7](../design/02-smoke-x-protocol.md), [04 §4.3](../design/04-storage-and-history.md)

64 KB / 512 entries, partition-wide rather than per-session, plain text so it can be pulled off and
read directly. **The first instance of each distinct `reason`+value pair is pinned** so later churn
can never evict the evidence that mattered.

Add a serial console command to dump it. The HTTP endpoints (`/api/v1/debug/novelty` and
`/debug/packets`) arrive with F9 in M2 — but the *capture* must be running now, because that is the
half that cannot be backfilled.

**Done when:** the ring wraps without evicting a pinned entry, and the file survives a remount.

---

## F5 — cook_store

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** torn-write recovery is easy to
> write and hard to get right. The truncate-at-every-offset test in F5.3 is not optional.

### F5.1 cook_store: implement record encode/decode and CRC on the host

- **blocked-by:** P1.2, F1.6 · **verify:** H · **board:** no
- **design:** [04 §4.2](../design/04-storage-and-history.md)

Built on `record_gen.h`. CRC-16/CCITT-FALSE over bytes 0..13 of a sample; CRC-32 over bytes 0..251 of
a header. Readers take `hdr_len` and `rec_len` **from the header**, never from `sizeof` — that alone
makes additive field growth backward-compatible.

**Done when:** every fixture in `protocol/fixtures/records/` round-trips, and the future-`version`
header with a larger `rec_len` is read rather than rejected.

### F5.2 cook_store: implement session open, append, and close

- **blocked-by:** F5.1 · **verify:** H · **board:** no
- **design:** [04 §4.2, §4.3](../design/04-storage-and-history.md)

256-byte header at offset 0, then N × 16 B. `sample_count` is authoritative on close and derived from
file size while open — so an unclean shutdown cannot leave a lying header.

**Done when:** a written session reopens and reads back identically, against an in-memory filesystem
double.

### F5.3 cook_store: recover a torn append on session open

- **blocked-by:** F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.5](../design/04-storage-and-history.md), [§12.10](../design/12-task-planning-notes.md)

The seven-step §4.5 sequence when reopening a session whose `active_id` is set: validate header
magic/version/CRC, align the body to a whole number of records, then walk back up to three records
validating CRC-16, truncating each time. Write an auto-mark `{kind: 7, text: "power restored"}` on
successful resume. A header that fails validation renames the file to `.bad` and starts fresh rather
than discarding data silently.

**Done when:** host tests pass for a `.smk` truncated at **every** byte offset within the final
record, a header with bad CRC, a header with bad magic, and a header declaring a future `version`
with a larger `rec_len`. Recovery must converge in all cases — **no infinite loop, no unbounded
truncation.**

### F5.4 cook_store: implement the session lifecycle rules

- **blocked-by:** F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.6](../design/04-storage-and-history.md)

Sessions start automatically — asking the user to remember to press start before an 18-hour brisket
is a design that loses data.

Start when paired ∧ ≥ 1 probe attached ∧ no session open, **and** (any attached probe above 90 °F ∨
an explicit start). End on: all probes detached for 10 continuous minutes ∨ explicit stop ∨ 36 h cap
(auto-starting a continuation session) ∨ unpaired.

**Packet loss is deliberately not an end condition.** A cook that resumes after a 30-minute dropout
is one cook, and the graph should say so.

**Done when:** a table test covers each start and end condition, and a 40-minute synthetic dropout
leaves the session open with a visible gap.

### F5.5 cook_store: implement the LittleFS binding and boot-time index rebuild

- **blocked-by:** F5.2, F1.2 · **verify:** H · **board:** no
- **design:** [04 §4.3](../design/04-storage-and-history.md), [03 §3.5](../design/03-firmware-architecture.md)

Mount `/cooks` via `joltwallet/littlefs`. **No index file** — rebuild the in-RAM index at boot by
reading each `.smk`'s 256-byte header. 64 sessions is 16 KB of reads, well under 100 ms. An index file
is one more thing to desynchronise from reality after an unclean shutdown and buys nothing at this
scale.

In-RAM index is ~40 B per session — ~2.5 KB for 64.

**Done when:** an index rebuild from 64 synthetic sessions completes within budget and skips a `.bad`
file without aborting.

### F5.6 cook_store: implement the 240-sample live ring

- **blocked-by:** F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.3](../design/04-storage-and-history.md)

Two hours at 30 s = 3.84 KB in RAM. Serves `GET /api/v1/live` with no flash read, the OLED sparkline,
the alarm engine's rolling-window rules, and the BLE `history_preview` — so the alarm path never
touches flash.

**Done when:** the ring is exactly 240 entries, wraps correctly, and its slope over the last 20
samples matches A2.2's Dart implementation on shared input.

### F5.7 cook_store: implement the fsync policy

- **blocked-by:** F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.5](../design/04-storage-and-history.md)

`fsync()` every 4th sample (2 min), and immediately on: session close, alarm raised, network mode
change, OTA start, low-battery warning, and any button press. Worst-case loss is two minutes of a
24-hour cook — noise. Endurance absorbs either choice (three orders of magnitude of margin), so the
deciding factor is write latency inside the event path. Configurable.

**Done when:** the cadence is asserted and each immediate-flush trigger is covered.

### F5.8 cook_store: implement retention

- **blocked-by:** F5.5 · **verify:** H · **board:** no
- **design:** [04 §4.7](../design/04-storage-and-history.md)

`retention_max_sessions` 64, `retention_min_free_pct` 10 %. Delete the oldest **closed, unpinned**
session. Pinned sessions are never auto-deleted; **the active session is never deleted, ever.**

If the active session alone would fill the partition — 54 days of continuous logging — appending
stops and `BRIDGE_EVT_STORAGE` fires with `full`. Practically unreachable, but silent data loss is
not an acceptable failure mode.

**Done when:** host tests cover retention with a pinned oldest session, with only the active session
present, and the partition-full path.

### F5.9 cook_store: implement marks

- **blocked-by:** F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.2, §4.3](../design/04-storage-and-history.md)

32-byte records in a sibling `.mrk`, absent when there are none. Kinds 0–7, with 2/5/7 written
automatically by the lid-open detector, the alarm engine, and power-restore recovery.

**Done when:** marks round-trip including multibyte UTF-8 truncated safely at 24 bytes.

### F5.10 cook_store: implement the streaming read path

- **blocked-by:** F5.1, F5.5 · **verify:** H · **board:** no
- **design:** [04 §4.8](../design/04-storage-and-history.md), [06 §6.1](../design/06-device-api.md)

`cook_store_read(session_id, from_t, to_t, stride, bucket_s, agg, sink, ctx)` — **never allocates
more than `buf_len`.** Because records are fixed-width, a time range is a *seek*, not a scan:
`offset = 256 + index × 16`, with binary search over ≤ 18 reads for a 54-day file.

`agg=minmax` emits per-bucket min/mean/max per probe. This is display honesty, not compression: a
24-hour cook is 2,880 points against ~400 logical pixels, and plain stride decimation steps straight
over a lid-open spike.

**Done when:** a 24-hour fixture returns 960 buckets at `bucket=90&agg=minmax`, a synthetic spike
survives in the `max` series, peak RAM during a full read is bounded and asserted, and a range query
on a 54-day file completes within the binary-search bound.

### F5.11 cook_store: verify session resume across a real power cut

- **blocked-by:** F5.3, F5.4, F3.9 · **verify:** C · **board:** yes
- **design:** [04 §4.5](../design/04-storage-and-history.md), [11 §11.1](../design/11-roadmap-and-risks.md)

Pull power mid-cook on real hardware. The session must reopen, recover any torn final record, append
the `"power restored"` auto-mark, and continue into **the same session** — not a new one.

Power loss mid-cook is the expected case, not the exceptional one: smokers get bumped, extension
cords get tripped over, batteries run down. This is the headline improvement over the reference,
where any reset silently discards the entire cook.

**Done when:** observed on the board with the resulting `.smk` committed to the PR. **This is the
other half of M1's exit gate.**

---

## F6 — app_time

### F6.1 app_time: implement clock source arbitration

- **blocked-by:** F7.1 · **verify:** H · **board:** no
- **design:** [04 §4.4](../design/04-storage-and-history.md)

SNTP > phone > none, with the active `source` recorded. The board has no battery-backed RTC.

**Samples always store `t` = seconds since session start**, from `esp_timer` — monotonic, never
adjusted, never wrong. Wall clock is a session-level property, not a per-sample one. The graph's
x-axis is always correct *relative to the cook*, which is the axis that actually matters for barbecue.

**Done when:** source precedence is table-tested and a source change never rewrites a sample's `t`.

### F6.2 app_time: implement header back-patching

- **blocked-by:** F6.1, F5.2 · **verify:** H · **board:** no
- **design:** [04 §4.4](../design/04-storage-and-history.md)

When a session starts with `clock_valid = 0` and a source arrives later, compute
`started_unix_ms = now_unix_ms − (uptime_now − started_uptime_s) × 1000`, seek to header offset 16,
rewrite 8 bytes plus the CRC, and set `clock_valid`. Every previously written sample becomes
correctly dated with **no rewrite of sample data** — the entire reason `t` is relative.

**Done when:** the named case from [10 §10.5](../design/10-repo-tooling-and-testing.md) passes: a
session that starts with no clock and acquires one at t = 40 min.

### F6.3 app_time: implement the monotonic floor

- **blocked-by:** F6.1 · **verify:** H · **board:** no
- **design:** [04 §4.4](../design/04-storage-and-history.md)

Persist `time/last_epoch_ms` about every 10 minutes. After a reboot, start from that value marked
`source = stale`, so timestamps never go backwards and the app can honestly say "clock approximate"
until a real source lands. Everything on disk is UTC; `tz_offset_min` is display-only.

**Done when:** a reboot with no clock source produces a non-decreasing epoch marked stale.

---

## T4 — Capture and replay tooling

**Replay is not optional tooling.** One captured cook has to serve as an unlimited test fixture,
because you cannot re-run reality ([11 §11.6](../design/11-roadmap-and-risks.md)).

### T4.1 tools/lora: write the .loralog normaliser

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [10 §10.4](../design/10-repo-tooling-and-testing.md)

Turn serial-captured reference output and dumped `novelty.log` files into normalised `.loralog`
records (uptime, rssi, snr, payload). The HTTP fetch path in `pull.py` arrives with F9 in M2; at M1
the source is a serial dump, which is all V2.1 produces.

**Done when:** V2.1's raw serial log normalises without hand-editing.

### T4.2 tools/lora: write replay.py

- **blocked-by:** T4.1 · **verify:** H · **board:** no
- **design:** [10 §10.4](../design/10-repo-tooling-and-testing.md)

Feed a `.loralog` into (a) the host test corpus and (b) a firmware build where `app_lora` is swapped
for a stub fed from a file — so the whole decode → store → alarm → API path runs at 100× speed with
no Smoke X, no smoker, and no fire.

**One captured cook becomes an unlimited test fixture.** With a single board this is not a
convenience; it is what makes iteration possible at all.

**Done when:** an 18-hour capture replays through the full firmware path in under a minute and
produces a byte-identical `.smk` on repeat runs.

### T4.3 tools/lora: commit the fixture corpus

- **blocked-by:** T4.1, V2.1, V2.2 · **verify:** H · **board:** no
- **design:** [10 §10.4](../design/10-repo-tooling-and-testing.md), [02 §2.3](../design/02-smoke-x-protocol.md)

`protocol/fixtures/lora/` with the real X4 state and sync captures, plus deliberately malformed and
truncated payloads. Replace the synthetic X4 vector in [02 §2.3](../design/02-smoke-x-protocol.md)
and note in the doc which vectors are now real.

**Done when:** the corpus is committed and F3.8 can run against it.

---

## A4 — Local cache and delta sync

The app owns a full copy of every cook it has seen. Charts read from drift, **never from the
network**, so scrolling history works on the couch with the bridge unplugged.

### A4.1 data/local: define the drift schema and migrations

- **blocked-by:** A3.2 · **verify:** H · **board:** no
- **design:** [08 §8.5](../design/08-flutter-app.md)

`bridges`, `sessions`, `samples` (PK `(bridgeId, sessionId, t)`, `p1..p4` **nullable** ints in tenths
°F), `marks`, `alarmLog`.

Per D12 the schema stays multi-bridge capable even though the UI is single-device — the plumbing
costs nothing to keep general, and adding a picker later becomes screens rather than a migration.

**Done when:** the schema builds, migrations run from empty, and a detached probe stores as `NULL`.

### A4.2 data/local: implement the DAOs with batched background inserts

- **blocked-by:** A4.1 · **verify:** H · **board:** no
- **design:** [08 §8.5](../design/08-flutter-app.md)

`batch()` inside one transaction on a background isolate. A 24-hour cook is 2,880 rows and must land
in tens of milliseconds without touching the UI frame budget.

Write the DAO interface so that swapping to per-session BLOB chunks — which is exactly the wire
format — would not reach the repository layer. That is the escape hatch if profiling ever disagrees
with one-row-per-sample.

**Done when:** 2,880 rows insert within budget in a benchmark test and range queries return correctly.

### A4.3 data/repos: implement the delta-sync engine

- **blocked-by:** A4.2, A3.3, T3.2 · **verify:** S · **board:** no
- **design:** [08 §8.5](../design/08-flutter-app.md)

On connect: `GET /status` (firmware version gate, active session id), `GET /sessions` (reconcile new,
updated, deleted), then for each session where `cachedMaxT < deviceMaxT` fetch
`?format=bin&from=cachedMaxT+1` and batch-insert. Reconnecting mid-cook transfers only what was
missed.

**Done when:** against `tools/sim`, a simulated three-hour disconnect and reconnect transfers exactly
360 samples (5.8 KB), and a restart mid-sync resumes without duplicating rows.

### A4.4 data/repos: implement cache-first reads

- **blocked-by:** A4.3 · **verify:** S · **board:** no
- **design:** [08 §8.5](../design/08-flutter-app.md)

`BridgeRepository` and `SessionRepository` read from drift and treat the transport as a refresh
source, so every screen renders offline.

**Done when:** a repository test against `MockTransport` plus an in-memory drift database serves a
full 18-hour cook with the transport disconnected.

---

## What is deliberately *not* in M1

| | Why |
| --- | --- |
| Wi-Fi, HTTP, WebSocket, mDNS | M2. F5.10's streaming read is built now so F9 has nothing to invent |
| `/api/v1/debug/*` endpoints | M2 with F9. F4 captures the evidence now; reading it over HTTP can wait |
| BLE / NimBLE | M3 |
| Any Flutter screen | M4. A2–A4 are logic and data only — no UI work before `tools/sim` and the transports are solid ([§12.6 rule 1](../design/12-task-planning-notes.md)) |
| Alarm engine, OLED pages, button gestures | M5 |
| OTA, battery ADC | M6 / M5. F12 additionally gates on V1.3's divider ratio ([§12.6 rule 6](../design/12-task-planning-notes.md)) |
