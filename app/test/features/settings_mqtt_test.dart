/// A16 — the Home Assistant / MQTT settings page and its transport round-trip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/features/settings/settings_mqtt.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('MqttSettingsView', () {
    testWidgets('save reports the edited config, blank password kept', (
      tester,
    ) async {
      Map<String, Object?>? applied;
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(host: 'old', port: 1883),
            onApply:
                ({
                  required enabled,
                  required host,
                  required port,
                  required user,
                  password,
                  required prefix,
                  required haDiscovery,
                }) async {
                  applied = {
                    'enabled': enabled,
                    'host': host,
                    'port': port,
                    'password': password,
                  };
                },
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('mqtt-host')), 'broker.lan');
      await tester.tap(find.byKey(const Key('mqtt-enabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();

      expect(applied, isNotNull);
      expect(applied!['host'], 'broker.lan');
      expect(applied!['enabled'], true);
      // A blank password field must NOT wipe the stored one.
      expect(applied!['password'], isNull);
    });

    testWidgets('enabling without a host is refused with a reason', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            onApply:
                ({
                  required enabled,
                  required host,
                  required port,
                  required user,
                  password,
                  required prefix,
                  required haDiscovery,
                }) async {
                  called = true;
                },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('mqtt-enabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();
      expect(find.byKey(const Key('mqtt-error')), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('a Bluetooth link explains instead of offering the form', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            unsupportedReason: 'Home Assistant needs a Wi-Fi connection.',
            onApply:
                ({
                  required enabled,
                  required host,
                  required port,
                  required user,
                  password,
                  required prefix,
                  required haDiscovery,
                }) async {},
          ),
        ),
      );
      expect(find.byKey(const Key('mqtt-unsupported')), findsOneWidget);
      expect(find.byKey(const Key('mqtt-host')), findsNothing);
    });
  });
}
