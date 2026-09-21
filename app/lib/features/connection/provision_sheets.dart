/// N10.7–N10.9/N10.11 — the provisioning flows.
///
/// **Join home Wi-Fi (STA).** The bridge joins your network so your phone keeps
/// its internet. The password is sent over Bluetooth and is never stored by the
/// app (the field is cleared with the sheet, and the repository takes it as an
/// argument only).
///
/// **Use the bridge hotspot (AP).** No home network? The bridge broadcasts its
/// own; the phone joins it directly. The SSID and passkey are read off the
/// bridge, not typed by the user, and the flow keeps Bluetooth until the user
/// confirms.
///
/// **Named errors (N10.11).** A rejected password, an unreachable router and a
/// failed switch each get their own copy and their own recovery pair; none of
/// them can leave the user without a link, because Bluetooth is still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'connection_format.dart';

/// The body behind `?overlay=provisionSta`.
class ProvisionStaBody extends ConsumerStatefulWidget {
  const ProvisionStaBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<ProvisionStaBody> createState() => _ProvisionStaBodyState();
}

class _ProvisionStaBodyState extends ConsumerState<ProvisionStaBody> {
  final TextEditingController _password = TextEditingController();
  String _ssid = kScannedNetworks.first.ssid;
  String? _localError;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _localError = 'Enter the Wi-Fi password.');
      return;
    }
    setState(() => _localError = null);
    final scope = ShellScope.maybeOf(context);
    await ref
        .read(bridgeRepositoryProvider)
        .joinWifi(ssid: _ssid, password: password);
    scope?.showToast('Sending the password over Bluetooth…');
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final connection = ref.watch(snapshotProvider).value?.connection;
    final notice = ref.watch(snapshotProvider).value?.notice;
    final problem = connection != null && connectionHasProblem(connection);
    final errorText =
        _localError ??
        (problem ? connectionErrorCopy(connection, notice: notice) : null);
    final severity = problem && !connectionProblemIsWarning(connection)
        ? BannerSeverity.critical
        : BannerSeverity.warn;
    final scope = ShellScope.maybeOf(context);

    return Column(
      key: const ValueKey<String>('provision-sta-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CapabilityNotice(
          key: ValueKey<String>('provision-sta-notice'),
          message:
              'The bridge joins your home Wi-Fi so your phone keeps its '
              'internet and you can reach the bridge anywhere in range. The '
              'password is sent over Bluetooth and is not stored in the app.',
        ),
        const SizedBox(height: 18),
        Text(
          'CHOOSE A NETWORK',
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SmokeCard(
          subtle: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final network in kScannedNetworks)
                LinkRow(
                  key: ValueKey<String>('provision-sta-net-${network.ssid}'),
                  icon: SmokeGlyph.wifi,
                  name: network.ssid,
                  sub: signalWord(network.bars),
                  onTap: () => setState(() {
                    _ssid = network.ssid;
                    _localError = null;
                  }),
                  right: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SignalBars(bars: network.bars),
                      const SizedBox(width: 6),
                      SmokeIcon(
                        network.ssid == _ssid
                            ? SmokeGlyph.check
                            : SmokeGlyph.chevronRight,
                        size: 16,
                        color: network.ssid == _ssid
                            ? tokens.positive
                            : tokens.textMuted,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey<String>('provision-sta-password'),
          controller: _password,
          obscureText: true,
          onChanged: (_) {
            if (_localError != null) {
              setState(() => _localError = null);
            }
          },
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Password',
            hintText: '••••••••',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            labelStyle: SmokeText.labelSm.copyWith(color: tokens.textMuted),
            prefixIcon: SmokeIcon(
              SmokeGlyph.lock,
              size: 16,
              color: tokens.textMuted,
            ),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: 12),
          InsightBanner(
            key: const ValueKey<String>('provision-sta-error'),
            message: errorText,
            severity: severity,
            icon: SmokeGlyph.alertTriangle,
          ),
          const SizedBox(height: 10),
          SmokeButton(
            key: const ValueKey<String>('provision-sta-use-hotspot'),
            label: 'Use the bridge hotspot instead',
            icon: SmokeGlyph.wifi,
            variant: SmokeButtonVariant.ghost,
            onPressed: () => scope?.openOverlay(DevOverlay.provisionAp),
          ),
        ],
        const SizedBox(height: 18),
        PrimaryAction(
          key: const ValueKey<String>('provision-sta-connect'),
          label: problem ? 'Try again' : 'Connect bridge',
          icon: SmokeGlyph.link,
          onPressed: _connect,
        ),
        const SizedBox(height: 8),
        SmokeButton(
          key: const ValueKey<String>('provision-sta-cancel'),
          label: 'Cancel',
          variant: SmokeButtonVariant.ghost,
          onPressed: widget.onDone,
        ),
      ],
    );
  }
}

