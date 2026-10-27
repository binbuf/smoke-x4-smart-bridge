# 07 — Display & Controls

The bridge has one button and a 128×64 OLED. That is enough for up to four pages,
a passkey overlay, and a power-off confirmation. The Billows page appears only
after a Billows has been detected. Everything else is in the app.

## 7.1 Display

| | |
|---|---|
| Panel | SSD1306, 128×64, I²C at 400 kHz |
| Power | Vext (GPIO36) LOW before the I²C bus is created |
| Font | 5×7 body (21 columns × 8 rows); 12×24 numeric face for the headline temp and passkey |
| Refresh | Dirty-driven; a 1 Hz tick only while a time field is visible |
| Sleep | After `display_timeout_s` (default 60 s); Vext stays on, panel `0xAE`, render task idles |
| Wake | Any PRG press, BLE connect, pairing start, or alarm-free state change that matters |
| Framebuffer | 1 KB page-ordered; host-testable goldens |

The display is a status surface, not a menu. It never asks the user to choose
between more than two things, and it never requires a button sequence.

## 7.2 Pages

Tap PRG to advance. The current page survives display sleep and BLE connects; it
resets to page 1 on boot. The passkey and power-off overlays pre-empt the page.

### Page 1 — Probes (default)

```
┌─────────────────────┐
│P1          225.0°F  │
│P2          165.2°F  │
│P3             ---   │
│P4           80.0°F  │
│                     │
│• App   • X4   87%   │
└─────────────────────┘
```

- Four lines in probe order. No names or roles in the MVP; identity is `P1`–`P4`.
- One-decimal temperature. Show the unit on each line, or one unit marker in the
  status strip if the panel is too tight; do not mix both in one render.
- Detached: `---`, never `0.0`.
- If a probe is invalid (not detached, but no usable reading): `ERR`.
- Bottom strip: App dot (filled when connected, hollow when advertising), Smoke
  X4 dot (filled when a packet arrived in the last 90 s), battery percent or
  `—`, and a `!` if storage is unavailable. `App` is the user-facing word for
  the BLE link; `BLE` stays in diagnostics only.

The large numeric face is reserved for a future single-probe hero view. On the
four-probe page, 5×7 is clearer than four 12×24 numbers.

### Page 2 — Connection

```
┌─────────────────────┐
│App   connected      │
│Name  SmokeX4-A4F2   │
│Phones paired    2/4 │
│                     │
│X4    paired         │
│Radio  910.5 MHz     │
│Signal -71  last 12s │
└─────────────────────┘
```

When advertising, show `App ready to pair` and the phone's pairing state. When
the Smoke X4 is lost, show `X4 no data 14m`. When unpaired:

```
┌─────────────────────┐
│X4    not paired     │
│Scanning 915/920 MHz │
│                     │
│Put the Smoke X4 in  │
│SYNC, then hold its  │
│button until it beeps│
└─────────────────────┘
```

The scan page is the only place that instructs a physical action on the Smoke
X4. It must match the real ThermoWorks sync gesture; the task owner confirms it
on the bench.

### Page 3 — Billows

```
┌─────────────────────┐
│BILLOWS    DETECTED  │
│SET       225.0°F   │
│P4        224.6°F   │
│                     │
│Set on the Smoke X4  │
└─────────────────────┘
```

- `DETECTED` / `NOT DETECTED` from the Smoke X4. The page is only shown when a
  Billows has been detected; do not invent a "connected" state for a device
  whose fan output is not observable.
- `SET` is the Smoke X4 channel 4 set temp, only when validated; otherwise
  `SET —`.
- `P4` is probe 4 (the fan channel) if connected, else `—`.
- The last line always says "Set on the Smoke X4". There is no control mode and
  no app-set target in the MVP.
- Never show a fan speed, duty, or "running" state that is not measured.

### Page 4 — Bridge

