#!/usr/bin/env python3
"""Export the approved Flutter screens into a FigCraft document.

The screenshots in ``app/screenshots`` are the production UI contract. This
tool keeps that contract exact while making the copy editable:

* each view becomes a page with its screenshot as the reference layer;
* every text run dumped from the real Flutter render tree (see the
  ``FIGCRAFT_DUMP`` branch in ``app/tool/ui_screenshots_test.dart``) is covered
  by a rectangle filled with the colour sampled around it, then redrawn as a
  FigCraft text layer at the same position, size and weight;
* icons, charts and every non-text pixel stay in the reference layer.

The result looks like the app but the words are selectable text, so copy can be
edited in FigCraft and diffed back into ``app/lib``.

Usage (from the repository root):

    make design-export           # dump + build design/figcraft/render/smoke-x4-views.figcraft
    tools/figcraft_export.py --only live_dark --out /tmp/one.figcraft
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RENDER = ROOT / "design" / "figcraft" / "render"
# 3x captures of the same render tree, written by the screenshot test next to
# the 1x goldens when FIGCRAFT_DUMP is set.
SHOTS = RENDER / "shots"
DUMP = RENDER / "dump"
DEFAULT_OUT = RENDER / "smoke-x4-views.figcraft"
DEFAULT_SHEET = RENDER / "text-ids.md"
FIGCRAFT = Path.home() / ".local" / "bin" / "figcraft-cli"

PAGE_BG = "#100E0C"
INDEX_COLUMNS = 5
INDEX_GAP_X = 64
INDEX_GAP_Y = 72
INDEX_LABEL_GAP = 12

# Flutter's logical canvas for every reference screenshot.
FRAME_W = 390
FRAME_H = 844

WEIGHT_NAMES = {
    100: "Thin",
    200: "Extra Light",
    300: "Light",
    400: "Regular",
    500: "Medium",
    600: "Semi Bold",
    700: "Bold",
    800: "Extra Bold",
    900: "Black",
}

# File name -> page title. Keeps the page list readable instead of showing
# snake_case file names.
TITLES = {
    "live_dark": "Live · dark",
    "live_light": "Live · light",
    "live_billows_detected": "Live · Billows detected",
    "live_billows_lost": "Live · Billows lost",
    "live_offline_cache": "Live · Offline with cache",
    "live_offline_nocache_dark": "Live · Offline without cache",
    "live_stale_dark": "Live · Stale reading",
    "live_x4_warning_dark": "Live · Smoke X warning",
    "history_dark": "History · dark",
    "history_light": "History · light",
    "history_custom_range_dark": "History · Custom range sheet",
    "history_all_dark": "History · All saved history",
    "history_cooks_dark": "History · Cooks",
    "history_filter_dark": "History · Filtered P1",
    "history_empty_dark": "History · Empty",
    "history_probe_empty_dark": "History · Probe empty",
    "history_storage_dark": "History · Storage dark",
    "history_storage_light": "History · Storage light",
    "history_fullscreen_dark": "History · Full screen",
    "past_cook_dark": "Past cook · dark",
    "past_cook_light": "Past cook · light",
    "settings_dark": "Settings · dark",
    "settings_light": "Settings · light",
    "bridge_details_dark": "Bridge details · dark",
    "bridge_details_light": "Bridge details · light",
    "appearance_dark": "Appearance · dark",
    "appearance_light": "Appearance · light",
    "setup_dark": "Setup · dark",
    "setup_light": "Setup · light",
    "passkey_dark": "Passkey instruction",
    "re_pair_dark": "Re-pair",
    "billows_settings_dark": "Billows settings",
    "device_log_dark": "History on this phone",
    "oled_page_dark": "Bridge OLED · overview",
    "oled_passkey_dark": "Bridge OLED · passkey",
    "confirm_factory_reset_dark": "Confirm · factory reset",
    "confirm_power_off_light": "Confirm · power off",
    "scenario_lab_dark": "Experimental lab",
}


# The document carries one set of views: the light theme wherever a design
# exists in both, plus the dark-only states (dialogs, the experimental lab, the
# Bridge OLED). Light and dark export the same labels, so the dark duplicates
# only split review across two pages.
LIGHT_BASELINE = {
    "history_storage_dark": "history_storage_light",
    "past_cook_dark": "past_cook_light",
}

# Source-only captures that never go into the hand-off document; History ·
# Storage light stands in for its dark twin.
DARK_ONLY = {
    "live_dark",
    "history_dark",
    "history_storage_dark",
    "past_cook_dark",
    "settings_dark",
    "bridge_details_dark",
    "appearance_dark",
    "setup_dark",
}


def view_names() -> list[str]:
    """The views that become pages, in file order."""
    names = sorted(p.stem for p in SHOTS.glob("*.png"))
    return [n for n in names if n not in DARK_ONLY]


def title_for(name: str) -> str:
    return TITLES.get(name, name.replace("_", " ").capitalize())


def parse_colour(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def is_visible(
    image: Image.Image, rect: list[float], colour: str, scale: float
) -> bool:
    """Whether the run's ink is actually visible in the approved screenshot.

    Flutter lays out everything behind the bottom navigation bar and behind
    sheets. Those runs must not be covered or redrawn: the screenshot already
    shows what is on top. Ink coverage distinguishes a painted run (roughly
    12-25% of its box in the text colour) from one hidden behind another
    surface (near zero).
    """
    x, y, w, h = rect
    box = (
        max(0, int(round(x * scale))),
        max(0, int(round(y * scale))),
        min(image.width, int(round((x + w) * scale))),
        min(image.height, int(round((y + h) * scale))),
    )
    if box[2] <= box[0] or box[3] <= box[1]:
        return False
    target = parse_colour(colour)
    crop = image.crop(box)
    pixels = list(crop.getdata())
    if not pixels:
        return False
    hits = sum(
        1
        for pixel in pixels
        if sum((pixel[i] - target[i]) ** 2 for i in range(3)) < 60 * 60
    )
    return hits / len(pixels) >= 0.09


def weight_name(weight: int) -> str:
    return WEIGHT_NAMES[min(WEIGHT_NAMES, key=lambda w: abs(w - weight))]


def hex_rgb(rgb: tuple[int, int, int]) -> str:
    return "#%02X%02X%02X" % rgb


def _ring_pixels(image: Image.Image, box: tuple[float, float, float, float], pad: int):
    """Pixels in the border ring around ``box`` (screenshot pixels)."""
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    width, height = image.size
    ox0, oy0 = max(0, x0 - pad), max(0, y0 - pad)
    ox1, oy1 = min(width, x1 + pad), min(height, y1 + pad)
    for y in range(oy0, oy1):
        for x in range(ox0, ox1):
            if x0 - pad < x < x1 + pad and y0 - pad < y < y1 + pad:
                # Skip the text's own box: antialiased glyphs bias the sample.
                if x0 <= x < x1 and y0 <= y < y1:
                    continue
            yield image.getpixel((x, y))


def patch_colour(image: Image.Image, rect: list[float], scale: float) -> str:
    """The flat colour behind a text run, sampled from the ring around it."""
    x, y, w, h = rect
    box = (x * scale, y * scale, (x + w) * scale, (y + h) * scale)
    pad = max(2, int(round(2 * scale)))
    pixels = list(_ring_pixels(image, box, pad))
    if not pixels:
        inner = image.crop(tuple(int(round(v)) for v in box))
        pixels = list(inner.getdata())
    if not pixels:
        return PAGE_BG
    # Quantise slightly so antialiasing and screenshot compression do not split
    # one flat background across many near-identical buckets.
    quantised = Counter((r // 4, g // 4, b // 4) for r, g, b in pixels)
    bucket, _ = quantised.most_common(1)[0]
    candidates = [p for p in pixels if (p[0] // 4, p[1] // 4, p[2] // 4) == bucket]
    r = sum(p[0] for p in candidates) // len(candidates)
    g = sum(p[1] for p in candidates) // len(candidates)
    b = sum(p[2] for p in candidates) // len(candidates)
    return hex_rgb((r, g, b))


def is_multiline(run: dict, rect: list[float]) -> bool:
    if "\n" in run["text"]:
        return True
    line_height = run.get("lineHeight") or 0
    return line_height > 0 and rect[3] > line_height * 1.5


def text_layer(run: dict) -> dict | None:
    text = run["text"]
    if not text.strip():
        return None
    if run.get("icon"):
        return None
    colour = run["color"]
    if colour.endswith("00"):
        return None

    x, y, w, h = run["rect"]
    paragraph = run["paragraph"]
    align = run.get("align", "left")
    multiline = is_multiline(run, run["rect"])
    props: dict[str, object] = {
        "fontFamily": "Roboto",
        "fontStyle": weight_name(run["fontWeight"]),
        "fontSize": run["fontSize"],
        "fill": colour,
        "textAlign": align,
        "textAutoResize": "height",
    }
    if run.get("lineHeight"):
        props["lineHeight"] = round(run["lineHeight"], 2)
    if run.get("letterSpacing"):
        props["letterSpacing"] = round(run["letterSpacing"], 3)

    x_pos = x
    # Always pin the width. FigCraft measures auto-width text before it applies
    # the creation props (so 42px numbers were being wrapped into 14px boxes);
    # a fixed width laid out with the real size avoids that.
    if multiline or align in ("center", "right"):
        # Keep the paragraph's own box so alignment and wrapping match Flutter.
        x_pos = paragraph[0]
        width = paragraph[2]
    else:
        # Single line: a little slack protects against small face differences.
        width = w * 1.08 + 3

    params: dict[str, object] = {
        "type": "text",
        "text": text,
        "x": round(x_pos, 2),
        "y": round(y, 2),
        "name": text.strip().replace("\n", " ")[:60] or "Text",
        "props": props,
    }
    if width:
        params["width"] = round(width, 2)
    return params

def build_clean_image(name: str, image_path: Path) -> Path:
    """The screenshot with visible text painted out, keeping the layout.

    Baking the cleanup into the reference image means an edited FigCraft text
    layer never leaves the old words showing underneath, even when the new copy
    is longer than the old.
    """
    dump = json.loads((DUMP / f"{name}.json").read_text())
    image = Image.open(image_path).convert("RGB")
    source = image.copy()
    scale = image.width / FRAME_W
    draw = ImageDraw.Draw(image)
    for run in dump["runs"]:
        if run.get("icon") or not run["text"].strip():
            continue
        if run["color"].endswith("00"):
            continue
        x, y, w, h = run["rect"]
        if w <= 0.5 or h <= 0.5:
            continue
        if x + w < 0 or y + h < 0 or x > FRAME_W or y > FRAME_H:
            continue
        if not is_visible(source, run["rect"], run["color"], scale):
            continue
        pad = 0.5
        box = (
            max(0, int(round((x - pad) * scale))),
            max(0, int(round((y - pad) * scale))),
            min(image.width, int(round((x + w + pad) * scale))),
            min(image.height, int(round((y + h + pad) * scale))),
        )
        if box[2] <= box[0] or box[3] <= box[1]:
            continue
        draw.rectangle(box, fill=patch_colour(source, run["rect"], scale))

    clean_dir = RENDER / "clean"
    clean_dir.mkdir(parents=True, exist_ok=True)
    clean_path = clean_dir / f"{name}.png"
    image.save(clean_path)
    return clean_path


def _slug(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:24].rstrip("-") or "x"


def text_entries(name: str, dump: dict, image: Image.Image) -> list[dict]:
    """The runs that become text layers, each with its stable ID.

    Every view has its own namespace, so an ID identifies one label on one
    screen: ``live_light.03.temp-value``. The ordinal follows paint order; the
    slug comes from the copy. The ID never goes into the copy, because the copy
    is what the layer renders on the approved screenshot. It is the start of the
    layer name (so the layers panel and Cmd+F find it) and is stored as plugin
    data on the layer, which leaves the canvas exactly as approved.
    """
    scale = image.width / FRAME_W
    entries: list[dict] = []
    for run in dump["runs"]:
        if run.get("icon") or not run["text"].strip():
            continue
        x, y, w, h = run["rect"]
        if w <= 0.5 or h <= 0.5:
            continue
        if x + w < 0 or y + h < 0 or x > FRAME_W or y > FRAME_H:
            continue
        if run["color"].endswith("00"):
            continue
        if not is_visible(image, run["rect"], run["color"], scale):
            continue
        layer = text_layer(run)
        if layer is None:
            continue
        label = f"{name}.{len(entries) + 1:02d}.{_slug(run['text'])}"
        layer["name"] = f"{label} · {run['text'].strip()[:48]}"
        entries.append({"id": label, "run": run, "layer": layer})
    return entries


def build_page(
    name: str, image_path: Path, entries: list[dict] | None = None
) -> list[dict]:
    """One page: cleaned reference image and editable text layers."""
    dump = json.loads((DUMP / f"{name}.json").read_text())
    image = Image.open(image_path).convert("RGB")
    clean_path = build_clean_image(name, image_path)
    if entries is None:
        entries = text_entries(name, dump, image)

    commands: list[dict] = []
    commands.append({"command": "page.add", "as": "page", "params": {"name": title_for(name)}})
    commands.append(
        {
            "command": "page.setBackground",
            "params": {"id": {"$ref": "page"}, "color": PAGE_BG},
        }
    )
    commands.append(
        {
            "command": "node.create",
            "as": "screen",
            "params": {
                "type": "frame",
                "x": 0,
                "y": 0,
                "width": FRAME_W,
                "height": FRAME_H,
                "name": title_for(name),
                "props": {"fill": PAGE_BG, "clip": True},
            },
        }
    )
    commands.append(
        {
            "command": "image.place",
            "params": {
                "path": str(clean_path),
                "parent": {"$ref": "screen"},
                "x": 0,
                "y": 0,
                "width": FRAME_W,
                "height": FRAME_H,
                "mode": "fill",
            },
        }
    )

    for entry in entries:
        layer = dict(entry["layer"])
        layer["parent"] = {"$ref": "screen"}
        commands.append({"command": "node.create", "params": layer})
    return commands


def build_index(names: list[str]) -> list[dict]:
    commands: list[dict] = [
        {"command": "page.list", "as": "pages"},
        {
            "command": "page.rename",
            "params": {
                "id": {"$ref": "pages", "field": "0/id"},
                "name": "Index",
            },
        },
    ]
    for i, source in enumerate(names):
        name = LIGHT_BASELINE.get(source, source)
        column = i % INDEX_COLUMNS
        row = i // INDEX_COLUMNS
        frame_h = FRAME_H + 36
        x = 48 + column * (FRAME_W + INDEX_GAP_X)
        y = 48 + row * (frame_h + INDEX_GAP_Y)
        ref = f"frame_{i}"
        commands.append(
            {
                "command": "node.create",
                "as": ref,
                "params": {
                    "type": "frame",
                    "x": x,
                    "y": y,
                    "width": FRAME_W,
                    "height": frame_h,
                    "name": title_for(name),
                    "props": {"fill": PAGE_BG, "clip": True},
                },
            }
        )
        commands.append(
            {
                "command": "image.place",
                "params": {
                    "path": str(SHOTS / f"{name}.png"),
                    "parent": {"$ref": ref},
                    "x": 0,
                    "y": 0,
                    "width": FRAME_W,
                    "height": FRAME_H,
                    "mode": "fill",
                },
            }
        )
        commands.append(
            {
                "command": "node.create",
                "params": {
                    "type": "text",
                    "parent": {"$ref": ref},
                    "x": 0,
                    "y": FRAME_H + 10,
                    "text": title_for(name),
                    "name": title_for(name),
                    "props": {
                        "fontFamily": "Roboto",
                        "fontStyle": "Medium",
                        "fontSize": 14,
                        "fill": "#B9AFA6FF",
                    },
                },
            }
        )
    return commands


def write_copy_sheet(entries_by_view: dict[str, list[dict]], path: Path) -> None:
    """A review sheet: every label ID, the words it currently shows, where.

    One table per view so the copy can be read, chosen and rewritten outside
    FigCraft. The document stays the source of truth for unedited labels; this
    sheet is the checklist and the record of the current state.
    """
    lines = [
        "# Text label IDs",
        "",
        "Generated by `make design-export` — do not hand-edit.",
        "Each row is one text layer in `design/figcraft/render/smoke-x4-views.figcraft`.",
        "The ID is the layer's first line of copy and the start of its layer name.",
        "",
    ]
    for name, entries in entries_by_view.items():
        lines += [
            f"## {title_for(name)}",
            "",
            "| ID | Text | Position (x, y) |",
            "| --- | --- | --- |",
        ]
        for entry in entries:
            text = entry["run"]["text"].replace("|", "\\|").replace("\n", "⏎")
            x, y = entry["run"]["rect"][0], entry["run"]["rect"][1]
            lines.append(f"| `{entry['id']}` | {text} | {x:.0f}, {y:.0f} |")
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", help="export just these view names")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--skip-index", action="store_true")
    parser.add_argument("--script", type=Path, help="also write the JSON script here")
    parser.add_argument("--sheet", type=Path, default=DEFAULT_SHEET, help="write the label ID sheet here")
    args = parser.parse_args()

    all_names = view_names()
    names = all_names
    if args.only:
        wanted = set(args.only)
        missing = wanted - set(names)
        if missing:
            parser.error(f"unknown view(s): {', '.join(sorted(missing))}")
        names = [n for n in names if n in wanted]

    script: list[dict] = []
    script.append({"command": "file.new", "params": {"name": "Smoke X4 Smart Bridge · Views"}})
    if not args.skip_index:
        script.append(
            {
                "command": "command.batch",
                "params": {"label": "Index", "commands": build_index(all_names)},
            }
        )

    entries_by_view: dict[str, list[dict]] = {}
    for name in names:
        image_path = SHOTS / f"{name}.png"
        image = Image.open(image_path).convert("RGB")
        dump = json.loads((DUMP / f"{name}.json").read_text())
        entries = text_entries(name, dump, image)
        entries_by_view[name] = entries
        commands = build_page(name, image_path, entries)
        script.append({"command": "command.batch", "params": {"label": title_for(name), "commands": commands}})
    if not args.only:
        write_copy_sheet(entries_by_view, args.sheet)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    script_path = args.script or (RENDER / "export-script.json")
    script_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.write_text(json.dumps(script, indent=1) + "\n")

    result = subprocess.run(
        [str(FIGCRAFT), "run", str(script_path), "--out", str(args.out)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode
    failures = [line for line in result.stdout.splitlines() if '"ok":false' in line]
    if failures:
        sys.stderr.write("\n".join(failures[:10]) + "\n")
        return 1
    print(f"wrote {args.out} ({args.out.stat().st_size / 1_000_000:.1f} MB, {len(names)} views)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
