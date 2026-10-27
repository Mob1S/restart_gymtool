import 'package:flutter/material.dart';

import '../../domain/rest_advice.dart';
import '../../domain/session_summary.dart';
import '../../domain/session_comparison.dart';
import '../../domain/types.dart';
import '../theme.dart';
import '../tokens.dart';
import 'app_card.dart';
import 'stat_block.dart';
import 'session_comparison_view.dart';

/// 总结正文：三个数字、口径字样、组间休息回顾，以及每个动作的卡片。
///
/// **总结页（刚练完）与历史详情页（翻旧账）共用这一份渲染。** 数字由
/// `data/repositories/session_summary_loader.dart` 装载（口径只此一处），
/// 这里只回答长什么样 —— 两个屏幕各画一套的话，同一场训练迟早会出现两套
/// 口径字样，而且不会有任何测试变红。
///
/// 它**不含滚动**：正文摊成一列，滚动留给调用方 —— 总结页要在这一列后面
/// 接「完成」按钮，两者得在同一个 ListView 里一起滚。
class SessionSummaryView extends StatelessWidget {
  final SessionSummary summary;
  final void Function(SetEntry set, String name, int index)? onEdit;
  final void Function(SetEntry set)? onReview;
  final List<ExerciseComparison>? comparisons;
  final bool comparisonLoading;
  final String? comparisonError;
  final VoidCallback? onComparisonRetry;

  const SessionSummaryView({
    super.key,
    required this.summary,
    this.onEdit,
    this.onReview,
    this.comparisons,
    this.comparisonLoading = false,
    this.comparisonError,
    this.onComparisonRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      // stretch 而不是默认的 center：三块统计靠 WrapAlignment.spaceBetween
      // 撑满整行，文本要整行左对齐 —— 松约束下 Wrap 会缩到内容宽，
      // 三块会挤在左边，与搬家前的观感不一样
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 三块统计用 **Wrap** 而不是 Row。
        //
        // 系统字号放大到 2 倍时，三个数字并排会挤出屏幕（实测 360×640
        // 下 `RenderFlex overflowed by 156 pixels on the right`）。
        // Wrap 在这一档会自动折成两行 —— **数字宁可换行，也不能被切掉**：
        // 总容量正是要求用户拿笔手工核对的那个数。
        // 正常字号下三块正好一行，观感与 Row + spaceBetween 一致。
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: AppSpacing.lg,
          children: [
            StatBlock(
              label: '时长',
              value: _minutes(summary.durationSeconds),
              unit: '分',
            ),
            StatBlock(label: '总组数', value: '${summary.totalSets}', unit: '组'),
            StatBlock(
              label: '总容量',
              value: summary.volumeLoad.round().toString(),
              unit: 'kg',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // 规格附录的口径要求：容量必须写明它是「重量 × 次数」，
          // 且**不能写成「个人最好」** —— 容量是训练量，不是力量成绩
          '总容量（重量 × 次数）',
          style: TextStyle(fontSize: AppFontSize.label, color: c.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xl),

        Text(
          '组间休息回顾（粗略参考）',
          style: TextStyle(
            fontSize: AppFontSize.h2,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        for (final s in summary.exercises) _exerciseCard(context, s),
        if (summary.session.finishedAt != null)
          SessionComparisonView(
            comparisons: comparisons,
            loading: comparisonLoading,
            error: comparisonError,
            onRetry: onComparisonRetry,
          ),
      ],
    );
  }

  String _minutes(int seconds) => (seconds / 60).round().toString();

  Widget _exerciseCard(BuildContext context, ExerciseSummary s) {
    final c = appColors(context);
    final reps = s.sets.map((e) => e.reps).toList();
    final rests = s.sets.map((e) => e.restSeconds).toList();
    final hasSegments = s.sets.any((s) => s.detail?.isRestPause == true);
    final feedback = hasSegments ? null : buildRestFeedback(reps, rests);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.exerciseName,
              style: TextStyle(
                fontSize: AppFontSize.title,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // ⭐ 原始次数数组**必须原样显示** —— 只给结论不给原始数字，
            // 用户无法核对，也不会相信
            Text(
              s.sets
                  .map(
                    (set) => [
                      set.reps,
                      ...?set.detail?.continuations.map((s) => s.reps),
                    ].join('+'),
                  )
                  .join(' / '),
              style: TextStyle(
                fontSize: AppFontSize.title,
                color: c.textPrimary,
                fontFeatures: tabularNums,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (index, set) in s.sets.indexed) ...[
              InkWell(
                onTap: onEdit == null
                    ? null
                    : () => onEdit!(set, s.exerciseName, index),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: onEdit == null ? 0 : 10,
                  ),
                  child: Text(
                    '第 ${index + 1} 组 · ${set.equipmentWeight.label} × ${set.reps}${set.detail?.effort == null ? '' : ' @ ${set.detail!.effort!.label}'}${set.detail?.continuations.isNotEmpty == true ? ' + ${set.detail!.segmentLabel}' : ''}${set.detail?.endedEarly == true ? ' · 提前结束' : ''}${set.detail?.role == 'warmup' ? ' · 热身' : ''}${onEdit == null ? '' : ' · 编辑'}${set.detail?.target == null ? '' : '\n原目标：${set.detail!.target!.label}'}',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              if (onReview != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => onReview!(set),
                    icon: const Icon(Icons.video_library_outlined, size: 18),
                    label: Text('第 ${index + 1} 组视频复盘'),
                  ),
                ),
            ],
            if (feedback != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                feedback.message,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: _kindColor(c, feedback.kind),
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              // 组数 < 3 时明确沉默，不硬给建议
              Text(
                hasSegments ? '分段记录按各段分别计算容量，停顿不计为连续次数。' : '组数不足 3 组，暂不判断',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: c.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _kindColor(AppColors c, RestFeedbackKind kind) => switch (kind) {
    // 界面按 kind 上色，**不解析 message** —— 文案改了类型还在
    RestFeedbackKind.positive => c.success,
    RestFeedbackKind.addWeight => c.accent,
    _ => c.textSecondary,
  };
}
