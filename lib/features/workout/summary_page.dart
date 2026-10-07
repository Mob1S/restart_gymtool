import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/session_repo.dart';
import '../../data/repositories/set_repo.dart';
import '../../domain/metrics.dart';
import '../../domain/rest_advice.dart';
import '../../domain/types.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/primary_button.dart';
import '../../ui/widgets/stat_block.dart';

/// 训练总结。
///
/// **按路由参数 id 从库里读，不依赖 controller** —— 这正是 [endWorkout]
/// 敢于「结束就立刻清内存」的前提：总结页不受内存被清空的影响。
class SummaryPage extends StatefulWidget {
  final String sessionId;
  const SummaryPage({super.key, required this.sessionId});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  WorkoutSession? _session;
  List<_ExerciseSummary> _summaries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final session = await getSession(exec, widget.sessionId);
    final ses = await listSessionExercises(exec, widget.sessionId);

    final summaries = <_ExerciseSummary>[];
    for (final se in ses) {
      final sets = await listSets(exec, se.id);
      final done = sets.where((s) => s.isCompleted).toList();
      if (done.isEmpty) continue; // 空动作不上总结页
      final ex = await getExercise(exec, se.exerciseId);
      summaries.add(_ExerciseSummary(
        name: ex?.name ?? '未知动作',
        sets: done,
      ));
    }

    if (!mounted) return;
    setState(() {
      _session = session;
      _summaries = summaries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: Text('这场训练不存在')));
    }

    final finishedAt = session.finishedAt ??
        DateTime.now().millisecondsSinceEpoch;
    final durationSeconds = ((finishedAt - session.startedAt) / 1000).round();

    final allSets = _summaries.expand((s) => s.sets).toList();
    final volume = totalVolumeLoad(
      allSets.map((s) => SetLike(weight: s.weight, reps: s.reps, isCompleted: true)).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练总结'),
        backgroundColor: c.background,
        // 总结页**没有返回键** —— 结束是不可逆的，这里只给一个出口
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatBlock(label: '时长', value: _minutes(durationSeconds), unit: '分'),
              StatBlock(label: '总组数', value: '${allSets.length}', unit: '组'),
              StatBlock(label: '总容量', value: volume.round().toString(), unit: 'kg'),
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

          Text('组间休息回顾（粗略参考）', style: TextStyle(
            fontSize: AppFontSize.h2,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          )),
          const SizedBox(height: AppSpacing.md),

          for (final s in _summaries) _exerciseCard(context, s),

          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: '完成',
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }

  String _minutes(int seconds) => (seconds / 60).round().toString();

  Widget _exerciseCard(BuildContext context, _ExerciseSummary s) {
    final c = appColors(context);
    final reps = s.sets.map((e) => e.reps).toList();
    final rests = s.sets.map((e) => e.restSeconds).toList();
    final feedback = buildRestFeedback(reps, rests);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name, style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            )),
            const SizedBox(height: AppSpacing.sm),
            // ⭐ 原始次数数组**必须原样显示** —— 只给结论不给原始数字，
            // 用户无法核对，也不会相信
            Text(reps.join(' / '), style: TextStyle(
              fontSize: AppFontSize.title,
              color: c.textPrimary,
              fontFeatures: tabularNums,
            )),
            if (feedback != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(feedback.message, style: TextStyle(
                fontSize: AppFontSize.caption,
                color: _kindColor(c, feedback.kind),
              )),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              // 组数 < 3 时明确沉默，不硬给建议
              Text('组数不足 3 组，暂不判断', style: TextStyle(
                fontSize: AppFontSize.caption, color: c.textTertiary,
              )),
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

class _ExerciseSummary {
  final String name;
  final List<SetEntry> sets;
  const _ExerciseSummary({required this.name, required this.sets});
}
