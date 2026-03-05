import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/task_models.dart';
import '../../models/profile.dart';
import '../../services/supabase_service.dart';
import '../../ui/app_theme.dart';
import '../../utils/time_format.dart';

enum _QuestionSort { mostUnusual, mostChanged }

enum _AlertReasonType { unwantedAnswer, numericThreshold, suddenShift }

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.service});

  final SupabaseService service;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<_DashboardPayload> _dashboardFuture;

  _QuestionSort _questionSort = _QuestionSort.mostUnusual;
  String? _selectedEmployeeId;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_DashboardPayload> _loadDashboard({bool forceRefresh = false}) async {
    final results = await Future.wait<dynamic>([
      widget.service.fetchEmployeesOnly(forceRefresh: forceRefresh),
      widget.service.fetchAllAssignments(forceRefresh: forceRefresh),
      widget.service.fetchDashboardAnswerEntries(forceRefresh: forceRefresh),
      widget.service.fetchFlaggedTaskAlertCount(forceRefresh: forceRefresh),
    ]);

    return _DashboardPayload(
      employees: results[0] as List<Profile>,
      assignments: results[1] as List<TaskAssignment>,
      answers: results[2] as List<DashboardAnswerEntry>,
      alertCount: results[3] as int,
      loadedAt: DateTime.now(),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _dashboardFuture = _loadDashboard(forceRefresh: true);
    });
  }

  void _changeEmployee(String? employeeId) {
    if (employeeId == _selectedEmployeeId) {
      return;
    }
    setState(() {
      _selectedEmployeeId = employeeId;
      _dashboardFuture = _loadDashboard(forceRefresh: true);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  bool _isWithinLast7Days(DateTime value, DateTime now) {
    final localValue = value.toLocal();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    return !localValue.isBefore(start);
  }

  List<DashboardAnswerEntry> _filterAnswers(
    List<DashboardAnswerEntry> answers,
  ) {
    final now = DateTime.now();

    final filtered = answers.where((entry) {
      if (!_isWithinLast7Days(entry.answer.answeredAt, now)) {
        return false;
      }
      if (_selectedEmployeeId != null &&
          entry.assignment.employeeId != _selectedEmployeeId) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => b.answer.answeredAt.compareTo(a.answer.answeredAt));
    return filtered;
  }

  String _answerDisplayText(DashboardAnswerEntry entry) {
    final raw = entry.answer.answerText.trim();
    if (raw.isEmpty) {
      return '(blank)';
    }

    if (entry.question.inputType == QuestionInputType.check) {
      final parsed = CheckAnswerValue.parse(raw);
      return parsed.hasDetails ? parsed.displayText : parsed.baseAnswer;
    }

    return raw;
  }

  String _answerCountKey(DashboardAnswerEntry entry) {
    final raw = entry.answer.answerText.trim();
    if (raw.isEmpty) {
      return '(blank)';
    }

    if (entry.question.inputType == QuestionInputType.check) {
      return CheckAnswerValue.parse(raw).baseAnswer.toLowerCase();
    }

    return raw.toLowerCase();
  }

  double? _extractNumericValue(DashboardAnswerEntry entry) {
    if (entry.question.inputType != QuestionInputType.number) {
      return null;
    }

    final raw = entry.answer.answerText.trim();
    if (raw.isEmpty) {
      return null;
    }

    final normalized = raw.replaceAll(',', '');
    final direct = double.tryParse(normalized);
    if (direct != null) {
      return direct;
    }

    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(0)!);
  }

  String _questionKey(DashboardAnswerEntry entry) {
    return '${entry.assignment.title.trim()}||${entry.question.prompt.trim()}||${entry.question.inputType.value}';
  }

  bool _isAnswerMatch(String answerText, String target) {
    return answerText.trim().toLowerCase() == target.trim().toLowerCase();
  }

  Map<String, _NumericStats> _numericStatsByQuestion(
    List<DashboardAnswerEntry> answers,
  ) {
    final grouped = <String, List<double>>{};

    for (final entry in answers) {
      final numeric = _extractNumericValue(entry);
      if (numeric == null) {
        continue;
      }
      grouped.putIfAbsent(_questionKey(entry), () => <double>[]).add(numeric);
    }

    final result = <String, _NumericStats>{};
    grouped.forEach((key, values) {
      if (values.isEmpty) {
        return;
      }
      final sum = values.reduce((a, b) => a + b);
      final mean = sum / values.length;
      final variance = values.length < 2
          ? 0.0
          : values
                    .map((value) => (value - mean) * (value - mean))
                    .reduce((a, b) => a + b) /
                values.length;
      final stdDev = math.sqrt(variance);
      var minValue = values.first;
      var maxValue = values.first;
      for (final value in values) {
        if (value < minValue) {
          minValue = value;
        }
        if (value > maxValue) {
          maxValue = value;
        }
      }
      result[key] = _NumericStats(
        mean: mean,
        stdDev: stdDev,
        min: minValue,
        max: maxValue,
        count: values.length,
      );
    });

    return result;
  }

  Set<String> _detectSuddenShiftAnswerIds(List<DashboardAnswerEntry> answers) {
    final byQuestion = <String, List<DashboardAnswerEntry>>{};
    for (final entry in answers) {
      byQuestion
          .putIfAbsent(_questionKey(entry), () => <DashboardAnswerEntry>[])
          .add(entry);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last7Start = today.subtract(const Duration(days: 6));

    final shifted = <String>{};
    for (final group in byQuestion.values) {
      final previous = <DashboardAnswerEntry>[];
      final todayAnswers = <DashboardAnswerEntry>[];

      for (final entry in group) {
        final answeredAt = entry.answer.answeredAt.toLocal();
        if (answeredAt.isBefore(last7Start)) {
          continue;
        }
        if (_isSameDay(answeredAt, now)) {
          todayAnswers.add(entry);
        } else {
          previous.add(entry);
        }
      }

      if (todayAnswers.isEmpty || previous.length < 4) {
        continue;
      }

      final prevCounts = <String, int>{};
      for (final entry in previous) {
        final key = _answerCountKey(entry);
        prevCounts[key] = (prevCounts[key] ?? 0) + 1;
      }
      if (prevCounts.isEmpty) {
        continue;
      }

      final sortedPrev = prevCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final baseline = sortedPrev.first;
      final baselineShare = baseline.value / previous.length;
      if (baselineShare < 0.65) {
        continue;
      }

      for (final entry in todayAnswers) {
        if (_answerCountKey(entry) != baseline.key) {
          shifted.add(entry.answer.id);
        }
      }
    }

    return shifted;
  }

  List<_UnusualAnswer> _buildUnusualAnswers(
    List<DashboardAnswerEntry> answers,
  ) {
    final numericStats = _numericStatsByQuestion(answers);
    final suddenShiftIds = _detectSuddenShiftAnswerIds(answers);

    final unusual = <_UnusualAnswer>[];
    for (final entry in answers) {
      final reasons = <_AlertReason>[];
      var score = 0.0;

      final unwanted = entry.question.unwantedAnswer;
      if (unwanted != null && unwanted.trim().isNotEmpty) {
        if (_isAnswerMatch(entry.answer.answerText, unwanted)) {
          reasons.add(
            _AlertReason(
              type: _AlertReasonType.unwantedAnswer,
              message: 'Unwanted answer: ${entry.answer.answerText.trim()}',
            ),
          );
          score += 3.0;
        }
      }

      final numeric = _extractNumericValue(entry);
      final stats = numericStats[_questionKey(entry)];
      if (numeric != null &&
          stats != null &&
          stats.count >= 5 &&
          stats.stdDev > 0) {
        final zScore = (numeric - stats.mean).abs() / stats.stdDev;
        if (zScore >= 2.0) {
          reasons.add(
            _AlertReason(
              type: _AlertReasonType.numericThreshold,
              message:
                  'Numeric threshold crossed: ${numeric.toStringAsFixed(1)} (avg ${stats.mean.toStringAsFixed(1)})',
            ),
          );
          score += 2.0 + math.min(zScore, 3.0);
        }
      }

      if (suddenShiftIds.contains(entry.answer.id)) {
        reasons.add(
          const _AlertReason(
            type: _AlertReasonType.suddenShift,
            message: 'Sudden shift from recent baseline',
          ),
        );
        score += 1.8;
      }

      if (reasons.isNotEmpty) {
        unusual.add(
          _UnusualAnswer(entry: entry, reasons: reasons, score: score),
        );
      }
    }

    unusual.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return b.entry.answer.answeredAt.compareTo(a.entry.answer.answeredAt);
    });
    return unusual;
  }

  List<_CountRow> _topAnswers(List<DashboardAnswerEntry> answers) {
    final counts = <String, int>{};
    final labels = <String, String>{};

    for (final entry in answers) {
      final key = _answerCountKey(entry);
      counts[key] = (counts[key] ?? 0) + 1;
      labels.putIfAbsent(key, () => _answerDisplayText(entry));
    }

    final rows =
        counts.entries
            .map(
              (entry) =>
                  _CountRow(label: labels[entry.key]!, count: entry.value),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return rows.take(8).toList();
  }

  _AnswerSnapshot _buildAnswerSnapshot({
    required List<DashboardAnswerEntry> answers,
    required List<_UnusualAnswer> unusual,
    required int alertCount,
  }) {
    final questionKeys = <String>{};
    final employeeIds = <String>{};
    final numericValues = <double>[];

    var yesCount = 0;
    var noCount = 0;

    for (final entry in answers) {
      questionKeys.add('${entry.assignment.title}|${entry.question.prompt}');
      employeeIds.add(entry.assignment.employeeId);

      if (entry.question.inputType == QuestionInputType.check) {
        final parsed = CheckAnswerValue.parse(entry.answer.answerText);
        if (parsed.isYes) {
          yesCount++;
        } else {
          noCount++;
        }
      }

      final numeric = _extractNumericValue(entry);
      if (numeric != null) {
        numericValues.add(numeric);
      }
    }

    final numericAverage = numericValues.isEmpty
        ? null
        : numericValues.reduce((a, b) => a + b) / numericValues.length;

    return _AnswerSnapshot(
      totalResponses: answers.length,
      uniqueQuestions: questionKeys.length,
      uniqueEmployees: employeeIds.length,
      yesCount: yesCount,
      noCount: noCount,
      numericAverage: numericAverage,
      unusualCount: unusual.length,
      alertCount: alertCount,
    );
  }

  List<_QuestionInsightRow> _buildQuestionInsights(
    List<DashboardAnswerEntry> answers,
    List<_UnusualAnswer> unusual,
  ) {
    final byQuestion = <String, _QuestionAccumulator>{};
    final unusualByQuestion = <String, int>{};

    for (final item in unusual) {
      final key = _questionKey(item.entry);
      unusualByQuestion[key] = (unusualByQuestion[key] ?? 0) + 1;
    }

    final now = DateTime.now();

    for (final entry in answers) {
      final key = _questionKey(entry);
      final current =
          byQuestion[key] ??
          _QuestionAccumulator(
            category: entry.assignment.title,
            prompt: entry.question.prompt,
            inputType: entry.question.inputType,
          );

      current.responses++;
      if (entry.answer.answeredAt.isAfter(current.latestAnsweredAt)) {
        current.latestAnsweredAt = entry.answer.answeredAt;
      }

      final answerKey = _answerCountKey(entry);
      current.answerCounts[answerKey] =
          (current.answerCounts[answerKey] ?? 0) + 1;
      current.answerLabels.putIfAbsent(
        answerKey,
        () => _answerDisplayText(entry),
      );

      if (_isSameDay(entry.answer.answeredAt, now)) {
        current.todayAnswerCounts[answerKey] =
            (current.todayAnswerCounts[answerKey] ?? 0) + 1;
      } else {
        current.previousAnswerCounts[answerKey] =
            (current.previousAnswerCounts[answerKey] ?? 0) + 1;
      }

      final numeric = _extractNumericValue(entry);
      if (numeric != null) {
        current.numericValues.add(numeric);
      }

      if (entry.question.inputType == QuestionInputType.check) {
        final parsed = CheckAnswerValue.parse(entry.answer.answerText);
        if (parsed.isYes) {
          current.yesCount++;
        } else {
          current.noCount++;
        }
      }

      current.latestEntries.add(entry);
      byQuestion[key] = current;
    }

    final rows = <_QuestionInsightRow>[];
    byQuestion.forEach((key, value) {
      value.latestEntries.sort(
        (a, b) => b.answer.answeredAt.compareTo(a.answer.answeredAt),
      );

      final distribution =
          value.answerCounts.entries
              .map(
                (entry) => _CountRow(
                  label: value.answerLabels[entry.key] ?? entry.key,
                  count: entry.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.count.compareTo(a.count));

      final numericAverage = value.numericValues.isEmpty
          ? null
          : value.numericValues.reduce((a, b) => a + b) /
                value.numericValues.length;
      double? numericMin;
      double? numericMax;
      if (value.numericValues.isNotEmpty) {
        numericMin = value.numericValues.reduce((a, b) => a < b ? a : b);
        numericMax = value.numericValues.reduce((a, b) => a > b ? a : b);
      }

      final distinctRatio = value.responses == 0
          ? 0.0
          : value.answerCounts.length / value.responses;

      String? todayMode;
      if (value.todayAnswerCounts.isNotEmpty) {
        final sorted = value.todayAnswerCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        todayMode = sorted.first.key;
      }

      String? previousMode;
      double previousModeShare = 0;
      if (value.previousAnswerCounts.isNotEmpty) {
        final sorted = value.previousAnswerCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        previousMode = sorted.first.key;
        previousModeShare =
            sorted.first.value /
            value.previousAnswerCounts.values.reduce((a, b) => a + b);
      }

      var changedScore = distinctRatio * 2;
      if (todayMode != null &&
          previousMode != null &&
          todayMode != previousMode &&
          previousModeShare >= 0.55) {
        changedScore += 1.8;
      }

      final recentResponses = value.latestEntries
          .take(3)
          .map(
            (entry) =>
                '${entry.assignment.employeeName}: ${_answerDisplayText(entry)} (${DateFormat('M/d h:mm a').format(entry.answer.answeredAt.toLocal())})',
          )
          .toList();

      rows.add(
        _QuestionInsightRow(
          category: value.category,
          prompt: value.prompt,
          inputType: value.inputType,
          responses: value.responses,
          latestAnsweredAt: value.latestAnsweredAt,
          distribution: distribution.take(4).toList(),
          yesCount: value.yesCount,
          noCount: value.noCount,
          numericAverage: numericAverage,
          numericMin: numericMin,
          numericMax: numericMax,
          unusualScore: (unusualByQuestion[key] ?? 0).toDouble(),
          changedScore: changedScore,
          latestResponses: recentResponses,
        ),
      );
    });

    rows.sort((a, b) {
      if (_questionSort == _QuestionSort.mostChanged) {
        final byChanged = b.changedScore.compareTo(a.changedScore);
        if (byChanged != 0) {
          return byChanged;
        }
      } else {
        final byUnusual = b.unusualScore.compareTo(a.unusualScore);
        if (byUnusual != 0) {
          return byUnusual;
        }
      }
      return b.latestAnsweredAt.compareTo(a.latestAnsweredAt);
    });

    return rows.take(12).toList();
  }

  List<_CategoryPanelRow> _buildCategoryPanels(
    List<DashboardAnswerEntry> answers,
    List<_UnusualAnswer> unusual,
  ) {
    final byCategory = <String, _CategoryAccumulator>{};
    final outliersByCategory = <String, int>{};
    final now = DateTime.now();

    for (final item in unusual) {
      final category = item.entry.assignment.title.trim();
      outliersByCategory[category] = (outliersByCategory[category] ?? 0) + 1;
    }

    for (final entry in answers) {
      final category = entry.assignment.title.trim();
      final current =
          byCategory[category] ?? _CategoryAccumulator(title: category);

      current.responses++;
      if (_isSameDay(entry.answer.answeredAt, now)) {
        current.todayResponses++;
        final key = _answerCountKey(entry);
        current.todayAnswerCounts[key] =
            (current.todayAnswerCounts[key] ?? 0) + 1;
        current.answerLabels.putIfAbsent(key, () => _answerDisplayText(entry));
      }

      current.questionPrompts.add(entry.question.prompt);
      current.latestAnsweredAt =
          entry.answer.answeredAt.isAfter(current.latestAnsweredAt)
          ? entry.answer.answeredAt
          : current.latestAnsweredAt;

      if (entry.question.inputType == QuestionInputType.check) {
        final parsed = CheckAnswerValue.parse(entry.answer.answerText);
        if (parsed.isYes) {
          current.yesCount++;
        } else {
          current.noCount++;
        }
      }

      byCategory[category] = current;
    }

    final rows = <_CategoryPanelRow>[];
    byCategory.forEach((key, value) {
      final topToday = value.todayAnswerCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final keyTodayAnswers = topToday
          .take(2)
          .map(
            (entry) =>
                '${value.answerLabels[entry.key] ?? entry.key} (${entry.value})',
          )
          .toList();

      final avgPerDay = value.responses / 7;
      String trend;
      if (value.todayResponses > avgPerDay * 1.25 + 1) {
        trend = 'Up vs 7d';
      } else if (value.todayResponses < avgPerDay * 0.75 - 1) {
        trend = 'Down vs 7d';
      } else {
        trend = 'Stable vs 7d';
      }

      rows.add(
        _CategoryPanelRow(
          title: key,
          responses: value.responses,
          todayResponses: value.todayResponses,
          questionCount: value.questionPrompts.length,
          yesCount: value.yesCount,
          noCount: value.noCount,
          keyAnswersToday: keyTodayAnswers,
          trendLabel: trend,
          outlierCount: outliersByCategory[key] ?? 0,
          latestAnsweredAt: value.latestAnsweredAt,
        ),
      );
    });

    rows.sort((a, b) => b.responses.compareTo(a.responses));
    return rows.take(10).toList();
  }

  List<_EmployeePatternRow> _buildEmployeePatterns(
    List<DashboardAnswerEntry> answers,
  ) {
    final byQuestion = <String, _EmployeePatternAccumulator>{};

    for (final entry in answers) {
      final key =
          '${entry.assignment.title.trim()}||${entry.question.prompt.trim()}';
      final current =
          byQuestion[key] ??
          _EmployeePatternAccumulator(
            category: entry.assignment.title,
            prompt: entry.question.prompt,
          );

      final employeeId = entry.assignment.employeeId;
      final employeeStats =
          current.byEmployee[employeeId] ??
          _EmployeePatternEmployee(
            employeeName: entry.assignment.employeeName,
            username: entry.assignment.employeeUsername,
          );

      employeeStats.responses++;
      final answerKey = _answerCountKey(entry);
      employeeStats.answerCounts[answerKey] =
          (employeeStats.answerCounts[answerKey] ?? 0) + 1;
      employeeStats.answerLabels.putIfAbsent(
        answerKey,
        () => _answerDisplayText(entry),
      );

      final numeric = _extractNumericValue(entry);
      if (numeric != null) {
        employeeStats.numericValues.add(numeric);
      }

      current.byEmployee[employeeId] = employeeStats;
      byQuestion[key] = current;
    }

    final rows = <_EmployeePatternRow>[];
    byQuestion.forEach((_, value) {
      if (value.byEmployee.length < 2) {
        return;
      }

      final employeeComparisons = <_EmployeeAnswerPattern>[];
      var totalResponses = 0;

      value.byEmployee.forEach((_, employee) {
        totalResponses += employee.responses;
        final sorted = employee.answerCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topKey = sorted.isEmpty ? null : sorted.first.key;
        final topLabel = topKey == null
            ? '(no answer)'
            : employee.answerLabels[topKey] ?? topKey;

        double? numericAverage;
        if (employee.numericValues.isNotEmpty) {
          numericAverage =
              employee.numericValues.reduce((a, b) => a + b) /
              employee.numericValues.length;
        }

        employeeComparisons.add(
          _EmployeeAnswerPattern(
            employeeName: employee.employeeName,
            username: employee.username,
            responses: employee.responses,
            topAnswer: topLabel,
            numericAverage: numericAverage,
          ),
        );
      });

      employeeComparisons.sort((a, b) => b.responses.compareTo(a.responses));

      rows.add(
        _EmployeePatternRow(
          category: value.category,
          prompt: value.prompt,
          totalResponses: totalResponses,
          employees: employeeComparisons,
        ),
      );
    });

    rows.sort((a, b) => b.totalResponses.compareTo(a.totalResponses));
    return rows.take(8).toList();
  }

  String _formatCompactDouble(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  Color _reasonColor(_AlertReasonType type) {
    return switch (type) {
      _AlertReasonType.unwantedAnswer => const Color(0xFFE57373),
      _AlertReasonType.numericThreshold => const Color(0xFFFFB74D),
      _AlertReasonType.suddenShift => const Color(0xFF64B5F6),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_DashboardPayload>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                children: const [
                  SizedBox(height: 180),
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

            final payload =
                snapshot.data ??
                const _DashboardPayload(
                  employees: <Profile>[],
                  assignments: <TaskAssignment>[],
                  answers: <DashboardAnswerEntry>[],
                  alertCount: 0,
                  loadedAt: null,
                );

            final employeesById = <String, _EmployeeOption>{
              for (final employee in payload.employees)
                employee.id: _EmployeeOption(
                  id: employee.id,
                  label: employee.fullName,
                ),
            };
            for (final assignment in payload.assignments) {
              employeesById.putIfAbsent(
                assignment.employeeId,
                () => _EmployeeOption(
                  id: assignment.employeeId,
                  label: assignment.employeeName,
                ),
              );
            }
            for (final entry in payload.answers) {
              employeesById.putIfAbsent(
                entry.assignment.employeeId,
                () => _EmployeeOption(
                  id: entry.assignment.employeeId,
                  label: entry.assignment.employeeName,
                ),
              );
            }
            final employeeOptions = employeesById.values.toList()
              ..sort(
                (a, b) =>
                    a.label.toLowerCase().compareTo(b.label.toLowerCase()),
              );

            final selectedEmployeeValue =
                employeeOptions.any(
                  (option) => option.id == _selectedEmployeeId,
                )
                ? _selectedEmployeeId
                : null;

            final answers = _filterAnswers(payload.answers);
            final unusual = _buildUnusualAnswers(answers);
            final snapshotStats = _buildAnswerSnapshot(
              answers: answers,
              unusual: unusual,
              alertCount: payload.alertCount,
            );
            final topAnswers = _topAnswers(answers);
            final questionInsights = _buildQuestionInsights(answers, unusual);
            final categoryPanels = _buildCategoryPanels(answers, unusual);
            final employeePatterns = _buildEmployeePatterns(answers);

            final unusualByReason = <_AlertReasonType, int>{
              _AlertReasonType.unwantedAnswer: 0,
              _AlertReasonType.numericThreshold: 0,
              _AlertReasonType.suddenShift: 0,
            };
            for (final item in unusual) {
              for (final reason in item.reasons) {
                unusualByReason[reason.type] =
                    (unusualByReason[reason.type] ?? 0) + 1;
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Admin Data Dashboard',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            if (payload.loadedAt != null)
                              Text(
                                DateFormat(
                                  'h:mm a',
                                ).format(payload.loadedAt!.toLocal()),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: _reload,
                              tooltip: 'Refresh',
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Employee',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: selectedEmployeeValue == null,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => _changeEmployee(null),
                              ),
                              for (final option in employeeOptions) ...[
                                const SizedBox(width: 6),
                                ChoiceChip(
                                  label: Text(option.label),
                                  selected: selectedEmployeeValue == option.id,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => _changeEmployee(option.id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Answer Snapshot (top)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 560 ? 2 : 4;
                    final tileWidth =
                        (constraints.maxWidth - ((columns - 1) * 8)) / columns;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Total responses',
                          value: '${snapshotStats.totalResponses}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Questions',
                          value: '${snapshotStats.uniqueQuestions}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Employees',
                          value: '${snapshotStats.uniqueEmployees}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Yes',
                          value: '${snapshotStats.yesCount}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'No',
                          value: '${snapshotStats.noCount}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Avg numeric',
                          value: snapshotStats.numericAverage == null
                              ? '--'
                              : _formatCompactDouble(
                                  snapshotStats.numericAverage!,
                                ),
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Top unusual',
                          value: '${snapshotStats.unusualCount}',
                        ),
                        _SnapshotTile(
                          width: tileWidth,
                          label: 'Alert count',
                          value: '${snapshotStats.alertCount}',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 860;
                    if (compact) {
                      return Column(
                        children: [
                          _SummaryListCard(
                            title: 'Most common answer values',
                            rows: topAnswers,
                            emptyLabel: 'No answers for this filter.',
                          ),
                          const SizedBox(height: 8),
                          _UnusualAnswersCard(
                            unusual: unusual.take(8).toList(),
                            answerDisplayText: _answerDisplayText,
                            reasonColor: _reasonColor,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SummaryListCard(
                            title: 'Most common answer values',
                            rows: topAnswers,
                            emptyLabel: 'No answers for this filter.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _UnusualAnswersCard(
                            unusual: unusual.take(8).toList(),
                            answerDisplayText: _answerDisplayText,
                            reasonColor: _reasonColor,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Question Insights (main)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('Most unusual'),
                              selected:
                                  _questionSort == _QuestionSort.mostUnusual,
                              onSelected: (_) {
                                setState(
                                  () =>
                                      _questionSort = _QuestionSort.mostUnusual,
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('Most changed'),
                              selected:
                                  _questionSort == _QuestionSort.mostChanged,
                              onSelected: (_) {
                                setState(
                                  () =>
                                      _questionSort = _QuestionSort.mostChanged,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (questionInsights.isEmpty)
                          const Text('No question insights for this filter.')
                        else
                          for (var i = 0; i < questionInsights.length; i++) ...[
                            _QuestionInsightRowView(
                              row: questionInsights[i],
                              numberFormatter: _formatCompactDouble,
                            ),
                            if (i != questionInsights.length - 1)
                              const Divider(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Task/Category Data Panels',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (categoryPanels.isEmpty)
                          const Text('No category data for this filter.')
                        else
                          for (var i = 0; i < categoryPanels.length; i++) ...[
                            _CategoryPanelRowView(row: categoryPanels[i]),
                            if (i != categoryPanels.length - 1)
                              const Divider(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee Input Patterns',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (employeePatterns.isEmpty)
                          const Text(
                            'No cross-employee patterns for this filter.',
                          )
                        else
                          for (var i = 0; i < employeePatterns.length; i++) ...[
                            _EmployeePatternRowView(
                              row: employeePatterns[i],
                              numberFormatter: _formatCompactDouble,
                            ),
                            if (i != employeePatterns.length - 1)
                              const Divider(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alerts based on answer content',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _AlertChip(
                              label: 'Unwanted answer appears',
                              count:
                                  unusualByReason[_AlertReasonType
                                      .unwantedAnswer] ??
                                  0,
                              color: _reasonColor(
                                _AlertReasonType.unwantedAnswer,
                              ),
                            ),
                            _AlertChip(
                              label: 'Numeric threshold crossed',
                              count:
                                  unusualByReason[_AlertReasonType
                                      .numericThreshold] ??
                                  0,
                              color: _reasonColor(
                                _AlertReasonType.numericThreshold,
                              ),
                            ),
                            _AlertChip(
                              label: 'Sudden shift from normal',
                              count:
                                  unusualByReason[_AlertReasonType
                                      .suddenShift] ??
                                  0,
                              color: _reasonColor(_AlertReasonType.suddenShift),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (unusual.isEmpty)
                          const Text('No content-based alerts in this filter.')
                        else
                          for (
                            var i = 0;
                            i < math.min(unusual.length, 12);
                            i++
                          ) ...[
                            _AlertRowView(
                              item: unusual[i],
                              answerDisplayText: _answerDisplayText,
                              reasonColor: _reasonColor,
                            ),
                            if (i != math.min(unusual.length, 12) - 1)
                              const Divider(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F8EA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD6E2C9)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF44513A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryListCard extends StatelessWidget {
  const _SummaryListCard({
    required this.title,
    required this.rows,
    required this.emptyLabel,
  });

  final String title;
  final List<_CountRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(emptyLabel)
            else
              for (var i = 0; i < rows.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF5E2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${rows[i].count}',
                        style: const TextStyle(
                          color: Color(0xFF121A0F),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i != rows.length - 1) const Divider(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _UnusualAnswersCard extends StatelessWidget {
  const _UnusualAnswersCard({
    required this.unusual,
    required this.answerDisplayText,
    required this.reasonColor,
  });

  final List<_UnusualAnswer> unusual;
  final String Function(DashboardAnswerEntry entry) answerDisplayText;
  final Color Function(_AlertReasonType type) reasonColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top unusual answers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (unusual.isEmpty)
              const Text('No unusual answers in this filter.')
            else
              for (var i = 0; i < unusual.length; i++) ...[
                _AlertRowView(
                  item: unusual[i],
                  answerDisplayText: answerDisplayText,
                  reasonColor: reasonColor,
                ),
                if (i != unusual.length - 1) const Divider(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _QuestionInsightRowView extends StatelessWidget {
  const _QuestionInsightRowView({
    required this.row,
    required this.numberFormatter,
  });

  final _QuestionInsightRow row;
  final String Function(double value) numberFormatter;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      row.category,
      row.inputType.label,
      '${row.responses} responses',
    ];

    final distributionText = row.distribution
        .map((entry) => '${entry.label}: ${entry.count}')
        .join(' • ');

    final numericText =
        (row.numericAverage != null &&
            row.numericMin != null &&
            row.numericMax != null)
        ? 'Numeric trend avg ${numberFormatter(row.numericAverage!)} (min ${numberFormatter(row.numericMin!)}, max ${numberFormatter(row.numericMax!)})'
        : null;

    final yesNoText = row.yesCount + row.noCount > 0
        ? 'Yes ${row.yesCount} / No ${row.noCount}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.prompt,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(parts.join(' • '), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          'Distribution: $distributionText',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF314327)),
        ),
        if (yesNoText != null) ...[
          const SizedBox(height: 2),
          Text(yesNoText, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (numericText != null) ...[
          const SizedBox(height: 2),
          Text(numericText, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (row.latestResponses.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Latest: ${row.latestResponses.join(' • ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _CategoryPanelRowView extends StatelessWidget {
  const _CategoryPanelRowView({required this.row});

  final _CategoryPanelRow row;

  @override
  Widget build(BuildContext context) {
    final detail = <String>[
      '${row.responses} responses',
      '${row.todayResponses} today',
      '${row.questionCount} questions',
      row.trendLabel,
    ];

    if (row.yesCount + row.noCount > 0) {
      detail.add('Yes ${row.yesCount}/No ${row.noCount}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (row.outlierCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE0E0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${row.outlierCount} outliers',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(detail.join(' • '), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          row.keyAnswersToday.isEmpty
              ? 'Key answers today: none'
              : 'Key answers today: ${row.keyAnswersToday.join(' • ')}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF314327)),
        ),
        const SizedBox(height: 2),
        Text(
          'Latest ${formatDateTime(row.latestAnsweredAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmployeePatternRowView extends StatelessWidget {
  const _EmployeePatternRowView({
    required this.row,
    required this.numberFormatter,
  });

  final _EmployeePatternRow row;
  final String Function(double value) numberFormatter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row.prompt} (${row.category})',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${row.totalResponses} total responses • ${row.employees.length} employees',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final employee in row.employees)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF5E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  employee.numericAverage == null
                      ? '${employee.employeeName}: ${employee.topAnswer} (${employee.responses})'
                      : '${employee.employeeName}: ${employee.topAnswer} • avg ${numberFormatter(employee.numericAverage!)} (${employee.responses})',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AlertRowView extends StatelessWidget {
  const _AlertRowView({
    required this.item,
    required this.answerDisplayText,
    required this.reasonColor,
  });

  final _UnusualAnswer item;
  final String Function(DashboardAnswerEntry entry) answerDisplayText;
  final Color Function(_AlertReasonType type) reasonColor;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answerDisplayText(entry),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${entry.question.prompt} • ${entry.assignment.title} • ${entry.assignment.employeeName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final reason in item.reasons)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: reasonColor(reason.type).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reason.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          formatDateTime(entry.answer.answeredAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DashboardPayload {
  const _DashboardPayload({
    required this.employees,
    required this.assignments,
    required this.answers,
    required this.alertCount,
    required this.loadedAt,
  });

  final List<Profile> employees;
  final List<TaskAssignment> assignments;
  final List<DashboardAnswerEntry> answers;
  final int alertCount;
  final DateTime? loadedAt;
}

class _AnswerSnapshot {
  const _AnswerSnapshot({
    required this.totalResponses,
    required this.uniqueQuestions,
    required this.uniqueEmployees,
    required this.yesCount,
    required this.noCount,
    required this.numericAverage,
    required this.unusualCount,
    required this.alertCount,
  });

  final int totalResponses;
  final int uniqueQuestions;
  final int uniqueEmployees;
  final int yesCount;
  final int noCount;
  final double? numericAverage;
  final int unusualCount;
  final int alertCount;
}

class _NumericStats {
  const _NumericStats({
    required this.mean,
    required this.stdDev,
    required this.min,
    required this.max,
    required this.count,
  });

  final double mean;
  final double stdDev;
  final double min;
  final double max;
  final int count;
}

class _AlertReason {
  const _AlertReason({required this.type, required this.message});

  final _AlertReasonType type;
  final String message;
}

class _UnusualAnswer {
  const _UnusualAnswer({
    required this.entry,
    required this.reasons,
    required this.score,
  });

  final DashboardAnswerEntry entry;
  final List<_AlertReason> reasons;
  final double score;
}

class _QuestionAccumulator {
  _QuestionAccumulator({
    required this.category,
    required this.prompt,
    required this.inputType,
  }) : latestAnsweredAt = DateTime.fromMillisecondsSinceEpoch(0);

  final String category;
  final String prompt;
  final QuestionInputType inputType;

  int responses = 0;
  DateTime latestAnsweredAt;
  final Map<String, int> answerCounts = <String, int>{};
  final Map<String, String> answerLabels = <String, String>{};
  final Map<String, int> todayAnswerCounts = <String, int>{};
  final Map<String, int> previousAnswerCounts = <String, int>{};
  final List<double> numericValues = <double>[];
  int yesCount = 0;
  int noCount = 0;
  final List<DashboardAnswerEntry> latestEntries = <DashboardAnswerEntry>[];
}

class _QuestionInsightRow {
  const _QuestionInsightRow({
    required this.category,
    required this.prompt,
    required this.inputType,
    required this.responses,
    required this.latestAnsweredAt,
    required this.distribution,
    required this.yesCount,
    required this.noCount,
    required this.numericAverage,
    required this.numericMin,
    required this.numericMax,
    required this.unusualScore,
    required this.changedScore,
    required this.latestResponses,
  });

  final String category;
  final String prompt;
  final QuestionInputType inputType;
  final int responses;
  final DateTime latestAnsweredAt;
  final List<_CountRow> distribution;
  final int yesCount;
  final int noCount;
  final double? numericAverage;
  final double? numericMin;
  final double? numericMax;
  final double unusualScore;
  final double changedScore;
  final List<String> latestResponses;
}

class _CategoryAccumulator {
  _CategoryAccumulator({required this.title})
    : latestAnsweredAt = DateTime.fromMillisecondsSinceEpoch(0);

  final String title;
  int responses = 0;
  int todayResponses = 0;
  final Set<String> questionPrompts = <String>{};
  final Map<String, int> todayAnswerCounts = <String, int>{};
  final Map<String, String> answerLabels = <String, String>{};
  int yesCount = 0;
  int noCount = 0;
  DateTime latestAnsweredAt;
}

class _CategoryPanelRow {
  const _CategoryPanelRow({
    required this.title,
    required this.responses,
    required this.todayResponses,
    required this.questionCount,
    required this.yesCount,
    required this.noCount,
    required this.keyAnswersToday,
    required this.trendLabel,
    required this.outlierCount,
    required this.latestAnsweredAt,
  });

  final String title;
  final int responses;
  final int todayResponses;
  final int questionCount;
  final int yesCount;
  final int noCount;
  final List<String> keyAnswersToday;
  final String trendLabel;
  final int outlierCount;
  final DateTime latestAnsweredAt;
}

class _EmployeePatternAccumulator {
  _EmployeePatternAccumulator({required this.category, required this.prompt});

  final String category;
  final String prompt;
  final Map<String, _EmployeePatternEmployee> byEmployee =
      <String, _EmployeePatternEmployee>{};
}

class _EmployeePatternEmployee {
  _EmployeePatternEmployee({
    required this.employeeName,
    required this.username,
  });

  final String employeeName;
  final String username;
  int responses = 0;
  final Map<String, int> answerCounts = <String, int>{};
  final Map<String, String> answerLabels = <String, String>{};
  final List<double> numericValues = <double>[];
}

class _EmployeePatternRow {
  const _EmployeePatternRow({
    required this.category,
    required this.prompt,
    required this.totalResponses,
    required this.employees,
  });

  final String category;
  final String prompt;
  final int totalResponses;
  final List<_EmployeeAnswerPattern> employees;
}

class _EmployeeAnswerPattern {
  const _EmployeeAnswerPattern({
    required this.employeeName,
    required this.username,
    required this.responses,
    required this.topAnswer,
    required this.numericAverage,
  });

  final String employeeName;
  final String username;
  final int responses;
  final String topAnswer;
  final double? numericAverage;
}

class _CountRow {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;
}

class _EmployeeOption {
  const _EmployeeOption({required this.id, required this.label});

  final String id;
  final String label;
}
