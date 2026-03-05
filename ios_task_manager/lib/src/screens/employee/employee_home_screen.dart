import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';
import '../profile_screen.dart';
import 'task_submission_screen.dart';

const _dailyCapacityMinutes = 8 * 60;
const _extraTimeMinuteSteps = <int>[
  15,
  30,
  45,
  60,
  75,
  90,
  120,
  150,
  180,
  240,
];

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
  _TaskBoardTab _taskBoardTab = _TaskBoardTab.assessment;
  GeneratedTaskOutcome _activeOutcome = GeneratedTaskOutcome.done;
  double _extraTimeIndex = 0;
  String? _activeOccurrenceKey;
  bool _isSavingGeneratedAction = false;

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
      widget.service.fetchCurrentEmployeeGeneratedTasks(forceRefresh: forceRefresh),
      widget.service.fetchCurrentEmployeeGeneratedTaskLogs(
        workDate: DateTime.now(),
        forceRefresh: forceRefresh,
      ),
    ]);

    return _EmployeeTaskPayload(
      tasks: results[0] as List<TaskAssignment>,
      generatedTasks: results[1] as List<GeneratedTaskItem>,
      todayTaskActionLogs: results[2] as List<GeneratedTaskActionLog>,
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

  List<TaskAssignment> _buildAssessments(_EmployeeTaskPayload payload) {
    final tasks = payload.tasks.where(_isVisibleNow).toList();
    tasks.sort((a, b) => a.expectedAt.compareTo(b.expectedAt));
    return tasks;
  }

  int _totalMinutesForDay(List<_PlannedTaskOccurrence> items) {
    return items.fold<int>(0, (sum, item) => sum + item.item.estimatedMinutes);
  }

  int _extraMinutesValue() {
    return _extraTimeMinuteSteps[_extraTimeIndex.round()];
  }

  Map<int, List<_PlannedTaskOccurrence>> _buildBalancedWeekSchedule(
    List<GeneratedTaskItem> sourceItems,
  ) {
    final schedule = <int, List<_PlannedTaskOccurrence>>{
      for (var day = 1; day <= 7; day++) day: <_PlannedTaskOccurrence>[],
    };

    for (final item in sourceItems) {
      final uniqueDays = item.weekdays.toSet().where((day) => day >= 1 && day <= 7);
      for (final day in uniqueDays) {
        schedule[day]!.add(
          _PlannedTaskOccurrence(
            item: item,
            originalWeekday: day,
            scheduledWeekday: day,
          ),
        );
      }
    }

    for (var day = 1; day <= 6; day++) {
      final current = schedule[day]!;
      final next = schedule[day + 1]!;
      var total = _totalMinutesForDay(current);
      if (total <= _dailyCapacityMinutes) {
        continue;
      }

      var overflow = total - _dailyCapacityMinutes;
      final orderedToMove = [...current]..sort((a, b) {
        final byPriority = b.item.priority.compareTo(a.item.priority);
        if (byPriority != 0) {
          return byPriority;
        }
        final byEstimate = b.item.estimatedMinutes.compareTo(
          a.item.estimatedMinutes,
        );
        if (byEstimate != 0) {
          return byEstimate;
        }
        return a.item.prompt.toLowerCase().compareTo(
          b.item.prompt.toLowerCase(),
        );
      });

      final toMove = <_PlannedTaskOccurrence>{};
      for (final candidate in orderedToMove) {
        if (overflow <= 0) {
          break;
        }
        toMove.add(candidate);
        overflow -= candidate.item.estimatedMinutes;
      }

      if (toMove.isEmpty) {
        continue;
      }

      current.removeWhere((item) => toMove.contains(item));
      for (final moved in orderedToMove.where(toMove.contains)) {
        next.add(
          _PlannedTaskOccurrence(
            item: moved.item,
            originalWeekday: moved.originalWeekday,
            scheduledWeekday: day + 1,
          ),
        );
      }
      total = _totalMinutesForDay(current);
      if (total < 0) {
        break;
      }
    }

    for (var day = 1; day <= 7; day++) {
      schedule[day]!.sort((a, b) {
        final byPriority = a.item.priority.compareTo(b.item.priority);
        if (byPriority != 0) {
          return byPriority;
        }
        final byEstimate = a.item.estimatedMinutes.compareTo(
          b.item.estimatedMinutes,
        );
        if (byEstimate != 0) {
          return byEstimate;
        }
        return a.item.prompt.toLowerCase().compareTo(
          b.item.prompt.toLowerCase(),
        );
      });
    }
    return schedule;
  }

  Widget _buildAssessmentCard(TaskAssignment task) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openTask(task),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          title: Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: Text(
            'Due ${formatDateTime(task.expectedAt)}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  String _occurrenceKey(_PlannedTaskOccurrence entry) {
    return '${entry.item.categoryTitle.trim().toLowerCase()}|'
        '${entry.item.prompt.trim().toLowerCase()}|'
        '${entry.originalWeekday}|${entry.scheduledWeekday}|'
        '${entry.item.priority}|${entry.item.estimatedMinutes}';
  }

  List<_PlannedTaskOccurrence> _filterCompletedOccurrencesForToday(
    List<_PlannedTaskOccurrence> source,
    List<GeneratedTaskActionLog> logs,
  ) {
    final remainingByKey = <String, int>{};
    for (final log in logs) {
      final key = '${log.categoryTitle.trim().toLowerCase()}|'
          '${log.prompt.trim().toLowerCase()}|'
          '${log.originalWeekday}|${log.scheduledWeekday}|'
          '${log.priority}|${log.estimatedMinutes}';
      remainingByKey[key] = (remainingByKey[key] ?? 0) + 1;
    }

    final result = <_PlannedTaskOccurrence>[];
    for (final entry in source) {
      final key = _occurrenceKey(entry);
      final used = remainingByKey[key] ?? 0;
      if (used > 0) {
        remainingByKey[key] = used - 1;
        continue;
      }
      result.add(entry);
    }
    return result;
  }

  void _syncActiveOccurrenceState(_PlannedTaskOccurrence active) {
    final key = _occurrenceKey(active);
    if (_activeOccurrenceKey == key) {
      return;
    }
    _activeOccurrenceKey = key;
    _activeOutcome = GeneratedTaskOutcome.done;
    _extraTimeIndex = 0;
  }

  Future<void> _submitTopGeneratedTask(
    _PlannedTaskOccurrence entry,
  ) async {
    if (_isSavingGeneratedAction) {
      return;
    }

    setState(() => _isSavingGeneratedAction = true);
    try {
      await widget.service.saveGeneratedTaskAction(
        categoryTitle: entry.item.categoryTitle,
        prompt: entry.item.prompt,
        scheduledWeekday: entry.scheduledWeekday,
        originalWeekday: entry.originalWeekday,
        priority: entry.item.priority,
        estimatedMinutes: entry.item.estimatedMinutes,
        outcome: _activeOutcome,
        extraMinutes: _activeOutcome == GeneratedTaskOutcome.needsMoreTime
            ? _extraMinutesValue()
            : null,
        workDate: DateTime.now(),
      );

      if (!mounted) {
        return;
      }

      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSavingGeneratedAction = false);
      }
    }
  }

  Widget _buildGeneratedTaskCard(_PlannedTaskOccurrence entry) {
    final item = entry.item;
    final weekdaysLabel = item.weekdays.map(weekdayShortLabel).join(', ');
    final shifted = entry.originalWeekday != entry.scheduledWeekday;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(
          item.prompt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          shifted
              ? '${item.categoryTitle} • ${formatDurationMinutes(item.estimatedMinutes)} • shifted from ${weekdayShortLabel(entry.originalWeekday)}'
              : '${item.categoryTitle} • $weekdaysLabel • ${formatDurationMinutes(item.estimatedMinutes)}',
        ),
        trailing: Chip(label: Text('P${item.priority}')),
      ),
    );
  }

  Widget _buildTopActionCard(_PlannedTaskOccurrence entry) {
    final item = entry.item;
    final shifted = entry.originalWeekday != entry.scheduledWeekday;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.prompt,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Chip(label: Text('P${item.priority}')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              shifted
                  ? '${item.categoryTitle} • shifted from ${weekdayShortLabel(entry.originalWeekday)}'
                  : item.categoryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Estimated: ${formatDurationMinutes(item.estimatedMinutes)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OutcomeButton(
                    label: 'Completed',
                    selected: _activeOutcome == GeneratedTaskOutcome.done,
                    onPressed: () {
                      setState(
                        () => _activeOutcome = GeneratedTaskOutcome.done,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OutcomeButton(
                    label: 'Not Completed',
                    selected: _activeOutcome == GeneratedTaskOutcome.notDone,
                    onPressed: () {
                      setState(
                        () => _activeOutcome = GeneratedTaskOutcome.notDone,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OutcomeButton(
                    label: 'Needs More Time',
                    selected:
                        _activeOutcome == GeneratedTaskOutcome.needsMoreTime,
                    onPressed: () {
                      setState(
                        () =>
                            _activeOutcome = GeneratedTaskOutcome.needsMoreTime,
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_activeOutcome == GeneratedTaskOutcome.needsMoreTime) ...[
              const SizedBox(height: 10),
              Text(
                'More time needed: ${formatDurationMinutes(_extraMinutesValue())}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _extraTimeIndex,
                min: 0,
                max: (_extraTimeMinuteSteps.length - 1).toDouble(),
                divisions: _extraTimeMinuteSteps.length - 1,
                label: formatDurationMinutes(_extraMinutesValue()),
                onChanged: (value) {
                  setState(() => _extraTimeIndex = value);
                },
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: _isSavingGeneratedAction
                  ? null
                  : () => _submitTopGeneratedTask(entry),
              icon: const Icon(Icons.check),
              label: Text(
                _isSavingGeneratedAction ? 'Saving...' : 'Save and Next',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskBoardSegmentedControl() {
    return SegmentedButton<_TaskBoardTab>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1C4A2A);
          }
          return const Color(0xFFF3F6EF);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return const Color(0xFF1D2A1F);
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const BorderSide(color: Color(0xFF1C4A2A), width: 1.5);
          }
          return const BorderSide(color: Color(0xFFC9D6C7));
        }),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      segments: const [
        ButtonSegment<_TaskBoardTab>(
          value: _TaskBoardTab.assessment,
          label: Text('Assessment'),
        ),
        ButtonSegment<_TaskBoardTab>(
          value: _TaskBoardTab.tasks,
          label: Text('Tasks'),
        ),
      ],
      selected: {_taskBoardTab},
      onSelectionChanged: (selection) {
        setState(() => _taskBoardTab = selection.first);
      },
    );
  }

  Widget _buildTaskTab(_EmployeeTaskPayload payload) {
    final assessments = _buildAssessments(payload);
    final weekday = DateTime.now().weekday;
    final balanced = _buildBalancedWeekSchedule(payload.generatedTasks);
    final generated = balanced[weekday] ?? const <_PlannedTaskOccurrence>[];
    final pendingGenerated = _filterCompletedOccurrencesForToday(
      generated,
      payload.todayTaskActionLogs,
    );
    final isAssessment = _taskBoardTab == _TaskBoardTab.assessment;

    final children = <Widget>[
      Text(
        isAssessment
            ? 'Assessment forms'
            : '${weekdayShortLabel(weekday)} tasks '
                '(${formatDurationMinutes(_totalMinutesForDay(pendingGenerated))}/8h)',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
    ];

    if (isAssessment) {
      if (assessments.isEmpty) {
        children.add(
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No assessments available right now.'),
            ),
          ),
        );
      } else {
        for (final task in assessments) {
          children.add(_buildAssessmentCard(task));
          children.add(const SizedBox(height: 10));
        }
      }
    } else {
      if (pendingGenerated.isEmpty) {
        children.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'All tasks for ${weekdayShortLabel(weekday)} are complete.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        );
      } else {
        final top = pendingGenerated.first;
        _syncActiveOccurrenceState(top);
        children.add(_buildTopActionCard(top));
      }
    }

    return ListView(padding: appPagePadding, children: children);
  }

  Widget _buildCalendarTab(_EmployeeTaskPayload payload) {
    final selectedWeekday = _calendarDate.weekday;
    final balanced = _buildBalancedWeekSchedule(payload.generatedTasks);
    final generated = balanced[selectedWeekday] ?? const <_PlannedTaskOccurrence>[];

    final children = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CalendarDatePicker(
            initialDate: _calendarDate,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            onDateChanged: (value) {
              setState(() => _calendarDate = value);
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '${weekdayShortLabel(selectedWeekday)} tasks '
            '(${formatDurationMinutes(_totalMinutesForDay(generated))}/8h)',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
    ];

    if (generated.isEmpty) {
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No auto tasks for ${weekdayShortLabel(selectedWeekday)}.',
            ),
          ),
        ),
      );
    } else {
      for (final item in generated) {
        children.add(_buildGeneratedTaskCard(item));
        children.add(const SizedBox(height: 8));
      }
    }

    return ListView(padding: appPagePadding, children: children);
  }

  PreferredSizeWidget _buildAppBar() {
    if (_tabIndex == 2) {
      return AppBar(centerTitle: true, title: const Text('Profile'));
    }
    if (_tabIndex == 1) {
      return AppBar(centerTitle: true, title: const Text('Calendar'));
    }
    return AppBar(centerTitle: true, title: _buildTaskBoardSegmentedControl());
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
                  generatedTasks: <GeneratedTaskItem>[],
                  todayTaskActionLogs: <GeneratedTaskActionLog>[],
                );

            if (_tabIndex == 1) {
              return _buildCalendarTab(payload);
            }

            return _buildTaskTab(payload);
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
    required this.generatedTasks,
    required this.todayTaskActionLogs,
  });

  final List<TaskAssignment> tasks;
  final List<GeneratedTaskItem> generatedTasks;
  final List<GeneratedTaskActionLog> todayTaskActionLogs;
}

enum _TaskBoardTab { assessment, tasks }

class _OutcomeButton extends StatelessWidget {
  const _OutcomeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        backgroundColor: selected
            ? const Color(0xFF1C4A2A)
            : const Color(0xFFF5F7F2),
        side: BorderSide(
          color: selected ? const Color(0xFF1C4A2A) : const Color(0xFFC8D5C5),
        ),
        foregroundColor: selected ? Colors.white : const Color(0xFF1D2A1F),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PlannedTaskOccurrence {
  const _PlannedTaskOccurrence({
    required this.item,
    required this.originalWeekday,
    required this.scheduledWeekday,
  });

  final GeneratedTaskItem item;
  final int originalWeekday;
  final int scheduledWeekday;
}
