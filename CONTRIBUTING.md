# Contributing

## The one hard rule

**`docs/reference/` is never edited.** It is a read-only vendor snapshot of
`G-Two/smoke-x-receiver` (MIT © 2022 G-Two), pinned at the commit recorded in
[`docs/reference/PROVENANCE.md`](docs/reference/PROVENANCE.md). It exists as provenance and as a
stable tree to diff against. Code carried from it into `firmware/` keeps the MIT notice in every
carried file (decision D9).

## Ground rules

- **Decisions D1–D14 are settled.** They live in
  [`docs/design/00-overview.md`](docs/design/00-overview.md). If one looks wrong during
  implementation, raise it as a question — don't quietly plan around it
  ([12 §12.3](docs/design/12-task-planning-notes.md)).
- **Conventional Commits** (`feat:`, `fix:`, `chore:`, `docs:`, …) — the changelog is generated
  from them.
- **Trunk-based.** Short-lived feature branches; `main` always builds and flashes.
- **Style** ([10 §10.7](docs/design/10-repo-tooling-and-testing.md)): C is 4-space/80-col via
  `.clang-format` (carried from the reference); Dart is `dart format` + `flutter_lints` with
  `prefer_final_locals` and `require_trailing_commas`. Warnings are errors in CI.
- `pre-commit install` once; the hooks format, validate YAML/JSON, and check that
  `protocol/gen` is current.

## Changing the protocol

`protocol/` is the single source of truth (D10). To change a binary layout:

1. Edit `protocol/records.yaml` — sizes are declared and validated; sentinels and flag bits are
   named, never numbered.
2. `dart run protogen` — regenerates `protocol/gen/record_gen.h`, `protocol/gen/records.g.dart`,
   and the package copies (`tools/bridge_protocol`, `app/lib/data/dto`).
3. Commit **all** emitted copies together. CI (`protocol.yml`) regenerates and fails on any
   diff; `dart run protogen --check` does the same locally.
4. If the wire shape changed, regenerate the golden vectors
   (`dart run protogen:gen_record_fixtures`) and update both test suites' expectations — the C
   and Dart tests parse the _same_ fixture files by design, so drift shows up as a red test.

HTTP contract changes go through `protocol/openapi.yaml` + the fixtures in
`protocol/fixtures/http/` (the sim and the app tests both read them). BLE changes go through
`protocol/records.yaml` (payloads) and `protocol/ble-gatt.md` (service shape).

## Running the suites

| Suite                         | Command                                                  | Needs                          |
| ----------------------------- | -------------------------------------------------------- | ------------------------------ |
| C host tests                  | `make test-host`                                         | gcc, cmake, ninja — no ESP-IDF |
| Record parity + contract lint | `dart test` in `tools/bridge_protocol`, `tools/protogen` | Dart                           |
| cookgen / sim                 | `dart test` in `tools/cookgen`, `tools/sim`              | Dart                           |
| App                           | `cd app && flutter analyze && flutter test`              | Flutter                        |
| Generated-code freshness      | `dart run protogen --check`                              | Dart                           |
| Firmware build                | `make build`                                             | ESP-IDF v5.4                   |

## Hardware discipline

There is exactly one board and it is also the only instrument pointed at the Smoke X. Batch
`board: yes` work into sittings, never flash during a cook, and never OTA an image that hasn't
been USB-flashed first — the full rules are in
[`docs/tasks/standing-work.md`](docs/tasks/standing-work.md).
