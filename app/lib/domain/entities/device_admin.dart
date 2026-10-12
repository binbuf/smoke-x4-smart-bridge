/// Device administration the app drives over BLE (v1.2): the telemetry snapshot
/// (`device_stats`) and the writable settings read back from `device_config`.
///
/// The bridge has no controls of its own, so these are the values its OLED
/// System/Radio pages once showed and its config once owned alone. Pure Dart —
/// the transport maps the wire codecs to these.
library;

/// A probe's role, as the user assigns it. Distinct from the wire `probe_role`
/// order (see the transport); this is the app's vocabulary.
enum ProbeRole {
  pit('Pit'),
  food('Food'),
  ambient('Ambient'),
  unused('Unused');

  const ProbeRole(this.label);
  final String label;
}

/// One probe's editable settings (`set_probe`).
class ProbeConfig {
  const ProbeConfig({
    required this.index,
    required this.name,
    required this.role,
    required this.targetF10,
  });

  /// 0..3 (jack 1..4).
  final int index;
  final String name;
  final ProbeRole role;

  /// Tenths of °F; 0 = no target.
  final int targetF10;
}

/// The writable device preferences (`set_device_prefs`).
class DevicePrefs {
  const DevicePrefs({
    required this.displayTimeoutS,
    required this.ledEnabled,
    required this.buzzerEnabled,
    required this.retentionMaxSessions,
    required this.retentionMinFreePct,
  });

  /// 0 = never sleep.
  final int displayTimeoutS;
  final bool ledEnabled;
  final bool buzzerEnabled;
  final int retentionMaxSessions;
  final int retentionMinFreePct;
}

/// The full writable settings read back from `device_config`.
class DeviceConfig {
  const DeviceConfig({required this.prefs, required this.probes});

  final DevicePrefs prefs;

  /// Exactly four, index 0..3.
  final List<ProbeConfig> probes;
}

/// The read-only telemetry snapshot (`device_stats`).
class DeviceStats {
  const DeviceStats({
    required this.paired,
    required this.clockValid,
    required this.advertising,
    required this.connected,
    required this.uptimeS,
    required this.heapFreeB,
    required this.heapMinB,
    required this.storageUsedB,
    required this.storageTotalB,
    required this.storedSessions,
    required this.loraFreqHz,
    required this.loraRssi,
    required this.loraSnr,
    required this.packetsOk,
    required this.packetsBad,
    required this.bonds,
  });

  final bool paired;
  final bool clockValid;
  final bool advertising;
  final bool connected;
  final int uptimeS;
  final int heapFreeB;
  final int heapMinB;
  final int storageUsedB;
  final int storageTotalB;
  final int storedSessions;
  final int loraFreqHz;
  final int loraRssi;
  final int loraSnr;
  final int packetsOk;
  final int packetsBad;
  final int bonds;
}
