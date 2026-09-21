# Smoke Bridge — new Flutter app

The rebuilt companion app for the Smoke X4 smart bridge, in `newui/`'s design
language. This is the N0 foundation (skeleton, packages, lint, golden harness);
screens land in later tasks. The legacy app is archived at `../app.old/` and is
**reference only**.

## Commands

From the repo root (`make` targets use the Windows-safe `.bat` wrappers):

| Command | Does |
|---|---|
| `make app.run` | `flutter run` on a connected device/emulator |
| `make app.test` | analyze + format check + `flutter test` (unit, widget, golden) |
| `make app.golden` | regenerate the goldens (`flutter test --update-goldens test/golden`) |
| `make app.gen` | `dart run build_runner build` |

Or from `app/` directly: `flutter run`, `flutter test`, `flutter analyze`.

## Layout

```
lib/
  app/        bootstrap, root widget, router
  design/     tokens / typography / primitives (N3) — presentation only
  domain/     pure Dart entities and engines (N1) — no Flutter imports
  data/       content tables, mocks, repositories (N2)
  features/   destinations and overlays (N4+)
  platform/   Android seams (N15)
test/
  domain/ design/ features/ integration/   unit, widget and contract tests
  golden/                                  text goldens (see golden.dart)
  support/                                 shared test helpers
```

The `domain/` purity and `design/` statelessness rules are enforced by tests,
not just convention: `test/domain/domain_purity_test.dart`,
`test/design/design_purity_test.dart`.

## Goldens

Goldens are **text descriptions of the rendered tree**, not PNGs, so they are
stable across platform and Flutter version. `flutter test` compares them; a
missing golden fails rather than writing itself. Regenerate deliberately with
`make app.golden` and review the diff.