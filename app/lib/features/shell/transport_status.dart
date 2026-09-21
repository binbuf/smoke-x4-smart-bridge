/// N4.4/N4.5 — the dual-link transport status the app bar shows.
///
/// Maps the data layer's [ConnectionState] onto the design system's
/// [TransportChip] axes. This is the prototype's `linkInfo()`, kept out of the
/// app-bar widget so both the bar and later screens (N10) read one projection.
library;

import '../../data/model/connection_state.dart';
import '../../design/status.dart';

/// The app-bar chip's inputs, derived from a [ConnectionState].
class TransportStatus {
  const TransportStatus({
    required this.label,
    required this.phase,
    required this.primary,
    required this.btConnected,
    required this.wifiConnected,
    required this.wifiAp,
  });

  final String label;
  final TransportPhase phase;
  final TransportPrimary primary;
  final bool btConnected;
  final bool wifiConnected;
  final bool wifiAp;

  /// The state shown before the first snapshot arrives.
  static const TransportStatus unknown = TransportStatus(
    label: 'Offline',
    phase: TransportPhase.offline,
    primary: TransportPrimary.none,
    btConnected: false,
    wifiConnected: false,
    wifiAp: false,
  );

  factory TransportStatus.from(ConnectionState connection) {
    final primary = switch (connection.primary) {
      LinkPrimary.bt => TransportPrimary.bt,
      LinkPrimary.wifi => TransportPrimary.wifi,
      null => TransportPrimary.none,
    };
    final (TransportPhase phase, String label) = switch (connection.phase) {
      ConnectionPhase.offline => (TransportPhase.offline, 'Offline'),
      ConnectionPhase.connecting => (TransportPhase.connecting, 'Connecting…'),
      ConnectionPhase.provisioning => (TransportPhase.provisioning, 'Hotspot'),
      ConnectionPhase.rollback => (TransportPhase.rollback, 'Bluetooth'),
      // The prototype has no `error` glyph; the chip shows the warning tint and
      // names the problem so it is never a silent red.
      ConnectionPhase.error => (TransportPhase.connecting, 'Error'),
      ConnectionPhase.connected => switch (connection.primary) {
        LinkPrimary.bt => (TransportPhase.connected, 'Bluetooth'),
        LinkPrimary.wifi => (
          TransportPhase.connected,
          connection.wifi.mode == WifiMode.ap ? 'Bridge Wi-Fi' : 'Home Wi-Fi',
        ),
        null => (TransportPhase.offline, 'Offline'),
      },
    };

    return TransportStatus(
      label: label,
      phase: phase,
      primary: primary,
      btConnected: connection.bt.connected,
      wifiConnected: connection.wifi.connected,
      wifiAp: connection.wifi.mode == WifiMode.ap,
    );
  }
}
