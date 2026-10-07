/// 建议的类型标签。界面若要按类型上色 / 配图标，认这个字段，
/// **不要去解析 [RestFeedback.message]** —— 文案改了类型还在，
/// 解析文案的代码会静默失效。
enum RestFeedbackKind {
  /// 次数没掉、休息也不长：保持现状
  positive,

  /// 次数没掉但休息偏长：还有余力
  addWeight,

  /// 末组只掉 1 次：多歇 15 秒
  extend15,

  /// 末组掉 2 次：多歇 30 秒
  extend30,

  /// 末组掉 3 次以上：多歇 30 秒，若还掉就说明重量偏大
  extend30CheckWeight,
}

/// 训练后给的一条组间休息建议，附带界面展示所需的全部原始数据。
class RestFeedback {
  final RestFeedbackKind kind;

  /// 原始次数数组。**界面必须原样展示**，让用户能自己核对 ——
  /// 只给结论不给原始数字，用户不会相信
  final List<int> reps;

  /// 首组次数 − 末组次数
  final int drop;

  /// 平均组后休息秒数；没有休息数据时为 null
  final double? avgRest;

  /// 已经拼好的人话，界面直接显示
  final String message;

  const RestFeedback({
    required this.kind,
    required this.reps,
    required this.drop,
    required this.avgRest,
    required this.message,
  });
}

/// 平均休息超过这个秒数，且次数没掉，就认为「还有余力」。
const int _longRestThresholdSeconds = 180;

/// 少于这个组数就不作判断。
const int _minSets = 3;

/// 各组的组后休息秒数，最后一组通常是 null（它是最后一组，没有「组后休息」）。
///
/// 一条数据都没有时返回 **null 而不是 0** —— 0 会被后面判成「歇得很短」，
/// 从而给出错误的「加重量」建议。
double? _averageRest(List<int?> rests) {
  var sum = 0;
  var n = 0;
  for (final r in rests) {
    if (r != null) {
      sum += r;
      n++;
    }
  }
  return n == 0 ? null : sum / n;
}

/// 生成训练后的组间休息提示。
///
/// 这是**粗略参考**，不是科学结论：只比较本次训练内首组与末组的次数差异，
/// 不跨训练推断、不建统计模型。该领域文献本身对最优休息时长没有共识，
/// 且同一个人不同训练日的反应差异明显。
///
/// **必须包含正反馈分支** —— 只挑毛病、从不肯定，用两周就会被无视。
///
/// 组数少于 3 时返回 null：数据不足时明确沉默，不硬给建议。
RestFeedback? buildRestFeedback(List<int> reps, List<int?> rests) {
  if (reps.length < _minSets) return null;

  final first = reps.first;
  final last = reps.last;
  final drop = first - last;
  final avgRest = _averageRest(rests);
  final list = reps.join(' / ');
  final restText = avgRest?.round();

  if (drop <= 0) {
    if (restText != null && restText > _longRestThresholdSeconds) {
      final minutes = restText ~/ 60;
      final seconds = restText % 60;
      return RestFeedback(
        kind: RestFeedbackKind.addWeight,
        reps: reps,
        drop: drop,
        avgRest: avgRest,
        message: '$list 全程稳定，平均歇了 $minutes 分 $seconds 秒 —— 还有余力，可以考虑加重量',
      );
    }
    return RestFeedback(
      kind: RestFeedbackKind.positive,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '$list 全程稳住了，节奏合适',
    );
  }

  if (drop == 1) {
    return RestFeedback(
      kind: RestFeedbackKind.extend15,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '末组 $first → $last，下次这个动作可以多歇 15 秒',
    );
  }

  if (drop == 2) {
    return RestFeedback(
      kind: RestFeedbackKind.extend30,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '末组 $first → $last，下次可以多歇 30 秒',
    );
  }

  return RestFeedback(
    kind: RestFeedbackKind.extend30CheckWeight,
    reps: reps,
    drop: drop,
    avgRest: avgRest,
    message: '末组 $first → $last，多歇 30 秒试试；如果还是掉，可能是重量偏大',
  );
}
