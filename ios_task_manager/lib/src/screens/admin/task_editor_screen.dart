import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

enum _ScheduleMode { oneTime, weekdays }

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.service,
    this.existingAssignment,
  });

  final SupabaseService service;
  final TaskAssignment? existingAssignment;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();

  DateTime _showAt = DateTime.now();
  DateTime _expectedAt = DateTime.now().add(const Duration(hours: 1));
  String? _selectedEmployeeId;
  bool _isLoading = false;
  bool _isLoadingQuestions = false;

  _ScheduleMode _scheduleMode = _ScheduleMode.oneTime;
  DateTime _repeatStartDate = DateUtils.dateOnly(DateTime.now());
  DateTime _repeatEndDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 14)),
  );
  TimeOfDay _repeatShowTime = TimeOfDay.now();
  TimeOfDay _repeatExpectedTime = TimeOfDay.now();
  final Set<int> _selectedWeekdays = {DateTime.now().weekday};

  late Future<List<Profile>> _employeesFuture;
  final List<_QuestionDraftForm> _questions = [];

  bool get _isEdit => widget.existingAssignment != null;

  @override
  void initState() {
    super.initState();
    _employeesFuture = widget.service.fetchEmployeesOnly();

    final existing = widget.existingAssignment;
    if (existing != null) {
      _titleController.text = existing.title;
      _instructionsController.text = existing.instructions;
      _showAt = existing.showAt;
      _expectedAt = existing.expectedAt;
      _selectedEmployeeId = existing.employeeId;
      _repeatShowTime = TimeOfDay.fromDateTime(existing.showAt);
      _repeatExpectedTime = TimeOfDay.fromDateTime(existing.expectedAt);
      _loadExistingQuestions(existing.id);
    } else {
      _questions.add(_QuestionDraftForm());
      _repeatShowTime = TimeOfDay.fromDateTime(_showAt);
      _repeatExpectedTime = TimeOfDay.fromDateTime(_expectedAt);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingQuestions(String assignmentId) async {
    setState(() => _isLoadingQuestions = true);
    try {
      final rows = await widget.service.fetchAssignmentQuestions(assignmentId);
      _questions.clear();
      for (final row in rows) {
        _questions.add(
          _QuestionDraftForm(
            prompt: row.prompt,
            type: row.inputType,
            options: row.dropdownOptions.join(', '),
            unwantedAnswer: row.unwantedAnswer ?? '',
          ),
        );
      }
      if (_questions.isEmpty) {
        _questions.add(_QuestionDraftForm());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      if (_questions.isEmpty) {
        _questions.add(_QuestionDraftForm());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingQuestions = false);
      }
    }
  }

  Future<void> _pickShowDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _showAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 730)),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_showAt),
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _showAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickExpectedDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _expectedAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 730)),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedAt),
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _expectedAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickRepeatStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _repeatStartDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _repeatStartDate = DateUtils.dateOnly(pickedDate);
      if (_repeatEndDate.isBefore(_repeatStartDate)) {
        _repeatEndDate = _repeatStartDate;
      }
    });
  }

  Future<void> _pickRepeatEndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _repeatEndDate,
      firstDate: _repeatStartDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _repeatEndDate = DateUtils.dateOnly(pickedDate);
    });
  }

  Future<void> _pickRepeatTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _repeatShowTime,
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _repeatShowTime = pickedTime;
    });
  }

  Future<void> _pickRepeatExpectedTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _repeatExpectedTime,
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _repeatExpectedTime = pickedTime;
    });
  }

  void _addQuestion() {
    setState(() {
      _questions.add(_QuestionDraftForm());
    });
  }

  void _removeQuestion(int index) {
    if (_questions.length == 1) {
      return;
    }
    setState(() {
      final item = _questions.removeAt(index);
      item.dispose();
    });
  }

  List<_ScheduledDatePair> _buildRecurringSchedule() {
    final start = DateUtils.dateOnly(_repeatStartDate);
    final end = DateUtils.dateOnly(_repeatEndDate);

    final schedule = <_ScheduledDatePair>[];
    for (
      DateTime date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      if (_selectedWeekdays.contains(date.weekday)) {
        schedule.add(
          _ScheduledDatePair(
            showAt: DateTime(
              date.year,
              date.month,
              date.day,
              _repeatShowTime.hour,
              _repeatShowTime.minute,
            ),
            expectedAt: DateTime(
              date.year,
              date.month,
              date.day,
              _repeatExpectedTime.hour,
              _repeatExpectedTime.minute,
            ),
          ),
        );
      }
    }

    return schedule;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an employee.')),
      );
      return;
    }

    final draftQuestions = <TaskDraftQuestion>[];
    for (final question in _questions) {
      final prompt = question.promptController.text.trim();
      if (prompt.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Every question must have a prompt.')),
        );
        return;
      }

      final options = question.optionsController.text
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();

      if (question.type == QuestionInputType.dropdown && options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dropdown questions need at least one option.'),
          ),
        );
        return;
      }

      if (question.type == QuestionInputType.buttons && options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buttons questions need at least two buttons.'),
          ),
        );
        return;
      }

      final unwantedAnswer = question.unwantedAnswerController.text.trim();
      if (question.notifyOnUnwantedAnswer && unwantedAnswer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter the unwanted answer or turn off notifications for that question.',
            ),
          ),
        );
        return;
      }

      draftQuestions.add(
        TaskDraftQuestion(
          prompt: prompt,
          inputType: question.type,
          dropdownOptions: options,
          unwantedAnswer: question.notifyOnUnwantedAnswer
              ? unwantedAnswer
              : null,
        ),
      );
    }

    if (!_isEdit && _scheduleMode == _ScheduleMode.weekdays) {
      if (_selectedWeekdays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pick at least one weekday for recurring schedule.'),
          ),
        );
        return;
      }
      if (_repeatEndDate.isBefore(_repeatStartDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('End date must be on or after start date.'),
          ),
        );
        return;
      }

      if (_repeatShowTime.hour > _repeatExpectedTime.hour ||
          (_repeatShowTime.hour == _repeatExpectedTime.hour &&
              _repeatShowTime.minute > _repeatExpectedTime.minute)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Show time must be before or equal to expected answer time.',
            ),
          ),
        );
        return;
      }
    }

    if (_showAt.isAfter(_expectedAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Show time must be before or equal to expected answer time.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      var createdCount = 0;

      if (_isEdit || _scheduleMode == _ScheduleMode.oneTime) {
        await widget.service.saveAssignment(
          draft: TaskAssignmentDraft(
            employeeId: _selectedEmployeeId!,
            title: _titleController.text,
            instructions: _instructionsController.text,
            showAt: _showAt,
            expectedAt: _expectedAt,
            questions: draftQuestions,
          ),
          assignmentId: widget.existingAssignment?.id,
        );
        createdCount = 1;
      } else {
        final schedule = _buildRecurringSchedule();
        if (schedule.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This schedule creates zero tasks. Adjust weekdays/date range.',
              ),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }

        if (schedule.length > 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Too many tasks at once (max 500). Reduce the date range.',
              ),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }

        for (final item in schedule) {
          if (item.showAt.isAfter(item.expectedAt)) {
            continue;
          }
          await widget.service.saveAssignment(
            draft: TaskAssignmentDraft(
              employeeId: _selectedEmployeeId!,
              title: _titleController.text,
              instructions: _instructionsController.text,
              showAt: item.showAt,
              expectedAt: item.expectedAt,
              questions: draftQuestions,
            ),
          );
        }
        createdCount = schedule.length;
      }

      if (!mounted) {
        return;
      }

      if (!_isEdit && _scheduleMode == _ScheduleMode.weekdays) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Created $createdCount tasks.')));
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
        setState(() => _isLoading = false);
      }
    }
  }

  String _weekdayShortLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Mon',
      DateTime.tuesday => 'Tue',
      DateTime.wednesday => 'Wed',
      DateTime.thursday => 'Thu',
      DateTime.friday => 'Fri',
      DateTime.saturday => 'Sat',
      DateTime.sunday => 'Sun',
      _ => 'Day',
    };
  }

  String _formatDateOnly(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final recurringCount = _buildRecurringSchedule().length;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Task' : 'Create Task')),
      body: AppBackground(
        child: _isLoadingQuestions
            ? const Center(child: CircularProgressIndicator())
            : FutureBuilder<List<Profile>>(
                future: _employeesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }

                  final employees = snapshot.data ?? const [];

                  return Form(
                    key: _formKey,
                    child: ListView(
                      padding: appPagePadding,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedEmployeeId,
                                  decoration: const InputDecoration(
                                    labelText: 'Employee',
                                  ),
                                  items: employees
                                      .map(
                                        (employee) => DropdownMenuItem(
                                          value: employee.id,
                                          child: Text(
                                            '${employee.fullName} (@${employee.username})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedEmployeeId = value);
                                  },
                                  validator: (value) => value == null
                                      ? 'Employee is required.'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _titleController,
                                  decoration: const InputDecoration(
                                    labelText: 'Task Title',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Title is required.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _instructionsController,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'Instructions',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Schedule',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                if (!_isEdit)
                                  SegmentedButton<_ScheduleMode>(
                                    segments: const [
                                      ButtonSegment(
                                        value: _ScheduleMode.oneTime,
                                        icon: Icon(Icons.event),
                                        label: Text('One Time'),
                                      ),
                                      ButtonSegment(
                                        value: _ScheduleMode.weekdays,
                                        icon: Icon(Icons.calendar_view_week),
                                        label: Text('Weekdays'),
                                      ),
                                    ],
                                    selected: {_scheduleMode},
                                    onSelectionChanged: (selection) {
                                      setState(() {
                                        _scheduleMode = selection.first;
                                      });
                                    },
                                  ),
                                if (!_isEdit) const SizedBox(height: 10),
                                if (_isEdit ||
                                    _scheduleMode == _ScheduleMode.oneTime)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _pickShowDateTime,
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                        ),
                                        label: Text(
                                          'Show Time: ${formatDateTime(_showAt)}',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _pickExpectedDateTime,
                                        icon: const Icon(Icons.schedule),
                                        label: Text(
                                          'Expected Answer Time: ${formatDateTime(_expectedAt)}',
                                        ),
                                      ),
                                    ],
                                  ),
                                if (!_isEdit &&
                                    _scheduleMode == _ScheduleMode.weekdays)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FBFF),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: _pickRepeatStartDate,
                                              icon: const Icon(
                                                Icons.calendar_today,
                                              ),
                                              label: Text(
                                                'Start: ${_formatDateOnly(_repeatStartDate)}',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _pickRepeatEndDate,
                                              icon: const Icon(
                                                Icons.event_available,
                                              ),
                                              label: Text(
                                                'End: ${_formatDateOnly(_repeatEndDate)}',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _pickRepeatTime,
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                              ),
                                              label: Text(
                                                'Show Time: ${_repeatShowTime.format(context)}',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed:
                                                  _pickRepeatExpectedTime,
                                              icon: const Icon(
                                                Icons.access_time,
                                              ),
                                              label: Text(
                                                'Expected Time: ${_repeatExpectedTime.format(context)}',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Days',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (var day = 1; day <= 7; day++)
                                              FilterChip(
                                                label: Text(
                                                  _weekdayShortLabel(day),
                                                ),
                                                selected: _selectedWeekdays
                                                    .contains(day),
                                                onSelected: (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedWeekdays.add(
                                                        day,
                                                      );
                                                    } else {
                                                      _selectedWeekdays.remove(
                                                        day,
                                                      );
                                                    }
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Will create $recurringCount task${recurringCount == 1 ? '' : 's'} in this range.',
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                            child: Row(
                              children: [
                                Text(
                                  'Questions',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: _addQuestion,
                                  icon: const Icon(Icons.add_circle_outline),
                                  label: const Text('Add'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _questions.length; i++)
                          _QuestionCard(
                            index: i,
                            question: _questions[i],
                            onDelete: () => _removeQuestion(i),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(
                            _isLoading
                                ? 'Saving...'
                                : _isEdit
                                ? 'Save Task'
                                : _scheduleMode == _ScheduleMode.weekdays
                                ? 'Create Scheduled Tasks'
                                : 'Save Task',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _QuestionDraftForm {
  _QuestionDraftForm({
    String prompt = '',
    this.type = QuestionInputType.text,
    String options = '',
    String unwantedAnswer = '',
  }) : promptController = TextEditingController(text: prompt),
       optionsController = TextEditingController(text: options),
       unwantedAnswerController = TextEditingController(text: unwantedAnswer),
       notifyOnUnwantedAnswer = unwantedAnswer.trim().isNotEmpty;

  final TextEditingController promptController;
  final TextEditingController optionsController;
  final TextEditingController unwantedAnswerController;
  QuestionInputType type;
  bool notifyOnUnwantedAnswer;

  void dispose() {
    promptController.dispose();
    optionsController.dispose();
    unwantedAnswerController.dispose();
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.onDelete,
  });

  final int index;
  final _QuestionDraftForm question;
  final VoidCallback onDelete;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Question ${widget.index + 1}'),
                const Spacer(),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red.shade700,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: widget.question.promptController,
              decoration: const InputDecoration(labelText: 'Prompt'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<QuestionInputType>(
              initialValue: widget.question.type,
              decoration: const InputDecoration(labelText: 'Input Type'),
              items: QuestionInputType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => widget.question.type = value);
                }
              },
            ),
            if (widget.question.type == QuestionInputType.dropdown ||
                widget.question.type == QuestionInputType.buttons) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.question.optionsController,
                decoration: InputDecoration(
                  labelText: widget.question.type == QuestionInputType.buttons
                      ? 'Buttons (comma separated)'
                      : 'Options (comma separated)',
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: widget.question.notifyOnUnwantedAnswer,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Notify if answer is not what I want',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onChanged: (value) {
                setState(() {
                  widget.question.notifyOnUnwantedAnswer = value;
                });
              },
            ),
            if (widget.question.notifyOnUnwantedAnswer) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: widget.question.unwantedAnswerController,
                decoration: const InputDecoration(
                  labelText: 'Unwanted answer',
                  helperText:
                      'Exact answer text that should trigger a notification.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduledDatePair {
  const _ScheduledDatePair({required this.showAt, required this.expectedAt});

  final DateTime showAt;
  final DateTime expectedAt;
}
