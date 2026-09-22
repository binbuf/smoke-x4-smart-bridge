/// N16.5 — the key named overlays.
///
/// The overlay half of the N16.5 golden set. Each case is the real
/// [ShellOverlayHost] resolving a [DevOverlay] exactly as the shell does (the
/// same resolver a deep link and the dev panel use), rendered over a pinned
/// repository so the description is deterministic. They use the default dark /
/// compact theme: the destination matrix (`destination_matrix_golden_test.dart`)
/// and the design gallery already pin the appearance axes.
///
/// `settle: false` is used where a body owns an indeterminate or paced
/// animation (the verb sheet's step timer, the onboarding scan ring, the
/// firmware progress): the description records structure and copy, not pixels,
/// so a fixed number of frames is still deterministic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/alarms/alarms_sheet.dart';
import 'package:smoke_bridge/features/shell/overlay.dart';

import '../support/load_fonts.dart';
import 'golden.dart';

/// A fixed instant: the status clock, the alarm ages and the wizard agree.
final DateTime _fixedNow = DateTime(2026, 9, 21, 9, 41);

typedef _OverlayCase = ({
  DevOverlay name,
  Map<String, String> props,
  String scenario,
  bool settle,
});

/// One entry per real named overlay in `resolveOverlay` (both alert tiers).
final List<(String, _OverlayCase)> _cases = <(String, _OverlayCase)>[
  (
    'probe',
    (
      name: DevOverlay.probe,
      props: {'jack': '3'},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'setup',
    (
      name: DevOverlay.setup,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'custom_food',
    (
      name: DevOverlay.customFood,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'connect',
    (
      name: DevOverlay.connect,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'modes',
    (
      name: DevOverlay.modes,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'modes_ref',
    (
      name: DevOverlay.modesRef,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'provision_sta',
    (
      name: DevOverlay.provisionSta,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'provision_ap',
    (
      name: DevOverlay.provisionAp,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'alarms',
    (
      name: DevOverlay.alarms,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'alarm_detail_device',
    (
      name: DevOverlay.alarmDetail,
      props: {'id': 'pit_crash', 'tier': 'device'},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'alarm_detail_app',
    (
      name: DevOverlay.alarmDetail,
      props: {'id': 'eta_soon', 'tier': 'app'},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'mark',
    (name: DevOverlay.mark, props: const {}, scenario: 'running', settle: true),
  ),
  (
    'edit_start',
    (
      name: DevOverlay.editStart,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'adopt',
    (
      name: DevOverlay.adopt,
      props: const {},
      scenario: 'existing',
      settle: true,
    ),
  ),
  (
    'onboarding',
    (
      name: DevOverlay.onboarding,
      props: const {},
      scenario: 'running',
      settle: false,
    ),
  ),
  (
    'firmware',
    (
      name: DevOverlay.firmware,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'firmware_update',
    (
      name: DevOverlay.firmwareUpdate,
      props: const {},
      scenario: 'running',
      settle: false,
    ),
  ),
  (
    'diagnostics',
    (
      name: DevOverlay.diagnostics,
      props: const {},
      scenario: 'running',
      settle: true,
    ),
  ),
  (
    'verb_restart',
    (
      name: DevOverlay.verb,
      props: {'kind': 'restart'},
      scenario: 'running',
      settle: false,
    ),
  ),
  (
    'confirm',
    (
      name: DevOverlay.confirm,
      props: {
        'title': 'Restart the bridge',
        'confirm': 'Restart',
        'danger': '1',
        'message': 'The bridge restarts and the cook keeps recording.',
        'keeps': 'The recording|The current cook',
        'loses': 'The live link for about a minute',
      },
      scenario: 'running',
      settle: true,
    ),
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final (key, overlayCase) in _cases) {
    final name = 'overlay_$key';
    testWidgets('$name matches its committed golden', (tester) async {
      final prefs = MockPrefsRepository();
      addTearDown(prefs.dispose);

      await pumpForGolden(
        tester,
        ProviderScope(
          overrides: [
            alarmsNowProvider.overrideWithValue(_fixedNow),
            prefsProvider.overrideWithValue(prefs),
            bridgeRepositoryProvider.overrideWith((ref) {
              final repo = MockBridgeRepository(
                nowMs: _fixedNow.millisecondsSinceEpoch,
                initialScenario: overlayCase.scenario,
              );
              ref.onDispose(repo.dispose);
              return repo;
            }),
          ],
          child: MaterialApp(
            theme: SmokeThemeData.dark(),
            home: Scaffold(
              body: ShellOverlayHost(
                request: OverlayRequest(overlayCase.name, overlayCase.props),
                onDismiss: _noop,
              ),
            ),
          ),
        ),
        settle: overlayCase.settle,
      );

      expectGolden(tester, name);
    });
  }
}

void _noop() {}
