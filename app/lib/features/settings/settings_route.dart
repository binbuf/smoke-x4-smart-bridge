/// The settings composition root, on the **shared** connection (newapp §F,
/// §I.1 Phase 0; 16 §16.6).
///
/// A single route with an inner section stack, so every page shares one link
/// and one set of reads. Everything it renders is one of the pure views in this
/// folder, which is what keeps them testable with no transport at all.
///
/// ## The three lies this file exists to have stopped telling
///
/// **1. A form that reported success and wrote nothing.** This route used to
/// build its *own* `HttpTransport` from the remembered base URL. On a
/// Bluetooth-only setup there is no base URL, so `_transport` stayed null, and
/// every write went through a null-aware `_transport?.configure(...)` — saving
/// probe settings appeared to succeed while nothing left the phone. The
/// transport now comes from [ShellScope], the same link the reader and the
/// Device tab use.
///
/// **2. A write reported as saved on the strength of a 200.** Every write here
/// resolves to a [WriteOutcome], decided by reading the bridge back — probe
/// configuration through `live()`, everything else through `deviceConfig()`.
/// [WriteOutcome.unverified] survives for the one case that is genuinely
/// unknowable: a lane that carries the write and cannot carry the read, which
/// is Bluetooth. The old code said "Saved" for every case including that one.
///
/// **3. A constructor default rendered as a device fact.** The worst instance
/// was `NetMode _netMode = NetMode.sta`, rendered as "Joined a network" at the
/// top of the Network page while the bridge sat there hosting its own access
/// point — the exact bug 16 §16.6 names. It is gone: [_netMode] is `NetMode?`,
/// starts null, and is only ever written from something the **device said** —
/// its `net` push over either lane, or the shell's snapshot, which is itself
/// derived from that push. Null renders `—`.
///
/// The same audit ran over every other field on this screen, and it found four
/// more of the same class. They are marked at their declarations.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart' show SmokeBridgeApp, ThemeProfile;
import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../core/format.dart';
import '../../data/local/database.dart' show CacheStats;
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';
import '../../data/transport/http_transport.dart';
import '../../domain/entities/entities.dart';
import '../bridge/verb_progress.dart';
import '../shell/shell_scope.dart';
import 'netmode_switch.dart';
import 'netmode_switch_sheet.dart';
import 'settings_data.dart';
import 'settings_diagnostics.dart';
import 'settings_kit.dart';
import 'settings_mqtt.dart';
import 'settings_network.dart';
import 'settings_power.dart';
import 'settings_probes.dart';
import 'settings_screen.dart';

class SettingsRoute extends StatefulWidget {
  const SettingsRoute({super.key, this.initialSection, this.embedded = false});

  /// Open straight onto one section — how `/device/settings/:section` reaches
  /// these pages. Null keeps the section-list behaviour.
  final SettingsSection? initialSection;

  /// True when pushed inside the Device branch: back is a branch pop, and
  /// there is no section list to return to.
  final bool embedded;

