#!/usr/bin/env python3
"""Extract the T37 30-minute cadence report from a product serial capture.

The starting point was `firmware/bench/t10_probe/tools/to_loralog.py`: it parses
the T10 probe's `t10cap: RX ...` lines.  This tool adds the product log format
(`sx4.radio: rx ...` followed by `sx4.sample: stored seq=...`) and turns the
capture into the committed T37 cadence report.

What it measures
----------------
* packets (stored samples) versus the nominal 30 s cadence;
* min/mean/max observed interval between consecutive samples;
* every interval greater than 90 s, plus a row for every bridge restart;
* RSSI min/mean/max for the samples that carry a radio reading;
* missing sequence numbers and samples with no RSSI.

Times inside one boot come from the ESP-IDF log timestamp (`I (12345)`), which
is the device uptime and is not affected by serial latency.  Wall time starts
and ends come from the capture helper's `# opened`/`# closed` markers.  A
restart resets the log clock, so intervals are never computed across a restart;
the restart gets its own gap row instead.

Use from the repository root:

    python tools/bench/cadence_report.py artifacts/bench/T37/06-cadence.log \
        --out artifacts/bench/T37/CADENCE-REPORT.md

The measured columns are generated; the template's cause column and display
rows stay for the T37 sitting to fill from real observations.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

NOMINAL_CADENCE_S = 30.0
GAP_THRESHOLD_S = 90.0

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TEMPLATE = ROOT / "artifacts" / "bench" / "T37" / "CADENCE-REPORT-TEMPLATE.md"

# ESP-IDF lines look like `I (12345) tag: msg`; a few serial captures lose the
# level/tag prefix (`(12345) msg`).  Both are accepted.
TIMESTAMP_RE = re.compile(r"^\s*(?:[IWEDV]\s*)?\((?P<ms>\d+)\)\s")

# Product firmware (T21/T25): one accepted state frame, then its stored record.
PRODUCT_RX_RE = re.compile(
    r"\bsx4\.radio:\s+rx\s+len=(?P<length>\d+)\s+"
    r"rssi=(?P<rssi>-?\d+)\s+snr=(?P<snr>-?\d+)"
)
PRODUCT_STORED_RE = re.compile(r"\bsx4\.sample:\s+stored\s+seq=(?P<seq>\d+)\b")

# T10 probe capture: `t10cap: RX t_ms=... len=... rssi=... ... class=state26`.
# Older lines sometimes lose the `t10cap:` prefix, so it is optional.
T10_RX_RE = re.compile(
    r"\b(?:t10cap:\s+)?RX\s+t_ms=(?P<t_ms>\d+)\s+len=(?P<length>\d+)\s+"
    r"rssi=(?P<rssi>-?\d+)\s+snr=(?P<snr>-?\d+)"
    r"(?:\s+commas=(?P<commas>\d+))?"
    r"(?:\s+class=(?P<cls>\w+))?"
)

OPENED_RE = re.compile(r"^#\s*opened\s+(?P<stamp>\S+)")
CLOSED_RE = re.compile(r"^#\s*closed\s+(?P<stamp>\S+)")


@dataclass
class Sample:
    """One accepted state frame represented in the log."""

    epoch: int
    t_ms: int
    seq: int | None
    rssi: int | None
    snr: int | None
    line: int
    source: str  # "product" or "t10"


@dataclass
class Capture:
    path: Path
    opened: datetime | None
    closed: datetime | None
    samples: list[Sample]
    radio_packets: int
    boot_count: int
    warnings: list[str]


def _iso(stamp: str) -> datetime | None:
    try:
        return datetime.fromisoformat(stamp)
    except ValueError:
        return None


def parse_capture(path: Path) -> Capture:
    """Parse a product or T10 serial capture without touching the hardware."""
    text = path.read_text(encoding="utf-8", errors="replace")
    opened: datetime | None = None
    closed: datetime | None = None
    product: list[Sample] = []
    t10: list[Sample] = []
    warnings: list[str] = []
    radio_packets = 0
    epoch = 0
    boot_count = 1
    last_ts_ms: int | None = None
    pending_rx: tuple[int, int, int, int] | None = None  # epoch, ts, rssi, snr

    for lineno, line in enumerate(text.splitlines(), 1):
        m = OPENED_RE.match(line)
        if m:
            opened = _iso(m.group("stamp"))
            continue
        m = CLOSED_RE.match(line)
        if m:
            closed = _iso(m.group("stamp"))
            continue

        # A boot banner starts a new uptime clock.  `rst:` follows `ESP-ROM:`
        # on the same boot, so only the first marker after activity counts.
        if line.startswith("ESP-ROM:") or "rst:0x" in line[:40]:
            if last_ts_ms is not None:
                epoch += 1
                boot_count += 1
                last_ts_ms = None
                pending_rx = None
            continue

        m = TIMESTAMP_RE.match(line)
        if not m:
            continue
        ts = int(m.group("ms"))
        if last_ts_ms is not None and ts + 1000 < last_ts_ms:
            warnings.append(
                f"line {lineno}: log clock went backwards without a boot "
                "banner; treated as a restart"
            )
            epoch += 1
            boot_count += 1
            pending_rx = None
        last_ts_ms = ts

        m = PRODUCT_RX_RE.search(line)
        if m:
            radio_packets += 1
            pending_rx = (epoch, ts, int(m.group("rssi")), int(m.group("snr")))
            continue

        m = PRODUCT_STORED_RE.search(line)
        if m:
            rssi: int | None = None
            snr: int | None = None
            if pending_rx is not None and pending_rx[0] == epoch:
                px_ts = pending_rx[1]
                # The sample log line follows the RX line by a few ms; do not
                # attach a stale packet from an earlier frame.
                if 0 <= ts - px_ts <= 5000:
                    rssi = pending_rx[2]
                    snr = pending_rx[3]
            product.append(
                Sample(
                    epoch=epoch,
                    t_ms=ts,
                    seq=int(m.group("seq")),
                    rssi=rssi,
                    snr=snr,
                    line=lineno,
                    source="product",
                )
            )
            pending_rx = None
            continue

        m = T10_RX_RE.search(line)
        if m:
            radio_packets += 1
            cls = m.group("cls")
            commas = m.group("commas")
            # Count state frames only: the sync beacon and ACK are not samples.
            # Without a class, the X4 state frame is the 26-comma payload.
            if cls is not None and cls != "state26":
                continue
            if cls is None and commas not in (None, "26"):
                continue
            t10.append(
                Sample(
                    epoch=epoch,
                    t_ms=int(m.group("t_ms")),
                    seq=None,
                    rssi=int(m.group("rssi")),
                    snr=int(m.group("snr")),
                    line=lineno,
                    source="t10",
                )
            )

    if product and t10:
        warnings.append(
            "capture contains both product and T10 sample lines; product lines "
            "were used"
        )
    samples = product if product else t10
    if not samples:
        warnings.append(
            "no stored product samples and no T10 state frames matched; "
            "check the capture format"
        )
    return Capture(
        path=path,
        opened=opened,
        closed=closed,
        samples=samples,
        radio_packets=radio_packets,
        boot_count=boot_count,
        warnings=warnings,
    )


def _sample_label(sample: Sample) -> str:
    if sample.seq is not None:
        return f"seq {sample.seq}"
    return f"t={sample.t_ms / 1000.0:.1f}s"


def analyze(
    capture: Capture,
    cadence_s: float = NOMINAL_CADENCE_S,
    gap_threshold_s: float = GAP_THRESHOLD_S,
) -> dict:
    """Turn a capture into the numbers the report template needs."""
    samples = sorted(capture.samples, key=lambda s: (s.epoch, s.t_ms))
    warnings = list(capture.warnings)

    by_epoch: dict[int, list[Sample]] = {}
    for sample in samples:
        by_epoch.setdefault(sample.epoch, []).append(sample)

    intervals: list[dict] = []
    gaps: list[dict] = []
    for epoch in sorted(by_epoch):
        rows = by_epoch[epoch]
        for before, after in zip(rows, rows[1:]):
            delta_s = (after.t_ms - before.t_ms) / 1000.0
            intervals.append(
                {
                    "epoch": epoch,
                    "after": _sample_label(before),
                    "before": _sample_label(after),
                    "seconds": delta_s,
                }
            )
            if delta_s > gap_threshold_s:
                gaps.append(
                    {
                        "kind": "radio",
                        "after": _sample_label(before),
                        "before": _sample_label(after),
                        "seconds": delta_s,
                        "cause": "_unrecorded — fill at T37_",
                    }
                )

    restart_count = 0
    epochs = sorted(by_epoch)
    for left, right in zip(epochs, epochs[1:]):
        restart_count += 1
        gaps.append(
            {
                "kind": "restart",
                "after": f"boot {left + 1} {_sample_label(by_epoch[left][-1])}",
                "before": f"boot {right + 1} {_sample_label(by_epoch[right][0])}",
                "seconds": None,
                "cause": (
                    "bridge restart — confirm cause (manual reset, watchdog, "
                    "power cut)"
                ),
            }
        )

    span_s = sum(
        (rows[-1].t_ms - rows[0].t_ms) / 1000.0 for rows in by_epoch.values()
    )
    wall_s: float | None = None
    if capture.opened is not None and capture.closed is not None:
        wall_s = (capture.closed - capture.opened).total_seconds()
        if wall_s <= 0:
            warnings.append("capture close time is not after its open time")
            wall_s = None
    if wall_s is None:
        wall_s = span_s
        if capture.opened is not None or capture.closed is not None:
            warnings.append(
                "capture has no usable # opened/# closed pair; expected count "
                "uses the first-to-last sample span"
            )

    sample_count = len(samples)
    expected = int((wall_s + cadence_s / 2.0) // cadence_s) if samples else 0
    missed = max(0, expected - sample_count)

    if intervals:
        seconds = [row["seconds"] for row in intervals]
        interval_min = min(seconds)
        interval_max = max(seconds)
        interval_mean = sum(seconds) / len(seconds)
    else:
        interval_min = interval_mean = interval_max = None

    rssis = [s.rssi for s in samples if s.rssi is not None]
    if rssis:
        rssi_min = min(rssis)
        rssi_max = max(rssis)
        rssi_mean = sum(rssis) / len(rssis)
    else:
        rssi_min = rssi_max = rssi_mean = None
        if samples:
            warnings.append("no sample had an associated rssi reading")

    seqs = [s.seq for s in samples if s.seq is not None]
    missing_seq: list[int] = []
    first_seq = last_seq = None
    if seqs:
        first_seq, last_seq = seqs[0], seqs[-1]
        if any(b <= a for a, b in zip(seqs, seqs[1:])):
            warnings.append(
                "sequence numbers are not strictly increasing; check the log "
                "for interleaved or duplicated records"
            )
        seen = set(seqs)
        if last_seq >= first_seq:
            missing_seq = [n for n in range(first_seq, last_seq + 1) if n not in seen]
        if len(seqs) != len(set(seqs)):
            warnings.append("duplicate sequence numbers in the capture")

    if restart_count:
        warnings.append(
            f"{restart_count} bridge restart(s): intervals spanning a restart "
            "are excluded and each restart is listed as a gap"
        )
    if sample_count and expected > sample_count:
        warnings.append(
            f"{expected - sample_count} fewer samples than the nominal cadence "
            "over the capture window"
        )

    return {
        "capture": capture.path.as_posix(),
        "opened": capture.opened.isoformat(timespec="seconds")
        if capture.opened
        else None,
        "closed": capture.closed.isoformat(timespec="seconds")
        if capture.closed
        else None,
        "wall_seconds": wall_s,
        "span_seconds": span_s,
        "sample_count": sample_count,
        "expected_count": expected,
        "missed_count": missed,
        "radio_packet_count": capture.radio_packets,
        "interval_count": len(intervals),
        "interval_min": interval_min,
        "interval_mean": interval_mean,
        "interval_max": interval_max,
        "gap_threshold_s": gap_threshold_s,
        "gap_count": sum(1 for g in gaps if g["kind"] == "radio"),
        "restart_count": restart_count,
        "gaps": gaps,
        "rssi_min": rssi_min,
        "rssi_mean": rssi_mean,
        "rssi_max": rssi_max,
        "first_seq": first_seq,
        "last_seq": last_seq,
        "missing_seq": missing_seq,
        "boot_count": capture.boot_count,
        "warnings": warnings,
    }


def _fmt_seconds(value: float | None) -> str:
    return "—" if value is None else f"{value:.1f} s"


def _fmt_rssi(value: float | int | None) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.1f} dBm"
    return f"{value} dBm"


def _gaps_table(gaps: list[dict]) -> str:
    if not gaps:
        return "_No interval > 90 s and no bridge restart in this capture._"
    lines = [
        "| # | Between | Gap | Cause |",
        "|---|---|---|---|",
    ]
    for index, gap in enumerate(gaps, 1):
        seconds = (
            f"{gap['seconds']:.1f} s"
            if gap["seconds"] is not None
            else "unknown (restart)"
        )
        lines.append(
            f"| {index} | {gap['after']} → {gap['before']} | {seconds} | "
            f"{gap['cause']} |"
        )
    return "\n".join(lines)


def _warnings_block(warnings: list[str]) -> str:
    if not warnings:
        return "_None._"
    return "\n".join(f"- {warning}" for warning in warnings)


def render_markdown(analysis: dict, template: str) -> str:
    """Fill the committed report template; fail loudly on stale placeholders."""
    values = {
        "CAPTURE": analysis["capture"],
        "OPENED": analysis["opened"] or "—",
        "CLOSED": analysis["closed"] or "—",
        "WALL_DURATION": _fmt_seconds(analysis["wall_seconds"]),
        "OBSERVED_SPAN": _fmt_seconds(analysis["span_seconds"]),
        "SAMPLE_COUNT": str(analysis["sample_count"]),
        "EXPECTED_COUNT": str(analysis["expected_count"]),
        "MISSED_COUNT": str(analysis["missed_count"]),
        "RADIO_PACKET_COUNT": str(analysis["radio_packet_count"]),
        "INTERVAL_MIN": _fmt_seconds(analysis["interval_min"]),
        "INTERVAL_MEAN": _fmt_seconds(analysis["interval_mean"]),
        "INTERVAL_MAX": _fmt_seconds(analysis["interval_max"]),
        "GAP_THRESHOLD": _fmt_seconds(analysis["gap_threshold_s"]),
        "GAP_COUNT": str(analysis["gap_count"]),
        "RESTART_COUNT": str(analysis["restart_count"]),
        "BOOT_COUNT": str(analysis["boot_count"]),
        "RSSI_MIN": _fmt_rssi(analysis["rssi_min"]),
        "RSSI_MEAN": _fmt_rssi(analysis["rssi_mean"]),
        "RSSI_MAX": _fmt_rssi(analysis["rssi_max"]),
        "FIRST_SEQ": "—" if analysis["first_seq"] is None else str(analysis["first_seq"]),
        "LAST_SEQ": "—" if analysis["last_seq"] is None else str(analysis["last_seq"]),
        "MISSING_SEQ": (
            ", ".join(str(n) for n in analysis["missing_seq"])
            if analysis["missing_seq"]
            else "none"
        ),
        "GAPS_TABLE": _gaps_table(analysis["gaps"]),
        "WARNINGS": _warnings_block(analysis["warnings"]),
    }
    rendered = template
    for key, value in values.items():
        rendered = rendered.replace("{{" + key + "}}", value)

    leftovers = sorted(set(re.findall(r"\{\{[A-Z_]+\}\}", rendered)))
    if leftovers:
        raise ValueError(
            "template has placeholders with no value: " + ", ".join(leftovers)
        )
    return rendered if rendered.endswith("\n") else rendered + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("capture", type=Path, help="product or T10 serial log")
    parser.add_argument(
        "--template",
        type=Path,
        default=DEFAULT_TEMPLATE,
        help=f"report template (default: {DEFAULT_TEMPLATE})",
    )
    parser.add_argument("--out", type=Path, help="write the report here")
    parser.add_argument(
        "--cadence",
        type=float,
        default=NOMINAL_CADENCE_S,
        help="nominal cadence in seconds (default: 30)",
    )
    parser.add_argument(
        "--gap-threshold",
        type=float,
        default=GAP_THRESHOLD_S,
        help="visible-gap threshold in seconds (default: 90)",
    )
    args = parser.parse_args(argv)

    if not args.capture.is_file():
        parser.error(f"capture not found: {args.capture}")
    if not args.template.is_file():
        parser.error(f"template not found: {args.template}")

    capture = parse_capture(args.capture)
    analysis = analyze(capture, args.cadence, args.gap_threshold)
    report = render_markdown(analysis, args.template.read_text(encoding="utf-8"))

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        # Windows consoles often default to cp1252; the report contains ⏳ and
        # typographic dashes, so write UTF-8 bytes rather than relying on the
        # process code page.
        sys.stdout.buffer.write(report.encode("utf-8"))

    if analysis["sample_count"] == 0:
        print("error: no samples found in the capture", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
