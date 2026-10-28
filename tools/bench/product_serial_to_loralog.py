#!/usr/bin/env python3
"""Convert a product-firmware serial log into a loralog v1 fixture.

The product image logs every accepted radio frame as two consecutive lines:

    I (1046273) sx4.radio: rx len=76 rssi=-48 snr=10 freq=918500000
    I (1046273) sx4.radio: payload="LMXC[\\,30,..." hex=...

This tool pairs those lines by timestamp and writes the same
``boot t_ms rssi snr dir class payload`` rows the bench probes produce. It is
read-only over the capture; the product image stays flashed.
"""
import argparse
import pathlib
import re

RX_RE = re.compile(
    r"^I \((?P<t>\d+)\) sx4\.radio: rx len=(?P<len>\d+) "
    r"rssi=(?P<rssi>-?\d+) snr=(?P<snr>-?\d+) freq=(?P<freq>\d+)$"
)
PAY_RE = re.compile(r'^I \((?P<t>\d+)\) sx4\.radio: payload="(?P<payload>.*)" hex=')


def classify(commas: int) -> str:
    return {
        2: "ack2",
        6: "sync6",
        26: "state26",
        16: "state16",
    }.get(commas, "other")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("serial_log")
    ap.add_argument("out")
    args = ap.parse_args()

    src = pathlib.Path(args.serial_log)
    out = pathlib.Path(args.out)

    pending = None
    rows = []
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        m = RX_RE.match(line)
        if m:
            pending = m.groupdict()
            continue
        p = PAY_RE.match(line)
        if not p:
            continue
        if pending is None or pending["t"] != p.group("t"):
            raise SystemExit(
                f"unpaired payload at t={p.group('t')} in {src}"
            )
        payload = p.group("payload")
        rows.append({
            "t": pending["t"],
            "rssi": pending["rssi"],
            "snr": pending["snr"],
            "dir": "rx",
            "cls": classify(payload.count(",")),
            "payload": payload,
        })
        pending = None

    lines = [
        "# loralog v1",
        f"# source: {src.as_posix()}",
        "# fields: boot t_ms rssi snr dir class payload",
    ]
    for r in rows:
        lines.append(
            f"0 {r['t']} {r['rssi']} {r['snr']} {r['dir']} {r['cls']} "
            f"{r['payload']}"
        )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(rows)} packets to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
