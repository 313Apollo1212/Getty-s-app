enum TaskStatus {
  pending,
  submitted,
  revisionRequested,
  approved;

  static TaskStatus fromString(String value) {
    return switch (value) {
      'submitted' => TaskStatus.submitted,
      'revision_requested' => TaskStatus.revisionRequested,
      'approved' => TaskStatus.approved,
      _ => TaskStatus.pending,
    };
  }

  String get value {
    return switch (this) {
      TaskStatus.pending => 'pending',
      TaskStatus.submitted => 'submitted',
      TaskStatus.revisionRequested => 'revision_requested',
      TaskStatus.approved => 'approved',
    };
  }

  String get label {
    return switch (this) {
      TaskStatus.pending => 'Pending',
      TaskStatus.submitted => 'Submitted',
      TaskStatus.revisionRequested => 'Revision Requested',
      TaskStatus.approved => 'Approved',
    };
  }
}

const _typePrefix = '__type:';
const _unwantedAnswerPrefix = '__meta:unwanted:';
const _checkYesDetailsPrefix = '__meta:check_yes_details:';

enum QuestionInputType {
  text,
  number,
  dropdown,
  time,
  check,
  buttons;

  static QuestionInputType fromString(String value) {
    return switch (value) {
      'number' => QuestionInputType.number,
      'dropdown' => QuestionInputType.dropdown,
      'time' => QuestionInputType.time,
      'check' => QuestionInputType.check,
      'buttons' => QuestionInputType.buttons,
      _ => QuestionInputType.text,
    };
  }

  String get value => name;

  // Current DB enum may not include "check", so persist check as dropdown.
  String get storageValue {
    return switch (this) {
      QuestionInputType.check => QuestionInputType.dropdown.value,
      QuestionInputType.buttons => QuestionInputType.dropdown.value,
      _ => value,
    };
  }

  String get label {
    return switch (this) {
      QuestionInputType.text => 'Text',
      QuestionInputType.number => 'Number',
      QuestionInputType.dropdown => 'Dropdown',
      QuestionInputType.time => 'Time',
      QuestionInputType.check => 'Check (Yes/No)',
      QuestionInputType.buttons => 'Buttons',
    };
  }
}

String weekdayShortLabel(int weekday) {
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

int? weekdayFromShortLabel(String raw) {
  final normalized = raw.trim().toLowerCase();
  return switch (normalized) {
    'mon' => DateTime.monday,
    'tue' => DateTime.tuesday,
    'wed' => DateTime.wednesday,
    'thu' => DateTime.thursday,
    'fri' => DateTime.friday,
    'sat' => DateTime.saturday,
    'sun' => DateTime.sunday,
    _ => null,
  };
}

String formatDurationMinutes(int totalMinutes) {
  if (totalMinutes < 60) {
    return '${totalMinutes}m';
  }
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

class CheckAnswerValue {
  const CheckAnswerValue({
    required this.isYes,
    this.weekdays = const <int>[],
    this.estimatedMinutes,
    this.priority,
  });

  final bool isYes;
  final List<int> weekdays;
  final int? estimatedMinutes;
  final int? priority;

  int? get weekday => weekdays.isEmpty ? null : weekdays.first;

  bool get hasDetails {
    return isYes &&
        weekdays.isNotEmpty &&
        estimatedMinutes != null &&
        priority != null;
  }

  String get baseAnswer => isYes ? 'Yes' : 'No';

  String toStorageText() {
    if (!hasDetails) {
      return baseAnswer;
    }
    final dayLabel = weekdays.map(weekdayShortLabel).join(',');
    return '$baseAnswer | $dayLabel | ${estimatedMinutes}m | P$priority';
  }

  String get displayText {
    if (!hasDetails) {
      return baseAnswer;
    }
    final dayLabel = weekdays.map(weekdayShortLabel).join(', ');
    return '$baseAnswer • $dayLabel • ${formatDurationMinutes(estimatedMinutes!)} • P$priority';
  }

  static CheckAnswerValue parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const CheckAnswerValue(isYes: false);
    }

    final segments = text.split('|').map((entry) => entry.trim()).toList();
    final head = segments.first.toLowerCase();
    final isYes = head.startsWith('yes');
    final isNo = head.startsWith('no');
    if (!isYes && !isNo) {
      return const CheckAnswerValue(isYes: false);
    }

    var weekdays = <int>[];
    int? estimatedMinutes;
    int? priority;

    if (segments.length >= 2) {
      weekdays =
          segments[1]
              .split(',')
              .map((entry) => weekdayFromShortLabel(entry))
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();
    }
    if (segments.length >= 3) {
      final minutesMatch = RegExp(r'(\d+)').firstMatch(segments[2]);
      if (minutesMatch != null) {
        estimatedMinutes = int.tryParse(minutesMatch.group(1)!);
      }
    }
    if (segments.length >= 4) {
      final priorityMatch = RegExp(r'([1-5])').firstMatch(segments[3]);
      if (priorityMatch != null) {
        priority = int.tryParse(priorityMatch.group(1)!);
      }
    }

    return CheckAnswerValue(
      isYes: isYes,
      weekdays: weekdays,
      estimatedMinutes: estimatedMinutes,
      priority: priority,
    );
  }
}

