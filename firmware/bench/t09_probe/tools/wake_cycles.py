"""T09 hold-PRG wake test, 20 cycles.

Assumes the probe is in deep sleep. Each cycle asserts DTR for 2 s (the CP2102
auto-reset circuit drives the same GPIO0/PRG net), releases it, captures the
boot, and classifies the result as APP (application booted), ROM_DOWNLOAD (the
ROM downloader banner appeared), or NO_OUTPUT.

On a non-APP result it recovers with an EN/RTS reset and waits for the probe to
return to sleep. The raw per-cycle log and the CSV are written under
artifacts/bench/T09/probe/.
"""

import os
import serial
import time

PORT = os.environ.get("T09_PORT", "COM5")
BASE = os.path.join("artifacts", "bench", "T09", "probe")
CYCLES = 20
HOLD_S = 2.0

os.makedirs(BASE, exist_ok=True)
p = serial.Serial()
p.port = PORT
p.baudrate = 115200
p.timeout = 0.05
p.dtr = False
p.rts = False
p.open()

alllog = bytearray()
rows = []


def drain(seconds):
    end = time.time() + seconds
    b = bytearray()
    while time.time() < end:
        d = p.read(4096)
        if d:
            b += d
    return b


def reset_via_en():
    p.setDTR(False)
    p.setRTS(True)
    time.sleep(0.25)
    p.setRTS(False)


for i in range(1, CYCLES + 1):
    drain(0.2)  # confirm the probe is quiet (asleep)
    p.setDTR(True)
    time.sleep(HOLD_S)
    p.setDTR(False)

    b = bytearray()
    end = time.time() + 3.0
    while time.time() < end:
        d = p.read(4096)
        if d:
            b += d
            if b"SLEEP entering deep sleep" in b:
                time.sleep(0.5)
                b += drain(0.5)
                break
            if b"waiting for download" in b or b"DOWNLOAD_BOOT" in b:
                time.sleep(0.5)
                b += drain(0.5)
                break

    text = b.decode("utf-8", "replace")
    app = "WAKE " in text or "BOOT count=" in text
    download = "waiting for download" in text or "DOWNLOAD_BOOT" in text
    if app and not download:
        result = "APP"
    elif download:
        result = "ROM_DOWNLOAD"
    else:
        result = "NO_OUTPUT"
    rows.append((i, result))
    alllog += f"\n===== cycle {i}: {result} =====\n".encode()
    alllog += b
    print(f"cycle {i:02d}: {result}", flush=True)

    if result != "APP":
        reset_via_en()
        rb = drain(4.0)
        alllog += b"\n----- recovery reset -----\n" + rb
        if b"SLEEP entering deep sleep" not in rb:
            alllog += b"\n----- recovery extra -----\n" + drain(4.0)

p.close()
open(os.path.join(BASE, "wake-cycles-20.txt"), "wb").write(alllog)
with open(os.path.join(BASE, "wake-cycles-20.csv"), "w") as f:
    f.write("cycle,result\n")
    for i, r in rows:
        f.write(f"{i},{r}\n")
print("\nSUMMARY:", {r: sum(1 for _, x in rows if x == r) for _, r in rows})
