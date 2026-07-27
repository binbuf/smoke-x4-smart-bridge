/// A24.3 — the Bridge tab: the device screen (design 13 §13.5.6).
///
/// Tab 4 of the shell. It answers "which bridge is this, is it reachable, and
/// what can I do to it" — identity (name/id/ip/fw/last-seen), the two safe
/// actions (Identify, re-run Wi-Fi setup), and the disruptive verbs
/// (restart / forget / factory-reset / power-off), **each gated behind a cost
/// sheet that spells out what it keeps and what it loses** rather than a generic
/// "Are you sure?" (§13.5.6).
///
/// **State-first (A24.10).** The screen leads with a connection card that
/// names the truth of right now — Bluetooth / Wi-Fi (hosted) / Wi-Fi (joined) /
/// not connected / no bridge set up — and everything below it declares which
/// state it belongs to: identity rows say "last known" when the bridge is not
/// reachable instead of presenting stale prefs as live facts (the board-found
/// bug: a factory-reset bridge whose old id and IP still read as current), and
/// the verbs that need a link are disabled with their reason when there is
/// none.
///
/// **Data source.** The shell passes its shared [ShellSession]: the live
/// [DashboardSnapshot] (link, mode, address, last reading, paired), the
/// supervisor's [LiveLink] health, and the already-open transport (a `status()`
/// read for firmware and id). With no session (bare tests), it falls back to
/// `AppEnv.instance` prefs, explicitly framed as last-known.
///
/// **No dead controls** (`settings_screen.dart:5-11`, rail R2): Identify has no
/// wire verb in this build, so it is present-and-disabled *with its reason on
/// screen*, the same discipline the settings epic used for battery calibration.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'verb_progress.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../core/format.dart';
import '../../data/prefs/bridge_prefs.dart';
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../shell/connection_sheet.dart';
import '../shell/shell_session.dart';

class BridgeTab extends StatefulWidget {
  /// [session] and [prefs] are both optional so the shell's `const BridgeTab()`
  /// keeps compiling: a one-line import swap lands the real screen, and passing
  /// `session:` later lights up its live data. Tests inject a seeded session.
  const BridgeTab({super.key, this.session, this.prefs});

  final ShellSession? session;
  final BridgePrefs? prefs;

  @override
  State<BridgeTab> createState() => _BridgeTabState();
}

class _BridgeTabState extends State<BridgeTab> {
  /// Fetched for the firmware and device-id rows; null until it lands. Retried
  /// from [build] whenever the session connects after this tab first mounted —
  /// the shell rebuilds on every session change, so a late link still fills
  /// the rows.
  BridgeStatus? _status;
  bool _fetching = false;

  BridgePrefs? get _prefs => widget.prefs ?? AppEnv.instance?.prefs;
  DashboardSnapshot? get _snapshot => widget.session?.snapshot;

  /// The one question every section of this screen keys off: is the bridge
  /// reachable right now?
  bool get _connected =>
      _snapshot != null && _snapshot!.link != LinkKind.offline;

