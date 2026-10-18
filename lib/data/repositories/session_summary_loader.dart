import '../../domain/metrics.dart';
import '../../domain/session_summary.dart';
import '../../domain/types.dart';
import '../db/sql_executor.dart';
import 'exercise_repo.dart';
import 'session_repo.dart';
import 'set_repo.dart';

/// 装载一场训练的总结数字。**总结页与历史详情页共用这一处计算。**
///
/// 它是 `SummaryPage._load()` + `build` 那段口径的原样搬家：只留已完成的组、
/// 一个动作都没做的组不上卡片、`finishedAt` 为空（还没结束）按「现在」算时长。
/// 两个屏幕各算各的话，同一场训练会量出两个容量，**而且不会有任何测试变红** ——
/// 数字悄悄写歪正是这一层最难发现的一类错。`test/widget/smoke_test.dart` 里那条
/// 总结页用例逐字断言着这些数字，改这里的任何一条口径之前先看它。
///
/// `sessionId` 不存在时返回 null（不抛）—— 界面据此显示「这场训练不存在」。
///
/// 每个动作各查一次组：**这里的 N 是「这一场的动作数」，不是「训练的场数」**，
/// 一场只有几个动作，与总结页今天的行为一致。被点名禁掉的 N+1 是进步页
/// 「按动作逐个查历史」（见 `progress_repo.dart`），不是这里。
Future<SessionSummary?> loadSessionSummary(
  SqlExecutor exec,
  String sessionId,
) async {
  final session = await getSession(exec, sessionId);
  if (session == null) return null;

  final exercises = <ExerciseSummary>[];
  for (final se in await listSessionExercises(exec, sessionId)) {
    // `listSets` 把占位组也带回来（记录界面靠它找「当前这组」），但占位组
    // 不是训练记录 —— 组数与容量一个字都不能算进去
    final done = (await listSets(exec, se.id)).where((s) => s.isCompleted);
    if (done.isEmpty) continue; // 空动作不上总结页
    final exercise = await getExercise(exec, se.exerciseId);
    exercises.add(
      ExerciseSummary(
        // 动作取不到时写「未知动作」，不崩 —— 与总结页一字不差
        exerciseName: exercise?.name ?? '未知动作',
        sets: done.toList(),
      ),
    );
  }

  final allSets = [for (final e in exercises) ...e.sets];

  // 训练还没结束（`finishedAt` 为空）时按「现在」算 —— 进行中的训练也能装载，
  // 时长是一块还会长的数。口径走 metrics.sessionDurationSeconds ——
  // 与历史行（SessionSummaryRow）同一份实现，不在这里重算。
  final finishedAt =
      session.finishedAt ?? DateTime.now().millisecondsSinceEpoch;

  return SessionSummary(
    session: session,
    exercises: exercises,
    durationSeconds: sessionDurationSeconds(session.startedAt, finishedAt),
    totalSets: allSets.length,
    // 容量一律走 metrics.totalVolumeLoad —— 口径只此一份实现，不在这里重算。
    // 组已在上面滤成已完成，所以 isCompleted 恒为 true。
    volumeLoad: totalVolumeLoad([
      for (final s in allSets) ...[
        SetLike(weight: s.weight, reps: s.reps, isCompleted: true),
        for (final segment in s.detail?.continuations ?? [])
          SetLike(
            weight: segment.reading.kilograms,
            reps: segment.reps,
            isCompleted: true,
          ),
      ],
    ]),
  );
}
