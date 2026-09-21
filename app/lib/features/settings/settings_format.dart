/// N13 — the pure projections behind the Settings tree, firmware/OTA,
/// diagnostics and the device verbs.
///
/// Everything here is a plain function over the N2 models: no widget, no
/// provider, no repository. Keeping it here lets the prototype's exact copy
/// (`app.js` `viewSettings`, `overlayFirmware`, `overlayFirmwareUpdate`,
/// `overlayDiagnostics`, `VERBS`) be unit-tested without a binding.
///
/// Invariants this file holds:
///  * **I5** — a gated action states its reason, never a dead control.
///  * **I8** — a destructive verb states what it keeps and what it loses.
///  * **OTA** — image is Wi-Fi-only, a recording session is a 409 conflict
///    unless explicitly forced, and a failed 120 s health gate auto-rolls back.
library;

import '../../data/model/app_settings.dart';
import '../../data/model/connection_state.dart';
import '../../data/model/device_info.dart';
import '../../data/repository/bridge_repository.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';

// ── device verbs (N13.19–N13.22) ─────────────────────────────────────────

/// One device verb's cost-sheet and progress-sheet copy, from `app.js` VERBS
/// and the `ask-*` confirm bodies.
class VerbSpec {
  const VerbSpec({
    required this.verb,
    required this.id,
    required this.title,
    required this.sub,
    required this.confirmTitle,
    required this.confirmLabel,
    required this.danger,
    required this.message,
    required this.keeps,
    required this.loses,
    required this.steps,
  });

  final DeviceVerb verb;

  /// The prop value a `?overlay=verb&kind=<id>` carries.
  final String id;

  /// The progress-sheet title (`Restarting the bridge`).
  final String title;

  /// The progress-sheet sub (`Settings and the recording are kept.`).
  final String sub;

  /// The cost-sheet title (`Restart the bridge?`).
  final String confirmTitle;

  final String confirmLabel;

  /// Paints the confirm action in the critical hue.
  final bool danger;

  /// The cost-sheet body (what happens, in plain words).
  final String message;

  /// What survives the verb (I8).
  final List<String> keeps;

  /// What the verb destroys (I8).
  final List<String> loses;

  /// The named steps the progress sheet completes one by one (I7).
  final List<String> steps;
}

/// The four verbs, prototype-exact (`app.js` VERBS + `ask-*`).
const List<VerbSpec> kVerbSpecs = <VerbSpec>[
  VerbSpec(
    verb: DeviceVerb.restart,
    id: 'restart',
    title: 'Restarting the bridge',
    sub: 'Settings and the recording are kept.',
    confirmTitle: 'Restart the bridge?',
    confirmLabel: 'Restart',
    danger: false,
    message:
        'Recording pauses for about 30 seconds. The bridge keeps its settings '
        'and the current cook is not lost.',
    keeps: <String>['Settings', 'The current cook', 'Recorded sessions'],
    loses: <String>[],
    steps: <String>[
      'Stopping recording cleanly',
      'Draining the sample buffer',
      'Rebooting',
      'LoRa re-sync',
      'Reconnecting',
    ],
  ),
  VerbSpec(
    verb: DeviceVerb.forget,
    id: 'forget',
    title: 'Forgetting this bridge',
    sub: 'Pairing and Wi-Fi are removed from this app only.',
    confirmTitle: 'Forget this bridge?',
    confirmLabel: 'Forget',
    danger: true,
    message:
        'Removes the pairing and saved Wi-Fi from this app. The bridge keeps '
        'recording and keeps its own data. You will need its passkey to pair '
        'again.',
    keeps: <String>['The bridge\'s own data', 'Recording on the bridge'],
    loses: <String>['The pairing on this phone', 'Saved Wi-Fi in this app'],
    steps: <String>[
      'Dropping the Bluetooth bond',
      'Clearing saved Wi-Fi from the app',
      'Stopping background monitoring',
    ],
  ),
  VerbSpec(
    verb: DeviceVerb.factoryReset,
    id: 'factory',
    title: 'Factory resetting',
    sub: 'Everything on the bridge is being erased.',
    confirmTitle: 'Factory reset the bridge?',
    confirmLabel: 'Factory reset',
    danger: true,
    message:
        'Everything on the bridge is erased — Wi-Fi, alarm rules and all '
        'recorded cook sessions. This cannot be undone. The bridge reboots '
        'into setup mode.',
    keeps: <String>[],
    loses: <String>[
      'Wi-Fi and alarm rules',
      'All recorded sessions',
      'Every setting',
    ],
    steps: <String>[
      'Stopping recording',
      'Erasing recorded sessions',
      'Clearing Wi-Fi and alarm rules',
      'Restoring defaults',
      'Rebooting to setup mode',
    ],
  ),
  VerbSpec(
    verb: DeviceVerb.ota,
    id: 'ota',
    title: 'Installing firmware',
    sub: 'Do not power off the bridge.',
    confirmTitle: 'Install this firmware?',
    confirmLabel: 'Install',
    danger: false,
    message:
        'The bridge verifies the image, streams it over Wi-Fi, writes the '
        'inactive slot and reboots. Do not power it off during the update.',
    keeps: <String>['Settings', 'Recorded sessions'],
    loses: <String>['Nothing — the old slot stays until the health check'],
    steps: <String>[
      'Verifying the image',
      'Streaming over Wi-Fi',
      'Writing the inactive slot',
      'Rebooting into the new slot',
      'Health check',
    ],
  ),
];

