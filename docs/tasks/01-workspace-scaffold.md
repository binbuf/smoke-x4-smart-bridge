# T01 — Workspace scaffold and ignore rules

## Goal
Create the new repository tree beside the read-only `legacy/` reference so that
every later firmware, app, protocol, and tooling task has a place to land. A
clean clone sees the tree and produces no untracked build output.

## Context (read first)
- Design: [00 §0.3](../design/00-product.md), [09](../design/09-legacy-audit.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on: nothing (`blocked-by: —`).
- `legacy/` is read-only reference; this is a greenfield build, so there is no
  existing production code to re-scaffold. Do not delete or move legacy files.

## Scope
- [ ] Create the new tree beside `legacy/`:

  ```
  firmware/    ESP-IDF project
  app/         Flutter project
  protocol/    records.yaml, ble.yaml, fixtures/, gen/
  tools/       codegen, BLE fake host, bench scripts
  docs/        design + tasks + hardware-verified.md
  ```

- [ ] Add `.gitignore` entries for build outputs, `.dart_tool`, `build/`,
      `sdkconfig` local overrides, and generated files that are not committed.
- [ ] Keep `legacy/` untouched: do not delete or move any legacy file.

## Out of scope
- Protocol contract content and codegen — owned by T02.
- Host test harness and fixtures — owned by T03.
- ESP-IDF project contents and partition table — owned by T04.
- Flutter app contents — owned by T05.
- Any refactor, cleanup, or deletion of `legacy/` — not part of this plan;
  `legacy/` stays read-only reference.

## Design notes
- The tree layout above is the contract later tasks assume; directory names and
  responsibilities must match it exactly.
- `protocol/` owns `records.yaml`, `ble.yaml`, `fixtures/`, and `gen/`;
  `tools/` owns codegen, the BLE fake host, and bench scripts.
- Generated files that are committed must be ignored only where the source
  says so; generated files that are not committed belong in `.gitignore`.
- No new build output may be left untracked — the ignore rules are part of the
  deliverable, not an afterthought.
- This is a scaffold task: create the structure, not the contents owned by the
  sibling M0 tasks.

## Done when
- [ ] A clean clone can see the tree.
- [ ] No new build output is untracked.
- [ ] `legacy/` is neither deleted nor moved.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
