import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

enum _DateWindow { today, last7Days, last30Days, all }

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<_DashboardPayload> _dashboardFuture;

  final TextEditingController _searchController = TextEditingController();

  _DateWindow _dateWindow = _DateWindow.last7Days;
  String? _selectedEmployeeId;
  String? _selectedAssignmentId;
  String _searchQuery = '';
  QuestionInputType? _selectedInputType;
  Set<TaskStatus> _selectedStatuses = Set<TaskStatus>.from(TaskStatus.values);

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_DashboardPayload> _loadDashboard({bool forceRefresh = false}) async {
    final results = await Future.wait<dynamic>([
      widget.service.fetchAllAssignments(forceRefresh: forceRefresh),
      widget.service.fetchDashboardAnswerEntries(forceRefresh: forceRefresh),
      widget.service.fetchFlaggedTaskAlertCount(forceRefresh: forceRefresh),
    ]);

    return _DashboardPayload(
      assignments: results[0] as List<TaskAssignment>,
      answers: results[1] as List<DashboardAnswerEntry>,
      alertCount: results[2] as int,
      loadedAt: DateTime.now(),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _dashboardFuture = _loadDashboard(forceRefresh: true);
    });
  }

  void _toggleStatus(TaskStatus status) {
    setState(() {
      if (_selectedStatuses.contains(status)) {
        if (_selectedStatuses.length == 1) {
          return;
        }
        _selectedStatuses.remove(status);
      } else {
        _selectedStatuses.add(status);
      }
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _dateWindow = _DateWindow.last7Days;
      _selectedEmployeeId = null;
      _selectedAssignmentId = null;
      _searchQuery = '';
      _selectedInputType = null;
      _selectedStatuses = Set<TaskStatus>.from(TaskStatus.values);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  bool _isActionable(TaskAssignment task) {
    return task.status == TaskStatus.pending ||
        task.status == TaskStatus.revisionRequested;
  }

  bool _matchesDateWindow(DateTime value, DateTime now) {
    final localValue = value.toLocal();

    return switch (_dateWindow) {
      _DateWindow.today => _isSameDay(localValue, now),
      _DateWindow.last7Days => !localValue.isBefore(
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
      ),
      _DateWindow.last30Days => !localValue.isBefore(
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29)),
      ),
      _DateWindow.all => true,
    };
  }

  List<DashboardAnswerEntry> _filterAnswers(
    List<DashboardAnswerEntry> answers,
  ) {
    final now = DateTime.now();
    final query = _searchQuery.trim().toLowerCase();

    final filtered = answers.where((entry) {
      if (!_matchesDateWindow(entry.answer.answeredAt, now)) {
        return false;
      }

      if (_selectedEmployeeId != null &&
          entry.assignment.employeeId != _selectedEmployeeId) {
        return false;
      }

      if (_selectedAssignmentId != null &&
          entry.assignment.id != _selectedAssignmentId) {
        return false;
      }

      if (_selectedInputType != null &&
          entry.question.inputType != _selectedInputType) {
        return false;
      }

      if (!_selectedStatuses.contains(entry.assignment.status)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = <String>[
        entry.assignment.title,
        entry.assignment.instructions,
        entry.assignment.employeeName,
        entry.assignment.employeeUsername,
        entry.question.prompt,
        entry.answer.answerText,
      ];
      return searchable.any((value) => value.toLowerCase().contains(query));
    }).toList();

    filtered.sort((a, b) => b.answer.answeredAt.compareTo(a.answer.answeredAt));
    return filtered;
  }

  List<TaskAssignment> _filterAssignments(List<TaskAssignment> assignments) {
    return assignments.where((task) {
      if (_selectedEmployeeId != null &&
          task.employeeId != _selectedEmployeeId) {
        return false;
      }
      if (_selectedAssignmentId != null && task.id != _selectedAssignmentId) {
        return false;
      }
      if (!_selectedStatuses.contains(task.status)) {
        return false;
      }
      return true;
    }).toList();
  }

  _DashboardStats _buildStats({
    required List<TaskAssignment> assignments,
    required List<DashboardAnswerEntry> answers,
    required int alertCount,
  }) {
    final now = DateTime.now().toLocal();
    final yesterday = now.subtract(const Duration(days: 1));
    final employeeIds = <String>{};
    final taskIds = <String>{};

    var responsesToday = 0;
    var responsesYesterday = 0;

    for (final entry in answers) {
      employeeIds.add(entry.assignment.employeeId);
      taskIds.add(entry.assignment.id);
      if (_isSameDay(entry.answer.answeredAt, now)) {
        responsesToday++;
      }
      if (_isSameDay(entry.answer.answeredAt, yesterday)) {
        responsesYesterday++;
      }
    }

    var pending = 0;
    var overdue = 0;
    for (final task in assignments) {
      if (_isActionable(task)) {
        pending++;
      }
      if (_isActionable(task) && task.expectedAt.toLocal().isBefore(now)) {
        overdue++;
      }
    }

    return _DashboardStats(
      totalResponses: answers.length,
      responsesToday: responsesToday,
      responsesYesterday: responsesYesterday,
      employeesResponded: employeeIds.length,
      tasksWithResponses: taskIds.length,
      pendingTasks: pending,
      overdueTasks: overdue,
      alerts: alertCount,
    );
  }

  List<_CountRow> _topAnswers(List<DashboardAnswerEntry> answers) {
    final counts = <String, int>{};
    final labels = <String, String>{};

    for (final entry in answers) {
      final raw = entry.answer.answerText.trim();
      if (raw.isEmpty) {
        continue;
      }
      final key = raw.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      labels.putIfAbsent(key, () => raw);
    }

    final rows =
        counts.entries
            .map(
              (entry) =>
                  _CountRow(label: labels[entry.key]!, count: entry.value),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return rows.take(6).toList();
  }

  List<_CountRow> _typeBreakdown(List<DashboardAnswerEntry> answers) {
    final counts = <QuestionInputType, int>{};

    for (final entry in answers) {
      final type = entry.question.inputType;
      counts[type] = (counts[type] ?? 0) + 1;
    }

    final rows =
        counts.entries
            .map(
              (entry) => _CountRow(label: entry.key.label, count: entry.value),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return rows;
  }

  List<_EmployeeSummaryRow> _employeeBreakdown(
    List<DashboardAnswerEntry> answers,
  ) {
    final byEmployee = <String, _EmployeeSummaryRow>{};

    for (final entry in answers) {
      final id = entry.assignment.employeeId;
      final existing = byEmployee[id];
      if (existing == null) {
        byEmployee[id] = _EmployeeSummaryRow(
          name: entry.assignment.employeeName,
          username: entry.assignment.employeeUsername,
          responseCount: 1,
          latestAnsweredAt: entry.answer.answeredAt,
        );
      } else {
        byEmployee[id] = _EmployeeSummaryRow(
          name: existing.name,
          username: existing.username,
          responseCount: existing.responseCount + 1,
          latestAnsweredAt:
              entry.answer.answeredAt.isAfter(existing.latestAnsweredAt)
              ? entry.answer.answeredAt
              : existing.latestAnsweredAt,
        );
      }
    }

    final rows = byEmployee.values.toList()
      ..sort((a, b) => b.responseCount.compareTo(a.responseCount));

    return rows.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_DashboardPayload>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                children: const [
                  SizedBox(height: 180),
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
                const _DashboardPayload(
                  assignments: <TaskAssignment>[],
                  answers: <DashboardAnswerEntry>[],
                  alertCount: 0,
                  loadedAt: null,
                );

            final assignments = _filterAssignments(payload.assignments);
            final answers = _filterAnswers(payload.answers);
            final stats = _buildStats(
              assignments: assignments,
              answers: answers,
              alertCount: payload.alertCount,
            );

            final employees = <String, _EmployeeOption>{};
            final tasks = <String, _TaskOption>{};
            for (final task in payload.assignments) {
              employees.putIfAbsent(
                task.employeeId,
                () => _EmployeeOption(
                  id: task.employeeId,
                  name: task.employeeName,
                  username: task.employeeUsername,
                ),
              );
              tasks.putIfAbsent(
                task.id,
                () => _TaskOption(
                  id: task.id,
                  title: task.title,
                  employeeId: task.employeeId,
                  employeeName: task.employeeName,
                  expectedAt: task.expectedAt,
                ),
              );
            }

            final employeeOptions = employees.values.toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
            final taskOptions = tasks.values.toList()
              ..sort((a, b) => b.expectedAt.compareTo(a.expectedAt));

            final topAnswers = _topAnswers(answers);
            final typeBreakdown = _typeBreakdown(answers);
            final employeeBreakdown = _employeeBreakdown(answers);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Filters',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (payload.loadedAt != null)
                              Text(
                                'Updated ${DateFormat('h:mm a').format(payload.loadedAt!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: _reload,
                              tooltip: 'Refresh',
                              icon: const Icon(Icons.refresh_rounded, size: 19),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search question, answer, employee, task',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final dateWindow in _DateWindow.values)
                              ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Text(dateWindow.label),
                                selected: _dateWindow == dateWindow,
                                onSelected: (_) {
                                  setState(() => _dateWindow = dateWindow);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final compact = width < 760;
                            final fieldWidth = compact
                                ? width
                                : (width - 16) / 3;

                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SizedBox(
                                  width: fieldWidth,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey<String?>(_selectedEmployeeId),
                                    initialValue: _selectedEmployeeId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Employee',
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('All employees'),
                                      ),
                                      ...employeeOptions.map(
                                        (employee) => DropdownMenuItem<String>(
                                          value: employee.id,
                                          child: Text(
                                            '${employee.name} (@${employee.username})',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedEmployeeId = value;
                                        final selectedTask =
                                            _selectedAssignmentId;
                                        if (selectedTask != null &&
                                            value != null &&
                                            !taskOptions.any(
                                              (task) =>
                                                  task.id == selectedTask &&
                                                  task.employeeId == value,
                                            )) {
                                          _selectedAssignmentId = null;
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey<String?>(
                                      _selectedAssignmentId,
                                    ),
                                    initialValue: _selectedAssignmentId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Task',
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('All tasks'),
                                      ),
                                      ...taskOptions
                                          .where(
                                            (task) =>
                                                _selectedEmployeeId == null ||
                                                task.employeeId ==
                                                    _selectedEmployeeId,
                                          )
                                          .map(
                                            (task) => DropdownMenuItem<String>(
                                              value: task.id,
                                              child: Text(
                                                '${task.title} · ${task.employeeName}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                    ],
                                    onChanged: (value) {
                                      setState(
                                        () => _selectedAssignmentId = value,
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child:
                                      DropdownButtonFormField<
                                        QuestionInputType
                                      >(
                                        initialValue: _selectedInputType,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Answer Type',
                                        ),
                                        items: [
                                          const DropdownMenuItem<
                                            QuestionInputType
                                          >(
                                            value: null,
                                            child: Text('All types'),
                                          ),
                                          ...QuestionInputType.values.map(
                                            (type) =>
                                                DropdownMenuItem<
                                                  QuestionInputType
                                                >(
                                                  value: type,
                                                  child: Text(type.label),
                                                ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setState(
                                            () => _selectedInputType = value,
                                          );
                                        },
                                      ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final status in TaskStatus.values)
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Text(status.label),
                                selected: _selectedStatuses.contains(status),
                                onSelected: (_) => _toggleStatus(status),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${answers.length} responses match filters',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _resetFilters,
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Quick Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryTile(
                      label: 'Responses',
                      value: '${stats.totalResponses}',
                    ),
                    _SummaryTile(
                      label: 'Today',
                      value: '${stats.responsesToday}',
                    ),
                    _SummaryTile(
                      label: 'Yesterday',
                      value: '${stats.responsesYesterday}',
                    ),
                    _SummaryTile(
                      label: 'Employees',
                      value: '${stats.employeesResponded}',
                    ),
                    _SummaryTile(
                      label: 'Tasks Answered',
                      value: '${stats.tasksWithResponses}',
                    ),
                    _SummaryTile(
                      label: 'Need Action',
                      value: '${stats.pendingTasks}',
                    ),
                    _SummaryTile(
                      label: 'Overdue',
                      value: '${stats.overdueTasks}',
                    ),
                    _SummaryTile(label: 'Alerts', value: '${stats.alerts}'),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 840;
                    if (compact) {
                      return Column(
                        children: [
                          _SummaryListCard(
                            title: 'Most Common Answers',
                            rows: topAnswers,
                            emptyLabel: 'No answers for this filter.',
                          ),
                          const SizedBox(height: 8),
                          _SummaryListCard(
                            title: 'Answer Type Breakdown',
                            rows: typeBreakdown,
                            emptyLabel: 'No answer types found.',
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SummaryListCard(
                            title: 'Most Common Answers',
                            rows: topAnswers,
                            emptyLabel: 'No answers for this filter.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SummaryListCard(
                            title: 'Answer Type Breakdown',
                            rows: typeBreakdown,
                            emptyLabel: 'No answer types found.',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee Response Summary',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (employeeBreakdown.isEmpty)
                          const Text(
                            'No employee response data for this filter.',
                          )
                        else
                          for (
                            var index = 0;
                            index < employeeBreakdown.length;
                            index++
                          ) ...[
                            _EmployeeRow(row: employeeBreakdown[index]),
                            if (index != employeeBreakdown.length - 1)
                              const Divider(height: 10),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F8EA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD6E2C9)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF44513A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryListCard extends StatelessWidget {
  const _SummaryListCard({
    required this.title,
    required this.rows,
    required this.emptyLabel,
  });

  final String title;
  final List<_CountRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(emptyLabel)
            else
              for (var i = 0; i < rows.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF5E2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${rows[i].count}',
                        style: const TextStyle(
                          color: Color(0xFF121A0F),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i != rows.length - 1) const Divider(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.row});

  final _EmployeeSummaryRow row;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFFD7EAB8),
          child: Text(
            row.name.isEmpty ? '?' : row.name[0].toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF121A0F),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '@${row.username}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${row.responseCount} responses',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Latest ${formatDateTime(row.latestAnsweredAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardPayload {
  const _DashboardPayload({
    required this.assignments,
    required this.answers,
    required this.alertCount,
    required this.loadedAt,
  });

  final List<TaskAssignment> assignments;
  final List<DashboardAnswerEntry> answers;
  final int alertCount;
  final DateTime? loadedAt;
}

class _DashboardStats {
  const _DashboardStats({
    required this.totalResponses,
    required this.responsesToday,
    required this.responsesYesterday,
    required this.employeesResponded,
    required this.tasksWithResponses,
    required this.pendingTasks,
    required this.overdueTasks,
    required this.alerts,
  });

  final int totalResponses;
  final int responsesToday;
  final int responsesYesterday;
  final int employeesResponded;
  final int tasksWithResponses;
  final int pendingTasks;
  final int overdueTasks;
  final int alerts;
}

class _EmployeeOption {
  const _EmployeeOption({
    required this.id,
    required this.name,
    required this.username,
  });

  final String id;
  final String name;
  final String username;
}

class _TaskOption {
  const _TaskOption({
    required this.id,
    required this.title,
    required this.employeeId,
    required this.employeeName,
    required this.expectedAt,
  });

  final String id;
  final String title;
  final String employeeId;
  final String employeeName;
  final DateTime expectedAt;
}

class _CountRow {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;
}

class _EmployeeSummaryRow {
  const _EmployeeSummaryRow({
    required this.name,
    required this.username,
    required this.responseCount,
    required this.latestAnsweredAt,
  });

  final String name;
  final String username;
  final int responseCount;
  final DateTime latestAnsweredAt;
}

extension on _DateWindow {
  String get label {
    return switch (this) {
      _DateWindow.today => 'Today',
      _DateWindow.last7Days => '7 Days',
      _DateWindow.last30Days => '30 Days',
      _DateWindow.all => 'All',
    };
  }
}
