/// §F Network and §F Firmware (design 05 §5.4, §5.8; 06 §6.2; 03 §3.7).
///
/// **The bug this file was rewritten to kill.** The "Current" line used to read
/// off `NetMode _netMode = NetMode.sta` — a *constructor default* in the route,
/// never once written by a read from the device. A bridge sitting there hosting
/// its own access point rendered as "Joined a network", in bold, at the top of
/// the one page a user opens when they cannot reach it. It was the single
/// clearest instance of the thing §I.0 says to delete outright, and it is why
/// [NetworkSettingsView.mode] is now nullable and null means `—`.
///
/// The second change is the switch itself. It used to be fire-and-forget:
/// `onApply` posted a mode change down the very link that change was about to
/// kill, then set the local field to whatever had been asked for and reported
/// success. If the password was wrong, the bridge left, failed to join, and was
/// reachable by nobody — while this screen said it had joined. Mode changes now
/// run §E.3's wizard ([NetModeSwitch]): request with a rollback timer, race the
/// expected new endpoint, commit on a real `GET /status` 200, and if nobody
/// commits, say so with the device's own countdown on screen.
///
/// Two promises older than this file, both kept:
///
///  * **Manual address entry is always available and jumps the queue** (05
///    §5.8, 08 §8.4). It is the one path that works when discovery, mDNS, the
///    AP default and Bluetooth have all failed.
///  * **The OTA `409` is a feature.** An update is refused while a session is
///    active unless forced, because nobody should discover a bad flash fourteen
///    hours into a brisket.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../ui/ui.dart';
import 'netmode_switch.dart' show kNetModeRevertS;
import 'settings_kit.dart';

/// Which of the two things the bridge can be doing with Wi-Fi.
///
/// There is deliberately no `unknown` member: absence is `null`, the same way
/// every other unread value in this app is absent rather than enumerated.
enum NetMode { ap, sta }

class NetworkSettingsView extends StatefulWidget {
  const NetworkSettingsView({
    required this.onSwitchMode,
    this.mode,
    this.ssid = '',
    this.ip = '',
    this.apPsk = '',
    this.wifiDbm,
    this.apClients,
    this.revertInS,
    this.manualAddress = '',
    this.onManualAddress,
    this.manualAddressError = '',
    this.manualAddressBusy = false,
    this.recoveryMessage = '',
    this.unsupportedReason = '',
    super.key,
  });

  /// **Null until the bridge has said so.** Never defaulted: a settings screen
  /// that states a mode it was never told is the same lie as a stale
  /// temperature under a live chip.
  final NetMode? mode;

  /// Runs §E.3's wizard. Returns when the switch has reached a resting state —
  /// committed, rolled back, or refused — so the page can re-read afterwards.
  final Future<void> Function(NetMode mode, String ssid, String psk)
  onSwitchMode;

  /// The network it joined, or the one it hosts. Empty = not reported.
  final String ssid;
  final String ip;

  /// Handed back by the device on a switch to hosting: the user needs it to
  /// join (06 §6.2). It is not a secret from anyone already on that network.
  final String apPsk;

  /// Bridge → router, in dBm. Only meaningful while it is a client.
  final int? wifiDbm;

  /// Devices joined to the bridge's own network. Only meaningful while hosting.
  final int? apClients;

  /// Seconds until the device rolls back a change nobody has confirmed. The
  /// device owns this countdown; the app only reports it.
  final int? revertInS;

  final String manualAddress;

  /// Hands the normalised address to the route, which **probes it before it
  /// believes it**. The row promises "reconnects straight away"; the promise
  /// is only keepable if something answered.
  final ValueChanged<String>? onManualAddress;

  /// What the route found when it tried the address, in the user's words.
  /// Empty when nothing has been tried or the last try worked.
  final String manualAddressError;

  /// True while that probe is in flight, so the verb says what it is doing
  /// instead of appearing to have done nothing.
  final bool manualAddressBusy;

  /// Set after a change that left this phone unable to reach the bridge — the
  /// recovery copy, not a spinner.
  final String recoveryMessage;

  /// Non-empty when there is no link to carry a mode change at all.
  final String unsupportedReason;

  @override
  State<NetworkSettingsView> createState() => _NetworkSettingsViewState();
}

class _NetworkSettingsViewState extends State<NetworkSettingsView> {
  final _ssid = TextEditingController();
  final _psk = TextEditingController();
  final _manual = TextEditingController();

