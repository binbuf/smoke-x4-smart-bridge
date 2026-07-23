# M3 — BLE and Provisioning

**The milestone where the bridge stops needing a laptop.** Everything M2 proved with `curl` becomes
reachable from a phone standing at the smoker: NimBLE advertises, the OLED lights for the first
time to show a passkey, and the app provisions Wi-Fi over an encrypted, authenticated GATT link
that **stays connected across the network transition it causes** — which is the entire reason a
wrong password is recoverable from a lawn chair. The contract was frozen in M0
([ble-gatt](../../protocol/ble-gatt.md), P3.1) and the codecs already generated; like M2, this is
wiring, not negotiation.

**Exit gate** ([M3 outline](M2-M6-outline.md), [11 §11.1](../design/11-roadmap-and-risks.md)):

- A phone provisions the bridge **from factory-reset to a working STA connection entirely over
  BLE**
- It recovers from a **deliberately wrong Wi-Fi password without touching the hardware**

> **The sitting carries M2's debts, stated now so they cannot slip again.** Two rows were
> deliberately deferred out of the M2 bench by owner decision
> ([hardware-verified](../hardware-verified.md)): the real-credential STA join — credentials belong
> to the provisioning flow, not a bench file — and mDNS-from-LAN, which needs a real STA to test
> from. Both close inside A8.4. And F9.13's heap sign-off was **provisional**, with the NimBLE
> allowance subtracted on paper; V3a.1 is the promised re-measure, and the paper arithmetic is
> already uncomfortable (see that task). If V3a.1 fails, that is a design conversation before M4 —
> not after.

28 tasks — **24 `board: no`, 4 `board: yes`**. The board tasks (F10.10, A6.7, A8.4, V3a.1) form
**one bench sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)) at the end, after every
host- and sim-verifiable box is closed. The F track (P3.2 → F11a → F10) and the A track (A6 → A8)
run in parallel; the sitting is where they join. F11a lands before F10 finishes bonding
([§12.6 rule 4](../design/12-task-planning-notes.md)): the passkey is displayed on the OLED, and
without the display a serial fallback would have to be built and then removed.

---

