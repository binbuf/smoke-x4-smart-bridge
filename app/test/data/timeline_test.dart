/// N2.11 — timeline normalisation.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

CatalogEntry _entry({
  String id = 'synthetic',
  HazardClass hazard = HazardClass.unstated,
  CutThickness thickness = CutThickness.medium,
  int pitMin = 2250,
  int pitMax = 2750,
  TimelineSeed? tl,
}) => CatalogEntry(
  id: id,
  category: 'Misc',
  name: 'Synthetic',
  glyph: 'side',
  hazard: hazard,
  thickness: thickness,
  pitBandMinF10: pitMin,
  pitBandMaxF10: pitMax,
  blurb: '',
  doneness: const [Doneness(id: 'done', label: 'Done', targetF10: 1600)],
  defaultDonenessId: 'done',
  tl: tl,
);

void main() {
  final table = kCatalogTable;

  test('a cut with no seed is synthesised from thickness and pit band', () {
    final lowMedium = normalizeTimeline(_entry());
    expect(lowMedium.totalMin, const MinuteRange(120, 210));
    expect(lowMedium.spritzEveryMin, 45);
    expect(lowMedium.restMin, 5);
    expect(lowMedium.stall, isNull);

    final lowThick = normalizeTimeline(_entry(thickness: CutThickness.thick));
    expect(lowThick.totalMin, const MinuteRange(240, 360));
    expect(lowThick.stall, isNotNull);
    expect(lowThick.spritzEveryMin, isNull);

    final hotThin = normalizeTimeline(
      _entry(thickness: CutThickness.thin, pitMax: 4000),
    );
    expect(hotThin.totalMin, const MinuteRange(20, 45));
    expect(hotThin.spritzEveryMin, isNull);
  });

  test('a seeded total and stall win over synthesis', () {
    final timeline = normalizeTimeline(
      _entry(
        thickness: CutThickness.thick,
        tl: const TimelineSeed(
          totalMin: MinuteRange(600, 840),
          stall: StallSeed(
            minF10: 1500,
            maxF10: 1700,
            durMinLo: 120,
            durMinHi: 240,
          ),
          wrap: WrapStep(tempF10: 1650, label: 'Wrap', note: 'Paper.'),
          spritzEveryMin: 45,
          spritzSpecified: true,
          restMin: 60,
          onNote: 'Fat side up.',
          pullNote: 'Butter smooth.',
        ),
      ),
    );
    expect(timeline.totalMin, const MinuteRange(600, 840));
    expect(timeline.stall!.minF10, 1500);
    expect(timeline.stall!.durationMin, const MinuteRange(120, 240));
    expect(timeline.wrap!.label, 'Wrap');
    expect(timeline.spritzEveryMin, 45);
    expect(timeline.restMin, 60);
    expect(timeline.phases.map((p) => p.id), [
      'on',
      'stall',
      'wrap',
      'pull',
      'rest',
    ]);
    expect(timeline.phases.first.note, 'Fat side up.');
    expect(
      timeline.phases.firstWhere((p) => p.id == 'pull').note,
      'Butter smooth.',
    );
  });

  test('a short cook gains the flip phase', () {
    final timeline = normalizeTimeline(
      _entry(
        thickness: CutThickness.thin,
        tl: const TimelineSeed(totalMin: MinuteRange(8, 14), restMin: 3),
      ),
    );
    expect(timeline.phases.map((p) => p.id), ['on', 'flip', 'pull', 'rest']);
  });

  test('an explicit null spritz is not defaulted when a stall exists', () {
    final timeline = normalizeTimeline(
      _entry(
        thickness: CutThickness.thick,
        tl: const TimelineSeed(
          totalMin: MinuteRange(480, 720),
          stall: StallSeed(
            minF10: 1500,
            maxF10: 1700,
            durMinLo: 90,
            durMinHi: 180,
          ),
          spritzSpecified: true,
          restMin: 60,
        ),
      ),
    );
    expect(timeline.spritzEveryMin, isNull);
  });

  test('the real catalog round-trips the prototype brisket numbers', () {
    final timeline = table.timelineFor('beef_brisket')!;
    expect(timeline.totalMin, const MinuteRange(600, 840));
    expect(timeline.stall!.minF10, 1500);
    expect(timeline.wrap!.tempF10, 1650);
    expect(timeline.spritzEveryMin, 45);
    expect(timeline.restMin, 60);
  });

  test('every timeline is honest: a positive range and non-empty phases', () {
    for (final timeline in table.timelines.values) {
      expect(timeline.totalMin.max, greaterThan(timeline.totalMin.min));
      expect(timeline.phases, isNotEmpty);
    }
  });
}
