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

## T03 — N2 Data and mocks: catalog/style/timeline tables, scenarios, mock repository

Status: **done** (N2.1–N2.32 all landed; the dev panel widget and boot deep-link seam are in place — N4.10 mounts the panel and N4.3 routes it).
`dart test test/domain test/data` green (**131**); `flutter test` green (**152**); `flutter analyze` and format check clean.

**Real paths**
- Content `app/lib/data/content/`: `catalog_data.dart`, `styles_data.dart`, `fixtures_data.dart` (**generated** by `node app/tool/gen_mock_content.mjs` from `newui/mock-data.js`); hand-written `timelines.dart`, `catalog.dart`, `scenarios.dart`.
- Models `app/lib/data/model/`: `catalog_entry.dart`, `connection_state.dart`, `cook_state.dart`, `bridge_snapshot.dart` (freezed), `app_settings.dart` (freezed), `alarm.dart`, `alarm_rule.dart`, `connection_mode.dart`, `device_info.dart`, `history_entry.dart`, `mock_event.dart`.
- Repo `app/lib/data/repository/`: `bridge_repository.dart`, `mock_bridge_repository.dart`, `mock_event_bus.dart`, `prefs_repository.dart`. Providers `app/lib/data/providers.dart`; barrel `app/lib/data/data.dart`; dev control `app/lib/data/dev_panel.dart`.
- Widgets `app/lib/features/dev/`: `dev_panel.dart` (`DevPanel`, N2.31, release-excluded) and `dev_boot.dart` (`applyDevDeepLink`, N2.32). `app/lib/app/bootstrap.dart` parses `Uri.base` and overrides `initialDevDeepLinkProvider`.
- Tests `app/test/data/{content_validation,timeline,mock_repository,settings,dev_panel}_test.dart`; `app/test/features/{dev_panel_widget,dev_boot}_test.dart`.

**Commands that work (repo root)**
- `cd app && dart test test/domain test/data` — the N2 exit gate (131 pass).
- `cd app && flutter test` — full suite incl. goldens (152 pass).
- `cd app && node tool/gen_mock_content.mjs` — regenerate the three content tables after editing `newui/mock-data.js`.
- `make app.gen` — build_runner only (freezed); it does NOT regenerate content tables.

**Contract facts later tasks need**
- `kCatalogTable` (139 cuts, 10 categories, 331 styles over 139 styled cuts, `timelines` one per cut). Reviewers: `kCatalogReviewer`, `kStylesReviewer`, `kTimelineReviewer`.
- `BridgeRepository` is the only screen source: `snapshot()` stream, `resync/connect/disconnect/adoptSession/startCook/addItem/markPulled/mark/ackAlarm/probeRole/setTarget/applyMode/performVerb/checkForUpdates/setFavourite`, dev `selectScenario/fireEvent`, plus `catalog/connectionModes/alarmRules/mockEvents/device/firmware/history/scenarios`.
- `MockBridgeRepository({int? nowMs, String initialScenario})`; 11 scenarios incl. `running/idle/existing/offline` + 7 connection-matrix. `snapshot()` replays `current` on each subscription, so `await repo.snapshot().first` reads state.
- `ProbeState.reading` → N1 `ProbeReading` with the I4 gate; `MockPrefsRepository` backs `AppSettings.defaults`.
- `DevPanelController.applyLocation('?scenario=offline&units=C&screen=timeline&overlay=probe&jack=3')` is tested; `DevDeepLink.parse` accepts query, fragment and app URIs.
- `DevPanel` (N2.31) reads `bridgeRepositoryProvider` + `prefsProvider`, renders scenario/screen/overlay/event buttons + units/theme/profile + connect, and reports navigation through `onScreen`/`onOverlay`. `kDevOverlayLabels` is the 15 prop-free overlays. It is release-excluded via `kReleaseMode`.
- `applyDevDeepLink(container, link)` (N2.32) applies `scenario`/`units`; `bootstrap.dart` stashes the parsed link in `initialDevDeepLinkProvider` (default/none in release) for N4.3.

