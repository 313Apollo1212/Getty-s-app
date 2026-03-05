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
  late Future<_EmployeeTaskPayload> _tasksFuture;

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
    _tasksFuture = _loadTasks();
  }

  Future<_EmployeeTaskPayload> _loadTasks({bool forceRefresh = false}) async {
    final results = await Future.wait<dynamic>([
      widget.service.fetchAssignmentsForCurrentEmployee(forceRefresh: forceRefresh),
      widget.service.fetchCurrentEmployeePriorityHints(forceRefresh: forceRefresh),
    ]);

    return _EmployeeTaskPayload(
      tasks: results[0] as List<TaskAssignment>,
      hintsByTitle: results[1] as Map<String, TaskPriorityHint>,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _tasksFuture = _loadTasks(forceRefresh: true);
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
          child: FutureBuilder<_EmployeeTaskPayload>(
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

              final payload =
                  snapshot.data ??
                  const _EmployeeTaskPayload(
                    tasks: <TaskAssignment>[],
                    hintsByTitle: <String, TaskPriorityHint>{},
                  );
              final allTasks = payload.tasks;
              final actionableTasks = allTasks.where(_isVisibleNow).toList();
              final todayWeekday = DateTime.now().weekday;
              final rankedTasks = <_RankedTask>[];
              for (final task in actionableTasks) {
                final key = task.title.trim().toLowerCase();
                final hint = payload.hintsByTitle[key];
                if (hint == null || hint.weekday != todayWeekday) {
                  continue;
                }
                rankedTasks.add(_RankedTask(task: task, hint: hint));
              }

              rankedTasks.sort((a, b) {
                final byPriority = a.hint.priority.compareTo(b.hint.priority);
                if (byPriority != 0) {
                  return byPriority;
                }
                final byEstimate = a.hint.estimatedMinutes.compareTo(
                  b.hint.estimatedMinutes,
                );
                if (byEstimate != 0) {
                  return byEstimate;
                }
                return a.task.expectedAt.compareTo(b.task.expectedAt);
              });

              if (rankedTasks.isEmpty) {
                return ListView(
                  padding: appPagePadding,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No tasks for ${weekdayShortLabel(todayWeekday)} yet. '
                          'This view requires Yes answers with weekday entry.',
                        ),
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: appPagePadding,
                itemCount: rankedTasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ranked = rankedTasks[index];
                  final task = ranked.task;
                  final hint = ranked.hint;
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
                        subtitle: Text(
                          '${weekdayShortLabel(hint.weekday)} • '
                          'Priority ${hint.priority} • '
                          '${formatDurationMinutes(hint.estimatedMinutes)}',
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

class _EmployeeTaskPayload {
  const _EmployeeTaskPayload({
    required this.tasks,
    required this.hintsByTitle,
  });

  final List<TaskAssignment> tasks;
  final Map<String, TaskPriorityHint> hintsByTitle;
}

class _RankedTask {
  const _RankedTask({required this.task, required this.hint});

  final TaskAssignment task;
  final TaskPriorityHint hint;
}
