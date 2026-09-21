/// N10 — the pure projections behind the connection surfaces.
///
/// Everything here is a plain function over the N2 models: no widget, no
/// provider, no repository. The connect sheet, the mode cards, the reference
/// table, the provisioning flows and the Settings bridge card all read one
/// projection, so a deep link and a tap can never describe the link
/// differently.
///
/// Invariants encoded here:
/// * **I9** — one transport carries data at a time; [activeModeId] is the one
///   answer, derived from `primary` plus the Wi-Fi mode.
/// * **I13** — a capability that is missing gets copy, not an error. Every
///   [ModeFeature] carries its own [featureReason] ("Full history needs
///   Wi-Fi"), which a disabled control states inline.
/// * **N10.13** — the two hops are never conflated: the phone→bridge signal and
///   the bridge→router signal live on their own link rows and are named.
library;

import '../../data/model/connection_mode.dart';
import '../../data/model/connection_state.dart';

/// The prototype's `signalWord`: bars → a plain word, never a number alone.
String signalWord(int? bars) {
  if (bars == null) {
    return 'no signal';
  }
  const words = <String>['none', 'weak', 'fair', 'good', 'strong'];
  if (bars < 0 || bars >= words.length) {
    return 'good';
  }
  return words[bars];
}

/// The prototype's `ago()`, from a "seconds since" value.
String? agoLabel(int? seconds) {
  if (seconds == null) {
    return null;
  }
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) {
    return '${s}s ago';
  }
  final m = (s / 60).round();
  return m < 60 ? '${m}m ago' : '${(m / 60).round()}h ago';
}

/// Which transport is carrying data, as a mode id (`ble` / `ap` / `sta`).
///
/// The prototype reads `c.mode`, which its fixtures never set, so its mode card
/// never highlights. This derives the same answer from the link model instead:
/// `primary` first, then the Wi-Fi mode.
String? activeModeId(ConnectionState c) {
  if (c.primary == LinkPrimary.bt) {
    return 'ble';
  }
  if (c.primary == LinkPrimary.wifi) {
    return c.wifi.mode == WifiMode.ap ? 'ap' : 'sta';
  }
  return null;
}

/// The [ConnectionMode] currently carrying data, or null when nothing is.
ConnectionMode? activeMode(ConnectionState c, List<ConnectionMode> modes) {
  final id = activeModeId(c);
  for (final mode in modes) {
    if (mode.id == id) {
      return mode;
    }
  }
  return null;
}

/// The one-word state on a mode card (`modeCardCompact`).
String modeStateWord(ConnectionMode mode, {required bool active}) {
  if (active) {
    return 'Active';
  }
  return mode.requiresWifiCreds ? 'Needs password' : 'Available';
}

/// The Wi-Fi link's plain label (`viewSettings`).
String wifiModeLabel(ConnectionState c) {
  final wifi = c.wifi;
  return switch (wifi.mode) {
    WifiMode.ap => 'Bridge hotspot',
    WifiMode.sta => wifi.ssid ?? 'Home Wi-Fi',
    WifiMode.off || null => 'Off',
  };
}

/// The Bluetooth row's sub line in the connect sheet.
String bluetoothSubtitle(LinkState bt) {
  if (!bt.connected) {
    return 'Not connected';
  }
  final parts = <String>[
    signalWord(bt.bars),
    if (bt.lastSyncS != null) agoLabel(bt.lastSyncS)!,
  ];
  return parts.join(' · ');
}

/// The Bluetooth row's sub line in Settings — the phone→bridge hop, named.
String bridgeBluetoothSubtitle(LinkState bt) {
  if (!bt.connected) {
    return 'Not connected';
  }
  final parts = <String>[
    'Phone → bridge',
    signalWord(bt.bars),
    if (bt.rssi != null) '${bt.rssi} dBm',
    if (bt.lastSyncS != null) agoLabel(bt.lastSyncS)!,
  ];
  return parts.join(' · ');
}

/// The Wi-Fi row's sub line in the connect sheet.
String wifiSubtitle(ConnectionState c) {
  final wifi = c.wifi;
  if (wifi.mode == WifiMode.off || wifi.mode == null) {
    return 'Not set up';
  }
  if (wifi.connected) {
    final name = wifi.mode == WifiMode.ap
        ? 'Bridge hotspot'
        : (wifi.ssid ?? '');
    final parts = <String>[
      name,
      signalWord(wifi.bars),
      if (wifi.lastSyncS != null) agoLabel(wifi.lastSyncS)!,
    ];
    return parts.join(' · ');
  }
  if (c.phase == ConnectionPhase.connecting) {
    return 'Connecting to ${wifi.ssid ?? ''}…';
  }
  return 'Not connected';
}

