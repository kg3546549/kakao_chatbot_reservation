import 'package:flutter/material.dart';
import 'dashboard_tab.dart';
import 'history_tab.dart';
import 'statistics_tab.dart';
import 'templates_tab.dart';
import 'settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = [
    const DashboardTab(),
    const HistoryTab(),
    const StatisticsTab(),
    const TemplatesTab(),
    const SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '대시보드'),
          NavigationDestination(icon: Icon(Icons.history), label: '이력'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '통계'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: '항목 설정'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
