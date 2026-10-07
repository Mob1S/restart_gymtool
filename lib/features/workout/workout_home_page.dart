import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/format.dart';
import '../../domain/session_label.dart';
import '../../domain/types.dart';
import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/primary_button.dart';
import 'conflict_dialog.dart';

/// 训练首页。它要回答两个问题：
/// 1. 有没有没练完的（「继续 今天 15:20 的训练 · 深蹲 等 3 个动作 · 已记 12 组」）
/// 2. 否则就开一场新的
class WorkoutHomePage extends StatefulWidget {
  const WorkoutHomePage({super.key});

  @override
  State<WorkoutHomePage> createState() => _WorkoutHomePageState();
}

class _WorkoutHomePageState extends State<WorkoutHomePage> {
  WorkoutSession? _active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  /// 探一次库里有没有进行中的训练。
  ///
  /// **必须在挂载后再探** —— 旧项目修过一个竞态：主页刚挂载、
  /// resume 还没跑完时用户点了「开始新训练」。
  Future<void> _probe() async {
    final c = context.read<ActiveSessionController>();
    await c.resume();
    if (!mounted) return;
    setState(() => _active = c.session);
  }

  Future<void> _startNew() async {
    final c = context.read<ActiveSessionController>();

    // 先刷新一次 _active，避免竞态
    await c.resume();
    if (!mounted) return;
    setState(() => _active = c.session);

    if (_active != null) {
      final choice = await showConflictDialog(
        context,
        description: _describe(c),
      );
      if (!mounted) return;

      switch (choice) {
        case ConflictChoice.resume:
          context.push('/session/${_active!.id}');
          return;
        case ConflictChoice.endAndStartNew:
          await c.endWorkout();
          break;
        case ConflictChoice.cancel:
        case null:
          return;
      }
    }

    final result = await c.startNew();
    if (!mounted) return;
    if (result == StartResult.started) {
      context.push('/session/${c.session!.id}');
    }
  }

  /// 「深蹲 等 3 个动作 · 已记 12 组」。
  ///
  /// 主页那张「继续…的训练」卡片与冲突弹窗**共用它** —— 抽出来不是为了省几行
  /// 代码，而是为了让「这说的是哪一场」在**这个页面里**只有一个答案。
  /// 两处各写一遍、改一处忘一处时，用户会看到两句互相矛盾的话，
  /// 而这个按钮存在的全部意义就是让他确认「是不是我刚才那场」。
  ///
  /// 真正的「唯一来源」是 `domain/session_label.dart` 的 `describeExercises`
  /// —— 它保证的是**跨页面**一致（总结页、历史详情页都会用它）。
  /// 这个私有包装只管本页的两处调用点。
  ///
  /// （计划初版写的是 `_describe(ActiveSessionController c, WorkoutSession s)`，
  /// 但 `s` 从未被用过，且 `build()` 当时是**内联**调用而没走这个函数 ——
  /// 于是注释里「共用同一个函数」那句在代码里并不成立。已改成名副其实。）
  String _describe(ActiveSessionController c) =>
      describeExercises(c.exercises.map((e) => e.progress).toList());

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActiveSessionController>();
    final sc = appColors(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('训练', style: TextStyle(
            fontSize: AppFontSize.h1,
            fontWeight: FontWeight.w700,
            color: sc.textPrimary,
          )),
          const SizedBox(height: AppSpacing.xl),

          if (c.session != null)
            AppCard(
              onTap: () => context.push('/session/${c.session!.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('继续 ${formatDateTime(c.session!.startedAt)} 的训练',
                      style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w600,
                        color: sc.accent,
                      )),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _describe(c),
                    style: TextStyle(
                        fontSize: AppFontSize.caption, color: sc.textSecondary),
                  ),
                ],
              ),
            ),

          if (c.session != null) const SizedBox(height: AppSpacing.lg),

          PrimaryButton(
            label: c.session != null ? '开始新训练' : '开始训练',
            icon: Icons.play_arrow_rounded,
            onPressed: _startNew,
          ),
        ],
      ),
    );
  }
}
