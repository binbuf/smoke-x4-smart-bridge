/// A2.4 — enter, exit, and hovering at each threshold without oscillating.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

/// Runs the detector over (t, f) pairs, returning stall state per t.
Map<int, bool> run(StallDetector d, List<({int t, double? f})> pts) => {
  for (final p in pts) p.t: d.add(p.t, p.f),
};

/// Piecewise series builder at 30 s cadence.
List<({int t, double? f})> ramp({
  required int fromT,
  required int toT,
  required double startF,
  required double fPerHr,
}) => [
  for (var t = fromT; t <= toT; t += 30)
    (t: t, f: startF + fPerHr * (t - fromT) / 3600),
];

void main() {
  test('enters after 30 sustained minutes flat inside the band', () {
    final d = StallDetector();
    // Climb through 140 °F fast, then sit dead flat at 155 °F.
    final pts = [
      ...ramp(fromT: 0, toT: 3600, startF: 100, fPerHr: 55), // ends 155
      ...ramp(fromT: 3630, toT: 10800, startF: 155, fPerHr: 0),
    ];
    final states = run(d, pts);
    // Not stalled 20 minutes into the plateau (slope must first decay,
    // then hold for 30 min)…
    expect(states[4800], isFalse);
    // …but stalled well before the plateau is 2 hours old.
    expect(states[10800], isTrue);
  });

  test('does not enter below the 140 °F band edge', () {
    final d = StallDetector();
    final pts = ramp(fromT: 0, toT: 10800, startF: 135, fPerHr: 0);
    final states = run(d, pts);
    expect(states.values.any((s) => s), isFalse);
  });

  test('does not enter above the 180 °F band edge', () {
    final d = StallDetector();
    final pts = ramp(fromT: 0, toT: 10800, startF: 185, fPerHr: 0);
    expect(run(d, pts).values.any((s) => s), isFalse);
  });

  test('a steady 2.5 °F/hr climb through the band never enters', () {
    final d = StallDetector();
    final pts = ramp(fromT: 0, toT: 4 * 3600, startF: 140, fPerHr: 2.5);
    expect(run(d, pts).values.any((s) => s), isFalse);
  });

  test('~25 minutes under threshold then a breakout does not enter', () {
    final d = StallDetector();
    // Flat from t=0: the slope needs ~5 min of samples before it reads
    // <2 °F/hr, so the sustained-flat clock runs ≈25 min by t=1800 —
    // short of the 30-minute requirement — and the breakout resets it.
    final pts = [
      ...ramp(fromT: 0, toT: 1800, startF: 155, fPerHr: 0),
      ...ramp(fromT: 1830, toT: 7200, startF: 155, fPerHr: 25),
    ];
    expect(run(d, pts).values.any((s) => s), isFalse);
  });

  test('exits only after 15 sustained minutes above 4 °F/hr', () {
    final d = StallDetector();
    final plateau = [...ramp(fromT: 0, toT: 7200, startF: 157, fPerHr: 0)];
    final states1 = run(d, plateau);
    expect(states1[7200], isTrue);

    // Breakout at 8 °F/hr: the 10-min slope needs time to cross 4, then
    // 15 min of sustain — still stalled shortly after the breakout starts.
    final breakout = ramp(fromT: 7230, toT: 12600, startF: 157, fPerHr: 8);
    final states2 = run(d, breakout);
    expect(states2[7800], isTrue, reason: 'slope has not sustained yet');
    expect(states2[12600], isFalse, reason: 'breakout held > 15 min');
  });

  test('hovering between the thresholds does not oscillate', () {
    final d = StallDetector();
    final plateau = ramp(fromT: 0, toT: 7200, startF: 157, fPerHr: 0);
    run(d, plateau);
    expect(d.stalled, isTrue);

    // 3 °F/hr sits between enter (<2) and exit (>4): the latched state
    // must hold with zero flapping.
    final hover = ramp(fromT: 7230, toT: 14400, startF: 157, fPerHr: 3);
    final states = run(d, hover);
    expect(states.values.every((s) => s), isTrue);
  });

  test('a non-food role never stalls', () {
    final d = StallDetector(role: ProbeRole.pit);
    final pts = ramp(fromT: 0, toT: 10800, startF: 155, fPerHr: 0);
    expect(run(d, pts).values.any((s) => s), isFalse);
  });

  test('detached (null) samples do not satisfy the band condition', () {
    final d = StallDetector();
    final pts = [for (var t = 0; t <= 10800; t += 30) (t: t, f: null)];
    expect(run(d, pts).values.any((s) => s), isFalse);
  });
}