  /// True once somebody has typed a network name. Until then the field mirrors
  /// whatever the bridge reports.
  bool _ssidEdited = false;

  String _manualError = '';
  String _joinError = '';

  @override
  void initState() {
    super.initState();
    _ssid.text = widget.ssid;
    _manual.text = widget.manualAddress;
  }

  /// Prefills "Join a network" from the network the bridge is actually on.
  ///
  /// The controller used to be `late final` off `widget.ssid`, and `widget.ssid`
  /// is `''` on the first build — the route learns the SSID from `signal()` a
  /// round trip later. So the one field that could have been pre-filled with
  /// the right answer was permanently empty, and a user re-joining the network
  /// the bridge had just dropped off had to type it in from memory.
  @override
  void didUpdateWidget(covariant NetworkSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ssidEdited && widget.ssid != oldWidget.ssid) {
      _ssid.text = widget.ssid;
    }
  }

  @override
  void dispose() {
    _ssid.dispose();
    _psk.dispose();
    _manual.dispose();
    super.dispose();
  }

  /// §16.4 rule 3 keeps RSSI out of everything except Diagnostics, and a bare
  /// "−58 dBm" on a settings page is exactly that. The word carries the
  /// meaning; the number stays beside it for anyone who wants it.
  static String signalWord(int dbm) => switch (dbm) {
    >= -60 => 'Strong',
    >= -70 => 'Good',
    >= -80 => 'Weak',
    _ => 'Barely there',
  };

  String? get _modeValue => switch (widget.mode) {
    null => null,
    NetMode.ap => 'Hosting its own',
    NetMode.sta => 'Joined yours',
  };

  String get _modeSubtitle => switch (widget.mode) {
    null =>
      'The bridge hasn’t told this phone which it is doing yet. The app does '
          'not guess.',
    NetMode.ap =>
      'Your phone joins the bridge’s network to reach it. No router needed, '
          'and no internet on that network by design.',
    NetMode.sta =>
      'The bridge is on your network, so you can reach it from anywhere in '
          'the house.',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hosting = widget.mode == NetMode.ap;
    return SettingsPage(
      key: const Key('settings-network'),
      children: [
        if (widget.revertInS != null && widget.revertInS! > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: CapabilityNotice(
              key: const Key('network-revert-pending'),
              icon: Icons.history_rounded,
              message:
                  'A change is waiting to be confirmed. If this phone does not '
                  'reach the bridge on the new network, it goes back to what '
                  'was working in ${widget.revertInS} seconds. Nothing to undo.',
            ),
          ),
        if (widget.recoveryMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: ProblemState(
              key: const Key('network-recovery'),
              title: 'Couldn’t reach the bridge',
              message: widget.recoveryMessage,
            ),
          ),
        const SettingsSectionLabel('Right now'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('network-current'),
              // Not "Network": it sat directly above a row called "Network
              // name", two different things opening with the same word, on the
              // page somebody opens because they cannot reach the bridge.
              label: 'What it’s doing',
              subtitle: _modeSubtitle,
              value: _modeValue,
            ),
            SettingsRow(
              key: const Key('network-ssid'),
              label: hosting ? 'Its network name' : 'Network name',
              value: widget.ssid.isEmpty ? null : widget.ssid,
            ),
            SettingsRow(
              key: const Key('network-address'),
              label: 'Address',
              subtitle: 'Where this phone sends its requests',
              value: widget.ip.isEmpty ? null : widget.ip,
            ),
            SettingsRow(
              key: const Key('network-strength'),
              label: hosting ? 'Devices joined to it' : 'Signal to your router',
              subtitle: hosting
                  ? 'The bridge cannot measure your phone’s signal from where '
                        'it sits'
                  : 'Bridge to router. Your phone’s own signal is a different '
                        'hop.',
              value: hosting
                  ? (widget.apClients == null ? null : '${widget.apClients}')
                  : (widget.wifiDbm == null
                        ? null
                        : '${signalWord(widget.wifiDbm!)} · '
                              '${widget.wifiDbm} dBm'),
            ),
          ],
        ),
        if (hosting && widget.apPsk.isNotEmpty) ...[
          const SettingsSectionLabel('Password for its network'),
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: MonoWell(
              key: const Key('network-ap-psk'),
              value: widget.apPsk,
              label:
                  'JOIN “${widget.ssid.isEmpty ? 'the bridge' : widget.ssid}”'
                  ' WITH',
            ),
          ),
        ],
        const SettingsSectionLabel('Change how it connects'),
        SettingsGroup(
          reason: widget.unsupportedReason,
          footer: const Text(
            'A change is confirmed only once this phone finds the bridge '
            'again. If it cannot, the bridge puts back what was working on its '
            'own — you never have to walk over with a cable.',
          ),
          children: [
            SettingsActionRow(
              key: const Key('network-mode-ap'),
              label: 'Host its own network',
              subtitle:
                  'Works anywhere, even with no Wi-Fi at all. Costs battery, '
                  'and your phone has to leave your home network to reach it.',
              buttonLabel: hosting ? 'Already hosting' : 'Switch',
              onPressed: hosting
                  ? null
                  : () => widget.onSwitchMode(NetMode.ap, '', ''),
            ),
            SettingsFieldRow(
              label: 'Join a network',
              subtitle:
                  'The bridge joins your Wi-Fi, and you reach it from '
                  'anywhere in the house',
              fieldKey: const Key('network-ssid-field'),
              controller: _ssid,
              hintText: 'Network name',
              onChanged: (_) => _ssidEdited = true,
            ),
            SettingsFieldRow(
              label: 'Password',
              subtitle:
                  'Only used to join. It is stored on the bridge, never '
                  'sent back.',
              fieldKey: const Key('network-psk'),
              controller: _psk,
              obscure: true,
              errorText: _joinError,
            ),
            SettingsActionRow(
              key: const Key('network-join'),
              label: 'Join that network',
              subtitle: 'The app reconnects on the other side and confirms',
              buttonLabel: 'Join',
              onPressed: _join,
            ),
            // §F lists a settable SoftAP name and key. The firmware derives
            // both from the device id and hands the key back on the switch, so
            // the row states that rather than offering a field the bridge
            // would ignore.
            const SettingsRow(
              key: Key('network-ap-credentials'),
              label: 'Name and password of its own network',
              subtitle: 'Both come from the id printed on the case',
              reason:
                  'The bridge builds these itself so that a phone can always '
                  'find it after a reset. There is nothing to set.',
            ),
            const SettingsRow(
              key: Key('network-revert-timer'),
              label: 'Go back if the change doesn’t work',
              subtitle:
                  'How long the bridge waits for this phone to find it again '
                  'before putting back what was working',
              value: '$kNetModeRevertS seconds',
              reason:
                  'The timer is fixed in the app so that a value nobody could '
                  'reach the bridge to correct can never be set too short.',
            ),
          ],
        ),
        const SettingsSectionLabel('Reach it directly'),
        SettingsGroup(
          footer: const Text(
            'Typing an address always works, and it jumps ahead of everything '
            'else the app tries. It is the escape hatch when discovery fails.',
          ),
          children: [
            SettingsFieldRow(
              label: 'Address',
              subtitle: 'An IP address, or a name your network resolves',
              fieldKey: const Key('network-manual'),
              controller: _manual,
              hintText: '192.168.1.42',
              errorText: _manualError.isNotEmpty
                  ? _manualError
                  : widget.manualAddressError,
            ),
            SettingsActionRow(
              key: const Key('network-manual-connect'),
              label: 'Use that address',
              subtitle: widget.manualAddressBusy
                  ? 'Asking the bridge whether it is there…'
                  : 'The app checks the address answers before it keeps it',
              buttonLabel: widget.manualAddressBusy ? 'Trying…' : 'Connect',
              onPressed: widget.manualAddressBusy ? null : _connectManual,
            ),
          ],
        ),
        Text(
          'Bluetooth stays connected through every change on this page. That '
          'is what makes a wrong password recoverable instead of a walk to the '
          'smoker.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
    );
  }

  void _join() {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) {
      setState(() => _joinError = 'Enter the name of the network to join');
      return;
    }
    setState(() => _joinError = '');
    widget.onSwitchMode(NetMode.sta, ssid, _psk.text);
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

