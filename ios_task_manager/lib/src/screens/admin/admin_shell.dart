import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../profile_screen.dart';
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

  @override
  void initState() {
    super.initState();
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
    final pages = [
      AdminTasksScreen(service: widget.service),
      EmployeesScreen(service: widget.service),
      ProfileScreen(service: widget.service, currentUser: widget.currentUser),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Dashboard'),
            Text(
              widget.currentUser.fullName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_index == 0)
            IconButton(
              onPressed: _openAlerts,
              tooltip: 'Alerts',
              icon: Badge(
                isLabelVisible: _alertCount > 0,
                label: Text(_alertCount > 99 ? '99+' : '$_alertCount'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          IconButton(
            onPressed: () async {
              await widget.service.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) async {
          setState(() => _index = value);
          if (value == 0) {
            await _loadAlertCount();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
