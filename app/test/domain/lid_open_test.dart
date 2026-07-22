/// A2.5 — detect-then-confirm AND detect-then-escalate. Suppressing a real
/// pit_crash is the expensive failure, so both branches are covered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';

void main() {
  test('a ≥25 °F drop within 3 minutes fires detection immediately', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    for (var t = 0; t <= 1000; t += 30) {
      events.addAll(d.add(t, 250));
    }
    events.addAll(d.add(1030, 230));
    expect(events, isEmpty, reason: '20 °F is not enough');
    events.addAll(d.add(1060, 212));
    expect(events.whereType<LidOpenDetected>().length, 1);
    final det = events.whereType<LidOpenDetected>().single;
    expect(det.t, 1060);
    expect(det.dropF, closeTo(38, 0.001));
    expect(d.pending, isTrue);
  });

  test('recovery ≥ 50 % within 20 min confirms a lid open', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    for (var t = 0; t <= 1000; t += 30) {
      events.addAll(d.add(t, 250));
    }
    events.addAll(d.add(1030, 224)); // −26: detected
    expect(events.whereType<LidOpenDetected>().length, 1);

    // Sag a little further, then recover.
    events.addAll(d.add(1060, 220));
    events.addAll(d.add(1090, 224));
    expect(events.whereType<LidOpenConfirmed>(), isEmpty);
    // drop = 250−220 = 30; needs +15 from the low → 235.
    events.addAll(d.add(1120, 236));
    expect(events.whereType<LidOpenConfirmed>().length, 1);
    expect(events.whereType<PitCrashEscalated>(), isEmpty);
    expect(d.pending, isFalse);
  });

  test('no recovery within 20 min escalates to pit_crash', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    for (var t = 0; t <= 1000; t += 30) {
      events.addAll(d.add(t, 250));
    }
    events.addAll(d.add(1030, 218)); // −32: detected
    expect(events.whereType<LidOpenDetected>().length, 1);

    // The fire is dying: it keeps sagging, never recovering half the drop.
    for (var t = 1060; t <= 1030 + 1300; t += 30) {
      events.addAll(d.add(t, 214 - (t - 1060) / 300));
    }
    expect(events.whereType<PitCrashEscalated>().length, 1);
    expect(events.whereType<LidOpenConfirmed>(), isEmpty);
    final esc = events.whereType<PitCrashEscalated>().single;
    expect(esc.t - 1030, greaterThanOrEqualTo(1200));
    expect(d.pending, isFalse);
  });

  test('a slow drift never looks like a lid open', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    // 60 °F down over an hour — 3 °F per any 3-minute window.
    for (var t = 0; t <= 3600; t += 30) {
      events.addAll(d.add(t, 250 - t / 60));
    }
    expect(events, isEmpty);
  });

  test('a 24.9 °F drop stays under the threshold', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    for (var t = 0; t <= 300; t += 30) {
      events.addAll(d.add(t, 250));
    }
    events.addAll(d.add(330, 225.1));
    expect(events, isEmpty);
  });

  test('detached pit samples are skipped, not crashed on', () {
    final d = LidOpenDetector();
    final events = <LidEvent>[];
    for (var t = 0; t <= 600; t += 30) {
      events.addAll(d.add(t, t % 60 == 0 ? 250 : null));
    }
    events.addAll(d.add(630, 220));
    expect(events.whereType<LidOpenDetected>().length, 1);
  });
}
