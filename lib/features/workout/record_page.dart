import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/types.dart';
import '../../domain/training_prescription.dart';
import 'effort_input.dart';
import 'prescription_panel.dart';
import '../../domain/weight_value.dart';
import '../../domain/workout_edit.dart';
import '../../state/exercise_preferences_controller.dart';
import 'completed_sets_sheet.dart';
import 'exercise_settings_sheet.dart';
import 'next_set_weight.dart';
import 'replace_exercise_sheet.dart';
import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/fill_or_scroll.dart';
import '../../ui/widgets/primary_button.dart';
import 'workout_value_input.dart';
import 'exercise_picker.dart';
import 'exercise_strip.dart';
import 'rest_view.dart';
import 'remove_exercise_dialog.dart';
import '../history/delete_session_dialog.dart';
import '../../state/record_management_controller.dart';

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
  EquipmentWeight? _weight;
  int? _reps;
  Effort? _effort;
  bool _ready = false;
  bool _gestureActive = false;
  bool _settingsOpen = false;

  bool get _interactionLocked => _gestureActive || _settingsOpen;

  @override
  void initState() {
    super.initState();
    // 记录全程屏幕常亮 —— 组间放下手机时不该息屏
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = context.read<ActiveSessionController>();
      await c.resume();
      if (mounted) {
        final preferences = context.read<ExercisePreferencesController?>();
        await preferences?.load(
          c.exercises.map((e) => e.sessionExercise.exerciseId),
        );
      }
      _syncFromPending(c);
      if (mounted) setState(() => _ready = true);
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
      _weight = pending.equipmentWeight;
      _reps = pending.pendingReps;
      _effort = null;
    });
  }

  /// 当前动作下那条**未完成的占位组** —— 界面靠它确定「现在该记哪一组」。
  ///
  /// 它不存在时 [ActiveSessionController.completeCurrentSet] 会静默 return，
  /// 所以这里为 null 就意味着「完成这组」不该可点。
  SetEntry? _pendingOf(ActiveSessionController c) {
    final active = c.currentExercise;
    if (active == null) return null;
    return _firstOrNull(active.sets.where((s) => !s.isCompleted));
  }

  Future<void> _complete(ActiveSessionController c) async {
    final weight = _weight;
    final reps = _reps;
    if (weight == null || reps == null) return;

    // 一次轻微震动，**让用户不用盯着屏幕确认**（规格 §6.1）
    if (c.writing || _interactionLocked) return;
    final originalPending = _pendingOf(c)?.id;
    final result = await c.completeCurrentReading(
      weight,
      reps,
      effort: _effort,
    );
    if (c.writeMessage == null &&
        c.currentExercise?.sets.any((s) => s.restStartedAt != null) == true) {
      await HapticFeedback.lightImpact();
    }
    if (result == WorkoutWriteResult.saved ||
        result == WorkoutWriteResult.savedNeedsReload ||
        _pendingOf(c)?.id != originalPending) {
      _syncFromPending(c);
    }
  }

  Future<void> _beginNextSet(ActiveSessionController c) async {
    if (_interactionLocked) return;
    await c.beginNextSet();
    _syncFromPending(c);
  }

  Future<void> _addExercise(ActiveSessionController c) async {
    if (_interactionLocked) return;
    final flushed = await c.flushPendingWeight();
    if (!mounted ||
        (flushed != WorkoutWriteResult.saved &&
            flushed != WorkoutWriteResult.unchanged)) {
      return;
    }
    final picked = await showExerciseMultiPicker(context);
    if (picked == null || !mounted) return;
    await c.addExercises(picked.map((e) => e.id).toList());
    if (mounted) {
      await context.read<ExercisePreferencesController?>()?.load(
        picked.map((e) => e.id),
      );
    }
    _syncFromPending(c);
  }

  Future<void> _endWorkout(ActiveSessionController c) async {
    if (_interactionLocked) return;
    final id = await c.endWorkout();
    if (!mounted) return;
    if (id != null) context.go('/summary/$id');
  }

  Future<void> _remove(ActiveSessionController c) async {
    if (_interactionLocked) return;
    final id = c.currentSessionExerciseId;
    if (id == null) return;
    try {
      final preview = await c.previewExerciseRemoval(id);
      if (preview == null || !mounted) return;
      final choice = await showRemoveExerciseDialog(context, preview);
      if (choice == null) return;
      await c.removeExercise(preview, choice);
      _syncFromPending(c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openSettings(ActiveSessionController c) async {
    if (_interactionLocked || c.writing) return;
    final prefs = context.read<ExercisePreferencesController?>();
    final active = c.currentExercise;
    final pending = _pendingOf(c);
    if (prefs == null || active == null) return;
    final resting = active.sets.any((set) => set.restStartedAt != null);
    final reading = pending == null
        ? null
        : c.stagedReading(pending.id) ??
              (resting
                  ? pending.equipmentWeight
                  : _weight ?? pending.equipmentWeight);
    final reps = _reps;
    final effort = _effort;
    setState(() => _settingsOpen = true);
    try {
      final flushed = await c.flushPendingWeight();
      if (!mounted ||
          (flushed != WorkoutWriteResult.saved &&
              flushed != WorkoutWriteResult.unchanged)) {
        return;
      }
      final result = await showExerciseSettingsSheet(
        context,
        prefs,
        active.sessionExercise.exerciseId,
        active.exerciseName,
        sessionId: pending == null ? null : widget.sessionId,
        pendingSetId: pending?.id,
        pendingReading: reading,
      );
      if (result == WorkoutWriteResult.saved && mounted) {
        await c.resume();
        _syncFromPending(c);
        if (mounted) {
          setState(() {
            _reps = reps;
            _effort = effort;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _settingsOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActiveSessionController>();
    final sc = appColors(context);

    final session = c.session;
    if (session == null || session.id != widget.sessionId) {
      return Scaffold(
        appBar: AppBar(title: const Text('记录')),
        body: const EmptyState(message: '这场训练不在了，可能已被结束'),
      );
    }

    return PopScope(
      canPop: !_interactionLocked && !c.hasPendingWeight && !c.writing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || c.writing || _interactionLocked) return;
        final result = await c.flushPendingWeight();
        if (mounted &&
            (result == WorkoutWriteResult.saved ||
                result == WorkoutWriteResult.unchanged)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: sc.background,
          title: Text(session.name ?? '训练'),
          actions: [
            if (c.recordingExercises.length > 1)
              IconButton(
                tooltip: '移除当前动作',
                onPressed:
                    !_ready || _interactionLocked || (c.loading || c.writing)
                    ? null
                    : () => _remove(c),
                icon: const Icon(Icons.playlist_remove),
              ),
            if (context.watch<RecordManagementController?>() != null)
              IconButton(
                tooltip: '删除这场训练',
                onPressed:
                    !_ready ||
                        _interactionLocked ||
                        c.loading ||
                        context.watch<RecordManagementController?>()?.busy ==
                            true
                    ? null
                    : () async {
                        if (await showDeleteSessionDialog(
                              context,
                              widget.sessionId,
                            ) &&
                            context.mounted) {
                          context.go('/');
                        }
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            TextButton(
              onPressed:
                  !_ready || _interactionLocked || (c.loading || c.writing)
                  ? null
                  : () => _endWorkout(c),
              child: const Text('结束训练'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── 动作条：换动作不必退出记录界面 ──
              ExerciseStrip(
                exercises: c.recordingExercises,
                currentIndex: c.currentIndex,
                onSelect: (i) async {
                  if (!_ready ||
                      _interactionLocked ||
                      c.loading ||
                      (c.writing && !c.savingWeight)) {
                    return;
                  }
                  await c.setCurrentIndex(i);
                  _syncFromPending(c);
                },
                onAdd: () {
                  if (_ready &&
                      !_interactionLocked &&
                      !c.loading &&
                      !c.writing) {
                    _addExercise(c);
                  }
                },
              ),

              if (c.currentExercise != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _interactionLocked || c.writing
                          ? null
                          : () => showCompletedSetsSheet(
                              context,
                              c,
                              context.read<ExercisePreferencesController?>(),
                            ),
                      key: const ValueKey('completed-sets'),
                      child: Text(
                        '本场已记 ${c.exercises.expand((e) => e.sets).where((s) => s.isCompleted).length} 组',
                      ),
                    ),
                    TextButton(
                      onPressed: _interactionLocked || c.writing
                          ? null
                          : () => _openSettings(c),
                      child: const Text('动作设置'),
                    ),
                    TextButton(
                      onPressed: _interactionLocked || c.writing
                          ? null
                          : () async {
                              await showReplaceExerciseSheet(context, c);
                              if (context.mounted) {
                                await context
                                    .read<ExercisePreferencesController?>()
                                    ?.load(
                                      c.exercises.map(
                                        (e) => e.sessionExercise.exerciseId,
                                      ),
                                    );
                              }
                              _syncFromPending(c);
                            },
                      child: const Text('替换当前动作'),
                    ),
                  ],
                ),
              if (c.writeMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text(c.writeMessage!),
                      TextButton(
                        onPressed: _interactionLocked || c.writing
                            ? null
                            : () async {
                                await c.resume();
                                _syncFromPending(c);
                              },
                        child: const Text('重新载入'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !_ready || c.loading
                    ? const Center(child: CircularProgressIndicator())
                    : c.recordingExercises.isEmpty
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
      ),
    );
  }

  Widget _body(ActiveSessionController c, AppColors sc) {
    final active = c.currentExercise!;
    final prefs = context.watch<ExercisePreferencesController?>();
    final preference = prefs?.preferenceFor(active.sessionExercise.exerciseId);
    final pendingUnit =
        (_weight ?? _pendingOf(c)?.equipmentWeight)?.unit ??
        preference?.weightUnit ??
        WeightUnit.kg;
    final step = pendingUnit == WeightUnit.kg
        ? preference?.kgStep ?? DecimalReading.parse('2.5')
        : preference?.lbStep ?? DecimalReading.parse('5');
    final note = preference?.equipmentNote ?? '';
    final planned = active.prescription?.targets.length ?? 0;
    final total = planned > active.sets.length ? planned : active.sets.length;
    final completed = active.sets.where((s) => s.isCompleted).length;
    final resting = _firstOrNull(
      active.sets.where((s) => s.isCompleted && s.restStartedAt != null),
    );

    // ── 正在休息 ──
    if (resting != null) {
      return RestView(
        restStartedAt: resting.restStartedAt!,
        nextSetNumber: completed + 1,
        onBeginNextSet: _interactionLocked || (c.writing && !c.savingWeight)
            ? null
            : () => _beginNextSet(c),
        exerciseName: active.exerciseName,
        details: [
          EquipmentNote(note: note),
          if (_pendingOf(c) != null)
            NextSetWeight(
              key: ValueKey(_pendingOf(c)!.id),
              controller: c,
              pending: _pendingOf(c)!,
              step: step.asDouble,
              readingStep: step,
              showKgEquivalent: preference?.showKgEquivalent ?? false,
              onGestureActiveChanged: (active) {
                if (mounted) setState(() => _gestureActive = active);
              },
            ),
          Text('刚完成 ${resting.equipmentWeight.label} × ${resting.reps}'),
          TextButton(
            onPressed: _interactionLocked || c.writing
                ? null
                : () async {
                    try {
                      final preview = await c.previewUndo();
                      if (!mounted) return;
                      if (preview == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已开始后续组或休息已失效，无法撤销')),
                        );
                        return;
                      }
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('撤销刚才的完成？'),
                          content: const Text('返回刚才这一组，下一组准备值将清除'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('撤销完成'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await c.undoLastCompletion(preview);
                        _syncFromPending(c);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
            key: const ValueKey('undo-last-completion'),
            child: const Text('误点完成？撤销'),
          ),
        ],
      );
    }

    final pending = _pendingOf(c);
    final weight =
        _weight ?? pending?.equipmentWeight ?? EquipmentWeight.kg(20);
    final reps = _reps ?? pending?.pendingReps ?? 8;

    // 窄屏 / 横屏下这一列会比一屏高（320×480 实测溢出 59px，切掉的正好是
    // 底部那个「完成这组」）。装得下时布局与从前完全一致，见 FillOrScroll。
    return Column(
      children: [
        Expanded(
          child: FillOrScroll(
            child: Column(
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
                EquipmentNote(note: note),

                if (pending != null)
                  PrescriptionPanel(
                    key: ValueKey('target-${pending.id}'),
                    pending: pending,
                    snapshot: active.prescription,
                    enabled: !_interactionLocked && !c.writing,
                    onAdopt: (reference) async {
                      final result = await c.adoptReference(
                        pending.id,
                        reference,
                      );
                      if (mounted &&
                          (result == WorkoutWriteResult.saved ||
                              result == WorkoutWriteResult.savedNeedsReload)) {
                        final current = _pendingOf(c);
                        if (current?.id == pending.id) {
                          setState(() => _weight = current!.equipmentWeight);
                        }
                      }
                    },
                  ),
                const Spacer(),

                WorkoutValueInput(
                  key: ValueKey(
                    '${pending?.id}:${pending?.detail?.currentSegment ?? 0}',
                  ),
                  weight: weight,
                  reps: reps,
                  step: weight.unit == WeightUnit.kg
                      ? preference?.kgStep ?? DecimalReading.parse('2.5')
                      : preference?.lbStep ?? DecimalReading.parse('5'),
                  enabled: !c.writing && !_settingsOpen,
                  showKgEquivalent: preference?.showKgEquivalent ?? false,
                  onWeightChanged: (value) {
                    if (mounted) setState(() => _weight = value);
                  },
                  onRepsChanged: (value) {
                    if (mounted) setState(() => _reps = value);
                  },
                  onGestureActiveChanged: (active) {
                    if (mounted) setState(() => _gestureActive = active);
                  },
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _interactionLocked || c.writing
                          ? null
                          : () => _openSettings(c),
                      child: Text('幅度 ${step.text} ${weight.unit.name} ▾'),
                    ),
                    EffortInput(
                      value: _effort,
                      segment: pending?.detail?.isRestPause == true,
                      enabled: !_interactionLocked && !c.writing,
                      onChanged: (value) => setState(() => _effort = value),
                    ),
                  ],
                ),
                if (pending?.detail?.firstCompletedAt != null)
                  TextButton(
                    onPressed: _interactionLocked || c.writing
                        ? null
                        : () async {
                            await c.finishPartialGroup(pending!.id);
                            _syncFromPending(c);
                          },
                    child: const Text('结束本组，保留已做分段'),
                  ),

                const Spacer(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: PrimaryButton(
            label: pending?.detail?.intraRestStartedAt != null
                ? '开始第 ${pending!.detail!.currentSegment + 1} 段'
                : pending?.detail?.isRestPause == true
                ? '✓ 完成第 ${pending!.detail!.currentSegment + 1} 段'
                : '✓ 完成这组',
            // 没有待完成的组时置灰 —— 那正是「点了没反应」的假死状态
            onPressed: pending == null || _interactionLocked || c.writing
                ? null
                : () => pending.detail?.intraRestStartedAt != null
                      ? c.beginNextSegment(pending.id)
                      : _complete(c),
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
      '本场上一组 ${last.equipmentWeight.label} × ${last.reps}',
      style: TextStyle(
        fontSize: AppFontSize.caption,
        color: sc.textTertiary,
        fontFeatures: tabularNums,
      ),
    );
  }
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
