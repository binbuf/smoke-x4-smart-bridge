#!/usr/bin/env python3
"""Bench serial capture helper.

Opens the board's console without toggling DTR/RTS, optionally pulses EN to
reset, and appends every line to artifacts/bench/T10/serial-<stamp>.log by
default. Pass --out to capture a named evidence file (T37 uses this); the
parent directory is created. A USB power cut is written as a `# serial error:`
line instead of a traceback, so the capture stays usable as evidence.
"""
import argparse
import datetime as dt
import pathlib
import sys
import time

import serial


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM5")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parents[4]
    outdir = root / "artifacts" / "bench" / "T10"
    outdir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%dT%H%M%S")
    outpath = pathlib.Path(args.out) if args.out else outdir / f"serial-{stamp}.log"
    outpath.parent.mkdir(parents=True, exist_ok=True)

    ser = serial.Serial()
    ser.port = args.port
    ser.baudrate = args.baud
    ser.timeout = 0.2
    ser.dtr = False
    ser.rts = False
    ser.open()
    if args.reset:
        ser.rts = True
        time.sleep(0.15)
        ser.rts = False
        time.sleep(0.05)

    print(f"capturing {args.port} @ {args.baud} -> {outpath}", flush=True)
    with outpath.open("a", encoding="utf-8", errors="replace") as fh:
        fh.write(f"# opened {dt.datetime.now().isoformat(timespec='seconds')} "
                 f"port={args.port} baud={args.baud}\n")
        fh.flush()
        try:
            while True:
                try:
                    raw = ser.readline()
                except serial.SerialException as exc:
                    # A USB power cut removes the port. Keep the capture as
                    # evidence: record the error and close cleanly.
                    fh.write(f"# serial error: {exc}\n")
                    print(f"serial error: {exc}", file=sys.stderr, flush=True)
                    break
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                fh.write(line + "\n")
                fh.flush()
                print(line, flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            fh.write(f"# closed {dt.datetime.now().isoformat(timespec='seconds')}\n")
            ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
