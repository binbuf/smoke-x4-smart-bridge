# Running the field report

**One run, one log, and the desk has everything it needs to finish.**

A large part of the app is provably correct at the desk — 1,211 tests, 27
firmware host suites. A specific, enumerable part of it is not provable there at
all, because it depends on what *this phone's* Android build does, what *this*
OEM's background killer does, and what the bridge actually answers. This is the
harness for that part.

Takes about three minutes. Please do it **next to the bridge**, with the bridge
powered on and at least one probe plugged in.

---

## Before you start

Three things worth setting up, because they change what the run can tell us:

1. **Have a cook in history.** Anything with a few hours of readings. Two checks
   (BLE throughput, chart build) measure against the *longest* cook cached on
   the phone, and against a ten-minute cook they measure nothing useful.
2. **Decide which lane you want measured.** The BLE throughput number only
   exists on Bluetooth, and it is the number §E.6 and risk J2 both hang on. If
   you can, run the report **twice** — once on Wi-Fi, once with Wi-Fi off so it
   falls back to Bluetooth. Two logs is far better than one.
3. **Do not pre-grant anything.** If notifications are currently denied or the
   battery exemption is off, *leave it* — that is a finding, and I would rather
   see the real state of a normally-installed app.

---

## The run

1. **Device** tab → **Diagnostics** → **Run the field checks**.
   (If Diagnostics is hidden, five taps on the firmware row on the Device tab
   opens it — the Android "build number" convention.)

2. **Leave the rollback switch OFF for the first run.** See below.

3. Tap **Run the checks** and watch it go. Each check reports as it finishes;
   the Bluetooth history transfer is the slow one and can take a minute or so.

4. **While it is running, watch for the test alarm.** One check posts a real
   critical notification. Note down:
   - did it make a **sound**?
   - did it show as a **heads-up banner** over whatever was on screen?
   - if you lock the phone and put it face down first — does it **light the
     screen**?

   That last one is the whole `USE_FULL_SCREEN_INTENT` question and there is no
   way to read it programmatically on this plugin version, so your eyes are the
   instrument.

5. When it finishes, tap **Share the log** and send it over. If the share sheet
   misbehaves, the full report is on screen and selectable — copy and paste
   works just as well.

---

## The second run: the rollback test

Worth doing, and worth understanding first.

The switch labelled **"Include the network rollback test"** does something
deliberately alarming: it tells the bridge to join a Wi-Fi network that does not
exist, and then waits to see whether the bridge notices nobody confirmed and
**puts itself back**. That self-healing is the entire feature — it is what
replaced "walk to the smoker with a USB cable" — and it has never run on
hardware.

What actually happens:

- the Wi-Fi link really does go away, for about **50 seconds**;
- the bridge keeps recording the whole time, and Bluetooth stays connected;
- then it comes back on its own and the check passes.

If it does **not** come back:

- the bridge is most likely on its own hosted network — try
  **`http://192.168.4.1`**, or the app's "Reach it directly by address";
- Bluetooth should still reach it regardless, which is the escape hatch the
  design depends on. If Bluetooth *also* cannot reach it, that is the single
  most important thing in the whole run and worth saying loudly.

Run this one **when no cook you care about is in progress**.

---

## What I will do with it

Each of these is currently an inference from reading code, and the log turns it
into a fact:

| Log line | What it settles |
|---|---|
| `phone.identity` | Which OEM behaviours apply (J1 names Samsung, Xiaomi, OnePlus) |
| `notify.critical` + your notes | Whether the 3 a.m. path works at all, and whether Android 16 Live Updates are worth building for this device |
| `fgs.start` | Whether `connectedDevice` survives here — and if not, whether CompanionDeviceManager becomes necessary |
| `ble.history` | §E.6 and J2: is full history over Bluetooth genuinely fast enough, or does the honest 2-hour copy need to stay? |
| `rules.readback` | Whether my rule→tunable mapping is right. **It was inferred from reading `app_api_core.c`** — if this fails it prints the tunable keys the device actually reports, and I can correct the mapping from that alone |
| `config.readback` | Whether the §F settings fix really reaches the device |
| `db.schema` | Whether the v1→v2 migration ran cleanly on a real install with real data |
| `sync.state` | Whether rollover detection is too eager — a permanent gap on a bridge that was never left alone would mean §E.5 needs revisiting |
| `chart.decimate` | §H.2's open decision 3: keep `fl_chart` or move to a `CustomPainter`. A series build inside one 16 ms frame says keep it |
| `net.rollback` | Whether §E.3 works on hardware |

**A `SKIP` is not a failure.** It means the check could not run — no bridge, wrong
lane, no plumbing in this build. It costs nothing except the answer, and the log
says which.

---

## If something goes wrong mid-run

The harness cannot take the app down: a check that throws becomes a `FAIL`
carrying its reason and the run continues. If the app *does* die, that is itself
the most interesting result in the file — please say what you were looking at
when it happened.

The report is written to the app's documents directory as
`smokebridge-field-report-YYYYMMDD-HHMM.txt` even if sharing fails, so nothing
is lost.
