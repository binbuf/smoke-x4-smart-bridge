/// The settings composition root (A12).
///
/// A single route with an inner section stack, so the seven pages share
/// one connection and one set of reads. Everything it renders is one of
/// the pure views in this folder, which is what keeps them testable
/// without a transport.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../data/local/database.dart' show CacheStats;
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';
import '../../data/transport/http_transport.dart';
import '../../domain/entities/entities.dart';
import '../bridge/verb_progress.dart';
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
  String _saver = 'auto';
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
    _quietHours = AppEnv.instance?.prefs.quietHoursEnabled ?? true;
    _monitoring = AppEnv.instance?.prefs.monitoringEnabled ?? true;
    unawaited(_load());
  }

  /// The cache's size, read straight from drift. Deliberately outside the
  /// `baseUrl == null` guard below: a phone that has never been paired
  /// still has a cache page, and one whose bridge is unreachable must
  /// still be able to clear it.
  Future<void> _loadCache() async {
    final db = AppEnv.instance?.db;
    if (db == null) {
      return;
    }
    final stats = await db.cacheStats();
    if (mounted) {
      setState(() => _cache = stats);
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

  Future<void> _load() async {
    unawaited(_loadCache());
    final env = AppEnv.instance;
    final baseUrl = env?.prefs.lastBaseUrl;
    if (env == null || baseUrl == null) {
      return;
    }
    final t = env.transportFor(baseUrl);
    _transport = t;
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
    unawaited(_transport?.close());
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
      // surface HTTP-only rather than silently dropping the write.
      unsupportedReason: _transport is BleTransport
          ? 'Probe names and targets need a Wi-Fi connection to the bridge.'
          : '',
      onSave: (probes) async {
        await _transport?.configure(BridgeConfig(probes: probes));
        setState(() => _probes = probes);
      },
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
      onUnits: (u) async {
        setState(() => _units = u);
        await AppEnv.instance?.prefs.setDisplayUnits(u);
        // The DEVICE renders temperatures on its own OLED; the two
        // screens must agree, so the setting travels.
        await _transport?.configure(BridgeConfig(displayUnits: u));
      },
      batterySaver: _saver,
      onBatterySaver: (v) async {
        setState(() => _saver = v);
        await _transport?.configure(
          BridgeConfig(
            batterySaver: switch (v) {
              'off' => BatterySaverMode.off,
              'on' => BatterySaverMode.on,
              _ => BatterySaverMode.auto,
            },
          ),
        );
      },
    ),
    SettingsSection.advanced => AdvancedSettingsView(
      radio: {
        if (_status != null) 'firmware': _status!.fw,
        if (_status != null) 'packets_seen': _status!.numProbes,
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
