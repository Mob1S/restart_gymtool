import 'package:flutter/widgets.dart';

import '../data/repositories/executor_access.dart';
import '../data/repositories/session_comparison_repo.dart';
import '../data/repositories/session_summary_loader.dart';
import '../domain/session_comparison.dart';
import '../domain/session_summary.dart';

/// A correction can arrive while either query is still running. Both reads
/// belong to the same generation, so an older baseline cannot replace it.
mixin SummaryFeedbackLoader<T extends StatefulWidget> on State<T> {
  SessionSummary? feedbackSummary;
  bool feedbackLoading = true;
  String? feedbackError;
  List<ExerciseComparison>? feedbackComparisons;
  bool comparisonsLoading = false;
  String? comparisonError;
  int _feedbackGeneration = 0;

  Future<SessionSummary?> readFeedbackSummary(SqlExecutor exec, String id) =>
      loadSessionSummary(exec, id);

  Future<List<ExerciseComparison>> readFeedbackComparisons(
    SqlExecutor exec,
    SessionSummary summary,
  ) => loadSessionComparisons(exec, summary);

  Future<void> loadSummaryFeedback(SqlExecutor exec, String id) async {
    if (!mounted) return;
    final generation = ++_feedbackGeneration;
    setState(() {
      if (feedbackSummary?.session.id != id) feedbackSummary = null;
      feedbackLoading = feedbackSummary == null;
      feedbackError = null;
      feedbackComparisons = null;
      comparisonError = null;
      comparisonsLoading = false;
    });
    SessionSummary? summary;
    try {
      summary = await readFeedbackSummary(exec, id);
    } catch (_) {
      if (!mounted || generation != _feedbackGeneration) return;
      setState(() {
        feedbackLoading = false;
        feedbackError = '训练记录载入失败，请重试';
      });
      return;
    }
    if (!mounted || generation != _feedbackGeneration) return;
    setState(() {
      feedbackSummary = summary;
      feedbackLoading = false;
      comparisonsLoading = summary?.session.finishedAt != null;
    });
    if (summary == null || summary.session.finishedAt == null) return;

    try {
      final comparisons = await readFeedbackComparisons(exec, summary);
      if (!mounted || generation != _feedbackGeneration) return;
      setState(() {
        feedbackComparisons = comparisons;
        comparisonsLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _feedbackGeneration) return;
      setState(() {
        comparisonsLoading = false;
        comparisonError = '上次记录对比暂不可用，本场记录仍可查看';
      });
    }
  }

  @override
  void dispose() {
    _feedbackGeneration++;
    super.dispose();
  }
}
