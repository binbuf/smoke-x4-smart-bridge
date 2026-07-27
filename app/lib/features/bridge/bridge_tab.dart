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
///
/// **Signal (A26).** The connection card names not just *which* link but *how
/// strong* it is, from [BridgeTransport.signal]. The two hops are labelled
/// separately and never conflated, because only one of them is measurable on
/// each lane: Bluetooth reads the phone↔bridge RSSI off the phone's own radio,
/// Wi-Fi can only report the bridge's uplink to the router, and on the
/// bridge's own hosted network neither end can see the other's radio at all —
/// so that state says so and shows the client count instead of inventing bars.
/// The rows poll only while this tab is the visible one; a signal meter is not
/// worth waking the radio behind three other screens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'verb_progress.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../core/core.dart';
import '../../data/prefs/bridge_prefs.dart';
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../settings/settings_screen.dart' show SettingsSection;
import '../shell/connection_sheet.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_session.dart';

class BridgeTab extends StatefulWidget {
  /// [session] and [prefs] are both optional so the shell's `const BridgeTab()`
  /// keeps compiling: a one-line import swap lands the real screen, and passing
  /// `session:` later lights up its live data. Tests inject a seeded session.
  const BridgeTab({
    super.key,
    this.session,
    this.prefs,
    this.transport,
    this.active,
  });

  /// Injected by tests. In the app it is null and the tab reads the one live
  /// session from [ShellScope] — the router builds this widget, so it can no
  /// longer be handed a session through its constructor.
  final ShellSession? session;
  final BridgePrefs? prefs;

  /// Test seam: the transport the identity and signal rows read from.
  /// Production passes nothing and the tab reaches through the session (or,
  /// failing that, the remembered address) exactly as it always has.
  final BridgeTransport? transport;

  /// Whether this tab is the one on screen. All four shell branches stay
  /// mounted, so "mounted" is not "visible" — and the signal poll must not run
  /// against a bridge nobody is looking at. Null reads it from [ShellScope]
  /// (and is true with no shell above, as in a bare test).
  final bool? active;

  @override
  State<BridgeTab> createState() => _BridgeTabState();
}

class _BridgeTabState extends State<BridgeTab> {
  /// Fetched for the firmware and device-id rows; null until it lands. Retried
  /// from [build] whenever the session connects after this tab first mounted —
  /// the shell rebuilds on every session change, so a late link still fills
  /// the rows.
  BridgeStatus? _status;

  /// A26 — the live signal, or null when it has not landed (or the last read
  /// failed). Never carried over from a previous link: a dBm from the Wi-Fi
  /// lane rendered under a Bluetooth heading is the same class of lie as the
  /// stale-IP bug this screen was rebuilt to kill.
  LinkSignal? _signal;

  /// Distinguishes "we have not measured this yet" from "we tried and could
  /// not" — two states that must never read the same.
  bool _signalFailed = false;

  /// The link the value in [_signal] was measured on. A dBm from the Wi-Fi
  /// lane rendered under a Bluetooth heading is the same class of lie as the
  /// stale-IP bug this screen was rebuilt to kill, so a swap discards it.
  LinkKind? _signalLink;

  bool _fetching = false;
  Timer? _poll;

  /// A signal that is older than this is not worth showing; the poll keeps it
  /// fresher than that whenever the tab is visible.
  static const Duration _pollEvery = Duration(seconds: 20);

  BridgePrefs? get _prefs => widget.prefs ?? AppEnv.instance?.prefs;

  /// The live session: injected (tests) or the shell's. Resolved per build
  /// because the scope is only reachable from a [BuildContext].
  ShellSession? _session;
  ShellSession? get _live => widget.session ?? _session;
  DashboardSnapshot? get _snapshot => _live?.snapshot;

  /// Visible right now — the poll's gate. Null until first resolved, which is
  /// what lets the initial arm happen exactly once whichever way it lands.
  bool? _activeResolved;
  bool get _active => _activeResolved ?? true;

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

