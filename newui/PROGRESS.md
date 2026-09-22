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

## T08 — N7 Graph: chart, ranges, zoom/pan, fullscreen, legend isolate, targets/bands, stats

Status: **done**. `make app.test` green (**339**; N7 adds 36 — 10 widget + 19 projection + 7 chart-data); `flutter analyze` and format check clean; `dart test test/domain test/data` still green (136). Graph is a real destination and the fullscreen host has the real chart.

**Real paths (all under `app/lib/features/graph/`; barrel `graph.dart`)**
- `graph_format.dart` — pure: `GraphRange`, `GraphViewState`, `GraphDomain` + prototype-exact `graphDomain()`, `seriesDashArray`/`seriesDash`/`seriesWidth`, `buildGraphSamples`/`buildGraphSeries`, `graphYBounds`, `graphTargets`/`graphPitBand`/`graphMarks`/`graphWindowStats`, `graphZoomHint`, `legendValue`.
- `graph_model.dart` — `graphNowProvider`, `graphViewProvider` (`NotifierProvider<GraphViewNotifier, GraphViewState>`), `graphSamplesProvider`, `graphModelProvider` + `GraphModel`.
- `chart_data.dart` — `buildCookChartData(...) → LineChartData`; `chartAreaFillAlpha = 0.10`; `chartBarSeries(...)`.
- `cook_chart.dart` — `CookChart` (fl_chart `LineChart`, `duration: Duration.zero`).
- `graph_page.dart` — `GraphPage`; `graph_fullscreen.dart` — `GraphFullscreenBody`.
- Wired: `features/shell/destinations.dart` `GraphDestination` → `GraphPage`; `features/shell/shell.dart` fullscreen child → `GraphFullscreenBody`. **`ShellFullscreenGraphPlaceholder` was deleted**; `test/features/shell_test.dart` now passes a plain child.

**Commands that work**
- `make app.test` — the N7 gate (338 pass).
- `cd app && flutter test test/features/graph_test.dart test/features/graph_format_test.dart test/features/graph_chart_data_test.dart` — 10 + 19 + 7 = 36.
- `cd app && dart test test/domain test/data` — unchanged (136).
- `make app.golden` regenerates `app/test/golden/goldens/graph.golden.txt`.

**Contract facts later tasks need**
- **`CookChart` is provider-free**: `CookChart(model: ChartSeriesModel, domain: GraphDomain, unit:, series: List<GraphSeriesMeta>, targets:, band:, marks:, isolatedJack:, onZoomFactor:, onPanMinutes:)`. N12's history/detail chart reuses it with a different `ChartSeriesModel` (N7.16). `buildCookChartData` is the unit-test surface for the invariants.
- **The mock has no sample stream.** `buildGraphSamples` resamples `ProbeState.spark` onto one aligned session-seconds grid (30 s cadence, widened so the grid ≤1200 points) then `buildGraphSeries` calls N1.14 `buildChartSeries` (run-split before LTTB, envelope >1200). N15 must feed real `Sample`s through the same `buildGraphSeries`.
- **View state is shared** via `graphViewProvider`, so the fullscreen chart is the inline chart for the same window by construction. Fullscreen itself is still **local shell state**, not `?fullscreen=1` (N4 follow-up not done).
- Range chips reset zoom/pan; zoom cap 40×; pan never goes negative. Hint text: `1.5× zoom` / `Pinch or scroll to zoom · drag to pan`.
- Keys: `graph-page`, `graph-range`, `graph-zoom-out`/`graph-zoom-in`/`graph-fullscreen`, `graph-chart`, `graph-legend`, `graph-zoom-hint`, `graph-reset`, `graph-stats`, `graph-stat-<jack>`, `graph-add-mark`, `graph-share`, `graph-empty`, `graph-crosshair`; fullscreen `shell-graph-title`, `graph-fullscreen-zoom`, `graph-pan-back`/`graph-pan-fwd`, `graph-fullscreen-zoom-out`/`graph-fullscreen-zoom-in`/`graph-fullscreen-reset`, `shell-graph-exit`, `graph-fullscreen-chart`, `graph-fullscreen-legend`.
- Crosshair = fl_chart `touchCallback` → custom `graph-crosshair` tip; each row is the bar's nearest **real** spot (built-in tooltip is off).
- `graphNowProvider` (defaults `DateTime.now()`) pins the window; any graph golden/test must override it **and** `shellClockProvider` and pass a fixed `MockBridgeRepository`.

**Deviations / gotchas**
- Pinch zoom is best-effort (`onScaleUpdate` when `pointerCount >= 2`, untested); wheel + zoom buttons + drag-to-pan are fully wired and tested. `tester.drag` needs several `moveBy`s — a single-move drag only emits the pan start, not an update.
- Share is a toast (`Opening share sheet — graph`); CSV/share sheet is N15.
- The Live mini-graph preview (`LiveMiniGraphCard`) is **unchanged** (still an N3 `Sparkline`-style spark). Swapping it to `CookChart` is a follow-up and would move the `app_shell` golden.
- fl_chart draws 4 y-interval gridlines (min/max forced labels off) instead of the prototype's 5; same display-unit extent.
- `shell_router_test.dart` updated: the graph deep link asserts `graph-page`; fullscreen taps `graph-fullscreen`; the toast test now uses the Timeline placeholder.

**Follow-ups**
- N12: reuse `CookChart` for the cook-detail chart.
- N15: real samples → `buildGraphSeries`; graph share/CSV; `MarkKind.spritz`/`turn` on the wire.
- N16: consider graph goldens for `idle`/`offline` (only `running` pinned) and the fullscreen golden.

## T09 — N8 Timeline: Gantt, upcoming interventions, event rail, timeline DB projection

Status: **done**. `make app.test` green (**370**; N8 adds 31 — 18 pure + 11 widget + 1 golden + 1 repo); `flutter analyze` and format check clean; `dart test test/domain test/data` green (**137**, was 136). Timeline is a real destination.

