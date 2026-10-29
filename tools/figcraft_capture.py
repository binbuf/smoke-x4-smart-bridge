#!/usr/bin/env python3
"""Report copy edited in FigCraft against the exported screenshot baseline.

``tools/figcraft_export.py`` writes one editable text layer per text run and
keeps the source-of-truth text in ``design/figcraft/render/dump``. After copy is
edited in FigCraft (or in the app while attached), this prints exactly which
strings changed, so they can be applied to ``app/lib`` and the goldens
regenerated.

Usage (from the repository root):

    make design-capture
    tools/figcraft_capture.py --doc design/figcraft/render/smoke-x4-views.figcraft

Exit status is 1 when copy changed, so it also works as a check.
"""

from __future__ import annotations

import argparse
import json
import zipfile
from pathlib import Path

import figcraft_export as export


def load_document(path: Path) -> dict:
    """A .figcraft file is a zip with the layer tree in document.json."""
    with zipfile.ZipFile(path) as archive:
        return json.loads(archive.read("document.json"))


def text_layers(nodes: dict, root_id: int) -> list[dict]:
    """Text layers under a node, in creation/paint order."""
    out: list[dict] = []

    def walk(node_id: int) -> None:
        node = nodes.get(str(node_id))
        if node is None:
            return
        if node.get("type") == "text":
            out.append(node)
        for child in node.get("children", []):
            walk(child)

    walk(root_id)
    return out


def label_of(layer: dict) -> str:
    """The label ID a layer carries.

    Older exports parked the ID as the first line of the copy, which painted it
    over the screen. Newer ones keep it in the layer's plugin data and use it to
    start the layer name; the copy holds only the words the user reads.
    """
    plugin = (layer.get("pluginData") or {}).get("smoke_bridge") or {}
    if plugin.get("id"):
        return str(plugin["id"])
    name = layer.get("name", "")
    if ".figcraft" in name or " · " in name:
        return name.split(" · ")[0]
    text = layer.get("characters", "")
    first, _, rest = text.partition("\n")
    return first if rest and "." in first else ""


def copy_of(layer: dict) -> str:
    """The layer's copy as the user reads it."""
    text = layer.get("characters", "")
    if label_of(layer) and text.startswith(label_of(layer) + "\n"):
        return text.partition("\n")[2]
    return text


def exported_runs(name: str, image_path: Path) -> list[dict]:
    """The runs that actually became text layers for a view."""
    dump = json.loads((export.DUMP / f"{name}.json").read_text())
    from PIL import Image

    image = Image.open(image_path).convert("RGB")
    scale = image.width / export.FRAME_W
    kept = []
    for run in dump["runs"]:
        if run.get("icon") or not run["text"].strip():
            continue
        x, y, w, h = run["rect"]
        if w <= 0.5 or h <= 0.5:
            continue
        if x + w < 0 or y + h < 0 or x > export.FRAME_W or y > export.FRAME_H:
            continue
        if run["color"].endswith("00"):
            continue
        if not export.is_visible(image, run["rect"], run["color"], scale):
            continue
        kept.append(run)
    return kept


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--doc", type=Path, default=export.DEFAULT_OUT)
    parser.add_argument("--only", action="append", help="limit to these view names")
    args = parser.parse_args()

    document = load_document(args.doc)
    nodes = document["nodes"]
    pages = document["pages"]

    titles = {
        export.title_for(p.stem): p
        for p in sorted(export.SHOTS.glob("*.png"))
    }

    changed: list[tuple[str, str, str, str]] = []
    unknown: list[str] = []
    for page_id in pages:
        page = nodes.get(str(page_id))
        if page is None or page.get("type") != "page":
            continue
        shot = titles.get(page.get("name"))
        if shot is None:
            continue
        name = shot.stem
        if args.only and name not in set(args.only):
            continue
        baseline = exported_runs(name, shot)
        layers = text_layers(nodes, page_id)
        if len(layers) != len(baseline):
            unknown.append(
                f"{export.title_for(name)}: {len(layers)} text layers, "
                f"{len(baseline)} when exported"
            )
        for index, run in enumerate(baseline):
            if index >= len(layers):
                break
            layer = layers[index]
            old = run["text"]
            new = copy_of(layer)
            if new != old:
                changed.append((export.title_for(name), label_of(layer), old, new))
        for layer in layers[len(baseline):]:
            changed.append(
                (export.title_for(name), label_of(layer), "", copy_of(layer))
            )

    if unknown:
        for line in unknown:
            print(f"note: {line}")
    if not changed:
        print("No copy changes.")
        return 0

    for page, label, old, new in changed:
        if old:
            print(f"{page} · {label}\n  - {old}\n  + {new}")
        else:
            print(f"{page} · {label}\n  + {new}")
    print(f"\n{len(changed)} changed string(s).")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
