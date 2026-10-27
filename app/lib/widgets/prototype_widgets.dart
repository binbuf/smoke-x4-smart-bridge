import 'package:flutter/material.dart';

import '../app/view_state.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';
import 'probe_sparkline.dart';

class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.view,
    required this.onRetry,
  });

  final LiveViewState view;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (view.phase == ConnectionPhase.live ||
        view.phase == ConnectionPhase.syncing) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color color, IconData icon) = switch (view.phase) {
      ConnectionPhase.live => (
        StatusColors.live(context),
        Icons.bluetooth_connected,
      ),
      ConnectionPhase.stale => (StatusColors.aging(context), Icons.schedule),
      ConnectionPhase.syncing => (StatusColors.info(context), Icons.sync),
      ConnectionPhase.reconnecting => (
        StatusColors.aging(context),
        Icons.sync_problem,
      ),
      ConnectionPhase.failed => (scheme.error, Icons.link_off),
      ConnectionPhase.offline => (
        StatusColors.stale(context),
        Icons.cloud_off_outlined,
      ),
      ConnectionPhase.blocked => (scheme.error, Icons.bluetooth_disabled),
      ConnectionPhase.setup => (
        StatusColors.stale(context),
        Icons.bluetooth_searching,
      ),
    };

    final action = switch (view.phase) {
      ConnectionPhase.failed => 'Retry',
      ConnectionPhase.offline => 'Retry',
      ConnectionPhase.reconnecting => 'Retry now',
      ConnectionPhase.stale => 'Read now',
      ConnectionPhase.blocked => 'Open settings',
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: dark ? 0.32 : 0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.connectionTitle,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 1),
                Text(
                  view.connectionSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: () {
                if (view.phase == ConnectionPhase.blocked) {
                  _showBlockedHelp(context);
                } else {
                  onRetry();
                }
              },
              child: Text(action),
            ),
        ],
      ),
    );
  }

  void _showBlockedHelp(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening the relevant Android settings.')),
    );
  }
}

/// A small LED-style status light with a soft halo. The halo is the only glow
/// in the app so healthy surfaces stay calm.
class StatusLed extends StatelessWidget {
  const StatusLed({
    super.key,
    required this.color,
    this.active = true,
    this.size = 10,
  });

  final Color color;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: 0.9),
              width: 2,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.42),
                      blurRadius: 9,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// A compact, cell-phone-style signal meter. Four bars avoid exposing dBm to
/// users who only need to know whether the link is excellent, good, fair or
/// weak.
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.level,
    this.color,
    this.semanticLabel,
  });

  /// 1 (weak) to 4 (excellent).
  final int level;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = color ?? scheme.onSurfaceVariant;
    final bars = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < 4; index++)
          Container(
            width: 4,
            height: 6.0 + index * 4,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 2.5),
            decoration: BoxDecoration(
              color: index < level ? active : active.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(1.2),
            ),
          ),
      ],
    );
    if (semanticLabel == null) return bars;
    return Semantics(label: semanticLabel, child: bars);
  }
}

class ProbeCard extends StatelessWidget {
  const ProbeCard({
    super.key,
    required this.probe,
    required this.units,
    required this.isOffline,
    required this.accent,
    required this.onTap,
  });

  final ProbeView probe;
  final Units units;
  final bool isOffline;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = probe.connected;
    final muted = probe.muted;

    final status = probe.statusText;
    final statusColor = isOffline
        ? StatusColors.stale(context)
        : switch (probe.health) {
            ProbeHealth.live => StatusColors.live(context),
            ProbeHealth.aging => StatusColors.aging(context),
            ProbeHealth.stale => StatusColors.aging(context),
            ProbeHealth.frozen => scheme.error,
          };

    return Semantics(
      container: true,
      button: true,
      label: probe.semanticsLabel,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: muted ? accent.withValues(alpha: 0.5) : accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'P${probe.number}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    if (connected && probe.health == ProbeHealth.aging)
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: StatusColors.aging(context),
                      ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (connected)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: probe.valueText,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: muted
                                  ? scheme.onSurface.withValues(alpha: 0.55)
                                  : scheme.onSurface,
                              fontSize: 42,
                            ),
                          ),
                          TextSpan(
                            text: probe.unitSuffix,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  )
                else
                  Text(
                    '—',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 42,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ExcludeSemantics(
                      child: ProbeSparkline(
                        points: probe.lastHour,
                        color: accent,
                        units: units,
                        muted: muted,
                        height: 46,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (status != null)
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: connected
                                ? statusColor
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          probe.trendText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted
                                ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.header,
  });

  final String title;
  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (header != null) ...[
                header!,
                if (children.isNotEmpty) const Divider(),
              ],
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      enabled: enabled,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 19,
          color: enabled ? scheme.onSurfaceVariant : scheme.outline,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        enabled ? Icons.chevron_right : Icons.lock_outline,
        size: 20,
        color: enabled ? scheme.onSurfaceVariant : scheme.outline,
      ),
      onTap: onTap,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
            if (secondary != null) ...[const SizedBox(height: 10), secondary!],
          ],
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showLossSheet(
  BuildContext context, {
  required String title,
  required String intro,
  required List<String> bullets,
  String? keepNote,
  required String confirmLabel,
  bool destructive = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  intro,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
                if (bullets.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        for (final bullet in bullets)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  destructive
                                      ? Icons.remove_circle_outline
                                      : Icons.check_circle_outline,
                                  size: 17,
                                  color: destructive
                                      ? scheme.error
                                      : StatusColors.live(context),
                                ),
                                const SizedBox(width: 9),
                                Expanded(child: Text(bullet)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (keepNote != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    keepNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StatusColors.live(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: destructive
                            ? FilledButton.styleFrom(
                                backgroundColor: scheme.error,
                                foregroundColor: scheme.onError,
                              )
                            : null,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
