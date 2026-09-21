/// N1 — the domain barrel.
///
/// Pure Dart: this library and everything under `lib/domain/` imports nothing
/// from Flutter or `dart:ui`, so the whole of it is host-testable without a
/// binding (components_research_notes.md §6, §10) and `dart test` can run it.
library;

export 'analysis/chart_series.dart';
export 'analysis/cook_stats.dart';
export 'analysis/eta.dart';
export 'analysis/lttb.dart';
export 'analysis/rate_of_change.dart';
export 'analysis/series.dart';
export 'analysis/stall.dart';
export 'entities/freshness.dart';
export 'entities/gap.dart';
export 'entities/mark.dart';
export 'entities/probe.dart';
export 'entities/probe_reading.dart';
export 'entities/sample.dart';
export 'plan/cook_annotation.dart';
export 'plan/cook_phase.dart';
export 'plan/cook_plan.dart';
export 'plan/cook_style.dart';
export 'plan/cook_timeline.dart';
export 'plan/hazard.dart';
export 'plan/presets.dart';
export 'situation/situation.dart';
export 'units/temp_value.dart';