**Real paths (all under `app/lib/features/timeline/`; barrel `timeline.dart`)**
- `timeline_format.dart` — pure: `buildTimelineModel`, `buildUpcoming`, `buildRailEvents`, `TimelineModel`/`TimelineRow`/`UpcomingIntervention`/`TimelineEvent`/`InterventionKind`, `markKindWord`, `railTimeLabel`, the fraction constants and `kFallbackTimeline`.
- `timeline_model.dart` — `timelineNowProvider`, `timelineModelProvider`.
- `timeline_page.dart` — `TimelinePage` + `_ScheduleHeader`/`_Gantt`/`_UpcomingGrid`/`_Reminders`/`_EventRail`.
- Wired: `features/shell/destinations.dart` `TimelineDestination` → `const TimelinePage()`.
- Tests `app/test/features/timeline_format_test.dart` (17), `app/test/features/timeline_test.dart` (11), `app/test/golden/timeline_golden_test.dart` + `goldens/timeline.golden.txt`; one new repo test in `app/test/data/mock_repository_test.dart`.

**Commands that work**
- `make app.test` — the N8 gate (370 pass).
- `cd app && flutter test test/features/timeline_test.dart test/features/timeline_format_test.dart` — 28 fast tests.
- `cd app && dart test test/domain test/data` — data/domain gate (137).
- `make app.golden` regenerates `timeline.golden.txt` too.

