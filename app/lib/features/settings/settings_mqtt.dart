/// §F Home Assistant / MQTT (design 05 §5.7).
///
/// Wi-Fi only, opt-in, and the reason is worth stating on screen rather than
/// merely enforcing: **the broker lives on your network, not on the bridge.** A
/// Bluetooth link reaches the bridge and nothing else, so there is no path from
/// it to a broker at all. On that lane the page renders its rows dimmed with
/// that sentence beneath them, and does not offer a form that could only fail.
///
/// The password is write-only: the device never returns it, so the field loads
/// blank and an empty field on save means "keep the stored one". That is stated
/// in the field's own subtitle, because a blank password box on a form that has
/// clearly been configured before is otherwise indistinguishable from a
/// password that got lost.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/transport/bridge_transport.dart' show MqttConfig;
import '../../design/design.dart';
import '../../ui/ui.dart';
import 'settings_kit.dart';

class MqttSettingsView extends StatefulWidget {
  const MqttSettingsView({
    required this.config,
    required this.onApply,
    this.configKnown = true,
    this.unsupportedReason = '',
    super.key,
  });

  final MqttConfig config;

  /// False until the bridge has actually answered `GET /config/mqtt`. The
  /// summary rows then read `—` instead of showing [MqttConfig]'s own
  /// constructor defaults (port 1883, prefix `smokebridge`) as if the bridge
  /// had reported them.
  ///
  /// **The form is gated on it too, and that was the bug.** The summary rows
  /// honoured this flag from the day it was added; the fields below them did
  /// not. They seeded `late final` controllers from a default-constructed
  /// [MqttConfig] on the first build — blank host, port 1883, publishing off —
  /// and the route hands the real config in a round trip later. A user who
  /// opened the page and tapped "Save to the bridge" before the read landed
  /// wrote that empty form over a working broker, and the read-back agreed
  /// with it, because it *was* what the bridge now had.
  final bool configKnown;

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

  /// Non-empty on a lane that cannot do MQTT.
  final String unsupportedReason;

  @override
  State<MqttSettingsView> createState() => _MqttSettingsViewState();
}

