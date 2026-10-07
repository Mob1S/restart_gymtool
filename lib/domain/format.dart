/// 下标即 `DateTime.weekday` 的返回值：1 = 周一 …… 7 = 周日。
const List<String> _weekdayLabels = [
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// `9月16日 周三`。
///
/// 全程用本地时区的 getter，不用 `intl` 的 locale 格式化 —— 同一份代码在不同
/// 地区设置下会排出不同格式，是那种只在别人机器上复现的 bug。
/// 月和日**不补零**（中文习惯）。
String formatDate(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.month}月${d.day}日 ${_weekdayLabels[d.weekday]}';
}

/// `09:05`（24 小时制）—— 必须补零，否则 9 点 5 分会写成 `9:5`。
String formatTime(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 训练是什么时候开始的：`今天 15:20` / `昨天 19:30` / `9月16日 19:30`。
///
/// 「今天 / 昨天」是为了让用户一眼认出主页那个「继续」按钮说的是哪一场 ——
/// 他打开 App 时心里想的正是「这是刚才那场，还是昨天那场」。
///
/// [now] 显式传入是为了可测：不传就用真实时间。
String formatDateTime(int timestamp, [int? now]) {
  final reference = now ?? DateTime.now().millisecondsSinceEpoch;
  final days = _calendarDaysBetween(reference, timestamp);
  if (days == 0) return '今天 ${formatTime(timestamp)}';
  if (days == 1) return '昨天 ${formatTime(timestamp)}';
  // 去掉 formatDate 末尾的星期 —— 这里已经有时间了，再加星期会把句子撑长
  return '${formatDate(timestamp).split(' ').first} ${formatTime(timestamp)}';
}

/// 按「日历天」算差，而不是按 24 小时。
///
/// 23:50 练完、次日 00:10 打开 App，两者只差 20 分钟但确实跨了一天，
/// 那时说「昨天」才对。做法是把两个时间戳都抹到当天零点再相减。
int _calendarDaysBetween(int now, int then) {
  final a = DateTime.fromMillisecondsSinceEpoch(now);
  final b = DateTime.fromMillisecondsSinceEpoch(then);
  final startOfA = DateTime(a.year, a.month, a.day).millisecondsSinceEpoch;
  final startOfB = DateTime(b.year, b.month, b.day).millisecondsSinceEpoch;
  return ((startOfA - startOfB) / 86400000).round();
}

/// 休息计时用的钟面：`12:34`（分:秒），超过一小时进位到 `65:20` 形式。
///
/// 与 [formatDuration] 分工不同：那个是总结页里的人话，这个是**一直在跳动的
/// 数字**，必须是等宽、等长、不换行，所以不带任何单位字。
String formatClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 总结页里的人话时长：`45 秒` / `1 分 05 秒` / `1 小时 2 分`。
String formatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  if (safe < 60) return '$safe 秒';

  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;

  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分 ${secs.toString().padLeft(2, '0')} 秒';
}