**Contract facts later tasks need**
- `buildTimelineModel({cook, pendingSession, catalog, marks, nowMs, autoWrapReminder}) → TimelineModel`. Prototype-exact rules: bar = `totalMin.mid`, stall = 38–72 % of the bar, wrap tick = 55 %, domain tail = 45 min, served-by = +30 min, upcoming capped at 4.
- `TimelineRow`: `endMs`, `wrapAtMs`, `stallStartMs`/`stallEndMs`, `progressAt(nowMs)`, `hasWrapMilestone`/`hasStall`/`hasSpritz`, resolved `wrapEnabled`/`spritzEnabled`. **The wrap milestone draws whenever `timeline.wrap != null`; the per-cook toggle only gates the nudge.**
- **`CookItem` gained three fields**: `timeline` (`CookTimeline?`, the N9.18 custom-food seam), `wrapEnabled` and `spritzEnabled` (`bool?`, null = seed from the cut's timeline).
- **`BridgeRepository` gained `setItemInterventions(jack, {wrap, spritz})`** (null = leave unchanged). Mock implemented; **N15 must implement it on the real transport and serialise the three new `CookItem` fields.**
- Keys: `timeline-page`, `timeline-empty`, `timeline-header`/`-off-by`/`-served-by`/`-item-count`/`-estimate-note`, `timeline-gantt`/`-axis`/`-gantt-empty`, `timeline-row-<jack>`/`-row-name-<jack>`/`-bar-<jack>`/`-row-end-<jack>`/`-stall-<jack>`/`-wrap-<jack>`/`-now-<jack>`/`-now-label`, `timeline-upcoming`/`-note`/`-empty`/`-<i>`/`-time-<i>`, `timeline-reminders`/`-off`/`-empty`/`-<jack>`/`-wrap-toggle-<jack>`/`-spritz-toggle-<jack>`, `timeline-rail`/`-empty`/`-<i>`/`-dot-<i>`/`-time-<i>`/`-now`, `timeline-add`, `timeline-log-event`.

**Deviations / gotchas**
- **Upcoming is future-only.** `app.js` lists every turn regardless of time, so `running` would show the sausage turn ~35 min in the past; `buildUpcoming` drops `atMs < nowMs`.
- **The now line is on every track** (task N8.5), not just jack 1 as in `app.js`; the `NOW` label is on the first track only.
- **The per-cook reminder toggles are a new surface** — `app.js` has no toggles on the Timeline view (the seed lives in setup). They write the fields N9.11 will seed.
- `railTimeLabel` appends `· expected` to predictions (prototype); N8.8's wording is also in `timeline-estimate-note` and `timeline-upcoming-note`.
- Q2 resolved: timeline DB stays read-only; the only per-cook edit is wrap/spritz.
- `MockBridgeRepository._addItem` does **not** yet carry `CookItem.timeline` across a re-add — N9 must set it.
- `shell_router_test.dart` updated: the toast test now uses Settings (Timeline is real), and the dev-panel timeline test asserts `timeline-empty` (the `idle` fixture has no cook).

**Follow-ups**
- N9.11: seed `wrapEnabled`/`spritzEnabled` from the setup toggle; thread custom-food `CookItem.timeline` through `addItem`/`startCook`.
- N15: implement `setItemInterventions` and `CookItem` serialisation.
- N16: consider Timeline goldens for `idle`/`existing`/`offline` (only `running` pinned).

## T10 — N9 Catalog and setup: new/existing/watch, search, styles, custom food, add-item guard

Status: **done**. `flutter test` green (**409**; N9 adds 39 — 20 pure + 17 widget + 2 repo); `flutter analyze` and format check clean; `dart test test/domain test/data` green (**139**, was 137). The catalog-as-setup flow is real in the `setup` overlay, and custom foods in `customFood`.

**Real paths (all under `app/lib/features/setup/`; barrel `setup.dart`)**
- `setup_format.dart` — pure: `SetupMode` (newCook/existing/watch), `SetupFood`, `setupFoods`, `searchSetupFoods`, `setupFoodById`, `setupStylesFor`, `setupStyleById`, `SetupSummary` + `setupSummary`, `expectedCookLabel`, `busyJacks`/`jackIsBusy`/`jackLabel`/`firstFreeJack`, `timelineForItem`, `longItemDelayMin`, `customTargetRefusal`, `customFoodFromForm`, `kCustomFoodGlyphs`, `kCustomFoodHazards`.
- `setup_sheet.dart` — `SetupSheetBody` (the `?overlay=setup` body); `custom_food_sheet.dart` — `CustomFoodSheetBody` (the `?overlay=customFood` body).
- `features/shell/overlay.dart` now resolves both names to the real bodies (setup reads `context=edit`, `jack`, `food` props).

**Commands that work (repo root)**
- `make app.test` — the N9 gate (analyze + format + `flutter test`, 409 pass).
- `cd app && flutter test test/features/setup_test.dart test/features/setup_format_test.dart` — 37 fast N9 tests.
- `cd app && dart test test/domain test/data` — data/domain gate (139).
- No golden changed (the setup sheet has no golden; it is an overlay).

**Contract facts later tasks need**
- **`BridgeRepository.startCook`/`addItem` gained optional `pullF10`, `timeline`, `wrap`, `spritz`; `startCook` also `startedAtMs` and `adoptPendingSession`.** `adoptPendingSession: true` (with a pending session) backdates the cook to `pendingSession.startedAtMs`, assigns the item, clears the session and sets `notice: 'Cook adopted · pulled N samples'` (N9.15, I10). The old calls are source-compatible.
- **`CustomFood` gained `glyph` (`String`, default `'unstated'`), `thickness` (`CutThickness`, default medium) and `blurb` (`String`, default `'Custom food'`).** All additive. Custom foods live in `AppSettings.customCatalog` (prefs), not the catalog table; the picker reads them via `settingsProvider`.
- **A custom food's timeline travels on `CookItem.timeline`** (N9.18); the picker passes `timeline:` to `startCook` only for custom foods or a style with its own timeline — built-ins pass null so the catalog timeline table drives (an intentional choice, see deviations).
- The overlay body's title is static (`Cook setup`); the **mode-specific sub copy is inside the body** (`setup-mode-sub`), not the shell header, because `resolveOverlay` has no mode. Deviation from `setupScrim`'s per-mode title/sub.
- Keys: `setup-sheet`, `setup-modes`, `setup-mode-sub`, `setup-watch-notice`, `setup-existing-notice`/`-session`/`-when`/`-offsets`/`-offset-<mins>`, `setup-catalog-search`/`-clear`/`-count`/`-empty`, `setup-categories`, `setup-custom-food`, `setup-food-<id>`/`-meta-<id>`, `setup-styles`/`-note`/`style-<id>`, `setup-doneness`, `setup-summary`/`-target`/`-pull`/`-rest`/`-cook`/`-style`, `setup-jacks`/`jack-<n>`/`-jack-notice`, `setup-wrap-row`/`setup-spritz-row`, `setup-start`, `setup-safety-refusal`; custom form `custom-food-sheet`/`-name`/`-category`/`-glyph-<g>`/`-hazard`/`-thickness`/`-pit-lo`/`-pit-hi`/`-target`/`-rest`/`-total-lo`/`-total-hi`/`-wrap`/`-spritz`/`-save`/`-cancel`/`-error`.
- The long-item confirm uses the imperative `showModalCard(context, ...)` from `shell/overlay.dart` (not the `confirm` named overlay, which stays a placeholder) and its default confirm key is `shell-overlay-confirm`.

**Deviations / gotchas**
- **Built-in preset targets keep the prototype's reviewer-pinned rungs; the I12 gate runs on custom targets only.** `content_validation_test.dart` intentionally pins a few below-floor catalog rungs (raw tuna, rosé duck, …), so re-gating them here would contradict the catalog owner. `customTargetRefusal` refuses a user-authored below-floor target; `CookPlan`'s constructor remains the gate for a real plan. Documented in `setup_format.dart`.
- For `existing` mode with a pending session, the session is always cleared once a cook starts, even when the user picks "I will set a time" (the explicit start overrides the anchor). This keeps the "pull the collected samples" promise without leaving an unadopted session behind.
- **`_addItem` now carries `CookItem.timeline` and the wrap/spritz overrides across a re-add** (the T09 follow-up). The T09 note "`_addItem` does not carry `timeline`" is resolved.
- The `Add to cook` label appears in `context=edit` **or** whenever a cook is already active is not distinguished — the label is edit-context only; behaviour (append) is identical either way because `startCook` appends to an active cook.
- `_CatalogPicker` shows only the categories present in the picker list (all 10 with the shipped catalog). A search shows no category chip selected (`value: ''`), matching "search overrides the category".
- The setup body renders inside the shell's `ShellSheet` `SingleChildScrollView`; in widget tests it is wrapped in a `SingleChildScrollView` and interacted with via `ensureVisible`.

**Follow-ups**
- N11/N12/N13/N14 still own their overlay bodies (`alarms`, `alarmDetail`, `firmware`, …); `confirm` is still a placeholder (N9 uses `showModalCard` directly).
- N15 must implement the extended `startCook`/`addItem` signatures and serialise `CustomFood.glyph`/`thickness`/`blurb`, `CookItem.timeline`, `wrapEnabled`, `spritzEnabled`.
- N16: consider a setup-sheet golden for each mode (`new`/`existing`/`watch`) and a custom-food golden.

## T11 — N10 Connection and provisioning: transport chip, connect sheet, AP/STA flows, rollback UX

Status: **done**. `make app.test` green (**451**; N10 adds 42 — 17 pure + 21 widget + 4 repo); `flutter analyze` and format check clean; `dart test test/domain test/data` green (**143**, was 139). No golden changed.

**Real paths (all under `app/lib/features/connection/`; barrel `connection.dart`)**
- `connection_format.dart` — pure: `signalWord`, `agoLabel`, `activeModeId`/`activeMode`, `modeStateWord`, `wifiModeLabel`, `bluetoothSubtitle`, `bridgeBluetoothSubtitle`, `wifiSubtitle`, `bridgeWifiSubtitle`, `ConnectionError`+`connectionErrorOf`/`connectionErrorCopy`, `connectionHasProblem`, `ModeFeature`+`featureLabel`/`featureReason`/`featureAvailable`/`capabilityRows`, `fullHistoryRefusal`, `kScannedNetworks`, `kHotspotSsid`/`kHotspotPasskey`.
- `connect_sheet.dart` — `ConnectSheetBody` (N10.2/N10.3/N10.4/N10.6).
- `mode_cards.dart` — `ConnectionModeCard`, `ConnectionModesBody` (the `modes` sheet), `ModesReferenceBody` (N10.5).
- `provision_sheets.dart` — `ProvisionStaBody` (N10.7/N10.11), `ProvisionApBody` (N10.8).
- `bridge_card.dart` — `BridgeCard` (N10.12–N10.15) for Settings.
- Wired: `shell/overlay.dart` resolves `connect`/`modes`/`modesRef`/`provisionSta`/`provisionAp` to the real bodies; `shell/destinations.dart` mounts `BridgeCard` in the Settings placeholder.

**Commands that work**
- `make app.test` — the N10 gate (analyze + format + `flutter test`, 451 pass).
- `cd app && flutter test test/features/connection_test.dart test/features/connection_format_test.dart` — 38 fast N10 tests.
- `cd app && dart test test/domain test/data` — data/domain gate (143).
- No golden regeneration needed.

**Contract facts later tasks need**
- **`BridgeRepository` gained four methods** (mock implemented, N15 must implement on the real transport): `joinWifi({ssid, password})` (password is an argument only — never stored), `useHotspot()`, `confirmHotspotJoined()`, `forgetNetwork()`. `resync()` is unchanged; the "Re-synced · up to date" notice is a UI toast, not a snapshot notice.
- **Active mode is derived, not read.** The prototype reads `connection.mode`, which `mock-data.js` never sets (its card never highlights). `activeModeId(c)` derives it from `primary` + `wifi.mode` — an intentional fix.
- **Two-hop discipline (N10.13)** lives in the Settings subtitles: `bridgeBluetoothSubtitle` says `Phone → bridge · …`; `bridgeWifiSubtitle` says `Bridge → router · …` (or `Phone → bridge (hotspot) · …` for AP). The connect sheet uses the terse prototype subtitles.
- **`wifiSubtitle`/`bridgeWifiSubtitle` append `agoLabel(lastSyncS)`**, so both link rows carry health + signal + last sync (the prototype only put it on Bluetooth).
- **`connectionErrorCopy` is the one error-copy source** (N10.11/I15): `wrong_password`, `router_unreachable`, `switch_failed` (falls back to `snapshot.notice`). The connect sheet shows it with Try again + Use hotspot; the STA sheet shows it with a hotspot escape hatch and relabels its primary "Try again".
- **I13 capability copy** is `featureReason` ("Full history needs Wi-Fi."); the reference matrix prints it under each missing row and `BridgeCard` shows `bridge-capability` when the active transport lacks full history. `fullHistoryRefusal` returns null when no mode is carrying data.
- **`BridgeCard` is the N10.12 seam** mounted inside the Settings `DestinationPlaceholder`; N13 replaces the rest of that tree.
- Keys: connect `connection-sheet`/`-device`/`-link-bt`/`-link-wifi`/`-link-*-data`/`-battery`/`-recording`/`-error`/`-try-again`/`-use-hotspot`/`-switch-label`/`-mode-<id>`/`-mode-info-<id>`/`-mode-state-<id>`/`-rollback-notice`/`-resync`/`-disconnect`; modes `connection-modes`/`-notice`; reference `connection-modes-ref`/`-ref-notice`/`-ref-card-<id>`/`-ref-good-<id>-<text>`/`-ref-limited-<id>-<text>`/`-ref-cap-<feature>-<id>`/`-ref-reason-<feature>-<id>`; STA `provision-sta-body`/`-notice`/`-net-<ssid>`/`-password`/`-error`/`-use-hotspot`/`-connect`/`-cancel`; AP `provision-ap-body`/`-notice`/`-hotspot`/`-passkey`/`-steps`/`-open`/`-joined`/`-note`; Settings `bridge-card`/`-bt`/`-bt-data`/`-bt-warm`/`-wifi`/`-wifi-data`/`-battery`/`-recording`/`-capability`/`-resync`/`-change-mode`/`-disconnect`/`-forget-network`.

**Deviations / gotchas**
- Sheet sub-titles are static (`resolveOverlay` has no snapshot): connect sub is `Bluetooth and Wi-Fi`, not the device name; the device name is the first card.
- The mock transitions through `joinWifi`/`useHotspot`/`confirmHotspotJoined` and the dev events; named errors are rendered from `ConnectionState`, so tests set the scenario rather than simulating async failure.
- `shell_router_test.dart`'s per-overlay scroll test now opens the `modesRef` sheet from the connect sheet's `?` button (the connect body is real, so `shell-overlay-copy` no longer exists there).
- `ModesReferenceBody` keeps `onDone` for the host contract but does not call it (the `?` opens a new overlay).
- STA "Try again" re-submits; the hotspot escape hatch is a ghost button (I14: one ember primary).
- No Wi-Fi secret is persisted; a repo test asserts the snapshot `toString()` never contains the password.

**Follow-ups**
- N13: replace the Settings placeholder (the `BridgeCard` is the N10.12 seam); firmware/OTA rows stay N13's.
- N14: onboarding step 5 can reuse `ConnectionModeCard`; the wizard's mode step is not wired here.
- N15: implement the four new repository methods on the real transport; keep the password out of storage.
- N16: consider connect-sheet/reference goldens per scenario (none exist).

## T12 — N11 Alarms and monitoring: strip/sheet/detail, two tiers, rules, delivery, quiet hours

Status: **done**. `flutter test` green (**502**; N11 adds 51 — 35 pure + 12 widget
+ 4 repo); `flutter analyze` and format check clean; `dart test test/domain
test/data` green (**169**, was 143). No golden changed.

**Real paths**
- `app/lib/data/alarms/notification_policy.dart` — pure `planNotifications()`,
  `NotificationChannel` (4), `AppFinding` (6), `QuietHours`, `PendingNotification`,
  `NotificationPlan`, `channelFor`, `alarmTitle`, `findingTitle/Body`,
  `escalationRung`, `kEscalateToRepeat` (5 min), `kEscalateToFullScreen` (10 min),
  `orderedActiveAlarms`, `isActiveAlarm`, `severityRank`, `snoozeUntilMs`,
  `kMaxSnoozeMinutes`.
- `app/lib/features/alarms/` — `alarms_sheet.dart` (`AlarmsSheetBody`,
  `alarmsNowProvider`), `alarm_detail_sheet.dart` (`AlarmDetailSheetBody`),
  `alarms_format.dart` (`deliveryVerdict`, `deviceRules`/`appRules`,
  `deriveFindings`, `severityWord`/`tierWord`, `agoWord`/`firedLine`,
  `whyFiredRows`, `ruleIsEditable`), barrel `alarms.dart`.
- `shell/overlay.dart` resolves `alarms` + `alarmDetail` to the real bodies
  (`alarmDetail` reads `props['id']`).
- Tests `app/test/data/notification_policy_test.dart` (pure, `package:test`),
  `app/test/features/alarms_format_test.dart` (pure), `app/test/features/alarms_test.dart`
  (12 widgets), 4 repo tests in `app/test/data/mock_repository_test.dart`.

**Commands that work**
- `make app.test` — the N11 gate (analyze + format + `flutter test`, 502 pass).
- `cd app && flutter test test/features/alarms_test.dart` — 12.
- `cd app && dart test test/data/notification_policy_test.dart test/features/alarms_format_test.dart` — 35.
- `cd app && dart test test/domain test/data` — data/domain gate (169).

**Contract facts later tasks need**
- **`BridgeRepository` gained five methods** (mock implemented; N15 must implement
  on the real transport / persist app rules): `snoozeAlarm(id, {minutes=10})`,
  `sendTestAlarm()`, `setAlarmRuleEnabled(id, enabled)`,
  `saveAppAlarmRule(AlarmRule)` (app-tier only; a device rule is refused),
  `deleteAppAlarmRule(id)`. `alarmRules` is now a mutable mock list (still 9+3).
- **`Alarm` gained `snoozedUntilMs`** (`snoozedAt(nowMs)`, JSON `snoozed_until_ms`).
  A snooze is app-side delivery only: the alarm stays raised and unacked.
- **N11.10 interpretation**: `preferManualAlarm` silences a *non-critical* device
  alarm's notification while an app insight/alarm is active; critical never
  defers and the list is unchanged (I2). Pinned by tests.
- **N11.15**: `MockBridgeRepository.disconnect()` (and `ble-dropped` → offline)
  appends a `bridge_unreachable` app insight once per down-link while a cook is
  active.
- The policy lives in `lib/data/alarms/` (not `lib/domain/`) because it reasons
  over the data-layer `Alarm`; it is Flutter-free and in the `dart test` gate.
- Q4 resolved: pause is display-only; `planNotifications` reads only alarms + the
  wall clock.

**Deviations / gotchas**
- `AlarmTier` exists in both `data/model/alarm.dart` and `design/atoms.dart`;
  feature/test files must alias or `hide` one.
- `alarmsNowProvider` pins the sheet's relative times — override it in any test
  that settles the sheet.
- The alarms sheet renders inside the shell `ShellSheet` scroll view; widget tests
  wrap it in a `SingleChildScrollView` and `ensureVisible` the lower toggles.
- The `alarms` overlay sub copy is `From the bridge and insights from the app,
  kept separate` (the prototype's).

**Follow-ups**
- N13: the Settings tree's alarms section (N13.4) should reuse this preference +
  rule surface; the same `preferManualAlarm`/`quietHours`/`monitoring` settings.
- N15: implement the five repo methods on the real transport; persist app rules;
  build the Android foreground service + the ongoing notification (N11.14's real
  half). The four channels are already a closed enum.
- N16: consider an alarms-sheet golden; no golden renders an overlay today.





## T13 — N12 History: history groups, cook detail, favourite/repeat/export/delete

Status: **done**. `flutter test` green (**541**; N12 adds 39 — 12 widget + 12
format + 9 export/data + 4 repo + 1 setup prefill + 1 router); `flutter analyze`
and format check clean; `dart test test/domain test/data` green (**182**, was
169). No golden changed.

**Real paths**
- `app/lib/data/export/cook_export.dart` — pure: `historySamples(entry)` (the
  prototype `histPoints` curve, 61 points), `historyRail(entry)` (derived
  milestones), `buildCookCsv({samples, sessionStartedUnixMs})`, `iso8601Utc`,
  `cookCsvHeader`, `kHistorySampleCount`.
- `app/lib/features/history/` — `history_format.dart` (grouping, recap, result
  stats, chart inputs, marks, gaps, filename/summary), `history_model.dart`
  (`historyNowProvider`, `historyGroupsProvider`, `historyUnitProvider`),
  `history_page.dart` (`HistoryPage`), `cook_detail_page.dart`
  (`CookDetailPage`), barrel `history.dart`.
- `HistoryEntry` gained `markEvents` (`List<Mark>`, default `const []`), `gaps`
  (`List<RecordedGap>`, default `const []`), `isOpen`, `durationS` and a full
  `copyWith`. The int `marks` stays the fixture count.
- Wired: `destinations.dart` `HistoryDestination` → `HistoryPage`,
  `CookDetailDestination` → `CookDetailPage(id:)`, and the Settings History row
  now calls `scope.openScreen(ShellScreen.history)`. `SetupSheetBody` gained
  `initialStyleId`; `resolveOverlay(setup)` reads the `style` prop.

**Commands that work**
- `make app.test` — the N12 gate (analyze + format + `flutter test`, 541 pass).
- `cd app && flutter test test/features/history_test.dart test/features/history_format_test.dart` — 24 fast N12 tests.
- `cd app && dart test test/data/cook_export_test.dart` — 9 export tests.
- `cd app && dart test test/domain test/data` — data/domain gate (182).

**Contract facts later tasks need**
- **`BridgeRepository` gained six methods** (mock implemented; **N15 must
  implement on the real CookRepository/drift**): `deleteCook(id)`,
  `setCookNotes(id, notes)`, `setCookEnded(id, ended)`, `addCookMark(id,
  {kind, text, atMs})`, `deleteCookMark(id, index)`, `exportCookCsv(id)`.
  `deleteCook`/the verbs only touch the annotation (I10); `exportCookCsv`
  returns the cache-side CSV string (N15.14 streams it).
- **`ShellScope` gained `openCookDetail(String id)`** (optional, no-op default),
  wired in `AppShell` to `/settings/history/<id>`. Tests that build a
  `ShellScope` without it keep compiling.
- **CSV is byte-compatible with the device's `format=csv`**: header
  `t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi`, detached = empty field,
  `iso8601` empty when the session has no clock (I11). Rows come from
  `historySamples` in the mock (N15 feeds the real cache).
- Keys: `history-page`, `history-start`, `history-notice`, `history-empty`,
  `history-group-thisWeek`/`-earlier`, `history-group-count-<group>`,
  `history-card-<id>`/`-name-<id>`/`-sub-<id>`/`-peak-<id>`; detail
  `cook-detail-page`/`-missing`/`-header`/`-name`/`-line`/`-stars`/`-fav`/
  `-recap`/`-recap-<slug>`/`-result`/`-chart`/`-notes`/`-notes-text`/
  `-notes-edit`/`-notes-sheet`/`-notes-field`/`-notes-save`/`-marks`/
  `-marks-empty`/`-mark-<i>`/`-mark-time-<i>`/`-mark-title-<i>`/
  `-mark-delete-<i>`/`-add-mark`/`-mark-sheet`/`-mark-kinds`/`-mark-text`/
  `-mark-save`/`-pull`/`-gaps`/`-gap-<i>`/`-repeat`/`-share`/`-end`/`-delete`/
  `-delete-note`.

**Deviations / gotchas**
- **The share action is a toast**, not a share sheet (`share_plus` is N15.21).
  The toast reports `cook-<id>.csv · N rows · B bytes`; the CSV itself is real
  and generated from the cache. N15 wires the sheet.
- **The marks rail is derived when the fixture has no explicit marks.** The
  generated seeds carry only a mark *count*; `historyRail` shows the
  prototype's `Cook started / Wrapped (only when wrapped) / Probe-tender /
  Pulled`. Editing a mark seeds `markEvents` from that derived rail, so the
  list card's count and the rail stay in agreement. N15 replaces it with the
  cache's real `Marks` rows.
- **"Pull" is a mark, not a separate status**: `cook-detail-pull` appends a
  `note` mark `Pulled`. End/reopen is `setCookEnded` (status `done`/`open`).
- **`historyGaps` derives from the grid's own cadence**, not the device's 30 s
  (the fixture resamples into 60 points, so a 30 s threshold would read every
  interval as a dropout). Explicit `HistoryEntry.gaps` win.
- Stars use `tokens.warning` (the prototype's `.fav`/`.stars` gold), which is a
  deliberate exception to the strict status-hue rule; it is an accent, not a
  status fill.
- `historySamples` emits `rssi: -60` (the fixture has no signal); mock-only.

**Follow-ups for later tasks**
- N13: the Settings tree replaces the placeholder around the History row.
- N15: implement the six repo methods on the real transport; stream the CSV from
  drift (N15.14); wire `share_plus` (N15.21).
- N16: consider History list + cook-detail goldens (none exist).

## T14 — N13 Settings and device: settings tree, firmware/OTA, diagnostics, restart/forget/factory

Status: **done**. `make app.test` green (**583**; N13 adds 42 — 13 pure + 16 settings widget + 10 device widget + 2 repo + 1 generic-confirm shell); `flutter analyze` and format check clean; `dart test test/domain test/data` green (**184**, was 182). No golden changed.

**Real paths (all under `app/lib/features/settings/`; barrel `settings.dart`)**
- `settings_format.dart` — pure: `VerbSpec`/`kVerbSpecs`/`verbSpec`/`verbFromId`/`verbId`, `OtaGuard`/`otaGuard`, `firmwareRowSub`/`updateFirmwareRowSub`, `channelWord`/`otaChannelWord`, `DiagnosticFact`/`diagnosticFacts`, `storageUsedFraction`/`sessionsKept`/`flashUsed`/`retention`, `LogLevel`/`logLevelOf`, `kDiagnosticsTapCount`/`diagnosticsGateSub`, `appearanceSub`/`unitsSub`/`monitoringSub`.
- `settings_page.dart` — `SettingsPage` (N13.1–N13.8) + the private `_DiagnosticsGateRow`.
- `firmware_sheet.dart` — `FirmwareSheetBody` (N13.9), `FirmwareUpdateSheetBody` (N13.10–N13.12).
- `diagnostics_sheet.dart` — `DiagnosticsSheetBody` (N13.15–N13.17) + `diagnosticsText`.
- `verb_sheet.dart` — `VerbSheetBody` (N13.13/N13.20).
- `settings_widgets.dart` — `FactRow`, `StorageBar`.
- `design/cost_sheet.dart` gained `CostSheetBody` (message + keeps/loses, no title/buttons); `CostSheet` now uses it.
- Wired: `shell/destinations.dart` `SettingsDestination` → `const SettingsPage()` (**`DestinationPlaceholder` deleted**); `shell/overlay.dart` resolves `firmware`/`firmwareUpdate`/`diagnostics`/`verb` to real bodies and `confirm` to `CostSheetBody`.
- `MockBridgeRepository.checkForUpdates()` now also `_set(_snapshot.copyWith())` so device discovery rebuilds watchers (mock-only; see gotchas).
- Tests `app/test/features/settings_format_test.dart` (13), `settings_test.dart` (16), `settings_device_test.dart` (10), `app/test/support/settings_harness.dart` (harness, not a test); 2 repo tests in `app/test/data/mock_repository_test.dart`; 1 generic-confirm test in `app/test/features/shell_test.dart`.

**Commands that work (repo root)**
- `make app.test` — the N13 gate (analyze + format + `flutter test`, 583 pass).
- `cd app && flutter test test/features/settings_test.dart test/features/settings_device_test.dart test/features/settings_format_test.dart` — 39 fast N13 tests.
- `cd app && dart test test/domain test/data` — data/domain gate (184).
- No golden regeneration needed.

**Contract facts later tasks need**
- **`DevOverlay.verb` takes a `kind` prop** (`restart`/`forget`/`factory`/`ota`); its sheet title/sub come from `verbSpec`. A missing/unknown kind renders a **passive** body (`verb-passive`) with no timer and no mutation, so the N4 resolver test can mount it safely. Settings opens it via `scope.openOverlay(DevOverlay.verb, {'kind': spec.id})`.
- **`DevOverlay.confirm` is now real**: its body is `CostSheetBody` built from `title`/`confirm`/`danger` props and `message`, plus `keeps`/`loses` as `|`-separated prop strings. It still cannot run an action (the shell's confirm row only dismisses); the real device flows use imperative `showCostSheet`.
- **`CostSheetBody`** is the shared I8 keeps/loses content; `CostSheet` = `CostSheetBody` + title + primary/ghost buttons. `showCostSheet` is unchanged.
- **`MockBridgeRepository.checkForUpdates()` emits a snapshot nudge** in addition to setting `device.available`. Because `_snapshot.copyWith()` is freezed-*equal*, that nudge alone may not rebuild Riverpod watchers; the firmware sheets therefore also call `ref.invalidate(snapshotProvider)` after a check. N15 should expose device/firmware as a real signal instead.
- Keys: Settings `settings-page`/`-wifi-card`/`-join-wifi`/`-use-hotspot`/`-forget-network`/`-cooks-card`/`-history`/`-prefs-card`/`-units`/`-appearance`/`-profile`/`-density`/`-motion`/`-monitoring`/`-prefer-manual`/`-quiet-hours`/`-hold-ble`/`-wrap-reminders`/`-bridge-card`/`-firmware`/`-update-firmware`/`-about`/`-about-row`/`-about-taps`/`-actions-card`/`-verb-<id>`/`-honesty`/`-honesty-text`; firmware `firmware-sheet`/`-version`/`-channel`/`-rollback`/`-check`/`-install`/`-update-sheet`/`-available`/`-transport-notice`/`-wifi-ok`/`-session-notice`/`-force-row`/`-force`; diagnostics `diagnostics-sheet`/`-identity`/`-id`/`-signal`/`-bt`/`-wifi`/`-storage`/`-storage-bar`/`-logs`/`-log-<i>`; verb `verb-sheet`/`-passive`/`-title`/`-step-<i>`/`-readback`/`-close`/`-keep-open`.

**Deviations / gotchas**
- **Verb steps are paced by `Timer(const SmokeMotion().value)` (600 ms).** `pumpAndSettle` does **not** advance pending timers, so tests must `pump(Duration(milliseconds: 700))` per step (see `runVerb` in `settings_test.dart`). The mock's `performVerb` mutates synchronously, so the last step's read-back is available immediately after it runs.
- **N13.18 five-tap gate** is on the About row: taps 1–4 show `N/5` + a "N more taps" toast, the 5th opens diagnostics and resets. The sub states the requirement, so it is not a dead control (I5). A tap counter left mid-way when the user leaves is not persisted (not tested).
- **N13.22 shared generic confirm**: device cost sheets use `CostSheet` via `showCostSheet`; the named `confirm` overlay renders `CostSheetBody`. The N9 long-item warning still uses `showModalCard` because the named overlay cannot execute a per-item action — both are shared components, but they are not the same widget.
- The OTA verb calls `performVerb(DeviceVerb.ota, force: prefs.forceOta)`. The mock ignores `force`; the **force toggle itself is the gate** on the Install button (`otaGuard`).
- Diagnostics "Copy diagnostics" fires the toast first and copies via an unawaited, error-swallowed `Clipboard.setData` (the test binding has no clipboard plugin); N15 should wire the real clipboard/share.
- Field report reuses `showCostSheet` (Send report / Cancel) and toasts on confirm; no network (N15).
- `shell_router_test.dart` updated: Settings→History now taps `settings-history`; the toast test taps `bridge-resync`.

**Follow-ups**
- N15: real device discovery signal, OTA (stream/slots/120 s health gate), restart/forget/factory endpoints, real field report + clipboard/share, persist `forceOta`/`otaChannel` on the real transport.
- N16: no goldens for the Settings tree, firmware, update, diagnostics or verb sheets; consider one Settings golden (fixed repo + prefs + `shellPulseEnabledProvider:false`).
- N11: the Settings behaviour toggles and the alarms sheet both write the same `AppSettings` fields — keep them a single source if the alarms sheet gains its own editor.

## T15 — N14 Onboarding: 8-step wizard, preflight, passkey coaching, troubleshoot

Status: **done**. `make app.test` green (**609**; N14 adds 26 — 18 pure + 8 widget + 0 repo/golden); `flutter analyze` and format check clean; `dart test test/domain test/data` green (**202**, was 184). No golden changed.

**Real paths (all under `app/lib/features/onboarding/`; barrel `onboarding.dart`)**
- `setup_format.dart` — pure: `OnboardStep` (8), `kOnboardSteps`, `OnboardPermission`/`PermissionState`/`kOnboardPermissions`, `SetupHop`/`HopStatus`, `SetupFault`, `SetupState`, `SetupToken`, `SetupHopRow`, `kPasskeyPlaceholder`.
- `onboarding_model.dart` — `SetupMachine` (`Notifier<SetupState>`) + `setupStateProvider`, `onboardingRequiredProvider`, `onboardingSkippedProvider`.
- `onboarding_sheet.dart` — `OnboardingBody`, `OnboardingFoot`, `OnboardingSurface` (gate), `finishOnboarding`, `skipOnboarding`.
- Wired: `shell/overlay.dart` `DevOverlay.onboarding` -> real body/foot; `shell/shell.dart` mounts `OnboardingSurface` above everything while required; `features/live/live_page.dart` `live-connect-bridge` empty state when skipped.
- Tests `app/test/data/onboarding_setup_test.dart` (18, `package:test`, in the `dart test` gate) and `app/test/features/onboarding_test.dart` (8 widget).

**Commands that work**
- `make app.test` — the N14 gate (analyze + format + `flutter test`, 609 pass).
- `cd app && flutter test test/features/onboarding_test.dart` — 8.
- `cd app && dart test test/data/onboarding_setup_test.dart` — 18.
- `cd app && dart test test/domain test/data` — data/domain gate (202).
- Re-run `dart run build_runner build` after any further `AppSettings` change (the freezed file was regenerated).

**Contract facts later tasks need**
- **`AppSettings` gained `bridgeName` (`String`, default `'Backyard Bridge'`) and `onboardStatus` (`OnboardStatus { fresh, skipped, paired }`, default `paired`).** Freezed regenerated.
- **Default `paired` is deliberate on the mock build** (every scenario carries a bridge; keeps the 583 pre-N14 tests green). Factory-fresh = `fresh`. N15 seeds `fresh` on a real first install and returns to it on factory reset.
- **The wizard is a pure machine in the `dart test` gate.** `canAdvance` = I6 next-step; `blockedReason` = I5 copy; `beginAsync()`/`resolve(token, fn)` = monotonic generation guard. Faults are named (`SetupFault` title/body/recoverLabel, I15).
- **`setupStateProvider` lives above the overlay** (resume on reopen); finish/skip call `reset()`. Finish persists units + `bridgeName` + `paired` and calls `BridgeRepository.connect()`; skip persists `skipped`.
- **`SheetOverlay` gained `footBuilder`**; the host prefers it over `foot`. `_OverlayPlaceholder`/`_propLine` and the `shell-overlay-copy`/`-props` keys were removed (onboarding was the last placeholder).
- **Passkey is structural-only**: no code field/parameter; `kPasskeyPlaceholder = '••••••'`. A test asserts no `Text` renders a 6-digit code. N15 owns the real platform passkey flow.
- Keys: `onboarding-surface`/`-body`/`-foot`/`-step-rail`/`-step-dot-<i>`/`-next`/`-back`/`-skip`/`-welcome`/`-welcome-copy`/`-preflight`/`-perm-<Name>`/`-perm-allow-<Name>`/`-scan`/`-scan-ring`/`-found-bridge`/`-found-sub`/`-troubleshoot-link`/`-troubleshoot`/`-ts-<i>`/`-passkey`/`-passkey-note`/`-sync`/`-listener-notice`/`-skip-base`/`-network`/`-mode-<id>`/`-name`/`-name-field`/`-units`/`-done`/`-done-copy`/`-hop-<Hop>`/`-hop-status-<Hop>`/`-fault`/`-fault-title`/`-fault-body`/`-fault-recover`; Live `live-connect-bridge`. Permission keys use the display name (`-perm-allow-Bluetooth`).

**Deviations / gotchas**
- Default `onboardStatus: paired` means the mock never auto-opens the wizard; tests set `fresh` explicitly.
- The named `?overlay=onboarding` dev path is dismissible; the gate is not (its X = Skip). Both share `OnboardingBody`/`OnboardingFoot`.
- The gate sheet head shows the current step title/sub; the named-overlay head is static (`Welcome to Smoke`).
- The network step selects locally (no `applyMode`); the prototype's troubleshoot `permRow(...,false)` Allow rows became plain checklist rows.
- Denial is a platform-only state in the real app; the widget renders the named denied state + resumable Allow (pinned by a seeded `setupStateProvider` test). `SetupMachine.fault(...)` is the test/dev seam.

**Follow-ups**
- N15: seed `fresh` on first install, reset to `fresh` on factory reset; real BLE scan/pair + platform permission requests + real passkey entry; `shared_preferences` persistence of `bridgeName`/`onboardStatus`.
- N16: no golden renders the wizard; consider one for the gate.

## T16 — N15 Bridge integration: real HTTP + BLE transports, sync engine, drift cache, background service, OTA

Status: **continue** (attempts 1–2). Attempt 1 landed the **transport +
connection + sync core** (N15.1, 15.2, 15.4–15.7, 15.10, 15.11, 15.12, 15.14).
Attempt 2 landed the **exit-gate-critical drop-in N15.8** and the **persistence
half of N15.13**. Tree green: `make app.test` **657** (was 640; +17),
`dart test test/domain test/data` **250** (was 233; +17). No screen or existing
test changed; `providers.dart` gained a flag-guarded real branch.

**Real paths (pure Dart)**
- Transport (attempt 1, under `app/lib/data/transport/`; barrel `transport.dart`):
  `bridge_transport.dart` (contract + DTOs + capabilities),
  `http_transport.dart` (`dart:io`, Bearer, error envelope, streamed NDJSON
  samples, WS `/api/v1/stream`, streamed `/ota`), `mock_transport.dart`
  (`MockBridgeDevice`, `failWith`, `statusPlan`, `calls`),
  `connection_manager.dart` (six lanes, `kConnectionBackoff`),
  `connection_supervisor.dart` (BLE-lead → Wi-Fi-upgrade → warm → failover),
  `bridge_session.dart` (status→sync→live→cache→subscribe, 10 s poll,
  `linkLost`), `sample_cache.dart` (`SampleCache`/`SyncState`/
  `InMemorySampleCache`; idempotent, never rewrites, I10), `sync_engine.dart`
  (high-water rollover gap before upsert, `samplesInWindow`,
  `exportCookCsvFromCache`).
- **Attempt 2 `app/lib/data/repository/real_bridge_repository.dart` — N15.8**:
  `RealBridgeRepository implements BridgeRepository` composing
  `ConnectionSupervisor` + `BridgeSession` + `SampleCache`. Maps
  `BridgeStatus`/`NetStatus`/`PowerStatus` → `ConnectionState` (+ `LinkState`,
  RSSI→bars), `LiveProbe` → `ProbeState` (4 jacks, absent null I3), `SessionInfo`
  + cache → `HistoryEntry` (peak from cached samples, marks from
  `transport.marks`, gaps from the cache), `DeviceStatus`/`StorageStatus` →
  `DeviceInfo`. Unadopted active session → `PendingSession`. Cook lifecycle
  maps onto `setCookClock` (`started_unix_ms`) and `postMark`; mutations swallow
  wire errors (I15); `linkLost` → `supervisor.failover()` then re-attach;
  `exportCookCsv` streams the cache. Screens still see only `BridgeRepository`.
- **Attempt 2 `app/lib/data/repository/real_prefs_repository.dart` — N15.13**:
  `KeyValueStore` + `InMemoryKeyValueStore` + `JsonPrefsRepository.load(store)`
  (load once for synchronous `current`, persist on write). Full `AppSettings`
  round-trip incl. `CustomFood` + its `CookTimeline`; corrupt blob → defaults
  (I15); no Wi-Fi secret stored.
- `providers.dart` — real repository opt-in via
  `--dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=…`; default remains
  `MockBridgeRepository` (dev panel + all widget tests unaffected).
  `prefsProvider` still mock until the `shared_preferences` adapter.

**Commands that work**
- `make app.test` — full gate (analyze + format + `flutter test`, **657**).
- `cd app && flutter test test/data/real_bridge_repository_test.dart` — 10.
- `cd app && flutter test test/data/real_prefs_repository_test.dart` — 7.
- `cd app && dart test test/domain test/data` — data/domain gate (**250**).
- Helper: `app/test/support/fake_bridge_server.dart` (do not add `tools/sim`).

**Contract facts later tasks need**
- `BridgeTransport` covers status/live/sessions/session/samples/marks/config/
  network/time/cook-clock/pairing/verbs/OTA/events.
- `ConnectionSupervisor.active` is the only transport carrying data; a warm BLE
  is open but idle; `verifyActive()` is a real `status()` read.
- `BridgeSession` caches backfill + pushed samples; `linkLost` fires on a failed
  poll. `SampleCache`/`SyncEngine` are the drift seam.
- `RealBridgeRepository` exposes `transport` and `cache` for dev/inspection;
  `snapshot()` replays `current` before the controller (same as the mock).

**Deviations / gotchas**
- HTTP is `dart:io`, not Dio; lanes are sequential by priority (same observable
  contract).
- Alarms/device read-back have **no wire endpoint yet**: the real repo keeps
  alarms/rules app-side and `checkForUpdates` uses the firmware fixture. Real
  device alarms land with the platform work.
- `_addItem` marks the jack attached app-side; the live feed still owns readings.
- App-only `MarkKind.spritz`/`turn` are written as wire `note`.
- Keep `InMemorySampleCache.clearConnectivityGapsBetween` and the drift version
  identical.
- `RealBridgeRepository.dispose()` disposes the supervisor but not the
  `ConnectionManager`.

**Follow-ups**
- N15.3 `BleTransport` (flutter_blue_plus) behind `TransportFactory.openBle()`;
  wire into `httpSupervisor` so `auto` can lead on BLE.
- N15.9 real drift schema implementing `SampleCache` + codegen; swap the in-memory
  cache in the provider.
- N15.13 plugin adapter: `KeyValueStore` over `shared_preferences`, loaded once
  in `bootstrap.dart`, then wire `prefsProvider` to `JsonPrefsRepository`.
- Real `alarms` parsing + `bridge_unreachable` insight + `alarmConfig` mapping.
- N15.15–N15.22 platform services (notifications, foreground service,
  `CookMonitor`, permissions, `network_binder`, `firmware_picker`+`share_plus`,
  diagnostics read-back) — plugins.
- N16: no goldens for any bridge surface.
