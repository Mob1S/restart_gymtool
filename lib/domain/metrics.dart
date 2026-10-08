import 'dart:math' as math;

import 'types.dart';

/// 容量负荷（volume load）= Σ(重量 × 次数)，**只累加已完成的组**。
///
/// 注意：文献中 "volume" 一词口径不统一（有的指总次数，有的指组数×次数）。
/// 本 App 一律采用含重量的 volume load 口径，命名上也必须叫 volumeLoad
/// 而不是 volume。
double totalVolumeLoad(List<SetLike> sets) {
  var sum = 0.0;
  for (final s in sets) {
    if (s.isCompleted) sum += s.weight * s.reps;
  }
  return sum;
}

/// 估算 1RM（e1RM）。
///
/// 采用三种经典公式的算术平均，以降低单一公式的偏差 —— 同一组数据这三个
/// 公式会给出不同结果，没有任何一个被公认最准。
///
/// 适用范围：仅当 `2 <= reps <= 10` 时有效。次数 > 10 时外推严重失真，
/// 返回 null，**调用方必须不显示该值**。`reps == 1` 时直接返回实测重量。
///
/// **公式一旦确定不得更改** —— 换了公式，进步页的历史曲线会出现无解释的
/// 断层。因此公式只有这一份实现，别处一律调用它，不重写。
///
/// 返回 null 时**不能当 0 处理** —— 0 会被读成「练得很差」，
/// 而事实是「这一组不适合换算」。
double? estimateOneRepMax(double weight, int reps) {
  if (reps < 1) return null;
  if (reps == 1) return weight;
  if (reps > 10) return null;

  final epley = weight * (1 + reps / 30);
  final brzycki = (weight * 36) / (37 - reps);
  final lombardi = weight * math.pow(reps, 0.1);

  return (epley + brzycki + lombardi) / 3;
}

/// 一场训练的时长（秒）。
///
/// **口径只有这一份实现。** 历史列表行（`SessionSummaryRow`）、历史详情页与
/// 总结页（`SessionSummary`）都要显示时长 —— 三处各写一遍的话，
/// `round()` 与 `~/` 的差别会让同一场训练在列表上显示 2 分钟、在详情页显示
/// 1 分钟，而用户没有任何办法判断哪个对。
///
/// 用 `round()` 而不是截断：90.6 秒更接近 2 分钟而不是 1 分钟。
/// 这不是精度问题，是**四舍五入的方向**，所以必须由一处说了算。
///
/// `finishedAt` 由调用方传入而不是从 `WorkoutSession` 里取 —— 进行中的训练
/// 没有结束时间，调用方要用「现在」兜底（总结页与历史详情页共用这份计算，
/// 但只有前者可能碰到进行中的训练）。
int sessionDurationSeconds(int startedAt, int finishedAt) =>
    ((finishedAt - startedAt) / 1000).round();
