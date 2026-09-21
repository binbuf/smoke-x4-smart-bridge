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

/// The live repository. Mock until N15.
final bridgeRepositoryProvider = Provider<BridgeRepository>((ref) {
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
