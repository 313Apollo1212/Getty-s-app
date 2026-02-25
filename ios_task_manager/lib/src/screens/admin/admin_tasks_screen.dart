import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
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

  Widget _buildTaskItem(TaskAssignment task) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(task.status.label)),
            ],
          ),
          Text('Expected: ${formatDateTime(task.expectedAt)}'),
          Text(
            task.submittedAt == null
                ? 'Submitted: Not yet'
                : 'Submitted: ${formatDateTime(task.submittedAt!)}',
          ),
          if (task.instructions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(task.instructions),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openEditor(assignment: task),
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openReview(task),
                icon: const Icon(Icons.rate_review),
                label: const Text('Review'),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.red.shade800,
                ),
                onPressed: () => _deleteTask(task),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<TaskAssignment>>(
        future: _assignmentsFuture,
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
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Create Task'),
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
                        ..sort((a, b) => a.expectedAt.compareTo(b.expectedAt));
                      final sample = employeeTasks.first;

                      return ExpansionTile(
                        key: PageStorageKey('employee-${sample.employeeId}'),
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
                          '${sample.employeeName} (@${sample.employeeUsername})',
                        ),
                        subtitle: Text(
                          '${employeeTasks.length} task${employeeTasks.length == 1 ? '' : 's'}',
                        ),
                        children: [
                          for (var i = 0; i < employeeTasks.length; i++) ...[
                            _buildTaskItem(employeeTasks[i]),
                            if (i != employeeTasks.length - 1)
                              const Divider(height: 1),
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
    );
  }
}
