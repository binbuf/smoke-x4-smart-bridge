/// N13.1–N13.8 — the Settings tree.
///
/// The settings tree is a stack of labelled cards: the connection bridge card
/// (N10.12, reused), the Wi-Fi setup rows, Cooks → History, the display and
/// behaviour preferences, the Bridge card (firmware / update / diagnostics) and
/// the destructive device actions. Every row does something real; a gated
/// action states its reason instead of sitting dead (I5).
///
/// Invariants encoded here:
///  * **I5** — no dead controls: the About row says how many taps it wants.
///  * **I8** — a destructive verb routes through the shared cost sheet first.
///  * **I11** — the honesty footer states the no-clock / detached rules.
///  * **N13.5** — every preference is written through [PrefsRepository] and
///    applies immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/model/connection_state.dart';
import '../../data/providers.dart';
import '../../data/repository/bridge_repository.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../connection/bridge_card.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'settings_format.dart';

/// The Settings destination.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final snapshot = ref.watch(snapshotProvider).value;
    final repo = ref.watch(bridgeRepositoryProvider);
    final prefs = ref.read(prefsProvider);
    final scope = ShellScope.maybeOf(context);
    final connection = snapshot?.connection;
    final joinedHomeWifi =
        connection != null &&
        connection.wifi.mode == WifiMode.sta &&
        connection.wifi.connected;

    void updatePrefs(AppSettings Function(AppSettings) transform) {
      unawaited(prefs.update(transform));
    }

    return ShellScrollHost(
      resetToken: ShellScreen.settings,
      child: Column(
        key: const ValueKey<String>('settings-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // N13.1 — the connection card (N10.12) plus the Wi-Fi setup rows.
          const BridgeCard(),
          const SectionLabel(label: 'Set up Wi-Fi'),
          SmokeCard(
            key: const ValueKey<String>('settings-wifi-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SettingsRow(
                  key: const ValueKey<String>('settings-join-wifi'),
                  icon: SmokeGlyph.router,
                  name: 'Join your home network',
                  sub:
                      'Keeps your phone on the internet; reach the bridge '
                      'anywhere',
                  onTap: () => scope?.openOverlay(DevOverlay.provisionSta),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-use-hotspot'),
                  icon: SmokeGlyph.wifi,
                  name: 'Use the bridge hotspot',
                  sub: 'No home network needed — join the bridge directly',
                  onTap: () => scope?.openOverlay(DevOverlay.provisionAp),
                ),
                if (joinedHomeWifi)
                  SettingsRow(
                    key: const ValueKey<String>('settings-forget-network'),
                    icon: SmokeGlyph.unlink,
                    name: 'Forget network',
                    sub: connection.wifi.ssid ?? 'Home Wi-Fi',
                    onTap: () {
                      unawaited(repo.forgetNetwork());
                      scope?.showToast('Network forgotten');
                    },
                  ),
              ],
            ),
          ),

          // N13.2 — Cooks → History.
          const SectionLabel(label: 'Cooks'),
          SmokeCard(
            key: const ValueKey<String>('settings-cooks-card'),
            child: SettingsRow(
              key: const ValueKey<String>('settings-history'),
              icon: SmokeGlyph.history,
              name: 'History',
              sub: 'Past cooks, notes, ratings and exports',
              onTap: () => scope?.openScreen(ShellScreen.history),
            ),
          ),

          // N13.3–N13.5 — display and behaviour preferences.
          const SectionLabel(label: 'Preferences'),
          SmokeCard(
            key: const ValueKey<String>('settings-prefs-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SettingsRow(
                  key: const ValueKey<String>('settings-units'),
                  icon: SmokeGlyph.thermometer,
                  name: 'Units',
                  sub: unitsSub(settings.units),
                  trailing: SegmentedChips<TempUnit>(
                    segments: const <SmokeSegment<TempUnit>>[
                      SmokeSegment(value: TempUnit.fahrenheit, label: '°F'),
                      SmokeSegment(value: TempUnit.celsius, label: '°C'),
                    ],
                    value: settings.units,
                    onChanged: (units) =>
                        updatePrefs((s) => s.copyWith(units: units)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-appearance'),
                  icon: SmokeGlyph.monitor,
                  name: 'Appearance',
                  sub: appearanceSub(settings.themeMode),
                  trailing: SegmentedChips<AppThemeMode>(
                    segments: const <SmokeSegment<AppThemeMode>>[
                      SmokeSegment(value: AppThemeMode.system, label: 'Auto'),
                      SmokeSegment(value: AppThemeMode.light, label: 'Light'),
                      SmokeSegment(value: AppThemeMode.dark, label: 'Dark'),
                    ],
                    value: settings.themeMode,
                    onChanged: (mode) =>
                        updatePrefs((s) => s.copyWith(themeMode: mode)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-profile'),
                  icon: SmokeGlyph.sun,
                  name: 'High-contrast profile',
                  sub: settings.displayProfile == DisplayProfile.daylight
                      ? 'On — for bright sun'
                      : 'Off',
                  trailing: SmokeToggle(
                    value: settings.displayProfile == DisplayProfile.daylight,
                    onChanged: (on) => updatePrefs(
                      (s) => s.copyWith(
                        displayProfile: on
                            ? DisplayProfile.daylight
                            : DisplayProfile.standard,
                      ),
                    ),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-density'),
                  icon: SmokeGlyph.sliders,
                  name: 'Density',
                  sub: settings.density == Density.compact
                      ? 'Compact — more at a glance'
                      : 'Comfortable',
                  trailing: SmokeToggle(
                    value: settings.density == Density.comfortable,
                    onChanged: (on) => updatePrefs(
                      (s) => s.copyWith(
                        density: on ? Density.comfortable : Density.compact,
                      ),
                    ),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-motion'),
                  icon: SmokeGlyph.eye,
                  name: 'Reduce motion',
                  sub: settings.reducedMotion
                      ? 'Animations minimised'
                      : 'Full motion',
                  trailing: SmokeToggle(
                    value: settings.reducedMotion,
                    onChanged: (on) =>
                        updatePrefs((s) => s.copyWith(reducedMotion: on)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-monitoring'),
                  icon: SmokeGlyph.bell,
                  name: 'Alarms & monitoring',
                  sub: monitoringSub(settings.monitoring),
                  onTap: () => scope?.openOverlay(DevOverlay.alarms),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-prefer-manual'),
                  icon: SmokeGlyph.key,
                  name: 'Prefer my own alarms',
                  sub: 'Manual alarms win over device rules',
                  trailing: SmokeToggle(
                    value: settings.preferManualAlarm,
                    onChanged: (on) =>
                        updatePrefs((s) => s.copyWith(preferManualAlarm: on)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-quiet-hours'),
                  icon: SmokeGlyph.moon,
                  name: 'Quiet hours',
                  sub:
                      'Silences warning & info 10pm–6am. Critical always sounds',
                  trailing: SmokeToggle(
                    value: settings.quietHours,
                    onChanged: (on) =>
                        updatePrefs((s) => s.copyWith(quietHours: on)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-hold-ble'),
                  icon: SmokeGlyph.link,
                  name: 'Keep Bluetooth warm',
                  sub: 'Faster failover while on Wi-Fi',
                  trailing: SmokeToggle(
                    value: settings.holdBle,
                    onChanged: (on) =>
                        updatePrefs((s) => s.copyWith(holdBle: on)),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-wrap-reminders'),
                  icon: SmokeGlyph.calendar,
                  name: 'Wrap / spritz reminders',
                  sub: 'Use the expected timeline for nudges',
                  trailing: SmokeToggle(
                    value: settings.autoWrapReminder,
                    onChanged: (on) =>
                        updatePrefs((s) => s.copyWith(autoWrapReminder: on)),
                  ),
                ),
              ],
            ),
          ),

          // N13.6 — the Bridge card: firmware, update, diagnostics.
          const SectionLabel(label: 'Bridge'),
          SmokeCard(
            key: const ValueKey<String>('settings-bridge-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SettingsRow(
                  key: const ValueKey<String>('settings-firmware'),
                  icon: SmokeGlyph.cpu,
                  name: 'Firmware',
                  sub: firmwareRowSub(repo.device),
                  onTap: () => scope?.openOverlay(DevOverlay.firmware),
                ),
                SettingsRow(
                  key: const ValueKey<String>('settings-update-firmware'),
                  icon: SmokeGlyph.upload,
                  name: 'Update firmware',
                  sub: updateFirmwareRowSub(repo.device),
                  onTap: () => scope?.openOverlay(DevOverlay.firmwareUpdate),
                ),
                _DiagnosticsGateRow(
                  key: const ValueKey<String>('settings-about'),
                  deviceId: repo.device.id,
                  onUnlocked: () => scope?.openOverlay(DevOverlay.diagnostics),
                  onProgress: (taps) =>
                      scope?.showToast(diagnosticsGateSub(taps)),
                ),
              ],
            ),
          ),

          // N13.7 — destructive device actions.
          const SectionLabel(label: 'Device actions'),
          SmokeCard(
            key: const ValueKey<String>('settings-actions-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final spec in kVerbSpecs)
                  if (spec.verb != DeviceVerb.ota)
                    SettingsRow(
                      key: ValueKey<String>('settings-verb-${spec.id}'),
                      icon: switch (spec.verb) {
                        DeviceVerb.restart => SmokeGlyph.refresh,
                        DeviceVerb.forget => SmokeGlyph.unlink,
                        DeviceVerb.factoryReset => SmokeGlyph.alertTriangle,
                        DeviceVerb.ota => SmokeGlyph.upload,
                      },
                      name: switch (spec.verb) {
                        DeviceVerb.restart => 'Restart the bridge',
                        DeviceVerb.forget => 'Forget this bridge',
                        DeviceVerb.factoryReset => 'Factory reset',
                        DeviceVerb.ota => 'Install firmware',
                      },
                      sub: switch (spec.verb) {
                        DeviceVerb.restart =>
                          'Recovers a hung bridge · recording pauses ~30 s',
                        DeviceVerb.forget =>
                          'Remove pairing and Wi-Fi from this app',
                        DeviceVerb.factoryReset =>
                          'Erase all settings, Wi-Fi and recorded sessions',
                        DeviceVerb.ota => 'Over Wi-Fi only',
                      },
                      danger: spec.danger,
                      onTap: () => _askVerb(context, scope, spec),
                    ),
              ],
            ),
          ),

          // N13.8 — the honesty footer (I11, I3).
          const SmokeCard(
            key: ValueKey<String>('settings-honesty'),
            subtle: true,
            child: Text(
              'A bridge with no clock stores no timestamp — never a made-up '
              'one. A detached probe is absent, never 0.',
              key: ValueKey<String>('settings-honesty-text'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askVerb(
    BuildContext context,
    ShellScope? scope,
    VerbSpec spec,
  ) async {
    final confirmed = await showCostSheet(
      context,
      title: spec.confirmTitle,
      message: spec.message,
      confirmLabel: spec.confirmLabel,
      cancelLabel: 'Cancel',
      keeps: spec.keeps,
      loses: spec.loses,
      destructive: spec.danger,
    );
    if (confirmed == true) {
      scope?.openOverlay(DevOverlay.verb, <String, String>{'kind': spec.id});
    }
  }
}

/// N13.18 — the About row, gated behind five taps (research notes §11.4).
///
/// The row is never dead (I5): its sub line counts the taps down, and each
/// partial tap reports progress.
class _DiagnosticsGateRow extends StatefulWidget {
  const _DiagnosticsGateRow({
    super.key,
    required this.deviceId,
    required this.onUnlocked,
    required this.onProgress,
  });

  final String deviceId;
  final VoidCallback onUnlocked;
  final ValueChanged<int> onProgress;

  @override
  State<_DiagnosticsGateRow> createState() => _DiagnosticsGateRowState();
}

class _DiagnosticsGateRowState extends State<_DiagnosticsGateRow> {
  int _taps = 0;

  void _tap() {
    final next = _taps + 1;
    if (next >= kDiagnosticsTapCount) {
      setState(() => _taps = 0);
      widget.onUnlocked();
      return;
    }
    setState(() => _taps = next);
    widget.onProgress(next);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey<String>('settings-about-row'),
      icon: SmokeGlyph.info,
      name: 'About & diagnostics',
      sub: _taps == 0
          ? '${widget.deviceId} · signal, storage, logs'
          : diagnosticsGateSub(_taps),
      trailing: _taps == 0
          ? null
          : Text(
              '$_taps/$kDiagnosticsTapCount',
              key: const ValueKey<String>('settings-about-taps'),
              style: SmokeText.monoSmall,
            ),
      onTap: _tap,
    );
  }
}
