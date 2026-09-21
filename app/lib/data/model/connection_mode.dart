/// N2.22 — the three connection modes and their capability flags.
library;

/// Which features a transport can carry. Plain-language copy accompanies each
/// flag in the modes reference sheet.
class ModeCapability {
  const ModeCapability({
    required this.live,
    required this.preview,
    required this.fullHistory,
    required this.config,
    required this.rules,
    required this.ota,
  });

  final bool live;
  final bool preview;
  final bool fullHistory;
  final bool config;
  final bool rules;
  final bool ota;
}

/// One transport mode (`ble` / `ap` / `sta`).
class ConnectionMode {
  const ConnectionMode({
    required this.id,
    required this.icon,
    required this.name,
    required this.tagline,
    required this.summary,
    required this.good,
    required this.limited,
    required this.capability,
    required this.requiresWifiCreds,
  });

  final String id;
  final String icon;
  final String name;
  final String tagline;
  final String summary;

  /// The plain-language "what works" list.
  final List<String> good;

  /// The plain-language "what is limited" list — never hidden.
  final List<String> limited;

  final ModeCapability capability;

  /// Whether joining this mode needs an SSID + password.
  final bool requiresWifiCreds;
}
