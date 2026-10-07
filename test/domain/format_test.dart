import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/format.dart';

void main() {
  // 全部用**显式固定**的时间戳构造，不依赖真实时钟 ——
  // 旧项目有一条赌时钟的测试实测 20 次闪 2 次，那种测试比没有更危险。
  final wed = DateTime(2024, 9, 16, 19, 30).millisecondsSinceEpoch;

  test('formatDate 用本地时区，月和日不补零', () {
    expect(formatDate(wed), '9月16日 周一');
  });

  test('formatTime 必须补零，否则 9 点 5 分会写成 9:5', () {
    final t = DateTime(2024, 1, 5, 9, 5).millisecondsSinceEpoch;
    expect(formatTime(t), '09:05');
  });

  test('formatDateTime —— 同一天说「今天」', () {
    final now = DateTime(2024, 9, 16, 21, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '今天 19:30');
  });

  test('formatDateTime —— 差一天说「昨天」', () {
    final now = DateTime(2024, 9, 17, 8, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '昨天 19:30');
  });

  test('formatDateTime —— 更早用日期，不带星期', () {
    final now = DateTime(2024, 9, 20, 8, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '9月16日 19:30');
  });

  test('跨天按日历天算，不按 24 小时 —— 23:50 练完、次日 00:10 打开说「昨天」', () {
    final before = DateTime(2024, 9, 16, 23, 50).millisecondsSinceEpoch;
    final after = DateTime(2024, 9, 17, 0, 10).millisecondsSinceEpoch;
    expect(formatDateTime(before, after), '昨天 23:50');
  });

  test('formatDuration —— 不足 1 分钟只说秒', () {
    expect(formatDuration(45), '45 秒');
  });

  test('formatDuration —— 分秒都要，秒补零', () {
    expect(formatDuration(65), '1 分 05 秒');
  });

  test('formatDuration —— 超过 1 小时带小时', () {
    expect(formatDuration(3725), '1 小时 2 分');
  });

  // formatClock 是休息界面那个一直在跳的钟面。计划初版漏了它的测试，
  // 但计划自己的注里写明它「是纯函数且必须可单测（00:00 与进位是边界）」。

  test('formatClock —— 零点显示 00:00，不能是 0:0', () {
    expect(formatClock(0), '00:00');
  });

  test('formatClock —— 分秒都补零', () {
    expect(formatClock(65), '01:05');
    expect(formatClock(59), '00:59');
  });

  test('formatClock —— 超过一小时不进位到小时，分继续累加（钟面不换行）', () {
    expect(formatClock(3920), '65:20');
  });

  test('formatClock —— 负数夹到 00:00（时钟回拨等异常不该显示负数）', () {
    expect(formatClock(-5), '00:00');
  });
}
