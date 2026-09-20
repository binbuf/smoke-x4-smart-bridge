/// The freshness ladder (13 §13.6.1, newapp §H.1) — the app's honesty spine.
///
/// These exist because the ladder was, for a while, frozen at connect time. It
/// ran on `BridgeStatus.lastPacketSAgo`: a *device* counter, measuring the base
/// station's silence rather than ours, read once in `BridgeSession.start()` and
/// re-read only when an alarm, session or pairing frame happened to arrive. A
/// fourteen-hour cook with no alarms therefore read it once and reported `live`
/// for the duration — the stale veil never appeared, the pulse dot never
/// stopped, and a number from four hours ago sat under a green chip.
///
/// §16.2: *a stale number that looks live is worse than no number.* So what is
/// pinned here is not the rung boundaries — those are arithmetic — but the two
/// properties the old code lacked:
///
///  * the age is measured on **this phone's** clock, against the moment a
///    reading actually arrived, so it works on every lane and needs no RTC;
///  * it is computed **at read time**, so a screen nobody is pushing data to
///    still goes stale on its own. Staleness is the one state that becomes true
///    by the passage of time, and an absence of packets fires no callback.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';

const int _fixedNow = 1770000000000;

DashboardSnapshot _snap({
  int? readingAgeS,
  bool baseLost = false,
  LinkKind link = LinkKind.http,
  bool attached = true,
}) => DashboardSnapshot(
  probes: [
    ProbeView(
      probe: 1,
      role: ProbeRole.pit,
      name: 'Pit',
      tempF10: attached ? 2250 : null,
    ),
    const ProbeView(probe: 2, role: ProbeRole.food, name: 'Brisket'),
    const ProbeView(probe: 3, role: ProbeRole.unused, name: 'Probe 3'),
    const ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: link,
  baseLost: baseLost,
  readingAtUnixMs: readingAgeS == null ? null : _fixedNow - readingAgeS * 1000,
);

/// A session whose clock is ours to move.
ShellSession _session(DashboardSnapshot? snap, {int at = _fixedNow}) =>
    ShellSession.seeded(snapshot: snap, now: () => at);

void main() {
  group('the ladder measures the phone, not the device', () {
    test('a reading that just landed is live', () {
      final s = _session(_snap(readingAgeS: 3));
      addTearDown(s.dispose);
      expect(s.freshness, ProbeFreshness.live);
    });

    test('the four rungs land where 13 §13.6.1 says', () {
      for (final (ageS, expected) in const [
        (45, ProbeFreshness.live),
        (46, ProbeFreshness.aging),
        (90, ProbeFreshness.aging),
        (91, ProbeFreshness.stale),
        (600, ProbeFreshness.stale),
        (601, ProbeFreshness.frozen),
      ]) {
        final s = _session(_snap(readingAgeS: ageS));
        addTearDown(s.dispose);
        expect(
          s.freshness,
          expected,
          reason: 'a reading ${ageS}s old should be $expected',
        );
      }
    });

    test(
      'the same snapshot goes stale as the clock moves — no new data needed',
      () {
        // THE regression. One snapshot, never replaced, exactly as a quiet
        // fourteen-hour cook produces. Only the clock advances.
        final snap = _snap(readingAgeS: 0);

        final fresh = _session(snap, at: _fixedNow);
        addTearDown(fresh.dispose);
        expect(fresh.freshness, ProbeFreshness.live);

        final later = _session(snap, at: _fixedNow + 120 * 1000);
        addTearDown(later.dispose);
        expect(
          later.freshness,
          ProbeFreshness.stale,
          reason:
              'two minutes on, the same untouched snapshot must read stale — '
              'this is the assertion the old device-counter ladder failed',
        );

        final muchLater = _session(snap, at: _fixedNow + 4 * 3600 * 1000);
        addTearDown(muchLater.dispose);
        expect(muchLater.freshness, ProbeFreshness.frozen);
      },
    );

    test('an unknown age is unknown, never live', () {
      // The old ladder read a null age as `live` whenever any probe was
      // attached — so the BLE lane, which has no `/status` to carry the
      // counter at all, reported every reading as fresh forever.
      final s = _session(_snap(readingAgeS: null, link: LinkKind.ble));
      addTearDown(s.dispose);
      expect(s.freshness, ProbeFreshness.unknown);
    });

    test('no snapshot at all is unknown', () {
      final s = _session(null);
      addTearDown(s.dispose);
      expect(s.freshness, ProbeFreshness.unknown);
    });

    test('the bridge saying the base went quiet outranks our arithmetic', () {
      // We may be hearing the bridge perfectly and still be looking at numbers
      // nothing is measuring any more.
      final s = _session(_snap(readingAgeS: 2, baseLost: true));
      addTearDown(s.dispose);
      expect(s.freshness, ProbeFreshness.frozen);
    });
  });

  group('losing the link is said in the snapshot, not only in the launch', () {
    test('disconnected() restates the same readings as unreachable', () {
      final live = _snap(readingAgeS: 30);
      final gone = live.disconnected();

      expect(gone.link, LinkKind.offline);
      expect(
        gone.probes.map((p) => p.tempF10),
        live.probes.map((p) => p.tempF10),
        reason: 'the numbers do not change — only their trustworthiness does',
      );
      expect(
        gone.readingAtUnixMs,
        live.readingAtUnixMs,
        reason:
            'the reading is exactly as old as it was; the ladder ages it '
            'from here',
      );
      expect(
        gone.netMode,
        isNull,
        reason:
            '"hosting" and "joined" are claims about a live link, and there '
            'is not one',
      );
      expect(
        gone.address,
        live.address,
        reason:
            'where the bridge *was* is what the reconciler compares against '
            'to notice it has moved',
      );
    });
  });
}
