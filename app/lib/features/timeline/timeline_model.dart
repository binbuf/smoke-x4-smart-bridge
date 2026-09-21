/// N8 — the Timeline screen's Riverpod seam.
///
/// The clock is overridable so the schedule is deterministic in tests and
/// goldens; it is read once per build, no ticker (the N4/N5 precedent). The
/// model is a pure projection of the snapshot, the settings gate and the
/// catalog timeline table.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'timeline_format.dart';

/// The Timeline screen's clock. Overridable; read once per build.
final timelineNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The whole Timeline projection for the current snapshot, or null before the
/// first snapshot arrives.
final timelineModelProvider = Provider<TimelineModel?>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  if (snapshot == null) {
    return null;
  }
  final settings = ref.watch(settingsProvider).value;
  final catalog = ref.watch(bridgeRepositoryProvider).catalog;
  final now = ref.watch(timelineNowProvider);
  return buildTimelineModel(
    cook: snapshot.cook,
    pendingSession: snapshot.pendingSession,
    catalog: catalog,
    marks: snapshot.marks,
    nowMs: now.millisecondsSinceEpoch,
    autoWrapReminder: settings?.autoWrapReminder ?? true,
  );
});
