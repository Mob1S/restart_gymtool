import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../domain/session_comparison.dart';
import '../../domain/set_detail.dart';
import '../../domain/types.dart';
import '../theme.dart';
import '../tokens.dart';
import 'app_card.dart';

/// Describes recorded work, without turning load or volume into a strength claim.
class SessionComparisonView extends StatelessWidget {
  final List<ExerciseComparison>? comparisons;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  const SessionComparisonView({
    super.key,
    this.comparisons,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && error == null && (comparisons?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    final c = appColors(context);
    return Column(
      key: const ValueKey('session-comparison'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(
          '与上次同动作记录对比',
          style: TextStyle(
            fontSize: AppFontSize.h2,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '组数包含已完成的热身及未分类组；容量为重量 × 次数，表示训练量。',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: c.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text('正在读取上次记录…'),
          )
        else if (error != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error!),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('重试对比')),
              ],
            ),
          )
        else
          for (final comparison in comparisons!)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(child: _ComparisonCard(comparison: comparison)),
            ),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final ExerciseComparison comparison;
  const _ComparisonCard({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final previous = comparison.previous;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          comparison.exerciseName,
          style: TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _RecordBlock(label: '本次', record: comparison.current),
        const SizedBox(height: AppSpacing.md),
        if (previous == null)
          Text('首次记录，暂没有上次可对比', style: TextStyle(color: c.textSecondary))
        else ...[
          Divider(color: c.border, height: AppSpacing.lg),
          _RecordBlock(label: '上次', record: previous),
          const SizedBox(height: AppSpacing.md),
          Text(
            '训练量变化：${previous.logicalSetCount} 组 → '
            '${comparison.current.logicalSetCount} 组 · '
            '${_volumeChange(comparison.current.volumeLoad - previous.volumeLoad)}',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: c.textSecondary,
              fontFeatures: tabularNums,
            ),
          ),
        ],
      ],
    );
  }

  String _volumeChange(double difference) {
    if (difference.abs() < 1e-9) return '容量相同';
    return '容量${difference > 0 ? '增加' : '减少'} '
        '${formatWeightKg(difference.abs())} kg';
  }
}

class _RecordBlock extends StatelessWidget {
  final String label;
  final SessionExerciseRecord record;
  const _RecordBlock({required this.label, required this.record});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final date = DateTime.fromMillisecondsSinceEpoch(record.session.startedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label · ${date.year}年${formatDate(record.session.startedAt)}',
          style: TextStyle(
            fontSize: AppFontSize.body,
            fontWeight: FontWeight.w600,
            color: label == '本次' ? c.accent : c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${record.logicalSetCount} 组 · 容量 ${formatWeightKg(record.volumeLoad)} kg',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: c.textSecondary,
            fontFeatures: tabularNums,
          ),
        ),
        for (final (occurrenceIndex, occurrence)
            in record.occurrences.indexed) ...[
          if (record.occurrences.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '第 ${occurrenceIndex + 1} 次出现',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: c.textSecondary,
                ),
              ),
            ),
          for (final (index, set) in occurrence.sets.indexed)
            _SetRecord(index: index, set: set),
        ],
      ],
    );
  }
}

class _SetRecord extends StatelessWidget {
  final int index;
  final SetEntry set;
  const _SetRecord({required this.index, required this.set});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final detail = set.detail;
    final role = switch (detail?.role) {
      'warmup' => '热身',
      'work' => '正式',
      _ => '未分类',
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${index + 1} 组 · ${set.equipmentWeight.label} × ${set.reps} · '
            '$role · ${detail?.effort?.label ?? '用力程度未记录'}',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: c.textPrimary,
              fontFeatures: tabularNums,
            ),
          ),
          for (final segment in detail?.continuations ?? <RecordedSegment>[])
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
              ),
              child: Text(
                '休息 ${segment.pauseSeconds} 秒 → ${segment.reading.label} × '
                '${segment.reps} · ${segment.effort?.label ?? '用力程度未记录'}',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: c.textSecondary,
                  fontFeatures: tabularNums,
                ),
              ),
            ),
          if (detail?.endedEarly == true)
            Text(
              '本组提前结束，仅统计已完成部分',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: c.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