## P3 — GATT contract completion

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** M2's not-in-table promised
> that setting the optional API bearer token "travels over BLE (M3)" — but the frozen v1
> `control_op` table has **no `set_token` op**, and `result.detail` only carries the AP PSK. Either
> the token gets an additive op 12 (a contract change: `records.yaml`, regenerated codecs, a
> [ble-gatt](../../protocol/ble-gatt.md) section) or token provisioning moves to v1.1 and M4's
> settings UI hides the toggle when no transport can set it. **Decide it in P3.2 and record the
> decision in [ble-gatt](../../protocol/ble-gatt.md)** — do not let it drift into F10 as an
> invented op. A second, smaller question rides along: `live_state.soc_pct` and the advertising
> blob's `soc` have **no "battery unknown" sentinel**, and the truth-producing `app_power` is M5's
> F12. Pick the degenerate value (and whether a `device_info.caps` reserved bit should say "no
> battery yet") here, once, in the contract — not ad hoc in two codebases.

### P3.2 protocol: fold device_info and wifi_scan_ctrl into records.yaml and regenerate

- **blocked-by:** P3.1, P1.4 · **verify:** H · **board:** no
- **design:** [ble-gatt §5.1, §5.3](../../protocol/ble-gatt.md), [10 §10.2](../design/10-repo-tooling-and-testing.md)

The debt [ble-gatt](../../protocol/ble-gatt.md) declares at its own top: `device_info` (40 B) and
`wifi_scan_ctrl` (2 B) exist only as prose tables, and "must be folded into `records.yaml` before
the firmware BLE service (M3) implements them." Add both to the `ble_payloads` section, regenerate
`record_gen.h` and `records.g.dart` through `tools/protogen` (P1.4's staleness gate keeps the
output honest), commit hex fixture vectors alongside the existing record fixtures, and update
Appendix A so the "no generated codec yet" note disappears. Resolve both epic-flag questions while
the file is open.

**Done when:** both codecs round-trip their fixtures in C and Dart, the parity suites pass on
shared vectors, CI's regen check stays green, and the two contract questions have recorded answers
in [ble-gatt](../../protocol/ble-gatt.md).

---

## F11a — app_ui, the passkey half

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** this is pixel work — a
> 12×24 font table, inverted regions, an 8-row layout at 21 columns — and pixel work iterated over
> a serial cable on one board is misery. **The framebuffer→PNG harness comes first** (the reference
> ships `scripts/render_oled_preview.py` to copy), page renderers are pure functions of a snapshot
> struct, and every glyph decision is reviewed as a PNG in CI before the panel ever shows it.

F11 splits here, deliberately ([M3 outline](M2-M6-outline.md)): M3 takes **only what F10 needs** —
display init, the framebuffer, the large font, the passkey overlay. The five pages, the gesture
machine, sparkline, LED, and the sleep policy all belong in M5 with the alarm engine. At M3 the
panel is dark except while pairing is in progress; that is honest scope, not a stub.

The component keeps the established shape: a pure `app_ui_core` (framebuffer, fonts, renderers —
no ESP-IDF headers) under thin I²C glue, so all of it runs in the host suite.

### F11a.1 app_ui: implement the framebuffer core and drawing primitives

- **blocked-by:** F1.6 · **verify:** H · **board:** no
- **design:** [07 §7.1, §7.6](../design/07-display-and-controls.md)

The reference's 1 KB page-ordered framebuffer and flush split are correct — keep them, as §7.6
says, and skip LVGL entirely. This task is the buffer plus the primitives the passkey overlay
needs: pixel set/clear, the 5×7 small font on its 6×8 cell (21 columns × 8 rows), `draw_hline` /
`draw_rect`, and `draw_invert_region`. `draw_sparkline`, `draw_progress`, and `draw_bitmap` (the
eventual QR) wait for F11b in M5 — decided, not forgotten.

**Done when:** primitives are pixel-asserted on the host against expected buffers, text clipping at
column 21 and row 8 is exact, and an invert-then-invert round-trips to the original buffer.

### F11a.2 tools/oled: write the framebuffer→PNG preview harness

- **blocked-by:** F11a.1 · **verify:** H · **board:** no
- **design:** [07 §7.6](../design/07-display-and-controls.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

Copy the reference's `scripts/render_oled_preview.py` and adapt it to our framebuffer dump format:
a host test renders a snapshot, writes the raw 1 KB buffer, and the script turns it into a scaled
PNG. Golden buffers live next to the host tests; CI compares byte-exact and uploads the rendered
PNGs as artifacts, so a font tweak is reviewed by looking at a picture instead of decoding hex.
This is the task that makes every later F11 task cheap, which is why it is second, not last.

**Done when:** a fixture buffer renders to a committed golden PNG in CI, a deliberate one-pixel
change fails the comparison, and the artifact upload shows the rendered image on a PR.

### F11a.3 app_ui: implement the 12×24 large font

- **blocked-by:** F11a.1, F11a.2 · **verify:** H · **board:** no
- **design:** [07 §7.1, §7.6](../design/07-display-and-controls.md)

The headline font: digits `0–9`, space, and `°` at 12×24 — ~1.2 KB of table — with
`draw_text_large()`. It exists in M3 for exactly one screen (six passkey digits readable across a
dark yard) and gets reused by every M5 page, so the glyph table is reviewed once, now, through the
PNG harness.

**Done when:** every glyph renders pixel-identical to its committed golden, and a passkey-sized
string centres correctly on the 128-wide buffer.

### F11a.4 app_ui: implement the passkey overlay renderer

- **blocked-by:** F11a.3 · **verify:** H · **board:** no
- **design:** [07 §7.3](../design/07-display-and-controls.md), [05 §5.6](../design/05-connectivity-and-provisioning.md)

`render_overlay_passkey(const ui_state_t*)` — a pure function of the snapshot struct, per §7.6 —
producing the §7.3 mock: `PAIR WITH PHONE`, the six digits in the large font with the group gap
(`418 302`), `enter this code in the app`. One decided deviation, so the golden is not mistaken for
drift: **row 7 stays blank in M3.** The §7.3 mock shows the status strip there, but the strip's
sources (SoC, alarm glyph) are M5 components; F11b adds the strip to every page and overlay at
once.

**Done when:** the renderer's golden PNG matches the §7.3 layout (row 7 blank), digit grouping is
correct for all-zero and all-nine passkeys, and the renderer touches nothing outside the buffer.

### F11a.5 app_ui: implement the SSD1306 glue with Vext rail sequencing

- **blocked-by:** F11a.4, F1.3, F1.4 · **verify:** H · **board:** no
- **design:** [07 §7.1](../design/07-display-and-controls.md), [01 §1.2](../design/01-hardware.md), [hardware-verified V1.4](../hardware-verified.md)

The thin half: SSD1306 init at I²C 400 kHz (SDA 17, SCL 18, RST 21) behind an injected i2c ops
seam, plus the minimal render service on the existing `app_ui` task row — subscribe to the bus,
show the passkey overlay when F10.5 announces one, blank the panel (`0xAE`) when bonding ends. The
board-found fact from V1.4 is **baked in, not remembered**: the OLED's I²C pull-ups hang off the
switched Vext rail, so the sequence is Vext (GPIO36) LOW → settle → *create* the `i2c_master` bus →
init — creating the bus before rail power-up wedges the controller. The bench already paid for this
lesson in `bench.c`; F11a.5 is where it moves into the product.

**Done when:** a host test asserts the exact init-command and rail-ordering sequence through the
seam, the render service draws only on state change (no unconditional 1 Hz redraw), and a
rail-before-bus ordering violation is impossible to express through the component's API.

---

## F10 — app_ble

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md), R7):** Android BLE is Android
> BLE — bonding, MTU negotiation, and notification reliability all vary by OEM, which is why this
> epic is budgeted generously and why `live_state` was designed at 16 B: it survives the 23-byte
> default MTU when negotiation fails, so telemetry degrades rather than breaks. The host suite
> proves the contract; **the bench is the only test that counts**, and one rework pass after the
> sitting is expected, not a failure. A second flag, structural: NimBLE's stock bond store
> (`ble_store_config`) opens NVS directly, and [03 §3.6](../design/03-firmware-architecture.md) is
> explicit that only `app_config` does that. Spike the store-callback wiring **early in F10.5** —
> either bonds route through `app_config`'s typed layer or the exception is documented in 03 §3.6,
> but it is decided, not discovered.

