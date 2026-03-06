import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../profile_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_tasks_screen.dart';
import 'employees_screen.dart';
import 'task_alerts_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.service,
    required this.currentUser,
  });

  final SupabaseService service;
  final Profile currentUser;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  int _alertCount = 0;
  late final List<Widget> _pages;
  static const _titles = ['Dashboard', 'Add', 'Users', 'Profile'];

  @override
  void initState() {
    super.initState();
    _pages = [
      AdminDashboardScreen(service: widget.service),
      AdminTasksScreen(service: widget.service),
      EmployeesScreen(service: widget.service),
      ProfileScreen(service: widget.service, currentUser: widget.currentUser),
    ];
    _loadAlertCount();
  }

  Future<void> _loadAlertCount() async {
    try {
      final count = await widget.service.fetchFlaggedTaskAlertCount();
      if (!mounted) {
        return;
      }
      setState(() => _alertCount = count);
    } catch (_) {}
  }

  Future<void> _openAlerts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskAlertsScreen(service: widget.service),
      ),
    );
    if (mounted) {
      await _loadAlertCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    const bellHitBox = 38.0;
    const navHeight = 72.0;
    final barColor =
        Theme.of(context).navigationBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: barColor,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _titles[_index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _openAlerts,
                    tooltip: 'Alerts',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(bellHitBox, bellHitBox),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Badge(
                      isLabelVisible: _alertCount > 0,
                      label: Text(_alertCount > 99 ? '99+' : '$_alertCount'),
                      child: const Icon(Icons.notifications_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: IndexedStack(index: _index, children: _pages),
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: barColor,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: navHeight,
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.92,
                child: NavigationBar(
                  backgroundColor: barColor,
                  height: navHeight,
                  selectedIndex: _index,
                  onDestinationSelected: (value) async {
                    setState(() => _index = value);
                    await _loadAlertCount();
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      selectedIcon: Icon(Icons.space_dashboard),
                      label: 'Dashboard',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.add_circle_outline),
                      selectedIcon: Icon(Icons.add_circle),
                      label: 'Add',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Users',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