  @override
  State<SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<SettingsRoute> {
  SettingsSection? _section;
  BridgeTransport? _transport;
  StreamSubscription<BridgeEvent>? _events;

  // ── read from the device; null until it answers ──────────────────────
  BridgeStatus? _status;
  LiveState? _live;
  List<Probe> _probes = const [];

  /// **Default-as-fact #5, and the one that could destroy a configuration.**
  /// [_probes] is `const []` until `live()` lands, and the probe form seeded
  /// four blank `Probe(n:)` from it — then "Save to the bridge" wrote those
  /// blanks over the user's real names, roles and targets and reported
  /// success, because the read-back matched the blanks it had just written.
  /// The form is gated on this flag and does not exist until it is true.
  bool _probesKnown = false;

  LinkSignal? _signal;

  /// `GET /api/v1/config/alarms` — which of the bridge's nine rules are on.
  ///
  /// **Default-as-fact #6.** This was a `const` map of six rules, all true,
  /// handed straight to the view: "6 of 6 on" rendered as a statement about a
  /// device over any lane, on a phone that had never met a bridge, and naming
  /// six of the nine §G.1 rules at that. Null until the bridge answers.
  Map<String, bool>? _deviceRules;

  /// A16 — Home Assistant. [_mqttKnown] is separate from `_mqtt != null`
  /// because [MqttConfig]'s own constructor carries port 1883 and the prefix
  /// `smokebridge`; handing the view a default-constructed one would put two
  /// values on screen that the bridge never reported. **Default-as-fact #2.**
  MqttConfig? _mqtt;
  bool _mqttKnown = false;

  /// **Default-as-fact #1, and the one 16 §16.6 names.** Was
  /// `NetMode _netMode = NetMode.sta`, rendered as "Joined a network" over a
  /// bridge that was hosting its own. Now: null until a `net` push, a shell
  /// snapshot, or a hosted-network client count says otherwise.
  NetMode? _netMode;
  String _netSsid = '';
  String _netIp = '';
  String _apPsk = '';
  int? _revertInS;
  String _netRecovery = '';

  /// The manual-address escape hatch, mid-flight and after it failed.
  bool _manualAddressBusy = false;
  String _manualAddressError = '';

  /// `GET /api/v1/config/device`, the read half — the bridge's own screen
  /// timeout, its light, its saver mode and its retention limit.
  ///
  /// [DeviceConfig.unknown] until it answers, and **permanently unknown over
  /// Bluetooth**, which returns it rather than throwing. That is the right
  /// shape for this screen: every field is nullable, so an unread value lands
  /// on `—` beside the sentence that says why, and no page has to handle a
  /// thrown read for a row that was only ever going to say `—`.
  DeviceConfig _device = DeviceConfig.unknown;

  /// **Default-as-fact #3.** The saver mode was write-only in every direction:
  /// nothing read it back, so the page separated what was *asked for* from
  /// what the bridge reports it is *doing*, and [_saverConfirmed] kept the two
  /// apart. `deviceConfig()` now supplies the missing read, so on Wi-Fi this
  /// flag is finally true and the row states a fact. It stays false over
  /// Bluetooth — where it is still the honest answer.
  String? _saver;
  bool _saverConfirmed = false;

  /// From the device's `power` push, which is a measurement rather than a
  /// setting. Null until one arrives.
  bool? _saverEngaged;
  int? _socPct;
  bool? _charging;

  /// **Default-as-fact #4.** `paired` was read as `_status?.paired ?? false`
  /// — "not paired" rendered for a bridge that had simply not answered yet,
  /// on the page whose whole job is to tell you whether it is paired. Now
  /// nullable all the way to the row.
  bool? get _paired => _status?.paired;

  // ── phone-side facts. Genuinely known, so genuinely rendered ──────────
  String _units = 'F';
  ThemeProfile _themeProfile = ThemeProfile.dark;
  bool _quietHours = true;
  bool _monitoring = true;
  bool _batteryExempt = false;

  // ── OTA ──────────────────────────────────────────────────────────────
  int? _otaPct;
  String _otaPhase = '';
  String _otaRefusal = '';

  // ── the phone's own cache. Read from drift, never from the bridge ─────
  CacheStats _cache = CacheStats.empty;
  bool _clearing = false;
  List<(String, String)> _syncRows = const [];
  String _rolloverLoss = '';

  /// §F's transport column, resolved once for every page that needs it.
  SettingsLane get _lane => switch (_transport) {
    null => SettingsLane.none,
    BleTransport() => SettingsLane.bluetooth,
    _ => SettingsLane.wifi,
  };

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _units = AppEnv.instance?.prefs.displayUnits ?? 'F';
    _themeProfile = ThemeProfile.fromName(AppEnv.instance?.prefs.themeProfile);
    _quietHours = AppEnv.instance?.prefs.quietHoursEnabled ?? true;
    _monitoring = AppEnv.instance?.prefs.monitoringEnabled ?? true;
    unawaited(_loadCache());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _adoptSharedTransport();
    _adoptShellFacts();
  }

  /// Takes the shell's live transport. Called from `didChangeDependencies` as
  /// well as `initState`, because the supervisor can swap Bluetooth for Wi-Fi
  /// while this screen is open and a page holding the old link would keep
  /// writing down a socket nobody is listening to.
  void _adoptSharedTransport() {
    final shared = ShellScope.maybeOf(context)?.bridge?.transport;
    if (shared != null && !identical(shared, _transport)) {
      _transport = shared;
      unawaited(_events?.cancel());
      _events = shared.events.listen(_onEvent);
      unawaited(_load());
    }
  }

  /// Facts the shell already holds. The **network mode** is the important one:
  /// the shell's snapshot derives it from the device's `net` push, or from the
  /// hosted network's fixed address — both observations, neither a default.
  void _adoptShellFacts() {
    final snap = ShellScope.maybeOf(context)?.snapshot;
    if (snap == null) {
      return;
    }
    final mode = switch (snap.netMode) {
      'ap' => NetMode.ap,
      'sta' => NetMode.sta,
      _ => null,
    };
    final address = snap.address;
    // A null here is "the shell has not resolved one" — it never overwrites a
    // mode the device itself already stated on this screen.
    if ((mode != null && mode != _netMode) ||
        (address.isNotEmpty && address != _netIp)) {
      setState(() {
        if (mode != null) {
          _netMode = mode;
        }
        if (address.isNotEmpty) {
          _netIp = address;
        }
      });
    }
  }

  /// The device's own push frames. `net` is the authoritative statement of
  /// which network it is on — over Bluetooth it is the only one there is.
  void _onEvent(BridgeEvent e) {
    if (!mounted) {
      return;
    }
    switch (e) {
      case BridgeNetEvent(:final mode, :final ip):
        setState(() {
          _netMode = switch (mode) {
            'ap' => NetMode.ap,
            'sta' => NetMode.sta,
            _ => _netMode,
          };
          if (ip != null && ip.isNotEmpty) {
            _netIp = ip;
          }
        });
      case BridgePowerEvent(:final socPct, :final charging, :final saver):
        setState(() {
          _socPct = socPct;
          _charging = charging;
          _saverEngaged = saver;
        });
      case BridgeOtaEvent(:final phase, :final pct):
        setState(() {
          _otaPhase = phase;
          _otaPct = pct;
        });
      case BridgePairingEvent():
        unawaited(_refreshStatus());
      default:
        break;
    }
  }

