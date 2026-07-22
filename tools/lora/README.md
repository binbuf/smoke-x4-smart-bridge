# tools/lora — capture tooling

Turns real Smoke X traffic into committed fixtures. In M0 that means
normalizing an **ESP-IDF monitor log from the reference firmware**; the
HTTP-based `pull.py`/`replay.py` arrive with T4 (M1) once our firmware serves
`/api/v1/debug/*`.

```bash
dart run lora:normalize capture.log --name first-x4-capture
```

writes `protocol/fixtures/lora/first-x4-capture.loralog` (every packet:
boot-segment, t_ms, RSSI, SNR, direction, class, payload) and
`…report.md` — packet counts, interval statistics, link quality, and direct
evidence on protocol questions Q1/Q2/Q4/Q6/Q8, plus copy-paste-ready vectors
for [design 02 §2.3](../../docs/design/02-smoke-x-protocol.md).

## The bench + capture sitting (V1.x, V2.1, V2.2 — no cook required)

The base station broadcasts every 30 s whether anything is cooking or not;
probes at room temperature produce fully real X4 vectors.

**Safety, before any power:**

1. **Screw the LoRa antenna on first and leave it on.** Pairing transmits the
   sync ACK; TX into an open antenna port can destroy the SX1262 PA.
2. Connecting the battery? **Meter the SH1.25-2 polarity against the board
   silkscreen first** (V1.1) — third-party packs have shipped reversed, and
   reversed polarity kills the board. USB-C-only is fine for this sitting.

**Part 1 — capture with the reference firmware (V1.2, V2.1, V2.2):**

```powershell
# ESP-IDF 5.4 PowerShell. Build a COPY — docs/reference/ stays frozen.
mkdir ~\esp-work; cd ~\esp-work
Copy-Item -Recurse D:\repos\binbuf\smoke-x4-smart-bridge\docs\reference\smoke-x-receiver .
cd smoke-x-receiver
git clone https://github.com/nopnop2002/esp-idf-sx126x.git   # submodule dir is empty in the snapshot
Copy-Item sdkconfig.heltec-v3 sdkconfig
idf.py build
idf.py -p COMx flash monitor          # COM port from Device Manager
```

In the monitor press **Ctrl+T then Ctrl+L** to log to a file — that file is
the deliverable. Then:

- **V2.2 (2 min):** with the bridge unpaired, put the X4 base in sync mode →
  the 6-comma beacon and our ACK land in the log. Afterwards confirm the
  stock ThermoWorks receiver still updates.
- **V2.1:** all four probes in, leave it logging (overnight on the counter is
  ideal). While it runs: unplug/replug a probe (Q4), set a tight alarm band
  so it trips and stays tripped a few minutes (Q8), flip °F↔°C and back,
  short a probe jack then leave it open (rest of Q4), optionally stand a
  probe in hot water for a real curve.

Then normalize: `dart run lora:normalize <logfile> --name first-x4-capture`
and commit the outputs under `protocol/fixtures/lora/`.

**Part 2 — bench numbers with our diagnostic (V1.3, V1.4):**

```bash
make bench-flash          # or, from firmware/:
# idf.py -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3;sdkconfig.bench" build flash monitor
```

It prints `BENCH`-prefixed lines continuously: the GPIO37-gated VBAT reading
with both candidate ratios (hold a DMM on the pack at two charge levels —
that settles ×4.9 vs ×2.0), the Vext gate probe result, the I²C-under-Wi-Fi
error counter, button press/release events, and LED fade direction.
Transcribe them into [`docs/hardware-verified.md`](../../docs/hardware-verified.md)
— every box measured or explicitly unresolved, none silently blank.
