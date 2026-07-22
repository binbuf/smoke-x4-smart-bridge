# Provenance — docs/reference/smoke-x-receiver

`docs/reference/smoke-x-receiver` is a **read-only vendor snapshot**, not a submodule. It exists as
a frozen provenance copy of the upstream project this bridge's protocol work derives from, and as a
stable tree to diff against when upstream changes something.

| | |
| --- | --- |
| Upstream | <https://github.com/G-Two/smoke-x-receiver> |
| Pinned commit | `75e671c427f6903bba1848bbf7a1a385e4ac1afb` |
| Upstream commit date | 2026-07-05 (`Update web UI (#27)`) |
| Licence | MIT © 2022 G-Two (see `smoke-x-receiver/LICENSE`) |

## Rules

- **Never edit anything under `docs/reference/`.** It is a snapshot; local edits would silently
  diverge from the provenance it exists to provide. This rule is restated in
  [`CONTRIBUTING.md`](../../CONTRIBUTING.md).
- The nested `.git` directory was deliberately stripped when the snapshot was taken — a snapshot,
  not a submodule, so no contributor needs an extra clone step for files nobody compiles.
- To compare against newer upstream work, clone upstream separately and diff against this tree.
- Code carried from this snapshot into `firmware/` (per decision
  [D9](../design/00-overview.md)) retains the MIT copyright notice in every carried file.

This project is not affiliated with or endorsed by ThermoWorks.