/// The Wi-Fi row's sub line in Settings — the bridge→router hop, named.
String bridgeWifiSubtitle(ConnectionState c) {
  final wifi = c.wifi;
  if (wifi.mode == WifiMode.off || wifi.mode == null) {
    return 'Not set up';
  }
  if (wifi.connected) {
    final hop = wifi.mode == WifiMode.ap
        ? 'Phone → bridge (hotspot)'
        : 'Bridge → router';
    final parts = <String>[
      hop,
      wifiModeLabel(c),
      if (wifi.ip != null) wifi.ip!,
      signalWord(wifi.bars),
      if (wifi.lastSyncS != null) agoLabel(wifi.lastSyncS)!,
    ];
    return parts.join(' · ');
  }
  if (c.phase == ConnectionPhase.connecting) {
    return 'Connecting to ${wifi.ssid ?? ''}…';
  }
  return 'Not connected';
}

/// The named provisioning errors (N10.11).
enum ConnectionError { wrongPassword, routerUnreachable, switchFailed, unknown }

/// Maps the wire's error string onto a named state.
ConnectionError connectionErrorOf(String? error) => switch (error) {
  'wrong_password' => ConnectionError.wrongPassword,
  'router_unreachable' => ConnectionError.routerUnreachable,
  'switch_failed' => ConnectionError.switchFailed,
  _ => ConnectionError.unknown,
};

/// Whether the connection is showing an error or a rollback.
bool connectionHasProblem(ConnectionState c) =>
    c.phase == ConnectionPhase.error || c.phase == ConnectionPhase.rollback;

/// The error/rollback copy, one sentence per named state (N10.3, N10.11).
String connectionErrorCopy(ConnectionState c, {String? notice}) =>
    switch (connectionErrorOf(c.error)) {
      ConnectionError.wrongPassword =>
        'That Wi-Fi password was rejected. The bridge kept Bluetooth so '
            'nothing is lost.',
      ConnectionError.routerUnreachable =>
        'The bridge could not reach the router. Check the network name and '
            'that the router is on.',
      ConnectionError.switchFailed =>
        notice ??
            'The last change did not stick. The bridge kept its previous link.',
      ConnectionError.unknown =>
        notice ??
            'The last change did not stick. The bridge kept its previous link.',
    };

/// Whether the notice is a warning (rollback) rather than a failure.
bool connectionProblemIsWarning(ConnectionState c) =>
    c.phase == ConnectionPhase.rollback;

/// A capability a mode may or may not carry (I13, N10.5).
enum ModeFeature { live, preview, fullHistory, config, rules, ota }

/// The row label for a capability.
String featureLabel(ModeFeature feature) => switch (feature) {
  ModeFeature.live => 'Live readings',
  ModeFeature.preview => '2-hour preview',
  ModeFeature.fullHistory => 'Full history download',
  ModeFeature.config => 'Setup & mode changes',
  ModeFeature.rules => 'Alarm-rule editing',
  ModeFeature.ota => 'Firmware update',
};

/// The copy-over-error for a missing capability (I13).
String featureReason(ModeFeature feature) => switch (feature) {
  ModeFeature.live => 'Live readings need a link.',
  ModeFeature.preview => 'The preview needs a link.',
  ModeFeature.fullHistory => 'Full history needs Wi-Fi.',
  ModeFeature.config => 'Changes need a link.',
  ModeFeature.rules => 'Alarm-rule editing needs Wi-Fi.',
  ModeFeature.ota => 'Firmware updates need Wi-Fi.',
};

/// Whether [mode] carries [feature].
bool featureAvailable(ConnectionMode mode, ModeFeature feature) =>
    switch (feature) {
      ModeFeature.live => mode.capability.live,
      ModeFeature.preview => mode.capability.preview,
      ModeFeature.fullHistory => mode.capability.fullHistory,
      ModeFeature.config => mode.capability.config,
      ModeFeature.rules => mode.capability.rules,
      ModeFeature.ota => mode.capability.ota,
    };

/// One capability-matrix row (N10.5).
class CapabilityRow {
  const CapabilityRow(this.feature, {required this.ok});

  final ModeFeature feature;
  final bool ok;

  String get label => featureLabel(feature);

  /// The reason copy when the capability is missing (I13).
  String? get reason => ok ? null : featureReason(feature);
}

/// The capability matrix for [mode], in the prototype's order.
List<CapabilityRow> capabilityRows(ConnectionMode mode) => <CapabilityRow>[
  for (final feature in ModeFeature.values)
    CapabilityRow(feature, ok: featureAvailable(mode, feature)),
];

/// The "copy over error" a capability gate shows (I13).
///
/// Null when the current mode carries full history (or nothing is carrying
/// data, in which case the app has no basis to gate anything).
String? fullHistoryRefusal(ConnectionState c, List<ConnectionMode> modes) {
  final mode = activeMode(c, modes);
  if (mode == null || mode.capability.fullHistory) {
    return null;
  }
  return featureReason(ModeFeature.fullHistory);
}

/// The scanned networks the STA flow offers (`overlayProvisionSta`).
const List<({String ssid, int bars})> kScannedNetworks =
    <({String ssid, int bars})>[
      (ssid: 'HomeNet-5G', bars: 4),
      (ssid: 'HomeNet-2.4G', bars: 3),
      (ssid: 'Backyard-AP', bars: 2),
    ];

/// The default AP SSID/passkey when the bridge is not yet broadcasting.
const String kHotspotSsid = 'SmokeBridge-A4F2';
const String kHotspotPasskey = 'smoke-4471';
