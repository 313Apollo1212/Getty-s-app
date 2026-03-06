import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';
import '../profile_screen.dart';
import 'employee_questions_screen.dart';
import 'task_submission_screen.dart';

const _dailyCapacityMinutes = 8 * 60;
const _extraTimeMinuteSteps = <int>[15, 30, 45, 60, 75, 90, 120, 150, 180, 240];

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _startOfWeek(DateTime value) {
  final date = _dateOnly(value);
  return date.subtract(Duration(days: date.weekday - 1));
}

String _weekdayLongLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'Day',
  };
}

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
  DateTime _weekStart = _startOfWeek(DateTime.now());
  _TaskBoardTab _taskBoardTab = _TaskBoardTab.assessment;
  final Map<String, _TaskActionDraft> _taskActionDrafts = {};
  bool _isSavingGeneratedAction = false;
  bool _isAddingPriorityFiveTasks = false;

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
    final visibleWeekStart = _dateOnly(_weekStart);
    final visibleWeekEnd = visibleWeekStart.add(const Duration(days: 6));
    final results = await Future.wait<dynamic>([
      widget.service.fetchAssignmentsForCurrentEmployee(
        forceRefresh: forceRefresh,
      ),
      widget.service.fetchCurrentEmployeeGeneratedTasks(
        forceRefresh: forceRefresh,
      ),
      widget.service.fetchCurrentEmployeeGeneratedTaskLogs(
        workDate: DateTime.now(),
        forceRefresh: forceRefresh,
      ),
      widget.service.fetchCurrentEmployeeGeneratedTaskLogsRange(
        startDate: visibleWeekStart,
        endDate: visibleWeekEnd,
        forceRefresh: forceRefresh,
      ),
      widget.service.fetchCurrentEmployeeGeneratedTaskReassignmentsForWeek(
        weekStartDate: visibleWeekStart,
        forceRefresh: forceRefresh,
      ),
    ]);

    return _EmployeeTaskPayload(
      tasks: results[0] as List<TaskAssignment>,
      generatedTasks: results[1] as List<GeneratedTaskItem>,
      todayTaskActionLogs: results[2] as List<GeneratedTaskActionLog>,
      visibleWeekTaskActionLogs: results[3] as List<GeneratedTaskActionLog>,
      weekTaskReassignments: results[4] as List<GeneratedTaskReassignment>,
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

  List<TaskAssignment> _buildVisibleAssignmentsByKind(
    _EmployeeTaskPayload payload,
    AssignmentKind kind,
  ) {
    final tasks = payload.tasks
        .where(_isVisibleNow)
        .where((task) => task.kind == kind)
        .toList();
    tasks.sort((a, b) => a.expectedAt.compareTo(b.expectedAt));
    return tasks;
  }

  List<TaskAssignment> _buildAssessments(_EmployeeTaskPayload payload) {
    return _buildVisibleAssignmentsByKind(payload, AssignmentKind.assessment);
  }

  List<TaskAssignment> _buildManualTasks(_EmployeeTaskPayload payload) {
    return _buildVisibleAssignmentsByKind(payload, AssignmentKind.task);
  }

  int _totalMinutesForDay(List<_PlannedTaskOccurrence> items) {
    return items.fold<int>(0, (sum, item) => sum + item.item.estimatedMinutes);
  }

  Color _priorityColor(int value) {
    return switch (value) {
      1 => const Color(0xFFD32F2F),
      2 => const Color(0xFFF57C00),
      3 => const Color(0xFFFBC02D),
      4 => const Color(0xFF7CB342),
      _ => const Color(0xFF2E7D32),
    };
  }

  Color _priorityTextColor(int value) {
    if (value >= 4) {
      return Colors.white;
    }
    if (value == 3) {
      return Colors.black;
    }
    return Colors.white;
  }

  String? _shiftSummary(_PlannedTaskOccurrence entry) {
    final movedFrom = entry.movedFromWeekday;
    if (movedFrom == null && entry.originalWeekday == entry.scheduledWeekday) {
      return null;
    }
    return 'Shifted to ${weekdayShortLabel(entry.scheduledWeekday)} • original ${weekdayShortLabel(entry.originalWeekday)}';
  }

  String _statusLabel(_TaskProgressState state) {
    if (!state.completed || state.latestLog == null) {
      return 'Pending';
    }
    return switch (state.latestLog!.outcome) {
      GeneratedTaskOutcome.done => 'Completed',
      GeneratedTaskOutcome.notDone => 'Not completed',
      GeneratedTaskOutcome.needsMoreTime => 'Needed more time',
    };
  }

  Color? _statusBackgroundColor(_TaskProgressState state) {
    if (!state.completed || state.latestLog == null) {
      return null;
    }
    return switch (state.latestLog!.outcome) {
      GeneratedTaskOutcome.done => const Color(0xFFEAF7EE),
      GeneratedTaskOutcome.notDone => const Color(0xFFFDECEC),
      GeneratedTaskOutcome.needsMoreTime => const Color(0xFFFFF3E0),
    };
  }

  Color? _statusBorderColor(_TaskProgressState state) {
    if (!state.completed || state.latestLog == null) {
      return null;
    }
    return switch (state.latestLog!.outcome) {
      GeneratedTaskOutcome.done => const Color(0xFF62B77A),
      GeneratedTaskOutcome.notDone => const Color(0xFFE57373),
      GeneratedTaskOutcome.needsMoreTime => const Color(0xFFFFB74D),
    };
  }

  Color _statusChipColor(_TaskProgressState state) {
    if (!state.completed || state.latestLog == null) {
      return const Color(0xFFE8EFE8);
    }
    return switch (state.latestLog!.outcome) {
      GeneratedTaskOutcome.done => const Color(0xFFD6F0DC),
      GeneratedTaskOutcome.notDone => const Color(0xFFF8D7DA),
      GeneratedTaskOutcome.needsMoreTime => const Color(0xFFFFE0B2),
    };
  }

  Map<int, List<_PlannedTaskOccurrence>> _buildBalancedWeekSchedule(
    List<GeneratedTaskItem> sourceItems,
  ) {
    final schedule = <int, List<_PlannedTaskOccurrence>>{
      for (var day = 1; day <= 7; day++) day: <_PlannedTaskOccurrence>[],
    };

    for (final item in sourceItems) {
      final uniqueDays = item.weekdays.toSet().where(
        (day) => day >= 1 && day <= 7,
      );
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
      final orderedToMove = [...current]
        ..sort((a, b) {
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

  Map<int, List<_PlannedTaskOccurrence>> _applyWeekReassignments(
    Map<int, List<_PlannedTaskOccurrence>> baseSchedule,
    List<GeneratedTaskReassignment> reassignments,
  ) {
    final adjusted = <int, List<_PlannedTaskOccurrence>>{
      for (var day = 1; day <= 7; day++)
        day: [...baseSchedule[day] ?? const []],
    };

    for (final reassignment in reassignments) {
      if (reassignment.fromScheduledWeekday < 1 ||
          reassignment.fromScheduledWeekday > 7 ||
          reassignment.targetWeekday < 1 ||
          reassignment.targetWeekday > 7) {
        continue;
      }

      final sourceList = adjusted[reassignment.fromScheduledWeekday]!;
      final matchIndex = sourceList.indexWhere((entry) {
        return entry.item.categoryTitle.trim().toLowerCase() ==
                reassignment.categoryTitle.trim().toLowerCase() &&
            entry.item.prompt.trim().toLowerCase() ==
                reassignment.prompt.trim().toLowerCase() &&
            entry.originalWeekday == reassignment.originalWeekday &&
            entry.item.priority == reassignment.priority &&
            entry.item.estimatedMinutes == reassignment.estimatedMinutes;
      });
      if (matchIndex >= 0) {
        final moved = sourceList.removeAt(matchIndex);
        adjusted[reassignment.targetWeekday]!.add(
          _PlannedTaskOccurrence(
            item: moved.item,
            originalWeekday: moved.originalWeekday,
            scheduledWeekday: reassignment.targetWeekday,
            movedFromWeekday: reassignment.fromScheduledWeekday,
          ),
        );
      } else {
        adjusted[reassignment.targetWeekday]!.add(
          _PlannedTaskOccurrence(
            item: GeneratedTaskItem(
              categoryTitle: reassignment.categoryTitle,
              prompt: reassignment.prompt,
              weekdays: <int>[reassignment.targetWeekday],
              estimatedMinutes: reassignment.estimatedMinutes,
              priority: reassignment.priority,
              answeredAt: reassignment.createdAt,
            ),
            originalWeekday: reassignment.originalWeekday,
            scheduledWeekday: reassignment.targetWeekday,
            movedFromWeekday: reassignment.fromScheduledWeekday,
          ),
        );
      }
    }

    for (var day = 1; day <= 7; day++) {
      adjusted[day]!.sort((a, b) {
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

    return adjusted;
  }

  Future<DateTime> _findNextAvailableDateForExtraWork(
    _EmployeeTaskPayload payload, {
    required int extraMinutes,
  }) async {
    final today = _dateOnly(DateTime.now());
    final weekCache = <String, List<GeneratedTaskReassignment>>{};
    final base = _buildBalancedWeekSchedule(payload.generatedTasks);
    final currentWeekStart = _startOfWeek(today);
    final currentWeekKey = _dateOnly(currentWeekStart).toIso8601String();
    weekCache[currentWeekKey] = payload.weekTaskReassignments;

    for (var dayOffset = 1; dayOffset <= 56; dayOffset++) {
      final candidateDate = today.add(Duration(days: dayOffset));
      final candidateWeekStart = _startOfWeek(candidateDate);
      final candidateWeekKey = _dateOnly(candidateWeekStart).toIso8601String();
      final reassignments =
          weekCache[candidateWeekKey] ??
          await widget.service
              .fetchCurrentEmployeeGeneratedTaskReassignmentsForWeek(
                weekStartDate: candidateWeekStart,
              );
      weekCache[candidateWeekKey] = reassignments;

      final schedule = _applyWeekReassignments(base, reassignments);
      final dayItems =
          schedule[candidateDate.weekday] ?? const <_PlannedTaskOccurrence>[];
      final dayTotal = _totalMinutesForDay(dayItems);
      if (dayTotal + extraMinutes <= _dailyCapacityMinutes) {
        return candidateDate;
      }
    }

    return today.add(const Duration(days: 1));
  }

  String _buildExtraTimePrompt(String prompt) {
    const suffix = ' (Extra time)';
    if (prompt.endsWith(suffix)) {
      return prompt;
    }
    return '$prompt$suffix';
  }

  Future<void> _addPriorityFiveTasksFromFuture(
    _EmployeeTaskPayload payload,
  ) async {
    if (_isAddingPriorityFiveTasks || _isSavingGeneratedAction) {
      return;
    }

    final todayWeekday = DateTime.now().weekday;
    if (todayWeekday >= DateTime.sunday) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No future weekdays left in this week.')),
      );
      return;
    }

    setState(() => _isAddingPriorityFiveTasks = true);
    try {
      final balanced = _buildBalancedWeekSchedule(payload.generatedTasks);
      final schedule = _applyWeekReassignments(
        balanced,
        payload.weekTaskReassignments,
      );
      final weekStart = _startOfWeek(DateTime.now());
      GeneratedTaskReassignmentDraft? selected;
      for (var day = todayWeekday + 1; day <= DateTime.sunday; day++) {
        final dayEntries = schedule[day] ?? const <_PlannedTaskOccurrence>[];
        final dayDate = weekStart.add(Duration(days: day - 1));
        final dayLogs = _logsForDate(
          payload.visibleWeekTaskActionLogs,
          dayDate,
        );
        final dayStates = _buildTaskProgressStates(dayEntries, dayLogs);
        for (final state in dayStates) {
          final entry = state.entry;
          if (state.completed || entry.item.priority != 5) {
            continue;
          }
          selected = GeneratedTaskReassignmentDraft(
            categoryTitle: entry.item.categoryTitle,
            prompt: entry.item.prompt,
            originalWeekday: entry.originalWeekday,
            fromScheduledWeekday: day,
            targetWeekday: todayWeekday,
            priority: entry.item.priority,
            estimatedMinutes: entry.item.estimatedMinutes,
          );
          break;
        }
        if (selected != null) {
          break;
        }
      }

      if (selected == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pending Priority 5 tasks found in upcoming days.',
            ),
          ),
        );
        return;
      }

      await widget.service.saveGeneratedTaskReassignments(
        weekStartDate: weekStart,
        reassignments: <GeneratedTaskReassignmentDraft>[selected],
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Moved 1 Priority 5 task to today.')),
      );
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
        setState(() => _isAddingPriorityFiveTasks = false);
      }
    }
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

  Widget _buildManualTaskCard(TaskAssignment task) {
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

  List<_TaskProgressState> _buildTaskProgressStates(
    List<_PlannedTaskOccurrence> source,
    List<GeneratedTaskActionLog> logs,
  ) {
    final logsByKey = <String, List<GeneratedTaskActionLog>>{};
    for (final log in logs) {
      final key =
          '${log.categoryTitle.trim().toLowerCase()}|'
          '${log.prompt.trim().toLowerCase()}|'
          '${log.originalWeekday}|${log.scheduledWeekday}|'
          '${log.priority}|${log.estimatedMinutes}';
      logsByKey.putIfAbsent(key, () => <GeneratedTaskActionLog>[]).add(log);
    }

    final result = <_TaskProgressState>[];
    for (final entry in source) {
      final key = _occurrenceKey(entry);
      final matching = logsByKey[key];
      final completed = matching != null && matching.isNotEmpty;
      final log = completed ? matching.removeAt(0) : null;
      result.add(
        _TaskProgressState(
          key: key,
          entry: entry,
          completed: completed,
          latestLog: log,
        ),
      );
    }
    return result;
  }

  List<GeneratedTaskActionLog> _logsForDate(
    List<GeneratedTaskActionLog> logs,
    DateTime date,
  ) {
    final dateOnly = _dateOnly(date);
    return logs.where((log) => _dateOnly(log.workDate) == dateOnly).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
  }

  void _toggleOutcomeSelection(String key, GeneratedTaskOutcome outcome) {
    setState(() {
      final current = _taskActionDrafts[key];
      if (current != null && current.outcome == outcome) {
        _taskActionDrafts.remove(key);
        return;
      }
      _taskActionDrafts[key] = _TaskActionDraft(
        outcome: outcome,
        extraIndex: current?.extraIndex ?? 0,
      );
    });
  }

  void _updateExtraIndex(String key, double value) {
    setState(() {
      final current = _taskActionDrafts[key];
      if (current == null) {
        _taskActionDrafts[key] = _TaskActionDraft(
          outcome: GeneratedTaskOutcome.needsMoreTime,
          extraIndex: value,
        );
      } else {
        _taskActionDrafts[key] = _TaskActionDraft(
          outcome: current.outcome,
          extraIndex: value,
        );
      }
    });
  }

  Future<void> _submitGeneratedTask(
    _PlannedTaskOccurrence entry,
    _TaskActionDraft draft,
    _EmployeeTaskPayload payload,
  ) async {
    if (_isSavingGeneratedAction || draft.outcome == null) {
      return;
    }

    final extraMinutes = draft.outcome == GeneratedTaskOutcome.needsMoreTime
        ? _extraTimeMinuteSteps[draft.extraIndex.round()]
        : null;

    setState(() => _isSavingGeneratedAction = true);
    try {
      await widget.service.saveGeneratedTaskAction(
        categoryTitle: entry.item.categoryTitle,
        prompt: entry.item.prompt,
        scheduledWeekday: entry.scheduledWeekday,
        originalWeekday: entry.originalWeekday,
        priority: entry.item.priority,
        estimatedMinutes: entry.item.estimatedMinutes,
        outcome: draft.outcome!,
        extraMinutes: extraMinutes,
        workDate: DateTime.now(),
      );

      if (draft.outcome == GeneratedTaskOutcome.needsMoreTime &&
          extraMinutes != null &&
          extraMinutes > 0) {
        final targetDate = await _findNextAvailableDateForExtraWork(
          payload,
          extraMinutes: extraMinutes,
        );
        await widget.service.saveGeneratedTaskReassignments(
          weekStartDate: _startOfWeek(targetDate),
          reassignments: <GeneratedTaskReassignmentDraft>[
            GeneratedTaskReassignmentDraft(
              categoryTitle: entry.item.categoryTitle,
              prompt: _buildExtraTimePrompt(entry.item.prompt),
              originalWeekday: entry.originalWeekday,
              fromScheduledWeekday: entry.scheduledWeekday,
              targetWeekday: targetDate.weekday,
              priority: entry.item.priority,
              estimatedMinutes: extraMinutes,
            ),
          ],
        );
      }

      if (!mounted) {
        return;
      }

      _taskActionDrafts.remove(_occurrenceKey(entry));
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

  Widget _buildPriorityBadge(int priority) {
    final bg = _priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Priority $priority',
        style: TextStyle(
          color: _priorityTextColor(priority),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCalendarTaskCard(_TaskProgressState state) {
    final entry = state.entry;
    final item = entry.item;
    final shiftSummary = _shiftSummary(entry);
    final bgColor = _statusBackgroundColor(state);
    final borderColor = _statusBorderColor(state);
    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.categoryTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildPriorityBadge(item.priority),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              shiftSummary == null
                  ? 'Estimated: ${formatDurationMinutes(item.estimatedMinutes)}'
                  : 'Estimated: ${formatDurationMinutes(item.estimatedMinutes)} • $shiftSummary',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusChipColor(state),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(state),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (state.completed) ...[
                  const SizedBox(width: 8),
                  Text(
                    formatDateTime(
                      state.latestLog?.submittedAt ?? DateTime.now(),
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksExecutionCard(
    _TaskProgressState state,
    _EmployeeTaskPayload payload,
  ) {
    final entry = state.entry;
    final item = entry.item;
    final draft = _taskActionDrafts[state.key];
    final selectedOutcome = draft?.outcome;
    final shiftSummary = _shiftSummary(entry);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.categoryTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildPriorityBadge(item.priority),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.prompt,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              shiftSummary == null
                  ? 'Estimated: ${formatDurationMinutes(item.estimatedMinutes)}'
                  : 'Estimated: ${formatDurationMinutes(item.estimatedMinutes)} • $shiftSummary',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OutcomeButton(
                    label: 'Completed',
                    selected: selectedOutcome == GeneratedTaskOutcome.done,
                    onPressed: () {
                      _toggleOutcomeSelection(
                        state.key,
                        GeneratedTaskOutcome.done,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OutcomeButton(
                    label: 'Not Completed',
                    selected: selectedOutcome == GeneratedTaskOutcome.notDone,
                    onPressed: () {
                      _toggleOutcomeSelection(
                        state.key,
                        GeneratedTaskOutcome.notDone,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OutcomeButton(
                    label: 'Needs More Time',
                    selected:
                        selectedOutcome == GeneratedTaskOutcome.needsMoreTime,
                    onPressed: () {
                      _toggleOutcomeSelection(
                        state.key,
                        GeneratedTaskOutcome.needsMoreTime,
                      );
                    },
                  ),
                ),
              ],
            ),
            if (selectedOutcome == GeneratedTaskOutcome.needsMoreTime) ...[
              const SizedBox(height: 10),
              Text(
                'More time needed: ${formatDurationMinutes(_extraTimeMinuteSteps[draft?.extraIndex.round() ?? 0])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: draft?.extraIndex ?? 0,
                min: 0,
                max: (_extraTimeMinuteSteps.length - 1).toDouble(),
                divisions: _extraTimeMinuteSteps.length - 1,
                label: formatDurationMinutes(
                  _extraTimeMinuteSteps[draft?.extraIndex.round() ?? 0],
                ),
                onChanged: (value) => _updateExtraIndex(state.key, value),
              ),
            ],
            if (selectedOutcome != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
                onPressed: _isSavingGeneratedAction
                    ? null
                    : () => _submitGeneratedTask(entry, draft!, payload),
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
          label: Text('Weekly Assessment'),
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
    final manualTasks = _buildManualTasks(payload);
    final weekday = DateTime.now().weekday;
    final weekdayLabel = _weekdayLongLabel(weekday);
    final balanced = _buildBalancedWeekSchedule(payload.generatedTasks);
    final schedule = _applyWeekReassignments(
      balanced,
      payload.weekTaskReassignments,
    );
    final generated = schedule[weekday] ?? const <_PlannedTaskOccurrence>[];
    final progressStates = _buildTaskProgressStates(
      generated,
      payload.todayTaskActionLogs,
    );
    final pendingStates = progressStates
        .where((state) => !state.completed)
        .toList();
    final isAssessment = _taskBoardTab == _TaskBoardTab.assessment;
    final completedCount = progressStates
        .where((state) => state.completed)
        .length;
    final percentCompleted = progressStates.isEmpty
        ? 0
        : ((completedCount / progressStates.length) * 100).round();
    final totalMinutes = _totalMinutesForDay(generated);

    final children = <Widget>[
      Text(
        isAssessment
            ? 'Weekly assessment forms'
            : '$weekdayLabel • ${formatDurationMinutes(totalMinutes)} total',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (!isAssessment) ...[
        const SizedBox(height: 4),
        Text(
          '$percentCompleted% completed ($completedCount/${progressStates.length})',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _isAddingPriorityFiveTasks
              ? null
              : () => _addPriorityFiveTasksFromFuture(payload),
          icon: _isAddingPriorityFiveTasks
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(
            _isAddingPriorityFiveTasks ? 'Adding...' : 'Add Priority 5 task',
          ),
        ),
      ],
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
      if (manualTasks.isNotEmpty) {
        children.add(
          Text(
            'Assigned tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
        children.add(const SizedBox(height: 8));
        for (final task in manualTasks) {
          children.add(_buildManualTaskCard(task));
          children.add(const SizedBox(height: 10));
        }
      }

      if (pendingStates.isNotEmpty) {
        children.add(
          Text(
            'Auto tasks from assessments',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
        children.add(const SizedBox(height: 8));
      }

      if (manualTasks.isEmpty && pendingStates.isEmpty) {
        children.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No tasks available right now.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        );
      } else if (pendingStates.isNotEmpty) {
        for (final state in pendingStates) {
          children.add(_buildTasksExecutionCard(state, payload));
          children.add(const SizedBox(height: 10));
        }
      }
    }

    return ListView(padding: appPagePadding, children: children);
  }

  Widget _buildCalendarTab(_EmployeeTaskPayload payload) {
    final selectedDate = _dateOnly(_calendarDate);
    final weekDates = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    final selectedWeekday = selectedDate.weekday;
    final balanced = _buildBalancedWeekSchedule(payload.generatedTasks);
    final schedule = _applyWeekReassignments(
      balanced,
      payload.weekTaskReassignments,
    );
    final generated =
        schedule[selectedWeekday] ?? const <_PlannedTaskOccurrence>[];
    final selectedDayLogs = _logsForDate(
      payload.visibleWeekTaskActionLogs,
      selectedDate,
    );
    final calendarStates = _buildTaskProgressStates(generated, selectedDayLogs);

    var weekTotalMinutes = 0;
    var weekDoneMinutes = 0;
    for (final date in weekDates) {
      final dayItems =
          schedule[date.weekday] ?? const <_PlannedTaskOccurrence>[];
      final dayLogs = _logsForDate(payload.visibleWeekTaskActionLogs, date);
      final dayStates = _buildTaskProgressStates(dayItems, dayLogs);
      weekTotalMinutes += _totalMinutesForDay(dayItems);
      weekDoneMinutes += dayStates
          .where((state) => state.completed)
          .fold<int>(
            0,
            (sum, state) => sum + state.entry.item.estimatedMinutes,
          );
    }

    final children = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _weekStart = _weekStart.subtract(
                          const Duration(days: 7),
                        );
                        _calendarDate = _weekStart;
                        _tasksFuture = _loadTasks(forceRefresh: true);
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_weekStart.month}/${_weekStart.day} - ${_weekStart.add(const Duration(days: 6)).month}/${_weekStart.add(const Duration(days: 6)).day}',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _weekStart = _weekStart.add(const Duration(days: 7));
                        _calendarDate = _weekStart;
                        _tasksFuture = _loadTasks(forceRefresh: true);
                      });
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final date in weekDates)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _WeekDayTile(
                          date: date,
                          selected: date == selectedDate,
                          totalMinutes: _totalMinutesForDay(
                            schedule[date.weekday] ??
                                const <_PlannedTaskOccurrence>[],
                          ),
                          onTap: () {
                            setState(() => _calendarDate = date);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '${_weekdayLongLabel(selectedWeekday)} • ${formatDurationMinutes(_totalMinutesForDay(generated))} total',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      Text(
        'Week total: ${formatDurationMinutes(weekTotalMinutes)} • Done: ${formatDurationMinutes(weekDoneMinutes)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
    ];

    if (calendarStates.isEmpty) {
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
      for (final state in calendarStates) {
        children.add(_buildCalendarTaskCard(state));
        children.add(const SizedBox(height: 8));
      }
    }

    return ListView(padding: appPagePadding, children: children);
  }

  PreferredSizeWidget _buildAppBar() {
    if (_tabIndex == 3) {
      return AppBar(centerTitle: true, title: const Text('Profile'));
    }
    if (_tabIndex == 2) {
      return AppBar(centerTitle: true, title: const Text('Questions'));
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
                  visibleWeekTaskActionLogs: <GeneratedTaskActionLog>[],
                  weekTaskReassignments: <GeneratedTaskReassignment>[],
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
      body: _tabIndex == 3
          ? ProfileScreen(
              service: widget.service,
              currentUser: widget.currentUser,
            )
          : _tabIndex == 2
          ? EmployeeQuestionsScreen(service: widget.service)
          : _buildTasksAndCalendarTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) {
          setState(() {
            _tabIndex = value;
            if (value == 0) {
              _weekStart = _startOfWeek(DateTime.now());
              _calendarDate = DateTime.now();
              _tasksFuture = _loadTasks(forceRefresh: true);
            }
          });
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
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Questions',
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
    required this.visibleWeekTaskActionLogs,
    required this.weekTaskReassignments,
  });

  final List<TaskAssignment> tasks;
  final List<GeneratedTaskItem> generatedTasks;
  final List<GeneratedTaskActionLog> todayTaskActionLogs;
  final List<GeneratedTaskActionLog> visibleWeekTaskActionLogs;
  final List<GeneratedTaskReassignment> weekTaskReassignments;
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
    this.movedFromWeekday,
  });

  final GeneratedTaskItem item;
  final int originalWeekday;
  final int scheduledWeekday;
  final int? movedFromWeekday;
}

class _TaskProgressState {
  const _TaskProgressState({
    required this.key,
    required this.entry,
    required this.completed,
    this.latestLog,
  });

  final String key;
  final _PlannedTaskOccurrence entry;
  final bool completed;
  final GeneratedTaskActionLog? latestLog;
}

class _TaskActionDraft {
  const _TaskActionDraft({required this.outcome, required this.extraIndex});

  final GeneratedTaskOutcome? outcome;
  final double extraIndex;
}

class _WeekDayTile extends StatelessWidget {
  const _WeekDayTile({
    required this.date,
    required this.selected,
    required this.totalMinutes,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final int totalMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF1C4A2A) : const Color(0xFFF1F5EE);
    final fg = selected ? Colors.white : const Color(0xFF203025);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC6D5C3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              weekdayShortLabel(date.weekday),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            Text(
              '${date.day}',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            Text(
              formatDurationMinutes(totalMinutes),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
