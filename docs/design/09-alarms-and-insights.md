# 09 — Alarms and Insights

Two things turn a data logger into something you'd actually cook with: **it wakes you up when it
matters**, and **it tells you something you couldn't work out by staring at the number**.

## 9.1 Two tiers, on purpose

|             | **Device tier** (firmware)                     | **App tier** (Flutter)                           |
| ----------- | ---------------------------------------------- | ------------------------------------------------ |
| Runs        | always, even with no phone in existence        | while the app or its foreground service is alive |
| Signals via | OLED banner, LED, optional buzzer, WS/BLE push | Android notifications                            |
| Rules       | cheap, thresholdy, no history needed           | windowed regression over cached history          |
| Latching    | authoritative — the device owns alarm state    | mirrors and acknowledges the device's            |

The device tier exists because a phone that ran out of battery is not a reason for a $200 brisket to
overcook. The app tier exists because ETA projection and stall detection need more history and more
maths than belongs in a 30-second event handler.

**The device is the source of truth for alarm state.** The app reconciles on connect — an alarm that
fired at 03:40 while your phone was face-down is still latched and unacknowledged when you pick it
up at 07:00, and the app says so.

## 9.2 Device-tier rules

Evaluated in `components/app_alarm/rules.c` — pure C, no ESP-IDF, host-tested — on every sample plus
a 10 s tick.

| Rule              | Default             | Trigger                                                                                     | Severity           |
| ----------------- | ------------------- | ------------------------------------------------------------------------------------------- | ------------------ |
| `smoke_x_alarm`   | on                  | The base's own alarm: packet `new_alarm` set, or an alarm-enabled probe outside its min/max | critical           |
| `target_reached`  | on                  | A `food` probe crosses its configured target upward                                         | critical           |
| `pit_out_of_band` | on, ±25 °F / 10 min | `pit` probe outside target ± band, sustained                                                | warning            |
| `pit_crash`       | on                  | `pit` falls > 50 °F below target **and** slope < −10 °F/hr for 10 min — the fire is dying   | critical           |
| `probe_detached`  | on                  | A probe goes attached → detached during a session                                           | warning            |
| `base_lost`       | on, 10 min          | No valid state message from the base station                                                | warning            |
| `battery_low`     | on, 15 % / 5 %      | Bridge battery, two thresholds                                                              | warning / critical |
| `storage_low`     | on, 2 % free        | `cooks` partition nearly full                                                               | warning            |
| `system_fault`    | on                  | A coredump was found at boot — the bridge restarted unexpectedly                            | warning            |

`pit_crash` and `pit_out_of_band` both need a short slope, which the device gets from the 240-sample
RAM ring ([04 §4.3](04-storage-and-history.md)) — no flash reads on the alarm path.

### Lifecycle

```
     condition true                ack (button / app / BLE)
  ────────────────────►  RAISED  ─────────────────────────►  ACKED
                          │  │                                 │
      condition false     │  └──── auto_clear && cond false ───┤
      + hysteresis        │                                    │
                          ▼                                    ▼
                       CLEARED ◄─────────────────────────── CLEARED
```

- **Latched.** A `target_reached` that fires at 02:00 stays raised until someone acknowledges it,
  even if the probe later cools. Transient alarms that clear themselves are alarms you sleep through.
- **Acknowledging silences, it does not resolve.** LED and buzzer stop; the alarm stays in the list
  and in `GET /api/v1/status` with `acked: true`.
- **Hysteresis on re-arm.** `target_reached` cannot re-raise until the probe drops 3 °F below
  target. `pit_out_of_band` needs the pit back inside the band for 5 minutes. Without this, a probe
  hovering exactly at threshold generates an alarm every 30 seconds all night.
- **Lid-open grace.** While a lid-open is detected (§9.4), `pit_out_of_band` and `pit_crash` are
  suppressed for 15 minutes. Every spritz and every wrap otherwise fires the pit alarm, and an alarm
  that cries wolf gets muted permanently by the user — which is the real failure.

Each alarm carries an id, rule, probe, trigger value, timestamp, severity, and ack state, and is
written to the session's `.mrk` file as a mark (kind 5) so the graph shows where it happened.

## 9.3 App-tier rules

Computed in `domain/analysis/` over the cached history.

| Rule                            | Trigger                                  | Severity                       |
| ------------------------------- | ---------------------------------------- | ------------------------------ |
| `eta_soon`                      | A food probe's ETA drops below 30 min    | info — _"start getting ready"_ |
| `stall_started` / `stall_ended` | §9.4                                     | info                           |
| `lid_open`                      | §9.4                                     | info                           |
| `bridge_unreachable`            | No data for 3 min while a cook is active | warning                        |
| `phone_offline`                 | Foreground service lost network entirely | warning                        |

These are advisory by design. Anything that must fire reliably lives in the device tier.

## 9.4 The analysis

All of it is pure functions in `domain/analysis/`, table-tested, with the same rules mirrored in C
where the device needs them.

### Rate of change

Ordinary least-squares slope over a rolling **10-minute window** (20 samples at 30 s):

```
slope_f10_per_s = Σ((tᵢ − t̄)(yᵢ − ȳ)) / Σ((tᵢ − t̄)²)
°F/hr = slope_f10_per_s × 3600 / 10
```

Windows with fewer than 12 valid samples, or spanning a gap > 2 min, return `null` rather than a
number computed from bad data. Displayed to one decimal place; the underlying resolution is 0.1 °F
over 10 minutes, so a `±0.6 °F/hr` claim is at the edge of meaningful and is rendered as `~0`.

### ETA to target

