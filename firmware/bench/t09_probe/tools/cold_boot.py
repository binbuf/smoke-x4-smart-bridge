"""T09 cold-boot capture: reset the probe and drive one PRG pulse via DTR.

Run from the repository root with the probe already flashed:

    <idf python> firmware/bench/t09_probe/tools/cold_boot.py

It resets through RTS, captures the boot log at 115200, asserts DTR (which is
the CP2102 auto-reset transistor's GPIO0/PRG net) for 400 ms when the probe
reaches its PRG window, and stops just after the probe enters deep sleep.
"""

import os
import serial
import sys
import time

PORT = os.environ.get("T09_PORT", "COM5")
BASE = os.path.join("artifacts", "bench", "T09", "probe")
OUT = os.path.join(BASE, "cold-boot-serial.txt")

os.makedirs(BASE, exist_ok=True)
p = serial.Serial()
p.port = PORT
p.baudrate = 115200
p.timeout = 0.05
p.dtr = False
p.rts = False
p.open()

buf = bytearray()
start = time.time()
p.setDTR(False)
p.setRTS(True)
time.sleep(0.25)
p.setRTS(False)

pulsed = False
while time.time() - start < 45:
    d = p.read(4096)
    if d:
        buf += d
        sys.stdout.buffer.write(d)
        sys.stdout.flush()
        if not pulsed and b"PRG_CHECK idle" in buf:
            time.sleep(0.4)
            print("\n[driver] DTR=1 (assert) for 400 ms", flush=True)
            p.setDTR(True)
            time.sleep(0.4)
            p.setDTR(False)
            print("[driver] DTR=0 (release)", flush=True)
            pulsed = True
    if pulsed and b"SLEEP entering deep sleep" in buf:
        time.sleep(0.5)
        break
p.close()
open(OUT, "wb").write(buf)
print("\n[driver] captured %d bytes -> %s" % (len(buf), OUT))
