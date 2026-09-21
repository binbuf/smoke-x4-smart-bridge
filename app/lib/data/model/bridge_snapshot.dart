/// N2.14 / N2.16–N2.21 — a complete UI situation.
///
/// [BridgeSnapshot] is what `BridgeRepository.snapshot()` streams: connection,
/// cook, four jacks, alarms, marks, an unadopted session and a notice. A
/// [Scenario] names one such situation (`running`, `offline`, …) plus the
/// metadata the dev panel shows.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/domain.dart';
import 'alarm.dart';
import 'connection_state.dart';
import 'cook_state.dart';

part 'bridge_snapshot.freezed.dart';

/// The live state every screen reads. Immutable; the repository emits a new one
/// on every change.
@freezed
abstract class BridgeSnapshot with _$BridgeSnapshot {
  const factory BridgeSnapshot({
    required ConnectionState connection,
    required CookState cook,
    @Default(<ProbeState>[]) List<ProbeState> probes,
    @Default(<Alarm>[]) List<Alarm> alarms,
    @Default(<Mark>[]) List<Mark> marks,
    PendingSession? pendingSession,

    /// A one-line banner ("Bridge restarted — recording resumed.").
    String? notice,
  }) = _BridgeSnapshot;
}

/// A named fixture: the snapshot plus the dev-panel metadata.
class Scenario {
  const Scenario({
    required this.key,
    required this.label,
    required this.snapshot,
  });

  /// `running`, `idle`, `bt_only`, `switch_rollback`, …
  final String key;
  final String label;
  final BridgeSnapshot snapshot;

  Scenario withSnapshot(BridgeSnapshot next) =>
      Scenario(key: key, label: label, snapshot: next);
}
