/// N10 — the pure connection projections.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/content/fixtures_data.dart';
import 'package:smoke_bridge/data/model/connection_mode.dart';
import 'package:smoke_bridge/data/model/connection_state.dart';
import 'package:smoke_bridge/features/connection/connection_format.dart';

ConnectionState _conn({
  ConnectionPhase phase = ConnectionPhase.connected,
  String? error,
  LinkPrimary? primary = LinkPrimary.wifi,
  LinkState bt = const LinkState(),
  LinkState wifi = const LinkState(mode: WifiMode.sta),
}) => ConnectionState(
  phase: phase,
  error: error,
  primary: primary,
  bt: bt,
  wifi: wifi,
);

ConnectionMode _mode(String id) =>
    kConnectionModes.firstWhere((m) => m.id == id);

void main() {
  group('signal words', () {
    test('bars map to a word, never a bare number', () {
      expect(signalWord(null), 'no signal');
      expect(signalWord(0), 'none');
      expect(signalWord(1), 'weak');
      expect(signalWord(2), 'fair');
      expect(signalWord(3), 'good');
      expect(signalWord(4), 'strong');
      expect(signalWord(9), 'good');
    });

    test('ago labels match the prototype', () {
      expect(agoLabel(null), isNull);
      expect(agoLabel(0), '0s ago');
      expect(agoLabel(45), '45s ago');
      expect(agoLabel(60), '1m ago');
      expect(agoLabel(3599), '1h ago');
      expect(agoLabel(3600), '1h ago');
      expect(agoLabel(7200), '2h ago');
    });
  });

  group('active mode (I9)', () {
    test('one transport carries data at a time', () {
      expect(
        activeModeId(
          _conn(primary: LinkPrimary.bt, bt: const LinkState(connected: true)),
        ),
        'ble',
      );
      expect(
        activeModeId(
          _conn(
            wifi: const LinkState(
              mode: WifiMode.sta,
              connected: true,
              ssid: 'HomeNet-5G',
            ),
          ),
        ),
        'sta',
      );
      expect(
        activeModeId(
          _conn(wifi: const LinkState(mode: WifiMode.ap, connected: true)),
        ),
        'ap',
      );
      expect(activeModeId(_conn(primary: null)), isNull);
    });

    test('activeMode resolves the matching catalog entry', () {
      expect(activeMode(_conn(), kConnectionModes)?.id, 'sta');
      expect(activeMode(_conn(primary: null), kConnectionModes), isNull);
    });
  });

  group('mode card state', () {
    test('active / needs password / available', () {
      expect(modeStateWord(_mode('ble'), active: true), 'Active');
      expect(modeStateWord(_mode('ble'), active: false), 'Available');
      expect(modeStateWord(_mode('sta'), active: false), 'Needs password');
      expect(modeStateWord(_mode('ap'), active: false), 'Available');
    });
  });

  group('link subtitles (N10.13)', () {
    test('Wi-Fi mode label is plain language', () {
      expect(
        wifiModeLabel(_conn(wifi: const LinkState(mode: WifiMode.ap))),
        'Bridge hotspot',
      );
      expect(
        wifiModeLabel(
          _conn(
            wifi: const LinkState(mode: WifiMode.sta, ssid: 'HomeNet-5G'),
          ),
        ),
        'HomeNet-5G',
      );
      expect(wifiModeLabel(_conn()), 'Home Wi-Fi');
      expect(
        wifiModeLabel(_conn(wifi: const LinkState(mode: WifiMode.off))),
        'Off',
      );
    });

    test('Bluetooth subtitle carries signal and last sync', () {
      expect(bluetoothSubtitle(const LinkState()), 'Not connected');
      expect(
        bluetoothSubtitle(const LinkState(connected: true, bars: 3)),
        'good',
      );
      expect(
        bluetoothSubtitle(
          const LinkState(connected: true, bars: 3, lastSyncS: 4),
        ),
        'good · 4s ago',
      );
      expect(bluetoothSubtitle(const LinkState(connected: true)), 'no signal');
    });

    test('Settings names the phone→bridge hop and its dBm', () {
      expect(
        bridgeBluetoothSubtitle(
          const LinkState(connected: true, bars: 3, rssi: -62, lastSyncS: 4),
        ),
        'Phone → bridge · good · -62 dBm · 4s ago',
      );
      expect(bridgeBluetoothSubtitle(const LinkState()), 'Not connected');
    });

    test('Wi-Fi subtitle covers off / connected / connecting', () {
      expect(
        wifiSubtitle(_conn(wifi: const LinkState(mode: WifiMode.off))),
        'Not set up',
      );
      expect(
        wifiSubtitle(
          _conn(
            wifi: const LinkState(
              mode: WifiMode.sta,
              connected: true,
              ssid: 'HomeNet-5G',
              bars: 4,
              lastSyncS: 4,
            ),
          ),
        ),
        'HomeNet-5G · strong · 4s ago',
      );
      expect(
        wifiSubtitle(
          _conn(
            phase: ConnectionPhase.connecting,
            wifi: const LinkState(mode: WifiMode.sta, ssid: 'HomeNet-5G'),
          ),
        ),
        'Connecting to HomeNet-5G…',
      );
      expect(
        wifiSubtitle(
          _conn(
            primary: null,
            wifi: const LinkState(mode: WifiMode.sta, ssid: 'HomeNet-5G'),
          ),
        ),
        'Not connected',
      );
      expect(
        wifiSubtitle(
          _conn(
            wifi: const LinkState(
              mode: WifiMode.ap,
              connected: true,
              bars: 4,
              lastSyncS: 1,
            ),
          ),
        ),
        'Bridge hotspot · strong · 1s ago',
      );
    });

    test('Settings names the bridge→router hop', () {
      expect(
        bridgeWifiSubtitle(
          _conn(
            wifi: const LinkState(
              mode: WifiMode.sta,
              connected: true,
              ssid: 'HomeNet-5G',
              ip: '192.168.1.42',
              bars: 4,
              lastSyncS: 4,
            ),
          ),
        ),
        'Bridge → router · HomeNet-5G · 192.168.1.42 · strong · 4s ago',
      );
      expect(
        bridgeWifiSubtitle(
          _conn(
            wifi: const LinkState(
              mode: WifiMode.ap,
              connected: true,
              bars: 4,
              lastSyncS: 1,
            ),
          ),
        ),
        'Phone → bridge (hotspot) · Bridge hotspot · strong · 1s ago',
      );
    });
  });

  group('named errors (N10.11)', () {
    test('each error maps to its own state and copy', () {
      expect(
        connectionErrorOf('wrong_password'),
        ConnectionError.wrongPassword,
      );
      expect(
        connectionErrorOf('router_unreachable'),
        ConnectionError.routerUnreachable,
      );
      expect(connectionErrorOf('switch_failed'), ConnectionError.switchFailed);
      expect(connectionErrorOf('nonsense'), ConnectionError.unknown);

      expect(
        connectionErrorCopy(
          _conn(phase: ConnectionPhase.error, error: 'wrong_password'),
        ),
        contains('password was rejected'),
      );
      expect(
        connectionErrorCopy(
          _conn(phase: ConnectionPhase.error, error: 'router_unreachable'),
        ),
        contains('could not reach the router'),
      );
      expect(
        connectionErrorCopy(
          _conn(phase: ConnectionPhase.rollback, error: 'switch_failed'),
          notice: 'Kept Bluetooth.',
        ),
        'Kept Bluetooth.',
      );
      expect(
        connectionErrorCopy(
          _conn(phase: ConnectionPhase.rollback, error: 'switch_failed'),
        ),
        contains('kept its previous link'),
      );
    });

    test('problem phases are error and rollback only', () {
      expect(
        connectionHasProblem(
          _conn(phase: ConnectionPhase.error, error: 'wrong_password'),
        ),
        isTrue,
      );
      expect(
        connectionHasProblem(_conn(phase: ConnectionPhase.rollback)),
        isTrue,
      );
      expect(connectionHasProblem(_conn()), isFalse);
      expect(
        connectionProblemIsWarning(_conn(phase: ConnectionPhase.rollback)),
        isTrue,
      );
      expect(
        connectionProblemIsWarning(_conn(phase: ConnectionPhase.error)),
        isFalse,
      );
    });
  });

  group('capability matrix (I13, N10.5)', () {
    test('BLE is live but cannot do history, rules or OTA', () {
      final ble = _mode('ble');
      expect(featureAvailable(ble, ModeFeature.live), isTrue);
      expect(featureAvailable(ble, ModeFeature.fullHistory), isFalse);
      expect(featureAvailable(ble, ModeFeature.rules), isFalse);
      expect(featureAvailable(ble, ModeFeature.ota), isFalse);
      expect(
        featureReason(ModeFeature.fullHistory),
        'Full history needs Wi-Fi.',
      );
    });

    test('AP and STA carry everything', () {
      for (final id in ['ap', 'sta']) {
        for (final feature in ModeFeature.values) {
          expect(
            featureAvailable(_mode(id), feature),
            isTrue,
            reason: '$id/$feature',
          );
        }
      }
    });

    test('capabilityRows lists every feature with a reason when missing', () {
      final rows = capabilityRows(_mode('ble'));
      expect(rows, hasLength(ModeFeature.values.length));
      final history = rows.firstWhere(
        (r) => r.feature == ModeFeature.fullHistory,
      );
      expect(history.ok, isFalse);
      expect(history.reason, 'Full history needs Wi-Fi.');
      final live = rows.firstWhere((r) => r.feature == ModeFeature.live);
      expect(live.ok, isTrue);
      expect(live.reason, isNull);
    });

    test('fullHistoryRefusal gates only a Wi-Fi-less active link', () {
      expect(
        fullHistoryRefusal(
          _conn(primary: LinkPrimary.bt, bt: const LinkState(connected: true)),
          kConnectionModes,
        ),
        'Full history needs Wi-Fi.',
      );
      expect(fullHistoryRefusal(_conn(), kConnectionModes), isNull);
      expect(
        fullHistoryRefusal(
          _conn(wifi: const LinkState(mode: WifiMode.ap, connected: true)),
          kConnectionModes,
        ),
        isNull,
      );
      expect(
        fullHistoryRefusal(_conn(primary: null), kConnectionModes),
        isNull,
      );
    });
  });

  test('the STA flow offers the prototype scan list', () {
    expect(kScannedNetworks, hasLength(3));
    expect(kScannedNetworks.first.ssid, 'HomeNet-5G');
    expect(kScannedNetworks.first.bars, 4);
  });
}
