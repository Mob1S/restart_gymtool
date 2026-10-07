import 'types.dart';

/// 超过这个时长的休息，认定为「忘了按开始下一组」，而不是真实休息。
///
/// 30 分钟是刻意宽松的阈值：力量训练的组间休息极少超过 10 分钟，留三倍余量
/// 是为了绝不误伤一次真实的长时间休息（比如中途接了个电话）。它要挡掉的是
/// 另一种情况 —— 做完一组直接关掉 App 走了，第二天打开看到
/// 「组间休息 14:23:00」。
const int staleRestThresholdMs = 30 * 60 * 1000;

/// 这段休息是否已经跑过头。[restStartedAt] 为 null 表示当前没在休息。
bool isStaleRest(int? restStartedAt, int now) {
  if (restStartedAt == null) return false;
  return now - restStartedAt > staleRestThresholdMs;
}

/// 从一组记录里找出那段已经跑过头的休息。
///
/// 返回 null 表示：没有正在进行的休息，或正在进行的这段还算新鲜 ——
/// 两种情况调用方都应该什么都不做。
SetEntry? findStaleRest(List<SetEntry> sets, int now) {
  for (final s in sets) {
    if (s.isCompleted && isStaleRest(s.restStartedAt, now)) return s;
  }
  return null;
}