**Deviations / gotchas**
- Counts in the task text are stale: it is **139/331/139**, not ~318/133. `game_antelope` and `game_squirrel` have only 1 style each.
- Content validation pins the prototype's below-floor rungs (raw tuna, rosé duck, warm ham, 140 °F lobster/crab, 160 °F rabbit, cold sides) as exact exception sets; `unstated` (non-meat) entries are not floor-checked.
- **Follow-up (N9):** the catalog marks all vegetables/sides/desserts/cold items `unstated`, which N1 floors at 160 °F. The picker must not apply that floor to declared non-meat content (coleslaw 38 °F, cold-smoke cheese 90 °F, butter 80 °F would be refused otherwise).
- **Follow-up (N4/N6):** `ProbeState` duplicates part of `ProbeReading`; consider collapsing to one projection when the shell wires the providers.
- Generated files are committed; run `make app.gen` after any freezed-model change.
- The dev panel does not mount itself: N4.10 places `DevPanel` beside the phone frame and supplies `onScreen`/`onOverlay`; N4.3 routes `screen`/`overlay` (incl. `initialDevDeepLinkProvider`). The panel's overlay buttons omit `probe`/`alarmDetail`/`confirm`/`verb` (they need props).

## T04 — N3 Design system: tokens, typography, icons and component primitives

Status: **done**. `flutter test` green (**201**, was 152); `flutter analyze` clean; format check clean; `dart test test/domain test/data` still green (131).

**Real paths (all under `app/lib/design/`; import the barrel `design/design.dart`)**
- `tokens.dart` — `SmokeTokens` (ThemeExtension), `SmokeSpacing`, `SmokeRadii`, `SmokeDensity`, `SmokeProfile`. `SmokeTokens.tint(base, alpha)` is the Flutter spelling of `rgba(var(--x-rgb), a)`; `series(jack)`, `statusFill/statusBorder`.
- `theme.dart` — `SmokeThemeData.build/dark/light({brightness, profile, density, reducedMotion})`; keeps the `SmokeTheme` font/dark-alias façade N0/N2 code uses.
- `motion.dart` — `SmokeMotion` (quick 120 / standard 220 / value 600 / gauge 800 / pulse 2 s; `effective()` zeroes all but pulse under reduced motion).
- `text.dart` — `SmokeText` (16 named styles, tabular `tnum` on numerics) + `SmokeTextScale` (hero 96→56, gauge 84→64→dropped at >1.3×).
- `icons.dart` — `SmokeGlyph` (67 names) + `SmokeIcon`; `SmokeIcons.byName` keeps prototype-name parity.
- `food_avatar.dart` — `FoodGlyph` (21 identities), `FoodAvatarRegister.{disciplined,vivid}`, `FoodAvatarSize`, `FoodAvatar.stopsFor`.
- Primitives: `card.dart`, `buttons.dart` (PrimaryAction/SmokeButton/ActionRow), `chips.dart`, `toggle.dart`, `rows.dart` (SettingsRow/LinkRow/SignalBars/SectionLabel), `atoms.dart` (JackBadge/TargetPill/TrendChip/ModeBadge/TierTag), `pulse.dart` (PulseDot + SmokePulseScope), `status.dart` (TransportChip/InsightBanner/CapabilityNotice/AlarmBar), `indicators.dart` (Sparkline/TargetGauge/PhaseTrack), `mono_well.dart`, `states.dart` (EmptyState/ProblemState/LoadingState/StaleVeil), `stats.dart` (StatGrid/StatMini/RecapRow), `legend.dart` (SeriesLegend/LegendSwatch), `haptics.dart`, `cost_sheet.dart`.
- `gallery.dart` — `DesignGallery`; route `/design` added in `app/lib/app/router.dart`.
- Tests `app/test/design/{tokens,icons,primitives,design_layering}_test.dart`; goldens `app/test/golden/design_gallery_golden_test.dart` + 6 files `app/test/golden/goldens/design_gallery_{dark,light,daylight}_{compact,comfortable}.golden.txt`.

