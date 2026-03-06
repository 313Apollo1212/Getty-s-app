import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

const _estimateMinuteSteps = <int>[
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
  300,
  360,
  420,
  480,
];

int _closestEstimateStepIndex(int minutes) {
  var bestIndex = 0;
  var bestDelta = (minutes - _estimateMinuteSteps.first).abs();
  for (var i = 1; i < _estimateMinuteSteps.length; i++) {
    final delta = (minutes - _estimateMinuteSteps[i]).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

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
  final Map<String, DateTime> _answerEditedAt = {};

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
      final results = await Future.wait<dynamic>([
        widget.service.fetchAssignmentQuestions(widget.assignment.id),
        widget.service.fetchAnswersForAssignment(widget.assignment.id),
      ]);
      final questions = results[0] as List<AssignmentQuestion>;
      final answers = results[1] as Map<String, QuestionAnswer>;

      if (!mounted) {
        return;
      }

      for (final question in questions) {
        final existingAnswer = answers[question.id];
        _controllers.putIfAbsent(
          question.id,
          () => TextEditingController(text: existingAnswer?.answerText ?? ''),
        );
        if (existingAnswer != null) {
          _answerEditedAt[question.id] = existingAnswer.answeredAt;
        }
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
    _answerEditedAt[question.id] = DateTime.now().toUtc();
    setState(() {});
  }

  void _markAnswerEdited(String questionId) {
    _answerEditedAt[questionId] = DateTime.now().toUtc();
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
        answeredAtByQuestion: _answerEditedAt,
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
      body: AppBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
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
                              label: Text(
                                'Status: ${widget.assignment.status.label}',
                              ),
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final question in _questions)
                      _QuestionInputCard(
                        question: question,
                        controller: _controllers[question.id]!,
                        initialAnswer: _answers[question.id],
                        canEdit: _canEdit,
                        onPickTime: () => _pickTime(question),
                        onAnswerChanged: () => _markAnswerEdited(question.id),
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
    required this.onAnswerChanged,
  });

  final AssignmentQuestion question;
  final TextEditingController controller;
  final QuestionAnswer? initialAnswer;
  final bool canEdit;
  final VoidCallback onPickTime;
  final VoidCallback onAnswerChanged;

  @override
  State<_QuestionInputCard> createState() => _QuestionInputCardState();
}

class _QuestionInputCardState extends State<_QuestionInputCard> {
  late String? _dropdownValue;
  bool? _checkValue;
  String? _buttonsValue;
  final Set<int> _yesWeekdays = <int>{};
  double _estimateIndex = 3;
  int _priority = 3;

  int get _estimatedMinutes => _estimateMinuteSteps[_estimateIndex.round()];

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

  String _selectedDaysLabel() {
    if (_yesWeekdays.isEmpty) {
      return 'None selected';
    }
    final sorted = _yesWeekdays.toList()..sort();
    return sorted.map(weekdayShortLabel).join(', ');
  }