/// The body behind `?overlay=provisionAp`.
class ProvisionApBody extends ConsumerWidget {
  const ProvisionApBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final connection = ref.watch(snapshotProvider).value?.connection;
    final scope = ShellScope.maybeOf(context);
    final wifi = connection?.wifi;
    final ssid = wifi?.ssid ?? kHotspotSsid;
    final passkey = wifi?.passkey ?? kHotspotPasskey;

    return Column(
      key: const ValueKey<String>('provision-ap-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CapabilityNotice(
          key: ValueKey<String>('provision-ap-notice'),
          message:
              'No home network? The bridge can broadcast its own. Your phone '
              'joins it directly — some phones will warn there is “no '
              'internet”, which is normal.',
        ),
        const SizedBox(height: 12),
        SmokeCard(
          key: const ValueKey<String>('provision-ap-hotspot'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SmokeIcon(SmokeGlyph.wifi, color: tokens.textBody),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          ssid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 13.5,
                            color: tokens.textHi,
                          ),
                        ),
                        Text(
                          'Bridge hotspot',
                          style: SmokeText.labelSm.copyWith(
                            fontSize: 11.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SmokeIcon(SmokeGlyph.qr, color: tokens.textMuted),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Network password',
                style: SmokeText.labelSm.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              MonoWell(
                key: const ValueKey<String>('provision-ap-passkey'),
                value: passkey,
                small: true,
                onCopy: () => scope?.showToast('Passkey copied'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Column(
          key: const ValueKey<String>('provision-ap-steps'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _NumberedStep(
              index: 1,
              text: 'Open your phone’s Wi-Fi settings.',
              tokens: tokens,
            ),
            _NumberedStep(index: 2, text: 'Join $ssid.', tokens: tokens),
            _NumberedStep(
              index: 3,
              text: 'Come back — the app finds the bridge automatically.',
              tokens: tokens,
            ),
          ],
        ),
        const SizedBox(height: 18),
        PrimaryAction(
          key: const ValueKey<String>('provision-ap-open'),
          label: 'Open Wi-Fi settings',
          icon: SmokeGlyph.wifi,
          onPressed: () =>
              scope?.showToast('Opening your phone’s Wi-Fi settings…'),
        ),
        const SizedBox(height: 8),
        SmokeButton(
          key: const ValueKey<String>('provision-ap-joined'),
          label: 'I have joined',
          icon: SmokeGlyph.check,
          variant: SmokeButtonVariant.ghost,
          onPressed: () async {
            await ref.read(bridgeRepositoryProvider).confirmHotspotJoined();
            scope?.showToast('Bridge hotspot joined');
            onDone();
          },
        ),
        const SizedBox(height: 10),
        Text(
          'The bridge stays on Bluetooth until you confirm.',
          key: const ValueKey<String>('provision-ap-note'),
          textAlign: TextAlign.center,
          style: SmokeText.labelSm.copyWith(
            fontSize: 11,
            color: tokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.index,
    required this.text,
    required this.tokens,
  });

  final int index;
  final String text;
  final SmokeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.cardSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.hairlineStrong),
            ),
            child: Text(
              '$index',
              style: SmokeText.labelSm.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: tokens.textHi,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: SmokeText.body.copyWith(
                  fontSize: 12.5,
                  color: tokens.textBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
