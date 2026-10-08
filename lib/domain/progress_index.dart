import 'progress.dart';

/// 进步列表里迷你走势保留的点数。
///
/// 一行只有几十像素高，点再多就糊成一团；12 个点大约是每周两练的一个半月，
/// 够看出趋势又不至于把最近几次的变化压扁。
const int recentPointCount = 12;

/// 进步列表的一行：一个动作 + 它最近那些点。
///
/// 只管**练过**的动作 —— 名字由调用方拿 `exerciseId` 去动作库取。
/// 要在这里补上没练过的动作，纯逻辑层就得认识 `exercise` 表：
/// 多一个数据源，换不来一行更有用的信息。
class ExerciseProgressRow {
  final String exerciseId;

  /// 最近一次训练那一场的时间。列表按它倒序：最近练过的在最上面
  final int lastTrainedAt;

  /// **最近那一次**训练里最重的一组，不是历史最好成绩 ——
  /// 行上并排写着「最近 9/10 · 最重 60 kg」，两个数必须是同一天的。
  /// 换成历史最大值，屏幕上会出现「最近 9/10 · 最重 100 kg」：
  /// 日期与数字各说各话，比不显示还糟
  final double topWeight;
  final int topWeightReps;

  /// 最近 [recentPointCount] 个点，**按时间升序** —— 与
  /// `buildSessionPoints` 的输出同序，画线左旧右新，不必再翻一遍。
  ///
  /// 代价（明确接受）：`recent.last` 是最新那个点，而列表里新的行在上面，
  /// 两处方向相反，读代码时容易看错。
  final List<SessionPoint> recent;

  const ExerciseProgressRow({
    required this.exerciseId,
    required this.lastTrainedAt,
    required this.topWeight,
    required this.topWeightReps,
    required this.recent,
  });
}

/// 把全量事实聚成进步列表：**一个动作一行**，按「最近练过」倒序。
///
/// 分组一律走 [buildSessionPoints] —— 「一场 = 一个点」的口径只有那一份实现。
/// 传**全量**进来即可：它的分组键是 `(exerciseId, sessionId)`，一次长出所有
/// 动作的点，这里再按 `SessionPoint.exerciseId` 分桶。**不要**自己先按动作
/// 过滤再逐个调用 —— 过滤条件漏一个字段不会报错，只会让某个动作的曲线
/// 悄悄混进别的动作的数字。
List<ExerciseProgressRow> buildProgressIndex(List<SetFact> facts) {
  // 每个桶里的点已按时间升序（buildSessionPoints 的承诺），这里只做分桶
  final byExercise = <String, List<SessionPoint>>{};
  for (final point in buildSessionPoints(facts)) {
    (byExercise[point.exerciseId] ??= []).add(point);
  }

  return [for (final entry in byExercise.entries) _row(entry.key, entry.value)]
    ..sort(_byLastTrainedDesc);
}

/// 最近练过的在前；并列时按 `exerciseId` 兜底。
///
/// 并列不是罕见情况：同一场里练了两个动作，它们的 [ExerciseProgressRow.lastTrainedAt]
/// 必然相同。不写兜底，并列时谁在前就只剩两个说不清的来源 ——
/// `buildSessionPoints` 按 `sessionId` 排出来的分桶顺序，以及 Dart 的 `sort`
/// （它**不保证稳定**）。两个来源都跟「动作」没关系，行序却会随新数据变。
/// 兜底只为确定性，不为语义。
int _byLastTrainedDesc(ExerciseProgressRow a, ExerciseProgressRow b) {
  final byTime = b.lastTrainedAt.compareTo(a.lastTrainedAt);
  return byTime != 0 ? byTime : a.exerciseId.compareTo(b.exerciseId);
}

/// 一个动作的行。`points` 按时间升序且非空 —— 桶由事实长出，没练过就长不出桶。
ExerciseProgressRow _row(String exerciseId, List<SessionPoint> points) {
  final latest = points.last;
  return ExerciseProgressRow(
    exerciseId: exerciseId,
    lastTrainedAt: latest.startedAt,
    topWeight: latest.topWeight,
    topWeightReps: latest.topWeightReps,
    // 取尾巴：数组本来就是升序，reverse 再记一次方向只会多一处看错的机会
    recent: points.length <= recentPointCount
        ? points
        : points.sublist(points.length - recentPointCount),
  );
}