/// §F Firmware.
class FirmwareSettingsView extends StatelessWidget {
  const FirmwareSettingsView({
    required this.currentVersion,
    required this.otaSupported,
    this.model,
    this.unsupportedReason = '',
    this.imageSourceAvailable = false,
    this.sessionActive = false,
    this.progressPct,
    this.phase = '',
    this.refusal = '',
    this.onUpload,
    super.key,
  });

  final String currentVersion;
  final String? model;

  /// False on Bluetooth, always: an image is far too big for that lane.
  final bool otaSupported;

  /// Why, in the user's words, when [otaSupported] is false.
  final String unsupportedReason;

  /// A12.6 — whether an `AppEnv.firmwareImage` source is registered to pick a
  /// `.bin`. False in v1: the screen then explains where to get an image
  /// rather than showing a dead enabled button.
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
    final t = context.tokens;
    final updating = progressPct != null;
    return SettingsPage(
      key: const Key('settings-firmware'),
      children: [
        const SettingsSectionLabel('Installed'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('firmware-version'),
              label: 'Version',
              subtitle: 'Updates install over Wi-Fi and never touch your cooks',
              value: currentVersion.isEmpty ? null : currentVersion,
            ),
            SettingsRow(
              key: const Key('firmware-model'),
              label: 'Model',
              value: (model ?? '').isEmpty ? null : model,
            ),
          ],
        ),
        const SettingsSectionLabel('Update'),
        // §F asks for a "check for update". There is no update server behind
        // this product, so the row states that instead of a button that would
        // spin and then say nothing.
        const SettingsGroup(
          children: [
            SettingsRow(
              key: Key('firmware-check'),
              label: 'Check for an update',
              subtitle: 'Ask whether a newer firmware exists',
              reason:
                  'There is nowhere to ask. This firmware is built and '
                  'installed by hand, so a new version arrives as a file you '
                  'choose below.',
            ),
          ],
        ),
        if (!otaSupported)
          SettingsGroup(
            reason: unsupportedReason.isEmpty
                ? 'Updating needs a Wi-Fi connection to the bridge.'
                : unsupportedReason,
            children: const [
              SettingsRow(
                key: Key('firmware-unsupported'),
                label: 'Install a firmware file',
                subtitle: 'Sends a .bin straight to the bridge',
              ),
            ],
          )
        else if (!imageSourceAvailable)
          SettingsGroup(
            reason:
                'Picking a file isn’t in this version of the app. Open the '
                'SmokeBridge web installer on a computer, plug the bridge in '
                'with a USB cable, and it will flash the latest firmware for '
                'you.',
            children: const [
              SettingsRow(
                key: Key('firmware-no-image-source'),
                label: 'Install a firmware file',
                subtitle: 'Sends a .bin straight to the bridge',
              ),
            ],
          )
        else
          SettingsGroup(
            children: [
              SettingsActionRow(
                key: const Key('firmware-upload'),
                label: 'Install a firmware file',
                subtitle: updating
                    ? '$phase — $progressPct%'
                    : 'Pick a .bin and send it. The bridge restarts into it '
                          'when it has the whole file.',
                buttonLabel: updating ? 'Updating…' : 'Choose a file',
                onPressed: (onUpload == null || updating)
                    ? null
                    : () => onUpload!(force: false),
              ),
            ],
          ),
        if (updating)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  key: const Key('firmware-progress'),
                  value: (progressPct! / 100).clamp(0.0, 1.0),
                ),
                const SizedBox(height: SmokeTokens.s2),
                Text(
                  '$phase — $progressPct%',
                  key: const Key('firmware-phase'),
                  style: SmokeType.bodySm.copyWith(color: t.textBody),
                ),
              ],
            ),
          ),
        if (refusal.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: ProblemState(
              key: const Key('firmware-refusal'),
              title: 'The bridge refused the update',
              message:
                  'A cook is running. Nobody should discover a bad flash '
                  'fourteen hours into a brisket.',
            ),
          ),
          if (sessionActive && imageSourceAvailable && otaSupported)
            // A separate, deliberate action. Never an automatic retry.
            SettingsGroup(
              children: [
                SettingsActionRow(
                  key: const Key('firmware-upload-force'),
                  label: 'Update anyway',
                  subtitle:
                      'Ends the running cook. The readings already taken '
                      'are kept.',
                  buttonLabel: 'Update anyway',
                  danger: true,
                  onPressed: onUpload == null
                      ? null
                      : () => onUpload!(force: true),
                ),
              ],
            ),
        ],
        Text(
          'An update never touches your cooks. They live in the bridge’s '
          'storage and on this phone, not in the firmware image.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
    );
  }
}