class TaskPriorityHint {
  const TaskPriorityHint({
    required this.weekday,
    required this.priority,
    required this.estimatedMinutes,
    required this.answeredAt,
  });

  final int weekday;
  final int priority;
  final int estimatedMinutes;
  final DateTime answeredAt;
}

class GeneratedTaskItem {
  const GeneratedTaskItem({
    required this.categoryTitle,
    required this.prompt,
    required this.weekdays,
    required this.estimatedMinutes,
    required this.priority,
    required this.answeredAt,
  });

  final String categoryTitle;
  final String prompt;
  final List<int> weekdays;
  final int estimatedMinutes;
  final int priority;
  final DateTime answeredAt;
}

enum GeneratedTaskOutcome {
  done,
  notDone,
  needsMoreTime;

  String get value {
    return switch (this) {
      GeneratedTaskOutcome.done => 'done',
      GeneratedTaskOutcome.notDone => 'not_done',
      GeneratedTaskOutcome.needsMoreTime => 'needs_more_time',
    };
  }

  String get label {
    return switch (this) {
      GeneratedTaskOutcome.done => 'Completed',
      GeneratedTaskOutcome.notDone => 'Not completed',
      GeneratedTaskOutcome.needsMoreTime => 'Needs more time',
    };
  }

  static GeneratedTaskOutcome fromString(String value) {
    return switch (value) {
      'done' => GeneratedTaskOutcome.done,
      'not_done' => GeneratedTaskOutcome.notDone,
      'needs_more_time' => GeneratedTaskOutcome.needsMoreTime,
      _ => GeneratedTaskOutcome.done,
    };
  }
}

class GeneratedTaskActionLog {
  const GeneratedTaskActionLog({
    required this.id,
    required this.employeeId,
    required this.categoryTitle,
    required this.prompt,
    required this.scheduledWeekday,
    required this.originalWeekday,
    required this.priority,
    required this.estimatedMinutes,
    required this.outcome,
    required this.workDate,
    required this.submittedAt,
    this.extraMinutes,
  });

  final String id;
  final String employeeId;
  final String categoryTitle;
  final String prompt;
  final int scheduledWeekday;
  final int originalWeekday;
  final int priority;
  final int estimatedMinutes;
  final GeneratedTaskOutcome outcome;
  final int? extraMinutes;
  final DateTime workDate;
  final DateTime submittedAt;

  factory GeneratedTaskActionLog.fromMap(Map<String, dynamic> map) {
    return GeneratedTaskActionLog(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      categoryTitle: map['category_title'] as String? ?? '',
      prompt: map['prompt'] as String? ?? '',
      scheduledWeekday: (map['scheduled_weekday'] as num?)?.toInt() ?? 1,
      originalWeekday: (map['original_weekday'] as num?)?.toInt() ?? 1,
      priority: (map['priority'] as num?)?.toInt() ?? 3,
      estimatedMinutes: (map['estimated_minutes'] as num?)?.toInt() ?? 0,
      outcome: GeneratedTaskOutcome.fromString(
        map['outcome'] as String? ?? 'done',
      ),
      extraMinutes: (map['extra_minutes'] as num?)?.toInt(),
      workDate: DateTime.parse(map['work_date'] as String),
      submittedAt: DateTime.parse(map['submitted_at'] as String),
    );
  }
}

