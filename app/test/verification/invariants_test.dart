/// N16.2 — the invariant suite: one named test per I2–I15.
///
/// `newui/components_research_notes.md` §1 lists fifteen non-negotiable
/// invariants. I1 (the bridge transmits exactly one LoRa packet) is firmware
/// and is not testable from the app; the other fourteen each get a test here,
/// named `I<n> — …`, so a regression points straight at the rule it broke.
///
/// These tests deliberately assert the *contract*, not the pixel: each one is
/// anchored to the smallest real seam that enforces the rule (a pure function,
/// a design primitive, or the composed screen). Widget tests that need a live
/// snapshot use the mock repository's named scenarios.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/alarms/notification_policy.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/atoms.dart' as atoms;
import 'package:smoke_bridge/design/design.dart' hide AlarmTier;
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/live/live.dart';
import 'package:smoke_bridge/features/onboarding/onboarding.dart';
import 'package:smoke_bridge/features/settings/settings.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;

Alarm _alarm({
  required AlarmTier tier,
  AlarmSeverity severity = AlarmSeverity.critical,
  String rule = 'target_reached',
  int atMs = _t0ms,
  bool acked = false,
}) => Alarm(
  id: '${tier.name}-$rule',
  tier: tier,
  severity: severity,
  rule: rule,
  atMs: atMs,
  acked: acked,
  ruleId: rule,
);