  Future<void> _load() async {
    unawaited(_loadCache());
    final t = _transport;
    if (AppEnv.instance == null || t == null) {
      // No shared link yet. The pages that need the device say so
      // individually; nothing here fabricates a second connection.
      return;
    }
    await _refreshStatus();
    await _refreshDeviceConfig();
    try {
      final signal = await t.signal();
      if (mounted) {
        setState(() {
          _signal = signal;
          if (signal.ssid.isNotEmpty) {
            _netSsid = signal.ssid;
          }
          // A client count only exists on a hosted network. It is a fact the
          // device reported, so it may settle the mode — an inference from a
          // measurement, never from a default.
          if (signal.apClients != null) {
            _netMode = NetMode.ap;
          }
        });
      }
    } on Object {
      // A signal read is a round trip and may fail on its own; the rest of
      // the page still renders.
    }
    if (t.capabilities.mqtt) {
      try {
        final mqtt = await t.mqttConfig();
        if (mounted) {
          setState(() {
            _mqtt = mqtt;
            _mqttKnown = true;
          });
        }
      } on Object {
        // The Home Assistant page renders `—` rather than defaults.
      }
    }
    await _refreshAlarmRules();
  }

  /// The bridge's own rule set, for the summary row on the Alarms page.
  ///
  /// The rule *editor* has read this since §G.3; the settings page beside it
  /// was still printing a constant. Bluetooth throws
  /// [BridgeUnsupportedException] here, which is the right answer — the row
  /// then says `—` and "the bridge hasn't reported its rules yet", which is
  /// exactly true on that lane.
  Future<void> _refreshAlarmRules() async {
    final t = _transport;
    if (t == null) {
      return;
    }
    try {
      final config = await t.alarmConfig();
      final rules = config['rules'];
      if (rules is! List || !mounted) {
        return;
      }
      final byId = <String, bool>{};
      for (final r in rules.whereType<Map<Object?, Object?>>()) {
        final id = r['rule'];
        if (id is String) {
          byId[id] = r['enabled'] == true;
        }
      }
      setState(() => _deviceRules = byId);
    } on Object {
      // A lane that cannot read them leaves the row on `—` with the sentence
      // that says the bridge has not reported them. That is the honest state,
      // and it is the state this row spent its whole life lying about.
    }
  }

  Future<void> _refreshStatus() async {
    final t = _transport;
    if (t == null) {
      return;
    }
    try {
      final status = await t.status();
      final live = await t.live();
      if (mounted) {
        setState(() {
          _status = status;
          _live = live;
          _probes = live.probes;
          // The device has now described its jacks, so the probe form is
          // allowed to exist. Everything before this point was `const []`.
          _probesKnown = true;
          if (status.socPct != null) {
            _socPct = status.socPct;
          }
          _charging ??= status.charging;
        });
      }
    } on Object {
      // Settings still renders: the pages that need the device say so
      // individually rather than the whole screen failing.
    }
  }

  /// Reads the bridge's own settings and **adopts the saver mode as a
  /// confirmed fact** when it reports one.
  ///
  /// [_saverConfirmed] is set only here. A user's tap never sets it, which is
  /// what keeps "you asked for Always saving" and "the bridge is running
  /// Always saving" from collapsing into the same sentence on a lane that
  /// cannot tell them apart.
  Future<void> _refreshDeviceConfig() async {
    final t = _transport;
    if (t == null) {
      return;
    }
    try {
      final device = await t.deviceConfig();
      if (!mounted) {
        return;
      }
      setState(() {
        _device = device;
        final reported = device.batterySaver;
        if (reported != null) {
          _saver = reported.name;
          _saverConfirmed = true;
        }
      });
    } on Object {
      // A lane that refuses the read leaves every row on `—` with its reason,
      // which is the state the page is built to render anyway.
    }
  }

  /// The cache's size, read straight from drift. Deliberately outside any
  /// link guard: a phone that has never been paired still has a cache page,
  /// and one whose bridge is unreachable must still be able to clear it.
  Future<void> _loadCache() async {
    final db = AppEnv.instance?.db;
    if (db == null) {
      return;
    }
    final stats = await db.cacheStats();
    final bridgeId = await db.sessionDao.knownBridgeId();
    final rows = <(String, String)>[];
    final gaps = <String>[];
    if (bridgeId != null) {
      final sessions = await db.sessionDao.allSessions(bridgeId);
      for (final session in sessions.take(3)) {
        final sync = await db.syncStateDao.forSession(bridgeId, session.id);
        if (sync != null) {
          rows.add((
            'Cook ${session.id} — copied up to',
            formatDuration(sync.highWaterT),
          ));
          if (sync.deviceMinT != null && sync.deviceMaxT != null) {
            rows.add((
              'Cook ${session.id} — the bridge holds',
              '${formatDuration(sync.deviceMinT!)} to '
                  '${formatDuration(sync.deviceMaxT!)}',
            ));
          }
        }
        final holes = await db.syncStateDao.forBridgeSession(
          bridgeId,
          session.id,
        );
        for (final g in holes.where((g) => g.reason.isPermanent)) {
          gaps.add('cook ${session.id}, ${formatDuration(g.durationS)}');
        }
      }
    }
    if (mounted) {
      setState(() {
        _cache = stats;
        _syncRows = rows;
        _rolloverLoss = gaps.join('; ');
      });
    }
  }