Same component shape as F8 and F9: a pure `app_ble_core` — characteristic registry, payload
assembly, write dispatch, security table — over injected state providers and ops, with the NimBLE
glue kept thin. **Every payload serializes through `record_gen.h`; nothing is hand-rolled.** The
codecs, their fixtures, and the Dart mirrors have existed since M0 — F10's job is to stand a GATT
server in front of them.

### F10.1 app_ble: implement the service table and payload assembly core

- **blocked-by:** P3.2, F1.6 · **verify:** H · **board:** no
- **design:** [ble-gatt §1, §5](../../protocol/ble-gatt.md), [05 §5.6](../design/05-connectivity-and-provisioning.md), [03 §3.1](../design/03-firmware-architecture.md)

The registry of all nine characteristics with their properties and security levels, payload
builders for every readable/notifiable characteristic assembled from injected state providers
(`smoke_x_ctrl` state, `cook_ring`, `app_net` status, `app_config`, system info), and the write
dispatcher that parses `wifi_scan_ctrl` / `wifi_config` / `device_control` through the generated
unpack functions. Detached probes are the `TEMP_DETACHED` sentinel end to end — **never 0** — the
same invariant F9.3 grep-proofed for JSON. The `soc_pct` degenerate value is whatever P3.2 decided,
emitted from one place.

**Done when:** every builder byte-matches the P3.2/P1.5 fixtures for seeded state, C-encode →
Dart-decode parity passes on shared vectors, and a malformed write (short, bad version handling per
the never-reject-on-ver rule, over-length) is table-tested to a `result{invalid}` rather than a
crash.

### F10.2 app_ble: implement the advertising and scan-response builders

- **blocked-by:** P3.2, F8.3 · **verify:** H · **board:** no
- **design:** [ble-gatt §2](../../protocol/ble-gatt.md), [05 §5.6](../design/05-connectivity-and-provisioning.md)

Pure builders for both PDUs, byte-asserted against the §2 tables: flags + 128-bit service UUID
(21 of 31 bytes) in the advertisement; complete local name + manufacturer blob (29 of 31) in the
scan response. `SmokeBridge-XXXX` reuses F8.3's MAC-suffix helper so the BLE name, AP SSID, and
mDNS TXT `id` can never disagree. The 7-byte status blob (`ver, flags, pit_temp, soc,
session_minutes`) is rebuilt on the same events that feed `live_state`, because a device list
showing *"pit 243 °F · 4 h 12 m"* from a stale blob is worse than none. Interval policy: 500 ms
idle, 250 ms for 60 s after boot or a button press.

**Done when:** both PDUs are byte-identical to the §2 fixtures for a matrix of states (unpaired, in
session, detached pit), the 31-byte budget is asserted at build time, and the interval policy is
table-tested on a fake clock.

### F10.3 app_ble: implement the MTU strategy and notification chunker

- **blocked-by:** F10.1 · **verify:** H · **board:** no
- **design:** [ble-gatt §4](../../protocol/ble-gatt.md)