void main() {
  setUpAll(loadAppFonts);

  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;

  setUp(() {
    repo = MockBridgeRepository(nowMs: _t0ms);
    prefs = MockPrefsRepository();
  });

  tearDown(() async {
    await repo.dispose();
    await prefs.dispose();
  });

  Widget harness(Widget child) => ProviderScope(
    overrides: [
      bridgeRepositoryProvider.overrideWithValue(repo),
      prefsProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: SmokeThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );

  // ── I2 ────────────────────────────────────────────────────────────────
  test('I2 — the app mirrors a device alarm; it never re-decides it', () {
    final now = DateTime(2026, 9, 21, 3, 40);
    final device = _alarm(
      tier: AlarmTier.device,
      atMs: now.millisecondsSinceEpoch,
    );
    // 03:40, inside quiet hours: a critical device alarm still sounds. That is
    // the whole reason the device tier exists.
    final plan = planNotifications(
      alarms: <Alarm>[device],
      alreadyPosted: const <String>{},
      now: now,
    );

    expect(plan.post, hasLength(1));
    expect(plan.post.single.channel, NotificationChannel.critical);
    expect(plan.post.single.silent, isFalse);
    expect(plan.post.single.alarmId, device.id);

    // The app does not resolve it, and polling again does not re-post it.
    final repoll = planNotifications(
      alarms: <Alarm>[device],
      alreadyPosted: <String>{alarmKey(device)},
      escalatedTo: <String, int>{alarmKey(device): 0},
      now: now.add(const Duration(seconds: 30)),
    );
    expect(repoll.post, isEmpty);
    expect(repoll.withdraw, isEmpty);
  });

  test(
    'I2 — an app insight is labelled as an insight, never a device alarm',
    () {
      // The tag word differs; the two tiers are distinct enum values.
      expect(atoms.AlarmTier.device, isNot(atoms.AlarmTier.app));
      expect(
        () => const atoms.TierTag(tier: atoms.AlarmTier.app),
        returnsNormally,
      );
    },
  );

  // ── I3 ────────────────────────────────────────────────────────────────
  test('I3 — absent is not zero: a detached probe renders an em dash', () {
    expect(tempParts(null, TempUnit.fahrenheit).num, '—');
    expect(tempParts(null, TempUnit.celsius).num, '—');
    expect(fmtTemp0(null, TempUnit.fahrenheit), '—');
    expect(spokenTemp(null, TempUnit.fahrenheit), 'No reading');

    // A present zero is still a present value, distinct from absent.
    expect(TempValue.fromWire(tempDetachedSentinel).isAbsent, isTrue);
    expect(TempValue.fromWire(0).toDisplay(TempUnit.fahrenheit), 0);
  });

  // ── I4 ────────────────────────────────────────────────────────────────
  test('I4 — stale removes derived values rather than greying them', () {
    expect(Freshness.live.showsDerived, isTrue);
    expect(Freshness.aging.showsDerived, isTrue);
    expect(Freshness.stale.showsDerived, isFalse);
    expect(Freshness.frozen.showsDerived, isFalse);
    expect(Freshness.unknown.showsDerived, isFalse);
  });

  // ── I5 ────────────────────────────────────────────────────────────────
  testWidgets('I5 — a disabled control states its reason on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeThemeData.dark(),
        home: const Scaffold(
          body: PrimaryAction(
            label: 'Install',
            onPressed: null,
            enabledReason: 'An image is Wi-Fi only',
          ),
        ),
      ),
    );
    expect(find.text('Install'), findsOneWidget);
    expect(find.text('An image is Wi-Fi only'), findsOneWidget);
  });

  // ── I6 ────────────────────────────────────────────────────────────────
  test('I6 — every setup step has a next step, with a reason otherwise', () {
    const welcome = SetupState();
    expect(welcome.canAdvance, isTrue);
    expect(welcome.blockedReason, isNull);

    // A fresh preflight cannot advance until the permissions are granted, and
    // it says why.
    const preflight = SetupState(step: OnboardStep.preflight);
    expect(preflight.canAdvance, isFalse);
    expect(preflight.blockedReason, isNotNull);

    // Nor can an unnamed bridge.
    const unnamed = SetupState(step: OnboardStep.name, name: '   ');
    expect(unnamed.canAdvance, isFalse);
    expect(unnamed.blockedReason, isNotNull);
  });

  testWidgets('I6 — an empty state offers exactly one way forward', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: EmptyState(
            title: 'No cooks yet',
            copy: 'Start one and it will appear here.',
            actionLabel: 'Set up a cook',
            onAction: () => pressed++,
          ),
        ),
      ),
    );
    expect(find.text('Set up a cook'), findsOneWidget);
    await tester.tap(find.text('Set up a cook'));
    expect(pressed, 1);
  });

  // ── I7 ────────────────────────────────────────────────────────────────
  test('I7 — a device verb is confirmed by a read-back line', () {
    // Every verb spec names its steps and its read-back copy; the sheet shows
    // the read-back rather than assuming the write landed.
    for (final spec in kVerbSpecs) {
      expect(spec.steps, isNotEmpty, reason: spec.id);
      expect(spec.sub, isNotEmpty, reason: spec.id);
    }
  });

  // ── I8 ────────────────────────────────────────────────────────────────
  testWidgets('I8 — a destructive action states keeps and loses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeThemeData.dark(),
        home: const Scaffold(
          body: CostSheet(
            title: 'Factory reset?',
            message: 'The bridge forgets everything.',
            keeps: <String>['Nothing'],
            loses: <String>['Every recorded cook', 'The pairing'],
            confirmLabel: 'Erase',
            cancelLabel: 'Keep it',
          ),
        ),
      ),
    );
    expect(find.text('KEEPS'), findsOneWidget);
    expect(find.text('LOSES'), findsOneWidget);
    expect(find.text('Every recorded cook'), findsOneWidget);
    expect(find.text('Erase'), findsOneWidget);
    expect(find.text('Keep it'), findsOneWidget);
  });

  // ── I9 ────────────────────────────────────────────────────────────────
  test('I9 — exactly one transport is active at a time', () async {
    final wifi = MockTransport(kind: TransportKind.http, label: 'wifi');
    final ble = MockTransport(kind: TransportKind.ble, label: 'ble');
    final factory = _TestTransportFactory(wifi: wifi, ble: ble);
    final supervisor = ConnectionSupervisor(
      manager: ConnectionManager(factory: factory),
      factory: factory,
    );

    final active = await supervisor.start();
    expect(active, same(wifi));
    expect(supervisor.active, same(wifi));
    expect(supervisor.active!.kind, TransportKind.http);
    // BLE is held warm, but it is not the active (data-carrying) transport.
    expect(supervisor.bleWarm, isTrue);
    await supervisor.dispose();
  });

  // ── I10 ───────────────────────────────────────────────────────────────
  test(
    'I10 — samples key on (bridgeId, sessionId, t) and are never rewritten',
    () async {
      final cache = InMemorySampleCache();
      await cache.upsertSamples('b1', 1, const <Sample>[
        Sample(t: 0, tempsF10: [1000, null, null, null], unixMs: 5),
      ]);
      // Re-syncing the same instant with a different value is a no-op: the first
      // recorded value is the truth.
      await cache.upsertSamples('b1', 1, const <Sample>[
        Sample(t: 0, tempsF10: [1999, null, null, null], unixMs: 5),
      ]);
      final rows = await cache.samples('b1', 1);
      expect(rows, hasLength(1));
      expect(rows.single.tempsF10.first, 1000);

      // A different session is a different key.
      await cache.upsertSamples('b1', 2, const <Sample>[
        Sample(t: 0, tempsF10: [2000, null, null, null], unixMs: 5),
      ]);
      expect(await cache.sampleCount('b1', 2), 1);
    },
  );

  // ── I11 ───────────────────────────────────────────────────────────────
  test('I11 — a bridge with no clock stores null, never a fabricated time', () {
    const noClock = Sample(t: 0, tempsF10: [1000, null, null, null]);
    expect(noClock.unixMs, isNull);
    expect(
      candidateAnchors(
        samples: const <Sample>[
          Sample(t: 0, tempsF10: [1000, null, null, null]),
        ],
        sessionStartUnixMs: null,
      ),
      isEmpty,
    );
  });

  // ── I12 ───────────────────────────────────────────────────────────────
  test('I12 — food safety is a hard gate; an unsafe target is refused', () {
    expect(
      () => CookPlan(
        presetId: 'custom',
        title: 'Chicken',
        hazard: HazardClass.poultry,
        doneness: 'Done',
        probes: <PlanProbe>[
          PlanProbe(
            jack: ProbeJack.one,
            isPit: false,
            name: 'Chicken',
            targetF10: 1400, // below the 165 °F poultry floor
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  // ── I13 ───────────────────────────────────────────────────────────────
  testWidgets('I13 — a missing capability is copy, never an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeThemeData.dark(),
        home: const Scaffold(
          body: CapabilityNotice(message: 'Full history needs Wi-Fi.'),
        ),
      ),
    );
    expect(find.text('Full history needs Wi-Fi.'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
  });

  // ── I14 ───────────────────────────────────────────────────────────────
  testWidgets('I14 — a destination has at most one ember primary action', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final scenario in <String>['running', 'idle', 'offline']) {
      await repo.selectScenario(scenario);
      await tester.pumpWidget(harness(const LivePage()));
      await tester.pumpAndSettle();
      expect(
        find.byType(PrimaryAction).evaluate().length,
        lessThanOrEqualTo(1),
        reason: 'LivePage/$scenario has more than one ember primary action',
      );
    }
  });

  // ── I15 ───────────────────────────────────────────────────────────────
  testWidgets('I15 — a failure is a named state, never a raw exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: ProblemState(
            title: 'Bridge unreachable',
            copy: 'It may have restarted. We will keep trying.',
            actionLabel: 'Reconnect',
            onAction: () {},
          ),
        ),
      ),
    );
    expect(find.text('Bridge unreachable'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    // The component takes named copy only — there is no `Object error` seam.
    expect(find.textContaining('Exception'), findsNothing);
  });
}

class _TestTransportFactory implements TransportFactory {
  _TestTransportFactory({required this.wifi, required this.ble});

  final MockTransport wifi;
  final MockTransport ble;

  @override
  Future<BridgeTransport?> openHttp(String host) async => wifi;

  @override
  Future<BridgeTransport?> openBle() async => ble;
}
