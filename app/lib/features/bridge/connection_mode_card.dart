/// "How is this connected, and what are my other options?" — newapp §E.1 and
/// §C.5, rendered.
///
/// §E.1 asks for **three plain choices**, and the hard part is that they are not
/// three settings of one thing: "Bluetooth" is which radio *this phone* prefers,
/// while the two Wi-Fi rows are which network *the bridge* is on. Presenting
/// them as one picker is right — it is the question a user actually has — so
/// this card is careful about the seam:
///
///  * **the selection is read, never assumed.** Nothing is selected until the
///    link says which one is live. `NetMode _netMode = NetMode.sta` rendered as
///    "Joined a network" while the bridge hosted an AP is the bug §16.6 names
///    by line number, and an unselected row is the honest state before the
///    device has spoken;
///  * **the bridge's own network state is stated separately** when we are
///    talking over Bluetooth, because then the app is on one axis and the
///    bridge is on the other, and collapsing them would hide the exact
///    situation this release exists to surface;
///  * **no row is dead.** A choice that cannot be made right now is rendered,
///    dimmed, with its reason directly beneath (§16.5).
///
/// The signal block below it keeps the two-hop model verbatim: only Bluetooth
/// can measure phone↔bridge, only the bridge can measure bridge↔router, and on
/// the bridge's own network neither end can see the other's radio — so that
/// state says so and shows the client count rather than inventing bars.
library;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../ui/ui.dart';
import '../dashboard/dashboard_snapshot.dart';

/// The three plain choices of §E.1.
enum ConnectionChoice {
  /// Fast, close range, no network of any kind.
  bluetooth,

  /// The bridge makes its own network and the phone joins it.
  bridgeHosts,

  /// The bridge joins the house Wi-Fi.
  joinsYours,
}

extension ConnectionChoiceCopy on ConnectionChoice {
  String get title => switch (this) {
    ConnectionChoice.bluetooth => 'Bluetooth',
    ConnectionChoice.bridgeHosts => 'The bridge’s own network',
    ConnectionChoice.joinsYours => 'Your Wi-Fi',
  };

  /// One sentence, and it says what you *get*, not how it works.
  String get blurb => switch (this) {
    ConnectionChoice.bluetooth =>
      'Fast and close range. Good for checking in while you are at the '
          'cooker. Live readings only.',
    ConnectionChoice.bridgeHosts =>
      'The bridge makes a network and your phone joins it. Reaches further '
          'than Bluetooth and needs no router. No internet, by design.',
    ConnectionChoice.joinsYours =>
      'The bridge joins the Wi-Fi you already have, so you can check the '
          'cook from anywhere in the house.',
  };

  IconData get icon => switch (this) {
    ConnectionChoice.bluetooth => Icons.bluetooth_rounded,
    ConnectionChoice.bridgeHosts => Icons.wifi_tethering_rounded,
    ConnectionChoice.joinsYours => Icons.wifi_rounded,
  };
}

/// Which choice the live link *is*, or null when nothing has said yet.
///
/// Null is a first-class answer and the reason this is a function rather than a
/// field with a default.
ConnectionChoice? choiceFor({required LinkKind link, String? netMode}) {
  if (link == LinkKind.ble) {
    return ConnectionChoice.bluetooth;
  }
  if (link != LinkKind.http) {
    return null;
  }
  return switch (netMode) {
    'ap' => ConnectionChoice.bridgeHosts,
    'sta' => ConnectionChoice.joinsYours,
    _ => null,
  };
}

class ConnectionModeCard extends StatelessWidget {
  const ConnectionModeCard({
    required this.link,
    required this.onChoose,
    this.netMode,
    this.deviceNetMode,
    this.address = '',
    this.signal,
    this.signalFailed = false,
    this.disabledReason = '',
    this.onManageConnection,
    super.key,
  });

  final LinkKind link;

  /// `'ap'` / `'sta'` for the **link in use** — only Wi-Fi has one.
  final String? netMode;

  /// `'ap'` / `'sta'` for the **bridge itself**, learned over whichever lane is
  /// up. Only interesting when it differs from what the link can say — i.e.
  /// when we are on Bluetooth and the bridge is off doing its own thing.
  final String? deviceNetMode;

  final String address;
  final LinkSignal? signal;

  /// A signal read was attempted and failed, as distinct from never attempted.
  final bool signalFailed;

  /// Why a choice cannot be made right now. Empty means it can.
  final String disabledReason;

  final ValueChanged<ConnectionChoice> onChoose;
  final VoidCallback? onManageConnection;

  bool get _connected => link != LinkKind.offline;
  ConnectionChoice? get _selected => choiceFor(link: link, netMode: netMode);

  /// The current state in one sentence, with no default anywhere in it.
  String get _statement {
    switch (_selected) {
      case ConnectionChoice.bluetooth:
        return 'Connected over Bluetooth. Live readings now; Wi-Fi adds the '
            'full history, settings and updates.';
      case ConnectionChoice.bridgeHosts:
        return 'Connected on the bridge’s own network at ${_bare(address)}.';
      case ConnectionChoice.joinsYours:
        return 'Connected through your network at ${_bare(address)}.';
      case null:
        return _connected
            // Reached, but it has not said which network it is on. Saying
            // nothing is better than picking one.
            ? 'Connected. The bridge has not said which network it is on yet.'
            : 'Not connected. The app keeps trying on its own — Bluetooth '
                  'first, then Wi-Fi.';
    }
  }

