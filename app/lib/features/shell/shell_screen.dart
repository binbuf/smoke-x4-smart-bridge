/// N4.2/N4.3 — the shell's screen model.
///
/// The shell renders one of seven surfaces: the five bottom-nav destinations
/// plus `history` (inside Settings) and `cookDetail` (inside History). The
/// prototype's `go()` and its `state.screen` string map onto [ShellScreen]; the
/// router translates between this enum and URLs.
///
/// The dev panel's [DevScreen] has no `cookDetail`, so the two enums are
/// deliberately separate: [DevScreen] is the dev-control vocabulary, this is
/// the navigation vocabulary.
library;

import '../../data/dev_panel.dart';

/// Every surface the shell can show.
enum ShellScreen { live, temps, timeline, graph, settings, history, cookDetail }

extension ShellScreenX on ShellScreen {
  /// The canonical route for this surface.
  String get path => switch (this) {
    ShellScreen.live => '/live',
    ShellScreen.temps => '/temps',
    ShellScreen.timeline => '/timeline',
    ShellScreen.graph => '/graph',
    ShellScreen.settings => '/settings',
    ShellScreen.history => '/settings/history',
    ShellScreen.cookDetail => '/settings/history/detail',
  };

  /// The bottom-nav destination this surface highlights.
  ShellScreen get navDestination => switch (this) {
    ShellScreen.history || ShellScreen.cookDetail => ShellScreen.settings,
    _ => this,
  };

  /// The app-bar title (the prototype's `.ab-title`).
  String get title => switch (this) {
    ShellScreen.live => 'Live',
    ShellScreen.temps => 'Temperatures',
    ShellScreen.timeline => 'Timeline',
    ShellScreen.graph => 'Graph',
    ShellScreen.settings => 'Settings',
    ShellScreen.history => 'History',
    ShellScreen.cookDetail => 'Cook detail',
  };

  /// The app-bar subtitle (`.ab-sub`), or null when the variant has none.
  String? get subtitle => switch (this) {
    ShellScreen.temps => 'Every probe, up close',
    ShellScreen.timeline => 'Expected & actual',
    ShellScreen.graph => 'All probes',
    ShellScreen.settings => 'Connection & preferences',
    ShellScreen.history => 'Past cooks',
    _ => null,
  };

  /// Whether the app bar shows a back chevron.
  bool get hasBack =>
      this == ShellScreen.history || this == ShellScreen.cookDetail;

  /// Whether the app bar shows the "start a cook" plus (History only).
  bool get hasPlus => this == ShellScreen.history;

  /// The dev-panel name, when one exists.
  DevScreen? get devScreen => switch (this) {
    ShellScreen.live => DevScreen.live,
    ShellScreen.temps => DevScreen.temps,
    ShellScreen.timeline => DevScreen.timeline,
    ShellScreen.graph => DevScreen.graph,
    ShellScreen.settings => DevScreen.settings,
    ShellScreen.history => DevScreen.history,
    ShellScreen.cookDetail => null,
  };
}

/// The route a dev-panel screen button asks for.
String pathForDevScreen(DevScreen screen) => switch (screen) {
  DevScreen.live => ShellScreen.live.path,
  DevScreen.temps => ShellScreen.temps.path,
  DevScreen.timeline => ShellScreen.timeline.path,
  DevScreen.graph => ShellScreen.graph.path,
  DevScreen.settings => ShellScreen.settings.path,
  DevScreen.history => ShellScreen.history.path,
};

/// Resolves a location (path + optional query) to a [ShellScreen].
///
/// Unknown paths fall back to Live, matching the prototype's
/// `map[state.screen] || viewLive`.
ShellScreen screenFromPath(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path == ShellScreen.temps.path) {
    return ShellScreen.temps;
  }
  if (path == ShellScreen.timeline.path) {
    return ShellScreen.timeline;
  }
  if (path == ShellScreen.graph.path) {
    return ShellScreen.graph;
  }
  if (path.startsWith('${ShellScreen.history.path}/')) {
    return ShellScreen.cookDetail;
  }
  if (path == ShellScreen.history.path) {
    return ShellScreen.history;
  }
  if (path == ShellScreen.settings.path || path.startsWith('/settings')) {
    return ShellScreen.settings;
  }
  return ShellScreen.live;
}
