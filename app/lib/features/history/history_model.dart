/// N12 — the History screen's Riverpod seam.
///
/// The clock is overridable so the seven-day grouping is deterministic in tests
/// and goldens; it is read once per build, no ticker (the N4/N5 precedent). The
/// model is a pure projection of the repository's history stream and the unit
/// preference.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model/history_entry.dart';
import '../../data/providers.dart';
import '../../domain/domain.dart';
import 'history_format.dart';

/// The History screen's clock. Overridable; read once per build.
final historyNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The seven cooks, grouped This week / Earlier.
final historyGroupsProvider = Provider<List<HistoryGrouping>>((ref) {
  final entries = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
  final now = ref.watch(historyNowProvider);
  return groupHistory(entries, nowMs: now.millisecondsSinceEpoch);
});

/// The display unit, from Settings (canonical storage stays tenths-°F).
final historyUnitProvider = Provider<TempUnit>(
  (ref) => ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit,
);
