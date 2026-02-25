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

class TaskAssignment {
  const TaskAssignment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeUsername,
    required this.title,
    required this.instructions,
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
  });

  final String id;
  final String assignmentId;
  final String prompt;
  final QuestionInputType inputType;
  final int sortOrder;
  final List<String> dropdownOptions;

  factory AssignmentQuestion.fromMap(Map<String, dynamic> map) {
    final optionsRaw = map['dropdown_options'];
    final options = <String>[];
    if (optionsRaw is List) {
      for (final entry in optionsRaw) {
        options.add(entry.toString());
      }
    }

    String? storedType;
    if (options.isNotEmpty && options.first.startsWith('__type:')) {
      storedType = options.first.replaceFirst('__type:', '').trim();
      options.removeAt(0);
    }

    var inputType = QuestionInputType.fromString(
      map['input_type'] as String? ?? 'text',
    );

    if (storedType != null &&
        (storedType == QuestionInputType.check.value ||
            storedType == QuestionInputType.buttons.value)) {
      inputType = QuestionInputType.fromString(storedType);
    }

    final lowered = options.map((entry) => entry.trim().toLowerCase()).toList();
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
      dropdownOptions: options,
    );
  }
}

class QuestionAnswer {
  const QuestionAnswer({
    required this.questionId,
    required this.answerText,
    required this.answeredAt,
  });

  final String questionId;
  final String answerText;
  final DateTime answeredAt;

  factory QuestionAnswer.fromMap(Map<String, dynamic> map) {
    return QuestionAnswer(
      questionId: map['question_id'] as String,
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
  });

  final String prompt;
  final QuestionInputType inputType;
  final List<String> dropdownOptions;
}

class TaskAssignmentDraft {
  TaskAssignmentDraft({
    required this.employeeId,
    required this.title,
    required this.instructions,
    required this.expectedAt,
    required this.questions,
  });

  final String employeeId;
  final String title;
  final String instructions;
  final DateTime expectedAt;
  final List<TaskDraftQuestion> questions;
}