**Commands that work (repo root)**
- `make app.test` — analyze + format check + full `flutter test` (the N3 gate; 201 pass).
- `make app.golden` — regenerates the gallery goldens too.
- `cd app && flutter test test/design` — 44 fast primitive/token tests.
- `cd app && flutter test test/golden/design_gallery_golden_test.dart` — the 6 gallery goldens.

**Contract deviations / decisions later tasks must know**
- **Icons are a Material mapping, not ported SVG paths.** Flutter has no SVG renderer in the SDK and N0 pinned the package set (no `flutter_svg`). The stable contract is the icon *name* (`SmokeGlyph`); `SmokeIcons.data` maps each to the closest Material glyph. Swapping artwork later is a one-file change.
- **`FoodGlyph` has 21 identities, not 13.** The catalog actually uses 18 (`beef bread brisket cheese egg fish fruit game ground pork potato poultry ribs shellfish side steak veg wholeBird`) plus `ambient`/`pit`/`unstated`. The research notes' "13" is stale, same as T03's counts.
- **PulseDot is stateless; the ticker is not owned by the app root.** `SmokePulseScope` carries an `Animation<double>?`; with no scope the dot renders static. N4 must mount one repeating controller at the shell root (a root-owned controller makes `pumpAndSettle` unusable for every golden, which is why SmokeApp does not). `SmokeMotion.pulse` is the duration; reduced motion must not stop it (the still dot *is* the staleness signal).
- **`SmokeApp` defaults changed**: `themeMode: ThemeMode.system` (was hard dark), plus `profile`/`density`/`reducedMotion` params. N4 passes `AppSettings` values; `AppThemeMode`/`DisplayProfile`/`Density` (data/) map to `ThemeMode`/`SmokeProfile`/`SmokeDensity` (design/).
- **Golden harness gained `pumpForGolden(..., settle: false)`** for trees with intentional indeterminate animations (spinner, pulse). Existing callers are unaffected. The gallery goldens use it.
- Gallery goldens are structurally identical across the three themes/densities (the harness describes text/icons, not pixels); theme values are pinned by `tokens_test.dart`, not the goldens.
- `TargetGauge.isReached(value, target)` is the "target reached closes the ring, never green" gate; the gauge colour is always the passed series mark.

**Gotchas**
- `lib/design/` must stay stateless and inward-free (`design_purity_test`); no `Duration(...)` or raw colour may appear in `lib/features/` or `lib/app/` (`design_layering_test` scans them). Use `SmokeMotion`/`SmokeTokens`.
- The gallery must render every primitive with no overflow at 390×844 and at 1.0 text scale; button labels are `Flexible`+ellipsis, and the gallery golden test loads the bundled fonts.
- `showCostSheet(context, ...)` returns `Future<bool?>` (true = confirm) and uses the standard `showModalBottomSheet`.

**Follow-ups (N4/N16)**
- Mount a single pulse controller (SmokePulseScope) beside the shell chrome.
- Optionally keep `/design` behind a debug flag in release (N16).
- N7 wires `SeriesLegend.onIsolate`; N5/N6 wire `TargetGauge`/`Sparkline`/`PhaseTrack` to real projections.

## T05 — N4 Shell: phone chrome, bottom nav, overlay framework and fullscreen graph host

Status: **done**. `make app.test` green (**229** tests; was 201); `flutter analyze` and format check clean; `dart test test/domain test/data` still green (131).

