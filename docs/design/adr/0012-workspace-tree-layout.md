# 0012 — Workspace tree layout and ignore policy

## Status

Accepted

## Context

The project starts from an empty production tree beside a read-only `legacy/`
reference. Every later task (protocol codegen, host tests, firmware, app, tools)
needs a stable location, and the repository must not accumulate untracked build
output as those tasks start building. A clean clone must show the tree even
before the sibling M0 tasks add their first real files.

## Decision

Keep the production tree beside `legacy/` as `firmware/` (ESP-IDF project),
`app/` (Flutter project), `protocol/` (YAML sources, `fixtures/`, committed
`gen/`), `tools/` (codegen, BLE fake host, bench scripts) and `docs/` (design,
tasks, progress, verified hardware). Track empty scaffold directories with
`.gitkeep`. Ignore build output (`.dart_tool/`, `build/`, Gradle caches),
ESP-IDF local state (`firmware/sdkconfig*` excluding `sdkconfig.defaults*`,
`managed_components/`), editor and Python scratch. Do **not** ignore
`protocol/gen/`: generated codecs are committed and T02's `--check` guards drift.

## Consequences

Later tasks land in the shared paths without re-deciding the layout, and CI can
rely on `protocol/gen/` existing in a clone. Adding generated output that is not
committed requires an explicit `.gitignore` entry at the point of introduction;
build output must never be committed. `legacy/` stays ignored and read-only.
