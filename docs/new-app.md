# The rebuilt app (`app/`)

The new companion app is the Flutter package at [`app/`](../app/), rebuilt from
the `newui/` prototype. It replaces the legacy app archived at `app.old/`
(git-ignored, reference only). This page is the entry point for the new app; the
pre-rebuild feature inventory in [`current-app.md`](current-app.md) describes the
**archived** app and is kept only as history.

## Where things live

```
app/lib/
  app/        bootstrap, root widget, router, font licences
  design/     tokens, typography, primitives — presentation only, stateless
  domain/     pure Dart entities and engines — zero Flutter imports
  data/       content tables, models, mock + real repositories, transports, cache
  features/   destinations and overlays (live, temps, timeline, graph,
              history, settings, onboarding, alarms, connection, monitor)
  platform/   Android seams (BLE, notifications, permissions, share, OTA)
app/test/
  domain/ design/ data/ features/ integration/   unit, widget, contract tests
  golden/                                        text goldens (see golden.dart)
  verification/                                  N16 invariant + audit suite
  support/                                       shared test helpers
```

The architecture, the invariants (I1–I15) and the design rules are in
[`newui/NOTES.md`](../newui/NOTES.md) and
[`newui/components_research_notes.md`](../newui/components_research_notes.md).
The build order is [`newui/ROADMAP.md`](../newui/ROADMAP.md); the shared notebook
is [`newui/PROGRESS.md`](../newui/PROGRESS.md).

## Commands

From the repo root:

| Command | Does |
|---|---|
| `make app.run` | `flutter run` on a device/emulator |
| `make app.test` | analyze + format check + `flutter test` (unit, widget, golden) |
| `make app.golden` | regenerate the text goldens |
| `make app.gen` | `dart run build_runner build` |

From `app/` directly: `flutter test`, `flutter analyze`,
`dart test test/domain test/data`, `flutter build apk --release`.

The real bridge is opt-in at build time:
`flutter run --dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=…`.
Without it the app runs the mock repository and the dev panel.

## Verification and release

- The invariant/audit suite is `app/test/verification/` — one named test per
  I2–I15, plus the copy, accessibility, reduced-motion, empty-state, field-report
  and release-build checks.
- Goldens are **text descriptions** of the widget tree, stable across platform
  and Flutter version; `flutter test` compares them and a missing golden fails.
- The release gate is [`RELEASE.md`](RELEASE.md); the bench field report is
  [`FIELD-REPORT.md`](FIELD-REPORT.md).

## Notes on the archive

- `app.old/` is **reference only** and git-ignored. Nothing in the new app
  imports from it; its behaviour (rate/ETA/stall math, safety floors, sync
  protocol) was re-implemented, not vendored.
- [`current-app.md`](current-app.md) and [`newapp.md`](newapp.md) predate the
  rebuild. `newapp.md` is the redesign spec the prototype implements;
  `current-app.md` is the archived app's inventory. Neither describes the
  shipping `app/` — read this page and `app/README.md` for that.
