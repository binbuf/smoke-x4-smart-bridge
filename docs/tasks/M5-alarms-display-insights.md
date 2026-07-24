# M5 — Alarms, display, insights

**The milestone where the bridge stops needing the phone.** Four milestones have built a device that
records faithfully and answers questions when asked; none of them built one that _tells you
something_. M5 does: `app_alarm` decides, latches, and refuses to cry wolf; `app_ui` finally lights
the panel it has only ever used to show a six-digit passkey; `app_power` turns GPIO37 and a divider
into a number a user can act on; and A13 carries the device's decisions into an Android notification
that survives the app being swiped away.

The through-line is [09 §9.1](../design/09-alarms-and-insights.md)'s two tiers, and it is a
structural claim rather than a layering preference: **the device tier runs with no phone in
existence.** A phone that ran out of battery is not a reason for a $200 brisket to overcook. Every
task below either implements that claim or renders it.

**Exit gate** ([M5 outline](M2-M6-outline.md), [11 §11.1](../design/11-roadmap-and-risks.md)):

- an unattended **overnight** cook wakes the user for `target_reached`
- the bridge alarms correctly **with the phone powered off**
- a **lid-open does not fire a false pit alarm**

34 tasks — **30 `board: no`, 4 `board: yes`**. The four board rows (F13.9, F11b.12, F12.6, A13.7)
are **one bench sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)) at the end, in that
order, because each needs the previous one's output on the glass to be observable. The lanes are
F13 (rules, then surfaces) and F12 (battery) feeding F11b (which renders both), with A13 running
beside them on the app side and joining at the sitting.

> **Read this before writing a line of F13.** The rules live in
> `firmware/components/app_alarm/rules.c` — pure C, no ESP-IDF, host-tested — and **the same rules
> are already implemented in Dart** under `app/lib/domain/analysis/` (A2, M0). `rate_of_change.dart`,
> `stall.dart` and `lid_open.dart` are the reference implementations with the constants already
> argued and table-tested. F13 **projects** them into C; it does not re-derive them, and any
> constant that differs between the two files is a bug in one of them, not a dialect.

---

## Decisions to carry into planning

The design docs settle the rules, the pages and the pin map. They do not settle the following, and
each was decided here rather than improvised at a call site.

### The heap budget for everything M5 adds

[hardware-verified](../hardware-verified.md)'s V3a.1 measured `min_free_heap` ≈ **78.2 KB** against a
150 KB target, stable and leak-free over the window. The working decision recorded there is **option
1 — the target was wrong**: it was set against an estimated NimBLE cost of 35–45 KB
([01 §1.4](../design/01-hardware.md)) and the real cost is ≈ 90–100 KB. M5 does not reopen that, and
it explicitly does **not** trim buffers ad hoc. What it owes instead is an honest budget for its own
additions, stated up front and verified by M6's 24 h soak (V3):

| M5 addition                                              | Heap    | Static (BSS)      | Notes                                                                                                     |
| -------------------------------------------------------- | ------- | ----------------- | --------------------------------------------------------------------------------------------------------- |
| `app_alarm` rule state table (16 slots × 20 B)           | 0       | ~0.4 KB           | Fixed-size array, no allocation on the alarm path — the same rule as the sample path                      |
| `app_alarm` lid-open detector                            | 0       | ~0.1 KB           | Reads `cook_ring` in place; keeps a reference/low-point pair, not a history                               |
| `app_ui` F11b page state, gesture machine, LED patterns  | 0       | ~0.3 KB           | The 1 KB framebuffer already exists (F11a); page renderers are pure functions writing into it             |
| LEDC driver (one channel, GPIO35)                        | ~0.5 KB | —                 | ESP-IDF allocation, not ours                                                                              |
| `app_power` ADC oneshot unit + calibration handle        | ~1 KB   | ~0.1 KB           | `adc_oneshot_new_unit` + the curve-fitting calibration scheme                                             |
| **Total**                                                | **≤ 2 KB** | **≈ 0.9 KB**   | ≈ 2.5 % of the measured 78 KB headroom                                                                    |

**No new task rows.** `app_alarm` (3 KB), `app_ui` (4 KB) and `app_power` (2.5 KB) have been in
`firmware/main/tasks.h` since F1.4 and are already inside `BRIDGE_TASK_STACK_TOTAL`; M5 populates
rows that were budgeted four milestones ago. The 32 KB assert is untouched and
`test_tasks_table.c`'s pinned sum does not move. If a task in this plan appears to need a tenth row,
that is a design conversation, not a bump — the same rule `ble_push` was held to in M3.

One correction rides along: the `app_ui` row's comment reads *"4 Hz button sampling"* and
[07 §7.4](../design/07-display-and-controls.md) specifies **20 ms sampling with a 30 ms debounce**.
25 Hz is what a double-tap window of 400 ms actually needs. The comment is wrong, not the design;
F11b.11 fixes the comment and the task wakes on a 20 ms tick, rendering only when dirty.

### The alarm-rules blob stays device-private; the wire is JSON

`APP_CONFIG_ALARM_RULES` is a 64 B NVS blob, and `handle_config_alarms` currently **echoes it back
verbatim** — a placeholder M2 recorded as provisional. F13 makes both halves real, and the question
is whether the encoding belongs in [`protocol/records.yaml`](../../protocol/records.yaml).

**It does not.** [06 §6.2](../design/06-device-api.md) specifies `/config/alarms` as JSON, and
[ble-gatt](../../protocol/ble-gatt.md) has no alarm-config characteristic at all — nothing outside
the device ever sees the bytes. Putting a private NVS layout into the frozen protocol contract would
oblige three Dart copies to track a device implementation detail. The blob gets a version byte and a
host-tested codec (F13.1); the contract stays JSON.

### `alarm_rule` **is** added to `records.yaml`

The opposite call, for the opposite reason. The nine rule identifiers are spelled today in
`app/lib/features/settings/settings_probes.dart` (`_ruleLabel`), will be spelled again in the C
engine, in `/status`'s `"rule"` field, in the WebSocket `alarm` frame, and in the `.mrk` alarm mark.
That is four spellings of the same closed set across two languages — exactly what D10 and
[10 §10.2](../design/10-repo-tooling-and-testing.md) put a codegen step in the repo to prevent. It
is added as an `enums:` entry, regenerated through `tools/protogen`, and `protogen --check` stays
green with all three Dart copies and the C header updated (F13.2).

### `pit_out_of_band` uses the **configured target**, the base's band drives `smoke_x_alarm`

[09 §9.2](../design/09-alarms-and-insights.md) lists both rules and the distinction is easy to
collapse by accident. `smoke_x_alarm` mirrors *the base station's own* decision — the packet's
`new_alarm` edge, or an `alarm_armed` probe outside the `alarm_low`/`alarm_high` the X4 itself
carries. `pit_out_of_band` is **ours**, evaluated against the pit probe's `p*_target` from
`app_config` ± the configured band. They can disagree, and when they do both are correct: the base is
reporting its settings, we are reporting the user's.

### Alarm identity is `(rule, probe)`; ids are u8, monotonic, never 0

