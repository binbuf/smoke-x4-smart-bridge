# Progress

> Bench evidence (serial captures, screenshots, UI dumps, database copies and
> firmware images) is intentionally not committed. It lives in the git-ignored
> `artifacts/` tree on the bench machine, so paths under `artifacts/` below refer
> to local evidence rather than files in this repository.

One markdown file per task (`T01.md`, `T02.md`, …), written by that task's session with what later
tasks need to know: real paths, commands that work, contract deviations, gotchas. Facts, not narrative.
The harness indexes these notes — and maintains the generated "Key facts" digest — in `PROGRESS.md`;
it never writes here. The file for a task that has not run does not exist.
