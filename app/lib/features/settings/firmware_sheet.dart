/// N13.9–N13.14 — the firmware and update sheets.
///
/// The firmware sheet states what is installed and which channel it follows;
/// the update sheet states the **transport rule first** (an image is Wi-Fi-only,
/// so the primary action becomes *Join Wi-Fi*, never Install — N13.11) and the
/// **session guard** (a recording cook is a 409 `session_active` unless the user
/// explicitly forces it — N13.12). Both carry the auto-rollback promise
/// verbatim (N13.14).
library;

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/model/connection_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'settings_format.dart';
import 'settings_widgets.dart';

/// The body behind `?overlay=firmware` (N13.9).
class FirmwareSheetBody extends ConsumerWidget {
  const FirmwareSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the snapshot so "Check for updates" (which nudges the stream) and
    // any device mutation rebuild this sheet.
    ref.watch(snapshotProvider);
    final repo = ref.watch(bridgeRepositoryProvider);
    final device = repo.device;
    final firmware = repo.firmware;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final prefs = ref.read(prefsProvider);
    final scope = ShellScope.maybeOf(context);
    final tokens = SmokeTokens.of(context);

    return Column(
      key: const ValueKey<String>('firmware-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SmokeIcon(SmokeGlyph.cpu, color: tokens.textBody),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          device.version,
                          key: const ValueKey<String>('firmware-version'),
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 16,
                            color: tokens.textHi,
                          ),
                        ),
                        Text(
                          'Installed ${device.versionDate} · '
                          '${channelWord(device.channel)} channel',
                          style: SmokeText.labelSm.copyWith(
                            fontSize: 11.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (device.available != null)
                    Text(
                      'Update',
                      style: SmokeText.label.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tokens.warning,
                      ),
                    )
                  else
                    SmokeIcon(
                      SmokeGlyph.check,
                      size: 17,
                      color: tokens.positive,
                    ),
                ],
              ),
              const Divider(height: 24),
              FactRow(label: 'Hardware', value: device.hardware),
              FactRow(label: 'Bootloader', value: device.bootloader),
              const FactRow(label: 'Auto-rollback', value: 'On'),
            ],
          ),
        ),
        const SectionLabel(label: 'Update channel'),
        FilterChips<OtaChannel>(
          key: const ValueKey<String>('firmware-channel'),
          options: const <SmokeSegment<OtaChannel>>[
            SmokeSegment(value: OtaChannel.stable, label: 'Stable'),
            SmokeSegment(value: OtaChannel.beta, label: 'Beta'),
          ],
          value: settings.otaChannel,
          onChanged: (channel) =>
              unawaited(prefs.update((s) => s.copyWith(otaChannel: channel))),
        ),
        const SizedBox(height: 12),
        CapabilityNotice(
          key: const ValueKey<String>('firmware-rollback'),
          message:
              'Firmware is delivered over Wi-Fi only — Bluetooth cannot carry '
              'an image. ${firmware.rollback}',
        ),
        const SizedBox(height: 16),
        if (device.available != null)
          SmokeCard(
            subtle: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Available now',
                  style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  device.available!,
                  style: SmokeText.bodyStrong.copyWith(
                    fontSize: 15,
                    color: tokens.textHi,
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryAction(
                  key: const ValueKey<String>('firmware-install'),
                  label: 'Install ${device.available}',
                  icon: SmokeGlyph.upload,
                  onPressed: () {
                    scope?.closeOverlay();
                    scope?.openOverlay(
                      DevOverlay.firmwareUpdate,
                      const <String, String>{},
                    );
                  },
                ),
              ],
            ),
          )
        else
          PrimaryAction(
            key: const ValueKey<String>('firmware-check'),
            label: 'Check for updates',
            icon: SmokeGlyph.refresh,
            onPressed: () async {
              await repo.checkForUpdates();
              // Discovery is a read-back: force the watching surfaces to
              // re-read `device` even though the snapshot value is unchanged.
              ref.invalidate(snapshotProvider);
              final available = repo.device.available;
              scope?.showToast(
                available == null
                    ? 'You are on the latest ${otaChannelWord(settings.otaChannel)} '
                          'release.'
                    : 'Update available: $available',
              );
            },
          ),
      ],
    );
  }
}

/// The body behind `?overlay=firmwareUpdate` (N13.10–N13.12).
class FirmwareUpdateSheetBody extends ConsumerWidget {
  const FirmwareUpdateSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(snapshotProvider);
    final repo = ref.watch(bridgeRepositoryProvider);
    final device = repo.device;
    final firmware = repo.firmware;
    final snapshot = ref.watch(snapshotProvider).value;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final prefs = ref.read(prefsProvider);
    final scope = ShellScope.maybeOf(context);
    final tokens = SmokeTokens.of(context);
    final guard = otaGuard(
      connection:
          snapshot?.connection ??
          const ConnectionState(phase: ConnectionPhase.offline),
      recording: snapshot?.cook.active ?? false,
      forced: settings.forceOta,
    );

