/// N13.15–N13.17 — the About & diagnostics sheet.
///
/// Identity and health, the two signal hops (never conflated), storage and
/// retention, the level-coloured recent logs, and the two export actions. No
/// row ever fabricates a value: a detached probe is `—`, never `0` (I3), and a
/// bridge with no clock stores no timestamp (I11).
library;

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model/connection_state.dart';
import '../../data/model/device_info.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../connection/connection_format.dart';
import '../shell/shell.dart';
import 'settings_format.dart';
import 'settings_widgets.dart';

/// The body behind `?overlay=diagnostics` (N13.15–N13.17).
class DiagnosticsSheetBody extends ConsumerWidget {
  const DiagnosticsSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider).value;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final repo = ref.watch(bridgeRepositoryProvider);
    final device = repo.device;
    final connection = snapshot.connection;
    final storage = device.storage;
    final scope = ShellScope.maybeOf(context);
    final tokens = SmokeTokens.of(context);

    return Column(
      key: const ValueKey<String>('diagnostics-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SmokeCard(
          key: const ValueKey<String>('diagnostics-identity'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SmokeIcon(SmokeGlyph.cpu, color: tokens.textBody),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connection.deviceName,
                      style: SmokeText.bodyStrong.copyWith(
                        fontSize: 14,
                        color: tokens.textHi,
                      ),
                    ),
                  ),
                  Text(
                    device.id,
                    key: const ValueKey<String>('diagnostics-id'),
                    style: SmokeText.monoSmall.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final fact in diagnosticFacts(device, connection))
                FactRow(label: fact.label, value: fact.value),
            ],
          ),
        ),

        const SectionLabel(label: 'Signal'),
        SmokeCard(
          key: const ValueKey<String>('diagnostics-signal'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinkRow(
                key: const ValueKey<String>('diagnostics-bt'),
                icon: SmokeGlyph.bluetooth,
                name: 'Bluetooth',
                sub: connection.bt.connected
                    ? <String>[
                        signalWord(connection.bt.bars),
                        if (connection.bt.rssi != null)
                          '${connection.bt.rssi} dBm',
                      ].join(' · ')
                    : 'Not connected',
                off: !connection.bt.connected,
                right: SignalBars(bars: connection.bt.bars ?? 0),
              ),
              LinkRow(
                key: const ValueKey<String>('diagnostics-wifi'),
                icon: connection.wifi.mode == WifiMode.ap
                    ? SmokeGlyph.wifi
                    : SmokeGlyph.router,
                name: 'Wi-Fi',
                sub: connection.wifi.mode == WifiMode.off
                    ? 'Not set up'
                    : connection.wifi.connected
                    ? <String>[
                        connection.wifi.ssid ?? '',
                        if (connection.wifi.ip != null) connection.wifi.ip!,
                        signalWord(connection.wifi.bars),
                      ].where((s) => s.isNotEmpty).join(' · ')
                    : 'Not connected',
                off: !connection.wifi.connected,
                right: SignalBars(bars: connection.wifi.bars ?? 0),
              ),
            ],
          ),
        ),

        const SectionLabel(label: 'Storage'),
        SmokeCard(
          key: const ValueKey<String>('diagnostics-storage'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FactRow(label: 'Sessions kept', value: sessionsKept(storage)),
              FactRow(label: 'Flash used', value: flashUsed(storage)),
              FactRow(label: 'Retention', value: retention(storage)),
              const SizedBox(height: 8),
              StorageBar(
                key: const ValueKey<String>('diagnostics-storage-bar'),
                fraction: storageUsedFraction(storage),
              ),
            ],
          ),
        ),

        const SectionLabel(label: 'Recent logs'),
        SmokeCard(
          key: const ValueKey<String>('diagnostics-logs'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < device.logs.length; i++)
                _LogLine(index: i, log: device.logs[i]),
            ],
          ),
        ),

        const SizedBox(height: 16),
        ActionRow(
          actions: <SmokeActionSpec>[
            SmokeActionSpec(
              label: 'Copy diagnostics',
              icon: SmokeGlyph.download,
              onPressed: () {
                unawaited(
                  Clipboard.setData(
                    ClipboardData(text: diagnosticsText(device, connection)),
                  ).catchError((Object _) {}),
                );
                scope?.showToast('Diagnostics copied to clipboard');
              },
            ),
            SmokeActionSpec(
              label: 'Field report',
              icon: SmokeGlyph.share,
              variant: SmokeButtonVariant.ghost,
              onPressed: () async {
                final send = await showCostSheet(
                  context,
                  title: 'Send a field report?',
                  message:
                      'Bundles recent logs, device facts and the last '
                      '${storage.days} days of session headers. No cook data '
                      'leaves the phone without you seeing it first.',
                  confirmLabel: 'Send report',
                  cancelLabel: 'Cancel',
                  destructive: false,
                );
                if (send == true) {
                  scope?.showToast('Field report sent');
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// One level-coloured log line.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.index, required this.log});

  final int index;
  final DeviceLog log;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = switch (logLevelOf(log.level)) {
      LogLevel.warn => tokens.warning,
      LogLevel.error => tokens.critical,
      LogLevel.info => tokens.textBody,
    };
    return Padding(
      key: ValueKey<String>('diagnostics-log-$index'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            log.t,
            style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              log.level,
              style: SmokeText.labelSm.copyWith(color: hue),
            ),
          ),
          Expanded(
            child: Text(
              log.text,
              style: SmokeText.labelSm.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: tokens.textHi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The copy-diagnostics payload: identity, health, storage and the log tail.
String diagnosticsText(DeviceInfo device, ConnectionState connection) {
  final buffer = StringBuffer()
    ..writeln('SmokeBridge ${device.id}')
    ..writeln('${device.hardware} · bootloader ${device.bootloader}')
    ..writeln(
      'Firmware ${device.version} (${channelWord(device.channel)}) '
      '${device.versionDate}',
    );
  for (final fact in diagnosticFacts(device, connection)) {
    buffer.writeln('${fact.label}: ${fact.value}');
  }
  final storage = device.storage;
  buffer
    ..writeln('Storage: ${flashUsed(storage)} · ${sessionsKept(storage)}')
    ..writeln('Recent logs:');
  for (final log in device.logs) {
    buffer.writeln('${log.t} ${log.level} ${log.text}');
  }
  return buffer.toString();
}
