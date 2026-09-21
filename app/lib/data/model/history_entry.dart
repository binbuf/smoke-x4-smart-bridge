/// N2.21 — past-cook fixtures.
library;

/// A history fixture, stored relative to "now" so scenarios stay fresh.
class HistorySeed {
  const HistorySeed({
    required this.id,
    required this.name,
    required this.presetId,
    required this.styleId,
    required this.glyph,
    required this.jack,
    required this.startedAgoMin,
    required this.durationMin,
    required this.plannedMin,
    required this.peakF10,
    required this.targetF10,
    this.favourite = false,
    this.notes = '',
    this.marks = 0,
    this.rating = 0,
    this.status = 'done',
    this.photos = 0,
    this.stalledMin = 0,
    this.wrapAtF10,
  });

  final String id;
  final String name;
  final String presetId;
  final String styleId;
  final String glyph;
  final int jack;

  /// Minutes before the repository's "now" that the cook started.
  final int startedAgoMin;

  final int durationMin;
  final int plannedMin;

  /// Highest recorded temperature, tenths °F.
  final int peakF10;

  /// Final target, tenths °F.
  final int targetF10;

  final bool favourite;
  final String notes;
  final int marks;
  final int rating;
  final String status;
  final int photos;

  /// Minutes spent in the stall (0 = none).
  final int stalledMin;

  /// The temperature the cook was wrapped at, tenths °F, or null.
  final int? wrapAtF10;
}

/// A resolved history entry (a [HistorySeed] with a real wall clock).
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.name,
    required this.presetId,
    required this.styleId,
    required this.glyph,
    required this.jack,
    required this.startedAtMs,
    required this.durationMin,
    required this.plannedMin,
    required this.peakF10,
    required this.targetF10,
    this.favourite = false,
    this.notes = '',
    this.marks = 0,
    this.rating = 0,
    this.status = 'done',
    this.photos = 0,
    this.stalledMin = 0,
    this.wrapAtF10,
  });

  final String id;
  final String name;
  final String presetId;
  final String styleId;
  final String glyph;
  final int jack;
  final int startedAtMs;
  final int durationMin;
  final int plannedMin;
  final int peakF10;
  final int targetF10;
  final bool favourite;
  final String notes;
  final int marks;
  final int rating;
  final String status;
  final int photos;
  final int stalledMin;
  final int? wrapAtF10;

  /// Planned-vs-actual delta in minutes (positive = ran over).
  int get overrunMin => durationMin - plannedMin;

  HistoryEntry copyWith({bool? favourite}) => HistoryEntry(
    id: id,
    name: name,
    presetId: presetId,
    styleId: styleId,
    glyph: glyph,
    jack: jack,
    startedAtMs: startedAtMs,
    durationMin: durationMin,
    plannedMin: plannedMin,
    peakF10: peakF10,
    targetF10: targetF10,
    favourite: favourite ?? this.favourite,
    notes: notes,
    marks: marks,
    rating: rating,
    status: status,
    photos: photos,
    stalledMin: stalledMin,
    wrapAtF10: wrapAtF10,
  );

  static HistoryEntry fromSeed(HistorySeed seed, int nowMs) => HistoryEntry(
    id: seed.id,
    name: seed.name,
    presetId: seed.presetId,
    styleId: seed.styleId,
    glyph: seed.glyph,
    jack: seed.jack,
    startedAtMs: nowMs - seed.startedAgoMin * 60 * 1000,
    durationMin: seed.durationMin,
    plannedMin: seed.plannedMin,
    peakF10: seed.peakF10,
    targetF10: seed.targetF10,
    favourite: seed.favourite,
    notes: seed.notes,
    marks: seed.marks,
    rating: seed.rating,
    status: seed.status,
    photos: seed.photos,
    stalledMin: seed.stalledMin,
    wrapAtF10: seed.wrapAtF10,
  );
}
