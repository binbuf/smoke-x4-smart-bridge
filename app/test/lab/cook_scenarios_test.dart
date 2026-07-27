/// A22.5 / A22.6 — the scenario regression suite (design 14 §14.12).
///
/// Pumps every frame of every [labScenarios] entry through the real
/// [CookView] at three phone widths and asserts it renders **cleanly**: no
/// thrown exception (which, in a widget test, includes any RenderFlex overflow —
/// the framework reports it as a `FlutterError` that [WidgetTester.takeException]
/// returns), and the key content for the frame is present. This is the "test
/// suite" that lets us change the UI and know the whole event flow still holds,
/// with no device and no bridge.
///
/// It is deliberately not a golden-image suite: image goldens need the bundled
/// fonts loaded and a pinned render backend (A19.2b). This asserts behaviour and
/// layout, which is what catches the overflow-on-a-narrow-phone and
/// null-in-a-stale-frame classes of bug — the two that actually bite.
///
/// A22.6 adds three checks the earlier suite could not make: that the real-cook
/// scenario reproduces the captured fixture byte-for-byte (not invented
/// numbers), that the new link/freshness states are shaped as the app must
/// handle them, and that the lab's °F/°C and forced-freshness overrides render
/// cleanly through the same production widgets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/lab/scenarios.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';

import '../support/load_fonts.dart';

// The narrowest supported phone, a common mid, and a large phone. 360 dp is
// where overflow bugs live.
const _widths = <double>[360, 393, 430];

