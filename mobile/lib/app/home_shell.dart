import 'package:flutter/material.dart';

import '../core/design/motion.dart';
import '../features/map/home_overview.dart';
import '../features/journeys/screens.dart';
import '../features/maintenance/screens.dart';
import '../features/settings/screens.dart';

/// Tabs are mounted on first visit and retained. In particular switching tabs
/// never destroys the map controller, camera or a selected route.
class TrafficHomeShell extends StatefulWidget {
  const TrafficHomeShell({super.key});
  @override
  State<TrafficHomeShell> createState() => _TrafficHomeShellState();
}

class _TrafficHomeShellState extends State<TrafficHomeShell> {
  int selected = 0;
  final visited = <int>{0};
  final pages = const [
    HomeOverview(),
    JourneysScreen(),
    GarageScreen(),
    SettingsScreen(),
  ];
  void select(int index) => setState(() {
    selected = index;
    visited.add(index);
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: selected == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) select(0);
    },
    child: Scaffold(
      body: IndexedStack(
        index: selected,
        children: [
          for (var i = 0; i < pages.length; i++)
            TickerMode(
              enabled: selected == i,
              child: visited.contains(i) ? pages[i] : const SizedBox.shrink(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        animationDuration: TrafficMotion.duration(context),
        selectedIndex: selected,
        onDestinationSelected: select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Bản đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Hành trình',
          ),
          NavigationDestination(
            icon: Icon(Icons.two_wheeler_outlined),
            selectedIcon: Icon(Icons.two_wheeler),
            label: 'Xe',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
    ),
  );
}
