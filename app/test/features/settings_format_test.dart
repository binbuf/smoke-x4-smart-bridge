/// N13 — the Settings / device pure projections.
///
/// Pins the prototype's copy and the OTA/diagnostics rules without a binding:
/// the verb cost/progress specs, the Wi-Fi-only and 409 session guards, the
/// firmware row labels, the diagnostics facts and the five-tap gate.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/settings/settings.dart';
import 'package:test/test.dart';

void main() {
  group('device verbs (N13.19–N13.22)', () {
    test('there are four verbs with prototype-exact progress copy', () {
      expect(kVerbSpecs, hasLength(4));
      final restart = verbSpec(DeviceVerb.restart);
      expect(restart.title, 'Restarting the bridge');
      expect(restart.sub, 'Settings and the recording are kept.');
      expect(restart.steps, <String>[
        'Stopping recording cleanly',
        'Draining the sample buffer',
        'Rebooting',
        'LoRa re-sync',
        'Reconnecting',
      ]);
      expect(restart.danger, isFalse);
      expect(restart.keeps, isNotEmpty);

      final factory = verbSpec(DeviceVerb.factoryReset);
      expect(factory.confirmLabel, 'Factory reset');
      expect(factory.danger, isTrue);
      expect(factory.loses, contains('All recorded sessions'));
      expect(factory.steps.last, 'Rebooting to setup mode');

      final forget = verbSpec(DeviceVerb.forget);
      expect(forget.message, contains('from this app'));
      expect(forget.keeps, contains('The bridge\'s own data'));

      final ota = verbSpec(DeviceVerb.ota);
      expect(ota.steps, <String>[
        'Verifying the image',
        'Streaming over Wi-Fi',
        'Writing the inactive slot',
        'Rebooting into the new slot',
        'Health check',
      ]);
    });

    test('verb ids round-trip for the overlay prop', () {
      for (final spec in kVerbSpecs) {
        expect(verbId(spec.verb), spec.id);
        expect(verbFromId(spec.id), spec.verb);
      }
      expect(verbFromId('nonsense'), isNull);
      expect(verbFromId(null), isNull);
    });
  });

  group('OTA guard (N13.11/N13.12)', () {
    const btOnly = ConnectionState(
      phase: ConnectionPhase.connected,
      primary: LinkPrimary.bt,
    );
    const onWifi = ConnectionState(
      phase: ConnectionPhase.connected,
      primary: LinkPrimary.wifi,
      wifi: LinkState(mode: WifiMode.sta, connected: true, ssid: 'HomeNet-5G'),
    );

    test('not on Wi-Fi: primary is Join Wi-Fi, Install is refused', () {
      final guard = otaGuard(
        connection: btOnly,
        recording: false,
        forced: false,
      );
      expect(guard.wifiOk, isFalse);
      expect(guard.primaryIsJoinWifi, isTrue);
      expect(guard.canInstall, isFalse);
      expect(guard.installReason, 'Wi-Fi required to install');
    });

    test('recording on Wi-Fi: 409 conflict until forced', () {
      final blocked = otaGuard(
        connection: onWifi,
        recording: true,
        forced: false,
      );
      expect(blocked.conflict, isTrue);
      expect(blocked.canInstall, isFalse);
      expect(blocked.installReason, contains('Force the update'));

      final forced = otaGuard(
        connection: onWifi,
        recording: true,
        forced: true,
      );
      expect(forced.conflict, isFalse);
      expect(forced.canInstall, isTrue);
      expect(forced.installReason, isNull);
    });

    test('idle on Wi-Fi: Install is available', () {
      final guard = otaGuard(
        connection: onWifi,
        recording: false,
        forced: false,
      );
      expect(guard.canInstall, isTrue);
      expect(guard.primaryIsJoinWifi, isFalse);
      expect(guard.installReason, isNull);
    });
  });

  group('firmware rows (N13.6/N13.9)', () {
    test('the firmware row reports update state', () {
      expect(firmwareRowSub(kDevice), 'v1.4.2 · up to date');
      expect(
        firmwareRowSub(kDevice.copyWith(available: 'v1.5.0')),
        'v1.4.2 · update available',
      );
      expect(updateFirmwareRowSub(kDevice), 'Over Wi-Fi only');
      expect(
        updateFirmwareRowSub(kDevice.copyWith(available: 'v1.5.0')),
        'Install v1.5.0 over Wi-Fi',
      );
    });

    test('channels word correctly', () {
      expect(channelWord(DeviceChannel.stable), 'stable');
      expect(channelWord(DeviceChannel.beta), 'beta');
      expect(otaChannelWord(OtaChannel.stable), 'stable');
      expect(otaChannelWord(OtaChannel.beta), 'beta');
    });
  });

  group('diagnostics (N13.15–N13.17)', () {
    test('facts carry every prototype line', () {
      const connection = ConnectionState(
        phase: ConnectionPhase.connected,
        batteryPct: 71,
      );
      final facts = diagnosticFacts(kDevice, connection);
      final map = <String, String>{
        for (final fact in facts) fact.label: fact.value,
      };
      expect(map['Firmware'], 'v1.4.2 · stable');
      expect(map['Hardware'], 'rev C · ESP32-S3');
      expect(map['Bootloader'], '2.1.0');
      expect(map['Uptime'], '73h 7m');
      expect(map['Free heap'], '128 KB');
      expect(map['Battery'], '71%');
      expect(map['Recording'], 'Yes — on the bridge');
      expect(map['Last crash'], 'None');
    });

    test('absent values are — and never a fabricated zero', () {
      const connection = ConnectionState(phase: ConnectionPhase.offline);
      final facts = diagnosticFacts(kDevice, connection);
      final map = <String, String>{
        for (final fact in facts) fact.label: fact.value,
      };
      expect(map['Battery'], '—');
    });

    test('storage projections match the prototype', () {
      final storage = kDevice.storage;
      expect(sessionsKept(storage), '12 of 64');
      expect(flashUsed(storage), '36 of 512 KB');
      expect(retention(storage), '~54 days of recording');
      expect(storageUsedFraction(storage), closeTo(36 / 512, 0.0001));
    });

    test('log levels bucket into three hues', () {
      expect(logLevelOf('info'), LogLevel.info);
      expect(logLevelOf('warn'), LogLevel.warn);
      expect(logLevelOf('warning'), LogLevel.warn);
      expect(logLevelOf('error'), LogLevel.error);
      expect(logLevelOf('critical'), LogLevel.error);
      expect(logLevelOf('anything'), LogLevel.info);
    });
  });

  group('five-tap gate (N13.18)', () {
    test('the sub line counts the taps down', () {
      expect(kDiagnosticsTapCount, 5);
      expect(diagnosticsGateSub(0), contains('Tap 5 times'));
      expect(diagnosticsGateSub(1), contains('4 more taps'));
      expect(diagnosticsGateSub(4), contains('1 more tap'));
      expect(diagnosticsGateSub(4), isNot(contains('taps to unlock')));
    });
  });

  group('preference sub-lines (N13.3/N13.4)', () {
    test('the rows describe the current value', () {
      expect(appearanceSub(AppThemeMode.system), 'Follows your phone');
      expect(appearanceSub(AppThemeMode.light), 'Light');
      expect(appearanceSub(AppThemeMode.dark), 'Dark');
      expect(unitsSub(TempUnit.fahrenheit), 'Temperatures in Fahrenheit');
      expect(unitsSub(TempUnit.celsius), 'Temperatures in Celsius');
      expect(monitoringSub(true), 'Watching in the background');
      expect(monitoringSub(false), 'Off');
    });
  });
}