  void _syncCheckController() {
    if (_checkValue == true) {
      if (widget.question.requiresYesDetails) {
        final sortedDays = _yesWeekdays.toList()..sort();
        widget.controller.text = CheckAnswerValue(
          isYes: true,
          weekdays: sortedDays,
          estimatedMinutes: _estimatedMinutes,
          priority: _priority,
        ).toStorageText();
      } else {
        widget.controller.text = 'Yes';
      }
    } else if (_checkValue == false) {
      widget.controller.text = 'No';
    } else {
      widget.controller.text = '';
    }
  }

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
      final parsed = CheckAnswerValue.parse(widget.controller.text);
      if (parsed.isYes) {
        _checkValue = true;
      } else {
        final current = widget.controller.text.trim().toLowerCase();
        if (current == 'no') {
          _checkValue = false;
        }
      }
      if (widget.question.requiresYesDetails) {
        _yesWeekdays
          ..clear()
          ..addAll(parsed.weekdays);
        if (parsed.estimatedMinutes != null) {
          _estimateIndex = _closestEstimateStepIndex(
            parsed.estimatedMinutes!,
          ).toDouble();
        }
        final configuredDefault = widget.question.defaultPriority;
        if (configuredDefault != null &&
            configuredDefault >= 1 &&
            configuredDefault <= 5) {
          _priority = configuredDefault;
        }
        if (parsed.priority != null &&
            parsed.priority! >= 1 &&
            parsed.priority! <= 5) {
          _priority = parsed.priority!;
        }
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
            const SizedBox(height: 8),
            switch (widget.question.inputType) {
              QuestionInputType.text => TextFormField(
                controller: widget.controller,
                readOnly: !widget.canEdit,
                decoration: const InputDecoration(),
                onChanged: widget.canEdit
                    ? (_) => widget.onAnswerChanged()
                    : null,
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
                decoration: const InputDecoration(),
                onChanged: widget.canEdit
                    ? (_) => widget.onAnswerChanged()
                    : null,
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
                        widget.onAnswerChanged();
                      },
                decoration: const InputDecoration(),
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
                  if (value &&
                      widget.question.requiresYesDetails &&
                      _yesWeekdays.isEmpty) {
                    return 'Pick at least one weekday for the Yes answer.';
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
                                    _syncCheckController();
                                    state.didChange(true);
                                    widget.onAnswerChanged();
                                  }
                                : null,
                          ),
                          ChoiceChip(
                            label: const Text('No'),
                            selected: _checkValue == false,
                            onSelected: widget.canEdit
                                ? (_) {
                                    setState(() => _checkValue = false);
                                    _syncCheckController();
                                    state.didChange(false);
                                    widget.onAnswerChanged();
                                  }
                                : null,
                          ),
                        ],
                      ),
                      if (_checkValue == true &&
                          widget.question.requiresYesDetails) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Select weekday(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var day = 1; day <= 7; day++)
                              FilterChip(
                                label: Text(weekdayShortLabel(day)),
                                selected: _yesWeekdays.contains(day),
                                onSelected: widget.canEdit
                                    ? (selected) {
                                        setState(() {
                                          if (selected) {
                                            _yesWeekdays.add(day);
                                          } else {
                                            _yesWeekdays.remove(day);
                                          }
                                        });
                                        _syncCheckController();
                                        state.didChange(true);
                                        widget.onAnswerChanged();
                                      }
                                    : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selected: ${_selectedDaysLabel()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_yesWeekdays.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Estimated time: ${formatDurationMinutes(_estimatedMinutes)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Slider(
                            value: _estimateIndex,
                            min: 0,
                            max: (_estimateMinuteSteps.length - 1).toDouble(),
                            divisions: _estimateMinuteSteps.length - 1,
                            label: formatDurationMinutes(_estimatedMinutes),
                            onChanged: widget.canEdit
                                ? (value) {
                                    setState(() => _estimateIndex = value);
                                    _syncCheckController();
                                    widget.onAnswerChanged();
                                  }
                                : null,
                          ),
                          Text(
                            'Priority: $_priority',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var value = 1; value <= 5; value++)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    backgroundColor: _priority == value
                                        ? _priorityColor(value)
                                        : _priorityColor(
                                            value,
                                          ).withValues(alpha: 0.12),
                                    foregroundColor: _priority == value
                                        ? _priorityTextColor(value)
                                        : _priorityColor(value),
                                    side: BorderSide(
                                      color: _priorityColor(value),
                                      width: _priority == value ? 2 : 1,
                                    ),
                                  ),
                                  onPressed: !widget.canEdit
                                      ? null
                                      : () {
                                          setState(() => _priority = value);
                                          _syncCheckController();
                                          widget.onAnswerChanged();
                                        },
                                  child: Text(
                                    '$value',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F8EC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFD6E2C9),
                              ),
                            ),
                            child: const Text(
                              'Priority scale: 1 = highest urgency, 2 = high, 3 = medium, 4 = low, 5 = lowest urgency.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
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
                            color: Theme.of(context).textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.8),
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
                                      widget.onAnswerChanged();
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
