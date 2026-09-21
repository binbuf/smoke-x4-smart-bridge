/// N10.4/N10.5 — the three mode cards and the technical reference.
///
/// One compact card shape (`modeCardCompact`) is shared by the connect sheet,
/// the modes sheet and the onboarding wizard: icon, name, a one-word state and
/// a `?` that opens the reference. The reference is where the prototype's long
/// copy lives — the summary, the good/limited lists and the capability matrix
/// — so the everyday surfaces stay terse.
///
/// **I13** is encoded twice here: a missing capability is a check/dash row in
/// the matrix *and* the plain-language reason under it ("Full history needs
/// Wi-Fi"), never a silent gap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/connection_mode.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'connection_format.dart';

/// The `ConnectionMode.icon` string, resolved against the design's glyph set.
SmokeGlyph _glyphFor(String name) {
  for (final glyph in SmokeGlyph.values) {
    if (glyph.name == name) {
      return glyph;
    }
  }
  return SmokeGlyph.wifi;
}

/// The compact mode row: name + one-word state + `?` info.
class ConnectionModeCard extends StatelessWidget {
  const ConnectionModeCard({
    super.key,
    required this.mode,
    required this.active,
    required this.onTap,
    required this.onInfo,
  });

  final ConnectionMode mode;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: active ? tokens.tint(tokens.positive, 0.08) : tokens.cardSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.control),
        side: BorderSide(
          color: active ? tokens.tint(tokens.positive, 0.35) : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.cardRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SmokeIcon(_glyphFor(mode.icon), color: tokens.textBody),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            mode.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SmokeText.bodyStrong.copyWith(
                              fontSize: 13.5,
                              color: tokens.textHi,
                            ),
                          ),
                        ),
                        if (active) ...<Widget>[
                          const SizedBox(width: 6),
                          const ModeBadge(label: 'Active'),
                        ],
                      ],
                    ),
                    Text(
                      '${mode.tagline} · '
                      '${modeStateWord(mode, active: active)}',
                      key: ValueKey<String>('connection-mode-state-${mode.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeText.labelSm.copyWith(
                        fontSize: 11.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _ModeInfoButton(
                key: ValueKey<String>('connection-mode-info-${mode.id}'),
                name: mode.name,
                onTap: onInfo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeInfoButton extends StatelessWidget {
  const _ModeInfoButton({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      button: true,
      label: 'About $name',
      child: Material(
        color: tokens.cardRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SmokeIcon(
              SmokeGlyph.question,
              size: 15,
              color: tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// N10.4 — the `modes` sheet: three ways to talk to the bridge.
class ConnectionModesBody extends ConsumerWidget {
  const ConnectionModesBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(snapshotProvider).value?.connection;
    final modes = ref.watch(bridgeRepositoryProvider).connectionModes;
    final activeId = connection == null ? null : activeModeId(connection);
    final scope = ShellScope.maybeOf(context);

    return Column(
      key: const ValueKey<String>('connection-modes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CapabilityNotice(
          key: ValueKey<String>('connection-modes-notice'),
          icon: SmokeGlyph.compass,
          message:
              'Three ways to talk to the bridge. Tap ? on any one for the '
              'full technical detail.',
        ),
        const SizedBox(height: 12),
        for (final mode in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConnectionModeCard(
              key: ValueKey<String>('connection-mode-${mode.id}'),
              mode: mode,
              active: mode.id == activeId,
              onTap: () => _selectMode(ref, scope, mode.id),
              onInfo: () =>
                  scope?.openOverlay(DevOverlay.modesRef, {'mode': mode.id}),
            ),
          ),
      ],
    );
  }

  Future<void> _selectMode(WidgetRef ref, ShellScope? scope, String id) async {
    if (id == 'ble') {
      await ref.read(bridgeRepositoryProvider).applyMode('ble');
      scope?.showToast('Switched to Bluetooth');
      onDone();
      return;
    }
    scope?.openOverlay(
      id == 'ap' ? DevOverlay.provisionAp : DevOverlay.provisionSta,
    );
  }
}

/// N10.5 — the technical reference (`overlayModesRef`).
class ModesReferenceBody extends ConsumerWidget {
  const ModesReferenceBody({super.key, required this.onDone, this.focusMode});

  final VoidCallback onDone;

  /// When set, only this mode is expanded (the `?` button's `mode` prop).
  final String? focusMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final connection = ref.watch(snapshotProvider).value?.connection;
    final modes = ref.watch(bridgeRepositoryProvider).connectionModes;
    final activeId = connection == null ? null : activeModeId(connection);

    return Column(
      key: const ValueKey<String>('connection-modes-ref'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CapabilityNotice(
          key: ValueKey<String>('connection-ref-notice'),
          message:
              'The bridge is a pure listener: it never transmits except for '
              'one tiny LoRa acknowledgement. All three modes share that rule.',
        ),
        const SizedBox(height: 12),
        for (final mode in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReferenceCard(
              key: ValueKey<String>('connection-ref-card-${mode.id}'),
              mode: mode,
              active: mode.id == activeId,
              open: focusMode == null || focusMode == mode.id,
              tokens: tokens,
            ),
          ),
      ],
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    super.key,
    required this.mode,
    required this.active,
    required this.open,
    required this.tokens,
  });

  final ConnectionMode mode;
  final bool active;
  final bool open;
  final SmokeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SmokeCard(
      subtle: !active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.cardRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SmokeIcon(_glyphFor(mode.icon), color: tokens.textBody),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            mode.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SmokeText.bodyStrong.copyWith(
                              fontSize: 13.5,
                              color: tokens.textHi,
                            ),
                          ),
                        ),
                        if (active) ...<Widget>[
                          const SizedBox(width: 6),
                          const ModeBadge(label: 'Active'),
                        ],
                      ],
                    ),
                    Text(
                      mode.tagline,
                      style: SmokeText.labelSm.copyWith(
                        fontSize: 11.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            mode.summary,
            style: SmokeText.body.copyWith(
              fontSize: 12.5,
              color: tokens.textBody,
            ),
          ),
          if (open) ...<Widget>[
            const SizedBox(height: 8),
            for (final good in mode.good)
              _ModeLine(
                key: ValueKey<String>('connection-ref-good-${mode.id}-$good'),
                text: good,
                good: true,
                tokens: tokens,
              ),
            for (final limit in mode.limited)
              _ModeLine(
                key: ValueKey<String>(
                  'connection-ref-limited-${mode.id}-$limit',
                ),
                text: limit,
                good: false,
                tokens: tokens,
              ),
            const SizedBox(height: 8),
            Divider(height: 1, color: tokens.hairline),
            const SizedBox(height: 8),
            Text(
              'CAPABILITIES',
              style: SmokeText.labelSm.copyWith(
                letterSpacing: 0.9,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            for (final row in capabilityRows(mode))
              _CapabilityRow(row: row, modeId: mode.id, tokens: tokens),
          ],
        ],
      ),
    );
  }
}

class _ModeLine extends StatelessWidget {
  const _ModeLine({
    super.key,
    required this.text,
    required this.good,
    required this.tokens,
  });

  final String text;
  final bool good;
  final SmokeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SmokeIcon(
              good ? SmokeGlyph.check : SmokeGlyph.minus,
              size: 14,
              color: good ? tokens.positive : tokens.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: SmokeText.labelSm.copyWith(
                fontSize: 12,
                color: tokens.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.row,
    required this.modeId,
    required this.tokens,
  });

  final CapabilityRow row;
  final String modeId;
  final SmokeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            key: ValueKey<String>(
              'connection-ref-cap-${row.feature.name}-$modeId',
            ),
            children: <Widget>[
              Expanded(
                child: Text(
                  row.label,
                  style: SmokeText.body.copyWith(
                    fontSize: 12.5,
                    color: tokens.textBody,
                  ),
                ),
              ),
              if (row.ok)
                SmokeIcon(SmokeGlyph.check, size: 15, color: tokens.positive)
              else
                Text(
                  '—',
                  style: SmokeText.body.copyWith(color: tokens.textMuted),
                ),
            ],
          ),
          if (row.reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                row.reason!,
                key: ValueKey<String>(
                  'connection-ref-reason-${row.feature.name}-$modeId',
                ),
                style: SmokeText.labelSm.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
