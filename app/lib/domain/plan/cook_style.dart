/// N1.8 — a cook-style pack.
///
/// Selecting a cut is not enough: "Pork Shoulder" could be Texas pulled pork,
/// Kālua pork, Carolina, Cuban mojo or cochinita pibil. A style is a **named
/// regional preparation** that sets pit band, wrap, spritz, target, rest and
/// the expected timeline together. [region] is identity metadata — an identity
/// badge, never a status channel.
library;

import 'cook_timeline.dart';

/// A named style for one preset/cut, keyed by the preset id in the data tables.
class CookStyle {
  const CookStyle({
    required this.id,
    required this.name,
    required this.region,
    this.tagline = '',
    required this.pitBandMinF10,
    required this.pitBandMaxF10,
    this.targetF10,
    this.wrap,
    this.spritzEveryMin,
    this.restMin = 0,
    this.timeline,
    this.note = '',
  });

  /// Stable id within the cut, e.g. `central_texas`.
  final String id;
  final String name;

  /// "Texas", "Hawaii", "Yucatán" … — identity only.
  final String region;

  /// One line under the name in the picker.
  final String tagline;

  /// Pit target band, tenths °F.
  final int pitBandMinF10;
  final int pitBandMaxF10;

  /// This style's target, tenths °F. Null takes the cut's default doneness.
  final int? targetF10;
  final WrapStep? wrap;

  /// Minutes between spritzes, or null when the style does not spritz.
  final int? spritzEveryMin;
  final int restMin;

  /// The style's own expected timeline, when it differs from the cut's.
  final CookTimeline? timeline;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'region': region,
    if (tagline.isNotEmpty) 'tagline': tagline,
    'pit_band_min_f10': pitBandMinF10,
    'pit_band_max_f10': pitBandMaxF10,
    if (targetF10 != null) 'target_f10': targetF10,
    if (wrap != null) 'wrap': wrap!.toJson(),
    if (spritzEveryMin != null) 'spritz_every_min': spritzEveryMin,
    'rest_min': restMin,
    if (timeline != null) 'timeline': timeline!.toJson(),
    if (note.isNotEmpty) 'note': note,
  };

  static CookStyle fromJson(Map<String, Object?> j) => CookStyle(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    region: j['region'] as String? ?? '',
    tagline: j['tagline'] as String? ?? '',
    pitBandMinF10: (j['pit_band_min_f10'] as num?)?.toInt() ?? 0,
    pitBandMaxF10: (j['pit_band_max_f10'] as num?)?.toInt() ?? 0,
    targetF10: (j['target_f10'] as num?)?.toInt(),
    wrap: j['wrap'] == null
        ? null
        : WrapStep.fromJson((j['wrap'] as Map).cast<String, Object?>()),
    spritzEveryMin: (j['spritz_every_min'] as num?)?.toInt(),
    restMin: (j['rest_min'] as num?)?.toInt() ?? 0,
    timeline: j['timeline'] == null
        ? null
        : CookTimeline.fromJson((j['timeline'] as Map).cast<String, Object?>()),
    note: j['note'] as String? ?? '',
  );
}
