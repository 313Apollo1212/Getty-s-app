import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';
import 'task_editor_screen.dart';

class TaskReviewScreen extends StatefulWidget {
  const TaskReviewScreen({
    super.key,
    required this.service,
    required this.assignment,
  });

  final SupabaseService service;
  final TaskAssignment assignment;

  @override
  State<TaskReviewScreen> createState() => _TaskReviewScreenState();
}

class _TaskReviewScreenState extends State<TaskReviewScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<AssignmentQuestion> _questions = const [];
  Map<String, QuestionAnswer> _answers = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        widget.service.fetchAssignmentQuestions(widget.assignment.id),
        widget.service.fetchAnswersForAdminReview(
          assignmentId: widget.assignment.id,
          employeeId: widget.assignment.employeeId,
        ),
      ]);
      final questions = results[0] as List<AssignmentQuestion>;
      final answers = results[1] as Map<String, QuestionAnswer>;
      if (!mounted) {
        return;
      }
      setState(() {
        _questions = questions;
        _answers = answers;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changeStatus(TaskStatus status) async {
    setState(() => _isSaving = true);
    try {
      await widget.service.updateAssignmentStatus(
        assignmentId: widget.assignment.id,
        status: status,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => _isSaving = false);
    }
  }

  Future<void> _openEditor() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          service: widget.service,
          existingAssignment: widget.assignment,
        ),
      ),
    );

    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildCompactAnswer(
    AssignmentQuestion question,
    QuestionAnswer? answer,
  ) {
    if (answer == null || answer.answerText.trim().isEmpty) {
      return Text(
        'No response',
        style: TextStyle(
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
        ),
      );
    }

    final text = answer.answerText.trim();
    if (question.inputType == QuestionInputType.check) {
      final isYes = text.toLowerCase() == 'yes';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isYes ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: isYes ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
    }

    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildAnswerRow(
    int index,
    AssignmentQuestion question,
    QuestionAnswer? answer,
  ) {
    final background = index.isEven
        ? const Color(0xFFF4F8EC)
        : Colors.transparent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;

        if (compact) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.prompt,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildCompactAnswer(question, answer)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Response Info',
                      onPressed: () => _showAnswerInfo(answer),
                      icon: const Icon(Icons.info_outline, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  question.prompt,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildCompactAnswer(question, answer),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Response Info',
                onPressed: () => _showAnswerInfo(answer),
                icon: const Icon(Icons.info_outline, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAnswerInfo(QuestionAnswer? answer) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Response Info'),
        content: Text(
          answer == null
              ? 'No response has been submitted yet.'
              : 'Answered: ${formatDateTime(answer.answeredAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Review'),
        actions: [
          IconButton(
            onPressed: _openEditor,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Task',
          ),
        ],
      ),
      body: AppBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: appPagePadding,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.assignment.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: const Icon(Icons.person_outline),
                                label: Text(widget.assignment.employeeName),
                              ),
                              Chip(
                                avatar: const Icon(Icons.flag_outlined),
                                label: Text(widget.assignment.status.label),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Expected: ${formatDateTime(widget.assignment.expectedAt)}',
                          ),
                          Text(
                            widget.assignment.submittedAt == null
                                ? 'Submitted: Not yet'
                                : 'Submitted: ${formatDateTime(widget.assignment.submittedAt!)}',
                          ),
                          if (widget.assignment.instructions.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Instructions',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(widget.assignment.instructions),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Answers',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  if (_questions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No questions were configured for this task.',
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < _questions.length;
                              index++
                            ) ...[
                              Builder(
                                builder: (context) {
                                  final question = _questions[index];
                                  final answer = _answers[question.id];
                                  return _buildAnswerRow(
                                    index,
                                    question,
                                    answer,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _isSaving
                            ? null
                            : () => _changeStatus(TaskStatus.revisionRequested),
                        child: const Text('Request Changes'),
                      ),
                      FilledButton(
                        onPressed: _isSaving
                            ? null
                            : () => _changeStatus(TaskStatus.approved),
                        child: const Text('Approve'),
                      ),
                      OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _changeStatus(TaskStatus.pending),
                        child: const Text('Reopen as Pending'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
