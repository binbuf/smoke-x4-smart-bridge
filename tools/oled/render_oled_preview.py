#!/usr/bin/env python3
"""Render OLED framebuffer dumps to scaled PNGs (task F11a.2, design 07 §7.6).

Adapted from the reference's scripts/render_oled_preview.py (MIT — see
docs/reference/PROVENANCE.md). The reference re-implemented the firmware's
font in Python and drew sample text, which means the picture could agree
with the script while disagreeing with the firmware. This version renders
the *firmware's own output*: `firmware/test/test_app_ui` writes each
rendered snapshot as a raw 1 KB page-ordered buffer, and this script only
turns bytes into pixels. There is no second font, so there is nothing to
drift.

    make oled-preview                     # goldens -> firmware/test/goldens/oled/*.png
    python tools/oled/render_oled_preview.py --scale 6 some.fb

Which artifact is authoritative: the **.fb** is. The C host test compares
it byte-exact, so a one-pixel change is a red test. The PNG is how a human
reviews the change on a pull request — CI regenerates and uploads it. PNGs
are not diff-gated because deflate output is not stable across zlib
versions; gating them would produce failures that mean nothing.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

WIDTH = 128
HEIGHT = 64
PAGES = HEIGHT // 8
FB_BYTES = WIDTH * PAGES

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_DIR = REPO_ROOT / "firmware" / "test" / "goldens" / "oled"

# SSD1306 blue-on-black, so a reviewer sees roughly what the yard sees.
INK = (0x7A, 0xC6, 0xFF)
PAPER = (0x08, 0x0B, 0x12)
BEZEL = (0x30, 0x34, 0x3C)


def unpack_fb(data: bytes) -> bytearray:
    """Page-ordered 1 KB buffer -> one byte per pixel, row-major."""
    if len(data) != FB_BYTES:
        raise SystemExit(f"expected {FB_BYTES} bytes, got {len(data)}")
    pixels = bytearray(WIDTH * HEIGHT)
    for page in range(PAGES):
        for x in range(WIDTH):
            column = data[page * WIDTH + x]
            for bit in range(8):
                if (column >> bit) & 1:
                    pixels[(page * 8 + bit) * WIDTH + x] = 1
    return pixels


def _chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, pixels: bytearray, scale: int, border: int) -> None:
    w = WIDTH * scale + border * 2
    h = HEIGHT * scale + border * 2
    rows = []
    for sy in range(h):
        row = bytearray()
        inside_y = border <= sy < h - border
        for sx in range(w):
            inside_x = border <= sx < w - border
            if inside_y and inside_x:
                on = pixels[((sy - border) // scale) * WIDTH + (sx - border) // scale]
                row.extend(INK if on else PAPER)
            else:
                row.extend(BEZEL)
        rows.append(b"\x00" + bytes(row))

    header = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(_chunk(b"IHDR", header))
        fh.write(_chunk(b"IDAT", zlib.compress(b"".join(rows), 9)))
        fh.write(_chunk(b"IEND", b""))


def as_text(pixels: bytearray) -> str:
    """ASCII rendering, for a terminal or a failing-test log."""
    return "\n".join(
        "".join("#" if pixels[y * WIDTH + x] else "." for x in range(WIDTH))
        for y in range(HEIGHT)
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("inputs", nargs="*", type=Path, help=".fb dumps (default: goldens)")
    ap.add_argument("-o", "--out-dir", type=Path, help="default: alongside each input")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--border", type=int, default=4)
    ap.add_argument("--text", action="store_true", help="also print ASCII art")
    args = ap.parse_args()

    inputs = args.inputs or sorted(GOLDEN_DIR.glob("*.fb"))
    if not inputs:
        print(f"no .fb inputs (looked in {GOLDEN_DIR})", file=sys.stderr)
        return 1

    for src in inputs:
        pixels = unpack_fb(src.read_bytes())
        dst_dir = args.out_dir or src.parent
        dst = dst_dir / (src.stem + ".png")
        write_png(dst, pixels, args.scale, args.border)
        print(f"wrote {dst.relative_to(REPO_ROOT) if dst.is_relative_to(REPO_ROOT) else dst}")
        if args.text:
            print(as_text(pixels))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
