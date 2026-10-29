#!/usr/bin/env python3
"""Compare the approved screenshots with a fresh capture of the same screens.

The golden test says *whether* a screen changed; this says *what* changed. It
writes a 50% blend and an amplified delta for every scenario, plus an index page
sorted worst-first, so an intentional change can be reviewed before the baseline
is updated.

    make capture       # writes build/captures at 3x
    make design-diff   # writes build/scenario-diff

Both images are compared at the baseline's size (390 x 844); a 3x capture is
downscaled, which costs a small amount of resampling noise. The default
threshold of 4/255 mean per channel is above that noise and well below a real
layout or colour change.
"""

from __future__ import annotations

import argparse
import html
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "app" / "screenshots"
CAPTURE = ROOT / "build" / "captures"
OUT = ROOT / "build" / "scenario-diff"
AMPLIFY = 4.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=BASE, help="approved screenshots")
    parser.add_argument("--new", type=Path, default=CAPTURE, help="fresh captures")
    parser.add_argument("--out", type=Path, default=OUT, help="output directory")
    parser.add_argument("--ids", nargs="*", default=None, help="only these ids")
    parser.add_argument(
        "--fail-over",
        type=float,
        default=None,
        metavar="MEAN",
        help="exit 1 when any scenario's mean delta exceeds MEAN",
    )
    return parser.parse_args()


def delta_images(base: Image.Image, new: Image.Image) -> tuple[Image.Image, Image.Image, float, int]:
    """Overlay, amplified delta, mean delta, max delta."""
    overlay = Image.blend(base, new, 0.5)
    difference = ImageChops.difference(base, new)
    stats = ImageStat.Stat(difference)
    mean = sum(stats.mean) / len(stats.mean)
    maximum = max(channel[1] for channel in stats.extrema)
    amplified = difference.convert("L").point(
        lambda value: min(255, round(value * AMPLIFY))
    )
    return overlay, amplified, mean, maximum


def main() -> int:
    args = parse_args()
    if not args.base.is_dir():
        print(f"No baseline directory: {args.base}", file=sys.stderr)
        return 2
    if not args.new.is_dir():
        print(
            f"No captures in {args.new}. Run `make capture` first.",
            file=sys.stderr,
        )
        return 2

    wanted = set(args.ids) if args.ids else None
    rows: list[tuple[str, float, int, Path, Path, Path]] = []
    missing: list[str] = []
    unchanged = 0

    for base_path in sorted(args.base.glob("*.png")):
        name = base_path.stem
        if wanted is not None and name not in wanted:
            continue
        new_path = args.new / base_path.name
        if not new_path.is_file():
            missing.append(name)
            continue

        with Image.open(base_path) as base_file:
            base = base_file.convert("RGB")
        with Image.open(new_path) as new_file:
            new = new_file.convert("RGB")
        if new.size != base.size:
            new = new.resize(base.size, Image.LANCZOS)

        overlay, amplified, mean, maximum = delta_images(base, new)
        if mean < 0.01 and maximum == 0:
            unchanged += 1
            continue

        target = args.out / name
        target.mkdir(parents=True, exist_ok=True)
        overlay.save(target / "overlay.png", optimize=True)
        amplified.save(target / "delta.png", optimize=True)
        rows.append((name, mean, maximum, target, new_path, base_path))

    args.out.mkdir(parents=True, exist_ok=True)
    rows.sort(key=lambda row: row[1], reverse=True)

    changed = [row for row in rows if row[1] >= 0.01]
    print(f"Compared {len(rows) + unchanged + len(missing)} scenarios")
    if unchanged:
        print(f"  {unchanged} pixel-identical")
    if missing:
        print(f"  {len(missing)} with no capture: {', '.join(missing)}")
    if not changed:
        print("  nothing changed")
    else:
        print(f"\n{'scenario':40} {'mean':>7} {'max':>5}")
        for name, mean, maximum, *_ in changed:
            print(f"{name:40} {mean:7.2f} {maximum:5d}")

    _write_index(args.out, changed, missing)

    if args.fail_over is not None:
        over = [row for row in changed if row[1] > args.fail_over]
        if over:
            print(
                f"\n{len(over)} scenario(s) exceed {args.fail_over}/255 mean: "
                + ", ".join(row[0] for row in over),
                file=sys.stderr,
            )
            return 1
    return 0


def _write_index(
    out: Path,
    rows: list[tuple[str, float, int, Path, Path, Path]],
    missing: list[str],
) -> None:
    parts = [
        "<!doctype html><meta charset='utf-8'>",
        "<title>Scenario diff</title>",
        "<style>",
        "body{font:14px/1.4 -apple-system,Segoe UI,sans-serif;margin:24px;"
        "background:#151311;color:#eae4dc}",
        "h1{font-size:18px}table{border-collapse:collapse}",
        "td,th{padding:6px 10px;border-bottom:1px solid #2a2520;"
        "vertical-align:top;text-align:left}",
        "img{width:130px;border-radius:6px;display:block}",
        "code{color:#f0a07a}.warn{color:#e9a83e}",
        "</style>",
        "<h1>Scenario diff</h1>",
        "<p>Baseline | 50% blend | amplified delta.</p>",
        "<table><tr><th>Scenario</th><th>Baseline</th><th>Blend</th>"
        "<th>Delta</th><th>Mean / max</th></tr>",
    ]
    for name, mean, maximum, target, _new_path, base_path in rows:
        parts.append(
            "<tr>"
            f"<td><code>{html.escape(name)}</code></td>"
            f"<td><img src='file://{base_path}'></td>"
            f"<td><img src='file://{target / 'overlay.png'}'></td>"
            f"<td><img src='file://{target / 'delta.png'}'></td>"
            f"<td>{mean:.2f} / {maximum}</td>"
            "</tr>"
        )
    if missing:
        parts.append(
            "<tr><td colspan='5' class='warn'>No capture: "
            + html.escape(", ".join(missing))
            + "</td></tr>"
        )
    parts.append("</table>")
    (out / "index.html").write_text("\n".join(parts), encoding="utf-8")
    print(f"\nWrote {(out / 'index.html').relative_to(ROOT)}")


if __name__ == "__main__":
    raise SystemExit(main())
