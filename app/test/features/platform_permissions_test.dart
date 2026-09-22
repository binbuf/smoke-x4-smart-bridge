/// N15.18/N15.19 — the permission and network-binder seams.
///
/// `flutter_test` because both files import `flutter/services` (the
/// `permission_handler` and `MethodChannel` plumbing); the logic under test is
/// pure and driven by fakes, so no OS prompt or Kotlin is involved.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/platform/network_binder.dart';
import 'package:smoke_bridge/platform/permissions.dart';

class FakePermissionBackend implements PermissionBackend {
  FakePermissionBackend({this.androidSdkInt, this.locationServices = true});

  @override
  final int? androidSdkInt;
  bool locationServices;

  /// The answer each request/status returns; defaults to granted.
  final Map<AppPermission, RawPermissionStatus> answers = {};

  final requested = <AppPermission>[];
  final read = <AppPermission>[];

  RawPermissionStatus _answer(AppPermission p) =>
      answers[p] ?? RawPermissionStatus.granted;

  @override
  Future<RawPermissionStatus> request(AppPermission p) async {
    requested.add(p);
    return _answer(p);
  }

  @override
  Future<RawPermissionStatus> status(AppPermission p) async {
    read.add(p);
    return _answer(p);
  }

  @override
  Future<bool> locationServicesEnabled() async => locationServices;
}

void main() {
  group('AppPermissions (N15.18)', () {
    test('Android 12+ requests scan + connect, never location', () async {
      final backend = FakePermissionBackend(androidSdkInt: 33);
      final perms = AppPermissions(backend);
      expect(await perms.ensureBleReady(), PermissionResult.granted);
      expect(backend.requested, [
        AppPermission.bluetoothScan,
        AppPermission.bluetoothConnect,
      ]);
    });

    test('Android 11 and below adds the legacy location leg', () async {
      final backend = FakePermissionBackend(androidSdkInt: 30);
      final perms = AppPermissions(backend);
      await perms.ensureBleReady();
      expect(backend.requested, contains(AppPermission.location));
    });

    test('a single permanent denial wins over the granted rest', () async {
      final backend = FakePermissionBackend(androidSdkInt: 33);
      backend.answers[AppPermission.bluetoothConnect] =
          RawPermissionStatus.permanentlyDenied;
      final perms = AppPermissions(backend);
      expect(await perms.ensureBleReady(), PermissionResult.permanentlyDenied);
    });

    test('a plain denial is retryable', () async {
      final backend = FakePermissionBackend(androidSdkInt: 33);
      backend.answers[AppPermission.bluetoothScan] = RawPermissionStatus.denied;
      final perms = AppPermissions(backend);
      expect(await perms.bleStatus(), PermissionResult.denied);
      expect(backend.read, isNotEmpty);
    });

    test(
      'restricted routes like permanently denied (no dialog left)',
      () async {
        final backend = FakePermissionBackend(androidSdkInt: 33);
        backend.answers[AppPermission.bluetoothScan] =
            RawPermissionStatus.restricted;
        final perms = AppPermissions(backend);
        expect(await perms.bleStatus(), PermissionResult.permanentlyDenied);
      },
    );

    test('notifications are a separate prompt and never fatal', () async {
      final backend = FakePermissionBackend(androidSdkInt: 33);
      backend.answers[AppPermission.notification] = RawPermissionStatus.denied;
      final perms = AppPermissions(backend);
      expect(await perms.ensureNotifications(), PermissionResult.denied);
      expect(await perms.locationServicesEnabled(), isTrue);
    });
  });

  group('FakeNetworkBinder (N15.19)', () {
    test('bind then unbind is a strict lifecycle', () async {
      final binder = FakeNetworkBinder();
      expect(binder.state, BinderState.unbound);
      await binder.bind();
      expect(binder.state, BinderState.bound);
      expect(() => binder.bind(), throwsA(isA<BinderStateError>()));
      await binder.unbind();
      expect(binder.state, BinderState.unbound);
      expect(() => binder.unbind(), throwsA(isA<BinderStateError>()));
      await binder.dispose();
    });

    test(
      'joinAp implies the bind (a joined-but-unbound AP is the trap)',
      () async {
        final binder = FakeNetworkBinder();
        await binder.joinAp('SmokeBridge-A4F2', 'hunter2boo');
        expect(binder.state, BinderState.bound);
        expect(binder.calls, ['joinAp:SmokeBridge-A4F2']);
        await binder.dispose();
      },
    );

    test('a lost network releases the binding and says so', () async {
      final binder = FakeNetworkBinder();
      await binder.bind();
      final seen = <BinderState>[];
      final sub = binder.states.listen(seen.add);
      binder.simulateLost();
      await Future<void>.delayed(Duration.zero);
      expect(binder.state, BinderState.lost);
      expect(seen, [BinderState.lost]);
      await sub.cancel();
      await binder.dispose();
    });

    test('dispose releases a live binding, never throws', () async {
      final binder = FakeNetworkBinder();
      await binder.bind();
      await binder.dispose();
      expect(binder.calls, contains('bind'));
      expect(binder.calls, contains('unbind'));
    });
  });
}
