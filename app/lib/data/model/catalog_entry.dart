/// N2.1 — the catalog entry model and its timeline seed.
///
/// One cut in the reviewer-owned library: identity, food-safety class, the
/// doneness ladder and the raw `tl` seed the timeline database is normalised
/// from. [doneness] reuses the N1 [Doneness] value object, so a target coming
/// from the catalog is the same type (and the same safety gate) as one built by
/// hand.
///
/// The seed is deliberately **raw**, not a normalised [CookTimeline]: synthesis
/// for cuts that omit a seed belongs to `normalizeTimeline` (N2.11), and
/// round-tripping the seed keeps that behaviour testable.
library;

import '../../domain/domain.dart';

/// A stall seed: expected plateau band and duration, still in seed form.
class StallSeed {
  const StallSeed({
    required this.minF10,
    required this.maxF10,
    required this.durMinLo,
    required this.durMinHi,
  });

  final int minF10;
  final int maxF10;
  final int durMinLo;
  final int durMinHi;
}

/// The per-cut `tl` seed exactly as the prototype's catalog carries it.
///
/// [spritzSpecified] distinguishes "the author wrote `spritz: null`" (no
/// spritz, ever) from "the author said nothing" (let `normalizeTimeline`
/// decide), which is the same distinction `mock-data.js` makes with
/// `seed.spritz !== undefined`.
class TimelineSeed {
  const TimelineSeed({
    this.totalMin,
    this.stall,
    this.wrap,
    this.spritzEveryMin,
    this.spritzSpecified = false,
    this.turn,
    this.restMin,
    this.onNote = '',
    this.pullNote = '',
  });

  final MinuteRange? totalMin;
  final StallSeed? stall;
  final WrapStep? wrap;
  final int? spritzEveryMin;
  final bool spritzSpecified;
  final TurnStep? turn;

  /// Rest minutes; null takes the prototype's default of 5.
  final int? restMin;

  final String onNote;
  final String pullNote;
}

/// One catalog cut.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.category,
    required this.name,
    required this.glyph,
    required this.hazard,
    required this.thickness,
    required this.pitBandMinF10,
    required this.pitBandMaxF10,
    required this.blurb,
    required this.doneness,
    required this.defaultDonenessId,
    this.tl,
  });

  final String id;
  final String category;
  final String name;

  /// Placeholder-avatar glyph name (`brisket`, `steak`, `fish` …).
  final String glyph;

  final HazardClass hazard;
  final CutThickness thickness;

  /// Recommended pit band, tenths °F.
  final int pitBandMinF10;
  final int pitBandMaxF10;

  final String blurb;

  /// The doneness ladder. Targets are post-rest finals.
  final List<Doneness> doneness;

  /// The doneness the picker opens on.
  final String defaultDonenessId;

  /// The raw timeline seed, or null when the cut has none (synthesised later).
  final TimelineSeed? tl;

  /// Carryover for this cut, tenths °F.
  int get carryoverF10 => carryoverFor(hazard: hazard, thickness: thickness);

  /// The default doneness, falling back to the first rung when the id is
  /// unknown.
  Doneness get defaultDoneness {
    for (final d in doneness) {
      if (d.id == defaultDonenessId) {
        return d;
      }
    }
    return doneness.first;
  }

  Doneness? donenessById(String id) {
    for (final d in doneness) {
      if (d.id == id) {
        return d;
      }
    }
    return null;
  }

  /// This cut as an N1-style [CookPreset] — the shape the setup flow consumes.
  CookPreset toPreset() => CookPreset(
    id: id,
    category: category,
    name: name,
    hazard: hazard,
    doneness: doneness,
    pitBandMinF10: pitBandMinF10,
    pitBandMaxF10: pitBandMaxF10,
    thickness: thickness,
    blurb: blurb,
  );
}
