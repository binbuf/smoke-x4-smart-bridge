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

import '../data/dev_panel.dart';
import '../data/local/drift_sample_cache.dart';
import '../data/local/open_database.dart';
import '../data/model/app_settings.dart';
import '../data/providers.dart';
import '../data/repository/real_prefs_repository.dart';
import '../data/repository/shared_prefs_store.dart';
import '../features/dev/dev_boot.dart';
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
    ],
  );
  unawaited(applyDevDeepLink(container, link));

  runApp(
    UncontrolledProviderScope(container: container, child: const SmokeApp()),
  );
}
