/// A9.1 — the dashboard projection.
///
/// The reason this is a pure function: every case below is a table row
/// rather than a widget pump, and the one invariant that must never bend
/// (`detached` → `null`, never 0) is asserted over the whole snapshot.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

import '../support/shapes.dart';

void main() {
  test('no probes: four views, all detached, nothing renders a number', () {
    final snap = buildDashboard(
      status: statusFor(),
      live: const LiveState(t: 0, tempsF10: [null, null, null, null]),
      history: const [],
      link: LinkKind.http,
    );
    expect(snap.probes, hasLength(4));
    expect(snap.anyAttached, isFalse);
    for (final p in snap.probes) {
      expect(p.tempF10, isNull);
      expect(p.attached, isFalse);
    }
  });

  test('all detached: no temperature anywhere is 0', () {
    final snap = snapshotFor(allDetached(hours: 2));
    expect(snap.anyAttached, isFalse);
    // The invariant, over the whole projection rather than one field.
    expect(snap.probes.where((p) => p.tempF10 == 0), isEmpty);
    expect(snap.probes.map((p) => p.tempF10), everyElement(isNull));
  });

  test('headline slots follow roles, and survive their absence', () {
    final snap = snapshotFor(syntheticCook(hours: 6));
    expect(snap.headlinePit?.probe, 1);
    expect(snap.headlineFood?.probe, 2);
    expect(snap.secondary.map((p) => p.probe), [3, 4]);

    // A cook with no pit-role probe at all is legal and must render.
    final noPit = buildDashboard(
      status: statusFor(),
      live: LiveState(
        t: 3600,
        tempsF10: const [1600, null, null, null],
        probes: const [Probe(n: 1, name: 'Brisket', role: ProbeRole.food)],
      ),
      history: syntheticCook(hours: 2),
      link: LinkKind.http,
    );
    expect(noPit.headlinePit, isNull);
    expect(noPit.headlineFood?.probe, 1);
    expect(noPit.secondary.map((p) => p.probe), [2, 3, 4]);
  });

  test('a probe with no configuration falls back to jack 1 is the pit', () {
    // BLE's 16-byte live_state cannot carry names or roles; the OLED makes
    // the same assumption, so the two screens never disagree.
    final snap = buildDashboard(
      status: statusFor(),
      live: LiveState(t: 600, tempsF10: const [2430, 1600, null, null]),
      history: syntheticCook(hours: 1),
      link: LinkKind.ble,
      fullHistory: false,
    );
    expect(snap.headlinePit?.probe, 1);
    expect(snap.probes[0].name, 'Probe 1');
    expect(snap.fullHistory, isFalse);
  });

  test('a stalled food probe gets the reason, not a number', () {
    // Twelve hours of the synthetic brisket sits in the stall band.
    final snap = snapshotFor(syntheticCook(hours: 8));
    final food = snap.headlineFood!;
    expect(food.stalled, isTrue);
    expect(food.eta, isA<EtaUnavailable>());
    expect((food.eta! as EtaUnavailable).reason, EtaUnavailableReason.stalled);
  });

  test('a target above pit temperature answers, it does not guess', () {
    final snap = buildDashboard(
      status: statusFor(),
      live: LiveState(
        t: 7200,
        tempsF10: const [2000, 1600, null, null],
        probes: const [
          Probe(n: 1, role: ProbeRole.pit),
          // 300 °F target under a 200 °F pit: "not at this pit temperature"
          // is genuinely the right answer.
          Probe(n: 2, role: ProbeRole.food, targetF10: 3000),
        ],
      ),
      history: [
        for (var i = 0; i < 240; i++)
          Sample(t: i * 30, tempsF10: [2000, 1500 + i, null, null]),
      ],
      link: LinkKind.http,
    );
    expect(
      (snap.probes[1].eta! as EtaUnavailable).reason,
      EtaUnavailableReason.targetAtOrAbovePit,
    );
  });

  test('under 30 minutes of history refuses to project', () {
    final snap = buildDashboard(
      status: statusFor(),
      live: LiveState(
        t: 600,
        tempsF10: const [2500, 1200, null, null],
        probes: pitAndFood,
      ),
      history: syntheticCook(hours: 1).take(20).toList(),
      link: LinkKind.http,
    );
    expect(
      (snap.probes[1].eta! as EtaUnavailable).reason,
      EtaUnavailableReason.insufficientHistory,
    );
  });

  test('a series that just came back from a gap refuses to state a rate', () {
    // Two readings after a half-hour hole is not a slope. §9.4 returns
    // null rather than a number computed from bad data.
    final snap = snapshotFor(
      withGap(syntheticCook(hours: 4), fromT: 12600, toT: 14340),
    );
    expect(snap.probes.first.rateFPerHr, isNull);
    expect(snap.samples, isNotEmpty);
    // And the chart still has both runs to draw.
    expect(
      buildChartSeries(snap.samples, fromT: 0, toT: 14400).series.first.runs,
      hasLength(2),
    );
  });

  test('battery absence is absence, not zero', () {
    final unknown = snapshotFor(syntheticCook(hours: 1));
    expect(unknown.batteryKnown, isFalse);
    expect(unknown.socPct, isNull);

    final known = snapshotFor(syntheticCook(hours: 1), socPct: 71);
    expect(known.batteryKnown, isTrue);
    expect(known.socPct, 71);
  });

  test('the live push wins for now, the cache wins for history', () {
    final history = syntheticCook(hours: 1);
    final snap = buildDashboard(
      status: statusFor(),
      live: LiveState(
        t: history.last.t,
        tempsF10: const [9999, null, null, null],
        recent: [
          Sample(
            t: history.last.t + 30,
            tempsF10: const [8888, null, null, null],
          ),
        ],
        probes: pitAndFood,
      ),
      history: history,
      link: LinkKind.http,
    );
    expect(snap.probes.first.tempF10, 9999);
    // And the newer pushed sample is appended without duplicating the cache.
    expect(snap.samples.length, history.length + 1);
    expect(snap.samples.last.t, history.last.t + 30);
  });

  test('base-lost and alarms travel into the snapshot', () {
    final snap = snapshotFor(
      syntheticCook(hours: 1),
      baseLost: true,
      alarms: const [
        Alarm(
          id: 3,
          rule: 'target_reached',
          probe: 2,
          severity: AlarmSeverity.critical,
        ),
      ],
    );
    expect(snap.baseLost, isTrue);
    expect(snap.lastPacketSAgo, 740);
    expect(snap.anyUnacked, isTrue);
    expect(snap.probes[1].alarm?.rule, 'target_reached');
  });
}
