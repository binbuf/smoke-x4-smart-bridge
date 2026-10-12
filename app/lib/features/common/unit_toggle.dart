/// The one temperature-unit control.
///
/// Present in every tab's app bar, so a user reading the Graph or History can
/// switch °F/°C without returning to Live. It reads and writes the controller's
/// persisted preference, so the choice survives a relaunch.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_scope.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';

class UnitToggle extends StatelessWidget {
  const UnitToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    final unit = controller.unit;
    return PopupMenuButton<TempUnit>(
      tooltip: 'Temperature unit',
      initialValue: unit,
      onSelected: controller.setUnit,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => const [
        PopupMenuItem(value: TempUnit.fahrenheit, child: Text('Fahrenheit')),
        PopupMenuItem(value: TempUnit.celsius, child: Text('Celsius')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeSpace.sm,
          vertical: SmokeSpace.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unit == TempUnit.celsius ? '°C' : '°F',
              style: const TextStyle(
                color: SmokePalette.textHi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: SmokePalette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
