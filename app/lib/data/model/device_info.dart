/// N2.24 — device identity, diagnostics and firmware fixtures.
library;

/// The OTA release channel.
enum DeviceChannel { stable, beta }

/// One line in the diagnostics log.
class DeviceLog {
  const DeviceLog({required this.t, required this.level, required this.text});

  final String t;
  final String level;
  final String text;
}

/// Flash usage and retention.
class DeviceStorage {
  const DeviceStorage({
    required this.usedKb,
    required this.totalKb,
    required this.sessions,
    required this.days,
  });

  final int usedKb;
  final int totalKb;
  final int sessions;
  final int days;
}

/// Device identity + diagnostics.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.hardware,
    required this.version,
    required this.versionDate,
    required this.bootloader,
    required this.channel,
    this.available,
    required this.uptimeMin,
    required this.heapKb,
    required this.storage,
    this.lastCrash,
    this.logs = const [],
  });

  final String id;
  final String hardware;
  final String version;
  final String versionDate;
  final String bootloader;
  final DeviceChannel channel;

  /// The version "Check for updates" found, or null when up to date.
  final String? available;

  final int uptimeMin;
  final int heapKb;
  final DeviceStorage storage;
  final String? lastCrash;
  final List<DeviceLog> logs;

  DeviceInfo copyWith({
    String? version,
    Object? available = _sentinel,
    Object? lastCrash = _sentinel,
    DeviceChannel? channel,
  }) => DeviceInfo(
    id: id,
    hardware: hardware,
    version: version ?? this.version,
    versionDate: versionDate,
    bootloader: bootloader,
    channel: channel ?? this.channel,
    available: available == _sentinel ? this.available : available as String?,
    uptimeMin: uptimeMin,
    heapKb: heapKb,
    storage: storage,
    lastCrash: lastCrash == _sentinel ? this.lastCrash : lastCrash as String?,
    logs: logs,
  );
}

const Object _sentinel = Object();

/// The available firmware image and its release notes.
class FirmwareInfo {
  const FirmwareInfo({
    required this.latest,
    required this.latestDate,
    required this.sizeKb,
    required this.notes,
    required this.rollback,
  });

  final String latest;
  final String latestDate;
  final int sizeKb;
  final List<String> notes;

  /// The auto-rollback promise — Wi-Fi only, session guard, 120 s health gate.
  final String rollback;
}