**Real paths (all under `app/lib/features/shell/`)**
- `shell.dart` — `AppShell` (the persistent chrome), `ShellScope`, `shellPulseEnabledProvider`, `shellClockProvider`, and the location helpers `baseLocation` / `overlayRequestFromLocation` / `locationWithOverlay`.
- `shell_screen.dart` — `ShellScreen` (`live/temps/timeline/graph/settings/history/cookDetail`), `screenFromPath`, `pathForDevScreen`.
- `phone_frame.dart` — `ShellPhoneFrame` (status bar + app area + overlay/toast hosts), `ShellStatusBar`, `ShellScrollHost` (resets on token change).
- `bottom_nav.dart` — `ShellBottomNav`, `kShellNavItems`; `app_bar.dart` — `ShellAppBar`, `ShellIconButton`; `alerts_bell.dart` — `AlertsBell`; `transport_status.dart` — `TransportStatus.from(ConnectionState)`.
- `overlay.dart` — `OverlayRequest`, `resolveOverlay`, `ShellSheet`, `ShellModalCard`, `ShellOverlayHost`, imperative `showSheet` / `showModalCard`.
- `graph_host.dart` — `ShellFullscreenGraphHost`, `ShellFullscreenGraphPlaceholder`; `toast.dart` — `ShellToastController`, `ShellToastHost`; `destinations.dart` — the 7 placeholder destinations.
- Router `app/lib/app/router.dart`: `createAppRouter()` + the shared `appRouter`; `SmokeApp` gained an optional `router` param for test isolation.
- Tests `app/test/features/shell_test.dart` (23), `app/test/features/shell_router_test.dart` (9); `app/test/golden/app_shell_golden_test.dart` regenerated.

**Commands that work (repo root)**
- `make app.test` — analyze + format check + full `flutter test` (229 pass).
- `cd app && flutter test test/features/shell_test.dart test/features/shell_router_test.dart`.
- `cd app && dart test test/domain test/data` — unchanged data/domain gate (131).
- `make app.golden` — regenerates the shell golden too.

