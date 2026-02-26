import 'package:flutter/material.dart';

import '../../models/task_models.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';
import 'task_review_screen.dart';

class TaskAlertsScreen extends StatefulWidget {
  const TaskAlertsScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<TaskAlertsScreen> createState() => _TaskAlertsScreenState();
}

class _TaskAlertsScreenState extends State<TaskAlertsScreen> {
  late Future<List<FlaggedTaskAlert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = widget.service.fetchFlaggedTaskAlerts();
  }

  Future<void> _reload() async {
    setState(() {
      _alertsFuture = widget.service.fetchFlaggedTaskAlerts();
    });
  }

  Future<void> _openAlertReview(FlaggedTaskAlert alert) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskReviewScreen(
          service: widget.service,
          assignment: alert.assignment,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Alerts')),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<FlaggedTaskAlert>>(
            future: _alertsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ListView(
                  children: const [
                    SizedBox(height: 160),
                    Center(child: CircularProgressIndicator()),
                  ],
                );
              }

              if (snapshot.hasError) {
                return ListView(
                  padding: appPagePadding,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(snapshot.error.toString()),
                      ),
                    ),
                  ],
                );
              }

              final alerts = snapshot.data ?? const [];
              if (alerts.isEmpty) {
                return ListView(
                  padding: appPagePadding,
                  children: const [
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No flagged answers right now.'),
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: appPagePadding,
                itemCount: alerts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openAlertReview(alert),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${alert.assignment.employeeName} - ${alert.assignment.title}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              alert.question.prompt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Answer: ${alert.answerText}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF9B1C1C),
                              ),
                            ),
                            Text(
                              'Trigger value: ${alert.unwantedAnswer}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Answered at ${formatDateTime(alert.answeredAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
