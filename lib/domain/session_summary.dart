import 'metrics.dart';
import 'types.dart';

/// 总结页上一个动作的卡片内容。
///
/// [sets] **只含已完成的组** —— 占位组（`is_completed = 0`）在装载时就滤掉了，
/// 这里拿到的是训练记录本身。顺序保持 `position` 升序（记录时的先后），
/// 界面要把它原样拼成 `8 / 8 / 8` 给人核对。
class ExerciseSummary {
  /// Stable identity; renamed or same-named exercises keep separate history.
  final String exerciseId;

  /// 动作名。取不到动作时是「未知动作」而不是 null —— 卡片总得有个标题，
  /// 而历史里引用着已被归档 / 删掉的动作是真实会发生的。
  final String exerciseName;

  final List<SetEntry> sets;

  const ExerciseSummary({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
  });
}

/// 一场训练的全部数字。
///
/// **总结页（刚练完）与历史详情页（翻旧账）共用这一份装载结果** ——
/// 两个屏幕各算各的，同一场训练迟早会量出两个容量，而且不会有任何测试变红。
/// 装载只有一处实现：`data/repositories/session_summary_loader.dart`。
class SessionSummary {
  final WorkoutSession session;

  /// 只含「至少做完一组」的动作，顺序即 `session_exercise.position` 升序。
  /// 一个动作都没做的场次这里是空的 —— 但 [session] 仍在，不是 null。
  final List<ExerciseSummary> exercises;

  /// 时长（秒），`((finishedAt - startedAt) / 1000).round()`。
  /// 训练还没结束时 `finishedAt` 取「现在」。
  final int durationSeconds;

  /// 已完成的组数（占位组不算）—— 总结页「总组数」那一块的数。
  final int totalSets;

  /// 总容量 Σ(重量 × 次数)，口径见 `domain/metrics.dart` 的 `totalVolumeLoad`。
  /// **这是训练量，不是力量成绩** —— 界面文案不许写成「个人最好」。
  final double volumeLoad;

  const SessionSummary({
    required this.session,
    required this.exercises,
    required this.durationSeconds,
    required this.totalSets,
    required this.volumeLoad,
  });
}

/// Recorded volume uses canonical kg and includes each performed segment once.
/// An incomplete parent is excluded, just as it is from the saved summary.
double recordedSetsVolume(Iterable<SetEntry> sets) => totalVolumeLoad([
  for (final set in sets)
    if (set.isCompleted) ...[
      SetLike(weight: set.weight, reps: set.reps, isCompleted: true),
      for (final segment in set.detail?.continuations ?? [])
        SetLike(
          weight: segment.reading.kilograms,
          reps: segment.reps,
          isCompleted: true,
        ),
    ],
]);