`bridge_evt_alarm_t.alarm_id` is a `uint8_t` and the API's `ack_alarm` carries one. Two alarms of the
same rule on the same probe are **the same alarm** — that is what makes latching meaningful. Ids
allocate monotonically from 1 and wrap to 1 rather than 0, because 0 reads as "no alarm" at three
call sites already.

### `charging` is **inferred**, not sensed

The Heltec V3 exposes no charge-status line ([01 §1.2](../design/01-hardware.md)) and V1.5 has no
current meter, so `/status.power.charging` cannot be read. F12 infers it: the filtered pack voltage
is ≥ 4.15 V, **or** it has risen ≥ 30 mV over the last 10 minutes. Both branches are defensible on a
Li-ion pack under load and neither is certain, so the field is documented as inferred and the bench
row confirms it by plugging USB in and watching the flag. An inferred `true` costs nothing; an
inferred `false` on a charging bridge shows a discharging icon, which is the cheap failure.

### Self-calibration is clamped to ±20 % of ×4.9

V1.3 resolved the ratio to **×4.9** and the gate sense to **GPIO37 HIGH = divider enabled** (inverted
from [01 §1.3](../design/01-hardware.md)'s pseudocode, which drives it LOW — F12 follows the board,
not the doc). It never took a second DMM point, so F12 self-calibrates against the 4.2 V full-charge
plateau. The hazard is obvious: one bad reading writes a permanent wrong ratio into NVS. So the
solver requires a sustained plateau (8 consecutive 30 s samples within ±10 mV while `charging`), and
**refuses any result outside ±20 % of ×4.9**. A pack that would need a ratio of ×2.0 is not a
calibration, it is a different board — and the plan for that is a bench row, not a silent write.

### Battery-saver has two flags: the user's and the automatic

[01 §1.6](../design/01-hardware.md) auto-engages the saver profile below 20 % SoC. If that writes the
same `DEV_BATTERY_SAVER` key the user's toggle writes, then charging back to 30 % silently undoes a
choice the user made deliberately. F12 keeps `DEV_BATTERY_SAVER` as the user's sticky setting and
holds the automatic engagement in RAM; the effective state is the OR of the two, and only the
automatic half releases (at 30 %, hysteresis against a pack hovering at 20 %).

### Quiet hours are evaluated in the **phone's** local time

[09 §9.5](../design/09-alarms-and-insights.md) says 22:00–06:00 without saying whose clock. The
bridge's clock can be `STALE` or absent entirely ([04 §4.4](../design/04-storage-and-history.md)),
and quiet hours exist to protect a sleeping human who is next to the phone. The phone decides. The
device tier has no quiet hours at all — its LED and buzzer are governed by `led_enabled` /
`buzzer_enabled`, which is [07 §7.5](../design/07-display-and-controls.md)'s answer to the same
problem and is already in `app_config`.

### The panel's I²C counters land in `/status`, additively

V3a.1's OLED-error row was deferred to M5/F11b because M3's panel is dark except while a passkey is
showing, so there was no sustained traffic to count errors against, and `app_ui` has no counter.
F11b makes the display always-on and F11b.11 adds `ok`/`err` counters to the panel layer, surfaced as
a new `"display"` object in `GET /api/v1/status` and on the System page. Additive fields are not
breaking ([06 §6.5](../design/06-device-api.md)); this is the cheapest way to make the deferred row
measurable in the **product** image rather than in a bench build.

---

## F13 — `app_alarm`

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the risk in F13 is not the
> arithmetic, it is **the number of ways a correct rule becomes a useless alarm.** [09
> §9.2](../design/09-alarms-and-insights.md) is unusually explicit about this and the outline repeats
> it: _"hysteresis is the feature, not a detail"_. A probe oscillating ±1 °F across its target must
> fire **once** — not once per sample, not once per minute. Every rule in this epic therefore has
> three tests and not one: it fires, it does not re-fire, and it re-arms only after the stated
> condition. A rule with only the first test is not done.
>
> The second flag is the mirror obligation. `rate_of_change.dart`, `stall.dart` and `lid_open.dart`
> are the settled implementations. Any constant that differs between them and `rules.c` is a defect,
> and F13.4 asserts the shared ones against the same fixture rather than trusting two readings of the
> same paragraph.

### F13.1 app_alarm: implement the rule-configuration codec and its defaults

- **blocked-by:** F7.1 · **verify:** H · **board:** no
- **design:** [09 §9.2](../design/09-alarms-and-insights.md), [03 §3.6](../design/03-firmware-architecture.md)

The versioned encoding of `APP_CONFIG_ALARM_RULES`, replacing M2's echo-the-blob placeholder: a
version byte, an enable bit per rule, and the tunables §9.2's table names — the pit band and its
sustain, the crash threshold / slope / sustain, `base_lost` seconds, the two battery percentages, the
storage percentage, and the three hysteresis constants (`target_reached` re-arm margin,
`pit_out_of_band` re-arm window, lid-open grace). Every default is §9.2's, and the whole structure
must fit the 64 B blob with room to grow. Decoding an unknown future version **keeps the fields it
understands and defaults the rest** rather than rejecting the blob, because the alternative is a
firmware downgrade silently disabling every alarm.

**Done when:** host tests round-trip every field, a zero-length blob (never written) decodes to the
full §9.2 defaults, a truncated blob decodes to defaults without reading past the end, a
future-version blob keeps its known prefix, and the encoded size is asserted ≤ 64 B so the cap is a
test rather than a comment.

### F13.2 protocol: add the `alarm_rule` enum to records.yaml and regenerate

- **blocked-by:** P1.4 · **verify:** H · **board:** no
- **design:** [09 §9.2](../design/09-alarms-and-insights.md), [10 §10.2](../design/10-repo-tooling-and-testing.md)

The nine rule identifiers as a generated closed set, for the reason in the decisions section: they
are about to have four spellings across two languages. Add the `enums:` block, run `tools/protogen`,
and commit `protocol/gen/record_gen.h` plus **all three** Dart copies
(`protocol/gen/`, `app/lib/data/dto/`, `tools/bridge_protocol/lib/`). The wire values are the
`/status` strings, so a rule's name is its JSON spelling and its C enumerator is derived from it —
no mapping table anywhere.

**Done when:** `dart run protogen --check` is green with the working tree committed, the C header
carries `bridge_alarm_rule_t` with a name lookup, the Dart copies are byte-identical to each other,
and the app's existing `_ruleLabel` switch is asserted to cover every generated value (a rule the
firmware can raise and the app cannot name is a bug the enum now makes visible).

### F13.3 app_alarm: implement the pure rule evaluator

- **blocked-by:** F13.1, F13.2, F5.6 · **verify:** H · **board:** no
- **design:** [09 §9.2](../design/09-alarms-and-insights.md)

`rules.c` — pure C11, no ESP-IDF, no globals a test cannot reach. One function that takes an input
snapshot (per-probe temperature and attach state, per-probe role and target, the base's own
`alarm_armed`/`alarm_low`/`alarm_high`, the `new_alarm` edge, slopes from `cook_ring`, seconds since
the last packet, battery SoC, free storage percent, coredump-present) plus the decoded config, and
returns the set of conditions that are **true right now**. It decides nothing about latching — that
is F13.4 — which is what keeps it a table-testable function instead of a state machine with inputs.

