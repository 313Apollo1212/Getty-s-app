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
  bool _isApplyingAction = false;

  @override
  void initState() {
    super.initState();
    _alertsFuture = widget.service.fetchFlaggedTaskAlerts();
  }

  Future<void> _reload() async {
    setState(() {
      _alertsFuture = widget.service.fetchFlaggedTaskAlerts(forceRefresh: true);
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

  Future<void> _ignoreAlert(FlaggedTaskAlert alert) async {
    if (_isApplyingAction) {
      return;
    }
    setState(() => _isApplyingAction = true);
    try {
      await widget.service.ignoreFlaggedTaskAlert(alertKey: alert.alertKey);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alert ignored.')));
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isApplyingAction = false);
      }
    }
  }

  Future<void> _deleteAlert(FlaggedTaskAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Alert'),
        content: const Text(
          'Remove this alert from notifications? This does not delete task answers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    if (_isApplyingAction) {
      return;
    }
    setState(() => _isApplyingAction = true);
    try {
      await widget.service.deleteFlaggedTaskAlert(alertKey: alert.alertKey);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alert deleted.')));
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isApplyingAction = false);
      }
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
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${alert.assignment.employeeName} - ${alert.assignment.title}',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            alert.question.prompt,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _isApplyingAction
                                    ? null
                                    : () => _ignoreAlert(alert),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Ignore'),
                              ),
                              FilledButton.tonal(
                                onPressed: _isApplyingAction
                                    ? null
                                    : () => _openAlertReview(alert),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Review'),
                              ),
                              TextButton(
                                onPressed: _isApplyingAction
                                    ? null
                                    : () => _deleteAlert(alert),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
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
