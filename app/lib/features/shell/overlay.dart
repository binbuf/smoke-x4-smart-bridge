/// N4.6–N4.8 — the overlay framework and the named overlay router.
///
/// Two mechanisms, one chrome:
///
/// * [showSheet] / [showModalCard] are the imperative framework primitives — a
///   bottom sheet with grabber, head and scrollable body, and a centred confirm
///   card. Both dismiss on a scrim tap (`barrierDismissible`). Later screens
///   (N9/N10/N11/N13) use these for ad-hoc flows.
/// * [ShellOverlayHost] renders the **named** overlays inside the phone frame.
///   The prototype's §7 map is reproduced by [resolveOverlay]: every
///   [DevOverlay] resolves to a sheet or a modal, so the dev panel and a deep
///   link open the same surface by name. The real contents land in their
///   owning tasks; this is the routing and dismissal contract.
///
/// The surfaces are shared, so an in-tree overlay and an imperative sheet can
/// never drift apart.
library;

import 'package:flutter/material.dart';

import '../../data/dev_panel.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../alarms/alarm_detail_sheet.dart';
import '../alarms/alarms_sheet.dart';
import '../connection/connect_sheet.dart';
import '../connection/mode_cards.dart';
import '../connection/provision_sheets.dart';
import '../live/live_overlays.dart';
import '../onboarding/onboarding_sheet.dart';
import '../settings/diagnostics_sheet.dart';
import '../settings/firmware_sheet.dart';
import '../settings/settings_format.dart';
import '../settings/verb_sheet.dart';
import '../setup/custom_food_sheet.dart';
import '../setup/setup_sheet.dart';
import '../temps/probe_sheet.dart';
import 'app_bar.dart';

/// A named overlay request plus its string props.
@immutable
class OverlayRequest {
  const OverlayRequest(this.name, [this.props = const <String, String>{}]);

  final DevOverlay name;
  final Map<String, String> props;

  @override
  bool operator ==(Object other) =>
      other is OverlayRequest &&
      other.name == name &&
      _mapEquals(other.props, props);

  @override
  int get hashCode => Object.hash(name, Object.hashAllUnordered(props.entries));

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// The resolved presentation of an overlay.
sealed class OverlayContent {
  const OverlayContent({required this.title});

  final String title;
}

/// Builds an overlay body/actions with the host's dismiss callback, so a body
/// can apply an action and close without importing the shell.
typedef OverlayBodyBuilder = Widget Function(VoidCallback dismiss);

/// A bottom-sheet overlay.
class SheetOverlay extends OverlayContent {
  const SheetOverlay({
    required super.title,
    this.sub,
    this.body,
    this.bodyBuilder,
    this.foot,
    this.footBuilder,
  });

  final String? sub;

  /// A static body. Ignored when [bodyBuilder] is supplied.
  final Widget? body;

  /// A body that needs the host's dismiss callback (N5 mark sheet, …).
  final OverlayBodyBuilder? bodyBuilder;

  final Widget? foot;

  /// A foot that needs the host's dismiss callback (N14 wizard).
  final OverlayBodyBuilder? footBuilder;
}

/// A centred modal-card overlay.
class ModalOverlay extends OverlayContent {
  const ModalOverlay({
    required super.title,
    this.body,
    this.bodyBuilder,
    this.confirmLabel = 'Confirm',
    this.danger = false,
    this.actions,
    this.actionsBuilder,
  });

  final Widget? body;
  final OverlayBodyBuilder? bodyBuilder;
  final String confirmLabel;
  final bool danger;

  /// Replaces the default Confirm/Cancel row. Ignored when [actionsBuilder]
  /// is supplied.
  final Widget? actions;

