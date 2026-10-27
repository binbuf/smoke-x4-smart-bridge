import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import 'history_chart_panel.dart';
import 'history_view_loader.dart';

/// Dedicated full-screen chart. It never forces an orientation: portrait and
/// landscape are both allowed, and the chart fills whichever one is active.
class HistoryFullScreenScreen extends StatelessWidget {
  const HistoryFullScreenScreen({
    super.key,
    required this.controller,
    this.historical = false,
    this.gapOverride,
  });

  final BridgeController controller;
  final bool historical;
  final bool? gapOverride;

  @override
  Widget build(BuildContext context) {
    return HistoryViewLoader(
      controller: controller,
      hasGap: gapOverride ?? true,
      builder: (context, view) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
        final window = view.windowLabel(use24Hour: use24Hour);
        final probeMeta = view.probeMeta;
        final metaLead = view.noData
            ? 'No readings'
            : historical
            ? 'Recorded history'
            : view.lastSyncedLabel;

        return Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 54, 10, 8),
                    child: HistoryChartPanel(
                      view: view,
                      expanded: true,
                      historical: historical,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  left: 12,
                  right: 8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              window,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$metaLead · $probeMeta'
                              '${view.estimated ? ' · times estimated' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Close full-screen chart',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_fullscreen, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
