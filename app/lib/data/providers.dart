/// N2.30 — the Riverpod seam.
///
/// Screens depend on these four providers, never on an implementation type, so
/// N15 can swap `bridgeRepositoryProvider` for the real transport without a
/// widget change. This file imports Flutter (Riverpod) and is therefore **not**
/// part of the `dart test test/data` surface; the repositories it wires are.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/ble_gatt_fbp.dart' show openBleTransport;
import '../platform/firmware_picker.dart';
import '../platform/network_binder.dart';
import '../platform/notifications.dart';
import '../platform/permissions.dart';
import '../platform/share.dart';
import '../platform/system_settings.dart';
import 'dev_panel.dart';
import 'model/app_settings.dart';
import 'model/bridge_snapshot.dart';
import 'model/history_entry.dart';
import 'repository/bridge_repository.dart';
import 'repository/mock_bridge_repository.dart';
import 'repository/prefs_repository.dart';
import 'repository/real_bridge_repository.dart';
import 'transport/connection_supervisor.dart';
import 'transport/sample_cache.dart';

/// N15.8 — the real bridge transport is the default. The mock is opt-in for
/// the UX lab and fixture-driven dev runs:
/// `flutter run --dart-define=MOCK_BRIDGE=true`.
///
/// A normal debug, profile or release build talks to the bridge; only an
/// explicit `MOCK_BRIDGE=true` installs [MockBridgeRepository]. Tests override
/// the provider directly and never depend on this flag.
const bool kMockBridgeEnabled = bool.fromEnvironment('MOCK_BRIDGE');

/// The bridge host the real repository races first (mDNS name by default).
const String kBridgeHost = String.fromEnvironment(
  'BRIDGE_HOST',
  defaultValue: 'smokebridge.local',
);

/// The live repository. Real unless `MOCK_BRIDGE=true` (N15.8).
final bridgeRepositoryProvider = Provider<BridgeRepository>((ref) {
  if (!kMockBridgeEnabled) {
    final repo = RealBridgeRepository(
      supervisor: httpSupervisor(
        host: kBridgeHost,
        // N15.3 — let `auto` lead on BLE when the platform radio is available.
        bleOpener: openBleTransport,
      ),
      cache: ref.watch(sampleCacheProvider),
      // N15.20 — the real build threads a picked `.bin` into the OTA verb.
      firmwarePicker: _pickFirmware,
    );
    ref.onDispose(repo.dispose);
    return repo;
  }
  final repo = MockBridgeRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// N15.9 — the persistent sample cache. In-memory by default so tests and the
/// UX lab stay hermetic; `bootstrap.dart` overrides this with the drift cache
/// backed by a real on-device database.
final sampleCacheProvider = Provider<SampleCache>(
  (ref) => InMemorySampleCache(),
);

/// Preferences storage. In-memory by default (tests, dev panel); the app build
/// overrides this in `bootstrap.dart` with the persistent repository (N15.13).
final prefsProvider = Provider<PrefsRepository>((ref) {
  final prefs = MockPrefsRepository();
  ref.onDispose(prefs.dispose);
  return prefs;
});

/// N15.20 — adapt the platform picker's [PickedFirmware] to the repository's
/// transport-neutral [FirmwareImage]. A cancel is null, not an error.
Future<FirmwareImage?> _pickFirmware() async {
  final picked = await pickFirmwareImage();
  if (picked == null) {
    return null;
  }
  return FirmwareImage(
    name: picked.name,
    lengthBytes: picked.lengthBytes,
    bytes: picked.bytes,
  );
}

/// The settings tree, watched.
final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(prefsProvider).watch(),
);

// ── N15.15–N15.22 platform seams ─────────────────────────────────────────
//
// Defaults are the pure fakes so `flutter test` and the UX lab never touch a
// platform channel. `bootstrap.dart` overrides them with the plugin
// implementations on a real device.

/// N15.15/N15.17 — where the cook monitor posts.
final notificationSinkProvider = Provider<NotificationSink>(
  (ref) => RecordingNotificationSink(),
);

/// N15.16/N15.17 — the foreground-service lifecycle.
final foregroundServiceProvider = Provider<ForegroundServiceHost>(
  (ref) => FakeForegroundServiceHost(),
);

/// N15.18 — runtime BLE/notification permissions. Null until the composition
/// root installs the production backend (the gates then degrade to in-app
/// copy rather than throwing).
final permissionsProvider = Provider<AppPermissions?>((ref) => null);

/// N15.18 — OS-settings deep links.
final systemSettingsProvider = Provider<SystemSettings?>((ref) => null);

/// N15.19 — the hosted-AP network binder.
final networkBinderProvider = Provider<NetworkBinder?>((ref) => null);

/// N15.21 — the share sheet.
final shareSheetProvider = Provider<ShareSheet>((ref) => RecordingShareSheet());

/// The live snapshot, watched. Every screen reads this.
final snapshotProvider = StreamProvider<BridgeSnapshot>(
  (ref) => ref.watch(bridgeRepositoryProvider).snapshot(),
);

/// Past cooks, watched.
final historyProvider = StreamProvider<List<HistoryEntry>>(
  (ref) => ref.watch(bridgeRepositoryProvider).watchHistory(),
);

/// N2.32 — the deep link parsed at boot (`?scenario=` / `?units=` are applied
/// to the repositories; `?screen=` / `?overlay=` are left for the shell).
///
/// `bootstrap.dart` overrides this with the parsed [DevDeepLink], so N4's
/// router can read it once it exists and clear it. It is [DevDeepLink.none] on
/// a normal launch and always [DevDeepLink.none] in release.
final initialDevDeepLinkProvider = Provider<DevDeepLink>(
  (ref) => DevDeepLink.none,
);
