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

**Landed**

- Created `firmware/`, `protocol/` (with `fixtures/`, `fixtures/lora/`, `gen/`)
  and `tools/`, each with a tracked `.gitkeep` so the empty scaffold appears in
  a clean clone. `app/` and `docs/` already existed (approved Flutter prototype
  and design set) and were kept as-is.
- Expanded the root `.gitignore` for build output (`build/`, `.dart_tool/`,
  `.gradle/`, coverage, plugin files), ESP-IDF local state (`firmware/sdkconfig`,
  `sdkconfig.old`, `managed_components/`, `dependencies.lock`), Android
  `local.properties`/signing files, and Python/editor scratch. `legacy/` remains
  ignored. `protocol/gen/` is deliberately **not** ignored because generated
  codecs are committed and drift-checked by T02.
- Added `docs/design/adr/0012-workspace-tree-layout.md` and a "Repository tree"
  section in `docs/design/README.md`. Wrote reusable facts to
  `docs/progress/T01.md`.

**Deviations**

- None affecting scope. `app/` was not re-scaffolded because the approved
  prototype already occupies that path; T05 owns turning it into the production
  app. `docs/` already existed and matches the required tree.
- No new protocol/YAML, firmware or app content was created (owned by T02–T05).

**Check results**

- Simulated clean clone (temporary `GIT_INDEX_FILE`, `git read-tree HEAD`,
  `git add` scaffold, `git write-tree`): top-level entries are `.gitignore`,
  `README.md`, `app`, `docs`, `enclosure`, `firmware`, `protocol`, `tools`; all
  scaffold `.gitkeep` files are present; zero `build/`, `.dart_tool/` or
  `sdkconfig` paths in the tree.
- `git check-ignore` confirmed all 11 representative build/local paths are
  ignored and that `sdkconfig.defaults*`, `protocol/gen/*` and
  `protocol/fixtures/lora/*` remain trackable.
- `git status --porcelain -uall` shows no untracked build output.
- `git status --porcelain legacy` is empty; `legacy/` still has 5866 local files
  and 0 tracked files (ignored reference, untouched).

**Remaining work / next task must know**

- T02 can write `protocol/records.yaml`, `protocol/ble.yaml` and committed
  `protocol/gen/` outputs directly. T03 can populate
  `protocol/fixtures/lora/`. T04 can create the ESP-IDF project in `firmware/`.
- `legacy/` is local-only (not in a clean clone); copy fixture content during
  authoring rather than depending on it in CI or at runtime.
- No blockers. Follow-ups: root README says "Android or iOS" (should be
  Android-only, T66); T05 decides prototype-only file disposition.
