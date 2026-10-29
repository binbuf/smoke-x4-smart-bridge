#!/usr/bin/env python3
"""Build the Experimental lab's contact sheet from the approved screenshots.

`app/screenshots` is the UI contract; the lab shows the same frames as
thumbnails so a reviewer can see every approved screen at once. Shipping the
full 390 x 844 images as assets would add megabytes to the APK, so this writes
small downscales to `app/assets/thumbs` instead.

Run it after approving a golden change:

    python3 tools/make_thumbs.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "app" / "screenshots"
DESTINATION = ROOT / "app" / "assets" / "thumbs"

# 3 columns across a 390 pt viewport leaves roughly 110 pt per cell; 120 px keeps
# the thumbnail crisp on a 3x display without a visible file size.
WIDTH = 120


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    sources = sorted(SOURCE.glob("*.png"))
    if not sources:
        raise SystemExit(f"No screenshots in {SOURCE}")

    for source in sources:
        with Image.open(source) as image:
            height = round(image.height * (WIDTH / image.width))
            thumb = image.convert("RGB").resize((WIDTH, height), Image.LANCZOS)
        # 256 colours is visually indistinguishable at this size and roughly a
        # sixth of the bytes of a full-colour PNG.
        thumb.quantize(colors=256, dither=Image.NONE).save(
            DESTINATION / source.name, optimize=True
        )

    wanted = {source.name for source in sources}
    removed = 0
    for stale in DESTINATION.glob("*.png"):
        if stale.name not in wanted:
            stale.unlink()
            removed += 1

    print(
        f"Wrote {len(sources)} thumbnails to "
        f"{DESTINATION.relative_to(ROOT)}"
        + (f", removed {removed} stale" if removed else "")
    )


if __name__ == "__main__":
    main()
