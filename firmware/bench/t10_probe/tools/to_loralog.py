#!/usr/bin/env python3
"""Convert a T10 serial capture into a loralog v1 fixture (bench only)."""
import argparse
import pathlib
import re

RX_RE = re.compile(
    r"t10cap: RX t_ms=(?P<t>\d+) len=(?P<len>\d+) rssi=(?P<rssi>-?\d+) "
    r"snr=(?P<snr>-?\d+) commas=(?P<commas>\d+) class=(?P<cls>\w+)"
)
PAY_RE = re.compile(r't10cap: PAYLOAD ascii="(?P<payload>.*)"')
ACK_RE = re.compile(r"I \((\d+)\) t10cap: ACK_TX len=\d+ payload=(?P<payload>.*)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("serial_log")
    ap.add_argument("out")
    args = ap.parse_args()

    src = pathlib.Path(args.serial_log)
    out = pathlib.Path(args.out)
    rows = []
    pending = None
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        m = RX_RE.search(line)
        if m:
            pending = m.groupdict()
            continue
        p = PAY_RE.search(line)
        if p and pending:
            rows.append({
                "t": pending["t"],
                "rssi": pending["rssi"],
                "snr": pending["snr"],
                "dir": "rx",
                "cls": pending["cls"],
                "payload": p.group("payload"),
            })
            pending = None
            continue
        a = ACK_RE.search(line)
        if a:
            rows.append({
                "t": a.group(1),
                "rssi": "?",
                "snr": "?",
                "dir": "tx",
                "cls": "ack2",
                "payload": a.group("payload"),
            })

    lines = [
        "# loralog v1",
        f"# source: {src.as_posix()}",
        "# fields: boot t_ms rssi snr dir class payload",
    ]
    for r in rows:
        lines.append(
            f"0 {r['t']} {r['rssi']} {r['snr']} {r['dir']} {r['cls']} {r['payload']}"
        )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(rows)} packets to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
