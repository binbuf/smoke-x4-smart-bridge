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
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';
import '../../data/transport/http_transport.dart';
import '../../domain/entities/entities.dart';
import 'settings_network.dart';
import 'settings_probes.dart';
import 'settings_screen.dart';

class SettingsRoute extends StatefulWidget {
  const SettingsRoute({super.key});

  @override
  State<SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<SettingsRoute> {
  SettingsSection? _section;
  BridgeTransport? _transport;
  List<Probe> _probes = const [];
  BridgeStatus? _status;
  String _units = 'F';
  bool _quietHours = true;
  bool _monitoring = true;
  bool _batteryExempt = false;

  @override
  void initState() {
    super.initState();
    _units = AppEnv.instance?.prefs.displayUnits ?? 'F';
    _quietHours = AppEnv.instance?.prefs.quietHoursEnabled ?? true;
    _monitoring = AppEnv.instance?.prefs.monitoringEnabled ?? true;
    unawaited(_load());
  }

  Future<void> _load() async {
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
  }

  @override
  void dispose() {
    unawaited(_transport?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = _section;
    return Scaffold(
      appBar: AppBar(
        title: Text(section?.title ?? 'Settings'),
        leading: IconButton(
          key: const Key('settings-back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => section == null
              ? context.go(AppRoutes.home)
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
      mode: NetMode.sta,
      onApply: (mode, ssid, psk) async {},
      onManualAddress: (address) async {
        await AppEnv.instance?.prefs.recordConnection(address);
        if (mounted) {
          context.go(AppRoutes.home);
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
    ),
    SettingsSection.advanced => AdvancedSettingsView(
      radio: {
        if (_status != null) 'firmware': _status!.fw,
        if (_status != null) 'packets_seen': _status!.numProbes,
      },
    ),
    SettingsSection.firmware => FirmwareSettingsView(
      currentVersion: _status?.fw ?? '',
      otaSupported: _transport?.capabilities.ota ?? false,
      sessionActive: _status?.sessionActive ?? false,
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
