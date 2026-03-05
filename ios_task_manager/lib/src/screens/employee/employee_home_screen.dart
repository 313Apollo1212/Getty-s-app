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
  int _tabIndex = 0;
  DateTime _calendarDate = DateTime.now();

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

  List<_RankedTask> _buildRankedTasksForWeekday(
    _EmployeeTaskPayload payload,
    int weekday,
  ) {
    final allTasks = payload.tasks;
    final actionableTasks = allTasks.where(_isVisibleNow).toList();
    final rankedTasks = <_RankedTask>[];
    for (final task in actionableTasks) {
      final key = task.title.trim().toLowerCase();
      final hint = payload.hintsByTitle[key];
      rankedTasks.add(
        _RankedTask(
          task: task,
          hint: hint != null && hint.weekday == weekday ? hint : null,
        ),
      );
    }

    rankedTasks.sort((a, b) {
      final aHasHint = a.hint != null;
      final bHasHint = b.hint != null;
      if (aHasHint != bHasHint) {
        return aHasHint ? -1 : 1;
      }

      if (!aHasHint || !bHasHint) {
        return a.task.expectedAt.compareTo(b.task.expectedAt);
      }

      final byPriority = a.hint!.priority.compareTo(b.hint!.priority);
      if (byPriority != 0) {
        return byPriority;
      }
      final byEstimate = a.hint!.estimatedMinutes.compareTo(
        b.hint!.estimatedMinutes,
      );
      if (byEstimate != 0) {
        return byEstimate;
      }
      return a.task.expectedAt.compareTo(b.task.expectedAt);
    });
    return rankedTasks;
  }

  Widget _buildRankedTaskList({
    required List<_RankedTask> rankedTasks,
    required String emptyMessage,
  }) {
    if (rankedTasks.isEmpty) {
      return ListView(
        padding: appPagePadding,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyMessage),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: hint == null
                  ? const Text('Tap to submit')
                  : Text(
                      '${weekdayShortLabel(hint.weekday)} • '
                      'Priority ${hint.priority} • '
                      '${formatDurationMinutes(hint.estimatedMinutes)}',
                    ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_tabIndex == 2) {
      return AppBar(title: const Text('Profile'));
    }
    if (_tabIndex == 1) {
      return AppBar(title: const Text('Calendar'));
    }
    return AppBar(
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
    );
  }

  Widget _buildTasksAndCalendarTab() {
    return AppBackground(
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

            if (_tabIndex == 1) {
              final selectedWeekday = _calendarDate.weekday;
              final rankedTasks = _buildRankedTasksForWeekday(
                payload,
                selectedWeekday,
              );
              return ListView(
                padding: appPagePadding,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CalendarDatePicker(
                        initialDate: _calendarDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        onDateChanged: (value) {
                          setState(() => _calendarDate = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${weekdayShortLabel(selectedWeekday)} tasks',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.45,
                    child: _buildRankedTaskList(
                      rankedTasks: rankedTasks,
                      emptyMessage:
                          'No tasks for ${weekdayShortLabel(selectedWeekday)} yet.',
                    ),
                  ),
                ],
              );
            }

            final todayWeekday = DateTime.now().weekday;
            final rankedTasks = _buildRankedTasksForWeekday(
              payload,
              todayWeekday,
            );
            return _buildRankedTaskList(
              rankedTasks: rankedTasks,
              emptyMessage:
                  'No tasks available right now.',
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _tabIndex == 2
          ? ProfileScreen(
              service: widget.service,
              currentUser: widget.currentUser,
            )
          : _buildTasksAndCalendarTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) {
          setState(() => _tabIndex = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
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
  final TaskPriorityHint? hint;
}
