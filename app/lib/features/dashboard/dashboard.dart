/// Dashboard feature: live tiles, chart, and session controls (A9, M4).
///
/// The reconciliation is a pure function into one immutable snapshot
/// ([DashboardSnapshot]); the widgets render the snapshot and nothing
/// else. See design 08 §8.6.
library;

export 'dashboard_route.dart';
export 'dashboard_screen.dart';
export 'dashboard_snapshot.dart';
export 'header_strip.dart';
export 'probe_tile.dart';
export 'session_controls.dart';
