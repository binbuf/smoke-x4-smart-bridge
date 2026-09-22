/// N2.30 — the Riverpod seam.
///
/// Screens depend on these four providers, never on an implementation type, so
/// N15 can swap `bridgeRepositoryProvider` for the real transport without a
/// widget change. This file imports Flutter (Riverpod) and is therefore **not**
/// part of the `dart test test/data` surface; the repositories it wires are.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dev_panel.dart';
import 'model/app_settings.dart';
import 'model/bridge_snapshot.dart';
import 'model/history_entry.dart';
import 'repository/bridge_repository.dart';
import 'repository/mock_bridge_repository.dart';
import 'repository/prefs_repository.dart';
import 'repository/real_bridge_repository.dart';
import 'transport/connection_supervisor.dart';

/// N15.8 — opt in to the real bridge transport at build time:
/// `flutter run --dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=…`.
///
/// The default stays [MockBridgeRepository] so the dev panel, the UX lab and
/// every existing test keep working; a real build flips one flag.
const bool kRealBridgeEnabled = bool.fromEnvironment('REAL_BRIDGE');

/// The bridge host the real repository races first (mDNS name by default).
const String kBridgeHost = String.fromEnvironment(
  'BRIDGE_HOST',
  defaultValue: 'smokebridge.local',
);

/// The live repository. Mock unless `REAL_BRIDGE=true` (N15.8).
final bridgeRepositoryProvider = Provider<BridgeRepository>((ref) {
  if (kRealBridgeEnabled) {
    final repo = RealBridgeRepository(
      supervisor: httpSupervisor(host: kBridgeHost),
    );
    ref.onDispose(repo.dispose);
    return repo;
  }
  final repo = MockBridgeRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Preferences storage. In-memory until N15.
final prefsProvider = Provider<PrefsRepository>((ref) {
  final prefs = MockPrefsRepository();
  ref.onDispose(prefs.dispose);
  return prefs;
});

/// The settings tree, watched.
final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(prefsProvider).watch(),
);

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
