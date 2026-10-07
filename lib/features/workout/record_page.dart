import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/types.dart';
import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/primary_button.dart';
import 'drag_number.dart';
import 'exercise_picker.dart';
import 'exercise_strip.dart';
import 'number_stepper.dart';
import 'rest_view.dart';

/// 记录页。**屏幕上只呈现当前这一组** —— 拇指永远停在同一个位置，
/// 不需要瞄准（规格 §6.1 的方案 B）。
///
/// 为什么不是全览列表：点击目标小、单手够不到顶部、改数值还要跳转。
class RecordPage extends StatefulWidget {
  final String sessionId;
  const RecordPage({super.key, required this.sessionId});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  /// 用户此刻在编辑的数值。与库里那条占位组的值分开保存 ——
  /// 拖动过程中不该每一帧都写库，**只有点「完成这组」才落盘**。
  double? _weight;
  int? _reps;

  @override
  void initState() {
    super.initState();
    // 记录全程屏幕常亮 —— 组间放下手机时不该息屏
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = context.read<ActiveSessionController>();
      await c.resume();
      _syncFromPending(c);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  /// 把编辑值同步成当前动作那条未完成占位组的值。
  ///
  /// 只在「切换动作」或「刚完成一组」时调用 —— 用户正在拖数字时不能覆盖他。
  void _syncFromPending(ActiveSessionController c) {
    if (!mounted) return;
    final pending = _pendingOf(c);
    if (pending == null) {
      setState(() {
        _weight = null;
        _reps = null;
      });
      return;
    }
    setState(() {
      _weight = pending.weight;
      _reps = pending.reps;
    });
  }

  /// 当前动作下那条**未完成的占位组** —— 界面靠它确定「现在该记哪一组」。
  ///
  /// 它不存在时 [ActiveSessionController.completeCurrentSet] 会静默 return，
  /// 所以这里为 null 就意味着「完成这组」不该可点。
  SetEntry? _pendingOf(ActiveSessionController c) {
    if (c.currentIndex < 0 || c.currentIndex >= c.exercises.length) return null;
    return _firstOrNull(
      c.exercises[c.currentIndex].sets.where((s) => !s.isCompleted),
    );
  }

  Future<void> _complete(ActiveSessionController c) async {
    final weight = _weight;
    final reps = _reps;
    if (weight == null || reps == null) return;

    // 一次轻微震动，**让用户不用盯着屏幕确认**（规格 §6.1）
    await HapticFeedback.lightImpact();

    await c.completeCurrentSet(weight, reps);
    _syncFromPending(c);
  }

  Future<void> _beginNextSet(ActiveSessionController c) async {
    await c.beginNextSet();
    _syncFromPending(c);
  }

  Future<void> _addExercise(ActiveSessionController c) async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    await c.addExercise(picked.id);
    _syncFromPending(c);
  }

