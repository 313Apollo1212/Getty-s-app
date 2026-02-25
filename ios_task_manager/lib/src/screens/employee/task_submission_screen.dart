import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../utils/time_format.dart';

class TaskSubmissionScreen extends StatefulWidget {
  const TaskSubmissionScreen({
    super.key,
    required this.service,
    required this.assignment,
  });

  final SupabaseService service;
  final TaskAssignment assignment;

  @override
  State<TaskSubmissionScreen> createState() => _TaskSubmissionScreenState();
}

class _TaskSubmissionScreenState extends State<TaskSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  List<AssignmentQuestion> _questions = const [];
  Map<String, QuestionAnswer> _answers = const {};
  final Map<String, TextEditingController> _controllers = {};

  bool get _canEdit {
    return widget.assignment.status == TaskStatus.pending ||
        widget.assignment.status == TaskStatus.revisionRequested;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final questions = await widget.service.fetchAssignmentQuestions(
        widget.assignment.id,
      );
      final answers = await widget.service.fetchAnswersForAssignment(
        widget.assignment.id,
      );

      if (!mounted) {
        return;
      }

      for (final question in questions) {
        _controllers.putIfAbsent(
          question.id,
          () => TextEditingController(
            text: answers[question.id]?.answerText ?? '',
          ),
        );
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

  Future<void> _pickTime(AssignmentQuestion question) async {
    final initialText = _controllers[question.id]?.text;
    TimeOfDay initial = TimeOfDay.now();

    if (initialText != null && initialText.contains(':')) {
      final parts = initialText.split(':');
      final hour = int.tryParse(parts.first) ?? initial.hour;
      final minute = int.tryParse(parts.last) ?? initial.minute;
      initial = TimeOfDay(hour: hour, minute: minute);
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) {
      return;
    }

    final hour = picked.hour.toString().padLeft(2, '0');
    final minute = picked.minute.toString().padLeft(2, '0');
    _controllers[question.id]?.text = '$hour:$minute';
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_canEdit) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final payload = <String, String>{};
    for (final question in _questions) {
      payload[question.id] = _controllers[question.id]?.text.trim() ?? '';
    }

    setState(() => _isSaving = true);
    try {
      await widget.service.submitAnswers(
        assignmentId: widget.assignment.id,
        answers: payload,
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    widget.assignment.title,
                    style: Theme.of(context).textTheme.headlineSmall,
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
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('Status: ${widget.assignment.status.label}'),
                  ),
                  if (!_canEdit) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'This task is read-only until admin requests changes.',
                    ),
                  ],
                  if (widget.assignment.instructions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(widget.assignment.instructions),
                  ],
                  const SizedBox(height: 16),
                  for (final question in _questions)
                    _QuestionInputCard(
                      question: question,
                      controller: _controllers[question.id]!,
                      initialAnswer: _answers[question.id],
                      canEdit: _canEdit,
                      onPickTime: () => _pickTime(question),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isSaving || !_canEdit ? null : _submit,
                    icon: const Icon(Icons.send),
                    label: Text(
                      _isSaving
                          ? 'Submitting...'
                          : widget.assignment.status ==
                                TaskStatus.revisionRequested
                          ? 'Resubmit'
                          : 'Submit',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _QuestionInputCard extends StatefulWidget {
  const _QuestionInputCard({
    required this.question,
    required this.controller,
    required this.initialAnswer,
    required this.canEdit,
    required this.onPickTime,
  });

  final AssignmentQuestion question;
  final TextEditingController controller;
  final QuestionAnswer? initialAnswer;
  final bool canEdit;
  final VoidCallback onPickTime;

  @override
  State<_QuestionInputCard> createState() => _QuestionInputCardState();
}

class _QuestionInputCardState extends State<_QuestionInputCard> {
  late String? _dropdownValue;
  bool? _checkValue;
  String? _buttonsValue;

  @override
  void initState() {
    super.initState();
    if (widget.question.inputType == QuestionInputType.dropdown) {
      final current = widget.controller.text.trim();
      if (widget.question.dropdownOptions.contains(current)) {
        _dropdownValue = current;
      } else {
        _dropdownValue = null;
      }
    } else if (widget.question.inputType == QuestionInputType.check) {
      final current = widget.controller.text.trim().toLowerCase();
      if (current == 'yes') {
        _checkValue = true;
      } else if (current == 'no') {
        _checkValue = false;
      }
    } else if (widget.question.inputType == QuestionInputType.buttons) {
      final current = widget.controller.text.trim();
      if (widget.question.dropdownOptions.contains(current)) {
        _buttonsValue = current;
      } else {
        _buttonsValue = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.question.prompt,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Type: ${widget.question.inputType.label}'),
            const SizedBox(height: 8),
            switch (widget.question.inputType) {
              QuestionInputType.text => TextFormField(
                controller: widget.controller,
                readOnly: !widget.canEdit,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'This answer is required.';
                  }
                  return null;
                },
              ),
              QuestionInputType.number => TextFormField(
                controller: widget.controller,
                readOnly: !widget.canEdit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'This answer is required.';
                  }
                  if (num.tryParse(value.trim()) == null) {
                    return 'Enter a valid number.';
                  }
                  return null;
                },
              ),
              QuestionInputType.time => TextFormField(
                controller: widget.controller,
                readOnly: true,
                onTap: widget.canEdit ? widget.onPickTime : null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'HH:MM',
                  suffixIcon: Icon(Icons.access_time),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Time is required.';
                  }
                  final parts = value.split(':');
                  if (parts.length != 2) {
                    return 'Use HH:MM format.';
                  }
                  final hour = int.tryParse(parts[0]);
                  final minute = int.tryParse(parts[1]);
                  if (hour == null || minute == null) {
                    return 'Use HH:MM format.';
                  }
                  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
                    return 'Enter a valid time.';
                  }
                  return null;
                },
              ),
              QuestionInputType.dropdown => DropdownButtonFormField<String>(
                initialValue: _dropdownValue,
                hint: const Text('Need to be entered'),
                items: widget.question.dropdownOptions
                    .map(
                      (option) =>
                          DropdownMenuItem(value: option, child: Text(option)),
                    )
                    .toList(),
                onChanged: !widget.canEdit
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _dropdownValue = value);
                        widget.controller.text = value;
                      },
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please select an option.';
                  }
                  return null;
                },
              ),
              QuestionInputType.check => FormField<bool>(
                initialValue: _checkValue,
                validator: (value) {
                  if (value == null) {
                    return 'Please choose Yes or No.';
                  }
                  return null;
                },
                builder: (state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Yes'),
                            selected: _checkValue == true,
                            onSelected: widget.canEdit
                                ? (_) {
                                    setState(() => _checkValue = true);
                                    widget.controller.text = 'Yes';
                                    state.didChange(true);
                                  }
                                : null,
                          ),
                          ChoiceChip(
                            label: const Text('No'),
                            selected: _checkValue == false,
                            onSelected: widget.canEdit
                                ? (_) {
                                    setState(() => _checkValue = false);
                                    widget.controller.text = 'No';
                                    state.didChange(false);
                                  }
                                : null,
                          ),
                        ],
                      ),
                      if (state.hasError) ...[
                        const SizedBox(height: 6),
                        Text(
                          state.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              QuestionInputType.buttons => FormField<String>(
                initialValue: _buttonsValue,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please select a button.';
                  }
                  return null;
                },
                builder: (state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_buttonsValue == null)
                        Text(
                          'Need to be entered',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                          ),
                        ),
                      if (_buttonsValue == null) const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in widget.question.dropdownOptions)
                            ChoiceChip(
                              label: Text(option),
                              selected: _buttonsValue == option,
                              onSelected: widget.canEdit
                                  ? (_) {
                                      setState(() => _buttonsValue = option);
                                      widget.controller.text = option;
                                      state.didChange(option);
                                    }
                                  : null,
                            ),
                        ],
                      ),
                      if (state.hasError) ...[
                        const SizedBox(height: 6),
                        Text(
                          state.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            },
            if (widget.initialAnswer != null) ...[
              const SizedBox(height: 6),
              Text(
                'Previous answer time: ${formatDateTime(widget.initialAnswer!.answeredAt)}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
