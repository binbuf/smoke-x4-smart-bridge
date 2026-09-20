/// The dashboard projection (A9, M4).
///
/// The reconciliation is a pure function into one immutable snapshot
/// ([DashboardSnapshot]); the widgets render the snapshot and nothing
/// else. See design 08 §8.6.
///
/// **What used to live here.** `dashboard_route.dart`, `dashboard_screen.dart`,
/// `header_strip.dart` and `session_controls.dart` were the pre-shell screen —
/// each standing up its own connection, its own chip and its own bar. The
/// `StatefulShellRoute` rewrite replaced all four and left them compiling,
/// partly imported for one helper, and reachable from nothing. newapp §I.0 lists
/// exactly that as the first thing to delete, so it is deleted: the mark sheet
/// that was the only living part of `session_controls.dart` now lives in
/// `features/cook/mark_sheet.dart`, wired to a control a user can actually
/// reach.
///
/// `probe_tile.dart` went the same way, and took `lib/app/palette.dart` with
/// it: that file was a byte-for-byte duplicate of `design/series_palette.dart`
/// kept alive by this one unreachable widget, and two palettes is precisely
/// the drift that makes an app stop feeling designed. Its unique assertions
/// were migrated to `test/design/series_channels_test.dart` first.
library;

export 'dashboard_snapshot.dart';
