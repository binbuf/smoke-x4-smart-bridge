# FigCraft hand-off

The approved screenshots in [`app/screenshots`](../../app/screenshots) remain the
UI contract. This directory holds a generated FigCraft document that keeps that
contract exact while making the copy editable.

```bash
make design-export    # re-dump the render tree and rebuild the .figcraft file
make design-capture   # after saving in FigCraft: list the copy that changed
```

Output (git-ignored, rebuilt on demand):

```text
design/figcraft/render/
├── smoke-x4-views.figcraft   # the hand-off document
├── shots/<view>.png          # 3x captures of the real widget tree
├── clean/<view>.png          # shots with the text painted out
├── dump/<view>.json          # text runs, positions, faces, colours
├── text-ids.md               # every text ID per view (ID, text, position)
└── export-script.json        # the command script that built the document
```

## What is in the document

* **Index** — every view as a thumbnail, in reading order.
* **One page per view** (38 at the time of writing) — a 390 × 844 frame holding
  the cleaned reference image plus one FigCraft text layer per text run.

Text is real, selectable and editable. Icons, sparklines, charts, cards and
everything else stay in the reference image, so the page looks like the app.
The words that were baked into the screenshot are painted out before import;
editing a sentence never leaves the old one showing underneath.

### Text IDs

Every text layer carries a label ID that is unique across the whole document:
`<view>.<nn>.<slug>`, e.g. `live_light.05.smoke-x4` or
`history_light.12.all-probes`. `nn` is the layer's position in paint order (1 is
the top-left-most), the slug is derived from the words.

* The ID is the **start of the layer name** (`live_light.05.smoke-x4 · Smoke X4`),
  so it shows in the layers panel and is found with Cmd+F.
* The ID is **not** in the layer's copy. The copy is exactly the words the
  screen shows; anything else would paint an ID line across the design.
* Edit only the layer's text. `make design-capture` compares in layer order and
  reports per ID: `Live · light · live_light.05.smoke-x4` followed by
  `old → new`.
* `render/text-ids.md` has the same list as one table per view (ID, text,
  position) for reviewing and choosing copy outside FigCraft.

Numeric runs are separate labels by design: a temperature renders as
`165.2` and `°F` in two layers, so each part can be styled or changed on its
own.

### One theme

The document holds the light theme wherever a design exists in both themes;
dark-only states (the Experimental lab, the Bridge OLED screens, dialogs) are
kept as they are. The dark duplicates export the same labels, so they would only
split review in two. To bring them back, empty `DARK_ONLY` (and
`LIGHT_BASELINE`) in `tools/figcraft_export.py` and run `make design-export`.

## How it is made

1. `app/tool/ui_screenshots_test.dart` normally compares goldens. With
   `FIGCRAFT_DUMP` set it instead writes, for every scenario, the laid-out text
   runs (position, size, weight, colour, tracking) and a 3x capture. Hidden
   tabs (`IndexedStack`), offstage widgets and copy covered by the navigation
   bar or a sheet are dropped.
2. `tools/figcraft_export.py` samples the background colour around each run,
   paints the run out of the reference image, and emits a FigCraft command
   script (`command.batch` per view) that `figcraft-cli run` executes.

The result renders within roughly 1–3/255 mean pixel difference of the
screenshot; the remaining difference is glyph antialiasing.

## Round trip

1. Edit copy in FigCraft. Keep each text layer in place — moving one breaks the
   position matching used by the capture step.
2. Save (`Cmd+S`).
3. Run `make design-capture`. It prints, per view, `old → new` for every changed
   string and exits non-zero when there are changes.
4. Apply the copy to `app/lib/app/strings.dart` (or the owning screen), run
   `make app-check`, and regenerate the goldens if the change is intentional:
   `cd app && flutter test --update-goldens tool/ui_screenshots_test.dart`.

## Limits

* Only text is editable. Colour, layout, icons and charts still change in code
  first, then the export is regenerated.
* Formatting is preserved per run (font size, weight, tracking, line height,
  colour, alignment). Richly styled runs are separate layers, which is why a
  temperature may be two layers (`165.2` and `°F`).
* A paragraph that Flutter clipped at the screen edge is still a full text layer
  in the frame, clipped by the frame — the copy can be longer than the visible
  part.

## MCP setup

`opencode.json` runs the headless `figcraft-cli mcp` server. That is enough to
build, inspect and re-read the document from an agent session.

To let the agent drive the **open FigCraft app** instead, launch it with a
control port and attach:

```bash
open -a FigCraft --args --control 7979
```

then change the server command in `opencode.json` to:

```json
"command": ["/Users/dan/.local/bin/figcraft-cli", "mcp", "--attach", "7979"]
```

Save in the app before running `make design-capture`, because the capture step
reads the file on disk.