Naive `(target − current) / slope` is wrong in the back half of every cook, because meat approaches
pit temperature asymptotically rather than linearly. Two models, and a refusal to guess:

**Linear** — used early, when the probe is far below pit and climbing steadily.

**Newton cooling** — used once the food is within ~60 °F of pit temperature:

```
T(t) = T_pit − (T_pit − T₀)·e^(−k·t)

           1        T_pit − T_target
t_remain = ─ · ln( ────────────────── )
           k        T_pit − T_current
```

`k` is fitted from the last 60 minutes by regressing `ln(T_pit − T)` against `t`. Requires
`T_target < T_pit` — if the target is above the current pit temperature the answer is _"not at this
pit temperature"_, which is genuinely the right answer and is what the app says.

**Guard rails**, because a confidently wrong ETA is worse than none:

- Needs ≥ 30 minutes of session history
- Needs `|slope| ≥ 1 °F/hr`
- Suppressed entirely while a stall is detected → _"stalled — ETA unavailable"_
- Presented as a **range** derived from the slope's standard error, rounded to 15 minutes:
  _"5h 45m – 7h 00m"_. Never `6h 23m`; the physics does not support that precision and the false
  confidence is what makes people trust it and then get burned
- Recomputed on every sample, but the _displayed_ value is rate-limited so it doesn't twitch

### Stall detection

The classic barbecue stall: evaporative cooling balances heat input and a large cut sits at
150–170 °F for hours.

```
enter:  role == food
        ∧ |slope| < 2 °F/hr sustained ≥ 30 min
        ∧ 140 °F ≤ temp ≤ 180 °F
exit:   slope > 4 °F/hr sustained ≥ 15 min
```

Worth surfacing not because it needs action but because it prevents one: _"the stall is normal,
your cook is fine, do not raise the pit temperature"_ is the single most useful thing an app can say
to someone at hour six of their first brisket.

### Lid open

```
detect:  pit probe drops ≥ 25 °F within any 3-minute window
confirm: recovers ≥ 50 % of the drop within 20 min → it was a lid open
         does not recover                          → escalate to `pit_crash`
```

Firing on detection (so the grace window starts immediately) and confirming afterwards means the
pit alarm is suppressed from the moment the lid opens, and a genuine fire failure still escalates
20 minutes later. An auto-mark (kind 2) is written to the session so the graph is annotated.

### Carryover

When a food probe reaches its target, internal temperature continues rising 3–8 °F after removal,
depending on cut size. The app shows an informational _"pull at ≈ 198 °F to land at 203 °F"_ hint
based on the probe's recent slope and a per-role constant. Advisory only — no alarm, no automation,
because the constant depends on the cut and we don't know the cut.

### Cook statistics

Computed on session close and shown on the detail screen: total duration, pit mean and standard
deviation, time in band, pit min/max, per-probe start/end/peak, stall duration, number of lid
events, average °F/hr per phase, and total samples with gap count. This is what makes cooks
comparable, which is what makes the whole thing more than a thermometer with a screen.

## 9.5 Notifications on Android

Four channels, so users can tune rather than mute:

| Channel    | Importance | Behaviour                                                                      |
| ---------- | ---------- | ------------------------------------------------------------------------------ |
| `critical` | HIGH       | Sound + vibration + heads-up, full-screen intent, optional DND bypass (opt-in) |
| `warning`  | DEFAULT    | Sound, heads-up                                                                |
| `info`     | LOW        | Silent, in the shade                                                           |
| `ongoing`  | MIN        | The foreground service notification — silent, non-dismissible while cooking    |

**Quiet hours** (default 22:00–06:00, configurable): `warning` and `info` go silent; `critical`
still sounds. Overcooking a brisket at 3 a.m. is precisely the thing worth waking up for, which is
why `target_reached` is critical.

The ongoing notification is a live readout, updated every 30 s:

```
┌────────────────────────────────────────┐
│ 🔥 Smoke Bridge · Brisket · 04:12       │
│ Pit 243°F ▼   Brisket 163°F ▲          │
│ ETA 5h45m – 7h00m · stalling           │
│ [ Add mark ]            [ Stop cook ]  │
└────────────────────────────────────────┘
```

## 9.6 The foreground service

```
┌────────── UI isolate ──────────┐        ┌───── service isolate ─────┐
│ Riverpod providers             │◄──────►│ BridgeTransport (WS/BLE)  │
│ drift (reads)                  │  port  │ drift (writes)            │
│ charts, screens                │        │ alarm reconciliation      │
└────────────────────────────────┘        │ notification updates      │
                                          └───────────────────────────┘
```

|             |                                                                                                         |
| ----------- | ------------------------------------------------------------------------------------------------------- |
| Starts      | when a cook session becomes active and monitoring is enabled                                            |
| Type        | `connectedDevice` (required from Android 14)                                                            |
| Stops       | on session end, on user stop, or 10 min after the last successful connection when no session is active  |
| Reconnect   | exponential backoff, immediate retry on `ConnectivityChanged`; `bridge_unreachable` warning after 3 min |
| Persistence | writes every received sample straight to drift, so history survives the app being swiped away           |

**Battery optimisation** is the practical hazard: several OEM Android builds kill long-running
foreground services regardless of type. After the first cook starts, the app offers a one-tap
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` with a plain explanation. It is opt-in; declining degrades
the app to _"reconnects and catches up when you open it"_ — which still works, because sync is
delta-based and the **device** never stopped recording ([04](04-storage-and-history.md)).

That is the safety net worth restating: even if the phone dies, the app is killed, and the network
drops, **the bridge keeps logging to flash and keeps sounding its own alarms.** Everything in this
document is a convenience layered on top of a device that already works alone.
</content>