Request ATT_MTU 247 on connect (`history_preview`'s 244 B + 3 fits one PDU) and implement the one
piece the stack does not do for us: ATT cannot fragment a notification, so `net_status`,
`wifi_scan_result`, and `result` payloads longer than `MTU − 3` are split at that boundary for the
client to concatenate. Reads use standard Read Blob and long writes use Prepare/Execute — stack
behaviour, verified rather than reimplemented. The load-bearing guarantee gets a compile-time
witness: **`live_state` is 16 B and 16 ≤ 20**, so a failed negotiation still carries telemetry.

**Done when:** the chunker is table-tested at MTU 23 and 247 for every variable payload including
the ≤ 10 B fixed-prefix-arrives-whole rule, and a static assert ties `BRIDGE_LIVE_STATE_SIZE` to
the 20-byte default-MTU bound so a future field addition fails the build, not the yard.

### F10.4 app_ble: implement the NimBLE host glue and the ble_push task row

- **blocked-by:** F10.1, F1.4 · **verify:** H · **board:** no
- **design:** [05 §5.6](../design/05-connectivity-and-provisioning.md), [03 §3.3](../design/03-firmware-architecture.md), [01 §1.4](../design/01-hardware.md)

NimBLE init, GAP/GATT registration from the F10.1 table, `CONFIG_BT_NIMBLE_ENABLED` and
`CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y` in the sdkconfig defaults (all three images). Then the
ws_push lesson, applied before the board can teach it again: notification fan-out — subscribe to
the event bus, build payloads, call into NimBLE — runs on its **own `ble_push` row in
`main/tasks.h`**, never on the event-loop or NimBLE host task. Adding that row trips the 28 KB
`_Static_assert` (the table sits ~512 B under the line): **that is the assert doing its job.**
Renegotiate the budget against [01 §1.4](../design/01-hardware.md)'s existing `ble_app 4K`
allowance in the same commit, in the tasks.h comment, as a decision — not a silent bump.

**Done when:** all three images build with NimBLE enabled, the tasks-table host test covers the new
row, the budget change is documented against §1.4, and the core runs against a fake NimBLE ops
layer in the host suite.

### F10.5 app_ble: implement bonding, the security profile, and the passkey display path

- **blocked-by:** F10.4, F11a.5, F7.1, F1.3 · **verify:** H · **board:** no
- **design:** [ble-gatt §3](../../protocol/ble-gatt.md), [05 §5.6](../design/05-connectivity-and-provisioning.md), [03 §3.6](../design/03-firmware-architecture.md)

LE Secure Connections, passkey entry, IO capability **DisplayOnly**: generate the 6-digit passkey,
publish it as a new `BRIDGE_EVT_BLE` event (additive to the bus enum — the guard test grows with
it) so F11a.5 shows the overlay, clear it on bond success, failure, or timeout. Enforce the three
security levels exactly as §3 tables them — `device_info` open, everything else encrypted,
`wifi_config`/`device_control` additionally authenticated, CCCD writes at the characteristic's own
level. Bonds persist via the epic-flag decision, capped at 3 with the fourth attempt rejected;
forget-all works through the 10 s PRG factory reset and `device_control` op 8.

**Done when:** a host test drives the core through pair → bond → reconnect-encrypted → forget, an
unauthenticated write to `wifi_config` is rejected at the security layer (not the handler), the
fourth bond is refused, and the passkey event round-trips into F11a's renderer snapshot in the same
suite.

### F10.6 app_ble: implement the wifi_config write and net_status notify path

- **blocked-by:** F10.1, F8.1, F8.4 · **verify:** H · **board:** no
- **design:** [ble-gatt §5.2, §5.5, §5.9](../../protocol/ble-gatt.md), [05 §5.4, §5.7](../design/05-connectivity-and-provisioning.md)

The provisioning artery. Validate the parsed `wifi_config`, answer on `result` **first**, then hand
off to `app_net_core_apply_later` — the ~500 ms deferred apply F8.4 built for exactly this moment,
so the acknowledgement flushes before the radio it rode on reconfigures. `result.detail` carries
the generated AP PSK on a mode change to AP (the phone needs it to join); **no stored STA
credential is ever emitted on any characteristic** — grep-proof it like F9.7 did. `net_status`
notifies on every `BRIDGE_EVT_NET` transition, because the app watches `connecting → up/failed`
across the §5.7 handoff and a missed transition strands the wizard.

**Done when:** the accept-then-apply ordering is proven on a fake clock, a superseding config wins
inside the window, each net transition produces exactly one correctly-packed notification, and no
code path can emit `sta_psk` bytes.

### F10.7 app_ble: implement the Wi-Fi scan flow

- **blocked-by:** F10.1, F8.3 · **verify:** H · **board:** no
- **design:** [ble-gatt §5.3, §5.4](../../protocol/ble-gatt.md), [05 §5.7](../design/05-connectivity-and-provisioning.md)

`wifi_scan_ctrl` start/cancel; results stream one AP per notification with `index`/`total` so
completion is implicit; a scan already running answers `result{op_echo: 0, status: busy}`. The scan
itself is an injected `app_net` op — the same seam F8.3's channel selection scans through — because
scanning from AP mode is not free on this chip (it needs a temporary APSTA arrangement or a brief
AP gap); the core stays pure and table-tested, and the empirical cost of scanning mid-AP is a named
observation for the bench sitting, not a surprise.

**Done when:** a synthetic 12-AP scan produces 12 correctly-indexed notifications byte-matching the
fixtures, cancel mid-scan stops the stream, the busy path answers without disturbing the running
scan, and an empty scan result (total 0) is handled.

### F10.8 app_ble: implement device_control dispatch and result correlation

- **blocked-by:** F10.1, F3.6, F5.4, F5.9, F6.1 · **verify:** H · **board:** no
- **design:** [ble-gatt §5.6, §5.9](../../protocol/ble-gatt.md), [04 §4.4, §4.6](../design/04-storage-and-history.md)

All eleven ops, each answered on `result` with `op_echo` set, each routed to a component that M1
already proved: `pair`/`unpair` → `smoke_x_ctrl` (unpair touches nothing outside this device —
that invariant is two milestones old); `session_start`/`session_stop` → F5.4's lifecycle with the
same refusal semantics as the REST group; `mark` → F5.9 (UTF-8 truncation lives in the store, the
handler only validates); `set_time` → `app_time` as a `phone` source, which fires `BRIDGE_EVT_TIME`
and F6.2's already-tested header back-patch — the wizard's step 3 is why sessions are dated from
the first sample. `set_units`, `reboot`, `factory_reset` (bonds included) round it out. Two honest
degenerates, noted rather than faked: `identify` wakes the display and flashes what exists (the LED
driver is M5's), and `ack_alarm` mirrors F9.9's accept-and-record until F13 gives it an engine.

**Done when:** every op is table-tested through seeded component doubles to its exact `result`
frame, unknown ops answer `invalid` without side effects, and a `set_time` against a clock-invalid
open session is observed back-patching in the host harness.

### F10.9 app_ble: implement live_state and history_preview serving

- **blocked-by:** F10.1, F10.3, F5.6 · **verify:** H · **board:** no
- **design:** [ble-gatt §5.7, §5.8](../../protocol/ble-gatt.md), [04 §4.3](../design/04-storage-and-history.md)

The telemetry that justifies D1: `live_state` notified on every decoded packet (~30 s) from
`BRIDGE_EVT_SAMPLE`, plus immediately on any `BRIDGE_EVT_ALARM` transition — the subscription is
wired now so F13 changes nothing here in M5. `history_preview` serves the pit probe's last 2 h at
1-minute buckets straight from `cook_ring` — no flash read, ≤ 120 values, 244 B max — enough for a
real sparkline over BLE alone; full history over BLE stays v1.1 and the contract says so.

**Done when:** a replayed fixture stream produces correctly-packed notifications at the sample
cadence, sentinels survive to the wire (never 0), `history_preview` matches a Dart-side decode of
the same seeded ring, and a ring shorter than 2 h yields `count` < 120 rather than padding.

### F10.10 bench: bring up BLE on the board and bond with the passkey on the OLED

- **blocked-by:** F10.2, F10.5, F10.6, F10.7, F10.8, F10.9, F9.13 · **verify:** B · **board:** yes
- **design:** [ble-gatt §2, §3](../../protocol/ble-gatt.md), [01 §1.8](../design/01-hardware.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

Part of the single M3 sitting, and the F track's half of it: the bridge advertises with the correct
scan-response blob (verified with a BLE scanner app against the §2 byte tables); a phone bonds via
the passkey shown on the real OLED — F11a's whole output proving itself in one glance; an
unauthenticated `wifi_config` write from an unbonded central is rejected; bonds survive a reboot;
forget-all clears them. Record the negotiated MTU and any OEM oddity the same way A14.4 recorded
its phone identity.

**Done when:** the bond cycle, security refusal, and persistence checks are recorded in
`docs/hardware-verified.md` with the phone's OEM and Android version.

---

## A6 — BleTransport

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md), R7):** the epic flag on F10
> applies verbatim — and one design-doc line needs a reality check now rather than in a bug report.
> [08 §8.6](../design/08-flutter-app.md) says the passkey is "entered in the app"; on Android the
> passkey dialog for BLE bonding is **owned by the OS**, appears over the app, and varies by OEM.
> The wizard's pair step therefore *instructs and observes* — it shows what the OLED is doing and
> watches bond state — rather than hosting its own six-digit field. Plan A8.2's copy accordingly;
> if some OEM's dialog proves hostile, that is bench evidence for the sitting, not a redesign
> mid-epic.

The third implementation sliding under `BridgeTransport` — which is exactly why the interface
exists. `flutter_blue_plus` is already pinned (A1.3, `^2.3.10` in `app/pubspec.yaml`); the DTO
codecs in `app/lib/data/dto/records.g.dart` mirror `record_gen.h` byte for byte; the behavioural
suite around `MockTransport` (A3.3) and the parity harness already define correct. A6 must not
invent a wire format — it decodes what P3.2's generators emit, the same rule F10 lives under.

### A6.1 data/transport: define the GATT client seam and the fake bridge peripheral

- **blocked-by:** A1.3, P3.2 · **verify:** H · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md), [ble-gatt §1–§5](../../protocol/ble-gatt.md)

