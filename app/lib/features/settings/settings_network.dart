/// A12.3 / A12.5 — network settings and the firmware page (design 05
/// §5.4, §5.8; 06 §6.2; 03 §3.7).
///
/// Two promises this file has to keep, both older than it is:
///
///  * **Manual IP entry is always available and jumps the queue** (05
///    §5.8, 08 §8.4). It is the one path that works when discovery, mDNS,
///    the AP default and BLE have all failed — A7.1 built `enterManual` to
///    pre-empt a race in flight so that this field could exist.
///  * **The OTA `409` is a feature.** An update is refused while a session
///    is active unless forced, because nobody should discover a bad flash
///    fourteen hours into a brisket. The screen explains the refusal and
///    offers the force path as a deliberate second action — never as an
///    automatic retry.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';

enum NetMode { ap, sta }

class NetworkSettingsView extends StatefulWidget {
  const NetworkSettingsView({
    required this.mode,
    required this.onApply,
    this.ssid = '',
    this.ip = '',
    this.apPsk = '',
    this.rssi,
    this.manualAddress = '',
    this.onManualAddress,
    this.recoveryMessage = '',
    super.key,
  });

  final NetMode mode;

  /// Applies a mode change. The device answers *before* it reconfigures
  /// and defers ~500 ms so the reply flushes (05 §5.4) — the app does not
  /// invent a second handoff on top of that.
  final Future<void> Function(NetMode mode, String ssid, String psk) onApply;
  final String ssid;
  final String ip;

  /// Returned by the device on a switch to AP: the user needs it to join
  /// (06 §6.2). It is not a secret from anyone already on that AP.
  final String apPsk;
  final int? rssi;
  final String manualAddress;
  final ValueChanged<String>? onManualAddress;

  /// Set after a mode change that left this phone unable to reach the
  /// bridge — the recovery copy, not a spinner.
  final String recoveryMessage;

  @override
  State<NetworkSettingsView> createState() => _NetworkSettingsViewState();
}

class _NetworkSettingsViewState extends State<NetworkSettingsView> {
  late final _ssid = TextEditingController(text: widget.ssid);
  final _psk = TextEditingController();
  late final _manual = TextEditingController(text: widget.manualAddress);
  String _manualError = '';

  @override
  void dispose() {
    _ssid.dispose();
    _psk.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-network'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Current', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          widget.mode == NetMode.ap
              ? 'Hosting its own network'
                    '${widget.ssid.isEmpty ? '' : ' · ${widget.ssid}'}'
                    '${widget.apPsk.isEmpty ? '' : ' · key ${widget.apPsk}'}'
              : 'Joined ${widget.ssid.isEmpty ? 'a network' : widget.ssid}'
                    '${widget.ip.isEmpty ? '' : ' · ${widget.ip}'}'
                    '${widget.rssi == null ? '' : ' · ${widget.rssi} dBm'}',
          key: const Key('network-current'),
          style: theme.textTheme.bodyLarge,
        ),
        if (widget.recoveryMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('network-recovery'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.recoveryMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Change', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // The same honest copy A8 uses. The trade is real in both
        // directions and the user is the one who has to live with it.
        ListTile(
          key: const Key('network-mode-ap'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Host its own network'),
          subtitle: const Text(
            'Works anywhere, even with no Wi-Fi. Costs battery, and your '
            'phone leaves your home network to connect.',
          ),
          trailing: widget.mode == NetMode.ap
              ? const Icon(Icons.check)
              : TextButton(
                  onPressed: () => widget.onApply(NetMode.ap, '', ''),
                  child: const Text('Switch'),
                ),
        ),
        const Divider(),
        const Text('Join a Wi-Fi network'),
        const SizedBox(height: 4),
        TextField(
          key: const Key('network-ssid'),
          controller: _ssid,
          decoration: const InputDecoration(labelText: 'Network name'),
        ),
        TextField(
          key: const Key('network-psk'),
          controller: _psk,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('network-join'),
          onPressed: () => widget.onApply(NetMode.sta, _ssid.text, _psk.text),
          child: const Text('Join'),
        ),
        const SizedBox(height: 24),
        Text('Reach it directly', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'If the app cannot find the bridge, type its address. This '
          'always works, and it jumps ahead of everything else.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextField(
          key: const Key('network-manual'),
          controller: _manual,
          decoration: InputDecoration(
            labelText: 'Address',
            hintText: '192.168.1.42',
            errorText: _manualError.isEmpty ? null : _manualError,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('network-manual-connect'),
          onPressed: _connectManual,
          child: const Text('Connect'),
        ),
      ],
    );
  }

  void _connectManual() {
    final raw = _manual.text.trim();
    final normalized = raw.startsWith('http') ? raw : 'http://$raw';
    final uri = Uri.tryParse(normalized);
    if (raw.isEmpty || uri == null || uri.host.isEmpty || uri.host == 'http') {
      setState(() => _manualError = 'That is not an address the app can use');
      return;
    }
    setState(() => _manualError = '');
    widget.onManualAddress?.call(normalized);
  }
}

/// A12.5 — firmware and OTA.
class FirmwareSettingsView extends StatelessWidget {
  const FirmwareSettingsView({
    required this.currentVersion,
    required this.otaSupported,
    this.imageSourceAvailable = false,
    this.sessionActive = false,
    this.progressPct,
    this.phase = '',
    this.refusal = '',
    this.onUpload,
    super.key,
  });