  /// Builds the action row with the host's dismiss callback.
  final OverlayBodyBuilder? actionsBuilder;
}

/// The prototype's §7 map, as a resolver over [DevOverlay].
OverlayContent resolveOverlay(OverlayRequest request) {
  return switch (request.name) {
    DevOverlay.onboarding => SheetOverlay(
      title: kOnboardingOverlayTitle,
      sub: kOnboardingOverlaySub,
      bodyBuilder: onboardingOverlayBody,
      footBuilder: onboardingOverlayFoot,
    ),
    DevOverlay.setup => SheetOverlay(
      title: 'Cook setup',
      sub: 'Set up before, during, or after you light the fire',
      bodyBuilder: (dismiss) => SetupSheetBody(
        onDone: dismiss,
        addContext: request.props['context'] == 'edit',
        initialJack: ProbeJack.fromN(
          int.tryParse(request.props['jack'] ?? '') ?? 0,
        ),
        initialFoodId: request.props['food'],
        initialStyleId: request.props['style'],
      ),
    ),
    DevOverlay.connect => SheetOverlay(
      title: 'Connection',
      sub: 'Bluetooth and Wi-Fi',
      bodyBuilder: (dismiss) => ConnectSheetBody(onDone: dismiss),
    ),
    DevOverlay.modes => SheetOverlay(
      title: 'Connection modes',
      sub: 'Switch any time — the app stays reachable',
      bodyBuilder: (dismiss) => ConnectionModesBody(onDone: dismiss),
    ),
    DevOverlay.modesRef => SheetOverlay(
      title: 'Connection modes',
      sub: 'Technical reference',
      bodyBuilder: (dismiss) =>
          ModesReferenceBody(onDone: dismiss, focusMode: request.props['mode']),
    ),
    DevOverlay.provisionSta => SheetOverlay(
      title: 'Join home Wi-Fi',
      sub: 'Sent over Bluetooth',
      bodyBuilder: (dismiss) => ProvisionStaBody(onDone: dismiss),
    ),
    DevOverlay.provisionAp => SheetOverlay(
      title: 'Use the bridge hotspot',
      sub: 'Direct link, no router needed',
      bodyBuilder: (dismiss) => ProvisionApBody(onDone: dismiss),
    ),
    DevOverlay.alarms => SheetOverlay(
      title: 'Alerts',
      sub: 'From the bridge and insights from the app, kept separate',
      bodyBuilder: (dismiss) => AlarmsSheetBody(onDone: dismiss),
    ),
    DevOverlay.alarmDetail => SheetOverlay(
      title: 'Alert',
      sub: request.props['tier'] == 'app'
          ? 'Insight from the app'
          : 'From the bridge',
      bodyBuilder: (dismiss) =>
          AlarmDetailSheetBody(alarmId: request.props['id'], onDone: dismiss),
    ),
    DevOverlay.mark => SheetOverlay(
      title: 'Add a mark',
      sub: 'A timestamped event on this cook',
      bodyBuilder: (dismiss) => MarkSheetBody(onDone: dismiss),
    ),
    DevOverlay.probe => SheetOverlay(
      title: 'Probe ${request.props['jack'] ?? ''}'.trim(),
      sub: 'Jack details',
      bodyBuilder: (dismiss) => ProbeSheetBody(
        jack:
            ProbeJack.fromN(int.tryParse(request.props['jack'] ?? '') ?? 1) ??
            ProbeJack.one,
        onDone: dismiss,
      ),
    ),
    DevOverlay.adopt => ModalOverlay(
      title: 'Adopt session',
      confirmLabel: 'Adopt session',
      bodyBuilder: (dismiss) => AdoptSessionBody(onDone: dismiss),
      actionsBuilder: (dismiss) => AdoptSessionActions(onDone: dismiss),
    ),
    DevOverlay.editStart => ModalOverlay(
      title: 'Adjust start time',
      confirmLabel: 'Done',
      bodyBuilder: (dismiss) => EditStartBody(onDone: dismiss),
    ),
    DevOverlay.confirm => ModalOverlay(
      title: request.props['title'] ?? 'Confirm',
      confirmLabel: request.props['confirm'] ?? 'Confirm',
      danger: request.props['danger'] == '1',
      body: CostSheetBody(
        message:
            request.props['message'] ??
            'This action has a cost. Read it before you continue.',
        keeps: _propList(request.props['keeps']),
        loses: _propList(request.props['loses']),
      ),
    ),
    DevOverlay.customFood => SheetOverlay(
      title: 'Custom food',
      sub: 'Add your own cut to the catalog',
      bodyBuilder: (dismiss) => CustomFoodSheetBody(onDone: dismiss),
    ),
    DevOverlay.firmware => SheetOverlay(
      title: 'Firmware',
      sub: 'Version and channel',
      bodyBuilder: (dismiss) => FirmwareSheetBody(onDone: dismiss),
    ),
    DevOverlay.firmwareUpdate => SheetOverlay(
      title: 'Update firmware',
      sub: 'Over Wi-Fi only',
      bodyBuilder: (dismiss) => FirmwareUpdateSheetBody(onDone: dismiss),
    ),
    DevOverlay.diagnostics => SheetOverlay(
      title: 'About & diagnostics',
      sub: 'Device facts and logs',
      bodyBuilder: (dismiss) => DiagnosticsSheetBody(onDone: dismiss),
    ),
    DevOverlay.verb => SheetOverlay(
      title: switch (verbFromId(request.props['kind'])) {
        final verb? => verbSpec(verb).title,
        null => 'Working…',
      },
      sub: switch (verbFromId(request.props['kind'])) {
        final verb? => verbSpec(verb).sub,
        null => 'Restart / forget / factory',
      },
      bodyBuilder: (dismiss) =>
          VerbSheetBody(onDone: dismiss, kind: request.props['kind']),
    ),
  };
}

/// Splits a `|`-separated prop into a list (empty → no items).
List<String> _propList(String? value) {
  if (value == null || value.isEmpty) {
    return const <String>[];
  }
  return value.split('|').where((s) => s.isNotEmpty).toList();
}

/// The shared sheet surface: grabber, head, scrollable body, optional foot.
class ShellSheet extends StatelessWidget {
  const ShellSheet({
    super.key,
    required this.title,
    this.sub,
    required this.body,
    this.foot,
    this.onClose,
    this.scrollController,
  });

