import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
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
      final questions = await widget.service.fetchAssignmentQuestions(
        widget.assignment.id,
      );
      final answers = await widget.service.fetchAnswersForAdminReview(
        assignmentId: widget.assignment.id,
        employeeId: widget.assignment.employeeId,
      );
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

  Widget _buildAnswerBlock(
    AssignmentQuestion question,
    QuestionAnswer? answer,
  ) {
    if (answer == null || answer.answerText.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Text('No answer submitted yet'),
      );
    }

    final text = answer.answerText.trim();
    final lower = text.toLowerCase();
    final isCheck = question.inputType == QuestionInputType.check;
    final isButtons = question.inputType == QuestionInputType.buttons;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCheck)
            Row(
              children: [
                Icon(
                  lower == 'yes' ? Icons.check_circle : Icons.cancel,
                  color: lower == 'yes' ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else if (isButtons)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const Icon(Icons.smart_button_outlined),
                Chip(
                  label: Text(
                    text,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            SelectableText(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 6),
              Text('Answered at ${formatDateTime(answer.answeredAt)}'),
            ],
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
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
                        const SizedBox(height: 8),
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
                const SizedBox(height: 18),
                Text('Answers', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var index = 0; index < _questions.length; index++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${index + 1}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _questions[index].prompt,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(_questions[index].inputType.label),
                          ),
                          const SizedBox(height: 8),
                          _buildAnswerBlock(
                            _questions[index],
                            _answers[_questions[index].id],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
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
    );
  }
}
