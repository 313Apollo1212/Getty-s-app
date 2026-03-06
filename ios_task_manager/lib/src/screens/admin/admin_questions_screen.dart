import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

class AdminQuestionsScreen extends StatefulWidget {
  const AdminQuestionsScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends State<AdminQuestionsScreen> {
  late Future<List<Profile>> _employeesFuture;
  Future<List<EmployeeQuestionMessage>>? _messagesFuture;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _selectedEmployeeId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _employeesFuture = widget.service.fetchEmployeesOnly();
    _bootstrapSelection();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapSelection() async {
    try {
      final employees = await widget.service.fetchEmployeesOnly();
      if (!mounted || employees.isEmpty) {
        return;
      }
      setState(() {
        _selectedEmployeeId = employees.first.id;
        _messagesFuture = widget.service.fetchQuestionMessagesForEmployee(
          employeeId: employees.first.id,
        );
      });
    } catch (_) {}
  }

  Future<void> _selectEmployee(String employeeId) async {
    if (_selectedEmployeeId == employeeId) {
      return;
    }
    setState(() {
      _selectedEmployeeId = employeeId;
      _messagesFuture = widget.service.fetchQuestionMessagesForEmployee(
        employeeId: employeeId,
        forceRefresh: true,
      );
    });
  }

  Future<void> _reloadMessages() async {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) {
      return;
    }
    setState(() {
      _messagesFuture = widget.service.fetchQuestionMessagesForEmployee(
        employeeId: employeeId,
        forceRefresh: true,
      );
    });
  }

  Future<void> _sendQuestion() async {
    final employeeId = _selectedEmployeeId;
    final text = _messageController.text.trim();
    if (_isSending || employeeId == null || text.isEmpty) {
      return;
    }

    setState(() => _isSending = true);
    try {
      await widget.service.sendAdminQuestionMessage(
        employeeId: employeeId,
        messageText: text,
      );
      _messageController.clear();
      await _reloadMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
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
        setState(() => _isSending = false);
      }
    }
  }

  Widget _buildEmployeeSelector(List<Profile> employees) {
    if (employees.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('No employees yet.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final employee in employees) ...[
                ChoiceChip(
                  label: Text(employee.fullName),
                  selected: _selectedEmployeeId == employee.id,
                  onSelected: (_) => _selectEmployee(employee.id),
                ),
                if (employee != employees.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(EmployeeQuestionMessage message) {
    final meId = widget.service.currentUser?.id;
    final isMine =
        message.senderRole == QuestionMessageSenderRole.admin &&
        message.senderId == meId;

    final alignment = isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubbleColor = isMine
        ? const Color(0xFF1C4A2A)
        : const Color(0xFFE7ECDF);
    final textColor = isMine ? Colors.white : const Color(0xFF13200F);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            message.messageText,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${message.senderRole == QuestionMessageSenderRole.admin ? 'Admin' : 'Employee'} • ${formatDateTime(message.createdAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildMessagesBody() {
    final future = _messagesFuture;
    if (future == null) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Select an employee to start.'),
          ),
        ),
      );
    }

    return FutureBuilder<List<EmployeeQuestionMessage>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(snapshot.error.toString()),
            ),
          );
        }

        final messages = snapshot.data ?? const <EmployeeQuestionMessage>[];
        if (messages.isEmpty) {
          return const Card(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No messages yet. Ask the first question below.'),
              ),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _buildMessageBubble(messages[index]),
          ),
        );
      },
    );
  }

  Widget _buildComposer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendQuestion(),
                decoration: const InputDecoration(
                  hintText: 'Type question for employee...',
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSending ? null : _sendQuestion,
              icon: _isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_isSending ? 'Sending...' : 'Send'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask a Question')),
      body: AppBackground(
        child: FutureBuilder<List<Profile>>(
          future: _employeesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: appPagePadding,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(snapshot.error.toString()),
                    ),
                  ),
                ],
              );
            }

            final employees = snapshot.data ?? const <Profile>[];

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _buildEmployeeSelector(employees),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMessagesBody(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: _buildComposer(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
