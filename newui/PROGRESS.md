# Progress notes

Shared notebook for the symphony run. Each task session appends a "## Txx — title" section with what
later tasks need to know: real paths, commands that work, contract deviations, gotchas. Facts, not
narrative. The harness inlines the tail of this file into every prompt.

## T01 — N0 Foundations: Flutter app skeleton, package set, lint/CI and golden harness

Status: done. `make app.test` green (15 tests); `flutter analyze` clean; `flutter build apk --debug` succeeds.

**Real paths**
- App root `app/` — Dart package `smoke_bridge`, Android applicationId `com.smokebridge.smoke_bridge` (unchanged). `app.old/` is reference-only and git-ignored.
- Source `app/lib/{app,design,domain,data,features,platform}`; `lib/data` and `lib/platform` hold `.gitkeep` only.
- Tests `app/test/{domain,design,features,golden,integration}` + `app/test/support/load_fonts.dart`.
- Fonts `app/assets/fonts/{Archivo[wdth,wght],Inter[opsz,wght],JetBrainsMono[wght]}.ttf` + `OFL-*.txt`; declared in `app/pubspec.yaml`; licences registered by `registerFontLicences()` in `app/lib/app/font_licences.dart` (called from `app/lib/app/bootstrap.dart`).
- CI `.github/workflows/app.yml`, pinned to Flutter 3.47.2.

**Commands that work (repo root)**
- `make app.test` — analyze + format check + `flutter test`.
- `make app.gen` — `dart run build_runner build`.
- `make app.golden` — `flutter test --update-goldens test/golden`.
- `make app.run` — `flutter run`.
- Direct from `app/`: `flutter test`, `flutter analyze`, `dart run build_runner build`, `flutter build apk --debug`.

**Decisions / deviations**
- Goldens are **text descriptions** of the widget tree (`app/test/golden/golden.dart`), not PNGs — same choice app.old made. Platform/Flutter-version independent. `--update-goldens` works because `expectGolden` honours `autoUpdateGoldenFiles`. Committed placeholder `app/test/golden/goldens/app_shell.golden.txt` (390×844).
- `riverpod_generator` added as a dev dep (not in the N0.2 list) so `riverpod_annotation` is usable; `freezed` pinned `3.2.6-dev.1` for analyzer compatibility (as app.old).
- Makefile `DART`/`FLUTTER` wrappers use `cmd //c dart.bat` / `cmd //c flutter.bat` on Windows because the Flutter SDK's extensionless shell scripts do not execute under make. Only the four `app.*` targets use them.
- `app/android/gradle.properties` sets `kotlin.incremental=false` (Windows Defender / pub-cache-on-C: vs repo-on-D: Kotlin cache assert; copied from app.old).
- `app/analysis_options.yaml` excludes `**/*.g.dart` and `**/*.freezed.dart` from analysis; generated files are committed and freshness-checked in CI.

**Gotchas for later tasks**
- build_runner 2.15 removed `--delete-conflicting-outputs` (warning + ignored); `make app.gen` and CI omit it.
- `pumpForGolden` defaults to a 390×844 logical surface; `describeTree` requires exactly one `MaterialApp` in the tree.
- Never import from `app.old/lib`.
- Placeholder route is `lib/features/home/home_page.dart` wired by `lib/app/router.dart` (go_router); N4 replaces it.
- `lib/design/theme.dart` is a minimal dark theme only. N3's token naming question (Q1: `N0` Tailwind-style vs legacy `SmokeTokens`) is still open.