  Future<void> _endWorkout(ActiveSessionController c) async {
    final id = await c.endWorkout();
    if (!mounted) return;
    if (id != null) context.go('/summary/$id');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActiveSessionController>();
    final sc = appColors(context);

    final session = c.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('记录')),
        body: const EmptyState(message: '这场训练不在了，可能已被结束'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: sc.background,
        title: Text(session.name ?? '训练'),
        actions: [
          TextButton(
            onPressed: () => _endWorkout(c),
            child: const Text('结束训练'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 动作条：换动作不必退出记录界面 ──
            ExerciseStrip(
              exercises: c.exercises,
              currentIndex: c.currentIndex,
              onSelect: (i) {
                c.setCurrentIndex(i);
                _syncFromPending(c);
              },
              onAdd: () => _addExercise(c),
            ),

            Expanded(
              child: c.exercises.isEmpty
                  // 空训练**不是死路** —— 旧项目在这里踩过坑：
                  // 只写一句「这次训练还没有动作」，没有任何添加入口
                  ? EmptyState(
                      message: '这次训练还没有动作',
                      action: PrimaryButton(
                        label: '添加动作',
                        icon: Icons.add,
                        onPressed: () => _addExercise(c),
                      ),
                    )
                  : _body(c, sc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ActiveSessionController c, AppColors sc) {
    final active = c.exercises[c.currentIndex];
    final total = active.sets.length;
    final completed = active.sets.where((s) => s.isCompleted).length;
    final resting = _firstOrNull(
      active.sets.where((s) => s.isCompleted && s.restStartedAt != null),
    );

    // ── 正在休息 ──
    if (resting != null) {
      return RestView(
        restStartedAt: resting.restStartedAt!,
        nextSetNumber: completed + 1,
        onBeginNextSet: () => _beginNextSet(c),
      );
    }

    final pending = _pendingOf(c);
    final weight = _weight ?? pending?.weight ?? 20;
    final reps = _reps ?? pending?.reps ?? 8;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),

        Text(
          active.exerciseName,
          style: TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w600,
            color: sc.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // 「第 N / M 组」——旧项目这里踩过「组数只是右上角小灰字，不显眼」，
        // 所以它现在是动作名正下方的一等信息
        Text(
          '第 ${completed + 1} / $total 组',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: sc.textSecondary,
            fontFeatures: tabularNums,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
        _lastPerformanceLine(active, sc),

        const Spacer(),

        DragNumber(
          value: weight,
          onChanged: (v) => setState(() => _weight = v),
        ),

        const SizedBox(height: AppSpacing.xl),
        NumberStepper(
          value: weight,
          onChanged: (v) => setState(() => _weight = v),
        ),

        const SizedBox(height: AppSpacing.lg),
        _repsRow(reps, sc),

        const Spacer(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: PrimaryButton(
            label: '✓ 完成这组',
            // 没有待完成的组时置灰 —— 那正是「点了没反应」的假死状态
            onPressed: pending == null ? null : () => _complete(c),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// 「本场上一组 40 kg × 8」。
  ///
  /// 显示的是**本场**刚做完的那一组，用来避免「刚才那组到底加了多少」的犹豫。
  /// 还没记过任何一组时不占位（返回空盒子）。
  ///
  /// （计划原文的注释写的是「从上一次训练查出来的」，与它下面这几行代码
  /// 不符 —— 代码读的是 `active.sets`，也就是本场。**只改了注释**，
  /// 行为与文案「本场上一组」一致。）
  Widget _lastPerformanceLine(ActiveExercise active, AppColors sc) {
    final done = active.sets.where((s) => s.isCompleted).toList();
    if (done.isEmpty) return const SizedBox.shrink();
    final last = done.last;
    return Text(
      '本场上一组 ${_fmt(last.weight)} kg × ${last.reps}',
      style: TextStyle(
        fontSize: AppFontSize.caption,
        color: sc.textTertiary,
        fontFeatures: tabularNums,
      ),
    );
  }

  Widget _repsRow(int reps, AppColors sc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '次数',
          style: TextStyle(fontSize: AppFontSize.label, color: sc.textTertiary),
        ),
        const SizedBox(width: AppSpacing.md),
        NumberStepper(
          value: reps.toDouble(),
          step: 1,
          max: 100,
          onChanged: (v) => setState(() => _reps = v.round()),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 48,
          child: Text(
            '$reps',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.h2,
              fontWeight: FontWeight.w600,
              color: sc.textPrimary,
              fontFeatures: tabularNums,
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// `Iterable.firstOrNull` —— 取第一个元素，没有元素时返回 null。
///
/// Dart 的 `Iterable` **没有内置它**（那是 `package:collection` 的扩展）。
/// 本工程里 `collection` 只是传递依赖，直接 import 会触发
/// `depend_on_referenced_packages`，所以本页自带一个私有实现
/// （与 `ActiveSessionController` 里那个同源，但那是它的私有函数，
/// 界面层拿不到 —— 不为此把它变成 public）。
T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}
