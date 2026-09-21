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

## T02 — N1 Domain: entities, units, freshness, food safety and analysis engines

Status: done. `dart test test/domain` green (87 tests). `make app.test` green (100 tests total, analyze + format check + `flutter test`).

**Real paths (all under `app/lib/domain/`, pure Dart, barrel `domain.dart`)**
- `units/temp_value.dart` — `TempValue`, `TempUnit`, `c10ToF10`/`f10ToC10`, sentinels.
- `entities/` — `probe.dart` (`ProbeJack` 1–4, `ProbeRole`, `Probe` config), `freshness.dart`, `sample.dart` (`Sample.tempsF10`, nullable `unixMs`), `mark.dart`, `gap.dart` (`GapReason`, `RecordedGap`, `findGaps`, `detectRollover`, `detectConnectivityGaps`), `probe_reading.dart` (the only `@freezed` model; generated `.freezed.dart` committed).
- `plan/` — `hazard.dart` (`HazardClass`/`SafetyMode`/`SafetyFloor`), `presets.dart` (`CutThickness`, `Doneness`, `DonenessLadder`, `CookPreset`, `carryoverFor`, `pullTempFor`, `restSecondsFor`), `cook_style.dart`, `cook_timeline.dart` (`MinuteRange`/`StallWindow`/`WrapStep`/`TurnStep`/`CookPhaseSpec`/`CookTimeline`), `cook_phase.dart`, `cook_plan.dart`, `cook_annotation.dart`.
- `analysis/` — `series.dart` (`TempPoint`/`ValuePoint`/`OlsFit`/`olsFit`/`windowedValid`), `rate_of_change.dart`, `eta.dart`, `stall.dart`, `cook_stats.dart`, `lttb.dart`, `chart_series.dart`.
- `situation/situation.dart` (`SituationFacts`/`reconcile`/`Situation`).

**Test tooling (deviation from T01, deliberate)**
- Added `test: ^1.31.0` as a direct dev dependency. All `app/test/domain/*` tests import `package:test/test.dart` (not `flutter_test`) so the task's named gate `dart test test/domain` actually compiles and runs. `flutter test` still runs them (100 tests). **Any future test that `dart test` must run cannot import `flutter_test`.**
- Deleted the N0.6 placeholder `lib/domain/models/temperature_reading.dart` (+ `.freezed.dart`, `.g.dart`, its test) as the task directed; `ProbeReading` is now the codegen smoke. Run `make app.gen` after touching a `@freezed` model.

**Commands that work (repo root)**
- `cd app && dart test test/domain` — the N1 exit gate (87 pass).
- `make app.test` — analyze + format check + full `flutter test`.
- `make app.gen` — regenerate freezed (`ProbeReading` only in domain).

**Contract deviations / decisions (N2+ must know)**
- `ProbeJack` is an enum, not an `int`; `Sample.tempsF10` keeps jack order (index 0 = jack 1) and `probeValue(sample, ProbeJack)` is the accessor. `ProbeRole.defaultFor(jack)` = `pit` for jack 4, `unused` otherwise.
- `carryoverFor({hazard, thickness})` and `pullTempFor({targetF10, carryoverF10, hazard, isIntact, mode})` take named params rather than a preset/cut object.
- `Freshness` has a fifth member `unknown` (no reading) beyond the four-rung ladder. `showsDerived` plus the alias `canShowDerived` are the I4 gate.
- `CookTimeline` JSON keys are snake_case (`total_min`, `spritz_every_min`, `rest_min`, `phases`, …) and its sub-records have `toJson`/`fromJson`; N2's timeline table can serialise straight into it.
- `CookPlan.fromJson` defaults an unknown hazard to `unstated` (160 °F floor), not the legacy `wholeMuscleRedMeat`, fixing the documented fallback inconsistency. Consequence: a stored plan that omits hazard and targets under 160 °F is dropped on load.
- `CookStyle`/`CookTimeline` are models only — **no catalog tables**. N2 owns `Presets.all`, `CookTimeline` per cut, `CookStyle` per cut and the scenarios.
- ETA/rate/stall operate on `int` session-seconds and `TempPoint = ({int t, double? f})`. Cook stats take `List<Sample>` + `Probe` configs + `Mark`s.
- `CookPlan.copyWith` re-runs the safety gate; `CookAnnotation.toPlan()` likewise.

**Gotchas**
- Generated files are committed and CI freshness-checks `git diff --exit-code -- lib`; always run `make app.gen` before committing model changes.
- `app/lib/domain/` must stay free of `package:flutter` and `dart:ui` (`domain_purity_test.dart` + CI grep). `package:meta` is allowed.
- `app.js` §4 approximates carryover/pull; N1 uses the real `SafetyFloor`-clamped values per NOTES §3.4, so prototype numbers may differ by a degree at the floor.