/// N2.31 — the dev-only prototype control panel.
///
/// The right-hand panel from `newui/index.html` (`index.html` §devpanel,
/// `app.js` §5 `renderDev`): scenario, screen, overlay and mock-event switches
/// plus the units / theme / profile controls, driven entirely by the pure-Dart
/// [DevPanelController].
///
/// **Release-excluded.** [build] collapses to an empty box under
/// [kReleaseMode], so the tree-shaker drops it and the whole mock surface with
/// it. The N4 shell mounts it beside the phone frame and supplies navigation
/// through [onScreen] / [onOverlay]; this widget never navigates itself.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/model/bridge_snapshot.dart';
import '../../data/model/mock_event.dart';
import '../../data/providers.dart';
import '../../design/theme.dart';
import '../../domain/domain.dart';

/// The labels the prototype's panel uses for the overlays that need no props.
const Map<DevOverlay, String> kDevOverlayLabels = <DevOverlay, String>{
  DevOverlay.onboarding: 'Onboarding',
  DevOverlay.setup: 'Cook setup',
  DevOverlay.connect: 'Connection',
  DevOverlay.modes: 'Modes',
  DevOverlay.modesRef: 'Modes reference',
  DevOverlay.provisionSta: 'Join Wi-Fi',
  DevOverlay.provisionAp: 'Hotspot',
  DevOverlay.alarms: 'Alerts',
  DevOverlay.mark: 'Add mark',
  DevOverlay.adopt: 'Adopt',
  DevOverlay.editStart: 'Edit start',
  DevOverlay.customFood: 'Custom food',
  DevOverlay.firmware: 'Firmware',
  DevOverlay.firmwareUpdate: 'Update firmware',
  DevOverlay.diagnostics: 'Diagnostics',
};

/// The prototype's right-hand panel.
class DevPanel extends ConsumerWidget {
  const DevPanel({super.key, this.onScreen, this.onOverlay});

  /// Called when a screen button is tapped. N4.3 routes it.
  final void Function(DevScreen screen)? onScreen;

  /// Called when an overlay button is tapped. N4.7 routes it.
  final void Function(DevOverlay overlay, Map<String, String> props)? onOverlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kReleaseMode) {
      return const SizedBox.shrink();
    }

    final repository = ref.watch(bridgeRepositoryProvider);
    final prefs = ref.watch(prefsProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // Rebuild the active-scenario highlight whenever a scenario switches.
    ref.watch(snapshotProvider);

    final controller = DevPanelController(
      repository: repository,
      prefs: prefs,
      onScreen: onScreen,
      onOverlay: onOverlay,
    );

    return Material(
      color: SmokeTheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Prototype controls',
              style: TextStyle(
                fontFamily: SmokeTheme.displayFont,
                fontSize: 18,
                color: SmokeTheme.textHi,
              ),
            ),
            const _Label('Scenario (bridge state)'),
            _ScenarioButtons(
              controller: controller,
              activeKey: repository.activeScenarioKey,
            ),
            const _Label('Screens'),
            _ScreenButtons(controller: controller),
            const _Label('Overlays / flows'),
            _OverlayButtons(controller: controller),
            const _Label('Mock event bus'),
            _EventButtons(
              controller: controller,
              events: repository.mockEvents,
            ),
            const _Label('Settings'),
            _SettingsButtons(controller: controller, settings: settings),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: SmokeTheme.ember,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ScenarioButtons extends StatelessWidget {
  const _ScenarioButtons({required this.controller, required this.activeKey});

  final DevPanelController controller;
  final String activeKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final Scenario scenario in controller.scenarios)
          _PanelButton(
            key: ValueKey<String>('dev-scenario-${scenario.key}'),
            label: scenario.label,
            selected: scenario.key == activeKey,
            onPressed: () => unawaited(controller.applyScenario(scenario.key)),
          ),
      ],
    );
  }
}

class _ScreenButtons extends StatelessWidget {
  const _ScreenButtons({required this.controller});

  final DevPanelController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final DevScreen screen in DevScreen.values)
          _PanelButton(
            key: ValueKey<String>('dev-screen-${screen.name}'),
            label: screen.name,
            onPressed: () => controller.onScreen?.call(screen),
          ),
      ],
    );
  }
}

class _OverlayButtons extends StatelessWidget {
  const _OverlayButtons({required this.controller});

  final DevPanelController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final MapEntry<DevOverlay, String> entry
            in kDevOverlayLabels.entries)
          _PanelButton(
            key: ValueKey<String>('dev-overlay-${entry.key.name}'),
            label: entry.value,
            onPressed: () => controller.onOverlay?.call(entry.key, const {}),
          ),
      ],
    );
  }
}

class _EventButtons extends StatelessWidget {
  const _EventButtons({required this.controller, required this.events});

  final DevPanelController controller;
  final List<MockEventSpec> events;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final MockEventSpec event in events)
          Tooltip(
            message: event.hint,
            child: _PanelButton(
              key: ValueKey<String>('dev-event-${event.id}'),
              label: event.label,
              onPressed: () => unawaited(controller.fireEvent(event.id)),
            ),
          ),
      ],
    );
  }
}

class _SettingsButtons extends StatelessWidget {
  const _SettingsButtons({required this.controller, required this.settings});

  final DevPanelController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final units = settings.units == TempUnit.celsius
        ? TempUnit.fahrenheit
        : TempUnit.celsius;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _PanelButton(
          key: const ValueKey<String>('dev-units'),
          label: 'Units: ${settings.units.suffix}',
          onPressed: () => unawaited(controller.setUnits(units)),
        ),
        _PanelButton(
          key: const ValueKey<String>('dev-theme'),
          label: 'Theme: ${settings.themeMode.name}',
          onPressed: () => unawaited(controller.cycleTheme()),
        ),
        _PanelButton(
          key: const ValueKey<String>('dev-profile'),
          label: 'Profile: ${settings.displayProfile.name}',
          onPressed: () => unawaited(controller.toggleProfile()),
        ),
        _PanelButton(
          key: const ValueKey<String>('dev-connect'),
          label: 'Simulate connection sheet',
          onPressed: controller.openConnect,
        ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: selected ? SmokeTheme.background : SmokeTheme.textBody,
      backgroundColor: selected ? SmokeTheme.ember : null,
      side: BorderSide(
        color: selected ? SmokeTheme.ember : const Color(0xFF253044),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: const Size(0, 32),
      textStyle: const TextStyle(fontSize: 12),
    );
    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
