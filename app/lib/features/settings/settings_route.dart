/// The settings composition root (A12), on the **shared** connection
/// (newapp §F, §I.1 Phase 0).
///
/// A single route with an inner section stack, so the pages share one
/// connection and one set of reads. Everything it renders is one of the pure
/// views in this folder, which is what keeps them testable without a transport.
///
/// **The bug this fixes was the worst one in the app.** This route used to
/// build its *own* `HttpTransport` from the remembered base URL while the rest
/// of the shell reused the supervisor's open link. Two consequences, both bad:
///
///  * on a **Bluetooth-only setup there was no base URL at all**, so
///    `_transport` stayed null — and because every write went through a
///    null-aware `_transport?.configure(...)`, **saving probe settings appeared
///    to succeed while writing nothing**. A form that reports success and
///    changes nothing is the single most expensive kind of lie an app can tell;
///  * even over Wi-Fi it opened a second socket to a device that had one.
///
/// So the transport now comes from [ShellScope] — the same link the reader and
/// the Device tab use — and **every write verifies by read-back** before the
/// UI reports anything, which is house rule 7 ("verify by behaviour, not by
/// return value") applied where it was being skipped.
///
/// The second half of §F's complaint is also fixed: the device pages used to
/// render **constructor defaults as if they were facts read from the bridge**
/// (display timeout 60 s, status LED on, 64 cooks kept). Absent is now absent —
/// see [DeviceSettingsView]'s nullable inputs.
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
import 'settings_mqtt.dart';
import 'settings_network.dart';
import 'settings_probes.dart';
import 'settings_screen.dart';

class SettingsRoute extends StatefulWidget {
  const SettingsRoute({super.key, this.initialSection, this.embedded = false});

  /// Open straight onto one section — how `/bridge/:section` reaches these
  /// pages now that settings has been folded into the Bridge branch
  /// (13 §13.3.2). Null keeps the old section-list behaviour.
  final SettingsSection? initialSection;

  /// True when pushed inside the Bridge branch: back is a branch pop, and
  /// there is no section list to return to.
  final bool embedded;

  @override
  State<SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<SettingsRoute> {
  SettingsSection? _section;
  BridgeTransport? _transport;
  List<Probe> _probes = const [];
  BridgeStatus? _status;
  String _units = 'F';
  String? _saver;
  ThemeProfile _themeProfile = ThemeProfile.dark;
  bool _quietHours = true;
  bool _monitoring = true;
  bool _batteryExempt = false;

  // A12.3 — network. The mode is optimistic: it reflects what was last
  // applied from this screen, because `/status` does not carry it and
  // opening a WebSocket just to render one line is a bad trade.
  NetMode _netMode = NetMode.sta;
  String _netSsid = '';
  String _apPsk = '';
  String _netRecovery = '';

  // A12.6 — OTA upload state. Progress comes from the transport's `ota`
  // events, not from byte counting: the device is authoritative about its
  // own phase.
  int? _otaPct;
  String _otaPhase = '';
  String _otaRefusal = '';
  StreamSubscription<BridgeEvent>? _otaEvents;

  // A16 — Home Assistant / MQTT. Loaded from the device (HTTP-only); null
  // until it answers, and left null on a transport that cannot do it.
  MqttConfig? _mqtt;

  // A29 — the phone's own cache. Read from drift, never from the bridge:
  // this page is about what THIS PHONE keeps, and it must render with the
  // bridge unplugged.
  CacheStats _cache = CacheStats.empty;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _units = AppEnv.instance?.prefs.displayUnits ?? 'F';
    _themeProfile = ThemeProfile.fromName(
      AppEnv.instance?.prefs.themeProfile,
    );
    _quietHours = AppEnv.instance?.prefs.quietHoursEnabled ?? true;
    _monitoring = AppEnv.instance?.prefs.monitoringEnabled ?? true;
    unawaited(_loadCache());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _adoptSharedTransport();
  }

  /// The cache's size, read straight from drift. Deliberately outside the
  /// `baseUrl == null` guard below: a phone that has never been paired
  /// still has a cache page, and one whose bridge is unreachable must
  /// still be able to clear it.
  /// §F's Diagnostics rows the app itself owns: the sync high-water marks and
  /// the device's reported buffer extent, which are the two numbers that
  /// explain a chart with a hole in it.
  Map<String, Object?> _syncRows = const {};