class _MqttSettingsViewState extends State<MqttSettingsView> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _prefix = TextEditingController();
  bool _enabled = false;
  bool _ha = true;

  /// True once somebody has typed in or toggled this form. From then on a
  /// later read never overwrites it: a broker read arriving mid-edit must not
  /// take back the address being typed.
  bool _edited = false;

  String _error = '';
  bool _saving = false;

  bool get _blocked => widget.unsupportedReason.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.configKnown) {
      _adopt();
    }
  }

  /// Takes the bridge's answer whenever a fresh one arrives and the user has
  /// not started editing.
  @override
  void didUpdateWidget(covariant MqttSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.configKnown && !_edited) {
      _adopt();
    }
  }

  void _markEdited(String _) => _edited = true;

  void _adopt() {
    final c = widget.config;
    _seed(_host, c.host);
    _seed(_port, c.port.toString());
    _seed(_user, c.user);
    _seed(_prefix, c.prefix);
    _enabled = c.enabled;
    _ha = c.haDiscovery;
    // The password is never echoed by the device, so the field stays blank
    // and an empty field on save means "keep the stored one".
  }

  /// Assigns only when the text differs. The setter collapses the selection, so
  /// an unconditional write on every parent rebuild would jump the caret in a
  /// box somebody had just tapped into.
  static void _seed(TextEditingController c, String value) {
    if (c.text != value) {
      c.text = value;
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'A port is a number from 1 to 65535');
      return;
    }
    if (_enabled && _host.text.trim().isEmpty) {
      setState(() => _error = 'Turning this on needs your broker’s address');
      return;
    }
    setState(() {
      _error = '';
      _saving = true;
    });
    try {
      await widget.onApply(
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
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final known = widget.configKnown;
    return SettingsPage(
      key: const Key('settings-mqtt'),
      lead:
          'Publish your cook to Home Assistant over MQTT. The bridge shows up '
          'as one device, with each probe, the battery and the cook status as '
          'entities — nothing to configure by hand at the other end.',
      children: [
        const SettingsSectionLabel('Publishing'),
        SettingsGroup(
          reason: widget.unsupportedReason,
          children: [
            SettingsRow(
              key: const Key('mqtt-status'),
              label: 'Status',
              subtitle: widget.config.connected
                  ? 'The bridge is connected to your broker and publishing'
                  : (known
                        ? 'The bridge is not connected to a broker'
                        : 'The bridge hasn’t reported this yet'),
              value: !known
                  ? null
                  : (widget.config.connected
                        ? 'Publishing'
                        : (widget.config.enabled ? 'Trying' : 'Off')),
            ),
            SettingsRow(
              key: const Key('mqtt-current-broker'),
              label: 'Broker',
              subtitle: 'Where readings are being sent',
              value: !known || widget.config.host.isEmpty
                  ? null
                  : '${widget.config.host}:${widget.config.port}',
            ),
          ],
        ),
        if (_blocked)
          // The rows above already carry the reason. Repeating the form dimmed
          // would be nine more inert fields saying the same thing.
          Text(
            'Connect the bridge to your Wi-Fi under Network, then come back — '
            'the form appears here.',
            key: const Key('mqtt-unsupported'),
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          )
        else if (!known)
          // Not a spinner, and emphatically not the form: an empty form here
          // is a save button pointed at a working broker.
          Text(
            'The bridge hasn’t sent its broker settings yet. The form appears '
            'here as soon as it does — filling one in now would write it over '
            'whatever the bridge is actually using.',
            key: const Key('mqtt-unread'),
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          )
        else ...[
          const SettingsSectionLabel('Your broker'),
          SettingsGroup(
            children: [
              SettingsSwitchRow(
                key: const Key('mqtt-enabled'),
                label: 'Publish to Home Assistant',
                subtitle:
                    'The bridge connects to your broker and keeps publishing '
                    'while it is powered',
                value: _enabled,
                onChanged: (v) => setState(() {
                  _edited = true;
                  _enabled = v;
                }),
              ),
              SettingsFieldRow(
                label: 'Broker address',
                subtitle: 'The machine running MQTT on your network',
                fieldKey: const Key('mqtt-host'),
                controller: _host,
                hintText: '192.168.1.10 or homeassistant.local',
                onChanged: _markEdited,
              ),
              SettingsFieldRow(
                label: 'Port',
                subtitle: '1883 unless you changed it',
                fieldKey: const Key('mqtt-port'),
                controller: _port,
                keyboardType: TextInputType.number,
                onChanged: _markEdited,
              ),
              SettingsFieldRow(
                label: 'Username',
                subtitle: 'Leave empty if your broker allows anonymous clients',
                fieldKey: const Key('mqtt-user'),
                controller: _user,
                onChanged: _markEdited,
              ),
              SettingsFieldRow(
                label: 'Password',
                subtitle:
                    'The bridge never sends this back, so it loads empty. '
                    'Leaving it empty keeps the one already stored.',
                fieldKey: const Key('mqtt-pass'),
                controller: _pass,
                obscure: true,
                onChanged: _markEdited,
              ),
            ],
          ),
          const SettingsSectionLabel('Home Assistant'),
          SettingsGroup(
            children: [
              SettingsSwitchRow(
                key: const Key('mqtt-ha-discovery'),
                label: 'Create the entities automatically',
                subtitle:
                    'Turn this off only if you define the entities yourself in '
                    'Home Assistant',
                value: _ha,
                onChanged: (v) => setState(() {
                  _edited = true;
                  _ha = v;
                }),
              ),
              SettingsFieldRow(
                label: 'Topic prefix',
                subtitle:
                    'Change it only if another SmokeBridge already publishes '
                    'here',
                fieldKey: const Key('mqtt-prefix'),
                controller: _prefix,
                hintText: 'smokebridge',
                onChanged: _markEdited,
              ),
            ],
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
              // The hue rides the icon and the border; the sentence stays
              // readable ink (§14.6.5). Red words on this surface measure
              // 3.19:1 — an error nobody can read is not an error message.
              child: CapabilityNotice(
                key: const Key('mqtt-error'),
                message: _error,
                icon: Icons.error_outline_rounded,
                role: StatusRole.critical,
              ),
            ),
          PrimaryAction(
            key: const Key('mqtt-save'),
            label: 'Save to the bridge',
            busy: _saving,
            onPressed: () => unawaited(_save()),
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            'The app reads the settings back from the bridge afterwards and '
            'shows you what it actually kept.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
      ],
    );
  }
}