`flutter_blue_plus` is a platform plugin, so it hides behind a narrow interface — scan, connect,
bond state, MTU, characteristic read/write/subscribe — exactly as `nsd` did for A7.2. Alongside it,
a fake bridge peripheral implemented in Dart on the generated codecs: it advertises the §2 blob,
walks the bond state machine, enforces the three security levels, serves every characteristic, and
is configurable for the failure modes that matter (MTU negotiation refused → 23, notifications
split at `MTU − 3`, bond rejected, connection dropped mid-write). This fake is to A6 what
`tools/sim` is to A5 — the thing that makes every following task board-free.

**Done when:** the seam's contract test runs against the fake, including the misuse cases (read
before bond on an encrypted characteristic, double connect), and the fake's payloads byte-match the
protocol fixtures.

### A6.2 data/transport: implement BleTransport over the seam

- **blocked-by:** A6.1, A3.3 · **verify:** H · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md), [ble-gatt §5](../../protocol/ble-gatt.md)

The `BridgeTransport` implementation with honest capabilities: `liveState` and `historyPreview`
true, `fullHistory` and `ota` false. `live_state` notifications map to `BridgeEvent.sample`,
`net_status` to `BridgeEvent.net`, `control()` writes `device_control` and correlates the `result`
notify by `op_echo` into completion or a typed failure by `status` — meaning, never magic numbers,
the same rule A5.1 set. `sessions()` and `samples()` answer with the typed unsupported condition
the capability flags promise, and the shared behavioural suite becomes capability-aware so **one
parameterised harness runs Mock, Http, and Ble** and they cannot drift apart unnoticed.

