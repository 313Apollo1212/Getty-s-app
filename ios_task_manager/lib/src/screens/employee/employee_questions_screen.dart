import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

class EmployeeQuestionsScreen extends StatefulWidget {
  const EmployeeQuestionsScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<EmployeeQuestionsScreen> createState() =>
      _EmployeeQuestionsScreenState();
}

class _EmployeeQuestionsScreenState extends State<EmployeeQuestionsScreen> {
  late Future<List<EmployeeQuestionMessage>> _messagesFuture;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messagesFuture = widget.service.fetchCurrentEmployeeQuestionMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload({bool forceRefresh = true}) async {
    setState(() {
      _messagesFuture = widget.service.fetchCurrentEmployeeQuestionMessages(
        forceRefresh: forceRefresh,
      );
    });
  }

  Future<void> _sendResponse() async {
    final text = _messageController.text.trim();
    if (_isSending || text.isEmpty) {
      return;
    }

    setState(() => _isSending = true);
    try {
      await widget.service.sendEmployeeQuestionResponse(messageText: text);
      _messageController.clear();
      await _reload();
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

  Widget _buildBubble(EmployeeQuestionMessage message) {
    final meId = widget.service.currentUser?.id;
    final isMine =
        message.senderRole == QuestionMessageSenderRole.employee &&
        message.senderId == meId;
    final bubbleColor = isMine
        ? const Color(0xFF1C4A2A)
        : const Color(0xFFE7ECDF);
    final textColor = isMine ? Colors.white : const Color(0xFF13200F);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
            formatDateTime(message.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Card(
      margin: EdgeInsets.zero,
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
                onSubmitted: (_) => _sendResponse(),
                decoration: const InputDecoration(
                  hintText: 'Type your response...',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSending ? null : _sendResponse,
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
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: FutureBuilder<List<EmployeeQuestionMessage>>(
                  future: _messagesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return ListView(
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

                    final messages =
                        snapshot.data ?? const <EmployeeQuestionMessage>[];
                    if (messages.isEmpty) {
                      return ListView(
                        children: const [
                          Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No questions yet. Admin questions will appear here.',
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildBubble(messages[index]),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: _buildComposer(),
            ),
          ],
        ),
      ),
    );
  }
}
