import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/progress.dart';
import 'package:gym_tracker/domain/progress_index.dart';

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

/// 把一个点摊成一条列表，用于与 [buildSessionPoints] 的输出逐字段对照。
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
  group('buildProgressIndex', () {
    test('1. 按最近练过倒序：后练的排在先练的前面', () {
      // 输入故意按时间正序给：实现若原样返回输入、或排序方向写反，这条都会红
      final rows = buildProgressIndex([
        f(50, 5, exercise: 'A', session: 'sa', startedAt: 100),
        f(50, 5, exercise: 'B', session: 'sb', startedAt: 200),
      ]);

      expect(rows.map((r) => r.exerciseId), ['B', 'A']);
      expect(rows.first.lastTrainedAt, 200);
      expect(rows.last.lastTrainedAt, 100);
    });

    test('2. 一个动作两场 → 一行（按动作分组，不是按场分行）', () {
      final rows = buildProgressIndex([
        f(60, 5, exercise: 'A', session: 'sa1', startedAt: 100),
        f(60, 5, exercise: 'A', session: 'sa2', startedAt: 200),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.exerciseId, 'A');
      expect(rows.single.recent.map((p) => p.sessionId), ['sa1', 'sa2']);
    });

    test('3. recent 取最近 12 个点（挤掉最早的 3 场），且按时间升序', () {
      final rows = buildProgressIndex([
        for (var i = 1; i <= 15; i++)
          f(60, 5, session: 's$i', startedAt: i * 100),
      ]);

      final recent = rows.single.recent;
      expect(recent, hasLength(12));
      expect(recent.map((p) => p.startedAt), [
        400,
        500,
        600,
        700,
        800,
        900,
        1000,
        1100,
        1200,
        1300,
        1400,
        1500,
      ], reason: '应当是尾部 12 场（s4…s15）、左旧右新；取头部或倒序都会在这里露出来');
      expect(recent.first.sessionId, 's4');
      expect(recent.last.sessionId, 's15');
    });

    test('4. 复用 buildSessionPoints：同一场两个动作各算各的，不合并', () {
      final facts = [
        f(60, 10, exercise: '卧推', session: 's1', startedAt: 1000),
        f(70, 3, exercise: '卧推', session: 's1', startedAt: 1000),
        f(100, 5, exercise: '深蹲', session: 's1', startedAt: 1000),
      ];
      final rows = buildProgressIndex(facts);
      expect(rows, hasLength(2), reason: '一场里两个动作必须长出两行');

      final bench = rows.singleWhere((r) => r.exerciseId == '卧推');
      final p = bench.recent.single;
      expect(p.volumeLoad, 60 * 10 + 70 * 3);
      expect(p.topWeight, 70);
      // 分组一旦自己重写一遍，很容易写成「取最重那组的 e1RM」：
      // 70×3 的 76.42 会顶掉 60×10 的 78.51，数字是错的却不报错
      expect(p.bestE1rm, closeTo(78.51, 0.01));
      expect(p.e1rmWeight, 60);
      expect(
        bench.recent.map(shape).toList(),
        buildSessionPoints(facts)
            .where((q) => q.exerciseId == '卧推')
            .map(shape)
            .toList(),
        reason: '进步页的点必须与 Task 1 同输入下的一模一样：口径分叉时两边各自自洽，只有对照能发现',
      );

      final squat = rows.singleWhere((r) => r.exerciseId == '深蹲');
      expect(
        squat.recent.single.volumeLoad,
        100 * 5,
        reason: '深蹲的 500 不该混进卧推的点',
      );
      expect(squat.topWeight, 100, reason: '卧推的 70 不该混进深蹲的点');
    });

    test('5. topWeight / lastTrainedAt 取最近那一次，不是历史最好成绩', () {
      final row = buildProgressIndex([
        f(100, 1, session: 'old', startedAt: 100),
        f(60, 8, session: 'new', startedAt: 900),
      ]).single;

      expect(row.lastTrainedAt, 900);
      // 行上写的是「最近 9/10 · 最重 60 kg」：两个数必须同一天。
      // 取历史最大值会显示成「最近 9/10 · 最重 100 kg」——日期与数字对不上
      expect(row.topWeight, 60);
      expect(row.topWeightReps, 8);
      expect(row.recent.map((p) => p.topWeight), [100, 60]);
    });

    test('6. 最近一场并列（同一场练了两个动作）→ 行序按 exerciseId 兜底', () {
      // 两行的 lastTrainedAt 相同（同一场），但 sessionId 故意与动作 id 反着排：
      // A 最近是 'sz'、B 是 'sa'。分桶顺序由 buildSessionPoints 的 sessionId
      // 兜底决定（'sa' 在前），行序若照抄它就成了 B、A —— 那条路与「动作」
      // 毫无关系，换个场次的 id 行序就会跳。并列时行序只能有一个来源。
      // （sessionId 顺着排时两种写法恰好同序 —— 那样的断言是个永远绿的假守卫。）
      final facts = [
        f(50, 5, exercise: 'A', session: 'sz', startedAt: 1000),
        f(60, 5, exercise: 'B', session: 'sa', startedAt: 1000),
      ];

      expect(buildProgressIndex(facts).map((r) => r.exerciseId), ['A', 'B']);
      expect(
        buildProgressIndex(facts.reversed.toList()).map((r) => r.exerciseId),
        ['A', 'B'],
        reason: '换一次输入顺序行序就变的话，列表会莫名其妙地跳',
      );
    });

    test('7. 没有事实 → 空表，不是异常', () {
      expect(buildProgressIndex([]), isEmpty);
    });
  });
}