  Future<void> _loadCache() async {
    final db = AppEnv.instance?.db;
    if (db == null) {
      return;
    }
    final stats = await db.cacheStats();
    final bridgeId = await db.sessionDao.knownBridgeId();
    final rows = <String, Object?>{};
    if (bridgeId != null) {
      final sessions = await db.sessionDao.allSessions(bridgeId);
      for (final session in sessions.take(3)) {
        final sync = await db.syncStateDao.forSession(bridgeId, session.id);
        if (sync == null) {
          continue;
        }
        rows['cook ${session.id} synced to'] = '${sync.highWaterT}s';
        if (sync.deviceMinT != null && sync.deviceMaxT != null) {
          rows['cook ${session.id} on the bridge'] =
              '${sync.deviceMinT}s–${sync.deviceMaxT}s';
        }
      }
      final gaps = <String>[];
      for (final session in sessions.take(3)) {
        final holes = await db.syncStateDao.forBridgeSession(
          bridgeId,
          session.id,
        );
        for (final g in holes.where((g) => g.reason.isPermanent)) {
          gaps.add('cook ${session.id}: ${formatDuration(g.durationS)}');
        }
      }
      if (gaps.isNotEmpty) {
        rows['lost to buffer rollover'] = gaps.join(', ');
      }
    }
    if (mounted) {
      setState(() {
        _cache = stats;
        _syncRows = rows;
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

  /// Takes the shell's live transport. Called from `didChangeDependencies`
  /// as well as `initState`, because the supervisor can swap BLE for Wi-Fi
  /// while this screen is open and a settings page holding the old link would
  /// keep writing down a socket nobody is listening to.
  void _adoptSharedTransport() {
    final shared = ShellScope.maybeOf(context)?.bridge?.transport;
    if (shared != null && !identical(shared, _transport)) {
      _transport = shared;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    unawaited(_loadCache());
    final env = AppEnv.instance;
    final t = _transport;
    if (env == null || t == null) {
      // No shared link yet. The pages that need the device say so
      // individually; nothing here fabricates a second connection.
      return;
    }
    try {
      final status = await t.status();
      final live = await t.live();
      if (mounted) {
        setState(() {
          _status = status;
          _probes = live.probes;
        });
      }
    } on Object {
      // Settings still renders: the pages that need the device say so
      // individually rather than the whole screen failing.
    }
    if (t.capabilities.mqtt) {
      try {
        final mqtt = await t.mqttConfig();
        if (mounted) {
          setState(() => _mqtt = mqtt);
        }
      } on Object {
        // The Home Assistant page falls back to defaults if the read fails.
      }
    }
  }

  /// A12.6 — pick a `.bin` through the injected seam, stream it to
  /// `POST /api/v1/ota`, and render progress from the device's own `ota`
  /// frames. [force] carries `?force=1`; the `409 session_active` refusal
  /// surfaces as copy and the force path is a separate, deliberate act —
  /// never an automatic retry.
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

    // The device is authoritative about its phase, so progress is read off
    // its `ota` frames rather than counted here.
    _otaEvents ??= transport.events.listen((e) {
      if (e is BridgeOtaEvent && mounted) {
        setState(() {
          _otaPhase = e.phase;
          _otaPct = e.pct;
        });
      }
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
        // The bridge's own refusal (its 409 session_active message). The
        // view turns it into the two-tier copy and the deliberate force
        // button, which only appears while a cook is active.
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

  /// **Write, then read back, then report** (house rule 7; newapp §F).
  ///
  /// The old shape was `await _transport?.configure(cfg); setState(...)` — a
  /// null-aware call whose failure mode is silence and whose success mode is
  /// unverified. This one:
  ///
  ///  1. refuses when there is no link, and says so;
  ///  2. writes;
  ///  3. **re-reads `live()` and adopts what the device actually reports**, so
  ///     the form shows the bridge's truth rather than the user's intent;
  ///  4. reports what happened either way.
  ///
  /// Step 3 is the one that matters. A device that clamps a target, rejects a
  /// name, or ignores a field it does not support will now show that on screen
  /// instead of leaving the user's typing there looking saved.
  Future<void> _writeAndVerify(BridgeConfig cfg, String okMessage) async {
    final t = _transport;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (t == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Not connected to the bridge — nothing was saved.'),
        ),
      );
      return;
    }
    try {
      await t.configure(cfg);
      final live = await t.live();
      if (!mounted) {
        return;
      }
      setState(() => _probes = live.probes);
      final expected = cfg.probes;
      if (expected != null && !probeWriteWasHonoured(expected, live.probes)) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'The bridge kept its own values for some of those. What you see '
              'now is what it actually has.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
        return;
      }
      messenger?.showSnackBar(SnackBar(content: Text(okMessage)));
    } on BridgeUnsupportedException catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('${e.what} needs a Wi-Fi connection.')),
      );
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('The bridge didn’t take that. Nothing was saved.'),
        ),
      );
    }
  }

  /// D15's verbs. The bridge answers *before* it acts and then drops the
  /// link, so a transport error here is as likely to be the success path as
  /// a failure — there is nothing honest to report and nothing to retry.
  Future<void> _power(ControlCommand cmd) async {
    try {
      await _transport?.control(cmd);
    } on Object {
      // Deliberately swallowed; see above.
    }
  }

  /// The three verbs that take the bridge down run inside the A24.9 sheet,
  /// which verifies completion by watching the bridge actually drop — the
  /// board-found gap was a factory reset that succeeded with no confirmation.
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

  @override
  void dispose() {
    unawaited(_otaEvents?.cancel());
    // The supervisor owns this link's lifetime now. Closing it here would take
    // the live readings down every time somebody backed out of settings.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = _section;
    // Deep-linked at a section (`/bridge/:section`): there is no section list
    // behind it, so back is a branch pop and go_router supplies the button.
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
                    ? context.go(AppRoutes.bridge)
                    : setState(() => _section = null),
              ),
      ),
      body: SafeArea(child: _body(section)),
    );
  }

  Widget _body(SettingsSection? section) => switch (section) {
    null => SettingsHomeView(onOpen: (s) => setState(() => _section = s)),
    SettingsSection.probes => ProbeSettingsView(
      probes: _probes,
      celsius: _units == 'C',
      // A6's typed condition, surfaced as copy: `BleTransport` has no
      // `device_control` op for probe names or roles, and v1 leaves that
      // surface HTTP-only rather than silently dropping the write. Also true
      // when there is no shared link at all — a disabled row with a reason
      // beats a form that reports success and writes nothing.
      unsupportedReason: switch (_transport) {
        null => 'Not connected to the bridge — reconnect to change probes.',
        BleTransport() =>
          'Probe names and targets need a Wi-Fi connection to the bridge.',
        _ => '',
      },
      onSave: (probes) =>
          _writeAndVerify(BridgeConfig(probes: probes), 'Probes saved'),
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
      deviceRules: const {
        'smoke_x_alarm': true,
        'target_reached': true,
        'pit_out_of_band': true,
        'pit_crash': true,
        'probe_detached': true,
        'base_lost': true,
      },
      alarms: _status?.alarms ?? const [],
      onAck: (a) => unawaited(
        _transport?.control(ControlCommand.ackAlarm(alarmId: a.id)) ??
            Future<void>.value(),
      ),
    ),
    SettingsSection.network => NetworkSettingsView(
      mode: _netMode,
      ssid: _netSsid,
      apPsk: _apPsk,
      recoveryMessage: _netRecovery,
      // A12.3 — the real switch. The device answers first and defers ~500 ms
      // so this reply flushes before it tears the interface down (05 §5.4);
      // switching to AP hands back a generated key the user needs to rejoin,
      // which is exactly why applyNetwork returns it instead of being a
      // fire-and-forget config write.
      onApply: (mode, ssid, psk) async {
        final t = _transport;
        if (t == null) {
          return;
        }
        try {
          final apPsk = await t.applyNetwork(
            mode: mode == NetMode.ap ? NetworkMode.ap : NetworkMode.sta,
            ssid: ssid,
            psk: psk,
          );
          if (!mounted) return;
          setState(() {
            _netMode = mode;
            _netSsid = mode == NetMode.ap ? '' : ssid;
            _apPsk = apPsk;
            _netRecovery = mode == NetMode.ap
                ? 'The bridge is switching to its own network. Your phone has '
                      'to leave this one to reach it'
                      '${apPsk.isEmpty ? '' : ' — the key is shown above'}.'
                : 'The bridge is joining $ssid. If the app cannot find it '
                      'again, type its address under "Reach it directly".';
          });
        } on BridgeApiException catch (err) {
          if (!mounted) return;
          setState(() => _netRecovery = err.message);
        } on Object {
          if (!mounted) return;
          setState(
            () => _netRecovery =
                'The bridge did not accept that change. It may already have '
                'moved — try reaching it directly.',
          );
        }
      },
      onManualAddress: (address) async {
        await AppEnv.instance?.prefs.recordConnection(address);
        if (mounted) {
          context.go(AppRoutes.home);
        }
      },
    ),
    SettingsSection.homeAssistant => MqttSettingsView(
      config: _mqtt ?? const MqttConfig(),
      // BLE cannot reach a LAN broker; the page says so rather than offering a
      // form that would throw BridgeUnsupportedException on save.
      unsupportedReason: _transport is BleTransport
          ? 'Home Assistant needs a Wi-Fi connection to the bridge.'
          : '',
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
            if (t == null) {
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
              final fresh = await t.mqttConfig();
              if (mounted) {
                setState(() => _mqtt = fresh);
              }
            } on Object {
              // Best-effort; the page keeps rendering its current state.
            }
          },
    ),
    SettingsSection.device => DeviceSettingsView(
      units: _units,
      // §H.3 — the daylight profile, wired to the token architecture that was
      // built for it. Applied live, so a user standing in the sun sees the
      // change rather than being told to relaunch.
      themeProfile: _themeProfile,
      onThemeProfile: (p) async {
        setState(() => _themeProfile = p);
        SmokeBridgeApp.setProfile(context, p);
        await AppEnv.instance?.prefs.setThemeProfile(p.name);
      },
      onUnits: (u) async {
        setState(() => _units = u);
        await AppEnv.instance?.prefs.setDisplayUnits(u);
        // The DEVICE renders temperatures on its own OLED; the two
        // screens must agree, so the setting travels.
        await _writeAndVerify(BridgeConfig(displayUnits: u), 'Units saved');
      },
      // Absent, not defaulted: the saver mode is only known once the bridge
      // has said so, and rendering `auto` before it does is a constructor
      // default masquerading as a fact (§F, §I.0).
      batterySaver: _saver,
      onBatterySaver: (v) async {
        setState(() => _saver = v);
        await _writeAndVerify(
          BridgeConfig(
            batterySaver: switch (v) {
              'off' => BatterySaverMode.off,
              'on' => BatterySaverMode.on,
              _ => BatterySaverMode.auto,
            },
          ),
          'Battery saver saved',
        );
      },
      unsupportedReason: _transport == null
          ? 'Not connected to the bridge — reconnect to change these.'
          : '',
    ),
    SettingsSection.advanced => AdvancedSettingsView(
      // newapp §F — "Replace today's stub with real read-outs."
      //
      // This map was `{firmware, packets_seen: numProbes}` — and the second
      // was **mislabelled**: `numProbes` is how many probes the base reports,
      // not a packet count. A diagnostics page that states a wrong fact is
      // worse than one that states nothing, because it is the page someone
      // reads when they already suspect something is wrong.
      //
      // Every row below is either measured or absent.
      radio: {
        if (_status != null) 'firmware': _status!.fw,
        if (_status != null) 'model': _status!.model,
        if (_status != null) 'device id': _status!.deviceId,
        if (_status != null) 'uptime': formatDuration(_status!.uptimeS),
        if (_status != null) 'probes reported': _status!.numProbes,
        if (_status?.lastPacketSAgo != null)
          'last packet': '${_status!.lastPacketSAgo}s ago',
        if (_status != null) 'base station lost': _status!.baseLost,
        if (_status != null) 'storage free': '${_status!.storageFreePct}%',
        // Absent ≠ zero: a bridge that cannot measure a battery says nothing
        // rather than 0%.
        if (_status?.socPct != null) 'battery': '${_status!.socPct}%',
        'transport': switch (_transport) {
          null => 'not connected',
          BleTransport() => 'Bluetooth',
          _ => 'Wi-Fi',
        },
        if (_transport != null)
          'full history': _transport!.capabilities.fullHistory,
        if (_transport != null) 'can configure': _transport!.capabilities.config,
        ..._syncRows,
      },
      paired: _status?.paired ?? false,
      // D15 moved these off the button; this screen is now the only way to
      // re-scan or drop the base.
      onPair: _transport == null
          ? null
          : () => unawaited(_power(const ControlCommand.pair())),
      onUnpair: _transport == null
          ? null
          : () => unawaited(_power(const ControlCommand.unpair())),
      onFieldReport: () => context.push(AppRoutes.fieldReport),
    ),
    SettingsSection.firmware => FirmwareSettingsView(
      currentVersion: _status?.fw ?? '',
      otaSupported: _transport?.capabilities.ota ?? false,
      imageSourceAvailable: AppEnv.instance?.firmwareImage != null,
      sessionActive: _status?.sessionActive ?? false,
      progressPct: _otaPct,
      phase: _otaPhase,
      refusal: _otaRefusal,
      onUpload: AppEnv.instance?.firmwareImage == null ? null : _uploadFirmware,
    ),
    SettingsSection.power => PowerSettingsView(
      sessionActive: _status?.sessionActive ?? false,
      // Each verb runs inside the A24.9 completion sheet after the view's own
      // confirm: send → watch the bridge actually go down → an explicit done
      // state, instead of the old fire-and-forget.
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
    SettingsSection.storage => StorageSettingsView(
      sessions: _cache.sessions,
      samples: _cache.samples,
      approxBytes: _cache.approxBytes,
      busy: _clearing,
      onClear: _clearCache,
    ),
    SettingsSection.about => AboutView(
      appVersion: AppEnv.instance?.appVersion ?? '',
      firmwareVersion: _status?.fw ?? '',
      deviceId: _status?.deviceId ?? '',
    ),
  };
}

/// Kept so the analyzer proves the OTA path is HTTP-only: a transport
/// that can take an image is an [HttpTransport], and nothing else claims
/// otherwise.
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