  /// What the *bridge* is doing, when that is a separate fact from what the
  /// app is doing. This is the line that ends "Offline · retry 6".
  String get _deviceLine {
    if (_selected != ConnectionChoice.bluetooth) {
      return '';
    }
    return switch (deviceNetMode) {
      'ap' =>
        'Your bridge is hosting its own network right now, so Wi-Fi cannot '
            'reach it from yours.',
      'sta' => 'Your bridge is on your Wi-Fi as well.',
      _ => '',
    };
  }

  static String _bare(String url) => url.isEmpty
      ? noValue
      : url
            .replaceFirst(RegExp('^https?://'), '')
            .replaceFirst(RegExp(r'/$'), '');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final deviceLine = _deviceLine;
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
                _selected?.icon ?? Icons.cloud_off_rounded,
                size: 26,
                color: _connected ? t.textHi : t.textMuted,
              ),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selected?.title ?? 'Not connected',
                      key: const Key('bridge-connection-title'),
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statement,
                      key: const Key('bridge-connection-caption'),
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                    if (deviceLine.isNotEmpty) ...[
                      const SizedBox(height: SmokeTokens.s2),
                      Text(
                        deviceLine,
                        key: const Key('bridge-device-netmode'),
                        style: SmokeType.bodySm.copyWith(color: t.textBody),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_connected) ...[
            const SizedBox(height: SmokeTokens.s3),
            Divider(height: 1, color: t.hairline),
            const SizedBox(height: SmokeTokens.s3),
            SignalSection(
              link: link,
              netMode: netMode,
              signal: signal,
              signalFailed: signalFailed,
            ),
          ],
          const SizedBox(height: SmokeTokens.s4),
          Text(
            'HOW IT CONNECTS',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          for (final c in ConnectionChoice.values) ...[
            _ChoiceRow(
              key: Key('mode-${c.name}'),
              choice: c,
              selected: c == _selected,
              disabledReason: disabledReason,
              onTap: disabledReason.isEmpty && c != _selected
                  ? () => onChoose(c)
                  : null,
            ),
            const SizedBox(height: SmokeTokens.s2),
          ],
          if (onManageConnection != null) ...[
            const SizedBox(height: SmokeTokens.s1),
            OutlinedButton.icon(
              key: const Key('bridge-manage-connection'),
              onPressed: onManageConnection,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Fallback and preferences'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One §E.1 choice, as an option card.
///
/// The selected one is not tappable — there is nothing to switch to — and it
/// says so by being marked rather than by looking broken.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.selected,
    required this.disabledReason,
    required this.onTap,
    super.key,
  });

  final ConnectionChoice choice;
  final bool selected;
  final String disabledReason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final blocked = onTap == null && !selected;
    return Semantics(
      button: !blocked && !selected,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        child: Container(
          padding: const EdgeInsets.all(SmokeTokens.s3),
          decoration: BoxDecoration(
            color: selected ? t.cardRaised : t.cardSubtle,
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
            border: Border.all(
              color: selected
                  ? StatusPalette.border(StatusRole.positive)
                  : t.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    choice.icon,
                    size: 20,
                    color: blocked
                        ? t.chromeDim
                        : (selected ? t.textHi : t.textBody),
                  ),
                  const SizedBox(width: SmokeTokens.s3),
                  Expanded(
                    child: Text(
                      choice.title,
                      style: SmokeType.title.copyWith(
                        color: blocked ? t.textMuted : t.textHi,
                      ),
                    ),
                  ),
                  if (selected)
                    // The icon AND the word — a tick alone is a colour-blind
                    // reader's guess.
                    Text(
                      'In use',
                      key: const Key('mode-in-use'),
                      style: SmokeType.bodySm.copyWith(
                        color: t.textHi,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (!blocked)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: t.textMuted,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  choice.blurb,
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ),
              if (blocked && disabledReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 4),
                  child: Text(
                    disabledReason,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two-hop signal model (A26), unchanged.
///
/// Only ever rendered while the link is up — a dBm from a link that is down is
/// a number about the past presented as the present.
class SignalSection extends StatelessWidget {
  const SignalSection({
    required this.link,
    required this.netMode,
    required this.signal,
    required this.signalFailed,
    super.key,
  });

  final LinkKind link;
  final String? netMode;
  final LinkSignal? signal;
  final bool signalFailed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sig = signal;
    final onBle = link == LinkKind.ble;
    final hosted = link == LinkKind.http && netMode == 'ap';
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
          unknownWhy: signalFailed
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
      // Android will not hand this app its own signal without the location
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
                  // A [Wrap], not a [Row]: bars + word + reading is three
                  // items whose widths all grow with the text scale, and at
                  // 200% they stop fitting on one line at 360 dp. They go on
                  // to a second line rather than off the edge.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SmokeTokens.s2,
                    children: [
                      SignalBars(bars: signalBars(value, kind: kind)),
                      Text(
                        signalLabel(level!),
                        style: SmokeType.title.copyWith(color: t.textHi),
                      ),
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
