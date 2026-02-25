import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../profile_screen.dart';
import 'admin_tasks_screen.dart';
import 'employees_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final pages = [
      EmployeesScreen(service: widget.service),
      AdminTasksScreen(service: widget.service),
      ProfileScreen(service: widget.service, currentUser: widget.currentUser),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard - ${widget.currentUser.fullName}'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await widget.service.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
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
