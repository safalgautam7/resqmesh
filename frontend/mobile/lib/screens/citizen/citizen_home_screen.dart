import 'package:flutter/material.dart';

import 'alerts_screen.dart';
import 'citizen_home_tab.dart';
import 'my_reports_screen.dart';

class CitizenHomeScreen extends StatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  State<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends State<CitizenHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const CitizenHomeTab(),
          // Reload each time the tab becomes active so an offline report that
          // was later delivered shows up in "My Reports" without a manual pull.
          MyReportsScreen(isActive: _index == 1),
          const AlertsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'My Reports'),
          NavigationDestination(icon: Icon(Icons.campaign), label: 'Alerts'),
        ],
      ),
    );
  }
}
