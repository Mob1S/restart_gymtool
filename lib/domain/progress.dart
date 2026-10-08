import 'metrics.dart';
import 'types.dart';

/// 一条「已完成组」的事实。仓储查出来的就是它，之后全在 Dart 里算。
///
/// 只带折算成点要用的字段：容量与 e1RM 的口径都只吃重量和次数，
/// 组 id / 休息时长那是记录界面的事，这里没有读者。
class SetFact {
  final String exerciseId;
  final String sessionId;

  /// 该场的开始时间。每条事实都带着它，分组排序就不必再回查 session 表
  final int sessionStartedAt;

  /// 重量（kg）
  final double weight;
  final int reps;

  const SetFact({
    required this.exerciseId,
    required this.sessionId,
    required this.sessionStartedAt,
    required this.weight,
    required this.reps,
  });
}

/// 一场训练里的一个点。**一次训练 = 一个点。**
///
/// 按组画点会一天之内来回锯齿（组间掉次数、组间调重量都上下跳），
/// 而进步页回答的是「比上一次强了吗」—— 所以先把一场里的组聚成一个点。
class SessionPoint {
  final String exerciseId;
  final String sessionId;
  final int startedAt;

  /// 这一场最重的一组
  final double topWeight;

  /// [topWeight] 那一组的次数；最大重量并列时取次数多的那组 ——
  /// 同样重、做得多，就是那场里更强的一组
  final int topWeightReps;

  /// 这一场所有可换算组里最好的 e1RM；一组都换算不了时为 null。
  ///
  /// **不是「最重那组的 e1RM」**：`60×10` 的 78.51 高于 `70×3` 的 76.42，
  /// 尽管后者更重（规格 §2.1 第 3 条）。null 不能当 0 —— 0 读起来是
  /// 「练得很差」，事实是「这一场没有适合换算的组」。
  final double? bestE1rm;

  /// [bestE1rm] 来自哪一组 —— 界面要把这组原样写出来（「来自 60 kg × 10」）。
  /// [bestE1rm] 为 null 时一并 null
  final double? e1rmWeight;
  final int? e1rmReps;

  /// 这一场的 Σ(重量 × 次数)
  final double volumeLoad;

  const SessionPoint({
    required this.exerciseId,
    required this.sessionId,
    required this.startedAt,
    required this.topWeight,
    required this.topWeightReps,
    required this.bestE1rm,
    required this.e1rmWeight,
    required this.e1rmReps,
    required this.volumeLoad,
  });
}

/// 把散的组聚成「每场一个点」，按 `startedAt` 升序、同一时刻用 `sessionId` 兜底。
///
/// **输入顺序不得依赖**：排序规则属于本函数。若沿用调用方给的顺序，同一份数据
/// 换一个调用方（或 SQL 少了一个 ORDER BY）就会换一种点序，而曲线是给人看趋势的
/// —— 点序一变，「在进步还是退步」的结论也会变。
///
/// 分组键是 **`(exerciseId, sessionId)` 两个字段，不是只有 `sessionId`**。
/// 只用 `sessionId` 会让「忘了先按动作过滤」的调用方**静默**拿到一场里所有动作
/// 混在一起的组 —— 数字是错的，但不报错、不崩，只是曲线悄悄变成一条没有意义的线。
/// 加上 `exerciseId` 之后这条错路走不通：传进来多少动作就长出多少点，
/// 每个点都只属于一个动作，调用方事后按 [SessionPoint.exerciseId] 过滤也来得及。
/// 多一个字段换掉一种「静默算错」，值得。
List<SessionPoint> buildSessionPoints(List<SetFact> facts) {
  // 键用 record —— 它按字段做相等与哈希，不必手工拼字符串分隔符
  final grouped = <(String, String), List<SetFact>>{};
  for (final fact in facts) {
    (grouped[(fact.exerciseId, fact.sessionId)] ??= []).add(fact);
  }

  return [for (final sets in grouped.values) _sessionPoint(sets)]
    ..sort(_byStartedAt);
}

/// 同一时刻开的两场按 `sessionId` 兜底，再并列按 `exerciseId`。
/// 兜底只为确定性，不为语义：谁先谁后都说得过去，
/// 但**换一次输入顺序就换一次前后**不行。
int _byStartedAt(SessionPoint a, SessionPoint b) {
  final byTime = a.startedAt.compareTo(b.startedAt);
  if (byTime != 0) return byTime;
  final bySession = a.sessionId.compareTo(b.sessionId);
  return bySession != 0 ? bySession : a.exerciseId.compareTo(b.exerciseId);
}

/// 把同一个动作在同一场里的组聚成一个点。
/// `sets` 非空 —— 分组时由事实长出，空场长不出来。
SessionPoint _sessionPoint(List<SetFact> sets) {
  var topWeight = sets.first.weight;
  var topWeightReps = sets.first.reps;
  double? bestE1rm;
  double? e1rmWeight;
  int? e1rmReps;

  for (final s in sets) {
    if (s.weight > topWeight ||
        (s.weight == topWeight && s.reps > topWeightReps)) {
      topWeight = s.weight;
      topWeightReps = s.reps;
    }

    final e1rm = estimateOneRepMax(s.weight, s.reps);
    if (e1rm == null) continue;
    // 并列时取更重的一组：e1RM 恰好相等并非不可能，而「第一次遇到的」
    // 依赖输入顺序 —— 本函数刚承诺过不依赖它
    final better =
        bestE1rm == null ||
        e1rm > bestE1rm ||
        (e1rm == bestE1rm && s.weight > e1rmWeight!);
    if (better) {
      bestE1rm = e1rm;
      e1rmWeight = s.weight;
      e1rmReps = s.reps;
    }
  }

  // 容量一律走 metrics.totalVolumeLoad —— 口径只此一份实现。这里再累加一遍，
  // 总结页与进步页就会各算各的，分叉时没人发现。事实按定义都是已完成的组
  // （仓储过滤了 is_completed = 1），所以 SetLike 的 isCompleted 恒为 true。
  final volumeLoad = totalVolumeLoad([
    for (final s in sets)
      SetLike(weight: s.weight, reps: s.reps, isCompleted: true),
  ]);

  return SessionPoint(
    exerciseId: sets.first.exerciseId,
    sessionId: sets.first.sessionId,
    startedAt: sets.first.sessionStartedAt,
    topWeight: topWeight,
    topWeightReps: topWeightReps,
    bestE1rm: bestE1rm,
    e1rmWeight: e1rmWeight,
    e1rmReps: e1rmReps,
    volumeLoad: volumeLoad,
  );
}