  /// Both the session and the visibility come from [ShellScope], which is only
  /// reachable once dependencies are available — so the poll is (re)armed here
  /// rather than in `initState`.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = ShellScope.maybeOf(context);
    _syncActive();
  }

  /// An explicitly passed `active` (tests) changes through here.
  @override
  void didUpdateWidget(BridgeTab old) {
    super.didUpdateWidget(old);
    _syncActive();
  }

  void _syncActive() {
    final active = widget.active ?? ShellScope.isActive(context, 3);
    if (active == _activeResolved) {
      return;
    }
    final first = _activeResolved == null;
    _activeResolved = active;
    _syncPoll();
    // Whatever is on screen was last measured while the tab was hidden; land
    // a fresh reading before the first tick. Not on the first resolve —
    // `initState` already asked once.
    if (active && !first) {
      unawaited(_fetchDeviceInfo());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// The signal poll runs only while this tab is the visible one.
  void _syncPoll() {
    _poll?.cancel();
    _poll = _active
        ? Timer.periodic(_pollEvery, (_) => unawaited(_fetchDeviceInfo()))
        : null;
  }

  /// The transport this screen asks, in preference order: an injected one
  /// (tests), the shell session's open link (no second socket), then nothing —
  /// the remembered-address fallback is built per read in [_fetchDeviceInfo].
  BridgeTransport? get _open => widget.transport ?? _live?.bridge?.transport;

  void _maybeRefetch() {
    if (_status == null && !_fetching && _open != null) {
      unawaited(_fetchDeviceInfo());
    }
  }

  /// One `status()` + one `signal()` read, for the identity rows and the
  /// signal rows. Reuses the shell session's open transport when present (no
  /// second socket); otherwise builds one from the remembered address and
  /// closes it straight after — the same build-ask-close shape `AppConnection`
  /// uses to probe a lane.
  Future<void> _fetchDeviceInfo() async {
    if (_fetching) {
      return; // a pull landing on top of a tick must not double the reads
    }
    _fetching = true;
    try {
      final live = _open;
      if (live != null) {
        await _readInto(live, close: false);
        return;
      }
      final env = AppEnv.instance;
      final url = env?.prefs.lastBaseUrl;
      if (env == null || url == null || url.isEmpty) {
        // BLE, a fresh install, or a bare test — the rows fall back to prefs
        // and the signal block stays absent rather than showing a stale dBm.
        return;
      }
      await _readInto(env.transportFor(url), close: true);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _readInto(BridgeTransport t, {required bool close}) async {
    try {
      final s = await t.status();
      if (mounted) {
        setState(() => _status = s);
      }
    } on Object {
      // The device page still renders; the rows that needed it say `—`.
    }
    try {
      final sig = await t.signal();
      if (mounted) {
        setState(() {
          _signal = sig;
          _signalFailed = false;
          _signalLink = _snapshot?.link;
        });
      }
    } on Object {
      // Unreachable, or a link that dropped between the two reads. Drop the
      // old reading rather than keep presenting it as current.
      if (mounted) {
        setState(() {
          _signal = null;
          _signalFailed = true;
        });
      }
    }
    if (close) {
      await t.close();
    }
  }

  /// Pull-to-refresh (13 §13.5.2): ask the unit for a new value, then
  /// re-read this screen's own rows. The session reports its own failure
  /// through the shell's top bar; the device rows just refill or stay `—`.
  Future<void> _onRefresh() async {
    await _live?.refresh();
    await _fetchDeviceInfo();
  }

  /// Runs a disruptive verb inside the completion sheet (A24.9): send, then
  /// verify by watching the bridge actually go down, then a done state. The
  /// send goes through the shared session when present; otherwise a
  /// per-command transport that also serves as the probe.
  Future<void> _runVerb(DisruptiveVerb verb, ControlCommand cmd) async {
    final session = _live;
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

  /// The diagnostics gate. Five taps on the firmware row — the convention
  /// every Android user already knows from Build number.
  int _fwTaps = 0;

  void _tapFirmware() {
    _fwTaps++;
    if (_fwTaps < 5) {
      return;
    }
    _fwTaps = 0;
    context.push('${AppRoutes.bridge}/${SettingsSection.advanced.slug}');
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

  String get _deviceId => _status?.deviceId.isNotEmpty == true
      ? _status!.deviceId
      : (_live?.bridge?.bridgeId.isNotEmpty == true
            ? _live!.bridge!.bridgeId
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
    final children = (!_remembered && !_connected)
        ? [_connectionCard(t)]
        : [
            _connectionCard(t),
            const SizedBox(height: SmokeTokens.s4),
            _identityCard(t),
            const SizedBox(height: SmokeTokens.s4),
            _actionsCard(t),
            const SizedBox(height: SmokeTokens.s4),
            _dangerCard(t),
          ];
    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          key: const Key('bridge-tab'),
          // The short "no bridge yet" page has nothing to scroll, and a page
          // that cannot scroll cannot be pulled.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(SmokeTokens.s4),
          children: children,
        ),
      ),
    );
  }

  // ── the connection card: the state of right now, always first ─────────

  ({IconData icon, String title, String caption}) get _connectionState {
    final link = _snapshot?.link;
    final upgrading = _live?.liveLink?.upgrading ?? false;
    if (link == LinkKind.http) {
      final hosted = _snapshot?.netMode == 'ap';
      return (
        icon: hosted ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
        title: hosted
            ? 'Wi-Fi — the bridge’s own network'
            : 'Wi-Fi — your network',
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
        caption:
            'Can’t reach the bridge right now. The app keeps trying '
            'and reconnects on its own — Bluetooth first, then Wi-Fi.',
      );
    }
    return (
      icon: Icons.add_link_rounded,
      title: 'No bridge set up',
      caption:
          'This phone isn’t linked to a bridge yet. Setup takes a few '
          'minutes and starts over Bluetooth.',
    );
  }

  Widget _connectionCard(SmokeTokens t) {
    final s = _connectionState;
    final session = _live;
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
              Icon(
                s.icon,
                size: 26,
                color: _connected ? t.textHi : t.textMuted,
              ),
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
          if (_connected) ...[
            const SizedBox(height: SmokeTokens.s3),
            Divider(height: 1, color: t.hairline),
            const SizedBox(height: SmokeTokens.s3),
            _signalSection(t),
          ],
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
              onPressed: () => unawaited(showConnectionSheet(context, session)),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Manage connection'),
            ),
        ],
      ),
    );
  }

  // ── signal: how strong, and between which two things ──────────────────

  /// Only ever rendered while [_connected] — a dBm from a link that is down
  /// is a number about the past presented as the present.
  Widget _signalSection(SmokeTokens t) {
    // A transport swap (BLE → Wi-Fi, or a failover back) makes the last
    // reading a fact about a different radio. Hide it until the next poll
    // rather than relabel it.
    final sig = _signalLink == _snapshot?.link ? _signal : null;
    final onBle = _snapshot?.link == LinkKind.ble;
    final hosted =
        _snapshot?.link == LinkKind.http && _snapshot?.netMode == 'ap';
    final rows = <Widget>[];

    // 1. The hop the user is standing in. Bluetooth is the only lane that can
    //    measure it, and it measures it exactly.
    if (onBle) {
      rows.add(
        _SignalRow(
          key: const Key('bridge-signal-ble'),
          icon: Icons.bluetooth_rounded,
          title: 'Phone to bridge',
          dbm: sig?.linkDbm,
          kind: SignalKind.bluetooth,
          // Absent, never faked — and a read that failed must not go on
          // saying "measuring" as if it were still trying this instant.
          unknownWhy: _signalFailed
              ? 'Couldn’t measure it just now.'
              : 'Measuring…',
        ),
      );
    } else if (hosted) {
      // The bridge is the access point. It cannot see the phone's radio and
      // the phone will not report its own, so there is no number to show —
      // say that, and show the one fact the bridge does have.
      final n = sig?.apClients;
      rows.add(
        _SignalNote(
          key: const Key('bridge-signal-hosted'),
          icon: Icons.wifi_tethering_rounded,
          title: 'Phone to bridge',
          body: n == null
              ? 'On the bridge’s own network. Neither end can measure this '
                    'link’s strength.'
              : 'On the bridge’s own network — '
                    '${n == 1 ? "1 device" : "$n devices"} connected. Neither '
                    'end can measure this link’s strength.',
        ),
      );
    } else {
      // Joined Wi-Fi: the phone reaches the bridge through the router, and
      // Android will not hand this app its own RSSI without the location
      // permission the manifest promises never to take (A6.6).
      rows.add(
        const _SignalNote(
          key: Key('bridge-signal-wifi-phone'),
          icon: Icons.wifi_rounded,
          title: 'Phone to bridge',
          body:
              'Through your network. Android only reports this phone’s '
              'Wi-Fi strength to apps that ask for location, which this one '
              'does not.',
        ),
      );
    }

    // 2. The bridge's own uplink, on whichever lane could learn it. Over
    //    Bluetooth this still works — net_status carries it — which is how
    //    you find out the bridge has drifted out of Wi-Fi range while you
    //    are standing next to it.
    if (sig?.wifiDbm != null) {
      rows.add(
        _SignalRow(
          key: const Key('bridge-signal-wifi'),
          icon: Icons.router_rounded,
          title: (sig!.ssid.isEmpty)
              ? 'Bridge to your network'
              : 'Bridge to ${sig.ssid}',
          dbm: sig.wifiDbm,
          kind: SignalKind.wifi,
          unknownWhy: '',
        ),
      );
    }

    return Column(
      key: const Key('bridge-signal'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SIGNAL', style: SmokeType.label.copyWith(color: t.textMuted)),
        const SizedBox(height: SmokeTokens.s2),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: SmokeTokens.s3),
          rows[i],
        ],
      ],
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
        // Five taps on the firmware row opens the diagnostics console —
        // packet log, novelty log, app log. It is a real support tool and it
        // must stay reachable in the field without a cable (08 §8.2), but it
        // is not a peer of "Probes" in a production settings list, which is
        // where it used to sit.
        GestureDetector(
          key: const Key('bridge-diagnostics-gate'),
          behavior: HitTestBehavior.opaque,
          onTap: _tapFirmware,
          child: StatRow(label: 'Firmware', value: _firmware, mono: true),
        ),
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

  /// The safe actions, and the way into every device settings page.
  ///
  /// The permanently-disabled "Identify" row that used to lead this card is
  /// gone. Present-and-disabled-with-a-reason is the right discipline for a
  /// control the user is *looking for* — battery calibration, which they came
  /// to settings to find — and the wrong one for a control they never knew
  /// existed: there it is just a dead row at the top of the card, teaching
  /// that the card cannot be trusted. There is no identify verb in this
  /// firmware, so there is no row.
  Widget _actionsCard(SmokeTokens t) => SmokeCard(
    padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
    child: Column(
      children: [
        for (final s in SettingsSection.deviceSections) ...[
          _TileRow(
            key: Key('bridge-section-${s.name}'),
            icon: s.icon,
            title: s.title,
            subtitle: s.subtitle,
            onTap: () => context.push('${AppRoutes.bridge}/${s.slug}'),
          ),
          Divider(height: 1, color: t.hairline),
        ],
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
        // "DANGER ZONE" is a sysadmin idiom, shouted. The four cost sheets
        // underneath already carry the weight, and they do it calmly.
        child: Text(
          'RESET AND POWER',
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
                      cancelLabel: 'Leave it running',
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
                cancelLabel: 'Keep this bridge',
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
                      cancelLabel: 'Don’t erase',
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
                      cancelLabel: 'Leave it on',
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
    required String cancelLabel,
    required Future<void> Function() run,
  }) async {
    final ok = await showCostSheet(
      context,
      title: title,
      body: body,
      keeps: keeps,
      loses: loses,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
    if (ok) {
      await run();
    }
  }
}

/// One measured hop: the two ends it spans, the bars, the dBm, and the word.
///
/// A null [dbm] renders [unknownWhy] rather than bars — "we have not measured
/// this yet" and "this link is weak" must never look the same.
class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.icon,
    required this.title,
    required this.dbm,
    required this.kind,
    required this.unknownWhy,
    super.key,
  });

  final IconData icon;
  final String title;
  final int? dbm;
  final SignalKind kind;
  final String unknownWhy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final value = dbm;
    final level = value == null ? null : signalLevel(value, kind: kind);
    final advice = level == null ? '' : signalAdvice(level, kind: kind);
    return Semantics(
      label: value == null
          ? '$title, not measured'
          : '$title, ${signalLabel(level!)}, ${value.abs()} dBm below zero',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: t.textMuted),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SmokeType.body.copyWith(color: t.textBody)),
                if (value == null)
                  Text(
                    unknownWhy.isEmpty ? 'Not measured yet.' : unknownWhy,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  )
                else ...[
                  Row(
                    children: [
                      SignalBars(bars: signalBars(value, kind: kind)),
                      const SizedBox(width: SmokeTokens.s2),
                      Text(
                        signalLabel(level!),
                        style: SmokeType.title.copyWith(color: t.textHi),
                      ),
                      const SizedBox(width: SmokeTokens.s2),
                      Text(
                        formatDbm(value),
                        style: SmokeType.mono.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                  if (advice.isNotEmpty)
                    Text(
                      advice,
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A hop nobody can measure, stated plainly. This is the honest alternative
/// to drawing four grey bars and letting the user read them as "no signal".
class _SignalNote extends StatelessWidget {
  const _SignalNote({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: t.textMuted),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SmokeType.body.copyWith(color: t.textBody)),
              Text(body, style: SmokeType.bodySm.copyWith(color: t.textMuted)),
            ],
          ),
        ),
      ],
    );
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
            Icon(icon, size: 22, color: enabled ? tint : t.chromeDim),
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