  final String title;
  final String? sub;
  final Widget body;
  final Widget? foot;
  final VoidCallback? onClose;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      key: const ValueKey<String>('shell-overlay-sheet'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radii.card + 6),
        ),
        border: Border(top: BorderSide(color: tokens.hairlineStrong)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: tokens.hairlineStrong,
                borderRadius: BorderRadius.circular(tokens.radii.pill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        key: const ValueKey<String>('shell-overlay-title'),
                        style: SmokeText.title.copyWith(fontSize: 19),
                      ),
                      if (sub != null)
                        Text(
                          sub!,
                          key: const ValueKey<String>('shell-overlay-sub'),
                          style: SmokeText.sub.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                ShellIconButton(
                  key: const ValueKey<String>('shell-overlay-close'),
                  glyph: SmokeGlyph.x,
                  label: 'Close',
                  onTap: onClose,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: body,
            ),
          ),
          if (foot != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.hairline)),
              ),
              child: foot,
            ),
        ],
      ),
    );
  }
}

/// The shared centred confirm card.
class ShellModalCard extends StatelessWidget {
  const ShellModalCard({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel = 'Confirm',
    this.danger = false,
    this.actions,
    this.onConfirm,
    this.onCancel,
  });

  final String title;
  final Widget body;
  final String confirmLabel;
  final bool danger;

  /// Replaces the default Confirm/Cancel row (N5 adopt).
  final Widget? actions;

  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      key: const ValueKey<String>('shell-overlay-modal'),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(color: tokens.hairlineStrong),
        boxShadow: tokens.shadowCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            key: const ValueKey<String>('shell-overlay-title'),
            style: SmokeText.title.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 16),
          actions ??
              Row(
                children: <Widget>[
                  Expanded(
                    child: danger
                        ? SmokeButton(
                            key: const ValueKey<String>(
                              'shell-overlay-confirm',
                            ),
                            label: confirmLabel,
                            variant: SmokeButtonVariant.danger,
                            onPressed: onConfirm,
                          )
                        : PrimaryAction(
                            key: const ValueKey<String>(
                              'shell-overlay-confirm',
                            ),
                            label: confirmLabel,
                            onPressed: onConfirm,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SmokeButton(
                      key: const ValueKey<String>('shell-overlay-cancel'),
                      label: 'Cancel',
                      variant: SmokeButtonVariant.ghost,
                      onPressed: onCancel,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Renders the named overlay above the app area, dismiss on scrim tap.
class ShellOverlayHost extends StatelessWidget {
  const ShellOverlayHost({
    super.key,
    required this.request,
    required this.onDismiss,
    this.scrollController,
  });

  final OverlayRequest? request;
  final VoidCallback onDismiss;

  /// Preserved per-overlay body scroll (N4.11).
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final current = request;
    if (current == null) {
      return const SizedBox.shrink();
    }
    final tokens = SmokeTokens.of(context);
    final content = resolveOverlay(current);

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('shell-overlay-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: tokens.scrim),
          ),
        ),
        switch (content) {
          SheetOverlay() => Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              child: ShellSheet(
                title: content.title,
                sub: content.sub,
                body: content.bodyBuilder?.call(onDismiss) ?? content.body!,
                foot: content.footBuilder?.call(onDismiss) ?? content.foot,
                scrollController: scrollController,
                onClose: onDismiss,
              ),
            ),
          ),
          ModalOverlay() => Center(
            child: ShellModalCard(
              title: content.title,
              body: content.bodyBuilder?.call(onDismiss) ?? content.body!,
              confirmLabel: content.confirmLabel,
              danger: content.danger,
              actions:
                  content.actionsBuilder?.call(onDismiss) ?? content.actions,
              onConfirm: onDismiss,
              onCancel: onDismiss,
            ),
          ),
        },
      ],
    );
  }
}

/// Shows an in-app-styled bottom sheet. Returns when it is dismissed.
Future<void> showSheet(
  BuildContext context, {
  required String title,
  String? sub,
  required Widget body,
  Widget? foot,
}) {
  final tokens = SmokeTokens.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(tokens.radii.card + 6),
      ),
    ),
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
      ),
      child: ShellSheet(
        title: title,
        sub: sub,
        body: body,
        foot: foot,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// Shows the centred confirm card. Resolves `true` on confirm, `false`/null
/// when cancelled or dismissed by tapping the scrim.
Future<bool?> showModalCard(
  BuildContext context, {
  required String title,
  required Widget body,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) {
  final tokens = SmokeTokens.of(context);
  return showDialog<bool>(
    context: context,
    barrierColor: tokens.scrim,
    builder: (dialogContext) => ShellModalCard(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      danger: danger,
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
    ),
  );
}
