# 07 — Display and Controls

The 128×64 OLED and the single PRG button, designed so the bridge is genuinely useful **standing
next to it with no phone in your hand**.

> **[13 §13.7](13-ux-architecture.md) supersedes the page copy, the LED table and the overlay rules
> here.** It adds a Welcome page and a setup-stance overlay, an overlay priority stack, and a table
> of user-facing state names that replaces wire identifiers on the glass. The button model, the
> panel/framebuffer design and the power rules below stand. §7.5's rule that `led_enabled = OFF`
> means zero duty *in every state* is deliberately **not** overridden by 13 — it is raised as an
> open question there instead.

Two questions from the brief, answered up front:

> **Should the button switch modes?**
> Yes — but as a _context action on the Network page_, not a global toggle. A blind global
> "long-press swaps AP/STA" is one pocket-press away from taking your bridge off the network 12
> hours into a cook. Requiring the user to navigate to the Network page first means the screen
> already shows what they're switching _from_ and _to_.

> **Should the screen show Wi-Fi info when hosting, or the joined network when a client?**
> Yes, both — on a dedicated Network page that renders differently per mode (SSID **and password**
> when hosting; SSID, IP, and signal when joined). Plus a permanent one-line status strip on every
> page, so network state is never more than a glance away.

## 7.1 The display

|            |                                                                                  |
| ---------- | -------------------------------------------------------------------------------- |
| Panel      | SSD1306, 128×64, I²C @ 400 kHz (SDA 17, SCL 18, RST 21)                          |
| Power      | Vext (GPIO36) must be driven **LOW**                                             |
| Small font | 5×7 glyphs on a 6×8 cell → **21 columns × 8 rows**                               |
| Large font | 12×24 digits + `°`, for the headline temperature. ~1.2 KB of table               |
| Refresh    | 1 Hz, and immediately on any state change. Paused while asleep                   |
| Sleep      | after `display_timeout_s` (default 60 s) → panel off (`0xAE`), render task idles |
| Wake       | any button, any alarm, session start/end, network state change, BLE connect      |

Sleeping the panel saves ~10 mA — the cheapest single item in the power budget
([01 §1.6](01-hardware.md)) — and matters because an AP-mode bridge cannot otherwise sleep at all.

The reference draws seven fixed lines of 5×7 text at 1 Hz forever. That is a fine debug readout and
a poor product. Everything below is additive: the same information, organized into pages, with the
one number you actually want made large.

### The status strip

Row 7 (the bottom line) is reserved on every page:

```
●sta  04:12  71%  ⚠
```

| Field                | Meaning                                                       |
| -------------------- | ------------------------------------------------------------- |
| `●` / `○`            | filled = LoRa packet within the last 60 s; hollow = base lost |
| `sta` / `ap` / `---` | network mode; `ap*` when a client is associated               |
| `04:12`              | elapsed time in the active cook, or `--:--`                   |
| `71%`                | battery SoC, or `USB` when charging                           |
| `⚠`                  | an unacknowledged alarm exists                                |

## 7.2 Pages

Tap PRG to advance. The current page persists across sleep; it resets to page 1 on boot and
whenever an alarm fires.

### Page 1 — Probes (default)

```
┌─────────────────────┐
│Pit          204/250 │  ← name, alarm band
│                     │
│    243°F        ▼   │  ← 12×24 large, trend arrow
│                     │
│Brisket 163°F  +4.1  │  ← °F/hr
│Point    159°F  +3.8 │
│Flat        ---      │  ← detached, never "0°F"
│●sta  04:12  71%     │
└─────────────────────┘
```

The probe with `role = pit` gets the large treatment; if no role is assigned, probe 1 does. Trend
arrows: `▲` rising > 5 °F/hr, `▼` falling > 5 °F/hr, `–` steady. Detached probes render `---`, never
a temperature — the reference's `0.0` is a real trap on a graph and a real confusion on a screen.

