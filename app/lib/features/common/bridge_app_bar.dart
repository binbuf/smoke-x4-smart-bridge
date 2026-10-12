/// The one app bar every tab wears.
///
/// It owns the title, the [ConnectionChip], the manual sync control (with its
/// busy/error/disabled states) and the [UnitToggle]. Keeping all four here is
/// the whole point: the sync logic and the unit control exist once, so a tab
/// can never drift into its own slightly-different copy.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/tokens.dart';
import 'connection.dart';
import 'unit_toggle.dart';

class BridgeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BridgeAppBar({super.key, required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    return AppBar(
      title: Text(title),
      actions: [
        const ConnectionChip(),
        const SizedBox(width: SmokeSpace.sm),
        _SyncButton(controller: controller),
        const SizedBox(width: SmokeSpace.sm),
        const UnitToggle(),
      ],
    );
  }
}

/// The manual "pull history now" control. It is disabled with no link, spins
/// while a sync is in flight, and turns warning-coloured when the last sync
/// failed — so the control itself is where "sync is not working" is visible.
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: controller.syncing
          ? 'Syncing…'
          : (controller.syncError ?? 'Sync now'),
      onPressed: controller.connected ? controller.syncNow : null,
      icon: controller.syncing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(
              controller.syncError == null ? Icons.sync : Icons.sync_problem,
              color: controller.syncError == null
                  ? null
                  : SmokePalette.warning,
            ),
    );
  }
}