class GeneratedTaskReassignment {
  const GeneratedTaskReassignment({
    required this.id,
    required this.employeeId,
    required this.categoryTitle,
    required this.prompt,
    required this.originalWeekday,
    required this.fromScheduledWeekday,
    required this.targetWeekday,
    required this.priority,
    required this.estimatedMinutes,
    required this.weekStartDate,
    required this.createdAt,
  });

  final String id;
  final String employeeId;
  final String categoryTitle;
  final String prompt;
  final int originalWeekday;
  final int fromScheduledWeekday;
  final int targetWeekday;
  final int priority;
  final int estimatedMinutes;
  final DateTime weekStartDate;
  final DateTime createdAt;

  factory GeneratedTaskReassignment.fromMap(Map<String, dynamic> map) {
    return GeneratedTaskReassignment(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      categoryTitle: map['category_title'] as String? ?? '',
      prompt: map['prompt'] as String? ?? '',
      originalWeekday: (map['original_weekday'] as num?)?.toInt() ?? 1,
      fromScheduledWeekday:
          (map['from_scheduled_weekday'] as num?)?.toInt() ?? 1,
      targetWeekday: (map['target_weekday'] as num?)?.toInt() ?? 1,
      priority: (map['priority'] as num?)?.toInt() ?? 5,
      estimatedMinutes: (map['estimated_minutes'] as num?)?.toInt() ?? 0,
      weekStartDate: DateTime.parse(map['week_start_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class GeneratedTaskReassignmentDraft {
  const GeneratedTaskReassignmentDraft({
    required this.categoryTitle,
    required this.prompt,
    required this.originalWeekday,
    required this.fromScheduledWeekday,
    required this.targetWeekday,
    required this.priority,
    required this.estimatedMinutes,
  });

  final String categoryTitle;
  final String prompt;
  final int originalWeekday;
  final int fromScheduledWeekday;
  final int targetWeekday;
  final int priority;
  final int estimatedMinutes;
}

class TaskAssignment {
  const TaskAssignment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeUsername,
    required this.title,
    required this.instructions,
    required this.showAt,
    required this.expectedAt,
    required this.status,
    required this.createdAt,
    required this.submittedAt,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeUsername;
  final String title;
  final String instructions;
  final DateTime showAt;
  final DateTime expectedAt;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? submittedAt;

  factory TaskAssignment.fromMap(Map<String, dynamic> map) {
    final employee = (map['employee'] as Map<String, dynamic>?) ?? const {};

    return TaskAssignment(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      employeeName: employee['full_name'] as String? ?? '',
      employeeUsername: employee['username'] as String? ?? '',
      title: map['title'] as String? ?? '',
      instructions: map['instructions'] as String? ?? '',
      showAt: DateTime.parse(
        (map['show_at'] as String?) ?? (map['expected_at'] as String),
      ),
      expectedAt: DateTime.parse(map['expected_at'] as String),
      status: TaskStatus.fromString(map['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(map['created_at'] as String),
      submittedAt: map['submitted_at'] == null
          ? null
          : DateTime.parse(map['submitted_at'] as String),
    );
  }
}

class AssignmentQuestion {
  const AssignmentQuestion({
    required this.id,
    required this.assignmentId,
    required this.prompt,
    required this.inputType,
    required this.sortOrder,
    required this.dropdownOptions,
    required this.unwantedAnswer,
    required this.requiresYesDetails,
  });

  final String id;
  final String assignmentId;
  final String prompt;
  final QuestionInputType inputType;
  final int sortOrder;
  final List<String> dropdownOptions;
  final String? unwantedAnswer;
  final bool requiresYesDetails;

  factory AssignmentQuestion.fromMap(Map<String, dynamic> map) {
    final optionsRaw = map['dropdown_options'];
    final options = <String>[];
    if (optionsRaw is List) {
      for (final entry in optionsRaw) {
        options.add(entry.toString());
      }
    }

    String? storedType;
    String? unwantedAnswer;
    var requiresYesDetails = false;
    final cleanedOptions = <String>[];

    for (final option in options) {
      if (option.startsWith(_typePrefix)) {
        storedType = option.replaceFirst(_typePrefix, '').trim();
        continue;
      }
      if (option.startsWith(_unwantedAnswerPrefix)) {
        final encoded = option.replaceFirst(_unwantedAnswerPrefix, '').trim();
        if (encoded.isNotEmpty) {
          try {
            unwantedAnswer = Uri.decodeComponent(encoded);
          } catch (_) {
            unwantedAnswer = encoded;
          }
        }
        continue;
      }
      if (option.startsWith(_checkYesDetailsPrefix)) {
        final value = option.replaceFirst(_checkYesDetailsPrefix, '').trim();
        requiresYesDetails = value != '0';
        continue;
      }
      cleanedOptions.add(option);
    }

    var inputType = QuestionInputType.fromString(
      map['input_type'] as String? ?? 'text',
    );

    if (storedType != null &&
        (storedType == QuestionInputType.check.value ||
            storedType == QuestionInputType.buttons.value)) {
      inputType = QuestionInputType.fromString(storedType);
    }

    final lowered = cleanedOptions
        .map((entry) => entry.trim().toLowerCase())
        .toList();
    final isYesNo =
        lowered.length == 2 &&
        lowered.contains('yes') &&
        lowered.contains('no');
    if (inputType == QuestionInputType.dropdown && isYesNo) {
      inputType = QuestionInputType.check;
    }

    return AssignmentQuestion(
      id: map['id'] as String,
      assignmentId: map['assignment_id'] as String,
      prompt: map['prompt'] as String? ?? '',
      inputType: inputType,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      dropdownOptions: cleanedOptions,
      unwantedAnswer: unwantedAnswer,
      requiresYesDetails: requiresYesDetails,
    );
  }
}

class QuestionAnswer {
  const QuestionAnswer({
    required this.id,
    required this.questionId,
    required this.answerText,
    required this.answeredAt,
  });

  final String id;
  final String questionId;
  final String answerText;
  final DateTime answeredAt;

  factory QuestionAnswer.fromMap(Map<String, dynamic> map) {
    final idValue = map['id']?.toString();
    final questionIdValue = map['question_id'] as String? ?? '';

    return QuestionAnswer(
      id: idValue == null || idValue.isEmpty ? questionIdValue : idValue,
      questionId: questionIdValue,
      answerText: map['answer_text'] as String? ?? '',
      answeredAt: DateTime.parse(map['answered_at'] as String),
    );
  }
}

class TaskDraftQuestion {
  TaskDraftQuestion({
    required this.prompt,
    required this.inputType,
    required this.dropdownOptions,
    this.unwantedAnswer,
    this.requiresYesDetails = false,
  });

  final String prompt;
  final QuestionInputType inputType;
  final List<String> dropdownOptions;
  final String? unwantedAnswer;
  final bool requiresYesDetails;
}

class TaskAssignmentDraft {
  TaskAssignmentDraft({
    required this.employeeId,
    required this.title,
    required this.instructions,
    required this.showAt,
    required this.expectedAt,
    required this.questions,
  });

  final String employeeId;
  final String title;
  final String instructions;
  final DateTime showAt;
  final DateTime expectedAt;
  final List<TaskDraftQuestion> questions;
}

class FlaggedTaskAlert {
  const FlaggedTaskAlert({
    required this.alertKey,
    required this.assignment,
    required this.question,
    required this.answerText,
    required this.unwantedAnswer,
    required this.answeredAt,
  });

  final String alertKey;
  final TaskAssignment assignment;
  final AssignmentQuestion question;
  final String answerText;
  final String unwantedAnswer;
  final DateTime answeredAt;
}

class DashboardAnswerEntry {
  const DashboardAnswerEntry({
    required this.assignment,
    required this.question,
    required this.answer,
  });

  final TaskAssignment assignment;
  final AssignmentQuestion question;
  final QuestionAnswer answer;
}
