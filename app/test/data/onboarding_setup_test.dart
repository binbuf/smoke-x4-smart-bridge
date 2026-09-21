/// N14 — the pure onboarding state machine.
///
/// Runs under `dart test test/domain test/data`: no binding, no Flutter.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/onboarding/setup_format.dart';
import 'package:test/test.dart';

void main() {
  group('steps and the rail (N14.1)', () {
    test('there are exactly eight named steps in order', () {
      expect(kOnboardSteps.map((step) => step.name), <String>[
        'welcome',
        'preflight',
        'scan',
        'passkey',
        'sync',
        'network',
        'name',
        'done',
      ]);
      expect(kOnboardSteps, hasLength(8));
    });

    test('every step has a title, sub and primary label', () {
      for (final step in kOnboardSteps) {
        expect(step.title, isNotEmpty, reason: step.name);
        expect(step.sub, isNotEmpty, reason: step.name);
        expect(step.primaryLabel, isNotEmpty, reason: step.name);
      }
      expect(OnboardStep.scan.primaryLabel, 'Pair this bridge');
      expect(OnboardStep.passkey.primaryLabel, 'Confirm');
      expect(OnboardStep.done.primaryLabel, 'Go to Live');
    });
  });

  group('advancing and I6 — no state without a next step', () {
    test('welcome always has a forward action', () {
      const state = SetupState();
      expect(state.step, OnboardStep.welcome);
      expect(state.canAdvance, isTrue);
      expect(state.next().step, OnboardStep.preflight);
    });

    test('preflight blocks until the required permissions are granted', () {
      const state = SetupState(step: OnboardStep.preflight);
      expect(state.canAdvance, isFalse);
      expect(state.blockedReason, isNotNull);
      expect(state.next().step, OnboardStep.preflight, reason: 'no forward');

      final allowed = state
          .allow(OnboardPermission.bluetooth)
          .allow(OnboardPermission.notifications);
      expect(allowed.canAdvance, isTrue);
      expect(allowed.next().step, OnboardStep.scan);
      // Location is explicitly optional ("older Android"): it never blocks.
      expect(
        allowed.permissionOf(OnboardPermission.location),
        PermissionState.unknown,
      );
    });

    test('scan blocks until a bridge answers', () {
      const state = SetupState(step: OnboardStep.scan);
      expect(state.canAdvance, isFalse);
      expect(
        state.foundBridge().canAdvance,
        isTrue,
        reason: 'a found bridge is a next step',
      );
      expect(state.foundBridge().next().step, OnboardStep.passkey);
    });

    test('passkey confirms then advances to sync', () {
      const state = SetupState(step: OnboardStep.passkey);
      expect(state.canAdvance, isFalse);
      final confirmed = state.confirmPasskey();
      expect(confirmed.canAdvance, isTrue);
      expect(confirmed.next().step, OnboardStep.sync);
    });

    test('sync blocks until the base hop is resolved', () {
      const state = SetupState(step: OnboardStep.sync);
      expect(state.canAdvance, isFalse);
      expect(state.heardBase().canAdvance, isTrue);
      expect(state.skipBase().canAdvance, isTrue);
      expect(state.heardBase().next().step, OnboardStep.network);
      expect(state.skipBase().next().step, OnboardStep.network);
    });

    test('name blocks on an empty bridge name', () {
      const state = SetupState(step: OnboardStep.name);
      expect(state.canAdvance, isTrue, reason: 'the default has a name');
      final blank = state.setName('   ');
      expect(blank.canAdvance, isFalse);
      expect(blank.next().step, OnboardStep.name);
      expect(blank.setName('Patio').next().step, OnboardStep.done);
    });

    test('back never moves past the first step', () {
      expect(const SetupState().back().step, OnboardStep.welcome);
      expect(
        const SetupState(step: OnboardStep.name).back().step,
        OnboardStep.network,
      );
    });
  });

  group('preflight permissions (N14.3)', () {
    test('a denied permission is a resumable named state', () {
      const state = SetupState(step: OnboardStep.preflight);
      final denied = state.deny(OnboardPermission.bluetooth);
      expect(
        denied.permissionOf(OnboardPermission.bluetooth),
        PermissionState.denied,
      );
      expect(denied.fault, SetupFault.permissionDenied);
      expect(denied.canAdvance, isFalse);
      expect(denied.fault.title, isNotEmpty);
      expect(denied.fault.body, isNotEmpty);
      expect(denied.fault.terminal, isFalse);

      final resumed = denied.allow(OnboardPermission.bluetooth);
      expect(resumed.fault, SetupFault.none);
      expect(resumed.canAdvance, isFalse, reason: 'notifications still due');
    });
  });

  group('the passkey is never rendered (invariant)', () {
    test('there is no code field and no code parameter anywhere', () {
      const state = SetupState(step: OnboardStep.passkey);
      expect(state.passkeyConfirmed, isFalse);
      // The placeholder is a fixed elision, not a code.
      expect(kPasskeyPlaceholder, '••••••');
      expect(RegExp(r'\d{4,6}').hasMatch(kPasskeyPlaceholder), isFalse);
    });
  });

  group('recovery paths (N14.11)', () {
    test('every fault is named with copy and a recovery label (I15)', () {
      for (final fault in SetupFault.values) {
        if (fault == SetupFault.none) {
          expect(fault.title, isEmpty);
          continue;
        }
        expect(fault.title, isNotEmpty, reason: fault.name);
        expect(fault.body, isNotEmpty, reason: fault.name);
        expect(fault.recoverLabel, isNotEmpty, reason: fault.name);
      }
    });

    test('a skipped hop reads "— not set up"', () {
      const state = SetupState(step: OnboardStep.sync);
      final skipped = state.skipBase();
      expect(skipped.hopOf(SetupHop.baseStation), HopStatus.skipped);
      expect(skipped.hopOf(SetupHop.bluetooth), HopStatus.notSetUp);
      expect(HopStatus.notSetUp.label, '— not set up');
      expect(HopStatus.skipped.label, 'Skipped');
      expect(HopStatus.done.label, 'Paired');
    });

    test('the done step summarises all three hops', () {
      final state = const SetupState()
          .foundBridge()
          .confirmPasskey()
          .skipBase();
      final summary = state.hopSummary;
      expect(summary, hasLength(SetupHop.values.length));
      final base = summary.firstWhere((row) => row.hop == SetupHop.baseStation);
      expect(base.statusLabel, 'Skipped');
      final bluetooth = summary.firstWhere(
        (row) => row.hop == SetupHop.bluetooth,
      );
      expect(bluetooth.statusLabel, 'Paired');
    });
  });

  group('network mode (N14.8)', () {
    test('defaults to Bluetooth and stamps the network hop', () {
      const state = SetupState(step: OnboardStep.network);
      expect(state.modeId, 'ble');
      final sta = state.selectMode('sta');
      expect(sta.modeId, 'sta');
      expect(sta.hopOf(SetupHop.network), HopStatus.done);
    });
  });

  group('name and units (N14.9)', () {
    test('name and units are carried on the value', () {
      const state = SetupState(step: OnboardStep.name);
      expect(state.name, 'Backyard Bridge');
      expect(state.units, TempUnit.fahrenheit);
      final next = state.setName('Patio').setUnits(TempUnit.celsius);
      expect(next.name, 'Patio');
      expect(next.units, TempUnit.celsius);
    });
  });

  group('monotonic generation guard (invariant)', () {
    test('a superseded completion cannot drag the flow backwards', () {
      const state = SetupState(step: OnboardStep.scan);
      // Two overlapping async flows: the first is superseded by the second.
      final first = state.beginAsync();
      final staleToken = first.token;
      final second = first.beginAsync();
      expect(second.generation, state.generation + 2);

      // The stale flow's late completion is dropped.
      final staleResolved = second.resolve(
        staleToken,
        (s) => s.copyWith(step: OnboardStep.welcome),
      );
      expect(staleResolved.step, OnboardStep.scan);
      expect(staleResolved, second);

      // The current flow's completion lands.
      final resolved = second.resolve(second.token, (s) => s.foundBridge());
      expect(resolved.hopOf(SetupHop.bluetooth), HopStatus.done);
    });

    test('generation only ever increases', () {
      var state = const SetupState();
      for (var i = 1; i <= 5; i++) {
        state = state.beginAsync();
        expect(state.generation, i);
      }
    });
  });
}
