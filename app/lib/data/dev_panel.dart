/// N2.31 / N2.32 — the dev-panel control layer and deep links.
///
/// The prototype's right-hand panel (scenario / screen / overlay / event) and
/// its `?screen=` / `?overlay=` / `?scenario=` / `?units=` boot parameters,
/// expressed as **pure Dart** so they are testable and so the N4 shell can
/// render the actual widget without duplicating any logic.
///
/// Nothing here is a screen. `DevScreen` / `DevOverlay` are names the shell
/// routes on; `DevPanelController` mutates the repository and preferences and
/// reports the requested surface through callbacks. The panel widget must be
/// compiled out of release (`kReleaseMode`), which the shell owns.
library;

import '../domain/domain.dart';
import 'model/bridge_snapshot.dart';
import 'model/mock_event.dart';
import 'repository/bridge_repository.dart';
import 'repository/prefs_repository.dart';

/// The five destinations plus History (inside Settings).
enum DevScreen { live, temps, timeline, graph, settings, history }

/// Every overlay the prototype can open (NOTES §2).
enum DevOverlay {
  onboarding,
  setup,
  connect,
  modes,
  modesRef,
  provisionSta,
  provisionAp,
  alarms,
  alarmDetail,
  mark,
  probe,
  adopt,
  editStart,
  confirm,
  customFood,
  firmware,
  firmwareUpdate,
  diagnostics,
  verb,
}

/// A parsed deep link. Every field is optional; unknown values are dropped
/// rather than throwing, because a bad deep link must not crash the app.
class DevDeepLink {
  const DevDeepLink({
    this.screen,
    this.overlay,
    this.scenario,
    this.units,
    this.props = const {},
  });

  final DevScreen? screen;
  final DevOverlay? overlay;
  final String? scenario;
  final TempUnit? units;

  /// Extra overlay props (`id`, `jack`, …), as strings.
  final Map<String, String> props;

  static const DevDeepLink none = DevDeepLink();

  bool get isEmpty =>
      screen == null &&
      overlay == null &&
      scenario == null &&
      units == null &&
      props.isEmpty;

  /// Parses a URL, a route (`/live?units=C`) or a bare fragment
  /// (`#screen=graph`). Query and fragment parameters are merged.
  factory DevDeepLink.parse(String location) {
    if (location.trim().isEmpty) {
      return none;
    }
    Uri uri;
    try {
      uri = Uri.parse(location);
    } on FormatException {
      return none;
    }
    final params = <String, String>{};
    params.addAll(uri.queryParameters);
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final query = fragment.contains('?')
          ? fragment.substring(fragment.indexOf('?') + 1)
          : fragment;
      try {
        params.addAll(Uri.splitQueryString(query));
      } on FormatException {
        // A malformed fragment contributes nothing.
      }
    }

    final screen = _screenByName(params['screen']);
    final overlay = _overlayByName(params['overlay']);
    final units = switch (params['units']?.toUpperCase()) {
      'C' => TempUnit.celsius,
      'F' => TempUnit.fahrenheit,
      _ => null,
    };
    final scenario = params['scenario'];
    final props = <String, String>{
      for (final entry in params.entries)
        if (!const {
          'screen',
          'overlay',
          'units',
          'scenario',
        }.contains(entry.key))
          entry.key: entry.value,
    };
    return DevDeepLink(
      screen: screen,
      overlay: overlay,
      scenario: scenario,
      units: units,
      props: props,
    );
  }

  static DevScreen? _screenByName(String? name) {
    if (name == null) {
      return null;
    }
    for (final s in DevScreen.values) {
      if (s.name == name) {
        return s;
      }
    }
    return null;
  }

  static DevOverlay? _overlayByName(String? name) {
    if (name == null) {
      return null;
    }
    for (final o in DevOverlay.values) {
      if (o.name == name) {
        return o;
      }
    }
    return null;
  }
}

/// Drives the dev panel: scenario and event switching, units, and deep links.
///
/// The shell passes [onScreen] / [onOverlay]; this class never navigates.
class DevPanelController {
  DevPanelController({
    required this.repository,
    required this.prefs,
    this.onScreen,
    this.onOverlay,
  });

  final BridgeRepository repository;
  final PrefsRepository prefs;

  /// Called when a deep link (or the panel) asks for a destination.
  final void Function(DevScreen screen)? onScreen;

  /// Called when a deep link (or the panel) asks for an overlay.
  final void Function(DevOverlay overlay, Map<String, String> props)? onOverlay;

  List<Scenario> get scenarios => repository.scenarios;

  List<MockEventSpec> get events => repository.mockEvents;

  String get activeScenarioKey => repository.activeScenarioKey;

  /// Switch the live fixture.
  Future<void> applyScenario(String key) => repository.selectScenario(key);

  /// Fire a mock event.
  Future<void> fireEvent(String eventId) => repository.fireEvent(eventId);

  /// Switch the display unit (storage stays canonical °F).
  Future<void> setUnits(TempUnit units) =>
      prefs.update((s) => s.copyWith(units: units));

  /// Apply a parsed deep link: data first, then the requested surface.
  Future<void> apply(DevDeepLink link) async {
    if (link.scenario != null) {
      await applyScenario(link.scenario!);
    }
    if (link.units != null) {
      await setUnits(link.units!);
    }
    if (link.screen != null) {
      onScreen?.call(link.screen!);
    }
    if (link.overlay != null) {
      onOverlay?.call(link.overlay!, link.props);
    }
  }

  /// Convenience for boot: parse then apply.
  Future<void> applyLocation(String location) =>
      apply(DevDeepLink.parse(location));
}
