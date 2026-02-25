import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../utils/time_format.dart';
import '../profile_screen.dart';
import 'task_submission_screen.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({
    super.key,
    required this.service,
    required this.currentUser,
  });

  final SupabaseService service;
  final Profile currentUser;

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  late Future<List<TaskAssignment>> _tasksFuture;

  @override
  void initState() {
    super.initState();
    _tasksFuture = widget.service.fetchAssignmentsForCurrentEmployee();
  }

  Future<void> _reload() async {
    setState(() {
      _tasksFuture = widget.service.fetchAssignmentsForCurrentEmployee();
    });
  }

  Future<void> _openTask(TaskAssignment assignment) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskSubmissionScreen(
          service: widget.service,
          assignment: assignment,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          service: widget.service,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Tasks - ${widget.currentUser.fullName}'),
        actions: [
          IconButton(
            onPressed: _openProfile,
            tooltip: 'Profile',
            icon: const Icon(Icons.person),
          ),
          TextButton.icon(
            onPressed: widget.service.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<TaskAssignment>>(
          future: _tasksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(snapshot.error.toString())),
                ],
              );
            }

            final tasks = snapshot.data ?? const [];
            if (tasks.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No tasks assigned yet.')),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final task = tasks[index];

                return Card(
                  child: ListTile(
                    title: Text(task.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Expected: ${formatDateTime(task.expectedAt)}'),
                        Text(
                          task.submittedAt == null
                              ? 'Submitted: Not yet'
                              : 'Submitted: ${formatDateTime(task.submittedAt!)}',
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Chip(label: Text(task.status.label))],
                    ),
                    onTap: () => _openTask(task),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
