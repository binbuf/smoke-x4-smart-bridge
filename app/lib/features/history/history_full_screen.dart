import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import 'history_chart_panel.dart';

/// Dedicated full-screen chart. It never forces an orientation: portrait and
/// landscape are both allowed, and the chart fills whichever one is active.
class HistoryFullScreenScreen extends StatelessWidget {
  const HistoryFullScreenScreen({
    super.key,
    required this.controller,
    this.historical = false,
    this.gapOverride,
  });

  final PrototypeController controller;
  final bool historical;
  final bool? gapOverride;

  HistoryFixture _fixture() {
    return buildHistoryFixture(
      controller.historyRange,
      empty: !controller.historyHasData,
      oneProbe: controller.historyOneProbe,
      estimated: controller.historyEstimated,
      missingFromBridge: controller.historyMissingFromBridge,
      hasGap: gapOverride ?? true,
      customStart: controller.historyCustomRange?.start,
      customEnd: controller.historyCustomRange?.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final fixture = _fixture();
        final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
        final window = historyWindowLabel(
          controller.historyRange,
          fixture.start,
          fixture.end,
          use24Hour: use24Hour,
        );
        final probeCount = controller.historyProbe == null ? 4 : 1;
        final dataProbeCount = controller.historyProbe == null
            ? fixture.series
                  .where(
                    (series) =>
                        series.points.any((point) => point.valueF != null),
                  )
                  .length
            : (fixture.seriesHasValues(controller.historyProbe! - 1) ? 1 : 0);
        final probeMeta = dataProbeCount == probeCount
            ? '$probeCount ${probeCount == 1 ? 'probe' : 'probes'}'
            : '$dataProbeCount of $probeCount ${probeCount == 1 ? 'probe' : 'probes'}';
        final metaLead = !fixture.hasValues
            ? 'No readings'
            : historical
            ? 'Recorded history'
            : controller.lastSyncedLabel;

        return Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 54, 10, 8),
                    child: HistoryChartPanel(
                      controller: controller,
                      fixture: fixture,
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
                              '$metaLead · $probeMeta',
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
