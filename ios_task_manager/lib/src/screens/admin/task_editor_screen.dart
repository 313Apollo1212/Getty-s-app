import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

enum _ScheduleMode { oneTime, weekdays }

enum _RecurringStopMode { endDate, untilStopped }

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.service,
    this.existingAssignment,
    this.creationKind = AssignmentKind.task,
  });

  final SupabaseService service;
  final TaskAssignment? existingAssignment;
  final AssignmentKind creationKind;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  static const int _maxRecurringTasks = 500;
  static const int _untilStoppedHorizonDays = 3650;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();

  DateTime _showAt = DateTime.now();
  DateTime _expectedAt = DateTime.now().add(const Duration(hours: 1));
  String? _selectedEmployeeId;
  bool _isLoading = false;
  bool _isLoadingQuestions = false;

  _ScheduleMode _scheduleMode = _ScheduleMode.oneTime;
  _RecurringStopMode _recurringStopMode = _RecurringStopMode.endDate;
  DateTime _repeatStartDate = DateUtils.dateOnly(DateTime.now());
  DateTime _repeatEndDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 14)),
  );
  TimeOfDay _repeatShowTime = TimeOfDay.now();
  TimeOfDay _repeatExpectedTime = TimeOfDay.now();
  final Set<int> _selectedWeekdays = {DateTime.now().weekday};

  late Future<List<Profile>> _employeesFuture;
  final List<_QuestionDraftForm> _questions = [];
  late final AssignmentKind _editorKind;

  bool get _isEdit => widget.existingAssignment != null;

  @override
  void initState() {
    super.initState();
    _employeesFuture = widget.service.fetchEmployeesOnly();
    _editorKind = widget.existingAssignment?.kind ?? widget.creationKind;

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
            requiresYesDetails: row.requiresYesDetails,
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

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
      _showAt = _combineDateAndTime(pickedDate, pickedTime);
      if (_expectedAt.isBefore(_showAt)) {
        _expectedAt = _showAt.add(const Duration(hours: 1));
      }
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
      _expectedAt = _combineDateAndTime(pickedDate, pickedTime);
    });
  }

  void _setExpectedOffset(Duration offset) {
    setState(() {
      _expectedAt = _showAt.add(offset);
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

  Future<void> _pickRepeatShowTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _repeatShowTime,
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _repeatShowTime = pickedTime;
      final showTotal = pickedTime.hour * 60 + pickedTime.minute;
      final dueTotal =
          _repeatExpectedTime.hour * 60 + _repeatExpectedTime.minute;
      if (dueTotal < showTotal) {
        _repeatExpectedTime = pickedTime;
      }
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

  void _toggleWeekday(int day, bool selected) {
    setState(() {
      if (selected) {
        _selectedWeekdays.add(day);
      } else {
        _selectedWeekdays.remove(day);
      }
    });
  }

  void _selectPresetWeekdays(Set<int> days) {
    setState(() {
      _selectedWeekdays
        ..clear()
        ..addAll(days);
    });
  }

  int _timeOfDayToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  List<_ScheduledDatePair> _buildRecurringSchedule() {
    final start = DateUtils.dateOnly(_repeatStartDate);
    final end = _recurringStopMode == _RecurringStopMode.endDate
        ? DateUtils.dateOnly(_repeatEndDate)
        : DateUtils.dateOnly(
            _repeatStartDate.add(
              const Duration(days: _untilStoppedHorizonDays),
            ),
          );

    final schedule = <_ScheduledDatePair>[];
    for (
      DateTime date = start;
      !date.isAfter(end) && schedule.length < _maxRecurringTasks;
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
          requiresYesDetails: question.requiresYesDetails,
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
      if (_recurringStopMode == _RecurringStopMode.endDate &&
          _repeatEndDate.isBefore(_repeatStartDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('End date must be on or after start date.'),
          ),
        );
        return;
      }

      if (_timeOfDayToMinutes(_repeatShowTime) >
          _timeOfDayToMinutes(_repeatExpectedTime)) {
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
            kind: _editorKind,
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

        for (final item in schedule) {
          if (item.showAt.isAfter(item.expectedAt)) {
            continue;
          }
          await widget.service.saveAssignment(
            draft: TaskAssignmentDraft(
              employeeId: _selectedEmployeeId!,
              title: _titleController.text,
              instructions: _instructionsController.text,
              kind: _editorKind,
              showAt: item.showAt,
              expectedAt: item.expectedAt,
              questions: draftQuestions,
            ),
          );
          createdCount++;
        }

        if (!mounted) {
          return;
        }

        if (createdCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No tasks were created. Check show/expected times and schedule.',
              ),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      if (!mounted) {
        return;
      }

      if (!_isEdit && _scheduleMode == _ScheduleMode.weekdays) {
        final itemLabel = _editorKind == AssignmentKind.task
            ? 'tasks'
            : 'assessments';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _recurringStopMode == _RecurringStopMode.untilStopped
                  ? 'Started repeating schedule. Created $createdCount upcoming $itemLabel.'
                  : 'Created $createdCount $itemLabel.',
            ),
          ),
        );
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

  String _selectedDaysLabel() {
    if (_selectedWeekdays.isEmpty) {
      return 'No days selected';
    }

    final sorted = _selectedWeekdays.toList()..sort();
    return sorted.map(_weekdayShortLabel).join(', ');
  }

  Widget _buildBasicsSection(List<Profile> employees) {
    return _SectionCard(
      title: '1. Task Details',
      subtitle: 'Pick who gets this task and what they need to do.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedEmployeeId,
            decoration: const InputDecoration(labelText: 'Employee'),
            items: employees
                .map(
                  (employee) => DropdownMenuItem(
                    value: employee.id,
                    child: Text('${employee.fullName} (@${employee.username})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedEmployeeId = value);
            },
            validator: (value) =>
                value == null ? 'Employee is required.' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Task Title'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Title is required.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _instructionsController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Instructions (optional)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOneTimeScheduleSection() {
    final gap = _expectedAt.difference(_showAt);
    final gapLabel = gap.inMinutes >= 0
        ? '${gap.inHours}h ${gap.inMinutes % 60}m between show and due'
        : 'Due time is before show time';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateTimeFieldTile(
          icon: Icons.visibility_outlined,
          title: 'Show task to employee',
          value: formatDateTime(_showAt),
          onTap: _pickShowDateTime,
        ),
        const SizedBox(height: 8),
        _DateTimeFieldTile(
          icon: Icons.schedule,
          title: 'Expected answer time',
          value: formatDateTime(_expectedAt),
          onTap: _pickExpectedDateTime,
        ),
        const SizedBox(height: 10),
        Text(
          'Quick due time shortcuts',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _setExpectedOffset(const Duration(minutes: 30)),
              child: const Text('+30 min'),
            ),
            OutlinedButton(
              onPressed: () => _setExpectedOffset(const Duration(hours: 1)),
              child: const Text('+1 hour'),
            ),
            OutlinedButton(
              onPressed: () => _setExpectedOffset(const Duration(hours: 2)),
              child: const Text('+2 hours'),
            ),
            OutlinedButton(
              onPressed: () => _setExpectedOffset(const Duration(hours: 4)),
              child: const Text('+4 hours'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF5E2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            gapLabel,
            style: const TextStyle(
              color: Color(0xFF121A0F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecurringScheduleSection(int recurringCount) {
    final usesCap =
        _recurringStopMode == _RecurringStopMode.untilStopped &&
        recurringCount >= _maxRecurringTasks;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Repeat until', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<_RecurringStopMode>(
            segments: const [
              ButtonSegment(
                value: _RecurringStopMode.endDate,
                icon: Icon(Icons.event_available_outlined),
                label: Text('End Date'),
              ),
              ButtonSegment(
                value: _RecurringStopMode.untilStopped,
                icon: Icon(Icons.loop_rounded),
                label: Text('Until Stopped'),
              ),
            ],
            selected: {_recurringStopMode},
            onSelectionChanged: (selection) {
              setState(() {
                _recurringStopMode = selection.first;
              });
            },
          ),
          const SizedBox(height: 10),
          Text('Date Range', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _DateTimeFieldTile(
            icon: Icons.event_note_outlined,
            title: 'Start date',
            value: _formatDateOnly(_repeatStartDate),
            onTap: _pickRepeatStartDate,
            compact: true,
          ),
          if (_recurringStopMode == _RecurringStopMode.endDate) ...[
            const SizedBox(height: 6),
            _DateTimeFieldTile(
              icon: Icons.event_available_outlined,
              title: 'End date',
              value: _formatDateOnly(_repeatEndDate),
              onTap: _pickRepeatEndDate,
              compact: true,
            ),
          ] else ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF5E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Repeats every selected week until you stop it.',
                style: TextStyle(
                  color: Color(0xFF121A0F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text('Daily Times', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _DateTimeFieldTile(
            icon: Icons.visibility_outlined,
            title: 'Show time',
            value: _repeatShowTime.format(context),
            onTap: _pickRepeatShowTime,
            compact: true,
          ),
          const SizedBox(height: 6),
          _DateTimeFieldTile(
            icon: Icons.schedule_outlined,
            title: 'Expected time',
            value: _repeatExpectedTime.format(context),
            onTap: _pickRepeatExpectedTime,
            compact: true,
          ),
          const SizedBox(height: 10),
          Text('Weekdays', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(_weekdayShortLabel(day)),
                  selected: _selectedWeekdays.contains(day),
                  onSelected: (selected) => _toggleWeekday(day, selected),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _selectPresetWeekdays({
                  DateTime.monday,
                  DateTime.tuesday,
                  DateTime.wednesday,
                  DateTime.thursday,
                  DateTime.friday,
                }),
                child: const Text('Mon-Fri'),
              ),
              OutlinedButton(
                onPressed: () => _selectPresetWeekdays({
                  DateTime.monday,
                  DateTime.tuesday,
                  DateTime.wednesday,
                  DateTime.thursday,
                  DateTime.friday,
                  DateTime.saturday,
                  DateTime.sunday,
                }),
                child: const Text('All week'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _selectPresetWeekdays({DateTime.saturday, DateTime.sunday}),
                child: const Text('Weekend'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected days: ${_selectedDaysLabel()}',
                  style: const TextStyle(
                    color: Color(0xFF121A0F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _recurringStopMode == _RecurringStopMode.endDate
                      ? 'Will create $recurringCount task${recurringCount == 1 ? '' : 's'} in this range.'
                      : usesCap
                      ? 'Creating $recurringCount upcoming tasks now. This will keep repeating weekly until stopped.'
                      : 'Will create $recurringCount upcoming tasks and keep repeating weekly until stopped.',
                  style: const TextStyle(
                    color: Color(0xFF121A0F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(int recurringCount) {
    return _SectionCard(
      title: '2. Schedule',
      subtitle: 'When the task appears and when the answer is expected.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  label: Text('Repeat by Weekday'),
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
          if (_isEdit || _scheduleMode == _ScheduleMode.oneTime)
            _buildOneTimeScheduleSection(),
          if (!_isEdit && _scheduleMode == _ScheduleMode.weekdays)
            _buildRecurringScheduleSection(recurringCount),
        ],
      ),
    );
  }

  Widget _buildQuestionsSection() {
    return Column(
      children: [
        _SectionCard(
          title: '3. Questions',
          subtitle: 'Add the questions employees will answer for this task.',
          trailing: FilledButton.tonalIcon(
            onPressed: _addQuestion,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add Question'),
          ),
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _questions.length; i++)
          _QuestionCard(
            index: i,
            question: _questions[i],
            onDelete: () => _removeQuestion(i),
            canDelete: _questions.length > 1,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recurringCount = _buildRecurringSchedule().length;
    final label = _editorKind.label;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit $label' : 'Create $label')),
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
                        _buildBasicsSection(employees),
                        const SizedBox(height: 12),
                        _buildScheduleSection(recurringCount),
                        const SizedBox(height: 12),
                        _buildQuestionsSection(),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _save,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _isLoading
                                ? 'Saving...'
                                : _isEdit
                                ? 'Save $label Changes'
                                : _scheduleMode == _ScheduleMode.weekdays
                                ? _recurringStopMode ==
                                          _RecurringStopMode.untilStopped
                                      ? 'Start Weekly Repeat ($recurringCount queued)'
                                      : 'Create $recurringCount Scheduled $label${recurringCount == 1 ? '' : 's'}'
                                : 'Create $label',
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _DateTimeFieldTile extends StatelessWidget {
  const _DateTimeFieldTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: compact ? Colors.white : const Color(0xFFF4F8EC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_calendar_outlined, size: 18),
            ],
          ),
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
    this.requiresYesDetails = false,
  }) : promptController = TextEditingController(text: prompt),
       optionsController = TextEditingController(text: options),
       unwantedAnswerController = TextEditingController(text: unwantedAnswer),
       notifyOnUnwantedAnswer = unwantedAnswer.trim().isNotEmpty;

  final TextEditingController promptController;
  final TextEditingController optionsController;
  final TextEditingController unwantedAnswerController;
  QuestionInputType type;
  bool notifyOnUnwantedAnswer;
  bool requiresYesDetails;

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
    required this.canDelete,
  });

  final int index;
  final _QuestionDraftForm question;
  final VoidCallback onDelete;
  final bool canDelete;

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
                Text(
                  'Question ${widget.index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.canDelete ? widget.onDelete : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: widget.question.promptController,
              decoration: const InputDecoration(labelText: 'Question text'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<QuestionInputType>(
              initialValue: widget.question.type,
              decoration: const InputDecoration(labelText: 'Answer type'),
              items: QuestionInputType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    widget.question.type = value;
                    if (value != QuestionInputType.check) {
                      widget.question.requiresYesDetails = false;
                    }
                  });
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
                      ? 'Button labels (comma separated)'
                      : 'Dropdown options (comma separated)',
                  helperText: 'Example: Yes, No',
                ),
              ),
            ],
            if (widget.question.type == QuestionInputType.check) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: widget.question.requiresYesDetails,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'If employee answers Yes, ask for day + estimate + priority',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Shows a Mon-Sun picker, estimated time slider, and 1-5 priority on employee submit.',
                ),
                onChanged: (value) {
                  setState(() {
                    widget.question.requiresYesDetails = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: widget.question.notifyOnUnwantedAnswer,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Alert admin on unwanted answer',
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
                  helperText: 'Exact answer text that should trigger alert.',
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
