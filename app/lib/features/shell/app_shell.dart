import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/lab_gate.dart';
import '../../debug/scenario_lab.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import '../history/history_screen.dart';
import '../live/live_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.enableExperimentalLab = experimentalLabEnabled,
  });

  final BridgeController controller;
  final bool enableExperimentalLab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        const titles = ['Live', 'History', 'Settings'];
        final tab = controller.tab;
        return Scaffold(
          appBar: prototypeAppBar(
            context,
            controller,
            titles[tab.index],
            highlightedTitle: false,
            actions: [
              if (enableExperimentalLab)
                PopupMenuButton<String>(
                  key: const Key('nav.experimental'),
                  tooltip: 'App menu',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value != 'experimental') return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ScenarioLabScreen(controller: controller),
                      ),
                    );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'experimental',
                      child: Row(
                        children: [
                          Icon(Icons.science_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Experimental lab'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              if (tab == AppTab.history)
                ConnectionBanner(
                  view: controller.liveView,
                  onRetry: controller.retryConnection,
                ),
              Expanded(
                child: IndexedStack(
                  index: tab.index,
                  children: [
                    LiveScreen(controller: controller),
                    HistoryScreen(controller: controller),
                    SettingsScreen(
                      controller: controller,
                      enableExperimentalLab: enableExperimentalLab,
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (index) =>
                controller.setTab(AppTab.values[index]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.thermostat_outlined),
                selectedIcon: Icon(Icons.thermostat),
                label: 'Live',
              ),
              NavigationDestination(
                icon: Icon(Icons.timeline_outlined),
                selectedIcon: Icon(Icons.timeline),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
