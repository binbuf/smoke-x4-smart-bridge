/// N1.9 — the per-cut expected-cook model.
///
/// This is the shape of the new Timeline database (the tables themselves belong
/// to the data/mocks task). Every value is optional and honest: a cut with no
/// wrap simply has `wrap == null`, and the Timeline view shows no wrap
/// reminder. The times are **estimates and must say so**.
library;

/// A closed minute range `[min, max]`, as `totalMin` and stall duration use.
class MinuteRange {
  const MinuteRange(this.min, this.max);

  final int min;
  final int max;

  /// The midpoint used for Gantt bar length.
  double get mid => (min + max) / 2;

  bool contains(int minutes) => minutes >= min && minutes <= max;

  Map<String, Object?> toJson() => {'min': min, 'max': max};

  static MinuteRange fromJson(Map<String, Object?> j) =>
      MinuteRange((j['min'] as num).toInt(), (j['max'] as num).toInt());

  @override
  bool operator ==(Object other) =>
      other is MinuteRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'MinuteRange($min–$max)';
}

/// The stall band: an expected temperature plateau and how long it lasts.
class StallWindow {
  const StallWindow({
    required this.minF10,
    required this.maxF10,
    required this.durationMin,
  });

  /// Tenths °F.
  final int minF10;
  final int maxF10;
  final MinuteRange durationMin;

  Map<String, Object?> toJson() => {
    'min_f10': minF10,
    'max_f10': maxF10,
    'duration_min': durationMin.toJson(),
  };

  static StallWindow fromJson(Map<String, Object?> j) => StallWindow(
    minF10: (j['min_f10'] as num).toInt(),
    maxF10: (j['max_f10'] as num).toInt(),
    durationMin: MinuteRange.fromJson(
      (j['duration_min'] as Map).cast<String, Object?>(),
    ),
  );
}

/// A wrap / cover step: the temperature it happens at, and the words.
class WrapStep {
  const WrapStep({this.tempF10, required this.label, this.note = ''});

  /// Tenths °F, or null when the step is time-based rather than temperature.
  final int? tempF10;
  final String label;
  final String note;

  Map<String, Object?> toJson() => {
    if (tempF10 != null) 'temp_f10': tempF10,
    'label': label,
    if (note.isNotEmpty) 'note': note,
  };

  static WrapStep fromJson(Map<String, Object?> j) => WrapStep(
    tempF10: (j['temp_f10'] as num?)?.toInt(),
    label: j['label'] as String? ?? '',
    note: j['note'] as String? ?? '',
  );
}

/// A turn / rotate intervention that happens once, at an elapsed minute.
class TurnStep {
  const TurnStep({required this.elapsedMin, this.note = ''});

  final int elapsedMin;
  final String note;

  Map<String, Object?> toJson() => {
    'elapsed_min': elapsedMin,
    if (note.isNotEmpty) 'note': note,
  };

  static TurnStep fromJson(Map<String, Object?> j) => TurnStep(
    elapsedMin: (j['elapsed_min'] as num).toInt(),
    note: j['note'] as String? ?? '',
  );
}

/// One named phase of the honest arc (`on`, `stall`, `wrap`, `pull`, `rest`…).
class CookPhaseSpec {
  const CookPhaseSpec({required this.id, required this.label, this.note = ''});

  final String id;
  final String label;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (note.isNotEmpty) 'note': note,
  };

  static CookPhaseSpec fromJson(Map<String, Object?> j) => CookPhaseSpec(
    id: j['id'] as String? ?? '',
    label: j['label'] as String? ?? '',
    note: j['note'] as String? ?? '',
  );
}

/// The canonical expected-cook record for one cut.
class CookTimeline {
  const CookTimeline({
    required this.totalMin,
    this.stall,
    this.wrap,
    this.spritzEveryMin,
    this.turn,
    this.restMin = 0,
    this.phases = const [],
  });

  /// Expected cook, pre-rest.
  final MinuteRange totalMin;
  final StallWindow? stall;
  final WrapStep? wrap;

  /// Minutes between spritzes, or null when the cut is not spritzed.
  final int? spritzEveryMin;
  final TurnStep? turn;

  /// Post-cook rest, minutes.
  final int restMin;
  final List<CookPhaseSpec> phases;

  bool get hasStall => stall != null;
  bool get hasWrap => wrap != null;

  Map<String, Object?> toJson() => {
    'total_min': totalMin.toJson(),
    if (stall != null) 'stall': stall!.toJson(),
    if (wrap != null) 'wrap': wrap!.toJson(),
    if (spritzEveryMin != null) 'spritz_every_min': spritzEveryMin,
    if (turn != null) 'turn': turn!.toJson(),
    'rest_min': restMin,
    'phases': [for (final p in phases) p.toJson()],
  };

  static CookTimeline fromJson(Map<String, Object?> j) => CookTimeline(
    totalMin: MinuteRange.fromJson(
      (j['total_min'] as Map).cast<String, Object?>(),
    ),
    stall: j['stall'] == null
        ? null
        : StallWindow.fromJson((j['stall'] as Map).cast<String, Object?>()),
    wrap: j['wrap'] == null
        ? null
        : WrapStep.fromJson((j['wrap'] as Map).cast<String, Object?>()),
    spritzEveryMin: (j['spritz_every_min'] as num?)?.toInt(),
    turn: j['turn'] == null
        ? null
        : TurnStep.fromJson((j['turn'] as Map).cast<String, Object?>()),
    restMin: (j['rest_min'] as num?)?.toInt() ?? 0,
    phases: [
      for (final p in (j['phases'] as List? ?? const []))
        if (p is Map) CookPhaseSpec.fromJson(p.cast<String, Object?>()),
    ],
  );
}
