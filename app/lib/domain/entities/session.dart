/// A recording session as the bridge reports it.
///
/// The bridge records continuously and opens a session file by itself the
/// moment samples arrive, whether or not anyone is cooking. A "cook" in this
/// app is a user-drawn window **over** one of these sessions (see `Cook`), so a
/// session is raw evidence, not a cook.
///
/// [startedUnixMs] and [endedUnixMs] are null when the bridge had no wall clock
/// — never a fabricated epoch.
library;

/// One `history_session` (protocol/records.yaml), as the app uses it.
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.name,
    required this.startedUnixMs,
    required this.endedUnixMs,
    required this.samplePeriodS,
    required this.sampleCount,
    required this.numProbes,
    required this.closed,
    required this.pinned,
  });

  /// Device-monotonic session id. Never minted by the phone.
  final int id;
  final String name;

  /// Null when the bridge had no clock.
  final int? startedUnixMs;
  final int? endedUnixMs;

  final int samplePeriodS;
  final int sampleCount;
  final int numProbes;
  final bool closed;
  final bool pinned;

  /// The last second a closed session holds, or null while open/clocksless.
  int? get deviceMaxT {
    final start = startedUnixMs;
    final end = endedUnixMs;
    if (!closed || start == null || end == null || end < start) {
      return null;
    }
    return (end - start) ~/ 1000;
  }

  @override
  String toString() => 'SessionInfo(id: $id, name: $name, closed: $closed)';
}
