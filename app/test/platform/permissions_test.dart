/// A24.2 — the permission REDUCTION contract: version-gated set selection, the
/// status → verdict map, and the worst-wins combine, driven by a fake backend
/// with no OS prompt (design 13 §13.2.0, 05 §5.8.3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/platform/permissions.dart';

/// The plugin seam, faked. `status` reads a script; `request` records the ask
/// and returns the scripted post-prompt status (falling back to the pre-prompt
/// one, then granted), so "which permissions were even requested" is assertable.
class FakePermissionBackend implements PermissionBackend {
  FakePermissionBackend({
    this.androidSdkInt,
    this.locationServices = true,
    Map<AppPermission, RawPermissionStatus>? statuses,
    Map<AppPermission, RawPermissionStatus>? afterRequest,
  }) : _statuses = {...?statuses},
       _afterRequest = {...?afterRequest};

  @override
  final int? androidSdkInt;
  bool locationServices;
  final Map<AppPermission, RawPermissionStatus> _statuses;
  final Map<AppPermission, RawPermissionStatus> _afterRequest;

  final List<AppPermission> requested = [];

  @override
  Future<RawPermissionStatus> status(AppPermission p) async =>
      _statuses[p] ?? RawPermissionStatus.denied;

  @override
  Future<RawPermissionStatus> request(AppPermission p) async {
    requested.add(p);
    final r = _afterRequest[p] ?? _statuses[p] ?? RawPermissionStatus.granted;
    _statuses[p] = r;
    return r;
  }

  @override
  Future<bool> locationServicesEnabled() async => locationServices;
}

void main() {
  group('ensureBleReady — version-gated set selection', () {
    test(
      'Android 12+ (SDK 33) asks scan + connect only, NOT location',
      () async {
        final backend = FakePermissionBackend(
          androidSdkInt: 33,
          afterRequest: {
            AppPermission.bluetoothScan: RawPermissionStatus.granted,
            AppPermission.bluetoothConnect: RawPermissionStatus.granted,
          },
        );
        final result = await AppPermissions(backend).ensureBleReady();
        expect(result, PermissionResult.granted);
        expect(backend.requested, [
          AppPermission.bluetoothScan,
          AppPermission.bluetoothConnect,
        ]);
        expect(backend.requested, isNot(contains(AppPermission.location)));
      },
    );

    test('Android 11 (SDK 30) also asks for location', () async {
      final backend = FakePermissionBackend(
        androidSdkInt: 30,
        afterRequest: {
          AppPermission.bluetoothScan: RawPermissionStatus.granted,
          AppPermission.bluetoothConnect: RawPermissionStatus.granted,
          AppPermission.location: RawPermissionStatus.granted,
        },
      );
      final result = await AppPermissions(backend).ensureBleReady();
      expect(result, PermissionResult.granted);
      expect(backend.requested, contains(AppPermission.location));
    });

    test('off Android (null SDK) skips the legacy location leg', () async {
      final backend = FakePermissionBackend(
        androidSdkInt: null,
        afterRequest: {
          AppPermission.bluetoothScan: RawPermissionStatus.granted,
          AppPermission.bluetoothConnect: RawPermissionStatus.granted,
        },
      );
      await AppPermissions(backend).ensureBleReady();
      expect(backend.requested, isNot(contains(AppPermission.location)));
    });
  });

  group('ensureBleReady — worst verdict wins', () {
    Future<PermissionResult> withStatuses(
      Map<AppPermission, RawPermissionStatus> after,
    ) => AppPermissions(
      FakePermissionBackend(androidSdkInt: 33, afterRequest: after),
    ).ensureBleReady();

    test('one denied → denied', () async {
      expect(
        await withStatuses({
          AppPermission.bluetoothScan: RawPermissionStatus.granted,
          AppPermission.bluetoothConnect: RawPermissionStatus.denied,
        }),
        PermissionResult.denied,
      );
    });

    test('one permanentlyDenied outranks a plain denial', () async {
      expect(
        await withStatuses({
          AppPermission.bluetoothScan: RawPermissionStatus.denied,
          AppPermission.bluetoothConnect: RawPermissionStatus.permanentlyDenied,
        }),
        PermissionResult.permanentlyDenied,
      );
    });

    test('all granted → granted', () async {
      expect(
        await withStatuses({
          AppPermission.bluetoothScan: RawPermissionStatus.granted,
          AppPermission.bluetoothConnect: RawPermissionStatus.granted,
        }),
        PermissionResult.granted,
      );
    });
  });

  group('the status → verdict map', () {
    Future<PermissionResult> single(RawPermissionStatus s) => AppPermissions(
      FakePermissionBackend(
        androidSdkInt: 33,
        afterRequest: {
          AppPermission.bluetoothScan: s,
          AppPermission.bluetoothConnect: RawPermissionStatus.granted,
        },
      ),
    ).ensureBleReady();

    test('limited and provisional are usable grants', () async {
      expect(
        await single(RawPermissionStatus.limited),
        PermissionResult.granted,
      );
      expect(
        await single(RawPermissionStatus.provisional),
        PermissionResult.granted,
      );
    });

    test('restricted routes like permanent (settings, not retry)', () async {
      expect(
        await single(RawPermissionStatus.restricted),
        PermissionResult.permanentlyDenied,
      );
    });

    test('denied stays retryable', () async {
      expect(await single(RawPermissionStatus.denied), PermissionResult.denied);
    });
  });

  group('bleStatus — reads without prompting', () {
    test('never records a request, and combines statuses', () async {
      final backend = FakePermissionBackend(
        androidSdkInt: 33,
        statuses: {
          AppPermission.bluetoothScan: RawPermissionStatus.granted,
          AppPermission.bluetoothConnect: RawPermissionStatus.denied,
        },
      );
      final result = await AppPermissions(backend).bleStatus();
      expect(result, PermissionResult.denied);
      expect(backend.requested, isEmpty);
    });
  });

  group('notifications', () {
    test('ensureNotifications maps the single verdict and prompts', () async {
      final backend = FakePermissionBackend(
        androidSdkInt: 33,
        afterRequest: {
          AppPermission.notification: RawPermissionStatus.permanentlyDenied,
        },
      );
      final result = await AppPermissions(backend).ensureNotifications();
      expect(result, PermissionResult.permanentlyDenied);
      expect(backend.requested, [AppPermission.notification]);
    });

    test('notificationStatus reads without prompting', () async {
      final backend = FakePermissionBackend(
        androidSdkInt: 33,
        statuses: {AppPermission.notification: RawPermissionStatus.granted},
      );
      expect(
        await AppPermissions(backend).notificationStatus(),
        PermissionResult.granted,
      );
      expect(backend.requested, isEmpty);
    });
  });

  group('locationServicesEnabled — passthrough', () {
    test('reflects the backend toggle', () async {
      expect(
        await AppPermissions(
          FakePermissionBackend(androidSdkInt: 30, locationServices: false),
        ).locationServicesEnabled(),
        isFalse,
      );
      expect(
        await AppPermissions(
          FakePermissionBackend(androidSdkInt: 30, locationServices: true),
        ).locationServicesEnabled(),
        isTrue,
      );
    });
  });
}
