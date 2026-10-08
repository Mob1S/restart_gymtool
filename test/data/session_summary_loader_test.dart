import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/session_summary_loader.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';

/// 本文件走**真实的记录路径**（`addSet` → `completeSet`，占位组就是没调
/// `completeSet` 的那条），不像 `session_summary_list_test` 那样手工 INSERT ——
/// 装载函数读的正是这些仓储写出来的行，「预建占位组」这个约定由 [addSet] 落实。
void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e2', '卧推', 0, 0, 1)",
    );
  });

  tearDown(() async => exec.close());

  // ⭐ 这个 Task 的全部意义就在这条：总结页与历史详情**共用同一份计算**。
  // 3 组刻意分在**两个动作**上 —— 「只累加第一个动作的组」那种写法会在这里红，
  // 而那正是两个屏幕各算各的之后最容易长出来的偏差。
  test('⭐ 与 Phase 1 总结页同一个口径：3 组 122.5 × 12', () async {
    final s = await createSession(exec, name: '推日', templateId: null);
    final squat = await addExerciseToSession(exec, s.id, 'e1');
    final bench = await addExerciseToSession(exec, s.id, 'e2');

    for (var i = 0; i < 2; i++) {
      final set = await addSet(exec, squat.id, 122.5, 12);
      await completeSet(exec, set.id, 1000 + i);
    }
    final third = await addSet(exec, bench.id, 122.5, 12);
    await completeSet(exec, third.id, 2000);
    await finishSession(exec, s.id, s.startedAt + 90600);

    final summary = await loadSessionSummary(exec, s.id);

    expect(summary, isNotNull);
    final loaded = summary!;
    expect(loaded.session.id, s.id);
    expect(loaded.totalSets, 3);
    // 122.5 刻意带小数：先把重量 round 成 123 再乘，这里会变成 4428
    expect(loaded.volumeLoad, closeTo(4410, 0.001));
    expect(loaded.exercises.map((e) => e.exerciseName).toList(), [
      '深蹲',
      '卧推',
    ], reason: '顺序按 position —— 总结页的动作卡片就是这个先后');
    expect(loaded.exercises.map((e) => e.sets.length).toList(), [2, 1]);
    // 90.6 秒 → 四舍五入到秒；写成截断（90）或除错数量级都会红
    expect(loaded.durationSeconds, 91);
  });

  // ⭐ 空动作不上总结页：做过组才算练了。加了卧推却一组没做，
  // 卡片上多一张「卧推 · 组数不足 3 组，暂不判断」是噪音，不是记录。
  test('一组都没做的动作不进 exercises（容量与组数也不算它）', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final squat = await addExerciseToSession(exec, s.id, 'e1');
    final bench = await addExerciseToSession(exec, s.id, 'e2');

    final done = await addSet(exec, squat.id, 20, 8);
    await completeSet(exec, done.id, 1000);
    await addSet(exec, bench.id, 60, 5); // 占位组：从没完成
    await finishSession(exec, s.id, s.startedAt + 1000);

    final summary = await loadSessionSummary(exec, s.id);

    expect(summary, isNotNull);
    final loaded = summary!;
    expect(loaded.exercises.map((e) => e.exerciseName).toList(), ['深蹲']);
    expect(loaded.totalSets, 1);
    expect(loaded.volumeLoad, closeTo(160, 0.001));
  });

  test('不存在的 sessionId 返回 null，不抛', () async {
    expect(await loadSessionSummary(exec, '没有这一场'), isNull);
  });

  // ⭐ 进行中的训练也能装载。总结页正常不会走到这一支（它排在「结束」之后），
  // 但 `endWorkout` 是先清内存再跳页的 —— 时长按「现在」算才不会在这里断。
  test('进行中的训练：finishedAt 为空，时长按「现在」算', () async {
    final s = await createSession(exec, name: '进行中', templateId: null);
    // 开始时间挪到 10 分钟前，**不 sleep**：手写时间戳，让「现在 − started_at」
    // 成为确定的量级
    final startedAt = DateTime.now().millisecondsSinceEpoch - 600000;
    await exec.run('UPDATE session SET started_at = ? WHERE id = ?', [
      startedAt,
      s.id,
    ]);
    final se = await addExerciseToSession(exec, s.id, 'e1');
    final set = await addSet(exec, se.id, 20, 8);
    await completeSet(exec, set.id, startedAt + 60000);

    final summary = await loadSessionSummary(exec, s.id);

    expect(summary, isNotNull);
    final loaded = summary!;
    expect(loaded.session.finishedAt, isNull, reason: '前提：这场还没结束');
    // 没有 finishedAt 就取「现在」—— 10 分钟那头刚过，所以 ≥ 600 且不会远走；
    // 若写成 0 或抛异常，这两条都接得住
    expect(loaded.durationSeconds, greaterThanOrEqualTo(600));
    expect(loaded.durationSeconds, lessThan(660));
    expect(loaded.totalSets, 1);
  });

  // ⭐ 占位组（`is_completed = 0`）不是训练记录：它是记录界面为「下一组」预建的
  // 坑位，重量 999 × 99 是故意填的显眼数 —— 混进来一眼就能看出来。
  test('⭐ 占位组不进组数与容量（999 × 99 一个字都不能进来）', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final se = await addExerciseToSession(exec, s.id, 'e1');
    final done = await addSet(exec, se.id, 20, 8);
    await completeSet(exec, done.id, 1000);
    await addSet(exec, se.id, 999, 99); // 未完成
    await finishSession(exec, s.id, s.startedAt + 1000);

    final summary = await loadSessionSummary(exec, s.id);

    expect(summary, isNotNull);
    final loaded = summary!;
    expect(loaded.totalSets, 1);
    expect(loaded.volumeLoad, closeTo(160, 0.001), reason: '999 × 99 是坑位，不是记录');
    expect(loaded.exercises.single.sets, hasLength(1));
  });

  // ⭐ 补上来的守卫（计划里没有）。「忘了按 session 过滤」是一类不报错、不崩、
  // 只是数字悄悄变成两场之和的错，两条用例各自装一场才照得到。
  test('只装这一场的组，别场的数字不串进来', () async {
    final a = await createSession(exec, name: 'A', templateId: null);
    final seA = await addExerciseToSession(exec, a.id, 'e1');
    final setA = await addSet(exec, seA.id, 20, 8);
    await completeSet(exec, setA.id, 1000);
    await finishSession(exec, a.id, a.startedAt + 60000);

    final b = await createSession(exec, name: 'B', templateId: null);
    final seB = await addExerciseToSession(exec, b.id, 'e1');
    final setB = await addSet(exec, seB.id, 100, 10);
    await completeSet(exec, setB.id, 2000);
    await finishSession(exec, b.id, b.startedAt + 60000);

    final summaryA = await loadSessionSummary(exec, a.id);

    expect(summaryA, isNotNull);
    final loaded = summaryA!;
    expect(loaded.session.name, 'A');
    expect(loaded.totalSets, 1, reason: 'B 场的组串进来就会变成 2');
    expect(loaded.volumeLoad, closeTo(160, 0.001));
  });
}