Widget _host(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

LabScenario _byId(String id) => labScenarios.firstWhere((s) => s.id == id);

/// Pumps a [CookView] for one frame at [width] and asserts it renders cleanly.
Future<void> _expectClean(
  WidgetTester tester,
  LabFrame frame,
  double width, {
  ProbeFreshness? freshness,
  bool celsius = false,
  required String reason,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _host(
      CookView(
        snapshot: frame.snapshot,
        plan: frame.plan,
        freshness: freshness ?? frame.freshness,
        celsius: celsius,
      ),
    ),
  );
  // Settle the temperature tween and the gauge sweep.
  await tester.pump(const Duration(seconds: 1));

  expect(tester.takeException(), isNull, reason: reason);
  // Every frame shows at least one temperature digit somewhere.
  expect(find.textContaining(RegExp(r'\d')), findsWidgets, reason: reason);
}

/// The frames to render for a scenario. Small scenarios are exercised
/// exhaustively; a long real-cook replay (109 frames) is sampled — endpoints
/// plus an even spread — because it is the same layout every frame and 327
/// widget tests for one scenario buys no extra overflow coverage.
List<LabFrame> _framesToTest(List<LabFrame> frames) {
  if (frames.length <= 16) {
    return frames;
  }
  final picked = <LabFrame>[];
  const stride = 8;
  for (var i = 0; i < frames.length; i += stride) {
    picked.add(frames[i]);
  }
  if (picked.last != frames.last) {
    picked.add(frames.last);
  }
  return picked;
}

void main() {
  setUpAll(loadAppFonts);

  for (final scenario in labScenarios) {
    group('scenario: ${scenario.id}', () {
      for (final frame in _framesToTest(scenario.frames)) {
        for (final width in _widths) {
          // atS keeps the name unique even when two frames share a caption.
          testWidgets('${frame.label} @${frame.atS}s @${width.toInt()}dp', (
            tester,
          ) async {
            await _expectClean(
              tester,
              frame,
              width,
              reason:
                  '${scenario.id} / "${frame.label}" @ ${width.toInt()}dp '
                  'threw or overflowed',
            );
          });
        }
      }
    });
  }

  testWidgets('every scenario advances without a dead frame', (tester) async {
    for (final s in labScenarios) {
      expect(s.frames, isNotEmpty, reason: '${s.id} has no frames');
      // The timeline is monotonic and `at()` never returns null.
      for (var t = 0; t <= s.durationS; t += 60) {
        expect(s.at(t).label, isNotEmpty);
      }
    }
  });

  // ── A22.6: the new states are present and shaped correctly ──────────────

  test('the A22.6 states are all in the library', () {
    for (final id in [
      'real_x4',
      'ble_degraded',
      'offline_cached',
      'reconnect',
    ]) {
      expect(
        labScenarios.any((s) => s.id == id),
        isTrue,
        reason: 'scenario "$id" is missing from labScenarios',
      );
    }
  });

  test('real_x4 replays the captured fixture, not invented numbers', () {
    // The source of truth for the real cook. If the const in scenarios.dart
    // ever drifts from the capture, this fails — the whole point is real data.
    final fx =
        jsonDecode(
              File(
                '${_repoRoot()}/protocol/fixtures/'
                'live-x4-2026-07-25/recent_series.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final count = fx['count'] as int;
    final step = fx['step_s'] as int;
    final series = (fx['series_f10'] as List)
        .map((j) => (j as List).cast<int>())
        .toList();

    final s = _byId('real_x4');
    expect(s.frames, hasLength(count));
    for (var i = 0; i < count; i++) {
      final frame = s.frames[i];
      expect(frame.atS, i * step, reason: 'frame $i is off the 30 s grid');
      expect(frame.snapshot.probes, hasLength(4));
      for (var j = 0; j < 4; j++) {
        expect(
          frame.snapshot.probes[j].tempF10,
          series[j][i],
          reason: 'frame $i jack ${j + 1} does not match the capture',
        );
      }
    }
    // Instrument mode: raw probes, no cook plan.
    expect(s.frames.every((f) => f.plan == null), isTrue);
  });

  test('real_x4 grows its recent window one sample at a time', () {
    final s = _byId('real_x4');
    // The window starts short and ends holding the whole 54-minute cook.
    expect(s.frames.first.snapshot.probes[0].recent, hasLength(1));
    expect(
      s.frames.last.snapshot.probes[0].recent.length,
      s.frames.length,
      reason: 'the last frame should carry every sample so far',
    );
  });

  test('ble_degraded is a labelled, history-less BLE instrument', () {
    final s = _byId('ble_degraded');
    for (final f in s.frames) {
      expect(f.plan, isNull, reason: 'BLE degraded is instrument mode');
      expect(f.snapshot.link, LinkKind.ble);
      expect(
        f.snapshot.fullHistory,
        isFalse,
        reason: 'BLE cannot serve full history (2-hour preview only)',
      );
      expect(
        f.snapshot.probes.map((p) => p.name),
        ['Probe 1', 'Probe 2', 'Probe 3', 'Probe 4'],
        reason: 'BLE live_state carries no names — fall back to jack numbers',
      );
    }
  });

  test('offline_cached shows the freshness ladder while offline', () {
    final s = _byId('offline_cached');
    expect(s.frames.every((f) => f.snapshot.link == LinkKind.offline), isTrue);
    // Guided, so the removed gauges are what a reviewer inspects.
    expect(s.frames.every((f) => f.plan != null), isTrue);
    final rungs = s.frames.map((f) => f.freshness).toSet();
    expect(rungs, containsAll([ProbeFreshness.stale, ProbeFreshness.frozen]));
  });

  test('reconnect draws the outage as a real gap', () {
    final s = _byId('reconnect');
    // A frozen, base-lost middle: the app must not pretend the silence is live.
    expect(
      s.frames.any(
        (f) => f.freshness == ProbeFreshness.frozen && f.snapshot.baseLost,
      ),
      isTrue,
    );
    // The final frame's recent window has a real time hole (> the 120 s rate
    // gap), so the sparkline spans it instead of faking a flat line.
    final recent = s.frames.last.snapshot.probes[0].recent;
    var maxDt = 0;
    for (var i = 1; i < recent.length; i++) {
      final dt = recent[i].t - recent[i - 1].t;
      if (dt > maxDt) {
        maxDt = dt;
      }
    }
    expect(maxDt, greaterThan(120), reason: 'no drawn gap in the sparkline');
  });

  // ── A22.6: the lab's °F/°C and forced-freshness overrides render ────────

  group('override paths render cleanly', () {
    for (final id in [
      'real_x4',
      'ble_degraded',
      'offline_cached',
      'reconnect',
    ]) {
      final s = _byId(id);
      final endpoints = <LabFrame>{s.frames.first, s.frames.last};
      for (final frame in endpoints) {
        for (final width in _widths) {
          testWidgets('$id "${frame.label}" in °C @${width.toInt()}dp', (
            tester,
          ) async {
            await _expectClean(
              tester,
              frame,
              width,
              celsius: true,
              reason: '$id "${frame.label}" @ ${width.toInt()}dp in °C',
            );
          });
        }
      }
    }

    // Forcing any rung on a guided frame is the lab's freshness override; it
    // must survive every rung, including the derived-values-removed ones.
    final guided = _byId('offline_cached').frames.first;
    for (final rung in ProbeFreshness.values) {
      testWidgets('forced ${rung.name} on a guided frame @360dp', (
        tester,
      ) async {
        await _expectClean(
          tester,
          guided,
          360,
          freshness: rung,
          reason: 'forced ${rung.name}',
        );
      });
    }
  });
}

/// Walks up from the test's working directory to the repo root, located by its
/// `protocol/records.yaml` — the same anchor the data-layer fixtures use.
String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = dir.parent;
  }
  return dir.path;
}