**Hold 2 s** → cycle the displayed unit (°F ↔ °C). Display only; storage stays canonical
([04 §4.2](04-storage-and-history.md)).

### Page 2 — Cook

```
┌─────────────────────┐
│Brisket        #27   │
│Elapsed  04:12:30    │
│Brisket 163 → 203°F  │
│ETA  6h20m  (stall)  │
│    ╱‾‾╲___╱‾‾‾‾     │  ← 2 h sparkline, 21×16 px
│    ╱                │
│Marks 3   1,440 pts  │
│●sta  04:12  71%     │
└─────────────────────┘
```

The sparkline is the pit probe over the RAM ring's 2-hour window
([04 §4.3](04-storage-and-history.md)) — auto-scaled, with min/max labelled at the ends. This is
where "did the fire hold overnight?" gets answered without unlocking a phone.

**Hold 2 s** → start or stop the session, with a 3-second confirm countdown.

### Page 3 — Network

The page that answers the brief's second question. It renders differently per mode.

**Hosting (AP):**

```
┌─────────────────────┐
│NETWORK   hosting    │
│SSID                 │
│  SmokeBridge-A4F2   │
│Password             │
│  Gk7mR2xQpT         │
│http://192.168.4.1   │
│1 device connected   │
│●ap*  04:12  71%     │
└─────────────────────┘
```

Everything needed to join is on the glass. No app, no manual, no default password to look up. (A
Wi-Fi join QR replaces the SSID/password block as a stretch item — see
[05 §5.3](05-connectivity-and-provisioning.md).)

**Joined (STA):**

```
┌─────────────────────┐
│NETWORK   joined     │
│Backyard             │
│  ▂▄▆█  -54 dBm      │
│192.168.1.42         │
│smokebridge.local    │
│BLE 1 conn  2 bonded │
│                     │
│●sta  04:12  71%     │
└─────────────────────┘
```

**Connecting / failed:**

```
┌─────────────────────┐
│NETWORK   connecting │
│Backyard             │
│  attempt 3          │
│  retry in 4:52      │
│                     │
│Hold PRG to host     │
│  own network        │
│○---  04:12  71%     │
└─────────────────────┘
```

**Hold 2 s** → toggle AP ↔ STA, with a confirm countdown that names the target:
`Switch to hosting? 3…2…1`.

### Page 4 — Radio

```
┌─────────────────────┐
│RADIO      paired    │
│Smoke X4  |abCDe     │
│910.5 MHz            │
│RSSI -71  SNR 9      │
│Last packet    12s   │
│OK 4102  Bad 3       │
│Interval  30.0s avg  │
│●sta  04:12  71%     │
└─────────────────────┘
```

The mean inter-packet interval is on the glass because it is the cheapest possible field test of
[02 Q1](02-smoke-x-protocol.md#28-open-questions) — if header field 1 really is the transmit
interval, this number tracks it. (Billows state is decoded and stored but not displayed in v1, per
[D11](00-overview.md); it would slot in here when a unit is available to test against.)

When unpaired, it becomes the pairing screen:

```
┌─────────────────────┐
│RADIO    UNPAIRED    │
│                     │
│Scanning 915/920 MHz │
│                     │
│Put your Smoke X     │
│base in SYNC mode    │
│                     │
│○---  --:--  71%     │
└─────────────────────┘
```

**Hold 2 s** → unpair (when paired, with confirm) or force a re-scan (when unpaired).

### Page 5 — System

```
┌─────────────────────┐
│SYSTEM    v1.0.0     │
│Battery 3.89V  71%   │
│  charging           │
│Uptime  14:15:30     │
│Storage 9% of 2.4MB  │
│  12 cooks           │
│Heap 168k (min 141k) │
│●sta  04:12  71%     │
└─────────────────────┘
```

**Hold 2 s** → toggle battery-saver mode.

## 7.3 Overlays

Transient screens that pre-empt whatever page is showing.

**Boot splash + recovery window** ([03 §3.4.1](03-firmware-architecture.md)):

```
┌─────────────────────┐
│   SMOKE BRIDGE      │
│      v1.0.0         │
│                     │
│  hold PRG for       │
│  AP mode      3     │
│                     │
│  connect antenna    │
│  before use         │
└─────────────────────┘
```

**BLE passkey** — the reason we get real MITM protection ([05 §5.6](05-connectivity-and-provisioning.md)):

```
┌─────────────────────┐
│  PAIR WITH PHONE    │
│                     │
│      418 302        │  ← large font
│                     │
│  enter this code    │
│  in the app         │
│●sta  04:12  71%     │
└─────────────────────┘
```

> **Shipped in M3 with one decided deviation: row 7 is blank.** The status strip's sources (battery
> SoC, the alarm glyph) are M5 components, so F11a leaves the row empty rather than inventing them;
> F11b adds the strip to every page and overlay at once. Stated here so the committed golden
> (`firmware/test/goldens/oled/passkey-418302.fb`) is not mistaken for drift.

