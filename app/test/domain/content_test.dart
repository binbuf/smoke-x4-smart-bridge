/// N1.8/N1.9 — cook-style packs and the expected-cook timeline model.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('N1.8 a CookStyle round-trips through JSON with its region badge', () {
    const style = CookStyle(
      id: 'central_texas',
      name: 'Central Texas',
      region: 'Texas',
      tagline: 'Salt & pepper, butcher paper',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      targetF10: 2010,
      wrap: WrapStep(
        tempF10: 1650,
        label: 'Wrap in butcher paper',
        note: 'Protects the bark.',
      ),
      spritzEveryMin: 45,
      restMin: 60,
      note: 'The benchmark.',
    );

    final restored = CookStyle.fromJson(style.toJson());
    expect(restored.id, 'central_texas');
    expect(restored.region, 'Texas');
    expect(restored.targetF10, 2010);
    expect(restored.wrap!.tempF10, 1650);
    expect(restored.spritzEveryMin, 45);
    expect(restored.restMin, 60);
    // Region is identity metadata, never a status channel.
    expect(restored.region, isNot(style.name));
  });

  test('N1.9 a CookTimeline round-trips and carries the optional steps', () {
    const timeline = CookTimeline(
      totalMin: MinuteRange(600, 840),
      stall: StallWindow(
        minF10: 1500,
        maxF10: 1700,
        durationMin: MinuteRange(120, 240),
      ),
      wrap: WrapStep(tempF10: 1650, label: 'Wrap'),
      spritzEveryMin: 45,
      turn: TurnStep(elapsedMin: 5, note: 'Flip once.'),
      restMin: 60,
      phases: [
        CookPhaseSpec(id: 'on', label: 'On the smoker'),
        CookPhaseSpec(id: 'stall', label: 'The stall', note: 'Normal.'),
      ],
    );

    final restored = CookTimeline.fromJson(timeline.toJson());
    expect(restored.totalMin, const MinuteRange(600, 840));
    expect(restored.totalMin.mid, 720);
    expect(restored.stall!.minF10, 1500);
    expect(restored.wrap!.label, 'Wrap');
    expect(restored.spritzEveryMin, 45);
    expect(restored.turn!.elapsedMin, 5);
    expect(restored.restMin, 60);
    expect(restored.phases.map((p) => p.id), ['on', 'stall']);
  });

  test('a cut with no wrap simply has no wrap step', () {
    const timeline = CookTimeline(totalMin: MinuteRange(20, 30));
    expect(timeline.hasWrap, isFalse);
    expect(timeline.hasStall, isFalse);
    expect(CookTimeline.fromJson(timeline.toJson()).wrap, isNull);
  });
}
