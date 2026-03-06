import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import 'admin_questions_screen.dart';
import 'task_editor_screen.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  Future<void> _openEditor({required AssignmentKind creationKind}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          service: widget.service,
          creationKind: creationKind,
        ),
      ),
    );
  }

  Future<void> _openAskQuestion() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminQuestionsScreen(service: widget.service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: appPagePadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        _openEditor(creationKind: AssignmentKind.assessment),
                    icon: const Icon(Icons.assignment_add),
                    label: const Text('Create Assessment'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _openEditor(creationKind: AssignmentKind.task),
                    icon: const Icon(Icons.add_task),
                    label: const Text('Create Task'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _openAskQuestion,
                    icon: const Icon(Icons.question_answer_outlined),
                    label: const Text('Ask a Question'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