`pit_crash` and `pit_out_of_band` read their slopes from `cook_ring_slope_f_per_hr()`, which already
returns "no value" for a short or gappy window: **a rule with no slope does not fire**, it abstains.
A detached probe is `TEMP_DETACHED`, never 0, at every comparison.

**Done when:** each of the nine rules has a table test for fires / does-not-fire / abstains-on-bad-
input; `target_reached` is asserted **not** to fire on a `pit`-role probe and `pit_crash` **not** on a
`food`-role one; a detached probe is asserted to produce no temperature-derived condition at all; and
a probe whose target is unset is asserted to be silent rather than treated as target 0.

### F13.4 app_alarm: implement the latching lifecycle, hysteresis, and re-arm

- **blocked-by:** F13.3 · **verify:** H · **board:** no
- **design:** [09 §9.2 Lifecycle](../design/09-alarms-and-insights.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

§9.2's four-state machine over a fixed `(rule, probe)`-keyed table: `condition true → RAISED`,
`ack → ACKED`, `condition false + hysteresis → CLEARED`. **Latched** — a `target_reached` at 02:00
stays raised until someone acknowledges it, even if the probe later cools. **Acknowledging silences,
it does not resolve** — the alarm stays in the list and in `/status` with `acked: true`, and only the
LED and buzzer stop.

This is the task the outline calls the feature. `target_reached` cannot re-raise until the probe
drops 3 °F below target; `pit_out_of_band` needs the pit back inside the band for 5 minutes. Ids are
u8, monotonic from 1, wrapping to 1.

**Done when:** the named regression from [10 §10.5](../design/10-repo-tooling-and-testing.md) passes —
**a probe oscillating ±1 °F across its target for two hours produces exactly one alarm** — and,
alongside it: an acked alarm is asserted to remain listed and unresolved; a cleared alarm re-raises
only after the full re-arm margin; the table saturates gracefully (a 17th distinct alarm is refused
with a log, never overwrites a raised one); and every test is verified to fail against a build with
the hysteresis constants zeroed.

### F13.5 app_alarm: implement lid-open detection and the pit-alarm grace window

- **blocked-by:** F13.4 · **verify:** H · **board:** no
- **design:** [09 §9.2, §9.4](../design/09-alarms-and-insights.md)

The third clause of the exit gate, and the one that decides whether a user keeps the pit alarms
enabled. Detect on a **≥ 25 °F pit drop within any 3-minute window**, and from that instant suppress
`pit_out_of_band` and `pit_crash` for 15 minutes. Confirm afterwards: a recovery of ≥ 50 % of the
drop within 20 minutes was a lid open; no recovery **escalates to `pit_crash`**, which is why firing
on detection is safe rather than merely convenient.

The Dart original is `app/lib/domain/analysis/lid_open.dart` and the C port must agree with it
numerically, not approximately.

**Done when:** a spritz-shaped fixture (25 °F drop, recovery inside 20 min) produces **zero** pit
alarms and one lid-open mark; a dying-fire fixture (same drop, no recovery) produces `pit_crash` at
the 20-minute mark and not before; the grace window is asserted to expire; a second lid open during
an active grace window extends rather than stacks; and the shared constants are asserted equal to
`lid_open.dart`'s by reading the same fixture through both suites.

### F13.6 app_alarm: implement the ESP-IDF glue behind an injected ops seam

- **blocked-by:** F13.5 · **verify:** H · **board:** no
- **design:** [03 §3.1, §3.2](../design/03-firmware-architecture.md), [09 §9.2](../design/09-alarms-and-insights.md)

The thin half: subscribe to `BRIDGE_EVT_SAMPLE`, `BRIDGE_EVT_BASE_LOST`, `BRIDGE_EVT_STORAGE`,
`BRIDGE_EVT_POWER` and `BRIDGE_EVT_SESSION`, run the evaluator on each sample **plus a 10 s tick**
(the time-based rules cannot wait for a packet that is not coming — `base_lost` is precisely the
absence of one), and publish `BRIDGE_EVT_ALARM` on every transition. It occupies the `app_alarm` task
row that has existed since F1.4; it does not add one. Handlers mutate a snapshot and notify the task
— **no rule evaluation on the event loop**, per §3.2's duration guard, which is the lesson `ws_push`
and `ble_push` already paid for.

Every device fact the core cannot know arrives through an ops struct (uptime, coredump-present,
storage free percent, current SoC), so the whole thing is drivable from the host.

**Done when:** the seam is exercised on the host for a sample-driven raise, a tick-driven `base_lost`
raise with no samples at all, an ack arriving from three sources (button, HTTP, BLE) reaching the
same state, and a session end clearing session-scoped alarms while leaving `battery_low` and
`storage_low` — which are properties of the bridge, not of the cook — untouched.

### F13.7 app_alarm: write an alarm mark into the session

- **blocked-by:** F13.6, F5.7 · **verify:** H · **board:** no
- **design:** [09 §9.2](../design/09-alarms-and-insights.md), [04 §4.2](../design/04-storage-and-history.md)

Each raise writes a `mark_rec` of **kind 5 (`alarm`)** to the session's `.mrk`, carrying the probe and
a text naming the rule and the trigger value, so the graph shows where it happened — in the app, in a
CSV export, and in the session detail's mark timeline, all of which already render kind 5 (A11.3).
Lid-open detection writes **kind 2 (`lid_open`)** as §9.4's auto-mark. Marks are written from the
`app_alarm` task, never from a handler, and a session that is not open drops the mark rather than
opening one.

**Done when:** a raise with a session open is asserted to append exactly one kind-5 mark with the
rule name in its text, a raise with no session open writes nothing and does not error, marks survive
the §4.5 recovery ladder, and an alarm raised twice across a clear/re-arm cycle writes two marks
(because it happened twice).

### F13.8 app_api / app_ble: surface alarm state on every transport

- **blocked-by:** F13.6 · **verify:** H · **board:** no
- **design:** [06 §6.2, §6.3](../design/06-device-api.md), [ble-gatt §5.1](../../protocol/ble-gatt.md)

Four surfaces that are all currently honest placeholders, made real in one task because they are one
seam: `GET /api/v1/status`'s `"alarms": []` becomes the live list in §6.2's exact shape; the
WebSocket emits §6.3's `alarm` frame on every transition; `{"type":"ack_alarm","id":N}` and BLE
`device_control` op 11 both route to the engine (the M2 code comment *"ack_alarm routing lands with
the alarm engine (M5 F13)"* is the task); and `live_state.alarm_active` stops being a hardcoded
`false`.

**This is the `/status.ble` lesson, applied before the board can teach it again.** A
shape-complete placeholder that outlives its milestone reports a lost pairing or a silent alarm, and
[hardware-verified](../hardware-verified.md) records what that cost. `GET /config/alarms` also stops
echoing the raw blob and returns F13.1's decoded JSON, with `POST` validating rather than storing
whatever it is handed.

**Done when:** the `/status` alarm array is asserted against the §6.2 fixture including the empty
case; an ack over each of the three paths flips `acked` and is idempotent; an unknown alarm id is
refused rather than ignored; `POST /config/alarms` with an out-of-range band returns `400
invalid_field` and leaves the stored config unchanged; and `live_state.alarm_active` is asserted true
only while an **unacked** alarm exists.

### F13.9 bench: prove the device tier with the phone powered off

- **blocked-by:** F13.8, F11b.12 · **verify:** B · **board:** yes
- **design:** [09 §9.1](../design/09-alarms-and-insights.md), [hardware-verified](../hardware-verified.md)

Two of the three exit-gate clauses, and the one that cannot be simulated. With the phone **powered
off** — not backgrounded, not disconnected, off — drive a probe across its target and confirm the
bridge raises, latches, lights the LED, shows the §7.3 alarm overlay, and still reports the alarm as
raised-and-unacknowledged when the phone comes back. Then open the lid on a live pit and confirm **no
pit alarm fires**, and that a lid-open mark appears in the session.

**Done when:** both clauses are recorded in `docs/hardware-verified.md` with the observed timings, the
session file carrying the kind-5 and kind-2 marks is committed as evidence, and anything that fired
when it should not have is a named row rather than an omission.

---

## F11b — `app_ui`, the remainder

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** §12.8 flags F11 as pixel work —
> _"a 12×24 font table, a sparkline, inverted regions, an 8-row layout at 21 columns"_ — and its
> suggested handling was to build the framebuffer→PNG harness first. **That is already done**: F11a
> shipped the primitives, both fonts, the `.fb` goldens and `tools/oled`, so F11b inherits the
> iteration loop rather than paying for it. What is left is the part the harness cannot judge: **21
> columns is not many.** `NETWORK   connecting` is 20. A probe named `Chuck roast` beside
> `163°F  +4.1` does not fit. Every page renderer therefore truncates deliberately and the golden
> pins the truncation, because the alternative — discovering it on a panel in a dark yard — is what
> A15.5-1 already cost the app side once.
>
> The second flag is the gesture machine. [07 §7.4](../design/07-display-and-controls.md) specifies
> **commit-on-release, not on threshold**, and **a wake press is consumed**. Both are behavioural
> claims with exact tests, and both are the difference between a one-button UI that is tolerable and
> one that takes your bridge off the network from inside a pocket.

### F11b.1 app_ui: grow the snapshot struct and render the status strip

- **blocked-by:** F11a.4 · **verify:** H · **board:** no
- **design:** [07 §7.1](../design/07-display-and-controls.md)

`app_ui_state_t` grows from M3's two passkey fields to the whole set the five pages read — probes
(name, value, attach state, role, target, slope), session (id, name, elapsed, sample and mark
counts), network (mode, ssid, psk, ip, rssi, client count), radio (paired, device id, frequency, rssi,
snr, last-packet age, ok/bad counts, mean interval), power (mV, SoC, charging, saver), system
(version, uptime, storage, heap), and alarm state. It stays **POD and comparable**, because
`app_ui_panel_render()`'s "push only if changed" contract is a `memcmp` and the whole
render-only-when-dirty policy rests on it.

Then row 7 on **every page and every overlay**, which is the deviation F11a deliberately recorded and
promised to close here: `●sta  04:12  71%  ⚠` — filled dot for a packet within 60 s, mode with `ap*`
when a client is associated, elapsed or `--:--`, SoC or `USB`, and the warning glyph only while an
alarm is unacknowledged.

**Done when:** the strip is golden-pinned in all five of its interesting shapes (base lost, AP with a
client, no session, charging, unacked alarm); the passkey overlay's committed golden is **regenerated
with the strip present** and the change is called out as the promised closure rather than drift; and
the struct is asserted to contain no pointers, so comparing two snapshots compares their content.

### F11b.2 app_ui: add the remaining §7.6 primitives — sparkline and progress

- **blocked-by:** F11a.1 · **verify:** H · **board:** no
- **design:** [07 §7.6](../design/07-display-and-controls.md)

`draw_sparkline(x, y, w, h, vals, n)` and `draw_progress(x, y, w, h, pct)`, completing the list §7.6
names. The sparkline auto-scales to its own min/max, renders a flat line rather than dividing by zero
when they are equal, **skips detached samples instead of plotting them as the bottom of the range**,
and handles more samples than pixels (the 240-sample ring into 21 columns) by bucketing rather than
by dropping the tail.

**Done when:** pixel-asserted for a rising ramp, a flat series, a series with a detached hole, a
single sample, zero samples, and a series longer than the width; the progress bar is asserted at 0 %,
100 %, and a fractional pixel; and every call clips silently at the buffer edge like every other
primitive.

### F11b.3 app_ui: render page 1 — Probes

- **blocked-by:** F11b.1 · **verify:** H · **board:** no
- **design:** [07 §7.2](../design/07-display-and-controls.md)

The default page and the one that has to work at four feet in the dark: the `pit`-role probe's
temperature in the 12×24 font with a trend arrow, its name and alarm band above, and the other three
probes as name / value / °F-hr rows. **Detached probes render `---`, never a temperature** — §7.2 is
explicit that the reference's `0.0` is a real trap, and it is the same invariant the app has enforced
end to end since M0. Trend arrows are §7.2's thresholds: `▲` above +5 °F/hr, `▼` below −5, `–`
between. If no probe carries the `pit` role, probe 1 gets the large treatment.

The displayed unit follows `DEV_UNITS`; storage stays canonical °F
([04 §4.2](../design/04-storage-and-history.md)).

**Done when:** goldens cover four attached probes, all detached, no pit role, a probe with no target,
a °C render of the same state, and a name long enough to need truncation; and the all-detached golden
is asserted to contain **no digit** in any temperature slot, the same way A15.2 asserts it on the
phone.

### F11b.4 app_ui: render page 2 — Cook

- **blocked-by:** F11b.2, F11b.3 · **verify:** H · **board:** no
- **design:** [07 §7.2](../design/07-display-and-controls.md), [04 §4.3](../design/04-storage-and-history.md)

Session name and number, elapsed, the primary food probe's current → target, ETA with its stall
annotation, the **2-hour pit sparkline over the RAM ring**, and the mark/sample counts. This is where
_"did the fire hold overnight?"_ gets answered without unlocking a phone, which is the whole
justification for the sparkline existing on a 128×64 panel.

ETA is the device's cheap version and it says so: with no session, fewer than 30 minutes of history,
or a slope under 1 °F/hr it renders `--` rather than a number. **The app tier owns the real ETA**
([09 §9.4](../design/09-alarms-and-insights.md)'s two models and its range presentation); the device
never renders a confident wrong answer.

**Done when:** goldens cover an active cook with a full ring, a session under 30 minutes old, no
session at all, a stalled probe, and a ring with a dropout in it; and the sparkline is asserted to
plot from the ring rather than from flash (no `cook_store` read on the render path, asserted through
the fake).

### F11b.5 app_ui: render pages 3, 4 and 5 — Network, Radio, System

- **blocked-by:** F11b.1 · **verify:** H · **board:** no
- **design:** [07 §7.2](../design/07-display-and-controls.md)

The three information pages, together because they are one rendering technique with three payloads.
**Network** answers the brief's second question and renders differently per mode: hosting shows SSID
**and password** and the URL and the client count — everything needed to join, on the glass, with no
app and no manual; joined shows SSID, a signal bar, IP, hostname and the BLE link count; connecting
shows the attempt number and the retry countdown. **Radio** shows the pairing state, frequency, RSSI/
SNR, last-packet age, ok/bad counts and the **mean inter-packet interval** — which is on the glass
because it is the cheapest possible field test of [02 Q1](../design/02-smoke-x-protocol.md), and
becomes the scanning screen when unpaired. **System** shows version, battery, uptime, storage, heap —
and the F11b.11 I²C counters, which is where V3a.1's deferred row becomes readable without a serial
cable.

Per [D11](../design/00-overview.md), Billows state is decoded and stored and **not** displayed.

**Done when:** goldens cover all three network modes, paired and unpaired radio, and System with and
without battery data; the AP password is asserted present on the hosting golden (it is the one thing
that page exists for); and every string that can exceed 21 columns has a truncation golden.

### F11b.6 app_ui: render the alarm, confirm-countdown and splash overlays

- **blocked-by:** F11b.1, F13.4 · **verify:** H · **board:** no
- **design:** [07 §7.3](../design/07-display-and-controls.md)

Three transient screens that pre-empt whatever page is showing. The **alarm** overlay is inverted
video so it reads across a dark yard — F11a's `app_ui_invert_region` exists for exactly this — naming
the probe, the value and the rule, and it persists until acknowledged **or 60 s, after which the page
reverts but the LED keeps signalling and the alarm stays unacknowledged in the API**. Silencing the
screen is not the same as dealing with it, and the overlay's timeout must not touch alarm state.

The **confirm countdown** backs every hold action with `release to cancel`; the **boot splash** shows
the version, the 3-second recovery window, and the antenna warning
([01 §1.5](../design/01-hardware.md)).

**Done when:** goldens cover the alarm overlay for each severity and for a long probe name, the
countdown at 3/2/1, and the splash; the 60 s revert is asserted to leave the alarm raised and unacked;
and an alarm arriving while a countdown is showing is asserted to win (an alarm outranks a
confirmation, always).

### F11b.7 app_ui: implement the button gesture machine

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [07 §7.4](../design/07-display-and-controls.md)

§7.4's state machine as a pure function of (level, timestamp): 20 ms sampling, 30 ms debounce, and the
`IDLE → PRESSED → TAP_WAIT → DOUBLE_TAP` / `HOLD_CONFIRM → FACTORY_ARM` transitions. Tap under
400 ms, double-tap within 400 ms of the first, hold at 2 s, factory-reset arm at 10 s.

Two properties are the whole point and each gets its own test: **hold actions commit on release, not
on reaching the threshold** — let go early and nothing happens — and **a wake press is consumed**, so
waking a sleeping display never also changes the page. The output vocabulary is
`UI_INPUT_BACK/NEXT/SELECT` per [D3](../design/00-overview.md), so the three-button variant is a
driver and a Kconfig flag rather than a UI rewrite.

**Done when:** the machine is table-tested against synthesised level/time traces for tap,
double-tap, hold-released-early (nothing happens), hold-released-after-2 s (commits), the 10 s
factory arm, a 25 ms bounce burst (debounced to nothing), a press held across a wake, and a press
that never releases; and no test needs a GPIO.

### F11b.8 app_ui: implement the page and context-action model

- **blocked-by:** F11b.3, F11b.4, F11b.5, F11b.7 · **verify:** H · **board:** no
- **design:** [07 §7.2, §7.4](../design/07-display-and-controls.md)

What the gestures mean once they arrive: tap advances the page and wraps; the current page persists
across sleep, **resets to page 1 on boot and whenever an alarm fires**; a tap on an alarm overlay
acknowledges it; double-tap adds a `Mark N`; and hold-2 s runs the **current page's** context action
behind a confirm — unit toggle, session start/stop, AP↔STA switch, unpair/re-scan, saver toggle.

That the mode switch is a context action on the Network page rather than a global toggle is
[07](../design/07-display-and-controls.md)'s answer to the brief's first question, and the reason is
worth keeping in the code: the screen already shows what you are switching **from** and **to**, and a
blind global long-press is one pocket-press away from taking a bridge off the network 12 hours into a
cook.

**Done when:** a table test walks every (page × gesture) pair and asserts the action, including the
five hold actions and the pages where a gesture does nothing; an alarm is asserted to force page 1 and
to consume the acknowledging tap; a hold released before its threshold is asserted to perform **no**
action on any page; and the factory-reset path is asserted to require all three `KEEP HOLDING`
confirmations.

### F11b.9 app_ui: implement the sleep and wake policy

- **blocked-by:** F11b.8 · **verify:** H · **board:** no
- **design:** [07 §7.1](../design/07-display-and-controls.md), [01 §1.6](../design/01-hardware.md)

Sleep after `display_timeout_s` (default 60 s) → panel off (`0xAE`), render task idle; wake on any
button, any alarm, session start/end, network state change, or BLE connect. **The cheapest single item
in the power budget** — ~10 mA, and it is what lets an AP-mode bridge get anywhere near a 24 h cook
([01 §1.6](../design/01-hardware.md)); F12's saver profile shortens the timeout to 30 s.

**Done when:** the policy is table-tested for each wake source, for a timeout of 0 (never sleeps) as
the documented always-on setting, for an alarm raised while asleep (wakes, and the overlay is what
appears), for the wake press being consumed exactly once, and for a sleeping panel doing **zero** I²C
transfers — asserted through the seam's counter, because "the display is off" and "the driver stopped
talking to it" are different claims and only the second one saves current.

### F11b.10 app_ui: implement the LED pattern engine and the buzzer mirror

- **blocked-by:** F11b.1 · **verify:** H · **board:** no
- **design:** [07 §7.5](../design/07-display-and-controls.md)

§7.5's pattern table as a pure function of (state, time) → duty cycle: 2 Hz blink for an unacked
alarm, solid while pairing, double-blink every 2 s for base-lost, slow breathe during OTA, a 20 ms
per-packet heartbeat (off by default), and the 5 s rapid flash for `identify`. Governed by
`led_enabled`, whose default is `alarms_only`, because a light blinking all night on a bedside bridge
is a reason to unplug it. The piezo on GPIO7 mirrors the alarm pattern when `buzzer_enabled` — the
code is present and a **no-op when unfitted**, which is the state of every board we have.

**Done when:** each pattern is asserted at sampled instants across two full periods (a blink asserted
at one instant is not a blink); precedence is asserted when several conditions are true at once
(alarm outranks base-lost outranks heartbeat); `led_enabled = off` is asserted to produce a zero duty
cycle in **every** state including alarm; and `identify` is asserted to return to the prior pattern
after 5 s rather than latching.

### F11b.11 app_ui: implement the ESP-IDF glue — button, LED, and the panel's I²C counters

- **blocked-by:** F11b.9, F11b.10 · **verify:** H · **board:** no
- **design:** [07 §7.1, §7.4, §7.5](../design/07-display-and-controls.md), [hardware-verified V3a.1](../hardware-verified.md)

The part that can only be proven on the board, kept as thin as the panel layer already is: GPIO0
sampled on a 20 ms tick (correcting the `tasks.h` comment, per the decisions section), the LED on
GPIO35 under LEDC, subscriptions to every event the snapshot reads, and the dirty-render loop that
replaces the reference's unconditional 1 Hz full redraw.

It also adds **`ok` / `err` counters to `app_ui_panel`**, surfaced through the System page and a new
additive `"display"` object in `GET /api/v1/status`. That is V3a.1's deferred OLED-error row becoming
measurable in the product image — M3 could not close it because the panel was dark, and F11b.12 is
where the number finally gets read.

**Done when:** the button seam is host-driven end to end (level trace → gesture → action → snapshot
change) with no GPIO; the LED duty is asserted through a fake LEDC op; the I²C counters are asserted
to increment on transfer and on failure separately; a panel failure at bring-up is asserted to leave
the bridge **cooking headless** rather than failing the boot ([03 §3.4](../design/03-firmware-architecture.md));
and both images build.

### F11b.12 bench: the five pages, the gestures, and the I²C error count on the real panel

- **blocked-by:** F11b.11, F12.5 · **verify:** B · **board:** yes
- **design:** [07](../design/07-display-and-controls.md), [hardware-verified](../hardware-verified.md)

The first row of the sitting, because everything after it is easier to observe once the glass works.
Walk all five pages with the button, run each context action to its confirm and cancel it, run one to
completion, verify the sparkline against the app's chart for the same window, and let the panel sleep
and wake. Then leave the display on with BLE active for ≥ 10 minutes and read the I²C `ok`/`err`
counters — **the V1.4 method, on the product image**, closing the row M3 recorded as not measurable.

**Done when:** every page is photographed or transcribed into `docs/hardware-verified.md`, the
gesture set is confirmed including a hold released early doing nothing, the I²C error count is
recorded as a number against a transfer count, and any layout that is unreadable at arm's length is a
named follow-up rather than a shrug.

---

## F12 — `app_power`

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** F12 was gated on V1.3 and
> **V1.3 resolved it** — ×4.9, and GPIO37 **HIGH** enables the divider, which is *inverted* from
> [01 §1.3](../design/01-hardware.md)'s own pseudocode. The remaining uncertainty is narrower and
> sharper: **there is only one calibration point.** V1.3 read 788 mV of ADC with the pack at roughly
> mid-charge and inferred ×4.9 from Li-ion range arithmetic rather than from a DMM, and the second
> point was never taken. So the ratio is *probably* right and *definitely* unverified at a second
> voltage, which is why F12.2 self-calibrates against the 4.2 V plateau and why F12.1's SoC curve
> must degrade honestly rather than confidently.
>
> The consequence to design for: **`soc_pct` has a real sentinel** (`SOC_UNKNOWN = 255`, decided in
> P3.2) and every consumer already renders its absence. A wrong percentage is worse than no
> percentage, and the app has been rendering `battery n/a` correctly since M4.

### F12.1 app_power: implement the pure voltage → SoC core

- **blocked-by:** F7.1 · **verify:** H · **board:** no
- **design:** [01 §1.3](../design/01-hardware.md), [hardware-verified V1.3](../hardware-verified.md)

Pure C11: raw ADC millivolts in, filtered pack millivolts and state of charge out. The divider ratio
comes from `vbat_cal_num`/`vbat_cal_den` in NVS, defaulting to **×4.9**; the filter is an EMA sized so
a Wi-Fi TX burst does not move the displayed percentage; and SoC is a **lookup against a Li-ion
discharge curve, not a linear map** — §1.3 is explicit that a linear map reads "50 %" for most of the
cook and then falls off a cliff. Below the curve's floor and above its ceiling the answer clamps, and
a reading of 0 mV (which is what a *disabled* divider produces — V1.3's inverted gate makes this the
likely wiring bug) returns **`SOC_UNKNOWN`**, never 0 %.

**Done when:** the curve is table-tested at ten voltages including both ends and both clamps, a 0 mV
reading is asserted to produce `SOC_UNKNOWN` rather than a flat battery, the EMA is asserted to
converge and to be monotonic under a monotonic input, and a stored calibration is asserted to change
the result exactly as the ratio predicts.

### F12.2 app_power: implement plateau self-calibration and the charging inference

- **blocked-by:** F12.1 · **verify:** H · **board:** no
- **design:** [01 §1.3](../design/01-hardware.md), [hardware-verified V1.3](../hardware-verified.md)

The answer to the missing second DMM point. While `charging` is inferred true and the filtered reading
holds a plateau — 8 consecutive 30 s samples within ±10 mV — the true pack voltage is 4.2 V, which
solves for the ratio; the result is written to `vbat_cal_num`/`vbat_cal_den` **only if it lands within
±20 % of ×4.9**. Anything further away is not a calibration and is logged and discarded, because one
bad write is permanent and silent.

`charging` itself is inferred (see the decisions section): filtered voltage ≥ 4.15 V, or a rise of
≥ 30 mV over 10 minutes. §1.3's one-point `POST /api/v1/config/device {"vbat_actual_mv": 4020}`
command stays as the manual override and takes precedence over anything the plateau solver decided.

**Done when:** a synthetic charge curve is asserted to converge on the correct ratio and to stop
adjusting once converged; a noisy plateau is asserted **not** to trigger; a solver result implying
×2.0 is asserted to be refused and logged; the manual command is asserted to overwrite a
self-calibrated value and not vice versa; and the charging inference is table-tested at the two
boundaries and for a discharging pack that briefly rises.

### F12.3 app_power: implement the battery-saver profile

- **blocked-by:** F12.1 · **verify:** H · **board:** no
- **design:** [01 §1.6](../design/01-hardware.md), [07 §7.2](../design/07-display-and-controls.md)

§1.6's profile — CPU 160 MHz, OLED timeout 30 s, BLE advertising interval 2 s, WebSocket push
throttled — as a pure decision function plus the ops that apply it. Auto-engages below **20 %** SoC
and releases at **30 %**, and per the decisions section it keeps the automatic engagement separate
from the user's sticky `DEV_BATTERY_SAVER`, so charging back up never silently undoes a deliberate
choice. `SOC_UNKNOWN` never engages the saver — an unknown battery is not a low one.

**Done when:** the hysteresis is asserted against a pack oscillating across 20 % (engages once), the
user's setting is asserted to survive an auto-engage/auto-release cycle, `SOC_UNKNOWN` is asserted
inert, and each applied setting is asserted to reach its op exactly once per transition rather than on
every sample.

### F12.4 app_power: implement the ESP-IDF glue behind an injected ADC seam

- **blocked-by:** F12.2, F12.3 · **verify:** H · **board:** no
- **design:** [01 §1.3](../design/01-hardware.md), [03 §3.1](../design/03-firmware-architecture.md)

ADC1 channel 0 on GPIO1 through `adc_oneshot` with the calibration scheme, oversampled ~64 times,
**gated by driving GPIO37 HIGH** — V1.3's inverted sense, which is stated in exactly one place in the
firmware and asserted in exactly one test, the same way `app_ui`'s Vext polarity lives only in
`op_vext_power`. Sampled every 30 s on the existing `app_power` task row, publishing
`BRIDGE_EVT_POWER` on change. ADC2 is unusable while Wi-Fi is active ([01 §1.2](../design/01-hardware.md));
nothing here touches it.

**Done when:** the seam asserts the gate is driven HIGH before the read and released after; a read
with the gate never asserted is asserted to produce `SOC_UNKNOWN` rather than 0 %; the 30 s cadence and
the change-only publication are asserted through a fake clock; and both images build.

### F12.5 app_api / app_ble: surface power on every transport

- **blocked-by:** F12.4 · **verify:** H · **board:** no
- **design:** [06 §6.2, §6.3](../design/06-device-api.md), [ble-gatt §5.1.1](../../protocol/ble-gatt.md)

`GET /api/v1/status`'s `"power"` object — hardcoded to `{"mv":null,"soc_pct":null,...}` since M2 —
becomes real; the WebSocket emits §6.3's `power` frame; `live_state.soc_pct` and the advertising
blob's `soc` carry a real value instead of `SOC_UNKNOWN`; and **`device_info.caps` b5 `battery` flips
to true**, which is the bit P3.2 added precisely so the app could tell "no battery data yet" from "a
flat battery". `POST /config/device` gains `vbat_actual_mv` and `battery_saver`.

**Done when:** `/status.power` is asserted against the §6.2 fixture with real values and with
`SOC_UNKNOWN`; `caps` b5 is asserted to follow whether `app_power` initialised rather than being a
literal; the app's `battery n/a` path is asserted to still render for a bridge reporting
`SOC_UNKNOWN`; and the calibration `POST` is asserted to validate its argument.

### F12.6 bench: battery on the board — gate sense, ratio, saver

- **blocked-by:** F12.5 · **verify:** B · **board:** yes
- **design:** [01 §1.3, §1.6](../design/01-hardware.md), [hardware-verified V1.3, V1.5](../hardware-verified.md)

Confirm the divider gate in the **product** image (V1.3 proved it in the bench image), read SoC on
battery and on USB, watch the charging inference flip when the cable goes in, and let the pack fall
far enough to see the saver engage — or, if that is impractical in one sitting, force the threshold
and confirm the profile applies and releases. V1.3's missing second calibration point closes here if
a DMM is available; if not, the plateau solver's result is recorded as the second point and said to
be exactly that.

**Done when:** the V1.3 rows in `docs/hardware-verified.md` gain a measured second point or an
explicit statement that the plateau solver stands in for one, the charging inference is recorded as
observed or corrected, and V1.5's deferred brownout question is either answered or re-deferred **with
a reason** rather than left blank.

---

## A13 — Foreground service, notifications, quiet hours

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** A13's risk is the one §9.6
> names outright — **several OEM Android builds kill long-running foreground services regardless of
> type.** That is not fixable in Dart, and pretending otherwise is how this epic overruns. The design
> already contains the mitigation and, more usefully, the fallback: the opt-in
> `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt, and a degraded mode that is honestly described as
> _"reconnects and catches up when you open it"_ — which still works, because sync is delta-based and
> **the device never stopped recording**. Build the degraded path first and the happy path second.
>
> The second flag is testability. `flutter_foreground_task`'s handler runs in a separate isolate
> behind platform channels, and `flutter test` has neither. So the **policy is pure Dart** and the
> plugin sits behind a narrow seam with an in-memory fake — the same shape A7.4 gave `nsd` and A14
> gave the network binder, for the same reason. A13's host tests prove the decisions; the sitting
> proves the plumbing.
>
> And the trap A12.2 already wrote down: **the two tiers are not interchangeable.** A notification
> screen that lists device rules beside app rules implies the phone can be switched off. It cannot —
> that is what the *bridge* is for, and the copy must keep saying so.

### A13.1 domain/alarms: implement the notification policy as a pure function

- **blocked-by:** A2.1 · **verify:** H · **board:** no
- **design:** [09 §9.5](../design/09-alarms-and-insights.md)

Given the device's alarm list, the app-tier findings, the quiet-hours setting and the wall clock,
decide **what to post, on which channel, and whether it makes a sound** — with no plugin, no
`BuildContext` and no clock of its own. §9.5's four channels (`critical` HIGH with full-screen intent
and opt-in DND bypass, `warning` DEFAULT, `info` LOW, `ongoing` MIN) and its quiet-hours rule:
warnings and info go silent between 22:00 and 06:00, **critical still sounds**, because overcooking a
brisket at 3 a.m. is precisely the thing worth waking up for.

The policy is also where **latching is mirrored, not re-decided**: an alarm the device reports as
raised-and-unacked at 07:00 must produce a notification even though it fired at 03:40 while the phone
was face-down, and it must not produce a second one every time `/status` is polled.

**Done when:** table-tested for each severity inside and outside quiet hours, for a midnight-spanning
window, for an alarm already notified (no duplicate), for one acked on the device (withdrawn), for one
that fired while the app was dead (posted once on reconnect), and for quiet hours disabled entirely;
and the function is asserted to read the clock only through its argument.

### A13.2 platform/notifications: implement the channels and the delivery seam

- **blocked-by:** A13.1 · **verify:** H · **board:** no
- **design:** [09 §9.5](../design/09-alarms-and-insights.md), [08 §8.2](../design/08-flutter-app.md)

`flutter_local_notifications` behind a `NotificationSink` interface — post, update, cancel — with a
`shared_preferences`-free in-memory implementation for tests and the real one registered at bootstrap.
Channel creation is idempotent and happens once; **channel importance cannot be changed after
creation on Android**, which is a real constraint and the reason the four channels are created up
front with the right importances rather than lazily with defaults.

`POST_NOTIFICATIONS` (API 33+) is requested at the moment the first cook starts, not at launch — a
permission prompt on first open, before the user has seen anything work, is the classic way to get it
denied permanently.

**Done when:** the four channels are asserted created with §9.5's importances and no duplicates on a
second bootstrap; a denied permission is asserted to degrade to in-app surfacing rather than throwing;
the sink's fake records posts, updates and cancels in order; and `flutter test` touches no platform
channel.

### A13.3 features/monitor: implement the service's reconciliation loop

- **blocked-by:** A13.2, A9.5 · **verify:** H · **board:** no
- **design:** [09 §9.6](../design/09-alarms-and-insights.md), [08 §8.5](../design/08-flutter-app.md)

§9.6's service-isolate half, as a plain Dart class with the transport, the database and the sink
injected: hold the connection, **write every received sample straight to drift** so history survives
the app being swiped away, reconcile the device's alarm list against what has already been notified,
and run the app-tier rules over the cached history. Reconnect on A7.3's existing backoff ladder with
an immediate retry on connectivity change, and raise the `bridge_unreachable` warning after 3 minutes
of no data during an active cook.

Everything it calls exists: `SyncEngine`, `SampleDao`, `rateOfChange`, `eta`, `StallDetector`,
`LidOpenDetector`. This task wires them into a loop that survives the UI being gone; it does not
invent analysis.

**Done when:** the loop is driven against `MockTransport` for a clean run, a mid-cook disconnect and
reconnect (asserting no duplicate notifications and no lost samples), a bridge that never comes back
(`bridge_unreachable` once, not per retry), an alarm raised while disconnected and discovered on
reconnect, and a session ending; and every sample received is asserted present in drift afterwards.

### A13.4 features/monitor: implement the ongoing notification readout

- **blocked-by:** A13.3 · **verify:** H · **board:** no
- **design:** [09 §9.5](../design/09-alarms-and-insights.md)

§9.5's live readout, updated every 30 s: session name and elapsed, pit and food temperatures with
trend arrows, the ETA range and stall state, and the two actions — `Add mark` and `Stop cook`. It is
built from the **same** `DashboardSnapshot` projection the dashboard renders (A9.1), because two
sources of truth for "what is the pit doing" is how a notification ends up disagreeing with the screen
behind it.

Detached probes render `—`, a session with no clock renders elapsed rather than an epoch date, and an
unknown battery renders nothing at all — the same three invariants the dashboard has enforced since
M4.

**Done when:** the readout string is table-tested from a seeded snapshot for a normal cook, an
all-detached cook, a stalled probe with ETA suppressed, no session, and a 15-hour elapsed time; the
two actions are asserted to dispatch exactly one `ControlCommand` each; and the update cadence is
asserted to be 30 s rather than per-sample.

### A13.5 features/monitor: implement the service lifecycle and the battery-optimisation opt-in

- **blocked-by:** A13.4 · **verify:** H · **board:** no
- **design:** [09 §9.6](../design/09-alarms-and-insights.md)

§9.6's start/stop rules behind the same seam: start when a cook session becomes active and monitoring
is enabled, type `connectedDevice` (required from Android 14), stop on session end, on user stop, or
10 minutes after the last successful connection with no session active. Then the practical hazard —
after the **first** cook starts, offer a one-tap `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` with a plain
explanation, **opt-in**, and accept a decline gracefully: the app degrades to "reconnects and catches
up when you open it", which still works.

The manifest gains `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS`
and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, and `test/platform/manifest_test.dart`'s exact-permission
list grows to match — that list exists so a dependency cannot quietly add a location prompt, and it
only works if it is maintained deliberately.

**Done when:** the lifecycle is table-tested for each start and stop trigger including the 10-minute
idle stop; a declined opt-in is asserted to leave the app fully functional with the degraded copy
shown once rather than on every launch; the manifest test passes with the four new permissions and
still rejects anything unexpected; and the FGS type is asserted present, because omitting it is a
crash on Android 14 rather than a warning.

### A13.6 features/settings: wire quiet hours and retire the delivery caveat

- **blocked-by:** A13.5 · **verify:** H · **board:** no
- **design:** [09 §9.5](../design/09-alarms-and-insights.md), [08 §8.6](../design/08-flutter-app.md)

A12.2 shipped the alarms screen with a quiet-hours switch that goes nowhere and a caveat reading
_"Background monitoring arrives in a later release."_ **This is that release.** Wire the switch and
its window to `BridgePrefs`, make the per-channel choices real, add the monitoring toggle, and delete
the caveat — replacing it with what is now true, including the honest OEM sentence about battery
optimisation. The two-tier copy stays exactly as it is; nothing about A12.2's central claim has
changed.

**Done when:** the caveat string is asserted **absent** and the new copy present (a test that fails
today and passes after, which is the point); quiet hours round-trip through prefs and reach A13.1's
policy; toggling monitoring off is asserted to stop the service; and the device tier's copy is
asserted unchanged, because it was right the first time.

### A13.7 bench: the overnight cook, and the exit gate

- **blocked-by:** A13.6, F13.9 · **verify:** C · **board:** yes
- **design:** [09](../design/09-alarms-and-insights.md), [hardware-verified](../hardware-verified.md)

The last row of the sitting and the milestone's own gate: an **unattended overnight cook that wakes
the user for `target_reached`**. Set a target that will be crossed while the user is asleep, leave the
phone alone with the app swiped away, and record what happened — whether the notification arrived,
whether it made a sound through quiet hours (it must: `target_reached` is critical), whether the
foreground service survived until morning on this OEM, and whether the bridge's own latched state
agreed with the phone's when both were checked at 07:00.

**Done when:** the run is recorded in `docs/hardware-verified.md` with the phone's OEM and Android
version, the notification's arrival time against the session file's alarm mark, the service's survival
or the point at which it was killed, and the three exit-gate clauses each marked pass or fail by
observation rather than by inference.

---

## What is deliberately _not_ in M5

|                                                              | Why                                                                                                                                                                                          |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Heap remediation                                             | V3a.1's finding is recorded and M5's own budget is stated above (≤ 2 KB). The decision is _the target was wrong_; **M6's V3 24 h soak is what settles it**, and trimming buffers now would pre-empt the evidence |
| A Wi-Fi join QR on the OLED                                  | v1.1 stretch ([05 §5.3](../design/05-connectivity-and-provisioning.md)); `draw_bitmap` stays unbuilt until something needs it                                                                 |
| The three-button hardware variant                            | v1.1 ([07 §7.4](../design/07-display-and-controls.md)). F11b.7 emits the `UI_INPUT_*` vocabulary so it stays a driver, not a rewrite                                                          |
| DIO1 interrupt-driven LoRa RX                                 | v1.1; the polling driver works ([01 §1.5](../design/01-hardware.md))                                                                                                                          |
| Billows on the Radio page                                    | D11 — decoded and stored, never surfaced, and there is no unit to test against                                                                                                               |
| Cloud push / FCM                                             | Not planned ([11 §11.2](../design/11-roadmap-and-risks.md)). Every notification in A13 is local, which is also why they work with no internet                                                 |
| Carryover hints on the OLED                                  | [09 §9.4](../design/09-alarms-and-insights.md) makes it advisory and per-cut, and 21 columns is already tight. The app is where it belongs, and it is not in the exit gate                     |
| OTA progress overlay wired to a real OTA                     | F14 (M6). F11b.6 renders the §7.3 overlay; nothing drives it until the OTA path exists                                                                                                        |
| Quiet hours on the **device**                                | The bridge has `led_enabled` / `buzzer_enabled` ([07 §7.5](../design/07-display-and-controls.md)) and often no valid clock. Quiet hours are the phone's, and only the phone's                  |
| A second calibration point from a DMM                        | Not ours to schedule — F12.2's plateau solver stands in, F12.6 takes the point if a meter is present                                                                                          |
| iOS                                                          | Deferred ([11 §11.2](../design/11-roadmap-and-risks.md))                                                                                                                                     |
