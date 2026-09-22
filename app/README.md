# Smoke Bridge — the app

The companion app for the Smoke X4 smart bridge, in `newui/`'s design language.
It is complete through the `newui/ROADMAP.md` build (N0–N16): the live/temps/
timeline/graph/history/settings destinations, the two-tier alarm system, the
onboarding wizard, and the real bridge integration (HTTP + BLE transports, drift
cache, foreground service, OTA). The legacy app is archived at `../app.old/` and
is **reference only**; the entry point for the rebuilt app is
[`../docs/new-app.md`](../docs/new-app.md).

## Commands

From the repo root (`make` targets use the Windows-safe `.bat` wrappers):

| Command | Does |
|---|---|
| `make app.run` | `flutter run` on a connected device/emulator |
| `make app.test` | analyze + format check + `flutter test` (unit, widget, golden) |
| `make app.golden` | regenerate the goldens (`flutter test --update-goldens test/golden`) |
| `make app.gen` | `dart run build_runner build` |

Or from `app/` directly: `flutter run`, `flutter test`, `flutter analyze`,
`dart test test/domain test/data`.

The real bridge is the default: `flutter run` talks to `smokebridge.local`
over HTTP/BLE (override with `--dart-define=BRIDGE_HOST=…`). The mock
repository is opt-in for fixture-driven dev runs:
`flutter run --dart-define=MOCK_BRIDGE=true`.

## Verification and release

`test/verification/` is the N16 invariant and audit suite: one named test per
invariant I2–I15, plus copy, accessibility, reduced-motion, empty-state,
field-report and release-build checks. The release gate is
[`../docs/RELEASE.md`](../docs/RELEASE.md).

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
  verification/                            N16 invariant + audit suite
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