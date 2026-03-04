import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
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

  bool _isActionable(TaskAssignment task) {
    return task.status == TaskStatus.pending ||
        task.status == TaskStatus.revisionRequested;
  }

  bool _isVisibleNow(TaskAssignment task) {
    if (!_isActionable(task)) {
      return false;
    }
    final nowUtc = DateTime.now().toUtc();
    return !task.showAt.toUtc().isAfter(nowUtc);
  }

  @override
  void initState() {
    super.initState();
    _tasksFuture = widget.service.fetchAssignmentsForCurrentEmployee();
  }

  Future<void> _reload() async {
    setState(() {
      _tasksFuture = widget.service.fetchAssignmentsForCurrentEmployee(
        forceRefresh: true,
      );
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
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: ProfileScreen(
            service: widget.service,
            currentUser: widget.currentUser,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Tasks'),
            Text(
              widget.currentUser.fullName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openProfile,
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<TaskAssignment>>(
            future: _tasksFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ListView(
                  children: const [
                    SizedBox(height: 160),
                    Center(child: CircularProgressIndicator()),
                  ],
                );
              }

              if (snapshot.hasError) {
                return ListView(
                  padding: appPagePadding,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(snapshot.error.toString()),
                      ),
                    ),
                  ],
                );
              }

              final allTasks = snapshot.data ?? const [];
              final tasks = allTasks.where(_isVisibleNow).toList();
              if (tasks.isEmpty) {
                return ListView(
                  padding: appPagePadding,
                  children: const [
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No tasks due right now.'),
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: appPagePadding,
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openTask(task),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        title: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