/// The spec for [verb].
VerbSpec verbSpec(DeviceVerb verb) =>
    kVerbSpecs.firstWhere((spec) => spec.verb == verb);

/// Resolves the `kind` prop (`restart` / `forget` / `factory` / `ota`).
DeviceVerb? verbFromId(String? id) {
  for (final spec in kVerbSpecs) {
    if (spec.id == id) {
      return spec.verb;
    }
  }
  return null;
}

/// The `kind` prop for [verb].
String verbId(DeviceVerb verb) => verbSpec(verb).id;

// ── firmware & OTA (N13.9–N13.14) ────────────────────────────────────────

/// The OTA transport and session guard (`overlayFirmwareUpdate`).
class OtaGuard {
  const OtaGuard({
    required this.wifiOk,
    required this.recording,
    required this.forced,
  });

  /// The bridge is on Wi-Fi (AP or STA). Bluetooth cannot carry an image.
  final bool wifiOk;

  /// A cook is recording right now.
  final bool recording;

  /// The user accepted the 409 `session_active` override.
  final bool forced;

  /// The session-active conflict is unresolved.
  bool get conflict => recording && !forced;

  /// Install is possible only with Wi-Fi and no unresolved conflict.
  bool get canInstall => wifiOk && !conflict;

  /// Not on Wi-Fi: the primary action is *Join Wi-Fi*, never Install (N13.11).
  bool get primaryIsJoinWifi => !wifiOk;

  /// Why Install is disabled (I5), or null when it is available.
  String? get installReason {
    if (!wifiOk) {
      return 'Wi-Fi required to install';
    }
    if (conflict) {
      return 'Force the update above, or wait until the cook is done';
    }
    return null;
  }
}

/// Builds the guard from the live connection and cook state.
OtaGuard otaGuard({
  required ConnectionState connection,
  required bool recording,
  required bool forced,
}) => OtaGuard(
  wifiOk: connection.wifi.connected,
  recording: recording,
  forced: forced,
);

/// The Settings "Firmware" row's sub line (`viewSettings`).
String firmwareRowSub(DeviceInfo device) => device.available == null
    ? '${device.version} · up to date'
    : '${device.version} · update available';

/// The Settings "Update firmware" row's sub line (`viewSettings`).
String updateFirmwareRowSub(DeviceInfo device) => device.available == null
    ? 'Over Wi-Fi only'
    : 'Install ${device.available} over Wi-Fi';

