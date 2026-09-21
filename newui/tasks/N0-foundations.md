# N0 — Foundations

**Goal:** a new Flutter app at `app/` that boots, renders a themed shell over mock
state, and has the CI/golden harness the rest of the backlog depends on.

**Design:** [`newui/index.html`](../index.html) · [`newui/styles.css`](../styles.css)
· [`newui/NOTES.md`](../NOTES.md) §8 · `app.old/pubspec.yaml` (package set, reference only).

---

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N0.1 | Scaffold: `flutter create` a fresh app in `app/` (Android-first), package name unchanged, `app.old/` remains reference-only | — | H | `app.old/pubspec.yaml` |
| N0.2 | Pin the package set (`flutter_riverpod`, `riverpod_annotation`, `freezed`, `json_serializable`, `go_router`, `fl_chart`, `shared_preferences`, `logger`, `meta`). Defer BLE/drift/notifications/share to N15 | N0.1 | H | `app.old/pubspec.yaml`, NOTES §6 |
| N0.3 | `analysis_options.yaml`: strict lints; layering guards as tests — `domain/` has zero Flutter imports, `ui/` is stateless over plain values | N0.1 | H | `components_research_notes.md` §10 |
| N0.4 | Folder layout: `lib/{app,design,domain,data,features,platform}`, `test/{domain,design,features,golden,integration}` | N0.1 | H | `app.old/lib` (layout only) |
| N0.5 | Bundle the three variable fonts (Archivo, Inter, JetBrainsMono) + OFL licences, register via `LicenseRegistry` | N0.1 | H | `styles.css` §fonts, NOTES §8 |
| N0.6 | Codegen pipeline: `build_runner` wired; a trivial `@freezed` model generates; `dart run build_runner build` documented | N0.2 | H | — |
| N0.7 | Bootstrap: `ProviderScope`, `runApp`, a `SmokeApp` widget that renders a placeholder route | N0.2, N0.4 | W | `index.html` shell |
| N0.8 | Golden harness: golden test scaffold + `--update-goldens` make target + a checked-in placeholder golden at 390×844 | N0.7 | W | `index.html` frame |
| N0.9 | CI: analyze, test, golden compare; fonts available offline | N0.8 | H | `docs/tasks/README.md` (CI posture) |
| N0.10 | Make targets / scripts: `app.run`, `app.test`, `app.golden`, `app.gen` | N0.9 | H | `Makefile` |

## Exit gate

`flutter run` opens a themed blank shell on the 390×844 frame; `flutter test`
runs the layering + placeholder golden green in CI; codegen is reproducible from
a clean checkout.

## Must-not-regress

None (no invariants yet). Do not import anything from `app.old/lib`.

---

## Hand-off

Status: **done** (attempt 1). All ten sub-tasks landed; the tree is green.

### What landed
- `app/` is a fresh `flutter create` project: package `smoke_bridge`, applicationId `com.smokebridge.smoke_bridge` (unchanged), Android-only.
- Package set pinned in `app/pubspec.yaml` (flutter_riverpod, riverpod_annotation, freezed/freezed_annotation, json_serializable/json_annotation, go_router, fl_chart, shared_preferences, logger, meta; build_runner + riverpod_generator as dev deps). BLE/drift/notifications/share deferred to N15.
- `app/analysis_options.yaml`: flutter_lints + strict-casts/inference/raw-types and extra lints; generated files excluded. Layering is enforced by tests: `test/domain/domain_purity_test.dart` (domain has zero Flutter/`dart:ui` imports) and `test/design/design_purity_test.dart` (design is stateless and does not import app/data/features/riverpod). `test/integration/project_layout_test.dart` pins the N0.4 tree.
- Three variable fonts + OFL licences bundled in `app/assets/fonts/`, declared in pubspec and registered via `LicenseRegistry` in `app/lib/app/font_licences.dart` (called from `app/lib/app/bootstrap.dart`); `test/integration/font_assets_test.dart` proves the assets ship and the licences load/register.
- Codegen wired: `lib/domain/models/temperature_reading.dart` (`@freezed` + `json_serializable`) generates committed `.freezed.dart`/`.g.dart`; round-trip test `test/domain/temperature_reading_test.dart`.
- Bootstrap: `runApp(ProviderScope(child: SmokeApp()))`; `SmokeApp` is `MaterialApp.router` over a single go_router route rendering the themed `HomePage` placeholder.
- Golden harness: text-based (`test/golden/golden.dart`) with self-tests; committed placeholder `goldens/app_shell.golden.txt` at 390×844.
- Make targets `app.run`, `app.test`, `app.golden`, `app.gen`; CI `.github/workflows/app.yml` (analyze, format, test+goldens, debug APK) pinned to Flutter 3.47.2.

### Deviations from the plan
- Goldens are text (tree descriptions), not PNGs, for cross-platform/CI stability; `--update-goldens` is still the regenerate switch.
- Added `riverpod_generator` so `riverpod_annotation` is actually usable; `freezed` stays at `3.2.6-dev.1` for analyzer compatibility.
- CI Flutter pin moved 3.44.7 → 3.47.2 to match the SDK that generated `app/android/` (AGP 9.1.0 / Gradle 9.3.1).
- Makefile gained Windows-safe `DART`/`FLUTTER` wrappers (`cmd //c *.bat`) for the four `app.*` targets.
- `kotlin.incremental=false` in `app/android/gradle.properties` for the Windows APK build.

### Verification (real commands, real output)
- `cd app && flutter test` → `00:01 +15: All tests passed!`
- `cd app && flutter analyze` → `No issues found!`
- `cd app && dart format --output=none --set-exit-if-changed lib test` → exit 0
- `make app.test` → analyze clean + format clean + `+15: All tests passed!`
- `cd app && flutter build apk --debug` → `√ Built build\app\outputs\flutter-apk\app-debug.apk`
- `make app.gen` → `wrote 3 outputs`; an immediate re-run reports `1 same` (reproducible).

### Next task must know
- Put domain logic in `lib/domain/**` with zero Flutter imports (both `test/domain/domain_purity_test.dart` and the CI grep enforce it).
- N3 fills `lib/design/`; keep it stateless and free of app/data/features/riverpod imports, or `test/design/design_purity_test.dart` fails. **Q1 (token naming) is unresolved.**
- New screens replace the `HomePage` placeholder via `lib/app/router.dart`.
- After any copy change, regenerate goldens with `make app.golden` and review the diff; never hand-write them.