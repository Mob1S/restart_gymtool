import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/rest_advice.dart';

void main() {
  test('组数少于 3 时明确沉默，不给任何提示', () {
    expect(buildRestFeedback([8, 8], [90, null]), isNull);
    expect(buildRestFeedback([], []), isNull);
    expect(buildRestFeedback([8], [null]), isNull);
  });

  test('全程稳定且休息不长 → 正反馈', () {
    final f = buildRestFeedback([5, 5, 5, 5], [90, 90, 90, null])!;
    expect(f.kind, RestFeedbackKind.positive);
    expect(f.drop, 0);
    expect(f.message, contains('5 / 5 / 5 / 5'));
    expect(f.message, contains('节奏合适'));
  });

  test('全程稳定但平均休息 > 180 秒 → 加重提示（不是缩短休息）', () {
    final f = buildRestFeedback([5, 5, 5], [200, 200, null])!;
    expect(f.kind, RestFeedbackKind.addWeight);
    expect(f.message, contains('还有余力，可以考虑加重量'));
    expect(f.message, contains('3 分 20 秒'));
  });

  test('平均休息刚好 180 秒不算长（边界是不含）', () {
    final f = buildRestFeedback([6, 6, 6], [180, 180, null])!;
    expect(f.kind, RestFeedbackKind.positive);
  });

  test('末组掉 1 次 → 多歇 15 秒', () {
    final f = buildRestFeedback([5, 5, 4], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend15);
    expect(f.message, contains('末组 5 → 4'));
    expect(f.message, contains('15 秒'));
  });

  test('末组掉 2 次 → 多歇 30 秒', () {
    final f = buildRestFeedback([5, 5, 3], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend30);
    expect(f.message, contains('30 秒'));
  });

  test('末组掉 3 次以上 → 多歇 30 秒 + 归因提示', () {
    final f = buildRestFeedback([5, 5, 2], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend30CheckWeight);
    expect(f.message, contains('可能是重量偏大'));
  });

  test('次数递增（drop < 0）按 drop <= 0 处理，也是正反馈', () {
    final f = buildRestFeedback([5, 6, 7], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.positive);
    expect(f.drop, -2);
  });

  test('一条休息数据都没有时 avgRest 为 null，不能当成 0', () {
    final f = buildRestFeedback([5, 5, 5], [null, null, null])!;
    expect(f.avgRest, isNull);
    // 若把 null 当成 0，会走进「歇得很短」从而误判 —— 这里必须是正反馈
    expect(f.kind, RestFeedbackKind.positive);
  });

  test('次数数组原样返回，供界面核对', () {
    final f = buildRestFeedback([12, 10, 9], [60, 60, null])!;
    expect(f.reps, [12, 10, 9]);
    // drop >= 3 分支的文案按规格 §4.3 是「末组 {first} → {last}…」，
    // 不含整串次数数组 —— 那一行由总结页自己渲染（计划 Task 13 的卡片首行）。
    // 这里锁的是「文案里的首末次数与原始数组一致」。
    expect(f.message, contains('末组 12 → 9'));
  });
}