**Alarm** — inverted video so it reads across a dark yard:

```
┌─────────────────────┐
│███ A L A R M ███████│
│                     │
│ Brisket             │
│   203.1°F           │
│ target reached      │
│                     │
│ tap PRG to silence  │
└─────────────────────┘
```

Persists until acknowledged (tap) or 60 s, after which the page reverts but the **LED keeps
signalling and the alarm stays unacknowledged** in the API — silencing the screen is not the same as
dealing with it.

**Confirm countdown** — every destructive or disruptive hold action:

```
┌─────────────────────┐
│                     │
│  Switch to hosting? │
│                     │
│  keep holding   2   │
│                     │
│  release to cancel  │
│                     │
└─────────────────────┘
```

**OTA**:

```
┌─────────────────────┐
│  UPDATING FIRMWARE  │
│                     │
│  ████████░░░░  62%  │
│                     │
│  do not power off   │
│                     │
│  1.0.0 → 1.1.0      │
└─────────────────────┘
```

## 7.4 The button

One button — GPIO0, active LOW, sampled at 20 ms with a 30 ms debounce. It carries **two
meanings and nothing else**, because the bridge is a passthrough: every *control* lives in the
app (D15). The device shows information, and it can be switched off.

| Gesture          | Timing                 | Action                                                                                                                                                                                                                              |
| ---------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Tap**          | < 400 ms               | Next info view. Emitted on release **immediately** — with no double-tap to disambiguate against, nothing waits out a 400 ms window. Wakes the display (that press is consumed by the wake, not the view-advance). Dismisses an alarm overlay — **dismissing is not silencing** |
| **Hold**         | ≥ 2 s                  | Power off → deep sleep. Past tap length the overlay names it and counts down; at the threshold it reads `release to confirm`                                                                                                          |
| **Hold to wake** | ≥ 5 s from deep sleep  | Power on. The GPIO0 wake is confirmed by a sustained hold so a pocket-press cannot power the bridge on; released early it goes straight back to sleep ([03 §3.4.1](03-firmware-architecture.md))                                      |

There is deliberately **no double-tap, no hold ladder, and no on-device menu**. Units, sessions,
marks, pairing, network mode, battery saver, factory reset and alarm silence are app concerns,
reachable over HTTP and BLE ([06](06-device-api.md), [05](05-connectivity-and-provisioning.md)).

### Gesture state machine

```
        ┌──────┐  press    ┌─────────┐  release <400 ms   ┌─────┐
        │ IDLE │──────────►│ PRESSED │───────────────────►│ TAP │─► next view
        └──────┘           └────┬────┘                    └─────┘
            ▲                   │ held ≥ 2 s
            │                   ▼
            │            ┌──────────────┐
            │            │ HOLD_CONFIRM │   release <2 s ─► nothing (cancel)
            │            │  (countdown) │
            │            └──────┬───────┘
            └───────────────────┴─ release ≥2 s = commit ─► POWER OFF
```