  final String currentVersion;

  /// False on BLE, always: OTA is HTTP-only (F14, M6 on the device side).
  /// The upload button is then absent, not disabled-and-mysterious.
  final bool otaSupported;

  /// A12.6 — whether an `AppEnv.firmwareImage` source is registered to
  /// pick a `.bin`. False in v1 (no file picker yet): the screen then
  /// explains where to get an image and how to install it rather than
  /// showing a dead enabled button. **A button that explains itself beats
  /// a button that does nothing.**
  final bool imageSourceAvailable;
  final bool sessionActive;
  final int? progressPct;
  final String phase;

  /// The device's own words when it answered `409 session_active`.
  final String refusal;

  /// [force] carries `?force=1`.
  final Future<void> Function({required bool force})? onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-firmware'),
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Installed version'),
          trailing: Text(
            currentVersion.isEmpty ? noValue : currentVersion,
            key: const Key('firmware-version'),
          ),
        ),
        if (!otaSupported)
          Text(
            'Updates need a Wi-Fi connection to the bridge.',
            key: const Key('firmware-unsupported'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          if (progressPct != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              key: const Key('firmware-progress'),
              value: (progressPct! / 100).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 4),
            Text(
              '$phase — $progressPct%',
              key: const Key('firmware-phase'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (refusal.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('firmware-refusal'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The bridge refused the update',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A cook is running. Nobody should discover a bad flash '
                    'fourteen hours into a brisket.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!imageSourceAvailable)
            // A12.6 — no picker in v1. Explain, do not present a dead
            // button: the transport is real and drivable against the sim,
            // and this text is honest about how to update today.
            Text(
              'Over-the-air updates from inside the app arrive in a later '
              'release. For now, install the latest firmware from the web '
              'installer, or flash it over USB — see the project README.',
              key: const Key('firmware-no-image-source'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            FilledButton.icon(
              key: const Key('firmware-upload'),
              onPressed: onUpload == null
                  ? null
                  : () => onUpload!(force: false),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload firmware'),
            ),
            if (refusal.isNotEmpty && sessionActive) ...[
              const SizedBox(height: 8),
              // A separate, deliberate action. Never an automatic retry.
              OutlinedButton(
                key: const Key('firmware-upload-force'),
                onPressed: onUpload == null
                    ? null
                    : () => onUpload!(force: true),
                child: const Text('Update anyway, ending this cook'),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
