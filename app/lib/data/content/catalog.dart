/// N2.1–N2.13 — the assembled catalog table.
///
/// The generated tables (`catalog_data.dart`, `styles_data.dart`) plus the
/// derived timeline database (`timelines.dart`), behind one lookup surface.
/// This is the reviewer-owned content layer; nothing here talks to Flutter.
library;

import '../../domain/domain.dart';
import '../model/catalog_entry.dart';
import 'catalog_data.dart';
import 'styles_data.dart';
import 'timelines.dart';

/// The whole content library, ready for the picker and the Timeline tab.
class CatalogTable {
  CatalogTable({
    required this.entries,
    required this.categories,
    required this.styles,
    required this.timelines,
    this.catalogReviewer = kCatalogReviewer,
    this.stylesReviewer = kStylesReviewer,
    this.timelineReviewer = kTimelineReviewer,
  }) : _byId = {for (final e in entries) e.id: e};

  final List<CatalogEntry> entries;
  final List<String> categories;

  /// Named styles keyed by preset id.
  final Map<String, List<CookStyle>> styles;

  /// Expected-cook database keyed by preset id; one entry per catalog cut.
  final Map<String, CookTimeline> timelines;

  final String catalogReviewer;
  final String stylesReviewer;
  final String timelineReviewer;

  final Map<String, CatalogEntry> _byId;

  CatalogEntry? byId(String id) => _byId[id];

  /// The styles for [presetId] — empty when the cut has none.
  List<CookStyle> stylesFor(String presetId) => styles[presetId] ?? const [];

  /// The expected timeline for [presetId], or null for an unknown id.
  CookTimeline? timelineFor(String presetId) => timelines[presetId];

  /// The number of named variants over all cuts.
  int get styleCount => styles.values.fold(0, (n, list) => n + list.length);

  /// The cuts that carry at least one named style.
  int get styledCutCount => styles.length;

  /// Every catalog cut whose id has no timeline — must be empty.
  List<String> get missingTimelines => [
    for (final e in entries)
      if (!timelines.containsKey(e.id)) e.id,
  ];
}

/// The singleton content library.
final CatalogTable kCatalogTable = CatalogTable(
  entries: kCatalog,
  categories: kCategories,
  styles: kStylesByPreset,
  timelines: kTimelines,
);
