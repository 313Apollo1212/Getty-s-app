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
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final topInset = viewPadding.top;
    const topBarHeight = 16.0;
    const bellHitBox = 34.0;
    const navHeight = 70.0;
    final barColor =
        Theme.of(context).navigationBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: topInset + topBarHeight,
            decoration: BoxDecoration(
              color: barColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Transform.translate(
                offset: const Offset(-32, 16),
                child: IconButton(
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
                    child: const Icon(
                      Icons.notifications_rounded,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                widthFactor: 0.9,
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
                      icon: Icon(Icons.checklist_outlined),
                      selectedIcon: Icon(Icons.checklist),
                      label: 'Tasks',
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