Two properties worth stating because they are what make a one-button UI tolerable:

1. **The hold commits on _release_, not on reaching the threshold.** The countdown gives a
   visible cancel path: let go early and nothing happens. On a device whose only action is
   "switch off", that is the difference between a deliberate act and one pocket-press taking a
   bridge down 12 hours into a cook.
2. **A wake press is consumed.** Waking a sleeping display never also changes the view, so the
   user always sees the state they left.

### The alarm is displayed, never silenced here

An alarm takes over the glass (§7.3) and forces view 1, because it has to read across a dark
yard. A tap **dismisses the overlay and moves to the next view** — the alarm itself stays active
and the strip keeps its glyph. Silencing belongs to the Smoke X receiver or to the app. The
bridge reports; it does not resolve.

### Designed for three buttons

Per D3, the input layer is abstracted now even though only one button ships:

```c
typedef enum { UI_INPUT_BACK, UI_INPUT_NEXT, UI_INPUT_SELECT } ui_input_t;
```

With one button, gestures map onto that vocabulary (tap→NEXT, hold→SELECT; **BACK has no gesture**
now that double-tap is gone). Fitting tactile switches on **GPIO47 (NEXT)** and **GPIO48 (SELECT)**
— both free and safe ([01 §1.2](01-hardware.md)) — becomes a Kconfig flag and a driver, not a UI
rewrite. The view model and the overlays are unchanged.

## 7.5 LED

The white LED on GPIO35 (active HIGH, LEDC PWM). Governed by `led_enabled`, default `alarms_only` —
a light blinking all night on a bedside bridge is a reason to unplug it.

| Pattern                    | Meaning                                                     |
| -------------------------- | ----------------------------------------------------------- |
| Off                        | Normal, or the user disabled it                             |
| 2 Hz blink                 | **Unacknowledged alarm**                                    |
| Solid                      | Pairing mode active                                         |
| Double-blink every 2 s     | Base station lost                                           |
| Slow breathe               | OTA in progress                                             |
| One 20 ms flash per packet | Heartbeat — off by default, useful during antenna placement |
| 5 s rapid flash            | `identify` from the app, for telling two bridges apart      |

An optional piezo on GPIO7 mirrors the alarm pattern when `buzzer_enabled` is set; the code is
present and a no-op when unfitted.

## 7.6 Rendering implementation

Extend the reference's approach rather than pulling in LVGL — a full graphics stack is a poor trade
for a 1 KB framebuffer on a device with no PSRAM.

- Keep its 1 KB page-ordered framebuffer and `framebuffer_flush()`; both are correct and small.
- Add: `draw_text_large()` (12×24 digits), `draw_hline`/`draw_rect`/`draw_progress`,
  `draw_sparkline(x, y, w, h, int16_t *vals, n)`, `draw_invert_region()`, and `draw_bitmap()` for
  the eventual QR.
- **Render only when dirty.** A dirty flag set by event-bus handlers plus a 1 Hz tick for the clock
  fields, instead of the reference's unconditional 1 Hz full redraw. Cuts I²C traffic and CPU
  wakeups to near zero while nothing is changing.
- Page renderers are pure functions of a snapshot struct — `render_page_probes(const ui_state_t*)` —
  so the whole display layer is testable on the host. **Built in M3 as
  `tools/oled/render_oled_preview.py`** (`make oled-preview`): the host test writes each rendered
  snapshot as a raw 1 KB framebuffer and the script turns those into PNGs, which makes visual review
  possible in CI without hardware.

  One adaptation from the reference's version, worth stating because it is the whole point: the
  reference re-implemented the firmware's font in Python and drew sample text, so its picture could
  agree with the script while disagreeing with the firmware. Ours renders **the firmware's own
  output** and owns no font at all. The **`.fb` is the golden** — byte-compared in the C host test,
  so a one-pixel change is a red test; the PNG is the artifact a human reviews, and is not
  diff-gated because deflate output is not stable across zlib versions.
  </content>
