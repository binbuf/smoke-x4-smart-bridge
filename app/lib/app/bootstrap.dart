/// N0.7 — app bootstrap: bindings, bundled-font licences, and the
/// `ProviderScope` every later provider hangs off.
///
/// N2.32 adds the boot deep link: `?scenario=` / `?units=` are applied to the
/// repositories before the first frame, and the parsed link is exposed to the
/// shell through `initialDevDeepLinkProvider` for the N4 router to consume.
///
/// N15.13/N15.9 open the persistent stores here, **before** the container
/// exists, so the first frame already has settings and a cache to read from.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alarms/notification_policy.dart';
import '../data/dev_panel.dart';
import '../data/local/drift_sample_cache.dart';
import '../data/local/open_database.dart';
import '../data/model/app_settings.dart';
import '../data/providers.dart';
import '../data/repository/real_prefs_repository.dart';
import '../data/repository/shared_prefs_store.dart';
import '../features/dev/dev_boot.dart';
import '../features/monitor/monitor.dart';
import '../platform/network_binder.dart';
import '../platform/notifications.dart';
import '../platform/notifications_plugin.dart';
import '../platform/permissions.dart';
import '../platform/share_plugin.dart';
import '../platform/system_settings.dart';
import 'font_licences.dart';
import 'smoke_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();

  // N15.13 — load settings once, synchronously readable from the first frame.
  // A build with no stored blob starts `fresh` so the first-run wizard runs
  // (the mock default `paired` is only for the UX lab).
  final prefs = await JsonPrefsRepository.load(
    await SharedPrefsKeyValueStore.open(),
    initial: AppSettings.defaults.copyWith(onboardStatus: OnboardStatus.fresh),
  );

  // N15.9 — the on-device cook cache.
  final database = await openAppDatabase();
  final cache = DriftSampleCache(database);

  // N15.15–N15.22 — the composition root owns the plugin implementations. The
  // default (mock / UX-lab) build keeps the pure fakes so no channel is touched;
  // a `REAL_BRIDGE=true` build installs the platform plumbing and starts the
  // background cook monitor.
  final systemSettings = SystemSettings();
  final permissions = AppPermissions.production(
    androidSdkInt: await systemSettings.androidSdkInt(),
  );
  final networkBinder = ChannelNetworkBinder();
  final notificationSink = kRealBridgeEnabled
      ? PluginNotificationSink()
      : RecordingNotificationSink();
  final foregroundService = kRealBridgeEnabled
      ? PluginForegroundServiceHost()
      : FakeForegroundServiceHost();

  final DevDeepLink link = DevDeepLink.parse(
    kReleaseMode ? '' : Uri.base.toString(),
  );
  final container = ProviderContainer(
    overrides: [
      initialDevDeepLinkProvider.overrideWithValue(link),
      prefsProvider.overrideWith((ref) {
        ref.onDispose(prefs.dispose);
        return prefs;
      }),
      sampleCacheProvider.overrideWith((ref) {
        ref.onDispose(() => unawaited(database.close()));
        return cache;
      }),
      notificationSinkProvider.overrideWithValue(notificationSink),
      foregroundServiceProvider.overrideWithValue(foregroundService),
      permissionsProvider.overrideWithValue(permissions),
      systemSettingsProvider.overrideWithValue(systemSettings),
      networkBinderProvider.overrideWithValue(networkBinder),
      shareSheetProvider.overrideWithValue(const PluginShareSheet()),
    ],
  );
  unawaited(applyDevDeepLink(container, link));

  // N15.17 — the monitor watches the repository the container already built.
  // Started only for a real bridge: over the mock it would post fixture alarms.
  if (kRealBridgeEnabled) {
    final monitor = CookMonitor(
      repository: container.read(bridgeRepositoryProvider),
      sink: notificationSink,
      service: foregroundService,
      settings: MonitorSettings(
        monitoringEnabled: prefs.current.monitoring,
        quiet: QuietHours(enabled: prefs.current.quietHours),
        preferManualAlarm: prefs.current.preferManualAlarm,
      ),
    );
    unawaited(monitor.start());
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const SmokeApp()),
  );
}