    if (device.available == null) {
      return Column(
        key: const ValueKey<String>('firmware-update-sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CapabilityNotice(
            message:
                'You are on the latest ${otaChannelWord(settings.otaChannel)} '
                'release, ${device.version}.',
            icon: SmokeGlyph.check,
          ),
          const SizedBox(height: 16),
          PrimaryAction(
            key: const ValueKey<String>('firmware-check'),
            label: 'Check again',
            icon: SmokeGlyph.refresh,
            onPressed: () async {
              await repo.checkForUpdates();
              ref.invalidate(snapshotProvider);
              final available = repo.device.available;
              scope?.showToast(
                available == null
                    ? 'Still up to date.'
                    : 'Update available: $available',
              );
            },
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey<String>('firmware-update-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Installed',
                          style: SmokeText.labelSm.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                        Text(
                          device.version,
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 15,
                            color: tokens.textHi,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SmokeIcon(SmokeGlyph.arrowRight, color: tokens.textMuted),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Available',
                          style: SmokeText.labelSm.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                        Text(
                          firmware.latest,
                          key: const ValueKey<String>('firmware-available'),
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 15,
                            color: tokens.p1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              for (final note in firmware.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SmokeIcon(
                        SmokeGlyph.check,
                        size: 14,
                        color: tokens.positive,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style: SmokeText.sub.copyWith(color: tokens.textBody),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      firmware.latestDate,
                      style: SmokeText.labelSm.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    '${firmware.sizeKb} KB',
                    style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
              FactRow(
                label: 'Channel',
                value: otaChannelWord(settings.otaChannel),
              ),
            ],
          ),
        ),

        // N13.11 — the transport rule comes first.
        if (!guard.wifiOk) ...<Widget>[
          const SizedBox(height: 12),
          CapabilityNotice(
            key: const ValueKey<String>('firmware-transport-notice'),
            severity: BannerSeverity.warn,
            icon: SmokeGlyph.alertTriangle,
            message:
                'This bridge is not on Wi-Fi right now. An image is too big '
                'for Bluetooth — join home Wi-Fi or the bridge hotspot before '
                'updating.',
          ),
          const SizedBox(height: 12),
          ActionRow(
            actions: <SmokeActionSpec>[
              SmokeActionSpec(
                label: 'Join Wi-Fi',
                icon: SmokeGlyph.router,
                onPressed: () {
                  scope?.closeOverlay();
                  scope?.openOverlay(DevOverlay.provisionSta);
                },
              ),
              SmokeActionSpec(
                label: 'Use hotspot',
                icon: SmokeGlyph.wifi,
                variant: SmokeButtonVariant.ghost,
                onPressed: () {
                  scope?.closeOverlay();
                  scope?.openOverlay(DevOverlay.provisionAp);
                },
              ),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          CapabilityNotice(
            key: const ValueKey<String>('firmware-wifi-ok'),
            message:
                'Connected over Wi-Fi. Do not power the bridge off during the '
                'update.',
          ),
        ],

        // N13.12 — the session guard.
        if (guard.recording) ...<Widget>[
          const SizedBox(height: 12),
          InsightBanner(
            key: const ValueKey<String>('firmware-session-notice'),
            severity: guard.forced
                ? BannerSeverity.info
                : BannerSeverity.critical,
            icon: SmokeGlyph.alertTriangle,
            word: guard.forced ? 'Forced' : 'Recording',
            message:
                'A cook is recording right now. Updating pauses recording and '
                'normally returns 409 session_active. Force it only if you '
                'accept losing this window.',
          ),
          SettingsRow(
            key: const ValueKey<String>('firmware-force-row'),
            icon: SmokeGlyph.zap,
            name: 'Force update during this cook',
            sub: 'Overrides the session-active guard',
            trailing: SmokeToggle(
              key: const ValueKey<String>('firmware-force'),
              value: settings.forceOta,
              onChanged: (on) =>
                  unawaited(prefs.update((s) => s.copyWith(forceOta: on))),
            ),
          ),
        ],

        const SizedBox(height: 16),
        PrimaryAction(
          key: const ValueKey<String>('firmware-install'),
          label: 'Install ${firmware.latest}',
          icon: SmokeGlyph.upload,
          enabledReason: guard.installReason,
          onPressed: guard.canInstall
              ? () {
                  scope?.closeOverlay();
                  scope?.openOverlay(DevOverlay.verb, const <String, String>{
                    'kind': 'ota',
                  });
                }
              : null,
        ),
      ],
    );
  }
}
