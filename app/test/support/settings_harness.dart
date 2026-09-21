/// N13 — a small harness that mounts the Settings page plus the real named
/// overlay host, mirroring `AppShell`'s overlay stack. Later N13 tests open
/// overlays, tap confirm and watch the verb sheet from here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/settings/settings.dart';
import 'package:smoke_bridge/features/shell/overlay.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';

/// Captures the shell callbacks a Settings row fires.
class SettingsProbe {
  OverlayRequest? request;
  String? toast;
  ShellScreen? screen;
  int overlayOpens = 0;
  int closeCalls = 0;
}

/// Mounts [child] (defaults to the Settings page) under a real overlay host.
class SettingsHarness extends StatefulWidget {
  const SettingsHarness({
    super.key,
    required this.repo,
    required this.prefs,
    required this.probe,
    this.child,
  });

  final MockBridgeRepository repo;
  final MockPrefsRepository prefs;
  final SettingsProbe probe;
  final Widget? child;

  @override
  State<SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<SettingsHarness> {
  @override
  Widget build(BuildContext context) {
    final request = widget.probe.request;
    return ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(widget.repo),
        prefsProvider.overrideWithValue(widget.prefs),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: ShellScope(
            openOverlay:
                (DevOverlay overlay, [Map<String, String> props = const {}]) {
                  widget.probe.overlayOpens += 1;
                  setState(() {
                    widget.probe.request = OverlayRequest(overlay, props);
                  });
                },
            closeOverlay: () {
              widget.probe.closeCalls += 1;
              setState(() => widget.probe.request = null);
            },
            showToast: (message) => widget.probe.toast = message,
            toggleFullGraph: () {},
            openScreen: (screen) => widget.probe.screen = screen,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: widget.child ?? const SettingsPage()),
                if (request != null)
                  Positioned.fill(
                    child: ShellOverlayHost(
                      request: request,
                      onDismiss: () {
                        widget.probe.closeCalls += 1;
                        setState(() => widget.probe.request = null);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pumps the harness at a tall surface so the whole settings tree lays out.
Future<SettingsProbe> pumpSettings(
  WidgetTester tester, {
  required MockBridgeRepository repo,
  required MockPrefsRepository prefs,
  Widget? child,
  Size size = const Size(500, 6000),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final probe = SettingsProbe();
  await tester.pumpWidget(
    SettingsHarness(repo: repo, prefs: prefs, probe: probe, child: child),
  );
  await tester.pumpAndSettle();
  return probe;
}