**Done when:** the capability-filtered behavioural suite is green against `BleTransport` over the
fake, every `result.status` value maps to its typed failure, and an unknown notification payload is
dropped with a debug log per the additive-contract rule.

### A6.3 data/transport: implement MTU degradation and notification reassembly

- **blocked-by:** A6.2 · **verify:** H · **board:** no
- **design:** [ble-gatt §4](../../protocol/ble-gatt.md)

The client half of F10.3: request 247, accept whatever arrives, derive chunk boundaries from the
negotiated value. Variable notifications (`net_status`, `wifi_scan_result`, `result`) concatenate
consecutive fragments until the length implied by the fixed prefix — which the contract guarantees
arrives whole in the first chunk — is satisfied. At the default 23, `live_state` must work
untouched; that is the 16 B design surviving contact with the OEM most likely to break negotiation.

**Done when:** the suite passes with the fake pinned to MTU 23 and to 247, a `wifi_scan_result`
split across three notifications reassembles byte-exact, and an interleaved-fragment torture case
either reassembles correctly or fails loudly — never silently corrupts.

### A6.4 data/transport: implement scan, connect, and bond with the status-blob model

- **blocked-by:** A6.1 · **verify:** H · **board:** no
- **design:** [ble-gatt §2.3, §3](../../protocol/ble-gatt.md), [08 §8.6](../design/08-flutter-app.md)

Scan filtered by the service UUID, with the manufacturer blob parsed into a discovery model — pit
temperature, session minutes, flags — so the wizard's find step shows *"Smoke Bridge A4F2 ·
pit 243 °F · 4 h 12 m"* before any connection exists. Bonding drives the seam's bond flow (the OS
owns the dialog — see the epic flag), reconnection to a bonded bridge skips pairing, and a bridge
that was factory-reset since the last bond (our LTK is gone) surfaces as a **typed re-bond-needed
condition**, because "it just won't connect" is the bug report this task exists to prevent.

**Done when:** blob parsing is table-tested including sentinel temperatures and zero-session, the
bond, rebond, and stale-bond paths all pass against the fake, and a malformed advertisement
degrades to a nameless entry instead of failing the scan.

### A6.5 data/transport: fill ConnectionManager's BLE lane

- **blocked-by:** A6.2, A6.4, A7.1 · **verify:** H · **board:** no
- **design:** [08 §8.4](../design/08-flutter-app.md), [05 §5.8.5](../design/05-connectivity-and-provisioning.md)

Replace the honest stub in `app/lib/data/transport/connection_manager.dart` — the slot A7.1 built
the race around so M3 fills a lane, not reworks a flow. The order holds: BLE engages only after
every HTTP lane fails, manual IP still pre-empts everything, and a BLE win hands the caller a
transport whose capabilities honestly say degraded, which is what drives the chart's "full history
needs Wi-Fi" notice. Heed the M2 race-test lesson: fake lane timeouts must be *held*, not
instantly completed, or the deterministic all-lanes-done path races the async probes.

**Done when:** table tests cover BLE winning after HTTP exhaustion, BLE unavailable falling through
to offline-from-cache, manual entry pre-empting a BLE attempt in flight, and the existing A7 suite
staying green unchanged.

### A6.6 app/android: add the BLE manifest rows and update the pinned manifest test

- **blocked-by:** A14.3 · **verify:** H · **board:** no
- **design:** [05 §5.8.3](../design/05-connectivity-and-provisioning.md)

The BLE rows A14.3 explicitly left for M3: `BLUETOOTH_SCAN` with `neverForLocation`,
`BLUETOOTH_CONNECT` (API 31+), and the legacy trio (`BLUETOOTH`, `BLUETOOTH_ADMIN`, the
already-present location grant) gated to API ≤ 30 with `maxSdkVersion`. **A14.3's manifest test
pins the exact current permission set — it must be updated in this same task**, or the suite is red
the moment the rows land; that coupling is deliberate, because it is also what stops a dependency
from quietly adding a location prompt to onboarding.

