/// N0.7 — app bootstrap: bindings, bundled-font licences, and the
/// `ProviderScope` every later provider hangs off.
///
/// N2.32 adds the boot deep link: `?scenario=` / `?units=` are applied to the
/// repositories before the first frame, and the parsed link is exposed to the
/// shell through `initialDevDeepLinkProvider` for the N4 router to consume.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dev_panel.dart';
import '../data/providers.dart';
import '../features/dev/dev_boot.dart';
import 'font_licences.dart';
import 'smoke_app.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();

  final DevDeepLink link = DevDeepLink.parse(
    kReleaseMode ? '' : Uri.base.toString(),
  );
  final container = ProviderContainer(
    overrides: [initialDevDeepLinkProvider.overrideWithValue(link)],
  );
  unawaited(applyDevDeepLink(container, link));

  runApp(
    UncontrolledProviderScope(container: container, child: const SmokeApp()),
  );
}
