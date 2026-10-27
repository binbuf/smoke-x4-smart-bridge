#!/usr/bin/env python3
"""Convert an OLED .fb golden to a PNG for human review (T22).

The 1 KB page-ordered SSD1306 bytes remain the gate; this tool only makes them
eyeballable. It is dependency-free (Python standard library only).

    python tools/ui_fb_to_png.py firmware/test/goldens/ui
    python tools/ui_fb_to_png.py firmware/test/goldens/ui/01-probes-four.fb \
        --out artifacts/ui/01-probes-four.png --scale 4
"""

from __future__ import annotations

import argparse
import pathlib
import struct
import zlib

WIDTH = 128
HEIGHT = 64
FB_SIZE = WIDTH * HEIGHT // 8


def read_fb(path: pathlib.Path) -> bytes:
    data = path.read_bytes()
    if len(data) != FB_SIZE:
        raise SystemExit(f"{path}: expected {FB_SIZE} bytes, got {len(data)}")
    return data


def pixels(fb: bytes) -> list[list[int]]:
    """Return rows of 0/1 pixels. Page N holds display rows N*8 .. N*8+7."""
    rows = []
    for y in range(HEIGHT):
        page = y // 8
        bit = y % 8
        row = []
        for x in range(WIDTH):
            row.append(1 if fb[page * WIDTH + x] & (1 << bit) else 0)
        rows.append(row)
    return rows


def write_png(path: pathlib.Path, fb: bytes, scale: int) -> None:
    rows = pixels(fb)
    out_w = WIDTH * scale
    out_h = HEIGHT * scale
    raw = bytearray()
    for y in range(out_h):
        raw.append(0)  # PNG filter: none
        src = rows[y // scale]
        for x in range(out_w):
            raw.append(255 if src[x // scale] else 0)

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", out_w, out_h, 8, 0, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path, help=".fb file or directory")
    parser.add_argument("--out", type=pathlib.Path, help="output .png or directory")
    parser.add_argument("--scale", type=int, default=4, help="integer zoom (default 4)")
    args = parser.parse_args()
    if args.scale < 1:
        raise SystemExit("--scale must be >= 1")

    if args.input.is_dir():
        files = sorted(args.input.glob("*.fb"))
        if not files:
            raise SystemExit(f"{args.input}: no .fb files")
        out_dir = args.out or (args.input / "png")
        for fb_path in files:
            target = out_dir / (fb_path.stem + ".png")
            write_png(target, read_fb(fb_path), args.scale)
            print(target)
        return

    target = args.out or args.input.with_suffix(".png")
    write_png(target, read_fb(args.input), args.scale)
    print(target)


if __name__ == "__main__":
    main()