**Done when:** the build succeeds, `app/test/platform/manifest_test.dart` asserts the new exact set
including both `neverForLocation` attributes and the `maxSdkVersion` gates, and the
foreground-service rows are provably still absent (they are A13's, M5).

### A6.7 bench: prove BleTransport against the board on the real phone

- **blocked-by:** A6.3, A6.4, A6.5, A6.6, F10.10 · **verify:** B · **board:** yes
- **design:** [ble-gatt §2–§5](../../protocol/ble-gatt.md), [08 §8.4](../design/08-flutter-app.md)

Part of the single M3 sitting, and the A track's echo of A14.4: on the real phone, the scan list
shows the blob-decorated entry; bonding completes with the OLED passkey; `live_state` notifications
arrive at the sample cadence with the negotiated MTU logged; a `control()` round-trip
(`set_units`) comes back `ok`; kill Wi-Fi on the phone and watch the ConnectionManager race fall
through to the BLE lane with the degraded-capability notice surfacing. Record OEM, Android version,
and every deviation — this is the evidence the epic flag says to expect needing.

**Done when:** all five checks are in `docs/hardware-verified.md` with the phone's identity, and
any OEM quirk becomes a follow-up task rather than a shrug.

---

## A8 — Onboarding wizard

The deliberate exception to "no Flutter screens before M4"
([§12.6 rule 1](../design/12-task-planning-notes.md)): the exit gate is *a phone provisions the
bridge*, and that cannot be demonstrated from a unit test. The wizard ships with minimal chrome —
M4 restyles, it does not rewire — and its logic lives in a pure state machine the screens merely
project, so the UI debt stays cosmetic.

### A8.1 ui/onboarding: implement the wizard flow as a pure state machine

- **blocked-by:** A6.2, A6.4, A14.1 · **verify:** H · **board:** no
- **design:** [05 §5.7](../design/05-connectivity-and-provisioning.md), [08 §8.6](../design/08-flutter-app.md)

The five §8.6 steps as states — find, pair, time, network, handoff — with every transition,
timeout, and failure edge explicit and clock-injected. Step 3 writes `set_time` silently (sessions
correctly dated from the first sample — F6.2 does the rest); step 4 offers hosted vs joined with
the honest battery/range copy and the device-side scan results; the network step's mode choice
feeds a single `wifi_config` write. Failure edges are first-class states, not error dialogs: bond
rejected, scan empty, config refused, handoff timeout — each has a defined next step, because the
§5.7 choreography's whole point is that there is always a next step.

**Done when:** a table test walks every path through the machine against the A6.1 fake — including
abandon-and-restart at each step — and no state can be entered with a dead BLE link without
surfacing reconnect-or-restart.

### A8.2 ui/onboarding: implement the five screens

- **blocked-by:** A8.1, A1.2 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [05 §5.7](../design/05-connectivity-and-provisioning.md)

Minimal-chrome projections of the state machine: the find list with blob-decorated entries, the
pair step that points at the bridge's OLED and observes the OS bonding dialog (see A6's epic flag —
the app does not host a passkey field), the mode choice, the scan-fed network picker with manual
SSID entry, and the live handoff progress. Screens contain no logic beyond dispatching intents to
A8.1 — that is what keeps M4's restyle cosmetic.

**Done when:** widget tests drive all five screens against the state machine and fake, the pair
screen renders correct copy for both the dialog and no-dialog OEM cases, and a `flutter test` run
touches no platform channel.

### A8.3 ui/onboarding: implement handoff verification and the recovery path

- **blocked-by:** A8.1, A7.1, A14.1, A6.5 · **verify:** S · **board:** no
- **design:** [05 §5.7](../design/05-connectivity-and-provisioning.md), [08 §8.4](../design/08-flutter-app.md)

The exit gate, rehearsed entirely off the board. Watch `net_status` across the transition; on STA
`up`, race HTTP via the ConnectionManager and require a real `/status` 200 before declaring
victory; on AP, take the PSK from `result.detail`, join through A14.1's `joinAp`, bind, and hit
`192.168.4.1`. **HTTP unreachable after 20 s is not failure — it is the recovery state**: BLE is
still connected, so the wizard offers revert-to-hosting (one `wifi_config{mode: AP}` write) or
retry with corrected credentials. The wrong-password path is scripted in the fake (`net_status`
`connecting → failed`) and must land the user back at the network step with the reason stated, not
at a spinner.

**Done when:** an integration test wiring the fake peripheral to a spawned `tools/sim` walks
success, wrong-password → recover → succeed, and unreachable-STA → revert-to-AP, and the 20 s
budget is asserted on a fake clock.

