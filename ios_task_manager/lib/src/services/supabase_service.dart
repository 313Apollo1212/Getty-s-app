import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/task_models.dart';

class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  static String usernameToEmail(String username) {
    final normalized = username.trim().toLowerCase();
    return '$normalized@example.com';
  }

  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: usernameToEmail(username),
        password: password,
      );
    } on AuthException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<Profile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) {
      return null;
    }

    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return Profile.fromMap(row);
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<List<Profile>> fetchAllUsers() async {
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .order('full_name', ascending: true);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Profile.fromMap)
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<List<Profile>> fetchEmployeesOnly() async {
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .eq('role', 'employee')
          .order('full_name', ascending: true);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Profile.fromMap)
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-create-user',
        body: {
          'username': username.trim(),
          'password': password,
          'full_name': fullName.trim(),
          'role': role,
        },
      );

      if (response.status < 200 || response.status > 299) {
        if (response.status == 404) {
          throw const AppException(
            'Backend function "admin-create-user" is not deployed.',
          );
        }
        final data = response.data;
        final message = data is Map<String, dynamic>
            ? data['error']?.toString() ?? 'Failed to create user.'
            : 'Failed to create user.';
        throw AppException(message);
      }
    } on FunctionException catch (error) {
      throw AppException(error.details?.toString() ?? error.toString());
    }
  }

  Future<void> resetUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-reset-password',
        body: {'user_id': userId, 'new_password': newPassword},
      );

      if (response.status < 200 || response.status > 299) {
        if (response.status == 404) {
          throw const AppException(
            'Backend function "admin-reset-password" is not deployed.',
          );
        }
        final data = response.data;
        final message = data is Map<String, dynamic>
            ? data['error']?.toString() ?? 'Failed to reset password.'
            : 'Failed to reset password.';
        throw AppException(message);
      }
    } on FunctionException catch (error) {
      throw AppException(error.details?.toString() ?? error.toString());
    }
  }

  Future<void> deleteUser({required String userId}) async {
    try {
      final response = await _client.functions.invoke(
        'admin-delete-user',
        body: {'user_id': userId},
      );

      if (response.status < 200 || response.status > 299) {
        if (response.status == 404) {
          throw const AppException(
            'Backend function "admin-delete-user" is not deployed.',
          );
        }
        final data = response.data;
        final message = data is Map<String, dynamic>
            ? data['error']?.toString() ?? 'Failed to delete user.'
            : 'Failed to delete user.';
        throw AppException(message);
      }
    } on FunctionException catch (error) {
      throw AppException(error.details?.toString() ?? error.toString());
    }
  }

  Future<void> updateOwnProfile({
    required String username,
    required String fullName,
    String? newPassword,
  }) async {
    try {
      final body = <String, dynamic>{
        'username': username.trim(),
        'full_name': fullName.trim(),
      };

      if (newPassword != null && newPassword.trim().isNotEmpty) {
        body['new_password'] = newPassword.trim();
      }

      final response = await _client.functions.invoke(
        'update-my-profile',
        body: body,
      );

      if (response.status < 200 || response.status > 299) {
        if (response.status == 404) {
          throw const AppException(
            'Backend function "update-my-profile" is not deployed.',
          );
        }
        final data = response.data;
        final message = data is Map<String, dynamic>
            ? data['error']?.toString() ?? 'Failed to update profile.'
            : 'Failed to update profile.';
        throw AppException(message);
      }
    } on FunctionException catch (error) {
      throw AppException(error.details?.toString() ?? error.toString());
    }
  }

  Future<List<TaskAssignment>> fetchAllAssignments() async {
    try {
      final rows = await _client
          .from('task_assignments')
          .select(
            '*, employee:profiles!task_assignments_employee_id_fkey(full_name, username)',
          )
          .order('expected_at', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(TaskAssignment.fromMap)
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<List<TaskAssignment>> fetchAssignmentsForCurrentEmployee() async {
    final user = currentUser;
    if (user == null) {
      return [];
    }

    try {
      final rows = await _client
          .from('task_assignments')
          .select(
            '*, employee:profiles!task_assignments_employee_id_fkey(full_name, username)',
          )
          .eq('employee_id', user.id)
          .order('expected_at', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(TaskAssignment.fromMap)
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<List<AssignmentQuestion>> fetchAssignmentQuestions(
    String assignmentId,
  ) async {
    try {
      final rows = await _client
          .from('assignment_questions')
          .select()
          .eq('assignment_id', assignmentId)
          .order('sort_order', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(AssignmentQuestion.fromMap)
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<Map<String, QuestionAnswer>> fetchAnswersForAssignment(
    String assignmentId,
  ) async {
    final user = currentUser;
    if (user == null) {
      return const {};
    }

    try {
      final rows = await _client
          .from('question_answers')
          .select()
          .eq('assignment_id', assignmentId)
          .eq('employee_id', user.id);

      final map = <String, QuestionAnswer>{};
      for (final entry in (rows as List).cast<Map<String, dynamic>>()) {
        final answer = QuestionAnswer.fromMap(entry);
        map[answer.questionId] = answer;
      }
      return map;
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<Map<String, QuestionAnswer>> fetchAnswersForAdminReview({
    required String assignmentId,
    required String employeeId,
  }) async {
    try {
      final rows = await _client
          .from('question_answers')
          .select()
          .eq('assignment_id', assignmentId)
          .eq('employee_id', employeeId);

      final map = <String, QuestionAnswer>{};
      for (final entry in (rows as List).cast<Map<String, dynamic>>()) {
        final answer = QuestionAnswer.fromMap(entry);
        map[answer.questionId] = answer;
      }
      return map;
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> saveAssignment({
    required TaskAssignmentDraft draft,
    String? assignmentId,
  }) async {
    final currentAdmin = currentUser;
    if (currentAdmin == null) {
      throw const AppException('You must be signed in.');
    }

    final data = {
      'employee_id': draft.employeeId,
      'title': draft.title.trim(),
      'instructions': draft.instructions.trim(),
      'expected_at': draft.expectedAt.toUtc().toIso8601String(),
    };

    try {
      late final String id;
      if (assignmentId == null) {
        final inserted = await _client
            .from('task_assignments')
            .insert({...data, 'created_by': currentAdmin.id})
            .select('id')
            .single();
        id = inserted['id'] as String;
      } else {
        id = assignmentId;
        await _client
            .from('task_assignments')
            .update({
              ...data,
              'status': TaskStatus.pending.value,
              'submitted_at': null,
            })
            .eq('id', id);
        await _client.from('question_answers').delete().eq('assignment_id', id);
        await _client
            .from('assignment_questions')
            .delete()
            .eq('assignment_id', id);
      }

      final questionsPayload = <Map<String, dynamic>>[];
      for (var index = 0; index < draft.questions.length; index++) {
        final question = draft.questions[index];
        final inputType = question.inputType.storageValue;
        final dropdownOptions = switch (question.inputType) {
          QuestionInputType.check => <String>['__type:check', 'Yes', 'No'],
          QuestionInputType.buttons => <String>[
            '__type:buttons',
            ...question.dropdownOptions,
          ],
          QuestionInputType.dropdown => question.dropdownOptions,
          _ => <String>[],
        };

        questionsPayload.add({
          'assignment_id': id,
          'prompt': question.prompt.trim(),
          'input_type': inputType,
          'dropdown_options': dropdownOptions,
          'sort_order': index,
        });
      }

      if (questionsPayload.isNotEmpty) {
        await _client.from('assignment_questions').insert(questionsPayload);
      }
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> submitAnswers({
    required String assignmentId,
    required Map<String, String> answers,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AppException('You must be signed in.');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    final payload = answers.entries
        .map(
          (entry) => {
            'assignment_id': assignmentId,
            'question_id': entry.key,
            'employee_id': user.id,
            'answer_text': entry.value.trim(),
            'answered_at': now,
          },
        )
        .toList();

    try {
      if (payload.isNotEmpty) {
        await _client
            .from('question_answers')
            .upsert(
              payload,
              onConflict: 'assignment_id,question_id,employee_id',
            );
      }

      await _client
          .from('task_assignments')
          .update({'status': TaskStatus.submitted.value, 'submitted_at': now})
          .eq('id', assignmentId);
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> updateAssignmentStatus({
    required String assignmentId,
    required TaskStatus status,
  }) async {
    final payload = <String, dynamic>{'status': status.value};
    if (status == TaskStatus.pending) {
      payload['submitted_at'] = null;
    }

    try {
      await _client
          .from('task_assignments')
          .update(payload)
          .eq('id', assignmentId);
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }

  Future<void> deleteAssignment({required String assignmentId}) async {
    try {
      await _client.from('task_assignments').delete().eq('id', assignmentId);
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    }
  }
}
