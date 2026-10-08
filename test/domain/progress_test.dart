import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/progress.dart';

/// 造一条已完成组的事实；默认同一场（s1）、同一动作（e1）。
SetFact f(
  double weight,
  int reps, {
  String session = 's1',
  int startedAt = 1000,
  String exercise = 'e1',
}) => SetFact(
  exerciseId: exercise,
  sessionId: session,
  sessionStartedAt: startedAt,
  weight: weight,
  reps: reps,
);

/// 把一个点摊成一条列表，用于「两种输入顺序结果完全相同」那种整体对比。
/// `SessionPoint` 没有 `==`（沿用 types.dart 里值对象不重写 `==` 的习惯）。
List<Object?> shape(SessionPoint p) => [
  p.exerciseId,
  p.sessionId,
  p.startedAt,
  p.topWeight,
  p.topWeightReps,
  p.bestE1rm,
  p.e1rmWeight,
  p.e1rmReps,
  p.volumeLoad,
];

void main() {
  group('buildSessionPoints', () {
    test('1. 一次训练 = 一个点：同一场 3 组聚成一个', () {
      final points = buildSessionPoints([f(60, 10), f(60, 8), f(60, 6)]);

      expect(points, hasLength(1));
      // 每组各算各的会得到 3 个点；聚成一个点时容量是三组之和
      expect(points.single.volumeLoad, 60 * 10 + 60 * 8 + 60 * 6);
    });

    test('2. 最佳 e1RM 不来自最重的那组', () {
      // 60×10 的 e1RM 78.51 高于 70×3 的 76.42，尽管 70 更重（规格 §2.1）。
      // 实现写成「取最重那组的 e1RM」时，这条必须红。
      final points = buildSessionPoints([f(60, 10), f(70, 3)]);
      final p = points.single;

      expect(p.topWeight, 70);
      expect(p.topWeightReps, 3);
      expect(p.bestE1rm, closeTo(78.51, 0.01));
      expect(p.e1rmWeight, 60);
      expect(p.e1rmReps, 10);
    });

    test('3. 最大重量并列 → 取次数多的那一组', () {
      final points = buildSessionPoints([f(60, 5), f(60, 8)]);

      expect(points.single.topWeight, 60);
      expect(points.single.topWeightReps, 8);
    });

    test('4. 所有组次数都 > 10 → 该场没有 e1RM（不补 0、不补估算）', () {
      final points = buildSessionPoints([f(60, 12), f(55, 15)]);
      final p = points.single;

      expect(p.bestE1rm, isNull);
      expect(p.e1rmWeight, isNull);
      expect(p.e1rmReps, isNull);
      // 没有 e1RM 不影响其余几项照常算
      expect(p.topWeight, 60);
      expect(p.volumeLoad, 60 * 12 + 55 * 15);
    });

    test('5. reps == 1 → 用实测重量当 e1RM', () {
      final p = buildSessionPoints([f(100, 1)]).single;

      expect(p.bestE1rm, 100);
      expect(p.e1rmWeight, 100);
      expect(p.e1rmReps, 1);
    });

    test('6. 输入乱序 → 结果与有序时完全相同', () {
      final ordered = [
        f(60, 10, session: 'a', startedAt: 100),
        f(70, 3, session: 'a', startedAt: 100),
        f(40, 12, session: 'b', startedAt: 300),
        f(80, 2, session: 'b', startedAt: 300),
        f(50, 5, session: 'c', startedAt: 200),
      ];
      // 一个固定的乱序，不用 Random —— 红了的时候要能原样复现
      final shuffled = [
        ordered[3],
        ordered[0],
        ordered[4],
        ordered[2],
        ordered[1],
      ];

      expect(
        buildSessionPoints(shuffled).map(shape).toList(),
        buildSessionPoints(ordered).map(shape).toList(),
      );
    });

    test('7. 多场按 startedAt 升序（输入是乱序的）', () {
      final points = buildSessionPoints([
        f(50, 5, session: 'c', startedAt: 3000),
        f(50, 5, session: 'a', startedAt: 1000),
        f(50, 5, session: 'b', startedAt: 2000),
      ]);

      expect(points.map((p) => p.startedAt), [1000, 2000, 3000]);
      expect(points.map((p) => p.sessionId), ['a', 'b', 'c']);
    });

    test('8. 容量只累加该场：两场的 volumeLoad 不串', () {
      final points = buildSessionPoints([
        f(20, 8, session: 'a', startedAt: 100),
        f(100, 5, session: 'b', startedAt: 200),
      ]);

      expect(points[0].volumeLoad, 20 * 8);
      expect(points[1].volumeLoad, 100 * 5);
    });

    test('9. 同一时刻开的两场按 sessionId 兜底，不随输入顺序变', () {
      final forward = buildSessionPoints([
        f(50, 5, session: 'a', startedAt: 1000),
        f(60, 5, session: 'b', startedAt: 1000),
      ]);
      final backward = buildSessionPoints([
        f(60, 5, session: 'b', startedAt: 1000),
        f(50, 5, session: 'a', startedAt: 1000),
      ]);

      expect(forward.map((p) => p.sessionId), ['a', 'b']);
      expect(backward.map((p) => p.sessionId), ['a', 'b']);
    });

    test('10. 没有事实 → 空表，不是异常', () {
      expect(buildSessionPoints([]), isEmpty);
    });

    test('⭐ 11. 同一场两个动作 → 两个点，绝不合并', () {
      // 这一条守的是「忘了先按动作过滤」那条错路。
      // 分组键若只有 sessionId，下面这 4 条事实会聚成 **1** 个点：
      // 卧推和深蹲混在一起，topWeight 取到两个动作里的最大值 ——
      // 数字是错的，但不报错、不崩，只是曲线悄悄变成一条没有意义的线。
      // 加上 exerciseId 之后传进来多少动作就长出多少点。
      final points = buildSessionPoints([
        f(60, 10, session: 's1', startedAt: 1000, exercise: '卧推'),
        f(60, 8, session: 's1', startedAt: 1000, exercise: '卧推'),
        f(100, 5, session: 's1', startedAt: 1000, exercise: '深蹲'),
        f(100, 4, session: 's1', startedAt: 1000, exercise: '深蹲'),
      ]);

      expect(points, hasLength(2), reason: '一场里两个动作必须长出两个点');
      expect(points.map((p) => p.exerciseId), ['卧推', '深蹲']);

      final bench = points.first;
      expect(bench.topWeight, 60, reason: '深蹲的 100kg 不该混进卧推的点');
      expect(bench.volumeLoad, 60 * 10 + 60 * 8);
    });
  });
}
