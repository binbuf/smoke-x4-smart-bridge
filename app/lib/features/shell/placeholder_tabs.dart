/// A24.1 — placeholder Alarms and Bridge tabs (design 13 §13.3.3).
///
/// These are the **seam** agent B fills. `AppShell` references [AlarmsTab] and
/// [BridgeTab] by name; today they resolve here, to a branded empty state that
/// says what is coming. When agent B lands the real screens at
/// `features/alarms/alarms_tab.dart` and `features/bridge/bridge_tab.dart`
/// (each exporting a widget of the same name), integration is a one-line import
/// swap in `app_shell.dart` — the call sites do not change.
///
/// Kept out of `ui/`: these are feature screens, not primitives.
library;

import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// Tab 2 — two-tier alarms, quiet hours, delivery status and the alarm log
/// (13 §13.3.3). **Acknowledgement is not here** — that is one tap on the Cook
/// tab's AlarmBar (§13.3.3).
class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    key: Key('alarms-tab'),
    icon: Icons.notifications_none_rounded,
    title: 'Alarms',
    message:
        'Two tiers, quiet hours, delivery status and the alarm log land here. '
        'To silence a ringing alarm, use the bar on the Cook tab.',
  );
}

/// Tab 3 — the device: probes, network, power, firmware, pairing, paired
/// phones, forget/replace (13 §13.3.3).
class BridgeTab extends StatelessWidget {
  const BridgeTab({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    key: Key('bridge-tab'),
    icon: Icons.router_outlined,
    title: 'Bridge',
    message:
        'Probes, network, power, firmware and pairing for your bridge land '
        'here.',
  );
}