  /// Whether this phone knows a bridge at all — false on a fresh install and
  /// after a factory reset has forgotten it.
  bool get _remembered =>
      (_prefs?.lastBaseUrl ?? '').isNotEmpty ||
      (_prefs?.lastBridgeId ?? '').isNotEmpty ||
      _snapshot != null;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchDeviceInfo());
  }

  void _maybeRefetch() {
    if (_status == null &&
        !_fetching &&
        widget.session?.bridge?.transport != null) {
      _fetching = true;
      unawaited(
        _fetchDeviceInfo().whenComplete(() => _fetching = false),
      );
    }
  }

  /// One `status()` read for the firmware/id rows. Reuses the shell session's
  /// open transport when present (no second socket); otherwise builds one from
  /// the remembered address and closes it straight after — the same
  /// build-ask-close shape `AppConnection` uses to probe a lane.
  Future<void> _fetchDeviceInfo() async {
    final live = widget.session?.bridge?.transport;
    if (live != null) {
      await _statusInto(live, close: false);
      return;
    }
    final env = AppEnv.instance;
    final url = env?.prefs.lastBaseUrl;
    if (env == null || url == null || url.isEmpty) {
      return; // BLE, a fresh install, or a bare test — rows fall back to prefs
    }
    await _statusInto(env.transportFor(url), close: true);
  }

  Future<void> _statusInto(BridgeTransport t, {required bool close}) async {
    try {
      final s = await t.status();
      if (mounted) {
        setState(() => _status = s);
      }
    } on Object {
      // The device page still renders; the rows that needed it say `—`.
    } finally {
      if (close) {
        await t.close();
      }
    }
  }

  /// Runs a disruptive verb inside the completion sheet (A24.9): send, then
  /// verify by watching the bridge actually go down, then a done state. The
  /// send goes through the shared session when present; otherwise a
  /// per-command transport that also serves as the probe.
  Future<void> _runVerb(DisruptiveVerb verb, ControlCommand cmd) async {
    final session = widget.session;
    final bridge = session?.bridge;
    Future<void> Function() send;
    Future<void> Function() probe;
    BridgeTransport? fallback;
    if (session != null && bridge != null) {
      send = () => session.control(cmd);
      // Reads the CURRENT active transport each poll, so a supervisor swap
      // mid-verify still probes the live link.
      probe = () => bridge.transport.status();
    } else {
      final env = AppEnv.instance;
      final url = env?.prefs.lastBaseUrl;
      if (env == null || url == null || url.isEmpty) {
        return;
      }
      final t = env.transportFor(url);
      fallback = t;
      send = () => t.control(cmd);
      probe = () => t.status();
    }
    if (!mounted) {
      await fallback?.close();
      return;
    }
    await showVerbProgressSheet(
      context,
      verb: verb,
      send: send,
      probe: probe,
      // A confirmed factory reset forgets the bridge on this phone at the
      // same moment — the app must never keep claiming a bridge the reset
      // just erased. (Warned in the cost sheet before the user confirms.)
      onCompleted: verb == DisruptiveVerb.factoryReset
          ? () => unawaited(_prefs?.forgetBridge() ?? Future<void>.value())
          : null,
      onSetUpAgain: verb == DisruptiveVerb.factoryReset
          ? () {
              if (mounted) {
                context.go(AppRoutes.setup);
              }
            }
          : null,
    );
    await fallback?.close();
  }

  Future<void> _forget() async {
    await _prefs?.forgetBridge();
    if (mounted) {
      // Nothing remembered → the guided setup flow, where a phone with no
      // bridge belongs (A9.5/§13.5.1).
      context.go(AppRoutes.setup);
    }
  }

  // ── identity values ───────────────────────────────────────────────────

  String get _deviceId =>
      _status?.deviceId.isNotEmpty == true
          ? _status!.deviceId
          : (widget.session?.bridge?.bridgeId.isNotEmpty == true
                ? widget.session!.bridge!.bridgeId
                : (_prefs?.lastBridgeId ?? noValue));

  /// The address the app is USING, never a stale one presented as live: the
  /// snapshot's address while on Wi-Fi, an explicit "none — via Bluetooth"
  /// while on BLE (there is no address in use), and the remembered one only
  /// inside the last-known framing when disconnected.
  String get _address {
    if (_connected && _snapshot!.link == LinkKind.ble) {
      return 'none — via Bluetooth';
    }
    final url = (_snapshot?.address.isNotEmpty == true)
        ? _snapshot!.address
        : (_prefs?.lastBaseUrl ?? '');
    if (url.isEmpty) {
      return noValue;
    }
    return url
        .replaceFirst(RegExp('^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
  }

  String get _firmware =>
      _status?.fw.isNotEmpty == true ? _status!.fw : noValue;

  String get _lastReading {
    final ago = _snapshot?.lastPacketSAgo;
    if (ago != null) {
      return '${formatDuration(ago)} ago';
    }
    final when = formatSessionDate(_prefs?.lastSeenUnixMs);
    return when.isEmpty ? noValue : when;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    _maybeRefetch();
    // A phone with no bridge at all gets ONE clear card and its one action —
    // not a page of dashes pretending there is something to manage.
    if (!_remembered && !_connected) {
      return SafeArea(
        top: false,
        child: ListView(
          key: const Key('bridge-tab'),
          padding: const EdgeInsets.all(SmokeTokens.s4),
          children: [_connectionCard(t)],
        ),
      );
    }
    return SafeArea(
      top: false,
      child: ListView(
        key: const Key('bridge-tab'),
        padding: const EdgeInsets.all(SmokeTokens.s4),
        children: [
          _connectionCard(t),
          const SizedBox(height: SmokeTokens.s4),
          _identityCard(t),
          const SizedBox(height: SmokeTokens.s4),
          _actionsCard(t),
          const SizedBox(height: SmokeTokens.s4),
          _dangerCard(t),
        ],
      ),
    );
  }

  // ── the connection card: the state of right now, always first ─────────

  ({IconData icon, String title, String caption}) get _connectionState {
    final link = _snapshot?.link;
    final upgrading = widget.session?.liveLink?.upgrading ?? false;
    if (link == LinkKind.http) {
      final hosted = _snapshot?.netMode == 'ap';
      return (
        icon: hosted ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
        title: hosted ? 'Wi-Fi — hosted network' : 'Wi-Fi — joined network',
        caption: hosted
            ? 'Connected on the bridge’s own network at $_address. '
                  'Full history, settings, and updates are available.'
            : 'Connected through your network at $_address. '
                  'Full history, settings, and updates are available.',
      );
    }
    if (link == LinkKind.ble) {
      return (
        icon: Icons.bluetooth_rounded,
        title: 'Bluetooth',
        caption: upgrading
            ? 'Live readings now, over Bluetooth. Connecting to Wi-Fi in '
                  'the background for full history.'
            : 'Live readings over Bluetooth. Connect Wi-Fi for full '
                  'history, settings, and updates.',
      );
    }
    if (_remembered) {
      return (
        icon: Icons.cloud_off_rounded,
        title: 'Not connected',
        caption: 'Can’t reach the bridge right now. The app keeps trying '
            'and reconnects on its own — Bluetooth first, then Wi-Fi.',
      );
    }
    return (
      icon: Icons.add_link_rounded,
      title: 'No bridge set up',
      caption: 'This phone isn’t linked to a bridge yet. Setup takes a few '
          'minutes and starts over Bluetooth.',
    );
  }

  Widget _connectionCard(SmokeTokens t) {
    final s = _connectionState;
    final session = widget.session;
    return SmokeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONNECTION',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(s.icon, size: 26, color: _connected ? t.textHi : t.textMuted),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      key: const Key('bridge-connection-title'),
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.caption,
                      key: const Key('bridge-connection-caption'),
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SmokeTokens.s3),
          if (!_remembered && !_connected)
            FilledButton.icon(
              key: const Key('bridge-set-up'),
              onPressed: () => context.go(AppRoutes.setup),
              icon: const Icon(Icons.bluetooth_searching_rounded),
              label: const Text('Set up a bridge'),
            )
          else if (session != null)
            OutlinedButton.icon(
              key: const Key('bridge-manage-connection'),
              onPressed: () =>
                  unawaited(showConnectionSheet(context, session)),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Manage connection'),
            ),
        ],
      ),
    );
  }

  Widget _identityCard(SmokeTokens t) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YOUR BRIDGE',
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
        if (!_connected) ...[
          const SizedBox(height: SmokeTokens.s2),
          Text(
            'Not connected — these are the last known details.',
            key: const Key('bridge-last-known'),
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
        const SizedBox(height: SmokeTokens.s2),
        StatRow(label: 'Device ID', value: _deviceId, mono: true),
        StatRow(label: 'Address', value: _address, mono: true),
        StatRow(label: 'Firmware', value: _firmware, mono: true),
        StatRow(label: 'Last reading', value: _lastReading),
        StatRow(
          label: 'Smoke X base',
          value: !_connected
              ? noValue
              : ((_snapshot?.paired ?? true) ? 'Paired' : 'Not paired'),
        ),
      ],
    ),
  );

  Widget _actionsCard(SmokeTokens t) => SmokeCard(
    padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
    child: Column(
      children: [
        _TileRow(
          key: const Key('bridge-identify'),
          icon: Icons.lightbulb_outline_rounded,
          title: 'Identify',
          // Present-and-disabled with its reason, not a button that lies: this
          // build has no identify control verb (rail R2).
          subtitle:
              'Not available yet — this bridge’s firmware has no '
              '“flash the screen” command.',
          onTap: null,
        ),
        Divider(height: 1, color: t.hairline),
        _TileRow(
          key: const Key('bridge-rerun-wifi'),
          icon: Icons.wifi_rounded,
          title: 'Run setup again',
          subtitle:
              'Change Wi-Fi or re-pair. Keeps your cooks and this phone’s '
              'Bluetooth bond.',
          onTap: () => context.go(AppRoutes.setup),
        ),
      ],
    ),
  );

  Widget _dangerCard(SmokeTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          left: SmokeTokens.s2,
          bottom: SmokeTokens.s2,
        ),
        child: Text(
          'DANGER ZONE',
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
      ),
      SmokeCard(
        padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
        child: Column(
          children: [
            _TileRow(
              key: const Key('bridge-restart'),
              icon: Icons.restart_alt_rounded,
              title: 'Restart the bridge',
              subtitle: _connected
                  ? 'Keeps everything — it reconnects on its own.'
                  : 'Needs a connection to the bridge.',
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Restart the bridge?',
                      body:
                          'It goes unreachable for a few seconds while it '
                          'reboots, then reconnects by itself.',
                      keeps: 'Everything.',
                      confirmLabel: 'Restart',
                      run: () => _runVerb(
                        DisruptiveVerb.restart,
                        const ControlCommand.reboot(),
                      ),
                    ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-forget'),
              icon: Icons.link_off_rounded,
              title: 'Forget this bridge',
              subtitle: 'This phone stops connecting to it.',
              onTap: () => _confirmThen(
                title: 'Forget this bridge on this phone?',
                body:
                    'Only this phone forgets it — the bridge keeps its '
                    'pairing, its network and every cook. You can add it '
                    'again later.',
                loses: 'The cooks cached on this phone.',
                confirmLabel: 'Forget',
                run: _forget,
              ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-factory-reset'),
              icon: Icons.delete_forever_rounded,
              title: 'Factory reset',
              subtitle: _connected
                  ? 'Wipes the bridge back to how it shipped.'
                  : 'Needs a connection to the bridge.',
              danger: true,
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Erase everything on the bridge?',
                      body:
                          'This wipes the bridge back to how it shipped and '
                          'cannot be undone. This phone will forget it too — '
                          'afterwards you set it up again like new.',
                      loses:
                          'Its pairing, its Wi-Fi, every cook on the bridge, '
                          'and this phone’s saved connection to it.',
                      confirmLabel: 'Erase everything',
                      run: () => _runVerb(
                        DisruptiveVerb.factoryReset,
                        const ControlCommand.factoryReset(),
                      ),
                    ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-power-off'),
              icon: Icons.power_settings_new_rounded,
              title: 'Power off',
              subtitle: _connected
                  ? 'Only the button on the bridge can turn it back on.'
                  : 'Needs a connection to the bridge.',
              danger: true,
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Power off the bridge?',
                      body:
                          'It stops answering on Wi-Fi and Bluetooth, and '
                          'nothing in this app can wake it. To turn it back '
                          'on you must physically hold the PRG button on the '
                          'bridge for about five seconds.',
                      loses: 'Remote access until someone walks over to it.',
                      confirmLabel: 'Power off',
                      run: () => _runVerb(
                        DisruptiveVerb.powerOff,
                        const ControlCommand.powerOff(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Open the cost sheet; run [run] only if the user confirms.
  Future<void> _confirmThen({
    required String title,
    required String body,
    String? keeps,
    String? loses,
    required String confirmLabel,
    required Future<void> Function() run,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CostSheet(
        title: title,
        body: body,
        keeps: keeps,
        loses: loses,
        confirmLabel: confirmLabel,
      ),
    );
    if (ok ?? false) {
      await run();
    }
  }
}

/// One device-page row: an icon, a title, a supporting line, and (when tappable)
/// a chevron. A null [onTap] renders it dimmed — the honest look of a control
/// that cannot act, kept visible with its reason rather than hidden.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onTap != null;
    final tint = danger ? StatusPalette.critical : t.textBody;
    final titleColor = !enabled
        ? t.textMuted
        : (danger ? StatusPalette.critical : t.textHi);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeTokens.s4,
          vertical: SmokeTokens.s3,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: enabled ? tint : t.chromeDim,
            ),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SmokeType.title.copyWith(color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: SmokeTokens.s2),
              Icon(Icons.chevron_right_rounded, size: 20, color: t.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// The confirm surface every disruptive verb opens (§13.5.6): the consequence
/// spelled out as what it *keeps* and what it *loses*, then Cancel / confirm.
/// The confirm is a plain destructive `FilledButton`, never the ember
/// [PrimaryAction] — the one ember button on a screen is a *forward* action,
/// not an erase (rail R1).
class _CostSheet extends StatelessWidget {
  const _CostSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.keeps,
    this.loses,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String? keeps;
  final String? loses;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SmokeTokens.radiusCard),
          ),
          border: Border.all(color: t.hairline),
        ),
        padding: const EdgeInsets.all(SmokeTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: SmokeType.displayS.copyWith(color: t.textHi)),
            const SizedBox(height: SmokeTokens.s2),
            Text(body, style: SmokeType.body.copyWith(color: t.textBody)),
            if (keeps != null) ...[
              const SizedBox(height: SmokeTokens.s3),
              _CostLine(
                icon: Icons.check_circle_outline_rounded,
                lead: 'Keeps',
                text: keeps!,
                tint: StatusPalette.positive,
              ),
            ],
            if (loses != null) ...[
              const SizedBox(height: SmokeTokens.s2),
              _CostLine(
                icon: Icons.remove_circle_outline_rounded,
                lead: 'Loses',
                text: loses!,
                tint: StatusPalette.critical,
              ),
            ],
            const SizedBox(height: SmokeTokens.s5),
            FilledButton(
              key: const Key('cost-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: StatusPalette.critical,
                foregroundColor: t.textHi,
                minimumSize: const Size(64, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SmokeTokens.radiusControl,
                  ),
                ),
              ),
              child: Text(confirmLabel, style: SmokeType.title),
            ),
            const SizedBox(height: SmokeTokens.s2),
            TextButton(
              key: const Key('cost-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: SmokeType.title.copyWith(color: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.icon,
    required this.lead,
    required this.text,
    required this.tint,
  });

  final IconData icon;
  final String lead;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: SmokeTokens.s2),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: SmokeType.bodySm.copyWith(color: t.textBody),
              children: [
                TextSpan(
                  text: '$lead ',
                  style: SmokeType.bodySm.copyWith(
                    color: t.textHi,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
