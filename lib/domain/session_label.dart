/// `describeExercises` 需要的**最小**形状：只需要动作名和每组是否完成。
///
/// 参数写成结构化的最小形状（而不是依赖 `state/` 的 `ActiveExercise`），
/// 是为了让 domain 不反过来依赖编排层 —— `ActiveExercise` 天然满足这个形状。
class ExerciseProgress {
  final String exerciseName;
  final List<SetProgress> sets;

  const ExerciseProgress({required this.exerciseName, required this.sets});
}

class SetProgress {
  final bool isCompleted;

  const SetProgress({required this.isCompleted});
}

/// 描述一场进行中的训练练到哪了：`深蹲 等 3 个动作 · 已记 12 组`。
///
/// 主页按钮和「上一场训练还没结束」的询问弹窗共用它。抽出来不是为了省几行
/// 代码，而是为了让「这说的是哪一场」只有一个答案 —— 两处各写一遍，
/// 改一处忘一处时用户会看到两句互相矛盾的话，而这个按钮存在的全部意义
/// 就是让他确认「是不是我刚才那场」。
String describeExercises(List<ExerciseProgress> exercises) {
  if (exercises.isEmpty) return '还没有动作';

  var completed = 0;
  for (final e in exercises) {
    for (final s in e.sets) {
      if (s.isCompleted) completed++;
    }
  }

  final first = exercises.first.exerciseName;
  final what =
      exercises.length == 1 ? first : '$first 等 ${exercises.length} 个动作';
  return '$what · 已记 $completed 组';
}