```
┌─────────────────────┐
│BRIDGE       v0.1.0  │
│Battery  3.89V  87%  │
│Log      12.4 days left│
│Readings  35,712     │
│Uptime   14:15:30    │
│Memory   142k (low 128k)│
└─────────────────────┘
```

- Battery percent is `—` when unknown; do not invent charging state.
- `Log` shows days left at the current cadence; `Readings` shows the stored
  count.
- Firmware version and uptime.
- `Memory` is a bench diagnostic; it may be removed from the release page if it
  makes the page too dense. It is useful during the 24 h soak.
- Page names in the app preview are `Probes`, `Connection`, `Billows`, `Bridge`.
  The OLED itself may keep the compact headers above.

## 7.3 Overlays

### Passkey

Shown when a phone starts bonding. It is the reason the bridge gets MITM
protection.

```
┌─────────────────────┐
│  PAIR WITH PHONE    │
│                     │
│      418 302        │  ← 12×24
│                     │
│  enter this code    │
│  on your phone      │
└─────────────────────┘
```

- Generated at bond start; expires when bonding ends or after 60 s.
- The app must tell the user to look at the bridge before the OS prompt.
- If the phone rejects the code, the bridge clears it and returns to the page.
- A tap cancels the pairing attempt and returns to the page; the phone sees a
  failed bond and offers a retry.
- A passkey is never shown while merely advertising. A phone that has not
  started bonding cannot learn it.

### Power off

```
┌─────────────────────┐
│  POWER OFF          │
│                     │
│  keep holding   2   │
│                     │
│  release to cancel  │
└─────────────────────┘
```

- Appears after ~400 ms of hold; counts down to 1.5 s.
- At the threshold: `release to confirm`.
- A tap during the countdown does nothing; only releasing cancels.
- Releasing before the threshold cancels; releasing after commits.
- On commit: show `OFF` for ~300 ms, turn Vext off, sleep the radio, enter deep
  sleep.

### Boot

```
┌─────────────────────┐
│  SMOKE X4 BRIDGE    │
│       v0.1.0        │
│                     │
│ Attach antenna      │
│ before power        │
└─────────────────────┘
```

The splash is visible for at least 300 ms so a human can see it, then the first
page. There is no boot-time **menu or reset** gesture; the only boot-time hold is the
hold-to-wake confirmation. GPIO0 is a strap and holding it through a cold reset
can enter the ROM downloader.

### Storage failure

```
┌─────────────────────┐
│  STORAGE UNAVAILABLE│
│                     │
│  live readings only │
│  this session will  │
│  not be recorded    │
└─────────────────────┘
```

This is a persistent overlay until the next boot. A tap dismisses the overlay
for this boot so the normal pages remain usable; the bottom strip keeps a
storage warning. The app's `stats.flags.storage_ok = 0` and
`live.flags.storage_ok = 0` tell the same truth. Do not silently continue as if
recording works.

### Factory reset / clear history

These are app-initiated. The OLED shows a short progress state (`RESETTING…`,
`CLEARING LOG…`) and then reboots or returns to page 1. There is no on-device
confirmation because there is no on-device command for them.

## 7.4 The button

One button, GPIO0, active LOW, sampled at 20 ms with a 30 ms debounce.

| Gesture | Timing | Action |
|---|---|---|
| **Tap** | press < 400 ms | Next page. If the display was asleep, the press only wakes it. If an overlay is up, the tap dismisses it when dismissal is safe (passkey timeout, storage notice), otherwise it does nothing. |
| **Hold** | ≥ 1.5 s | Power off. Countdown from ~400 ms; commit on release. |
| **Hold from sleep** | ≥ 1.5 s | Power on. The boot path confirms the hold; an early release returns to sleep. |

There is no double-tap, long-press ladder, menu, or on-device setting. The
button never changes pairing, units, history, or Billows state.

### Dialog selection