  Future<void> _clearCache() async {
    final db = AppEnv.instance?.db;
    if (db == null) {
      return;
    }
    setState(() => _clearing = true);
    try {
      await db.clearCachedCooks();
      await _loadCache();
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  // ── write, read back, then report ────────────────────────────────────

  /// **Write, then read back, then report** (16 §16.4 rule 10, §16.6).
  ///
  /// The shape this replaces was `await _transport?.configure(cfg);
  /// setState(...)` — a null-aware call whose failure mode is silence and
  /// whose success mode is unverified. This one refuses when there is no link
  /// and says so; writes; re-reads `live()` and **adopts what the device
  /// actually reports**; and then reports which of the six things happened.
  ///
  /// **Two read-backs, because there are two reads.** Probe configuration
  /// comes back on `live()`; everything else comes back on `deviceConfig()`.
  /// A write that touches both has to satisfy both.
  ///
  /// [WriteOutcome.unverified] survives, and it is no longer a euphemism for
  /// "we did not look". It now means one specific, true thing: **the lane
  /// carried the write and cannot carry the read**. Bluetooth answers
  /// `DeviceConfig.unknown`, so a units change over Bluetooth still reports
  /// "the app can't confirm it stuck" — while the same change over Wi-Fi is
  /// checked field by field and reports "Saved to the bridge", meaning it.
  Future<WriteOutcome> _writeAndVerify(
    BridgeConfig cfg, {
    required String what,
  }) async {
    final t = _transport;
    if (t == null) {
      return _report(WriteOutcome.noLink, what);
    }
    try {
      await t.configure(cfg);

      final expected = cfg.probes;
      if (expected != null) {
        final live = await t.live();
        if (!mounted) {
          return WriteOutcome.unverified;
        }
        setState(() {
          _live = live;
          _probes = live.probes;
          _probesKnown = true;
        });
        if (!probeWriteWasHonoured(expected, live.probes)) {
          return _report(WriteOutcome.changedByDevice, what);
        }
      }

      if (touchesDeviceConfig(cfg)) {
        final device = await t.deviceConfig();
        if (!mounted) {
          return WriteOutcome.unverified;
        }
        setState(() {
          _device = device;
          final reported = device.batterySaver;
          if (reported != null) {
            _saver = reported.name;
            _saverConfirmed = true;
          }
        });
        return _report(switch (deviceWriteVerdict(device, cfg)) {
          true => WriteOutcome.verified,
          false => WriteOutcome.changedByDevice,
          // The device said nothing about the field we wrote. Not a
          // failure, and emphatically not a success.
          null => WriteOutcome.unverified,
        }, what);
      }
      return _report(WriteOutcome.verified, what);
    } on BridgeUnsupportedException catch (e) {
      return _report(WriteOutcome.refused, e.what);
    } on Object {
      return _report(WriteOutcome.failed, what);
    }
  }

  WriteOutcome _report(WriteOutcome outcome, String what) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(writeOutcomeMessage(outcome, what)),
        duration: Duration(seconds: outcome == WriteOutcome.verified ? 3 : 6),
      ),
    );
    return outcome;
  }

  // `_power(cmd)` used to live here: send, swallow every exception, report
  // nothing. That is the right shape for D15's three disruptive verbs — the
  // bridge answers *before* it acts and then drops the link, so an error is as
  // likely to be the success path as a failure — and those three now run
  // inside the A24.9 sheet, which confirms them by watching the bridge go
  // down. Pair and unpair were sharing it, and they do not drop the link at
  // all, so they got the silence without the reason for it.

  /// Pair and unpair — **awaited, and checked against `paired` afterwards.**
  ///
  /// These went through [_power], whose whole contract is "the bridge answers
  /// and then drops the link, so an error here is as likely to be the success
  /// path as a failure". That is true of reboot, power off and factory reset.
  /// It is not true of these two: the link stays up, and a re-scan that found
  /// nothing reported absolutely nothing — the button dimmed for a moment and
  /// the page carried on saying whatever it had said before.
  ///
  /// So this compares the bridge's own `paired` either side of the call and
  /// says which of the four things happened. Nothing is claimed from the fact
  /// that a request returned.
  Future<void> _pairing({required bool pair}) async {
    final t = _transport;
    if (t == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final before = _status?.paired;
    try {
      await t.control(
        pair ? const ControlCommand.pair() : const ControlCommand.unpair(),
      );
      await _refreshStatus();
      if (!mounted) {
        return;
      }
      final after = _status?.paired;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(switch ((pair, after)) {
            (_, null) =>
              'The bridge took that, but it hasn’t said whether it is paired.',
            (true, true) when before == true =>
              'Still paired to the same base station.',
            (true, true) =>
              'Paired. Readings arrive from the base station now.',
            (true, false) =>
              'The bridge didn’t find a base station. Put yours into sync '
                  'mode and try again.',
            (false, false) => 'Unpaired. Readings stop until you pair again.',
            (false, true) =>
              'The bridge still reports a base station. Nothing changed.',
          }),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('The bridge didn’t take that. Nothing changed.'),
        ),
      );
    }
  }

  /// Silencing an alarm is a write, so it is sent, read back and reported.
  ///
  /// It used to be `_transport?.control(...) ?? Future.value()` inside an
  /// `unawaited` — a fully enabled "Silence" button that did nothing at all
  /// with no link, swallowed every failure when there was one, and never
  /// re-read the status it had just changed.
  Future<void> _ack(Alarm alarm) async {
    final t = _transport;
    if (t == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await t.control(ControlCommand.ackAlarm(alarmId: alarm.id));
      await _refreshStatus();
      if (!mounted) {
        return;
      }
      final back = (_status?.alarms ?? const <Alarm>[])
          .where((a) => a.id == alarm.id)
          .firstOrNull;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            back == null || back.acked
                ? 'Silenced. It stays in the list until it clears.'
                : 'The bridge hasn’t silenced that one. It is still sounding.',
          ),
        ),
      );
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'The bridge didn’t take that. The alarm is still sounding.',
          ),
        ),
      );
    }
  }

  Future<void> _runDisruptive(DisruptiveVerb verb, ControlCommand cmd) async {
    final t = _transport;
    if (t == null || !mounted) {
      return;
    }
    await showVerbProgressSheet(
      context,
      verb: verb,
      send: () => t.control(cmd),
      probe: () => t.status(),
      // A confirmed factory reset forgets the bridge on this phone too — the
      // app must never keep claiming a bridge the reset just erased.
      onCompleted: verb == DisruptiveVerb.factoryReset
          ? () => unawaited(
              AppEnv.instance?.prefs.forgetBridge() ?? Future<void>.value(),
            )
          : null,
      onSetUpAgain: verb == DisruptiveVerb.factoryReset
          ? () {
              if (mounted) {
                context.go(AppRoutes.setup);
              }
            }
          : null,
    );
  }

  /// §16.3 situation 9's remedy, verified: set the clock, then re-read `live()`
  /// and only claim it worked if the bridge now reports a plausible date.
  Future<void> _setClock() async {
    final t = _transport;
    if (t == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await t.control(
        ControlCommand.setTime(unixMs: DateTime.now().millisecondsSinceEpoch),
      );
      final live = await t.live();
      if (!mounted) {
        return;
      }
      setState(() => _live = live);
      final ok =
          live.unixMs != null &&
          live.unixMs! >= DiagnosticsSettingsView.plausibleFrom;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'The bridge knows the time now. Cooks from here on are dated.'
                : 'The bridge took the time but still isn’t reporting a date.',
          ),
        ),
      );
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(content: Text('The bridge didn’t take the time.')),
      );
    }
  }

  // ── §E.3 — the network switch, with a rollback ───────────────────────

  /// Runs §E.3's wizard rather than the old fire-and-forget `onApply`.
  ///
  /// The old path posted the change down the link it was about to kill, set
  /// `_netMode` to whatever had been asked for, and reported success — so a
  /// wrong password produced a bridge nobody could reach, under a screen
  /// saying it had joined. Now the device arms a rollback, the app races the
  /// expected new endpoint, and the mode is adopted **only on a commit**.
  Future<void> _switchMode(NetMode mode, String ssid, String psk) async {
    final t = _transport;
    if (t == null) {
      return;
    }
    final target = mode == NetMode.ap ? NetworkMode.ap : NetworkMode.sta;
    var handedBackPsk = '';
    final machine = NetModeSwitch(
      apply: (m, s, p) async {
        final key = await t.applyNetwork(
          mode: m,
          ssid: s,
          psk: p,
          revertAfterS: kNetModeRevertS,
        );
        handedBackPsk = key;
        return key;
      },
      // A lane wins only on a real `GET /status` 200 — never on a socket that
      // merely opened.
      probe: () async {
        await t.status();
        return true;
      },
      commit: t.commitNetworkMode,
    );

    setState(() {
      _netRecovery = '';
      _revertInS = null;
    });

    final result = await showNetModeSwitchSheet(
      context,
      machine: machine,
      mode: target,
      ssid: ssid,
      psk: psk,
    );
    if (!mounted || result == null) {
      return;
    }

    switch (result.phase) {
      case NetSwitchPhase.committed:
        setState(() {
          _netMode = mode;
          _netSsid = mode == NetMode.ap ? _netSsid : ssid;
          _apPsk = handedBackPsk;
          _revertInS = null;
          _netRecovery = '';
        });
        await _load();
      case NetSwitchPhase.revertPending:
        setState(() {
          // The mode is NOT adopted. Nothing confirmed it, and the device is
          // about to put back what worked.
          _revertInS = result.revertInS;
          _netRecovery =
              'The bridge took the change but this phone never found it again. '
              'It goes back to the network that was working in '
              '${result.revertInS} seconds, on its own. '
              '${mode == NetMode.sta ? 'Check the network name and password, then try again.' : 'Your phone may need to join the bridge’s own network first.'}';
        });
      case NetSwitchPhase.refused:
        setState(
          () => _netRecovery = result.detail.isEmpty
              ? 'The bridge refused that change. Nothing was altered.'
              : '${result.detail} Nothing was altered.',
        );
      case NetSwitchPhase.requesting:
      case NetSwitchPhase.reconnecting:
        break;
    }
  }

  /// The escape hatch, **verified before it is believed** (05 §5.8, 08 §8.4).
  ///
  /// The row's own subtitle promises "Reconnects straight away and remembers
  /// it". What it did was record the string and `context.go('/live')` — so one
  /// mistyped digit recorded a dead address, navigated away from the page that
  /// could fix it, and left the reader on `/live` with no message at all
  /// (16 §16.4 rule 10). A `GET /status` on the address is one round trip and
  /// it is the difference between a promise and a claim.
  Future<void> _useManualAddress(String address) async {
    setState(() {
      _manualAddressBusy = true;
      _manualAddressError = '';
    });
    final probe = HttpTransport(address);
    try {
      final status = await probe.status();
      await AppEnv.instance?.prefs.recordConnection(
        address,
        bridgeId: status.deviceId.isEmpty ? null : status.deviceId,
      );
      if (mounted) {
        context.go(AppRoutes.live);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _manualAddressError =
              'Nothing answered at that address. Check it against the '
              'bridge’s own screen, which shows the one it is using.',
        );
      }
    } finally {
      await probe.close();
      if (mounted) {
        setState(() => _manualAddressBusy = false);
      }
    }
  }

  /// A12.6 — pick a `.bin` through the injected seam and stream it to
  /// `POST /api/v1/ota`. Progress comes from the device's own `ota` frames,
  /// handled in [_onEvent]: the device is authoritative about its phase.
  Future<void> _uploadFirmware({required bool force}) async {
    final source = AppEnv.instance?.firmwareImage;
    final transport = _transport;
    if (source == null || transport == null) {
      return;
    }
    final image = await source();
    if (image == null) {
      return; // the user cancelled the picker
    }
    setState(() {
      _otaRefusal = '';
      _otaPhase = 'starting';
      _otaPct = 0;
    });
    try {
      await transport.uploadFirmware(
        image.bytes,
        lengthBytes: image.lengthBytes,
        force: force,
      );
    } on BridgeApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _otaPct = null;
        _otaPhase = '';
        // The bridge's own refusal (its 409 session_active message). The view
        // turns it into the two-tier copy and the deliberate force button,
        // which only appears while a cook is active.
        _otaRefusal = err.message;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _otaPct = null;
        _otaPhase = '';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    // The supervisor owns this link's lifetime now. Closing it here would take
    // the live readings down every time somebody backed out of settings.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = _section;
    // Deep-linked at a section: there is no section list behind it, so back is
    // a branch pop and go_router supplies the button.
    final pinned = widget.initialSection != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(section?.title ?? 'Settings'),
        leading: pinned
            ? null
            : IconButton(
                key: const Key('settings-back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => section == null
                    ? context.go(AppRoutes.device)
                    : setState(() => _section = null),
              ),
      ),
      body: SafeArea(child: _body(section)),
    );
  }

  Widget _body(SettingsSection? section) => switch (section) {
    null => SettingsHomeView(onOpen: (s) => setState(() => _section = s)),

    SettingsSection.identity => IdentitySettingsView(
      deviceId: _status?.deviceId,
      model: _status?.model,
      firmware: _status?.fw,
      address: _netIp.isEmpty ? null : _netIp,
      paired: _paired,
      controlReason: _lane.control,
      onPair: _transport == null ? null : () => unawaited(_pairing(pair: true)),
      onUnpair: _transport == null
          ? null
          : () => unawaited(_pairing(pair: false)),
    ),

    SettingsSection.probes => ProbeSettingsView(
      probes: _probes,
      probesKnown: _probesKnown,
      celsius: _units == 'C',
      // §F's transport column: `BleTransport` has no `device_control` op for
      // probe names or roles, and v1 leaves that surface Wi-Fi-only rather
      // than silently dropping the write.
      unsupportedReason: _lane.probes,
      onOpenAlarmRules: () => context.push(AppRoutes.deviceAlarms),
      onSave: (probes) => _writeAndVerify(
        BridgeConfig(probes: probes),
        what: 'probe names and targets',
      ),
    ),

    SettingsSection.alarms => AlarmSettingsView(
      quietHours: _quietHours,
      onQuietHours: (v) async {
        setState(() => _quietHours = v);
        await AppEnv.instance?.prefs.setQuietHours(v);
      },
      monitoring: _monitoring,
      onMonitoring: (v) async {
        setState(() => _monitoring = v);
        await AppEnv.instance?.prefs.setMonitoringEnabled(v);
      },
      batteryExempt: _batteryExempt,
      onRequestBatteryExempt: () async {
        final ok = await AppEnv.instance?.foregroundService
            ?.requestIgnoreBatteryOptimizations();
        if (mounted) {
          setState(() => _batteryExempt = ok ?? false);
        }
      },
      onOpenRules: () => context.push(AppRoutes.deviceAlarms),
      deviceRules: _deviceRules,
      alarms: _status?.alarms ?? const [],
      ackReason: _lane.control,
      onAck: (a) => unawaited(_ack(a)),
    ),

    SettingsSection.display => DisplaySettingsView(
      units: _units,
      deviceUnits: _device.displayUnits,
      displayTimeoutS: _device.displayTimeoutS,
      onDisplayTimeout: (s) => _writeAndVerify(
        BridgeConfig(displayTimeoutS: s),
        what: 'the screen timeout',
      ),
      onUnits: (u) async {
        // A PHONE setting first: it lands in prefs and every reading in the
        // app changes on the next frame, bridge or no bridge. The row used to
        // carry `deviceReason`, which made °F/°C unchangeable whenever the
        // bridge was unreachable — on a page that states the opposite
        // principle one card below.
        setState(() => _units = u);
        await AppEnv.instance?.prefs.setDisplayUnits(u);
        // The DEVICE renders temperatures on its own screen; the two must
        // agree, so the setting also travels — and now it is read back, so
        // over Wi-Fi this reports "Saved" and means it. With no link there is
        // nothing to report: the app's own change already happened, and
        // "nothing was saved" would be false.
        if (_transport == null) {
          return;
        }
        await _writeAndVerify(BridgeConfig(displayUnits: u), what: 'the units');
      },
      // §H.3 — the daylight profile, applied live: a user standing in the sun
      // sees the change rather than being told to relaunch.
      themeProfile: _themeProfile,
      onThemeProfile: (p) async {
        setState(() => _themeProfile = p);
        SmokeBridgeApp.setProfile(context, p);
        await AppEnv.instance?.prefs.setThemeProfile(p.name);
      },
      deviceReason: _lane.deviceConfig,
      hardwareReason: _lane.deviceHardware,
    ),

    SettingsSection.led => LedSettingsView(
      enabled: _device.ledEnabled,
      reason: _lane.deviceHardware,
      onEnabled: (v) => _writeAndVerify(
        BridgeConfig(ledEnabled: v),
        what: 'the status light',
      ),
    ),

    SettingsSection.power => PowerSettingsView(
      sessionActive: _status?.sessionActive ?? false,
      socPct: _socPct,
      charging: _charging,
      batterySaver: _saver,
      batterySaverConfirmed: _saverConfirmed,
      saverEngaged: _saverEngaged,
      configReason: _lane.deviceConfig,
      controlReason: _lane.control,
      onBatterySaver: (v) async {
        final outcome = await _writeAndVerify(
          BridgeConfig(
            batterySaver: switch (v) {
              'off' => BatterySaverMode.off,
              'on' => BatterySaverMode.on,
              _ => BatterySaverMode.auto,
            },
          ),
          what: 'the battery saver',
        );
        if (!mounted) {
          return;
        }
        // A verified write has already adopted the device's own answer inside
        // _writeAndVerify, with [_saverConfirmed] set. This only covers the
        // lane that took the write and cannot read it back: the choice is
        // shown as chosen, and the row says it is unconfirmed.
        if (outcome == WriteOutcome.unverified) {
          setState(() {
            _saver = v;
            _saverConfirmed = false;
          });
        }
      },
      // Each verb runs inside the A24.9 completion sheet after the view's own
      // cost sheet: send → watch the bridge actually go down → an explicit
      // done state, instead of the old fire-and-forget.
      onRestart: _transport == null
          ? null
          : () => _runDisruptive(
              DisruptiveVerb.restart,
              const ControlCommand.reboot(),
            ),
      onPowerOff: _transport == null
          ? null
          : () => _runDisruptive(
              DisruptiveVerb.powerOff,
              const ControlCommand.powerOff(),
            ),
      onFactoryReset: _transport == null
          ? null
          : () => _runDisruptive(
              DisruptiveVerb.factoryReset,
              const ControlCommand.factoryReset(),
            ),
    ),

    SettingsSection.network => NetworkSettingsView(
      mode: _netMode,
      ssid: _netSsid,
      ip: _netIp,
      apPsk: _apPsk,
      wifiDbm: _signal?.wifiDbm,
      apClients: _signal?.apClients,
      revertInS: _revertInS,
      recoveryMessage: _netRecovery,
      unsupportedReason: _lane.network,
      onSwitchMode: _switchMode,
      manualAddressError: _manualAddressError,
      manualAddressBusy: _manualAddressBusy,
      onManualAddress: _useManualAddress,
    ),

    SettingsSection.homeAssistant => MqttSettingsView(
      config: _mqtt ?? const MqttConfig(),
      configKnown: _mqttKnown,
      unsupportedReason: _lane.mqtt,
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
            final t = _transport;
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (t == null) {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    writeOutcomeMessage(
                      WriteOutcome.noLink,
                      'the Home Assistant settings',
                    ),
                  ),
                ),
              );
              return;
            }
            try {
              await t.setMqttConfig(
                enabled: enabled,
                host: host,
                port: port,
                user: user,
                password: password,
                prefix: prefix,
                haDiscovery: haDiscovery,
              );
              // The read-back. `GET /config/mqtt` echoes everything except the
              // password, which the device never returns — so the comparison
              // covers everything it is possible to compare.
              final fresh = await t.mqttConfig();
              if (!mounted) {
                return;
              }
              setState(() {
                _mqtt = fresh;
                _mqttKnown = true;
              });
              final honoured = mqttWriteWasHonoured(
                fresh,
                enabled: enabled,
                host: host,
                port: port,
                user: user,
                prefix: prefix,
                haDiscovery: haDiscovery,
              );
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    writeOutcomeMessage(
                      honoured
                          ? WriteOutcome.verified
                          : WriteOutcome.changedByDevice,
                      'the Home Assistant settings',
                    ),
                  ),
                ),
              );
            } on Object {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    writeOutcomeMessage(
                      WriteOutcome.failed,
                      'the Home Assistant settings',
                    ),
                  ),
                ),
              );
            }
          },
    ),

    SettingsSection.firmware => FirmwareSettingsView(
      currentVersion: _status?.fw ?? '',
      model: _status?.model,
      otaSupported: _transport?.capabilities.ota ?? false,
      unsupportedReason: _lane.firmware,
      imageSourceAvailable: AppEnv.instance?.firmwareImage != null,
      sessionActive: _status?.sessionActive ?? false,
      progressPct: _otaPct,
      phase: _otaPhase,
      refusal: _otaRefusal,
      onUpload: AppEnv.instance?.firmwareImage == null ? null : _uploadFirmware,
    ),

    SettingsSection.data => DataSettingsView(
      sessions: _cache.sessions,
      samples: _cache.samples,
      approxBytes: _cache.approxBytes,
      storageFreePct: _status?.storageFreePct,
      maxSessionsOnBridge: _device.maxSessions,
      minFreePct: _device.minFreePct,
      hardwareReason: _lane.deviceHardware,
      onMaxSessions: (n) => _writeAndVerify(
        BridgeConfig(maxSessions: n),
        what: 'how many cooks the bridge keeps',
      ),
      shareAvailable: AppEnv.instance?.shareSheet != null,
      busy: _clearing,
      onClear: _clearCache,
      onOpenCooks: () => context.go(AppRoutes.cooks),
    ),

    // newapp §F — "replace today's stub with real read-outs". Every row here
    // is measured or absent; the stub it replaces stated a probe count under
    // the label "packets seen".
    SettingsSection.advanced => DiagnosticsSettingsView(
      lane: _lane,
      address: _netIp.isEmpty ? null : _netIp,
      linkDbm: _signal?.linkDbm,
      wifiDbm: _signal?.wifiDbm,
      apClients: _signal?.apClients,
      ssid: _netSsid,
      lastProblem: ShellScope.maybeOf(context)?.refreshFailure?.title ?? '',
      canFullHistory: _transport?.capabilities.fullHistory,
      canConfigure: _transport?.capabilities.config,
      firmware: _status?.fw,
      model: _status?.model,
      deviceId: _status?.deviceId,
      uptimeS: _status?.uptimeS,
      storageFreePct: _status?.storageFreePct,
      socPct: _status?.socPct,
      paired: _paired,
      probesReported: _status?.numProbes,
      lastPacketSAgo: _status?.lastPacketSAgo,
      baseLost: _status?.baseLost,
      syncRows: _syncRows,
      rolloverLoss: _rolloverLoss,
      clockUnixMs: _live?.unixMs,
      onSetClock: _transport == null ? null : () => unawaited(_setClock()),
      onFieldReport: () => context.push(AppRoutes.fieldReport),
    ),

    SettingsSection.about => AboutView(
      appVersion: AppEnv.instance?.appVersion ?? '',
      firmwareVersion: _status?.fw ?? '',
      deviceId: _status?.deviceId ?? '',
    ),
  };
}

