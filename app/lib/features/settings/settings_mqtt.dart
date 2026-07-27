/// A16 — Home Assistant / MQTT settings (design 05 §5.7).
///
/// Wi-Fi-only, opt-in. The broker lives on your LAN, so on a Bluetooth-only
/// link the page explains that rather than offering a form that cannot work
/// (the settings rule: a control that cannot work is worse than no control).
///
/// The password is write-only: the device never returns it, so the field is
/// left blank on load and an empty field on save means "keep the stored one".
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/transport/bridge_transport.dart' show MqttConfig;

class MqttSettingsView extends StatefulWidget {
  const MqttSettingsView({
    required this.config,
    required this.onApply,
    this.unsupportedReason = '',
    super.key,
  });

  final MqttConfig config;

  /// Applies the config. [password] null means "leave the stored password
  /// unchanged" — a blank field must not wipe it.
  final Future<void> Function({
    required bool enabled,
    required String host,
    required int port,
    required String user,
    String? password,
    required String prefix,
    required bool haDiscovery,
  })
  onApply;

  /// Non-empty on a transport that cannot do MQTT (BLE): the page shows this
  /// instead of the form.
  final String unsupportedReason;

  @override
  State<MqttSettingsView> createState() => _MqttSettingsViewState();
}

class _MqttSettingsViewState extends State<MqttSettingsView> {
  late final _host = TextEditingController(text: widget.config.host);
  late final _port = TextEditingController(text: widget.config.port.toString());
  late final _user = TextEditingController(text: widget.config.user);
  final _pass = TextEditingController();
  late final _prefix = TextEditingController(text: widget.config.prefix);
  late bool _enabled = widget.config.enabled;
  late bool _ha = widget.config.haDiscovery;
  String _error = '';

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Port must be a number from 1 to 65535');
      return;
    }
    if (_enabled && _host.text.trim().isEmpty) {
      setState(() => _error = 'Turning it on needs a broker address');
      return;
    }
    setState(() => _error = '');
    unawaited(
      widget.onApply(
        enabled: _enabled,
        host: _host.text.trim(),
        port: port,
        user: _user.text.trim(),
        // Blank = keep the stored password.
        password: _pass.text.isEmpty ? null : _pass.text,
        prefix: _prefix.text.trim().isEmpty
            ? 'smokebridge'
            : _prefix.text.trim(),
        haDiscovery: _ha,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.unsupportedReason.isNotEmpty) {
      return Padding(
        key: const Key('settings-mqtt'),
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.unsupportedReason,
          key: const Key('mqtt-unsupported'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView(
      key: const Key('settings-mqtt'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Publish your cook to Home Assistant over MQTT. Your bridge appears '
          'as a device with the probes, battery and cook status as entities — '
          'no manual configuration in Home Assistant.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('mqtt-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Publish to Home Assistant'),
          subtitle: Text(
            widget.config.connected
                ? 'Connected to the broker'
                : (_enabled ? 'Not connected yet' : 'Off'),
            key: const Key('mqtt-status'),
          ),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const Divider(),
        TextField(
          key: const Key('mqtt-host'),
          controller: _host,
          decoration: const InputDecoration(
            labelText: 'Broker address',
            hintText: '192.168.1.10 or homeassistant.local',
          ),
        ),
        TextField(
          key: const Key('mqtt-port'),
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Port'),
        ),
        TextField(
          key: const Key('mqtt-user'),
          controller: _user,
          decoration: const InputDecoration(labelText: 'Username (optional)'),
        ),
        TextField(
          key: const Key('mqtt-pass'),
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            hintText: 'Leave blank to keep the current one',
          ),
        ),
        TextField(
          key: const Key('mqtt-prefix'),
          controller: _prefix,
          decoration: const InputDecoration(labelText: 'Topic prefix'),
        ),
        SwitchListTile(
          key: const Key('mqtt-ha-discovery'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Home Assistant auto-discovery'),
          subtitle: const Text(
            'Entities appear automatically. Turn off only if you define them '
            'yourself in Home Assistant.',
          ),
          value: _ha,
          onChanged: (v) => setState(() => _ha = v),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _error,
            key: const Key('mqtt-error'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('mqtt-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
