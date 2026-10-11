/// The three destinations: Live, Graph, History.
///
/// Kept as an [IndexedStack] so each tab holds its scroll position and the
/// live connection is never torn down by a tab switch.
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../features/graph/graph_screen.dart';
import '../features/history/history_screen.dart';
import '../features/live/live_screen.dart';
import 'bridge_controller.dart';
import 'bridge_scope.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  BridgeController? _controller;
  int _seenAction = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = BridgeScope.of(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onController);
      _controller = controller;
      _seenAction = controller.actionSeq;
      controller.addListener(_onController);
    }
  }

  /// Surfaces a user-triggered action's outcome (success or failure) as a
  /// snackbar, so "nothing happened" is never the whole story.
  void _onController() {
    final controller = _controller;
    if (controller == null || controller.actionSeq == _seenAction) {
      return;
    }
    _seenAction = controller.actionSeq;
    final message = controller.actionMessage;
    if (message == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [LiveScreen(), GraphScreen(), HistoryScreen()],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SmokePalette.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.thermostat_outlined),
              selectedIcon: Icon(Icons.thermostat),
              label: 'Live',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart_outlined),
              selectedIcon: Icon(Icons.show_chart),
              label: 'Graph',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