**Contract facts later tasks need**
- **Overlays are URL query params.** Any destination accepts `?overlay=<DevOverlay.name>&<props>`; `AppShell` reads `GoRouterState.uri` (via the `location` prop) so a deep link and a tap produce the same surface. Dismiss strips the query. Helpers: `locationWithOverlay`, `overlayRequestFromLocation`, `baseLocation`.
- **`AppShell` is controlled** (`location` + `onLocation`); tests use a harness, the router passes `context.go`. The shell holds no business state — it watches `snapshotProvider` only for the unacked count/transport chip.
- **`ShellScreen` ≠ `DevScreen`.** `DevScreen` has no `cookDetail`; `ShellScreen` has both `history` and `cookDetail` (both highlight Settings in the nav). Routes: `/live /temps /timeline /graph /settings /settings/history /settings/history/:id`.
- **The pulse controller IS mounted at the shell root** (N3's follow-up), driven by `shellPulseEnabledProvider`. It makes `pumpAndSettle` hang, so **any test that pumps `AppShell`/`SmokeApp` must override `shellPulseEnabledProvider` to false** (or use `pumpForGolden(..., settle: false)`). `shellClockProvider` pins the status-bar clock for goldens.
- **Overlay framework is two mechanisms, one chrome.** Named overlays render in-tree via `ShellOverlayHost`; `showSheet`/`showModalCard` are imperative wrappers on the root Navigator for ad-hoc flows. All 19 `DevOverlay` values resolve (`resolveOverlay`); `adopt`, `editStart`, `confirm` are modals, the rest sheets. Contents are placeholders naming the owning task (N5/N6/N8/N9/N10/N11/N13/N14).
- **`AppShell` dev branch** (debug only): wide (`≥700×500`) mounts `DevPanel` beside a 390-wide phone frame; narrow shows a floating `shell-dev-panel-button` that opens the panel in a bottom sheet. Release returns the chrome only. Existing `DevPanel` button labels omit `probe`/`alarmDetail`/`confirm`/`verb` (they need props); deep links can still open them (`?overlay=probe&jack=3`).
- **N4.11**: `ShellScrollHost(resetToken: screen)` resets the destination scroll; `AppShell` keeps one `ScrollController` per overlay name and restores its offset on reopen (saved in `_closeOverlay`, jumped post-frame in `_openOverlay`).
- **Fullscreen graph is local shell state** (`_fullGraph`), mounted above the overlay stack, dismissed by scrim tap or `shell-graph-exit`. It is **not** URL-driven yet — N7 owns the real chart.
- `HomePage` (`lib/features/home/`) is deleted; `/live` is the initial route.

**Deviations / gotchas**
- The task's "`PhaseTrack`-prefixed phone frame" is read as "prefix the shell widgets (`Shell…`)"; `PhaseTrack` is a probe primitive (N3.21) and is not part of the frame. No `PhaseTrack` is used in the shell.
- The status-bar clock is static (one `shellClockProvider` read, no ticker) — a repeating clock would break `pumpAndSettle`. The prototype ticks every second; cosmetic only.
- Toast lifetimes use `SmokeMotion.pulse` (2.0 s) not the prototype's 2.2 s, because no `Duration` literal may appear outside `lib/design/`.
- `showSheet`/`showModalCard` use the root Navigator, so in the wide debug preview they cover the dev panel too; named overlays stay inside the phone frame.
- The `AppShell` wide branch constrains the frame to 390 wide / `min(844, height)`; the frame is the app, not a drawn bezel (no fake rounded bezel on a real device).

**Follow-ups for later tasks**
- N5–N13 replace the `destinations.dart` placeholders and the placeholder overlay bodies; keep using `ShellScope.of(context)` for overlay/toast/fullscreen and the N2 providers for data.
- N7: wire the fullscreen graph host body and consider making fullscreen state URL-driven (`?fullscreen=1`).
- N11: `AlertsBell` count already comes from `snapshot.alarms` unacked; ack wiring is N11's.
- N16: consider gating `/design` behind a debug flag.

## T06 — N5 Live: alerts, cook header, stopwatch, instrument mode, adopt banner, probe rail

Status: **done**. `flutter test` green (**256**; was 229); `flutter analyze` clean; `dart format` clean; `dart test test/domain test/data` green (**134**; was 131). Live is now a real screen.

**Real paths**
- `app/lib/features/live/` — the feature: `live_page.dart` (`LivePage`, `liveNowProvider`), `alarm_strips.dart` (`LiveAlarmStrips`, `orderedUnackedAlarms`), `cook_header.dart` (`CookHeaderCard`, `StopwatchCard`), `instrument_card.dart`, `summary_strip.dart`, `probe_rail.dart` (`LiveProbeRail`, `CompactProbeTile`), `mini_graph.dart`, `live_format.dart` (pure `fmtStopwatch`/`fmtClock`/`fmtDuration`/`fmtEta`/`tempParts`/`probeName`), `live_overlays.dart` (`MarkSheetBody`, `EditStartBody`, `AdoptSessionBody`, `AdoptSessionActions`, `kMarkKinds`), barrel `live.dart`.
- Tests `app/test/features/live_test.dart` (widgets), `app/test/features/live_format_test.dart` (pure). Golden regenerated: `app/test/golden/goldens/app_shell.golden.txt` now describes the real Live page.

**Commands that work (repo root / `app/`)**
- `cd app && flutter test` — full suite incl. goldens (256 pass).
- `cd app && flutter test test/features/live_test.dart test/features/live_format_test.dart` — the N5 gate (24 pass).
- `cd app && dart test test/domain test/data` — data/domain gate (134 pass).
- `make app.golden` — regenerates the shell golden (needs the deterministic overrides below).

**Contract facts later tasks need**
- **`ShellScope` gained `openScreen(ShellScreen)`.** Destinations navigate with it (`Live` → Graph/Temps). `AppShell` wires it to `_onNavSelect`.
- **`ShellScrollHost` moved out of `AppShell` and into each destination.** `AppShell` now does `Expanded(child: widget.child)` so the go_router nested Navigator gets a bounded height. `LivePage` and `DestinationPlaceholder` wrap their own body in `ShellScrollHost`. Why: a Navigator inside a vertical `SingleChildScrollView` shrink-wraps during route transitions and overflows a tall destination (transient RenderFlex overflow on navigation). If a later destination forgets its `ShellScrollHost`, it will not scroll.
- **Overlay framework**: `SheetOverlay`/`ModalOverlay` gained optional `bodyBuilder`/`actionsBuilder` (`Widget Function(VoidCallback dismiss)`); `ShellModalCard` gained `actions`. Use them so an overlay body can apply an action and close without importing the shell. `resolveOverlay` now returns real bodies for `mark` (sheet), `editStart` and `adopt` (modals). `adopt` uses `actionsBuilder` (keys `live-adopt-confirm`/`live-adopt-cancel`) instead of the default confirm row.
- **`BridgeRepository` gained three methods**: `setCookPaused(bool)` (UI-only flag; never touches `startedAtMs`), `setCookStart(int)` (moves the window, keeps samples/marks), `discardSession()` (drops `pendingSession`). `MockBridgeRepository` implements them; **N15 must implement them on the real transport**.
- **`MarkKind` gained `spritz` and `turn`** (app-originated user kinds; the wire `mark_rec.kind` has neither — it has `alarm`/`auto_detected` which the UI mark sheet omits). N15 must map or extend the wire.
- `liveNowProvider` is the Live clock (overridable). No ticker is owned: the stopwatch reads it once per build (N4 status-clock precedent). Pause captures the elapsed at the tap and freezes the display.
- **I14 on Live**: when the adopt banner and the instrument card are both present (`existing`), the banner's "Adopt session" is the only ember `PrimaryAction`; the instrument card's "Start a cook" demotes to a normal `SmokeButton` (`InstrumentModeCard(primary: false)`). The prototype had two primaries there.
- Keys: `live-page`, `live-alarm-*`/`live-alarm-ack-all`, `live-notice`, `live-adopt-banner`/`live-adopt`/`live-discard-session`, `live-cook-header`/`live-cook-name`/`live-cook-settings`, `live-stopwatch`/`live-stopwatch-time`/`live-stopwatch-toggle`/`live-stopwatch-edit-start`, `live-instrument`/`live-instrument-start`/`live-instrument-graph`, `live-summary-*`, `live-probe-<jack>`/`live-probe-temp-<jack>`/`live-probe-sub-<jack>`, `live-mini-graph`/`live-mini-graph-label`, `live-probes-details`, `mark-kind-<name>`/`mark-note`/`mark-save`, `edit-start-<mins>`/`edit-start-current`.

**Deviations / gotchas**
- `shell_test.dart`'s `wrap()` now includes a `ProviderScope` because the overlay bodies read providers.
- `app_shell_golden_test.dart` now overrides `bridgeRepositoryProvider` (`MockBridgeRepository(nowMs: fixed)`), `shellClockProvider` and `liveNowProvider` to one fixed instant; otherwise the elapsed readouts are non-deterministic. Any future golden that renders Live must do the same.
- The mini graph is a `spark`-based preview (per-series min/max scaling, like the prototype's `miniChart`); N7 owns the real chart.
- The `mark` sheet's 8 kinds map straight onto `MarkKind`; `lidOpen`/`probeMoved`/`phaseChange` are the wire spellings.
- `_OverlayPlaceholder` still backs every other overlay (N6/N8/N9/N10/N11/N13/N14).

**Follow-ups for later tasks**
- N6: `DevOverlay.probe` body is still a placeholder; the Live probe tile opens it with `jack`.
- N9: the setup sheet must honour the `context=edit` prop the Live cook-settings button passes (`openOverlay(DevOverlay.setup, {'context': 'edit'})`).
- N7: replace the mini graph preview and the fullscreen host body.
- N11: `DevOverlay.alarmDetail` body (Live opens it with `id`/`tier`); ack + ack-all already work against the repo.
- N15: implement the three new repo methods and resolve `MarkKind.spritz`/`turn` against the wire.
- N16: consider adding Live goldens for `idle`/`existing`/`offline` (only `running` is pinned today, via `app_shell`).

## T07 — N6 Temps: per-probe cards, probe sheet, roles/targets, detached handling

Status: **done**. `make app.test` green (**302** tests; was 256); `dart test test/domain test/data` green (**136**; was 134). Temps is a real destination.

**Real paths**
- `app/lib/features/temps/` — `temps_page.dart` (`TempsPage`), `temp_card.dart` (`TempCard`), `probe_sheet.dart` (`ProbeSheetBody`), `temps_format.dart` (pure), barrel `temps.dart`.
- `app/lib/features/shell/destinations.dart` — `TempsDestination` → `const TempsPage()`.
- `app/lib/features/shell/overlay.dart` — `DevOverlay.probe` → `ProbeSheetBody` via `bodyBuilder` (jack from the `jack` prop, default 1).
- Tests `app/test/features/temps_test.dart` (19), `app/test/features/temps_format_test.dart` (24), `app/test/golden/temps_golden_test.dart` + `app/test/golden/goldens/temps.golden.txt`; 2 new repo tests in `app/test/data/mock_repository_test.dart`.

**Commands that work**
- `make app.test` — analyze + format + full `flutter test` (302 pass).
- `cd app && flutter test test/features/temps_test.dart test/features/temps_format_test.dart` — N6 gate (43 pass).
- `cd app && dart test test/domain test/data` — data/domain gate (136 pass).
- `make app.golden` regenerates `temps.golden.txt` too.

**Contract facts later tasks need**
- Pure helpers in `temps_format.dart`: `attachedProbes`/`detachedProbes` (attached **and** role != unused vs not), `probeFor`, `cookEntryFor`, `updatedWord`, `probeFreshnessWord`, `kProbePhases`, `probePhaseIndex`, `trendFor`, `fmtTempUnit`, `tempMetaCells`, `pullForDoneness`, `selectedDoneness`.
- Keys: `temps-page`, `temps-attached-count`/`temps-unit-toggle`, `temps-card-<jack>`, `temps-temp-<jack>` (Text.rich), `temps-fresh-<jack>`, `temps-progress-<jack>`, `temps-meta-<label-slug>-<jack>`, `temps-detached-<jack>`/`temps-detached-role-<jack>`, `temps-empty`; sheet `probe-sheet-*` (`body/header/name/sub/temp/spark/phase/stats/roles/doneness/pull-notice/set-target`), `probe-share`.
- Editors call `repo.probeRole` / `repo.setTarget`; "Set a target" opens `DevOverlay.setup` with `context=edit` + `jack=N`.

**Deviations / gotchas**
- **`probeRole(unused)` clears `attached`/`temp` (N2)**, so a re-roled jack reads `Unplugged` on Live and moves to Temps' "Not attached" (I3 wins over the role word).
- I4 gate is `Freshness.showsDerived` (live **or** aging), not the prototype's `=== 'live'`.
- `probeFreshnessWord`: `frozen → "Stale"`, `stale → "—"` (prototype-exact). Trend labels are always `° F/hr`; temperatures and the pit band do convert with the unit toggle.
- `Test alarm` / `Share this probe` only toast (no repo method): N11/N12 own the real ones. I12's refusal lives in N9; N6 offers the preset ladder and a floor-clamped `pullTempFor` notice.
- `PhaseTrack` is prototype-exact: target crossing → `Ready`, so `Resting` is never current; with `pull == target`, `Pull now` is unreachable.
- `shell_router_test.dart` updated: fullscreen/toast now use the Graph placeholder; the Temps nav test asserts `temps-page`; the probe deep link expects two "Probe 3" texts.

**Follow-ups**
- N7: real chart (the sheet spark is the N3 `Sparkline`).
- N9: honour `context=edit` + `jack` from "Set a target".
- N11: `DevOverlay.alarmDetail` + real test alarm. N12: share/export.
- N16: add Temps goldens for `idle`/`offline` (only `running` pinned).