/// Kept so the analyzer proves the OTA path is HTTP-only: a transport that can
/// take an image is an [HttpTransport], and nothing else claims otherwise.
bool otaCapable(BridgeTransport t) => t is HttpTransport && t.capabilities.ota;

/// §G.3's read-back comparison, hoisted out of the widget so the rule can be
/// tested directly: **did the device actually take what we sent?**
///
/// Compares only the fields that were written. A device echoing extra state it
/// manages itself (an alarm band, a probe we said nothing about) is not a
/// mismatch; a device that kept its own name, clamped a target, or dropped the
/// probe entirely is.
bool probeWriteWasHonoured(List<Probe> sent, List<Probe> echoed) {
  for (final p in sent) {
    final back = echoed.where((e) => e.n == p.n).firstOrNull;
    if (back == null ||
        back.name != p.name ||
        back.role != p.role ||
        back.targetF10 != p.targetF10) {
      return false;
    }
  }
  return true;
}

/// Whether [cfg] asks for anything `GET /config/device` reports back.
///
/// Exists so a probe-only write does not pay for a read it has no use for, and
/// so a write that touches nothing readable cannot silently claim to have been
/// verified against a read that never happened.
bool touchesDeviceConfig(BridgeConfig cfg) =>
    cfg.displayUnits != null ||
    cfg.batterySaver != null ||
    cfg.displayTimeoutS != null ||
    cfg.ledEnabled != null ||
    cfg.maxSessions != null;

