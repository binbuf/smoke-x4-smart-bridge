/// N2.32 — boot-time deep-link application.
///
/// The prototype reads `?screen=` / `?overlay=` / `?scenario=` / `?units=` from
/// `location` before its first render (`app.js` §9 boot). This is the Flutter
/// equivalent of that step: [DevDeepLink] already parses the values (N2.32's
/// tested control layer), and [applyDevDeepLink] pushes `scenario` / `units`
/// into the boot repositories.
///
/// The `screen` / `overlay` half is a shell concern: `bootstrap.dart` stashes
/// the parsed link in `initialDevDeepLinkProvider`, and N4's router reads it
/// once the destinations exist. This file never navigates.
///
/// Release is a no-op — the panel and its deep links do not exist there.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/providers.dart';

/// Applies the `scenario` / `units` half of a parsed boot [link].
///
/// A no-op in release or when [link] is empty. Returns [link] for convenience.
Future<DevDeepLink> applyDevDeepLink(
  ProviderContainer container,
  DevDeepLink link,
) async {
  if (kReleaseMode || link.isEmpty) {
    return link;
  }
  final controller = DevPanelController(
    repository: container.read(bridgeRepositoryProvider),
    prefs: container.read(prefsProvider),
  );
  await controller.apply(link);
  return link;
}