/// `stable` / `beta`.
String channelWord(DeviceChannel channel) => channel.name;

/// `stable` / `beta` for the preference enum.
String otaChannelWord(OtaChannel channel) => channel.name;

// ── diagnostics (N13.15–N13.17) ──────────────────────────────────────────

/// One label/value line in the diagnostics sheet.
class DiagnosticFact {
  const DiagnosticFact(this.label, this.value);

  final String label;
  final String value;
}

/// The identity/health facts, prototype-exact (`overlayDiagnostics`). Absent
/// values are `—`, never a fabricated `0` (I3/I11).
List<DiagnosticFact> diagnosticFacts(
  DeviceInfo device,
  ConnectionState connection,
) => <DiagnosticFact>[
  DiagnosticFact(
    'Firmware',
    '${device.version} · ${channelWord(device.channel)}',
  ),
  DiagnosticFact('Hardware', device.hardware),
  DiagnosticFact('Bootloader', device.bootloader),
  DiagnosticFact('Uptime', fmtDuration(device.uptimeMin * 60000)),
  DiagnosticFact('Free heap', '${device.heapKb} KB'),
  DiagnosticFact(
    'Battery',
    connection.batteryPct == null ? '—' : '${connection.batteryPct}%',
  ),
  DiagnosticFact(
    'Recording',
    connection.recording ? 'Yes — on the bridge' : 'No',
  ),
  DiagnosticFact('Last crash', device.lastCrash ?? 'None'),
];

/// Flash used, as a 0..1 fraction (the prototype's storage bar).
double storageUsedFraction(DeviceStorage storage) =>
    storage.totalKb <= 0 ? 0 : storage.usedKb / storage.totalKb;

/// Sessions kept, prototype-exact (`12 of 64`).
String sessionsKept(DeviceStorage storage) => '${storage.sessions} of 64';

/// Flash used, prototype-exact (`36 of 512 KB`).
String flashUsed(DeviceStorage storage) =>
    '${storage.usedKb} of ${storage.totalKb} KB';

/// Retention, prototype-exact (`~54 days of recording`).
String retention(DeviceStorage storage) => '~${storage.days} days of recording';

/// The severity hue bucket a log line maps to (level-coloured list).
enum LogLevel { info, warn, error }

/// Maps the wire's level string onto a hue bucket.
LogLevel logLevelOf(String level) => switch (level) {
  'warn' || 'warning' => LogLevel.warn,
  'error' || 'critical' => LogLevel.error,
  _ => LogLevel.info,
};

// ── five-tap diagnostics gate (N13.18) ───────────────────────────────────

/// How many taps on the About row unlock diagnostics.
const int kDiagnosticsTapCount = 5;

/// The About row's sub copy for a given tap count.
String diagnosticsGateSub(int taps) {
  final shown = taps.clamp(0, kDiagnosticsTapCount);
  if (shown <= 0) {
    return 'Tap $kDiagnosticsTapCount times for device facts and logs';
  }
  return '${kDiagnosticsTapCount - shown} more tap'
      '${kDiagnosticsTapCount - shown == 1 ? '' : 's'} to unlock diagnostics';
}

// ── preferences (N13.3–N13.5) ────────────────────────────────────────────

/// The Appearance row's sub line (`themeLabel`).
String appearanceSub(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => 'Follows your phone',
  AppThemeMode.light => 'Light',
  AppThemeMode.dark => 'Dark',
};

/// The Units row's sub line (`viewSettings`).
String unitsSub(TempUnit units) => units == TempUnit.celsius
    ? 'Temperatures in Celsius'
    : 'Temperatures in Fahrenheit';

/// The Alarms & monitoring row's sub line (`viewSettings`).
String monitoringSub(bool monitoring) =>
    monitoring ? 'Watching in the background' : 'Off';
