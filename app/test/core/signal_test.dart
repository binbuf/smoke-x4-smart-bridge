/// A26 — the signal ladder. Pure, so the thresholds are pinned by a test
/// rather than by whatever the meter happened to look like on one bench.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/core/signal.dart';

void main() {
  group('signalLevel', () {
    test('the two radios do not share a scale', () {
      // The whole reason SignalKind exists: −70 dBm is a comfortable Wi-Fi
      // link and a middling Bluetooth one. One shared table would mislabel
      // one of them, every time.
      expect(signalLevel(-70, kind: SignalKind.wifi), SignalLevel.fair);
      expect(signalLevel(-70, kind: SignalKind.bluetooth), SignalLevel.good);
    });

    test('wifi bands', () {
      expect(signalLevel(-30, kind: SignalKind.wifi), SignalLevel.excellent);
      expect(signalLevel(-55, kind: SignalKind.wifi), SignalLevel.excellent);
      expect(signalLevel(-56, kind: SignalKind.wifi), SignalLevel.good);
      expect(signalLevel(-67, kind: SignalKind.wifi), SignalLevel.good);
      expect(signalLevel(-68, kind: SignalKind.wifi), SignalLevel.fair);
      expect(signalLevel(-78, kind: SignalKind.wifi), SignalLevel.fair);
      expect(signalLevel(-79, kind: SignalKind.wifi), SignalLevel.weak);
      expect(signalLevel(-95, kind: SignalKind.wifi), SignalLevel.weak);
    });

    test('bluetooth bands', () {
      expect(
        signalLevel(-40, kind: SignalKind.bluetooth),
        SignalLevel.excellent,
      );
      expect(signalLevel(-61, kind: SignalKind.bluetooth), SignalLevel.good);
      expect(signalLevel(-73, kind: SignalKind.bluetooth), SignalLevel.fair);
      expect(signalLevel(-85, kind: SignalKind.bluetooth), SignalLevel.weak);
    });

    test('bars are 1..4 — never 0, at any input', () {
      for (var dbm = 0; dbm >= -120; dbm--) {
        for (final k in SignalKind.values) {
          final b = signalBars(dbm, kind: k);
          expect(b, inInclusiveRange(1, 4), reason: '$dbm dBm on $k');
        }
      }
    });
  });

  group('formatting', () {
    test('a real minus sign, and the em dash for nothing', () {
      expect(formatDbm(-67), '−67 dBm');
      expect(formatDbm(null), '—');
    });

    test('only a weak link gets advice — the rest stay quiet', () {
      // An app that comments on every healthy reading teaches people to
      // stop reading it.
      expect(signalAdvice(SignalLevel.excellent, kind: SignalKind.wifi), '');
      expect(signalAdvice(SignalLevel.good, kind: SignalKind.wifi), '');
      expect(signalAdvice(SignalLevel.fair, kind: SignalKind.wifi), '');
      expect(
        signalAdvice(SignalLevel.weak, kind: SignalKind.wifi),
        contains('router'),
      );
      expect(
        signalAdvice(SignalLevel.weak, kind: SignalKind.bluetooth),
        contains('closer'),
      );
    });
  });
}