The input layer is modelled as `NEXT` (tap) and `SELECT` (hold), even though only
one button exists. Pages use `NEXT`; the power-off confirmation uses
`SELECT`; a future two-option dialog can be driven by tapping to move the
highlight and holding to commit, without a hardware change. The MVP has no
multi-option menu, so this is a shape, not a hidden feature.

### Gesture state machine

```
        ┌──────┐  press    ┌─────────┐  release <400 ms   ┌─────┐
        │ IDLE │──────────►│ PRESSED │───────────────────►│ TAP │─► next page
        └──────┘           └────┬────┘                    └─────┘
            ▲                   │ held ≥400 ms
            │                   ▼
            │            ┌──────────────┐
            │            │ HOLD_CONFIRM │  release <1.5 s ─► cancel
            │            │  (countdown) │
            │            └──────┬───────┘
            └───────────────────┴─ release ≥1.5 s = commit ─► POWER OFF
```

Properties:

1. **Commit on release.** The user can always cancel by letting go.
2. **A wake press is consumed.** Waking the display never also changes the page.
3. **No hidden destructive gesture.** Factory reset is app-only; a pocket press
   cannot erase a cook.

### Deep-sleep wake

The device is woken by GPIO0. The boot code checks that the button is still held
for ~1.5 s after reset. If not, it goes back to sleep without starting BLE or
the UI. This is the defense against a pocket press.

The GPIO0 ROM-strap risk is a hardware gate (see [01 §1.4](01-hardware.md)). T09
verified **20/20** USB-attached hold-PRG wakes with no ROM-download entry
(2026-10-26); the physical button on battery is still owed. See
[`hardware-verified.md`](../hardware-verified.md) and
[ADR 0020](adr/0020-gpio0-ext1-deep-sleep-wake.md). If the detached repeat
contradicts that result, the fallback is wake-by-RST plus a documented
instruction, or an external latch. Do not ship a hold-to-wake feature that is
unreliable.

## 7.5 Display state priority

When several things are true, show the highest-priority state:

1. Factory reset / clear-history progress (device is going away).
2. Passkey overlay.
3. Power-off confirmation.
4. Storage failure.
5. Boot splash.
6. Normal page.

An alarm does not exist in the MVP, so there is no alarm overlay. The app is not
notified of alarms; the Smoke X4's own alarm remains the alarm.

## 7.6 Rendering and testing

- Page renderers are pure functions of a `ui_snapshot_t` and write a 1 KB
  framebuffer.
- Host tests compare framebuffer bytes against committed goldens for:
  four probes, detached probe, unpaired link page, paired link page, passkey,
  power-off countdown, storage failure, and Billows detected/not detected.
- A small host tool converts a framebuffer to PNG for human review; the `.fb`
  bytes are the gate, the PNG is for eyes.
- The display must be legible at arm's length through the case window. Test in
  daylight and at night.
- The panel sleeps after the configured timeout; a BLE connect or a button wakes
  it. A waking tap is consumed.

## 7.7 Bench verification

- [ ] Tap cycles all visible pages (Billows only after detection), with no perceptible lag.
- [ ] A waking tap does not change the page.
- [ ] Hold shows the countdown; early release cancels; commit sleeps the board.
- [ ] Hold from sleep boots to page 1; early release goes back to sleep.
- [ ] PRG wake works 20/20 with USB attached and detached (the strap risk).
      **USB attached: ✅ 20/20, 2026-10-26** (`rst:0x5 (DSLEEP)`, no ROM
      download; DTR drove the GPIO0 net). USB detached + physical button: owed.
- [ ] Passkey is readable at arm's length and only appears during bonding.
- [ ] Detached probe shows `---`, never `0.0`.
- [ ] Storage failure overlay appears when the `samples` partition is made
      invalid (bench test build).
- [ ] Display sleep and wake work with BLE connected.
- [ ] Deep-sleep current is measured and recorded.
