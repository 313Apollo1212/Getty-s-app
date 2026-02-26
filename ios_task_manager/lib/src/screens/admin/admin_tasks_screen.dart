import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';
import 'task_editor_screen.dart';
import 'task_review_screen.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  late Future<List<TaskAssignment>> _assignmentsFuture;
  final Set<String> _expandedEmployees = <String>{};

  static const _statusColors = <TaskStatus, Color>{
    TaskStatus.pending: Color(0xFFF0F3F8),
    TaskStatus.submitted: Color(0xFFDCEBFB),
    TaskStatus.revisionRequested: Color(0xFFFFE3E0),
    TaskStatus.approved: Color(0xFFDDF3E5),
  };

  @override
  void initState() {
    super.initState();
    _assignmentsFuture = widget.service.fetchAllAssignments();
  }

  Future<void> _reload() async {
    setState(() {
      _assignmentsFuture = widget.service.fetchAllAssignments();
    });
  }

  Future<void> _openEditor({TaskAssignment? assignment}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          service: widget.service,
          existingAssignment: assignment,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openReview(TaskAssignment assignment) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TaskReviewScreen(service: widget.service, assignment: assignment),
      ),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _deleteTask(TaskAssignment assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text(
          'Delete "${assignment.title}" for ${assignment.employeeName}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.service.deleteAssignment(assignmentId: assignment.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task deleted.')));
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _onTaskMenuSelected(
    _TaskMenuAction action,
    TaskAssignment task,
  ) async {
    switch (action) {
      case _TaskMenuAction.edit:
        await _openEditor(assignment: task);
      case _TaskMenuAction.delete:
        await _deleteTask(task);
    }
  }

  Widget _buildTaskItem(TaskAssignment task) {
    final statusColor = _statusColors[task.status] ?? Colors.grey.shade200;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                _MetaText(
                  icon: Icons.schedule_outlined,
                  text: 'Expected ${formatDateTime(task.expectedAt)}',
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _MetaText(
                        icon: Icons.check_circle_outline,
                        text: task.submittedAt == null
                            ? 'Not submitted'
                            : 'Submitted ${formatDateTime(task.submittedAt!)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _openReview(task),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('View'),
                    ),
                  ],
                ),
                if (task.instructions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    task.instructions,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: statusColor,
                  label: Text(
                    task.status.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C2A38),
                    ),
                  ),
                ),
                PopupMenuButton<_TaskMenuAction>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (action) => _onTaskMenuSelected(action, task),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _TaskMenuAction.edit,
                      child: _MenuItemContent(
                        icon: Icons.edit_outlined,
                        text: 'Edit',
                      ),
                    ),
                    PopupMenuItem(
                      value: _TaskMenuAction.delete,
                      child: _MenuItemContent(
                        icon: Icons.delete_outline,
                        text: 'Delete',
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 8), actions],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 8),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<TaskAssignment>>(
          future: _assignmentsFuture,
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

            final assignments = snapshot.data ?? const [];
            final grouped = <String, List<TaskAssignment>>{};
            for (final task in assignments) {
              grouped
                  .putIfAbsent(task.employeeId, () => <TaskAssignment>[])
                  .add(task);
            }

            final groupedEntries = grouped.entries.toList()
              ..sort(
                (a, b) => a.value.first.employeeName.toLowerCase().compareTo(
                  b.value.first.employeeName.toLowerCase(),
                ),
              );

            return ListView(
              padding: appPagePadding,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.checklist_rtl_rounded,
                                  size: 16,
                                ),
                                label: Text('Tasks ${assignments.length}'),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.people_outline_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  'Employees ${groupedEntries.length}',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add_task),
                          label: const Text('Create Task'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (groupedEntries.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No tasks yet.'),
                    ),
                  ),
                for (final entry in groupedEntries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Builder(
                      builder: (context) {
                        final employeeTasks = entry.value
                          ..sort(
                            (a, b) => a.expectedAt.compareTo(b.expectedAt),
                          );
                        final sample = employeeTasks.first;

                        return ExpansionTile(
                          key: PageStorageKey('employee-${sample.employeeId}'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            6,
                            0,
                            6,
                            8,
                          ),
                          initiallyExpanded: _expandedEmployees.contains(
                            sample.employeeId,
                          ),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedEmployees.add(sample.employeeId);
                              } else {
                                _expandedEmployees.remove(sample.employeeId);
                              }
                            });
                          },
                          title: Text(
                            sample.employeeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            '@${sample.employeeUsername} · ${employeeTasks.length} task${employeeTasks.length == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          children: [
                            for (var i = 0; i < employeeTasks.length; i++) ...[
                              _buildTaskItem(employeeTasks[i]),
                              if (i != employeeTasks.length - 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Divider(height: 1),
                                ),
                            ],
                          ],
                        );
                      },
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

enum _TaskMenuAction { edit, delete }

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _MenuItemContent extends StatelessWidget {
  const _MenuItemContent({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}
