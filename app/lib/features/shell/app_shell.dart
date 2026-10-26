import 'package:flutter/material.dart';

import '../../prototype/prototype_controller.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import '../history/history_screen.dart';
import '../live/live_screen.dart';
import '../settings/bridge_details.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final PrototypeController controller;

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
            actions: [
              if (tab != AppTab.settings)
                ConnectionStatusChip(
                  controller: controller,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BridgeDetailsScreen(controller: controller),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (tab != AppTab.settings)
                ConnectionBanner(controller: controller),
              Expanded(
                child: IndexedStack(
                  index: tab.index,
                  children: [
                    LiveScreen(controller: controller),
                    HistoryScreen(controller: controller),
                    SettingsScreen(controller: controller),
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