/// **Did the device take what we sent — and if not, is that a refusal or a
/// silence?** Three answers, because there are three situations.
///
///  * `true` — every field we wrote came back matching.
///  * `false` — the device reported a field and it is **not** what we asked
///    for. It clamped, or it kept its own. The screen shows what it has.
///  * `null` — the device did not report a field we wrote, so nothing can be
///    concluded. This is the case [DeviceConfig.honoured] cannot express: it
///    returns a bool, so a missing field reads as a mismatch and a Bluetooth
///    link — which reports nothing at all — would accuse the bridge of
///    refusing every write. Absent is not disagreement.
///
/// Compares **only the fields that were sent**, the same rule
/// [DeviceConfig.honoured] and [probeWriteWasHonoured] follow, so a device
/// reporting five settings we said nothing about is never a mismatch.
bool? deviceWriteVerdict(DeviceConfig echoed, BridgeConfig sent) {
  var unread = false;
  bool agrees<T>(T? want, T? got) {
    if (want == null) {
      return true; // not written, not our business
    }
    if (got == null) {
      unread = true;
      return true;
    }
    return want == got;
  }

  if (!agrees(sent.displayUnits, echoed.displayUnits) ||
      !agrees(sent.batterySaver, echoed.batterySaver) ||
      !agrees(sent.displayTimeoutS, echoed.displayTimeoutS) ||
      !agrees(sent.ledEnabled, echoed.ledEnabled) ||
      !agrees(sent.maxSessions, echoed.maxSessions)) {
    return false;
  }
  return unread ? null : true;
}

/// The same comparison for the Home Assistant form.
///
/// The password is deliberately **not** compared: the device never returns it,
/// so there is nothing to compare against, and treating its absence as a
/// mismatch would report every successful save as a failure.
bool mqttWriteWasHonoured(
  MqttConfig echoed, {
  required bool enabled,
  required String host,
  required int port,
  required String user,
  required String prefix,
  required bool haDiscovery,
}) =>
    echoed.enabled == enabled &&
    echoed.host == host &&
    echoed.port == port &&
    echoed.user == user &&
    echoed.prefix == prefix &&
    echoed.haDiscovery == haDiscovery;