### A8.4 bench: run the M3 exit gate — and close M2's deferred rows

- **blocked-by:** A8.2, A8.3, A6.7, F8.8 · **verify:** B · **board:** yes
- **design:** [05 §5.7](../design/05-connectivity-and-provisioning.md), [M3 outline](M2-M6-outline.md), [hardware-verified](../hardware-verified.md)

Part of the single M3 sitting — its finale. Factory-reset the bridge (10 s PRG hold), then run the
wizard for real: bond via the OLED passkey, **deliberately enter a wrong Wi-Fi password first**,
watch the recovery path land back at the network step over the still-connected BLE link, correct
it, and finish on the **real home network** — closing F8.8's deferred real-credential STA row at
last, in the flow the owner deferred it to. Then, with STA genuinely up: `smokebridge.local` and
`dns-sd -B _smokebridge._tcp` from a LAN machine, closing the mDNS-from-LAN rider. **This is the
whole exit gate, plus M2's two debts, in one sitting.**

**Done when:** the run is recorded in `docs/hardware-verified.md` (including which recovery branch
was exercised and the passkey-dialog behaviour of the phone), the F8.8 and mDNS deferred rows are
closed with pointers to this sitting, and the hardware was never touched between factory reset and
STA-up except to hold PRG at the start.

---

## V3a — Coexistence, deferred from V1.6

### V3a.1 bench: re-measure coexistence and heap with NimBLE live

- **blocked-by:** F10.10, F9.13 · **verify:** B · **board:** yes
- **design:** [01 §1.4, §1.8](../design/01-hardware.md), [ble-gatt §6](../../protocol/ble-gatt.md), [hardware-verified](../hardware-verified.md)

Part of the single M3 sitting, last by design — it needs everything else running. The three V1.6
boxes deferred because "our stack doesn't exist yet" now can't hide: **OLED I²C stable with BLE
active** (error counter over ≥ 10 min, the V1.4 method); **LoRa RX with BLE advertising and a
WebSocket client streaming** (packet cadence unaffected — sub-GHz should be independent of the
2.4 GHz contention, confirmed rather than assumed); and **free heap with AP + NimBLE + httpd +
both LittleFS mounts**, closing F9.13's provisional. Go in with eyes open: M2 measured
`min_free_heap` ~180.7 KB, and subtracting the §1.4 NimBLE allowance of 35–45 KB lands at
136–146 KB — **potentially under the 150 KB target.** If NimBLE comes in at the light end, the box
closes; if not, the milestone caveat applies: that is a design conversation (buffer counts,
concurrency caps, or the target itself) held before M4 — shrinking things ad hoc at the bench is
explicitly not this task.

**Done when:** all three boxes in `docs/hardware-verified.md`'s deferred table are closed with
measured numbers, F9.13's provisional annotation is replaced by the real figure next to the §1.4
budget, and — if the margin is gone — the design conversation is opened as its own recorded
question, not absorbed silently.

---

## What is deliberately _not_ in M3

|                                                     | Why                                                                                                                                                              |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full history over BLE                               | v1.1 ([ble-gatt §5.8](../../protocol/ble-gatt.md)). `history_preview`'s 2 h sparkline is the honest v1.0 story; the chart's capability notice already exists (A3.1) |
| Paged OLED UI, gestures, boot splash, LED, sleep    | M5 (F11b) with the alarm engine. M3's display shows a passkey and is otherwise dark — honest scope, not a stub                                                    |
| Alarm engine                                        | M5 (F13). `ack_alarm` dispatch and the alarm-notify subscription are wired now so F13 changes nothing in `app_ble`                                                |
| Battery truth in `soc_pct`                          | F12 (M5) gates on V1.3's divider facts. The degenerate value is decided once in P3.2, not improvised twice                                                        |
| Bearer-token provisioning over BLE                  | The frozen op table has no `set_token` — the P3 flag decides additive-op-12 vs v1.1, in the contract, before anyone codes it                                      |
| Dashboard, chart, sessions, settings screens        | M4. A8's wizard is the sole, deliberate [§12.6 rule 1](../design/12-task-planning-notes.md) exception — the exit gate is undemonstrable without it                |
| A14.4's binder-alone/shim-alone matrix completion   | Needs M4's screens; recorded partial in [hardware-verified](../hardware-verified.md) and stays an M4 rider                                                        |
| BLE OTA                                             | OTA is HTTP-only, F14 (M6); `device_info.caps` b4 advertises it honestly when it exists                                                                          |
| iOS build or platform code                          | Deferred ([11 §11.2](../design/11-roadmap-and-risks.md))                                                                                                          |
| Multi-bridge picker                                 | D12 — the fake peripheral and `bridges` table stay multi-capable; onboarding a second bridge replaces the first                                                   |
| Wi-Fi join QR on the OLED                           | v1.1 stretch ([§12.7](../design/12-task-planning-notes.md)); `draw_bitmap` waits with it                                                                          |
